# Record

What we found and decided while building Headset, newest entry first.
"User" marks what the user heard or saw in the game. Everything else came from logs, code or tests.
How the game's sound is built and what the probe showed is in `mods/nightcoop-voice/RECORD.md`, under 2026-11-08.

Installed: a 0.4.9 test build on the user's PC on 2026-11-10, with the commented-out tuning file, all 136 tests passing.
Played on 0.4.7 on 2026-11-09 (user): "I've been playing with it. it's good", and the two others have had no issues, one on Linux. All three logs show the effect on 29 of 29 places.
Heard and approved on 0.3.1 (user): shots in noise cancelling ("great"), driving with the radio in noise cancelling ("very good"), your own shots in clamping ("very good"), firing during a V line in both modes ("great"), and standing and walking somewhere quiet ("great").
Also heard: grenades and a close explosion ("good"), burning wrecks ("wrecks are good too"), and NPC gunfire at offset 136 ("good"). The user called the tuning good on 2026-11-08, with every live value then matching the source, `grunt_body_db=8` being the last to carry over.
Not yet checked in the game: the commented-out tuning file and moving old ones aside, which the log's `tuning: moved an old tuning file aside` line will show. 0.4.8's car radio and its thump on others' guns and blasts. 0.4.9's Wwise build check.

## 2026-11-10: The tuning file no longer holds old values

The user asked whether the crew gets the same behaviour. Not quite: Bleack's and Bossun's last logs show `recoil 6 dB`, the user's `recoil 12 dB`, though the source starts at 12. The mod wrote `tuning.ini` with that day's starting values the first time it ran, and every value in it overrides the source from then on, so a new start never reached anyone who already had the file. Their other values happened to match.
Now (user): the mod writes the file with every value commented out, its first line `# Headset tuning, format 2.`, so it changes nothing until a line is opened. A file without that line is renamed `tuning.old.ini` on the next start and logged, so everyone gets the source's values. The user's own file goes the same way, with nothing lost, since every value in it matched the source. Live tuning from here means taking the `#` off a line in the new file, which the game writes, so it's one Claude can edit (AppData redirect). Others' thump stays at +6 (user), 6 dB under your own gun's +12.

## 2026-11-09: Off on any Wwise but the one it was made for

For publishing on Nexus (user). The effect is called through positions read from 2.5's exe, so a patch that moves Wwise could crash. The bank we make is version 150, so a change of bank version already fails safely at `LoadBankMemoryCopy`; a smaller Wwise update wouldn't.
0.4.9 counts `mov dword ptr [rdx+4], 0x7E701` in the exe's code before touching Wwise, which is how each of the game's effects fills in its build number. 2.5 has nine; one more says `0x7E501`, so a stray can outlive an update, and it needs five or more. Below that it logs why and stays off. The count on the exe file is nine; the in-game line `Wwise build 7e701, on 9 of the game's effects` hasn't been seen yet.
Also in 0.4.9: your own gun's `recoil_db` starts at 12 (user), which is what the user had live while playing 0.4.7.

## 2026-11-08: A thump for other people's guns and for blasts

The user found that "when you aren't shooting, it feels like everything is muted". The logs on 0.4.7 agree: close NPC shots read 149-154 dB real and take the microphones down 37-40 dB, leaving only the cups' leak below 300 Hz at -10 dB, with nothing raising the lows as `Guns_Firing` has.
0.4.8 adds the same two-pole 120 Hz boost on `Gun_NPC_Fire`, `Gun_NPC_Fire_Important`, `Grenades_SP`, `Explosions_SP` and `Explosions`, from `thump_db` (start +6), in the detector already on each bus and after its reading, so it can't deepen the clamp. `places.hpp` says which bus gets which. Impacts, crashes and physics get none. Your own gun goes from +6 to +9 (user), live in the user's `tuning.ini` on 2026-11-08.

- Close NPC shots peak higher on their bus than the player's (+13 to +17 dB against +8), full-range peaks that don't say how much is low end. Whether they now overshadow your own gun, and whether big explosions distort, is for the ear.
- It only changes the bangs. In a sustained firefight the microphones recover over 900 ms (`kReleaseSlowMs`), so if the gaps still feel muted, that's next.

## 2026-11-08: A car's radio is part of the world

The user decided a car's radio should be processed "after all", since it comes from speakers in the cabin, but not a bike's. This reverses leaving it clean, which the user had called "very good" when driving in noise cancelling on 0.3.1. Both modes, by the user's choice: in hearing protection it reaches you through the microphones and ducks under a bang, in noise cancelling it loses what the world loses, so it's only fully clean in Passthrough.
The game gives each kind of vehicle its own radio aux bus under `Music_Diagetic_Radios_Vehicle_Player_INT` and `_EXT`, so nothing has to detect what you're in. 0.4.8 puts `ClampKind::Plain` in slot 3 of the twelve `Music_Dgtc_Car_*` buses (Hyper, Lowend, Muscle, Sports, Suv, Truck, each `_INT` and `_EXT`); the bank uses only slot 0 on them. `Music_Dgtc_Mbike_*` and `Music_Dgtc_Pocket_Radio` have nothing of ours. The metro's own radio bus was left out, since only cars were asked for.

- From the banks. Four probe recordings show a motorbike's radio at its full level on `Music_Dgtc_Mbike_EXT`, -6.1 dB there and on its parents, so a vehicle's radio does pass through its own aux bus. No car was caught.
- Effects haven't been put on an aux bus before in this mod. `SetBusEffect` answers for each one in the log if it refuses.
- Not traced: which bus a police car or other unnamed class uses.

## 2026-11-08: Passthrough stays Passthrough with the radio on

A radio left on used to bring hearing protection out of Passthrough. The user asked to remove that, so only the player's choice sets the mode now (and `always_worn` in `tuning.ini`). 0.4.8 drops `SetRadioLeftOn`, so the interface in `headset_api.h` is version 2 and needs NightCoop Voice 0.7.2; with an older voice, nearby voices play plain until both are updated.

## 2026-11-08: Story characters in person are part of the world

The user asked whether a voice on a call could be told from one in the world, such as talking to a character in a story moment. The game already sorts them. `vo_matrix`, the event the exe names, picks a bus by two switches, `VO_context` and `VO_expression`:

| Context and expression | Bus | Branch |
|---|---|---|
| Quest, spoken | `VO_Important_Occlusion`, under `VO_Quest` | `Effect_Bus/VO` |
| Quest, phone | `VO_Phone` | `Effect_Bus/VO` |
| any, `inner_dialog` | `VO_2D_Important` | `Effect_Bus/VO` |
| minor_activity, spoken | `VO_Important_SP` | `Effect_Bus_SP` |
| gameplay, spoken | `VO_Gameplay_SP` | `Effect_Bus_SP` |
| Community, spoken | `VO_Flavor_SP` | `Effect_Bus_SP` |

So story characters in person were never processed: the world effect is on `Effect_Bus_SP`, and they go down the other branch, as clean as a call. Their reverb was already processed, through `Reverbs_SP`.
0.4.7 puts `ClampKind::Plain` on `VO_Quest`, in slot 3, as on the other buses outside `Effect_Bus_SP`. The bank puts no effect on `VO_Quest`, and it covers `VO_Important`, `VO_Important_Occlusion`, `VO_Important_Boss`, `VO_Important_Somi_Holo` and `VO_News_Speakers`. In Noise Cancelling they lose what the world loses, about 18 dB in the mids and 28 in the highs, so story lines lean on subtitles; the user chose that over a lighter cut. It isn't a detector, so speech can't set off the clamp.

- From the banks only. Calls show on `VO_Phone` in the probe recordings, but none of the 13 larger ones caught anything on a `VO_Quest` bus, so the first story scene is what confirms it.
- `VO_Quest` never played in a recording, so its layout is unseen. `Effect_Bus/VO` and `VO_Phone` are 7.1 there, which the effect handles; it leaves a bus of over 8 channels alone.
- Left clean: 9 one-off events play directly on `Effect_Bus/VO` (Kurt at the stadium, `vo_q306_custom_tv` and others), which also carries V and calls.
- Which expression Johnny's lines use wasn't traced.

## 2026-11-08: Tap cycles, a HUD state, and the cybernetic legs

After playing with 0.4.3 (user). Installed as 0.4.4 to 0.4.6; the HUD at its final spot and size, and the final tap order, not yet seen.
- A tap now goes to the next mode instead of toggling (Passthrough, Noise Cancelling, Hearing Protection, round again: the user's order, in 0.4.5; 0.4.4 went the other way), so the last-mode memory is gone. The hold is 150 ms, was 250. The confirmation sounds moved round: Passthrough has the old Noise Cancelling one, Hearing Protection the old Passthrough one, Noise Cancelling the old Hearing Protection one. The wheel's circuit lines are gone (user).
- A small headphones icon and the mode's name sit on the HUD under the health bar, showing what the headset is really doing, so a radio left on reads Hearing Protection while Passthrough is chosen. Names are spelled out, since acronyms "might be cryptic to people" (user). Hidden in Passthrough from 0.4.6 (user), so it only appears when the headset is doing something. Also from 0.4.6 it's the size of Voice's rows (user): font 24, not in capitals, a 24 icon, at y 206 as one more row above them. On 0.4.4 it never appeared (user): it was placed in a popup's units, two to a screen pixel, but the HUD layer is about one to a pixel (the vehicle customizer's `Tool.reds` says so), which put it at y 1640, below the screen. 0.4.5 has it at half the size, at (70, 175), chosen from a sketch of the HUD (user): just above NightCoop Voice's display and lined up with it, and measured from the top like the health bar, so a taller screen doesn't move it. Above the phone hint was the first idea, but that hint sat at different heights in different screenshots.
- **Cybernetic legs came through unchanged (user).** Traced through the game's banks: `lcm_player_double_jump` plays on `Perks` and `lcm_dash` on its child `Perks_Dash`, and `Perks` had no effect of ours. It gets a Plain clamp in slot 3, free in `init.bnk`. Perk weapons' charges and shots are on it too and so get processed as well.
- **Not fixed: 21 events play straight on the `SFX` parent bus**, among them `w_cyb_fortified_ankles`, `w_cyb_superhero_landing`, `lcm_cyb_speedboost` and the `lcm_mvs_sliding_*` slides. A bus effect there would also process everything under `SFX` that's left out on purpose (UI, full-screen effects, Time_Dilation, Braindance), so those sounds stay unprocessed. What fixes them would be changing the banks, which isn't planned.

## 2026-11-08: The wheel in the game's own style

The first wheel in the game showed only its labels and centre circle (user's picture): the game draws nothing for an `inkShape` built with a runtime vertex list. The user asked for the game's look, with a pie of selectable slices and the game's blue outline on the one you point at. Mocked up three layouts; the user chose three equal slices. Installed as 0.4.1; not yet seen in the game.
- The game's wheel, read from `radial_wheel.inkwidget`: a full-screen black rectangle at 15%, Codeware's same red `vignette_1` on top, red ring art, and a blue pointer, with its blur and the "radialMenu" slow motion. We use the black layer, the vignette and its colours. Slices, ring and pointer are ours, because no game art is a pie slice.
- `tools/make_wheel_art.py` draws them white with alpha and packs `headset_wheel.archive`. One slice is drawn and turned 120 degrees for each mode. The texture starts from the game's wheel highlight, keeping its UI settings; WolvenKit's import turns streaming on, so the script turns it off.
- On 0.4.1 every part came out as a glowing square (user's picture), with the slice's shape visible inside. The game's UI blends a texture as premultiplied, so white at alpha 0 adds its tint where it should show nothing. The art's colour now fades with its alpha (0.4.2). That picture also showed the archive loads and that `SetRotation` turns clockwise: the lit slice was top left, where it belongs.
- On 0.4.2 the wheel drew and worked (user), and it was "kinda ugly/basic". Also from that test: choosing Noise Cancelling made no sound. Its cue, `ui_generic_set_14_positive`, is one the game only plays on a device, never through the audio system's `Play`, which is how the other two cues play; the source now uses `ui_hacking_access_granted`. The phone's corner of the HUD stayed visible; while the wheel is open its root's opacity goes to 0 and is put back as it was, with no game function replaced, so UI mods aren't touched. Both are in 0.4.3, not yet tried.
- A second pass from a mockup the user approved (installed as 0.4.3, not yet seen in the game): about 15% smaller, translucent slices with thin outlines, a blue glow rising to a thick rim on the lit slice instead of a flat fill, cut corners, circuit traces and a ticked ring, and waveform icons: a full wave, clipped peaks, and a wave dying to flat. The panel's copy was rewritten, with Surroundings and Gunfire lines like the game's item stats. Each slice's icon, name and Active tag are stacked and centred together on the slice's centre of area. Each line of a name is its own text, because the multi-line text left-aligned its lines in the game (user's picture). Opacities are a first guess: the game blends darker than the mockup.
- The first version's info panel was plain rectangles, without the chamfered corner in the mockup.
- **Stale picture behind the wheel** (user: look one way, open, close, turn round, open, and the blurred view is the earlier direction): the wheel turned blur off to keep the world visible. In the vehicle customizer's four setups the two that ask for blur stayed live and the two that don't froze, and its setup 2 froze with slow motion on, so blur rather than slow motion is the difference, though that mod's RECORD credits slow motion. The game's own wheel asks for blur too. The wheel now asks, and clearing on close comes back with it. Not yet seen to work.

## 2026-11-08: The key moves to `,`, and the settings stay on Native Settings

- The user asked for `,` in place of `.`. It's in none of the game's default bindings (`r6/config` has no `IK_Comma`). It also ends a clash on the user's PC, where Voice's Mute is saved on `.`, so one tap did both. Installed as 0.4.1.
- Moving to Mod Settings was looked at and dropped (user). Voice's device lists, per-player mutes, Refresh button and Hear yourself don't fit it, so Voice stays on Native Settings, and there's "no point asking people to install two different settings menu mods for two sibling mods".

## 2026-11-08: One key, a wheel, and the radio made sense of

The user pointed out that a player riding with ANC who uses push-to-talk mustn't have the headset removed each time, and asked for the headset and radio to be thought through as one. The radio is really two things: a quick transmission, and a radio left on. Only the second is what the headset's feel is meant to nudge. Worked out together; 0.4.0 builds it:
- No "not on your head" state (user): the modes are Passthrough, Active Hearing Protection and Active Noise Cancellation. Passthrough is a true bypass. It starts each session in Passthrough, remembering your last real mode.
- `.` is the key, free in the game's default bindings (user). A tap goes between Passthrough and the last real mode, on release, since until then it might be a hold; a game UI sound confirms which. Holding it opens a wheel like the game's own: Noise Cancellation top left, Hearing Protection top right, Passthrough the bottom half (user). The wheel takes over input while open, which the user accepted: "be sure it's safe before you check your phone".
- Radio: holding it to talk changes nothing. Left on while in Passthrough, it brings hearing protection until it's off. A mode you chose is never overridden, which settled the question of radio during noise cancelling.
- Changing mode fades one out and the next in. The effect goes on the buses at the start even in Passthrough, so the first tap acts at once.
- "Active Hearing Protection" is the menu's name for level-dependent hearing protection, the proper term (EN 352-4 and the studies), chosen to sit beside Active Noise Cancellation.
- The wheel is a Codeware popup in the queue the vehicle customizer settled on, blocking, with no cursor, reading the game's raw `mouse_x` and `mouse_y`, and without Codeware's half-second fade. It's drawn with `inkShape` vertex lists as thin triangles; nothing in this repo or Codeware has used those, so whether they draw at all is the first thing to look at. If up and down are reversed, `wheel_flip_y=1`.
- `src/headset_api.h` is what other mods get: voice tells it when the radio is left on and hands it nearby voices, which take the world's clamp, or noise cancelling's bands.

## 2026-11-08: NPC gunfire too quiet in clamping

The user wanted "a way to make NPC gunfire a bit louder". The log had close NPC shots at +5 to +10 dB, as loud as the player's own gun on its bus, which offset 148 turned into 153-158 real and the full -40 dB. They also have no recoil lows to carry them. Offset moved to 136, live and in the source: a close shot now comes down about 33 dB and a typical -20 dB one about 17 dB. Your own gun is unchanged.

## 2026-11-08: Feeling yourself breathe

On 0.3.1 the user liked grunts in noise cancelling and asked for them to feel more "inside - closer to self". Tried live: `grunt_body_db` from 5 to 8. The source adds `grunt_body_hz` (450, was the same 700 as V's lines), a darker skull path, movable while playing. Voice level alone may not be all of it: `VO_V_Onos` is a 2D bus and may be centred already, and any reverb the game sends V's sounds to doesn't pass through our effect.

The user also decided that in dynamic clamping grunts shouldn't be drowned out as V's lines are: "grunts don't stick out same as speech and they give an immersive feeling to the gunfight - like, all the chaos is suppressed but your can feel yourself breathe and it's a reminder of sorts". So `grunt_clamp_mask_db` is 0 in clamping; they still lose their air during a bang, and noise cancelling still drowns them out with V's lines.

In clamping, though, grunts at `grunt_open_db=-3` were "too 'clear'" (user), so that moved to -12, live and in the source.

## 2026-11-08: A gunshot drowns out V

The user: "a gunshot is probably drawning out everything, right? so V really shouldn't be able to hear himself/herself, even without clamping". Right: a shot far outweighs your own voice in your skull, with or without a headset. This replaces the rule that V is never pushed down during a bang. In 0.3.1 all of V's voice and breathing goes down by how loud the bang is, in both modes, on the clamp's own curve and timing, scaled so the loudest bang is -30 dB (`mask_db`); a typical NPC shot is about -18. Accepted cost: V's lines during a firefight are often lost, leaving subtitles. Off mode is untouched. Start strong and back off by ear.

## 2026-11-08: Gunshots should hit harder in noise cancelling

The user asked whether shots should be louder in ANC than in clamping, and agreed they should. Cancelling works on steady sound and can't keep up with something as sudden as a gunshot, and consumer cups block less than hearing protection (general knowledge of how it works, not measured). 0.3.0 treated a shot like traffic, so its low thump was weaker in ANC (-26 dB) than through the clamping cups (-10), which is backwards. 0.3.1 eases each band towards its level during a bang (lows -8, middle -12, highs -22), by how loud the bang is, on the clamp's own timing, on all the world's buses. The numbers are first guesses for tuning by ear.

## 2026-11-08: V's voice wants to go further

Live changes to `tuning.ini` work in the game: an edit was read one second after saving. On 0.3.0 the user found V "very easily understandable, I think we can make that effect stronger", that it "doesn't quite sell the ANC/clamping effect", and that grunts and such could be "a touch more pronounced". Moved live to `body_db=5` and `air_floor_db=-22`, which covers lines and grunts alike. At that, "the clean voice part of it is still too present - not quite like ANC". The user proposed going all the way first and bringing back just enough, so the air path went to -60 dB, leaving only the body path below 700 Hz, and that was "very good. understandable too" in noise cancelling. So nothing needed bringing back, and V's lines start at +5 and -60.

0.3.1 splits lines from grunts and breathing (`VO_V_Onos`), which also start at +5 and -60, as heard: "the grunts are good now too" (user). It also adds an open level, -5 dB for lines and -3 for grunts, because in dynamic clamping the air path used to be fully open whenever no bang was clamping it, so V sounded nearly untouched.

## 2026-11-08: 0.3.0, the rest of the sound, noise cancelling and V's body

Built in one go to test all at once (user), ahead of moving NightCoop Voice over.
- **The lift** was measured on the finished mix in the old headset; here each bus only knows itself, so every clamp bus publishes its power and all of them read the sum. It's a frame behind for some buses, which a 400 ms rise can't notice. Bus levels are before the bus volumes, so its -38 dB may want moving.
- **The hiss and the narrowing** happen once, on `Effect_Bus_SP`, the one stereo bus carrying the world. If that bus is idle there's no hiss, which should only be menus and loading. Your own gun and steps are on 7.1 buses and aren't narrowed.
- **Noise cancelling** is three bands on the same buses as the clamp (lows -26, middle -18, highs -28 dB), from what such headphones generally do, not measured; the three bands add back up exactly at 0 dB. No clamp, since there are no microphones to turn down. UI, the score and the car radio have no effect on them, so they stay clean.
- **V's body path**, on `VO_V` and `VO_V_Onos`: below 700 Hz is the body path, +3 dB; above is the air path, which follows the clamp in dynamic clamping and sits at its floor in noise cancelling, never below -12 dB so V's lines stay followable. V's breathing is on `VO_V_Onos`, traced from the `lcm_breathing` and `lcm_breathing_stamina` events through the banks. Your footsteps get +6 dB through the cups on `Locomotion_Player`, and keep their lows in noise cancelling.
- What radio should do during noise cancelling is still undecided (user); NightCoop Voice isn't connected yet anyway.

## 2026-11-08: 0.2.0, the microphones, the cups and the recoil

The first part of the sound stage, from `headset3` in NightCoop Voice: on each clamp bus and each channel, the microphones (120 Hz one-pole highpass, 7 kHz lowpass) turned down by the clamp, plus the cups' leak (two-pole 300 Hz, -10 dB) that nothing turns down. It's linear, so a leak on each bus adds up to the same leak on the whole mix. Still to come: the lift, the hiss and the narrowing.
- With the leak carrying the shot, `depth_per_db` goes back to 0.57, per the entry below.
- **Recoil**, the user's idea: "artificially added some low frequency to gunshots during clamping to maybe induce a feeling of vibration in the arms". Headphones can't shake arms, so it reads more in the head and chest. Your own shot's lows (two-pole 120 Hz, +6 dB) are raised on `Guns_Firing` while worn, after the detector reads it, so the loudness estimate doesn't include them. Made from the shot, so each gun feels different. Built early so it can be heard alongside the leak.
- `sound=0` in `tuning.ini` leaves only the clamp, to compare; `leak_db` and `recoil_db` move the rest.
- A bus with more than 8 channels gets only the clamp; none of the clamp buses has one on the user's setting.

## 2026-11-08: What a real headset does to your own gunshot

On 0.1.2 the user heard gunshots "definitely much louder now", and the unclamped first shot "seems gone". The log has the game finding its tuning file and your gun coming down 25.6 dB. The user asked what the real thing does.
- Published figures: firearms peak around 159-169 dB at the shooter (144 to 172 by weapon), standard earmuffs cut that peak by 20-38 dB, and the electronics hold their own microphone sound below about 82 dB in the ear.
- So under the cups a shot still peaks somewhere around 120-150 dB for a few milliseconds, far above what the electronics pass. What you hear of your own shot is what gets through the cups and your head; the microphones add almost nothing. No firsthand description of its timbre turned up. Earmuffs stop lows worst, so duller and thumpier is my reading.
- For the sound stage: the mic path should go nearly silent during a bang, which is deeper than today's 26 dB, while the cups' leak carries the shot. 0.57 sounded wrong because the leak was missing, so `depth_per_db` 0.35 is a stopgap to raise again once the leak is in, by ear.
- User reports call the release instant and very fast; no measured figure turned up.

## 2026-11-08: V's own body, planned

The user wants V's voice to feel processed when the ears are sealed: "you can't really hear yourself and what you can feels like it's coming from within your body", and it was the breathing that gave them the idea. That's the occlusion effect: a seal cuts the air path to your own voice but not the path through your skull. Agreed plan, to build after noise cancelling and before the crew test:
- V = a body path plus an air path. The body path is there while worn: warm lows, no highs, no room. The air path is what the outside mics give back, so it's open in dynamic clamping, ducks with the clamp, and is mostly gone in noise cancelling.
- The same body path goes on V's footsteps and breathing.
- V is no longer grouped with phone and Johnny, who stay untouched. V is still never clamped like the world.
- Keep some highs on V's lines, since they carry story, and tune by ear (user: "ok, let's see it").

## 2026-11-08: First time in the game, 0.1.0

The effect went on 25 of 25 places, and detectors read what the probe's meters had: `Guns_Firing` +8.0 dB.
- **Too strong** (user): "unsuppressed gunshots are almost inaudible." The log says why: your gun's +8 dB is 158 real, 73 over the threshold, which `depth_per_db` 0.57 took to the 40 dB limit, leaving it at -32 dB. The bullet hits that stayed audible on a car were the UI's hit markers, not world impacts (user), and UI is outside the headset by design. 0.1.1 starts at 0.35: the gun comes down about 26 dB, as the old radio headset's shots did. The cups' leak, which gave the old headset its thump, comes with the sound stage.
- **The first shot was loud** (user): "the first shot after enabling the clamping is loud, then it starts working". Wwise ends a bus's effect while the bus is quiet and makes a new one on the next sound (the log's alive counts swing between 0 and 6), and each new clamp faded in from nothing over 0.2 s. In 0.1.1 a new clamp starts already worn, and takes the detector frame that woke it but not older ones. Most likely the cause; not yet heard.
- **`v_destruction` clamped with nothing happening:** 6 to 10 dB for over a minute at a time, reading -16 to -25 dB, 95 to 104 real. Something sustained plays on that bus, probably burning or damaged vehicles. 0.1.1's offset is 108, so those stay under the threshold and a crash at +9 still reaches 117.
- **Live tuning didn't work, because the game couldn't see the file.** 0.1.1 logged "The system cannot find the path specified" for `%LOCALAPPDATA%\Headset\tuning.ini`. The Claude desktop app redirects new files it creates under `AppData\Local` into `AppData\Local\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Local`, and shows them to its own processes at the usual path. So Claude saw the file and even read it correctly in a throwaway program, while the game found nothing; NightCoop Voice's `tuning.ini` worked because it already existed. From 0.1.2 the plugin makes its own file from inside the game, with every setting and its explanation. A player's game does the same, so nothing else is needed for anyone else.

## 2026-11-08: The headset leaves NightCoop Voice

The user wanted the radio headset's clamp to stop catching chatter and to go further, and proposed a separate mod with three modes (off, dynamic clamping, noise cancelling) that proximity voice "uses", shipping alone if one Wwise effect can do what's needed. A test in NightCoop Voice 0.6.6 proved our own effect runs on the game's buses. This is the mod that came of it, without a framework: another mod's effect coexists if it uses other buses or slots, and the README lists ours.

The design as approved: a detector effect on each bus of bangs, a clamp effect on each bus the microphones would pick up. One threshold around 85 dB of estimated real-world loudness, depth up to 40 dB, today's instant attack and release. V, phone and Johnny stay outside the headset, as implant audio (user). What pressing radio during noise cancelling should do is undecided (user).

Built so far, in the design's order: clamp and trigger. Still to come: the mic band, leak, lift, hiss and narrowing; moving NightCoop Voice over; noise cancelling.

- **Why a bus's level, and not the finished mix:** the 15-minute probe showed 80% of the crossings of the old clamp level had no bang behind them, and loud speech is louder than a typical NPC shot, so only the bus can say which is which.
- **Timing:** a clamp above a detector runs after it in the same audio frame (measured for `SFX_SP` under `Effect_Bus_SP`, 4,003 of 4,003 frames, 0.00 to 0.16 ms apart). Each detector's audio frame is kept as one level per sample, and each clamp uses each detector frame once. So your own gun clamps `Weapons` on the very sample, and buses beside a detector at most one frame (11 ms) later.
- **Effect slots:** the highest one `init.bnk` leaves free on each bus. Slot 3 isn't free on `Explosions` (the game uses 2 and 3), `Explosions_SP` (3) or `Weapons_SP` (0 and 3), which is why not everything is in 3. The clamp isn't on `Weapons_SP`, since `Effect_Bus_SP` above it covers that.
- **Offsets are a first guess:** the loudest reading the probe saw on each bus, taken as that thing at its loudest in the real world: your gun about +8 dB at 158 dB real, NPC guns +7 at 155, grenades +4 at 165, explosions +4 at 168, bullet impacts -4 at 120, destruction +15 at 135, physics -6 at 110. Those readings came from bus meters; a detector reads inside an effect, which may be before the bus's volume. The log gives every detector's loudest reading to calibrate from.
- **The clamp doesn't follow the game's volume settings on purpose:** detectors sit below the buses that the volume sliders act on, so a player's Master 30 or 100 gives the same real-world estimate.
- `Guns_Firing_Mech`, the weapon's mechanical noise, and `Melee_*` don't trigger it for now.
