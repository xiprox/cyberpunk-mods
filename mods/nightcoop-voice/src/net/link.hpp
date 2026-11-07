// One direct UDP path to one player, found by hole punching (ICE, through libjuice). The two sides swap addresses over
// NightCoop's channel; after that audio goes straight between them.
#pragma once

#include "core/common.hpp"

#include <atomic>
#include <string>

struct juice_agent;

namespace nv
{
enum SignalKind : uint8_t
{
    SignalDescription = 1,
    SignalCandidate = 2,
    SignalGatheringDone = 3,
    SignalRestart = 4, // from the answering side: please start over with a new generation
};

enum class LinkState
{
    Connecting,
    Connected,
    Failed,
};

class LinkSink
{
public:
    virtual ~LinkSink() = default;
    // Text to pass to the other player's Link. Called from the link's own thread.
    virtual void LinkSignal(PeerId aPeer, uint8_t aKind, uint32_t aGeneration, const std::string& aText) = 0;
    // A datagram from the other player. Called from the link's own thread.
    virtual void LinkPacket(PeerId aPeer, const uint8_t* aData, size_t aSize) = 0;
};

class Link
{
public:
    // aOfferer: this side speaks first. aStunIndex picks the public STUN server, so retries can try another.
    Link(PeerId aPeer, uint32_t aGeneration, bool aOfferer, int aStunIndex, LinkSink& aSink);
    ~Link(); // waits for the link's thread, so don't call it while holding a lock its callbacks take

    Link(const Link&) = delete;
    Link& operator=(const Link&) = delete;

    bool Start();
    void OnSignal(uint8_t aKind, const std::string& aText);
    bool Send(const uint8_t* aData, size_t aSize);

    // How the path got through, for the log: "srflx to srflx" and so on, never an address.
    std::string PathKinds() const;

    LinkState State() const
    {
        return m_state.load();
    }
    uint32_t Generation() const
    {
        return m_generation;
    }

private:
    static void OnState(juice_agent* aAgent, int aState, void* aUser);
    static void OnCandidate(juice_agent* aAgent, const char* aSdp, void* aUser);
    static void OnGatheringDone(juice_agent* aAgent, void* aUser);
    static void OnReceive(juice_agent* aAgent, const char* aData, size_t aSize, void* aUser);

    void SendDescriptionAndGather();

    const PeerId m_peer;
    const uint32_t m_generation;
    const bool m_offerer;
    LinkSink& m_sink;
    juice_agent* m_agent = nullptr;
    bool m_gathering = false;
    std::atomic<LinkState> m_state{LinkState::Connecting};
};
} // namespace nv
