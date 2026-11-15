#include "audio/headset_link.hpp"

#include "core/common.hpp"
#include "headset_api.h"

#include <windows.h>

#include <atomic>

namespace nv
{
namespace
{
constexpr double kLookEveryMs = 1000.0;

std::atomic<const HeadsetApi*> g_api{nullptr};
std::atomic<bool> g_gaveUp{false};
double g_lastLookMs = -1e9;
} // namespace

void RefreshHeadsetLink(double aNowMs)
{
    if (g_api.load() || g_gaveUp.load() || aNowMs - g_lastLookMs < kLookEveryMs)
    {
        return;
    }
    g_lastLookMs = aNowMs;

    // Pinned, because our audio thread can still be calling it when the plugins are told to unload at the game's end.
    HMODULE module = nullptr;
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_PIN, L"Headset.dll", &module) || !module)
    {
        return; // not loaded yet, or not installed: voice just plays plain
    }
    const auto getApi = reinterpret_cast<Headset_GetApi_t>(GetProcAddress(module, "Headset_GetApi"));
    const HeadsetApi* const api = getApi ? getApi(HEADSET_API_VERSION) : nullptr;
    if (!api)
    {
        g_gaveUp.store(true);
        Logf(LogWarn, "headset: found the Headset mod, but it doesn't offer version %d of its interface", HEADSET_API_VERSION);
        return;
    }
    g_api.store(api);
    Logf(LogInfo, "headset: using the Headset mod");
}

bool HeadsetLinked()
{
    return g_api.load() != nullptr;
}

void ProcessVoicesThroughHeadset(float* aLeft, float* aRight, int aFrames)
{
    if (const HeadsetApi* const api = g_api.load(std::memory_order_relaxed))
    {
        api->ProcessNearbyVoices(aLeft, aRight, aFrames);
    }
}

void SetHeadsetApiForTest(const HeadsetApi* aApi)
{
    g_api.store(aApi);
    g_gaveUp.store(false);
}
} // namespace nv
