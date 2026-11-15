![The headset's HUD icon, large, beside its Hearing Protection, Noise Cancelling, and Passthrough rows](header.png)

# Headset

Adds a tactical headset that mimics how real hearing protection and noise cancelling sound, with three modes on one key.

- **Hearing protection** lets you hear the street through its microphones and clamps gunshots, explosions, and crashes the instant they happen.
  It judges each sound by what it is and how loud it would be in real life, so shouting, engines, and the radio never set it off.
- **Noise cancelling** shuts the city out, but can't keep up with a shot, so gunfire still comes through.
- **Passthrough:** as if the headset weren't there.

Outside Passthrough, you hear yourself from the inside: V's voice and breathing through the skull, footsteps through your body, and a kick in your own shots.

## Using it

The headset key is the comma key (`,`) by default, and you can change it under Mods > Headset in the main menu or the pause menu.

- **Tap** it for the next mode.
- **Hold** it to pick a mode from a wheel.
  In co-op, time doesn't slow down while the wheel is open, so pick a safe moment.

With **Radioport puts the headset on** switched on in the same menu, turning the Radioport on in Passthrough switches to noise cancelling, or to hearing protection if you choose it there, and turning it off goes back to Passthrough.

## What it needs

RED4ext, redscript, Cyber Engine Tweaks, Codeware, and Native Settings, on Cyberpunk 2077 2.5.

## Installing

Extract the zip into the game folder, or install it with your mod manager.
To remove it, delete `red4ext/plugins/Headset`, `bin/x64/plugins/cyber_engine_tweaks/mods/Headset`, and `archive/pc/mod/headset`.

## Compatibility

- **Co-op:** works on NightCoop.
- **Linux:** runs under Proton.
- **Sound mods:** untried with mods that replace the game's sounds, which the headset is tuned to.
- **Game patches:** if a patch changes the game's audio engine, the headset switches itself off until it's updated.

## Known limits

Sliding, the Fortified Ankles' charged jump, and Superhero Landing come through unchanged.

## Bug reports

Close the game and attach the newest `red4ext/logs/headset-*.log` from the game folder.

## For developers

### How it works

Headset is a RED4ext plugin that registers a Wwise effect plug-in with the game's own Wwise, whose functions the game's exe exports by name, and puts that effect on the game's buses.
A detector on each bus that carries bangs, such as `Guns_Firing`, turns the bus's level into an estimate of real-world loudness, with an offset for each bus.
A clamp on each bus a headset's microphones would pick up turns that bus down by how far the detectors' estimates, added as power, are over the threshold, and adds the leak through the cups.
Noise cancelling is three bands on the same buses, and V's voice and breathing get their body path on `VO_V` and `VO_V_Onos`.
The starting values are in `src/headset/control.hpp`, each detector's offset is in `src/wwise/places.hpp`, and [RECORD.md](RECORD.md) says why each part is the way it is, and what the game's banks showed.

The effect's interface was read from the game's exe, not from a Wwise SDK, so before touching Wwise the plugin checks that the game's effects carry the build number `src/wwise/ak.hpp` was read from (`kBuildVersion`, at least `kMinBuildStamps` of them).
On any other build it logs why and stays off.

### For other mods adding Wwise effects

A bus has four effect slots, and `SetBusEffect` puts an effect in the one it's given, replacing what's there (unverified: we haven't put an effect over one of the game's), so stay clear of these.
Each slot in the table is the highest one the game's `init.bnk` leaves free on that bus.
`src/wwise/places.hpp` is the source of this table, so change both together.

| Bus | Slot | Use |
|---|---|---|
| `Guns_Firing`, `Gun_NPC_Fire`, `Gun_NPC_Fire_Important`, `Grenades_SP`, `Bullet_Impacts`, `Bullet_Impacts_SP`, `v_destruction`, `Physics` | 3 | Detector |
| `Explosions_SP` | 2 | Detector |
| `Explosions` | 0 | Detector |
| `Explosions` | 1 | Clamp |
| `Effect_Bus_SP`, `Ambiences`, `Community`, `Consumables`, `Devices`, `Enemies`, `Foley`, `Locomotion`, `Locomotion_Additional`, `Locomotion_Player`, `Perks`, `Quest`, `VO_Quest`, `Vehicles`, `Vehicles_Suspensions`, `Weapons` | 3 | Clamp |
| `Music_Dgtc_Car_Hyper_INT` and `_EXT`, likewise `Lowend`, `Muscle`, `Sports`, `Suv`, `Truck` | 3 | Clamp |
| `VO_V`, `VO_V_Onos` | 3 | V's body path |

The plug-in is company 173, plug-in `0x4853`.

### For other mods using the headset

`src/headset_api.h` says what's offered: find `Headset_GetApi` in `Headset.dll`, and carry on without it if it isn't there.
NightCoop Voice hands it nearby voices, so partners near you are heard the way the world is.

### Tuning

The plugin writes `%LOCALAPPDATA%\Headset\tuning.ini` with every setting it reads, its starting value, and what it does, all commented out, and reads the file again within a second of saving.
Take the `#` off a line to change that setting, and put it back to return to the starting value.
A file an older version wrote with live values is moved aside as `tuning.old.ini`, so a new starting value reaches everyone.

### Building and testing

The commands for building, testing, checking the scripts, and installing are in [CLAUDE.md](CLAUDE.md#building-and-installing).
`headset_test` checks the bank, the plug-in interface, and the sound without the game.
RED4ext.SDK comes from the repository's `deps` folder, which `tools/fetch-red4ext-sdk.ps1` at the root fills.
The wheel's slices are a texture in `game/archive/headset/headset_wheel.archive`, redrawn by `python -I tools/make_wheel_art.py`, which needs WolvenKit's command line.

### How the crew gets it

A build installed on xip's PC reaches the crew through Choom Collector's Mods tab.
Releases for everyone else come from release-please, as the repository's [README.md](../../README.md#releases) describes.
