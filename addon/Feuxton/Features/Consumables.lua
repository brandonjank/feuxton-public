-- Shared inventory actions. Restricted/unavailable values remain unknown.
local _,ns=...
local C={};ns.features.Consumables=C
C.ids={19013,19012,9421,19011,19010,5510,19009,19008,5509,19007,19006,5511,19005,19004,5512}
local function api(name,legacy) return type(C_Item)=="table" and C_Item[name] or _G[legacy] end
local function number(value)
    local S=ns.state
    return not S.isSecret(value) and type(value)=="number" and value>=0 and value==math.floor(value) and value<2147483648 and value or nil
end
function C.inventory()
    local S=ns.state;local now=S.readableCall(GetTime)
    if C.scannedAt and now and now-C.scannedAt<.25 then return C.itemID,C.count end
    C.scannedAt=now;C.itemID=0;C.count=0
    local unknown=false
    for _,id in ipairs(C.ids) do
        local count=number(S.readableCall(api("GetItemCount","GetItemCount"),id,false,false,false,false))
        if count==nil then unknown=true
        elseif count>0 then C.itemID=id;C.count=count;return id,count end
    end
    if unknown then C.count=nil end
    return C.itemID,C.count
end
function C.candidate()
    local id=C.inventory()
    return {id=0,name="Feuxton Healthstone",unit="player",itemID=id}
end
-- Scan to a confirmed end before reporting absence. Hidden names and a full
-- bounded scan stay unknown; Well Fed is not an active eating effect.
function C.recovery()
    local S=ns.state;local A=type(C_UnitAuras)=="table" and C_UnitAuras or {}
    if type(A.GetAuraDataByIndex)~="function" then return nil,nil end
    local eating,drinking,complete=false,false,true
    for i=1,80 do
        local ok,a=pcall(A.GetAuraDataByIndex,"player",i,"HELPFUL")
        if not ok or S.isSecret(a) then complete=false
        elseif a==nil then
            if not complete then return eating and true or nil,drinking and true or nil end
            return eating,drinking
        else
            local name=S.safeField(a,"name")
            if type(name)~="string" then complete=false
            elseif name=="Food" or name==FOOD then eating=true
            elseif name=="Drink" or name==DRINK then drinking=true
            elseif name=="Food & Drink" or name=="Refreshment" then eating=true;drinking=true end
        end
    end
    return eating and true or nil,drinking and true or nil
end
function C.packet(tick)
    local S=ns.state;local id,count=C.inventory();local ready,usable,spellID
    if id>0 then
        local fn=api("GetItemCooldown","GetItemCooldown")
        if type(fn)=="function" then
            local ok,start,duration,enabled=pcall(fn,id)
            if ok and not S.isSecret(start) and not S.isSecret(duration) and not S.isSecret(enabled) and type(start)=="number" and type(duration)=="number" and start>=0 and duration>=0 then
                if enabled==true or enabled==1 then ready=start==0 or duration==0 or start+duration<=(S.readableCall(GetTime) or -1)
                elseif enabled==false or enabled==0 then ready=false end
            end
        end
        usable=S.readableCall(api("IsUsableItem","IsUsableItem"),id)
        if type(usable)~="boolean" then usable=nil end
        local getSpell=api("GetItemSpell","GetItemSpell")
        if type(getSpell)=="function" then local ok,name,value=pcall(getSpell,id);if ok then spellID=number(value) end end
    end
    local class=S.readableCall(function()local _,key=UnitClass("player");return key end)
    local M=S.managedSpells;local entry=M and M.entries[class..":Feuxton Healthstone"]
    local key=M and M.current(entry) and entry.itemID==id and S.compactBindingCode(entry.key) or 0
    local function flag(v)return v==true and 2 or v==false and 1 or 0 end
    local eating,drinking=C.recovery()
    local packet="HHI2"..S.bytes(S.setupSession,4)..S.bytes(tick,4)..S.bytes(id,4)..S.bytes(spellID or 0,4)..S.bytes(count and math.min(count,65534) or 65535,2)..S.bytes(flag(ready),1)..S.bytes(flag(usable),1)..S.bytes(S.spellUseCode("shared.healthstone"),1)..S.bytes(key,2)..S.bytes(flag(eating),1)..S.bytes(flag(drinking),1)
    return packet..S.bytes(S.adler32(packet),4)
end
local events=CreateFrame("Frame")
events:RegisterEvent("BAG_UPDATE_DELAYED");events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent",function()
    C.scannedAt=nil
    local S=ns.state
    if S.discoverBindings and S.readableCall(InCombatLockdown)==false then S.discoverBindings() end
end)
