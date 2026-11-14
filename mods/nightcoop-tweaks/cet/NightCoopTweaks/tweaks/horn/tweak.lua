-- Horn: partners hear the horn of the car or bike we drive.
--
-- NightCoop passes a police AV's horn on, but no car's, so partners' copy of
-- our car stays silent while we honk. This plays the car's own horn events,
-- from the game's audio metadata (tools/make-sound-tables.py), on their copy
-- through NightCoop's SDK. The driver's side: partners need nothing.
-- RECORD.md has why.

local Log = require("core/log")
local Ref = require("core/ref")
local Sounds = require("core/sounds")
local Horns = require("tweaks/horn/horns")

local Tweak = { name = "Horn" }

local DRIVER_SLOT = "seat_front_left"  -- VehicleComponent.GetDriverSlotName(); bikes use it too
local RESEND_SECONDS = 0.4             -- a stop goes again, since a lost one would leave the horn on at partners
local CHECK_SECONDS = 0.5              -- how often a horn left on is checked against our seat

local enabled = true
local active    -- { vehicle = EntityID, on, off, name } while our horn is on at partners
local resend    -- { vehicle, on, at }: the stop's second try
local lastCheck = -math.huge
local presses = 0
local report = "no horn yet"

-- The vehicle's audio resource, as the horn table knows it.
local function audioResource(vehicle)
    local record = vehicle:GetRecord()
    local player = record:Player_audio_resource()
    if Horns[player] then
        return player
    end
    local other = NameToString(record:AudioResourceName())
    if Horns[other] then
        return other
    end
    return player ~= "" and player or other
end

-- Whether the local player sits in this vehicle's driver seat.
local function drives(vehicle)
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

local function stopActive()
    if active.off then
        Sounds.Play(active.vehicle, active.off, { important = true })
        resend = { vehicle = active.vehicle, on = active.on, at = os.clock() + RESEND_SECONDS }
    end
    active = nil
end

-- VehicleComponent.ToggleVehicleHorn(state, isPolice): the driver's horn key,
-- and a quest's honk. Only a vehicle we drive, or the one our horn is on in.
local function onToggle(component, state, isPolice)
    local vehicle = component:GetVehicle()
    if not vehicle then
        return
    end
    local id = vehicle:GetEntityID()
    if not state then
        if active and Ref.SameId(active.vehicle, id) then
            stopActive()
        end
        return
    end
    if not enabled or vehicle:IsA("vehicleAVBaseObject") or not drives(vehicle) then
        return
    end
    local name = audioResource(vehicle)
    local horn = Horns[name]
    if not horn then
        report = "no horn sound known for this vehicle (" .. tostring(name) .. ")"
        Log.Problem("Horn: no horn sound known for the audio resource '" .. tostring(name) .. "'")
        return
    end
    if active then
        stopActive()
    end
    local on = isPolice and horn.policeOn or horn.on
    local off = isPolice and horn.policeOff or horn.off
    if isPolice and not horn.policeOn then
        on, off = horn.on, horn.off
    end
    Sounds.Play(id, on, { important = true })
    presses = presses + 1
    report = string.format("%d press(es); last: %s (%s)", presses, on, name)
    if off then
        active = { vehicle = id, on = on, off = off, name = name }
    end
end

function Tweak.Init()
    Observe("VehicleComponent", "ToggleVehicleHorn", function(self, state, isPolice)
        local ok, err = pcall(onToggle, self, state, isPolice)
        if not ok then
            Log.Problem("Horn: " .. tostring(err))
        end
    end)
end

function Tweak.Update()
    local now = os.clock()
    if resend and now >= resend.at then
        -- the second try stops the horn's own event, in case the stop event didn't reach it
        Sounds.Play(resend.vehicle, resend.on, { stop = true, important = true })
        resend = nil
    end
    -- out of the seat with the key still held, or a load: the release won't come from that car
    if active and now - lastCheck >= CHECK_SECONDS then
        lastCheck = now
        local vehicle = Game.FindEntityByID(active.vehicle)
        if not vehicle or not drives(vehicle) then
            stopActive()
        end
    end
end

function Tweak.Shutdown()
    if active then
        stopActive()
    end
end

function Tweak.DrawOverlay()
    enabled = ImGui.Checkbox("Partners hear your horn", enabled)
    ImGui.TextWrapped(report)
end

return Tweak
