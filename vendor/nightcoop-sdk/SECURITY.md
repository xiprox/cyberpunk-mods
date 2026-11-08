<!-- SPDX-License-Identifier: MIT — Copyright (c) 2026 NightCoop (see LICENSE) -->
# NightCoop SDK — security

The NightCoop SDK lets a mod on your machine exchange data with the same mod on your co-op partners' machines. That is a
network-facing interface, so this page says plainly what a partner can do to you through it, what NightCoop checks, what
it does **not** check, and what a port author and a reviewer (for example on Nexus Mods) should look at.

Short version:

- A partner can only send **data** — bytes — to the **same mod** on your machine, within size and rate limits, and only
  of the kinds the mod declared it uses. They cannot run code, call SDK functions on your machine, reach mods you do not
  have, or exceed the limits.
- NightCoop checks the **form** of everything (lengths, encodings, owners, limits, permissions). The **meaning** of a mod's
  data — whether a number is in range, whether an id exists — is the mod's job. A port must treat every value a partner
  sends as untrusted.
- The player has the last word: switches turn parts of the SDK off, single mods can be blocked, and the host can switch
  mods off for a whole session.

## 1. Threat model

| Who | What they control | What they want |
|---|---|---|
| A partner in your session (host or guest) | Their own game, their own copy of NightCoop (possibly modified), their own mods (possibly malicious or broken) | Crash or freeze your game, corrupt your world or save, fake on-screen or log messages, flood your connection |
| The hub (relay server) | Only routing | Read or change traffic |
| A mod installed on your own machine | Everything in your game process | Not covered: a RED4ext plugin is native code with full access to your process; the SDK's permissions are a cooperation contract for well-behaved mods, not a sandbox |

Transport: NightCoop's links are encrypted between the host and each guest (the hub
relays envelopes it cannot read). A guest's message to another guest goes through the host, which decrypts and relays it:
**the host of a session sees all mod data of that session.** Do not send secrets through the SDK.

## 2. What a partner can do through the SDK

- Send channel messages to your copy of a mod you both registered with the same id and the same `protocol`
  (`NCSDK_MOD_USES_CHANNELS` declared on both sides): any bytes up to 1024 (unreliable) or 16384 (reliable).
- As host: set the shared state of such a mod (`USES_SHARED_STATE`); as guest: ask the host to set it — the host's mod can
  refuse in `stateRequest`.
- Attach entity state (`USES_ENTITY_STATE`) to entities **they own** (their player, the vehicle they drive, NPCs NightCoop
  gave them, their shared spawns): up to 1024 bytes per key; your mod gets it on your mirror of that entity.
- Show their mod list (the passport: ids, versions, names, flags) — it decides who gets which data, and it appears in
  NightCoop's log and in the "every player needs this mod" note.
- Feed a pose source (VR head and hands) and share spawned entities — handled by NightCoop's pose and spawns modules with
  their own checks (see `docs/api.md`).
- Ask you, as the owner of an NPC, to do an effect on it from their body (`USES_NPC_REQUESTS` on both sides,
  `docs/npc-effects.md`): a status effect or an attack **that exists in your TweakDB** with the right record
  class, damage up to 100 % of health, a push up to 1000, its own time, attitude, side, a follow role, god mode, a kill, fake
  death, despawn, hiding — only on an NPC you lead, only while both of you are in your world and their body is within 150 m
  of it, at most 20 requests per second per mod and partner (bursts 2×). The general request carries up to 1024 bytes to your
  copy of the same mod, which decides; at most 256 open requests per mod.
- Tell you, as the owner of an NPC's copy, what its owner did (a status, a push, hiding, a follow role): taken only from the
  NPC's owner as your machine knows it, statuses only of a look-only type unless your copy of the mod asked otherwise.
- Declare that their world is slowed (`USES_WORLD_TIME`): you get the slow-down within the implant radius,
  as from their Sandevistan, no stronger than 0.02, for at most 120 s per declaration.
- As host: ask everyone a question of a mod in NightCoop's voting window (`USES_VOTES` in the host's
  passport): two languages of text up to 160 bytes for the question and 80 per option, 2..8 options. A guest shows it only
  if the host's passport declares the flag; the texts are cleaned (`cleanText`) before they reach the screen; one vote at a
  time, incoming vote words are limited to 8 a second per sender. Votes are counted only from the voters the host named,
  only by the host.
- As a guest: ask the host to change the world (`USES_WORLD_ASK` in the asker's passport — the host checks
  it): only the time of day (forward, at most a day) and a weather state by name; the host takes one ask in 2 seconds
  per player, and decides by its own copy of the mod or by a vote of every player; the host changes its world by the game's
  own way, nothing else is run.
- As the owner of an NPC: tell that a player killed it (an event to everyone's mods). Taken only from the NPC's owner as your
  machine knows it, and only naming a player of the session as the killer.
- Tell what your game should show instead of their content you lack (`docs/content-fallbacks.md`): a fallback
  record, weather state, station or pose sent with their vehicle, radio, weather or photo mode word, and answers to your
  asks about their weapons. A fallback is only ever a choice among the content **your** game has:
  NightCoop takes it only if it is in your TweakDB (and of the expected class: a vehicle record for a vehicle, an item record
  for an item) or among your game's stations, poses or weather states; otherwise its own default or nothing. Asks and answers
  are bounded: 32 per word, 256 per partner and session; an answer counts only for a record you asked that partner about.

Any value inside those limits is possible, including nonsense: huge numbers, NaN, negative counts, ids of entities that do
not exist, text with control characters. NightCoop delivers it to your mod after the checks below.

## 3. What a partner cannot do

NightCoop enforces, on the receiving machine:

| Check | How |
|---|---|
| No code from the network | The SDK carries data only. Nothing received is executed, loaded or interpreted as a script by NightCoop |
| Memory safety of the wire | Every reader checks lengths before it allocates or copies (`n > max \|\| Remaining() < n`), strings are bounded, unknown kinds and versions are refused |
| Only the same mod | Data goes to a mod only if both sides registered the same id **and** the same `protocol`; a mod you do not have never receives anything |
| Permissions | A mod uses only what its passport declares (`NCSDK_MOD_USES_CHANNELS`, `_SHARED_STATE`, `_ENTITY_STATE`, `_POSE`, `_ACTIONS`, `_NPC_REQUESTS`, `_WORLD_TIME`, `_SAVE` for script systems in the save, `_MENU` for co-op menu items, `_VOTES` for votes, `_WORLD_ASK` for asks to the host's world, `_EFFECTS` for effects and sounds, `_REWARDS` for rewards, `_HOOKS` for hook declarations, `_FALLBACKS` for content substitutes; `SPAWNS_ENTITIES` for shared spawns, `CHANGES_QUESTS` for per-player quest facts). An undeclared call answers `NCSDK_E_DENIED`; partners' data of an undeclared kind is dropped — checked against our mod's flags and against the flags in the sender's passport |
| Size limits | Per message and per value (§2), 256 shared-state keys per mod, 4096 entity-state records per mod (owned, and received from partners), 1024 queued events per mod (the oldest drop) |
| Rate limits | Per mod and direction 32 KiB/s and 120 messages/s, bursts up to 4×; incoming per mod **and sender** |
| Ownership | Entity state is taken only from the entity's owner as your machine knows it (a player — only from that player; a shared spawn — only from the machine that leads it now) |
| Shared spawns | A partner announces only its own spawns: the spawn number carries the sender's peer number in its top byte, a number of another creator is dropped (one log line). `NCSDK_SHARE_HANDOFF` needs `SPAWNS_ENTITIES` like `entityShare`; an NPC handed to the nearest player goes through NightCoop's own NPC handoff with its checks — nothing is spawned because a partner said so. A shared vehicle is mirrored by NightCoop's vehicle sync with its own limits (64 shared vehicles per sender, the record must be a vehicle record). `entityLeader` only reads. A mod effect (`effectShow`) is shown only from a peer whose passport declares `NCSDK_MOD_USES_EFFECTS`, at most 20 a second per peer, within 150 m of that peer's player, and only an `.effect` resource that is in our game (fire and forget: picture and sound, no damage or logic); effects and sounds on entities (`effectAttach`, `soundPlay`) — the same passport and rate checks, only on our own mirror or copy of a synced entity |
| Rewards | A partner's `rewardGrant` creates an item in our inventory only if we have the same mod (id and protocol), its passport declares `NCSDK_MOD_USES_REWARDS`, the record is an item of our TweakDB and not tagged `Quest`, 1..9999 of it, at most 2 a second (bursts of 8) from that peer, we are in one world, and a guest's player is within 100 m of ours (the host — any distance). Each grant number is given at most once and its answer is remembered for 10 minutes: a repeated or replayed message gets the same answer, never a second item |
| Host authority | Shared state is written only by the host; a guest only asks |
| Clean text | Every text from a partner that NightCoop shows or logs (passport names and versions), and every text a mod passes to `showMessage` or `log`, is cleaned: valid UTF-8, no control characters (C0, DEL, C1), no invisible or direction-changing characters (bidi marks, overrides and isolates, zero-width characters, tags, fillers), no line breaks (a mod's log line cannot forge a NightCoop line), at most 2 combining marks in a row, bounded length. Mods get the same cleaning as `cleanText` / `CleanText` |
| Threads | Callbacks run on the game thread from NightCoop's frame, never from inside a call of the table, never on the network thread |

### The co-op menu, the save, manifests

- **Menu items** are local: labels are cleaned, at most 8 per mod and 32 in all; a press goes only to the mod that added the
  item, on this machine.
- **Script systems in the save** (`scriptableScope`): a mod may speak only of classes that are `ScriptableSystem`s and not of
  the game's world systems NightCoop decides (fast travel, police, …); the first mod to speak of a class owns the word.
  The guest decides its own save: nothing of it comes from a partner.
- **Manifests** (`*.nightcoop`) are read from your own game folder only, never from the network; the rights are those of
  the passport they declare; a manifest cannot do anything the mod's code could not.

## 4. What NightCoop does not guarantee

- **The meaning of a mod's data.** NightCoop cannot know that a "speed" must be below 200 or that an item id must exist.
  Validate in your mod.
- **That a partner's flags or mod are honest.** A modified client can claim any passport. The permission check protects
  you from a well-behaved mod misusing the SDK and from data of kinds your mod never asked for; it does not prove what code
  runs on the other machine.
- **That the partner runs the same code.** Same id and `protocol` is the only match. Raise `protocol` when your data
  format changes.
- **Confidentiality from the host** (see §1).
- **Protection from local mods** (see §1).

## 5. Levers of the player and the host

| Lever | Where | Effect |
|---|---|---|
| `sdk` | `switches.txt` line `sdk = off`, or the CET console `NightCoopQuestSet("sdk", false)` | The whole SDK off: no table, no class functions, no mod data, NightCoop's `.reds` not compiled |
| `sdk_channels`, `sdk_state`, `sdk_entity_state` | same | One kind of mod data off |
| `sdk_block = author.mod, other.mod` | `switches.txt` (or `NightCoopSdkBlock("author.mod", true)` for this run) | Those mods cannot register: they work as without NightCoop; partners' data for them is dropped |
| `sdk_session` | the host's `switches.txt` or console | Off on the host: no mod data for anybody in the sessions it hosts (guests are told and obey; each machine drops mod data on its own) |
| `sdk_permissions` | same | The check of declared permissions (on by default); off — every use is allowed, for testing only |
| `sdk_npc`, `sdk_npc_show`, `sdk_npc_push`, `sdk_npc_lasting`, `sdk_world_slow` | same | Effects on NPCs and a partner's declared world slow-down: off — partners' requests are refused, nothing is shown on copies |

Every refusal writes a line to NightCoop's log starting with `sdk:`; `NightCoopSdkStatus()` in the CET console shows the
counters (denied calls, dropped data, rate limits, blocked mods).

## 6. Checklist for port authors

1. **Declare exactly what you use** in `RegisterMod` (`NCSDK_MOD_USES_*`, `SPAWNS_ENTITIES`, `CHANGES_QUESTS`) — no more.
2. **Never trust a number from a partner.** Check ranges, NaN/infinity (`isfinite`), array sizes, enum values; clamp or
   drop. Decode with explicit sizes; never index an array with a received value without a bounds check.
3. **Never trust a text from a partner.** Pass it through `cleanText` / `CleanText` before you show or log it; never build
   file paths, console commands, TweakDB ids or CName lookups that do something from received text without a whitelist.
4. **Do not spawn, give items, change facts, run actions or move entities because a partner said so.** Received data may
   describe what the owner did; your mod decides what to do with it, within the game's rules, on entities that are yours
   (`entityIsMine`) or mirrors NightCoop gave you.
5. **World changes go through the host** (`HOST_AUTHORITY`): a guest asks, the host's mod decides in `stateRequest` or on a
   channel message, and refuses anything it would not do itself.
6. **Do not send every frame reliably.** Use streams (`NCSDK_STATE_STREAM`) or `LATEST_ONLY` for continuous values; the
   rate limit will refuse a flood (`NCSDK_E_LIMIT`).
7. **No networking of your own.** Everything goes through the SDK: then the limits, permissions and the player's switches
   apply, and reviewers can trust that.
8. **Work without NightCoop**: `NightCoopSdkGet` may be `NULL`, `Version()` may be 0, the module may be absent
   (`@if(ModuleExists("NightCoop"))`). Never ship NightCoop's own `.reds` files.
9. Test with a partner who **lacks** your mod and with one who sends garbage (another `protocol`, a broken build).

## 7. Notes for reviewers (Nexus Mods and others)

What to look at in a port built on this SDK:

- **Registration**: the flags in `RegisterMod` / `NcSdkModInfo.flags`. Every SDK call the port makes must be covered by a
  declared permission (§3) — undeclared calls fail at run time with `NCSDK_E_DENIED`, so an over-broad declaration is the
  only thing to question.
- **No own network code**: no sockets, HTTP clients or other transports (C/C++: no `ws2_32`, `winhttp`, `wininet` imports;
  redscript and Lua: no such APIs exist). All traffic goes through NightCoop, which applies the limits above.
- **Handling of received data** (§6, points 2–4): received values are checked before use; nothing is spawned, given or
  executed directly from received data; received texts are cleaned before they are shown.
- **What NightCoop already guarantees** (§3) does not need to be re-checked per port: wire memory safety, limits, rate,
  ownership of entity state, host authority over shared state, text cleaning of what NightCoop itself shows.
- The SDK is MIT-licensed (`LICENSE`); the bridge of a port carries the license of the mod it ports (see the port's
  README, `ports/flight/README.md`).

## 8. Reporting a vulnerability

Please report security problems privately to the NightCoop team (a direct message to the moderators on the NightCoop
Discord server), not in public channels. Include the NightCoop build (the log's first line), the game version and, if you
can, the bytes or steps that trigger it.
