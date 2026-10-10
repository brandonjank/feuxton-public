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
function I.bytes()
    local S=ns.state
    local function query(fn,isChannel)
        if type(fn)~="function" then return nil end
        local values={pcall(fn,"target")}
        if values[1]~=true then return nil end
        local name=values[2]
        if S.isSecret(name) then return nil,values[isChannel and 8 or 9],nil,values[isChannel and 9 or 10] end
        return name~=nil,values[isChannel and 8 or 9],name,values[isChannel and 9 or 10]
    end
    local casting,blocked,name,id=query(UnitCastingInfo,false)
    local channelling,channelBlocked,channelName,channelID=query(UnitChannelInfo,true)
    local current
    if casting==true then current=true;channel=false
    elseif channelling==true then current=true;channel=true;blocked=channelBlocked;name=channelName;id=channelID
    elseif casting==false and channelling==false then current=false
    else current=active;if channel then blocked=channelBlocked end end
    if current==true and active~=true then sequence=(sequence+1)%65536 end
    active=current
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
