# Getting started: Cyber Engine Tweaks (Lua)

Cyber Engine Tweaks exposes every RTTI class as a global, so the class `NightCoopSdk` is available in Lua:
`NightCoopSdk.InSession()`, `NightCoopSdk.Send(...)`. You can call it from the CET console or from a CET mod. A complete mod:
[`examples/lua-counter/`](../examples/lua-counter/).

You do not need redscript for this. (With redscript installed, you also get scripted event objects; the helper below uses
them when they exist.)

## Use the helper

`sdk/cet/nightcoop_sdk.lua` wraps the class: it checks that NightCoop is there, registers your mod, polls events and decodes
them, and does nothing (quietly) when NightCoop is absent. Copy it into your mod folder next to `init.lua`:

```
bin/x64/plugins/cyber_engine_tweaks/mods/YourMod/init.lua
bin/x64/plugins/cyber_engine_tweaks/mods/YourMod/nightcoop_sdk.lua
```

```lua
local Sdk = require("nightcoop_sdk")

local mod = Sdk.new("yourname.yourmod", "Your Mod", "1.0.0", 1, Sdk.FLAG.NEEDED_BY_ALL + Sdk.FLAG.USES_CHANNELS)

registerForEvent("onInit", function()
    mod:register()                -- safe to repeat
end)

registerForEvent("onUpdate", function(dt)
    mod:poll(function(ev)         -- at most 32 events per frame by default
        if ev.kind == Sdk.EVENT.STATE and ev.key == "count" then
            print("count is now " .. ev.data)
        end
    end)
end)
```

`Sdk.new(id, name, version, protocol, flags)`: the id is `[a-z0-9._-]`, 3..64 bytes, stable forever; `protocol` is your own wire
version; `flags` is a sum of `Sdk.FLAG.*`.

## Helper reference

| Call | What |
|---|---|
| `Sdk.available()` | NightCoop is here and its SDK is on (`Version() > 0`) |
| `mod:register()` | Register or update the mod. `true` on success. Safe to call again |
| `mod:unregister()` | |
| `mod:poll(handler [, maxPerFrame])` | In `onUpdate`. Registers by itself if that did not work yet (retries every 5 s). Calls `handler(ev)` for each queued event. Returns how many |
| `mod:send(to, channel, text, reliable)` | `to`: a peer, `Sdk.PEER_HOST` (0) or `Sdk.PEER_ALL` (-2). Returns peers reached, or a negative code |
| `mod:setState(key, value)` / `mod:removeState(key)` | Shared state. Host: set and spread. Guest: ask the host |
| `mod:getState(key)` | The value as a string, or `nil` if the key is not set |
| `mod:setEntityState(entity, key, value, stream)` / `mod:clearEntityState(entity, key)` | Owner only. `entity` is an `EntityID` |
| `mod:log(level, text)` / `mod:showMessage(text, seconds, tone)` | |
| `mod:peerHasMod(peer)` / `mod:peerModVersion(peer)` | |
| `Sdk.inSession()`, `Sdk.isHost()`, `Sdk.inWorld()`, `Sdk.inHostWorld()`, `Sdk.localPeer()`, `Sdk.peers()`, `Sdk.peerName(peer)`, `Sdk.peerInOurWorld(peer)` | Session |
| `Sdk.entityRef(entity)`, `Sdk.entityOfRef(ref)`, `Sdk.entityIsMine(entity)`, `Sdk.partnerBody(peer)` | Entities |
| `Sdk.pick(ru, en)` | A label in the game's UI language |
| `Sdk.toU64(v)`, `Sdk.splitRef(ref)` | 64-bit helpers, see below |
| `Sdk.RESULT`, `Sdk.FLAG`, `Sdk.LOG`, `Sdk.TONE`, `Sdk.EVENT`, `Sdk.SESSION`, `Sdk.NET`, `Sdk.PEER_*` | Constants, same numbers as in redscript |

When NightCoop is absent, `Int32` helpers return `Sdk.RESULT.UNSUPPORTED` (-4), booleans `false`, `getState` `nil`.

## Events

Lua cannot be a `Listen` target, so you poll in `onUpdate`. `poll` takes events with `NightCoopSdk.PollEvent(id)` when the
scripted event class exists (redscript installed), otherwise with `NightCoopSdk.PollEventText(id)`. Both give the same table:

| Field | Meaning |
|---|---|
| `ev.kind` | `Sdk.EVENT.SESSION` 1, `MESSAGE` 2, `STATE` 3, `ENTITY_STATE` 4, `PARTNER_POSE` 5, `SHARED_SPAWN` 6 |
| `ev.peer` | Session: the peer it is about. Message: the sender. State: who set it. Entity state: the owner |
| `ev.a` | Session: `Sdk.SESSION.*`. Message: the channel. Entity state: the key. Shared spawn: 1 appeared / 0 gone |
| `ev.key` | State: the shared-state key |
| `ev.removed` | The state key or entity-state key was removed or cleared |
| `ev.data` | The payload as a Lua string of raw bytes |
| `ev.entityHash` | Decimal `EntityID` hash of **our** mirror/copy (`"0"` if none) |
| `ev.entity` | The `EntityID`, only when the event came as an object; otherwise `nil` (use `Sdk.entityOfRef(ev.ref)`) |
| `ev.ref` | The packed network reference |
| `ev.source` | `"object"` or `"text"` |

The helper decodes the text line of `PollEventText` (tab-separated; its fields are listed in the comment of `PollEventText`
in `NightCoopSdkNative.reds`). The text line carries no pose fields: for `PARTNER_POSE` use the object path.

## Uint64 values

`Uint64` values (the reference, the entity hash) come to Lua as `cdata` (`ULL`). Do not convert them with `tonumber`: above
2^53 they lose digits, and a packed reference is always above that. Compare with `tostring` or keep them as `cdata`.
`Sdk.toU64("123")` builds a `cdata` from a decimal string; `Sdk.splitRef(ref)` returns `kind, owner, id` as plain numbers
(owner `16777215` means none).

## Bytes

Byte arrays are slow in Lua (they are tables). Use the text variants: `Send`, `SetState`, `SetEntityState`. They take Lua
strings; keep payloads small.

## Without the helper

```lua
-- The class exists only when NightCoop is loaded; guard the lookup.
local ok, version = pcall(function() return NightCoopSdk.Version() end)
if ok and version > 0 then          -- 0: the player switched the SDK off
    NightCoopSdk.RegisterMod("yourname.yourmod", "Your Mod", "1.0.0", 1, 1)
end
-- in onUpdate:
local line = NightCoopSdk.PollEventText("yourname.yourmod")   -- "" when the queue is empty
```

Try calls from the console too: `NightCoopSdk.InSession()`, `NightCoopSdk.Peers()`, `NightCoopSdkStatus()`.
