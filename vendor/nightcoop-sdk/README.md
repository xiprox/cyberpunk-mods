# NightCoop SDK

Co-op support for other Cyberpunk 2077 mods: a mod tells NightCoop what it is, talks to the same mod on the partners'
machines, keeps shared state through the host, attaches its own data to synced entities (players, vehicles, NPCs),
shares the entities it spawns, feeds a pose source (VR, motion capture) and calls NightCoop's actions by name.

Status: version 1. The interface is a contract: see `include/nightcoop_sdk.h` (C, the source of truth) and
`redscript/NightCoop/` (redscript and CET). Start with [docs/README.md](docs/README.md).

## Layout

| Path | What |
|---|---|
| `include/nightcoop_sdk.h` | The C interface for RED4ext plugins |
| `redscript/NightCoop/NightCoopSdkNative.reds` | The class `NightCoopSdk` (static natives, top level) and the event class `NightCoopSdkEvent` — for redscript; CET reaches the same class as `NightCoopSdk.*` |
| `redscript/NightCoop/NightCoopSdk.reds` | `module NightCoop` with the enums: `@if(ModuleExists("NightCoop"))` and `import NightCoop.*` |
| `cet/nightcoop_sdk.lua` | Lua helper for Cyber Engine Tweaks mods (registration, polling in onUpdate) |
| `SECURITY.md` | Threat model: what a partner can and cannot do through the SDK, checklists for port authors and reviewers |
| `docs/` | Guides: concepts (sessions, ownership, authority), each feature, limits, versioning; [what not to hook](docs/do-not-hook.md) |
| `examples/` | A shared counter in C, redscript and Lua |
| `ports/flight/` | The co-op port of Let There Be Flight, built only on this SDK: a worked example of a full mod, with its README (what, license, install) |

## Ports

The SDK ships one port as a worked example of a full mod in co-op: what it needs from NightCoop and how it gets it.

| Mod | Author, license | Port |
|---|---|---|
| Let There Be Flight | jackhumbert, MIT | `ports/flight` — the driver's flight on partners' mirrors, passengers in a flying car |
| Mods that spawn entities (Codeware DynamicEntitySystem, CET spawners, AMM) | — | shared spawns in the core (`entityShare`), no third-party code |

## Shipping

NightCoop ships both `.reds` files in its own plugin folder (`red4ext/plugins/NightCoop/redscript/`) and adds them to the
redscript compilation itself, only when NightCoop.dll really loads. A mod that uses the SDK ships only its own files and
guards its NightCoop code with `@if(ModuleExists("NightCoop"))`: without NightCoop it compiles and runs as before.

## License

The SDK — headers, `.reds`, Lua helpers, docs, examples and the port's own code — is MIT (`LICENSE`): use it in any mod,
open or closed. The port's `THIRD_PARTY.md` keeps the notice of the mod it bridges.
