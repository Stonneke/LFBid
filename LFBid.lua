-- LFBid.lua - Turtle WoW 1.12

local lfbid_activeItem
local LFbidFrame  -- declare at module level so it persists across function calls
local lfbid_windowOpen = false  -- track if the bidding window is currently visible
local lfbid_timerFrame
local lfbid_openFrame
local lfbid_openWindowOpen = false
local lfbid_openType = "MS"
local lfbid_openItemLink = ""
local lfbid_biddingOpen = false
local lfbid_bidMode = "points"
local lfbid_whisperFrame
local lfbid_bids = {}
local lfbid_rollSeen = {}
local LFBID_ADDON_PREFIX = "LFBid"
local LFDKP_ADDON_PREFIX = "LFDKP"
local lfbid_backdropAlpha = 0.30
local lfbid_useDKPCheck = 1
local RefreshMasterLootButtons

local function ApplyLFBidBackdropAlpha()
    if LFbidFrame then
        LFbidFrame:SetBackdropColor(0, 0, 0, lfbid_backdropAlpha)
    end
    if lfbid_openFrame then
        lfbid_openFrame:SetBackdropColor(0, 0, 0, lfbid_backdropAlpha)
    end
end

print("LFBid loaded. Use /lfbid for commands.")


local function ParseBidMessage(msg, fallbackName)
    if not msg or msg == "" then
        return nil, nil, nil
    end

    local parsedName, points, spec
    local space1 = string.find(msg, " ")
    if space1 then
        parsedName = string.sub(msg, 1, space1 - 1)
        local rest = string.sub(msg, space1 + 1)
        local space2 = string.find(rest, " ")
        if space2 then
            points = tonumber(string.sub(rest, 1, space2 - 1))
            spec = string.sub(rest, space2 + 1)
        end
    end

    local finalName = parsedName or fallbackName
    return finalName, points, spec
end

local function ParseSystemRollMessage(msg)
    if not msg or msg == "" then
        return nil, nil
    end

    local _, _, playerName, rollValue = string.find(msg, "^(.-) rolls (%d+) %(%d+%-%d+%)$")
    if not playerName or not rollValue then
        return nil, nil
    end

    local numericRoll = tonumber(rollValue)
    if not numericRoll then
        return nil, nil
    end

    return playerName, numericRoll
end

local function EscapeChatMessageText(message)
    return string.gsub(tostring(message or ""), "|", "||")
end

local function SendSafeChatMessage(message, chatType, language, target)
    local text = tostring(message or "")
    local safeMessage
    if string.find(text, "|Hitem:") then
        safeMessage = text
    else
        safeMessage = EscapeChatMessageText(text)
    end
    if safeMessage == "" then
        return
    end
    SendChatMessage(safeMessage, chatType, language, target)
end

local function EncodeAddonText(text)
    local encoded = tostring(text or "")
    encoded = string.gsub(encoded, "%%", "%%25")
    encoded = string.gsub(encoded, "|", "%%7C")
    return encoded
end

local function DecodeAddonText(text)
    local decoded = tostring(text or "")
    decoded = string.gsub(decoded, "%%7C", "|")
    decoded = string.gsub(decoded, "%%25", "%%")
    return decoded
end

local function ItemTextForAnnouncement(itemText)
    local text = tostring(itemText or "")
    local _, _, itemName = string.find(text, "|h%[(.-)%]|h")
    if itemName and itemName ~= "" then
        return "[" .. itemName .. "]"
    end
    return text
end

local function ShowItemTooltip(anchorFrame, itemLink)
    if not anchorFrame or not itemLink or itemLink == "" then
        return
    end
    GameTooltip:SetOwner(anchorFrame, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(itemLink)
    GameTooltip:Show()
end

local function HandleItemLinkClick(itemLink)
    if not itemLink or itemLink == "" then
        return
    end

    if HandleModifiedItemClick and HandleModifiedItemClick(itemLink) then
        return
    end

    if IsShiftKeyDown and IsShiftKeyDown() then
        if ChatFrame_OpenChat then
            ChatFrame_OpenChat(itemLink)
            return
        end
        if ChatFrameEditBox and ChatFrameEditBox.Insert then
            ChatFrameEditBox:Insert(itemLink)
            return
        end
    end

    if IsControlKeyDown and IsControlKeyDown() and DressUpItemLink then
        DressUpItemLink(itemLink)
    end
end

local function SendBidMessageToLootMaster(msg, lootMasterName)
    if SendAddonMessage then
        local channel
        if GetNumRaidMembers and GetNumRaidMembers() and GetNumRaidMembers() > 0 then
            channel = "RAID"
        elseif GetNumPartyMembers and GetNumPartyMembers() and GetNumPartyMembers() > 0 then
            channel = "PARTY"
        elseif lootMasterName and lootMasterName ~= "" then
            channel = "WHISPER"
        end

        if channel then
            if channel == "WHISPER" then
                SendAddonMessage(LFBID_ADDON_PREFIX, msg, channel, lootMasterName)
            else
                SendAddonMessage(LFBID_ADDON_PREFIX, msg, channel)
            end
            return true
        end
    end

    if lootMasterName and lootMasterName ~= "" then
        SendSafeChatMessage(msg, "WHISPER", nil, lootMasterName)
        return true
    end

    return false
end

local function GetCurrentLootMasterName()
    if not GetLootMethod then
        return nil
    end

    local method, partyMasterId, raidMasterId = GetLootMethod()
    if method ~= "master" then
        return nil
    end

    if raidMasterId ~= nil then
        if raidMasterId == 0 then
            return UnitName("player")
        end
        return UnitName("raid" .. tostring(raidMasterId))
    end

    if partyMasterId ~= nil then
        if partyMasterId == 0 then
            return UnitName("player")
        end
        return UnitName("party" .. tostring(partyMasterId))
    end

    return UnitName("player")
end

local function IsPlayerMasterLooter()
    local myName = UnitName("player")
    local lootMasterName = GetCurrentLootMasterName()
    if not myName or not lootMasterName then
        return false
    end
    return string.lower(tostring(myName)) == string.lower(tostring(lootMasterName))
end

local function SendBiddingStartMessage(itemLink)
    if not SendAddonMessage then
        return false
    end

    local payload = "START:" .. EncodeAddonText(itemLink)
    if GetNumRaidMembers and GetNumRaidMembers() and GetNumRaidMembers() > 0 then
        SendAddonMessage(LFBID_ADDON_PREFIX, payload, "RAID")
        return true
    end

    if GetNumPartyMembers and GetNumPartyMembers() and GetNumPartyMembers() > 0 then
        SendAddonMessage(LFBID_ADDON_PREFIX, payload, "PARTY")
        return true
    end

    return false
end

local function SendBiddingCloseMessage()
    if not SendAddonMessage then
        return false
    end

    local payload = "CLOSE"
    if GetNumRaidMembers and GetNumRaidMembers() and GetNumRaidMembers() > 0 then
        SendAddonMessage(LFBID_ADDON_PREFIX, payload, "RAID")
        return true
    end

    if GetNumPartyMembers and GetNumPartyMembers() and GetNumPartyMembers() > 0 then
        SendAddonMessage(LFBID_ADDON_PREFIX, payload, "PARTY")
        return true
    end

    return false
end

local function NormalizeSpec(spec)
    if not spec then
        return "Unknown"
    end

    local text = tostring(spec)
    if text == "" then
        return "Unknown"
    end

    local lower = string.lower(text)
    if lower == "ms" then
        return "MS"
    elseif lower == "os" then
        return "OS"
    elseif lower == "alt" then
        return "Alt"
    end

    local first = string.sub(text, 1, 1)
    local rest = string.sub(text, 2)
    return string.upper(first) .. string.lower(rest)
end

local function FindDKPPlayerKey(playerName)
    if type(LFTentDKP) ~= "table" then
        return nil
    end

    local name = tostring(playerName or "")
    if name == "" then
        return nil
    end

    if LFTentDKP[name] ~= nil then
        return name
    end

    local target = string.lower(name)
    for key, _ in pairs(LFTentDKP) do
        if string.lower(tostring(key)) == target then
            return key
        end
    end

    return nil
end

local function GetPlayerDKPInfo(playerName)
    local dkpKey = FindDKPPlayerKey(playerName)
    if not dkpKey then
        return nil, false
    end
    return tonumber(LFTentDKP[dkpKey]), true
end

local function ParseDKPDeltaMessage(msg)
    local text = tostring(msg or "")
    if text == "" then
        return nil, nil
    end

    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    if text == "" then
        return nil, nil
    end

    local lower = string.lower(text)
    if string.sub(lower, 1, 4) == "dkp " then
        text = string.sub(text, 5)
    elseif string.sub(lower, 1, 4) == "dkp:" then
        text = string.sub(text, 5)
    end

    -- Accept payloads from LFDKP like "Alice +1 points".
    text = string.gsub(text, "%s+[Pp][Oo][Ii][Nn][Tt][Ss]?$", "")

    local _, _, name, sign, amount = string.find(text, "^(%S+)%s*([%+%-])%s*(%d+)$")
    if name and sign and amount then
        local delta = tonumber(amount)
        if not delta then
            return nil, nil
        end
        if sign == "-" then
            delta = -delta
        end
        return name, delta
    end

    local _, _, compactName, signedNumber = string.find(text, "^(%S+)%s+([%+%-]%d+)$")
    if compactName and signedNumber then
        return compactName, tonumber(signedNumber)
    end

    return nil, nil
end

local function ApplyDKPDelta(playerName, delta)
    if not playerName or playerName == "" or type(delta) ~= "number" then
        return false
    end

    if type(LFTentDKP) ~= "table" then
        LFTentDKP = {}
    end

    local key = FindDKPPlayerKey(playerName)
    if not key then
        key = tostring(playerName)
    end

    local oldPoints = tonumber(LFTentDKP[key]) or 0
    local newPoints = oldPoints + delta
    LFTentDKP[key] = newPoints

    print("LFBid: DKP updated for " .. key .. ": " .. oldPoints .. " -> " .. newPoints)
    return true
end

local function BidHasEnoughDKP(bid)
    if not lfbid_useDKPCheck then
        return true
    end

    local bidPoints = tonumber(bid and bid.points)
    if not bidPoints then
        return true
    end

    local playerDKP = GetPlayerDKPInfo(bid and bid.name)
    if not playerDKP then
        playerDKP = 0
    end

    return playerDKP >= bidPoints
end

local function IsUnknownZeroBid(bid)
    if not lfbid_useDKPCheck then
        return false
    end

    local bidPoints = tonumber(bid and bid.points)
    if bidPoints ~= 0 then
        return false
    end

    local _, isKnownPlayer = GetPlayerDKPInfo(bid and bid.name)
    return not isKnownPlayer
end

local function RemoveExistingBidForPlayer(playerName)
    if not playerName or playerName == "" then
        return
    end

    local target = string.lower(tostring(playerName))
    for index = table.getn(lfbid_bids), 1, -1 do
        local bid = lfbid_bids[index]
        local bidName = ""
        if bid and bid.name then
            bidName = string.lower(tostring(bid.name))
        end

        if bidName == target then
            table.remove(lfbid_bids, index)
        end
    end
end

local function StartLFBidMessageTimer(messages, intervalOrIntervals, onDone)
    if not lfbid_timerFrame then
        lfbid_timerFrame = CreateFrame("Frame")
    end

    lfbid_timerFrame:Hide()
    lfbid_timerFrame.elapsed = 0
    lfbid_timerFrame.interval = 1
    lfbid_timerFrame.intervals = intervalOrIntervals
    lfbid_timerFrame.messages = messages or {}
    lfbid_timerFrame.index = 1
    lfbid_timerFrame.onDone = onDone

    lfbid_timerFrame:SetScript("OnUpdate", function()
        local elapsed = arg1 or 0
        lfbid_timerFrame.elapsed = (lfbid_timerFrame.elapsed or 0) + elapsed
        local currentInterval = lfbid_timerFrame.interval
        if type(lfbid_timerFrame.intervals) == "table" then
            currentInterval = tonumber(lfbid_timerFrame.intervals[lfbid_timerFrame.index]) or currentInterval
        else
            currentInterval = tonumber(lfbid_timerFrame.intervals) or currentInterval
        end

        if lfbid_timerFrame.elapsed < currentInterval then
            return
        end
        lfbid_timerFrame.elapsed = 0

        local msg = lfbid_timerFrame.messages[lfbid_timerFrame.index]
        if msg then
            SendSafeChatMessage(msg, "RAID")
            lfbid_timerFrame.index = lfbid_timerFrame.index + 1
            return
        end

        lfbid_timerFrame:SetScript("OnUpdate", nil)
        lfbid_timerFrame:Hide()
        if lfbid_timerFrame.onDone then
            lfbid_timerFrame.onDone()
        end
    end)

    lfbid_timerFrame:Show()
end

local function CloseBidding()
    if not lfbid_biddingOpen then
        print("LFBid: Bidding is not active.")
        return
    end

    local messages
    local intervals

    if lfbid_bidMode == "roll" then
        local itemText = lfbid_activeItem or "item"
        local winnerName = nil
        local winnerRoll = nil

        for _, bid in ipairs(lfbid_bids) do
            local bidRoll = tonumber(bid and bid.points) or 0
            local bidName = tostring(bid and bid.name or "")

            if not winnerName or bidRoll > winnerRoll or (bidRoll == winnerRoll and string.lower(bidName) < string.lower(winnerName)) then
                winnerName = bidName
                winnerRoll = bidRoll
            end
        end

        local winnerMsg = "Winner: No valid rolls"
        if winnerName and winnerName ~= "" and winnerRoll ~= nil then
            winnerMsg = "Winner: " .. winnerName .. " with " .. tostring(winnerRoll)
        end

        messages = {
            "Ending rolls for " .. itemText,
            "3",
            "2",
            "1",
            "Rolls have ended",
            winnerMsg,
        }
        intervals = {1, 3, 1, 1, 1, 1}
    else
        local firstMsg
        if lfbid_activeItem then
            firstMsg = "Closing bids on item " .. lfbid_activeItem
        else
            firstMsg = "Closing bids"
        end

        messages = {
            firstMsg,
            "3",
            "2",
            "1",
            "Bids are now closed",
        }
        intervals = {1, 3, 1, 1, 1}
    end

    StartLFBidMessageTimer(messages, intervals, function()
        lfbid_biddingOpen = false
        lfbid_rollSeen = {}
        SendBiddingCloseMessage()
        if RefreshMasterLootButtons then
            RefreshMasterLootButtons()
        end
    end)
end

local function StartPointsBiddingFromMasterWindow()
    if lfbid_bidMode ~= "points" then
        return
    end

    if lfbid_biddingOpen then
        print("LFBid: Bidding is already active.")
        return
    end

    if not lfbid_activeItem or lfbid_activeItem == "" then
        print("LFBid: No active item set.")
        return
    end

    lfbid_openItemLink = lfbid_activeItem
    lfbid_biddingOpen = true
    SendBiddingStartMessage(lfbid_activeItem)
    SendSafeChatMessage("Start bidding on item: " .. lfbid_activeItem, "RAID")

    if RefreshMasterLootButtons then
        RefreshMasterLootButtons()
    end
end

RefreshMasterLootButtons = function()
    if not LFbidFrame then
        return
    end

    if LFbidFrame.startBtn then
        if lfbid_bidMode == "points" then
            LFbidFrame.startBtn:Show()
            if lfbid_biddingOpen then
                LFbidFrame.startBtn:SetText("Started")
                LFbidFrame.startBtn:Disable()
            else
                LFbidFrame.startBtn:SetText("Start Bid")
                LFbidFrame.startBtn:Enable()
            end
        else
            LFbidFrame.startBtn:Hide()
        end
    end

    if LFbidFrame.stopBtn then
        if lfbid_biddingOpen then
            LFbidFrame.stopBtn:Enable()
        else
            LFbidFrame.stopBtn:Disable()
        end
    end
end

local function RefreshLFBidBidList()
    if not LFbidFrame or not LFbidFrame.gridCells then
        print("LFBid: Cannot refresh, frame or grid is nil")
        return
    end

    if lfbid_bidMode == "roll" then
        local specs = {"ROLLS"}
        local grouped = {
            ROLLS = {},
        }

        for _, bid in ipairs(lfbid_bids) do
            if bid then
                table.insert(grouped.ROLLS, bid)
            end
        end

        table.sort(grouped.ROLLS, function(a, b)
            local aRoll = tonumber(a and a.points) or 0
            local bRoll = tonumber(b and b.points) or 0
            if aRoll ~= bRoll then
                return aRoll > bRoll
            end
            local aName = string.lower(tostring(a and a.name or ""))
            local bName = string.lower(tostring(b and b.name or ""))
            return aName < bName
        end)

        local neededCells = 1
        local colWidth = 410
        local cellGapY = 8
        local startX = 10
        local startY = -58

        local cell = LFbidFrame.gridCells[1]
        if not cell then
            cell = CreateFrame("Frame", nil, LFbidFrame)
            cell:SetWidth(colWidth)
            cell:SetHeight(100)
            cell:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 12,
                insets = { left = 3, right = 3, top = 3, bottom = 3 }
            })
            cell:SetBackdropColor(0, 0, 0, 0.2)

            cell.label = cell:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            cell.label:SetPoint("TOPLEFT", cell, "TOPLEFT", 8, -8)
            cell.label:SetJustifyH("LEFT")

            cell.text = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            cell.text:SetPoint("TOPLEFT", cell.label, "BOTTOMLEFT", 0, -2)
            cell.text:SetWidth(colWidth - 16)
            cell.text:SetJustifyH("LEFT")

            LFbidFrame.gridCells[1] = cell
        end

        cell:ClearAllPoints()
        cell:SetPoint("TOPLEFT", LFbidFrame, "TOPLEFT", startX, startY)

        local lines = {}
        for _, bid in ipairs(grouped.ROLLS) do
            table.insert(lines, tostring(bid.name or "") .. " - " .. tostring(bid.points or ""))
        end
        if table.getn(lines) == 0 then
            lines[1] = "-"
        end

        cell.label:SetText(specs[1])
        cell.text:SetText(table.concat(lines, "\n"))
        cell:Show()

        local existingCells = table.getn(LFbidFrame.gridCells)
        for index = neededCells + 1, existingCells do
            local extraCell = LFbidFrame.gridCells[index]
            if extraCell then
                extraCell:Hide()
            end
        end

        LFbidFrame:SetHeight(198 + cellGapY)
        return
    end

    local specs = {"MS", "OS"}
    local grouped = {
        MS = {},
        OS = {},
    }
    local extraSpecs = {}
    local seen = {
        MS = true,
        OS = true,
    }

    for _, bid in ipairs(lfbid_bids) do
        if bid then
            local normalized = NormalizeSpec(bid.spec)
            if not grouped[normalized] then
                grouped[normalized] = {}
            end
            table.insert(grouped[normalized], bid)

            if not seen[normalized] then
                seen[normalized] = true
                table.insert(extraSpecs, normalized)
            end
        end
    end

    table.sort(extraSpecs, function(a, b)
        return string.lower(a) < string.lower(b)
    end)

    for _, spec in ipairs(extraSpecs) do
        table.insert(specs, spec)
    end

    for spec, bidList in pairs(grouped) do
        table.sort(bidList, function(a, b)
            local aPoints = tonumber(a and a.points) or 0
            local bPoints = tonumber(b and b.points) or 0
            if aPoints ~= bPoints then
                return aPoints > bPoints
            end
            local aName = string.lower(tostring(a and a.name or ""))
            local bName = string.lower(tostring(b and b.name or ""))
            return aName < bName
        end)
    end

    local neededCells = table.getn(specs)
    local colWidth = 200
    local cellGapX = 10
    local cellGapY = 8
    local startX = 10
    local startY = -58

    for index = 1, neededCells do
        local spec = specs[index]
        local cell = LFbidFrame.gridCells[index]
        if not cell then
            cell = CreateFrame("Frame", nil, LFbidFrame)
            cell:SetWidth(colWidth)
            cell:SetHeight(100)
            cell:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 12,
                insets = { left = 3, right = 3, top = 3, bottom = 3 }
            })
            cell:SetBackdropColor(0, 0, 0, 0.2)

            cell.label = cell:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            cell.label:SetPoint("TOPLEFT", cell, "TOPLEFT", 8, -8)
            cell.label:SetJustifyH("LEFT")

            cell.text = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            cell.text:SetPoint("TOPLEFT", cell.label, "BOTTOMLEFT", 0, -2)
            cell.text:SetWidth(colWidth - 16)
            cell.text:SetJustifyH("LEFT")

            LFbidFrame.gridCells[index] = cell
        end

        local col
        local modFunc = mod
        if not modFunc and math and math.fmod then
            modFunc = math.fmod
        end
        if modFunc then
            col = modFunc(index - 1, 2)
        else
            col = (index - 1) - (math.floor((index - 1) / 2) * 2)
        end
        local row = math.floor((index - 1) / 2)
        local x = startX + (col * (colWidth + cellGapX))
        local y = startY - (row * (100 + cellGapY))
        cell:ClearAllPoints()
        cell:SetPoint("TOPLEFT", LFbidFrame, "TOPLEFT", x, y)

        local lines = {}
        local bidList = grouped[spec] or {}
        for _, bid in ipairs(bidList) do
            local pointsText = tostring(bid.points or "")
            local nameText = tostring(bid.name or "")
            if IsUnknownZeroBid(bid) then
                nameText = "|cff33aaff" .. nameText .. "|r"
            elseif not BidHasEnoughDKP(bid) then
                nameText = "|cffff2020" .. nameText .. "|r"
            end
            local line = pointsText .. " -- " .. nameText
            table.insert(lines, line)
        end
        if table.getn(lines) == 0 then
            lines[1] = "-"
        end

        cell.label:SetText(spec)
        cell.text:SetText(table.concat(lines, "\n"))
        cell:Show()
    end

    local existingCells = table.getn(LFbidFrame.gridCells)
    for index = neededCells + 1, existingCells do
        local cell = LFbidFrame.gridCells[index]
        if cell then
            cell:Hide()
        end
    end

    local rows = math.ceil(neededCells / 2)
    if rows < 1 then
        rows = 1
    end
    LFbidFrame:SetHeight(90 + rows * (100 + cellGapY))
end

local function LFBidOpenDropDown_OnClick()
    local value = this and this.value
    if not value then
        return
    end
    lfbid_openType = value
    UIDropDownMenu_SetSelectedValue(lfbid_openFrame.dropDown, value)
    UIDropDownMenu_SetText(value, lfbid_openFrame.dropDown)
end

local function LFBidOpenDropDown_Initialize(frame, level)
    local info

    info = UIDropDownMenu_CreateInfo()
    info.text = "MS"
    info.value = "MS"
    info.func = LFBidOpenDropDown_OnClick
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo()
    info.text = "OS"
    info.value = "OS"
    info.func = LFBidOpenDropDown_OnClick
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo()
    info.text = "Alt"
    info.value = "Alt"
    info.func = LFBidOpenDropDown_OnClick
    UIDropDownMenu_AddButton(info, level)
end

local function OpenLFBidOpenWindow()
    if not lfbid_openFrame then
        lfbid_openFrame = CreateFrame("Frame", "LFBidOpenFrame", UIParent)
        lfbid_openFrame:SetWidth(300)
        lfbid_openFrame:SetHeight(170)
        lfbid_openFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        lfbid_openFrame:SetFrameStrata("DIALOG")
        lfbid_openFrame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        lfbid_openFrame:SetBackdropColor(0, 0, 0, lfbid_backdropAlpha)
        lfbid_openFrame:EnableMouse(true)
        lfbid_openFrame:SetMovable(true)
        lfbid_openFrame:RegisterForDrag("LeftButton")
        lfbid_openFrame:SetScript("OnDragStart", function()
            lfbid_openFrame:StartMoving()
        end)
        lfbid_openFrame:SetScript("OnDragStop", function()
            lfbid_openFrame:StopMovingOrSizing()
        end)

        lfbid_openFrame.title = lfbid_openFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lfbid_openFrame.title:SetPoint("TOPLEFT", lfbid_openFrame, "TOPLEFT", 10, -14)
        lfbid_openFrame.title:SetText("LF Tent Bidding")

        lfbid_openFrame.alphaSlider = CreateFrame("Slider", "LFBidOpenAlphaSlider", lfbid_openFrame, "OptionsSliderTemplate")
        lfbid_openFrame.alphaSlider:SetWidth(120)
        lfbid_openFrame.alphaSlider:SetHeight(14)
        lfbid_openFrame.alphaSlider:SetPoint("TOPLEFT", lfbid_openFrame, "TOPLEFT", 150, -16)
        lfbid_openFrame.alphaSlider:SetMinMaxValues(0.05, 0.90)
        lfbid_openFrame.alphaSlider:SetValueStep(0.05)
        lfbid_openFrame.alphaSlider:SetValue(lfbid_backdropAlpha)
        lfbid_openFrame.alphaSlider:SetScript("OnValueChanged", function()
            local value = arg1
            if not value and this and this.GetValue then
                value = this:GetValue()
            end
            if value then
                lfbid_backdropAlpha = value
                ApplyLFBidBackdropAlpha()
            end
        end)
        if getglobal("LFBidOpenAlphaSliderText") then
            getglobal("LFBidOpenAlphaSliderText"):SetText("Background")
        end
        if getglobal("LFBidOpenAlphaSliderLow") then
            getglobal("LFBidOpenAlphaSliderLow"):SetText("5%")
        end
        if getglobal("LFBidOpenAlphaSliderHigh") then
            getglobal("LFBidOpenAlphaSliderHigh"):SetText("90%")
        end

        lfbid_openFrame.pointsLabel = lfbid_openFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lfbid_openFrame.pointsLabel:SetPoint("TOPLEFT", lfbid_openFrame, "TOPLEFT", 10, -58)
        lfbid_openFrame.pointsLabel:SetText("Points")

        lfbid_openFrame.itemLabel = lfbid_openFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lfbid_openFrame.itemLabel:SetPoint("TOPLEFT", lfbid_openFrame, "TOPLEFT", 10, -30)
        lfbid_openFrame.itemLabel:SetText("Item")

        lfbid_openFrame.itemText = lfbid_openFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lfbid_openFrame.itemText:SetPoint("LEFT", lfbid_openFrame.itemLabel, "RIGHT", 10, 0)
        lfbid_openFrame.itemText:SetWidth(190)
        lfbid_openFrame.itemText:SetJustifyH("LEFT")
        lfbid_openFrame.itemText:SetText("-")

        lfbid_openFrame.itemLinkButton = CreateFrame("Button", nil, lfbid_openFrame)
        lfbid_openFrame.itemLinkButton:SetWidth(190)
        lfbid_openFrame.itemLinkButton:SetHeight(18)
        lfbid_openFrame.itemLinkButton:SetPoint("LEFT", lfbid_openFrame.itemText, "LEFT", 0, 0)
        lfbid_openFrame.itemLinkButton.itemLink = nil
        local openItemButton = lfbid_openFrame.itemLinkButton
        lfbid_openFrame.itemLinkButton:SetScript("OnEnter", function()
            ShowItemTooltip(openItemButton, openItemButton.itemLink)
        end)
        lfbid_openFrame.itemLinkButton:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        lfbid_openFrame.itemLinkButton:SetScript("OnClick", function()
            HandleItemLinkClick(openItemButton.itemLink)
        end)

        lfbid_openFrame.pointsEditBox = CreateFrame("EditBox", nil, lfbid_openFrame, "InputBoxTemplate")
        lfbid_openFrame.pointsEditBox:SetWidth(170)
        lfbid_openFrame.pointsEditBox:SetHeight(20)
        lfbid_openFrame.pointsEditBox:SetPoint("LEFT", lfbid_openFrame.pointsLabel, "RIGHT", 10, 0)
        lfbid_openFrame.pointsEditBox:SetAutoFocus(false)

        lfbid_openFrame.typeLabel = lfbid_openFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lfbid_openFrame.typeLabel:SetPoint("TOPLEFT", lfbid_openFrame, "TOPLEFT", 10, -88)
        lfbid_openFrame.typeLabel:SetText("Type")

        lfbid_openFrame.dropDown = CreateFrame("Frame", "LFBidOpenDropDown", lfbid_openFrame, "UIDropDownMenuTemplate")
        lfbid_openFrame.dropDown:SetPoint("LEFT", lfbid_openFrame.typeLabel, "RIGHT", -5, -5)
        UIDropDownMenu_SetWidth(80, lfbid_openFrame.dropDown)
        UIDropDownMenu_Initialize(lfbid_openFrame.dropDown, LFBidOpenDropDown_Initialize)
        UIDropDownMenu_SetSelectedValue(lfbid_openFrame.dropDown, lfbid_openType)
        UIDropDownMenu_SetText(lfbid_openType, lfbid_openFrame.dropDown)

        lfbid_openFrame.closeBtn = CreateFrame("Button", nil, lfbid_openFrame, "UIPanelButtonTemplate")
        lfbid_openFrame.closeBtn:SetWidth(24)
        lfbid_openFrame.closeBtn:SetHeight(24)
        lfbid_openFrame.closeBtn:SetPoint("TOPRIGHT", lfbid_openFrame, "TOPRIGHT", -4, -4)
        lfbid_openFrame.closeBtn:SetFrameLevel(lfbid_openFrame:GetFrameLevel() + 2)
        lfbid_openFrame.closeBtn:SetText("X")
        lfbid_openFrame.closeBtn:SetScript("OnClick", function()
            lfbid_openFrame:Hide()
            lfbid_openWindowOpen = false
        end)

        lfbid_openFrame.bidBtn = CreateFrame("Button", nil, lfbid_openFrame, "UIPanelButtonTemplate")
        lfbid_openFrame.bidBtn:SetWidth(80)
        lfbid_openFrame.bidBtn:SetHeight(22)
        lfbid_openFrame.bidBtn:SetPoint("BOTTOM", lfbid_openFrame, "BOTTOM", 0, 10)
        lfbid_openFrame.bidBtn:SetText("BID")
        lfbid_openFrame.bidBtn:SetScript("OnClick", function()
            if not lfbid_biddingOpen then
                print("LFBid: Bidding is closed.")
                lfbid_openFrame:Hide()
                lfbid_openWindowOpen = false
                return
            end

            local playerName = UnitName("player") or "Player"
            local points = ""
            if lfbid_openFrame.pointsEditBox then
                points = tostring(lfbid_openFrame.pointsEditBox:GetText() or "")
            end
            local spec = lfbid_openType or ""
            local msg = playerName .. " " .. points .. " " .. spec
            local method, masterId = GetLootMethod()
            local lootMasterName
            if method == "master" then
                if masterId == 0 then
                    lootMasterName = UnitName("player")
                else
                    if GetNumRaidMembers() and GetNumRaidMembers() > 0 then
                        lootMasterName = UnitName("raid" .. tostring(masterId))
                    elseif GetNumPartyMembers and GetNumPartyMembers() > 0 then
                        lootMasterName = UnitName("party" .. tostring(masterId))
                    end
                end
            end

            local sent = SendBidMessageToLootMaster(msg, lootMasterName)
            if not sent then
                print("Could not find loot master. Make sure Master Looter is set.")
                return
            end

            if points ~= "" then
                print("LFBid: " .. tostring(spec) .. " bid placed for " .. points .. " points.")
            else
                print("LFBid: " .. tostring(spec) .. " bid placed.")
            end

            if lfbid_openFrame and lfbid_openFrame.pointsEditBox then
                lfbid_openFrame.pointsEditBox:SetText("")
            end

            lfbid_openFrame:Hide()
            lfbid_openWindowOpen = false
        end)
    end

    UIDropDownMenu_SetSelectedValue(lfbid_openFrame.dropDown, lfbid_openType)
    UIDropDownMenu_SetText(lfbid_openType, lfbid_openFrame.dropDown)
    if lfbid_openFrame.itemText then
        if lfbid_openItemLink and lfbid_openItemLink ~= "" then
            lfbid_openFrame.itemText:SetText(lfbid_openItemLink)
            if lfbid_openFrame.itemLinkButton then
                lfbid_openFrame.itemLinkButton.itemLink = lfbid_openItemLink
                lfbid_openFrame.itemLinkButton:EnableMouse(true)
            end
        else
            lfbid_openFrame.itemText:SetText("-")
            if lfbid_openFrame.itemLinkButton then
                lfbid_openFrame.itemLinkButton.itemLink = nil
                lfbid_openFrame.itemLinkButton:EnableMouse(false)
            end
        end
    end
    if lfbid_openFrame.alphaSlider then
        lfbid_openFrame.alphaSlider:SetValue(lfbid_backdropAlpha)
    end
    ApplyLFBidBackdropAlpha()
    lfbid_openWindowOpen = true
    lfbid_openFrame:Show()
end

local function OpenLFBidWindow(itemLink, bidMode)
    -- create the frame only once
    if not LFbidFrame then
        LFbidFrame = CreateFrame("Frame", "LFbidFrame", UIParent)
        LFbidFrame:SetWidth(430)
        LFbidFrame:SetHeight(220)
        LFbidFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        LFbidFrame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        LFbidFrame:SetBackdropColor(0, 0, 0, lfbid_backdropAlpha)
        LFbidFrame:EnableMouse(true)
        LFbidFrame:SetMovable(true)
        LFbidFrame:RegisterForDrag("LeftButton")
        -- drag handlers; use the named variable (no self parameter to avoid nil)
        LFbidFrame:SetScript("OnDragStart", function()
            LFbidFrame:StartMoving()
        end)
        LFbidFrame:SetScript("OnDragStop", function()
            LFbidFrame:StopMovingOrSizing()
        end)

        LFbidFrame.alphaSlider = CreateFrame("Slider", "LFBidMasterAlphaSlider", LFbidFrame, "OptionsSliderTemplate")
        LFbidFrame.alphaSlider:SetWidth(130)
        LFbidFrame.alphaSlider:SetHeight(14)
        LFbidFrame.alphaSlider:SetPoint("TOPLEFT", LFbidFrame, "TOPLEFT", 12, -16)
        LFbidFrame.alphaSlider:SetMinMaxValues(0.05, 0.90)
        LFbidFrame.alphaSlider:SetValueStep(0.05)
        LFbidFrame.alphaSlider:SetValue(lfbid_backdropAlpha)
        LFbidFrame.alphaSlider:SetScript("OnValueChanged", function()
            local value = arg1
            if not value and this and this.GetValue then
                value = this:GetValue()
            end
            if value then
                lfbid_backdropAlpha = value
                ApplyLFBidBackdropAlpha()
            end
        end)
        if getglobal("LFBidMasterAlphaSliderText") then
            getglobal("LFBidMasterAlphaSliderText"):SetText("Background")
        end
        if getglobal("LFBidMasterAlphaSliderLow") then
            getglobal("LFBidMasterAlphaSliderLow"):SetText("5%")
        end
        if getglobal("LFBidMasterAlphaSliderHigh") then
            getglobal("LFBidMasterAlphaSliderHigh"):SetText("90%")
        end

        LFbidFrame.startBtn = CreateFrame("Button", nil, LFbidFrame, "UIPanelButtonTemplate")
        LFbidFrame.startBtn:SetWidth(90)
        LFbidFrame.startBtn:SetHeight(24)
        LFbidFrame.startBtn:SetPoint("TOP", LFbidFrame, "TOP", -48, -6)
        LFbidFrame.startBtn:SetText("Start Bid")
        LFbidFrame.startBtn:SetScript("OnClick", function()
            StartPointsBiddingFromMasterWindow()
        end)

        -- Stop Bids button (top center)
        LFbidFrame.stopBtn = CreateFrame("Button", nil, LFbidFrame, "UIPanelButtonTemplate")
        LFbidFrame.stopBtn:SetWidth(90)
        LFbidFrame.stopBtn:SetHeight(24)
        LFbidFrame.stopBtn:SetPoint("TOP", LFbidFrame, "TOP", 48, -6)
        LFbidFrame.stopBtn:SetText("Stop Bids")
            LFbidFrame.stopBtn:SetScript("OnClick", function()
                CloseBidding()
            end)

        LFbidFrame.dkpCheckBox = CreateFrame("CheckButton", "LFBidUseDKPCheckBox", LFbidFrame, "UICheckButtonTemplate")
        LFbidFrame.dkpCheckBox:SetWidth(24)
        LFbidFrame.dkpCheckBox:SetHeight(24)
        LFbidFrame.dkpCheckBox:SetPoint("TOPRIGHT", LFbidFrame, "TOPRIGHT", -28, -8)
        LFbidFrame.dkpCheckBox:SetChecked(lfbid_useDKPCheck)
        LFbidFrame.dkpCheckBox:SetScript("OnClick", function()
            lfbid_useDKPCheck = this:GetChecked() and 1 or nil
            RefreshLFBidBidList()
        end)
        if getglobal("LFBidUseDKPCheckBoxText") then
            getglobal("LFBidUseDKPCheckBoxText"):SetText("Check DKP")
            getglobal("LFBidUseDKPCheckBoxText"):ClearAllPoints()
            getglobal("LFBidUseDKPCheckBoxText"):SetPoint("RIGHT", LFbidFrame.dkpCheckBox, "LEFT", -2, 1)
        end

        LFbidFrame.text = LFbidFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        if LFbidFrame.text then
            LFbidFrame.text:SetPoint("TOP", LFbidFrame, "TOP", 0, -34)
        end

        LFbidFrame.itemLinkButton = CreateFrame("Button", nil, LFbidFrame)
        LFbidFrame.itemLinkButton:SetWidth(380)
        LFbidFrame.itemLinkButton:SetHeight(18)
        LFbidFrame.itemLinkButton:SetPoint("TOP", LFbidFrame, "TOP", 0, -34)
        LFbidFrame.itemLinkButton.itemLink = nil
        local mlItemButton = LFbidFrame.itemLinkButton
        LFbidFrame.itemLinkButton:SetScript("OnEnter", function()
            ShowItemTooltip(mlItemButton, mlItemButton.itemLink)
        end)
        LFbidFrame.itemLinkButton:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        LFbidFrame.itemLinkButton:SetScript("OnClick", function()
            HandleItemLinkClick(mlItemButton.itemLink)
        end)

        LFbidFrame.gridCells = {}

        -- Close button (top right)
        LFbidFrame.closeBtn = CreateFrame("Button", nil, LFbidFrame, "UIPanelButtonTemplate")
        LFbidFrame.closeBtn:SetWidth(24)
        LFbidFrame.closeBtn:SetHeight(24)
        LFbidFrame.closeBtn:SetPoint("TOPRIGHT", LFbidFrame, "TOPRIGHT", -4, -4)
        LFbidFrame.closeBtn:SetText("X")
        LFbidFrame.closeBtn:SetScript("OnClick", function()
            LFbidFrame:Hide()
            lfbid_windowOpen = false
        end)
    end
    LFbidFrame.text:SetText(itemLink or "")
    if LFbidFrame.itemLinkButton then
        if itemLink and itemLink ~= "" then
            LFbidFrame.itemLinkButton.itemLink = itemLink
            LFbidFrame.itemLinkButton:EnableMouse(true)
        else
            LFbidFrame.itemLinkButton.itemLink = nil
            LFbidFrame.itemLinkButton:EnableMouse(false)
        end
    end
    lfbid_bidMode = bidMode or "points"
    lfbid_bids = {}
    lfbid_rollSeen = {}
    if LFbidFrame.dkpCheckBox then
        LFbidFrame.dkpCheckBox:SetChecked(lfbid_useDKPCheck)
    end
    if LFbidFrame.alphaSlider then
        LFbidFrame.alphaSlider:SetValue(lfbid_backdropAlpha)
    end
    ApplyLFBidBackdropAlpha()
    RefreshMasterLootButtons()
    RefreshLFBidBidList()
    lfbid_windowOpen = true
    LFbidFrame:Show()
end

local function ExtractStartPayload(msg)
    if not msg then
        return nil
    end
    if string.sub(msg, 1, 6) == "START|" then
        return string.sub(msg, 7)
    end
    if string.sub(msg, 1, 6) == "START:" then
        return DecodeAddonText(string.sub(msg, 7))
    end
    return nil
end

local function IsClosePayload(msg)
    return msg == "CLOSE"
end

if not lfbid_whisperFrame then
    lfbid_whisperFrame = CreateFrame("Frame")
    lfbid_whisperFrame:RegisterEvent("CHAT_MSG_WHISPER")
    lfbid_whisperFrame:RegisterEvent("CHAT_MSG_ADDON")
    lfbid_whisperFrame:RegisterEvent("CHAT_MSG_SYSTEM")
    lfbid_whisperFrame:SetScript("OnEvent", function(_, eventName, p1, p2, p3, p4)
        if not lfbid_windowOpen then
            return
        end

        local evt = eventName or event
        if evt == "CHAT_MSG_SYSTEM" then
            if not lfbid_biddingOpen or lfbid_bidMode ~= "roll" then
                return
            end

            local rollName, rollValue = ParseSystemRollMessage(p1 or arg1)
            if not rollName or rollValue == nil then
                return
            end

            local rollKey = string.lower(tostring(rollName))
            if lfbid_rollSeen[rollKey] then
                return
            end

            lfbid_rollSeen[rollKey] = true
            table.insert(lfbid_bids, {
                name = rollName,
                points = rollValue,
                spec = "ROLL",
            })
            RefreshLFBidBidList()
            return
        end

        if not lfbid_biddingOpen then
            return
        end

        if lfbid_bidMode == "roll" then
            return
        end

        local msg
        local sender
        local sourceType = "whisper"

        if evt == "CHAT_MSG_ADDON" then
            local prefix = p1 or arg1
            if prefix ~= LFBID_ADDON_PREFIX then
                return
            end
            msg = p2 or arg2
            sender = p4 or arg4
            sourceType = "addon"
        else
            msg = p1 or arg1
            sender = p2 or arg2
        end

        if not msg or msg == "" or not sender then
            return
        end

        if sourceType == "addon" and ExtractStartPayload(msg) ~= nil then
            return
        end
        if sourceType == "addon" and IsClosePayload(msg) then
            return
        end
        if sourceType == "addon" then
            local addonChannel = p3 or arg3
            local dkpPlayer = ParseDKPDeltaMessage(msg)
            if addonChannel == "RAID" and dkpPlayer then
                return
            end
        end

        local finalName, points, spec = ParseBidMessage(msg, sender)
        
        if finalName and points ~= nil and spec then
            RemoveExistingBidForPlayer(finalName)
            print("LFBid: Received " .. sourceType .. " bid from " .. finalName .. ": " .. points .. " " .. spec)
            table.insert(lfbid_bids, {
                name = finalName,
                points = points,
                spec = spec
            })
            RefreshLFBidBidList()
        else
            print("LFBid: Failed to parse " .. sourceType .. " bid from " .. (sender or "unknown") .. ": " .. (msg or "no message"))
        end
    end)
end

local lfbid_openSyncFrame = CreateFrame("Frame")
lfbid_openSyncFrame:RegisterEvent("CHAT_MSG_ADDON")
lfbid_openSyncFrame:SetScript("OnEvent", function(_, eventName, p1, p2, p3, p4)
    local evt = eventName or event
    if evt ~= "CHAT_MSG_ADDON" then
        return
    end

    local prefix = p1 or arg1
    local msg = p2 or arg2
    local channel = p3 or arg3
    local sender = p4 or arg4
    if not msg or msg == "" then
        return
    end

    -- External addon can push DKP changes in RAID addon channel: "Player +/- Points".
    -- Only process DKP changes from the LFDKP prefix.
    if channel == "RAID" and prefix == LFDKP_ADDON_PREFIX then
        local dkpPlayer, dkpDelta = ParseDKPDeltaMessage(msg)
        if dkpPlayer and dkpDelta then
            if ApplyDKPDelta(dkpPlayer, dkpDelta) and lfbid_windowOpen then
                RefreshLFBidBidList()
            end
            return
        end

        print("LFBid: Received LFDKP message but could not parse: " .. tostring(msg))
        return
    end

    if prefix ~= LFBID_ADDON_PREFIX then
        return
    end

    local startItemLink = ExtractStartPayload(msg)
    local isClose = IsClosePayload(msg)
    if startItemLink == nil and not isClose then
        return
    end

    local myName = UnitName("player")
    if sender and myName and string.lower(sender) == string.lower(myName) then
        return
    end

    if isClose then
        lfbid_biddingOpen = false
        lfbid_openItemLink = ""
        if lfbid_openFrame and lfbid_openWindowOpen then
            lfbid_openFrame:Hide()
            lfbid_openWindowOpen = false
            print("LFBid: Bidding is now closed.")
        end
        return
    end

    lfbid_openItemLink = tostring(startItemLink or "")
    lfbid_biddingOpen = true
    OpenLFBidOpenWindow()
end)

local function HandleLFBidSlash(msg)
    if not msg then msg = "" end
    msg = tostring(msg)

    local cmd, rest
    local spacePos = string.find(msg, " ")
    if spacePos and spacePos > 0 then
        cmd = string.sub(msg, 1, spacePos - 1)
        rest = string.sub(msg, spacePos + 1)
    else
        cmd = msg
        rest = ""
    end

    if cmd then
        if string.lower then
            cmd = string.lower(cmd)
        else
            cmd = cmd:gsub("%u", string.lower)
        end
    end

    if cmd == "start" then
        if not IsPlayerMasterLooter() then
            print("LFBid: /lfbid start and /lfbid roll are only available to the Master Looter.")
            return
        end
        if rest == "" then
            print("Usage: /lfbid start <itemlink>")
            return
        end
        if lfbid_windowOpen then
            print("Bidding window already open. Close it first with the X button.")
            return
        end
        lfbid_activeItem = rest
        lfbid_openItemLink = rest
        lfbid_biddingOpen = false
        lfbid_bidMode = "points"
        OpenLFBidWindow(rest, "points")
    elseif cmd == "roll" then
        if not IsPlayerMasterLooter() then
            print("LFBid: /lfbid start and /lfbid roll are only available to the Master Looter.")
            return
        end
        if rest == "" then
            print("Usage: /lfbid roll <itemlink>")
            return
        end
        if lfbid_windowOpen then
            print("Bidding window already open. Close it first with the X button.")
            return
        end

        lfbid_activeItem = rest
        lfbid_openItemLink = ""
        lfbid_biddingOpen = true
        lfbid_bidMode = "roll"
        lfbid_rollSeen = {}
        SendSafeChatMessage("Start rolling for item: " .. rest, "RAID")
        OpenLFBidWindow(rest, "roll")
    elseif cmd == "open" then
        if lfbid_openWindowOpen then
            print("LFBid open window already open.")
            return
        end
        OpenLFBidOpenWindow()
    else
        print("LFbid commands:\n  /lfbid start <itemlink>\n  /lfbid roll <itemlink>\n  /lfbid open")
    end
end

local function RegisterLFBidSlashCommand()
    SlashCmdList = SlashCmdList or {}
    SLASH_LFBID1 = "/lfbid"
    SlashCmdList["LFBID"] = HandleLFBidSlash
end

RegisterLFBidSlashCommand()

local lfbid_initFrame = CreateFrame("Frame")
lfbid_initFrame:RegisterEvent("PLAYER_LOGIN")
lfbid_initFrame:SetScript("OnEvent", function()
    RegisterLFBidSlashCommand()
end)
