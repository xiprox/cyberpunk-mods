#include "net/link.hpp"

#include <juice/juice.h>

#include <cstring>

namespace nv
{
namespace
{
struct StunServer
{
    const char* host;
    uint16_t port;
};
constexpr StunServer kStunServers[] = {
    {"stun.l.google.com", 19302},
    {"stun.cloudflare.com", 3478},
};

const char* StateName(juice_state_t aState)
{
    switch (aState)
    {
    case JUICE_STATE_DISCONNECTED:
        return "disconnected";
    case JUICE_STATE_GATHERING:
        return "gathering";
    case JUICE_STATE_CONNECTING:
        return "connecting";
    case JUICE_STATE_CONNECTED:
        return "connected";
    case JUICE_STATE_COMPLETED:
        return "completed";
    case JUICE_STATE_FAILED:
        return "failed";
    default:
        return "unknown";
    }
}
} // namespace

Link::Link(PeerId aPeer, uint32_t aGeneration, bool aOfferer, int aStunIndex, LinkSink& aSink)
    : m_peer(aPeer)
    , m_generation(aGeneration)
    , m_offerer(aOfferer)
    , m_sink(aSink)
{
    // Warnings only: libjuice's chattier levels print addresses, and this log gets shared.
    juice_set_log_level(JUICE_LOG_LEVEL_WARN);
    juice_set_log_handler([](juice_log_level_t, const char* aMessage) { Logf(LogWarn, "libjuice: %s", aMessage); });

    const int servers = static_cast<int>(sizeof(kStunServers) / sizeof(kStunServers[0]));
    const StunServer& stun = kStunServers[aStunIndex % servers];

    juice_config_t config{};
    config.concurrency_mode = JUICE_CONCURRENCY_MODE_THREAD;
    config.stun_server_host = stun.host;
    config.stun_server_port = stun.port;
    config.cb_state_changed = reinterpret_cast<juice_cb_state_changed_t>(&Link::OnState);
    config.cb_candidate = reinterpret_cast<juice_cb_candidate_t>(&Link::OnCandidate);
    config.cb_gathering_done = reinterpret_cast<juice_cb_gathering_done_t>(&Link::OnGatheringDone);
    config.cb_recv = reinterpret_cast<juice_cb_recv_t>(&Link::OnReceive);
    config.user_ptr = this;

    m_agent = reinterpret_cast<juice_agent*>(juice_create(&config));
    if (!m_agent)
    {
        Logf(LogWarn, "link %u: could not create the agent", m_peer);
        m_state.store(LinkState::Failed);
    }
}

Link::~Link()
{
    if (m_agent)
    {
        juice_destroy(reinterpret_cast<juice_agent_t*>(m_agent));
    }
}

void Link::SendDescriptionAndGather()
{
    char description[JUICE_MAX_SDP_STRING_LEN];
    if (juice_get_local_description(reinterpret_cast<juice_agent_t*>(m_agent), description, sizeof(description)) != 0)
    {
        Logf(LogWarn, "link %u: no local description", m_peer);
        m_state.store(LinkState::Failed);
        return;
    }
    m_sink.LinkSignal(m_peer, SignalDescription, m_generation, description);
    if (!m_gathering)
    {
        m_gathering = true;
        juice_gather_candidates(reinterpret_cast<juice_agent_t*>(m_agent));
    }
}

bool Link::Start()
{
    if (!m_agent)
    {
        return false;
    }
    if (m_offerer)
    {
        SendDescriptionAndGather();
    }
    return true;
}

void Link::OnSignal(uint8_t aKind, const std::string& aText)
{
    if (!m_agent)
    {
        return;
    }
    auto* agent = reinterpret_cast<juice_agent_t*>(m_agent);
    switch (aKind)
    {
    case SignalDescription:
        if (juice_set_remote_description(agent, aText.c_str()) != 0)
        {
            Logf(LogWarn, "link %u: bad remote description", m_peer);
            m_state.store(LinkState::Failed);
            return;
        }
        if (!m_offerer)
        {
            SendDescriptionAndGather();
        }
        break;
    case SignalCandidate:
        juice_add_remote_candidate(agent, aText.c_str());
        break;
    case SignalGatheringDone:
        juice_set_remote_gathering_done(agent);
        break;
    default:
        break;
    }
}

bool Link::Send(const uint8_t* aData, size_t aSize)
{
    if (!m_agent || m_state.load() != LinkState::Connected)
    {
        return false;
    }
    return juice_send(reinterpret_cast<juice_agent_t*>(m_agent), reinterpret_cast<const char*>(aData), aSize) == 0;
}

std::string Link::PathKinds() const
{
    if (!m_agent)
    {
        return "unknown path";
    }
    const auto kind = [](const char* aCandidate) -> std::string {
        const char* type = std::strstr(aCandidate, " typ ");
        if (!type)
        {
            return "unknown";
        }
        std::string text = type + 5;
        return text.substr(0, text.find(' '));
    };
    char local[JUICE_MAX_CANDIDATE_SDP_STRING_LEN] = {};
    char remote[JUICE_MAX_CANDIDATE_SDP_STRING_LEN] = {};
    if (juice_get_selected_candidates(reinterpret_cast<juice_agent_t*>(m_agent), local, sizeof(local), remote,
                                      sizeof(remote)) != 0)
    {
        return "unknown path";
    }
    return kind(local) + " to " + kind(remote);
}

void Link::OnState(juice_agent*, int aState, void* aUser)
{
    auto* self = static_cast<Link*>(aUser);
    const auto state = static_cast<juice_state_t>(aState);
    Logf(LogTrace, "link %u gen %u: %s", self->m_peer, self->m_generation, StateName(state));
    switch (state)
    {
    case JUICE_STATE_CONNECTED:
    case JUICE_STATE_COMPLETED:
        self->m_state.store(LinkState::Connected);
        break;
    case JUICE_STATE_FAILED:
        self->m_state.store(LinkState::Failed);
        break;
    default:
        break;
    }
}

void Link::OnCandidate(juice_agent*, const char* aSdp, void* aUser)
{
    auto* self = static_cast<Link*>(aUser);
    self->m_sink.LinkSignal(self->m_peer, SignalCandidate, self->m_generation, aSdp);
}

void Link::OnGatheringDone(juice_agent*, void* aUser)
{
    auto* self = static_cast<Link*>(aUser);
    self->m_sink.LinkSignal(self->m_peer, SignalGatheringDone, self->m_generation, "");
}

void Link::OnReceive(juice_agent*, const char* aData, size_t aSize, void* aUser)
{
    auto* self = static_cast<Link*>(aUser);
    self->m_sink.LinkPacket(self->m_peer, reinterpret_cast<const uint8_t*>(aData), aSize);
}
} // namespace nv
