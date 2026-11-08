// SPDX-License-Identifier: MIT — Copyright (c) 2026 NightCoop (see sdk/LICENSE)
// NightCoop SDK example: a shared counter as a RED4ext plugin (C++).
//
// What it does
//   - Finds NightCoop.dll lazily (RED4ext "Running" state, once a second until found) and registers the mod
//     "example.counter.c" with hooks.
//   - The host keeps the counter in shared state under the key "count". Every 30 s the host adds 1 (the host is the only
//     one that counts here, to keep the example short) and sends a "ping" message (channel 1) to everyone.
//   - Every player (host and guests) sees stateChanged for "count": it is logged and shown on screen. The ping text is
//     shown on screen too.
//   - stateRequest (host side) shows how the host judges a guest's request: a guest may only add exactly 1.
//
// Build: see README.md. Needs nightcoop_sdk.h (../../include) and RED4ext.SDK (header only).

#include <RED4ext/RED4ext.hpp>

#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "nightcoop_sdk.h"

namespace
{
constexpr const char* kModId = "example.counter.c"; // ASCII [a-z0-9._-], 3..64 bytes, stable forever
constexpr const char* kStateKey = "count";
constexpr uint16_t kChannelPing = 1;
constexpr float kBumpPeriodS = 30.0f;

const NcSdkApi* g_api = nullptr; // set when NightCoop is found; cleared by hooks.shutdown
NcSdkMod g_mod = 0;
ULONGLONG g_lastLookupMs = 0;
float g_timerS = 0.0f;
RED4ext::v1::GameState g_runningState; // lives as long as the plugin

// --------------------------------------------------------------------------------------------------------- helpers

void Logf(int32_t aLevel, const char* aFormat, ...)
{
    if (!g_api || !g_mod)
    {
        return;
    }
    char buffer[256];
    va_list args;
    va_start(args, aFormat);
    vsnprintf(buffer, sizeof(buffer), aFormat, args);
    va_end(args);
    g_api->log(g_mod, aLevel, buffer);
}

void PeerName(NcSdkPeer aPeer, char* aOut, size_t aCap)
{
    aOut[0] = 0;
    if (aPeer != NCSDK_PEER_NONE)
    {
        g_api->peerName(aPeer, aOut, aCap);
    }
    if (aOut[0] == 0)
    {
        snprintf(aOut, aCap, "peer %u", static_cast<unsigned>(aPeer));
    }
}

// The counter as the shared state has it now (0 if the key is not set yet).
long long ReadCount()
{
    char buffer[32];
    const int32_t size = g_api->stateGet(g_mod, kStateKey, buffer, sizeof(buffer) - 1);
    if (size <= 0) // NCSDK_E_UNKNOWN: no such key yet
    {
        return 0;
    }
    buffer[size] = 0;
    return atoll(buffer);
}

// Host only: add 1, spread it, tell everyone.
void Bump()
{
    char text[32];
    const int length = snprintf(text, sizeof(text), "%lld", ReadCount() + 1);

    // The host stores the value, calls our stateChanged and sends it to every peer that has the mod.
    // (A guest would call exactly the same: its stateSet is a request to the host.)
    const int32_t result = g_api->stateSet(g_mod, kStateKey, text, static_cast<size_t>(length));
    if (result < 0)
    {
        Logf(NCSDK_LOG_WARN, "stateSet failed: %d", result);
        return;
    }

    // A message on our own channel to everyone who has the mod. Unreliable (flags 0): a missed ping does not matter.
    static const char kPing[] = "bumped the counter";
    g_api->send(g_mod, NCSDK_TO_ALL, kChannelPing, kPing, sizeof(kPing) - 1, 0);
}

// --------------------------------------------------------------------------------------------------------- hooks

void OnFrame(void*, float aDt)
{
    if (!g_api || !g_mod)
    {
        return;
    }
    g_timerS += aDt;
    if (g_timerS < kBumpPeriodS)
    {
        return;
    }
    g_timerS = 0.0f;

    NcSdkWhere where = {};
    where.size = sizeof(where);
    g_api->where(&where);
    if (where.inSession && where.isHost && where.inWorld) // only the host counts
    {
        Bump();
    }
}

// Hooks come from NightCoop's frame (never from inside registerMod); after hooks.shutdown g_api is NULL — check first.
void OnEvent(void*, int32_t aEvent, NcSdkPeer aPeer)
{
    if (!g_api || !g_mod)
    {
        return;
    }
    char name[64];
    switch (aEvent)
    {
    case NCSDK_EV_SESSION_START:
        Logf(NCSDK_LOG_INFO, "session started, we are peer %u", static_cast<unsigned>(aPeer));
        break;
    case NCSDK_EV_SESSION_END:
        Logf(NCSDK_LOG_INFO, "session ended");
        break;
    case NCSDK_EV_PEER_MOD:
        PeerName(aPeer, name, sizeof(name));
        Logf(NCSDK_LOG_INFO, "%s has the counter mod", name);
        break;
    case NCSDK_EV_PEER_NO_MOD:
        PeerName(aPeer, name, sizeof(name));
        Logf(NCSDK_LOG_INFO, "%s does not have the counter mod", name);
        break;
    default:
        break;
    }
}

void OnMessage(void*, NcSdkPeer aFrom, uint16_t aChannel, const uint8_t* aData, size_t aSize)
{
    if (!g_api || !g_mod || aChannel != kChannelPing)
    {
        return;
    }
    char name[64];
    PeerName(aFrom, name, sizeof(name));

    char text[160];
    snprintf(text, sizeof(text), "%s %.*s", name, static_cast<int>(aSize), reinterpret_cast<const char*>(aData));
    g_api->showMessage(g_mod, text, 3.0f, NCSDK_TONE_INFO);
}

void OnStateChanged(void*, const char* aKey, const uint8_t* aData, size_t aSize, NcSdkPeer aBy)
{
    if (!g_api || !g_mod || strcmp(aKey, kStateKey) != 0)
    {
        return;
    }
    char by[64];
    PeerName(aBy, by, sizeof(by));

    if (aSize == 0) // removed (also what a session end looks like)
    {
        Logf(NCSDK_LOG_INFO, "counter removed (by %s)", by);
        return;
    }
    char value[32];
    snprintf(value, sizeof(value), "%.*s", static_cast<int>(aSize), reinterpret_cast<const char*>(aData));
    Logf(NCSDK_LOG_INFO, "count = %s (set by %s)", value, by);

    char text[64];
    snprintf(text, sizeof(text), "Shared counter: %s", value);
    g_api->showMessage(g_mod, text, 2.0f, NCSDK_TONE_QUIET);
}

// Host only: a guest asks to set a key. Return 1 to accept, 0 to refuse.
int32_t OnStateRequest(void*, NcSdkPeer, const char* aKey, const uint8_t* aData, size_t aSize)
{
    if (!g_api || !g_mod || strcmp(aKey, kStateKey) != 0 || aSize == 0 || aSize > 18)
    {
        return 0; // only our key, and no removal
    }
    char value[32];
    snprintf(value, sizeof(value), "%.*s", static_cast<int>(aSize), reinterpret_cast<const char*>(aData));
    return atoll(value) == ReadCount() + 1 ? 1 : 0; // a guest may add exactly 1
}

void OnShutdown(void*)
{
    // NightCoop.dll is unloading: its table is about to disappear. Never call it again.
    g_api = nullptr;
    g_mod = 0;
}

// --------------------------------------------------------------------------------------------------------- connecting

void TryConnect()
{
    // Plugins load in an unknown order, so NightCoop may not be loaded when our Main runs. Look from the game thread,
    // at most once a second.
    const ULONGLONG now = GetTickCount64();
    if (now - g_lastLookupMs < 1000)
    {
        return;
    }
    g_lastLookupMs = now;

    const HMODULE nightCoop = GetModuleHandleW(L"NightCoop.dll");
    if (!nightCoop)
    {
        return; // not loaded (yet)
    }
    const auto get = reinterpret_cast<NcSdkGetFn>(GetProcAddress(nightCoop, NCSDK_EXPORT_NAME));
    if (!get)
    {
        return;
    }
    const NcSdkApi* api = get(NCSDK_VERSION);
    if (!api)
    {
        return; // no interface of this version, or the player switched the SDK off: behave as if NightCoop were absent
    }

    // Hooks we leave NULL are not an error: items of that kind wait in the mod's poll queue, which this mod never reads.
    static NcSdkHooks hooks = {};
    hooks.size = sizeof(hooks);
    hooks.frame = &OnFrame;
    hooks.event = &OnEvent;
    hooks.message = &OnMessage;
    hooks.stateChanged = &OnStateChanged;
    hooks.stateRequest = &OnStateRequest;
    hooks.shutdown = &OnShutdown;

    NcSdkModInfo info = {};
    info.size = sizeof(info);
    // Every player should have it, and the host decides the value: guests only ask.
    // What the mod uses — shared state and channels: an undeclared use answers NCSDK_E_DENIED.
    info.flags = NCSDK_MOD_NEEDED_BY_ALL | NCSDK_MOD_HOST_AUTHORITY | NCSDK_MOD_USES_SHARED_STATE | NCSDK_MOD_USES_CHANNELS;
    info.id = kModId;
    info.name = "Shared counter (C++ example)";
    info.version = "1.0.0";
    info.protocol = 1; // our own wire version: bump it when the meaning of "count" or the ping changes
    info.hooks = &hooks;

    g_api = api; // the first events (session, peers) come with NightCoop's next frame, not from inside registerMod
    const NcSdkMod mod = api->registerMod(&info);
    if (!mod)
    {
        g_api = nullptr; // refused (bad id, already registered, too many mods); NightCoop's log says why. Retry later.
        return;
    }
    g_mod = mod;
    Logf(NCSDK_LOG_INFO, "registered, NightCoop build %s", api->build ? api->build : "?");
}

bool OnRunningUpdate(RED4ext::CGameApplication*)
{
    if (!g_mod)
    {
        TryConnect();
    }
    return false; // the result does not matter in the Running state
}
} // namespace

// --------------------------------------------------------------------------------------------------------- RED4ext

RED4EXT_C_EXPORT bool RED4EXT_CALL Main(RED4ext::v1::PluginHandle aHandle, RED4ext::v1::EMainReason aReason,
                                        const RED4ext::v1::Sdk* aSdk)
{
    switch (aReason)
    {
    case RED4ext::v1::EMainReason::Load:
    {
        g_runningState.OnEnter = nullptr;
        g_runningState.OnUpdate = &OnRunningUpdate;
        g_runningState.OnExit = nullptr;
        aSdk->gameStates->Add(aHandle, RED4ext::EGameStateType::Running, &g_runningState);
        aSdk->logger->Info(aHandle, "NightCoop counter example loaded");
        break;
    }
    case RED4ext::v1::EMainReason::Unload:
    {
        if (g_api && g_mod)
        {
            g_api->unregisterMod(g_mod);
        }
        g_api = nullptr;
        g_mod = 0;
        break;
    }
    }
    return true;
}

RED4EXT_C_EXPORT void RED4EXT_CALL Query(RED4ext::v1::PluginInfo* aInfo)
{
    aInfo->name = L"NightCoop SDK example: counter";
    aInfo->author = L"NightCoop";
    aInfo->version = RED4EXT_V1_SEMVER(1, 0, 0);
    aInfo->runtime = RED4EXT_V1_RUNTIME_VERSION_INDEPENDENT; // we only use the RED4ext API, not the game's memory
    aInfo->sdk = RED4EXT_V1_SDK_VERSION_CURRENT;
}

RED4EXT_C_EXPORT uint32_t RED4EXT_CALL Supports()
{
    return RED4EXT_API_VERSION_1;
}
