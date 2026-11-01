-- NightCoop Tweaks: personal additions to the NightCoop co-op mod.
--
-- Each tweak is a folder under tweaks/ with a tweak.lua (README, "Adding a
-- tweak"); core/ holds what they share. This file loads them, passes CET's
-- events on, and draws the "NightCoop Tweaks" window with a section per tweak.

local Log = require("core/log")
local Input = require("core/input")
local NightCoop = require("core/nightcoop")
local PartnerMenu = require("core/partnermenu")
local Choices = require("core/choices")
local Effects = require("core/effects")
local Phone = require("core/phone")

-- Goes in the zip's name (tools/pack.ps1) and the log's first line, to tell
-- the builds friends run apart. Raise it for every zip that goes out.
local VERSION = "0.1.1"

-- The tweaks, in the order their partner-menu entries and window sections appear.
local TWEAKS = {
    "tweaks/sendmoney/tweak",
    "tweaks/bikeseat/tweak",
}

-- Shared parts with their own Init, Update or Shutdown, run before the tweaks.
local CORE = {
    "core/input",
    "core/choices",
    "core/quantity",
    "core/progressbar",
    "core/effects",
    "core/partnermenu",
    "core/phone",
}

local SESSION_SECONDS = 0.5

local parts = {}  -- { name, module }: the core first, then the tweaks
local tweaks = {} -- the tweaks' parts
local api = {}    -- what the tweaks give the CET console
local broken = {} -- "part: hook" -> true once that hook threw
local overlayOpen = false
local session, lastSession = nil, -math.huge

local function load(path, isTweak)
    local ok, module = pcall(require, path)
    if not ok then
        Log.Problem(string.format("%s didn't load: %s", path, tostring(module)))
        return
    end
    local part = { name = module.name or path, module = module }
    table.insert(parts, part)
    if isTweak then
        table.insert(tweaks, part)
        for key, fn in pairs(module.api or {}) do
            api[key] = fn
        end
    end
end

for _, path in ipairs(CORE) do
    load(path, false)
end
for _, path in ipairs(TWEAKS) do
    load(path, true)
end

-- Runs a part's hook. A hook that throws is logged once and not called again
-- until Reload All Mods, so one broken tweak doesn't take the others down.
local function run(part, hook, ...)
    local fn = part.module[hook]
    local key = part.name .. ": " .. hook
    if not fn or broken[key] then
        return
    end
    local ok, err = pcall(fn, ...)
    if not ok then
        broken[key] = true
        Log.Problem(string.format("%s failed and is off until Reload All Mods: %s", key, tostring(err)))
    end
end

local function runAll(list, hook, ...)
    for _, part in ipairs(list) do
        run(part, hook, ...)
    end
end

local function drawWindow()
    local now = os.clock()
    if now - lastSession >= SESSION_SECONDS then
        lastSession = now
        session = NightCoop.Session()
    end
    if not session then
        ImGui.TextWrapped("NightCoop isn't answering. Is it installed and loaded?")
    elseif not session.connected then
        ImGui.Text("Not in a co-op session.")
    else
        ImGui.Text(string.format("You are peer %d (%s)", session.peerId, session.role))
    end

    for _, part in ipairs(tweaks) do
        if part.module.DrawOverlay and ImGui.CollapsingHeader(part.name, ImGuiTreeNodeFlags.DefaultOpen) then
            run(part, "DrawOverlay", session)
        end
    end

    local problems = Log.problems
    local title = #problems > 0 and string.format("Diagnostics (%d problem%s)", #problems, #problems == 1 and "" or "s") or "Diagnostics"
    if ImGui.CollapsingHeader(title .. "###diagnostics") then
        ImGui.Text("Version " .. VERSION)
        ImGui.Text("Partner menu:")
        for _, line in ipairs(PartnerMenu.Explain()) do
            ImGui.TextWrapped("  " .. line)
        end
        for _, line in ipairs(Input.Explain()) do
            ImGui.TextWrapped("  " .. line)
        end
        for _, line in ipairs(Choices.Explain()) do
            ImGui.TextWrapped("  " .. line)
        end
        ImGui.TextWrapped(Phone.Explain())
        ImGui.TextWrapped(Effects.Describe())
        for _, text in ipairs(problems) do
            ImGui.TextColored(1, 0.45, 0.4, 1, text)
        end
    end
end

registerForEvent("onInit", function()
    spdlog.info("NightCoop Tweaks " .. VERSION)
    runAll(parts, "Init")
end)

registerForEvent("onUpdate", function()
    runAll(parts, "Update")
end)

registerForEvent("onShutdown", function()
    for i = #parts, 1, -1 do
        run(parts[i], "Shutdown")
    end
end)

registerForEvent("onOverlayOpen", function()
    overlayOpen = true
    lastSession = -math.huge
    runAll(tweaks, "OverlayOpened")
end)

registerForEvent("onOverlayClose", function()
    overlayOpen = false
    runAll(tweaks, "OverlayClosed")
end)

registerForEvent("onDraw", function()
    if not overlayOpen then
        return
    end
    if ImGui.Begin("NightCoop Tweaks", ImGuiWindowFlags.AlwaysAutoResize) then
        drawWindow()
    end
    ImGui.End()
end)

-- For finding a game effect's name: GetMod("NightCoopTweaks").Effect("name")
-- plays it for 3 s on what we look at; Diagnostics lists the names it has.
api.Effect = Effects.Try

-- GetMod("NightCoopTweaks").<function> from the CET console
return api
