// Small building blocks for the mic chain, the proximity voice and the radio voice.
#pragma once

#include "core/common.hpp"

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <vector>

namespace nv
{
constexpr float kPi = 3.14159265358979f;

inline float Clamp01(float aValue)
{
    return std::clamp(aValue, 0.f, 1.f);
}

inline float SoftClip(float aSample)
{
    const float magnitude = std::fabs(aSample);
    if (magnitude <= 0.8f)
    {
        return aSample;
    }
    // Eases from linear at 0.8 toward 1.0 without a corner.
    const float over = (magnitude - 0.8f) / 0.2f;
    const float shaped = 0.8f + 0.2f * (over / (1.f + over));
    return aSample < 0.f ? -shaped : shaped;
}

class OnePole
{
public:
    void SetCutoff(float aHz)
    {
        m_coefficient = 1.f - std::exp(-2.f * kPi * std::clamp(aHz, 20.f, 22000.f) / kRate);
    }

    float Lowpass(float aInput)
    {
        m_state += m_coefficient * (aInput - m_state);
        return m_state;
    }

    void Reset()
    {
        m_state = 0.f;
    }

private:
    float m_coefficient = 1.f;
    float m_state = 0.f;
};

class Biquad
{
public:
    void SetLowpass(float aHz, float aQ = 0.707f)
    {
        const float w = 2.f * kPi * aHz / kRate;
        const float alpha = std::sin(w) / (2.f * aQ);
        const float cosW = std::cos(w);
        Set((1.f - cosW) / 2.f, 1.f - cosW, (1.f - cosW) / 2.f, 1.f + alpha, -2.f * cosW, 1.f - alpha);
    }

    void SetHighpass(float aHz, float aQ = 0.707f)
    {
        const float w = 2.f * kPi * aHz / kRate;
        const float alpha = std::sin(w) / (2.f * aQ);
        const float cosW = std::cos(w);
        Set((1.f + cosW) / 2.f, -(1.f + cosW), (1.f + cosW) / 2.f, 1.f + alpha, -2.f * cosW, 1.f - alpha);
    }

    void SetPeak(float aHz, float aQ, float aDb)
    {
        const float a = std::pow(10.f, aDb / 40.f);
        const float w = 2.f * kPi * aHz / kRate;
        const float alpha = std::sin(w) / (2.f * aQ);
        const float cosW = std::cos(w);
        Set(1.f + alpha * a, -2.f * cosW, 1.f - alpha * a, 1.f + alpha / a, -2.f * cosW, 1.f - alpha / a);
    }

    float Process(float aInput)
    {
        const float output = m_b0 * aInput + m_z1;
        m_z1 = m_b1 * aInput - m_a1 * output + m_z2;
        m_z2 = m_b2 * aInput - m_a2 * output;
        return output;
    }

private:
    void Set(float aB0, float aB1, float aB2, float aA0, float aA1, float aA2)
    {
        m_b0 = aB0 / aA0;
        m_b1 = aB1 / aA0;
        m_b2 = aB2 / aA0;
        m_a1 = aA1 / aA0;
        m_a2 = aA2 / aA0;
    }

    float m_b0 = 1.f;
    float m_b1 = 0.f;
    float m_b2 = 0.f;
    float m_a1 = 0.f;
    float m_a2 = 0.f;
    float m_z1 = 0.f;
    float m_z2 = 0.f;
};

// Temporary, for tuning by ear: Engine reads these from tuning.ini while the game runs, if that file exists on this PC, so
// levels can be tried without a restart. Once they're right they go into the constants and all of this comes out.
struct LiveTuning
{
    std::atomic<float> roomDb{0.f}; // added to the room's level
    std::atomic<float> ring{1.f};   // times the decay
    std::atomic<float> echoDb{0.f};
    std::atomic<float> ownDb{0.f};  // your own voice in the room, on top of roomDb

    // From the Settings choice "Distance falloff (test)", not tuning.ini: the share of today's dB a voice loses with
    // distance, and whether that lift eases back to today's curve between 20 and 40 m.
    std::atomic<float> falloff{1.f};
    std::atomic<bool> falloffTaper{false};

    // headset_solo=1: the radio key puts the headset on with no session, to try it alone (2026-11-07).
    std::atomic<bool> headsetSolo{false};
    // The radio headset, to tune it gentler or firmer by ear in the game (2026-11-07).
    std::atomic<float> headsetDb{0.f};          // added to its clamp level: up means only louder sounds get turned down
    std::atomic<float> headsetSteep{3.f};       // dB down for each dB over it
    std::atomic<float> headsetDeepestDb{40.f};  // how far down it can go
    std::atomic<float> headsetHissDb{0.f};      // added to its hiss
};
inline LiveTuning g_liveTuning;

// What surrounds someone, as measured by rays.
struct RoomSound
{
    float enclosure = 0.f;     // 0 open air .. 1 closed in
    float meters = 8.f;        // how far a sound travels on average before it meets something
    float decaySeconds = 0.6f; // how long it rings for
};

// The sound of a space: two feedback delay networks, one with a small room's echo spacing and one with a big space's. Their
// delays never change, because moving a delay while sound is in it is heard as a warble, and rays and slow motion both
// change the room quickly. A change of room moves what goes in from one network to the other, and how fast they die.
class RoomReverb
{
public:
    RoomReverb();

    // Eases to these over about half a second.
    void SetRoom(const RoomSound& aRoom);

    // Reads aSend and adds the room's sound to aLeft and aRight. All hold aFrames samples. The sound that comes out holds
    // the same energy whatever the decay, so a long decay rings longer without getting louder.
    void Process(const float* aSend, float* aLeft, float* aRight, int aFrames);

private:
    static constexpr int kLines = 8;

    struct Network
    {
        std::array<std::vector<float>, kLines> lines;
        std::array<size_t, kLines> positions{};
        std::array<float, kLines> damped{};
        std::array<float, kLines> gains{};
        float damping = 0.f;
        float meanDelay = 0.f;
        float inputGain = 0.f;
        std::vector<float> preDelay;
        size_t preDelayPosition = 0;
    };

    struct Diffuser
    {
        std::vector<float> buffer;
        size_t position = 0;
    };

    void SetDecay(Network& aNetwork, float aDecaySeconds);
    void Step(Network& aNetwork, float aInput, float& aLeft, float& aRight);

    Network m_small;
    Network m_large;
    std::array<Diffuser, 4> m_diffusers;
    RoomSound m_target;
    float m_decay = 0.6f;
    float m_appliedDecay = 0.f;
    float m_size = 0.f;
    float m_wet = 0.f;
};

// Any input rate to 48 kHz or back, by straight lines between samples. Windows does the good conversion whenever it
// can; this is only for audio drivers that refuse it.
class Resampler
{
public:
    void SetRatio(double aInputRate, double aOutputRate)
    {
        m_step = aInputRate / aOutputRate;
    }

    template<typename Emit>
    void Process(const float* aInput, int aCount, Emit&& aEmit)
    {
        for (int i = 0; i < aCount; ++i)
        {
            const float current = aInput[i];
            while (m_phase < 1.0)
            {
                aEmit(m_previous + static_cast<float>(m_phase) * (current - m_previous));
                m_phase += m_step;
            }
            m_phase -= 1.0;
            m_previous = current;
        }
    }

private:
    double m_step = 1.0;
    double m_phase = 0.0;
    float m_previous = 0.f;
};
} // namespace nv
