// Turns a recording of the game into versions to compare by ear, for the headset idea in RECORD.md (2026-11-07):
//   <name>-limiter.wav   a plain fast limiter on each ear, about how a clamp in the mod could act
//   <name>-headset.wav   a model of a tactical headset: what its outside microphones pick up is limited and loses a little
//                        top end, while what leaks through the ear cups never is, but loses far more treble than bass.
//                        So a blast shrinks to a muffled thump while quiet sounds come through as they were.
//                        Measured on the user's recordings, it barely differs from the limiter and is even a little
//                        brighter in a blast: kept for comparison.
//   <name>-headset2.wav  the same idea, exaggerated to work in the game's mix, where a blast is only some 15 dB over the
//                        clamp level instead of 50 or more. The microphones turn down three dB for every dB a sound goes
//                        over it, judged on the whole sound, and a louder, more muffled leak through the cups takes over.
//   <name>-headset3.wav  the second, plus what the user asked for after hearing it: quiet sounds lifted a little, as
//                        talk-through does; recovery that slows while bangs keep coming, so the world doesn't breathe at
//                        the fire rate; the deepest bass no longer turning it down; and a faint constant character, a little
//                        narrower with a soft hiss, so wearing it is felt.
// All are written next to the recording at the same level as it, so they can be compared straight against it.
//
//   headset_clamp <recording.wav> [threshold dB over the recording's typical level]
//   headset_clamp <recording.wav> --at <dB>    the same clamp level for every recording, as a real headset would have
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <string>
#include <vector>

namespace
{
constexpr double kPi = 3.14159265358979323846;

// First guesses, all to be judged by ear.
constexpr float kThresholdOverTypicalDb = 15.f; // peaks this far over the recording's typical level get clamped
// The clamp acts on the very sample a peak arrives: easing in over even 1 ms let a bang's first millisecond through at
// full level, a click as loud as the bang. A headset's electronics clamp within about a millisecond, and with no look-ahead
// in either, instant is the closest a sample-by-sample limiter gets.
constexpr float kReleaseMs = 150.f;
constexpr float kPeakHoldMs = 30.f;             // stops the clamp chattering on each cycle of a low rumble
constexpr float kMicLowHz = 120.f;              // small outside microphones lose the deepest bass
constexpr float kMicHighHz = 7000.f;            // and the very top
constexpr float kLeakDb = -15.f;                // ear cups pass bass at about this
constexpr float kLeakHz = 200.f;                // and lose about 6 dB more per octave above this: -29 dB at 1 kHz, -41 at 4 kHz

// The second model. Real blasts are so far over a headset's clamp that what its microphones add hardly counts; the game's
// mix squeezes that, so the microphones have to give way faster for the leak to be what's left.
constexpr float kSteepness = 3.f;               // dB down for each dB over the clamp level
constexpr float kDeepestDb = 40.f;              // no further than this
constexpr float kLeak2Db = -10.f;
constexpr float kLeak2Hz = 300.f;               // two-pole: about -21 dB more at 1 kHz, -33 at 2 kHz

// The third model: the second, with what the user asked for after hearing it (2026-11-07).
constexpr float kDetectLowHz = 80.f;     // what turns the microphones down ignores the deepest bass, so an engine or music doesn't
constexpr float kReleaseSlowMs = 900.f;  // during repeated bangs the world stays down instead of breathing at the fire rate
constexpr float kBusyRiseMs = 80.f;      // how fast repeated clamping counts as busy
constexpr float kBusyFallMs = 2500.f;    // and how long that lasts after the last bang
constexpr float kLiftBelowDb = 18.f;     // sounds this far under the clamp level get lifted, as a headset's talk-through does
constexpr float kLiftRatio = 0.5f;       // 1 dB up for every 2 dB further under
constexpr float kLiftMostDb = 6.f;
constexpr float kLiftFloorDb = -70.f;    // under this it's silence rather than a quiet sound, and stays as it is
constexpr float kLiftDownMs = 20.f;      // a sound getting louder loses its lift fast
constexpr float kLiftUpMs = 400.f;       // and quiet gains it slowly
constexpr float kWidth = 0.75f;          // microphones on the cups tell less of where a sound is than ears do
constexpr float kHissDb = -64.f;         // the talk-through electronics' own faint hiss
constexpr float kHissLowHz = 300.f;
constexpr float kHissHighHz = 6000.f;

struct Audio
{
    int channels = 0;
    int rate = 0;
    std::vector<float> samples; // interleaved
};

uint32_t Get32(const std::vector<uint8_t>& aData, size_t aAt)
{
    uint32_t value;
    std::memcpy(&value, aData.data() + aAt, 4);
    return value;
}

uint16_t Get16(const std::vector<uint8_t>& aData, size_t aAt)
{
    uint16_t value;
    std::memcpy(&value, aData.data() + aAt, 2);
    return value;
}

// 32-bit float or 16-bit PCM, mono or stereo.
bool ReadWav(const std::filesystem::path& aPath, Audio& aOut)
{
    FILE* file = _wfopen(aPath.c_str(), L"rb");
    if (!file)
    {
        return false;
    }
    std::vector<uint8_t> data;
    uint8_t buffer[65536];
    size_t got;
    while ((got = std::fread(buffer, 1, sizeof(buffer), file)) > 0)
    {
        data.insert(data.end(), buffer, buffer + got);
    }
    std::fclose(file);
    if (data.size() < 12 || std::memcmp(data.data(), "RIFF", 4) != 0 || std::memcmp(data.data() + 8, "WAVE", 4) != 0)
    {
        return false;
    }
    int format = 0;
    int bits = 0;
    size_t at = 12;
    while (at + 8 <= data.size())
    {
        const uint32_t size = Get32(data, at + 4);
        const size_t body = at + 8;
        if (std::memcmp(data.data() + at, "fmt ", 4) == 0 && body + 16 <= data.size())
        {
            format = Get16(data, body);
            aOut.channels = Get16(data, body + 2);
            aOut.rate = static_cast<int>(Get32(data, body + 4));
            bits = Get16(data, body + 14);
            if (format == 0xFFFE && size >= 26 && body + 26 <= data.size())
            {
                format = Get16(data, body + 24); // the sub-format's first two bytes are the plain format number
            }
        }
        else if (std::memcmp(data.data() + at, "data", 4) == 0)
        {
            const size_t bytes = std::min<size_t>(size, data.size() - body);
            if (format == 3 && bits == 32)
            {
                aOut.samples.resize(bytes / 4);
                std::memcpy(aOut.samples.data(), data.data() + body, aOut.samples.size() * 4);
            }
            else if (format == 1 && bits == 16)
            {
                aOut.samples.resize(bytes / 2);
                for (size_t i = 0; i < aOut.samples.size(); ++i)
                {
                    aOut.samples[i] = static_cast<int16_t>(Get16(data, body + i * 2)) / 32768.f;
                }
            }
            else
            {
                std::printf("Only 32-bit float or 16-bit WAVs are read (this is format %d, %d bits).\n", format, bits);
                return false;
            }
            return aOut.channels >= 1 && aOut.channels <= 2 && aOut.rate > 0;
        }
        at = body + size + (size & 1);
    }
    return false;
}

bool WriteWav(const std::filesystem::path& aPath, const Audio& aAudio)
{
    FILE* file = _wfopen(aPath.c_str(), L"wb");
    if (!file)
    {
        return false;
    }
    const uint32_t bytes = static_cast<uint32_t>(aAudio.samples.size() * 4);
    const uint32_t riff = 36 + bytes;
    const uint32_t fmtSize = 16;
    const uint16_t format = 3;
    const uint16_t channels = static_cast<uint16_t>(aAudio.channels);
    const uint32_t rate = static_cast<uint32_t>(aAudio.rate);
    const uint16_t align = static_cast<uint16_t>(channels * 4);
    const uint32_t byteRate = rate * align;
    const uint16_t bits = 32;
    std::fwrite("RIFF", 1, 4, file);
    std::fwrite(&riff, 4, 1, file);
    std::fwrite("WAVEfmt ", 1, 8, file);
    std::fwrite(&fmtSize, 4, 1, file);
    std::fwrite(&format, 2, 1, file);
    std::fwrite(&channels, 2, 1, file);
    std::fwrite(&rate, 4, 1, file);
    std::fwrite(&byteRate, 4, 1, file);
    std::fwrite(&align, 2, 1, file);
    std::fwrite(&bits, 2, 1, file);
    std::fwrite("data", 1, 4, file);
    std::fwrite(&bytes, 4, 1, file);
    std::fwrite(aAudio.samples.data(), 4, aAudio.samples.size(), file);
    std::fclose(file);
    return true;
}

float Coefficient(float aMs, int aRate)
{
    return 1.f - std::exp(-1000.f / (aMs * static_cast<float>(aRate)));
}

class OnePole
{
public:
    OnePole(float aHz, int aRate) : m_a(1.f - std::exp(static_cast<float>(-2.0 * kPi * aHz / aRate)))
    {
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
    float m_a;
    float m_y = 0.f;
};

// Butterworth lowpass, from the usual cookbook.
class Lowpass2
{
public:
    Lowpass2(float aHz, int aRate)
    {
        const double w = 2.0 * kPi * aHz / aRate;
        const double alpha = std::sin(w) / (2.0 * 0.7071);
        const double a0 = 1.0 + alpha;
        m_b0 = static_cast<float>((1.0 - std::cos(w)) / 2.0 / a0);
        m_b1 = static_cast<float>((1.0 - std::cos(w)) / a0);
        m_b2 = m_b0;
        m_a1 = static_cast<float>(-2.0 * std::cos(w) / a0);
        m_a2 = static_cast<float>((1.0 - alpha) / a0);
    }
    float Process(float aIn)
    {
        const float out = m_b0 * aIn + m_z1;
        m_z1 = m_b1 * aIn - m_a1 * out + m_z2;
        m_z2 = m_b2 * aIn - m_a2 * out;
        return out;
    }

private:
    float m_b0, m_b1, m_b2, m_a1, m_a2;
    float m_z1 = 0.f;
    float m_z2 = 0.f;
};

// Butterworth highpass, from the same cookbook.
class Highpass2
{
public:
    Highpass2(float aHz, int aRate)
    {
        const double w = 2.0 * kPi * aHz / aRate;
        const double alpha = std::sin(w) / (2.0 * 0.7071);
        const double a0 = 1.0 + alpha;
        m_b0 = static_cast<float>((1.0 + std::cos(w)) / 2.0 / a0);
        m_b1 = static_cast<float>(-(1.0 + std::cos(w)) / a0);
        m_b2 = m_b0;
        m_a1 = static_cast<float>(-2.0 * std::cos(w) / a0);
        m_a2 = static_cast<float>((1.0 - alpha) / a0);
    }
    float Process(float aIn)
    {
        const float out = m_b0 * aIn + m_z1;
        m_z1 = m_b1 * aIn - m_a1 * out + m_z2;
        m_z2 = m_b2 * aIn - m_a2 * out;
        return out;
    }

private:
    float m_b0, m_b1, m_b2, m_a1, m_a2;
    float m_z1 = 0.f;
    float m_z2 = 0.f;
};

// Lifts quiet sounds a little, the way a tactical headset's talk-through makes footsteps easier to hear.
class Lift
{
public:
    Lift(float aBelowDb, int aRate)
        : m_belowDb(aBelowDb), m_power(Coefficient(30.f, aRate)), m_down(Coefficient(kLiftDownMs, aRate)),
          m_up(Coefficient(kLiftUpMs, aRate))
    {
    }

    float Gain(float aIn)
    {
        m_level += (aIn * aIn - m_level) * m_power;
        const float levelDb = 10.f * std::log10(std::max(m_level, 1e-12f));
        float target = 0.f;
        if (levelDb < m_belowDb && levelDb > kLiftFloorDb)
        {
            target = std::min(kLiftMostDb, (m_belowDb - levelDb) * kLiftRatio) * std::min(1.f, (levelDb - kLiftFloorDb) / 10.f);
        }
        m_liftDb += (target - m_liftDb) * (target < m_liftDb ? m_down : m_up);
        m_most = std::max(m_most, m_liftDb);
        m_sumDb += m_liftDb;
        ++m_samples;
        return std::pow(10.f, m_liftDb / 20.f);
    }

    float MostDb() const
    {
        return m_most;
    }
    float MeanDb() const
    {
        return m_samples ? static_cast<float>(m_sumDb / m_samples) : 0.f;
    }

private:
    float m_belowDb;
    float m_power;
    float m_down;
    float m_up;
    float m_level = 0.f;
    float m_liftDb = 0.f;
    float m_most = 0.f;
    double m_sumDb = 0.0;
    int64_t m_samples = 0;
};

// No look-ahead, like a headset's: it reacts to a peak as it happens. aSteepness 1 holds peaks at the threshold; more turns
// a sound that many dB down for each dB it goes over, as far as aDeepestDb. With aSlowReleaseMs, recovery slows towards
// that while bangs keep coming.
class Limiter
{
public:
    Limiter(float aThreshold, int aRate, float aSteepness = 1.f, float aDeepestDb = 120.f, float aSlowReleaseMs = 0.f)
        : m_threshold(aThreshold), m_release(Coefficient(kReleaseMs, aRate)),
          m_holdSamples(static_cast<int>(kPeakHoldMs * aRate / 1000.f)), m_sink(1.f - Coefficient(kPeakHoldMs, aRate)),
          m_steepness(aSteepness), m_floor(std::pow(10.f, -aDeepestDb / 20.f)),
          m_slowRelease(aSlowReleaseMs > 0.f ? Coefficient(aSlowReleaseMs, aRate) : 0.f),
          m_busyRise(Coefficient(kBusyRiseMs, aRate)), m_busyFall(Coefficient(kBusyFallMs, aRate))
    {
    }

    float Process(float aIn)
    {
        return aIn * Track(aIn);
    }

    // Follows aDetect and returns the gain for it, to apply to aDetect or to another signal.
    float Track(float aDetect)
    {
        // The peak jumps up at once, stays for the hold, then sinks. The gain drops with it at once and recovers at the
        // release speed.
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
        if (m_peak > m_threshold)
        {
            const float ratio = m_threshold / m_peak;
            target = std::max(m_steepness == 1.f ? ratio : std::pow(ratio, m_steepness), m_floor);
        }
        float release = m_release;
        if (m_slowRelease > 0.f)
        {
            const bool down = m_gain < 0.5f; // over 6 dB
            m_busy += ((down ? 1.f : 0.f) - m_busy) * (down ? m_busyRise : m_busyFall);
            release += (m_slowRelease - m_release) * m_busy;
        }
        m_gain = target < m_gain ? target : m_gain + (target - m_gain) * release;
        m_deepest = std::min(m_deepest, m_gain);
        m_clampedSamples += m_gain < 0.708f ? 1 : 0; // more than 3 dB
        ++m_samples;
        // A breath: well down, then back up near full, as happens between shots when it recovers too fast.
        if (m_gain < 0.316f) // -10 dB
        {
            m_armed = true;
        }
        else if (m_armed && m_gain > 0.708f)
        {
            m_armed = false;
            ++m_breaths;
        }
        return m_gain;
    }

    int Breaths() const
    {
        return m_breaths;
    }

    float DeepestDb() const
    {
        return 20.f * std::log10(std::max(m_deepest, 1e-6f));
    }
    double ClampedShare() const
    {
        return m_samples ? static_cast<double>(m_clampedSamples) / m_samples : 0.0;
    }

private:
    float m_threshold;
    float m_release;
    int m_holdSamples;
    float m_sink;
    float m_steepness;
    float m_floor;
    float m_slowRelease;
    float m_busyRise;
    float m_busyFall;
    float m_busy = 0.f;
    bool m_armed = false;
    int m_breaths = 0;
    int m_holdLeft = 0;
    float m_peak = 0.f;
    float m_gain = 1.f;
    float m_deepest = 1.f;
    int64_t m_clampedSamples = 0;
    int64_t m_samples = 0;
};

// The middle of the recording's 50 ms levels, leaving out silence: what "normal" sounds like in it.
float TypicalLevel(const Audio& aAudio)
{
    const size_t window = static_cast<size_t>(aAudio.rate / 20) * aAudio.channels;
    std::vector<float> levels;
    for (size_t start = 0; start + window <= aAudio.samples.size(); start += window)
    {
        double sum = 0.0;
        for (size_t i = start; i < start + window; ++i)
        {
            sum += static_cast<double>(aAudio.samples[i]) * aAudio.samples[i];
        }
        const float rms = static_cast<float>(std::sqrt(sum / window));
        if (rms > 0.001f) // -60 dB
        {
            levels.push_back(rms);
        }
    }
    if (levels.empty())
    {
        return 0.f;
    }
    std::nth_element(levels.begin(), levels.begin() + levels.size() / 2, levels.end());
    return levels[levels.size() / 2];
}

float PeakDb(const Audio& aAudio)
{
    float peak = 0.f;
    for (const float sample : aAudio.samples)
    {
        peak = std::max(peak, std::fabs(sample));
    }
    return 20.f * std::log10(std::max(peak, 1e-6f));
}
} // namespace

int wmain(int aCount, wchar_t** aArguments)
{
    if (aCount < 2)
    {
        std::printf("headset_clamp <recording.wav> [threshold dB over the typical level, default %.0f]\n", kThresholdOverTypicalDb);
        std::printf("headset_clamp <recording.wav> --at <threshold dB>\n");
        return 1;
    }
    const std::filesystem::path input = aArguments[1];
    const bool fixed = aCount > 3 && std::wcscmp(aArguments[2], L"--at") == 0;
    const float fixedDb = fixed ? static_cast<float>(_wtof(aArguments[3])) : 0.f;
    const float givenOverDb = !fixed && aCount > 2 ? static_cast<float>(_wtof(aArguments[2])) : kThresholdOverTypicalDb;
    Audio original;
    if (!ReadWav(input, original))
    {
        std::printf("Couldn't read %ls as a WAV.\n", input.c_str());
        return 1;
    }
    const float typical = TypicalLevel(original);
    if (typical <= 0.f)
    {
        std::printf("%ls is silent.\n", input.c_str());
        return 1;
    }
    const float overDb = fixed ? fixedDb - 20.f * std::log10(typical) : givenOverDb;
    const float threshold = typical * std::pow(10.f, overDb / 20.f);
    const int channels = original.channels;
    const size_t frames = original.samples.size() / channels;
    std::printf("%ls: %.1f s, %d channel(s), %d Hz\n", input.filename().c_str(), static_cast<double>(frames) / original.rate,
                channels, original.rate);
    std::printf("  typical level %.1f dB, loudest peak %.1f dB, clamping peaks over %.1f dB (%.0f dB over typical)\n",
                20.f * std::log10(typical), PeakDb(original), 20.f * std::log10(threshold), overDb);

    Audio limited = original;
    Audio headset = original;
    Audio headset2 = original;
    Audio headset3 = original;
    const float leakGain = std::pow(10.f, kLeakDb / 20.f);
    const float leak2Gain = std::pow(10.f, kLeak2Db / 20.f);
    const float liftBelowDb = 20.f * std::log10(threshold) - kLiftBelowDb;
    for (int channel = 0; channel < channels; ++channel)
    {
        Limiter plain(threshold, original.rate);
        Limiter microphone(threshold, original.rate);
        Limiter microphone2(threshold, original.rate, kSteepness, kDeepestDb);
        Limiter microphone3(threshold, original.rate, kSteepness, kDeepestDb, kReleaseSlowMs);
        OnePole micLow(kMicLowHz, original.rate);
        Lowpass2 micHigh(kMicHighHz, original.rate);
        OnePole leak(kLeakHz, original.rate);
        Lowpass2 leak2(kLeak2Hz, original.rate);
        Highpass2 detectLow(kDetectLowHz, original.rate);
        Lift lift(liftBelowDb, original.rate);
        for (size_t frame = 0; frame < frames; ++frame)
        {
            const size_t index = frame * channels + channel;
            const float in = original.samples[index];
            limited.samples[index] = plain.Process(in);
            const float picked = micHigh.Process(micLow.Highpass(in));
            headset.samples[index] = microphone.Process(picked) + leak.Lowpass(in) * leakGain;
            const float leaked = leak2.Process(in) * leak2Gain;
            headset2.samples[index] = picked * microphone2.Track(in) + leaked;
            headset3.samples[index] = picked * lift.Gain(picked) * microphone3.Track(detectLow.Process(in)) + leaked;
        }
        const char* ear = channels == 1 ? "mono" : channel == 0 ? "left" : "right";
        std::printf("  %s, down at most and share of time over 3 dB down: limiter %.1f dB %.1f%%, headset microphones %.1f dB "
                    "%.1f%%, headset 2 microphones %.1f dB %.1f%%, headset 3 microphones %.1f dB %.1f%%\n",
                    ear, -plain.DeepestDb(), plain.ClampedShare() * 100.0, -microphone.DeepestDb(),
                    microphone.ClampedShare() * 100.0, -microphone2.DeepestDb(), microphone2.ClampedShare() * 100.0,
                    -microphone3.DeepestDb(), microphone3.ClampedShare() * 100.0);
        std::printf("  %s, breaths (down 10 dB, then back within 3 dB): headset 2 %d, headset 3 %d; headset 3 lift %.1f dB at "
                    "most, %.1f dB on average\n",
                    ear, microphone2.Breaths(), microphone3.Breaths(), lift.MostDb(), lift.MeanDb());
    }

    // Headset 3's character, which needs both ears at once: a narrower picture, and the electronics' hiss in each ear.
    if (channels == 2)
    {
        uint32_t seed = 0x9e3779b9u;
        const auto noise = [&seed] {
            seed = seed * 1664525u + 1013904223u;
            return static_cast<float>(static_cast<int32_t>(seed)) / 2147483648.f;
        };
        std::vector<float> hiss(headset3.samples.size());
        for (int channel = 0; channel < 2; ++channel)
        {
            OnePole low(kHissLowHz, original.rate);
            Lowpass2 high(kHissHighHz, original.rate);
            for (size_t frame = 0; frame < frames; ++frame)
            {
                hiss[frame * 2 + channel] = high.Process(low.Highpass(noise()));
            }
        }
        double power = 0.0;
        for (const float sample : hiss)
        {
            power += static_cast<double>(sample) * sample;
        }
        const float hissGain =
            std::pow(10.f, kHissDb / 20.f) / static_cast<float>(std::sqrt(std::max(power / hiss.size(), 1e-20)));
        for (size_t frame = 0; frame < frames; ++frame)
        {
            float& left = headset3.samples[frame * 2];
            float& right = headset3.samples[frame * 2 + 1];
            const float middle = (left + right) * 0.5f;
            const float side = (left - right) * 0.5f * kWidth;
            left = middle + side + hiss[frame * 2] * hissGain;
            right = middle - side + hiss[frame * 2 + 1] * hissGain;
        }
    }

    const auto named = [&](const wchar_t* aSuffix) {
        std::filesystem::path path = input;
        path.replace_filename(input.stem().wstring() + aSuffix);
        return path;
    };
    if (!WriteWav(named(L"-limiter.wav"), limited) || !WriteWav(named(L"-headset.wav"), headset) ||
        !WriteWav(named(L"-headset2.wav"), headset2) || !WriteWav(named(L"-headset3.wav"), headset3))
    {
        std::printf("Couldn't write the results.\n");
        return 1;
    }
    std::printf("  loudest peak now: limiter %.1f dB, headset %.1f dB, headset 2 %.1f dB, headset 3 %.1f dB\n", PeakDb(limited),
                PeakDb(headset), PeakDb(headset2), PeakDb(headset3));
    std::printf("Wrote the -limiter, -headset, -headset2 and -headset3 versions\n");
    return 0;
}
