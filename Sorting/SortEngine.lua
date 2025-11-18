-- Guda Sort Engine
-- 6-Phase Advanced Sorting Algorithm for WoW 1.12.1

local addon = Guda

local SortEngine = {}
addon.Modules.SortEngine = SortEngine

-- Priority items that should always be sorted first
local PriorityItems = {
    [6948] = true, -- Hearthstone
}

-- Custom ordering for item classes
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
    if not class then return 99 end

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

--===========================================================================
-- PHASE 1: Special Container Detection
--===========================================================================

local function DetectSpecializedBags(bagIDs)
    local containers = {
        soul = {},
        quiver = {},
        ammo = {},
        regular = {}
    }

    for _, bagID in ipairs(bagIDs) do
        local bagType = addon.Modules.Utils:GetSpecializedBagType(bagID)
        if bagType == "soul" then
            table.insert(containers.soul, bagID)
        elseif bagType == "quiver" then
            table.insert(containers.quiver, bagID)
        elseif bagType == "ammo" then
            table.insert(containers.ammo, bagID)
        else
            table.insert(containers.regular, bagID)
        end
    end

    return containers
end

--===========================================================================
-- PHASE 2: Specialized Item Routing
--===========================================================================

local function RouteSpecializedItems(bagIDs, containers)
    -- This phase moves specialized items to their preferred containers
    -- We'll do this by marking items for routing and then executing moves

    local routingPlan = {}

    -- Scan all items
    for _, bagID in ipairs(bagIDs) do
        local numSlots = addon.Modules.Utils:GetBagSlotCount(bagID)
        if numSlots and numSlots > 0 then
            for slot = 1, numSlots do
                local link = GetContainerItemLink(bagID, slot)
                if link then
                    local preferredType = addon.Modules.Utils:GetItemPreferredContainer(link)

                    -- If item has a preferred container type and isn't already in one
                    if preferredType then
                        local currentBagType = addon.Modules.Utils:GetSpecializedBagType(bagID)

                        -- If not already in preferred container
                        if currentBagType ~= preferredType then
                            local targetBags = containers[preferredType]
                            if targetBags and table.getn(targetBags) > 0 then
                                -- Find first available slot in preferred containers
                                local foundSlot = false
                                for _, targetBagID in ipairs(targetBags) do
                                    if not foundSlot then
                                        local targetSlots = addon.Modules.Utils:GetBagSlotCount(targetBagID)
                                        for targetSlot = 1, targetSlots do
                                            local targetLink = GetContainerItemLink(targetBagID, targetSlot)
                                            if not targetLink then
                                                -- Found empty slot - plan the move
                                                table.insert(routingPlan, {
                                                    fromBag = bagID,
                                                    fromSlot = slot,
                                                    toBag = targetBagID,
                                                    toSlot = targetSlot
                                                })
                                                foundSlot = true
                                                break
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Execute routing plan
    for _, move in ipairs(routingPlan) do
        PickupContainerItem(move.fromBag, move.fromSlot)
        PickupContainerItem(move.toBag, move.toSlot)
        ClearCursor()
    end

    return table.getn(routingPlan)
end

--===========================================================================
-- PHASE 3: Stack Consolidation
--===========================================================================

local function ConsolidateStacks(bagIDs)
    -- Group items by (itemID, quality, soulbound)
    local itemGroups = {}

    -- Collect all items with their locations
    for _, bagID in ipairs(bagIDs) do
        local numSlots = addon.Modules.Utils:GetBagSlotCount(bagID)
        if numSlots and numSlots > 0 then
            for slot = 1, numSlots do
                local link = GetContainerItemLink(bagID, slot)
                if link then
                    local texture, count, locked = GetContainerItemInfo(bagID, slot)
                    local itemID = GetItemID(link)
                    local _, _, quality = GetItemInfo(link)

                    -- Create group key
                    local groupKey = itemID .. "_" .. (quality or 0)

                    if not itemGroups[groupKey] then
                        itemGroups[groupKey] = {
                            itemID = itemID,
                            link = link,
                            stacks = {}
                        }
                    end

                    table.insert(itemGroups[groupKey].stacks, {
                        bagID = bagID,
                        slot = slot,
                        count = count or 1,
                        priority = addon.Modules.Utils:GetContainerPriority(bagID)
                    })
                end
            end
        end
    end

    -- For each group, consolidate stacks
    local consolidationMoves = 0
    for _, group in pairs(itemGroups) do
        if table.getn(group.stacks) > 1 then
            -- Get max stack size
            local _, _, _, _, _, _, _, maxStack = GetItemInfo(group.link)
            maxStack = maxStack or 1

            if maxStack > 1 then
                -- Sort stacks by priority DESC, then count DESC
                table.sort(group.stacks, function(a, b)
                    if a.priority ~= b.priority then
                        return a.priority > b.priority
                    end
                    return a.count > b.count
                end)

                -- Greedy consolidation
                for i = 1, table.getn(group.stacks) do
                    local source = group.stacks[i]
                    if source.count < maxStack then
                        for j = i + 1, table.getn(group.stacks) do
                            local target = group.stacks[j]
                            if target.count > 0 then
                                local spaceAvailable = maxStack - source.count
                                local amountToMove = math.min(spaceAvailable, target.count)

                                if amountToMove > 0 then
                                    -- Split from target and add to source
                                    if amountToMove < target.count then
                                        SplitContainerItem(target.bagID, target.slot, amountToMove)
                                        PickupContainerItem(source.bagID, source.slot)
                                        ClearCursor()
                                    else
                                        -- Move entire stack
                                        PickupContainerItem(target.bagID, target.slot)
                                        PickupContainerItem(source.bagID, source.slot)
                                        ClearCursor()
                                    end

                                    source.count = source.count + amountToMove
                                    target.count = target.count - amountToMove
                                    consolidationMoves = consolidationMoves + 1

                                    if source.count >= maxStack then
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return consolidationMoves
end

--===========================================================================
-- PHASE 4: Categorical Sorting
--===========================================================================

local function AddSortKeys(items)
    for _, item in ipairs(items) do
        if item.data and item.data.link then
            local itemID = GetItemID(item.data.link)
            local classID = GetItemClassID(item.data.link)
            local _, _, quality, iLevel = GetItemInfo(item.data.link)

            -- Priority: Hearthstone = 1, everything else = 1000
            item.priority = PriorityItems[itemID] and 1 or 1000

            -- Container priority
            item.containerPriority = addon.Modules.Utils:GetContainerPriority(item.bagID)

            -- Get sorted class order
            item.sortedClass = classOrder[classID] or 99

            -- Inverted quality (higher quality = earlier)
            item.invertedQuality = -(quality or 0)

            -- Inverted item level
            item.invertedItemLevel = -(iLevel or 0)

            -- Item name for alphabetical sorting
            item.itemName = item.name or ""

            -- Inverted count (larger stacks first)
            item.invertedCount = -(item.data.count or 1)

            -- Inverted item ID for consistent sorting
            item.invertedItemID = -(itemID)
        end
    end
end

local function SortItems(items)
    AddSortKeys(items)

    table.sort(items, function(a, b)
        -- Priority items first (Hearthstone)
        if a.priority ~= b.priority then
            return a.priority < b.priority
        end

        -- Container type (Soul > Quiver > Ammo > Regular)
        if a.containerPriority ~= b.containerPriority then
            return a.containerPriority > b.containerPriority
        end

        -- Item category
        if a.sortedClass ~= b.sortedClass then
            return a.sortedClass < b.sortedClass
        end

        -- Quality (Epic > Rare > Uncommon > Common > Poor)
        if a.invertedQuality ~= b.invertedQuality then
            return a.invertedQuality < b.invertedQuality
        end

        -- Item level (descending)
        if a.invertedItemLevel ~= b.invertedItemLevel then
            return a.invertedItemLevel < b.invertedItemLevel
        end

        -- Alphabetically by name
        if a.itemName ~= b.itemName then
            return a.itemName < b.itemName
        end

        -- Item ID (group same items together)
        if a.invertedItemID ~= b.invertedItemID then
            return a.invertedItemID < b.invertedItemID
        end

        -- Stack count (larger stacks first within same item)
        return a.invertedCount < b.invertedCount
    end)

    return items
end

--===========================================================================
-- PHASE 5: Empty Slot Management & Apply Sort
--===========================================================================

local function CollectItems(bagIDs)
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

local function BuildTargetPositions(bagIDs, itemCount)
    local positions = {}
    local index = 1

    -- Sort bags by priority: Soul (40) > Quiver (30) > Ammo (20) > Regular (10)
    local sortedBags = {}
    for _, bagID in ipairs(bagIDs) do
        table.insert(sortedBags, {
            bagID = bagID,
            priority = addon.Modules.Utils:GetContainerPriority(bagID)
        })
    end

    -- Sort bags by priority descending (highest first)
    table.sort(sortedBags, function(a, b)
        return a.priority > b.priority
    end)

    -- Build positions in priority order
    for _, bagInfo in ipairs(sortedBags) do
        local bagID = bagInfo.bagID
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

local function ApplySort(bagIDs, items, targetPositions)
    ClearCursor()

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

    return moveCount
end

--===========================================================================
-- PHASE 6: Final Validation (Informational)
--===========================================================================

local function ValidateSort(bagIDs)
    -- This is mostly informational - in practice, the sort should be correct
    -- Could add checks here if needed for debugging
    return true
end

--===========================================================================
-- Main Sort Functions
--===========================================================================

function SortEngine:SortBags()
    local bagIDs = addon.Constants.BAGS

    -- Phase 1: Detect specialized bags
    local containers = DetectSpecializedBags(bagIDs)

    -- Phase 2: Route specialized items to their bags
    local routeCount = RouteSpecializedItems(bagIDs, containers)

    -- Phase 3: Consolidate stacks in ALL bags (including specialized)
    local consolidateCount = ConsolidateStacks(bagIDs)

    -- Phase 4: Sort items WITHIN each specialized bag (soul, quiver, ammo)
    local specializedMoves = 0
    for _, bagType in ipairs({"soul", "quiver", "ammo"}) do
        local specialBags = containers[bagType]
        for _, bagID in ipairs(specialBags) do
            -- Sort items within this single specialized bag
            local items = CollectItems({bagID})
            if table.getn(items) > 0 then
                items = SortItems(items)
                local targetPositions = BuildTargetPositions({bagID}, table.getn(items))
                local moveCount = ApplySort({bagID}, items, targetPositions)
                specializedMoves = specializedMoves + moveCount
            end
        end
    end

    -- Phase 5: Categorical sort regular bags
    local regularMoves = 0
    local regularBagIDs = containers.regular
    if table.getn(regularBagIDs) > 0 then
        local items = CollectItems(regularBagIDs)
        if table.getn(items) > 0 then
            items = SortItems(items)
            local targetPositions = BuildTargetPositions(regularBagIDs, table.getn(items))
            regularMoves = ApplySort(regularBagIDs, items, targetPositions)
        end
    end

    -- Return total moves made (used to determine if another pass is needed)
    return routeCount + consolidateCount + specializedMoves + regularMoves
end

function SortEngine:SortBank()
    if not addon.Modules.BankScanner:IsBankOpen() then
        addon:Print("Bank must be open to sort!")
        return 0
    end

    local bagIDs = addon.Constants.BANK_BAGS

    -- Phase 1: Detect specialized bags
    local containers = DetectSpecializedBags(bagIDs)

    -- Phase 2: Route specialized items
    local routeCount = RouteSpecializedItems(bagIDs, containers)

    -- Phase 3: Consolidate stacks
    local consolidateCount = ConsolidateStacks(bagIDs)

    -- Phase 4: Sort items WITHIN each specialized bag
    local specializedMoves = 0
    for _, bagType in ipairs({"soul", "quiver", "ammo"}) do
        local specialBags = containers[bagType]
        for _, bagID in ipairs(specialBags) do
            local items = CollectItems({bagID})
            if table.getn(items) > 0 then
                items = SortItems(items)
                local targetPositions = BuildTargetPositions({bagID}, table.getn(items))
                local moveCount = ApplySort({bagID}, items, targetPositions)
                specializedMoves = specializedMoves + moveCount
            end
        end
    end

    -- Phase 5: Sort regular bags
    local regularBagIDs = containers.regular
    local regularMoves = 0
    if table.getn(regularBagIDs) > 0 then
        local items = CollectItems(regularBagIDs)
        if table.getn(items) > 0 then
            items = SortItems(items)
            local targetPositions = BuildTargetPositions(regularBagIDs, table.getn(items))
            regularMoves = ApplySort(regularBagIDs, items, targetPositions)
        end
    end

    -- Return total moves made
    return routeCount + consolidateCount + specializedMoves + regularMoves
end
