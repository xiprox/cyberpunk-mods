#include "audio/mixer.hpp"

#include "audio/headset_link.hpp"
#include "audio/jitter.hpp"

#include <opus.h>

#include <cmath>
#include <cstring>

namespace nv
{
namespace
{
constexpr double kSpatialStaleMs = 1500.0;  // positions stop during loads; proximity fades out rather than freezes
constexpr double kTalkHoldMs = 300.0;       // how long a talker stays lit on the HUD after their last sound
constexpr double kSquelchAfterMs = 2000.0;  // a radio click only after this much radio silence from that talker
constexpr float kTalkEnergy = 1e-6f;
constexpr float kGainSlew = 0.15f;          // per sample block: new positions glide in instead of stepping
constexpr float kRadioFade = 0.005f;        // per sample: a few milliseconds, so the radio cuts off cleanly when they stop
constexpr float kRadioCutFade = 0.00008f;   // per sample: about a quarter of a second as a partner walks in or out of the radio's range
constexpr int kDelaySamples = 64;          // a little over the widest head delay, and a power of two
constexpr float kDelaySlewPerBlock = 4.f;   // samples: a fast glide would be heard as a pitch wobble
constexpr float kShadowRecalcRatio = 0.03f; // recomputing a filter is cheap, but not worth it per tiny move

// Echoes: up to about a third of a second, a tunnel's length away.
constexpr int kEchoSamples = 16384;         // a power of two
constexpr float kEchoToneHz = 6000.f;       // a bounce and the air on the way take the top off
constexpr float kEchoQuiet = 0.0002f;
constexpr float kEchoMaxSlew = 0.008f;      // of a sample per sample: a delay changing any faster is heard as a pitch change
constexpr float kEchoJumpSamples = 480.f;   // further off than this, it fades out and comes back in the right place
constexpr float kEchoFadePerSample = 1.f / 144.f; // 3 ms
constexpr float kEarLagSlewPerBlock = 1.f;

// Your own voice in your room: 9 dB under anyone else's there. 6 was chosen by ear in an underpass, then turned down 3 dB (user,
// 2026-11-10): it reaches you late by the mic's and the output's latency, which makes it stand out as an echo more than a room would.
constexpr float kOwnEchoGain = 0.35f;

// In the open you don't hear your own voice come back, unless you shout. Only somewhere closed in.
constexpr float kOwnEchoNeedsClosedFrom = 0.25f;
constexpr float kOwnEchoNeedsClosedTo = 0.6f;

// Your voice gets here about 70 ms late, after the mic and the sound card. A real wall's reflection of your own voice arrives
// sooner than that and blends into it. So a sound that dies quickly plays entirely after your word has ended, and you hear
// your word again. It only sounds like a room once the ring far outlasts the wait, so an ordinary room stays out of it, as it
// does in life unless you listen for it. A partner's voice has no such wait, and gets the room's sound everywhere.
constexpr float kOwnEchoNeedsDecayFrom = 0.5f;
constexpr float kOwnEchoNeedsDecayTo = 1.4f; // by ear, with the gain above: a concrete hallway at 0.8 s about -15 dB, an underpass at 1.6 s -6 dB
constexpr float kOwnEchoSlew = 0.1f;        // per block
constexpr uint32_t kOwnVoiceMaxBehind = kBlock * 4;

constexpr int kTheirRoomIdleBlocks = 700;   // a little longer than the longest tail

constexpr float kSlowRoomDecay = 2.2f;      // slow motion rings, wherever you are

// The earpiece is at your ear, so it suffers less from these than a voice across the room does.
constexpr float kRadioOpenHz = 20000.f;
constexpr float kRadioUnderwaterHz = 700.f;
constexpr float kRadioUnderwaterGain = 0.5f;
constexpr float kRadioSlowHz = 1400.f;
constexpr float kRadioSlowSend = 0.5f;
constexpr float kSlowRoomMeters = 20.f;     // slow motion feels like a big room, wherever you are

// What the listener's state does to the radio for this block.
struct RadioWorld
{
    float cutoffHz = kRadioOpenHz;
    float gain = 1.f;
    float send = 0.f;
};
} // namespace

class Voice
{
public:
    explicit Voice(PeerId aPeer)
        : peer(aPeer)
    {
        int error = 0;
        m_decoder = opus_decoder_create(kRate, 1, &error);
        if (error != OPUS_OK)
        {
            Logf(LogError, "mixer: Opus decoder failed: %s", opus_strerror(error));
            m_decoder = nullptr;
        }
        m_lowpass1.SetCutoff(16000.f);
        m_lowpass2.SetCutoff(16000.f);
        m_roomLowpass1.SetCutoff(16000.f);
        m_roomLowpass2.SetCutoff(16000.f);
        m_echoTone.SetCutoff(kEchoToneHz);
        m_echoLine.resize(kEchoSamples);
        m_statHigh.SetHighpass(300.f);
        m_statLow.SetLowpass(4000.f);
    }

    ~Voice()
    {
        if (m_decoder)
        {
            opus_decoder_destroy(m_decoder);
        }
    }

    void Render(float* aLeft, float* aRight, float* aSend, float* aRadioLeft, float* aRadioRight, TestRoute aTest,
                const RadioWorld& aWorld, double aNowMs);

    const PeerId peer;
    JitterBuffer jitter;

    std::atomic<float> gainLeft{0.f};
    std::atomic<float> gainRight{0.f};
    std::atomic<float> lowpassHz{16000.f};
    std::atomic<float> reverbSend{0.f};
    std::atomic<float> reverbLowpassHz{16000.f};
    std::atomic<float> theirRoomAmount{0.f};
    std::atomic<float> theirEnclosure{0.f};
    std::atomic<float> theirMeters{8.f};
    std::atomic<float> theirDecay{0.6f};
    std::array<std::array<std::atomic<float>, 5>, kEchoTaps> echoes{}; // delay, gain left and right, lag left and right
    std::atomic<float> delayLeft{0.f};
    std::atomic<float> delayRight{0.f};
    std::atomic<float> shadowLeftHz{SpatialOutput::kNoShadowHz};
    std::atomic<float> shadowRightHz{SpatialOutput::kNoShadowHz};
    std::atomic<bool> audible{false};
    std::atomic<double> spatialMs{-1e12};
    std::atomic<bool> muted{false};
    std::atomic<bool> radioCut{false};

    std::atomic<double> nearAtMs{-1e12};
    std::atomic<double> radioAtMs{-1e12};
    std::atomic<double> heardEnergy{0.0};
    std::atomic<double> heardBandEnergy{0.0};
    std::atomic<int> heardSamples{0};

private:
    struct EchoSlot
    {
        float delay = 0.f;
        float left = 0.f;
        float right = 0.f;
        float lagLeft = 0.f;
        float lagRight = 0.f;
        float fade = 1.f;
        bool jumping = false;
    };

    void NextFrame(double aNowMs);
    float ReadDelayed(float aDelay) const;
    float ReadEcho(float aDelay) const;

    OpusDecoder* m_decoder = nullptr;
    JitterFrame m_incoming;
    float m_pcm[kFrame]{};
    int m_position = kFrame;
    bool m_frameRadio = false;
    bool m_frameActive = false;

    OnePole m_lowpass1;
    OnePole m_lowpass2;
    float m_appliedCutoff = 16000.f;
    float m_delayLine[kDelaySamples]{};
    int m_delayWrite = 0;
    float m_currentDelayLeft = 0.f;
    float m_currentDelayRight = 0.f;
    OnePole m_shadowLeft;
    OnePole m_shadowRight;
    float m_appliedShadowLeft = 0.f;
    float m_appliedShadowRight = 0.f;
    float m_currentLeft = 0.f;
    float m_currentRight = 0.f;
    float m_currentSend = 0.f;

    OnePole m_roomLowpass1;
    OnePole m_roomLowpass2;
    float m_appliedRoomCutoff = 16000.f;

    OnePole m_echoTone;
    std::vector<float> m_echoLine;
    uint32_t m_echoWrite = 0;
    std::array<EchoSlot, kEchoTaps> m_echoSlots;

    RoomReverb m_theirRoom;
    float m_theirInput[kBlock]{};
    float m_theirLeft[kBlock]{};
    float m_theirRight[kBlock]{};
    float m_currentTheirs = 0.f;
    int m_theirIdleBlocks = kTheirRoomIdleBlocks;

    RadioEffect m_radio;
    OnePole m_radioWorld1;
    OnePole m_radioWorld2;
    float m_appliedRadioWorldHz = 0.f;
    float m_radioWorldGain = 1.f;
    Biquad m_statHigh;
    Biquad m_statLow;
    float m_radioGain = 0.f;
    float m_radioAllowed = 1.f;
    double m_lastRadioMs = -1e12;
};

void Voice::NextFrame(double aNowMs)
{
    jitter.Pull(aNowMs, m_incoming);
    m_position = 0;
    m_frameActive = m_incoming.kind != JitterFrame::None;
    m_frameRadio = (m_incoming.flags & kFlagRadio) != 0;

    int decoded = 0;
    if (m_decoder && m_frameActive)
    {
        if (m_incoming.startOfSpurt)
        {
            opus_decoder_ctl(m_decoder, OPUS_RESET_STATE);
        }
        switch (m_incoming.kind)
        {
        case JitterFrame::Packet:
            decoded = opus_decode_float(m_decoder, m_incoming.data, m_incoming.size, m_pcm, kFrame, 0);
            break;
        case JitterFrame::Repair:
            decoded = opus_decode_float(m_decoder, m_incoming.data, m_incoming.size, m_pcm, kFrame, 1);
            break;
        default:
            decoded = opus_decode_float(m_decoder, nullptr, 0, m_pcm, kFrame, 0);
            break;
        }
    }
    if (decoded != kFrame)
    {
        std::memset(m_pcm, 0, sizeof(m_pcm));
        m_frameActive = false;
    }
}

// Reads this many samples back from the newest one, between samples where needed.
float Voice::ReadDelayed(float aDelay) const
{
    const int whole = static_cast<int>(aDelay);
    const float part = aDelay - static_cast<float>(whole);
    const float newer = m_delayLine[(m_delayWrite - 1 - whole + kDelaySamples * 2) % kDelaySamples];
    const float older = m_delayLine[(m_delayWrite - 2 - whole + kDelaySamples * 2) % kDelaySamples];
    return newer + (older - newer) * part;
}

float Voice::ReadEcho(float aDelay) const
{
    const auto whole = static_cast<uint32_t>(aDelay);
    const float part = aDelay - static_cast<float>(whole);
    const float newer = m_echoLine[(m_echoWrite - 1u - whole) & (kEchoSamples - 1u)];
    const float older = m_echoLine[(m_echoWrite - 2u - whole) & (kEchoSamples - 1u)];
    return newer + (older - newer) * part;
}

void Voice::Render(float* aLeft, float* aRight, float* aSend, float* aRadioLeft, float* aRadioRight, TestRoute aTest,
                   const RadioWorld& aWorld, double aNowMs)
{
    const float playerVolume = muted.load() ? 0.f : 1.f;

    // Where the proximity path should be by the end of this block.
    const bool fresh = aNowMs - spatialMs.load() < kSpatialStaleMs;
    float targetLeft = fresh ? gainLeft.load() * playerVolume : 0.f;
    float targetRight = fresh ? gainRight.load() * playerVolume : 0.f;
    float targetSend = fresh ? reverbSend.load() * playerVolume : 0.f;
    float targetTheirs = fresh ? theirRoomAmount.load() : 0.f;
    bool echoesOn = fresh && playerVolume > 0.f;
    bool radioRoute = true;
    const bool radioCutHere = aTest == TestRoute::Off && fresh && radioCut.load();
    float targetDelayLeft = delayLeft.load();
    float targetDelayRight = delayRight.load();
    float targetShadowLeft = shadowLeftHz.load();
    float targetShadowRight = shadowRightHz.load();
    if (aTest != TestRoute::Off)
    {
        targetDelayLeft = targetDelayRight = 0.f; // hearing yourself comes from the middle of your head
        targetShadowLeft = targetShadowRight = SpatialOutput::kNoShadowHz;
        targetTheirs = 0.f;
        echoesOn = false;
    }
    if (aTest == TestRoute::Clean)
    {
        targetLeft = targetRight = 1.f;
        targetSend = 0.f;
        radioRoute = false;
    }
    else if (aTest == TestRoute::Radio)
    {
        targetLeft = targetRight = targetSend = 0.f;
    }

    const float cutoff = lowpassHz.load();
    if (std::fabs(cutoff - m_appliedCutoff) > 1.f)
    {
        m_appliedCutoff += (cutoff - m_appliedCutoff) * 0.25f;
        m_lowpass1.SetCutoff(m_appliedCutoff);
        m_lowpass2.SetCutoff(m_appliedCutoff);
    }
    const float roomCutoff = reverbLowpassHz.load();
    if (std::fabs(roomCutoff - m_appliedRoomCutoff) > 1.f)
    {
        m_appliedRoomCutoff += (roomCutoff - m_appliedRoomCutoff) * 0.25f;
        m_roomLowpass1.SetCutoff(m_appliedRoomCutoff);
        m_roomLowpass2.SetCutoff(m_appliedRoomCutoff);
    }

    if (std::fabs(targetShadowLeft - m_appliedShadowLeft) > m_appliedShadowLeft * kShadowRecalcRatio)
    {
        m_appliedShadowLeft = targetShadowLeft;
        m_shadowLeft.SetCutoff(targetShadowLeft);
    }
    if (std::fabs(targetShadowRight - m_appliedShadowRight) > m_appliedShadowRight * kShadowRecalcRatio)
    {
        m_appliedShadowRight = targetShadowRight;
        m_shadowRight.SetCutoff(targetShadowRight);
    }
    if (m_appliedRadioWorldHz <= 0.f)
    {
        m_appliedRadioWorldHz = aWorld.cutoffHz;
        m_radioWorld1.SetCutoff(m_appliedRadioWorldHz);
        m_radioWorld2.SetCutoff(m_appliedRadioWorldHz);
    }
    else if (std::fabs(aWorld.cutoffHz - m_appliedRadioWorldHz) > 1.f)
    {
        m_appliedRadioWorldHz += (aWorld.cutoffHz - m_appliedRadioWorldHz) * 0.25f;
        m_radioWorld1.SetCutoff(m_appliedRadioWorldHz);
        m_radioWorld2.SetCutoff(m_appliedRadioWorldHz);
    }

    const float delayStepLeft =
        std::clamp(targetDelayLeft - m_currentDelayLeft, -kDelaySlewPerBlock, kDelaySlewPerBlock) / kBlock;
    const float delayStepRight =
        std::clamp(targetDelayRight - m_currentDelayRight, -kDelaySlewPerBlock, kDelaySlewPerBlock) / kBlock;

    const float stepLeft = (targetLeft - m_currentLeft) * kGainSlew / kBlock;
    const float stepRight = (targetRight - m_currentRight) * kGainSlew / kBlock;
    const float stepSend = (targetSend - m_currentSend) * kGainSlew / kBlock;
    const float stepTheirs = (targetTheirs - m_currentTheirs) * kGainSlew / kBlock;

    // What each echo does over this block.
    std::array<float, kEchoTaps> echoDelayStep{};
    std::array<float, kEchoTaps> echoLeftStep{};
    std::array<float, kEchoTaps> echoRightStep{};
    std::array<float, kEchoTaps> echoFadeStep{};
    for (size_t slot = 0; slot < m_echoSlots.size(); ++slot)
    {
        EchoSlot& echo = m_echoSlots[slot];
        const float targetDelay = echoes[slot][0].load();
        const float wantLeft = echoesOn ? echoes[slot][1].load() : 0.f;
        const float wantRight = echoesOn ? echoes[slot][2].load() : 0.f;
        const bool silent = echo.left < kEchoQuiet && echo.right < kEchoQuiet;
        if (silent)
        {
            // Nothing's playing, so nobody hears it arrive somewhere new.
            echo.delay = targetDelay;
            echo.lagLeft = echoes[slot][3].load();
            echo.lagRight = echoes[slot][4].load();
            echo.fade = 1.f;
            echo.jumping = false;
        }
        else if (std::fabs(targetDelay - echo.delay) > kEchoJumpSamples)
        {
            echo.jumping = true;
        }
        echo.lagLeft += std::clamp(echoes[slot][3].load() - echo.lagLeft, -kEarLagSlewPerBlock, kEarLagSlewPerBlock);
        echo.lagRight += std::clamp(echoes[slot][4].load() - echo.lagRight, -kEarLagSlewPerBlock, kEarLagSlewPerBlock);
        const float maxMove = kEchoMaxSlew * kBlock;
        echoDelayStep[slot] = echo.jumping ? 0.f : std::clamp(targetDelay - echo.delay, -maxMove, maxMove) / kBlock;
        echoLeftStep[slot] = (wantLeft - echo.left) * kGainSlew / kBlock;
        echoRightStep[slot] = (wantRight - echo.right) * kGainSlew / kBlock;
        echoFadeStep[slot] = echo.jumping ? -kEchoFadePerSample : kEchoFadePerSample;
    }

    bool heardAny = false;
    double energy = 0.0;
    double bandEnergy = 0.0;
    for (int i = 0; i < kBlock; ++i)
    {
        if (m_position >= kFrame)
        {
            NextFrame(aNowMs);
            if (m_frameActive && m_frameRadio && radioRoute && !radioCutHere)
            {
                if (aNowMs - m_lastRadioMs > kSquelchAfterMs)
                {
                    m_radio.KeyUp();
                }
                m_lastRadioMs = aNowMs;
            }
        }
        const float sample = m_pcm[m_position++];
        heardAny = heardAny || std::fabs(sample) > kTalkEnergy;
        energy += static_cast<double>(sample) * sample;
        const float band = m_statLow.Process(m_statHigh.Process(sample));
        bandEnergy += static_cast<double>(band) * band;

        m_currentLeft += stepLeft;
        m_currentRight += stepRight;
        m_currentSend += stepSend;
        m_currentTheirs += stepTheirs;
        const float filtered = m_lowpass2.Lowpass(m_lowpass1.Lowpass(sample));
        const float roomHears = m_roomLowpass2.Lowpass(m_roomLowpass1.Lowpass(sample));
        m_delayLine[m_delayWrite] = filtered;
        m_delayWrite = (m_delayWrite + 1) % kDelaySamples;
        m_currentDelayLeft += delayStepLeft;
        m_currentDelayRight += delayStepRight;
        aLeft[i] += m_shadowLeft.Lowpass(ReadDelayed(m_currentDelayLeft)) * m_currentLeft;
        aRight[i] += m_shadowRight.Lowpass(ReadDelayed(m_currentDelayRight)) * m_currentRight;
        aSend[i] += roomHears * m_currentSend;
        m_theirInput[i] = filtered * m_currentTheirs;

        m_echoLine[m_echoWrite & (kEchoSamples - 1u)] = m_echoTone.Lowpass(roomHears);
        ++m_echoWrite;
        for (size_t slot = 0; slot < m_echoSlots.size(); ++slot)
        {
            EchoSlot& echo = m_echoSlots[slot];
            echo.delay += echoDelayStep[slot];
            echo.left += echoLeftStep[slot];
            echo.right += echoRightStep[slot];
            echo.fade = Clamp01(echo.fade + echoFadeStep[slot]);
            if (echo.left >= kEchoQuiet || echo.right >= kEchoQuiet)
            {
                aLeft[i] += ReadEcho(echo.delay + echo.lagLeft) * echo.left * echo.fade;
                aRight[i] += ReadEcho(echo.delay + echo.lagRight) * echo.right * echo.fade;
            }
        }

        const float radioTarget = m_frameActive && m_frameRadio && radioRoute ? 1.f : 0.f;
        m_radioGain += (radioTarget - m_radioGain) * kRadioFade;
        m_radioWorldGain += (aWorld.gain - m_radioWorldGain) * kRadioFade;
        m_radioAllowed += ((radioCutHere ? 0.f : 1.f) - m_radioAllowed) * kRadioCutFade;
        if (m_radioGain > 0.0005f || m_radio.IsClicking())
        {
            float heard = m_radio.Process(sample, m_radioGain);
            heard = m_radioWorld2.Lowpass(m_radioWorld1.Lowpass(heard)) * m_radioWorldGain * playerVolume * m_radioAllowed;
            aSend[i] += heard * aWorld.send;
            aRadioLeft[i] += heard * kRadioBothEarsGain;
            aRadioRight[i] += heard * kRadioBothEarsGain;
        }
    }

    for (size_t slot = 0; slot < m_echoSlots.size(); ++slot)
    {
        EchoSlot& echo = m_echoSlots[slot];
        if (echo.jumping && echo.fade <= 0.f)
        {
            echo.delay = echoes[slot][0].load();
            echo.jumping = false;
        }
    }

    // The room the talker's in comes the same way the voice does, so it plays at the voice's own level and from its direction.
    m_theirIdleBlocks = targetTheirs > 0.001f ? 0 : std::min(m_theirIdleBlocks + 1, kTheirRoomIdleBlocks);
    if (m_theirIdleBlocks < kTheirRoomIdleBlocks)
    {
        RoomSound theirs;
        theirs.enclosure = theirEnclosure.load();
        theirs.meters = theirMeters.load();
        theirs.decaySeconds = theirDecay.load();
        m_theirRoom.SetRoom(theirs);
        std::memset(m_theirLeft, 0, sizeof(m_theirLeft));
        std::memset(m_theirRight, 0, sizeof(m_theirRight));
        m_theirRoom.Process(m_theirInput, m_theirLeft, m_theirRight, kBlock);
        for (int i = 0; i < kBlock; ++i)
        {
            aLeft[i] += m_theirLeft[i] * m_currentLeft;
            aRight[i] += m_theirRight[i] * m_currentRight;
        }
    }

    if (heardAny)
    {
        heardEnergy.fetch_add(energy);
        heardBandEnergy.fetch_add(bandEnergy);
        heardSamples.fetch_add(kBlock);
        if (m_frameRadio && radioRoute && !radioCutHere)
        {
            radioAtMs.store(aNowMs);
        }
        if (std::max(targetLeft, targetRight) > 0.002f)
        {
            nearAtMs.store(aNowMs);
        }
    }
}

Mixer::Mixer() = default;
Mixer::~Mixer() = default;

std::shared_ptr<Voice> Mixer::Find(PeerId aPeer) const
{
    AcquireSRWLockShared(&m_lock);
    std::shared_ptr<Voice> found;
    for (const auto& voice : m_voices)
    {
        if (voice->peer == aPeer)
        {
            found = voice;
            break;
        }
    }
    ReleaseSRWLockShared(&m_lock);
    return found;
}

void Mixer::AddVoice(PeerId aPeer)
{
    if (Find(aPeer))
    {
        return;
    }
    auto voice = std::make_shared<Voice>(aPeer);
    AcquireSRWLockExclusive(&m_lock);
    m_voices.push_back(std::move(voice));
    ReleaseSRWLockExclusive(&m_lock);
}

void Mixer::RemoveVoice(PeerId aPeer)
{
    AcquireSRWLockExclusive(&m_lock);
    std::erase_if(m_voices, [aPeer](const auto& aVoice) { return aVoice->peer == aPeer; });
    ReleaseSRWLockExclusive(&m_lock);
}

void Mixer::RemoveAll()
{
    AcquireSRWLockExclusive(&m_lock);
    m_voices.clear();
    ReleaseSRWLockExclusive(&m_lock);
}

void Mixer::PushPacket(PeerId aPeer, uint16_t aSequence, uint8_t aFlags, const uint8_t* aOpus, int aSize)
{
    if (const auto voice = Find(aPeer))
    {
        voice->jitter.Push(aSequence, aFlags, aOpus, aSize, NowMs());
    }
}

void Mixer::SetSpatial(PeerId aPeer, const SpatialOutput& aSpatial)
{
    if (const auto voice = Find(aPeer))
    {
        voice->gainLeft.store(aSpatial.gainLeft);
        voice->gainRight.store(aSpatial.gainRight);
        voice->lowpassHz.store(aSpatial.lowpassHz);
        voice->reverbSend.store(aSpatial.reverbSend);
        voice->reverbLowpassHz.store(aSpatial.reverbLowpassHz);
        voice->theirRoomAmount.store(aSpatial.theirRoom);
        voice->delayLeft.store(aSpatial.delayLeft);
        voice->delayRight.store(aSpatial.delayRight);
        voice->shadowLeftHz.store(aSpatial.shadowLeftHz);
        voice->shadowRightHz.store(aSpatial.shadowRightHz);
        voice->audible.store(aSpatial.audible);
        voice->spatialMs.store(NowMs());
    }
}

void Mixer::SetEchoes(PeerId aPeer, const EchoSet& aEchoes)
{
    if (const auto voice = Find(aPeer))
    {
        for (size_t slot = 0; slot < aEchoes.size(); ++slot)
        {
            const EchoTap& tap = aEchoes[slot];
            voice->echoes[slot][0].store(tap.delaySamples);
            voice->echoes[slot][1].store(tap.gainLeft);
            voice->echoes[slot][2].store(tap.gainRight);
            voice->echoes[slot][3].store(tap.lagLeft);
            voice->echoes[slot][4].store(tap.lagRight);
        }
    }
}

void Mixer::SetTheirRoom(PeerId aPeer, const RoomSound& aRoom)
{
    if (const auto voice = Find(aPeer))
    {
        voice->theirEnclosure.store(aRoom.enclosure);
        voice->theirMeters.store(aRoom.meters);
        voice->theirDecay.store(aRoom.decaySeconds);
    }
}

void Mixer::SetOwnEcho(float aAmount)
{
    m_ownEchoTarget.store(Clamp01(aAmount));
}

void Mixer::PushOwnVoice(const float* aSamples, int aCount)
{
    uint32_t write = m_ownWrite.load(std::memory_order_relaxed);
    const uint32_t read = m_ownRead.load(std::memory_order_acquire);
    const auto room = static_cast<int>(kOwnVoiceSamples - (write - read));
    const int count = std::min(aCount, room); // nobody's reading while there's no output, so this just stops filling
    for (int i = 0; i < count; ++i)
    {
        m_ownVoice[write % kOwnVoiceSamples] = aSamples[i];
        ++write;
    }
    m_ownWrite.store(write, std::memory_order_release);
}

void Mixer::SetRadioCut(PeerId aPeer, bool aCut)
{
    if (const auto voice = Find(aPeer))
    {
        voice->radioCut.store(aCut);
    }
}

void Mixer::SetPeerMuted(PeerId aPeer, bool aMuted)
{
    if (const auto voice = Find(aPeer))
    {
        voice->muted.store(aMuted);
    }
}

void Mixer::SetMasterGain(float aGain)
{
    m_masterTarget.store(aGain);
}

void Mixer::TakeHeardStats(PeerId aPeer, float& aDb, float& aBandBelowDb, float& aSeconds) const
{
    aDb = -100.f;
    aBandBelowDb = 0.f;
    aSeconds = 0.f;
    if (const auto voice = Find(aPeer))
    {
        const double energy = voice->heardEnergy.exchange(0.0);
        const double bandEnergy = voice->heardBandEnergy.exchange(0.0);
        const int samples = voice->heardSamples.exchange(0);
        if (samples > 0)
        {
            aDb = 10.f * static_cast<float>(std::log10(std::max(energy / samples, 1e-12)));
            aBandBelowDb = aDb - 10.f * static_cast<float>(std::log10(std::max(bandEnergy / samples, 1e-12)));
            aSeconds = static_cast<float>(samples) / kRate;
        }
    }
}

void Mixer::SetRoom(const RoomSound& aRoom)
{
    m_enclosure.store(aRoom.enclosure);
    m_roomMeters.store(aRoom.meters);
    m_roomDecay.store(aRoom.decaySeconds);
}

void Mixer::SetTestRoute(TestRoute aRoute)
{
    m_testRoute.store(static_cast<int>(aRoute));
}

void Mixer::SetListenerEffects(float aUnderwater, float aSlowMotion)
{
    m_underwater.store(Clamp01(aUnderwater));
    m_slowMotion.store(Clamp01(aSlowMotion));
}

void Mixer::PlayTone(float aHz, float aMs, float aVolume)
{
    AcquireSRWLockExclusive(&m_toneLock);
    m_pendingTone.hz = aHz;
    m_pendingTone.volume = aVolume;
    m_pendingTone.total = static_cast<int>(aMs * kRate / 1000.f);
    m_pendingTone.done = 0;
    m_tonePending = true;
    ReleaseSRWLockExclusive(&m_toneLock);
}

void Mixer::TalkState(PeerId aPeer, bool& aNear, bool& aRadio) const
{
    aNear = false;
    aRadio = false;
    if (const auto voice = Find(aPeer))
    {
        const double now = NowMs();
        aNear = now - voice->nearAtMs.load() < kTalkHoldMs;
        aRadio = now - voice->radioAtMs.load() < kTalkHoldMs;
    }
}

void Mixer::Render(float* aStereo)
{
    std::memset(m_left, 0, sizeof(m_left));
    std::memset(m_right, 0, sizeof(m_right));
    std::memset(m_send, 0, sizeof(m_send));
    std::memset(m_radioLeft, 0, sizeof(m_radioLeft));
    std::memset(m_radioRight, 0, sizeof(m_radioRight));

    AcquireSRWLockShared(&m_lock);
    m_renderList = m_voices;
    ReleaseSRWLockShared(&m_lock);

    const double now = NowMs();
    const auto test = static_cast<TestRoute>(m_testRoute.load());
    const float underwater = m_underwater.load();
    const float slow = m_slowMotion.load();
    RadioWorld world;
    world.cutoffHz = kRadioOpenHz * std::pow(kRadioSlowHz / kRadioOpenHz, slow) *
                     std::pow(kRadioUnderwaterHz / kRadioOpenHz, underwater);
    world.cutoffHz = std::max(world.cutoffHz, kRadioUnderwaterHz);
    world.gain = 1.f + (kRadioUnderwaterGain - 1.f) * underwater;
    world.send = kRadioSlowSend * slow * (1.f - underwater);
    for (const auto& voice : m_renderList)
    {
        const TestRoute route = voice->peer == kSelfVoice ? test : TestRoute::Off;
        voice->Render(m_left, m_right, m_send, m_radioLeft, m_radioRight, route, world, now);
    }
    m_renderList.clear();

    // Your own voice, as far as the room is concerned. It can run a little ahead or behind, so it's kept from falling far
    // behind: a late tail would be heard as a separate voice.
    const uint32_t ownWrite = m_ownWrite.load(std::memory_order_acquire);
    uint32_t ownRead = m_ownRead.load(std::memory_order_relaxed);
    if (ownWrite - ownRead > kOwnVoiceMaxBehind)
    {
        ownRead = ownWrite - kBlock;
    }
    const float ownRings = Clamp01((m_roomDecay.load() - kOwnEchoNeedsDecayFrom) / (kOwnEchoNeedsDecayTo - kOwnEchoNeedsDecayFrom));
    const float ownClosedIn = Clamp01((m_enclosure.load() - kOwnEchoNeedsClosedFrom) / (kOwnEchoNeedsClosedTo - kOwnEchoNeedsClosedFrom));
    const float ownTarget = m_ownEchoTarget.load() * kOwnEchoGain * ownRings * ownClosedIn * std::pow(10.f, g_liveTuning.ownDb.load() / 20.f);
    const float ownStep = (ownTarget - m_ownEcho) * kOwnEchoSlew / kBlock;
    for (int i = 0; i < kBlock; ++i)
    {
        m_ownEcho += ownStep;
        if (ownRead != ownWrite)
        {
            m_send[i] += m_ownVoice[ownRead % kOwnVoiceSamples] * m_ownEcho;
            ++ownRead;
        }
    }
    m_ownRead.store(ownRead, std::memory_order_release);

    RoomSound room;
    const float enclosure = m_enclosure.load();
    const float roomMeters = m_roomMeters.load();
    const float roomDecay = m_roomDecay.load();
    room.enclosure = enclosure + (1.f - enclosure) * slow;
    room.meters = roomMeters + (kSlowRoomMeters - roomMeters) * slow;
    room.decaySeconds = roomDecay + (std::max(roomDecay, kSlowRoomDecay) - roomDecay) * slow;
    m_reverb.SetRoom(room);
    m_reverb.Process(m_send, m_left, m_right, kBlock);

    // Nearby voices and their rooms are outside sounds, heard as the Headset mod hears the world; the radio plays inside it.
    ProcessVoicesThroughHeadset(m_left, m_right, kBlock);
    for (int i = 0; i < kBlock; ++i)
    {
        m_left[i] += m_radioLeft[i];
        m_right[i] += m_radioRight[i];
    }

    const float masterStep = (m_masterTarget.load() - m_masterCurrent) / kBlock;
    for (int i = 0; i < kBlock; ++i)
    {
        m_masterCurrent += masterStep;
        m_left[i] *= m_masterCurrent;
        m_right[i] *= m_masterCurrent;
    }

    if (TryAcquireSRWLockExclusive(&m_toneLock))
    {
        if (m_tonePending)
        {
            m_tone = m_pendingTone;
            m_tonePending = false;
        }
        ReleaseSRWLockExclusive(&m_toneLock);
    }
    for (int i = 0; i < kBlock && m_tone.done < m_tone.total; ++i)
    {
        const float progress = static_cast<float>(m_tone.done) / static_cast<float>(m_tone.total);
        // A sine shaped window keeps the beep from clicking at either end.
        const float window = std::sin(kPi * progress);
        const float phase = 2.f * kPi * m_tone.hz * static_cast<float>(m_tone.done) / kRate;
        const float sample = std::sin(phase) * window * m_tone.volume;
        m_left[i] += sample;
        m_right[i] += sample;
        ++m_tone.done;
    }

    for (int i = 0; i < kBlock; ++i)
    {
        aStereo[i * 2] = SoftClip(m_left[i]);
        aStereo[i * 2 + 1] = SoftClip(m_right[i]);
    }
}
} // namespace nv
