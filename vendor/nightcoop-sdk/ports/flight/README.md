# Let There Be Flight — NightCoop port

Co-op support for [Let There Be Flight](https://github.com/jackhumbert/let_there_be_flight) (LTBF) by Jack Humbert
(MIT): fly together in NightCoop. The port is one redscript file built only on the public NightCoop SDK and LTBF's public
script members.

## Install

- NightCoop with its SDK.
- Let There Be Flight 0.3.20 or later (0.3.18 on game 2.31) with everything it needs: RED4ext, ArchiveXL, TweakXL, Input
  Loader, redscript.
- Copy `r6/scripts/NightCoopFlight/NightCoopFlight.reds` into `<game>/r6/scripts/NightCoopFlight/`. Without NightCoop or
  without LTBF the file compiles to nothing.

Every player who wants to see the flight as it is should have both LTBF and the port; NightCoop's mods check names those who
lack the port.

## What players see

| | A partner with LTBF and the port | A partner without them |
|---|---|---|
| You fly your car | LTBF's thrusters in place of the wheels, their FX and sound, the flight as you see it | Your car flies without wheels |
| You land | The wheels come back | The wheels come back |
| A partner rides in your flying car | The flight is yours: their LTBF stays off for the ride, the camera follows the car | The same |
| You get out in the air and a partner stays in it | Their LTBF goes on with the flight: the car is theirs now | The car stays yours and flies on with nobody at the controls; they ride in it |
| You switch gravity off with LTBF's quickhack | The car floats on their screen as on yours | The same, wheels on |

What else the port does:

- A flying car is never pulled into the game's physics when another car touches it (it would just drop), and is never handed
  to a partner whose game cannot fly it.
- LTBF's quickhacks are not offered on a partner's car; the game's own vehicle quickhacks work on it through NightCoop.

Mod id `nightcoop.port.let_there_be_flight`, version 2.0, protocol 2, flags "needed by all", "changes the world" and "uses
entity state".

## Limits

- A partner without the port, with LTBF or without it, sees no thrusters, FX or flight sound — only your car without wheels.
  With LTBF but without the port, their own flight key may also switch LTBF on for your car in their game (NightCoop then
  pulls it back to your path). Install the port on every machine.
- LTBF's one-shot sounds of switching the flight on and off are heard by the driver only.
- Faster than about 100 m/s a partner sees the car jump from point to point.

## License

The port: MIT, as NightCoop's SDK. Let There Be Flight: MIT, Jack Humbert — see THIRD_PARTY.md.
