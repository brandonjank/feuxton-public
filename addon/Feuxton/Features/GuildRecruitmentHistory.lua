-- Guild-only suppression replication. These messages never invite or chat.
local _,ns=...
local H={prefix="FXGuildR1",limit=2048,maximum=720*3600}
ns.features.GuildRecruitmentHistory=H
local function public(v)local ok,s=pcall(issecretvalue,v);return ok and not s end
local function call(f,...)if type(f)~="function"then return end;local ok,v=pcall(f,...);if ok and public(v)then return v end end
local function number(v,max)return public(v)and type(v)=="number"and v>=0 and v==math.floor(v)and v<=(max or 2147483647)and v or nil end
local function success(v,kind)
 if v==true then return true end
 local e=type(Enum)=="table"and Enum[kind];local expected=type(e)=="table"and call(function()return e.Success end)
 return number(v)and number(expected)and v==expected or false
end
local function send(text)
 if not H.available or #text>255 or call(C_ChatInfo.InChatMessagingLockdown)~=false then return false end
 local ok,v=pcall(C_ChatInfo.SendAddonMessage,H.prefix,text,"GUILD")
 return ok and public(v)and success(v,"SendAddonMessageResult")
end
local function key(c)
 if c.realm then return c.realm.."\31"..c.guild end
 if type(c.scope)=="string"and c.scope:match("^@club:[1-9]%d*$")then return c.scope end
end
local function encode(guid,row)return row.name.."|"..guid.."|"..row.attempted.."|"..row.untilAt.."|"..(row.result=="declined"and "D"or "A")end
local function merge(s,guid,row,c)
 if not s or not H.text or not H.text(row.name,96)or not H.text(guid,128)then return false end
 if not number(row.attempted)or not number(row.untilAt)or row.attempted>c.utc+5 or row.untilAt<=c.utc or row.untilAt<row.attempted or row.untilAt-row.attempted>H.maximum then return false end
 local oldKey=s.names[row.name];local old=oldKey and s.records[oldKey]
 if not old then
  -- A retained GUID with conflicting names is ambiguous. Never overwrite a
  -- live hold while rebuilding a history from independently saved ledgers.
  if s.records[guid]then s.blockedUntil=math.max(s.blockedUntil or 0,row.untilAt);return false end
  if H.count>=H.limit then H.full=true;s.blockedUntil=math.max(s.blockedUntil or 0,row.untilAt);return false end
  oldKey=guid;old={name=row.name,attempted=row.attempted,untilAt=row.untilAt,result=row.result};s.records[oldKey]=old;s.names[row.name]=oldKey;H.count=H.count+1
 else
  old.untilAt=math.max(old.untilAt,row.untilAt);old.attempted=math.max(old.attempted or 0,row.attempted)
  if row.result=="declined"then old.result="declined"end
 end
 return true,oldKey,old
end
local function rebuild(store,c,historyKey,hours)
 if store.histories~=nil and type(store.histories)~="table"then return end
 local histories=store.histories or {}
 local current={records={},names={}}
 local sources,seen={},{}
 local function addRows(rows)
  if type(rows)~="table"then return false end
  if not seen[rows]then sources[#sources+1]=rows;seen[rows]=true end
  return true
 end
 local function addHistory(scope)
  local history=histories[scope]
  if history==nil then return true end
  if type(history)~="table"or type(history.names)~="table"or not addRows(history.records)then return false end
  if history.blockedUntil~=nil then
   local hold=number(history.blockedUntil)
   if not hold then return false end
   current.blockedUntil=math.max(current.blockedUntil or 0,hold)
  end
  return true
 end
 if not addHistory(historyKey)or not addRows(c.ledger.records)then return end
 local legacyKey=historyKey
 if not c.realm then
  legacyKey=c.legacyRealm and (c.legacyRealm.."\31"..(c.legacyGuild or c.guild))
  if legacyKey and not addHistory(legacyKey)then return end
  if store.clubActors~=nil and type(store.clubActors)~="table"then return end
  local actors=store.clubActors and store.clubActors[historyKey]
  if actors~=nil and type(actors)~="table"then return end
  for _,ledger in pairs(actors or {})do
   if type(ledger)~="table"or not addRows(ledger.records)then return end
  end
 end
 if legacyKey then
  local prefix=legacyKey.."\31"
  for scopeKey,ledger in pairs(store.scopes)do
   if type(scopeKey)=="string"and scopeKey:sub(1,#prefix)==prefix then
    if type(ledger)~="table"or not addRows(ledger.records)then return end
   end
  end
 end
 for _,rows in ipairs(sources)do
  for guid,row in pairs(rows)do
   if type(row)~="table"or not number(row.untilAt)then return end
   local expires=row.untilAt
   local at=number(row.attempted)or math.max(0,expires-86400)
   -- Preserve the old 24-hour upgrade only on its original realm path.
   -- Club migration copies active absolute expiries without reviving holds.
   if c.realm and not row.sharedVersion then
    at=math.max(at,expires-86400)
    expires=math.max(expires,at+(hours or 72)*3600)
   end
   if expires>c.utc then
    local ok,_,stored=merge(current,guid,{name=row.name,attempted=at,untilAt=expires,result=row.result},c)
    if not ok then return end
    stored.sharedVersion=1
   end
  end
 end
 return current
end
function H.attach(store,c,text,hours)
 H.text=text
 local historyKey=key(c);if not historyKey then return false end
 local owner=historyKey.."\31"..c.actor.."\31"..c.session
 if H.retryOwner==owner and c.at<(H.retryAt or 0)then return false end
 if H.owner~=owner then
  H.owner=owner;H.scope=nil;H.roster=nil;H.context=c;H.tasks={};H.peers={};H.known={};H.dirty={};H.count=0;H.full=false;H.peerOverflow=false;H.nextSend=0;H.needRequest=true;H.sent=false;H.readyAt=c.at+3;H.lastRequest=nil
  local api=type(C_ChatInfo)=="table"and C_ChatInfo
  local registered=api and call(api.IsAddonMessagePrefixRegistered,H.prefix)
  local registration=api and call(api.RegisterAddonMessagePrefix,H.prefix)
  H.available=api and type(api.SendAddonMessage)=="function"and(registered==true or success(registration,"RegisterAddonMessagePrefixResult"))or false
  local rebuilt=rebuild(store,c,historyKey,hours)
  if not rebuilt then
   H.owner=nil;H.retryOwner=owner;H.retryAt=c.at+30
   return false
  end
  store.histories=store.histories or {}
  store.histories[historyKey]=rebuilt;H.scope=rebuilt
  H.retryOwner=nil
 end
 if not H.scope then return false end
 c.ledger.records=H.scope.records;c.ledger.names=H.scope.names
 H.context=c;return true
end
local function senderActor(sender,c)
 if not public(sender)or type(sender)~="string"or not H.roster then return end
 local realm
 if c.realm then
  realm=call(GetNormalizedRealmName)
  if type(realm)~="string"or realm==""then realm=c.realm:gsub("%s","")end
 end
 local actor
 for guid,row in pairs(H.roster)do
  if sender==row.name or realm and sender==row.name.."-"..realm then
   if actor or row.guid~=guid or guid==c.actor then return end
   actor=guid
  end
 end
 return actor
end
local function enqueue(sender,nonce,c)
 for index,task in ipairs(H.tasks)do if task.actor==sender then if task.nonce==nonce then return end;table.remove(H.tasks,index);break end end
 if #H.tasks>=8 then return end
 local rows={}
 for guid,row in pairs(H.scope.records)do if row.untilAt>c.utc then rows[#rows+1]=encode(guid,row)end end
 table.sort(rows)
 local hash=0;for _,row in ipairs(rows)do hash=(hash+ns.state.adler32(row))%4294967296 end
 H.tasks[#H.tasks+1]={actor=sender,nonce=nonce,rows=rows,index=0,hash=hash}
end
function H.ready(c)
 if not H.scope or not H.available or not H.sent or(not c.realm and (not H.roster or H.needRequest))or H.full or H.peerOverflow or(H.scope.blockedUntil or 0)>c.utc or c.at<H.readyAt then return false end
 for _,peer in pairs(H.peers)do if not peer.complete then return false end end
 return true
end
function H.reserve(c,candidate,hours)
 local row={name=candidate.name,attempted=c.utc,untilAt=c.utc+hours*3600,result="unknown"}
 local ok,guid,stored=merge(H.scope,candidate.guid,row,c)
 if not ok then return false end
 stored.sharedVersion=1
 local payload=encode(guid,stored);H.dirty[guid]=payload
 if send("U|"..payload)then H.dirty[guid]=nil;return true end
 return false
end
function H.declined(c,guid,hours)
 local row=H.scope and H.scope.records[guid];if not row then return end
 row.attempted=c.utc;row.untilAt=math.max(row.untilAt,c.utc+hours*3600);row.result="declined";row.sharedVersion=1
 local payload=encode(guid,row);H.dirty[guid]=payload
 if send("U|"..payload)then H.dirty[guid]=nil end
end
function H.step(c,roster)
 if not H.scope then return end
 if not c.realm and not roster then H.invalidateRoster() end
 H.context=c;H.roster=roster
 if not roster or not H.available then return end
 -- Re-request incomplete transfers. Never expire a known incomplete peer
 -- into permission to invite from an unconfirmed history.
 if H.lastRequest then for _,peer in pairs(H.peers)do if not peer.complete and c.at-(peer.progress or H.lastRequest)>=30 then H.needRequest=true;break end end end
 if c.at<H.nextSend then return end;H.nextSend=c.at+.25
 if H.needRequest then
  H.nonce=(H.nonce or c.session)%4294967295+1
  if send("Q|"..c.session.."|"..H.nonce)then
   local waiting={}
   if not c.realm then
    for actor,peer in pairs(H.peers)do
     local member=roster[actor]
     if not peer.complete and member and member.online~=false then waiting[actor]={complete=false,progress=c.at} end
    end
   end
   H.needRequest=false;H.sent=true;H.lastRequest=c.at;H.readyAt=c.at+3;H.peers=waiting
  else H.sent=false;H.nextSend=c.at+2 end
  return
 end
 for guid,payload in pairs(H.dirty)do if send("U|"..payload)then H.dirty[guid]=nil else H.nextSend=c.at+2 end;return end
 local task=H.tasks[1];if not task then return end
 local text=task.index==0 and "B|"..task.nonce.."|"..#task.rows or task.index<=#task.rows and "R|"..task.nonce.."|"..task.index.."|"..task.rows[task.index]or "E|"..task.nonce.."|"..#task.rows.."|"..task.hash
 if send(text)then task.index=task.index+1;if task.index>#task.rows+1 then table.remove(H.tasks,1)end else H.nextSend=c.at+2 end
end
function H.invalidateRoster()
 if H.context and not H.context.realm and H.roster then
  H.needRequest=true;H.sent=false
 end
 H.roster=nil
end
function H.receive(prefix,text,channel,sender)
 local c=H.context
 if not c or not H.scope or not public(prefix)or prefix~=H.prefix or not public(text)or type(text)~="string"or #text>255 or not public(channel)or channel~="GUILD"then return end
 local actor=senderActor(sender,c);if not actor then return end
 local function integerText(v,max)local n=tonumber(v);return number(n,max)and tostring(n)==v and n or nil end
 local session,request=text:match("^Q|(%d+)|(%d+)$")
 if session then
  session=integerText(session,4294967295);request=integerText(request,4294967295);if not session or not request or request==0 then return end
  if H.known[actor]~=session then H.known[actor]=session;if H.sent then H.needRequest=true end end
  enqueue(actor,request,c);return
 end
 local nonce,count=text:match("^B|(%d+)|(%d+)$")
 if nonce then
  nonce=integerText(nonce,4294967295);count=integerText(count,H.limit)
  local peers=0;for _ in pairs(H.peers)do peers=peers+1 end
  if nonce==H.nonce and count and H.lastRequest and c.at-H.lastRequest>=0 and c.at-H.lastRequest<=600 then
   if peers>=32 and not H.peers[actor]then H.peerOverflow=true;return end
   H.peers[actor]={count=count,seen={},received=0,hash=0,complete=false,progress=c.at}
  end;return
 end
 local n,index,payload=text:match("^R|(%d+)|(%d+)|(.+)$")
 local update=text:match("^U|(.+)$")
 if payload or update then
  local peer=H.peers[actor];local i=index and integerText(index,H.limit)
  if payload and(tonumber(n)~=H.nonce or not peer or not peer.count or not i or i<1 or i>peer.count or peer.seen[i])then return end
  local name,guid,at,untilAt,result=(payload or update):match("^([^|]+)|([^|]+)|(%d+)|(%d+)|([AD])$")
  at=at and integerText(at);untilAt=untilAt and integerText(untilAt)
  if not name or not at or not untilAt then return end
  if not merge(H.scope,guid,{name=name,attempted=at,untilAt=untilAt,result=result=="D"and "declined"or "unknown"},c)then return end
  local stored=H.scope.records[H.scope.names[name]];stored.sharedVersion=1
  if payload then peer.seen[i]=true;peer.received=peer.received+1;peer.hash=(peer.hash+ns.state.adler32(payload))%4294967296;peer.progress=c.at end
  return
 end
 local finish,total,hash=text:match("^E|(%d+)|(%d+)|(%d+)$");local peer=H.peers[actor]
 if peer and tonumber(finish)==H.nonce and tonumber(total)==peer.count and peer.received==peer.count and tonumber(hash)==peer.hash then peer.complete=true end
end
local events=CreateFrame("Frame");events:RegisterEvent("CHAT_MSG_ADDON")
for _,event in ipairs({"PLAYER_ENTERING_WORLD","PLAYER_LEAVING_WORLD","PLAYER_GUILD_UPDATE"})do events:RegisterEvent(event)end
events:SetScript("OnEvent",function(_,event,...)
 if event=="CHAT_MSG_ADDON"then H.receive(...)
 elseif event~="PLAYER_GUILD_UPDATE"or public((...))and (...)=="player"then H.context=nil;H.owner=nil end
end)
