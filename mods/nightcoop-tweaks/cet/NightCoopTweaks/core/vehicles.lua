-- The car we drive, for the tweaks that play its sounds to partners (Horn,
-- Siren): whether the local player sits in a vehicle's driver seat, and which
-- of its audio resources a table from the game's audio metadata knows.

local Ref = require("core/ref")

local Vehicles = {}

local DRIVER_SLOT = "seat_front_left" -- VehicleComponent.GetDriverSlotName(); bikes use it too

-- Whether the local player sits in this vehicle's driver seat (the mounting
-- facility's slot, as the game's IsDriver).
function Vehicles.Drives(vehicle)
    local player = Game.GetPlayer()
    if not player then
        return false
    end
    local info = Game.GetMountingFacility():GetMountingInfoSingleWithIds(player:GetEntityID())
    if not info or not Ref.SameId(info.parentId, vehicle:GetEntityID()) then
        return false
    end
    return NameToString(info.slotId.id):find(DRIVER_SLOT, 1, true) ~= nil
end

-- The vehicle's audio resource, as `known` (a table by resource name) has it:
-- the record's player_audio_resource, else its AudioResourceName. When the
-- table has neither, the name to report.
function Vehicles.AudioResource(vehicle, known)
    local record = vehicle:GetRecord()
    local player = record:Player_audio_resource()
    if known[player] then
        return player
    end
    local other = NameToString(record:AudioResourceName())
    if known[other] then
        return other
    end
    return player ~= "" and player or other
end

return Vehicles
