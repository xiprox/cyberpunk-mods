-- Development only (vehicle-customizer/RECORD.md): the automated test runner.
-- When TweakDB's VehicleCustomizerDev.autotest is true (dev/r6/tweaks/vehiclecustomizerdev/autotest.yaml, which
-- tools/run-autotest.ps1 installs for one run), it waits for the save the main menu continued to load, runs the
-- job named in VehicleCustomizerDev.job, and writes autotest-report.txt in this folder: one line per step,
-- "PASS"/"FAIL" lines for checks, "SHOT <name>" when the run script should take a screenshot, and "DONE" last.

local REPORT = "autotest-report.txt"

local runner = {
    enabled = false,
    job = nil,
    clock = 0,
    worldSince = nil,
    started = false,
    steps = nil,
    stepIndex = 0,
    waitUntil = 0,
    passes = 0,
    fails = 0,
}

local function write(line)
    local file = io.open(REPORT, "a")
    if file then
        file:write(os.date("%H:%M:%S "), line, "\n")
        file:close()
    end
    print("[VehicleCustomizerDev] " .. line)
end

local function check(name, ok, detail)
    if ok then
        runner.passes = runner.passes + 1
        write("PASS " .. name .. (detail and (" - " .. detail) or ""))
    else
        runner.fails = runner.fails + 1
        write("FAIL " .. name .. (detail and (" - " .. detail) or ""))
    end
end

local function shot(name)
    write("SHOT " .. name)
end

-- JSON text for one value: strings, numbers, booleans, nil and flat tables of those.
local function json(value)
    local kind = type(value)
    if kind == "string" then
        return '"' .. value:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub("\n", "\\n") .. '"'
    elseif kind == "number" or kind == "boolean" then
        return tostring(value)
    elseif kind == "table" then
        if #value > 0 or next(value) == nil then
            local parts = {}
            for _, v in ipairs(value) do
                table.insert(parts, json(v))
            end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        local parts = {}
        for k, v in pairs(value) do
            table.insert(parts, json(tostring(k)) .. ":" .. json(v))
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
end

local function try(action)
    local ok, result = pcall(action)
    if ok then
        return result
    end
    return nil
end

local function nameOf(cname)
    return try(function() return NameToString(cname) end) or tostring(cname)
end

-- Job "dump": every vehicle record in TweakDB with what the catalog generator needs from the game itself:
-- its entity file (as the hash the files are found by), look, localized name, kind and maker, and whether
-- the garage list has it. Written to vehicle-records.jsonl next to the report.
local function dumpVehicleRecords()
    local garage = {}
    for _, id in ipairs(try(function() return TweakDB:GetFlat("Vehicle.vehicle_list.list") end) or {}) do
        garage[tostring(id)] = true
    end
    local records = try(function() return TweakDB:GetRecords("gamedataVehicle_Record") end) or {}
    write("vehicle records in TweakDB: " .. #records)
    local file = io.open("vehicle-records.jsonl", "w")
    local written, withTemplate = 0, 0
    for _, record in ipairs(records) do
        local id = record:GetID()
        local name = try(function() return TDBID.ToStringDEBUG(id) end) or tostring(id)
        local template = try(function() return record:EntityTemplatePath() end)
        local templateHash = try(function() return tostring(ResRef.GetHash(template)) end)
            or try(function() return tostring(template.hash) end)
        local templateText = try(function() return ResRef.ToString(template) end) or tostring(template)
        local displayKey = try(function() return record:DisplayName() end)
        local display = try(function() return GetLocalizedTextByKey(displayKey) end)
            or try(function() return Game.GetLocalizedTextByKey(displayKey) end)
        local vehicleType = try(function() return tostring(record:Type():Type()) end)
            or try(function() return nameOf(record:Type():EnumName()) end)
        local typeName = try(function() return TDBID.ToStringDEBUG(record:Type():GetID()) end)
        local maker = try(function() return TDBID.ToStringDEBUG(record:Manufacturer():GetID()) end)
        local model = try(function() return TDBID.ToStringDEBUG(record:Model():GetID()) end)
        local entry = {
            name = name,
            template_hash = templateHash,
            template = templateText,
            look = try(function() return nameOf(record:AppearanceName()) end),
            display_key = displayKey and nameOf(displayKey) or nil,
            display = display,
            type = vehicleType,
            type_record = typeName,
            maker = maker,
            model = model,
            garage = garage[tostring(id)] or false,
        }
        if templateHash then
            withTemplate = withTemplate + 1
        end
        if file then
            file:write(json(entry), "\n")
        end
        written = written + 1
    end
    if file then
        file:close()
    end
    check("dump of vehicle records", written > 0 and withTemplate > 0,
        written .. " records written, " .. withTemplate .. " with an entity file hash")
end

-- Job "suite": the engine on one pool copy of the Hella, start to finish. The copy is spawned in front of V,
-- then each choice goes through the engine's own calls as the shop will make them, the engine's Verify checks
-- the car against the build after each, and a picture is taken. Then the game's reset on getting in, then the
-- garage: unlock, call, see it arrive in its build, send it away. Saving is locked for the run (NoSave.reds).
local S = {
    cat = "archer_hella__basic_01",
    -- Copy 3: the user plays with copy 1 (in their garage since 2026-11-06), the persistence jobs use copy 2.
    record = "Vehicle.vc_archer_hella__basic_01_3",
    suburban = "archer_hella__basic_suburban_1",
}

local function engine()
    return try(function() return Game.GetScriptableSystemsContainer():Get("VehicleCustomizer.VCEngine") end)
end

local function rid()
    return TweakDBID.new(S.record)
end

local function car()
    if not S.id then
        return nil
    end
    return try(function() return Game.FindEntityByID(S.id) end)
end

local function lookOf(v)
    if not v then
        return "(no car)"
    end
    local look = try(function() return v:GetCurrentAppearanceName() end)
    return look and (try(function() return look.value end) or nameOf(look)) or "?"
end

local function flat(path)
    return try(function() return TweakDB:GetFlat("VehicleCustomizer." .. S.cat .. "." .. path) end)
end

local function verify(name)
    local e, v = engine(), car()
    local result = (e and v) and (try(function() return e:Verify(v) end) or "Verify failed to run") or "no car"
    check(name, result:sub(1, 2) == "ok", lookOf(v) .. "; " .. result)
end

local function idHash(id)
    return id and (try(function() return tostring(id.hash) end) or tostring(id)) or nil
end

local function distanceToPlayer(v)
    local a = try(function() return v:GetWorldPosition() end)
    local b = try(function() return Game.GetPlayer():GetWorldPosition() end)
    if not a or not b then
        return 9999
    end
    return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
end

-- Runs a choice and waits for the car's look to change: every choice rebuilds the car by switching twins.
local function rebuilt(action)
    return function()
        local v = car()
        local before = lookOf(v)
        action(engine(), v)
        return {
            what = "the car to be rebuilt (look still " .. before .. ")",
            timeout = 12,
            test = function() return lookOf(car()) ~= before end,
        }
    end
end

local function isTwinOf(look, base)
    return look == base .. "__vc_a" or look == base .. "__vc_b"
end

-- V turns 30 degrees right first: in the user's save V stands beside their own car, which hid half the view.
local function turnV()
    local player = Game.GetPlayer()
    local pos = player:GetWorldPosition()
    local f = player:GetWorldForward()
    S.facing = math.atan2(-f.x, f.y) - math.rad(30)
    Game.GetTeleportationFacility():Teleport(player, pos, EulerAngles.new(0, 0, math.deg(S.facing)))
end

local function spawnCopy()
    local player = Game.GetPlayer()
    local pos = player:GetWorldPosition()
    local facing = S.facing or (function() local f = player:GetWorldForward() return math.atan2(-f.x, f.y) end)()
    local fx, fy = -math.sin(facing), math.cos(facing)
    local yaw = facing + math.pi / 2 -- side on to V, so the picture shows the whole car
    local spec = DynamicEntitySpec.new()
    spec.recordID = rid()
    local ahead = S.distance or 8
    spec.position = Vector4.new(pos.x + fx * ahead, pos.y + fy * ahead, pos.z + 0.2, 1)
    spec.orientation = Quaternion.new(0, 0, math.sin(yaw / 2), math.cos(yaw / 2))
    spec.alwaysSpawned = true
    spec.persistState = false
    spec.persistSpawn = false
    S.id = Game.GetDynamicEntitySystem():CreateEntity(spec)
    write("  spawned entity " .. tostring(idHash(S.id)) .. " " .. ahead .. " m ahead of V")
    return { what = "the copy to appear", timeout = 20, test = function() return car() ~= nil end }
end

local function suiteStart()
    local e = engine()
    check("engine is running", e ~= nil, e and e:GetNote() or "VehicleCustomizer.VCEngine not found")
    local cats = try(function() return TweakDB:GetFlat("VehicleCustomizer.catalogs") end) or {}
    -- 100 since 2026-11-06 night (the Nazare family, Johnny's Porsche, the Semimaru and the Legatus added).
    check("catalogs loaded by TweakXL", #cats == 100, #cats .. " catalogs")
    local styles = flat("styles") or {}
    check("the Hella's styles", #styles == 8, #styles .. " styles")
    local positions = flat("kit.police_9afe.positions")
    local p1 = positions and positions[1]
    check("a kit's positions read as vectors", p1 ~= nil and p1.x ~= nil,
        p1 and string.format("first at %.4f, %.4f, %.4f", p1.x, p1.y, p1.z) or tostring(positions))
    check("the pool copy's record exists", try(function() return TweakDB:GetRecord(S.record) end) ~= nil, S.record)
    local lock = try(function()
        return Game.GetScriptableSystemsContainer():Get("VehicleCustomizerDev.NoSaveDuringTests"):IsLocked()
    end)
    check("saving is locked for the run", lock == true, tostring(lock))
    local old = try(function() return Game.GetScriptableServiceContainer():GetService("VehicleCustomizerTest.KitService") end)
    check("the old test is out of the game", old == nil)
    try(function() Game.GetTimeSystem():SetGameTimeByHMS(18, 0, 0) end) -- softer light than noon for the pictures
    if e then
        e:SetBuildText(rid(), "")
    end
end

local function suiteCalled()
    local e = engine()
    S.oldHash = idHash(S.id)
    S.id = nil
    check("unlock the copy", e:Unlock(rid()) == true)
    -- Whether it comes is checked next; the game's answer to the call isn't to be trusted (persist_check).
    write("  the game answered " .. tostring(e:Call(rid())) .. " to the call")
    return {
        what = "the called copy to appear",
        timeout = 45,
        test = function()
            local id = e:GetEntityOf(rid())
            local hash = idHash(id)
            if hash and hash ~= "0" and hash ~= S.oldHash and try(function() return Game.FindEntityByID(id) end) then
                S.id = id
                return true
            end
            return false
        end,
    }
end

local SUITE = {
    { "engine, catalogs and save lock", suiteStart, 1 },
    { "turn V away from their own car", turnV, 2 },
    { "spawn the pool copy in front of V", spawnCopy, 5 },
    { "check the copy as it came", function()
        check("the copy is our record", try(function() return TDBID.ToStringDEBUG(car():GetRecordID()) end) == S.record)
        verify("copy as spawned")
        shot("01_as_spawned")
    end, 5 },
    { "choose the Suburban style", rebuilt(function(e, v) e:ChooseLook(v, CName.new(S.suburban)) end), 5 },
    { "check the Suburban style", function()
        check("Suburban look on a twin", isTwinOf(lookOf(car()), S.suburban), lookOf(car()))
        local seen = try(function() return engine():Diagnose(car()) end) or "Diagnose failed to run"
        check("the engine finds the Suburban style in the catalog", seen:find("style suburban_1", 1, true) ~= nil, seen)
        verify("Suburban style")
        shot("02_suburban")
    end, 5 },
    { "choose the junk front bumper", rebuilt(function(e, v)
        e:ChooseOption(v, CName.new("bumper_front.bumper"), CName.new("4f41bb5f")) end), 2 },
    { "choose the Quadra Turbo-R rims", rebuilt(function(e, v)
        e:ChooseOption(v, CName.new("wheel.wheel"), CName.new("307348bd")) end), 2 },
    { "choose the Quadra Turbo-R tires", rebuilt(function(e, v)
        e:ChooseOption(v, CName.new("wheel.tire"), CName.new("d184d620")) end), 5 },
    { "check the parts", function()
        verify("junk bumper, Turbo-R rims and tires")
        shot("03_parts")
    end, 5 },
    { "paint the whole car primer red", rebuilt(function(e, v) e:ChooseCarPaint(v, CName.new("primer_red")) end), 5 },
    { "check the paint", function()
        verify("whole car primer red")
        shot("04_primer_red")
    end, 5 },
    { "paint the hood stickerbomb_01", rebuilt(function(e, v)
        e:ChoosePaint(v, CName.new("hood_a.hood"), CName.new("stickerbomb_01")) end), 5 },
    { "check the hood", function()
        verify("hood stickerbomb_01 over the red")
        shot("05_hood")
    end, 5 },
    -- The police body is a slot now (Body: police), which the Suburban lacks: choosing it adds the part.
    { "add the police body (a slot the Suburban lacks)", rebuilt(function(e, v)
        e:ChooseOption(v, CName.new("base.body.police_body"), CName.new("df85ca17")) end), 2 },
    { "add the police light bar", rebuilt(function(e, v) e:ToggleKit(v, CName.new("police_9afe")) end), 2 },
    { "add the scavenger stickers", rebuilt(function(e, v) e:ToggleKit(v, CName.new("scavengers_00af")) end), 5 },
    { "check the kits", function()
        verify("police shell, light bar, scavenger stickers")
        shot("06_kits")
    end, 5 },
    { "lift the light bar 0.3 m and turn it 20 degrees", function()
        engine():MoveKit(car(), CName.new("police_9afe"), Vector4.new(0, 0, 0.3, 20))
    end, 3 },
    { "check the moved light bar", function()
        verify("light bar moved live")
        shot("07_moved")
    end, 5 },
    -- One part on its own (user, 2026-11-06): the light bar's first part, its spotlight.
    { "the spotlight alone: up 15 cm, pitched 20 and rolled 10 degrees", function()
        engine():NudgeKit(car(), CName.new("police_9afe"), 0, Vector4.new(0, 0, 0.15, 0), Vector4.new(20, 10, 0, 0))
    end, 3 },
    { "check the spotlight", function()
        verify("one kit part moved on its own")
        local text = engine():GetBuildText(rid())
        check("the part's move is saved", text:find("part=police_9afe:0:0:0:0.150:0:20:10", 1, true) ~= nil, text)
        shot("07b_part_moved")
    end, 5 },
    { "rebuild in place", rebuilt(function(e, v) e:Rebuild(v) end), 5 },
    { "check it all came through the rebuild", function()
        verify("after a rebuild in place")
        local text = engine():GetBuildText(rid())
        local x, y, z, w = text:match("kit=police_9afe:([^:;]*):([^:;]*):([^:;]*):([^:;]*)")
        local saved = x and math.abs(tonumber(x)) < 0.001 and math.abs(tonumber(y)) < 0.001
            and math.abs(tonumber(z) - 0.3) < 0.001 and math.abs(tonumber(w) - 20) < 0.01
        check("the light bar's offset is saved", saved == true, text)
        shot("08_rebuilt")
    end, 5 },
    { "the game's look reset, as when V gets in", function()
        S.lookBefore = lookOf(car())
        car():GetVehicleComponent():EnableCustomizableAppearance(false)
    end, 4 },
    { "check the look was kept", function()
        check("look kept against the reset", lookOf(car()) == S.lookBefore, S.lookBefore .. " -> " .. lookOf(car()))
        verify("after the reset")
    end, 1 },
    { "a co-op session's build arrives for this car (a partner's, not a change)", rebuilt(function(e, v)
        S.partnerBuild = "look=archer_hella__basic_poor_1;slot=bumper_back.bumper:da1ad5f5:;slot=base.body.police_body:df85ca17:"
        S.ownBefore = e:GetBuildText(v:GetRecordID())
        e:PutSessionBuild(v:GetRecordID(), S.partnerBuild, false, 1)
    end), 5 },
    { "check the car wears the session's build", function()
        check("partner's look on a twin", isTwinOf(lookOf(car()), "archer_hella__basic_poor_1"), lookOf(car()))
        check("the engine has the session's build", engine():HasSessionBuild(rid()) == true)
        check("our own saved build untouched", engine():GetBuildText(rid()) == S.ownBefore)
        verify("partner's build")
        shot("09_partner_build")
    end, 5 },
    { "the session ends: back to our own build", rebuilt(function(e, v)
        e:PutSessionBuild(v:GetRecordID(), "", false, 1)
    end), 5 },
    { "check our own build is back", function()
        check("our look again", isTwinOf(lookOf(car()), S.suburban), lookOf(car()))
        verify("our own build again")
    end, 1 },
    { "take the spawned copy away", function()
        Game.GetDynamicEntitySystem():DeleteEntity(S.id)
    end, 3 },
    { "unlock and call the copy", suiteCalled, 2 },
    { "wait for the called copy to drive up", function()
        -- Off-road (the user's save is in the Badlands) the summoned car is slow to come.
        -- How fast it comes is the game's summon, not the mod's, so a slow one is a note, not a failure.
        return { what = "the called copy to come within 30 m", timeout = 90, optional = true,
                 test = function() return car() and distanceToPlayer(car()) < 30 end }
    end, 5 },
    { "check the called copy", function()
        check("called copy in its build's look", isTwinOf(lookOf(car()), S.suburban), lookOf(car()))
        verify("called copy")
        shot("10_called")
    end, 5 },
    { "send it away and clear the build", function()
        engine():SendAway(rid())
        engine():SetBuildText(rid(), "")
    end, 2 },
}

-- Jobs "persist_save" and "persist_check", run one after the other: whether a build and a garage unlock come
-- back after a quicksave and a restart of the game (the user allowed quicksaves in the newest save's
-- playthrough, 2026-11-06). The first gives pool copy 2 a build longer than one saved name holds, unlocks it and
-- quicksaves; the second, started fresh, continues that quicksave, checks both came back, calls the copy and
-- verifies it, then takes it all away again and quicksaves, so the newest save is left as it was but for time.
local P = {
    record = "Vehicle.vc_archer_hella__basic_01_2",
    text = "look=archer_hella__basic_suburban_1;paint=primer_red;slot=bumper_front.bumper:4f41bb5f:;"
        .. "slot=wheel.wheel:307348bd:;slot=wheel.tire:d184d620:;slot=hood_a.hood:07b2949c:stickerbomb_01;"
        .. "slot=base.body.police_body:df85ca17:;kit=police_9afe:0:0:0.300:20;kit=scavengers_00af:0:0:0:0",
}

local function prid()
    return TweakDBID.new(P.record)
end

local function saveState()
    return try(function() return Game.GetScriptableServiceContainer():GetService("VehicleCustomizerDev.SaveState") end)
end

local function saveLock()
    return try(function() return Game.GetScriptableSystemsContainer():Get("VehicleCustomizerDev.NoSaveDuringTests") end)
end

local function persistStart()
    local e = engine()
    check("engine is running", e ~= nil, e and e:GetNote() or "VehicleCustomizer.VCEngine not found")
    check("saving is locked for the run", saveLock() ~= nil and saveLock():IsLocked() == true)
    local state = saveState()
    check("the in-game menu can quicksave", state ~= nil and try(function() return state.menu ~= nil end) ~= false)
end

-- Lifts the save lock, quicksaves as the quicksave key does, and waits for the game's answer.
local function quicksave(name)
    return function()
        local state, lock = saveState(), saveLock()
        P.answers = state and state:Answers() or 0
        lock:Allow(true)
        local asked = state and state:QuickSave()
        check("asked for a quicksave (" .. name .. ")", asked == true)
        if not asked then
            lock:Allow(false)
            return nil
        end
        return { what = "the quicksave to finish", timeout = 40,
                 test = function() return saveState():Answers() > P.answers end }
    end
end

local function quicksaveDone(name)
    return function()
        saveLock():Allow(false)
        local state = saveState()
        check("quicksave written (" .. name .. ")", state:Answers() > P.answers and state:LastOk() == true,
            "answers " .. tostring(state:Answers()) .. ", last ok " .. tostring(state:LastOk()))
        check("saving locked again", saveLock():IsLocked() == true)
    end
end

local PERSIST_SAVE = {
    { "engine, save lock and the in-game menu", persistStart, 1 },
    { "give pool copy 2 a long build and unlock it", function()
        local e = engine()
        e:SetBuildText(prid(), P.text)
        check("build set, " .. #P.text .. " characters", e:GetBuildText(prid()) == P.text, e:GetBuildText(prid()))
        e:Unlock(prid())
        check("copy 2 in V's garage", e:IsUnlocked(prid()) == true)
    end, 2 },
    { "quicksave", quicksave("with the build"), 3 },
    { "check the quicksave", quicksaveDone("with the build"), 2 },
}

local PERSIST_CHECK = {
    { "engine, save lock and the in-game menu", persistStart, 1 },
    { "check the build and the garage came back", function()
        local e = engine()
        local text = e:GetBuildText(prid())
        check("build came back after the restart", text == P.text, #text .. " characters: " .. text)
        check("copy 2 still in V's garage", e:IsUnlocked(prid()) == true)
    end, 1 },
    { "call copy 2", function()
        local e = engine()
        -- The game's answer isn't to be trusted: after a restart it said no and the car came anyway.
        write("  the game answered " .. tostring(e:Call(prid())) .. " to the call")
        return { what = "copy 2 to appear", timeout = 45,
                 test = function()
                     local id = e:GetEntityOf(prid())
                     if id and idHash(id) ~= "0" and try(function() return Game.FindEntityByID(id) end) then
                         S.id = id
                         return true
                     end
                     return false
                 end }
    end, 6 },
    { "check the called copy", function()
        check("copy 2 in its build's look", isTwinOf(lookOf(car()), S.suburban), lookOf(car()))
        verify("copy 2 after a restart")
        write(string.format("  copy 2 is %.0f m from V", distanceToPlayer(car())))
        shot("copy2_after_restart")
    end, 5 },
    { "take it all away again", function()
        local e = engine()
        e:SendAway(prid())
        e:SetBuildText(prid(), "")
        e:Lock(prid())
        check("build cleared", e:GetBuildText(prid()) == "")
        check("copy 2 out of V's garage", e:IsUnlocked(prid()) == false)
    end, 3 },
    { "quicksave the cleaned-up state", quicksave("cleaned up"), 3 },
    { "check the quicksave", quicksaveDone("cleaned up"), 2 },
}

-- Job "prepare": hands the game to the user for a test at the PC (2026-11-06). Pool copy 1 gets a full build
-- (Suburban, the Quadra Turbo-R's rims and tires, primer red, the police shell with the light bar, the scavenger
-- kit; no kit moved, so the panel's moves start from zero), goes into V's garage and is called to V; then the
-- save lock is lifted for the rest of the session, so the user can save as usual.
local PREPARE = {
    { "engine and catalogs", function()
        S.record = "Vehicle.vc_archer_hella__basic_01_1" -- the user's copy
        local e = engine()
        check("engine is running", e ~= nil, e and e:GetNote() or "VehicleCustomizer.VCEngine not found")
    end, 1 },
    { "give pool copy 1 a full build and put it in V's garage", function()
        local e = engine()
        local text = "look=archer_hella__basic_suburban_1;paint=primer_red;slot=bumper_front.bumper:4f41bb5f:;"
            .. "slot=wheel.wheel:307348bd:;slot=wheel.tire:d184d620:;"
            .. "slot=base.body.police_body:df85ca17:;kit=police_9afe:0:0:0:0;kit=scavengers_00af:0:0:0:0"
        e:SetBuildText(rid(), text)
        check("build set", e:GetBuildText(rid()) == text)
        e:Unlock(rid())
        check("copy 1 in V's garage", e:IsUnlocked(rid()) == true)
    end, 1 },
    { "call copy 1", function()
        local e = engine()
        write("  the game answered " .. tostring(e:Call(rid())) .. " to the call")
        return { what = "copy 1 to appear", timeout = 45,
                 test = function()
                     local id = e:GetEntityOf(rid())
                     if id and idHash(id) ~= "0" and try(function() return Game.FindEntityByID(id) end) then
                         S.id = id
                         return true
                     end
                     return false
                 end }
    end, 4 },
    { "check it and hand over", function()
        check("copy 1 in its build's look", isTwinOf(lookOf(car()), S.suburban), lookOf(car()))
        verify("copy 1 as called")
        write(string.format("  copy 1 is %.0f m from V and driving up", distanceToPlayer(car())))
        saveLock():Allow(true)
        check("saving unlocked for the user", saveLock():IsLocked() == false)
    end, 1 },
}

-- Job "sweep": every catalog in the game, one after another (2026-11-06; only the Hella had run before). Pool
-- copy 4 of each is given its first style, the last option of every slot and up to three kits, spawned in front of
-- V, checked with Verify and by the engine's own count of parts it couldn't place, pictured, and taken away.
local function catalogFlat(cat, path)
    return try(function() return TweakDB:GetFlat("VehicleCustomizer." .. cat .. "." .. path) end)
end

local function catalogNames(cat, path)
    local out = {}
    for _, v in ipairs(catalogFlat(cat, path) or {}) do
        table.insert(out, try(function() return v.value end) or nameOf(v))
    end
    return out
end

-- The engine's last build note for a record, from its log.
local function lastBuildNote(record)
    local e = engine()
    local count = e and e:GetLogCount() or 0
    for n = count - 1, math.max(0, count - 30), -1 do
        local line = e:GetLogLine(n) or ""
        if line:find("build %d+: " .. record:gsub("%p", "%%%0") .. " ") then
            return line
        end
    end
    return ""
end

-- Variant 1: the first style, every slot's last option, the first three kits. Variant 2 ("sweep_b"): the last
-- style, every slot's second option, a whole-car paint, and the three kits after those.
local function sweepSteps(variant)
    variant = variant or 1
    local cats = {}
    for _, v in ipairs(try(function() return TweakDB:GetFlat("VehicleCustomizer.catalogs") end) or {}) do
        table.insert(cats, try(function() return v.value end) or nameOf(v))
    end
    local steps = {
        { "engine and catalogs; " .. #cats .. " catalogs to go through", function()
            local e = engine()
            check("engine is running", e ~= nil)
            check("saving is locked for the run", saveLock() ~= nil and saveLock():IsLocked() == true)
            try(function() Game.GetTimeSystem():SetGameTimeByHMS(18, 0, 0) end)
            S.distance = 12 -- room for the trucks and the coach
        end, 1 },
        { "turn V away from their own car", turnV, 2 },
    }
    for _, cat in ipairs(cats) do
        local record = "Vehicle.vc_" .. cat .. "_4"
        local base = ""
        table.insert(steps, { cat .. ": build it and spawn it", function()
            S.record = record
            local styles = catalogNames(cat, "styles")
            local style = variant == 2 and styles[#styles] or styles[1]
            local baseName = style and catalogFlat(cat, "style." .. style .. ".base")
            base = baseName and (try(function() return baseName.value end) or nameOf(baseName)) or ""
            local parts = { "look=" .. base }
            local slots = catalogNames(cat, "slots")
            if variant == 2 then
                -- A whole-car paint: the second the body offers, else the first.
                for _, slot in ipairs(slots) do
                    if slot == "base.body" then
                        local body = catalogNames(cat, "slot." .. slot .. ".options")[1]
                        local paints = body and catalogNames(cat, "option." .. body .. ".paints") or {}
                        if #paints > 0 then
                            table.insert(parts, "paint=" .. (paints[2] or paints[1]))
                        end
                    end
                end
            end
            for _, slot in ipairs(slots) do
                local options = catalogNames(cat, "slot." .. slot .. ".options")
                local pick = variant == 2 and (options[2] or options[1]) or options[#options]
                if pick then
                    table.insert(parts, "slot=" .. slot .. ":" .. pick .. ":")
                end
            end
            local kits = catalogNames(cat, "kits")
            local from = variant == 2 and 4 or 1
            for k = from, math.min(from + 2, #kits) do
                table.insert(parts, "kit=" .. kits[k] .. ":0:0:0:0")
            end
            local text = table.concat(parts, ";")
            engine():SetBuildText(rid(), text)
            write(string.format("  %s: %d styles, %d slots, %d kits; build %d characters", cat, #styles,
                #catalogNames(cat, "slots"), #kits, #text))
            return spawnCopy()
        end, 1 })
        table.insert(steps, { cat .. ": wait for its style", function()
            if not car() then
                return nil
            end
            -- A copy whose record's look is already the style's stays in it: the engine has nothing to switch.
            return { what = cat .. " in its style's look", timeout = 10,
                     test = function()
                         local look = lookOf(car())
                         return base == "" or look == base or isTwinOf(look, base)
                     end }
        end, 3 })
        table.insert(steps, { cat .. ": check it", function()
            check(cat .. " spawned", car() ~= nil, record)
            if not car() then
                return
            end
            verify(cat)
            local note = lastBuildNote(record)
            local failed = tonumber(note:match("(%d+) failed") or "0")
            check(cat .. ": every part placed", failed == 0, note:match("; (.*)$") or note)
            shot("sweep_" .. cat)
        end, 4 })
        table.insert(steps, { cat .. ": take it away", function()
            if S.id then
                try(function() Game.GetDynamicEntitySystem():DeleteEntity(S.id) end)
            end
            S.id = nil
            engine():SetBuildText(rid(), "")
        end, 1 })
    end
    return steps
end

-- Job "repair": what holds of a repair (2026-11-06: the panel's first Repair, which rebuilt, left the dents and a
-- lost bumper). Copy 3 in the Suburban style is dented by the game's own visual-destruction event and loses its
-- front bumper, is repaired in place without a rebuild, is dented again and rebuilt; a picture after each.
local function dent(v)
    local evt = VehicleQuestVisualDestructionEvent.new()
    evt.accumulate = false
    evt.front, evt.frontLeft, evt.frontRight = 1.0, 1.0, 1.0
    evt.left, evt.right, evt.back, evt.backLeft, evt.backRight = 0.8, 0.8, 0.8, 0.8, 0.8
    evt.roof = 0.6
    v:QueueEvent(evt)
end

local function repairInPlace(v)
    local event = try(function() return VehicleRepairEvent.new() end) or try(function() return NewObject("VehicleRepairEvent") end)
    if event then
        v:QueueEvent(event)
    end
    local dents = try(function() v:DestructionResetGrid() return true end)
    local glass = try(function() v:DestructionResetGlass() return true end)
    return (event and "repair event, " or "no repair event, ") .. (dents and "dents reset, " or "dents failed, ")
        .. (glass and "glass reset" or "glass failed")
end

local REPAIR = {
    { "engine, save lock, light", function()
        check("engine is running", engine() ~= nil)
        check("saving is locked for the run", saveLock() ~= nil and saveLock():IsLocked() == true)
        try(function() Game.GetTimeSystem():SetGameTimeByHMS(18, 0, 0) end)
        engine():SetBuildText(rid(), "look=" .. S.suburban)
    end, 1 },
    { "turn V away from their own car", turnV, 2 },
    { "spawn copy 3 in the Suburban style", spawnCopy, 3 },
    { "wait for the style", function()
        return { what = "the Suburban look", timeout = 10, test = function() return isTwinOf(lookOf(car()), S.suburban) end }
    end, 4 },
    { "clean", function()
        verify("clean copy")
        shot("r1_clean")
    end, 5 },
    { "dent it and knock its front bumper off", function()
        dent(car())
        local bumper = "bumper_f_01"
        local ok = try(function() car():DetachPart(CName.new(bumper)) return true end)
        write("  dented; DetachPart(" .. bumper .. ") " .. (ok and "called" or "failed"))
    end, 4 },
    { "damaged", function() shot("r2_damaged") end, 5 },
    { "repair in place, no rebuild", function()
        write("  " .. repairInPlace(car()))
    end, 4 },
    { "repaired in place", function() shot("r3_repaired_in_place") end, 5 },
    { "a while later", function() shot("r4_repaired_a_while_later") end, 8 },
    { "dent it again, then rebuild", function()
        dent(car())
    end, 3 },
    { "dented again", function() shot("r5_dented_again") end, 5 },
    { "rebuild in place", rebuilt(function(e, v) e:Rebuild(v) end), 5 },
    { "after the rebuild", function()
        verify("rebuilt while dented")
        shot("r6_dented_then_rebuilt")
    end, 5 },
    { "take it away", function()
        try(function() Game.GetDynamicEntitySystem():DeleteEntity(S.id) end)
        engine():SetBuildText(rid(), "")
    end, 1 },
}

-- Job "wheels": the shared wheel list (2026-11-06). Copy 3 in the Suburban style gets the biggest set in the game
-- (a truck's) scaled to its own size, then the Quadra's at the front and the Cortes police set at the back, then
-- the Quadra's rims all round in the Cortes police tires and in its own (rims and tires apart, 2026-11-07), then
-- its back wheels narrowed and its front ones made bigger; then a Kusanagi gets another bike's wheels.
local function wheelSets(kind)
    local out = {}
    for _, v in ipairs(try(function() return TweakDB:GetFlat("VehicleCustomizer.wheels." .. kind) end) or {}) do
        table.insert(out, try(function() return v.value end) or nameOf(v))
    end
    return out
end

local function wheelFrom(id)
    return try(function() return TweakDB:GetFlat("VehicleCustomizer.wheel." .. id .. ".from") end) or ""
end

local function findWheels(kind, test)
    for _, id in ipairs(wheelSets(kind)) do
        local code = try(function() return TweakDB:GetFlat("VehicleCustomizer.wheel." .. id .. ".code") end) or ""
        if test(wheelFrom(id), code) then
            return id
        end
    end
    return nil
end

local W = {}

local WHEELS = {
    { "engine, save lock, light; pick the sets", function()
        check("engine is running", engine() ~= nil)
        check("saving is locked for the run", saveLock() ~= nil and saveLock():IsLocked() == true)
        try(function() Game.GetTimeSystem():SetGameTimeByHMS(18, 0, 0) end)
        local cars = wheelSets("car")
        W.big = cars[#cars]
        -- The Quadra Turbo-R's (named after the cars wearing them since 2026-11-07; "Turbo" alone is the 911's too).
        W.quadra = findWheels("car", function(from) return from:find("Turbo-R", 1, true) or from:find("Quadra", 1, true) end)
        W.cortes = findWheels("car", function(from, code) return from:find("Cortes") and code:find("police") end)
        W.bike = findWheels("bike", function(from) return not from:find("Kusanagi") end)
        write(string.format("  %d car sets, %d bike sets; biggest %s from %s; Quadra %s; Cortes police %s; bike %s from %s",
            #cars, #wheelSets("bike"), tostring(W.big), wheelFrom(W.big or ""), tostring(W.quadra), tostring(W.cortes),
            tostring(W.bike), wheelFrom(W.bike or "")))
        check("found the sets to try", W.big and W.quadra and W.cortes and W.bike and true or false)
        engine():SetBuildText(rid(), "look=" .. S.suburban)
    end, 1 },
    { "turn V away from their own car", turnV, 2 },
    { "spawn copy 3 in the Suburban style", spawnCopy, 3 },
    { "wait for the style", function()
        return { what = "the Suburban look", timeout = 10, test = function() return isTwinOf(lookOf(car()), S.suburban) end }
    end, 4 },
    { "its own wheels", function()
        verify("own wheels")
        shot("w1_own_wheels")
    end, 5 },
    { "the biggest wheels in the game, fitted", rebuilt(function(e, v) e:ChooseWheels(v, CName.new("all"), CName.new(W.big)) end), 5 },
    { "check them", function()
        verify("biggest set fitted")
        shot("w2_biggest_fitted")
    end, 5 },
    { "Quadra at the front", rebuilt(function(e, v) e:ChooseWheels(v, CName.new("f"), CName.new(W.quadra)) end), 2 },
    { "Cortes police at the back", rebuilt(function(e, v) e:ChooseWheels(v, CName.new("b"), CName.new(W.cortes)) end), 5 },
    { "check front and back", function()
        verify("Quadra front, Cortes back")
        local text = engine():GetBuildText(rid())
        check("the build has both", text:find("rims@f=" .. W.quadra, 1, true) ~= nil and text:find("tires@f=" .. W.quadra, 1, true) ~= nil
            and text:find("rims@b=" .. W.cortes, 1, true) ~= nil and text:find("tires@b=" .. W.cortes, 1, true) ~= nil, text)
        shot("w3_front_quadra_back_cortes")
    end, 5 },
    -- Rims and tires apart (2026-11-07): the Quadra's rims all round, then the Cortes police tires all round, the
    -- rims sized to fill them.
    { "Quadra rims all round", rebuilt(function(e, v) e:ChooseRims(v, CName.new("all"), CName.new(W.quadra)) end), 5 },
    { "check the rims", function()
        verify("Quadra rims, front and back tires as they were")
        local text = engine():GetBuildText(rid())
        check("the build has the rims on both axles", text:find("rims=" .. W.quadra, 1, true) ~= nil, text)
        check("the tires stay", text:find("tires@b=" .. W.cortes, 1, true) ~= nil, text)
        shot("w3b_quadra_rims")
    end, 5 },
    { "Cortes police tires all round", rebuilt(function(e, v) e:ChooseTires(v, CName.new("all"), CName.new(W.cortes)) end), 5 },
    { "check the rims in the tires", function()
        verify("Quadra rims in Cortes police tires")
        local text = engine():GetBuildText(rid())
        check("the build has Quadra rims in Cortes tires", text:find("rims=" .. W.quadra, 1, true) ~= nil
            and text:find("tires=" .. W.cortes, 1, true) ~= nil, text)
        shot("w3c_quadra_rims_cortes_tires")
    end, 5 },
    -- The game's "no name" is hash 0; CName.new("") is a name for the empty string, which the engine took as a
    -- tire set and wrote as "tires=" (run of 15:39).
    { "the car's own tires back", rebuilt(function(e, v) e:ChooseTires(v, CName.new("all"), CName.new(0)) end), 5 },
    { "check the rims in its own tires", function()
        verify("Quadra rims in the car's own tires")
        local text = engine():GetBuildText(rid())
        check("no tires in the build", text:find("tires", 1, true) == nil, text)
        shot("w3d_quadra_rims_own_tires")
    end, 5 },
    { "narrow the back wheels to 75%", rebuilt(function(e, v) e:SetWheelFit(v, CName.new("b"), 100, 75) end), 5 },
    { "check the back", function()
        verify("back narrowed")
        shot("w4_back_narrowed")
    end, 5 },
    { "make the front wheels 115%", rebuilt(function(e, v) e:SetWheelFit(v, CName.new("f"), 115, 100) end), 5 },
    { "check the front", function()
        verify("front bigger")
        shot("w5_front_bigger")
    end, 5 },
    { "paint the front rims", rebuilt(function(e, v)
        local paints = try(function() return TweakDB:GetFlat("VehicleCustomizer.wheel." .. W.quadra .. ".paints") end) or {}
        W.paint = paints[#paints] and (try(function() return paints[#paints].value end) or nameOf(paints[#paints])) or "default"
        write("  front rim paint " .. W.paint)
        e:ChooseWheelPaint(v, CName.new("f"), CName.new(W.paint))
    end), 5 },
    { "check the front rims' paint", function()
        verify("front rims painted " .. tostring(W.paint))
        shot("w5b_front_rims_painted")
    end, 5 },
    -- A new rim or tire goes back to the automatic fit (user, 2026-11-08): both widths, on its axles; the size stays.
    { "the back tire's and rim's widths set by hand", rebuilt(function(e, v)
        e:SetRimWidth(v, CName.new("b"), 120)
    end), 5 },
    { "check the widths are in the build", function()
        verify("back rims and tires set by hand")
        local text = engine():GetBuildText(rid())
        check("the back's fit has both widths", text:find("fit@b=100:75:120", 1, true) ~= nil, text)
    end, 1 },
    { "a new rim at the back", rebuilt(function(e, v) e:ChooseRims(v, CName.new("b"), CName.new(W.cortes)) end), 5 },
    { "check the back fitted itself again and the front didn't change", function()
        verify("Cortes rims at the back, automatic fit")
        local text = engine():GetBuildText(rid())
        check("the back's widths are automatic again", text:find("fit@b=", 1, true) == nil, text)
        check("the front's size stays", text:find("fit@f=115:100", 1, true) ~= nil, text)
        shot("w5c_new_rim_auto_fit")
    end, 5 },
    { "take it away", function()
        try(function() Game.GetDynamicEntitySystem():DeleteEntity(S.id) end)
        engine():SetBuildText(rid(), "")
    end, 2 },
    { "a Kusanagi with another bike's wheels", function()
        S.record = "Vehicle.vc_yaiba_kusanagi_basic_01_3"
        engine():SetBuildText(rid(), "rims=" .. W.bike .. ";tires=" .. W.bike)
        return spawnCopy()
    end, 5 },
    { "check the bike", function()
        verify("Kusanagi with " .. wheelFrom(W.bike) .. " wheels")
        shot("w6_bike")
    end, 5 },
    { "take it away", function()
        try(function() Game.GetDynamicEntitySystem():DeleteEntity(S.id) end)
        engine():SetBuildText(rid(), "")
    end, 2 },
    -- Every axle (user asked why not, 2026-11-06): a Bratsk has a second front axle. Its build is written the way
    -- builds were before rims and tires came apart (wheels=), which still reads as that set's rims and tires.
    { "a Bratsk truck on the Cortes police wheels, every axle", function()
        S.record = "Vehicle.vc_kaukaz_bratsk__basic_01_3"
        S.distance = 13
        engine():SetBuildText(rid(), "wheels=" .. W.cortes)
        return spawnCopy()
    end, 5 },
    { "check the truck", function()
        verify("Bratsk with Cortes police wheels")
        local note = lastBuildNote(S.record)
        local fitted = tonumber(note:match("(%d+) wheel parts fitted") or "0")
        check("every axle fitted (3 axles, 12 parts)", fitted == 12, note:match("; (.*)$") or note)
        shot("w7_truck_every_axle")
    end, 5 },
    { "take it away", function()
        try(function() Game.GetDynamicEntitySystem():DeleteEntity(S.id) end)
        engine():SetBuildText(rid(), "")
    end, 1 },
}

-- Job "buy" (2026-11-06 evening): what buying on the screen does, one call at a time, so a crash names its call.
-- Buying crashed the game for a Barghest Apollo and a Herrera Outlaw (Cyberpunk2077.exe+0x7bb8a0, handed the
-- catalog's name hash where it wanted a pointer), a bought Hella never appeared and its saved build was gone, and
-- F7 beside a Quartz copy in the garage crashed too. For each car in VehicleCustomizerDev.arg ("cat,cat,..."; a
-- "screen" among them opens the screen first): the steps of a buy one by one on one copy, then the screen's whole
-- Buy on the next copy, each line in the report before its call. Both copies are put back after each car; saving
-- stays locked for the run.
local function shopSystem()
    return try(function() return Game.GetScriptableSystemsContainer():Get("VehicleCustomizer.VCShop") end)
end

local function poolOf(cat)
    local out = {}
    for _, id in ipairs(try(function() return TweakDB:GetFlat("VehicleCustomizer." .. cat .. ".pool") end) or {}) do
        table.insert(out, id)
    end
    return out
end

local function recName(id)
    return id and (try(function() return TDBID.ToStringDEBUG(id) end) or tostring(id)) or "none"
end

local function buyCarSteps(cat, steps)
    local c = {}
    table.insert(steps, { cat .. ": pick a free copy (the screen's FreeCopy)", function()
        local styles = try(function() return TweakDB:GetFlat("VehicleCustomizer." .. cat .. ".styles") end) or {}
        c.style = styles[1] and nameOf(styles[1]) or ""
        c.base = nameOf(try(function() return TweakDB:GetFlat("VehicleCustomizer." .. cat .. ".style." .. c.style .. ".base") end) or "")
        local n = shopSystem():FreeCopy(CName.new(cat))
        c.rid = poolOf(cat)[(n or -1) + 1]
        check(cat .. ": a free copy", c.rid ~= nil, "copy index " .. tostring(n) .. ", " .. recName(c.rid) .. ", style " .. c.style .. " (" .. c.base .. ")")
    end, 1 })
    table.insert(steps, { cat .. ": save its build", function()
        local e = engine()
        e:SetBuildText(c.rid, "look=" .. c.base)
        local back = e:GetBuildText(c.rid)
        check(cat .. ": build saved", back == "look=" .. c.base, back)
    end, 1 })
    table.insert(steps, { cat .. ": unlock it in V's garage (the game's EnablePlayerVehicleID)", function()
        write("  unlock answered " .. tostring(engine():Unlock(c.rid)))
    end, 2 })
    table.insert(steps, { cat .. ": ask the garage whether it has it (IsVehiclePlayerUnlocked)", function()
        check(cat .. ": in the garage", engine():IsUnlocked(c.rid) == true)
    end, 1 })
    table.insert(steps, { cat .. ": ask the garage about all 480 copies, as the screen did every second", function()
        local e, n = engine(), 0
        for _, other in ipairs(try(function() return TweakDB:GetFlat("VehicleCustomizer.catalogs") end) or {}) do
            for _, id in ipairs(poolOf(nameOf(other))) do
                if e:IsUnlocked(id) then
                    n = n + 1
                end
            end
        end
        write("  " .. n .. " pool copies in the garage")
    end, 1 })
    table.insert(steps, { cat .. ": select it (the screen's SetTarget)", function()
        shopSystem():SetTarget(c.rid)
    end, 1 })
    table.insert(steps, { cat .. ": bring it here (the screen's Bring here: the game's call from V's garage)", function()
        shopSystem():BringHere(c.rid)
        write("  the screen says: " .. tostring(shopSystem():Message()))
        return { what = cat .. " to appear", timeout = 30, optional = true,
                 test = function() return try(function() return engine():VehicleOf(c.rid) end) ~= nil end }
    end, 2 })
    table.insert(steps, { cat .. ": did it come", function()
        local v = try(function() return engine():VehicleOf(c.rid) end)
        check(cat .. ": called from the garage", v ~= nil, v and string.format("%.1f m from V", distanceToPlayer(v)) or "not in the world")
        shot(cat .. "_called")
    end, 2 })
    table.insert(steps, { cat .. ": is the build still saved", function()
        local back = engine():GetBuildText(c.rid)
        check(cat .. ": build kept", back == "look=" .. c.base, back)
    end, 1 })
    table.insert(steps, { cat .. ": the screen's whole Buy, on the next free copy", function()
        local s = shopSystem()
        s:Buy(CName.new(cat), CName.new(c.style))
        c.rid2 = s:Record()
        write("  bought " .. recName(c.rid2) .. "; the screen says: " .. tostring(s:Message()))
        return { what = "the second copy to appear", timeout = 30, optional = true,
                 test = function() return try(function() return engine():VehicleOf(c.rid2) end) ~= nil end }
    end, 2 })
    table.insert(steps, { cat .. ": put both copies back", function()
        local s = shopSystem()
        for _, id in ipairs({ c.rid, c.rid2 }) do
            write("  returning " .. recName(id) .. " (send away, the game's lock, build cleared)")
            s:ReturnCar(id)
        end
    end, 2 })
end

local function buySteps()
    local arg = try(function() return TweakDB:GetFlat("VehicleCustomizerDev.arg") end) or ""
    local cars, screen, garage = {}, false, false
    for token in tostring(arg):gmatch("[^,%s]+") do
        if token == "screen" then
            screen = true
        elseif token == "garage" then
            -- the screen on Garage, My cars: the list that crashed the game by a Quartz copy (F7, 2026-11-06)
            screen, garage = true, true
        else
            table.insert(cars, token)
        end
    end
    if #cars == 0 then
        cars = { "archer_hella__basic_01", "archer_quartz__basic_01", "herrera_outlaw_basic_01", "brennan_apollo_basic_01_ep1" }
    end
    local steps = {}
    table.insert(steps, { "cars: " .. table.concat(cars, ", ") .. (screen and "; with the screen open" or "; screen closed"), function()
        shot("start")
    end, 1 })
    if screen then
        table.insert(steps, { "open the screen" .. (garage and " on Garage, My cars" or ""), function()
            local s = shopSystem()
            if garage then
                s.tab = 6
                s.garagePick = CName.new("mine")
            end
            s:Open()
            if garage then
                s.tab = 6
            end
            return { what = "the screen to open", timeout = 10, test = function() return shopSystem():IsOpen() end }
        end, 2 })
        table.insert(steps, { "picture with the screen open", function() shot("screen_open") end, 1 })
    end
    for _, cat in ipairs(cars) do
        buyCarSteps(cat, steps)
    end
    if screen then
        table.insert(steps, { "picture of the screen at the end", function() shot("screen_end") end, 1 })
        table.insert(steps, { "close the screen", function() shopSystem():CloseScreen() end, 2 })
    end
    return steps
end

-- Job "own" (2026-11-06 evening): V's own cars are customizable now (the mod replaces CrystalCoat, user). For each
-- of the game's own records in VehicleCustomizerDev.arg (default the Outlaw and the Nazare): the engine counts it
-- as ours but not a shop copy; spawned in front of V, the game's reset on getting in still runs while it has no
-- build (CrystalCoat stays); a style, a part and a paint go on and Verify checks every part; then the reset is
-- refused; the build is cleared and the car taken away. Saving stays locked.
local function ownCarSteps(record, steps)
    local c = {}
    local function v() return c.id and try(function() return Game.FindEntityByID(c.id) end) or nil end
    local function keptNotes()
        local e, n = engine(), 0
        local count = try(function() return e:GetLogCount() end) or 0
        for i = math.max(0, count - 60), count - 1 do
            local line = try(function() return e:GetLogLine(i) end) or ""
            if line:find("against the game's reset", 1, true) and line:find(record, 1, true) then
                n = n + 1
            end
        end
        return n
    end
    table.insert(steps, { record .. ": the engine's own car, not a shop copy", function()
        local e, rid = engine(), TweakDBID.new(record)
        c.rid = rid
        c.cat = nameOf(e:CatalogOf(rid))
        check(record .. ": counted as V's own", e:IsOurs(rid) == true and e:IsPoolCopy(rid) == false, "catalog " .. c.cat)
        e:SetBuildText(rid, "")
    end, 1 })
    table.insert(steps, { record .. ": spawn it in front of V", function()
        local player = Game.GetPlayer()
        local pos, f = player:GetWorldPosition(), player:GetWorldForward()
        local facing = math.atan2(-f.x, f.y)
        local yaw = facing + math.pi / 2
        local spec = DynamicEntitySpec.new()
        spec.recordID = c.rid
        spec.position = Vector4.new(pos.x + f.x * 8, pos.y + f.y * 8, pos.z + 0.2, 1)
        spec.orientation = Quaternion.new(0, 0, math.sin(yaw / 2), math.cos(yaw / 2))
        spec.alwaysSpawned = true
        spec.persistState = false
        spec.persistSpawn = false
        c.id = Game.GetDynamicEntitySystem():CreateEntity(spec)
        return { what = record .. " to appear", timeout = 20, test = function() return v() ~= nil end }
    end, 2 })
    table.insert(steps, { record .. ": the game's reset on getting in, with no build (CrystalCoat keeps working)", function()
        c.kept = keptNotes()
        v():GetVehicleComponent():EnableCustomizableAppearance(false)
    end, 2 })
    table.insert(steps, { record .. ": was it let through", function()
        check(record .. ": reset let through without a build", keptNotes() == c.kept, "refusals noted " .. keptNotes() .. ", before " .. c.kept)
        shot(record:gsub("^Vehicle%.", "") .. "_stock")
    end, 1 })
    table.insert(steps, { record .. ": another style", function()
        local styles = try(function() return TweakDB:GetFlat("VehicleCustomizer." .. c.cat .. ".styles") end) or {}
        local style = nameOf(styles[#styles > 1 and 2 or 1])
        c.look = nameOf(TweakDB:GetFlat("VehicleCustomizer." .. c.cat .. ".style." .. style .. ".base"))
        write("  style " .. style .. " (" .. c.look .. ")")
        local before = lookOf(v())
        engine():ChooseLook(v(), CName.new(c.look))
        return { what = "the rebuild", timeout = 12, test = function() return lookOf(v()) ~= before end }
    end, 2 })
    table.insert(steps, { record .. ": a part and a paint", function()
        local e = engine()
        for _, slot in ipairs(try(function() return TweakDB:GetFlat("VehicleCustomizer." .. c.cat .. ".slots") end) or {}) do
            local s = nameOf(slot)
            local options = try(function() return TweakDB:GetFlat("VehicleCustomizer." .. c.cat .. ".slot." .. s .. ".options") end) or {}
            if #options > 1 and not c.slot then
                c.slot, c.option = s, nameOf(options[2])
            end
        end
        if c.slot then
            write("  slot " .. c.slot .. " to option " .. c.option)
            e:ChooseOption(v(), CName.new(c.slot), CName.new(c.option))
        end
        local paints = try(function() return TweakDB:GetFlat("VehicleCustomizer." .. c.cat .. ".option." .. (c.option or "") .. ".paints") end) or {}
        if paints[1] then
            write("  whole car paint " .. nameOf(paints[1]))
            e:ChooseCarPaint(v(), paints[1])
        end
    end, 3 })
    table.insert(steps, { record .. ": check every part", function()
        local result = try(function() return engine():Verify(v()) end) or "Verify failed to run"
        check(record .. ": the build is on the car", result:sub(1, 2) == "ok", lookOf(v()) .. "; " .. result)
        shot(record:gsub("^Vehicle%.", "") .. "_built")
    end, 1 })
    table.insert(steps, { record .. ": the game's reset on getting in, with a build", function()
        c.kept = keptNotes()
        v():GetVehicleComponent():EnableCustomizableAppearance(false)
    end, 2 })
    table.insert(steps, { record .. ": was it refused", function()
        check(record .. ": reset refused with a build", keptNotes() > c.kept, "refusals noted " .. keptNotes() .. ", before " .. c.kept)
        local result = try(function() return engine():Verify(v()) end) or "Verify failed to run"
        check(record .. ": the build still on after the reset", result:sub(1, 2) == "ok", result)
    end, 1 })
    table.insert(steps, { record .. ": clear the build and take it away", function()
        engine():SetBuildText(c.rid, "")
        try(function() Game.GetDynamicEntitySystem():DeleteEntity(c.id) end)
    end, 2 })
end

local function ownSteps()
    local arg = try(function() return TweakDB:GetFlat("VehicleCustomizerDev.arg") end) or ""
    local records = {}
    for token in tostring(arg):gmatch("[^,%s]+") do
        table.insert(records, token)
    end
    if #records == 0 then
        records = { "Vehicle.v_sport1_herrera_outlaw_player", "Vehicle.v_sportbike2_arch_player" }
    end
    local steps = { { "own cars: " .. table.concat(records, ", "), function() shot("start") end, 1 } }
    for _, record in ipairs(records) do
        ownCarSteps(record, steps)
    end
    return steps
end

-- Job "session" (2026-11-07): the co-op sync through NightCoop's shared state, in a real session this PC hosts
-- alone (the host is in a session as soon as it hosts). It waits for the session (hosted from the pause menu's
-- Co-op screen, "Host a session"), then: our list of shop cars goes into the state; a bought Quartz puts its build
-- in as a change and the car comes; a change of ours lands in the state and in our save; a partner's change,
-- played by setting the state directly, lands in our save and on the car; with its key gone, our car puts its
-- saved build back in (an owner's build); a partner's list of copies keeps buying off them; returning the car
-- removes its key and takes it off our list. Saving stays locked.
local SDK_ID = "xip.vehiclecustomizer"

local function sdk(name, ...)
    local args = { ... }
    local spread = table.unpack or unpack
    return try(function() return NightCoopSdk[name](spread(args)) end)
end

local function sessionSteps()
    local c = {}
    local function key() return (recName(c.rid):gsub("^Vehicle%.", "")) end
    local function state(k) return sdk("HasState", SDK_ID, k) and sdk("GetState", SDK_ID, k) or nil end
    local function v() return try(function() return engine():VehicleOf(c.rid) end) end
    local cat = "archer_quartz__basic_01"
    return {
        { "wait for a NightCoop session (Co-op, Host a session)", function()
            shot("before_session")
            return { what = "a session", timeout = 600, test = function() return sdk("InSession") == true end }
        end, 5 },
        { "the session is up", function()
            write("  host " .. tostring(sdk("IsHost")) .. ", our number " .. tostring(sdk("LocalPeer")) .. ", partners " .. #(sdk("Peers") or {}))
            check("we host it", sdk("IsHost") == true)
            c.own = "own." .. tostring(sdk("LocalPeer"))
        end, 3 },
        { "our list of shop cars is in the session's state", function()
            check("our list is in", state(c.own) ~= nil, tostring(state(c.own)))
        end, 1 },
        { "buy a Quartz on the screen's Buy", function()
            local styles = try(function() return TweakDB:GetFlat("VehicleCustomizer." .. cat .. ".styles") end) or {}
            c.style = nameOf(styles[1])
            local s = shopSystem()
            s:Buy(CName.new(cat), CName.new(c.style))
            c.rid = s:Record()
            write("  bought " .. recName(c.rid) .. "; the screen says: " .. tostring(s:Message()))
            return { what = "the Quartz to come from the garage", timeout = 30, test = function() return v() ~= nil end }
        end, 3 },
        { "the Quartz's build is the session's", function()
            local value = state(key())
            check("its build is in the session's state as a change", value ~= nil and value:sub(1, 2) == "c|", tostring(value))
            check("the engine wears the session's build", engine():HasSessionBuild(c.rid) == true)
            check("our list has it", (state(c.own) or ""):find("," .. key() .. ",", 1, true) ~= nil, tostring(state(c.own)))
            shot("bought")
        end, 1 },
        { "the screen on it, in a session", function()
            local s = shopSystem()
            s.tab = 0
            s:Open()
            return { what = "the screen to open", timeout = 10, test = function() return shopSystem():IsOpen() end }
        end, 2 },
        { "picture of the screen", function() shot("screen") end, 1 },
        { "close the screen", function() shopSystem():CloseScreen() end, 2 },
        { "a change of ours: another style", function()
            local styles = try(function() return TweakDB:GetFlat("VehicleCustomizer." .. cat .. ".styles") end) or {}
            local style = nameOf(styles[#styles > 1 and 2 or 1])
            c.look = nameOf(TweakDB:GetFlat("VehicleCustomizer." .. cat .. ".style." .. style .. ".base"))
            local before = lookOf(v())
            engine():ChooseLook(v(), CName.new(c.look))
            return { what = "the rebuild", timeout = 12, test = function() return lookOf(v()) ~= before end }
        end, 2 },
        { "check our change", function()
            local saved = engine():GetBuildText(c.rid)
            check("the change is in the session's state", state(key()) == "c|" .. saved, tostring(state(key())))
            check("and in our save", saved:find("look=" .. c.look, 1, true) ~= nil, saved)
            local result = try(function() return engine():Verify(v()) end) or "Verify failed to run"
            check("the car wears it", result:sub(1, 2) == "ok", lookOf(v()) .. "; " .. result)
        end, 1 },
        { "a partner's change arrives (set in the state as a partner would)", function()
            c.partner = "look=" .. c.look .. ";paint=primer_red"
            write("  set: " .. tostring(sdk("SetState", SDK_ID, key(), "c|" .. c.partner)))
        end, 3 },
        { "check the partner's change", function()
            check("kept in our save, since the car is ours", engine():GetBuildText(c.rid) == c.partner, engine():GetBuildText(c.rid))
            local result = try(function() return engine():Verify(v()) end) or "Verify failed to run"
            check("the car wears it", result:sub(1, 2) == "ok", lookOf(v()) .. "; " .. result)
            shot("partner_change")
        end, 1 },
        { "the car's key goes (as at a session's start): our car puts its build back in", function()
            write("  removed: " .. tostring(sdk("RemoveState", SDK_ID, key())))
            return { what = "our build back in the state", timeout = 10, test = function() return state(key()) ~= nil end }
        end, 1 },
        { "check the owner's build", function()
            check("back in as an owner's build", state(key()) == "s|" .. engine():GetBuildText(c.rid), tostring(state(key())))
        end, 1 },
        { "a partner's list takes all Hella copies but the 4th", function()
            local pool = poolOf("archer_hella__basic_01")
            local list = ","
            for i, id in ipairs(pool) do
                if i ~= 4 then list = list .. (recName(id):gsub("^Vehicle%.", "")) .. "," end
            end
            c.others = {}
            for _, id in ipairs(pool) do
                if engine():GetBuildText(id) ~= "" then table.insert(c.others, recName(id)) end
            end
            write("  set own.1: " .. tostring(sdk("SetState", SDK_ID, "own.1", list)) .. (#c.others > 0 and ("; we own " .. table.concat(c.others, ", ")) or ""))
        end, 2 },
        { "check buying skips the partner's copies", function()
            local picks, ok = {}, true
            for _ = 1, 10 do
                local n = shopSystem():FreeCopy(CName.new("archer_hella__basic_01"))
                table.insert(picks, tostring(n))
                ok = ok and (n == 3 or n == -1)
            end
            check("ten picks all copy 4 (index 3), or none if we own it", ok, table.concat(picks, " "))
            write("  removed own.1: " .. tostring(sdk("RemoveState", SDK_ID, "own.1")))
        end, 2 },
        { "return the Quartz", function()
            shopSystem():ReturnCar(c.rid)
        end, 3 },
        { "check it's gone from the session", function()
            check("its key is gone", state(key()) == nil, tostring(state(key())))
            check("our list no longer has it", (state(c.own) or ""):find("," .. key() .. ",", 1, true) == nil, tostring(state(c.own)))
            check("its build is gone from our save", engine():GetBuildText(c.rid) == "")
        end, 1 },
    }
end

-- Job "probes": the tool idea's unknowns (UX.md, 2026-11-07), on a Hella copy spawned in front of V.
-- 1: does the game's render highlight event outline one named part? 2: which part is under a ray, from each part's
-- box (probe-bounds.lua, written by experiments/tool/part-bounds.py) through its component's GetLocalToWorld?
-- 3: the turret gun's data, how it sits in V's hands, and what a weapon switch does with it (the user switches).
local PROBE_GUN = "Items.Preset_HMG_Default"

local function hashText(h)
    if h == nil then
        return nil
    end
    local s = tostring(h):gsub("ULL$", ""):gsub("LL$", "")
    return s
end

local function meshHashOf(comp)
    local m = try(function() return comp.mesh end)
    if m == nil then
        return nil, "no mesh field"
    end
    local h = try(function() return ResRef.GetHash(m) end)
    if h then
        return hashText(h), "ResRef.GetHash"
    end
    h = try(function() return ResourceAsyncRef.GetHash(m) end)
    if h then
        return hashText(h), "ResourceAsyncRef.GetHash"
    end
    h = try(function() return m.hash end)
    if h then
        return hashText(h), "hash field"
    end
    return nil, "no hash"
end

local function classOf(obj)
    return try(function() return nameOf(obj:GetClassName()) end) or "?"
end

-- Every mesh part of a car that has a box: name, class, the component, its box.
local function boxedParts(v, bounds)
    local parts, unknown, how = {}, {}, nil
    for _, comp in ipairs(try(function() return v:GetComponents() end) or {}) do
        local cls = classOf(comp)
        local name = try(function() return nameOf(comp.name) end) or "?"
        if cls:find("MeshComponent", 1, true) and not name:find("_shadow", 1, true) then
            local key, method = meshHashOf(comp)
            how = how or (key and method)
            local box = key and bounds[key]
            if box and not box.path:find("_shadow", 1, true) then
                table.insert(parts, { name = name, cls = cls, comp = comp, box = box })
            else
                table.insert(unknown, name .. (key and "" or (" (" .. method .. ")")))
            end
        end
    end
    return parts, unknown, how
end

local function vec3(v)
    return { v.x, v.y, v.z }
end

-- The component's world matrix: rows X, Y, Z are its axes in the world, W its place (world = x*X + y*Y + z*Z + W).
local function toLocal(m, point, dir)
    local X, Y, Z, W = m.X, m.Y, m.Z, m.W
    local a, b, c = X.x, Y.x, Z.x
    local d, e, f = X.y, Y.y, Z.y
    local g, h, i = X.z, Y.z, Z.z
    local A, B, C = e * i - f * h, -(d * i - f * g), d * h - e * g
    local det = a * A + b * B + c * C
    if math.abs(det) < 1e-9 then
        return nil
    end
    local D, E, F = -(b * i - c * h), a * i - c * g, -(a * h - b * g)
    local G, H, I = b * f - c * e, -(a * f - c * d), a * e - b * d
    local inv = { { A / det, D / det, G / det }, { B / det, E / det, H / det }, { C / det, F / det, I / det } }
    local function apply(v)
        return { inv[1][1] * v[1] + inv[1][2] * v[2] + inv[1][3] * v[3],
                 inv[2][1] * v[1] + inv[2][2] * v[2] + inv[2][3] * v[3],
                 inv[3][1] * v[1] + inv[3][2] * v[2] + inv[3][3] * v[3] }
    end
    return apply({ point[1] - W.x, point[2] - W.y, point[3] - W.z }), apply(dir), math.abs(det)
end

local function toWorld(m, p)
    return { p[1] * m.X.x + p[2] * m.Y.x + p[3] * m.Z.x + m.W.x,
             p[1] * m.X.y + p[2] * m.Y.y + p[3] * m.Z.y + m.W.y,
             p[1] * m.X.z + p[2] * m.Y.z + p[3] * m.Z.z + m.W.z }
end

local function rayBox(o, d, mn, mx)
    local tmin, tmax = -math.huge, math.huge
    for k = 1, 3 do
        if math.abs(d[k]) < 1e-9 then
            if o[k] < mn[k] or o[k] > mx[k] then
                return nil
            end
        else
            local t1, t2 = (mn[k] - o[k]) / d[k], (mx[k] - o[k]) / d[k]
            if t1 > t2 then
                t1, t2 = t2, t1
            end
            tmin = math.max(tmin, t1)
            tmax = math.min(tmax, t2)
            if tmin > tmax then
                return nil
            end
        end
    end
    if tmax < 0 then
        return nil
    end
    return math.max(tmin, 0)
end

-- The parts a ray goes through, smallest box first (the agreed rule), each with how far along the ray it starts.
local function partsOnRay(parts, origin, dir)
    local hits = {}
    for _, p in ipairs(parts) do
        local m = try(function() return p.comp:GetLocalToWorld() end)
        if m then
            local o, d, scale = toLocal(m, origin, dir)
            if o then
                local t = rayBox(o, d, p.box.min, p.box.max)
                if t then
                    local size = (p.box.max[1] - p.box.min[1]) * (p.box.max[2] - p.box.min[2])
                        * (p.box.max[3] - p.box.min[3]) * scale
                    table.insert(hits, { name = p.name, t = t, size = size })
                end
            end
        end
    end
    table.sort(hits, function(x, y) return x.size < y.size end)
    return hits
end

-- The part to light up. Smallest-first alone picked parts on the far side (the far wheel over the near tire, the
-- far door over the near one; first probes run), so: the nearest part, unless a smaller one starts within 40 cm
-- of it (a rim inside its tire's box); shells as big as the body or the interior (over 3 m3) only if nothing else.
local function pickPart(hits)
    local nearest, shell = nil, nil
    for _, hit in ipairs(hits) do
        if hit.size > 3.0 then
            if not shell or hit.t < shell.t then
                shell = hit
            end
        elseif not nearest or hit.t < nearest.t then
            nearest = hit
        end
    end
    if not nearest then
        return shell
    end
    local best = nearest
    for _, hit in ipairs(hits) do
        if hit.size <= 3.0 and hit.t <= nearest.t + 0.4 and hit.size < best.size then
            best = hit
        end
    end
    return best
end

local function hitList(hits)
    local out = {}
    for i, hit in ipairs(hits) do
        if i > 6 then
            table.insert(out, "+" .. (#hits - 6) .. " more")
            break
        end
        table.insert(out, string.format("%s (%.2f m3, at %.1f m)", hit.name, hit.size, hit.t))
    end
    return #out > 0 and table.concat(out, ", ") or "nothing"
end

local function crosshairRay()
    local player = Game.GetPlayer()
    local m = try(function() return player:GetFPPCameraComponent():GetLocalToWorld() end)
    if not m then
        return nil
    end
    -- The camera looks along its own Y axis (the game's Matrix.GetDirectionVector).
    local f = m.Y
    local len = math.sqrt(f.x * f.x + f.y * f.y + f.z * f.z)
    return { m.W.x, m.W.y, m.W.z }, { f.x / len, f.y / len, f.z / len }
end

local function highlight(v, part, outline, fill, opacity)
    local evt = try(function() return entRenderHighlightEvent.new() end)
        or try(function() return NewObject("entRenderHighlightEvent") end)
    if not evt then
        return false, "the event can't be made"
    end
    local set = pcall(function()
        if part then
            evt.componentName = CName.new(part)
        end
        evt.outlineIndex = outline
        evt.fillIndex = fill
        evt.opacity = opacity
        evt.seeThroughWalls = false
    end)
    if not set then
        return false, "its fields can't be set"
    end
    local queued = pcall(function() v:QueueEvent(evt) end)
    return queued, queued and "queued" or "QueueEvent failed"
end

local function describe(value)
    if type(value) == "table" then
        local out = {}
        for _, v in ipairs(value) do
            table.insert(out, describe(v))
        end
        return "[" .. table.concat(out, ", ") .. "]"
    end
    return try(function() return TDBID.ToStringDEBUG(value) end)
        or try(function() local s = NameToString(value) return s ~= "" and s or nil end)
        or tostring(value)
end

local function heldRecord()
    local item = try(function()
        return Game.GetTransactionSystem():GetItemInSlot(Game.GetPlayer(), TweakDBID.new("AttachmentSlots.WeaponRight"))
    end)
    if not item then
        return nil
    end
    return try(function() return TDBID.ToStringDEBUG(item:GetItemID().id) end)
        or try(function() return TDBID.ToStringDEBUG(ItemID.GetTDBID(item:GetItemID())) end) or "?"
end

local function effectNames()
    local names = {}
    local list = try(function() return Game.GetStatusEffectSystem():GetAppliedEffects(Game.GetPlayer():GetEntityID()) end) or {}
    for _, e in ipairs(list) do
        table.insert(names, try(function() return TDBID.ToStringDEBUG(e:GetRecord():GetID()) end) or "?")
    end
    table.sort(names)
    return names
end

local function probeSteps()
    local bounds = try(function() return require("probe-bounds") end) or {}
    local c = { targets = {} }
    local function v() return car() end
    return {
        { "probes: turn V and spawn the Hella copy in front", function()
            S.distance = 7
            turnV()
            try(function() Game.GetTimeSystem():SetGameTimeByHMS(18, 0, 0) end)
            return spawnCopy()
        end, 4 },
        { "the car's mesh parts and their boxes", function()
            local parts, unknown, how = boxedParts(v(), bounds)
            c.parts = parts
            local names = {}
            for _, p in ipairs(parts) do
                table.insert(names, p.name)
            end
            write("  mesh hash read by " .. tostring(how) .. "; with a box: " .. table.concat(names, ", "))
            write("  without a box: " .. (#unknown > 0 and table.concat(unknown, ", ") or "none"))
            check("the car's parts are found among the boxes", #parts >= 10, #parts .. " with a box, " .. #unknown .. " without")
            for _, want in ipairs({ "door_fl", "hood", "wheel_fl", "bumper_f" }) do
                for _, p in ipairs(parts) do
                    if p.name:find(want, 1, true) then
                        table.insert(c.targets, p.name)
                        break
                    end
                end
            end
            write("  parts to outline: " .. table.concat(c.targets, ", "))
            shot("p0_car")
        end, 2 },
        { "probe 1: outline the whole car (control)", function()
            local ok, how = highlight(v(), nil, 1, 0, 1.0)
            check("a highlight event for the whole car", ok, how)
        end, 2 },
        -- A picture is saved up to 2.5 s after its SHOT line (the run script's 1 s poll, then 1.5 s for the game in
        -- front), so the next change waits 4 s: the first probes run's pictures each showed the following step's.
        { "picture", function() shot("p1_whole_car") end, 4 },
        { "clear it", function() highlight(v(), nil, 0, 0, 0.0) end, 2 },
        { "probe 1: outline one part, " .. "the first target", function()
            local ok, how = highlight(v(), c.targets[1], 1, 0, 1.0)
            check("an outline on " .. tostring(c.targets[1]), ok, how .. "; outline colour 1")
        end, 2 },
        { "picture", function() shot("p1_" .. tostring(c.targets[1]) .. "_outline1") end, 4 },
        { "clear it, outline the second target in another colour", function()
            highlight(v(), c.targets[1], 0, 0, 0.0)
            local ok, how = highlight(v(), c.targets[2], 2, 0, 1.0)
            check("an outline on " .. tostring(c.targets[2]), ok, how .. "; outline colour 2")
        end, 2 },
        { "picture", function() shot("p1_" .. tostring(c.targets[2]) .. "_outline2") end, 4 },
        { "clear it, fill the third target", function()
            highlight(v(), c.targets[2], 0, 0, 0.0)
            local ok, how = highlight(v(), c.targets[3], 0, 1, 0.6)
            check("a fill on " .. tostring(c.targets[3]), ok, how .. "; fill colour 1 at 0.6")
        end, 2 },
        { "picture", function() shot("p1_" .. tostring(c.targets[3]) .. "_fill1") end, 4 },
        { "clear it, outline the fourth in colour 3", function()
            highlight(v(), c.targets[3], 0, 0, 0.0)
            local ok, how = highlight(v(), c.targets[4], 3, 0, 1.0)
            check("an outline on " .. tostring(c.targets[4]), ok, how .. "; outline colour 3")
        end, 2 },
        { "picture", function() shot("p1_" .. tostring(c.targets[4]) .. "_outline3") end, 4 },
        { "clear it", function() highlight(v(), c.targets[4], 0, 0, 0.0) end, 1 },
        { "probe 2: a ray from the eye to each part's middle", function()
            local origin = crosshairRay()
            check("the camera's place is read", origin ~= nil)
            if not origin then
                return
            end
            local found, top, total = 0, 0, 0
            for _, p in ipairs(c.parts) do
                local m = try(function() return p.comp:GetLocalToWorld() end)
                if m then
                    local mid = { (p.box.min[1] + p.box.max[1]) / 2, (p.box.min[2] + p.box.max[2]) / 2,
                                  (p.box.min[3] + p.box.max[3]) / 2 }
                    local w = toWorld(m, mid)
                    local d = { w[1] - origin[1], w[2] - origin[2], w[3] - origin[3] }
                    local len = math.sqrt(d[1] ^ 2 + d[2] ^ 2 + d[3] ^ 2)
                    local hits = partsOnRay(c.parts, origin, { d[1] / len, d[2] / len, d[3] / len })
                    total = total + 1
                    local listed = false
                    for i, hit in ipairs(hits) do
                        if hit.name == p.name then
                            listed = true
                            if i == 1 then
                                top = top + 1
                            end
                        end
                    end
                    if listed then
                        found = found + 1
                    end
                    write(string.format("  %s (middle %.1f m away): %s", p.name, len, hitList(hits)))
                end
            end
            check("every part is listed under a ray to its middle", found == total, found .. " of " .. total)
            write("  the part itself first (smallest box) for " .. top .. " of " .. total)
        end, 1 },
        { "probe 2: what's under the crosshair now", function()
            local origin, dir = crosshairRay()
            if not origin then
                return
            end
            local hits = partsOnRay(c.parts, origin, dir)
            write("  under the crosshair: " .. hitList(hits))
            local at = try(function() return Game.GetTargetingSystem():GetLookAtPosition(Game.GetPlayer(), false, false) end)
            if at then
                write(string.format("  the game's look-at point: %.2f, %.2f, %.2f", at.x, at.y, at.z))
            end
            local picked = pickPart(hits)
            if picked then
                highlight(v(), picked.name, 1, 0, 1.0)
                c.lit = picked.name
            end
            shot("p2_crosshair")
        end, 2 },
        { "probe 3: the turret gun's data", function()
            if c.lit then
                highlight(v(), c.lit, 0, 0, 0.0)
                c.lit = nil
            end
            for _, field in ipairs({ "equipArea", "itemType", "itemCategory", "gameplayRestrictions", "OnEquip", "OnAttach",
                                     "attacks", "ammo", "mass", "canDrop", "dropObject", "dropSettings", "entityName",
                                     "appearanceResourceName", "appearanceName", "tags", "statModifiers",
                                     "statModifierGroups", "primaryTriggerMode", "triggerModes", "rangedAttacks",
                                     "effectors", "objectActions", "holsteredItem", "movementPattern", "isSingleInstance",
                                     "animFeatureName", "animName", "crosshair", "itemSecondaryAction" }) do
                local value = try(function() return TweakDB:GetFlat(PROBE_GUN .. "." .. field) end)
                write("  " .. field .. ": " .. (value == nil and "(none)" or describe(value)))
            end
            c.effectsBefore = effectNames()
            write("  V's status effects before: " .. table.concat(c.effectsBefore, ", "))
        end, 1 },
        { "probe 3: give V the turret gun and draw it", function()
            local player = Game.GetPlayer()
            try(function() Game.AddToInventory(PROBE_GUN, 1) end)
            for _, item in ipairs(try(function()
                local ok, items = Game.GetTransactionSystem():GetItemList(player)
                return items
            end) or {}) do
                local id = try(function() return item:GetID() end)
                if id and try(function() return TDBID.ToStringDEBUG(id.id) end) == PROBE_GUN then
                    c.gun = id
                end
            end
            check("the turret gun is in V's inventory", c.gun ~= nil)
            if c.gun then
                local evt = try(function() return RequestEquipHeavyWeapon.new() end)
                    or try(function() return NewObject("RequestEquipHeavyWeapon") end)
                check("the game's equip request for a heavy weapon is made", evt ~= nil)
                if evt then
                    evt.itemID = c.gun
                    player:QueueEvent(evt)
                end
            end
            return { what = "the turret gun in V's hands", timeout = 15, test = function() return heldRecord() == PROBE_GUN end }
        end, 3 },
        { "probe 3: holding it", function()
            check("V holds the turret gun", heldRecord() == PROBE_GUN, tostring(heldRecord()))
            local after = effectNames()
            local new = {}
            for _, name in ipairs(after) do
                local seen = false
                for _, old in ipairs(c.effectsBefore or {}) do
                    if old == name then
                        seen = true
                    end
                end
                if not seen then
                    table.insert(new, name)
                end
            end
            write("  status effects the gun added: " .. (#new > 0 and table.concat(new, ", ") or "none"))
            shot("p3_holding")
        end, 1 },
        { "YOUR TURN (2 min): look over the car (the part under the crosshair lights up), sprint, fire, then switch weapons", function()
            c.lastLit = nil
            return {
                what = "a weapon switch (the turret gun out of V's hands)",
                timeout = 120,
                optional = true,
                test = function()
                    local origin, dir = crosshairRay()
                    if origin and c.parts then
                        local hits = partsOnRay(c.parts, origin, dir)
                        local picked = pickPart(hits)
                        local top = picked and picked.name or nil
                        if top ~= c.lastLit then
                            if c.lastLit then
                                highlight(v(), c.lastLit, 0, 0, 0.0)
                            end
                            if top then
                                highlight(v(), top, 1, 0, 1.0)
                                write("  aimed at " .. top .. "; on the ray: " .. hitList(hits))
                            end
                            c.lastLit = top
                        end
                    end
                    return heldRecord() ~= PROBE_GUN
                end,
            }
        end, 3 },
        { "probe 3: after the switch", function()
            if c.lastLit then
                highlight(v(), c.lastLit, 0, 0, 0.0)
            end
            write("  in V's hands now: " .. tostring(heldRecord()))
            local still = c.gun and try(function() return Game.GetTransactionSystem():HasItem(Game.GetPlayer(), c.gun) end)
            write("  the turret gun still in V's inventory: " .. tostring(still))
            shot("p3_after_switch")
        end, 1 },
        { "clean up: the gun and the car", function()
            try(function() Game.GetTransactionSystem():RemoveItemByTDBID(Game.GetPlayer(), TweakDBID.new(PROBE_GUN), 1) end)
            if S.id then
                try(function() Game.GetDynamicEntitySystem():DeleteEntity(S.id) end)
            end
        end, 1 },
    }
end

-- Job "tool": the tool, our copy of the turret gun (Items.VC_ProbeTool: no weight packages, never fires; dev's
-- probe-tool.yaml and ProbeTool.reds), in the user's hands beside a Hella copy whose part under the crosshair
-- lights up green by the refined rule (pickPart). The user sprints, holds fire, drops it by switching weapons,
-- picks it up again and drops it again; the job counts refused shots, drops and pickups.
local PROBE_TOOL = "Items.VC_ProbeTool"

local function heldWeapon()
    return try(function()
        return Game.GetTransactionSystem():GetItemInSlot(Game.GetPlayer(), TweakDBID.new("AttachmentSlots.WeaponRight"))
    end)
end

local function isTool(item)
    if not item then
        return false
    end
    local id = try(function() return item:GetItemID().id end)
    if not id then
        return false
    end
    local want = TweakDBID.new(PROBE_TOOL)
    return try(function() return id.hash == want.hash and id.length == want.length end) == true
        or try(function() return TDBID.ToStringDEBUG(id) end) == PROBE_TOOL
end

local function toolGuard()
    return try(function() return Game.GetScriptableSystemsContainer():Get("VehicleCustomizerDev.ProbeToolGuard") end)
end

-- Whether a tool is in V's inventory (taken with "Take" rather than drawn with "Equip").
local function toolInInventory()
    local want = TweakDBID.new(PROBE_TOOL)
    for _, item in ipairs(try(function()
        local ok, items = Game.GetTransactionSystem():GetItemList(Game.GetPlayer())
        return items
    end) or {}) do
        local id = try(function() return item:GetID() end)
        if id and try(function() return id.id.hash == want.hash and id.id.length == want.length end) then
            return true
        end
    end
    return false
end

local function toolSteps()
    local bounds = try(function() return require("probe-bounds") end) or {}
    local c = { drops = 0, pickups = 0, taken = 0, nextBagCheck = 0 }
    local function v() return car() end
    return {
        { "tool: turn V and spawn the Hella copy in front", function()
            S.distance = 7
            turnV()
            try(function() Game.GetTimeSystem():SetGameTimeByHMS(18, 0, 0) end)
            return spawnCopy()
        end, 4 },
        { "tool: the record and the guard", function()
            c.parts = boxedParts(v(), bounds)
            check("the tool's record exists", try(function() return TweakDB:GetRecord(PROBE_TOOL) end) ~= nil)
            local attach = try(function() return TweakDB:GetFlat(PROBE_TOOL .. ".OnAttach") end)
            check("the tool has no weight packages", attach ~= nil and #attach == 0, attach and describe(attach) or "nil")
            check("the guard against firing runs", toolGuard() ~= nil)
            c.refusedBefore = try(function() return toolGuard():Refused() end) or 0
        end, 1 },
        { "tool: give it to V and draw it", function()
            local player = Game.GetPlayer()
            try(function() Game.AddToInventory(PROBE_TOOL, 1) end)
            for _, item in ipairs(try(function()
                local ok, items = Game.GetTransactionSystem():GetItemList(player)
                return items
            end) or {}) do
                local id = try(function() return item:GetID() end)
                local want = TweakDBID.new(PROBE_TOOL)
                if id and try(function() return id.id.hash == want.hash and id.id.length == want.length end) then
                    c.tool = id
                end
            end
            check("the tool is in V's inventory", c.tool ~= nil)
            if c.tool then
                local evt = try(function() return RequestEquipHeavyWeapon.new() end)
                    or try(function() return NewObject("RequestEquipHeavyWeapon") end)
                evt.itemID = c.tool
                player:QueueEvent(evt)
            end
            return { what = "the tool in V's hands", timeout = 15, test = function() return isTool(heldWeapon()) end }
        end, 2 },
        { "tool: in hand", function()
            check("V holds the tool", isTool(heldWeapon()))
            check("probe 4: our text is on the tool's screen", try(function() return toolGuard():HasScreen() end) == true)
            c.ammo = try(function() return WeaponObject.GetMagazineAmmoCount(heldWeapon()) end)
            write("  its magazine: " .. tostring(c.ammo))
            shot("t1_holding")
        end, 4 },
        { "YOUR TURN (3 min): aim over the car, sprint, hold fire, switch weapons to drop it, pick it up (R), drop it again", function()
            c.lastLit = nil
            c.held = true
            return {
                what = "the tool dropped twice",
                timeout = 180,
                optional = true,
                test = function()
                    local inHand = isTool(heldWeapon())
                    if c.held and not inHand then
                        c.drops = c.drops + 1
                        write("  dropped (" .. c.drops .. ")")
                    elseif not c.held and inHand then
                        c.pickups = c.pickups + 1
                        write("  picked up again (" .. c.pickups .. ")")
                    end
                    c.held = inHand
                    if not inHand and runner.clock >= c.nextBagCheck then
                        c.nextBagCheck = runner.clock + 0.5
                        local bag = toolInInventory()
                        if bag and not c.inBag then
                            c.taken = c.taken + 1
                            write("  taken into the inventory, not drawn (" .. c.taken .. ")")
                        end
                        c.inBag = bag
                    end
                    local origin, dir = crosshairRay()
                    if origin and c.parts then
                        local picked = pickPart(partsOnRay(c.parts, origin, dir))
                        local top = picked and picked.name or nil
                        if top ~= c.lastLit then
                            if c.lastLit then
                                highlight(v(), c.lastLit, 0, 0, 0.0)
                            end
                            if top then
                                highlight(v(), top, 1, 0, 1.0)
                            end
                            try(function() toolGuard():SetScreenText(top and top:gsub("_", " ") or "aim at a part") end)
                            c.lastLit = top
                        end
                    end
                    return c.drops >= 2
                end,
            }
        end, 2 },
        { "tool: what happened", function()
            if c.lastLit then
                highlight(v(), c.lastLit, 0, 0, 0.0)
            end
            local refused = (try(function() return toolGuard():Refused() end) or 0) - c.refusedBefore
            write("  frames with fire held and the shot refused: " .. refused)
            write("  times the weapon asked about a shot with the tool in hand: "
                .. tostring(try(function() return toolGuard():Asked() end)))
            write("  taken into the inventory instead of drawn: " .. c.taken)
            check("dropped by a weapon switch", c.drops >= 1, c.drops .. " drops")
            check("picked up again from the ground", c.pickups >= 1, c.pickups .. " pickups")
            write("  magazine when first drawn: " .. tostring(c.ammo))
            shot("t2_after")
        end, 4 },
        { "clean up: the tool and the car", function()
            try(function() Game.GetTransactionSystem():RemoveItemByTDBID(Game.GetPlayer(), TweakDBID.new(PROBE_TOOL), 1) end)
            if S.id then
                try(function() Game.GetDynamicEntitySystem():DeleteEntity(S.id) end)
            end
        end, 1 },
    }
end

-- Job "camera": probe 5, a live picture of one part. The game's TV streaming camera (ProbeCamera.reds) is
-- spawned 1.6 m from the near front wheel of a Hella copy, aimed at it, switched on, and its picture shown on the
-- HUD; then with a depth cut and a plain background (how close that gets to the part on its own), then from three
-- sides. Pictures only; nothing for the user to do but keep the game in front.
local function lookAt(from, to)
    local dx, dy, dz = to[1] - from[1], to[2] - from[2], to[3] - from[3]
    local yaw = math.atan2(-dx, dy)
    local pitch = math.atan2(dz, math.sqrt(dx * dx + dy * dy))
    local cz, sz, cx, sx = math.cos(yaw / 2), math.sin(yaw / 2), math.cos(pitch / 2), math.sin(pitch / 2)
    return Quaternion.new(cz * sx, sz * sx, sz * cx, cz * cx)
end

local function probeCamera()
    return try(function() return Game.GetScriptableSystemsContainer():Get("VehicleCustomizerDev.ProbeCamera") end)
end

local function cameraSteps()
    local bounds = try(function() return require("probe-bounds") end) or {}
    local c = {}
    local function v() return car() end
    local function placeCamera(angle)
        -- Around the wheel, from V's side of the car: angle 0 is straight out from the car's side.
        local mid, out = c.target, c.out
        local ca, sa = math.cos(angle), math.sin(angle)
        local dir = { out[1] * ca - out[2] * sa, out[1] * sa + out[2] * ca }
        local from = { mid[1] + dir[1] * 1.6, mid[2] + dir[2] * 1.6, mid[3] + 0.5 }
        local ok = try(function()
            return probeCamera():Spawn(Vector4.new(from[1], from[2], from[3], 1), lookAt(from, mid))
        end)
        return { what = "the camera to appear", timeout = 10, test = function()
            return ok and try(function() return probeCamera():IsHere() end) == true
        end }
    end
    return {
        { "camera: turn V and spawn the Hella copy in front", function()
            S.distance = 7
            turnV()
            try(function() Game.GetTimeSystem():SetGameTimeByHMS(18, 0, 0) end)
            return spawnCopy()
        end, 4 },
        { "camera: find the near front wheel", function()
            check("the camera probe's script runs", probeCamera() ~= nil)
            local parts = boxedParts(v(), bounds)
            local player = Game.GetPlayer():GetWorldPosition()
            local best, bestD
            for _, p in ipairs(parts) do
                if p.name:find("wheel_01_f", 1, true) or p.name:find("wheel_f", 1, true) then
                    local m = try(function() return p.comp:GetLocalToWorld() end)
                    if m then
                        local mid = toWorld(m, { (p.box.min[1] + p.box.max[1]) / 2, (p.box.min[2] + p.box.max[2]) / 2,
                                                 (p.box.min[3] + p.box.max[3]) / 2 })
                        local d = (mid[1] - player.x) ^ 2 + (mid[2] - player.y) ^ 2
                        if not bestD or d < bestD then
                            best, bestD, c.target, c.name = p, d, mid, p.name
                        end
                    end
                end
            end
            check("a front wheel to aim at", best ~= nil, tostring(c.name))
            if c.target then
                local carPos = v():GetWorldPosition()
                local ox, oy = c.target[1] - carPos.x, c.target[2] - carPos.y
                -- Straight out from the car's side: the car's own right or left, whichever faces the wheel.
                local r = v():GetWorldRight()
                local sign = (ox * r.x + oy * r.y) >= 0 and 1 or -1
                c.out = { r.x * sign, r.y * sign }
            end
        end, 1 },
        -- Second camera run (the first, 11:13: dark, then see-through, never the wheel): the picture shown before
        -- the camera is on, then switched on with nothing else changed, then render frequencies 1 and 30.
        { "camera: spawn the TV camera 1.6 m from the wheel", function() return placeCamera(0) end, 1 },
        { "camera: its picture on the HUD while it's still off", function()
            write("  " .. tostring(try(function() return probeCamera():Describe() end)))
            check("its picture is on the HUD", try(function() return probeCamera():ShowFeed() end) == true)
        end, 2 },
        { "picture", function() shot("k0_off") end, 4 },
        { "camera: switch it on, nothing else changed", function()
            write("  " .. tostring(try(function() return probeCamera():SwitchOnly(true) end)))
        end, 1 },
        { "picture", function() shot("k1_on_1s") end, 1 },
        { "wait", function() end, 2 },
        { "picture", function() shot("k2_on_4s") end, 4 },
        -- Third camera run (the second, 11:19, showed the tyre live once the image named its part "stuff", but
        -- very dark): brighter by the image's tint, then the depth cut and plain background to isolate the wheel.
        { "camera: brighter, tint 3", function() try(function() probeCamera():SetBrightness(3.0) end) end, 1 },
        { "picture", function() shot("r1_tint3") end, 4 },
        { "camera: tint 6", function() try(function() probeCamera():SetBrightness(6.0) end) end, 1 },
        { "picture", function() shot("r2_tint6") end, 4 },
        { "camera: wider (fov 40), depth cut 2.2 m, plain background", function()
            write("  " .. tostring(try(function() return probeCamera():Enable(40.0, 2.2, true) end)))
        end, 3 },
        { "picture", function() shot("r3_cut_plain") end, 4 },
        { "camera: depth cut 2.2 m, no plain background", function()
            write("  " .. tostring(try(function() return probeCamera():Enable(40.0, 2.2, false) end)))
        end, 3 },
        { "picture", function() shot("r4_cut_only") end, 4 },
        { "camera: depth cut 1.9 m, plain background", function()
            write("  " .. tostring(try(function() return probeCamera():Enable(40.0, 1.9, true) end)))
        end, 3 },
        { "picture", function() shot("r5_cut_1_9_plain") end, 4 },
        { "clean up: the camera, its picture and the car", function()
            try(function() probeCamera():Remove() end)
            if S.id then
                try(function() Game.GetDynamicEntitySystem():DeleteEntity(S.id) end)
            end
        end, 1 },
    }
end

-- Job "toolui": the real tool (mod's Tool.reds, tool.yaml: the Kyubi stand-in) on a Hella copy in front of V. A
-- test ray stands in for the camera (VCTool.TestAim) and Press stands in for the arrow keys: the hood picked,
-- another hood tried on and undone, the car's style changed and undone; then the user tries it by hand.
local function vcTool()
    return try(function() return Game.GetScriptableSystemsContainer():Get("VehicleCustomizer.VCTool") end)
end

local function toolUiSteps()
    local bounds = try(function() return require("probe-bounds") end) or {}
    -- Arg "keep" (run with -KeepGameOpen): no timed turn and no clean-up, the tool and the Hella left for the user.
    local keep = try(function() return TweakDB:GetFlat("VehicleCustomizerDev.arg") end) == "keep"
    local c = {}
    local function v() return car() end
    local function screen() return tostring(try(function() return vcTool():ScreenText() end)) end
    local function press(key)
        try(function() vcTool():Press(CName.new(key)) end)
        write("  " .. key .. ": " .. screen())
    end
    local function buildText() return try(function() return engine():GetBuildText(rid()) end) or "" end
    -- The screen's lines say this text, as it is (a chosen item is in brackets: "[Size]").
    local function rowHas(text) return screen():find(text, 1, true) ~= nil end
    -- Right along the row you're on until the item is chosen.
    local function toKind(label)
        for _ = 1, 6 do
            if rowHas(label) then
                return true
            end
            press("right")
        end
        return rowHas(label)
    end
    -- A key, then wait for the car to be rebuilt (each rebuild switches it to its other twin look).
    local function rebuiltAfter(key, what)
        local before = lookOf(v())
        press(key)
        return { what = what, timeout = 12, test = function() return lookOf(v()) ~= before end }
    end
    return {
        { "toolui: turn V and spawn the Hella copy in front", function()
            S.distance = 7
            turnV()
            try(function() Game.GetTimeSystem():SetGameTimeByHMS(18, 0, 0) end)
            try(function() engine():SetBuildText(rid(), "") end)
            return spawnCopy()
        end, 4 },
        { "toolui: hand over the tool", function()
            check("the tool system runs", vcTool() ~= nil)
            check("the tool's record exists", try(function() return TweakDB:GetRecord("Items.VC_Tool") end) ~= nil)
            check("the tool is handed over", try(function() return vcTool():Give() end) == true)
            return { what = "the tool in V's hands", timeout = 15, test = function() return try(function() return vcTool():IsHeld() end) == true end }
        end, 3 },
        { "toolui: its screen", function()
            check("our screen is on the tool", try(function() return vcTool():HasScreen() end) == true, screen())
            shot("u1_holding")
        end, 4 },
        { "toolui: aim a test ray at the front bumper (the hood has no alternative on this Hella)", function()
            local parts = boxedParts(v(), bounds)
            local origin = crosshairRay()
            for _, p in ipairs(parts) do
                if p.name:find("bumper_f", 1, true) then
                    local m = p.comp:GetLocalToWorld()
                    local mid = toWorld(m, { (p.box.min[1] + p.box.max[1]) / 2, (p.box.min[2] + p.box.max[2]) / 2,
                                             (p.box.min[3] + p.box.max[3]) / 2 })
                    c.dir = { mid[1] - origin[1], mid[2] - origin[2], mid[3] - origin[3] }
                end
            end
            check("the front bumper is found", c.dir ~= nil)
            if c.dir then
                try(function()
                    vcTool():TestAim(v(), Vector4.new(origin[1], origin[2], origin[3], 1),
                        Vector4.new(c.dir[1], c.dir[2], c.dir[3], 0), true)
                end)
            end
        end, 2 },
        { "toolui: what the screen says", function()
            local text = screen()
            write("  screen: " .. text)
            -- Seen from V's side, the ray to the bumper's middle passes the front tire's box first; step along the
            -- tabs to the bumper as a player would.
            for _ = 1, 6 do
                if screen():lower():find("%[[^%]]*bumper[^%]]*%]") then
                    break
                end
                press("right")
            end
            check("the bumper's tab is chosen", screen():lower():find("%[[^%]]*bumper[^%]]*%]") ~= nil, screen())
            shot("u2_bumper_row0")
        end, 4 },
        { "toolui: down: what to change on it", function()
            press("down")
            check("in the what-to-change row", try(function() return vcTool():Row() end) == 1, screen())
        end, 1 },
        { "picture", function() shot("u3_row1") end, 4 },
        { "toolui: down: the bumpers", function()
            press("down")
            check("in the choices row", try(function() return vcTool():Row() end) == 2, screen())
            c.before = buildText()
        end, 1 },
        { "picture", function() shot("u4_row2") end, 4 },
        { "toolui: right: the other bumper, put on after resting", function()
            press("right")
            local before = lookOf(v())
            return { what = "the car rebuilt with the other bumper", timeout = 12, test = function() return lookOf(v()) ~= before end }
        end, 2 },
        { "toolui: check the bumper", function()
            local now = buildText()
            check("the build has another bumper now", now ~= c.before and now:find("bumper", 1, true) ~= nil, now)
            write("  screen: " .. screen())
            shot("u5_other_bumper")
        end, 4 },
        { "toolui: backspace undoes", function()
            local before = lookOf(v())
            press("back")
            return { what = "the car rebuilt back", timeout = 12, test = function() return lookOf(v()) ~= before end }
        end, 2 },
        { "toolui: check the undo", function()
            -- Undoing a car's first change leaves "look=<its look>", not an empty build (the undo fix, 2026-11-07).
            check("the bumper is undone", not buildText():find("slot=", 1, true), buildText())
        end, 1 },
        { "toolui: up, up, left to the car's tab, down into its style", function()
            press("up")
            press("up")
            for _ = 1, 6 do
                if screen():find("%[Whole car%]") then
                    break
                end
                press("left")
            end
            check("the car's tab", screen():find("%[Whole car%]") ~= nil, screen())
            press("down")
            press("down")
            c.look = lookOf(v())
            press("right")
            return { what = "the car in another style", timeout = 12, test = function() return lookOf(v()) ~= c.look end }
        end, 3 },
        { "toolui: check the style, picture", function()
            write("  look now " .. lookOf(v()) .. "; screen: " .. screen())
            -- The car's tab holds only what spans the car (UX.md, "Where options live", 2026-11-07).
            check("no wheels on the car's tab", not screen():find("Wheels", 1, true), screen())
            shot("u6_style")
        end, 4 },
        { "toolui: undo the style", function()
            c.styled = lookOf(v())
            press("back")
            return { what = "the style undone", timeout = 12, test = function() return lookOf(v()) ~= c.styled end }
        end, 2 },
        { "toolui: check the undo brought the style back", function()
            check("the car's own style is back", not lookOf(v()):find("combatcab", 1, true), lookOf(v()))
            shot("u7_undone")
        end, 3 },
        -- Rims and tires on their own parts (2026-11-07): aimed at the nearest rim, its tab has every rim, its
        -- paint, its width and which wheels (that axle unless all are chosen); the tire's has every tire, the
        -- wheel's size, the tire's width and which wheels. Each width changes its own part only.
        { "toolui: up to the tabs, aim at the nearest rim", function()
            press("up")
            press("up")
            local origin = crosshairRay()
            local best, bestDist = nil, math.huge
            for _, p in ipairs(boxedParts(v(), bounds)) do
                -- Any rim: this Hella wears the Quadra's back rim (wheel_bl_01) on all four (run of 15:43).
                if p.box.path:find("__ext01_wheel_", 1, true) then
                    local m = p.comp:GetLocalToWorld()
                    local mid = toWorld(m, { (p.box.min[1] + p.box.max[1]) / 2, (p.box.min[2] + p.box.max[2]) / 2,
                                             (p.box.min[3] + p.box.max[3]) / 2 })
                    local d = { mid[1] - origin[1], mid[2] - origin[2], mid[3] - origin[3] }
                    local dist = math.sqrt(d[1] * d[1] + d[2] * d[2] + d[3] * d[3])
                    if dist < bestDist then
                        best, bestDist = d, dist
                    end
                end
            end
            check("a rim to aim at", best ~= nil)
            if best then
                try(function()
                    vcTool():TestAim(v(), Vector4.new(origin[1], origin[2], origin[3], 1),
                        Vector4.new(best[1], best[2], best[3], 0), true)
                end)
            end
        end, 2 },
        { "toolui: the rims' tab, down", function()
            write("  screen: " .. screen())
            for _ = 1, 6 do
                if screen():match("%[(%a+) rims%]") then
                    break
                end
                press("right")
            end
            c.Axle = screen():match("%[(%a+) rims%]")
            check("a rims' tab", c.Axle ~= nil, screen())
            c.Axle = c.Axle or "Front"
            c.a, c.o = (c.Axle == "Front") and "f" or "b", (c.Axle == "Front") and "b" or "f"
            check("its tires' tab beside it", screen():find(c.Axle .. " tires", 1, true) ~= nil, screen())
            press("down")
            check("rim, width, and its own axle's wheels by default", rowHas("[Rim]") and rowHas("Width")
                and rowHas(c.Axle .. " wheels"), screen())
            shot("u8_rims_row1")
        end, 4 },
        { "toolui: down: every rim; right: the next one, put on after resting", function()
            press("down")
            local count = tonumber(screen():match("%d+ of (%d+)") or "0")
            check("every rim to choose from (over 100)", count > 100, screen())
            c.before = buildText()
            return rebuiltAfter("right", "the car rebuilt with another rim")
        end, 2 },
        { "toolui: check the rim went on this axle only", function()
            local now = buildText()
            check("the rims on this axle", now:find("rims@" .. c.a .. "=", 1, true) ~= nil, now)
            check("not the other", now:find("rims@" .. c.o .. "=", 1, true) == nil and now:find("rims=", 1, true) == nil, now)
            check("and no tires", now:find("tires", 1, true) == nil, now)
            write("  screen: " .. screen())
            shot("u9_other_rim")
            return rebuiltAfter("back", "the rim undone")
        end, 2 },
        { "toolui: check the undo; up, to the rim's Width, down; right: 105%", function()
            check("the rim is undone", buildText() == c.before, buildText())
            press("up")
            check("on the rim's Width", toKind("[Width]"), screen())
            press("down")
            check("at its automatic width", screen():find("100%% %(auto%)") ~= nil, screen())
            return rebuiltAfter("right", "the car rebuilt with wider rims")
        end, 2 },
        { "toolui: check only the rims got wider", function()
            local now = buildText()
            check("this axle's rims 105% wide, the tires and the wheel's size as they were",
                now:find("fit@" .. c.a .. "=100:100:105", 1, true) ~= nil, now)
            check("the other axle as it was", now:find("fit@" .. c.o .. "=", 1, true) == nil, now)
            shot("u10_wider_rims")
            return rebuiltAfter("back", "the rims' width undone")
        end, 2 },
        { "toolui: up, up, to this axle's tires' tab, down, to Size, down; right: 105%", function()
            check("the rims' width is undone", buildText() == c.before, buildText())
            press("up")
            press("up")
            for _ = 1, 6 do
                if rowHas("[" .. c.Axle .. " tires]") then
                    break
                end
                press("right")
            end
            check("the tires' tab", rowHas("[" .. c.Axle .. " tires]"), screen())
            press("down")
            check("tire, size, width, and its own axle's wheels by default", rowHas("[Tire]") and rowHas("Size")
                and rowHas("Width") and rowHas(c.Axle .. " wheels"), screen())
            check("on Size", toKind("[Size]"), screen())
            press("down")
            check("at its own size", screen():find("100%% %(own size%)") ~= nil, screen())
            return rebuiltAfter("right", "the car rebuilt with bigger wheels on this axle")
        end, 2 },
        { "toolui: check the size, this axle only", function()
            local now = buildText()
            check("this axle's wheels 105%", now:find("fit@" .. c.a .. "=105:100", 1, true) ~= nil, now)
            check("the other axle as it was", now:find("fit@" .. c.o .. "=", 1, true) == nil, now)
            shot("u11_bigger_wheels")
            return rebuiltAfter("back", "the size undone")
        end, 2 },
        { "toolui: up, to the tire's Width, down; right: 105%", function()
            check("the size is undone", buildText() == c.before, buildText())
            press("up")
            check("on the tire's Width", toKind("[Width]"), screen())
            press("down")
            check("at its automatic width", screen():find("100%% %(auto%)") ~= nil, screen())
            return rebuiltAfter("right", "the car rebuilt with wider tires")
        end, 2 },
        { "toolui: check only the tires got wider", function()
            local now = buildText()
            -- The rim's width is the third number, written only when it isn't its own.
            check("this axle's tires 105% wide, the rims as they were", now:find("fit@" .. c.a .. "=100:105", 1, true) ~= nil
                and now:find("fit@" .. c.a .. "=100:105:", 1, true) == nil, now)
            shot("u12_wider_tires")
            return rebuiltAfter("back", "the tires' width undone")
        end, 2 },
        { "toolui: all wheels, then Size 105%", function()
            check("the tires' width is undone", buildText() == c.before, buildText())
            press("up")
            check("on which wheels", toKind("[" .. c.Axle .. " wheels]"), screen())
            press("down")
            press("right")
            press("enter")
            press("up")
            check("all wheels chosen", rowHas("[All wheels]"), screen())
            check("on Size again", toKind("[Size]"), screen())
            press("down")
            return rebuiltAfter("right", "the car rebuilt with bigger wheels all round")
        end, 2 },
        { "toolui: check every wheel changed", function()
            local now = buildText()
            check("every wheel 105%", now:find("fit@f=105:100", 1, true) ~= nil and now:find("fit@b=105:100", 1, true) ~= nil, now)
            shot("u13_bigger_all_round")
            return rebuiltAfter("back", "the size undone")
        end, 2 },
        { "toolui: another tab and back: this axle again; aim by hand from now", function()
            check("the size is undone", buildText() == c.before, buildText())
            press("up")
            press("up")
            press("left")
            press("right")
            press("down")
            check("back to this axle's wheels", rowHas(c.Axle .. " wheels") and not rowHas("All wheels"), screen())
            press("up")
            try(function() vcTool():TestAim(v(), Vector4.new(0, 0, 0, 1), Vector4.new(0, 1, 0, 0), false) end)
        end, 3 },
        { "YOUR TURN (3 min): aim the tool at the Hella, arrows to move, Enter puts on, Backspace undoes; switch weapons when done", function()
            if keep then
                write("  kept: the tool and the Hella stay for the user")
                return
            end
            return { what = "the tool out of V's hands", timeout = 180, optional = true,
                     test = function() return try(function() return vcTool():IsHeld() end) == false end }
        end, 2 },
        { "clean up: the tool and the car", function()
            if keep then
                return
            end
            try(function() Game.GetTransactionSystem():RemoveItemByTDBID(Game.GetPlayer(), TweakDBID.new("Items.VC_Tool"), 1) end)
            try(function() engine():SetBuildText(rid(), "") end)
            if S.id then
                try(function() Game.GetDynamicEntitySystem():DeleteEntity(S.id) end)
            end
        end, 1 },
    }
end

-- Job "toolready" (run with -KeepGameOpen): a Hella copy in front of V and the tool in V's hands, then the game is
-- the user's. Nothing tested.
local function toolReadySteps()
    return {
        { "toolready: turn V and spawn the Hella copy in front", function()
            S.distance = 7
            turnV()
            try(function() Game.GetTimeSystem():SetGameTimeByHMS(18, 0, 0) end)
            try(function() engine():SetBuildText(rid(), "") end)
            return spawnCopy()
        end, 3 },
        { "toolready: the tool in V's hands", function()
            check("the tool is handed over", try(function() return vcTool():Give() end) == true)
            return { what = "the tool in V's hands", timeout = 15, test = function() return try(function() return vcTool():IsHeld() end) == true end }
        end, 2 },
    }
end

local JOBS = {
    -- Each job is a list of steps: { "description", function() ... end, wait seconds after }. A step may return
    -- { what = "...", timeout = s, test = function() return done end } to wait for something before the next.
    dump = {
        { "screenshot of the loaded world", function() shot("world") end, 2 },
        { "dump every vehicle record", dumpVehicleRecords, 1 },
    },
    suite = SUITE,
    persist_save = PERSIST_SAVE,
    persist_check = PERSIST_CHECK,
    prepare = PREPARE,
    sweep = function() return sweepSteps(1) end,
    sweep_b = function() return sweepSteps(2) end,
    repair = REPAIR,
    wheels = WHEELS,
    buy = function() return buySteps() end,
    own = function() return ownSteps() end,
    session = function() return sessionSteps() end,
    probes = function() return probeSteps() end,
    tool = function() return toolSteps() end,
    camera = function() return cameraSteps() end,
    toolui = function() return toolUiSteps() end,
    toolready = function() return toolReadySteps() end,
}

local function finish()
    write(string.format("DONE %d passed, %d failed", runner.passes, runner.fails))
    runner.steps = nil
end

-- The main menu's stand-in player exists before any save loads (first run, 2026-11-06), so the runner waits
-- for the dev script to have continued the save, then for the player to attach in the loaded world.
local function menuContinued()
    local state = try(function() return Game.GetScriptableServiceContainer():GetService("VehicleCustomizerDev.AutoLoadState") end)
    return state ~= nil and (try(function() return state:IsDone() end) or try(function() return state.done end)) == true
end

-- A save can also load without the dev script's Continue: a Space tap of the run script on the main menu, a click,
-- or a session hosted from the Co-op screen (2026-11-07 morning: the world was there by 09:11:17 with "0 tries",
-- and the runner waited at "menu not here" until stopped). The game's own "still at the main menu" tells the
-- menu's stand-in player from a loaded world, as other CET mods do it.
local function savedWorldHere()
    return Game.GetPlayer() ~= nil
        and try(function() return GetSingleton("inkMenuScenario"):GetSystemRequestsHandler():IsPreGame() end) == false
end

-- The engine's own notes, as they come, into the report.
local function copyEngineLog()
    local e = engine()
    if not e then
        return
    end
    local count = try(function() return e:GetLogCount() end) or 0
    runner.engineSeen = runner.engineSeen or 0
    while runner.engineSeen < count do
        local line = try(function() return e:GetLogLine(runner.engineSeen) end) or ""
        if line ~= "" then
            write("  engine: " .. line)
        end
        runner.engineSeen = runner.engineSeen + 1
    end
end

local function tick(delta)
    runner.clock = runner.clock + delta
    if not runner.enabled then
        return
    end
    if not runner.started then
        if not runner.continued then
            if menuContinued() then
                runner.continued = true
                runner.attachedAt = nil
                write("main menu continued the newest save; waiting for the world")
            elseif runner.attachedAt and savedWorldHere() then
                runner.continued = true
                write("a save loaded without the runner's Continue (a tap, a click or Co-op); waiting for the world")
            elseif runner.clock >= (runner.nextRetry or 0) then
                -- Ask the auto-continue again, and say every 10 s where it stands.
                runner.nextRetry = runner.clock + 5
                local state = try(function() return Game.GetScriptableServiceContainer():GetService("VehicleCustomizerDev.AutoLoadState") end)
                if state then
                    -- The run script writes autotest-go.txt once its Space taps should have closed the start screen.
                    local go = io.open("autotest-go.txt", "r")
                    if go then
                        go:close()
                        if not runner.toldGone then
                            runner.toldGone = true
                            write("the run script says the start screen is gone")
                        end
                        try(function() state:StartScreenGone() end)
                    end
                    try(function() state:Retry() end)
                    runner.retries = (runner.retries or 0) + 1
                    if runner.retries % 2 == 0 then
                        write("waiting at the menu: " .. tostring(try(function() return state:Describe() end)))
                    end
                end
            end
            return
        end
        if not runner.attachedAt or not Game.GetPlayer() then
            return
        end
        if runner.clock - runner.attachedAt < 15 then
            return -- let the world settle, and the run script's taps close the loading screen's "press to continue"
        end
        runner.started = true
        runner.steps = JOBS[runner.job]
        if type(runner.steps) == "function" then
            runner.steps = runner.steps() -- a job made from what's in TweakDB, such as "sweep"
        end
        runner.stepIndex = 0
        runner.waitUntil = runner.clock
        write("world loaded; job " .. tostring(runner.job))
        if not runner.steps then
            write("FAIL no such job")
            finish()
        end
        return
    end
    copyEngineLog()
    if not runner.steps then
        return
    end
    local waiting = runner.waitFor
    if waiting then
        local ok, done = pcall(waiting.test)
        if ok and done then
            write(string.format("  done waiting for %s (%.1f s)", waiting.what, runner.clock - waiting.since))
            runner.waitFor = nil
            runner.waitUntil = runner.clock + waiting.after
        elseif runner.clock - waiting.since > waiting.timeout then
            if waiting.optional then
                write("NOTE step " .. runner.stepIndex .. ": gave up waiting for " .. waiting.what)
            else
                check("step " .. runner.stepIndex .. " finished", false, "timed out waiting for " .. waiting.what)
            end
            runner.waitFor = nil
            runner.waitUntil = runner.clock + waiting.after
        end
        return
    end
    if runner.clock < runner.waitUntil then
        return
    end
    runner.stepIndex = runner.stepIndex + 1
    local step = runner.steps[runner.stepIndex]
    if not step then
        finish()
        return
    end
    write("step " .. runner.stepIndex .. ": " .. step[1])
    local ok, result = pcall(step[2])
    if not ok then
        check("step " .. runner.stepIndex .. " ran", false, tostring(result))
    elseif type(result) == "table" and result.test then
        result.since = runner.clock
        result.after = step[3] or 1
        result.timeout = result.timeout or 10
        runner.waitFor = result
        return
    end
    runner.waitUntil = runner.clock + (step[3] or 1)
end

registerForEvent("onInit", function()
    pcall(require("scout").init)
    runner.enabled = try(function() return TweakDB:GetFlat("VehicleCustomizerDev.autotest") end) == true
    runner.job = try(function() return TweakDB:GetFlat("VehicleCustomizerDev.job") end)
    if runner.enabled then
        local file = io.open(REPORT, "w")
        if file then
            file:close()
        end
        write("runner on; job " .. tostring(runner.job) .. "; waiting for the save to load")
        -- Every attach counts, the main menu's stand-in's too: the Continue above forgets it, and a world loaded
        -- some other way needs the attach to be known (savedWorldHere).
        ObserveAfter("PlayerPuppet", "OnGameAttached", function()
            runner.attachedAt = runner.clock
        end)
    end
end)

-- The dev panel (panel.lua), drawn while CET's overlay is open; switched off for the session if it errors.
local panel = require("panel")
-- The shop scouting window (scout.lua), the same way; its teleport also needs every frame (scout.update).
local scout = require("scout")
-- Its capture key, bound to Page Down in CET's bindings.json: a screenshot and what V looks at, for Claude.
registerHotkey("scoutCapture", "Shop scouting: capture the scene", function()
    local ok, problem = pcall(scout.capture)
    if not ok then
        print("[VehicleCustomizerDev] capture failed: " .. tostring(problem))
    end
end)
local overlayOpen = false
local panelBroken = false
local scoutBroken = false
registerForEvent("onOverlayOpen", function() overlayOpen = true end)
registerForEvent("onOverlayClose", function() overlayOpen = false end)
registerForEvent("onDraw", function()
    if overlayOpen and not panelBroken then
        local ok, problem = pcall(panel.draw)
        if not ok then
            panelBroken = true
            print("[VehicleCustomizerDev] the panel stopped on an error: " .. tostring(problem))
        end
    end
    if overlayOpen and not scoutBroken then
        local ok, problem = pcall(scout.draw)
        if not ok then
            scoutBroken = true
            print("[VehicleCustomizerDev] the scouting window stopped on an error: " .. tostring(problem))
        end
    end
end)

registerForEvent("onUpdate", function(delta)
    local scoutOk, scoutProblem = pcall(scout.update, delta)
    if not scoutOk then
        scout.going = nil
        print("[VehicleCustomizerDev] scouting teleport stopped on an error: " .. tostring(scoutProblem))
    end
    local ok, problem = pcall(tick, delta)
    if not ok then
        write("FAIL runner error: " .. tostring(problem))
        finish()
        runner.enabled = false
    end
end)
