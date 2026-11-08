#include "audio/headset.hpp"

#include "audio/dsp.hpp" // g_liveTuning, for tuning by ear in the game

#include <algorithm>
#include <cmath>

namespace nv
{
namespace
{
constexpr double kTwoPi = 6.283185307179586;

// headset3 as the user heard it on recordings of the game ("feels fantastic"), at the game's Master volume 100. Levels are
// dB of the game's own samples, before Windows' volume; the user's recordings at Master 100 are on the same scale.
// The clamp level, its steepness, how deep it goes and the hiss can be moved live through tuning.ini (headset_db,
// headset_steep, headset_deepest_db, headset_hiss_db); these are where they start.
// -14 as tuned in the game ("good for now", 2026-11-07): at -20 the loudest syllables of an NPC talking at a moderate
// distance got clamped, while at -14 speech is left alone and shots still go down by up to 27 dB.
constexpr float kClampAtDb = -14.f;
// It turns a sound 3 dB down for each dB over the clamp level, 40 dB at most; both start in g_liveTuning.
constexpr float kReleaseMs = 150.f;     // back up after a single bang
constexpr float kReleaseSlowMs = 900.f; // while bangs keep coming, so the world doesn't breathe at the fire rate
constexpr float kBusyRiseMs = 80.f;
constexpr float kBusyFallMs = 2500.f;
constexpr float kPeakHoldMs = 30.f;     // stops the clamp chattering on each cycle of a low rumble
constexpr float kDetectLowHz = 80.f;    // an engine or music's bass alone doesn't turn the world down
constexpr float kMicLowHz = 120.f;      // small outside microphones lose the deepest bass
constexpr float kMicHighHz = 7000.f;    // and the very top
constexpr float kLeakDb = -10.f;        // the cups' own leak, never turned down
constexpr float kLeakHz = 300.f;        // two-pole: about 21 dB more off at 1 kHz, 33 at 2 kHz
constexpr float kLiftUnderDb = -38.f;   // sounds under this get lifted, as talk-through does; where it was heard and liked
constexpr float kLiftRatio = 0.5f;      // 1 dB up for every 2 dB further under
constexpr float kLiftMostDb = 6.f;
constexpr float kLiftFloorDb = -70.f;   // under this it's silence rather than a quiet sound, and stays as it is
constexpr float kLiftDownMs = 20.f;     // a sound getting louder loses its lift fast
constexpr float kLiftUpMs = 400.f;      // and quiet gains it slowly
constexpr float kWidth = 0.75f;         // microphones on the cups tell less of where a sound is than ears do
constexpr float kHissDb = -64.f;        // the talk-through electronics' own faint hiss
constexpr float kHissLowHz = 300.f;
constexpr float kHissHighHz = 6000.f;
constexpr float kWearSeconds = 0.2f;    // putting it on or taking it off never clicks
constexpr int kControlEvery = 16;       // samples between working out the lift again, which takes logarithms
constexpr double kGameFreshMs = 500.0;  // voices follow the game's clamp only while the game's sound is coming through
constexpr float kVoiceClampMs = 3.f;    // voices follow the game's clamp smoothly between its buffers

float Coefficient(float aMs, int aRate)
{
    return 1.f - std::exp(-1000.f / (aMs * static_cast<float>(aRate)));
}

float FromDb(float aDb)
{
    return std::pow(10.f, aDb / 20.f);
}

class RatePole
{
public:
    void Set(float aHz, int aRate)
    {
        m_a = 1.f - std::exp(static_cast<float>(-kTwoPi * aHz / aRate));
    }
    void Reset()
    {
        m_y = 0.f;
    }
    float Lowpass(float aIn)
    {
        m_y += m_a * (aIn - m_y);
        return m_y;
    }
    float Highpass(float aIn)
    {
        return aIn - Lowpass(aIn);
    }

private:
    float m_a = 1.f;
    float m_y = 0.f;
};

// Butterworth, from the usual cookbook, at any rate.
class Biquad2
{
public:
    void SetLowpass(float aHz, int aRate)
    {
        const double w = kTwoPi * aHz / aRate;
        const double alpha = std::sin(w) / (2.0 * 0.7071);
        Set((1.0 - std::cos(w)) / 2.0, 1.0 - std::cos(w), (1.0 - std::cos(w)) / 2.0, 1.0 + alpha, -2.0 * std::cos(w), 1.0 - alpha);
    }
    void SetHighpass(float aHz, int aRate)
    {
        const double w = kTwoPi * aHz / aRate;
        const double alpha = std::sin(w) / (2.0 * 0.7071);
        Set((1.0 + std::cos(w)) / 2.0, -(1.0 + std::cos(w)), (1.0 + std::cos(w)) / 2.0, 1.0 + alpha, -2.0 * std::cos(w),
            1.0 - alpha);
    }
    void Reset()
    {
        m_z1 = m_z2 = 0.f;
    }
    float Process(float aIn)
    {
        const float out = m_b0 * aIn + m_z1;
        m_z1 = m_b1 * aIn - m_a1 * out + m_z2;
        m_z2 = m_b2 * aIn - m_a2 * out;
        return out;
    }

private:
    void Set(double aB0, double aB1, double aB2, double aA0, double aA1, double aA2)
    {
        m_b0 = static_cast<float>(aB0 / aA0);
        m_b1 = static_cast<float>(aB1 / aA0);
        m_b2 = static_cast<float>(aB2 / aA0);
        m_a1 = static_cast<float>(aA1 / aA0);
        m_a2 = static_cast<float>(aA2 / aA0);
    }

    float m_b0 = 1.f, m_b1 = 0.f, m_b2 = 0.f, m_a1 = 0.f, m_a2 = 0.f;
    float m_z1 = 0.f, m_z2 = 0.f;
};

// No look-ahead, like a headset's electronics: it acts on the very sample a peak arrives, since easing in let a bang's
// first millisecond through at full level on the recordings.
class Clamp
{
public:
    void Configure(int aRate)
    {
        m_release = Coefficient(kReleaseMs, aRate);
        m_slowRelease = Coefficient(kReleaseSlowMs, aRate);
        m_busyRise = Coefficient(kBusyRiseMs, aRate);
        m_busyFall = Coefficient(kBusyFallMs, aRate);
        m_holdSamples = static_cast<int>(kPeakHoldMs * aRate / 1000.f);
        m_sink = 1.f - Coefficient(kPeakHoldMs, aRate);
    }
    void Reset()
    {
        m_peak = 0.f;
        m_gain = 1.f;
        m_busy = 0.f;
        m_holdLeft = 0;
        m_armed = false;
    }

    float Track(float aDetect, float aThreshold, float aSteepness, float aFloor)
    {
        const float level = std::fabs(aDetect);
        if (level >= m_peak)
        {
            m_peak = level;
            m_holdLeft = m_holdSamples;
        }
        else if (m_holdLeft > 0)
        {
            --m_holdLeft;
        }
        else
        {
            m_peak = std::max(level, m_peak * m_sink);
        }
        float target = 1.f;
        if (m_peak > aThreshold)
        {
            target = std::max(std::pow(aThreshold / m_peak, aSteepness), aFloor);
        }
        const bool down = m_gain < 0.5f; // over 6 dB
        m_busy += ((down ? 1.f : 0.f) - m_busy) * (down ? m_busyRise : m_busyFall);
        const float release = m_release + (m_slowRelease - m_release) * m_busy;
        m_gain = target < m_gain ? target : m_gain + (target - m_gain) * release;
        // A breath: well down, then back up near full, as happens between shots when it recovers too fast.
        if (m_gain < 0.316f)
        {
            m_armed = true;
        }
        else if (m_armed && m_gain > 0.708f)
        {
            m_armed = false;
            ++breaths;
        }
        return m_gain;
    }

    uint32_t breaths = 0;

private:
    float m_release = 0.f, m_slowRelease = 0.f, m_busyRise = 0.f, m_busyFall = 0.f, m_sink = 0.f;
    int m_holdSamples = 0;
    int m_holdLeft = 0;
    float m_peak = 0.f;
    float m_gain = 1.f;
    float m_busy = 0.f;
    bool m_armed = false;
};

// Lifts quiet sounds a little, the way a tactical headset's talk-through makes footsteps easier to hear.
class Lift
{
public:
    void Configure(int aRate)
    {
        m_power = Coefficient(30.f, aRate);
        m_down = 1.f - std::pow(1.f - Coefficient(kLiftDownMs, aRate), static_cast<float>(kControlEvery));
        m_up = 1.f - std::pow(1.f - Coefficient(kLiftUpMs, aRate), static_cast<float>(kControlEvery));
    }
    void Reset()
    {
        m_level = 0.f;
        m_liftDb = 0.f;
        m_gain = 1.f;
        m_count = 0;
    }

    float Gain(float aIn, float aBelowDb, float aFloorDb)
    {
        m_level += (aIn * aIn - m_level) * m_power;
        if (++m_count >= kControlEvery)
        {
            m_count = 0;
            const float levelDb = 10.f * std::log10(std::max(m_level, 1e-12f));
            float target = 0.f;
            if (levelDb < aBelowDb && levelDb > aFloorDb)
            {
                target = std::min(kLiftMostDb, (aBelowDb - levelDb) * kLiftRatio) * std::min(1.f, (levelDb - aFloorDb) / 10.f);
            }
            m_liftDb += (target - m_liftDb) * (target < m_liftDb ? m_down : m_up);
            m_gain = FromDb(m_liftDb);
        }
        return m_gain;
    }

private:
    float m_power = 0.f, m_down = 0.f, m_up = 0.f;
    float m_level = 0.f;
    float m_liftDb = 0.f;
    float m_gain = 1.f;
    int m_count = 0;
};

// What one ear hears through the headset: the microphones' sound, lifted and clamped, and the cups' leak.
struct Ear
{
    Biquad2 detect;
    RatePole micLow;
    Biquad2 micHigh;
    Biquad2 leak;
    Clamp clamp;
    Lift lift;
    float lastClamp = 1.f;
    float lastLift = 1.f;
    float deepest = 1.f;

    void Configure(int aRate)
    {
        detect.SetHighpass(kDetectLowHz, aRate);
        micLow.Set(kMicLowHz, aRate);
        micHigh.SetLowpass(kMicHighHz, aRate);
        leak.SetLowpass(kLeakHz, aRate);
        clamp.Configure(aRate);
        lift.Configure(aRate);
    }
    void Reset()
    {
        detect.Reset();
        micLow.Reset();
        micHigh.Reset();
        leak.Reset();
        clamp.Reset();
        lift.Reset();
        lastClamp = lastLift = 1.f;
    }

    float Wet(float aIn, float aThreshold, float aSteepness, float aDeepest, float aLiftBelowDb, float aFloorDb)
    {
        const float picked = micHigh.Process(micLow.Highpass(aIn));
        lastLift = lift.Gain(picked, aLiftBelowDb, aFloorDb);
        lastClamp = clamp.Track(detect.Process(aIn), aThreshold, aSteepness, aDeepest);
        deepest = std::min(deepest, lastClamp);
        static const float leakGain = FromDb(kLeakDb);
        return picked * lastLift * lastClamp + leak.Process(aIn) * leakGain;
    }
};

void KeepLowest(std::atomic<float>& aStore, float aValue)
{
    float current = aStore.load(std::memory_order_relaxed);
    while (aValue < current && !aStore.compare_exchange_weak(current, aValue, std::memory_order_relaxed))
    {
    }
}
} // namespace

struct HeadsetStream::State
{
    int channels = 0;
    int rate = 48000;
    Ear ears[kMaxChannels];
    RatePole hissLow[2];
    Biquad2 hissHigh[2];
    float hissUnit = 1.f; // makes the filtered noise one unit RMS
    uint32_t seed = 0x9e3779b9u;
    float wear = 0.f;
    float wearStep = 0.f;

    float Noise()
    {
        seed = seed * 1664525u + 1013904223u;
        return static_cast<float>(static_cast<int32_t>(seed)) / 2147483648.f;
    }
};

HeadsetStream::HeadsetStream() : m_state(new State)
{
}

HeadsetStream::~HeadsetStream()
{
    delete m_state;
}

void HeadsetStream::Configure(int aChannels, int aRate)
{
    State& state = *m_state;
    state.channels = std::clamp(aChannels, 0, kMaxChannels);
    state.rate = std::max(aRate, 8000);
    state.wear = 0.f;
    state.wearStep = 1.f / (kWearSeconds * static_cast<float>(state.rate));
    for (Ear& ear : state.ears)
    {
        ear.Configure(state.rate);
        ear.Reset();
    }
    for (int side = 0; side < 2; ++side)
    {
        state.hissLow[side].Set(kHissLowHz, state.rate);
        state.hissHigh[side].SetLowpass(kHissHighHz, state.rate);
    }
    // Measure what the filters leave of the noise, so the hiss lands at its level whatever the rate.
    double power = 0.0;
    const int count = state.rate;
    for (int i = 0; i < count; ++i)
    {
        const float sample = state.hissHigh[0].Process(state.hissLow[0].Highpass(state.Noise()));
        power += static_cast<double>(sample) * sample;
    }
    state.hissUnit = 1.f / static_cast<float>(std::sqrt(std::max(power / count, 1e-20)));
    for (int side = 0; side < 2; ++side)
    {
        state.hissLow[side].Reset();
        state.hissHigh[side].Reset();
    }
}

float HeadsetStream::WornAmount() const
{
    return m_state->wear;
}

void HeadsetStream::Process(float* aSamples, uint32_t aFrames, bool aWorn, float aLevelShiftDb, bool aReport, double aNowMs)
{
    State& state = *m_state;
    const int channels = state.channels;
    if (channels <= 0 || !aSamples)
    {
        return;
    }
    if (aReport)
    {
        g_headset.frames.fetch_add(aFrames, std::memory_order_relaxed);
        g_headset.buffers.fetch_add(1, std::memory_order_relaxed);
    }
    if (state.wear <= 0.f && !aWorn)
    {
        if (aReport)
        {
            g_headset.gameAtMs.store(aNowMs, std::memory_order_relaxed);
            g_headset.clamp[0].store(1.f, std::memory_order_relaxed);
            g_headset.clamp[1].store(1.f, std::memory_order_relaxed);
        }
        return; // off: the game's sound is left exactly as it came
    }
    if (state.wear <= 0.f)
    {
        // Putting it on: fresh filters, heard from nothing as it fades in.
        for (Ear& ear : state.ears)
        {
            ear.Reset();
        }
    }

    // The lift stays where it was tuned when the clamp level moves: it's about quiet sounds, not loud ones.
    const float threshold = FromDb(kClampAtDb + aLevelShiftDb + g_liveTuning.headsetDb.load(std::memory_order_relaxed));
    const float steepness = g_liveTuning.headsetSteep.load(std::memory_order_relaxed);
    const float deepest = FromDb(-g_liveTuning.headsetDeepestDb.load(std::memory_order_relaxed));
    const float liftBelowDb = kLiftUnderDb + aLevelShiftDb;
    const float floorDb = kLiftFloorDb + aLevelShiftDb;
    const float hissGain =
        state.hissUnit * FromDb(kHissDb + aLevelShiftDb + g_liveTuning.headsetHissDb.load(std::memory_order_relaxed));
    const float step = aWorn ? state.wearStep : -state.wearStep;
    uint64_t wornFrames = 0;
    for (int channel = 0; channel < channels; ++channel)
    {
        state.ears[channel].deepest = 1.f;
    }

    float wet[kMaxChannels];
    for (uint32_t frame = 0; frame < aFrames; ++frame)
    {
        float* samples = aSamples + static_cast<size_t>(frame) * channels;
        state.wear = std::clamp(state.wear + step, 0.f, 1.f);
        wornFrames += state.wear > 0.f ? 1 : 0;
        for (int channel = 0; channel < channels; ++channel)
        {
            wet[channel] = state.ears[channel].Wet(samples[channel], threshold, steepness, deepest, liftBelowDb, floorDb);
        }
        if (channels >= 2)
        {
            const float middle = (wet[0] + wet[1]) * 0.5f;
            const float side = (wet[0] - wet[1]) * 0.5f * kWidth;
            wet[0] = middle + side + state.hissHigh[0].Process(state.hissLow[0].Highpass(state.Noise())) * hissGain;
            wet[1] = middle - side + state.hissHigh[1].Process(state.hissLow[1].Highpass(state.Noise())) * hissGain;
        }
        for (int channel = 0; channel < channels; ++channel)
        {
            samples[channel] += (wet[channel] - samples[channel]) * state.wear;
        }
    }

    if (aReport)
    {
        const int ears = std::min(channels, 2);
        for (int side = 0; side < 2; ++side)
        {
            const Ear& ear = state.ears[std::min(side, ears - 1)];
            g_headset.clamp[side].store(ear.lastClamp, std::memory_order_relaxed);
            g_headset.lift[side].store(ear.lastLift, std::memory_order_relaxed);
        }
        g_headset.gameAtMs.store(aNowMs, std::memory_order_relaxed);
        g_headset.wornFrames.fetch_add(wornFrames, std::memory_order_relaxed);
        float lowest = 1.f;
        uint32_t breaths = 0;
        for (int channel = 0; channel < ears; ++channel)
        {
            lowest = std::min(lowest, state.ears[channel].deepest);
            breaths += state.ears[channel].clamp.breaths;
            state.ears[channel].clamp.breaths = 0;
        }
        KeepLowest(g_headset.deepestDb, 20.f * std::log10(std::max(lowest, 1e-6f)));
        g_headset.breaths.fetch_add(breaths, std::memory_order_relaxed);
    }
}

struct HeadsetVoices::State
{
    RatePole micLow[2];
    Biquad2 micHigh[2];
    Biquad2 leak[2];
    float clamp[2] = {1.f, 1.f};
    float clampFollow = 0.f;
    float wear = 0.f;
    float wearStep = 0.f;
};

HeadsetVoices::HeadsetVoices() : m_state(new State)
{
    constexpr int kVoiceRate = 48000;
    for (int side = 0; side < 2; ++side)
    {
        m_state->micLow[side].Set(kMicLowHz, kVoiceRate);
        m_state->micHigh[side].SetLowpass(kMicHighHz, kVoiceRate);
        m_state->leak[side].SetLowpass(kLeakHz, kVoiceRate);
    }
    m_state->clampFollow = Coefficient(kVoiceClampMs, kVoiceRate);
    m_state->wearStep = 1.f / (kWearSeconds * kVoiceRate);
}

HeadsetVoices::~HeadsetVoices()
{
    delete m_state;
}

void HeadsetVoices::Process(float* aLeft, float* aRight, int aFrames, bool aWorn, double aNowMs)
{
    State& state = *m_state;
    if (state.wear <= 0.f && !aWorn)
    {
        return;
    }
    if (state.wear <= 0.f)
    {
        for (int side = 0; side < 2; ++side)
        {
            state.micLow[side].Reset();
            state.micHigh[side].Reset();
            state.leak[side].Reset();
            state.clamp[side] = 1.f;
        }
    }
    // Voices take the game's clamp, so a blast swallows a shout beside you, but not its lift: a voice nearby is far
    // louder than the quiet sounds the talk-through lifts.
    const bool fresh = aNowMs - g_headset.gameAtMs.load(std::memory_order_relaxed) < kGameFreshMs;
    const float target[2] = {fresh ? g_headset.clamp[0].load(std::memory_order_relaxed) : 1.f,
                             fresh ? g_headset.clamp[1].load(std::memory_order_relaxed) : 1.f};
    const float leakGain = FromDb(kLeakDb);
    const float step = aWorn ? state.wearStep : -state.wearStep;
    float* ears[2] = {aLeft, aRight};
    for (int i = 0; i < aFrames; ++i)
    {
        state.wear = std::clamp(state.wear + step, 0.f, 1.f);
        float wet[2];
        for (int side = 0; side < 2; ++side)
        {
            state.clamp[side] += (target[side] - state.clamp[side]) * state.clampFollow;
            const float in = ears[side][i];
            wet[side] = state.micHigh[side].Process(state.micLow[side].Highpass(in)) * state.clamp[side] +
                        state.leak[side].Process(in) * leakGain;
        }
        const float middle = (wet[0] + wet[1]) * 0.5f;
        const float side = (wet[0] - wet[1]) * 0.5f * kWidth;
        aLeft[i] += (middle + side - aLeft[i]) * state.wear;
        aRight[i] += (middle - side - aRight[i]) * state.wear;
    }
}
} // namespace nv
