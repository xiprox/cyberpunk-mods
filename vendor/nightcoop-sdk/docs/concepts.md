# Concepts

What every co-op mod has to know. Read this before the API.

## Session, host and guests

A **session** is a group of players connected through NightCoop. One of them is the **host**; the others are **guests**.
Every player has a **peer number**: the host is always `0` (`NCSDK_PEER_HOST`), `LocalPeer()` / `where().localPeer` is your
own number, `-1` (`NCSDK_PEER_NONE`) out of a session.

- "In a session" means connected. The host is in a session as soon as it hosts, even with no guests yet.
- Out of a session the game is plain single-player. The SDK still works then: your mod registers, shared state is stored
  locally, channels reach nobody. Write the mod so that this case needs no special code.
- Peer numbers belong to one session. Do not store them in a save file or use them as a player's identity.

## The host's game is the world

The host's game runs the world: time, weather, NPCs, quests, the population. Guests see it through NightCoop. The
consequence for mods:

> If a guest changes the world locally, that guest's game diverges from everybody else's.

So a mod that changes the world must do it **on the host** and let guests ask: by a channel message or by writing shared
state (the host decides, see below). A mod that changes only its own player (looks, HUD, controls, camera) needs no
host at all. Register that with `NCSDK_MOD_LOCAL_ONLY`.

## In the host's world

A guest is not always in the host's world: it may be in the main menu, loading, or in its own campaign. Two checks:

| Check | Meaning |
|---|---|
| `InWorld()` | Our player is in a loaded world (not the main menu, not loading) |
| `InHostWorld()` | We are in the host's world (a guest who joined it; for the host: always when in world) |
| `PeerInOurWorld(peer)` | Both of us are in the host's world |

Events `PEER_WORLD_IN` / `PEER_WORLD_OUT` tell when a partner enters or leaves your world. Anything that involves a partner's
entity (a mirror of their car, their body) makes sense only while both of you are in the host's world.

## Ownership: who leads what

Every player **leads** (owns):

- their own player character;
- the vehicle they drive;
- the NPCs NightCoop handed to them (and NPCs given to them later).

On every other machine the same thing exists as a **mirror** or **copy**: a local entity that follows the owner's data.
You can read it, but the owner decides what it does. Two rules:

1. Change only what is yours. For anything else, ask the owner (a channel message to that peer).
2. Ask first which it is: `entityIsMine(entity)` returns `1` (yours), `0` (a partner's, yours is a mirror or copy) or
   `NCSDK_E_UNKNOWN` (NightCoop does not sync it, so it is purely local and therefore yours).

An entity you cannot name across machines (an `EntityID` is local) is named by a **network reference** (`NcSdkNetRef`:
kind, owner, id), the same on every machine. `entityRef` turns a local entity into a reference, `entityOfRef` turns a reference
into the local entity (mirror, copy or your own), or `0` if it is not here now (not streamed, not spawned yet). In scripts the
reference is packed into one `Uint64`: `kind 8 bits | owner 24 bits | id 32 bits`.

References and local `EntityID`s are not permanent. A mirror can be destroyed and created again under a new `EntityID`; an NPC
can pass to another owner. Do not keep an `EntityID` of a partner's entity as a permanent handle: ask `entityOfRef` when you
need it, or let NightCoop push your data to the current mirror (entity state, see [api.md](api.md)).

## Where mod data goes

A mod has three ways to put data on other machines. Pick by what the data is:

| Data | Use |
|---|---|
| A fact about the **world or the session** that everyone should agree on ("the counter is 7", "the event started") | **Shared state**: key to value, kept by the host, the same for everyone, late joiners included |
| A fact about **one entity** ("this car is in flight mode") | **Entity state**: a value attached to a synced entity by its owner, delivered to the mirror, also to late joiners |
| An **event** or a request ("please start the event", "I fired") | **Channel message**: reliable or not, to one peer, the host or everyone |

## The mod passport and the protocol

When a player appears in the session, every player tells every other the list of their registered mods: id, version,
`protocol` and flags (the **passport**). It is sent again whenever a mod registers or unregisters.

- Mod data travels only between players who registered the **same id with the same `protocol`**. A partner without your mod,
  or with a different protocol number, receives nothing and cannot send you anything. Nothing is sent to them, and nothing
  breaks.
- `peerHasMod(peer)` answers `1` (yes), `0` (no, or another protocol) or `NCSDK_E_STATE` (not known yet: the exchange with
  that player is not over). Events `PEER_MOD` / `PEER_NO_MOD` announce the answer.
- Raise your `protocol` when the meaning of your data changes in a way old versions cannot read. Players on different
  numbers then simply do not talk to each other, which is better than misreading.
- If you register with `NCSDK_MOD_NEEDED_BY_ALL` and a partner lacks the mod (or has another protocol), **both** players get
  a short note on screen, once per partner and mod, and a log line. Entry to the session is never refused.

## Why the host decides shared state

Shared state has one writer of record: the host. When the host sets a key, it stores it, tells itself and sends it to all
peers that have the mod. When a guest sets a key, the guest only sends a **request**; the host's mod may refuse it
(`stateRequest` hook in C; scripts accept everything), and only the host's answer changes the value, for everybody
including the guest. This is also why two players cannot disagree about the value for long.

Flag `NCSDK_MOD_HOST_AUTHORITY` documents the same decision for your whole mod: its world changes come from the host, guests
ask the host.

## The guest's save in the host's world

A guest joins the host's world by a save NightCoop builds on the guest's machine from two saves: the **world** of the
host's save — quest facts, the journal, scenes, the population, the world's script systems — and the guest's **character**: inventory, stats, perks,
appearance, wardrobe, and every other script system. When the session ends, the way back builds the guest's campaign the
other way round: its own world, the character of the session.

For a mod this means:

- A `ScriptableSystem` of your mod is the **character's** by default: the guest brings their own state (needs, addictions,
  equipment sets, a wardrobe). A system that keeps the **world** of your mod (its NPCs, a gig board, an economy, events of
  the world) can say so: `scriptableScope(mod, class, NCSDK_SCOPE_WORLD)` — the guest takes the host's state of it, and the
  way home brings back the campaign's own.
- A quest fact your mod marked with `factKeepLocal` keeps the guest's own value at the entry (and the session's value at the
  way home). Mark your facts right after registering: the word counts at the moment of the entry.
- Items with the quest flag that are not equipment go aside for the session at the first entry (the host's quest graph must
  not see quest items of another campaign) and come back home with the guest.
- Entities a mod keeps in the save (Codeware's persistent spawns) are the world's: the host's.

## What a partner is doing, and co-op events

`partnerState` answers for any player of the session (and for yourself): in our world or where, downed, in combat, in a
vehicle (and which one — a network reference you can turn into your own entity), in a scene, in a menu, health and level.
Co-op events say when it changes — a partner fell or got up, every player is down (the co-op death: nobody dies alone in a
session, the host loads its last save), a partner got into or out of a vehicle, an NPC was killed by a player (and by whom),
every player is in a menu (the world stands), the host saved or loaded, the host skipped time. They come from what NightCoop
already knows; reading needs no flag.

## NightCoop's own interface for mods

A mod can put its own items into NightCoop's co-op menu («Mods…») and ask every player a question in NightCoop's voting
window. A vote of a mod decides like NightCoop's choices: by the host's voting mode (everyone / more than half), the host
can apply its choice by holding End. Each player sees the texts in their own language (give Russian and English), never
the host's text in another language.

## Events of libraries and of the SDK

| What you used to watch | In a session use | Why |
|---|---|---|
| Codeware `Session/Start`, `Session/Ready`, cet-kit `GameSession.OnStart` | `NCSDK_EV_SESSION_START` and `NCSDK_EV_PEER_WORLD_IN` (or `where().inHostWorld`) | A world load is not a session: a guest loads the host's world by save, and only then is in it |
| `Session/BeforeEnd`, `GameSession.OnEnd` | `NCSDK_EV_PEER_WORLD_OUT`, `NCSDK_EV_SESSION_END` | Leaving a world and leaving the session are different moments |
| `Session/BeforeSave`, `Session/AfterSave`, `OnSavingComplete` | `NCSDK_EV_HOST_SAVE` (value 1) on every machine | A guest's own saves in the host's world are technical; the host's save is the session's |
| `Session/Pause`, `Session/Resume`, `GameSession.OnPause` | `NCSDK_EV_WORLD_PAUSE` | In a session the world stands only when every player is in a menu; one player's menu does not stop it |
| `FastTravelSystem.*`, `TimeskipGameController` | `NCSDK_EV_TIME_SKIP` | Only the host skips time; the guests' clocks follow |
| Death screen, `PlayerPuppet.OnDeath` | `NCSDK_EV_PEER_DOWN`, `NCSDK_EV_TEAM_DOWN` | A player in a session lies downed instead; the team's death reloads the host's save |
