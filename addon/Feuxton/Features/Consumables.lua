-- Shared inventory actions. Restricted/unavailable values remain unknown.
local _,ns=...
local C={};ns.features.Consumables=C
C.ids={19013,19012,9421,19011,19010,5510,19009,19008,5509,19007,19006,5511,19005,19004,5512}
-- This is explicit local pause intent, not an observed player posture. The
-- stock /sit and /stand emotes pass these tokens to C_ChatInfo.PerformEmote.
-- A post-hook preserves the game's command and return values unchanged.
C.restPauseRequested=false
function C.observeRestRequest(token)
    if ns.state.isSecret(token) or type(token)~="string" then return end
    token=string.upper(token)
    if token=="SIT" then C.restPauseRequested=true
    elseif token=="STAND" then C.restPauseRequested=false end
end
function C.installRestHook()
    if C.restHookInstalled or type(hooksecurefunc)~="function" or type(C_ChatInfo)~="table" or type(C_ChatInfo.PerformEmote)~="function" then return end
    C.restHookInstalled=pcall(hooksecurefunc,C_ChatInfo,"PerformEmote",C.observeRestRequest)
end
C.installRestHook()
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
-- Rest inventory contains public item facts only. Live ownership, readiness and
-- keys are read again for each completed envelope; cached metadata cannot use an item.
C.rest={dirty=true,bindingsDirty=true,wellFedDirty=true,wellFedDescription="",wellFedDescriptionKnown=false,items={},byID={},pending={},present={},reserved={},revision=0,page=0,complete=false}
C.bagIndex={dirty=true,rows={},facts={}}
local function restText(value,limit)
    return not ns.state.isSecret(value) and type(value)=="string" and #value<=(limit or 512) and value or nil
end
local function restNumber(value,maximum)
    local n=number(value);return n and n<=(maximum or 2147483647) and n or nil
end
function C.invalidateBagIndex()C.bagIndex.dirty=true end
-- Deferred discovery shares only public identity/position and static item
-- facts. Live ownership/count, locks, cooldown and usability are never cached.
function C.bagLocations()
    local S=ns.state;local I=C.bagIndex
    if not I.dirty or S.readableCall(InCombatLockdown)~=false then return I.rows,I.complete end
    I.dirty=false;I.rows={};I.facts={};I.complete=true
    local container=type(C_Container)=="table" and C_Container or {}
    local slots=container.GetContainerNumSlots or GetContainerNumSlots;local info=container.GetContainerItemInfo
    local bags=restNumber(NUM_BAG_SLOTS,8)or restNumber(NUM_TOTAL_EQUIPPED_BAG_SLOTS,8)
    if bags==nil or type(slots)~="function"or type(info)~="function"then I.complete=false;return I.rows,I.complete end
    local visited=0
    for bag=0,bags do
        local count=restNumber(S.readableCall(slots,bag),128)
        if count==nil then I.complete=false
        else for slot=1,count do
            visited=visited+1;if visited>256 then I.complete=false;break end
            local ok,value=pcall(info,bag,slot)
            if not ok or S.isSecret(value)then I.complete=false
            elseif value~=nil then
                local id=restNumber(S.safeField(value,"itemID"))
                if not id or id==0 then I.complete=false else I.rows[#I.rows+1]={bag=bag,slot=slot,itemID=id}end
            end
        end end
        if visited>256 then break end
    end
    return I.rows,I.complete
end
function C.publicItemFacts(id)
    local S=ns.state;local cached=C.bagIndex.facts[id]
    if cached~=nil then return cached or nil end
    local fn=api("GetItemInfo","GetItemInfo");local facts
    if type(fn)=="function"then
        local values={pcall(fn,id)}
        if values[1]==true then
            local classID,subclassID=restNumber(values[13],255),restNumber(values[14],255)
            if classID~=nil and subclassID~=nil then facts={classID=classID,subclassID=subclassID,itemLevel=restNumber(values[5],65534),minLevel=restNumber(values[6],65534),name=restText(values[2],128),itemDescription=restText(values[19])}end
        end
    end
    C.bagIndex.facts[id]=facts or false -- unavailable static facts remain unknown to each consumer
    return facts
end
local function restString(value)
    return value==nil and ns.state.bytes(65535,2) or ns.state.bytes(#value,2)..value
end
function C.restCanonical()
    local S=ns.state;local R=C.rest
    local chunks={"FRM1",restString(R.locale),S.bytes(R.complete and 1 or 0,1),S.bytes(R.wellFedDescriptionKnown and 1 or 0,1),restString(R.wellFedDescription),S.bytes(#R.items,1)}
    for _,item in ipairs(R.items)do
        chunks[#chunks+1]=S.bytes(item.itemID,4)..S.bytes(item.useSpellID or 0,4)..S.bytes(item.minLevel or 65535,2)
            ..restString(item.name)..restString(item.itemDescription)..restString(item.useDescription)..restString(item.tooltipText)
    end
    return table.concat(chunks)
end
local function restField(object,key)
    local S=ns.state
    if S.isSecret(object) or type(object)~="table"then return nil,false end
    local ok,value=pcall(function()return object[key]end)
    if not ok or S.isSecret(value)then return nil,false end
    return value,true
end
local restTimeUnits={s=true,sec=true,secs=true,second=true,seconds=true,m=true,min=true,mins=true,minute=true,minutes=true,
    h=true,hr=true,hrs=true,hour=true,hours=true,d=true,day=true,days=true}
local function restVolatileTooltipLine(value,kind)
    -- Client footers can change on a bag or aura event without changing any
    -- nutrition facts. Keep use text and effect descriptions intact.
    local plain=value:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r",""):match("^%s*(.-)%s*$")
    if plain=="" then return true end
    local countdown
    if kind=="item" then
        countdown=plain:match("^Cooldown remaining:%s+(.+)$")
    elseif kind=="aura" then
        countdown=plain:match("^(.-)%s+remaining$")
    end
    if not countdown then return false end
    local singular,plural=countdown:match("^%d+%s+|4(%a+):(%a+);$")
    if singular then return restTimeUnits[singular:lower()] and restTimeUnits[plural:lower()] end
    local unit=countdown:match("^%d+%s+(%a+)$")
    return unit and restTimeUnits[unit:lower()]
end
local function restTooltipLines(data,kind,locale)
    local S=ns.state;local lines,public=restField(data,"lines")
    if not public then return nil end
    if S.isSecret(lines) or type(lines)~="table"then return nil end
    local english=locale=="enUS" or locale=="enGB"
    local texts={};local size=0
    for i=1,40 do
        local line,public=restField(lines,i)
        if not public then return nil end
        if line==nil then return table.concat(texts,"\n") end
        if type(line)~="table"then return nil end
        for _,field in ipairs({"leftText","rightText"})do
            local value,public=restField(line,field)
            if not public then return nil end
            if value~=nil then
                value=restText(value)
                if value==nil then return nil end
                if not english or not restVolatileTooltipLine(value,kind) then
                    size=size+#value+(#texts>0 and 1 or 0);if size>512 then return nil end
                    texts[#texts+1]=value
                end
            end
        end
    end
    return nil -- an unterminated bounded tooltip is incomplete, never truncated proof
end
local function restTooltip(bag,slot)
    local S=ns.state;local fn=type(C_TooltipInfo)=="table" and C_TooltipInfo.GetBagItem
    return type(fn)=="function" and restTooltipLines(S.readableCall(fn,bag,slot),"item",C.rest.locale)or nil
end
function C.refreshRestCatalog()
    local S=ns.state;local R=C.rest
    if type(S.bytes)~="function"then return end
    local canonical=C.restCanonical()
    if canonical~=R.canonical then
        R.canonical=canonical;R.revision=(R.revision+1)%65536;R.checksum=S.adler32(canonical);R.page=0
        if ns.markSetupDirty then ns.markSetupDirty()end
    end
end
function C.updateWellFedDescription(index)
    local S=ns.state;local R=C.rest
    if not R.wellFedDirty or S.readableCall(InCombatLockdown)~=false then return end
    R.wellFedDirty=false
    local description;local fn=type(C_TooltipInfo)=="table" and C_TooltipInfo.GetUnitAura
    if index and type(fn)=="function"then
        local data=S.readableCall(fn,"player",index,"HELPFUL")
        local lines=restField(data,"lines");local first=restField(lines,1);local name=restField(first,"leftText")
        name=restText(name,128)
        if name and name:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")=="Well Fed"then
            local locale=R.locale or restText(S.readableCall(GetLocale),16)
            description=restTooltipLines(data,"aura",locale)
        end
    end
    R.wellFedDescriptionKnown=description~=nil and description~=""
    R.wellFedDescription=R.wellFedDescriptionKnown and description or ""
    C.refreshRestCatalog()
end
local function restItemInfo(id,bag,slot)
    local S=ns.state;local facts=C.publicItemFacts(id)
    if not facts then return nil end
    if facts.classID~=0 or facts.subclassID~=5 then return false end -- actual food/drink subclass only
    local useSpellID;local spell=api("GetItemSpell","GetItemSpell")
    if type(spell)=="function"then
        local ok,_,value=pcall(spell,id);if ok then useSpellID=restNumber(value);if useSpellID==0 then useSpellID=nil end end
    end
    local descriptionAPI=S.spellAPI and S.spellAPI.GetSpellDescription or GetSpellDescription
    local useDescription=useSpellID and restText(S.readableCall(descriptionAPI,useSpellID)) or nil
    return {itemID=id,useSpellID=useSpellID,minLevel=facts.minLevel,name=facts.name,
        itemDescription=facts.itemDescription,useDescription=useDescription,tooltipText=restTooltip(bag,slot)}
end
function C.scanRestInventory()
    local S=ns.state;local R=C.rest
    if not R.dirty or S.readableCall(InCombatLockdown)~=false or type(S.bytes)~="function"then return end
    R.dirty=false;R.complete=true;R.locale=restText(S.readableCall(GetLocale),16)
    R.pending={};R.present={}
    for _,item in ipairs(R.items)do item.locations={}end
    local locations,complete=C.bagLocations();R.complete=complete==true
    for _,location in ipairs(locations)do
        local id=location.itemID;R.present[id]=true
        local facts=restItemInfo(id,location.bag,location.slot)
        if facts==nil then R.complete=false;R.pending[id]=true
        elseif facts then
            local item=R.byID[id]
            if not item and #R.items<8 then item={itemID=id};R.byID[id]=item;R.items[#R.items+1]=item;R.bindingsDirty=true end
            if not item then R.complete=false
            else
                if item.useSpellID~=facts.useSpellID then R.bindingsDirty=true end
                for _,field in ipairs({"useSpellID","minLevel","name","itemDescription","useDescription","tooltipText"})do item[field]=facts[field]end
                item.locations=item.locations or {};item.locations[#item.locations+1]={bag=location.bag,slot=location.slot}
            end
        end
    end
    table.sort(R.items,function(a,b)return a.itemID<b.itemID end)
    C.refreshRestCatalog()
end
function C.restMetadata()
    C.scanRestInventory()
    local S=ns.state;local R=C.rest;local rows={}
    for _,item in ipairs(R.items)do
        rows[#rows+1]=S.jsonObject({itemID=item.itemID,useSpellID=item.useSpellID,minLevel=item.minLevel,name=item.name,
            itemDescription=item.itemDescription,useDescription=item.useDescription,tooltipText=item.tooltipText})
    end
    local canonical=R.canonical or C.restCanonical()
    return '{"version":1,"revision":'..S.jsonValue(R.revision)..',"checksum":'..S.jsonValue(R.checksum or S.adler32(canonical))
        ..',"locale":'..S.jsonValue(R.locale)..',"complete":'..S.jsonValue(R.complete)..',"wellFedDescriptionKnown":'..S.jsonValue(R.wellFedDescriptionKnown)..',"wellFedDescription":'..S.jsonValue(R.wellFedDescription)..',"items":['..table.concat(rows,",")..']}'
end
-- Keep recovery keys separate from the spell and recipient pools. Use
-- standard function keys that the game can receive from Windows input.
local restKeys={}
for n=1,12 do
    if n~=10 then restKeys[#restKeys+1]="SHIFT-F"..n end -- Windows context menu
end
for n=1,11 do
    if n~=4 then restKeys[#restKeys+1]="CTRL-F"..n end -- Close document
end

local function restBindingCurrent(entry)
    local S=ns.state
    return entry and entry.key and not ns.keyPolicy.reason(entry.key) and S.compactBindingCode(entry.key)>0
        and S.readableCall(GetBindingAction,entry.key,false)=="" and S.readableCall(GetBindingAction,entry.key,true)==entry.action
end
function C.refreshRestBindings()
    local S=ns.state;local R=C.rest
    if S.readableCall(InCombatLockdown)~=false then return end
    C.scanRestInventory()
    if not R.bindingsDirty or not S.managedSpells or not S.managedSpells.available()then return end
    R.bindingsDirty=false
    if not R.owner then R.owner=CreateFrame("Frame",nil,UIParent)end
    R.stand=R.stand or {stand=true}
    local entries={R.stand};for _,item in ipairs(R.items)do entries[#entries+1]=item end
    local cleared=pcall(ClearOverrideBindings,R.owner)
    for _,entry in ipairs(entries)do
        local previous=entry.key;entry.key=nil
        entry.buttonName=entry.stand and "FeuxtonRestStand" or "FeuxtonRestItem"..entry.itemID
        entry.action="CLICK "..entry.buttonName..":LeftButton"
        if not entry.button then
            entry.button=CreateFrame("Button",entry.buttonName,UIParent,"SecureActionButtonTemplate")
            entry.button:SetSize(1,1);entry.button:SetPoint("TOPLEFT",UIParent,"TOPLEFT",-10000,10000);entry.button:SetAlpha(0)
            entry.button:RegisterForClicks("AnyDown","AnyUp");entry.button:SetAttribute("useOnKeyDown",true)
            entry.button:SetAttribute("checkselfcast",false);entry.button:SetAttribute("checkfocuscast",false);entry.button:SetAttribute("checkmouseovercast",false)
            entry.button:SetAttribute("unit","player")
            entry.button:SetAttribute("macrotext",entry.stand and "/stand" or nil)
            entry.button:SetAttribute("item",entry.itemID and "item:"..entry.itemID or nil)
        end
        entry.button:SetAttribute("type",nil)
        local function bind(key)
            if not cleared or ns.keyPolicy.reason(key) or S.compactBindingCode(key)==0
                or S.readableCall(GetBindingAction,key,false)~="" or S.readableCall(GetBindingAction,key,true)~=""then return false end
            R.reserved[key]=entry.itemID or "stand"
            local ok=pcall(SetOverrideBindingClick,R.owner,false,key,entry.buttonName,"LeftButton")
            if ok and S.readableCall(GetBindingAction,key,true)==entry.action then entry.key=key;return true end
            return false
        end
        if previous then bind(previous)end
        if not entry.key then
            for _,key in ipairs(restKeys)do
                if not R.reserved[key] and bind(key)then break end
            end
        end
        entry.button:SetAttribute("type",entry.key and (entry.stand and "macro" or "item") or nil)
    end
end
local function restLocked(item)
    local S=ns.state;local fn=type(C_Container)=="table"and C_Container.GetContainerItemInfo
    if type(fn)~="function"then return nil end
    local any,complete=false,true
    for _,location in ipairs(item.locations or {})do
        local value=S.readableCall(fn,location.bag,location.slot)
        local id=restNumber(S.safeField(value,"itemID"));local locked=S.safeField(value,"isLocked")
        if id~=item.itemID or S.isSecret(locked) or type(locked)~="boolean"then complete=false
        else any=true;if not locked then return false end end
    end
    return any and complete and true or nil
end
-- Scan to a confirmed end before reporting absence. Hidden names and a full
-- bounded scan stay unknown; Well Fed is not an active eating effect.
function C.recovery()
    local S=ns.state;local A=type(C_UnitAuras)=="table" and C_UnitAuras or {}
    local campfireName="Welcoming Campfire";local campfire
    if type(A.GetAuraDataBySpellName)=="function" then
        local ok,a=pcall(A.GetAuraDataBySpellName,"player",campfireName,"HELPFUL")
        if ok and not S.isSecret(a) then
            if a==nil then campfire=false
            elseif type(a)=="table" and S.safeField(a,"name")==campfireName then campfire=true end
        end
    end
    if type(A.GetAuraDataByIndex)~="function" then C.updateWellFedDescription(nil);return nil,nil,campfire,nil end
    local eating,drinking,wellFed,complete=false,false,false,true
    local campfireFound=false;local wellFedIndex
    local function result(ended)
        C.updateWellFedDescription(wellFedIndex)
        local fire=campfire
        -- A later exact readable presence wins over an earlier targeted nil.
        if campfireFound then fire=true elseif fire==nil and ended and complete then fire=false end
        if ended and complete then return eating,drinking,fire,wellFed end
        return eating and true or nil,drinking and true or nil,fire,wellFed and true or nil
    end
    for i=1,80 do
        local ok,a=pcall(A.GetAuraDataByIndex,"player",i,"HELPFUL")
        if not ok or S.isSecret(a) then complete=false
        elseif a==nil then
            return result(true)
        else
            local name=S.safeField(a,"name")
            if type(name)~="string" then complete=false
            elseif name=="Food" or name==FOOD then eating=true
            elseif name=="Drink" or name==DRINK then drinking=true
            elseif name=="Food & Drink" or name=="Refreshment" then eating=true;drinking=true
            elseif name==campfireName then campfireFound=true
            elseif name=="Well Fed" then wellFed=true;wellFedIndex=wellFedIndex or i end
        end
    end
    return result(false)
end
function C.itemState(id)
    local S=ns.state;local ready,usable,spellID
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
    return ready,usable,spellID
end
-- Inventory events can arrive in large bursts while loot/bag tooltips load.
-- Only a changed Healthstone identity needs the full managed spell discovery;
-- queue it on the existing setup scheduler instead of rebuilding inside events.
function C.queueInventoryBindings()
    local S=ns.state
    if S.readableCall(InCombatLockdown)~=false then return end
    local id,count=C.inventory()
    if id==0 and count==0 then C.bindingItemID=nil;return end
    if not id or id==0 or C.bindingItemID==id then return end
    C.bindingItemID=id
    local class=S.readableCall(function()local _,key=UnitClass("player");return key end)
    local M=S.managedSpells
    local entry=type(class)=="string" and M and M.entries[class..":Feuxton Healthstone"]
    if (not entry or entry.itemID~=id) and ns.markSetupDirty then ns.markSetupDirty()end
end
local function restFlag(value)return value==true and 2 or value==false and 1 or 0 end
function C.restExtension(tick,wellFed)
    local S=ns.state;local R=C.rest
    C.scanRestInventory();C.refreshRestBindings();C.queueInventoryBindings()
    local pages=math.max(1,math.ceil(#R.items/2));local page=tick%pages
    local first=page*2+1;local count=math.min(2,math.max(0,#R.items-first+1));local kind=0
    local ok,inside,instance=pcall(IsInInstance)
    if ok and not S.isSecret(inside) and type(inside)=="boolean"then
        if not inside then kind=1
        elseif not S.isSecret(instance) and type(instance)=="string"and instance~=""then kind=instance=="party" and 2 or instance=="raid" and 3 or 4 end
    end
    local canonical=R.canonical or C.restCanonical()
    local stand=restBindingCurrent(R.stand) and S.compactBindingCode(R.stand.key)or 0
    local packet=S.bytes(R.revision,2)..S.bytes(R.checksum or S.adler32(canonical),4)..S.bytes(page,1)..S.bytes(pages,1)..S.bytes(count,1)..S.bytes(restFlag(wellFed),1)..S.bytes(stand,2)..S.bytes(kind,1)
    for i=first,first+count-1 do
        local item=R.items[i];local owned=number(S.readableCall(api("GetItemCount","GetItemCount"),item.itemID,false,false,false,false))
        local ready,usable,spellID=C.itemState(item.itemID);local locked=restLocked(item)
        local binding=restBindingCurrent(item) and item.useSpellID and spellID==item.useSpellID and S.compactBindingCode(item.key)or 0
        if not item.useSpellID or spellID~=item.useSpellID then ready=nil;usable=nil end
        local flags=restFlag(ready)+restFlag(usable)*4+restFlag(locked)*16
        packet=packet..S.bytes(item.itemID,4)..S.bytes(owned and math.min(owned,65534)or 65535,2)..S.bytes(binding,2)..S.bytes(flags,1)
    end
    assert(#packet==13+count*9,"rest offer capacity")
    return packet
end
function C.packet(tick)
    local S=ns.state;local id,count=C.inventory();local ready,usable,spellID=C.itemState(id)
    local class=S.readableCall(function()local _,key=UnitClass("player");return key end)
    local M=S.managedSpells;local entry=M and M.entries[class..":Feuxton Healthstone"]
    local key=M and M.current(entry) and entry.itemID==id and S.compactBindingCode(entry.key) or 0
    local function flag(v)return v==true and 2 or v==false and 1 or 0 end
    local eating,drinking,campfire,wellFed=C.recovery()
    -- HHI4 never carries a previous campfire presence into an unknown read.
    -- Bits 2..3 reserve a tri-state sitting observation. It remains unknown
    -- until a real client query is verified; bit 4 is separate local intent.
    local recoveryState=flag(campfire)+(C.restPauseRequested and 16 or 0)
    -- A corpse is not a ghost. Query the explicit public API each completed
    -- batch; missing, restricted and invalid results remain unknown.
    local ghost=flag(S.readableCall(UnitIsGhost,"player"))
    local packet="HHI6"..S.bytes(S.setupSession,4)..S.bytes(tick,4)..S.bytes(id,4)..S.bytes(spellID or 0,4)..S.bytes(count and math.min(count,65534) or 65535,2)..S.bytes(flag(ready),1)..S.bytes(flag(usable),1)..S.bytes(S.spellUseCode("shared.healthstone"),1)..S.bytes(key,2)..S.bytes(flag(eating),1)..S.bytes(flag(drinking),1)..S.bytes(recoveryState,1)..S.bytes(ghost,1)..C.restExtension(tick,wellFed)
    assert(#packet+4<=66,"rest inventory packet capacity")
    return packet..S.bytes(S.adler32(packet),4)
end
local events=CreateFrame("Frame");C.events=events
events:RegisterEvent("BAG_UPDATE_DELAYED");events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_STARTED_MOVING");events:RegisterEvent("PLAYER_ENTERING_WORLD")
for _,event in ipairs({"ITEM_DATA_LOAD_RESULT","GET_ITEM_INFO_RECEIVED","UPDATE_BINDINGS","UNIT_AURA","PLAYER_LEVEL_UP"})do pcall(events.RegisterEvent,events,event)end
events:SetScript("OnEvent",function(_,event,unit)
    local S=ns.state;local R=C.rest
    if event=="UNIT_AURA"then
        if not S.isSecret(unit) and unit=="player"then R.wellFedDirty=true end
        return
    end
    if event=="PLAYER_STARTED_MOVING" then C.restPauseRequested=false;return end
    if event=="ITEM_DATA_LOAD_RESULT" or event=="GET_ITEM_INFO_RECEIVED" then
        local id=restNumber(unit)
        -- Other addons request item data when opening bags, loot and vendors.
        -- Their unrelated completions must not scan our bags or rebuild keys.
        if not id or not (R.pending[id] or R.byID[id] and R.present[id])then return end
        C.invalidateBagIndex();R.dirty=true;return
    end
    if event=="UPDATE_BINDINGS"then R.bindingsDirty=true;return end
    if event=="PLAYER_ENTERING_WORLD"then
        C.installRestHook();C.bindingItemID=nil;R.bindingsDirty=true
    end
    if event=="BAG_UPDATE_DELAYED" or event=="PLAYER_ENTERING_WORLD"then C.invalidateBagIndex()end
    C.scannedAt=nil;R.dirty=true
    if event~="BAG_UPDATE_DELAYED"then R.wellFedDirty=true end
    -- The coordinated consumable producer coalesces pending inventory work.
    -- Live item counts, cooldowns, locks and effective key readbacks are still
    -- queried directly for each offer; count-only changes do not change keys.
end)
