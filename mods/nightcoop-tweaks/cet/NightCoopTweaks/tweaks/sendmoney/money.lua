-- Eddies: the balance, how amounts read, and sending them through NightCoop.

local NightCoop = require("core/nightcoop")

local Money = {}

local RECORD = "Items.money"
local MAX_PER_TRANSFER = 9999 -- NightCoop refuses a quantity outside 1..9999

function Money.Thousands(n)
    local digits = tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (digits:gsub("^,", ""))
end

function Money.Eddies(n)
    return Money.Thousands(n) .. " eddies"
end

function Money.Balance()
    local player = Game.GetPlayer()
    if not player then
        return 0
    end
    return Game.GetTransactionSystem():GetItemQuantity(player, MarketSystem.Money())
end

-- Sends `total` eddies to `peer` in transfers of at most MAX_PER_TRANSFER.
-- Returns how much was requested, plus NightCoop's reply when it stopped early.
local function send(peer, total)
    local requested = 0
    while requested < total do
        local chunk = math.min(total - requested, MAX_PER_TRANSFER)
        local reply = NightCoop.GiveItem(RECORD, chunk, peer)
        if not reply then
            return requested, "NightCoop is not loaded"
        end
        if not reply:find("requested", 1, true) then
            return requested, reply
        end
        requested = requested + chunk
    end
    return requested
end

-- Sends after checking the balance, and says what happened in one line.
-- Returns how much was requested, the summary line, and whether it all went.
function Money.Send(peer, amount)
    amount = math.floor(tonumber(amount) or 0)
    -- NightCoop checks each transfer against the balance on its own, but the
    -- debits land later, so a split send could pass the check more than it should.
    local balance = Money.Balance()
    if amount <= 0 or amount > balance then
        return 0, "Not sent: " .. Money.Eddies(amount) .. " asked, you have " .. Money.Eddies(balance), false
    end
    local label = NightCoop.PeerLabel(peer)
    local requested, problem = send(peer, amount)
    if not problem then
        return requested, "Sent " .. Money.Eddies(requested) .. " to " .. label, true
    elseif requested > 0 then
        return requested, "Sent " .. Money.Eddies(requested) .. " of " .. Money.Eddies(amount) .. " to " .. label .. ", then: " .. problem, false
    end
    return 0, "Not sent: " .. problem, false
end

return Money
