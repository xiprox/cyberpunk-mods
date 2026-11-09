// Which of the game's buses the headset's effect sits on, and in which of Wwise's four effect slots (0 to 3). Published in
// the README, so another mod adding an effect can keep clear: SetBusEffect silently replaces whatever is in a slot. Each slot
// here is the highest one init.bnk leaves free on that bus.
#pragma once

#include "wwise/ak.hpp"

namespace hs
{
// Sounds that can set the clamp off. offsetDb turns a bus's level (dB of its samples) into an estimate of real-world loudness:
// the loudest reading seen on that bus is taken as the real thing at its loudest. Rough until calibrated in the game.
// Thump: the lows raised on that bus, after it's read and before the clamp and the cups, as felt in the body.
enum class Thump : uint32_t
{
    None = 0,
    OwnGun = 1, // recoil_db: through the shoulder
    Others = 2, // thump_db: other people's shots and blasts, through the chest
};

struct DetectorPlace
{
    const char* name;
    uint32_t bus;
    uint32_t slot;
    float offsetDb;
    Thump thump;
};
inline constexpr DetectorPlace kDetectors[] = {
    {"Guns_Firing", ak::Id("Guns_Firing"), 3, 150.f, Thump::OwnGun},        // your own gun; about +8 dB is a shot at your ear
    {"Gun_NPC_Fire", ak::Id("Gun_NPC_Fire"), 3, 136.f, Thump::Others},      // others' guns; at 148 close ones all hit the clamp's limit
    {"Gun_NPC_Fire_Important", ak::Id("Gun_NPC_Fire_Important"), 3, 136.f, Thump::Others},
    {"Grenades_SP", ak::Id("Grenades_SP"), 3, 161.f, Thump::Others},
    {"Explosions_SP", ak::Id("Explosions_SP"), 2, 164.f, Thump::Others},
    {"Explosions", ak::Id("Explosions"), 0, 164.f, Thump::Others},          // slots 2 and 3 are the game's; 1 is our clamp's
    {"Bullet_Impacts", ak::Id("Bullet_Impacts"), 3, 124.f, Thump::None},
    {"Bullet_Impacts_SP", ak::Id("Bullet_Impacts_SP"), 3, 124.f, Thump::None},
    {"v_destruction", ak::Id("v_destruction"), 3, 108.f, Thump::None},      // crashes; 120 clamped 6-10 dB for minutes with nothing happening
    {"Physics", ak::Id("Physics"), 3, 116.f, Thump::None},                  // heavy things hitting things
};
inline constexpr int kDetectorCount = static_cast<int>(sizeof(kDetectors) / sizeof(kDetectors[0]));

enum class ClampKind : uint32_t
{
    Plain = 0,   // the microphones and the cups
    World = 1,   // the same, plus the hiss and the narrowing, once: the one stereo bus that carries the whole world
    OwnBody = 2, // the same, plus your own steps through your body
    VoiceOfV = 3, // a body path and an air path, the air following the microphones; a bang drowns the whole of it out
    BreathOfV = 4, // the same for V's grunts and breathing, set a little differently from V's lines
};
inline constexpr int kClampKindCount = 5;

// Where the headset acts: everything its microphones would pick up. UI, full-screen effects, score music, phone and Johnny's
// voices (implant audio), and the radio on a bike or in your pocket are on buses with no effect of ours, so they stay out.
struct ClampPlace
{
    const char* name;
    uint32_t bus;
    uint32_t slot;
    ClampKind kind;
};
inline constexpr ClampPlace kClamps[] = {
    {"Effect_Bus_SP", ak::Id("Effect_Bus_SP"), 3, ClampKind::World}, // the whole world: NPCs, traffic, their guns, reverb, shop music
    {"Ambiences", ak::Id("Ambiences"), 3, ClampKind::Plain},
    {"Community", ak::Id("Community"), 3, ClampKind::Plain},
    {"Consumables", ak::Id("Consumables"), 3, ClampKind::Plain},
    {"Devices", ak::Id("Devices"), 3, ClampKind::Plain},
    {"Enemies", ak::Id("Enemies"), 3, ClampKind::Plain},
    {"Explosions", ak::Id("Explosions"), 1, ClampKind::Plain},
    {"Foley", ak::Id("Foley"), 3, ClampKind::Plain},
    {"Locomotion", ak::Id("Locomotion"), 3, ClampKind::Plain},
    {"Locomotion_Additional", ak::Id("Locomotion_Additional"), 3, ClampKind::Plain},
    {"Locomotion_Player", ak::Id("Locomotion_Player"), 3, ClampKind::OwnBody}, // your footsteps
    {"Perks", ak::Id("Perks"), 3, ClampKind::Plain},                  // cybernetic legs' double jump, dash, and perk weapons' charges
    {"Quest", ak::Id("Quest"), 3, ClampKind::Plain},
    {"Vehicles", ak::Id("Vehicles"), 3, ClampKind::Plain},
    {"Vehicles_Suspensions", ak::Id("Vehicles_Suspensions"), 3, ClampKind::Plain},
    {"Weapons", ak::Id("Weapons"), 3, ClampKind::Plain},
    {"VO_Quest", ak::Id("VO_Quest"), 3, ClampKind::Plain},            // story characters speaking in person, which skip Effect_Bus_SP; calls are on VO_Phone
    // A car's radio comes from speakers in the cabin. Each kind of car has its own bus, inside and outside view; bikes' are apart.
    {"Music_Dgtc_Car_Hyper_INT", ak::Id("Music_Dgtc_Car_Hyper_INT"), 3, ClampKind::Plain},
    {"Music_Dgtc_Car_Hyper_EXT", ak::Id("Music_Dgtc_Car_Hyper_EXT"), 3, ClampKind::Plain},
    {"Music_Dgtc_Car_Lowend_INT", ak::Id("Music_Dgtc_Car_Lowend_INT"), 3, ClampKind::Plain},
    {"Music_Dgtc_Car_Lowend_EXT", ak::Id("Music_Dgtc_Car_Lowend_EXT"), 3, ClampKind::Plain},
    {"Music_Dgtc_Car_Muscle_INT", ak::Id("Music_Dgtc_Car_Muscle_INT"), 3, ClampKind::Plain},
    {"Music_Dgtc_Car_Muscle_EXT", ak::Id("Music_Dgtc_Car_Muscle_EXT"), 3, ClampKind::Plain},
    {"Music_Dgtc_Car_Sports_INT", ak::Id("Music_Dgtc_Car_Sports_INT"), 3, ClampKind::Plain},
    {"Music_Dgtc_Car_Sports_EXT", ak::Id("Music_Dgtc_Car_Sports_EXT"), 3, ClampKind::Plain},
    {"Music_Dgtc_Car_Suv_INT", ak::Id("Music_Dgtc_Car_Suv_INT"), 3, ClampKind::Plain},
    {"Music_Dgtc_Car_Suv_EXT", ak::Id("Music_Dgtc_Car_Suv_EXT"), 3, ClampKind::Plain},
    {"Music_Dgtc_Car_Truck_INT", ak::Id("Music_Dgtc_Car_Truck_INT"), 3, ClampKind::Plain},
    {"Music_Dgtc_Car_Truck_EXT", ak::Id("Music_Dgtc_Car_Truck_EXT"), 3, ClampKind::Plain},
    {"VO_V", ak::Id("VO_V"), 3, ClampKind::VoiceOfV},                 // V's lines
    {"VO_V_Onos", ak::Id("VO_V_Onos"), 3, ClampKind::BreathOfV},      // V's breathing and grunts: the lcm_breathing events play here
};
inline constexpr int kClampCount = static_cast<int>(sizeof(kClamps) / sizeof(kClamps[0]));

// Ours, chosen not to collide. Plug-in companies 64..255 are for in-house use; the game's banks use 0 and CDPR's 666.
inline constexpr uint32_t kCompany = 173;
inline constexpr uint32_t kPlugin = 0x4853; // "HS"
inline constexpr uint32_t kFullPluginId = (kPlugin << 16) | (kCompany << 4) | static_cast<uint32_t>(ak::kPluginTypeEffect);
inline constexpr uint32_t kBankId = ak::Id("xip_headset_bank");
inline constexpr uint32_t kClampShareSetBase = ak::Id("xip_headset_clamp"); // one per ClampKind
inline constexpr uint32_t kDetectorShareSetBase = ak::Id("xip_headset_detector");
} // namespace hs
