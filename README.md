# Cyberpunk 2077 mods

Various mods for Cyberpunk 2077, most of them for playing co-op on NightCoop.

| Name                                            | What                                                                           |
| ----------------------------------------------- | ------------------------------------------------------------------------------ |
| [`headset`](mods/headset)                       | Hearing protection and noise cancelling, in singleplayer or co-op              |
| [`nightcoop-voice`](mods/nightcoop-voice)       | Proximity and radio voice for NightCoop                                        |
| [`nightcoop-tweaks`](mods/nightcoop-tweaks)     | Fixes and small additions to NightCoop: sending money, bike animations, sfx... |
| [`vehicle-customizer`](mods/vehicle-customizer) | Customize cars and bikes, with NightCoop support                               |
| [`passenger-radio`](mods/passenger-radio)       | Set radio from the passenger seat                                              |
| [`no-carry-weight`](mods/no-carry-weight)       | Adds 1000 carry capacity                                                       |

## Shared tools

Compile a mod's redscript without touching the game, safe while it runs:

```bash
powershell -File tools/check-scripts.ps1 -Mod nightcoop-voice
```

```bash
powershell -File tools/check-scripts.ps1 -Mod vehicle-customizer
```

Read NightCoop's DLL for its natives (`disasm` first; needs `llvm-objdump`):

```bash
python -I tools/ncre.py --help
```

Fetch RED4ext.SDK into `deps/`, at the commit the plugins are built against:

```bash
powershell -File tools/fetch-red4ext-sdk.ps1
```

Zip a released mod as its release would, into the mod's `build/package`:

```bash
powershell -File tools/package-mod.ps1 -Mod headset
```

Turn a mod README's players' part into the text for its Nexus Mods page, in the mod's `dist/nexus-page.txt`:

```bash
python -I tools/nexus-page.py headset
```

Render an HTML page to a 1300×372 px PNG for a mod's Nexus Mods header:

```bash
powershell -File tools/render-html.ps1 -Html header.html -Out mods/headset/header.png
```

A mod's own tools are in its `tools/` folder.

## Releases

The mods in `release-please-config.json` are released from here, each with its own pull request.
After each push to `main`, [release-please](https://github.com/googleapis/release-please) keeps a pull request open for each of them with the next version and changelog, read from the commits that touch that mod's folder: `feat` raises the minor version and `fix` the patch.
Merging one publishes a GitHub release, tagged like `headset-v0.5.0`.
The workflow then zips the mod with `tools/package-mod.ps1`, which runs the mod's own `tools/stage.ps1` to build and test it, attaches the zip to the release, and uploads it to Nexus Mods as a new version of the mod's file (documented: [Nexus-Mods/upload-action](https://github.com/Nexus-Mods/upload-action); unverified until Headset's next release uploads).
The workflow can't compile redscript, which needs the game, so run `tools/check-scripts.ps1` on the mod before merging.

To check the build on GitHub without releasing anything, run the workflow by hand with the mod's folder, and the zip is kept with the run:

```bash
gh workflow run release.yml -f mod=mods/headset
```

Each mod's Nexus Mods page and its first file are made by hand, since the upload only adds versions to a file that exists (documented on the same page).
On the file's Advanced section, Nexus Mods shows the File ID and the Unique Mod ID; the number in the page's address is not the one the upload takes (read in cyberpunk-tobii, README.md, "Development").
They're stored as the repository variables `NEXUSMODS_<KEY>_MOD_ID` and `NEXUSMODS_<KEY>_FILE_ID`, where the key is the folder name in capitals with underscores, and until both exist, the mod's releases skip Nexus Mods.
The secret `NEXUSMODS_API_KEY`, a Personal API Key from the bottom of the Nexus Mods account's API keys settings, serves every mod.

The `publish-mod` skill in `.claude/skills/` takes a mod through all of this for its first release.
