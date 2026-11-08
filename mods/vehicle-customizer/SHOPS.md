# Shop candidates

Places in Night City that could become the mechanic's shop: garages that already exist, that a car might get into, and that the game leaves quiet.
The idea (user, 2026-11-06): **different shops sell different parts**. A legit shop with police parts makes no sense ("how did he get them???"), but a shady shop out in the Badlands might easily have them.
**Decided (user, 2026-11-06):** shops with a clear owner, such as a gang's garage, lean heavily into that owner's style, or a style that clearly fits them. One neutral-looking big shop, if there is one, is the "has everything" place. (Now two, neither neutral: Hal's workshop, the Mox shop, and Dakota's, both with everything legal; 2026-11-06 and 2026-11-07.)

Everything here comes from the game's files, not from looking ([RECORD.md](RECORD.md), 2026-11-06), so for each place it's still unknown whether the door opens, whether a car fits through it, and how it looks.
"Gig" means the game's own job at that spot (a fixer's gig or an NCPD job): it comes alive while that job runs and is quiet otherwise, as far as the files show.
**People** counts the spots near the place where the game puts someone (people working, sitting, guards), within 25 m. A gig's enemies count too, though they may only show up during the gig.
**Feel** is a guess from who the job involves (a mechanic, a gang, scavengers) and the setting.

## How we pick them (user, 2026-11-06)

1. The user goes near a place with the dev mod's **Shop scouting** window (opens with CET's overlay): "Go near" holds V in the air while the place loads, then sets V down on walkable ground about 50 m away, facing it, so a gig's or gang's fight doesn't start on arrival. It also pins the place on the map (each place has a pin box, with "Pin all" and "Clear pins"; pins go at the place's own coordinates and last until the next load), and a line shows how far the nearest place is and which way ("42 m ahead-left, 3 m above"). The capture key (Page Down) saves a screenshot and what V looks at (position, the looked-at point and object, the nearest place and its job's journal state) to `dev/captures/<time>.jpg` and `.json`, while `tools/capture-watcher.ps1` runs beside the game. Each place's Copy button puts `[jake_estevezs_garage] Jake Estevez's garage, Heywood, The Glen (-1439.1, -1293.8, 46.8)` on the clipboard, to paste in chat. "5 m ahead" and "10 m ahead" step V forward through walls and shut doors. "Back to where I was" undoes the last of these, "Kill enemies within 100 m" clears hostiles and gang members (not police or civilians), and "Mark this spot" writes where V stands and a note to `scout-marks.txt` in the dev mod's folder in the game.
2. The user looks around and says what it feels like, and asks about lore, quests, and how the place changes before and after its job.
3. We decide whether it becomes a shop, and if so, how: what it sells, where the car goes, where the stand is.
4. It's logged under **Visits** below, with the marks.
5. Later we review the whole set and reorganize or re-decide.

## Coverage

Which of the catalog's style families have a shop (2026-11-06; models counted from the catalogs' style names):

| Family | Models | Shop |
|---|---|---|
| 6th Street | 5 (Hella, Thrax, Columbus, Mackinaw, Colby Gran Butte) | Wicked Tires; Arroyo workshop (tentative, missable) |
| Tyger Claws | 5 (Turbo-R, Shion, Quartz, Muramasa, Columbus) | Japantown press workshop |
| Valentinos | 6 (Alvarado and cabrio, Thrax, Colby, Colby Gran Butte, Mackinaw) | Wellsprings body shop |
| Nomad / Aldecaldos | many (whole Nomad versions of 7 models, kits on more) | Dakota's (big, tentative); Badlands gas station (Aldecaldos mechanics); Big Pete's (small, tentative) |
| Police / NCPD | 14 | Landfill scrapyard (the most illegal) |
| Mox | 4 (Quartz, Supron, Alvarado Vato, Muramasa) | Hal's workshop (decided) |
| Neutral: stock, street, suburban, beater (25 models have beater looks) | all | Hal's workshop and Dakota's (decided: each carries everything else legal too) |
| Wraiths | 6 (Colby Little Mule and Vulture, Galena Gecko, Quartz Specter, Shion Samum, Type-66 Hoon) | Big Pete's place (decided; the NPC aimed at near it was a Wraith) |
| Racing | 9 | **none**; lead: the garage from Claire's racing jobs (sq024), next to the Arroyo workshop, not visited |
| Barghest (Phantom Liberty) | 9 | **none**; Dogtown wasn't scouted (its sectors carry no location names) |
| Maelstrom | 2 (Galena, Thrax) | **none**; Northside is theirs |
| Corporate and military (Arasaka 4, Militech 5, Kang Tao 3, NetWatch 4, MaxTac 3) | 5 to 14 | Landfill scrapyard (decided) |
| Scavengers | 4 | to be seen: maybe a tiny garage in a scav area |
| Animals, Voodoo Boys | 1 each | to scout: Pacifica, or Dogtown |
| Delamain | 2 | a small merch terminal by his entrance (decided) |
| Combat cab | 2 | Landfill scrapyard (decided) |

**Decided after the coverage review** (user, 2026-11-06):
- **Big Pete's place becomes the Wraiths shop** (illicit, Badlands raiders), not a second Nomad one.
- **Corporate and military parts** (Arasaka, Militech, Kang Tao, NetWatch, MaxTac) **join the landfill scrapyard's** illegal stock, and so does the **combat cab**.
- **Delamain:** his material is small: a body sticker kit and a door sticker kit (`kit_delamain_doors`), Delamain headrests and the Delamain paint, on the Cortes and Delamain no. 21. So a **small merch terminal next to his entrance**, as if Delamain sells merch. (The cab's bullet-hole and dented looks belong to the story, not the shop.)
- **Scavengers:** to be seen. If their parts are mostly stickers and other small items, a tiny garage somewhere in a scav area.

## Still to scout

Open, for later (user):
- **Racing:** the garage from Claire's racing jobs (`loc_sq024_mariannes_garage`), next to the Arroyo workshop.
- **Barghest:** Dogtown needs its own search; its sectors carry no location names, so it never made the list.
- **Maelstrom:** a place in Northside, their turf.
- **Animals and Voodoo Boys:** somewhere in Pacifica, or Dogtown if nothing else.
- **Scavengers:** a tiny garage in a scav area, if their parts turn out small.
- **The Arroyo workshop's after state:** unlock El Capitan's gig the same way.

## Shop staff

Mechanics to people the shops with, found from the user's captures at the Badlands gas station (2026-11-06) and in the files:
- **NPC records:** `Character.CitizenAldecaldosMaleMechanic` (all three gas station mechanics; display name "NC Resident"), `Character.California_Mechanic` (`base\quest\tertiary_characters\california_mechanic.ent`). Few records are named as mechanics; most mechanics are ordinary citizen or gang records in a mechanic's look.
- **Mechanic looks:** Aldecaldos (`citizen__aldecaldos_ma_mechanic_01` to `_05`, and the Nomad start's `q000__car_mechanic`); **6th Street**, men and women, from the Arroyo gig (`gang__6thstreet_ma__sts_std_arr_06_mechanic_01` to `_04`, `gang__6thstreet_wa__…_01` to `_03`); a generic mechanic (`base\characters\appearances\main_npc\mechanic.app`: `default` and `long_apron`), plus mechanic clothing pieces for men and women (`base\characters\main_npc\mechanic\`: jacket, pants, belts, shoes, arms).
- **Work animations (workspots):** at the gas station, `generic__kneel_ground__inspect__01`, `generic__kneel_ground_tool__fix__01` and `generic__stand_ground__look_at_products__01/03`, with `generic__stand_glass__clean__01` for the diner staff. Elsewhere in the world: `garage\stand_car_lean_front__work__01`, `common\car\male__lie_creeper__work__01` (on a creeper under a car), `common\ground\generic__lie_ground_car__repair__01`, `common\car\generic__stand_ground_lean_front_car_engine__idle__01`, `common\ground\generic__kneel_ground_lean_front_screwdriver__repair__01` and `construction_site\generic__kneel_welder__use__01`.

## Visits

Verdicts so far, newest first:
- **Hal Cantos's workshop** (Northside), after its gig: **the Mox shop, and it carries everything else legal too** (decided; the illegal stock stays at the landfill scrapyard). Its garage doors are dead after the gig and get removed.
- **Badlands gas station** (Panam's Hellman quests): tentatively a neutral shop, opening after "Life During Wartime"; a mechanic already works there.
- **Dakota's workshop** (Badlands): tentatively the big Nomad shop, cleaned up (lift bars removed for parking); **it also carries everything else legal, as Hal's does** (decided 2026-11-07: it has no unlock gate, so everything is on sale before Hal's gig). Big Pete's could be the smaller Nomad shop (user).
- **Stock** (user, revised): every shop carries its whole style, whatever its size; holding options back annoys players.
- **Workshop building** (Badlands, south-west): dropped; a gig's garage, not shop-like.
- **Lone garage** (Badlands, south): dropped; dead.
- **Lone garage** (Badlands, far east): dropped; the same dead door, not checked by command.
- **Lone garage** (Badlands, east): dropped; dead.
- **Lone garage** (Badlands, near Big Pete's): dropped; dead.
- **Lone garage** (Rancho Coronado): dropped; no garage door at all.
- **Row of garage sheds** (Rancho Coronado): dropped; dead, and its doors don't open.
- **The church garage** (Badlands, south-west): dropped; a one-bay Nomad prologue garage.
- **The Nomad start's garage** (Badlands, far south): dropped; likely unreachable after the prologue.
- **Wellsprings body shop** (Heywood): yes, the Valentinos shop, after its gig "The Lord Giveth and Taketh Away", with cleanup.
- **Unknown lift** (-1578.1, 635.7): dropped; a parking lot.
- **Unknown lift, City Center's west edge**: dropped; a company's site.
- **Raffen Shiv camp** (Badlands, east): dropped; a story location the Raffen Shiv still hold, too remote for a mechanic's.
- **Badlands lot** (south): not now; an empty garage room behind an NCPD job's spot, easy to fit out later.
- **Big Pete's place** (Badlands): **the Wraiths shop** (decided after the coverage review), after its gig, with the gig's leftover security area switched off.
- **Scrapyard in Arroyo**: dropped; not shop-like, and too busy a spot for illegal work.
- **Scrapyard by the landfill** (Badlands): yes, the shop for the most illegal parts (police gear, stolen cop cars cut up), in the garage by the entrance, barrier removed; open before and after its gig.
- **6th Street workshop at a Kang Tao site** (Arroyo): tentatively a second 6th Street shop, missable: Karl takes it over if he survives his gig, otherwise no shop.
- **Workshop with the mechanical press** (Japantown): yes, as the Tyger Claws shop, after its gig, with some cleanup.
- **Garage no. 66** (Rancho Coronado): tentatively dropped; maybe a hidden bike-only shop if nothing better turns up.
- **Wicked Tires Autoshop** (The Glen): yes, as the 6th Street shop, changed only after its gig.

### Badlands gas station (`badlands_gas_station`), 2026-11-06

**Pictures** (captures 19:12): a teal roadside gas station with pumps and a fenced yard, under tall lamps. Inside is a working garage: a mechanic crouched by a blue car over a pit, a crane gantry, racks, crates and lockers. "Pretty nice place" (user).
**The quest:** Panam's Hellman arc. In the files the place switches between a `default` state and the main quest's states `q104` and `q104_station`, plus `q104_gas_station_nomads_arrival` for the Aldecaldos arriving and `spawned_vehicles`. In the journal, `q104` covers **"Lightning Breaks"** (`q104_01_sabotage`) and **"Life During Wartime"** (`q104_02_av_chase`).
**Verdict (user, tentative): a neutral shop, opening after the Hellman quests**, so after "Life During Wartime" (its journal entry "Succeeded"). The mechanic already working there makes it feel lived-in. But its three mechanics are all Aldecaldos (`Character.CitizenAldecaldosMaleMechanic`, captures 19:15–19:16), and they work there in the `default` state, so after Panam's quests the Aldecaldos keep the garage. That leans Nomad rather than neutral.

### Dakota's workshop (`badlands_workshop`), 2026-11-06

**Pictures** (captures 19:08): a brick garage with a big "Dakota" sign over two bays, wrecks and tires out front, Dakota's people about. Inside is a large workshop: a two-post lift with a crossbar, a big yellow crane, a raised platform, tool walls, lockers and a screen with a map. The user's tracked gig at the time was Dakota's "MIA" ("Find Ben"). It's Dakota Smith's own place: she's the Badlands fixer, and her gigs are given here.
**Verdict (user, tentative): the big Nomad shop**, cleaned up, maybe even the "has everything" shop if no other big shop turns up. Remove the lift's posts and crossbar so players can park easily. It would take Big Pete's place as the main Nomad shop.
**To think about:** Dakota is a fixer working here, so the shop shares the place with her and her gigs. A garage is the business she already runs in the story, so it fits.
**Decided (user, 2026-11-07): it carries everything else legal too**, like Hal's workshop, because nothing gates it: Hal's opens only after its gig, so without this a player would wait for that gig to buy outside the owned shops' styles. **No unlock gate in the files:** no quest switch of the world's sectors touches the garage; the nearest are at two farms 300 to 600 m away (`after_storm_sand_damage` at the sq004 farmhouse, the sq021 farm's `var_cows`, `var_present_day`, `farm_meatman_2077` and `var_police_after`; `sector-variants.py`). It's open as soon as V can reach the Badlands. Not checked: whether any quest closes it for a while.

### Workshop building (`workshop_building`), 2026-11-06

**In the files:** the listed height (21.5 m) comes from the far-away stand-in, which put the user underground. The workshop's props stand on a floor at about 68.9 m, around (-2903.0, -4701.9). It's the site of a Badlands gig (`sts_bls_ina_09`).
**What the user saw:** a gig spot, but more a garage than a shop.
**Verdict (user): dropped.**

### Lone garage, Badlands south (`lone_garage_5`), 2026-11-06

**What the user saw:** also dead. Aimed at, its door reports the game class `FakeDoor` (capture 19:04), which confirms these garages are dummy fronts. **Verdict: dropped.**

### Lone garage, Badlands far east (`lone_garage_4`), 2026-11-06

**What the user saw:** the same door as the others, so probably dead too (not checked by command). **Verdict: dropped.**

### Lone garage, Badlands east (`lone_garage_3`), 2026-11-06

**What the user saw:** also dead. **Verdict: dropped.**

### Lone garage, Badlands near Big Pete's (`lone_garage_2`), 2026-11-06

**What the user saw:** also dead. **Verdict: dropped.**

### Lone garage, Rancho Coronado (`lone_garage`), 2026-11-06

**What the user saw:** as dead as the garage sheds; there isn't even a garage door.
**Verdict: dropped.**

### Row of garage sheds (`row_of_garage_sheds`), 2026-11-06

**What the user saw:** the place seems dead, and the garage wouldn't open even by command, so its doors are probably painted on rather than real doors.
**Verdict: dropped.**

### The church garage (`the_church_garage`), 2026-11-06

**The user asked:** is this place also locked behind a quest? (No pictures yet; the captures at 18:53–18:55 are from the Nomad start's garage.)
**In the files:** no gig. It's part of the Nomad prologue's hideout barn: the far-away stand-in is named `q000_church_garage`, and inside is an ambient area called `hideout_barn_church_room`, with car taillight lights as if a car were parked there. Its sector switches between `var_gate` and `var_collision`, most likely from the Nomad prologue, so in other saves it stays in its default state. It's reachable: a fast travel point stands about 130 m away (-3479.6, -4184.6).
**Pictures** (captures 18:59): a small white wooden church with a steeple and porch, and a one-bay garage beside it with its door **open** in the user's save. Inside are tool racks, tires, "No Regrets" graffiti, and the Nomad prologue's broken Galena (`Vehicle.cs_savable_thorton_galena_nomad_broken`). So nothing blocks it here. The second capture caught the Windows window switcher in front of the game.
**Verdict (user): dropped.**

### The Nomad start's garage (`the_nomad_starts_garage`), 2026-11-06

**What the user saw** (pictures in `dev/captures/`): "nice little garage", neutral with a small stock, but likely unreachable after the prologue. Some players might get there with mods that lift the map's barriers.
**In the files:** no fast travel point is near it; the nearest is 1.6 km away (-2811, -5434), and the southernmost in the whole game is at y -5585, about 900 m north of the garage (y -6484). So it's very likely past where the open world lets V go after the Nomad prologue.
**Verdict (user): dropped.** A shop only players with barrier mods can reach isn't worth building. A small neutral shop belongs somewhere reachable.

### Wellsprings body shop (`wellsprings_body_shop`), 2026-11-06

**Pictures** (captures 18:43): a walled yard behind a barred gate on the street, then a yard of closed roll-up garages with wrecks, drums and crates. On the walls are an "El Padre Sabe" mural and a big rose: Padre's and the Valentinos' turf.
**The gig** is Padre's **"The Lord Giveth and Taketh Away"** (`sts_hey_spr_03`, journal title `LocKey#12701`), search and recover: "Retrieve the Militech car purchased by the nomads", at a "Garage on Russell St.". Some Nomads bought a stolen Militech SUV from the Valentinos on Padre's turf without asking him. The gig's own files call the garage the auto body shop; the Nexus garage mod for this place names the same gig.
**In the user's save:** the gig **isn't in the journal**, so it hasn't been done or offered here, though the user remembers doing it, probably in another playthrough. It could be unlocked the same way as Sparring Partner, through Heywood's gig manager.
**Unlocking its gig** (Heywood gig manager, `0x8aebb0e063b98003`): the gig is revealed in the tier 2 phase. That runs once `hey_sts_counter` (Heywood gigs finished) reaches **7**, after two 10-second waits and Padre's message `new_sts_002`. The phase waits for `padre_visited`, marks the gig on the map while `spr_03_finished` is unset, and the gig starts at its trigger (`#spr_03_tr_content_init`). The user asked to unlock it (2026-11-06).
**Inside** (captures 18:45, doors forced open by command; the user reloads to put them back): "it looks great". A big, well-kitted body shop: a two-post lift with yellow arms, a tire changer and wheel balancer, tire racks, workbenches and tool chests, a grated pit, shelves, a rose mural in the Valentinos' style, the "Get there alive" sign, and a second hall through the back.
**After the gig** (unlocked with `padre_visited` and `hey_sts_counter` 7, then a save and reload; the user finished it; pictures in `dev/captures/`): "the shop is basically fully open". It needs cleanup.
**Other jobs here:** none places anything at the shop. An NCPD job's state, `ma_hey_spr_02_loot_hide`, hides some loot in this sector. The other states nearby (a bomb, a cyberpsycho, a DJ booth) come from larger sectors that cover the area.
**Verdict (user): yes, a Valentinos shop, opened after the gig**, with cleanup (assuming no other gig uses the place). The catalog's Valentinos material: heaviest on the Chevalier Thrax and Villefort Alvarado (with the cabrio and hearse), then the Thorton Colby (and the Phantom Liberty version), Colby pickup and Mackinaw.

### Unknown lift (`unknown_lift`), 2026-11-06

**What the user saw:** a parking lot, not a shop.
**Verdict (user): dropped.**

### Unknown lift, City Center's west edge (`unknown_lift_city_centers_west_edge`), 2026-11-06

**What the user saw** (pictures in `dev/captures/`): a company's site.
**Verdict (user): dropped.**

### Raffen Shiv camp (`raffen_shiv_camp`), 2026-11-06

**What the user saw** (pictures in `dev/captures/`): there's a garage, but a major story beat plays here. The Raffen Shiv probably come back afterwards: in this save that mission should be done, yet enemies still spawned. Even if they didn't, it wouldn't become a mechanic's out in the middle of nowhere.
**Verdict (user): dropped.**

### Badlands lot (`badlands_lot`), 2026-11-06

**What the user saw** (pictures in `dev/captures/`): an NCPD job's spot. Opening the garage door by command shows an empty room.
**Verdict (user): not now.** It could be an easy place for one more shop later, but designing one isn't worth it for now.

### Big Pete's place (`big_petes_place`), 2026-11-06

**Pictures** (captures 18:23 with the gig "Active", 18:24 just after it, 18:26 after a reload, both "Succeeded"): a roadside Badlands garage under power lines and cacti, with a canopy, wrecks out front and closed roll-up doors; one bay stands open. Inside is a raised platform with a two-post car lift, racks, tires and an "EXIT" sign, plus bodies from the gig's fight.
**After the gig:** as far as the user could tell, nothing changed. The files agree: the place's only state switch is `goons_shooting_car`, during the gig, and there's no after-the-gig switch. The gig is complete (journal "Succeeded") and needs nothing more. The minimap still showed **"Area: Hostile"** after the reload: it's the gig's security area staying behind (user), with a fairly small radius. The shop switches it off.
**Verdict (user):** first a tentative Nomad shop on the illicit side; after the coverage review, **the Wraiths shop**, opened after the gig. The catalog's Nomad material: whole Nomad vehicles (Archer Quartz, Mizutani Shion and its courier version, Quadra Type-66, Thorton Colby, Galena and Mackinaw), plus Nomad parts and kits on the Mahir Supron, Villefort Columbus and Cortes, and others.

### Scrapyard in Arroyo (`scrapyard_in_arroyo`), 2026-11-06

**What the user saw** (pictures in `dev/captures/`): doesn't look like a shop of any kind, and it's too much in the middle of the hustle and bustle for illegal work.
**Verdict (user): dropped.**

### Scrapyard by the landfill (`scrapyard_by_the_landfill`), 2026-11-06

**What the user saw:** "perfect for the most illegal stuff": the kind of place where stolen cop cars get cut up and hidden forever. The barrier to the scrapyard side is down by default. Raising it with a quickhack left its lights hanging on the bar, so better to remove the bar entirely. Before turning left into the scrapyard, a garage on the right is perfect for this kind of place: closed by default (the user opened it with a command). "You come in, get your illegal parts installed, delta."
**Pictures** (captures 17:59–18:01): a fenced road into the scrapyard between hills of junk and stacked wrecks; a barred gate and a barrier with a red light bar; trailers and portacabins; the garage is a white building with a roll-up door; a **junk vendor** in a green booth ("Selling anything interesting?"). The gig (`sts_bls_ina_11`, find a robot in the landfill, with a technician) **isn't in the user's journal**.
**In the files:** the garage's roll-up door is an ordinary gate device (`gate_1`, 1369.6, -1679.6, 49.3), beside a side door (1369.8, -1684.2). The barrier is a separate roadblock object (`road_barrier_poor_small`, 1385.0, -1689.2, 49.2), so it can be removed outright. Both sit in a sector the game switches during the gig (`during_sts`, `interior_tr_on`), so the garage may only open while the gig runs. Whether that gig is what opens it isn't known yet; it isn't offered in this save.
**Verdict (user): yes, the shop for the most illegal parts** (police parts and the like), in the garage, with the barrier removed.
**Its gig is "Sparring Partner"** (Dakota's; journal title `LocKey#12523`): thievery, "Retrieve data from broken training bot", at the Warbler Lake Hazardous Waste Facility, Anderson St.; the brief starts with a kid "folks call … Red Joe".
**Unlocking its gig** (Badlands gig manager, `0x9d4761f73def416f`): every phase waits for `dakota_visited`. The scrapyard gig is marked on the map in the tier 3 and tier 3_1 phases while `ina_11_finished` is unset. Tier 3_1 opens once `bls_sts_counter` (Badlands gigs finished) reaches **5**, after two 10-second delays. The user asked to have it activated (2026-11-06): set `dakota_visited` 1 and the counter to at least 5.
**Worked** (user, 2026-11-06): the gig appeared after a save and reload, and the user completed it. During the gig the garage door could be used and opened. After it, with another save and reload, the place is more or less as before, door shut. So the shop has to open the door (and other doors) itself after the gig, along with the cleanup and removing the barrier; nothing in the game does it.
**Decided (user): this shop is open before its gig too**; there's no story reason to wait. The gig opens the same door itself, so opening it earlier shouldn't clash. Whether to keep the stand out of the way while the gig runs (its journal state "Active") is to be seen once it's built.

### 6th Street workshop at a Kang Tao site (`6th_street_workshop_at_a_kang_tao_site`), 2026-11-06

**What the user saw:** "nice place". The garage door was locked with no way to interact, so the user forced it open with a command; it looks like a gig spot.
**Pictures** (captures 17:52–17:53, `dev/captures/20261106-1752*` and `-1753*`): a green-and-orange building at a corner under the Arroyo pipelines, with a fenced yard and closed roll-up doors. Inside is a big workshop and warehouse: racks of crates and drums, tires, a mezzanine with stairs, hanging cables, plastic curtains (maybe a paint booth) and a 6th Street banner. The last capture caught the Windows window switcher in front of the game. The gig (`sts_std_arr_06`) **isn't in the user's journal**, so this is the before state.
**The gig** (El Capitan's): a Kang Tao hotshot, Karl Ginsky, "went and got wasted in Arroyo" and lost company data. V finds it in this warehouse (objectives: enter the factory, find the shard, talk to Jeremy, follow Karl), and Kang Tao security turns up and "neutralizes" Karl unless V fights. Two 6th Street mechanics work here, and the car lift is the gig's "advanced auto crane with a suspended body".
**After the gig:** not seen; it would need El Capitan to offer the gig, as with Hal's. To check what unlocks it, alongside Hal's shortcut.
**Verdict (user, tentative): a second 6th Street shop, possibly missable.** Depending on how much the gig changes the place: if Karl survives, he takes it over; if he dies, there's no shop. With Wicked Tires as the other 6th Street shop, losing this one is fine. The gig's own facts can drive it: `arr_06_karl_killed` (Karl dead), `arr_06_finished` and `arr_06_complete`, plus `arr_06_combat_kang_tao`, `arr_06_v_took_money` and `arr_06_abandoned`.

### Workshop with the mechanical press, the Tyger Claws' (`workshop_with_the_mechanical_press`), 2026-11-06

**What the user saw:** a Tyger Claws place.
**Before the gig** (captures 17:40–17:41, `dev/captures/20261106-1740*`, gig "Active"): a yard behind a barred sliding gate under the elevated highway and its pipes, with Tyger Claws graffiti on the walls. Inside are a red sports car, a Tyger Claws Villefort Columbus van (`Vehicle.hackable_villefort_columbus_tyger`), pipe racks, crates and a fuel tank, and a warehouse with an open roll-up door: racks, a press gantry, an arcade machine, floor drains. Marked "Area: Hostile".
**The gig** (`sts_wbr_jpn_02`, from Wakako): rescue Lauren Costigan, held hostage by the Tyger Claws to pressure her husband Bradley; she's somewhere below, by the "Get to the basement" objective. Tyger Claws on guard talk about family and the Militech prison transfer. Wakako closes it with "Lauren is secure … Contract closed."
**After the gig** (captures 17:47, gig "Succeeded"): no more "Area: Hostile"; the warehouse is a long, tidy hall of racks, crates and floor drains with the roll-up door at the yard. The user: "the area feels cleaner now".
**Verdict (user): yes, a Tyger Claws shop**, with some cleanup. The catalog's Tyger Claws material: the Quadra Turbo-R and Mizutani Shion (both heavy with it, the Shion's Nomad version too), Archer Quartz, Arch Nemesis, Thorton Galena, the Villefort Columbus van (`tygerclaws_01`) and the Yaiba Kusanagi bike.

### Hal Cantos's workshop, the Moxes' (`hal_cantoss_workshop`), 2026-11-06

**What the user saw:** "looks awesome and could serve as our big neutral shop". But it's shut tight (the user got in with "5 m ahead") and marked **"Area: Hostile"**.
**Pictures** (captures 17:22–17:23, `dev/captures/20261106-1722*`): outside, a fenced yard under a gantry with three or more closed roll-up doors and a big yellow sign. Inside is a large workshop: several bays with grated pits, a two-post lift with ramps, a mezzanine with stairs, a container, a Mox mural, blood on the floor, steam. The gig (`sts_wat_nid_01`) **isn't in the user's journal at all**, so it hasn't been offered yet and this is the before state.
**The gig** (Regina's; probably "Occupational Hazard", title unverified): it's the Moxes' place. Hal Cantos, a braindance tech, was "at the Mox's" cracking a braindance for them; a Mox, Annie, dove into it and went cyberpsycho; Lena is dead, Lizzie wounded upstairs. V stops Annie, by fighting her or hacking her through the Moxes' local net, and gets Hal out of hiding. Regina closes the gig, or tells V that Hal died if V left.
**In the files:** the main freight gate is the gig's own door (`sts_wat_nid_01_gate`, -1225.7, 2278.3, 7.0, beside an envprobe named "main_closed_gate"). "Area: Hostile" comes from the gig's security area and security system (-1219.6, 2274.1) and two cameras. The place's sectors switch between `lockdown`, `dead_moxies_var` (bodies after the gig), `var_blood` and `loot`.
**Can it be opened?** Very likely, after the gig: the gate and the hostile area are devices, so a script can unlock and open the one and switch off the other. What isn't known is whether the `lockdown` state also adds shutters as world objects, or whether the game opens the place itself after the gig; the after state will tell.
**What the gig changes, from its files** (2026-11-06 evening; `sts_wat_nid_01_openworld.questphase` read with `questgraph.py`, the sectors' switches with `sector-variants.py`):
- **Before:** two switches start on. `dead_moxies_var` is four dead Moxes (`ma_corpse`, `wa_corpse`) and blood decals inside the workshop, so the blood the user saw belongs to it. `lockdown`, in the nearby sector, is a single invisible collision wall about 5 m above the floor (-1213.3, 2276.0, 11.9), probably closing the window V could climb in through (the gig watches three ways in: a door, a window and the gate); a far-away sector holds one more `lockdown` piece the scripts can't read. The doors are dead, and the security area makes it "Area: Hostile".
- **When V walks into the gig's start area:** the gig powers the doors `sts_wat_nid_01_door_01` and `sts_wat_nid_door_02`, turns `lockdown` off, keeps passers-by out (a crowd-free area) and points V to Hal. When Annie dies, the security area is forced to switch, most likely off.
- **After the gig:** once V is outside the gig's cleanup area and 3 game hours have passed, the game takes the doors' power away again, turns `lockdown` back on, removes the dead Moxes and their blood, runs spawn actions on the gig's people (most likely removing them), switches the security area again and lets the crowd back. A bugfix phase removes the dead Moxes too. **So the after state should be the before state, shut tight, but clean and no longer hostile.** Nothing in the files opens it later, and no other quest uses Hal (his `hal_cantos_default` scene is only his own small talk).
- **For the shop:** as at the landfill scrapyard, the shop opens the place itself: power and open the doors (ordinary door devices) and remove the `lockdown` wall. That wall is a cooked collision node, so ArchiveXL can delete it, but the deletion also applies before the gig. The cleanup a shop would need (bodies, blood) the game does itself.
- Not this gig's: a katana, a loot token and blood marks about 25 m east (-1195, 2248) belong to another world story (`wnid_04`, switches `var_katana` and `var_blood`).
**How the gig starts** (Watson's gig manager quest phase, read with `experiments/areas/game-files/questgraph.py`): every Watson gig phase waits for the fact `reggie_visited`. Hal's gig sits in the Northside **tier 3** phase (`sts_wat_nid_tier_3`); while `nid_01_finished` is unset, it marks the gig's point of interest discovered on the map, and the gig itself starts at its trigger area at the workshop (`#sts_wat_nid_01_tr_start`). Higher tiers also check the Street Cred tier `StreetCredTier.WatsonTier4`. The gig's own facts include `nid_01_start`, `nid_01_hal_met`, `nid_01_hal_rescued`, `nid_01_finished` and `nid_01_player_left_psycho_alive/dead`.
**In the user's save** (console, 2026-11-06): `reggie_visited` 0 even after seeing Regina; `sts_wat_nid_tier_1` 1, `tier_2` 0, `tier_3` 0, `tier_4` 1; `nid_01_start` and `nid_01_finished` 0; cyberpsychos `ow_psychos_done` 3, `ow_psychos_killed` 2, reward not collected. Regina's conversation sets `reggie_visited` on its first-meeting and cyberpsycho-reward branches; neither ran here.
**What reveals Hal's gig:** the manager phase for tier 3_2. It runs once `wat_sts_counter` (Watson gigs finished) reaches **19**, then sets `sts_wat_*_tier_3_2`, waits for `reggie_visited`, marks Hal's gig on the map, and waits at its start trigger. Setting `sts_wat_nid_tier_3` by hand does nothing, because the phases follow the quest's flow, not the fact. A shortcut, on the user's word: set `reggie_visited` 1 and `wat_sts_counter` 19. That also reveals every Watson gig up to that tier. **Planned (user):** do it once the other garages are checked; the scouting save is a throwaway test save, so breaking things later doesn't matter.
**The Northside phase** (`sts_wat_northside_industrial_district.questphase`, read 2026-11-06 evening) waits on any of the facts `sts_wat_nid_tier_3`, `_3_1` or `_3_2`, then marks Hal's gig on the map once V is outside its start area (`#sts_wat_nid_01_tr_start`), and starts the gig when V walks into that area on foot. So if the shortcut above doesn't bring the gig up after a save and reload, setting `sts_wat_nid_tier_3_2` 1 is the next thing to try, as long as the Northside phase is running at all (it seems to need `reggie_visited` first).
**Unlocked** (user's go-ahead, 2026-11-06 19:48, through the command file): before, `reggie_visited` 0, `wat_sts_counter` 3, Northside tiers 1 and 4 set, 2 and 3 not; set `reggie_visited` 1 and `wat_sts_counter` 19. Within 30 seconds, without a reload, the manager set `sts_wat_nid_tier_3_1` and `_3_2` (`tier_3` stayed 0), and the gig came up.
**The gig, played** (user, 2026-11-06 about 19:50): finished. Facts afterwards: `nid_01_finished` 1, `nid_01_hal_rescued` 1, `nid_01_psycho_dead` 1 with `nid_01_weak` 0 (Annie killed in the fight, not hacked), `nid_01_lie` 0. No captures were taken.
**After the gig** (user, right after it, V by the workshop at -1234.8, 2292.3): the garage doors don't open and can't be interacted with. That fits the files: at the end the gig takes both doors' power away. The game's reset 3 game hours later (the `lockdown` wall back, bodies and blood gone, the hostile area off) hasn't been seen yet.
**Hal is still there** (user, about 20:00): he stands at the workshop after the gig. The reset takes him away too: it switches off the gig's three spawners, Hal's (`#nid_01_com`), Annie's (`#nid_01_com_psycho`) and the dead's (`#nid_01_com_dead`). The capture of 19:53 (`dev/captures/20261106-195305.json`) has data only, no picture, because the capture watcher stopped when the game closed at 19:45 and wasn't started again: V north of the workshop (-1234.1, 2302.1) facing south, aimed at metal 2 m up on the front (-1231.3, 2281.8, 9.2), probably a door; the capture doesn't record people.
**The workshop's own crowd:** Northside's open-world phase (`base\open_world\community\watson\northside\phases\wat_nid_phase.questphase`) switches on a spawner called `#wat_nid_lizzies_workshop_com`, the people working there before the gig (the place list counted 2 spots). The gig switches it off when it starts, and nothing in the files switches it back on, so after the gig the place stays empty and the shop brings its own staff. "Lizzie's" most likely means the Moxes (the game's files call their gang voices `gang_liz_*`, after Lizzie's Bar), so the files themselves call it the Moxes' workshop. Who is in that crowd isn't read yet: it's defined in the world's always-loaded sectors, and reading those with `pkg.py` took 45 GB of memory before it was stopped.
**The doors in the files** (`whereis.py`, within 35 m): the big freight gate is an entity of its own (`sts_wat_nid_01_gate.ent`, debug name `door_freight`, at -1225.7, 2278.3, 7.0), beside reflection probes named `main_closed_gate` and `main_open_gate`, so it can be removed at runtime like the objects at Wicked Tires. The other doors are ordinary single, sliding and double doors (`single_door.ent`, `single_door_techie.ent`, `double_door.ent`) and a window shutter (`shutter_window_w150.ent`). A roll-up door that isn't among these is cooked into the scenery; aiming the capture key at each door will tell which is which.
**Verdict (user): yes, the Mox shop, and it carries everything else too.** It leans into the Moxes' style like the other owned shops, and it's also the "has everything" shop. The garage doors get removed rather than opened (user: "we'll need to remove them manually"). The catalog's Mox material: the Archer Quartz, Mahir Supron, Villefort Alvarado (with the cabrio and hearse) and Yaiba Kusanagi.
**Decided (user): "everything" means legal only.** The illegal stock (police, corporate and military parts, the combat cab) stays at the landfill scrapyard.
**Lore fit:** it isn't neutral, it's the Moxes'. Either the Moxes leave it after the tragedy and a neutral mechanic moves in, or it becomes a Mox shop. The catalog has Mox looks on the Archer Quartz, Mahir Supron, Villefort Alvarado (with cabrio and hearse) and Yaiba Kusanagi.

### Garage no. 66 (`garage_no_66`), 2026-11-06

**Briefing from the files:** its gig "Error 404" (`sts_std_rcr_04`) is active in the user's save, so this visit sees the before state. The fixer's call: a site on the Net is smearing acting mayor Weldon Holt, and the client wants it gone. Its server sits in Garage no. 66 in Rancho Coronado; V enters the garage area and destroys the server or sends a virus through it. In the garage, two gearheads restore an out-of-production car ("Drive shaft's fucked, but the bearings'll be new, sandblasted. Still waitin' on a new compressor"; "You can't just buy tech like this"), and one of them "sold out to Militech". A scavenger van spawns with the gig. So it reads as a private lock-up of car hobbyists with a political server on the side, not a gang's place; whether the scavs belong to it is unclear.
**Before the gig** (capture 17:17, from a ledge above, gig "Active"): a walled yard of lock-ups marked **"Area: Hostile"**, with a **6th Street** van parked in it and a hostile guard. The car lift (a two-post lift with a platform) stands out in the open yard, not in a garage. Objective at the time: "Find the garage with the servers." So the yard is 6th Street-held, at least while the gig runs. The files show no after-the-gig switch for this place's sectors (unlike Wicked Tires), so what changes afterwards is likely only what the gig itself spawns or breaks.
**After the gig** (capture 17:20, gig "Succeeded"): the same yard, still **"Area: Hostile"**, the 6th Street van still parked; no guard in view. So it stays 6th Street turf after the gig.
**Verdict (user): tentatively dropped.** It could be a hidden bike-only shop, but a better place for that will probably turn up.

### Wicked Tires Autoshop, 6th Street's garage (`jake_estevezs_garage`), 2026-11-06

**Pictures** (capture key, 17:09, `dev/captures/20261106-1709*.jpg`; the gig is done in the user's save, journal "Succeeded", so this is the after state):
- The neon sign says **Wicked Tires Autoshop**, beside a big 6th Street snake-skull mural ("6th Str") and "High Octane" signs: a 6th Street front with a fenced yard and room out front, under the highway.
- **Bay 2** (right, open): an inspection pit with a hinged grate cover (`hatch_horizontal_grate_hinged`, -1431.5, -1283.6), stacks of tires, a "Get there alive, or your money back" sign.
- **Bay 1** (left, shutter half up): the wrecked car (`v_deco_vehicles_destroyed_01`) sits over its pit. Its door is blocked by a forklift (`forklift`, -1444.3, -1305.0) and a rusted wreck that is really a body-disposal container (`disposal_broken_car`, -1449.2, -1306.3), next to the gig's crate-stack trap (`gle_06_dvc_crates`, -1442.6, -1299.7). All of these are separate objects, not walls.
- The car lift's post stands in the middle of the hall between the bays.
- The user's tracked gig at the time, "Error 404" ("Enter the garage area", 1.7 km off), is Garage no. 66's (`sts_std_rcr_04`), active in this save.

**What the user saw:** "pretty neat place". Plenty of space out front, a direct entrance to one service bay, the second bay's entrance blocked, a wrecked car in one bay. Both bays have gaps in the floor a small car could drop into: cover them, maybe with the game's hinged covers. The car lift, the reason it made the list, stands where nobody could use it: maybe remove it.

**What the files say:** it isn't Jake's garage, it's 6th Street's. The gig (`sts_hey_gle_06`, Heywood, The Glen; probably Padre's "Life's Work", title unverified): Jake Estevez tuned cars for 6th Street and built them one they can't use. Two of their men talk it over: "Serial's scrubbed off, soft's packed with ICE", "The soft, the calibrations, even the go-betweens for the tech were his!". V gets into the garage, uploads software at the computer upstairs, takes the car to Jake, and Jake leaves town for a collector in Sacramento. Afterwards one of the 6th Street men says "Nature doesn't leave empty spaces. Someone'll turn up." So it looks legit but was a gang's tuning shop.
In the garage's sector: the lift is the gig's own trap device (`gle_06_dvc_lift_car`, -1439.1, -1293.8, 46.8). The wreck is a decoration entity (`v_deco_vehicles_destroyed_01`, -1445.7, -1288.7, 46.8). There's a hinged floor grate (`hatch_horizontal_grate_hinged`, -1431.5, -1283.6) and a gate (`gate_1`, -1432.2, -1299.4), which may be the blocked entrance. The computer is upstairs (-1420.2, -1284.7, 51.8). The garage has an office, a staircase, a side area and a toilet, and the gig's tank sits by a car. All of it is in a sector the game switches after the gig (`post_sts_variant`, plus `bodies` and `loot`). Which of these objects the switch changes isn't known yet.

**Decided (user):** a 6th Street shop ("yes!"), leaning hard into their style. No illegal parts like police gear; other places will carry those. Change the place only in its after-the-gig state.
What the catalog has for it: 6th Street styles, paints (`6th_street_*`) and door stickers on the Archer Hella, Chevalier Thrax and Villefort Columbus van; a 6th Street look of the Thorton Mackinaw; and on the Thorton Colby pickup, a style `jake_estevez_01` and a kit `body_stickers_6th_street_estevez`, most likely Jake's own car from the gig.
**Open:** what the game's after-gig switch changes (the pictures show the after state only). The changes the user floated all touch separate objects (the wreck, the forklift, the disposal wreck, the crate trap, the lift, a second grate cover for bay 1's pit), so they can be made after the gig only.

## Going there by hand

In the Cyber Engine Tweaks console (coordinates from the tables; z is the floor plus a metre):

```lua
Game.GetTeleportationFacility():Teleport(Game.GetPlayer(), ToVector4{x=-1439.1, y=-1293.8, z=48, w=1}, ToEulerAngles{roll=0, pitch=0, yaw=0})
```

## Garages with a car lift

The game's car-lift trap (a car hanging on a lift that can be dropped on enemies) stands in a garage interior every time, so these are the surest.

| Place | District | Lift at (x, y, z) | What's there | How the game uses it | People | Feel |
|---|---|---|---|---|---|---|
| Jake Estevez's garage | Heywood, The Glen | -1439.1, -1293.8, 46.8 | 14 tires, about 30 tools | Gig: you bring a car back to Jake Estevez, go into the garage and upload software at a computer there; the files have an "after the gig" state for the place | 1 | Honest mechanic: **legit** |
| Garage no. 66 | Santo Domingo, Rancho Coronado | 254.8, -1089.1, 21.4 | 5 tires, about 30 tools | Gig "Error 404" (active in the user's save on 2026-11-06): find Garage no. 66 and destroy a server in it; a scavenger van | 0 | Scavengers' lock-up: **shady** |
| Hal Cantos's workshop | Watson, Northside industrial district | -1219.1, 2263.2, 7.0 | about 40 tools | Gig: a cyberpsycho in the workshop (the map pin says "Warehouse"); Moxes involved | 2 | Industrial workshop: **legit-ish** |
| Workshop with the mechanical press | Westbrook, Japantown (the files' folder says "monoblade workshop") | -243.1, 1619.6, 41.2 | about 45 tools | Gig: get inside, find Lauren Costigan in the basement; a keycard and an elevator | 0 | Unclear; at 41 m it may be upstairs |
| 6th Street workshop at a Kang Tao site | Santo Domingo, Arroyo | -635.5, -1155.1, 7.8 | about 20 tools | Gig from El Capitan: Kang Tao, two 6th Street mechanics; the lift scans as "Advanced auto crane with a suspended body". Next door is the garage from Claire's racing jobs (the files call it Marianne's garage) | 4 | Gang mechanics: **shady** |
| Scrapyard by the landfill | Badlands, by the landfill where V wakes up after the heist | 1369.5, -1690.5, 49.3 (two more within 40 m) | 3 lifts, 277 pieces of wrecks, 12 tires | Gig: find a robot, with a technician | 0 | Scrapyard: **very shady** |
| Scrapyard in Arroyo | Santo Domingo, Arroyo (near Megabuilding H7) | -28.7, -1036.8, 7.5 (another 5 m away) | 2 lifts, 48 tires, 167 pieces of wrecks | An NCPD job | 4 | Scrapyard: **shady** |
| Big Pete's place | Badlands | -148.2, -4416.0, 58.8 | a few tires and tools | Gig: find and kill Big Pete; his goons shoot at a car | 23 (probably his goons) | **Very shady** |
| Badlands lot | Badlands, south | -1285.5, -4237.4, 62.7 | 5 tires, 10 pieces of wrecks | An NCPD job | 1 | Remote, **shady** |
| Raffen Shiv camp | Badlands, east | 2987.3, -2405.0, 118.5 | a car jack and a forklift, tires, tools | A side quest at the Raffen Shiv camp (`sq004`) | 3 to 9 | Bandit camp: **very shady**, but a quest place |
| Unknown | City Center, west edge | -2312.8, 471.5, 7.3 | 9 tires, about 10 tools | No job of its own found; a minor quest's meeting (`mq304`) is set up nearby | 0 | ? |
| Unknown | no named place within 150 m | -1578.1, 635.7, 9.3 | 3 tires, a few tools | None found | 6 | ? |

## Garages without a lift, worth a look

| Place | District | At (x, y, z) | What's there | How the game uses it | People | Feel |
|---|---|---|---|---|---|---|
| Wellsprings body shop | Heywood, Wellsprings, by the water | -2461.5, -912.2, 9.2 | 2 big shutters, 9 tires, about 40 tools; the files have a "car in the garage" state | Gig with the Valentinos (Pablo Delgado) and a Nomad truck: you drive the truck out of the garage. The gig's files call the place the auto body shop. A Nexus mod turns this garage into a home and says its gates don't open in the base game | 3 | Body shop: **legit**-looking, Valentinos turf |
| The Nomad start's garage | Badlands, far south (probably Yucca) | -3963.0, -6483.7, 75.8 | the Nomad prologue's garage, tires, tools; the files have a garage gate device | The Nomad start | 2 to 4 | Small-town mechanic: **legit** |
| The church garage | Badlands, south-west, by the Nomad hideout barn | -3463.0, -4056.3, 75.0 | 10 tires, tools | The Nomad start | 0 | Nomad: **shady**-ish |
| A row of garage sheds | Santo Domingo, Rancho Coronado | 330 to 412, -2076 to -1953, about -2 | ten Badlands-style garage buildings, tires, pieces of wrecks | None found | 0 to 10 | Unknown inside |
| Lone garage buildings | Badlands: -99.1, -4220.4 / 3201.6, 670.7 / 4253.8, -428.7 / -1127.0, -5599.7; Rancho Coronado: 509.4, -1820.5; a workshop at -2870.9, -4691.2 | | the same Badlands garage building | None found | 0 to 2 | Remote |

## Busy places, not dormant

Mechanics at work in the Kabuki market (-1033.9, 1357.0), Delamain's garage (-945.5, -114.2), the Badlands workshop of an NCPD job with 44 people around (2416.8, -782.3), a Badlands gas station from a main quest (`q104`) with 36 (-1859.5, -4278.4).

## Leads from the web, not found in the files

- **El Capitan's drop-off garages:** the doors open when you arrive with a stolen car. A Nexus mod turned one in Northside, near the Longshore North fast travel point, into "V's Northside Autoshop". The files don't name them; his jobs set them up.
- **New American Autoworks** (Jackson Plains, Badlands) and **Sunset Auto** (near the Sunset Motel, probably): drive-in garages in the GarageCore mod.
- **NC Autoshop's Repair** puts a mechanic into 12 existing workshops, and says some open only after a gig ("Life's Work" in The Glen, "Occupational Hazard" in Northside). That fits Jake's garage and Hal's workshop above.

## How this was found

`experiments/areas/game-files/sectors.py` reads the game's list of all 24,161 world sectors and what each one uses. `garages.py` then reads where each car lift, tire, tool, wreck part, big shutter and mechanic stands, groups them into places, and notes the named places, jobs and people around them. Named places come from the files' own folder names (`sectors\c_heywood\glen\loc_sts_hey_gle_06`), and gig details from the game's English text. The full lists are in `experiments/areas/game-files/data/garages.json` and `results/garages-<date>.txt`.
