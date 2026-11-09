#include "headset/voices.hpp"

#include "core/common.hpp"
#include "headset/control.hpp"
#include "headset/sound.hpp"

#include <algorithm>
#include <cmath>

namespace hs
{
namespace
{
constexpr int kRate = 48000;
constexpr float kWearSeconds = 0.2f;
constexpr float kClampFollowMs = 3.f; // voices follow the world's clamp smoothly between its frames
constexpr double kWorldFreshMs = 500.0; // only while the world's sound is coming through

struct State
{
    Ear ears[2];
    float clamp = 1.f;
    float wear = 0.f;
    Mode active = Mode::Passthrough;
    bool configured = false;
};
State g_state;

float FromDb(float aDb)
{
    return std::pow(10.f, aDb / 20.f);
}

void Configure()
{
    for (Ear& ear : g_state.ears)
    {
        ear.Configure(kRate);
        ear.Reset();
    }
    g_state.configured = true;
}
} // namespace

void ResetNearbyVoices()
{
    g_state = State{};
}

void ProcessNearbyVoices(float* aLeft, float* aRight, int aFrames)
{
    State& state = g_state;
    if (!state.configured)
    {
        Configure();
    }
    const Mode wanted = EffectiveMode();
    if (state.wear <= 0.f)
    {
        if (state.active != wanted)
        {
            for (Ear& ear : state.ears)
            {
                ear.Reset();
            }
            state.clamp = 1.f;
        }
        state.active = wanted;
    }
    const bool worn = wanted != Mode::Passthrough && wanted == state.active;
    if (!worn && state.wear <= 0.f)
    {
        return;
    }

    const bool sound = g_control.soundOn.load(std::memory_order_relaxed);
    const bool fresh = NowMs() - g_control.worldClampAtMs.load(std::memory_order_relaxed) < kWorldFreshMs;
    const float target = fresh ? g_control.worldClamp.load(std::memory_order_relaxed) : 1.f;
    const float follow = 1.f - std::exp(-1000.f / (kClampFollowMs * static_cast<float>(kRate)));
    const float step = (worn ? 1.f : -1.f) / (kWearSeconds * static_cast<float>(kRate));
    const float leak = FromDb(g_control.leakDb.load(std::memory_order_relaxed));
    const float width = g_control.width.load(std::memory_order_relaxed);
    const float low = FromDb(g_control.noiseLowDb.load(std::memory_order_relaxed));
    const float mid = FromDb(g_control.noiseMidDb.load(std::memory_order_relaxed));
    const float high = FromDb(g_control.noiseHighDb.load(std::memory_order_relaxed));
    const float bangLow = FromDb(g_control.noiseBangLowDb.load(std::memory_order_relaxed));
    const float bangMid = FromDb(g_control.noiseBangMidDb.load(std::memory_order_relaxed));
    const float bangHigh = FromDb(g_control.noiseBangHighDb.load(std::memory_order_relaxed));
    const bool noiseCancelling = state.active == Mode::NoiseCancelling;

    for (int i = 0; i < aFrames; ++i)
    {
        state.wear = std::clamp(state.wear + step, 0.f, 1.f);
        state.clamp += (target - state.clamp) * follow;
        const float inLeft = aLeft[i];
        const float inRight = aRight[i];
        float wetLeft;
        float wetRight;
        if (!sound)
        {
            wetLeft = inLeft * state.clamp;
            wetRight = inRight * state.clamp;
        }
        else if (noiseCancelling)
        {
            const float bang = 1.f - state.clamp;
            const float l = low + (bangLow - low) * bang;
            const float m = mid + (bangMid - mid) * bang;
            const float h = high + (bangHigh - high) * bang;
            wetLeft = state.ears[0].NoiseCancel(inLeft, l, m, h);
            wetRight = state.ears[1].NoiseCancel(inRight, l, m, h);
        }
        else
        {
            // No lift: a voice nearby is far louder than the quiet sounds the talk-through lifts.
            const float a = state.ears[0].Process(inLeft, state.clamp, leak);
            const float b = state.ears[1].Process(inRight, state.clamp, leak);
            const float middle = (a + b) * 0.5f;
            const float side = (a - b) * 0.5f * width;
            wetLeft = middle + side;
            wetRight = middle - side;
        }
        aLeft[i] = inLeft + (wetLeft - inLeft) * state.wear;
        aRight[i] = inRight + (wetRight - inRight) * state.wear;
    }
}
} // namespace hs
