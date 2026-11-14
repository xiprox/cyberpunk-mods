# Record

What we found and decided while building NightCoop Tweaks, newest entry first.
[README.md](README.md) says what the tweaks do; this file says why they're that way.

"User" marks what the user saw in the game.
Versions on this PC: Cyberpunk 2077 (CET reports 3.0.88.46235), NightCoop build bacb705, Cyber Engine Tweaks 1.38.1, Codeware installed.

Checked in the game on 2026-10-29: a send from the menu shows the progress bar (user).
Checked in the game on 2026-11-03: the quantity slider opens and closes in the world (user), and a send through it arrives (Bossun's 1 eddy, offered at 14:34:24 on their clock, received at 22:34:25 on Bleack's).
Checked in the game by 2026-11-08: opening the menu from the phone's Contacts works well (user).
Not yet checked in the game: that both F and Enter do it there, whether the mouse wheel moves the selection, whether the amounts come back after cancelling the slider (below), whether map pins give nicknames, and whether NightCoop's dialog votes leave our choice list alone.
CET writes small logs out only now and then, so during a session the mod's log is empty: the NightCoop Tweaks window's Diagnostics section shows what the partner menu sees, which keys reach the mod, and any error.
Not yet checked in the game: anything of Far partner pins (below).
Not yet checked in the game: anything of Horn and Silenced shots (below).
Not yet checked in the game: anything of Siren (below), including that partners don't hear a siren without it.

## 2026-11-14: Partners hear the siren of the police car we drive

This came up while designing a car-controls menu mod, whose police-car switches would flip the game's siren lights and sound apart. The user believes NightCoop doesn't pass a police car's siren sound on, with the game's own V key too, so the fix belongs here and not in the car mod.
That is the user's belief, not yet seen or heard in the game. What backs it:
- No collected log has a line about a siren: Choom Collector's sessions of 2026-11-13 (all four players) and 2026-11-14, the old collector's folders, and the game's own NightCoop logs of today. The one hit is another mod's (Let There Be Flight naming a police record).
- NightCoop's DLL (build 5a51ea59, protocol 183, the one installed) has no siren string apart from three `..._police_siren` names in its list of every vehicle record. Its vehicle code reads and sets the head light mode (`GetHeadLightMode`, `SetHeadLightMode`) and plays a prevention AV's sounds (`av_sound`), and nothing about sirens.

**How the game switches it.** `VehicleComponent.ToggleSiren(lights, sounds)` (`vehicleComponent.script`, line 5557) acts only for a car whose data package has `UseAuxiliary`, the police cars, and only when that car isn't wrecked or the call turns something off.
- Lights: `ToggleLights(lights, Utility)` and the police sign effect.
- Sound: the native `VehicleObject.ToggleSiren(sounds)`.
- Both are kept on the car's persistent state (`SetSirenLightsState`, `SetSirenSoundsState`).

Who calls it:
- Both on or both off: the V key (`VehicleSiren`, a tap under 0.25 s, which flips both by `GetSirenState`).
- Each part as asked: the police AI's `ToggleLightsAndSirens`, a quest's `VehicleQuestSirenEvent`, a chase (`VehicleChaseTargetEvent`), and the record's default state 0.5 s after the car spawns (`SirenLight`, `SirenSounds`, which the `_siren` records set).
- Both off: the player getting out (`OnUnmountingEvent`), the wanted level dropping to 0, and the car's death.

**The sound** is in the audio metadata the horn's came from: `audioVehicleMetadata.generalData.sirenOnEvent` and `sirenOffEvent` (`..._siren_start`, `..._siren_stop`).
- 12 audio resources have one: the Archer Hella, Chevalier Emperor, Militech Hellhound and Villefort Cortes police cars, and the Thorton Merrimac police and MaxTac. Each also has a `_traffic` resource with events of its own, and the MaxTac Merrimac uses the Emperor's siren.
- `tools/make-sound-tables.py` now also writes `tweaks/siren/sirens.lua`. Its `horns.lua` and `silencedshots/sounds.lua` came out byte for byte as before.

**The tweak.** `tweaks/siren` observes `ToggleSiren` before and after (`ObserveBefore`, `ObserveAfter`) and compares the car's `GetSirenSoundsState` across the call. So a call that changes the lights alone, one the game refuses (not a police car, a wreck), or one that repeats the state sends nothing. That leaves the car-controls mod free to switch lights and sound apart.
- Sound on, in a car we drive (the horn's driver-seat test): the siren's on event on partners' copy, through `core/sounds.lua`.
- Sound off: the off event, and 0.4 s later a stop of the on event itself, as the horn does. A new start in that car within the 0.4 s calls the second stop off, the silenced shots' lesson.
- The off also goes for a car we drive whose siren we didn't start: one that was already sounding when we took the wheel, which partners' copy might be playing of its own accord.
- Every 0.5 s, a siren on at partners is stopped if the car is gone, we're no longer in its driver seat, or its sound is off.
- The car's resource is its record's `player_audio_resource` where the table knows it, else its `AudioResourceName`, as for the horn.

The horn's driver-seat test and resource lookup moved to `core/vehicles.lua`, since the siren needs them too. The horn is otherwise as it was. The mod is 0.1.5 with the siren.

An offline run of the real `core/sounds.lua`, `core/vehicles.lua`, the siren tweak and the horn tweak, with the game, CET and the SDK stubbed (the game's `ToggleSiren` rule copied into the stub), went through:
- V on and off; the lights alone; a state repeated; getting out with the siren on; an NPC's police car; off and on again within 0.4 s; the car gone; a passenger seat;
- a siren on before we took the wheel; a car known only by its traffic resource; a car that isn't a police car; a wreck; an unknown car;
- the checkbox, no session, NightCoop's "not now", and Reload All Mods with the siren on;
- the horn's press and release, and a passenger's press, after the move.

Each sent what it should. That says nothing about what the game plays.
Not yet checked in the game:
- that partners really hear no siren without this; if NightCoop does pass it on, this doubles it, which would show as two sirens or one that won't stop;
- that the `_siren_start` events play and loop on partners' copy and stop with `_siren_stop`;
- that CET's `ObserveAfter` fires for `ToggleSiren` as `Observe` does for the horn;
- whether partners' copy of a car whose record turns the siren on at spawn (`_siren` records) starts one of its own, and whether our off reaches it;
- which resource the game's police records name.

A siren already sounding when we take the wheel isn't sent, since nothing switched. Whether NightCoop passes the police lights on is unknown, and not this tweak's.
In a session, the window's Siren section counts starts and stops. Diagnostics' "Sounds to partners" line says whether they went out, and each partner's nightcoop.log counts the mod sounds it played in its "fired paths" line (`sdk_fx:sound`).

## 2026-11-13: Partners hear our horn and our silenced shots

Two things were annoying in co-op (user): a car's horn wasn't heard by the partners, and a silenced weapon made no sound for them whatsoever. Both are NightCoop's (build 5a51ea59, protocol 183), not ours.

**Silenced shots are muted on purpose.** A partner's shot on our side is a blank shot, and NightCoop gives it the weapon's own NPC shot sound ("weapon sound: ... plays the weapon's own shot sound ('shoot' of its gameWeaponAudio, npc settings ...)"), except for a silenced weapon: "weapon sound: a blank shot has no sound — silenced shot". That line is in every crew member's logs from 2026-10-29 to today's session, and its reason, "silenced shot", sits in the DLL among the other reasons a blank shot is silent ("not a weapon", "no weapon audio", ...).
The game has the right sound. In `base\sound\metadata\cooked_metadata.audio_metadata` (in `audio_1_general.archive`) a weapon's `audioWeaponSettingsGroup`, named by `Item_Record.AudioName()` (`wea_set_unity`), has `playerSettings`, `npcSettings`, `playerSilenced` and `npcSilenced`. The NPC settings name a gun choir of voices (`audioNpcGunChoirVoice`), each with a single shot (`fireSound`), a burst, or an automatic loop and its stop event (`autoFireSound`, `autoFireStop`). Unity's silenced NPC shot is `w_gun_npc_unity_fire_voice_01_supp`, heard to 150 m; the plain one, 500 m. Of the 74 sets, 16 have their own `npcSilenced`; the others have none, and Panam's Grad's plain NPC sound is already its silenced one.

**A car's horn isn't synced at all.** The only horn NightCoop handles is a prevention AV's ("the game's AV sound scripts are watched ... descent, horn, hover, ascent ... (av_sound)"), and its DLL holds no other horn string. The driver's horn key goes `VehicleComponent.OnAction` → `ToggleVehicleHorn(state, isPolice)` → the native `VehicleObject.ToggleHorn` on our car, and partners' copy of it, a mirror NightCoop places, never hears it. Each car's horn is in the same metadata: `audioVehicleMetadata.generalData.hornOnEvent` and `hornOffEvent` (a loop and its stop, heard to 30 m), named by `Vehicle_Record`'s `player_audio_resource` (`v_car_thorton_galena`); a bike's is one 2 s beep with no stop, and police cars are their own resources with their own horn.

**Both go through NightCoop's SDK.** `NightCoopSdk.PlaySoundOn(id, entity, event, stop)` plays a sound event, as `GameObject.PlaySound`, on each partner's mirror or copy of an entity NightCoop syncs: our player (their body of us) or a vehicle. Partners need only NightCoop; their NightCoop takes it from a mod whose passport declares `UsesEffects`, so `core/sounds.lua` registers the mod as `xip.nightcoop-tweaks`, protocol 1, with that flag alone. That's the first time this mod registers; before, it only read the SDK. Sounds go out from CET's `onUpdate`, the place NightCoop's CET guide polls from, since SDK calls belong on the game thread; hooks only queue them.
- NightCoop takes 10 sounds a second from a mod in bursts of 20 (`NCSDK_FX_PER_S`), and nobody says whether they arrive for sure. So ordinary sounds keep to 8 and 16 of our own and are dropped past that, and a sound that ends something (a horn's or a loop's stop) is tried again for 2 s while NightCoop says "not now" or "over the limit", and goes a second time 0.4 s later as a stop of the sound's own event.
- `tools/make-sound-tables.py` writes `tweaks/silencedshots/sounds.lua` (65 weapon sets) and `tweaks/horn/horns.lua` (173 vehicles) from that metadata, so no event name is typed by hand.

`tweaks/horn` observes `VehicleComponent.ToggleVehicleHorn` and plays the horn on our car for partners when our player sits in its driver seat (the mounting facility's slot `seat_front_left`, as the game's `IsDriver`), not in an AV. The stop goes out when the release comes for that car, or when we're no longer in its driver seat with the horn still on.

`tweaks/silencedshots` observes `ShootEvents.OnEnter`, once a shot in the local player's weapon state machine (partners' bodies have none), and acts on `weapon:IsSilenced()`. A shot is the set's single shot where there is one; held full auto, or a weapon with only a loop (the silenced Lexington, Pulsar, Ajax), runs the loop while shots keep coming within the weapon's `CycleTime` and 0.1 s, then sends its stop; a lone shot of a loop-only weapon stops it at 0.9 of a cycle, for one shot; the Masamune's silenced NPC sound is a burst only, played as firing starts and every 0.6 s while it goes on. Each player gets one of the set's voices by peer id, as each NPC gets one.
Neither hook is in NightCoop's `do-not-hook.md`.

An offline run of the real `core/sounds.lua` and both tweaks, with the game, CET and the SDK stubbed, went through a press and release, a passenger's horn, getting out with the key held, a bike, a police car, an unknown car, single shots, an unsilenced weapon, a partner's shot, full auto, a lone loop shot, bursts, Umbra's two kinds, a weapon change mid-loop, our own limit, NightCoop refusing a stop over its limit, no session, and a shutdown mid-loop and mid-honk; each sent what it should. That says nothing about what the game plays.
Not yet checked in the game: that CET's `onUpdate` counts as the game thread for `PlaySoundOn` (a "not now" in Diagnostics, and "from another thread" in nightcoop.log, would say not); that `IsSilenced` is NightCoop's test too (if not, some shots play twice or not at all); how the NPC loops sound driven by our trigger, at their own rate rather than our weapon's; the 0.6 s Masamune burst, a guess; that partners hear it from our body, not the gun; and whether `GetMountingInfoSingleWithIds` takes the one argument from CET.
If NightCoop's developer makes silenced shots heard, this would double them: check its log for the "silenced shot" line first.

**First try, 21:58 that evening, after everyone's Reload All Mods (user):**
- The user honked in a car and nobody heard it.
- Bossun honked in the same car. Bleack and Ecto heard it, the user didn't, and Bleack and Ecto went on hearing a horn at the car after he got out.

The logs say only the user's copy ran the new tweaks:
- The user's NightCoop log has "[xip.nightcoop-tweaks] registered — 'NightCoop Tweaks' 0.1.3" at 21:58:06.
- The mod lists the three partners sent at their reloads (21:58:09 to 22:00:03) don't have it.
- Choom Collector's Mods tab had delivered the new files in four batches, but never `init.lua`, which loads them. Its hub had been looping since 21:56:26 on "init.lua changed on xip's PC while it was being sent": the file had been saved in three quick edits and the collector offered a hash from between them. The collector's log collection stopped at 21:56:23 too.
- So the partners ran 0.1.2's `init.lua` with the new files unused beside it, and Bossun's honk was never sent.

What Bleack and Ecto heard is unknown: possibly the user's horn, started at their side and never stopped. Their logs from the test weren't collected.

The car was the host's player car. The user's own car of that record was its mirror (NightCoop's `player_car_place`), and the user sat in its driver seat from 21:58:12 to 21:58:29.

NightCoop's receiving side, read in build 5a51ea59's disassembly (`HandleEffect` in `SdkSpawns.cpp`), plays a mod's sound with `AudioSystem.Play(event, entity, no emitter)` and stops one with `AudioSystem.Stop`. The game's own `GameObject.PlaySound` takes another path for an entity: it queues an `AudioEvent` on it. Still unproven:
- whether a horn loop started NightCoop's way stops by the horn's stop event, or by `AudioSystem.Stop`;
- whether the user's sends went out at all, which the Diagnostics window shows and no log does.

Later, partners' logs (collected once the collector was restarted) showed that the user's sounds had gone out after all. Each partner's NightCoop counts the mod sounds it plays in its "fired paths" line, and by 21:58:57 `sdk_fx:sound` was 45 on all three, Bossun 2 m away among them.

**Second try, after everyone had 0.1.3 (Reload All Mods 22:16 to 22:18, user):**
- Honking "seems to work perfectly".
- The user's suppressed Shigure on full auto was heard by everyone for its first three shots, then went silent.
- Bleack's Overwatch was heard by nobody.

The Shigure is the Arasaka Shigure, a Saratoga preset (`LocKey#51341`), so its audio set is `wea_set_saratoga`. Its silenced NPC voice has only the automatic loop (`w_gun_npc_saratoga_fire_voice_01_supp`, looping in the metadata) and its stop. So the tweak ran the loop, and something ended it after about three shots: either the loop's stop went out mid-burst, or loop starts and stops ran into NightCoop's 10-a-second limit. The window's counts will tell which.

NightCoop itself plays a blank shot through the game's weapon audio with a mode, 'single', 'automatic' or 'burst', taken from the weapon's record (DLL strings: "the mode of a blank shot follows the weapon's record (FullAuto → 'automatic', others → 'single')"). The game manages an automatic loop inside that call. A bare loop event is the tweak's own approximation.

The Overwatch (`Preset_Grad_Panam`) has no silencer attachment: its blueprint is `Iconic_Ranged_Weapon_NoMuzzle_Blueprint`, and it carries `BaseStats.CanSilentKill = 1` itself. The game's `ShootEvents.OnEnter` takes the silenced path (`SilencedShoot`, silenced stims) on `CanSilentKill > 0`, while the tweak asked `weapon:IsSilenced()`. NightCoop muted a partner's shot at 22:18:21 on the user's side, its first "silenced shot" since 20:49. After 22:18:33 the user's NightCoop played no more partner mod sounds. Silencer attachments (`w_silencer_01`), several iconic mods and PL's tech sniper also give `CanSilentKill`.

The user's window, after the Shigure (22:16 to about 22:35):
- "183 silenced shot(s), 29 sound(s) sent; last: wea_set_saratoga, loop of wea_npc_saratoga_suppressor".
- "108 sent, heard 324 times, 0 dropped over our own limit", with no refusals.

`ShootEvents.OnEnter` does come once a bullet. NightCoop refused nothing, so its limit wasn't the cause. But 183 shots made 29 loop runs: the loop kept stopping and starting again mid-fire. Two faults in 0.1.3, both reproduced offline:
- A run ended once no shot had come within the weapon's cycle and 0.1 s. A frame hitch is longer than that, so held fire split into runs.
- A run's second stop, 0.4 s after the first, stops the loop's event by name. So it also stopped the next run's loop when that started within the 0.4 s. In the offline run, a second burst 0.25 s after the first had its loop stopped 0.23 s in, while still firing: "three shots, then silent".

0.1.4 ends a loop where the game ends the firing sequence: `WeaponTransition.EndShootingSequence`, called as the weapon goes back to ready (after its cycle, so a lone shot too), reloads, is lowered or put away. It's the same place the game lifts the weapon's trigger (`SetTriggerDown(false)`). A second without a shot ends a loop too, should that call not come. A new start of the same loop calls off the earlier run's second stop: the new run's stop ends any instance left over.

0.1.4 also takes a shot as silenced by the game's rule, `CanSilentKill > 0`, not `IsSilenced()`. The offline run went through the earlier cases again, plus:
- a hitch mid-burst: one loop;
- two bursts 0.25 s apart: nothing stops the second while it fires;
- a stat-silenced gun with nothing attached: the Overwatch's suppressed shot;
- no end of the sequence: the loop stops a second after the last shot.

Bleack had quit, so his window couldn't confirm that `IsSilenced()` was false for the Overwatch. Still unchecked in the game: how the NPC loop sounds for a whole burst, and whether a lone shot of a loop-only weapon (silenced Lexington, Pulsar) sounds as one shot when its loop runs for one cycle.

Phantom Liberty keeps its own `ep1\sound\metadata\cooked_metadata.audio_metadata` (in `ep1\audio_1_general.archive`), which the generator didn't read. It now reads both, with one namespace, since a PL set can name base-game settings: 70 weapon sets, up from 65, and the same 173 horns.

## 2026-11-08: The partner menu opens from the phone only

The "[F] Interact" prompt next to a partner got in the way, and the phone's Contacts alone work well (user).
The prompt is gone, with its look-at and facing checks and the 1 m reach. `PartnerMenu.OpenFor` is the only way in, so the menu now closes only when the partner leaves the session, not when they walk 5 m off. While no menu is up or asked for, `PartnerMenu.Update` does nothing, and the Diagnostics no longer list partners' distances or what we look at.
Entries below that describe the prompt are history.

An offline run of the real `core/partnermenu.lua` with the game stubbed went through idling beside a partner (no list, no game calls), opening from the phone, a far partner, a car, a popup coming back, combat refusing, a phone that stays open, and the partner leaving; each ended where it should. That says nothing about what the game draws.
Not yet checked in the game: that the prompt no longer comes up.

## 2026-11-08: Partners stay on the map when they're far away

Partners' map markers vanished past a certain distance (user). NightCoop's logs say why: "puppets: peer 2 is 200 m away, their body is removed until they come closer", and 0.1 s later "the map pin of xip (peer 2) is removed". The pin is registered on the body (`RegisterMappinWithObject`), so it goes with it, and the floating name tag says "no marker: no body in our world".
In Bleack's and Bossun's logs, 30 of 47 removals are at 200 or 201 m and the rest are jumps of 244 to 3039 m; no body ever appeared farther than 151.4 m. Both 200 and 150 are constants the function loads from the DLL, and no setting changes them. Raising them isn't the fix anyway: a body far off would stand in a part of the city that isn't loaded.
It isn't a limit of the game's map: NightCoop gives the pin `MappinUISpawnProfile.Always` (no distance limit) and `MinimapMappinUIProfile.Quest` (`clampX`, `clampY`, so it sits on the minimap's edge).
NightCoop goes on tracking a partner with no body: Bossun's log has peer 1 removed at 200 m and made again at 146.9 m almost three minutes later.

`tweaks/farpins` puts our own pin at `NightCoopRemoteInfo`'s position while a partner has no body, and moves it four times a second. The rule is "no body", not "past 200 m", because coming back a partner has none between 200 and 150 m either.
- It uses the SDK for who has a body and what they're called (`NightCoopSdk.PartnerBody`, `PeerName`; reads need no registration). Matching pins to partners by position, as `core/nightcoop.lua` does, can't tell who's who when two stand together. If the SDK doesn't answer there are no pins, since "no body" would put a second pin on everyone.
- The pin has NightCoop's own pair, `Mappins.CPO_RemotePlayerMappinDefinition` and `CPO_RemotePlayerVariant`, because NightCoop's hooks on the minimap profile, icon and title choose by variant. NightCoop's pin goes through `RegisterMappinWithObject` and ours through `RegisterMappin`; NightCoop places its objective pins that way, with `Mappins.QuestStaticMappinDefinition`.
- `core/nightcoop.lua` reads these pins too when it learns names. They carry the right name at the partner's place, so that's harmless.
- It reads the mode from `NightCoopMarkers("status")` every 5 s and stays off when NightCoop's map markers are. A partner in their own world, not the host's, also has no body here, so they keep a pin at the position NightCoop gives.

An offline run of the real `tweaks/farpins/tweak.lua` and `core/nightcoop.lua` with the game stubbed went through a body leaving and coming back, two partners, a load, the session ending, NightCoop's marker modes, the SDK off and missing, a refused pin and shutdown; each ended where it should. That says nothing about what the game draws.
Test with a game restart, not Reload All Mods: that drops NightCoop's hooks, and the pin's look depends on them.
Not yet checked in the game: whether the game takes a position pin of this pair and draws it with NightCoop's icon on the map and the minimap's edge, its caption on the map, and the `MappinData.new()` and `RegisterMappin` calls with this definition.

## 2026-11-03: After cancelling the amount slider the menu wouldn't open for a while

After "Custom amount..." and Cancel, the send menu couldn't be opened again for a while (user, on all three players).
The logs don't show the cancel: nothing logged the slider opening or closing, and CET had written the user's log only up to 21:33. They do show the menu staying "open" with no send: Bossun's 14:34:38 for 37 s, until a menu opened, and 14:35:27 for 59 s; Bleack's 22:35:23 for 34 s. A stretch that long is rare in the earlier sessions. Bossun's transfer at 14:36:02, inside the 59 s, has no "Sent" line and left the menu open, so it didn't go through the menu; the CET window sends without either, so it probably came from there.
While the state is "open" the prompt stays off, and only a pick, the partner walking off or something like a menu ends it, which would fit "temporarily".
What only the cancel does: it drew the amounts list from inside the popup's close callback, with the popup still coming off the screen. A send closes the menu there and draws nothing. The phone lost its list in the same kind of moment (2026-10-29), so the list now comes back from `PartnerMenu.Update`, half a second after the popup closes, the same wait the phone gets.
That the list was on the blackboard but not on the screen is the best guess, not something seen. Nothing in the game's scripts explains it, and F on such a list would still pick from it, so two blind presses would have sent money; the logs have no such send.
For the next time, the log now says "quantity popup closed: cancelled" (or the amount) and "partner menu: waiting for a tweak's popup", and "open for ..." again when the list is back. No "quantity popup closed" line would mean the popup's callback never came, which would leave the menu waiting for good.
An offline run of the real `core/partnermenu.lua` and `tweaks/sendmoney/menu.lua` with the game stubbed went through cancel, opening the slider again, a send, Back and Never mind, the partner walking off during the wait, a menu opening on the same Esc, and a slider that won't open; each ended where it should. That says nothing about what the game draws.
Not yet checked in the game.

## 2026-11-01: A partner in first-person stands on a bike

Anyone riding a bike in first-person looks like they stand to the others, and sits in third-person (user, on all three players). NightCoop's reports agree: "body at the handlebars of a bike" gives hands at 0.98 m and none of the frames collapsed at the seat, against 0.03 m and nearly all of them. It looked like one player's problem because the user rides in first-person and the friends in third.
NightCoop puts a body on a bike on the graph's third-person branch whatever the rider's camera (its switches `bike_tpp_all`, `bike_rider_tpp`). `NightCoopAnimTap(20)` on the rider, across a switch from third-person to first, shows what fired once: the wrappers `player_fpp_head` = 1 and `player_tpp_head` = 0, `TPPRepresentation` (NightCoop keeps that from the body), and two camera reset events. At least some of a body's animation sets are gated on `player_tpp_head`: NightCoop's "body builder" line drops a security-cam set "on player_tpp_head". So the bet is that the wrapper takes the third-person bike clips away and the graph falls back to a stand.
This fits what looked odd: after a game restart the user sat in first-person, not having switched camera yet, so the wrappers hadn't been sent. A body also sits only some seconds after a switch back to third-person, as an npc copy "stands in its seat workspot" while its clip sets load. It's still a bet: the wrapper count on a body didn't change at the moment one sat again, seconds later, and the tap's report gives features only as counts, so an input inside a feature would not show.
`tweaks/bikeseat` writes both wrappers back on every other `PlayerPuppet`. A body that never had them changed sits fine on foot, so this should leave everything else alone. The other way, turning those two switches off, changes every rider, and NightCoop's text warns of a "spine rebuilt for the camera".
First try, 23:57 that night, ten times a second on all three machines (the log collector's Mods tab brings this mod to the friends, and each reloaded): "still broken" for everyone (user).
NightCoop's pose lines say it helped but not enough. The user's first-person samples on the other two machines went from 270 standing and 9 sitting to 13 standing and 49 sitting (hips over or under 0.5 m, about every 5 s). What's left comes in stretches of about 5 to 25 s after a camera switch, getting on, or a new body, and then the body sits: 23:57:42 to 23:57:47 after a switch, 00:02:25 to 00:02:46 and 00:04:54 to 00:05:14 after a new body. Short rides and switching back and forth are nearly all stretch, which may be what everyone saw. The fall to about a fifth is the best evidence for the wrappers so far, though it doesn't name them alone.
So 0.1.1 writes them every frame, in case the stretch is the clips loading again after even a moment with the wrapper off, and looks for a missing body every second, not every three.
Checked in the game on 2026-11-02: it "works seemingly perfectly" (user, after testing with the friends). From 0.1.1 loading at 00:38:41 on the user's clock to 00:44:47, NightCoop's pose lines on all three machines have first-person riders 100 sitting and 0 standing, all three players among them, and third-person riders 63 and 0; 4 of the 107 samples with no known camera stand. The lines come about every 5 s, so a shorter stand wouldn't show. Frame times didn't rise over those 6 minutes (33.4 to 33.4 ms, 21.7 to 18.9, 11.3 to 9.6).
That the clips load again after a moment with the wrapper off is still inferred; the logs don't show it directly.
Not yet checked in the game: how long the look through `Game.GetEntityList` takes, and a longer session.

## 2026-11-01: The phone opens the partner menu in a car

The menu was off in every vehicle because F also gets out of the car, an assumption nobody had checked. The game's script (`vehicleTransition.script`) only gets out once F is held for 0.3 s, and our pick is a tap, so the user asked to loosen it.
From the phone the menu now opens in a car and stays open there; a list opened by walking up still closes on getting in, and the walk-up prompt stays off, since partners in their seats are all within reach and it would come up at every glance at them.
In a car a pick has to end within 0.25 s, not the usual 0.35 s, so one press can't both pick and start getting out; Enter picks there too.
F and the scroll keys do reach the mod in a car: every vehicle input context includes `InteractionActions` through `UIExploration`. A quick F does one other thing in a car, only with a weapon drawn in car combat: it puts the weapon away.
A ride of the story keeps the menu off (the player's `VehicleScene` status effect tag, the one the game's `IsExitVehicleBlocked` reads), so our list can't share F with a scene's "Skip Ride".
The first try refused from the phone in a car: "in a workspot (seated or leaning)" (user). A car's seat is a workspot to the game (`IsActorInWorkspot`), which the vehicle rule used to hide by coming first, so the seat rule now leaves cars alone.
Not yet checked in the game, including whether the car keeps moving behind the amount slider.

## 2026-10-29: F on a ride's dialog choice also skipped the ride, by NightCoop, not us

In Panam's car, F on "How much do you know about Rocky Ridge?" also took the "Skip Ride [F]" prompt, and the ride jumped ahead (user).
NightCoop's log has both from the one press, at 21:31:10.995: "dialog vote #76: we vote for option 4 ... (our press)" and "scene skip: we skip the cutscene of scene 0x14fa37456a18f706 (node 1753: the player's "cancel")", then the car moved 853 m by a quest teleport. NightCoop takes the choice press for its vote and plays it to the game later ("press replayed through the interaction manager"), so the press itself was left to the ride's skip, which shares F.
Our mod had no part: in a vehicle the partner menu is off and writes no choice list, and its key listener only listens (`ItemQuantityPickerController.OnAction` consumes nothing). The game's own scene skip is Y (`SceneFastForward`), unchanged in the user's key bindings, so "Skip Ride" on F is the scene's own option. For NightCoop's developer to fix.

## 2026-10-29: No prompt in scenes or seats

In a scene (V seated with Johnny, no HUD) the "[F] Interact" prompt came up for B, because NightCoop stands every partner on our spot during one (user).
The game keeps the scene's tier in the player's state machine blackboard (`PlayerStateMachine.HighLevel`, `gamePSMHighLevel`: tier 1 is full gameplay, 2 a staged walk, 3 limited, 4 and 5 cinematics), and its own code holds gameplay back from tier 2 (the pocket radio, the forced holster), so the partner menu is off from tier 2 to 5, and in a workspot (`WorkspotGameSystem.IsActorInWorkspot`, a seat or a lean), where F can be the way out.
Diagnostics names the tier when it's off for one.
Checked in the game on 2026-10-30: the menu went off for tiers 2 to 5 through the evening (the user's log).
That night the prompt came up again in the scene where Scorpion's drone scouts for Panam (q104) (user). NightCoop's log has our player "controls a device ... (plays as V, scene tier 1)" from 20:15:31 to 20:16:40, out of the car, with both partners working the drone from the same spot: flying a drone is tier 1, so the tier check let it through. The game keeps that in the same blackboard, `PlayerStateMachine.IsControllingDevice` (a drone, camera or turret) and `IsUIZoomDevice` (zoomed into a device's screen), and turns the phone off for either (`PhoneSystem.IsBlockedByBlackboard`), so the partner menu is off for either too.
The user suggested a backstop that would have caught both: a partner on our exact spot. NightCoop's log shows it in the drone scene, "the body of peer 0 stands inside our player (0.0 m: one spawn point for both) — hidden until one of us steps away", and the same for peer 1, and the prompt even favoured such a partner: the facing check took one closer than 0.2 m as faced head-on. So partners within 0.3 m are now left out of the prompt (Diagnostics marks them "on our spot, left out"), whatever the scene's tier or flags say; two people facing each other stand farther apart than that, and a partner walked into steps out of it.
Our own mod's log had nothing from then: CET had last written it at 19:55, and the log collector skips our junctioned mod folder, so its copy of that log isn't collected; NightCoop's log was the record.

## 2026-10-29: A nickname goes to a partner only when they stand apart

Both partners showed as "B" in the phone's Contacts, where one is Bleack (user).
The mod's log shows how: "peer 2 is B" while peer 0 was B, and later "peer 0 is Bleack" and "peer 3 is Bleack" in the same second. Each partner took the name of the nearest pin within 2.5 m, so with B's pin missing from the lists for a moment and B standing by Bleack, both took Bleack's; and names, once learned, were never looked at again.
The pins carry nothing that ties them to a peer (`IMappin.GetEntityID` gives the body, which nothing maps to a peer id; `NightCoopRemoteInfo` has only peer, position, yaw, speed and tick), so pairing stays by position, made strict:
a pin names a partner only when no other partner is within 2.5 m of it and no pin of another name is within 2.5 m of them, so partners close together are left until they part; a new pairing is taken once two looks in a row, 2 s apart, agree, since a pin can trail a moving body; a nickname is one partner's, and whoever had it by an earlier mix-up loses it (back to "Peer N") when its owner is paired again; and the pairing runs every 2 s for as long as there are partners, so a wrong name is put right.
An offline run of `core/nightcoop.lua` with the game stubbed went through partners together, a trailing pin, B beside Bleack's lone pin, parting, and an old mix-up, and gave the right names each time; not yet checked in the game.

## 2026-10-29: Partners are contacts in the phone, and calling one opens their partner menu

The phone's Contacts tab (`NewHudPhoneGameController`, the 2.x phone) is filled in `SetScreenType` from `MessengerUtils.GetCallableAndNonEmptyContacts`, the journal's contacts as `ContactData`.
Overriding that function failed in the game: CET answered "Function GetCallableAndNonEmptyContacts in class MessengerUtils does not exist" (user), because a script's static function isn't a member of its class but a global named `MessengerUtils::GetCallableAndNonEmptyContacts;JournalManager` (NightCoop's dump lists it as `G`), which CET's Observe and Override can't reach. `tools/check.py` now checks every hook against the class's member functions.
So `core/phone.lua` observes `SetScreenType` instead and, on the Contacts tab, adds one `ContactData` per partner NightCoop reports (type `Contact`, callable, preview "NightCoop partner", an id `nightcoop_peer_<peer>` and a negative hash, clear of the journal's); the game already mixes a script-made entry into its contact lists, the "Show all" item.
Appending them to the list's data source (`AppendItem`) after it was filled added them, by Diagnostics, but they didn't show (user), so the list is filled again with `PopulateListData`, the game's contacts and ours, the way `SetScreenType` fills it; that sorts the partners by name among the callable contacts.
F in the phone's list is the `click` action (F, left mouse, X on a pad), which on the Contacts tab calls `CallContact`; the override sees our id, closes the phone with `CloseContactList` and hands the partner to `PartnerMenu.OpenFor`, before the game builds a holocall, so NightCoop's call sharing ("any contact, shared dial and answer") never sees a call.
The partner menu waits for the phone to close (`UI_ComDevice.ContactsActive`) and opens the partner's list with no prompt and no walking-off rule; in combat it says so on screen instead (in a vehicle too, until 2026-11-01, above).
The first try opened for one partner but not the other: for B, the host 59 m away, Diagnostics said the menu was open for them, from afar, while no list was on the dialog blackboard (user). Something took the list off as the phone closed; what, and why for that partner, is unknown. So the menu now waits half a second after the phone closes, and keeps the list it shows and puts it back whenever it goes missing while open (Diagnostics counts how often).
The phone's Call key is the `click` action, bound to F, left mouse and pad X but not Enter, so Enter on the game's own contacts does nothing; the user wanted Enter on a partner too. The phone listens for its keys on the player (`RegisterInputListener`), which doesn't send it Enter at all, so `core/phone.lua` reads Enter itself, as `UI_Apply` or `ChoiceApply` with the Enter key behind it, and calls the selected partner when the phone is up on the Contacts tab. Whether those actions reach a listener on the player while the phone is up is untested; Diagnostics' "Keys heard" and "partner calls ... by Enter" will say.
Reading keys moved out of `core/choices.lua` into `core/input.lua`, one listener on the player for every action any part asks for, so the phone and the choice list don't each register one.
In our lists Enter picks, since `ChoiceApply` is bound to F, Enter and pad X.
A real chat thread with the partner was ruled out: the messenger draws threads from journal entries a mod can't make at runtime, and NightCoop wraps `MessengerDialogViewController.ActivateReply` to send every chat reply to the host.

## 2026-10-29: The payee's glowing eyes are parked

In the story's payments the payee's eyes glow orange and flicker while the bar runs (user), so on a send our game would play that on its own copy of the partner's body, needing nothing from their side.
The game's scripts never name it (quest scenes play it), so `core/effects.lua` lists the effects of what we look at (an entity's `entEffectSpawnerComponent.effectDescs`) in Diagnostics and plays one from the console, to find its name on an NPC and see whether a partner's body has it; NightCoop adds effects to partner bodies for its Sandevistan trail, so a missing one could be added the same way.
The user parked it before the name was found.

## 2026-10-29: A transfer shows as the game's progress bar

The user wanted the "transaction in progress" bar from the story's payments in place of the on-screen message.
It's the HUD progress bar quests and quickhack uploads use (`HUDProgressBarController`), drawn from the `UI_HUDProgressBar` blackboard, with a money look (the eddies icon) for `gameSimpleMessageType.Money`.
`core/progressbar.lua` sets it in the game's own order (`rpgManager.script`): Active, header, the texts, the message type last, so our own header keeps the money look, which the controller otherwise picks only for two of the game's headers.
The bar follows the real transfer: it fills while NightCoop's request is out and completes once our balance drops, which is when the host accepted it and NightCoop debited us; it fails at once on a refusal, or after 8 seconds without an answer.
It doesn't sync to partners (NightCoop only reads its controller to place its own status line), so only the sender sees it, as in the story.
When a quest's bar is already up, the on-screen message comes back instead.

## 2026-10-29: The prompt comes up within 1 m of a partner we face

At first the prompt only came up when the game's look-at target was the partner's body, which needs the crosshair on them, and it rarely showed (user).
It now also comes up when the camera faces a partner within 20 degrees across the ground; a partner in another world has no body here, but a prompt for them still works, since money goes through the host.
The range was 3 m, and the user found that too far: it's 1 m now.
It stays off in combat, because the game treats our list as a conversation and holds back consumables and grenades while one is up.

## 2026-10-29: F reaches the menu as ChoiceApply or Choice1, read with ListenerAction's static functions

The prompt came up, but F did nothing (user).
Two things changed at once and F works since (user), so which one it was is unknown: the handler read the action as `action:GetName(action)`, while CET 1.38 knows `ListenerAction` (native `gameinputScriptListenerAction`) with static functions, now called as `ListenerAction.GetName(action)` with the old form as a fallback; and the mod listened only for `ChoiceApply`, which NightCoop watches for its dialog votes, and now also listens for `Choice1` (and `Choice1_Release`), what F sends for the game's own "[F] Open" prompts.
One F comes as both, so the first press and release count once.
The Diagnostics section's "Keys heard" line names the last action the mod got.

## 2026-10-28: One mod of many tweaks, on a shared core

The user plans more NightCoop tweaks, so the mod is one CET mod with a folder per tweak under `tweaks/` and what they share in `core/`, rather than a CET mod per tweak: the partner's "[F] Interact" list has to be one list, and two mods would each write their own to the dialog blackboard and read F twice.
Tweaks add entries to that list through `core/partnermenu.lua` and draw a section of one CET window.
`init.lua` runs every tweak's hooks in `pcall`, and a hook that throws stays off until Reload All Mods, since a tweak that fails every frame would otherwise stop the ones after it and fill the log.

## 2026-10-28: Partner nicknames come from NightCoop's map pins

No NightCoop native gives a partner's nickname: `NightCoopStatus` has only our own peer id, `NightCoopRemoteInfo(i)` gives `peer=N pos=(x, y, z) ...`, and the status natives that mention peers (`NightCoopSessionStatus`, `NightCoopMenu`, `NightCoopMarkers("status")`) print states, not peer-to-name pairs (read in their disassembly).
NightCoop's logs do pair them, "map pin #1 for Bleack (peer 4) on the body 0x9de835", and that pin is the way in: NightCoop registers one per partner body with the game's `MappinSystem`, variant `CPO_RemotePlayerVariant`, and sets its `debugCaption` to the nickname (its DLL calls `SetMappinDebugCaption`).
The game reads a script-set caption back through `IMappin.GetDisplayName()` (`CyberspaceMappinController` does), so `core/nightcoop.lua` lists the remote-player pins, takes their names, and pairs each with the peer NightCoop places within 2.5 m of it across the ground (made strict on 2026-10-29, above).
Names stay for the session, since a partner who leaves our world loses their pin.
A partner never seen in our world, or with NightCoop's player markers off, stays "Peer N".
If pins turn out to have no caption, the fallback is NightCoop's floating name tags: an ink layer `NightCoopPlayerMarkers` in the HUD with a `NightCoopPlayerMarker` per partner holding a name and a distance text, though nothing on them says which peer they belong to.

## 2026-10-28: The custom amount is the game's own quantity popup

The slider the game shows for dropping or selling a stack (`ItemQuantityPickerController`, widget `base\gameplay\gui\widgets\notifications\item_quantity_picker.inkwidget`) is opened with `ShowGameNotification` and a `QuantityPickerPopupData`, as the backpack does.
It's shown from `PopupsManager`, found on Codeware's `inkHUDLayer`, which shows the game's own in-world popups (the car color picker, the codex) with `isBlocking` and `useCursor`; the game's dialog widget controller is the fallback.
`TransferToPlayer` hides the price, and the popup's item name and button text are set to the partner and "Send" after its `SetData`.
The popup stays up while its notification token is held: the backpack takes it down by dropping the token in its close callback, so `core/quantity.lua` does the same.
CET Lua can't be a callback target, so the token's listener is a detached `gameNotificationsTest`, a sample class the game never uses whose `OnResponse` only clears its own field, and `core/quantity.lua` observes that `OnResponse`.

## 2026-10-28: "[F] Interact" is our own list on the game's dialog blackboard

The game's dialog widget draws whatever `DialogChoiceHubs` holds on the `UIInteractions` blackboard, and the player's state machine treats a non-empty list as a conversation (`AreChoiceHubsActive`), so the mouse wheel doesn't switch weapons while ours is up.
`core/choices.lua` writes the list, the active hub id and the selected index there, puts the list back if something clears it, and steps aside when the game writes a conversation of its own.
The game's interaction system doesn't know our list, so F and scrolling are read from `ChoiceApply`, `ChoiceScrollUp` and `ChoiceScrollDown`, which `Exploration` includes on foot.
The listener is a detached `ItemQuantityPickerController`, whose `OnAction` reacts only to `mouse_wheel`, so our actions run no game code.
`UI_MoveUp` and `UI_MoveDown` are also bound to W, S, Q and E, so only the wheel, the arrow keys and the d-pad scroll.
A pick is a tap of F of 0.35 s at most, because NightCoop helps a downed partner up on a held F.
The prompt shows when `TargetingSystem.GetLookAtObject` gives a body within 3 m that stands within 1.5 m of NightCoop's position for a peer, so a partner in another world, with no body here, gets no prompt.
NightCoop's dialog votes read the same blackboard and the dialog widget's active hub and selection; they're meant for scene choices, but that's unchecked.

## 2026-10-28: Money goes through NightCoop's own item transfer

`NightCoopGiveItem(record: String, quantity: Int32, peer: Int32) -> String` (signature read from NightCoop's `PostRegisterTypes`) offers items to a peer; the host accepts, the sender is debited, the recipient is credited, and both sides confirm, so an item can be lost but never duplicated.
Eddies are the item `Items.money`.
NightCoop refuses a quantity outside 1 to 9,999 and a transfer to ourselves, so larger amounts go as several transfers.
It checks each request against the balance but debits later, so several requests in a row could each pass; `tweaks/sendmoney/money.lua` checks the whole amount against the balance first.
A successful call answers "inventory: transfer 0x... requested for peer N".

## 2026-10-28: How NightCoop and the game are read

NightCoop is a closed-source RED4ext plugin with no API documentation.
Its script natives are registered in `PostRegisterTypes`, and `tools/re/ncre.py natives` reads their names and signatures from the disassembly ([docs/nightcoop-natives.txt](docs/nightcoop-natives.txt)); CET calls them as `Game.<Name>(...)`.
NightCoop also exports a C interface, `NightCoopAddonApi`, for one native addon at a time; it's undocumented and these tweaks don't need it.
For the game, REDmod ships the script sources of this exact version in `<game>\tools\redmod\scripts`, and NightCoop dumps every class, property and function into `rtti-names-*.txt` next to its DLL.
