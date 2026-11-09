#include "wwise/effect.hpp"

#include "core/common.hpp"
#include "headset/clamp.hpp"
#include "headset/control.hpp"
#include "headset/sound.hpp"
#include "wwise/ak.hpp"
#include "wwise/places.hpp"

#include <windows.h>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstring>
#include <new>

namespace hs
{
namespace
{
constexpr float kWearSeconds = 0.2f; // putting it on or taking it off never clicks
constexpr float kIgnoreLevel = 0.1f; // a detector this far under the threshold can't add to a clamp
constexpr double kFreshMs = 15.0;    // a detector frame written longer ago than this is from before a clamp woke up

constexpr float kLiftRatio = 0.5f;      // 1 dB up for every 2 dB further under
constexpr float kLiftMostDb = 6.f;
constexpr float kLiftFloorBelowDb = 32.f; // this far under the lift's level it's silence rather than a quiet sound
constexpr float kLiftDownMs = 20.f;     // a sound getting louder loses its lift fast
constexpr float kLiftUpMs = 400.f;      // and quiet gains it slowly
constexpr double kLevelFreshMs = 40.0;  // a bus that's said nothing for this long has stopped

// One detector's latest audio frame, written by that bus's effect and read by every clamp. Two slots, so a clamp reading a
// frame isn't overwriting-in-progress by the next one.
struct TrackSlot
{
    uint32_t frames = 0;
    float loudest = 0.f;
    float level[kMaxFrames] = {};
};
struct Track
{
    TrackSlot slots[2];
    std::atomic<uint64_t> sequence{0};
    std::atomic<double> writtenMs{0.0};
};
Track g_tracks[kDetectorCount];

// The talk-through's lift listens to everything its microphones pick up, which is spread over all the clamp buses.
struct LevelSlot
{
    std::atomic<float> power{0.f};
    std::atomic<double> atMs{-1e9};
};
constexpr uint32_t kLevelSlots = 64;
LevelSlot g_levels[kLevelSlots];
std::atomic<uint32_t> g_nextLevelSlot{0};

std::atomic<bool> g_broken{false};

float FromDb(float aDb)
{
    return std::pow(10.f, aDb / 20.f);
}

void RaiseTo(std::atomic<float>& aMax, float aValue)
{
    if (aValue > aMax.load(std::memory_order_relaxed))
    {
        aMax.store(aValue, std::memory_order_relaxed);
    }
}

void LowerTo(std::atomic<float>& aMin, float aValue)
{
    if (aValue < aMin.load(std::memory_order_relaxed))
    {
        aMin.store(aValue, std::memory_order_relaxed);
    }
}

// Each of these is kept apart so the __try has nothing to unwind. A wrong guess about Wwise's data must not take the game down.
bool MeasureLevels(const ak::AudioBuffer* aBuffer, float aOffsetGain, TrackSlot& aSlot, float& aLoudest)
{
    __try
    {
        aSlot.frames = 0;
        const auto* const data = static_cast<const float*>(aBuffer->data);
        const uint32_t channels = aBuffer->channelConfig & 0xFF;
        const uint32_t frames = aBuffer->validFrames;
        if (!data || frames == 0 || frames > aBuffer->maxFrames || frames > kMaxFrames)
        {
            return true;
        }
        std::memset(aSlot.level, 0, frames * sizeof(float));
        for (uint32_t channel = 0; channel < channels; ++channel)
        {
            const float* const samples = data + static_cast<size_t>(channel) * aBuffer->maxFrames;
            for (uint32_t i = 0; i < frames; ++i)
            {
                const float level = samples[i] < 0.f ? -samples[i] : samples[i];
                aSlot.level[i] = level > aSlot.level[i] ? level : aSlot.level[i];
            }
        }
        float loudest = 0.f;
        for (uint32_t i = 0; i < frames; ++i)
        {
            loudest = aSlot.level[i] > loudest ? aSlot.level[i] : loudest;
            aSlot.level[i] *= aOffsetGain;
        }
        aLoudest = loudest;
        aSlot.loudest = loudest * aOffsetGain;
        aSlot.frames = frames;
        return true;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return false;
    }
}

bool MeasurePower(const ak::AudioBuffer* aBuffer, uint32_t aFrames, float& aPower)
{
    __try
    {
        const auto* const data = static_cast<const float*>(aBuffer->data);
        const uint32_t channels = aBuffer->channelConfig & 0xFF;
        float loudest = 0.f;
        for (uint32_t channel = 0; channel < channels; ++channel)
        {
            const float* const samples = data + static_cast<size_t>(channel) * aBuffer->maxFrames;
            float sum = 0.f;
            for (uint32_t i = 0; i < aFrames; ++i)
            {
                sum += samples[i] * samples[i];
            }
            loudest = sum > loudest ? sum : loudest;
        }
        aPower = loudest / static_cast<float>(aFrames);
        return true;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return false;
    }
}

bool ApplyGains(ak::AudioBuffer* aBuffer, const float* aGains, uint32_t aFrames)
{
    __try
    {
        auto* const data = static_cast<float*>(aBuffer->data);
        const uint32_t channels = aBuffer->channelConfig & 0xFF;
        for (uint32_t channel = 0; channel < channels; ++channel)
        {
            float* const samples = data + static_cast<size_t>(channel) * aBuffer->maxFrames;
            for (uint32_t i = 0; i < aFrames; ++i)
            {
                samples[i] *= aGains[i];
            }
        }
        return true;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return false;
    }
}

bool ProcessEars(ak::AudioBuffer* aBuffer, Ear* aEars, const float* aMic, const float* aWear, uint32_t aFrames, float aLeakGain)
{
    __try
    {
        auto* const data = static_cast<float*>(aBuffer->data);
        const uint32_t channels = aBuffer->channelConfig & 0xFF;
        for (uint32_t channel = 0; channel < channels; ++channel)
        {
            float* const samples = data + static_cast<size_t>(channel) * aBuffer->maxFrames;
            Ear& ear = aEars[channel];
            for (uint32_t i = 0; i < aFrames; ++i)
            {
                const float in = samples[i];
                samples[i] = in + (ear.Process(in, aMic[i], aLeakGain) - in) * aWear[i];
            }
        }
        return true;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return false;
    }
}

// The one stereo bus carrying the world: the same, then the narrower picture and the hiss.
bool ProcessWorld(ak::AudioBuffer* aBuffer, Ear* aEars, Hiss& aHiss, const float* aMic, const float* aWear, uint32_t aFrames, float aLeakGain, float aWidth, float aHissGain)
{
    __try
    {
        auto* const left = static_cast<float*>(aBuffer->data);
        float* const right = left + aBuffer->maxFrames;
        for (uint32_t i = 0; i < aFrames; ++i)
        {
            const float inLeft = left[i];
            const float inRight = right[i];
            const float wetLeft = aEars[0].Process(inLeft, aMic[i], aLeakGain);
            const float wetRight = aEars[1].Process(inRight, aMic[i], aLeakGain);
            const float middle = (wetLeft + wetRight) * 0.5f;
            const float side = (wetLeft - wetRight) * 0.5f * aWidth;
            left[i] = inLeft + (middle + side + aHiss.Next(0) * aHissGain - inLeft) * aWear[i];
            right[i] = inRight + (middle - side + aHiss.Next(1) * aHissGain - inRight) * aWear[i];
        }
        return true;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return false;
    }
}

// aBang runs from 0, no bang, to 1, the loudest: how far each band has moved from its cancelled level to its level during a bang.
bool ProcessNoiseCancel(ak::AudioBuffer* aBuffer, Ear* aEars, const float* aWear, const float* aBang, uint32_t aFrames, float aLow, float aMid, float aHigh, float aBangLow, float aBangMid, float aBangHigh)
{
    __try
    {
        auto* const data = static_cast<float*>(aBuffer->data);
        const uint32_t channels = aBuffer->channelConfig & 0xFF;
        for (uint32_t channel = 0; channel < channels; ++channel)
        {
            float* const samples = data + static_cast<size_t>(channel) * aBuffer->maxFrames;
            Ear& ear = aEars[channel];
            for (uint32_t i = 0; i < aFrames; ++i)
            {
                const float in = samples[i];
                const float bang = aBang[i];
                const float wet = ear.NoiseCancel(in, aLow + (aBangLow - aLow) * bang, aMid + (aBangMid - aMid) * bang, aHigh + (aBangHigh - aHigh) * bang);
                samples[i] = in + (wet - in) * aWear[i];
            }
        }
        return true;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return false;
    }
}

bool ProcessVoice(ak::AudioBuffer* aBuffer, Ear* aEars, const float* aAir, const float* aMask, const float* aWear, uint32_t aFrames, float aBody)
{
    __try
    {
        auto* const data = static_cast<float*>(aBuffer->data);
        const uint32_t channels = aBuffer->channelConfig & 0xFF;
        for (uint32_t channel = 0; channel < channels; ++channel)
        {
            float* const samples = data + static_cast<size_t>(channel) * aBuffer->maxFrames;
            Ear& ear = aEars[channel];
            for (uint32_t i = 0; i < aFrames; ++i)
            {
                const float in = samples[i];
                samples[i] = in + (ear.Voice(in, aBody, aAir[i]) * aMask[i] - in) * aWear[i];
            }
        }
        return true;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return false;
    }
}

// A bang's lows, raised before the clamp and the cups: your own shot through the shoulder, others' shots and blasts through the chest.
bool AddRecoil(ak::AudioBuffer* aBuffer, Lowpass2* aLows, float aGain, float& aWear, float aStep)
{
    __try
    {
        auto* const data = static_cast<float*>(aBuffer->data);
        const uint32_t channels = aBuffer->channelConfig & 0xFF;
        const uint32_t frames = aBuffer->validFrames;
        const float startWear = aWear;
        for (uint32_t channel = 0; channel < channels && channel < static_cast<uint32_t>(kMaxEars); ++channel)
        {
            float* const samples = data + static_cast<size_t>(channel) * aBuffer->maxFrames;
            Lowpass2& low = aLows[channel];
            float wear = startWear;
            for (uint32_t i = 0; i < frames; ++i)
            {
                wear = std::clamp(wear + aStep, 0.f, 1.f);
                samples[i] += low.Process(samples[i]) * aGain * wear;
            }
            aWear = wear;
        }
        return true;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return false;
    }
}

// IAkPluginParam. The virtual functions are in Wwise's slot order: SetParam comes first because it's declared by a base.
class Params
{
public:
    virtual ~Params() = default;

    virtual int SetParam(uint16_t, const void*, uint32_t)
    {
        return ak::kSuccess;
    }

    virtual Params* Clone(void*)
    {
        return new (std::nothrow) Params(*this);
    }

    virtual int Init(void*, const void* aBlock, uint32_t aSize)
    {
        return SetParamsBlock(aBlock, aSize);
    }

    virtual int Term(void*)
    {
        delete this;
        return ak::kSuccess;
    }

    virtual int SetParamsBlock(const void* aBlock, uint32_t aSize)
    {
        if (aBlock && aSize >= 2 * sizeof(uint32_t))
        {
            uint32_t values[2] = {};
            std::memcpy(values, aBlock, sizeof(values));
            role = values[0] == static_cast<uint32_t>(Role::Detector) ? Role::Detector : Role::Clamp;
            index = values[1] < static_cast<uint32_t>(kDetectorCount) ? static_cast<int>(values[1]) : 0;
        }
        return ak::kSuccess;
    }

    Role role = Role::Clamp;
    int index = 0;
};

// IAkInPlaceEffectPlugin, again in slot order. Term deletes with our own heap, so Wwise's allocator is never touched.
class Effect
{
public:
    Effect() = default;

    virtual ~Effect() = default;

    virtual int Term(void*)
    {
        (m_role == Role::Detector ? g_control.detectorsAlive : g_control.clampsAlive).fetch_sub(1, std::memory_order_relaxed);
        delete this;
        return ak::kSuccess;
    }

    virtual int Reset()
    {
        return ak::kSuccess;
    }

    virtual int GetPluginInfo(ak::PluginInfo& aInfo)
    {
        aInfo.type = ak::kPluginTypeEffect;
        aInfo.buildVersion = ak::kBuildVersion;
        aInfo.inPlace = true;
        aInfo.canChangeRate = false;
        aInfo.reserved = false;
        aInfo.canProcessObjects = false;
        aInfo.isDeviceEffect = false;
        aInfo.canRunOnObjectConfig = true;
        aInfo.usesGainAttribute = false;
        return ak::kSuccess;
    }

    virtual bool SupportMediaRelocation() const
    {
        return false;
    }

    virtual int RelocateMedia(uint8_t*, uint8_t*)
    {
        return 0;
    }

    virtual int Init(void*, void*, void* aParams, ak::AudioFormat& aFormat)
    {
        if (aParams)
        {
            m_role = static_cast<Params*>(aParams)->role;
            m_index = static_cast<Params*>(aParams)->index;
        }
        if (m_role == Role::Clamp && m_index < kClampKindCount)
        {
            m_kind = static_cast<ClampKind>(m_index);
        }
        (m_role == Role::Detector ? g_control.detectorsAlive : g_control.clampsAlive).fetch_add(1, std::memory_order_relaxed);
        const int rate = std::max(static_cast<int>(aFormat.sampleRate), 8000);
        m_rate = rate;
        m_envelope.Configure(rate);
        m_envelope.Reset();
        m_wearStep = 1.f / (kWearSeconds * static_cast<float>(rate));
        for (Ear& ear : m_ears)
        {
            ear.Configure(rate);
        }
        for (Lowpass2& low : m_recoil)
        {
            low.Set(kRecoilHz, rate);
        }
        if (m_role == Role::Clamp && m_kind == ClampKind::World)
        {
            m_hiss.Configure(rate);
        }
        m_levelSlot = g_nextLevelSlot.fetch_add(1, std::memory_order_relaxed) % kLevelSlots;
        // Wwise ends this effect while its bus is quiet and makes a new one on the next sound, which is often a gunshot. The new
        // one is already worn: fading in from nothing is only for putting the headset on, and let the first shot through.
        // A detector's wear is only its recoil, so with the sound off it has none to start from.
        m_wear = IsWorn() && (m_role == Role::Clamp || g_control.soundOn.load(std::memory_order_relaxed)) ? 1.f : 0.f;
        m_activeMode = EffectiveMode();
        m_justStarted = true;
        return ak::kSuccess;
    }

    virtual void Execute(ak::AudioBuffer* aBuffer)
    {
        if (g_broken.load(std::memory_order_relaxed))
        {
            return;
        }
        if (m_role == Role::Detector)
        {
            Detect(aBuffer);
        }
        else
        {
            Clamp(aBuffer);
        }
    }

    virtual int TimeSkip(uint32_t)
    {
        return ak::kDataReady;
    }

private:
    void Detect(ak::AudioBuffer* aBuffer)
    {
        if (!DetectorsWanted())
        {
            return;
        }
        Track& track = g_tracks[m_index];
        const uint64_t next = track.sequence.load(std::memory_order_relaxed) + 1;
        TrackSlot& slot = track.slots[next & 1];
        const float offsetDb = g_control.offsetDb[m_index].load(std::memory_order_relaxed);
        const float thresholdDb = g_control.thresholdDb.load(std::memory_order_relaxed);
        float loudest = 0.f;
        if (!MeasureLevels(aBuffer, FromDb(offsetDb - thresholdDb), slot, loudest))
        {
            g_broken.store(true);
            return;
        }
        track.writtenMs.store(NowMs(), std::memory_order_relaxed);
        track.sequence.store(next, std::memory_order_release);
        g_control.detectorRuns[m_index].fetch_add(1, std::memory_order_relaxed);
        RaiseTo(g_control.loudestReading[m_index], loudest);

        // Read first, so the estimate of its loudness doesn't include what's added here.
        const Thump thump = kDetectors[m_index].thump;
        if (thump != Thump::None && slot.frames > 0)
        {
            const bool wanted = IsWorn() && g_control.soundOn.load(std::memory_order_relaxed);
            const float recoilDb = (thump == Thump::OwnGun ? g_control.recoilDb : g_control.thumpDb).load(std::memory_order_relaxed);
            if (wanted || m_wear > 0.f)
            {
                if (m_wear <= 0.f)
                {
                    for (Lowpass2& low : m_recoil)
                    {
                        low.Reset();
                    }
                }
                const float gain = recoilDb > 0.f ? FromDb(recoilDb) - 1.f : 0.f;
                if (!AddRecoil(aBuffer, m_recoil, gain, m_wear, wanted ? m_wearStep : -m_wearStep))
                {
                    g_broken.store(true);
                }
            }
        }
    }

    // Every detector frame is used exactly once, by the first run of this clamp after the detector wrote it: in the same audio
    // frame when the detector ran first, as it does below this bus, or one frame later (11 ms) on a bus beside it.
    void Gather(uint32_t aFrames)
    {
        std::memset(m_power, 0, aFrames * sizeof(float));
        for (int d = 0; d < kDetectorCount; ++d)
        {
            const Track& track = g_tracks[d];
            const uint64_t sequence = track.sequence.load(std::memory_order_acquire);
            if (sequence == m_seen[d])
            {
                continue;
            }
            m_seen[d] = sequence;
            const TrackSlot& slot = track.slots[sequence & 1];
            if (slot.loudest < kIgnoreLevel)
            {
                continue;
            }
            const uint32_t frames = std::min(slot.frames, aFrames);
            for (uint32_t i = 0; i < frames; ++i)
            {
                m_power[i] += slot.level[i] * slot.level[i];
            }
        }
    }

    // How much the talk-through lifts quiet sounds, from everything it hears right now; the same on every bus.
    float NextLift(const ak::AudioBuffer* aBuffer, uint32_t aFrames)
    {
        float mine = 0.f;
        if (!MeasurePower(aBuffer, aFrames, mine))
        {
            g_broken.store(true);
            return 0.f;
        }
        const double now = NowMs();
        g_levels[m_levelSlot].power.store(mine, std::memory_order_relaxed);
        g_levels[m_levelSlot].atMs.store(now, std::memory_order_relaxed);
        double total = 0.0;
        for (const LevelSlot& level : g_levels)
        {
            if (now - level.atMs.load(std::memory_order_relaxed) < kLevelFreshMs)
            {
                total += level.power.load(std::memory_order_relaxed);
            }
        }
        const float levelDb = 10.f * std::log10(std::max(static_cast<float>(total), 1e-12f));
        const float underDb = g_control.liftUnderDb.load(std::memory_order_relaxed);
        const float floorDb = underDb - kLiftFloorBelowDb;
        float target = 0.f;
        if (levelDb < underDb && levelDb > floorDb)
        {
            target = std::min(kLiftMostDb, (underDb - levelDb) * kLiftRatio) * std::min(1.f, (levelDb - floorDb) / 10.f);
        }
        const float frameMs = static_cast<float>(aFrames) * 1000.f / static_cast<float>(m_rate);
        m_liftDb += (target - m_liftDb) * (1.f - std::exp(-frameMs / (target < m_liftDb ? kLiftDownMs : kLiftUpMs)));
        return m_liftDb;
    }

    void Clamp(ak::AudioBuffer* aBuffer)
    {
        // Changing mode fades out what it was doing and fades in the new one, so nothing clicks.
        const Mode wanted = EffectiveMode();
        if (m_wear <= 0.f)
        {
            m_activeMode = wanted;
        }
        const bool worn = wanted != Mode::Passthrough && wanted == m_activeMode;
        if (!worn && m_wear <= 0.f)
        {
            return;
        }
        const uint32_t frames = aBuffer->validFrames;
        if (!aBuffer->data || frames == 0 || frames > aBuffer->maxFrames || frames > kMaxFrames)
        {
            return;
        }
        if (m_wear <= 0.f)
        {
            // Putting it on: whatever the detectors wrote before now is history.
            m_envelope.Reset();
            m_liftDb = 0.f;
            m_lastLift = 1.f;
            m_hiss.Reset();
            for (Ear& ear : m_ears)
            {
                ear.Reset();
            }
            for (int d = 0; d < kDetectorCount; ++d)
            {
                m_seen[d] = g_tracks[d].sequence.load(std::memory_order_acquire);
            }
        }
        else if (m_justStarted)
        {
            // Woken by a sound: the detector below may have just written the very shot that woke it, and that counts. Anything
            // older is from before this effect existed.
            const double now = NowMs();
            for (int d = 0; d < kDetectorCount; ++d)
            {
                if (now - g_tracks[d].writtenMs.load(std::memory_order_relaxed) > kFreshMs)
                {
                    m_seen[d] = g_tracks[d].sequence.load(std::memory_order_acquire);
                }
            }
        }
        m_justStarted = false;

        Gather(frames);
        const bool noiseCancelling = m_activeMode == Mode::NoiseCancelling;
        const float depth = g_control.depthPerDb.load(std::memory_order_relaxed);
        const float floor = FromDb(-g_control.deepestDb.load(std::memory_order_relaxed));
        const float step = worn ? m_wearStep : -m_wearStep;
        float lowest = 1.f;
        for (uint32_t i = 0; i < frames; ++i)
        {
            const float gain = m_envelope.Track(std::sqrt(m_power[i]), depth, floor);
            m_wear = std::clamp(m_wear + step, 0.f, 1.f);
            m_clamps[i] = gain;
            m_wears[i] = m_wear;
            m_gains[i] = 1.f + (gain - 1.f) * m_wear;
            lowest = std::min(lowest, m_gains[i]);
        }

        if (m_kind == ClampKind::World)
        {
            g_control.worldClamp.store(m_clamps[frames - 1], std::memory_order_relaxed);
            g_control.worldClampAtMs.store(NowMs(), std::memory_order_relaxed);
        }

        const uint32_t channels = aBuffer->channelConfig & 0xFF;
        const bool sound = g_control.soundOn.load(std::memory_order_relaxed) && channels <= static_cast<uint32_t>(kMaxEars);
        bool ok = true;
        const bool ownVoice = m_kind == ClampKind::VoiceOfV || m_kind == ClampKind::BreathOfV;
        if (ownVoice)
        {
            // Left alone with the sound off.
            if (sound)
            {
                const bool grunts = m_kind == ClampKind::BreathOfV;
                const float airFloor = FromDb((grunts ? g_control.gruntFloorDb : g_control.airFloorDb).load(std::memory_order_relaxed));
                const float airOpen = FromDb((grunts ? g_control.gruntOpenDb : g_control.airOpenDb).load(std::memory_order_relaxed));
                // A bang drowns out your own voice, skull and all, as far as its loudness says: the same curve as the clamp, scaled so
                // that the loudest bang (the clamp's deepest) reaches mask_db.
                const float deepestDb = std::max(g_control.deepestDb.load(std::memory_order_relaxed), 1.f);
                const float maskDb = (grunts && !noiseCancelling ? g_control.gruntClampMaskDb : g_control.maskDb).load(std::memory_order_relaxed);
                const float maskPower = -maskDb / deepestDb;
                if (grunts)
                {
                    const float bodyHz = g_control.gruntBodyHz.load(std::memory_order_relaxed);
                    if (bodyHz != m_bodyHz)
                    {
                        m_bodyHz = bodyHz;
                        for (Ear& ear : m_ears)
                        {
                            ear.body.Set(bodyHz, m_rate);
                        }
                    }
                }
                for (uint32_t i = 0; i < frames; ++i)
                {
                    m_mic[i] = noiseCancelling ? airFloor : std::max(m_clamps[i] * airOpen, airFloor);
                    m_mask[i] = m_clamps[i] < 1.f ? std::pow(m_clamps[i], maskPower) : 1.f;
                }
                ok = ProcessVoice(aBuffer, m_ears, m_mic, m_mask, m_wears, frames, FromDb((grunts ? g_control.gruntBodyDb : g_control.bodyDb).load(std::memory_order_relaxed)));
            }
        }
        else if (noiseCancelling)
        {
            if (sound)
            {
                const bool ownBody = m_kind == ClampKind::OwnBody;
                for (uint32_t i = 0; i < frames; ++i)
                {
                    m_mic[i] = 1.f - m_clamps[i];
                }
                ok = ProcessNoiseCancel(aBuffer, m_ears, m_wears, m_mic, frames, ownBody ? 1.f : FromDb(g_control.noiseLowDb.load(std::memory_order_relaxed)),
                                        FromDb(g_control.noiseMidDb.load(std::memory_order_relaxed)), FromDb(g_control.noiseHighDb.load(std::memory_order_relaxed)),
                                        ownBody ? 1.f : FromDb(g_control.noiseBangLowDb.load(std::memory_order_relaxed)),
                                        FromDb(g_control.noiseBangMidDb.load(std::memory_order_relaxed)), FromDb(g_control.noiseBangHighDb.load(std::memory_order_relaxed)));
            }
        }
        else if (sound)
        {
            const float liftDb = NextLift(aBuffer, frames);
            const float lift = FromDb(liftDb);
            const float rise = (lift - m_lastLift) / static_cast<float>(frames);
            float gain = m_lastLift;
            for (uint32_t i = 0; i < frames; ++i)
            {
                gain += rise;
                m_mic[i] = m_clamps[i] * gain;
            }
            m_lastLift = lift;

            const float leak = FromDb(g_control.leakDb.load(std::memory_order_relaxed));
            if (m_kind == ClampKind::World && channels == 2)
            {
                const float hiss = m_hiss.Unit() * FromDb(g_control.hissDb.load(std::memory_order_relaxed));
                ok = ProcessWorld(aBuffer, m_ears, m_hiss, m_mic, m_wears, frames, leak, g_control.width.load(std::memory_order_relaxed), hiss);
            }
            else
            {
                const float body = m_kind == ClampKind::OwnBody ? FromDb(g_control.footstepDb.load(std::memory_order_relaxed)) : 1.f;
                ok = ProcessEars(aBuffer, m_ears, m_mic, m_wears, frames, leak * body);
            }
        }
        else
        {
            ok = ApplyGains(aBuffer, m_gains, frames);
        }
        if (!ok)
        {
            g_broken.store(true);
            return;
        }
        if (!noiseCancelling && !ownVoice)
        {
            LowerTo(g_control.lowestGain, lowest);
        }
    }

    Role m_role = Role::Clamp;
    int m_index = 0;
    ClampKind m_kind = ClampKind::Plain;
    Mode m_activeMode = Mode::Passthrough;
    int m_rate = 48000;
    ClampEnvelope m_envelope;
    float m_wear = 0.f;
    float m_wearStep = 0.f;
    bool m_justStarted = true;
    uint64_t m_seen[kDetectorCount] = {};
    float m_power[kMaxFrames] = {};
    float m_gains[kMaxFrames] = {};
    float m_clamps[kMaxFrames] = {};
    float m_wears[kMaxFrames] = {};
    float m_mic[kMaxFrames] = {};
    float m_mask[kMaxFrames] = {};
    Ear m_ears[kMaxEars];
    Lowpass2 m_recoil[kMaxEars];
    Hiss m_hiss;
    uint32_t m_levelSlot = 0;
    float m_liftDb = 0.f;
    float m_lastLift = 1.f;
    float m_bodyHz = kBodyHz;
};

void Put32(std::vector<uint8_t>& aBank, uint32_t aValue)
{
    for (int i = 0; i < 4; ++i)
    {
        aBank.push_back(static_cast<uint8_t>(aValue >> (8 * i)));
    }
}

void PutTag(std::vector<uint8_t>& aBank, const char* aTag)
{
    aBank.insert(aBank.end(), aTag, aTag + 4);
}

// One effect share set, as in the game's init.bnk (object kind 16). The parameter block says which role and which of it this is.
void PutShareSet(std::vector<uint8_t>& aBank, uint32_t aId, Role aRole, uint32_t aIndex)
{
    constexpr uint32_t kTrailingZeros = 7; // no media, RTPCs, states or plug-in properties
    constexpr uint32_t kParamsSize = 2 * sizeof(uint32_t);
    aBank.push_back(16);
    Put32(aBank, 4 + 4 + 4 + kParamsSize + kTrailingZeros);
    Put32(aBank, aId);
    Put32(aBank, kFullPluginId);
    Put32(aBank, kParamsSize);
    Put32(aBank, static_cast<uint32_t>(aRole));
    Put32(aBank, aIndex);
    aBank.insert(aBank.end(), kTrailingZeros, 0);
}
} // namespace

void* NewEffect()
{
    return new (std::nothrow) Effect();
}

void* NewParams()
{
    return new (std::nothrow) Params();
}

std::vector<uint8_t> MakeBank()
{
    std::vector<uint8_t> bank;
    // The header as in the game's own small banks: version 150, its language and project numbers, and a hash nothing reads.
    PutTag(bank, "BKHD");
    Put32(bank, 40);
    Put32(bank, 150);
    Put32(bank, kBankId);
    Put32(bank, 0x17705D3E);
    Put32(bank, 0x10);
    Put32(bank, 0x1DC);
    Put32(bank, 0);
    for (uint32_t i = 0; i < 4; ++i)
    {
        Put32(bank, kBankId + i);
    }

    std::vector<uint8_t> objects;
    Put32(objects, kDetectorCount + kClampKindCount);
    for (uint32_t i = 0; i < static_cast<uint32_t>(kDetectorCount); ++i)
    {
        PutShareSet(objects, kDetectorShareSetBase + i, Role::Detector, i);
    }
    for (uint32_t kind = 0; kind < static_cast<uint32_t>(kClampKindCount); ++kind)
    {
        PutShareSet(objects, kClampShareSetBase + kind, Role::Clamp, kind);
    }
    PutTag(bank, "HIRC");
    Put32(bank, static_cast<uint32_t>(objects.size()));
    bank.insert(bank.end(), objects.begin(), objects.end());
    return bank;
}

bool AudioBroken()
{
    return g_broken.load();
}

void ClearAudioBroken()
{
    g_broken.store(false);
}

void ResetTracks()
{
    for (Track& track : g_tracks)
    {
        track.sequence.store(0);
        track.writtenMs.store(0.0);
        track.slots[0].frames = track.slots[1].frames = 0;
        track.slots[0].loudest = track.slots[1].loudest = 0.f;
    }
    for (LevelSlot& level : g_levels)
    {
        level.power.store(0.f);
        level.atMs.store(-1e9);
    }
}
} // namespace hs
