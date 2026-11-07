// The voice mod without the game: who is connected, what goes where, and the audio threads. The game side (or the test
// program) tells it about players and positions, and carries its setup messages over NightCoop.
#pragma once

#include "audio/automix.hpp"
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
    PeerLink link = PeerLink::Connecting;
    bool talkingNear = false;
    bool talkingRadio = false;
    bool muted = false;  // they muted themselves
    bool onAir = false;  // their radio mic is on
    int pingMs = -1;
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

    // ---- positions, from the game thread
    void SetListener(const Vec3& aPosition, const Vec3& aForward, const Vec3& aRight);
    void SetPeerSpatial(PeerId aPeer, const Vec3& aPosition, const Vec3& aForward, int aCabin);
    void SetListenerState(bool aUnderwater, float aWorldSpeed, bool aInCar);
    void SetGameMaster(float aPercent);

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
    void ToggleRadio();
    void RadioKeyDown();
    void RadioKeyUp(double aHeldMs);
    void SetTest(int aRoute);     // TestRoute: hear yourself, with no session needed
    void ApplySettings();         // re-read everything from Settings

    // ---- state for the HUD and the menus, from any thread
    std::vector<PeerView> Peers() const;
    bool InSession() const
    {
        return m_inSession.load();
    }
    bool Muted() const
    {
        return m_muted.load();
    }
    bool RadioOn() const
    {
        return m_radioOn.load();
    }
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
    void SendPresence(double aNowMs);
    void LogLevels(double aNowMs);
    void ReadLiveTuning(double aNowMs);
    std::string AutoGainKey();
    void SaveAutoGain();
    void UpdateAudioThreads(double aNowMs);
    void StartAudioThreads();
    void StopAudioThreads();
    void CaptureLoop();
    void RenderLoop();

    std::shared_ptr<Peer> FindPeer(PeerId aPeer) const;
    void CreateLink(Peer& aPeer, uint32_t aGeneration);
    void DestroyLink(Peer& aPeer);
    void HandleSignal(Peer& aPeer, uint8_t aKind, uint32_t aGeneration, const std::string& aText);
    void Note(const std::string& aText);
    void ApplyPeerMix(const Peer& aPeer);
    void OnMicPacket(const uint8_t* aOpus, int aSize, bool aSpurt);
    void SetRadio(bool aOn);
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
    std::atomic<bool> m_radioOn{false};
    bool m_radioWasOnAtPress = false;
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
    std::string m_falloffChoice = "unset"; // temporary, so the log says which falloff curve was on
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
