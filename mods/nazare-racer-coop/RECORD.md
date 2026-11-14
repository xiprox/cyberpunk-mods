# Record

What we found and decided while making the Nazaré Racer copies, newest entry first.
[README.md](README.md) says what the mod is; this file says why it's that way.

"User" marks what the user saw in the game. "Logs" marks what the collected logs show.

Installed: nowhere now. On 2026-11-14 neither folder is in this PC's game folder, and on 2026-11-13 no player's `nightcoop-mods.txt` lists the tweak. All three games had the records on 2026-11-08 (logs, below).
Not yet checked in the game: the names on screen, and all three bikes ridden at once.

## 2026-11-08: Both copies in a session

Logs: Bleack rode the Shiro, and Bossun's game spawned its mirror from that record (the vehicle customizer's RECORD.md has the details). The user's game had the Shiro too, and Bossun's game had the Kuro out (`attached: Vehicle.v_sportbike2_arch_player_02_kuro`).
Bleack's Shiro was in a session again on 2026-11-09. So the records work on Bleack's Linux install as well.

## 2026-11-02: Two copies, and their names from an archive

- NightCoop (build bacb705) treats players' vehicles of one TweakDB record as one: a guest's own bike becomes the mirror of the host's ("our own entity becomes its mirror", `player_car_record`, `player_car_place`). Logs showed it on the Racer, record 0x239d486ca8.
- The Racer is `Vehicle.v_sportbike2_arch_player_02`; plain `_player` is the base Nazaré and `_03` the Kobold.
- A record's `displayName` is a hashed text key, so a new name needs a localization file in an archive. `build_names.py` writes it with no WolvenKit, and `--check` rebuilds the kart mod's localization file byte for byte.
- The game loads an `.archive` from a folder inside `archive/pc/mod`, on this PC: at the main menu it held that archive open just as it held `kart.archive`, and ArchiveXL logged "All translations merged" with no errors. A folder is what the collector's Mods tab can share.
- The two folders' names differ (`nazareracercopies` and `nazareracercopies_names`) because the collector's Mods tab hid a second folder of the same name that day.
- The user said not to bother checking whether NightCoop counts a modded bike as the player's own in the host's world.
