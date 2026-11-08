# Limits and versions

## Limits

| What | Limit | C constant |
|---|---|---|
| Mod id | ASCII `[a-z0-9._-]`, 3..64 bytes | `NCSDK_ID_MAX` 64 |
| Mods registered at once | 64 | |
| Shared-state key | 64 bytes UTF-8 | `NCSDK_STATE_KEY_MAX` 64 |
| Shared-state value | 4096 bytes | `NCSDK_STATE_VALUE_MAX` 4096 |
| Shared-state keys per mod | 256 | `NCSDK_STATE_KEYS_MAX` 256 |
| Unreliable message, or entity-state stream | 1024 bytes | `NCSDK_UNRELIABLE_MAX` 1024 |
| Reliable message | 16384 bytes | `NCSDK_RELIABLE_MAX` 16384 |
| Entity state value (either mode) | 1024 bytes | `NCSDK_ENTITY_STATE_MAX` 1024 |
| Entity-state key, channel | `uint16_t` (0..65535), your own numbering | |
| Poll queue | 1024 items per mod, the oldest are dropped | |
| Rate per mod and direction | 32768 bytes/s and 120 messages/s, averaged over a second | `NCSDK_RATE_BYTES_PER_S`, `NCSDK_RATE_MESSAGES_PER_S` |
| Script systems a mod speaks of (`scriptableScope`) | 32 per mod, class name 128 bytes | `NCSDK_SCOPES_MAX`, `NCSDK_CLASS_NAME_MAX` |
| Items in the co-op menu | 8 per mod, 32 in all; key 32 bytes `[a-z0-9._-]`, label 80 bytes | `NCSDK_MENU_ITEMS_MAX`, `NCSDK_MENU_KEY_MAX`, `NCSDK_MENU_LABEL_MAX` |
| A vote | one at a time in a session; 2..8 options; key 32 bytes; question 160, option 80 bytes per language; up to 16 voters | `NCSDK_VOTE_*_MAX` |
| Manifests | 64 per game, 64 KiB each, `*.nightcoop`, up to three folders deep | |
| World asks (`worldAsk`) | one in 2 seconds per mod (two in a row), the host takes one in 2 seconds per player; 16 waiting per guest; a weather state name 64 bytes | |

**Rates.** Short bursts up to 4 times the rate are allowed. The rate covers channel messages, shared
state and entity state of the mod together. Going over it on the way out returns `NCSDK_E_LIMIT` and nothing is sent. Over it
on the way in from one peer, NightCoop drops the data and counts it; this protects you from a partner's broken build. Design
for it: send state when it changes, not every frame, and put continuously changing values in an entity-state **stream**
(`NCSDK_STATE_STREAM`) or an unreliable message with `NCSDK_SEND_LATEST_ONLY`.

A pose source is sent at about 30 Hz.

Strings are UTF-8. Sizes are in bytes.

## Interface version

`NCSDK_VERSION` is `1`. `NightCoopSdkGet(version)` returns `NULL` when NightCoop has no interface of that version, or when the
player switched the SDK off. Scripts: `NightCoopSdk.Version()` returns `0` in the second case.

Everything in these guides is version 1: a NightCoop that gives you the table (C) or has the module `NightCoop`
(redscript, CET) has all of it.

`NCSDK_VERSION` changes **only on an incompatible change**. Everything else will be added in a way that old code still
works:

- New functions go **only to the end of `NcSdkApi`**.
- New callbacks go only to the end of `NcSdkHooks`.
- New fields go only to the end of structs that carry a `size` field (`NcSdkApi`, `NcSdkHooks`, `NcSdkModInfo`, `NcSdkWhere`,
  `NcSdkPose`, `NcSdkPolled`).
- New natives of the script class go to the end of the class.

What this means for you:

- Set the `size` field of every struct you pass in to `sizeof` of your copy of the header: it tells NightCoop which fields
  your build has.
- A function added after version 1 may be missing in the NightCoop the player has. Check it before calling:
  `NCSDK_HAS(api, field)` is true when `api->size` covers the field and the pointer is not NULL. The same table can come from an
  older NightCoop of the same `NCSDK_VERSION`.

### redscript: natives added later

A redscript mod is compiled on the player's machine against the `.reds` of the NightCoop the player has. A call to a native
that this NightCoop does not declare is a compile error — and one compile error stops the compilation of **every** script
mod of the player. `@if(ModuleExists("NightCoop"))` would not help there: the module is there, only the function is not.

So natives added after version 1 will come with a marker module of their own: a small file next to the SDK's `.reds` that
declares a module named in these guides when it appears. NightCoop.dll adds the SDK's `.reds` to the compilation by name,
and a marker only when it registers its natives; guard calls to them with `@if(ModuleExists("<that module>"))`. For
everything in version 1, `@if(ModuleExists("NightCoop"))` is enough. In CET, check that the class has a later function
before calling it.

## Your mod's `protocol`

`NcSdkModInfo.protocol` (scripts: the `protocol` argument of `RegisterMod`) is your own wire version, unrelated to
`NCSDK_VERSION`. Data goes only between players who registered the same mod id **and the same protocol**. Anyone else gets
`PeerHasMod` = 0 and `NCSDK_EV_PEER_NO_MOD`.

Change it when the meaning or layout of your data changes in a way an older copy of your mod cannot read: new message formats,
a different encoding of a state value, new meaning of an entity-state key. Do not change it for compatible additions (a new
key that old versions ignore).

`NcSdkApi.protocol` is NightCoop's own wire version; it is informational. `NcSdkApi.build` is the build stamp (commit) of the
running NightCoop, handy for log lines.
