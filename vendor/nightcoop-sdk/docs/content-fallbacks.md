# Content a partner may not have

Almost all mod content reaches a partner's game as a **TweakDB record** (a car, a weapon, a piece of clothing, an attack),
a **name** (a weather state, a radio station, a photo mode pose animation) or a **resource path**. These are the same on
every machine only when the mods are the same. When your mod is installed on one machine and not on the other, the
partner's game simply has no such record or name: without care a car does not appear (and its riders vanish with it), a
weapon is not in the hands, a body is naked, a pose is a bind pose, a radio station flips through the game's stations.

NightCoop shows **the game's own content of the same kind** instead — the way it does for clothes.
It picks a sensible one by itself; your mod can name a better one with `fallbackSet`.

## What NightCoop substitutes by itself

Every row is a switch (`NightCoopQuestSet("<switch>", false)` turns it off: the old behaviour). All are on by default.

| Content | When the partner lacks it | Switch |
|---|---|---|
| Clothes of a player | A plain T-shirt, trousers or shoes for the body part it covered (by the item's placement slot, sent with the look). Head, face and accessories stay empty | `look_missing_default` |
| A vehicle (shared car, traffic, a quest car) | A game vehicle of the same kind and with seats not fewer: a bike — `Vehicle.v_sportbike2_arch_player`, a 1–2 seat car — `Vehicle.v_sport2_mizutani_shion_player`, a car — `Vehicle.v_standard2_archer_hella_player`, a tank — `Vehicle.v_militech_basilisk`. The kind and the seats come from the owner (its record's `.type` and seat set). Riders sit in the same seats. The mod's appearance and paint are not applied. NightCoop never asks the game to spawn a record it does not have | `car_missing_default` |
| A weapon in a partner's hands (their body, their photo mode double) | A game weapon of the same `.itemType` (handgun, revolver, rifle, katana, …); the owner of the weapon answers which | `item_missing_default` |
| A dropped item or loot of a partner's world | Not given (the game cannot make it); one log line instead of a call on every word | `item_missing_default` |
| A hit with an attack record of a weapon mod | The hit event is built with a game attack of the same attack type (`Attacks.Bullet_GameEffect`, `Attacks.BaseExplosion`, …) | `attack_missing_default` |
| A radio station (the car's radio for passengers) | The station goes by **name** (its `ERadioStationList` member, the same in every game version that has it): the passenger's game plays the station of the same name (its number may differ). A station the passenger does not have (the 15th station of 2.5 at 2.31), or a number the owner's game has no station for (a radio mod plays) — the game station the mod named, else the passenger's own station; never set again and again | `radio_by_name` |
| A weather state of the host | A guest sets the fallback the host sends: the one the weather mod named, else a game state of the same family by name (rain, toxic rain, fog, clouds, sand, pollution, clear) | `weather_fallback` |
| A photo mode pose of a partner (their double in our photo mode) | The pose the pose mod named, else a plain standing pose (`idle_stand_02`, no weapon). The pose category is ours. The double's clothes get the same defaults as the body | `photo_pose_missing_default` |
| A vehicle a mod bought or gave (Virtual Car Dealer, Claim Any Vehicle) in a guest's garage in the host's world | Opens by its record name, read from the mod's own TweakXL files (`r6/tweaks/**.yaml`, top-level keys `Vehicle.…`) | `garage_mod_names` |
| A known mod without the SDK the partner lacks | The mods check note says what it means for them (RadioExt, AMM, EquipmentEx, Virtual Car Dealer, ArchiveXL, TweakXL, Codeware) | `mods_profiles` |

Not substituted (yet) — design your mod around it: an appearance a mod adds to a **game** vehicle or NPC (the game keeps
its own), animation sets and workspots of mods on a partner's body (skipped), effects of mods (not spawned), vehicles with
seat names of their own (the partner's body is placed where the owner says, without the seat pose), stations of RadioExt
(it plays past the game's radio: the passenger keeps its own station), shots of weapons without a magazine (NightCoop counts
shots by the magazine).

## Naming a fallback

Name fallbacks right after you register the mod. Declare `NCSDK_MOD_USES_FALLBACKS` in the passport. Name a fallback for
every record, state, station or pose of yours a partner may lack; NightCoop sends it with the content (the partner has no
record of yours to read it from), and the partner shows it only when your content is not in their game.

C:

```c
static const NcSdkModInfo info = {sizeof(NcSdkModInfo), NCSDK_MOD_ADDS_ITEMS | NCSDK_MOD_USES_FALLBACKS,
                                  "yourname.cars", "Your cars", "1.0", 1, 0, NULL};
NcSdkMod mod = api->registerMod(&info);
if (NCSDK_HAS(api, fallbackSet))
{
    api->fallbackSet(mod, NCSDK_FALLBACK_VEHICLE, "Vehicle.v_yourname_sedan_player", "Vehicle.v_standard2_archer_hella_player");
    api->fallbackSet(mod, NCSDK_FALLBACK_ITEM, "Items.yourname_rifle", "Items.Preset_Copperhead_Default");
}
```

redscript (guard it, so the mod compiles without NightCoop):

```swift
@if(ModuleExists("NightCoop"))
private func NameFallbacks() -> Void {
  NightCoopSdk.FallbackSet("yourname.cars", EnumInt(NightCoopSdkFallbackKind.Vehicle),
    "Vehicle.v_yourname_sedan_player", "Vehicle.v_standard2_archer_hella_player");
}
```

Cyber Engine Tweaks (`sdk/cet/nightcoop_sdk.lua`):

```lua
local mod = Sdk.new("yourname.cars", "Your cars", "1.0", 1, Sdk.FLAG.ADDS_ITEMS + Sdk.FLAG.USES_FALLBACKS)
registerForEvent("onInit", function()
    mod:register()
    mod:fallbackSet(Sdk.FALLBACK.VEHICLE, "Vehicle.v_yourname_sedan_player", "Vehicle.v_standard2_archer_hella_player")
end)
```

A good fallback is of the same kind and as close as you can get: a vehicle with the same seats (all game vehicles use the
seats `seat_front_left`, `seat_front_right`, `seat_back_left`, `seat_back_right`), a weapon of the same type (the partner's
body animation follows the weapon class), a weather state of the game (`24h_weather_sunny`, `24h_weather_light_clouds`,
`24h_weather_cloudy`, `24h_weather_heavy_clouds`, `24h_weather_fog`, `24h_weather_rain`, `24h_weather_toxic_rain`,
`24h_weather_pollution`, `24h_weather_sandstorm`), a radio station of the game by its `ERadioStationList` name
(`AGGRO_INDUSTRIAL`, `ELECTRO_INDUSTRIAL`, `HIP_HOP`, `AGGRO_TECHNO`, `DOWNTEMPO`, `ATTITUDE_ROCK`, `POP`, `LATINO`, `METAL`,
`MINIMAL_TECHNO`, `JAZZ`, `GROWL`, `DARK_STAR`, `IMPULSE_FM`; the radio name of your station is what the car's
`GetRadioReceiverStationName` gives while it plays), a pose of the game (`idle_stand_01` … `idle_stand_09`). The fallback must be
in every player's game: use base-game records, not Phantom Liberty ones.

A record of a vehicle or an item and a weather state or station are separate tables: `fallbackSet` with a record kind
replaces the previous fallback of that record whoever named it; the one named later wins. With the switch `sdk_fallbacks`
off, `fallbackSet` answers `NCSDK_E_OFF`; NightCoop's own defaults stay.

## Checking the partner's content yourself

Your mod may send its own names through its channels or entity state (an outfit preset, a station, a summoned car). Check
them before you use them: `contentHere(kind, name)` answers whether this game has the record, station or pose. Weather
states cannot be checked (`NCSDK_E_UNSUPPORTED`: the game has no list to ask; a guest learns only by setting one).

`peerHasKnownMod(peer, kind, name)` tells whether a partner has a mod that does **not** use the SDK — RadioExt, AMM, a car
pack — by where it lies and its folder or file name as in NightCoop's mods list (`logs/nightcoop-mods.txt`). It answers
from the mods check, so `NCSDK_E_STATE` until the check with that partner is over. For mods that use the SDK use
`peerHasMod`.

## Recipe: your mod changes how V looks beyond items

Hiding body parts, a variant of an item, V's appearance changed by a script, a swapped character — NightCoop sends only the
items of the look. Make it travel yourself, with what the SDK already has:

1. On a change, the owner sets an entity state on its **own player**: `entitySetState(mod, playerEntityHash, key, data,
   0)` (reliable: late joiners get it too). Keep `data` small: a preset id, a set of bits, a name.
2. Partners get `hooks.entityState` (or event `EntityState`) on **our body there** — `aEntity` is that body, `partnerBody(peer)`
   gives it too. Apply your change to it locally, the same way your mod applies it to V.
3. Check names you received with `contentHere` (an appearance resource of your mod the partner may lack: skip or use a game
   one). Clear the key (`entityClearState`) when the change is undone.

Declare `NCSDK_MOD_USES_ENTITY_STATE`. Nothing goes to partners without your mod.
