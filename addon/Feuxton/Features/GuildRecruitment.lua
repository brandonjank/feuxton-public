-- Public guild observations, one reused social macro and a private import box.
-- Only a native click can run PreClick/the macro. Timers/events never send.
local _,ns=...
local B={plates={},samples={},pending={},action=0,rosterDirty=true,configurationNonce=0}
ns.features.GuildRecruitment=B
local MAX=2147483647
local D=ns.features.GuildDiscovery
local M=ns.features.GuildMilestones
local H=ns.features.GuildRecruitmentHistory
local separator="\31"
local clubPrefix="@club:"
local function public(value)
    if type(issecretvalue)~="function" then return false end
    local ok,secret=pcall(issecretvalue,value);return ok and not secret
end
local function call(fn,...)
    if type(fn)~="function" then return nil end
    local ok,value=pcall(fn,...);if not ok or not public(value)then return nil end;return value
end
local function integer(value,maximum)
    return public(value)and type(value)=="number"and value>=0 and value==math.floor(value)and value<=(maximum or MAX)and value or nil
end
local function utf8(value,maximum,empty)
    if not public(value)or type(value)~="string"or #value>(maximum or 140)or not empty and #value==0 then return nil end
    local i=1;local visible=false
    while i<=#value do
        local a=value:byte(i);local count,code,minimum=1,a,0
        if a>=194 and a<=223 then count,code,minimum=2,a-192,128
        elseif a>=224 and a<=239 then count,code,minimum=3,a-224,2048
        elseif a>=240 and a<=244 then count,code,minimum=4,a-240,65536
        elseif a>=128 then return nil end
        if i+count-1>#value then return nil end
        for j=1,count-1 do local c=value:byte(i+j);if c<128 or c>191 then return nil end;code=code*64+c-128 end
        if code<minimum or code>1114111 or code>=55296 and code<=57343 or code<32 or code>=127 and code<=159 or code==124
            or code==173 or code>=1536 and code<=1541 or code==1564 or code==1757 or code==1807 or code==2192 or code==2193 or code==2274 or code==6158
            or code>=8203 and code<=8207 or code>=8232 and code<=8238 or code>=8288 and code<=8303 or code==65279 or code>=65529 and code<=65531
            or code==69821 or code==69837 or code>=78896 and code<=78911 or code>=113824 and code<=113827 or code>=119155 and code<=119162 or code==917505 or code>=917536 and code<=917631 then return nil end
        if code~=32 and code~=160 and code~=5760 and not(code>=8192 and code<=8202)and code~=8239 and code~=8287 and code~=12288 then visible=true end
        i=i+count
    end
    return (empty or visible)and value or nil
end
local function flag(v)return v==true and 2 or v==false and 1 or 0 end
local function now()local n=call(GetTime);return type(n)=="number"and n>=0 and n<math.huge and n or nil end
local function wall()return integer(call(GetServerTime))end
local function increment(v)return math.min(MAX,(integer(v)or 0)+1)end
local function retireTicket(at)
    if B.ticket or B.macroArmed then B.quarantine=math.max(B.quarantine or 0,(at or now()or 0)+2)end
    B.ticket=nil;B.candidateScan=nil
    if B.actionButton and call(InCombatLockdown)==false then
        B.actionButton:SetAttribute("type",nil);B.actionButton:SetAttribute("macrotext",nil);B.actionButton:SetAttribute("feuxton-action",nil);B.macroArmed=false
    end
end
local function validLedger(ledger)
    return type(ledger)=="table" and type(ledger.records)=="table" and type(ledger.names)=="table" and type(ledger.attempts)=="table"
end
local function historicalRealm(actor,guild,normalized,onlyNormalized)
    if not actor or not guild or onlyNormalized and not normalized then return nil,"unavailable" end
    local store=type(FeuxtonDB)=="table" and FeuxtonDB.guildRecruitment
    if not store then return nil,"none" end
    if type(store)~="table" or store.schema~=1 or type(store.scopes)~="table" then return nil,"unavailable" end
    -- The normalized name only confirms an existing exact owner key. Never
    -- create a second realm namespace or reuse history across actors or guilds.
    local guildPart=separator..guild..separator
    local suffix=guildPart..actor
    local match,invalid,otherActor
    for key,ledger in pairs(store.scopes) do
        if type(key)=="string" then
            local realm,guildName=key:match("^([^\31]+)\31([^\31]+)\31[^\31]+$")
            if guildName==guild and not onlyNormalized then otherActor=true end
            if key:sub(-#suffix)==suffix and (not onlyNormalized or realm and realm:gsub("%s","")==normalized) then
                local name=utf8(realm,96)
                if not name or name:sub(1,#clubPrefix)==clubPrefix then return nil,"unavailable" end
                if match then return nil,"ambiguous" end
                match,invalid=name,not validLedger(ledger)
            end
        end
    end
    if invalid then return nil,"unavailable" end
    return match,match and "unique" or otherActor and "unavailable" or "none"
end
local function playerRealm(actor,guild)
    if type(GetRealmName)=="function" then
        local ok,name=pcall(GetRealmName)
        if ok then
            if not public(name) then return nil end
            if name~=nil and name~="" then
                local realm=utf8(name,96)
                return realm and realm:sub(1,#clubPrefix)~=clubPrefix and realm or nil
            end
        end
    end
    if not actor then return nil end
    local normalized=utf8(call(GetNormalizedRealmName),96)
    if not normalized then return nil end
    guild=guild or utf8(call(GetGuildInfo,"player"),96)
    return historicalRealm(actor,guild,normalized,true)
end
local function probeText(fn,maximum,...)
    if type(fn)~="function" then return nil,"missing" end
    local ok,value=pcall(fn,...)
    if not ok then return nil,"failed" end
    if type(issecretvalue)~="function" then return nil,"unverified" end
    local verified,secret=pcall(issecretvalue,value)
    if not verified or type(secret)~="boolean" then return nil,"unverified" end
    if secret then return nil,"restricted" end
    if value==nil or value=="" then return nil,"empty" end
    local text=utf8(value,maximum)
    return text,text and "public" or "invalid"
end
local function probeGuildClub(guild)
    if not guild then return "unavailable" end
    local api=C_Club
    if type(api)~="table" or type(api.GetGuildClubId)~="function" or type(api.GetClubInfo)~="function" then return "missing" end
    if type(C_ChatInfo)~="table" or call(C_ChatInfo.InChatMessagingLockdown)~=false then return "unavailable" end
    local ok,id=pcall(api.GetGuildClubId)
    if not ok then return "failed" end
    if not public(id) then return "restricted" end
    if id==nil or id==0 then return "empty" end
    if not integer(id,9007199254740991) then return "invalid" end
    local guildType=call(function()return Enum.ClubType.Guild end)
    if type(guildType)~="number" then return "unavailable" end
    local info
    ok,info=pcall(api.GetClubInfo,id)
    if not ok then return "failed" end
    if not public(info) then return "restricted" end
    if info==nil then return "empty" end
    if type(info)~="table" then return "invalid" end
    local clubID,clubType,name=info.clubId,info.clubType,info.name
    if not public(clubID) or not public(clubType) or not public(name) then return "restricted" end
    if clubID~=id or clubType~=guildType or name~=guild then return "mismatch" end
    return "public",id
end
function B.realmProbe()
    if call(InCombatLockdown)~=false or call(UnitAffectingCombat,"player")~=false then return nil end
    local _,directState=probeText(GetRealmName,96)
    local normalized,normalizedState=probeText(GetNormalizedRealmName,96)
    local actor,actorState=probeText(UnitGUID,64,"player")
    local guild,guildState=probeText(GetGuildInfo,96,"player")
    local _,matchState=historicalRealm(actor,guild,normalized,true)
    return {v=2,direct=directState,normalized=normalizedState,actor=actorState,guild=guildState,match=matchState,club=probeGuildClub(guild)}
end
local function currentScope(actor,guild)
    if guild then
        local _,id=probeGuildClub(guild)
        if id then return clubPrefix..string.format("%.0f",id),nil,true end
    end
    local store=type(FeuxtonDB)=="table" and FeuxtonDB.guildRecruitment
    if type(store)=="table" then
        if store.clubActors~=nil and type(store.clubActors)~="table" or store.clubLegacy~=nil and type(store.clubLegacy)~="table" then return end
        -- Temporary club API loss must not reopen an older ledger for this owner.
        for _,actors in pairs(store.clubActors or {})do
            if type(actors)~="table" or actors[actor]~=nil then return end
        end
        for _,origin in pairs(store.clubLegacy or {})do
            if type(origin)~="table" or origin.guild==guild then return end
        end
    end
    local realm=playerRealm(actor,guild)
    return realm,realm,false
end
local function copySavedValue(value,depth)
    if type(value)~="table" then return value end
    if depth==0 then return nil end
    local result={}
    for key,entry in pairs(value) do
        if type(key)=="string" or type(key)=="number" then result[key]=copySavedValue(entry,depth-1) end
    end
    return result
end
local function newActorLedger(prior)
    local ledger={records={},names={},attempts={},totalInvites=0,totalJoins=0,totalDeclines=0}
    if prior then
        for _,key in ipairs({"attempts","lastAttempt","lastDelayMs","lastWhoAt","totalInvites","totalJoins","totalDeclines","statistics","milestones"})do
            if prior[key]~=nil then ledger[key]=copySavedValue(prior[key],4) end
        end
    end
    return ledger
end
local function clubLedger(store,scope,actor,guild)
    if store.clubActors~=nil and type(store.clubActors)~="table" or store.clubLegacy~=nil and type(store.clubLegacy)~="table" then return end
    local actors=store.clubActors and store.clubActors[scope]
    if actors~=nil and type(actors)~="table" then return end
    local legacy=store.clubLegacy and store.clubLegacy[scope]
    if legacy~=nil then
        if type(legacy)~="table" or not utf8(legacy.realm,96) or not utf8(legacy.guild,96) then return end
    elseif not actors then
        local realm,status=historicalRealm(actor,guild)
        if status~="unique" and status~="none" then return end
        if realm then
            for _,origin in pairs(store.clubLegacy or {})do
                if type(origin)~="table" or origin.realm==realm and origin.guild==guild then return end
            end
            legacy={realm=realm,guild=guild}
        end
    end
    local ledger=actors and actors[actor]
    if ledger==nil then
        local prior=legacy and store.scopes[legacy.realm..separator..legacy.guild..separator..actor]
        if prior~=nil and not validLedger(prior) then return end
        ledger=newActorLedger(prior)
    end
    return ledger,actors,legacy
end
local function readIdentity()
    local actor=utf8(call(UnitGUID,"player"),64)
    if not actor then return nil end
    local guild=utf8(call(GetGuildInfo,"player"),96)
    local scope,realm,club=currentScope(actor,guild)
    if scope then return {actor=actor,guild=guild,scope=scope,realm=realm,club=club} end
end
local function configurationContext(identity)
    if identity==nil then identity=readIdentity() end
    if not identity then return nil end
    local stamp=now();local session=integer(ns.state.setupSession,4294967295)
    if not stamp or not session or session==0 then return nil end
    local guild=identity.club and identity.guild or nil
    local owner=identity.scope..separator..(guild and guild..separator or "")..identity.actor..separator..session
    return {actor=identity.actor,scope=identity.scope,guild=guild,session=session,at=stamp,owner=owner}
end
-- Observe the native chat box without changing or hooking any Blizzard UI.
-- Only its standard name and boolean proofs leave this function, never text.
local function nativeChatState(t)
    local state={identity="",ordinary=false}
    local opener=call(GetBindingAction,"ENTER",true)
    if type(opener)=="string"then state.opener=opener=="OPENCHAT"end
    if type(GetCurrentKeyBoardFocus)~="function"then return state end
    local ok,focus=pcall(GetCurrentKeyBoardFocus)
    if not ok or not public(focus)then return state end
    if focus==nil then state.focus=false;state.ordinary=true;return state end
    state.focus=false
    local getter=ChatEdit_GetActiveWindow
    if type(getter)~="function"and type(ChatFrameUtil)=="table"then getter=ChatFrameUtil.GetActiveWindow end
    if call(getter)~=focus then return state end
    local name=call(function()return focus:GetName()end)
    if not utf8(name,32)or not name:match("^ChatFrame%d+EditBox$")or call(function()return focus:IsShown()end)~=true then return state end
    state.focus=true;state.identity=name
    local text=call(function()return focus:GetText()end)
    if type(text)=="string"then
        state.empty=text==""
        if t and(t.kind==1 or t.kind==5)then state.matches=text==(t.kind==5 and "/gpromote "or "/ginvite ")..t.name else state.matches=false end
    end
    return state
end
local function ownContext(identity)
    local G=ns.features.GroupContext
    if not G or type(G.names)~="function"then return nil end
    if identity==nil then identity=readIdentity() end
    -- A current positive self read is also the control for qualified nils.
    if not identity or not identity.guild then return nil end
    local actor,guild,scope,realm,club=identity.actor,identity.guild,identity.scope,identity.realm,identity.club
    local _,name=G.names("player",96);name=utf8(name,96)
    local stamp=now();local utc=wall();local session=integer(ns.state.setupSession,4294967295)
    if not scope or not name or not stamp or not utc or not session or session==0 then return nil end
    local key=scope..separator..guild..separator..actor
    if B.owner~=key or B.session~=session then
        retireTicket(stamp);B.owner=key;B.session=session;B.pending={};B.samples={};D.reset(key.."\31"..session);B.roster=nil;B.rosterScan=nil;B.rosterDirty=true;B.rosterRetryAt=nil;B.rosterRequested=nil;B.ledger=nil;B.ledgerMaintenance=nil
    end
    if type(FeuxtonDB)~="table"then return nil end
    local store=FeuxtonDB.guildRecruitment
    if store==nil then store={schema=1,scopes={}};FeuxtonDB.guildRecruitment=store end
    if type(store)~="table"or store.schema~=1 or type(store.scopes)~="table"then return nil end
    local ledger,actors,legacy
    if club then ledger,actors,legacy=clubLedger(store,scope,actor,guild)
    else
        ledger=store.scopes[key]
        if ledger==nil then ledger=newActorLedger();store.scopes[key]=ledger end
    end
    if not validLedger(ledger) or #ledger.attempts>10 then return nil end
    local attempts={}
    for _,at in ipairs(ledger.attempts)do if not integer(at)then return nil end;if utc-at<60 then attempts[#attempts+1]=at end end
    local historyContext={actor=actor,name=name,guild=guild,scope=scope,realm=realm,club=club,session=session,at=stamp,utc=utc,ledger=ledger,
        legacyRealm=legacy and legacy.realm,legacyGuild=legacy and legacy.guild}
    if not H.attach(store,historyContext,utf8,B.configuration and B.configuration.reinviteHours or 72)then return nil end
    if club and not (actors and actors[actor]) then
        if not store.clubActors then store.clubActors={} end
        if not actors then actors={};store.clubActors[scope]=actors end
        actors[actor]=ledger
        if legacy then
            if not store.clubLegacy then store.clubLegacy={} end
            store.clubLegacy[scope]=legacy
        end
    end
    if B.ledger~=ledger or not B.ledgerMaintenance or stamp-B.ledgerMaintenance>=5 then
        local count=0
        for guid,row in pairs(ledger.records)do
            if type(row)~="table"or not integer(row.untilAt)then return nil end
            if row.untilAt<=utc then ledger.records[guid]=nil;if ledger.names[row.name]==guid then ledger.names[row.name]=nil end else count=count+1 end
        end
        B.ledger=ledger;B.recordCount=count;B.ledgerMaintenance=stamp;H.count=count;H.full=count>=H.limit
    end
    ledger.attempts=attempts
    historyContext.recordCount=B.recordCount or 0
    return historyContext
end
local function permissions()
    local invite=call(CanGuildInvite)
    local chat;if type(C_GuildInfo)=="table"then chat=call(C_GuildInfo.CanSpeakInGuildChat)end
    if type(invite)~="boolean"then invite=nil end;if type(chat)~="boolean"then chat=nil end
    local lockdown;if type(C_ChatInfo)=="table"then lockdown=call(C_ChatInfo.InChatMessagingLockdown)end
    if chat==true then
        if type(lockdown)~="boolean"then chat=nil
        elseif lockdown~=false then chat=false end
    end
    return invite,chat
end
local function movement()
    if type(IsPlayerMoving)=="function"then
        local ok,value=pcall(IsPlayerMoving)
        if ok and not public(value)then return nil end
        if ok and type(value)=="boolean"then return value end
    end
    -- Same public legacy fallback as RangeTracking.movement; restricted raw
    -- movement is not replaced with guessed inactivity.
    local speed=call(GetUnitSpeed,"player")
    if type(speed)=="number"and speed>=0 and speed<math.huge then return speed>0 end
end
local function safety(context,configuration,kind,grant)
    if not context then return false end
    if kind~=0 then
        local invite,chat=permissions();if chat~=true or(kind==1 or kind==3)and invite~=true or kind==5 and call(CanGuildPromote)~=true then return false end
        if type(C_ChatInfo)~="table"or call(C_ChatInfo.InChatMessagingLockdown)~=false or type(C_ChatInfo.SendChatMessage)~="function"or type(C_GuildInfo)~="table"then return false end
    end
    local taxi=call(UnitOnTaxi,"player")
    if taxi~=true and taxi~=false then return false end
    if call(InCombatLockdown)~=false or call(UnitAffectingCombat,"player")~=false or call(UnitIsDeadOrGhost,"player")~=false or taxi==false and movement()~=false then return false end
    for _,name in ipairs({"UnitCastingInfo","UnitChannelInfo"})do
        local fn=_G[name]
        if type(fn)~="function"then return false end
        local ok,value=pcall(fn,"player");if not ok or not public(value)or value~=nil then return false end
    end
    local C=ns.features.Consumables
    if not C or type(C.recovery)~="function"then return false end
    local ok,eating,drinking=pcall(C.recovery)
    if not ok or not public(eating)or not public(drinking)or eating~=false or drinking~=false then return false end
    if type(GetCurrentKeyBoardFocus)~="function"then return false end
    local focusOK,focus=pcall(GetCurrentKeyBoardFocus)
    if not focusOK or not public(focus)then return false end
    if focus~=nil then
        if configuration and focus==B.editor then
            -- The dedicated import box has a separate owner/nonce protocol.
        elseif grant then
            local chat=nativeChatState(grant)
            if chat.focus~=true or chat.empty~=true and chat.matches~=true then return false end
        else return false end
    end
    return true
end
local function candidate(unit,context)
    if not utf8(unit,32)or call(UnitExists,unit)~=true or call(UnitIsPlayer,unit)~=true or call(UnitIsUnit,unit,"player")~=false or call(UnitCanAssist,"player",unit)~=true or call(UnitIsVisible,unit)~=true or call(UnitIsConnected,unit)~=true or call(UnitIsDeadOrGhost,unit)~=false then return nil end
    -- Discovery only needs a publicly visible player, not interaction range.
    -- CheckInteractDistance is protected during combat on Forever: even a
    -- pcall emits ADDON_ACTION_BLOCKED. Keep passive collection read-only.
    if unit~="target"and unit~="mouseover"and not unit:match("^nameplate%d+$")then return nil end
    local guid=utf8(call(UnitGUID,unit),64);local first,name=ns.features.GroupContext.names(unit,96);name=utf8(name,96)
    if not guid or guid==context.actor or not name then return nil end
    local ok,guild=pcall(GetGuildInfo,unit)
    if not ok or not public(guild)then return nil end
    if guild~=nil then B.samples[guid]=nil;D.remove(name);return nil end
    local isGuilded=call(UnitIsInGuild,unit)
    local guildless=isGuilded==false
    if isGuilded==true then D.remove(name);return nil end
    if not guildless then
        -- Owner-confirmed API contract, 2026-11-12: a successful public nil
        -- means no guild on every supported client build. The current unit,
        -- positive player-guild control and resolved stable identity remain
        -- required; missing/error/secret reads are never that successful nil.
        if not context.guild or type(GetPlayerInfoByGUID)~="function"then return {unit=unit,guid=guid,name=name,qualified=false}end
        local resolved=call(function()return select(6,GetPlayerInfoByGUID(guid))end)
        if not utf8(resolved,96)or resolved~=first and resolved~=name then return {unit=unit,guid=guid,name=name,qualified=false}end
        local sample=B.samples[guid]
        if not sample then
            local count=0;for key,row in pairs(B.samples)do if context.at-row.last>10 then B.samples[key]=nil else count=count+1 end end
            if count>=256 then return {unit=unit,guid=guid,name=name,qualified=false}end
        end
        if not sample or sample.name~=name or context.at-sample.last>10 then sample={name=name,first=context.at,count=0};B.samples[guid]=sample end
        sample.last=context.at;sample.count=sample.count+1
        guildless=sample.count>=2 and context.at-sample.first>=1
    end
    if call(UnitGUID,unit)~=guid or ns.features.GroupContext.fullName(unit,96)~=name then return nil end
    return {unit=unit,guid=guid,name=name,qualified=guildless}
end
local function candidateLevel(unit)
    local level=integer(call(UnitLevel,unit))
    return level and level>0 and level or nil
end
local function currentCandidate(t,context)
    return D.current(t,context,candidate,candidateLevel)
end
local function rosterMember(index)
    if type(GetGuildRosterInfo)~="function"then return nil end
    local ok,name,rankName,rank,level,_,_,_,_,online,_,_,_,_,_,_,_,guid=pcall(GetGuildRosterInfo,index)
    name=utf8(name,96);guid=utf8(guid,64)
    local onlineFlag;if public(online)and type(online)=="boolean"then onlineFlag=online end
    return ok and name and {name=name,guid=guid,index=index,rank=integer(rank,9),level=integer(level,100),online=onlineFlag}or nil
end
local function rosterStep(context,cfg)
    if B.requestRoster and (not B.rosterRequested or context.at-B.rosterRequested>=2)then
        B.requestRoster=false;B.rosterRequested=context.at
        if type(C_GuildInfo)=="table"and type(C_GuildInfo.GuildRoster)=="function"then pcall(C_GuildInfo.GuildRoster)end
    end
    if not B.rosterScan and B.rosterDirty and context.at>=(B.rosterRetryAt or 0) then
        B.rosterDirty=false
        local count=integer(call(GetNumGuildMembers),1000)
        if not count or count==0 then B.rosterDirty=true;B.rosterRetryAt=context.at+1;return end
        B.rosterScan={count=count,index=1,members={},onlineNames={},valid=true,at=context.at}
    end
    local scan=B.rosterScan;if not scan then return end
    for _=1,8 do
        if scan.index>scan.count then break end
        local member=rosterMember(scan.index);scan.index=scan.index+1
        local key=member and (member.guid or "name:"..member.name)
        if key and not scan.members[key] then
            scan.members[key]=member
            if context.club and member.online~=false then
                if not member.guid or scan.onlineNames[member.name] then scan.valid=false end
                scan.onlineNames[member.name]=true
            end
        else scan.valid=false end
    end
    if scan.index<=scan.count then return end
    B.rosterScan=nil
    if scan.count~=integer(call(GetNumGuildMembers),1000)or not scan.valid or context.club and not scan.members[context.actor] then
        B.rosterDirty=true;B.rosterRetryAt=context.at+1;return
    end
    B.rosterRetryAt=nil
    local initial=B.roster==nil;B.roster=scan.members;B.rosterAt=context.at
    if M then M.observe(context,B.roster,cfg and cfg.milestones)end
    if initial then return end -- initial login roster is never a join event
    for guid,pending in pairs(B.pending)do
        local member=scan.members[guid]
        if not member and guid:sub(1,5)=="name:"then
            for _,entry in pairs(scan.members)do if entry.name==pending.name then member=entry;pending.memberGUID=entry.guid;break end end
        end
        if pending.joinSeen and pending.invited and not pending.joined and member and member.name==pending.name and pending.joinAt and scan.at>=pending.joinAt then
            pending.joined=true;pending.joinedAt=context.at;context.ledger.totalJoins=increment(context.ledger.totalJoins)
            if not pending.statisticsConfirmed then pending.statisticsConfirmed=true;D.statistics(context,"confirmed")end
            D.statistics(context,"joins")
            local row=context.ledger.records[guid];if row then row.joined=true end
        end
    end
end
local function budget(context)
    local ledger=context.ledger
    if #ledger.attempts>=8 or context.recordCount>=2048 then return false end
    local delayMs=8000
    if ledger.lastDelayMs~=nil then
        delayMs=integer(ledger.lastDelayMs,12000)
        if not delayMs or delayMs<8000 then return false end
    end
    local last=integer(ledger.lastAttempt)
    if last and context.utc-last<6 then return false end
    if B.lastAttemptOwner==B.owner and type(B.lastAttemptMonotonic)=="number"then
        return context.at-B.lastAttemptMonotonic>=delayMs/1000
    end
    -- Persisted UTC is whole seconds. A cold owner/reload needs one extra
    -- second so its unknown subsecond phase cannot shorten the real gap.
    return not last or context.utc-last>=math.ceil(delayMs/1000)+1
end
local function suppressed(context,c)
    local function active(guid)
        local row=guid and context.ledger.records[guid]
        if not row then return false end
        if not integer(row.untilAt)then return true end
        if row.untilAt>context.utc then return true end
        context.ledger.records[guid]=nil
        if context.ledger.names[row.name]==guid then context.ledger.names[row.name]=nil end
        B.recordCount=math.max(0,(B.recordCount or 0)-1);context.recordCount=B.recordCount
        return false
    end
    local other=context.ledger.names[c.name]
    local result=active(c.guid)or active(other)
    if other and not context.ledger.records[other]then context.ledger.names[c.name]=nil end
    return result
end
local function decode64(value)
    if type(value)~="string"or #value==0 or #value>15764 or #value%4~=0 or value:find("[^A-Za-z0-9+/=]")then return nil end
    local alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";local digits={}
    for i=1,#alphabet do digits[alphabet:sub(i,i)]=i-1 end
    local out={}
    for index=1,#value,4 do
        local a,b,c,d=value:sub(index,index),value:sub(index+1,index+1),value:sub(index+2,index+2),value:sub(index+3,index+3)
        local x,y,z,w=digits[a],digits[b],digits[c],digits[d]
        if not x or not y or c=="="and(d~="="or index+3~=#value or y%16~=0)or d=="="and(index+3~=#value or c~="="and(not z or z%4~=0))or c~="="and not z or d~="="and not w then return nil end
        out[#out+1]=string.char(x*4+math.floor(y/16))
        if c~="="then out[#out+1]=string.char(y%16*16+math.floor(z/4))end
        if d~="="then out[#out+1]=string.char(z%4*64+w)end
    end
    local decoded=table.concat(out);return #decoded<=11823 and decoded or nil
end
local function template(value,milestone)
    value=utf8(value,120);if not value then return nil end
    local remainder=value:gsub("{player}",""):gsub("{guild}","");if milestone then remainder=remainder:gsub("{level}","")end
    return not remainder:find("[{}]")and value or nil
end
local function decodeConfiguration(raw)
    if type(raw)~="string"or #raw>11823 or #raw>=1 and raw:byte(1)~=4 or #raw>=2 and raw:byte(2)>2 then return nil end
    if #raw<8 then return nil,"incomplete" end
    local offset=3;local lists={}
    for kind=1,2 do
        local count=raw:byte(offset);offset=offset+1
        if not count then return nil,"incomplete" end
        if count<1 or count>32 then return nil end
        local list={}
        for i=1,count do
            local length=raw:byte(offset);offset=offset+1
            if not length then return nil,"incomplete" end
            if length<1 or length>120 then return nil end
            if offset+length-1>#raw then return nil,"incomplete" end
            local text=template(raw:sub(offset,offset+length-1));if not text then return nil end
            list[i]=text;offset=offset+length
        end
        lists[kind]=list
    end
    local flags=raw:byte(offset);offset=offset+1
    if not flags then return nil,"incomplete" end
    if flags>7 then return nil end
    if offset+3>#raw then return nil,"incomplete" end
    local generation=0;for i=0,3 do generation=generation+raw:byte(offset+i)*256^i end;offset=offset+4
    local ranks={}
    for _,level in ipairs({25,45,60})do
        local length=raw:byte(offset);offset=offset+1
        if not length then return nil,"incomplete" end
        if length>64 then return nil end
        if offset+length-1>#raw then return nil,"incomplete" end
        local name=raw:sub(offset,offset+length-1);offset=offset+length
        if length>0 and(not utf8(name,64)or name:find("[{}]")or name:match("^%s")or name:match("%s$"))then return nil end
        ranks[level]=name
    end
    local count=raw:byte(offset);offset=offset+1
    if not count then return nil,"incomplete" end
    if count<1 or count>32 then return nil end
    local messages={}
    for i=1,count do
        local length=raw:byte(offset);offset=offset+1
        if not length then return nil,"incomplete" end
        if length<1 or length>120 then return nil end
        if offset+length-1>#raw then return nil,"incomplete" end
        local text=template(raw:sub(offset,offset+length-1),true);if not text then return nil end
        messages[i]=text;offset=offset+length
    end
    if offset+1>#raw then return nil,"incomplete" end
    if offset+1<#raw then return nil end
    local hours=raw:byte(offset)+256*raw:byte(offset+1);if hours<1 or hours>720 then return nil end
    offset=offset+2
    if offset~=#raw+1 then return nil end
    return {canonical=raw,checksum=ns.state.adler32(raw),invite=lists[1],welcome=lists[2],whoScope=raw:byte(2),reinviteHours=hours,recruiting=flags>=4,milestones={generation=generation,enabled=flags%2==1,congratulate=math.floor(flags/2)%2==1,ranks=ranks,messages=messages}}
end
local function configuration()
    local store=type(FeuxtonDB)=="table"and FeuxtonDB.guildRecruitment
    local saved=type(store)=="table"and store.configuration
    local raw=type(saved)=="table"and saved.canonical
    if type(raw)~="string"then B.configuration=nil;B.configurationRaw=nil;return nil end
    if B.configurationRaw~=raw then B.configuration=decodeConfiguration(raw);B.configurationRaw=raw end
    return B.configuration
end
local function clearMacro()
    if B.actionButton and call(InCombatLockdown)==false then
        B.actionButton:SetAttribute("type",nil);B.actionButton:SetAttribute("macrotext",nil)
        B.actionButton:SetAttribute("feuxton-action",nil);B.macroArmed=false
    end
end
local function rejectOwnedAction(event,value,fn)
    local window=B.actionWindow;local at=now()
    if not window or not at or at>window.expires or window.session~=ns.state.setupSession or window.owner~=B.owner then return end
    local source
    if event=="MACRO_ACTION_BLOCKED"or event=="MACRO_ACTION_FORBIDDEN"then source="MACRO";fn=value
    else source=utf8(value,64)end
    fn=utf8(fn,128)
    if not source or not fn or source~=ns.addonName and source~="MACRO"and source~="UNKNOWN"then return end
    if not(fn:find("SendChatMessage",1,true)or fn:find("Guild",1,true)or fn:find("RunMacro",1,true)or fn=="UNKNOWN")then return end
    local record={event=event,source=source,functionName=fn,session=window.session,action=window.action,kind=window.kind,at=wall()or 0}
    B.lastRejection=record;B.blocked=true;B.routeRejected=true
    local store=type(FeuxtonDB)=="table"and FeuxtonDB.guildRecruitment
    if type(store)=="table"then
        if type(store.rejections)~="table"then store.rejections={}end
        store.rejections[#store.rejections+1]=record;while #store.rejections>16 do table.remove(store.rejections,1)end
    end
    local t=B.ticket
    if t and t.action==window.action and t.session==window.session then t.stage=0;t.status=6 end
    local pending=B.pending[window.guid];if pending then pending.authorized=false end
    B.quarantine=math.max(B.quarantine or 0,at+2);clearMacro()
end
local function configurationOutcome(outcome,length)
    B.configurationImport={v=1,outcome=outcome,length=math.min(16000,integer(length)or 0),ordinal=B.editorNonce}
    if outcome~="opened"and outcome~="settling"and ns.markSetupDirty then ns.markSetupDirty()end
end
function B.configurationProbe()
    return B.configurationImport
end
local function closeEditor(outcome,length)
    if not B.editor then return end
    if outcome and B.editorOwner then configurationOutcome(outcome,length)end
    B.editor:ClearFocus();B.editor:SetText("");B.editor:Hide()
    B.editorOwner=nil;B.editorNonce=nil;B.editorExpires=nil;B.editorSubmit=nil
end
local function editorFlags()
    if not B.editor or type(GetCurrentKeyBoardFocus)~="function"then return nil,nil end
    local ok,focus=pcall(GetCurrentKeyBoardFocus);if not ok or not public(focus)then return nil,nil end
    local owned=focus==B.editor and call(B.editor.IsShown,B.editor)==true
    if not owned then return false,nil end
    local text=call(B.editor.GetText,B.editor);if type(text)~="string"then return true,nil end;return true,text==""
end
local function keyCurrent(kind,key)
    local M=ns.state.managedSpells
    return M and M.auxiliaryCurrent and M.auxiliaryCurrent(kind=="action"and "guild.action"or "guild.configuration",kind=="action"and "FeuxtonGuildRecruitAction"or "FeuxtonGuildRecruitConfiguration",key)or false
end
local function macroText(t)
    return(t.kind==2 or t.kind==4 and t.claimReady)and "/stopmacro [combat][dead]\n/g "..t.message or nil
end
local function attributeMatches(button,key,expected)
    local ok,value=pcall(button.GetAttribute,button,key)
    return ok and public(value)and value==expected
end
local function macroCurrent(t,context)
    local button=B.actionButton
    return button and keyCurrent("action",B.actionKey)and attributeMatches(button,"type",macroText(t)and "macro"or nil)
        and attributeMatches(button,"macrotext",macroText(t))
        and call(button.GetAttribute,button,"feuxton-action")==t.action
        and call(button.GetAttribute,button,"feuxton-session")==context.session
        and call(button.GetAttribute,button,"feuxton-configuration")==t.configurationChecksum
        and call(button.GetAttribute,button,"feuxton-message")==t.messageChecksum
        and call(button.GetAttribute,button,"feuxton-nonce")==t.configurationNonce
end
local function beginOwnedAction(context,t)
    B.actionWindow={at=context.at,expires=math.min(t.expires,context.at+2),session=t.session,action=t.action,kind=t.kind,guid=t.guid,owner=B.owner}
end
local function welcomeCurrent(t)
    local pending=B.pending[t.guid];local member=B.roster and B.roster[pending and pending.memberGUID or t.guid];local current=member and rosterMember(member.index)
    return pending and pending.joined and not pending.welcomeReserved and current and current.guid==(pending.memberGUID or t.guid)and current.name==t.name
        and type(C_GuildInfo)=="table"and call(C_GuildInfo.MemberExistsByName,t.name)==true
end
local function clickAction(_,_,down)
    if down==false then return end
    local context=ownContext();local t=B.ticket;local cfg=configuration()
    if not context or not t or t.stage~=0 or t.status~=4 or B.routeRejected or not cfg or cfg.checksum~=t.configurationChecksum or t.owner~=B.owner or t.session~=context.session or context.at>=t.expires
        or B.quarantine and context.at<B.quarantine or not safety(context,false,t.kind)or not macroCurrent(t,context)then clearMacro();if t then t.stage=0;t.status=6 end;return end
    if t.kind==3 then
        if not t.who or cfg.whoScope~=t.who.scope or D.best(context,candidate,candidateLevel,suppressed,function(a,b)return a.name<b.name end)then clearMacro();t.status=6;return end
        t.status=D.sendWho(context,t.who,utf8)and 5 or 6
        B.quarantine=context.at+2;return
    end
    if t.kind==1 then
        local c=currentCandidate(t,context)
        if not c or not c.qualified or c.guid~=t.guid or c.name~=t.name or suppressed(context,c)or not budget(context)or not B.roster or nativeChatState(t).opener~=true then clearMacro();t.status=6;return end
        if not H.ready(context)or not H.reserve(context,c,cfg.reinviteHours)then clearMacro();t.status=6;return end
        beginOwnedAction(context,t)
        context.ledger.attempts[#context.ledger.attempts+1]=context.utc;context.ledger.lastAttempt=context.utc
        context.ledger.lastDelayMs=math.random(8000,12000)
        B.lastAttemptMonotonic=context.at;B.lastAttemptOwner=B.owner
        context.ledger.totalInvites=increment(context.ledger.totalInvites);D.statistics(context,"attempts")
        B.recordCount=H.count;context.recordCount=H.count
        local pending={name=c.name,at=context.at,invited=false,authorized=false};B.pending[c.guid]=pending
        t.status=5;B.quarantine=context.at+2;B.blocked=false
        local ok=pcall(C_ChatInfo.SendChatMessage,t.message,"WHISPER",nil,c.name)
        local latest=ownContext();local current=latest and currentCandidate(t,latest)
        if not ok or B.blocked or not latest or latest.actor~=context.actor or latest.guild~=context.guild or latest.scope~=context.scope or latest.session~=context.session
            or not current or not current.qualified or current.guid~=c.guid or current.name~=c.name or not safety(latest,false,1)then clearMacro();t.status=6;return end
        pending.authorized=true;t.stage=2;t.status=5
    elseif t.kind==4 or t.kind==5 then
        if not M.current(context,t,cfg.milestones,rosterMember)then clearMacro();t.status=6;return end
        if not M.owns(context,t)then M.claim(context,t);clearMacro();t.status=5;B.quarantine=context.at+2;return end
        if not M.reserve(context,t)then clearMacro();t.status=6;return end
        beginOwnedAction(context,t);t.status=5;B.quarantine=context.at+2
        if t.kind==5 then t.stage=2;B.requestRoster=true end
    elseif t.kind==2 then
        if not welcomeCurrent(t)then clearMacro();t.status=6;return end
        beginOwnedAction(context,t)
        local pending=B.pending[t.guid];pending.welcomeReserved=true;D.statistics(context,"welcomes")
        local row=context.ledger.records[t.guid];if row then row.welcomed=true end
        t.status=5;B.quarantine=context.at+2
    else clearMacro();t.status=6 end
end
local function afterAction(_,_,down)
    if down==false then return end
    local at=now();if at then B.quarantine=math.max(B.quarantine or 0,at+2)end
    clearMacro()
end
local function openConfiguration()
    local context=configurationContext()
    if not context or not keyCurrent("configuration",B.configurationKey)or not safety(context,false,0)then return end
    retireTicket(context.at);B.quarantine=math.max(B.quarantine or 0,context.at+2)
    B.configurationNonce=B.configurationNonce%4294967295+1
    B.editorOwner=context.owner;B.editorNonce=B.configurationNonce;B.editorExpires=context.at+3
    configurationOutcome("opened",0)
    B.editor:SetText("");B.editor:Show();B.editor:SetFocus()
end
local function editorFailure(context)
    if not context or not B.editorOwner or B.editorOwner~=context.owner or B.editorNonce~=B.configurationNonce then return "ownership" end
    if not B.editorExpires or context.at>=B.editorExpires then return "expired" end
    if editorFlags()~=true then return "focus" end
    if not keyCurrent("configuration",B.configurationKey)then return "binding" end
    if not safety(context,true,0)then return "safety" end
end
local function consumeConfiguration(context,submit)
    local text=call(B.editor.GetText,B.editor)
    if type(text)~="string"then closeEditor("text");return end
    local length=#text
    if length>16000 or length<submit.length then closeEditor("text",length);return end
    if submit.observed and length==submit.length then return end
    submit.observed=true
    submit.length=length
    local prefix="/feuxton-guild-config "..string.format("%.0f",submit.nonce).." "
    local encoded
    if length<=#prefix and prefix:sub(1,length)==text then encoded=""
    elseif text:sub(1,#prefix)==prefix then encoded=text:sub(#prefix+1)
    else closeEditor("prefix",length);return end
    if #encoded>15764 or encoded:find("[^A-Za-z0-9+/=]")then closeEditor("encoding",length);return end
    local raw,cfg,reason
    if #encoded==0 or #encoded%4~=0 then reason="incomplete"
    else
        raw=decode64(encoded)
        if not raw then closeEditor("encoding",length);return end
        cfg,reason=decodeConfiguration(raw)
        if reason=="incomplete"and encoded:find("=",1,true)then reason=nil end
    end
    if not cfg then
        if reason~="incomplete"then closeEditor("payload",length);return end
        configurationOutcome("settling",length);return
    end
    if type(FeuxtonDB)~="table"then closeEditor("storage",length);return end
    local store=FeuxtonDB.guildRecruitment
    if store==nil then store={schema=1,scopes={}};FeuxtonDB.guildRecruitment=store end
    if type(store)~="table"or store.schema~=1 or type(store.scopes)~="table"then closeEditor("storage",length);return end
    local previous=configuration()
    if not previous or previous.checksum~=cfg.checksum then B.routeRejected=false end
    store.configuration={version=1,canonical=raw,checksum=cfg.checksum};B.configuration=cfg;B.configurationRaw=raw
    retireTicket(context.at);B.quarantine=math.max(B.quarantine or 0,context.at+2);closeEditor("accepted",length)
end
local function importConfiguration(editor)
    if editor~=B.editor then return end
    local context=configurationContext()
    local failure=editorFailure(context)
    if failure then closeEditor(failure);return end
    if B.editorSubmit then return end
    -- Enter can arrive before all queued native text. Only that explicit
    -- submit can wait, under the same editor, owner, nonce and idle guards.
    local submit={editor=editor,owner=context.owner,nonce=B.editorNonce,length=0,expires=math.min(B.editorExpires,context.at+.75),nextAt=context.at+.1}
    B.editorSubmit=submit
    consumeConfiguration(context,submit)
end
local function observeConfigurationEditor(context)
    if not B.editorOwner then return end
    local submit=B.editorSubmit;local length=submit and submit.length
    local failure=editorFailure(context)
    if failure then closeEditor(failure,length);return end
    if not submit then return end
    if submit.editor~=B.editor or submit.owner~=context.owner or submit.nonce~=B.editorNonce then closeEditor("ownership",length);return end
    if context.at>=submit.expires then closeEditor("incomplete",length);return end
    if context.at>=submit.nextAt then
        submit.nextAt=context.at+.1
        consumeConfiguration(context,submit)
    end
end
local function ensureButtons()
    local M=ns.state.managedSpells
    if not M or type(M.claimAuxiliaryBinding)~="function"or call(InCombatLockdown)~=false then return end
    if not B.actionButton then
        local action=CreateFrame("Button","FeuxtonGuildRecruitAction",UIParent,"SecureActionButtonTemplate")
        action:SetSize(1,1);action:SetPoint("TOPLEFT",UIParent,"TOPLEFT",-10000,10000);action:SetAlpha(0)
        action:RegisterForClicks("AnyDown","AnyUp");action:SetAttribute("useOnKeyDown",true)
        action:SetScript("PreClick",clickAction);action:SetScript("PostClick",afterAction);B.actionButton=action
        local button=CreateFrame("Button","FeuxtonGuildRecruitConfiguration",UIParent)
        button:SetSize(1,1);button:SetPoint("TOPLEFT",UIParent,"TOPLEFT",-10000,10000);button:SetAlpha(0);button:RegisterForClicks("AnyDown")
        button:SetScript("OnClick",openConfiguration);B.configurationButton=button
        local editor=CreateFrame("EditBox","FeuxtonGuildRecruitConfigurationEditBox",UIParent,"InputBoxTemplate")
        editor:SetSize(1,1);editor:SetPoint("CENTER",UIParent,"CENTER",0,0);editor:SetAlpha(0);editor:SetAutoFocus(false);editor:SetMaxLetters(16000)
        editor:SetScript("OnEnterPressed",importConfiguration);editor:SetScript("OnEscapePressed",function()closeEditor("cancelled")end);editor:Hide();B.editor=editor
    end
    B.actionKey=M.claimAuxiliaryBinding("guild.action","FeuxtonGuildRecruitAction")
    B.configurationKey=M.claimAuxiliaryBinding("guild.configuration","FeuxtonGuildRecruitConfiguration")
end
local function render(value,name,guild,level)
    if not template(value,level~=nil)or not utf8(name,96)or not utf8(guild,96)or name:find("[{}]")or guild:find("[{}]")then return nil end
    if level then value=value:gsub("{level}",tostring(level))end
    return utf8(value:gsub("{player}",function()return name end):gsub("{guild}",function()return guild end),140)
end
local function ticket(context,kind,c,cfg)
    local messages=kind==5 and {"Promotion at level {level}"}or kind==4 and cfg.milestones.messages or kind==3 and {"Search available guildless players"}or kind==1 and cfg.invite or cfg.welcome;local start=math.random(1,#messages)
    local message,index
    for offset=0,#messages-1 do
        index=(start+offset-1)%#messages+1;message=render(messages[index],c.name,context.guild,c.milestoneLevel)
        if message then break end
    end
    if not message then return false end
    B.action=B.action%4294967295+1
    local t={action=B.action,kind=kind,status=4,stage=0,messageIndex=index-1,message=message,messageChecksum=ns.state.adler32(message),configurationChecksum=cfg.checksum,configurationNonce=B.configurationNonce,
        guid=c.guid,name=c.name,unit=c.unit,who=c.whoRequest,expires=context.at+10,owner=B.owner,session=context.session,milestoneLevel=c.milestoneLevel,targetRank=c.targetRank,currentRank=c.currentRank}
    if kind==4 or kind==5 then t.claimReady=M.owns(context,t)end
    B.ticket=t;B.candidateScan=nil
    local button=B.actionButton
    if call(InCombatLockdown)~=false or not keyCurrent("action",B.actionKey)then t.status=6;return false end
    button:SetAttribute("macrotext",macroText(t));button:SetAttribute("feuxton-action",t.action);button:SetAttribute("feuxton-session",t.session)
    button:SetAttribute("feuxton-configuration",t.configurationChecksum);button:SetAttribute("feuxton-message",t.messageChecksum);button:SetAttribute("feuxton-nonce",t.configurationNonce)
    button:SetAttribute("type",macroText(t)and "macro"or nil)
    B.macroArmed=true
    return true
end

local function candidateBefore(a,b)
    if a.level~=b.level then
        if not a.level then return false end;if not b.level then return true end
        return a.level>b.level
    end
    if a.guid~=b.guid then return a.guid<b.guid end
    if a.name~=b.name then return a.name<b.name end
    return (a.unit or "")<(b.unit or "")
end
local function rankedCandidate(context)
    if D.scan then return nil,true end
    return D.best(context,candidate,candidateLevel,suppressed,candidateBefore),false
end
local function update(context,cfg)
    for guid,pending in pairs(B.pending)do if context.at-pending.at>300 then B.pending[guid]=nil end end
    if not cfg or not keyCurrent("action",B.actionKey)then retireTicket(context.at);return 3 end
    if B.routeRejected then return 6 end
    if M.configure(context,cfg.milestones)then B.rosterDirty=true;B.requestRoster=true end
    if(cfg.milestones.enabled or cfg.recruiting)and(not B.rosterRequested or context.at-B.rosterRequested>=30)then B.rosterDirty=true;B.requestRoster=true end
    rosterStep(context,cfg)
    H.step(context,not B.rosterDirty and not B.rosterScan and B.roster or nil)
    if B.ticket then
        local t=B.ticket
        if t.owner~=B.owner or t.session~=context.session or context.at>=t.expires or cfg.checksum~=t.configurationChecksum then retireTicket(context.at)
        elseif t.stage==2 then
            local c=t.kind==1 and currentCandidate(t,context);local chat=nativeChatState(t)
            local record=t.kind==1 and context.ledger.records[t.guid]
            local valid=t.kind==1 and c and c.qualified and c.guid==t.guid and c.name==t.name and record and record.result~="declined"and H.ready(context)or t.kind==5 and M.current(context,t,cfg.milestones,rosterMember)and M.owns(context,t)
            if not valid or t.status~=5 or chat.opener~=true or not safety(context,false,t.kind,t)then retireTicket(context.at);return 2 end
            return 5
        elseif t.status~=4 then
            if B.quarantine and context.at<B.quarantine then return t.status end
            retireTicket(context.at)
        else
            if not safety(context,false,t.kind)or not macroCurrent(t,context)or(t.kind==1 or t.kind==5)and nativeChatState(t).opener~=true then return 2 end
            if t.kind==1 then local c=currentCandidate(t,context);if not c or not c.qualified or c.guid~=t.guid or c.name~=t.name or suppressed(context,c)or not H.ready(context)then retireTicket(context.at);return 2 end
            elseif t.kind==3 then
                if not t.who or D.best(context,candidate,candidateLevel,suppressed,candidateBefore)then retireTicket(context.at);return 3 end
            elseif t.kind==4 or t.kind==5 then if not M.current(context,t,cfg.milestones,rosterMember)then retireTicket(context.at);return 2 end
            elseif not welcomeCurrent(t)then return 2 end
            return 4
        end
    end
    if B.quarantine and context.at<B.quarantine then return 3 end
    if not B.roster or context.club and (B.rosterDirty or B.rosterScan) then return 1 end
    local milestoneKind,milestone=M.next(context,cfg.milestones,rosterMember)
    if milestoneKind then
        if not safety(context,false,milestoneKind)or milestoneKind==5 and nativeChatState(nil).opener~=true then return 2 end
        return ticket(context,milestoneKind,milestone,cfg)and 4 or 2
    end
    if not cfg.recruiting then return 3 end
    if not H.ready(context)then return 7 end
    for guid,pending in pairs(B.pending)do
        if pending.joined and not pending.welcomeReserved and context.at-pending.joinedAt<=60 then
            if not safety(context,false,2)then return 2 end
            return ticket(context,2,{guid=guid,name=pending.name},cfg)and 4 or 2
        end
    end
    if not safety(context,false,1)or nativeChatState(nil).opener~=true then B.candidateScan=nil;return 2 end
    local c,unknown=rankedCandidate(context)
    if c then
        if not budget(context)then return 3 end
        return ticket(context,1,c,cfg)and 4 or 2
    end
    if not unknown then
        local request=D.whoRequest(context,cfg.whoScope,utf8)
        if request then return ticket(context,3,{guid="who-query",name="Who search",whoRequest=request},cfg)and 4 or 2 end
    end
    return unknown and 1 or 3
end
function B.packet(tick)
    D.maintain()
    ensureButtons()
    if B.macroArmed and not B.ticket then retireTicket(now())end
    local identity=readIdentity() or false
    local editorContext=configurationContext(identity)
    observeConfigurationEditor(editorContext)
    local focus,empty=editorFlags();local cfg=configuration();local context=ownContext(identity);local status
    if context then D.collect(context,B.plates,candidate,candidateLevel)end
    if focus==true then retireTicket(editorContext and editorContext.at);status=3
    elseif context then status=update(context,cfg)
    else retireTicket(editorContext and editorContext.at);B.pending={};H.invalidateRoster();M.clear();status=editorContext and 3 or 0 end
    B.monitorContext=context;B.monitorTick=tick
    local invite,canChat=permissions();local t=B.ticket
    local expires=t and math.max(0,math.min(10000,math.floor((t.expires-context.at)*1000)))or 0
    local ledger=context and context.ledger or {};local S=ns.state
    local actionKey=keyCurrent("action",B.actionKey)and S.compactBindingCode(B.actionKey)or 0
    local configKey=keyCurrent("configuration",B.configurationKey)and S.compactBindingCode(B.configurationKey)or 0
    local chat=nativeChatState(t)
    local milestoneStatus,milestonePending,announcements,confirmed,promoted=M.statistics()
    local packet=ns.wire.schemas.guildRecruitment..S.bytes(S.setupSession,4)..S.bytes(tick,4)..S.bytes(t and t.action or 0,4)..S.bytes(t and t.kind or 0,1)..S.bytes(status,1)..S.bytes(expires,2)
        ..S.bytes(math.min(10,#(ledger.attempts or {})),1)..S.bytes(integer(ledger.totalInvites)or 0,4)..S.bytes(integer(ledger.totalJoins)or 0,4)..S.bytes(integer(ledger.totalDeclines)or 0,4)
        ..S.bytes(flag(invite)+flag(canChat)*4+flag(call(CanGuildPromote))*16,1)..S.bytes(focus==true and 1 or t and t.stage or 0,1)..S.bytes(t and t.messageChecksum or 0,4)
        ..S.bytes(cfg and cfg.checksum or 0,4)..S.bytes(B.configurationNonce,4)..S.bytes(t and t.messageIndex or 0,1)..S.bytes(actionKey,2)..S.bytes(configKey,2)..S.bytes(flag(focus)+flag(empty)*4,1)
        ..S.bytes(flag(chat.focus)+flag(chat.empty)*4+flag(chat.matches)*16+flag(chat.opener)*64,1)
        ..S.bytes(D.count,2)..S.bytes(D.whoStatus,1)
        ..S.bytes(t and t.milestoneLevel or 0,1)..S.bytes(t and t.targetRank or 255,1)..S.bytes(t and t.currentRank or 255,1)..S.bytes(milestoneStatus,1)..S.bytes(milestonePending,2)..S.bytes(announcements,4)..S.bytes(confirmed,4)..S.bytes(promoted,4)
    for _,value in ipairs({context and context.actor or editorContext and editorContext.actor or "",context and context.guild or editorContext and editorContext.guild or "",context and context.scope or editorContext and editorContext.scope or "",t and t.guid or "",t and t.name or "",chat.identity})do packet=packet..S.bytes(#value,1)..value end
    assert(#packet+4<=602,"guild recruitment packet capacity")
    return packet..S.bytes(S.adler32(packet),4)
end

-- Read-only queue pages use only remaining envelope space. They cannot
-- prepare actions, refresh native unit facts or reserve an invitation.
local monitorStatKeys=D.statisticsKeys
local function monitorRow(c,context)
    local ledger=context.ledger;local record=ledger.records[c.guid]or ledger.records[ledger.names[c.name]or ""]
    local pending=B.pending[c.guid];local state=1;local wait=0
    if record and type(record.untilAt)=="number"and record.untilAt>context.utc then
        state=record.result=="declined"and 8 or 4;wait=math.min(H.maximum,math.ceil(record.untilAt-context.utc))
    elseif not c.qualified or not c.guildAt then state=2
    elseif context.at<c.guildAt or context.at-c.guildAt>60 then state=3 end
    if pending and pending.authorized then state=pending.joined and 7 or 6 end
    if B.ticket and B.ticket.kind==1 and B.ticket.guid==c.guid and B.ticket.status==4 then state=5 end
    local level=type(c.level)=="number"and c.level>0 and c.level<=255 and c.level or 0
    return {name=c.name,guid=c.guid,level=level,source=c.who and 2 or 1,state=state,wait=wait,seen=math.max(0,math.min(65535,math.floor(context.at-c.seenAt)))}
end
function B.monitorPacket(tick,maximum)
    local previous=B.monitorPublication
    if previous and previous.session==ns.state.setupSession and previous.tick==tick then return previous.packet end
    local publication={session=ns.state.setupSession,tick=tick};B.monitorPublication=publication
    local context=B.monitorTick==tick and B.monitorContext
    local stats=D.statistics(context)
    if not context or not stats or type(maximum)~="number"or maximum<75 then return nil end
    local view=B.monitorView
    if not view or view.owner~=B.owner or view.session~=context.session or context.at<view.at or context.at-view.at>30
        or view.offset>=#view.rows and context.at-view.at>=1 then
        B.monitorRevision=(B.monitorRevision or 0)%4294967295+1
        view={owner=B.owner,session=context.session,revision=B.monitorRevision,at=context.at,offset=0,rows={},ready=0,unknown=0,suppressed=0}
        for _,c in pairs(D.rows)do if utf8(c.name,96)then
            local row=monitorRow(c,context);view.rows[#view.rows+1]=row
            if row.state==1 or row.state==5 then view.ready=view.ready+1 elseif row.state==2 or row.state==3 then view.unknown=view.unknown+1 elseif row.state==4 or row.state==8 then view.suppressed=view.suppressed+1 end
        end end
        local function rank(row)return row.state==5 and 0 or row.state==1 and 1 or row.state==6 and 2 or 3 end
        table.sort(view.rows,function(a,b)if rank(a)~=rank(b)then return rank(a)<rank(b)end;return candidateBefore(a,b)end)
        B.monitorView=view
    end
    local ready,unknown,suppressedCount,outstanding=view.ready,view.unknown,view.suppressed,0
    for _,p in pairs(B.pending)do if p.authorized and not p.joined and not p.declined and context.at-p.at<=120 then outstanding=outstanding+1 end end
    local delay=type(context.ledger.lastDelayMs)=="number"and context.ledger.lastDelayMs or 8000
    local inviteWait=0
    if B.lastAttemptOwner==B.owner and B.lastAttemptMonotonic then inviteWait=math.max(0,(delay/1000-(context.at-B.lastAttemptMonotonic))*1000)
    elseif context.ledger.lastAttempt then inviteWait=math.max(0,(math.ceil(delay/1000)+1-(context.utc-context.ledger.lastAttempt))*1000)end
    if #context.ledger.attempts>=8 then inviteWait=math.max(inviteWait,(60-(context.utc-context.ledger.attempts[1]))*1000)end
    local whoWait=math.max(0,((D.nextWho or 0)-context.at)*1000,((D.externalUntil or 0)-context.at)*1000)
    if D.lastWhoOwner~=D.owner and context.ledger.lastWhoAt then whoWait=math.max(whoWait,(61-(context.utc-context.ledger.lastWhoAt))*1000)end
    local entries={};local bytes=75;local offset=math.min(view.offset,#view.rows)
    for index=offset+1,math.min(#view.rows,offset+4)do
        local row=view.rows[index];local size=#row.name+10
        if bytes+size>maximum then break end
        entries[#entries+1]=ns.state.bytes(#row.name,1)..row.name..ns.state.bytes(row.level,1)..ns.state.bytes(row.source,1)..ns.state.bytes(row.state,1)..ns.state.bytes(row.seen,2)..ns.state.bytes(row.wait,4);bytes=bytes+size
    end
    if offset<#view.rows and #entries==0 then return nil end
    local S=ns.state
    local packet=ns.wire.schemas.guildQueue..S.bytes(context.session,4)..S.bytes(tick,4)..S.bytes(S.adler32(B.owner),4)..S.bytes(view.revision,4)
        ..S.bytes(#view.rows,2)..S.bytes(offset,2)..S.bytes(math.min(65535,math.floor((context.at-view.at)*1000)),2)..S.bytes(#entries,1)
        ..S.bytes(ready,2)..S.bytes(unknown,2)..S.bytes(suppressedCount,2)..S.bytes(outstanding,2)
        ..S.bytes(math.min(65535,math.ceil(inviteWait)),2)..S.bytes(math.min(65535,math.ceil(whoWait)),2)..S.bytes(stats.since,4)
    for _,key in ipairs(monitorStatKeys)do packet=packet..S.bytes(stats[key],4)end
    packet=packet..table.concat(entries);packet=packet..S.bytes(S.adler32(packet),4)
    publication.packet=packet;view.offset=offset+#entries
    if view.offset>=#view.rows and context.at-view.at<1 then view.offset=0 end
    return packet
end

local function nativeText(value)
    if not public(value)or type(value)~="string"or #value>1024 then return nil end
    return value:gsub("|Hplayer:[^|]-|h(.-)|h","%1"):gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")
end
local function matchName(message,format)
    message=nativeText(message);format=nativeText(format)
    if not message or not format then return nil end
    local a,b=format:find("%%s",1);if not a then a,b=format:find("%%1%$s",1)end
    if not a then return nil end
    local before,after=format:sub(1,a-1),format:sub(b+1)
    if after:find("%%")or before:find("%%")or message:sub(1,#before)~=before or after~=""and message:sub(-#after)~=after then return nil end
    local name=message:sub(#before+1,#message-#after)
    if name:sub(1,1)=="["and name:sub(-1)=="]"then name=name:sub(2,-2)end
    return utf8(name,96)
end
local function systemMessage(message)
    local context=ownContext();if not context then return end
    local invited=matchName(message,_G.ERR_GUILD_INVITE_S)
    if invited then
        for guid,pending in pairs(B.pending)do
            if pending.name==invited and pending.authorized and not pending.declined then
                pending.invited=true;pending.inviteReceipt=true
                if not pending.statisticsConfirmed then pending.statisticsConfirmed=true;D.statistics(context,"confirmed")end
                if B.ticket and B.ticket.guid==guid and B.ticket.kind==1 then B.ticket.status=5 end
                return
            end
        end
        return
    end
    local name=matchName(message,_G.ERR_GUILD_JOIN_S);local declined=false
    if not name then name=matchName(message,_G.ERR_GUILD_DECLINE_S)or matchName(message,_G.ERR_GUILD_DECLINE_AUTO_S);declined=name~=nil end
    if not name then return end
    for guid,pending in pairs(B.pending)do
        if pending.name==name and pending.authorized then
            if declined then
                if not pending.declined and not pending.joined then
                    pending.declined=true;context.ledger.totalDeclines=increment(context.ledger.totalDeclines)
                    if not pending.statisticsConfirmed then pending.statisticsConfirmed=true;D.statistics(context,"confirmed")end
                    D.statistics(context,"declines")
                    H.declined(context,guid,B.configuration and B.configuration.reinviteHours or 72)
                    if B.ticket and B.ticket.guid==guid then retireTicket(context.at)end
                    B.pending[guid]=nil
                end
            elseif not pending.declined and context.at-pending.at<=120 then
                -- Some clients omit the inviter's invite receipt. A named
                -- server join plus the subsequent exact roster membership is
                -- still required before any welcome is offered.
                pending.invited=true;pending.joinSeen=true;pending.joinAt=context.at;B.rosterDirty=true;B.requestRoster=true
                if B.ticket and B.ticket.guid==guid and B.ticket.kind==1 then B.ticket.stage=0;B.ticket.status=5 end
            end
            return
        end
    end
end
local events=CreateFrame("Frame");B.events=events
for _,event in ipairs({"NAME_PLATE_UNIT_ADDED","NAME_PLATE_UNIT_REMOVED","PLAYER_TARGET_CHANGED","UPDATE_MOUSEOVER_UNIT","PLAYER_ENTERING_WORLD","PLAYER_LEAVING_WORLD","PLAYER_REGEN_DISABLED","ADDON_LOADED","WHO_LIST_UPDATE","GUILD_ROSTER_UPDATE","PLAYER_GUILD_UPDATE","CHAT_MSG_SYSTEM","ADDON_ACTION_BLOCKED","ADDON_ACTION_FORBIDDEN","MACRO_ACTION_BLOCKED","MACRO_ACTION_FORBIDDEN"})do pcall(events.RegisterEvent,events,event)end
events:SetScript("OnEvent",function(_,event,value,...)
    if event=="NAME_PLATE_UNIT_ADDED"then if public(value)and type(value)=="string"and value:match("^nameplate%d+$")then local count=0;for _ in pairs(B.plates)do count=count+1 end;if count<128 and not B.plates[value]then B.plates[value]=true;B.candidateScan=nil end end
    elseif event=="NAME_PLATE_UNIT_REMOVED"then if public(value)and type(value)=="string"and B.plates[value]then B.plates[value]=nil;B.candidateScan=nil end
    elseif event=="PLAYER_TARGET_CHANGED"or event=="UPDATE_MOUSEOVER_UNIT"then B.candidateScan=nil
    elseif event=="WHO_LIST_UPDATE"then D.whoResults(ownContext(),utf8)
    elseif event=="ADDON_LOADED"then D.addonLoaded()
    elseif event=="CHAT_MSG_SYSTEM"then systemMessage(value)
    elseif event=="GUILD_ROSTER_UPDATE"then B.rosterDirty=true;B.rosterScan=nil;B.rosterRetryAt=nil;H.invalidateRoster() -- permission to request is not a request trigger
    elseif event=="PLAYER_GUILD_UPDATE"then if public(value)and value=="player"then B.rosterDirty=true;B.rosterScan=nil;B.rosterRetryAt=nil;B.requestRoster=true end
    elseif event=="ADDON_ACTION_BLOCKED"or event=="ADDON_ACTION_FORBIDDEN"or event=="MACRO_ACTION_BLOCKED"or event=="MACRO_ACTION_FORBIDDEN"then local fn=(event=="MACRO_ACTION_BLOCKED"or event=="MACRO_ACTION_FORBIDDEN")and value or select(1,...);if not D.rejected(fn)then rejectOwnedAction(event,value,select(1,...))end
    elseif event=="PLAYER_REGEN_DISABLED"then closeEditor("safety");retireTicket(now())
    else D.cancelWho();closeEditor("ownership");retireTicket(now());B.actionWindow=nil;B.pending={};B.samples={};B.plates={};B.roster=nil;B.rosterScan=nil;B.rosterDirty=true;B.requestRoster=true end
end)
