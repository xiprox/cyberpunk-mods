-- Sounds partners hear from us: NightCoop's SDK plays a game sound event on
-- each partner's copy of one of our entities (our body, the car we drive), as
-- GameObject.PlaySound would. Partners need only NightCoop, which takes such
-- sounds only from a mod registered with "uses effects", so this registers the
-- mod once. Our own game plays the sound for us already.
--
-- Tweaks queue sounds with Sounds.Play from anywhere (a hook, an observer);
-- they go out from Update, CET's onUpdate, since NightCoop takes SDK calls on
-- the game thread only. RECORD.md has why it's done this way.

local Log = require("core/log")

local Sounds = { name = "Sounds to partners" }

local MOD_ID = "xip.nightcoop-tweaks" -- stable forever: partners' NightCoop knows the mod by it
local MOD_NAME = "NightCoop Tweaks"
local PROTOCOL = 1
local USES_EFFECTS = 2097152 -- NCSDK_MOD_USES_EFFECTS: the permission for PlaySoundOn

local REGISTER_SECONDS = 5.0 -- between tries to register
local POLL_PER_FRAME = 32    -- events NightCoop queues for the mod; nothing here needs them
local MAX_QUEUED = 64

-- NightCoop takes 10 sounds a second from a mod, in bursts of 20
-- (NCSDK_FX_PER_S). Ordinary sounds keep to 8 and 16, so a stop always has room.
local RATE, BURST = 8, 16
local RETRY_SECONDS = 2.0    -- how long a sound that must arrive is tried again

local RESULT_NAMES = {
    [-1] = "bad argument", [-2] = "not now", [-3] = "over the limit", [-4] = "unsupported",
    [-5] = "switched off", [-6] = "denied", [-7] = "entity not synced",
}

local version = "?"
local registered, lastRegister = false, -math.huge
local queue = {} -- { entity, event, stop, important, since }
local tokens, lastRefill = BURST, nil
local stats = { sent = 0, reached = 0, dropped = 0, refused = {} }
local lastSent

local function sdkOn()
    local ok, v = pcall(function() return NightCoopSdk.Version() end)
    return ok and type(v) == "number" and v > 0
end

local function register(now)
    if registered or now - lastRegister < REGISTER_SECONDS then
        return registered
    end
    lastRegister = now
    local ok, result = pcall(function()
        return NightCoopSdk.RegisterMod(MOD_ID, MOD_NAME, version, PROTOCOL, USES_EFFECTS)
    end)
    registered = ok and result == true
    if registered then
        spdlog.info("registered with NightCoop's SDK as " .. MOD_ID)
    elseif ok then
        Log.Problem("NightCoop's SDK refused to register the mod (its log says why); partners won't hear our sounds")
    end
    return registered
end

-- NightCoop keeps up to 1024 events for a registered mod and drops the oldest;
-- taking them keeps its count of dropped events at 0.
local function drainEvents()
    for _ = 1, POLL_PER_FRAME do
        local ok, line = pcall(function() return NightCoopSdk.PollEventText(MOD_ID) end)
        if not ok or line == nil or line == "" then
            return
        end
    end
end

local function inSession()
    local ok, result = pcall(function() return NightCoopSdk.InSession() end)
    return ok and result == true
end

local function refill(now)
    if lastRefill then
        tokens = math.min(BURST, tokens + (now - lastRefill) * RATE)
    end
    lastRefill = now
end

local function refuse(code)
    local key = RESULT_NAMES[code] or tostring(code)
    stats.refused[key] = (stats.refused[key] or 0) + 1
    if code == -6 then
        -- not declared, or the registration went (a NightCoop restart of the SDK): register again
        registered = false
    end
end

-- Sends one; true when it's done with (sent, or refused for good).
local function send(item, now)
    if not item.important then
        if tokens < 1 then
            stats.dropped = stats.dropped + 1
            return true
        end
        tokens = tokens - 1
    end
    local ok, result = pcall(function()
        return NightCoopSdk.PlaySoundOn(MOD_ID, item.entity, item.event, item.stop)
    end)
    if not ok then
        Log.Problem("NightCoopSdk.PlaySoundOn failed: " .. tostring(result))
        return true
    end
    if result >= 0 then
        stats.sent = stats.sent + 1
        stats.reached = stats.reached + result
        lastSent = string.format("%s%s to %d partner(s)", item.stop and "stop " or "", item.event, result)
        return true
    end
    if item.important and (result == -2 or result == -3) and now - item.since < RETRY_SECONDS then
        return false
    end
    refuse(result)
    return true
end

-- Plays `event` (a game sound event name) on partners' copies of the entity
-- with this EntityID. opts.stop stops it there instead; opts.important keeps
-- trying for a while when NightCoop says "not now" or "over the limit", for a
-- sound whose loss would leave something on, like a horn's stop.
function Sounds.Play(entity, event, opts)
    opts = opts or {}
    if #queue >= MAX_QUEUED then
        stats.dropped = stats.dropped + 1
        return
    end
    table.insert(queue, {
        entity = entity, event = event, stop = opts.stop == true,
        important = opts.important == true, since = os.clock(),
    })
end

-- Our peer id in the session, -1 out of one.
function Sounds.LocalPeer()
    local ok, peer = pcall(function() return NightCoopSdk.LocalPeer() end)
    return ok and type(peer) == "number" and peer or -1
end

function Sounds.SetVersion(text)
    version = text
end

function Sounds.Update()
    local now = os.clock()
    refill(now)
    if not sdkOn() then
        registered = false
        queue = {}
        return
    end
    if not register(now) then
        queue = {}
        return
    end
    drainEvents()
    if #queue == 0 then
        return
    end
    if not inSession() then
        queue = {}
        return
    end
    local waiting = {}
    for _, item in ipairs(queue) do
        if not send(item, now) then
            table.insert(waiting, item)
        end
    end
    queue = waiting
end

-- On Reload All Mods and when the game closes: what's queued (a horn's or a
-- loop's stop) gets one try, then NightCoop forgets the mod.
function Sounds.Shutdown()
    if registered and inSession() then
        for _, item in ipairs(queue) do
            item.important = true
            send(item, math.huge)
        end
    end
    queue = {}
    if registered then
        pcall(function() NightCoopSdk.UnregisterMod(MOD_ID) end)
        registered = false
    end
end

function Sounds.Explain()
    local refused = {}
    for reason, count in pairs(stats.refused) do
        table.insert(refused, string.format("%s %d", reason, count))
    end
    table.sort(refused)
    local lines = {
        string.format("Sounds to partners: %s; %d sent, heard %d times, %d dropped over our own limit%s",
            registered and ("registered as " .. MOD_ID) or "not registered with NightCoop's SDK",
            stats.sent, stats.reached, stats.dropped,
            #refused > 0 and ("; refused: " .. table.concat(refused, ", ")) or ""),
    }
    if lastSent then
        table.insert(lines, "  last: " .. lastSent)
    end
    if stats.refused["not now"] then
        table.insert(lines, "  \"not now\" in a session: look in nightcoop.log for \"from another thread\"")
    end
    return lines
end

return Sounds
