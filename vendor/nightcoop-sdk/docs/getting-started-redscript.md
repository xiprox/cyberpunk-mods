# Getting started: redscript

redscript mods use the native class `NightCoopSdk`: static functions that mirror the C interface. NightCoop adds the
declarations to the redscript compilation itself, only when NightCoop really loads. A complete mod:
[`examples/redscript-counter/`](../examples/redscript-counter/).

## Do not copy NightCoop's .reds files

The files `NightCoopSdk.reds` and `NightCoopSdkNative.reds` ship inside NightCoop's plugin folder
(`red4ext/plugins/NightCoop/redscript/`). **Do not copy them into your mod.** Two definitions of the same class break the
compilation of every script. They are in the SDK folder for reading only.

What they declare:

- module `NightCoop`: the enums `NightCoopSdkResult`, `NightCoopSdkModFlag`, `NightCoopSdkEventKind`, `NightCoopSdkSessionEvent`,
  `NightCoopSdkPoseBit`;
- at top level: the native class `NightCoopSdk` and the scripted class `NightCoopSdkEvent` (NightCoop creates its instances).

## Make the mod compile without NightCoop

Without NightCoop (not installed, or not loaded) the module `NightCoop` does not exist,
`@if(ModuleExists("NightCoop"))` is false, and the code under it is not compiled. The game starts normally. So guard
every piece of code that touches NightCoop, and give it a stub:

```swift
@if(ModuleExists("NightCoop"))
import NightCoop.*

@if(ModuleExists("NightCoop"))
private func CoopSend(text: String) -> Void {
  NightCoopSdk.Send("yourname.yourmod", -2, 1, text, false);
}

@if(!ModuleExists("NightCoop"))
private func CoopSend(text: String) -> Void {}
```

`import NightCoop.*` brings the enums. Flags and events are enum values; convert with `EnumInt(...)`.

## Register

Register once per load, in a `ScriptableSystem`'s `OnAttach`. The call runs again on every game load, which is safe: with the
same id it updates name, version, flags and protocol and returns `true`. If the same id is registered by a C plugin, scripts
get `false`.

```swift
@if(ModuleExists("NightCoop"))
public class MyCoopSystem extends ScriptableSystem {

  private func OnAttach() -> Void {
    if NightCoopSdk.Version() == 0 {
      return; // 0: the player switched the SDK off
    }
    // Declare every use: an undeclared one answers Denied (sdk/SECURITY.md)
    let flags: Int32 = EnumInt(NightCoopSdkModFlag.NeededByAll) | EnumInt(NightCoopSdkModFlag.UsesChannels);
    if NightCoopSdk.RegisterMod("yourname.yourmod", "Your Mod", "1.0.0", 1, flags) {
      NightCoopSdk.Listen("yourname.yourmod", this, n"OnCoopEvent");
    };
  }

  protected cb func OnCoopEvent(evt: ref<NightCoopSdkEvent>) -> Void {
    if evt.kind == EnumInt(NightCoopSdkEventKind.State) && Equals(evt.key, "count") {
      // evt.data is the new value as text
    };
  }
}

@if(!ModuleExists("NightCoop"))
public class MyCoopSystem extends ScriptableSystem {
}
```

Arguments of `RegisterMod`: id (`[a-z0-9._-]`, 3..64 bytes, stable forever), display name, version string, `protocol`
(your own wire version) and `flags` (a bit set: `EnumInt(A) | EnumInt(B)`, see [api.md](api.md)).

## Receive events: Listen or PollEvent

**`Listen(id, target, function)`** makes NightCoop call `target.function(event)` on the game thread, once per event, from its
frame, instead of queueing the events.

- The function must take **exactly one parameter**, `ref<NightCoopSdkEvent>`. `Listen` returns `false` otherwise.
- Mark it `cb func` and give the name as a `CName`: `n"OnCoopEvent"`.
- The target is held weakly. When it dies (the world unloads), events go back to the queue. Call `Listen` again on the next
  `OnAttach`, as the example does.
- `NightCoopSdk.Listen(id, null, n"")` stops the callback.

**`ListenFrame(id, target, function)`** makes NightCoop call `target.function(dt: Float)` every frame while the player is
in a world — the place for work your mod does each frame (look at what the game does, feed visuals from a partner's stream).
A chain of `DelaySystem.DelayCallbackNextFrame` stops when the game loads a save; this keeps going. Call it from `OnAttach`
next to `Listen`.

**`PollEvent(id)`** returns the next queued event, or `null`. Use it if you prefer to pull, for example from your own update
loop. The queue holds up to 1024 events per mod; the oldest drop.

Fields of `NightCoopSdkEvent`:

| Field | Meaning |
|---|---|
| `kind` | `NightCoopSdkEventKind`: `Session` 1, `Message` 2, `State` 3, `EntityState` 4, `PartnerPose` 5, `SharedSpawn` 6 |
| `peer` | Session: the peer it is about. Message: the sender. State: who set it. EntityState: the owner |
| `a` | Session: `NightCoopSdkSessionEvent`. Message: the channel. EntityState: the key. SharedSpawn: 1 appeared / 0 gone |
| `key` | Shared-state key (State events) |
| `removed` | The state key or the entity-state key was removed or cleared |
| `data` | The payload as text. Empty if it is not valid UTF-8 |
| `bytes` | The payload as `array<Uint8>`, always |
| `entity` | EntityState, SharedSpawn: **our** local mirror/copy (`EntityID`) |
| `ref` | The network reference, packed in a `Uint64` (kind 8, owner 24, id 32 bits) |
| `poseValid`, `head`, `leftHand`, `rightHand`, `aimOrigin`, `aimDir` | PartnerPose; `poseValid` 0 means the source is gone |

## Calling the API

```swift
NightCoopSdk.Send("yourname.yourmod", -2, 1, "hello", false);   // to everyone who has the mod, unreliable
NightCoopSdk.SetState("yourname.yourmod", "count", "7");          // host: set and spread; guest: ask the host
let count: String = NightCoopSdk.GetState("yourname.yourmod", "count");
```

Every function takes your mod id as its first argument. Peers are `Int32`: the host is `0`, "everyone" is `-2`, "none" is
`-1`. `Int32` results are `0` or a positive count on success and a negative `NightCoopSdkResult` on failure. All functions
are listed in [api.md](api.md).
