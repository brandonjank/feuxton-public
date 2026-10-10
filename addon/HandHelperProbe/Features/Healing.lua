-- Shared friendly-action delivery. Secure buttons are clicked by hardware keys;
-- ordinary Lua only configures them outside combat and reports public evidence.
local _, ns = ...
local F={cache={},buttons={},assignments={},retired={{},{}},bank=1,revision=0}
ns.features.Healing=F
F.actions={{key="paladin.blessingMight",name="Blessing of Might"},{key="paladin.blessingWisdom",name="Blessing of Wisdom"}}
F.heal={key="paladin.holyLight",name="Holy Light",healing=true}
F.layHands={key="paladin.layHands",name="Lay on Hands",healing=true}
F.cancelFury={key="paladin.cancelRighteousFury",name="Righteous Fury",cancel=true}
-- Compact, reversible managed-key vocabulary; ordinary player bindings are untouched.
function F.key(code)
    local bank=code>=33 and 2 or 1;local i=code-(bank==2 and 32 or 0)
    if i<1 or i>22 then return nil end
    return (bank==1 and "ALT-CTRL-" or "CTRL-SHIFT-")..(i<=12 and "F"..i or tostring(i-13))
end
function F.keyCode(key)
    for bank=1,2 do for i=1,22 do local code=(bank-1)*32+i;if F.key(code)==key then return code end end end
    return 0
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
    if type(HandHelperProbeDB)~="table" then return end
    local list=HandHelperProbeDB.managedHealTrace or {};HandHelperProbeDB.managedHealTrace=list
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
end
function F.scan(unit,identity,now)
    local G=ns.features.GroupContext;local S=ns.state
    if S.readableCall(InCombatLockdown)~=false then return {{},{}} end
    local cached=F.cache[unit]
    if cached and cached.identity==identity and now-cached.at>=0 and now-cached.at<.25 then return cached.values,cached.at end
    local values={{},{}};local complete=false
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
function F.initialize()
    if F.owner or type(SetOverrideBindingClick)~="function" or type(ClearOverrideBindings)~="function" or type(GetBindingAction)~="function" or type(SecureHandlerWrapScript)~="function" then return end
    F.owner=CreateFrame("Frame",nil,UIParent)
    for bank=1,2 do F.buttons[bank]={}
        for member=1,6 do F.buttons[bank][member]={}
            for action,spec in ipairs(member==1 and {F.actions[1],F.actions[2],F.heal,F.layHands,F.cancelFury} or {F.actions[1],F.actions[2],F.heal}) do
                local unit=ns.features.GroupContext.tokens[member]
                local name="HandHelperPartyAction"..bank.."_"..member.."_"..action
                local b=CreateFrame("Button",name,UIParent,"SecureActionButtonTemplate,SecureHandlerBaseTemplate")
                b:SetSize(1,1);b:SetPoint("TOPLEFT",UIParent,"TOPLEFT",-10000,10000);b:SetAlpha(0)
                b:RegisterForClicks("AnyDown","AnyUp");b:SetAttribute("useOnKeyDown",true)
                b:SetAttribute("type",nil);b:SetAttribute("spell",spec.name);b:SetAttribute("unit",unit)
                b:SetAttribute("checkselfcast",false);b:SetAttribute("checkfocuscast",false)
                b:SetAttribute("hh-heal",spec.healing==true);b:SetAttribute("hh-cancel",spec.cancel==true)
                -- Use the native spell handler, not an addon macrotext runner.
                -- The secure wrapper checks combat at the hardware click itself.
                SecureHandlerWrapScript(b,"OnClick",b,[[
                    local heal = self:GetAttribute("hh-heal")
                    local cancel = self:GetAttribute("hh-cancel")
                    local allowed = self:GetAttribute("hh-valid") and (heal or cancel or SecureCmdOptionParse("[nocombat]1;0") == "1")
                    if heal then allowed = allowed and SecureCmdOptionParse("[@"..self:GetAttribute("unit")..",exists,help,nodead]1;0") == "1" end
                    self:SetAttribute("type",allowed and (cancel and "cancelaura" or "spell") or nil)
                ]])
                b:SetScript("PreClick",function(self,button,down)
                    local G=ns.features.GroupContext;local S=ns.state
                    local guid=G.text(G.read(UnitGUID,1,unit),40)
                    local valid=self.hhIdentity and guid==self.hhIdentity and G.read(UnitExists,1,unit).value==true and G.read(UnitIsDeadOrGhost,1,unit).value==false and G.read(UnitIsConnected,1,unit).value==true and G.read(UnitCanAssist,1,"player",unit).value==true
                    if S.readableCall(InCombatLockdown)==false then self:SetAttribute("hh-valid",valid and true or nil) end
                    if spec.healing and down==true and valid then
                        local name=G.fullName(unit,64)
                        local now=timeNow()
                        if name~="" and now and self.hhSpellID then
                            F.sequence=((F.sequence or 0)+1)%4294967296
                            F.attempt={sequence=F.sequence,revision=F.revision,index=member,unit=unit,identity=guid,name=name,id=self.hhSpellID,at=now,kind=0}
                            trace("MANAGED_CLICK",unit,guid,name,self.hhSpellID)
                        end
                    end
                end)
                F.buttons[bank][member][action]={button=b,name=name,unit=unit,spec=spec}
            end
        end
    end
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
local function actionForKey(key,override)
    local G=ns.features.GroupContext;local v=G.read(GetBindingAction,1,key,override)
    return v.status=="observed" and type(v.value)=="string" and v.value or nil
end
function F.refresh(now)
    local G=ns.features.GroupContext;local S=ns.state
    if S.readableCall(InCombatLockdown)~=false or type(now)~="number" then return end
    if G.text(G.read(UnitClass,2,"player"),16)~="PALADIN" then
        if F.owner then ClearOverrideBindings(F.owner);F.assignments={};F.signature=nil end
        return
    end
    F.initialize();if not F.owner then return end
    local ids={};for i=1,6 do ids[i]=G.text(G.read(UnitGUID,1,G.tokens[i]),40) end
    local heal=F.spell(F.heal,"player")
    local lay=F.spell(F.layHands,"player")
    local signature=table.concat(ids,"|").."|"..heal.id.."|"..lay.id
    local changed=signature~=F.signature
    local conflict=false
    for _,entry in ipairs(F.assignments) do if entry.key and (ns.keyPolicy.reason(entry.key) or actionForKey(entry.key,false)~="" or actionForKey(entry.key,true)~="CLICK "..entry.name..":LeftButton") then conflict=true end end
    if not changed and not conflict and not F.retryAt then return end
    if F.retryAt and now<F.retryAt then return end
    local nextBank=F.signature and (3-F.bank) or F.bank
    local retiredAt=F.retired[nextBank].at
    -- An old key must never become a key for a new party identity while an
    -- Context retention plus capture freshness can cover 3.5 s. Quarantine
    -- for four seconds before reusing a bank for different recipients.
    if retiredAt and now-retiredAt<4 then
        ClearOverrideBindings(F.owner);F.assignments={};F.retryAt=retiredAt+4;return
    end
    ClearOverrideBindings(F.owner)
    for _,entry in ipairs(F.assignments) do entry.button:SetAttribute("type",nil);entry.button:SetAttribute("hh-valid",nil);entry.button.hhIdentity=nil end
    if F.signature then F.retired[F.bank].at=now end
    F.bank=nextBank;F.signature=signature;F.revision=(F.revision+1)%4294967296;F.retryAt=nil;F.assignments={}
    local keyIndex=1
    local order={};for member=1,5 do for action=1,2 do order[#order+1]={member,action} end end
    for member=1,6 do order[#order+1]={member,3} end
    order[#order+1]={1,4};order[#order+1]={1,5}
    for _,slot in ipairs(order) do local member,action=slot[1],slot[2]
        local entry=F.buttons[F.bank][member][action];entry.identity=ids[member];entry.key=nil
        if entry.identity~="" then
            while keyIndex<=22 do
                -- WoW hardware bindings use canonical ALT-CTRL-SHIFT order.
                -- A noncanonical key may round-trip by name but miss real input.
                local key=F.key((F.bank-1)*32+keyIndex);keyIndex=keyIndex+1
                if not ns.keyPolicy.reason(key) and actionForKey(key,false)=="" and actionForKey(key,true)=="" then
                    local ok=pcall(SetOverrideBindingClick,F.owner,false,key,entry.name,"LeftButton")
                    if ok and actionForKey(key,true)=="CLICK "..entry.name..":LeftButton" then entry.key=key;break end
                end
            end
        end
        entry.button.hhIdentity=entry.identity~="" and entry.identity or nil
        local castID=action==3 and heal.id or action==4 and lay.id or 0
        entry.button.hhSpellID=castID>0 and castID or nil
        entry.button:SetAttribute("spell",castID>0 and castID or entry.spec.name)
        entry.button:SetAttribute("hh-valid",action>=3 and entry.identity~="" and true or nil);entry.button:SetAttribute("type",nil)
        F.assignments[#F.assignments+1]=entry
    end
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
    local values,at=F.scan(unit,identity,now);local age=type(at)=="number" and math.floor(math.max(0,now-at)*1000) or 65535
    local entry1,entry2=F.assignments[(index-1)*2+1],F.assignments[(index-1)*2+2]
    local scope=index<=5 and entry1 and entry2 and entry1.identity==identity and entry2.identity==identity and identity~="" and 2 or 0
    local packet=S.bytes(F.revision,4)..S.bytes(scope,1)..S.bytes(G.code(F.melee(unit,class,role)),1)..S.bytes(math.min(65535,age),2)
    for action,spec in ipairs({F.actions[1],F.actions[2],F.heal}) do
        local spell=F.spell(spec,unit);local aura=values[action] or {};local entry=action==3 and F.assignments[10+index] or action==1 and entry1 or entry2
        local key=entry and entry.identity==identity and identity~="" and entry.key or ""
        if action~=3 and scope~=2 then key="" end
        if action==3 and entry and (entry.button.hhSpellID~=spell.id or not F.receiptsAvailable) then key="" end
        if not key or #key>16 or key~="" and (ns.keyPolicy.reason(key) or actionForKey(key,true)~="CLICK "..entry.name..":LeftButton") then key="" end
        local flags=0
        for i,v in ipairs({spell.learned,spell.usable,spell.mana,spell.ready,spell.range,aura.present or {},aura.own or {},aura.other or {}}) do flags=flags+G.code(v)*4^(i-1) end
        flags=flags+S.spellUseCode(spec.key)*65536
        packet=packet..S.bytes(spell.id,4)..S.bytes(flags,3)..S.bytes(F.keyCode(key),1)
    end
    if index==1 then
        local r=F.attempt;local identity=r and r.identity or ""
        local age=r and math.floor(math.max(0,now-(r.eventAt or r.at))*1000) or 65535
        packet=packet..S.bytes(r and r.sequence or 0,4)..S.bytes(r and r.revision or 0,4)..S.bytes(r and r.index or 0,1)..S.bytes(r and r.id or 0,4)..S.bytes(r and r.kind or 0,1)..S.bytes(math.min(65535,age),2)..S.bytes(#identity,1)..identity
    end
    return packet
end

-- Courtesy recipients are deliberately separate from party delivery. Moving a
-- mouse across players must not rotate Holy Light's keys or receipt revision.
do
    local C={units={"target","mouseover"},buttons={},assignments={},bank=1,banks=8,revision=0,retired={}}
    F.courtesy=C
    function C.key(code)
        if code<1 or code>32 then return nil end
        if code<=8 then return (code<=4 and "ALT-CTRL-SHIFT-F" or "ALT-SHIFT-F")..((code-1)%4+1) end
        if code<=24 then return (code<=16 and "ALT-CTRL-SHIFT-F" or "ALT-SHIFT-F")..((code-9)%8+5) end
        return "ALT-CTRL-SHIFT-"..(code-25)
    end
    local function candidate(unit)
        local G=ns.features.GroupContext
        return G.read(UnitIsPlayer,1,unit).value==true and G.read(UnitCanAssist,1,"player",unit).value==true and G.text(G.read(UnitGUID,1,unit),40) or ""
    end
    function C.initialize()
        if C.owner or not F.owner then return end
        C.owner=CreateFrame("Frame",nil,UIParent)
        for bank=1,C.banks do C.buttons[bank]={}
            for member,unit in ipairs(C.units) do C.buttons[bank][member]={}
                for action,spec in ipairs(F.actions) do
                    local name="HandHelperCourtesyAction"..bank.."_"..member.."_"..action
                    local b=CreateFrame("Button",name,UIParent,"SecureActionButtonTemplate,SecureHandlerBaseTemplate")
                    b:SetSize(1,1);b:SetPoint("TOPLEFT",UIParent,"TOPLEFT",-10000,10000);b:SetAlpha(0)
                    b:RegisterForClicks("AnyDown","AnyUp");b:SetAttribute("useOnKeyDown",true)
                    b:SetAttribute("unit",unit);b:SetAttribute("spell",spec.name)
                    b:SetAttribute("checkselfcast",false);b:SetAttribute("checkfocuscast",false)
                    SecureHandlerWrapScript(b,"OnClick",b,[[
                        local allowed = self:GetAttribute("hh-valid") and SecureCmdOptionParse("[nocombat]1;0") == "1"
                        self:SetAttribute("type",allowed and "spell" or nil)
                    ]])
                    b:SetScript("PreClick",function(self)
                        if ns.state.readableCall(InCombatLockdown)~=false then return end
                        local G=ns.features.GroupContext
                        local valid=self.hhIdentity and candidate(unit)==self.hhIdentity and G.read(UnitExists,1,unit).value==true and G.read(UnitIsDeadOrGhost,1,unit).value==false and G.read(UnitIsConnected,1,unit).value==true and G.read(UnitIsVisible,1,unit).value==true and G.read(UnitAffectingCombat,1,unit).value==false
                        self:SetAttribute("hh-valid",valid and true or nil)
                    end)
                    C.buttons[bank][member][action]={button=b,name=name,unit=unit,spec=spec}
                end
            end
        end
    end
    local function clear()
        if C.owner then ClearOverrideBindings(C.owner) end
        for _,e in ipairs(C.assignments) do e.button:SetAttribute("type",nil);e.button:SetAttribute("hh-valid",nil);e.button.hhIdentity=nil end
        C.assignments={}
    end
    function C.refresh(now,ids)
        if ns.state.readableCall(InCombatLockdown)~=false then return end
        if ids[1]=="" and ids[2]=="" and not C.owner then return end
        C.initialize();if not C.owner then return end
        -- Preserve each missing scope independently: hovering away must not
        -- rebuild the keys for a friendly player still selected as target.
        local boundIds={}
        for member=1,2 do
            boundIds[member]=ids[member]~="" and ids[member] or C.boundIds and C.boundIds[member] or ""
            if ids[member]=="" then for _,e in ipairs(C.assignments) do if e.unit==C.units[member] then e.button:SetAttribute("hh-valid",nil);e.button:SetAttribute("type",nil) end end end
        end
        local signature=table.concat(boundIds,"|")
        local conflict=false
        for _,e in ipairs(C.assignments) do if e.key and (ns.keyPolicy.reason(e.key) or actionForKey(e.key,false)~="" or actionForKey(e.key,true)~="CLICK "..e.name..":LeftButton") then conflict=true end end
        if ids[1]=="" and ids[2]=="" and not conflict then
            -- An empty mouseover publishes no recipient and cannot pass PreClick.
            -- Keep its identity-scoped keys so a brief gap does not consume a bank.
            for _,e in ipairs(C.assignments) do e.button:SetAttribute("hh-valid",nil);e.button:SetAttribute("type",nil) end
            return
        end
        if signature==C.signature and not conflict and not C.retryAt then return end
        -- Invalidate immediately even during bank quarantine. Old bindings can
        -- never point at a newly hovered/selected player.
        local bank,retryAt
        for offset=1,C.banks do
            local nextBank=C.signature and (C.bank+offset-1)%C.banks+1 or offset
            local retired=C.retired[nextBank]
            if not C.signature or nextBank~=C.bank then
                if not retired or now-retired>=4 then bank=nextBank;break end
                retryAt=math.min(retryAt or retired+4,retired+4)
            end
        end
        if not bank then clear();C.retryAt=retryAt;return end
        clear()
        if C.signature then C.retired[C.bank]=now end
        C.bank=bank;C.signature=signature;C.boundIds=boundIds;C.retryAt=nil;C.revision=(C.revision+1)%4294967296
        local code=(bank-1)*4+1;local last=bank*4
        for member=1,2 do for action=1,2 do
            local e=C.buttons[bank][member][action];e.identity=boundIds[member];e.key=nil;e.code=0
            if e.identity~="" then
                while code<=last do
                    local key=C.key(code);local chosen=code;code=code+1
                    if not ns.keyPolicy.reason(key) and actionForKey(key,false)=="" and actionForKey(key,true)=="" then
                        local ok=pcall(SetOverrideBindingClick,C.owner,false,key,e.name,"LeftButton")
                        if ok and actionForKey(key,true)=="CLICK "..e.name..":LeftButton" then e.key=key;e.code=chosen;break end
                    end
                end
            end
            e.button.hhIdentity=e.identity~="" and e.identity or nil
            e.button:SetAttribute("hh-valid",nil);e.button:SetAttribute("type",nil)
            C.assignments[#C.assignments+1]=e
        end end
    end
    function C.packet(now,tick)
        local G=ns.features.GroupContext;local S=ns.state
        local ids={candidate("target"),candidate("mouseover")}
        C.refresh(now,ids)
        if ids[1]=="" and ids[2]=="" then return nil end
        local packet="HHB1"..S.bytes(S.setupSession,4)..S.bytes(tick,4)..S.bytes(C.revision,4)
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
            local values,at=F.scan(unit,identity,now);local age=at and math.min(65535,math.floor(math.max(0,now-at)*1000)) or 65535
            local scope=C.boundIds and C.boundIds[member]==identity and not C.retryAt and identity~="" and 2 or 0
            packet=packet..S.bytes(flags,2)..S.bytes(G.code(F.melee(unit,class,role)),1)..S.bytes(scope,1)..S.bytes(age,2)..S.bytes(#identity,1)..identity..S.bytes(#name,1)..name
            for action,spec in ipairs(F.actions) do
                local spell=F.spell(spec,unit);local aura=values[action] or {};local entry=C.assignments[(member-1)*2+action]
                local code=scope==2 and entry and entry.identity==identity and entry.key and not ns.keyPolicy.reason(entry.key) and actionForKey(entry.key,true)=="CLICK "..entry.name..":LeftButton" and entry.code or 0
                local f=0;for i,v in ipairs({spell.range,aura.present or {},aura.own or {},aura.other or {}}) do f=f+G.code(v)*4^(i-1) end
                packet=packet..S.bytes(f,1)..S.bytes(code,1)
            end
        end
        packet=packet..S.bytes(S.adler32(packet),4);assert(#packet<=184)
        return packet
    end
end
