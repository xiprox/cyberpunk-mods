# Headset

A headset for Cyberpunk 2077 with three modes, always on your head:

- **Passthrough:** as if it weren't there.
- **Active Hearing Protection** (level-dependent hearing protection): you hear the world through its outside microphones, a little thinner. The moment a gun or a blast goes off they're turned down, the way a tactical headset's electronics clamp a bang, and you get only what comes through the cups, a muffled thump. Then the world comes back. People talking, engines and the car radio can't set it off.
- **Active Noise Cancellation:** the world is shut out, a car's radio included. A bang is too sudden for it to cancel, so a shot hits harder than in hearing protection.

It runs inside the game's own audio engine, Wwise, as an effect on the game's sound buses, so it knows what each sound is before the sounds are mixed together. It needs no co-op mod.

Requires RED4ext, redscript, Cyber Engine Tweaks, Codeware and Native Settings.

Made for game version 2.5. If a patch changes the game's Wwise, the headset turns itself off until the mod is updated, and `red4ext/logs/headset-*.log` says so.

## The headset key

`,` by default, set under the game's Settings menu, Headset.

- **Tap:** the next mode: Passthrough, Active Noise Cancellation, Active Hearing Protection, and round again. A sound confirms which you landed on, and a small headphones icon on the HUD, under the health bar, shows the mode whenever it isn't Passthrough.
- **Hold:** a wheel opens, three equal slices in the style of the game's own: Active Noise Cancellation top left, Active Hearing Protection top right, Passthrough at the bottom. Move the mouse and let go to pick. Time slows in singleplayer; in co-op it doesn't, so pick a safe moment.

The slices are a small texture in `game/archive/headset/headset_wheel.archive`, redrawn by `python -I tools/make_wheel_art.py`, which needs WolvenKit's command line.

## What it listens to, and what it turns down

**Can set it off:** your gun, NPC guns, grenades, explosions, bullet impacts, vehicle destruction and heavy physics. Each is read from its own bus, with an estimate of how loud that really is, and the clamp starts at about 85 dB of real-world loudness.

**Gets turned down:** everything a headset's microphones would pick up: NPCs, including story characters talking to you in person, traffic, ambience, footsteps, your gun, reverb, music playing in the world and a car's radio.

**Left out:** UI, full-screen effects, slow-motion stingers, the score, the radio on a bike or in your pocket, and phone and Johnny's voices, which you'd hear through implants.

**V's own body:** while worn, V's lines, grunts and breathing come through a warm body path, and an air path that follows the microphones, so V goes "inside your head" during a bang and in noise cancelling. A loud bang drowns V's lines out for a moment, as it would you, so they're often lost during a firefight. V's grunts and breathing stay in dynamic clamping: with the chaos held down, you can feel yourself breathe. Your own footsteps thud through your body, your own gunshots gain low-end recoil, and other people's gunshots and explosions a thump in the chest.

## For other mods adding Wwise effects

A bus has four effect slots, and `SetBusEffect` silently replaces whatever is in the one it's given, so stay clear of these. The game's own effects take the low slots on many buses.

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

## For other mods using the headset

`src/headset_api.h` says what's offered: find `Headset_GetApi` in `Headset.dll` and carry on without it if it isn't there. NightCoop Voice hands it nearby voices to hear them as the world is heard.

## Tuning, for now

`%LOCALAPPDATA%\Headset\tuning.ini`, read within a second of saving. Lines like:

- `threshold_db=85`: the real-world loudness where the clamp starts.
- `depth_per_db=0.57`: how many dB the microphones come down for each dB over it.
- `deepest_db=40`: how far down they can go.
- `sound=1`: 0 leaves only the clamp, to compare.
- `leak_db=-10`: how much gets through the cups, muffled and never turned down.
- `recoil_db=9`: how much the lows of your own gunshots are raised; 0 is off.
- `thump_db=6`: the same for other people's gunshots and for explosions.
- `lift_under_db=-38`, `hiss_db=-64`, `width=0.75`: the talk-through's lift, hiss and narrowing.
- `body_db=5`, `air_floor_db=-60`, `air_open_db=-5`: V's lines; `grunt_body_db=8`, `grunt_floor_db=-60`, `grunt_open_db=-12`: V's grunts and breathing; `mask_db=-30`: how far the loudest bang drowns V out; `grunt_clamp_mask_db=0`, `grunt_body_hz=450`: grunts in dynamic clamping, and how dark they are; `footstep_db=6`: your own steps.
- `noise_low_db=-26`, `noise_mid_db=-18`, `noise_high_db=-28`: noise cancelling's three bands.
- `noise_bang_low_db=-8`, `noise_bang_mid_db=-12`, `noise_bang_high_db=-22`: the same during a bang, which it can't keep up with.
- `offset_Guns_Firing=150`: what a bus's level adds up to in real-world dB, one per bus by name.
- `always_worn=1`: hearing protection even in Passthrough.
- `wheel_flip_y=1`: swaps up and down on the wheel, if they turn out reversed.

## Building

```bash
cmake -S . -B build -G "Visual Studio 17 2022" -A x64
```

```bash
cmake --build build --config Release --target headset_test Headset
```

RED4ext.SDK comes from the repo's `deps` folder (`tools/fetch-red4ext-sdk.ps1`). `headset_test` checks the bank, the plug-in interface and the clamp without the game.
