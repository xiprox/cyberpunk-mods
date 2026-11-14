---
name: publish-mod
description: Publish a mod from this repository on Nexus Mods for the first time, from a readiness check to the first upload and automatic releases after it. Use when the user asks to publish, release, or put a mod on Nexus Mods. Pass the mod's folder name, such as nightcoop-voice.
---

# Publishing a mod

Take the mod in `mods/<mod>` from the crew to its first release on Nexus Mods, in this order.
Headset's files are the example for each step: its first release, `headset-v0.5.0`, came from merging the release pull request release-please opened once Headset was in its files.
Each step that commits, pushes, merges, or sets a repository variable waits for the user's go-ahead, as the root CLAUDE.md says.

## 1. Check it's ready

Report every check that fails to the user before going further, and fix nothing they haven't agreed to.

- **Played:** the mod's RECORD.md shows the crew played the version about to ship, and its "Not yet checked in the game" line holds nothing a new player would hit first.
  Read each player's latest logs, as the root CLAUDE.md says, for that version loading and working.
- **Game patches:** a mod that relies on the game exe's internals, such as offsets, a Wwise interface, or a function's layout, checks the game's build and switches itself off on another one, with a log line saying why, as Headset's Wwise build check does (`mods/headset/src/wwise/install.cpp`).
  A mod that only uses RED4ext, redscript, Codeware, TweakXL, ArchiveXL, or CET needs no check.
- **Requirements:** every mod it needs is known by name: redscript for `.reds` files, Codeware for its types, TweakXL for tweaks, ArchiveXL for `.xl` files, and Native Settings for a settings page.
- **Settings files:** a file the mod writes for players to edit starts with every value commented out, so a later starting value reaches players who already have the file (Headset's RECORD.md, 2026-11-10).
- **Game files:** the zip holds nothing copied unchanged from the game's files.
- **Tests and scripts:** the mod's tests pass, and `tools/check-scripts.ps1` passes for a mod with redscript.

## 2. Make it releasable

1. Give the mod a `tools/stage.ps1 -Out <folder>` that builds it, runs its tests, and lays it out in the folder as the game folder is, like `mods/headset/tools/stage.ps1`.
   If a test needs an audio device or the game, make it skip itself when the `CI` environment variable is set, which GitHub's build machines set (documented in GitHub's list of default environment variables).
2. Give it a `release.json` with `zip`, the zip's name before the version, and `title`, the file's name on Nexus Mods, like `mods/headset/release.json`.
3. Give it a `version.txt` holding the version the crew last played, and have the build read its version from there, as `mods/headset/CMakeLists.txt` does.
4. Add the mod to `release-please-config.json`, with `"release-type": "simple"` and `"component"` set to its folder name, and to `.release-please-manifest.json` at the version in `version.txt`.
5. Run `powershell -File tools/package-mod.ps1 -Mod <mod>`, and check the zip it writes to the mod's `build/package`: every file the game needs, paths with forward slashes, and the version in what the mod logs.

## 3. Write the page

1. Rewrite the README to `.claude/rules/writing.md`'s README section: the players' part first, which becomes the page, then the developers' part under `## For developers`, where `tools/nexus-page.py` stops.
   Go over the players' part with the user line by line, then run the `doc-reviewer` agent on it.
2. Make the header from an HTML page the user approves, with `powershell -File tools/render-html.ps1 -Html <page> -Out mods/<mod>/header.png`, whose default size is the header's, and put it at the top of the README.
3. Run `python -I tools/nexus-page.py <mod>`, which writes the page's text to `mods/<mod>/dist/nexus-page.txt`.
   Its overview is the README's first paragraph, so shorten that if the page's overview field won't take it.

## 4. Release it

1. Propose the commits: one for each mod's folder, and the two release-please files in a commit of their own with the scope `repo`.
   Push once the user agrees.
2. Run the release workflow as a dry run, which builds the mod on GitHub without releasing it: `gh workflow run release.yml -f mod=mods/<mod>`.
   When it worked, the run keeps the zip as its artifact.
3. After the push, release-please opens the mod's release pull request, with the next version from the mod's `feat` and `fix` commits.
   A mod with earlier commits gets all of them in its first changelog (unverified: Headset had none).
   If the user wants a different first version, a commit in the mod's folder with the footer `Release-As: <version>` sets it.
4. Run `tools/check-scripts.ps1` on the mod, then merge the pull request on the user's go-ahead.
   GitHub publishes the release with the zip attached, as it did `headset-v0.5.0`.
5. The user creates the Nexus Mods page from `nexus-page.txt`, `header.png`, and the release's zip, lists the requirements, and tags the page AI-generated.
6. The user sends the Unique Mod ID and the File ID, shown under Advanced on the file.
   Set them as the repository variables the root README's "Releases" section names.
7. Add a RECORD.md entry saying the mod is on Nexus Mods, from which version.

From then on, merging the mod's release pull request uploads each new version to Nexus Mods, as the root README's "Releases" section describes.
