-- Target cast activity plus a native interruptibility flag. Restricted values
-- only reach supported native color rendering; Lua never branches on them.
local _,ns=...
local I={};ns.features.Interrupts=I
local active,channel,sequence=nil,nil,0
local eventID,eventName
local castActivity
function I.initialize()
    local S=ns.state
    castActivity=ns.features.CastTracking.newActivityState()
    local dot=S.resourcePanel:CreateTexture(nil,"OVERLAY")
    dot:SetSize(8,8);dot:SetPoint("TOPLEFT",616,-4);I.dot=dot
    I.window=S.hud:CreateTexture(nil,"OVERLAY");I.window:SetSize(4,4);I.window:SetPoint("TOPLEFT",540,-2)
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
        I.window:SetColorTexture(1,.65,0,1)
        if current==true and channel==false then
            if remaining~=4294967295 then
                if remaining==0 then I.window:SetColorTexture(1,0,0,1)
                elseif remaining<=lead then I.window:SetColorTexture(0,1,0,1)
                else I.window:SetColorTexture(.2,.2,.2,1) end
            else pcall(function()
                if I.windowLead~=lead then
                    local curve=C_CurveUtil.CreateColorCurve();curve:SetType(Enum.LuaCurveType.Step)
                    curve:AddPoint(0,CreateColor(1,0,0,1));curve:AddPoint(.0001,CreateColor(0,1,0,1));curve:AddPoint(lead/1000+.0001,CreateColor(.2,.2,.2,1))
                    I.windowCurve=curve;I.windowLead=lead
                end
                local duration=UnitCastingDuration("target")
                local color=duration:EvaluateRemainingDuration(I.windowCurve)
                I.window:SetColorTexture(color:GetRGBA())
            end) end
        end
    end
    I.timingBytes=S.bytes(current==true and (channel==true and 2 or channel==false and 1 or 0) or 0,1)..S.bytes(lead,2)..S.bytes(remaining,4)
    if I.dot then
        I.dot:SetColorTexture(1,1,1,1)
        local ok,painted=pcall(function()
            if current~=true then return false end
            return ns.features.RangeTracking.paintBoolean(I.dot,blocked,{.2,.2,.2,1},{0,1,0,1})
        end)
        if not ok or painted~=true then I.dot:SetVertexColor(1,1,1,1);I.dot:SetColorTexture(1,.65,0,1) end
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
