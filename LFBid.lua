-- LFBid.lua - Turtle WoW 1.12

local lfbid_activeItem
local LFbidFrame  -- declare at module level so it persists across function calls
local lfbid_windowOpen = false  -- track if the bidding window is currently visible
local lfbid_timerFrame
local lfbid_openFrame
local lfbid_openWindowOpen = false
local lfbid_optionsFrame
local lfbid_optionsWindowOpen = false
local lfbid_dkpSheetFrame
local lfbid_dkpSheetWindowOpen = false
local lfbid_dkpSheetScrollOffset = 0
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
local lfbid_dkpCheckTier = 1
local lfbid_bidListScrollOffset = 0
local lfbid_bidListMaxOffset = 0
local lfbid_specScrollOffsets = {}
local lfbid_hoveredSpec = nil
local lfbid_openAltBid = false
local LFBID_ROLL_VISIBLE_ROWS = 10
local LFBID_POINTS_VISIBLE_ROWS = 6
local RefreshMasterLootButtons
local RefreshLFBidBidList
local RefreshLFBidDKPSheetWindow
local OpenLFBidWindow

local function ApplyLFBidBackdropAlpha()
    if LFbidFrame then
        LFbidFrame:SetBackdropColor(0, 0, 0, lfbid_backdropAlpha)
    end
    if lfbid_openFrame then
        lfbid_openFrame:SetBackdropColor(0, 0, 0, lfbid_backdropAlpha)
    end
    if lfbid_optionsFrame then
        lfbid_optionsFrame:SetBackdropColor(0, 0, 0, lfbid_backdropAlpha)
    end
    if lfbid_dkpSheetFrame then
        lfbid_dkpSheetFrame:SetBackdropColor(0, 0, 0, lfbid_backdropAlpha)
    end
end

print("LFBid loaded. Use /lfbid for commands.")


local function ParseBidMessage(msg, fallbackName)
    if not msg or msg == "" then
        return nil, nil, nil, false
    end

    local parsedName, points, spec, altBid
    local space1 = string.find(msg, " ")
    if space1 then
        parsedName = string.sub(msg, 1, space1 - 1)
        local rest = string.sub(msg, space1 + 1)
        local space2 = string.find(rest, " ")
        if space2 then
            points = tonumber(string.sub(rest, 1, space2 - 1))
            local specPart = string.sub(rest, space2 + 1)
            local space3 = string.find(specPart, " ")
            if space3 then
                spec = string.sub(specPart, 1, space3 - 1)
                local altMarker = string.sub(specPart, space3 + 1)
                if altMarker and string.lower(tostring(altMarker)) == "alt" then
                    altBid = true
                end
            else
                spec = specPart
            end
        end
    end

    local finalName = parsedName or fallbackName
    return finalName, points, spec, altBid and true or false
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

local function IsPlayerFounderOrBanker()
    if not GetGuildInfo then
        return false
    end

    local _, rankName = GetGuildInfo("player")
    if not rankName or rankName == "" then
        return false
    end

    local normalizedRank = string.lower(tostring(rankName))
    return normalizedRank == "founder" or normalizedRank == "banker"
end

local function IsPlayerGuildRankAlt()
    if not GetGuildInfo then
        return false
    end

    local _, rankName = GetGuildInfo("player")
    if not rankName or rankName == "" then
        return false
    end

    local normalizedRank = string.lower(tostring(rankName))
    return normalizedRank == "alt" or normalizedRank == "alts"
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
    elseif lower == "alt" or lower == "tmog" or lower == "t-mog" then
        return "T-MOG"
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
        return nil, nil, false
    end

    local entry = LFTentDKP[dkpKey]
    local directValue = tonumber(entry)
    if directValue ~= nil then
        return directValue, 0, true
    end

    if type(entry) == "table" then
        local tier1 = tonumber(entry.tier1 or entry.t1 or entry[1] or entry["Tier 1"] or entry.Tier1 or entry.points1 or entry.dkp1) or 0
        local tier2 = tonumber(entry.tier2 or entry.t2 or entry[2] or entry["Tier 2"] or entry.Tier2 or entry.points2 or entry.dkp2) or 0
        return tier1, tier2, true
    end

    return 0, 0, true
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

    local entry = LFTentDKP[key]
    local oldPoints = 0
    local newPoints = 0

    if type(entry) == "table" then
        oldPoints = tonumber(entry.tier1 or entry.t1 or entry[1] or entry["Tier 1"] or entry.Tier1 or entry.points1 or entry.dkp1) or 0
        newPoints = oldPoints + delta

        if entry.t1 ~= nil then
            entry.t1 = newPoints
        elseif entry.tier1 ~= nil then
            entry.tier1 = newPoints
        elseif entry[1] ~= nil then
            entry[1] = newPoints
        elseif entry["Tier 1"] ~= nil then
            entry["Tier 1"] = newPoints
        elseif entry.Tier1 ~= nil then
            entry.Tier1 = newPoints
        elseif entry.points1 ~= nil then
            entry.points1 = newPoints
        elseif entry.dkp1 ~= nil then
            entry.dkp1 = newPoints
        else
            entry.t1 = newPoints
        end

        LFTentDKP[key] = entry
    else
        oldPoints = tonumber(entry) or 0
        newPoints = oldPoints + delta
        LFTentDKP[key] = newPoints
    end

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

    local playerTier1, playerTier2 = GetPlayerDKPInfo(bid and bid.name)
    local playerDKP
    if lfbid_dkpCheckTier == 2 then
        playerDKP = playerTier2
    else
        playerDKP = playerTier1
    end
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

    local _, _, isKnownPlayer = GetPlayerDKPInfo(bid and bid.name)
    return not isKnownPlayer
end

local function SetDKPCheckTier(tier)
    if tier == 2 then
        lfbid_dkpCheckTier = 2
    else
        lfbid_dkpCheckTier = 1
    end

    if lfbid_optionsFrame then
        if lfbid_optionsFrame.t1RaidCheck then
            lfbid_optionsFrame.t1RaidCheck:SetChecked(lfbid_dkpCheckTier == 1)
        end
        if lfbid_optionsFrame.t2RaidCheck then
            lfbid_optionsFrame.t2RaidCheck:SetChecked(lfbid_dkpCheckTier == 2)
        end
    end

    if LFbidFrame and LFbidFrame.gridCells then
        RefreshLFBidBidList()
    end
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

RefreshLFBidBidList = function()
    if not LFbidFrame or not LFbidFrame.gridCells then
        print("LFBid: Cannot refresh, frame or grid is nil")
        return
    end

    local function ClampBidListOffset(maxOffset)
        local maxValue = tonumber(maxOffset) or 0
        if maxValue < 0 then
            maxValue = 0
        end

        if lfbid_bidListScrollOffset < 0 then
            lfbid_bidListScrollOffset = 0
        elseif lfbid_bidListScrollOffset > maxValue then
            lfbid_bidListScrollOffset = maxValue
        end

        lfbid_bidListMaxOffset = maxValue
    end

    local function UpdateBidListScrollBar(totalEntries)
        local totalCount = tonumber(totalEntries) or 0
        if totalCount < 0 then
            totalCount = 0
        end

        local maxOffset = totalCount - LFBID_ROLL_VISIBLE_ROWS
        if maxOffset < 0 then
            maxOffset = 0
        end

        ClampBidListOffset(maxOffset)
        if not LFbidFrame.bidScrollBar then
            return
        end

        LFbidFrame.bidScrollBar:SetMinMaxValues(0, lfbid_bidListMaxOffset)
        LFbidFrame.bidScrollBar:SetValueStep(1)
        LFbidFrame.bidScrollBar:SetValue(lfbid_bidListScrollOffset)

        if lfbid_bidListMaxOffset > 0 then
            LFbidFrame.bidScrollBar:Show()
        else
            LFbidFrame.bidScrollBar:Hide()
        end
    end

    local function GetFixedBidCellHeight(visibleRows)
        local headerHeight = 20
        local lineHeight = 12
        local bottomPadding = 10
        local rows = tonumber(visibleRows) or 1
        if rows < 1 then
            rows = 1
        end
        return headerHeight + (rows * lineHeight) + bottomPadding
    end

    local function CountBidsForSpec(specName)
        local target = tostring(specName or "")
        if target == "" then
            return 0
        end

        local count = 0
        for _, bid in ipairs(lfbid_bids) do
            if bid and NormalizeSpec(bid.spec) == target then
                count = count + 1
            end
        end
        return count
    end

    local function AttachSpecScrollBar(cell)
        if not cell or cell.scrollBar then
            return
        end

        cell:EnableMouse(true)
        cell:SetScript("OnEnter", function()
            if cell.specKey and cell.specKey ~= "" then
                lfbid_hoveredSpec = cell.specKey
            end
        end)
        cell:SetScript("OnLeave", function()
            if lfbid_hoveredSpec == cell.specKey then
                lfbid_hoveredSpec = nil
            end
        end)

        cell.scrollBar = CreateFrame("Slider", nil, cell)
        cell.scrollBar:SetPoint("TOPRIGHT", cell, "TOPRIGHT", -4, -24)
        cell.scrollBar:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -4, 8)
        cell.scrollBar:SetWidth(10)
        if cell.scrollBar.SetOrientation then
            cell.scrollBar:SetOrientation("VERTICAL")
        end
        cell.scrollBar:SetMinMaxValues(0, 0)
        cell.scrollBar:SetValueStep(1)
        cell.scrollBar:SetValue(0)
        cell.scrollBar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
        cell.scrollBar:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 12, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 }
        })
        cell.scrollBar:SetBackdropColor(0, 0, 0, 0.20)

        local ownerCell = cell
        cell.scrollBar:SetScript("OnValueChanged", function()
            local specKey = ownerCell.specKey
            if not specKey or specKey == "" then
                return
            end

            local value = tonumber(arg1) or 0
            if value < 0 then
                value = 0
            end

            local maxOffset = CountBidsForSpec(specKey) - LFBID_POINTS_VISIBLE_ROWS
            if maxOffset < 0 then
                maxOffset = 0
            end

            local nextOffset = math.floor(value + 0.5)
            if nextOffset > maxOffset then
                nextOffset = maxOffset
            elseif nextOffset < 0 then
                nextOffset = 0
            end

            if nextOffset ~= (lfbid_specScrollOffsets[specKey] or 0) then
                lfbid_specScrollOffsets[specKey] = nextOffset
                RefreshLFBidBidList()
            end
        end)
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
        local colWidth = 392
        local startX = 10
        local startY = -76
        local frameTopOffset = 76
        local frameBottomPadding = 40
        local cellHeight = GetFixedBidCellHeight(LFBID_ROLL_VISIBLE_ROWS)

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

        cell:SetWidth(colWidth)
        if cell.text then
            cell.text:SetWidth(colWidth - 16)
        end
        if cell.scrollBar then
            cell.scrollBar:Hide()
        end
        cell:ClearAllPoints()
        cell:SetPoint("TOPLEFT", LFbidFrame, "TOPLEFT", startX, startY)

        local totalRolls = table.getn(grouped.ROLLS)
        UpdateBidListScrollBar(totalRolls)

        local lines = {}
        local startIndex = lfbid_bidListScrollOffset + 1
        local endIndex = lfbid_bidListScrollOffset + LFBID_ROLL_VISIBLE_ROWS
        for idx = startIndex, endIndex do
            local bid = grouped.ROLLS[idx]
            if bid then
                table.insert(lines, tostring(bid.name or "") .. " - " .. tostring(bid.points or ""))
            end
        end
        if table.getn(lines) == 0 then
            lines[1] = "-"
        end

        cell:SetHeight(cellHeight)

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

        LFbidFrame:SetHeight(frameTopOffset + cellHeight + frameBottomPadding)
        return
    end

    if LFbidFrame.bidScrollBar then
        LFbidFrame.bidScrollBar:Hide()
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
    local colWidth = 191
    local cellGapX = 10
    local cellGapY = 8
    local startX = 10
    local startY = -76
    local frameTopOffset = 76
    local frameBottomPadding = 40
    local rowHeights = {}
    local specCellHeight = {}
    local specLines = {}
    local fixedCellHeight = GetFixedBidCellHeight(LFBID_POINTS_VISIBLE_ROWS)
    local specMaxOffsets = {}

    for _, spec in ipairs(specs) do
        local entryCount = table.getn(grouped[spec] or {})
        local maxOffset = entryCount - LFBID_POINTS_VISIBLE_ROWS
        if maxOffset < 0 then
            maxOffset = 0
        end

        local offset = tonumber(lfbid_specScrollOffsets[spec]) or 0
        if offset < 0 then
            offset = 0
        elseif offset > maxOffset then
            offset = maxOffset
        end

        lfbid_specScrollOffsets[spec] = offset
        specMaxOffsets[spec] = maxOffset
    end

    for _, spec in ipairs(specs) do
        local lines = {}
        local bidList = grouped[spec] or {}
        local startIndex = (lfbid_specScrollOffsets[spec] or 0) + 1
        local endIndex = (lfbid_specScrollOffsets[spec] or 0) + LFBID_POINTS_VISIBLE_ROWS
        for idx = startIndex, endIndex do
            local bid = bidList[idx]
            if bid then
                local pointsText = tostring(bid.points or "")
                local nameText = tostring(bid.name or "")
                if IsUnknownZeroBid(bid) then
                    nameText = "|cff33aaff" .. nameText .. "|r"
                elseif not BidHasEnoughDKP(bid) then
                    nameText = "|cffff2020" .. nameText .. "|r"
                end
                local line = pointsText .. " -- " .. nameText
                if bid.altBid then
                    line = pointsText .. " - ALT - " .. nameText
                end
                table.insert(lines, line)
            end
        end
        if table.getn(lines) == 0 then
            lines[1] = "-"
        end

        specLines[spec] = lines
        specCellHeight[spec] = fixedCellHeight
    end

    for index = 1, neededCells do
        local spec = specs[index]
        local cell = LFbidFrame.gridCells[index]
        if not cell then
            cell = CreateFrame("Frame", nil, LFbidFrame)
            cell:SetWidth(colWidth)
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
            cell.text:SetWidth(colWidth - 30)
            cell.text:SetJustifyH("LEFT")

            LFbidFrame.gridCells[index] = cell
        end

        AttachSpecScrollBar(cell)

        cell:SetWidth(colWidth)
        if cell.text then
            cell.text:SetWidth(colWidth - 30)
        end
        cell:SetHeight(specCellHeight[spec] or 100)
        cell.specKey = spec

        if cell.scrollBar then
            local maxOffset = specMaxOffsets[spec] or 0
            local offset = lfbid_specScrollOffsets[spec] or 0
            cell.scrollBar:SetMinMaxValues(0, maxOffset)
            cell.scrollBar:SetValueStep(1)
            cell.scrollBar:SetValue(offset)
            if maxOffset > 0 then
                cell.scrollBar:Show()
            else
                cell.scrollBar:Hide()
            end
        end

        local row = math.floor((index - 1) / 2)
        local rowIndex = row + 1
        local targetHeight = specCellHeight[spec] or 100
        if not rowHeights[rowIndex] or targetHeight > rowHeights[rowIndex] then
            rowHeights[rowIndex] = targetHeight
        end

        cell.label:SetText(spec)
        cell.text:SetText(table.concat(specLines[spec], "\n"))
        cell:Show()
    end

    local rowCount = math.ceil(neededCells / 2)
    local currentY = startY
    for rowIndex = 1, rowCount do
        local rowTopY = currentY
        for col = 0, 1 do
            local index = ((rowIndex - 1) * 2) + col + 1
            if index <= neededCells then
                local x = startX + (col * (colWidth + cellGapX))
                local cell = LFbidFrame.gridCells[index]
                if cell then
                    cell:ClearAllPoints()
                    cell:SetPoint("TOPLEFT", LFbidFrame, "TOPLEFT", x, rowTopY)
                end
            end
        end

        local rowHeight = rowHeights[rowIndex] or 100
        currentY = currentY - rowHeight - cellGapY
    end

    local existingCells = table.getn(LFbidFrame.gridCells)
    for index = neededCells + 1, existingCells do
        local cell = LFbidFrame.gridCells[index]
        if cell then
            if cell.scrollBar then
                cell.scrollBar:Hide()
            end
            cell:Hide()
        end
    end

    local totalGridHeight = 0
    if rowCount < 1 then
        rowCount = 1
    end
    for rowIndex = 1, rowCount do
        totalGridHeight = totalGridHeight + (rowHeights[rowIndex] or 100)
    end
    if rowCount > 1 then
        totalGridHeight = totalGridHeight + ((rowCount - 1) * cellGapY)
    end

    LFbidFrame:SetHeight(frameTopOffset + totalGridHeight + frameBottomPadding)
end

local function RunLFBidRollTestSimulation(requestedCount)
    local count = tonumber(requestedCount) or 40
    if count < 1 then
        count = 1
    elseif count > 200 then
        count = 200
    end

    local testItem = "[LFBid Test Item]"
    lfbid_activeItem = testItem
    lfbid_openItemLink = ""
    lfbid_biddingOpen = true
    lfbid_bidMode = "roll"
    lfbid_rollSeen = {}

    OpenLFBidWindow(testItem, "roll")

    lfbid_bids = {}
    local randomFunc
    if math and math.random then
        randomFunc = math.random
    elseif random then
        randomFunc = random
    end

    for idx = 1, count do
        local rollValue = 1
        if randomFunc then
            rollValue = randomFunc(1, 100)
        end

        table.insert(lfbid_bids, {
            name = "TestRoller" .. tostring(idx),
            points = rollValue,
            spec = "ROLLS",
        })
    end

    RefreshLFBidBidList()
    print("LFBid: Simulated " .. tostring(count) .. " rolls in the ML frame.")
end

local function RunLFBidPointsTestSimulation()
    local testItem = "[LFBid Test Bids]"
    local specs = {"MS", "OS", "T-MOG"}

    lfbid_activeItem = testItem
    lfbid_openItemLink = testItem
    lfbid_biddingOpen = false
    lfbid_bidMode = "points"
    lfbid_rollSeen = {}

    OpenLFBidWindow(testItem, "points")

    lfbid_bids = {}
    lfbid_specScrollOffsets = {}

    for specIndex, spec in ipairs(specs) do
        for idx = 1, 11 do
            local basePoints = 130 - (idx * 4)
            local adjustedPoints = basePoints - ((specIndex - 1) * 3)
            if adjustedPoints < 1 then
                adjustedPoints = 1
            end

            table.insert(lfbid_bids, {
                name = "Test" .. spec .. idx,
                points = adjustedPoints,
                spec = spec,
            })
        end
    end

    RefreshLFBidBidList()
    print("LFBid: Simulated 11 bids each for MS, OS, and T-MOG.")
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
    info.text = "T-MOG"
    info.value = "T-MOG"
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

        lfbid_openFrame.altCheck = CreateFrame("CheckButton", "LFBidOpenAltCheckButton", lfbid_openFrame, "UICheckButtonTemplate")
        lfbid_openFrame.altCheck:SetPoint("LEFT", lfbid_openFrame.dropDown, "RIGHT", 6, -1)
        lfbid_openFrame.altCheck:SetWidth(24)
        lfbid_openFrame.altCheck:SetHeight(24)
        lfbid_openFrame.altCheck:SetChecked(lfbid_openAltBid and 1 or nil)
        lfbid_openFrame.altCheck:SetScript("OnClick", function()
            lfbid_openAltBid = this:GetChecked() and true or false
        end)
        if getglobal("LFBidOpenAltCheckButtonText") then
            getglobal("LFBidOpenAltCheckButtonText"):SetText("ALT")
        end

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
            local useAltTag = false
            if lfbid_openFrame.altCheck then
                useAltTag = lfbid_openFrame.altCheck:GetChecked() and true or false
            end
            lfbid_openAltBid = useAltTag

            local msg = playerName .. " " .. points .. " " .. spec
            if useAltTag then
                msg = msg .. " ALT"
            end
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

    if IsPlayerGuildRankAlt() then
        lfbid_openAltBid = true
    end

    if lfbid_openFrame.altCheck then
        lfbid_openFrame.altCheck:SetChecked(lfbid_openAltBid and 1 or nil)
    end
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

local function GetTierPointsFromDKPEntry(entry)
    local directValue = tonumber(entry)
    if directValue ~= nil then
        return directValue, 0
    end

    if type(entry) ~= "table" then
        return 0, 0
    end

    local tier1 = tonumber(entry.tier1 or entry.t1 or entry[1] or entry["Tier 1"] or entry.Tier1 or entry.points1 or entry.dkp1) or 0
    local tier2 = tonumber(entry.tier2 or entry.t2 or entry[2] or entry["Tier 2"] or entry.Tier2 or entry.points2 or entry.dkp2) or 0
    return tier1, tier2
end

local function EnsureDKPDataLoaded()
    if type(LFTentDKP) == "table" and next(LFTentDKP) ~= nil then
        return
    end

    if type(LFTentDKPDefaults) == "table" and next(LFTentDKPDefaults) ~= nil then
        LFTentDKP = LFTentDKPDefaults
    end
end

local function BuildSortedDKPSheetRows()
    EnsureDKPDataLoaded()

    local rows = {}
    if type(LFTentDKP) ~= "table" then
        return rows
    end

    for playerName, value in pairs(LFTentDKP) do
        local tier1, tier2 = GetTierPointsFromDKPEntry(value)
        table.insert(rows, {
            player = tostring(playerName or ""),
            tier1 = tier1,
            tier2 = tier2,
        })
    end

    table.sort(rows, function(a, b)
        return string.lower(tostring(a.player or "")) < string.lower(tostring(b.player or ""))
    end)

    return rows
end

local function NormalizeDKPPlayerName(name)
    local text = tostring(name or "")
    local dashPos = string.find(text, "-")
    if dashPos and dashPos > 1 then
        text = string.sub(text, 1, dashPos - 1)
    end
    return string.lower(text)
end

local function SyncDKPToGuildNotes()
    EnsureDKPDataLoaded()

    if type(LFTentDKP) ~= "table" then
        print("LFBid: DKP table is empty or invalid.")
        return
    end

    if not GetNumGuildMembers or not GetGuildRosterInfo or not GuildRoster then
        print("LFBid: Guild roster API is not available.")
        return
    end

    if not GuildRosterSetPublicNote and not GuildRosterSetNote then
        print("LFBid: Public guild note API is not available.")
        return
    end

    local previousShowOffline = nil
    if SetGuildRosterShowOffline then
        if GetGuildRosterShowOffline then
            previousShowOffline = GetGuildRosterShowOffline() and 1 or 0
        end
        SetGuildRosterShowOffline(1)
    end

    GuildRoster()

    local totalMembers = tonumber(GetNumGuildMembers(true)) or tonumber(GetNumGuildMembers()) or 0
    if totalMembers <= 0 then
        print("LFBid: No guild members found in roster.")
        if SetGuildRosterShowOffline and previousShowOffline ~= nil then
            SetGuildRosterShowOffline(previousShowOffline)
            GuildRoster()
        end
        return
    end

    local guildIndexByName = {}
    local idx
    for idx = 1, totalMembers do
        local rosterName = GetGuildRosterInfo(idx)
        local lookup = NormalizeDKPPlayerName(rosterName)
        if lookup ~= "" then
            guildIndexByName[lookup] = idx
        end
    end

    local updated = 0
    local missing = 0
    local writeFailed = 0
    local replacedExisting = 0
    local wroteFresh = 0
    local playerName, value
    for playerName, value in pairs(LFTentDKP) do
        local lookup = NormalizeDKPPlayerName(playerName)
        local memberIndex = guildIndexByName[lookup]

        if memberIndex then
            local tier1, tier2 = GetTierPointsFromDKPEntry(value)
            local dkpToken = "[" .. tostring(tier1) .. ":" .. tostring(tier2) .. "]"

            local _, _, _, _, _, _, existingPublicNote = GetGuildRosterInfo(memberIndex)
            local currentNote = tostring(existingPublicNote or "")
            local hadDKPToken = string.find(currentNote, "%[%s*%-?%d+%s*:%s*%-?%d+%s*%]") ~= nil

            local noteText
            if hadDKPToken then
                noteText = string.gsub(currentNote, "%[%s*%-?%d+%s*:%s*%-?%d+%s*%]", dkpToken, 1)
                replacedExisting = replacedExisting + 1
            else
                noteText = dkpToken
                wroteFresh = wroteFresh + 1
            end

            local wrote = false
            if GuildRosterSetPublicNote then
                GuildRosterSetPublicNote(memberIndex, noteText)
                wrote = true
            elseif GuildRosterSetNote then
                GuildRosterSetNote(memberIndex, noteText)
                wrote = true
            end

            if wrote then
                updated = updated + 1
            else
                writeFailed = writeFailed + 1
            end
        else
            missing = missing + 1
        end
    end

    if SetGuildRosterShowOffline and previousShowOffline ~= nil then
        SetGuildRosterShowOffline(previousShowOffline)
    end
    GuildRoster()
    print("LFBid: DKP => Notes complete. Updated " .. updated .. " (replaced " .. replacedExisting .. ", new " .. wroteFresh .. "), missing " .. missing .. ", failed " .. writeFailed .. ".")
end

local function SyncGuildNotesToDKP()
    if not GetNumGuildMembers or not GetGuildRosterInfo or not GuildRoster then
        print("LFBid: Guild roster API is not available.")
        return
    end

    local previousShowOffline = nil
    if SetGuildRosterShowOffline then
        if GetGuildRosterShowOffline then
            previousShowOffline = GetGuildRosterShowOffline() and 1 or 0
        end
        SetGuildRosterShowOffline(1)
    end

    GuildRoster()

    local totalMembers = tonumber(GetNumGuildMembers(true)) or tonumber(GetNumGuildMembers()) or 0
    if totalMembers <= 0 then
        print("LFBid: No guild members found in roster.")
        if SetGuildRosterShowOffline and previousShowOffline ~= nil then
            SetGuildRosterShowOffline(previousShowOffline)
            GuildRoster()
        end
        return
    end

    if type(LFTentDKP) ~= "table" then
        LFTentDKP = {}
    end

    local updated = 0
    local unchanged = 0
    local skipped = 0
    local idx
    for idx = 1, totalMembers do
        local rosterName, _, _, _, _, _, publicNote = GetGuildRosterInfo(idx)
        local _, _, tier1Text, tier2Text = string.find(tostring(publicNote or ""), "%[%s*(%-?%d+)%s*:%s*(%-?%d+)%s*%]")

        if rosterName and tier1Text and tier2Text then
            local tier1 = tonumber(tier1Text)
            local tier2 = tonumber(tier2Text)

            if tier1 ~= nil and tier2 ~= nil then
                local key = FindDKPPlayerKey(rosterName)
                if not key then
                    key = tostring(rosterName)
                end

                local current = LFTentDKP[key]
                local currentT1, currentT2 = GetTierPointsFromDKPEntry(current)
                if currentT1 == tier1 and currentT2 == tier2 then
                    unchanged = unchanged + 1
                else
                    LFTentDKP[key] = { t1 = tier1, t2 = tier2 }
                    updated = updated + 1
                end
            else
                skipped = skipped + 1
            end
        else
            skipped = skipped + 1
        end
    end

    if SetGuildRosterShowOffline and previousShowOffline ~= nil then
        SetGuildRosterShowOffline(previousShowOffline)
    end
    GuildRoster()

    if lfbid_dkpSheetWindowOpen then
        RefreshLFBidDKPSheetWindow()
    end

    print("LFBid: Notes => DKP complete. Updated " .. updated .. ", unchanged " .. unchanged .. ", skipped " .. skipped .. ".")
end

RefreshLFBidDKPSheetWindow = function()
    if not lfbid_dkpSheetFrame or not lfbid_dkpSheetFrame.rows then
        return
    end

    local dataRows = BuildSortedDKPSheetRows()
    local maxRows = table.getn(lfbid_dkpSheetFrame.rows)
    local rowCount = table.getn(dataRows)
    local maxOffset = rowCount - maxRows
    if maxOffset < 0 then
        maxOffset = 0
    end

    if lfbid_dkpSheetScrollOffset > maxOffset then
        lfbid_dkpSheetScrollOffset = maxOffset
    end
    if lfbid_dkpSheetScrollOffset < 0 then
        lfbid_dkpSheetScrollOffset = 0
    end

    if lfbid_dkpSheetFrame.scrollBar then
        lfbid_dkpSheetFrame.scrollBar:SetMinMaxValues(0, maxOffset)
        lfbid_dkpSheetFrame.updatingScrollBar = true
        lfbid_dkpSheetFrame.scrollBar:SetValue(lfbid_dkpSheetScrollOffset)
        lfbid_dkpSheetFrame.updatingScrollBar = false

        if maxOffset > 0 then
            lfbid_dkpSheetFrame.scrollBar:SetAlpha(1)
        else
            lfbid_dkpSheetFrame.scrollBar:SetAlpha(0.5)
        end
    end

    local startIndex = lfbid_dkpSheetScrollOffset + 1

    local i
    for i = 1, maxRows do
        local rowWidget = lfbid_dkpSheetFrame.rows[i]
        local rowData = dataRows[startIndex + i - 1]
        if rowData then
            rowWidget.player:SetText(rowData.player)
            rowWidget.tier1:SetText(tostring(rowData.tier1))
            rowWidget.tier2:SetText(tostring(rowData.tier2))
            rowWidget.player:Show()
            rowWidget.tier1:Show()
            rowWidget.tier2:Show()
        else
            rowWidget.player:SetText("")
            rowWidget.tier1:SetText("")
            rowWidget.tier2:SetText("")
            rowWidget.player:Hide()
            rowWidget.tier1:Hide()
            rowWidget.tier2:Hide()
        end
    end

    if rowCount == 0 then
        lfbid_dkpSheetFrame.emptyText:SetText("No DKP entries found.")
        lfbid_dkpSheetFrame.emptyText:Show()
    else
        lfbid_dkpSheetFrame.emptyText:Hide()
    end

    if rowCount > 0 then
        local endIndex = startIndex + maxRows - 1
        if endIndex > rowCount then
            endIndex = rowCount
        end
        lfbid_dkpSheetFrame.moreText:SetText("Showing " .. tostring(startIndex) .. "-" .. tostring(endIndex) .. " of " .. tostring(rowCount))
        lfbid_dkpSheetFrame.moreText:Show()
    else
        lfbid_dkpSheetFrame.moreText:Hide()
    end
end

local function OpenLFBidDKPSheetWindow()
    if not lfbid_dkpSheetFrame then
        lfbid_dkpSheetFrame = CreateFrame("Frame", "LFBidDKPSheetFrame", UIParent)
        lfbid_dkpSheetFrame:SetWidth(420)
        lfbid_dkpSheetFrame:SetHeight(410)
        lfbid_dkpSheetFrame:SetPoint("CENTER", UIParent, "CENTER", 280, 40)
        lfbid_dkpSheetFrame:SetFrameStrata("DIALOG")
        lfbid_dkpSheetFrame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        lfbid_dkpSheetFrame:SetBackdropColor(0, 0, 0, lfbid_backdropAlpha)
        lfbid_dkpSheetFrame:EnableMouse(true)
        lfbid_dkpSheetFrame:SetMovable(true)
        lfbid_dkpSheetFrame:RegisterForDrag("LeftButton")
        lfbid_dkpSheetFrame:SetScript("OnDragStart", function()
            lfbid_dkpSheetFrame:StartMoving()
        end)
        lfbid_dkpSheetFrame:SetScript("OnDragStop", function()
            lfbid_dkpSheetFrame:StopMovingOrSizing()
        end)
        if lfbid_dkpSheetFrame.EnableMouseWheel then
            lfbid_dkpSheetFrame:EnableMouseWheel(true)
            lfbid_dkpSheetFrame:SetScript("OnMouseWheel", function()
                local delta = arg1 or 0
                if delta == 0 then
                    return
                end

                local step = 1
                if IsShiftKeyDown and IsShiftKeyDown() then
                    step = 5
                end

                if delta > 0 then
                    lfbid_dkpSheetScrollOffset = lfbid_dkpSheetScrollOffset - step
                else
                    lfbid_dkpSheetScrollOffset = lfbid_dkpSheetScrollOffset + step
                end

                RefreshLFBidDKPSheetWindow()
            end)
        end

        lfbid_dkpSheetFrame.title = lfbid_dkpSheetFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lfbid_dkpSheetFrame.title:SetPoint("TOPLEFT", lfbid_dkpSheetFrame, "TOPLEFT", 10, -14)
        lfbid_dkpSheetFrame.title:SetText("LFBid DKP Sheet")

        lfbid_dkpSheetFrame.closeBtn = CreateFrame("Button", nil, lfbid_dkpSheetFrame, "UIPanelButtonTemplate")
        lfbid_dkpSheetFrame.closeBtn:SetWidth(24)
        lfbid_dkpSheetFrame.closeBtn:SetHeight(24)
        lfbid_dkpSheetFrame.closeBtn:SetPoint("TOPRIGHT", lfbid_dkpSheetFrame, "TOPRIGHT", -4, -4)
        lfbid_dkpSheetFrame.closeBtn:SetText("X")
        lfbid_dkpSheetFrame.closeBtn:SetScript("OnClick", function()
            lfbid_dkpSheetFrame:Hide()
            lfbid_dkpSheetWindowOpen = false
        end)

        lfbid_dkpSheetFrame.headerPlayer = lfbid_dkpSheetFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lfbid_dkpSheetFrame.headerPlayer:SetPoint("TOPLEFT", lfbid_dkpSheetFrame, "TOPLEFT", 16, -44)
        lfbid_dkpSheetFrame.headerPlayer:SetText("Player")

        lfbid_dkpSheetFrame.headerTier1 = lfbid_dkpSheetFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lfbid_dkpSheetFrame.headerTier1:SetPoint("TOPLEFT", lfbid_dkpSheetFrame, "TOPLEFT", 240, -44)
        lfbid_dkpSheetFrame.headerTier1:SetText("Tier 1")

        lfbid_dkpSheetFrame.headerTier2 = lfbid_dkpSheetFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lfbid_dkpSheetFrame.headerTier2:SetPoint("TOPLEFT", lfbid_dkpSheetFrame, "TOPLEFT", 320, -44)
        lfbid_dkpSheetFrame.headerTier2:SetText("Tier 2")

        lfbid_dkpSheetFrame.scrollBar = CreateFrame("Slider", "LFBidDKPSheetScrollBar", lfbid_dkpSheetFrame)
        lfbid_dkpSheetFrame.scrollBar:SetPoint("TOPRIGHT", lfbid_dkpSheetFrame, "TOPRIGHT", -8, -30)
        lfbid_dkpSheetFrame.scrollBar:SetPoint("BOTTOMRIGHT", lfbid_dkpSheetFrame, "BOTTOMRIGHT", -8, 30)
        lfbid_dkpSheetFrame.scrollBar:SetWidth(16)
        lfbid_dkpSheetFrame.scrollBar:SetMinMaxValues(0, 0)
        lfbid_dkpSheetFrame.scrollBar:SetValueStep(1)
        lfbid_dkpSheetFrame.scrollBar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")

        local sbBg = lfbid_dkpSheetFrame.scrollBar:CreateTexture(nil, "BACKGROUND")
        sbBg:SetTexture("Interface\\Buttons\\UI-SliderBar-Background")
        sbBg:SetAllPoints(lfbid_dkpSheetFrame.scrollBar)
        sbBg:SetVertexColor(0.2, 0.2, 0.2, 0.8)

        local thumb = lfbid_dkpSheetFrame.scrollBar:GetThumbTexture()
        if thumb then
            thumb:SetWidth(16)
            thumb:SetHeight(24)
        end

        lfbid_dkpSheetFrame.scrollBar:SetValue(0)
        lfbid_dkpSheetFrame.scrollBar:SetScript("OnValueChanged", function()
            if lfbid_dkpSheetFrame.updatingScrollBar then
                return
            end

            local value = arg1
            if value == nil and this and this.GetValue then
                value = this:GetValue()
            end
            value = tonumber(value) or 0
            value = math.floor(value + 0.5)

            if value ~= lfbid_dkpSheetScrollOffset then
                lfbid_dkpSheetScrollOffset = value
                RefreshLFBidDKPSheetWindow()
            end
        end)

        lfbid_dkpSheetFrame.rows = {}
        local maxRows = 14
        local startY = -66
        local rowStep = 22
        local idx
        for idx = 1, maxRows do
            local y = startY - ((idx - 1) * rowStep)
            local row = {}

            row.player = lfbid_dkpSheetFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.player:SetPoint("TOPLEFT", lfbid_dkpSheetFrame, "TOPLEFT", 16, y)
            row.player:SetWidth(210)
            row.player:SetJustifyH("LEFT")

            row.tier1 = lfbid_dkpSheetFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.tier1:SetPoint("TOPLEFT", lfbid_dkpSheetFrame, "TOPLEFT", 240, y)
            row.tier1:SetWidth(70)
            row.tier1:SetJustifyH("LEFT")

            row.tier2 = lfbid_dkpSheetFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.tier2:SetPoint("TOPLEFT", lfbid_dkpSheetFrame, "TOPLEFT", 320, y)
            row.tier2:SetWidth(70)
            row.tier2:SetJustifyH("LEFT")

            table.insert(lfbid_dkpSheetFrame.rows, row)
        end

        lfbid_dkpSheetFrame.emptyText = lfbid_dkpSheetFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lfbid_dkpSheetFrame.emptyText:SetPoint("TOP", lfbid_dkpSheetFrame, "TOP", 0, -190)
        lfbid_dkpSheetFrame.emptyText:SetText("")

        lfbid_dkpSheetFrame.moreText = lfbid_dkpSheetFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lfbid_dkpSheetFrame.moreText:SetPoint("BOTTOMLEFT", lfbid_dkpSheetFrame, "BOTTOMLEFT", 16, 14)
        lfbid_dkpSheetFrame.moreText:SetText("")
    end

    lfbid_dkpSheetFrame:SetBackdropColor(0, 0, 0, lfbid_backdropAlpha)
    lfbid_dkpSheetScrollOffset = 0
    RefreshLFBidDKPSheetWindow()
    lfbid_dkpSheetWindowOpen = true
    lfbid_dkpSheetFrame:Show()
end

local function OpenLFBidOptionsWindow()
    if not lfbid_optionsFrame then
        lfbid_optionsFrame = CreateFrame("Frame", "LFBidOptionsFrame", UIParent)
        lfbid_optionsFrame:SetWidth(260)
        lfbid_optionsFrame:SetHeight(260)
        lfbid_optionsFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
        lfbid_optionsFrame:SetFrameStrata("DIALOG")
        lfbid_optionsFrame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        lfbid_optionsFrame:SetBackdropColor(0, 0, 0, lfbid_backdropAlpha)
        lfbid_optionsFrame:EnableMouse(true)
        lfbid_optionsFrame:SetMovable(true)
        lfbid_optionsFrame:RegisterForDrag("LeftButton")
        lfbid_optionsFrame:SetScript("OnDragStart", function()
            lfbid_optionsFrame:StartMoving()
        end)
        lfbid_optionsFrame:SetScript("OnDragStop", function()
            lfbid_optionsFrame:StopMovingOrSizing()
        end)

        lfbid_optionsFrame.title = lfbid_optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lfbid_optionsFrame.title:SetPoint("TOPLEFT", lfbid_optionsFrame, "TOPLEFT", 10, -14)
        lfbid_optionsFrame.title:SetText("LFBid Options")

        lfbid_optionsFrame.closeBtn = CreateFrame("Button", nil, lfbid_optionsFrame, "UIPanelButtonTemplate")
        lfbid_optionsFrame.closeBtn:SetWidth(24)
        lfbid_optionsFrame.closeBtn:SetHeight(24)
        lfbid_optionsFrame.closeBtn:SetPoint("TOPRIGHT", lfbid_optionsFrame, "TOPRIGHT", -4, -4)
        lfbid_optionsFrame.closeBtn:SetText("X")
        lfbid_optionsFrame.closeBtn:SetScript("OnClick", function()
            lfbid_optionsFrame:Hide()
            lfbid_optionsWindowOpen = false
        end)

        lfbid_optionsFrame.dkpToNotesBtn = CreateFrame("Button", nil, lfbid_optionsFrame, "UIPanelButtonTemplate")
        lfbid_optionsFrame.dkpToNotesBtn:SetWidth(200)
        lfbid_optionsFrame.dkpToNotesBtn:SetHeight(26)
        lfbid_optionsFrame.dkpToNotesBtn:SetPoint("TOP", lfbid_optionsFrame, "TOP", 0, -46)
        lfbid_optionsFrame.dkpToNotesBtn:SetText("DKP => Notes")
        lfbid_optionsFrame.dkpToNotesBtn:SetScript("OnClick", function()
            SyncDKPToGuildNotes()
        end)

        lfbid_optionsFrame.notesToDkpBtn = CreateFrame("Button", nil, lfbid_optionsFrame, "UIPanelButtonTemplate")
        lfbid_optionsFrame.notesToDkpBtn:SetWidth(200)
        lfbid_optionsFrame.notesToDkpBtn:SetHeight(26)
        lfbid_optionsFrame.notesToDkpBtn:SetPoint("TOP", lfbid_optionsFrame.dkpToNotesBtn, "BOTTOM", 0, -10)
        lfbid_optionsFrame.notesToDkpBtn:SetText("Notes => DKP")
        lfbid_optionsFrame.notesToDkpBtn:SetScript("OnClick", function()
            SyncGuildNotesToDKP()
        end)

        lfbid_optionsFrame.showDKPSheetBtn = CreateFrame("Button", nil, lfbid_optionsFrame, "UIPanelButtonTemplate")
        lfbid_optionsFrame.showDKPSheetBtn:SetWidth(200)
        lfbid_optionsFrame.showDKPSheetBtn:SetHeight(26)
        lfbid_optionsFrame.showDKPSheetBtn:SetPoint("TOP", lfbid_optionsFrame.notesToDkpBtn, "BOTTOM", 0, -10)
        lfbid_optionsFrame.showDKPSheetBtn:SetText("Show DKP sheet")
        lfbid_optionsFrame.showDKPSheetBtn:SetScript("OnClick", function()
            OpenLFBidDKPSheetWindow()
        end)

        lfbid_optionsFrame.raidTierLabel = lfbid_optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lfbid_optionsFrame.raidTierLabel:SetPoint("TOPLEFT", lfbid_optionsFrame.showDKPSheetBtn, "BOTTOMLEFT", 0, -14)
        lfbid_optionsFrame.raidTierLabel:SetText("Bid DKP Tier")

        lfbid_optionsFrame.t1RaidCheck = CreateFrame("CheckButton", "LFBidT1RaidCheckButton", lfbid_optionsFrame, "UICheckButtonTemplate")
        lfbid_optionsFrame.t1RaidCheck:SetPoint("TOPLEFT", lfbid_optionsFrame.raidTierLabel, "BOTTOMLEFT", -2, -6)
        lfbid_optionsFrame.t1RaidCheck:SetScript("OnClick", function()
            SetDKPCheckTier(1)
        end)
        if getglobal("LFBidT1RaidCheckButtonText") then
            getglobal("LFBidT1RaidCheckButtonText"):SetText("T1 Raid")
        end

        lfbid_optionsFrame.t2RaidCheck = CreateFrame("CheckButton", "LFBidT2RaidCheckButton", lfbid_optionsFrame, "UICheckButtonTemplate")
        lfbid_optionsFrame.t2RaidCheck:SetPoint("TOPLEFT", lfbid_optionsFrame.t1RaidCheck, "BOTTOMLEFT", 0, -2)
        lfbid_optionsFrame.t2RaidCheck:SetScript("OnClick", function()
            SetDKPCheckTier(2)
        end)
        if getglobal("LFBidT2RaidCheckButtonText") then
            getglobal("LFBidT2RaidCheckButtonText"):SetText("T2 Raid")
        end
    end

    SetDKPCheckTier(lfbid_dkpCheckTier)
    lfbid_optionsFrame:SetBackdropColor(0, 0, 0, lfbid_backdropAlpha)
    lfbid_optionsWindowOpen = true
    lfbid_optionsFrame:Show()
end

OpenLFBidWindow = function(itemLink, bidMode)
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
        LFbidFrame.alphaSlider:SetWidth(105)
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
        LFbidFrame.startBtn:SetPoint("TOP", LFbidFrame, "TOP", -48, -28)
        LFbidFrame.startBtn:SetText("Start Bid")
        LFbidFrame.startBtn:SetScript("OnClick", function()
            StartPointsBiddingFromMasterWindow()
        end)

        -- Stop Bids button (top center)
        LFbidFrame.stopBtn = CreateFrame("Button", nil, LFbidFrame, "UIPanelButtonTemplate")
        LFbidFrame.stopBtn:SetWidth(90)
        LFbidFrame.stopBtn:SetHeight(24)
        LFbidFrame.stopBtn:SetPoint("TOP", LFbidFrame, "TOP", 48, -28)
        LFbidFrame.stopBtn:SetText("Stop Bids")
            LFbidFrame.stopBtn:SetScript("OnClick", function()
                CloseBidding()
            end)

        LFbidFrame.dkpCheckBox = CreateFrame("CheckButton", "LFBidUseDKPCheckBox", LFbidFrame, "UICheckButtonTemplate")
        LFbidFrame.dkpCheckBox:SetWidth(24)
        LFbidFrame.dkpCheckBox:SetHeight(24)
        LFbidFrame.dkpCheckBox:SetPoint("TOPRIGHT", LFbidFrame, "TOPRIGHT", -28, -28)
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
            LFbidFrame.text:SetPoint("TOP", LFbidFrame, "TOP", 0, -52)
        end

        LFbidFrame.itemLinkButton = CreateFrame("Button", nil, LFbidFrame)
        LFbidFrame.itemLinkButton:SetWidth(380)
        LFbidFrame.itemLinkButton:SetHeight(18)
        LFbidFrame.itemLinkButton:SetPoint("TOP", LFbidFrame, "TOP", 0, -52)
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

        LFbidFrame.bidScrollBar = CreateFrame("Slider", "LFBidMasterBidScrollBar", LFbidFrame)
        LFbidFrame.bidScrollBar:SetPoint("TOPRIGHT", LFbidFrame, "TOPRIGHT", -8, -76)
        LFbidFrame.bidScrollBar:SetPoint("BOTTOMRIGHT", LFbidFrame, "BOTTOMRIGHT", -8, 40)
        LFbidFrame.bidScrollBar:SetWidth(14)
        if LFbidFrame.bidScrollBar.SetOrientation then
            LFbidFrame.bidScrollBar:SetOrientation("VERTICAL")
        end
        LFbidFrame.bidScrollBar:SetMinMaxValues(0, 0)
        LFbidFrame.bidScrollBar:SetValueStep(1)
        LFbidFrame.bidScrollBar:SetValue(0)
        LFbidFrame.bidScrollBar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
        LFbidFrame.bidScrollBar:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 12, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 }
        })
        LFbidFrame.bidScrollBar:SetBackdropColor(0, 0, 0, 0.25)
        LFbidFrame.bidScrollBar:SetScript("OnValueChanged", function()
            local value = tonumber(arg1) or 0
            if value < 0 then
                value = 0
            end

            local nextOffset = math.floor(value + 0.5)
            if nextOffset > lfbid_bidListMaxOffset then
                nextOffset = lfbid_bidListMaxOffset
            elseif nextOffset < 0 then
                nextOffset = 0
            end

            if nextOffset ~= lfbid_bidListScrollOffset then
                lfbid_bidListScrollOffset = nextOffset
                RefreshLFBidBidList()
            end
        end)
        LFbidFrame.bidScrollBar:Hide()

        if LFbidFrame.EnableMouseWheel then
            LFbidFrame:EnableMouseWheel(true)
            LFbidFrame:SetScript("OnMouseWheel", function()
                if not lfbid_windowOpen then
                    return
                end

                local delta = arg1 or 0
                if delta == 0 then
                    return
                end

                if lfbid_bidMode ~= "roll" then
                    local targetSpec = nil
                    if lfbid_hoveredSpec and lfbid_hoveredSpec ~= "" then
                        targetSpec = lfbid_hoveredSpec
                    end

                    if (not targetSpec or targetSpec == "") and LFbidFrame.gridCells then
                        for _, cell in ipairs(LFbidFrame.gridCells) do
                            if cell and cell:IsShown() and cell.specKey and cell.scrollBar and cell.scrollBar:IsShown() then
                                targetSpec = cell.specKey
                                break
                            end
                        end
                    end

                    if not targetSpec or targetSpec == "" then
                        return
                    end

                    local specKey = targetSpec
                    local totalForSpec = 0
                    for _, bid in ipairs(lfbid_bids) do
                        if bid and NormalizeSpec(bid.spec) == specKey then
                            totalForSpec = totalForSpec + 1
                        end
                    end

                    local maxOffset = totalForSpec - LFBID_POINTS_VISIBLE_ROWS
                    if maxOffset < 0 then
                        maxOffset = 0
                    end
                    if maxOffset == 0 then
                        return
                    end

                    local currentOffset = tonumber(lfbid_specScrollOffsets[specKey]) or 0
                    local nextOffset = currentOffset
                    if delta > 0 then
                        nextOffset = nextOffset - 1
                    else
                        nextOffset = nextOffset + 1
                    end

                    if nextOffset < 0 then
                        nextOffset = 0
                    elseif nextOffset > maxOffset then
                        nextOffset = maxOffset
                    end

                    if nextOffset ~= currentOffset then
                        lfbid_specScrollOffsets[specKey] = nextOffset
                        RefreshLFBidBidList()
                    end
                    return
                end

                local nextOffset = lfbid_bidListScrollOffset
                if delta > 0 then
                    nextOffset = nextOffset - 1
                else
                    nextOffset = nextOffset + 1
                end

                if nextOffset < 0 then
                    nextOffset = 0
                elseif nextOffset > lfbid_bidListMaxOffset then
                    nextOffset = lfbid_bidListMaxOffset
                end

                if nextOffset ~= lfbid_bidListScrollOffset then
                    lfbid_bidListScrollOffset = nextOffset
                    RefreshLFBidBidList()
                end
            end)
        end

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
    lfbid_bidListScrollOffset = 0
    lfbid_bidListMaxOffset = 0
    lfbid_specScrollOffsets = {}
    lfbid_hoveredSpec = nil
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

        local finalName, points, spec, altBid = ParseBidMessage(msg, sender)
        
        if finalName and points ~= nil and spec then
            RemoveExistingBidForPlayer(finalName)
            print("LFBid: Received " .. sourceType .. " bid from " .. finalName .. ": " .. points .. " " .. spec)
            table.insert(lfbid_bids, {
                name = finalName,
                points = points,
                spec = spec,
                altBid = altBid and true or false,
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
    elseif cmd == "options" then
        if not IsPlayerMasterLooter() and not IsPlayerFounderOrBanker() then
            print("LFBid: /lfbid options is only available to the Master Looter, Founder, or Banker.")
            return
        end
        if lfbid_optionsWindowOpen then
            print("LFBid options window already open.")
            return
        end
        OpenLFBidOptionsWindow()
    elseif cmd == "test" then
        RunLFBidRollTestSimulation(rest)
    elseif cmd == "testbid" then
        RunLFBidPointsTestSimulation()
    else
        print("LFbid commands:\n  /lfbid start <itemlink>\n  /lfbid roll <itemlink>\n  /lfbid open\n  /lfbid options")
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
