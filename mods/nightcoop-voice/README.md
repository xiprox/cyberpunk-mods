# NightCoop Voice

Voice chat inside NightCoop sessions: nearby voices that follow distance, direction, walls and cars, plus a group radio. Audio goes directly between players, not through NightCoop or its host. [RECORD.md](RECORD.md) says why it's built the way it is.

## Install

Every player needs the same files, and RED4ext, Codeware, CET, Native Settings and NightCoop 0.2.0 or newer. Unzip `dist/NightCoopVoice-<version>.zip` into the game folder. To remove the mod, delete `red4ext/plugins/NightCoopVoice` and `bin/x64/plugins/cyber_engine_tweaks/mods/NightCoopVoice`.

## How it plays

Nothing needs pressing to talk. Links connect when a session starts, and your mic is live from then on, with a voice gate deciding when you're speaking.

| Control | What it does |
|---|---|
| Mute (default mouse side button 1) | Silences your mic everywhere |
| Radio mic (default mouse side button 2) | Tap: on or off. Hold: on until you let go |

- **Nearby:** full volume within 2 m, then falling close to how speech really does, about 6 dB per doubling of distance, to silent at 40 m. For now, Settings has a temporary Distance falloff (test) choice to compare gentler curves by ear. In headphones, voices sit around your head: the far ear hears them a moment later and with less treble, and voices behind you lose treble too. On speakers, turn off Headphones in Settings for a plain pan. A talker with their back to you sounds duller and a little quieter. Voices nearly die when you dive underwater, and turn dull and roomy in any slow motion.
- **Walls and doors:** five rays, spread across and up and down, so a ledge or door frame muffles partly. A closed door counts as a thin barrier. Glass stops less than a wall, and grates, catwalks and foliage hardly anything. Give `TraceResult.GetHitEntity` a local variable, never a `script_ref` parameter passed along: that form crashed all three players in 0.3.0.
- **Corners:** when walls are in the way, the voice also comes round them if there's a way. It finds one from where either player has recently walked, which covers several corners, or by searching for a single corner nobody has walked. The voice then comes from the first bend you can see, with its distance measured along the route, less treble per corner, and more muffling for a closed door on the way. Otherwise it comes through the wall. Both add up, so it can't flip between the two.
- **Rooms and echoes:** rays around you measure the space you're in. A closet dies fast, a hall or tunnel rings, and open air gives back very little. A balcony or anywhere else with no roof over one side lets sound out instead of ringing, and so does a low wall. Carpet, fabric, upholstery, grass and the like shorten the ring. Across a closed room the voice falls away while the room's sound doesn't. Walls far enough off and big enough give real echoes, from their own direction, up to four per talker. Posts, signs, stairs, low walls and soft surfaces don't. A voice through a wall brings the sound of the room it's in, as that player's own rays measured it. In headphones you also hear your own voice in the room, never directly, only somewhere closed in that rings for more than about half a second, and not underwater or in a car.
- **Cars:** riders in one vehicle hear each other clean. Between the inside of a car and anywhere else, voices are heavily muffled within 5 m and silent past that. Bikes block nothing.
- **Radio:** everyone always hears it, at any distance, through walls and cars. Only players with their radio mic on are sent over it. It has the grit of a military radio's digital voice encoding. In headphones it plays from an earpiece in the left or right ear, or in both, as chosen in Settings. With Headphones off it always plays in both ears.

Levels set themselves. Each mic evens itself out with an automatic gain, which remembers each mic between runs, and a compressor, so speech leaves every player at about the same level. Each listener's voices then keep their balance with that player's game: the mod measures what the output plays, takes away its own voices, and sets one gain for all voices, so the game's Master Volume and the system volume don't matter. Voices rise when a fight starts and settle slowly afterwards. Nearby gunfire can still drown them out, on purpose. Where the output can't be measured, voices follow the Master Volume setting alone. Every 30 s NightCoop's log gets `levels:` lines with the real numbers, `rays:` lines with what the rays cost, and an `acoustics:` line with the measured room and how ways round were found.

Settings are in the game's Settings menu under Mods, Voice. They're stored per PC in `%LOCALAPPDATA%\NightCoopVoice\settings.ini`, so sharing the mod folder doesn't share them. The co-op menu's Mods page also has mute and radio items.

## How it's built

| Part | Where | Does |
|---|---|---|
| Engine | `src/` | Mic chain, Opus, encrypted links, jitter buffer, mixer, effects, all on its own threads |
| Game glue | `src/plugin/` | NightCoop session events and setup messages, script functions, keys |
| Acoustics | `src/audio/acoustics.cpp` | Decides which rays to cast and what the answers mean, with no game in it, so the test program can stand in for the world |
| HUD and positions | `game/scripts/` | Reads positions and casts the rays it's asked for each frame, draws the corner display |
| Settings | `game/cet/` | The Voice section, through Native Settings |

NightCoop's SDK carries only setup: addresses over a reliable channel, and a key the host makes per session in shared state. There is deliberately no voice fallback: a pair that can't connect stays silent, shows it on the HUD and keeps retrying. The host could read that key, as it can all SDK data.

A player's mod list can fail to register on another machine: on one join, Bleack's NightCoop never registered Bossun's, for any mod, so Bleack never answered Bossun's link offers. So while a player is stuck, the mod re-sends its own list, by registering and unregistering a throwaway mod, which makes NightCoop send it again.

`src/engine.hpp` is the boundary to reuse if another mod ever needs direct links.

## Build

Needs Visual Studio 2022 and CMake.

```bash
powershell -File tools/fetch_deps.ps1
```

```bash
cmake -S . -B build -G "Visual Studio 17 2022" -A x64 -DRED4EXT_SDK_DIR=<short path to RED4ext.SDK>
```

```bash
cmake --build build --config Release
```

`build/Release/voice_test.exe` checks everything that doesn't need the game: effects by their measured output, rooms, corners and echoes in a made-up world of boxes, packets, the jitter buffer, real links between two engines on one PC, and the audio devices. It plays only silence, and never stores or sends microphone audio.
