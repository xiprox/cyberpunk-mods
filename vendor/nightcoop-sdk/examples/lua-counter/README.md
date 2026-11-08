# Shared counter, Cyber Engine Tweaks (Lua)

A CET mod that uses the NightCoop SDK through the native class `NightCoopSdk` and the helper `nightcoop_sdk.lua`.

- Registers the mod `example.counter.lua` (protocol 1) in `onInit`; `poll()` registers again by itself if NightCoop was not
  ready yet.
- The counter is shared state under the key `count`, kept by the host. The hotkey **Shared counter +1** adds 1: on the host
  it sets the value, on a guest the same call is a request to the host. Then it sends a `ping` message (channel 1) to
  everyone who has the mod.
- `onUpdate` calls `counter:poll(onEvent)`. The handler logs the new value, shows it on screen, shows the ping text, and
  logs when a partner has or lacks the mod.
- Without NightCoop (or with its SDK switched off) every helper call does nothing, and the hotkey prints one line.

## Install

Copy two files into one mod folder:

```
Cyberpunk 2077\bin\x64\plugins\cyber_engine_tweaks\mods\CoopCounterExample\init.lua
Cyberpunk 2077\bin\x64\plugins\cyber_engine_tweaks\mods\CoopCounterExample\nightcoop_sdk.lua   <- from sdk\cet\
```

`require("nightcoop_sdk")` loads the helper from the same folder. Every player of a session needs the example for the
counter to travel between them.

Bind the hotkey in the CET overlay: **Bindings**, entry *Shared counter +1* of this mod.

## What you should see

Host and guest in a session, both with the mod: after a hotkey press on either side, `Shared counter: N` at the bottom of
both screens, `count = N (set by peer P)` in NightCoop's log (lines of this mod start with `sdk: [example.counter.lua]`),
and on the other player the ping `<name> bumped the counter`.

A press on a guest is a request: the value changes when the host's answer comes back. Two players pressing at the same
moment can lose one increment; for a real counter send "add 1" as a channel message and let the host add.

No redscript is needed: without it the helper reads events through `NightCoopSdk.PollEventText`.

See `../../docs/getting-started-cet.md`.
