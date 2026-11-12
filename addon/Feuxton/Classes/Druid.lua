-- Druid observations. Shared app policies own decisions, forms and delivery.
local _,ns=...
local H={coreSlotCount=2,denseBridgeLayout={key="druid-slim-v1",height=309,nativeVitalsTop=214,nativeVitalsHeight=87,nativeSignalsTop=301,nativeSignalsHeight=58,gauges=148,units=148,unitHeight=20,activity=14,headerActivity=true,resources=148,setup=184,grid=184,roster=184,coreStamp=108,targetStamp=122,marker={1,.5,.25}}}
ns.classes.DRUID=H
H.specs=ns.spellCatalog.DRUID.specs
-- Class-owned native certificates, rank choices and form/queue handling.
local spellOverrides={["druid.wrath"]={["nativeAuraCandidates"]={48518},["auraName"]="Eclipse (Lunar)",["aura"]="player"},["druid.starfire"]={["nativeAuraCandidates"]={48517},["auraName"]="Eclipse (Solar)",["aura"]="player"},["druid.moonkinForm"]={["noToggle"]=true},["druid.bearForm"]={["noToggle"]=true},["druid.direBearForm"]={["noToggle"]=true},["druid.catForm"]={["noToggle"]=true},["druid.prowl"]={["noToggle"]=true,["aura"]="player"},["druid.faerieFireFeral"]={["auraName"]="Faerie Fire"},["druid.markOfTheWild"]={["aura"]="player"},["druid.thorns"]={["aura"]="player"},["druid.barkskin"]={["aura"]="player"},["druid.frenziedRegeneration"]={["aura"]="player"},["druid.enrage"]={["aura"]="player"},["druid.innervate"]={["aura"]="player"},["druid.naturesSwiftness"]={["aura"]="player"},["druid.healingTouchEfficient"]={["pinnedSpellID"]=5188}}
for _,spec in ipairs(H.specs) do for field,value in pairs(spellOverrides[spec.key] or {}) do spec[field]=value end end
H.healingSpecs={H.specs[2],H.specs[25],H.specs[26],H.specs[27],H.specs[28],H.specs[38]}
H.buffSpecs={H.specs[30],H.specs[31]}
H.buffAbilityKeys={};for i,spec in ipairs(H.buffSpecs)do H.buffAbilityKeys[i]=spec.key end
H.targetingSpecs={};for i,spec in ipairs(H.healingSpecs)do H.targetingSpecs[i]=spec end
for i,spec in ipairs(H.buffSpecs)do spec.deliverySlot=5+i;H.targetingSpecs[6+i]=spec end
H.auraSpecs={};for i,spec in ipairs(H.specs)do H.auraSpecs[i]=spec end
H.auraSpecs[39]={key="druid.clearcasting",name="Clearcasting",auraName="Clearcasting",aura="player",nativeAuraCandidates={16870}}
local function integer(S,value,low,high)
 return not S.isSecret(value) and type(value)=="number" and value==math.floor(value) and value>=low and value<=high and value or nil
end
function H.initializePreview()
 local S=ns.state;local G=ns.features.GroupContext;local R=ns.features.RangeTracking;local B=ns.features.SpellBridge
 if G.text(G.read(UnitClass,2,"player"),16)~="DRUID" then return end
 local bridge=B.create(S.hud,H.specs);H.bridge=bridge;S.druidNativePanel=bridge.panel;bridge.panel:SetHeight(190)
 for i,tile in ipairs(bridge.tiles) do tile.manaCost=B.createManaCost(bridge.panel,12+(i-1)%14*46+18,24+math.floor((i-1)/14)*32,16) end
 local function dot(x,y)local d=bridge.panel:CreateTexture(nil,"OVERLAY");d:SetSize(4,4);d:SetPoint("TOPLEFT",x,-y);R.initialize(d,1,.65,0,1);return d end
 local combatDot=dot(650,116);H.combatDot=combatDot
 local resources={};H.resources=resources
 local function resource(x,y)local widget=B.createManaCost(bridge.panel,x,y,128);R.initialize(widget.valid,1,.65,0,1);return widget end
 for i,power in ipairs({0,1,3})do resources[i]=resource(12+(i-1)*164,106);resources[i].powerType=power end
 local combo=resource(504,106);H.combo=combo
 local stacks=resource(504,112);H.stacks=stacks
 local clearcastingBackground=dot(508,70);clearcastingBackground:SetSize(8,8);R.paintColor(clearcastingBackground,0,.25,1,1)
 local attackerDots={};H.attackerDots=attackerDots
 for i=1,40 do attackerDots[i]={dot(12+(i-1)*6,144),dot(280+(i-1)*6,144)}end
 H.recipientDots={};H.recipientBridges={};H.recipientSpecs={}
 for index,unit in ipairs(G.tokens)do
  local x=12+(index-1)*104;local group={range={},geometry={dot(x+48,152),dot(x+54,152)}};H.recipientDots[index]=group
  for action=1,6 do group.range[action]=dot(x+(action-1)*6,152)end
  for _,offset in ipairs({36,42})do local background=dot(x+offset,152);R.paintColor(background,0,.25,1,1)end
  H.recipientBridges[unit]={panel=bridge.panel,verifiedAuras={},onlySpecifiedAuras=true}
  H.recipientSpecs[unit]={{key="druid.rejuvenation",name="Rejuvenation",aura=unit,auraFilter="HELPFUL|PLAYER",auraX=x+36,auraY=152,auraSize=4},{key="druid.regrowth",name="Regrowth",aura=unit,auraFilter="HELPFUL|PLAYER",auraX=x+42,auraY=152,auraSize=4}}
 end
 local function bool(d,value)local ok,painted=pcall(R.paintBoolean,d,value,{0,1,0,1},{1,0,0,1});if not ok or painted~=true then R.paintColor(d,1,.65,0,1)end end
 local function gauge(widget,current,maximum)
  local ok=pcall(function()
   if not S.isSecret(maximum)and(type(maximum)~="number"or maximum<=0 or maximum~=maximum or maximum==math.huge)then error("Resource maximum unavailable")end
   if not S.isSecret(current)and(type(current)~="number"or current<0 or current~=current or current==math.huge)then error("Resource value unavailable")end
   widget.bar:SetMinMaxValues(0,maximum);widget.bar:SetValue(current)
  end)
  bool(widget.valid,ok and true or nil)
 end
 function H.observeRecipient(index,unit,identity,spells)
  local F=ns.features.Healing;local x=12+(index-1)*104;local own=H.recipientBridges[unit]
  local specs=H.recipientSpecs[unit]
  local reads={spells["druid.rejuvenation"],spells["druid.regrowth"]}
  local eligible=identity~=""and G.read(UnitIsVisible,1,unit).value==true and G.read(UnitCanAssist,1,"player",unit).value==true
  if eligible then B.auras(own,specs,reads)end
  F.druidAuras=F.druidAuras or {};F.druidAuras[unit]={};F.druidAuraRevisions=F.druidAuraRevisions or {};F.druidAuraRevisions[unit]=own.auraRevision or 0
  for i,spec in ipairs(specs)do
   local settled=eligible and GetTime()>=(own.settledAt or math.huge);local aura=eligible and reads[i].aura or {}
   F.druidAuras[unit][spec.key]={present=aura,own=aura,nativeFlags=(settled and own.absence and own.absence[i]and 1 or 0)+(settled and own.configured and own.configured[i]and 2 or 0)}
  end
  local near15,near30
  if identity~=""then
   if unit=="player"then near15=true;near30=true
   else local distance,checked=G.readPair(UnitDistanceSquared,unit);if checked.value==true and distance.status=="observed"and type(distance.value)=="number"and distance.value>=0 then near15=distance.value<=225;near30=distance.value<=900 end end
  end
  bool(H.recipientDots[index].geometry[1],near15);bool(H.recipientDots[index].geometry[2],near30)
  F.druidGeometry=F.druidGeometry or {};F.druidGeometry[unit]=(near15==true and 2 or near15==false and 1 or 0)+(near30==true and 2 or near30==false and 1 or 0)*4
 end
 local errorEvents=CreateFrame("Frame",nil,bridge.panel);errorEvents:RegisterEvent("UI_ERROR_MESSAGE");errorEvents:RegisterEvent("PLAYER_TARGET_CHANGED")
 errorEvents:SetScript("OnEvent",function(_,event,id,text)
  if event=="PLAYER_TARGET_CHANGED"then H.behindAt=nil;return end
  local code=integer(S,id,0,2147483647);local label=G.text(G.scalar(text),200)
  local expected=S.readableCall(function()return LE_GAME_ERR_BADATTACKPOS end);local expectedText=S.readableCall(function()return SPELL_FAILED_NOT_BEHIND end)
  if(type(expected)=="number"and code==expected)or(type(expectedText)=="string"and label==expectedText)then H.behindSequence=((H.behindSequence or 0)+1)%4294967296;H.behindAt=GetTime();H.behindGeneration=S.auraGeneration end
 end)
 local tick,elapsed=0,0
 local function render()
  if not S.executionBytes then return end
  local F=ns.features.Healing;tick=(tick+1)%4294967296
  local level=integer(S,S.readableCall(UnitLevel,"player"),1,100);if not level then error("Level unavailable")end
  local readings={};for i,spec in ipairs(H.specs)do
   local r,rangeOK,rangeRaw,usableOK,usableRaw,manaRaw,rangeSource,usableSource=F.spell(spec,spec.unit or"target");readings[i]=r
   local known=r.learned.status=="observed"and r.learned.value
   B.render(bridge,i,r.id,known,spec,rangeOK,rangeRaw,usableOK,usableRaw,manaRaw,rangeSource,usableSource)
   B.renderPowerCost(bridge.tiles[i].manaCost,r.id,known==true,spec.powerType or 0)
  end
  local auraReads={};for i,spec in ipairs(H.specs)do auraReads[i]=readings[i]end
  auraReads[39]={id=16870,learned={status="observed",value=true}}
  B.auras(bridge,H.auraSpecs,auraReads)
  local combat=G.read(UnitAffectingCombat,1,"player");bool(combatDot,UnitAffectingCombat("player"))
  local form=G.read(GetShapeshiftForm,1);local caster,formID={},4294967295
  if form.status=="observed"and integer(S,form.value,0,32)then caster={status="observed",value=form.value==0};if form.value==0 then formID=0 else local id=S.specialActionSpell(form.value);if id then formID=id end end end
  local power=integer(S,S.readableCall(UnitPowerType,"player"),0,31)or 255
  for _,widget in ipairs(resources)do local ok=pcall(function()gauge(widget,UnitPower("player",widget.powerType),UnitPowerMax("player",widget.powerType))end);if not ok then bool(widget.valid,nil)end end
  local cpOK=pcall(function()gauge(combo,GetComboPoints("player","target"),32)end);if not cpOK then bool(combo.valid,nil)end
  local stackValue
  if type(C_UnitAuras)=="table"and type(C_UnitAuras.GetAuraDataBySpellName)=="function"then local ok,aura=pcall(C_UnitAuras.GetAuraDataBySpellName,"target","Lacerate","HARMFUL|PLAYER");if ok and not S.isSecret(aura)and type(aura)=="table"then local success,value=pcall(function()return aura.applications end);if success then stackValue=value end end end
  gauge(stacks,stackValue,32)
  local X=ns.features.ControlEffects;local probe,reach=X.nearbyProbe()
  for i,pair in ipairs(attackerDots)do local unit="nameplate"..i;local onPlayer,near;local exists=S.readableCall(UnitExists,unit)
   if exists==false then onPlayer=false;near=false
   elseif exists==true and S.readableCall(UnitIsDeadOrGhost,unit)==false and S.readableCall(UnitCanAttack,"player",unit)==true then
    local ok,value=pcall(UnitIsUnit,unit.."target","player");if ok then onPlayer=value end
    if probe>0 and reach>0 and reach<=8 then local ok,value=X.readMeleeRange(unit,probe);if ok then near=value end end
   end;bool(pair[1],onPlayer);bool(pair[2],near)
  end
  local packet="DRS2"..S.bytes(S.setupSession,4)..S.bytes(tick,4)..S.bytes(level,1)..S.bytes(S.updateRateMs,2)..S.bytes(S.auraGeneration,1)..S.bytes(#H.specs,1)..S.bytes(S.bindingsValid and 2 or 0,1)
  local settled=GetTime()>=(bridge.settledAt or math.huge)
  for i,spec in ipairs(H.specs)do
   local r=readings[i];local entry=S.managedSpells and S.managedSpells.delivery("DRUID",spec.managedName or spec.name);local key=S.bindingsValid and S.managedSpells.deliveryCurrent(entry)and S.compactBindingCode(entry.key)or 0
   local flags=0;for j,value in ipairs({r.learned,r.usable,r.mana,r.range,r.ready,r.aura or{}})do flags=flags+G.code(value)*4^(j-1)end
   local info=S.readableCall(S.spellAPI.GetSpellInfo,r.id);local ms=integer(S,S.safeField(info,"castTime"),0,10000)or 65535
   local usage=S.spellUseCode(spec.key)+(settled and bridge.absence and bridge.absence[i]and 4 or 0)+(settled and bridge.configured and bridge.configured[i]and 8 or 0)
   packet=packet..S.bytes(r.id,4)..S.bytes(key,2)..S.bytes(flags,2)..S.bytes(usage,1)..S.bytes(ms,2)
  end
  local stealth=G.read(IsStealthed,1);if stealth.status~="observed"then stealth=readings[11].aura or{}end
  local attacking=G.read(S.spellAPI.IsCurrentSpell or IsCurrentSpell,1,6603)
  local states=G.code(stealth)+G.code(readings[1].aura)*4+G.code(readings[3].aura)*16+G.code(auraReads[39].aura)*64+G.code(attacking)*256+(settled and bridge.configured and bridge.configured[39]and 1024 or 0)+(settled and bridge.absence and bridge.absence[39]and 2048 or 0)
  local targetLevel=integer(S,S.readableCall(UnitLevel,"target"),-1,100);targetLevel=targetLevel==-1 and 65534 or targetLevel or 65535
  local classification=G.text(G.read(UnitClassification,1,"target"),20);local types={normal=1,elite=2,rareelite=3,rare=4,worldboss=5,trivial=6,minus=7}
  local age=H.behindAt and H.behindGeneration==S.auraGeneration and math.min(65534,math.max(0,math.floor((GetTime()-H.behindAt)*1000)))or 65535
  local maul=G.read(S.spellAPI.IsCurrentSpell or IsCurrentSpell,1,readings[23].id)
  local function binding(name)local e=S.managedSpells and S.managedSpells.entries["DRUID:"..name];return S.bindingsValid and S.managedSpells.current(e)and S.compactBindingCode(e.key)or 0 end
  local activeID,activeKind=ns.features.CastTracking.activityIdentity()
  packet=packet..S.executionBytes(2)..S.bytes(G.code(combat),1)..S.bytes(G.code(caster),1)..S.bytes(formID,4)..S.bytes(power,1)..S.bytes(states,2)..S.bytes(targetLevel,2)..S.bytes(types[classification]or 0,1)..S.bytes(bridge.auraRevision or 0,4)..S.bytes(H.behindSequence or 0,4)..S.bytes(age,2)..S.bytes(G.code(maul),1)..S.bytes(binding("Feuxton Stop Casting"),2)..S.bytes(binding("Feuxton Cancel Form"),2)..S.bytes(activeID,4)..S.bytes(activeKind,1)
  local sum=S.adler32(packet);for i,d in ipairs(bridge.stamp)do local value=math.floor(sum/256^(i-1))%256/255;d:SetColorTexture(value,value,value,1)end
  S.publishTransportPacket(12,packet..S.bytes(sum,4))
 end
 bridge.panel:SetScript("OnUpdate",function(_,dt)elapsed=elapsed+dt;if elapsed<S.updateInterval()then return end;elapsed=0;local ok,err=pcall(render);H.lastError=not ok and S.describe(err)or nil;if not ok then S.publishTransportPacket(12,nil)end end)
 S.profileScript(bridge.panel,"OnUpdate","Druid bridge")
end
