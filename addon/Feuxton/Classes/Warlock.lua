-- Warlock leveling catalog and WLS6 class packet. No rotation or input here.
local _,ns=...
local H={denseBridgeLayout={key="warlock-slim-v1",gauges=78,units=78,unitHeight=20,activity=14,headerActivity=true,resources=78,setup=98,grid=98,roster=98,coreStamp=108,targetStamp=122,marker={.5,.25,1}}}
ns.classes.WARLOCK=H
H.specs=ns.spellCatalog.WARLOCK.specs
-- Class-owned native certificates, rank choices and form/queue handling.
local spellOverrides={["warlock.agony"]={["nativeAuraIDs"]={["70338"]={[6217]=6217}}},["warlock.corruption"]={["nativeAuraIDs"]={["70338"]={[6223]=6223}}},["warlock.shadowBolt"]={["auraName"]="Shadow Trance"},["warlock.searingPain"]={["nativeAuraCandidates"]={1293696},["auraName"]="Demonic Brand"},["warlock.mouseoverAgony"]={["nativeAuraIDs"]={["70338"]={[6217]=6217}}},["warlock.mouseoverCorruption"]={["nativeAuraIDs"]={["70338"]={[6223]=6223}}}}
for _,spec in ipairs(H.specs) do for field,value in pairs(spellOverrides[spec.key] or {}) do spec[field]=value end end
local function publicInteger(value,maximum)
 local S=ns.state
 if not S.isSecret(value) and type(value)=="number" and value>=0 and value<=maximum and value==math.floor(value) then return value end
end
local function shardTarget()
 local S=ns.state;local G=ns.features.GroupContext
 local slots=publicInteger(NUM_BAG_SLOTS,8)
 if not slots or slots==0 then return 0 end
 local container=type(C_Container)=="table" and C_Container or {}
 local capacity=0
 for bag=1,slots do
  local size=publicInteger(S.readableCall(container.GetContainerNumSlots or GetContainerNumSlots,bag),128)
  if not size then return 0 end
  if size>0 then
   local family=G.read(container.GetContainerNumFreeSlots or GetContainerNumFreeSlots,2,bag)
   local mask=family.status=="observed" and publicInteger(family.value,4294967295)
   if not mask then return 0 end
   -- This client uses bag-family bit 4 for dedicated Soul Shard bags.
   if math.floor(mask/4)%2==1 then capacity=capacity+size end
  end
 end
 return capacity>0 and capacity or 2
end
local function tooltipInteger(value)
 if value:match("^%d+$") then return publicInteger(tonumber(value),16777215) end
 local first,remaining=value:match("^(%d%d?%d?)(,.*)$")
 if not first then return nil end
 while remaining~="" do
  local group,tail=remaining:match("^,(%d%d%d)(.*)$")
  if not group then return nil end
  first=first..group;remaining=tail
 end
 return publicInteger(tonumber(first),16777215)
end
local function lifeTapRestore(id)
 local S=ns.state
 local locale=S.readableCall(GetLocale)
 if locale~="enUS" and locale~="enGB" then return nil end
 local text=S.readableCall(S.spellAPI.GetSpellDescription or GetSpellDescription,id)
 if type(text)~="string" or #text>256 then return nil end
 -- The active spell's text incorporates rank, Spirit and the talent. No
 -- catalog baseline or subtraction of restricted player stats is equivalent.
 local health,mana=text:match("^%s*Converts ([%d,]+) Health into ([%d,]+) Mana for you%. Spirit increases the amount converted%.%s*$")
 if not health or not mana then return nil end
 local cost,restore=tooltipInteger(health),tooltipInteger(mana)
 if cost and cost>0 and restore and restore>0 then return restore end
end
function H.initializePreview()
 local S=ns.state;local G=ns.features.GroupContext
 if G.text(G.read(UnitClass,2,"player"),16)~="WARLOCK" then return end
 local B=ns.features.SpellBridge;local bridge=B.create(S.hud,H.specs,true);H.bridge=bridge;S.warlockNativePanel=bridge.panel
 bridge.panel:SetHeight(72)
 -- The final tile row leaves two lanes for the pet control and combat witness.
 local petX,petY=B.tileOrigin(#H.specs+1)
 local petIcon=bridge.panel:CreateTexture(nil,"ARTWORK");petIcon:SetSize(16,16);petIcon:SetPoint("TOPLEFT",petX,-petY)
 petIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
 pcall(SetPortraitTexture,petIcon,"pet")
 local petUse=S.attachSpellUse(bridge.panel,petIcon,"warlock.petAttack")
 petUse.useDot:ClearAllPoints();petUse.useDot:SetPoint("TOPRIGHT",petIcon,"TOPRIGHT",0,0)
 local combatX,combatY=B.tileOrigin(#H.specs+2)
 local combatDot=bridge.panel:CreateTexture(nil,"OVERLAY");combatDot:SetSize(4,4);combatDot:SetPoint("TOPLEFT",combatX,-combatY)
 -- The two lower-right gauge rows are empty on Warlock. Keep all three
 -- restricted bars at full width and leave player, pet and target gauges alone.
 local hoverHealth=CreateFrame("StatusBar",nil,bridge.panel)
 hoverHealth:SetPoint("TOPLEFT",340,-64);hoverHealth:SetSize(128,4);hoverHealth:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8");hoverHealth:SetStatusBarColor(0,1,0,1)
 local hoverBackground=hoverHealth:CreateTexture(nil,"BACKGROUND");hoverBackground:SetAllPoints();hoverBackground:SetColorTexture(.18,.18,.18,1)
 local hoverHealthValid=bridge.panel:CreateTexture(nil,"OVERLAY");hoverHealthValid:SetSize(4,4);hoverHealthValid:SetPoint("TOPLEFT",472,-64)
 H.mouseoverHealth=hoverHealth;H.mouseoverHealthValid=hoverHealthValid
 local channelCosts={B.createManaCost(bridge.panel,504,64,128),B.createManaCost(bridge.panel,340,68,128)}
 H.channelCosts=channelCosts
 local function channelCostStatus(widget,valid,zero)
  if not valid then widget.valid:SetColorTexture(1,.65,0,1) else widget.valid:SetColorTexture(0,1,zero and 1 or 0,1) end
 end
 local function renderChannelCosts(id,learned)
  local upfront,perSecond,zeroUpfront,zeroPerSecond
  local ok=learned==true and pcall(function()
   local api=S.spellAPI.GetSpellPowerCost or GetSpellPowerCost
   if type(api)~="function" then error("Channel cost API unavailable") end
   local costs=api(id);if S.isSecret(costs) then error("Channel costs unavailable") end
   if costs==nil then error("Channel costs unavailable") end
   if type(costs)~="table" or #costs>8 then error("Channel costs unavailable") end
   upfront=0;perSecond=0;local found=false
   for _,entry in ipairs(costs) do
    if S.isSecret(entry) or type(entry)~="table" then error("Channel cost entry unavailable") end
    local kind=S.safeField(entry,"type")
    if type(kind)~="number" or kind<0 or kind>255 or kind~=math.floor(kind) then error("Channel cost type unavailable") end
    if kind==0 then
     if found then error("Multiple channel mana costs") end;found=true
     upfront=entry.cost;perSecond=entry.costPerSec
     local alternate=entry.costPerSecond
     if not S.isSecret(perSecond) and perSecond==nil then perSecond=alternate
     elseif S.isSecret(alternate) or alternate~=nil and (S.isSecret(perSecond) or alternate~=perSecond) then error("Ambiguous channel cost") end
     if not S.isSecret(perSecond) and perSecond==nil then perSecond=0 end
     local function validAmount(amount) return S.isSecret(amount) or type(amount)=="number" and amount>=0 and amount==amount and amount~=math.huge end
     if not validAmount(upfront) or not validAmount(perSecond) then error("Channel amount unavailable") end
     local minimum=entry.minCost
     if S.isSecret(minimum) or minimum~=nil and (type(minimum)~="number" or minimum<0 or minimum~=minimum or minimum>0 and (S.isSecret(upfront) or minimum>upfront)) then error("Variable channel minimum") end
    end
   end
   local maximum=UnitPowerMax("player",0)
   if not S.isSecret(maximum) and (type(maximum)~="number" or maximum<=0 or maximum~=maximum or maximum==math.huge) then error("Mana maximum unavailable") end
   channelCosts[1].bar:SetMinMaxValues(0,maximum);channelCosts[1].bar:SetValue(upfront)
   channelCosts[2].bar:SetMinMaxValues(0,maximum);channelCosts[2].bar:SetValue(perSecond)
   zeroUpfront=not S.isSecret(upfront) and upfront==0;zeroPerSecond=not S.isSecret(perSecond) and perSecond==0
  end)
  channelCostStatus(channelCosts[1],ok,zeroUpfront);channelCostStatus(channelCosts[2],ok,zeroPerSecond)
 end
 local function count(id)
  local api=type(C_Item)=="table" and C_Item.GetItemCount or GetItemCount
  local value=G.read(api,1,id,false,false)
  return value.status=="observed" and type(value.value)=="number" and value.value>=0 and value.value<65535 and value.value==math.floor(value.value) and value.value or 65535
 end
 H.mouseoverGeneration=0
 local mouseEvents=CreateFrame("Frame",nil,bridge.panel)
 mouseEvents:RegisterEvent("UPDATE_MOUSEOVER_UNIT");mouseEvents:RegisterEvent("PLAYER_ENTERING_WORLD");mouseEvents:RegisterEvent("UNIT_PET")
 mouseEvents:SetScript("OnEvent",function(_,event)
  if event=="UNIT_PET" then pcall(SetPortraitTexture,petIcon,"pet") else H.mouseoverGeneration=(H.mouseoverGeneration+1)%4294967296 end
 end)
 local lastIdentity=""
 local armorExpiry,armorSeen
 local function observeArmor(unit,name,aura,id)
  if unit~="player" or name~="Demon Armor" then return end
  if armorSeen then armorExpiry=0;return end
  armorSeen=true
  local spellID=id.status=="observed" and publicInteger(id.value,2147483647)
  if not spellID or spellID==0 then return end
  local expiration=S.safeField(aura,"expirationTime")
  if type(expiration)~="number" or expiration~=expiration or expiration<0 or expiration==math.huge then return end
  if expiration==0 then
   if S.safeField(aura,"duration")==0 then armorExpiry=1 end
   return
  end
  local now=S.readableCall(GetTime)
  if type(now)=="number" and now>=0 and expiration>=now then armorExpiry=expiration-now<300 and 2 or 1 end
 end
 local function mouseover()
  local identity=G.text(G.read(UnitGUID,1,"mouseover"),40)
  if identity~=lastIdentity then lastIdentity=identity;H.mouseoverGeneration=(H.mouseoverGeneration+1)%4294967296 end
  local flags=0
  for index,observation in ipairs({G.read(UnitExists,1,"mouseover"),G.read(UnitIsDeadOrGhost,1,"mouseover"),G.read(UnitCanAttack,1,"player","mouseover"),G.read(UnitIsUnit,1,"mouseover","player"),G.read(UnitIsVisible,1,"mouseover"),G.read(UnitIsUnit,1,"mouseover","target")}) do flags=flags+G.code(observation)*4^(index-1) end
  local onPlayer=G.read(UnitExists,1,"mouseovertarget").value==true and G.read(UnitIsUnit,1,"mouseovertarget","player") or {}
  flags=flags+G.code(onPlayer)*4096
  return {identity=identity,generation=H.mouseoverGeneration,flags=flags}
 end
 local tick,elapsed=0,0
 local function render()
  if not S.executionBytes then return end
  local F=ns.features.Healing;tick=(tick+1)%4294967296
  local level=S.readableCall(UnitLevel,"player");if type(level)~="number" or level<1 or level>100 then error("Level unavailable") end
  local hover=mouseover();local readings={}
  local combat=G.read(UnitAffectingCombat,1,"player")
  local outOfCombat=combat.status=="observed" and combat.value==false
  for i,spec in ipairs(H.specs) do
   local r,rangeOK,rangeRaw,usableOK,usableRaw,manaRaw,rangeSource,usableSource
   if spec.petAbility then r=ns.features.PetSupport.readSacrifice()
   else r,rangeOK,rangeRaw,usableOK,usableRaw,manaRaw,rangeSource,usableSource=F.spell(spec,spec.unit or "target") end
   readings[i]=r
   if spec.petAbility then ns.features.PetSupport.renderSacrifice(bridge.tiles[i],r)
   else B.render(bridge,i,r.id,r.learned.status=="observed" and r.learned.value or nil,spec,rangeOK,rangeRaw,usableOK,usableRaw,manaRaw,rangeSource,usableSource);B.renderManaCost(bridge.tiles[i].manaCost,r.id,r.learned.status=="observed" and r.learned.value==true) end
  end
  -- The shield outlives the sacrificed demon. Retain only its verified aura
  -- lookup ID; current pet learned state, action and binding remain untouched.
  if H.sacrificeAuraSession~=S.setupSession then H.sacrificeAuraSession=S.setupSession;H.sacrificeAuraID=nil end
  local sacrificeReading=readings[34]
  if sacrificeReading.learned.value==true then H.sacrificeAuraID=sacrificeReading.id end
  local auraReadings=readings
  if H.sacrificeAuraID then
   auraReadings={};for i,r in ipairs(readings)do auraReadings[i]=r end
   auraReadings[34]={id=H.sacrificeAuraID,learned={status="observed",value=true}}
  end
  armorExpiry,armorSeen=0,false
  B.auras(bridge,H.specs,auraReadings,outOfCombat and observeArmor or nil)
  if auraReadings~=readings then sacrificeReading.aura=auraReadings[34].aura end
  local auraSettled=GetTime()>=(bridge.settledAt or math.huge)
  local healthOK=false
  if hover.identity~="" and hover.flags%4==2 then
   healthOK=pcall(function()
    local maximum=UnitHealthMax("mouseover")
    if not S.isSecret(maximum) and (type(maximum)~="number" or maximum<=0 or maximum~=maximum) then error("Mouseover maximum unavailable") end
    hoverHealth:SetMinMaxValues(0,maximum);hoverHealth:SetValue(UnitHealth("mouseover"))
   end)
  end
  if healthOK then hoverHealthValid:SetColorTexture(0,1,0,1) else hoverHealth:SetMinMaxValues(0,1);hoverHealth:SetValue(0);hoverHealthValid:SetColorTexture(1,.65,0,1) end
  local hellfire=readings[33];renderChannelCosts(hellfire.id,hellfire.learned.status=="observed" and hellfire.learned.value==true)
  local packet=ns.wire.schemas.warlockPreview..S.bytes(S.setupSession,4)..S.bytes(tick,4)..S.bytes(level,1)..S.bytes(S.updateRateMs,2)..S.bytes(S.auraGeneration,1)..S.bytes(#H.specs,1)..S.bytes(S.bindingsValid and 2 or 0,1)
  local tapRestore,tapID=0,0
  for i,spec in ipairs(H.specs) do
   local r=readings[i];local M=S.managedSpells;local family=spec.managedName or spec.name
   local entry=M and M.entries["WARLOCK:"..family]
   if M and not spec.petAbility then entry=M.delivery("WARLOCK",family)end
   local compatible=not spec.petAbility or entry and entry.id==r.id and entry.petActionSlot==r.petActionSlot and entry.petIdentity==r.petIdentity
   local current=M and(spec.petAbility and M.current(entry)or not spec.petAbility and M.deliveryCurrent(entry))
   local key=S.bindingsValid and compatible and current and S.compactBindingCode(entry.key) or 0
   if spec.key=="warlock.lifeTap" and outOfCombat and key>0 and r.learned.value==true and entry.id==r.id and r.id>0 and r.id<=16777215 then
    local amount=lifeTapRestore(r.id)
    if amount then tapRestore,tapID=amount,r.id end
   end
   local ready=r.ready
   local flags=0;for j,value in ipairs({r.learned,r.usable,r.mana,r.range,ready,r.aura or {}}) do flags=flags+G.code(value)*4^(j-1) end
   local info=S.readableCall(S.spellAPI.GetSpellInfo,r.id);local ms=spec.petAbility and r.castMs or S.safeField(info,"castTime");if type(ms)~="number" or ms<0 or ms>10000 then ms=65535 end
   local absent=bridge.absence and bridge.absence[i] and auraSettled
   local configured=bridge.configured and bridge.configured[i] and auraSettled
   packet=packet..S.bytes(r.id,4)..S.bytes(key,2)..S.bytes(flags,2)..S.bytes(S.spellUseCode(spec.usageKey or spec.key)+(absent and 4 or 0)+(configured and 8 or 0),1)..S.bytes(ms,2)
  end
  combatDot:SetColorTexture(1,1,1,1)
  local painted,result=pcall(ns.features.RangeTracking.paintBoolean,combatDot,UnitAffectingCombat("player"),{0,1,0,1},{.2,.2,.2,1})
  if not painted or result~=true then combatDot:SetVertexColor(1,1,1,1);combatDot:SetColorTexture(1,.65,0,1) end
  -- Start/stop events describe the whole auto-repeat session. A current-spell
  -- query can be false between wand shots, so use it only before a known event.
  local wand=S.autoStateSource=="autorepeat event" and type(S.autoActive)=="boolean"
    and {status="observed",value=S.autoActive} or G.read(S.spellAPI.IsCurrentSpell or IsCurrentSpell,1,5019)
  local stones=0
  for _,id in ipairs(ns.features.Consumables.ids) do local n=count(id);if n==65535 then stones=65535;break end;stones=math.min(65534,stones+n) end
  packet=packet..S.executionBytes(2)..S.bytes(G.code(combat),1)..S.bytes(count(6265),2)..S.bytes(G.code(wand),1)..S.bytes(stones,2)
  if hover.generation~=H.mouseoverGeneration or hover.identity~=G.text(G.read(UnitGUID,1,"mouseover"),40) then error("Mouseover identity changed during Warlock update") end
  packet=packet..S.bytes(hover.flags,2)..S.bytes(hover.generation,4)..S.bytes(#hover.identity,1)..hover.identity
  packet=packet..S.bytes(bridge.auraRevision or 0,4)
  packet=packet..(ns.features.PetSupport.bytes and ns.features.PetSupport.bytes() or S.bytes(0,3))
  local stop=S.managedSpells and S.managedSpells.entries["WARLOCK:Feuxton Stop Casting"]
  packet=packet..S.bytes(S.bindingsValid and S.managedSpells.current(stop) and S.compactBindingCode(stop.key) or 0,2)
  local activeID,activeKind=ns.features.CastTracking.activityIdentity()
  packet=packet..S.bytes(activeID,4)..S.bytes(activeKind,1)
  local sacrifice=readings[34];local petIdentity=sacrifice.petIdentity or ""
  local petAction=ns.features.PetSupport.sacrificeAction()
  if sacrifice.petIdentity~=ns.features.PetSupport.identity() or sacrifice.petActionSlot>0 and (not petAction or petAction.id~=sacrifice.id or petAction.slot~=sacrifice.petActionSlot) then error("Pet action changed during Warlock update") end
  packet=packet..S.bytes(sacrifice.petActionSlot,1)..S.bytes(#petIdentity,1)..petIdentity
  packet=packet..S.bytes(armorExpiry,1)..S.bytes(shardTarget(),2)..S.bytes(tapRestore,3)..S.bytes(tapID,3)
  local sum=S.adler32(packet);for i,dot in ipairs(bridge.stamp) do local v=math.floor(sum/256^(i-1))%256/255;dot:SetColorTexture(v,v,v,1) end
  S.publishTransportPacket(ns.wire.ids.warlockPreview,packet..S.bytes(sum,4))
 end
 bridge.panel:SetScript("OnUpdate",function(self,dt) elapsed=elapsed+dt;if elapsed<S.updateInterval() then return end;elapsed=0;local ok,err=pcall(render);H.lastError=not ok and S.describe(err) or nil;if not ok then S.publishTransportPacket(ns.wire.ids.warlockPreview,nil) end end)
 S.profileScript(bridge.panel,"OnUpdate","Warlock bridge")
end
