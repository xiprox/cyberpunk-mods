-- Scouting shop candidates (SHOPS.md): teleport near a place, not into it, look around, clear out enemies,
-- mark spots for the record. A dev aid while the user picks the shops; drawn while CET's overlay is open.
local scout = { status = "", note = "" }

local STANDOFF = 50 -- metres from the place: near enough to walk, far enough not to land in a gig's fight
-- V is held in the air while the place streams in: from 1.5 s on it looks for walkable ground twice a second,
-- and gives up after 8 s (across the map, loading can take a while).
local FIRST_TRY, GIVE_UP = 1.5, 8

-- From SHOPS.md (garages.py's sites). feel is a guess from who the place's job involves.
local places = {
    { group = "With a car lift" },
    { "Jake Estevez's garage", "Heywood, The Glen", "6th Street front", -1439.1, -1293.8, 46.8,
      "6th Street's garage, where Jake Estevez tuned their cars. Gig: take back the car Jake built (upload software at the computer), bring it to Jake, who leaves town." },
    { "Garage no. 66", "Santo Domingo, Rancho Coronado", "shady", 254.8, -1089.1, 21.4,
      "Car lift. Gig: find Garage no. 66 and destroy a server in it; a scavenger van." },
    { "Hal Cantos's workshop", "Watson, Northside", "legit-ish", -1219.1, 2263.2, 7.0,
      "Car lift. Gig: a cyberpsycho in the workshop; Moxes involved." },
    { "Workshop with the mechanical press", "Westbrook, Japantown", "?", -243.1, 1619.6, 41.2,
      "Car lift, maybe upstairs (41 m). Gig: find Lauren Costigan in the basement; keycard, elevator." },
    { "6th Street workshop at a Kang Tao site", "Santo Domingo, Arroyo", "shady", -635.5, -1155.1, 7.8,
      "Car lift. El Capitan's gig: Kang Tao, two 6th Street mechanics. Next door: the garage from Claire's racing jobs." },
    { "Scrapyard by the landfill", "Badlands", "very shady", 1399.1, -1674.3, 49.3,
      "3 car lifts, 277 pieces of wrecks. Gig: find a robot, with a technician." },
    { "Scrapyard in Arroyo", "Santo Domingo, Arroyo", "shady", -26.0, -1034.9, 7.5,
      "2 car lifts, 48 tires, 167 pieces of wrecks. An NCPD job." },
    { "Big Pete's place", "Badlands", "very shady", -148.2, -4416.0, 58.8,
      "Car lift. Gig: find and kill Big Pete; his goons shoot at a car." },
    { "Badlands lot", "Badlands, south", "shady", -1285.5, -4237.4, 62.7,
      "Car lift, 10 pieces of wrecks. An NCPD job." },
    { "Raffen Shiv camp", "Badlands, east", "very shady", 2989.3, -2381.3, 118.5,
      "A car jack and a forklift. A side quest at the camp (sq004)." },
    { "Unknown lift, City Center's west edge", "City Center", "?", -2312.8, 471.5, 7.3,
      "Car lift, 9 tires. No job of its own found; a minor quest's meeting (mq304) nearby." },
    { "Unknown lift", "?", "?", -1578.1, 635.7, 9.3,
      "Car lift, 3 tires. No named place within 150 m." },
    { group = "Without a lift" },
    { "Wellsprings body shop", "Heywood, Wellsprings", "legit-looking", -2461.5, -912.2, 9.2,
      "2 big shutters. Gig: Valentinos and a Nomad truck, driven out of the garage. A Nexus mod says the gates don't open." },
    { "The Nomad start's garage", "Badlands, far south", "legit", -3963.0, -6483.7, 75.8,
      "The Nomad prologue's garage, with a garage gate device." },
    { "The church garage", "Badlands, south-west", "shady-ish", -3463.0, -4056.3, 75.0,
      "By the Nomad hideout barn; tires, tools." },
    { "Row of garage sheds", "Santo Domingo, Rancho Coronado", "?", 380.0, -1990.0, -2.0,
      "Ten Badlands-style garage buildings; inside unknown." },
    { "Lone garage", "Rancho Coronado", "?", 509.4, -1820.5, 28.5, "A Badlands-style garage building." },
    { "Lone garage", "Badlands", "?", -99.1, -4220.4, 42.5, "A Badlands-style garage building, near Big Pete's." },
    { "Lone garage", "Badlands, east", "?", 3201.6, 670.7, 105.3, "A Badlands-style garage building." },
    { "Lone garage", "Badlands, far east", "?", 4253.8, -428.7, 148.1, "A Badlands-style garage building." },
    { "Lone garage", "Badlands, south", "?", -1127.0, -5599.7, 93.0, "A Badlands-style garage building." },
    { "Workshop building", "Badlands, south-west", "?", -2870.9, -4691.2, 21.5, "A building named workshop." },
    { group = "Busy, for comparison" },
    { "Kabuki market mechanics", "Watson, Kabuki", "busy", -1033.9, 1357.0, 7.9, "Mechanics at work, 77 people around." },
    { "Delamain's garage", "Heywood, Vista del Rey", "busy", -945.5, -114.2, 7.7, "Delamain's HQ." },
    { "Badlands workshop", "Badlands", "busy", 2416.8, -782.3, 67.9, "An NCPD job; 44 people around." },
    { "Badlands gas station", "Badlands", "busy", -1859.5, -4278.4, 75.1, "From a main quest (q104); 36 people around." },
}

local function say(text)
    scout.status = text
    print("[VehicleCustomizerDev] " .. text)
end

local function yawTowards(fx, fy, tx, ty)
    return math.deg(math.atan2(-(tx - fx), ty - fy))
end

local function place(player, x, y, z, yaw)
    Game.GetTeleportationFacility():Teleport(player, Vector4.new(x, y, z, 1), EulerAngles.new(0, 0, yaw))
end

-- A walkable point (the NPCs' navmesh) about STANDOFF metres from the place, at about its height.
local function landing(p)
    local nav = Game.GetNavigationSystem()
    local best, bestDz
    local standoff = p.standoff or STANDOFF
    for i = 0, 15 do
        local a = math.rad(i * 22.5)
        local cx, cy = p.x + standoff * math.cos(a), p.y + standoff * math.sin(a)
        local ok, point = pcall(function()
            local res = nav:FindPointInSphereOnlyHumanNavmesh(Vector4.new(cx, cy, p.z, 1), 12, NavGenAgentSize.Human, false)
            if res and EnumInt(res.status) == 0 then -- worldNavigationRequestStatus.OK
                return res.point
            end
        end)
        if ok and point then
            local dz = math.abs(point.z - p.z)
            if dz < 8 and (not best or dz < bestDz) then
                best, bestDz = point, dz
            end
        end
    end
    return best
end

-- Below the held spot, if no walkable point was found: the first static surface under V.
local function groundBelow(x, y, z)
    local ok, hit, trace = pcall(function()
        return Game.GetSpatialQueriesSystem():SyncRaycastByCollisionGroup(
            Vector4.new(x, y, z + 30, 1), Vector4.new(x, y, z - 60, 1), CName.new("Static"), true, false)
    end)
    if ok and hit and trace and trace.position then
        return trace.position
    end
    return nil
end

-- A map pin on the place itself (on the map, the minimap and in the world), so V can tell where it is.
-- The player's own custom-marker look; pins live until cleared or the next load.
local function setPin(p, on)
    local mappins = Game.GetMappinSystem()
    if on and not p.pin then
        local data = MappinData.new()
        data.mappinType = TweakDBID.new("Mappins.DefaultStaticMappin")
        data.variant = gamedataMappinVariant.CustomPositionVariant
        data.active = true
        data.visibleThroughWalls = true
        p.pin = mappins:RegisterMappin(data, Vector4.new(p.x, p.y, p.z + 1, 1))
    elseif not on and p.pin then
        pcall(function() mappins:UnregisterMappin(p.pin) end)
        p.pin = nil
    end
end

local function goNear(p)
    local player = Game.GetPlayer()
    if not player then
        return
    end
    pcall(setPin, p, true)
    if player:GetMountedVehicle() then
        say("Get out of the car first; call it once you're there.")
        return
    end
    local here = player:GetWorldPosition()
    local f = player:GetWorldForward()
    scout.back = { x = here.x, y = here.y, z = here.z, yaw = math.deg(math.atan2(-f.x, f.y)) }
    local hx, hy, hz = p.x + (p.standoff or STANDOFF), p.y, p.z + 2
    scout.going = { p = p, x = hx, y = hy, z = hz, yaw = yawTowards(hx, hy, p.x, p.y), t = 0 }
    say("Going near " .. p.name .. "; holding V in the air while it loads...")
end

-- Claude's command file: Claude writes commands to claude-command.txt in this mod's folder, one per line, and
-- reads the answers from claude-reply.txt, so the user doesn't paste console lines. Checked twice a second.
--   goto x y z [yaw]           teleport exactly there
--   near x y z [metres] [name] land on walkable ground that far from the spot (50 m when left out), facing it
--   facts name ...              reply with each quest fact's value
--   setfact name value          set a quest fact (only on the user's word)
--   where                       reply with V's position and heading
--   capture [note]              the capture key's screenshot and scene data
local COMMANDS, REPLIES = "claude-command.txt", "claude-reply.txt"
local pollIn = 0

local function reply(text)
    local file = io.open(REPLIES, "a")
    if file then
        file:write(os.date("%H:%M:%S ") .. text .. "\n")
        file:close()
    end
end

local function runCommand(line)
    local words = {}
    for w in line:gmatch("%S+") do
        words[#words + 1] = w
    end
    local cmd = (words[1] or ""):lower()
    local player = Game.GetPlayer()
    if cmd == "" then
        return
    elseif cmd == "goto" and player then
        local x, y, z, yaw = tonumber(words[2]), tonumber(words[3]), tonumber(words[4]), tonumber(words[5])
        local here = player:GetWorldPosition()
        local f = player:GetWorldForward()
        scout.back = { x = here.x, y = here.y, z = here.z, yaw = math.deg(math.atan2(-f.x, f.y)) }
        place(player, x, y, z, yaw or scout.back.yaw)
        say(string.format("Claude moved V to %.1f, %.1f, %.1f", x, y, z))
        reply(string.format("goto done: %.1f %.1f %.1f", x, y, z))
    elseif cmd == "near" then
        local p = { x = tonumber(words[2]), y = tonumber(words[3]), z = tonumber(words[4]),
                    standoff = tonumber(words[5]), name = table.concat(words, " ", 6) }
        if p.name == "" then
            p.name = string.format("%.0f, %.0f", p.x, p.y)
        end
        goNear(p)
        reply("near: going to " .. p.name)
    elseif cmd == "facts" then
        local qs = Game.GetQuestsSystem()
        local parts = {}
        for i = 2, #words do
            parts[#parts + 1] = words[i] .. "=" .. tostring(qs:GetFactStr(words[i]))
        end
        reply("facts " .. table.concat(parts, " "))
    elseif cmd == "setfact" then
        Game.GetQuestsSystem():SetFactStr(words[2], tonumber(words[3]) or 1)
        reply("setfact " .. words[2] .. "=" .. tostring(Game.GetQuestsSystem():GetFactStr(words[2])))
    elseif cmd == "where" and player then
        local pos = player:GetWorldPosition()
        local f = player:GetWorldForward()
        reply(string.format("where %.1f %.1f %.1f yaw %.0f%s", pos.x, pos.y, pos.z, math.deg(math.atan2(-f.x, f.y)),
            player:GetMountedVehicle() and " (in a vehicle)" or ""))
    elseif cmd == "capture" then
        scout.note = table.concat(words, " ", 2)
        scout.capture()
        reply("capture taken")
    else
        reply("unknown command: " .. line)
    end
end

local function pollCommands(dt)
    pollIn = pollIn - dt
    if pollIn > 0 then
        return
    end
    pollIn = 0.5
    local file = io.open(COMMANDS, "r")
    if not file then
        return
    end
    local text = file:read("*a")
    file:close()
    if not text or not text:find("%S") then
        return
    end
    local clear = io.open(COMMANDS, "w") -- emptied rather than deleted, which needs no os call
    if clear then
        clear:close()
    end
    for line in text:gmatch("[^\r\n]+") do
        local ok, problem = pcall(runCommand, line)
        if not ok then
            reply("error in '" .. line .. "': " .. tostring(problem))
        end
    end
end

function scout.update(dt)
    pcall(pollCommands, dt)
    local g = scout.going
    if not g then
        return
    end
    local player = Game.GetPlayer()
    if not player then
        scout.going = nil
        return
    end
    g.t = g.t + dt
    if g.t >= FIRST_TRY and g.t >= (g.nextTry or 0) then
        g.nextTry = g.t + 0.5
        local spot = landing(g.p)
        if spot then
            scout.going = nil
            place(player, spot.x, spot.y, spot.z + 0.2, yawTowards(spot.x, spot.y, g.p.x, g.p.y))
            local d = math.sqrt((spot.x - g.p.x) ^ 2 + (spot.y - g.p.y) ^ 2)
            say(string.format("Near %s: %.0f m away, facing it (%.1f s).", g.p.name, d, g.t))
            return
        end
    end
    if g.t < GIVE_UP then
        place(player, g.x, g.y, g.z, g.yaw)
        return
    end
    scout.going = nil
    local ground = groundBelow(g.x, g.y, g.z)
    if ground then
        place(player, ground.x, ground.y, ground.z + 0.5, g.yaw)
        say("Near " .. g.p.name .. " (no walkway found; put on the ground below, maybe a roof).")
    else
        place(player, g.x, g.y, g.z, g.yaw)
        say("Near " .. g.p.name .. ", but no ground found; left at the place's height. Use Back if it looks wrong.")
    end
end

-- Steps V straight ahead, through walls and shut doors, onto walkable ground near the spot if there is any
-- (the navmesh within 3 m and 4 m up or down), else at the same height.
local function stepAhead(metres)
    local player = Game.GetPlayer()
    if not player then
        return
    end
    if player:GetMountedVehicle() then
        say("Get out of the car first.")
        return
    end
    local pos = player:GetWorldPosition()
    local f = player:GetWorldForward()
    local yaw = math.deg(math.atan2(-f.x, f.y))
    scout.back = { x = pos.x, y = pos.y, z = pos.z, yaw = yaw }
    local tx, ty, tz = pos.x + f.x * metres, pos.y + f.y * metres, pos.z
    local ok, point = pcall(function()
        local res = Game.GetNavigationSystem():FindPointInSphereOnlyHumanNavmesh(Vector4.new(tx, ty, tz + 0.5, 1), 3,
            NavGenAgentSize.Human, false)
        if res and EnumInt(res.status) == 0 and math.abs(res.point.z - tz) < 4 then
            return res.point
        end
    end)
    if ok and point then
        place(player, point.x, point.y, point.z + 0.2, yaw)
        say(string.format("%d m ahead, on walkable ground.", metres))
    else
        place(player, tx, ty, tz + 0.2, yaw)
        say(string.format("%d m ahead, at the same height (no walkway found there). Back undoes it.", metres))
    end
end

-- Hostile NPCs, and gang members who aren't hostile yet, within the radius; never police, civilians or crowd.
-- Quest characters that can't die are skipped by the game's own Kill.
local function killEnemies(radius)
    local player = Game.GetPlayer()
    if not player then
        return
    end
    local n = 0
    for _, npc in ipairs(player:GetNPCsAroundObject(radius) or {}) do
        local ok = pcall(function()
            if npc and not npc:IsDead() and npc:IsEnemy() and not npc:IsCharacterPolice() then
                npc:Kill(player, false, false)
                n = n + 1
            end
        end)
        if not ok then
            -- not a puppet we can judge; leave it
        end
    end
    say(string.format("Killed %d within %d m.", n, radius))
end

local function nearest(x, y)
    local best, bd
    for _, p in ipairs(places) do
        if p.name then
            local d = math.sqrt((p.x - x) ^ 2 + (p.y - y) ^ 2)
            if not best or d < bd then
                best, bd = p, d
            end
        end
    end
    return best, bd
end

-- Appends where V stands, and the note, to scout-marks.txt in this mod's folder, for the record.
local function mark()
    local player = Game.GetPlayer()
    if not player then
        return
    end
    local pos = player:GetWorldPosition()
    local f = player:GetWorldForward()
    local p, d = nearest(pos.x, pos.y)
    local line = string.format("%s | near %s (%.0f m) | %.1f, %.1f, %.1f | yaw %.0f | %s",
        os.date("%Y-%m-%d %H:%M:%S"), p and p.name or "?", d or 0, pos.x, pos.y, pos.z,
        math.deg(math.atan2(-f.x, f.y)), scout.note)
    local file = io.open("scout-marks.txt", "a")
    if file then
        file:write(line .. "\n")
        file:close()
        say("Marked: " .. line)
        scout.note = ""
    else
        say("Couldn't write scout-marks.txt")
    end
end

-- Each place gets a short id from its name (lone_garage_2 for the second of a name), to quote in chat.
local ids = {}
for _, p in ipairs(places) do
    if not p.group then
        p.name, p.district, p.feel, p.x, p.y, p.z, p.what = p[1], p[2], p[3], p[4], p[5], p[6], p[7]
        local id = p.name:lower():gsub("'s", "s"):gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
        ids[id] = (ids[id] or 0) + 1
        p.id = ids[id] > 1 and (id .. "_" .. ids[id]) or id
    end
end

-- The job each place belongs to, by its code in the game's files; its journal state says before or after.
local GIGS = {
    ["Jake Estevez's garage"] = "sts_hey_gle_06", ["Garage no. 66"] = "sts_std_rcr_04",
    ["Hal Cantos's workshop"] = "sts_wat_nid_01", ["Workshop with the mechanical press"] = "sts_wbr_jpn_02",
    ["6th Street workshop at a Kang Tao site"] = "sts_std_arr_06", ["Scrapyard by the landfill"] = "sts_bls_ina_11",
    ["Big Pete's place"] = "sts_bls_ina_02", ["Wellsprings body shop"] = "sts_hey_spr_03", ["Raffen Shiv camp"] = "sq004",
}
for _, p in ipairs(places) do
    if p.name then
        p.gig = GIGS[p.name]
    end
end

-- The job's state in V's journal (Inactive, Active, Succeeded, Failed), or nil if the journal doesn't say.
-- The journal's paths for gigs aren't known, so it tries likely ones, then every quest's id.
local function gigState(code)
    local jm = Game.GetJournalManager()
    local function stateOf(entry)
        local s = tostring(jm:GetEntryState(entry))
        return s:match("(%a+)%s*%(") or s:match(":%s*(%a+)") or s
    end
    for _, path in ipairs({ "quests/street_stories/" .. code, "quests/street_story/" .. code, "quests/minor_quest/" .. code,
                            "quests/side_quest/" .. code, "quests/" .. code }) do
        local ok, entry = pcall(function() return jm:GetEntryByString(path, "gameJournalQuest") end)
        if ok and entry then
            return stateOf(entry), path
        end
    end
    local ok, found = pcall(function()
        local filter = JournalRequestStateFilter.new()
        filter.inactive, filter.active, filter.succeeded, filter.failed = true, true, true, true
        local context = JournalRequestContext.new()
        context.stateFilter = filter
        local entries = jm:GetQuests(context)
        for _, entry in ipairs(entries or {}) do
            if entry:GetId() == code then
                return { stateOf(entry), "id " .. code }
            end
        end
    end)
    if ok and found then
        return found[1], found[2]
    end
    return nil, "not found in the journal"
end

-- A tiny JSON writer for the captures (CET's Lua has none of its own here).
local function toJson(v, indent)
    indent = indent or ""
    local t = type(v)
    if t == "table" then
        local keys = {}
        for k in pairs(v) do
            keys[#keys + 1] = k
        end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        local parts = {}
        for _, k in ipairs(keys) do
            parts[#parts + 1] = indent .. "  " .. toJson(tostring(k)) .. ": " .. toJson(v[k], indent .. "  ")
        end
        return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
    elseif t == "string" then
        return '"' .. v:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"'
    elseif t == "number" then
        return (v ~= v or v == math.huge or v == -math.huge) and "null" or string.format("%.3f", v):gsub("%.?0+$", "")
    elseif t == "boolean" then
        return tostring(v)
    end
    return "null"
end

local function round1(n)
    return math.floor(n * 10 + 0.5) / 10
end

local function vec(v)
    return v and { x = round1(v.x), y = round1(v.y), z = round1(v.z) } or nil
end

-- The capture key (Page Down by default): what V sees, for Claude. Writes capture-<time>.json here and asks
-- tools/capture-watcher.ps1, running beside the game, for a screenshot by writing capture-request.txt.
function scout.capture()
    local player = Game.GetPlayer()
    if not player then
        return
    end
    local stamp = os.date("%Y%m%d-%H%M%S")
    local pos = player:GetWorldPosition()
    local f = player:GetWorldForward()
    local data = {
        stamp = stamp,
        time = os.date("%Y-%m-%d %H:%M:%S"),
        note = scout.note,
        player = { x = round1(pos.x), y = round1(pos.y), z = round1(pos.z), yaw = round1(math.deg(math.atan2(-f.x, f.y))) },
    }
    pcall(function() data.in_vehicle = player:GetMountedVehicle() ~= nil end)
    pcall(function() data.camera_forward = vec(Game.GetCameraSystem():GetActiveCameraForward()) end)
    -- The first surface along the camera's view, up to 80 m (the targeting system's look-at point ran 400 m
    -- through walls when no object was aimed at, first captures 2026-11-06).
    pcall(function()
        local from = Vector4.new(pos.x, pos.y, pos.z + 1.6, 1)
        pcall(function()
            local ok, t = Game.GetCameraSystem():GetActiveCameraWorldTransform()
            if ok and t and t.position then
                from = Vector4.new(t.position.x, t.position.y, t.position.z, 1)
            end
        end)
        local fwd = Game.GetCameraSystem():GetActiveCameraForward()
        local to = Vector4.new(from.x + fwd.x * 80, from.y + fwd.y * 80, from.z + fwd.z * 80, 1)
        local hit, result = Game.GetSpatialQueriesSystem():SyncRaycastByCollisionGroup(from, to, CName.new("Static"), false, false)
        if hit and result and result.position then
            local at = result.position
            data.look_at = vec(at)
            data.look_at.distance = round1(math.sqrt((at.x - from.x) ^ 2 + (at.y - from.y) ^ 2 + (at.z - from.z) ^ 2))
            pcall(function() data.look_at.material = NameToString(result.material) end)
        end
    end)
    pcall(function()
        local at = Game.GetTargetingSystem():GetLookAtPosition(player, false, false)
        if at and (at.x ~= 0 or at.y ~= 0) then
            data.aim_point = vec(at)
        end
    end)
    pcall(function()
        local o = Game.GetTargetingSystem():GetLookAtObject(player, false, false)
        if o then
            local op = o:GetWorldPosition()
            data.look_object = { position = vec(op) }
            pcall(function() data.look_object.class = NameToString(o:GetClassName()) end)
            pcall(function() data.look_object.name = o:GetDisplayName() end)
            pcall(function() data.look_object.record = TDBID.ToStringDEBUG(o:GetRecordID()) end)
            pcall(function() data.look_object.entity_id = tostring(o:GetEntityID().hash) end)
        end
    end)
    local p, d = nearest(pos.x, pos.y)
    if p then
        data.nearest = { id = p.id, name = p.name, distance = round1(d), gig = p.gig }
        if p.gig then
            local ok, state, how = pcall(gigState, p.gig)
            data.nearest.gig_state = ok and state or nil
            data.nearest.gig_state_from = ok and how or tostring(state)
        end
    end
    local file = io.open("capture-" .. stamp .. ".json", "w")
    if not file then
        say("Couldn't write the capture")
        return
    end
    file:write(toJson(data) .. "\n")
    file:close()
    local request = io.open("capture-request.txt", "w")
    if request then
        request:write(stamp)
        request:close()
    end
    say("Captured " .. stamp .. (p and (" near " .. p.name) or ""))
end

local function copyPlace(p)
    local text = string.format("[%s] %s, %s (%.1f, %.1f, %.1f)", p.id, p.name, p.district, p.x, p.y, p.z)
    ImGui.SetClipboardText(text)
    say("Copied: " .. text)
end

-- Pins don't outlive a load, so forget them when V comes into a new session.
function scout.init()
    ObserveAfter("PlayerPuppet", "OnGameAttached", function()
        for _, p in ipairs(places) do
            p.pin = nil
        end
    end)
end

-- "Jake Estevez's garage: 42 m ahead-left, 3 m above", for the place nearest V.
local SIDES = { "ahead", "ahead-left", "left", "behind-left", "behind", "behind-right", "right", "ahead-right" }
local function whereIsNearest()
    local player = Game.GetPlayer()
    if not player then
        return nil
    end
    local pos = player:GetWorldPosition()
    local p, d = nearest(pos.x, pos.y)
    if not p then
        return nil
    end
    local f = player:GetWorldForward()
    local turn = math.deg(math.atan2(-(p.x - pos.x), p.y - pos.y) - math.atan2(-f.x, f.y)) % 360
    local side = SIDES[math.floor((turn + 22.5) / 45) % 8 + 1]
    local dz = p.z - pos.z
    local height = math.abs(dz) < 2 and "same height" or string.format("%.0f m %s", math.abs(dz), dz > 0 and "above" or "below")
    return string.format("Nearest: %s, %.0f m %s, %s", p.name, d, side, height), p
end

-- The nearest place's job state, looked up at most every 5 s.
local function jobLine(p)
    if not (p and p.gig) then
        return nil
    end
    if not p.stateAt or os.clock() - p.stateAt > 5 then
        local ok, state, how = pcall(gigState, p.gig)
        p.state = ok and (state or ("unknown, " .. tostring(how))) or ("unknown: " .. tostring(state))
        p.stateAt = os.clock()
    end
    return "Its job (" .. p.gig .. "): " .. p.state
end

function scout.draw()
    if not scout.placed then
        local w, h = 1920, 1080
        local ok, dw, dh = pcall(GetDisplayResolution)
        if ok and dw and dh and dw > 0 and dh > 0 then
            w, h = dw, dh
        end
        local ww, wh = 480, math.min(700, h - 80)
        -- left of the dev panel (560 wide, centred), or centred if that doesn't fit
        local x = w / 2 - 280 - 12 - ww
        if x < w * 0.05 then
            x = (w - ww) / 2
        end
        ImGui.SetNextWindowPos(x, (h - wh) / 2, ImGuiCond.Always)
        ImGui.SetNextWindowSize(ww, wh, ImGuiCond.Always)
        scout.placed = true
    end
    ImGui.SetNextWindowSizeConstraints(320, 200, 900, 1300)
    if not ImGui.Begin("Shop scouting") then
        ImGui.End()
        return
    end
    if ImGui.Button("Back to where I was") and scout.back then
        local b = scout.back
        place(Game.GetPlayer(), b.x, b.y, b.z, b.yaw)
        say("Back.")
    end
    ImGui.SameLine()
    if ImGui.Button("5 m ahead") then
        stepAhead(5)
    end
    ImGui.SameLine()
    if ImGui.Button("10 m ahead") then
        stepAhead(10)
    end
    if ImGui.Button("Kill enemies within 100 m") then
        killEnemies(100)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip("Hostiles and gang members, not police or civilians.\nKilling gang members who weren't hostile yet may draw the police.")
    end
    scout.note = ImGui.InputText("##note", scout.note, 300)
    ImGui.SameLine()
    if ImGui.Button("Mark this spot") then
        mark()
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip("Writes where V stands, the nearest place and the note to scout-marks.txt.")
    end
    if ImGui.Button("Pin all") then
        for _, p in ipairs(places) do
            if p.name then
                pcall(setPin, p, true)
            end
        end
    end
    ImGui.SameLine()
    if ImGui.Button("Clear pins") then
        for _, p in ipairs(places) do
            if p.name then
                setPin(p, false)
            end
        end
    end
    local where, near = whereIsNearest()
    if where then
        ImGui.Text(where)
        local job = jobLine(near)
        if job then
            ImGui.Text(job)
        end
    end
    ImGui.TextDisabled("Capture key: Page Down (CET Bindings) - screenshot + what you look at, for Claude")
    if scout.status ~= "" then
        ImGui.TextWrapped(scout.status)
    end
    ImGui.Separator()
    ImGui.BeginChild("places")
    for i, p in ipairs(places) do
        if p.group then
            ImGui.Spacing()
            ImGui.Text(p.group)
        else
            if ImGui.Button("Go near##" .. i) then
                goNear(p)
            end
            ImGui.SameLine()
            local _, pressed = ImGui.Checkbox("##pin" .. i, p.pin ~= nil)
            if pressed then
                local ok, problem = pcall(setPin, p, p.pin == nil)
                if not ok then
                    say("Couldn't pin: " .. tostring(problem))
                end
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip("Pin on the map")
            end
            ImGui.SameLine()
            if ImGui.Button("Copy##" .. i) then
                copyPlace(p)
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip("Copy its id, name, district and coordinates, to paste in chat")
            end
            ImGui.SameLine()
            ImGui.Text(p.name)
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip(string.format("%s\n%s\n%.1f, %.1f, %.1f", p.district, p.what, p.x, p.y, p.z))
            end
            ImGui.SameLine()
            ImGui.TextDisabled(p.district .. " - " .. p.feel)
        end
    end
    ImGui.EndChild()
    ImGui.End()
end

return scout
