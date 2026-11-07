-- Shared pet commands and explicit learned pet abilities. Never change autocast.
local _,ns=...
local P={key="warlock.petAttack",name="Feuxton Pet Attack"}
ns.features.PetSupport=P
P.sacrificeIDs={[7812]=true,[19438]=true,[19440]=true,[19441]=true,[19442]=true,[19443]=true}
local function integer(value,low,high)
    local S=ns.state
    return not S.isSecret(value) and type(value)=="number" and value==math.floor(value) and value>=low and value<=high
end
function P.identity()
    local S=ns.state;local value=S.readableCall(UnitGUID,"pet")
    return type(value)=="string" and #value>0 and #value<=40 and not value:find("[^!-~]") and value or nil
end
-- GetPetActionInfo supplies the actual learned pet action, including its rank.
-- A missing/secret identity or incomplete scan cannot certify an absent skill.
function P.sacrificeAction()
    local S=ns.state;local identity=P.identity()
    if S.readableCall(UnitExists,"pet")==false then return nil,true,nil end
    if not identity or type(GetPetActionInfo)~="function" then return nil,false,identity end
    for slot=1,10 do
        local ok,name,texture,isToken,active,autoAllowed,autoEnabled,id=pcall(GetPetActionInfo,slot)
        if not ok or S.isSecret(name) or S.isSecret(id) or S.isSecret(isToken) then return nil,false,identity end
        if integer(id,1,2147483647) and P.sacrificeIDs[id] then
            local info=S.readableCall(S.spellAPI.GetSpellInfo,id)
            if isToken~=true and name=="Sacrifice" and S.safeField(info,"name")=="Sacrifice" then
                return {id=id,name=name,slot=slot,identity=identity},true,identity
            end
        end
    end
    return nil,true,identity
end
function P.abilityCandidate()
    local action=P.sacrificeAction()
    return action and {id=action.id,name="Sacrifice",unit="player",petAbility=true,petActionSlot=action.slot,petIdentity=action.identity} or nil
end
function P.current(entry)
    local action=P.sacrificeAction()
    return entry and action and entry.petAbility==true and entry.id==action.id
        and entry.petActionSlot==action.slot and entry.petIdentity==action.identity or false
end
function P.readSacrifice()
    local S=ns.state;local G=ns.features.GroupContext;local action,complete,identity=P.sacrificeAction()
    local r={id=action and action.id or 0,learned=complete and {status="observed",value=action~=nil} or {},usable={},mana={},range={},ready={},petIdentity=identity,petActionSlot=action and action.slot or 0,castMs=0}
    if not action then return r end
    local global=G.read(GetPetActionsUsable,1)
    local slot=G.read(GetPetActionSlotUsable,1,action.slot)
    if global.value==false or slot.value==false then r.usable={status="observed",value=false}
    elseif slot.value==true and (global.value==true or type(GetPetActionsUsable)~="function") then r.usable={status="observed",value=true} end
    -- Sacrifice costs no player mana and shields its owner at unlimited range.
    r.mana={status="observed",value=false};r.range={status="observed",value=true}
    local ok,start,duration,enabled=pcall(GetPetActionCooldown or function()end,action.slot)
    r.cooldownOK=ok;r.cooldownStart=start;r.cooldownDuration=duration
    if ok and not S.isSecret(start) and not S.isSecret(duration) and not S.isSecret(enabled)
        and type(start)=="number" and start>=0 and start==start and start~=math.huge
        and type(duration)=="number" and duration>=0 and duration==duration and duration~=math.huge then
        if enabled==0 or enabled==false then r.ready={status="observed",value=false}
        elseif enabled==1 or enabled==true then r.ready={status="observed",value=duration==0 or start+duration<=GetTime()} end
    end
    return r
end
function P.renderSacrifice(tile,r)
    local S=ns.state;tile.spellID=r.id>0 and r.id or nil;tile.known=r.learned.value
    S.renderSpellIcon(tile,S.readableCall(S.spellAPI.GetSpellInfo,r.id))
    local rendered=false
    if r.id>0 and r.cooldownOK then
        local function amount(v)return S.isSecret(v) or type(v)=="number" and v>=0 and v==v and v~=math.huge end
        if amount(r.cooldownStart) and amount(r.cooldownDuration) then rendered=pcall(tile.cooldown.SetCooldown,tile.cooldown,r.cooldownStart,r.cooldownDuration) end
    end
    if not rendered then tile.cooldown:Clear() end
    local shade=rendered and 1 or .35;tile.dial:SetColorTexture(shade,shade,shade,1)
    -- No player spell API, mana bar, GCD or cast receipt is borrowed for a pet action.
    for _,dot in ipairs(tile.visualSignals)do ns.features.RangeTracking.paintColor(dot,1,.65,0,1)end
    tile.manaCost.valid:SetColorTexture(1,.65,0,1)
end

function P.candidate(class)
    if class~="WARLOCK" then return nil end
    -- A command has no player spell ID and never pretends to be Attack (6603).
    return {id=0,name=P.name,unit="target",petCommand=true}
end

function P.bytes()
    local S=ns.state
    local class=S.readableCall(function()local _,key=UnitClass("player");return key end)
    local M=S.managedSpells
    local entry=M and M.entries["WARLOCK:"..P.name]
    local valid=class=="WARLOCK" and S.bindingsValid and M and M.current(entry)
        and entry.petCommand==true and entry.id==0 and entry.unit=="target"
    return S.bytes(valid and S.compactBindingCode(entry.key) or 0,2)..S.bytes(S.spellUseCode(P.key),1)
end
