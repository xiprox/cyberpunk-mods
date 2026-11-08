# Getting started: C / C++ (RED4ext plugin)

You use `include/nightcoop_sdk.h` directly. It is plain C: numbers, UTF-8 strings, byte buffers and function pointers. No
C++ types cross the boundary, so any compiler works. NightCoop is a RED4ext plugin itself (`NightCoop.dll`); your plugin
talks to it through one exported function.

A complete plugin: [`examples/c-counter/`](../examples/c-counter/).

## 1. Find NightCoop

NightCoop.dll exports `NightCoopSdkGet` (`NCSDK_EXPORT_NAME`):

```c
const NcSdkApi* NightCoopSdkGet(uint32_t aVersion);
```

RED4ext loads plugins in an unknown order, so **do not look in `DllMain` or in `Main(Load)`**. Look from the game thread
later: on the first tick of a RED4ext game state, for example `Running`. If NightCoop is not there yet, try again a moment
later (once a second is plenty):

```cpp
HMODULE nc = GetModuleHandleW(L"NightCoop.dll");
if (!nc) return;                                   // not loaded (yet), or not installed
auto get = (NcSdkGetFn)GetProcAddress(nc, NCSDK_EXPORT_NAME);
const NcSdkApi* api = get ? get(NCSDK_VERSION) : nullptr;
if (!api) return;                                  // no interface of this version, or the player switched the SDK off
```

`api == NULL` means: work as if NightCoop were absent. Your mod must still do whatever it does on its own.

The state callback that does the lookup:

```cpp
static RED4ext::v1::GameState g_state;

bool OnRunningUpdate(RED4ext::CGameApplication*) { if (!g_mod) TryConnect(); return false; }

RED4EXT_C_EXPORT bool RED4EXT_CALL Main(RED4ext::v1::PluginHandle aHandle, RED4ext::v1::EMainReason aReason,
                                        const RED4ext::v1::Sdk* aSdk)
{
    if (aReason == RED4ext::v1::EMainReason::Load)
    {
        g_state.OnEnter = nullptr;
        g_state.OnUpdate = &OnRunningUpdate;
        g_state.OnExit = nullptr;
        aSdk->gameStates->Add(aHandle, RED4ext::EGameStateType::Running, &g_state);
    }
    else if (g_api && g_mod)
    {
        g_api->unregisterMod(g_mod);        // Unload
        g_api = nullptr; g_mod = 0;
    }
    return true;
}
```

## 2. Check the table

`NcSdkApi` is a table of function pointers. Its `size` field says how big the table of the running NightCoop is. New functions
are only ever added to the end of the table without changing `NCSDK_VERSION`, so a function added after your first release
may be missing in an older NightCoop. Check it before calling:

```c
if (NCSDK_HAS(api, pollEvent)) { /* safe to call */ }
```

`NCSDK_HAS(api, field)` is true when the table is big enough to contain the field and the pointer is not NULL.
See [limits-and-versions.md](limits-and-versions.md).

## 3. Register the mod

```c
static NcSdkHooks hooks = {};
hooks.size = sizeof(hooks);
hooks.context = nullptr;                 // passed back as the first argument of every callback
hooks.message = &OnMessage;
hooks.stateChanged = &OnStateChanged;
hooks.shutdown = &OnShutdown;            // leave the rest NULL

NcSdkModInfo info = {};
info.size = sizeof(info);
info.flags = NCSDK_MOD_NEEDED_BY_ALL | NCSDK_MOD_USES_CHANNELS; // NCSDK_MOD_*: declare every use (permissions)
info.id = "yourname.yourmod";            // ASCII [a-z0-9._-], 3..64 bytes, stable forever
info.name = "Your Mod";
info.version = "1.0.0";
info.protocol = 1;                       // your own wire version
info.hooks = &hooks;                     // may be NULL: then poll with pollEvent

NcSdkMod mod = api->registerMod(&info);
if (!mod) { /* refused: see NightCoop's log; the mod keeps working without co-op */ }
```

`registerMod` returns a handle, `0` when refused: a bad id, an id already registered, too many mods (64), or a hash collision with
another id. The reason is written to NightCoop's log. The strings and the hooks struct are copied.

No hook is called from inside `registerMod`: the first events come with NightCoop's next frame, after the call has returned
and you have stored the handle. When you register in the middle of a session, NightCoop gives you the current picture as events
(`NCSDK_EV_SESSION_START`, `NCSDK_EV_PEER_JOIN` for each peer, `NCSDK_EV_PEER_WORLD_IN` for each peer in your world, then
`NCSDK_EV_PEER_MOD` / `NCSDK_EV_PEER_NO_MOD` as passports arrive).

## 4. Hooks

All hooks run on the game thread. Do not block in them.

| Hook | When |
|---|---|
| `frame(ctx, dt)` | Every game frame while NightCoop runs, after its own tick. `dt` in seconds |
| `event(ctx, NCSDK_EV_*, peer)` | Session events: session start/end, a player joined/left, entered/left our world, has/has not your mod. `peer` is `NCSDK_PEER_NONE` for the session itself |
| `message(ctx, from, channel, data, size)` | A channel message of your mod |
| `stateChanged(ctx, key, data, size, by)` | A shared state key changed. Also once per key after you join a session. `size 0` with `data NULL`: removed |
| `stateRequest(ctx, from, key, data, size)` | **Host only**: a guest asks to set a key. Return `1` to accept, `0` to refuse. `NULL`: accept everything |
| `entityState(ctx, from, entity, ref, key, data, size)` | Entity state of your mod from the entity's owner, laid on **your** local mirror/copy `entity`. Comes again if the mirror appears later |
| `partnerPose(ctx, peer, pose)` | A partner's pose source changed (`pose NULL`: gone) |
| `sharedSpawn(ctx, owner, ref, entity, present)` | A shared spawn of a partner appeared here (`1`, `entity` is our copy) or is gone (`0`) |
| `shutdown(ctx)` | NightCoop is unloading (game exit). Stop, never call the table again |

A hook you leave `NULL` is not an error: items of that kind go to the mod's poll queue (`pollEvent`) instead, kept up to 1024 items
(the oldest drop). If you never poll, they just fall off.

## 5. Use the table

Everything below is called with your handle. A few examples; the whole list is in [api.md](api.md).

```c
NcSdkWhere where = {}; where.size = sizeof(where);
api->where(&where);                                   // inSession, isHost, inWorld, localPeer, ...

api->stateSet(mod, "count", "7", 1);                  // host: set and spread; guest: ask the host
api->send(mod, NCSDK_TO_ALL, 1, "hi", 2, 0);          // channel 1, unreliable, everyone who has the mod
api->showMessage(mod, "Hello", 3.0f, NCSDK_TONE_INFO);
```

Results: `int32_t` functions return `NCSDK_OK` (0) or a positive count on success, a negative `NCSDK_E_*` on failure.

## 6. Unregister and shut down

- On unload of your plugin (`Main(Unload)`): `api->unregisterMod(mod)`.
- If NightCoop unloads first it calls `hooks.shutdown`. From that moment do not call the table: its memory goes away with
  `NightCoop.dll`. Set your `api` pointer to `NULL` in that hook and have every code path check it.

## Threads

Everything is the game thread (RED4ext game-state updates, script natives, NightCoop's frame) unless a function says
"any thread" in the header. `log`, `showMessage` and `pick` are marked any thread. Callbacks come on the game thread.
