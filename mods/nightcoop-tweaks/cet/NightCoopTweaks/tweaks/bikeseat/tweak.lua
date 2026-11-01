-- Bike seat: keeps a partner who rides a bike in first-person sitting on it.
-- Without this they look like they stand, to everyone but themselves.
--
-- A camera going to first-person turns the player's wrappers player_tpp_head off
-- and player_fpp_head on, and NightCoop passes that to the partner's body, whose
-- graph plays a bike by its third-person clips. So a body keeps these two as a
-- third-person body has them, whatever the rider's camera. RECORD.md has why.
-- This is the watcher's side: the rider needs nothing.

local NightCoop = require("core/nightcoop")
local Ref = require("core/ref")

local Tweak = { name = "Bike seat" }

local SCAN_SECONDS = 1.0 -- how often to look for a body we don't have yet

local enabled = true
local tppHead, fppHead
local bodies = {} -- the bodies' EntityIDs, since a handle would keep a body alive
local lastScan = -math.huge
local report = "not looked yet"

-- A partner's body is a PlayerPuppet, as our player is.
local function scan()
    local player = Game.GetPlayer()
    if not player then
        return
    end
    local started = os.clock()
    local entities = Game.GetEntityList()
    local found = {}
    for _, entity in ipairs(entities) do
        if entity:IsA("PlayerPuppet") and not Ref.Same(entity, player) then
            table.insert(found, entity:GetEntityID())
        end
    end
    bodies = found
    report = string.format("last look: %d of %d entities, %.1f ms", #found, #entities, (os.clock() - started) * 1000)
end

local function setWrapper(body, key, value)
    local event = NewObject("entAnimWrapperWeightSetter")
    event.key = key
    event.value = value
    body:QueueEvent(event)
end

-- True when a body we held has gone, which a rejoin's new body shows up as.
local function apply()
    local alive = {}
    for _, id in ipairs(bodies) do
        local body = Game.FindEntityByID(id)
        if body then
            setWrapper(body, tppHead, 1.0)
            setWrapper(body, fppHead, 0.0)
            table.insert(alive, id)
        end
    end
    local lost = #alive < #bodies
    bodies = alive
    return lost
end

function Tweak.Init()
    tppHead = CName.new("player_tpp_head")
    fppHead = CName.new("player_fpp_head")
end

-- Every frame: at ten times a second a body still stood for seconds after each
-- switch of the rider's camera, as if its clips had to load again.
function Tweak.Update()
    if not enabled then
        return
    end
    local lost = apply()
    local now = os.clock()
    if not lost and now - lastScan < SCAN_SECONDS then
        return
    end
    lastScan = now
    local session = NightCoop.Session()
    if not session or not session.connected then
        bodies = {}
    elseif lost or #bodies < #NightCoop.Remotes(session.peerId) then
        scan()
    end
end

function Tweak.DrawOverlay()
    enabled = ImGui.Checkbox("Keep partners sitting on bikes", enabled)
    ImGui.TextWrapped(string.format("%d partner bodies held; %s", #bodies, report))
end

return Tweak
