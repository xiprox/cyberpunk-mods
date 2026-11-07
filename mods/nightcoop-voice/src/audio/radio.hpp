// What the radio does to a voice, in the order it would happen for real: a boom mic driven hard, the digital encoding of a
// military radio, then a small earpiece in one ear.
#pragma once

#include "audio/dsp.hpp"

#include <cstdint>

namespace nv
{
enum class RadioEar : int
{
    Left = 0,
    Right = 1,
    Both = 2, // speakers: there's no earpiece to sit in one ear
};

// One ear sounds quieter than two at the same level, so the earpiece plays this much above what both ears would get.
constexpr float kRadioBothEarsGain = 0.63f; // about -4 dB

class RadioEffect
{
public:
    RadioEffect();

    // The short click of a radio keying up. It plays through the earpiece whatever the voice's fade is doing.
    void KeyUp();
    bool IsClicking() const
    {
        return m_clickLeft > 0;
    }

    // One sample at 48 kHz. aVoiceGain fades the voice in and out. aOnEar is the ear wearing the earpiece, aOtherEar the
    // little that leaks around the head to the other one.
    void Process(float aSample, float aVoiceGain, float& aOnEar, float& aOtherEar);

private:
    static constexpr int kHistory = 64; // a power of two, and longer than any delay in here

    float Encode(float aInput);
    float Back(int aSamples) const;

    Biquad m_inHigh;
    Biquad m_inLow1;
    Biquad m_inLow2;

    int m_encodePhase = 0;
    float m_decoded = 0.f;
    float m_estimate = 0.f;
    float m_step = 0.f;
    uint32_t m_bits = 0;

    Biquad m_outHigh1;
    Biquad m_outHigh2;
    Biquad m_outLow1;
    Biquad m_outLow2;
    Biquad m_peak;

    float m_history[kHistory]{};
    int m_write = 0;
    OnePole m_leak;

    int m_clickLeft = 0;
    uint32_t m_noise = 0x12345;
};
} // namespace nv
