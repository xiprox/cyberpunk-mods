-- The Voice section of the game's Settings menu, through Native Settings. Everything is stored by the plugin, so this
-- file holds no state of its own beyond what the menu needs.

local TAB = "/nightcoopvoice"
local MIC = TAB .. "/mic"
local KEYS = TAB .. "/keys"
local HEARING = TAB .. "/hearing"
local CONNECTION = TAB .. "/connection"
local PLAYERS = TAB .. "/players"
local PLAYER_POLL_SECONDS = 1.0
local PLACEHOLDER_WAIT_SECONDS = 20.0

local nativeVoice
local menu
local micOption
local outputOption
local playersSeen = {}
local placeholderWaits = {}
local playerTimer = 0.0

local function setting(key, fallback)
    return nativeVoice.GetSetting(key, fallback)
end

local function settingNumber(key, fallback)
    return tonumber(setting(key, tostring(fallback))) or fallback
end

local function settingOn(key, fallback)
    return setting(key, fallback and "1" or "0") == "1"
end

local function store(key)
    return function(value)
        if type(value) == "boolean" then
            value = value and "1" or "0"
        end
        nativeVoice.SetSetting(key, tostring(value))
    end
end

-- The first entry stands for the system default, whose stored id is empty.
local function deviceChoices(capture, key)
    local names = { "System default" }
    local ids = { "" }
    local current = setting(key, "")
    local selected = 1
    local count = nativeVoice.DeviceCount(capture)
    for i = 0, count - 1 do
        names[#names + 1] = nativeVoice.DeviceName(capture, i)
        ids[#ids + 1] = nativeVoice.DeviceId(capture, i)
        if ids[#ids] == current then
            selected = #ids
        end
    end
    return names, ids, selected
end

local function addDeviceOption(path, label, description, capture, key)
    local names, ids, selected = deviceChoices(capture, key)
    return menu.addSelectorString(path, label, description, names, selected, 1, function(index)
        nativeVoice.SetSetting(key, ids[index] or "")
    end, 1)
end

local function rebuildDevices()
    nativeVoice.RefreshDevices()
    menu.removeOption(micOption)
    menu.removeOption(outputOption)
    micOption = addDeviceOption(MIC, "Microphone", "Which microphone your voice comes from.", true, "mic_device")
    outputOption = addDeviceOption(HEARING, "Output", "Where you hear other players.", false, "output_device")
end

local function buildMenu()
    menu.addTab(TAB, "Voice", function()
        nativeVoice.SetTest(0) -- hear-yourself never outlives the menu
    end)

    menu.addSubcategory(MIC, "Microphone")
    micOption = addDeviceOption(MIC, "Microphone", "Which microphone your voice comes from.", true, "mic_device")
    menu.addRangeInt(MIC, "Voice gate", "How sure the mod must be that it's speech before sending. Higher blocks more background sound, lower cuts off fewer quiet words.",
        0, 100, 5, settingNumber("gate", 60), 60, store("gate"))
    menu.addSwitch(MIC, "Noise removal", "Removes fans, keyboards and other steady noise from your voice.",
        settingOn("noise_removal", true), true, store("noise_removal"))
    menu.addSwitch(MIC, "Echo cancellation", "Only for playing on speakers: removes the game's sound from your mic. Leave it off with a headset.",
        settingOn("echo_cancel", false), false, store("echo_cancel"))
    menu.addSelectorString(MIC, "Hear yourself", "A test of your mic through the mod. It switches off when you leave this menu. Use a headset, or speakers will feed back.",
        { "Off", "Clean", "Through the radio" }, 1, 1, function(index)
            nativeVoice.SetTest(index - 1)
        end)
    menu.addButton(MIC, "Refresh devices", "Plugged something in? This finds it.", "Refresh", 45, rebuildDevices)

    menu.addSubcategory(KEYS, "Keys")
    menu.addKeyBinding(KEYS, "Mute", "Silences your mic everywhere, nearby and on the radio.",
        setting("key_mute", "IK_Mouse4"), "IK_Mouse4", false, store("key_mute"))
    menu.addKeyBinding(KEYS, "Radio mic", "Hold to talk on the radio. In combat, your voice goes on the radio without it.",
        setting("key_radio", "IK_Mouse5"), "IK_Mouse5", false, store("key_radio"))

    menu.addSubcategory(HEARING, "Hearing")
    outputOption = addDeviceOption(HEARING, "Output", "Where you hear other players.", false, "output_device")
    menu.addRangeInt(HEARING, "Voice level", "Voices set their own level against the game and every mic evens itself out, so this is only for taste. In dB; 0 is the automatic level.",
        -12, 12, 1, settingNumber("voice_level", 0), 0, store("voice_level"))
    menu.addSwitch(HEARING, "Headphones", "Places nearby voices around your head, which only works in headphones. Turn it off for speakers.",
        settingOn("headphones", true), true, store("headphones"))
    menu.addSwitch(HEARING, "Show the voice display", "The corner display of your mic, the radio and who's talking.",
        settingOn("hud", true), true, store("hud"))

    menu.addSubcategory(CONNECTION, "Connection")
    local relayChoices = { "needed", "always" }
    menu.addSelectorString(CONNECTION, "Relay", "How voice travels. When needed: straight between players, and over NightCoop only while there's no direct link. Always: over NightCoop with everyone, never straight; it comes a little later, goes by way of the host, and stops in loading screens.",
        { "When needed", "Always" }, setting("relay", "needed") == "always" and 2 or 1, 1, function(index)
            nativeVoice.SetSetting("relay", relayChoices[index] or "needed")
        end)

    menu.addSubcategory(PLAYERS, "Players")
end

-- NightCoop calls a player "Player 0" until their nickname arrives. A row made under that name would be left behind, so
-- it waits, and only shows if the nickname never comes.
local function nameIsSettled(name)
    if not name:match("^Player %d+$") then
        return true
    end
    placeholderWaits[name] = (placeholderWaits[name] or 0.0) + PLAYER_POLL_SECONDS
    return placeholderWaits[name] >= PLACEHOLDER_WAIT_SECONDS
end

-- A row per player, added the first time they show up this run and kept through their rejoins.
local function updatePlayers()
    local count = nativeVoice.PeerCount()
    for i = 0, count - 1 do
        local name = nativeVoice.PeerNameAt(i)
        if name ~= "" and not playersSeen[name] and nameIsSettled(name) then
            playersSeen[name] = true
            local key = "peer." .. name .. ".mute"
            menu.addSwitch(PLAYERS, "Mute " .. name, "Stops you hearing this player. They aren't told.",
                settingOn(key, false), false, store(key))
        end
    end
end

registerForEvent("onInit", function()
    nativeVoice = NightCoopVoiceNative
    if not nativeVoice then
        print("[NightCoopVoice] The plugin isn't loaded, so there are no voice settings.")
        return
    end
    menu = GetMod("nativeSettings")
    if not menu then
        print("[NightCoopVoice] Native Settings isn't installed, so the voice settings have no menu.")
        return
    end
    buildMenu()
end)

registerForEvent("onUpdate", function(deltaTime)
    if not nativeVoice or not menu then
        return
    end
    playerTimer = playerTimer + deltaTime
    if playerTimer >= PLAYER_POLL_SECONDS then
        playerTimer = 0.0
        updatePlayers()
    end
end)

registerForEvent("onOverlayOpen", function()
    if nativeVoice then
        nativeVoice.SetOverlayOpen(true)
    end
end)

registerForEvent("onOverlayClose", function()
    if nativeVoice then
        nativeVoice.SetOverlayOpen(false)
    end
end)
