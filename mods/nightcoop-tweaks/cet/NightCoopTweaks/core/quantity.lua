-- The game's own quantity popup (the slider it shows for dropping or selling a
-- stack), opened in the world to pick a number.
--
-- The popup stays up while its notification token is held and goes away when
-- the token is released, as in BackpackMainGameController.OnQuantityPickerPopupClosed.
-- Its close callback is caught by a detached gameNotificationsTest (a sample
-- class the game never uses; its OnResponse only clears its own field).

local Ref = require("core/ref")

local Quantity = {}

local WIDGET = "base\\gameplay\\gui\\widgets\\notifications\\item_quantity_picker.inkwidget"

local catcher
local dialogController -- the game's dialog widget controller, a fallback to show from
local open = nil       -- { token, data, item, title, button, onClose(amount or nil) }

-- A game controller on the HUD layer to show the popup from (Codeware's
-- inkSystem), PopupsManager first, as it shows the game's own in-world popups.
local function hudController()
    local ok, found = pcall(function()
        local layer = Game.GetInkSystem():GetLayer(CName.new("inkHUDLayer"))
        for _, controller in ipairs(layer:GetGameControllers()) do
            if controller:IsA("PopupsManager") then
                return controller
            end
        end
        return layer:GetGameController()
    end)
    if ok and found then
        return found
    end
    return dialogController and dialogController.Get() or nil
end

-- The player's stack of `itemID`, for the popup's icon and rarity bar.
local function inventoryItem(player, itemID)
    local ok, item = pcall(function()
        local itemData = Game.GetTransactionSystem():GetItemData(player, itemID)
        return UIInventoryItem.Make(player, itemData)
    end)
    if ok then
        return item
    end
    return nil
end

function Quantity.IsOpen()
    return open ~= nil
end

-- Opens the slider from 1 to `options.max`, headed `options.title`, its OK button
-- saying `options.button`, showing the player's `options.item` (an ItemID) if
-- given. `options.onClose(amount)` gets the amount, or nil when cancelled.
-- Returns false when there's no HUD to show it on, or one is already open.
function Quantity.Open(options)
    local player = Game.GetPlayer()
    local controller = hudController()
    if not player or not controller or open or options.max < 2 then
        return false
    end

    local item = options.item and inventoryItem(player, options.item)
    local data = QuantityPickerPopupData.new()
    data.notificationName = CName.new(WIDGET)
    data.queueName = CName.new("modal_popup")
    data.isBlocking = true
    data.useCursor = true
    data.maxValue = options.max
    data.actionType = QuantityPickerActionType.TransferToPlayer -- no price shown
    if item then
        data.inventoryItem = item -- a weak ref in the data; `open.item` keeps it alive
    end

    -- Set before showing: the popup may initialize (and run SetData) right away.
    open = { data = data, item = item, title = options.title, button = options.button, onClose = options.onClose }
    local token = controller:ShowGameNotification(data)
    if not token then
        open = nil
        return false
    end
    token:RegisterListener(catcher, CName.new("OnResponse"))
    open.token = token
    return true
end

local function onResponse(closeData)
    local done = open
    open = nil
    -- Releasing the token is what takes the popup off the screen.
    done.token = nil
    collectgarbage()

    local amount
    if closeData and closeData:IsA("QuantityPickerPopupCloseData") and closeData.choosenQuantity > 0 then
        amount = closeData.choosenQuantity
    end
    spdlog.info("quantity popup closed: " .. (amount and ("amount " .. amount) or "cancelled"))
    done.onClose(amount)
end

function Quantity.Init()
    catcher = NewObject("gameNotificationsTest")
    -- Our choice lists set the selected index, so this is known before a list item can open the popup.
    dialogController = Ref.WeakSlot()
    ObserveAfter("dialogWidgetGameController", "OnDialogsSelectIndex", function(self)
        dialogController.Set(self)
    end)
    ObserveAfter("gameNotificationsTest", "OnResponse", function(self, closeData)
        if open and Ref.Same(self, catcher) then
            onResponse(closeData)
        end
    end)
    -- The popup shows the item's name and the widget's own button text.
    ObserveAfter("ItemQuantityPickerController", "SetData", function(self)
        if open and self.data and Ref.Same(self.data, open.data) then
            inkTextRef.SetText(self.itemNameText, open.title)
            if open.button then
                inkTextRef.SetText(self.buttonOkText, open.button)
            end
        end
    end)
end

function Quantity.Shutdown()
    if open then
        open.token = nil
        open = nil
        collectgarbage()
    end
end

return Quantity
