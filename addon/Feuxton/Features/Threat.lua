-- Readiness for the secure skull action. Never call SetRaidTarget from Lua:
-- this client can silently reject it even when pcall returns success.
local _, ns = ...
local T={};ns.features.Threat=T
function T.readyBinding()
    local S=ns.state;local M=S.managedSpells
    local entry=M and M.entries["PALADIN:Feuxton Skull"]
    if not S.bindingsValid or not entry or not M.current(entry) or not entry.skull then return end
    local class=S.readableCall(function()local _,key=UnitClass("player");return key end)
    if class~="PALADIN" then return end
    local role=S.readableCall(UnitGroupRolesAssigned,"player")
    if role~="TANK" and S.readableCall(GetPartyAssignment,"MAINTANK","player")~=true then return end
    if S.readableCall(UnitIsDeadOrGhost,"player")~=false or S.readableCall(UnitExists,"target")~=true
        or S.readableCall(UnitCanAttack,"player","target")~=true or S.readableCall(UnitIsDeadOrGhost,"target")~=false then return end
    local raid=S.readableCall(IsInRaid)
    if raid~=false and (raid~=true or S.readableCall(UnitIsGroupLeader,"player")~=true and S.readableCall(UnitIsGroupAssistant,"player")~=true) then return end
    if type(GetRaidTargetIndex)~="function" then return end
    -- A successful nil is a readable unmarked target; missing/error/secret is
    -- unknown. Never toggle an existing skull off or inspect a secret index.
    local ok,index=pcall(GetRaidTargetIndex,"target")
    if not ok or S.isSecret(index) or index~=nil and (type(index)~="number" or index~=math.floor(index) or index<0 or index>8) or index==8 then return end
    local now=S.readableCall(GetTime)
    if type(now)~="number" or now<0 or now~=now or now==math.huge or type(FeuxtonDB)~="table" then return end
    local last=FeuxtonDB.lastTankSkullAt
    if type(last)=="number" and last==last and last>=0 then
        -- Saved uptime also keeps /reload from bypassing the limit. If a new
        -- game process resets uptime, wait eight seconds from the new sample.
        if now<last then FeuxtonDB.lastTankSkullAt=now;return end
        if now-last<8 then return end
    end
    return entry.key
end
function T.clicked(down)
    if down~=true or type(FeuxtonDB)~="table" then return end
    local now=ns.state.readableCall(GetTime)
    if type(now)=="number" and now>=0 and now==now and now<math.huge then FeuxtonDB.lastTankSkullAt=now end
end
