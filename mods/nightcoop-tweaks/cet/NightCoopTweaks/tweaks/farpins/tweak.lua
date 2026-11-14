-- Far partner pins: keeps a partner on the map and minimap when they're far away.
--
-- NightCoop removes a partner's body 200 m away and makes it again within about
-- 150 m, and its map pin is attached to that body, so the pin goes with it.
-- NightCoop goes on knowing where they are, so while a partner has no body here
-- this puts a pin of the same kind at their position; NightCoop's own hooks give
-- that kind of pin its icon and keep it on the minimap's edge. RECORD.md has why.
-- This is the watcher's side: the partner needs nothing.

local Log = require("core/log")
local NightCoop = require("core/nightcoop")

local Tweak = { name = "Far partner pins" }

local TICK_SECONDS = 0.25    -- how often the pins follow their partners
local RETRY_SECONDS = 5.0    -- before asking again when the game gives no pin
local SETTING_SECONDS = 5.0  -- how often to read NightCoop's map marker setting

local enabled = true
local pins = {}    -- peer id -> { id = the game's NewMappinID, name = its caption }
local retryAt = {} -- peer id -> os.clock() when a pin that failed may be tried again
local lastTick, lastSetting = -math.huge, -math.huge
local mapMarkersOn = true
local report = "not looked yet"

local function vector(pos)
    return Vector4.new(pos.x, pos.y, pos.z, 1)
end

-- Whether the partner has a body in our world, and nil when the SDK can't say:
-- taking that for "no" would put a second pin on every partner.
local function hasBody(peer)
    local ok, result = pcall(function()
        if NightCoopSdk.Version() <= 0 then
            return nil
        end
        local body = NightCoopSdk.PartnerBody(peer)
        return body ~= nil and Game.FindEntityByID(body) ~= nil
    end)
    if ok then
        return result
    end
    return nil
end

local function partnerName(peer)
    local ok, name = pcall(function() return NightCoopSdk.PeerName(peer) end)
    if ok and type(name) == "string" and name ~= "" then
        return name
    end
    return NightCoop.PeerLabel(peer)
end

-- "player markers: in the world and on the map; world: ..." (or "in the world
-- only", "on the map only", "no markers"). A status we can't read leaves it on.
local function readMapMarkers(now)
    if now - lastSetting < SETTING_SECONDS then
        return mapMarkersOn
    end
    lastSetting = now
    local status = NightCoop.Call("NightCoopMarkers", "status")
    local mode = type(status) == "string" and status:match("^player markers: ([^;]*)")
    mapMarkersOn = not mode or mode:find("map", 1, true) ~= nil
    return mapMarkersOn
end

-- peer id -> position of the partners who should have our pin now.
local function bodilessPartners(now)
    if not enabled then
        report = "switched off"
        return {}
    end
    if not readMapMarkers(now) then
        report = "off, as NightCoop's map markers are"
        return {}
    end
    local session = NightCoop.Session()
    if not session or not session.connected then
        report = "not in a co-op session"
        return {}
    end

    local far = {}
    for _, remote in ipairs(NightCoop.Remotes(session.peerId)) do
        local body = hasBody(remote.id)
        if body == nil then
            Log.Problem("Far partner pins: NightCoop's SDK doesn't say who has a body here, so there are no pins")
            report = "NightCoop's SDK isn't answering"
            return {}
        end
        -- (0, 0) is where a partner reads before NightCoop has their position
        if not body and remote.pos and not (remote.pos.x == 0 and remote.pos.y == 0) then
            far[remote.id] = remote.pos
        end
    end
    report = nil
    return far
end

local function registerPin(pos, name)
    local data = MappinData.new()
    data.mappinType = TweakDBID.new("Mappins.CPO_RemotePlayerMappinDefinition")
    data.variant = gamedataMappinVariant.CPO_RemotePlayerVariant
    data.active = true
    data.visibleThroughWalls = true
    local system = Game.GetMappinSystem()
    local id = system:RegisterMappin(data, vector(pos))
    if id.value == 0 then
        error("the game gave pin id 0")
    end
    system:SetMappinDebugCaption(id, name)
    return id
end

local function addPin(peer, pos, now)
    if now < (retryAt[peer] or -math.huge) then
        return
    end
    local name = partnerName(peer)
    local ok, id = pcall(registerPin, pos, name)
    if not ok then
        retryAt[peer] = now + RETRY_SECONDS
        Log.Problem("Far partner pins: no pin for a partner: " .. tostring(id))
        return
    end
    retryAt[peer] = nil
    pins[peer] = { id = id, name = name }
    spdlog.info(string.format("far pin for %s (peer %d) is on", name, peer))
end

local function movePin(pin, peer, pos)
    local system = Game.GetMappinSystem()
    system:SetMappinPosition(pin.id, vector(pos))
    local name = partnerName(peer)
    if name ~= pin.name then
        system:SetMappinDebugCaption(pin.id, name)
        pin.name = name
    end
end

local function removePin(peer)
    local pin = pins[peer]
    pins[peer], retryAt[peer] = nil, nil
    pcall(function() Game.GetMappinSystem():UnregisterMappin(pin.id) end)
    spdlog.info(string.format("far pin for %s (peer %d) is off", pin.name, peer))
end

local function describePins()
    local names = {}
    for _, pin in pairs(pins) do
        table.insert(names, pin.name)
    end
    table.sort(names)
    if #names == 0 then
        return "no partner needs one now"
    end
    return "pinned: " .. table.concat(names, ", ")
end

function Tweak.Update()
    local now = os.clock()
    if now - lastTick < TICK_SECONDS then
        return
    end
    lastTick = now

    -- A load or the main menu: the world's pins went with it, and the ids we
    -- hold belong to the old world's mappin system.
    if not Game.GetPlayer() then
        pins, retryAt = {}, {}
        report = "no world"
        return
    end

    local far = bodilessPartners(now)
    for peer in pairs(pins) do
        if not far[peer] then
            removePin(peer)
        end
    end
    for peer, pos in pairs(far) do
        if pins[peer] then
            movePin(pins[peer], peer, pos)
        else
            addPin(peer, pos, now)
        end
    end
    report = report or describePins()
end

-- On Reload All Mods too: nothing would own these pins afterwards.
function Tweak.Shutdown()
    for peer in pairs(pins) do
        removePin(peer)
    end
end

function Tweak.DrawOverlay()
    enabled = ImGui.Checkbox("Show partners on the map when they're far away", enabled)
    ImGui.TextWrapped(report)
end

return Tweak
