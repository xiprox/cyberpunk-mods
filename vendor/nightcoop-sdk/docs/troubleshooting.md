# Troubleshooting

## Where to look

1. **NightCoop's log.** Lines about your mod start with `sdk: [your.mod.id]`. Registration refusals, missing partners,
   refused state requests and dropped data are written there. Start here.
2. **`NightCoopSdkStatus()`** in the Cyber Engine Tweaks console. It prints the registered mods, the providers, and per mod:
   how many items were sent, received, dropped, limited, and how many wait in the queue. A growing "dropped" or "limited"
   number means you are over the rate limit or the queue (see [limits-and-versions.md](limits-and-versions.md)).
3. **The mod's own log lines.** `Log(...)` / `log(...)` write into NightCoop's log under your mod.

## Switches

The player (or you, while testing) can switch parts of the SDK off. In the CET console:

```lua
NightCoopQuestSet("sdk_channels", false)
```

or put a line `sdk_channels = off` into `switches.txt`.

| Switch | Switches off |
|---|---|
| `sdk` | The whole SDK. `NightCoopSdkGet` returns `NULL`, `NightCoopSdk.Version()` returns `0`: your mod must work as if NightCoop were absent |
| `sdk_channels` | Channel messages (`send`) |
| `sdk_state` | Shared state |
| `sdk_entity_state` | Entity state |
| `sdk_mods_check` | The on-screen note about partners missing a `NEEDED_BY_ALL` mod |
| `sdk_permissions` | The check of declared permissions (`NCSDK_MOD_USES_*`): off — every use is allowed |
| `sdk_spawns`, `sdk_fx`, `sdk_rewards`, `sdk_fallbacks`, `sdk_manifests`, `sdk_menu`, `sdk_votes`, `sdk_world_ask`, `sdk_save_scopes`, `sdk_npc`, `sdk_npc_lease`, `sdk_world_slow` | One feature each: shared spawns, effects and sounds, rewards, content fallbacks, manifests, items in the co-op menu, votes, asks to change the world, script systems in the save, effects on NPCs, the lease of an NPC, the world slow-down. A call of a part that is off answers `NCSDK_E_OFF`; partners' requests of that kind are refused |
| `sdk_npc_show`, `sdk_npc_push`, `sdk_npc_lasting`, `npc_time_freeze`, `npc_god_mirror`, `sdk_npc_logic`, `npc_host_only`, `sdk_spawns_auto`, `sdk_spawns_limits`, `sdk_spawns_handoff`, `sdk_spawns_cars`, `sdk_spawns_host_only` | How NightCoop shows and hands over NPCs, vehicles and spawns of mods ([npc-effects.md](npc-effects.md), [shared-spawns.md](shared-spawns.md)). All on by default except `npc_host_only` (the host never hands its NPCs to guests) and `sdk_spawns_host_only` (copies of spawns only from the host) |
| `hook_overlap` | NightCoop's check of other mods' hooks on functions co-op relies on ([do-not-hook.md](do-not-hook.md)): log lines, the note on the screen; `hookDeclare` / `hookCoopUses` answer `NCSDK_E_OFF` |
| `sdk_session` | Host only: mods on the SDK in sessions it hosts. Off — no mod data for anybody in that session; functions that send answer `NCSDK_E_DENIED` |

The player can also block single mods: a line `sdk_block = author.mod, other.mod` in `switches.txt` (or
`NightCoopSdkBlock("author.mod", true)` in the CET console for this run). A blocked mod's `registerMod` is refused (it works
as without NightCoop) and partners' data for it is dropped.

A function whose part is switched off answers `NCSDK_E_OFF` (`SwitchedOff`) where the part reports errors. If your data does
not travel, check the switches before anything else.

## It does not work: causes by symptom

| Symptom | Likely cause |
|---|---|
| `registerMod` returns `0`, or `RegisterMod` returns `false` | Bad id (not ASCII `[a-z0-9._-]`, shorter than 3 or longer than 64 bytes); the id is already registered (scripts: it belongs to a C plugin); 64 mods already; a hash collision with another id. NightCoop's log says which |
| `NightCoopSdkGet` returns `NULL`, or `Version()` is `0` | The SDK is switched off (`sdk`), or this NightCoop has no interface of the version you asked for |
| `GetModuleHandle` finds no `NightCoop.dll` | NightCoop is not loaded. Look from the game thread after your `Main`, not in `DllMain`; plugins load in an unknown order |
| Nothing arrives at the partner | The partner has not registered the same id **with the same `protocol`**; or its passport has not arrived yet (`PeerHasMod` = `-2`); or you are not in a session. `send` returns `0` when nobody has the mod |
| `send` returns `NCSDK_E_STATE` | No session, or the passport of that very peer is not known yet. Wait for `PEER_MOD` |
| `send` / `stateSet` returns `NCSDK_E_LIMIT` | Over 32 KiB/s or 120 messages/s (bursts up to 4x). Send on change, use a stream or `LATEST_ONLY`, send less |
| `send` returns `NCSDK_E_ARG` | Payload too large (1024 bytes unreliable, 16384 reliable), empty id, bad channel or handle |
| Guest `stateSet` changes nothing | A guest only **asks**. The value changes when the host accepts and `stateChanged` arrives. The host's `stateRequest` hook may have refused (a log line on both sides). If the host has not answered the mods check yet you get `NCSDK_E_STATE`; if the host lacks the mod, `NCSDK_E_DENIED` |
| Any function returns `NCSDK_E_DENIED`, the log says "uses what it did not declare" | The permission flag is missing in `RegisterMod` (`NCSDK_MOD_USES_*`, `SPAWNS_ENTITIES`, `CHANGES_QUESTS`) |
| `send`, `stateSet`, `entitySetState` return `NCSDK_E_DENIED` in a session | The host switched mods off for the session (`sdk_session`) |
| `SetEntityState` returns `NCSDK_E_DENIED` | You are not the owner. Check `EntityIsMine(entity) == 1` |
| `SetEntityState` returns `NCSDK_E_UNKNOWN` | NightCoop does not sync that entity (it is purely local) |
| The partner never gets the entity state | Their mirror is not there yet (the value waits and arrives when it appears); or the partner does not have the mod with the same protocol; or the `sdk_entity_state` switch is off |
| No events in redscript | `Listen` returned `false` (the function must take exactly one `ref<NightCoopSdkEvent>`); the target died with the world and you did not `Listen` again; or you registered with the wrong id. Without `Listen`, call `PollEvent` |
| No events in C | A hook left `NULL` sends items to the poll queue (`pollEvent`); you register hooks but the mod never polls |
| `Unsupported` | That part (pose, actions, spawns) is not in this NightCoop build |
| Events are missing under heavy traffic | The poll queue holds 1024 items per mod and drops the oldest. Poll every frame or use hooks / `Listen` |
| redscript does not compile after adding NightCoop code | You copied NightCoop's `.reds` files into your mod (duplicate definitions), or you used `NightCoopSdk` outside `@if(ModuleExists("NightCoop"))` |
| A part of co-op does nothing with your mod installed, nothing in the SDK log | Your mod replaces a function co-op relies on. Look for `hooks:` lines in NightCoop's log and `logs/nightcoop-hooks.txt`; if NightCoop cannot see it, check the list in [do-not-hook.md](do-not-hook.md#what-nightcoop-cannot-find) |
| Both players get a note about a missing mod | Your mod has `NEEDED_BY_ALL` and the partner lacks it or has another protocol. Switch `sdk_mods_check` off to hide the note while testing |

## Testing alone

Out of a session you are your own host: shared state works locally, `send` reaches nobody (it returns `NCSDK_E_STATE`). That is enough to
check registration, state logic and your fallback without NightCoop. For real traffic and the guest side you need a second
player.
