# Record

What we found and decided while making No carry weight, newest entry first.
[README.md](README.md) says what the mod is; this file says why it's that way.

"User" marks what the user saw in the game. "Logs" marks what the collected logs show.

Installed: on the user's PC since 2026-11-05. Logs: on 2026-11-13 the user's and Ecto's games had it, and Bleack's and Bossun's didn't.
Not yet checked in the game: anything in co-op. It was loaded in the session of 2026-11-13, but nobody has said how it went.

## 2026-11-05: 1000 more, seen working

- The file appends a +1000 `BaseStats.CarryCapacity` modifier to `Character.Player_Primary_Stats_Base`. The user chose 1000 over 100000 to keep the menus' readout short.
- Seen working that day (user): TweakXL logged no error, the save picked up the limit, and the inventory showed 252/1271 with no layout trouble.
- It hooks no function, and that record isn't in the SDK's "Data co-op relies on" table, so nothing goes through NightCoop.
