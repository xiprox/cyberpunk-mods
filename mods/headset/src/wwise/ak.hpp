// Wwise as the game's exe has it: version 2023.1.19, build number 0x7E701. There's no SDK here. The order of the plug-in
// functions is in Audiokinetic's reference, and the slots, sizes and offsets were read from the game's own effects
// (RECORD.md). A bus effect's functions are called through these exact positions, so don't reorder anything.
#pragma once

#include <cstddef>
#include <cstdint>

namespace hs::ak
{
struct PluginInfo
{
    int32_t type;
    uint32_t buildVersion;
    bool inPlace;
    bool canChangeRate;
    bool reserved;
    bool canProcessObjects;
    bool isDeviceEffect;
    bool canRunOnObjectConfig;
    bool usesGainAttribute;
};
static_assert(offsetof(PluginInfo, buildVersion) == 4);
static_assert(offsetof(PluginInfo, inPlace) == 8);
static_assert(offsetof(PluginInfo, canProcessObjects) == 0xB);
static_assert(offsetof(PluginInfo, canRunOnObjectConfig) == 0xD);
static_assert(offsetof(PluginInfo, usesGainAttribute) == 0xE);

// Only the two fields the game's effects read; Wwise owns the rest.
struct AudioFormat
{
    uint32_t sampleRate;
    uint32_t channelConfig;
};

// Channels lie one after the other in data, each maxFrames long. The channel count is channelConfig's low 8 bits.
struct AudioBuffer
{
    void* data;
    uint32_t channelConfig;
    int32_t state;
    uint16_t maxFrames;
    uint16_t validFrames;
};
static_assert(offsetof(AudioBuffer, channelConfig) == 8);
static_assert(offsetof(AudioBuffer, state) == 12);
static_assert(offsetof(AudioBuffer, maxFrames) == 16);
static_assert(offsetof(AudioBuffer, validFrames) == 18);

constexpr int kSuccess = 1;
constexpr int kDataReady = 45;
constexpr int32_t kPluginTypeEffect = 3;
constexpr uint32_t kBuildVersion = 0x7E701; // AK_WWISESDK_VERSION_COMBINED, written by every effect in the exe
// 2.5's exe has nine effects stamped with it and one still stamped 0x7E501, so a stray can outlive a Wwise update: hence a majority.
constexpr int kMinBuildStamps = 5;

using CreateFn = void* (*)(void*);
using IsInitializedFn = bool (*)();
using RegisterPluginFn = int (*)(int32_t, uint32_t, uint32_t, CreateFn, CreateFn, void*);
using LoadBankFn = int (*)(const void*, uint32_t, uint32_t&);
using SetBusEffectFn = int (*)(uint32_t, uint32_t, uint32_t);

constexpr char kIsInitializedName[] = "?IsInitialized@SoundEngine@AK@@YA_NXZ";
constexpr char kRegisterPluginName[] =
    "?RegisterPlugin@SoundEngine@AK@@YA?AW4AKRESULT@@W4AkPluginType@@IIP6APEAVIAkPlugin@2@PEAVIAkPluginMemAlloc@2@@ZP6APEAVIAkPluginParam@2@1@ZP6A?AW43@AEAIPEAUAkDeviceDescription@@@Z@Z";
constexpr char kLoadBankName[] = "?LoadBankMemoryCopy@SoundEngine@AK@@YA?AW4AKRESULT@@PEBXIAEAI@Z";
constexpr char kSetBusEffectName[] = "?SetBusEffect@SoundEngine@AK@@YA?AW4AKRESULT@@III@Z";

// Wwise's IDs: the FNV-1 hash of a lowercased name.
constexpr uint32_t Id(const char* aName)
{
    uint32_t hash = 2166136261u;
    for (; *aName; ++aName)
    {
        const char c = (*aName >= 'A' && *aName <= 'Z') ? static_cast<char>(*aName + 32) : *aName;
        hash = hash * 16777619u;
        hash ^= static_cast<uint8_t>(c);
    }
    return hash;
}
} // namespace hs::ak
