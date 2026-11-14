// The Headset mod, if it's there: the world's sound is its own, and voice only hands it nearby voices.
// Without it, voice plays plain. Safe from any thread.
#pragma once

struct HeadsetApi;

namespace nv
{
// About once a second: looks for Headset.dll until it's found.
void RefreshHeadsetLink(double aNowMs);
bool HeadsetLinked();

// Whether the Headset mod is on in any mode, hearing protection or noise cancelling; false in Passthrough and without the mod.
bool HeadsetOn();

// Other players' nearby voices and their rooms, heard through the headset. The radio never goes through this: it plays inside it.
void ProcessVoicesThroughHeadset(float* aLeft, float* aRight, int aFrames);

// In place of finding the real thing, for the test program; null for none.
void SetHeadsetApiForTest(const HeadsetApi* aApi);
} // namespace nv
