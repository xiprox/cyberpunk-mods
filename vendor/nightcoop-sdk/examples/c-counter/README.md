# Shared counter, C++ (RED4ext plugin)

A RED4ext plugin that uses the NightCoop SDK directly through `nightcoop_sdk.h`.

What it does:

- Registers the mod `example.counter.c` (protocol 1) the first time it finds `NightCoop.dll` (checked once a second from the
  game thread, in the RED4ext `Running` state).
- The counter lives in the mod's **shared state** under the key `count` (decimal text). The host owns it.
- **Only the host counts here**: every 30 seconds the host adds 1 and sends a `ping` message (channel 1) to everyone who has
  the mod. This keeps the example short; the host timer is not part of the SDK.
- Every player, host and guests, gets `stateChanged` for `count`: it is written to NightCoop's log and shown at the bottom
  of the screen. The ping text is shown too.
- A guest that calls `stateSet("count", ...)` would only send a *request*. The host side of that is the `stateRequest` hook
  in the code: it accepts only the key `count` with exactly the current value plus 1. (Two guests asking at the same moment
  with the same number: the second request is refused. For a real counter, send "add 1" as a channel message and let the
  host do the arithmetic.)

## Build

You need Visual Studio 2022 (C++ workload) and a checkout of RED4ext.SDK (header only).

```powershell
.\build.ps1 -Red4extSdk C:\src\RED4ext.SDK\include
# optional: -NightCoopSdk <folder with nightcoop_sdk.h>   (default: ..\..\include)
# optional: -OutDir <folder>                              (default: .\build)
```

The result is `build\NightCoopCounterExample.dll`.

## Install

Copy the dll to the game folder:

```
Cyberpunk 2077\red4ext\plugins\NightCoopCounterExample\NightCoopCounterExample.dll
```

NightCoop must be installed too (`red4ext\plugins\NightCoop\NightCoop.dll`). Every player of a session needs the example
for the counter to travel between them (the mod's passport and protocol must match).

## What you should see

In NightCoop's log, lines of this mod start with `sdk: [example.counter.c]`. Once NightCoop is up:

```
registered, NightCoop build <stamp>
```

Host and guest in a session, both with the plugin:

- on each side a line that the other player has the counter mod (`NCSDK_EV_PEER_MOD`);
- every 30 s on the host: `count = N (set by ...)`, the same line on the guest a moment later, and the on-screen message
  `Shared counter: N` on both;
- a ping message `<name> bumped the counter` on the guest.

A partner without the plugin sees nothing, and (because of `NCSDK_MOD_NEEDED_BY_ALL`) both players get a short note that
the mod is missing on the other side.

See `../../docs/getting-started-c.md` for the connection steps this file follows.
