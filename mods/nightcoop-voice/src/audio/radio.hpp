// What the radio does to a voice, in the order it would happen for real: a boom mic driven hard, the digital encoding of a
// military radio, then the small speakers in a tactical headset's ear cups.
#pragma once

#include "audio/dsp.hpp"

#include <cstdint>

namespace nv
{
// The radio plays in both ears, as in the headset, never in one (RECORD.md, 2026-11-07): the headset's clamp covers both
// ears either way. This puts it at a nearby voice's level; a single earpiece had needed about 4 dB more.
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

    // One sample at 48 kHz, for each ear. aVoiceGain fades the voice in and out.
    float Process(float aSample, float aVoiceGain);

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

    int m_clickLeft = 0;
    uint32_t m_noise = 0x12345;
};
} // namespace nv
