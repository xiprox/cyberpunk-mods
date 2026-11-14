#include "wwise/install.hpp"

#include "core/common.hpp"
#include "headset/control.hpp"
#include "wwise/ak.hpp"
#include "wwise/effect.hpp"
#include "wwise/places.hpp"

#include <windows.h>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <string>
#include <thread>

namespace hs
{
namespace
{
constexpr double kWaitAfterWwiseMs = 10000.0; // the game loads the bank that defines the buses after starting Wwise
constexpr double kLogEveryMs = 10000.0;
constexpr double kTuningEveryMs = 1000.0;

std::atomic<bool> g_stop{false};
std::atomic<bool> g_started{false};
std::atomic<int> g_state{static_cast<int>(InstallState::Off)};
std::thread g_thread;
int64_t g_tuningStamp = 0;

float ToDb(float aLinear)
{
    return 20.f * std::log10(aLinear > 1e-7f ? aLinear : 1e-7f);
}

// The plugin thread: everything that isn't the audio itself.
bool Install(ak::RegisterPluginFn aRegister, ak::LoadBankFn aLoadBank, ak::SetBusEffectFn aSetBusEffect)
{
    // Wwise keeps calling this code until the game closes, later than our plugin is told to unload.
    HMODULE self = nullptr;
    GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN, reinterpret_cast<LPCWSTR>(&Install), &self);

    const auto create = [](void*) -> void* { return NewEffect(); };
    const auto createParams = [](void*) -> void* { return NewParams(); };
    int result = aRegister(ak::kPluginTypeEffect, kCompany, kPlugin, create, createParams, nullptr);
    if (result != ak::kSuccess)
    {
        Logf(LogWarn, "RegisterPlugin answered %d", result);
        return false;
    }
    const std::vector<uint8_t> bank = MakeBank();
    uint32_t bankId = 0;
    result = aLoadBank(bank.data(), static_cast<uint32_t>(bank.size()), bankId);
    if (result != ak::kSuccess)
    {
        Logf(LogWarn, "LoadBankMemoryCopy answered %d", result);
        return false;
    }

    int placed = 0;
    int wanted = 0;
    for (int i = 0; i < kDetectorCount; ++i)
    {
        ++wanted;
        const int answer = aSetBusEffect(kDetectors[i].bus, kDetectors[i].slot, kDetectorShareSetBase + static_cast<uint32_t>(i));
        placed += answer == ak::kSuccess ? 1 : 0;
        if (answer != ak::kSuccess)
        {
            Logf(LogWarn, "SetBusEffect answered %d for the detector on %s", answer, kDetectors[i].name);
        }
    }
    for (int i = 0; i < kClampCount; ++i)
    {
        ++wanted;
        const int answer = aSetBusEffect(kClamps[i].bus, kClamps[i].slot, kClampShareSetBase + static_cast<uint32_t>(kClamps[i].kind));
        placed += answer == ak::kSuccess ? 1 : 0;
        if (answer != ak::kSuccess)
        {
            Logf(LogWarn, "SetBusEffect answered %d for the clamp on %s", answer, kClamps[i].name);
        }
    }
    Logf(LogInfo, "effect on %d of %d places (bank %08x)", placed, wanted, bankId);
    return placed > 0;
}

void LogStats()
{
    char text[900];
    int used = 0;
    for (int i = 0; i < kDetectorCount; ++i)
    {
        const uint32_t runs = g_control.detectorRuns[i].exchange(0);
        const float reading = ToDb(g_control.loudestReading[i].exchange(0.f));
        if (runs == 0 || reading < -60.f)
        {
            continue;
        }
        const float offset = g_control.offsetDb[i].load();
        const int wrote = std::snprintf(text + used, sizeof(text) - used, "%s%s %+.1f dB = %.0f real", used ? ", " : "", kDetectors[i].name, reading, reading + offset);
        if (wrote > 0)
        {
            used = std::min<int>(used + wrote, sizeof(text) - 1);
        }
    }
    const float lowestDb = ToDb(g_control.lowestGain.exchange(1.f));
    if (used == 0 && lowestDb > -0.05f)
    {
        return;
    }
    Logf(LogInfo, "mode %d, deepest %.1f dB, %d detectors and %d clamps alive; loudest: %s%s", static_cast<int>(EffectiveMode()), lowestDb,
         g_control.detectorsAlive.load(), g_control.clampsAlive.load(), used ? text : "(nothing)",
         AudioBroken() ? "; STOPPED: reading an audio buffer failed" : "");
}

// Every number tuning.ini can move, in the order the file lists them.
struct FloatKey
{
    const char* key;
    std::atomic<float>* store;
    float start;
    float low;
    float high;
    const char* comment;
};
const FloatKey kFloatKeys[] = {
    {"threshold_db", &g_control.thresholdDb, kStartThresholdDb, 40.f, 200.f, "the real-world loudness where the clamp starts: up (95, 105) and only louder bangs set it off"},
    {"depth_per_db", &g_control.depthPerDb, kStartDepthPerDb, 0.05f, 4.f, "how many dB the microphones come down for each dB over: lower is gentler"},
    {"deepest_db", &g_control.deepestDb, kStartDeepestDb, 3.f, 60.f, "how far down the microphones can go at most"},
    {"leak_db", &g_control.leakDb, kStartLeakDb, -60.f, 6.f, "how much gets through the cups, muffled, and is never turned down"},
    {"recoil_db", &g_control.recoilDb, kStartRecoilDb, 0.f, 24.f, "raises the lows of your own gunshots, felt more than heard: 0 is off"},
    {"thump_db", &g_control.thumpDb, kStartThumpDb, 0.f, 24.f, "raises the lows of other people's gunshots and of explosions: 0 is off"},
    {"lift_under_db", &g_control.liftUnderDb, kStartLiftUnderDb, -80.f, 0.f, "sounds quieter than this are lifted a little, as talk-through does"},
    {"hiss_db", &g_control.hissDb, kStartHissDb, -120.f, -20.f, "the electronics' faint hiss: lower is quieter"},
    {"width", &g_control.width, kStartWidth, 0.f, 1.f, "how wide the world sounds: 1 is as it was"},
    {"body_db", &g_control.bodyDb, kStartBodyDb, -24.f, 12.f, "how warm V's voice is through the skull"},
    {"air_floor_db", &g_control.airFloorDb, kStartAirFloorDb, -60.f, 0.f, "how much of V's voice always comes through the air: lower is more inside your head"},
    {"air_open_db", &g_control.airOpenDb, kStartAirOpenDb, -60.f, 0.f, "V's lines through the microphones when nothing's clamping them"},
    {"grunt_body_db", &g_control.gruntBodyDb, kStartGruntBodyDb, -24.f, 12.f, "the same warmth for V's grunts and breathing"},
    {"grunt_floor_db", &g_control.gruntFloorDb, kStartGruntFloorDb, -60.f, 0.f, "how much of V's grunts and breathing always comes through the air"},
    {"grunt_open_db", &g_control.gruntOpenDb, kStartGruntOpenDb, -60.f, 0.f, "V's grunts and breathing through the microphones when nothing's clamping them"},
    {"mask_db", &g_control.maskDb, kStartMaskDb, -60.f, 0.f, "how far a bang drowns out V's voice and breathing, at the loudest bang: 0 is not at all"},
    {"grunt_clamp_mask_db", &g_control.gruntClampMaskDb, kStartGruntClampMaskDb, -60.f, 0.f, "how far a bang drowns out V's grunts and breathing in dynamic clamping: 0 keeps them"},
    {"grunt_body_hz", &g_control.gruntBodyHz, kStartGruntBodyHz, 100.f, 2000.f, "below this V's grunts and breathing come through the skull: lower is further inside your head"},
    {"footstep_db", &g_control.footstepDb, kStartFootstepDb, -24.f, 18.f, "how much your own steps thud through your body"},
    {"noise_low_db", &g_control.noiseLowDb, kStartNoiseLowDb, -60.f, 0.f, "noise cancelling: the lows"},
    {"noise_mid_db", &g_control.noiseMidDb, kStartNoiseMidDb, -60.f, 0.f, "noise cancelling: the middle"},
    {"noise_high_db", &g_control.noiseHighDb, kStartNoiseHighDb, -60.f, 0.f, "noise cancelling: the highs"},
    {"noise_bang_low_db", &g_control.noiseBangLowDb, kStartNoiseBangLowDb, -60.f, 0.f, "noise cancelling during a bang, which it can't keep up with: the lows"},
    {"noise_bang_mid_db", &g_control.noiseBangMidDb, kStartNoiseBangMidDb, -60.f, 0.f, "noise cancelling during a bang: the middle"},
    {"noise_bang_high_db", &g_control.noiseBangHighDb, kStartNoiseBangHighDb, -60.f, 0.f, "noise cancelling during a bang: the highs"},
};

// The first line of a file this version wrote.
constexpr const char* kTemplateMark = "# Headset tuning, format 2.";
} // namespace

// The file is made here, by the game, so it's where the game can see it and every setting comes with its explanation. Every value starts
// commented out: a file written once with that day's starting values would otherwise hold a player there after they move on, as it held
// two players' recoil at 6 dB after the start went to 12 (2026-11-10). A file without the mark is one of those, and is moved aside.
void PrepareTuningFile(const std::filesystem::path& aFile)
{
    std::error_code error;
    if (std::filesystem::exists(aFile, error))
    {
        std::string first;
        {
            std::ifstream existing(aFile);
            std::getline(existing, first);
        }
        if (first.rfind(kTemplateMark, 0) == 0)
        {
            return;
        }
        std::filesystem::path old = aFile;
        old.replace_extension(L".old.ini");
        std::filesystem::rename(aFile, old, error);
        if (error)
        {
            Logf(LogWarn, "tuning: couldn't move the old tuning file aside, so its values still apply: %s", error.message().c_str());
            return;
        }
        Logf(LogInfo, "tuning: moved an old tuning file aside as %ls, so the mod's own starting values apply", old.filename().c_str());
    }
    std::filesystem::create_directories(aFile.parent_path(), error);
    std::ofstream file(aFile);
    file << kTemplateMark << " Read again within a second of saving. Every value below starts with # and changes nothing:\n"
         << "# take the # off a setting's line to use it, and put it back to return to where the mod starts.\n";
    for (const FloatKey& key : kFloatKeys)
    {
        file << "# " << key.key << " is " << key.comment << "\n# " << key.key << "=" << key.start << "\n";
    }
    file << "# sound=0 leaves only the clamp, to compare\n"
         << "# sound=1\n"
         << "# wheel_flip_y=1 swaps up and down on the mode wheel, if they turn out reversed\n"
         << "# wheel_flip_y=0\n"
         << "# always_worn=1 keeps it on without the key\n"
         << "# always_worn=0\n\n"
         << "# What each bus's level adds up to in real-world dB: lower one to make that kind of sound clamp less\n";
    for (const DetectorPlace& place : kDetectors)
    {
        file << "# offset_" << place.name << "=" << place.offsetDb << "\n";
    }
}

namespace
{

int CountGameBuildStamps(HMODULE aGame)
{
    const auto* const base = reinterpret_cast<const uint8_t*>(aGame);
    const auto* const nt = reinterpret_cast<const IMAGE_NT_HEADERS*>(base + reinterpret_cast<const IMAGE_DOS_HEADER*>(base)->e_lfanew);
    const IMAGE_SECTION_HEADER* section = IMAGE_FIRST_SECTION(nt);
    for (WORD i = 0; i < nt->FileHeader.NumberOfSections; ++i, ++section)
    {
        if (std::memcmp(section->Name, ".text", 6) == 0)
        {
            return CountBuildStamps(base + section->VirtualAddress, section->Misc.VirtualSize, ak::kBuildVersion);
        }
    }
    return 0;
}

void InstallerLoop(std::filesystem::path aTuningFile)
{
    PrepareTuningFile(aTuningFile);
    const HMODULE game = GetModuleHandleW(nullptr);
    const auto isInitialized = reinterpret_cast<ak::IsInitializedFn>(GetProcAddress(game, ak::kIsInitializedName));
    const auto registerPlugin = reinterpret_cast<ak::RegisterPluginFn>(GetProcAddress(game, ak::kRegisterPluginName));
    const auto loadBank = reinterpret_cast<ak::LoadBankFn>(GetProcAddress(game, ak::kLoadBankName));
    const auto setBusEffect = reinterpret_cast<ak::SetBusEffectFn>(GetProcAddress(game, ak::kSetBusEffectName));
    const bool exported = isInitialized && registerPlugin && loadBank && setBusEffect;
    const int stamps = CountGameBuildStamps(game);
    // The effect is called through positions read from this build, so another build is never tried.
    const bool sameWwise = stamps >= ak::kMinBuildStamps;
    const bool available = exported && sameWwise;
    if (!exported)
    {
        g_state.store(static_cast<int>(InstallState::NotAvailable));
        Logf(LogWarn, "this program doesn't export Wwise's functions, so there's no headset");
    }
    else if (!sameWwise)
    {
        g_state.store(static_cast<int>(InstallState::NotAvailable));
        Logf(LogWarn, "the headset is off: only %d of the game's effects are Wwise build %x, the one this version was made for. A game patch has probably changed Wwise, so the mod needs updating", stamps, ak::kBuildVersion);
    }
    else
    {
        Logf(LogInfo, "Wwise build %x, on %d of the game's effects", ak::kBuildVersion, stamps);
    }

    double upSinceMs = -1.0;
    double lastLogMs = 0.0;
    double lastTuningMs = 0.0;
    bool installed = false;
    bool failed = false;
    while (!g_stop.load())
    {
        const double now = NowMs();
        if (now - lastTuningMs >= kTuningEveryMs)
        {
            lastTuningMs = now;
            ReadTuning(aTuningFile);
        }
        // Always, even in Passthrough, where the effect does nothing: so that the first tap acts at once.
        if (available && !installed && !failed && isInitialized())
        {
            upSinceMs = upSinceMs < 0.0 ? now : upSinceMs;
            if (now - upSinceMs >= kWaitAfterWwiseMs)
            {
                installed = Install(registerPlugin, loadBank, setBusEffect);
                failed = !installed;
                g_state.store(static_cast<int>(installed ? InstallState::Installed : InstallState::Failed));
                lastLogMs = now;
            }
        }
        if (installed && now - lastLogMs >= kLogEveryMs)
        {
            lastLogMs = now;
            LogStats();
        }
        Sleep(50);
    }
}
} // namespace

void StartInstaller(const std::filesystem::path& aTuningFile)
{
    if (!g_started.exchange(true))
    {
        g_stop.store(false);
        g_state.store(static_cast<int>(InstallState::Waiting));
        g_thread = std::thread(InstallerLoop, aTuningFile);
    }
}

void StopInstaller()
{
    g_stop.store(true);
    if (g_thread.joinable())
    {
        g_thread.join();
    }
    g_started.store(false);
    g_state.store(static_cast<int>(InstallState::Off));
}

int CountBuildStamps(const uint8_t* aCode, size_t aSize, uint32_t aBuild)
{
    const uint8_t stamp[] = {0xC7, 0x42, 0x04, static_cast<uint8_t>(aBuild), static_cast<uint8_t>(aBuild >> 8), static_cast<uint8_t>(aBuild >> 16), static_cast<uint8_t>(aBuild >> 24)};
    const uint8_t* const end = aCode + aSize;
    int found = 0;
    for (const uint8_t* at = std::search(aCode, end, std::begin(stamp), std::end(stamp)); at != end; at = std::search(at + sizeof(stamp), end, std::begin(stamp), std::end(stamp)))
    {
        ++found;
    }
    return found;
}

InstallState GetInstallState()
{
    return static_cast<InstallState>(g_state.load());
}

// Temporary, like the same file in NightCoop Voice: lines like threshold_db=85, picked up within a second of saving.
bool ReadTuning(const std::filesystem::path& aFile)
{
    std::error_code error;
    const auto written = std::filesystem::last_write_time(aFile, error);
    // Says once what it finds, since a missing file otherwise looks just like nothing having changed.
    static int lastResult = -1;
    if (error.value() != lastResult)
    {
        lastResult = error.value();
        Logf(LogInfo, "tuning file %ls: %s", aFile.c_str(), error ? error.message().c_str() : "found");
    }
    const int64_t stamp = error ? 0 : static_cast<int64_t>(written.time_since_epoch().count());
    if (stamp == g_tuningStamp)
    {
        return false;
    }
    g_tuningStamp = stamp;

    float numbers[std::size(kFloatKeys)];
    for (size_t i = 0; i < std::size(kFloatKeys); ++i)
    {
        numbers[i] = kFloatKeys[i].start;
    }
    bool sound = true;
    bool flipY = false;
    bool alwaysWorn = false;
    float offsets[kDetectorCount];
    for (int i = 0; i < kDetectorCount; ++i)
    {
        offsets[i] = kDetectors[i].offsetDb;
    }

    std::ifstream file(aFile);
    std::string line;
    while (std::getline(file, line))
    {
        const size_t equals = line.find('=');
        if (equals == std::string::npos || line[0] == '#')
        {
            continue;
        }
        const std::string key = line.substr(0, equals);
        const float value = static_cast<float>(std::atof(line.c_str() + equals + 1));
        if (!std::isfinite(value))
        {
            continue;
        }
        for (size_t i = 0; i < std::size(kFloatKeys); ++i)
        {
            if (key == kFloatKeys[i].key)
            {
                numbers[i] = std::clamp(value, kFloatKeys[i].low, kFloatKeys[i].high);
            }
        }
        if (key == "sound")
        {
            sound = value != 0.f;
        }
        else if (key == "wheel_flip_y")
        {
            flipY = value != 0.f;
        }
        else if (key == "always_worn")
        {
            alwaysWorn = value != 0.f;
        }
        else if (key.rfind("offset_", 0) == 0)
        {
            const std::string name = key.substr(7);
            for (int i = 0; i < kDetectorCount; ++i)
            {
                if (name == kDetectors[i].name)
                {
                    offsets[i] = std::clamp(value, 0.f, 220.f);
                }
            }
        }
    }
    for (size_t i = 0; i < std::size(kFloatKeys); ++i)
    {
        kFloatKeys[i].store->store(numbers[i]);
    }
    g_control.soundOn.store(sound);
    g_control.wheelFlipY.store(flipY);
    for (int i = 0; i < kDetectorCount; ++i)
    {
        g_control.offsetDb[i].store(offsets[i]);
    }
    g_control.wornByTuning.store(alwaysWorn);
    Logf(LogInfo, "tuning: clamp from %.0f dB real, %.2f dB off per dB over, %.0f dB at most; sound %s, leak %.0f dB, recoil %.0f dB, thump %.0f dB%s", g_control.thresholdDb.load(), g_control.depthPerDb.load(),
         g_control.deepestDb.load(), sound ? "on" : "off", g_control.leakDb.load(), g_control.recoilDb.load(), g_control.thumpDb.load(), alwaysWorn ? ", always worn" : "");
    return true;
}
} // namespace hs
