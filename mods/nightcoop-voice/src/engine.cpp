#include "engine.hpp"

#include "audio/wasapi.hpp"

#include <pmmintrin.h>
#include <xmmintrin.h>

#include <algorithm>
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
constexpr double kHoldToTalkMs = 350.0;
constexpr double kLevelsEveryMs = 30000.0;
constexpr float kHeardWorthLoggingSeconds = 0.5f;
constexpr float kAutoGainSaveStepDb = 1.f;
constexpr size_t kMaxSignalText = 4096;
constexpr size_t kMaxQueuedSignals = 512;
constexpr size_t kSignalHeader = 5;
constexpr size_t kPresenceSize = 16;
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

enum PresenceBit : uint8_t
{
    PresenceMuted = 1,
    PresenceOnAir = 2,
};

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

    std::atomic<double> lastReceiveMs{0.0};
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
    std::atomic<float> wayRoundMeters{0.f}; // 0 if there's none
    std::atomic<float> wayRoundBends{0.f};
    TalkerEase ease;   // game thread only
    PathEase pathEase; // game thread only
};

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
    m_radioOn.store(false); // the radio mic starts each session off
    Logf(LogInfo, "session started, we are peer %u", aSelf);
}

void Engine::SessionEnd()
{
    m_inSession.store(false);
    m_haveKey.store(false);
    m_radioOn.store(false);
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

void Engine::DestroyLink(Peer& aPeer)
{
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
    switch (aKind)
    {
    case SignalRestart:
        if (aPeer.offerer && aGeneration == aPeer.generation && aPeer.link)
        {
            Logf(LogInfo, "peer %u asks to reconnect", aPeer.id);
            DestroyLink(aPeer);
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
                DestroyLink(aPeer);
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
        Peer& peer = *entry;
        const bool hasLink = peer.link != nullptr;
        const LinkState state = hasLink ? peer.link->State() : LinkState::Failed;
        const bool connected = hasLink && state == LinkState::Connected;

        if (connected && !peer.wasConnected)
        {
            peer.wasConnected = true;
            peer.retryDelayMs = kFirstRetryMs;
            peer.noLinkNoted.store(false);
            peer.lastReceiveMs.store(aNowMs);
            Logf(LogInfo, "peer %u (%s): direct link up after %.0f ms, %s", peer.id, peer.name.c_str(),
                 aNowMs - peer.linkCreatedMs, peer.link->PathKinds().c_str());
            Note("Voice linked with " + peer.name);
        }

        if (hasLink)
        {
            const bool timedOut = state == LinkState::Connecting && aNowMs - peer.linkCreatedMs > kConnectTimeoutMs;
            const bool silent =
                connected && m_haveKey.load() && aNowMs - peer.lastReceiveMs.load() > kSilentLinkMs;
            if (state == LinkState::Failed || timedOut || silent)
            {
                if (peer.wasConnected)
                {
                    Note("Voice lost the link to " + peer.name + ", reconnecting");
                }
                Logf(LogInfo, "peer %u (%s): link %s", peer.id, peer.name.c_str(),
                     silent ? "went silent" : timedOut ? "timed out" : "failed");
                if (peer.offerer)
                {
                    DestroyLink(peer);
                    peer.nextRetryMs = aNowMs + peer.retryDelayMs;
                    peer.retryDelayMs = std::min(peer.retryDelayMs * 2.0, kMaxRetryMs);
                }
                else if (aNowMs - peer.lastRestartAskMs > kRestartAskEveryMs)
                {
                    peer.lastRestartAskMs = aNowMs;
                    peer.wasConnected = false;
                    LinkSignal(peer.id, SignalRestart, peer.generation, "");
                }
            }
        }
        else if (peer.offerer && m_haveKey.load() && aNowMs >= peer.nextRetryMs)
        {
            CreateLink(peer, peer.generation + 1);
        }

        if (!connected && !peer.noLinkNoted.load() && aNowMs - peer.addedMs > kNoLinkNoteAfterMs)
        {
            peer.noLinkNoted.store(true);
            Note("No direct link to " + peer.name + " yet, still trying");
        }
    }

    if (aNowMs - m_lastPresenceMs >= kPresenceEveryMs)
    {
        m_lastPresenceMs = aNowMs;
        SendPresence(aNowMs);
    }
    LogLevels(aNowMs);
    ReadLiveTuning(aNowMs);
    UpdateAudioThreads(aNowMs);
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
    }
    g_liveTuning.roomDb.store(roomDb);
    g_liveTuning.ring.store(ring);
    g_liveTuning.echoDb.store(echoDb);
    g_liveTuning.ownDb.store(ownDb);
    Logf(LogInfo, "tuning: room %+.1f dB, ring times %.2f, echoes %+.1f dB, own voice %+.1f dB", roomDb, ring, echoDb, ownDb);
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
            Logf(LogInfo, "levels: %s arrived at %.0f dB (speech band %.1f lower) over %.0f s; %.0f m away, walls %.2f, way round %.0f m with %.0f bends, cabin %d, turned away %.2f, nearby gain %.2f",
                 peer->name.c_str(), db, bandBelow, seconds, peer->distance.load(), peer->occlusion.load(),
                 peer->wayRoundMeters.load(), peer->wayRoundBends.load(), peer->cabin.load(), peer->turnedAway.load(),
                 peer->nearGain.load());
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
    const uint8_t bits = static_cast<uint8_t>((m_muted.load() ? PresenceMuted : 0) | (m_radioOn.load() ? PresenceOnAir : 0));
    const uint32_t now = static_cast<uint32_t>(aNowMs);
    const uint8_t enclosure = ToByte(m_roomEnclosure.load(), 1.f);
    const uint8_t meters = ToByte(m_roomMeters.load(), kPresenceRoomMeters);
    const uint8_t decay = ToByte(m_roomDecay.load(), kPresenceRoomDecay);

    SharedLock lock(m_peersLock);
    for (const auto& peer : m_peers)
    {
        if (!peer->link || peer->link->State() != LinkState::Connected)
        {
            continue;
        }
        // The ping trick: they echo our send time and say how long they sat on it.
        uint8_t plain[kPresenceSize];
        plain[0] = bits;
        PutU32(plain + 1, now);
        const double echoAt = peer->echoAtMs.load();
        PutU32(plain + 5, peer->echoSent.load());
        PutU32(plain + 9, echoAt > 0.0 ? static_cast<uint32_t>(aNowMs - echoAt) : 0xFFFFFFFFu);
        plain[13] = enclosure;
        plain[14] = meters;
        plain[15] = decay;

        PacketInfo info;
        info.type = PacketPresence;
        info.counter = m_counter.fetch_add(1);
        info.sender = m_self.load();
        uint8_t packet[kMaxPacket];
        const size_t size = SealPacket(key, info, plain, sizeof(plain), packet);
        peer->link->Send(packet, size);
    }
}

void Engine::LinkPacket(PeerId aPeer, const uint8_t* aData, size_t aSize)
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
    peer->lastReceiveMs.store(now);

    if (info.type == PacketAudio)
    {
        if (plainSize > 2)
        {
            const uint16_t sequence = static_cast<uint16_t>(plain[0] | plain[1] << 8);
            peer->lastAudioMs.store(now);
            m_mixer.PushPacket(aPeer, sequence, info.flags, plain + 2, static_cast<int>(plainSize - 2));
        }
    }
    else if (info.type == PacketPresence && plainSize == kPresenceSize)
    {
        peer->remoteBits.store(plain[0]);
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

    const bool radio = m_radioOn.load();
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
    SharedLock lock(m_peersLock);
    for (const auto& peer : m_peers)
    {
        if (!peer->link)
        {
            continue;
        }
        // Your nearby voice goes only to people close enough to hear it; the radio goes to everyone.
        const bool nearby = peer->audibleNearby.load() && now - peer->spatialMs.load() < kPositionFreshMs;
        if (radio || nearby)
        {
            peer->link->Send(packet, size);
        }
    }
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
    m_acoustics.SetTalker(aPeer, aPosition, aCabin, nowMs - peer->lastAudioMs.load() < kTalkingRecentlyMs, nowMs);
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
    const SpatialOutput output = ComputeSpatial(input);
    m_mixer.SetSpatial(aPeer, output);
    peer->audibleNearby.store(output.audible);
    peer->spatialMs.store(nowMs);

    const float x = aPosition.x - m_listenerPosition.x;
    const float y = aPosition.y - m_listenerPosition.y;
    const float z = aPosition.z - m_listenerPosition.z;
    const float distance = std::sqrt(x * x + y * y + z * z);

    const float echoAmount = Clamp01(1.f - input.occlusion * kEchoOcclusion) * (1.f - input.sharedCabin) *
                             (1.f - input.separatedCabin) * (1.f - input.underwater) *
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

void Engine::SetRadio(bool aOn)
{
    if (m_radioOn.exchange(aOn) != aOn)
    {
        Tone(aOn ? kToneRadioOn : kToneRadioOff);
        Logf(LogInfo, "radio mic %s", aOn ? "on" : "off");
    }
}

void Engine::ToggleRadio()
{
    SetRadio(!m_radioOn.load());
}

void Engine::RadioKeyDown()
{
    // On at the press, so a held key talks from the first word.
    m_radioWasOnAtPress = m_radioOn.load();
    SetRadio(true);
}

void Engine::RadioKeyUp(double aHeldMs)
{
    if (m_radioWasOnAtPress || aHeldMs >= kHoldToTalkMs)
    {
        SetRadio(false);
    }
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
    const std::string radioEar = m_settings.Get("radio_ear");
    m_mixer.SetRadioEar(!headphones || radioEar == "both" ? RadioEar::Both
                        : radioEar == "right"             ? RadioEar::Right
                                                          : RadioEar::Left);

    // Temporary, to compare falloff curves by ear in a session. Only changes what this PC hears, and never the 40 m limit
    // that decides sending, so the players' games still agree.
    const std::string falloff = m_settings.Get("falloff_test");
    if (falloff != m_falloffChoice)
    {
        m_falloffChoice = falloff;
        const bool taper = falloff == "70t";
        const float share = falloff == "85" ? 0.85f : falloff == "70" || taper ? 0.7f : falloff == "50" ? 0.5f : 1.f;
        g_liveTuning.falloff.store(share);
        g_liveTuning.falloffTaper.store(taper);
        Logf(LogInfo, "falloff: %.0f%%%s", share * 100.f, taper ? " with taper" : share >= 1.f ? " (today)" : "");
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

std::vector<PeerView> Engine::Peers() const
{
    std::vector<PeerView> views;
    SharedLock lock(m_peersLock);
    views.reserve(m_peers.size());
    for (const auto& peer : m_peers)
    {
        PeerView view;
        view.id = peer->id;
        view.name = peer->name;
        if (peer->link && peer->link->State() == LinkState::Connected)
        {
            view.link = PeerLink::Linked;
        }
        else if (peer->noLinkNoted.load())
        {
            view.link = PeerLink::Failed;
        }
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
            if (peer->link && peer->link->State() == LinkState::Connected)
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
