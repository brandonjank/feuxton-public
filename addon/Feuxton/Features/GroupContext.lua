-- Shared party capability collection. No gameplay input or polling until wired to a HUD.
local _, ns = ...
local feature = {}
ns.features.GroupContext = feature

-- Keep false/zero distinct from unknown and never inspect protected scalars/tables.
function feature.scalar(value)
    if type(issecretvalue)=="function" and issecretvalue(value) then return {status="restricted"} end
    local kind=type(value)
    if kind~="boolean" and kind~="number" and kind~="string" then return {status="unknown"} end
    if kind=="number" and (value~=value or value==math.huge or value==-math.huge) then return {status="unknown"} end
    return {status="observed",value=value}
end
function feature.read(fn, index, ...)
    if type(fn) ~= "function" then return {status="unavailable"} end
    local args={...}
    local ok,value=pcall(function() return select(index,fn(unpack(args))) end)
    if not ok then return {status="error"} end
    return feature.scalar(value)
end
-- Sample related API results together. Each scalar retains its own restriction
-- status; one secret result must not hide an independently readable result.
function feature.readPair(fn, ...)
    if type(fn)~="function" then return {status="unavailable"},{status="unavailable"} end
    local ok,first,second=pcall(fn,...)
    if not ok then return {status="error"},{status="error"} end
    return feature.scalar(first),feature.scalar(second)
end
function feature.field(object, key)
    if type(issecretvalue)=="function" and issecretvalue(object) then return {status="restricted"} end
    if type(object)~="table" then return {status="unknown"} end
    return feature.read(function() return object[key] end,1)
end
function feature.auraSummary(unit)
    local api=type(C_UnitAuras)=="table" and C_UnitAuras or {}
    local result={}
    if type(api.GetAuraDataByIndex)~="function" then return {{status="unavailable"}} end
    for index=1,16 do
        local ok,aura=pcall(api.GetAuraDataByIndex,unit,index,"HELPFUL")
        if not ok then result[#result+1]={status="error"};break end
        if type(issecretvalue)=="function" and issecretvalue(aura) then result[#result+1]={status="restricted"};break end
        if aura==nil then break end
        if type(aura)~="table" then result[#result+1]={status="unknown"};break end
        result[#result+1]={spellID=feature.field(aura,"spellId"),name=feature.field(aura,"name")}
    end
    return result
end
function feature.capture(spells)
    local snapshot={members={},inRaid=feature.read(IsInRaid,1),groupCount=feature.read(GetNumGroupMembers,1)}
    -- Fixed tokens preserve older party indexes; focus is an additional diagnostic unit.
    for _,unit in ipairs({"player","party1","party2","party3","party4","focus"}) do
        local member={unit=unit,exists=feature.read(UnitExists,1,unit),identity=feature.read(UnitGUID,1,unit),name=feature.read(UnitName,1,unit),class=feature.read(UnitClass,2,unit),connected=feature.read(UnitIsConnected,1,unit),dead=feature.read(UnitIsDeadOrGhost,1,unit),combat=feature.read(UnitAffectingCombat,1,unit),visible=feature.read(UnitIsVisible,1,unit),assistable=feature.read(UnitCanAssist,1,"player",unit),role=feature.read(UnitGroupRolesAssigned,1,unit),health=feature.read(UnitHealth,1,unit),maximumHealth=feature.read(UnitHealthMax,1,unit),ranges={}}
        member.isPlayer=feature.read(UnitIsUnit,1,unit,"player")
        member.isFocus=feature.read(UnitIsUnit,1,unit,"focus")
        member.mainTank=feature.read(GetPartyAssignment,1,"MAINTANK",unit)
        member.healthFraction={status="unknown"}
        if member.exists.status=="observed" and member.exists.value==true and member.health.status=="observed" and member.maximumHealth.status=="observed" and type(member.health.value)=="number" and type(member.maximumHealth.value)=="number" and member.maximumHealth.value>0 and member.health.value>=0 and member.health.value<=member.maximumHealth.value then
            member.healthFraction={status="observed",value=member.health.value/member.maximumHealth.value}
        end
        local api=type(C_Spell)=="table" and C_Spell or {}
        for _,spell in ipairs(spells or {}) do
            if spell.id and spell.id.status=="observed" and type(spell.id.value)=="number" then
                member.ranges[spell.key]=ns.features.RangeTracking.readRange(api.IsSpellInRange or IsSpellInRange,api.IsSpellInRange and spell.id.value or spell.name,unit)
            else member.ranges[spell.key]={status="unknown"} end
        end
        member.auras=feature.auraSummary(unit)
        snapshot.members[#snapshot.members+1]=member
    end
    return snapshot
end


-- HHR1: six fixed tokens, one atomic identity/status record beside each native bar.
-- No aura scans or binding discovery in this shared 50-1000 ms callback.
feature.tokens={"player","party1","party2","party3","party4","focus"}
function feature.code(value)
    return value and value.status=="observed" and (value.value==true and 2 or value.value==false and 1 or 0) or 0
end
function feature.text(value,limit)
    local text=value and value.status=="observed" and value.value
    return type(text)=="string" and #text<=limit and text or ""
end
-- Forever's second UnitName result is the surname, not the realm. Keep the
-- complete public name for recipient receipts; first names are not unique.
local function fullName(first,surname,limit)
    if ns.state.isSecret(first) or ns.state.isSecret(surname) or type(first)~="string" or first=="" then return "" end
    if surname~=nil and type(surname)~="string" then return "" end
    local separator=feature.read(function() return Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR end,1)
    if separator.status=="restricted" then return "" end
    separator=separator.status=="observed" and type(separator.value)=="string" and separator.value or " "
    local name=type(surname)=="string" and surname~="" and first..separator..surname or first
    return #name<=(limit or 64) and name or ""
end
-- A party row needs both the fallback first name and the complete name. Keep
-- the two results from one query, without retaining a unit snapshot for casts.
function feature.names(unit,limit)
    local ok,first,surname=pcall(UnitName,unit)
    if not ok then return "","" end
    return feature.text(feature.scalar(first),limit or 64),fullName(first,surname,limit)
end
function feature.fullName(unit,limit)
    local _,name=feature.names(unit,limit)
    return name
end
function feature.initialize()
    local S=ns.state
    local panel=CreateFrame("Frame",nil,S.hud);S.groupPanel=panel;panel:SetSize(668,102)
    panel:SetPoint("TOPLEFT",S.hud,"TOPLEFT",0,-512)
    local displays={};S.groupDisplays=displays
    for index,unit in ipairs(feature.tokens) do
        local y=6+(index-1)*16
        local bar=CreateFrame("StatusBar",nil,panel);bar:SetPoint("TOPLEFT",12,-y-4);bar:SetSize(96,8)
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8");bar:SetStatusBarColor(0,1,0,1)
        local back=bar:CreateTexture(nil,"BACKGROUND");back:SetAllPoints();back:SetColorTexture(0.18,0.18,0.18,1)
        displays[index]={unit=unit,bar=bar}
        displays[index].healRanges={}
        for action=1,3 do local dot=bar:CreateTexture(nil,"OVERLAY");dot:SetSize(4,4);dot:SetPoint("TOPLEFT",bar,"TOPLEFT",108+(action-1)*6,0);ns.features.RangeTracking.initialize(dot,1,.65,0,1);displays[index].healRanges[action]=dot end
    end
    local tick,total=0,0
    panel:SetScript("OnUpdate",function(self,elapsed)
        total=total+elapsed;if total<S.updateInterval() then return end;total=0;tick=(tick+1)%4294967296
        local raid=feature.code(feature.read(IsInRaid,1));local count=feature.read(GetNumGroupMembers,1)
        count=count.status=="observed" and type(count.value)=="number" and count.value>=0 and count.value<=40 and count.value==math.floor(count.value) and count.value or 255
        local healSpecs=ns.classes.PALADIN and ns.classes.PALADIN.rangeSpecs or {}
        local playerClass=feature.text(feature.read(UnitClass,2,"player"),16)
        local friendly=(playerClass=="PALADIN" or playerClass=="SHAMAN" or playerClass=="DRUID") and ns.features.Healing or nil
        local now=S.readableCall(GetTime)
        if friendly then
            friendly.spellStatus={}
            if type(now)~="number" or not pcall(friendly.refresh,now) then friendly=nil end
        elseif ns.features.Healing then pcall(ns.features.Healing.refresh,now) end
        for index,display in ipairs(displays) do
            local ok,rowError=pcall(function()
                local unit=display.unit
                local exists=feature.read(UnitExists,1,unit)
                local guid=exists.value==true and feature.text(feature.read(UnitGUID,1,unit),40) or ""
                local name,full="",""
                if exists.value==true then name,full=feature.names(unit,24) end
                if full~="" then name=full end
                local rendered=false
                if exists.value==true and guid~="" then
                    rendered=pcall(function()
                        local maximum=UnitHealthMax(unit)
                        if not S.isSecret(maximum) and (type(maximum)~="number" or maximum<=0) then error("No maximum") end
                        display.bar:SetMinMaxValues(0,maximum);display.bar:SetValue(UnitHealth(unit))
                    end)
                end
                if not rendered then display.bar:SetMinMaxValues(0,1);display.bar:SetValue(0) end
                local flags=feature.code(exists)
                local checks={feature.read(UnitIsDeadOrGhost,1,unit),feature.read(UnitIsConnected,1,unit),feature.read(UnitIsVisible,1,unit),feature.read(UnitCanAssist,1,"player",unit),feature.read(UnitAffectingCombat,1,unit),feature.read(UnitIsUnit,1,unit,"player"),feature.read(UnitIsUnit,1,unit,"focus"),feature.read(GetPartyAssignment,1,"MAINTANK",unit)}
                for i,value in ipairs(checks) do flags=flags+feature.code(value)*4^i end
                local role=feature.text(feature.read(UnitGroupRolesAssigned,1,unit),12)
                local roleID=role=="TANK" and 1 or role=="HEALER" and 2 or role=="DAMAGER" and 3 or role=="NONE" and 4 or 0
                local class=feature.text(feature.read(UnitClass,2,unit),16);local classID=0
                for i,key in ipairs({"HUNTER","SHAMAN","WARRIOR","WARLOCK","DRUID","ROGUE","PALADIN","PRIEST","MAGE"}) do if class==key then classID=i end end
                local ranges=0;local api=type(C_Spell)=="table" and C_Spell or {}
                -- A row consumes each friendly spell immediately: public flags
                -- go to its packet, while raw restricted range goes only to
                -- that row's native indicator. No global sample map is needed.
                local spells=friendly and {} or nil
                if friendly then for action,spec in ipairs(friendly.deliverySpecs()) do
                    local spell,rangeOK,rangeRaw=friendly.spell(spec,unit);spells[spec.key]=spell
                    if friendly.shaman or friendly.druid then
                        local druid=ns.classes.DRUID
                        local dot=friendly.druid and druid.recipientDots and druid.recipientDots[index].range[action] or display.healRanges[action];dot:Show()
                        local painted,result=pcall(ns.features.RangeTracking.paintBoolean,dot,rangeRaw,{0,1,0,1},{1,0,0,1})
                        if not rangeOK or not painted or result~=true or spell.id==0 then ns.features.RangeTracking.paintColor(dot,1,.65,0,1) end
                    end
                end end
                if friendly and friendly.druid and ns.classes.DRUID.observeRecipient then ns.classes.DRUID.observeRecipient(index,unit,guid,spells) end
                for i,spell in ipairs(healSpecs) do
                    local range
                    for _,sample in pairs(spells or {}) do if sample.id==spell.id then range=sample.range;break end end
                    if not range then range=ns.features.RangeTracking.readRange(api.IsSpellInRange or IsSpellInRange,api.IsSpellInRange and spell.id or spell.name,unit) end
                    ranges=ranges+feature.code(range)*4^(i-1)
                end
                if not friendly or not (friendly.shaman or friendly.druid) then for _,dot in ipairs(display.healRanges) do dot:Hide() end end
                local packet=(friendly and (friendly.druid and "HHR7" or friendly.shaman and "HHR4" or "HHR8") or "HHR1")..S.bytes(S.setupSession,4)..S.bytes(tick,4)..S.bytes(index,1)..S.bytes(raid,1)..S.bytes(count,1)..S.bytes(flags,3)..S.bytes(roleID,1)..S.bytes(classID,1)..S.bytes(#guid,1)..guid..S.bytes(#name,1)..name..S.bytes(ranges,1)..S.bytes(rendered and 2 or 0,1)
                if friendly then packet=packet..friendly.memberBytes(index,unit,guid,class,role,now,spells) end
                packet=packet..S.bytes(S.adler32(packet),4);assert(#packet<=(friendly and friendly.druid and 256 or 198))
                S.publishTransportPacket(15+index,packet,true)
            end)
            S.groupRowErrors=S.groupRowErrors or {};S.groupRowErrors[index]=not ok and S.describe(rowError) or nil
            if not ok then S.publishTransportPacket(15+index,nil,true) end -- bad rows never retain old identity/health
        end
        -- Publish after all six rows, avoiding transient mixed roster sequences.
        local courtesy
        if friendly and not friendly.shaman and not friendly.druid and friendly.courtesy then
            local ok,packet=pcall(friendly.courtesy.packet,now,tick)
            if ok then courtesy=packet end
        end
        S.publishTransportPacket(4,courtesy,true)
        local targeting
        if friendly then local ok,packet=pcall(ns.features.RecipientTargeting.packet,now,tick);if ok then targeting=packet end end
        S.publishTransportPacket(7,targeting,true)
        S.refreshTransportPacketState()
    end)
    S.profileScript(panel,"OnUpdate","group")
end
