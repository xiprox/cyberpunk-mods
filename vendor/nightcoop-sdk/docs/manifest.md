# The manifest: a mod without code

A mod made only of data — a car (TweakXL + ArchiveXL), clothes, a quest phase in an archive, a tweak — has no code that
could call the SDK. A small text file next to it tells NightCoop what the mod is and what it needs in a session.

## Where

A file named `<anything>.nightcoop`, in any of the mod folders of the game, up to three levels deep:

| Folder | Example |
|---|---|
| `archive/pc/mod/` | `archive/pc/mod/MyCar/mycar.nightcoop` |
| `r6/tweaks/` | `r6/tweaks/MyCar/mycar.nightcoop` |
| `r6/scripts/` | `r6/scripts/MyMod/mymod.nightcoop` |
| `red4ext/plugins/`, `mods/` (REDmod), `bin/x64/plugins/cyber_engine_tweaks/mods/` | the same |
| `r6/nightcoop/` | a folder for manifests only |

NightCoop reads them once, when the game starts (at most 64 manifests, 64 KiB each). The log says what it
took: `sdk: [author.my_car] by its manifest archive/pc/mod/MyCar/mycar.nightcoop — …`. The switch `sdk_manifests` (on) turns the reading off in
`switches.txt`.

## Format

Lines `key = value`, `#` starts a comment, UTF-8.

    # My Car — a TweakXL vehicle
    id = author.my_car              # required: [a-z0-9._-], 3..64 bytes, stable
    name = My Car
    version = 1.2
    protocol = 1                    # your data version; for a mod without code leave it 1
    flags = needed_by_all, adds_items, changes_quests

    # quest facts that are each player's own (not mirrored from the host; kept at the entry into the host's world)
    fact = mycar_owned
    facts = mycar_tuning_a, mycar_tuning_b

    # script systems of the mod (for a mod with redscript but no NightCoop code): the world's or each player's own
    world_system = MyCar.GarageSystem
    character_system = MyCar.TuningSystem

    # a record of the mod a partner without the mod does not have — they get a record of the game instead
    fallback = Vehicle.v_mycar_player -> Vehicle.v_standard2_archer_quartz_player
    fallback = Items.MyCar_Jacket -> Items.Jacket_01_basic_01

| Key | What | Needs the flag |
|---|---|---|
| `id`, `name`, `version`, `protocol` | The passport, as `registerMod` | — |
| `flags` | Passport flags by name: `needed_by_all`, `local_only`, `changes_world`, `changes_quests`, `adds_items`, `spawns_entities`, `host_authority`, `uses_save`. Flags of code (channels, state, pose, actions, menu, votes) are skipped | — |
| `fact`, `facts` | `factKeepLocal` for each | `changes_quests` |
| `world_system`, `character_system` | `scriptableScope` (applied when the game's scripts are loaded: the first player in a world) | `uses_save` |
| `fallback` | `record -> record` (TweakDB names or `0x…` ids): what a partner without the mod sees instead | — |

The rights are those of a passport: what the flags do not declare is refused (one log line). A manifest cannot do anything
the mod's own code could not. List only the facts your mod itself writes: a fact of the main story must stay the world's.

## A mod that has code too

If the mod's own code registers the same id (a plugin or scripts), the code takes over the manifest's entry: the same
handle, the facts, scopes and fallbacks of the manifest stay, the passport becomes the code's. A manifest of a mod whose
code registered first is not needed and is skipped with a log line.
