-- Send money: eddies to a partner, from the partner menu (the phone's Contacts)
-- or from this tweak's section of the CET window.
-- The recipient needs only NightCoop; this mod is the sender's side.

local PartnerMenu = require("core/partnermenu")
local Menu = require("tweaks/sendmoney/menu")
local Window = require("tweaks/sendmoney/window")

local Tweak = { name = "Send money" }

function Tweak.Init()
    PartnerMenu.Add(Menu.Entry)
end

Tweak.DrawOverlay = Window.Draw
Tweak.OverlayOpened = Window.Opened
Tweak.OverlayClosed = Window.Closed

-- GetMod("NightCoopTweaks").Send(peerId, amount) from the CET console
Tweak.api = {
    Send = Window.Send,
}

return Tweak
