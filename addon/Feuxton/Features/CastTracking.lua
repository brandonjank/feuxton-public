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

-- Shared public UI rejection feedback. UI_ERROR_MESSAGE contains no spell ID:
-- the optional spell association below is only a short temporal join with an
-- explicit player FAILED event. The app must also own the matching attempt.
local feedbackDefinitions
local categoryGlobals={
    {1,{"LE_GAME_ERR_OUT_OF_RANGE","LE_GAME_ERR_SPELL_FAILED_OUT_OF_RANGE"},{"SPELL_FAILED_OUT_OF_RANGE","ERR_OUT_OF_RANGE","ERR_SPELL_OUT_OF_RANGE"}},
    {2,{"LE_GAME_ERR_BADATTACKPOS","LE_GAME_ERR_BADATTACKFACING","LE_GAME_ERR_SPELL_FAILED_NOT_BEHIND","LE_GAME_ERR_SPELL_FAILED_UNIT_NOT_INFRONT"},{"SPELL_FAILED_UNIT_NOT_INFRONT","SPELL_FAILED_NOT_BEHIND","ERR_BADATTACKFACING","ERR_BADATTACKPOS"}},
    {3,{"LE_GAME_ERR_SPELL_FAILED_LINE_OF_SIGHT","LE_GAME_ERR_LINE_OF_SIGHT"},{"SPELL_FAILED_LINE_OF_SIGHT"}},
    {4,{"LE_GAME_ERR_INVALID_ATTACK_TARGET","LE_GAME_ERR_SPELL_FAILED_BAD_TARGETS","LE_GAME_ERR_SPELL_FAILED_TARGETS_DEAD","LE_GAME_ERR_SPELL_FAILED_TARGET_NOT_DEAD","LE_GAME_ERR_SPELL_FAILED_TARGET_CREATURETYPE"},{"SPELL_FAILED_BAD_TARGETS","SPELL_FAILED_TARGETS_DEAD","SPELL_FAILED_TARGET_NOT_DEAD","SPELL_FAILED_TARGET_NOT_PLAYER","SPELL_FAILED_TARGET_IS_PLAYER","SPELL_FAILED_TARGET_CREATURETYPE","SPELL_FAILED_TARGET_NOT_UNDEAD","SPELL_FAILED_TARGET_NOT_UNDEAD_OR_DEMON","ERR_INVALID_ATTACK_TARGET"}},
    {5,{"LE_GAME_ERR_SPELL_FAILED_IMMUNE","LE_GAME_ERR_ATTACK_IMMUNE"},{"SPELL_FAILED_IMMUNE","ERR_ATTACK_IMMUNE_S"}},
    {6,{"LE_GAME_ERR_OUT_OF_MANA","LE_GAME_ERR_OUT_OF_RAGE","LE_GAME_ERR_OUT_OF_ENERGY","LE_GAME_ERR_OUT_OF_FOCUS","LE_GAME_ERR_SPELL_FAILED_NO_POWER"},{"SPELL_FAILED_NO_POWER","ERR_OUT_OF_MANA","ERR_OUT_OF_RAGE","ERR_OUT_OF_ENERGY","ERR_OUT_OF_FOCUS"}},
    {7,{"LE_GAME_ERR_SPELL_COOLDOWN","LE_GAME_ERR_SPELL_FAILED_NOT_READY"},{"SPELL_FAILED_NOT_READY","ERR_SPELL_COOLDOWN"}},
    {8,{"LE_GAME_ERR_SPELL_IN_PROGRESS","LE_GAME_ERR_SPELL_FAILED_SPELL_IN_PROGRESS"},{"SPELL_FAILED_SPELL_IN_PROGRESS","ERR_SPELL_IN_PROGRESS"}},
    {9,{"LE_GAME_ERR_SPELL_FAILED_INTERRUPTED"},{"SPELL_FAILED_INTERRUPTED"}},
}
local function feedbackNumber(value,minimum,maximum)
    if ns.state.isSecret(value) or type(value)~="number" or value~=value or value<minimum or value>maximum or value~=math.floor(value) then return nil end
    return value
end
local function feedbackText(value)
    if ns.state.isSecret(value) or type(value)~="string" or value=="" or #value>200 then return nil end
    return value
end
local function definitions()
    if feedbackDefinitions then return feedbackDefinitions end
    local values={codes={},texts={}}
    local function add(map,key,category)
        if key~=nil then if map[key]~=nil and map[key]~=category then map[key]=false else map[key]=category end end
    end
    for _,row in ipairs(categoryGlobals) do
        for _,name in ipairs(row[2]) do add(values.codes,feedbackNumber(ns.state.readableCall(function()return _G[name]end),1,65535),row[1]) end
        for _,name in ipairs(row[3]) do add(values.texts,feedbackText(ns.state.readableCall(function()return _G[name]end)),row[1]) end
    end
    feedbackDefinitions=values;return values
end
local function feedbackCategory(code,text)
    local known=definitions();local a=code and known.codes[code];local b=text and known.texts[text]
    if a and b and a~=b then return 0 end
    return a or b or 0
end
local function feedbackAdvance(state) state.sequence=((state.sequence or 0)+1)%65536 end
function P.newFeedbackState() return {sequence=0,registered=P.feedbackRegistered==true} end
local function feedbackJoin(state,now,generation)
    local event,failed=state.error,state.failed
    if not event or (event.category==0 and event.code==0) or event.associated or not failed or event.generation~=generation or failed.generation~=generation then return end
    local gap=math.abs(event.at-failed.at)
    if gap>.2 or now-event.at<0 or now-failed.at<0 then return end
    event.associated=true;event.id=failed.id;event.targetGeneration=generation
    -- A reason may arrive one update before FAILED. Publish a new revision
    -- when that same reason gains its explicitly marked temporal association.
    feedbackAdvance(state);event.sequence=state.sequence
end
function P.feedbackEvent(state,event,unit,a,b,c)
    if not state then return end
    local S=ns.state
    if event=="PLAYER_ENTERING_WORLD" or event=="PLAYER_DEAD" or event=="PLAYER_TARGET_CHANGED" then
        state.failed=nil;state.error=nil;state.sent=nil
        if event=="PLAYER_ENTERING_WORLD" then feedbackDefinitions=nil end
        return
    end
    local now=S.readableCall(GetTime)
    local generation=feedbackNumber(S.auraGeneration,0,255)
    if type(now)~="number" or now~=now or now<0 or now>=4294967296 or not generation then state.failed=nil;state.error=nil;return end
    if event=="UI_ERROR_MESSAGE" then
        local code=feedbackNumber(unit,1,65535);local text=feedbackText(a)
        local category=feedbackCategory(code,text)
        if not code and category==0 then return end
        feedbackAdvance(state)
        state.error={at=now,generation=generation,code=code or 0,category=category,sequence=state.sequence}
        feedbackJoin(state,now,generation)
        return
    end
    if S.isSecret(unit) or unit~="player" then
        if event=="UNIT_SPELLCAST_FAILED" then state.failed=nil end
        return
    end
    if event=="UNIT_SPELLCAST_SENT" then
        state.failed=nil;state.error=nil
        state.sent={at=now,id=feedbackNumber(c,1,2147483647),guid=feedbackText(b),generation=generation}
    elseif event=="UNIT_SPELLCAST_START" or event=="UNIT_SPELLCAST_CHANNEL_START" then
        state.failed=nil;state.error=nil
    elseif event=="UNIT_SPELLCAST_SUCCEEDED" then
        state.failed=nil;state.error=nil;state.sent=nil
    elseif event=="UNIT_SPELLCAST_FAILED" then
        local id=feedbackNumber(b,1,2147483647);local guid=feedbackText(a)
        if not id then state.failed=nil;return end
        local sent=state.sent
        if sent and (sent.generation~=generation or sent.id and sent.id~=id or sent.guid and guid and sent.guid~=guid) then state.failed=nil;return end
        state.failed={at=now,id=id,guid=guid,generation=generation}
        feedbackJoin(state,now,generation)
    elseif event=="UNIT_SPELLCAST_INTERRUPTED" then state.failed=nil;state.error=nil end
end
function P.feedbackPacket(tick,now)
    local S=ns.state;local state=P.currentFeedback
    if S.isSecret(now) or type(now)~="number" or now~=now or now<0 or now>=4294967296 then now=S.readableCall(GetTime) end
    if type(now)~="number" or now~=now or now<0 or now>=4294967296 then now=nil end
    local event=state and state.registered and state.error
    local age=type(now)=="number" and event and now-event.at or nil
    if not age or age<0 then event=nil end
    local registered=state and state.registered==true
    local sequence,code,category,id,generation,ageMs,flags=0,0,0,0,0,65535,registered and 1 or 0
    if event then
        sequence=event.sequence;code=event.code;category=event.category
        ageMs=math.min(65534,math.floor(age*1000));flags=flags+(category>0 and 2 or 0)
        if event.associated then id=event.id;generation=event.targetGeneration;flags=flags+4 end
    end
    local packet="HHJ1"..S.bytes(S.setupSession,4)..S.bytes(tick,4)..S.bytes(sequence,2)..S.bytes(code,2)..S.bytes(category,1)..S.bytes(id,4)..S.bytes(generation,1)..S.bytes(ageMs,2)..S.bytes(flags,1)
    return packet..S.bytes(S.adler32(packet),4)
end
