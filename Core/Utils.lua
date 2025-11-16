-- Guda Utility Functions

local addon = Guda

local Utils = {}
addon.Modules.Utils = Utils

-- Format money (copper to gold/silver/copper string) - WoW 1.12.1 version
function Utils:FormatMoney(copper, showZero)
    if not copper or copper == 0 then
        return "0c"
    end

    local gold = math.floor(copper / 10000)
    local silver = math.floor(mod(copper, 10000) / 100)
    local bronze = mod(copper, 100)

    local str = ""
    if gold > 0 then
        str = str .. gold .. "g "
    end
    if silver > 0 or gold > 0 then
        str = str .. silver .. "s "
    end
    str = str .. bronze .. "c"

    return str
end

-- Get item info with caching
local itemCache = {}
function Utils:GetItemInfo(itemLink)
    if not itemLink then return nil end

    if itemCache[itemLink] then
        return unpack(itemCache[itemLink])
    end

    local name, link, quality, iLevel, reqLevel, class, subclass, maxStack, equipSlot, texture = GetItemInfo(itemLink)

    if name then
        itemCache[itemLink] = {name, link, quality, iLevel, reqLevel, class, subclass, maxStack, equipSlot, texture}
        return name, link, quality, iLevel, reqLevel, class, subclass, maxStack, equipSlot, texture
    end

    return nil
end

-- Get quality color
function Utils:GetQualityColor(quality)
    local color = addon.Constants.QUALITY_COLORS[quality] or addon.Constants.QUALITY_COLORS[1]
    return color.r, color.g, color.b
end

-- Create colored text
function Utils:ColorText(text, r, g, b)
    local red = math.floor(r * 255)
    local green = math.floor(g * 255)
    local blue = math.floor(b * 255)
    return string.format("|cFF%02X%02X%02X%s|r", red, green, blue, text)
end

-- Deep copy table
function Utils:DeepCopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[Utils:DeepCopy(orig_key)] = Utils:DeepCopy(orig_value)
        end
        setmetatable(copy, Utils:DeepCopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

-- Get class color
function Utils:GetClassColor(class)
    local colors = {
        WARRIOR = {r = 0.78, g = 0.61, b = 0.43},
        PALADIN = {r = 0.96, g = 0.55, b = 0.73},
        HUNTER = {r = 0.67, g = 0.83, b = 0.45},
        ROGUE = {r = 1.00, g = 0.96, b = 0.41},
        PRIEST = {r = 1.00, g = 1.00, b = 1.00},
        SHAMAN = {r = 0.00, g = 0.44, b = 0.87},
        MAGE = {r = 0.41, g = 0.80, b = 0.94},
        WARLOCK = {r = 0.58, g = 0.51, b = 0.79},
        DRUID = {r = 1.00, g = 0.49, b = 0.04},
    }
    return colors[class] or {r = 0.5, g = 0.5, b = 0.5}
end

-- Format time ago
function Utils:FormatTimeAgo(timestamp)
    local diff = time() - timestamp
    if diff < 60 then
        return "Just now"
    elseif diff < 3600 then
        return math.floor(diff / 60) .. "m ago"
    elseif diff < 86400 then
        return math.floor(diff / 3600) .. "h ago"
    else
        return math.floor(diff / 86400) .. "d ago"
    end
end

-- Get bag slot count
function Utils:GetBagSlotCount(bagID)
    if bagID == -1 then
        -- Bank has 24 slots in vanilla
        return 24
    else
        return GetContainerNumSlots(bagID) or 0
    end
end

-- Check if bag is valid
function Utils:IsBagValid(bagID)
    if bagID == 0 or bagID == -1 then
        return true
    end
    return GetContainerNumSlots(bagID) and GetContainerNumSlots(bagID) > 0
end

-- Truncate text to length
function Utils:TruncateText(text, maxLen)
    if not text then return "" end
    if string.len(text) <= maxLen then
        return text
    end
    return string.sub(text, 1, maxLen - 3) .. "..."
end
