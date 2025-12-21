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

-- Update the bar buttons
function QuestItemBar:Update()
    if addon.Modules.DB:GetSetting("showQuestBar") == false then
        local frame = Guda_QuestItemBar
        if frame then frame:Hide() end
        return
    end
    self:ScanForQuestItems()
    
    local frame = Guda_QuestItemBar
    if not frame then return end

    -- Hide all buttons first
    for _, button in ipairs(buttons) do
        button:Hide()
    end

    if table.getn(questItems) == 0 then
        frame:Hide()
        return
    end

    frame:Show()

    local buttonSize = 37
    local spacing = 2
    local xOffset = 5
    
    for i, item in ipairs(questItems) do
        local button = buttons[i]
        if not button then
            button = CreateFrame("Button", "Guda_QuestItemBarButton" .. i, frame, "Guda_ItemButtonTemplate")
            table.insert(buttons, button)
        end

        button:SetID(item.slotID)
        -- SetBagItem expects bagID and slotID
        button.bagID = item.bagID
        button.slotID = item.slotID
        button.itemData = { link = GetContainerItemLink(item.bagID, item.slotID) }
        
        local icon = getglobal(button:GetName() .. "IconTexture")
        icon:SetTexture(item.texture)
        
        local count = getglobal(button:GetName() .. "Count")
        if item.count > 1 then
            count:SetText(item.count)
            count:Show()
        else
            count:Hide()
        end

        button:ClearAllPoints()
        button:SetPoint("LEFT", frame, "LEFT", xOffset + (i-1) * (buttonSize + spacing), 0)
        button:Show()
        
        -- Set custom data for tooltip handling
        button.hasItem = true

        -- Allow dragging the bar via buttons
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
    
    -- Adjust frame width based on number of items
    local newWidth = xOffset * 2 + table.getn(questItems) * (buttonSize + spacing) - spacing
    frame:SetWidth(math.max(newWidth, 40))
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
    
    addon.Modules.Events:Register("PLAYER_ENTERING_WORLD", function()
        QuestItemBar:Update()
    end, "QuestItemBar")

    QuestItemBar:Update()
    addon:Debug("QuestItemBar initialized")
end

QuestItemBar.isLoaded = true
