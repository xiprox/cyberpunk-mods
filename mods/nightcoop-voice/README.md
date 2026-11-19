![Voice's corner display: your mic live, your radio on air, and three players nearby, on the radio, and on the Relay](header.png)

# NightCoop Proximity Voice + Radio

Adds proximity voice chat and a group radio to NightCoop, inside the game, with no voice app to run beside it.

- **Nearby voices** come from where your partners stand, fade with distance, and are muffled by walls, doors, and shut cars, while an open window or door lets them through.
- **Rooms echo:** a voice rings in a tunnel, sounds close in a closet, and carries the echo of the room it comes from.
- **The radio** reaches everyone at any distance, with the grit of a military radio.
- **Levels set themselves:** every mic evens itself out, so nobody has to ask anyone to turn up.

## Using it

Your mic is live as soon as a session starts, and a voice gate decides when you're speaking.

- **Mouse 4** mutes your mic.
- **Mouse 5** is the radio mic: tap it to leave it on or off, or hold it to talk and it goes off when you let go.
  While it's on, everyone hears you on the radio, close by too.
  NightCoop's co-op menu also switches it.

Both keys and every other setting are under Mods > Voice in the main menu or the pause menu.
On speakers, switch off Headphones there, since voices are placed around your head for headphones.

## Direct and Relay

Voice travels one of two ways: directly between players, or through the host over NightCoop, called the Relay.

**Direct** sends your voice straight from your PC to each other player's PC over the internet, which is the quickest way.
To connect, the two PCs have to reach each other through their home routers, and some routers and internet providers don't allow that, so a direct connection takes a moment to set up and sometimes can't be made at all.

**The Relay** sends your voice along the connection NightCoop already uses for the game, through the host's PC.
It works whenever you can play together, but it's a detour: two players far from the host hear each other later, and since it travels with the game's own messages, it stops during loading screens.

Voice uses the Relay only while a direct connection is setting up, or when one can't be made, and the voice display shows "Relay" after a player's name while their voice comes that way.
Under Mods > Voice > Connection, **Always** uses the Relay with everyone instead.

## What it needs

RED4ext, redscript, Cyber Engine Tweaks, Codeware, and Native Settings, on Cyberpunk 2077 2.5.
Everyone in the session needs the mod, on the same version.

## Installing

Extract the zip into the game folder, or install it with your mod manager.
To remove it, delete `red4ext/plugins/NightCoopVoice` and `bin/x64/plugins/cyber_engine_tweaks/mods/NightCoopVoice`.

## Compatibility

- **Headset:** with [Headset](https://www.nexusmods.com/cyberpunk2077/mods/38448) installed, voices around you go through it like the rest of the world, and the radio plays inside it.
- **Linux:** runs under Proton.

## Known limits

Cars with models of their own, added by other mods, count as shut, windows and all.

## Bug reports

Close the game and attach the newest `red4ext/logs/nightcoopvoice-*.log` and `red4ext/plugins/NightCoop/nightcoop.log` from the game folder.

## For developers

### How it works

| Part | Where | Does |
|---|---|---|
| Engine | `src/` | Mic chain, Opus, encrypted links, jitter buffer, mixer, effects, all on its own threads |
| Game glue | `src/plugin/` | NightCoop session events, setup messages and the Relay, script functions, keys |
| Acoustics | `src/audio/acoustics.cpp` | Decides which rays to cast and what the answers mean, with no game in it, so the test program can stand in for the world |
| HUD and positions | `game/scripts/` | Reads positions and casts the rays it's asked for each frame, draws the corner display |
| Settings | `game/cet/` | The Voice section, through Native Settings |

NightCoop's SDK carries link setup, with each player's addresses, over a reliable channel, and a key the host makes per session in shared state.
The host could read that key, as it can all mod data in a session (read in `vendor/nightcoop-sdk/SECURITY.md`: the host decrypts and relays guests' messages).

The Relay is the path through NightCoop: the same encrypted packets as the direct links, two 20 ms frames to an unreliable message on a second channel, sent on the game thread, where the SDK has to be called.
Each game picks a path per partner for itself and takes both at all times, so a switch needs nothing agreed, and sequence numbers run on across it.
Each player's presence, a small message with their mute, radio mic, and room, goes the same way once a second, so all of that and the ping work on either path; the ping is then the Relay's real round trip.
NightCoop allows 120 messages and 32,768 bytes a second per mod (read in `nightcoop_sdk.h`, `NCSDK_RATE_MESSAGES_PER_S` and `NCSDK_RATE_BYTES_PER_S`): two frames a message fit four partners on the Relay at once, so past that a message carries three.
When NightCoop refuses a message for its rate, its frames are dropped, never retried, and messages carry a frame more for a while.
On Always, a player tells partners in their presence, so they stop trying direct with them.
`relay:` lines in NightCoop's log count what went each way every 30 s.

A player's mod list can fail to register on another machine: on one join, Bleack's NightCoop never registered Bossun's, for any mod, so Bleack never answered Bossun's link offers, and the cause inside NightCoop is unknown (measured in the crew's logs, [RECORD.md](RECORD.md), 2026-11-03).
So while some player has no link, or no word of their mods, the mod registers and unregisters a throwaway mod, which makes NightCoop send its list again, first after `ResendSchedule::kFirstMs` and then less and less often (`src/net/resend.hpp`).

Settings are stored per PC in `%LOCALAPPDATA%\NightCoopVoice\settings.ini`, so sharing the mod folder doesn't share them.
NightCoop's co-op menu also has a mute item and a radio mic item on its Mods page.
[RECORD.md](RECORD.md) says why each part is the way it is.

### How it sounds

- **Nearby:** full volume within `kNearMeters`, then falling on the curve in `RolloffGain` (`src/audio/spatial.cpp`) and fading to silent at `kFarMeters` (`src/audio/acoustics.cpp`).
  In headphones, the far ear hears a voice a moment later and with less treble, and voices behind you lose treble too.
  A talker with their back to you sounds duller and a little quieter.
  Voices nearly die when you dive underwater, and turn dull and roomy in any slow motion.
- **Walls and doors:** five rays, spread across and up and down, so a ledge or door frame muffles partly.
  A closed door counts as a thin barrier, glass stops less than a wall, and grates, catwalks, and foliage hardly anything.
- **Corners:** when walls are in the way, the voice also comes around them if there's a way, found from where either player has recently walked or by searching for a single corner nobody has walked.
  That part comes from the first bend you can see, with its distance measured along the route, less treble per corner, and more muffling for a closed door on the way.
  It comes through the wall as well, and the two add up, so it can't flip between them.
- **Rooms and echoes:** rays around you measure the space you're in.
  A balcony or anywhere else with no roof over one side lets sound out instead of ringing, and so does a low wall, while carpet, fabric, upholstery, grass, and the like shorten the ring.
  Walls far enough off and big enough give real echoes, from their own direction, up to four per talker.
  A voice through a wall brings the sound of the room it's in, as that player's own rays measured it.
  In headphones you also hear your own voice in a closed room that rings long enough, never directly, and not underwater or in a car (`src/audio/mixer.cpp`).
- **Cars:** riders in one vehicle hear each other clean.
  Between the inside of a shut car and anywhere else, a voice is muffled to a murmur that holds to `kCabinFadeFromMeters` and fades out by `kCabinReachMeters` (`src/audio/spatial.hpp`).
  A window wound down or shot out, an open or torn-off door, and the missing roof of a cabrio or targa let voices through, and a voice through a gap seems to come from it.
  Seated players' voices come from their heads, and bikes block nothing.
  Each player's game reports what's open on the car they sit in, and where the gaps are comes from each car's parts and a table of their meshes made from the game files by `tools/car_openings.py`, rerun after a game patch.
- **Radio:** only the player switches their radio mic: a tap leaves it on or off, a hold of `RadioMic::kHoldToTalkMs` or more talks and goes off when let go, and the co-op menu's item toggles it (`src/audio/spatial.hpp`).
  Each session starts with it off.
  What's said for `RadioMic::kTailMs` after it goes off still goes on the radio, so a last word isn't cut off.
  Their radio plays for every partner at any distance, close by and in a vehicle you share too, on top of their nearby voice.
- **Levels:** each mic evens itself out with an automatic gain, which remembers each mic between runs, and a compressor.
  The mod measures what the output plays, takes away its own voices, and sets one gain for all voices, so the game's Master Volume and the system volume don't matter.
  Where the output can't be measured, voices follow the Master Volume setting alone.
  Every 30 s NightCoop's log gets `levels:` lines with the real numbers, `rays:` lines with what the rays cost, and an `acoustics:` line with the measured room and how ways round were found.

### For other mods

`src/engine.hpp` is the boundary to reuse if another mod needs direct links.
Voice uses Headset's interface, `../headset/src/headset_api.h`, to hand it nearby voices, and plays plain without it.

### Building and testing

It needs Visual Studio and CMake 3.25 or newer.
From a fresh clone, `powershell -File tools/stage.ps1 -Out build/stage` fetches the libraries into `deps/` at pinned versions and RED4ext.SDK with `../../tools/fetch-red4ext-sdk.ps1`, then configures, builds, and tests.
After that, [CLAUDE.md](CLAUDE.md#building-and-installing) has the commands to rebuild, test, check the scripts, and install.

`build/Release/voice_test.exe` checks everything that doesn't need the game, and plays only silence, never storing or sending microphone audio:

- effects, by their measured output
- rooms, corners, and echoes, in a made-up world of boxes
- packets and the jitter buffer
- real links between two engines on one PC
- the Relay, over a fake NightCoop channel with its rate limit
- the audio devices, unless it's given `--no-devices`

Two tools try a headset-style clamp on the game's sound, outside the game and not part of the mod:

- `build/Release/record_game.exe` records what the default output plays into `recordings/`.
  Page Up starts and stops it, with two rising beeps for recording and two falling ones for stopped, neither recorded, and while it runs the game doesn't get Page Up.
- `build/Release/headset_clamp.exe <recording.wav>` writes `-limiter`, `-headset`, `-headset2`, and `-headset3` versions next to the recording, at the same level, to compare by ear.
  `--at <dB>` sets one clamp level for every recording.

### How the crew gets it

A build installed on xip's PC reaches the crew through Choom Collector's Mods tab.
Releases for everyone else come from release-please, as the repository's [README.md](../../README.md#releases) describes.
