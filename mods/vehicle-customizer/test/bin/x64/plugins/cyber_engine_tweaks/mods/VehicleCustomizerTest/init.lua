-- In-game tests for the vehicle customizer (vehicle-customizer/RECORD.md).
-- On the test Hella (the stock-look file copy), part, look and add-on choices are saved in builds.txt, sent to
-- the redscript service (r6/scripts/VehicleCustomizerTest), and built into the car, which rebuilds where it
-- stands. On any other Hella or a Nazare-family bike, part buttons change the car you sit in or look at and
-- aren't kept. Every action writes to test.log in this folder at once, return values included.

local STOCK = "Vehicle.v_standard2_archer_hella_player"
local COPY_SAME = STOCK .. "_vctest"
local COPY_LOOK = STOCK .. "_vctest_b"

-- Every copy in vehiclecustomizertest.yaml. The truck, the van and the AV are models the game never lets V own.
local FILE_COPIES = {
    COPY_SAME,
    COPY_LOOK,
    "Vehicle.v_utility4_kaukaz_bratsk_vctest",
    "Vehicle.v_utility4_chevalier_centurion_vctest",
    "Vehicle.av_rayfield_excalibur_vctest",
}

local LIST = "Vehicle.vehicle_list.list"
local LIVE_PREFIX = "Vehicle.vc_live_"
local LIVE_FILE = "live-copies.txt"

local HELLA = "base\\vehicles\\standard\\v_standard2_archer_hella\\entities\\meshes\\v_standard2_archer_hella__ext01_"
local QUADRA = "base\\vehicles\\sport\\v_sport1_quadra_turbo\\entities\\meshes\\v_sport1_quadra_turbo__ext01_"
local PORSCHE = "base\\vehicles\\sport\\v_sport2_porsche_911turbo\\entities\\meshes\\v_sport2_porsche_911turbo__ext01_"
local NEMESIS = "base\\vehicles\\sportbike\\v_sportbike2_arch_nemesis\\entities\\meshes\\v_sportbike2_arch_nemesis__ext01_"

local HOOD_PAINTS = { "primer_red", "stickerbomb_01", "deathrace_01", "police_01", "suburban_01", "primer_black" }

local BUMPERS = {
    { name = "junk", mesh = HELLA .. "junk_bumper_f_01.mesh", paint = "color_02" },
    { name = "stock", mesh = HELLA .. "bumper_f_01.mesh", paint = "police_02" },
}

-- Part, mesh. The Quadra set is what V's Hella has as stock; the Hella never has the Porsche set.
local WHEELS = {
    {
        name = "Porsche",
        parts = {
            { "wheel_01_fl_a", PORSCHE .. "wheel_fl_01.mesh" },
            { "wheel_01_fr_a", PORSCHE .. "wheel_fl_01.mesh" },
            { "wheel_01_bl_a", PORSCHE .. "wheel_bl_01.mesh" },
            { "wheel_01_br_a", PORSCHE .. "wheel_bl_01.mesh" },
            { "tire_01_fl_a", PORSCHE .. "tire_fl_01.mesh" },
            { "tire_01_fr_a", PORSCHE .. "tire_fl_01.mesh" },
            { "tire_01_bl_a", PORSCHE .. "tire_bl_01.mesh" },
            { "tire_01_br_a", PORSCHE .. "tire_bl_01.mesh" },
            { "tire_01_fl_a_shadow", PORSCHE .. "tire_bl_01_shadow.mesh" },
            { "tire_01_fr_a_shadow", PORSCHE .. "tire_bl_01_shadow.mesh" },
            { "tire_01_bl_a_shadow", PORSCHE .. "tire_bl_01_shadow.mesh" },
            { "tire_01_br_a_shadow", PORSCHE .. "tire_bl_01_shadow.mesh" },
        },
    },
    {
        name = "Quadra (stock)",
        parts = {
            { "wheel_01_fl_a", QUADRA .. "wheel_bl_01.mesh" },
            { "wheel_01_fr_a", QUADRA .. "wheel_bl_01.mesh" },
            { "wheel_01_bl_a", QUADRA .. "wheel_bl_01.mesh" },
            { "wheel_01_br_a", QUADRA .. "wheel_bl_01.mesh" },
            { "tire_01_fl_a", QUADRA .. "tire_bl_01.mesh" },
            { "tire_01_fr_a", QUADRA .. "tire_bl_01.mesh" },
            { "tire_01_bl_a", QUADRA .. "tire_bl_01.mesh" },
            { "tire_01_br_a", QUADRA .. "tire_bl_01.mesh" },
            { "tire_01_fl_a_shadow", QUADRA .. "tire_fl_01_shadow.mesh" },
            { "tire_01_fr_a_shadow", QUADRA .. "tire_fl_01_shadow.mesh" },
            { "tire_01_bl_a_shadow", QUADRA .. "tire_bl_01_shadow.mesh" },
            { "tire_01_br_a_shadow", QUADRA .. "tire_bl_01_shadow.mesh" },
        },
    },
}

-- The Nazare, Racer and Kobold are one bike with a different fairing.
local FAIRINGS = {
    { name = "Kobold", mesh = NEMESIS .. "fairing_f_c_01.mesh", shadow = NEMESIS .. "fairing_f_c_01_shadow.mesh", paint = "pink_01" },
    { name = "Nazare", mesh = NEMESIS .. "fairing_f_a_01.mesh", shadow = NEMESIS .. "fairing_f_a_01_shadow.mesh", paint = "yellow" },
    { name = "Racer", mesh = NEMESIS .. "fairing_f_b_01.mesh", shadow = NEMESIS .. "fairing_f_b_01_shadow.mesh", paint = "troy_01" },
}

local BIKE_PAINTS = { "chrome_01", "camo_01", "neon_01", "red_01", "troy_01" }

local overlayOpen = false
local status = "Nothing done yet."
local nextBumper = 1 -- the bumper the robot arms' Try puts on next
local clock = 0 -- seconds since the mod loaded, from onUpdate

local function log(text)
    status = text
    local file = io.open("test.log", "a")
    if file then
        file:write(os.date("%H:%M:%S "), text, "\n")
        file:close()
    end
    print("[VehicleCustomizerTest] " .. text)
end

local function attempt(what, action)
    local ok, result = pcall(action)
    log(what .. " -> " .. (ok and tostring(result) or ("ERROR " .. tostring(result))))
    return ok and result
end

local function currentVehicle()
    local player = Game.GetPlayer()
    if not player then
        return nil
    end
    local ok, vehicle = pcall(function() return Game.GetMountedVehicle(player) end)
    if ok and vehicle then
        return vehicle
    end
    ok, vehicle = pcall(function() return Game.GetTargetingSystem():GetLookAtObject(player, false, false) end)
    if ok and vehicle and vehicle:IsVehicle() then
        return vehicle
    end
    return nil
end

local function recordOf(vehicle)
    local ok, value = pcall(function() return vehicle:GetRecordID().value end)
    return ok and tostring(value) or "?"
end

local function lookOf(vehicle)
    local ok, value = pcall(function() return NameToString(vehicle:GetCurrentAppearanceName()) end)
    return ok and tostring(value) or "?"
end

-- Compared by id, since a record TweakXL added may not show its name.
local function labelOf(vehicle)
    local ok, id = pcall(function() return tostring(vehicle:GetRecordID()) end)
    if not ok then
        return "?"
    end
    if id == tostring(TweakDBID.new(STOCK)) then
        return "stock Hella"
    elseif id == tostring(TweakDBID.new(COPY_SAME)) then
        return "test copy, stock look"
    elseif id == tostring(TweakDBID.new(COPY_LOOK)) then
        return "test copy, its own look"
    end
    return recordOf(vehicle)
end

local function findPart(vehicle, name)
    local parts = vehicle:GetComponents()
    for i = 1, #parts do
        if parts[i] and NameToString(parts[i].name) == name then
            return parts[i]
        end
    end
    return nil
end

-- The saved build: what was changed on the stock-look test copy, kept in builds.txt and put back each time
-- that copy appears. Only that copy keeps a build, so the stock Hella and every other car stay as they are.
local BUILD_FILE = "builds.txt"
local BUILD_RECORD = COPY_SAME
local STOCK_LOOK = "archer_hella__basic_player_01"
local BASE_LOOKS = {
    "archer_hella__basic_suburban_1_2",
    "archer_hella__basic_poor_2_2",
    "archer_hella__basic_6th_street_01",
    STOCK_LOOK,
}

local function emptyBuild()
    return { look = nil, parts = {}, order = {}, kit = false, kitOffset = { 0, 0, 0 } }
end

local build = emptyBuild()
local pendingApply = {}

-- Who puts the saved build on the copy. True: the redscript service, as the car is built; a change is saved,
-- sent to the service and the car rebuilt in place, and the window only reports what it finds. False: this
-- window, on the car after it appears, with the once-a-second check that puts back emptied parts.
local buildByService = true
local pendingRebuild = nil

local function isBuildCopy(vehicle)
    local ok, id = pcall(function() return tostring(vehicle:GetRecordID()) end)
    return ok and id == tostring(TweakDBID.new(BUILD_RECORD))
end

local function saveBuild()
    local file = io.open(BUILD_FILE, "w")
    if not file then
        return
    end
    if build.look then
        file:write("look|", build.look, "\n")
    end
    if build.kit then
        file:write(string.format("kit|%.2f,%.2f,%.2f\n", build.kitOffset[1], build.kitOffset[2], build.kitOffset[3]))
    end
    for _, name in ipairs(build.order) do
        local change = build.parts[name]
        file:write("part|", name, "|", change.mesh or "", "|", change.paint or "", "\n")
    end
    file:close()
end

local function loadBuild()
    build = emptyBuild()
    local file = io.open(BUILD_FILE, "r")
    if not file then
        return
    end
    for line in file:lines() do
        local kind, a, b, c = line:match("^(%a+)|([^|]*)|?([^|]*)|?([^|]*)$")
        if kind == "look" then
            build.look = a
        elseif kind == "kit" then
            build.kit = true
            local i = 1
            for number in a:gmatch("[-%d%.]+") do
                build.kitOffset[i] = tonumber(number) or 0
                i = i + 1
            end
        elseif kind == "part" then
            build.parts[a] = { mesh = b ~= "" and b or nil, paint = c ~= "" and c or nil }
            table.insert(build.order, a)
        end
    end
    file:close()
end

local buildCopySeen -- set below; remembers which entity is the build copy

local function remember(vehicle, partName, mesh, paint)
    if not isBuildCopy(vehicle) then
        return
    end
    buildCopySeen(vehicle)
    local change = build.parts[partName]
    if not change then
        change = {}
        build.parts[partName] = change
        table.insert(build.order, partName)
    end
    if mesh then
        change.mesh = mesh
        change.paint = paint
    else
        change.paint = paint
    end
    saveBuild()
end

-- A look carries a list of what its visual controller loads for each part, by part name: mesh and paint.
-- When a car comes back into view the game loads parts by that list, so a part changed without updating
-- its entry comes back missing (the third run). This updates the part's entry to what it now has.
local function registerDependency(vehicle, part, partName, paint)
    local ok, result = pcall(function()
        local controller = vehicle:FindComponentByType(CName.new("entVisualControllerComponent"))
        if not controller then
            return "no visual controller"
        end
        local deps = controller.appearanceDependency
        local appearance = CName.new(paint or "default")
        local changed = 0
        for i = 1, #deps do
            if NameToString(deps[i].componentName) == partName then
                deps[i].mesh = part.mesh
                deps[i].appearanceName = appearance
                changed = changed + 1
            end
        end
        if changed == 0 then
            local dep = entVisualControllerDependency.new()
            dep.componentName = CName.new(partName)
            dep.mesh = part.mesh
            dep.appearanceName = appearance
            table.insert(deps, dep)
        end
        controller.appearanceDependency = deps
        controller:LoadAppearanceDependencies(false)
        return (changed > 0 and "updated" or "added") .. " in a list of " .. #deps
    end)
    log("  " .. partName .. " in the visual controller's list -> " .. (ok and result or ("ERROR " .. tostring(result))))
end

-- With the service building the copy, a change to it is only saved; the car is rebuilt in place next frame,
-- once for however many changes a button makes.
local function saveForService(vehicle, partName, mesh, paint)
    remember(vehicle, partName, mesh, paint)
    log(string.format("%s saved to the build (mesh %s, paint %s); the service puts it on as the car is rebuilt",
        partName, mesh and mesh:match("[^\\]+$") or "kept", paint or (mesh and "default" or "kept")))
    pendingRebuild = vehicle:GetEntityID()
    return true
end

-- Both return whether the game took the change; `replaying` puts a saved change back without saving it again.
local function setPaint(vehicle, partName, paint, replaying)
    local part = findPart(vehicle, partName)
    if not part then
        log(partName .. " is not on this vehicle")
        return false
    end
    if buildByService and not replaying and isBuildCopy(vehicle) then
        return saveForService(vehicle, partName, nil, paint)
    end
    local done = attempt(partName .. " class " .. NameToString(part:GetClassName()) .. " paint " .. paint, function()
        return part:ChangeAppearance(CName.new(paint), false)
    end)
    if done then
        registerDependency(vehicle, part, partName, paint)
    end
    if done and not replaying then
        remember(vehicle, partName, nil, paint)
    end
    return done
end

local function setMesh(vehicle, partName, mesh, paint, replaying)
    local part = findPart(vehicle, partName)
    if not part then
        log(partName .. " is not on this vehicle")
        return false
    end
    if buildByService and not replaying and isBuildCopy(vehicle) then
        return saveForService(vehicle, partName, mesh, paint)
    end
    local done = attempt(partName .. " class " .. NameToString(part:GetClassName()) .. " mesh " .. mesh, function()
        part.meshAppearance = CName.new(paint or "default")
        return part:ChangeResource(ResRef.FromName(mesh), false)
    end)
    if done then
        registerDependency(vehicle, part, partName, paint)
    end
    if done and not replaying then
        remember(vehicle, partName, mesh, paint)
    end
    return done
end

-- Adding parts a look doesn't have: the Archer Quartz Nomad's front kit, mounted exactly as on that car
-- (archer_quartz_nomad.app, look aldecados_01): each part on the Base mount point with its offset and turn,
-- and a shadow hanging off the part. The kit is saved with the build and added again whenever the copy
-- appears; the offset moves the whole kit, to fit it to a car of another shape.
local NOMAD = "base\\vehicles\\common\\parts\\v_common__nomad\\entities\\meshes\\v_common_nomad_part__ext01_"
local KIT = {
    { name = "vc_nomad_sensor", mesh = NOMAD .. "sensor_medium_02.mesh", shadow = NOMAD .. "sensor_medium_02_shadow.mesh",
      paint = "dusty_01", pos = { -0.6987, 1.8611, -0.0768 }, rot = { 0, 0, 0, 1 } },
    { name = "vc_nomad_detector_1", mesh = NOMAD .. "detector_medium_01.mesh", shadow = NOMAD .. "detector_medium_01_shadow.mesh",
      paint = "dusty_light_01", pos = { -0.5849, 1.8777, -0.3633 }, rot = { -0.3234716, 0.0179898, 0.2841919, 0.9023732 } },
    { name = "vc_nomad_detector_2", mesh = NOMAD .. "detector_medium_01.mesh", shadow = NOMAD .. "detector_medium_01_shadow.mesh",
      paint = "dusty_light_01", pos = { -0.5490, 1.7580, -0.4821 }, rot = { -0.5109810, -0.0071725, 0.2204561, 0.8308105 } },
    { name = "vc_nomad_detector_3", mesh = NOMAD .. "detector_medium_01.mesh", shadow = NOMAD .. "detector_medium_01_shadow.mesh",
      paint = "dusty_light_01", pos = { 0.5519, 1.7663, -0.4801 }, rot = { -0.5034177, 0.0902069, -0.2860584, 0.8103110 } },
    { name = "vc_nomad_detector_4", mesh = NOMAD .. "detector_medium_01.mesh", shadow = NOMAD .. "detector_medium_01_shadow.mesh",
      paint = "dusty_light_01", pos = { 0.6013, 1.8779, -0.3702 }, rot = { -0.2870721, 0.0251881, -0.2870211, 0.9135503 } },
}

local function kitPosition(entry)
    local o = build.kitOffset
    return Vector4.new(entry.pos[1] + o[1], entry.pos[2] + o[2], entry.pos[3] + o[3], 1)
end

local function loadMesh(vehicle, part, name, mesh, paint)
    attempt("  " .. name .. " mesh " .. mesh, function()
        part.meshAppearance = CName.new(paint or "default")
        return part:ChangeResource(ResRef.FromName(mesh), false)
    end)
    registerDependency(vehicle, part, name, paint)
end

-- Makes a mesh part, attaches it, adds it to the car and loads its mesh; logs each step.
local function addPart(vehicle, name, mesh, paint, bindName, slotName, position, rotation)
    local part = findPart(vehicle, name)
    if part then
        loadMesh(vehicle, part, name, mesh, paint)
        return part
    end
    local ok, problem = pcall(function()
        part = NewObject("entMeshComponent")
        part.name = CName.new(name)
        part.meshAppearance = CName.new(paint or "default")
        local binding = NewObject("entHardTransformBinding")
        binding.bindName = CName.new(bindName)
        if slotName then
            binding.slotName = CName.new(slotName)
        end
        part.parentTransform = binding
        if position then
            local transform = WorldTransform.new()
            transform:SetPosition(position)
            transform:SetOrientation(rotation)
            part.localTransform = transform
        end
        vehicle:AddComponent(part)
    end)
    if not ok then
        log("  making " .. name .. " failed: " .. tostring(problem))
        return nil
    end
    log("  " .. name .. " added to the car; found on it afterwards: " .. tostring(findPart(vehicle, name) ~= nil))
    loadMesh(vehicle, findPart(vehicle, name) or part, name, mesh, paint)
    return part
end

local function addKit(vehicle)
    for _, entry in ipairs(KIT) do
        local rotation = Quaternion.new(entry.rot[1], entry.rot[2], entry.rot[3], entry.rot[4])
        if addPart(vehicle, entry.name, entry.mesh, entry.paint, "vehicle_slots", "Base", kitPosition(entry), rotation) then
            addPart(vehicle, entry.name .. "_shadow", entry.shadow, nil, entry.name, nil, nil, nil)
        end
    end
end

-- Parts added to a car already in the world never joined it (sixth run), so the kit now goes in as the car
-- is built, from redscript (r6/scripts/VehicleCustomizerTest): this tells that service what to add.
local KIT_SERVICE = "VehicleCustomizerTest.KitService"

local function kitService()
    local container = Game.GetScriptableServiceContainer()
    return container and container:GetService(KIT_SERVICE)
end

local function tellKitService()
    local ok, problem = pcall(function()
        local service = kitService()
        if not service then
            error("service unavailable")
        end
        service:SetKit(build.kit, build.kitOffset[2], build.kitOffset[3])
        -- The saved parts go too, and whether the service puts them on as the car is built.
        service:SetSwapAtBuild(buildByService)
        service:ClearParts()
        for _, name in ipairs(build.order) do
            local change = build.parts[name]
            service:SetPart(CName.new(name), change.mesh or "", CName.new(change.paint or "None"))
        end
    end)
    log(string.format("kit service told: on %s, %.1f m ahead, %.1f m up; %d saved parts, put on %s -> %s",
        tostring(build.kit), build.kitOffset[2], build.kitOffset[3], #build.order,
        buildByService and "by the service as the car is built" or "by the window after it appears",
        ok and "done" or ("ERROR " .. tostring(problem))))
end

-- Logs each time the game asked to put the copy back on its record's look and the service's wrap refused
-- (getting in, or CrystalCoat Continuity as the car appears). Checked once a second.
local lookKeepsSeen = 0

local function logLookKeeps()
    local ok, count, note = pcall(function()
        local service = kitService()
        return service:GetLookKeeps(), service:GetLookKeepNote()
    end)
    if ok and count and count ~= lookKeepsSeen then
        lookKeepsSeen = count
        log("the game asked to reset the copy's look (" .. count .. " so far); " .. tostring(note))
    end
end

-- What the service last did with the saved parts, and how they stand on the car now.
local function serviceSwapNotes(vehicle)
    local ok, notes = pcall(function()
        local service = kitService()
        return { "service build: " .. service:GetSwapNote(), "parts now: " .. service:DescribeParts(vehicle) }
    end)
    return ok and notes or { "ERROR " .. tostring(notes) }
end

local function kitServiceNote()
    local ok, note = pcall(function()
        local service = kitService()
        if not service then
            return "service unavailable"
        end
        return service:GetNote() .. "; builds seen " .. tostring(service:GetBuilds())
    end)
    return ok and note or ("ERROR " .. tostring(note))
end

-- What the service saw of reassembles of the copy, and of builds of any car from the Hella's look file.
local function serviceWatchNotes()
    local ok, notes = pcall(function()
        local service = kitService()
        if not service then
            return { "service unavailable" }
        end
        return { "reassembles: " .. service:GetReassembleNote(), "builds from the Hella's look file: " .. service:GetHellaBuildNote() }
    end)
    return ok and notes or { "ERROR " .. tostring(notes) }
end

-- The same kit, added to every look of the Hella's look file by the ArchiveXL patch (archive/pc/mod).
local AXL_PARTS = { "vc_axl_sensor", "vc_axl_detector_1", "vc_axl_detector_2", "vc_axl_detector_3", "vc_axl_detector_4" }

local function logKitParts(vehicle)
    local codeware, archive = {}, {}
    for _, entry in ipairs(KIT) do
        table.insert(codeware, findPart(vehicle, entry.name) and "on" or "off")
    end
    for _, name in ipairs(AXL_PARTS) do
        table.insert(archive, findPart(vehicle, name) and "on" or "off")
    end
    log("  kit parts from the service (vc_nomad_*): " .. table.concat(codeware, " ")
        .. "; from the ArchiveXL patch (vc_axl_*): " .. table.concat(archive, " "))
    for _, line in ipairs(serviceWatchNotes()) do
        log("  " .. line)
    end
end

-- Sends the build copy back to the garage and calls it again 2 s later, so the game builds it afresh and the
-- service adds the kit. Run from outside the car.
local pendingCallBack = nil

-- A respawn on the spot was tried and dropped: the game drives a called car on to the player (three-route run).
local function rebuildCopy()
    local player = Game.GetPlayer()
    local okMounted, mounted = pcall(function() return Game.GetMountedVehicle(player) end)
    if okMounted and mounted then
        log("rebuild skipped: get out of the car first")
        return
    end
    local ok, problem = pcall(function()
        local service = kitService()
        if not service then
            error("service unavailable")
        end
        service:SendAway()
    end)
    log("build copy sent back to the garage to be rebuilt -> " .. (ok and "done; calling it again in 2 s" or ("ERROR " .. tostring(problem))))
    if ok then
        pendingCallBack = clock + 2
    end
end

local function callBackCopy()
    pendingCallBack = nil
    attempt("build copy called again", function()
        return kitService():CallBack()
    end)
end

local function kitPartsOn(vehicle)
    local count = 0
    for _, entry in ipairs(KIT) do
        if findPart(vehicle, entry.name) then
            count = count + 1
        end
    end
    return count
end

local function moveKit(vehicle, ahead, up)
    build.kitOffset[2] = build.kitOffset[2] + ahead
    build.kitOffset[3] = build.kitOffset[3] + up
    saveBuild()
    tellKitService()
    for _, entry in ipairs(KIT) do
        local part = findPart(vehicle, entry.name)
        if part then
            pcall(function() part:SetLocalPosition(kitPosition(entry)) end)
        end
    end
    log(string.format("kit moved: %.2f m ahead, %.2f m up in all", build.kitOffset[2], build.kitOffset[3]))
end

-- The kit comes off by rebuilding the car without it (the button does that next), not by hiding its parts.
local function takeKitOff()
    build.kit = false
    saveBuild()
    tellKitService()
    log("kit taken off and forgotten")
end

local buildCopyId = nil
local nextHealCheck = 0

local function meshLoaded(part)
    local ok, mesh = pcall(function() return part.meshResource end)
    return ok and mesh ~= nil
end

-- With the service building the copy, the check only reports: it logs whenever the set of saved or kit parts
-- found with no mesh loaded changes, and fixes nothing, to show whether parts put on at the build stay.
local lastEmptyReport = ""

local function reportEmptyParts(vehicle)
    local empty = {}
    for _, name in ipairs(build.order) do
        local part = findPart(vehicle, name)
        if part and not meshLoaded(part) then
            table.insert(empty, name)
        end
    end
    if build.kit then
        for _, entry in ipairs(KIT) do
            local part = findPart(vehicle, entry.name)
            if part and not meshLoaded(part) then
                table.insert(empty, entry.name)
            end
        end
    end
    local report = table.concat(empty, ", ")
    if report ~= lastEmptyReport then
        log(report == "" and "check: every saved and kit part has its mesh loaded again"
            or ("check: found with no mesh loaded, left as is: " .. report))
        lastEmptyReport = report
    end
end

-- Puts back any saved part found with no mesh loaded while the build copy is near, and says so in the log.
-- If the visual controller's list is right, this never has anything to do.
local function healBuild()
    if not buildCopyId or (#build.order == 0 and not build.kit) then
        return
    end
    local vehicle = Game.FindEntityByID(buildCopyId)
    local player = Game.GetPlayer()
    if not vehicle or not player then
        return
    end
    if Vector4.Distance(player:GetWorldPosition(), vehicle:GetWorldPosition()) > 60 then
        return
    end
    if buildByService then
        reportEmptyParts(vehicle)
        return
    end
    local healed = {}
    for _, name in ipairs(build.order) do
        local part = findPart(vehicle, name)
        if part and not meshLoaded(part) then
            local change = build.parts[name]
            if change.mesh then
                setMesh(vehicle, name, change.mesh, change.paint, true)
            else
                setPaint(vehicle, name, change.paint, true)
            end
            table.insert(healed, name)
        end
    end
    -- Only a kit part that is on the car but empty gets its mesh back. A part that isn't on the car at all
    -- isn't added again from here: in the sixth run, adding parts to a car already in the world never took,
    -- and adding them every second grew the visual controller's list without end.
    if build.kit then
        for _, entry in ipairs(KIT) do
            local part = findPart(vehicle, entry.name)
            if part and not meshLoaded(part) then
                table.insert(healed, entry.name)
                loadMesh(vehicle, part, entry.name, entry.mesh, entry.paint)
            end
        end
    end
    if #healed > 0 then
        log("found with no mesh loaded and put back: " .. table.concat(healed, ", "))
    end
end

local function checkBuild(vehicle)
    for _, name in ipairs(build.order) do
        local part = findPart(vehicle, name)
        if not part then
            log("check: " .. name .. " is not on this vehicle")
        else
            local ok, paint = pcall(function() return NameToString(part.meshAppearance) end)
            log(string.format("check: %s mesh loaded %s, paint %s", name, tostring(meshLoaded(part)), ok and paint or "?"))
        end
    end
end

-- Puts every saved change back; returns how many didn't take.
local function applyBuild(vehicle)
    local missing = 0
    for _, name in ipairs(build.order) do
        local change = build.parts[name]
        local done
        if change.mesh then
            done = setMesh(vehicle, name, change.mesh, change.paint, true)
        else
            done = setPaint(vehicle, name, change.paint, true)
        end
        if not done then
            missing = missing + 1
        end
    end
    return missing
end

-- The first run's call (a string name and a CName) failed in CET with "expected userdata, received nil",
-- so this tries the ways other mods write flats, one after another, and logs each.
local function setLookFlat(look)
    local flat = BUILD_RECORD .. ".appearanceName"
    local ok, current = pcall(function() return TweakDB:GetFlat(flat) end)
    log("look flat " .. flat .. " holds " .. (ok and tostring(current) or ("ERROR " .. tostring(current))))
    local tries = {
        { "a flat id and a CName", function() return TweakDB:SetFlat(TweakDBID.new(flat), CName.new(look)) end },
        { "a record id with the field and a CName", function()
            return TweakDB:SetFlat(TweakDBID.new(TweakDBID.new(BUILD_RECORD), ".appearanceName"), CName.new(look))
        end },
        { "a name and a string", function() return TweakDB:SetFlat(flat, look) end },
        { "a name and a CName", function() return TweakDB:SetFlat(flat, CName.new(look)) end },
    }
    for _, try in ipairs(tries) do
        local done, result = pcall(try[2])
        log("  look set with " .. try[1] .. " -> " .. (done and tostring(result) or ("ERROR " .. tostring(result))))
        if done and result then
            local _, now = pcall(function() return TweakDB:GetFlat(flat) end)
            log("  look flat now holds " .. tostring(now))
            return true
        end
    end
    return false
end

local function setBaseLook(look)
    log("base look of the build copy, from its next call: " .. look)
    if setLookFlat(look) then
        build.look = look ~= STOCK_LOOK and look or nil
        saveBuild()
    else
        log("  the look wasn't set, so it isn't saved")
    end
end

-- The other way: change the look of the car in front of you, as the game does when it swaps in a wrecked
-- look, then put the saved parts back, since a new look builds its parts afresh.
local function changeLookNow(vehicle, look)
    -- The builder of a look change may not say which car it builds, so the service is told what to expect.
    attempt("kit service told to expect look " .. look, function()
        kitService():ExpectLook(CName.new(look))
        return true
    end)
    attempt("look of this car changed now to " .. look, function()
        vehicle:PrefetchAppearanceChange(CName.new(look))
        vehicle:ScheduleAppearanceChange(CName.new(look))
        return true
    end)
    if buildByService then
        table.insert(pendingApply, { id = vehicle:GetEntityID(), at = clock + 1, since = clock, tries = 0 })
        log("checking the rebuilt car in 1 s")
    elseif #build.order > 0 then
        table.insert(pendingApply, { id = vehicle:GetEntityID(), at = clock + 1, since = clock, tries = 0 })
        log("putting the saved build back in 1 s, on the new look")
    end
end

-- Rebuilding in place: the game ignores a change to the look a car already has, so the car switches between
-- its look's twins, <look>__vc_a and <look>__vc_b, which the test's ArchiveXL patch adds to the Hella's
-- entity file. Both point at the same look, so nothing changes but the parts the service adds.
local function twinOf(look)
    local base, side = look:match("^(.*)__vc_([ab])$")
    if base then
        return base .. (side == "a" and "__vc_b" or "__vc_a")
    end
    return look .. "__vc_a"
end

local function rebuildInPlace(vehicle)
    local look = lookOf(vehicle)
    log("rebuilding the copy in place: " .. look .. " -> its twin")
    changeLookNow(vehicle, twinOf(look))
end

buildCopySeen = function(vehicle)
    buildCopyId = vehicle:GetEntityID()
end

local function onVehicleAttached(vehicle)
    if isBuildCopy(vehicle) then
        buildCopySeen(vehicle)
    end
    if isBuildCopy(vehicle) and (#build.order > 0 or build.look or build.kit) then
        table.insert(pendingApply, { id = vehicle:GetEntityID(), at = clock, since = clock, tries = 0 })
    end
end

local function applyPending()
    for i = #pendingApply, 1, -1 do
        local job = pendingApply[i]
        if clock >= job.at then
            table.remove(pendingApply, i)
            local vehicle = Game.FindEntityByID(job.id)
            if vehicle and buildByService then
                log(string.format("the build copy appeared %.2f s ago in look %s; the service builds its %d saved parts",
                    clock - job.since, lookOf(vehicle), #build.order))
                log("  kit service: " .. kitServiceNote())
                logKitParts(vehicle)
                for _, line in ipairs(serviceSwapNotes(vehicle)) do
                    log("  " .. line)
                end
            elseif vehicle then
                log(string.format("the build copy appeared %.2f s ago in look %s; putting back %d changes",
                    clock - job.since, lookOf(vehicle), #build.order))
                log("  kit service: " .. kitServiceNote())
                logKitParts(vehicle)
                local missing = applyBuild(vehicle)
                if missing > 0 and job.tries < 3 then
                    table.insert(pendingApply, { id = job.id, at = clock + 1, since = job.since, tries = job.tries + 1 })
                    log(missing .. " changes didn't take; trying again in 1 s")
                end
            end
        end
    end
end

loadBuild()

local function describe(vehicle)
    log("vehicle " .. labelOf(vehicle) .. ", record " .. recordOf(vehicle) .. ", look " .. lookOf(vehicle))
    attempt("dynamic entity id", function()
        return EntityID.IsDynamic(vehicle:GetEntityID())
    end)
    local parts = vehicle:GetComponents()
    for i = 1, #parts do
        local part = parts[i]
        local ok, paint = pcall(function() return NameToString(part.meshAppearance) end)
        if ok and paint then
            log("  " .. NameToString(part.name) .. "  " .. NameToString(part:GetClassName()) .. "  paint " .. paint)
        end
    end
end

-- Live copies: records made while the game runs. They last until it closes, so live-copies.txt
-- holds them and onTweak makes them again before a save that owns them loads.

local function readLive()
    local list = {}
    local file = io.open(LIVE_FILE, "r")
    if file then
        for line in file:lines() do
            local name, hash, length = line:match("^(%S+) (%d+) (%d+)$")
            if name then
                table.insert(list, { name = name, hash = tonumber(hash), length = tonumber(length) })
            end
        end
        file:close()
    end
    return list
end

local function writeLive(list)
    local file = io.open(LIVE_FILE, "w")
    if file then
        for _, copy in ipairs(list) do
            file:write(string.format("%s %d %d\n", copy.name, copy.hash, copy.length))
        end
        file:close()
    end
end

local function makeRecord(name, base)
    local cloned = TweakDB:CloneRecord(name, base)
    local list = TweakDB:GetFlat(LIST)
    table.insert(list, TweakDBID.new(name))
    local listed = TweakDB:SetFlat(LIST, list)
    return "cloned " .. tostring(cloned) .. ", listed " .. tostring(listed)
end

local function unlock(name)
    attempt(name .. " unlock", function()
        return Game.GetVehicleSystem():EnablePlayerVehicle(name, true, false)
    end)
    attempt(name .. " counts as unlocked", function()
        return Game.GetVehicleSystem():IsVehiclePlayerUnlocked(TweakDBID.new(name))
    end)
end

local function recordExists(name)
    local ok, record = pcall(function() return TweakDB:GetRecord(name) end)
    return ok and record ~= nil
end

local function copyNow(vehicle)
    local list = readLive()
    local number = 0
    for _, copy in ipairs(list) do
        number = math.max(number, tonumber(copy.name:match("(%d+)$")) or 0)
    end
    -- A removed copy's record stays until the game closes, so skip any name the session still has.
    repeat
        number = number + 1
    until not recordExists(LIVE_PREFIX .. number)
    local name = LIVE_PREFIX .. number
    local base = vehicle:GetRecordID()
    log("copying " .. labelOf(vehicle) .. " as " .. name)
    local ok, result = pcall(makeRecord, name, base)
    log(name .. " -> " .. tostring(result))
    if ok and tostring(result):find("cloned true", 1, true) then
        table.insert(list, { name = name, hash = base.hash, length = base.length })
        writeLive(list)
        unlock(name)
    end
end

-- The window, top to bottom: the last thing done; the car you're at; its parts, look and add-on, each a row
-- of choices; the garage copies; and, folded away, the older experiments. On the test Hella a choice is
-- saved and built into the car, which rebuilds where it stands; on any other Hella or a Nazare-family bike
-- it goes straight onto the car and isn't kept.

-- One row: a label, then a button per choice; the current one is marked. Returns the choice pressed, or nil.
local function choiceRow(label, choices, current, id)
    ImGui.Text(label)
    local pressed = nil
    for i, choice in ipairs(choices) do
        ImGui.SameLine()
        local text = (choice == current and "[" .. choice .. "]" or choice) .. "##" .. id .. i
        if ImGui.Button(text) then
            pressed = i
        end
    end
    return pressed
end

-- What the build holds now, for marking the current choice.
local function builtBumper()
    local change = build.parts["bumper_f_01"]
    for _, bumper in ipairs(BUMPERS) do
        if change and change.mesh == bumper.mesh then
            return bumper.name
        end
    end
    return "stock"
end

local function builtWheels()
    local change = build.parts["wheel_01_fl_a"]
    if change and change.mesh and change.mesh:find("porsche", 1, true) then
        return "Porsche"
    end
    return "Quadra (stock)"
end

local function shortLook(look)
    return (look:gsub("^archer_hella__basic_", ""))
end

local function names(list, field)
    local out = {}
    for _, item in ipairs(list) do
        table.insert(out, field and item[field] or item)
    end
    return out
end

local function hellaParts(vehicle, saved)
    local hood = saved and build.parts["hood_a"] and build.parts["hood_a"].paint or nil
    local i = choiceRow("Front bumper:", names(BUMPERS, "name"), saved and builtBumper() or nil, "bumper")
    if i then
        setMesh(vehicle, "bumper_f_01", BUMPERS[i].mesh, BUMPERS[i].paint)
    end
    i = choiceRow("Hood paint:  ", HOOD_PAINTS, hood, "hood")
    if i then
        setPaint(vehicle, "hood_a", HOOD_PAINTS[i])
    end
    i = choiceRow("Wheels:      ", names(WHEELS, "name"), saved and builtWheels() or nil, "wheels")
    if i then
        for _, entry in ipairs(WHEELS[i].parts) do
            setMesh(vehicle, entry[1], entry[2])
        end
    end
end

local function lookRow(vehicle)
    local looks = {}
    for _, look in ipairs(BASE_LOOKS) do
        table.insert(looks, shortLook(look))
    end
    local current = shortLook(lookOf(vehicle)):gsub("__vc_[ab]$", "")
    local i = choiceRow("Base look:   ", looks, current, "look")
    if i then
        changeLookNow(vehicle, BASE_LOOKS[i])
    end
end

local function kitRows(vehicle)
    if not build.kit then
        ImGui.Text("Nomad front kit (from the Archer Quartz Nomad): off")
        ImGui.SameLine()
        if ImGui.Button("Put it on") then
            build.kit = true
            build.kitOffset = { 0, 0, 0 }
            saveBuild()
            buildCopySeen(vehicle)
            tellKitService()
            log("Nomad kit on")
            rebuildInPlace(vehicle)
        end
        return
    end
    ImGui.Text(string.format("Nomad front kit: on, %d of %d parts on the car, moved %.1f m ahead and %.1f m up",
        kitPartsOn(vehicle), #KIT, build.kitOffset[2], build.kitOffset[3]))
    ImGui.SameLine()
    if ImGui.Button("Take it off") then
        takeKitOff()
        rebuildInPlace(vehicle)
    end
    ImGui.Text("Move the kit:")
    ImGui.SameLine()
    if ImGui.Button("ahead") then moveKit(vehicle, 0.1, 0) end
    ImGui.SameLine()
    if ImGui.Button("back") then moveKit(vehicle, -0.1, 0) end
    ImGui.SameLine()
    if ImGui.Button("up") then moveKit(vehicle, 0, 0.1) end
    ImGui.SameLine()
    if ImGui.Button("down") then moveKit(vehicle, 0, -0.1) end
    ImGui.SameLine()
    if ImGui.Button("where the Quartz has it") then moveKit(vehicle, -build.kitOffset[2], -build.kitOffset[3]) end
end

local function testCopySection(vehicle)
    ImGui.TextWrapped("Each choice is saved and built into the car, which rebuilds where it stands in about a second. "
        .. "A call brings it back with its parts; the base look goes back to player_01.")
    ImGui.Spacing()
    hellaParts(vehicle, true)
    lookRow(vehicle)
    kitRows(vehicle)
    ImGui.Spacing()
    ImGui.Text(string.format("Saved: %d parts, Nomad kit %s", #build.order, build.kit and "on" or "off"))
    ImGui.SameLine()
    if ImGui.Button("Rebuild in place") then
        rebuildInPlace(vehicle)
    end
    ImGui.SameLine()
    if ImGui.Button("Start over (stock)") then
        build = emptyBuild()
        saveBuild()
        log("saved build forgotten; rebuilding the copy stock")
        pendingRebuild = vehicle:GetEntityID()
    end
    if ImGui.CollapsingHeader("What the service did") then
        ImGui.TextWrapped("Last build: " .. kitServiceNote())
        for _, line in ipairs(serviceSwapNotes(vehicle)) do
            ImGui.TextWrapped(line)
        end
        for _, line in ipairs(serviceWatchNotes()) do
            ImGui.TextWrapped(line)
        end
    end
end

local function bikeSection(vehicle)
    ImGui.TextWrapped("Bike changes go straight onto it and aren't kept.")
    local i = choiceRow("Body paint:", BIKE_PAINTS, nil, "bikepaint")
    if i then
        setPaint(vehicle, "body_a_01", BIKE_PAINTS[i])
    end
    i = choiceRow("Fairing:   ", names(FAIRINGS, "name"), nil, "fairing")
    if i then
        setMesh(vehicle, "fairing_a_01", FAIRINGS[i].mesh, FAIRINGS[i].paint)
        setMesh(vehicle, "fairing_a_01_shadow", FAIRINGS[i].shadow)
    end
end

local function callTestCopy()
    attempt("test Hella called", function()
        return kitService():CallBack()
    end)
end

-- The Try moment: two robot arms at the car's nose, working with their own welding, then the part goes on.
-- The Phantom Liberty arm is a device whose animation graph takes a state (0 idle, 1 work, 2 distract), and
-- its entity names its own welding effect and work sound. Delamain's arm, from his garage quest, is a plain
-- animated entity with a weld effect of its own. Nothing here adds sparks the arms don't already have.
local ARM_PL = "ep1\\gameplay\\devices\\robotic_arms\\robotic_arms.ent"
local ARM_DELAMAIN = "base\\items\\interactive\\industrial\\int_industrial_002__robotic_arm_delamain.ent"
local PL_WORK_SOUND = "amb_g_city_el_tv_p_sq031_1_bushido_x__workshop_scene_loop"
local TRY_SECONDS = 4

local arms = {} -- { id = EntityID, kind = "Phantom Liberty" or "Delamain" }
local armTurn = 0 -- extra degrees, in case an arm faces the wrong way
local pendingTry = nil

local function spawnArm(path, kind, position, target)
    local transform = WorldTransform.new()
    transform:SetPosition(position)
    local facing = Vector4.ToRotation(Vector4.new(target.x - position.x, target.y - position.y, 0, 0))
    transform:SetOrientationEuler(EulerAngles.new(0, 0, facing.yaw + armTurn))
    local id = exEntitySpawner.Spawn(path, transform, "")
    table.insert(arms, { id = id, kind = kind })
    return "spawned"
end

local function bringArms(vehicle)
    local position = vehicle:GetWorldPosition()
    local forward = vehicle:GetWorldForward()
    local right = vehicle:GetWorldRight()
    local function at(ahead, side)
        return Vector4.new(position.x + forward.x * ahead + right.x * side,
            position.y + forward.y * ahead + right.y * side, position.z, 1)
    end
    local nose = at(2.2, 0)
    attempt("Phantom Liberty arm, front left", function() return spawnArm(ARM_PL, "Phantom Liberty", at(3.0, -1.8), nose) end)
    attempt("Delamain arm, front right", function() return spawnArm(ARM_DELAMAIN, "Delamain", at(3.0, 1.8), nose) end)
end

local function forEachArm(action)
    for _, arm in ipairs(arms) do
        local entity = Game.FindEntityByID(arm.id)
        if entity then
            action(arm, entity)
        else
            log(arm.kind .. " arm isn't in the world")
        end
    end
end

local function setArmState(state)
    forEachArm(function(arm, entity)
        if arm.kind == "Phantom Liberty" then
            attempt(arm.kind .. " arm state " .. state, function()
                local feature = NewObject("AnimFeature_RoboticArm")
                feature.state = state
                AnimationControllerComponent.ApplyFeature(entity, CName.new("Robotic_arm"), feature)
                if state == 1 then
                    GameObject.PlaySound(entity, CName.new(PL_WORK_SOUND))
                else
                    GameObject.StopSound(entity, CName.new(PL_WORK_SOUND))
                end
                return true
            end)
        end
    end)
end

local function setWelding(on)
    forEachArm(function(arm, entity)
        if arm.kind == "Phantom Liberty" then
            attempt(arm.kind .. " arm welding " .. tostring(on), function()
                if on then
                    GameObjectEffectHelper.StartEffectEvent(entity, CName.new("FX_Welding_Sparks"), false)
                else
                    GameObjectEffectHelper.StopEffectEvent(entity, CName.new("FX_Welding_Sparks"))
                end
                return true
            end)
        else
            attempt(arm.kind .. " arm welding " .. tostring(on), function()
                local event = on and entSpawnEffectEvent.new() or entKillEffectEvent.new()
                event.effectName = CName.new("sq025_weld")
                entity:QueueEvent(event)
                return true
            end)
        end
    end)
end

local function sendArmsAway()
    forEachArm(function(arm, entity)
        attempt(arm.kind .. " arm despawn", function()
            exEntitySpawner.Despawn(entity)
            return true
        end)
    end)
    arms = {}
end

local function tryBumper(vehicle)
    local bumper = BUMPERS[nextBumper]
    nextBumper = nextBumper % #BUMPERS + 1
    setArmState(1)
    setWelding(true)
    pendingTry = { at = clock + TRY_SECONDS, id = vehicle:GetEntityID(), bumper = bumper }
    log("arms at work; the " .. bumper.name .. " bumper goes on in " .. TRY_SECONDS .. " s")
end

local function finishTry()
    local try = pendingTry
    pendingTry = nil
    local vehicle = Game.FindEntityByID(try.id)
    if vehicle then
        setMesh(vehicle, "bumper_f_01", try.bumper.mesh, try.bumper.paint)
    else
        log("the car isn't in the world any more")
    end
    setWelding(false)
    setArmState(0)
end

local function armButtons(vehicle, look)
    ImGui.Text("Robot arms here: " .. #arms)
    if #arms == 0 then
        if ImGui.Button("Bring two arms to this car's nose") then
            bringArms(vehicle)
        end
        return
    end
    if ImGui.Button("Arms: work") then setArmState(1) end
    ImGui.SameLine()
    if ImGui.Button("Arms: idle") then setArmState(0) end
    ImGui.SameLine()
    if ImGui.Button("Arms: distract") then setArmState(2) end
    if ImGui.Button("Welding on") then setWelding(true) end
    ImGui.SameLine()
    if ImGui.Button("Welding off") then setWelding(false) end
    if look:find("archer_hella", 1, true) and not pendingTry then
        if ImGui.Button("Try the " .. BUMPERS[nextBumper].name .. " front bumper, with the arms") then
            tryBumper(vehicle)
        end
    end
    if ImGui.Button("Turn the arms 90 degrees") then
        armTurn = (armTurn + 90) % 360
        sendArmsAway()
        bringArms(vehicle)
        log("arms turned by " .. armTurn .. " degrees in all")
    end
    ImGui.SameLine()
    if ImGui.Button("Send the arms away") then sendArmsAway() end
end

local function garageSection()
    ImGui.TextWrapped("The test copies: the test Hella and a second Hella in its own look, a Kaukaz Bratsk truck "
        .. "and a Chevalier Centurion van V can't normally own, and a Rayfield Excalibur AV. Don't call the AV: "
        .. "it crashes the game.")
    if ImGui.Button("Add them to my garage") then
        for _, name in ipairs(FILE_COPIES) do
            attempt(name .. " unlock", function()
                return Game.GetVehicleSystem():EnablePlayerVehicle(name, true, false)
            end)
        end
    end
    ImGui.SameLine()
    if ImGui.Button("Remove them") then
        for _, name in ipairs(FILE_COPIES) do
            attempt(name .. " remove", function()
                return Game.GetVehicleSystem():EnablePlayerVehicle(name, false, true)
            end)
        end
    end
end

-- Earlier tests kept for reference; nothing the current test needs.
local function olderSection(vehicle)
    ImGui.TextWrapped("Who puts the test Hella's build on: " .. (buildByService
        and "the service, as the car is built (current)." or "this window, after the car appears (old way)."))
    if ImGui.Button(buildByService and "Switch to the old way" or "Switch back to the service") then
        buildByService = not buildByService
        log("the saved build is now put on " .. (buildByService and "by the service as the car is built"
            or "by the window after the car appears"))
        tellKitService()
    end
    if ImGui.Button("Rebuild the test Hella by sending it to the garage and calling it back") then
        rebuildCopy()
    end
    if vehicle then
        if ImGui.Button("Write this vehicle's parts to test.log") then
            describe(vehicle)
        end
        ImGui.SameLine()
        if ImGui.Button("Write its kit parts to test.log") then
            logKitParts(vehicle)
        end
        if isBuildCopy(vehicle) and not buildByService then
            if ImGui.Button("Put the saved build back now (old way)") then
                log("putting the saved build back by hand: " .. applyBuild(vehicle) .. " changes didn't take")
            end
        end
        if ImGui.Button("Copy this vehicle now, without a restart (live copy)") then
            copyNow(vehicle)
        end
    end
    local live = readLive()
    if #live > 0 then
        ImGui.Text("Live copies: " .. #live)
        ImGui.SameLine()
        if ImGui.Button("Unlock them again") then
            for _, copy in ipairs(live) do
                unlock(copy.name)
            end
        end
        ImGui.SameLine()
        if ImGui.Button("Remove live copies") then
            for _, copy in ipairs(live) do
                attempt(copy.name .. " remove", function()
                    return Game.GetVehicleSystem():EnablePlayerVehicle(copy.name, false, true)
                end)
            end
            writeLive({})
        end
    end
    if vehicle and ImGui.CollapsingHeader("Robot arms") then
        armButtons(vehicle, lookOf(vehicle))
    end
end

local function drawWindow()
    ImGui.TextWrapped("Last: " .. status)
    ImGui.Separator()

    local vehicle = currentVehicle()
    if not vehicle then
        ImGui.Text("Look at or sit in a car.")
        if ImGui.Button("Call the test Hella") then
            callTestCopy()
        end
    else
        local look = lookOf(vehicle)
        if isBuildCopy(vehicle) then
            ImGui.Text("The test Hella  (look " .. shortLook(look) .. ")")
            testCopySection(vehicle)
        elseif look:find("archer_hella", 1, true) then
            ImGui.Text("A Hella that isn't the test copy  (look " .. shortLook(look) .. ")")
            ImGui.TextWrapped("Changes go straight onto it and aren't kept. Only the test Hella keeps a build.")
            hellaParts(vehicle, false)
        elseif look:find("arch_nemesis", 1, true) then
            ImGui.Text("A Nazare-family bike  (look " .. look .. ")")
            bikeSection(vehicle)
        else
            ImGui.Text("Vehicle " .. labelOf(vehicle) .. "  (look " .. look .. ")")
            ImGui.TextWrapped("No part buttons for this one: only the Hella and the Nazare, Racer and Kobold bikes have them.")
        end
    end

    ImGui.Spacing()
    if ImGui.CollapsingHeader("Garage copies") then
        garageSection()
    end
    if ImGui.CollapsingHeader("Older experiments") then
        olderSection(vehicle)
    end
end

registerForEvent("onTweak", function()
    for _, copy in ipairs(readLive()) do
        local ok, result = pcall(makeRecord, copy.name, TweakDBID.new(copy.hash, copy.length))
        log("at startup " .. copy.name .. " -> " .. (ok and result or ("ERROR " .. tostring(result))))
    end
    if build.look then
        log("at startup, base look of the build copy " .. build.look)
        setLookFlat(build.look)
    end
end)

registerForEvent("onInit", function()
    ObserveAfter("VehicleObject", "OnGameAttached", function(self)
        local ok, problem = pcall(onVehicleAttached, self)
        if not ok then
            log("watching vehicles appear failed: " .. tostring(problem))
        end
    end)
    log(string.format("loaded; saved build: %d parts, base look %s", #build.order, build.look or "stock"))
    tellKitService()
end)

registerForEvent("onUpdate", function(delta)
    clock = clock + delta
    if #pendingApply > 0 then
        local ok, problem = pcall(applyPending)
        if not ok then
            pendingApply = {}
            log("putting the build back failed: " .. tostring(problem))
        end
    end
    if clock >= nextHealCheck then
        nextHealCheck = clock + 1
        logLookKeeps()
        local ok, problem = pcall(healBuild)
        if not ok then
            log("checking the build copy's parts failed: " .. tostring(problem))
            nextHealCheck = clock + 30
        end
    end
    if pendingCallBack and clock >= pendingCallBack then
        callBackCopy()
    end
    if pendingRebuild then
        local vehicle = Game.FindEntityByID(pendingRebuild)
        pendingRebuild = nil
        if vehicle then
            tellKitService()
            rebuildInPlace(vehicle)
        end
    end
    if pendingTry and clock >= pendingTry.at then
        local ok, problem = pcall(finishTry)
        if not ok then
            pendingTry = nil
            log("finishing the try failed: " .. tostring(problem))
        end
    end
end)

registerForEvent("onOverlayOpen", function() overlayOpen = true end)
registerForEvent("onOverlayClose", function() overlayOpen = false end)

registerForEvent("onDraw", function()
    if not overlayOpen then
        return
    end
    if ImGui.Begin("Vehicle Customizer Test") then
        -- A Lua error between Begin and End would unbalance ImGui, so nothing may escape here.
        local ok, problem = pcall(drawWindow)
        if not ok then
            ImGui.TextWrapped(tostring(problem))
        end
    end
    ImGui.End()
end)
