-- Development only (vehicle-customizer/RECORD.md): a CET window over the engine, driven by the catalog.
-- It works on the car V is in, else the one V looks at, else the last one it spawned, if that car is a pool copy
-- (Vehicle.vc_<catalog>_<n>). Every choice goes through the engine's own calls, as the shop's will, so each one
-- saves the build and rebuilds the car in place. It reads the catalog from TweakDB, as the engine does.

local panel = { spawnCatalog = 1, spawnCopy = 1, fine = false, verify = "" }

local function try(action)
    local ok, result = pcall(action)
    if ok then
        return result
    end
    return nil
end

local function str(cname)
    if cname == nil then
        return ""
    end
    return try(function() return cname.value end) or try(function() return NameToString(cname) end) or tostring(cname)
end

-- An entry of a dropdown the user picked. CET's Selectable answers whether the entry is selected, every frame,
-- not whether it was clicked: an open paint list re-applied the current paint each frame, rebuilding the car 30
-- times a second until it was thrown into the air with the user inside (2026-11-06). So only an entry that
-- isn't the current one counts.
local function picked(label, isCurrent)
    return ImGui.Selectable(label, isCurrent) == true and not isCurrent
end

local function engine()
    return try(function() return Game.GetScriptableSystemsContainer():Get("VehicleCustomizer.VCEngine") end)
end

local cache = {}
local function flat(cat, path)
    local key = cat .. "." .. path
    if cache[key] == nil then
        cache[key] = try(function() return TweakDB:GetFlat("VehicleCustomizer." .. key) end) or false
    end
    return cache[key] or nil
end

local function names(cat, path)
    local out = {}
    for _, v in ipairs(flat(cat, path) or {}) do
        table.insert(out, str(v))
    end
    return out
end

-- The build text, read the way Build.reds writes it.
local function parseBuild(text)
    local build = { look = "", paint = "", slots = {}, kits = {}, kitOrder = {}, wheels = { f = "", b = "" },
                    fit = { f = { 100, 100 }, b = { 100, 100 } } }
    for field in (text or ""):gmatch("[^;]+") do
        local key, value = field:match("^([%a@]+)=(.*)$")
        -- build.wheels is the rim on each axle (rims and tires apart since 2026-11-07; wheels= is an older build's
        -- set for both); the panel's list still puts a set's rim and tire on together.
        if key == "wheels" or key == "rims" then
            build.wheels.f, build.wheels.b = value, value
        elseif key == "wheels@f" or key == "wheels@b" or key == "rims@f" or key == "rims@b" then
            build.wheels[key:sub(-1)] = value
        elseif key == "wheelpaint" then
            build.wheelPaint = { f = value, b = value }
        elseif key == "wheelpaint@f" or key == "wheelpaint@b" then
            build.wheelPaint = build.wheelPaint or { f = "", b = "" }
            build.wheelPaint[key:sub(-1)] = value
        elseif key == "fit@f" or key == "fit@b" then
            -- size:tire width[:rim width] (the rim's own width since 2026-11-07)
            local size, width, rim = value:match("^([^:]*):([^:]*):?(.*)$")
            build.fit[key:sub(-1)] = { tonumber(size) or 100, tonumber(width) or 100, tonumber(rim) or 100 }
        elseif key == "look" then
            build.look = value
        elseif key == "paint" then
            build.paint = value
        elseif key == "slot" then
            local slot, option, paint = value:match("^([^:]*):([^:]*):?(.*)$")
            if slot then
                build.slots[slot] = { option = option, paint = paint }
            end
        elseif key == "kit" then
            -- kit=<kit>:x:y:z:yaw[:pitch:roll]
            local f = {}
            for piece in (value .. ":"):gmatch("([^:]*):") do
                table.insert(f, piece)
            end
            local kit = f[1]
            build.kits[kit] = { x = tonumber(f[2]) or 0, y = tonumber(f[3]) or 0, z = tonumber(f[4]) or 0,
                                yaw = tonumber(f[5]) or 0, pitch = tonumber(f[6]) or 0, roll = tonumber(f[7]) or 0 }
            table.insert(build.kitOrder, kit)
        elseif key == "part" then
            -- part=<kit>:<index>:x:y:z:yaw:pitch:roll, for parts moved on their own
            local f = {}
            for piece in (value .. ":"):gmatch("([^:]*):") do
                table.insert(f, piece)
            end
            build.parts = build.parts or {}
            build.parts[f[1] .. ":" .. (f[2] or "")] = { x = tonumber(f[3]) or 0, y = tonumber(f[4]) or 0,
                z = tonumber(f[5]) or 0, yaw = tonumber(f[6]) or 0, pitch = tonumber(f[7]) or 0, roll = tonumber(f[8]) or 0 }
        end
    end
    return build
end

local function baseLook(look)
    return (look:gsub("__vc_[ab]$", ""))
end

local function targetCar()
    local player = Game.GetPlayer()
    if not player then
        return nil
    end
    local mounted = try(function() return Game.GetMountedVehicle(player) end)
    if mounted then
        return mounted, "V is in it"
    end
    local looked = try(function() return Game.GetTargetingSystem():GetLookAtObject(player, false, false) end)
    if looked and try(function() return looked:IsVehicle() end) then
        return looked, "V looks at it"
    end
    if panel.spawned then
        local spawned = try(function() return Game.FindEntityByID(panel.spawned) end)
        if spawned then
            return spawned, "spawned here"
        end
    end
    return nil
end

local TAG_COLORS = {
    style = { 0.45, 0.85, 0.45 },
    look = { 0.45, 0.70, 1.00 },
    wreck = { 0.65, 0.65, 0.65 },
    car = { 1.00, 0.65, 0.30 },
}

local function tags(cat, key)
    local car = flat(cat, key .. ".vehicle")
    if car then
        ImGui.SameLine()
        local c = TAG_COLORS.car
        ImGui.TextColored(c[1], c[2], c[3], 1, "[car " .. car .. "]")
    end
    local shown = 0
    for _, origin in ipairs(names(cat, key .. ".origins")) do
        local kind, name = origin:match("^(%a+):(.*)$")
        if kind == "style" then
            name = flat(cat, "style." .. name .. ".label") or name
        end
        if shown < 4 and kind then
            local c = TAG_COLORS[kind] or { 1, 1, 1 }
            ImGui.SameLine()
            ImGui.TextColored(c[1], c[2], c[3], 1, "[" .. kind .. " " .. name .. "]")
            shown = shown + 1
        end
    end
end

-- Repairs a car where it stands, the game's ways: its repair event (health back to full, no longer destroyed),
-- then the dents and the broken glass. No rebuild: the car's damage outlives a rebuild, which put the dents and a
-- lost bumper straight back (user's picture, 2026-11-06), and nothing in scripts puts a lost part back on; for
-- that, "Fresh from garage" sends the car away and calls it again, as the game repairs V's cars.
local function repair(v)
    local event = try(function() return VehicleRepairEvent.new() end)
        or try(function() return NewObject("VehicleRepairEvent") end)
    if event then
        v:QueueEvent(event)
    end
    local dents = try(function() v:DestructionResetGrid() return true end)
    local glass = try(function() v:DestructionResetGlass() return true end)
    panel.repair = "repaired in place: " .. (event and "health" or "no repair event") .. ", "
        .. (dents and "dents" or "dents failed") .. ", " .. (glass and "glass" or "glass failed")
end

local function spawnAhead(record)
    local player = Game.GetPlayer()
    local pos = player:GetWorldPosition()
    local f = player:GetWorldForward()
    local yaw = math.atan2(-f.x, f.y) + math.pi / 2
    local spec = DynamicEntitySpec.new()
    spec.recordID = TweakDBID.new(record)
    spec.position = Vector4.new(pos.x + f.x * 7, pos.y + f.y * 7, pos.z + 0.2, 1)
    spec.orientation = Quaternion.new(0, 0, math.sin(yaw / 2), math.cos(yaw / 2))
    spec.alwaysSpawned = true
    spec.persistState = false
    spec.persistSpawn = false
    if panel.spawned then
        try(function() Game.GetDynamicEntitySystem():DeleteEntity(panel.spawned) end)
    end
    panel.spawned = Game.GetDynamicEntitySystem():CreateEntity(spec)
end

local function spawnSection(e)
    if not ImGui.CollapsingHeader("Spawn or call a pool copy") then
        return
    end
    local cats = names("", "catalogs")
    if #cats == 0 then
        cats = {}
        for _, v in ipairs(try(function() return TweakDB:GetFlat("VehicleCustomizer.catalogs") end) or {}) do
            table.insert(cats, str(v))
        end
    end
    if #cats == 0 then
        ImGui.Text("No catalogs in TweakDB.")
        return
    end
    panel.spawnCatalog = math.max(1, math.min(panel.spawnCatalog, #cats))
    local current = cats[panel.spawnCatalog]
    if ImGui.BeginCombo("catalog", (flat(current, "label") or current) .. "  (" .. current .. ")") then
        for i, cat in ipairs(cats) do
            if picked((flat(cat, "label") or cat) .. "  (" .. cat .. ")##" .. i, i == panel.spawnCatalog) then
                panel.spawnCatalog = i
            end
        end
        ImGui.EndCombo()
    end
    panel.spawnCopy = ImGui.SliderInt("copy", panel.spawnCopy, 1, 5)
    local record = "Vehicle.vc_" .. current .. "_" .. panel.spawnCopy
    ImGui.Text(record)
    if ImGui.Button("Spawn 7 m ahead") then
        spawnAhead(record)
    end
    ImGui.SameLine()
    if ImGui.Button("Unlock in garage") and e then
        e:Unlock(TweakDBID.new(record))
    end
    ImGui.SameLine()
    if ImGui.Button("Call") and e then
        e:Call(TweakDBID.new(record))
    end
    ImGui.SameLine()
    if ImGui.Button("Send away") and e then
        e:SendAway(TweakDBID.new(record))
    end
end

local function styleSection(e, v, cat, build, look)
    if not ImGui.CollapsingHeader("Style and paint", ImGuiTreeNodeFlags.DefaultOpen) then
        return
    end
    local current = baseLook(look)
    for _, style in ipairs(names(cat, "styles")) do
        local key = "style." .. style
        local looks = names(cat, key .. ".looks")
        local label = (flat(cat, key .. ".label") or style) .. "  " .. (flat(cat, key .. ".code") or style)
        ImGui.PushID(style)
        local inStyle = false
        for _, l in ipairs(looks) do
            if l == current then
                inStyle = true
            end
        end
        if ImGui.RadioButton(label, inStyle) and not inStyle then
            e:ChooseLook(v, CName.new(looks[1]))
        end
        if inStyle and #looks > 1 then
            ImGui.Indent()
            for _, l in ipairs(looks) do
                local short = l:gsub("^.-__basic_", ""):gsub("^.-__", "")
                if ImGui.RadioButton(short, l == current) and l ~= current then
                    e:ChooseLook(v, CName.new(l))
                end
                ImGui.SameLine()
            end
            ImGui.NewLine()
            ImGui.Unindent()
        end
        ImGui.PopID()
    end
    -- The whole car's paint: what the body offers.
    local bodyOption = nil
    for _, slot in ipairs(names(cat, "slots")) do
        if slot == "base.body" then
            bodyOption = names(cat, "slot." .. slot .. ".options")[1]
        end
    end
    local paints = bodyOption and names(cat, "option." .. bodyOption .. ".paints") or {}
    if #paints > 0 and ImGui.BeginCombo("whole car paint", build.paint ~= "" and build.paint or "(the look's own)") then
        if picked("(the look's own)", build.paint == "") then
            -- CName.new(0) is the game's "no name"; CName.new("") names the empty string (wheels run, 2026-11-07).
            e:ChooseCarPaint(v, CName.new(0))
        end
        for _, p in ipairs(paints) do
            if picked(p, p == build.paint) then
                e:ChooseCarPaint(v, CName.new(p))
            end
        end
        ImGui.EndCombo()
    end
end

local function slotSection(e, v, cat, build, look)
    if not ImGui.CollapsingHeader("Parts") then
        return
    end
    -- The slots the current look has a part in; for the others a pick adds the part.
    local has = {}
    for _, row in ipairs(names(cat, "look." .. baseLook(look) .. ".parts")) do
        has[row:match("^([^|]+)|") or ""] = true
    end
    for _, slot in ipairs(names(cat, "slots")) do
        local key = "slot." .. slot
        local chosen = build.slots[slot]
        ImGui.PushID(slot)
        ImGui.Text((flat(cat, key .. ".label") or slot) .. "  [" .. slot .. "]")
        if not has[slot] then
            ImGui.SameLine()
            ImGui.TextColored(0.7, 0.7, 0.7, 1, "(this style has none; a pick adds it)")
        end
        ImGui.Indent()
        if ImGui.RadioButton(has[slot] and "the style's own" or "none", chosen == nil) and chosen then
            e:ClearSlot(v, CName.new(slot))
        end
        for _, option in ipairs(names(cat, key .. ".options")) do
            local okey = "option." .. option
            local isChosen = chosen ~= nil and chosen.option == option
            if ImGui.RadioButton((flat(cat, okey .. ".code") or option) .. "##" .. option, isChosen) and not isChosen then
                e:ChooseOption(v, CName.new(slot), CName.new(option))
            end
            tags(cat, okey)
        end
        local paints = chosen and names(cat, "option." .. chosen.option .. ".paints") or {}
        if #paints > 0 and ImGui.BeginCombo("paint", chosen.paint ~= "" and chosen.paint or "(carried over)") then
            for _, p in ipairs(paints) do
                if picked(p, p == chosen.paint) then
                    e:ChoosePaint(v, CName.new(slot), CName.new(p))
                end
            end
            ImGui.EndCombo()
        elseif not chosen and ImGui.Button("paint this part") then
            local first = nil
            local style = nil
            -- the style's option's first paint, so the slot has a paint to change from
            for _, s in ipairs(names(cat, "styles")) do
                for _, l in ipairs(names(cat, "style." .. s .. ".looks")) do
                    if l == baseLook(build.look ~= "" and build.look or "") then
                        style = s
                    end
                end
            end
            for _, row in ipairs(style and names(cat, "style." .. style .. ".options") or {}) do
                local s, o = row:match("^(.-)=(.*)$")
                if s == slot then
                    first = names(cat, "option." .. o .. ".paints")[1]
                end
            end
            if first then
                e:ChoosePaint(v, CName.new(slot), CName.new(first))
            end
        end
        ImGui.Unindent()
        ImGui.PopID()
    end
end

-- The shared wheel list (wheels.yaml), read straight from TweakDB.
local wheelCache = {}
local function wheelFlat(path)
    if wheelCache[path] == nil then
        wheelCache[path] = try(function() return TweakDB:GetFlat("VehicleCustomizer." .. path) end) or false
    end
    return wheelCache[path] or nil
end

local function wheelSection(e, v, cat, build)
    if not ImGui.CollapsingHeader("Wheels") then
        return
    end
    local kind = str(flat(cat, "wheelKind"))
    local own = flat(cat, "wheelFit")
    if kind == "" or not own or not own[1] then
        ImGui.Text("No wheel size for this car in the catalog.")
        return
    end
    local function cm(x)
        return string.format("%.0f", x * 100)
    end
    ImGui.Text(string.format("This car's own: front %s x %s cm, back %s x %s cm (across x wide)",
        cm(own[1].x * 2), cm(own[1].y), cm(own[2].x * 2), cm(own[2].y)))
    panel.axle = panel.axle or "all"
    for _, a in ipairs({ { "all", "All four" }, { "f", "Front" }, { "b", "Back" } }) do
        if ImGui.RadioButton(a[2] .. "##axle", panel.axle == a[1]) and panel.axle ~= a[1] then
            panel.axle = a[1]
        end
        ImGui.SameLine()
    end
    ImGui.NewLine()
    local axle = panel.axle == "b" and "b" or "f"
    local current = build.wheels[axle]
    -- How big they sit, in percent of the car's own.
    local fit = build.fit[axle]
    local step = panel.fine and 1 or 5
    ImGui.Text(string.format("size %d%%  width %d%%", fit[1], fit[2]))
    for _, m in ipairs({ { "size", step, 0 }, { "width", 0, step } }) do
        ImGui.SameLine()
        if ImGui.Button("-" .. m[1]) then
            e:SetWheelFit(v, CName.new(panel.axle), fit[1] - m[2], fit[2] - m[3])
        end
        ImGui.SameLine()
        if ImGui.Button("+" .. m[1]) then
            e:SetWheelFit(v, CName.new(panel.axle), fit[1] + m[2], fit[2] + m[3])
        end
    end
    ImGui.SameLine()
    if ImGui.Button("own size") then
        e:SetWheelFit(v, CName.new(panel.axle), 100, 100)
    end
    -- The rims' paint: the set's paints, or this car's own rims' when no set is on.
    local paintNow = (build.wheelPaint and build.wheelPaint[axle]) or ""
    local paints, seen = {}, {}
    local function offer(list)
        for _, p in ipairs(list or {}) do
            local name = str(p)
            if not seen[name] then
                seen[name] = true
                table.insert(paints, name)
            end
        end
    end
    if current ~= "" then
        offer(wheelFlat("wheel." .. current .. ".paints"))
    else
        for _, option in ipairs(names(cat, "slot.wheel.wheel.options")) do
            offer(flat(cat, "option." .. option .. ".paints"))
        end
    end
    if #paints > 0 and ImGui.BeginCombo("rim paint", paintNow ~= "" and paintNow or "(as they come)") then
        if picked("(as they come)", paintNow == "") then
            e:ChooseWheelPaint(v, CName.new(panel.axle), CName.new(0))
        end
        for _, p in ipairs(paints) do
            if picked(p, p == paintNow) then
                e:ChooseWheelPaint(v, CName.new(panel.axle), CName.new(p))
            end
        end
        ImGui.EndCombo()
    end
    -- The list for this kind of vehicle, those nearest this car's own size first.
    local ids = {}
    for _, id in ipairs(wheelFlat("wheels." .. kind) or {}) do
        table.insert(ids, str(id))
    end
    local ref = axle == "b" and own[2] or own[1]
    table.sort(ids, function(a, b)
        local sa, sb = wheelFlat("wheel." .. a .. ".size"), wheelFlat("wheel." .. b .. ".size")
        return math.abs((sa and sa.x or 0) - ref.x) < math.abs((sb and sb.x or 0) - ref.x)
    end)
    if ImGui.BeginChild("wheel list", 0, 260, true) then
        if picked("the car's own rims and tires", current == "") then
            e:ChooseWheels(v, CName.new(panel.axle), CName.new(0))
        end
        for _, id in ipairs(ids) do
            local size = wheelFlat("wheel." .. id .. ".size")
            local label = string.format("%s  %s x %s cm  [%s]##%s", wheelFlat("wheel." .. id .. ".code") or id,
                size and cm(size.x * 2) or "?", size and cm(size.y) or "?", wheelFlat("wheel." .. id .. ".from") or "?", id)
            if picked(label, current == id) then
                e:ChooseWheels(v, CName.new(panel.axle), CName.new(id))
            end
        end
    end
    ImGui.EndChild()
end

local function kitSection(e, v, cat, build)
    if not ImGui.CollapsingHeader("Add-ons") then
        return
    end
    panel.fine = ImGui.Checkbox("fine steps (5 mm, 0.5 degrees; else 5 cm, 5 degrees)", panel.fine)
    local step = panel.fine and 0.005 or 0.05
    local turn = panel.fine and 0.5 or 5
    for _, kit in ipairs(names(cat, "kits")) do
        local key = "kit." .. kit
        local on = build.kits[kit] ~= nil
        ImGui.PushID(kit)
        local _, pressed = ImGui.Checkbox((flat(cat, key .. ".code") or kit) .. "##on", on)
        if pressed then
            e:ToggleKit(v, CName.new(kit))
        end
        tags(cat, key)
        -- What it was made to sit on, as a hint: it hangs off the car's mount points and goes on without it.
        local madeFor = {}
        for _, what in ipairs(names(cat, key .. ".madeFor")) do
            local kind, id = what:match("^(%a+):(.*)$")
            if kind == "kit" then
                table.insert(madeFor, flat(cat, "kit." .. id .. ".code") or id)
            elseif kind == "slot" then
                table.insert(madeFor, flat(cat, "slot." .. id .. ".label") or id)
            end
        end
        if #madeFor > 0 then
            ImGui.SameLine()
            ImGui.TextColored(0.7, 0.7, 0.7, 1, "made to sit on " .. table.concat(madeFor, ", "))
        end
        if on then
            ImGui.Indent()
            -- What the controls move: the whole kit, or one part of it on its own (user, 2026-11-06).
            panel.kitPart = panel.kitPart or {}
            local target = panel.kitPart[kit] or -1
            local codes = {}
            for _, c in ipairs(flat(cat, key .. ".codes") or {}) do
                table.insert(codes, tostring(c))
            end
            if ImGui.RadioButton("whole kit##target", target == -1) and target ~= -1 then
                panel.kitPart[kit] = -1
            end
            for i, code in ipairs(codes) do
                ImGui.SameLine()
                if ImGui.RadioButton(code .. "##part" .. i, target == i - 1) and target ~= i - 1 then
                    panel.kitPart[kit] = i - 1
                end
            end
            target = panel.kitPart[kit] or -1
            local o = target == -1 and build.kits[kit]
                or (build.parts and build.parts[kit .. ":" .. target]) or { x = 0, y = 0, z = 0, yaw = 0, pitch = 0, roll = 0 }
            ImGui.Text(string.format("%s: moved %.3f, %.3f, %.3f m; turned yaw %.1f, pitch %.1f, roll %.1f",
                target == -1 and "whole kit" or codes[target + 1] or "part", o.x, o.y, o.z, o.yaw, o.pitch, o.roll))
            -- { label, move x, y, z, yaw; turn pitch, roll }
            local controls = {
                { "x", step, 0, 0, 0, 0, 0 }, { "y", 0, step, 0, 0, 0, 0 }, { "z", 0, 0, step, 0, 0, 0 },
                { "yaw", 0, 0, 0, turn, 0, 0 }, { "pitch", 0, 0, 0, 0, turn, 0 }, { "roll", 0, 0, 0, 0, 0, turn },
            }
            for n, m in ipairs(controls) do
                if n == 4 then
                    ImGui.NewLine()
                end
                for _, sign in ipairs({ -1, 1 }) do
                    if ImGui.Button((sign < 0 and "-" or "+") .. m[1]) then
                        e:NudgeKit(v, CName.new(kit), target, Vector4.new(sign * m[2], sign * m[3], sign * m[4], sign * m[5]),
                            Vector4.new(sign * m[6], sign * m[7], 0, 0))
                    end
                    ImGui.SameLine()
                end
            end
            if ImGui.Button("reset##moves") then
                e:ResetKitMoves(v, CName.new(kit), target)
            end
            ImGui.Unindent()
        end
        ImGui.PopID()
    end
end

function panel.draw()
    -- Back to a known place and size once per load, and never larger than this, so it can't fill the screen
    -- (the user maximized it by accident, 2026-11-06).
    -- In the middle of the screen CET reports: at 100, 100 it was off screen on the user's wide display.
    if not panel.placed then
        local w, h = 1920, 1080
        local ok, dw, dh = pcall(GetDisplayResolution)
        if ok and dw and dh and dw > 0 and dh > 0 then
            w, h = dw, dh
        end
        local ww, wh = 560, math.min(760, h - 80)
        ImGui.SetNextWindowPos((w - ww) / 2, (h - wh) / 2, ImGuiCond.Always)
        ImGui.SetNextWindowSize(ww, wh, ImGuiCond.Always)
        panel.placed = true
    end
    ImGui.SetNextWindowSizeConstraints(360, 200, 1100, 1300)
    if not ImGui.Begin("Vehicle Customizer (dev)") then
        ImGui.End()
        return
    end
    local e = engine()
    if not e then
        ImGui.Text("The engine isn't running (VehicleCustomizer.VCEngine).")
        ImGui.End()
        return
    end
    if panel.callAt and os.clock() >= panel.callAt then
        e:Call(TweakDBID.new(panel.callRecord))
        panel.repair = "called " .. panel.callRecord .. " again; it comes undamaged"
        panel.callAt = nil
    end
    -- Only single lines up here: the engine's note, the build and Verify's answer change length with every
    -- choice and shifted the whole window (user, 2026-11-06), so they're under Status, collapsed at first.
    local v, why = targetCar()
    local record = v and try(function() return v:GetRecordID() end)
    local cat = record and str(e:CatalogOf(record)) or ""
    local function status(lines)
        if ImGui.CollapsingHeader("Status") then
            ImGui.TextWrapped("engine: " .. (try(function() return e:GetNote() end) or ""))
            for _, line in ipairs(lines) do
                ImGui.TextWrapped(line)
            end
        end
    end
    if not v then
        ImGui.Text("No car: get in one, look at one, or spawn a pool copy.")
        status({})
    elseif cat == "" then
        ImGui.Text((try(function() return TDBID.ToStringDEBUG(record) end) or "?") .. " (" .. why .. ") isn't a pool copy.")
        if ImGui.Button("Repair") then
            repair(v)
        end
        status({ panel.repair or "" })
    else
        local text = e:GetBuildText(record)
        local build = parseBuild(text)
        local look = str(v:GetCurrentAppearanceName())
        ImGui.Text((flat(cat, "label") or cat) .. "  " .. TDBID.ToStringDEBUG(record) .. "  (" .. why .. ")")
        if ImGui.Button("Rebuild") then
            e:Rebuild(v)
        end
        ImGui.SameLine()
        if ImGui.Button("Repair") then
            repair(v)
        end
        ImGui.SameLine()
        if ImGui.Button("Fresh from garage") then
            -- Away now, called again in a moment: it comes undamaged, in its build.
            e:SendAway(record)
            panel.callRecord = TDBID.ToStringDEBUG(record)
            panel.callAt = os.clock() + 1.5
            panel.repair = "sent away; calling it again"
        end
        ImGui.SameLine()
        if ImGui.Button("Verify") then
            panel.verify = e:Verify(v)
        end
        ImGui.SameLine()
        if ImGui.Button("Reset build") then
            e:ResetBuild(v)
        end
        ImGui.SameLine()
        if ImGui.Button("Print build") then
            print("[VehicleCustomizerDev] " .. TDBID.ToStringDEBUG(record) .. " " .. text)
        end
        status({
            "look " .. look,
            "build " .. (text ~= "" and text or "(none)"),
            "verify: " .. (panel.verify ~= "" and panel.verify or "(press Verify)"),
            panel.repair or "",
        })
        styleSection(e, v, cat, build, look)
        slotSection(e, v, cat, build, look)
        wheelSection(e, v, cat, build)
        kitSection(e, v, cat, build)
    end
    spawnSection(e)
    ImGui.End()
end

return panel
