-- The game's own progress bar, the one quests and quickhack uploads show in
-- the middle of the HUD ("transaction in progress"). HUDProgressBarController
-- draws whatever the UI_HUDProgressBar blackboard holds, so this sets it the
-- way the game does (rpgManager.script): Active, the texts, the message type
-- last, then the progress. Clearing Active plays the "completed" ending when
-- the bar is past 96%, and the "failed" one before that.

local ProgressBar = {}

local FULL_HOLD = 0.3   -- seconds the full bar stays before its "completed" ending
local FAIL_HOLD = 0.15  -- seconds before the "failed" ending

local job = nil -- { started, options, phase ("running", "ending"), endAt, progress }

local function blackboard()
    local defs = Game.GetAllBlackboardDefs()
    return Game.GetBlackboardSystem():Get(defs.UI_HUDProgressBar), defs.UI_HUDProgressBar
end

-- The message type is an enum in a Variant; without it the bar keeps the plain look.
local function setMessageType(bb, def, value)
    local attempts = {
        function() return ToVariant(value) end,
        function() return ToVariant(value, "gameSimpleMessageType") end,
    }
    for _, attempt in ipairs(attempts) do
        local ok, variant = pcall(attempt)
        if ok and variant then
            bb:SetVariant(def.MessageType, variant, true)
            return
        end
    end
end

local function setProgress(value)
    if job.progress and math.abs(job.progress - value) < 0.005 then
        return
    end
    job.progress = value
    local bb, def = blackboard()
    bb:SetFloat(def.Progress, value)
end

local function finish(succeeded, failedText)
    local bb, def = blackboard()
    if succeeded then
        setProgress(1.0)
        job.endAt = os.clock() + FULL_HOLD
    else
        if failedText then
            bb:SetString(def.FailedText, failedText, true)
        end
        job.endAt = os.clock() + FAIL_HOLD
    end
    job.phase = "ending"
end

-- True while a bar is up, ours or the game's.
function ProgressBar.Busy()
    if job then
        return true
    end
    local bb, def = blackboard()
    return bb:GetBool(def.Active)
end

-- Shows the bar until `options.check()` says "done" or "failed".
--   header     the title over the bar
--   detail     the line under it
--   done       its text when it completes
--   failed     its text when it fails; check() can return a second value to replace it
--   money      the eddies look
--   minSeconds how long it takes to fill at least
--   timeout    seconds after which it fails, with timeoutText as its failure text
--   check()    nil while waiting, "done" or "failed", plus an optional failure text
-- Returns false when a bar is already up (a quest's, or another of ours).
function ProgressBar.Start(options)
    if ProgressBar.Busy() then
        return false
    end
    job = { started = os.clock(), options = options, phase = "running" }
    local bb, def = blackboard()
    bb:SetBool(def.Active, true)
    bb:SetString(def.Header, options.header)
    bb:SetString(def.BottomText, options.detail or "", true)
    bb:SetString(def.FailedText, options.failed or "", true)
    bb:SetString(def.CompletedText, options.done or "", true)
    setMessageType(bb, def, options.money and gameSimpleMessageType.Money or gameSimpleMessageType.Neutral)
    setProgress(0.0)
    return true
end

-- Changes the line under the bar while it runs.
function ProgressBar.SetDetail(text)
    if job then
        local bb, def = blackboard()
        bb:SetString(def.BottomText, text, true)
    end
end

function ProgressBar.Update()
    if not job then
        return
    end
    local now = os.clock()
    if job.phase == "ending" then
        if now >= job.endAt then
            local bb, def = blackboard()
            bb:SetBool(def.Active, false)
            job = nil
        end
        return
    end

    local options = job.options
    local elapsed = now - job.started
    local result, failedText = options.check()
    if result == "failed" then
        finish(false, failedText)
    elseif elapsed > options.timeout then
        finish(false, options.timeoutText)
    elseif result == "done" and elapsed >= options.minSeconds then
        finish(true)
    else
        -- fills to 90% over minSeconds, then waits there for "done"
        setProgress(math.min(elapsed / options.minSeconds, 1.0) * 0.9)
    end
end

function ProgressBar.Shutdown()
    if job then
        local bb, def = blackboard()
        bb:SetBool(def.Active, false)
        job = nil
    end
end

return ProgressBar
