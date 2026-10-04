-- Run from the repository root: lua tests/regressions.lua
local realprint=print
local objects={}
local methods={}
local function obj(kind,parent)
 local o=setmetatable({kind=kind,parent=parent,shown=true,scripts={}}, {__index=function(_,k)return methods[k] or function()end end})
 objects[#objects+1]=o;return o
end
methods.SetScript=function(s,k,f)s.scripts[k]=f end
methods.Show=function(s)s.shown=true end;methods.Hide=function(s)s.shown=false end
methods.IsShown=function(s)return s.shown end
methods.SetText=function(s,t)s.text=t end
methods.CreateTexture=function(s)return obj('texture',s)end
methods.CreateFontString=function(s)return obj('font',s)end
methods.GetWidth=function()return 260 end;methods.GetHeight=function()return 185 end
CreateFrame=function(kind,name,parent)local o=obj(kind,parent);if name then _G[name]=o end;return o end
UIParent=obj('Frame');Minimap=obj('Frame');SlashCmdList={}
local now=100;local grouped=true;local class='WARRIOR';local dead=true;local ghost=false;local moved=false
GetTime=function()return now end;time=GetTime;date=function()return '04.10'end
IsInRaid=function()return false end;IsInGroup=function()return grouped end
IsInInstance=function()return false,'none'end;GetRealZoneText=function()return 'World'end
UnitName=function(unit)if unit=='player'then return 'Alice' end end
UnitExists=function(unit)return unit=='player' or (moved and unit=='party1')end
UnitGUID=function(unit)if unit==(moved and 'party1' or 'player')then return 'Player-1-A' end end
UnitClass=function()return class,class end
UnitIsDead=function()return dead end
UnitIsDeadOrGhost=function()return dead or ghost end
MouseIsOver=function()return true end;IsMouseButtonDown=function()return false end
LibStub=nil
dofile('libs/LibDBIcon-1-0.lua')
assert(LibStub:GetLibrary('LibDBIcon-1.0'))
assert(LibStub:NewLibrary('test', 'Revision: 5'))
assert(not LibStub:NewLibrary('test', 4))
print=function()end
dofile('RaidDeathTracker.lua')
local event=RaidDeathTrackerFrame.scripts.OnEvent
event(RaidDeathTrackerFrame,'ADDON_LOADED','RaidDeathTracker')
local function death()
 CombatLogGetCurrentEventInfo=function()return now,'UNIT_DIED',nil,nil,nil,nil,nil,'Player-1-A','Alice'end
 event(RaidDeathTrackerFrame,'COMBAT_LOG_EVENT_UNFILTERED')
end
death();now=110;death()
assert(RaidDeathData.Alice==2, 'a second real death must count')
class='HUNTER';now=200;RaidDeathData={};death();dead=false;ghost=true;moved=true;now=204
for _,o in ipairs(objects)do if o.kind=='Frame'and o~=RaidDeathTrackerDisplay and o.scripts.OnUpdate then o.scripts.OnUpdate(o,4)end end
assert(RaidDeathData.Alice==1, 'release and roster movement must preserve a hunter death')
ghost=false;moved=false;now=210;death()
CombatLogGetCurrentEventInfo=function()return now,'SPELL_RESURRECT',nil,nil,nil,nil,nil,'Player-1-A','Alice'end
event(RaidDeathTrackerFrame,'COMBAT_LOG_EVENT_UNFILTERED')
assert(RaidDeathData.Alice==2, 'resurrection before the check must preserve the death')
now=214
for _,o in ipairs(objects)do if o.kind=='Frame'and o~=RaidDeathTrackerDisplay and o.scripts.OnUpdate then o.scripts.OnUpdate(o,4)end end
assert(RaidDeathData.Alice==2, 'resurrection must not double-count the pending death')
now=220;death();now=224
for _,o in ipairs(objects)do if o.kind=='Frame'and o~=RaidDeathTrackerDisplay and o.scripts.OnUpdate then o.scripts.OnUpdate(o,4)end end
assert(RaidDeathData.Alice==2, 'Feign Death must not count')
RaidDeathData={Alice=5};RDTSessions={{name='Yesterday',data={Bob=2},classes={}}}
for _,o in ipairs(objects)do if o.kind=='font' and o.text=='<'then o.parent.scripts.OnClick()end end
grouped=false;event(RaidDeathTrackerFrame,'GROUP_ROSTER_UPDATE')
assert(#RDTSessions==2 and RDTSessions[1].data.Alice==5, 'archive view must not prevent saving')
grouped=true;event(RaidDeathTrackerFrame,'GROUP_ROSTER_UPDATE')
assert(next(RaidDeathData)==nil, 'a new group must start a new session')
RaidDeathData.Alice=7
local saved=RaidDeathData
SlashCmdList.RAIDDEATHTRACKER('test')
assert(RaidDeathData==saved and RaidDeathData.Alice==7, 'test data must never enter SavedVariables')
SlashCmdList.RAIDDEATHTRACKER('test clear')
assert(RaidDeathData==saved and RaidDeathData.Alice==7, 'clearing test mode must preserve the live session')
realprint('RaidDeathTracker regressions passed')
