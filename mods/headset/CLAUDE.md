# Headset

Hearing protection for Cyberpunk 2077, built inside the game's Wwise, usable in singleplayer and from NightCoop Voice; [README.md](README.md) says what it does.
`RECORD.md` holds what we found and decided, newest entry first; add an entry when a finding or decision changes how the mod works, and keep its "Installed" and "Not yet checked in the game" lines current.

- The user approves a design before any building starts. Realism beats clarity, and nobody should have to adjust levels.
- Say what went untested in the game. Tests measure the sound but can't judge it: only the user's ears can, so don't call something fixed until they've heard it.
- Logs are in the game's `red4ext/logs/headset-*.log`: `effect on`, `tuning:`, `headset on/off` and the 10-second `worn` lines, which give each bang bus's loudest reading.

## Building and installing

```bash
cmake --build build --config Release --target headset_test Headset -- /m /v:minimal /nologo
```

```bash
build/Release/headset_test.exe
```

```bash
powershell -File ../../tools/check-scripts.ps1 -Mod headset
```

```bash
cmake --install build --config Release --prefix build/stage
```

- While the user is testing and tweaking in game, edit code only, and build, test, package and install when they say so. Levels can still change live through `tuning.ini` (README).
- While the game runs, never install, and never close it without being asked.
- Zip `build/stage` to `dist/Headset-<version>.zip` with `tar -a -cf dist/Headset-<version>.zip -C build/stage archive bin red4ext`, so its paths have forward slashes for Linux. Install by copying `build/stage` over the game folder, then compare file hashes.
- `version.txt` and `CHANGELOG.md` change only through release-please's pull request. Test builds between releases keep the last release's number, and the log's `built` time says which build ran.
- Run the script check above before merging a release pull request: the release workflow builds and tests but can't compile redscript.

## In the code

- `src/wwise/ak.hpp` is Wwise's plug-in interface as the game's exe has it. There's no SDK here; the slots and offsets were read from the exe (RECORD.md). A game patch that changes the Wwise version needs them checked again, starting with the build number. The mod stays off on another build until `kBuildVersion` and `kMinBuildStamps` are updated.
- `src/wwise/places.hpp` is the only place that says which bus gets what, in which slot. Each slot is the highest one `init.bnk` leaves free on that bus; keep the README's table in step with it.
- Natives in `src/plugin/main.cpp` and their declarations in `game/scripts/HeadsetNative.reds` must match and ship together.
- Don't call into Wwise from its audio thread. Everything that does runs on the installer's own thread.

## Commits

Conventional Commits, with a scope a player recognizes (`clamp`, `settings`), never a file or a layer.
The title says what the player gets, not what the code does; the description says why, and what went unchecked in the game.
A `feat` or `fix` title goes into the changelog and the Nexus Mods notes as typed, so it's written as a release note: `feat` raises the minor version and `fix` the patch. `refactor`, `docs`, `test`, `ci` and `chore` stay out of the changelog and make no release, so anything a player wouldn't notice uses those.
One change per commit, inside this folder. Claude commits only when asked, and proposes every commit's title and description first.
