// The voice mod without the game: who is connected, what goes where, and the audio threads. The game side (or the test
// program) tells it about players and positions, and carries its setup messages and the Relay over NightCoop.
//
// Voice goes to each partner on one of two paths. Direct: the hole-punched link, while it's connected and hearing from
// them. The Relay: otherwise, the same sealed packets in a NightCoop channel message, two 20 ms frames to a message.
// Each game picks for itself and takes both paths at all times, so nothing has to be agreed. "Always" in Settings puts
// every pair with this player on the Relay: it makes no direct links, and tells partners so in its presence.
#pragma once

#include "audio/automix.hpp"
#include "audio/car.hpp"
#include "audio/mic.hpp"
#include "audio/mixer.hpp"
#include "core/settings.hpp"
#include "net/link.hpp"
#include "net/packet.hpp"

#include <windows.h>

#include <atomic>
#include <condition_variable>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace nv
{
enum class PeerLink : int
{
    Connecting = 1,
    Linked = 2,
    Failed = 3,
};

struct PeerView
{
    PeerId id = 0;
    std::string name;
    PeerLink link = PeerLink::Connecting; // the direct link
    bool relay = false;  // no direct link, and the Relay is getting their voice through
    bool talkingNear = false;
    bool talkingRadio = false;
    bool muted = false;  // they muted themselves
    bool onAir = false;  // their radio mic is on
    int pingMs = -1;     // the round trip of whichever path carries it
};

// How a Relay message fared with NightCoop. It's never retried: voice that can't go now is dropped.
enum class RelaySend : int
{
    Sent,
    Limit,   // over NightCoop's rate limit (NCSDK_E_LIMIT)
    NotNow,  // NightCoop can't send to them just now (NCSDK_E_STATE: a load, or their mod list hasn't come)
    Refused, // anything else
};

// The most one Relay message may hold: NightCoop's limit for an unreliable message (NCSDK_UNRELIABLE_MAX).
constexpr size_t kRelayMaxMessage = 1024;

// Counts since the partner was added, for the log and the test program.
struct PathStats
{
    uint32_t heardDirect = 0;   // audio frames from them, by the path they came
    uint32_t heardRelay = 0;
    uint32_t duplicates = 0;    // audio frames that came a second time, dropped
    uint32_t stale = 0;         // Relay frames that came far too late to play, dropped
    uint32_t relayMessages = 0; // Relay messages we sent them
    uint32_t relayFrames = 0;   // audio frames in those
    uint32_t refusedLimit = 0;  // messages NightCoop refused for its rate limit, their frames dropped
    uint32_t refusedNotNow = 0;
    uint32_t refusedOther = 0;
    uint32_t tooOld = 0;        // audio frames dropped before sending, after waiting through a load or a hitch
};

class Engine final : public LinkSink
{
public:
    // aUseDevices false: no real mic or speakers, for the test program (see InjectMic and GetMixer).
    Engine(Settings& aSettings, bool aUseDevices = true);
    ~Engine() override;

    Engine(const Engine&) = delete;
    Engine& operator=(const Engine&) = delete;

    // ---- session, from one thread (the game thread)
    void SessionStart(PeerId aSelf);
    void SessionEnd();
    void SetKey(const uint8_t* aKey, size_t aSize);
    void AddPeer(PeerId aPeer, const std::string& aName);
    void RemovePeer(PeerId aPeer);
    void SetPeerName(PeerId aPeer, const std::string& aName);
    void OnSignal(PeerId aFrom, const uint8_t* aData, size_t aSize);

    // aSend returns false to keep that message and the rest for that player for the next try; other players' go on.
    void DrainSignals(const std::function<bool(PeerId, const std::vector<uint8_t>&)>& aSend);
    void DrainNotes(const std::function<void(const std::string&)>& aShow);

    // ---- the Relay, from the game thread only: NightCoop's SDK may be called there and nowhere else.
    // Every frame: hands aSend the messages that are ready, one partner's in order.
    void DrainRelay(const std::function<RelaySend(PeerId, const uint8_t*, size_t)>& aSend);
    // A Relay message from a partner. False if they aren't known here yet (their packets are dropped until they are).
    bool OnRelay(PeerId aFrom, const uint8_t* aData, size_t aSize);

    // ---- positions, from the game thread
    void SetListener(const Vec3& aPosition, const Vec3& aForward, const Vec3& aRight);
    void SetPeerSpatial(PeerId aPeer, const Vec3& aPosition, const Vec3& aForward, int aCabin);
    void SetListenerState(bool aUnderwater, float aWorldSpeed, bool aInCar);
    // While our game has us in combat, the radio mic is on (RadioMic).
    void SetInCombat(bool aInCombat);
    void SetGameMaster(float aPercent);

    // ---- cars, from the game thread. aOwner is a partner's id, or kOurCar. A closed car's key is anything that tells it
    // apart from another; 0 means not in one.
    static constexpr PeerId kOurCar = static_cast<PeerId>(-1);
    // Whether the owner's car (aKey) still needs describing, part by part, between BeginCar and FinishCar.
    bool CarNeedsParts(PeerId aOwner, uint32_t aKey);
    void BeginCar(PeerId aOwner, uint32_t aKey);
    void AddCarPart(PeerId aOwner, int aGlass, int aDoor, const std::string& aName, uint64_t aMesh, const Vec3& aPivot);
    void FinishCar(PeerId aOwner, const std::string& aAppearance);
    // The car we sit in, where our head is, and what our game says is open; partners hear of changes at once.
    void SetOurCar(uint32_t aKey, const CarFrame& aFrame, const Vec3& aHead, const CarStates& aStates);
    // The car a partner sits in, as it stands in our world; what's open on it comes from their presence.
    void SetPeerCar(PeerId aPeer, uint32_t aKey, const CarFrame& aFrame);

    // ---- sound rays, from the game thread: it casts them, and everything else happens here
    bool NextSoundRay(RayRequest& aRequest)
    {
        return m_acoustics.NextRay(aRequest, NowMs());
    }
    void ReportSoundRay(const RayAnswer& aAnswer)
    {
        m_acoustics.ReportRay(aAnswer);
    }
    void LogAcoustics()
    {
        m_acoustics.LogStats();
    }

    // ---- controls, from any thread
    void ToggleMute();
    void RadioKeyDown();
    void RadioKeyUp();
    void SetTest(int aRoute);     // TestRoute: hear yourself, with no session needed
    void ApplySettings();         // re-read everything from Settings

    // ---- state for the HUD and the menus, from any thread
    std::vector<PeerView> Peers() const;
    PathStats Stats(PeerId aPeer) const;
    bool RelayAlways() const
    {
        return m_relayAlways.load();
    }
    bool InSession() const
    {
        return m_inSession.load();
    }
    bool Muted() const
    {
        return m_muted.load();
    }
    bool RadioOn() const;
    float MicLevel() const
    {
        return m_mic->Level();
    }
    bool GateOpen() const
    {
        return m_mic->GateOpen();
    }
    bool AudioRunning() const
    {
        return m_audioRunning.load();
    }

    // ---- for the test program
    void InjectMic(const float* aMono, int aCount);
    Mixer& GetMixer()
    {
        return m_mixer;
    }

    // LinkSink
    void LinkSignal(PeerId aPeer, uint8_t aKind, uint32_t aGeneration, const std::string& aText) override;
    void LinkPacket(PeerId aPeer, const uint8_t* aData, size_t aSize) override;

private:
    struct Peer;

    void Post(std::function<void()> aWork);
    void WorkerLoop();
    void Tick(double aNowMs);
    void TickDirect(Peer& aPeer, double aNowMs);
    void TickPath(Peer& aPeer, double aNowMs);
    void SendPresence(double aNowMs);
    void LogLevels(double aNowMs);
    void LogRelay(double aNowMs);
    void ReceivePacket(PeerId aPeer, const uint8_t* aData, size_t aSize, bool aRelay, bool aStale);
    // Sends one sealed packet to one partner by their path; the caller holds m_peersLock.
    void SendToPeer(Peer& aPeer, const uint8_t* aPacket, size_t aSize, bool aAudio, double aNowMs);
    void RelayRefusedForRate(double aNowMs, const Peer& aPeer, int aFrames);
    void ReadLiveTuning(double aNowMs);
    std::string AutoGainKey();
    void SaveAutoGain();
    void UpdateAudioThreads(double aNowMs);
    void StartAudioThreads();
    void StopAudioThreads();
    void CaptureLoop();
    void RenderLoop();

    std::shared_ptr<Peer> FindPeer(PeerId aPeer) const;
    Car* CarOf(PeerId aOwner, std::shared_ptr<Peer>& aKeep); // ours, or a partner's kept alive by aKeep
    void CreateLink(Peer& aPeer, uint32_t aGeneration);
    void DestroyLink(Peer& aPeer, const char* aWhy);
    void HandleSignal(Peer& aPeer, uint8_t aKind, uint32_t aGeneration, const std::string& aText);
    void Note(const std::string& aText);
    void ApplyPeerMix(const Peer& aPeer);
    void OnMicPacket(const uint8_t* aOpus, int aSize, bool aSpurt);
    // Changes the radio mic under its lock, then logs it and tells partners if that turned it on or off. aTone plays the radio's
    // on or off tone too: only the key does, since combat starting and ending would beep through every fight (user, 2026-11-15).
    void ChangeRadio(const std::function<bool(RadioMic&, double)>& aChange, bool aTone);
    void Tone(float aHz);

    Settings& m_settings;
    const bool m_useDevices;
    Mixer m_mixer;
    AutoMix m_autoMix;
    std::unique_ptr<MicProcessor> m_mic;

    // Peers: added and removed on the worker thread, read everywhere. Never held across juice_destroy.
    mutable SRWLOCK m_peersLock = SRWLOCK_INIT;
    std::vector<std::shared_ptr<Peer>> m_peers;

    std::atomic<PeerId> m_self{0};
    std::atomic<bool> m_inSession{false};

    mutable SRWLOCK m_keyLock = SRWLOCK_INIT;
    VoiceKey m_key{};
    std::atomic<bool> m_haveKey{false};

    std::atomic<bool> m_muted{false};
    // The key thread, the game thread and the mic all touch it.
    mutable std::mutex m_radioMutex;
    RadioMic m_radioMic;
    std::atomic<bool> m_relayAlways{false};
    std::atomic<int> m_relayAudience{0}; // partners on the Relay who should have heard the last frame

    // Game thread only: packing more frames into a message for a while after NightCoop refused one for its rate.
    int m_relayExtraFrames = 0;
    double m_relayLastLimitMs = -1e12;
    double m_relayLastRaiseMs = -1e12;
    double m_lastRelayLogMs = 0.0; // worker thread
    std::atomic<int> m_testRoute{0};

    uint16_t m_sequence = 0;
    std::atomic<uint32_t> m_counter{0};
    int m_stunCursor = 0;

    // Listener, for SetPeerSpatial.
    Vec3 m_listenerPosition;
    Vec3 m_listenerForward{0.f, 1.f, 0.f};
    Vec3 m_listenerRight{1.f, 0.f, 0.f};
    std::atomic<bool> m_headphones{true};
    ListenerEase m_listenerEase; // game thread only
    Acoustics m_acoustics;       // game thread only

    // The car we sit in. Game thread only, but for m_ourCarBits, which presence sends.
    Car m_ourCar;
    uint32_t m_ourCarKey = 0;
    Vec3 m_ourHead;
    CarStates m_ourCarStates;
    std::atomic<uint64_t> m_ourCarBits{0};

    // The room we're in, as our partners hear about it.
    std::atomic<float> m_roomEnclosure{0.f};
    std::atomic<float> m_roomMeters{8.f};
    std::atomic<float> m_roomDecay{0.6f};

    // The worker thread and what it's asked to do.
    std::mutex m_workMutex;
    std::condition_variable m_workReady;
    std::deque<std::function<void()>> m_work;
    std::atomic<bool> m_stopWorker{false};
    std::thread m_worker;
    double m_lastPresenceMs = 0.0;
    double m_lastLevelsMs = 0.0;
    double m_lastTuningCheckMs = 0.0;
    int64_t m_tuningFileTime = -1;
    float m_savedAutoGainDb = 0.f;

    std::mutex m_outMutex;
    std::deque<std::pair<PeerId, std::vector<uint8_t>>> m_outgoing;
    std::vector<std::string> m_notes;

    // Audio threads run only while someone is linked.
    std::atomic<bool> m_audioRunning{false};
    std::atomic<bool> m_stopAudio{false};
    std::thread m_captureThread;
    std::thread m_renderThread;
    double m_audioUnneededSinceMs = -1.0;

    std::mutex m_deviceMutex;
    std::string m_micDevice;
    std::string m_outputDevice;
    std::atomic<uint32_t> m_deviceGeneration{0};
    std::atomic<bool> m_echoOn{false};
};
} // namespace nv
