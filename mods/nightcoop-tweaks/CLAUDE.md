# NightCoop Tweaks

Personal Cyber Engine Tweaks additions to the NightCoop co-op mod; [README.md](README.md) has the layout and where everything lives.
`RECORD.md` holds what we found and decided, newest entry first; add an entry when a finding or decision changes how the mod works, and keep its "Not yet checked in the game" line current.

- The game's mods folder links to `cet/NightCoopTweaks` (`tools/link.ps1`), so edit files here, never in the game folder; the user loads changes with CET's Reload All Mods.
- Look game APIs up before using them: the script sources in `<game>\tools\redmod\scripts` and NightCoop's `rtti-names-*.txt`. NightCoop's own natives are in `docs/nightcoop-natives.txt`, and `tools/re/ncre.py` reads more of its DLL.
- Friends run zips from `tools/pack.ps1`; raise `VERSION` in `init.lua` before packing a build that differs from one already sent, so their logs say which build they ran.
- Run `python -I tools/check.py` after every Lua change and fix what it reports. It parses with LuaJIT and flags stray and misspelt globals, but only the game runs the mod, so still say what went untested there.
- Each tweak is a folder `cet/NightCoopTweaks/tweaks/<tweak>/` with `tweak.lua` as its entry, listed in `TWEAKS` in `init.lua` (README, "Adding a tweak"). It keeps its own code in its folder.
- `core/` is only what two or more tweaks share, or what a tweak needs from the game without being about that tweak: NightCoop's natives, the partner menu, choice lists, popups. Move code there when a second tweak needs it, not before.
- Files are required by their path from the mod's folder (`require("core/nightcoop")`, `require("tweaks/sendmoney/money")`). Observe and Override go in an `Init`, which `onInit` runs.

## Commits

Conventional Commits, with the tweak a player recognizes as the scope (`send-money`), or `menu` for the partner menu itself, `window` for the CET window, `install` for the scripts; never a file or a layer.
The title says what the player gets, not what the code does; the description says why, and what went unchecked in the game.
One change per commit.

Claude commits only when asked, and proposes every commit's title and description in the reply first, for the user to approve or change.
