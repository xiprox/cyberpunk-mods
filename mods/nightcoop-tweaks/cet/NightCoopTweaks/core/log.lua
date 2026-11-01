-- Problems the player should see now. CET writes the mod's log out only now
-- and then, so a problem also goes to the CET console at once and to the
-- window's Diagnostics.

local Log = { problems = {} }

local reported = {} -- text -> true, so a problem that repeats every frame shows once

function Log.Problem(text)
    if reported[text] then
        return
    end
    reported[text] = true
    table.insert(Log.problems, text)
    spdlog.error(text)
    print("[NightCoop Tweaks] " .. text)
end

return Log
