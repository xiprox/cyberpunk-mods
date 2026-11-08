# NightCoop Voice

Co-op voice for Cyberpunk 2077 on the NightCoop mod; [README.md](README.md) says what it does and how it's built.
`RECORD.md` holds what we found and decided, newest entry first; add an entry when a finding or decision changes how the mod works, and keep its "Installed" and "Not yet checked in the game" lines current.

- The user approves a design before any building starts. Realism beats clarity, and nobody should have to adjust levels, so no volume or distance sliders.
- Say what went untested in the game. Tests measure the sound but can't judge it: only the user's ears can, so don't call something fixed until they've heard it.
- Read the logs first for anything in-game: `C:\Users\wayne\Documents\CP77 Collected Logs\<player>\game\red4ext\plugins\NightCoop\nightcoop.log`. `xip` is the user, `Bobson` is Bossun (clock 7 h behind), `Bleack` (clock 1 h ahead). Look for `levels:`, `rays:`, `acoustics:`, `tuning:`, `time:`, `relay:` and `headset:` lines.

## Building and installing

```bash
cmake --build build --config Release --target voice_test NightCoopVoice -- /m /v:minimal /nologo
```

```bash
build/Release/voice_test.exe
```

```bash
powershell -File ../../tools/check-scripts.ps1 -Mod nightcoop-voice
```

```bash
cmake --install build --config Release --prefix build/stage
```

- While the user is testing and tweaking in game, edit code only, and build, test, package and install when they say so ("install and restart"). Levels can still change live through `tuning.ini` (RECORD.md).
- While the game runs, never install, and never close it without being asked. Pass `--no-devices` to `voice_test`. `check-scripts.ps1` runs on a hidden desktop so a compile error's dialog can't appear over the game; don't run `scc` any other way then.
- Zip `build/stage` to `dist/NightCoopVoice-<version>.zip`. Install by copying `build/stage` over the game folder, then compare file hashes. Installing on the user's PC is how updates reach the others, through their log collector.
- Raise `VERSION` in `CMakeLists.txt` before packing a build that differs from one already installed, so logs say which build ran. Raise `kProtocol` in `src/plugin/main.cpp` when packets or setup messages change meaning: all players then need the new version.

## In the code

- Natives in `src/plugin/main.cpp` and their declarations in `game/scripts/NightCoopVoiceNative.reds` must match and ship together.
- The `Deref` copy in `game/scripts/NightCoopVoiceDoors.reds` must stay: without it Codeware corrupts the game's allocator, which crashed all three players in 0.3.0. Don't pass a `script_ref` parameter straight to any Codeware native.
- `near` and `far` are Windows macros; don't use them as names in anything that includes `windows.h`.
- Ray geometry lives in `src/audio/acoustics.cpp` with no game in it. Add a fake room to `voice_test.cpp` for each spot that sounded wrong, named after the spot.
- A partner's nearby voice is only sent by straight-line distance and cars (`ShouldSendNearby`). Keep walls, corners and facing out of that, since they differ on each machine.

## Commits

A git repo since 0.4.6 (2026-11-07). Earlier versions exist only as zips in `dist/`, which stays out of git with `build/` and `deps/` (`tools/fetch_deps.ps1` fills `deps/`).
Conventional Commits, with a scope a player recognizes (`relay`, `radio`, `acoustics`, `falloff`), never a file or a layer.
The title says what the player gets, not what the code does; the description says why, and what went unchecked in the game.
One change per commit.

Claude commits only when asked, and proposes every commit's title and description in the reply first, for the user to approve or change.
