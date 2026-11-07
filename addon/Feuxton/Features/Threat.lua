-- Readiness for the secure skull action. Never call SetRaidTarget from Lua:
-- this client can silently reject it even when pcall returns success.
local _, ns = ...
local T={};ns.features.Threat=T
local function timeNow()
 if type(ns.state.readableCall)~="function" then return nil end
 local now=ns.state.readableCall(GetTime)
 return type(now)=="number" and now>=0 and now==now and now<math.huge and now or nil
end
function T.resetSelection()
 T.selectedAt=timeNow();T.lastTime=T.selectedAt;T.attempted=false
end
T.resetSelection()
T.events=CreateFrame("Frame")
T.events:RegisterEvent("PLAYER_TARGET_CHANGED");T.events:RegisterEvent("PLAYER_ENTERING_WORLD")
T.events:SetScript("OnEvent",T.resetSelection)
function T.readyBinding()
    local S=ns.state;local M=S.managedSpells
    local entry=M and M.entries["PALADIN:Feuxton Skull"]
    if not S.bindingsValid or not entry or not M.current(entry) or not entry.skull then return end
    local class=S.readableCall(function()local _,key=UnitClass("player");return key end)
    if class~="PALADIN" then return end
    local role=S.readableCall(UnitGroupRolesAssigned,"player")
    if role~="TANK" and S.readableCall(GetPartyAssignment,"MAINTANK","player")~=true then return end
    if S.readableCall(UnitIsDeadOrGhost,"player")~=false or S.readableCall(UnitExists,"target")~=true
        or S.readableCall(UnitCanAttack,"player","target")~=true or S.readableCall(UnitIsDeadOrGhost,"target")~=false then T.resetSelection();return end
    local raid=S.readableCall(IsInRaid)
    if raid~=false and (raid~=true or S.readableCall(UnitIsGroupLeader,"player")~=true and S.readableCall(UnitIsGroupAssistant,"player")~=true) then return end
    if type(GetRaidTargetIndex)~="function" then return end
    -- A successful nil is a readable unmarked target; missing/error/secret is
    -- unknown. Never toggle an existing skull off or inspect a secret index.
    local ok,index=pcall(GetRaidTargetIndex,"target")
    if not ok or S.isSecret(index) or index~=nil and (type(index)~="number" or index~=math.floor(index) or index<0 or index>8) or index==8 then return end
    local now=timeNow()
    if not now then T.selectedAt=nil;T.lastTime=nil;return end
    if not T.selectedAt or not T.lastTime or now<T.lastTime then T.resetSelection();return end
    T.lastTime=now
    if T.attempted or now-T.selectedAt<=2 then return end
    return entry.key
end
function T.clicked(down)
    -- Reserve before client delivery; failed/partial keys cannot spam this
    -- selection. A different selection starts its own two-second dwell.
    if down==true then T.attempted=true end
end
