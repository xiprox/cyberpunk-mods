-- The game's input actions, for the parts of the mod that read keys. One
-- detached ItemQuantityPickerController listens on the player for every action
-- they ask for (its OnAction only reacts to 'mouse_wheel', so our actions run
-- no game code), and observing its OnAction hands each action to them.

local Log = require("core/log")
local Ref = require("core/ref")

local Input = {}

local CHECK_SECONDS = 0.5

local catcher
local player        -- the player the catcher listens on (a weak slot)
local registered = {} -- action name -> true, on that player
local names = {}    -- the actions asked for, in order
local handlers = {} -- handler(name, kind, action)
local heard = { count = 0 } -- for diagnostics: count, last, at, error
local lastCheck = -math.huge

-- ListenerAction's functions are static; older CET only took them on the instance.
local function actionCall(action, fn)
    local ok, result = pcall(function() return ListenerAction[fn](action) end)
    if ok then
        return result
    end
    return action[fn](action, action)
end

-- The keys behind `action` (EInputKey numbers), or nil when the game doesn't say.
function Input.Keys(action)
    local ok, keys = pcall(actionCall, action, "GetKey")
    if ok and type(keys) == "table" and #keys > 0 then
        return keys
    end
    return nil
end

function Input.HasKey(action, key)
    for _, pressed in ipairs(Input.Keys(action) or {}) do
        if pressed == key then
            return true
        end
    end
    return false
end

-- Hands each of the input actions `actionNames` to `handler(name, kind, action)`,
-- kind being the gameinputActionType's name ("BUTTON_PRESSED", ...). In an Init.
function Input.Listen(actionNames, handler)
    for _, name in ipairs(actionNames) do
        local known = false
        for _, have in ipairs(names) do
            known = known or have == name
        end
        if not known then
            table.insert(names, name)
        end
    end
    table.insert(handlers, handler)
end

local function onAction(action)
    local ok, name, kind = pcall(function()
        return Game.NameToString(actionCall(action, "GetName")), actionCall(action, "GetType").value
    end)
    heard.count = heard.count + 1
    if not ok then
        heard.error = tostring(name)
        return
    end
    heard.last, heard.at = name .. " " .. tostring(kind), os.clock()
    for _, handler in ipairs(handlers) do
        local done, err = pcall(handler, name, kind, action)
        if not done then
            Log.Problem("input: a key handler failed: " .. tostring(err))
        end
    end
end

-- Listens on the current player for every action asked for; a loaded save
-- brings a new player, who gets them all again.
function Input.Update()
    local now = os.clock()
    if now - lastCheck < CHECK_SECONDS then
        return
    end
    lastCheck = now
    local current = Game.GetPlayer()
    if not current then
        return
    end
    local known = player.Get()
    if not (known and Ref.Same(known, current)) then
        registered = {}
        player.Set(current)
    end
    for _, name in ipairs(names) do
        if not registered[name] then
            current:RegisterInputListener(catcher, name)
            registered[name] = true
        end
    end
end

-- What reaches the mod of the keys, for diagnostics.
function Input.Explain()
    local lines = { string.format("Keys: %s, %d action(s)", player and player.Get() and "listening on the player" or "not listening yet", #names) }
    if heard.last then
        table.insert(lines, string.format("Keys heard: %d, last %s %.1f s ago", heard.count, heard.last, os.clock() - heard.at))
    else
        table.insert(lines, string.format("Keys heard: %d", heard.count))
    end
    if heard.error then
        table.insert(lines, "Key error: " .. heard.error)
    end
    return lines
end

function Input.Init()
    catcher = NewObject("ItemQuantityPickerController")
    player = Ref.WeakSlot()
    ObserveAfter("ItemQuantityPickerController", "OnAction", function(self, action)
        if Ref.Same(self, catcher) then
            onAction(action)
        end
    end)
end

function Input.Shutdown()
    local current = player and player.Get()
    if current then
        for name in pairs(registered) do
            current:UnregisterInputListener(catcher, name)
        end
    end
end

return Input
