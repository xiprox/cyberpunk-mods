// What one channel of a bus sounds like through the headset. Ported from "headset3" in NightCoop Voice, tuned there by ear
// ("feels fantastic"): the outside microphones' thinner sound, which the clamp turns down, and what gets through the cups, which
// nothing turns down. A real headset lets a gunshot through its cups by far more than through its microphones (RECORD.md).
#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>

namespace hs
{
inline constexpr double kTwoPi = 6.283185307179586;
inline constexpr float kMicLowHz = 120.f;   // small outside microphones lose the deepest bass
inline constexpr float kMicHighHz = 7000.f; // and the very top
inline constexpr float kLeakHz = 300.f;     // two-pole: about 21 dB more off at 1 kHz, 33 at 2 kHz
inline constexpr float kRecoilHz = 120.f;   // what's boosted of your own shot, felt more than heard
inline constexpr float kNoiseLowHz = 500.f;  // noise cancelling's own lows, where its microphones do the work
inline constexpr float kNoiseHighHz = 4000.f;
inline constexpr float kBodyHz = 700.f;     // below this, V's voice reaches V through the skull
inline constexpr float kHissLowHz = 300.f;
inline constexpr float kHissHighHz = 6000.f;
inline constexpr int kMaxEars = 8;

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

// Butterworth, from the usual cookbook.
class Lowpass2
{
public:
    void Set(float aHz, int aRate)
    {
        const double w = kTwoPi * aHz / aRate;
        const double alpha = std::sin(w) / (2.0 * 0.7071);
        const double a0 = 1.0 + alpha;
        m_b0 = static_cast<float>((1.0 - std::cos(w)) / 2.0 / a0);
        m_b1 = static_cast<float>((1.0 - std::cos(w)) / a0);
        m_b2 = m_b0;
        m_a1 = static_cast<float>(-2.0 * std::cos(w) / a0);
        m_a2 = static_cast<float>((1.0 - alpha) / a0);
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
    float m_b0 = 1.f, m_b1 = 0.f, m_b2 = 0.f, m_a1 = 0.f, m_a2 = 0.f;
    float m_z1 = 0.f, m_z2 = 0.f;
};

struct Ear
{
    RatePole micLow;
    Lowpass2 micHigh;
    Lowpass2 leak;
    Lowpass2 noiseLow;
    Lowpass2 noiseHigh;
    Lowpass2 body;

    void Configure(int aRate)
    {
        micLow.Set(kMicLowHz, aRate);
        micHigh.Set(kMicHighHz, aRate);
        leak.Set(kLeakHz, aRate);
        noiseLow.Set(kNoiseLowHz, aRate);
        noiseHigh.Set(kNoiseHighHz, aRate);
        body.Set(kBodyHz, aRate);
    }
    void Reset()
    {
        micLow.Reset();
        micHigh.Reset();
        leak.Reset();
        noiseLow.Reset();
        noiseHigh.Reset();
        body.Reset();
    }

    // aMic turns the microphones down (and up, for the lift); the cups' leak is never turned down.
    float Process(float aIn, float aMic, float aLeakGain)
    {
        return micHigh.Process(micLow.Highpass(aIn)) * aMic + leak.Process(aIn) * aLeakGain;
    }

    // Three bands, split so that with all three gains at 1 the sound comes out exactly as it went in.
    float NoiseCancel(float aIn, float aLow, float aMid, float aHigh)
    {
        const float low = noiseLow.Process(aIn);
        const float upTo4k = noiseHigh.Process(aIn);
        const float high = aIn - upTo4k;
        const float mid = upTo4k - low;
        return low * aLow + mid * aMid + high * aHigh;
    }

    // V's own voice: the part below kBodyHz arrives through the skull, the rest through the air, which the headset can take away.
    float Voice(float aIn, float aBody, float aAir)
    {
        const float low = body.Process(aIn);
        return low * aBody + (aIn - low) * aAir;
    }
};

// The talk-through electronics' own faint hiss.
class Hiss
{
public:
    void Configure(int aRate)
    {
        for (int side = 0; side < 2; ++side)
        {
            m_low[side].Set(kHissLowHz, aRate);
            m_high[side].Set(kHissHighHz, aRate);
        }
        // Measure what the filters leave of the noise, so the hiss lands at its level whatever the rate.
        double power = 0.0;
        for (int i = 0; i < aRate; ++i)
        {
            const float sample = Next(0);
            power += static_cast<double>(sample) * sample;
        }
        m_unit = 1.f / static_cast<float>(std::sqrt(std::max(power / aRate, 1e-20)));
        Reset();
    }
    void Reset()
    {
        for (int side = 0; side < 2; ++side)
        {
            m_low[side].Reset();
            m_high[side].Reset();
        }
    }
    float Next(int aSide)
    {
        m_seed = m_seed * 1664525u + 1013904223u;
        const float noise = static_cast<float>(static_cast<int32_t>(m_seed)) / 2147483648.f;
        return m_high[aSide].Process(m_low[aSide].Highpass(noise));
    }
    float Unit() const
    {
        return m_unit;
    }

private:
    RatePole m_low[2];
    Lowpass2 m_high[2];
    uint32_t m_seed = 0x9e3779b9u;
    float m_unit = 1.f;
};
} // namespace hs
