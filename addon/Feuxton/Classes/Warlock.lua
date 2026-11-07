-- Warlock leveling catalog and WLS5 class packet. No rotation or input here.
local _,ns=...
local H={denseBridgeLayout={key="warlock-dense-v5",height=377,nativeVitalsTop=232,nativeVitalsHeight=87,nativeSignalsTop=319,nativeSignalsHeight=58,gauges=168,units=168,unitHeight=28,activity=14,headerActivity=true,resources=168,setup=196,grid=196,roster=196,coreStamp=108,targetStamp=122,marker={.5,.25,1}}}
ns.classes.WARLOCK=H
H.specs={
 -- Native green slots in the retained October 12 build-70338 game frames
 -- verified these exact cast/effect IDs. Other ranks/builds are not inferred.
 {key="warlock.agony",name="Bane of Agony",petAttack=true,aura="target",nativeAuraIDs={["70338"]={[6217]=6217}}},
 {key="warlock.corruption",name="Corruption",petAttack=true,aura="target",nativeAuraIDs={["70338"]={[6223]=6223}}},
 {key="warlock.immolate",name="Immolate",petAttack=true,aura="target"},
 {key="warlock.shadowBolt",name="Shadow Bolt",petAttack=true,aura="player",auraName="Shadow Trance"},
 {key="warlock.searingPain",name="Searing Pain",petAttack=true,aura="target",auraName="Demonic Brand",nativeAuraCandidates={1293696}},
 {key="warlock.drainLife",name="Drain Life",petAttack=true},
 {key="warlock.drainSoul",name="Drain Soul",petAttack=true},
 {key="warlock.lifeTap",name="Life Tap",unit="player"},
 {key="warlock.demonArmor",name="Demon Armor",unit="player",aura="player"},
 {key="warlock.demonSkin",name="Demon Skin",unit="player",aura="player"},
 {key="warlock.soulLink",name="Soul Link",unit="player",aura="player"},
 {key="warlock.amplifyCurse",name="Amplify Curse",unit="player",aura="player"},
 {key="warlock.summonImp",name="Summon Imp",unit="player"},
 {key="warlock.summonVoidwalker",name="Summon Voidwalker",unit="player"},
 {key="warlock.summonSuccubus",name="Summon Succubus",unit="player"},
 {key="warlock.summonIncubus",name="Summon Incubus",unit="player"},
 {key="warlock.summonFelhunter",name="Summon Felhunter",unit="player"},
 {key="warlock.healthFunnel",name="Health Funnel",unit="pet"},
 {key="warlock.shoot",name="Shoot",petAttack=true},
 {key="warlock.createHealthstone",name="Create Healthstone",unit="player"},
 {key="warlock.siphonLife",name="Siphon Life",petAttack=true,aura="target"},
 {key="warlock.elements",name="Curse of the Elements",petAttack=true,aura="target"},
 -- Explicit alternate-unit keys never redirect an ordinary target spell.
 {key="warlock.mouseoverAgony",name="Bane of Agony",managedName="Feuxton Mouseover Bane of Agony",unit="mouseover",aura="mouseover",usageKey="warlock.agony",nativeAuraIDs={["70338"]={[6217]=6217}}},
 {key="warlock.mouseoverCorruption",name="Corruption",managedName="Feuxton Mouseover Corruption",unit="mouseover",aura="mouseover",usageKey="warlock.corruption",nativeAuraIDs={["70338"]={[6223]=6223}}},
 {key="warlock.mouseoverImmolate",name="Immolate",managedName="Feuxton Mouseover Immolate",unit="mouseover",aura="mouseover",usageKey="warlock.immolate"},
 {key="warlock.mouseoverSiphonLife",name="Siphon Life",managedName="Feuxton Mouseover Siphon Life",unit="mouseover",aura="mouseover",usageKey="warlock.siphonLife"},
 {key="warlock.mouseoverElements",name="Curse of the Elements",managedName="Feuxton Mouseover Curse of the Elements",unit="mouseover",aura="mouseover",usageKey="warlock.elements"},
 {key="warlock.conflagrate",name="Conflagrate",petAttack=true},
 {key="warlock.shadowburn",name="Shadowburn",petAttack=true},
 {key="warlock.incinerate",name="Incinerate",petAttack=true},
 {key="warlock.havoc",name="Bane of Havoc",petAttack=true,aura="target"},
 {key="warlock.mouseoverHavoc",name="Bane of Havoc",managedName="Feuxton Mouseover Bane of Havoc",unit="mouseover",aura="mouseover",usageKey="warlock.havoc"},
 {key="warlock.hellfire",name="Hellfire",unit="player"},
 {key="warlock.sacrifice",name="Sacrifice",unit="player",petAbility=true,offGlobalCooldown=true,aura="player"}
}
function H.initializePreview()
 local S=ns.state;local G=ns.features.GroupContext
 if G.text(G.read(UnitClass,2,"player"),16)~="WARLOCK" then return end
 local B=ns.features.SpellBridge;local bridge=B.create(S.hud,H.specs);H.bridge=bridge;S.warlockNativePanel=bridge.panel
 -- Costs and the possibly restricted maximum go directly to native bars.
 -- IsSpellUsable can remain true when the client rejects a low-mana cast.
 for i,tile in ipairs(bridge.tiles) do
  local x,y=12+(i-1)%14*46,6+math.floor((i-1)/14)*40
  tile.manaCost=B.createManaCost(bridge.panel,x+18,y+18,16)
  tile.cost=tile.manaCost.bar;tile.costValid=tile.manaCost.valid
 end
 local petIcon=bridge.panel:CreateTexture(nil,"ARTWORK");petIcon:SetSize(16,16);petIcon:SetPoint("TOPLEFT",610,-86)
 petIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
 pcall(SetPortraitTexture,petIcon,"pet");S.attachSpellUse(bridge.panel,petIcon,"warlock.petAttack")
 local combatDot=bridge.panel:CreateTexture(nil,"OVERLAY");combatDot:SetSize(4,4);combatDot:SetPoint("TOPLEFT",220,-122)
 local hoverHealth=CreateFrame("StatusBar",nil,bridge.panel)
 hoverHealth:SetPoint("TOPLEFT",300,-98);hoverHealth:SetSize(128,4);hoverHealth:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8");hoverHealth:SetStatusBarColor(0,1,0,1)
 local hoverBackground=hoverHealth:CreateTexture(nil,"BACKGROUND");hoverBackground:SetAllPoints();hoverBackground:SetColorTexture(.18,.18,.18,1)
 local hoverHealthValid=bridge.panel:CreateTexture(nil,"OVERLAY");hoverHealthValid:SetSize(4,4);hoverHealthValid:SetPoint("TOPLEFT",432,-98)
 H.mouseoverHealth=hoverHealth;H.mouseoverHealthValid=hoverHealthValid
 local channelCosts={B.createManaCost(bridge.panel,300,106,128),B.createManaCost(bridge.panel,300,114,128)}
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
  local F=ns.features.Healing;F.spellStatus={};tick=(tick+1)%4294967296
  local level=S.readableCall(UnitLevel,"player");if type(level)~="number" or level<1 or level>100 then error("Level unavailable") end
  local hover=mouseover();local readings={}
  for i,spec in ipairs(H.specs) do
   local r=spec.petAbility and ns.features.PetSupport.readSacrifice() or F.spell(spec,spec.unit or "target");readings[i]=r
   if spec.petAbility then ns.features.PetSupport.renderSacrifice(bridge.tiles[i],r)
   else B.render(bridge,i,r.id,r.learned.status=="observed" and r.learned.value or nil,spec);B.renderManaCost(bridge.tiles[i].manaCost,r.id,r.learned.status=="observed" and r.learned.value==true) end
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
  B.auras(bridge,H.specs,auraReadings)
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
  local packet="WLS5"..S.bytes(S.setupSession,4)..S.bytes(tick,4)..S.bytes(level,1)..S.bytes(S.updateRateMs,2)..S.bytes(S.auraGeneration,1)..S.bytes(#H.specs,1)..S.bytes(S.bindingsValid and 2 or 0,1)
  for i,spec in ipairs(H.specs) do
   local r=readings[i];local entry=S.managedSpells and S.managedSpells.entries["WARLOCK:"..(spec.managedName or spec.name)]
   local compatible=not spec.petAbility or entry and entry.id==r.id and entry.petActionSlot==r.petActionSlot and entry.petIdentity==r.petIdentity
   local key=S.bindingsValid and compatible and S.managedSpells.current(entry) and S.compactBindingCode(entry.key) or 0
   local ready=r.ready
   local flags=0;for j,value in ipairs({r.learned,r.usable,r.mana,r.range,ready,r.aura or {}}) do flags=flags+G.code(value)*4^(j-1) end
   local info=S.readableCall(S.spellAPI.GetSpellInfo,r.id);local ms=spec.petAbility and r.castMs or S.safeField(info,"castTime");if type(ms)~="number" or ms<0 or ms>10000 then ms=65535 end
   local absent=bridge.absence and bridge.absence[i] and auraSettled
   local configured=bridge.configured and bridge.configured[i] and auraSettled
   packet=packet..S.bytes(r.id,4)..S.bytes(key,2)..S.bytes(flags,2)..S.bytes(S.spellUseCode(spec.usageKey or spec.key)+(absent and 4 or 0)+(configured and 8 or 0),1)..S.bytes(ms,2)
  end
  local combat=G.read(UnitAffectingCombat,1,"player")
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
  local sum=S.adler32(packet);for i,dot in ipairs(bridge.stamp) do local v=math.floor(sum/256^(i-1))%256/255;dot:SetColorTexture(v,v,v,1) end
  S.publishTransportPacket(11,packet..S.bytes(sum,4))
 end
 bridge.panel:SetScript("OnUpdate",function(self,dt) elapsed=elapsed+dt;if elapsed<S.updateInterval() then return end;elapsed=0;local ok,err=pcall(render);H.lastError=not ok and S.describe(err) or nil;if not ok then S.publishTransportPacket(11,nil) end end)
 S.profileScript(bridge.panel,"OnUpdate","Warlock bridge")
end
