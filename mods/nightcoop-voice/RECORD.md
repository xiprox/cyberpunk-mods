# Record

What we found and decided while building NightCoop Voice, newest entry first.
[README.md](README.md) says what the mod does; this file says why it's that way.

"User" marks what the user heard or saw in the game. Everything else came from logs, code or tests, and says so where it matters.
Started on 2026-11-05 and filled in from the session transcripts, notes and logs. "My" means the assistant's explanation at the time, which the logs or the user may not have confirmed. Readings matched to a spot by time are marked "by timing", since the logs don't say where a player stood.

Installed: 0.6.3 on the user's PC on 2026-11-07, reaching the others through the log collector: the radio headset clamping at -14 dB, with live tuning keys and the radio always in both ears, on top of 0.5.0's Relay and 0.4.6's falloff choices, protocol 3, so it doesn't play with 0.4.x and everyone updates together. Its 336 tests pass with audio devices. The user's `headset_db` is back to 0. With `headset_db=6` (the clamp at -14 dB) the user said "I think this is good for now". So 0.6.3 builds it in for everyone: the clamp is at -14 dB and the lift stays at -38 dB, as heard; the user's `headset_db` goes back to 0 when it's installed. Its made-up test blast now peaks near -5 dB, as the recorded shots did. At -10 dB, from the old belief in a -10.5 dB ceiling, it was hardly clamped at -14. Installed the same day. 0.4.6 and 0.5.0 were never installed.
Not yet checked in the game: all of 0.6.0's radio headset. All of 0.5.0's Relay (its entry says what to look for). 0.4.6's falloff choices. 0.4.5 itself. Partners' reverb and echoes, last heard on 0.4.0. Their room, corners and doors by ear. On the user's own voice since the fixes: the open street, alley, mattress alcove, ramp recess, tunnel and soft materials. Whether voices at 10-30 m are too quiet. Whispering. Car muffling timing, and radio grit and level.

## 2026-11-14: Riders in one vehicle aren't on each other's radio

Riders in one vehicle hear each other clean, so a partner's radio on top of that only plays them twice. The 15 m cut already took a radio left on from afar, but not one switched on close by (`RadioKeep`), and not with the Headset on. The user's choice, in 0.8.1: in a vehicle you share, a switch-on close by no longer keeps a partner on the radio (`RadioCut`). Once you're apart, the keep works as before. The Headset mod on in either mode still keeps the radio: noise cancelling cuts the voice in the next seat hard and the clamp swallows a shout in car combat, so the radio is the intercom, as real crews use one. A bike shared with a passenger counts as one vehicle. It's each listener's own pair, so a third player outside still hears both riders on the radio. The log says `radio: <name> left to the air, as we share a vehicle` when the keep is overridden.

## 2026-11-11: Switching the radio on close by keeps it, and so does the headset

Playing 0.7.6, the user found the cut in the way when getting ready for a fight: within 15-25 m of each other, switching the radio on did nothing anyone could hear. Two changes in 0.7.7, both the user's:
- A switch-on means it. A partner who switches their radio on (a tap, or a hold, which switches it on) within 25 m of you stays on your radio until you've been more than 25 m apart for 30 s on end (`RadioKeep`): a dash across a fight doesn't end it, going separate ways does. So the cut is only for a radio left on from further off, and someone who walks up with it on taps it off and on. Each listener still decides for their own pair, so a third player far away is never touched. The 30 s was my addition, which the user accepted.
- The Headset mod on in either mode keeps the radio, not only noise cancelling (user): putting it on means you want the radio, and hearing protection's clamp swallows a shout beside you in a fight, where the radio is what gets through. Only Passthrough, or no Headset mod, cuts. It's each listener's own headset that counts.
- Turned down first: switching the talker's radio mic itself off once the whole crew is within 15 m, and back on past 25 m (my idea). It's one switch for everyone, so it could only act with everyone close, and the radio gets forgotten mostly when someone isn't.
- Partners learned the radio's state only from the once-a-second presence, so an off and on could fall between two and never be seen. The first byte of the presence now also counts switch-ons in its top five bits, wrapping at 32, and every switch sends a presence at once. Builds before 0.7.7 test only the bits they know and ignore the count, so the protocol number stays; from such a build a switch-on is never seen and the cut works as in 0.7.6. The first count heard from a partner is only a start, so a late joiner doesn't take an earlier switch-on as one made close by.
- The log has `radio: <name> switched their radio on close by, so stays on it` and `has been apart long enough to be left to the air again`, besides the cut's own lines.

## 2026-11-10: The radio cut goes by distance alone

On 0.7.3 and 0.7.4 the user found the radio "goes on and off within building spaces in ways that are unpredictable and hard to understand". The log agrees: 226 switches in about 70 minutes on the user's PC, 55 of them within 2 s of that partner's last. Two causes:
- 104 came under 22 m, from the room test: readings sitting at its 0.35 line (0.33 to 0.37), and at 9 m with walls at 0.99 a way round found and lost again, switching every 2-4 s through the 0.7 s hold. A yes or no drawn from readings that wobble flips, and nothing in the sound says why.
- 122 came at the range edge, 22 m and beyond: inside buildings, floors and stairs moved players back and forth across it, and 3 m wasn't enough to come back.

0.7.5, the user's choice: distance only. A partner's radio is cut within 15 m and comes back past 25 m. Walls and rooms don't count, so someone close in the next room is heard muffled or barely at all. Separate vehicles and noise cancelling still keep the radio. The room test (`InAnotherRoom`) and the way-round search while a partner is quiet are gone. The other choice was to fade the radio in as a partner's nearby voice gets harder to hear, which never flips but plays both at once at middle distances; it's for later if distance alone still feels wrong. Not cutting the talker's mic, which would also cut off a third player further away.

## 2026-11-09: A close partner isn't on the radio too

The user's idea: stop hearing someone twice, in the air and on the radio, when they're close. 0.7.3 stops playing a partner's radio on your own PC while they're within 25 m, the user's choice after 10, 20 and 30 (25 from 0.7.4; 0.7.3 was built with 30). It's only that partner and only your game, so their mic stays on for anyone further away. It needs no protocol change, and each player works it out for themselves. `radio_near_m` in `tuning.ini` moves the range live; 0 is off. At 25 m a voice is already about -14 dB, so someone at the edge can be faint; the user accepted that.

- Decided with the user: a wall doesn't bring the radio back ("the wall effect is cool"), so someone behind one is heard muffled, but another room does, since they'd barely be heard at all. Another room is at least 0.35 occlusion (three of the five lines through a thin wall) with no way round, or one with 4 or more bends, a closed door, or longer than 1.5 times the straight line plus 4 m (`InAnotherRoom`), from that day's readings: 9 m at 0.64 with an 8 m way round at gain 0.25 is a wall, 13 m at 0.65 with 28 m and 7 bends at 0.08 is a room. A reading has to hold for 0.7 s to change it. The way round is now also looked for every 2 s while a partner is quiet and within radio range, as it was only searched while talking and the answer has to be there for the first word. If one of you is on or in a vehicle you aren't sharing, the radio stays, a bike included, so passing each other doesn't switch it on and off. The same vehicle counts as close. Noise cancelling keeps the radio at any distance, since it cuts nearby voices hard and the radio is how you'd talk to someone beside you. Hearing protection and Passthrough cut it.
- It comes back 3 m past the range and fades over about a quarter of a second, and only applies while their position is fresh. The display shows them as nearby, not on the radio, while it's cut.
- `SetPeerSpatial` gained an `apart` argument, since cabin 0 can't tell a bike from being on foot. Natives and scripts ship together.
- The log has `radio: <name> left to the air at N m` and `back on the radio`.

## 2026-11-09: A softer bend for distance

Testing 0.7.2 with Bleack, the user found 40 m faint, as it should be, but 15 m "closer to faint than it is to being next to them, which isn't very logical". The numbers agree: -13.5 dB at 15 m and -20.6 at 40, which by the usual 10 dB for half as loud is about 39% and 24% as loud as someone beside you. That session's log had a nearby gain near 0.2 at 15 m and 0.1 at 40. A curve of 6 dB per doubling is right for sound level but spends most of its drop in the first few metres, and a levelled mic has none of what makes real distance feel gentler: reflections, people raising their voices, the brain's compensation.
From four shapes that all keep 40 m as it was, the user picked the softer bend over the straight line my recommendation had been. 0.7.3: `-20.6 dB * ((distance - 2) / 38) ^ 0.8`, so -2.7 at 5 m, -5.9 at 10, -8.7 at 15, -11.3 at 20, -16.1 at 30, -20.6 at 40, then the fade from 40 to 50. Past 40 m the bend carries on, about 1.3 dB under the chart's line at 45 m, in the fade. It covers voices, room sound and echoes as before; the darkening with distance and the radio are unchanged.
`falloff_bend` in `tuning.ini` moves it live (1 is a straight line in dB, lower drops sooner). No protocol change. A side effect in a closed room: the room's sound still falls about a third as fast as the voice, but with the voice falling less, it stands out less from it at 15 m (about 6 dB less drop than the voice, was about 9.5).

## 2026-11-08: The 85% falloff for everyone

The user picked 85% after the 0.4.6 comparison, for voices "a bit easier to hear" at medium distances. Built in as 0.7.2 (`kRolloffShare`), and the test choice's code is gone: `falloff_test` in `settings.ini` is ignored and the log no longer has `falloff:` lines.
A voice, its room sound and its echoes now lose 85% of the old curve's dB, about 5 dB per doubling instead of 6. In dB: -5.8 at 5 m, -10.6 at 10, -15.5 at 20, -18.5 at 30, -20.6 at 40, then the fade to silence at 50. The radio is unchanged. It only changes what each player hears, so no protocol change.

## 2026-11-08: The radio no longer puts the headset on

Removed at the user's request, with its switch under Hearing: you can now stay in Passthrough with the radio on. 0.7.2 no longer tells Headset about the radio, so its link only hands over nearby voices. `headset_solo` goes too, since all it did was let the radio key try this with no session; a leftover line in `tuning.ini` or `headset` in `settings.ini` is ignored.
Headset's interface is version 2 without that call (its 0.4.8), and neither side accepts the other's old version. A mismatched pair doesn't crash: voice logs that it can't use the mod and nearby voices play plain, so 0.7.2 and 0.4.8 go out together.

## 2026-11-08: Voices now carry to 50 m

The user asked to move silence from 40 m to 50 m. The curve wasn't what cut voices off: from 40 to 50 m it only loses another 2 dB, while the fade started at 30 m and had them silent by 40.
0.7.1 keeps a 10 m fade but runs it from 40 to 50 m, so at 35 m a voice is -23.1 dB instead of -29.1, and at 45 m -31.2 instead of silent. Nothing under 30 m changes in level.
- The limit also decides who gets sent a voice, and `kFarMeters` in `acoustics.cpp` limits the rays and ways round, so `SpatialInput::farMeters` and it move together.
- The darkening with distance used to stretch between 2 m and the far limit. It now has its own 40 m (`kDullestAtMeters`), so voices sound the same as before under 40 m and get no duller past it.
- The falloff test's taper still ends at 40 m, now where the fade begins.
- Packets mean the same, so no protocol change. But until everyone has 0.7.1, a player on 0.7.0 cuts a voice off at 40 m: a talker on 0.7.0 stops sending there, which a listener on 0.7.1 hears as a drop from about -24 dB, and a listener on 0.7.0 hears nothing from 40 to 50 m.
- Not measured: the small extra cost of rays and ways round out to 50 m.
- The "Distance falloff (test)" choice is hidden from Settings (user), so everyone is on today's curve. The code behind it stays, read from `falloff_test` in `settings.ini`, and a value saved earlier still applies with no menu to change it. The user tried 85% and 70% for a few minutes on 2026-11-08 and went back to 100% (log); no verdict was given.

## 2026-11-08: Settings stay on Native Settings

Moving to Mod Settings was looked at and dropped (user). It declares its options when scripts compile and has no buttons, so the Microphone and Output lists, per-player mutes, Refresh devices and Hear yourself don't fit. Saved keys and levels would also have needed importing, and every change would wait for its Apply button. Headset stays on Native Settings too, so players need only one settings mod.

## 2026-11-08: 0.7.0, the headset moves to its own mod

The world's sound is now `mods/headset`'s, which works inside Wwise (its RECORD.md). Voice keeps two connections through `src/audio/headset_link.cpp`: it says when the radio is left on, and hands over nearby voices. Without the mod, or if it's broken by a patch, voice plays plain. No protocol change, since this is local to each player. Built, 318 tests pass without audio devices; not installed.
- Gone from voice: the Windows hook on the game's sound, its copy of the headset, the Wwise probe and effect test (their findings are in the entry below), and the headset tuning keys. `headset_solo` stays, to try the radio key with no session.
- "Radio headset" (Off, On, On without clamping) became a switch, "Leaving the radio on puts the headset on". Holding the key to talk doesn't, so a push-to-talk never changes what you hear. Old settings still mean what they did: "0" off, anything else on.

## 2026-11-08: What the buses showed, and our own Wwise effect, to try

The probe's 15 minutes of play (`experiments/wwise-probe-2026-11-08_10-37-53*`, out of git; the headset was off, and the probe reads ahead of it anyway):
- **Most of what crosses the clamp level isn't a bang.** The finished mix was over -14 dB in 38.1% of buffers. In 80% of those no gunfire, explosion, grenade, impact or destruction bus was sounding even at -30 dB; it was the player's engine, the bike radio, traffic and reverb. In 2,088 of them (about 23 s) a voice was louder than every bang, which is the chatter the user complained of. Listening only to those bang buses would fire 4-8% of the time, depending on the level.
- **Level alone can't tell a bang from speech.** Typical peak, then loudest: NPC gunfire -20.8 and +7.2 dB, the player's -6.2 and +8.0, destruction -44.8 and +15.1 (the loudest thing in the run); `VO_Flavor_SP` -34.3 and +0.1, `VO_Gameplay_SP` -24.3 and -5.2. Loud speech is louder than a typical shot, so the bus has to say which is which.
- **Buses show what the game's limiter hides.** An NPC shot read +6.3 dB on its bus and reached the finished mix at -3.7. Some children read louder than their parents, so readings don't compare across buses without an offset per kind of sound.
- **No head start.** A bus's reading comes a median 0.10 ms before the next finished buffer, buffers about every 10 ms. Clean shots land in that very buffer, but of 27 bangs starting from silence 12 did, 5 were a buffer early, 4 a buffer late and 6 never moved the mix by 3 dB. Only 96 of 669 buses sounded in this run.

The user's plan, design still to come: the headset becomes its own mod with three modes (off, dynamic clamping, noise cancelling), usable in singleplayer, and proximity voice "uses" it. No framework, if one Wwise effect can do what's needed.

0.6.6 tries that effect, off unless `wwise_fx_db=-20` is in `tuning.ini`. Installed 2026-11-08 with that line in the user's `tuning.ini` and run in the game the same day.
- It registers a plug-in, loads a small bank of ours and puts the effect in slot 0 of `Effect_Bus_SP` (all world sound) at that gain, read live; 0 passes the sound through. A second copy on its child `SFX_SP` changes nothing and times which runs first, since the design would like a detector on a child to run ahead of the clamp on its parent. `SetBusEffect` takes a share set ID, which is why the bank is needed. `wwise fx:` lines every 10 s say what happened.
- There's no Wwise SDK on this PC. The order of the functions is from Audiokinetic's reference and the rest was read from the game's own effects in the exe, whose `GetPluginInfo` functions all write the build number `0x7E701`: effect slots 0 destructor, 1 Term, 2 Reset, 3 GetPluginInfo, 4-5 media relocation, 6 Init, 7 Execute, 8 TimeSkip (answers 45, `AK_DataReady`); parameter slots 0 destructor, 1 SetParam, 2 Clone, 3 Init, 4 Term, 5 SetParamsBlock. `AkAudioBuffer`: data 0, channel config 8, state 12, max frames 16, valid frames 18, channels end to end. Audio format: rate 0, channel config 4. Plug-in IDs are `plugin << 16 | company << 4 | 3`; the banks use companies 0 and CDPR's 666, and ours is 200.
- A share set in bank 150 is object kind 16: ID, plug-in ID, parameter size, parameters, then 7 zero bytes. Each bus in `init.bnk` holds its effect count after the ducking list, and both target buses have none.
- `init.bnk` shows layouts aren't all stereo: `Effect_Bus` is 7.1 (`0063F108`), `Reverbs_SP` 5.1 (`0060F106`), `Ambiences_SP` 36-channel ambisonic (`00000224`), and `Effect_Bus_SP` inherits. The probe now writes the layout each bus reports (`#layout` lines, summed up by the report).
- Our plug-in's code stays loaded until the game closes, because Wwise can call it after our plugin is told to unload. Nothing in it uses Wwise's allocator.
- **It works** (user, after switching between -20 and 0 live: "works"). In the log: `RegisterPlugin`, `LoadBankMemoryCopy` and both `SetBusEffect` calls answered 1 at 11:32:51, in the menus. Nothing ran until the save loaded about 40 s later, when one copy came alive on each bus, so the effect outlasted that load. Peak in and out were -13.5/-33.5, -10.0/-30.0 and -11.1/-31.1 dB at -20, and -7.4/-7.4 at 0.
- **A child runs just before its parent, in the same frame:** `SFX_SP` started 0.00 to 0.16 ms before `Effect_Bus_SP` in 4,003 of 4,003 frames, with frames 10.7 ms apart (512 at 48 kHz). So a detector on a bang bus sees the samples before a clamp on its parent runs, for this pair at least.
- Both buses were stereo at the effect here (`00003102`), on the user's 3D-headphones setting; other speaker settings may differ.
- Layouts the buses reported on the user's setting (`experiments/wwise-probe-2026-11-08_11-32-51*`; 45 buses reported one): 19 stereo, among them `Master Audio Bus` and `Effect_Bus_SP`; 17 at 7.1, among them `Effect_Bus` and the player's gun buses; 6 at 5.1, the reverbs; `Ambiences_SP` and its adverts child 36-channel ambisonic. So an effect has to take any channel count.
- The "Dynamic range" setting: `dynamic_preset` takes values 0 to 7 and has 30 curves on 28 buses in `init.bnk`, all on what looks like bus volume, in steps that read as 1, 1.5, 2, 3 and 4 dB if the stored numbers are Wwise's linearized dB. So up to about ±4 dB per bus and per preset: `v_destruction` up to +4 dB, NPC weapons up to +2, ambience down to -4. Which of the seven menu names is which number isn't in the bank.
- The only Mastering Suite in `init.bnk` sits on the system audio device, the likely home of the game's limiter (`Master Audio Bus` reached +9 dB, the finished mix -0.0). `dynamic_preset` doesn't touch it in the bank. Effects on buses run ahead of it.
- 0.6.7 adds to the probe a `#preset` line whenever `dynamic_preset` changes, read once a second through `Query::GetRTPCValue`, and a line in the log. The report then gives each stretch of the run its levels and any layouts that changed. Installed 2026-11-08 with `wwise_fx_db=0`, so the effect is in place but changes nothing, and run that day (`experiments/wwise-probe-2026-11-08_11-52-43*`):
  - The user went through the seven choices in the game. The number changed the moment each was picked: 6 at the start (the saved 3D Audio Headphones), then 0 to 6 in the order they were tried, so 0 Home Cinema, 1 Headphones, 2 TV Speakers, 3 Small Speakers, 4 Boost Low, 5 Boost High, 6 3D Audio Headphones, if they were tried in the order listed for them. 7 was never seen.
  - **Layouts didn't change.** None of the 71 buses that reported one changed in any choice, and `Effect_Bus_SP` stayed stereo at the effect. This was switching live, without a restart. New this run: `V_Motorbikes_SP` is 3 channels, `Bullet_Impacts` 5.1, `Gun_NPC_Fire` stereo.
  - **The limiter never went away.** The finished mix peaked between -2.9 and -0.0 dB under every choice, while the player's gun read +7.5 to +9.0 on `Guns_Firing`. Sometimes the finished mix read above `Master Audio Bus` (-0.0 against -5.3 on 1), so something after that meter or beside it adds level; not worked out.
  - **The meters seem to include the choice's volume.** `Guns_Firing`'s loudest was 8.0 to 8.1 on 0, 1, 3, 4 and 5, 7.5 on the last 6, and 9.0 on 2, the one choice whose curve gives it +1 dB. One clean case with about half a dB of spread, so suggestive. A detector inside an effect may read before that volume instead; to be checked when calibrating.
  - The effect came through every switch with its layout unchanged. It went away during loads and menus (Wwise ended it) and came back by itself. Three switches left `SFX_SP` and its parent short of frames for under a second.
- Still unknown: whether it lasts through fast travel and long play, Bleack's Proton, and whether a restart on another choice gives different layouts.

## 2026-11-08: Inside Wwise, what's reachable

The user asked whether going inside Wwise could take the headset further, since the clamp still catches NPC speech: "I want to leave it open". Read from the game's files; nothing has been called or heard yet.
- **The exe exports the Wwise API by name**, 499 functions with their full decorated signatures, so `GetProcAddress` on `Cyberpunk2077.exe` reaches them. Among them `Query::GetRTPCValue`, `RegisterBusMeteringCallback`, `RegisterBusVolumeCallback`, `RegisterCaptureCallback`, `RegisterGlobalCallback`, `RegisterPlugin`, `RegisterPluginDLL`, `SetBusEffect`, `SetOutputDeviceEffect`, `LoadBankMemoryCopy`, `PostEvent`, `SetRTPCValue`, `GetIDFromString`, `IsInitialized`, `StartOutputCapture`. I had said this would need disassembly; that was wrong.
- **`init.bnk` holds 401 buses** (bank version 150, so the wiki's "Wwise 2019" looks out of date), and nearly all their names can be recovered by FNV-1 hashing words from the exe and the event list. They split finely: `Guns_Firing`, `Gun_NPC_Fire`, `Explosions`, `Expl_Large`, `Grenades_SP`, `Bullet_Flybys`, `VO_Gameplay_SP`, `VO_Flavor_SP`, `VO_V`, `VO_Phone`, `ambiences`, `Music_Diagetic_Radios_Vehicle_Player_INT`, `Ui`, `UI_HitMarker`, `Music_Systemic_Combat`, `Explosion_tinitus`.
- **The game already meters its own buses**: 57 Meter effects write game parameters such as `rms_loudness_guns_player_firing`, `rms_loudness_guns_NPC_firing`, `rms_loudness_explosions_default`, `rms_loudness_VO_Gameplay`, `rms_loudness_ambiances`, `rms_loudness_vehicle_player_radio`, on a -48..0 dB range, mostly with 0 ms attack and 100 ms release.
- `volume_sfx`, `volume_dialogue`, `volume_music`, `volume_music_car_radio` and `volume_master` are game parameters that buses respond to, and `dynamic_preset` drives 28 buses. The event list has 23,634 events, with 508 gun-fire names such as `w_gun_osprey_fire`.
- The exe's build paths say the game's Wwise is 2023.1.19, so the wiki's "2019" is out of date. Audiokinetic's reference for that version gives `AkBusMeteringCallbackInfo` and `AkMetering`.
- The user settled what the clamp is for: chatter must not set it off, but an explosion during chatter should clamp the chatter too, as a real headset would. They want the clamp's depth to follow estimated real-world loudness, and to work out first what belongs in the headset and what doesn't, such as UI out and ambience in. The car radio stays out of the clamp: "for practical reasons. one could also say they play in your implants too" (user). Vehicle crashes and heavy impacts should set it off too (user).
- 0.6.5 adds a probe, off unless `wwise_probe=1` is in `tuning.ini`: `RegisterBusMeteringCallback` on all 669 buses and aux buses (`src/audio/wwise_buses.inc`, generated from `init.bnk`), peak and RMS per audio frame into `%LOCALAPPDATA%\NightCoopVoice\wwise-probe-*.csv`, with the finished mix's level alongside. It changes no sound. `tools/wwise_probe_report.py` reads the file. Installed 2026-11-08, not yet run in the game.
- Not yet known: whether a bus's level arrives before that buffer reaches the output, and whether buses without a Meter can be read. The probe answers both.
To extract again: `WolvenKit.CLI unbundle` on `audio_1_general.archive` and `audio_2_soundbanks.archive` with `-r "\.bnk$|eventsmetadata"`, then `convert serialize` on `eventsmetadata.json`, which is a CR2W file.

## 2026-11-07: 0.6.0, the radio headset in the game

headset3 as heard on the recordings, built into the mod. The design was approved with Off, Gentle and Firm, then: "we just need off and on (gentle). we can drop firm" (user). So Settings, Hearing, Radio headset is a switch, on by default, clamping at -20 dB of the game's samples at its Master volume 100.
- It's worn while the radio mic is on and the switch is on. It eases on and off over 0.2 s, and once off the game's sound passes exactly as it was, which a test checks sample for sample.
- How it reaches the game's sound: at the plugin's load the mod opens a throwaway stream, finds Windows' shared function tables for audio clients and their render clients, and patches Initialize, InitializeSharedAudioStream (IAudioClient3), GetService, GetBuffer and ReleaseBuffer. Streams set up after that are known with their format, and each buffer handed back in ReleaseBuffer goes through the headset in place, on the game's own audio thread. It's left alone if the stream wasn't seen being set up, isn't 32-bit float, is a loopback, or is the mod's own (marked while the mod sets up its streams). The game loads no XAudio2 or DirectSound, so its engine, built into the exe, should come through this way; Audioware's streams count as the game's. Only streams set up by the game's exe drive what voices follow.
- The clamp level, the lift and the hiss move with the game's Master volume, as the voice levels already assume (30 is 10.5 dB lower). A test checks that a blast 10.5 dB quieter at Master 30 is clamped as hard.
- Nearby voices, their rooms and your own voice in the room go through it: the same thinner sound, the cups' leak and the narrowing, turned down as the game's sound is at that moment, but not lifted, since a voice nearby is far louder than the quiet sounds the talk-through lifts. The radio now mixes apart from them and plays inside it.
- Logs: a `headset:` line for each stream set up (who made it, its format, whether the headset runs on it), `headset: on` and `off`, and every 30 s how much of the game's sound it was worn for, how far it turned down, breaths, and its cost.
- Trying it alone: `headset_solo=1` in `tuning.ini` lets the radio key put it on with no session. Temporary, like the rest of that file; the user's PC has it.
- In the game it went in before the game set up its sound: the game's own stream was stereo, 48 kHz, 32-bit float, from Cyberpunk2077.exe. "Works well. maybe we'll need an even gentler version (or tune this one)" (user). So `tuning.ini` also takes `headset_db` (added to the clamp level), `headset_steep` (dB down per dB over, 3), `headset_deepest_db` (40) and `headset_hiss_db` (added to the hiss), read within a second, in 0.6.1, installed on 2026-11-07 (a test checks that 6 dB up and 2 dB per dB turns a blast down 20 dB less). The lift stays where it was tuned when the clamp level moves. Once settled, build the values in and remove the keys with the rest of that file.
- An existing test, the far ear hearing a talker 0.65 ms later, failed on one run in two: it slid the ears against each other over a 1 kHz tone, which repeats every 48 samples, and sometimes took 35 - 48 = -13. It now searches only later lags under one period.
- "Even in the absence of loud noises, (moderate-loud) NPC speech gets the clamping treatment" (user), recorded with an enemy talking at a moderate distance. In that recording the speech peaks at -19 to -22 dB, right at the -20 dB clamp level. The model turned its loudest syllables down by up to 7 dB (1.3% of the time), while the lift raised its quieter parts about 2 dB, so speech came out flattened. With the clamp at -14 dB (`headset_db=6`) the speech isn't touched, and the shots in the same recording are still turned down 27 dB at most. The shots peak at -4 to -6 dB, so the -10.5 dB ceiling in the first recordings was those sounds, not a limit the game always applies.
- The game has a "Dynamic range" setting, `/audio/dynamicrange` `SpeakerSetup`: HomeCinema, Headphones, TVSpeakers, SmallSpeakers, BoostLow, BoostHigh, 3DAudioHeadphones (the user's). The user asked whether the game's own peak limiting could be turned off while the radio is on. The mod only sees the finished mix, so the only lever is that setting. Switching it would also drop the user's 3D audio, and it's a saved setting that a crash could leave switched. Not pursued; tuning first.
- 0.6.4: Radio headset is now Off, On without clamping, or On (user). Without clamping, the lift, the thinner sound, the narrowing, the hiss and the cups' leak stay, so a radio left on still feels slightly off, but nothing loud is turned down, for the game or for nearby voices, and blasts can drown the radio again. Stored as "0", "2" and "1", so the old switch's values keep their meaning. Installed the same day; 337 tests pass with audio devices.
- Radio earpiece is gone, and the radio always plays in both ears: "we need to remove left/right options for the headset, since the clamping applies to both sides" (user). The one-ear leak around the head went with it. Saved `radio_ear` values are ignored. In 0.6.2.
Not yet checked in the game: whether the mod loads before the game sets up its sound (the first `headset:` lines say), the game's real format, the cost, Bleack's Linux, and how it feels in play.
The user asked about clamping by frequency. The model to try has two paths. The hear-through microphones' sound is limited and loses some top end. The ear cups' passive leak is never clamped, but cuts highs far more than lows, roughly 30-40 dB against 15-20 dB (typical figures, not measured). In a blast the electronic path shuts down and what's left is a muffled low thump through the cups. It needs the game's samples, so the Windows volume route couldn't do it either way.

## 2026-11-07: 0.5.0, the Relay as built

Built to the design below, as 0.5.0 with protocol 3, so it doesn't play with 0.4.x. What building it added or found, from code and `voice_test`, none of it heard in a game yet:
- A partner's path is direct while the link is connected and has had a direct packet within 8 s (`kSilentLinkMs`, which now counts direct packets only), else the Relay. So a link that went silent on the answering side, which it keeps while asking for a new one, no longer counts as up, and its voice moves to the Relay.
- A switch can't play a frame twice: each frame goes by one path, and a frame whose sequence number was taken in the last 10 s is dropped, whichever path brings it. In the switching test A made 279 frames, and B took 151 direct and 128 over the Relay, none twice.
- Loads, my addition to the design: only the game thread can send, so a frame that waited there over 250 ms is dropped rather than sent late. Each message also starts with its send time, and the receiver drops frames over 500 ms later than the quickest message of the last few seconds. Otherwise a backlog delivered all at once after a load would start someone's sentence seconds late. Whether NightCoop delivers such a backlog at all is unknown.
- Notes: "Voice with Bleack on Relay" once the Relay gets their voice through, at once on Always, otherwise after 3 s without direct, so the half second a direct link takes at a session's start doesn't bring the note every time. "No direct link to Bleack yet" doesn't show while the Relay works.
- The answering side logged "link timed out" or "went silent" every 100 ms while it waited, and after asking to reconnect it took its own silent link for a new one, so it noted "Voice linked with B" again every 8-10 s (xip's log, 2026-11-06 22:44). Now it logs once per ask, every 10 s, and notes a loss once.
- Leaving Always: the first offer can arrive before the presence saying so. The offer is taken as the sign, and an older presence's Always bit is ignored for 3 s.
- Rate, in the test with its made-up speech: five partners at three frames a message took 85-90 messages and 17-25 KB in the busiest second. At 32 kbit/s that's roughly 5-6 KB a second per partner on either packing, so past about five partners at once it's the 32 KB, not the 120 messages, that runs out, by my estimate. A fake limit of 15 messages a second got refusals, then four frames a message and no more refusals.
- `relay:` lines every 30 s per partner: messages and frames sent, NightCoop's refusals by kind, frames dropped as too old, frames heard by each path, dropped late or twice, and the ping.

To check in a session: the Relay's delay between the user and Bleack by way of Bossun, what loading screens do to it, NightCoop's rate handling (`relay:` and `sdk:` lines, `NightCoopSdkStatus()` in the CET console), whether a host relaying guests' messages counts against its own rate, the HUD's Relay rows and the mic line saying LIVE, the notes, the Settings entry, and a whole session on Always.

## 2026-11-07: The radio drowned in loud moments; clamping like a headset, to try

"In loud moments, it can get somewhat drowned out" (user), who felt "a headset literally inside your ear would always feel loud enough". Voices rise with the game's loudness only up to +12 dB (`kMaxGainDb`), so gunfire can still win, and the radio hits the same limit.
The user also suggested turning the game down in the radio ear while your radio is on, which would also make leaving it on feel odd. Then they asked whether that's realistic, since an operative needs to hear their surroundings, and it isn't. A tactical headset covers both ears but plays the surroundings back through outside microphones, and clamps gunfire and explosions to a safe level within about a millisecond, with the radio on top. Blocking one ear fits a plain earbud, not that.
Proposed, not built: the radio keeps rising by up to 3 or 6 dB once voices hit their limit, as a test choice.
Clamping through the Windows volume of the game's sound was rejected. By my estimate, not measured, it would act 20-30 ms late, since loopback, the audio thread and Windows' mixing each take about 10 ms. So the start of every bang would get through, and it would pump everything down together.
The way to do it for real is to take the game's sound inside its own process, as the game hands it to Windows, and limit it there with no delay. The game loads no XAudio2 or DirectSound, so its sound goes through the same Windows audio interface the mod uses. That means hooking the game's sound output, a new kind of risk for this mod, untested on Linux. With the radio always heard, the clamp would always be on in co-op, and voice levels would need retuning around it.
"Definitely worth experimenting with clamping... If it feels good to use, could be worth hooking into the games sound output" (user), planned for the next day. First step, agreed: record a firefight through the loopback the mod already has, and clamp it outside the game into before-and-after clips, before any hook. Built on 2026-11-07 as `tools/record_game` (Page Up with beeps, which the user asked for) and `tools/headset_clamp`. The clamp's first try eased in over 1 ms and let each bang's first millisecond through at full level, so it now clamps on the sample a peak arrives. On a made-up firefight its peaks stop at the threshold, 15 dB over the recording's typical level.
The user recorded four clips: a quiet street with distant gunshots, a gunfight with grenades and shots into a car, an O-Five into the air and then at the ground (dying), and three O-Five shots into a wall and a reload. The game's own loudest peaks stop at -10.5 dB in three of them, so the game already limits itself. All are clamped at one fixed level for all four, -26 dB (firm) or -20 dB (gentle), taken from the quiet street.
- The first headset model: "a hard time detecting a difference between model and limiter" (user). Measured, it was as loud as the limiter in a blast and a little brighter. A limiter turns all pitches down alike. The cup leak, 15 dB down, hardly shows when a blast is only some 15 dB over the clamp. And filtering the microphones' sound before their limiter made it clamp less.
- headset2 exaggerates for the game's squeezed mix: the microphones go 3 dB down per dB over the clamp, to -40 dB at most, judged on the whole sound, and the leak is -10 dB and two-pole at 300 Hz. In blasts it keeps 4-12 dB more bass than treble against the limiter. "Now this is starting to feel very nice" (user), who wants Off, Gentle and Firm in Settings, Gentle the default.
- The user also confirmed that headset2 "breathes" at the fire rate and wants that fixed, wants partners' nearby voices through the headset while the radio stays clear, and asked to try lifting quiet sounds, as real talk-through does. The deep bass I suspected behind headset2's 3% of clamping on the quiet street wasn't it: ignoring the bass below 80 Hz barely changed that, so it's most likely the distant gunshots.
- The user wants a constant, subtle feel while wearing it, to nudge people off a radio they forget on, since "telling people to turn off their radios is immersion breaking".
- headset3 is headset2 plus: recovery slowing from 150 ms to 900 ms while bangs keep coming (breaths in the gunfight 39 down to 10), the bass below 80 Hz not triggering it, quiet sounds lifted up to 6 dB (1-3 dB on average), the picture narrowed to 75% and a hiss at -64 dB. After a blast the world now takes about a second to come back. "Feels fantastic" (user), so headset3 is the model to build into the game.
- Decided (user): the headset is worn while your radio mic is on, so that brings the clamp, the lift and the character, and with the radio off the world sounds natural. That's the nudge: a radio left on feels slightly off with nobody saying so. With the radio off nothing protects an incoming call from a fight, and that needs no fix: "don't forget to turn on your radio when going into combat" (user). So the radio's own loud-moment boost (choice 1) is dropped.
- Radio earpiece now defaults to Both (user), since a tactical headset covers both ears. A saved Left or Right stays as it is.

## 2026-11-07: Falloff curves to compare in a session

The user wants nearby voices "a bit easier to hear" at medium distances, since "sometimes it can be hard to hear people under the ambient noise", and asked for a switch or slider to try first.
Today's curve is full volume within 2 m, then -6.8 dB at 5 m, -12.5 at 10, -15.8 at 15, -18.3 at 20 and -21.7 at 30, fading out from 30 m to silence at 40 m. That's already close to how speech really falls off.
The user had held back from a slider because a gentler curve leaves someone at 30 m fairly loud just before the fade takes them away. The 40 m limit also decides who gets sent a voice, so every game has to agree on it, and it stays out of this.
0.4.6 adds "Distance falloff (test)" under Hearing: 100% (today), 85%, 70%, 50%, and 70% with taper. A percentage is the share of today's dB a voice loses at each distance. At 30 m, 85% is 3.3 dB louder than today and 70% is 6.5 dB louder. The taper keeps the full lift up to 20 m and eases back to today's curve by 40 m, so 70% with taper is -12.8 dB at 20 m and -18.5 dB at 30 m, the 85% level.
It covers a voice, its room sound and its echoes, not the radio. It only changes what that player hears and is logged as `falloff:`. No protocol change, so 0.4.6 plays with 0.4.5. Once a curve is picked by ear, build it in for everyone and remove the choice.

## 2026-11-07: A Relay fallback, for sharing with the community

The user reversed "no voice fallback": "I want to add fallback so I can share this mod with the community." No direct link in the logs has failed while NightCoop itself worked, so it isn't fixing anything seen so far. Designed, and approved by the user; built in 0.5.0 (the entry above):
- When a direct link is down, voice and presence go as the same encrypted packets over a NightCoop channel, two 20 ms frames a message, and switch back when direct returns. Each side picks for itself and accepts both.
- A guest's messages to another guest go through the host, so the user and Bleack would go by way of Bossun in North America, very roughly 150-200 ms each way (estimate). It also only moves while the games run frames, so loads cut it.
- Named "Relay" in the HUD (user). A visible Relay setting, When needed or Always, so the crew can play a whole session on it (user). Protocol 3.
- NightCoop's limits are 120 messages and 32 KB a second per mod, enough for 4 partners on the Relay at once.
The SDK's `SECURITY.md` bars networking of your own and tells Nexus Mods reviewers to look for it, which the direct links are. Ask the NightCoop team before publishing. If they require it, Always is the version that complies.

## 2026-11-05: Solo mode came and went; the tuning file stays for now

To test alone the user asked for the mod to act as if a link existed. I began building a recorder that repeated their words from a spot in the world, and they stopped it: "why so complex?". They could already compare their own echo with the last session, and the full test would wait for the team.
What shipped for that test was `solo=1` in `tuning.ini`, which ran the audio and the room's rays with nobody linked. 0.4.5 removes it, since it kept the mic open with no session.
`%LOCALAPPDATA%\NightCoopVoice\tuning.ini` remains, with `room_db=`, `ring=`, `echo_db=` and `own_db=`, read within a second and logged as `tuning:`. It only changes the PC it's on, and with no file nothing changes. It's there to tune partners' level live at the team test. Once levels are settled, put them in the constants and remove `LiveTuning` and `ReadLiveTuning`.

## 2026-11-05: A hallway gave a "second me"

In a concrete hallway "there's a second me mimicking every sound I make" (user). Readings by timing: closed 0.90-1.00, 4-5 m, ringing 0.5-0.9 s, which is reasonable, so the measure wasn't the fault. An apartment nearby had the same problem (user).
I blamed the reverb's first pass, which is only eight copies of the voice, and went from two input diffusers to four. The user heard no real difference, so that theory was wrong or not the main cause. The four diffusers are still in, and could come back out.
A further diffuser for the user's own voice alone was proposed and dropped when the user asked whether it was realistic: it isn't, since a room treats every voice alike.
10 dB less on the user's own voice made it "much better" (user), so it was mostly level. If a copy comes back, the next idea is lowering own reverb while speaking and raising it in pauses, which is how a real voice covers its own reflections.

## 2026-11-05: How loud your own voice is in a room

The user's own reverb reaches them late, an estimated 60-90 ms, never measured: mic capture, noise removal in 10 ms blocks, a 30 ms output buffer (`kRenderTargetMs`), and the Windows mixer and sound card. Real reflections in a small space arrive within about 5-30 ms and blend into the voice. So a short ring plays after the word has ended and sounds like a repeat, and shrinking buffers can't close that gap.
That sets these rules, for own voice only:
- Silent below a 0.5 s ring, full at 1.4 s (`kOwnEchoNeedsDecayFrom`, `kOwnEchoNeedsDecayTo`), and only somewhere closed in (0.25 to 0.6 enclosure). A pipe or kitchen therefore stays silent for it; only partners can show those spots.
- Gain 0.5, 6 dB under a partner's reverb. In the underpass, 10 dB under felt a touch quiet and 6 dB under "feels right" (user). Earlier the user had picked full partner level there, before the hallway.
- Headphones on only, and not underwater or in a car.

The user asked whether partners want the same cut, since it's the same room. Their reverb follows their voice with no gap and sits under it, so I left them alone, but nobody has heard that yet. Decide at the team test; a faint "second Bossun" in a hallway would change this.

## 2026-11-04 to 05: The room measure was wrong in most places that aren't rooms

Each of these came from the user standing somewhere with SFX at 0 and saying it sounded wrong. Readings by timing. The rays are ten: eight around at head height, one up, one down.

- **Balcony, "sounds like a tunnel"** (user): closed 0.85-0.91, ringing 3.5-3.9 s, because the ceiling above and the building across the courtyard both stopped rays. Now each direction looks for a roof out that way, and an open side counts as open.
- **Sidewalk under a high overhang:** closed 0.12, 38 m, ringing 3.0 s. A roof 30 m up counted, and rays flying 40 m earned a tunnel bonus. Now a roof counts within 15 m, or within 25 m with a wall nearby under it. Ring is capped by open sides: 0.5 s at three, 0.25 s with no roof.
- **Open square, faint echo** (user): stairs, signs and low walls gave echoes, because any ray hit counted as a full wall. Now an echo needs a surface reaching past the hit to both sides.
- **Ramp recess beside a low wall:** closed 1.00, ringing 1.2 s. Rays at head height stopped at the wall, with open air above it. Now a wall must rise 1.5 m past the hit or that direction is open. Going 2.5 m found the ceiling instead, as a fake room showed.
- **Mattress alcove open to a field, "clear echo"** (user): closed 0.94, ringing 0.8 s, roof over 8 of 8. Probably a far structure over the field counted as cover. The roof check now looks no further than 12 m along a ray.
- **Pipe and overpass, almost nothing** (user): closed 0.51 and 0.12, because open ends cut the level even with a ceiling right above. A ceiling under 15 m now holds a minimum level. A real overpass should give a soft slap and about half a second of ring, by my estimate.
- **Tunnel, "too compressed"** (user): closed 1.00, 5 m, ringing 0.9 s. It was sized from its narrow side, and a curve stopped its rays short of the bonus. Long narrow spaces under 8 m now ring up to twice as long, with longer echo spacing.
- **Underpass, "sounds great"** (user): closed 0.94-0.97, 8-10 m, ringing 1.6-2.0 s. This is the reference, and the tunnel change leaves anything this wide alone.

Decay now comes from a space's narrow side, about 4 V / S, with opposite directions added so standing beside a wall doesn't change the room. Before, the mean ray length made long spaces ring far too long.
Soft materials soak up sound and give no echo (`SoftSurfaceAbsorbs`). The review had cut this because soft surfaces were under 0.2% of hits; the user called it a no-brainer, and it costs no rays. It only sees what the ten rays touch, so low furniture mostly won't count. Hard and unknown surfaces stay at 0.2, so rooms tuned by ear don't move.
An elevator read nearly open and later closed (user heard the change). Moving cars are probably invisible to the rays, as vehicles are; left alone as rare. Clutter below head height isn't detected either.

## 2026-11-04: A repeat of the user's words in an alley

In an alley: "not a slight reverb feeling, it's straight up a repetition of my words" (user). I had just called a faint echo about right there, reading only the numbers (closed 0.12, ringing 0.2 s), and that was wrong.
Big-space delays of 40-100 ms with a short ring hardly go round once, so the reverb acts as a plain delay, and the mic's lateness adds to it. A short ring now stays in the small network however big the place: `kLargeNeedsDecayFrom`, `kLargeNeedsDecayTo` in `dsp.cpp`. Own voice also fell silent below a short ring here, which later became the rule above.

## 2026-11-04: 0.4.0 was far too echoey

First session with acoustics, all three on 0.4.0: "the echo is waaay too much", a balcony sounded like a tunnel, and a tunnel was too much too (user). On the logs, rays cost almost nothing: 20-61 a second, mean 4-7 us including script, worst 297 us, busiest frame 320 us; the voice's whole frame had a mean of 29-83 us and a worst of 1654 us.
Besides the measure above: reverb at -9 dB against a voice at 2 m, and 3-4 s rings. Echoes could sit almost level with a far talker's voice, so they're now capped about 9 dB under it, and halved in open air.
Levels went -9 to -15 and then -18 dB closed, and -26 to -38 dB open, all by ear on the user's own voice. 0.4.1 and 0.4.2 overshot, with the pipe nearly silent and no "noticeable echo" while running around talking (user).
Since this needs ears, not tests, `tuning.ini` was added so levels could change without a restart.

## 2026-11-04: The acoustics plan, and what the review changed

The user wanted beyond ordinary voice chat, with realism over clarity: corners, echoes, materials, own echo and their room, in one release with no on/off switches. A reviewer read the plan first, at the user's request. What changed, checked against code and logs:
- The old tail sat about 28 dB under a voice at 2 m and followed distance, so better echoes would have gone unheard. Its level now comes from the room, not the talker's distance.
- Room rays followed the camera, so looking down changed the room. They're on fixed world directions now.
- `audible` also decided sending, and it already disagreed between machines, since listener facing and per-machine walls fed into it. That reversed my claim at 0.3.7 that one shared distance made them match. Sending now goes by straight-line distance and cars only (`ShouldSendNearby`), since no way round is shorter.
- Echoes: walls only, since a floor bounce at 5 m is 2.7 ms and would comb. Up to 4, arrivals under 15 ms left to the tail, delay changes limited to 0.8% and larger moves crossfaded. Fixed reverb delays, since changing them warbles.
- Reach 40 m, not 80. Geometry moved into C++ behind flat natives (`NextRay`, `ReportRay`), so it can be tested on fake rooms. Rays limited to 12 and 300 us a frame. Fewer rays for players not talking lately.
- Their room comes from each player's own measure in the presence packet, at no ray cost, which is why the protocol went to 2. It only applies through walls, or a voice in your room would get two tails.
- Own voice is tail only, with no echoes.

The game's pathfinder was left out: `GetNavigationSystem(game).CalculatePathOnlyHumanNavmesh(a, b, NavGenAgentSize.Human, tolerance)` returning `ref<NavigationPath>` is confirmed from disassembly, but it's synchronous, and its cost with no route is unknown. Closed unlocked doors keep NPC links and locked ones disable them (`Door.EvaluateOffMeshLinksTask`), but whether routes cross those is unknown too. Test it from the CET console before using it. So two-corner routes nobody walked come through the wall. Corners use the last bend, both players' walked trails, then a fan of rays. A plain ray search stopped at one bend when the user asked "why this limit?", since two would take about 1,300 lines and 3-5 s per search, by my estimate.
"Why not build all at once so we don't have to restart the game 3 times?" and "nah, we'll just restart once and test in the end" (user) replaced my plan of stages behind switches.
Rays were chosen over the game's baked acoustics (`worldAcousticDataResource`, portals, reverb zones), since scripts can't query them and their format is unread. Measured rays at about 4 us made that easy.

## 2026-11-04: Asked about, not built

A falloff slider, to come back now that it wouldn't affect sending: I advised waiting for 0.4.x, since walls and facing took much of the level at distance. In the 0.3.8 session, 18-23% of speech arrived from 10-30 m at a mean nearby gain of 0.02-0.11. If it's too quiet, change the curve for everyone.
Whispering needs no mode if the voice gate and noise removal let it through, which is untested; the Hear yourself test would show. Shouting was set aside, since the user lives in an apartment and can't really shout.

## 2026-11-04: Distance sliders removed

"Full volume within" and "Silent past" are gone (0.3.7), so everyone gets 2 m and 40 m, set in `SpatialInput`, and saved values are ignored. The logs showed players hearing distance differently, and only implied about 9-14 m for Bleack; the user said it was 11 m, on purpose, because he wanders around. I suggested keeping the sliders and sending out to 100 m; "nvm, let's just remove the slider. if bleack finds it cuts off too soon, we bump it for everyone" (user). Silent past went because it also stopped sending, by my reading, and the user agreed.

## 2026-11-04: Materials and noise, as first asked

Materials: "maybe you can just look at game files?" (user), so I read them. Sectors store materials as hashes of names like `concrete.physmat`, listed in `r6/cache/tweakdb.bin`. Rays do return them, and the shares move a lot: `default_material` was 6-31% of hits by player in one session and 47-67% in others, unexplained. That's why they were first cut to through-wall loss only (2026-11-04 to 05 has the rest).
Noise: the goal was never clarity. "My goal here wasn't to make voice easier to hear, but to give noisy environments a more realistic feel" (user, typo fixed), and I had misread it as lifting voices. Then "let's just drop it" (user).

## 2026-11-04: Realism: radio, facing, water, slow motion, muffling

Radio (0.3.4): the user wanted a headset or military radio, not a voice in the head. An earpiece in one ear with a faint leak to the other, 350-3400 Hz, a peak at 2.5 kHz and CVSD grit. Full CVSD measured a tone only 8 dB over the rest, so it's blended at `kGrit` 0.6 for 13 dB. It plays about 4 dB over a nearby voice in that ear, as a guess. Both ears was added at the user's request (0.3.5), and is forced with Headphones off. "Seems fine now that both ears option is added" (user) was said on 0.3.4, which didn't have that option yet, so the radio's sound still has no real verdict.
Talker facing (0.3.6) rests on "camera is tied to the mouse and the body turns. my head tracker doesn't turn the body" (user): back turned is about 4 dB down and duller, with the room's sound unchanged. Underwater, on the listener only: about -20 dB, 350 Hz, panning collapsed. Slow motion from the world's speed, whatever the cause. The `time:` logs showed frame dt doesn't slow with the world, so positions don't go stale; a reading of 0 means a load, not slow motion.
A Sandevistan reached both partners at 0.30 for about 9.2 s in a test at 20:18:57. The owner eases back over about 0.7 s, and partners snap to 1. What the two test loops sounded like was never answered. Other slowdowns differ: one at 20:08:46 reached all three, and Bossun's near 19:58 and 20:14 showed only on his game, cause unknown.
Muffling takes time to change (0.3.8), as someone in the crew pointed out: car 1 s, walls 0.5 s for the full range, water 0.25 s in and 0.4 s out, slow motion 0.2 s in and 0.8 s out.
Dropped by the user: radio talkers placed left and right ("that's not how real radio works"), moving mouths, enemies hearing shouts, and noise masking or lifting.

## 2026-11-03: 0.3.0 crashed everyone

Seven crashes across all three in about 7 minutes, from 20:58:29 to 21:05:47 on the user's clock: three each for the user and Bossun, one for Bleack, each within minutes of the game starting on that build. Passing a `script_ref` parameter straight to Codeware's `TraceResult.GetHitEntity` compiles with a "temporary" flag, so Codeware frees the caller's variable and corrupts the game's allocator.
Three of the crashes are proven: the 21:02:15 dump shows the whole chain from `OnVoiceFrame` through `NightCoopVoiceDoorAt` to the free, and Bossun's logs show the same stack. The other four are very likely, since they landed at other addresses reading memory that was no longer there. So one crash's address alone doesn't point at the caller. The compiled call had flag 1 before the fix and has flag 0 after. `+0x6134ba` also predates this build, so it may be a separate older issue.
A session on this mod first blamed rays hitting half-destroyed objects and removed door muffling, which was wrong. A separate session traced the real cause and restored it. The `Deref` copy in `NightCoopVoiceDoors.reds` must stay. Check any Codeware native taking a `script_ref` the same way.
Doors are in the `Dynamic` collision group, from a CET test by the user and every door the logs have shown. A closed one came out too subtle, so 0.3.2 made it about 10 dB and 1.5 kHz, a thin wall 11 dB and 1.3 kHz, and thick walls 18 dB and 450 Hz.

## 2026-11-03: Direction and distance

"Vertical directionality impact is much larger than horizontal" and "10-15 meters away shouldn't still feel like I'm next to them" (user). In the code, by my reading: a pan by level alone, three rays at one height, and 15 m only 6 dB down. So 0.3.0 brought the head model, five spread rays and the near-inverse curve. Nobody has given a verdict on those by ear since.

## 2026-11-03: Levels set themselves

Bleack found the user quiet while Bossun found them fine, on identical packets (user). Bossun's game Master is 30 and the user's 100, and voices ignored it. So 0.2.0 has each mic even itself out and sets one voice gain per listener against the measured output. The volume sliders went; only a Voice level offset and per-player mute remain.
Every talker then arrived at about -24 dB RMS, yet both listeners ranked Bossun loudest (user). That plain RMS doesn't match ears because of bass is a theory nothing has settled. 0.2.1 judges auto gain on 300 Hz-4 kHz. Voice gain was also sinking in calm play, with speech 14 dB under loud parts where 6 was meant, which I thought the biggest part of it.
Asked more than once and never answered: Bleack's voice stream volume in `pavucontrol`, and whether Bossun is on speakers.

## 2026-11-03: A link that never formed

Bossun and Bleack failed to link on one join: Bleack's NightCoop never registered Bossun's mods, for any mod, so offers timed out. The cause inside NightCoop is unknown. 0.1.1 re-sends the mod list by registering and unregistering a throwaway mod, and adds a peer on its first setup message. Later they linked after 18 s with one re-send.

## 2026-11-03: First decisions

The idea came from NightCoop's SDK gaining byte channels: "a proximity voice + phone calls + radio mod" with three modes (user). Close by, a voice that follows distance and walls. Far away, a phone call, dropped if the game needs the phone "to not softlock quests". Far away on missions, a radio: "it's your ops comms".

The user's:
- "Build proximity and radio both now". The phone went unbuilt. I had advised it, since the game's phone functions are on NightCoop's do-not-hook list and "a 1:1 call only adds privacy and flavour" for three players; the user gave no reason of their own.
- Open mic, no push-to-talk: "in the heat of combat, no one can bother with PTT".
- Direct links between every pair: the two Europeans would otherwise talk through North America, and "I know it works between me and bossun". A relay of their own was first proposed, reusable by other mods, then "we could even just ditch the relay?". All three NATs kept one outside port, in the logs.
- No voice fallback: "nah, let's not even bother with that. if we experience issues with direct, we can consider alternatives then."
- Radio always heard, with each player switching their own radio mic, replacing my shared open and close: "if someone far away wants to say "hey guys, come to x", the others don't miss it". Calls over NPC dialogue are fine: "an NPC says something and a player makes a joke about it".
- Voices may lose to gunfire, "like a real gunfight", so the game's volume isn't lowered.
- Native UI: "forget what I said about CET only", after first asking for a CET overlay. Mod Settings came up for its live overlay, then "Keep Native Settings".
- "Let me review and approve (the design)", after I began building without that.
- The SDK's checklist bars networking of your own: "doesn't matter... ours is a completely separate additional system". Ask the NightCoop team before ever publishing it.

Mine, which the user agreed to:
- A car's cabin muffles heavily within 5 m and silences beyond, since total silence "with someone standing at your window could look like a broken link". Bikes block nothing. Riders in one vehicle hear each other clean.
- Audio is encrypted, with a key the host makes per session in SDK shared state, so no accounts or server. It began with a relay that shouldn't read the audio, and stayed with no reason recorded.
