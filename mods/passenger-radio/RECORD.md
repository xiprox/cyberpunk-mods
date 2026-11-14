# Record

What we found and decided while making Passenger radio, newest entry first.
[README.md](README.md) says what the mod is; this file says why it's that way.

"User" marks what the user saw or heard in the game. "Logs" marks what the collected logs show.

Installed: on the user's PC since 2026-11-02; Input Loader still loaded it on 2026-11-11. Whether the others have it isn't known; all three have Input Loader working.
Not yet checked in the game: that the station change was heard (the logs show it, nobody has said so), and whether a passenger getting out turns the radio off for the whole car (below).

## 2026-11-02: A passenger's radio reaches the whole car

Logs: Input Loader loaded the file at 23:36 on the user's clock. At 23:40, sitting in Bossun's car, the user turned its radio on (station 10) and changed to station 6 three seconds later, and Bossun's game set both for the car ("peer 1 set the radio of our car ... from their seat: on, station 10 — set here, as a passenger's radio key in the game").
Earlier that day, on NightCoop build bacb705, every radio change NightCoop passed on from a passenger was "off": notes from the time counted 9, 7 of them within 3 s of that passenger getting out, and 5 are still in the collected logs (Bossun's, 14:26 to 14:45 on his clock). So getting out probably turns the radio off for the whole car, which looks like a NightCoop bug. That's inferred from the logs; the music cutting out hasn't been confirmed in the game. The user's log of 2026-11-08 has one more "off" from the passenger's seat.

## 2026-11-02: Why passengers had no radio

- The block is in `r6/config/inputContexts.xml`: the `VehiclePassenger` context has no `VehicleInsideWheel` action. The user remembered this from the unmodded game; the scripts have no seat check, which misled at first.
- Story rides have a second block, `IsRadioEnabled` being false with the `VehicleScene` tag, which this mod leaves alone.
- The file appends only that one action. `VehicleAuxillary` would also bring the siren and visual customization.
- It's in a subfolder so the collector's Mods tab (1.3.1 and up) can share it, and Input Loader 0.2.6 reads the subfolder: on 2026-11-03 this PC's merged `r6/cache/inputContexts.xml` had the action inside `VehiclePassenger`.
