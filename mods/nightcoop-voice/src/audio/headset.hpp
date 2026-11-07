// The tactical headset a player wears while their radio mic is on (RECORD.md, 2026-11-07). Its microphones pick up the
// world and play it in, a little thinner, with quiet sounds lifted and loud ones turned down steeply; its cups let a
// muffled leak through that's never turned down, so a blast becomes a thump without its crack. A faint hiss and a slightly
// narrower picture are there all the time, so wearing it is felt. Tuned by ear on recordings of the game as "headset3".
#pragma once

#include <atomic>
#include <cstdint>

namespace nv
{
// Shared by the engine, which decides, the game's own audio threads, which run the headset on the game's sound, and the
// mixer, which runs nearby voices through it.
struct HeadsetControl
{
    std::atomic<bool> on{false};          // radio mic on and the Headset setting on
    std::atomic<float> levelShiftDb{0.f}; // the game's Master volume in dB: the clamp, the lift and the hiss move with it

    // What the game's sound is doing to the headset's microphones right now, per ear, for nearby voices to follow.
    std::atomic<float> clamp[2]{1.f, 1.f};
    std::atomic<float> lift[2]{1.f, 1.f};
    std::atomic<double> gameAtMs{-1e9};

    // For the log, added up by the game's side and taken every 30 s.
    std::atomic<uint64_t> frames{0};
    std::atomic<uint64_t> wornFrames{0};
    std::atomic<float> deepestDb{0.f};
    std::atomic<uint32_t> breaths{0};
    std::atomic<uint64_t> costNs{0};
    std::atomic<uint32_t> buffers{0};
};
inline HeadsetControl g_headset;

// One stream of the game's sound, any rate and up to 8 channels, run in place on interleaved float samples. The first two
// channels are the ears; any others get the same treatment each on its own, without the narrowing and the hiss.
class HeadsetStream
{
public:
    static constexpr int kMaxChannels = 8;

    HeadsetStream();
    ~HeadsetStream();
    HeadsetStream(const HeadsetStream&) = delete;
    HeadsetStream& operator=(const HeadsetStream&) = delete;

    void Configure(int aChannels, int aRate);
    // aWorn: whether the headset is on. It eases on and off over a fifth of a second, and once fully off the samples are
    // left exactly as they came. aReport: this is the game's sound, which sets what nearby voices follow and the log.
    void Process(float* aSamples, uint32_t aFrames, bool aWorn, float aLevelShiftDb, bool aReport, double aNowMs);

    float WornAmount() const;

private:
    struct State;
    State* m_state;
};

// Nearby voices and their rooms, 48 kHz stereo, through the same headset: the same thinner sound and muffled leak, turned
// down and lifted as the game's own sound is at that moment. The radio never goes through this: it plays inside the
// earpiece.
class HeadsetVoices
{
public:
    HeadsetVoices();
    ~HeadsetVoices();
    HeadsetVoices(const HeadsetVoices&) = delete;
    HeadsetVoices& operator=(const HeadsetVoices&) = delete;

    void Process(float* aLeft, float* aRight, int aFrames, bool aWorn, double aNowMs);

private:
    struct State;
    State* m_state;
};
} // namespace nv
