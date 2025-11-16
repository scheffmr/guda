-- Guda Tooltip Module - Lua 5.0 Compatible
local addon = Guda

local Tooltip = {}
addon.Modules.Tooltip = Tooltip

-- Helper function to get item ID from link (Lua 5.0 compatible)
local function GetItemIDFromLink(link)
    if not link then return nil end
    -- Use strfind instead of string.match
    local _, _, itemID = strfind(link, "item:(%d+):?")
    return itemID and tonumber(itemID) or nil
end

-- Count items for a specific character
local function CountItemsForCharacter(itemID, characterData)
    local total = 0
    
    -- Count bags
    if characterData.bags then
        for bagID, bagData in pairs(characterData.bags) do
            if bagData and bagData.slots then
                for slotID, itemData in pairs(bagData.slots) do
                    if itemData and itemData.link then
                        local slotItemID = GetItemIDFromLink(itemData.link)
                        if slotItemID == itemID then
                            total = total + (itemData.count or 1)
                        end
                    end
                end
            end
        end
    end
    
    return total
end

-- Get class color
local function GetClassColor(classToken)
    if not classToken then return 1.0, 1.0, 1.0 end
    local color = RAID_CLASS_COLORS[classToken]
    if color then return color.r, color.g, color.b end
    return 1.0, 1.0, 1.0
end

-- Add inventory info to tooltip
function Tooltip:AddInventoryInfo(tooltip, link)
    if not Guda_DB or not Guda_DB.characters then 
        addon:Debug("No Guda_DB or characters found")
        return 
    end
    
    local itemID = GetItemIDFromLink(link)
    if not itemID then 
        addon:Debug("Could not get item ID from link: " .. tostring(link))
        return 
    end
    
    addon:Debug("Processing item ID: " .. itemID)
    
    local totalCount = 0
    local characterCounts = {}
    
    -- Count items across all characters
    for charName, charData in pairs(Guda_DB.characters) do
        local count = CountItemsForCharacter(itemID, charData)
        if count > 0 then
            totalCount = totalCount + count
            table.insert(characterCounts, {
                name = charData.name or charName,
                classToken = charData.classToken,
                count = count
            })
            addon:Debug("Found " .. count .. " items on " .. charName)
        end
    end
    
    -- Only add to tooltip if we found items
    if totalCount > 0 then
        addon:Debug("Adding inventory info - Total: " .. totalCount)
        
        tooltip:AddLine(" ")
        tooltip:AddLine("Inventory", 0.7, 0.7, 0.7)
        tooltip:AddDoubleLine("Total: " .. totalCount, "", 1, 1, 1)
        
        -- Sort characters by name
        table.sort(characterCounts, function(a, b) 
            return a.name < b.name 
        end)
        
        -- Add character lines
        for _, charInfo in ipairs(characterCounts) do
            local r, g, b = GetClassColor(charInfo.classToken)
            tooltip:AddDoubleLine(charInfo.name, "Bags: " .. charInfo.count, r, g, b, 0.7, 0.7, 0.7)
        end
        
        tooltip:Show()
    else
        addon:Debug("No items found for ID: " .. itemID)
    end
end

function Tooltip:Initialize()
    addon:Print("Initializing tooltip module...")
    
    -- Hook SetBagItem
    local oldSetBagItem = GameTooltip.SetBagItem
    function GameTooltip:SetBagItem(bag, slot)
        oldSetBagItem(self, bag, slot)
        local link = GetContainerItemLink(bag, slot)
        if link then
            Tooltip:AddInventoryInfo(self, link)
        end
    end
    
    -- Hook SetHyperlink for chat links
    local oldSetHyperlink = GameTooltip.SetHyperlink
    function GameTooltip:SetHyperlink(link)
        oldSetHyperlink(self, link)
        if link and strfind(link, "item:") then
            Tooltip:AddInventoryInfo(self, link)
        end
    end
    
    -- Hook SetInventoryItem for character paperdoll
    local oldSetInventoryItem = GameTooltip.SetInventoryItem
    function GameTooltip:SetInventoryItem(unit, slot)
        oldSetInventoryItem(self, unit, slot)
        local link = GetInventoryItemLink(unit, slot)
        if link then
            Tooltip:AddInventoryInfo(self, link)
        end
    end
    
    -- Also hook ItemRefTooltip for chat links
    if ItemRefTooltip then
        local oldItemRefSetHyperlink = ItemRefTooltip.SetHyperlink
        function ItemRefTooltip:SetHyperlink(link)
            oldItemRefSetHyperlink(self, link)
            if link and strfind(link, "item:") then
                Tooltip:AddInventoryInfo(self, link)
            end
        end
    end

    -- Clear cache function
    function Tooltip:ClearCache()
        addon:Debug("Tooltip cache cleared")
    end

    -- Register for bag updates in Initialize
    function Tooltip:Initialize()
        addon:Print("Initializing tooltip module...")
        
        -- Your existing hook code...
        
        -- Clear cache on bag updates
        local frame = CreateFrame("Frame")
        frame:RegisterEvent("BAG_UPDATE")
        frame:SetScript("OnEvent", function()
            if event == "BAG_UPDATE" then
                Tooltip:ClearCache()
            end
        end)
        
        addon:Print("Tooltip item-count integration enabled")
    end
    
    addon:Print("Tooltip item-count integration enabled")
end