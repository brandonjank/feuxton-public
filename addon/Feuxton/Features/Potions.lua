-- Shared instant healing/mana items. The bag index owns only public discovery;
-- every offer rechecks live ownership, use-spell identity and readiness.
local _,ns=...
local P={dirty=true,items={},pending={},present={},known={},selected={},emptySince={}}
ns.features.Potions=P
P.keys={"shared.healingPotion","shared.manaPotion"}
P.names={"Feuxton Healing Potion","Feuxton Mana Potion"}
local function number(v,maximum)
    return not ns.state.isSecret(v) and type(v)=="number" and v>=0 and v==math.floor(v) and v<=(maximum or 2147483647) and v or nil
end
local function text(v,maximum)
    return not ns.state.isSecret(v) and type(v)=="string" and #v<=(maximum or 2048) and v or nil
end
local function api(name,legacy)return type(C_Item)=="table" and C_Item[name] or _G[legacy]end
local function live(id)
    local S=ns.state;local C=ns.features.Consumables
    local count=number(S.readableCall(api("GetItemCount","GetItemCount"),id,false,false,false,false))
    local ready,usable,spellID=C.itemState(id)
    return count,ready,usable,spellID
end
local function amount(value)local cleaned=(value or ""):gsub(",","");local n=number(tonumber(cleaned),1000000000);return n and n>0 and n or nil end
local function resource(description,name,prefix)
    local minimum,maximum
    local function add(low,high)
        low=amount(low);high=amount(high)
        if not low or not high or high<low or minimum and (minimum~=low or maximum~=high)then return false end
        minimum,maximum=low,high;return true
    end
    for low,high in description:gmatch(prefix.."%s+([%d,]+)%s+to%s+([%d,]+)%s+"..name.."%f[%A]")do if not add(low,high)then return nil end end
    for value in description:gmatch(prefix.."%s+([%d,]+)%s+"..name.."%f[%A]")do if not add(value,value)then return nil end end
    return minimum and {minimum=minimum,maximum=maximum}or nil
end
function P.parse(description)
    description=text(description);if not description then return nil end
    description=description:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r",""):lower()
    -- Sleep and periodic-restoration potions need separate activity policies.
    -- Do not turn an arbitrary potion into an instant emergency item.
    if description:find("over%s+[%d,]+%s+sec") or description:find("every%s+[%d,]+%s+sec") or description:find("per%s+[%d,]+%s+sec") or description:find("sleep",1,true) or description:find("deals?%s+[%d,]+")then return nil end
    local healing,mana=resource(description,"health","%f[%a]restores?"),resource(description,"mana","%f[%a]restores?")
    if healing and not mana then mana=resource(description,"mana","%f[%a]and")end
    if mana and not healing then healing=resource(description,"health","%f[%a]and")end
    return (healing or mana)and {healing=healing,mana=mana}or nil
end
local function tooltip(bag,slot)
    local S=ns.state;local fn=type(C_TooltipInfo)=="table" and C_TooltipInfo.GetBagItem
    local function field(object,key)
        if S.isSecret(object) or type(object)~="table"then return nil,false end
        local ok,value=pcall(function()return object[key]end)
        if not ok or S.isSecret(value)then return nil,false end
        return value,true
    end
    local object=S.readableCall(fn,bag,slot);local lines,public=field(object,"lines")
    if not public then return nil end
    if type(lines)~="table"then return nil end
    local result={};local size=0
    for index=1,40 do
        local line,public=field(lines,index);if not public then return nil end
        if line==nil then return table.concat(result,"\n")end
        for _,key in ipairs({"leftText","rightText"})do
            local value,public=field(line,key);if not public then return nil end
            if value~=nil then value=text(value,512);if not value then return nil end;size=size+#value+1;if size>2048 then return nil end;result[#result+1]=value end
        end
    end
    return nil
end
local function facts(id,bag,slot,english)
    local S=ns.state;local C=ns.features.Consumables;local public=C.publicItemFacts(id)
    if not public then return nil end
    local enums=type(Enum)=="table" and Enum.ItemConsumableSubclass
    local potion=type(enums)=="table" and number(enums.Potion,255)or nil
    if public.classID~=0 or public.subclassID~=(potion or 1)then return false end
    P.known[id]=true
    if not english then return nil end
    local _,_,_,spellID=live(id);if not spellID or spellID<=0 then return nil end
    local description=text(S.readableCall(S.spellAPI and S.spellAPI.GetSpellDescription or GetSpellDescription,spellID))
    local restoration=P.parse(description or public.itemDescription or tooltip(bag,slot))
    if not restoration then return nil end
    return {itemID=id,spellID=spellID,minLevel=public.minLevel,itemLevel=public.itemLevel,healing=restoration.healing,mana=restoration.mana}
end
function P.scan()
    local S=ns.state;local C=ns.features.Consumables
    if not P.dirty or S.readableCall(InCombatLockdown)~=false or not C then return end
    P.dirty=false;P.pending={};P.present={};P.known={};P.items={}
    local locale=S.readableCall(GetLocale);local english=locale=="enUS" or locale=="enGB"
    local locations=C.bagLocations()
    for _,location in ipairs(locations)do
        local id=location.itemID
        if not P.present[id]then
            P.present[id]=true;local item=facts(id,location.bag,location.slot,english)
            if item==nil then P.pending[id]=true
            elseif item and #P.items<32 then P.items[#P.items+1]=item end
        end
    end
end
local function effect(item,kind)if kind==1 then return item.healing end;return item.mana end
local function better(a,b,kind)
    if not b then return true end
    local x,y=effect(a,kind),effect(b,kind)
    local average=x.minimum+x.maximum;local previous=y.minimum+y.maximum
    if average~=previous then return average>previous end
    if x.minimum~=y.minimum then return x.minimum>y.minimum end
    return a.itemID<b.itemID
end
local function selectItem(kind,now)
    local S=ns.state;local old=P.selected[kind]
    if S.readableCall(InCombatLockdown)~=false then
        if old then
            local count,ready,usable,spellID=live(old.itemID)
            if count==0 and now then
                P.emptySince[kind]=P.emptySince[kind]or now
                if now<P.emptySince[kind] or now-P.emptySince[kind]>1 then P.selected[kind]=nil;return nil end
            elseif count and count>0 then P.emptySince[kind]=nil end
            return old,count,ready,usable,spellID
        end
        return nil
    end
    local level=number(S.readableCall(UnitLevel,"player"),255);local selected,bestCount,bestReady,bestUsable,bestSpellID
    for _,item in ipairs(P.items)do
        local restoration=effect(item,kind)
        if restoration and level and item.minLevel and item.minLevel<=level then
            local count,ready,usable,spellID=live(item.itemID)
            if count and count>0 and usable==true and spellID==item.spellID and better(item,selected,kind)then selected=item;bestCount,bestReady,bestUsable,bestSpellID=count,ready,usable,spellID end
        end
    end
    if selected then P.emptySince[kind]=nil
    elseif old then
        local count,ready,usable,spellID=live(old.itemID)
        if count==0 and now then
            P.emptySince[kind]=P.emptySince[kind]or now
            if now>=P.emptySince[kind] and now-P.emptySince[kind]<=1 then selected=old end
        elseif spellID==old.spellID then
            for _,item in ipairs(P.items)do if item.itemID==old.itemID and item.spellID==old.spellID and effect(item,kind)then selected=item;P.emptySince[kind]=nil;break end end
        end
        if selected then bestCount,bestReady,bestUsable,bestSpellID=count,ready,usable,spellID end
    end
    P.selected[kind]=selected
    if selected and (not old or old.itemID~=selected.itemID or old.spellID~=selected.spellID)and ns.markSetupDirty then ns.markSetupDirty()end
    return selected,bestCount,bestReady,bestUsable,bestSpellID
end
local function clock(now)
    if now==nil then now=ns.state.readableCall(GetTime)end
    return not ns.state.isSecret(now) and type(now)=="number" and now==now and now>=0 and now<math.huge and now or nil
end
function P.candidates()
    P.scan();local result={};local now=clock()
    for kind=1,2 do
        local item=selectItem(kind,now)
        if item then result[#result+1]={id=item.spellID,itemID=item.itemID,name=P.names[kind],abilityKey=P.keys[kind],unit="player"}end
    end
    return result
end
function P.packet(now,tick)
    local S=ns.state;now=clock(now);if not now then return nil end
    P.scan();local rows={};local mask=0
    local class=S.readableCall(function()local _,key=UnitClass("player");return key end);local M=S.managedSpells
    local function flag(v)return v==true and 2 or v==false and 1 or 0 end
    for kind=1,2 do
        local item,count,ready,usable,spellID=selectItem(kind,now)
        if item then
            local entry=class and M and M.entries[class..":"..P.names[kind]];local binding=0
            if count and count>0 and spellID==item.spellID and M and M.current(entry) and entry.itemID==item.itemID and entry.id==spellID then binding=S.compactBindingCode(entry.key)end
            if spellID~=item.spellID then ready=nil;usable=nil end
            mask=mask+2^(kind-1)
            rows[#rows+1]=S.bytes(item.itemID,4)..S.bytes(spellID or 0,4)..S.bytes(count and math.min(count,65534)or 65535,2)..S.bytes(flag(ready)+4*flag(usable)+16*S.spellUseCode(P.keys[kind]),1)..S.bytes(binding,2)
        end
    end
    if mask==0 then return nil end
    local packet="HHQ1"..S.bytes(S.setupSession,4)..S.bytes(tick,4)..S.bytes(mask,1)..table.concat(rows)
    assert(#packet==26 or #packet==39,"potion packet capacity")
    return packet..S.bytes(S.adler32(packet),4)
end
local events=CreateFrame("Frame");P.events=events
for _,event in ipairs({"BAG_UPDATE_DELAYED","PLAYER_REGEN_ENABLED","PLAYER_ENTERING_WORLD","PLAYER_LEVEL_UP","SKILL_LINES_CHANGED","ITEM_DATA_LOAD_RESULT","GET_ITEM_INFO_RECEIVED"})do pcall(events.RegisterEvent,events,event)end
events:SetScript("OnEvent",function(_,event,id)
    local C=ns.features.Consumables
    if event=="ITEM_DATA_LOAD_RESULT" or event=="GET_ITEM_INFO_RECEIVED"then
        id=number(id);if not id or not(P.pending[id]or P.present[id]and P.known[id])then return end
        if C then C.invalidateBagIndex()end
    end
    if C and (event=="BAG_UPDATE_DELAYED"or event=="PLAYER_ENTERING_WORLD")then C.invalidateBagIndex()end
    P.dirty=true -- no API scans, static parsing or secure binding writes in callbacks
end)
