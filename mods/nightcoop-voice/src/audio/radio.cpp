#include "audio/radio.hpp"

#include <cmath>

namespace nv
{
namespace
{
constexpr float kMicDrive = 4.f;             // a boom mic at the lips, into a hard limiter

// The band a radio carries.
constexpr float kBandLowHz = 350.f;
constexpr float kBandHighHz = 3400.f;

// CVSD at 16 kbit/s, the voice encoding of military radios. One bit per sample says "up" or "down", and the size of the
// step grows when the bits keep agreeing. Too small a step leaves a fizz on quiet sounds, too large a one a rasp on loud
// ones, and that's the grit.
constexpr int kEncodeEvery = 3;              // 48 kHz down to 16 kHz
constexpr float kStepMin = 0.006f;
constexpr float kStepMax = 0.20f;
constexpr float kStepRise = 0.05f;           // per sample while the last three bits agree
constexpr float kStepFall = 0.993f;          // otherwise: gone in about 9 ms
constexpr float kEstimateLeak = 0.94f;       // about 1 ms, so a bit error or a click can't linger
constexpr float kGrit = 0.6f;                // how much of the encoded signal to hear; all of it is harsh over a gunfight

// A small driver: no bass, and a peak where it rings.
constexpr float kPeakHz = 2500.f;
constexpr float kPeakQ = 1.2f;
constexpr float kPeakDb = 6.f;

// Sound bouncing inside the earpiece, under a millisecond. It's what makes this a small object at your ear.
constexpr int kCupFirstSamples = 17;
constexpr float kCupFirst = 0.35f;
constexpr int kCupSecondSamples = 38;
constexpr float kCupSecond = -0.2f;

constexpr float kSpeakerDrive = 1.2f;
constexpr float kOutput = 0.82f;             // set by measuring: see the loudness check in tools/voice_test.cpp

// What reaches the other ear: faint, late and muffled by the head.
constexpr int kLeakSamples = 30;             // about 0.6 ms
constexpr float kLeakHz = 900.f;
constexpr float kLeakGain = 0.08f;           // about -22 dB

constexpr int kClickSamples = kRate * 6 / 1000;
constexpr float kClickLevel = 0.8f;
} // namespace

RadioEffect::RadioEffect()
{
    m_inHigh.SetHighpass(kBandLowHz);
    m_inLow1.SetLowpass(kBandHighHz);
    m_inLow2.SetLowpass(kBandHighHz);
    m_outHigh1.SetHighpass(kBandLowHz);
    m_outHigh2.SetHighpass(kBandLowHz);
    m_outLow1.SetLowpass(kBandHighHz);
    m_outLow2.SetLowpass(kBandHighHz);
    m_peak.SetPeak(kPeakHz, kPeakQ, kPeakDb);
    m_leak.SetCutoff(kLeakHz);
    m_step = kStepMin;
}

void RadioEffect::KeyUp()
{
    m_clickLeft = kClickSamples;
}

float RadioEffect::Encode(float aInput)
{
    const bool up = aInput >= m_estimate;
    m_bits = ((m_bits << 1) | (up ? 1u : 0u)) & 7u;
    if (m_bits == 0u || m_bits == 7u)
    {
        m_step += (kStepMax - m_step) * kStepRise;
    }
    else
    {
        m_step = std::max(m_step * kStepFall, kStepMin);
    }
    m_estimate = m_estimate * kEstimateLeak + (up ? m_step : -m_step);
    return m_estimate;
}

float RadioEffect::Back(int aSamples) const
{
    return m_history[(m_write - aSamples + kHistory) & (kHistory - 1)];
}

void RadioEffect::Process(float aSample, float aVoiceGain, float& aOnEar, float& aOtherEar)
{
    float input = std::tanh(aSample * kMicDrive);
    input = m_inHigh.Process(input);
    input = m_inLow2.Process(m_inLow1.Process(input));

    if (++m_encodePhase >= kEncodeEvery)
    {
        m_encodePhase = 0;
        m_decoded = Encode(input);
    }

    float signal = (input + (m_decoded - input) * kGrit) * aVoiceGain;
    if (m_clickLeft > 0)
    {
        // Linear congruential: plenty random for a click.
        m_noise = m_noise * 1664525u + 1013904223u;
        const float noise = static_cast<float>(static_cast<int32_t>(m_noise)) / 2147483648.f;
        const float fade = static_cast<float>(m_clickLeft) / kClickSamples;
        signal += noise * kClickLevel * fade * fade;
        --m_clickLeft;
    }

    signal = m_outHigh2.Process(m_outHigh1.Process(signal));
    signal = m_outLow2.Process(m_outLow1.Process(signal));
    signal = m_peak.Process(signal);

    const float inCup = signal + kCupFirst * Back(kCupFirstSamples) + kCupSecond * Back(kCupSecondSamples);
    aOnEar = std::tanh(inCup * kSpeakerDrive) * kOutput;
    aOtherEar = m_leak.Lowpass(Back(kLeakSamples)) * kLeakGain * kOutput;

    m_history[m_write] = signal;
    m_write = (m_write + 1) & (kHistory - 1);
}
} // namespace nv
