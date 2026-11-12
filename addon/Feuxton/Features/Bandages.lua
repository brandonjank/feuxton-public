-- Shared self-bandage offer. Inventory metadata is deferred; live readiness is not cached.
local _,ns=...
local B={Key="shared.bandage",name="Feuxton Bandage",dirty=true,items={},pending={},present={}}
ns.features.Bandages=B
local function api(name,legacy)return type(C_Item)=="table" and C_Item[name] or _G[legacy]end
local function number(value,maximum)
    return not ns.state.isSecret(value) and type(value)=="number" and value>=0 and value==math.floor(value) and value<=(maximum or 2147483647) and value or nil
end
local function itemState(id)
    local S=ns.state;local count=number(S.readableCall(api("GetItemCount","GetItemCount"),id,false,false,false,false))
    local ready,usable,spellID
    local cooldown=api("GetItemCooldown","GetItemCooldown")
    if type(cooldown)=="function"then
        local ok,start,duration,enabled=pcall(cooldown,id)
        if ok and not S.isSecret(start) and not S.isSecret(duration) and not S.isSecret(enabled) and type(start)=="number" and type(duration)=="number" and start>=0 and duration>=0 then
            if enabled==true or enabled==1 then local now=S.readableCall(GetTime);ready=start==0 or duration==0 or type(now)=="number" and start+duration<=now
            elseif enabled==false or enabled==0 then ready=false end
        end
    end
    local value=S.readableCall(api("IsUsableItem","IsUsableItem"),id)
    if type(value)=="boolean"then usable=value end
    local spell=api("GetItemSpell","GetItemSpell")
    if type(spell)=="function"then local ok,_,id=pcall(spell,id);if ok then spellID=number(id);if spellID==0 then spellID=nil end end end
    return count,ready,usable,spellID
end
B.itemState=itemState
local function facts(id)
    local S=ns.state;local C=ns.features.Consumables;local public=C and C.publicItemFacts(id)
    if not public then return nil end
    local enums=type(Enum)=="table" and Enum.ItemConsumableSubclass
    local bandage=type(enums)=="table" and number(enums.Bandage,255) or nil
    if public.classID~=0 or public.subclassID~=(bandage or 7)then return false end
    local _,_,_,spellID=itemState(id);if not spellID then return nil end
    local description=S.readableCall(S.spellAPI and S.spellAPI.GetSpellDescription or GetSpellDescription,spellID)
    local healing
    if not S.isSecret(description) and type(description)=="string" and #description<=1024 then
        -- An optional public tooltip number orders carried bandages only. It
        -- is never a predicted player heal or a readiness/skill observation.
        local value=description:match("[Hh]eals?%s+([%d,]+)%s+damage") or description:match("[Rr]estores?%s+([%d,]+)%s+health")
        if value then healing=number(tonumber((value:gsub(",",""))))end
    end
    return {itemID=id,spellID=spellID,minLevel=public.minLevel,itemLevel=public.itemLevel,healing=healing}
end
function B.scan()
    local S=ns.state
    if not B.dirty or S.readableCall(InCombatLockdown)~=false then return end
    B.dirty=false;B.pending={};B.present={};local items={}
    local C=ns.features.Consumables
    if not C or type(C.bagLocations)~="function"then B.items={};B.complete=false;return end
    local locations,complete=C.bagLocations()
    for _,location in ipairs(locations)do
        local id=location.itemID
        if not B.present[id]then
            B.present[id]=true;local item=facts(id)
            if item==nil then B.pending[id]=true;complete=false
            elseif item then if #items<32 then items[#items+1]=item else complete=false end end
        end
    end
    local healingKnown=#items>0;for _,item in ipairs(items)do if not item.healing then healingKnown=false end end
    table.sort(items,function(a,b)
        if healingKnown and a.healing~=b.healing then return a.healing>b.healing end
        if (a.itemLevel or 0)~=(b.itemLevel or 0)then return (a.itemLevel or 0)>(b.itemLevel or 0)end
        if (a.minLevel or 0)~=(b.minLevel or 0)then return (a.minLevel or 0)>(b.minLevel or 0)end
        return a.itemID>b.itemID
    end)
    B.items=items;B.complete=complete
end
function B.select()
    local S=ns.state;B.scan()
    if S.readableCall(InCombatLockdown)~=false then return B.selected end
    local level=number(S.readableCall(UnitLevel,"player"),255);local selected
    for _,item in ipairs(B.items)do
        local count,_,usable,spellID=itemState(item.itemID)
        if level and item.minLevel and item.minLevel<=level and count and count>0 and usable==true and spellID==item.spellID then selected=item;break end
    end
    -- A transient restriction (e.g. Recently Bandaged) must not exchange the
    -- secure item identity. Fresh offer usability still blocks every send.
    if not selected and B.selected then
        for _,item in ipairs(B.items)do if item.itemID==B.selected.itemID and item.spellID==B.selected.spellID then selected=item;break end end
    end
    local previous=B.selected;B.selected=selected
    if (previous and previous.itemID or 0)~=(selected and selected.itemID or 0) or (previous and previous.spellID or 0)~=(selected and selected.spellID or 0)then
        if ns.markSetupDirty then ns.markSetupDirty()end
    end
    return selected
end
function B.candidate()
    local item=B.select()
    if not item then return nil end
    return {id=item.spellID,name=B.name,abilityKey=B.Key,unit="player",itemID=item.itemID}
end
function B.recentlyBandaged()
    local S=ns.state;local A=type(C_UnitAuras)=="table" and C_UnitAuras or {}
    -- This is an exact known aura query. Restricted/nil/error results are not
    -- absence; only a valid public false or a complete readable scan is proof.
    if type(A.GetPlayerAuraBySpellID)=="function"then
        for _,id in ipairs({11196,1305047}) do
            local ok,a=pcall(A.GetPlayerAuraBySpellID,id)
            if ok and not S.isSecret(a) and type(a)=="table" and number(S.safeField(a,"spellId"))==id then return true end
        end
    end
    if type(A.GetAuraDataByIndex)~="function"then return nil end
    local complete=true
    for index=1,80 do
        local ok,a=pcall(A.GetAuraDataByIndex,"player",index,"HARMFUL")
        if not ok or S.isSecret(a)then complete=false
        elseif a==nil then if complete then return false else return nil end
        else
            local id=number(S.safeField(a,"spellId"))
            if id==11196 or id==1305047 then return true elseif not id then complete=false end
        end
    end
    return nil
end
function B.packet(tick)
    local S=ns.state;local item=B.select();local id=item and item.itemID or 0
    if not item or id<=0 then return nil end -- absent/unknown optional offer stays unavailable
    local count,ready,usable,spellID
    count,ready,usable,spellID=itemState(id)
    if count==0 then return nil end -- absent optional source cannot become stale readiness
    local class=S.readableCall(function()local _,key=UnitClass("player");return key end)
    local M=S.managedSpells;local entry=class and M and M.entries[class..":"..B.name]
    local key=0
    if item and spellID==item.spellID and count and count>0 and M and M.current(entry) and entry.itemID==id and entry.id==spellID then key=S.compactBindingCode(entry.key)end
    if not item or spellID~=item.spellID then ready=nil;usable=nil end
    local function flag(v)return v==true and 2 or v==false and 1 or 0 end
    -- HHA1: 4 magic + 8 owner + 8 item/use spell + 2 count + four flags +
    -- 2 key + 4 checksum. Source-age/outer-tick ownership is enforced outside.
    local packet="HHA1"..S.bytes(S.setupSession,4)..S.bytes(tick,4)..S.bytes(id,4)..S.bytes(spellID or 0,4)..S.bytes(count and math.min(count,65534)or 65535,2)
        ..S.bytes(flag(ready),1)..S.bytes(flag(usable),1)..S.bytes(flag(B.recentlyBandaged()),1)..S.bytes(S.spellUseCode(B.Key),1)..S.bytes(key,2)
    assert(#packet==28,"bandage packet capacity")
    return packet..S.bytes(S.adler32(packet),4)
end
local events=CreateFrame("Frame");B.events=events
for _,event in ipairs({"BAG_UPDATE_DELAYED","PLAYER_REGEN_ENABLED","PLAYER_ENTERING_WORLD","PLAYER_LEVEL_UP","SKILL_LINES_CHANGED","ITEM_DATA_LOAD_RESULT","GET_ITEM_INFO_RECEIVED"})do pcall(events.RegisterEvent,events,event)end
events:SetScript("OnEvent",function(_,event,id)
    if event=="ITEM_DATA_LOAD_RESULT" or event=="GET_ITEM_INFO_RECEIVED"then
        id=number(id);if not id then return end
        local relevant=B.pending[id]
        if not relevant and B.present[id]then for _,item in ipairs(B.items)do if item.itemID==id then relevant=true;break end end end
        if not relevant then return end
        local C=ns.features.Consumables;if C then C.invalidateBagIndex()end
    end
    if event=="BAG_UPDATE_DELAYED" or event=="PLAYER_ENTERING_WORLD"then local C=ns.features.Consumables;if C then C.invalidateBagIndex()end end
    B.dirty=true -- no inventory, metadata or binding work in the event callback
end)
