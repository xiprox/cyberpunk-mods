-- Send money's section of the CET window, for a partner who isn't nearby (or
-- whose peer id you type in).

local NightCoop = require("core/nightcoop")
local Money = require("tweaks/sendmoney/money")

local Window = {}

local REFRESH_SECONDS = 0.5
local MAX_LOG = 6

local ui = {
    amount = 1000,
    peer = nil,         -- recipient picked in the list
    manual = false,     -- recipient typed in by peer id instead
    manualPeer = 1,
    confirm = false,
    lastRefresh = -math.huge,
    remotes = {},
    balance = 0,
    log = {},
}

local function addLog(text)
    table.insert(ui.log, 1, os.date("%H:%M:%S") .. "  " .. text)
    while #ui.log > MAX_LOG do
        table.remove(ui.log)
    end
end

local function refresh(session)
    local now = os.clock()
    if now - ui.lastRefresh < REFRESH_SECONDS then
        return
    end
    ui.lastRefresh = now
    ui.balance = Money.Balance()
    ui.remotes = NightCoop.Remotes(session.peerId)

    if not ui.manual and #ui.remotes == 1 then
        ui.peer = ui.remotes[1].id
    end
end

-- Sends and notes the outcome in the window. Returns what was requested, plus
-- the summary line when not all of it went.
function Window.Send(peer, amount)
    local requested, line, complete = Money.Send(peer, amount)
    addLog(line)
    ui.lastRefresh = -math.huge
    if complete then
        return requested
    end
    return requested, line
end

local function recipient()
    if ui.manual then
        return ui.manualPeer
    end
    return ui.peer
end

local function drawRecipients()
    ImGui.Text("Send to:")
    for _, r in ipairs(ui.remotes) do
        local label = NightCoop.PeerLabel(r.id)
        if r.distance then
            label = label .. string.format("  -  %d m away", math.floor(r.distance + 0.5))
        end
        if ImGui.RadioButton(label, not ui.manual and ui.peer == r.id) then
            ui.peer = r.id
            ui.manual = false
            ui.confirm = false
        end
    end
    if ImGui.RadioButton("Peer id:", ui.manual) then
        ui.manual = true
        ui.confirm = false
    end
    ImGui.SameLine()
    ImGui.PushItemWidth(90)
    local value, changed = ImGui.InputInt("##manualPeer", ui.manualPeer, 1, 1)
    ImGui.PopItemWidth()
    if changed then
        ui.manualPeer = math.max(0, value)
        ui.manual = true
        ui.confirm = false
    end
    if #ui.remotes == 0 then
        ImGui.TextWrapped("No partner positions coming in right now. The host is peer 0, guests are 1 and up.")
    end
end

local function drawAmount()
    ImGui.PushItemWidth(160)
    local value, changed = ImGui.InputInt("Amount", ui.amount, 100, 1000)
    ImGui.PopItemWidth()
    if changed then
        ui.amount = math.max(0, value)
        ui.confirm = false
    end
    for i, step in ipairs({ 100, 1000, 10000 }) do
        if i > 1 then
            ImGui.SameLine()
        end
        if ImGui.Button("+" .. Money.Thousands(step)) then
            ui.amount = ui.amount + step
            ui.confirm = false
        end
    end
    ImGui.SameLine()
    if ImGui.Button("All") then
        ui.amount = ui.balance
        ui.confirm = false
    end
    ImGui.SameLine()
    if ImGui.Button("Clear") then
        ui.amount = 0
        ui.confirm = false
    end
end

local function drawSend(session)
    local peer = recipient()
    local problem
    if peer == nil then
        problem = "Pick who to send to."
    elseif session.peerId == peer then
        problem = "That's you."
    elseif ui.amount <= 0 then
        problem = "Enter an amount."
    elseif ui.amount > ui.balance then
        problem = "You only have " .. Money.Eddies(ui.balance) .. "."
    end

    if problem then
        ImGui.TextColored(1, 0.75, 0.3, 1, problem)
        ui.confirm = false
        return
    end

    local label = NightCoop.PeerLabel(peer)
    if not ui.confirm then
        if ImGui.Button("Send " .. Money.Eddies(ui.amount) .. " to " .. label) then
            ui.confirm = true
        end
        return
    end

    ImGui.Text("Send " .. Money.Eddies(ui.amount) .. " to " .. label .. "?")
    if ImGui.Button("Confirm") then
        ui.confirm = false
        Window.Send(peer, ui.amount)
    end
    ImGui.SameLine()
    if ImGui.Button("Cancel") then
        ui.confirm = false
    end
end

function Window.Draw(session)
    if not (session and session.connected) then
        ImGui.TextWrapped("Needs a co-op session.")
        ui.confirm = false
        return
    end
    refresh(session)

    ImGui.Text("Balance: " .. Money.Eddies(ui.balance))
    drawRecipients()
    ImGui.Spacing()
    drawAmount()
    ImGui.Spacing()
    drawSend(session)

    if #ui.log > 0 then
        ImGui.Separator()
        for _, line in ipairs(ui.log) do
            ImGui.TextWrapped(line)
        end
    end
end

-- The window was opened: show fresh numbers rather than the last ones.
function Window.Opened()
    ui.lastRefresh = -math.huge
end

function Window.Closed()
    ui.confirm = false
end

return Window
