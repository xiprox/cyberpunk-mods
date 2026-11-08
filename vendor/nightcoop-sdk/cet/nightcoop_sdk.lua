-- SPDX-License-Identifier: MIT — Copyright (c) 2026 NightCoop (see sdk/LICENSE)
--[[
nightcoop_sdk.lua -- helper for Cyber Engine Tweaks mods that use the NightCoop SDK (version 1).

Copy this file into your mod folder next to init.lua (bin/x64/plugins/cyber_engine_tweaks/mods/<YourMod>/) and load it:

    local Sdk = require("nightcoop_sdk")

    local mod = Sdk.new("yourname.yourmod", "Your Mod", "1.0.0", 1, Sdk.FLAG.NEEDED_BY_ALL)

    registerForEvent("onInit", function() mod:register() end)
    registerForEvent("onUpdate", function(dt)
        mod:poll(function(ev)
            if ev.kind == Sdk.EVENT.STATE and ev.key == "count" then
                print("count is now " .. ev.data)
            end
        end)
    end)

If NightCoop is not installed, or the player switched the SDK off ("sdk" switch), every function here does nothing
and returns a neutral value (see each function); your mod keeps working as a single-player mod.

How events reach you: Lua cannot be a Listen target, so the mod polls in onUpdate. poll() takes the next queued item of
your mod with NightCoopSdk.PollEvent(id) when redscript is installed (the event class is scripted), otherwise with
NightCoopSdk.PollEventText(id), which works without redscript. Either way the handler gets the same table:

    ev.kind        Sdk.EVENT.*
    ev.peer        Int: who it is about (session event), the sender (message), who set it (state), the owner (entity state)
    ev.a           Int: session event (Sdk.SESSION.*), channel (message), entity-state key, 1/0 present (shared spawn),
                   1/0 we lead it now (spawn leader; ev.peer — the new leader)
    ev.key         String: shared-state key (state events); "" otherwise
    ev.removed     Bool: the state key / entity-state key was removed or cleared
    ev.data        String: the payload as raw bytes ("" if none or removed)
    ev.entityHash  String: decimal EntityID hash of OUR mirror/copy (entity-state and shared-spawn events); "0" if none
    ev.entity      EntityID userdata, only when the event came as an object (redscript installed); else nil.
                   Without it, use Sdk.entityOfRef(ev.ref).
    ev.ref         Uint64 (cdata) NCSDK_PACK_REF value: kind 8 | owner 24 | id 32 (see Sdk.splitRef)
    ev.source      "object" or "text"
    ev.request     Int: the request number of NPC_REQUEST / NPC_RESULT events
    ev.effect      Int: NPC_RESULT — Sdk.NPC.* of the effect, 0 — a general request
    ev.object      the NightCoopSdkEvent itself (source "object" only; pose fields of kind 5 are there)

Not covered by the text path: the pose fields of partner-pose events (kind 5). Use the object path for those.
]]

local Sdk = {}
Sdk.__index = Sdk

-- ------------------------------------------------------------------------------------------------ constants

Sdk.PEER_HOST = 0
Sdk.PEER_NONE = -1
Sdk.PEER_ALL = -2 -- send(): every peer that has the mod

-- Result codes of the Int32 functions (NightCoopSdkResult in redscript, NCSDK_E_* in C).
Sdk.RESULT = {
    OK = 0,
    BAD_ARGUMENT = -1,
    NOT_NOW = -2,
    LIMIT = -3,
    UNSUPPORTED = -4,
    SWITCHED_OFF = -5,
    DENIED = -6,
    UNKNOWN = -7,
    TOO_SMALL = -8,
}

-- Mod flags (add them: FLAG.NEEDED_BY_ALL + FLAG.HOST_AUTHORITY). Declare what the mod uses (USES_*, SPAWNS_ENTITIES for
-- shared spawns, CHANGES_QUESTS for KeepFactLocal): an undeclared use answers Denied (-6), see sdk/SECURITY.md.
Sdk.FLAG = {
    NEEDED_BY_ALL = 1,
    LOCAL_ONLY = 2,
    CHANGES_WORLD = 4,
    CHANGES_QUESTS = 8,
    ADDS_ITEMS = 16,
    SPAWNS_ENTITIES = 32,
    HOST_AUTHORITY = 64,
    USES_CHANNELS = 256,
    USES_SHARED_STATE = 512,
    USES_ENTITY_STATE = 1024,
    USES_POSE = 2048,
    USES_ACTIONS = 4096,
    USES_NPC_REQUESTS = 8192, -- npc effects and requests (sdk/docs/npc-effects.md)
    USES_WORLD_TIME = 67108864, -- worldSlow
    USES_SAVE = 32768,   -- mod:scriptableScope
    USES_MENU = 65536,   -- mod:menuItemSet, mod:menuItemRemove
    USES_VOTES = 131072, -- mod:voteStart, mod:voteCancel
    USES_WORLD_ASK = 8388608, -- mod:worldAsk
    CHANGES_NPC_LOGIC = 1048576, -- NPCs go to the nearest player only if they have the mod
    USES_EFFECTS = 2097152,      -- permission for mod:showEffect, attachEffect, playSound
    USES_REWARDS = 4194304,      -- permission for mod:grantReward
    USES_HOOKS = 262144, -- hookDeclare
    USES_FALLBACKS = 16384, -- fallbackSet
}

-- mod:showEffect flags (C NCSDK_FX_*).
Sdk.FX = { IGNORE_TIME_DILATION = 1, BY_NAME = 2 }

-- kinds of content a partner may not have (fallbackSet, contentHere)
Sdk.FALLBACK = { VEHICLE = 1, ITEM = 2, WEATHER = 3, RADIO = 4, PHOTO_POSE = 5 }
-- where a mod without the SDK lies (peerHasKnownMod) — the kinds of NightCoop's mods list (logs/nightcoop-mods.txt)
Sdk.KNOWN_MOD = { RED4EXT = 0, REDSCRIPT = 1, CET = 2, ARCHIVE = 3, REDMOD = 4, TWEAK = 5, ASI = 6 }

Sdk.LOG = { TRACE = 0, INFO = 1, WARN = 2, ERROR = 3 }
Sdk.TONE = { QUIET = 0, INFO = 1, WAIT = 2, URGENT = 3 }

-- ev.kind
Sdk.EVENT = { SESSION = 1, MESSAGE = 2, STATE = 3, ENTITY_STATE = 4, PARTNER_POSE = 5, SHARED_SPAWN = 6,
    -- the co-op menu and votes
    MENU_ITEM = 11,   -- ev.key — the item key of your mod the player pressed in the co-op menu
    VOTE_RESULT = 12, -- ev.key — the vote key, ev.a — the winner (-1 none), ev.value — Sdk.VOTE_END.*, ev.data — votes
                      -- per option (one byte each), then the number of voters
    SPAWN_LEADER = 9, REWARD = 18, -- shared spawns, rewards
}
-- we lead the NPC and a player asks this mod (ev.request; answer with mod:npcReply), and the
-- answer to our own request (ev.a = result, ev.request, ev.effect)
Sdk.EVENT.NPC_REQUEST = 7
Sdk.EVENT.NPC_RESULT = 8

-- effects on NPCs a partner leads (sdk/docs/npc-effects.md)
Sdk.NPC = { REQUEST = 0, STATUS = 1, REMOVE_STATUS = 2, DAMAGE = 3, IMPULSE = 4, SLOW = 5, ATTITUDE = 6, SIDE = 7, KILL = 8,
    FOLLOW = 9, GOD_MODE = 10, FAKE_DEATH = 11, DISPOSE = 12, HIDE = 13 }
Sdk.GOD_MODE = { MORTAL = 0, IMMORTAL = 1, INVULNERABLE = 2 }
Sdk.NPC_FLAG = {
    SKIP_LOCAL = 1,   -- status: your mod did it on our copy itself
    PERCENT = 2,      -- damage: value is percent of max health
    NONLETHAL = 4,    -- damage: can defeat, not kill
    REACT = 8,        -- damage without an attack record: a hit reaction of reactType
    ALL_PLAYERS = 16, -- attitude: to every player
    SHOW_ALWAYS = 32, -- status: on the partners' copies whatever its type
    NO_ANIM = 64,     -- kill: no death animation
    NO_RAGDOLL = 128, -- kill: no ragdoll
}
Sdk.NPC_SIDE = { JOIN = 0, ALL_ENEMIES = 1, OWN = 2 }
Sdk.ATTITUDE = { FRIENDLY = 0, NEUTRAL = 1, HOSTILE = 2 }

-- shareEntity flags (C NCSDK_SHARE_*). HANDOFF — an NPC goes to the player nearest to it, as an NPC of the world;
-- ev SPAWN_LEADER tells who leads it then.
Sdk.SHARE = { FOLLOW = 1, ANIMATE = 2, HANDOFF = 4 }

-- ev.a of a SESSION event
Sdk.SESSION = {
    START = 1,
    END = 2,
    PEER_JOIN = 3,
    PEER_LEAVE = 4,
    PEER_WORLD_IN = 5,
    PEER_WORLD_OUT = 6,
    PEER_MOD = 7, -- the player has this mod (same id and protocol)
    PEER_NO_MOD = 8,
    -- co-op events, their value in ev.value
    PARTNER_DOWN = 9,     -- value 1 fell, 0 got up
    TEAM_DOWN = 10,       -- every player of the host's world is down: 1 the host loads its last save, 0 no save
    PARTNER_VEHICLE = 11, -- value 1 in (passenger), 2 at the wheel, 0 out; ev.ref — the vehicle
    NPC_KILLED = 12,      -- ev.peer — the killer (may be us), ev.ref — the npc
    WORLD_PAUSE = 13,     -- value 1 every player is in a menu, 0 the world runs again
    HOST_SAVE = 14,       -- value 1 the host saved, 2 the host loaded a save
    TIME_SKIP = 15,       -- value — the world's game time after the host's skip, seconds
    WORLD_ANSWER = 32,    -- the answer to mod:worldAsk: value — Sdk.WORLD_ANSWER.*, peer — who asked
}

-- mod:worldAsk kinds and answers
Sdk.WORLD = { TIME_OF_DAY = 1, WEATHER = 2 }
Sdk.WORLD_ANSWER = { REFUSED = 0, DONE = 1, FAILED = 2, BUSY = 3 }

-- mod:scriptableScope scope
Sdk.SCOPE = { DEFAULT = 0, WORLD = 1, CHARACTER = 2 }
-- mod:menuItemSet flags (add them)
Sdk.MENU = { DISABLED = 1, IN_SESSION = 2, HOST_ONLY = 4, IN_WORLD = 8 }
-- ev.value of a VOTE_RESULT event
Sdk.VOTE_END = { DECIDED = 1, FORCED = 2, TIMED_OUT = 3, CANCELLED = 4, ABORTED = 5 }
-- Sdk.partner(peer).flags (test with Sdk.has(flags, Sdk.PARTNER.DOWN))
Sdk.PARTNER = { IN_WORLD = 1, DOWN = 2, COMBAT = 4, VEHICLE = 8, WHEEL = 16, SCENE = 32, MENU = 64, LINK_LOST = 128, US = 256 }
-- Sdk.partner(peer).where
Sdk.WHERE = { UNKNOWN = 0, HOST_WORLD = 1, MAIN_MENU = 2, LOADING = 3, JOINING = 4, OWN_WORLD = 5 }

-- kind of a network reference (see Sdk.splitRef)
Sdk.NET = { NONE = 0, PLAYER = 1, VEHICLE = 2, NPC = 3, SPAWN = 4 }

-- ------------------------------------------------------------------------------------------------ the class

-- NightCoopSdk is a native class registered by NightCoop.dll. Look it up lazily and never cache a failure for long:
-- before the game is ready the lookup may fail.
local cls = nil
local lastProbe = -1e9

local function sdk()
    if cls then
        return cls
    end
    local now = os.clock()
    if now - lastProbe < 5 then
        return nil
    end
    lastProbe = now
    local ok, c = pcall(function() return NightCoopSdk end)
    if ok and c ~= nil then
        local okv, v = pcall(c.Version)
        if okv and type(v) == "number" and v > 0 then
            cls = c
        end
    end
    return cls
end

-- Call NightCoopSdk.<name>(...). Returns the first result, or nil when the SDK is absent or the call failed.
local function call(name, ...)
    local c = sdk()
    if not c then
        return nil
    end
    local ok, r = pcall(c[name], ...)
    if ok then
        return r
    end
    return nil
end

local function code(r)
    if r == nil then
        return Sdk.RESULT.UNSUPPORTED
    end
    return r
end

-- Is NightCoop here with its SDK switched on?
function Sdk.available()
    return sdk() ~= nil
end

-- ------------------------------------------------------------------------------------------------ session (static)

function Sdk.inSession() return call("InSession") == true end
function Sdk.isHost() return call("IsHost") == true end
function Sdk.inWorld() return call("InWorld") == true end
function Sdk.inHostWorld() return call("InHostWorld") == true end
function Sdk.localPeer() return call("LocalPeer") or Sdk.PEER_NONE end
function Sdk.peers() return call("Peers") or {} end
function Sdk.peerName(peer) return call("PeerName", peer) or "" end
function Sdk.peerInOurWorld(peer) return call("PeerInOurWorld", peer) == true end

-- A text a partner sent, safe to show or log (valid UTF-8, no control, invisible or direction characters, at most
-- maxBytes, 0 — 256). Without NightCoop: the text cut to maxBytes bytes (no cleaning — nothing to show it with anyway).
function Sdk.cleanText(text, maxBytes)
    local r = call("CleanText", tostring(text or ""), maxBytes or 0)
    if type(r) == "string" then return r end
    local s = tostring(text or "")
    local max = (maxBytes and maxBytes > 0) and maxBytes or 256
    return s:sub(1, max)
end

-- ------------------------------------------------------------------------------------------------ hooks
-- sdk/docs/do-not-hook.md. Your mod hooks a game function (Override / Observe) — tell NightCoop, it warns the player like for
-- the hooks it finds itself: flags Sdk.HOOK.REPLACES (the original does not run) or Sdk.HOOK.WRAPS (it runs). Needs
-- FLAG.USES_HOOKS. Returns 1 — co-op relies on it now, 0 — not, or a negative Sdk.RESULT. Without NightCoop: 0.
Sdk.HOOK = { REPLACES = 1, WRAPS = 2 }
Sdk.HOOK_AREA = {
    PLAYER = 1, NPC = 2, POPULATION = 4, VEHICLES = 8, QUESTS = 16, TIME = 32, SAVES = 64, MENU = 128, WORLD = 256,
    DEVICES = 512, OTHER = 1024,
}
function Sdk.hookDeclare(id, class, fn, flags)
    return call("HookDeclare", id, class, fn, flags or Sdk.HOOK.REPLACES) or 0
end

-- Does co-op rely on Class.fn now? A mask of Sdk.HOOK_AREA (0 — no). Use it to call the original (the last argument of
-- your Override) where co-op needs it.
function Sdk.hookCoopUses(class, fn)
    return call("HookCoopUses", class, fn) or 0
end

-- Keys NightCoop reads itself: { {name=, vk=, ik=, action=, when=, rebindable=}, ... } (empty without NightCoop).
function Sdk.coopKeys()
    local out = {}
    for _, line in ipairs(call("CoopKeys") or {}) do
        local name, vk, ik, action, when, rebind = tostring(line):match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
        if name then
            out[#out + 1] = { name = name, vk = tonumber(vk), ik = ik, action = action, when = when, rebindable = rebind == "1" }
        end
    end
    return out
end

-- Pick a label in the game's UI language: ru for Russian, en for English, NightCoop's translation of en for the others.
function Sdk.pick(ru, en)
    return call("Pick", ru, en) or en
end

-- ------------------------------------------------------------------------------------------------ entities (static)

-- EntityID -> Uint64 network reference (cdata); nil if NightCoop does not sync the entity.
function Sdk.entityRef(entity)
    local r = call("EntityRef", entity)
    if r == nil or r == 0 then
        return nil
    end
    return r
end

-- Uint64 reference (cdata or decimal string) -> our local EntityID, or nil if it is not here now.
function Sdk.entityOfRef(ref)
    local u = Sdk.toU64(ref)
    if u == nil then
        return nil
    end
    return call("EntityOfRef", u)
end

-- 1 mine, 0 a partner's, RESULT.UNKNOWN (-7) not synced by NightCoop (then it is purely local: yours).
function Sdk.entityIsMine(entity)
    return code(call("EntityIsMine", entity))
end

-- The body of a partner in our world, or nil.
function Sdk.partnerBody(peer)
    return call("PartnerBody", peer)
end

-- ------------------------------------------------------------------------------------------------ partners

-- Is the bit set? (Lua 5.1 / LuaJIT without bit ops in plain Lua)
function Sdk.has(flags, bit)
    return flags ~= nil and bit ~= nil and flags >= 0 and math.floor(flags / bit) % 2 == 1
end

-- What a player is doing (a partner, or ourselves): { flags = Sdk.PARTNER bits, where = Sdk.WHERE.*, health = 0..1 or
-- -1, level = 0 unknown, vehicle = Uint64 ref or nil }, or nil (no session, no such player).
function Sdk.partner(peer)
    local flags = call("PartnerFlags", peer)
    if flags == nil or flags < 0 then
        return nil
    end
    local vehicle = call("PartnerVehicle", peer)
    if vehicle == 0 then
        vehicle = nil
    end
    return {
        flags = flags,
        where = call("PartnerWhere", peer) or Sdk.WHERE.UNKNOWN,
        health = call("PartnerHealth", peer) or -1,
        level = call("PartnerLevel", peer) or 0,
        vehicle = vehicle,
    }
end

-- ------------------------------------------------------------------------------------------------ shared spawns
-- Recipe for CET mods (exEntitySpawner leaves no mark NightCoop could see): right after you spawn, either share the entity
-- (partners get a copy or a mirror) or keep it local (NightCoop's NPC and vehicle rules never touch it). See
-- sdk/docs/shared-spawns.md. Needs the mod flag SPAWNS_ENTITIES.

-- Who leads the entity now (peer number); Sdk.PEER_NONE (-1) — not synced by NightCoop (purely local: yours).
function Sdk.entityLeader(entity)
    local r = call("EntityLeader", entity)
    if r == nil then
        return Sdk.PEER_NONE
    end
    return r
end

-- ------------------------------------------------------------------------------------------------ uint64 helpers

-- A decimal string (or number, or cdata) as a 64-bit integer. In LuaJIT (Cyber Engine Tweaks) the result is a uint64
-- cdata and loses nothing; elsewhere a plain number (lossy above 2^53).
function Sdk.toU64(v)
    if type(v) == "cdata" then
        return v
    end
    local s = tostring(v)
    if not s:match("^%d+$") then
        return nil
    end
    local loader = loadstring or load
    if loader then
        local okl, f = pcall(loader, "return " .. s .. "ULL")
        if okl and f then
            local ok, r = pcall(f)
            if ok then
                return r
            end
        end
    end
    return tonumber(s)
end

local U56 = Sdk.toU64("72057594037927936")
local U32 = Sdk.toU64("4294967296")
local U24 = Sdk.toU64("16777216")

-- Unpack a network reference (NCSDK_PACK_REF): returns kind, owner, id as plain numbers (owner 0xFFFFFF = none).
-- Needs LuaJIT 64-bit integers; returns nil elsewhere.
function Sdk.splitRef(ref)
    local u = Sdk.toU64(ref)
    if u == nil or type(u) ~= "cdata" then
        return nil
    end
    local ok, kind, owner, id = pcall(function()
        return tonumber(u / U56), tonumber((u / U32) % U24), tonumber(u % U32)
    end)
    if not ok then
        return nil
    end
    return kind, owner, id
end

-- ------------------------------------------------------------------------------------------------ event decoding

local function unhex(h)
    if h == nil or h == "" then
        return ""
    end
    return (h:gsub("%x%x", function(x) return string.char(tonumber(x, 16)) end))
end

local function splitTabs(line)
    local out, n, pos = {}, 0, 1
    while true do
        local i = string.find(line, "\t", pos, true)
        n = n + 1
        if not i then
            out[n] = string.sub(line, pos)
            break
        end
        out[n] = string.sub(line, pos, i - 1)
        pos = i + 1
    end
    return out
end

-- PollEventText line: kind \t peer \t a \t entityHash \t ref \t removed \t keyHex \t dataHex [\t value]
local function eventFromText(line)
    line = line:gsub("[\r\n]+$", "")
    local f = splitTabs(line)
    local kind = tonumber(f[1])
    if not kind or kind == 0 then
        return nil
    end
    local ev = {
        kind = kind,
        peer = tonumber(f[2]) or Sdk.PEER_NONE,
        a = tonumber(f[3]) or 0,
        entityHash = f[4] or "0",
        ref = Sdk.toU64(f[5] or "0"),
        removed = (f[6] == "1"),
        key = unhex(f[7]),
        data = unhex(f[8]),
        value = tonumber(f[9]) or 0,
        source = "text",
    }
    -- NPC_REQUEST / NPC_RESULT: key is "<request>/<effect>"
    if ev.kind == Sdk.EVENT.NPC_REQUEST or ev.kind == Sdk.EVENT.NPC_RESULT then
        local r, e = string.match(ev.key, "^(%d+)/(%-?%d+)$")
        ev.request = tonumber(r) or 0
        ev.effect = tonumber(e) or 0
    end
    return ev
end

local function bytesToString(t)
    local parts, n = {}, #t
    local i = 1
    while i <= n do
        local j = math.min(i + 255, n)
        parts[#parts + 1] = string.char((table.unpack or unpack)(t, i, j))
        i = j + 1
    end
    return table.concat(parts)
end

local function hashOf(entityId)
    local ok, h = pcall(function() return entityId.hash end)
    if not ok or h == nil then
        return "0"
    end
    return (tostring(h):gsub("U?LL$", ""))
end

local function eventFromObject(o)
    local ok, ev = pcall(function()
        local kind = o.kind
        if type(kind) ~= "number" or kind == 0 then
            return nil
        end
        local data = o.data or ""
        if data == "" and o.bytes ~= nil and #o.bytes > 0 then
            data = bytesToString(o.bytes)
        end
        return {
            kind = kind,
            peer = o.peer,
            a = o.a,
            key = o.key or "",
            removed = (o.removed == true),
            data = data,
            entity = o.entity,
            entityHash = hashOf(o.entity),
            ref = o.ref,
            value = o.value or 0,
            source = "object",
            object = o,
            request = o.request or 0,
            effect = o.effect or 0,
        }
    end)
    if ok then
        return ev
    end
    return nil
end

local function scriptedEventsExist()
    local ok, c = pcall(function() return NightCoopSdkEvent end)
    return ok and c ~= nil
end

-- ------------------------------------------------------------------------------------------------ a registered mod

-- Sdk.new(id, name, version, protocol, flags) -> mod object. Nothing is registered until :register().
--   id        stable unique id, ASCII [a-z0-9._-], 3..64 bytes
--   protocol  your own wire version: data goes only between players with equal numbers
--   flags     sum of Sdk.FLAG.*
function Sdk.new(id, name, version, protocol, flags)
    return setmetatable({
        id = id,
        name = name or id,
        version = version or "0",
        protocol = protocol or 1,
        flags = flags or 0,
        registered = false,
        _lastRegister = -1e9,
        _objectEvents = nil,
    }, Sdk)
end

-- Register (or update) the mod. Safe to call again. Returns true when registered; false when the SDK is absent or
-- refused (bad id, or the id is registered by a C plugin). The reason is in NightCoop's log.
function Sdk:register()
    local r = call("RegisterMod", self.id, self.name, self.version, self.protocol, self.flags)
    self.registered = (r == true)
    return self.registered
end

function Sdk:unregister()
    call("UnregisterMod", self.id)
    self.registered = false
end

-- Call from onUpdate. Registers the mod if that has not worked yet (retries every 5 s), then hands up to maxPerFrame
-- (default 32) queued events to handler(ev). A handler error is logged and does not stop the loop.
-- Returns how many events were handled.
function Sdk:poll(handler, maxPerFrame)
    if not sdk() then
        self.registered = false
        return 0
    end
    if not self.registered then
        local now = os.clock()
        if now - self._lastRegister < 5 then
            return 0
        end
        self._lastRegister = now
        if not self:register() then
            return 0
        end
    end
    if self._objectEvents == nil then
        self._objectEvents = scriptedEventsExist()
    end

    local limit = maxPerFrame or 32
    local handled = 0
    while handled < limit do
        local ev = nil
        -- PollEvent only when the scripted event class exists: without it the call could not build the object.
        if self._objectEvents then
            local o = call("PollEvent", self.id)
            if o ~= nil then
                ev = eventFromObject(o)
            end
        end
        if ev == nil then
            local line = call("PollEventText", self.id)
            if type(line) == "string" and line ~= "" then
                ev = eventFromText(line)
            end
        end
        if ev == nil then
            break
        end
        handled = handled + 1
        local ok, err = pcall(handler, ev)
        if not ok then
            self:log(Sdk.LOG.ERROR, "event handler failed: " .. tostring(err))
        end
    end
    return handled
end

-- ------------------------------------------------------------------------------------------------ log, screen

function Sdk:log(level, text)
    call("Log", self.id, level, tostring(text))
end

-- A one-off message at the bottom of the screen. Returns true if it was shown.
function Sdk:showMessage(text, seconds, tone)
    return call("ShowMessage", self.id, tostring(text), seconds or 3.0, tone or Sdk.TONE.INFO) == true
end

-- ------------------------------------------------------------------------------------------------ session

-- 1 the peer has this mod (same id and protocol), 0 not, RESULT.NOT_NOW (-2) not known yet.
function Sdk:peerHasMod(peer)
    return code(call("PeerHasMod", self.id, peer))
end

function Sdk:peerModVersion(peer)
    return call("PeerModVersion", self.id, peer) or ""
end

-- ------------------------------------------------------------------------------------------------ channels

-- to: a peer number, Sdk.PEER_HOST (0) or Sdk.PEER_ALL (-2). text: up to 1024 bytes unreliable, 16384 reliable.
-- Returns how many peers it went to (0: nobody has the mod) or a negative RESULT code.
function Sdk:send(to, channel, text, reliable)
    return code(call("Send", self.id, to, channel, tostring(text), reliable and true or false))
end

-- ------------------------------------------------------------------------------------------------ shared state

-- Host: sets and spreads. Guest: asks the host; the value changes when ev STATE comes back. "" removes the key.
function Sdk:setState(key, value)
    return code(call("SetState", self.id, key, tostring(value)))
end

function Sdk:removeState(key)
    return code(call("RemoveState", self.id, key))
end

-- The current value, or nil if the key is not set.
function Sdk:getState(key)
    if call("HasState", self.id, key) ~= true then
        return nil
    end
    return call("GetState", self.id, key)
end

-- ------------------------------------------------------------------------------------------------ entity state

-- Owner only. entity: an EntityID (for example vehicle:GetEntityID()). key: 0..65535, yours. stream = true: unreliable,
-- only the newest value matters. Partners get ev ENTITY_STATE on their mirror/copy.
function Sdk:setEntityState(entity, key, value, stream)
    return code(call("SetEntityState", self.id, entity, key, tostring(value), stream and true or false))
end

function Sdk:clearEntityState(entity, key)
    return code(call("ClearEntityState", self.id, entity, key))
end

-- ------------------------------------------------------------------------------------------------ effects on NPCs

-- An effect on an NPC NightCoop syncs is done by its OWNER with the game, as an action of our player (sdk/docs/npc-effects.md).
-- Register with Sdk.FLAG.USES_NPC_REQUESTS. npc: an EntityID (npc:GetEntityID()) — our local copy or our own NPC.
-- Returns 0 — done here now (ours, or not synced); > 0 — the request number (ev NPC_RESULT with ev.request comes back);
-- < 0 — a RESULT code. record / status / attack: a TweakDBID or its name ("BaseStatusEffect.Burning").
-- Points and vectors: Vector4 or {x, y, z} in world space.

local function tdbid(v)
    if v == nil or v == "" then
        return TweakDBID.new()
    end
    if type(v) == "string" then
        return TweakDBID.new(v)
    end
    return v
end

local function vec4(v)
    if v == nil then
        return Vector4.new(0, 0, 0, 0)
    end
    if type(v) == "table" and v.x == nil and v[1] ~= nil then
        return Vector4.new(v[1], v[2], v[3], 0)
    end
    if type(v) == "table" and v.x ~= nil then
        return Vector4.new(v.x, v.y, v.z, 0)
    end
    return v
end

-- kind: Sdk.NPC.*; the generic form of the calls below.
function Sdk:npcEffect(npc, kind, flags, mode, record, value, seconds, point, vector)
    return code(call("NpcEffect", self.id, npc, kind, flags or 0, mode or 0, tdbid(record), value or 0, seconds or 0,
        vec4(point), vec4(vector)))
end

-- flags: Sdk.NPC_FLAG.SKIP_LOCAL when your mod already put the status on our copy itself.
function Sdk:npcStatus(npc, status, flags)
    return code(call("NpcStatus", self.id, npc, tdbid(status), flags or 0))
end

function Sdk:npcRemoveStatus(npc, status, flags)
    return code(call("NpcRemoveStatus", self.id, npc, tdbid(status), flags or 0))
end

-- value: health points (Sdk.NPC_FLAG.PERCENT: percent of max health); attack: an Attack record or nil (health written
-- directly; with NPC_FLAG.REACT a reaction of reactType); point nil — the chest; dir nil — from us.
function Sdk:npcDamage(npc, attack, value, point, dir, flags, reactType)
    return code(call("NpcDamage", self.id, npc, tdbid(attack), value, vec4(point), vec4(dir), flags or 0, reactType or 0))
end

-- Ragdoll and push: impulse (world) at point; radius 0 — 1 m.
function Sdk:npcImpulse(npc, point, impulse, radius)
    return code(call("NpcImpulse", self.id, npc, vec4(point), vec4(impulse), radius or 0))
end

-- Its own time: dilation 0..1 for seconds (<= 120); 0 — frozen, 1 — back to normal.
function Sdk:npcSlow(npc, dilation, seconds)
    return code(call("NpcSlow", self.id, npc, dilation, seconds or 0))
end

-- attitude: Sdk.ATTITUDE.*, to us (flags Sdk.NPC_FLAG.ALL_PLAYERS: to every player).
function Sdk:npcAttitude(npc, attitude, flags)
    return code(call("NpcAttitude", self.id, npc, attitude, flags or 0))
end

-- side: Sdk.NPC_SIDE.* (JOIN our side, ALL_ENEMIES, OWN back to its group).
function Sdk:npcSide(npc, side)
    return code(call("NpcSide", self.id, npc, side))
end

-- Kill it, we are the killer (flags NO_ANIM, NO_RAGDOLL).
function Sdk:npcKill(npc, flags)
    return code(call("NpcKill", self.id, npc, flags or 0))
end

-- Follow us (an AI follower role, as companion mods; it stays with the NPC at its next owner); false — no role.
function Sdk:npcFollow(npc, follow)
    return code(call("NpcFollow", self.id, npc, follow and true or false))
end

-- God mode: Sdk.GOD_MODE.* (stays with the NPC at its next owner).
function Sdk:npcGodMode(npc, mode)
    return code(call("NpcGodMode", self.id, npc, mode or 0))
end

-- Fake death (its AI plays dying, as AMM "Fake Die"), dispose (as AMM "Despawn"), hide for good.
function Sdk:npcFakeDeath(npc) return self:npcEffect(npc, Sdk.NPC.FAKE_DEATH) end
function Sdk:npcDispose(npc) return self:npcEffect(npc, Sdk.NPC.DISPOSE) end
function Sdk:npcHide(npc) return self:npcEffect(npc, Sdk.NPC.HIDE) end

-- The general request: the owner's copy of this mod gets ev NPC_REQUEST (ev.entity / ev.entityHash — its NPC, ev.a — the
-- channel, ev.data — text) and answers with npcReply(ev.request, result, text); we get ev NPC_RESULT. Returns the request
-- number (> 0; also for our own NPC: then the request comes to us) or a negative RESULT code.
function Sdk:npcRequest(npc, channel, text)
    return code(call("NpcRequest", self.id, npc, channel, tostring(text or "")))
end

-- This mod slows (or stops) OUR world: dilation 0..1 for seconds (<= 120); 1 — over. Declare first, then slow the world
-- with the game yourself. Partners near us get it as an implant's slow-down; a declared stop is no loading screen.
function Sdk:worldSlow(dilation, seconds)
    return code(call("WorldSlow", self.id, dilation, seconds or 0))
end

-- The owner's answer: result 0 or a negative RESULT code; text up to 1024 bytes.
function Sdk:npcReply(request, result, text)
    return code(call("NpcReply", self.id, request, result or 0, tostring(text or "")))
end

-- ------------------------------------------------------------------------------------------------ the save, the co-op menu, votes
-- Declare the flags (Sdk.FLAG.USES_SAVE / USES_MENU / USES_VOTES).

-- A ScriptableSystem of your mod (its class name as RTTI has it) is the world's (Sdk.SCOPE.WORLD: a guest entering the
-- host's world by save takes the host's state of it) or each player's own (CHARACTER, the default); DEFAULT drops it.
function Sdk:scriptableScope(className, scope)
    return code(call("ScriptableScope", self.id, tostring(className), scope or Sdk.SCOPE.DEFAULT))
end

-- Several quest facts each player's own at once: returns how many were accepted (KeepFactsLocal; without it —
-- KeepFactLocal for each).
function Sdk:keepFactsLocal(facts, on)
    local list = {}
    for _, fact in ipairs(facts or {}) do
        list[#list + 1] = tostring(fact)
    end
    local r = call("KeepFactsLocal", self.id, list, on ~= false)
    if r ~= nil then
        return r
    end
    local n = 0
    for _, fact in ipairs(list) do
        if code(call("KeepFactLocal", self.id, fact, on ~= false)) == Sdk.RESULT.OK then
            n = n + 1
        end
    end
    return n
end

-- An item of your mod in NightCoop's co-op menu (Esc -> «Co-op» -> «Mods…»): a press comes as ev.kind EVENT.MENU_ITEM
-- with ev.key. ru / en — the label; flags — sum of Sdk.MENU.*.
function Sdk:menuItemSet(key, ru, en, flags)
    return code(call("MenuItemSet", self.id, tostring(key), tostring(ru or en or ""), tostring(en or ru or ""), flags or 0))
end

function Sdk:menuItemRemove(key)
    return code(call("MenuItemRemove", self.id, tostring(key)))
end

-- Host only: ask every player of the host's world in NightCoop's choice window. optionsRu / optionsEn — Lua arrays of the
-- same length (2..8); the end comes as EVENT.VOTE_RESULT with ev.key on every machine that has the mod.
function Sdk:voteStart(key, questionRu, questionEn, optionsRu, optionsEn)
    return code(call("VoteStart", self.id, tostring(key), tostring(questionRu or questionEn or ""),
                     tostring(questionEn or questionRu or ""), optionsRu or optionsEn or {}, optionsEn or optionsRu or {}))
end

function Sdk:voteCancel(key)
    return code(call("VoteCancel", self.id, tostring(key)))
end

-- Ask the host to change the world: kind Sdk.WORLD.TIME_OF_DAY (value — seconds of the day) or WEATHER (text — a weather
-- state, value — blend seconds). vote — decide by a vote of every player. The answer: SESSION.WORLD_ANSWER. Returns the ask's
-- number (> 0) or a RESULT.
function Sdk:worldAsk(kind, value, text, vote)
    return code(call("WorldAsk", self.id, kind, value or 0, tostring(text or ""), vote and true or false))
end

-- The votes of a VOTE_RESULT event: { votes = { per option }, voters = n }.
function Sdk.voteCounts(ev)
    local data = ev and ev.data or ""
    local out = { votes = {}, voters = 0 }
    if #data == 0 then
        return out
    end
    for i = 1, #data - 1 do
        out.votes[i] = string.byte(data, i)
    end
    out.voters = string.byte(data, #data)
    return out
end

-- ------------------------------------------------------------------------------------------------ shared spawns

-- Share an entity your mod spawned. flags: Sdk.SHARE.* added (FOLLOW + HANDOFF). An NPC: partners near it see it with its
-- animation; with HANDOFF it goes to the player nearest to it. A vehicle: partners get NightCoop's mirror with seats, doors
-- and driver, whoever drives leads it. A prop: a copy (FOLLOW: it follows your transform). If the class has no
-- ShareEntityFlags, the plain ShareEntity is called (FOLLOW and ANIMATE only).
function Sdk:shareEntity(entity, flags)
    local f = flags or 0
    local r = call("ShareEntityFlags", self.id, entity, f)
    if r ~= nil then
        return r
    end
    local follow = (f % 2) == 1
    local animate = (math.floor(f / 2) % 2) == 1
    return code(call("ShareEntity", self.id, entity, follow, animate))
end

function Sdk:unshareEntity(entity)
    return code(call("UnshareEntity", self.id, entity))
end

-- Keep the entity purely local: NightCoop never shares, adopts, hides or removes it. on = false — back to normal.
function Sdk:keepLocal(entity, on)
    return code(call("KeepLocal", self.id, entity, on ~= false))
end

-- Show a world effect (an .effect resource path, picture and sound, no damage) to the partners in our world, fire and
-- forget. Play it on your own machine yourself. position: Vector4, orientation: Quaternion (nil — no rotation).
-- Needs Sdk.FLAG.USES_EFFECTS. Returns how many partners got it (0 — nobody) or a negative RESULT code.
function Sdk:showEffect(path, position, orientation, flags)
    local rot = orientation or Quaternion.new(0, 0, 0, 1)
    return code(call("ShowEffect", self.id, tostring(path), position, rot, flags or 0))
end

-- An effect on a synced entity (a player, a vehicle, an NPC, a shared spawn), on the partners' mirror or copy of it. effect:
-- an .effect resource path attached to slot ("" — the root), or with Sdk.FX.BY_NAME the name of an effect of the entity's
-- template. Returns the effect number (for stopEffect) or a negative RESULT code.
function Sdk:attachEffect(entity, effect, slot, flags)
    return code(call("AttachEffect", self.id, entity, tostring(effect), tostring(slot or ""), flags or 0))
end

function Sdk:stopEffect(number, breakLoop)
    return code(call("StopEffect", self.id, number, breakLoop and true or false))
end

-- A sound event (as GameObject.PlaySound) on the partners' mirror or copy of a synced entity; stop = true stops it.
function Sdk:playSound(entity, event, stop)
    return code(call("PlaySoundOn", self.id, entity, tostring(event), stop and true or false))
end

-- A reward for a partner (to — a peer number, Sdk.PEER_ALL — everyone in our world): quantity of an item record
-- ("Items.money") created in their inventory, exactly once. Needs Sdk.FLAG.USES_REWARDS. Returns the first grant number
-- (> 0), 0 — nobody in our world, or a negative RESULT code; the answer comes as ev REWARD (entityHash = the grant number,
-- a = NCSDK result).
function Sdk:grantReward(to, record, quantity)
    return code(call("GrantReward", self.id, to, tostring(record), quantity or 1))
end

-- Lead an NPC for a while (possession, mind control): entity — our body of a synced NPC (a partner's NPC's copy here). Its
-- owner hands it over; NightCoop keeps it ours for seconds (1..600; -1 — until you call with 0; 0 — release now). The outcome
-- comes as ev SPAWN_LEADER for it (a = 1 ours now, 0 not handed over). Needs the mod flag USES_NPC_REQUESTS (8192).
function Sdk:leaseNpc(entity, seconds)
    return code(call("LeaseNpc", self.id, entity, seconds or 0))
end

-- ------------------------------------------------------------------------------------------------ content a partner may not have
-- sdk/docs/content-fallbacks.md

-- What a partner WITHOUT your mod sees instead of your content: kind Sdk.FALLBACK.*, name — your record / state / station /
-- pose animation, fallback — the game's own of the same kind ("" or nil clears). Needs FLAG.USES_FALLBACKS.
-- mod:fallbackSet(Sdk.FALLBACK.VEHICLE, "Vehicle.v_my_sedan", "Vehicle.v_standard2_archer_hella_player")
function Sdk:fallbackSet(kind, name, fallback)
    return code(call("FallbackSet", self.id, kind, tostring(name or ""), tostring(fallback or "")))
end

-- Is this content in THIS game: 1 yes, 0 no, RESULT.NOT_NOW (cannot tell yet), RESULT.UNSUPPORTED (weather states).
function Sdk.contentHere(kind, name)
    return code(call("ContentHere", kind, tostring(name or "")))
end

-- Does the partner have a mod without the SDK (kind Sdk.KNOWN_MOD.*, its folder or file name as in nightcoop-mods.txt):
-- 1 yes, 0 no, RESULT.NOT_NOW (the mods check with them is not over).
function Sdk.peerHasKnownMod(peer, kind, name)
    return code(call("PeerHasKnownMod", peer, kind, tostring(name or "")))
end

return Sdk
