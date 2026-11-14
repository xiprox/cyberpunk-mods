# Equipment-EX outfits in co-op

Partners seeing each other's whole Equipment-EX outfit in NightCoop, where today they see only part of it.
Found on 2026-11-02 from the logs and NightCoop.dll's disassembly on build bacb705, while Bossun wore an Equipment-EX outfit, and rechecked that day on 0.2.0 (build a3ea83df, protocol 164) from its code and strings only.
NightCoop has had newer builds since (5a51ea59 on 2026-11-13), so check all of this again first. Nothing is built.

## What NightCoop does

- It sends one item per body slot (`outfit_slots_ex`), and the slot latest in its table wins.
  So leg items in ThighLeft, ThighRight, BodyMiddle or BodyOuter replace the pants in LegsMiddle, and the pants are never sent.
  0.2.0 kept this: its log text still says "one per body slot — {} left out under an outer one".
- On bacb705, with an Equipment-EX outfit on, the sender's look compared as changed at every 2 s check and was resent, so partners swapped every item and re-veiled the body every 2 s.
  Each read rebuilt the item with `ItemID.FromTDBID`, which gives a new ID, and the comparison included the whole ID.
  0.2.0 added `outfit_id_stable`, on by default: one ItemID per record for the run, so the look goes out only when items change. Not yet seen in the game.
- A partner with a mod's TweakXL records but not its archive never finishes the look, because `look_missing_default` applies only when the record is missing.
  The body stays hidden until the veil's safety timeout (15 s on bacb705), then shows for about 1 s. Nothing in 0.2.0's strings or docs suggests this changed; not tested.
- An empty `r6/scripts/EquipmentEx` folder still shows in NightCoop's mod list (0 files) and makes it print its Equipment-EX `hooks:` line, so neither means the mod is installed: read the size column in `nightcoop-mods.txt`.
  On the evening of 2026-11-02 the folder was empty on all three PCs.
- Archives loose in `archive/pc/mod` don't travel through the collector's Mods tab, which shares folders only; that's how the user ended up with `r6/tweaks/raem` and `val_custom` but no archives. Moved into a folder of their own, they would.

For flickering or partly dressed partners, look for repeated "your look" lines on the sender and "body is shown ... NOT in" on the receiver before suggesting reinstalls: matching mods alone won't bring the pants back.

## The plan

Follow the recipe in [content-fallbacks.md](../vendor/nightcoop-sdk/docs/content-fallbacks.md) ("your mod changes how V looks beyond items"):

- The sender reads the 54 `OutfitSlots.*` slots and calls `SetEntityState` on its own player (reliable, up to 1024 bytes a key; 12 hex characters a slot fits).
- Partners get the value with the body's EntityID, and again when a body is re-created or a player joins late. They put the items on with `CreatePreviewItemID`, `GivePreviewItemByItemID` and `AddItemToSlot`.
- Keep `outfit_slots_ex` on, so a partner without the mod still sees NightCoop's partial outfit.
- Unknown: whether a partner's body accepts `OutfitSlots.*`, and whether NightCoop leaves our items on when its look changes. Its dress code appears to act only on its own look's entries (read from log strings, not traced). Items in both a body slot and an outfit slot may double up.
