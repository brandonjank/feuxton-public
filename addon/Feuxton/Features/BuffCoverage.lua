-- Optional, bounded public OOC benefit pages. No gameplay commands or raw
-- restricted values are retained; loss of this page never removes core data.
local _,ns=...
local B={cursor=0,identities={},urgentBurst=0}
ns.features.BuffCoverage=B
local units={"player","party1","party2","party3","party4","focus","target","mouseover"}
local function number(value,low,high)
 return not ns.state.isSecret(value) and type(value)=="number" and value==value and value~=math.huge and value~=-math.huge and value>=low and value<=high and value or nil
end
local function observed(v)return {status="observed",value=v}end
-- These costs are native values for the exact prepared ranks in one HHU1
-- publication. No restricted scalar is inspected, retained, or encoded in RGB.
function B.invalidateNativeCosts()
 local native=B.nativeCosts;if not native then return end
 native.marker:SetVertexColor(0,0,0,1)
 for _,cell in ipairs(native.stamp)do cell:SetVertexColor(0,0,0,1)end
end
local function renderNativeCosts(packet,readings)
 local S=ns.state;local F=ns.features.Healing;local bridge=ns.features.SpellBridge
 if not F or F.classKey~="PALADIN" or F.druid or not S.paladinNativePanel or not bridge or #readings~=3 then return end
 local native=B.nativeCosts
 if not native then
  local panel=S.paladinNativePanel
  local function cell(x)
   local texture=panel:CreateTexture(nil,"OVERLAY");texture:SetSize(4,4);texture:SetPoint("TOPLEFT",x,-24)
   texture:SetColorTexture(1,1,1,1);texture:SetVertexColor(0,0,0,1);return texture
  end
  native={widgets={},stamp={},marker=cell(620)};B.nativeCosts=native
  for i=1,3 do native.widgets[i]=bridge.createManaCost(panel,326+(i-1)*98,24,88)end
  for i=1,4 do native.stamp[i]=cell(626+(i-1)*6)end
 end
 for i,reading in ipairs(readings)do bridge.renderManaCost(native.widgets[i],reading.id,reading.learned)end
 -- Publish the certificate last. A failed/partial render remains ineligible.
 for i=1,4 do local value=packet:byte(#packet-4+i)/255;native.stamp[i]:SetVertexColor(value,value,value,1)end
 native.marker:SetVertexColor(0,1,1,1)
end
local nameIndex,relations={},{}
for _,effect in ipairs(ns.buffCatalog and ns.buffCatalog.effects or {})do
 for _,name in ipairs({effect.displayName,unpack(effect.aliases or {})})do
  if type(name)=="string"then local previous=nameIndex[name];if previous==nil then nameIndex[name]=effect elseif previous~=false and previous.familyKey~=effect.familyKey then nameIndex[name]=false end end
 end
end
for _,relation in ipairs(ns.buffCatalog and ns.buffCatalog.relations or {})do
 if relation.kind=="Unqualified"then relations[relation.left]=relations[relation.left]or {};relations[relation.left][relation.right]=true;relations[relation.right]=relations[relation.right]or {};relations[relation.right][relation.left]=true end
end
function B.initialize()
 if B.events then return end
 B.events=CreateFrame("Frame",nil,UIParent)
 for _,event in ipairs({"UNIT_AURA","UNIT_LEVEL","PLAYER_TARGET_CHANGED","UPDATE_MOUSEOVER_UNIT","GROUP_ROSTER_UPDATE"})do pcall(B.events.RegisterEvent,B.events,event)end
 B.events:SetScript("OnEvent",function(_,event,unit)
  local F=ns.features.Healing;if not F then return end
  if event=="PLAYER_TARGET_CHANGED"then F.cache.target=nil
  elseif event=="UPDATE_MOUSEOVER_UNIT"then F.cache.mouseover=nil
  elseif event=="GROUP_ROSTER_UPDATE"then F.cache={};B.identities={}
  elseif not ns.state.isSecret(unit) and type(unit)=="string"then F.cache[unit]=nil end
 end)
end
local function specs()
 local F=ns.features.Healing
 return F and F.buffSpecs and F.buffSpecs() or {}
end
function ns.state.buffProviderFamilies()
 local F=ns.features.Healing;local S=ns.state;local result={};local seen={}
 for _,spec in ipairs(specs())do
  local effect=ns.buffCatalog and ns.buffCatalog.byAbility[spec.key]
  local entry=F.delivery(spec);local spell=F.spell(spec,"player")
  if effect and entry and spell.learned.value==true and spell.usable.value==true and spell.mana.value==false and S.spellUseCode(spec.key)~=1 and not seen[effect.familyKey]then seen[effect.familyKey]=true;result[#result+1]=effect.familyKey end
 end
 return result
end
if type(ns.state.buffCoordinationEnabled)~="function"then function ns.state.buffCoordinationEnabled()return type(FeuxtonDB)=="table"and FeuxtonDB.buffCoordination==true end end
local function identity(unit)
 local G=ns.features.GroupContext
 if G.read(UnitExists,1,unit).value~=true or G.read(UnitIsPlayer,1,unit).value~=true or G.read(UnitCanAssist,1,"player",unit).value~=true or G.read(UnitIsDeadOrGhost,1,unit).value~=false or G.read(UnitIsConnected,1,unit).value~=true or G.read(UnitIsVisible,1,unit).value~=true then return "" end
 return G.text(G.read(UnitGUID,1,unit),40)
end
local function family(spec)
 local catalog=ns.buffCatalog
 return catalog and catalog.byAbility and catalog.byAbility[spec.key]
end
local function familyMatch(auraID,name,wanted)
 local catalog=ns.buffCatalog;local known=catalog and catalog.auraIndex and catalog.auraIndex[auraID]
 if known and known.familyKey==wanted.familyKey then return true,known end
 -- Existing class buff names remain readable evidence, but this does not
 -- promote an unqualified external/placement spell into a known aura alias.
 if wanted.sourceKind~="camp" and (name==wanted.displayName or name==wanted.name) then return true,nil end
 local named=nameIndex[name]
 if named and named.sourceKind=="class" and named.familyKey==wanted.familyKey then return true,nil end
 return false
end
function B.scan(unit,guid,now)
 local F=ns.features.Healing;local G=ns.features.GroupContext;local S=ns.state
 local unknown={{},{},{}}
 if S.readableCall(InCombatLockdown)~=false or type(now)~="number" then return unknown,nil,{} end
 local cached=F.cache[unit]
 if cached and cached.identity==guid and cached.buffEntries and now>=cached.at and now-cached.at<.25 then return cached.values,cached.at,cached.buffEntries end
 local definitions=specs();local result,values={},{{},{},{}};local protected,protectedUnknown=false,false
 for _,spec in ipairs(definitions)do result[spec.key]={}end
 local api=type(C_UnitAuras)=="table" and C_UnitAuras or {};local complete=false
 if type(api.GetAuraDataByIndex)=="function" then
  for index=1,80 do
   local ok,aura=pcall(api.GetAuraDataByIndex,unit,index,"HELPFUL")
   if not ok or S.isSecret(aura)then break end
   if aura==nil then complete=true;break end
   local name=G.text(G.field(aura,"name"),80)
   if name==""then break end
   local spell=G.field(aura,"spellId");local auraID=spell.status=="observed" and number(spell.value,1,2147483647)
   if auraID and auraID~=math.floor(auraID)then auraID=nil end
   local catalog=ns.buffCatalog;local exact=catalog and catalog.auraIndex and catalog.auraIndex[auraID];local named=nameIndex[name]
   if exact and exact.protectedEffect then
    local source=G.text(G.field(aura,"sourceUnit"),16);local owns=source~="" and G.read(UnitIsUnit,1,source,"player")or {}
    if owns.status=="observed" and owns.value==true then protected=true elseif owns.status~="observed"then protectedUnknown=true end
   end
   for i,spec in ipairs(definitions)do
    local definition=family(spec);local matches,known=false,nil
    if definition then matches,known=familyMatch(auraID,name,definition)else matches=name==spec.name end
    local related=exact or named
    if definition and related and ((relations[definition.key]and relations[definition.key][related.key])or related.sourceKind=="camp" and not exact and related.familyKey==definition.familyKey)then
     local row=result[spec.key];row.relationshipUnqualified=true;row.relatedID=row.relatedID or auraID;row.unqualifiedCamp=row.unqualifiedCamp or related.sourceKind=="camp"
    end
    if matches then
     local row=result[spec.key];row.present=observed(true)
     local source=G.text(G.field(aura,"sourceUnit"),16);local owns=source~="" and G.read(UnitIsUnit,1,source,"player") or {}
     local mine;if owns.status=="observed"then mine=owns.value end
     local ordinary=not known or known.sourceKind~="camp"
     if ordinary then
      local legacy=values[i];legacy.present=observed(true)
      if mine==true then legacy.own=observed(true)elseif mine==false then legacy.other=observed(true)else legacy.unknownOwner=true end
     end
     if mine==true then row.own=observed(true)elseif mine==false then row.other=observed(true)else row.unknownOwner=true end
     if not row.auraID or not row.ownClass and mine==true or ordinary and mine==true then
      row.auraID=auraID;row.sourceKind=known and known.sourceKind
      row.ownClass=ordinary and mine==true
      row.providerGuid=source~=""and G.text(G.read(UnitGUID,1,source),40)or nil
      local expiration=G.field(aura,"expirationTime");local ending=expiration.status=="observed" and number(expiration.value,0,math.huge)
      row.remainingSeconds=ending and ending>0 and math.min(65534,math.floor(math.max(0,ending-now))) or nil
     end
    end
   end
  end
 end
 for i,spec in ipairs(definitions)do
  local row=result[spec.key]
  if complete and not row.present then row.present=observed(false)end
  if complete and row.present and row.present.value==false then row.own=observed(false);row.other=observed(false)
  elseif complete and not row.unknownOwner and(row.own or row.other)then row.own=row.own or observed(false);row.other=row.other or observed(false)end
  local legacy=values[i]
  if legacy then
   if complete and not legacy.present then legacy.present=observed(false)end
   if complete and legacy.present and legacy.present.value==false then legacy.own=observed(false);legacy.other=observed(false)
   elseif complete and not legacy.unknownOwner and(legacy.own or legacy.other)then legacy.own=legacy.own or observed(false);legacy.other=legacy.other or observed(false)end
  end
 end
 F.cache[unit]={identity=guid,at=now,values=values,buffEntries=result,slotProtected=protected and observed(true)or complete and not protectedUnknown and observed(false)or {}};return values,now,result
end
local function choose()
 local F=ns.features.Healing
 -- Courtesy identity changes receive the next page. Druid's new default
 -- coverage is self/party only, so it does not silently add courtesy actions.
 if not F.druid and B.urgentBurst<2 then
  for i=7,8 do local guid=identity(units[i]);if guid~=B.identities[i]then B.identities[i]=guid;if guid~=""then B.urgentBurst=B.urgentBurst+1;return i,guid end end end
 end
 if F.druid then
  local selected=identity("target")
  if selected~=B.identities[7]then B.identities[7]=selected;if selected~=""then for i=1,6 do if identity(units[i])==selected then return i,selected end end end end
 end
 B.urgentBurst=0
 local maximum=F.druid and 6 or 8
 for unused=1,maximum do B.cursor=B.cursor%maximum+1;local guid=identity(units[B.cursor]);if guid~=""then return B.cursor,guid end end
end
function B.packet(now,tick)
 B.invalidateNativeCosts()
 local S=ns.state;local G=ns.features.GroupContext;local F=ns.features.Healing
 local definitions=specs();if #definitions==0 or S.readableCall(InCombatLockdown)~=false then return nil end
 B.initialize()
 B.pages=(B.pages or 0)+1
 local urgent=false
 if not F.druid then for i=7,8 do local guid=identity(units[i]);if guid~=""and guid~=B.identities[i]then urgent=true;break end end end
 local C=ns.features.BuffCoordination
 if not urgent and B.pages%4==0 and C and type(C.packet)=="function"then local peer=C.packet(now,tick);if peer then return peer end end
 local index,guid=choose();if not index then return nil end
 local unit=units[index];local values,at,coverage=B.scan(unit,guid,now)
 if not at or now<at or now-at>1 then return nil end
 local roster=S.transportPackets[16];if not roster then return nil end
 local rosterTick=0;for i=0,3 do rosterTick=rosterTick+roster.packet:byte(9+i)*256^i end
 local function providerIndex(guid)
  if not guid or guid==""then return 7 end
  for source=0,4 do local row=S.transportPackets[16+source];local wire=row and row.packet
   if wire and wire:sub(9,12)==roster.packet:sub(9,12)then local size=wire:byte(21);if size and size<=40 and wire:sub(22,21+size)==guid then return source end end
  end
  return 7
 end
 local level=G.read(UnitLevel,1,unit);level=level.status=="observed" and number(level.value,1,100) or 255
 if level~=math.floor(level)then level=255 end
 local packet="HHU1"..S.bytes(S.setupSession,4)..S.bytes(tick,4)..S.bytes(index-1,1)..S.bytes(rosterTick,4)..S.bytes(F.revision,4)..S.bytes(level,1)..S.bytes(math.floor((now-at)*1000),2)..S.bytes(G.code(F.cache[unit]and F.cache[unit].slotProtected),1)..S.bytes(#guid,1)..guid..S.bytes(#definitions,1)
 local costReadings={}
 for i,spec in ipairs(definitions)do
  local sample=F.spell(spec,unit);local delivery=F.delivery(spec);local id=delivery and delivery.id or 0
  costReadings[i]={id=id,learned=id>0 and sample.id==id and sample.learned.value==true}
  local flags=0
  for n,v in ipairs({sample.learned,sample.usable,sample.mana,sample.ready,sample.range})do flags=flags+G.code(v)*4^(n-1)end
  flags=flags+S.spellUseCode(spec.key)*1024
  local aura=coverage[spec.key]or {};local cover=G.code(aura.present)+G.code(aura.own)*4+G.code(aura.other)*16
  if aura.relationshipUnqualified then flags=flags+4096 end
  if aura.unqualifiedCamp then flags=flags+8192 end
  local provider=providerIndex(aura.providerGuid)
  if provider>=4 then flags=flags+16384 end
  cover=cover+provider%4*64
  -- A present-but-unidentified class effect cannot become confirmed absence.
  if aura.present and aura.present.value==true and not aura.auraID then cover=0 end
  if id==0 then flags=flags-flags%4 end -- no prepared rank is not learned proof
  local slot=F.druid and spec.deliverySlot or i==3 and 3 or i-1
  packet=packet..S.bytes(slot,1)..S.bytes(id,4)..S.bytes(flags,2)..S.bytes(aura.auraID or aura.relatedID or 0,4)..S.bytes(cover,1)..S.bytes(aura.remainingSeconds or 65535,2)
 end
 packet=packet..S.bytes(S.adler32(packet),4);assert(#packet<=113,"Optional buff page capacity")
 renderNativeCosts(packet,costReadings)
 return packet
end
