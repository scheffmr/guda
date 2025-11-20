-- Guda Sort Engine
-- 6-Phase Advanced Sorting Algorithm for WoW 1.12.1 / Turtle WoW

local addon = Guda

local SortEngine = {}
addon.Modules.SortEngine = SortEngine

--===========================================================================
-- CONSTANTS
--===========================================================================

-- Turtle WoW GetItemInfo signature:
-- itemName, itemLink, itemRarity, itemLevel, itemCategory, itemType, itemStackCount,
-- itemSubType, itemTexture, itemEquipLoc, itemSellPrice = GetItemInfo(itemID)

-- Priority items that should always be sorted first
local PRIORITY_ITEMS = {
	[6948] = 1, -- Hearthstone (highest priority)
}

-- Equipment slot ordering (for sorting equippable gear by slot)
local EQUIP_SLOT_ORDER = {
	["INVTYPE_HEAD"] = 1,
	["INVTYPE_NECK"] = 2,
	["INVTYPE_SHOULDER"] = 3,
	["INVTYPE_CLOAK"] = 4,
	["INVTYPE_CHEST"] = 5,
	["INVTYPE_ROBE"] = 5,
	["INVTYPE_BODY"] = 6,
	["INVTYPE_TABARD"] = 7,
	["INVTYPE_WRIST"] = 8,
	["INVTYPE_HAND"] = 9,
	["INVTYPE_WAIST"] = 10,
	["INVTYPE_LEGS"] = 11,
	["INVTYPE_FEET"] = 12,
	["INVTYPE_FINGER"] = 13,
	["INVTYPE_TRINKET"] = 14,
	["INVTYPE_WEAPONMAINHAND"] = 15,
	["INVTYPE_WEAPONOFFHAND"] = 16,
	["INVTYPE_WEAPON"] = 17,
	["INVTYPE_2HWEAPON"] = 18,
	["INVTYPE_SHIELD"] = 19,
	["INVTYPE_HOLDABLE"] = 20,
	["INVTYPE_RANGED"] = 21,
	["INVTYPE_RANGEDRIGHT"] = 22,
	["INVTYPE_THROWN"] = 23,
	["INVTYPE_RELIC"] = 24,
	["INVTYPE_BAG"] = 25,
	["INVTYPE_QUIVER"] = 26,
}

-- Category sorting order (1 is reserved for equippable gear)
local CATEGORY_ORDER = {
	["Consumable"] = 2,
	["Projectile"] = 3,
	["Weapon"] = 4,      -- Non-equippable weapons
	["Armor"] = 5,       -- Non-equippable armor
	["Quiver"] = 6,
	["Reagent"] = 7,
	["Trade Goods"] = 8,
	["Recipe"] = 9,
	["Container"] = 10,
	["Quest"] = 11,
	["Key"] = 12,
	["Miscellaneous"] = 13,
}

-- Subclass ordering for grouping related items
local SUBCLASS_ORDER = {
	gems = 1,
	cloth = 2,
	leather = 3,
	herbs = 4,
	elemental = 5,
	enchanting = 6,
	engineering = 7,
	consumable = 8,
	other = 99,
}

-- Gem name patterns for detection
local GEM_PATTERNS = {
	"ruby", "sapphire", "emerald", "diamond", "jade", "citrine",
	"aquamarine", "agate", "pearl", "topaz", "opal", "malachite",
	"tigerseye", "tiger's eye", "shadowgem"
}

--===========================================================================
-- UTILITY FUNCTIONS
--===========================================================================

-- Extract itemID from item link
local function GetItemID(link)
	if not link then return 0 end
	local _, _, itemID = string.find(link, "item:(%d+)")
	return tonumber(itemID) or 0
end

-- Extract texture pattern for grouping similar items
local function GetTexturePattern(textureName)
	if not textureName then return "" end

	-- Remove "Interface\\Icons\\INV_" prefix if present
	local cleaned = string.gsub(textureName, "^Interface\\Icons\\INV_", "")

	-- Remove trailing numbers and underscores (like _01, _03, etc.)
	cleaned = string.gsub(cleaned, "_%d+$", "")  -- Remove trailing _01, _02, etc.
	cleaned = string.gsub(cleaned, "_$", "")     -- Remove trailing underscore if any
	return cleaned
end

-- Check if an item is a mount by texture path
local function IsMount(itemTexture)
	if not itemTexture then return false end

	local textureLower = string.lower(itemTexture)

	-- Check for mount patterns in texture path
	-- Mount textures typically contain "mount" or "ability_mount"
	if string.find(textureLower, "mount") then
		return true
	end

	return false
end

-- Determine subclass order for grouping related items
local function GetSubclassOrder(subclass, itemName)
	if not subclass then return 50 end

	local subLower = string.lower(subclass)
	local nameLower = itemName and string.lower(itemName) or ""

	-- Check for gems (by subclass or name)
	if string.find(subLower, "metal") or string.find(subLower, "stone") or string.find(subLower, "gem") then
		return SUBCLASS_ORDER.gems
	end

	for _, gemPattern in ipairs(GEM_PATTERNS) do
		if string.find(nameLower, gemPattern) then
			return SUBCLASS_ORDER.gems
		end
	end

	-- Check other categories
	-- Group metals, stones, ores, bars together with gems
	if string.find(subLower, "metal") or string.find(subLower, "stone") or
	   string.find(nameLower, "ore") or string.find(nameLower, "bar") or string.find(nameLower, "stone") then
		return SUBCLASS_ORDER.gems  -- Group ores/bars/stones with gems
	end
	if string.find(subLower, "cloth") then return SUBCLASS_ORDER.cloth end
	if string.find(subLower, "leather") then return SUBCLASS_ORDER.leather end
	if string.find(subLower, "herb") then return SUBCLASS_ORDER.herbs end
	if string.find(subLower, "elemental") then return SUBCLASS_ORDER.elemental end
	if string.find(subLower, "enchanting") then return SUBCLASS_ORDER.enchanting end
	if string.find(subLower, "engineering") or string.find(subLower, "parts") or string.find(subLower, "device") then
		return SUBCLASS_ORDER.engineering
	end
	if string.find(subLower, "consumable") or string.find(subLower, "food") or string.find(subLower, "drink") then
		return SUBCLASS_ORDER.consumable
	end
	if string.find(subLower, "trade goods") or string.find(subLower, "other") then
		return SUBCLASS_ORDER.other
	end

	return 50 -- Default for unknown types
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
	local routingPlan = {}

	-- Scan all items and plan moves to specialized containers
	for _, bagID in ipairs(bagIDs) do
		local numSlots = addon.Modules.Utils:GetBagSlotCount(bagID)
		if numSlots and numSlots > 0 then
			for slot = 1, numSlots do
				local link = GetContainerItemLink(bagID, slot)
				if link then
					local preferredType = addon.Modules.Utils:GetItemPreferredContainer(link)
					local currentBagType = addon.Modules.Utils:GetSpecializedBagType(bagID)

					-- Route item if it has a preferred container and isn't already in one
					if preferredType and currentBagType ~= preferredType then
						local targetBags = containers[preferredType]
						if targetBags and table.getn(targetBags) > 0 then
						-- Find first available slot in preferred containers
							local foundSlot = false
							for _, targetBagID in ipairs(targetBags) do
								if not foundSlot then
									local targetSlots = addon.Modules.Utils:GetBagSlotCount(targetBagID)
									for targetSlot = 1, targetSlots do
										if not GetContainerItemLink(targetBagID, targetSlot) then
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
	local itemGroups = {}

	-- Collect all items with their locations
	for _, bagID in ipairs(bagIDs) do
		local numSlots = addon.Modules.Utils:GetBagSlotCount(bagID)
		if numSlots and numSlots > 0 then
			for slot = 1, numSlots do
				local link = GetContainerItemLink(bagID, slot)
				if link then
					local texture, count = GetContainerItemInfo(bagID, slot)
					local itemID = GetItemID(link)
					local _, _, itemRarity = GetItemInfo(itemID)

					-- Group by itemID and rarity
					local groupKey = itemID .. "_" .. (tonumber(itemRarity) or 0)

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
						priority = tonumber(addon.Modules.Utils:GetContainerPriority(bagID)) or 0
					})
				end
			end
		end
	end

	-- Consolidate stacks for each group
	local consolidationMoves = 0
	for _, group in pairs(itemGroups) do
		if table.getn(group.stacks) > 1 then
			local itemID = GetItemID(group.link)
			local _, _, _, _, _, _, itemStackCount = GetItemInfo(itemID)
			local maxStack = tonumber(itemStackCount) or 1

			if maxStack > 1 then
			-- Sort stacks: higher priority bags first, then larger stacks
				table.sort(group.stacks, function(a, b)
					if a.priority ~= b.priority then
						return a.priority > b.priority
					end
					return a.count > b.count
				end)

				-- Greedy consolidation: fill stacks from left to right
				for i = 1, table.getn(group.stacks) do
					local source = group.stacks[i]
					if source.count < maxStack then
						for j = i + 1, table.getn(group.stacks) do
							local target = group.stacks[j]
							if target.count > 0 then
								local spaceAvailable = maxStack - source.count
								local amountToMove = math.min(spaceAvailable, target.count)

								if amountToMove > 0 then
									if amountToMove < target.count then
										SplitContainerItem(target.bagID, target.slot, amountToMove)
										PickupContainerItem(source.bagID, source.slot)
									else
										PickupContainerItem(target.bagID, target.slot)
										PickupContainerItem(source.bagID, source.slot)
									end
									ClearCursor()

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
			local itemName, itemLink, itemRarity, itemLevel, itemCategory, itemType, itemStackCount,
			itemSubType, itemTexture, itemEquipLoc, itemSellPrice = GetItemInfo(itemID)
			--addon:Print("itemTexture:%s",itemTexture or 0);
			--addon:Print("itemEquipLoc:%s",itemEquipLoc or 0);
			--addon:Print("itemSubType:%s",itemSubType or 0);
			--addon:Print("itemType:%s",itemType or 0);
			--addon:Print("itemCategory:%s",itemCategory or 0);
			--addon:Print("itemLevel:%s",itemLevel or 0);
			if not itemName then
			-- Skip items that couldn't be loaded
				item.sortedClass = 999
				item.isEquippable = false
				item.priority = 1000
				item.equipSlotOrder = 999
				item.invertedQuality = 0
				item.invertedItemLevel = 0
				item.itemName = ""
				item.sortedSubclass = 999
				item.subclass = ""
				item.texturePattern = ""
				item.invertedCount = 0
				item.invertedItemID = 0
			else
			-- Check if item is equippable (Armor or Weapon category)
				local isEquippable = itemCategory == "Armor" or itemCategory == "Weapon"

				-- Check if item is a mount (by texture path)
				local isMount = IsMount(itemTexture)

				-- Priority (1 = hearthstone, 2 = mounts, 1000 = everything else)
				if PRIORITY_ITEMS[itemID] then
					item.priority = PRIORITY_ITEMS[itemID]
				elseif isMount then
					item.priority = 2
				else
					item.priority = 1000
				end
				item.isEquippable = isEquippable
				item.isMount = isMount

				-- Class and slot ordering
				if isEquippable then
					item.sortedClass = 1 -- All equippable gear gets priority class
					item.equipSlotOrder = EQUIP_SLOT_ORDER[itemEquipLoc] or 999
				else
					item.sortedClass = CATEGORY_ORDER[itemCategory] or 99
					item.equipSlotOrder = 999
				end

				-- Subclass ordering
				item.sortedSubclass = GetSubclassOrder(itemSubType, item.name)
				item.subclass = itemSubType or ""

				-- Texture pattern for grouping similar items (especially trade goods)
				item.texturePattern = GetTexturePattern(itemTexture)

				-- Inverted values for descending sorts
				item.invertedQuality = -(tonumber(itemRarity) or 0)
				item.invertedItemLevel = -(tonumber(itemLevel) or 0)
				item.invertedCount = -(tonumber(item.data.count) or 1)
				item.invertedItemID = -tonumber(itemID)

				-- Name for alphabetical sorting
				item.itemName = item.name or ""
			end
		end
	end
end

local function SortItems(items)
	AddSortKeys(items)

	table.sort(items, function(a, b)
	-- 1. Priority items first (Hearthstone, etc.)
		if a.priority ~= b.priority then
			return a.priority < b.priority
		end

		-- 2. Equippable items always come before non-equippable items
		if a.isEquippable ~= b.isEquippable then
			return a.isEquippable
		end

		-- 3. For equippable gear: sort by slot, subtype, texture pattern, quality, ilvl, name
		if a.isEquippable then
			if a.equipSlotOrder ~= b.equipSlotOrder then
				return a.equipSlotOrder < b.equipSlotOrder
			end
			-- Group by itemSubType first (e.g., "Ring", "Staff", "Cloth", etc.)
			if a.subclass ~= b.subclass then
				return a.subclass < b.subclass
			end
			-- Then group items with similar textures together
			if a.texturePattern ~= b.texturePattern then
				return a.texturePattern < b.texturePattern
			end
			if a.invertedQuality ~= b.invertedQuality then
				return a.invertedQuality < b.invertedQuality
			end
			if a.invertedItemLevel ~= b.invertedItemLevel then
				return a.invertedItemLevel < b.invertedItemLevel
			end
			if a.itemName ~= b.itemName then
				return a.itemName < b.itemName
			end
		else
		-- 4. For non-equippable items: sort by class, subclass, texture pattern, quality, name
			if a.sortedClass ~= b.sortedClass then
				return a.sortedClass < b.sortedClass
			end
			if a.sortedSubclass ~= b.sortedSubclass then
				return a.sortedSubclass < b.sortedSubclass
			end
			if a.subclass ~= b.subclass then
				return a.subclass < b.subclass
			end
			-- Group items with similar textures (e.g., all "Misc_Food", all "Fabric_Linen")
			if a.texturePattern ~= b.texturePattern then
				return a.texturePattern < b.texturePattern
			end
			if a.invertedQuality ~= b.invertedQuality then
				return a.invertedQuality < b.invertedQuality
			end
			if a.itemName ~= b.itemName then
				return a.itemName < b.itemName
			end
		end

		-- 5. Final tiebreakers (group identical items together)
		-- Sort by itemID first to ensure identical items are adjacent
		if a.invertedItemID ~= b.invertedItemID then
			return a.invertedItemID < b.invertedItemID
		end
		-- Then by item level
		if a.invertedItemLevel ~= b.invertedItemLevel then
			return a.invertedItemLevel < b.invertedItemLevel
		end
		-- Then by stack count (larger stacks first)
		if a.invertedCount ~= b.invertedCount then
			return a.invertedCount < b.invertedCount
		end
		-- Final stable sort: preserve original collection order for identical items
		-- This prevents unnecessary reshuffling when items are already sorted
		return a.sequence < b.sequence
	end)

	return items
end

--===========================================================================
-- PHASE 5: Empty Slot Management & Apply Sort
--===========================================================================

local function CollectItems(bagIDs)
	local items = {}
	local sequence = 0  -- Add sequence number for stable sort

	for _, bagID in ipairs(bagIDs) do
		local numSlots = addon.Modules.Utils:GetBagSlotCount(bagID)

		if addon.Modules.Utils:IsBagValid(bagID) then
			for slot = 1, numSlots do
				-- Scan directly from game API instead of cached data
				local texture, itemCount, locked = GetContainerItemInfo(bagID, slot)
				local itemLink = GetContainerItemLink(bagID, slot)

				if itemLink then
					-- Get fresh item info with ALL return values
					local itemID = GetItemID(itemLink)
					local name, link, quality, iLevel, category, itemType, stackCount, subType, iconTex, equipLoc, sellPrice = GetItemInfo(itemID)

					sequence = sequence + 1
					table.insert(items, {
						bagID = bagID,
						slot = slot,
						sequence = sequence,  -- Preserve original order
						data = {
							link = itemLink,
							texture = texture,
							count = itemCount or 1,
							quality = quality or 0,
							name = name,
							iLevel = iLevel,
							class = category,
							subclass = subType,  -- NOW INCLUDED!
							locked = locked,
						},
						quality = quality or 0,
						name = name or "",
						class = category or "",
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

	-- Sort bags by priority (descending), then by bag ID (ascending)
	local sortedBags = {}
	for _, bagID in ipairs(bagIDs) do
		table.insert(sortedBags, {
			bagID = bagID,
			priority = tonumber(addon.Modules.Utils:GetContainerPriority(bagID)) or 0
		})
	end

	table.sort(sortedBags, function(a, b)
		if a.priority ~= b.priority then
			return a.priority > b.priority
		end
		return a.bagID < b.bagID
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

	local moveToEmpty = {}
	local swapOccupied = {}

	-- Build move queues
	for i, item in ipairs(items) do
		local target = targetPositions[i]

		if target then
			local sourceBag, sourceSlot = item.bagID, item.slot
			local targetBag, targetSlot = target.bag, target.slot

			-- Skip if already in correct position
			if sourceBag ~= targetBag or sourceSlot ~= targetSlot then
				local targetItem = GetContainerItemLink(targetBag, targetSlot)

				if not targetItem then
					table.insert(moveToEmpty, {
						sourceBag = sourceBag,
						sourceSlot = sourceSlot,
						targetBag = targetBag,
						targetSlot = targetSlot,
					})
				else
					table.insert(swapOccupied, {
						sourceBag = sourceBag,
						sourceSlot = sourceSlot,
						targetBag = targetBag,
						targetSlot = targetSlot,
					})
				end
			end
		end
	end

	-- Execute moves to empty slots first
	local moveCount = 0
	for _, move in ipairs(moveToEmpty) do
		local _, _, locked = GetContainerItemInfo(move.sourceBag, move.sourceSlot)
		if not locked then
			PickupContainerItem(move.sourceBag, move.sourceSlot)
			PickupContainerItem(move.targetBag, move.targetSlot)
			ClearCursor()
			moveCount = moveCount + 1
		end
	end

	-- Execute swaps with occupied slots
	for _, move in ipairs(swapOccupied) do
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
-- PHASE 6: Sort Complexity Analysis
--===========================================================================

-- Analyze how many sorting passes are needed
-- Returns: {passes, itemsOutOfPlace, totalItems, alreadySorted}
local function AnalyzeSortComplexity(bagIDs)
	-- Collect current items
	local items = CollectItems(bagIDs)
	local totalItems = table.getn(items)

	if totalItems == 0 then
		return {passes = 0, itemsOutOfPlace = 0, totalItems = 0, alreadySorted = true}
	end

	-- Sort to get desired order
	local sortedItems = SortItems(items)

	-- Build target positions
	local targetPositions = BuildTargetPositions(bagIDs, totalItems)

	-- Create position maps for quick lookup
	local currentPositions = {}  -- [bagID_slot] = itemLink
	local targetMap = {}         -- [itemLink] = {targetBag, targetSlot, currentIndex}

	for i, item in ipairs(items) do
		local key = item.bagID .. "_" .. item.slot
		currentPositions[key] = item.data.link
	end

	for i, item in ipairs(sortedItems) do
		local target = targetPositions[i]
		if target and item.data.link then
			if not targetMap[item.data.link] then
				targetMap[item.data.link] = {}
			end
			table.insert(targetMap[item.data.link], {
				targetBag = target.bag,
				targetSlot = target.slot,
				currentIndex = i,
				sourceBag = item.bagID,
				sourceSlot = item.slot
			})
		end
	end

	-- Count items that are already in correct position
	local itemsInPlace = 0
	local itemsOutOfPlace = 0
	local maxDisplacement = 0

	for i, item in ipairs(sortedItems) do
		local target = targetPositions[i]
		if target then
			local sourceBag, sourceSlot = item.bagID, item.slot
			local targetBag, targetSlot = target.bag, target.slot

			if sourceBag == targetBag and sourceSlot == targetSlot then
				itemsInPlace = itemsInPlace + 1
			else
				itemsOutOfPlace = itemsOutOfPlace + 1

				-- Calculate displacement (how far the item needs to move)
				local displacement = math.abs(i - itemsInPlace - itemsOutOfPlace)
				if displacement > maxDisplacement then
					maxDisplacement = displacement
				end
			end
		end
	end

	-- If all items are in place, no sorting needed
	if itemsOutOfPlace == 0 then
		return {passes = 0, itemsOutOfPlace = 0, totalItems = totalItems, alreadySorted = true}
	end

	-- Estimate passes needed based on displacement complexity
	-- Simple heuristic:
	-- - If displacement is low (< 20% of items), probably 1-2 passes
	-- - If displacement is medium (20-50%), probably 2-4 passes
	-- - If displacement is high (>50%), might need 3-6 passes
	local displacementRatio = itemsOutOfPlace / totalItems
	local estimatedPasses

	if displacementRatio < 0.1 then
		estimatedPasses = 1
	elseif displacementRatio < 0.3 then
		estimatedPasses = 2
	elseif displacementRatio < 0.5 then
		estimatedPasses = 3
	elseif displacementRatio < 0.7 then
		estimatedPasses = 4
	else
		-- High complexity - analyze cycles
		-- Count how many swaps are needed vs moves to empty
		local needsSwap = 0
		for i, item in ipairs(sortedItems) do
			local target = targetPositions[i]
			if target then
				local sourceBag, sourceSlot = item.bagID, item.slot
				local targetBag, targetSlot = target.bag, target.slot

				if sourceBag ~= targetBag or sourceSlot ~= targetSlot then
					local targetKey = targetBag .. "_" .. targetSlot
					local targetOccupied = currentPositions[targetKey]
					if targetOccupied then
						needsSwap = needsSwap + 1
					end
				end
			end
		end

		-- More swaps needed = more passes
		local swapRatio = needsSwap / itemsOutOfPlace
		if swapRatio > 0.8 then
			estimatedPasses = 6
		elseif swapRatio > 0.5 then
			estimatedPasses = 5
		else
			estimatedPasses = 4
		end
	end

	return {
		passes = estimatedPasses,
		itemsOutOfPlace = itemsOutOfPlace,
		totalItems = totalItems,
		alreadySorted = false
	}
end

--===========================================================================
-- Main Sort Functions
--===========================================================================

-- Analyze bags to determine how many passes are needed
function SortEngine:AnalyzeBags()
	local bagIDs = addon.Constants.BAGS

	-- Detect specialized bags
	local containers = DetectSpecializedBags(bagIDs)

	-- Analyze regular bags only (specialized bags sort separately)
	local regularBagIDs = containers.regular
	if table.getn(regularBagIDs) > 0 then
		return AnalyzeSortComplexity(regularBagIDs)
	else
		return {passes = 0, itemsOutOfPlace = 0, totalItems = 0, alreadySorted = true}
	end
end

-- Analyze bank to determine how many passes are needed
function SortEngine:AnalyzeBank()
	if not addon.Modules.BankScanner:IsBankOpen() then
		return {passes = 0, itemsOutOfPlace = 0, totalItems = 0, alreadySorted = true}
	end

	local bagIDs = addon.Constants.BANK_BAGS

	-- Detect specialized bags
	local containers = DetectSpecializedBags(bagIDs)

	-- Analyze regular bags only
	local regularBagIDs = containers.regular
	if table.getn(regularBagIDs) > 0 then
		return AnalyzeSortComplexity(regularBagIDs)
	else
		return {passes = 0, itemsOutOfPlace = 0, totalItems = 0, alreadySorted = true}
	end
end

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

	-- Phase 5: Categorical sort regular bags TOGETHER
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

	-- Return total moves made
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

	-- Phase 5: Sort regular bags TOGETHER
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