-- Public guild observations, one reused social macro and a private import box.
-- Only a native click can run PreClick/the macro. Timers/events never send.
local _,ns=...
local B={plates={},samples={},pending={},action=0,rosterDirty=true,configurationNonce=0}
ns.features.GuildRecruitment=B
local MAX=2147483647
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
local function configurationContext()
    local actor=utf8(call(UnitGUID,"player"),64);local realm=utf8(call(GetRealmName),96)
    local stamp=now();local session=integer(ns.state.setupSession,4294967295)
    if not actor or not realm or not stamp or not session or session==0 then return nil end
    return {actor=actor,realm=realm,session=session,at=stamp,owner=realm.."\31"..actor.."\31"..session}
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
        if t and t.kind==1 then state.matches=text=="/ginvite "..t.name else state.matches=false end
    end
    return state
end
local function ownContext()
    local G=ns.features.GroupContext
    if not G or type(G.names)~="function"then return nil end
    local actor=utf8(call(UnitGUID,"player"),64)
    -- A current positive self read is also the control for qualified nils.
    local guild=utf8(call(GetGuildInfo,"player"),96)
    local realm=utf8(call(GetRealmName),96)
    local _,name=G.names("player",96);name=utf8(name,96)
    local stamp=now();local utc=wall();local session=integer(ns.state.setupSession,4294967295)
    if not actor or not guild or not realm or not name or not stamp or not utc or not session or session==0 then return nil end
    local key=realm.."\31"..guild.."\31"..actor
    if B.owner~=key or B.session~=session then
        retireTicket(stamp);B.owner=key;B.session=session;B.pending={};B.samples={};B.roster=nil;B.rosterScan=nil;B.rosterDirty=true;B.rosterRequested=nil;B.ledger=nil;B.ledgerMaintenance=nil
    end
    if type(FeuxtonDB)~="table"then return nil end
    local store=FeuxtonDB.guildRecruitment
    if store==nil then store={schema=1,scopes={}};FeuxtonDB.guildRecruitment=store end
    if type(store)~="table"or store.schema~=1 or type(store.scopes)~="table"then return nil end
    local ledger=store.scopes[key]
    if ledger==nil then ledger={records={},names={},attempts={},totalInvites=0,totalJoins=0,totalDeclines=0};store.scopes[key]=ledger end
    if type(ledger)~="table"or type(ledger.records)~="table"or type(ledger.names)~="table"or type(ledger.attempts)~="table"then return nil end
    if B.ledger~=ledger or not B.ledgerMaintenance or stamp-B.ledgerMaintenance>=5 then
        local count=0
        for guid,row in pairs(ledger.records)do
            if type(row)~="table"or not integer(row.untilAt)then return nil end
            if row.untilAt<=utc then ledger.records[guid]=nil;if ledger.names[row.name]==guid then ledger.names[row.name]=nil end else count=count+1 end
        end
        B.ledger=ledger;B.recordCount=count;B.ledgerMaintenance=stamp
    end
    if #ledger.attempts>10 then return nil end
    local attempts={}
    for _,at in ipairs(ledger.attempts)do if not integer(at)then return nil end;if utc-at<60 then attempts[#attempts+1]=at end end
    ledger.attempts=attempts
    return {actor=actor,name=name,guild=guild,realm=realm,session=session,at=stamp,utc=utc,ledger=ledger,recordCount=B.recordCount or 0}
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
        local invite,chat=permissions();if chat~=true or kind~=2 and invite~=true then return false end
        if type(C_ChatInfo)~="table"or call(C_ChatInfo.InChatMessagingLockdown)~=false or type(C_ChatInfo.SendChatMessage)~="function"or type(C_GuildInfo)~="table"then return false end
    end
    if call(InCombatLockdown)~=false or call(UnitAffectingCombat,"player")~=false or call(UnitIsDeadOrGhost,"player")~=false or call(UnitOnTaxi,"player")~=false or movement()~=false then return false end
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
    if unit=="target"or unit=="mouseover"then
        if call(CheckInteractDistance,unit,4)~=true then return nil end
    elseif not unit:match("^nameplate%d+$")then return nil end
    local guid=utf8(call(UnitGUID,unit),64);local first,name=ns.features.GroupContext.names(unit,96);name=utf8(name,96)
    if not guid or guid==context.actor or not name then return nil end
    local ok,guild=pcall(GetGuildInfo,unit)
    if not ok or not public(guild)then return nil end
    if guild~=nil then B.samples[guid]=nil;return nil end
    local isGuilded=call(UnitIsInGuild,unit)
    local guildless=isGuilded==false
    if isGuilded==true then return nil end
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
local function rosterMember(index)
    if type(GetGuildRosterInfo)~="function"then return nil end
    local ok,name,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,guid=pcall(GetGuildRosterInfo,index)
    name=utf8(name,96);guid=utf8(guid,64)
    return ok and name and {name=name,guid=guid,index=index}or nil
end
local function rosterStep(context)
    if B.requestRoster and (not B.rosterRequested or context.at-B.rosterRequested>=2)then
        B.requestRoster=false;B.rosterRequested=context.at
        if type(C_GuildInfo)=="table"and type(C_GuildInfo.GuildRoster)=="function"then pcall(C_GuildInfo.GuildRoster)end
    end
    if not B.rosterScan and B.rosterDirty then
        B.rosterDirty=false
        local count=integer(call(GetNumGuildMembers),1000)
        if not count or count==0 then return end
        B.rosterScan={count=count,index=1,members={},valid=true,at=context.at}
    end
    local scan=B.rosterScan;if not scan then return end
    for _=1,8 do
        if scan.index>scan.count then break end
        local member=rosterMember(scan.index);scan.index=scan.index+1
        if member then scan.members[member.guid or "name:"..member.name]=member else scan.valid=false end
    end
    if scan.index<=scan.count then return end
    B.rosterScan=nil
    if scan.count~=integer(call(GetNumGuildMembers),1000)or not scan.valid then return end
    local initial=B.roster==nil;B.roster=scan.members;B.rosterAt=context.at
    if initial then return end -- initial login roster is never a join event
    for guid,pending in pairs(B.pending)do
        local member=scan.members[guid]
        if pending.joinSeen and pending.invited and not pending.joined and member and member.name==pending.name and pending.joinAt and scan.at>=pending.joinAt then
            pending.joined=true;pending.joinedAt=context.at;context.ledger.totalJoins=increment(context.ledger.totalJoins)
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
    if type(value)~="string"or #value==0 or #value>10332 or #value%4~=0 or value:find("[^A-Za-z0-9+/=]")then return nil end
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
    local decoded=table.concat(out);return #decoded<=7747 and decoded or nil
end
local function template(value)
    value=utf8(value,120);if not value then return nil end
    local remainder=value:gsub("{player}",""):gsub("{guild}","")
    return not remainder:find("[{}]")and value or nil
end
local function decodeConfiguration(raw)
    if type(raw)~="string"or #raw<7 or #raw>7747 or raw:byte(1)~=1 then return nil end
    local offset=2;local lists={}
    for kind=1,2 do
        local count=raw:byte(offset);offset=offset+1;if not count or count<1 or count>32 then return nil end
        local list={}
        for i=1,count do
            local length=raw:byte(offset);offset=offset+1
            if not length or length<1 or length>120 or offset+length-1>#raw then return nil end
            local text=template(raw:sub(offset,offset+length-1));if not text then return nil end
            list[i]=text;offset=offset+length
        end
        lists[kind]=list
    end
    if offset~=#raw+1 then return nil end
    return {canonical=raw,checksum=ns.state.adler32(raw),invite=lists[1],welcome=lists[2]}
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
local function closeEditor()
    if not B.editor then return end
    B.editor:ClearFocus();B.editor:SetText("");B.editor:Hide();B.editorOwner=nil;B.editorExpires=nil
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
    return t.kind==2 and "/stopmacro [combat][dead]\n/g "..t.message or nil
end
local function attributeMatches(button,key,expected)
    local ok,value=pcall(button.GetAttribute,button,key)
    return ok and public(value)and value==expected
end
local function macroCurrent(t,context)
    local button=B.actionButton
    return button and keyCurrent("action",B.actionKey)and attributeMatches(button,"type",t.kind==2 and "macro"or nil)
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
    local pending=B.pending[t.guid];local member=B.roster and B.roster[t.guid];local current=member and rosterMember(member.index)
    return pending and pending.joined and not pending.welcomeReserved and current and current.guid==t.guid and current.name==t.name
        and type(C_GuildInfo)=="table"and call(C_GuildInfo.MemberExistsByName,t.name)==true
end
local function clickAction(_,_,down)
    if down==false then return end
    local context=ownContext();local t=B.ticket;local cfg=configuration()
    if not context or not t or t.stage~=0 or t.status~=4 or B.routeRejected or not cfg or cfg.checksum~=t.configurationChecksum or t.owner~=B.owner or t.session~=context.session or context.at>=t.expires
        or B.quarantine and context.at<B.quarantine or not safety(context,false,t.kind)or not macroCurrent(t,context)then clearMacro();if t then t.stage=0;t.status=6 end;return end
    if t.kind==1 then
        local c=candidate(t.unit,context)
        if not c or not c.qualified or c.guid~=t.guid or c.name~=t.name or suppressed(context,c)or not budget(context)or not B.roster or nativeChatState(t).opener~=true then clearMacro();t.status=6;return end
        beginOwnedAction(context,t)
        context.ledger.attempts[#context.ledger.attempts+1]=context.utc;context.ledger.lastAttempt=context.utc
        context.ledger.lastDelayMs=math.random(8000,12000)
        B.lastAttemptMonotonic=context.at;B.lastAttemptOwner=B.owner
        context.ledger.totalInvites=increment(context.ledger.totalInvites)
        context.ledger.records[c.guid]={name=c.name,untilAt=context.utc+86400,attempted=context.utc,result="unknown"}
        B.recordCount=(B.recordCount or 0)+1;context.ledger.names[c.name]=c.guid
        local pending={name=c.name,at=context.at,invited=false,authorized=false};B.pending[c.guid]=pending
        t.status=5;B.quarantine=context.at+2;B.blocked=false
        local ok=pcall(C_ChatInfo.SendChatMessage,t.message,"WHISPER",nil,c.name)
        local latest=ownContext();local current=latest and candidate(t.unit,latest)
        if not ok or B.blocked or not latest or latest.actor~=context.actor or latest.guild~=context.guild or latest.realm~=context.realm or latest.session~=context.session
            or not current or not current.qualified or current.guid~=c.guid or current.name~=c.name or not safety(latest,false,1)then clearMacro();t.status=6;return end
        pending.authorized=true;t.stage=2;t.status=5
    elseif t.kind==2 then
        if not welcomeCurrent(t)then clearMacro();t.status=6;return end
        beginOwnedAction(context,t)
        local pending=B.pending[t.guid];pending.welcomeReserved=true
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
    B.editorOwner=context.owner;B.editorExpires=context.at+3
    B.editor:SetText("");B.editor:Show();B.editor:SetFocus()
end
local function importConfiguration()
    local context=configurationContext();local focused=editorFlags()
    if not context or not B.editorOwner or B.editorOwner~=context.owner or not B.editorExpires or context.at>=B.editorExpires or focused~=true
        or not keyCurrent("configuration",B.configurationKey)or not safety(context,true,0)then closeEditor();return end
    local text=call(B.editor.GetText,B.editor)
    if type(text)~="string"or #text>10365 then closeEditor();return end
    local nonce,encoded=text:match("^/feuxton%-guild%-config (%d+) ([A-Za-z0-9+/=]+)$")
    local number=nonce and #nonce<=10 and tonumber(nonce)
    if not number or number~=B.configurationNonce or nonce~=string.format("%.0f",number)then closeEditor();return end
    local raw=decode64(encoded);local cfg=raw and decodeConfiguration(raw)
    if not cfg then closeEditor();return end
    if type(FeuxtonDB)~="table"then closeEditor();return end
    local store=FeuxtonDB.guildRecruitment
    if store==nil then store={schema=1,scopes={}};FeuxtonDB.guildRecruitment=store end
    if type(store)~="table"or store.schema~=1 or type(store.scopes)~="table"then closeEditor();return end
    local previous=configuration()
    if not previous or previous.checksum~=cfg.checksum then B.routeRejected=false end
    store.configuration={version=1,canonical=raw,checksum=cfg.checksum};B.configuration=cfg;B.configurationRaw=raw
    retireTicket(context.at);B.quarantine=math.max(B.quarantine or 0,context.at+2);closeEditor()
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
        editor:SetSize(1,1);editor:SetPoint("CENTER",UIParent,"CENTER",0,0);editor:SetAlpha(0);editor:SetAutoFocus(false);editor:SetMaxLetters(10400)
        editor:SetScript("OnEnterPressed",importConfiguration);editor:SetScript("OnEscapePressed",closeEditor);editor:Hide();B.editor=editor
    end
    B.actionKey=M.claimAuxiliaryBinding("guild.action","FeuxtonGuildRecruitAction")
    B.configurationKey=M.claimAuxiliaryBinding("guild.configuration","FeuxtonGuildRecruitConfiguration")
end
local function render(value,name,guild)
    if not template(value)or not utf8(name,96)or not utf8(guild,96)or name:find("[{}]")or guild:find("[{}]")then return nil end
    return utf8(value:gsub("{player}",function()return name end):gsub("{guild}",function()return guild end),140)
end
local function ticket(context,kind,c,cfg)
    local messages=kind==1 and cfg.invite or cfg.welcome;local start=math.random(1,#messages)
    local message,index
    for offset=0,#messages-1 do
        index=(start+offset-1)%#messages+1;message=render(messages[index],c.name,context.guild)
        if message then break end
    end
    if not message then return false end
    B.action=B.action%4294967295+1
    local t={action=B.action,kind=kind,status=4,stage=0,messageIndex=index-1,message=message,messageChecksum=ns.state.adler32(message),configurationChecksum=cfg.checksum,configurationNonce=B.configurationNonce,
        guid=c.guid,name=c.name,unit=c.unit,expires=context.at+10,owner=B.owner,session=context.session}
    B.ticket=t;B.candidateScan=nil
    local button=B.actionButton
    if call(InCombatLockdown)~=false or not keyCurrent("action",B.actionKey)then t.status=6;return false end
    button:SetAttribute("macrotext",macroText(t));button:SetAttribute("feuxton-action",t.action);button:SetAttribute("feuxton-session",t.session)
    button:SetAttribute("feuxton-configuration",t.configurationChecksum);button:SetAttribute("feuxton-message",t.messageChecksum);button:SetAttribute("feuxton-nonce",t.configurationNonce)
    button:SetAttribute("type",kind==2 and "macro"or nil)
    B.macroArmed=true
    return true
end
local function candidateLevel(unit)
    local level=integer(call(UnitLevel,unit))
    return level and level>0 and level or nil
end
local function candidateBefore(a,b)
    if a.level~=b.level then
        if not a.level then return false end;if not b.level then return true end
        return a.level>b.level
    end
    if a.guid~=b.guid then return a.guid<b.guid end
    if a.name~=b.name then return a.name<b.name end
    return a.unit<b.unit
end
local function rankedCandidate(context)
    local scan=B.candidateScan
    if not scan or context.at-scan.at>5 then
        local units={"target","mouseover"};for unit in pairs(B.plates)do units[#units+1]=unit end
        if #units>130 then B.candidateScan=nil;return nil,true end
        table.sort(units);scan={units=units,index=0,candidates={},unknown=false,at=context.at};B.candidateScan=scan
    end
    -- Finish the entire observed set before offering anyone. The bounded
    -- sweep avoids letting target order or nameplate enumeration set priority.
    for _=1,math.min(8,#scan.units-scan.index)do
        scan.index=scan.index+1
        local c=candidate(scan.units[scan.index],context)
        if c and not suppressed(context,c)then
            if c.qualified then
                c.level=candidateLevel(c.unit)
                local previous=scan.candidates[c.guid]
                if previous==nil then scan.candidates[c.guid]=c
                elseif previous and previous.name~=c.name then scan.candidates[c.guid]=false
                elseif previous and candidateBefore(c,previous)then scan.candidates[c.guid]=c end
            else scan.unknown=true end
        end
    end
    if scan.index<#scan.units then return nil,true end
    B.candidateScan=nil
    local best;for _,c in pairs(scan.candidates)do if c and(not best or candidateBefore(c,best))then best=c end end
    if not best then return nil,scan.unknown end
    if best.unit~="target"and best.unit~="mouseover"and not B.plates[best.unit]then return nil,true end
    local current=candidate(best.unit,context)
    if not current or not current.qualified or current.guid~=best.guid or current.name~=best.name or suppressed(context,current)
        or candidateLevel(current.unit)~=best.level then return nil,true end
    return current,false
end
local function update(context,cfg)
    for guid,pending in pairs(B.pending)do if context.at-pending.at>300 then B.pending[guid]=nil end end
    if not cfg or not keyCurrent("action",B.actionKey)then retireTicket(context.at);return 3 end
    if B.routeRejected then return 6 end
    rosterStep(context)
    if B.ticket then
        local t=B.ticket
        if t.owner~=B.owner or t.session~=context.session or context.at>=t.expires or cfg.checksum~=t.configurationChecksum then retireTicket(context.at)
        elseif t.stage==2 then
            local c=candidate(t.unit,context);local chat=nativeChatState(t)
            if t.kind~=1 or t.status~=5 or not c or not c.qualified or c.guid~=t.guid or c.name~=t.name or chat.opener~=true or not safety(context,false,1,t)then retireTicket(context.at);return 2 end
            return 5
        elseif t.status~=4 then
            if B.quarantine and context.at<B.quarantine then return t.status end
            retireTicket(context.at)
        else
            if not safety(context,false,t.kind)or not macroCurrent(t,context)or t.kind==1 and nativeChatState(t).opener~=true then return 2 end
            if t.kind==1 then local c=candidate(t.unit,context);if not c or not c.qualified or c.guid~=t.guid or c.name~=t.name then return 2 end
            elseif not welcomeCurrent(t)then return 2 end
            return 4
        end
    end
    if B.quarantine and context.at<B.quarantine then return 3 end
    if not B.roster then return 1 end
    for guid,pending in pairs(B.pending)do
        if pending.joined and not pending.welcomeReserved and context.at-pending.joinedAt<=60 then
            if not safety(context,false,2)then return 2 end
            return ticket(context,2,{guid=guid,name=pending.name},cfg)and 4 or 2
        end
    end
    if not safety(context,false,1)or nativeChatState(nil).opener~=true then B.candidateScan=nil;return 2 end
    if not budget(context)then B.candidateScan=nil;return 3 end
    local c,unknown=rankedCandidate(context)
    if c then return ticket(context,1,c,cfg)and 4 or 2 end
    return unknown and 1 or 3
end
function B.packet(tick)
    ensureButtons()
    if B.macroArmed and not B.ticket then retireTicket(now())end
    local editorContext=configurationContext()
    if B.editorOwner and(not editorContext or editorContext.owner~=B.editorOwner or not B.editorExpires or editorContext.at>=B.editorExpires or not safety(editorContext,true,0))then closeEditor()end
    local focus,empty=editorFlags();local cfg=configuration();local context=ownContext();local status
    if focus==true then retireTicket(editorContext and editorContext.at);status=3
    elseif context then status=update(context,cfg)
    else retireTicket(editorContext and editorContext.at);B.pending={};status=editorContext and 3 or 0 end
    local invite,canChat=permissions();local t=B.ticket
    local expires=t and math.max(0,math.min(10000,math.floor((t.expires-context.at)*1000)))or 0
    local ledger=context and context.ledger or {};local S=ns.state
    local actionKey=keyCurrent("action",B.actionKey)and S.compactBindingCode(B.actionKey)or 0
    local configKey=keyCurrent("configuration",B.configurationKey)and S.compactBindingCode(B.configurationKey)or 0
    local chat=nativeChatState(t)
    local packet="HGI2"..S.bytes(S.setupSession,4)..S.bytes(tick,4)..S.bytes(t and t.action or 0,4)..S.bytes(t and t.kind or 0,1)..S.bytes(status,1)..S.bytes(expires,2)
        ..S.bytes(math.min(10,#(ledger.attempts or {})),1)..S.bytes(integer(ledger.totalInvites)or 0,4)..S.bytes(integer(ledger.totalJoins)or 0,4)..S.bytes(integer(ledger.totalDeclines)or 0,4)
        ..S.bytes(flag(invite)+flag(canChat)*4,1)..S.bytes(focus==true and 1 or t and t.stage or 0,1)..S.bytes(t and t.messageChecksum or 0,4)
        ..S.bytes(cfg and cfg.checksum or 0,4)..S.bytes(B.configurationNonce,4)..S.bytes(t and t.messageIndex or 0,1)..S.bytes(actionKey,2)..S.bytes(configKey,2)..S.bytes(flag(focus)+flag(empty)*4,1)
        ..S.bytes(flag(chat.focus)+flag(chat.empty)*4+flag(chat.matches)*16+flag(chat.opener)*64,1)
    for _,value in ipairs({context and context.actor or editorContext and editorContext.actor or "",context and context.guild or "",context and context.realm or editorContext and editorContext.realm or "",t and t.guid or "",t and t.name or "",chat.identity})do packet=packet..S.bytes(#value,1)..value end
    assert(#packet+4<=512,"guild recruitment packet capacity")
    return packet..S.bytes(S.adler32(packet),4)
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
                    local row=context.ledger.records[guid];if row then row.untilAt=math.max(row.untilAt,context.utc+86400);row.result="declined"end
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
for _,event in ipairs({"NAME_PLATE_UNIT_ADDED","NAME_PLATE_UNIT_REMOVED","PLAYER_TARGET_CHANGED","UPDATE_MOUSEOVER_UNIT","PLAYER_ENTERING_WORLD","PLAYER_LEAVING_WORLD","PLAYER_REGEN_DISABLED","GUILD_ROSTER_UPDATE","PLAYER_GUILD_UPDATE","CHAT_MSG_SYSTEM","ADDON_ACTION_BLOCKED","ADDON_ACTION_FORBIDDEN","MACRO_ACTION_BLOCKED","MACRO_ACTION_FORBIDDEN"})do pcall(events.RegisterEvent,events,event)end
events:SetScript("OnEvent",function(_,event,value,...)
    if event=="NAME_PLATE_UNIT_ADDED"then if public(value)and type(value)=="string"and value:match("^nameplate%d+$")then local count=0;for _ in pairs(B.plates)do count=count+1 end;if count<128 and not B.plates[value]then B.plates[value]=true;B.candidateScan=nil end end
    elseif event=="NAME_PLATE_UNIT_REMOVED"then if public(value)and type(value)=="string"and B.plates[value]then B.plates[value]=nil;B.candidateScan=nil end
    elseif event=="PLAYER_TARGET_CHANGED"or event=="UPDATE_MOUSEOVER_UNIT"then B.candidateScan=nil
    elseif event=="CHAT_MSG_SYSTEM"then systemMessage(value)
    elseif event=="GUILD_ROSTER_UPDATE"then B.rosterDirty=true -- permission to request is not a request trigger
    elseif event=="PLAYER_GUILD_UPDATE"then if public(value)and value=="player"then B.rosterDirty=true;B.requestRoster=true end
    elseif event=="ADDON_ACTION_BLOCKED"or event=="ADDON_ACTION_FORBIDDEN"or event=="MACRO_ACTION_BLOCKED"or event=="MACRO_ACTION_FORBIDDEN"then rejectOwnedAction(event,value,select(1,...))
    elseif event=="PLAYER_REGEN_DISABLED"then closeEditor();retireTicket(now())
    else closeEditor();retireTicket(now());B.actionWindow=nil;B.pending={};B.samples={};B.plates={};B.roster=nil;B.rosterScan=nil;B.rosterDirty=true;B.requestRoster=true end
end)
