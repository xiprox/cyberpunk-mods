// Checks the headset without the game: the bank, the effect called the way Wwise calls it, and the clamp's behaviour. Whether
// it sounds right only the user's ears can say.

#include "core/common.hpp"
#include "headset/clamp.hpp"
#include "headset/control.hpp"
#include "headset/voices.hpp"
#include "wwise/ak.hpp"
#include "wwise/effect.hpp"
#include "wwise/install.hpp"
#include "wwise/places.hpp"

#include <windows.h>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <set>
#include <string>
#include <vector>

using namespace hs;

namespace
{
int g_failures = 0;

void Check(bool aOk, const char* aWhat)
{
    std::printf("  %s  %s\n", aOk ? "ok  " : "FAIL", aWhat);
    g_failures += aOk ? 0 : 1;
}

bool Near(float aValue, float aExpected, float aWithin)
{
    return std::fabs(aValue - aExpected) <= aWithin;
}

// As in the game's exe, written out here on purpose, apart from the code they check.
struct Buffer
{
    void* data;
    uint32_t config;
    int32_t state;
    uint16_t maxFrames;
    uint16_t validFrames;
};
struct Format
{
    uint32_t rate;
    uint32_t config;
};

constexpr uint16_t kFrames = 512;
constexpr uint32_t kStereo = 2 | (1 << 8);

void** Slots(void* aObject)
{
    return *static_cast<void***>(aObject);
}

void* MakeEffect(Role aRole, uint32_t aIndex)
{
    void* const params = NewParams();
    const uint32_t block[2] = {static_cast<uint32_t>(aRole), aIndex};
    reinterpret_cast<int (*)(void*, void*, const void*, uint32_t)>(Slots(params)[3])(params, nullptr, block, sizeof(block));
    void* const effect = NewEffect();
    Format format{48000, kStereo};
    reinterpret_cast<int (*)(void*, void*, void*, void*, Format*)>(Slots(effect)[6])(effect, nullptr, nullptr, params, &format);
    reinterpret_cast<int (*)(void*, void*)>(Slots(params)[4])(params, nullptr);
    return effect;
}

void Run(void* aEffect, Buffer* aBuffer)
{
    reinterpret_cast<void (*)(void*, Buffer*)>(Slots(aEffect)[7])(aEffect, aBuffer);
}

void End(void* aEffect)
{
    reinterpret_cast<int (*)(void*, void*)>(Slots(aEffect)[1])(aEffect, nullptr);
}

struct Audio
{
    std::vector<float> samples;
    Buffer buffer{};

    explicit Audio(int aChannels = 2, float aFill = 1.f) : samples(static_cast<size_t>(kFrames) * aChannels, aFill)
    {
        buffer = {samples.data(), static_cast<uint32_t>(aChannels) | (1 << 8), 45, kFrames, kFrames};
    }
    void Fill(float aValue)
    {
        std::fill(samples.begin(), samples.end(), aValue);
    }
    float& At(int aChannel, int aFrame)
    {
        return samples[static_cast<size_t>(aChannel) * kFrames + aFrame];
    }
};

void FreshStart()
{
    ResetControl();
    ResetTracks();
    ClearAudioBroken();
    g_control.mode.store(static_cast<int>(Mode::HearingProtection));
    g_control.mode.store(static_cast<int>(Mode::HearingProtection));
    g_control.soundOn.store(false); // only the clamp's own numbers, until a test asks for the rest
}

// Long enough that the headset is fully on.
void WearFully(void* aClamp, Audio& aAudio)
{
    for (int i = 0; i < 30; ++i)
    {
        aAudio.Fill(1.f);
        Run(aClamp, &aAudio.buffer);
    }
}

float DbGain(float aDb)
{
    return std::pow(10.f, aDb / 20.f);
}

void TestPlaces()
{
    std::printf("the buses and slots\n");
    struct Known
    {
        const char* name;
        uint32_t id;
    };
    const Known known[] = {
        {"Guns_Firing", 0x451dfbbe},    {"Gun_NPC_Fire", 0x4c7e1f08},       {"Gun_NPC_Fire_Important", 0x0d0d75e7},
        {"Grenades_SP", 0x9e0b3366},    {"Explosions_SP", 0x4ae39ba9},      {"Explosions", 0x2ce93fb5},
        {"Bullet_Impacts", 0xea9e8fd9}, {"Bullet_Impacts_SP", 0xef652f1d},  {"v_destruction", 0x8d818e88},
        {"Physics", 0x1a8feb14},        {"Effect_Bus_SP", 0x6d730099},      {"Ambiences", 0x3ca844c8},
        {"Community", 0x16d4dff8},      {"Consumables", 0xbf86f17b},        {"Devices", 0xfa77d906},
        {"Enemies", 0x85a8088b},        {"Foley", 0x0ec16eb6},              {"Locomotion", 0x21316dda},
        {"Locomotion_Additional", 0x952224d6}, {"Locomotion_Player", 0x533b8086}, {"Quest", 0x6b5d0665}, {"Perks", 0x0654798c},
        {"Vehicles", 0x39e64a16},       {"Vehicles_Suspensions", 0x8576bd8d}, {"Weapons", 0x577f56ac},
        {"VO_V", 0xf6e592ff},           {"VO_V_Onos", 0xe833cf33},          {"VO_Quest", 0xeab5ad7b},
        {"Music_Dgtc_Car_Hyper_INT", 0x412a469f},  {"Music_Dgtc_Car_Hyper_EXT", 0x4f0c4795},
        {"Music_Dgtc_Car_Lowend_INT", 0xaac406b6}, {"Music_Dgtc_Car_Lowend_EXT", 0x9cb96328},
        {"Music_Dgtc_Car_Muscle_INT", 0x5f4d7416}, {"Music_Dgtc_Car_Muscle_EXT", 0x5142d088},
        {"Music_Dgtc_Car_Sports_INT", 0x7e847e1e}, {"Music_Dgtc_Car_Sports_EXT", 0x90a2afa0},
        {"Music_Dgtc_Car_Suv_INT", 0x24747493},    {"Music_Dgtc_Car_Suv_EXT", 0x1a927a49},
        {"Music_Dgtc_Car_Truck_INT", 0xcbb41808},  {"Music_Dgtc_Car_Truck_EXT", 0xc19786de},
    };
    bool allMatch = true;
    for (const DetectorPlace& place : kDetectors)
    {
        bool found = false;
        for (const Known& k : known)
        {
            found = found || (std::strcmp(k.name, place.name) == 0 && k.id == place.bus);
        }
        allMatch = allMatch && found;
    }
    for (const ClampPlace& place : kClamps)
    {
        bool found = false;
        for (const Known& k : known)
        {
            found = found || (std::strcmp(k.name, place.name) == 0 && k.id == place.bus);
        }
        allMatch = allMatch && found;
    }
    Check(allMatch, "every bus name hashes to the ID in the game's init.bnk");

    std::set<std::pair<uint32_t, uint32_t>> taken;
    bool unique = true;
    bool inRange = true;
    for (const DetectorPlace& place : kDetectors)
    {
        unique = taken.insert({place.bus, place.slot}).second && unique;
        inRange = inRange && place.slot <= 3;
    }
    for (const ClampPlace& place : kClamps)
    {
        unique = taken.insert({place.bus, place.slot}).second && unique;
        inRange = inRange && place.slot <= 3;
    }
    Check(unique, "no two of ours share a slot on a bus");
    Check(inRange, "every slot is one of Wwise's four");
    // The game's own: Explosions uses 2 and 3, Explosions_SP uses 3.
    bool clear = true;
    for (const DetectorPlace& place : kDetectors)
    {
        clear = clear && !(place.bus == ak::Id("Explosions") && place.slot >= 2) && !(place.bus == ak::Id("Explosions_SP") && place.slot == 3);
    }
    for (const ClampPlace& place : kClamps)
    {
        clear = clear && !(place.bus == ak::Id("Explosions") && place.slot >= 2);
    }
    Check(clear, "and none is one the game's own effects use");
    bool detectorFirst = false;
    for (const DetectorPlace& place : kDetectors)
    {
        for (const ClampPlace& clamp : kClamps)
        {
            if (place.bus == clamp.bus)
            {
                detectorFirst = place.slot < clamp.slot;
            }
        }
    }
    Check(detectorFirst, "on the bus that has both, the detector comes first");
}

void TestBank()
{
    std::printf("the bank\n");
    const std::vector<uint8_t> bank = MakeBank();
    const auto read32 = [&bank](size_t aAt) {
        uint32_t value = 0;
        std::memcpy(&value, bank.data() + aAt, sizeof(value));
        return value;
    };
    Check(std::memcmp(bank.data(), "BKHD", 4) == 0 && read32(4) == 40 && read32(8) == 150, "a header of the size and version in the game's own banks");
    Check(std::memcmp(bank.data() + 48, "HIRC", 4) == 0, "then a list of objects");
    Check(bank.size() == 56 + static_cast<size_t>(read32(52)), "which ends where the file does");
    Check(read32(56) == static_cast<uint32_t>(kDetectorCount + kClampKindCount), "with one share set per detector and per kind of clamp");
    size_t at = 60;
    bool shapes = true;
    for (int i = 0; i < kDetectorCount + kClampKindCount; ++i)
    {
        shapes = shapes && bank[at] == 16 && read32(at + 1) == 27 && read32(at + 9) == kFullPluginId && read32(at + 13) == 8;
        at += 5 + 27;
    }
    Check(shapes, "each an effect share set naming our plug-in, with an 8 byte parameter block");
    Check(at == bank.size(), "and nothing is left over");
    Check(kFullPluginId == ((0x4853u << 16) | (173u << 4) | 3u), "our plug-in ID is company 173, plug-in 0x4853, effect");
}

void TestInterface()
{
    std::printf("the effect, called through the slots the game's own effects use\n");
    void* const params = NewParams();
    const uint32_t block[2] = {0, 1};
    Check(reinterpret_cast<int (*)(void*, void*, const void*, uint32_t)>(Slots(params)[3])(params, nullptr, block, 8) == 1, "parameters take their block in slot 3");
    void* const clone = reinterpret_cast<void* (*)(void*, void*)>(Slots(params)[2])(params, nullptr);
    Check(clone != nullptr && clone != params, "and clone themselves in slot 2");
    Check(reinterpret_cast<int (*)(void*, const void*, uint32_t)>(Slots(clone)[5])(clone, block, 8) == 1, "and take a new block in slot 5");
    Check(reinterpret_cast<int (*)(void*, void*)>(Slots(clone)[4])(clone, nullptr) == 1, "and end in slot 4");
    Check(reinterpret_cast<int (*)(void*, void*)>(Slots(params)[4])(params, nullptr) == 1, "both copies");

    void* const effect = NewEffect();
    uint8_t info[16] = {};
    Check(reinterpret_cast<int (*)(void*, void*)>(Slots(effect)[3])(effect, info) == 1, "the effect describes itself in slot 3");
    uint32_t build = 0;
    std::memcpy(&build, info + 4, sizeof(build));
    Check(info[0] == 3 && build == 0x7E701 && info[8] == 1 && info[13] == 1, "as an in-place effect of the game's Wwise build");
    Check(!reinterpret_cast<bool (*)(void*)>(Slots(effect)[4])(effect), "with no media to move");
    Format format{48000, kStereo};
    Check(reinterpret_cast<int (*)(void*, void*, void*, void*, Format*)>(Slots(effect)[6])(effect, nullptr, nullptr, nullptr, &format) == 1, "it starts up in slot 6");
    Check(reinterpret_cast<int (*)(void*, uint32_t)>(Slots(effect)[8])(effect, 512) == 45, "slot 8 skips time as the game's effects do");
    Check(reinterpret_cast<int (*)(void*)>(Slots(effect)[2])(effect) == 1, "slot 2 resets");
    Check(reinterpret_cast<int (*)(void*, void*)>(Slots(effect)[1])(effect, nullptr) == 1, "slot 1 ends it");
}

void TestEnvelope()
{
    std::printf("the clamp's numbers\n");
    ClampEnvelope clamp;
    clamp.Configure(48000);
    clamp.Reset();
    Check(clamp.Track(1.f, 0.57f, 0.01f) == 1.f, "exactly at the threshold nothing happens");
    Check(Near(clamp.Track(10.f, 0.57f, 0.01f), DbGain(-11.4f), 0.002f), "20 dB over comes down 11.4 dB at once");
    clamp.Reset();
    Check(Near(clamp.Track(1e6f, 0.57f, 0.01f), 0.01f, 1e-5f), "and never further than the deepest");
    float gain = 0.f;
    for (int i = 0; i < 960; ++i)
    {
        gain = clamp.Track(0.f, 0.57f, 0.01f);
    }
    Check(gain < 0.3f, "a bang's hold and release keep it down at first");
    for (int i = 0; i < 48000 * 3; ++i)
    {
        gain = clamp.Track(0.f, 0.57f, 0.01f);
    }
    Check(gain > 0.97f, "and it comes all the way back");
}

void TestClamping()
{
    std::printf("a bang through a detector and a clamp\n");
    FreshStart();
    void* const clamp = MakeEffect(Role::Clamp, 0);
    void* const detector = MakeEffect(Role::Detector, 0);
    Audio world;
    WearFully(clamp, world);
    Check(g_control.clampsAlive.load() >= 1 && g_control.detectorsAlive.load() >= 1, "both roles start");
    world.Fill(0.9f);
    Run(clamp, &world.buffer);
    Check(Near(world.At(0, 200), 0.9f, 1e-5f), "a loud sound with no bang behind it is left alone");

    // Guns_Firing: reading -20 dB is 130 dB real, so 45 over.
    Audio gun;
    gun.Fill(0.f);
    gun.At(0, 100) = 0.1f;
    world.Fill(1.f);
    Run(detector, &gun.buffer);
    Run(clamp, &world.buffer);
    Check(world.At(0, 99) == 1.f, "the sample before the bang is untouched");
    Check(Near(world.At(0, 100), DbGain(-45.f * kStartDepthPerDb), 0.003f), "and the bang's very sample is already down by the right amount");
    Check(Near(world.At(1, 100), DbGain(-45.f * kStartDepthPerDb), 0.003f), "in every channel");
    Check(Near(gun.At(0, 100), 0.1f, 1e-6f), "the detector leaves its own sound as it was");

    world.Fill(1.f);
    gun.Fill(0.f);
    Run(detector, &gun.buffer);
    Run(clamp, &world.buffer);
    Check(world.At(0, 500) < DbGain(-3.f), "it's still held down a frame later");

    for (int i = 0; i < 500; ++i)
    {
        world.Fill(1.f);
        gun.Fill(0.f);
        Run(detector, &gun.buffer);
        Run(clamp, &world.buffer);
    }
    Check(Near(world.At(0, 500), 1.f, 0.02f), "and recovers");
    End(clamp);
    End(detector);
}

void TestOrderAndSums()
{
    std::printf("order and several bangs\n");
    FreshStart();
    void* const beside = MakeEffect(Role::Clamp, 0);
    void* const detector = MakeEffect(Role::Detector, 0);
    Audio world;
    WearFully(beside, world);
    Audio gun;
    gun.Fill(0.f);
    gun.At(0, 50) = 0.1f;

    world.Fill(1.f);
    Run(beside, &world.buffer);
    Check(world.At(0, 50) == 1.f, "a clamp that runs before the detector hasn't heard the bang yet");
    Run(detector, &gun.buffer);
    world.Fill(1.f);
    Run(beside, &world.buffer);
    Check(world.At(0, 49) == 1.f && world.At(0, 50) < DbGain(-10.f), "it acts on the next frame, one frame late, at the same position");

    for (int i = 0; i < 500; ++i)
    {
        world.Fill(1.f);
        gun.Fill(0.f);
        Run(detector, &gun.buffer);
        Run(beside, &world.buffer);
    }
    const float recovered = world.At(0, 500);
    world.Fill(1.f);
    Run(beside, &world.buffer);
    Check(recovered > 0.95f && world.At(0, 500) > 0.95f, "and a detector frame counts only once");

    End(beside);
    End(detector);

    FreshStart();
    void* const clamp = MakeEffect(Role::Clamp, 0);
    void* const first = MakeEffect(Role::Detector, 1);
    void* const second = MakeEffect(Role::Detector, 2);
    Audio room;
    WearFully(clamp, room);
    Audio shot;
    shot.Fill(0.f);
    shot.At(0, 10) = 0.1f;
    Run(first, &shot.buffer);
    Run(second, &shot.buffer);
    room.Fill(1.f);
    Run(clamp, &room.buffer);
    // Gun_NPC_Fire and its sibling: -20 dB on top of their offset, and two together add 3 dB.
    const float npcOver = -20.f + kDetectors[1].offsetDb - kStartThresholdDb;
    Check(Near(20.f * std::log10(room.At(0, 10)), -(npcOver + 3.01f) * kStartDepthPerDb, 0.1f), "two shots at once count as their summed power");
    End(clamp);
    End(first);
    End(second);
}

void TestWearing()
{
    std::printf("wearing it\n");
    FreshStart();
    g_control.mode.store(static_cast<int>(Mode::Passthrough));
    void* const clamp = MakeEffect(Role::Clamp, 0);
    void* const detector = MakeEffect(Role::Detector, 0);
    Audio world;
    Audio gun;
    gun.Fill(0.f);
    gun.At(0, 100) = 0.1f;
    Run(detector, &gun.buffer);
    Run(clamp, &world.buffer);
    Check(world.At(0, 100) == 1.f, "not worn, a bang leaves the sound exactly as it was");

    g_control.mode.store(static_cast<int>(Mode::HearingProtection));
    for (int i = 0; i < 5; ++i)
    {
        world.Fill(1.f);
        Run(clamp, &world.buffer);
    }
    Run(detector, &gun.buffer);
    world.Fill(1.f);
    Run(clamp, &world.buffer);
    Check(world.At(0, 100) > 0.5f && world.At(0, 100) < 0.97f, "while it goes on, a bang only partly clamps");
    End(clamp);
    End(detector);

    FreshStart();
    void* const wakingDetector = MakeEffect(Role::Detector, 0);
    Audio firstShot;
    firstShot.Fill(0.f);
    firstShot.At(0, 100) = 0.1f;
    Run(wakingDetector, &firstShot.buffer);
    void* const woken = MakeEffect(Role::Clamp, 0); // Wwise made it because its bus just got a sound
    Audio wokenWorld;
    Run(woken, &wokenWorld.buffer);
    Check(Near(wokenWorld.At(0, 100), DbGain(-45.f * kStartDepthPerDb), 0.003f), "a clamp Wwise wakes up for a shot, while worn, clamps that first shot in full");
    End(woken);

    Run(wakingDetector, &firstShot.buffer);
    Sleep(40);
    void* const late2 = MakeEffect(Role::Clamp, 0);
    Audio lateWorld;
    Run(late2, &lateWorld.buffer);
    Check(lateWorld.At(0, 100) == 1.f, "but one waking up later doesn't react to that old shot");
    End(late2);
    End(wakingDetector);

    FreshStart();
    void* const again = MakeEffect(Role::Clamp, 0);
    Audio late;
    WearFully(again, late);
    g_control.mode.store(static_cast<int>(Mode::Passthrough));
    for (int i = 0; i < 30; ++i)
    {
        late.Fill(0.7f);
        Run(again, &late.buffer);
    }
    Check(Near(late.At(1, 300), 0.7f, 1e-5f), "taken off, the sound goes back to exactly as it was");
    End(again);

    FreshStart();
    g_control.mode.store(static_cast<int>(Mode::Passthrough));
    void* const off = MakeEffect(Role::Clamp, 0);
    void* const offDetector = MakeEffect(Role::Detector, 0);
    Audio quiet;
    Run(offDetector, &gun.buffer);
    Run(off, &quiet.buffer);
    Check(g_control.detectorRuns[0].load() == 0, "Off, the detectors don't even run");
    Check(quiet.At(0, 100) == 1.f, "and the sound is left alone");
    End(off);
    End(offDetector);
}

void TestChannels()
{
    std::printf("buses of any shape\n");
    FreshStart();
    void* const clamp = MakeEffect(Role::Clamp, 0);
    void* const detector = MakeEffect(Role::Detector, 0);
    Audio ambisonic(36);
    Audio surround(8);
    WearFully(clamp, surround);
    ambisonic.Fill(0.f);
    ambisonic.At(35, 7) = 0.1f;
    Run(detector, &ambisonic.buffer);
    surround.Fill(1.f);
    Run(clamp, &surround.buffer);
    Check(surround.At(7, 7) < DbGain(-10.f), "a bang in a 36 channel bus's last channel clamps a 7.1 bus's last channel");
    End(clamp);
    End(detector);

    FreshStart();
    void* const broken = MakeEffect(Role::Detector, 0);
    Buffer wild{reinterpret_cast<void*>(0x10), kStereo, 45, kFrames, kFrames};
    Run(broken, &wild);
    Check(AudioBroken(), "a bad buffer is caught, not a crash");
    Audio after;
    Run(broken, &after.buffer);
    Check(after.At(0, 0) == 1.f, "and the effect then leaves everything alone");
    ClearAudioBroken();
    End(broken);
}

// A steady tone through an effect, with an optional steady bang before it each frame; the level out of the last frame against
// the level in, in dB.
float ToneThrough(void* aEffect, float aHz, void* aDetector = nullptr, int aFrames = 60, float kAmp = 0.25f)
{
    Audio audio;
    Audio bang;
    double phase = 0.0;
    const double step = 6.283185307179586 * aHz / 48000.0;
    float out = 0.f;
    float in = 1.f;
    for (int frame = 0; frame < aFrames; ++frame)
    {
        double powerIn = 0.0;
        for (int i = 0; i < kFrames; ++i)
        {
            const float value = kAmp * static_cast<float>(std::sin(phase));
            audio.At(0, i) = value;
            audio.At(1, i) = value;
            powerIn += static_cast<double>(value) * value;
            phase += step;
        }
        in = static_cast<float>(std::sqrt(powerIn / kFrames)); // this very frame's, since a low tone doesn't fill a frame evenly
        if (aDetector)
        {
            bang.Fill(0.1f);
            Run(aDetector, &bang.buffer);
        }
        Run(aEffect, &audio.buffer);
        double power = 0.0;
        for (int i = 0; i < kFrames; ++i)
        {
            power += static_cast<double>(audio.At(0, i)) * audio.At(0, i);
        }
        out = static_cast<float>(std::sqrt(power / kFrames));
    }
    return 20.f * std::log10(std::max(out, 1e-6f) / in);
}

void TestSound()
{
    std::printf("the microphones and the cups\n");
    FreshStart();
    g_control.soundOn.store(true);
    void* const clamp = MakeEffect(Role::Clamp, 0);
    g_control.offsetDb[1].store(148.f); // reckoned a very close shot: a reading of -20 dB is 128 real, 43 over
    void* const detector = MakeEffect(Role::Detector, 1);
    const float expected = -43.f * kStartDepthPerDb;

    Check(Near(ToneThrough(clamp, 1000.f), 0.f, 1.5f), "with no bang, the middle of the sound passes about as it was");
    const float bass = ToneThrough(clamp, 40.f);
    Check(bass < -3.f && bass > -11.f, "deep bass is thinner, the microphones losing it and only the cups passing it");
    const float top = ToneThrough(clamp, 14000.f);
    Check(top < -3.f, "and so is the very top");

    Check(Near(ToneThrough(clamp, 2000.f, detector), expected, 3.f), "during a bang the middle comes down with the microphones");
    const float thump = ToneThrough(clamp, 60.f, detector);
    Check(thump > -13.f && thump < -8.f, "but the low end still gets through the cups, about 10 dB down");
    Check(thump > expected + 10.f, "so a bang is heard as a muffled thump");

    g_control.leakDb.store(-60.f);
    Check(ToneThrough(clamp, 60.f, detector) < expected + 3.f, "and a quieter leak takes that away");
    End(clamp);
    End(detector);

    FreshStart();
    g_control.soundOn.store(true);
    void* const ownGun = MakeEffect(Role::Detector, 0);
    const float recoil = ToneThrough(ownGun, 60.f);
    Check(recoil > kStartRecoilDb - 2.5f && recoil < kStartRecoilDb + 0.5f, "your own gun's lows are raised");
    Check(Near(ToneThrough(ownGun, 2000.f), 0.f, 0.5f), "its middle isn't");
    g_control.recoilDb.store(0.f);
    Check(Near(ToneThrough(ownGun, 60.f), 0.f, 0.01f), "and a recoil of 0 leaves it alone");
    g_control.recoilDb.store(kStartRecoilDb);
    g_control.soundOn.store(false);
    Check(Near(ToneThrough(ownGun, 60.f), 0.f, 0.01f), "as does turning the sound off");
    End(ownGun);

    FreshStart();
    g_control.soundOn.store(true);
    void* const npcGun = MakeEffect(Role::Detector, 1);
    const float npcThump = ToneThrough(npcGun, 60.f);
    Check(npcThump > kStartThumpDb - 2.5f && npcThump < kStartThumpDb + 0.5f, "an NPC's gun gets its own thump");
    Check(Near(ToneThrough(npcGun, 2000.f), 0.f, 0.5f), "in the lows only");
    g_control.recoilDb.store(0.f);
    Check(ToneThrough(npcGun, 60.f) > kStartThumpDb - 2.5f, "and your own gun's setting doesn't touch it");
    g_control.recoilDb.store(kStartRecoilDb);
    g_control.thumpDb.store(0.f);
    Check(Near(ToneThrough(npcGun, 60.f), 0.f, 0.01f), "its own does");
    g_control.thumpDb.store(kStartThumpDb);
    End(npcGun);

    bool thumpsWhereWanted = true;
    for (int i = 0; i < kDetectorCount; ++i)
    {
        const std::string name = kDetectors[i].name;
        const bool blast = name.rfind("Gun_NPC", 0) == 0 || name.rfind("Explosions", 0) == 0 || name == "Grenades_SP";
        const Thump wanted = name == "Guns_Firing" ? Thump::OwnGun : blast ? Thump::Others : Thump::None;
        thumpsWhereWanted = thumpsWhereWanted && kDetectors[i].thump == wanted;
    }
    Check(thumpsWhereWanted, "guns and blasts thump, and impacts, crashes and physics don't");

    FreshStart();
    g_control.soundOn.store(true);
    void* const physics = MakeEffect(Role::Detector, kDetectorCount - 1);
    Check(Near(ToneThrough(physics, 60.f), 0.f, 0.01f), "heavy things hitting things get none");
    End(physics);

    FreshStart();
    g_control.soundOn.store(true);
    g_control.mode.store(static_cast<int>(Mode::Passthrough));
    void* const offGun = MakeEffect(Role::Detector, 0);
    Check(Near(ToneThrough(offGun, 60.f), 0.f, 0.01f), "and nothing is raised while it isn't worn");
    End(offGun);

    FreshStart();
    g_control.soundOn.store(true);
    void* const wide = MakeEffect(Role::Clamp, 0);
    Audio many(36, 0.5f);
    Run(wide, &many.buffer);
    Check(Near(many.At(35, 100), 0.5f, 1e-5f), "a bus with more channels than the ears gets only the clamp");
    End(wide);
}

float Rms(Audio& aAudio, int aChannel)
{
    double power = 0.0;
    for (int i = 0; i < kFrames; ++i)
    {
        power += static_cast<double>(aAudio.At(aChannel, i)) * aAudio.At(aChannel, i);
    }
    return static_cast<float>(std::sqrt(power / kFrames));
}

void TestLiftHissAndWidth()
{
    std::printf("the talk-through's character\n");
    FreshStart();
    g_control.soundOn.store(true);
    void* const plain = MakeEffect(Role::Clamp, static_cast<uint32_t>(ClampKind::Plain));
    const float quiet = ToneThrough(plain, 1000.f, nullptr, 300, 0.003f);
    Check(quiet > 4.f && quiet < 7.f, "a quiet sound is lifted, up to 6 dB");
    Check(Near(ToneThrough(plain, 1000.f, nullptr, 300, 0.25f), 0.f, 1.5f), "a loud one isn't");
    End(plain);

    FreshStart();
    g_control.soundOn.store(true);
    void* const world = MakeEffect(Role::Clamp, static_cast<uint32_t>(ClampKind::World));
    Audio silence;
    for (int i = 0; i < 40; ++i)
    {
        silence.Fill(0.f);
        Run(world, &silence.buffer);
    }
    const float hissLeft = 20.f * std::log10(std::max(Rms(silence, 0), 1e-9f));
    const float hissRight = 20.f * std::log10(std::max(Rms(silence, 1), 1e-9f));
    Check(Near(hissLeft, kStartHissDb, 3.f) && Near(hissRight, kStartHissDb, 3.f), "the world's bus has a faint hiss, even in silence");
    Check(silence.At(0, 100) != silence.At(1, 100), "different in each ear");

    Audio oneSide;
    double phase = 0.0;
    for (int frame = 0; frame < 60; ++frame)
    {
        for (int i = 0; i < kFrames; ++i)
        {
            oneSide.At(0, i) = 0.25f * static_cast<float>(std::sin(phase));
            oneSide.At(1, i) = 0.f;
            phase += 6.283185307179586 * 1000.0 / 48000.0;
        }
        Run(world, &oneSide.buffer);
    }
    Check(Near(20.f * std::log10(Rms(oneSide, 1) / Rms(oneSide, 0)), -16.9f, 1.5f), "and a sound in one ear spreads a little to the other");
    End(world);

    FreshStart();
    g_control.soundOn.store(true);
    void* const beside = MakeEffect(Role::Clamp, static_cast<uint32_t>(ClampKind::Plain));
    Audio plainSilence;
    for (int i = 0; i < 40; ++i)
    {
        plainSilence.Fill(0.f);
        Run(beside, &plainSilence.buffer);
    }
    Check(Rms(plainSilence, 0) == 0.f, "other buses add no hiss of their own, so it's there only once");
    End(beside);
}

void TestNoiseCancelling()
{
    std::printf("noise cancelling\n");
    FreshStart();
    g_control.soundOn.store(true);
    g_control.mode.store(static_cast<int>(Mode::NoiseCancelling));
    void* const plain = MakeEffect(Role::Clamp, static_cast<uint32_t>(ClampKind::Plain));
    Check(Near(ToneThrough(plain, 100.f), kStartNoiseLowDb, 3.f), "the lows go most");
    Check(Near(ToneThrough(plain, 1400.f), kStartNoiseMidDb, 3.5f), "the middle goes least");
    Check(Near(ToneThrough(plain, 12000.f), kStartNoiseHighDb, 3.f), "the highs go too");
    void* const detector = MakeEffect(Role::Detector, 1);
    const float steadyLow = ToneThrough(plain, 100.f);
    const float bangLow = ToneThrough(plain, 100.f, detector);
    Check(Near(bangLow, kStartNoiseBangLowDb, 3.f), "a bang's lows get through, the cancelling not keeping up with it");
    Check(bangLow > steadyLow + 10.f, "far more than a steady low does");
    Check(Near(ToneThrough(plain, 1400.f, detector), kStartNoiseBangMidDb, 3.5f), "the middle gets through more too");
    Check(Near(ToneThrough(plain, 12000.f, detector), kStartNoiseBangHighDb, 3.f), "and the highs");
    End(detector);
    Check(Near(ToneThrough(plain, 100.f, nullptr, 400), kStartNoiseLowDb, 3.f), "and once the bang's over it cancels again");
    g_control.soundOn.store(false);
    Check(Near(ToneThrough(plain, 100.f), 0.f, 0.01f), "with the sound off it's left alone");
    g_control.soundOn.store(true);
    End(plain);

    void* const steps = MakeEffect(Role::Clamp, static_cast<uint32_t>(ClampKind::OwnBody));
    Check(Near(ToneThrough(steps, 100.f), 0.f, 2.5f), "your own steps keep their lows, coming through your body");
    End(steps);

    void* const voice = MakeEffect(Role::Clamp, static_cast<uint32_t>(ClampKind::VoiceOfV));
    Check(ToneThrough(voice, 5000.f) < -20.f, "V's voice loses its air, and only the body path's tail is left up top");
    End(voice);
}

void TestBody()
{
    std::printf("V's own body\n");
    FreshStart();
    g_control.soundOn.store(true);
    void* const voice = MakeEffect(Role::Clamp, static_cast<uint32_t>(ClampKind::VoiceOfV));
    Check(Near(ToneThrough(voice, 5000.f), kStartAirOpenDb, 1.f), "with the mics open V is only a little thinner up top");
    Check(Near(ToneThrough(voice, 100.f), kStartBodyDb, 1.f), "and a little warmer down low");
    void* const detector = MakeEffect(Role::Detector, 1);
    Check(ToneThrough(voice, 5000.f, detector) < -20.f, "during a bang the air goes");
    // Gun_NPC_Fire reckoned a very close shot, at a reading of -20 dB: 43 over, so the clamp says 24.5 dB, and the mask is three quarters of that.
    g_control.offsetDb[1].store(148.f);
    const float maskedDb = -43.f * kStartDepthPerDb * (-kStartMaskDb / kStartDeepestDb);
    Check(Near(ToneThrough(voice, 100.f, detector), kStartBodyDb + maskedDb, 2.f), "and the bang drowns out the body path too");
    g_control.offsetDb[1].store(120.f); // the same shot, reckoned 28 dB quieter in the real world
    const float distant = ToneThrough(voice, 100.f, detector);
    Check(distant > kStartBodyDb + maskedDb + 6.f && distant < kStartBodyDb, "a quieter bang drowns V out less");
    g_control.offsetDb[1].store(148.f);
    g_control.maskDb.store(0.f);
    Check(Near(ToneThrough(voice, 100.f, detector), kStartBodyDb, 1.f), "a mask of 0 lets the body path carry on");
    g_control.maskDb.store(kStartMaskDb);
    g_control.mode.store(static_cast<int>(Mode::NoiseCancelling));
    Check(Near(ToneThrough(voice, 100.f, detector), kStartBodyDb + maskedDb, 2.f), "a bang drowns V out in noise cancelling too");
    g_control.mode.store(static_cast<int>(Mode::HearingProtection));
    Check(Near(ToneThrough(voice, 100.f, nullptr, 400), kStartBodyDb, 1.f), "and V comes back once it's over");
    g_control.soundOn.store(false);
    Check(Near(ToneThrough(voice, 5000.f, detector), 0.f, 0.01f), "with the sound off V is left exactly alone");
    g_control.soundOn.store(true);
    End(voice);

    Sleep(40); // the last bang above is now too old for a new effect to count as the one that woke it
    void* const grunts = MakeEffect(Role::Clamp, static_cast<uint32_t>(ClampKind::BreathOfV));
    Check(Near(ToneThrough(grunts, 5000.f), kStartGruntOpenDb, 1.f), "V's grunts have their own open level");
    Check(Near(ToneThrough(grunts, 100.f), kStartGruntBodyDb, 1.f), "and their own warmth");
    Check(ToneThrough(grunts, 5000.f, detector) < -20.f, "and lose their air during a bang");
    Check(Near(ToneThrough(grunts, 100.f, detector), kStartGruntBodyDb, 1.5f), "but in dynamic clamping a bang doesn't drown them out");
    g_control.mode.store(static_cast<int>(Mode::NoiseCancelling));
    Check(Near(ToneThrough(grunts, 100.f, detector), kStartGruntBodyDb + maskedDb, 2.f), "as it does in noise cancelling");
    g_control.mode.store(static_cast<int>(Mode::HearingProtection));
    Sleep(40);
    const float brightBody = ToneThrough(grunts, 300.f, nullptr, 500);
    g_control.gruntBodyHz.store(150.f);
    const float darkBody = ToneThrough(grunts, 300.f, nullptr, 200);
    Check(darkBody < brightBody - 2.f, "and their skull path can be made darker while playing");
    g_control.gruntBodyHz.store(kStartGruntBodyHz);
    End(grunts);
    End(detector);

    FreshStart();
    g_control.soundOn.store(true);
    void* const plain = MakeEffect(Role::Clamp, static_cast<uint32_t>(ClampKind::Plain));
    void* const steps = MakeEffect(Role::Clamp, static_cast<uint32_t>(ClampKind::OwnBody));
    void* const bang = MakeEffect(Role::Detector, 1);
    const float others = ToneThrough(plain, 60.f, bang);
    ResetTracks();
    const float mine = ToneThrough(steps, 60.f, bang);
    Check(Near(mine - others, kStartFootstepDb, 2.f), "your own steps thud harder through the cups than others'");
    End(plain);
    End(steps);
    End(bang);
}

void TestModes()
{
    std::printf("the modes\n");
    ResetControl();
    Check(EffectiveMode() == Mode::Passthrough, "the headset starts doing nothing");
    Check(!IsWorn(), "which counts as not worn");
    CycleMode();
    Check(EffectiveMode() == Mode::NoiseCancelling, "a tap goes to noise cancelling first");
    CycleMode();
    Check(EffectiveMode() == Mode::HearingProtection, "the next to hearing protection");
    CycleMode();
    Check(EffectiveMode() == Mode::Passthrough, "and the next round to passthrough");
    ChooseMode(Mode::HearingProtection);
    Check(EffectiveMode() == Mode::HearingProtection, "the wheel picks any mode");
    CycleMode();
    Check(EffectiveMode() == Mode::Passthrough, "and a tap carries on from there");

    FreshStart();
    g_control.soundOn.store(true);
    void* const clamp = MakeEffect(Role::Clamp, static_cast<uint32_t>(ClampKind::Plain));
    Check(Near(ToneThrough(clamp, 1000.f), 0.f, 1.5f), "hearing protection passes the middle");
    ChooseMode(Mode::NoiseCancelling);
    Check(Near(ToneThrough(clamp, 100.f), kStartNoiseLowDb, 3.f), "changing mode takes effect after its fade");
    ChooseMode(Mode::Passthrough);
    Check(Near(ToneThrough(clamp, 100.f), 0.f, 0.01f), "and passthrough does nothing at all");
    End(clamp);
}

float VoicesTone(float aHz, int aBlocks = 200)
{
    constexpr int kBlock = 480;
    std::vector<float> left(kBlock);
    std::vector<float> right(kBlock);
    double phase = 0.0;
    double powerOut = 0.0;
    double powerIn = 0.0;
    for (int block = 0; block < aBlocks; ++block)
    {
        powerIn = 0.0;
        for (int i = 0; i < kBlock; ++i)
        {
            left[i] = right[i] = 0.25f * static_cast<float>(std::sin(phase));
            powerIn += static_cast<double>(left[i]) * left[i];
            phase += 6.283185307179586 * aHz / 48000.0;
        }
        g_control.worldClampAtMs.store(NowMs());
        ProcessNearbyVoices(left.data(), right.data(), kBlock);
        powerOut = 0.0;
        for (int i = 0; i < kBlock; ++i)
        {
            powerOut += static_cast<double>(left[i]) * left[i];
        }
    }
    return 10.f * static_cast<float>(std::log10(std::max(powerOut, 1e-12) / powerIn));
}

void TestNearbyVoices()
{
    std::printf("nearby voices through the headset\n");
    FreshStart();
    ResetNearbyVoices();
    g_control.soundOn.store(true);
    Check(Near(VoicesTone(1000.f), 0.f, 1.5f), "with nothing clamping, a voice passes about as it was");
    Check(VoicesTone(50.f) < -3.f, "a little thinner down low");
    g_control.worldClamp.store(0.01f);
    Check(Near(VoicesTone(4000.f), -40.f, 3.f), "a bang takes a shout down with the world");
    Check(Near(VoicesTone(60.f), kStartLeakDb, 3.f), "leaving what comes through the cups");
    g_control.worldClamp.store(1.f);

    ChooseMode(Mode::NoiseCancelling);
    Check(Near(VoicesTone(100.f), kStartNoiseLowDb, 3.f), "noise cancelling cuts them like the world");
    g_control.worldClamp.store(0.01f);
    Check(Near(VoicesTone(100.f), kStartNoiseBangLowDb, 3.f), "and lets a bang's lows through");
    g_control.worldClamp.store(1.f);

    ChooseMode(Mode::Passthrough);
    Check(Near(VoicesTone(100.f), 0.f, 0.01f), "passthrough leaves them exactly alone");

    FreshStart();
    ResetNearbyVoices();
    g_control.soundOn.store(true);
    g_control.worldClamp.store(0.01f);
    g_control.worldClampAtMs.store(NowMs() - 2000.0);
    std::vector<float> left(480, 0.25f);
    std::vector<float> right(480, 0.25f);
    for (int i = 0; i < 40; ++i)
    {
        std::fill(left.begin(), left.end(), 0.25f);
        std::fill(right.begin(), right.end(), 0.25f);
        ProcessNearbyVoices(left.data(), right.data(), 480);
    }
    Check(left[479] > 0.01f, "a stale clamp from the world's sound stopping isn't followed");
}

void TestWithoutWwise()
{
    std::printf("in a program with no Wwise\n");
    FreshStart();
    const std::filesystem::path file = std::filesystem::temp_directory_path() / L"headset_test_tuning.ini";
    {
        std::ofstream out(file, std::ios::trunc);
        out << "# a comment\nthreshold_db=90\ndepth_per_db=0.5\ndeepest_db=30\nalways_worn=1\noffset_Guns_Firing=140\n";
    }
    Check(ReadTuning(file), "the tuning file is read");
    Check(g_control.thresholdDb.load() == 90.f && g_control.depthPerDb.load() == 0.5f && g_control.deepestDb.load() == 30.f, "with its numbers");
    Check(g_control.wornByTuning.load() && g_control.offsetDb[0].load() == 140.f, "its always-worn and its offsets by bus name");
    Check(!ReadTuning(file), "and only once until it changes");
    std::filesystem::remove(file);

    StartInstaller(file);
    const double until = NowMs() + 2000.0;
    while (NowMs() < until && GetInstallState() != InstallState::NotAvailable)
    {
        Sleep(5);
    }
    Check(GetInstallState() == InstallState::NotAvailable, "it notices there's no Wwise to attach to");
    Sleep(200);
    Check(std::filesystem::exists(file), "it makes the tuning file when there isn't one");
    Check(g_control.depthPerDb.load() == kStartDepthPerDb && g_control.offsetDb[0].load() == kDetectors[0].offsetDb, "and reads the starting values back from it");
    StopInstaller();
    Check(GetInstallState() == InstallState::Off, "and it shuts down cleanly");
    std::filesystem::remove(file);
}

void TestBuildStamps()
{
    std::printf("finding Wwise's build in the game's code\n");
    const uint8_t stamp[] = {0xC7, 0x42, 0x04, 0x01, 0xE7, 0x07, 0x00};
    std::vector<uint8_t> code(64, 0xCC);
    Check(CountBuildStamps(code.data(), code.size(), ak::kBuildVersion) == 0, "none in code without one");
    std::copy(std::begin(stamp), std::end(stamp), code.begin());
    std::copy(std::begin(stamp), std::end(stamp), code.begin() + 20);
    std::copy(std::begin(stamp), std::end(stamp), code.end() - sizeof(stamp));
    Check(CountBuildStamps(code.data(), code.size(), ak::kBuildVersion) == 3, "one at the start, one inside and one at the very end");
    Check(CountBuildStamps(code.data(), code.size(), 0x7E501) == 0, "another build's number isn't counted");
    Check(CountBuildStamps(code.data(), code.size() - 1, ak::kBuildVersion) == 2, "and one cut off by the end of the code isn't either");
}
} // namespace

int main()
{
    TestPlaces();
    TestBank();
    TestInterface();
    TestEnvelope();
    TestClamping();
    TestOrderAndSums();
    TestWearing();
    TestChannels();
    TestSound();
    TestLiftHissAndWidth();
    TestNoiseCancelling();
    TestBody();
    TestModes();
    TestNearbyVoices();
    TestWithoutWwise();
    TestBuildStamps();
    std::printf("\n%s (%d failure%s)\n", g_failures == 0 ? "ALL OK" : "FAILED", g_failures, g_failures == 1 ? "" : "s");
    return g_failures == 0 ? 0 : 1;
}
