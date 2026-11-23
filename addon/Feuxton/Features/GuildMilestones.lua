-- Public guild roster changes and bounded social work. Observation never casts,
-- chats or promotes. Only the existing guild action key reserves a claim/use.
local _,ns=...
local M={prefix="FXGuildM1",claims={},levels={25,45,60},status=0}
ns.features.GuildMilestones=M
local function public(v)return type(issecretvalue)=="function"and not issecretvalue(v)end
local function call(fn,...)
 if type(fn)~="function"then return nil end
 local ok,v=pcall(fn,...);if not ok or not public(v)then return nil end;return v
end
local function number(v,max)return public(v)and type(v)=="number"and v==math.floor(v)and v>=0 and v<=(max or 2147483647)and v or nil end
local function identity(v)return public(v)and type(v)=="string"and #v>0 and #v<=64 and v:match("^[A-Za-z0-9%-]+$")and v or nil end
local function sameSender(sender,name,context)
 if not public(sender)or type(sender)~="string"then return false end
 if sender==name then return true end
 if not context.realm then return false end
 local realm=call(GetNormalizedRealmName);if type(realm)~="string"or realm==""then realm=context.realm:gsub("%s","")end
 return sender==name.."-"..realm
end
local function increment(s,key)s[key]=math.min(2147483647,(number(s[key])or 0)+1)end
local function succeeded(value,kind)
 if value==true then return true end
 local enums=type(Enum)=="table"and Enum[kind];local expected=type(enums)=="table"and call(function()return enums.Success end)
 return number(value)and number(expected)and value==expected or false
end
local function send(text)
 if not M.available then return false end
 local ok,value=pcall(C_ChatInfo.SendAddonMessage,M.prefix,text,"GUILD")
 return ok and public(value)and succeeded(value,"SendAddonMessageResult")
end
function M.configure(context,cfg)
 local enabled=cfg and cfg.enabled==true
 local owner=context.actor.."\31"..context.guild.."\31"..(context.scope or context.realm).."\31"..context.session
 if M.owner~=owner then M.owner=owner;M.claims={};M.scope=nil;M.baseline=true;M.lastMessage=nil;M.pending=0 end
 local s=context.ledger.milestones
 if type(s)~="table"or type(s.known)~="table"or type(s.events)~="table"then s={known={},events={},enabled=false,generation=0};context.ledger.milestones=s end
 if type(s.handled)~="table"then s.handled={}end
 M.scope=s;M.context=context;M.configuration=cfg
 if s.enabled~=enabled or s.generation~=(cfg and cfg.generation or 0)then s.enabled=enabled;s.generation=cfg and cfg.generation or 0;s.known={};s.events={};M.claims={};M.status=enabled and 1 or 0;return enabled end
 if not enabled then M.status=0 elseif M.status==0 then M.status=1 end;return false
end
local function eventKey(guid,level)return guid..":"..level end
function M.clear()
 if not M.context and not M.scope then return end
 M.owner=nil;M.scope=nil;M.context=nil;M.configuration=nil;M.roster=nil;M.pending=0;M.status=0;M.claims={};M.lastMessage=nil;M.baseline=true
end
function M.observe(context,roster,cfg)
 local s=M.scope;if not s or not cfg or not cfg.enabled then return end
 M.roster=roster;local present={};local eventCount=0;for _ in pairs(s.events)do eventCount=eventCount+1 end
 for guid,member in pairs(roster)do
  if identity(guid)and member.guid==guid and number(member.level,100)and member.level>0 and type(member.online)=="boolean"then
   present[guid]=true;local old=s.known[guid];s.known[guid]=number(old,100)and math.max(old,member.level)or member.level
   if not M.baseline and number(old,100)and member.level>old and member.online==true then
    for _,level in ipairs(M.levels)do
     local key=eventKey(guid,level)
     if old<level and member.level>=level and not s.events[key]and eventCount<64 then s.events[key]={guid=guid,name=member.name,level=level,at=context.utc,announced=s.handled[key]~=nil};eventCount=eventCount+1 end
    end
   end
  end
 end
 for guid in pairs(s.known)do if not present[guid]then s.known[guid]=nil end end
 for key in pairs(s.handled)do local guid=type(key)=="string"and key:match("^(.+):%d+$");if not guid or not present[guid]then s.handled[key]=nil end end
 for key,e in pairs(s.events)do
  local member=roster[e.guid]
  if not member or member.name~=e.name or not number(e.at)or context.utc-e.at>300 then s.events[key]=nil
  elseif e.waitRank and number(member.rank,9)and member.rank<e.waitRank then e.waitRank=nil;increment(s,"promoted") end
 end
 M.status=2;M.baseline=false
end
local function rankFor(name)
 if type(name)~="string"or name==""then return nil end
 local n=number(call(GuildControlGetNumRanks),10);if not n then return nil end
 local found
 for i=2,n do if call(GuildControlGetRankName,i)==name then if found then return nil end;found=i-1 end end
 return found -- zero (guild master) is deliberately never a target
end
function M.current(context,t,cfg,probe)
 local e=M.scope and M.scope.events[eventKey(t.guid,t.milestoneLevel)]
 local cached=M.roster and M.roster[t.guid];local member=cached and probe(cached.index)
 if not cfg or not cfg.enabled or not e or not member or member.guid~=e.guid or member.name~=e.name or member.online~=true or not number(member.level,100)or member.level<e.level or context.utc-e.at>300 then return nil end
 if t.kind==4 then return cfg.congratulate and not e.announced and e or nil end
 local rank=rankFor(cfg.ranks[e.level]);local own=M.roster and M.roster[context.actor]
 if rank and number(member.rank,9)and member.rank<=rank then return nil,rank,member.rank,true end
 if not rank or e.guid==context.actor or not number(member.rank,9)or not own or not number(own.rank,9)or rank<=own.rank or e.waitRank and(t.stage~=2 or e.waitRank~=t.currentRank)then return nil end
 local allowed=type(C_GuildInfo)=="table"and call(C_GuildInfo.IsGuildRankAssignmentAllowed,e.guid,rank+1)
 if call(CanGuildPromote)~=true or allowed~=true then return nil end
 if t.targetRank and(t.targetRank~=rank or t.currentRank~=member.rank)then return nil end
 return e,rank,member.rank
end
function M.owns(context,t)
 local c=M.claims[eventKey(t.guid,t.milestoneLevel)]
 return c and c.actor==context.actor and context.utc>=c.at+2 and context.utc<c.at+18
end
function M.claim(context,t)
 if not send("C|"..t.guid.."|"..t.milestoneLevel.."|"..context.actor.."|"..context.utc)then M.blockedUntil=context.utc+30;M.status=5;return false end
 local key=eventKey(t.guid,t.milestoneLevel);local old=M.claims[key]
 if not old or context.utc>=old.at+18 or context.actor<old.actor then M.claims[key]={actor=context.actor,at=context.utc}end
 return true
end
function M.reserve(context,t)
 local e=M.scope and M.scope.events[eventKey(t.guid,t.milestoneLevel)];if not e then return false end
 if t.kind==4 then
  if e.announced then return false end
  if not send("A|"..t.guid.."|"..t.milestoneLevel.."|"..context.actor.."|"..context.utc)then M.blockedUntil=context.utc+30;M.status=5;return false end
  e.announced=true;M.scope.handled[eventKey(t.guid,t.milestoneLevel)]=context.utc;increment(M.scope,"announcements");M.lastMessage={text=t.message,at=context.utc,actor=context.name,key=eventKey(t.guid,t.milestoneLevel)}
 else e.waitRank=t.currentRank;increment(M.scope,"promotionAttempts") end
 return true
end
function M.next(context,cfg,probe)
 M.pending=0;if not cfg or not cfg.enabled or not M.scope then M.status=0;return end
 local candidates={}
 for key,e in pairs(M.scope.events)do
  M.pending=M.pending+1
  local wanted=cfg.congratulate and not e.announced and 4 or cfg.ranks[e.level]~=""and 5 or nil
  if not wanted then M.scope.events[key]=nil;M.pending=M.pending-1
  else
   local claim=M.claims[key]
   if not claim or context.utc>=claim.at+18 or claim.actor==context.actor then candidates[#candidates+1]={kind=wanted,guid=e.guid,name=e.name,milestoneLevel=e.level,at=e.at,key=key}end
  end
 end
 if not M.available or M.blockedUntil and context.utc<M.blockedUntil then M.status=5;return end
 table.sort(candidates,function(a,b)if a.at~=b.at then return a.at<b.at end;if a.guid~=b.guid then return a.guid<b.guid end;return a.milestoneLevel<b.milestoneLevel end)
 -- Queue ordering is public retained state. Fresh native qualification stays
 -- bounded, including when every pending promotion is currently ineligible.
 for offset=1,math.min(4,#candidates)do
  local index=((M.scanCursor or 0)+offset-1)%#candidates+1;local c=candidates[index]
  local current,rank,old,done=M.current(context,c,cfg,probe)
  if done then M.scope.events[c.key]=nil;M.pending=M.pending-1
  elseif current then M.scanCursor=index;M.status=3;c.targetRank=rank;c.currentRank=old;return c.kind,c end
 end
 M.scanCursor=(M.scanCursor or 0)+math.min(4,#candidates);M.status=M.pending>0 and 4 or 2
end
function M.statistics()local s=M.scope or {};return M.status,M.pending or 0,number(s.announcements)or 0,number(s.confirmed)or 0,number(s.promoted)or 0 end
local events=CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_ADDON");events:RegisterEvent("CHAT_MSG_GUILD")
events:SetScript("OnEvent",function(_,event,...)
 if not M.scope or not M.context or not M.configuration or not M.configuration.enabled then return end
 if event=="CHAT_MSG_GUILD"then
  local text,sender=...;local last=M.lastMessage
  if last and public(text)and text==last.text and sameSender(sender,last.actor,M.context)and (call(GetServerTime)or 0)-last.at<=10 then increment(M.scope,"confirmed");M.lastMessage=nil end
  return
 end
 local prefix,text,channel,sender=...
 if not public(prefix)or prefix~=M.prefix or not public(text)or type(text)~="string"or #text>180 or not public(channel)or channel~="GUILD"then return end
 local mode,guid,level,actor,at=text:match("^([CA])|([A-Za-z0-9%-]+)|(%d+)|([A-Za-z0-9%-]+)|(%d+)$")
 level=tonumber(level);at=tonumber(at);local now=call(GetServerTime);local member=M.roster and M.roster[actor]
 if not member or not identity(guid)or not M.roster[guid]or not sameSender(sender,member.name,M.context)or not now or not at or math.abs(now-at)>18 or not(level==25 or level==45 or level==60)then return end
 local key=eventKey(guid,level);local old=M.claims[key]
 if mode=="C"then if not old or now>=old.at+18 or actor<old.actor then M.claims[key]={actor=actor,at=at}end
 else M.scope.handled[key]=at;if M.scope.events[key]then M.scope.events[key].announced=true end end
end)
local registration=type(C_ChatInfo)=="table"and call(C_ChatInfo.RegisterAddonMessagePrefix,M.prefix)
local registered=type(C_ChatInfo)=="table"and call(C_ChatInfo.IsAddonMessagePrefixRegistered,M.prefix)
M.available=type(C_ChatInfo)=="table"and type(C_ChatInfo.SendAddonMessage)=="function"and(registered==true or registered==nil and succeeded(registration,"RegisterAddonMessagePrefixResult"))
