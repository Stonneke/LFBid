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
local lfbid_addonStatusFrame
local lfbid_addonStatusWindowOpen = false
local lfbid_addonStatusScanFrame
local lfbid_addonStatusScanActive = false
local lfbid_addonStatusScanToken = nil
local lfbid_addonStatusExpected = {}
local lfbid_addonStatusInstalled = {}
local lfbid_addonStatusMissing = {}
local lfbid_addonStatusDisplayInstalled = {}
local lfbid_addonStatusDisplayMissing = {}
local lfbid_dkpSheetScrollOffset = 0
local lfbid_openType = "MS"
local lfbid_mlBidType = "MS"
local lfbid_mlAltBid = false
local lfbid_mlTmogBid = false
local lfbid_openItemLink = ""
local lfbid_biddingOpen = false
local lfbid_bidMode = "points"
local lfbid_whisperFrame
local lfbid_bids = {}
local lfbid_rollSeen = {}
local LFBID_ADDON_PREFIX = "LFBid"
local LFDKP_ADDON_PREFIX = "LFDKP"
local LFBID_ENABLE_DKP_DELTA_SYNC = false
local LFBID_ENABLE_ROLLFOR_ROW_BUTTONS = false
local LFBID_ENABLE_ROLLFOR_POPUP_BUTTONS = true
local lfbid_backdropAlpha = 0.30
local lfbid_useDKPCheck = 1
local lfbid_dkpCheckTier = 1
local lfbid_bidListScrollOffset = 0
local lfbid_bidListMaxOffset = 0
local lfbid_specScrollOffsets = {}
local lfbid_hoveredSpec = nil
local lfbid_openAltBid = false
local lfbid_openTmogBid = false
local LFBID_ROLL_VISIBLE_ROWS = 10
local LFBID_POINTS_VISIBLE_ROWS = 6
local lfbid_pendingWinnerAnnouncement = nil
local lfbid_manualWinnerSelectionActive = false
local lfbid_pendingManualWinnerBid = nil
local lfbid_manualWinnerCostText = ""
local LFBID_STATUS_REQUEST_PREFIX = "STATUSREQ:"
local LFBID_STATUS_RESPONSE_PREFIX = "STATUSRES:"
local LFBID_VERSION = "2.12"
local RefreshMasterLootButtons
local RefreshLFBidBidList
local RefreshLFBidDKPSheetWindow
local OpenLFBidWindow
local StartBiddingForItemLink

local function PersistLFBidSettings()
    if type(LFBidSettings) ~= "table" then
        LFBidSettings = {}
    end

    LFBidSettings.backdropAlpha = tonumber(lfbid_backdropAlpha) or 0.30
    LFBidSettings.useDKPCheck = lfbid_useDKPCheck and 1 or 0
    LFBidSettings.dkpCheckTier = (lfbid_dkpCheckTier == 2) and 2 or 1
    LFBidSettings.openAltBid = lfbid_openAltBid and 1 or 0
    LFBidSettings.openTmogBid = lfbid_openTmogBid and 1 or 0
end

local function LoadLFBidSettings()
    if type(LFBidSettings) ~= "table" then
        LFBidSettings = {}
    end

    local alpha = tonumber(LFBidSettings.backdropAlpha)
    if alpha and alpha >= 0 and alpha <= 1 then
        lfbid_backdropAlpha = alpha
    end

    if tonumber(LFBidSettings.useDKPCheck) == 1 then
        lfbid_useDKPCheck = 1
    else
        lfbid_useDKPCheck = nil
    end

    local tier = tonumber(LFBidSettings.dkpCheckTier)
    if tier == 2 then
        lfbid_dkpCheckTier = 2
    else
        lfbid_dkpCheckTier = 1
    end

    lfbid_openAltBid = tonumber(LFBidSettings.openAltBid) == 1
    lfbid_openTmogBid = tonumber(LFBidSettings.openTmogBid) == 1

    -- Write back defaults so the table always has a complete shape.
    PersistLFBidSettings()
end

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
    if lfbid_addonStatusFrame then
        lfbid_addonStatusFrame:SetBackdropColor(0, 0, 0, lfbid_backdropAlpha)
    end
end

print("LFBid loaded. Use /lfbid for commands.")


local function NormalizeBidderName(name)
    local text = tostring(name or "")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    local dashPos = string.find(text, "-")
    if dashPos and dashPos > 1 then
        text = string.sub(text, 1, dashPos - 1)
    end
    return text
end

local function ParseBidMessage(msg, fallbackName)
    local text = tostring(msg or "")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    if text == "" then
        return nil, nil, nil, false
    end

    local tokens = {}
    local tokenIter = string.gfind or string.gmatch
    for token in tokenIter(text, "%S+") do
        table.insert(tokens, token)
    end
    if table.getn(tokens) < 1 then
        return nil, nil, nil, false
    end

    local altBid = false
    local tmogBid = false
    while table.getn(tokens) > 0 do
        local lastToken = tokens[table.getn(tokens)]
        local lastLower = string.lower(tostring(lastToken or ""))
        if lastLower == "alt" then
            altBid = true
            table.remove(tokens)
        elseif lastLower == "tmog" or lastLower == "t-mog" then
            tmogBid = true
            table.remove(tokens)
        else
            break
        end
    end

    if table.getn(tokens) < 1 then
        local onlyName = NormalizeBidderName(fallbackName)
        if onlyName ~= "" and tmogBid then
            return onlyName, nil, nil, altBid and true or false, true
        end
        return nil, nil, nil, false, false
    end

    local points
    local spec
    local parsedName

    local token1 = tokens[1]
    local token2 = tokens[2]
    local token1Number = tonumber(token1)
    local token2Number = tonumber(token2)

    -- Preferred input formats: "<points> <spec>" or "<spec> <points>".
    if token1Number and not token2Number then
        points = token1Number
        spec = token2
    elseif token2Number and not token1Number then
        points = token2Number
        spec = token1
    end

    -- Allow transmog bids without points (e.g. "T-MOG" or "TMOG").
    if not points and table.getn(tokens) == 1 then
        local only = string.lower(tostring(tokens[1] or ""))
        if only == "tmog" or only == "t-mog" then
            points = 0
            spec = tokens[1]
            tmogBid = true
        end
    end

    -- Backward compatibility for old format with explicit player name in payload.
    if not points and table.getn(tokens) >= 3 then
        local token3 = tokens[3]
        local token3Number = tonumber(token3)
        if token2Number and not token3Number then
            parsedName = token1
            points = token2Number
            spec = token3
        elseif token3Number and not token2Number then
            parsedName = token1
            points = token3Number
            spec = token2
        end
    end

    local finalName = NormalizeBidderName(fallbackName)
    if finalName == "" then
        finalName = NormalizeBidderName(parsedName)
    end

    if finalName == "" or points == nil or not spec or spec == "" then
        if finalName ~= "" and tmogBid then
            return finalName, nil, nil, altBid and true or false, true
        end
        return nil, nil, nil, false, false
    end

    return finalName, points, spec, altBid and true or false, tmogBid and true or false
end

local function GenerateRandomTmogRoll()
    local roll = 1
    local randomFunc
    if math and math.random then
        randomFunc = math.random
    elseif random then
        randomFunc = random
    end

    if randomFunc then
        roll = tonumber(randomFunc(1, 100)) or 1
    end

    if roll < 1 then
        roll = 1
    elseif roll > 100 then
        roll = 100
    end

    return roll
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

local function GetLFBidVersionText()
    return LFBID_VERSION
end

local function BuildLFBidStatusRequest(token)
    return LFBID_STATUS_REQUEST_PREFIX .. tostring(token or "")
end

local function BuildLFBidStatusResponse(token, versionText)
    return LFBID_STATUS_RESPONSE_PREFIX .. tostring(token or "") .. ":" .. EncodeAddonText(versionText)
end

local function ParseLFBidStatusRequest(msg)
    local text = tostring(msg or "")
    if string.sub(text, 1, string.len(LFBID_STATUS_REQUEST_PREFIX)) ~= LFBID_STATUS_REQUEST_PREFIX then
        return nil
    end

    local token = string.sub(text, string.len(LFBID_STATUS_REQUEST_PREFIX) + 1)
    if token == "" then
        return nil
    end

    return token
end

local function ParseLFBidStatusResponse(msg)
    local text = tostring(msg or "")
    if string.sub(text, 1, string.len(LFBID_STATUS_RESPONSE_PREFIX)) ~= LFBID_STATUS_RESPONSE_PREFIX then
        return nil, nil
    end

    local payload = string.sub(text, string.len(LFBID_STATUS_RESPONSE_PREFIX) + 1)
    local _, _, token, versionText = string.find(payload, "^([^:]+):(.*)$")
    if not token or token == "" then
        return nil, nil
    end

    return token, DecodeAddonText(versionText)
end

local function GetSortedLFBidStatusNames(nameMap)
    local names = {}
    local normalizedName
    for normalizedName in pairs(nameMap or {}) do
        table.insert(names, normalizedName)
    end

    table.sort(names, function(a, b)
        local left = tostring((nameMap[a] and nameMap[a].displayName) or a or "")
        local right = tostring((nameMap[b] and nameMap[b].displayName) or b or "")
        return string.lower(left) < string.lower(right)
    end)

    return names
end

local function FinalizeLFBidAddonStatusScan()
    lfbid_addonStatusScanActive = false

    local missing = {}
    local normalizedName
    for normalizedName, entry in pairs(lfbid_addonStatusExpected) do
        if not lfbid_addonStatusInstalled[normalizedName] then
            missing[normalizedName] = {
                displayName = tostring(entry.displayName or normalizedName),
            }
        end
    end

    lfbid_addonStatusMissing = missing
    lfbid_addonStatusDisplayInstalled = GetSortedLFBidStatusNames(lfbid_addonStatusInstalled)
    lfbid_addonStatusDisplayMissing = GetSortedLFBidStatusNames(lfbid_addonStatusMissing)

    if lfbid_addonStatusFrame and lfbid_addonStatusFrame.RefreshLists then
        lfbid_addonStatusFrame:RefreshLists()
    end
end

local function StopLFBidAddonStatusScanTimer()
    if not lfbid_addonStatusScanFrame then
        return
    end

    lfbid_addonStatusScanFrame:SetScript("OnUpdate", nil)
    lfbid_addonStatusScanFrame:Hide()
end

local function StartLFBidAddonStatusScanTimer(durationSeconds)
    if not lfbid_addonStatusScanFrame then
        lfbid_addonStatusScanFrame = CreateFrame("Frame")
    end

    lfbid_addonStatusScanFrame.elapsed = 0
    lfbid_addonStatusScanFrame.duration = tonumber(durationSeconds) or 2
    lfbid_addonStatusScanFrame:SetScript("OnUpdate", function()
        local elapsed = arg1 or 0
        lfbid_addonStatusScanFrame.elapsed = (lfbid_addonStatusScanFrame.elapsed or 0) + elapsed
        if lfbid_addonStatusScanFrame.elapsed < (lfbid_addonStatusScanFrame.duration or 2) then
            return
        end

        StopLFBidAddonStatusScanTimer()
        FinalizeLFBidAddonStatusScan()
    end)
    lfbid_addonStatusScanFrame:Show()
end

local function CollectCurrentRaidMembers()
    local roster = {}
    if not GetNumRaidMembers or not GetRaidRosterInfo then
        return roster
    end

    local raidCount = tonumber(GetNumRaidMembers()) or 0
    local raidIndex
    for raidIndex = 1, raidCount do
        local playerName = GetRaidRosterInfo(raidIndex)
        local normalizedName = NormalizeBidderName(playerName)
        if normalizedName ~= "" then
            roster[normalizedName] = {
                displayName = normalizedName,
            }
        end
    end

    return roster
end

local function StartLFBidAddonStatusScan()
    lfbid_addonStatusExpected = {}
    lfbid_addonStatusInstalled = {}
    lfbid_addonStatusMissing = {}
    lfbid_addonStatusDisplayInstalled = {}
    lfbid_addonStatusDisplayMissing = {}

    if not SendAddonMessage then
        print("LFBid: Addon status scan requires SendAddonMessage.")
        if lfbid_addonStatusFrame and lfbid_addonStatusFrame.RefreshLists then
            lfbid_addonStatusFrame:RefreshLists()
        end
        return false
    end

    if not GetNumRaidMembers or (tonumber(GetNumRaidMembers()) or 0) <= 0 then
        print("LFBid: You must be in a raid to check addon status.")
        if lfbid_addonStatusFrame and lfbid_addonStatusFrame.RefreshLists then
            lfbid_addonStatusFrame:RefreshLists()
        end
        return false
    end

    lfbid_addonStatusExpected = CollectCurrentRaidMembers()
    lfbid_addonStatusScanToken = tostring(math.floor((GetTime and GetTime() or 0) * 1000)) .. tostring(math.random(1000, 9999))
    lfbid_addonStatusScanActive = true

    local myName = NormalizeBidderName(UnitName("player"))
    if myName ~= "" and lfbid_addonStatusExpected[myName] then
        lfbid_addonStatusInstalled[myName] = {
            displayName = myName,
            version = GetLFBidVersionText(),
        }
    end

    if lfbid_addonStatusFrame and lfbid_addonStatusFrame.RefreshLists then
        lfbid_addonStatusFrame:RefreshLists()
    end

    SendAddonMessage(LFBID_ADDON_PREFIX, BuildLFBidStatusRequest(lfbid_addonStatusScanToken), "RAID")
    StartLFBidAddonStatusScanTimer(2)
    return true
end

local function ItemTextForAnnouncement(itemText)
    local text = tostring(itemText or "")
    local _, _, itemName = string.find(text, "|h%[(.-)%]|h")
    if itemName and itemName ~= "" then
        return "[" .. itemName .. "]"
    end
    return text
end

local lfbid_scanTooltip

-- Extract the raw itemstring (e.g. "item:12345:0:0:0") from a full colored
-- hyperlink (e.g. "|cffFFD100|Hitem:12345:0:0:0|h[Name]|h|r").
-- GameTooltip:SetHyperlink expects the raw itemstring, not the colored link;
-- passing the full link breaks tooltips inconsistently across different clients.
-- This mirrors how aux-addon parses links in util/info.lua (parse_link /
-- itemstring) before calling SetHyperlink.
local function ExtractItemString(itemLink)
    local _, _, itemStr = string.find(itemLink, "|H([^|]+)|h")
    return itemStr
end

local function PrimeItemTooltipCache(itemLink)
    if not itemLink or itemLink == "" then
        return
    end

    if not lfbid_scanTooltip then
        lfbid_scanTooltip = CreateFrame("GameTooltip", "LFBidScanTooltip", nil, "GameTooltipTemplate")
    end

    local itemStr = ExtractItemString(itemLink) or itemLink
    if lfbid_scanTooltip and lfbid_scanTooltip.SetOwner and lfbid_scanTooltip.SetHyperlink then
        lfbid_scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
        pcall(lfbid_scanTooltip.SetHyperlink, lfbid_scanTooltip, itemStr)
    end
end

local function ShowItemTooltip(anchorFrame, itemLink)
    if not anchorFrame or not itemLink or itemLink == "" then
        return
    end

    if not string.find(itemLink, "|Hitem:", 1, true) then
        GameTooltip:SetOwner(anchorFrame, "ANCHOR_RIGHT")
        GameTooltip:SetText("Unknown item")
        GameTooltip:Show()
        return
    end

    local itemStr = ExtractItemString(itemLink) or itemLink

    if GetItemInfo then
        local itemName = GetItemInfo(itemStr)
        if not itemName then
            PrimeItemTooltipCache(itemLink)
        end
    else
        PrimeItemTooltipCache(itemLink)
    end

    GameTooltip:SetOwner(anchorFrame, "ANCHOR_RIGHT")
    local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, itemStr)
    if not ok then
        local _, _, itemName = string.find(itemLink, "|h%[(.-)%]|h")
        if itemName and itemName ~= "" then
            GameTooltip:SetText(itemName)
        else
            GameTooltip:SetText("Item details unavailable")
        end
    end
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

local function IsPlayerOfficerRank()
    if not GetGuildInfo then
        return false
    end

    local _, rankName = GetGuildInfo("player")
    if not rankName or rankName == "" then
        return false
    end

    local normalizedRank = string.lower(tostring(rankName))
    return normalizedRank == "chief officer" or normalizedRank == "officer"
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

local function IsSupportedBidSpec(spec)
    local normalized = NormalizeSpec(spec)
    return normalized == "MS" or normalized == "OS" or normalized == "T-MOG" or normalized == "X"
end

local function HasPrimaryMSBids()
    for _, bid in ipairs(lfbid_bids) do
        if bid and NormalizeSpec(bid.spec) == "MS" then
            return true
        end
    end

    return false
end

local function GetEffectiveBidSpec(spec, hasPrimaryMSBids)
    local normalized = NormalizeSpec(spec)
    if normalized == "X" then
        if hasPrimaryMSBids then
            return "MS"
        end
        return "OS"
    end

    return normalized
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

    PersistLFBidSettings()
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

local function GetBidDisplayName(bid)
    local displayName = tostring(bid and bid.name or "")
    if bid and bid.whisperBid then
        displayName = displayName .. " *"
    end
    return displayName
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
            SendSafeChatMessage(msg, "RAID_WARNING")
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

local function ResolvePointsAuctionOutcome()
    local hasPrimaryMSBids = HasPrimaryMSBids()
    local buckets = {
        ["MS"] = {},
        ["OS"] = {},
        ["T-MOG"] = {},
    }
    local priority = {"MS", "OS", "T-MOG"}

    for _, bid in ipairs(lfbid_bids) do
        local originalSpec = NormalizeSpec(bid and bid.spec)
        local spec = GetEffectiveBidSpec(originalSpec, hasPrimaryMSBids)
        local points = tonumber(bid and bid.points)
        if buckets[spec] and points then
            table.insert(buckets[spec], {
                name = tostring(bid.name or ""),
                points = points,
                spec = spec,
                originalSpec = originalSpec,
                altBid = bid and bid.altBid and true or false,
            })
        end
    end

    local selectedSpec = nil
    local selectedBids = nil

    -- ALT bids are fallback-only: if any non-ALT bids exist in a higher-priority
    -- bucket, that bucket must win selection and ALT bids cannot beat those players.
    for _, spec in ipairs(priority) do
        local bucket = buckets[spec]
        local hasNonAlt = false
        for _, entry in ipairs(bucket) do
            if not entry.altBid then
                hasNonAlt = true
                break
            end
        end

        if hasNonAlt then
            selectedSpec = spec
            selectedBids = bucket
            break
        end
    end

    if not selectedSpec then
        for _, spec in ipairs(priority) do
            if table.getn(buckets[spec]) > 0 then
                selectedSpec = spec
                selectedBids = buckets[spec]
                break
            end
        end
    end

    if not selectedSpec or not selectedBids then
        return nil
    end

    local winnerPool = selectedBids
    local nonAltPool = {}
    for _, entry in ipairs(selectedBids) do
        if not entry.altBid then
            table.insert(nonAltPool, entry)
        end
    end
    if table.getn(nonAltPool) > 0 then
        winnerPool = nonAltPool
    end

    table.sort(winnerPool, function(a, b)
        if a.points ~= b.points then
            return a.points > b.points
        end
        return string.lower(tostring(a.name or "")) < string.lower(tostring(b.name or ""))
    end)

    local winner = winnerPool[1]
    if not winner or winner.name == "" then
        return nil
    end

    -- For DKP pricing, ALT bids must never influence a non-ALT winner's cost.
    local pricingPool = winnerPool
    if not winner.altBid and table.getn(nonAltPool) > 0 then
        pricingPool = nonAltPool
    end

    local cost = 1
    local winnerBid = tonumber(winner.points) or 0

    local tiedTop = {}
    local tieIncludesX = false
    local _, bidEntry
    for _, bidEntry in ipairs(pricingPool) do
        local bidPoints = tonumber(bidEntry and bidEntry.points) or 0
        if bidPoints == winnerBid then
            table.insert(tiedTop, tostring(bidEntry.name or ""))
            if NormalizeSpec(bidEntry and bidEntry.originalSpec) == "X" then
                tieIncludesX = true
            end
        else
            break
        end
    end

    if table.getn(tiedTop) >= 2 then
        table.sort(tiedTop, function(a, b)
            return string.lower(tostring(a or "")) < string.lower(tostring(b or ""))
        end)

        return {
            isTie = true,
            tieNames = tiedTop,
            winnerSpec = selectedSpec,
            winnerBid = winnerBid,
            cost = winnerBid,
            tieIncludesX = tieIncludesX,
            itemLink = tostring(lfbid_activeItem or ""),
        }
    end

    local winnerIsX = NormalizeSpec(winner.originalSpec) == "X"
    if table.getn(pricingPool) >= 2 then
        local secondBid = tonumber(pricingPool[2].points) or 0

        if winnerIsX then
            cost = (secondBid + 1) * 2
        else
            -- If top bids are tied, winner pays the tied bid amount.
            -- Only unique top bids use second-highest + 1.
            if winnerBid == secondBid then
                cost = winnerBid
            else
                cost = secondBid + 1
            end
        end
    elseif winnerIsX then
        cost = 0
    end
    if cost < 1 then
        cost = 1
    end

    return {
        winnerName = winner.name,
        winnerSpec = selectedSpec,
        winnerBid = winnerBid,
        cost = cost,
        itemLink = tostring(lfbid_activeItem or ""),
    }
end

local function SendWinnerAnnouncement(outcome)
    if not outcome then
        return
    end

    local rawItemText = tostring(outcome.itemLink or "")
    local itemText = rawItemText
    if not string.find(rawItemText, "|Hitem:") then
        itemText = ItemTextForAnnouncement(rawItemText)
    end
    if itemText == "" then
        itemText = ItemTextForAnnouncement(rawItemText)
    end
    local message
    if outcome.isTie and outcome.tieNames and table.getn(outcome.tieNames) >= 2 then
        local names = table.concat(outcome.tieNames, ", ")
        if outcome.tieIncludesX then
            if itemText and itemText ~= "" then
                message = itemText .. " tied between " .. names .. ". Roll for it"
            else
                message = "Tie between " .. names .. ". Roll for it"
            end
        elseif itemText and itemText ~= "" then
            message = itemText .. " tied between " .. names .. ". Roll for it for " .. tostring(outcome.cost) .. " DKP"
        else
            message = "Tie between " .. names .. ". Roll for it for " .. tostring(outcome.cost) .. " DKP"
        end
    elseif itemText and itemText ~= "" then
        message = itemText .. " won by " .. tostring(outcome.winnerName) .. " for " .. tostring(outcome.cost) .. " DKP"
    else
        message = tostring(outcome.winnerName) .. " won for " .. tostring(outcome.cost) .. " DKP"
    end

    if GetNumRaidMembers and GetNumRaidMembers() and GetNumRaidMembers() > 0 then
        SendSafeChatMessage(message, "RAID_WARNING")
        return
    end

    if GetNumPartyMembers and GetNumPartyMembers() and GetNumPartyMembers() > 0 then
        SendSafeChatMessage(message, "PARTY")
        return
    end

    print("LFBid: " .. message)
end

local function EnsureWinnerConfirmPopupRegistered()
    StaticPopupDialogs = StaticPopupDialogs or {}
    if StaticPopupDialogs["LFBID_CONFIRM_WINNER_ANNOUNCE"] then
        return
    end

    StaticPopupDialogs["LFBID_CONFIRM_WINNER_ANNOUNCE"] = {
        text = "%s",
        button1 = "Yes",
        button2 = "No",
        OnAccept = function()
            if lfbid_pendingWinnerAnnouncement then
                SendWinnerAnnouncement(lfbid_pendingWinnerAnnouncement)
            end
            lfbid_pendingWinnerAnnouncement = nil
            lfbid_manualWinnerSelectionActive = false
            if RefreshLFBidBidList and lfbid_windowOpen then
                RefreshLFBidBidList()
            end
        end,
        OnCancel = function()
            lfbid_pendingWinnerAnnouncement = nil
            lfbid_manualWinnerSelectionActive = true
            if IsPlayerMasterLooter() then
                print("LFBid: Click a bid in the ML list to pick a winner manually.")
            end
            if RefreshLFBidBidList and lfbid_windowOpen then
                RefreshLFBidBidList()
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
end

local function EnsureManualWinnerCostPopupRegistered()
    StaticPopupDialogs = StaticPopupDialogs or {}
    if StaticPopupDialogs["LFBID_MANUAL_WINNER_COST"] then
        return
    end

    local function ReadManualWinnerCostText(popupFrame)
        local candidateFrames = {}
        if popupFrame then
            table.insert(candidateFrames, popupFrame)
        end

        if this then
            table.insert(candidateFrames, this)
            if this.GetParent then
                local parent = this:GetParent()
                if parent then
                    table.insert(candidateFrames, parent)
                end
            end
        end

        local index
        for index = 1, 4 do
            local frame = getglobal("StaticPopup" .. tostring(index))
            if frame and frame.which == "LFBID_MANUAL_WINNER_COST" then
                table.insert(candidateFrames, frame)
            end
            local editBox = getglobal("StaticPopup" .. tostring(index) .. "EditBox")
            if editBox and editBox.GetParent and editBox:GetParent() and editBox:GetParent().which == "LFBID_MANUAL_WINNER_COST" then
                local value = tostring(editBox:GetText() or "")
                if value ~= "" then
                    return value
                end
            end
        end

        local _, frame
        for _, frame in ipairs(candidateFrames) do
            if frame and frame.editBox and frame.editBox.GetText then
                return tostring(frame.editBox:GetText() or "")
            end
        end

        return tostring(lfbid_manualWinnerCostText or "")
    end

    StaticPopupDialogs["LFBID_MANUAL_WINNER_COST"] = {
        text = "%s",
        button1 = "Announce",
        button2 = "Cancel",
        hasEditBox = 1,
        maxLetters = 6,
        OnShow = function(popupFrame)
            local frame = popupFrame or this
            if frame and frame.editBox then
                frame.editBox:SetText("")
                frame.editBox:SetFocus()
                frame.editBox:HighlightText()
                lfbid_manualWinnerCostText = ""
                frame.editBox:SetScript("OnTextChanged", function()
                    lfbid_manualWinnerCostText = tostring(this:GetText() or "")
                end)
                frame.editBox:SetScript("OnEscapePressed", function()
                    if this and this:GetParent() then
                        this:GetParent():Hide()
                    end
                end)
            end
        end,
        EditBoxOnEnterPressed = function()
            lfbid_manualWinnerCostText = tostring(this:GetText() or "")
            if this and this:GetParent() and this:GetParent().button1 then
                this:GetParent().button1:Click()
            end
        end,
        OnAccept = function(popupFrame)
            if not lfbid_pendingManualWinnerBid then
                return
            end

            local textValue = ReadManualWinnerCostText(popupFrame)
            textValue = string.gsub(textValue, "^%s+", "")
            textValue = string.gsub(textValue, "%s+$", "")

            local cost = tonumber(textValue)
            if not cost then
                print("LFBid: Please enter a numeric DKP amount.")
                return
            end

            cost = math.floor(cost + 0.5)
            if cost < 1 then
                print("LFBid: DKP amount must be at least 1.")
                return
            end

            local bid = lfbid_pendingManualWinnerBid
            local outcome = {
                winnerName = tostring(bid.name or ""),
                winnerSpec = NormalizeSpec(bid.spec),
                winnerBid = tonumber(bid.points) or 0,
                cost = cost,
                itemLink = tostring(lfbid_activeItem or ""),
            }

            SendWinnerAnnouncement(outcome)
            lfbid_manualWinnerSelectionActive = false
            lfbid_pendingManualWinnerBid = nil
            lfbid_manualWinnerCostText = ""
            if RefreshLFBidBidList and lfbid_windowOpen then
                RefreshLFBidBidList()
            end
        end,
        OnCancel = function()
            lfbid_pendingManualWinnerBid = nil
            lfbid_manualWinnerCostText = ""
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
end

local function StartManualWinnerSelectionForBid(bid)
    if not IsPlayerMasterLooter() then
        return
    end
    if not lfbid_manualWinnerSelectionActive then
        return
    end
    if lfbid_biddingOpen then
        return
    end
    if not bid or not bid.name then
        return
    end

    EnsureManualWinnerCostPopupRegistered()
    lfbid_pendingManualWinnerBid = bid
    local text = tostring(bid.name) .. " selected. Enter DKP cost:"
    if StaticPopup_Show then
        StaticPopup_Show("LFBID_MANUAL_WINNER_COST", text)
    else
        print("LFBid: " .. text)
    end
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
        local pointsOutcome = nil
        if lfbid_bidMode == "points" then
            pointsOutcome = ResolvePointsAuctionOutcome()
        end

        lfbid_biddingOpen = false
        lfbid_rollSeen = {}
        SendBiddingCloseMessage()
        if RefreshMasterLootButtons then
            RefreshMasterLootButtons()
        end

        if lfbid_bidMode == "points" then
            if pointsOutcome then
                if IsPlayerMasterLooter() then
                    EnsureWinnerConfirmPopupRegistered()
                    lfbid_pendingWinnerAnnouncement = pointsOutcome
                    local confirmText
                    if pointsOutcome.isTie and pointsOutcome.tieNames and table.getn(pointsOutcome.tieNames) >= 2 then
                        if pointsOutcome.tieIncludesX then
                            confirmText = "Tie: " .. table.concat(pointsOutcome.tieNames, ", ") .. ". Announce roll-off?"
                        else
                            confirmText = "Tie: " .. table.concat(pointsOutcome.tieNames, ", ") .. ". Announce roll-off for " .. tostring(pointsOutcome.cost) .. " DKP?"
                        end
                    else
                        confirmText = tostring(pointsOutcome.winnerName) .. " won for " .. tostring(pointsOutcome.cost) .. " DKP, announce?"
                    end
                    if StaticPopup_Show then
                        StaticPopup_Show("LFBID_CONFIRM_WINNER_ANNOUNCE", confirmText)
                    else
                        print("LFBid: " .. confirmText)
                    end
                else
                    if pointsOutcome.isTie and pointsOutcome.tieNames and table.getn(pointsOutcome.tieNames) >= 2 then
                        if pointsOutcome.tieIncludesX then
                            print("LFBid: Tie between " .. table.concat(pointsOutcome.tieNames, ", ") .. ". Roll-off required.")
                        else
                            print("LFBid: Tie between " .. table.concat(pointsOutcome.tieNames, ", ") .. ". Roll-off for " .. tostring(pointsOutcome.cost) .. " DKP.")
                        end
                    else
                        print("LFBid: Winner is " .. tostring(pointsOutcome.winnerName) .. " for " .. tostring(pointsOutcome.cost) .. " DKP.")
                    end
                end
            else
                print("LFBid: Bidding ended with no valid MS/OS/T-MOG bids.")
            end
        end
    end)
end

local function CancelBidding()
    if not lfbid_biddingOpen then
        print("LFBid: Bidding is not active.")
        return
    end

    local message
    local activeLink = tostring(lfbid_activeItem or "")
    if activeLink ~= "" then
        message = activeLink .. " bidding is cancelled"
    else
        message = "Bidding is cancelled"
    end

    if GetNumRaidMembers and GetNumRaidMembers() and GetNumRaidMembers() > 0 then
        SendSafeChatMessage(message, "RAID_WARNING")
    elseif GetNumPartyMembers and GetNumPartyMembers() and GetNumPartyMembers() > 0 then
        SendSafeChatMessage(message, "PARTY")
    else
        print("LFBid: " .. message)
    end

    lfbid_biddingOpen = false
    lfbid_rollSeen = {}
    lfbid_bids = {}
    lfbid_pendingWinnerAnnouncement = nil
    lfbid_manualWinnerSelectionActive = false
    lfbid_pendingManualWinnerBid = nil
    SendBiddingCloseMessage()

    if RefreshMasterLootButtons then
        RefreshMasterLootButtons()
    end
    if RefreshLFBidBidList then
        RefreshLFBidBidList()
    end
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

    local mlOpeningBidPoints = nil
    local mlOpeningBidSpec = NormalizeSpec(lfbid_mlBidType)
    local mlOpeningBidAlt = lfbid_mlAltBid and true or false
    local shouldInsertPrimaryBid = false
    local shouldInsertTmogBid = lfbid_mlTmogBid and true or false
    local shouldInsertMLOpeningBid = false
    if LFbidFrame and LFbidFrame.mlBidPointsEdit then
        local text = tostring(LFbidFrame.mlBidPointsEdit:GetText() or "")
        text = string.gsub(text, "^%s+", "")
        text = string.gsub(text, "%s+$", "")
        if text ~= "" then
            local parsed = tonumber(text)
            if not parsed then
                print("LFBid: ML opening bid points must be a number.")
                return
            end
            parsed = math.floor(parsed + 0.5)
            if parsed < 0 then
                print("LFBid: ML opening bid points cannot be negative.")
                return
            end
            mlOpeningBidPoints = parsed
        end
    end

    if mlOpeningBidPoints ~= nil then
        shouldInsertPrimaryBid = true
    end

    if shouldInsertPrimaryBid and mlOpeningBidAlt and mlOpeningBidSpec == "X" then
        print("LFBid: ALT characters cannot bid X.")
        shouldInsertPrimaryBid = false
    end

    shouldInsertMLOpeningBid = shouldInsertPrimaryBid or shouldInsertTmogBid

    if shouldInsertMLOpeningBid then
        local myName = string.lower(tostring(UnitName("player") or ""))
        local hasOtherBids = false
        for _, bid in ipairs(lfbid_bids) do
            local bidderName = string.lower(tostring(bid and bid.name or ""))
            if bidderName ~= "" and bidderName ~= myName then
                hasOtherBids = true
                break
            end
        end

        if hasOtherBids then
            print("LFBid: ML opening bid is only allowed before other bids come in.")
            shouldInsertMLOpeningBid = false
        end
    end

    lfbid_openItemLink = lfbid_activeItem
    lfbid_biddingOpen = true
    lfbid_manualWinnerSelectionActive = false
    lfbid_pendingManualWinnerBid = nil

    if shouldInsertMLOpeningBid then
        local myName = tostring(UnitName("player") or "")
        if myName ~= "" then
            RemoveExistingBidForPlayer(myName)

            if shouldInsertPrimaryBid then
                table.insert(lfbid_bids, {
                    name = myName,
                    points = mlOpeningBidPoints,
                    spec = mlOpeningBidSpec,
                    altBid = mlOpeningBidAlt,
                })
            end

            if shouldInsertTmogBid then
                table.insert(lfbid_bids, {
                    name = myName,
                    points = GenerateRandomTmogRoll(),
                    spec = "T-MOG",
                    altBid = mlOpeningBidAlt,
                })
            end
        end
    end

    SendBiddingStartMessage(lfbid_activeItem)
    SendSafeChatMessage("Start bidding on item: " .. lfbid_activeItem, "RAID_WARNING")
    local whisperTarget = GetCurrentLootMasterName() or UnitName("player") or "ML"
    SendSafeChatMessage("Bid via /w " .. tostring(whisperTarget) .. " <spec> <points> (example: MS 25)", "RAID_WARNING")
    SendSafeChatMessage("TMOG via /w " .. tostring(whisperTarget) .. " TMOG or MS 10 TMOG", "RAID_WARNING")

    if RefreshMasterLootButtons then
        RefreshMasterLootButtons()
    end

    if RefreshLFBidBidList then
        RefreshLFBidBidList()
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

    if LFbidFrame.cancelBtn then
        if lfbid_biddingOpen then
            LFbidFrame.cancelBtn:Enable()
        else
            LFbidFrame.cancelBtn:Disable()
        end
    end

    if LFbidFrame.mlBidLabel then
        if lfbid_bidMode == "points" then
            LFbidFrame.mlBidLabel:Show()
        else
            LFbidFrame.mlBidLabel:Hide()
        end
    end

    if LFbidFrame.mlBidPointsEdit then
        if lfbid_bidMode == "points" then
            LFbidFrame.mlBidPointsEdit:Show()
            if lfbid_biddingOpen then
                LFbidFrame.mlBidPointsEdit:ClearFocus()
                LFbidFrame.mlBidPointsEdit:EnableMouse(false)
            else
                LFbidFrame.mlBidPointsEdit:EnableMouse(true)
            end
        else
            LFbidFrame.mlBidPointsEdit:Hide()
        end
    end

    if LFbidFrame.mlBidSpecDropDown then
        if lfbid_bidMode == "points" then
            LFbidFrame.mlBidSpecDropDown:Show()
            if UIDropDownMenu_SetSelectedValue then
                UIDropDownMenu_SetSelectedValue(LFbidFrame.mlBidSpecDropDown, lfbid_mlBidType)
            end
            if UIDropDownMenu_SetText then
                UIDropDownMenu_SetText(lfbid_mlBidType, LFbidFrame.mlBidSpecDropDown)
            end
            if lfbid_biddingOpen and UIDropDownMenu_DisableDropDown then
                UIDropDownMenu_DisableDropDown(LFbidFrame.mlBidSpecDropDown)
            elseif UIDropDownMenu_EnableDropDown then
                UIDropDownMenu_EnableDropDown(LFbidFrame.mlBidSpecDropDown)
            end
        else
            LFbidFrame.mlBidSpecDropDown:Hide()
        end
    end

    if LFbidFrame.mlTmogCheck then
        if lfbid_bidMode == "points" then
            LFbidFrame.mlTmogCheck:Show()
            LFbidFrame.mlTmogCheck:SetChecked(lfbid_mlTmogBid and 1 or nil)
            if lfbid_biddingOpen then
                LFbidFrame.mlTmogCheck:EnableMouse(false)
            else
                LFbidFrame.mlTmogCheck:EnableMouse(true)
            end
        else
            LFbidFrame.mlTmogCheck:Hide()
        end
    end

    if LFbidFrame.mlAltCheck then
        if lfbid_bidMode == "points" then
            LFbidFrame.mlAltCheck:Show()
            LFbidFrame.mlAltCheck:SetChecked(lfbid_mlAltBid and 1 or nil)
            if lfbid_biddingOpen then
                LFbidFrame.mlAltCheck:EnableMouse(false)
            else
                LFbidFrame.mlAltCheck:EnableMouse(true)
            end
        else
            LFbidFrame.mlAltCheck:Hide()
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

    local function EnsureSpecRowButtons(cell)
        if not cell or cell.rowButtons then
            return
        end

        cell.rowButtons = {}
        local rowIndex
        for rowIndex = 1, LFBID_POINTS_VISIBLE_ROWS do
            local rowButton = CreateFrame("Button", nil, cell)
            rowButton:SetWidth(158)
            rowButton:SetHeight(12)
            if rowIndex == 1 then
                rowButton:SetPoint("TOPLEFT", cell.label, "BOTTOMLEFT", 0, -2)
            else
                rowButton:SetPoint("TOPLEFT", cell.rowButtons[rowIndex - 1], "BOTTOMLEFT", 0, 0)
            end

            rowButton.text = rowButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            rowButton.text:SetPoint("LEFT", rowButton, "LEFT", 0, 0)
            rowButton.text:SetJustifyH("LEFT")

            rowButton:SetScript("OnClick", function()
                if this and this.bidData then
                    StartManualWinnerSelectionForBid(this.bidData)
                end
            end)

            table.insert(cell.rowButtons, rowButton)
        end
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
        local startY = -118
        local frameTopOffset = 118
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

    local specs = {"MS", "OS", "T-MOG"}
    local grouped = {
        MS = {},
        OS = {},
        ["T-MOG"] = {},
    }

    local hasPrimaryMSBids = HasPrimaryMSBids()

    for _, bid in ipairs(lfbid_bids) do
        if bid then
            local normalized = GetEffectiveBidSpec(bid.spec, hasPrimaryMSBids)
            if grouped[normalized] then
                table.insert(grouped[normalized], bid)
            end
        end
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
    local startY = -118
    local frameTopOffset = 118
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
        local visibleBids = {}
        local bidList = grouped[spec] or {}
        local startIndex = (lfbid_specScrollOffsets[spec] or 0) + 1
        local endIndex = (lfbid_specScrollOffsets[spec] or 0) + LFBID_POINTS_VISIBLE_ROWS
        for idx = startIndex, endIndex do
            local bid = bidList[idx]
            if bid then
                local pointsText = tostring(bid.points or "")
                local nameText = GetBidDisplayName(bid)
                if IsUnknownZeroBid(bid) then
                    nameText = "|cff33aaff" .. nameText .. "|r"
                elseif not BidHasEnoughDKP(bid) then
                    nameText = "|cffff2020" .. nameText .. "|r"
                end
                local line = pointsText .. " " .. nameText
                if NormalizeSpec(bid.spec) == "X" then
                    line = pointsText .. " X " .. nameText
                elseif bid.altBid then
                    line = pointsText .. " ALT " .. nameText
                end
                table.insert(lines, line)
                table.insert(visibleBids, bid)
            end
        end
        if table.getn(lines) == 0 then
            lines[1] = "-"
        end

        specLines[spec] = lines
        specLines[spec .. "_BIDS"] = visibleBids
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
        EnsureSpecRowButtons(cell)

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
        if cell.text then
            cell.text:SetText("")
        end

        local visibleBidRows = specLines[spec .. "_BIDS"] or {}
        if cell.rowButtons then
            local rowIndex
            for rowIndex = 1, LFBID_POINTS_VISIBLE_ROWS do
                local rowButton = cell.rowButtons[rowIndex]
                if rowButton then
                    rowButton:SetWidth(colWidth - 34)
                    local lineText = specLines[spec][rowIndex] or ""
                    local bidData = visibleBidRows[rowIndex]
                    rowButton.bidData = bidData
                    rowButton.text:SetText(lineText)

                    if bidData and IsPlayerMasterLooter() and lfbid_manualWinnerSelectionActive and not lfbid_biddingOpen then
                        rowButton:EnableMouse(true)
                    else
                        rowButton:EnableMouse(false)
                    end

                    rowButton:Show()
                end
            end
        end
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
            if cell.rowButtons then
                local rowIndex
                for rowIndex = 1, table.getn(cell.rowButtons) do
                    if cell.rowButtons[rowIndex] then
                        cell.rowButtons[rowIndex]:Hide()
                    end
                end
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
    info.text = "X"
    info.value = "X"
    info.func = LFBidOpenDropDown_OnClick
    UIDropDownMenu_AddButton(info, level)
end

local function LFBidMLBidDropDown_OnClick()
    local value = this and this.value
    if not value then
        return
    end
    lfbid_mlBidType = value
    if LFbidFrame and LFbidFrame.mlBidSpecDropDown then
        UIDropDownMenu_SetSelectedValue(LFbidFrame.mlBidSpecDropDown, value)
        UIDropDownMenu_SetText(value, LFbidFrame.mlBidSpecDropDown)
    end
end

local function LFBidMLBidDropDown_Initialize(frame, level)
    local info

    info = UIDropDownMenu_CreateInfo()
    info.text = "MS"
    info.value = "MS"
    info.func = LFBidMLBidDropDown_OnClick
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo()
    info.text = "OS"
    info.value = "OS"
    info.func = LFBidMLBidDropDown_OnClick
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo()
    info.text = "X"
    info.value = "X"
    info.func = LFBidMLBidDropDown_OnClick
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
        lfbid_openFrame.alphaSlider:SetMinMaxValues(0, 1)
        lfbid_openFrame.alphaSlider:SetValueStep(0.01)
        lfbid_openFrame.alphaSlider:SetValue(lfbid_backdropAlpha)
        lfbid_openFrame.alphaSlider:SetScript("OnValueChanged", function()
            local value = arg1
            if not value and this and this.GetValue then
                value = this:GetValue()
            end
            if value then
                lfbid_backdropAlpha = value
                ApplyLFBidBackdropAlpha()
                PersistLFBidSettings()
            end
        end)
        if getglobal("LFBidOpenAlphaSliderText") then
            getglobal("LFBidOpenAlphaSliderText"):SetText("Background")
        end
        if getglobal("LFBidOpenAlphaSliderLow") then
            getglobal("LFBidOpenAlphaSliderLow"):SetText("")
            getglobal("LFBidOpenAlphaSliderLow"):Hide()
        end
        if getglobal("LFBidOpenAlphaSliderHigh") then
            getglobal("LFBidOpenAlphaSliderHigh"):SetText("")
            getglobal("LFBidOpenAlphaSliderHigh"):Hide()
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
            PersistLFBidSettings()
        end)
        if getglobal("LFBidOpenAltCheckButtonText") then
            getglobal("LFBidOpenAltCheckButtonText"):SetText("ALT")
        end

        lfbid_openFrame.tmogCheck = CreateFrame("CheckButton", "LFBidOpenTMOGCheckButton", lfbid_openFrame, "UICheckButtonTemplate")
        lfbid_openFrame.tmogCheck:SetPoint("LEFT", lfbid_openFrame.altCheck, "RIGHT", 26, 0)
        lfbid_openFrame.tmogCheck:SetWidth(24)
        lfbid_openFrame.tmogCheck:SetHeight(24)
        lfbid_openFrame.tmogCheck:SetChecked(lfbid_openTmogBid and 1 or nil)
        lfbid_openFrame.tmogCheck:SetScript("OnClick", function()
            lfbid_openTmogBid = this:GetChecked() and true or false
            PersistLFBidSettings()
        end)
        if getglobal("LFBidOpenTMOGCheckButtonText") then
            getglobal("LFBidOpenTMOGCheckButtonText"):SetText("TMOG")
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

            local points = ""
            if lfbid_openFrame.pointsEditBox then
                points = tostring(lfbid_openFrame.pointsEditBox:GetText() or "")
            end
            local spec = lfbid_openType or ""
            local useAltTag = false
            if lfbid_openFrame.altCheck then
                useAltTag = lfbid_openFrame.altCheck:GetChecked() and true or false
            end
            local useTmogTag = false
            if lfbid_openFrame.tmogCheck then
                useTmogTag = lfbid_openFrame.tmogCheck:GetChecked() and true or false
            end
            if useAltTag and NormalizeSpec(spec) == "X" then
                print("LFBid: ALT characters cannot bid X.")
                return
            end
            lfbid_openAltBid = useAltTag
            lfbid_openTmogBid = useTmogTag
            PersistLFBidSettings()

            local trimmedPoints = tostring(points or "")
            trimmedPoints = string.gsub(trimmedPoints, "^%s+", "")
            trimmedPoints = string.gsub(trimmedPoints, "%s+$", "")

            local msg
            if useTmogTag and trimmedPoints == "" then
                msg = "TMOG"
            else
                msg = trimmedPoints .. " " .. spec
            end
            if useAltTag then
                msg = msg .. " ALT"
            end
            if useTmogTag and string.lower(msg) ~= "tmog" and string.lower(msg) ~= "t-mog" then
                msg = msg .. " TMOG"
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

            if useTmogTag and trimmedPoints == "" then
                print("LFBid: TMOG bid placed.")
            elseif points ~= "" then
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
    if lfbid_openFrame.tmogCheck then
        lfbid_openFrame.tmogCheck:SetChecked(lfbid_openTmogBid and 1 or nil)
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

    -- Cleanup for older builds: these controls should not exist on the bidder open window.
    if lfbid_openFrame.mlStartBidBtn then
        lfbid_openFrame.mlStartBidBtn:Hide()
    end
    if lfbid_openFrame.mlStartRollBtn then
        lfbid_openFrame.mlStartRollBtn:Hide()
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

local function ReloadDKPFromFileDefaults()
    local defaults = LFTentDKPDefaults
    local reloaded = {}

    if type(defaults) == "table" then
        local name, value
        for name, value in pairs(defaults) do
            if type(value) == "table" then
                reloaded[name] = {
                    t1 = tonumber(value.t1 or value.tier1 or value[1] or value["Tier 1"] or value.Tier1 or value.points1 or value.dkp1) or 0,
                    t2 = tonumber(value.t2 or value.tier2 or value[2] or value["Tier 2"] or value.Tier2 or value.points2 or value.dkp2) or 0,
                }
            else
                reloaded[name] = tonumber(value) or 0
            end
        end
    end

    -- Replace current runtime/saved DKP table with file defaults.
    LFTentDKP = reloaded
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

        lfbid_dkpSheetFrame.reloadFileBtn = CreateFrame("Button", nil, lfbid_dkpSheetFrame, "UIPanelButtonTemplate")
        lfbid_dkpSheetFrame.reloadFileBtn:SetWidth(118)
        lfbid_dkpSheetFrame.reloadFileBtn:SetHeight(20)
        lfbid_dkpSheetFrame.reloadFileBtn:SetPoint("TOPRIGHT", lfbid_dkpSheetFrame, "TOPRIGHT", -34, -10)
        lfbid_dkpSheetFrame.reloadFileBtn:SetText("Reload From File")
        lfbid_dkpSheetFrame.reloadFileBtn:SetScript("OnClick", function()
            ReloadDKPFromFileDefaults()
            lfbid_dkpSheetScrollOffset = 0
            RefreshLFBidDKPSheetWindow()
            print("LFBid: DKP reloaded from DKPData file defaults.")
        end)

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

local function OpenLFBidAddonStatusWindow()
    if not lfbid_addonStatusFrame then
        lfbid_addonStatusFrame = CreateFrame("Frame", "LFBidAddonStatusFrame", UIParent)
        lfbid_addonStatusFrame:SetWidth(380)
        lfbid_addonStatusFrame:SetHeight(360)
        lfbid_addonStatusFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
        lfbid_addonStatusFrame:SetFrameStrata("DIALOG")
        lfbid_addonStatusFrame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        lfbid_addonStatusFrame:SetBackdropColor(0, 0, 0, lfbid_backdropAlpha)
        lfbid_addonStatusFrame:EnableMouse(true)
        lfbid_addonStatusFrame:SetMovable(true)
        lfbid_addonStatusFrame:RegisterForDrag("LeftButton")
        lfbid_addonStatusFrame:SetScript("OnDragStart", function()
            lfbid_addonStatusFrame:StartMoving()
        end)
        lfbid_addonStatusFrame:SetScript("OnDragStop", function()
            lfbid_addonStatusFrame:StopMovingOrSizing()
        end)

        lfbid_addonStatusFrame.title = lfbid_addonStatusFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lfbid_addonStatusFrame.title:SetPoint("TOPLEFT", lfbid_addonStatusFrame, "TOPLEFT", 10, -14)
        lfbid_addonStatusFrame.title:SetText("LFBid Addon Status")

        lfbid_addonStatusFrame.closeBtn = CreateFrame("Button", nil, lfbid_addonStatusFrame, "UIPanelButtonTemplate")
        lfbid_addonStatusFrame.closeBtn:SetWidth(24)
        lfbid_addonStatusFrame.closeBtn:SetHeight(24)
        lfbid_addonStatusFrame.closeBtn:SetPoint("TOPRIGHT", lfbid_addonStatusFrame, "TOPRIGHT", -4, -4)
        lfbid_addonStatusFrame.closeBtn:SetText("X")
        lfbid_addonStatusFrame.closeBtn:SetScript("OnClick", function()
            lfbid_addonStatusFrame:Hide()
            lfbid_addonStatusWindowOpen = false
        end)

        lfbid_addonStatusFrame.refreshBtn = CreateFrame("Button", nil, lfbid_addonStatusFrame, "UIPanelButtonTemplate")
        lfbid_addonStatusFrame.refreshBtn:SetWidth(110)
        lfbid_addonStatusFrame.refreshBtn:SetHeight(24)
        lfbid_addonStatusFrame.refreshBtn:SetPoint("TOPRIGHT", lfbid_addonStatusFrame.closeBtn, "TOPLEFT", -8, 0)
        lfbid_addonStatusFrame.refreshBtn:SetText("Refresh")
        lfbid_addonStatusFrame.refreshBtn:SetScript("OnClick", function()
            StartLFBidAddonStatusScan()
        end)

        lfbid_addonStatusFrame.statusText = lfbid_addonStatusFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lfbid_addonStatusFrame.statusText:SetPoint("TOPLEFT", lfbid_addonStatusFrame.title, "BOTTOMLEFT", 0, -10)
        lfbid_addonStatusFrame.statusText:SetWidth(350)
        lfbid_addonStatusFrame.statusText:SetJustifyH("LEFT")

        lfbid_addonStatusFrame.installedHeader = lfbid_addonStatusFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lfbid_addonStatusFrame.installedHeader:SetPoint("TOPLEFT", lfbid_addonStatusFrame.statusText, "BOTTOMLEFT", 0, -12)
        lfbid_addonStatusFrame.installedHeader:SetText("Installed")

        lfbid_addonStatusFrame.missingHeader = lfbid_addonStatusFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lfbid_addonStatusFrame.missingHeader:SetPoint("TOPLEFT", lfbid_addonStatusFrame.installedHeader, "TOPLEFT", 180, 0)
        lfbid_addonStatusFrame.missingHeader:SetText("NOT Installed")

        lfbid_addonStatusFrame.installedText = lfbid_addonStatusFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lfbid_addonStatusFrame.installedText:SetPoint("TOPLEFT", lfbid_addonStatusFrame.installedHeader, "BOTTOMLEFT", 0, -6)
        lfbid_addonStatusFrame.installedText:SetWidth(165)
        lfbid_addonStatusFrame.installedText:SetJustifyH("LEFT")
        lfbid_addonStatusFrame.installedText:SetJustifyV("TOP")

        lfbid_addonStatusFrame.missingText = lfbid_addonStatusFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lfbid_addonStatusFrame.missingText:SetPoint("TOPLEFT", lfbid_addonStatusFrame.missingHeader, "BOTTOMLEFT", 0, -6)
        lfbid_addonStatusFrame.missingText:SetWidth(165)
        lfbid_addonStatusFrame.missingText:SetJustifyH("LEFT")
        lfbid_addonStatusFrame.missingText:SetJustifyV("TOP")

        lfbid_addonStatusFrame.RefreshLists = function()
            local installedLines = {}
            local missingLines = {}
            local _, normalizedName

            if lfbid_addonStatusScanActive then
                lfbid_addonStatusFrame.statusText:SetText("Scanning raid for LFBid responses...")
            else
                local expectedCount = table.getn(GetSortedLFBidStatusNames(lfbid_addonStatusExpected))
                local installedCount = table.getn(lfbid_addonStatusDisplayInstalled or {})
                local missingCount = table.getn(lfbid_addonStatusDisplayMissing or {})
                lfbid_addonStatusFrame.statusText:SetText("Installed: " .. tostring(installedCount) .. " / " .. tostring(expectedCount) .. "  |  Missing: " .. tostring(missingCount))
            end

            for _, normalizedName in ipairs(lfbid_addonStatusDisplayInstalled or {}) do
                local entry = lfbid_addonStatusInstalled[normalizedName]
                local line = tostring((entry and entry.displayName) or normalizedName or "")
                local versionText = tostring((entry and entry.version) or "")
                if versionText ~= "" then
                    line = line .. " (v" .. versionText .. ")"
                end
                table.insert(installedLines, line)
            end

            for _, normalizedName in ipairs(lfbid_addonStatusDisplayMissing or {}) do
                local entry = lfbid_addonStatusMissing[normalizedName]
                table.insert(missingLines, tostring((entry and entry.displayName) or normalizedName or ""))
            end

            if table.getn(installedLines) == 0 then
                if lfbid_addonStatusScanActive then
                    installedLines[1] = "Waiting for replies..."
                else
                    installedLines[1] = "-"
                end
            end

            if table.getn(missingLines) == 0 then
                if lfbid_addonStatusScanActive then
                    missingLines[1] = "Waiting for scan..."
                else
                    missingLines[1] = "-"
                end
            end

            lfbid_addonStatusFrame.installedText:SetText(table.concat(installedLines, "\n"))
            lfbid_addonStatusFrame.missingText:SetText(table.concat(missingLines, "\n"))
        end
    end

    lfbid_addonStatusFrame:SetBackdropColor(0, 0, 0, lfbid_backdropAlpha)
    lfbid_addonStatusWindowOpen = true
    lfbid_addonStatusFrame:Show()
    if lfbid_addonStatusFrame.RefreshLists then
        lfbid_addonStatusFrame:RefreshLists()
    end
end

local function OpenLFBidOptionsWindow()
    if not lfbid_optionsFrame then
        lfbid_optionsFrame = CreateFrame("Frame", "LFBidOptionsFrame", UIParent)
        lfbid_optionsFrame:SetWidth(260)
        lfbid_optionsFrame:SetHeight(300)
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

        lfbid_optionsFrame.addonStatusBtn = CreateFrame("Button", nil, lfbid_optionsFrame, "UIPanelButtonTemplate")
        lfbid_optionsFrame.addonStatusBtn:SetWidth(200)
        lfbid_optionsFrame.addonStatusBtn:SetHeight(26)
        lfbid_optionsFrame.addonStatusBtn:SetPoint("TOP", lfbid_optionsFrame.showDKPSheetBtn, "BOTTOM", 0, -10)
        lfbid_optionsFrame.addonStatusBtn:SetText("Who has addon")
        lfbid_optionsFrame.addonStatusBtn:SetScript("OnClick", function()
            OpenLFBidAddonStatusWindow()
            StartLFBidAddonStatusScan()
        end)

        lfbid_optionsFrame.raidTierLabel = lfbid_optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lfbid_optionsFrame.raidTierLabel:SetPoint("TOPLEFT", lfbid_optionsFrame.addonStatusBtn, "BOTTOMLEFT", 0, -14)
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
        LFbidFrame.alphaSlider:SetMinMaxValues(0, 1)
        LFbidFrame.alphaSlider:SetValueStep(0.01)
        LFbidFrame.alphaSlider:SetValue(lfbid_backdropAlpha)
        LFbidFrame.alphaSlider:SetScript("OnValueChanged", function()
            local value = arg1
            if not value and this and this.GetValue then
                value = this:GetValue()
            end
            if value then
                lfbid_backdropAlpha = value
                ApplyLFBidBackdropAlpha()
                PersistLFBidSettings()
            end
        end)
        if getglobal("LFBidMasterAlphaSliderText") then
            getglobal("LFBidMasterAlphaSliderText"):SetText("Background")
        end
        if getglobal("LFBidMasterAlphaSliderLow") then
            getglobal("LFBidMasterAlphaSliderLow"):SetText("")
            getglobal("LFBidMasterAlphaSliderLow"):Hide()
        end
        if getglobal("LFBidMasterAlphaSliderHigh") then
            getglobal("LFBidMasterAlphaSliderHigh"):SetText("")
            getglobal("LFBidMasterAlphaSliderHigh"):Hide()
        end

        LFbidFrame.startBtn = CreateFrame("Button", nil, LFbidFrame, "UIPanelButtonTemplate")
        LFbidFrame.startBtn:SetWidth(90)
        LFbidFrame.startBtn:SetHeight(24)
        LFbidFrame.startBtn:SetPoint("TOP", LFbidFrame, "TOP", -96, -36)
        LFbidFrame.startBtn:SetText("Start Bid")
        LFbidFrame.startBtn:SetScript("OnClick", function()
            StartPointsBiddingFromMasterWindow()
        end)

        -- Stop Bids button (top center)
        LFbidFrame.stopBtn = CreateFrame("Button", nil, LFbidFrame, "UIPanelButtonTemplate")
        LFbidFrame.stopBtn:SetWidth(90)
        LFbidFrame.stopBtn:SetHeight(24)
        LFbidFrame.stopBtn:SetPoint("TOP", LFbidFrame, "TOP", 0, -36)
        LFbidFrame.stopBtn:SetText("Stop Bids")
            LFbidFrame.stopBtn:SetScript("OnClick", function()
                CloseBidding()
            end)

        LFbidFrame.cancelBtn = CreateFrame("Button", nil, LFbidFrame, "UIPanelButtonTemplate")
        LFbidFrame.cancelBtn:SetWidth(90)
        LFbidFrame.cancelBtn:SetHeight(24)
        LFbidFrame.cancelBtn:SetPoint("TOP", LFbidFrame, "TOP", 96, -36)
        LFbidFrame.cancelBtn:SetText("Cancel Bid")
        LFbidFrame.cancelBtn:SetScript("OnClick", function()
            CancelBidding()
        end)

        LFbidFrame.dkpCheckBox = CreateFrame("CheckButton", "LFBidUseDKPCheckBox", LFbidFrame, "UICheckButtonTemplate")
        LFbidFrame.dkpCheckBox:SetWidth(24)
        LFbidFrame.dkpCheckBox:SetHeight(24)
        LFbidFrame.dkpCheckBox:SetPoint("TOPRIGHT", LFbidFrame, "TOPRIGHT", -28, -16)
        LFbidFrame.dkpCheckBox:SetChecked(lfbid_useDKPCheck)
        LFbidFrame.dkpCheckBox:SetScript("OnClick", function()
            lfbid_useDKPCheck = this:GetChecked() and 1 or nil
            PersistLFBidSettings()
            RefreshLFBidBidList()
        end)
        if getglobal("LFBidUseDKPCheckBoxText") then
            getglobal("LFBidUseDKPCheckBoxText"):SetText("Check DKP")
            getglobal("LFBidUseDKPCheckBoxText"):ClearAllPoints()
            getglobal("LFBidUseDKPCheckBoxText"):SetPoint("RIGHT", LFbidFrame.dkpCheckBox, "LEFT", -2, 1)
        end

        LFbidFrame.mlBidLabel = LFbidFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        LFbidFrame.mlBidLabel:SetPoint("TOP", LFbidFrame, "TOP", -150, -70)
        LFbidFrame.mlBidLabel:SetText("ML Bid   ")

        LFbidFrame.mlBidPointsEdit = CreateFrame("EditBox", nil, LFbidFrame, "InputBoxTemplate")
        LFbidFrame.mlBidPointsEdit:SetWidth(58)
        LFbidFrame.mlBidPointsEdit:SetHeight(18)
        LFbidFrame.mlBidPointsEdit:SetPoint("LEFT", LFbidFrame.mlBidLabel, "RIGHT", 6, 0)
        LFbidFrame.mlBidPointsEdit:SetAutoFocus(false)

        LFbidFrame.mlBidSpecDropDown = CreateFrame("Frame", "LFBidMasterMLBidSpecDropDown", LFbidFrame, "UIDropDownMenuTemplate")
        LFbidFrame.mlBidSpecDropDown:SetPoint("LEFT", LFbidFrame.mlBidPointsEdit, "RIGHT", -8, -4)
        UIDropDownMenu_SetWidth(70, LFbidFrame.mlBidSpecDropDown)
        UIDropDownMenu_Initialize(LFbidFrame.mlBidSpecDropDown, LFBidMLBidDropDown_Initialize)
        UIDropDownMenu_SetSelectedValue(LFbidFrame.mlBidSpecDropDown, lfbid_mlBidType)
        UIDropDownMenu_SetText(lfbid_mlBidType, LFbidFrame.mlBidSpecDropDown)

        LFbidFrame.mlAltCheck = CreateFrame("CheckButton", "LFBidMasterMLAltCheckButton", LFbidFrame, "UICheckButtonTemplate")
        LFbidFrame.mlAltCheck:SetPoint("LEFT", LFbidFrame.mlBidSpecDropDown, "RIGHT", -12, 0)
        LFbidFrame.mlAltCheck:SetWidth(24)
        LFbidFrame.mlAltCheck:SetHeight(24)
        LFbidFrame.mlAltCheck:SetChecked(lfbid_mlAltBid and 1 or nil)
        LFbidFrame.mlAltCheck:SetScript("OnClick", function()
            lfbid_mlAltBid = this:GetChecked() and true or false
            RefreshMasterLootButtons()
        end)
        if getglobal("LFBidMasterMLAltCheckButtonText") then
            getglobal("LFBidMasterMLAltCheckButtonText"):SetText("ALT  ")
        end

        LFbidFrame.mlTmogCheck = CreateFrame("CheckButton", "LFBidMasterMLTMOGCheckButton", LFbidFrame, "UICheckButtonTemplate")
        LFbidFrame.mlTmogCheck:SetPoint("LEFT", LFbidFrame.mlAltCheck, "RIGHT", 16, 0)
        LFbidFrame.mlTmogCheck:SetWidth(24)
        LFbidFrame.mlTmogCheck:SetHeight(24)
        LFbidFrame.mlTmogCheck:SetChecked(lfbid_mlTmogBid and 1 or nil)
        LFbidFrame.mlTmogCheck:SetScript("OnClick", function()
            lfbid_mlTmogBid = this:GetChecked() and true or false
            RefreshMasterLootButtons()
        end)
        if getglobal("LFBidMasterMLTMOGCheckButtonText") then
            getglobal("LFBidMasterMLTMOGCheckButtonText"):SetText("T-MOG")
        end

        LFbidFrame.text = LFbidFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        if LFbidFrame.text then
            LFbidFrame.text:SetPoint("TOP", LFbidFrame, "TOP", 0, -94)
        end

        LFbidFrame.itemLinkButton = CreateFrame("Button", nil, LFbidFrame)
        LFbidFrame.itemLinkButton:SetWidth(380)
        LFbidFrame.itemLinkButton:SetHeight(18)
        LFbidFrame.itemLinkButton:SetPoint("TOP", LFbidFrame, "TOP", 0, -94)
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
        LFbidFrame.bidScrollBar:SetPoint("TOPRIGHT", LFbidFrame, "TOPRIGHT", -8, -118)
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
    if LFbidFrame.mlBidPointsEdit then
        LFbidFrame.mlBidPointsEdit:SetText("")
    end
    if LFbidFrame.mlBidSpecDropDown then
        UIDropDownMenu_SetSelectedValue(LFbidFrame.mlBidSpecDropDown, lfbid_mlBidType)
        UIDropDownMenu_SetText(lfbid_mlBidType, LFbidFrame.mlBidSpecDropDown)
    end
    if LFbidFrame.mlTmogCheck then
        LFbidFrame.mlTmogCheck:SetChecked(lfbid_mlTmogBid and 1 or nil)
    end
    if LFbidFrame.mlAltCheck then
        LFbidFrame.mlAltCheck:SetChecked(lfbid_mlAltBid and 1 or nil)
    end
    lfbid_bidMode = bidMode or "points"
    lfbid_bids = {}
    lfbid_rollSeen = {}
    lfbid_manualWinnerSelectionActive = false
    lfbid_pendingManualWinnerBid = nil
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
            if lfbid_windowOpen then
                RefreshLFBidBidList()
            end
            return
        end

        if not lfbid_biddingOpen then
            return
        end

        if lfbid_bidMode == "roll" then
            return
        end

        -- Only the active Master Looter should parse whisper bids.
        if evt == "CHAT_MSG_WHISPER" and not IsPlayerMasterLooter() then
            return
        end

        -- Addon bid payloads are mirrored to the group; only ML should parse them here.
        -- Start/close sync is handled by lfbid_openSyncFrame separately.
        if evt == "CHAT_MSG_ADDON" and not IsPlayerMasterLooter() then
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

        if sourceType == "addon" then
            local myName = NormalizeBidderName(UnitName("player"))
            local senderName = NormalizeBidderName(sender)
            if myName ~= "" and senderName ~= "" and string.lower(myName) == string.lower(senderName) then
                -- Ignore our own mirrored addon payloads.
                return
            end
        end

        if sourceType == "addon" and ExtractStartPayload(msg) ~= nil then
            return
        end
        if sourceType == "addon" and IsClosePayload(msg) then
            return
        end
        if sourceType == "addon" and ParseLFBidStatusRequest(msg) then
            return
        end
        if sourceType == "addon" then
            local statusToken = ParseLFBidStatusResponse(msg)
            if statusToken then
                return
            end
        end
        if sourceType == "addon" then
            local addonChannel = p3 or arg3
            local dkpPlayer = ParseDKPDeltaMessage(msg)
            if addonChannel == "RAID" and dkpPlayer then
                return
            end
        end

        local finalName, points, spec, altBid, tmogBid = ParseBidMessage(msg, sender)

        if finalName then
            local insertedBid = false
            local normalizedSpec = NormalizeSpec(spec)
            if altBid and normalizedSpec == "X" then
                if IsPlayerMasterLooter() then
                    print("LFBid: Ignored X bid from alt-tagged bidder " .. tostring(finalName) .. ".")
                end
                return
            end

            RemoveExistingBidForPlayer(finalName)

            if points ~= nil and spec and spec ~= "" and not IsSupportedBidSpec(normalizedSpec) then
                if IsPlayerMasterLooter() then
                    print("LFBid: Ignored invalid spec from " .. tostring(finalName) .. ": " .. tostring(spec))
                end
                return
            end

            if points ~= nil and spec and spec ~= "" and normalizedSpec ~= "T-MOG" then
                table.insert(lfbid_bids, {
                    name = finalName,
                    points = points,
                    spec = spec,
                    altBid = altBid and true or false,
                    whisperBid = evt == "CHAT_MSG_WHISPER",
                })
                insertedBid = true
            elseif points ~= nil and spec and spec ~= "" and normalizedSpec == "T-MOG" then
                tmogBid = true
            end

            if tmogBid then
                table.insert(lfbid_bids, {
                    name = finalName,
                    points = GenerateRandomTmogRoll(),
                    spec = "T-MOG",
                    altBid = altBid and true or false,
                    whisperBid = evt == "CHAT_MSG_WHISPER",
                })
                insertedBid = true
            end

            if not insertedBid then
                local amML = IsPlayerMasterLooter()
                if amML then
                    print("LFBid: Failed to parse " .. sourceType .. " bid from " .. (sender or "unknown") .. ": " .. (msg or "no message"))
                end
                return
            end

            if lfbid_windowOpen then
                RefreshLFBidBidList()
            end
        else
            local amML = IsPlayerMasterLooter()
            if amML then
                print("LFBid: Failed to parse " .. sourceType .. " bid from " .. (sender or "unknown") .. ": " .. (msg or "no message"))
            end
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
        if not LFBID_ENABLE_DKP_DELTA_SYNC then
            return
        end

        local dkpPlayer, dkpDelta = ParseDKPDeltaMessage(msg)
        if dkpPlayer and dkpDelta then
            if ApplyDKPDelta(dkpPlayer, dkpDelta) and lfbid_windowOpen then
                RefreshLFBidBidList()
            end
            return
        end

        if IsPlayerMasterLooter() then
            print("LFBid: Received LFDKP message but could not parse: " .. tostring(msg))
        end
        return
    end

    if prefix ~= LFBID_ADDON_PREFIX then
        return
    end

    local myName = NormalizeBidderName(UnitName("player"))
    local senderName = NormalizeBidderName(sender)

    local statusRequestToken = ParseLFBidStatusRequest(msg)
    if statusRequestToken then
        if channel == "RAID" and senderName ~= "" and myName ~= "" and string.lower(senderName) ~= string.lower(myName) then
            SendAddonMessage(LFBID_ADDON_PREFIX, BuildLFBidStatusResponse(statusRequestToken, GetLFBidVersionText()), "RAID")
        end
        return
    end

    local statusResponseToken, statusVersion = ParseLFBidStatusResponse(msg)
    if statusResponseToken then
        if lfbid_addonStatusScanActive and lfbid_addonStatusScanToken and statusResponseToken == lfbid_addonStatusScanToken then
            if senderName ~= "" and lfbid_addonStatusExpected[senderName] then
                lfbid_addonStatusInstalled[senderName] = {
                    displayName = tostring(lfbid_addonStatusExpected[senderName].displayName or senderName),
                    version = tostring(statusVersion or "unknown"),
                }
                lfbid_addonStatusDisplayInstalled = GetSortedLFBidStatusNames(lfbid_addonStatusInstalled)
                if lfbid_addonStatusFrame and lfbid_addonStatusFrame.RefreshLists then
                    lfbid_addonStatusFrame:RefreshLists()
                end
            end
        end
        return
    end

    local startItemLink = ExtractStartPayload(msg)
    local isClose = IsClosePayload(msg)
    if startItemLink == nil and not isClose then
        return
    end

    if sender and myName and string.lower(sender) == string.lower(myName) then
        return
    end

    if isClose then
        lfbid_biddingOpen = false
        lfbid_openItemLink = ""
        if lfbid_openFrame and lfbid_openWindowOpen then
            lfbid_openFrame:Hide()
            lfbid_openWindowOpen = false
            if IsPlayerMasterLooter() then
                print("LFBid: Bidding is now closed.")
            end
        end
        return
    end

    lfbid_openItemLink = tostring(startItemLink or "")
    lfbid_biddingOpen = true
    OpenLFBidOpenWindow()
end)

local lfbid_itemContextMenuFrame
local lfbid_itemContextLink = nil
local lfbid_originalSetItemRef = nil

StartBiddingForItemLink = function(itemLink, mode)
    local normalizedItemLink = tostring(itemLink or "")
    if normalizedItemLink == "" then
        print("LFBid: Could not determine item link.")
        return
    end

    if not IsPlayerMasterLooter() then
        print("LFBid: Starting bids from item menu is only available to the Master Looter.")
        return
    end

    if lfbid_windowOpen then
        print("Bidding window already open. Close it first with the X button.")
        return
    end

    if mode == "roll" then
        lfbid_activeItem = normalizedItemLink
        lfbid_openItemLink = ""
        lfbid_biddingOpen = true
        lfbid_bidMode = "roll"
        lfbid_rollSeen = {}
        SendSafeChatMessage("Start rolling for item: " .. normalizedItemLink, "RAID_WARNING")
        OpenLFBidWindow(normalizedItemLink, "roll")
        return
    end

    lfbid_activeItem = normalizedItemLink
    lfbid_openItemLink = normalizedItemLink
    lfbid_biddingOpen = false
    lfbid_bidMode = "points"
    OpenLFBidWindow(normalizedItemLink, "points")
end

-- Cross-addon bridge for integrations (XLootMaster, etc.).
LFBid_StartBiddingForItemLink = function(itemLink, mode)
    StartBiddingForItemLink(itemLink, mode)
end

local function ExtractItemLinkFromItemRef(link, text)
    local textValue = tostring(text or "")
    local _, _, hyperlink = string.find(textValue, "(|Hitem:.-|h%[.-%]|h)")
    if hyperlink and hyperlink ~= "" then
        return hyperlink
    end

    local linkValue = tostring(link or "")
    if string.sub(linkValue, 1, 5) == "item:" then
        local itemName = nil
        if GetItemInfo then
            itemName = GetItemInfo(linkValue)
        end
        if itemName and itemName ~= "" then
            return "|H" .. linkValue .. "|h[" .. itemName .. "]|h"
        end
        return "|H" .. linkValue .. "|h[item]|h"
    end

    return nil
end

local function LFBidItemContextMenu_OnStartPoints()
    StartBiddingForItemLink(lfbid_itemContextLink, "points")
end

local function LFBidItemContextMenu_OnStartRoll()
    StartBiddingForItemLink(lfbid_itemContextLink, "roll")
end

local function LFBidItemContextMenu_Initialize(frame, level)
    if not level or level ~= 1 then
        return
    end

    local canStart = IsPlayerMasterLooter() and not lfbid_windowOpen

    local info = UIDropDownMenu_CreateInfo()
    info.isTitle = 1
    info.notCheckable = 1
    info.text = "LFBid"
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo()
    info.text = "Start bidding (points)"
    info.func = LFBidItemContextMenu_OnStartPoints
    info.notCheckable = 1
    info.disabled = canStart and nil or 1
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo()
    info.text = "Start rolling (1-100)"
    info.func = LFBidItemContextMenu_OnStartRoll
    info.notCheckable = 1
    info.disabled = canStart and nil or 1
    UIDropDownMenu_AddButton(info, level)
end

local function ShowLFBidItemContextMenu(itemLink)
    if not itemLink or itemLink == "" then
        return
    end

    if not lfbid_itemContextMenuFrame then
        lfbid_itemContextMenuFrame = CreateFrame("Frame", "LFBidItemContextMenuFrame", UIParent, "UIDropDownMenuTemplate")
        UIDropDownMenu_Initialize(lfbid_itemContextMenuFrame, LFBidItemContextMenu_Initialize, "MENU")
    end

    lfbid_itemContextLink = itemLink
    ToggleDropDownMenu(1, nil, lfbid_itemContextMenuFrame, "cursor", 0, 0)
end

local function RegisterLFBidItemRefHook()
    if lfbid_originalSetItemRef then
        return
    end

    lfbid_originalSetItemRef = SetItemRef
    SetItemRef = function(link, text, button, chatFrame)
        local clickedButton = button

        if clickedButton == "RightButton" then
            local itemLink = ExtractItemLinkFromItemRef(link, text)
            if itemLink and itemLink ~= "" then
                ShowLFBidItemContextMenu(itemLink)
                return
            end
        end

        if lfbid_originalSetItemRef then
            return lfbid_originalSetItemRef(link, text, button, chatFrame)
        end
    end
end

local lfbid_lootHookFrame = nil
local lfbid_originalLootFrameUpdate = nil
local lfbid_masterLootDropdownHooked = false
local lfbid_masterLootOriginalInitialize = nil
local lfbid_masterLootMenuSlot = nil
local lfbid_masterLootMenuItemLink = nil
local lfbid_debugEnabled = false
local lfbid_toggleDropDownHooked = false
local lfbid_originalToggleDropDownMenu = nil
local lfbid_rollForButton = nil
local lfbid_rollForMenuFrame = nil
local lfbid_rollForMenuEntries = {}
local lfbid_rollForPopupBidBtn = nil
local lfbid_rollForPopupRollBtn = nil
local lfbid_rollForPopupUpdateElapsed = 0

local function LFBidDebug(message)
    if not lfbid_debugEnabled then
        return
    end
    print("LFBid DEBUG: " .. tostring(message or ""))
end

local function ResolveDropDownFrame(frameRef)
    if type(frameRef) == "table" then
        return frameRef
    end
    if type(frameRef) == "string" and getglobal then
        return getglobal(frameRef)
    end
    return nil
end

local function IsGiveLootMenuTitle(level)
    local lvl = tonumber(level) or 1
    local textWidget = getglobal("DropDownList" .. tostring(lvl) .. "Button1NormalText")
    if not textWidget or not textWidget.GetText then
        return false
    end

    local text = tostring(textWidget:GetText() or "")
    if text == "" then
        return false
    end

    local lower = string.lower(text)
    if string.find(lower, "give loot to", 1, true) then
        return true
    end

    return false
end

local function HookLootButtonsForLFBid()
    local maxButtons = 16
    local index
    for index = 1, maxButtons do
        local button = getglobal("LootButton" .. tostring(index))
        if button and not button.lfbidHooked then
            button.lfbidHooked = true
            button.lfbidOriginalOnClick = button:GetScript("OnClick")
            button:SetScript("OnClick", function(self, mouseButton)
                local clickedButton = mouseButton
                local buttonFrame = self

                if not clickedButton and _G then
                    clickedButton = _G.arg1
                end
                if (not buttonFrame) and _G then
                    buttonFrame = _G.this
                end

                if buttonFrame and buttonFrame.GetID then
                    local clickedSlotId = tonumber(buttonFrame:GetID())
                    if clickedSlotId then
                        lfbid_masterLootMenuSlot = clickedSlotId
                    end
                end

                if clickedButton == "RightButton" and buttonFrame and buttonFrame.GetID and GetLootSlotLink then
                    local slotId = buttonFrame:GetID()
                    local itemLink = GetLootSlotLink(slotId)
                    if itemLink and itemLink ~= "" then
                        ShowLFBidItemContextMenu(itemLink)
                        return
                    end
                end

                if buttonFrame and buttonFrame.lfbidOriginalOnClick then
                    return buttonFrame.lfbidOriginalOnClick(self, mouseButton)
                end
            end)
        end
    end
end

local function ResolveItemLinkFromRollForButton(buttonFrame)
    if not buttonFrame then
        return nil
    end

    local slotCandidates = {}

    local function PushSlotCandidate(value)
        local n = tonumber(value)
        if n and n > 0 then
            table.insert(slotCandidates, n)
        end
    end

    if buttonFrame.slot then
        PushSlotCandidate(buttonFrame.slot)
    end
    if buttonFrame.GetID then
        PushSlotCandidate(buttonFrame:GetID())
    end

    local parent = buttonFrame.GetParent and buttonFrame:GetParent() or nil
    if parent then
        if parent.slot then
            PushSlotCandidate(parent.slot)
        end
        if parent.GetID then
            PushSlotCandidate(parent:GetID())
        end
    end

    if GetLootSlotLink then
        local _, slotId
        for _, slotId in ipairs(slotCandidates) do
            local itemLink = GetLootSlotLink(slotId)
            if itemLink and itemLink ~= "" then
                lfbid_masterLootMenuSlot = slotId
                return itemLink
            end
        end
    end

    return nil
end

local function HookRollForFrameClickTarget(frame)
    if not frame or frame.lfbidRollForHooked then
        return
    end

    if type(frame.IsObjectType) ~= "function" then
        return
    end

    if not frame:IsObjectType("Button") and not frame:IsObjectType("CheckButton") then
        return
    end

    if type(frame.GetScript) ~= "function" then
        return
    end

    local originalOnClick = frame:GetScript("OnClick")
    if type(originalOnClick) ~= "function" then
        return
    end

    if type(frame.RegisterForClicks) == "function" then
        frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end

    frame.lfbidRollForHooked = true
    frame.lfbidOriginalOnClick = originalOnClick
    frame:SetScript("OnClick", function(self, mouseButton)
        local clickedButton = mouseButton or (_G and _G.arg1)
        local clickFrame = self or (_G and _G.this)

        if clickedButton == "RightButton" then
            local itemLink = ResolveItemLinkFromRollForButton(clickFrame)
            if itemLink and itemLink ~= "" then
                ShowLFBidItemContextMenu(itemLink)
                return
            end
        end

        if clickFrame and clickFrame.lfbidOriginalOnClick then
            return clickFrame.lfbidOriginalOnClick(self, mouseButton)
        end
    end)
end

local function UpdateRollForRowActionButtonState(frame)
    if not frame or not frame.lfbidBidButton or not frame.lfbidRollButton then
        return
    end

    local itemLink = frame.lfbidCurrentItemLink
    local hasItem = itemLink and itemLink ~= ""
    local canStart = hasItem and IsPlayerMasterLooter() and not lfbid_windowOpen

    if hasItem then
        frame.lfbidBidButton:Show()
        frame.lfbidRollButton:Show()
    else
        frame.lfbidBidButton:Hide()
        frame.lfbidRollButton:Hide()
        return
    end

    if canStart then
        frame.lfbidBidButton:Enable()
        frame.lfbidRollButton:Enable()
    else
        frame.lfbidBidButton:Disable()
        frame.lfbidRollButton:Disable()
    end
end

local function EnsureRollForRowActionButtons(frame)
    if not frame or type(frame.SetItem) ~= "function" then
        return
    end

    if not LFBID_ENABLE_ROLLFOR_ROW_BUTTONS then
        if frame.lfbidBidButton then
            frame.lfbidBidButton:Hide()
        end
        if frame.lfbidRollButton then
            frame.lfbidRollButton:Hide()
        end
        return
    end

    if not frame.lfbidOriginalSetItem then
        frame.lfbidOriginalSetItem = frame.SetItem
        frame.SetItem = function(self, itemData)
            self.lfbidCurrentItemLink = itemData and itemData.link or nil
            self.lfbidCurrentItemSlot = itemData and itemData.slot or nil

            local result = self.lfbidOriginalSetItem(self, itemData)
            UpdateRollForRowActionButtonState(self)
            return result
        end
    end

    if frame.lfbidBidButton and frame.lfbidRollButton then
        UpdateRollForRowActionButtonState(frame)
        return
    end

    frame.lfbidBidButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.lfbidBidButton:SetWidth(30)
    frame.lfbidBidButton:SetHeight(16)
    frame.lfbidBidButton:SetText("Bid")
    frame.lfbidBidButton:SetPoint("RIGHT", frame, "RIGHT", -38, 0)
    frame.lfbidBidButton:SetScript("OnClick", function()
        if frame.lfbidCurrentItemLink and frame.lfbidCurrentItemLink ~= "" then
            StartBiddingForItemLink(frame.lfbidCurrentItemLink, "points")
        end
    end)

    frame.lfbidRollButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.lfbidRollButton:SetWidth(30)
    frame.lfbidRollButton:SetHeight(16)
    frame.lfbidRollButton:SetText("Roll")
    frame.lfbidRollButton:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
    frame.lfbidRollButton:SetScript("OnClick", function()
        if frame.lfbidCurrentItemLink and frame.lfbidCurrentItemLink ~= "" then
            StartBiddingForItemLink(frame.lfbidCurrentItemLink, "roll")
        end
    end)

    UpdateRollForRowActionButtonState(frame)
end

local function HookRollForLootButtonsForLFBid()
    local root = getglobal and getglobal("RollForLootFrame") or nil
    local header = getglobal and getglobal("RollForLootFrameHeader") or nil
    if not root and not header then
        return
    end

    local visited = {}
    local function HookFrameRecursive(frame)
        if not frame or visited[frame] then
            return
        end
        visited[frame] = true

        EnsureRollForRowActionButtons(frame)
        HookRollForFrameClickTarget(frame)

        if frame.icon then
            HookRollForFrameClickTarget(frame.icon)
        end

        if frame.comment then
            HookRollForFrameClickTarget(frame.comment)
        end

        local children = { frame:GetChildren() }
        local _, child
        for _, child in ipairs(children) do
            HookFrameRecursive(child)
        end
    end

    if root then
        HookFrameRecursive(root)
    end
    if header then
        HookFrameRecursive(header)
    end
end

local function BuildRollForLootMenuEntries()
    lfbid_rollForMenuEntries = {}

    if not GetNumLootItems or not GetLootSlotLink then
        return
    end

    local lootCount = tonumber(GetNumLootItems()) or 0
    local slot
    for slot = 1, lootCount do
        local itemLink = GetLootSlotLink(slot)
        if itemLink and itemLink ~= "" then
            table.insert(lfbid_rollForMenuEntries, {
                slot = slot,
                link = itemLink,
            })
        end
    end
end

local function LFBidRollForMenu_OnStartPoints(link)
    StartBiddingForItemLink(link, "points")
end

local function LFBidRollForMenu_OnStartRoll(link)
    StartBiddingForItemLink(link, "roll")
end

local function LFBidRollForMenu_Initialize(_, level)
    if not level or level ~= 1 then
        return
    end

    local info = UIDropDownMenu_CreateInfo()
    info.isTitle = 1
    info.notCheckable = 1
    info.text = "LFBid"
    UIDropDownMenu_AddButton(info, level)

    if not IsPlayerMasterLooter() then
        info = UIDropDownMenu_CreateInfo()
        info.notCheckable = 1
        info.disabled = 1
        info.text = "Master Looter only"
        UIDropDownMenu_AddButton(info, level)
        return
    end

    if lfbid_windowOpen then
        info = UIDropDownMenu_CreateInfo()
        info.notCheckable = 1
        info.disabled = 1
        info.text = "Close current LFBid window first"
        UIDropDownMenu_AddButton(info, level)
        return
    end

    if table.getn(lfbid_rollForMenuEntries) == 0 then
        info = UIDropDownMenu_CreateInfo()
        info.notCheckable = 1
        info.disabled = 1
        info.text = "No loot items found"
        UIDropDownMenu_AddButton(info, level)
        return
    end

    local _, entry
    for _, entry in ipairs(lfbid_rollForMenuEntries) do
        info = UIDropDownMenu_CreateInfo()
        info.notCheckable = 1
        info.text = "Bid: " .. tostring(entry.link)
        info.func = function()
            LFBidRollForMenu_OnStartPoints(entry.link)
        end
        UIDropDownMenu_AddButton(info, level)

        info = UIDropDownMenu_CreateInfo()
        info.notCheckable = 1
        info.text = "Roll: " .. tostring(entry.link)
        info.func = function()
            LFBidRollForMenu_OnStartRoll(entry.link)
        end
        UIDropDownMenu_AddButton(info, level)
    end
end

local function ShowRollForLFBidMenu(anchorFrame)
    if not anchorFrame then
        return
    end

    if not lfbid_rollForMenuFrame then
        lfbid_rollForMenuFrame = CreateFrame("Frame", "LFBidRollForMenuFrame", UIParent, "UIDropDownMenuTemplate")
        UIDropDownMenu_Initialize(lfbid_rollForMenuFrame, LFBidRollForMenu_Initialize, "MENU")
    end

    BuildRollForLootMenuEntries()
    ToggleDropDownMenu(1, nil, lfbid_rollForMenuFrame, anchorFrame, 0, 0)
end

local function EnsureRollForIntegrationButton()
    -- Intentionally disabled: keep row-level Bid/Roll buttons, but no top launcher button.
    if lfbid_rollForButton then
        lfbid_rollForButton:Hide()
    end
end

local function ResolveRollForPopupItemLink(popupFrame)
    if not popupFrame then
        return nil
    end

    local popupItemLink = nil
    local popupItemName = nil

    local function ConsumeText(text)
        local textValue = tostring(text or "")
        if textValue == "" then
            return
        end

        if not popupItemLink then
            local _, _, foundLink = string.find(textValue, "(|Hitem:.-|h%[.-%]|h)")
            if foundLink and foundLink ~= "" then
                popupItemLink = foundLink
            end
        end

        if not popupItemName then
            local _, _, foundName = string.find(textValue, "%[(.-)%]")
            if foundName and foundName ~= "" then
                popupItemName = foundName
            end
        end
    end

    local function ScanFrame(frame)
        if not frame or (popupItemLink and popupItemName) then
            return
        end

        if frame.GetText then
            ConsumeText(frame:GetText())
        end

        if frame.GetRegions then
            local regions = { frame:GetRegions() }
            local _, region
            for _, region in ipairs(regions) do
                if region and region.GetText then
                    ConsumeText(region:GetText())
                    if popupItemLink and popupItemName then
                        return
                    end
                end
            end
        end

        if frame.GetChildren then
            local children = { frame:GetChildren() }
            local _, child
            for _, child in ipairs(children) do
                ScanFrame(child)
                if popupItemLink and popupItemName then
                    return
                end
            end
        end
    end

    ScanFrame(popupFrame)

    -- Always prefer GetLootSlotLink (fully colored) over the text-scanned link.
    -- The text scan only extracts the |Hitem:...|h part without color codes.
    if GetNumLootItems and GetLootSlotLink then
        local lootCount = tonumber(GetNumLootItems()) or 0
        local normalizedPopupName = string.lower(tostring(popupItemName or ""))
        normalizedPopupName = string.gsub(normalizedPopupName, "^%s+", "")
        normalizedPopupName = string.gsub(normalizedPopupName, "%s+$", "")

        local onlyLink = nil
        local foundCount = 0
        local slot
        for slot = 1, lootCount do
            local itemLink = GetLootSlotLink(slot)
            if itemLink and itemLink ~= "" then
                foundCount = foundCount + 1
                onlyLink = itemLink

                if normalizedPopupName ~= "" then
                    local _, _, lootItemName = string.find(itemLink, "|h%[(.-)%]|h")
                    local normalizedLootName = string.lower(tostring(lootItemName or ""))
                    if normalizedLootName == normalizedPopupName then
                        return itemLink
                    end
                end
            end
        end

        -- Exactly one loot item: deterministic match, safe to use.
        if foundCount == 1 then
            return onlyLink
        end
    end

    -- Fall back to the link extracted directly from popup text (may lack color codes).
    if popupItemLink and popupItemLink ~= "" then
        return popupItemLink
    end

    return nil
end

local function EnsureRollForPopupActionButtons()
    if not LFBID_ENABLE_ROLLFOR_POPUP_BUTTONS then
        if lfbid_rollForPopupBidBtn then
            lfbid_rollForPopupBidBtn:Hide()
        end
        if lfbid_rollForPopupRollBtn then
            lfbid_rollForPopupRollBtn:Hide()
        end
        return
    end

    local popup = getglobal and getglobal("RollForRollingFrame") or nil
    if not popup then
        return
    end

    if not lfbid_rollForPopupBidBtn then
        lfbid_rollForPopupBidBtn = CreateFrame("Button", "LFBidRollForPopupBidButton", popup, "UIPanelButtonTemplate")
        lfbid_rollForPopupBidBtn:SetWidth(34)
        lfbid_rollForPopupBidBtn:SetHeight(20)
        lfbid_rollForPopupBidBtn:SetText("Bid")
        lfbid_rollForPopupBidBtn:SetScript("OnClick", function()
            local itemLink = ResolveRollForPopupItemLink(popup)
            if itemLink and itemLink ~= "" then
                StartBiddingForItemLink(itemLink, "points")
            else
                print("LFBid: Could not resolve the RollFor popup item.")
            end
        end)
    end

    if not lfbid_rollForPopupRollBtn then
        lfbid_rollForPopupRollBtn = CreateFrame("Button", "LFBidRollForPopupRollButton", popup, "UIPanelButtonTemplate")
        lfbid_rollForPopupRollBtn:SetWidth(34)
        lfbid_rollForPopupRollBtn:SetHeight(20)
        lfbid_rollForPopupRollBtn:SetText("Roll")
        lfbid_rollForPopupRollBtn:SetScript("OnClick", function()
            local itemLink = ResolveRollForPopupItemLink(popup)
            if itemLink and itemLink ~= "" then
                StartBiddingForItemLink(itemLink, "roll")
            else
                print("LFBid: Could not resolve the RollFor popup item.")
            end
        end)
    end

    lfbid_rollForPopupRollBtn:ClearAllPoints()
    lfbid_rollForPopupRollBtn:SetPoint("TOPLEFT", popup, "TOPLEFT", 8, -14)

    lfbid_rollForPopupBidBtn:ClearAllPoints()
    lfbid_rollForPopupBidBtn:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -8, -14)

    lfbid_rollForPopupBidBtn:SetFrameStrata(popup:GetFrameStrata() or "DIALOG")
    lfbid_rollForPopupRollBtn:SetFrameStrata(popup:GetFrameStrata() or "DIALOG")
    lfbid_rollForPopupBidBtn:SetFrameLevel((popup:GetFrameLevel() or 1) + 30)
    lfbid_rollForPopupRollBtn:SetFrameLevel((popup:GetFrameLevel() or 1) + 30)

    local canStart = IsPlayerMasterLooter() and not lfbid_windowOpen

    lfbid_rollForPopupBidBtn:Show()
    lfbid_rollForPopupRollBtn:Show()
    if canStart then
        lfbid_rollForPopupBidBtn:Enable()
        lfbid_rollForPopupRollBtn:Enable()
    else
        lfbid_rollForPopupBidBtn:Disable()
        lfbid_rollForPopupRollBtn:Disable()
    end
end

local function RegisterLFBidLootWindowHook()
    if lfbid_lootHookFrame then
        return
    end

    lfbid_lootHookFrame = CreateFrame("Frame")
    lfbid_lootHookFrame:RegisterEvent("PLAYER_LOGIN")
    lfbid_lootHookFrame:RegisterEvent("LOOT_OPENED")
    lfbid_lootHookFrame:SetScript("OnEvent", function()
        HookLootButtonsForLFBid()
        HookRollForLootButtonsForLFBid()
        EnsureRollForIntegrationButton()
        EnsureRollForPopupActionButtons()
    end)
    lfbid_lootHookFrame:SetScript("OnUpdate", function()
        lfbid_rollForPopupUpdateElapsed = lfbid_rollForPopupUpdateElapsed + (arg1 or 0)
        if lfbid_rollForPopupUpdateElapsed < 0.2 then
            return
        end
        lfbid_rollForPopupUpdateElapsed = 0
        EnsureRollForPopupActionButtons()
    end)

    if not lfbid_originalLootFrameUpdate and type(LootFrame_Update) == "function" then
        lfbid_originalLootFrameUpdate = LootFrame_Update
        LootFrame_Update = function()
            local result = lfbid_originalLootFrameUpdate()
            HookLootButtonsForLFBid()
            HookRollForLootButtonsForLFBid()
            EnsureRollForIntegrationButton()
            EnsureRollForPopupActionButtons()
            return result
        end
    end

    HookLootButtonsForLFBid()
    HookRollForLootButtonsForLFBid()
    EnsureRollForIntegrationButton()
    EnsureRollForPopupActionButtons()
end

local function ResolveMasterLootMenuSlot()
    if lfbid_masterLootMenuSlot and tonumber(lfbid_masterLootMenuSlot) then
        return tonumber(lfbid_masterLootMenuSlot)
    end

    if GroupLootDropDown then
        if GroupLootDropDown.slot and tonumber(GroupLootDropDown.slot) then
            return tonumber(GroupLootDropDown.slot)
        end
        if GroupLootDropDown.selectedSlot and tonumber(GroupLootDropDown.selectedSlot) then
            return tonumber(GroupLootDropDown.selectedSlot)
        end
        if GroupLootDropDown.selectedLootSlot and tonumber(GroupLootDropDown.selectedLootSlot) then
            return tonumber(GroupLootDropDown.selectedLootSlot)
        end
    end

    if LootFrame and LootFrame.selectedSlot and tonumber(LootFrame.selectedSlot) then
        return tonumber(LootFrame.selectedSlot)
    end

    if MasterLootDropDown then
        if MasterLootDropDown.slot and tonumber(MasterLootDropDown.slot) then
            return tonumber(MasterLootDropDown.slot)
        end
        if MasterLootDropDown.selectedSlot and tonumber(MasterLootDropDown.selectedSlot) then
            return tonumber(MasterLootDropDown.selectedSlot)
        end
    end

    return nil
end

local function StartBiddingFromMasterLootMenu(mode)
    local slotId = ResolveMasterLootMenuSlot()
    LFBidDebug("StartBiddingFromMasterLootMenu called. mode=" .. tostring(mode) .. ", slot=" .. tostring(slotId))
    if not slotId then
        print("LFBid: Could not determine selected loot slot.")
        return
    end

    if not GetLootSlotLink then
        print("LFBid: Loot slot API is not available.")
        return
    end

    local itemLink = GetLootSlotLink(slotId)
    if (not itemLink or itemLink == "") and lfbid_masterLootMenuItemLink and lfbid_masterLootMenuItemLink ~= "" then
        itemLink = lfbid_masterLootMenuItemLink
    end
    LFBidDebug("Resolved loot slot link: " .. tostring(itemLink))
    if not itemLink or itemLink == "" then
        print("LFBid: No item link found for selected loot slot.")
        return
    end

    StartBiddingForItemLink(itemLink, mode)
end

local function AddLFBidEntriesToMasterLootDropdown(level)
    LFBidDebug("AddLFBidEntriesToMasterLootDropdown level=" .. tostring(level))
    if level ~= 1 then
        return
    end

    if not IsPlayerMasterLooter() then
        return
    end

    lfbid_masterLootMenuSlot = nil
    lfbid_masterLootMenuItemLink = nil
    if LootFrame and LootFrame.selectedSlot and tonumber(LootFrame.selectedSlot) then
        lfbid_masterLootMenuSlot = tonumber(LootFrame.selectedSlot)
    elseif MasterLootDropDown and MasterLootDropDown.slot and tonumber(MasterLootDropDown.slot) then
        lfbid_masterLootMenuSlot = tonumber(MasterLootDropDown.slot)
    end
    if lfbid_masterLootMenuSlot and GetLootSlotLink then
        lfbid_masterLootMenuItemLink = GetLootSlotLink(lfbid_masterLootMenuSlot)
    end
    LFBidDebug("Master loot menu slot captured: " .. tostring(lfbid_masterLootMenuSlot))

    local info = UIDropDownMenu_CreateInfo()
    info.text = " "
    info.notCheckable = 1
    info.disabled = 1
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo()
    info.isTitle = 1
    info.text = "LFBid"
    info.notCheckable = 1
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo()
    info.text = "Start bidding (points)"
    info.notCheckable = 1
    info.disabled = nil
    info.notClickable = nil
    info.func = function()
        StartBiddingFromMasterLootMenu("points")
    end
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo()
    info.text = "Start rolling (1-100)"
    info.notCheckable = 1
    info.disabled = nil
    info.notClickable = nil
    info.func = function()
        StartBiddingFromMasterLootMenu("roll")
    end
    UIDropDownMenu_AddButton(info, level)
end

local function RegisterLFBidMasterLootDropdownHook()
    if lfbid_masterLootDropdownHooked then
        LFBidDebug("Master loot dropdown hook already active.")
        return
    end

    if MasterLootDropDown and type(MasterLootDropDown.initialize) == "function" then
        LFBidDebug("Hooking MasterLootDropDown.initialize")
        lfbid_masterLootOriginalInitialize = MasterLootDropDown.initialize
        MasterLootDropDown.initialize = function(level)
            LFBidDebug("MasterLootDropDown.initialize invoked. level=" .. tostring(level))
            lfbid_masterLootOriginalInitialize(level)
            AddLFBidEntriesToMasterLootDropdown(level)
        end
        lfbid_masterLootDropdownHooked = true
        return
    end

    if type(MasterLootDropDown_Initialize) == "function" then
        LFBidDebug("Hooking MasterLootDropDown_Initialize")
        lfbid_masterLootOriginalInitialize = MasterLootDropDown_Initialize
        MasterLootDropDown_Initialize = function(level)
            LFBidDebug("MasterLootDropDown_Initialize invoked. level=" .. tostring(level))
            lfbid_masterLootOriginalInitialize(level)
            AddLFBidEntriesToMasterLootDropdown(level)
        end
        lfbid_masterLootDropdownHooked = true
        return
    end

    LFBidDebug("Master loot dropdown initializer was not found.")
end

local function HookDropDownFrameInitialize(dropDownFrame, sourceTag)
    if not dropDownFrame or dropDownFrame.lfbidInitializeHooked then
        return
    end

    if type(dropDownFrame.initialize) ~= "function" then
        LFBidDebug("Dropdown frame has no initialize function: " .. tostring(sourceTag or "unknown"))
        return
    end

    local originalInitialize = dropDownFrame.initialize
    dropDownFrame.lfbidInitializeHooked = true
    dropDownFrame.initialize = function(level)
        LFBidDebug("Dropdown initialize invoked from " .. tostring(sourceTag or "unknown") .. ", level=" .. tostring(level))
        originalInitialize(level)
        if tonumber(level) == 1 and IsGiveLootMenuTitle(level) then
            LFBidDebug("Detected 'Give Loot To' dropdown, injecting LFBid entries.")
            AddLFBidEntriesToMasterLootDropdown(level)
        end
    end
    LFBidDebug("Hooked dropdown initialize at runtime: " .. tostring(sourceTag or "unknown"))
end

local function RegisterLFBidToggleDropDownProbeHook()
    if lfbid_toggleDropDownHooked then
        return
    end

    if type(ToggleDropDownMenu) ~= "function" then
        LFBidDebug("ToggleDropDownMenu is unavailable.")
        return
    end

    lfbid_originalToggleDropDownMenu = ToggleDropDownMenu
    ToggleDropDownMenu = function(level, value, dropDownFrame, anchorName, xOffset, yOffset)
        local resolved = ResolveDropDownFrame(dropDownFrame)
        local frameName = "nil"
        if resolved and resolved.GetName then
            frameName = tostring(resolved:GetName() or "unnamed")
        end
        LFBidDebug("ToggleDropDownMenu called. level=" .. tostring(level) .. ", frame=" .. frameName)

        if resolved then
            HookDropDownFrameInitialize(resolved, "ToggleDropDownMenu:" .. frameName)
        end

        return lfbid_originalToggleDropDownMenu(level, value, dropDownFrame, anchorName, xOffset, yOffset)
    end

    lfbid_toggleDropDownHooked = true
    LFBidDebug("Installed ToggleDropDownMenu probe hook.")
end

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
        SendSafeChatMessage("Start rolling for item: " .. rest, "RAID_WARNING")
        OpenLFBidWindow(rest, "roll")
    elseif cmd == "open" then
        if lfbid_openWindowOpen then
            print("LFBid open window already open.")
            return
        end
        OpenLFBidOpenWindow()
    elseif cmd == "options" then
        if not IsPlayerMasterLooter() and not IsPlayerOfficerRank() then
            print("LFBid: /lfbid options is only available to the Master Looter, Chief Officer, or Officer.")
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
RegisterLFBidItemRefHook()
RegisterLFBidLootWindowHook()
RegisterLFBidMasterLootDropdownHook()
RegisterLFBidToggleDropDownProbeHook()

local lfbid_initFrame = CreateFrame("Frame")
lfbid_initFrame:RegisterEvent("VARIABLES_LOADED")
lfbid_initFrame:RegisterEvent("PLAYER_LOGIN")
lfbid_initFrame:RegisterEvent("PLAYER_LOGOUT")
lfbid_initFrame:RegisterEvent("LOOT_OPENED")
lfbid_initFrame:SetScript("OnEvent", function()
    if event == "VARIABLES_LOADED" then
        LoadLFBidSettings()
        ApplyLFBidBackdropAlpha()
        if lfbid_optionsFrame then
            SetDKPCheckTier(lfbid_dkpCheckTier)
        end
        return
    end

    if event == "PLAYER_LOGOUT" then
        PersistLFBidSettings()
        return
    end

    RegisterLFBidSlashCommand()
    RegisterLFBidItemRefHook()
    RegisterLFBidLootWindowHook()
    RegisterLFBidMasterLootDropdownHook()
    RegisterLFBidToggleDropDownProbeHook()
end)
