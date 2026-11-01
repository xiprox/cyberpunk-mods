-- "Send money" in the partner menu: preset amounts or the game's quantity
-- slider, then a confirmation for a preset. The transfer shows as the game's
-- progress bar with the eddies look, as in the story's payments.

local NightCoop = require("core/nightcoop")
local Notify = require("core/notify")
local ProgressBar = require("core/progressbar")
local Quantity = require("core/quantity")
local Money = require("tweaks/sendmoney/money")

local Menu = {}

local PRESETS = { 1000, 5000, 10000 }
local BAR_SECONDS = 1.5   -- the bar fills over this at least, however fast the host answers
local BAR_TIMEOUT = 8.0   -- seconds to wait for the host to take the money before the bar fails

local showAmounts, showConfirm, openSlider

-- Sends, and runs the bar until our balance shows the host took the money
-- (NightCoop debits the sender once the host accepts the transfer).
local function sendNow(peer, amount)
    local before = Money.Balance()
    local requested, line, complete = Money.Send(peer, amount)
    spdlog.info(line)

    local label = NightCoop.PeerLabel(peer)
    local detail = Money.Thousands(amount) .. " eddies to " .. label
    if requested > 0 and not complete then
        detail = Money.Thousands(requested) .. " of " .. Money.Thousands(amount) .. " eddies to " .. label
    end
    local reason = line:gsub("^Not sent: ", ""):gsub("^inventory: ", "")

    local shown = ProgressBar.Start({
        header = "Transferring eddies",
        detail = detail,
        done = "Transfer complete",
        failed = "Transfer failed",
        timeoutText = "No answer from the host",
        money = true,
        minSeconds = BAR_SECONDS,
        timeout = BAR_TIMEOUT,
        check = function()
            if requested == 0 then
                return "failed"
            end
            if Money.Balance() <= before - requested then
                return "done"
            end
            return nil
        end,
    })
    if not shown then
        Notify.Toast(line) -- a quest's bar is up
    elseif requested == 0 then
        ProgressBar.SetDetail(reason)
    end
end

function showAmounts(menu)
    local balance = Money.Balance()
    local labels, picks = {}, {}
    local function add(label, pick)
        table.insert(labels, label)
        table.insert(picks, pick)
    end
    for _, preset in ipairs(PRESETS) do
        if preset <= balance then
            add(Money.Thousands(preset), function() showConfirm(menu, preset) end)
        end
    end
    if balance > 0 then
        add("All (" .. Money.Thousands(balance) .. ")", function() showConfirm(menu, balance) end)
    end
    if balance > 1 then -- the slider needs a range
        add("Custom amount...", function() openSlider(menu, balance) end)
    end
    add("Back", function() menu.Back() end)

    local title = balance > 0 and ("Send money - you have " .. Money.Thousands(balance)) or "Send money - you have no eddies"
    menu.Show(title, labels, function(choice)
        picks[choice]()
    end)
end

function showConfirm(menu, amount)
    local label = NightCoop.PeerLabel(menu.peer)
    menu.Show(label, { "Send " .. Money.Eddies(amount) .. " to " .. label, "Back" }, function(choice)
        if choice == 1 then
            menu.Close()
            sendNow(menu.peer, amount)
        else
            showAmounts(menu)
        end
    end)
end

-- The slider's Send button sends straight away; Cancel goes back to the amounts.
function openSlider(menu, balance)
    menu.Await()
    local opened = Quantity.Open({
        title = "Send eddies to " .. NightCoop.PeerLabel(menu.peer),
        max = balance,
        button = "Send",
        item = MarketSystem.Money(),
        onClose = function(amount)
            if amount then
                menu.Close()
                sendNow(menu.peer, amount)
            else
                showAmounts(menu)
            end
        end,
    })
    if not opened then
        Notify.Toast("The amount slider couldn't open here")
        showAmounts(menu)
    end
end

-- The partner menu's entry.
Menu.Entry = {
    label = "Send money",
    open = showAmounts,
}

return Menu
