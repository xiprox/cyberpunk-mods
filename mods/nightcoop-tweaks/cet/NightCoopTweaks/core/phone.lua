-- Partners in the phone's Contacts. Calling one (F, or Enter, on them) closes
-- the phone and opens their partner menu, wherever they are, instead of dialing.
--
-- NewHudPhoneGameController.SetScreenType fills the Contacts tab with the
-- journal's contacts as ContactData; ours are ContactData too, added by filling
-- the list again after it, and told apart by their id. (The function that
-- builds the list, MessengerUtils.GetCallableAndNonEmptyContacts, is a script
-- static, which the game keeps as a global, out of CET's Override's reach.)
-- Calling goes through NewHudPhoneGameController.CallContact before the game
-- makes a holocall of it, so NightCoop's call sharing never sees one. The
-- phone's Call key ('click') isn't bound to Enter, so Enter on a partner is
-- read here from the actions Enter does send.

local Input = require("core/input")
local Log = require("core/log")
local NightCoop = require("core/nightcoop")
local PartnerMenu = require("core/partnermenu")
local Ref = require("core/ref")

local Phone = {}

local ID_PREFIX = "nightcoop_peer_"
local HASH_BASE = -1000 -- our contacts' hashes, clear of the journal's
local IK_ENTER = 13
-- Enter sends these (F does too, which the phone's own Call key covers)
local ENTER_ACTIONS = { "UI_Apply", "ChoiceApply" }
local REPEAT_SECONDS = 0.3 -- one Enter comes as both actions

local seen = { fills = 0 } -- for diagnostics: fills, tab, at, added, calls
local phoneSlot            -- the phone controller, from its last SetScreenType
local lastCall = -math.huge

local function partnerContacts()
    local session = NightCoop.Session()
    if not (session and session.connected) then
        return {}
    end
    local now = Game.GetTimeSystem():GetGameTime()
    local contacts = {}
    for _, remote in ipairs(NightCoop.Remotes(session.peerId)) do
        local contact = NewObject("ContactData")
        contact.id = ID_PREFIX .. remote.id
        contact.contactId = contact.id
        contact.localizedName = NightCoop.PeerLabel(remote.id)
        contact.hasValidTitle = true
        contact.localizedPreview = "NightCoop partner"
        contact.type = MessengerContactType.Contact
        contact.isCallable = true
        contact.hash = HASH_BASE - remote.id
        contact.timeStamp = now
        table.insert(contacts, contact)
    end
    return contacts
end

-- The peer id of the selected contact, when it's one of ours.
local function selectedPartner(phone)
    local list = phone.contactListLogicController
    local contact = list and list:GetSelectedContactData()
    if not contact or type(contact.id) ~= "string" then
        return nil
    end
    return tonumber(contact.id:match("^" .. ID_PREFIX .. "(%d+)$"))
end

local function enumNumber(value)
    if type(value) == "number" then
        return value
    end
    return EnumInt(value)
end

-- After the phone fills a tab: on the Contacts tab, adds the partners at its end.
local function addPartners(phone, screen)
    seen.fills = seen.fills + 1
    seen.at = os.clock()
    local contacts = enumNumber(screen) == enumNumber(PhoneScreenType.Contacts)
    seen.tab = contacts and "Contacts" or "Unread"
    if not contacts then
        return
    end
    seen.added = 0
    local list = phone.contactListLogicController
    if not list then
        Log.Problem("phone: the Contacts tab has no list to add partners to")
        return
    end
    local partners = partnerContacts()
    if #partners == 0 then
        return
    end
    -- Items appended to the filled list didn't show (user), so it's filled
    -- again, the game's contacts and ours, the way SetScreenType filled it.
    local contacts = list.dataSource:GetArray()
    for _, contact in ipairs(partners) do
        table.insert(contacts, contact)
    end
    list:PopulateListData(contacts)
    seen.added = #partners
end

-- Closes the phone and opens the partner's menu in place of a call.
local function callPartner(phone, peer)
    lastCall = os.clock()
    seen.calls = (seen.calls or 0) + 1
    phone:CloseContactList()
    PartnerMenu.OpenFor(peer)
end

local function phoneOpen()
    local defs = Game.GetAllBlackboardDefs()
    return Game.GetBlackboardSystem():Get(defs.UI_ComDevice):GetBool(defs.UI_ComDevice.ContactsActive)
end

-- Enter on a partner in the Contacts tab calls them, as F does.
local function onEnter(name, kind, action)
    if kind ~= "BUTTON_PRESSED" or os.clock() - lastCall < REPEAT_SECONDS then
        return
    end
    if not Input.HasKey(action, IK_ENTER) or not phoneOpen() then
        return
    end
    local phone = phoneSlot.Get()
    if not phone or phone.threadsVisible or enumNumber(phone.screenType) ~= enumNumber(PhoneScreenType.Contacts) then
        return
    end
    local peer = selectedPartner(phone)
    if peer then
        seen.enter = (seen.enter or 0) + 1
        callPartner(phone, peer)
    end
end

-- One line on what the phone hooks have seen, for diagnostics.
function Phone.Explain()
    if seen.fills == 0 then
        return "Phone: no tab filled since the mod loaded (open the phone)"
    end
    local line = string.format("Phone: tabs filled %d time(s), last %s %.0f s ago", seen.fills, seen.tab, os.clock() - seen.at)
    if seen.added then
        line = line .. string.format("; partners added to Contacts last time: %d", seen.added)
    end
    if seen.calls then
        line = line .. string.format("; partner calls: %d (%d by Enter)", seen.calls, seen.enter or 0)
    end
    return line
end

function Phone.Init()
    phoneSlot = Ref.WeakSlot()
    ObserveAfter("NewHudPhoneGameController", "SetScreenType", function(self, screen)
        phoneSlot.Set(self)
        local ok, err = pcall(addPartners, self, screen)
        if not ok then
            Log.Problem("phone: partners not added to the contacts: " .. tostring(err))
        end
    end)

    Override("NewHudPhoneGameController", "CallContact", function(self, wrapped)
        local ok, peer = pcall(selectedPartner, self)
        if not ok then
            Log.Problem("phone: couldn't read the selected contact: " .. tostring(peer))
        end
        if not ok or not peer then
            return wrapped()
        end
        callPartner(self, peer)
    end)

    Input.Listen(ENTER_ACTIONS, onEnter)
end

return Phone
