# Make your mod co-op

A step-by-step path from a single-player mod to one that behaves in a NightCoop session. Read [concepts.md](concepts.md)
first. The example [shared counter](../examples/) shows steps 2 to 5 in three languages.

## 1. Sort what your mod does

Go through the mod's features and put each one into a bucket:

| Bucket | Examples | Rule |
|---|---|---|
| **Local**: changes only your own player | HUD, camera, controls, looks, sounds only you hear | Nothing to do. Register with `LOCAL_ONLY` so partners know they need nothing |
| **World**: changes what everybody shares | time, weather, NPCs, quests and facts, spawns, the population | Only the **host** may do it. Guests ask |
| **Entity**: describes one synced thing | "this car is flying", "this player holds a lantern" | The entity's **owner** attaches the data; everyone else gets it on their mirror |

If a feature is world-changing, ask what a guest sees when the host's game and theirs disagree. If the answer is "nothing
good", route it through the host.

## 2. Register, with an honest passport

- **Id**: stable, unique, ASCII `[a-z0-9._-]`, 3..64 bytes. A good shape is `author.modname`. Never change it.
- **Flags**: tell the truth, they are shown to other players: `NEEDED_BY_ALL` if everyone should have the mod,
  `LOCAL_ONLY`, `CHANGES_WORLD`, `CHANGES_QUESTS`, `ADDS_ITEMS`, `SPAWNS_ENTITIES`, `HOST_AUTHORITY`.
- **Permissions**: declare what the mod uses — `USES_CHANNELS`, `USES_SHARED_STATE`, `USES_ENTITY_STATE`, `USES_POSE`,
  `USES_ACTIONS` (spawns need `SPAWNS_ENTITIES`, `factKeepLocal` needs `CHANGES_QUESTS`). An undeclared use answers
  `NCSDK_E_DENIED`. Declare only what you use: reviewers (Nexus) read these flags.
- **Partner data is untrusted**: numbers out of range, texts with control characters, ids of things that do not exist.
  Check every value, clean every text (`cleanText` / `CleanText`), never spawn or run an action because a partner said
  so. The checklist is in [../SECURITY.md](../SECURITY.md).
- **Protocol**: start at `1`. Raise it when your data format changes incompatibly. Players on different numbers do not talk.
- **Without NightCoop**: the mod must still work as a single-player mod. In C check for `NULL`, in redscript use
  `@if(ModuleExists("NightCoop"))` with a stub, in Lua use the helper (it does nothing when NightCoop is absent).

## 3. Route world changes through the host

The pattern:

```
guest presses the button  -->  ask the host (channel message or shared state)
host decides and applies  -->  host publishes the result (shared state)
everybody, guest included -->  reads the result from the state event
```

Ask by channel when it is an **action** ("start the event now"). Ask by shared state when it is a **value** the host should
keep ("the setting is 3"). In both cases the host's game applies it; the guest's game never changes the world on its own.

Skeleton in redscript (host applies, guests ask on channel 1; `IsHost()` is the switch):

```swift
public func RequestEvent() -> Void {
  if NightCoopSdk.IsHost() || !NightCoopSdk.InSession() {
    this.StartEvent();                                   // we are the world: just do it
  } else {
    NightCoopSdk.Send("yourname.yourmod", 0, 1, "start", true);   // to the host, reliable
  };
}

// in the event handler
if evt.kind == EnumInt(NightCoopSdkEventKind.Message) && evt.a == 1 && NightCoopSdk.IsHost() {
  this.StartEvent();                                     // a guest asked
};
```

The host should treat requests as requests: check that the sender is allowed and the value is sane. In C that is the
`stateRequest` hook for shared state (return `0` to refuse); for channel messages it is your own code.

## 4. Shared state for the world's facts

Use shared state for a fact everybody should agree on and a late joiner should learn: "the counter is 7", "the event is
running", "the difficulty is 3". Key to value (keys up to 64 bytes, values up to 4096 bytes, 256 keys).

- The host sets it; everybody gets `stateChanged`. Late joiners get every key once after joining.
- A guest's set is a request. It changes only when the host accepts (scripts accept everything; in C you can refuse).
- Read the current value at any time with `stateGet` / `GetState`.
- Put each fact under its own key, not everything into one big value: small values mean small traffic.

## 5. Entity state for "my car" and "my player"

Use entity state when the data belongs to one synced entity: the vehicle you drive, your own player, an NPC you lead.

1. Get the entity: `vehicle.GetEntityID()` in scripts, or the `EntityID` hash in C.
2. Check you lead it: `EntityIsMine(entity) == 1`. If it returns `-7` (`Unknown`), NightCoop does not sync the entity and it
   is purely local, so partners can never see it.
3. Attach your value under a key you chose: `SetEntityState(id, entity, key, value, stream)`. Continuous values (a position,
   an angle, a throttle) go as a `stream`: unreliable, only the newest counts. Rare values (a mode) go reliable (default).
4. On the other machines, `entityState` / the `EntityState` event arrives with **their** local mirror in `entity`. Apply the
   value to that mirror. It comes again if the mirror is re-created, and for late joiners.

```swift
@if(ModuleExists("NightCoop"))
private func ShareFlightMode(vehicle: ref<VehicleObject>, mode: Int32) -> Void {
  NightCoopSdk.SetEntityState("yourname.yourmod", vehicle.GetEntityID(), 1, IntToString(mode), false);
}
```

Never write to an entity you do not lead. Ask its owner by channel instead.

## 6. Channels for events

Use a channel message for something that **happens** and is not a state: "I fired", "start the event", "ping". Pick a number
per kind of message (your own numbering, `uint16_t`). Reliable for things that must arrive and keep order, unreliable (the
default) for things where the next one replaces the last. Keep messages small: 1024 bytes unreliable, 16384 reliable, and
at most 120 messages and 32 KiB a second per direction.

`send` returns how many peers it reached. `0` means nobody has the mod: not an error.

## 7. Test with two players

- Run the session with **host and guest** and do every feature from both seats. Many bugs show only on the guest.
- Test **a partner without your mod**: nothing should break, and with `NEEDED_BY_ALL` both players should get the note.
- Test **joining late**: start the feature on the host, then let the guest join. The guest must get the current state.
- Test **leaving and rejoining**, and a guest going to the main menu and back (`PEER_WORLD_OUT`, `PEER_WORLD_IN`).
- Look at NightCoop's log (lines `sdk: [yourmod.id] ...`) and at `NightCoopSdkStatus()`: see [troubleshooting.md](troubleshooting.md).

## 8. A checklist by kind of mod

| Your mod | What to do |
|---|---|
| Visual only (LUT, lighting, HUD, camera, UI) | Nothing: it is local. Flag `NCSDK_MOD_LOCAL_ONLY` if you register at all |
| Clothes, cyberware looks (ArchiveXL, TweakXL) | A partner without the mod sees a fallback NightCoop picks; name your own: `fallback = Items.Mine -> Items.Game` in a [manifest](manifest.md). Flag `NCSDK_MOD_ADDS_ITEMS` |
| A new car (TweakXL + ArchiveXL) | A manifest with `needed_by_all`, `adds_items` and a `fallback` to a game car of the same kind: a partner without the mod gets NightCoop's stand-in for a missing record, and your fallback tells it which. Handling mods are local to the driver |
| Weapons | Your player's weapon is drawn on partners' machines by its record; for a partner without the mod name a game weapon with `fallback =` (NightCoop's stand-ins for missing records use it). Damage goes through the game's damage pipeline and NightCoop's claims: do not apply damage to partners' NPCs yourself |
| Quickhacks, status effects on NPCs | An NPC is led by its owner: change only NPCs `entityIsMine` says are yours; ask the owner by a channel message for the rest (and see the NPC functions of the SDK for ready requests) |
| Spawns (NPCs, props, vehicles) | Spawn on the host (or ask it), `entityShare` them; a purely local helper — `entityKeepLocal` |
| Quests, scenes, phases | The host's world decides quests: keep your mod's per-player facts with `factKeepLocal` / `factKeepLocalList` (or `fact =` in a manifest); never mark facts of the main story |
| Script systems with state (needs, economy, a gig board) | Decide whose it is: the character's (default) or the world's (`scriptableScope`, `world_system =` in a manifest) |
| Time, weather, the world's pace | The host leads the world's time and weather: a guest's change is undone. On the host change them as in single player; a guest asks with `worldAsk` (time of day, weather — the host's copy of your mod or a vote decides). The pace of time cannot be asked (no setter in the game's scripts): a pace mod is data that every player needs. Mind `NCSDK_EV_TIME_SKIP` to count skipped hours |
| Settings of your mod that must be the same for all | Keep them in the shared state: the host writes `stateSet("settings", …)` from its own settings, guests read `stateGet` / `stateChanged` and use those while in the session (their own again after `NCSDK_EV_SESSION_END`) |
| Menus and decisions for everybody | Your items: `menuItemSet` (co-op menu «Mods…»); a question to all: `voteStart` on the host |
| Saves | See below |

### Saves and save locks

In a session the host's saves are the session's; a guest's saves in the host's world are NightCoop's technical saves of
the guest's character. A mod that blocks saving (a save lock of its own, `GameInstance.GetSaveLocks`) blocks it only on
the machine it runs on: on the host that is the session's save — the save a guest joins by waits until the game lets the
host save. Release your locks when your moment is over; write your own files of the session after `NCSDK_EV_HOST_SAVE`
(value 1) and read them back after value 2 (the host loaded).

## Common mistakes

- **A guest changes the world itself.** The guest's game diverges: different weather, different NPCs, different quest state.
  Route it through the host (step 3).
- **Sending every frame, reliably.** The rate limit answers `NCSDK_E_LIMIT` and your data stops. Send on change; use a stream
  or `LATEST_ONLY` for continuous values.
- **Keeping a partner's `EntityID` as a permanent handle.** Mirrors are re-created under new `EntityID`s and NPCs change
  owners. Keep the network reference (or nothing) and ask `EntityOfRef` when you need the entity; let entity state push data to
  the current mirror.
- **Changing an entity you do not lead.** `SetEntityState` answers `NCSDK_E_DENIED`. A mirror or copy is the owner's thing:
  ask the owner by channel.
- **Treating "no answer" as "no".** `PeerHasMod` returns `-2` until the mods check with that player is over. Wait for the
  `PEER_MOD` / `PEER_NO_MOD` event.
- **Storing peer numbers in a save.** They belong to one session.
- **Reusing an id or protocol after an incompatible change.** Raise `protocol` so old copies stay silent instead of
  misreading your data.
- **Copying NightCoop's `.reds` files into your redscript mod.** Do not; NightCoop adds them itself.
- **Replacing a game function co-op relies on.** `@replaceMethod`, a CET `Override` or a detour that does not call the
  original can switch a part of co-op off silently. See [do-not-hook.md](do-not-hook.md) — and its section on what NightCoop
  cannot find by itself.
