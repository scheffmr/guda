-- Guda Mailbox Scanner
-- Scans and stores mailbox contents

local addon = Guda

local MailboxScanner = {}
addon.Modules.MailboxScanner = MailboxScanner

local mailboxOpen = false

-- Scan all mailbox items and return data
function MailboxScanner:ScanMailbox()
    if not mailboxOpen then
        addon:Debug("Cannot scan mailbox - not open")
        return {}
    end

    local mailboxData = {}
    local numItems = GetInboxNumItems()

    for i = 1, numItems do
        local mailRows = self:ScanMailItemRows(i)
        for _, row in ipairs(mailRows) do
            table.insert(mailboxData, row)
        end
    end

    return mailboxData
end

-- Scan a single mail into one or more rows (flattened)
function MailboxScanner:ScanMailItemRows(index)
    -- GetInboxHeaderInfo(index) returns: packageIcon, stationeryIcon, sender, subject, money, CODAmount, daysLeft, hasItem, wasRead, wasReturned, textCreated, canReply, isGM
    local packageIcon, stationeryIcon, sender, subject, money, CODAmount, daysLeft, hasItem, wasRead, wasReturned, textCreated, canReply, isGM = GetInboxHeaderInfo(index)

    local rows = {}
    
    if hasItem then
        -- Turtle WoW supports up to 12 attachments per mail

            -- GetInboxItem(index, itemIndex) returns: name, texture, count, quality, canUse
            local name, texture, count, quality, canUse = GetInboxItem(index, itemIndex)
            if name then
                local itemLink = addon.Modules.Utils:GetInboxItemLink(index, itemIndex)

                local itemData = {
                    link = itemLink,
                    texture = texture or "Interface\\Icons\\INV_Misc_Bag_08",
                    count = count or 1,
                    quality = quality or 0,
                    name = name,
                }

                -- If we have a link, try to get more detailed info
                if itemLink then
                    local itemName, link, itemQuality, iLevel, itemCategory, itemType, itemStackCount, itemSubType, itemTexture, itemEquipLoc, itemSellPrice = addon.Modules.Utils:GetItemInfo(itemLink)
                    if itemName then
                        itemData.name = itemName
                        itemData.quality = itemQuality or itemData.quality
                        itemData.iLevel = iLevel
                        itemData.type = itemType
                        itemData.class = itemCategory
                        itemData.subclass = itemSubType
                        itemData.equipSlot = itemEquipLoc
                        if itemTexture then itemData.texture = itemTexture end
                    end
                end

                table.insert(rows, {
                    sender = sender,
                    subject = subject,
                    money = (itemIndex == 1) and money or 0, -- Attach money only to the first row of this mail
                    CODAmount = (itemIndex == 1) and CODAmount or 0,
                    daysLeft = daysLeft,
                    hasItem = true,
                    item = itemData,
                    mailIndex = index,
                    itemIndex = itemIndex,
                    wasRead = wasRead,
                    packageIcon = packageIcon,
                })
        end
    end

    -- If no items found but there is money or it's just a letter
    if table.getn(rows) == 0 then
        table.insert(rows, {
            sender = sender,
            subject = subject,
            money = money,
            CODAmount = CODAmount,
            daysLeft = daysLeft,
            hasItem = false,
            item = nil,
            mailIndex = index,
            itemIndex = 1,
            wasRead = wasRead,
            packageIcon = packageIcon,
        })
    end

    return rows
end

-- Save current mailbox to database
function MailboxScanner:SaveToDatabase()
    if not mailboxOpen then
        return
    end

    local mailboxData = self:ScanMailbox()
    addon.Modules.DB:SaveMailbox(mailboxData)
    addon:Debug("Mailbox data saved")
end

-- Initialize mailbox scanner
function MailboxScanner:Initialize()
    -- Mailbox opened
    addon.Modules.Events:OnMailShow(function()
        mailboxOpen = true
        addon:Debug("Mailbox opened")
        
        -- Delay scan slightly to ensure item info is available
        local frame = CreateFrame("Frame")
        local elapsed = 0
        frame:SetScript("OnUpdate", function()
            elapsed = elapsed + arg1
            if elapsed >= 0.5 then
                frame:SetScript("OnUpdate", nil)
                if mailboxOpen then
                    MailboxScanner:SaveToDatabase()
                end
            end
        end)
    end, "MailboxScanner")

    -- Register for GET_ITEM_INFO_RECEIVED to refresh if item data arrives
    addon.Modules.Events:Register("GET_ITEM_INFO_RECEIVED", function()
        if mailboxOpen then
            addon:Debug("GET_ITEM_INFO_RECEIVED: Refreshing mailbox")
            MailboxScanner:SaveToDatabase()
        end
    end, "MailboxScanner")

    -- Register for MAIL_INBOX_UPDATE to detect when mail content changes
    addon.Modules.Events:Register("MAIL_INBOX_UPDATE", function()
        if mailboxOpen then
            addon:Debug("MAIL_INBOX_UPDATE: Refreshing mailbox")
            MailboxScanner:SaveToDatabase()
        end
    end, "MailboxScanner")

    -- Register for UI_ERROR_MESSAGE to handle "item not found" situations if needed
    -- (Some items might not be in cache and fail silently otherwise)

    -- Mailbox closed
    addon.Modules.Events:OnMailClosed(function()
        -- Final save on close
        self:SaveToDatabase()
        mailboxOpen = false
        addon:Debug("Mailbox closed")
    end, "MailboxScanner")
end

-- Check if mailbox is currently open
function MailboxScanner:IsMailboxOpen()
    return mailboxOpen
end
