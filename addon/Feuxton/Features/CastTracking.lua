-- Spell mana budgets. Costs stay paired with the currently resolved spell rank.
local _,ns=...
local P={};ns.features.CastTracking=P
local function fraction(id,known)
    local S=ns.state
    if known~=true or type(id)~="number" or id<=0 then return 255 end
    local maximum=S.readableCall(UnitPowerMax,"player",0)
    if type(maximum)~="number" or maximum<=0 then return 255 end
    local api=S.spellAPI.GetSpellPowerCost or GetSpellPowerCost
    if type(api)~="function" then return 255 end
    local ok,costs=pcall(api,id)
    if not ok or S.isSecret(costs) then return 255 end
    -- API documents nil for a resolved spell without resource costs.
    if costs==nil then return 0 end
    if type(costs)~="table" then return 255 end
    local total=0
    for _,entry in ipairs(costs) do
        local power=S.safeField(entry,"type")
        if type(power)~="number" then return 255 end
        if power==0 then
            local cost=S.safeField(entry,"cost")
            local perSecondOK,perSecond=pcall(function()return entry.costPerSec end)
            if not perSecondOK or S.isSecret(perSecond) then return 255 end
            local minimum=S.safeField(entry,"minCost")
            -- Variable / per-second costs cannot be bounded by an upfront cost.
            if type(cost)~="number" or cost<0 or (perSecond~=nil and (type(perSecond)~="number" or perSecond~=0)) or (minimum~=nil and (type(minimum)~="number" or minimum>cost)) then return 255 end
            total=total+cost
        end
    end
    return math.min(254,math.ceil(total/maximum*200))
end
P.manaFraction=fraction

-- Public cast events can include failed attempts at OTHER spells while a cast
-- is still active. Keep identity so those failures cannot erase its activity.
function P.newActivityState() return {serial=0} end
local function advanceActivity(state) state.serial=((state.serial or 0)+1)%4294967296 end
local function publicValue(value,kind)
    if ns.state.isSecret(value) or type(value)~=kind then return nil end
    if kind=="string" and value=="" then return nil end
    if kind=="number" and (value<=0 or value~=math.floor(value)) then return nil end
    return value
end
function P.activityEvent(state,event,guid,id)
    guid=publicValue(guid,"string");id=publicValue(id,"number")
    if event=="PLAYER_ENTERING_WORLD" or event=="PLAYER_DEAD" then
        advanceActivity(state)
        state.cast=nil;state.channel=nil;state.mode=nil;state.guid=nil;state.id=nil;return true
    end
    if event=="UNIT_SPELLCAST_START" or event=="UNIT_SPELLCAST_CHANNEL_START" then
        advanceActivity(state)
        state.mode=event=="UNIT_SPELLCAST_START" and "cast" or "channel"
        state.cast=state.mode=="cast";state.channel=state.mode=="channel"
        state.guid=guid;state.id=id;return true
    end
    if not state.mode then
        if event=="UNIT_SPELLCAST_STOP" or event=="UNIT_SPELLCAST_CHANNEL_STOP" then
            if state.cast~=nil or state.channel~=nil then advanceActivity(state) end
            state.cast=nil;state.channel=nil;return true
        end
        return false
    end
    if event=="UNIT_SPELLCAST_SUCCEEDED" and state.mode=="channel" then return false end
    if event=="UNIT_SPELLCAST_STOP" and state.mode~="cast" then return false end
    if event=="UNIT_SPELLCAST_CHANNEL_STOP" and state.mode~="channel" then return false end
    local matches
    if guid and state.guid then matches=guid==state.guid and (not id or not state.id or id==state.id)
    elseif id and state.id then matches=id==state.id end
    if matches==true then
        advanceActivity(state)
        state.cast=false;state.channel=false;state.mode=nil;state.guid=nil;state.id=nil;return true
    end
    -- Unidentified failure is not an end-of-cast observation. An unidentified
    -- STOP becomes unknown until a readable API poll resolves it.
    if matches==nil and (event=="UNIT_SPELLCAST_STOP" or event=="UNIT_SPELLCAST_CHANNEL_STOP") then
        advanceActivity(state)
        state[state.mode]=nil;state.mode=nil;state.guid=nil;state.id=nil;return true
    end
    return false
end
function P.activityFlag(state,fn,mode)
    if type(fn)~="function" then return state[mode] end
    local ok,name=pcall(fn,"player")
    if not ok or ns.state.isSecret(name) then return state[mode] end
    return name~=nil
end
-- Public identity from the current START lifecycle. A secret/new START clears
-- the previous ID; no retained receipt is treated as the current cast.
function P.activityIdentity()
    local state=P.currentActivity
    if not state then return 0,0 end
    if state.mode=="cast" and state.cast==true then return state.id or 0,2 end
    if state.mode=="channel" and state.channel==true then return state.id or 0,3 end
    if state.cast==false and state.channel==false then return 0,1 end
    return 0,0
end
-- A small independent lifecycle source joins diagnostic native timers to the
-- same completed main frame. It never supplies cast activity to execution.
function P.activityRecord()
    local id,kind=P.activityIdentity();local state=P.currentActivity
    return state and state.serial or 0,kind,id
end
function P.activityPacket()
    local S=ns.state;local serial,kind,id=P.activityRecord()
    local packet="PCS1"..S.bytes(S.setupSession,4)..S.bytes(serial,4)..S.bytes(kind,1)..S.bytes(id,4)
    return packet..S.bytes(S.adler32(packet),4)
end
