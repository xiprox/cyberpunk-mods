-- The Headset section of the game's Settings menu, through Native Settings, the sounds that confirm a change of mode, and each
-- frame's tick for the Radioport and the HUD.

local TAB = "/headset"
local MAIN = TAB .. "/main"

-- The game's own UI sounds, a different one for each mode, so you can tell which you've landed on.
-- Only ones the game itself plays through the audio system's Play: ui_generic_set_14_positive, which it only plays on a device, stayed silent.
local CUE_SOUNDS = { "ui_hacking_access_granted", "ui_menu_map_pin_off", "ui_menu_map_pin_on" } -- Passthrough, Hearing Protection, Noise Cancelling

-- "Mode with the Radioport" lists Noise Cancellation first, as the default, and stores each entry's mode number for
-- HeadsetRadioport.reds, which has the same default, so change both together.
local RADIOPORT_MODE_NAMES = { "Active Noise Cancellation", "Active Hearing Protection" }
local RADIOPORT_MODES = { 2, 1 }

local native
local menu

local function setting(key, fallback)
    return native.GetSetting(key, fallback)
end

local function settingOn(key, fallback)
    return setting(key, fallback and "1" or "0") == "1"
end

local function store(key)
    return function(value)
        if type(value) == "boolean" then
            value = value and "1" or "0"
        end
        native.SetSetting(key, tostring(value))
    end
end

local function radioportModeIndex()
    local mode = tonumber(setting("radioport_mode", "2"))
    for index, each in ipairs(RADIOPORT_MODES) do
        if each == mode then
            return index
        end
    end
    return 1
end

local function buildMenu()
    menu.addTab(TAB, "Headset")
    menu.addSubcategory(MAIN, "Headset")
    menu.addKeyBinding(MAIN, "Headset key", "Tap: the next mode. Hold: choose a mode. Passthrough is as if it weren't there. Active Hearing Protection lets you hear the world through its microphones and turns it down the moment a gun or a blast goes off. Active Noise Cancellation shuts the world out, a car's radio included.",
        setting("key_headset", "IK_Comma"), "IK_Comma", false, store("key_headset"))
    menu.addSwitch(MAIN, "Radioport puts the headset on", "Turning the Radioport on while in Passthrough switches the headset to the mode below, and turning it off switches back to Passthrough. If the headset was already in a mode, the Radioport leaves it alone.",
        settingOn("radioport_puts_on", false), false, store("radioport_puts_on"))
    menu.addSelectorString(MAIN, "Mode with the Radioport", "The mode turning the Radioport on switches the headset to.",
        RADIOPORT_MODE_NAMES, radioportModeIndex(), 1, function(index)
            native.SetSetting("radioport_mode", tostring(RADIOPORT_MODES[index]))
        end)
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
    HeadsetRadioport.Tick()
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
