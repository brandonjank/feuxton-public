-- Optional party-only benefit responsibility messages. They never cast spells,
-- mutate targets, claim aura coverage or act as a general command channel.
local _,ns=...
local B={protocol="FBC1",prefix="FeuxtonBuff1",peers={},sequence=0,cursor=0,queue={},queued={},successes={}}
ns.features.BuffCoordination=B
local units={"player","party1","party2","party3","party4"}
local function public(value)
 local S=ns.state
 if S.isSecret and S.isSecret(value)then return nil end
 return value
end
local function token(value,maximum)
 value=public(value)
 return type(value)=="string"and #value>0 and #value<=maximum and not value:find("[^%w_.%-]")and value or nil
end
local function integer(value,maximum)
 value=public(value)
 return type(value)=="number"and value==value and value>=0 and value<=maximum and value==math.floor(value)and value or nil
end
local function u32(packet,at)
 if type(packet)~="string"or #packet<at+3 then return nil end
 local a,b,c,d=packet:byte(at,at+3);return a+b*256+c*65536+d*16777216
end
function B.enabled()
 return type(public(FeuxtonDB))=="table"and public(FeuxtonDB.buffCoordination)==true
end
ns.state.buffCoordinationEnabled=B.enabled
ns.setBuffCoordinationEnabled=function(enabled)
 local S=ns.state
 if type(enabled)~="boolean"or S.readableCall(InCombatLockdown)~=false or S.isSecret(FeuxtonDB)then return false end
 if type(FeuxtonDB)~="table"then FeuxtonDB={}end
 FeuxtonDB.buffCoordination=enabled
 B.queue={};B.queued={};B.recentIntent=nil;B.successes={};B.peers={}
 return true
end
-- Reuse already published public roster identities. No second unit/aura scan
-- runs at the 100-ms cadence, and unknown rows never become absent members.
function B.context()
 local S=ns.state;local rows=S.transportPackets
 if type(rows)~="table"then return nil end
 local guids,byGuid={},{};local count,tick
 for i=1,5 do
  local row=rows[15+i];local packet=row and row.packet
  if type(packet)~="string"or #packet<25 or u32(packet,5)~=S.setupSession or packet:byte(13)~=i or packet:byte(14)~=1 then return nil end
  local currentCount=packet:byte(15);local currentTick=u32(packet,9)
  if currentCount>5 or count and count~=currentCount or tick and tick~=currentTick then return nil end
  count,tick=currentCount,currentTick
  local exists=packet:byte(16)%4;local size=packet:byte(21)
  if size>40 or #packet<21+size+4 or exists==0 or exists==3 then return nil end
  if exists==2 then
   local guid=token(packet:sub(22,21+size),40)
   if not guid or byGuid[guid]then return nil end
   guids[#guids+1]=guid;byGuid[guid]={unit=units[i],index=i-1,guid=guid}
  elseif size~=0 then return nil end
 end
 if #guids~=(count==0 and 1 or count)or not guids[1]then return nil end
 local localRow=rows[16].packet;local localGuid=localRow:sub(22,21+localRow:byte(21))
 if not byGuid[localGuid]or byGuid[localGuid].unit~="player"then return nil end
 table.sort(guids)
 local group=S.adler32(table.concat(guids,";"));local epoch=S.adler32("FBC1:"..table.concat(guids,";"))
 return {group=group,epoch=epoch,groupIdentity=tostring(group),groupEpoch=tostring(epoch),localGuid=localGuid,members=byGuid,rosterTick=tick,count=#guids}
end
local function allowed()
 local S=ns.state;local catalog=ns.buffCatalog
 if not catalog or type(S.buffProviderFamilies)~="function"then return {},{}end
 local ok,families=pcall(S.buffProviderFamilies)
 families=public(families)
 if not ok or type(families)~="table"or #families>24 then return {},{}end
 local result,seen={},{}
 for _,key in ipairs(families)do
  local definition=token(key,40)and catalog.byFamily[key]
  if definition and integer(definition.code,255)and definition.code>0 and not seen[key]then result[#result+1]=key;seen[key]=true end
 end
 table.sort(result);return result,seen
end
local function expire(now)
 for guid,peer in pairs(B.peers)do
  for key,row in pairs(peer.families)do
   if row.capAt and(now<row.capAt or now-row.capAt>=15)then row.capAt=nil;row.capSequence=nil end
   if row.intentAt and(now<row.intentAt or not row.intentUntil or now>=row.intentUntil)then row.intentAt=nil;row.intentSequence=nil;row.intentUntil=nil;row.recipient=nil end
   if not row.capAt and not row.intentAt then peer.families[key]=nil end
  end
  for boot,at in pairs(peer.retired)do if now<at or now-at>=15 then peer.retired[boot]=nil end end
  if not next(peer.families)then B.peers[guid]=nil end
 end
end
local function reset(context)
 local stamp=context and context.groupIdentity..":"..context.groupEpoch..":"..context.localGuid..":"..tostring(ns.state.setupSession)or nil
 if stamp~=B.contextStamp then B.contextStamp=stamp;B.peers={};B.queue={};B.queued={};B.recentIntent=nil;B.successes={};B.nextHeartbeat=0 end
end
local function frame(context,family,recipient,lease)
 B.sequence=(B.sequence+1)%4294967296
 local text=table.concat({B.protocol,context.groupIdentity,context.groupEpoch,tostring(ns.state.setupSession),context.localGuid,tostring(B.sequence),family,recipient or "",tostring(lease or 0)},"|")
 return #text<=255 and text or nil
end
local function queue(family,recipient,lease,at)
 local key=family.."|"..(recipient or "")
 if B.queued[key]then return end
 if #B.queue>=29 then return end
 B.queue[#B.queue+1]={family=family,recipient=recipient,lease=lease,key=key,at=at};B.queued[key]=true
end
local function send(context,row)
 local api=type(C_ChatInfo)=="table"and C_ChatInfo or {}
 if context.count<2 or not B.registered or type(api.SendAddonMessage)~="function"then return false end
 local text=frame(context,row.family,row.recipient,row.lease)
 if not text then return false end
 local ok=pcall(api.SendAddonMessage,B.prefix,text,"PARTY")
 return ok
end
local function now()
 return ns.state.readableCall(GetTime)
end
function B.intent(key,guid)
 local time=now();local context=B.context();reset(context)
 if not B.enabled()or not context or type(time)~="number"or not context.members[guid]then return false end
 local effect=ns.buffCatalog and ns.buffCatalog.byAbility[key];local family=effect and effect.familyKey or key
 local _,families=allowed();if not families[family]then return false end
 B.recentIntent=time;queue(family,guid,2000,time);return true
end
function B.success(key)
 local time=now();local context=B.context();reset(context)
 if not B.enabled()or not context or type(time)~="number"then return false end
 local effect=ns.buffCatalog and ns.buffCatalog.byAbility[key];local family=effect and effect.familyKey or key
 local _,families=allowed();if not families[family]then return false end
 B.successes[family]=time;B.nextHeartbeat=0;return true
end
ns.state.buffPeerIntent=B.intent
ns.state.buffPeerSuccess=B.success
local function senderGuid(sender,context)
 local G=ns.features.GroupContext;local found
 sender=public(sender);if type(sender)~="string"or #sender==0 or #sender>128 then return nil end
 for guid,member in pairs(context.members)do
  if G.text(G.read(UnitGUID,1,member.unit),40)==guid then
  local name=G.text(G.read(UnitFullName or UnitName,1,member.unit),64)
  local realm=type(UnitFullName)=="function"and G.text(G.read(UnitFullName,2,member.unit),64)or ""
  local full=realm~=""and name.."-"..realm or name
  if name~=""and(sender==full or sender==name and not sender:find("-",1,true))then
   if found and found~=guid then return nil end
   found=guid
  end
  end
 end
 return found
end
function B.receive(prefix,message,channel,sender,time)
 prefix,channel=public(prefix),public(channel)
 if prefix~=B.prefix or channel~="PARTY"or not B.enabled()or type(public(message))~="string"or #message>255 or type(time)~="number"then return false end
 local context=B.context();reset(context);if not context then return false end
 expire(time)
 local parts={};for part in(message.."|"):gmatch("([^|]*)|")do parts[#parts+1]=part end
 if #parts~=9 or parts[1]~=B.protocol or parts[2]~=context.groupIdentity or parts[3]~=context.groupEpoch then return false end
 if #parts[4]>10 or #parts[6]>10 or #parts[9]>4 or not parts[4]:match("^%d+$")or not parts[6]:match("^%d+$")or not parts[9]:match("^%d+$")then return false end
 local boot=integer(tonumber(parts[4]),4294967295);local provider=token(parts[5],40);local seq=integer(tonumber(parts[6]),4294967295)
 local family=token(parts[7],40);local recipient=parts[8];local lease=integer(tonumber(parts[9]),2000)
 if not boot or boot==0 or not provider or provider==context.localGuid or not seq or not family or not lease or not ns.buffCatalog.byFamily[family]or senderGuid(sender,context)~=provider then return false end
 local G=ns.features.GroupContext;local class=G.text(G.read(UnitClass,2,context.members[provider].unit),16)
 local owner=ns.classes[class];local supported=false
 for _,key in ipairs(owner and owner.buffAbilityKeys or {})do local effect=ns.buffCatalog.byAbility[key];if effect and effect.familyKey==family then supported=true;break end end
 if not supported then return false end
 if lease>0 and not context.members[recipient]or lease==0 and recipient~=""then return false end
 local peer=B.peers[provider]or {families={},retired={}}
 if peer.boot and peer.boot~=boot then
  if peer.retired[boot]then return false end
  local count=0;for _ in pairs(peer.retired)do count=count+1 end;if count>=2 then return false end
  peer.retired[peer.boot]=time;peer.families={};peer.sequence=nil
 end
 if peer.sequence then local delta=(seq-peer.sequence)%4294967296;if delta==0 or delta>=2147483648 then return false end end
 local count=0;for _ in pairs(peer.families)do count=count+1 end
 if not peer.families[family]and count>=24 then return false end
 peer.boot=boot;peer.sequence=seq;local row=peer.families[family]or{}
 if lease>0 then row.intentAt=time;row.intentSequence=seq;row.recipient=recipient;row.intentUntil=time+lease/1000
 else row.capAt=time;row.capSequence=seq end
 peer.families[family]=row
 B.peers[provider]=peer;return true
end
function B.update(time)
 time=public(time);if type(time)~="number"or time~=time or time==math.huge or time==-math.huge then return nil end
 local context=B.context();reset(context);if not context then return nil end
 expire(time)
 if not B.enabled()then B.peers={};B.queue={};B.queued={};return context end
 -- Success timestamps are protocol history, not cached native game reads.
 -- Idle peer publication needs no spell/usability query. Requalify current
 -- capabilities only at an actual heartbeat or managed intent/success.
 local activeSuccess=false
 for family,at in pairs(B.successes)do if time<at or time-at>=15 then B.successes[family]=nil else activeSuccess=true end end
 local active=activeSuccess or B.recentIntent and time>=B.recentIntent and time-B.recentIntent<2
 if activeSuccess and time>=(B.nextHeartbeat or 0)then
  local _,allowedFamilies=allowed();local families={}
  for family in pairs(B.successes)do if allowedFamilies[family]then families[#families+1]=family else B.successes[family]=nil end end;table.sort(families)
  for _,family in ipairs(families)do queue(family,nil,0)end;B.nextHeartbeat=time+5
 end
 if not active then B.queue={};B.queued={}end
 for unused=1,4 do
  if #B.queue==0 then break end
  local row=table.remove(B.queue,1);B.queued[row.key]=nil
  -- Intent lifetime is bounded from actual managed invocation, not from a
  -- later queued sender callback. Expired pending intents become heartbeats.
  if row.lease and row.lease>0 then local remaining=row.at and math.floor(math.max(0,2-(time-row.at))*1000)or 0;if remaining>0 then row.lease=remaining;send(context,row)end
  else send(context,row)end
 end
 return context
end
function B.snapshot(time)
 local context=B.update(time);if not context then return nil end
 local rows={}
 for guid,peer in pairs(B.peers)do for family,row in pairs(peer.families)do
  local useIntent=row.intentAt and(not row.capSequence or(row.intentSequence-row.capSequence)%4294967296<2147483648)
  local remaining=useIntent and math.floor(math.max(0,row.intentUntil-time)*1000)or 0
  local recipient=remaining>0 and context.members[row.recipient]or nil
  local at=useIntent and row.intentAt or row.capAt
  rows[#rows+1]={providerGuid=guid,providerBoot=peer.boot,sequence=useIntent and row.intentSequence or row.capSequence,familyKey=family,ageMs=math.floor((time-at)*1000),intentOnly=useIntent==true,intentUnit=recipient and recipient.index or 255,intentIdentity=recipient and recipient.guid or nil,intentRemainingMs=remaining}
 end end
 table.sort(rows,function(a,b)return a.providerGuid==b.providerGuid and a.familyKey<b.familyKey or a.providerGuid<b.providerGuid end)
 return {context=context,enabled=B.enabled(),peers=rows}
end
ns.state.buffPeerSnapshot=B.snapshot
function B.packet(time,tick)
 local snapshot=B.snapshot(time);if not snapshot then return nil end
 local S=ns.state;local context=snapshot.context;local row
 if #snapshot.peers>0 then B.cursor=B.cursor%#snapshot.peers+1;row=snapshot.peers[B.cursor]end
 row=row or {providerGuid=context.localGuid,providerBoot=S.setupSession,sequence=0,familyKey=nil,ageMs=0,intentUnit=255,intentRemainingMs=0}
 local family=row.familyKey and ns.buffCatalog.byFamily[row.familyKey]
 local packet="HHU1"..S.bytes(S.setupSession,4)..S.bytes(tick,4)..S.bytes(128,1)..S.bytes((snapshot.enabled and 1 or 0)+(row.intentOnly and 2 or 0),1)..S.bytes(context.group,4)..S.bytes(context.epoch,4)..S.bytes(row.providerBoot,4)..S.bytes(row.sequence,4)..S.bytes(math.min(14999,row.ageMs),2)..S.bytes(family and family.code or 0,1)..S.bytes(#row.providerGuid,1)..row.providerGuid..S.bytes(row.intentUnit,1)..S.bytes(row.intentIdentity and S.adler32(row.intentIdentity)or 0,4)..S.bytes(math.min(2000,row.intentRemainingMs),2)..S.bytes(context.rosterTick,4)
 packet=packet..S.bytes(S.adler32(packet),4)
 return #packet<=110 and packet or nil
end
local api=type(C_ChatInfo)=="table"and C_ChatInfo or {}
if type(api.RegisterAddonMessagePrefix)=="function"then local ok,value=pcall(api.RegisterAddonMessagePrefix,B.prefix);B.registered=ok and public(value)==true end
if not B.registered and type(api.IsAddonMessagePrefixRegistered)=="function"then local ok,value=pcall(api.IsAddonMessagePrefixRegistered,B.prefix);B.registered=ok and public(value)==true end
if type(CreateFrame)=="function"then
 local events=CreateFrame("Frame");events:RegisterEvent("CHAT_MSG_ADDON");events:RegisterEvent("GROUP_ROSTER_UPDATE");events:RegisterEvent("PLAYER_ENTERING_WORLD")
 events:SetScript("OnEvent",function(_,event,...)
  if event=="CHAT_MSG_ADDON"then local time=now();local prefix,message,channel,sender=...;if type(time)=="number"then B.receive(prefix,message,channel,sender,time)end
  else reset(nil)end
 end)
end
