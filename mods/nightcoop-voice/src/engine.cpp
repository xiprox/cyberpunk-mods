#include "engine.hpp"

#include "audio/headset_link.hpp"
#include "audio/wasapi.hpp"

#include <pmmintrin.h>
#include <xmmintrin.h>

#include <algorithm>
#include <array>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>

namespace nv
{
namespace
{
constexpr double kConnectTimeoutMs = 25000.0;
constexpr double kSilentLinkMs = 8000.0;
constexpr double kPresenceEveryMs = 1000.0;
constexpr double kFirstRetryMs = 2000.0;
constexpr double kMaxRetryMs = 30000.0;
constexpr double kRestartAskEveryMs = 10000.0;
constexpr double kNoLinkNoteAfterMs = 30000.0;
constexpr double kAudioLingerMs = 10000.0;     // keeps the mic open through a quick reconnect
constexpr double kPositionFreshMs = 1500.0;
constexpr double kLevelsEveryMs = 30000.0;
constexpr float kHeardWorthLoggingSeconds = 0.5f;
constexpr float kAutoGainSaveStepDb = 1.f;
constexpr size_t kMaxSignalText = 4096;
constexpr size_t kMaxQueuedSignals = 512;
constexpr size_t kSignalHeader = 5;
// Presence: bits (0), our send time (1), the echo of theirs and how long we held it (5, 9), our room (13-15), and what's
// open on the car we sit in (16-21): its gone glass (4 bytes, by the car record's glass index), windows down and doors
// open (a nibble each), and whether it has no roof.
constexpr size_t kPresenceSize = 22;
constexpr double kTalkingRecentlyMs = 10000.0; // what's between you and a quiet player isn't worth many rays
constexpr float kPresenceRoomMeters = 40.f;    // the longest room a byte has to carry
constexpr float kPresenceRoomDecay = 6.f;
constexpr float kEchoOcclusion = 2.f;          // a wall in the way takes the bounces with it, well before the voice
constexpr float kEchoInOpenAir = 0.5f;         // a facade across a square gives back little, and the city's noise covers that
constexpr float kToneMs = 70.f;
constexpr float kToneVolume = 0.12f;
constexpr float kToneRadioOn = 1320.f;
constexpr float kToneRadioOff = 880.f;
constexpr float kToneMute = 440.f;
constexpr float kToneUnmute = 660.f;

// The Relay. A message is a 4-byte send time, then entries of a 2-byte size and one sealed packet.
constexpr size_t kRelayHeader = 4;
constexpr double kRelayFreshMs = 3000.0;        // presence comes once a second, so this long without any means it's down
constexpr double kRelayNoteAfterMs = 3000.0;    // a direct link at the start of a session is usually up well before
constexpr double kFrameMs = 20.0;
constexpr double kRelayFlushSlackMs = 25.0;     // past the frames a message waits for, the first one goes anyway
constexpr double kRelayMostWaitMs = 250.0;      // older than this, a queued frame is too late to be worth sending
constexpr double kRelayStaleMs = 500.0;         // this much later than the quickest recent message, a frame can't play
constexpr size_t kRelayMostQueued = 64;
constexpr int kRelayPartnersAtTwoFrames = 4;    // 25 messages a second each, out of NightCoop's 120
constexpr int kRelayMostFrames = 4;
constexpr double kRelayRaiseEveryMs = 1000.0;   // after a refusal for the rate, one more frame a message, at most this often
constexpr double kRelayEaseAfterMs = 10000.0;   // and one fewer after this long with none
constexpr double kRelayLogEveryMs = 30000.0;
constexpr double kRelayLimitLogEveryMs = 10000.0;
constexpr double kSeenForMs = 10000.0;          // a frame's sequence number counts as taken for this long
constexpr double kAlwaysAfterOfferMs = 3000.0;

enum PresenceBit : uint8_t
{
    PresenceMuted = 1,
    PresenceOnAir = 2,
    PresenceRelayAlways = 4, // this player's Relay is set to Always: no direct link with them
};

// Each sender's own millisecond clock, for the Relay's send times.
uint32_t ClockStamp(double aNowMs)
{
    return static_cast<uint32_t>(static_cast<int64_t>(aNowMs));
}

struct RelayItem
{
    double queuedMs = 0.0;
    bool audio = false;
    std::vector<uint8_t> packet;
};

// How late a Relay message is against the quickest of the last few seconds. The two machines' clocks differ by any
// amount, so only differences between messages count. Keeps the last quick time through a load, so a backlog
// delivered all at once afterwards shows as late.
class RelayLateness
{
public:
    double Late(double aNowMs, uint32_t aSentMs)
    {
        const uint32_t transit = ClockStamp(aNowMs) - aSentMs;
        if (aNowMs - m_bucketStartMs >= kBucketMs)
        {
            if (m_haveCurrent)
            {
                m_previous = m_current;
                m_havePrevious = true;
            }
            m_haveCurrent = false;
            m_bucketStartMs = aNowMs;
        }
        if (!m_haveCurrent || static_cast<int32_t>(transit - m_current) < 0)
        {
            m_current = transit;
            m_haveCurrent = true;
        }
        uint32_t quickest = m_current;
        if (m_havePrevious && static_cast<int32_t>(m_previous - quickest) < 0)
        {
            quickest = m_previous;
        }
        return static_cast<double>(static_cast<int32_t>(transit - quickest));
    }

private:
    static constexpr double kBucketMs = 2500.0;
    double m_bucketStartMs = -1e12;
    uint32_t m_current = 0;
    uint32_t m_previous = 0;
    bool m_haveCurrent = false;
    bool m_havePrevious = false;
};

struct PathCounters
{
    std::atomic<uint32_t> heardDirect{0};
    std::atomic<uint32_t> heardRelay{0};
    std::atomic<uint32_t> duplicates{0};
    std::atomic<uint32_t> stale{0};
    std::atomic<uint32_t> relayMessages{0};
    std::atomic<uint32_t> relayFrames{0};
    std::atomic<uint32_t> refusedLimit{0};
    std::atomic<uint32_t> refusedNotNow{0};
    std::atomic<uint32_t> refusedOther{0};
    std::atomic<uint32_t> tooOld{0};
};

PathStats StatsOf(const PathCounters& aCounters)
{
    PathStats stats;
    stats.heardDirect = aCounters.heardDirect.load();
    stats.heardRelay = aCounters.heardRelay.load();
    stats.duplicates = aCounters.duplicates.load();
    stats.stale = aCounters.stale.load();
    stats.relayMessages = aCounters.relayMessages.load();
    stats.relayFrames = aCounters.relayFrames.load();
    stats.refusedLimit = aCounters.refusedLimit.load();
    stats.refusedNotNow = aCounters.refusedNotNow.load();
    stats.refusedOther = aCounters.refusedOther.load();
    stats.tooOld = aCounters.tooOld.load();
    return stats;
}

struct SeenFrame
{
    uint16_t sequence = 0;
    double atMs = -1e12;
};
constexpr size_t kSeenFrames = 256;

void PutU32(uint8_t* aOut, uint32_t aValue)
{
    aOut[0] = static_cast<uint8_t>(aValue);
    aOut[1] = static_cast<uint8_t>(aValue >> 8);
    aOut[2] = static_cast<uint8_t>(aValue >> 16);
    aOut[3] = static_cast<uint8_t>(aValue >> 24);
}

uint32_t GetU32(const uint8_t* aIn)
{
    return static_cast<uint32_t>(aIn[0]) | static_cast<uint32_t>(aIn[1]) << 8 | static_cast<uint32_t>(aIn[2]) << 16 |
           static_cast<uint32_t>(aIn[3]) << 24;
}

uint8_t ToByte(float aValue, float aMax)
{
    return static_cast<uint8_t>(std::clamp(aValue / aMax, 0.f, 1.f) * 255.f + 0.5f);
}

float FromByte(uint8_t aValue, float aMax)
{
    return static_cast<float>(aValue) / 255.f * aMax;
}

class SharedLock
{
public:
    explicit SharedLock(SRWLOCK& aLock)
        : m_lock(aLock)
    {
        AcquireSRWLockShared(&m_lock);
    }
    ~SharedLock()
    {
        ReleaseSRWLockShared(&m_lock);
    }

private:
    SRWLOCK& m_lock;
};

class ExclusiveLock
{
public:
    explicit ExclusiveLock(SRWLOCK& aLock)
        : m_lock(aLock)
    {
        AcquireSRWLockExclusive(&m_lock);
    }
    ~ExclusiveLock()
    {
        ReleaseSRWLockExclusive(&m_lock);
    }

private:
    SRWLOCK& m_lock;
};
} // namespace

struct Engine::Peer
{
    PeerId id = 0;
    std::string name;
    bool offerer = false;

    std::unique_ptr<Link> link;
    uint32_t generation = 0;
    double linkCreatedMs = 0.0;
    double nextRetryMs = 0.0;
    double retryDelayMs = kFirstRetryMs;
    double lastRestartAskMs = -1e12;
    double addedMs = 0.0;
    bool wasConnected = false;
    std::atomic<bool> noLinkNoted{false};

    // The path: direct while this is set (the link is connected and hearing from them), else the Relay. Set by Tick.
    std::atomic<bool> directUp{false};
    std::atomic<double> lastDirectMs{0.0}; // our last packet from them by each path
    std::atomic<double> lastRelayMs{-1e12};
    std::atomic<double> alwaysIgnoredUntilMs{-1e12}; // after an offer from them, their presence's Always bit is old

    // Worker thread only: what the log and the notes last said about the path.
    bool onRelay = false;
    bool relayNoted = false;
    bool theyWereAlways = false;
    double relaySinceMs = 0.0;
    std::string directDownWhy = "no direct link yet";
    PathStats logged;

    // Relay packets waiting for the game thread, queued by the audio and worker threads.
    std::mutex relayMutex;
    std::deque<RelayItem> relayQueue;
    RelayLateness relayLateness; // game thread only

    // Audio frames taken lately, so a frame that came by both paths plays once.
    std::mutex seenMutex;
    std::array<SeenFrame, kSeenFrames> seen{};

    PathCounters counters;

    std::atomic<double> lastAudioMs{-1e12};
    std::atomic<double> spatialMs{-1e12};
    std::atomic<bool> audibleNearby{false};
    std::atomic<int> pingMs{-1};
    std::atomic<uint8_t> remoteBits{0};
    std::atomic<uint32_t> echoSent{0};
    std::atomic<double> echoAtMs{0.0};

    // The last position's effect, for the log.
    std::atomic<float> distance{0.f};
    std::atomic<float> occlusion{0.f};
    std::atomic<float> nearGain{0.f};
    std::atomic<float> turnedAway{0.f};
    std::atomic<int> cabin{0};
    std::atomic<float> gapShare{0.f};       // of what crossed a cabin, how much came through its gaps
    std::atomic<float> wayRoundMeters{0.f}; // 0 if there's none
    std::atomic<float> wayRoundBends{0.f};
    TalkerEase ease;   // game thread only
    PathEase pathEase; // game thread only

    // The car they sit in: what's open on it, from their presence, and how it stands in our world (game thread only).
    std::atomic<uint64_t> remoteCar{0};
    Car car;
    uint32_t carKey = 0;
    CarFrame carFrame;
};

namespace
{
// What's open on a car, packed for an atomic: glass in the low 32 bits, then windows, doors, no roof.
uint64_t PackCar(const CarStates& aStates)
{
    return static_cast<uint64_t>(aStates.glassGone) | (static_cast<uint64_t>(aStates.windowsDown & 0xFu) << 32) |
           (static_cast<uint64_t>(aStates.doorsOpen & 0xFu) << 36) | (static_cast<uint64_t>(aStates.openTop ? 1u : 0u) << 40);
}

CarStates UnpackCar(uint64_t aBits)
{
    CarStates states;
    states.glassGone = static_cast<uint32_t>(aBits);
    states.windowsDown = static_cast<uint8_t>((aBits >> 32) & 0xFu);
    states.doorsOpen = static_cast<uint8_t>((aBits >> 36) & 0xFu);
    states.openTop = ((aBits >> 40) & 1u) != 0;
    return states;
}
} // namespace

Engine::Engine(Settings& aSettings, bool aUseDevices)
    : m_settings(aSettings)
    , m_useDevices(aUseDevices)
{
    uint32_t start = 0;
    RandomBytes(&start, sizeof(start));
    m_counter.store(start & 0x3FFFFFFFu); // never close to wrapping, and a restart can't reuse a nonce under one key

    m_mic = std::make_unique<MicProcessor>(
        [this](const uint8_t* aOpus, int aSize, bool aSpurt) { OnMicPacket(aOpus, aSize, aSpurt); });
    m_mic->SetOwnVoiceSink([this](const float* aSamples, int aCount) { m_mixer.PushOwnVoice(aSamples, aCount); });
    ApplySettings();
    m_worker = std::thread([this] { WorkerLoop(); });
}

Engine::~Engine()
{
    m_stopWorker.store(true);
    m_workReady.notify_all();
    if (m_worker.joinable())
    {
        m_worker.join();
    }
    StopAudioThreads();

    std::vector<std::shared_ptr<Peer>> peers;
    {
        ExclusiveLock lock(m_peersLock);
        peers.swap(m_peers);
    }
    for (const auto& peer : peers)
    {
        peer->link.reset();
    }
}

void Engine::Post(std::function<void()> aWork)
{
    {
        std::lock_guard lock(m_workMutex);
        m_work.push_back(std::move(aWork));
    }
    m_workReady.notify_one();
}

void Engine::WorkerLoop()
{
    while (!m_stopWorker.load())
    {
        std::deque<std::function<void()>> work;
        {
            std::unique_lock lock(m_workMutex);
            m_workReady.wait_for(lock, std::chrono::milliseconds(100),
                                 [this] { return m_stopWorker.load() || !m_work.empty(); });
            work.swap(m_work);
        }
        for (auto& item : work)
        {
            item();
        }
        Tick(NowMs());
    }
}

std::shared_ptr<Engine::Peer> Engine::FindPeer(PeerId aPeer) const
{
    SharedLock lock(m_peersLock);
    for (const auto& peer : m_peers)
    {
        if (peer->id == aPeer)
        {
            return peer;
        }
    }
    return nullptr;
}

void Engine::SessionStart(PeerId aSelf)
{
    m_self.store(aSelf);
    m_inSession.store(true);
    Logf(LogInfo, "session started, we are peer %u", aSelf);
    ChangeRadio([](RadioMic& aMic, double aNowMs) { return aMic.SetSession(true, aNowMs); }, false);
}

void Engine::SessionEnd()
{
    m_inSession.store(false);
    m_haveKey.store(false);
    ChangeRadio([](RadioMic& aMic, double aNowMs) { return aMic.SetSession(false, aNowMs); }, false);
    Post([this] {
        std::vector<std::shared_ptr<Peer>> peers;
        {
            ExclusiveLock lock(m_peersLock);
            peers.swap(m_peers);
        }
        for (const auto& peer : peers)
        {
            m_mixer.RemoveVoice(peer->id);
            peer->link.reset();
        }
    });
    Logf(LogInfo, "session ended");
}

void Engine::SetKey(const uint8_t* aKey, size_t aSize)
{
    if (aSize != m_key.size())
    {
        m_haveKey.store(false);
        return;
    }
    {
        ExclusiveLock lock(m_keyLock);
        std::memcpy(m_key.data(), aKey, m_key.size());
    }
    m_haveKey.store(true);
}

void Engine::AddPeer(PeerId aPeer, const std::string& aName)
{
    const PeerId self = m_self.load();
    Post([this, aPeer, aName, self] {
        if (FindPeer(aPeer))
        {
            return;
        }
        auto peer = std::make_shared<Peer>();
        peer->id = aPeer;
        peer->name = aName;
        peer->offerer = self < aPeer; // the lower number speaks first, so exactly one side does
        peer->addedMs = NowMs();
        m_mixer.AddVoice(aPeer);
        {
            ExclusiveLock lock(m_peersLock);
            m_peers.push_back(peer);
        }
        ApplyPeerMix(*peer);
        Logf(LogInfo, "peer %u (%s) has the mod, %s", aPeer, aName.c_str(), peer->offerer ? "we offer" : "they offer");
    });
}

void Engine::SetPeerName(PeerId aPeer, const std::string& aName)
{
    Post([this, aPeer, aName] {
        const auto peer = FindPeer(aPeer);
        if (!peer || peer->name == aName)
        {
            return;
        }
        {
            ExclusiveLock lock(m_peersLock);
            peer->name = aName;
        }
        ApplyPeerMix(*peer); // volumes are stored by name
        Logf(LogInfo, "peer %u is now called %s", aPeer, aName.c_str());
    });
}

void Engine::RemovePeer(PeerId aPeer)
{
    Post([this, aPeer] {
        std::shared_ptr<Peer> gone;
        {
            ExclusiveLock lock(m_peersLock);
            const auto found =
                std::find_if(m_peers.begin(), m_peers.end(), [aPeer](const auto& aEntry) { return aEntry->id == aPeer; });
            if (found != m_peers.end())
            {
                gone = *found;
                m_peers.erase(found);
            }
        }
        if (gone)
        {
            Logf(LogInfo, "peer %u (%s) left", aPeer, gone->name.c_str());
            m_mixer.RemoveVoice(aPeer);
            gone->link.reset();
        }
    });
}

void Engine::OnSignal(PeerId aFrom, const uint8_t* aData, size_t aSize)
{
    // A partner's bytes: check the shape before anything reads them.
    if (aSize < kSignalHeader || aSize > kSignalHeader + kMaxSignalText)
    {
        return;
    }
    if (std::memchr(aData + kSignalHeader, 0, aSize - kSignalHeader) != nullptr)
    {
        return;
    }
    std::vector<uint8_t> message(aData, aData + aSize);
    Post([this, aFrom, message = std::move(message)] {
        const auto peer = FindPeer(aFrom);
        if (!peer)
        {
            return; // they left while this was on its way
        }
        HandleSignal(*peer, message[0], GetU32(message.data() + 1),
                     std::string(reinterpret_cast<const char*>(message.data() + kSignalHeader),
                                 message.size() - kSignalHeader));
    });
}

void Engine::CreateLink(Peer& aPeer, uint32_t aGeneration)
{
    aPeer.generation = aGeneration;
    aPeer.linkCreatedMs = NowMs();
    auto link = std::make_unique<Link>(aPeer.id, aGeneration, aPeer.offerer, m_stunCursor++, *this);
    Link* started = link.get();
    {
        ExclusiveLock lock(m_peersLock);
        aPeer.link = std::move(link);
    }
    started->Start();
    Logf(LogInfo, "peer %u: connecting (try %u)", aPeer.id, aGeneration);
}

void Engine::DestroyLink(Peer& aPeer, const char* aWhy)
{
    if (aPeer.directUp.exchange(false))
    {
        aPeer.directDownWhy = aWhy;
    }
    std::unique_ptr<Link> old;
    {
        ExclusiveLock lock(m_peersLock);
        old = std::move(aPeer.link);
    }
    // Outside the lock: this waits for the link's thread, whose callbacks may be waiting for the same lock.
    old.reset();
    aPeer.wasConnected = false;
    aPeer.pingMs.store(-1);
}

void Engine::HandleSignal(Peer& aPeer, uint8_t aKind, uint32_t aGeneration, const std::string& aText)
{
    // With the Relay on Always here there's no direct link to set up: offers go unanswered.
    if (m_relayAlways.load())
    {
        return;
    }
    if ((aPeer.remoteBits.load() & PresenceRelayAlways) != 0)
    {
        if (aKind != SignalDescription)
        {
            return;
        }
        // An Always player makes no offers, so they've left Always, and the offer beat their presence saying so. An
        // older presence may still be on its way over the Relay, so the bit counts again only after a moment.
        aPeer.remoteBits.fetch_and(static_cast<uint8_t>(~PresenceRelayAlways));
        aPeer.alwaysIgnoredUntilMs.store(NowMs() + kAlwaysAfterOfferMs);
    }
    switch (aKind)
    {
    case SignalRestart:
        if (aPeer.offerer && aGeneration == aPeer.generation && aPeer.link)
        {
            Logf(LogInfo, "peer %u asks to reconnect", aPeer.id);
            DestroyLink(aPeer, "they asked to reconnect");
            aPeer.nextRetryMs = 0.0;
        }
        break;
    case SignalDescription:
        if (aPeer.offerer)
        {
            if (aPeer.link && aGeneration == aPeer.generation)
            {
                aPeer.link->OnSignal(aKind, aText);
            }
        }
        else if (aGeneration >= aPeer.generation)
        {
            // A newer try from the offering side replaces whatever we had.
            if (aPeer.link)
            {
                DestroyLink(aPeer, "they started a new link");
            }
            CreateLink(aPeer, aGeneration);
            aPeer.link->OnSignal(aKind, aText);
        }
        break;
    case SignalCandidate:
    case SignalGatheringDone:
        if (aPeer.link && aGeneration == aPeer.generation)
        {
            aPeer.link->OnSignal(aKind, aText);
        }
        break;
    default:
        break; // a newer version's message, or nonsense
    }
}

void Engine::LinkSignal(PeerId aPeer, uint8_t aKind, uint32_t aGeneration, const std::string& aText)
{
    std::vector<uint8_t> message(kSignalHeader + aText.size());
    message[0] = aKind;
    PutU32(message.data() + 1, aGeneration);
    std::memcpy(message.data() + kSignalHeader, aText.data(), aText.size());
    std::lock_guard lock(m_outMutex);
    if (m_outgoing.size() >= kMaxQueuedSignals)
    {
        m_outgoing.pop_front(); // only a player we can't reach piles up this many, and each retry starts over anyway
    }
    m_outgoing.emplace_back(aPeer, std::move(message));
}

void Engine::DrainSignals(const std::function<bool(PeerId, const std::vector<uint8_t>&)>& aSend)
{
    std::lock_guard lock(m_outMutex);
    if (m_outgoing.empty())
    {
        return;
    }
    // One player we can't reach yet mustn't hold up the others. Theirs stay in order, so a candidate never overtakes
    // its description.
    std::vector<PeerId> held;
    std::deque<std::pair<PeerId, std::vector<uint8_t>>> kept;
    for (auto& entry : m_outgoing)
    {
        const bool alreadyHeld = std::find(held.begin(), held.end(), entry.first) != held.end();
        if (alreadyHeld || !aSend(entry.first, entry.second))
        {
            if (!alreadyHeld)
            {
                held.push_back(entry.first);
            }
            kept.push_back(std::move(entry));
        }
    }
    m_outgoing.swap(kept);
}

void Engine::Note(const std::string& aText)
{
    std::lock_guard lock(m_outMutex);
    m_notes.push_back(aText);
}

void Engine::DrainNotes(const std::function<void(const std::string&)>& aShow)
{
    std::lock_guard lock(m_outMutex);
    for (const std::string& note : m_notes)
    {
        aShow(note);
    }
    m_notes.clear();
}

void Engine::Tick(double aNowMs)
{
    std::vector<std::shared_ptr<Peer>> peers;
    {
        SharedLock lock(m_peersLock);
        peers = m_peers;
    }
    for (const auto& entry : peers)
    {
        TickDirect(*entry, aNowMs);
        TickPath(*entry, aNowMs);
    }

    if (aNowMs - m_lastPresenceMs >= kPresenceEveryMs)
    {
        m_lastPresenceMs = aNowMs;
        SendPresence(aNowMs);
    }
    LogLevels(aNowMs);
    LogRelay(aNowMs);
    ReadLiveTuning(aNowMs);
    RefreshHeadsetLink(aNowMs);
    UpdateAudioThreads(aNowMs);
}

// The direct link: set it up, notice when it's lost, and try again. Not at all while either side's Relay is on Always.
void Engine::TickDirect(Peer& aPeer, double aNowMs)
{
    const bool theyAreAlways = (aPeer.remoteBits.load() & PresenceRelayAlways) != 0;
    if (theyAreAlways != aPeer.theyWereAlways)
    {
        aPeer.theyWereAlways = theyAreAlways;
        Logf(LogInfo, "peer %u (%s) set their Relay to %s", aPeer.id, aPeer.name.c_str(),
             theyAreAlways ? "Always" : "When needed");
        if (!theyAreAlways)
        {
            aPeer.retryDelayMs = kFirstRetryMs;
            aPeer.nextRetryMs = 0.0;
        }
    }
    if (m_relayAlways.load() || theyAreAlways)
    {
        const char* why = m_relayAlways.load() ? "the Relay is set to Always here" : "they set their Relay to Always";
        if (aPeer.link)
        {
            Logf(LogInfo, "peer %u (%s): dropping the direct link, as %s", aPeer.id, aPeer.name.c_str(), why);
            DestroyLink(aPeer, why);
        }
        if (aPeer.directDownWhy != why)
        {
            aPeer.directDownWhy = why;
        }
        return;
    }

    const bool hasLink = aPeer.link != nullptr;
    const LinkState state = hasLink ? aPeer.link->State() : LinkState::Failed;
    const bool connected = hasLink && state == LinkState::Connected;

    if (connected && !aPeer.wasConnected)
    {
        aPeer.wasConnected = true;
        aPeer.retryDelayMs = kFirstRetryMs;
        aPeer.noLinkNoted.store(false);
        aPeer.lastDirectMs.store(aNowMs);
        aPeer.directUp.store(true);
        Logf(LogInfo, "peer %u (%s): direct link up after %.0f ms, %s", aPeer.id, aPeer.name.c_str(),
             aNowMs - aPeer.linkCreatedMs, aPeer.link->PathKinds().c_str());
        Note("Voice linked with " + aPeer.name);
    }

    if (!hasLink)
    {
        if (aPeer.offerer && m_haveKey.load() && aNowMs >= aPeer.nextRetryMs)
        {
            CreateLink(aPeer, aPeer.generation + 1);
        }
        return;
    }

    const bool timedOut = state == LinkState::Connecting && aNowMs - aPeer.linkCreatedMs > kConnectTimeoutMs;
    // Only direct packets count here: a partner whose direct packets stopped may still be heard over the Relay.
    const bool silent = connected && m_haveKey.load() && aNowMs - aPeer.lastDirectMs.load() > kSilentLinkMs;
    if (connected && !silent && !aPeer.directUp.load())
    {
        // The answering side keeps a silent link while it waits for a new one, and the old one can come back to life.
        aPeer.directUp.store(true);
        aPeer.noLinkNoted.store(false);
        Logf(LogInfo, "peer %u (%s): direct link heard from again", aPeer.id, aPeer.name.c_str());
        Note("Voice linked with " + aPeer.name);
    }
    if (state != LinkState::Failed && !timedOut && !silent)
    {
        return;
    }

    const char* what = silent ? "went silent" : timedOut ? "timed out" : "failed";
    const char* why = silent ? "the direct link went silent" : timedOut ? "the direct link timed out" : "the direct link failed";
    if (aPeer.directUp.exchange(false))
    {
        aPeer.directDownWhy = why;
        Note("Voice lost the link to " + aPeer.name + ", reconnecting");
    }
    if (aPeer.offerer)
    {
        Logf(LogInfo, "peer %u (%s): link %s", aPeer.id, aPeer.name.c_str(), what);
        DestroyLink(aPeer, why);
        aPeer.nextRetryMs = aNowMs + aPeer.retryDelayMs;
        aPeer.retryDelayMs = std::min(aPeer.retryDelayMs * 2.0, kMaxRetryMs);
    }
    else if (aNowMs - aPeer.lastRestartAskMs > kRestartAskEveryMs)
    {
        // Logged with the ask, which goes once every kRestartAskEveryMs, rather than on every tick while waiting.
        aPeer.lastRestartAskMs = aNowMs;
        Logf(LogInfo, "peer %u (%s): link %s, asking them to reconnect", aPeer.id, aPeer.name.c_str(), what);
        LinkSignal(aPeer.id, SignalRestart, aPeer.generation, "");
    }
}

// Which way voice goes to them, for the log and the notes. OnMicPacket and SendPresence read directUp themselves.
void Engine::TickPath(Peer& aPeer, double aNowMs)
{
    const bool always = m_relayAlways.load() || (aPeer.remoteBits.load() & PresenceRelayAlways) != 0;
    const bool relayWorking = aNowMs - aPeer.lastRelayMs.load() < kRelayFreshMs;
    const bool onRelay = m_haveKey.load() && !aPeer.directUp.load();
    if (onRelay != aPeer.onRelay)
    {
        aPeer.onRelay = onRelay;
        if (onRelay)
        {
            aPeer.relaySinceMs = aNowMs;
            aPeer.relayNoted = false;
            Logf(LogInfo, "peer %u (%s): voice goes over the Relay: %s", aPeer.id, aPeer.name.c_str(),
                 aPeer.directDownWhy.c_str());
        }
        else if (aPeer.directUp.load())
        {
            Logf(LogInfo, "peer %u (%s): voice back on the direct link, the Relay stops", aPeer.id, aPeer.name.c_str());
        }
    }
    // Not for the moment a direct link takes to come up, or every session would start with this note.
    if (onRelay && relayWorking && !aPeer.relayNoted && (always || aNowMs - aPeer.relaySinceMs >= kRelayNoteAfterMs))
    {
        aPeer.relayNoted = true;
        Logf(LogInfo, "peer %u (%s): the Relay is getting through", aPeer.id, aPeer.name.c_str());
        Note("Voice with " + aPeer.name + " on Relay");
    }
    if (!aPeer.directUp.load() && !relayWorking && !aPeer.noLinkNoted.load() && aNowMs - aPeer.addedMs > kNoLinkNoteAfterMs)
    {
        aPeer.noLinkNoted.store(true);
        Note(always ? "No voice with " + aPeer.name + " on the Relay yet"
                    : "No direct link to " + aPeer.name + " yet, still trying");
    }
}

void Engine::LogRelay(double aNowMs)
{
    if (aNowMs - m_lastRelayLogMs < kRelayLogEveryMs)
    {
        return;
    }
    m_lastRelayLogMs = aNowMs;
    SharedLock lock(m_peersLock);
    for (const auto& peer : m_peers)
    {
        const PathStats now = StatsOf(peer->counters);
        PathStats& was = peer->logged;
        if (now.relayMessages == was.relayMessages && now.heardRelay == was.heardRelay && now.tooOld == was.tooOld &&
            now.refusedLimit == was.refusedLimit && now.refusedNotNow == was.refusedNotNow &&
            now.refusedOther == was.refusedOther && now.stale == was.stale && now.duplicates == was.duplicates)
        {
            continue;
        }
        Logf(LogInfo, "relay: %s: sent %u messages with %u frames; NightCoop refused %u for its rate, %u not now, %u otherwise; %u frames waited too long; heard %u frames over the Relay and %u direct, dropped %u too late and %u twice; ping %d ms",
             peer->name.c_str(), now.relayMessages - was.relayMessages, now.relayFrames - was.relayFrames,
             now.refusedLimit - was.refusedLimit, now.refusedNotNow - was.refusedNotNow,
             now.refusedOther - was.refusedOther, now.tooOld - was.tooOld, now.heardRelay - was.heardRelay,
             now.heardDirect - was.heardDirect, now.stale - was.stale, now.duplicates - was.duplicates,
             peer->pingMs.load());
        was = now;
    }
}

// Temporary: see LiveTuning. Lines like room_db=-3 in %LOCALAPPDATA%\NightCoopVoice\tuning.ini, picked up within a second.
void Engine::ReadLiveTuning(double aNowMs)
{
    if (!m_useDevices || aNowMs - m_lastTuningCheckMs < 1000.0)
    {
        return;
    }
    m_lastTuningCheckMs = aNowMs;

    wchar_t appData[MAX_PATH * 2] = {};
    const DWORD size = GetEnvironmentVariableW(L"LOCALAPPDATA", appData, static_cast<DWORD>(std::size(appData)));
    if (size == 0 || size >= std::size(appData))
    {
        return;
    }
    const std::filesystem::path path = std::filesystem::path(appData) / L"NightCoopVoice" / L"tuning.ini";
    std::error_code error;
    const auto written = std::filesystem::last_write_time(path, error);
    const int64_t stamp = error ? 0 : static_cast<int64_t>(written.time_since_epoch().count());
    if (stamp == m_tuningFileTime)
    {
        return;
    }
    m_tuningFileTime = stamp;

    float roomDb = 0.f;
    float ring = 1.f;
    float echoDb = 0.f;
    float ownDb = 0.f;
    float falloffBend = kStartFalloffBend;
    std::ifstream file(path);
    std::string line;
    while (std::getline(file, line))
    {
        const size_t equals = line.find('=');
        if (equals == std::string::npos)
        {
            continue;
        }
        const std::string key = line.substr(0, equals);
        const float value = static_cast<float>(std::atof(line.c_str() + equals + 1));
        if (!std::isfinite(value))
        {
            continue;
        }
        if (key == "room_db")
        {
            roomDb = std::clamp(value, -40.f, 20.f);
        }
        else if (key == "ring")
        {
            ring = std::clamp(value, 0.1f, 4.f);
        }
        else if (key == "echo_db")
        {
            echoDb = std::clamp(value, -60.f, 20.f);
        }
        else if (key == "own_db")
        {
            ownDb = std::clamp(value, -60.f, 20.f);
        }
        else if (key == "falloff_bend")
        {
            falloffBend = std::clamp(value, 0.3f, 2.f);
        }
    }
    g_liveTuning.roomDb.store(roomDb);
    g_liveTuning.ring.store(ring);
    g_liveTuning.echoDb.store(echoDb);
    g_liveTuning.ownDb.store(ownDb);
    g_liveTuning.falloffBend.store(falloffBend);
    Logf(LogInfo, "tuning: room %+.1f dB, ring times %.2f, echoes %+.1f dB, own voice %+.1f dB, falloff bend %.2f", roomDb, ring, echoDb, ownDb, falloffBend);
}

// Real numbers for when someone says a voice is too quiet, and what the mic learned, for next time.
void Engine::LogLevels(double aNowMs)
{
    if (!m_audioRunning.load() || aNowMs - m_lastLevelsMs < kLevelsEveryMs)
    {
        return;
    }
    m_lastLevelsMs = aNowMs;
    SaveAutoGain();

    Logf(LogInfo, "levels: mic speech %.0f dB (speech band %.1f lower), auto gain %+.0f dB, sent %.0f dB; game now %.0f dB, loud parts %.0f dB, master %.0f%%, voice gain %+.1f dB, voices out %.0f dB%s",
         m_mic->RawSpeechDb(), m_mic->SpeechBandBelowDb(), m_mic->AutoGainDb(), m_mic->SentSpeechDb(), m_autoMix.GameDb(),
         m_autoMix.LoudDb(), m_autoMix.Master(), m_autoMix.GainDb(), m_autoMix.TakeVoicesOutDb(),
         m_autoMix.Measured() ? "" : " (output not measured)");

    SharedLock lock(m_peersLock);
    for (const auto& peer : m_peers)
    {
        float db = 0.f;
        float bandBelow = 0.f;
        float seconds = 0.f;
        m_mixer.TakeHeardStats(peer->id, db, bandBelow, seconds);
        if (seconds >= kHeardWorthLoggingSeconds)
        {
            Logf(LogInfo, "levels: %s arrived at %.0f dB (speech band %.1f lower) over %.0f s; %.0f m away, walls %.2f, way round %.0f m with %.0f bends, cabin %d (%.2f through its gaps), turned away %.2f, nearby gain %.2f",
                 peer->name.c_str(), db, bandBelow, seconds, peer->distance.load(), peer->occlusion.load(),
                 peer->wayRoundMeters.load(), peer->wayRoundBends.load(), peer->cabin.load(), peer->gapShare.load(),
                 peer->turnedAway.load(), peer->nearGain.load());
        }
    }
}

std::string Engine::AutoGainKey()
{
    std::lock_guard lock(m_deviceMutex);
    return "agc." + (m_micDevice.empty() ? std::string("default") : m_micDevice);
}

void Engine::SaveAutoGain()
{
    const float gain = m_mic->AutoGainDb();
    if (std::fabs(gain - m_savedAutoGainDb) >= kAutoGainSaveStepDb)
    {
        m_savedAutoGainDb = gain;
        m_settings.Set(AutoGainKey(), std::to_string(gain));
    }
}

void Engine::SendPresence(double aNowMs)
{
    if (!m_haveKey.load())
    {
        return;
    }
    VoiceKey key;
    {
        SharedLock lock(m_keyLock);
        key = m_key;
    }
    const uint8_t bits = static_cast<uint8_t>((m_muted.load() ? PresenceMuted : 0) | (RadioOn() ? PresenceOnAir : 0) |
                                              (m_relayAlways.load() ? PresenceRelayAlways : 0));
    const uint32_t now = static_cast<uint32_t>(aNowMs);
    const uint8_t enclosure = ToByte(m_roomEnclosure.load(), 1.f);
    const uint8_t meters = ToByte(m_roomMeters.load(), kPresenceRoomMeters);
    const uint8_t decay = ToByte(m_roomDecay.load(), kPresenceRoomDecay);
    const CarStates car = UnpackCar(m_ourCarBits.load());

    SharedLock lock(m_peersLock);
    for (const auto& peer : m_peers)
    {
        // The ping trick: they echo our send time and say how long they sat on it. Over the Relay too, so the ping
        // is whichever path's real round trip.
        uint8_t plain[kPresenceSize];
        plain[0] = bits;
        PutU32(plain + 1, now);
        const double echoAt = peer->echoAtMs.load();
        PutU32(plain + 5, peer->echoSent.load());
        PutU32(plain + 9, echoAt > 0.0 ? static_cast<uint32_t>(aNowMs - echoAt) : 0xFFFFFFFFu);
        plain[13] = enclosure;
        plain[14] = meters;
        plain[15] = decay;
        PutU32(plain + 16, car.glassGone);
        plain[20] = static_cast<uint8_t>((car.windowsDown & 0xFu) | ((car.doorsOpen & 0xFu) << 4));
        plain[21] = car.openTop ? 1 : 0;

        PacketInfo info;
        info.type = PacketPresence;
        info.counter = m_counter.fetch_add(1);
        info.sender = m_self.load();
        uint8_t packet[kMaxPacket];
        const size_t size = SealPacket(key, info, plain, sizeof(plain), packet);
        SendToPeer(*peer, packet, size, false, aNowMs);
    }
}

void Engine::SendToPeer(Peer& aPeer, const uint8_t* aPacket, size_t aSize, bool aAudio, double aNowMs)
{
    if (aPeer.directUp.load() && aPeer.link && aPeer.link->Send(aPacket, aSize))
    {
        return;
    }
    RelayItem item;
    item.queuedMs = aNowMs;
    item.audio = aAudio;
    item.packet.assign(aPacket, aPacket + aSize);
    std::lock_guard lock(aPeer.relayMutex);
    if (aPeer.relayQueue.size() >= kRelayMostQueued)
    {
        // The game thread has stopped draining it, in a load or a long hitch.
        if (aPeer.relayQueue.front().audio)
        {
            aPeer.counters.tooOld++;
        }
        aPeer.relayQueue.pop_front();
    }
    aPeer.relayQueue.push_back(std::move(item));
}

void Engine::DrainRelay(const std::function<RelaySend(PeerId, const uint8_t*, size_t)>& aSend)
{
    const double now = NowMs();
    if (m_relayExtraFrames > 0 && now - m_relayLastLimitMs > kRelayEaseAfterMs)
    {
        --m_relayExtraFrames;
        m_relayLastLimitMs = now;
        Logf(LogInfo, "relay: no refusals for a while, packing one frame fewer a message");
    }
    const int frames = std::min((m_relayAudience.load() > kRelayPartnersAtTwoFrames ? 3 : 2) + m_relayExtraFrames,
                                kRelayMostFrames);
    // Long enough for the rest of a message's frames to come, so a lone frame only goes alone at the end of speech.
    const double flushMs = kFrameMs * (frames - 1) + kRelayFlushSlackMs;

    std::vector<std::shared_ptr<Peer>> peers;
    {
        SharedLock lock(m_peersLock);
        peers = m_peers;
    }
    const uint32_t stamp = ClockStamp(now);
    std::vector<std::pair<std::vector<uint8_t>, int>> messages; // each with its count of audio frames
    for (const auto& peer : peers)
    {
        messages.clear();
        {
            std::lock_guard lock(peer->relayMutex);
            auto& queue = peer->relayQueue;
            while (!queue.empty() && now - queue.front().queuedMs > kRelayMostWaitMs)
            {
                if (queue.front().audio)
                {
                    peer->counters.tooOld++;
                }
                queue.pop_front();
            }
            while (!queue.empty())
            {
                size_t bytes = kRelayHeader;
                int audio = 0;
                size_t count = 0;
                while (count < queue.size() && audio < frames &&
                       bytes + 2 + queue[count].packet.size() <= kRelayMaxMessage)
                {
                    bytes += 2 + queue[count].packet.size();
                    audio += queue[count].audio ? 1 : 0;
                    ++count;
                }
                if (count == 0)
                {
                    queue.pop_front(); // can't fit any message; no packet is this big
                    continue;
                }
                // Full, presence alone, or a frame that has waited long enough for its partner.
                const bool full = audio >= frames || count < queue.size();
                if (!full && audio > 0 && now - queue.front().queuedMs < flushMs)
                {
                    break;
                }
                std::vector<uint8_t> message(bytes);
                PutU32(message.data(), stamp);
                size_t at = kRelayHeader;
                for (size_t i = 0; i < count; ++i)
                {
                    const std::vector<uint8_t>& packet = queue[i].packet;
                    message[at] = static_cast<uint8_t>(packet.size());
                    message[at + 1] = static_cast<uint8_t>(packet.size() >> 8);
                    std::memcpy(message.data() + at + 2, packet.data(), packet.size());
                    at += 2 + packet.size();
                }
                queue.erase(queue.begin(), queue.begin() + static_cast<ptrdiff_t>(count));
                messages.emplace_back(std::move(message), audio);
            }
        }

        // Outside the queue's lock, so the audio thread never waits on NightCoop.
        for (const auto& [message, audio] : messages)
        {
            switch (aSend(peer->id, message.data(), message.size()))
            {
            case RelaySend::Sent:
                peer->counters.relayMessages++;
                peer->counters.relayFrames += static_cast<uint32_t>(audio);
                break;
            case RelaySend::Limit:
                peer->counters.refusedLimit++;
                RelayRefusedForRate(now, *peer, audio);
                break;
            case RelaySend::NotNow:
                peer->counters.refusedNotNow++;
                break;
            case RelaySend::Refused:
                peer->counters.refusedOther++;
                break;
            }
        }
    }
}

// Never waits or retries: the frames are dropped, and later messages carry more frames each, so there are fewer.
void Engine::RelayRefusedForRate(double aNowMs, const Peer& aPeer, int aFrames)
{
    if (aNowMs - m_relayLastLimitMs > kRelayLimitLogEveryMs)
    {
        Logf(LogInfo, "relay: NightCoop's rate limit refused a message to %s, and its %d frames were dropped",
             aPeer.name.c_str(), aFrames);
    }
    m_relayLastLimitMs = aNowMs;
    if (m_relayExtraFrames < kRelayMostFrames - 2 && aNowMs - m_relayLastRaiseMs >= kRelayRaiseEveryMs)
    {
        ++m_relayExtraFrames;
        m_relayLastRaiseMs = aNowMs;
        Logf(LogInfo, "relay: packing one frame more a message for a while, for NightCoop's rate limit");
    }
}

bool Engine::OnRelay(PeerId aFrom, const uint8_t* aData, size_t aSize)
{
    const auto peer = FindPeer(aFrom);
    if (!peer)
    {
        return false;
    }
    // A partner's bytes: every size is checked before anything is read.
    if (aSize < kRelayHeader || aSize > kRelayMaxMessage)
    {
        return true;
    }
    const bool stale = peer->relayLateness.Late(NowMs(), GetU32(aData)) > kRelayStaleMs;
    size_t at = kRelayHeader;
    while (aSize - at >= 2)
    {
        const size_t size = static_cast<size_t>(aData[at]) | static_cast<size_t>(aData[at + 1]) << 8;
        at += 2;
        if (size > aSize - at)
        {
            break;
        }
        ReceivePacket(aFrom, aData + at, size, true, stale);
        at += size;
    }
    return true;
}

void Engine::LinkPacket(PeerId aPeer, const uint8_t* aData, size_t aSize)
{
    ReceivePacket(aPeer, aData, aSize, false, false);
}

// From the link's thread (direct) or the game thread (the Relay). The packet's own sender, authenticated by the key,
// must be the player it came from, so a Relay message can't speak for anyone else.
void Engine::ReceivePacket(PeerId aPeer, const uint8_t* aData, size_t aSize, bool aRelay, bool aStale)
{
    if (!m_haveKey.load())
    {
        return;
    }
    VoiceKey key;
    {
        SharedLock lock(m_keyLock);
        key = m_key;
    }
    PacketInfo info;
    uint8_t plain[kMaxPlain];
    size_t plainSize = 0;
    if (!OpenPacket(key, aData, aSize, info, plain, plainSize) || info.sender != aPeer)
    {
        return;
    }

    const auto peer = FindPeer(aPeer);
    if (!peer)
    {
        return;
    }
    const double now = NowMs();
    (aRelay ? peer->lastRelayMs : peer->lastDirectMs).store(now);

    if (info.type == PacketAudio)
    {
        if (plainSize > 2)
        {
            const uint16_t sequence = static_cast<uint16_t>(plain[0] | plain[1] << 8);
            if (aStale)
            {
                peer->counters.stale++;
                return;
            }
            {
                // One stream whichever way it came: a frame already taken is never played again.
                std::lock_guard lock(peer->seenMutex);
                SeenFrame& seen = peer->seen[sequence % kSeenFrames];
                if (seen.sequence == sequence && now - seen.atMs < kSeenForMs)
                {
                    peer->counters.duplicates++;
                    return;
                }
                seen.sequence = sequence;
                seen.atMs = now;
            }
            (aRelay ? peer->counters.heardRelay : peer->counters.heardDirect)++;
            peer->lastAudioMs.store(now);
            m_mixer.PushPacket(aPeer, sequence, info.flags, plain + 2, static_cast<int>(plainSize - 2));
        }
    }
    else if (info.type == PacketPresence && plainSize == kPresenceSize)
    {
        uint8_t bits = plain[0];
        if (now < peer->alwaysIgnoredUntilMs.load())
        {
            bits &= static_cast<uint8_t>(~PresenceRelayAlways);
        }
        peer->remoteBits.store(bits);
        peer->echoSent.store(GetU32(plain + 1));
        peer->echoAtMs.store(now);
        const uint32_t held = GetU32(plain + 9);
        if (held != 0xFFFFFFFFu)
        {
            const uint32_t elapsed = static_cast<uint32_t>(now) - GetU32(plain + 5) - held;
            if (elapsed < 10000u)
            {
                peer->pingMs.store(static_cast<int>(elapsed));
            }
        }
        RoomSound theirs;
        theirs.enclosure = FromByte(plain[13], 1.f);
        theirs.meters = FromByte(plain[14], kPresenceRoomMeters);
        theirs.decaySeconds = FromByte(plain[15], kPresenceRoomDecay);
        m_mixer.SetTheirRoom(aPeer, theirs);
        CarStates car;
        car.glassGone = GetU32(plain + 16);
        car.windowsDown = static_cast<uint8_t>(plain[20] & 0xFu);
        car.doorsOpen = static_cast<uint8_t>(plain[20] >> 4);
        car.openTop = (plain[21] & 1u) != 0;
        peer->remoteCar.store(PackCar(car));
    }
}

void Engine::OnMicPacket(const uint8_t* aOpus, int aSize, bool aSpurt)
{
    const uint16_t sequence = m_sequence++;
    uint8_t plain[kMaxPlain];
    if (aSize + 2 > static_cast<int>(sizeof(plain)))
    {
        return;
    }
    plain[0] = static_cast<uint8_t>(sequence);
    plain[1] = static_cast<uint8_t>(sequence >> 8);
    std::memcpy(plain + 2, aOpus, static_cast<size_t>(aSize));

    bool radio = false;
    {
        std::lock_guard lock(m_radioMutex);
        radio = m_radioMic.OnAir(NowMs());
    }
    const uint8_t flags = static_cast<uint8_t>((radio ? kFlagRadio : 0) | (aSpurt ? kFlagSpurt : 0));

    const int test = m_testRoute.load();
    if (test != 0)
    {
        const uint8_t testFlags = static_cast<uint8_t>((aSpurt ? kFlagSpurt : 0) |
                                                       (test == static_cast<int>(TestRoute::Radio) ? kFlagRadio : 0));
        m_mixer.PushPacket(kSelfVoice, sequence, testFlags, aOpus, aSize);
    }

    if (!m_haveKey.load())
    {
        return;
    }
    VoiceKey key;
    {
        SharedLock lock(m_keyLock);
        key = m_key;
    }
    PacketInfo info;
    info.type = PacketAudio;
    info.flags = flags;
    info.counter = m_counter.fetch_add(1);
    info.sender = m_self.load();
    uint8_t packet[kMaxPacket];
    const size_t size = SealPacket(key, info, plain, static_cast<size_t>(aSize) + 2, packet);

    const double now = NowMs();
    int relayAudience = 0;
    SharedLock lock(m_peersLock);
    for (const auto& peer : m_peers)
    {
        // Your nearby voice goes only to people close enough to hear it; the radio goes to everyone.
        const bool nearby = peer->audibleNearby.load() && now - peer->spatialMs.load() < kPositionFreshMs;
        if (radio || nearby)
        {
            relayAudience += peer->directUp.load() ? 0 : 1;
            SendToPeer(*peer, packet, size, true, now);
        }
    }
    m_relayAudience.store(relayAudience);
}

void Engine::SetListener(const Vec3& aPosition, const Vec3& aForward, const Vec3& aRight)
{
    m_listenerPosition = aPosition;
    m_listenerForward = aForward;
    m_listenerRight = aRight;
    m_acoustics.SetListener(aPosition, NowMs());
    const RoomSound& room = m_acoustics.Room();
    m_mixer.SetRoom(room);
    m_roomEnclosure.store(room.enclosure);
    m_roomMeters.store(room.meters);
    m_roomDecay.store(room.decaySeconds);
}

void Engine::SetListenerState(bool aUnderwater, float aWorldSpeed, bool aInCar)
{
    m_listenerEase.Update(aUnderwater, SlowMotionFromWorldSpeed(aWorldSpeed), NowMs(), aInCar);
    m_mixer.SetListenerEffects(m_listenerEase.Underwater(), m_listenerEase.SlowMotion());
    // Only in headphones, or your speakers would play it back into your mic. A car's cabin has no room to speak of, and
    // the rays pass straight through it to the street.
    m_mixer.SetOwnEcho(m_headphones.load() ? (1.f - m_listenerEase.Underwater()) * (1.f - m_listenerEase.InCar()) : 0.f);
}

void Engine::SetPeerSpatial(PeerId aPeer, const Vec3& aPosition, const Vec3& aForward, int aCabin)
{
    const auto peer = FindPeer(aPeer);
    if (!peer)
    {
        return;
    }
    const double nowMs = NowMs();
    // What's open on the cars between us, as each of us reports our own, so both games decide the sending alike.
    const CarStates theirCar = UnpackCar(peer->remoteCar.load());
    const bool carOpen = aCabin == CabinSeparated && (theirCar.Any() || m_ourCarStates.Any());
    m_acoustics.SetTalker(aPeer, aPosition, aCabin, carOpen, nowMs - peer->lastAudioMs.load() < kTalkingRecentlyMs, nowMs);
    const float occlusion = aCabin == CabinShared ? 0.f : m_acoustics.Occlusion(aPeer);
    const SoundPath path = m_acoustics.Path(aPeer);
    peer->pathEase.Update(path.found, path.arrival, path.meters, path.bends, path.doors, nowMs);

    SpatialInput input;
    input.listenerPosition = m_listenerPosition;
    input.listenerForward = m_listenerForward;
    input.listenerRight = m_listenerRight;
    input.talkerPosition = aPosition;
    input.talkerForward = aForward;
    peer->ease.Update(aCabin, occlusion, nowMs);
    input.occlusion = peer->ease.Occlusion();
    input.sharedCabin = peer->ease.SharedCabin();
    input.separatedCabin = peer->ease.SeparatedCabin();
    input.headphones = m_headphones.load();
    input.underwater = m_listenerEase.Underwater();
    input.slowMotion = m_listenerEase.SlowMotion();
    input.enclosure = m_acoustics.Room().enclosure;
    input.pathAmount = peer->pathEase.Amount();
    input.pathArrival = peer->pathEase.Arrival();
    input.pathMeters = peer->pathEase.Meters();
    input.pathBends = peer->pathEase.Bends();
    input.pathDoors = peer->pathEase.Doors();
    if (aCabin == CabinSeparated)
    {
        // Through the gaps of their car, ours, or both. Inside a car, we hear with our head, not the camera behind it.
        const bool theirs = peer->carKey != 0 && peer->car.Described() && peer->car.Key() == peer->carKey;
        if (theirs)
        {
            peer->car.Update(theirCar, peer->carFrame, nowMs);
        }
        const bool ours = m_ourCarKey != 0 && m_ourCar.Described() && m_ourCar.Key() == m_ourCarKey;
        const CarSound through = ThroughCars(aPosition, ours ? m_ourHead : m_listenerPosition,
                                             theirs ? &peer->car.Openings() : nullptr, ours ? &m_ourCar.Openings() : nullptr,
                                             input.nearMeters);
        input.carOpenGain = through.gain;
        input.carOpenCutoffHz = through.cutoffHz;
        input.carOpenArrival = through.arrival;
    }
    input.carOpenAny = carOpen;
    const SpatialOutput output = ComputeSpatial(input);
    m_mixer.SetSpatial(aPeer, output);
    peer->audibleNearby.store(output.audible);
    peer->spatialMs.store(nowMs);

    const float x = aPosition.x - m_listenerPosition.x;
    const float y = aPosition.y - m_listenerPosition.y;
    const float z = aPosition.z - m_listenerPosition.z;
    const float distance = std::sqrt(x * x + y * y + z * z);

    const float echoAmount = Clamp01(1.f - input.occlusion * kEchoOcclusion) * (1.f - input.sharedCabin) *
                             (1.f - input.separatedCabin * (1.f - output.carOpenShare)) * (1.f - input.underwater) *
                             FarFade(distance, input.nearMeters, input.farMeters) *
                             (kEchoInOpenAir + (1.f - kEchoInOpenAir) * input.enclosure);
    m_mixer.SetEchoes(aPeer, ComputeEchoes(m_acoustics.Walls(), m_listenerPosition, m_listenerRight, aPosition, echoAmount, input.headphones));

    peer->wayRoundMeters.store(path.found ? path.meters : 0.f);
    peer->wayRoundBends.store(path.found ? path.bends : 0.f);
    peer->distance.store(distance);
    peer->occlusion.store(occlusion);
    peer->nearGain.store(std::max(output.gainLeft, output.gainRight));
    peer->turnedAway.store(output.turnedAway);
    peer->cabin.store(aCabin);
    peer->gapShare.store(output.carOpenShare);
}

Car* Engine::CarOf(PeerId aOwner, std::shared_ptr<Peer>& aKeep)
{
    if (aOwner == kOurCar)
    {
        return &m_ourCar;
    }
    aKeep = FindPeer(aOwner);
    return aKeep ? &aKeep->car : nullptr;
}

bool Engine::CarNeedsParts(PeerId aOwner, uint32_t aKey)
{
    std::shared_ptr<Peer> keep;
    const Car* const car = CarOf(aOwner, keep);
    return car && aKey != 0 && !(car->Described() && car->Key() == aKey);
}

void Engine::BeginCar(PeerId aOwner, uint32_t aKey)
{
    std::shared_ptr<Peer> keep;
    if (Car* const car = CarOf(aOwner, keep))
    {
        car->Begin(aKey);
    }
}

void Engine::AddCarPart(PeerId aOwner, int aGlass, int aDoor, const std::string& aName, uint64_t aMesh, const Vec3& aPivot)
{
    std::shared_ptr<Peer> keep;
    if (Car* const car = CarOf(aOwner, keep))
    {
        car->AddPart(aGlass, aDoor, aName, aMesh, aPivot);
    }
}

void Engine::FinishCar(PeerId aOwner, const std::string& aAppearance)
{
    std::shared_ptr<Peer> keep;
    Car* const car = CarOf(aOwner, keep);
    if (!car)
    {
        return;
    }
    car->Finish(aAppearance);
    Logf(LogInfo, "car: %s (%s) has %d gaps that can open%s, %d parts missing from the table", aAppearance.c_str(),
         aOwner == kOurCar ? "ours" : (keep ? keep->name.c_str() : "?"), car->GapCount(), car->OpenTop() ? ", no roof" : "",
         car->UnknownMeshes());
}

void Engine::SetOurCar(uint32_t aKey, const CarFrame& aFrame, const Vec3& aHead, const CarStates& aStates)
{
    m_ourCarKey = aKey;
    m_ourHead = aHead;
    CarStates states;
    if (aKey != 0 && m_ourCar.Described() && m_ourCar.Key() == aKey)
    {
        states = aStates;
        states.openTop = m_ourCar.OpenTop();
        m_ourCar.Update(states, aFrame, NowMs());
    }
    if (states != m_ourCarStates)
    {
        m_ourCarStates = states;
        m_ourCarBits.store(PackCar(states));
        Logf(LogInfo, "car: ours now has %s", states.Any() ? states.Describe().c_str() : "nothing open");
        Post([this] { SendPresence(NowMs()); });
    }
}

void Engine::SetPeerCar(PeerId aPeer, uint32_t aKey, const CarFrame& aFrame)
{
    if (const auto peer = FindPeer(aPeer))
    {
        peer->carKey = aKey;
        peer->carFrame = aFrame;
    }
}

void Engine::SetGameMaster(float aPercent)
{
    m_autoMix.SetGameMaster(aPercent);
}

void Engine::Tone(float aHz)
{
    m_mixer.PlayTone(aHz, kToneMs, kToneVolume);
}

void Engine::ToggleMute()
{
    const bool muted = !m_muted.load();
    m_muted.store(muted);
    m_mic->SetMuted(muted);
    m_settings.Set("muted", muted ? "1" : "0");
    Tone(muted ? kToneMute : kToneUnmute);
    Logf(LogInfo, "mic %s", muted ? "muted" : "unmuted");
}

void Engine::ChangeRadio(const std::function<bool(RadioMic&, double)>& aChange, bool aTone)
{
    bool changed = false;
    bool on = false;
    {
        std::lock_guard lock(m_radioMutex);
        changed = aChange(m_radioMic, NowMs());
        on = m_radioMic.On();
    }
    if (!changed)
    {
        return;
    }
    if (aTone)
    {
        Tone(on ? kToneRadioOn : kToneRadioOff);
    }
    Logf(LogInfo, "radio mic %s", on ? "on" : "off");
    // Partners' displays show who's on the radio, so they hear of it at once rather than with the next second's presence.
    Post([this] { SendPresence(NowMs()); });
}

void Engine::RadioKeyDown()
{
    ChangeRadio([](RadioMic& aMic, double aNowMs) { return aMic.KeyDown(aNowMs); }, true);
}

void Engine::RadioKeyUp()
{
    ChangeRadio([](RadioMic& aMic, double aNowMs) { return aMic.KeyUp(aNowMs); }, true);
}

void Engine::ToggleRadio()
{
    ChangeRadio([](RadioMic& aMic, double aNowMs) { return aMic.Toggle(aNowMs); }, true);
}

bool Engine::RadioOn() const
{
    std::lock_guard lock(m_radioMutex);
    return m_radioMic.On();
}

void Engine::SetTest(int aRoute)
{
    m_testRoute.store(aRoute);
    m_mixer.SetTestRoute(static_cast<TestRoute>(aRoute));
    Post([this, aRoute] {
        if (aRoute == 0)
        {
            m_mixer.RemoveVoice(kSelfVoice);
        }
        else
        {
            m_mixer.AddVoice(kSelfVoice);
        }
    });
}

void Engine::ApplyPeerMix(const Peer& aPeer)
{
    m_mixer.SetPeerMuted(aPeer.id, m_settings.GetBool("peer." + aPeer.name + ".mute", false));
}

void Engine::ApplySettings()
{
    m_autoMix.SetOffsetDb(m_settings.GetFloat("voice_level", 0.f));
    const bool headphones = m_settings.GetBool("headphones", true);
    m_headphones.store(headphones);
    // The Relay: "always" makes no direct links at all and tells partners so; anything else uses it only when needed.
    const bool always = m_settings.Get("relay") == "always";
    if (m_relayAlways.exchange(always) != always)
    {
        Logf(LogInfo, "relay: set to %s", always ? "Always, so no direct links" : "When needed");
        Post([this, always] {
            // Partners hear of it at once, by the path still in use, rather than with the next second's presence.
            SendPresence(NowMs());
            if (!always)
            {
                SharedLock lock(m_peersLock);
                for (const auto& peer : m_peers)
                {
                    peer->retryDelayMs = kFirstRetryMs;
                    peer->nextRetryMs = 0.0;
                }
            }
        });
    }

    const bool muted = m_settings.GetBool("muted", false);
    m_muted.store(muted);
    m_mic->SetMuted(muted);
    m_mic->SetGateThreshold(m_settings.GetFloat("gate", 60.f) / 100.f);
    m_mic->SetNoiseRemoval(m_settings.GetBool("noise_removal", true));
    const bool echo = m_settings.GetBool("echo_cancel", false);
    m_mic->SetEchoCancellation(echo);
    m_echoOn.store(echo);

    bool micChanged = false;
    {
        std::lock_guard lock(m_deviceMutex);
        const std::string mic = m_settings.Get("mic_device");
        const std::string output = m_settings.Get("output_device");
        micChanged = mic != m_micDevice;
        if (micChanged || output != m_outputDevice)
        {
            m_micDevice = mic;
            m_outputDevice = output;
            m_deviceGeneration.fetch_add(1);
        }
    }
    if (micChanged)
    {
        m_savedAutoGainDb = m_settings.GetFloat(AutoGainKey(), 0.f);
        m_mic->PresetAutoGain(m_savedAutoGainDb); // each mic keeps what it learned
    }

    SharedLock lock(m_peersLock);
    for (const auto& peer : m_peers)
    {
        ApplyPeerMix(*peer);
    }
}

PathStats Engine::Stats(PeerId aPeer) const
{
    const auto peer = FindPeer(aPeer);
    return peer ? StatsOf(peer->counters) : PathStats{};
}

std::vector<PeerView> Engine::Peers() const
{
    std::vector<PeerView> views;
    const double now = NowMs();
    SharedLock lock(m_peersLock);
    views.reserve(m_peers.size());
    for (const auto& peer : m_peers)
    {
        PeerView view;
        view.id = peer->id;
        view.name = peer->name;
        const bool direct = peer->directUp.load();
        if (direct)
        {
            view.link = PeerLink::Linked;
        }
        else if (peer->noLinkNoted.load())
        {
            view.link = PeerLink::Failed;
        }
        view.relay = !direct && now - peer->lastRelayMs.load() < kRelayFreshMs;
        const uint8_t bits = peer->remoteBits.load();
        view.muted = (bits & PresenceMuted) != 0;
        view.onAir = (bits & PresenceOnAir) != 0;
        view.pingMs = peer->pingMs.load();
        m_mixer.TalkState(peer->id, view.talkingNear, view.talkingRadio);
        views.push_back(std::move(view));
    }
    return views;
}

void Engine::InjectMic(const float* aMono, int aCount)
{
    m_mic->Process(aMono, aCount);
}

void Engine::UpdateAudioThreads(double aNowMs)
{
    if (!m_useDevices)
    {
        return;
    }
    bool wanted = m_testRoute.load() != 0;
    if (!wanted)
    {
        SharedLock lock(m_peersLock);
        for (const auto& peer : m_peers)
        {
            // Someone to talk to by either path.
            if (peer->directUp.load() || aNowMs - peer->lastRelayMs.load() < kRelayFreshMs)
            {
                wanted = true;
                break;
            }
        }
    }

    if (wanted)
    {
        m_audioUnneededSinceMs = -1.0;
        if (!m_audioRunning.load())
        {
            StartAudioThreads();
        }
    }
    else if (m_audioRunning.load())
    {
        if (m_audioUnneededSinceMs < 0.0)
        {
            m_audioUnneededSinceMs = aNowMs;
        }
        else if (aNowMs - m_audioUnneededSinceMs > kAudioLingerMs)
        {
            StopAudioThreads();
        }
    }
}

void Engine::StartAudioThreads()
{
    m_savedAutoGainDb = m_settings.GetFloat(AutoGainKey(), 0.f);
    m_mic->PresetAutoGain(m_savedAutoGainDb);
    m_stopAudio.store(false);
    m_audioRunning.store(true);
    m_captureThread = std::thread([this] { CaptureLoop(); });
    m_renderThread = std::thread([this] { RenderLoop(); });
    Logf(LogInfo, "audio started");
}

void Engine::StopAudioThreads()
{
    m_stopAudio.store(true);
    if (m_captureThread.joinable())
    {
        m_captureThread.join();
    }
    if (m_renderThread.joinable())
    {
        m_renderThread.join();
    }
    if (m_audioRunning.exchange(false))
    {
        SaveAutoGain();
        Logf(LogInfo, "audio stopped");
    }
}

void Engine::CaptureLoop()
{
    SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_HIGHEST);
    ComThread com;
    CaptureStream mic;
    CaptureStream loopback;
    std::vector<float> samples;
    std::vector<float> played;
    uint32_t openGeneration = m_deviceGeneration.load() - 1;

    while (!m_stopAudio.load())
    {
        const uint32_t generation = m_deviceGeneration.load();
        if (!mic.IsOpen() || generation != openGeneration)
        {
            std::string micDevice;
            {
                std::lock_guard lock(m_deviceMutex);
                micDevice = m_micDevice;
            }
            loopback.Close();
            if (!mic.Open(micDevice, false))
            {
                Sleep(2000);
                continue;
            }
            openGeneration = generation;
        }

        samples.clear();
        if (!mic.Read(samples, 20))
        {
            Logf(LogWarn, "audio: lost the microphone");
            mic.Close();
            Sleep(500);
            continue;
        }

        const bool echo = m_echoOn.load();
        if (echo)
        {
            if (!loopback.IsOpen())
            {
                std::string outputDevice;
                {
                    std::lock_guard lock(m_deviceMutex);
                    outputDevice = m_outputDevice;
                }
                loopback.Open(outputDevice, true);
            }
            if (loopback.IsOpen() && !loopback.Read(played, 0))
            {
                loopback.Close();
            }
            constexpr size_t kMaxQueued = kRate; // a second behind means the streams have drifted apart: start over
            if (played.size() > kMaxQueued)
            {
                played.clear();
            }
        }
        else if (loopback.IsOpen())
        {
            loopback.Close();
            played.clear();
        }

        if (samples.empty())
        {
            continue;
        }
        const bool haveReference = echo && played.size() >= samples.size();
        m_mic->Process(samples.data(), static_cast<int>(samples.size()), haveReference ? played.data() : nullptr);
        if (haveReference)
        {
            played.erase(played.begin(), played.begin() + static_cast<ptrdiff_t>(samples.size()));
        }
    }
}

void Engine::RenderLoop()
{
    SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_HIGHEST);
    // A fading room tail sinks into numbers so small the processor crawls over them. This treats them as the silence they are.
    _MM_SET_FLUSH_ZERO_MODE(_MM_FLUSH_ZERO_ON);
    _MM_SET_DENORMALS_ZERO_MODE(_MM_DENORMALS_ZERO_ON);
    ComThread com;
    RenderStream output;
    CaptureStream loopback;
    std::vector<float> played;
    float block[kBlock * 2];
    uint32_t openGeneration = m_deviceGeneration.load() - 1;

    while (!m_stopAudio.load())
    {
        const uint32_t generation = m_deviceGeneration.load();
        if (!output.IsOpen() || generation != openGeneration)
        {
            std::string device;
            {
                std::lock_guard lock(m_deviceMutex);
                device = m_outputDevice;
            }
            loopback.Close();
            if (!output.Open(device))
            {
                Sleep(2000);
                continue;
            }
            openGeneration = generation;
            // Without it voices still follow the game's Master Volume setting, just not what's playing.
            if (!loopback.Open(device, true))
            {
                Logf(LogWarn, "audio: can't measure the output, so voices follow only the Master Volume setting");
            }
        }

        if (loopback.IsOpen())
        {
            played.clear();
            if (!loopback.Read(played, 0))
            {
                Logf(LogWarn, "audio: lost the output measurement");
                loopback.Close();
            }
            else if (!played.empty())
            {
                m_autoMix.OnPlayed(played.data(), static_cast<int>(played.size()));
            }
        }

        int wanted = output.Wanted();
        if (wanted < 0)
        {
            Logf(LogWarn, "audio: lost the output device");
            output.Close();
            Sleep(500);
            continue;
        }
        while (wanted >= kBlock)
        {
            m_mixer.SetMasterGain(m_autoMix.GainLinear());
            m_mixer.Render(block);
            m_autoMix.OnBlock(block);
            if (!output.Write(block, kBlock))
            {
                output.Close();
                break;
            }
            wanted -= kBlock;
        }
        output.Wait(10);
    }
}
} // namespace nv
