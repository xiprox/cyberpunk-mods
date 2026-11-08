// SPDX-License-Identifier: MIT — Copyright (c) 2026 NightCoop (see sdk/LICENSE)
// NightCoop SDK for redscript mods — version 1: the class NightCoopSdk and its event.
//
// Top level on purpose (no `module`): redscript names a class declared in a module "Module.Class", and the game would
// look for a native class "NightCoop.NightCoopSdk" that does not exist. The enums are in NightCoopSdk.reds (module
// NightCoop): `import NightCoop.*` brings them, `@if(ModuleExists("NightCoop"))` tells whether NightCoop is here.
//
// Both files ship inside NightCoop's plugin folder; NightCoop.dll adds them to the redscript compilation itself, only when
// it really loads. Do not copy them into your mod (two definitions break the compilation of every script).
//
// Read the header comment of sdk/include/nightcoop_sdk.h (sessions, ownership, limits) and sdk/docs/.

// One item of a mod's events (PollEvent, or the argument of the Listen function). A scripted class: NightCoop creates it.
public class NightCoopSdkEvent extends IScriptable {
  public let kind: Int32;            // NightCoopSdkEventKind
  public let peer: Int32;
  public let a: Int32;
  public let key: String;
  public let removed: Bool;
  public let data: String;           // the payload as UTF-8 text (empty if it is not valid UTF-8)
  public let bytes: array<Uint8>;    // the payload as bytes
  public let entity: EntityID;
  public let ref: Uint64;            // NCSDK_PACK_REF: kind 8 | owner 24 | id 32
  public let poseValid: Int32;
  public let head: Transform;
  public let leftHand: Transform;
  public let rightHand: Transform;
  public let aimOrigin: Vector4;
  public let aimDir: Vector4;
  // NpcRequest (7) and NpcResult (8) events
  public let request: Int32;         // the request number
  public let effect: Int32;          // NpcResult: NightCoopSdkNpcEffect of NpcEffect/NpcStatus/..., 0 — a general NpcRequest
  // co-op events (kind Session, a 9..15) — their value; votes (kind VoteResult) — how it ended
  public let value: Int32;
}

public native class NightCoopSdk extends IScriptable {
  // ---------------------------------------------------------------- availability and mods
  // NCSDK_VERSION; 0 — NightCoop's SDK is switched off by the player (switch "sdk").
  public static native func Version() -> Int32;
  public static native func RegisterMod(id: String, name: String, version: String, protocol: Int32, flags: Int32) -> Bool;
  public static native func UnregisterMod(id: String) -> Void;
  // Deliver this mod's events by calling target.function(event: ref<NightCoopSdkEvent>) on the game thread instead of
  // queueing them for PollEvent. A null target stops it.
  public static native func Listen(id: String, target: ref<IScriptable>, function: CName) -> Bool;
  // The next queued event, or null.
  public static native func PollEvent(id: String) -> ref<NightCoopSdkEvent>;

  // ---------------------------------------------------------------- log, screen, language
  public static native func Log(id: String, level: Int32, text: String) -> Void;
  public static native func ShowMessage(id: String, text: String, seconds: Float, tone: Int32) -> Bool;
  public static native func Pick(ru: String, en: String) -> String;

  // ---------------------------------------------------------------- session
  public static native func InSession() -> Bool;
  public static native func IsHost() -> Bool;
  public static native func InWorld() -> Bool;
  public static native func InHostWorld() -> Bool;
  public static native func LocalPeer() -> Int32;      // -1 out of session
  public static native func Peers() -> array<Int32>;
  public static native func PeerName(peer: Int32) -> String;
  public static native func PeerInOurWorld(peer: Int32) -> Bool;
  public static native func PeerHasMod(id: String, peer: Int32) -> Int32; // 1 yes, 0 no, -2 not known yet
  public static native func PeerModVersion(id: String, peer: Int32) -> String;
  public static native func SharedTimeMs() -> Uint64;

  // ---------------------------------------------------------------- channels (to: a peer, 0 the host, -2 everyone)
  public static native func Send(id: String, to: Int32, channel: Int32, data: String, reliable: Bool) -> Int32;
  public static native func SendBytes(id: String, to: Int32, channel: Int32, data: array<Uint8>, reliable: Bool) -> Int32;

  // ---------------------------------------------------------------- shared state, kept by the host
  public static native func SetState(id: String, key: String, value: String) -> Int32;
  public static native func SetStateBytes(id: String, key: String, value: array<Uint8>) -> Int32;
  public static native func RemoveState(id: String, key: String) -> Int32;
  public static native func HasState(id: String, key: String) -> Bool;
  public static native func GetState(id: String, key: String) -> String;
  public static native func GetStateBytes(id: String, key: String) -> array<Uint8>;

  // ---------------------------------------------------------------- entities
  public static native func EntityRef(entity: EntityID) -> Uint64;     // 0 — not synced by NightCoop
  public static native func EntityOfRef(ref: Uint64) -> EntityID;
  public static native func EntityIsMine(entity: EntityID) -> Int32;   // 1 mine, 0 a partner's, -7 not synced (local)
  public static native func PartnerBody(peer: Int32) -> EntityID;
  public static native func SetEntityState(id: String, entity: EntityID, key: Int32, value: String, stream: Bool) -> Int32;
  public static native func SetEntityStateBytes(id: String, entity: EntityID, key: Int32, value: array<Uint8>, stream: Bool) -> Int32;
  public static native func ClearEntityState(id: String, entity: EntityID, key: Int32) -> Int32;
  public static native func ShareEntity(id: String, entity: EntityID, follow: Bool, animate: Bool) -> Int32;
  public static native func UnshareEntity(id: String, entity: EntityID) -> Int32;
  public static native func KeepLocal(id: String, entity: EntityID, on: Bool) -> Int32;

  // ---------------------------------------------------------------- pose source of our own player
  // valid — NightCoopSdkPoseBit; transforms in world space (worldSpace true) or body space; fingers — 10 curls 0..1
  // (left thumb..little, right thumb..little), may be empty.
  public static native func SetPose(id: String, valid: Int32, worldSpace: Bool, head: Transform, leftHand: Transform,
    rightHand: Transform, aimOrigin: Vector4, aimDir: Vector4, crouch: Float, fingers: array<Float>) -> Int32;
  public static native func ClearPose(id: String) -> Void;

  // ---------------------------------------------------------------- NightCoop's actions by name
  public static native func Actions() -> array<String>;
  public static native func ActionAvailable(name: String) -> Int32;    // 1 now, 0 not now, -7 unknown
  public static native func InvokeAction(id: String, name: String) -> Int32;

  // ---------------------------------------------------------------- events as text
  // The next queued event as one text line, "" when the queue is empty — for CET without redscript (the event class is
  // scripted) and for Lua, where byte arrays are slow. Tab-separated: kind, peer, a, entity hash, ref (decimal),
  // removed (0/1), key as hex, payload as hex. sdk/cet/nightcoop_sdk.lua decodes it.
  public static native func PollEventText(id: String) -> String;

  // ---------------------------------------------------------------- per-player quest facts
  // A quest fact that is each player's own — your scenes on the local V, your settings, your per-character state: the host
  // does not send it, a guest does not take the host's value, and quest pauses on it go by the local value. on false — the
  // world's again. Mark facts right after RegisterMod. 0 or a negative NightCoopSdkResult (SwitchedOff: "sdk_local_facts").
  public static native func KeepFactLocal(id: String, fact: String, on: Bool) -> Int32;

  // ---------------------------------------------------------------- vehicles a mod holds in the air
  // The mod holds this vehicle in the air on this machine (it flies our own): NightCoop's ground rules leave it alone
  // while on, and partners' mirrors of a vehicle we lead go by the same (C: NcSdkApi.entityAirborne). Release when it
  // lands. SetEntityAirborneFlags (at the end of the class) says more.
  public static native func SetEntityAirborne(id: String, entity: EntityID, on: Bool) -> Int32;

  // ---------------------------------------------------------------- text from partners (sdk/SECURITY.md)
  // A text safe to show or log: valid UTF-8, no control, invisible or direction-changing characters, spaces collapsed, at
  // most maxBytes bytes (0 — 256). Use it on every text a partner's copy of your mod sends you before you show it.
  public static native func CleanText(text: String, maxBytes: Int32) -> String;

  // ---------------------------------------------------------------- effects on NPCs a partner leads (sdk/docs/npc-effects.md)
  // Need the flag UsesNpcRequests (8192) in RegisterMod.
  // An effect on an NPC NightCoop syncs is done by its owner, with the game, as an action of our player. npc — our local
  // entity (a copy of a partner's NPC, or ours). Returns 0 — done here now (ours, or not synced), > 0 — the request number
  // (the owner's answer comes as the event NpcResult with this number), < 0 — NightCoopSdkResult.
  // flags — NightCoopSdkNpcFlag; points and vectors — world space.
  public static native func NpcEffect(id: String, npc: EntityID, kind: Int32, flags: Int32, mode: Int32, record: TweakDBID,
    value: Float, seconds: Float, point: Vector4, vector: Vector4) -> Int32;
  public static native func NpcStatus(id: String, npc: EntityID, status: TweakDBID, flags: Int32) -> Int32;
  public static native func NpcRemoveStatus(id: String, npc: EntityID, status: TweakDBID, flags: Int32) -> Int32;
  // value — health points (or percent with the flag Percent); attack — an Attack record (TweakDBID.undefined() — health
  // written directly; then reactType with the flag React gives a hit reaction); point (0,0,0 — the chest), dir (0 — from us)
  public static native func NpcDamage(id: String, npc: EntityID, attack: TweakDBID, value: Float, point: Vector4,
    dir: Vector4, flags: Int32, reactType: Int32) -> Int32;
  // ragdoll and push: impulse at point; radius 0 — 1 m
  public static native func NpcImpulse(id: String, npc: EntityID, point: Vector4, impulse: Vector4, radius: Float) -> Int32;
  // its own time: dilation 0..1 for seconds (<= 120); 0 — frozen, 1 — back to normal
  public static native func NpcSlow(id: String, npc: EntityID, dilation: Float, seconds: Float) -> Int32;
  // attitude: 0 friendly, 1 neutral, 2 hostile — to us (flag AllPlayers: to every player)
  public static native func NpcAttitude(id: String, npc: EntityID, attitude: Int32, flags: Int32) -> Int32;
  // side: NightCoopSdkNpcSide (Join our side, AllEnemies, Own back to its group)
  public static native func NpcSide(id: String, npc: EntityID, side: Int32) -> Int32;
  // kill it, we are the killer (flags NoAnim, NoRagdoll)
  public static native func NpcKill(id: String, npc: EntityID, flags: Int32) -> Int32;
  // its AI role: follow us (AIFollowerRole; stays with the NPC at its next owner), false — no role
  public static native func NpcFollow(id: String, npc: EntityID, follow: Bool) -> Int32;
  // god mode: 0 mortal again, 1 immortal, 2 invulnerable (stays with the NPC at its next owner)
  public static native func NpcGodMode(id: String, npc: EntityID, mode: Int32) -> Int32;
  // fake death (NightCoopSdkNpcEffect.FakeDeath), dispose (Dispose), hide for good (Hide): NpcEffect(id, npc, kind, 0, 0,
  // TweakDBID.undefined(), 0.0, 0.0, new Vector4(0.0, 0.0, 0.0, 0.0), new Vector4(0.0, 0.0, 0.0, 0.0))
  // The general request: the owner's copy of this mod gets the event NpcRequest with its local NPC and this channel and data,
  // does it there and answers with NpcReply; we get NpcResult. Always a request number (> 0), also for our own NPC.
  public static native func NpcRequest(id: String, npc: EntityID, channel: Int32, data: String) -> Int32;
  public static native func NpcRequestBytes(id: String, npc: EntityID, channel: Int32, data: array<Uint8>) -> Int32;
  // The owner's answer: result 0 or a negative NightCoopSdkResult, data — the reply (<= 1024 bytes)
  public static native func NpcReply(id: String, request: Int32, result: Int32, data: String) -> Int32;
  public static native func NpcReplyBytes(id: String, request: Int32, result: Int32, data: array<Uint8>) -> Int32;
  // This mod slows (or stops) OUR world: dilation 0..1 for seconds (<= 120); 1 — over. Declare, then slow it with the game
  // yourself. Partners near us get it as an implant's slow-down; a declared stop is no loading screen. Flag UsesWorldTime.
  public static native func WorldSlow(id: String, dilation: Float, seconds: Float) -> Int32;
  // ---------------------------------------------------------------- the save, the co-op menu, votes, partners, world asks
  // Their enums are in NightCoopSdk.reds (module NightCoop: import NightCoop.*).

  // Where the guest's game takes a ScriptableSystem of your mod from when the guest enters the host's world by save:
  // NightCoopSdkScope.World — the host's state of it, Character — each player's own (the default), Default — drop the word.
  // className — as RTTI has it: NameToString(this.GetClassName()) ("Module.Class" for a class in a module). Needs the flag
  // UsesSave. Say it right after RegisterMod. 0 or a negative NightCoopSdkResult.
  public static native func ScriptableScope(id: String, className: String, scope: Int32) -> Int32;
  // An item of your mod in NightCoop's co-op menu (Esc → «Co-op» → «Mods…», the main menu too): key [a-z0-9._-] 1..32,
  // ru / en — the label (the player's language), flags — NightCoopSdkMenuFlag. A press comes as an event of kind MenuItem
  // with key. Needs the flag UsesMenu.
  public static native func MenuItemSet(id: String, key: String, ru: String, en: String, flags: Int32) -> Int32;
  public static native func MenuItemRemove(id: String, key: String) -> Int32;
  // Host only: ask every player of the host's world in NightCoop's choice window (2..8 options; each player sees their own
  // language: give both, an empty one falls back to the other). The host's voting mode decides, End applies the host's
  // choice. The end comes as an event of kind VoteResult on every machine with your mod: key, a = the winner (-1 none),
  // value = NightCoopSdkVoteEnd, bytes = votes per option and last the number of voters. Needs the flag UsesVotes.
  public static native func VoteStart(id: String, key: String, questionRu: String, questionEn: String,
    optionsRu: array<String>, optionsEn: array<String>) -> Int32;
  public static native func VoteCancel(id: String, key: String) -> Int32;
  // What a player is doing (a partner, or ourselves): NightCoopSdkPartnerFlag bits (-1 — no session or no such player),
  // NightCoopSdkWhere, health 0..1 (-1 not known), character level (0 not known), the shared vehicle they sit in (packed
  // ref, 0 — none; EntityOfRef gives our entity of it). Reading needs no flag.
  public static native func PartnerFlags(peer: Int32) -> Int32;
  public static native func PartnerWhere(peer: Int32) -> Int32;
  public static native func PartnerHealth(peer: Int32) -> Float;
  public static native func PartnerLevel(peer: Int32) -> Int32;
  public static native func PartnerVehicle(peer: Int32) -> Uint64;
  // KeepFactLocal for a list at once: how many were accepted, or a negative NightCoopSdkResult for the call. A mod without
  // code says the same in its manifest (sdk/docs/manifest.md).
  public static native func KeepFactsLocal(id: String, facts: array<String>, on: Bool) -> Int32;
  // Ask the host to change the world (the host leads time and weather; a guest's own change is undone): kind —
  // NightCoopSdkWorldKind (TimeOfDay: value = seconds of the day; Weather: text = a weather state, value = blend seconds).
  // The host's copy of your mod decides (C hook), or with vote = true (or without such a hook) a vote of every player.
  // The answer — a Session event WorldAnswer (32): value = NightCoopSdkWorldAnswer, peer = who asked. Needs the flag
  // UsesWorldAsk. Returns the ask's number (> 0) or a negative NightCoopSdkResult.
  public static native func WorldAsk(id: String, kind: Int32, value: Int32, text: String, vote: Bool) -> Int32;
  // ---------------------------------------------------------------- shared spawns, effects, rewards, leading an NPC
  // sdk/docs/shared-spawns.md.
  // entityShare with all NightCoopSdkShareFlag bits (Follow 1, Animate 2, Handoff 4). Handoff: NightCoop may hand the NPC to
  // the player nearest to it, as an NPC of the world (event SpawnLeader tells who leads it then).
  public static native func ShareEntityFlags(id: String, entity: EntityID, flags: Int32) -> Int32;
  // Who leads the entity now (the peer whose machine runs its AI or physics); -1 — not synced by NightCoop (yours).
  public static native func EntityLeader(entity: EntityID) -> Int32;
  // Show a world effect (an .effect resource: picture and sound, no damage) on the partners in our world, fire and forget.
  // Play it on your own machine yourself (GameInstance.GetFxSystem(...).SpawnEffect). Needs the mod flag UsesEffects;
  // flags: NightCoopSdkFxFlag. Returns how many partners got it, or a negative NightCoopSdkResult.
  public static native func ShowEffect(id: String, path: String, position: Vector4, orientation: Quaternion, flags: Int32) -> Int32;
  // An effect on an entity NightCoop syncs (a player, a vehicle, an NPC, a shared spawn), on the partners' mirror or copy:
  // effect — an .effect resource path attached to slot ("" — the root), or with NightCoopSdkFxFlag.ByName the name of an
  // effect of the entity's template. Returns the effect number (> 0) for StopEffect, or a negative NightCoopSdkResult.
  public static native func AttachEffect(id: String, entity: EntityID, effect: String, slot: String, flags: Int32) -> Int64;
  public static native func StopEffect(id: String, effect: Int64, breakLoop: Bool) -> Int32;
  // A sound event (as GameObject.PlaySound) on the partners' mirror or copy of a synced entity; stop = true stops it.
  public static native func PlaySoundOn(id: String, entity: EntityID, event: String, stop: Bool) -> Int32;
  // A reward for a partner (to — a peer, -2 — everyone in our world): quantity of the item record ("Items.money") created in
  // their inventory, exactly once. Needs UsesRewards. Returns the first grant number (> 0), 0 — nobody in our world, or a
  // negative NightCoopSdkResult; the answer comes as event Reward (entity hash = the grant number, a = result).
  public static native func GrantReward(id: String, to: Int32, record: String, quantity: Int32) -> Int64;
  // Lead an NPC for a while (possession, mind control): entity — our body of a synced NPC (a partner's NPC's copy here). Its
  // owner hands it over; NightCoop's handoff rules keep it ours for seconds (1..600; -1 — until you call with 0; 0 — release).
  // The outcome comes as event SpawnLeader for it (a = 1 ours now, 0 not handed over). Needs the mod flag UsesNpcRequests.
  public static native func LeaseNpc(id: String, entity: EntityID, seconds: Int32) -> Int32;
  // ---------------------------------------------------------------- functions co-op relies on (sdk/docs/do-not-hook.md)
  // Tell NightCoop your mod hooks a game function (cls — script or native class name, fn — short name): flags
  // NightCoopSdkHookFlag.Replaces (the game's body does not run) or .Wraps (it runs). NightCoop warns the player like for the
  // hooks it finds itself. 1 — co-op relies on it now, 0 — not, or a negative NightCoopSdkResult (Denied without
  // NightCoopSdkModFlag.UsesHooks, SwitchedOff: "hook_overlap"). C: NcSdkApi.hookDeclare.
  public static native func HookDeclare(id: String, cls: String, fn: String, flags: Int32) -> Int32;
  // Does co-op rely on this function now: a mask of NightCoopSdkHookArea bits, 0 — no. Keep the original running there
  // (call wrappedMethod) while NightCoop is in a session.
  public static native func HookCoopUses(cls: String, fn: String) -> Int32;
  // Keys NightCoop reads itself, one per line: "name\tvk\tIK_name\taction\twhen\trebindable(0/1)" (C: keysUsed).
  public static native func CoopKeys() -> array<String>;
  // ---------------------------------------------------------------- content a partner may not have
  // sdk/docs/content-fallbacks.md. kind — NightCoopSdkFallbackKind.
  // What a partner WITHOUT your mod sees instead of your content: a game record / state / station / pose animation every
  // player has ("Vehicle.v_my_sedan" -> "Vehicle.v_standard2_archer_hella_player"). fallback "" — clear. Needs the flag
  // UsesFallbacks. 0 or a negative NightCoopSdkResult (SwitchedOff: "sdk_fallbacks").
  public static native func FallbackSet(id: String, kind: Int32, name: String, fallback: String) -> Int32;
  // Is this content in THIS game: 1 yes, 0 no, NotNow (cannot tell yet), Unsupported (weather states).
  public static native func ContentHere(kind: Int32, name: String) -> Int32;
  // Does the partner have a mod without the SDK — kind NightCoopSdkKnownModKind, its folder or file name as in
  // logs/nightcoop-mods.txt: 1 yes, 0 no, NotNow (the mods check with them is not over).
  public static native func PeerHasKnownMod(peer: Int32, kind: Int32, name: String) -> Int32;
  // ---------------------------------------------------------------- every frame
  // NightCoop calls target.function(dt: Float) on the game thread every frame while the player is in a world, after its
  // own frame and this mod's events. Unlike a chain of DelaySystem callbacks it keeps running through loads of a save.
  // The target is held weakly: call it again from OnAttach after a load (the system is a new object); null stops it.
  // false — no such function, or it does not take exactly one Float and return Void.
  public static native func ListenFrame(id: String, target: ref<IScriptable>, function: CName) -> Bool;
  // ---------------------------------------------------------------- vehicles a mod holds in the air, with flags
  // SetEntityAirborne with NightCoopSdkAirborneFlag bits (0 — release): Hold — the ground rules leave the vehicle alone;
  // NoWheels — the mod hides its wheels while it flies, a partner without the mod sees it without wheels too. A vehicle we
  // lead: every partner is told, with or without the mod, and one without the mod does not take its wheel.
  public static native func SetEntityAirborneFlags(id: String, entity: EntityID, flags: Int32) -> Int32;
}
