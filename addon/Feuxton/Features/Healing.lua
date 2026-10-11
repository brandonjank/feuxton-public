-- Shared friendly-action delivery. Secure buttons are clicked by hardware keys;
-- ordinary Lua only configures them outside combat and reports public evidence.
local _, ns = ...
local F={cache={},revision=0}
ns.features.Healing=F
F.actions={{key="paladin.blessingMight",name="Blessing of Might"},{key="paladin.blessingWisdom",name="Blessing of Wisdom"},{key="paladin.blessingKings",name="Blessing of Kings"}}
F.heal={key="paladin.holyLight",name="Holy Light",healing=true}
function F.deliverySpecs()
    local specs={F.actions[1],F.actions[2],F.heal}
    if not F.shaman then specs[4]=F.actions[3] end
    return specs
end
F.layHands={key="paladin.layHands",name="Lay on Hands",healing=true}
F.cancelFury={key="paladin.cancelRighteousFury",name="Righteous Fury",cancel=true}
function F.key(code)
 local bank=code>=33 and 2 or 1;local i=code-(bank==2 and 32 or 0)
 if i<1 or i>31 then return nil end
 local punctuation={"-","=","[","]",";","'",",",".","/"}
 return (bank==1 and "ALT-CTRL-" or "CTRL-SHIFT-")..(i<=12 and "F"..i or i<=22 and tostring(i-13) or punctuation[i-22])
end
local meleeSpecs={[71]=true,[72]=true,[73]=true,[259]=true,[260]=true,[261]=true,[66]=true,[70]=true,[263]=true,[103]=true,[104]=true,[250]=true,[251]=true,[252]=true,[268]=true,[269]=true}
local function numeric(value) return value and value.status=="observed" and type(value.value)=="number" and value.value>0 and value.value<2147483648 and value.value==math.floor(value.value) and value.value or nil end
local function timeNow() local v=ns.features.GroupContext.read(GetTime,1);return v.status=="observed" and type(v.value)=="number" and v.value>=0 and v.value or nil end
local function publicTrace(value)
    if ns.state.isSecret(value) then return {status="restricted"} end
    local kind=type(value)
    if kind=="string" then return {status="observed",value=string.sub(value,1,80)} end
    if kind=="number" or kind=="boolean" then return {status="observed",value=value} end
    return {status=kind=="nil" and "absent" or "unavailable"}
end
local function trace(event,unit,a,b,c)
    if type(FeuxtonDB)~="table" then return end
    local list=FeuxtonDB.managedHealTrace or {};FeuxtonDB.managedHealTrace=list
    list[#list+1]={event=event,unit=publicTrace(unit),a=publicTrace(a),b=publicTrace(b),c=publicTrace(c),at=timeNow()}
    if #list>12 then table.remove(list,1) end
end
function F.melee(unit,class,role)
    local G=ns.features.GroupContext
    if role=="HEALER" then return {status="observed",value=false} end
    if class=="WARRIOR" or class=="ROGUE" then return {status="observed",value=true} end
    if role=="TANK" and (class=="PALADIN" or class=="DRUID" or class=="WARRIOR" or class=="DEATHKNIGHT" or class=="MONK") then return {status="observed",value=true} end
    local spec
    if unit=="player" then local index=numeric(G.read(GetSpecialization,1));if index then spec=numeric(G.read(GetSpecializationInfo,1,index)) end
    else spec=numeric(G.read(GetInspectSpecialization,1,unit)) end -- only already available inspection data
    if spec then return {status="observed",value=meleeSpecs[spec]==true} end
    if class=="HUNTER" or class=="MAGE" or class=="WARLOCK" or class=="PRIEST" then return {status="observed",value=false} end
    return {} -- ambiguous hybrid: desktop chooses Wisdom, without inventing a spec
end
local function blessing(name)
    if name=="Blessing of Might" or name=="Greater Blessing of Might" then return 1 end
    if name=="Blessing of Wisdom" or name=="Greater Blessing of Wisdom" then return 2 end
    if name=="Blessing of Kings" or name=="Greater Blessing of Kings" then return 3 end
end
function F.scan(unit,identity,now)
    local G=ns.features.GroupContext;local S=ns.state
    if S.readableCall(InCombatLockdown)~=false then return {{},{},{}} end
    local cached=F.cache[unit]
    if cached and cached.identity==identity and now-cached.at>=0 and now-cached.at<.25 then return cached.values,cached.at end
    local values={{},{},{}};local complete=false
    local api=type(C_UnitAuras)=="table" and C_UnitAuras or {}
    if type(api.GetAuraDataByIndex)=="function" then
        for i=1,80 do
            local ok,aura=pcall(api.GetAuraDataByIndex,unit,i,"HELPFUL")
            if not ok or S.isSecret(aura) then break end
            if aura==nil then complete=true;break end
            local name=G.text(G.field(aura,"name"),80);if name=="" then break end
            local index=blessing(name)
            if index then
                values[index].present={status="observed",value=true}
                local source=G.text(G.field(aura,"sourceUnit"),16)
                local owns=source~="" and G.read(UnitIsUnit,1,source,"player") or {}
                if owns.status=="observed" then
                    if owns.value==true then values[index].own={status="observed",value=true}
                    elseif owns.value==false then values[index].other={status="observed",value=true} end
                else values[index].unknownOwner=true end
            end
        end
    end
    for _,aura in ipairs(values) do
        if complete and not aura.present then aura.present={status="observed",value=false} end
        if complete and aura.present and aura.present.value==false then aura.own={status="observed",value=false};aura.other={status="observed",value=false}
        elseif complete and not aura.unknownOwner and (aura.own or aura.other) then
            aura.own=aura.own or {status="observed",value=false};aura.other=aura.other or {status="observed",value=false}
        end
    end
    F.cache[unit]={identity=identity,at=now,values=values};return values,now
end
function F.track(button,spec,down)
    if not (spec.healing or spec.support) or down~=true or not F.receiptsAvailable then return end
    local G=ns.features.GroupContext
    local selected=spec.directSelf and "player" or "target"
    local guid=G.text(G.read(UnitGUID,1,selected),40)
    for member,unit in ipairs(G.tokens) do
        if G.read(UnitIsUnit,1,selected,unit).value==true and G.text(G.read(UnitGUID,1,unit),40)~="" and G.read(UnitCanAssist,1,"player",unit).value==true and G.read(UnitIsDeadOrGhost,1,unit).value==false then
            guid=G.text(G.read(UnitGUID,1,unit),40)
            local name,now=G.fullName(unit,64),timeNow()
            if name~="" and now and button.hhSpellID then
                F.sequence=((F.sequence or 0)+1)%4294967296
                F.attempt={sequence=F.sequence,revision=F.revision,index=member,unit=unit,identity=guid,name=name,id=button.hhSpellID,at=now,kind=0}
                trace("MANAGED_CLICK",unit,guid,name,button.hhSpellID)
            end
            return
        end
    end
end
function F.delivery(spec)
    local S=ns.state;local class=S.readableCall(function() local _,key=UnitClass("player");return key end)
    local e=S.managedSpells and S.managedSpells.entries[class..":"..spec.name]
    return S.bindingsValid and S.managedSpells.current(e) and e.unit=="target" and e.friendly and (not (spec.healing or spec.support) or F.receiptsAvailable) and e or nil
end
function F.initialize()
    if F.events then return end
    -- SENT supplies the recipient name and cast GUID. Later terminal events
    -- must match that GUID, not merely Holy Light's spell ID or enemy target.
    F.events=CreateFrame("Frame",nil,UIParent)
    F.receiptsAvailable=true
    for _,event in ipairs({"UNIT_SPELLCAST_SENT","UNIT_SPELLCAST_START","UNIT_SPELLCAST_SUCCEEDED","UNIT_SPELLCAST_FAILED","UNIT_SPELLCAST_INTERRUPTED"}) do
        if not pcall(F.events.RegisterEvent,F.events,event) then F.receiptsAvailable=false end
    end
    F.events:SetScript("OnEvent",function(self,event,unit,a,b,c)
        local G=ns.features.GroupContext;local now=timeNow();local r=F.attempt
        if r then trace(event,unit,a,b,c) end
        if not r or not now or now-r.at<0 or now-r.at>10 or ns.state.isSecret(unit) or unit~="player" then return end
        if event=="UNIT_SPELLCAST_SENT" then
            if r.kind~=0 then return end
            if ns.state.isSecret(a) or ns.state.isSecret(b) or ns.state.isSecret(c) then return end
            if now-r.at<=.75 and a==r.name and type(b)=="string" and b~="" and c==r.id and G.text(G.read(UnitGUID,1,r.unit),40)==r.identity then r.cast=b;r.kind=1 end
        elseif (event=="UNIT_SPELLCAST_FAILED" or event=="UNIT_SPELLCAST_INTERRUPTED") and not ns.state.isSecret(b) and b==r.id and r.kind==0 and now-r.at<=.75 then
            -- Rejected keypresses may fail before SENT supplies a cast GUID.
            -- This is only a negative result for the immediate managed attempt.
            r.kind=event=="UNIT_SPELLCAST_FAILED" and 3 or 4;r.eventAt=now
        elseif (event=="UNIT_SPELLCAST_SUCCEEDED" or event=="UNIT_SPELLCAST_FAILED" or event=="UNIT_SPELLCAST_INTERRUPTED") and not ns.state.isSecret(a) and not ns.state.isSecret(b) and r.cast and a==r.cast and b==r.id then
            r.kind=event=="UNIT_SPELLCAST_SUCCEEDED" and 2 or event=="UNIT_SPELLCAST_FAILED" and 3 or 4;r.eventAt=now
        end
    end)
end
function F.refresh(now)
    local G=ns.features.GroupContext;local S=ns.state
    if S.readableCall(InCombatLockdown)~=false or type(now)~="number" then return end
    local class=G.text(G.read(UnitClass,2,"player"),16)
    if class~="PALADIN" and class~="SHAMAN" then return end
    if class=="SHAMAN" and not F.shaman then
        F.shaman=true
        F.actions={{key="shaman.healingWave",name="Healing Wave",healing=true},{key="shaman.lesserHealingWave",name="Lesser Healing Wave",healing=true}}
        F.heal={key="shaman.riptide",name="Riptide",healing=true}
    end
    F.initialize();ns.features.RecipientTargeting.refresh()
    local signature={tostring(ns.features.RecipientTargeting.revision)}
    for _,spec in ipairs(F.deliverySpecs()) do local e=F.delivery(spec);signature[#signature+1]=e and e.id..":"..e.key or "" end
    if class=="PALADIN" and ns.features.ControlEffects then local e=F.delivery(ns.features.ControlEffects.freedom);signature[#signature+1]=e and e.id..":"..e.key or "" end
    local value=table.concat(signature,"|")
    if value~=F.signature then F.signature=value;F.revision=(F.revision+1)%4294967296 end
end
function F.spell(spec,unit)
    local G=ns.features.GroupContext;local S=ns.state;local api=type(C_Spell)=="table" and C_Spell or {};local book=type(C_SpellBook)=="table" and C_SpellBook or {}
    local cached=F.spellStatus and F.spellStatus[spec.key]
    if cached then cached.range=cached.id>0 and G.read(api.IsSpellInRange or IsSpellInRange,1,api.IsSpellInRange and cached.id or spec.name,unit) or {};return cached end
    local ok,info=pcall(api.GetSpellInfo or function() end,spec.name);local id=ok and numeric(G.field(info,"spellID")) or nil
    for _,known in ipairs(S.setupKnownSpells or {}) do
        if known.name==spec.name and type(known.id)=="number" and (not id or known.id>id) and G.read(book.IsSpellKnown or IsSpellKnown,1,known.id).value==true then id=known.id end
    end
    if spec.healing and S.bindingsValid then
        local chosen
        for _,mapping in ipairs(S.setupMappings or {}) do
            if mapping.name==spec.name and mapping.key and (not chosen or chosen.kind~="spell" and mapping.kind=="spell") then chosen=mapping end
        end
        if chosen and type(chosen.id)=="number" and chosen.id>0 then id=chosen.id end
    end
    local result={id=id or 0,learned={},usable={},mana={},range={},ready={}}
    if id then
        result.learned=G.read(book.IsSpellKnown or IsSpellKnown,1,id);result.usable=G.read(api.IsSpellUsable or IsUsableSpell,1,id);result.mana=G.read(api.IsSpellUsable or IsUsableSpell,2,id)
        result.range=G.read(api.IsSpellInRange or IsSpellInRange,1,api.IsSpellInRange and id or spec.name,unit)
        local cdOK,cd=pcall(api.GetSpellCooldown or function() end,id)
        if cdOK then
            local start,duration,enabled=G.field(cd,"startTime"),G.field(cd,"duration"),G.field(cd,"isEnabled")
            if start.status=="observed" and duration.status=="observed" and type(start.value)=="number" and type(duration.value)=="number" and enabled.status=="observed" and enabled.value==true then result.ready={status="observed",value=duration.value==0 or start.value+duration.value<=GetTime()} end
        end
    end
    if F.spellStatus then F.spellStatus[spec.key]=result end
    return result
end
function F.memberBytes(index,unit,identity,class,role,now)
    local G=ns.features.GroupContext;local S=ns.state
    local values,at
    if F.shaman then values,at={{},{},{}},now else values,at=F.scan(unit,identity,now) end
    local age=type(at)=="number" and math.floor(math.max(0,now-at)*1000) or 65535
    local scope=identity~="" and 2 or 0
    local packet=S.bytes(F.revision,4)..S.bytes(scope,1)..S.bytes(G.code(F.melee(unit,class,role)),1)..S.bytes(math.min(65535,age),2)
    for action,spec in ipairs(F.deliverySpecs()) do
        local spell=F.spell(spec,unit);local aura=values[blessing(spec.name) or 0] or {}
        local flags=0
        for i,v in ipairs({spell.learned,spell.usable,spell.mana,spell.ready,spell.range,aura.present or {},aura.own or {},aura.other or {}}) do flags=flags+G.code(v)*4^(i-1) end
        flags=flags+S.spellUseCode(spec.key)*65536
        packet=packet..S.bytes(spell.id,4)..S.bytes(flags,3)..S.bytes(0,1)
    end
    if index==1 then
        local r=F.attempt;local identity=r and r.identity or ""
        local age=r and math.floor(math.max(0,now-(r.eventAt or r.at))*1000) or 65535
        packet=packet..S.bytes(r and r.sequence or 0,4)..S.bytes(r and r.revision or 0,4)..S.bytes(r and r.index or 0,1)..S.bytes(r and r.id or 0,4)..S.bytes(r and r.kind or 0,1)..S.bytes(math.min(65535,age),2)..S.bytes(#identity,1)..identity
    end
    return packet
end

-- Courtesy observations share the same class spell and selector keys.
do
    local C={units={"target","mouseover"}}
    F.courtesy=C
    function C.key(code)
        if code<1 or code>32 then return nil end
        if code<=10 then return "CTRL-NUMPAD"..(code-1) end
        if code<=20 then return "CTRL-SHIFT-NUMPAD"..(code-11) end
        if code<=30 then return "ALT-CTRL-SHIFT-"..(code-21) end
        return code==31 and "ALT-CTRL-SHIFT-NUMPADPLUS" or "ALT-CTRL-SHIFT-NUMPADMINUS"
    end
    local function candidate(unit)
        local G=ns.features.GroupContext
        return G.read(UnitIsPlayer,1,unit).value==true and G.read(UnitCanAssist,1,"player",unit).value==true and G.text(G.read(UnitGUID,1,unit),40) or ""
    end
    function C.packet(now,tick)
        local G=ns.features.GroupContext;local S=ns.state
        local ids={candidate("target"),candidate("mouseover")}
        if ids[1]=="" and ids[2]=="" then return nil end
        local packet="HHB3"..S.bytes(S.setupSession,4)..S.bytes(tick,4)..S.bytes(F.revision,4)
        for _,spec in ipairs(F.actions) do
            local spell=F.spell(spec,"player");local flags=S.spellUseCode(spec.key)*256
            for i,v in ipairs({spell.learned,spell.usable,spell.mana,spell.ready}) do flags=flags+G.code(v)*4^(i-1) end
            packet=packet..S.bytes(spell.id,4)..S.bytes(flags,2)
        end
        for member,unit in ipairs(C.units) do
            local identity=ids[member];local name=identity~="" and G.fullName(unit,24) or ""
            local flags=0
            for i,v in ipairs({G.read(UnitExists,1,unit),G.read(UnitIsDeadOrGhost,1,unit),G.read(UnitIsConnected,1,unit),G.read(UnitIsVisible,1,unit),G.read(UnitCanAssist,1,"player",unit),G.read(UnitAffectingCombat,1,unit),G.read(UnitIsPlayer,1,unit)}) do flags=flags+G.code(v)*4^(i-1) end
            local class=G.text(G.read(UnitClass,2,unit),16);local role=G.text(G.read(UnitGroupRolesAssigned,1,unit),12)
            local classID=0;for i,key in ipairs({"HUNTER","SHAMAN","WARRIOR","WARLOCK","DRUID","ROGUE","PALADIN","PRIEST","MAGE"}) do if class==key then classID=i end end
            local roleID=role=="TANK" and 1 or role=="HEALER" and 2 or role=="DAMAGER" and 3 or role=="NONE" and 4 or 0
            local values,at=F.scan(unit,identity,now);local age=at and math.min(65535,math.floor(math.max(0,now-at)*1000)) or 65535
            local scope=identity~="" and 2 or 0
            packet=packet..S.bytes(flags,2)..S.bytes(G.code(F.melee(unit,class,role)),1)..S.bytes(scope,1)..S.bytes(age,2)..S.bytes(classID,1)..S.bytes(roleID,1)..S.bytes(#identity,1)..identity..S.bytes(#name,1)..name
            for action,spec in ipairs(F.actions) do
                local spell=F.spell(spec,unit);local aura=values[action] or {};local code=0
                local f=0;for i,v in ipairs({spell.range,aura.present or {},aura.own or {},aura.other or {}}) do f=f+G.code(v)*4^(i-1) end
                packet=packet..S.bytes(f,1)..S.bytes(code,1)
            end
        end
        packet=packet..S.bytes(S.adler32(packet),4);assert(#packet<=198)
        return packet
    end
end
