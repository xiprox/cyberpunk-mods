-- A choice list like the game's "[F] Talk" ones, drawn by the game's own dialog
-- widget. The list lives on the UIInteractions blackboard, where that widget
-- reads it (and where the game sees a choice list is up, so the mouse wheel
-- doesn't switch weapons). The game's interaction system doesn't know about the
-- list, so this module reads F and the scroll keys itself (through core/input).

local Input = require("core/input")

local Choices = {}

local HUB_ID = 4997715 -- an id the game's own hubs don't use
local TAP_SECONDS = 0.35 -- a longer F is a hold (NightCoop's "hold F to help up"), not a pick
local TAP_SECONDS_IN_VEHICLE = 0.25 -- F held for 0.3 s gets out of the car, so a pick ends before that
local STALE_PRESS = 2.0  -- seconds after which a press whose release we missed is forgotten
local RECHECK_SECONDS = 0.25
-- F is both ChoiceApply (the conversation lists') and Choice1 (the "[F] Open" prompts');
-- NightCoop watches ChoiceApply for its dialog votes, so either one picks.
local INPUT_ACTIONS = { "ChoiceApply", "Choice1", "Choice1_Release", "ChoiceScrollUp", "ChoiceScrollDown" }
local APPLY = { ChoiceApply = true, Choice1 = true, Choice1_Release = true }
-- UI_MoveUp/Down are bound to W/S/Q/E too; only the wheel, arrows and d-pad scroll the list
local SCROLL_KEYS = {
    [236] = true, [237] = true, -- IK_MouseWheelUp, IK_MouseWheelDown
    [38] = true, [40] = true,   -- IK_Up, IK_Down
    [142] = true, [143] = true, -- IK_Pad_DigitUp, IK_Pad_DigitDown
}

local shown = nil -- { title, choices = { label, ... }, selected (0-based), onPick(index) }
local pressedAt
local lastRecheck = -math.huge

local function interactions()
    local defs = Game.GetAllBlackboardDefs()
    return Game.GetBlackboardSystem():Get(defs.UIInteractions), defs.UIInteractions
end

local function buildHubs()
    local hubs = gameinteractionsvisDialogChoiceHubs.new()
    if not shown then
        return hubs
    end
    local hub = gameinteractionsvisListChoiceHubData.new()
    hub.id = HUB_ID
    hub.title = shown.title
    hub.activityState = gameinteractionsvisEVisualizerActivityState.Active
    local choices = {}
    for _, label in ipairs(shown.choices) do
        local choice = gameinteractionsvisListChoiceData.new()
        choice.localizedName = label
        choice.inputActionName = CName.new("None")
        table.insert(choices, choice)
    end
    hub.choices = choices
    hubs.choiceHubs = { hub }
    return hubs
end

local function write()
    local bb, def = interactions()
    bb:SetVariant(def.DialogChoiceHubs, ToVariant(buildHubs()))
    bb:SetInt(def.ActiveChoiceHubID, shown and HUB_ID or -1)
    bb:SetInt(def.SelectedIndex, shown and shown.selected or 0)
end

-- Whose choice list is on the blackboard: "ours", "game" (a real dialog), or "none".
local function owner()
    local bb, def = interactions()
    local ok, hubs = pcall(FromVariant, bb:GetVariant(def.DialogChoiceHubs))
    if not ok or not hubs or not hubs.choiceHubs or #hubs.choiceHubs == 0 then
        return "none"
    end
    for _, hub in ipairs(hubs.choiceHubs) do
        if hub.id ~= HUB_ID then
            return "game"
        end
    end
    return "ours"
end

local function isScrollKey(action)
    local keys = Input.Keys(action)
    if not keys then
        return true
    end
    for _, key in ipairs(keys) do
        if SCROLL_KEYS[key] then
            return true
        end
    end
    return false
end

local function tapSeconds()
    local ok, vehicle = pcall(function() return Game.GetMountedVehicle(Game.GetPlayer()) end)
    return ok and vehicle and TAP_SECONDS_IN_VEHICLE or TAP_SECONDS
end

local function onKey(name, kind, action)
    if not shown then
        return
    end

    if APPLY[name] then
        local now = os.clock()
        if kind == "BUTTON_RELEASED" or name == "Choice1_Release" then
            if pressedAt then
                local held = now - pressedAt
                pressedAt = nil
                if held <= tapSeconds() then
                    shown.onPick(shown.selected + 1)
                end
            end
        elseif kind == "BUTTON_PRESSED" and (not pressedAt or now - pressedAt > STALE_PRESS) then
            -- one F comes as ChoiceApply and Choice1 both: the first press and release count
            pressedAt = now
        end
        return
    end

    if kind == "BUTTON_PRESSED" and isScrollKey(action) then
        local step = name == "ChoiceScrollUp" and -1 or 1
        local selected = math.max(0, math.min(#shown.choices - 1, shown.selected + step))
        if selected ~= shown.selected then
            shown.selected = selected
            local bb, def = interactions()
            bb:SetInt(def.SelectedIndex, selected)
        end
    end
end

-- True while the game itself has a choice list up (a conversation, a scene).
function Choices.GameDialogOpen()
    return owner() == "game"
end

-- Our list and the lists on screen, for diagnostics.
function Choices.Explain()
    local lines = {}
    if shown then
        table.insert(lines, string.format("Our list: '%s', %d choices, choice %d selected", shown.title, #shown.choices, shown.selected + 1))
    else
        table.insert(lines, "Our list: none")
    end
    table.insert(lines, "Lists on screen: " .. Choices.Describe())
    return lines
end

-- The choice lists on the blackboard, for diagnostics: each one's id, title
-- and number of choices, or "none".
function Choices.Describe()
    local bb, def = interactions()
    local ok, hubs = pcall(FromVariant, bb:GetVariant(def.DialogChoiceHubs))
    if not ok or not hubs or not hubs.choiceHubs or #hubs.choiceHubs == 0 then
        return "none"
    end
    local list = {}
    for _, hub in ipairs(hubs.choiceHubs) do
        local whose = hub.id == HUB_ID and "ours " or ""
        table.insert(list, string.format("%s#%d '%s' (%d choices)", whose, hub.id, tostring(hub.title), #hub.choices))
    end
    return table.concat(list, ", ")
end

function Choices.Shown()
    return shown ~= nil
end

-- Shows `choices` under `title`; `onPick(index)` gets the 1-based choice picked
-- with F. Returns false while the game has a conversation of its own up.
function Choices.Show(title, choices, onPick, selected)
    if owner() == "game" then
        return false
    end
    shown = { title = title, choices = choices, onPick = onPick, selected = selected or 0 }
    pressedAt = nil
    write()
    return true
end

function Choices.Hide()
    if not shown then
        return
    end
    shown = nil
    pressedAt = nil
    if owner() ~= "game" then
        write()
    end
end

-- Every frame from whoever shows lists: puts the list back if the game cleared
-- it, and steps aside for a real dialog. Returns false when a real dialog took over.
function Choices.Recheck()
    if not shown then
        return true
    end
    local now = os.clock()
    if now - lastRecheck < RECHECK_SECONDS then
        return true
    end
    lastRecheck = now

    local who = owner()
    if who == "game" then
        shown = nil
        return false
    end
    local bb, def = interactions()
    if who == "none" or bb:GetInt(def.ActiveChoiceHubID) ~= HUB_ID or bb:GetInt(def.SelectedIndex) ~= shown.selected then
        write()
    end
    return true
end

function Choices.Init()
    Input.Listen(INPUT_ACTIONS, onKey)
end

function Choices.Shutdown()
    Choices.Hide()
end

return Choices
