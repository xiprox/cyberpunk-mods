-- The Headset section of the game's Settings menu, through Native Settings, and the sounds that confirm a change of mode.

local TAB = "/headset"
local MAIN = TAB .. "/main"

-- The game's own UI sounds, a different one for each mode, so you can tell which you've landed on.
-- Only ones the game itself plays through the audio system's Play: ui_generic_set_14_positive, which it only plays on a device, stayed silent.
local CUE_SOUNDS = { "ui_hacking_access_granted", "ui_menu_map_pin_off", "ui_menu_map_pin_on" } -- Passthrough, Hearing Protection, Noise Cancelling

local native
local menu

local function setting(key, fallback)
    return native.GetSetting(key, fallback)
end

local function store(key)
    return function(value)
        native.SetSetting(key, tostring(value))
    end
end

local function buildMenu()
    menu.addTab(TAB, "Headset")
    menu.addSubcategory(MAIN, "Headset")
    menu.addKeyBinding(MAIN, "Headset key", "Tap: the next mode. Hold: choose a mode. Passthrough is as if it weren't there. Active Hearing Protection lets you hear the world through its microphones and turns it down the moment a gun or a blast goes off. Active Noise Cancellation shuts the world out, a car's radio included.",
        setting("key_headset", "IK_Comma"), "IK_Comma", false, store("key_headset"))
end

registerForEvent("onInit", function()
    native = HeadsetNative
    if not native then
        print("[Headset] The plugin isn't loaded, so there are no headset settings.")
        return
    end
    menu = GetMod("nativeSettings")
    if not menu then
        print("[Headset] Native Settings isn't installed, so the headset settings have no menu.")
        return
    end
    buildMenu()
end)

registerForEvent("onUpdate", function()
    if not native then
        return
    end
    local cue = native.TakeCue()
    local wheel = native.TakeWheelEvent()
    if not Game.GetPlayer() then
        return
    end
    if cue and cue > 0 and CUE_SOUNDS[cue] then
        HeadsetSounds.Play(CName.new(CUE_SOUNDS[cue]))
    end
    if wheel == 1 then
        HeadsetWheelHost.Open()
    elseif wheel == 2 then
        HeadsetWheelHost.Close()
    end
    HeadsetHud.Tick()
end)

registerForEvent("onOverlayOpen", function()
    if native then
        native.SetOverlayOpen(true)
    end
end)

registerForEvent("onOverlayClose", function()
    if native then
        native.SetOverlayOpen(false)
    end
end)
