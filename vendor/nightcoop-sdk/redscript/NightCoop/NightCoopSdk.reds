// SPDX-License-Identifier: MIT — Copyright (c) 2026 NightCoop (see sdk/LICENSE)
// NightCoop SDK for redscript mods — version 1: the module NightCoop and its enums.
//
// The class NightCoopSdk (static natives registered by NightCoop.dll, mirroring sdk/include/nightcoop_sdk.h) and the
// event class NightCoopSdkEvent are in NightCoopSdkNative.reds, at top level (a native class inside a module would be
// looked up by the game as "NightCoop.NightCoopSdk"). This file makes the module exist: @if(ModuleExists("NightCoop"))
// is true only when NightCoop is loaded, and "import NightCoop.*" brings the enums below.
//
// Both files ship inside NightCoop's plugin folder and NightCoop.dll adds them to the redscript compilation itself (only
// when it really loads). Do not copy them into your mod. The same class is reachable from Cyber Engine Tweaks:
// NightCoopSdk.InSession(), NightCoopSdk.Send(...), ...
//
// Guard everything that touches NightCoop so your mod compiles and runs without it:
//
//   @if(ModuleExists("NightCoop"))
//   import NightCoop.*
//
//   @if(ModuleExists("NightCoop"))
//   private func ShareFlightState(vehicle: ref<VehicleObject>, mode: Int32) -> Void {
//     NightCoopSdk.SetEntityState("jackhumbert.let_there_be_flight", vehicle.GetEntityID(), 1, IntToString(mode), false);
//   }
//
// The mod id is the same stable id as NcSdkModInfo.id (ASCII [a-z0-9._-], 3..64 bytes). Register it once (for example
// in your ScriptableSystem's OnAttach) — every other call takes the same id. Results: Int32 functions return 0 or a
// positive count on success and a negative NightCoopSdkResult on failure.
module NightCoop

public enum NightCoopSdkResult {
  Ok = 0,
  BadArgument = -1,
  NotNow = -2,
  Limit = -3,
  Unsupported = -4,
  SwitchedOff = -5,
  Denied = -6,
  Unknown = -7,
  TooSmall = -8
}

// RegisterMod flags (a bit set: EnumInt(...) | EnumInt(...)).
public enum NightCoopSdkModFlag {
  NeededByAll = 1,
  LocalOnly = 2,
  ChangesWorld = 4,
  ChangesQuests = 8,
  AddsItems = 16,
  SpawnsEntities = 32,
  HostAuthority = 64,
  // What the mod uses — an undeclared use answers Denied (sdk/SECURITY.md).
  // ShareEntity / UnshareEntity / KeepLocal need SpawnsEntities, KeepFactLocal needs ChangesQuests.
  UsesChannels = 256,
  UsesSharedState = 512,
  UsesEntityState = 1024,
  UsesPose = 2048,
  UsesActions = 4096,
  // NpcEffect, NpcStatus, ..., NpcRequest, NpcReply, LeaseNpc (sdk/docs/npc-effects.md)
  UsesNpcRequests = 8192,
  UsesWorldTime = 67108864,  // WorldSlow
  UsesSave = 32768,     // ScriptableScope
  UsesMenu = 65536,     // MenuItemSet, MenuItemRemove
  UsesVotes = 131072,   // VoteStart, VoteCancel
  UsesWorldAsk = 8388608, // WorldAsk
  // The mod changes how NPCs think or fight — its NPCs go to the nearest player only if that player has the mod too
  // (switch "sdk_npc_logic")
  ChangesNpcLogic = 1048576,
  // ShowEffect, AttachEffect, StopEffect, PlaySoundOn
  UsesEffects = 2097152,
  // GrantReward
  UsesRewards = 4194304,
  // HookDeclare
  UsesHooks = 262144,
  // FallbackSet
  UsesFallbacks = 16384
}

// FallbackSet / ContentHere kind (NCSDK_FALLBACK_*)
public enum NightCoopSdkFallbackKind {
  Vehicle = 1,    // a vehicle record, "Vehicle.*"
  Item = 2,       // an item record, "Items.*" (weapons in hands, clothes)
  Weather = 3,    // a weather state name, "24h_weather_rain"
  Radio = 4,      // a radio station: the receiver's name while the mod plays; a game station by its ERadioStationList name, "AGGRO_INDUSTRIAL"
  PhotoPose = 5   // a photo mode pose animation, "idle_stand_02"
}

// PeerHasKnownMod kind (NCSDK_KNOWN_MOD_*) — where a mod without the SDK lies
public enum NightCoopSdkKnownModKind {
  Red4ext = 0,    // red4ext/plugins
  Redscript = 1,  // r6/scripts
  Cet = 2,        // bin/x64/plugins/cyber_engine_tweaks/mods
  Archive = 3,    // archive/pc/mod
  Redmod = 4,     // mods
  Tweak = 5,      // r6/tweaks
  Asi = 6         // bin/x64/plugins (.asi)
}

// NightCoopSdkEvent.kind
public enum NightCoopSdkEventKind {
  None = 0,
  Session = 1,      // a = NightCoopSdkSessionEvent, peer
  Message = 2,      // peer = from, a = channel, data / bytes
  State = 3,        // peer = by, key, data / bytes (empty and removed = true — the key is gone)
  EntityState = 4,  // peer = from, entity (our mirror or copy), ref, a = key, data / bytes
  PartnerPose = 5,  // peer, pose fields (poseValid 0 — the source is gone)
  SharedSpawn = 6,  // peer = owner, entity (our copy), ref, a = 1 appeared / 0 gone
  NpcRequest = 7,   // we lead the NPC: peer = who asks, entity = our NPC, ref, a = channel, request, data / bytes
  NpcResult = 8,     // the answer to our request: peer = owner, entity = our copy, ref, a = result, request, effect, data
  MenuItem = 11,    // key = the item key of your mod the player pressed in the co-op menu
  VoteResult = 12,   // key = the vote key, a = the winner (-1 none), value = NightCoopSdkVoteEnd, bytes = votes per option + voters
  SpawnLeader = 9,  // peer = the new leader, entity, ref, a = 1 we lead it now / 0 a partner
  Reward = 18       // the answer to GrantReward — peer = recipient, entity hash = grant, a = result
}

// NightCoopSdkEvent.a for kind Session
public enum NightCoopSdkSessionEvent {
  SessionStart = 1,
  SessionEnd = 2,
  PeerJoin = 3,
  PeerLeave = 4,
  PeerWorldIn = 5,
  PeerWorldOut = 6,
  PeerHasMod = 7,
  PeerNoMod = 8,
  // co-op events, their value in event.value
  PartnerDown = 9,      // value 1 fell, 0 got up
  TeamDown = 10,        // every player of the host's world is down: value 1 the host loads its last save, 0 no save
  PartnerVehicle = 11,  // value 1 in (passenger), 2 at the wheel, 0 out; ref / entity — the vehicle
  NpcKilled = 12,       // peer = the killer (may be us), ref / entity — the NPC
  WorldPause = 13,      // value 1 every player is in a menu, 0 the world runs again
  HostSave = 14,        // value 1 the host saved, 2 the host loaded a save
  TimeSkip = 15,        // value = the world's game time after the host's time skip, seconds
  WorldAnswer = 32      // the answer to a WorldAsk of your mod: value = NightCoopSdkWorldAnswer, peer = who asked
}

// SetPose valid bits
public enum NightCoopSdkPoseBit {
  Head = 1,
  LeftHand = 2,
  RightHand = 4,
  Fingers = 8,
  Aim = 16,
  Crouch = 32
}

// Effects on NPCs a partner leads (sdk/docs/npc-effects.md)

// NpcEffect kind; NightCoopSdkEvent.effect of NpcResult (0 — a general NpcRequest)
public enum NightCoopSdkNpcEffect {
  Request = 0,
  Status = 1,
  RemoveStatus = 2,
  Damage = 3,
  Impulse = 4,
  Slow = 5,
  Attitude = 6,
  Side = 7,
  Kill = 8,
  Follow = 9,       // mode 1 follow us, 0 no role
  GodMode = 10,     // mode 0 mortal, 1 immortal, 2 invulnerable
  FakeDeath = 11,
  Dispose = 12,
  Hide = 13
}

// NpcEffect / NpcStatus / NpcDamage / NpcAttitude / NpcKill flags (a bit set)
public enum NightCoopSdkNpcFlag {
  SkipLocal = 1,    // Status, RemoveStatus: your mod did it on our copy itself
  Percent = 2,      // Damage: value is percent of max health
  Nonlethal = 4,    // Damage: can defeat, not kill
  React = 8,        // Damage without an attack record: a hit reaction of reactType (gamedataAttackType)
  AllPlayers = 16,  // Attitude: to every player
  ShowAlways = 32,  // Status: on the partners' copies whatever its type
  NoAnim = 64,      // Kill: no death animation
  NoRagdoll = 128   // Kill: no ragdoll
}

// NpcSide
public enum NightCoopSdkNpcSide {
  Join = 0,         // our side (our attitude group, friendly to us)
  AllEnemies = 1,   // hostile to everyone
  Own = 2           // back to its own group
}

// ShareEntityFlags bits (C NCSDK_SHARE_*)
public enum NightCoopSdkShareFlag {
  Follow = 1,   // a prop's copy follows your transform (default: placed once)
  Animate = 2,  // an NPC copy plays your animation stream (always on for NPCs)
  Handoff = 4   // an NPC goes to the player nearest to it, as an NPC of the world
}

// ShowEffect / AttachEffect flags (C NCSDK_FX_*)
public enum NightCoopSdkFxFlag {
  IgnoreTimeDilation = 1, // the effect runs in real time, not slowed with the world
  ByName = 2              // AttachEffect: the effect is a name of the entity's template, not a resource path
}

// HookDeclare flags — exactly one (sdk/docs/do-not-hook.md)
public enum NightCoopSdkHookFlag {
  Replaces = 1, // the game's body does not run (@replaceMethod, CET Override without the original)
  Wraps = 2     // the original runs (@wrapMethod with wrappedMethod, CET Observe)
}

// HookCoopUses mask bits — what co-op does there
public enum NightCoopSdkHookArea {
  Player = 1,
  Npc = 2,
  Population = 4,
  Vehicles = 8,
  Quests = 16,
  Time = 32,
  Saves = 64,
  Menu = 128,
  World = 256,
  Devices = 512,
  Other = 1024
}

// ScriptableScope scope.
public enum NightCoopSdkScope {
  Default = 0,   // as NightCoop decides: a mod's system is the character's
  World = 1,     // the guest takes the host's state of it when it enters the host's world by save
  Character = 2  // each player's own
}

// MenuItemSet flags (a bit set).
public enum NightCoopSdkMenuFlag {
  Disabled = 1,  // shown, but not now: a press says so and does not reach the mod
  InSession = 2, // only in a session
  HostOnly = 4,  // not for guests
  InWorld = 8    // only in the pause menu (in a world), not in the main menu
}

// NightCoopSdkEvent.value of kind VoteResult — how a vote ended.
public enum NightCoopSdkVoteEnd {
  Decided = 1,   // the votes reached what the host's voting mode needs
  Forced = 2,    // the host applied its choice (held End)
  TimedOut = 3,  // NightCoop's voting time ran out (when the host has one)
  Cancelled = 4, // the mod cancelled it
  Aborted = 5    // the session ended, the host left its world, switched off
}

// PartnerFlags bits.
public enum NightCoopSdkPartnerFlag {
  InWorld = 1,     // in our world (both in the host's world); the bits below are fresh only with it
  Down = 2,
  Combat = 4,
  Vehicle = 8,
  Wheel = 16,      // at the wheel of a vehicle NightCoop shares
  Scene = 32,      // a scene leads them (a dialogue, a workspot, a cutscene)
  Menu = 64,       // their pause menu or a full-screen game window is open
  LinkLost = 128,  // the link to them is lost for now
  Us = 256         // it is us
}

// WorldAsk kind.
public enum NightCoopSdkWorldKind {
  TimeOfDay = 1, // value — seconds of the day 0..86399 (the world goes forward to it, at most a day)
  Weather = 2    // text — a weather state (e.g. 24h_weather_rain), value — blend seconds 0..600
}

// NightCoopSdkEvent.value of the Session event WorldAnswer (32).
public enum NightCoopSdkWorldAnswer {
  Refused = 0,
  Done = 1,
  Failed = 2,    // agreed, but the game did not take it, or the session ended
  Busy = 3       // another vote runs, or too many asks
}

// PartnerWhere.
public enum NightCoopSdkWhere {
  Unknown = 0,
  HostWorld = 1,
  MainMenu = 2,
  Loading = 3,
  Joining = 4,   // in their own world, entering the host's
  OwnWorld = 5
}

// SetEntityAirborneFlags bits (C NCSDK_AIRBORNE_*).
public enum NightCoopSdkAirborneFlag {
  Hold = 1,     // the ground rules leave the vehicle alone (contacts, return home, the wheel)
  NoWheels = 2  // the mod hides its wheels while it flies: a partner without the mod sees it without wheels too
}
