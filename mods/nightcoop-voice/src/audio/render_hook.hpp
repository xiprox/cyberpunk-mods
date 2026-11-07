// Puts the headset on the game's own sound. The game makes its sound with an engine built into its exe and hands each
// filled buffer to Windows through the usual audio interface; the mod lives in the same process, so it patches that
// interface's shared function tables and runs the headset over each buffer, in place, just before Windows takes it. That
// happens on the game's own audio thread, adds no delay, and never waits on anything.
//
// It only touches streams it saw being set up, in 32-bit float, and never the mod's own. Anything else passes untouched.
#pragma once

#include <cstdint>
#include <string>

namespace nv
{
// Once, as early as possible: before the game sets up its sound. False, with the reason logged, if it couldn't.
bool InstallRenderHook();

// The mod's own audio streams, opened on this thread while this is set, are left alone.
void SetOwnStreamsOnThisThread(bool aOwn);

struct RenderHookCounts
{
    uint32_t streamsSeen = 0;  // set up since the hook went in
    uint32_t streamsUsed = 0;  // of those, the ones the headset can run on
    uint64_t buffersRun = 0;   // buffers the headset ran over
    uint64_t buffersOwn = 0;   // the mod's own buffers, left alone
};
RenderHookCounts GetRenderHookCounts();
} // namespace nv
