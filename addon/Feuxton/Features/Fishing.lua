local _,ns=...
local F={session=nil,casts=0,catches=0,escaped=0,items=0,skillups=0,lastItem=0,lastQuantity=0}
ns.features.Fishing=F
local fishingSpells={[7620]=true,[7731]=true,[7732]=true,[18248]=true,[1240948]=true,[1240959]=true,[1240970]=true,[1240983]=true}
local function public(value,kind)
    return not ns.state.isSecret(value) and type(value)==kind
end
local function call(api,...)
    if not public(api,"function") then return end
    local ok,a,b,c=pcall(api,...)
    if ok then return a,b,c end
end
local controlsFamily,controlsButton="fishing.controls","FeuxtonFishingControls"
local interactAction="INTERACTTARGET"
-- Match Blizzard's Enable Interact Key and Interact Key Icons > Show All.
local controlValues={
    {"softTargetInteract","3"},
    {"SoftTargetIconEnemy","1"},
    {"SoftTargetIconInteract","1"},
    {"SoftTargetIconGameObject","1"},
    {"SoftTargetLowPriorityIcons","1"},
}
local function cvarAPI(name,legacy)
    if public(C_CVar,"table") then
        local api=ns.state.safeField(C_CVar,name)
        if public(api,"function") then return api end
    end
    return legacy
end
local function readControls()
    local binding=call(GetBindingAction,"E",false)
    local effective=call(GetBindingAction,"E",true)
    if not public(binding,"string") or not public(effective,"string") then return 0 end
    if effective~=binding and effective~=interactAction then return 3 end
    local get=cvarAPI("GetCVar",GetCVar)
    local changes={}
    for _,setting in ipairs(controlValues) do
        local value=call(get,setting[1])
        if not public(value,"string") or tonumber(value)==nil then return 0 end
        if tonumber(value)~=tonumber(setting[2]) then changes[#changes+1]=setting end
    end
    if binding==interactAction and #changes==0 then return 2 end
    return 1,binding,changes
end
local function change(api,...)
    if not public(api,"function") then return false end
    local ok,result=pcall(api,...)
    return ok and not ns.state.isSecret(result) and result~=false
end
local function observedFalse(api,...)
    local value=call(api,...)
    return public(value,"boolean") and value==false
end
local function configureControls()
    local managed=ns.state.managedSpells
    if not managed or not F.controlsKey or not managed.auxiliaryCurrent(controlsFamily,controlsButton,F.controlsKey) then return end
    if not observedFalse(InCombatLockdown) or not observedFalse(UnitAffectingCombat,"player") or
       not observedFalse(UnitIsDeadOrGhost,"player") or not observedFalse(UnitOnTaxi,"player") then return end
    if not public(GetCurrentKeyBoardFocus,"function") then return end
    local ok,focus=pcall(GetCurrentKeyBoardFocus)
    if not ok or ns.state.isSecret(focus) or focus~=nil then return end
    local state,_,classID,subclassID=ns.features.Equipment.observe()
    if state~=2 or classID~=2 or subclassID~=20 then return end
    local status,binding,changes=readControls()
    if status~=1 then return end
    if binding~=interactAction then
        local set=call(GetCurrentBindingSet)
        if not public(set,"number") or (set~=1 and set~=2) or not public(SaveBindings,"function") then return end
        if not change(SetBinding,"E",interactAction) then return end
        local assigned=call(GetBindingAction,"E",false)
        if not public(assigned,"string") or assigned~=interactAction then return end
        if not change(SaveBindings,set) then
            if binding=="" then change(SetBinding,"E") else change(SetBinding,"E",binding) end
            return
        end
    end
    local set=cvarAPI("SetCVar",SetCVar)
    for _,setting in ipairs(changes) do change(set,setting[1],setting[2]) end
end
function F.controlsObservation()
    local status=readControls()
    local managed=ns.state.managedSpells
    if status~=1 or not managed or not observedFalse(InCombatLockdown) then return status,"" end
    if not F.controlsButton then
        local button=CreateFrame("Button",controlsButton,UIParent)
        button:SetSize(1,1)
        button:SetPoint("TOPLEFT",UIParent,"TOPLEFT",-10000,10000)
        button:SetAlpha(0)
        button:RegisterForClicks("AnyDown")
        button:SetScript("OnClick",configureControls)
        F.controlsButton=button
    end
    F.controlsKey=managed.claimAuxiliaryBinding(controlsFamily,controlsButton)
    return status,F.controlsKey or ""
end
local function session()
    local value=ns.state.setupSession
    if F.session~=value then
        F.session=value
        F.casts,F.catches,F.escaped,F.items,F.skillups,F.lastItem,F.lastQuantity=0,0,0,0,0,0,0
        F.resolved,F.loot,F.slots=nil,nil,nil
    end
end
local function increment(field,step)F[field]=(F[field]+(step or 1))%4294967296 end
local function lootReady()
    local fishing=call(IsFishingLoot)
    if F.loot or not public(fishing,"boolean") or not fishing then return end
    F.loot=true;F.slots={}
    if F.casts~=F.resolved then F.resolved=F.casts;increment("catches") end
    local count=call(GetNumLootItems)
    if not public(count,"number") or count<0 or count>32 then return end
    for slot=1,count do
        local link=call(GetLootSlotLink,slot)
        local _,_,quantity=call(GetLootSlotInfo,slot)
        local id=public(link,"string") and tonumber(link:match("|Hitem:(%d+):"))
        if id and id>0 and id<2147483648 and public(quantity,"number") and quantity>=1 and quantity<=65535 and quantity==math.floor(quantity) then
            F.slots[slot]={id=id,quantity=quantity}
        end
    end
end
local events=CreateFrame("Frame")
for _,event in ipairs({"UNIT_SPELLCAST_CHANNEL_START","LOOT_READY","LOOT_OPENED","LOOT_SLOT_CLEARED","LOOT_CLOSED","UI_ERROR_MESSAGE","CHAT_MSG_SKILL"}) do pcall(events.RegisterEvent,events,event) end
events:SetScript("OnEvent",function(_,event,a,b,c)
    session()
    if event=="UNIT_SPELLCAST_CHANNEL_START" and public(a,"string") and a=="player" and public(c,"number") and fishingSpells[c] then
        increment("casts")
    elseif event=="LOOT_READY" or event=="LOOT_OPENED" then lootReady()
    elseif event=="LOOT_CLOSED" then F.loot,F.slots=nil,nil
    elseif event=="LOOT_SLOT_CLEARED" and F.slots and public(a,"number") then
        local slot=F.slots[a]
        if slot then
            increment("items",slot.quantity);F.lastItem,F.lastQuantity=slot.id,slot.quantity;F.slots[a]=nil
        end
    elseif event=="UI_ERROR_MESSAGE" and public(b,"string") and public(ERR_FISH_ESCAPED,"string") and b==ERR_FISH_ESCAPED and F.casts>0 and F.casts~=F.resolved then
        increment("escaped");F.resolved=F.casts
    elseif event=="CHAT_MSG_SKILL" and public(a,"string") then
        local name=call(GetSpellInfo,7620)
        if not public(name,"string") and public(C_Spell,"table") then name=call(ns.state.safeField(C_Spell,"GetSpellName"),7620) end
        if public(name,"string") and #name>0 and a:find(name,1,true) then increment("skillups") end
    end
end)
function F.packet(tick)
    session()
    local S=ns.state;local enchanted=call(GetWeaponEnchantInfo)
    local lure=public(enchanted,"boolean") and (enchanted and 2 or 1) or 0
    local packet="HFF1"..S.bytes(F.session,4)..S.bytes(tick,4)..S.bytes(F.casts,4)..S.bytes(F.catches,4)..S.bytes(F.escaped,4)
        ..S.bytes(F.items,4)..S.bytes(F.skillups,4)..S.bytes(F.lastItem,4)..S.bytes(F.lastQuantity,2)..S.bytes(lure,1)
    return packet..S.bytes(S.adler32(packet),4)
end
