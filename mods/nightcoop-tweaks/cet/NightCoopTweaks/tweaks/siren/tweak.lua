-- Siren: partners hear the siren of the police car we drive.
--
-- The game switches a police car's siren lights and sound apart, in
-- VehicleComponent.ToggleSiren(lights, sounds): from the V key, a quest, the
-- wanted level ending, or our getting out. The sound goes to the native
-- VehicleObject.ToggleSiren on our car, and nothing passes it on (NightCoop's
-- DLL names no siren). This plays the car's own siren events, from the game's
-- audio metadata (tools/make-sound-tables.py), on partners' copy of the car
-- through NightCoop's SDK, whenever the siren sound of the car we drive goes on
-- or off. The lights aren't this tweak's. The driver's side: partners need
-- nothing. RECORD.md has why.

local Log = require("core/log")
local Ref = require("core/ref")
local Sounds = require("core/sounds")
local Vehicles = require("core/vehicles")
local Sirens = require("tweaks/siren/sirens")

local Tweak = { name = "Siren" }

local RESEND_SECONDS = 0.4 -- a stop goes again, since a lost one would leave the siren on at partners
local CHECK_SECONDS = 0.5  -- how often a siren on at partners is checked against our seat and the car

local enabled = true
local before    -- the siren sound of the car whose ToggleSiren is running, as it was before
local active    -- { vehicle = EntityID, on, off, name } while our siren sounds at partners
local resend    -- { vehicle, on, at }: the stop's second try
local lastCheck = -math.huge
local starts, stops = 0, 0
local last = "nothing"

local function soundOn(ps)
    return ps:GetSirenSoundsState() == true
end

-- The siren the table has for this car, and the resource it went by.
local function sirenOf(vehicle)
    local name = Vehicles.AudioResource(vehicle, Sirens)
    local siren = Sirens[name]
    if not siren then
        last = "no siren sound known for this car (" .. tostring(name) .. ")"
        Log.Problem("Siren: no siren sound known for the audio resource '" .. tostring(name) .. "'")
    end
    return siren, name
end

-- The off event, then 0.4 s later a stop of the on event itself, in case the
-- off event didn't reach it.
local function sendStop(id, siren, name)
    Sounds.Play(id, siren.off, { important = true })
    resend = { vehicle = id, on = siren.on, at = os.clock() + RESEND_SECONDS }
    stops = stops + 1
    last = string.format("off, %s (%s)", siren.off, name)
end

local function stopActive()
    sendStop(active.vehicle, active, active.name)
    active = nil
end

-- The siren sound of this car went on or off in our game.
local function switched(vehicle, on)
    local id = vehicle:GetEntityID()
    local ours = active ~= nil and Ref.SameId(active.vehicle, id)
    if not on then
        if ours then
            stopActive()
        elseif enabled and Vehicles.Drives(vehicle) then
            -- one that sounded before we took the wheel, which partners' copy may play of its own accord
            local siren, name = sirenOf(vehicle)
            if siren then
                sendStop(id, siren, name)
            end
        end
        return
    end
    if ours or not enabled or not Vehicles.Drives(vehicle) then
        return
    end
    local siren, name = sirenOf(vehicle)
    if not siren then
        return
    end
    if active then
        stopActive()
    end
    if resend and Ref.SameId(resend.vehicle, id) then
        -- a second stop still due for this car would end the siren that starts now
        resend = nil
    end
    Sounds.Play(id, siren.on, { important = true })
    starts = starts + 1
    last = string.format("on, %s (%s)", siren.on, name)
    active = { vehicle = id, on = siren.on, off = siren.off, name = name }
end

-- ToggleSiren switches only a police car (its UseAuxiliary) that isn't
-- wrecked, and a call may change the lights alone, so what counts is the
-- sound's state on the car's persistent state, before and after the call.
local function onBefore(component)
    before = soundOn(component:GetPS())
end

local function onAfter(component)
    local was = before
    before = nil
    if was == nil then
        return
    end
    local now = soundOn(component:GetPS())
    if now == was then
        return
    end
    local vehicle = component:GetVehicle()
    if vehicle then
        switched(vehicle, now)
    end
end

function Tweak.Init()
    ObserveBefore("VehicleComponent", "ToggleSiren", function(self)
        before = nil
        local ok, err = pcall(onBefore, self)
        if not ok then
            Log.Problem("Siren: " .. tostring(err))
        end
    end)
    ObserveAfter("VehicleComponent", "ToggleSiren", function(self)
        local ok, err = pcall(onAfter, self)
        if not ok then
            before = nil
            Log.Problem("Siren: " .. tostring(err))
        end
    end)
end

function Tweak.Update()
    local now = os.clock()
    if resend and now >= resend.at then
        Sounds.Play(resend.vehicle, resend.on, { stop = true, important = true })
        resend = nil
    end
    -- the car gone, a load, or a change we didn't see: the off won't come from that car
    if active and now - lastCheck >= CHECK_SECONDS then
        lastCheck = now
        local vehicle = Game.FindEntityByID(active.vehicle)
        if not vehicle or not vehicle:IsA("vehicleBaseObject") or not Vehicles.Drives(vehicle)
            or not soundOn(vehicle:GetVehiclePS()) then
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
    local was = enabled
    enabled = ImGui.Checkbox("Partners hear your siren", enabled)
    if was and not enabled and active then
        stopActive()
    end
    ImGui.TextWrapped(string.format("%d siren start(s), %d stop(s) for partners; last: %s", starts, stops, last))
end

return Tweak
