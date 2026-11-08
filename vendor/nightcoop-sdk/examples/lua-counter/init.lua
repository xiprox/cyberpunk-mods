-- SPDX-License-Identifier: MIT — Copyright (c) 2026 NightCoop (see sdk/LICENSE)
-- NightCoop SDK example: a shared counter as a Cyber Engine Tweaks mod.
--
-- Put this file and nightcoop_sdk.lua (from sdk/cet/) in the same mod folder:
--   bin/x64/plugins/cyber_engine_tweaks/mods/CoopCounterExample/init.lua
--   bin/x64/plugins/cyber_engine_tweaks/mods/CoopCounterExample/nightcoop_sdk.lua
--
-- The counter is shared state of the mod "example.counter.lua", key "count" (decimal text), kept by the host.
-- The hotkey adds 1: on the host it sets the value, on a guest the same call is a request to the host. A "ping"
-- message (channel 1) goes to everyone who has the mod. Everybody sees the new value and the ping.

local Sdk = require("nightcoop_sdk")

local CHANNEL_PING = 1

local counter = Sdk.new(
    "example.counter.lua",            -- stable unique id: ASCII [a-z0-9._-], 3..64 bytes
    "Shared counter (Lua example)",   -- display name
    "1.0.0",                          -- your mod's version
    1,                                -- protocol: your own wire version
    Sdk.FLAG.NEEDED_BY_ALL + Sdk.FLAG.HOST_AUTHORITY + Sdk.FLAG.USES_SHARED_STATE + Sdk.FLAG.USES_CHANNELS
)

local function currentCount()
    return tonumber(counter:getState("count") or "0") or 0
end

local function bump()
    if not Sdk.available() then
        print("[counter] NightCoop is not installed (or its SDK is switched off)")
        return
    end
    local result = counter:setState("count", tostring(currentCount() + 1))
    if result < 0 then
        counter:log(Sdk.LOG.WARN, "SetState failed: " .. tostring(result))
        return
    end
    -- to = Sdk.PEER_ALL: every peer that has the mod. reliable = false: a missed ping does not matter.
    counter:send(Sdk.PEER_ALL, CHANNEL_PING, "bumped the counter", false)
end

local function onEvent(ev)
    if ev.kind == Sdk.EVENT.STATE and ev.key == "count" then
        if ev.removed then
            counter:log(Sdk.LOG.INFO, "counter removed")
        else
            counter:log(Sdk.LOG.INFO, "count = " .. ev.data .. " (set by peer " .. tostring(ev.peer) .. ")")
            counter:showMessage("Shared counter: " .. ev.data, 2.0, Sdk.TONE.QUIET)
        end

    elseif ev.kind == Sdk.EVENT.MESSAGE and ev.a == CHANNEL_PING then
        counter:showMessage(Sdk.peerName(ev.peer) .. " " .. ev.data, 3.0, Sdk.TONE.INFO)

    elseif ev.kind == Sdk.EVENT.SESSION then
        if ev.a == Sdk.SESSION.PEER_MOD then
            counter:log(Sdk.LOG.INFO, Sdk.peerName(ev.peer) .. " has the counter mod")
        elseif ev.a == Sdk.SESSION.PEER_NO_MOD then
            counter:log(Sdk.LOG.INFO, Sdk.peerName(ev.peer) .. " does not have the counter mod")
        end
    end
end

registerForEvent("onInit", function()
    counter:register() -- safe to repeat; poll() also retries if NightCoop was not ready yet
end)

registerForEvent("onUpdate", function(dt)
    counter:poll(onEvent) -- at most 32 events per frame
end)

registerHotkey("coop_counter_bump", "Shared counter +1", bump)
