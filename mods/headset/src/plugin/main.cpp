// RED4ext plugin: the settings, the headset key, the native class HeadsetNative that game/cet talks to, and what other mods can ask for.
// The sound itself is in src/wwise and src/headset.

#include <RED4ext/RED4ext.hpp>
#include <RED4ext/RTTITypes.hpp>
#include <RED4ext/Scripting/IScriptable.hpp>
#include <RED4ext/Scripting/Utils.hpp>

#include "build_time.h"
#include "core/common.hpp"
#include "core/settings.hpp"
#include "headset/control.hpp"
#include "headset/voices.hpp"
#include "headset_api.h"
#include "plugin/keys.hpp"
#include "wwise/install.hpp"

#include <atomic>
#include <cstdlib>
#include <filesystem>
#include <memory>
#include <string>

namespace
{
constexpr const char* kDefaultKey = "IK_Comma";

RED4ext::v1::PluginHandle g_handle = nullptr;
const RED4ext::v1::Sdk* g_sdk = nullptr;
hs::Settings g_settings;
std::unique_ptr<hs::KeyWatcher> g_keys;
std::atomic<int> g_cue{0}; // for the Lua side to play: 0 none, otherwise the mode just chosen plus one
std::atomic<int> g_wheelEvent{0}; // for the Lua side to act on: 1 open the wheel, 2 the key was let go

void LogSink(int aLevel, const char* aText)
{
    if (!g_sdk)
    {
        return;
    }
    if (aLevel >= hs::LogWarn)
    {
        g_sdk->logger->Warn(g_handle, aText);
    }
    else
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

// Outside the game folder, so sharing the mod's folder with friends doesn't hand them your settings.
std::filesystem::path DataFolder()
{
    wchar_t appData[MAX_PATH * 2] = {};
    const DWORD size = GetEnvironmentVariableW(L"LOCALAPPDATA", appData, static_cast<DWORD>(std::size(appData)));
    if (size > 0 && size < std::size(appData))
    {
        return std::filesystem::path(appData) / L"Headset";
    }
    return PluginFolder();
}

void ApplySettings()
{
    if (g_keys)
    {
        g_keys->SetKey(hs::VirtualKeyFromInputKey(g_settings.Get("key_headset", kDefaultKey)));
    }
}

const char* ModeName(hs::Mode aMode)
{
    return aMode == hs::Mode::HearingProtection ? "hearing protection" : aMode == hs::Mode::NoiseCancelling ? "noise cancelling" : "passthrough";
}

// A mode was chosen, by a tap, the wheel, or the Radioport (aWhy, for the log). Each plays its mode's cue.
void NoteChoice(const char* aWhy = "")
{
    const auto mode = static_cast<hs::Mode>(hs::g_control.mode.load());
    g_cue.store(static_cast<int>(mode) + 1);
    hs::Logf(hs::LogInfo, "headset: %s%s", ModeName(mode), aWhy);
}

void OnKeyTap()
{
    hs::CycleMode();
    NoteChoice();
}

void OnKeyHoldStart()
{
    g_wheelEvent.store(1);
}

void OnKeyHoldEnd()
{
    g_wheelEvent.store(2);
}

int ApiEffectiveMode()
{
    return static_cast<int>(hs::EffectiveMode());
}

const HeadsetApi g_api = {HEADSET_API_VERSION, &ApiEffectiveMode, &hs::ProcessNearbyVoices};
} // namespace

RED4EXT_C_EXPORT const HeadsetApi* Headset_GetApi(uint32_t aVersion)
{
    return aVersion == HEADSET_API_VERSION ? &g_api : nullptr;
}

struct HeadsetNative : RED4ext::IScriptable
{
    RED4ext::CClass* GetNativeType();
};

RED4ext::TTypedClass<HeadsetNative> g_class("HeadsetNative");

RED4ext::CClass* HeadsetNative::GetNativeType()
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
        *aOut = RED4ext::CString(HS_VERSION);
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
    ApplySettings();
}

void TakeWheelEvent(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, int32_t* aOut, int64_t)
{
    aFrame->code++;
    const int event = g_wheelEvent.exchange(0);
    if (aOut)
    {
        *aOut = event;
    }
}

void ChosenMode(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, int32_t* aOut, int64_t)
{
    aFrame->code++;
    if (aOut)
    {
        *aOut = hs::g_control.mode.load();
    }
}

void EffectiveMode(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, int32_t* aOut, int64_t)
{
    aFrame->code++;
    if (aOut)
    {
        *aOut = static_cast<int32_t>(hs::EffectiveMode());
    }
}

void ChooseMode(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, void*, int64_t)
{
    int32_t mode = 0;
    RED4ext::GetParameter(aFrame, &mode);
    aFrame->code++;
    if (mode >= 0 && mode <= static_cast<int>(hs::Mode::NoiseCancelling))
    {
        hs::ChooseMode(static_cast<hs::Mode>(mode));
        NoteChoice();
    }
}

void ChooseModeForRadioport(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, void*, int64_t)
{
    int32_t mode = 0;
    RED4ext::GetParameter(aFrame, &mode);
    aFrame->code++;
    if (mode >= 0 && mode <= static_cast<int>(hs::Mode::NoiseCancelling))
    {
        hs::ChooseMode(static_cast<hs::Mode>(mode));
        NoteChoice(", for the Radioport");
    }
}

void WheelFlipY(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, bool* aOut, int64_t)
{
    aFrame->code++;
    if (aOut)
    {
        *aOut = hs::g_control.wheelFlipY.load();
    }
}

void TakeCue(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, int32_t* aOut, int64_t)
{
    aFrame->code++;
    const int cue = g_cue.exchange(0);
    if (aOut)
    {
        *aOut = cue;
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
    RED4ext::CNamePool::Add("HeadsetNative");
    g_class.flags = {.isNative = true};
    RED4ext::CRTTISystem::Get()->RegisterType(&g_class);
}

void PostRegisterTypes()
{
    g_class.parent = RED4ext::CRTTISystem::Get()->GetClass("IScriptable");

    AddStatic("Version", Erase(&natives::Version), "String");
    AddStatic("GetSetting", Erase(&natives::GetSetting), "String", {{"String", "key"}, {"String", "fallback"}});
    AddStatic("SetSetting", Erase(&natives::SetSetting), nullptr, {{"String", "key"}, {"String", "value"}});
    AddStatic("TakeCue", Erase(&natives::TakeCue), "Int32");
    AddStatic("TakeWheelEvent", Erase(&natives::TakeWheelEvent), "Int32");
    AddStatic("ChosenMode", Erase(&natives::ChosenMode), "Int32");
    AddStatic("EffectiveMode", Erase(&natives::EffectiveMode), "Int32");
    AddStatic("ChooseMode", Erase(&natives::ChooseMode), nullptr, {{"Int32", "mode"}});
    AddStatic("ChooseModeForRadioport", Erase(&natives::ChooseModeForRadioport), nullptr, {{"Int32", "mode"}});    AddStatic("WheelFlipY", Erase(&natives::WheelFlipY), "Bool");
    AddStatic("SetOverlayOpen", Erase(&natives::SetOverlayOpen), nullptr, {{"Bool", "open"}});
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
        hs::SetLogSink(&LogSink);
        hs::ResetControl();

        auto* rtti = RED4ext::CRTTISystem::Get();
        rtti->AddRegisterCallback(RegisterTypes);
        rtti->AddPostRegisterCallback(PostRegisterTypes);

        // Our scripts compile only when this plugin really loads, so a missing DLL can't break anyone's scripts.
        const std::wstring scripts = (PluginFolder() / L"scripts").wstring();
        aSdk->scripts->Add(aHandle, scripts.c_str());

        const std::filesystem::path data = DataFolder();
        g_settings.Load(data / L"settings.ini");
        g_keys = std::make_unique<hs::KeyWatcher>(&OnKeyTap, &OnKeyHoldStart, &OnKeyHoldEnd);
        ApplySettings();
        hs::StartInstaller(data / L"tuning.ini");
        aSdk->logger->Info(aHandle, "Headset " HS_VERSION " loaded, built " HS_BUILT);
        break;
    }
    case RED4ext::v1::EMainReason::Unload:
    {
        hs::StopInstaller();
        g_keys.reset();
        hs::SetLogSink(nullptr);
        g_sdk = nullptr;
        break;
    }
    }
    return true;
}

RED4EXT_C_EXPORT void RED4EXT_CALL Query(RED4ext::v1::PluginInfo* aInfo)
{
    aInfo->name = L"Headset";
    aInfo->author = L"ihsan";
    aInfo->version = RED4EXT_V1_SEMVER(HS_VERSION_MAJOR, HS_VERSION_MINOR, HS_VERSION_PATCH);
    aInfo->runtime = RED4EXT_V1_RUNTIME_VERSION_INDEPENDENT;
    aInfo->sdk = RED4EXT_V1_SDK_VERSION_CURRENT;
}

RED4EXT_C_EXPORT uint32_t RED4EXT_CALL Supports()
{
    return RED4EXT_API_VERSION_1;
}
