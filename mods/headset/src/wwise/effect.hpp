// The headset's Wwise effect, which plays one of two roles depending on which bus it's on. A detector, on a bus of bangs,
// writes down how loud each sample was. A clamp, on a bus of what the microphones pick up, reads that and turns its bus down.
// Wwise runs a bus's children before the bus itself, in the same audio frame (RECORD.md), so a clamp above a detector already
// has that detector's levels for the samples it's about to turn down.
#pragma once

#include <cstdint>
#include <vector>

namespace hs
{
constexpr uint32_t kMaxFrames = 2048;

enum class Role : uint32_t
{
    Detector = 0,
    Clamp = 1,
};

// What Wwise's create callbacks return, usable from the test program too.
void* NewEffect();
void* NewParams();

// The bank declaring one share set per detector and one for the clamp.
std::vector<uint8_t> MakeBank();

// Whether reading an audio buffer has ever failed; the effect then leaves the sound alone.
bool AudioBroken();
void ClearAudioBroken();

// Back to no history, between tests.
void ResetTracks();
} // namespace hs
