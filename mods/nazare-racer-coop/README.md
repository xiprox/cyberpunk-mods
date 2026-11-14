# Nazaré Racer copies

Two copies of the Arch Nazaré "Racer", Kuro and Shiro, so three NightCoop players can each ride one.
NightCoop treats players' vehicles of one TweakDB record as one vehicle, so each rider needs a record of their own.
[RECORD.md](RECORD.md) says what we found and where it stands.

## What's in it

The folder is laid out like the game folder.

- `r6/tweaks/nazareracercopies/nazareracercopies.yaml`: the records `Vehicle.v_sportbike2_arch_player_02_kuro` and `_shiro`, based on the Racer (`Vehicle.v_sportbike2_arch_player_02`), and added to the vehicle list.
- `archive/pc/mod/nazareracercopies_names/`: the archive holding the two names, with its `.xl`. A record's `displayName` is a hashed text key, so new text needs a localization file inside an archive.
- `build_names.py` writes that archive with no modding tools, using the game's own compression DLL.

## Building

To change a name, edit `NAMES` in `build_names.py` and build again:

```bash
python -I build_names.py
```

Check the writer against real mod files (it rebuilds the kart mod's localization file byte for byte):

```bash
python -I build_names.py --check
```

## Installing and riding

Copy `r6` and `archive` over the game folder. Everyone in the session needs both, since a partner's bike is spawned by its record.
The crew gets them through the log collector's Mods tab, which shares folders only: that's why the archive is in a folder of its own inside `archive/pc/mod`.

The host rides the original. The other two each unlock one copy in the CET console:

```lua
Game.GetVehicleSystem():EnablePlayerVehicle('Vehicle.v_sportbike2_arch_player_02_kuro',true,false)
```

```lua
Game.GetVehicleSystem():EnablePlayerVehicle('Vehicle.v_sportbike2_arch_player_02_shiro',true,false)
```
