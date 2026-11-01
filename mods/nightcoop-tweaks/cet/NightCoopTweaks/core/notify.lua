-- Telling the player something: the game's on-screen message, and the mod's log.

local Notify = {}

-- A line in the middle of the screen for a few seconds, also written to the log.
function Notify.Toast(text)
    spdlog.info(text)
    pcall(function()
        local msg = gameSimpleScreenMessage.new()
        msg.isShown = true
        msg.duration = 4.0
        msg.message = text
        msg.isInstant = true
        local defs = Game.GetAllBlackboardDefs()
        Game.GetBlackboardSystem():Get(defs.UI_Notifications):SetVariant(defs.UI_Notifications.WarningMessage, ToVariant(msg), true)
    end)
end

return Notify
