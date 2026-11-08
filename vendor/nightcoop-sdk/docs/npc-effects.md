# Effects on NPCs a partner leads

C: `npcEffect`, `npcRequest`, `npcReply`; scripts:
`NpcEffect`, `NpcStatus`, `NpcRemoveStatus`, `NpcDamage`, `NpcImpulse`, `NpcSlow`, `NpcAttitude`, `NpcSide`, `NpcKill`,
`NpcFollow`, `NpcGodMode`, `NpcRequest`, `NpcReply`, and `WorldSlow` for your own world's time; guard them with `@if(ModuleExists("NightCoop"))`. Permission: `NCSDK_MOD_USES_NPC_REQUESTS` (script flag
`UsesNpcRequests`, 8192).

## Why

Every NPC NightCoop syncs is led by **one** player — its owner, usually the host. The others see a *copy*: an NPC without
its own AI that only plays what the owner's NPC does (position, animation, health, death). Whatever your mod does to a copy
with its own script is local:

- a status effect on a copy shows only on your screen, and the owner's NPC never had it — its AI does not react;
- a hit, a push, a slow-down or a change of side on a copy is overwritten by the owner's stream within a frame;
- `Kill()` on a copy does nothing for anybody else; the NPC keeps fighting at the owner.

So a quickhack mod that slows the target (CHRONOLOCK), pushes it (POLARITY), makes it fight for you (Possession) or burns it
from inside (SYSTEM FRY), a weapon that lifts enemies (REPULSOR) — all work in single player and do nothing in a session,
unless the owner of the NPC does the same thing. These calls ask the owner to do it **with the game, as an action of your
player**: there, the instigator is your player's body, so the NPC's AI turns on you, its death is yours (kill credit, XP,
"on kill" effects), and everybody sees the result on their copies.

## What NightCoop already carries by itself

You do not need these calls for what goes through the game's own paths:

| What | How it reaches the owner |
|---|---|
| A quickhack (an `ObjectAction` record with `startEffects` / `completionEffects`, also your mod's own TweakXL records) | NightCoop sends the action record and phase; the owner applies the record's status effects to its NPC from your body. Custom effector classes of your mod run there if the owner has your mod |
| Damage of your weapon, grenade, melee or of a status ticking on the copy from your player | Your game computes the hit on the copy; NightCoop sends it to the owner as a damage claim, the owner puts it into its own damage pipeline from your body (reaction, threat, death by your hand) |
| The owner's NPC's health, death and its killer, ragdoll, its own time dilation, its attitude to each player | The owner's snapshots and stream; copies follow |

## What you have to send

Anything your **script** does to an NPC beyond the record: `ApplyStatusEffect` in your redscript, `QueueEvent` of a ragdoll or
an impulse, `SetIndividualTimeDilation`, `AttitudeAgent.SetAttitudeTowards` / `SetAttitudeGroup`, `Kill`, damage you compute
yourself. Call the matching function instead of (or, for statuses, in addition to) doing it on the copy.

| Effect (C kind / script) | What the owner does with the game | What the partners see |
|---|---|---|
| `NCSDK_NPC_STATUS` / `NpcStatus` | `StatusEffectSystem.ApplyStatusEffect(npc, record, your body)` | The status on their copies if its type is only a look (burning, short circuit, EMP, jam, poison, shock, blindness, staggers), or any type with `NCSDK_NPC_SHOW_ALWAYS` (if they have your mod) |
| `NCSDK_NPC_UNSTATUS` / `NpcRemoveStatus` | `RemoveStatusEffect` (one stack) | Removed from the copies too |
| `NCSDK_NPC_DAMAGE` / `NpcDamage` | A hit of your attack record from your body through its damage pipeline (or, without a record, a health write by your hand) — the same path as your weapon's damage claims | Health and the reaction by the owner's stream |
| `NCSDK_NPC_IMPULSE` / `NpcImpulse` | A forced ragdoll and the impulse 0.1 s later, as the game's hit reactions do | Their copy falls with the owner's NPC and gets the same push |
| `NCSDK_NPC_SLOW` / `NpcSlow` | `SetIndividualTimeDilation` (value 1: `UnsetIndividualTimeDilation`; value 0 — frozen, set as 1e-6 like the game's own stops) | The NPC's own time by its snapshots (a frozen NPC too) |
| `NCSDK_NPC_ATTITUDE` / `NpcAttitude` | `SetAttitudeTowards(your body, attitude)` (or to every player) — written only when it changes | Each player's copy gets the NPC's attitude to that player (name colour, health bar, hostility) |
| `NCSDK_NPC_SIDE` / `NpcSide` | `SetAttitudeGroup`: your side (your attitude group, friendly to you — as the game's ally quickhack), hostile to everyone (as its madness), or back to its own group | Attitudes by snapshots; the NPC's fights with other NPCs are its owner's AI, the copies show its aim and shots |
| `NCSDK_NPC_KILL` / `NpcKill` | `Record1DamageInHistory(your body)` + `NPCPuppet.Kill(your body)` — if the game would let it die (not a boss in a fight, no god mode) | Its death, and you are its killer: your copy dies by your hand (XP, "on kill" effects, wanted level) |
| `NCSDK_NPC_FOLLOW` / `NpcFollow` | `AIComponent.SetAIRole(AIFollowerRole)` with your body as the follow target, as companion mods and AMM do (`mode` 0 / `false`: a plain `AIRole`, no role) | It walks and fights with you; copies show it. The role **stays with the NPC**: NightCoop hands an NPC to the player nearest to it, so a follower comes to lead to you — whoever leads it sets the role again, and only while you are in their world |
| `NCSDK_NPC_GODMODE` / `NpcGodMode` | `GodModeSystem.AddGodMode` under NightCoop's own source (`mode` 1 immortal, 2 invulnerable; 0 removes it) | Stays with the NPC like FOLLOW. Any god mode of the owner's NPC (yours, a quest's, AMM's immortal companions) also goes to every copy, so a lethal hit on an immortal NPC does not drop the copy |
| `NCSDK_NPC_FAKE_DEATH` | `ScriptedPuppet.SendAIDeathSignal` (AMM "Fake Die") | Its fall by the owner's animation stream |
| `NCSDK_NPC_DISPOSE` | `Dispose()` (AMM "Despawn") | Its copies go with the owner's "gone" word |
| `NCSDK_NPC_HIDE` | `gamePuppet.HideIrreversibly` | Hidden on every copy too |

How the call answers:

- **Your own NPC** (you lead it), or an NPC NightCoop does not sync: done here at once, the same way (instigator: your
  player). Returns `NCSDK_OK` (0). The partners' copies get the look as above.
- **A partner's NPC**: a request to its owner. Returns the request number (> 0). The answer comes as `hooks.npcResult` / the
  event `NpcResult` (`NCSDK_POLL_NPC_RESULT`, 8) with that number in `request`, the effect in `effect` and the result in `a`:
  `NCSDK_OK`, or `NCSDK_E_UNKNOWN` (the record is not in their game, the NPC is gone), `NCSDK_E_DENIED` (they do not lead it
  any more — look it up again with `entityRef` and ask the new owner), `NCSDK_E_STATE` (your body is not near it, it is dead,
  the game does not ragdoll it or does not let it die now), `NCSDK_E_LIMIT`, `NCSDK_E_OFF`.
- **Refused at once** (negative): `NCSDK_E_ARG` (a bad effect, or the entity is a player's body or a vehicle),
  `NCSDK_E_UNSUPPORTED` (a kind or flag this NightCoop does not know), `NCSDK_E_UNKNOWN` (no such entity, the record is not in
  your game), `NCSDK_E_STATE` (not in the same world with the owner, the owner's passport is not known yet),
  `NCSDK_E_DENIED` (no `USES_NPC_REQUESTS`, the owner has not your mod with your `protocol`, or the host switched mods off for
  the session), `NCSDK_E_LIMIT` (over `NCSDK_NPC_RATE_PER_S`), `NCSDK_E_OFF` (the player's switch `sdk_npc`).

**When you leave.** A status or a slow-down the owner put on its NPC from your body comes off when you leave its world (main
menu, a load, your own campaign, the end of the session): your body — its instigator — is gone. A follow role waits for you
to come back; a god mode and a follow role of a player who left the session are removed.

The owner checks every request again on its side (a partner's data is untrusted, see [../SECURITY.md](../SECURITY.md)): it
leads that NPC, both of you are in its world, your body is there and within `NCSDK_NPC_NEAR_M` (150 m), the record is in its
TweakDB with the right class (`StatusEffect` / `Attack`), and the rate per mod and partner.

### Status effects: the copy, the owner and damage ticks

By default `NpcStatus` also puts the status on **your own copy**, from your player — the way the game does for a quickhack.
That gives you the look right away, and if the status deals damage over time, its ticks on your copy are *your* hits: they
reach the owner as your damage claims. The owner's own ticks of a status from your body write no health (that would count it
twice), exactly as for quickhacks. If your mod already applied the status to the copy itself (for example the status comes
from your quickhack record), pass `NCSDK_NPC_SKIP_LOCAL` (script `NightCoopSdkNpcFlag.SkipLocal`).

### Damage

`value` is health points as **you** see them on your copy; NightCoop turns it into a share of the copy's max health and the
owner takes the same share of its NPC (machines may differ in difficulty and level). With `NCSDK_NPC_PERCENT` it is a
percent. With an attack `record`, the owner builds a real hit of that attack from your body (its type, flags and effects,
the NPC's hit reaction); without one, it writes the health directly, and `NCSDK_NPC_REACT` with `mode` = a
`gamedataAttackType` gives a hit reaction. `point` and `vector` are world space at the call (point (0,0,0) — the chest);
NightCoop sends the point relative to the NPC, since your copy may lag behind the owner's NPC by metres.
`NCSDK_NPC_NONLETHAL` defeats instead of killing.

### Damage of your drones, turrets and spawns

NightCoop sends the owner only hits whose instigator is **your player**: the game's damage pipeline on your machine counts them,
the owner applies them. A hit of your mod's drone, turret or spawned NPC on a copy is not your player's — it stays on your
copy (the owner never hears of it). Compute it in your mod and send it with `NpcDamage` (with the attack record of the drone's
weapon, so the NPC reacts as to that weapon); the owner applies it from your body, and the kill is yours.

## Your own world's time: `worldSlow`

A mod that slows or stops the **whole world** (bullet time, a stasis field, a time-stop implant, AMM's freeze) does it on its
own machine with `TimeSystem.SetTimeDilation` or `TimeDilationHelper`. In a session that is a problem: partners keep their
time and see you run in slow motion, NightCoop takes a world standing still for more than 0.3 s for a loading screen and
holds the whole session in a loading pause, and in co-op `TimeDilationHelper` profiles are switched off (the game's own
multiplayer rule, kept by NightCoop for menus).

Declare it first: `worldSlow(mod, dilation, seconds)` (script `WorldSlow(id, dilation, seconds)`, Lua `mod:worldSlow(d, s)`;
needs `NCSDK_MOD_USES_WORLD_TIME`, `UsesWorldTime`, 67108864), `dilation` 0..1 (0 — stopped) for up to
`NCSDK_WORLD_SLOW_MAX_S` (120) seconds; `dilation` 1 when it is over. Then slow the world yourself as you do in single
player. While it is declared:

- partners near you (within NightCoop's implant radius) get the same slow-down as from a Sandevistan: their world slows,
  your body moves at your pace there; a stop reaches them as almost stopped (0.02);
- a world standing still this way is no loading screen — neither yours nor theirs;
- `TimeDilationHelper.SetTimeDilationWithProfile` is not switched off for you.

It is your own world only: to freeze one NPC use `NpcSlow` with 0.

## The general request: your own logic on the owner's machine

When no fixed effect fits — your mod tracks its own state per NPC, spawns a field around it, plays a sound on it, chains a
hack to its squad — send your own message about the NPC to the machine that leads it:

1. `npcRequest(mod, entity, channel, data, size)` (script `NpcRequest(id, npc, channel, text)` / `NpcRequestBytes`). Always
   returns a request number (> 0): also for your own NPC, then the request comes to your own mod on this machine. One code
   path for every NPC.
2. The owner's copy of your mod gets `hooks.npcRequest` / the event `NpcRequest` (`NCSDK_POLL_NPC_REQUEST`, 7) with **its**
   local NPC in `entity`, the asker in `peer`, your `channel` in `a`, your data, and a request number of its own in
   `request`. Do it there with the game.
3. It answers with `npcReply(mod, request, result, data, size)` (script `NpcReply(id, request, result, text)`); you get the
   `NpcResult` event with your request number, `effect` 0 and its data.

Answer every request once. The owner keeps at most `NCSDK_NPC_PENDING_MAX` (256) open requests per mod; an older one is
answered `NCSDK_E_LIMIT` for you. Requests of a player who left are forgotten. Data is at most `NCSDK_NPC_DATA_MAX` (1024)
bytes each way. Treat the data like any partner data: check every value.

## Example 1 (redscript): a quickhack that slows its target

Your quickhack record already puts its status on the copy (so `SkipLocal`); the slow-down your effector did on the copy is
asked from the owner.

    @if(ModuleExists("NightCoop"))
    import NightCoop.*

    // Your effector, after the status is on the target
    @if(ModuleExists("NightCoop"))
    private func CoopSlow(target: ref<NPCPuppet>, status: TweakDBID) -> Void {
      let id = "you.chronolock";
      NightCoopSdk.NpcStatus(id, target.GetEntityID(), status, EnumInt(NightCoopSdkNpcFlag.SkipLocal));
      NightCoopSdk.NpcSlow(id, target.GetEntityID(), 0.2, 6.0);
    }

    @if(!ModuleExists("NightCoop"))
    private func CoopSlow(target: ref<NPCPuppet>, status: TweakDBID) -> Void {
      target.SetIndividualTimeDilation(n"ChronoLock", 0.2, 6.0); // without NightCoop
    }

Register once with the flag: `NightCoopSdk.RegisterMod("you.chronolock", "Chronolock", "1.2", 1,
EnumInt(NightCoopSdkModFlag.NeededByAll) | EnumInt(NightCoopSdkModFlag.UsesNpcRequests))`.

## Example 2 (redscript): your own logic through the general request

A "possession" hack: the owner's mod turns the NPC to your side and starts its own timer to give it back.

    @if(ModuleExists("NightCoop"))
    public class PossessionCoop extends ScriptableSystem {
      private let m_id: String = "you.possession";

      private func OnAttach() -> Void {
        NightCoopSdk.RegisterMod(this.m_id, "Possession", "2.0", 1,
          EnumInt(NightCoopSdkModFlag.NeededByAll) | EnumInt(NightCoopSdkModFlag.UsesNpcRequests));
        NightCoopSdk.Listen(this.m_id, this, n"OnCoopEvent");
      }

      // Called by your hack on any NPC — a copy or your own
      public func Possess(npc: ref<NPCPuppet>, seconds: Float) -> Void {
        NightCoopSdk.NpcRequest(this.m_id, npc.GetEntityID(), 1, FloatToString(seconds));
      }

      private cb func OnCoopEvent(ev: ref<NightCoopSdkEvent>) -> Bool {
        if ev.kind == EnumInt(NightCoopSdkEventKind.NpcRequest) && ev.a == 1 {
          // Here we lead the NPC: do it with the game, the asker's side
          let seconds = StringToFloat(ev.data);
          if seconds <= 0.0 || seconds > 60.0 {
            NightCoopSdk.NpcReply(this.m_id, ev.request, EnumInt(NightCoopSdkResult.BadArgument), "");
            return true;
          }
          NightCoopSdk.NpcSide(this.m_id, ev.entity, EnumInt(NightCoopSdkNpcSide.Join)); // ours: done at once
          this.StartRelease(ev.entity, seconds);                                         // your own timer, here
          NightCoopSdk.NpcReply(this.m_id, ev.request, 0, "");
        } else if ev.kind == EnumInt(NightCoopSdkEventKind.NpcResult) && ev.a != 0 {
          NightCoopSdk.Log(this.m_id, 1, "possession refused: " + IntToString(ev.a));
        }
        return true;
      }

      private func StartRelease(npc: EntityID, seconds: Float) -> Void { /* DelaySystem → NpcSide(..., Own) */ }
    }

Note that `NpcSide` on the owner's machine is a call on **its own** NPC: done at once, from the owner's player. If the side
must be the *asker's*, use the effect directly from the asker (`NpcSide` on the copy) — the owner then does it from the
asker's body; the general request is for logic NightCoop has no effect for.

## C

    NcSdkNpcEffect e = {sizeof e};
    e.kind = NCSDK_NPC_IMPULSE;
    e.point = hitPoint;                 /* world */
    e.vector = (NcSdkVec3){dir.x * 40, dir.y * 40, 12};
    e.value = 2.0f;                     /* influence radius, m */
    int32_t r = api->npcEffect(mod, npcEntityHash, &e);
    /* r == 0: done here; r > 0: wait for hooks.npcResult(..., aRequest == r, ...) */

`NcSdkHooks.npcRequest(ctx, from, entity, ref, request, channel, data, size)` and
`npcResult(ctx, owner, entity, ref, request, effect, result, data, size)` are in the hooks; without them the items
go to the poll queue (`NcSdkPolled.request`, `NcSdkPolled.effect`).

## CET (Lua)

    local mod = Sdk.new("you.repulsor", "Repulsor", "1.0", 1, Sdk.FLAG.NEEDED_BY_ALL + Sdk.FLAG.USES_NPC_REQUESTS)
    -- on hit:
    mod:npcImpulse(npc:GetEntityID(), {pos.x, pos.y, pos.z}, {0, 0, 25}, 3)
    mod:npcStatus(npc:GetEntityID(), "BaseStatusEffect.Stun")
    -- in onUpdate: mod:poll(function(ev) if ev.kind == Sdk.EVENT.NPC_RESULT then ... ev.request, ev.a ... end end)

## What is not here

- **Handing the NPC to you.** A possessed NPC stays with its owner: its AI is the owner's, you steer it by requests. A mod that
  wants to *drive* an NPC every frame (Possession's direct control) should ask once with the general request and let the
  owner's copy of the mod run it there. Handing the NPC over for the time of the possession is not in this version.
- **Copies of shared spawns** (`entityShare`) get statuses and hiding, not the push (their ragdoll is the mod's).

The switches that turn these parts off are in [troubleshooting.md](troubleshooting.md#switches).
