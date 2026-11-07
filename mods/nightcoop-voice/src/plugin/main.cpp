// RED4ext plugin: connects the voice engine to NightCoop's session and exposes it to scripts as the native class
// NightCoopVoiceNative (static functions, callable from redscript and CET Lua). The HUD and positions are in
// game/scripts, the Settings section in game/cet.

#include <RED4ext/RED4ext.hpp>
#include <RED4ext/RTTITypes.hpp>
#include <RED4ext/Scripting/IScriptable.hpp>
#include <RED4ext/Scripting/Natives/Generated/Vector4.hpp>
#include <RED4ext/Scripting/Utils.hpp>

#include "audio/wasapi.hpp"
#include "engine.hpp"
#include "net/resend.hpp"
#include "nightcoop_sdk.h"
#include "plugin/keys.hpp"

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

namespace
{
constexpr const char* kModId = "xip.nightcoop_voice"; // stable forever
constexpr const char* kResendModId = "xip.nightcoop_voice.resend";
constexpr uint32_t kProtocol = 3;                     // raise it when packets or setup messages change meaning
constexpr uint16_t kChannelSignal = 1;                // link setup, reliable
constexpr uint16_t kChannelAudio = 2;                 // the Relay: voice and presence when there's no direct link, unreliable
static_assert(nv::kRelayMaxMessage <= NCSDK_UNRELIABLE_MAX);
constexpr const char* kStateKey = "k";
constexpr ULONGLONG kLookupEveryMs = 1000;
constexpr ULONGLONG kPeerCheckEveryMs = 2000;
constexpr size_t kMaxPeers = 32;
constexpr float kNoteSeconds = 4.f;
constexpr const char* kDefaultMuteKey = "IK_Mouse4";
constexpr const char* kDefaultRadioKey = "IK_Mouse5";

// MicState bits.
constexpr int kMicMuted = 1;
constexpr int kMicRadio = 2;
constexpr int kMicGateOpen = 4;
constexpr int kMicAudioRunning = 8;
constexpr int kMicInSession = 16;

// PeerStateAt bits.
constexpr int kPeerLinked = 1;
constexpr int kPeerFailed = 2;
constexpr int kPeerTalkNear = 4;
constexpr int kPeerTalkRadio = 8;
constexpr int kPeerMuted = 16;
constexpr int kPeerOnAir = 32;
constexpr int kPeerRelay = 64;

constexpr ULONGLONG kRelayRefusalLogEveryMs = 10000;

const RED4ext::v1::Sdk* g_sdk = nullptr;
RED4ext::v1::PluginHandle g_handle = nullptr;
RED4ext::v1::GameState g_runningState;

const NcSdkApi* g_api = nullptr; // cleared by hooks.shutdown
NcSdkMod g_mod = 0;
ULONGLONG g_lastLookupMs = 0;
ULONGLONG g_lastPeerCheckMs = 0;
nv::ResendSchedule g_resendSchedule;
bool g_resendWanted = false;
std::vector<NcSdkPeer> g_earlyLogged; // who we've already logged a setup message from before their mod list

nv::Settings g_settings;
std::unique_ptr<nv::Engine> g_engine;
std::unique_ptr<nv::KeyWatcher> g_keys;

// Read and written on the game thread only: scripts and hooks run there.
std::vector<nv::PeerView> g_peerSnapshot;
std::vector<nv::DeviceInfo> g_microphones;
std::vector<nv::DeviceInfo> g_outputs;

void LogSink(int aLevel, const char* aText)
{
    if (g_api && g_mod)
    {
        g_api->log(g_mod, aLevel, aText);
    }
    else if (g_sdk && aLevel >= nv::LogInfo)
    {
        g_sdk->logger->Info(g_handle, aText);
    }
}

std::filesystem::path PluginFolder()
{
    HMODULE self = nullptr;
    GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                       reinterpret_cast<LPCWSTR>(&PluginFolder), &self);
    wchar_t path[MAX_PATH * 2] = {};
    GetModuleFileNameW(self, path, static_cast<DWORD>(std::size(path)));
    return std::filesystem::path(path).parent_path();
}

// Outside the game folder, so sharing the mod's folder with friends doesn't hand them your devices and volumes.
std::filesystem::path SettingsPath()
{
    wchar_t appData[MAX_PATH * 2] = {};
    const DWORD size = GetEnvironmentVariableW(L"LOCALAPPDATA", appData, static_cast<DWORD>(std::size(appData)));
    if (size > 0 && size < std::size(appData))
    {
        return std::filesystem::path(appData) / L"NightCoopVoice" / L"settings.ini";
    }
    return PluginFolder() / L"settings.ini";
}

void ApplyKeys()
{
    if (g_keys)
    {
        g_keys->SetKeys(nv::VirtualKeyFromInputKey(g_settings.Get("key_mute", kDefaultMuteKey)),
                        nv::VirtualKeyFromInputKey(g_settings.Get("key_radio", kDefaultRadioKey)));
    }
}

// First asked for by the Settings section, so opening the audio system never slows the game's start.
bool g_devicesLoaded = false;

void LoadDevices()
{
    g_microphones = nv::ListDevices(true);
    g_outputs = nv::ListDevices(false);
    g_devicesLoaded = true;
}

void EnsureDevices()
{
    if (!g_devicesLoaded)
    {
        LoadDevices();
    }
}

// "IK_Mouse4" as a player would say it.
std::string KeyLabel(const std::string& aKey)
{
    return aKey.rfind("IK_", 0) == 0 ? aKey.substr(3) : aKey;
}

// ---------------------------------------------------------------------------------------------------- NightCoop hooks

void MakeKey()
{
    nv::VoiceKey key;
    if (!nv::RandomBytes(key.data(), key.size()))
    {
        nv::Logf(nv::LogError, "no random bytes for the voice key");
        return;
    }
    const int32_t result = g_api->stateSet(g_mod, kStateKey, key.data(), key.size());
    if (result < 0)
    {
        nv::Logf(nv::LogWarn, "could not share the voice key: %d", result);
    }
}

void AnnounceFirstRun()
{
    if (g_settings.GetBool("noticed", false))
    {
        return;
    }
    g_settings.Set("noticed", "1");
    const std::string text = "NightCoop Voice: your mic is live to co-op partners. Mute: " +
                             KeyLabel(g_settings.Get("key_mute", kDefaultMuteKey)) +
                             ", radio mic: " + KeyLabel(g_settings.Get("key_radio", kDefaultRadioKey)) +
                             ". To change them: Settings, Mods, Voice.";
    g_api->showMessage(g_mod, text.c_str(), 10.f, NCSDK_TONE_INFO);
}

std::string PeerNameOf(NcSdkPeer aPeer)
{
    char name[128] = {};
    g_api->peerName(aPeer, name, sizeof(name));
    return name[0] ? name : "partner";
}

// Catches what the events miss: a mod list that never registered, a missed event, and nicknames, which arrive after a
// player joins (until then NightCoop calls the host "Player 0").
void CheckPeers()
{
    const ULONGLONG now = GetTickCount64();
    if (now - g_lastPeerCheckMs < kPeerCheckEveryMs)
    {
        return;
    }
    g_lastPeerCheckMs = now;

    NcSdkWhere where{};
    where.size = sizeof(where);
    g_api->where(&where);
    if (!where.inSession)
    {
        g_resendSchedule.Update(static_cast<double>(now), false);
        return;
    }

    bool stuck = false;
    NcSdkPeer peers[kMaxPeers];
    const size_t count = std::min(g_api->peers(peers, kMaxPeers), kMaxPeers);
    for (size_t i = 0; i < count; ++i)
    {
        const std::string name = PeerNameOf(peers[i]);
        const int32_t hasMod = g_api->peerHasMod(g_mod, peers[i]);
        if (hasMod == 1)
        {
            g_engine->AddPeer(peers[i], name);
        }
        else if (hasMod == NCSDK_E_STATE)
        {
            stuck = true;
        }
        g_engine->SetPeerName(peers[i], name);
    }
    for (const nv::PeerView& peer : g_engine->Peers())
    {
        // A partner heard over the Relay has our mod list, so sending it again wouldn't help.
        stuck = stuck || (peer.link != nv::PeerLink::Linked && !peer.relay);
    }
    if (g_resendSchedule.Update(static_cast<double>(now), stuck))
    {
        g_resendWanted = true;
    }
}

// NightCoop sends our mod list to everyone when any mod registers or unregisters, so a throwaway mod makes it go again.
void ResendModList()
{
    NcSdkModInfo info = {};
    info.size = sizeof(info);
    info.flags = NCSDK_MOD_LOCAL_ONLY;
    info.id = kResendModId;
    info.name = "NightCoop Voice (sends the mod list again)";
    info.version = NCV_VERSION;
    info.protocol = 1;
    const NcSdkMod temporary = g_api->registerMod(&info);
    if (temporary)
    {
        g_api->unregisterMod(temporary);
    }
    nv::Logf(nv::LogInfo, "a player has no link yet: sent our mod list again (%d)", g_resendSchedule.Sent());
}

void OnFrame(void*, float)
{
    if (!g_api || !g_mod || !g_engine)
    {
        return;
    }
    CheckPeers();
    g_engine->DrainSignals([](nv::PeerId aPeer, const std::vector<uint8_t>& aMessage) {
        const int32_t result =
            g_api->send(g_mod, aPeer, kChannelSignal, aMessage.data(), aMessage.size(), NCSDK_SEND_RELIABLE);
        if (result == NCSDK_E_LIMIT)
        {
            return false; // try again next frame
        }
        if (result == NCSDK_E_STATE)
        {
            NcSdkWhere where{};
            where.size = sizeof(where);
            g_api->where(&where);
            return !where.inSession; // their mods check isn't over: wait, unless the session itself is gone
        }
        return true;
    });
    // Here, on the game thread, as the SDK requires: the mic's frames for the Relay were queued on the audio thread.
    g_engine->DrainRelay([](nv::PeerId aPeer, const uint8_t* aData, size_t aSize) {
        const int32_t result = g_api->send(g_mod, aPeer, kChannelAudio, aData, aSize, 0);
        if (result > 0)
        {
            return nv::RelaySend::Sent;
        }
        if (result == NCSDK_E_LIMIT)
        {
            return nv::RelaySend::Limit;
        }
        if (result == NCSDK_E_STATE)
        {
            return nv::RelaySend::NotNow;
        }
        // 0: they don't have the mod after all. The engine counts these; the code is only here.
        static ULONGLONG lastLoggedMs = 0;
        const ULONGLONG now = GetTickCount64();
        if (lastLoggedMs == 0 || now - lastLoggedMs >= kRelayRefusalLogEveryMs)
        {
            lastLoggedMs = now;
            nv::Logf(nv::LogInfo, "relay: NightCoop refused a message to peer %u: %d", aPeer, result);
        }
        return nv::RelaySend::Refused;
    });
    g_engine->DrainNotes([](const std::string& aNote) {
        g_api->showMessage(g_mod, aNote.c_str(), kNoteSeconds, NCSDK_TONE_QUIET);
    });
}

void OnEvent(void*, int32_t aEvent, NcSdkPeer aPeer)
{
    if (!g_api || !g_mod || !g_engine)
    {
        return;
    }
    switch (aEvent)
    {
    case NCSDK_EV_SESSION_START:
    {
        g_engine->SessionStart(aPeer);
        NcSdkWhere where{};
        where.size = sizeof(where);
        g_api->where(&where);
        if (where.isHost)
        {
            MakeKey();
        }
        AnnounceFirstRun();
        break;
    }
    case NCSDK_EV_SESSION_END:
        g_engine->SessionEnd();
        g_earlyLogged.clear();
        break;
    case NCSDK_EV_PEER_MOD:
        g_engine->AddPeer(aPeer, PeerNameOf(aPeer));
        break;
    case NCSDK_EV_PEER_LEAVE:
        g_engine->RemovePeer(aPeer);
        break;
    default:
        break;
    }
}

// On the game thread. A guest's message to another guest comes through the host, but aFrom is still the guest who sent
// it: guest-to-guest links (xip and Bleack) have always been set up this way. Every packet inside a Relay message also
// carries its sender, authenticated by the key, and must match aFrom.
void OnMessage(void*, NcSdkPeer aFrom, uint16_t aChannel, const uint8_t* aData, size_t aSize)
{
    if (!g_api || !g_mod || !g_engine)
    {
        return;
    }
    if (aChannel == kChannelAudio)
    {
        if (!g_engine->OnRelay(aFrom, aData, aSize))
        {
            g_engine->AddPeer(aFrom, PeerNameOf(aFrom)); // a Relay message proves they have the mod, too
        }
        return;
    }
    if (aChannel != kChannelSignal)
    {
        return;
    }
    // A setup message proves they have the mod, even if word of their mod list never came.
    if (g_api->peerHasMod(g_mod, aFrom) != 1 &&
        std::find(g_earlyLogged.begin(), g_earlyLogged.end(), aFrom) == g_earlyLogged.end())
    {
        g_earlyLogged.push_back(aFrom);
        nv::Logf(nv::LogInfo, "setup message from peer %u before its mod list", aFrom);
    }
    g_engine->AddPeer(aFrom, PeerNameOf(aFrom));
    g_engine->OnSignal(aFrom, aData, aSize);
}

void OnStateChanged(void*, const char* aKey, const uint8_t* aData, size_t aSize, NcSdkPeer)
{
    if (g_engine && std::strcmp(aKey, kStateKey) == 0)
    {
        g_engine->SetKey(aData, aSize);
    }
}

// Only the host's own copy sets the key, so a guest's request for it is refused.
int32_t OnStateRequest(void*, NcSdkPeer, const char*, const uint8_t*, size_t)
{
    return 0;
}

void OnMenuItem(void*, const char* aKey)
{
    if (!g_engine)
    {
        return;
    }
    if (std::strcmp(aKey, "mute") == 0)
    {
        g_engine->ToggleMute();
    }
    else if (std::strcmp(aKey, "radio") == 0)
    {
        g_engine->ToggleRadio();
    }
}

void OnShutdown(void*)
{
    // NightCoop.dll is unloading and its table goes with it.
    g_api = nullptr;
    g_mod = 0;
}

void TryConnect()
{
    const ULONGLONG now = GetTickCount64();
    if (now - g_lastLookupMs < kLookupEveryMs)
    {
        return;
    }
    g_lastLookupMs = now;

    const HMODULE nightCoop = GetModuleHandleW(L"NightCoop.dll");
    if (!nightCoop)
    {
        return;
    }
    const auto get = reinterpret_cast<NcSdkGetFn>(GetProcAddress(nightCoop, NCSDK_EXPORT_NAME));
    const NcSdkApi* api = get ? get(NCSDK_VERSION) : nullptr;
    if (!api)
    {
        return;
    }

    static NcSdkHooks hooks = {};
    hooks.size = sizeof(hooks);
    hooks.frame = &OnFrame;
    hooks.event = &OnEvent;
    hooks.message = &OnMessage;
    hooks.stateChanged = &OnStateChanged;
    hooks.stateRequest = &OnStateRequest;
    hooks.menuItem = &OnMenuItem;
    hooks.shutdown = &OnShutdown;

    NcSdkModInfo info = {};
    info.size = sizeof(info);
    info.flags = NCSDK_MOD_NEEDED_BY_ALL | NCSDK_MOD_USES_CHANNELS | NCSDK_MOD_USES_SHARED_STATE | NCSDK_MOD_USES_MENU;
    info.id = kModId;
    info.name = "NightCoop Voice";
    info.version = NCV_VERSION;
    info.protocol = kProtocol;
    info.hooks = &hooks;

    g_api = api; // the first events come with NightCoop's next frame, not from inside registerMod
    const NcSdkMod mod = api->registerMod(&info);
    if (!mod)
    {
        g_api = nullptr; // NightCoop's log says why; try again later
        return;
    }
    g_mod = mod;

    if (NCSDK_HAS(api, menuItemSet))
    {
        api->menuItemSet(mod, "mute", "Голос: микрофон вкл/выкл", "Voice: mute or unmute", NCSDK_MENU_IN_SESSION);
        api->menuItemSet(mod, "radio", "Голос: рация вкл/выкл", "Voice: radio mic on or off", NCSDK_MENU_IN_SESSION);
    }
    nv::Logf(nv::LogInfo, "NightCoop Voice %s connected to NightCoop %s", NCV_VERSION, api->build ? api->build : "?");
}

bool OnRunningUpdate(RED4ext::CGameApplication*)
{
    if (!g_mod)
    {
        TryConnect();
    }
    else if (g_resendWanted && g_api)
    {
        // Here and not in a NightCoop hook: this changes the list of mods NightCoop walks to call those hooks.
        g_resendWanted = false;
        ResendModList();
    }
    return false;
}

nv::Vec3 ToVec3(const RED4ext::Vector4& aVector)
{
    // Garbage from a script must not reach the audio maths as NaN.
    const auto safe = [](float aValue) { return std::isfinite(aValue) ? aValue : 0.f; };
    return {safe(aVector.X), safe(aVector.Y), safe(aVector.Z)};
}

const nv::DeviceInfo* DeviceAt(bool aCapture, int32_t aIndex)
{
    const auto& devices = aCapture ? g_microphones : g_outputs;
    return aIndex >= 0 && aIndex < static_cast<int32_t>(devices.size()) ? &devices[static_cast<size_t>(aIndex)] : nullptr;
}

const nv::PeerView* PeerAt(int32_t aIndex)
{
    return aIndex >= 0 && aIndex < static_cast<int32_t>(g_peerSnapshot.size())
               ? &g_peerSnapshot[static_cast<size_t>(aIndex)]
               : nullptr;
}
} // namespace

struct NightCoopVoiceNative : RED4ext::IScriptable
{
    RED4ext::CClass* GetNativeType();
};

RED4ext::TTypedClass<NightCoopVoiceNative> g_class("NightCoopVoiceNative");

RED4ext::CClass* NightCoopVoiceNative::GetNativeType()
{
    return &g_class;
}

namespace natives
{
void Version(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, RED4ext::CString* aOut, int64_t)
{
    aFrame->code++;
    if (aOut)
    {
        *aOut = RED4ext::CString(NCV_VERSION);
    }
}

void MicState(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, int32_t* aOut, int64_t)
{
    aFrame->code++;
    if (!aOut)
    {
        return;
    }
    int state = 0;
    if (g_engine)
    {
        state |= g_engine->Muted() ? kMicMuted : 0;
        state |= g_engine->RadioOn() ? kMicRadio : 0;
        state |= g_engine->GateOpen() ? kMicGateOpen : 0;
        state |= g_engine->AudioRunning() ? kMicAudioRunning : 0;
        state |= g_engine->InSession() ? kMicInSession : 0;
    }
    *aOut = state;
}

void MicLevel(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, float* aOut, int64_t)
{
    aFrame->code++;
    if (aOut)
    {
        *aOut = g_engine ? g_engine->MicLevel() : 0.f;
    }
}

// Takes a fresh picture of the players; the *At functions read from it.
void PeerCount(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, int32_t* aOut, int64_t)
{
    aFrame->code++;
    if (g_engine)
    {
        g_peerSnapshot = g_engine->Peers();
    }
    else
    {
        g_peerSnapshot.clear();
    }
    if (aOut)
    {
        *aOut = static_cast<int32_t>(g_peerSnapshot.size());
    }
}

void PeerIdAt(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, int32_t* aOut, int64_t)
{
    int32_t index = 0;
    RED4ext::GetParameter(aFrame, &index);
    aFrame->code++;
    if (aOut)
    {
        const nv::PeerView* peer = PeerAt(index);
        *aOut = peer ? static_cast<int32_t>(peer->id) : -1;
    }
}

void PeerNameAt(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, RED4ext::CString* aOut, int64_t)
{
    int32_t index = 0;
    RED4ext::GetParameter(aFrame, &index);
    aFrame->code++;
    if (aOut)
    {
        const nv::PeerView* peer = PeerAt(index);
        *aOut = RED4ext::CString(peer ? peer->name.c_str() : "");
    }
}

void PeerStateAt(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, int32_t* aOut, int64_t)
{
    int32_t index = 0;
    RED4ext::GetParameter(aFrame, &index);
    aFrame->code++;
    if (!aOut)
    {
        return;
    }
    int state = 0;
    if (const nv::PeerView* peer = PeerAt(index))
    {
        state |= peer->link == nv::PeerLink::Linked ? kPeerLinked : 0;
        state |= peer->link == nv::PeerLink::Failed ? kPeerFailed : 0;
        state |= peer->talkingNear ? kPeerTalkNear : 0;
        state |= peer->talkingRadio ? kPeerTalkRadio : 0;
        state |= peer->muted ? kPeerMuted : 0;
        state |= peer->onAir ? kPeerOnAir : 0;
        state |= peer->relay ? kPeerRelay : 0;
    }
    *aOut = state;
}

void PeerPingAt(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, int32_t* aOut, int64_t)
{
    int32_t index = 0;
    RED4ext::GetParameter(aFrame, &index);
    aFrame->code++;
    if (aOut)
    {
        const nv::PeerView* peer = PeerAt(index);
        *aOut = peer ? peer->pingMs : -1;
    }
}

void SetListener(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, void*, int64_t)
{
    RED4ext::Vector4 position{};
    RED4ext::Vector4 forward{};
    RED4ext::Vector4 right{};
    RED4ext::GetParameter(aFrame, &position);
    RED4ext::GetParameter(aFrame, &forward);
    RED4ext::GetParameter(aFrame, &right);
    aFrame->code++;
    if (g_engine)
    {
        g_engine->SetListener(ToVec3(position), ToVec3(forward), ToVec3(right));
    }
}

void SetPeerSpatial(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, void*, int64_t)
{
    int32_t peer = 0;
    RED4ext::Vector4 position{};
    RED4ext::Vector4 forward{};
    int32_t cabin = 0;
    RED4ext::GetParameter(aFrame, &peer);
    RED4ext::GetParameter(aFrame, &position);
    RED4ext::GetParameter(aFrame, &forward);
    RED4ext::GetParameter(aFrame, &cabin);
    aFrame->code++;
    if (g_engine)
    {
        g_engine->SetPeerSpatial(static_cast<nv::PeerId>(peer), ToVec3(position), ToVec3(forward), cabin);
    }
}

void SetListenerState(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, void*, int64_t)
{
    bool underwater = false;
    float worldSpeed = 1.f;
    bool inCar = false;
    RED4ext::GetParameter(aFrame, &underwater);
    RED4ext::GetParameter(aFrame, &worldSpeed);
    RED4ext::GetParameter(aFrame, &inCar);
    aFrame->code++;
    if (g_engine && std::isfinite(worldSpeed))
    {
        g_engine->SetListenerState(underwater, worldSpeed, inCar);
    }
}

void SetGameMaster(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, void*, int64_t)
{
    float percent = 100.f;
    RED4ext::GetParameter(aFrame, &percent);
    aFrame->code++;
    if (g_engine && std::isfinite(percent))
    {
        g_engine->SetGameMaster(percent);
    }
}

// What the sound rays and the rest of the voice's frame cost the game thread, and how much rays may spend in one frame. A
// ray's time runs from handing it to the script until the script reports back, so it covers the script as well as the cast.
// Everything here runs on the game thread. Logs every 30 seconds.
constexpr double kRayBudgetUsPerFrame = 300.0;
constexpr int kMaxRaysPerFrame = 12;
constexpr ULONGLONG kCostLogEveryMs = 30000;

struct FrameCost
{
    uint64_t rays = 0;
    double rayTotalUs = 0.0;
    double rayWorstUs = 0.0;
    double raysWorstFrameUs = 0.0;
    uint64_t frames = 0;
    double frameTotalUs = 0.0;
    double frameWorstUs = 0.0;
    ULONGLONG periodStartMs = 0;
};
FrameCost g_cost;
LARGE_INTEGER g_frameStart{};
LARGE_INTEGER g_rayStart{};
double g_raysThisFrameUs = 0.0;
int g_raysThisFrame = 0;
nv::RayRequest g_ray;

struct MaterialSeen
{
    std::string name;
    float thinWall = 0.f;
    float soft = 0.f;
    uint32_t hits = 0;
};
std::unordered_map<uint64_t, MaterialSeen> g_materials;

double MicrosecondsSince(const LARGE_INTEGER& aStart)
{
    static const LONGLONG frequency = [] {
        LARGE_INTEGER value;
        QueryPerformanceFrequency(&value);
        return value.QuadPart;
    }();
    LARGE_INTEGER now;
    QueryPerformanceCounter(&now);
    return static_cast<double>(now.QuadPart - aStart.QuadPart) * 1000000.0 / static_cast<double>(frequency);
}

void LogCosts(ULONGLONG aElapsedMs)
{
    const double seconds = static_cast<double>(aElapsedMs) / 1000.0;
    char line[260];
    std::snprintf(line, sizeof(line),
                  "rays: %.0f a second, mean %.1f us, worst %.0f us, busiest frame %.0f us, %.2f ms per second; the voice's whole frame: mean %.0f us, worst %.0f us",
                  static_cast<double>(g_cost.rays) / seconds,
                  g_cost.rays ? g_cost.rayTotalUs / static_cast<double>(g_cost.rays) : 0.0, g_cost.rayWorstUs,
                  g_cost.raysWorstFrameUs, g_cost.rayTotalUs / 1000.0 / seconds,
                  g_cost.frames ? g_cost.frameTotalUs / static_cast<double>(g_cost.frames) : 0.0, g_cost.frameWorstUs);
    LogSink(nv::LogInfo, line);

    std::string materials = "rays: materials hit";
    for (const auto& [hash, material] : g_materials)
    {
        materials += " " + material.name + "=" + std::to_string(material.hits);
    }
    LogSink(nv::LogInfo, materials.c_str());
    if (g_engine)
    {
        g_engine->LogAcoustics();
    }
}

void FrameBegin(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, void*, int64_t)
{
    aFrame->code++;
    QueryPerformanceCounter(&g_frameStart);
    g_raysThisFrameUs = 0.0;
    g_raysThisFrame = 0;
}

void FrameEnd(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, void*, int64_t)
{
    aFrame->code++;
    const double frameUs = MicrosecondsSince(g_frameStart);
    g_cost.frames++;
    g_cost.frameTotalUs += frameUs;
    g_cost.frameWorstUs = std::max(g_cost.frameWorstUs, frameUs);
    g_cost.raysWorstFrameUs = std::max(g_cost.raysWorstFrameUs, g_raysThisFrameUs);

    const ULONGLONG nowMs = GetTickCount64();
    if (g_cost.periodStartMs == 0)
    {
        g_cost.periodStartMs = nowMs;
    }
    const ULONGLONG elapsedMs = nowMs - g_cost.periodStartMs;
    if (elapsedMs >= kCostLogEveryMs)
    {
        if (g_cost.rays > 0)
        {
            LogCosts(elapsedMs);
        }
        g_cost = FrameCost{};
        g_cost.periodStartMs = nowMs;
    }
}

// Whether there's another ray to cast this frame. RayFrom, RayTo and RayGroups then describe it.
void NextRay(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, bool* aOut, int64_t)
{
    aFrame->code++;
    const bool another = g_engine && g_raysThisFrame < kMaxRaysPerFrame && g_raysThisFrameUs < kRayBudgetUsPerFrame &&
                         g_engine->NextSoundRay(g_ray);
    if (another)
    {
        // Counted here, so a script that forgot to report back couldn't loop forever.
        g_raysThisFrame++;
        QueryPerformanceCounter(&g_rayStart);
    }
    if (aOut)
    {
        *aOut = another;
    }
}

void RayFrom(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, RED4ext::Vector4* aOut, int64_t)
{
    aFrame->code++;
    if (aOut)
    {
        *aOut = RED4ext::Vector4{g_ray.from.x, g_ray.from.y, g_ray.from.z, 1.f};
    }
}

void RayTo(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, RED4ext::Vector4* aOut, int64_t)
{
    aFrame->code++;
    if (aOut)
    {
        *aOut = RED4ext::Vector4{g_ray.to.x, g_ray.to.y, g_ray.to.z, 1.f};
    }
}

void RayGroups(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, int32_t* aOut, int64_t)
{
    aFrame->code++;
    if (aOut)
    {
        *aOut = static_cast<int32_t>(g_ray.groups);
    }
}

// result: 0 clear, 1 a wall, 2 a closed door. Also counts which materials the walls are made of, for the log.
void ReportRay(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, void*, int64_t)
{
    int32_t result = 0;
    RED4ext::Vector4 position{};
    RED4ext::Vector4 normal{};
    RED4ext::CName material;
    RED4ext::GetParameter(aFrame, &result);
    RED4ext::GetParameter(aFrame, &position);
    RED4ext::GetParameter(aFrame, &normal);
    RED4ext::GetParameter(aFrame, &material);
    aFrame->code++;

    nv::RayAnswer answer;
    answer.result = static_cast<nv::RayResult>(std::clamp(result, 0, 2));
    answer.position = ToVec3(position);
    answer.normal = ToVec3(normal);
    if (answer.result == nv::RayResult::Wall)
    {
        auto found = g_materials.find(material.hash);
        if (found == g_materials.end())
        {
            MaterialSeen seen;
            const char* name = material.ToString();
            seen.name = name ? name : "unknown";
            seen.thinWall = nv::ThinWallOcclusion(name);
            seen.soft = nv::SoftSurfaceAbsorbs(name);
            found = g_materials.emplace(material.hash, std::move(seen)).first;
        }
        found->second.hits++;
        answer.thinWall = found->second.thinWall;
        answer.soft = found->second.soft;
    }
    if (g_engine)
    {
        g_engine->ReportSoundRay(answer);
    }

    const double us = MicrosecondsSince(g_rayStart);
    g_cost.rays++;
    g_cost.rayTotalUs += us;
    g_cost.rayWorstUs = std::max(g_cost.rayWorstUs, us);
    g_raysThisFrameUs += us;
}

void ToggleMute(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, void*, int64_t)
{
    aFrame->code++;
    if (g_engine)
    {
        g_engine->ToggleMute();
    }
}

void ToggleRadio(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, void*, int64_t)
{
    aFrame->code++;
    if (g_engine)
    {
        g_engine->ToggleRadio();
    }
}

void SetOverlayOpen(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, void*, int64_t)
{
    bool open = false;
    RED4ext::GetParameter(aFrame, &open);
    aFrame->code++;
    if (g_keys)
    {
        g_keys->SetBlocked(open);
    }
}

void SetTest(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, void*, int64_t)
{
    int32_t route = 0;
    RED4ext::GetParameter(aFrame, &route);
    aFrame->code++;
    if (g_engine && route >= 0 && route <= 2)
    {
        g_engine->SetTest(route);
    }
}

void GetSetting(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, RED4ext::CString* aOut, int64_t)
{
    RED4ext::CString key;
    RED4ext::CString fallback;
    RED4ext::GetParameter(aFrame, &key);
    RED4ext::GetParameter(aFrame, &fallback);
    aFrame->code++;
    if (aOut)
    {
        *aOut = RED4ext::CString(g_settings.Get(key.c_str(), fallback.c_str()).c_str());
    }
}

void SetSetting(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, void*, int64_t)
{
    RED4ext::CString key;
    RED4ext::CString value;
    RED4ext::GetParameter(aFrame, &key);
    RED4ext::GetParameter(aFrame, &value);
    aFrame->code++;
    g_settings.Set(key.c_str(), value.c_str());
    if (g_engine)
    {
        g_engine->ApplySettings();
    }
    ApplyKeys();
}

void RefreshDevices(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, void*, int64_t)
{
    aFrame->code++;
    LoadDevices();
}

void DeviceCount(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, int32_t* aOut, int64_t)
{
    bool capture = false;
    RED4ext::GetParameter(aFrame, &capture);
    aFrame->code++;
    EnsureDevices();
    if (aOut)
    {
        *aOut = static_cast<int32_t>((capture ? g_microphones : g_outputs).size());
    }
}

void DeviceName(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, RED4ext::CString* aOut, int64_t)
{
    bool capture = false;
    int32_t index = 0;
    RED4ext::GetParameter(aFrame, &capture);
    RED4ext::GetParameter(aFrame, &index);
    aFrame->code++;
    if (aOut)
    {
        const nv::DeviceInfo* device = DeviceAt(capture, index);
        *aOut = RED4ext::CString(device ? device->name.c_str() : "");
    }
}

void DeviceId(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, RED4ext::CString* aOut, int64_t)
{
    bool capture = false;
    int32_t index = 0;
    RED4ext::GetParameter(aFrame, &capture);
    RED4ext::GetParameter(aFrame, &index);
    aFrame->code++;
    if (aOut)
    {
        const nv::DeviceInfo* device = DeviceAt(capture, index);
        *aOut = RED4ext::CString(device ? device->id.c_str() : "");
    }
}
} // namespace natives

namespace
{
void AddStatic(const char* aName, RED4ext::ScriptingFunction_t<void*> aFunction, const char* aReturnType,
               std::initializer_list<std::pair<const char*, const char*>> aParameters = {})
{
    auto* function = RED4ext::CClassStaticFunction::Create(&g_class, aName, aName, aFunction);
    function->flags = {.isNative = true, .isStatic = true};
    if (aReturnType)
    {
        function->SetReturnType(aReturnType);
    }
    for (const auto& [type, name] : aParameters)
    {
        function->AddParam(type, name);
    }
    g_class.RegisterFunction(function);
}

template<typename T>
RED4ext::ScriptingFunction_t<void*> Erase(void (*aFunction)(RED4ext::IScriptable*, RED4ext::CStackFrame*, T*, int64_t))
{
    return reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(aFunction);
}

void RegisterTypes()
{
    RED4ext::CNamePool::Add("NightCoopVoiceNative");
    g_class.flags = {.isNative = true};
    RED4ext::CRTTISystem::Get()->RegisterType(&g_class);
}

void PostRegisterTypes()
{
    g_class.parent = RED4ext::CRTTISystem::Get()->GetClass("IScriptable");

    AddStatic("Version", Erase(&natives::Version), "String");
    AddStatic("MicState", Erase(&natives::MicState), "Int32");
    AddStatic("MicLevel", Erase(&natives::MicLevel), "Float");
    AddStatic("PeerCount", Erase(&natives::PeerCount), "Int32");
    AddStatic("PeerIdAt", Erase(&natives::PeerIdAt), "Int32", {{"Int32", "index"}});
    AddStatic("PeerNameAt", Erase(&natives::PeerNameAt), "String", {{"Int32", "index"}});
    AddStatic("PeerStateAt", Erase(&natives::PeerStateAt), "Int32", {{"Int32", "index"}});
    AddStatic("PeerPingAt", Erase(&natives::PeerPingAt), "Int32", {{"Int32", "index"}});
    AddStatic("SetListener", Erase(&natives::SetListener), nullptr,
              {{"Vector4", "position"}, {"Vector4", "forward"}, {"Vector4", "right"}});
    AddStatic("SetPeerSpatial", Erase(&natives::SetPeerSpatial), nullptr,
              {{"Int32", "peer"}, {"Vector4", "position"}, {"Vector4", "forward"}, {"Int32", "cabin"}});
    AddStatic("SetListenerState", Erase(&natives::SetListenerState), nullptr,
              {{"Bool", "underwater"}, {"Float", "worldSpeed"}, {"Bool", "inCar"}});
    AddStatic("SetGameMaster", Erase(&natives::SetGameMaster), nullptr, {{"Float", "percent"}});
    AddStatic("FrameBegin", Erase(&natives::FrameBegin), nullptr);
    AddStatic("FrameEnd", Erase(&natives::FrameEnd), nullptr);
    AddStatic("NextRay", Erase(&natives::NextRay), "Bool");
    AddStatic("RayFrom", Erase(&natives::RayFrom), "Vector4");
    AddStatic("RayTo", Erase(&natives::RayTo), "Vector4");
    AddStatic("RayGroups", Erase(&natives::RayGroups), "Int32");
    AddStatic("ReportRay", Erase(&natives::ReportRay), nullptr,
              {{"Int32", "result"}, {"Vector4", "position"}, {"Vector4", "normal"}, {"CName", "material"}});
    AddStatic("ToggleMute", Erase(&natives::ToggleMute), nullptr);
    AddStatic("ToggleRadio", Erase(&natives::ToggleRadio), nullptr);
    AddStatic("SetOverlayOpen", Erase(&natives::SetOverlayOpen), nullptr, {{"Bool", "open"}});
    AddStatic("SetTest", Erase(&natives::SetTest), nullptr, {{"Int32", "route"}});
    AddStatic("GetSetting", Erase(&natives::GetSetting), "String", {{"String", "key"}, {"String", "fallback"}});
    AddStatic("SetSetting", Erase(&natives::SetSetting), nullptr, {{"String", "key"}, {"String", "value"}});
    AddStatic("RefreshDevices", Erase(&natives::RefreshDevices), nullptr);
    AddStatic("DeviceCount", Erase(&natives::DeviceCount), "Int32", {{"Bool", "capture"}});
    AddStatic("DeviceName", Erase(&natives::DeviceName), "String", {{"Bool", "capture"}, {"Int32", "index"}});
    AddStatic("DeviceId", Erase(&natives::DeviceId), "String", {{"Bool", "capture"}, {"Int32", "index"}});
}
} // namespace

RED4EXT_C_EXPORT bool RED4EXT_CALL Main(RED4ext::v1::PluginHandle aHandle, RED4ext::v1::EMainReason aReason,
                                        const RED4ext::v1::Sdk* aSdk)
{
    switch (aReason)
    {
    case RED4ext::v1::EMainReason::Load:
    {
        g_handle = aHandle;
        g_sdk = aSdk;
        nv::SetLogSink(&LogSink);

        auto* rtti = RED4ext::CRTTISystem::Get();
        rtti->AddRegisterCallback(RegisterTypes);
        rtti->AddPostRegisterCallback(PostRegisterTypes);

        // Our scripts compile only when this plugin really loads, so a missing DLL can't break anyone's scripts.
        const std::wstring scripts = (PluginFolder() / L"scripts").wstring();
        aSdk->scripts->Add(aHandle, scripts.c_str());

        g_runningState.OnEnter = nullptr;
        g_runningState.OnUpdate = &OnRunningUpdate;
        g_runningState.OnExit = nullptr;
        aSdk->gameStates->Add(aHandle, RED4ext::EGameStateType::Running, &g_runningState);

        g_settings.Load(SettingsPath());
        g_engine = std::make_unique<nv::Engine>(g_settings);
        g_keys = std::make_unique<nv::KeyWatcher>(*g_engine);
        ApplyKeys();
        aSdk->logger->Info(aHandle, "NightCoop Voice " NCV_VERSION " loaded");
        break;
    }
    case RED4ext::v1::EMainReason::Unload:
    {
        g_keys.reset();
        if (g_api && g_mod)
        {
            g_api->unregisterMod(g_mod);
        }
        g_api = nullptr;
        g_mod = 0;
        g_engine.reset();
        nv::SetLogSink(nullptr);
        g_sdk = nullptr;
        break;
    }
    }
    return true;
}

RED4EXT_C_EXPORT void RED4EXT_CALL Query(RED4ext::v1::PluginInfo* aInfo)
{
    aInfo->name = L"NightCoopVoice";
    aInfo->author = L"ihsan";
    aInfo->version = RED4EXT_V1_SEMVER(NCV_VERSION_MAJOR, NCV_VERSION_MINOR, NCV_VERSION_PATCH);
    aInfo->runtime = RED4EXT_V1_RUNTIME_VERSION_INDEPENDENT;
    aInfo->sdk = RED4EXT_V1_SDK_VERSION_CURRENT;
}

RED4EXT_C_EXPORT uint32_t RED4EXT_CALL Supports()
{
    return RED4EXT_API_VERSION_1;
}
