-- ============================================================
--  Embedded LibStub + LibDataBroker-1-1 shim + LibDBIcon-1.0
--  Minimal implementation fuer RaidDeathTracker
--  LibStub: public domain (Ace community)
-- ============================================================

-- LibStub
local LIBSTUB_MAJOR, LIBSTUB_MINOR = "LibStub", 2
local LibStub = _G[LIBSTUB_MAJOR]
if not LibStub or LibStub.minor < LIBSTUB_MINOR then
    LibStub = LibStub or { libs = {}, minors = {} }
    _G[LIBSTUB_MAJOR] = LibStub
    LibStub.minor = LIBSTUB_MINOR
    function LibStub:NewLibrary(major, minor)
        minor = assert(tonumber(tostring(minor):match("%d+")),
            "Minor version must be a number")
        local oldminor = self.minors[major]
        if oldminor and oldminor >= minor then return nil end
        self.minors[major] = minor
        self.libs[major] = self.libs[major] or {}
        return self.libs[major], oldminor
    end
    function LibStub:GetLibrary(major, silent)
        if not self.libs[major] and not silent then
            error(("Cannot find a library instance of %q."):format(tostring(major)), 2)
        end
        return self.libs[major], self.minors[major]
    end
    setmetatable(LibStub, { __call = LibStub.GetLibrary })
end

-- LibDataBroker-1-1 shim
local LDB = LibStub:NewLibrary("LibDataBroker-1-1", 4)
if LDB then
    LDB.objects = LDB.objects or {}
    function LDB:NewDataObject(name, obj)
        assert(not self.objects[name], "Duplicate data object: " .. name)
        obj = obj or {}
        self.objects[name] = obj
        return obj
    end
    function LDB:GetDataObjectByName(name)
        return self.objects[name]
    end
end

-- LibDBIcon-1.0
local LibDBIcon = LibStub:NewLibrary("LibDBIcon-1.0", 42)
if not LibDBIcon then return end

LibDBIcon.buttons = LibDBIcon.buttons or {}

local MINIMAP_RADIUS = 80

local function UpdateButtonPosition(button, db)
    local angle = math.rad(db and db.minimapPos or 220)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(angle) * MINIMAP_RADIUS,
        math.sin(angle) * MINIMAP_RADIUS)
end

function LibDBIcon:Register(name, dataobj, db)
    if self.buttons[name] then return end

    local button = CreateFrame("Button", "LibDBIcon10_" .. name, Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:EnableMouse(true)
    button:RegisterForDrag("LeftButton")
    button:RegisterForClicks("anyUp")

    -- Icon: BACKGROUND-Layer – Ring (BORDER) rendert darueber und liefert
    -- die kreisfoermige Beschneidung der Icon-Ecken.
    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture(dataobj.icon or "")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    button.icon = icon

    -- Ring: BORDER-Layer – liegt ueber dem Icon
    local border = button:CreateTexture(nil, "BORDER")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(56, 56)
    border:SetPoint("TOPLEFT", button, "TOPLEFT", -12, 12)
    button.border = border

    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- Drag zum Verschieben am Minimap-Rand
    button:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale  = UIParent:GetEffectiveScale()
            local angle  = math.deg(math.atan2(
                (cy / scale) - my, (cx / scale) - mx))
            if db then db.minimapPos = angle end
            UpdateButtonPosition(self, db)
        end)
    end)

    button:SetScript("OnDragStop", function(self)
        self:UnlockHighlight()
        self:SetScript("OnUpdate", nil)
    end)

    button:SetScript("OnClick", function(self, btn)
        if dataobj.OnClick then dataobj:OnClick(self, btn) end
    end)

    button:SetScript("OnEnter", function(self)
        if dataobj.OnTooltipShow then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            dataobj.OnTooltipShow(GameTooltip)
            GameTooltip:Show()
        end
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    UpdateButtonPosition(button, db)
    self.buttons[name] = button
end

function LibDBIcon:GetMinimapButton(name)
    return self.buttons[name]
end

function LibDBIcon:Refresh(name, db)
    local button = self.buttons[name]
    if button then UpdateButtonPosition(button, db) end
end
