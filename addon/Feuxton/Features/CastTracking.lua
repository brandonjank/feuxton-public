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
function P.newActivityState() return {} end
local function publicValue(value,kind)
    if ns.state.isSecret(value) or type(value)~=kind then return nil end
    if kind=="string" and value=="" then return nil end
    if kind=="number" and (value<=0 or value~=math.floor(value)) then return nil end
    return value
end
function P.activityEvent(state,event,guid,id)
    guid=publicValue(guid,"string");id=publicValue(id,"number")
    if event=="PLAYER_ENTERING_WORLD" or event=="PLAYER_DEAD" then
        state.cast=nil;state.channel=nil;state.mode=nil;state.guid=nil;state.id=nil;return true
    end
    if event=="UNIT_SPELLCAST_START" or event=="UNIT_SPELLCAST_CHANNEL_START" then
        state.mode=event=="UNIT_SPELLCAST_START" and "cast" or "channel"
        state.cast=state.mode=="cast";state.channel=state.mode=="channel"
        state.guid=guid;state.id=id;return true
    end
    if not state.mode then
        if event=="UNIT_SPELLCAST_STOP" or event=="UNIT_SPELLCAST_CHANNEL_STOP" then state.cast=nil;state.channel=nil;return true end
        return false
    end
    if event=="UNIT_SPELLCAST_SUCCEEDED" and state.mode=="channel" then return false end
    if event=="UNIT_SPELLCAST_STOP" and state.mode~="cast" then return false end
    if event=="UNIT_SPELLCAST_CHANNEL_STOP" and state.mode~="channel" then return false end
    local matches
    if guid and state.guid then matches=guid==state.guid and (not id or not state.id or id==state.id)
    elseif id and state.id then matches=id==state.id end
    if matches==true then
        state.cast=false;state.channel=false;state.mode=nil;state.guid=nil;state.id=nil;return true
    end
    -- Unidentified failure is not an end-of-cast observation. An unidentified
    -- STOP becomes unknown until a readable API poll resolves it.
    if matches==nil and (event=="UNIT_SPELLCAST_STOP" or event=="UNIT_SPELLCAST_CHANNEL_STOP") then
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
