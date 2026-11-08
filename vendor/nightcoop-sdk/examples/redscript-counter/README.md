# Shared counter, redscript

A redscript mod that uses the NightCoop SDK through the native class `NightCoopSdk`.

- Registers the mod `example.counter.redscript` (protocol 1) in `ScriptableSystem.OnAttach`. The call is repeated on every
  game load, which is safe.
- The counter is shared state under the key `count`, kept by the host. `Bump()` adds 1: on the host it sets the value, on a
  guest the same call is a request to the host. Then it sends a `ping` message (channel 1) to everyone who has the mod.
- `OnCoopEvent` (registered with `Listen`) receives the events: the new value of `count` (logged and shown on screen),
  the ping text (shown on screen) and the "partner has / does not have the mod" session events (logged).
- All NightCoop code is under `@if(ModuleExists("NightCoop"))`. Without NightCoop the stub class at the bottom of the
  file keeps `Bump()` callable and does nothing.

## Install

Put `CoopCounter.reds` where your redscript mods go:

```
Cyberpunk 2077\r6\scripts\CoopCounterExample\CoopCounter.reds
```

NightCoop provides `NightCoopSdk` and the `NightCoop` module to the redscript compiler itself when it loads. **Do not copy
NightCoop's `.reds` files into your mod**: two definitions of the same class break the compilation of every script.

Every player of a session needs the example for the counter to travel between them.

## Use

There is no key binding in the script. Call `Bump()` from the Cyber Engine Tweaks console:

```lua
Game.GetScriptableSystemsContainer():Get("CoopCounterSystem"):Bump()
```

(`Get` takes a `CName`; Cyber Engine Tweaks converts a plain string for it. The system is created by the game when a save
is loaded.)

Each call prints `count = N (set by peer P)` to NightCoop's log (lines of this mod start with
`sdk: [example.counter.redscript]`) and shows `Shared counter: N` on every player's screen; partners also see
`<name> bumped the counter`.

See `../../docs/getting-started-redscript.md`.
