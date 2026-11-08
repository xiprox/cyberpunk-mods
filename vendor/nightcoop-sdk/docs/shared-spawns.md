# Shared spawns

What happens to the entities your mod spawns when two or more players play together, and how to make them co-op.
Functions: `entityShare`, `entityUnshare`, `entityKeepLocal`, `entityLeader` (C), `ShareEntity`, `ShareEntityFlags`,
`UnshareEntity`, `KeepLocal`, `EntityLeader` (redscript and CET).

## Why NightCoop has to be told

NightCoop's rules for people and vehicles assume "the same person exists on every machine": an NPC of the host's world
also stands in the guest's world, so NightCoop pairs them up (one leads, the other becomes its mirror), hands the NPC to the
player nearest to it, removes a guest's extra copy, kills it when it died at the host. An entity your mod spawned exists only
on the machine where your mod spawned it. Without a word from your mod NightCoop either does not show it to partners at all
(props, vehicles) or treats it as an NPC of the world (NPCs) — and those rules do not fit it.

| What | NightCoop does without your call |
|---|---|
| An NPC spawned through Codeware `DynamicEntitySystem` (AMM NPCs, most NPC spawners) | Recognized by itself: partners near it see it with its animation, NightCoop never removes it, never makes it a mirror of another NPC, never hands it over, never kills it by a partner's list of the dead |
| Any other NPC (CET `exEntitySpawner`, your own RED4ext spawner) | An NPC of the world: shared, handed over, may be removed at a guest close to the host |
| A vehicle | Shared only while a player sits in it (then it is a player's car) |
| A prop, light, camera | Nothing: partners do not see it |

## Three calls

| C | Script | Use it for |
|---|---|---|
| `entityShare(mod, entity, flags)` | `ShareEntity(id, entity, follow, animate)`, `ShareEntityFlags(id, entity, flags)` | Partners should see it and play with it |
| `entityUnshare(mod, entity)` | `UnshareEntity(id, entity)` | Stop sharing (partners' copies go; an NPC becomes an NPC of the world again) |
| `entityKeepLocal(mod, entity, on)` | `KeepLocal(id, entity, on)` | Only the local player should see it (a photo-mode prop, a preview, a local companion): NightCoop never shares, adopts, hides or removes it |

Your mod needs `NCSDK_MOD_SPAWNS_ENTITIES` in its passport for all three. A mod may share only its own spawns: an entity
with a dynamic `EntityID`, not a crowd pedestrian, not an NPC of a community or a quest, and a prop must be a plain prop
(not a device, loot, a pickup or a trigger) — otherwise `NCSDK_E_DENIED` and one log line.

## Who leads a shared spawn

"Leads" means: its AI or physics runs on that machine, everybody else has a mirror.

| Kind | Who leads | Partners get |
|---|---|---|
| NPC | The machine that shared it. With `NCSDK_SHARE_HANDOFF`: the player nearest to it, exactly as for NPCs of the world (an ambush around a guest far from the host is fought by the guest's game, not by the host's far from its camera) | NightCoop's NPC copy with its animation stream, near them |
| Vehicle | Whoever drives it (as a player's car): sits behind the wheel — leads it; got out and nobody drives — goes back home | NightCoop's vehicle mirror: transform, seats, doors, driver and passengers, lights, damage |
| Prop | The machine that shared it | A copy from your template or record, placed once or following your transform (`NCSDK_SHARE_FOLLOW`) |

Without `NCSDK_SHARE_HANDOFF` an NPC stays led by the machine that shared it — right for a companion whose looks and role your
mod keeps (AMM companions).

While a partner leads your entity, **yours is its mirror**: NightCoop switches its AI or physics off and moves it by the
leader's stream. Do not drive it, teleport it or command its AI; ask the leader instead (a channel message to
`entityLeader(entity)`), or let your mod's copy on the leader's machine do it. You learn about the change:

| C | Script | |
|---|---|---|
| `hooks.spawnLeader(ctx, leader, &ref, entity, mine)` | event `SpawnLeader` (9) | The leader changed: `peer` / `leader` — who leads now, `a` / `mine` — 1 this machine does |
| `NCSDK_POLL_SPAWN_LEADER` (9) | `PollEvent`, `Listen` | The same as a queued item |
| `entityLeader(entity)` | `EntityLeader(entity)` | Who leads it now; `NCSDK_PEER_NONE` (-1 in scripts) — not synced by NightCoop |
| `entityIsMine(entity)` | `EntityIsMine(entity)` | 1 this machine leads it now |

Right after a handoff `entityIsMine` may still give the old answer for a moment (up to a quarter of a second).

## References and entity state

`entityRef` of a shared spawn gives an `NCSDK_NET_SPAWN` reference. Its `id` carries the sharing machine's peer
number in its top byte, so the same reference names the same spawn on every machine of the session — also a vehicle that
NightCoop mirrors as a shared vehicle. It is session-scoped: take `entityRef` again after `NCSDK_EV_SESSION_START`.

`entitySetState` works on shared spawns: the machine that leads it sets values, everybody else gets them on their copy or
mirror (`hooks.entityState`). When the leader changes (handoff, a new driver), the old leader's values stay on every machine
until the new leader sets its own — so write the state your mod needs from the leader's side, not only from the creator's.
Values from a machine that does not lead the spawn are dropped.

## Events at partners

`hooks.sharedSpawn` / event `SharedSpawn` (6): a partner's spawn appeared here (`present 1`, `entity` — our copy, our NPC copy
or our vehicle mirror) or is gone (`0`). A spawn your mod respawns (AMM spawns its NPCs again on every load, with new
`EntityID`s) is a new spawn: share it again right after spawning; partners get "gone" for the old one and "appeared" for the
new one.

## Mods on Cyber Engine Tweaks

CET's `exEntitySpawner.Spawn` leaves no mark on the entity, and the game spawns with the same function itself (the photo
mode's copy of V, entity spawner components, carried objects, vehicle customization), so NightCoop does not guess. Most
CET spawners spawn NPCs and vehicles through Codeware `DynamicEntitySystem` (recognized, see above) and only props, lights,
cameras and workspot entities through `exEntitySpawner` — NightCoop's rules never touch those. When you do spawn an NPC or a
vehicle with `exEntitySpawner`, tell NightCoop right after the spawn:

```lua
local Sdk = require("nightcoop_sdk")
local mod = Sdk.new("yourname.yourmod", "Your Mod", "1.0.0", 1, Sdk.FLAG.SPAWNS_ENTITIES)

local id = exEntitySpawner.Spawn(path, transform, appearance, record)
-- partners should see it (an NPC that goes to the nearest player):
mod:shareEntity(id, Sdk.SHARE.HANDOFF)
-- or: only this player should see it
-- mod:keepLocal(id, true)
```

## Vehicles in detail

- A shared vehicle is NightCoop's shared vehicle while a partner is near it (about 150 m): the partner's mirror is spawned from
  your vehicle's record. A partner without your vehicle's record gets no mirror (or a stand-in, depending on the NightCoop
  build); the mirror is never the partner's own vehicle of the same record.
- Seats: the four standard seats (`seat_front_left` is the driver). Not synchronized: trailers and cargo, windows, neon, trunk
  and hood, non-standard seats.
- On a mirror NightCoop switches the physics off and makes it invulnerable: damage and destruction come from the leader.
- `entityUnshare` makes it an ordinary vehicle again (shared only while a player sits in it).

## Effects and sounds on entities

`effectAttach` puts an effect on an entity NightCoop syncs — a partner's body, a vehicle, an NPC, a shared spawn — on each
partner's mirror or copy of it: an `.effect` resource attached to a slot of the entity (empty slot — its root), or with
`NCSDK_FX_BY_NAME` an effect of the entity's own template by name (as `GameObjectEffectHelper.StartEffectEvent`). Keep the
number it gives and stop it with `effectStop` (at once, or let its loop end). `soundPlay` plays or stops a sound event on the
partners' mirror or copy of an entity (as `GameObject.PlaySound`). Play both on your own entity yourself. A partner without
the resource, the effect name or the sound event shows or hears nothing. A sound at a point without an entity is not
supported: the game plays sounds on entities — put it on your player or a shared spawn.

## Rewards for partners

A gig, quest or port mod that pays the players gives each partner their share with `rewardGrant` (`mod:grantReward(to,
record, quantity)`): the item (an item record of TweakDB, `"Items.money"` for eddies) is created in that player's own
inventory, exactly once — a lost answer is repeated and never gives twice. The answer comes as hook `reward` / event `Reward`
(18). The partner's NightCoop gives it only if it has your mod too (same id and protocol), your passport declares
`NCSDK_MOD_USES_REWARDS`, the record is an item there and not a quest item, the quantity is 1..9999, the rate holds (2 a
second, bursts of 8), you are both in the host's world, and — from a guest — your player is within 100 m (a gift); the
host's world gives rewards from anywhere. Nothing is taken from your inventory; to hand over what you have, use NightCoop's
item transfer.

## Leading an NPC for a while

A possession or mind-control mod needs the possessed NPC's AI on its own machine. `npcLease(mod, entity, seconds)` asks the
NPC's owner for it: the owner hands it over by NightCoop's usual handoff, and your machine keeps leading it for the given
time (or until you release it with `0`) — NightCoop's own rules (distance, companions in combat, scenes, a partner's grapple)
do not take it away meanwhile. After that the usual rules lead it again (it goes back to the player nearest to it). The
outcome comes as `spawnLeader` for that NPC (ref kind `NCSDK_NET_NPC`): `mine 1` — yours now, `0` — the owner did not hand it
over within 5 seconds (its NightCoop refused: switch `sdk_npc_lease` off there, a mod's NPC without `NCSDK_SHARE_HANDOFF`,
`npc_host_only` on the host, it is dead or a crowd pedestrian). Needs `NCSDK_MOD_USES_NPC_REQUESTS`.

## Mods that change NPC logic

NightCoop runs an NPC's AI only on the machine that leads it; partners show its copy (no AI). A mod that changes how NPCs
think or fight (AI overhauls, balance, police, reactions) works only for the NPCs its player leads. Declare it with
`NCSDK_MOD_CHANGES_NPC_LOGIC` (script `NightCoopSdkModFlag.ChangesNpcLogic`, Lua `Sdk.FLAG.CHANGES_NPC_LOGIC`): an NPC of a
player who has your mod is then handed to the nearest player only if that player has your mod too (same id and protocol);
a player without it keeps showing the copy. An NPC your mod shared with `NCSDK_SHARE_HANDOFF` goes only to players who
have your mod, with or without the flag.

For AI mods that do not use the SDK the host can keep every NPC of its world: switch `npc_host_only` (off by default) —
the host never hands its NPCs to guests (by distance, companions in combat, scenes, a guest's grapple), guests show copies.

## Effects for partners

NightCoop shows partners the effects of the players' attacks and abilities (the game's effect nodes). An effect your mod
spawns itself (`FxSystem.SpawnEffect`) is only on your screen. Show it to partners with `effectShow` / `ShowEffect` /
`mod:showEffect(path, position, orientation, flags)`: the partners in your world spawn the same resource at the same place
(picture and sound, no damage, no logic), fire and forget. Declare `NCSDK_MOD_USES_EFFECTS`. A partner shows it only within
150 m of your player, at most 20 a second from you (your mod: 10 a second, bursts of 20), and only if the resource is in
its game (a mod with its own `.effect` files: a partner without them sees nothing).

## Limits (NightCoop's side, partners' data is untrusted)

Per partner: 32 NPCs, 8 vehicles, 64 props announced; 64 new at once, then 8 per second; copies are placed only within
100 m of the owner's body. A spawn number that does not carry the sender's peer number is dropped. See
[../SECURITY.md](../SECURITY.md); the switches of these features are in [troubleshooting.md](troubleshooting.md#switches).
