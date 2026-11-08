# Experience

What playing with the vehicle customizer should feel like, written as moments a player lives through, so the design and the next tests follow from them.
[RECORD.md](RECORD.md) has the evidence behind each status.

**The bar:** go above and beyond, so it feels like the garage of a great car customization game, not like a mod menu (user).
The UI is native to the game, with no Cyber Engine Tweaks window. Where frameworks stop, we go into the game files and write native code (user).

Status of each moment: **proven** (seen in the game), **likely** (the game has the pieces, untried), **unknown** (needs a test or research), **out** (not possible, or not wanted).

**Until the shop exists** (2026-11-06, for the crew's co-op test): F7 opens a panel down the right of the screen in the game's own popup style, beside the car, with every choice the engine has, tried on the car at once, undo, buying any model in any style, and buttons that step V round the car. No stand, pictures, prices or robot arms; it's dropped once the shop is built (user). RECORD.md has the details.

## 1. A real shop in Night City

You drive into a mechanic's shop that has stood dormant until now, or one big shop to begin with (user).
Your car rolls into a bay with Delamain-style robot arms around it, and next to it stands a computer that fits a mechanic's shop, showing the shop's own page.
Every option on that page has a picture, so you can choose without leaving the screen and skip what you don't care about at a glance (user).

- **Likely:** the screen. The stand's computer shows only the shop, never the generic in-game browser (user). The game already has many devices with a screen of their own, each a subclass of `DeviceInkGameControllerBase` with its own layout: vending machines, the jukebox, drop-point terminals, elevators, and the arcade machines that run whole minigames. Ours would be one more, designed as well as we can. The Yaiba showroom is only a page of the browser (`base\gameplay\gui\quests\mq060\yaiba_showroom_website.inkwidget`), so nothing ties the stand to its high-end showroom look (user).
- **Unknown:** the option pictures: rendered from the game's meshes before release, or photographed in the game. A picture of each part option takes the customizing "from 3/10 to maybe 7/10 immediately" (user, 2026-11-07), so they matter. A live render is first choice; failing that, a tool of our own that frames each part, captures it and ships the pictures with the mod (user). Leads: the game renders items live in its menus (`inkItemPreviewGameController`, the inventory's and wardrobe's previews), but only on full-screen menus, so on the tool's screen it's unlikely and on the shop's computer it's to be seen; photographing in the game is what the test runs already do (they frame the car and save pictures), so a capture job that applies each option and photographs it is the likely way, at a size still to count. The car itself shows each option for real as you move through them (a rebuild takes about a second).
  **Direction (user, 2026-11-07, after probe 5): pictures rendered outside the game**, by a tool of our own working from the catalog, as "product photos": free choice of camera, lighting and background, and parts cut out of meshes that combine several. Likely route: WolvenKit's command line exports each mesh with its materials (`uncook --mesh-export-type WithMaterials`), Blender (5.1 is installed) with the community Cyberpunk add-on (the WolvenKit Blender IO Suite, 1.8.0 for Blender 5.0; not installed) rebuilds the game's materials, and a script renders every option headless with a transparent background; the pictures go into the mod as atlases. About 2,100 pictures: 1,941 options in 100 catalogs (1,048 distinct meshes) and 177 wheel sets, each in its default paint, with paints as swatches (all 18,410 option-and-paint pairs would be too many). To find out first: how close the add-on's materials come to the game's, on one part beside its live picture. The in-game studio (a part copy in front of the TV camera) isn't pursued.
  **Each part on its own** (user, 2026-11-07): a picture shows the part in isolation, clean enough for a menu, never a screenshot of the whole car. The user is open to any route, a hidden render captured and reused included, even a one-time "loading previews" wait the first time the shop's menu opens. **Proven (probe 5, 2026-11-07): a live picture of a part.** The game's TV camera, spawned 1.6 m from a Hella's wheel and switched on, showed a clear live close-up of the rim and tyre in a UI image, and a depth cut of 2.2 m made everything farther away see-through, leaving the wheel, fender and the ground under it. A part fully alone needs nothing else within the cut: a copy of the part set apart, as the game's item preview stands in a hidden corner of the world. Leads found before (2026-11-07): the game has a **camera that renders into a texture** (`entRenderToTextureCameraComponent`: its own resolution, background colour, depth cut-off, scene layer and frame rate), and an ink image can show such a texture by name (`inkImage.useExternalDynamicTexture`, `externalDynamicTexture`), so a small camera aimed at a part shown alone could be a live picture on the tool's screen, with no capturing at all; the game also **loads a picture file from disk into an ink image** at run time (`SystemRequestsHandler.RequestGameScreenshotByPath`, photo mode's gallery), so pictures captured once, by us or on the player's PC, could be shown without packing them into the mod's archive (whether it reads outside the screenshots folder is unknown, and no script call to save a picture was found). Offline, outside the game: WolvenKit exports the meshes with their textures, and Blender with the community Cyberpunk add-on can render each part with a transparent background, though its materials may not match the game's exactly. Showing a part alone in the game is something the engine already does (it hides and shows a car's parts).
- **Likely: trying on as you move through the options** (user: "that's the real solution!"). The car rebuilds with the option you're on; to spare reloads, it waits until you've rested on an option for about half a second, so scrolling past options rebuilds nothing (proposed, instead of the user's first idea of a 2–3 s wait between changes). Each rebuild takes about a second, and test runs have done dozens in a row without trouble. A try-on stays on your own screen until you keep it with Enter, so partners don't see the car flicker and the session's shared state isn't written at each step (proposed).
- **Likely:** adding the shop to the world. ArchiveXL adds new objects to the world's streaming sectors, and the Object Spawner exports a built scene for it.
- **Unknown:** which shop. An existing garage the game leaves dormant, that a car can drive into (user). Each shop sells its own parts: police parts at a shady place out in the Badlands, not at a legit shop (user). A shop with a clear owner leans heavily into that owner's style, such as 6th Street's tuning garage in The Glen selling 6th Street styles, paints and stickers, and one neutral-looking big shop has everything (user). Every shop carries its whole style, whatever its size. Holding back options is annoying when you customize: go to a Nomad shop and you want to see all the Nomad parts (user, replacing an earlier idea that stock should fit a shop's size). A shop's size could instead decide which vehicles fit in it, such as bikes only in a tiny garage (proposed). A shop can depend on how its place's gig ended, and be missed: in Arroyo, a survivor of the gig takes the garage over, and if he dies there's no shop (user, tentative). The game's files point to about twenty places, most of them garages with a car lift that a gig uses once ([SHOPS.md](SHOPS.md)); none seen in the game yet.

**Being tried (user, 2026-11-07): a tool in your hand instead of the stand's computer**, like Garry's Mod's tool gun. The shop has a light tool you pick up, as you pick up a turret's gun, that guides the robot arms; switch weapons and you drop it, and a partner can pick it up. Aim it at the car and a screen built into the tool, about 5 by 5 inches, shows an interface designed as if made in Night City: a grid you move through with the arrow keys, the top row its tabs (the vehicle, then each part under the crosshair, smallest first, a sticker…), Down goes into a row, Left and Right choose, Up goes back. The part you aim at is highlighted. The shop's computer may come back for what needs a big screen: the catalog with pictures, buying, resetting, calling.
- **Proven with the real turret gun, the copy to make:** the tool's behaviour (probe, 2026-11-07). A turret's gun is its own kind of weapon (`Items.Preset_HMG_Default`, equip area `WeaponHeavy`); the game's own request put it in V's hands, and switching weapons dropped it on the ground as a pickup with "Take" and "Equip". Our copy keeps that but must neither fire nor weigh V down: it's a light tool (user). **The turret gun is only the probes' stand-in: the real tool is a new model of our own, not this big machine gun** (user, 2026-11-07); what carries over is the behaviour (the heavy slot's pick up and drop, no firing, no weight) and the way its screen is drawn. To find out: whether an item in the heavy slot can be held one-handed or like a pistol, since the hold comes from the item's animations. Its weight is the gun's data (`OnAttach`: `GLP.HoldingHMG` and stamina packages), which our copy leaves out; firing is still to be stopped. It already has a small display on top, its ammo count. Partners see a turret's gun in your hands and can pick up a dropped one, so the tool should work the same in co-op (user).
- **Proven on the stand-in:** the screen on the tool (probe, 2026-11-07). Guns' screens are a widget painted onto one of their meshes; on the turret gun's ammo counter our own text showed the part under the crosshair ("DOOR FL A", user's screenshot). The real tool gets its own screen mesh the same way, larger, with our own widget. To find out: how readable it is in first person, and making the tool's model and its screen's layout file. The screen can be larger than 5 inches if needed, as long as it doesn't block the view of the car, and it needn't be square: a wider one may show long part names better (user).
- **Proven:** the highlight (probe, 2026-11-07). The game's render highlight event with a component's name (`entRenderHighlightEvent.componentName`) outlines that part only, in the scanner's colours: green (as the user aimed), red, yellow, pale blue seen; following the aim, "it worked pretty well" (user). Fallback: drawing a box round the part, with only the drawing code we need copied from debug_draw into our mod (user).
- **Works, our own:** which part is under the crosshair (probe, 2026-11-07). A car's collision is a few rough shapes, not one per part, so the crosshair's ray is tested against each part's box (from its mesh file) in the part's own space; the lit part followed the user's aim. The smallest hit first (user: "makes sense") picked parts on the far side, so: the nearest part, a smaller one within 40 cm of it first, the body last. Every part needs a box, windows, mirrors and lights included. Once you go down into a row, the tab stays on its part until you go back up, so moving the aim doesn't switch it under you (user, agreed).

**Where options live (user, 2026-11-07): menus are designed from the player's side, not the engine's.** Every option lives on the part it changes: aim at a rim and every rim is there (this car's own and every other vehicle's, scaled to fit), with its paint; aim at a tire and every tire is there; the same for every part. The car's own tab holds only what spans the car: its style (a bundle of parts and paint, named as one), its paint as a whole, and add-ons. One place per option: nothing is changed from two menus with two different lists. Rims and tires are chosen apart (a Thorton rim no longer brings its tire). A change goes where you aimed: a "Back rims" tab changes the back rims unless you choose all of them on it (user: all by default was "confusing/unexpected"). A part's own setting changes that part alone: the tire's width the tire, the rim's width the rim, so one can be matched to the other (user). A new rim or tire fits itself as well as it can and the player adjusts from there, since a fully automatic fit can't be perfect (user, 2026-11-08; RECORD.md). The first tool put the shared wheel list under the car's tab and only the car family's own rims on the aimed rim, which split one thing across two places with different lists and hid most options from where the player looks ("this is bad for discovery", user); "don't cut corners, let's get it right", even if the evening's co-op session waits for it.

**What other games do** (quick research, 2026-11-07; nested menus left out, as that's our first idea; "sourced" means a guide or forum said so, the rest is from knowing the games):
- **Racing games** (GTA V's Los Santos Customs, Need for Speed Heat and Unbound, Forza Horizon, The Crew): a list menu, but the option you're on is on the car at once, and the camera swings to the area you're changing. For us: the try-on as you move through options; with the tool you frame the car yourself by aiming.
- **Mechanic sims** (Car Mechanic Simulator): first person, the part you look at is highlighted, and a pie menu opens on it with its actions; an examination mode colours parts by condition, and the highlighter is a help that its hardest mode switches off (sourced). The closest thing to our tool; its colours carry meaning, not just "this one".
- **A station for one suit** (Fallout 4's power armor station): pieces in a list, the chosen one highlighted on the model, tabs for Repair, Modify and Paint, a dot beside what's fitted (sourced). Players' complaint: the green highlight fills the whole piece and hides the paint colour being chosen (sourced). For us: outline, never fill, and no highlight while choosing a paint.
- **Hand tools in sandbox builders**: Garry's Mod's tool gun shows the chosen tool's name on a little screen on the gun itself, the precedent for our tool's screen; Scrap Mechanic's paint tool opens a palette of ten colours on a key (sourced).
- **Hands-on mechanic games** (Wrench, My Summer Car): no menus, every bolt by hand; it feels great and is slow, more than a shop visit wants.

## 2. Try it on, and the arms do the work

At the stand you pick a part and press Try.
The robot arms swing into action, sparks fly, tools whine, and the part is on the car.
You walk around it, try another, and nothing is paid for yet.

- **Proven:** parts, wheels and paint change on a live car or bike at once.
- **Proven:** a part from another car goes on when it's added as the car is built, and once on, it moves at once.
- **Proven:** adding and removing parts a look doesn't have while the car stands still (user: it has to happen in place). Each look gets two twin names of our own through ArchiveXL; switching to the other twin rebuilds the car in about a second without changing its look, and the build adds whatever the car should carry. Re-applying the current look does nothing, and a respawn on the spot doesn't hold, since the game drives a called car on to the player.
- **Likely:** the arms, sparks and sound. Phantom Liberty's `RoboticArms` device has an animation graph with Idle, Work and Distract states switched by one value from a script, and its entity carries its own `FX_Welding_Sparks` effect and a workshop sound; Delamain's arm from his garage quest carries an `sq025_weld` effect. No sparks of our own unless these fall short (user).
- **Later:** arms that reach for the exact part, which needs animations of our own on their rig. Until then the arms work in place around the bay, and it's fine if the illusion shows a little (user).

## 3. Buy, and the shop takes its picture

You can take the build out for a test drive first; a message tells you to enjoy it and come back to pay, or the new parts come off (user).
When you're happy you press Buy.
Perhaps a flash goes off, like a short purchase cutscene, and the shop photographs the car from a set angle (user): that picture is how the car shows from then on, so two Hellas with the same name are never confused.

- **Proven:** a new copy goes into the garage at once.
- **Likely:** showing a picture from a file, as the photo gallery loads any screenshot by path (`RequestGameScreenshotByPath`).
- **Unknown:** taking the picture. No game script takes a screenshot on request, so a native plugin does it.
- **Unknown:** putting the picture in the game's own call menu, which uses fixed texture atlases today, and naming a copy yourself.

## 4. Buy the car that was never for sale

The shop also sells a fresh copy of any car or bike, including the trucks and vans the game never lets V own, and the stock car stays as it was.

- **Proven:** copies in a file go into the garage at once; the Bratsk truck and Centurion van drove.

## 5. Grab a look from the street

You see a beat-up Hella with a white trunk in traffic, run a quickhack on it, and that look joins the shop's catalog.
It takes a deliberate action, so ordinary scanning in a fight adds nothing (user).

- **Likely:** a quickhack of our own. Vehicle quickhacks are TweakDB records (`DeviceAction.VehicleForceBrakesClassHack`), and mods that claim cars already add quickhacks.
- **Likely:** reading the look, since a passing car's look name and parts can be read live.

## 6. Panel by panel, and wheels from anywhere

A primer hood, a door in another paint, a junk bumper, tires clean, dusty or muddy: the lived-in look V's own Hella already has.
Any wheel set that fits the car, Porsche wheels on a Hella.

The whole car in one color as well, from the car's own paints or any color you pick, with a second color, decals and how glossy each panel is.

- **Proven:** paint on a single part, and Porsche wheels on the Hella.
- **Proven:** switching the whole car to another of its looks on the spot, with your parts put back a moment later; each look has its own set of parts, so a look without separate wheels can't take wheel swaps.
- **Likely:** the whole car in one of its own paints, part by part: a median of 11 paints shared by every body panel, up to 39.
- **Likely:** any color. The game's paint system under CrystalCoat keeps primary and secondary colors as any RGB, with decals, paint layers and clear coat per part; we'd drive it from our own screen. Cars whose materials lack its paint mask need patched materials, generated for each car.
- **Proven** (2026-11-06): any vehicle's wheels on any car (bikes' on any bike), from a shared list of 173 rim and tire pairs, each scaled to the car's own wheel size, front and back chosen apart, with size and width per axle in percent: a Bratsk truck's wheels sat right on a Hella, and narrower rears (for under wheel covers, user) are a width below 100%. Trucks take a set on every axle (a Bratsk's three), and the rims of each side can wear any paint their set offers (118 of the 181 car and bike sets have some); how a painted rim looks up close is still for the user to see.

## 7. It's still yours tomorrow

The car arrives as you built it every time you call it, after a load and after a restart.

- **Proven:** a saved build goes back on about one frame after the car appears, after a reload and after a full restart.
- **Proven:** the build holds when the car comes back from far away, because a check puts back any part that comes back empty; whether a part shows missing for a moment first is unknown.

## 8. Your crew sees it

Partners see your build parked and driving, and you might lend or give a copy to a friend.

- **Likely:** parked cars stay on partners' screens while everyone is near (proven); the build itself would travel as NightCoop entity state.
- **Unknown:** a parked car once the host drives far away, two players owning one copy, and giving copies.

## 9. A quick fix or a fresh car

The mechanic repairs two ways, priced to match (user: "that sounds fun"). A **quick fix** knocks the dents out and replaces the glass where the car stands; it's cheap and fast, but parts that came off stay off. A **full refresh** brings the car round fresh, every lost door and bumper back on, in its build; it costs more.

- **Proven:** the quick fix holds (the game's repair event and its dent and glass resets, with no rebuild), and lost parts and dents both outlive a rebuild in place, which is why a full refresh needs a car brought round fresh.
- **Unknown:** that a car brought round fresh has every lost part back (the dev panel's "Fresh from garage", to try the next time the user is in the game). Putting lost parts back in place as added parts is set aside for now (user).

## How choices are organized

From the car down, each step narrowing the next; the build stacks the same way, each layer over the one below (user: "sounds good").

1. **Model:** the Hella, the Colby, the Nazare.
2. **Style:** a group of the model's looks that share the same parts, such as the Hella's street, 6th Street, beater, police, cab and V's own. The style decides which parts exist, so it comes first. Choosing one puts on its cleanest look as the base. In the shop a style is the version of the car you buy, like a trim at a dealer: you buy a Suburban Hella and customize it from there (user). It stays a layer of the build, so the mechanic can change it later and carry over every choice whose slot the new style has.
3. **Parts:** by mount point and kind, the front bumper, the hood, each wheel's rim and tire, so a choice survives a change of style wherever that mount point exists. Options are every part the model uses there in any of its looks, whatever style it comes from, plus wheels and tires from other cars, for as much freedom as possible (user). Each option could say how sure we are it fits: seen on this style, from another style of this car, or from another car. A slot is one part of the car, a role, so the cabin and the trunk interior are two slots, and a part the current style lacks, such as the police body on a Suburban, is added at its mount point when chosen (built 2026-11-06).
4. **Add-ons:** stickers, stripes, a roof rack, the Nomad kit: separate parts, offered as switches, from this car or any other, a Nomad add-on on a Herrera Outlaw included (user). Each part of an add-on can be placed with fine controls, moved along and turned about each axis, in coarse and fine steps (user), starting from where its own car has it; the whole add-on can be moved and turned as one too (built 2026-11-06). Pairs such as left and right lamps could move as mirror images (proposed).
5. **Paint:** the whole car or each panel, and wear: clean, dusty, beaten up. A whole-car paint sits under the per-panel paints, and a panel takes it only if its mesh has that paint, so the screen has to show which panels do.

Every part is labelled with where it comes from, this style, another style of this car, or another car, so players can tell when they're mixing (user).

**How an option is shown** (user, 2026-11-06): like a real parts catalog, by its picture and a part number, not a made-up name. The part number is the game's own mesh name, tidied and written as the game writes it, in lowercase with underscores (user): the car's name and `ext01` dropped, as in `junk_bumper_f_01` or `wheel_police_02`. Kits get part numbers too (`kit_police_hood_trunk`, or a single part's own number), since a sentence in a model-number field would look out of place; paints show as a swatch with their code (`primer_red`), and styles carry a trim code (`suburban_1`) beside their name. Where it comes from is a separate origin tag with its own colour and icon per kind (this style, another style, another look of the car, another car, a wreck) and the source's name in it, such as "Villefort Cortes", so the source shows at a glance instead of being parsed out of the number.
Styles exist because looks differ in which parts they have. Adding the missing parts as a car is built, attached at a mount point, removes that limit, so any style takes any part and styles become starting points (user: "this is it"). Shown with the Nomad kit on the Hella, which needed fitting: at the Quartz's own offsets its lamps were hidden inside the Hella's bumper.
Parts that hang off a swapped part, such as a hood's sticker, are left as they are in the first version: the experience matters more than perfect visuals (user).

## Later

- **A turntable or lift** in the bay, the car slowly turning while you browse and rising for wheel work (user: maybe later).
- **A parts wall** where the looks you grabbed by quickhack hang in the shop (user: after the first version).

## Not in it

- **Body parts from another car**, such as a Hella bumper on a Porsche: they don't fit.
- **AVs:** calling one from the garage crashed the game twice.
- **CrystalCoat as the model for anything:** the user called it a cop-out instead of a proper customization system.
- **A custom look from far away:** distant cars probably show their stock model.
