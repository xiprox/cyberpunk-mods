// Turns a recording of the game into versions to compare by ear, for the headset idea in RECORD.md (2026-11-07):
//   <name>-limiter.wav   a plain fast limiter on each ear, about how a clamp in the mod could act
//   <name>-headset.wav   a model of a tactical headset: what its outside microphones pick up is limited and loses a little
//                        top end, while what leaks through the ear cups never is, but loses far more treble than bass.
//                        So a blast shrinks to a muffled thump while quiet sounds come through as they were.
// Both are written next to the recording at the same level as it, so they can be compared straight against it.
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

// No look-ahead, like a headset's: it reacts to a peak as it happens.
class Limiter
{
public:
    Limiter(float aThreshold, int aRate)
        : m_threshold(aThreshold), m_release(Coefficient(kReleaseMs, aRate)),
          m_holdSamples(static_cast<int>(kPeakHoldMs * aRate / 1000.f)), m_sink(1.f - Coefficient(kPeakHoldMs, aRate))
    {
    }

    float Process(float aIn)
    {
        // The peak jumps up at once, stays for the hold, then sinks; the gain follows it at the attack and release speeds.
        const float level = std::fabs(aIn);
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
        const float target = m_peak > m_threshold ? m_threshold / m_peak : 1.f;
        m_gain = target < m_gain ? target : m_gain + (target - m_gain) * m_release;
        m_deepest = std::min(m_deepest, m_gain);
        m_clampedSamples += m_gain < 0.708f ? 1 : 0; // more than 3 dB
        ++m_samples;
        return aIn * m_gain;
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
    const float leakGain = std::pow(10.f, kLeakDb / 20.f);
    for (int channel = 0; channel < channels; ++channel)
    {
        Limiter plain(threshold, original.rate);
        Limiter microphone(threshold, original.rate);
        OnePole micLow(kMicLowHz, original.rate);
        Lowpass2 micHigh(kMicHighHz, original.rate);
        OnePole leak(kLeakHz, original.rate);
        for (size_t frame = 0; frame < frames; ++frame)
        {
            const size_t index = frame * channels + channel;
            const float in = original.samples[index];
            limited.samples[index] = plain.Process(in);
            const float picked = micHigh.Process(micLow.Highpass(in));
            headset.samples[index] = microphone.Process(picked) + leak.Lowpass(in) * leakGain;
        }
        const char* ear = channels == 1 ? "mono" : channel == 0 ? "left" : "right";
        std::printf("  %s: limiter down %.1f dB at most, over 3 dB down %.1f%% of the time; headset microphones down %.1f dB at "
                    "most, %.1f%% of the time\n",
                    ear, -plain.DeepestDb(), plain.ClampedShare() * 100.0, -microphone.DeepestDb(),
                    microphone.ClampedShare() * 100.0);
    }

    std::filesystem::path limitedPath = input;
    limitedPath.replace_filename(input.stem().wstring() + L"-limiter.wav");
    std::filesystem::path headsetPath = input;
    headsetPath.replace_filename(input.stem().wstring() + L"-headset.wav");
    if (!WriteWav(limitedPath, limited) || !WriteWav(headsetPath, headset))
    {
        std::printf("Couldn't write the results.\n");
        return 1;
    }
    std::printf("  loudest peak now: limiter %.1f dB, headset %.1f dB\n", PeakDb(limited), PeakDb(headset));
    std::printf("Wrote %ls and %ls\n", limitedPath.filename().c_str(), headsetPath.filename().c_str());
    return 0;
}
