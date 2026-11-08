# NightCoop SDK documentation

Version 1. For authors of Cyberpunk 2077 mods that want to work in a NightCoop session: C/C++ (RED4ext), redscript and
Cyber Engine Tweaks (Lua).

## Start here

1. Read [concepts.md](concepts.md): sessions, the host's authority, who owns what. Ten minutes; it saves you from the usual bugs.
2. Pick your language and follow its guide: [C / RED4ext](getting-started-c.md), [redscript](getting-started-redscript.md),
   [Cyber Engine Tweaks](getting-started-cet.md).
3. Register your mod (a stable id, a name, a version, a protocol number, flags). Without NightCoop installed, your mod must
   keep working: every guide shows how.
4. Follow [make-your-mod-coop.md](make-your-mod-coop.md): what stays local, what goes through the host, what goes on an entity.
5. Look at the working example: a shared counter in [C++](../examples/c-counter/), [redscript](../examples/redscript-counter/)
   and [Lua](../examples/lua-counter/).
6. Test with two players. When something does not arrive, see [troubleshooting.md](troubleshooting.md).
7. Before you replace a game function (`@replaceMethod`, CET `Override`, a detour), read
   [do-not-hook.md](do-not-hook.md): the functions co-op relies on and what NightCoop cannot find by itself.

## Contents

| File | What |
|---|---|
| [concepts.md](concepts.md) | Session, host and guests, authority, ownership, "in the host's world", the mod passport |
| [getting-started-c.md](getting-started-c.md) | RED4ext plugin: find NightCoop, register, hooks, unregister, shutdown |
| [getting-started-redscript.md](getting-started-redscript.md) | `@if(ModuleExists("NightCoop"))`, registering in a `ScriptableSystem`, events |
| [getting-started-cet.md](getting-started-cet.md) | The same class from Lua, polling in `onUpdate`, the helper `sdk/cet/nightcoop_sdk.lua` |
| [api.md](api.md) | Every function: C name, script name, what it does, return codes |
| [npc-effects.md](npc-effects.md) | Effects on NPCs a partner leads (statuses, damage, pushes, time, sides, kills, roles), your own logic on the owner's machine, slowing your world |
| [limits-and-versions.md](limits-and-versions.md) | Sizes, rates, queues, `NCSDK_VERSION`, how the interface grows, the mod's `protocol` |
| [make-your-mod-coop.md](make-your-mod-coop.md) | Step by step: turning a single-player mod into a co-op one; a checklist by kind of mod; common mistakes |
| [manifest.md](manifest.md) | A mod without code (TweakXL, ArchiveXL, quest phases): the `*.nightcoop` file next to it |
| [shared-spawns.md](shared-spawns.md) | Entities your mod spawns: share, keep local, who leads (handoff to the nearest player, vehicles led by the driver), CET spawns |
| [content-fallbacks.md](content-fallbacks.md) | Content a partner may not have: what NightCoop shows instead (cars, weapons, radio, weather, poses), how your mod names a fallback |
| [../SECURITY.md](../SECURITY.md) | Threat model, what a partner can and cannot do through the SDK, checklists for port authors and reviewers |
| [troubleshooting.md](troubleshooting.md) | Log lines, `NightCoopSdkStatus()`, switches |
| [do-not-hook.md](do-not-hook.md) | Functions co-op relies on (script, native), its keys, data; what NightCoop finds itself and what it cannot find; `hookDeclare` |

The C header `include/nightcoop_sdk.h` is the source of truth for names and signatures; the redscript declarations are in
`redscript/NightCoop/`.
