# Cyberpunk 2077 mods

Each folder in `mods/` is its own mod project; read its CLAUDE.md, README.md and RECORD.md first. This file holds what all of them share.

## A mod's own files

- A new mod starts with these, without being asked:
  - `README.md`: what it does for a player, and how it's built, installed and shared with the crew.
  - `RECORD.md`: what we found and decided, newest entry first, each entry under a `## <YYYY-MM-DD>: <what changed>` heading. "User" marks what the user saw or heard in the game. Its top keeps an "Installed" line and a "Not yet checked in the game" line current. Add an entry when a finding or decision changes how the mod works.
  - `CLAUDE.md`, once the mod has rules of its own: its build and test commands, what must stay in step in its code, and its commit scopes. What this file says isn't repeated there.

## The game and the crew

- The game is in `C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077` (2.5, with Cyber Engine Tweaks, Codeware, TweakXL, ArchiveXL, RED4ext and NightCoop). Look game APIs up before using them: `<game>\tools\redmod\scripts`, and Codeware's `Scripts\Codeware.Global.reds`.
- The crew: `xip` is the user, on this PC. Bossun's log folder is `Bobson` (an older one `bossun`), his NightCoop name is `B`, and his clock is 7 h behind; he hosts from North America. Bleack runs Linux (CachyOS, GOG), clock 1 h ahead.
- For anything in the game, read the logs first. The user's log collector is Choom Collector (`C:\Users\wayne\dev\tools\choom-collector`, a rewrite of CP77 Log Collector), which writes one folder per session with a folder per player inside: `C:\Users\wayne\Documents\Choom Collector Logs\<YYYY-MM-DD> <code>\<player>`. Logs from before the switch (2026-11-13) stay in the old app's `C:\Users\wayne\Documents\CP77 Collected Logs\<player>`, with no session level. In a player's folder, NightCoop's log is at `game\red4ext\plugins\NightCoop\nightcoop.log` and its crashes in `nightcoop-crash.log`.
- The crew gets mods through the collector's Mods tab: it shares folders only, from a fixed list of places, so an archive goes in a folder of its own inside `archive\pc\mod` (the game loads it from there). Don't change either collector's code unless plainly asked.

## While the game runs

- Never install while the game runs, and never close it without being asked. While the user is testing in the game, edit code only and wait for "install and restart".
- Running the game unattended needs the user's permission for that day. The game takes keys only while its window is in front, and the loading screen after a save waits for one, so an automated run needs the game in front after the save loads; the user keeps it there.
- After CET's Reload All Mods, NightCoop's hooks are gone until a restart, so restart before judging co-op behaviour.

## Lessons that cost a crash or an evening

- **Redscript calls' results:** never index one (`f(x)[n]`) or pass one straight to an `Array*` function (`ArraySize(f(x))`, `ArrayFindFirst(f(x), …)`); put it in a local first. The script machine treats the argument as an address, which crashed the game (vehicle customizer, 2026-11-06).
- **Codeware natives:** don't pass a `script_ref` parameter straight to one. That corrupted the game's allocator and crashed all three players (NightCoop Voice 0.3.0).
- **NightCoop's SDK, game thread only:** call it only from `NightCoopSdk.ListenFrame` (every frame) and `Listen` (events). DelaySystem callbacks and a Codeware popup's clicks and refreshes aren't reliably on the game thread, and NightCoop refuses such calls as -2 (NotNow), logging "a mod called a game-thread function of the SDK from another thread". Before reading a -2 as "not now", look for that line. From anywhere else, queue the write for the next frame (vehicle customizer, 2026-11-07).
- **NightCoop's SDK, docs and protocol:** its docs are in `vendor/nightcoop-sdk/docs` (start with `concepts.md`), and `vendor/nightcoop-sdk/include/nightcoop_sdk.h` is the source of truth. Mod data passes only between players with the same protocol number, so raising it means everyone updates together.
- **Vehicles in NightCoop:** players' vehicles of one TweakDB record become one car in a session. That's why `nazare-racer-coop` and the vehicle customizer's copies exist.

## Tools

- Parse Lua with `luajit -bl <file>` after changing it; only the game runs it.
- Run Python that reads game files with `-I`.
- WolvenKit 9.1.0 is at `H:\WolvenKit`, its command line at `H:\WolvenKit\Console\WolvenKit.CLI.exe`.
- `tools/` holds what more than one mod uses or what isn't about any one mod: `check-scripts.ps1 -Mod <mod>`, `ncre.py`, `fetch-red4ext-sdk.ps1`, and the game-file readers `rdar.py` (archives, with the game's own Oodle) and `pkg.py` (CR2W files and the packages cooked into them), which a script imports by putting `tools/` on `sys.path`. A mod's own tools stay in its `tools/` folder, and a tool moves here when a second mod needs it.
- `deps/` holds libraries the mods share, fetched and out of git; `vendor/` is third-party code that is in git. RED4ext.SDK is in `deps/`, pinned in `tools/fetch-red4ext-sdk.ps1`; raise the pin after a game patch that changes its types.

## The repo

- This folder is one git repo for all the mods, private on GitHub as `xiprox/cyberpunk-mods`. Claude commits and pushes only when asked, and proposes every commit's title and description first.
- The mods in `release-please-config.json` are released from here (README). Don't edit their `version.txt`, their `CHANGELOG.md` or `.release-please-manifest.json` by hand, and keep each commit to one mod's folder, since release-please goes by the files a commit touches. Each mod's CLAUDE.md has its commit rules; changes to the repo itself use the scope `repo`.
- Mods moved into `mods/` and the SDK into `vendor/` on 2026-11-08, so older RECORD.md entries name the old paths.
- Build output, zips, test-run pictures, recordings and dumps of game files stay on disk but out of git. The vehicle customizer's scouting pictures are in git, and so are the reports of the test runs its RECORD.md cites.

## Compacting

- When the user says "let's compact", reply with the instructions for the compaction in one code block, saying what to keep, without the `/compact` itself, so they can copy and paste it.
