# NightCoop Tweaks

Personal additions to [NightCoop](https://nightcoop.net), the Cyberpunk 2077 co-op mod, as one Cyber Engine Tweaks mod.
[RECORD.md](RECORD.md) says what we found about NightCoop and the game, and why the tweaks work the way they do.

## Tweaks

### Send money

The phone's **Contacts** list has every partner in the session, sorted by name among the other contacts and marked "NightCoop partner".
F or Enter on one closes the phone and opens **Send money / Never mind**, drawn like the game's own conversation choices, wherever they are and from inside a car too (not in combat, a conversation, a cutscene or a seat, or while working a drone, camera or turret).
The mouse wheel, arrow keys or d-pad move the selection, and a tap of F picks (in a car too; holding F gets you out).
Send money offers 1,000, 5,000 and 10,000 (those you can afford), All, and **Custom amount...**, which opens the game's own quantity slider.
A preset asks once more before it sends; the slider's Send button sends straight away.
The transfer then runs as the game's own progress bar with the eddies look, as the story's payments do: it completes once the host has taken the money, and fails if NightCoop refuses or the host doesn't answer in 8 seconds.

Partners show by their NightCoop nickname once their map pin has been seen with no other partner beside them, and as "Peer N" until then.

The CET overlay's **NightCoop Tweaks** window also has a Send money section, and the CET console takes `GetMod("NightCoopTweaks").Send(peerId, amount)`.

The money goes through NightCoop's own item transfer: the host checks it and the sender is debited before the partner is credited, so nothing is duplicated.
The partner needs only NightCoop to receive; to send back they need this mod too.

### Bike seat

A partner riding a bike in first-person looks like they stand on it, to everyone else.
With this mod you see them sitting, whichever camera they use; the rider doesn't need it.
The **NightCoop Tweaks** window has a checkbox to turn it off.

### Far partner pins

NightCoop takes a partner's body away once they're 200 m off, and their map pin and name tag go with it.
With this mod they stay on your map and on the edge of your minimap, however far they go, until their body and NightCoop's own pin come back at about 150 m.
The name tag floating in the world still comes back only with the body.
It follows NightCoop's "Player markers" setting, the **NightCoop Tweaks** window has a checkbox to turn it off, and the partner doesn't need it.

### Horn

NightCoop doesn't pass a car's horn on, so partners never heard you honk.
With this mod they hear the horn of the car or bike you drive, its own sound, from their copy of it, for as long as you hold the key; a police car's is its police horn.
The partners need nothing but NightCoop, and the **NightCoop Tweaks** window has a checkbox to turn it off.

### Siren

The game switches a police car's siren lights and its sound apart, and as far as NightCoop's code shows it passes neither sound on, so partners wouldn't hear your siren.
With this mod they hear the siren of the police car you drive, its own sound, from their copy of it: it starts when the sound goes on (V, or anything else that turns it on while you drive) and stops when it goes off, when you get out, or when the car is gone.
Switching the lights alone sends nothing, and the lights are left to the game and NightCoop.
The partners need nothing but NightCoop, and the **NightCoop Tweaks** window has a checkbox to turn it off.

### Silenced shots

NightCoop plays a partner's shots with the weapon's NPC sound, but a silenced weapon's with none, so partners heard nothing at all.
With this mod they hear the shot an NPC firing that weapon silenced makes, from your body: a single shot, or the automatic loop from your first shot until you let go of the trigger.
A weapon counts as silenced the way the game counts it, so a silencer or an iconic with one built in (Panam's Overwatch); one the game gives no silenced NPC sound plays its plain one.
The partners need nothing but NightCoop, and the **NightCoop Tweaks** window has a checkbox to turn it off.

Horn, Siren and Silenced shots send through NightCoop's SDK, which takes 10 sounds a second from a mod: past 8 a second a fast single-shot weapon drops some shots, so a horn's, a siren's or a loop's stop always gets through.

## Requirements

- NightCoop (with RED4ext); 0.2.0 or later, whose SDK plays sounds on partners' copies, for Horn, Siren and Silenced shots
- Cyber Engine Tweaks 1.38 or later
- Codeware, for the amount slider

## Installing

On this PC the game's mods folder links to this repository, so an edit here is in the game after **Reload All Mods** in the CET overlay:

```bash
powershell -File tools/link.ps1
```

Pass `-Game "<your game folder>"` if the game isn't in Steam's default place, and `-Unlink` to take the link away.

For a partner, `tools/pack.ps1` writes `dist/NightCoopTweaks-<version>.zip`, laid out as the game folder is; they extract it into their Cyberpunk 2077 folder.
The version is `VERSION` in `init.lua`, which the mod also writes as its log's first line; raise it for every zip that goes out, so the logs say which build each player ran.

```bash
powershell -File tools/pack.ps1
```

## Checking

Only the game runs the mod, so `tools/check.py` catches what it can before Reload All Mods:
syntax errors (it parses with LuaJIT, the Lua CET runs), a global set by mistake (a missing `local`), a global read that isn't Lua's, CET's or a game type (a misspelt name), an `Observe` or `Override` of a function the class doesn't have (a misspelt name, or a script static, which CET can't hook), and a `core/` or `tweaks/` path that isn't a file.
It needs LuaJIT (`scoop install luajit`) and takes the game's type names from NightCoop's `rtti-names-*.txt`.

```bash
python -I tools/check.py
```

## Where things are

| What | Where |
|---|---|
| The mod in the game (a link to `cet/NightCoopTweaks`) | `<game>\bin\x64\plugins\cyber_engine_tweaks\mods\NightCoopTweaks` |
| The mod's own log | `cet/NightCoopTweaks/NightCoopTweaks.log` (CET writes it next to `init.lua`) |
| CET's log of script errors | `<game>\bin\x64\plugins\cyber_engine_tweaks\scripting.log` |
| NightCoop | `<game>\red4ext\plugins\NightCoop\NightCoop.dll` |
| NightCoop's logs | `<game>\red4ext\plugins\NightCoop\logs\` and `nightcoop.log` next to the DLL |
| NightCoop's list of every game class, property and function | `<game>\red4ext\plugins\NightCoop\rtti-names-*.txt` |
| The game's script sources, for this game version | `<game>\tools\redmod\scripts` |

`<game>` is `C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077` on Steam.

## Layout

- `cet/NightCoopTweaks/init.lua` loads the core and the tweaks, passes CET's events on, and draws the NightCoop Tweaks window.
- `cet/NightCoopTweaks/core/` is what the tweaks share:
  - `nightcoop.lua`: NightCoop's natives, the session, where the partners are, their nicknames
  - `partnermenu.lua`: the partner's menu, which tweaks add entries to and the phone opens
  - `phone.lua`: partners in the phone's Contacts, opening their partner menu from afar
  - `choices.lua`: a choice list drawn by the game's dialog widget, and its keys
  - `input.lua`: the game's input actions (F, Enter, the scroll keys) for the parts that read keys
  - `quantity.lua`: the game's quantity slider popup
  - `progressbar.lua`: the game's progress bar from quests and quickhack uploads
  - `effects.lua`: the effects an entity can play, listed in Diagnostics and played from the console with `GetMod("NightCoopTweaks").Effect("name")`, for finding a game effect's name
  - `notify.lua`: the game's on-screen message
  - `ref.lua`: comparing game objects and EntityIDs, and holding a game object without keeping it alive
  - `sounds.lua`: game sounds played on partners' copies of our body or car through NightCoop's SDK (the mod registers with it for that)
  - `vehicles.lua`: whether we sit in a vehicle's driver seat, and which of its audio resources a sound table knows (Horn, Siren)
  - `log.lua`: problems, logged once each and listed in Diagnostics
- `cet/NightCoopTweaks/tweaks/<tweak>/` is one tweak, `tweak.lua` its entry; `sendmoney/` has `money.lua` (balance and sending), `menu.lua` (its partner-menu steps) and `window.lua` (its window section); `bikeseat/` and `farpins/` are one file each; `horn/horns.lua`, `siren/sirens.lua` and `silencedshots/sounds.lua` are tables written from the game's files (below).
- `tools/link.ps1` and `tools/pack.ps1` install the mod here and package it for a partner; `tools/check.py` checks its Lua.
- `tools/make-sound-tables.py` writes the horn, siren and silenced-shot tables from the game's audio metadata with WolvenKit's command line; run it again after a game patch:

```bash
python -I tools/make-sound-tables.py
```
- `../../tools/ncre.py` reads NightCoop's disassembly, below.
- `docs/nightcoop-natives.txt` lists NightCoop's script natives with their signatures.

## Adding a tweak

Make a folder under `cet/NightCoopTweaks/tweaks/` with a `tweak.lua`, and add `"tweaks/<folder>/tweak"` to `TWEAKS` in `init.lua`.
`tweak.lua` returns a table with a `name` and any of these:

```lua
local Tweak = { name = "Wave" }               -- its section header in the window, and its name in the log

function Tweak.Init() end                     -- once, from CET's onInit: Observe, Override and PartnerMenu.Add go here
function Tweak.Update() end                   -- every frame
function Tweak.DrawOverlay(session) end       -- its section of the window; session is { role, connected, peerId } or nil
function Tweak.OverlayOpened() end
function Tweak.OverlayClosed() end
function Tweak.Shutdown() end                 -- on Reload All Mods and when the game closes

Tweak.api = { Wave = function(peerId) end }   -- GetMod("NightCoopTweaks").Wave(peerId) in the CET console

return Tweak
```

To offer something in the partner menu, add an entry in `Init`; `core/partnermenu.lua` describes the `menu` its `open` gets.
The list opens from the phone's Contacts with the partner anywhere, so an entry that only makes sense up close checks the distance itself:

```lua
PartnerMenu.Add({
    label = "Wave",
    open = function(menu)
        menu.Show("Wave at " .. NightCoop.PeerLabel(menu.peer), { "Big wave", "Back" }, function(choice)
            if choice == 1 then menu.Close() else menu.Back() end
        end)
    end,
})
```

A tweak's files require each other by their path from the mod's folder, as `require("tweaks/<folder>/<file>")`, and the core as `require("core/<file>")`.
A hook that throws is written to the log once and stays off until Reload All Mods, so the other tweaks keep working.

## Reading NightCoop

NightCoop is closed source, and its script natives aren't documented.
`../../tools/ncre.py` finds them in the DLL's disassembly (it needs `llvm-objdump` on the PATH):

```bash
python -I ../../tools/ncre.py disasm
```

```bash
python -I ../../tools/ncre.py natives
```

Then `fn`, `strings`, `where` and `xref` show a native's code and the strings it uses; `python -I ../../tools/ncre.py --help` lists them.
After a NightCoop update, regenerate `docs/nightcoop-natives.txt` and check that the natives the mod calls kept their signatures.
