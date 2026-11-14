# Manual shifting

Shifting gears by hand in cars and bikes: the user's idea, 2026-11-08.
Scouted by reading the exe only; nothing built and nothing tried in the game.

The addresses are for the 2.5 Steam exe (66,704,848 bytes, base 0x140000000), so a build needs byte patterns, since a game patch moves them.
Finding them took a full disassembly, whose listing was in a temporary folder and is gone.

## What the exe has

- Vehicle (`WheeledBaseObject`): gearbox at `*(veh+0xBC8)`, engine at `*(veh+0xBD0)`.
- Gearbox: owner at +0, 8 gear entries of 0x30 bytes from +0x18, count +0x198, current gear +0x1C8, pending +0x1C4, previous +0x1CC, cooldown timer +0x1B4, shift timer +0x1AC.
  Gear -1 is neutral, 0 is reverse, 1 and up are forward.
  Per entry (offsets from the gearbox, at index 0): +0x18 down speed, +0x1C up speed, +0x20 min RPM, +0x24 max RPM, +0x28 torque multiplier; +0x34 and +0x38 give RPM = a + b * speed.
- `0x14081db9c` ChangeGear(gearbox, gear, instant, ignoreCooldown): every gear change goes through it.
  It refuses during the cooldown unless forced, and when the config var `Vehicle/BlockChangeGear` is on (its value at 0x143917138).
- `0x1406e2e6c` is the automatic gearbox's update (gearbox, dt). All its decisions end in the one call at `0x1406e32ba`, reverse (0) and neutral (-1) included. It shifts up when RPM reaches the gear's max RPM.
  ChangeGear's other callers: `0x1406e41f0` snaps to the right gear (instant), `0x1406e94cc` goes from reverse to 1st, `0x14081e0ec` to reverse.
- Engine: RPM +0x14 (min +0x68, max +0x6C), clutch 0..1 +0x34, clutch state +0x38 (0 engaged, 1 out, 2 neutral, 3 in), fuel-cut timer +0x4C.
  `0x1406e01e8` integrates RPM from torque and inertia, clamped to max + 100; `0x1406e3a00` is the rev limiter (a 0.05 s fuel cut); `0x1406e35a8` computes torque.
  So the engine already simulates a clutch and a rev limiter.

## The plan

- A RED4ext plugin hooks the gearbox update, applies key presses there, and refuses the automatic forward-to-forward shifts at that one call, leaving reverse and neutral automatic.
- Stalling and a player clutch are ours to add. Hard downshifts are the risk nobody has tried.
- First check, with no build: CET's `GameOptions.SetBool("Vehicle", "BlockChangeGear", true)` while moving should hold the gear. Whether CET sees this var is unconfirmed.
- An existing mod, Manual Transmission by khaganmv (Nexus Mods 15562), seems to be CET-based; how it works wasn't looked at.
