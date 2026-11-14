# Drivable bus

The Mahir MT28 Coach as a vehicle V can drive (first), with NightCoop partners taking its seats (second): the user's idea, 2026-11-08.
Scouted from the game files only; nothing built and nothing tried in the game. Check these against the files before building on them.

## What its files have and lack

- The record `Vehicle.v_mahir_mt28_coach` (`tools/redmod/tweaks/base/gameplay/static_data/database/vehicles/special/v_mahir_mt28_coach.tweak` in the game folder) already has a drive model, an engine, player audio, third-person cameras and the four-seat set.
  `vehDefaultState.DisableAllInteractions = true` shuts it off. Make a new record and leave the traffic buses alone.
- Its entity `base\vehicles\special\v_mahir_mt28_coach_basic_01.ent` has no `gameinteractionsComponent` (a Supron has one) and one interaction slot, `seat_front_left_interaction`, offset to the right-hand door. A Supron also has slots for its other three seats.
- No steering wheel mesh, but the rig has animated `steering_wheel` bones at (-0.93, 4.01, 1.02). The driver's bone is over an ordinary double passenger bench.
- Seat bones: front left and both back ones are over real benches (mid-bench, sideways); `seat_front_right` (0.75, 3.44) is over nothing, by the door. The back left and right are on swapped sides.
  Move the bones in a copy of the rig and keep their names.
- One folding door, on the right; `door_front_left_*` and `door_front_right_*` are its two halves. The driver's seat is across the bus from it, so expect the game's entry clip to pass through a wall (not seen yet).

## In co-op

- NightCoop syncs only the four standard seat names ([shared-spawns.md](../vendor/nightcoop-sdk/docs/shared-spawns.md)), which the bus uses; four is enough for the crew of three.
- Players' vehicles of one record become one vehicle in a session, which is what a shared bus wants. Everyone needs the mod for the mirror.
- Whether NightCoop's by-the-door seating works with this one door is the first co-op unknown.
- Nexus Mods 17099 (tidusMD) already adds it as a player vehicle; it wasn't looked at.
