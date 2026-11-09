// Nearby voices from NightCoop Voice, 48 kHz stereo, through the headset: other players never pass through Wwise, so they're handed
// over here and treated as the world is at that moment. The radio is never sent here: it plays inside the headset.
#pragma once

namespace hs
{
// Only ever from one audio thread at a time, NightCoop Voice's mixer.
void ProcessNearbyVoices(float* aLeft, float* aRight, int aFrames);

// Back to where the mod starts, between tests.
void ResetNearbyVoices();
} // namespace hs
