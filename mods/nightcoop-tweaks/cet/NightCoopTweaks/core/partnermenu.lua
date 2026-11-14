-- A partner's menu: a choice list of what the tweaks offer for that partner
-- ("Send money", ...). The phone's Contacts open it, wherever the partner is.
--
-- A tweak adds its entry in its Init:
--
--   PartnerMenu.Add({
--       label = "Send money",
--       available = function(peer) return true end, -- optional
--       open = function(menu) ... end,
--   })
--
-- `open` gets a menu for this partner: `menu.peer` is their peer id, and
--   menu.Show(title, labels, onPick)  shows the tweak's own list; onPick(index) gets the 1-based pick
--   menu.Back()                       goes back to the partner's list
--   menu.Close()                      closes it all
--   menu.Await()                      hides the list while the tweak shows a popup;
--                                     call Show, Back or Close when the popup is done
--                                     (a list comes back a moment later, once the popup has gone)
-- The menu closes on its own when the partner leaves the session; after that
-- its functions do nothing, so a late callback can't reopen it.
--
-- PartnerMenu.OpenFor(peer) opens the partner's list, in a car too.

local Choices = require("core/choices")
local NightCoop = require("core/nightcoop")
local Notify = require("core/notify")

local PartnerMenu = {}

local SCAN_SECONDS = 0.1
local PENDING_SECONDS = 3.0 -- how long OpenFor waits for the phone or a menu to close
local SETTLE_SECONDS = 0.5  -- and then how long it lets the phone, or a tweak's popup, finish closing

local entries = {}
local state = nil   -- nil, "open" (a list is up) or "away" (a tweak's popup is)
local peer = nil
local pending = nil     -- { peer, at }: an OpenFor waiting for the phone to close
local lastOpening = nil -- what became of the last OpenFor, for diagnostics
local current = nil -- the menu handed to the open entry
local listed = nil  -- the list the menu shows: { title, labels, onPick }, put back if it goes missing
local putBack = 0   -- how often it had to be, for diagnostics
local settling = nil -- { show, at }: what to show once a tweak's popup that just closed has gone
local lastScan = -math.huge
local headline = nil -- what the menu is doing, or the last thing that happened to it; logged when it changes

local showList

function PartnerMenu.Add(entry)
    table.insert(entries, entry)
end

-- Opens `peerId`'s list as soon as nothing is in the way (the phone that
-- asked has closed), wherever they are.
function PartnerMenu.OpenFor(peerId)
    pending = { peer = peerId, at = os.clock() }
    lastOpening = string.format("asked for %s, waiting for the phone to close", NightCoop.PeerLabel(peerId))
end

-- Shows a list and remembers it, so Update can put it back.
local function display(title, labels, onPick)
    listed = { title = title, labels = labels, onPick = onPick }
    Choices.Show(title, labels, onPick)
end

local function setHeadline(text)
    if text ~= headline then
        headline = text
        spdlog.info("partner menu: " .. text)
    end
end

local function close(why)
    state, peer, current, listed, settling = nil, nil, nil, nil, nil
    Choices.Hide()
    setHeadline(why and ("closed, " .. why) or "closed")
end

-- Runs `show` now, or, when a tweak's popup is what asked, from Update once the
-- popup has gone: it asks from the popup's own close callback, with the popup
-- still coming off the screen.
local function showWhenClear(show)
    if state == "away" then
        settling = { show = show, at = os.clock() }
    else
        show()
    end
end

local function availableEntries()
    local list = {}
    for _, entry in ipairs(entries) do
        if not entry.available or entry.available(peer) then
            table.insert(list, entry)
        end
    end
    return list
end

local function newMenu()
    local menu = { peer = peer }
    local function live()
        return current == menu
    end
    function menu.Show(title, labels, onPick)
        if live() then
            showWhenClear(function()
                state = "open"
                display(title, labels, onPick)
            end)
        end
    end
    function menu.Back()
        if live() then
            showWhenClear(showList)
        end
    end
    function menu.Close()
        if live() then
            close()
        end
    end
    function menu.Await()
        if live() then
            state = "away"
            listed = nil
            Choices.Hide()
            setHeadline("waiting for a tweak's popup, for " .. NightCoop.PeerLabel(peer))
        end
    end
    return menu
end

-- The partner's list: every available entry, then "Never mind".
function showList()
    state = "open"
    current = nil
    local list = availableEntries()
    local labels = {}
    for _, entry in ipairs(list) do
        table.insert(labels, entry.label)
    end
    table.insert(labels, "Never mind")
    display(NightCoop.PeerLabel(peer), labels, function(choice)
        local entry = list[choice]
        if not entry then
            close()
            return
        end
        current = newMenu()
        entry.open(current)
    end)
end

local function inVehicle(player)
    local ok, vehicle = pcall(function() return Game.GetMountedVehicle(player) end)
    return ok and vehicle ~= nil
end

-- Why the player is busy with the story or a device, or nil: the game's scene
-- tiers 2 to 5 (staged walks, seats, cinematics; the game holds gameplay back
-- from tier 2); working a device (a drone, camera or turret) or zoomed into its
-- screen, which can be tier 1 (q104's drone) and where the game turns the phone
-- off too; or a workspot (a seat, a lean).
local function busyReason(player)
    local ok, why = pcall(function()
        local psm = player:GetPlayerStateMachineBlackboard()
        local def = Game.GetAllBlackboardDefs().PlayerStateMachine
        local tier = psm:GetInt(def.HighLevel)
        if tier >= EnumInt(gamePSMHighLevel.SceneTier2) and tier <= EnumInt(gamePSMHighLevel.SceneTier5) then
            return string.format("in a scene (tier %d)", tier)
        elseif psm:GetBool(def.IsControllingDevice) then
            return "controlling a device (a drone, camera or turret)"
        elseif psm:GetBool(def.IsUIZoomDevice) then
            return "zoomed into a device's screen"
        elseif StatusEffectSystem.ObjectHasStatusEffectWithTag(player, "VehicleScene") then
            -- a ride of the story, where the game won't let us out; F can be its "Skip Ride"
            return "the car is in a scene"
        end
        return nil
    end)
    if ok and why then
        return why
    end
    if inVehicle(player) then
        return nil -- a car's seat is a workspot too, and cars have their own rule
    end
    local seated
    ok, seated = pcall(function() return Game.GetWorkspotSystem():IsActorInWorkspot(player) end)
    if ok and seated then
        return "in a workspot (seated or leaning)"
    end
    return nil
end

local function inMenu()
    local defs = Game.GetAllBlackboardDefs()
    return Game.GetBlackboardSystem():Get(defs.UI_System):GetBool(defs.UI_System.IsInMenu)
end

local function phoneOpen()
    local defs = Game.GetAllBlackboardDefs()
    return Game.GetBlackboardSystem():Get(defs.UI_ComDevice):GetBool(defs.UI_ComDevice.ContactsActive)
end

-- What the partner menu is doing, line by line.
function PartnerMenu.Explain()
    local lines = { headline or "closed" }
    if lastOpening then
        table.insert(lines, "Last opening: " .. lastOpening)
    end
    if putBack > 0 then
        table.insert(lines, string.format("Lists put back after going missing: %d", putBack))
    end
    return lines
end

local function remoteById(remotes, id)
    for _, remote in ipairs(remotes) do
        if remote.id == id then
            return remote
        end
    end
    return nil
end

function PartnerMenu.Update()
    if state == "away" then
        if not settling or os.clock() - settling.at < SETTLE_SECONDS then
            return
        end
        local show = settling.show
        settling = nil
        show()
    end
    if not Choices.Recheck() then
        close("a conversation of the game took over")
    end
    if not state and not pending then
        return
    end

    local now = os.clock()
    if now - lastScan < SCAN_SECONDS then
        return
    end
    lastScan = now

    local player = Game.GetPlayer()
    local session = player and NightCoop.Session()
    local busy = player and busyReason(player)
    local blocked
    if #entries == 0 then
        blocked = "no tweak adds an entry"
    elseif not session then
        blocked = "NightCoop isn't answering"
    elseif not session.connected then
        blocked = "not in a co-op session"
    elseif inMenu() then
        blocked = "a menu is open"
    elseif busy then
        blocked = busy
    elseif player:IsInCombat() then
        -- our list counts as a conversation, and the game holds back consumables and grenades during one
        blocked = "in combat"
    elseif Choices.GameDialogOpen() then
        blocked = "the game has a choice list up: " .. Choices.Describe()
    end

    if pending then
        local waitingOn = (phoneOpen() and "the phone") or (inMenu() and "a menu")
        if waitingOn then
            pending.clearAt = nil
            if now - pending.at > PENDING_SECONDS then
                pending = nil
                lastOpening = string.format("dropped: %s was still open after %.0f s", waitingOn, PENDING_SECONDS)
            end
        elseif not pending.clearAt or now - pending.clearAt < SETTLE_SECONDS then
            -- the phone tidies the HUD as it closes; opening in the middle of that lost the list
            pending.clearAt = pending.clearAt or now
        else
            local wanted = pending.peer
            pending = nil
            if blocked then
                lastOpening = "refused: " .. blocked
                setHeadline("refused, " .. blocked)
                Notify.Toast("The partner menu can't open now: " .. blocked)
            else
                close()
                peer = wanted
                showList()
                lastOpening = "opened for " .. NightCoop.PeerLabel(wanted)
            end
        end
    end

    if blocked then
        if state then
            close(blocked)
        end
        return
    end
    if not state then
        return -- still waiting for the phone to close
    end

    -- Something took our list off the screen while the menu is open: put it back.
    if listed and state == "open" and not Choices.Shown() then
        putBack = putBack + 1
        Choices.Show(listed.title, listed.labels, listed.onPick)
    end

    -- The partner only has to stay in the session.
    if not remoteById(NightCoop.Remotes(session.peerId), peer) then
        close("the partner left")
        return
    end
    setHeadline("open for " .. NightCoop.PeerLabel(peer))
end

function PartnerMenu.Shutdown()
    close()
end

return PartnerMenu
