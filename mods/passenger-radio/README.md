# Passenger radio

The radio key in a passenger's seat.
The game's `VehiclePassenger` input context leaves out the `VehicleInsideWheel` action that the driving contexts and `DelamainTaxi` have, so a passenger can't open the radio.
This adds only that action, not `VehicleAuxillary`, which would also bring the siren and visual customization.
Story rides stay without a radio: `IsRadioEnabled` is false with the `VehicleScene` tag, and this doesn't lift it.
[RECORD.md](RECORD.md) says what we found and where it stands.

## Installing

It needs Input Loader. The folder is laid out like the game folder: copy `r6` over it.
The file is in a folder of its own, `r6/input/passengerradio/`, so the log collector's Mods tab can share it; Input Loader reads that folder.
`dist/passengerradio.zip` has the same layout. An earlier zip had a flat `r6/input/passengerradio.xml`, which anyone who extracted it should delete.

In NightCoop, only the passenger needs it: NightCoop sends the passenger's change to the car's owner, whose game sets the radio for everyone in the car.
