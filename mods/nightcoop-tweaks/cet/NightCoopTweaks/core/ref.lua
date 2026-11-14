-- Comparing game objects, and holding one without keeping it alive.

local Ref = {}

-- Whether two handles point at the same game object (Lua's == compares the handles).
function Ref.Same(a, b)
    return Game["OperatorEqual;IScriptableIScriptable;Bool"](a, b)
end

-- Whether two EntityIDs name the same entity.
function Ref.SameId(a, b)
    return Game["OperatorEqual;EntityIDEntityID;Bool"](a, b)
end

-- A slot for one game object that doesn't keep it alive, so a controller or a
-- player from before a save load reads back as nil. Create it in an Init.
function Ref.WeakSlot()
    local map = inkScriptWeakHashMap.new()
    map:Insert(0, nil)
    return {
        Get = function() return map:Get(0) end,
        Set = function(object) map:Set(0, object) end,
    }
end

return Ref
