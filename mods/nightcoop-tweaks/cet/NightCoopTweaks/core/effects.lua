-- Effects an entity can play (glowing eyes, sparks, glitches): the names in
-- its effect spawners (entEffectSpawnerComponent.effectDescs, from its
-- template), played and ended by name the way the game's scripts do.

local Effects = {}

local TEST_SECONDS = 3.0

local tests = {} -- { object, name, endAt }: plays from the console, ended in Update

local function cname(name)
    return CName.new(name)
end

-- The effect names `entity` can play, sorted (needs Codeware's GetComponents).
function Effects.Names(entity)
    local names = {}
    for _, component in ipairs(entity:GetComponents()) do
        if component:IsA("entEffectSpawnerComponent") then
            for _, desc in ipairs(component.effectDescs) do
                table.insert(names, Game.NameToString(desc.effectName))
            end
        end
    end
    table.sort(names)
    return names
end

function Effects.Play(object, name)
    GameObjectEffectHelper.StartEffectEvent(object, cname(name))
end

-- Lets a looping effect play out its end, as quest scenes do.
function Effects.End(object, name)
    GameObjectEffectHelper.BreakEffectLoopEvent(object, cname(name))
end

local function lookAt()
    local player = Game.GetPlayer()
    return player and Game.GetTargetingSystem():GetLookAtObject(player, false, false)
end

-- One line on what we look at and the effects it has, for diagnostics.
function Effects.Describe()
    local target = lookAt()
    if not target then
        return "Effects: look at someone to list theirs"
    end
    local ok, names = pcall(Effects.Names, target)
    local what = Game.NameToString(target:GetClassName())
    if not ok then
        return string.format("Effects of %s: can't list them (%s)", what, tostring(names))
    end
    if #names == 0 then
        return string.format("Effects of %s: none", what)
    end
    return string.format("Effects of %s (%d): %s", what, #names, table.concat(names, ", "))
end

-- From the CET console: plays `name` on what we look at for a few seconds.
function Effects.Try(name, seconds)
    local target = lookAt()
    if not target then
        return "look at someone first"
    end
    Effects.Play(target, name)
    table.insert(tests, { object = target, name = name, endAt = os.clock() + (seconds or TEST_SECONDS) })
    return "playing " .. name .. " on " .. Game.NameToString(target:GetClassName())
end

function Effects.Update()
    if #tests == 0 then
        return
    end
    local now = os.clock()
    for i = #tests, 1, -1 do
        local test = tests[i]
        if now >= test.endAt then
            pcall(Effects.End, test.object, test.name)
            table.remove(tests, i)
        end
    end
end

function Effects.Shutdown()
    for _, test in ipairs(tests) do
        pcall(Effects.End, test.object, test.name)
    end
    tests = {}
end

return Effects
