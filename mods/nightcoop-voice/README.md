# NightCoop Voice

Voice chat inside NightCoop sessions: nearby voices that follow distance, direction, walls and cars, plus a group radio. Audio goes directly between players when it can, and over NightCoop, through its host, when it can't (the Relay). [RECORD.md](RECORD.md) says why it's built the way it is.

## Install

Every player needs the same files, and RED4ext, Codeware, CET, Native Settings and NightCoop 0.2.0 or newer. Unzip `dist/NightCoopVoice-<version>.zip` into the game folder. To remove the mod, delete `red4ext/plugins/NightCoopVoice` and `bin/x64/plugins/cyber_engine_tweaks/mods/NightCoopVoice`.
Versions only talk to the same protocol: 0.8.0 and newer can't hear 0.7.x or older, so everyone updates together.

## How it plays

Nothing needs pressing to talk. Links connect when a session starts, and your mic is live from then on, with a voice gate deciding when you're speaking.

| Control | What it does |
|---|---|
| Mute (default mouse side button 1) | Silences your mic everywhere |
| Radio mic (default mouse side button 2) | Tap: on or off. Hold: on until you let go |

- **Nearby:** full volume within 2 m, then falling more evenly than speech really does, about 9 dB down at 15 m and 21 dB at 40 m, then fading to silent at 50 m. In headphones, voices sit around your head: the far ear hears them a moment later and with less treble, and voices behind you lose treble too. On speakers, turn off Headphones in Settings for a plain pan. A talker with their back to you sounds duller and a little quieter. Voices nearly die when you dive underwater, and turn dull and roomy in any slow motion.
- **Walls and doors:** five rays, spread across and up and down, so a ledge or door frame muffles partly. A closed door counts as a thin barrier. Glass stops less than a wall, and grates, catwalks and foliage hardly anything. Give `TraceResult.GetHitEntity` a local variable, never a `script_ref` parameter passed along: that form crashed all three players in 0.3.0.
- **Corners:** when walls are in the way, the voice also comes round them if there's a way. It finds one from where either player has recently walked, which covers several corners, or by searching for a single corner nobody has walked. The voice then comes from the first bend you can see, with its distance measured along the route, less treble per corner, and more muffling for a closed door on the way. Otherwise it comes through the wall. Both add up, so it can't flip between the two.
- **Rooms and echoes:** rays around you measure the space you're in. A closet dies fast, a hall or tunnel rings, and open air gives back very little. A balcony or anywhere else with no roof over one side lets sound out instead of ringing, and so does a low wall. Carpet, fabric, upholstery, grass and the like shorten the ring. Across a closed room the voice falls away while the room's sound doesn't. Walls far enough off and big enough give real echoes, from their own direction, up to four per talker. Posts, signs, stairs, low walls and soft surfaces don't. A voice through a wall brings the sound of the room it's in, as that player's own rays measured it. In headphones you also hear your own voice in the room, never directly, only somewhere closed in that rings for more than about half a second, and not underwater or in a car.
- **Cars:** riders in one vehicle hear each other clean. Between the inside of a shut car and anywhere else, a voice is muffled to a murmur: you can tell someone is talking, though hardly what they say. It holds to 3 m and fades out by 5 m, past which nothing gets through. A car's gaps let voices through: a window wound down or shot out, an open or torn-off door, and the missing roof of a cabrio or targa. Through a gap a voice seems to come from it, sounds nearly as in the open in line with it and duller round the car, and a small pane lets through less than a window; two cars side by side talk window to window. Seated players' voices come from their heads. Bikes block nothing. Each player's game reports what's open on the car they sit in. Where the gaps are comes from each car's parts and a table of their meshes made from the game files (`tools/car_openings.py`, rerun after a game patch); a mod's car whose glass isn't in it stays shut.
- **Radio:** everyone hears it, at any distance, through walls and cars. Only players with their radio mic on are sent over it. A partner who left theirs on from further off is left to the air within 15 m, so you don't hear them twice, and comes back on the radio past 25 m. Walls don't count, so someone close in the next room is heard muffled. Switching the radio on within 25 m of someone means it: they hear you on it until you've been more than 25 m apart for 30 s, so a dash across a fight doesn't end it, except while you share a vehicle, where you hear each other clean anyway. Nobody is left to the air while one of you is on or in a vehicle you aren't sharing, or while you wear the Headset mod in either mode, since putting it on means you want the radio. It has the grit of a military radio's digital voice encoding. It plays in both ears, from the headset's ear cups.
- **Headset:** with the separate Headset mod (`mods/headset`), nearby voices are heard through it just as the world is, so a blast swallows a shout beside you, and noise cancelling quiets the people around you. The radio plays inside it, and turning it on never changes the headset's mode. Without the Headset mod, voice plays plain.
- **Relay:** with no direct link to a partner, including the moment one takes to connect, voice goes to them over NightCoop instead, and back to direct once the link is up. Settings, Connection, Relay: When needed (the default), or Always, which makes no direct links at all, for every pair that includes you. Packing two frames a message adds 20 ms, waiting for game frames a little more, and a guest's voice to another guest goes by way of the host, so two players in Europe with a host in North America hear each other a few hundred ms later (an estimate). It only moves while the games run frames, so loading screens cut it. The HUD shows "Bleack - Relay", and "Bleack - nearby, Relay" while they talk.

Levels set themselves. Each mic evens itself out with an automatic gain, which remembers each mic between runs, and a compressor, so speech leaves every player at about the same level. Each listener's voices then keep their balance with that player's game: the mod measures what the output plays, takes away its own voices, and sets one gain for all voices, so the game's Master Volume and the system volume don't matter. Voices rise when a fight starts and settle slowly afterwards. Nearby gunfire can still drown them out, on purpose. Where the output can't be measured, voices follow the Master Volume setting alone. Every 30 s NightCoop's log gets `levels:` lines with the real numbers, `rays:` lines with what the rays cost, and an `acoustics:` line with the measured room and how ways round were found.

Settings are in the game's Settings menu under Mods, Voice. They're stored per PC in `%LOCALAPPDATA%\NightCoopVoice\settings.ini`, so sharing the mod folder doesn't share them. The co-op menu's Mods page also has mute and radio items.

## How it's built

| Part | Where | Does |
|---|---|---|
| Engine | `src/` | Mic chain, Opus, encrypted links, jitter buffer, mixer, effects, all on its own threads |
| Game glue | `src/plugin/` | NightCoop session events, setup messages and the Relay, script functions, keys |
| Acoustics | `src/audio/acoustics.cpp` | Decides which rays to cast and what the answers mean, with no game in it, so the test program can stand in for the world |
| HUD and positions | `game/scripts/` | Reads positions and casts the rays it's asked for each frame, draws the corner display |
| Settings | `game/cet/` | The Voice section, through Native Settings |

NightCoop's SDK carries setup, addresses over a reliable channel, and a key the host makes per session in shared state. The host could read that key, as it can all SDK data.
It also carries the Relay: the same encrypted packets as the direct links, two 20 ms frames to an unreliable message on a second channel, sent on the game thread, where the SDK has to be called. Each game picks a path per partner for itself and takes both at all times, so a switch needs nothing agreed, and sequence numbers run on across it. Presence goes the same way once a second, so mute, the radio mic, their room and the ping work on either path; the ping is then the Relay's real round trip. NightCoop allows 120 messages and 32768 bytes a second per mod: two frames a message fit four partners on the Relay at once, so past that a message carries three. When NightCoop refuses one for its rate, its frames are dropped, never retried, and messages carry a frame more for a while. On Always, a player tells partners in their presence, so they stop trying direct with them. `relay:` lines in NightCoop's log count what went each way every 30 s.

A player's mod list can fail to register on another machine: on one join, Bleack's NightCoop never registered Bossun's, for any mod, so Bleack never answered Bossun's link offers. So while a player is stuck, the mod re-sends its own list, by registering and unregistering a throwaway mod, which makes NightCoop send it again.

`src/engine.hpp` is the boundary to reuse if another mod ever needs direct links.

## Build

Needs Visual Studio 2022 and CMake.

```bash
powershell -File tools/fetch_deps.ps1
```

```bash
powershell -File ../../tools/fetch-red4ext-sdk.ps1
```

```bash
cmake -S . -B build -G "Visual Studio 17 2022" -A x64
```

```bash
cmake --build build --config Release
```

`build/Release/voice_test.exe` checks everything that doesn't need the game: effects by their measured output, rooms, corners and echoes in a made-up world of boxes, packets, the jitter buffer, real links between two engines on one PC, the Relay over a fake NightCoop channel with its rate limit, and the audio devices. It plays only silence, and never stores or sends microphone audio.

Two tools for trying a headset-style clamp on the game's sound, outside the game and not part of the mod:
- `build/Release/record_game.exe` records what the default output plays into `recordings/`. Page Up starts and stops it, with two rising beeps for recording and two falling ones for stopped, neither recorded. While it runs, the game doesn't get Page Up.
- `build/Release/headset_clamp.exe <recording.wav>` writes `-limiter` and `-headset` versions next to the recording, at the same level, to compare by ear. `--at <dB>` sets one clamp level for every recording.
