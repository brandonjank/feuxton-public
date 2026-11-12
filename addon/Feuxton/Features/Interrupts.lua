-- Target cast activity plus a native interruptibility flag. Restricted values
-- only reach supported native color rendering; Lua never branches on them.
local _,ns=...
local I={};ns.features.Interrupts=I
local active,channel,sequence=nil,nil,0
local eventID,eventName
local castActivity
-- Public lifecycle ownership only; no restricted cast fields are exposed.
function I.activitySequence() return sequence end
function I.initialize()
    local S=ns.state
    castActivity=ns.features.CastTracking.newActivityState()
    local dot=S.resourcePanel:CreateTexture(nil,"OVERLAY")
    dot:SetSize(8,8);dot:SetPoint("TOPLEFT",616,-4);I.dot=dot
    ns.features.RangeTracking.initialize(dot,1,.65,0,1)
    I.window=S.hud:CreateTexture(nil,"OVERLAY");I.window:SetSize(4,4);I.window:SetPoint("TOPLEFT",540,-2)
    ns.features.RangeTracking.initialize(I.window,1,.65,0,1)
    I.stamp={}
    for i=1,4 do local p=S.resourcePanel:CreateTexture(nil,"OVERLAY");p:SetSize(4,4);p:SetPoint("TOPLEFT",628+(i-1)*6,-4);I.stamp[i]=p end
    local eventFrame=CreateFrame("Frame",nil,S.hud)
    for _,event in ipairs({"PLAYER_TARGET_CHANGED","UNIT_SPELLCAST_START","UNIT_SPELLCAST_STOP","UNIT_SPELLCAST_FAILED","UNIT_SPELLCAST_INTERRUPTED","UNIT_SPELLCAST_CHANNEL_START","UNIT_SPELLCAST_CHANNEL_STOP"}) do pcall(eventFrame.RegisterEvent,eventFrame,event) end
    eventFrame:SetScript("OnEvent",function(_,event,unit,castGUID,spellID)
        if event=="PLAYER_TARGET_CHANGED" then active=nil;channel=nil;eventID=nil;eventName=nil;castActivity=ns.features.CastTracking.newActivityState();sequence=(sequence+1)%65536;return end
        if S.isSecret(unit) or unit~="target" then return end
        local accepted=ns.features.CastTracking.activityEvent(castActivity,event,castGUID,spellID)
        if event=="UNIT_SPELLCAST_START" or event=="UNIT_SPELLCAST_CHANNEL_START" then
            eventID=not S.isSecret(spellID) and type(spellID)=="number" and spellID or nil
            eventName=eventID and S.readableCall(S.spellAPI.GetSpellName,eventID) or nil
        end
        if event=="UNIT_SPELLCAST_START" then active=true;channel=false;sequence=(sequence+1)%65536
        elseif event=="UNIT_SPELLCAST_CHANNEL_START" then active=true;channel=true;sequence=(sequence+1)%65536
        elseif accepted then
            if castActivity.cast==false and castActivity.channel==false then active=false else active=nil end
        end
    end)
end

-- Optional alternate-hostile interrupt observations. This source is bounded and
-- independently stamped; it cannot invalidate the selected-target HHE2 lane.
-- Restricted range, cooldown and cast flags only reach native color APIs.
local extra
local function extraState()
    if extra then return extra end
    local S=ns.state;local panel=S.paladinNativePanel
    if not panel then return nil end
    local R=ns.features.RangeTracking
    extra={identity=nil,generation=0,sequence=0,active=nil,channel=nil,cells={},stamp={}}
    for i=1,11 do
        local p=panel:CreateTexture(nil,"OVERLAY");p:SetSize(4,4);p:SetPoint("TOPLEFT",20+(i-1)*6,-24);R.initialize(p,1,.65,0,1);extra.cells[i]=p
    end
    for i=1,4 do local p=panel:CreateTexture(nil,"OVERLAY");p:SetSize(4,4);p:SetPoint("TOPLEFT",92+(i-1)*6,-24);R.initialize(p,1,.65,0,1);extra.stamp[i]=p end
    extra.auraSignals={}
    for i,x in ipairs({86,116}) do
        local p=panel:CreateTexture(nil,"OVERLAY");p:SetSize(4,4);p:SetPoint("TOPLEFT",x,-24);R.initialize(p,0,.25,1,1);extra.auraSignals[i]=p
    end
    local frame=CreateFrame("Frame",nil,panel)
    for _,event in ipairs({"UPDATE_MOUSEOVER_UNIT","UNIT_SPELLCAST_START","UNIT_SPELLCAST_STOP","UNIT_SPELLCAST_FAILED","UNIT_SPELLCAST_INTERRUPTED","UNIT_SPELLCAST_CHANNEL_START","UNIT_SPELLCAST_CHANNEL_STOP"}) do pcall(frame.RegisterEvent,frame,event) end
    frame:SetScript("OnEvent",function(_,event,unit,castGUID,spellID)
        if event=="UPDATE_MOUSEOVER_UNIT" then extra.identity=nil;extra.generation=(extra.generation+1)%4294967296;extra.active=nil;extra.channel=nil;extra.activity=nil;extra.eventID=nil;return end
        if S.isSecret(unit) or unit~="mouseover" then return end
        extra.activity=extra.activity or ns.features.CastTracking.newActivityState()
        local accepted=ns.features.CastTracking.activityEvent(extra.activity,event,castGUID,spellID)
        if event=="UNIT_SPELLCAST_START" or event=="UNIT_SPELLCAST_CHANNEL_START" then
            extra.sequence=(extra.sequence+1)%65536;extra.active=true;extra.channel=event=="UNIT_SPELLCAST_CHANNEL_START"
            extra.eventID=not S.isSecret(spellID) and type(spellID)=="number" and spellID or nil
        elseif accepted then if extra.activity.cast==false and extra.activity.channel==false then extra.active=false else extra.active=nil end end
    end)
    return extra
end
local function extraNativeAuras(state)
    local S=ns.state;local now=S.readableCall(GetTime)
    if type(now)~="number" then return 0 end
    if state.targetGeneration~=S.auraGeneration then state.targetGeneration=S.auraGeneration;state.targetSettledAt=now+.2 end
    if not state.auraContainers and S.readableCall(InCombatLockdown)==false and now>=(state.auraRetryAt or 0) then
        state.auraRetryAt=now+1
        local containers={}
        local ok=pcall(function()
            for i,spec in ipairs({{unit="target",filter="HARMFUL",id=20066,x=86},{unit="player",filter="HARMFUL",id=11196,x=116}}) do
                local container=CreateFrame("AuraContainer",nil,S.paladinNativePanel,"CustomAuraContainerTemplate");containers[i]=container;container:SetAllPoints(S.paladinNativePanel)
                local ids={[spec.id]=true};if spec.id==11196 then ids[1305047]=true end
                container:AddAuraSlot("feuxton.interrupt."..spec.id,spec.filter,{candidateFilters={includeSpellIDs=ids},initializeFrame=function(button)
                    button:SetSize(4,4);button:SetPoint("TOPLEFT",container,"TOPLEFT",spec.x,-24);button:EnableMouse(false)
                    local icon=button:CreateTexture(nil,"ARTWORK");icon:SetAllPoints(button);button:SetIcon(icon)
                    local signal=button:CreateTexture(nil,"OVERLAY");signal:SetAllPoints(button);signal:SetColorTexture(0,1,0,1)
                end})
                container:SetUnit(spec.unit);container:SetEnabled(true)
            end
        end)
        if ok then state.auraContainers=containers;state.auraSettledAt=now+.2
        else for _,container in ipairs(containers) do pcall(container.SetEnabled,container,false);pcall(container.Hide,container) end end
    end
    if not state.auraContainers or now<(state.auraSettledAt or math.huge) then return 0 end
    return (now>=(state.targetSettledAt or math.huge) and 16 or 0)+32
end
local function extraPublicAura(unit,id,name,filter)
    local S=ns.state;local api=type(C_UnitAuras)=="table" and C_UnitAuras or {};local fn,args
    if unit=="player" and type(api.GetPlayerAuraBySpellID)=="function" then fn=api.GetPlayerAuraBySpellID;args={id}
    elseif type(api.GetAuraDataBySpellName)=="function" then fn=api.GetAuraDataBySpellName;args={unit,name,filter}
    else return {} end
    local ok,aura=pcall(fn,unpack(args))
    if not ok or S.isSecret(aura) then return {} end
    if aura==nil then return {status="observed",value=false} end
    if type(aura)~="table" then return {} end
    local observed=ns.features.GroupContext.field(aura,"spellId")
    if observed.status~="observed" or observed.value~=id then return {} end
    return {status="observed",value=true}
end
local function extraHoverClock(state,current,channel)
    -- The FHS3 row's left gutter is unused telemetry space. Its existing
    -- calibration font owns recognition; the separate HHK2 stamp owns unit/time.
    local footer=ns.nativeSignals
    if not state.hoverTimer and footer and footer.frame then state.hoverTimer=ns.rendering.numberFont(footer.frame,8,22,70,18) end
    if not state.hoverTimer then return {status=0,value=0},false end
    local getter=channel==true and UnitChannelDuration or UnitCastingDuration
    return ns.rendering.nativeTimer(state.hoverTimer,getter,"mouseover",current==true and type(channel)=="boolean")
end
local function publicCast(unit,isChannel)
    local S=ns.state;local fn=isChannel and UnitChannelInfo or UnitCastingInfo
    if type(fn)~="function" then return nil end
    local values={pcall(fn,unit)};if values[1]~=true then return nil end
    local name=values[2];local active
    if not S.isSecret(name) then active=name~=nil end
    return active,values[isChannel and 8 or 9],name,values[isChannel and 9 or 10],values[5],values[6]
end
function I.extraPacket(tick)
    local S=ns.state;local G=ns.features.GroupContext;local R=ns.features.RangeTracking
    if G.text(G.read(UnitClass,2,"player"),16)~="PALADIN" then return nil end
    local specs=ns.classes.PALADIN and ns.classes.PALADIN.specs;local targetSpec,hoverSpec
    for _,spec in ipairs(specs or {}) do if spec.key=="paladin.repentance" then targetSpec=spec elseif spec.key=="paladin.mouseoverRepentance" then hoverSpec=spec end end
    if not targetSpec or not hoverSpec then return nil end
    local target,trOK,tr,tuOK,tu,tm,trSource,tuSource=ns.features.Healing.spell(targetSpec,"target")
    if target.learned.value~=true or (target.id or 0)<=0 then return nil end
    local hover,hrOK,hr,huOK,hu,hm,hrSource,huSource=ns.features.Healing.spell(hoverSpec,"mouseover")
    if hover.id~=target.id or hover.learned.value~=true then return nil end
    local state=extraState();if not state then return nil end
    local identity=G.text(G.read(UnitGUID,1,"mouseover"),40) or ""
    if identity~=state.identity then state.identity=identity;state.generation=(state.generation+1)%4294967296;state.sequence=(state.sequence+1)%65536;state.active=nil;state.channel=nil;state.activity=nil;state.eventID=nil end
    local function flag(fn,...)return G.code(G.read(fn,1,...))end
    local function humanoid(unit)local v=G.read(UnitCreatureType,1,unit);return v.status=="observed" and type(v.value)=="string" and {status="observed",value=v.value=="Humanoid"} or {}end
    local flags=flag(UnitExists,"mouseover")+flag(UnitIsDeadOrGhost,"mouseover")*4+flag(UnitCanAttack,"player","mouseover")*16+flag(UnitIsUnit,"mouseover","player")*64+flag(UnitIsVisible,"mouseover")*256+flag(UnitIsUnit,"mouseover","target")*1024+G.code(humanoid("mouseover"))*4096
    local casting,blocked,name,id,startMs,endMs=publicCast("mouseover",false)
    local channeling,channelBlocked,channelName,channelID,channelStart,channelEnd=publicCast("mouseover",true)
    local current,channel
    if casting==true then current=true;channel=false
    elseif channeling==true then current=true;channel=true;blocked=channelBlocked;name=channelName;id=channelID;startMs=channelStart;endMs=channelEnd
    elseif casting==false and channeling==false then current=false
    else current=state.active;channel=state.channel;if channel==true then blocked=channelBlocked end end
    if current==true and state.active~=true then state.sequence=(state.sequence+1)%65536 end
    state.active=current;state.channel=channel
    local lead=math.max(350,200+2*math.max(50,math.min(1000,S.updateRateMs or 100)))
    local remaining=4294967295;local now=S.readableCall(GetTime)
    if current==true and not S.isSecret(startMs) and not S.isSecret(endMs) and type(startMs)=="number" and type(endMs)=="number" and type(now)=="number" and startMs==startMs and endMs==endMs and endMs>startMs and startMs<=now*1000 and endMs-now*1000<=86400000 then remaining=math.max(0,math.floor(endMs-now*1000)) end
    if current==true then
        if S.isSecret(id) or type(id)~="number" then id=state.eventID end
        if S.isSecret(name) or type(name)~="string" then name=id and S.readableCall(S.spellAPI.GetSpellName,id) or nil end
    else id=nil;name=nil end
    if S.isSecret(id) or type(id)~="number" or id<=0 or id~=math.floor(id) then id=0 end
    if S.isSecret(name) or type(name)~="string" then name="" end
    name=name:sub(1,32)
    local function binding(spec)
        local M=S.managedSpells;local e=M and M.entries["PALADIN:"..(spec.managedName or spec.name)]
        return S.bindingsValid and e and M.current(e) and e.id==target.id and e.unit==(spec.unit or "target") and S.compactBindingCode(e.key) or 0
    end
    local spellFlags=G.code(target.learned)+G.code(target.usable)*4+G.code(target.mana)*16+G.code(target.ready)*64
    local use=S.spellUseCode(targetSpec.key)+S.spellUseCode(hoverSpec.key)*4
    local hoverClock,assigned=extraHoverClock(state,current,channel)
    local bandageA=extraPublicAura("player",11196,"Recently Bandaged","HARMFUL")
    local bandageB=extraPublicAura("player",1305047,"Recently Bandaged","HARMFUL")
    local bandage
    if bandageA.value==true or bandageB.value==true then bandage={status="observed",value=true}
    elseif bandageA.status=="observed" and bandageB.status=="observed" then bandage={status="observed",value=false}
    else bandage={} end
    local auraProof=extraNativeAuras(state)+G.code(extraPublicAura("target",20066,"Repentance","HARMFUL"))+4*G.code(bandage)
    local packet="HHK2"..S.bytes(S.setupSession,4)..S.bytes(tick,4)..S.bytes(S.auraGeneration,1)..S.bytes(S.setupRevision or 0,4)..S.bytes(target.id,4)..S.bytes(binding(targetSpec),2)..S.bytes(binding(hoverSpec),2)..S.bytes(use,1)..S.bytes(spellFlags,1)..S.bytes(G.code(target.range)+G.code(hover.range)*4,1)..S.bytes(G.code(humanoid("target")),1)..S.bytes(state.generation,4)..S.bytes(flags,2)..S.bytes(current==true and 2 or current==false and 1 or 0,1)..S.bytes(channel==true and 2 or channel==false and 1 or 0,1)..S.bytes(state.sequence,2)..S.bytes(id,4)..S.bytes(lead,2)..S.bytes(remaining,4)..S.bytes(hoverClock.status,1)..S.bytes(assigned and 1 or 0,1)..S.bytes(hoverClock.value,4)..S.bytes(auraProof,1)..S.bytes(#identity,1)..identity..S.bytes(#name,1)..name
    packet=packet..S.bytes(S.adler32(packet),4);assert(#packet<=134,"alternate interrupt source capacity exceeded")
    for _,p in ipairs(state.auraSignals) do R.paintColor(p,0,.25,1,1) end
    for _,p in ipairs(state.cells) do R.paintColor(p,1,.65,0,1) end
    local function nativeRange(offset,spec,unit,rangeOK,rangeRaw,usableOK,usableRaw,manaRaw,rangeSource,usableSource)
        local cells={state.cells[offset],state.cells[offset+1],state.cells[offset+2],state.cells[offset+3]}
        local a,b=R.render(cells,target.id,unit,rangeOK,rangeRaw,usableOK,usableRaw,manaRaw,rangeSource,usableSource)
        R.paintColor(cells[2],a and 0 or 1,a and 1 or .65,a and 1 or 0,1);R.paintFlag(cells[4],b)
    end
    nativeRange(2,targetSpec,"target",trOK,tr,tuOK,tu,tm,trSource,tuSource)
    nativeRange(6,hoverSpec,"mouseover",hrOK,hr,huOK,hu,hm,hrSource,huSource)
    pcall(function()
        if not state.readyCurve then local c=C_CurveUtil.CreateColorCurve();c:SetType(Enum.LuaCurveType.Step);c:AddPoint(0,CreateColor(0,1,0,1));c:AddPoint(.000001,CreateColor(.2,.2,.2,1));state.readyCurve=c end
        local duration=C_Spell.GetSpellCooldownDuration(target.id,false);local color=duration:EvaluateRemainingDuration(state.readyCurve);state.cells[1]:SetVertexColor(color:GetRGBA())
    end)
    if current==true then
        pcall(R.paintBoolean,state.cells[10],blocked,{.2,.2,.2,1},{0,1,0,1})
        if channel==true then R.paintColor(state.cells[11],0,1,0,1)
        elseif channel==false then
            if remaining~=4294967295 then R.paintFlag(state.cells[11],remaining>0 and remaining<=lead)
            else pcall(function()
                if state.windowLead~=lead then local c=C_CurveUtil.CreateColorCurve();c:SetType(Enum.LuaCurveType.Step);c:AddPoint(0,CreateColor(.2,.2,.2,1));c:AddPoint(.000001,CreateColor(0,1,0,1));c:AddPoint(lead/1000+.000001,CreateColor(.2,.2,.2,1));state.windowCurve=c;state.windowLead=lead end
                local duration=UnitCastingDuration("mouseover");local color=duration:EvaluateRemainingDuration(state.windowCurve);state.cells[11]:SetVertexColor(color:GetRGBA())
            end) end
        end
    end
    local checksum=S.adler32(packet:sub(1,-5))
    for i,p in ipairs(state.stamp) do local c=math.floor(checksum/256^(i-1))%256/255;R.paintColor(p,c,c,c,1) end
    return packet
end
-- Public cast identity is shared by every class. The restricted interruptibility
-- flag stays native; its checksum stamp joins it to this exact packet.
function I.packet(tick,body)
    local S=ns.state
    -- Keep the HHG7 body unchanged. HHE2 alone adds cast type, timing lead,
    -- and optional public remaining milliseconds; restricted timing stays native.
    local packet="HHE2"..S.bytes(S.setupSession,4)..S.bytes(tick,4)..S.bytes(S.auraGeneration,1)..body..I.timingBytes
    local checksum=S.adler32(packet)
    for i,p in ipairs(I.stamp or {}) do local c=math.floor(checksum/256^(i-1))%256/255;p:SetColorTexture(c,c,c,1) end
    return packet..S.bytes(checksum,4)
end
function I.bytes()
    local S=ns.state
    local function query(fn,isChannel)
        if type(fn)~="function" then return nil end
        local values={pcall(fn,"target")}
        if values[1]~=true then return nil end
        local name=values[2]
        if S.isSecret(name) then return nil,values[isChannel and 8 or 9],nil,values[isChannel and 9 or 10],values[5],values[6] end
        return name~=nil,values[isChannel and 8 or 9],name,values[isChannel and 9 or 10],values[5],values[6]
    end
    local casting,blocked,name,id,startMs,endMs=query(UnitCastingInfo,false)
    local channelling,channelBlocked,channelName,channelID,channelStart,channelEnd=query(UnitChannelInfo,true)
    local current
    if casting==true then current=true;channel=false
    elseif channelling==true then current=true;channel=true;blocked=channelBlocked;name=channelName;id=channelID;startMs=channelStart;endMs=channelEnd
    elseif casting==false and channelling==false then current=false;channel=nil
    else current=active;if channel then blocked=channelBlocked end end
    if current==true and active~=true then sequence=(sequence+1)%65536 end
    active=current
    local lead=math.max(350,200+2*math.max(50,math.min(1000,S.updateRateMs or 100)))
    local remaining=4294967295
    local now=S.readableCall(GetTime)
    if current==true and not S.isSecret(startMs) and not S.isSecret(endMs) and type(startMs)=="number" and type(endMs)=="number" and type(now)=="number" and startMs==startMs and endMs==endMs and endMs>startMs and startMs<=now*1000 and endMs-now*1000<=86400000 then
        remaining=math.max(0,math.floor(endMs-now*1000))
    end
    if I.window then
        ns.features.RangeTracking.paintColor(I.window,1,.65,0,1)
        if current==true and channel==false then
            if remaining~=4294967295 then
                if remaining==0 then ns.features.RangeTracking.paintColor(I.window,1,0,0,1)
                elseif remaining<=lead then ns.features.RangeTracking.paintColor(I.window,0,1,0,1)
                else ns.features.RangeTracking.paintColor(I.window,.2,.2,.2,1) end
            else pcall(function()
                if I.windowLead~=lead then
                    local curve=C_CurveUtil.CreateColorCurve();curve:SetType(Enum.LuaCurveType.Step)
                    curve:AddPoint(0,CreateColor(1,0,0,1));curve:AddPoint(.0001,CreateColor(0,1,0,1));curve:AddPoint(lead/1000+.0001,CreateColor(.2,.2,.2,1))
                    I.windowCurve=curve;I.windowLead=lead
                end
                local duration=UnitCastingDuration("target")
                local color=duration:EvaluateRemainingDuration(I.windowCurve)
                I.window:SetVertexColor(color:GetRGBA())
            end) end
        end
    end
    I.timingBytes=S.bytes(current==true and (channel==true and 2 or channel==false and 1 or 0) or 0,1)..S.bytes(lead,2)..S.bytes(remaining,4)
    if I.dot then
        local ok,painted=pcall(function()
            if current~=true then return false end
            return ns.features.RangeTracking.paintBoolean(I.dot,blocked,{.2,.2,.2,1},{0,1,0,1})
        end)
        if not ok or painted~=true then ns.features.RangeTracking.paintColor(I.dot,1,.65,0,1) end
    end
    if current==true then
        if S.isSecret(id) or type(id)~="number" then id=eventID end
        if S.isSecret(name) or type(name)~="string" then name=eventName end
    else name=nil;id=nil end
    if S.isSecret(id) or type(id)~="number" or id<=0 or id~=math.floor(id) then id=0 end
    if S.isSecret(name) or type(name)~="string" then name="" end
    name=string.sub(name,1,32)
    return S.bytes(id,4)..S.bytes(#name,1)..name..S.bytes(current==true and 2 or current==false and 1 or 0,1)..S.bytes(sequence,2)
end
