# Cyberpunk 2077 mods

Our mods for Cyberpunk 2077, most of them for playing co-op on NightCoop.
Each mod's own README says how it's built and installed, and its RECORD.md what we found and decided.

| Folder | What |
|---|---|
| `mods/headset` | Hearing protection and noise cancelling, in singleplayer or co-op |
| `mods/nightcoop-voice` | Proximity and radio voice for NightCoop |
| `mods/nightcoop-tweaks` | Cyber Engine Tweaks additions to NightCoop: the partner menu, sending money, bike seats |
| `mods/vehicle-customizer` | Customize cars and bikes, seen by co-op partners |
| `mods/passenger-radio` | The radio key the passenger seat lacks |
| `mods/no-carry-weight` | Adds 1000 carry capacity |
| `ideas/` | Mods scouted but not started: manual shifting, a drivable bus, partners' sounds, Equipment-EX outfits in co-op |
| `vendor/nightcoop-sdk` | NightCoop's SDK and its docs (MIT), which the mods build against |
| `deps/` | Libraries the mods share, fetched and kept out of git |
| `tools/` | What more than one mod uses, or isn't about any one mod |

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

A mod's own tools are in its `tools/` folder.

## Releases

The mods in `release-please-config.json` are released from here, each with its own pull request. So far that's Headset.
After each push to `main`, [release-please](https://github.com/googleapis/release-please) keeps a pull request open for each of them with the next version and changelog, read from the commits that touch that mod's folder: `feat` raises the minor version and `fix` the patch.
Merging one publishes a GitHub release, tagged like `headset-v0.5.0`, and the workflow then builds and tests the mod and uploads its zip to Nexus Mods.
The workflow can't compile redscript, which needs the game, so run `tools/check-scripts.ps1` on the mod before merging.

A one-time setup:

1. In the repository's Settings > Actions > General, allow GitHub Actions to create pull requests.
2. On Nexus Mods, create the mod page and upload the first zip by hand. On its Files tab, Advanced under the file shows the File ID and the Unique Mod ID; the number in the page's address is not the one the upload needs.
3. Store your Nexus Mods Personal API Key, from the bottom of your account's API keys settings, as a secret:

   ```bash
   gh secret set NEXUSMODS_API_KEY
   ```

4. Store the two IDs as the repository variables `NEXUSMODS_HEADSET_MOD_ID` and `NEXUSMODS_HEADSET_FILE_ID`. Until both exist, releases skip Nexus Mods.

To release another mod, give it a `version.txt`, add it to `release-please-config.json` and `.release-please-manifest.json`, and give it a job in `.github/workflows/release.yml`.
