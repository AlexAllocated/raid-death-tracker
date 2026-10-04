-- ============================================================
--  RaidDeathTracker  v1.9.0
--  TBC Classic Anniversary (2.5.6)
--  Tracks player deaths — solo, in party and raid.
-- ============================================================

local ADDON_NAME = "RaidDeathTracker"
local TOP_N      = 5
local viewIndex  = 0   -- 0 = live, 1..N = Session
local lastDeathTime, pendingDeaths = {}, {}

-- ----------------------------------------------------------------
-- Core Frame (Events)
-- ----------------------------------------------------------------
local frame = CreateFrame("Frame", "RaidDeathTrackerFrame", UIParent)
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
-- Group events: via pcall, as availability varies by client version
for _, evt in ipairs({"GROUP_ROSTER_UPDATE", "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE"}) do
    pcall(frame.RegisterEvent, frame, evt)
end
-- Encounter events: via pcall, as availability varies by client version
for _, evt in ipairs({"ENCOUNTER_START", "ENCOUNTER_END", "BOSS_KILL"}) do
    pcall(frame.RegisterEvent, frame, evt)
end

-- ----------------------------------------------------------------
-- Helper: 1px pixel border from 4 textures.
-- No BackdropTemplate, no SetBackdrop — 100% compatible.
-- ----------------------------------------------------------------
local function AddPixelBorder(parent, r, g, b, a)
    local top = parent:CreateTexture(nil, "OVERLAY")
    top:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0,  0)
    top:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0,  0)
    top:SetHeight(1)
    top:SetColorTexture(r, g, b, a)

    local bot = parent:CreateTexture(nil, "OVERLAY")
    bot:SetPoint("BOTTOMLEFT",  parent, "BOTTOMLEFT",  0, 0)
    bot:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    bot:SetHeight(1)
    bot:SetColorTexture(r, g, b, a)

    local lft = parent:CreateTexture(nil, "OVERLAY")
    lft:SetPoint("TOPLEFT",    parent, "TOPLEFT",    0,  0)
    lft:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0,  0)
    lft:SetWidth(1)
    lft:SetColorTexture(r, g, b, a)

    local rgt = parent:CreateTexture(nil, "OVERLAY")
    rgt:SetPoint("TOPRIGHT",    parent, "TOPRIGHT",    0, 0)
    rgt:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    rgt:SetWidth(1)
    rgt:SetColorTexture(r, g, b, a)
end

-- ----------------------------------------------------------------
-- Design palette (based on FishingKit)
-- ----------------------------------------------------------------
local D = {
    bg      = {0.04, 0.04, 0.06},  bgA  = 0.92,
    border  = {0.18, 0.18, 0.23},  borA = 0.80,
    divider = {0.14, 0.14, 0.18},  divA = 0.90,
    accent  = {0.28, 0.74, 0.97},   -- soft cyan
    label   = {0.40, 0.40, 0.45},   -- muted
    value   = {0.82, 0.84, 0.88},   -- bright
    danger  = {0.90, 0.30, 0.30},   -- red
    barBg   = {0.07, 0.07, 0.09},
}

-- ----------------------------------------------------------------
-- Display Frame
-- ----------------------------------------------------------------
local display = CreateFrame("Frame", "RaidDeathTrackerDisplay", UIParent)
display:SetSize(260, 185)
display:SetPoint("CENTER")
display:SetMovable(true)
display:EnableMouse(true)
display:RegisterForDrag("LeftButton")
display:SetScript("OnDragStart", display.StartMoving)
display:SetScript("OnDragStop",  display.StopMovingOrSizing)
display:SetClampedToScreen(true)
display:Hide()  -- default: only visible in group/raid

-- Resize: SetResizable() is always required for StartSizing to work.
-- Bounds API differs: new SetResizeBounds() vs. old SetMinResize/SetMaxResize.
local MIN_W, MIN_H = 220, 150
local MAX_W, MAX_H = 500, 450
display:SetResizable(true)
if display.SetResizeBounds then
    display:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
else
    if display.SetMinResize then display:SetMinResize(MIN_W, MIN_H) end
    if display.SetMaxResize then display:SetMaxResize(MAX_W, MAX_H) end
end

-- Background
local bg = display:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(D.bg[1], D.bg[2], D.bg[3], D.bgA)

-- 1px border
AddPixelBorder(display, D.border[1], D.border[2], D.border[3], D.borA)

-- Icon (Header)
local icon = display:CreateTexture(nil, "OVERLAY")
icon:SetSize(16, 16)
icon:SetPoint("TOPLEFT", 10, -8)
icon:SetTexture("Interface\\Icons\\Spell_Shadow_DeathCoil")

-- Title
local titleText = display:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
titleText:SetPoint("LEFT", icon, "RIGHT", 5, 0)
titleText:SetText("|cff47bef5Raid Death Tracker|r")

-- TEST badge (next to title, only visible in test mode)
local testBadge = display:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
testBadge:SetPoint("LEFT", titleText, "RIGHT", 6, 0)
testBadge:SetText("|cffff9900[TEST]|r")
testBadge:Hide()

-- Close button (FishingKit style)
local closeBtn = CreateFrame("Button", nil, display)
closeBtn:SetSize(16, 16)
closeBtn:SetPoint("TOPRIGHT", -8, -8)
local closeBtnBg = closeBtn:CreateTexture(nil, "BACKGROUND")
closeBtnBg:SetAllPoints()
closeBtnBg:SetColorTexture(D.barBg[1], D.barBg[2], D.barBg[3], 0.8)
local closeTex = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
closeTex:SetPoint("CENTER", 0, 0)
closeTex:SetText("x")
closeTex:SetTextColor(D.label[1], D.label[2], D.label[3])
closeBtn:SetScript("OnEnter", function() closeTex:SetTextColor(D.value[1], D.value[2], D.value[3]) end)
closeBtn:SetScript("OnLeave", function() closeTex:SetTextColor(D.label[1], D.label[2], D.label[3]) end)
closeBtn:SetScript("OnClick", function() display:Hide() end)

-- Divider below header
local headerLine = display:CreateTexture(nil, "ARTWORK")
headerLine:SetPoint("TOPLEFT",  10, -28)
headerLine:SetPoint("TOPRIGHT", -10, -28)
headerLine:SetHeight(1)
headerLine:SetColorTexture(D.divider[1], D.divider[2], D.divider[3], D.divA)

-- Raid time line (between header and death list; empty when no timer)
local timeText = display:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
timeText:SetPoint("TOPLEFT", display, "TOPLEFT", 10, -34)
timeText:SetJustifyH("LEFT")

-- Content-Text
local contentText = display:CreateFontString(nil, "OVERLAY", "GameFontNormal")
contentText:SetPoint("TOPLEFT", display, "TOPLEFT", 10, -36)
contentText:SetWidth(240)
contentText:SetJustifyH("LEFT")
contentText:SetJustifyV("TOP")

-- Shift the death list down when the raid time line is visible
local function SetContentTop(offset)
    contentText:ClearAllPoints()
    contentText:SetPoint("TOPLEFT", display, "TOPLEFT", 10, -offset)
end

-- Divider above footer
local footerLine = display:CreateTexture(nil, "ARTWORK")
footerLine:SetPoint("BOTTOMLEFT",  10, 24)
footerLine:SetPoint("BOTTOMRIGHT", -10, 24)
footerLine:SetHeight(1)
footerLine:SetColorTexture(D.divider[1], D.divider[2], D.divider[3], D.divA)

-- Helper: footer button in FishingKit style
local function MakeFooterBtn(label, r, g, b)
    local btn = CreateFrame("Button", nil, display)
    btn:SetSize(54, 14)
    local btnBg = btn:CreateTexture(nil, "BACKGROUND")
    btnBg:SetAllPoints()
    btnBg:SetColorTexture(D.barBg[1], D.barBg[2], D.barBg[3], 0.8)
    AddPixelBorder(btn, r, g, b, 0.6)
    local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btnText:SetPoint("CENTER", 0, 0)
    btnText:SetText(label)
    btnText:SetTextColor(r, g, b)
    btn:SetScript("OnEnter", function() btnText:SetTextColor(D.value[1], D.value[2], D.value[3]) end)
    btn:SetScript("OnLeave", function() btnText:SetTextColor(r, g, b) end)
    return btn
end

-- Reset button (footer left)
local resetBtn = MakeFooterBtn("Reset", D.danger[1], D.danger[2], D.danger[3])
resetBtn:SetPoint("BOTTOMLEFT", 8, 6)
resetBtn:SetScript("OnClick", function()
    RaidDeathData = {}
    RDTClassCache = {}
    lastDeathTime, pendingDeaths = {}, {}
    frame:UpdateDisplay()
    print("|cff00ff00[RDT]|r Deaths reset.")
end)

-- Post channel menu
local CHAT_CHANNELS = {
    { label = "Say",    channel = "SAY" },
    { label = "Yell",   channel = "YELL" },
    { label = "Party",  channel = "PARTY" },
    { label = "Raid",   channel = "RAID" },
    { label = "Emote",  channel = "EMOTE" },
}

local channelMenu = CreateFrame("Frame", nil, display)
channelMenu:SetSize(60, #CHAT_CHANNELS * 16 + 4)
channelMenu:Hide()

local menuBg = channelMenu:CreateTexture(nil, "BACKGROUND")
menuBg:SetAllPoints()
menuBg:SetColorTexture(D.bg[1], D.bg[2], D.bg[3], 0.95)
AddPixelBorder(channelMenu, D.border[1], D.border[2], D.border[3], D.borA)

for i, entry in ipairs(CHAT_CHANNELS) do
    local item = CreateFrame("Button", nil, channelMenu)
    item:SetSize(56, 14)
    item:SetPoint("TOP", 0, -2 - (i - 1) * 16)
    local itemText = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    itemText:SetPoint("CENTER", 0, 0)
    itemText:SetText(entry.label)
    itemText:SetTextColor(D.label[1], D.label[2], D.label[3])
    item:SetScript("OnEnter", function() itemText:SetTextColor(D.accent[1], D.accent[2], D.accent[3]) end)
    item:SetScript("OnLeave", function() itemText:SetTextColor(D.label[1], D.label[2], D.label[3]) end)
    item:SetScript("OnClick", function()
        channelMenu:Hide()
        PostDeathsToChat(entry.channel, entry.label)
    end)
end

channelMenu:SetScript("OnShow", function() channelMenu:SetFrameStrata("TOOLTIP") end)
channelMenu:EnableMouse(true)

-- Close menu when clicking elsewhere
channelMenu:SetScript("OnUpdate", function(self)
    if not MouseIsOver(self) and IsMouseButtonDown("LeftButton") then
        self:Hide()
    end
end)

-- Post button (footer right)
local postBtn = MakeFooterBtn("Post", D.accent[1], D.accent[2], D.accent[3])
postBtn:SetPoint("BOTTOMRIGHT", -18, 6)
postBtn:SetScript("OnClick", function()
    if channelMenu:IsShown() then
        channelMenu:Hide()
    else
        channelMenu:ClearAllPoints()
        channelMenu:SetPoint("BOTTOM", postBtn, "TOP", 0, 4)
        channelMenu:Show()
    end
end)

-- Session navigation (footer center)
local function MakeArrowBtn(label)
    local btn = CreateFrame("Button", nil, display)
    btn:SetSize(16, 14)
    local tex = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tex:SetPoint("CENTER", 0, 0)
    tex:SetText(label)
    tex:SetTextColor(D.label[1], D.label[2], D.label[3])
    btn:SetScript("OnEnter", function() tex:SetTextColor(D.value[1], D.value[2], D.value[3]) end)
    btn:SetScript("OnLeave", function() tex:SetTextColor(D.label[1], D.label[2], D.label[3]) end)
    return btn, tex
end

local prevBtn, prevTex = MakeArrowBtn("<")
local nextBtn, nextTex = MakeArrowBtn(">")
prevBtn:SetPoint("BOTTOM", display, "BOTTOM", -10, 6)
nextBtn:SetPoint("BOTTOM", display, "BOTTOM",  10, 6)

-- Resize grip (bottom right)
local resizeGrip = CreateFrame("Button", nil, display)
resizeGrip:SetSize(14, 14)
resizeGrip:SetPoint("BOTTOMRIGHT", -1, 1)
resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
resizeGrip:SetScript("OnMouseDown", function(_, btn)
    if btn == "LeftButton" then display:StartSizing("BOTTOMRIGHT") end
end)
resizeGrip:SetScript("OnMouseUp", function()
    display:StopMovingOrSizing()
    if RDTConfig then
        RDTConfig.width  = display:GetWidth()
        RDTConfig.height = display:GetHeight()
    end
end)

-- Keep content width + footer layout in sync with frame size
display:SetScript("OnSizeChanged", function(self, width, height)
    contentText:SetWidth(width - 20)
end)

-- ----------------------------------------------------------------
-- Minimap-Button (via LibDBIcon)
-- ----------------------------------------------------------------
local minimapBtn  -- set after ADDON_LOADED

local ldbObj = LibStub("LibDataBroker-1-1"):NewDataObject("RaidDeathTracker", {
    type = "launcher",
    icon = "Interface\\Icons\\Spell_Shadow_DeathCoil",
    OnClick = function(self, btn)
        if btn == "LeftButton" then
            if display:IsShown() then display:Hide() else display:Show() end
        end
    end,
    OnTooltipShow = function(tt)
        tt:AddLine("|cff47bef5Raid Death Tracker|r")
        tt:AddLine("|cff666672[Click]|r Toggle panel", 1, 1, 1)
        tt:AddLine("|cff666672[Drag] |r Move position",  1, 1, 1)
    end,
})

-- ----------------------------------------------------------------
-- Helper: sorted death list (desc count, asc name)
-- ----------------------------------------------------------------
local function GetSortedDeaths(data)
    data = data or RaidDeathData
    local sorted = {}
    local total  = 0
    for name, count in pairs(data) do
        table.insert(sorted, { name = name, count = count })
        total = total + count
    end
    table.sort(sorted, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)
    return sorted, total
end

-- ----------------------------------------------------------------
-- Session navigation logic
-- ----------------------------------------------------------------
local isTestMode  = false
local testRaidLog = nil   -- dummy raid log while in test mode
local testDeathData = nil

local function GetViewData()
    if viewIndex > 0 and RDTSessions and RDTSessions[viewIndex] then
        local s = RDTSessions[viewIndex]
        return s.data, s.classes or {}
    end
    if isTestMode then return testDeathData or {}, {} end
    return RaidDeathData, RDTClassCache
end

local function UpdateNavUI()
    local sessionCount = RDTSessions and #RDTSessions or 0
    -- Badge
    if viewIndex > 0 and RDTSessions and RDTSessions[viewIndex] then
        testBadge:SetText("|cff888899[" .. RDTSessions[viewIndex].name .. "]|r")
        testBadge:Show()
    elseif isTestMode then
        testBadge:SetText("|cffff9900[TEST]|r")
        testBadge:Show()
    else
        testBadge:Hide()
    end
    -- Arrows
    local canPrev = viewIndex < sessionCount
    local canNext = viewIndex > 0
    prevTex:SetTextColor(canPrev and D.accent[1] or D.label[1],
                         canPrev and D.accent[2] or D.label[2],
                         canPrev and D.accent[3] or D.label[3])
    nextTex:SetTextColor(canNext and D.accent[1] or D.label[1],
                         canNext and D.accent[2] or D.label[2],
                         canNext and D.accent[3] or D.label[3])
    prevBtn:EnableMouse(canPrev)
    nextBtn:EnableMouse(canNext)
end

prevBtn:SetScript("OnClick", function()
    local sessionCount = RDTSessions and #RDTSessions or 0
    if viewIndex < sessionCount then
        viewIndex = viewIndex + 1
        UpdateNavUI()
        frame:UpdateDisplay()
    end
end)

nextBtn:SetScript("OnClick", function()
    if viewIndex > 0 then
        viewIndex = viewIndex - 1
        UpdateNavUI()
        frame:UpdateDisplay()
    end
end)

-- ----------------------------------------------------------------
-- Raid timer: first pull -> boss kills
-- Uses time() (epoch), so a /reload mid-raid keeps the timer intact.
-- ----------------------------------------------------------------
local function FormatDuration(sec)
    sec = math.max(0, math.floor(sec or 0))
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    local s = sec % 60
    if h > 0 then
        return string.format("%d:%02d:%02d", h, m, s)
    end
    return string.format("%d:%02d", m, s)
end

-- The raid log lives in RDTConfig.raidLog: RDTConfig has been a
-- registered SavedVariable since v1.0, so persistence works with a
-- plain /reload — no client restart needed to pick up a new TOC entry.
local function GetViewRaidLog()
    if viewIndex > 0 and RDTSessions and RDTSessions[viewIndex] then
        return RDTSessions[viewIndex].raidLog
    end
    if isTestMode and testRaidLog then return testRaidLog end
    return RDTConfig and RDTConfig.raidLog
end

-- Elapsed active time. Live while inside the tracked instance,
-- otherwise frozen at the last boss kill ("first pull till last boss").
-- Chained instances accumulate: baseElapsed holds the closed segments,
-- segStart is where the current segment began (travel time between
-- instances is excluded when the next segment opens).
local function GetRaidElapsed(log)
    local liveView = (viewIndex == 0) and not isTestMode
    local _, instType = IsInInstance()
    local inThatRaid = liveView
        and (instType == "raid" or instType == "party")
        and GetRealZoneText() == log.zone
    local segStart = log.segStart or log.startTime
    local base     = log.baseElapsed or 0
    local bosses   = log.bosses
    local last     = bosses and bosses[#bosses]
    -- End boss down: clock is stopped even while still inside
    if inThatRaid and not log.finalDown then
        return base + (time() - segStart), true
    end
    if last then
        local segTime = (last.t >= segStart) and (last.t - segStart) or 0
        return base + segTime, false
    end
    if log.endTime then return log.endTime - log.startTime, false end
    if liveView then return base + (time() - segStart), true end
    return 0, false
end

local function UpdateTimeLine()
    local log = GetViewRaidLog()
    if not log or not log.startTime then
        timeText:SetText("")
        SetContentTop(36)
        return
    end
    local elapsed, running = GetRaidElapsed(log)
    local n = log.bosses and #log.bosses or 0
    local zoneLabel = log.zone or "Raid"
    local zoneCount = log.zones and #log.zones or 1
    if zoneCount > 1 then
        zoneLabel = zoneLabel .. " +" .. (zoneCount - 1)
    end
    local line = string.format("|cff666672%s|r  |cff47bef5%s|r",
        zoneLabel, FormatDuration(elapsed))
    if n > 0 then
        line = line .. string.format("  |cff666672-  %d boss%s down|r", n, n == 1 and "" or "es")
    elseif running then
        line = line .. "  |cff666672-  in progress|r"
    end
    if log.finalDown then
        line = line .. "  |cff33bb55done|r"
    end
    timeText:SetText(line)
    SetContentTop(50)
end

-- Refresh the live timer once per second while the panel is shown
local tickAccum = 0
display:SetScript("OnUpdate", function(_, elapsed)
    tickAccum = tickAccum + elapsed
    if tickAccum < 1 then return end
    tickAccum = 0
    UpdateTimeLine()
end)

-- Dungeon timers are limited to TBC dungeons for now (instance map ids)
local TBC_DUNGEONS = {
    [543] = true, [542] = true, [540] = true,               -- Hellfire Citadel
    [547] = true, [546] = true, [545] = true,               -- Coilfang Reservoir
    [557] = true, [558] = true, [556] = true, [555] = true, -- Auchindoun
    [560] = true, [269] = true,                             -- Caverns of Time
    [554] = true, [553] = true, [552] = true,               -- Tempest Keep
    [585] = true,                                           -- Magisters' Terrace
}

-- First pull: any combat start inside a raid or TBC dungeon arms the
-- timer (group required, so solo farming does not trigger it).
-- Same-type chains continue the log; a type switch starts fresh.
local function OnCombatStart()
    if not RDTConfig or isTestMode then return end
    if not (IsInRaid() or IsInGroup()) then return end
    local _, instType = IsInInstance()
    if instType ~= "raid" and instType ~= "party" then return end
    if instType == "party" then
        local mapID = select(8, GetInstanceInfo())
        if not TBC_DUNGEONS[mapID or 0] then return end
    end
    local zone = GetRealZoneText() or "Instance"
    local log = RDTConfig.raidLog
    if log and log.startTime and log.zone == zone then return end

    -- Multi-instance chain (double raid night): the previous segment is
    -- retroactively closed at its LAST boss kill, so travel time between
    -- the instances is excluded; the clock resumes with this pull.
    -- Only same-type chains continue (raid->raid, dungeon->dungeon).
    if log and log.startTime and log.instType == instType then
        local segStart = log.segStart or log.startTime
        local last = log.bosses and log.bosses[#log.bosses]
        local segTime = (last and last.t >= segStart) and (last.t - segStart) or 0
        log.baseElapsed = (log.baseElapsed or 0) + segTime
        log.segStart    = time()
        log.zone        = zone
        log.zones       = log.zones or {}
        table.insert(log.zones, zone)
        log.killed      = {}
        log.finalDown   = nil
        UpdateTimeLine()
        print("|cff00ff00[RDT]|r Timer continues: " .. zone
            .. " (travel time excluded)")
        return
    end

    RDTConfig.raidLog = {
        zone        = zone,
        zones       = { zone },
        instType    = instType,
        startTime   = time(),
        segStart    = time(),
        baseElapsed = 0,
        bosses      = {},
        killed      = {},
    }
    UpdateTimeLine()
    print("|cff00ff00[RDT]|r "
        .. (instType == "party" and "Dungeon" or "Raid")
        .. " timer started: " .. zone)
end

-- End bosses per instance: killing one stops the clock on the spot
-- (a later optional kill in the same zone, e.g. Netherspite after
-- Prince in Karazhan, extends the frozen time to that kill).
local FINAL_BOSSES = {
    -- Raids
    ["Prince Malchezaar"]         = true,  -- Karazhan
    ["Gruul the Dragonkiller"]    = true,
    ["Magtheridon"]               = true,
    ["Lady Vashj"]                = true,  -- SSC
    ["Kael'thas Sunstrider"]      = true,  -- The Eye + Magisters' Terrace
    ["Archimonde"]                = true,  -- Mount Hyjal
    ["Illidan Stormrage"]         = true,  -- Black Temple
    ["Zul'jin"]                   = true,  -- Zul'Aman
    ["Kil'jaeden"]                = true,  -- Sunwell Plateau
    -- TBC dungeons
    ["Vazruden the Herald"]       = true,
    ["Keli'dan the Breaker"]      = true,
    ["Warchief Kargath Bladefist"] = true,
    ["Quagmirran"]                = true,
    ["The Black Stalker"]         = true,
    ["Warlord Kalithresh"]        = true,
    ["Nexus-Prince Shaffar"]      = true,
    ["Exarch Maladaar"]           = true,
    ["Talon King Ikiss"]          = true,
    ["Murmur"]                    = true,
    ["Epoch Hunter"]              = true,
    ["Aeonus"]                    = true,
    ["Pathaleon the Calculator"]  = true,
    ["Warp Splinter"]             = true,
    ["Harbinger Skyriss"]         = true,
}

-- Required bosses per raid: the clock stops once ALL of them are
-- dead in the current segment, so the kill order is not fixated.
-- Optional/untrackable encounters (Attumen, Maiden, Opera, Illhoof,
-- Netherspite, Nightbane, Chess) are excluded — killing them still
-- extends the frozen time. Zones without a list fall back to the
-- FINAL_BOSSES end-boss rule (used for dungeons).
local THE_EYE = { "Al'ar", "Void Reaver", "High Astromancer Solarian", "Kael'thas Sunstrider" }
local HYJAL   = { "Rage Winterchill", "Anetheron", "Kaz'rogal", "Azgalor", "Archimonde" }
local BT      = { "High Warlord Naj'entus", "Supremus", "Shade of Akama", "Teron Gorefiend",
                  "Gurtogg Bloodboil", "Reliquary of Souls", "Mother Shahraz",
                  "Illidari Council", "Illidan Stormrage" }
local REQUIRED_BOSSES = {
    ["Karazhan"]             = { "Moroes", "The Curator", "Shade of Aran", "Prince Malchezaar" },
    ["Gruul's Lair"]         = { "High King Maulgar", "Gruul the Dragonkiller" },
    ["Magtheridon's Lair"]   = { "Magtheridon" },
    ["Serpentshrine Cavern"] = { "Hydross the Unstable", "The Lurker Below", "Leotheras the Blind",
                                 "Fathom-Lord Karathress", "Morogrim Tidewalker", "Lady Vashj" },
    ["Tempest Keep"]         = THE_EYE,
    ["The Eye"]              = THE_EYE,
    ["Hyjal Summit"]         = HYJAL,
    ["The Battle for Mount Hyjal"] = HYJAL,
    ["Black Temple"]         = BT,
    ["The Black Temple"]     = BT,
    ["Zul'Aman"]             = { "Akil'zon", "Nalorakk", "Jan'alai", "Halazzi",
                                 "Hex Lord Malacrass", "Zul'jin" },
    ["Sunwell Plateau"]      = { "Kalecgos", "Brutallus", "Felmyst", "Eredar Twins",
                                 "M'uru", "Kil'jaeden" },
}

-- Complete when every required boss of the zone died in the current
-- segment. Names match leniently (substring both ways), since the
-- encounter event name and the fallback name can differ slightly
-- (e.g. "Eredar Twins" vs "The Eredar Twins").
local function IsInstanceComplete(log, killName)
    local req = REQUIRED_BOSSES[log.zone or ""]
    if not req then
        return FINAL_BOSSES[killName] or false
    end
    local segStart = log.segStart or log.startTime or 0
    for _, want in ipairs(req) do
        local found = false
        for _, b in ipairs(log.bosses or {}) do
            if b.t >= segStart
                and (b.name == want
                    or b.name:find(want, 1, true)
                    or want:find(b.name, 1, true)) then
                found = true
                break
            end
        end
        if not found then return false end
    end
    return true
end

-- A kill can be reported up to three times (ENCOUNTER_END, BOSS_KILL,
-- combat-log fallback) — dedupe via encounter id AND boss name; a
-- later event may backfill the fight duration.
local function RecordBossKill(encounterID, encounterName, fightDur)
    if not RDTConfig or isTestMode then return end
    local _, instType = IsInInstance()
    if instType ~= "raid" and instType ~= "party" then return end
    local log = RDTConfig.raidLog
    if not log or not log.startTime then
        OnCombatStart()
        log = RDTConfig.raidLog
    end
    if not log or not log.startTime then return end
    log.killed = log.killed or {}
    log.bosses = log.bosses or {}
    local name    = encounterName or "Unknown boss"
    local nameKey = "name:" .. name
    local idKey   = encounterID and ("id:" .. encounterID) or nil
    local existing = log.killed[nameKey] or (idKey and log.killed[idKey])
    if existing then
        if type(existing) == "table" then
            if fightDur and not existing.dur then existing.dur = fightDur end
            log.killed[nameKey] = existing
            if idKey then log.killed[idKey] = existing end
        end
        return
    end
    -- e = active elapsed at kill time (paused travel segments excluded)
    local now = time()
    local entry = {
        name = name,
        t    = now,
        e    = (log.baseElapsed or 0) + (now - (log.segStart or log.startTime)),
        dur  = fightDur,
        zone = log.zone,
    }
    log.killed[nameKey] = entry
    if idKey then log.killed[idKey] = entry end
    table.insert(log.bosses, entry)
    local justCompleted = false
    if not log.finalDown and IsInstanceComplete(log, name) then
        log.finalDown = true
        justCompleted = true
    end
    UpdateTimeLine()
    local msg = string.format("|cff00ff00[RDT]|r Boss down: %s  +%s",
        name, FormatDuration(entry.e))
    if fightDur then
        msg = msg .. string.format("  (fight %s)", FormatDuration(fightDur))
    end
    print(msg)
    if justCompleted then
        print("|cff00ff00[RDT]|r " .. (log.zone or "Instance") .. " complete - "
            .. ((log.instType == "party") and "Dungeon" or "Raid")
            .. " time: " .. FormatDuration(entry.e))
    end
end

-- Combat-log fallback: on classic clients some encounters (e.g.
-- Hydross) don't reliably fire ENCOUNTER_END/BOSS_KILL, so UNIT_DIED
-- of these NPC ids also counts as a kill. true = use the combat log
-- name; string = shared display name for multi-mob encounters.
-- Deliberately absent (scripted endings or mid-fight deaths would
-- cause false/premature records): Opera, Chess, Romulo & Julianne,
-- Eredar Twins, M'uru phase 1.
local BOSS_NPCS = {
    -- Karazhan
    [15550] = true, [16152] = true,   -- Attumen the Huntsman
    [15687] = true,                   -- Moroes
    [16457] = true,                   -- Maiden of Virtue
    [15691] = true,                   -- The Curator
    [15688] = true,                   -- Terestian Illhoof
    [16524] = true,                   -- Shade of Aran
    [15689] = true,                   -- Netherspite
    [15690] = true,                   -- Prince Malchezaar
    [17225] = true,                   -- Nightbane
    -- Gruul's Lair
    [18831] = true,                   -- High King Maulgar
    [19044] = true,                   -- Gruul the Dragonkiller
    -- Magtheridon's Lair
    [17257] = true,                   -- Magtheridon
    -- Serpentshrine Cavern
    [21216] = true,                   -- Hydross the Unstable
    [21217] = true,                   -- The Lurker Below
    [21215] = true,                   -- Leotheras the Blind
    [21214] = true,                   -- Fathom-Lord Karathress
    [21213] = true,                   -- Morogrim Tidewalker
    [21212] = true,                   -- Lady Vashj
    -- Tempest Keep: The Eye
    [19514] = true,                   -- Al'ar
    [19516] = true,                   -- Void Reaver
    [18805] = true,                   -- High Astromancer Solarian
    [19622] = true,                   -- Kael'thas Sunstrider
    -- Mount Hyjal
    [17767] = true,                   -- Rage Winterchill
    [17808] = true,                   -- Anetheron
    [17888] = true,                   -- Kaz'rogal
    [17842] = true,                   -- Azgalor
    [17968] = true,                   -- Archimonde
    -- Black Temple
    [22887] = true,                   -- High Warlord Naj'entus
    [22898] = true,                   -- Supremus
    [22841] = true,                   -- Shade of Akama
    [22871] = true,                   -- Teron Gorefiend
    [22948] = true,                   -- Gurtogg Bloodboil
    [23420] = "Reliquary of Souls",   -- Essence of Anger
    [22947] = true,                   -- Mother Shahraz
    [22949] = "Illidari Council", [22950] = "Illidari Council",
    [22951] = "Illidari Council", [22952] = "Illidari Council",
    [22917] = true,                   -- Illidan Stormrage
    -- Zul'Aman
    [23574] = true,                   -- Akil'zon
    [23576] = true,                   -- Nalorakk
    [23578] = true,                   -- Jan'alai
    [23577] = true,                   -- Halazzi
    [24239] = true,                   -- Hex Lord Malacrass
    [23863] = true,                   -- Zul'jin
    -- Sunwell Plateau
    [24892] = "Kalecgos",             -- Sathrovarr the Corruptor
    [24882] = true,                   -- Brutallus
    [25038] = true,                   -- Felmyst
    [25840] = "M'uru",                -- Entropius
    [25315] = true,                   -- Kil'jaeden

    -- ---- TBC dungeons (best effort; encounter events are primary) ----
    -- Hellfire Ramparts
    [17306] = true,                   -- Watchkeeper Gargolmar
    [17308] = true,                   -- Omor the Unscarred
    [17536] = "Vazruden the Herald", [17537] = "Vazruden the Herald",
    -- The Blood Furnace
    [17381] = true,                   -- The Maker
    [17380] = true,                   -- Broggok
    [17377] = true,                   -- Keli'dan the Breaker
    -- The Shattered Halls
    [16807] = true,                   -- Grand Warlock Nethekurse
    [16809] = true,                   -- Warbringer O'mrogg
    [16808] = true,                   -- Warchief Kargath Bladefist
    -- The Slave Pens
    [17941] = true,                   -- Mennu the Betrayer
    [17991] = true,                   -- Rokmar the Crackler
    [17942] = true,                   -- Quagmirran
    -- The Underbog
    [17770] = true,                   -- Hungarfen
    [18105] = true,                   -- Ghaz'an
    [17826] = true,                   -- Swamplord Musel'ek
    [17882] = true,                   -- The Black Stalker
    -- The Steamvault
    [17797] = true,                   -- Hydromancer Thespia
    [17796] = true,                   -- Mekgineer Steamrigger
    [17798] = true,                   -- Warlord Kalithresh
    -- Mana-Tombs
    [18341] = true,                   -- Pandemonius
    [18343] = true,                   -- Tavarok
    [18344] = true,                   -- Nexus-Prince Shaffar
    -- Auchenai Crypts
    [18371] = true,                   -- Shirrak the Dead Watcher
    [18373] = true,                   -- Exarch Maladaar
    -- Sethekk Halls
    [18472] = true,                   -- Darkweaver Syth
    [18473] = true,                   -- Talon King Ikiss
    [23035] = true,                   -- Anzu
    -- Shadow Labyrinth
    [18731] = true,                   -- Ambassador Hellmaw
    [18667] = true,                   -- Blackheart the Inciter
    [18732] = true,                   -- Grandmaster Vorpil
    [18708] = true,                   -- Murmur
    -- Old Hillsbrad Foothills
    [17848] = true,                   -- Lieutenant Drake
    [17862] = true,                   -- Captain Skarloc
    [18096] = true,                   -- Epoch Hunter
    -- The Black Morass
    [17879] = true,                   -- Chrono Lord Deja
    [17880] = true,                   -- Temporus
    [17881] = true,                   -- Aeonus
    -- The Mechanar
    [19219] = true,                   -- Mechano-Lord Capacitus
    [19221] = true,                   -- Nethermancer Sepethrea
    [19220] = true,                   -- Pathaleon the Calculator
    -- The Botanica
    [17976] = true,                   -- Commander Sarannis
    [17975] = true,                   -- High Botanist Freywinn
    [17978] = true,                   -- Thorngrin the Tender
    [17980] = true,                   -- Laj
    [17977] = true,                   -- Warp Splinter
    -- The Arcatraz
    [20870] = true,                   -- Zereketh the Unbound
    [20885] = true,                   -- Dalliah the Doomsayer
    [20886] = true,                   -- Wrath-Scryer Soccothrates
    [20912] = true,                   -- Harbinger Skyriss
    -- Magisters' Terrace
    [24723] = true,                   -- Selin Fireheart
    [24744] = true,                   -- Vexallus
    [24560] = true,                   -- Priestess Delrissa
    [24664] = true,                   -- Kael'thas Sunstrider (MgT)
}

-- ----------------------------------------------------------------
-- Print raid time & boss kill list (chat frame or channel)
-- ----------------------------------------------------------------
local function PrintRaidTime(chatType, chatLabel, whisperTarget)
    local log = GetViewRaidLog()
    if not log or not log.startTime then
        print("|cff00ff00[RDT]|r No raid timer recorded yet.")
        return
    end
    local elapsed, running = GetRaidElapsed(log)
    local bosses = log.bosses or {}
    local kind = (log.instType == "party") and "Dungeon time" or "Raid time"
    local multiZone = log.zones and #log.zones > 1
    local zoneText = multiZone and table.concat(log.zones, " + ") or (log.zone or "Raid")
    local header = string.format("%s - %s: %s%s",
        zoneText, kind, FormatDuration(elapsed), running and " (running)" or "")

    -- Per-boss elapsed: b.e = active time at kill (new format),
    -- fallback for pre-chain logs is wall time since first pull.
    local function BossElapsed(b)
        return b.e or (b.t - log.startTime)
    end

    if chatType then
        -- Post to chat: no color escapes allowed in SendChatMessage.
        -- whisperTarget is only set (and only used) for chatType WHISPER.
        SendChatMessage("( --< Raid Death Tracker - " .. header .. " >-- )",
            chatType, nil, whisperTarget)
        local lastZone
        for i, b in ipairs(bosses) do
            if multiZone and b.zone and b.zone ~= lastZone then
                SendChatMessage("-- " .. b.zone .. " --", chatType, nil, whisperTarget)
                lastZone = b.zone
            end
            local line = string.format("#%d  %s  +%s", i, b.name, FormatDuration(BossElapsed(b)))
            if b.dur then line = line .. string.format("  (fight %s)", FormatDuration(b.dur)) end
            SendChatMessage(line, chatType, nil, whisperTarget)
        end
        print("|cff00ff00[RDT]|r Raid time posted to " .. (chatLabel or chatType) .. ".")
        return
    end

    print("|cff00ff00[RDT]|r " .. header)
    if #bosses == 0 then
        print("  |cff666672No boss kills yet.|r")
    end
    local lastZone
    for i, b in ipairs(bosses) do
        if multiZone and b.zone and b.zone ~= lastZone then
            print("  |cff666672-- " .. b.zone .. " --|r")
            lastZone = b.zone
        end
        local line = string.format("  %d. |cffd1d6e1%s|r  |cff47bef5+%s|r",
            i, b.name, FormatDuration(BossElapsed(b)))
        if b.dur then
            line = line .. string.format("  |cff666672(fight %s)|r", FormatDuration(b.dur))
        end
        print(line)
    end
end

-- ----------------------------------------------------------------
-- UpdateDisplay
-- ----------------------------------------------------------------
local RANK_COLORS = {
    "|cffffcc00",  -- #1 Gold
    "|cffbbbbbb",  -- #2 Silver
    "|cffcd7f32",  -- #3 Bronze
    "|cff666672",  -- #4  (D.label)
    "|cff666672",  -- #5  (D.label)
}

local CLASS_COLORS = {
    WARRIOR  = "|cffC79C6E",
    PALADIN  = "|cffF58CBA",
    HUNTER   = "|cffABD473",
    ROGUE    = "|cffFFF569",
    PRIEST   = "|cffFFFFFF",
    SHAMAN   = "|cff0070DE",
    MAGE     = "|cff69CCF0",
    WARLOCK  = "|cff9482C9",
    DRUID    = "|cffFF7D0A",
}

function RaidDeathTrackerFrame:UpdateDisplay()
    UpdateTimeLine()
    local viewData, viewClasses = GetViewData()
    if not viewData or not next(viewData) then
        contentText:SetText("|cff333344No deaths recorded.|r")
        return
    end

    local sorted, total = GetSortedDeaths(viewData)

    local lines = {}
    for i = 1, math.min(TOP_N, #sorted) do
        local e      = sorted[i]
        local rank   = RANK_COLORS[i] or "|cff999999"
        local classId   = viewClasses and viewClasses[e.name]
        local nameColor = CLASS_COLORS[classId] or "|cffd1d6e1"
        table.insert(lines, string.format(
            "%s#%d|r  %s%s|r   |cff666672%dx|r",
            rank, i, nameColor, e.name, e.count
        ))
    end

    local extra  = #sorted - TOP_N
    local footer = ""
    if extra > 0 then
        footer = string.format(
            "\n|cff33334a+%d more  -  Total: %d|r",
            extra, total
        )
    elseif #sorted > 1 then
        footer = string.format("\n|cff444455Total: %d deaths|r", total)
    end

    local mvc = ""
    if #sorted >= 2 then
        mvc = string.format("\n|cff666672Most Valuable Corpse:|r |cffcc2222%s|r", sorted[1].name)
    end

    contentText:SetText(table.concat(lines, "\n") .. footer .. mvc)
end

-- ----------------------------------------------------------------
-- Helper: current group roster names (raid or party, incl. self)
-- ----------------------------------------------------------------
local function GetGroupRoster()
    local names = {}
    if IsInRaid() then
        for i = 1, 40 do
            local token = "raid" .. i
            if not UnitExists(token) then break end
            local n = UnitName(token)
            if n then names[n] = true end
        end
    elseif IsInGroup() then
        names[UnitName("player")] = true
        for i = 1, 4 do
            local token = "party" .. i
            if not UnitExists(token) then break end
            local n = UnitName(token)
            if n then names[n] = true end
        end
    end
    return names
end

-- ----------------------------------------------------------------
-- Print full roster (incl. 0 deaths) to the chat frame
-- ----------------------------------------------------------------
local function PrintFullList(chatType, chatLabel)
    local viewData, viewClasses = GetViewData()
    local roster = GetGroupRoster()

    -- Merge roster with recorded data so 0-death members appear too.
    local merged = {}
    for name in pairs(roster) do merged[name] = viewData[name] or 0 end
    for name, count in pairs(viewData) do merged[name] = count end

    local sorted, total = GetSortedDeaths(merged)
    if #sorted == 0 then
        print("|cff00ff00[RDT]|r No raid members found.")
        return
    end

    if chatType then
        -- Post to chat: no color escapes allowed in SendChatMessage.
        local header = "( --< Raid Death Tracker - Full List >-- )"
        if viewIndex > 0 and RDTSessions and RDTSessions[viewIndex] then
            header = "( --< Raid Death Tracker - " .. RDTSessions[viewIndex].name .. " >-- )"
        end
        SendChatMessage(header, chatType)
        for i, e in ipairs(sorted) do
            SendChatMessage(string.format("#%d  %s  -- %dx", i, e.name, e.count), chatType)
        end
        SendChatMessage(string.format("Total: %d deaths", total), chatType)
        print("|cff00ff00[RDT]|r Full list posted to " .. (chatLabel or chatType) .. ".")
        return
    end

    print("|cff00ff00[RDT]|r Full list (" .. #sorted .. " players, " .. total .. " deaths):")
    for i, e in ipairs(sorted) do
        local classId   = viewClasses and viewClasses[e.name]
        local nameColor = CLASS_COLORS[classId] or "|cffd1d6e1"
        print(string.format("  %d. %s%s|r - |cff666672%dx|r", i, nameColor, e.name, e.count))
    end
end

-- ----------------------------------------------------------------
-- Print only group members with 0 deaths (the "survivors")
-- ----------------------------------------------------------------
local function PrintZeroDeaths(chatType, chatLabel)
    local viewData, viewClasses = GetViewData()
    local roster = GetGroupRoster()

    if not next(roster) then
        print("|cff00ff00[RDT]|r No raid members found.")
        return
    end

    -- Collect group members without recorded deaths, sorted by name.
    local survivors = {}
    for name in pairs(roster) do
        if not viewData[name] or viewData[name] == 0 then
            table.insert(survivors, name)
        end
    end
    table.sort(survivors)

    if #survivors == 0 then
        print("|cff00ff00[RDT]|r Everyone has died at least once.")
        return
    end

    if chatType then
        -- Post to chat: no color escapes allowed in SendChatMessage.
        SendChatMessage("( --< Raid Death Tracker - No Deaths >-- )", chatType)
        for _, name in ipairs(survivors) do
            SendChatMessage(name .. "  -- 0x", chatType)
        end
        print("|cff00ff00[RDT]|r Survivors posted to " .. (chatLabel or chatType) .. ".")
        return
    end

    print("|cff00ff00[RDT]|r No deaths (" .. #survivors .. " players):")
    for _, name in ipairs(survivors) do
        local classId   = viewClasses and viewClasses[name]
        local nameColor = CLASS_COLORS[classId] or "|cffd1d6e1"
        print(string.format("  %s%s|r", nameColor, name))
    end
end

-- ----------------------------------------------------------------
-- Post Top 5 in Raid/Party
-- ----------------------------------------------------------------
function PostDeathsToChat(chatType, chatLabel)
    local viewData = GetViewData()
    if not viewData or next(viewData) == nil then
        print("|cff00ff00[RDT]|r No data to post.")
        return
    end

    chatType  = chatType  or "EMOTE"
    chatLabel = chatLabel or chatType

    local sorted, total = GetSortedDeaths(viewData)

    local header = "( --< Raid Death Tracker >-- )"
    if viewIndex > 0 and RDTSessions and RDTSessions[viewIndex] then
        header = "( --< Raid Death Tracker - " .. RDTSessions[viewIndex].name .. " >-- )"
    end

    SendChatMessage(header, chatType)
    for i = 1, math.min(TOP_N, #sorted) do
        local e = sorted[i]
        SendChatMessage(string.format("#%d  %s  -- %dx", i, e.name, e.count), chatType)
    end
    SendChatMessage(string.format("Total: %d deaths", total), chatType)

    print("|cff00ff00[RDT]|r Top 5 posted to " .. chatLabel .. ".")
end

-- ----------------------------------------------------------------
-- Group visibility + auto-reset on join
-- ----------------------------------------------------------------
local wasInGroup = false

-- Only update visibility, no reset (e.g. after /reload)
local function UpdateGroupVisibility()
    local inGroup = IsInRaid() or IsInGroup()
    if inGroup or isTestMode then display:Show() else display:Hide() end
    wasInGroup = inGroup
end

local MAX_SESSIONS = 5

local function SaveSession()
    local hasDeaths  = RaidDeathData and next(RaidDeathData)
    local rl         = RDTConfig and RDTConfig.raidLog
    local hasRaidLog = rl and rl.startTime
    if not hasDeaths and not hasRaidLog then return end
    local zone = (hasRaidLog and rl.zone) or GetRealZoneText() or "Unknown"
    if hasRaidLog and rl.zones and #rl.zones > 1 then
        zone = table.concat(rl.zones, " + ")
    end
    local date = date("%d.%m")
    local name = zone .. " " .. date
    local data, classes = {}, {}
    for k, v in pairs(RaidDeathData)  do data[k]    = v end
    for k, v in pairs(RDTClassCache)  do classes[k] = v end
    local raidLog
    if hasRaidLog then
        raidLog = {
            zone        = rl.zone,
            instType    = rl.instType,
            startTime   = rl.startTime,
            segStart    = rl.segStart,
            baseElapsed = rl.baseElapsed,
            finalDown   = rl.finalDown,
            endTime     = time(),
            bosses      = {},
        }
        if rl.zones then
            raidLog.zones = {}
            for _, z in ipairs(rl.zones) do table.insert(raidLog.zones, z) end
        end
        for _, b in ipairs(rl.bosses or {}) do
            table.insert(raidLog.bosses,
                { name = b.name, t = b.t, e = b.e, dur = b.dur, zone = b.zone })
        end
    end
    table.insert(RDTSessions, 1, { name = name, data = data, classes = classes, raidLog = raidLog })
    if #RDTSessions > MAX_SESSIONS then
        table.remove(RDTSessions, #RDTSessions)
    end
    print("|cff00ff00[RDT]|r Session saved: " .. name)
end

-- Reset + show only on actual group join
local function OnGroupRosterUpdate()
    local inGroup = IsInRaid() or IsInGroup()
    if inGroup and not wasInGroup then
        lastDeathTime, pendingDeaths = {}, {}
        RaidDeathData = {}
        RDTClassCache = {}
        if RDTConfig then RDTConfig.raidLog = {} end
        frame:UpdateDisplay()
        display:Show()
        print("|cff00ff00[RDT]|r Joined group — data reset.")
    elseif not inGroup and wasInGroup then
        SaveSession()
        lastDeathTime, pendingDeaths = {}, {}
        viewIndex = 0
        UpdateNavUI()
        if not isTestMode then display:Hide() end
    elseif not inGroup then
        if not isTestMode then display:Hide() end
    end
    wasInGroup = inGroup
end

-- ----------------------------------------------------------------
-- Death debounce: Priest Spirit of Redemption fires UNIT_DIED twice
-- (initial death + 15s ghost form expiry) — suppress the second.
-- ----------------------------------------------------------------
local DEATH_DEBOUNCE = 20

-- ----------------------------------------------------------------
-- Feign Death detection: confirm death after 3s delay
-- ----------------------------------------------------------------
local FEIGN_DEATH_DELAY = 3
-- Pending hunter checks are keyed by GUID, not a reusable raid unit token.

-- Currently running boss encounter (for fight duration)
local currentEncounter = nil  -- { id = encounterID, startT = GetTime() }

local deathCheckFrame = CreateFrame("Frame")

local function FindUnitToken(name, guid)
    local function matches(token)
        if guid then return UnitGUID(token) == guid end
        return UnitName(token) == name
    end
    if matches("player") then return "player" end
    for i = 1, 40 do
        local token = "raid"..i
        if not UnitExists(token) then break end
        if matches(token) then return token end
    end
    for i = 1, 4 do
        local token = "party"..i
        if not UnitExists(token) then break end
        if matches(token) then return token end
    end
end

local function OnDeathCheck(self)
    local now = GetTime()
    for guid, entry in pairs(pendingDeaths) do
        if now - entry.time >= FEIGN_DEATH_DELAY then
            pendingDeaths[guid] = nil
            local token = FindUnitToken(entry.name, guid)
            if token and UnitIsDeadOrGhost(token) then
                RaidDeathData[entry.name] = (RaidDeathData[entry.name] or 0) + 1
                frame:UpdateDisplay()
            end
            -- otherwise: Feign Death — don't count
        end
    end
    if not next(pendingDeaths) then
        self:SetScript("OnUpdate", nil)
    end
end

-- ----------------------------------------------------------------
-- Event Handler
-- ----------------------------------------------------------------
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == ADDON_NAME then
            if not RaidDeathData then RaidDeathData = {} end
            if not RDTConfig then RDTConfig = {} end
            if not RDTClassCache then RDTClassCache = {} end
            if not RDTSessions then RDTSessions = {} end
            if not RDTConfig.raidLog then
                -- Migration: RDTRaidLog was briefly its own SavedVariable
                RDTConfig.raidLog = (type(RDTRaidLog) == "table" and RDTRaidLog) or {}
            end
            RDTRaidLog = nil
            -- Migration: pre-chain logs lack the segment fields
            local rlog = RDTConfig.raidLog
            if rlog.startTime and not rlog.segStart then
                rlog.segStart    = rlog.startTime
                rlog.baseElapsed = 0
                rlog.zones       = { rlog.zone }
            end
            -- Migration: old minimapAngle field -> minimapPos (LibDBIcon format)
            if not RDTConfig.minimapPos then
                RDTConfig.minimapPos = RDTConfig.minimapAngle or 220
                RDTConfig.minimapAngle = nil
            end
            -- Restore persisted panel size (clamped to bounds)
            if RDTConfig.width and RDTConfig.height then
                local w = math.max(MIN_W, math.min(MAX_W, RDTConfig.width))
                local h = math.max(MIN_H, math.min(MAX_H, RDTConfig.height))
                display:SetSize(w, h)
            end
            LibStub("LibDBIcon-1.0"):Register("RaidDeathTracker", ldbObj, RDTConfig)
            minimapBtn = LibStub("LibDBIcon-1.0"):GetMinimapButton("RaidDeathTracker")
            self:UpdateDisplay()
            UpdateGroupVisibility()
            UpdateNavUI()
            print("|cff00ff00[RDT]|r v1.9.0 loaded. /rdt for help")
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateGroupVisibility()

    elseif event == "PLAYER_REGEN_DISABLED" then
        OnCombatStart()

    elseif event == "ENCOUNTER_START" then
        local encounterID = ...
        OnCombatStart()
        currentEncounter = { id = encounterID, startT = GetTime() }

    elseif event == "ENCOUNTER_END" then
        local encounterID, encounterName, _, _, success = ...
        if success == 1 or success == true then
            local dur
            if currentEncounter and currentEncounter.id == encounterID then
                dur = GetTime() - currentEncounter.startT
            end
            RecordBossKill(encounterID, encounterName, dur)
        end
        currentEncounter = nil

    elseif event == "BOSS_KILL" then
        local encounterID, encounterName = ...
        RecordBossKill(encounterID, encounterName, nil)

    elseif event == "GROUP_ROSTER_UPDATE"
        or event == "PARTY_MEMBERS_CHANGED"
        or event == "RAID_ROSTER_UPDATE" then
        OnGroupRosterUpdate()

    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, subEvent, _, _, _, _, _, destGUID, destName =
            CombatLogGetCurrentEventInfo()

        if subEvent == "SPELL_RESURRECT" and destGUID then
            lastDeathTime[destGUID] = nil
            local pending = pendingDeaths[destGUID]
            if pending then
                pendingDeaths[destGUID] = nil
                RaidDeathData[pending.name] = (RaidDeathData[pending.name] or 0) + 1
                frame:UpdateDisplay()
            end
            return
        end
        if subEvent ~= "UNIT_DIED" or not destGUID then return end

        -- Boss kill fallback via NPC id from the creature GUID
        -- (GUID format: Creature-0-server-instance-zone-npcID-spawn)
        if destGUID:sub(1, 8) == "Creature" then
            local npcID = tonumber((select(6, strsplit("-", destGUID))))
            local boss = npcID and BOSS_NPCS[npcID]
            if boss then
                RecordBossKill(nil, boss == true and destName or boss, nil)
            end
            return
        end

        if destGUID:sub(1, 6) == "Player"
            and (IsInRaid() or IsInGroup())
        then
            -- Only count own party/raid members
            local token = FindUnitToken(destName, destGUID)
            if token then
                local _, classId = UnitClass(token)
                if classId then RDTClassCache[destName] = classId end
                if classId == "HUNTER" then
                    -- Feign Death possible: confirm after 3s delay
                    pendingDeaths[destGUID] = { time = GetTime(), name = destName }
                    deathCheckFrame:SetScript("OnUpdate", OnDeathCheck)
                else
                    -- Suppress duplicate UNIT_DIED (Priest Spirit of Redemption fires twice).
                    local now = GetTime()
                    if classId == "PRIEST" and lastDeathTime[destGUID]
                        and now - lastDeathTime[destGUID] < DEATH_DEBOUNCE then
                        return
                    end
                    lastDeathTime[destGUID] = now
                    RaidDeathData[destName] = (RaidDeathData[destName] or 0) + 1
                    frame:UpdateDisplay()
                end
            end
        end
    end
end)

-- ----------------------------------------------------------------
-- Test mode
-- ----------------------------------------------------------------
local TEST_NAMES = {
    "Arthas", "Thrall", "Sylvanas", "Jaina", "Illidan",
    "Tyrande", "Kael'thas", "Vashj", "Akama", "Maiev",
}

local function ActivateTestMode()
    isTestMode = true
    viewIndex  = 0
    testDeathData = {}
    for _, name in ipairs(TEST_NAMES) do
        testDeathData[name] = math.random(1, 15)
    end
    -- Dummy double-raid chain: Karazhan (closed segment) + Gruul's Lair
    local now = time()
    testRaidLog = {
        zone        = "Gruul's Lair",
        zones       = { "Karazhan", "Gruul's Lair" },
        instType    = "raid",
        startTime   = now - 7200,
        segStart    = now - 1500,
        baseElapsed = 4800,
        finalDown   = true,
        bosses = {
            { name = "Attumen the Huntsman",   t = now - 6780, e = 420,  dur = 155, zone = "Karazhan" },
            { name = "Moroes",                 t = now - 6060, e = 1140, dur = 233, zone = "Karazhan" },
            { name = "The Curator",            t = now - 4200, e = 3000, dur = 312, zone = "Karazhan" },
            { name = "Prince Malchezaar",      t = now - 2400, e = 4800, dur = 428, zone = "Karazhan" },
            { name = "High King Maulgar",      t = now - 900,  e = 5400, dur = 258, zone = "Gruul's Lair" },
            { name = "Gruul the Dragonkiller", t = now - 300,  e = 6000, dur = 331, zone = "Gruul's Lair" },
        },
    }
    print("|cff00ff00[RDT]|r Test: " .. #TEST_NAMES .. " entries created.")
    display:Show()
    frame:UpdateDisplay()
    UpdateNavUI()
end

local function DeactivateTestMode()
    isTestMode = false
    viewIndex  = 0
    testDeathData = nil
    testRaidLog   = nil
    frame:UpdateDisplay()
    UpdateNavUI()
    UpdateGroupVisibility()
    print("|cff00ff00[RDT]|r Test mode ended.")
end

-- ----------------------------------------------------------------
-- Slash Commands
-- ----------------------------------------------------------------
SLASH_RAIDDEATHTRACKER1 = "/rdt"
SlashCmdList["RAIDDEATHTRACKER"] = function(msg)
    local raw = msg:match("^%s*(.-)%s*$") or ""
    msg = raw:lower()

    if     msg == ""           then
        if display:IsShown() then display:Hide() else display:Show() end
    elseif msg == "reset"      then
        RaidDeathData = {}
        RDTClassCache = {}
        lastDeathTime, pendingDeaths = {}, {}
        frame:UpdateDisplay()
        print("|cff00ff00[RDT]|r Deaths reset.")
    elseif msg:sub(1, 4) == "post" then
        local arg = msg:sub(6):match("^%s*(.-)%s*$") or ""
        local channelMap = { say = "SAY", yell = "YELL", party = "PARTY", raid = "RAID", emote = "EMOTE" }
        local ch = channelMap[arg]
        if arg ~= "" and not ch then
            print("|cff00ff00[RDT]|r Unknown channel. Use: say, yell, party, raid, emote")
            return
        end
        PostDeathsToChat(ch, arg ~= "" and arg or nil)
    elseif msg:sub(1, 4) == "list" then
        local arg = msg:sub(6):match("^%s*(.-)%s*$") or ""
        local channelMap = { say = "SAY", yell = "YELL", party = "PARTY", raid = "RAID", emote = "EMOTE" }
        local ch = channelMap[arg]
        if arg ~= "" and not ch then
            print("|cff00ff00[RDT]|r Unknown channel. Use: say, yell, party, raid, emote")
            return
        end
        PrintFullList(ch, arg ~= "" and arg or nil)
    elseif msg:sub(1, 4) == "zero" then
        local arg = msg:sub(6):match("^%s*(.-)%s*$") or ""
        local channelMap = { say = "SAY", yell = "YELL", party = "PARTY", raid = "RAID", emote = "EMOTE" }
        local ch = channelMap[arg]
        if arg ~= "" and not ch then
            print("|cff00ff00[RDT]|r Unknown channel. Use: say, yell, party, raid, emote")
            return
        end
        PrintZeroDeaths(ch, arg ~= "" and arg or nil)
    elseif msg:sub(1, 4) == "time" then
        local arg = msg:sub(6):match("^%s*(.-)%s*$") or ""
        if arg == "reset" then
            if RDTConfig then RDTConfig.raidLog = {} end
            frame:UpdateDisplay()
            print("|cff00ff00[RDT]|r Raid timer reset.")
            return
        end
        local channelMap = { say = "SAY", yell = "YELL", party = "PARTY", raid = "RAID", emote = "EMOTE" }
        local ch = channelMap[arg]
        if arg ~= "" and not ch then
            -- Anything that is no channel keyword counts as a player
            -- name -> whisper (original case from raw input).
            local target = raw:sub(6):match("^%s*(.-)%s*$")
            PrintRaidTime("WHISPER", target, target)
            return
        end
        PrintRaidTime(ch, arg ~= "" and arg or nil)
    elseif msg == "sessions"   then
        if not RDTSessions or #RDTSessions == 0 then
            print("|cff00ff00[RDT]|r No saved sessions.")
        else
            print("|cff00ff00[RDT]|r Saved sessions:")
            for i, s in ipairs(RDTSessions) do
                local count = 0
                for _ in pairs(s.data) do count = count + 1 end
                print(string.format("  %d. %s (%d players)", i, s.name, count))
            end
        end
    elseif msg == "test"       then ActivateTestMode()
    elseif msg == "test clear" then DeactivateTestMode()
    elseif msg == "debug"      then
        local count = 0
        if RaidDeathData then for _ in pairs(RaidDeathData) do count = count + 1 end end
        print("|cff00ff00[RDT]|r Debug:")
        print("  Entries: " .. count)
        print("  Panel visible: " .. tostring(display:IsShown()))
        print("  Panel size: " .. math.floor(display:GetWidth()) .. "x" .. math.floor(display:GetHeight()))
        print("  Minimap angle: " .. tostring(RDTConfig and RDTConfig.minimapPos))
        print("  Minimap btn size: " .. minimapBtn:GetWidth() .. "x" .. minimapBtn:GetHeight())
    else
        print("|cff00ff00[RDT]|r Commands:")
        print("  /rdt            - Toggle window")
        print("  /rdt reset      - Reset all deaths")
        print("  /rdt post [channel]   - Post top 5 (say/yell/party/raid/emote)")
        print("  /rdt list [channel]   - Full list incl. 0 deaths (optionally post)")
        print("  /rdt zero [channel]   - Only players with 0 deaths (optionally post)")
        print("  /rdt time [channel]   - Raid time & boss kills (optionally post)")
        print("  /rdt time <name>      - Whisper raid time to a player")
        print("  /rdt time reset       - Reset the raid timer")
        print("  /rdt sessions      - Show saved sessions")
        print("  /rdt test          - Test mode (dummy data)")
        print("  /rdt test clear    - End test mode")
        print("  /rdt debug         - Show debug information")
    end
end
