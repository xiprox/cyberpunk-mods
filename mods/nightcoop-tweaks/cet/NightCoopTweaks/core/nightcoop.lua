-- NightCoop's script natives (see docs/nightcoop-natives.txt), the session,
-- where the partners are, and their nicknames.

local NightCoop = {}

local MAX_REMOTE_SLOTS = 16
local PIN_MATCH = 2.5 -- metres (across the ground) between a partner's map pin and NightCoop's position of them
local LEARN_SECONDS = 2.0

local names = {}      -- peer id -> nickname, for this session
local candidates = {} -- peer id -> the name the last look paired them with, not yet taken
local lastLearn = -math.huge
local reportedNoCaptions = false

-- Calls a NightCoop native through CET's Game table; nil when it isn't there.
function NightCoop.Call(name, ...)
    local ok, result = pcall(function(...) return Game[name](...) end, ...)
    if ok then
        return result
    end
    return nil
end

function NightCoop.Distance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- The partner's nickname once we've seen their map pin, "Peer N" until then.
function NightCoop.PeerLabel(id)
    local name = names[id]
    if name then
        return id == 0 and (name .. " (host)") or name
    end
    if id == 0 then
        return "Peer 0 (host)"
    end
    return "Peer " .. id
end

-- { role, connected, peerId } from "role=guest connected=yes peerId=3 peers=4 rtt=..."
-- (offline: "role=offline connected=no peerId=none ..."), or nil when NightCoop isn't there.
function NightCoop.Session()
    local status = NightCoop.Call("NightCoopStatus")
    if not status then
        return nil
    end
    local role, connected, peerId = status:match("role=(%S+) connected=(%S+) peerId=(%S+)")
    if not role then
        return nil
    end
    local session = { role = role, connected = connected == "yes" and tonumber(peerId) ~= nil, peerId = tonumber(peerId) }
    if not session.connected then
        names, candidates = {}, {}
    end
    return session
end

-- NightCoop pins each partner's body on the map (a CPO_RemotePlayerVariant
-- pin) with their nickname as the pin's caption, which GetDisplayName() reads.
local function partnerPins()
    local system = Game.GetMappinSystem()
    local remoteVariant = EnumInt(gamedataMappinVariant.CPO_RemotePlayerVariant)
    local pins = {}
    -- a pin can be in more than one list; the same pin twice is harmless below
    for _, target in ipairs({ gamemappinsMappinTargetType.Map, gamemappinsMappinTargetType.Minimap, gamemappinsMappinTargetType.World }) do
        -- CET hands the `out mappins` array back as a return value
        for _, found in ipairs({ system:GetMappins(target) }) do
            if type(found) == "table" then
                for _, pin in ipairs(found) do
                    if EnumInt(pin:GetVariant()) == remoteVariant then
                        table.insert(pins, { name = pin:GetDisplayName(), pos = pin:GetWorldPosition() })
                    end
                end
            end
        end
    end
    return pins
end

local function usableName(name)
    return type(name) == "string" and name ~= "" and not name:find("^LocKey#")
end

local function near(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return dx * dx + dy * dy <= PIN_MATCH * PIN_MATCH
end

-- The name of the one pin near `remote`, when no other partner is near that
-- pin and no pin of another name is near them; nil when it's not that clear.
local function pinFor(remote, remotes, pins)
    local name
    for _, pin in ipairs(pins) do
        if near(pin.pos, remote.pos) then
            if name and name ~= pin.name then
                return nil
            end
            for _, other in ipairs(remotes) do
                if other ~= remote and other.pos and near(pin.pos, other.pos) then
                    return nil
                end
            end
            name = pin.name
        end
    end
    return usableName(name) and name or nil
end

-- Pairs each partner pin with the peer standing where it is. Partners close
-- together are left until they part, and a pairing is taken once two looks in
-- a row agree, since a pin can trail its partner's body while they move.
local function learnNames(remotes)
    local ok, pins = pcall(partnerPins)
    if not ok then
        return
    end
    if #pins > 0 and not reportedNoCaptions then
        local captioned = false
        for _, pin in ipairs(pins) do
            captioned = captioned or usableName(pin.name)
        end
        if not captioned then
            reportedNoCaptions = true
            spdlog.info(string.format("%d partner map pin(s), none with a name: '%s'", #pins, tostring(pins[1].name)))
        end
    end

    local found = {} -- peer id -> name, this look
    for _, remote in ipairs(remotes) do
        if remote.pos then
            found[remote.id] = pinFor(remote, remotes, pins)
        end
    end
    local previous = candidates
    candidates = {}
    for id, name in pairs(found) do
        if names[id] ~= name then
            if previous[id] == name then
                names[id] = name
                spdlog.info(string.format("peer %d is %s", id, name))
            else
                candidates[id] = name
            end
        end
        -- a nickname is one partner's: whoever had it by an earlier mix-up loses it
        if names[id] == name then
            for other, had in pairs(names) do
                if other ~= id and had == name and found[other] ~= name then
                    names[other] = nil
                    spdlog.info(string.format("peer %d isn't %s", other, name))
                end
            end
        end
    end
end

-- The partners NightCoop sends us positions of: { id, pos = { x, y, z }, distance }
-- sorted by peer id, without us. NightCoopRemoteInfo(i) gives
-- "peer=2 pos=(x, y, z) yaw=..." for each, and "" past the end of the list.
function NightCoop.Remotes(ownId)
    local player = Game.GetPlayer()
    local here = player and player:GetWorldPosition()
    local remotes = {}
    for i = 0, MAX_REMOTE_SLOTS - 1 do
        local info = NightCoop.Call("NightCoopRemoteInfo", i)
        if not info or info == "" then
            break
        end
        local id, x, y, z = info:match("peer=(%d+) pos=%(([^,]+), ([^,]+), ([^%)]+)%)")
        id, x, y, z = tonumber(id), tonumber(x), tonumber(y), tonumber(z)
        if id and id ~= ownId then
            local remote = { id = id }
            if x and y and z then
                remote.pos = { x = x, y = y, z = z }
                if here then
                    remote.distance = NightCoop.Distance(remote.pos, here)
                end
            end
            table.insert(remotes, remote)
        end
    end
    table.sort(remotes, function(a, b) return a.id < b.id end)

    -- every so often even when all have names, so a wrong one gets put right
    local now = os.clock()
    if now - lastLearn >= LEARN_SECONDS and #remotes > 0 then
        lastLearn = now
        learnNames(remotes)
    end
    return remotes
end

-- NightCoop's own item transfer: the host checks it, the sender is debited
-- before the recipient is credited, so nothing is duplicated. It takes 1 to
-- 9,999 of an item and answers "inventory: transfer 0x... requested for peer N"
-- when it went, or why not; nil when NightCoop isn't there.
function NightCoop.GiveItem(record, quantity, peer)
    return NightCoop.Call("NightCoopGiveItem", record, quantity, peer)
end

return NightCoop
