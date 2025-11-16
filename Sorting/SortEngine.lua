-- Guda Sort Engine
-- Adapted from Baganator sorting logic for WoW 1.12.1

local addon = Guda

local SortEngine = {}
addon.Modules.SortEngine = SortEngine

-- Priority items that should always be sorted first
local PriorityItems = {
    [6948] = true, -- Hearthstone
}

-- Custom ordering for item classes (matches Baganator's logical grouping)
local classOrder = {
    [0] = 1,  -- Consumable
    [6] = 2,  -- Projectile (ammo/arrows)
    [2] = 3,  -- Weapon
    [4] = 4,  -- Armor
    [11] = 5, -- Quiver
    [5] = 6,  -- Reagent
    [7] = 7,  -- Trade Goods
    [9] = 8,  -- Recipe
    [1] = 9,  -- Container
    [12] = 10, -- Quest
    [13] = 11, -- Key
    [15] = 12, -- Miscellaneous
}

-- Extract itemID from item link
local function GetItemID(link)
    if not link then return 0 end
    local _, _, itemID = string.find(link, "item:(%d+)")
    return tonumber(itemID) or 0
end

-- Get item class ID (numeric)
local function GetItemClassID(link)
    if not link then return 99 end
    local _, _, _, _, _, _, class = GetItemInfo(link)
    -- In 1.12.1, GetItemInfo returns class as string, need to map to ID
    -- We'll use a simple hash of the string for ordering
    if not class then return 99 end

    -- Map common class names to IDs (1.12.1 compatible)
    local classMap = {
        ["Consumable"] = 0,
        ["Container"] = 1,
        ["Weapon"] = 2,
        ["Armor"] = 4,
        ["Reagent"] = 5,
        ["Projectile"] = 6,
        ["Trade Goods"] = 7,
        ["Recipe"] = 9,
        ["Quiver"] = 11,
        ["Quest"] = 12,
        ["Key"] = 13,
        ["Miscellaneous"] = 15,
    }

    return classMap[class] or 99
end

-- Add sort keys to items
local function AddSortKeys(items)
    for _, item in ipairs(items) do
        if item.data and item.data.link then
            local itemID = GetItemID(item.data.link)
            local classID = GetItemClassID(item.data.link)

            -- Priority: Hearthstone = 1, everything else = 1000
            item.priority = PriorityItems[itemID] and 1 or 1000

            -- Get sorted class order (lower = earlier in bags)
            item.sortedClass = classOrder[classID] or 99

            -- Inverted quality (higher quality = earlier)
            item.invertedQuality = -(item.quality or 0)

            -- Item name for alphabetical sorting
            item.itemName = item.name or ""

            -- Inverted item ID for consistent sorting
            item.invertedItemID = -(itemID)
        end
    end
end

-- Sort items using multi-criteria comparison
local function SortItems(items)
    AddSortKeys(items)

    table.sort(items, function(a, b)
        -- Sort by priority first (Hearthstone)
        if a.priority ~= b.priority then
            return a.priority < b.priority
        end

        -- Then by class (Consumables, Ammo, Weapons, Armor, etc.)
        if a.sortedClass ~= b.sortedClass then
            return a.sortedClass < b.sortedClass
        end

        -- Within same class, sort by quality (Epic > Rare > Uncommon > Common > Poor)
        if a.invertedQuality ~= b.invertedQuality then
            return a.invertedQuality < b.invertedQuality
        end

        -- Then alphabetically by name
        if a.itemName ~= b.itemName then
            return a.itemName < b.itemName
        end

        -- Finally by item ID for consistency
        return a.invertedItemID < b.invertedItemID
    end)

    return items
end

-- Collect all items from bags
function SortEngine:CollectItems(bagIDs)
    local items = {}

    for _, bagID in ipairs(bagIDs) do
        local numSlots = addon.Modules.Utils:GetBagSlotCount(bagID)

        if addon.Modules.Utils:IsBagValid(bagID) then
            for slot = 1, numSlots do
                local itemData = addon.Modules.BagScanner:ScanSlot(bagID, slot)

                if itemData then
                    table.insert(items, {
                        bagID = bagID,
                        slot = slot,
                        data = itemData,
                        quality = itemData.quality or 0,
                        name = itemData.name or "",
                        class = itemData.class or "",
                    })
                end
            end
        end
    end

    return items
end

-- Build target slot positions (sequential, no gaps)
local function BuildTargetPositions(bagIDs, itemCount)
    local positions = {}
    local index = 1

    for _, bagID in ipairs(bagIDs) do
        local numSlots = addon.Modules.Utils:GetBagSlotCount(bagID)

        if addon.Modules.Utils:IsBagValid(bagID) then
            for slot = 1, numSlots do
                if index <= itemCount then
                    positions[index] = {bag = bagID, slot = slot}
                    index = index + 1
                else
                    break
                end
            end
        end

        if index > itemCount then
            break
        end
    end

    return positions
end

-- Apply sorted items back to bags (two-phase move system from Baganator)
function SortEngine:ApplySort(bagIDs, method)
    addon:Print("Sorting bags...")

    -- Collect and sort items
    local items = self:CollectItems(bagIDs)

    if table.getn(items) == 0 then
        addon:Print("No items to sort!")
        return
    end

    items = SortItems(items)

    -- Build target positions (sequential slots)
    local targetPositions = BuildTargetPositions(bagIDs, table.getn(items))

    -- Clear cursor
    ClearCursor()

    -- Two-phase move system (from Baganator)
    -- Phase 1: Moves to empty slots
    -- Phase 2: Swaps with occupied slots

    local moveQueue0 = {} -- Moves to empty slots
    local moveQueue1 = {} -- Swaps with occupied slots

    -- Build move queues
    for i, item in ipairs(items) do
        local target = targetPositions[i]

        if target then
            local sourceBag, sourceSlot = item.bagID, item.slot
            local targetBag, targetSlot = target.bag, target.slot

            -- Skip if already in correct position
            if sourceBag ~= targetBag or sourceSlot ~= targetSlot then
                -- Check if target slot is empty
                local targetItem = GetContainerItemLink(targetBag, targetSlot)

                if not targetItem then
                    -- Target is empty - Phase 1 move
                    table.insert(moveQueue0, {
                        sourceBag = sourceBag,
                        sourceSlot = sourceSlot,
                        targetBag = targetBag,
                        targetSlot = targetSlot,
                    })
                else
                    -- Target is occupied - Phase 2 swap
                    table.insert(moveQueue1, {
                        sourceBag = sourceBag,
                        sourceSlot = sourceSlot,
                        targetBag = targetBag,
                        targetSlot = targetSlot,
                    })
                end
            end
        end
    end

    -- Execute Phase 1: Move to empty slots first
    local moveCount = 0
    for _, move in ipairs(moveQueue0) do
        local _, _, locked = GetContainerItemInfo(move.sourceBag, move.sourceSlot)
        if not locked then
            PickupContainerItem(move.sourceBag, move.sourceSlot)
            PickupContainerItem(move.targetBag, move.targetSlot)
            ClearCursor()
            moveCount = moveCount + 1
        end
    end

    -- Execute Phase 2: Swap with occupied slots
    for _, move in ipairs(moveQueue1) do
        local _, _, sourceLocked = GetContainerItemInfo(move.sourceBag, move.sourceSlot)
        local _, _, targetLocked = GetContainerItemInfo(move.targetBag, move.targetSlot)

        if not sourceLocked and not targetLocked then
            PickupContainerItem(move.sourceBag, move.sourceSlot)
            PickupContainerItem(move.targetBag, move.targetSlot)
            ClearCursor()
            moveCount = moveCount + 1
        end
    end

    if moveCount > 0 then
        addon:Print("Sort complete! (%d items moved)", moveCount)
    else
        addon:Print("Items are already sorted!")
    end
end

-- Sort current bags
function SortEngine:SortBags()
    self:ApplySort(addon.Constants.BAGS, "type")
end

-- Sort bank
function SortEngine:SortBank()
    if not addon.Modules.BankScanner:IsBankOpen() then
        addon:Print("Bank must be open to sort!")
        return
    end

    self:ApplySort(addon.Constants.BANK_BAGS, "type")
end
