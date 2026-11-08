# API reference

Every function exists in the C table `NcSdkApi` and, in short form, as a static function of the script class `NightCoopSdk`
(redscript and Cyber Engine Tweaks). Names, signatures and comments are in `include/nightcoop_sdk.h` (the source of truth)
and `redscript/NightCoop/NightCoopSdkNative.reds`.

How the layers differ:

- **C** functions take your mod handle (`NcSdkMod`) first. **Scripts** take your mod id (`String`) first.
- **Peers** are `NcSdkPeer` (`uint32_t`) in C and `Int32` in scripts. The host is `0`. "Everyone" is `NCSDK_TO_ALL`
  (`0xFFFFFFFE`) in C and `-2` in scripts. "None" is `NCSDK_PEER_NONE` (`0xFFFFFFFF`) in C and `-1` in scripts.
- **Entities** are an `EntityID` hash (`uint64_t`) in C and an `EntityID` in scripts.
- **Strings** in C are UTF-8, zero-terminated. Scripts have text variants (`Send`, `SetState`, `SetEntityState`) and byte-array
  variants (`SendBytes`, `SetStateBytes`, `SetEntityStateBytes`).
- Calls are for the **game thread** unless this page says "any thread".

## Result codes

`int32_t` functions return `NCSDK_OK` (0) or a positive count/flag on success, a negative code on failure, unless noted.

| C | Script `NightCoopSdkResult` | Value | Meaning |
|---|---|---|---|
| `NCSDK_OK` | `Ok` | 0 | Done |
| `NCSDK_E_ARG` | `BadArgument` | -1 | Bad argument: NULL, empty, too long, bad handle |
| `NCSDK_E_STATE` | `NotNow` | -2 | Not now: no session, not in the world, the player is loading, the partner's passport is not known yet |
| `NCSDK_E_LIMIT` | `Limit` | -3 | Size or rate limit of the mod reached; try later, send less |
| `NCSDK_E_UNSUPPORTED` | `Unsupported` | -4 | This NightCoop build has no such feature |
| `NCSDK_E_OFF` | `SwitchedOff` | -5 | The player switched this feature off |
| `NCSDK_E_DENIED` | `Denied` | -6 | Not yours (not the owner), or the host refused |
| `NCSDK_E_UNKNOWN` | `Unknown` | -7 | No such peer, entity, key or action |
| `NCSDK_E_SIZE` | `TooSmall` | -8 | The output buffer is too small |

## Mods

| C | Script | What | Returns |
|---|---|---|---|
| `registerMod(&info)` | `RegisterMod(id, name, version, protocol, flags)` | Register the mod. C copies the strings and the hooks | C: handle, `0` if refused (bad id, id already registered, 64 mods already, hash collision with another id). Script: `Bool`; calling again with the same id updates name/version/flags/protocol and returns `true`; `false` if the id belongs to a C plugin. The reason is in NightCoop's log |
| `unregisterMod(mod)` | `UnregisterMod(id)` | Remove the mod. Call it on unload | |
| (the `version` field of the table) | `Version()` | `NCSDK_VERSION`. Scripts: `0` if the player switched the SDK off (C: `NightCoopSdkGet` returns `NULL`) | |

`NcSdkModInfo`: `size`, `flags`, `id`, `name`, `version`, `protocol`, `hooks` (may be NULL: poll instead).
Id: ASCII `[a-z0-9._-]`, 3..64 bytes, stable forever. `protocol`: your own wire version; data goes only between equal numbers.

Flags (`NcSdkModInfo.flags`; scripts: `NightCoopSdkModFlag`, combined with `EnumInt(A) | EnumInt(B)`):

| C | Script | Value | Meaning |
|---|---|---|---|
| `NCSDK_MOD_NEEDED_BY_ALL` | `NeededByAll` | 1 | Every player should have it. If a partner lacks it (or has another protocol), both get a note on screen (once per partner and mod) and a log line. Entry is never refused |
| `NCSDK_MOD_LOCAL_ONLY` | `LocalOnly` | 2 | Changes only its own player (looks, HUD, controls): partners need nothing |
| `NCSDK_MOD_CHANGES_WORLD` | `ChangesWorld` | 4 | Changes the shared world (time, weather, NPCs, objects, the population) |
| `NCSDK_MOD_CHANGES_QUESTS` | `ChangesQuests` | 8 | Changes quests, facts or scenes |
| `NCSDK_MOD_ADDS_ITEMS` | `AddsItems` | 16 | Adds items (TweakDB records) a partner without it does not have |
| `NCSDK_MOD_SPAWNS_ENTITIES` | `SpawnsEntities` | 32 | Spawns its own entities (NPCs, props, vehicles) |
| `NCSDK_MOD_HOST_AUTHORITY` | `HostAuthority` | 64 | Its world changes come from the host: guests ask the host by channel or shared state |
| `NCSDK_MOD_USES_CHANNELS` | `UsesChannels` | 256 | **Permission:** `send`; partners' channel messages to the mod |
| `NCSDK_MOD_USES_SHARED_STATE` | `UsesSharedState` | 512 | **Permission:** `stateSet`, `stateGet`; partners' shared state |
| `NCSDK_MOD_USES_ENTITY_STATE` | `UsesEntityState` | 1024 | **Permission:** `entitySetState`, `entityClearState`, `entityAirborne`; partners' entity state |
| `NCSDK_MOD_USES_POSE` | `UsesPose` | 2048 | **Permission:** `poseSet`, `poseClear`; `partnerPose` callbacks and events |
| `NCSDK_MOD_USES_ACTIONS` | `UsesActions` | 4096 | **Permission:** `actionInvoke` |
| `NCSDK_MOD_USES_NPC_REQUESTS` | `UsesNpcRequests` | 8192 | **Permission:** `npcEffect`, `npcRequest`, `npcReply`; partners' requests about NPCs we lead and the answers to ours |
| `NCSDK_MOD_USES_WORLD_TIME` | `UsesWorldTime` | 67108864 | **Permission:** `worldSlow` |
| `NCSDK_MOD_USES_EFFECTS` | `UsesEffects` | 2097152 (`1 << 21`) | **Permission:** `effectShow`, `effectAttach`, `effectStop`, `soundPlay`; partners' mod effects are shown only from a peer whose passport declares it |
| `NCSDK_MOD_USES_REWARDS` | `UsesRewards` | 4194304 (`1 << 22`) | **Permission:** `rewardGrant`; partners' rewards are given only from a peer whose passport declares it |
| `NCSDK_MOD_CHANGES_NPC_LOGIC` | `ChangesNpcLogic` | 1048576 (`1 << 20`) | Changes how NPCs think or fight (AI, balance, police, reactions). An NPC's AI runs only on the machine that leads it, so an NPC of a player with this mod goes to the nearest player only if that player has the mod too (same id and protocol); otherwise they show its copy. Switch `sdk_npc_logic`. See [shared-spawns.md](shared-spawns.md) |
| `NCSDK_MOD_USES_HOOKS` | `UsesHooks` | 262144 | **Permission:** `hookDeclare` (its declarations reach the player's screen) |
| `NCSDK_MOD_USES_FALLBACKS` | `UsesFallbacks` | 16384 | **Permission:** `fallbackSet` — see [content-fallbacks.md](content-fallbacks.md) |

Flags are part of the passport that other players see. They describe what your mod does, and they are
also its **permissions**: a use that is not declared answers `NCSDK_E_DENIED` (one log line), and partners' data of that
kind for the mod is dropped. Besides the `USES_*` flags: `entityShare` / `entityUnshare` / `entityKeepLocal` need
`SPAWNS_ENTITIES`, `factKeepLocal` needs `CHANGES_QUESTS`. Reading functions, `log`, `showMessage`, `pick`, `cleanText` and
`pollEvent` need nothing. See [../SECURITY.md](../SECURITY.md).

## Log, screen, language

Marked "any thread" in the header.

| C | Script | What | Returns |
|---|---|---|---|
| `log(mod, level, text)` | `Log(id, level, text)` | Write a line to NightCoop's log. Levels `NCSDK_LOG_TRACE` 0, `INFO` 1, `WARN` 2, `ERROR` 3 | |
| `showMessage(mod, text, seconds, tone)` | `ShowMessage(id, text, seconds, tone)` | A one-off message at the bottom of the screen, in the game's language font. Tones `NCSDK_TONE_QUIET` 0, `INFO` 1, `WAIT` 2, `URGENT` 3 | C: `int32_t`. Script: `Bool` |
| `pick(ru, en)` | `Pick(ru, en)` | A label in the game's UI language: `ru` for Russian, `en` for English, NightCoop's translation of `en` (if it has one) for the other 17 languages, else `en` | The string. In C the pointer lives while NightCoop is loaded |
| `cleanText(text, maxBytes, out, cap)` | `CleanText(text, maxBytes)` | A text safe to show or log: valid UTF-8, no control, invisible or direction-changing characters, spaces collapsed, at most `maxBytes` (0 — 256). Use it on every text a partner sends you | C: the cleaned length. Script: the text |

`log` and `showMessage` texts are cleaned the same way by NightCoop (no line breaks: a mod's line cannot forge a line of
NightCoop's log).

## Session

| C | Script | What |
|---|---|---|
| `where(&w)` | `InSession()`, `IsHost()`, `InWorld()`, `InHostWorld()`, `LocalPeer()`, `SharedTimeMs()` | The session picture, see below |
| `peers(out, max)` | `Peers()` | The other players of the session. C returns how many there are and fills at most `max`. Script returns `array<Int32>` |
| `peerName(peer, out, cap)` | `PeerName(peer)` | The player's name as in the player list. C returns its length; `out` gets it cut and zero-terminated |
| `peerInOurWorld(peer)` | `PeerInOurWorld(peer)` | Both of us are in the host's world |
| `peerHasMod(mod, peer)` | `PeerHasMod(id, peer)` | `1` the peer registered this mod (same id and protocol); `0` not (or another protocol); `NCSDK_E_STATE` (-2) not known yet |
| `peerModVersion(mod, peer)` | `PeerModVersion(id, peer)` | The peer's version string of this mod. C returns its length or a negative code |

`NcSdkWhere` (set `size` before the call):

| Field | Script | Meaning |
|---|---|---|
| `inSession` | `InSession()` | A session is up (connected; the host: even with no guests yet) |
| `isHost` | `IsHost()` | We are the host (alone, out of a session: 0) |
| `inWorld` | `InWorld()` | Our player is in the world (not the main menu, not loading) |
| `inHostWorld` | `InHostWorld()` | We are in the host's world (a guest who joined it; the host: always when in world) |
| `localPeer` | `LocalPeer()` | Our number; `NCSDK_PEER_NONE` (script: -1) out of a session |
| `peerCount` | `Peers()` length | Other players in the session |
| `sharedTimeMs` | `SharedTimeMs()` | The session clock in ms, the same on every machine; 0 out of a session |

## Channels

Messages of your mod to peers that have it.

| C | Script | What |
|---|---|---|
| `send(mod, to, channel, data, size, flags)` | `Send(id, to, channel, text, reliable)`, `SendBytes(id, to, channel, bytes, reliable)` | Send a message |

- `to`: a peer, the host (`0`) or everyone who has the mod (`NCSDK_TO_ALL` / `-2`). You are never a recipient yourself.
- `channel`: your own numbering, `uint16_t` (scripts: `Int32`).
- Flags: `NCSDK_SEND_RELIABLE` = reliable and ordered per channel (default: unreliable). `NCSDK_SEND_LATEST_ONLY` (C only,
  unreliable): of several messages on the same channel to the same peer in one frame, only the newest leaves at the end of
  the frame. Scripts take a `reliable` flag.
- Size: unreliable up to 1024 bytes, reliable up to 16384 bytes.
- Only peers whose passport lists the same id and protocol receive anything. A guest's message to another guest goes through
  the host, which relays it.
- **Returns** the number of peers it went to (`0`: nobody has the mod), `NCSDK_E_STATE` out of a session or when the passport of
  that very peer is not known yet, `NCSDK_E_UNKNOWN` for a peer not in the session, `NCSDK_E_LIMIT` over the rate,
  `NCSDK_E_ARG` for a bad size.

Receive with `hooks.message` or the `Message` event.

## Shared state

Per mod, key to value, kept by the host, the same for everyone in the session.

| C | Script | What |
|---|---|---|
| `stateSet(mod, key, data, size)` | `SetState(id, key, text)`, `SetStateBytes(id, key, bytes)` | Host: store, call `stateChanged` locally and send to every peer with the mod. Guest: ask the host. `size 0` removes the key |
| (`stateSet` with size 0) | `RemoveState(id, key)` | Remove the key |
| `stateGet(mod, key, out, cap)` | `GetState(id, key)`, `GetStateBytes(id, key)` | The current value. C returns its size, `NCSDK_E_SIZE` if `cap` is smaller, `NCSDK_E_UNKNOWN` if there is no such key |
| | `HasState(id, key)` | Is the key set? |

- **Guest**: the call only sends a request. The host's mod may refuse in `hooks.stateRequest` (scripts cannot refuse: they
  accept everything). When accepted, everybody including the guest gets `stateChanged` with `by` = the guest. When refused,
  nothing changes and both sides write a log line.
- **Joining**: the host sends the whole state of the mod to the guest as soon as it knows the guest has the mod. The guest gets
  one `stateChanged` per key. Becoming a guest first clears the local state (with removal events), then the host's state arrives.
  The end of a session clears the state for everyone (removal events).
- **Out of a session** you are your own host: `stateSet` works locally.
- Limits: key up to 64 bytes UTF-8, value up to 4096 bytes, 256 keys per mod.
- A guest's `stateSet` returns `NCSDK_E_STATE` when the host has not answered the mods check yet, and `NCSDK_E_DENIED` when
  the host does not have the mod.
- A removal arrives as `stateChanged` with size 0 and data `NULL` (script event: `removed`).

## Entities

### Network references

| C | Script | What |
|---|---|---|
| `entityRef(entity, &ref)` | `EntityRef(entity)` | Local entity to network reference. C: `NCSDK_E_UNKNOWN` if NightCoop does not sync it. Script: `Uint64`, `0` if not synced |
| `entityOfRef(&ref)` | `EntityOfRef(ref)` | Reference to our local entity (mirror, copy or our own). `0` if it is not here now (not streamed, not spawned yet) |
| `entityIsMine(entity)` | `EntityIsMine(entity)` | `1` this machine leads it; `0` a partner does (ours is a mirror or copy); `NCSDK_E_UNKNOWN` (-7) not synced by NightCoop, so purely local, so yours |
| `partnerBody(peer)` | `PartnerBody(peer)` | The body of that partner in our world. `0` none now |
| `entityLeader(entity)` | `EntityLeader(entity)` | Who leads it now: the peer whose machine runs its AI or physics (a shared NPC handed to the nearest player, a vehicle's driver). `NCSDK_PEER_NONE` (script `-1`) — not synced by NightCoop. See [shared-spawns.md](shared-spawns.md) |

`NcSdkNetRef`: `kind`, `owner` (who leads it now), `id`.

| Kind (C / script number) | Meaning | `id` |
|---|---|---|
| `NCSDK_NET_PLAYER` 1 | A player's character | the peer (= the owner) |
| `NCSDK_NET_VEHICLE` 2 | A vehicle NightCoop syncs (driven or shared): your own driven car, partners' cars mirrored here | its net id |
| `NCSDK_NET_NPC` 3 | An NPC NightCoop syncs: NPCs you share, copies of partners' NPCs | its net id |
| `NCSDK_NET_SPAWN` 4 | An entity a mod shared with `entityShare` | its share id; the sharing machine's peer number is in the top byte (one reference on every machine, session-scoped) |

Scripts get the reference packed in a `Uint64`: `kind 8 bits | owner 24 bits | id 32 bits` (`NCSDK_PACK_REF`). Owner
`0xFFFFFF` means none.

### Entity state

The main way for a port to say something about an entity: a value of your mod under a `uint16_t` key, attached to an
entity by its owner and delivered to the mirror/copy on every other machine.

| C | Script | What |
|---|---|---|
| `entitySetState(mod, entity, key, data, size, flags)` | `SetEntityState(id, entity, key, text, stream)`, `SetEntityStateBytes(id, entity, key, bytes, stream)` | **Owner only.** Attach the value. `NCSDK_STATE_STREAM` (script `stream = true`): unreliable, only the newest value matters (positions, poses); the default is reliable |
| `entityClearState(mod, entity, key)` | `ClearEntityState(id, entity, key)` | Clear one key everywhere |

- Returns `NCSDK_E_DENIED` if you are not the owner, `NCSDK_E_UNKNOWN` for an entity NightCoop does not sync. Size up to 1024
  bytes either way.
- NightCoop keeps the last value per (mod, entity, key) on the owner and on every receiver. Receivers get `hooks.entityState`
  (script event `EntityState`) with **their** local mirror/copy/body in `entity`.
- If the mirror is not there yet, the value waits and arrives when it appears. If the mirror is recreated (a new `EntityID`
  for the same car, NPC or body), the value is delivered again to the new one. A partner who joins later, or whose passport
  arrives later, gets all current values. A script mod that registers again (every load of a save makes its system anew)
  gets all current values again.
- Your own player is special: values on your player are kept for "our player", not for one `EntityID`, so they survive reloads,
  a new world and a new peer number. Partners get them on your body.
- If the entity is gone at the owner (the car or NPC is no longer synced or despawned), NightCoop forgets its values and
  tells receivers, who get a clear (size 0, `removed`). If the owner loses ownership (an NPC handed to another player), the
  values stay on the receivers until the new owner sets new ones.
- In the hook, `size 0` with `data NULL` means the key was cleared.

### Sharing and keeping local

Details of this part are in the header comments; behavior beyond them is not described here.

| C | Script | What |
|---|---|---|
| `entityShare(mod, entity, flags)` | `ShareEntity(id, entity, follow, animate)` | Share an entity your mod spawned: partners get a copy (template, appearance, transform), you lead it. `NCSDK_SHARE_FOLLOW`: the copy follows your transform (default: placed once, then static). `NCSDK_SHARE_ANIMATE`: an NPC copy plays your animation stream. The reference comes from `entityRef` |
| `entityUnshare(mod, entity)` | `UnshareEntity(id, entity)` | Stop sharing |
| `entityKeepLocal(mod, entity, on)` | `KeepLocal(id, entity, on)` | Keep the entity purely local: NightCoop never adopts, leads, hides or removes it (population, NPC copies, crowd rules). `on 0`: back to normal |
| `entityShare(mod, entity, NCSDK_SHARE_HANDOFF)` | `ShareEntityFlags(id, entity, flags)` | `NCSDK_SHARE_HANDOFF` (4): an NPC goes to the player nearest to it, as an NPC of the world; without it the sharing machine always leads it. A shared **vehicle** is NightCoop's shared vehicle (mirror with seats, doors, driver; whoever drives leads it). Script flags: `NightCoopSdkShareFlag` |

### Vehicles a mod holds in the air

For flight mods: while a vehicle flies, NightCoop's rules for cars on the ground must leave it alone.

| C | Script | What |
|---|---|---|
| `entityAirborne(mod, entity, flags)` | `SetEntityAirborneFlags(id, entity, flags)`, `SetEntityAirborne(id, entity, on)` | Your mod holds this vehicle in the air on this machine; `0` releases. `NCSDK_AIRBORNE_HOLD` (`NightCoopSdkAirborneFlag.Hold`): a mirror of it is not pulled into the game's physics when a car touches it, your own one is not returned home to a partner without your mod. `NCSDK_AIRBORNE_NO_WHEELS` (`.NoWheels`): your mod hides its wheels while it flies |

- The hold of a vehicle you lead is told to every partner, with or without your mod: their mirror goes by the same rules, a
  partner without your mod does not take its wheel (it flies on at your machine, they ride in it), and with `NoWheels` they see
  it without wheels.
- Needs `NCSDK_MOD_USES_ENTITY_STATE`. Release it when the vehicle lands; holds are dropped when the mod unregisters.

Hook `sharedSpawn` / event `SharedSpawn` tells that a partner's shared spawn appeared here (`present 1`, `entity` is our copy)
or is gone (`0`). Hook `spawnLeader` / event `SpawnLeader` tells that a shared spawn changed its leader.
All of it, with the recipe for CET spawns: [shared-spawns.md](shared-spawns.md).

## Effects for partners

| C | Script | What |
|---|---|---|
| `effectShow(mod, path, &at, flags)` | `ShowEffect(id, path, position, orientation, flags)` | Show a world effect (an `.effect` resource: its picture and sound, no damage, no logic) on the machines of the partners in our world, fire and forget. Play it on your own machine yourself. `path` — the resource path as in the archives (printable ASCII, up to `NCSDK_FX_PATH_MAX` 255 bytes, ending in `.effect`); a partner without the resource shows nothing. `NCSDK_FX_IGNORE_TIME_DILATION` (script `NightCoopSdkFxFlag.IgnoreTimeDilation`): not slowed with the world. Needs `NCSDK_MOD_USES_EFFECTS`. Returns how many partners got it, `NCSDK_E_LIMIT` over `NCSDK_FX_PER_S` (10/s, bursts of 20), `NCSDK_E_ARG`, `NCSDK_E_STATE`, `NCSDK_E_OFF` (`sdk_fx`) |

A partner shows it only within 150 m of your player, at most 20 a second from you, and only if the resource is in its
game.

| C | Script | What |
|---|---|---|
| `effectAttach(mod, entity, effect, slot, flags, &number)` | `AttachEffect(id, entity, effect, slot, flags)` | An effect on an entity NightCoop syncs (a player, a vehicle, an NPC, a shared spawn), on each partner's mirror or copy of it: an `.effect` resource attached to `slot` (empty — the root), or with `NCSDK_FX_BY_NAME` (script `NightCoopSdkFxFlag.ByName`) the name of an effect of the entity's template. Gives the effect number (script: the return value) |
| `effectStop(mod, number, breakLoop)` | `StopEffect(id, number, breakLoop)` | Stop it there: at once, or let its loop end |
| `soundPlay(mod, entity, event, stop)` | `PlaySoundOn(id, entity, event, stop)` | A sound event (as `GameObject.PlaySound`) on the partners' mirror or copy; an unknown event is silent there. A sound at a point without an entity — not supported (the game plays sounds on entities) |

All three need `NCSDK_MOD_USES_EFFECTS`, are rate-limited together with `effectShow`, and play nothing on your own machine —
play it there yourself. See [shared-spawns.md](shared-spawns.md).

## Leading an NPC for a while

| C | Script | What |
|---|---|---|
| `npcLease(mod, entity, seconds)` | `LeaseNpc(id, entity, seconds)` | Possession, mind control, an NPC the player drives: `entity` — our body of a synced NPC. Its owner hands it over by NightCoop's usual handoff, and this machine keeps leading it for `seconds` (1..`NCSDK_LEASE_MAX_S` 600; `NCSDK_LEASE_UNTIL_RELEASE`, script `-1` — until released): NightCoop's own handoff rules do not take it away. `0` — release now (the usual rules lead it again). Outcome: hook `spawnLeader` / event `SpawnLeader` for it (ref kind `NCSDK_NET_NPC`, `a` 1 ours now, 0 not handed over within 5 s). Needs `NCSDK_MOD_USES_NPC_REQUESTS`. Switch `sdk_npc_lease` |

## Rewards for partners

| C | Script | What |
|---|---|---|
| `rewardGrant(mod, to, record, quantity, &grant)` | `GrantReward(id, to, record, quantity)` | `quantity` of an item record (`"Items.money"`) created in a partner's own inventory (`to` — a peer, `NCSDK_TO_ALL` — everyone in our world), exactly once. Nothing is taken from you. Needs `NCSDK_MOD_USES_REWARDS`. Returns how many grants started (`grant` — the first number; script: the return value), `0` — nobody in our world |
| hook `reward(ctx, peer, grant, result)` | event `Reward` 18 | The partner's answer: `NCSDK_OK` given, `NCSDK_E_UNKNOWN` no such item record there, `NCSDK_E_DENIED` (no such mod or permission there, a quest item, too far from a guest), `NCSDK_E_LIMIT`, `NCSDK_E_STATE` (not in one world, or no answer for a minute), `NCSDK_E_OFF` |

The partner checks everything: the same mod (id and protocol), your passport, the record (an item, not a quest item),
1..`NCSDK_REWARD_MAX` (9999), the rate (`NCSDK_REWARD_PER_S` 2, bursts of 8), one world, and from a guest — your player within
100 m (the host's world gives quest and gig rewards from anywhere). A lost answer is repeated; the grant is never given
twice. To hand over an item you have, use NightCoop's item transfer (`NightCoopGiveItem`).

## Pose, actions

Brief. When this part is not in the running NightCoop build, the functions return `NCSDK_E_UNSUPPORTED`.

| C | Script | What |
|---|---|---|
| `poseSet(mod, &pose)` | `SetPose(id, valid, worldSpace, head, leftHand, rightHand, aimOrigin, aimDir, crouch, fingers)` | Feed a pose source for the local player's body as partners see it (VR head and hands, motion capture, emote mods). NightCoop sends it (about 30 Hz) and lays it on your body on the partners' machines. `valid` is a set of `NCSDK_POSE_*` bits (script `NightCoopSdkPoseBit`: Head 1, LeftHand 2, RightHand 4, Fingers 8, Aim 16, Crouch 32); transforms are in body space, or world space with `NCSDK_POSE_WORLD_SPACE` (script `worldSpace = true`); 10 finger curls 0..1, left thumb to little, then right |
| `poseClear(mod)` | `ClearPose(id)` | Remove the source |
| `partnerPose(peer, &pose)` | (event `PartnerPose`) | The last pose of a partner's source. `NCSDK_E_UNKNOWN`: they have none |
| `actionList(out, cap)` | `Actions()` | Names of NightCoop's own actions, `\n`-separated (C returns the full length). Known names: `coop_menu`, `story_pull`, `story_without_partner`, `revive_partner`, `save_pull`, `vote_yes`, `vote_no`, `pass_out` |
| `actionAvailable(name)` | `ActionAvailable(name)` | `1` can be done now, `0` not now, `NCSDK_E_UNKNOWN` no such action |
| `actionInvoke(mod, name)` | `InvokeAction(id, name)` | Do it as if its key were pressed. A key held through what it does (`revive_partner`: the revive animation up to the shot) counts as held to the end; what stops the key still stops it (heavy damage, the partner already up). `NCSDK_OK`, `NCSDK_E_STATE` (not now), `NCSDK_E_UNKNOWN` |

## Effects on NPCs a partner leads

The whole story, the table of effects and examples are in [npc-effects.md](npc-effects.md). Need
`NCSDK_MOD_USES_NPC_REQUESTS`.

| C | Script | What | Returns |
|---|---|---|---|
| `npcEffect(mod, entity, &effect)` | `NpcEffect(id, npc, kind, flags, mode, record, value, seconds, point, vector)`, and the short forms `NpcStatus(id, npc, status, flags)`, `NpcRemoveStatus(id, npc, status, flags)`, `NpcDamage(id, npc, attack, value, point, dir, flags, reactType)`, `NpcImpulse(id, npc, point, impulse, radius)`, `NpcSlow(id, npc, dilation, seconds)`, `NpcAttitude(id, npc, attitude, flags)`, `NpcSide(id, npc, side)`, `NpcKill(id, npc, flags)` | Do the effect on the NPC `entity` (our local entity: a copy of a partner's NPC, or ours). Ours, or not synced: done here at once with the game. A partner's: a request to its owner, who does it with the game from our body | `0` done here; `> 0` the request number (the answer: `npcResult` / event `NpcResult`); `< 0` refused (see npc-effects.md) |
| `npcRequest(mod, entity, channel, data, size)` | `NpcRequest(id, npc, channel, text)`, `NpcRequestBytes(id, npc, channel, bytes)` | The general request: the owner's copy of this mod gets `npcRequest` / event `NpcRequest` with its local NPC, does it there and answers | The request number (`> 0`, also for our own NPC: the request then comes to us) or `< 0` |
| `npcReply(mod, request, result, data, size)` | `NpcReply(id, request, result, text)`, `NpcReplyBytes(id, request, result, bytes)` | The owner's answer to a request it got: `result` `NCSDK_OK` or a negative code, data up to 1024 bytes | `NCSDK_OK`, `NCSDK_E_UNKNOWN` (no such open request), `NCSDK_E_ARG` |
| `worldSlow(mod, dilation, seconds)` | `WorldSlow(id, dilation, seconds)` | Declare that this mod slows (0 — stops) our world for `seconds` (<= 120; `dilation` 1 — over), then slow it yourself. Partners near us get it like a Sandevistan; a declared stop is no loading screen; `TimeDilationHelper` profiles pass in co-op. Needs `NCSDK_MOD_USES_WORLD_TIME` | `NCSDK_OK`, `NCSDK_E_ARG`, `NCSDK_E_DENIED`, `NCSDK_E_OFF` |

`NcSdkNpcEffect`: `size`, `kind` (`NCSDK_NPC_STATUS` 1, `UNSTATUS` 2, `DAMAGE` 3, `IMPULSE` 4, `SLOW` 5, `ATTITUDE` 6, `SIDE` 7,
`KILL` 8, `FOLLOW` 9, `GODMODE` 10, `FAKE_DEATH` 11, `DISPOSE` 12, `HIDE` 13; script `NightCoopSdkNpcEffect`; short forms
`NpcFollow(id, npc, follow)`, `NpcGodMode(id, npc, mode)`), `flags` (`NCSDK_NPC_SKIP_LOCAL` 1, `PERCENT` 2, `NONLETHAL` 4, `REACT` 8,
`ALL_PLAYERS` 16, `SHOW_ALWAYS` 32, `NO_ANIM` 64, `NO_RAGDOLL` 128; script `NightCoopSdkNpcFlag`), `mode` (attitude 0 friendly,
1 neutral, 2 hostile; side `NCSDK_NPC_SIDE_JOIN` 0, `_ALL_ENEMIES` 1, `_OWN` 2, script `NightCoopSdkNpcSide`; attack type with
`REACT`), `record` (TweakDBID of a status or an attack), `value` (damage, influence radius, dilation), `seconds` (slow),
`point`, `vector` (world space).

Limits: `NCSDK_NPC_RATE_PER_S` 20 requests per mod per second (bursts 2x; the owner counts per mod and partner),
`NCSDK_NPC_DATA_MAX` 1024 bytes, `NCSDK_NPC_PENDING_MAX` 256 open general requests per mod at the owner, `NCSDK_NPC_NEAR_M`
150 m between our body and the NPC at the owner, `NCSDK_NPC_SLOW_MAX_S` 120 s, `NCSDK_NPC_IMPULSE_MAX` 1000.

## Content a partner may not have

What NightCoop does by itself and how to use these: [content-fallbacks.md](content-fallbacks.md).

| C | Script | What | Returns |
|---|---|---|---|
| `fallbackSet(mod, kind, name, fallback)` | `FallbackSet(id, kind, name, fallback)` | What a partner **without your mod** sees instead of your content `name` of `kind`: the game's own content of the same kind that every player has. `fallback` NULL / `""` clears. Needs `NCSDK_MOD_USES_FALLBACKS` to set (clearing needs nothing). Any thread | `NCSDK_OK`, `NCSDK_E_ARG`, `NCSDK_E_DENIED`, `NCSDK_E_LIMIT` (1024 per mod), `NCSDK_E_OFF` (`sdk_fallbacks`) |
| `contentHere(kind, name)` | `ContentHere(kind, name)` | Is this content in **this** game. Use it on names a partner's copy of your mod sends you | `1` / `0`; `NCSDK_E_STATE` (not known yet), `NCSDK_E_UNSUPPORTED` (weather states), `NCSDK_E_ARG` |
| `peerHasKnownMod(peer, kind, name)` | `PeerHasKnownMod(peer, kind, name)` | Does a partner have a mod that does not use the SDK: where it lies (`kind`) and its folder or file name as in `logs/nightcoop-mods.txt`. From the mods check, only reading | `1` / `0`; `NCSDK_E_STATE` (the check is not over or `mods_check` is off), `NCSDK_E_UNKNOWN` (no such peer), `NCSDK_E_ARG` |

`kind` of `fallbackSet` / `contentHere` (`NCSDK_FALLBACK_*`, script `NightCoopSdkFallbackKind`):

| C | Script | Value | Name is |
|---|---|---|---|
| `NCSDK_FALLBACK_VEHICLE` | `Vehicle` | 1 | a vehicle record, `"Vehicle.v_my_sedan"` |
| `NCSDK_FALLBACK_ITEM` | `Item` | 2 | an item record, `"Items.my_rifle"` (weapons in hands, clothes) |
| `NCSDK_FALLBACK_WEATHER` | `Weather` | 3 | a weather state, `"my_acid_rain"` |
| `NCSDK_FALLBACK_RADIO` | `Radio` | 4 | a radio station: `name` — what the car's `GetRadioReceiverStationName` gives while your mod's station plays; `fallback` and `contentHere` — a game station by its `ERadioStationList` name (`"AGGRO_INDUSTRIAL"`, `"DOWNTEMPO"`; 2.5 adds `"EDGE_RUNNERS"`) |
| `NCSDK_FALLBACK_PHOTO_POSE` | `PhotoPose` | 5 | a photo mode pose by its animation name (`PhotoModePoses.*.animationName`) |

Names: 1..`NCSDK_FALLBACK_NAME_MAX` (128) bytes of printable ASCII. `kind` of `peerHasKnownMod` (`NCSDK_KNOWN_MOD_*`, script
`NightCoopSdkKnownModKind`): `RED4EXT` 0, `REDSCRIPT` 1, `CET` 2, `ARCHIVE` 3, `REDMOD` 4, `TWEAK` 5, `ASI` 6.

## Events and polling

The hooks of a C mod and the events of a script mod carry the same things.

| Hook (C) | Event kind (script `NightCoopSdkEventKind`) | Poll kind (C `NCSDK_POLL_*`) | Fields |
|---|---|---|---|
| `event` | `Session` 1 | `NCSDK_POLL_EVENT` 1 | `a` = `NCSDK_EV_*`, `peer` |
| `message` | `Message` 2 | `NCSDK_POLL_MESSAGE` 2 | `peer` = from, `a` = channel, data |
| `stateChanged` | `State` 3 | `NCSDK_POLL_STATE` 3 | `peer` = by, `key`, data (empty and `removed`: gone) |
| `entityState` | `EntityState` 4 | `NCSDK_POLL_ENTITY_STATE` 4 | `peer` = from, `entity`, `ref`, `a` = key, data |
| `partnerPose` | `PartnerPose` 5 | `NCSDK_POLL_PARTNER_POSE` 5 | `peer`, pose (`valid 0`: gone) |
| `sharedSpawn` | `SharedSpawn` 6 | `NCSDK_POLL_SHARED_SPAWN` 6 | `peer` = owner, `entity`, `ref`, `a` = 1 appeared / 0 gone |
| `npcRequest` | `NpcRequest` 7 | `NCSDK_POLL_NPC_REQUEST` 7 | `peer` = who asks, `entity` = our NPC, `ref`, `a` = channel, `request`, data |
| `npcResult` | `NpcResult` 8 | `NCSDK_POLL_NPC_RESULT` 8 | `peer` = owner, `entity` = our copy, `ref`, `a` = result, `request`, `effect`, data |
| `spawnLeader` | `SpawnLeader` 9 | `NCSDK_POLL_SPAWN_LEADER` 9 | `peer` = the new leader, `entity`, `ref`, `a` = 1 we lead it now / 0 a partner does |
| `reward` | `Reward` 18 | `NCSDK_POLL_REWARD` 18 | `peer` = the recipient, `entity` = the grant number, `a` = the result |

Session events (`NCSDK_EV_*`, script `NightCoopSdkSessionEvent`):

| C | Script | Value | Meaning |
|---|---|---|---|
| `NCSDK_EV_SESSION_START` | `SessionStart` | 1 | A session came up (`peer`: our own number) |
| `NCSDK_EV_SESSION_END` | `SessionEnd` | 2 | The session is over, or we left it |
| `NCSDK_EV_PEER_JOIN` | `PeerJoin` | 3 | A player joined |
| `NCSDK_EV_PEER_LEAVE` | `PeerLeave` | 4 | A player left, or the link is lost for good |
| `NCSDK_EV_PEER_WORLD_IN` | `PeerWorldIn` | 5 | The player is in our world now (both are in the host's world) |
| `NCSDK_EV_PEER_WORLD_OUT` | `PeerWorldOut` | 6 | The player left our world (menu, loading, own campaign) |
| `NCSDK_EV_PEER_MOD` | `PeerHasMod` | 7 | The player has this mod (same id and protocol): channels to them work now |
| `NCSDK_EV_PEER_NO_MOD` | `PeerNoMod` | 8 | The player answered the mods check without this mod, or with another protocol |

Delivery:

- **C with hooks**: callbacks on the game thread, always from the SDK's own frame (the last of NightCoop's frame), never from inside a call of the table. A hook you
  leave `NULL` sends that kind of item to the poll queue instead.
- **Poll queue**: up to 1024 items per mod, the oldest are dropped (counted in the status line, see
  [troubleshooting.md](troubleshooting.md)).
- **Scripts**: `Listen(id, target, n"Function")` makes NightCoop call `target.Function(event)` once per item on the game
  thread instead of queueing. The function takes exactly one `ref<NightCoopSdkEvent>`; `Listen` returns `false` otherwise. The
  target is held weakly: when it dies, items go back to the queue. `Listen(id, null, n"")` stops it.
- **Every frame (scripts)**: `ListenFrame(id, target, n"Function")` makes NightCoop call `target.Function(dt)` on the game
  thread every frame while the player is in a world, after its own frame and your events (C has `hooks.frame`). The function
  takes exactly one `Float` and returns `Void`. Unlike a chain of `DelaySystem` callbacks it keeps running through loads of a
  save; the target is held weakly, so call it again from `OnAttach`. `ListenFrame(id, null, n"")` stops it.
- **Registering in the middle of a session** gives your mod the current picture: `SESSION_START` (if in a session),
  `PEER_JOIN` for each peer, `PEER_WORLD_IN` for each peer in our world, then `PEER_MOD` / `PEER_NO_MOD` as passports come.

| C | Script | What |
|---|---|---|
| `pollEvent(mod, &polled)` | `PollEvent(id)` | The next queued item, or `kind 0` / `null` when empty |
| | `PollEventText(id)` | The same item as one text line, `""` when empty. For Cyber Engine Tweaks without redscript, see [getting-started-cet.md](getting-started-cet.md) |
| | `Listen(id, target, function)` | See above |
| `hooks.frame` | `ListenFrame(id, target, function)` | See above |

`NcSdkPolled` (C): set `size`, optionally give a buffer (`data`, `dataCap`). It fills `kind`, `peer`, `a`, `entity`, `ref`,
`key`, `dataSize` (the full size; the data is cut at `dataCap`), `pose`, `request` and `effect` (NPC
events; `key` is then `"<request>/<effect>"`, for the text form of `PollEventText`) and `value`.

Script event class `NightCoopSdkEvent`: `kind`, `peer`, `a`, `key`, `removed`, `data` (text; empty if not valid UTF-8),
`bytes`, `entity`, `ref`, `poseValid`, `head`, `leftHand`, `rightHand`, `aimOrigin`, `aimDir`, `request`,
`effect`, `value`.

## Functions co-op relies on, keys

What they are for — [do-not-hook.md](do-not-hook.md).

| C | Script | What |
|---|---|---|
| `hookDeclare(mod, cls, fn, address, flags)` | `HookDeclare(id, cls, fn, flags)` | Your mod hooks a game function: a script one by class (script or native name) and short name, or (C only) a native one by the address of its entry with `cls`/`fn` `NULL`. `flags` — exactly one of `NCSDK_HOOK_REPLACES` (1, the game's body does not run) and `NCSDK_HOOK_WRAPS` (2). NightCoop checks it like the overlaps it finds itself: a log line; a replacement of a function co-op relies on — the note on the screen with your mod's name. Returns `1` — co-op relies on it now, `0` — not; `NCSDK_E_ARG` (names not `[A-Za-z_][A-Za-z0-9_]*`, flags), `NCSDK_E_LIMIT` (256 per mod), `NCSDK_E_DENIED` (no `NCSDK_MOD_USES_HOOKS`), `NCSDK_E_OFF` (`hook_overlap` off). Game thread |
| `hookCoopUses(cls, fn, address)` | `HookCoopUses(cls, fn)` | Does co-op rely on it now: a mask of `NCSDK_HOOK_AREA_*` (`NightCoopSdkHookArea`: player 1, NPC 2, population 4, vehicles 8, quests 16, time 32, saves 64, menu 128, world 256, devices 512, other 1024), `0` — no. NightCoop places its hooks during the first minutes (some on switches or at session start): ask when you are about to replace, not once at load. `NCSDK_E_STATE` off the game thread. Needs nothing |
| `keysUsed(out, cap)` | `CoopKeys()` | Keys NightCoop reads itself, one per line: `name\tvk\tIK_name\taction\twhen\trebindable`. A press is not consumed: avoid them for your own hotkeys. Needs nothing, any thread |

## C hooks

`NcSdkHooks`: `size`, `context`, then `frame(ctx, dt)`, `event`, `message`, `stateChanged`, `stateRequest`, `entityState`,
`partnerPose`, `sharedSpawn`, `shutdown`, `npcRequest`, `npcResult`, `spawnLeader`, `reward`, `coopEvent`, `menuItem`,
`voteResult`, `worldRequest`. All optional. See [getting-started-c.md](getting-started-c.md) for when each runs.
`stateRequest` exists only in C.

## The save, the co-op menu, votes and partners

The guest's entry into the host's world by save, your items in NightCoop's co-op menu, votes of mods, what a partner is
doing, co-op events and asks to change the host's world. The script enums of this part are in the module `NightCoop` too
(`import NightCoop.*`).

### Flags they need

| Flag (C) | Script `NightCoopSdkModFlag` | CET `Sdk.FLAG` | Needed by |
|---|---|---|---|
| `NCSDK_MOD_USES_SAVE` (1 << 15) | `UsesSave` 32768 | `USES_SAVE` | `scriptableScope` |
| `NCSDK_MOD_USES_MENU` (1 << 16) | `UsesMenu` 65536 | `USES_MENU` | `menuItemSet` |
| `NCSDK_MOD_USES_VOTES` (1 << 17) | `UsesVotes` 131072 | `USES_VOTES` | `voteStart`; a guest shows the host's vote of a mod only if the host's passport declares it |

Reading a partner's state and co-op events need nothing. `factKeepLocalList` needs `NCSDK_MOD_CHANGES_QUESTS`, as
`factKeepLocal`.

### The guest's entry into the host's world by save

A guest who joins the host's world loads a save NightCoop builds from two: the **world** of the host's save (quest facts,
the journal, scenes, the population, the world's script systems) and the guest's **character** (inventory, stats, perks,
appearance, the character's script systems). See [concepts.md](concepts.md#the-guests-save-in-the-hosts-world).

| C | Script | What |
|---|---|---|
| `factKeepLocal(mod, fact, on)` | `KeepFactLocal(id, fact, on)` | A quest fact each player's own. It also keeps the **guest's own value** at the entry into the host's world (and the session's value at the way home) — switch `sdk_facts_save` |
| `factKeepLocalList(mod, facts, count, on)` | `KeepFactsLocal(id, facts, on)` | The same for a list. Returns how many were accepted (the refused ones are in the log) |
| `scriptableScope(mod, class, scope)` | `ScriptableScope(id, className, scope)` | Where the guest's game takes a `ScriptableSystem` of your mod from. `NCSDK_SCOPE_WORLD` (1): the host's state of it — a system that keeps the world of your mod (its NPCs, places, world events, a gig board, an economy); back in the guest's own campaign it is the campaign's own again. `NCSDK_SCOPE_CHARACTER` (2): each player's own — the default, said aloud. `NCSDK_SCOPE_DEFAULT` (0): drop the word. `class` — the RTTI name: `NameToString(this.GetClassName())`, "Module.Class" for a class in a redscript module. Refused: not a `ScriptableSystem` (`NCSDK_E_UNKNOWN`), one of the game's world systems NightCoop decides, or a class another mod spoke of (`NCSDK_E_DENIED`). 32 per mod. Game thread. Say it right after registering: it counts at the moment the guest enters |

### Items in the co-op menu

Your items appear on NightCoop's own screen: Esc → «Co-op» → «Mods…» (also in the main menu). The list is the game's menu
list, the same widgets NightCoop's items use (mouse, keyboard, gamepad, sounds).

| C | Script | What |
|---|---|---|
| `menuItemSet(mod, key, ru, en, flags)` | `MenuItemSet(id, key, ru, en, flags)` | Add or change an item. `key` — your own, `[a-z0-9._-]` 1..32 bytes; `ru` / `en` — the label (the player's language by `pick()` rules; one empty — the other is used), up to 80 bytes; `flags` — `NCSDK_MENU_*` (script `NightCoopSdkMenuFlag`): `DISABLED` 1 (shown with «not now», a press does not reach you), `IN_SESSION` 2, `HOST_ONLY` 4 (not for guests), `IN_WORLD` 8 (only in the pause menu). 8 items per mod, 32 in all. Any thread |
| `menuItemRemove(mod, key)` | `MenuItemRemove(id, key)` | Remove it. `NCSDK_E_UNKNOWN` — no such item. Unregistering removes all |
| hook `menuItem(ctx, key)` | event kind `MenuItem` 11, `key` | The player pressed the item. Poll kind `NCSDK_POLL_MENU` 11 |

### Votes of mods

The host's copy of your mod asks every player of the host's world a question; they vote in **NightCoop's choice window**
(the dialogue choice window: arrows, F or Enter, NumPad 1..8; who voted for what is written on the options, the title tells
how far the vote is). The window shows the question only when no choice of the game and no vote of NightCoop is on screen;
one vote at a time in a session. The host's voting mode decides («Choice voting: everyone / more than half» in «Extra
settings» of the co-op menu); the host can apply its own choice by holding End, as for NightCoop's choices; NightCoop's
voting time (when the host has one) applies too. Players without your mod vote as well — the decision is the session's.

| C | Script | What |
|---|---|---|
| `voteStart(mod, key, questionRu, questionEn, optionsRu, optionsEn, count)` | `VoteStart(id, key, questionRu, questionEn, optionsRu, optionsEn)` | Host only. 2..8 options; texts in Russian and English (each player sees their own language, never the host's text in another one: give both, an empty one falls back to the other), question up to 160 bytes, options up to 80. `NCSDK_E_STATE`: no session, not in the world, another vote runs; `NCSDK_E_DENIED`: a guest, not declared, the host switched mods off for the session. A guest's copy asks the host's copy by a channel message |
| `voteCancel(mod, key)` | `VoteCancel(id, key)` | Host only: stop it (`NCSDK_VOTE_CANCELLED` everywhere) |
| hook `voteResult(ctx, &result)` | event kind `VoteResult` 12 | The end, on every machine that has the mod. `NcSdkVoteResult`: `how` (`NCSDK_VOTE_*`, script `NightCoopSdkVoteEnd`: `DECIDED` 1, `FORCED` 2 — the host's End, `TIMED_OUT` 3, `CANCELLED` 4, `ABORTED` 5 — the session ended, the host left its world, switched off), `winner` (0-based, -1 none), `options`, `voters`, `votes[]` per option, `key`. Poll kind `NCSDK_POLL_VOTE` 12: `key`, `a` = winner, `value` = how, data — votes per option (a byte each) and last the number of voters |

Recipe: a convoy quest asks before it starts.

    @if(ModuleExists("NightCoop"))
    private func AskConvoy() -> Void {
      let ru: array<String>; ArrayPush(ru, "Едем"); ArrayPush(ru, "Не сейчас");
      let en: array<String>; ArrayPush(en, "Let's go"); ArrayPush(en, "Not now");
      NightCoopSdk.VoteStart("author.convoy", "start", "Начать конвой?", "Start the convoy?", ru, en);
    }
    // in the Listen function: if event.kind == 12 && Equals(event.key, "start") && event.a == 0 { StartConvoy(); }

### What a player is doing

| C | Script | What |
|---|---|---|
| `partnerState(peer, &state)` | `PartnerFlags(peer)`, `PartnerWhere(peer)`, `PartnerHealth(peer)`, `PartnerLevel(peer)`, `PartnerVehicle(peer)` | A partner, or yourself (`NCSDK_PARTNER_SELF`). `flags` — `NCSDK_PARTNER_*` (script `NightCoopSdkPartnerFlag`): `IN_WORLD` 1 (in our world; the body flags are fresh only with it), `DOWN` 2, `COMBAT` 4, `VEHICLE` 8, `WHEEL` 16, `SCENE` 32 (a scene leads them: dialogue, workspot, cutscene), `MENU` 64 (pause menu or a full-screen window), `LINK_LOST` 128, `SELF` 256. `where` — `NCSDK_WHERE_*`: host world 1, main menu 2, loading 3, joining 4, own world 5. `health` 0..1 (-1 not known), `level` (0 not known: it comes with the build stats), `vehicle` — the shared vehicle they sit in (a reference; `vehicleEntity` / `EntityOfRef` — ours of it). `NCSDK_E_STATE` — no session, `NCSDK_E_UNKNOWN` — no such player; script `PartnerFlags` gives -1 then. Game thread |

### Co-op events

They come as session events (`NCSDK_POLL_EVENT`, script kind `Session`), `a` = the event, with `value`, `entity`, `ref`.
A C mod with the hook `coopEvent(ctx, &event)` gets them there with all details (`NcSdkCoopEvent`); without it, `event`
gets event and peer only. Partners count only while in our world.

| C | Script `NightCoopSdkSessionEvent` | `value` | What |
|---|---|---|---|
| `NCSDK_EV_PEER_DOWN` 9 | `PartnerDown` | 1 fell, 0 got up | A partner lies downed / is up (revived, second heart, came to) |
| `NCSDK_EV_TEAM_DOWN` 10 | `TeamDown` | 1 the host loads its last save, 0 no save | Every player is down — the co-op death (nobody dies alone in a session) |
| `NCSDK_EV_PEER_VEHICLE` 11 | `PartnerVehicle` | 1 in, 2 at the wheel, 0 out | `ref`/`entity` — the vehicle (kind `NONE` when NightCoop does not share it) |
| `NCSDK_EV_NPC_KILLED` 12 | `NpcKilled` | — | An NPC NightCoop syncs was killed by a player: `peer` — the killer (may be you), `ref`/`entity` — the NPC. The owner of the NPC tells everyone; purely local NPCs give no event |
| `NCSDK_EV_WORLD_PAUSE` 13 | `WorldPause` | 1 paused, 0 runs | Every player of the host's world is in a menu (NightCoop's shared pause) |
| `NCSDK_EV_HOST_SAVE` 14 | `HostSave` | 1 saved, 2 loaded | The host saved / loaded a save. A good moment to write your own files of the session |
| `NCSDK_EV_TIME_SKIP` 15 | `TimeSkip` | the world's game time after it, s | The host skipped time; the guests' players were fast-forwarded as the game does for the one who skipped |

`NcSdkPolled.value` and `NightCoopSdkEvent.value` carry the value; `PollEventText` has it as the ninth field.

### Asking the host to change the world

The host leads the world's time and weather: a guest's own change is undone within seconds (the host's clock, `weather_host`).
A mod asks instead — right flag `NCSDK_MOD_USES_WORLD_ASK` (1 << 23; script `UsesWorldAsk`, CET `USES_WORLD_ASK`).

| C | Script | What |
|---|---|---|
| `worldAsk(mod, kind, value, text, flags)` | `WorldAsk(id, kind, value, text, vote)` | `kind` (white list): `NCSDK_WORLD_TIME_OF_DAY` 1 — `value` seconds of the day 0..86399, the world goes forward to that time (at most a day, never back); `NCSDK_WORLD_WEATHER` 2 — `text` a weather state (`[a-z0-9_]`, e.g. `24h_weather_rain`), `value` blend seconds 0..600 (the weather stays: its random change is off, as Codeware's `SetWeather` does). The host decides: the hook `worldRequest` of its copy of your mod (C: return 1 — do it, 0 — no), or — with `NCSDK_WORLD_ASK_VOTE` (script `vote = true`), or when the host's copy has no such hook, or the host has no such mod — a vote «yes / no» of every player of the host's world in NightCoop's choice window. The host sets it by the game's own way; the guests get it as the host's time and weather. On the host the ask is done at once (or voted with the flag). Returns the ask's number (> 0); `NCSDK_E_LIMIT` — one ask in 2 seconds (two in a row) |
| hook `worldRequest(ctx, from, kind, value, text)` | — | At the host. Scripts have no such hook: their asks go to a vote |
| event `NCSDK_EV_WORLD_ANSWER` 32 | `Session` event `WorldAnswer` 32 | Only to the mod that asked (on the asker's machine) and to its copy at the host. `peer` — who asked, `value` — `NCSDK_WORLD_ANSWER_*` (script `NightCoopSdkWorldAnswer`): `REFUSED` 0, `DONE` 1, `FAILED` 2 (agreed, but the game did not take it — no such weather state; or the session ended), `BUSY` 3 (another vote runs, asks too often); `entity` — the ask's number |

Not in the list, on purpose: **the pace of time** — the game's `TimeSystem` has no setter of it for scripts (only
`SetGameTimeBySeconds/ByHMS` and time dilation by a reason); mods that change it do so with data, which every player
needs (`NCSDK_MOD_NEEDED_BY_ALL`); and **the world's pause** — it belongs to NightCoop's menu (the world stands when every
player is in a menu).

### Mods without code: the manifest

A mod made only of data (TweakXL records, ArchiveXL, quest phases) can tell NightCoop the same with a file
`<anything>.nightcoop` next to it: [manifest.md](manifest.md).
