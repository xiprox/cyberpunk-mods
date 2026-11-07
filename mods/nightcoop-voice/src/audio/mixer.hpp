// Plays every talker: each packet is decoded and sent down the proximity path, the radio path, or both, then mixed.
#pragma once

#include "audio/acoustics.hpp"
#include "audio/dsp.hpp"
#include "audio/radio.hpp"
#include "audio/spatial.hpp"

#include <windows.h>

#include <atomic>
#include <memory>
#include <vector>

namespace nv
{
class JitterBuffer;
class Voice;

enum class TestRoute : int
{
    Off = 0,
    Clean = 1,
    Radio = 2,
};

class Mixer
{
public:
    Mixer();
    ~Mixer();

    Mixer(const Mixer&) = delete;
    Mixer& operator=(const Mixer&) = delete;

    void AddVoice(PeerId aPeer);
    void RemoveVoice(PeerId aPeer);
    void RemoveAll();

    // From the network thread. aOpus is one 20 ms frame.
    void PushPacket(PeerId aPeer, uint16_t aSequence, uint8_t aFlags, const uint8_t* aOpus, int aSize);

    // From the game thread. A voice with no fresh position plays no proximity audio.
    void SetSpatial(PeerId aPeer, const SpatialOutput& aSpatial);
    void SetEchoes(PeerId aPeer, const EchoSet& aEchoes);
    void SetPeerMuted(PeerId aPeer, bool aMuted);
    void SetMasterGain(float aGain); // from AutoMix: one gain for every voice, not the confirmation beeps
    void SetRoom(const RoomSound& aRoom);
    // The room around a talker, as they measured it. From the network thread.
    void SetTheirRoom(PeerId aPeer, const RoomSound& aRoom);
    // Your own voice in the room around you: the room only, since you already hear yourself. 0 .. 1.
    void SetOwnEcho(float aAmount);
    // From the mic thread. Only ever heard as the room's sound, so a gap or a dropped block goes unnoticed.
    void PushOwnVoice(const float* aSamples, int aCount);
    void SetTestRoute(TestRoute aRoute);
    void SetRadioEar(RadioEar aEar);
    // What the listener's own state does to the radio and the room. Nearby voices get theirs from SetSpatial.
    void SetListenerEffects(float aUnderwater, float aSlowMotion);

    // A short confirmation beep, heard only by this player.
    void PlayTone(float aHz, float aMs, float aVolume);

    // What this talker is heard through right now.
    void TalkState(PeerId aPeer, bool& aNear, bool& aRadio) const;

    // How loud this talker's speech has arrived, before any effect or gain here, since the last call, and how far its
    // speech frequencies sit below the whole signal. For the log.
    void TakeHeardStats(PeerId aPeer, float& aDb, float& aBandBelowDb, float& aSeconds) const;

    // aStereo holds kBlock interleaved frames.
    void Render(float* aStereo);

private:
    struct Tone
    {
        float hz = 0.f;
        float volume = 0.f;
        int total = 0;
        int done = 0;
    };

    std::shared_ptr<Voice> Find(PeerId aPeer) const;

    mutable SRWLOCK m_lock = SRWLOCK_INIT;
    std::vector<std::shared_ptr<Voice>> m_voices;
    std::vector<std::shared_ptr<Voice>> m_renderList;

    std::atomic<float> m_masterTarget{1.f};
    float m_masterCurrent = 1.f;
    std::atomic<float> m_enclosure{0.f};
    std::atomic<float> m_roomMeters{8.f};
    std::atomic<float> m_roomDecay{0.6f};
    std::atomic<int> m_testRoute{0};
    std::atomic<int> m_radioEar{static_cast<int>(RadioEar::Left)};
    std::atomic<float> m_underwater{0.f};
    std::atomic<float> m_slowMotion{0.f};

    SRWLOCK m_toneLock = SRWLOCK_INIT;
    Tone m_pendingTone;
    bool m_tonePending = false;
    Tone m_tone;

    RoomReverb m_reverb;
    float m_left[kBlock]{};
    float m_right[kBlock]{};
    float m_send[kBlock]{};

    // One writer, the mic thread, and one reader, the render thread.
    static constexpr int kOwnVoiceSamples = 4096;
    std::vector<float> m_ownVoice = std::vector<float>(kOwnVoiceSamples);
    std::atomic<uint32_t> m_ownWrite{0};
    std::atomic<uint32_t> m_ownRead{0};
    std::atomic<float> m_ownEchoTarget{0.f};
    float m_ownEcho = 0.f;
};
} // namespace nv
