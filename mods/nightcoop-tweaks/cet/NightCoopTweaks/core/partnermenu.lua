-- Walk up to a partner and look at them: "[F] Interact" opens a choice list
-- of what the tweaks offer for that partner ("Send money", ...).
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
-- The menu closes on its own when the partner walks off; after that its
-- functions do nothing, so a late callback can't reopen it.
--
-- PartnerMenu.OpenFor(peer) opens the partner's list from afar (the phone's
-- contacts do): no prompt, no walking off, and it works in a car.

local Choices = require("core/choices")
local NightCoop = require("core/nightcoop")
local Notify = require("core/notify")

local PartnerMenu = {}

local REACH = 1.0          -- metres from us to the partner for the prompt (the user found 3 m too far)
local BODY_MATCH = 1.5     -- metres between the looked-at body and NightCoop's position of that peer
local FACING = 0.94        -- cos 20 degrees: how straight we face a partner within REACH, across the ground
local LEAVE = 5.0          -- metres: the menu closes when the partner is farther than this
local STACKED = 0.3        -- metres: a partner this close stands on our spot, where a scene that places every player puts them
local PROMPT_GRACE = 0.4   -- seconds the prompt stays after we look away, so it doesn't flicker
local SCAN_SECONDS = 0.1
local PENDING_SECONDS = 3.0 -- how long OpenFor waits for the phone or a menu to close
local SETTLE_SECONDS = 0.5  -- and then how long it lets the phone finish closing

local entries = {}
local state = nil   -- nil, "prompt", "open" (a list is up) or "away" (a tweak's popup is)
local peer = nil
local fromAfar = false -- opened by OpenFor: the partner needn't be near
local pending = nil    -- { peer, at }: an OpenFor waiting for the phone to close
local afar = nil       -- what became of the last OpenFor, for diagnostics
local current = nil -- the menu handed to the open entry
local listed = nil  -- the list the menu shows: { title, labels, onPick }, put back if it goes missing
local putBack = 0   -- how often it had to be, for diagnostics
local lookedAt = -math.huge
local lastScan = -math.huge
local seen = {}     -- what the last scan saw, for the window's Diagnostics
local headline = nil -- why the menu is off, or what it's doing; logged when it changes

local showList

function PartnerMenu.Add(entry)
    table.insert(entries, entry)
end

-- Opens `peerId`'s list as soon as nothing is in the way (the phone that
-- asked has closed), wherever they are.
function PartnerMenu.OpenFor(peerId)
    pending = { peer = peerId, at = os.clock() }
    afar = string.format("asked for %s, waiting for the phone to close", NightCoop.PeerLabel(peerId))
end

-- Shows a list and remembers it, so Update can put it back.
local function display(title, labels, onPick)
    listed = { title = title, labels = labels, onPick = onPick }
    Choices.Show(title, labels, onPick)
end

local function close()
    state, peer, current, fromAfar, listed = nil, nil, nil, false, nil
    Choices.Hide()
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
            state = "open"
            display(title, labels, onPick)
        end
    end
    function menu.Back()
        if live() then
            showList()
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

local function showPrompt()
    state = "prompt"
    current = nil
    display(NightCoop.PeerLabel(peer), { "Interact" }, function()
        showList()
    end)
end

local function inVehicle(player)
    local ok, vehicle = pcall(function() return Game.GetMountedVehicle(player) end)
    return ok and vehicle ~= nil
end

-- Why the player is busy with the story or a device, or nil: the game's scene
-- tiers 2 to 5 (staged walks, seats, cinematics; the game holds gameplay back
-- from tier 2), where NightCoop stands every partner on our spot; working a
-- device (a drone, camera or turret) or zoomed into its screen, which can be
-- tier 1 (q104's drone) and where the game turns the phone off too; or a
-- workspot (a seat, a lean).
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

local function setHeadline(text)
    if text ~= headline then
        headline = text
        spdlog.info("partner menu: " .. text)
    end
end

local function notePartners(remotes)
    local list = {}
    for _, remote in ipairs(remotes) do
        if remote.distance and remote.distance < STACKED then
            table.insert(list, string.format("%s %.1f m (on our spot, left out)", NightCoop.PeerLabel(remote.id), remote.distance))
        elseif remote.distance then
            table.insert(list, string.format("%s %.1f m", NightCoop.PeerLabel(remote.id), remote.distance))
        else
            table.insert(list, NightCoop.PeerLabel(remote.id) .. " (no position)")
        end
    end
    table.insert(seen, "Partners: " .. (#list > 0 and table.concat(list, ", ") or "none, by NightCoop"))
end

-- The game's look-at target, when it's the body of a partner up close.
local function lookAtMatch(player, remotes)
    local target = Game.GetTargetingSystem():GetLookAtObject(player, false, false)
    if not target then
        table.insert(seen, "Looking at: nothing the game can target")
        return nil
    end
    local there = target:GetWorldPosition()
    local away = NightCoop.Distance(player:GetWorldPosition(), there)
    local nearest, nearestDistance
    for _, remote in ipairs(remotes) do
        if remote.pos then
            local distance = NightCoop.Distance(remote.pos, there)
            if not nearestDistance or distance < nearestDistance then
                nearest, nearestDistance = remote, distance
            end
        end
    end
    local line = string.format("Looking at: %s, %.1f m away", Game.NameToString(target:GetClassName()), away)
    if nearest then
        line = line .. string.format(", %.1f m from where NightCoop puts %s", nearestDistance, NightCoop.PeerLabel(nearest.id))
    end
    table.insert(seen, line)
    if away <= REACH and nearest and nearestDistance <= BODY_MATCH then
        return nearest.id
    end
    return nil
end

-- How straight the camera faces `pos` across the ground, as a cosine (1 is dead on).
local function facing(pos, here, forward)
    local dx, dy = pos.x - here.x, pos.y - here.y
    local length = math.sqrt(dx * dx + dy * dy)
    local flat = math.sqrt(forward.x * forward.x + forward.y * forward.y)
    if length < 0.2 then
        return 1 -- right above or below us (one on our spot is left out before this)
    end
    if flat < 0.3 then
        return 0 -- looking at the sky or our feet
    end
    return (dx * forward.x + dy * forward.y) / (length * flat)
end

-- The partner up close that the camera faces most straight.
local function facingMatch(player, remotes)
    local here = player:GetWorldPosition()
    local forward = Game.GetCameraSystem():GetActiveCameraForward()
    local best, bestDot
    for _, remote in ipairs(remotes) do
        if remote.pos and remote.distance and remote.distance <= REACH then
            local dot = facing(remote.pos, here, forward)
            if not bestDot or dot > bestDot then
                best, bestDot = remote, dot
            end
        end
    end
    if not best then
        table.insert(seen, string.format("Facing: no partner within %.0f m", REACH))
        return nil
    end
    table.insert(seen, string.format("Facing: %s, %.1f m away, %.0f degrees off", NightCoop.PeerLabel(best.id), best.distance, math.deg(math.acos(math.max(-1, math.min(1, bestDot))))))
    if bestDot >= FACING then
        return best.id
    end
    return nil
end

-- The partners not on our spot. A scene that places every player puts them all
-- on one spot, so a partner inside us is one NightCoop stacked there (it hides
-- their body, "one spawn point for both"), not someone we stand facing.
local function apart(remotes)
    local list = {}
    for _, remote in ipairs(remotes) do
        if not (remote.distance and remote.distance < STACKED) then
            table.insert(list, remote)
        end
    end
    return list
end

-- The partner we look at up close: the game's look-at target on their body, or
-- else the one we face within REACH. A partner in another world has no body
-- here, but money and the like go through the host, so a prompt for them works.
local function lookedAtPeer(player, remotes)
    local matched = lookAtMatch(player, remotes)
    local ok, faced = pcall(facingMatch, player, remotes)
    if not ok then
        table.insert(seen, "Facing: " .. tostring(faced))
        faced = nil
    end
    return matched or faced
end

-- What the partner menu saw on its last look around, line by line.
function PartnerMenu.Explain()
    local lines = { headline or "Not running yet" }
    if afar then
        table.insert(lines, "From afar: " .. afar)
    end
    if putBack > 0 then
        table.insert(lines, string.format("Lists put back after going missing: %d", putBack))
    end
    if state == "away" then
        table.insert(lines, "Waiting for a tweak's popup")
        return lines
    end
    for _, line in ipairs(seen) do
        table.insert(lines, line)
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
        return
    end
    if not Choices.Recheck() then -- a conversation of the game took over
        state, peer, current, fromAfar, listed = nil, nil, nil, false, nil
    end

    local now = os.clock()
    if now - lastScan < SCAN_SECONDS then
        return
    end
    lastScan = now

    seen = {}
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
                afar = string.format("dropped: %s was still open after %.0f s", waitingOn, PENDING_SECONDS)
            end
        elseif not pending.clearAt or now - pending.clearAt < SETTLE_SECONDS then
            -- the phone tidies the HUD as it closes; opening in the middle of that lost the list
            pending.clearAt = pending.clearAt or now
        else
            local wanted = pending.peer
            pending = nil
            if blocked then
                afar = "refused: " .. blocked
                Notify.Toast("The partner menu can't open now: " .. blocked)
            else
                close()
                peer, fromAfar = wanted, true
                showList()
                afar = "opened for " .. NightCoop.PeerLabel(wanted)
            end
        end
    end

    -- In a car only the phone opens the menu: partners in their seats are all
    -- within REACH, so the prompt would come up at every glance at them.
    if not blocked and not fromAfar and inVehicle(player) then
        blocked = "in a vehicle (the phone's contacts still open it)"
    end

    if blocked then
        setHeadline("off, " .. blocked)
        if state then
            close()
        end
        return
    end

    -- Something took our list off the screen while the menu is open: put it back.
    if listed and (state == "open" or state == "prompt") and not Choices.Shown() then
        putBack = putBack + 1
        Choices.Show(listed.title, listed.labels, listed.onPick)
    end

    local remotes = NightCoop.Remotes(session.peerId)
    notePartners(remotes)

    if fromAfar and state then
        -- opened from the phone: the partner only has to stay in the session
        if not remoteById(remotes, peer) then
            close()
            setHeadline("closed, the partner left")
            return
        end
        setHeadline("open for " .. NightCoop.PeerLabel(peer) .. ", from afar")
        return
    end

    if state == nil or state == "prompt" then
        local looked = lookedAtPeer(player, apart(remotes))
        if looked then
            lookedAt = now
            if state ~= "prompt" or looked ~= peer then
                peer = looked
                showPrompt()
            end
        elseif state == "prompt" and now - lookedAt > PROMPT_GRACE then
            close()
        end
        setHeadline(state == "prompt" and ("prompt for " .. NightCoop.PeerLabel(peer)) or "watching for a partner up close")
        return
    end

    -- With a list up the partner only has to stay close.
    local remote = remoteById(remotes, peer)
    if not remote or not remote.distance or remote.distance > LEAVE then
        close()
        setHeadline("closed, the partner walked off")
        return
    end
    setHeadline("open for " .. NightCoop.PeerLabel(peer))
end

function PartnerMenu.Shutdown()
    close()
end

return PartnerMenu
