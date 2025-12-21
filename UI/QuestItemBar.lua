-- Guda Quest Item Bar
-- Displays usable quest items in a separate bar

local addon = Guda
local QuestItemBar = addon.Modules.QuestItemBar
if not QuestItemBar then
    -- Fallback if Init.lua changed
    QuestItemBar = {}
    addon.Modules.QuestItemBar = QuestItemBar
end

local buttons = {}
local questItems = {}

-- Create a hidden tooltip for scanning
local scanTooltip
local function GetScanTooltip()
    if not scanTooltip then
        scanTooltip = CreateFrame("GameTooltip", "Guda_QuestBarScanTooltip", nil, "GameTooltipTemplate")
        scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    end
    return scanTooltip
end

-- Check if an item is usable by scanning its tooltip for "Use:"
local function IsItemUsable(bagID, slotID)
    if not bagID or not slotID then return false end

    local tooltip = GetScanTooltip()
    tooltip:ClearLines()
    tooltip:SetBagItem(bagID, slotID)

    for i = 1, tooltip:NumLines() do
        local line = getglobal("Guda_QuestBarScanTooltipTextLeft" .. i)
        if line then
            local text = line:GetText()
            if text and (string.find(text, "Use:") or string.find(text, "Starts a Quest")) then
                return true
            end
        end
    end
    return false
end

-- Scan bags for quest items
function QuestItemBar:ScanForQuestItems()
    questItems = {}
    
    -- Scan backpack and 4 bags
    for bagID = 0, 4 do
        local numSlots = GetContainerNumSlots(bagID)
        for slotID = 1, numSlots do
            local texture, count = GetContainerItemInfo(bagID, slotID)
            if texture then
                -- Re-use IsQuestItem logic from ItemButton.lua if accessible, 
                -- or implement a simple check here since we're in a separate module.
                -- UI\ItemButton.lua defines IsQuestItem locally, so we'll implement a similar check.
                
                local isQuest, isStarter = self:IsQuestItem(bagID, slotID)
                if isQuest and IsItemUsable(bagID, slotID) then
                    table.insert(questItems, {
                        bagID = bagID,
                        slotID = slotID,
                        texture = texture,
                        count = count
                    })
                end
            end
        end
    end
end

-- Local implementation of IsQuestItem (similar to the one in ItemButton.lua)
function QuestItemBar:IsQuestItem(bagID, slotID)
    local tooltip = GetScanTooltip()
    tooltip:ClearLines()
    tooltip:SetBagItem(bagID, slotID)

    local isQuestItem = false
    local isQuestStarter = false

    for i = 1, tooltip:NumLines() do
        local line = getglobal("Guda_QuestBarScanTooltipTextLeft" .. i)
        if line then
            local text = line:GetText()
            if text then
                if string.find(text, "Quest Starter") or
                   string.find(text, "This Item Begins a Quest") or
                   string.find(text, "Use: Starts a Quest") then
                    isQuestItem = true
                    isQuestStarter = true
                    break
                elseif string.find(text, "Quest Item") then
                    isQuestItem = true
                end
            end
        end
    end

    if not isQuestItem then
        local link = GetContainerItemLink(bagID, slotID)
        if link and addon.Modules.Utils and addon.Modules.Utils.ExtractItemID and addon.Modules.Utils.GetItemInfoSafe then
            local itemID = addon.Modules.Utils:ExtractItemID(link)
            if itemID then
                local _, _, _, _, itemCategory, itemType = addon.Modules.Utils:GetItemInfoSafe(itemID)
                if itemCategory == "Quest" or itemType == "Quest" then
                    isQuestItem = true
                end
            end
        end
    end

    return isQuestItem, isQuestStarter
end

function QuestItemBar:PinItem(itemID)
    if not itemID then return end
    local pins = addon.Modules.DB:GetSetting("questBarPinnedItems") or {}
    
    -- Check if already pinned
    for i = 1, 2 do
        if pins[i] == itemID then return end
    end
    
    -- Find first empty slot
    for i = 1, 2 do
        if not pins[i] then
            pins[i] = itemID
            addon.Modules.DB:SetSetting("questBarPinnedItems", pins)
            self:Update()
            return true
        end
    end
    
    -- Replace first slot if both are full
    pins[1] = itemID
    addon.Modules.DB:SetSetting("questBarPinnedItems", pins)
    self:Update()
    return true
end

-- Update the bar buttons
function QuestItemBar:Update()
    local showQuestBar = addon.Modules.DB:GetSetting("showQuestBar")
    local frame = Guda_QuestItemBar
    
    if showQuestBar == false then
        if frame then frame:Hide() end
        return
    end
    
    if not frame then return end
    frame:Show()

    self:ScanForQuestItems()
    
    local pinnedItems = addon.Modules.DB:GetSetting("questBarPinnedItems") or {}
    local buttonSize = 37
    local spacing = 2
    local xOffset = 5
    
    -- Used to keep track of which bag items are already displayed
    local usedBagSlots = {}

    for i = 1, 2 do
        local index = i
        local button = buttons[i]
        if not button then
            button = CreateFrame("Button", "Guda_QuestItemBarButton" .. i, frame, "Guda_ItemButtonTemplate")
            table.insert(buttons, button)
            
            -- Set up the button once
            button:RegisterForDrag("LeftButton")
            button:SetScript("OnDragStart", function()
                if IsShiftKeyDown() then
                    this:GetParent():StartMoving()
                    this:GetParent().isMoving = true
                end
            end)
            button:SetScript("OnDragStop", function()
                local parent = this:GetParent()
                if parent.isMoving then
                    parent:StopMovingOrSizing()
                    parent.isMoving = false
                    local point, _, relativePoint, x, y = parent:GetPoint()
                    addon.Modules.DB:SetSetting("questBarPosition", {point = point, relativePoint = relativePoint, x = x, y = y})
                end
            end)
        end

        local itemToDisplay = nil
        
        -- 1. Try to find the pinned item for this slot
        local pinnedID = pinnedItems[i]
        if pinnedID then
            -- Find this item in bags
            for _, item in ipairs(questItems) do
                local itemID = addon.Modules.Utils:ExtractItemID(GetContainerItemLink(item.bagID, item.slotID))
                if itemID == pinnedID and not usedBagSlots[item.bagID .. ":" .. item.slotID] then
                    itemToDisplay = item
                    usedBagSlots[item.bagID .. ":" .. item.slotID] = true
                    break
                end
            end
        end
        
        -- 2. If no pinned item or pinned item not found, auto-fill
        if not itemToDisplay then
            for _, item in ipairs(questItems) do
                if not usedBagSlots[item.bagID .. ":" .. item.slotID] then
                    itemToDisplay = item
                    usedBagSlots[item.bagID .. ":" .. item.slotID] = true
                    break
                end
            end
        end

        if itemToDisplay then
            button.bagID = itemToDisplay.bagID
            button.slotID = itemToDisplay.slotID
            button.hasItem = true
            button.itemData = { link = GetContainerItemLink(itemToDisplay.bagID, itemToDisplay.slotID) }
            
            local icon = getglobal(button:GetName() .. "IconTexture")
            icon:SetTexture(itemToDisplay.texture)
            icon:SetVertexColor(1.0, 1.0, 1.0, 1.0)
            
            local countText = getglobal(button:GetName() .. "Count")
            if itemToDisplay.count > 1 then
                countText:SetText(itemToDisplay.count)
                countText:Show()
            else
                countText:Hide()
            end
            
            button:SetScript("OnClick", function()
                if arg1 == "LeftButton" then
                    if CursorHasItem() then
                        -- Try to pin item on cursor
                        local tooltip = GetScanTooltip()
                        tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
                        tooltip:SetCursorItem()
                        local link = nil
                        -- In 1.12, getting link from cursor is hard.
                        -- We'll rely on Alt-Click from bags for pinning.
                    end

                    if IsShiftKeyDown() then
                        local link = GetContainerItemLink(this.bagID, this.slotID)
                        if link then HandleModifiedItemClick(link) end
                    else
                        UseContainerItem(this.bagID, this.slotID)
                    end
                elseif arg1 == "RightButton" then
                    if IsControlKeyDown() then
                        -- Clear pin for this slot
                        local pins = addon.Modules.DB:GetSetting("questBarPinnedItems") or {}
                        pins[index] = nil
                        addon.Modules.DB:SetSetting("questBarPinnedItems", pins)
                        QuestItemBar:Update()
                    else
                        UseContainerItem(this.bagID, this.slotID)
                    end
                end
            end)
            
            button:Show()
        else
            -- Empty slot
            button.hasItem = false
            button.bagID = nil
            button.slotID = nil
            
            local icon = getglobal(button:GetName() .. "IconTexture")
            icon:SetTexture("Interface\\Buttons\\UI-EmptySlot")
            icon:SetVertexColor(0.5, 0.5, 0.5, 0.5)
            
            local countText = getglobal(button:GetName() .. "Count")
            countText:Hide()
            
            button:SetScript("OnClick", function()
                if arg1 == "LeftButton" then
                    if CursorHasItem() then
                        -- Pinning from cursor is hard in 1.12 without hooks.
                    end
                elseif arg1 == "RightButton" then
                    if IsControlKeyDown() then
                        -- Clear pin for this slot
                        local pins = addon.Modules.DB:GetSetting("questBarPinnedItems") or {}
                        pins[index] = nil
                        addon.Modules.DB:SetSetting("questBarPinnedItems", pins)
                        QuestItemBar:Update()
                    end
                end
            end)
            
            button:Show()
        end

        button:SetScript("OnEnter", function()
            if this.hasItem then
                Guda_ItemButton_OnEnter(this)
            else
                GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                GameTooltip:SetText("Quest Slot " .. index)
                GameTooltip:AddLine("Auto-fills with usable quest items.", 1, 1, 1)
                GameTooltip:AddLine("Alt-Click an item in bags to pin it.", 0, 1, 0)
                GameTooltip:AddLine("Ctrl-Right-Click to unpin.", 0.5, 0.5, 0.5)
                GameTooltip:Show()
            end
        end)

        button:SetScript("OnLeave", function()
            if this.hasItem then
                Guda_ItemButton_OnLeave(this)
            else
                GameTooltip:Hide()
            end
        end)

        button:ClearAllPoints()
        button:SetPoint("LEFT", frame, "LEFT", xOffset + (i-1) * (buttonSize + spacing), 0)

        -- Update visual overlays (cooldown, etc)
        if Guda_ItemButton_UpdateCooldown then
            Guda_ItemButton_UpdateCooldown(button)
        end
    end
    
    -- Fixed width for 2 slots
    local newWidth = xOffset * 2 + 2 * (buttonSize + spacing) - spacing
    frame:SetWidth(newWidth)
end

function QuestItemBar:UpdateCooldowns()
    for _, button in ipairs(buttons) do
        if button:IsShown() and Guda_ItemButton_UpdateCooldown then
            Guda_ItemButton_UpdateCooldown(button)
        end
    end
end

-- Global wrappers for keybindings
function Guda_UseQuestItem1()
    local button = getglobal("Guda_QuestItemBarButton1")
    if button and button:IsShown() and button.hasItem and button.bagID and button.slotID then
        UseContainerItem(button.bagID, button.slotID)
    end
end

function Guda_UseQuestItem2()
    local button = getglobal("Guda_QuestItemBarButton2")
    if button and button:IsShown() and button.hasItem and button.bagID and button.slotID then
        UseContainerItem(button.bagID, button.slotID)
    end
end

function QuestItemBar:Initialize()
    local frame = CreateFrame("Frame", "Guda_QuestItemBar", UIParent)
    frame:SetWidth(40)
    frame:SetHeight(45)
    frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 150)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    
    addon:ApplyBackdrop(frame, "DEFAULT_FRAME")
    
    -- Handle dragging
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function()
        this:StartMoving()
    end)
    frame:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        local point, _, relativePoint, x, y = this:GetPoint()
        addon.Modules.DB:SetSetting("questBarPosition", {point = point, relativePoint = relativePoint, x = x, y = y})
    end)
    
    -- Restore position
    local pos = addon.Modules.DB:GetSetting("questBarPosition")
    if pos and pos.point then
        frame:ClearAllPoints()
        frame:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x, pos.y)
    end
    
    -- Register for events
    addon.Modules.Events:Register("BAG_UPDATE", function()
        QuestItemBar:Update()
    end, "QuestItemBar")

    addon.Modules.Events:Register("BAG_UPDATE_COOLDOWN", function()
        QuestItemBar:UpdateCooldowns()
    end, "QuestItemBar")
    
    addon.Modules.Events:Register("PLAYER_ENTERING_WORLD", function()
        QuestItemBar:Update()
    end, "QuestItemBar")

    QuestItemBar:Update()
    addon:Debug("QuestItemBar initialized")
end

QuestItemBar.isLoaded = true
