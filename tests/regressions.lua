-- Run from the repository root: lua tests/regressions.lua [case-name]
-- Load the actual addon and library; only the WoW UI and event sources are mocked.
local report = print
local objects, methods = {}, {}
local function noop() end
local function widget(kind, parent)
    local object = setmetatable({ kind = kind, parent = parent, shown = true, scripts = {} }, {
        __index = function(_, key) return methods[key] or noop end,
    })
    objects[#objects + 1] = object
    return object
end
methods.SetScript = function(self, key, callback) self.scripts[key] = callback end
methods.Show = function(self) self.shown = true end
methods.Hide = function(self) self.shown = false end
methods.IsShown = function(self) return self.shown end
methods.SetText = function(self, text) self.text = text end
methods.CreateTexture = function(self) return widget("texture", self) end
methods.CreateFontString = function(self) return widget("font", self) end
methods.GetWidth = function() return 260 end
methods.GetHeight = function() return 185 end
CreateFrame = function(kind, name, parent)
    local object = widget(kind, parent)
    if name then _G[name] = object end
    return object
end
UIParent, Minimap, SlashCmdList = widget("Frame"), widget("Frame"), {}

local now, grouped, instance, difficulty = 100, true, "none", 1
local alice = { name = "Alice", guid = "Player-1-A", class = "WARRIOR", dead = true }
local bob = { name = "Bob", guid = "Player-1-B", class = "WARRIOR" }
local units = { player = bob, party1 = alice }
GetTime = function() return now end
time, date = GetTime, function() return "04.10" end
IsInRaid = function() return false end
IsInGroup = function() return grouped end
IsInInstance = function() return instance ~= "none", instance end
GetRealZoneText = function()
    return instance == "raid" and "Karazhan" or instance == "party" and "Hellfire Ramparts" or "World"
end
GetInstanceInfo = function()
    return GetRealZoneText(), instance, difficulty, nil, nil, nil, nil, instance == "party" and 543 or 532
end
UnitExists = function(token) return units[token] ~= nil end
UnitName = function(token) return units[token] and units[token].name end
UnitGUID = function(token) return units[token] and units[token].guid end
UnitClass = function(token)
    local class = units[token] and units[token].class
    return class, class
end
UnitIsDead = function(token) return units[token] and units[token].dead or false end
UnitIsDeadOrGhost = function(token)
    local unit = units[token]
    return unit and (unit.dead or unit.ghost) or false
end
MouseIsOver, IsMouseButtonDown = function() return true end, function() return false end

LibStub = nil
dofile("libs/LibDBIcon-1-0.lua")
assert(LibStub:GetLibrary("LibDBIcon-1.0"), "standalone startup must register the library")
local stub, iconLibrary, newLibrary = LibStub, LibStub("LibDBIcon-1.0"), LibStub.NewLibrary
dofile("libs/LibDBIcon-1-0.lua")
assert(LibStub == stub and LibStub.NewLibrary == newLibrary, "reuse an existing LibStub")
assert(LibStub("LibDBIcon-1.0") == iconLibrary, "reuse an existing library of the same version")
assert(LibStub:NewLibrary("test", "Revision: 5"))
assert(not LibStub:NewLibrary("test", 4), "an older library must not replace a newer version")

print = noop
dofile("RaidDeathTracker.lua")
local function event(name, ...)
    RaidDeathTrackerFrame.scripts.OnEvent(RaidDeathTrackerFrame, name, ...)
end
event("ADDON_LOADED", "RaidDeathTracker")

local function combatEvent(kind, unit)
    unit = unit or alice
    CombatLogGetCurrentEventInfo = function()
        return now, kind, nil, nil, nil, nil, nil, unit.guid, unit.name
    end
    event("COMBAT_LOG_EVENT_UNFILTERED")
end
local function advance(seconds)
    now = now + seconds
    for _, object in ipairs(objects) do
        local update = object.scripts.OnUpdate
        if object.kind == "Frame" and update then update(object, seconds) end
    end
end
local function command(text) SlashCmdList.RAIDDEATHTRACKER(text) end
local function click(label)
    for _, object in ipairs(objects) do
        if object.kind == "font" and object.text == label then
            object.parent.scripts.OnClick()
            return
        end
    end
    error("missing button " .. label)
end
local function reset()
    grouped, instance, difficulty = true, "none", 1
    alice.class, alice.dead, alice.ghost = "WARRIOR", true, false
    units = { player = bob, party1 = alice }
    RDTSessions, RDTConfig.raidLog = {}, {}
    command("test clear")
    command("reset")
end

local cases = {
    { "repeat-dungeon", function()
        instance = "party"
        event("PLAYER_REGEN_DISABLED")
        advance(20)
        event("BOSS_KILL", 1, "Watchkeeper Gargolmar")
        advance(20)
        event("BOSS_KILL", 2, "Vazruden the Herald")
        local log = RDTConfig.raidLog
        assert(log.finalDown)
        instance = "none"
        event("PLAYER_ENTERING_WORLD")
        advance(100)
        instance = "party"
        event("PLAYER_ENTERING_WORLD")
        event("PLAYER_REGEN_DISABLED")
        assert(not log.finalDown and log.segStart == now, "the next normal run needs a fresh segment")
        assert(log.baseElapsed == 40, "exclude travel and retain the first completed run")
        advance(20)
        event("BOSS_KILL", 1, "Watchkeeper Gargolmar")
        event("BOSS_KILL", 1, "Watchkeeper Gargolmar")
        assert(#log.bosses == 3 and log.bosses[3].e == 60, "count the second kill once")
    end },
    { "dungeon-reload-and-corpse-run", function()
        instance = "party"
        event("PLAYER_REGEN_DISABLED")
        advance(20)
        event("BOSS_KILL", 1, "Watchkeeper Gargolmar")
        local log, start = RDTConfig.raidLog, RDTConfig.raidLog.segStart
        instance = "none"
        event("PLAYER_ENTERING_WORLD")
        instance = "party"
        event("PLAYER_ENTERING_WORLD")
        event("PLAYER_REGEN_DISABLED")
        assert(log.segStart == start and #log.zones == 1, "an unfinished run survives re-entry")
        event("BOSS_KILL", 2, "Vazruden the Herald")
        event("PLAYER_ENTERING_WORLD", false, true)
        event("PLAYER_REGEN_DISABLED")
        assert(log.finalDown and log.segStart == start, "reload inside a finished run must not restart it")
    end },
    { "completed-lockout-reentry", function()
        for _, kind in ipairs({ "raid", "party" }) do
            RDTConfig.raidLog = {}
            instance, difficulty = kind, 2
            event("PLAYER_REGEN_DISABLED")
            advance(20)
            local log = RDTConfig.raidLog
            log.finalDown = true
            local start = log.segStart
            instance = "none"
            event("PLAYER_ENTERING_WORLD")
            instance = kind
            event("PLAYER_ENTERING_WORLD")
            event("PLAYER_REGEN_DISABLED")
            assert(log.finalDown and log.segStart == start, "a raid or heroic lockout is not a new run")
        end
    end },
    { "repeat-death", function()
        combatEvent("UNIT_DIED")
        advance(10)
        combatEvent("SPELL_RESURRECT")
        combatEvent("UNIT_DIED")
        assert(RaidDeathData.Alice == 2, "a second real death within 20 seconds must count")
    end },
    { "priest-resurrection", function()
        alice.class = "PRIEST"
        combatEvent("UNIT_DIED")
        advance(15)
        combatEvent("UNIT_DIED")
        assert(RaidDeathData.Alice == 1, "Spirit of Redemption must not count twice")
        combatEvent("SPELL_RESURRECT")
        advance(1)
        combatEvent("UNIT_DIED")
        assert(RaidDeathData.Alice == 2, "a resurrected priest's next death must count")
    end },
    { "hunter-release", function()
        alice.class = "HUNTER"
        combatEvent("UNIT_DIED")
        alice.dead, alice.ghost = false, true
        units.party1, units.party2 = bob, alice
        advance(4)
        assert(RaidDeathData.Alice == 1, "release and roster movement must preserve the death")
        assert(not RaidDeathData.Bob, "a recycled unit token must not identify the victim")
    end },
    { "hunter-resurrection", function()
        alice.class = "HUNTER"
        combatEvent("UNIT_DIED")
        advance(1)
        combatEvent("SPELL_RESURRECT")
        alice.dead = false
        assert(RaidDeathData.Alice == 1, "resurrection before the check must preserve the death")
        advance(3)
        assert(RaidDeathData.Alice == 1, "the delayed check must not count it again")
        alice.dead = true
        combatEvent("UNIT_DIED")
        advance(4)
        assert(RaidDeathData.Alice == 2, "a second hunter death must count separately")
    end },
    { "feign-death", function()
        alice.class, alice.dead = "HUNTER", false
        combatEvent("UNIT_DIED")
        advance(4)
        assert(not RaidDeathData.Alice, "Feign Death must not count")
    end },
    { "pending-reset", function()
        alice.class = "HUNTER"
        combatEvent("UNIT_DIED")
        command("reset")
        advance(4)
        assert(next(RaidDeathData) == nil, "reset must also clear pending deaths")
    end },
    { "history-session", function()
        RaidDeathData.Alice = 5
        RDTSessions = { { name = "Yesterday", data = { Bob = 2 }, classes = {} } }
        click("<")
        grouped = false
        event("GROUP_ROSTER_UPDATE")
        assert(#RDTSessions == 2 and RDTSessions[1].data.Alice == 5,
            "viewing history must not prevent saving the live session")
        -- Browsing an archive while solo must not suppress the next group join.
        click("<")
        grouped = true
        event("GROUP_ROSTER_UPDATE")
        assert(next(RaidDeathData) == nil, "a new group must start a new session")
    end },
    { "test-data", function()
        RaidDeathData.Alice = 7
        RDTClassCache.Alice = "WARRIOR"
        local saved, classes = RaidDeathData, RDTClassCache
        command("test")
        assert(RaidDeathData == saved and RaidDeathData.Alice == 7 and not RaidDeathData.Arthas,
            "sample data must never enter SavedVariables")
        assert(RDTClassCache == classes and RDTClassCache.Alice == "WARRIOR")
        combatEvent("UNIT_DIED")
        command("test clear")
        assert(RaidDeathData == saved and RaidDeathData.Alice == 8,
            "real deaths during test mode must survive clearing the preview")
    end },
    { "test-session", function()
        RaidDeathData.Alice = 3
        command("test")
        grouped = false
        event("GROUP_ROSTER_UPDATE")
        assert(#RDTSessions == 1 and RDTSessions[1].data.Alice == 3,
            "leaving during test mode must save real deaths")
        assert(not RDTSessions[1].data.Arthas, "samples must not enter the archive")
        assert(RaidDeathTrackerDisplay:IsShown(), "the preview should remain visible")
        grouped = true
        event("GROUP_ROSTER_UPDATE")
        command("test clear")
        assert(next(RaidDeathData) == nil, "joining during test mode must reset the live session")
    end },
    { "test-raid-log", function()
        instance = "raid"
        command("test")
        event("ENCOUNTER_START", 1)
        advance(10)
        event("ENCOUNTER_END", 1, "Moroes", nil, nil, 1)
        command("test clear")
        local log = RDTConfig.raidLog
        assert(log.startTime and #log.bosses == 1 and log.bosses[1].name == "Moroes",
            "previewing sample data must not pause the real raid log")
        assert(log.bosses[1].dur == 10)
    end },
}

local ran = 0
for _, case in ipairs(cases) do
    if not arg[1] or arg[1] == case[1] then
        reset()
        case[2]()
        ran = ran + 1
        report("PASS " .. case[1])
    end
end
assert(ran > 0, "unknown case name")
report("RaidDeathTracker regressions passed (" .. ran .. " cases plus library startup)")
