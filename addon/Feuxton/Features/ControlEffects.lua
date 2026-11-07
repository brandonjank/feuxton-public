-- HHX5: shared control, friendly target/mouseover and independent Freedom receipt.
-- All secret fields remain unknown; native cooldown/usability stays rendered.
local _,ns=...
local X={cache={}}
ns.features.ControlEffects=X
X.freedom={key="paladin.freedom",name="Blessing of Freedom",support=true,offGlobalCooldown=true}
X.units={"player","party1","party2","party3","party4","target","mouseover"}
-- Stable capability indexes shared with windows/Cleansing.cs. Add learned
-- class removers here without giving unsupported classes an assumed spell.
X.cleanseSpecs={{index=1,class="PALADIN",key="paladin.purify",name="Purify",unit="player"}}
-- Verified Forever aura mechanics, independent of the player's learned rank.
-- Do not infer a mechanic from an icon, tooltip wording or a shared spell name.
-- Sources/rank limits: docs/control-aura-catalog-0.263.md.
X.controlAuraGroups={
 {kind="root",name="Entangling Roots",ids={339,1062,5195,9853}},
 {kind="root",name="Frost Nova",ids={122,865,10230}},
 {kind="root",name="Net",ids={6533}},
 {kind="snare",name="Frostbolt",ids={116,205,837,7322,8406,8407,10179,10180,10181}},
 {kind="snare",name="Hamstring",ids={1715,7372,7373}},
 {kind="snare",name="Wing Clip",ids={2974,14268}},
 {kind="snare",name="Concussive Shot",ids={5116}},
 {kind="snare",name="Frost Shock",ids={8056,8058,10472,10473}},
 {kind="snare",name="Crippling Poison",ids={3409}},
 {kind="snare",name="Frost Trap",ids={13810}},
 {kind="snare",name="Earthbind",ids={3600}},
 {kind="snare",name="Curse of Exhaustion",ids={18223}},
 {kind="stun",name="Hammer of Justice",ids={853,5589,10308}},
 {kind="stun",name="Bash",ids={5211,8983}},
 {kind="stun",name="Cheap Shot",ids={1833}},
 {kind="stun",name="Kidney Shot",ids={408,8643}},
 {kind="stun",name="War Stomp",ids={20549}},
 {kind="stun",name="Concussion Blow",ids={12809}},
 {kind="stun",name="Pounce",ids={9005,9823,9827}},
 {kind="stun",name="Psychic Scream (stun variant)",ids={15398}},
 {kind="fear",name="Fear",ids={5782,6213,6215}},
 {kind="fear",name="Psychic Scream",ids={8122,8124,10888,10890,437928}},
 {kind="fear",name="Howl of Terror",ids={5484,17928}},
 {kind="fear",name="Intimidating Shout",ids={5246}},
 {kind="fear",name="Panic",ids={19408}},
 {kind="charm",name="Seduction",ids={6358}},
 {kind="charm",name="Mind Control",ids={605,10911,10912}},
 {kind="sleep",name="Sleep",ids={700,8399}},
 {kind="sleep",name="Hibernate",ids={2637,18657,18658}},
}
local controlByID={}
for _,group in ipairs(X.controlAuraGroups) do for _,id in ipairs(group.ids) do controlByID[id]=group.kind end end
-- These specific records use other control mechanics. Their effect type or
-- movement-speed text alone must not activate Freedom or Will of the Forsaken.
X.controlAuraExclusions={[6789]="horror",[2094]="disorient",[1776]="incapacitate",[6770]="sap",[20066]="incapacitate",[118]="polymorph",[1604]="daze"}
local function controlKind(id)
 if type(id)=="number" and id>0 and id<=2147483647 and id==math.floor(id) then
  return controlByID[id],X.controlAuraExclusions[id]~=nil
 end
end
local function applyControl(result,kind)
 if kind=="root" or kind=="snare" then result.movement=true
 elseif kind=="stun" then result.stun=true
 elseif kind=="charm" or kind=="fear" or kind=="sleep" then result.forsaken=true end
end
local movementNames={['Frostbolt']=true,['Frost Shock']=true,['Hamstring']=true,['Wing Clip']=true,['Concussive Shot']=true,['Crippling Poison']=true,['Entangling Roots']=true,['Frost Nova']=true,['Frost Trap Aura']=true,['Ensnare']=true,['Net']=true,['Web']=true,['Tendon Rip']=true}
-- Exact known stun names supplement clients whose unit LoC API omits allies.
-- Unknown names and secret aura fields never acquire a guessed mechanic.
local stunNames={['Hammer of Justice']=true,['Bash']=true,['War Stomp']=true,['Intimidation']=true,['Cheap Shot']=true,['Kidney Shot']=true,['Concussion Blow']=true,['Pounce']=true}
local function flag(v)return v==true and 2 or v==false and 1 or 0 end
local function value(fn,...)return ns.state.readableCall(fn,...) end
local function learned(spell)
 local observation=spell and spell.learned
 if type(observation)=="table" and observation.status=="observed" and not ns.state.isSecret(observation.value) and type(observation.value)=="boolean" then return observation.value end
 return nil
end
local debuffTypes={Poison=1,Disease=2,Curse=4,Magic=8,Bleed=16}
-- A lower bound from available nameplate units, never a complete world count.
-- Public eligibility is required before a secret range value can be rendered.
function X.nearbyProbe()
 local S=ns.state;local now=value(GetTime)
 if X.probeCache and type(now)=="number" and now-X.probeAt>=0 and now-X.probeAt<1 then return unpack(X.probeCache) end
 local class=value(function()local _,c=UnitClass("player");return c end)
 local names={PALADIN={"Holy Strike"},HUNTER={"Raptor Strike"},SHAMAN={"Primal Strike","Stormstrike"},WARRIOR={"Rend"},ROGUE={"Sinister Strike"},DRUID={"Claw"}}
 local id,reach=0,0
 for _,name in ipairs(names[class] or {}) do
  local info=value(S.spellAPI.GetSpellInfo,name);local spell=S.safeField(info,"spellID");local maximum=S.safeField(info,"maxRange");local minimum=S.safeField(info,"minRange")
  -- Combat-range melee spells may report zero numeric range. This catalog
  -- definition supplies reach, never a unit's in-range observation.
  -- Forever Holy Strike: https://www.wowhead.com/forever/spell=1866/holy-strike
  if class=="PALADIN" and name=="Holy Strike" and maximum==0 and minimum==0 then maximum=5 end
  if type(spell)=="number" and spell>0 and value(S.bookAPI.IsSpellKnown or IsSpellKnown,spell)==true and type(maximum)=="number" and maximum>0 and maximum<=8 and minimum==0 then id=spell;reach=math.ceil(maximum);break end
 end
 -- Every class can expose the learned melee Attack check. The native API must
 -- still return an actual range result; nil/secret failures are never a hit.
 if id==0 and value(S.bookAPI.IsSpellKnown or IsSpellKnown,6603)==true then id=6603;reach=5 end
 if type(now)=="number" then X.probeCache={id,reach};X.probeAt=now end
 return id,reach
end
function X.engaged(unit)
 local threat=value(UnitThreatSituation,"player",unit)
 if type(threat)=="number" and threat>=0 and threat<=3 then return true end
 for _,friend in ipairs({"player","pet","party1","party2","party3","party4"}) do if value(UnitIsUnit,unit.."target",friend)==true then return true end end
 return nil -- another fight or unavailable threat/target data is not our pack
end
local function hasRangeResult(ok,result)
 return ok and (ns.state.isSecret(result) or type(result)=="boolean")
end
local function attackAction(slot)
 if type(slot)~="number" or slot<1 or slot>240 or slot~=math.floor(slot) or type(GetActionInfo)~="function" then return false end
 local ok,kind,id=pcall(GetActionInfo,slot);local S=ns.state
 return ok and not S.isSecret(kind) and not S.isSecret(id) and kind=="spell" and id==6603
end
local function attackSlots()
 local S=ns.state;local now=value(GetTime)
 if X.attackSlotCache and type(now)=="number" and now-X.attackSlotAt>=0 and now-X.attackSlotAt<1 then return X.attackSlotCache end
 local result={actions={}};local book=type(C_SpellBook)=="table" and C_SpellBook or {}
 if type(book.FindSpellBookSlotForSpell)=="function" then
  local ok,slot,bank=pcall(book.FindSpellBookSlotForSpell,6603,false,false,false,false)
  if ok and not S.isSecret(slot) and not S.isSecret(bank) and type(slot)=="number" and slot>=1 and slot<=4096 and slot==math.floor(slot)
   and type(bank)=="number" and bank>=0 and bank<=2 and bank==math.floor(bank) then result.bookSlot=slot;result.bookBank=bank end
 end
 local action=type(C_ActionBar)=="table" and C_ActionBar or {}
 local slots=type(action.FindSpellActionButtons)=="function" and S.readableCall(action.FindSpellActionButtons,6603) or nil
 if type(slots)=="table" and not S.isSecret(slots) and #slots<=32 then
  for _,slot in ipairs(slots) do if not S.isSecret(slot) and attackAction(slot) then result.actions[#result.actions+1]=slot end end
 end
 if type(now)=="number" then X.attackSlotCache=result;X.attackSlotAt=now end
 return result
end
-- C_SwingTimer is explicitly current-target-only. Spellbook/action checks
-- accept a unit token and are the only Attack fallbacks used for nameplates.
-- These are independent range APIs; an invalid/nil result is not false.
function X.readMeleeRange(unit,id)
 local S=ns.state;local R=ns.features.RangeTracking
 if id==6603 then
  local swing=type(C_SwingTimer)=="table" and C_SwingTimer or {}
  if unit=="target" and type(swing.IsTargetWithinSwingRange)=="function" then
   if not X.swingRangeEnabled and type(swing.EnableRangeCheck)=="function" then X.swingRangeEnabled=pcall(swing.EnableRangeCheck,0,true) end
   local ok,result=pcall(swing.IsTargetWithinSwingRange,0)
   if hasRangeResult(ok,result) then return true,result,"swing" end
  end
  local slots=attackSlots();local book=type(C_SpellBook)=="table" and C_SpellBook or {}
  if slots.bookSlot and type(book.IsSpellBookItemInRange)=="function" and type(book.GetSpellBookItemInfo)=="function" then
   local item=S.readableCall(book.GetSpellBookItemInfo,slots.bookSlot,slots.bookBank)
   if S.safeField(item,"spellID")==6603 then
    local ok,result=pcall(book.IsSpellBookItemInRange,slots.bookSlot,slots.bookBank,unit)
    if hasRangeResult(ok,result) then return true,result,"spellbook" end
   end
  end
  local action=type(C_ActionBar)=="table" and C_ActionBar or {}
  if type(action.IsActionInRange)=="function" then for _,slot in ipairs(slots.actions) do
   if attackAction(slot) then
    local ok,result=pcall(action.IsActionInRange,slot,unit)
    if hasRangeResult(ok,result) then return true,result,"action" end
   end
  end end
 end
 local ok,result=R.range(S.spellAPI.IsSpellInRange or IsSpellInRange,id,unit)
 return ok,result,"spell"
end
function X.nearby()
 local S=ns.state;local id,reach=X.nearbyProbe();local near="";local packed=0
 -- Fixed unique tokens also work after /reload without waiting for ADD events.
 -- Forty is a bounded sample; omitted/off-screen enemies are not assumed absent.
 for i=1,40 do
  local unit="nameplate"..i;local range;local exists=value(UnitExists,unit)
  if exists==false then range=false
  elseif exists==true and id>0 then
   local dead=value(UnitIsDeadOrGhost,unit);local hostile=value(UnitCanAttack,"player",unit);local combat=value(UnitAffectingCombat,unit)
   if dead==true or hostile==false or combat==false then range=false
   elseif dead==false and hostile==true and combat==true and X.engaged(unit)==true then
    local ok,result=X.readMeleeRange(unit,id);if ok then range=result end
   end
  end
  packed=packed+(S.isSecret(range) and 0 or flag(range))*4^((i-1)%4)
  if i%4==0 then near=near..S.bytes(packed,1);packed=0 end
  local dot=X.nearbyDots and X.nearbyDots[i]
  if dot then
   local ok,painted=pcall(ns.features.RangeTracking.paintBoolean,dot,range,{0,1,0,1},{1,0,0,1})
   if not ok or painted~=true then ns.features.RangeTracking.paintColor(dot,1,.65,0,1) end
  end
 end
 local info=value(S.spellAPI.GetSpellInfo,"Consecration");local costID=S.safeField(info,"spellID");local cost=255
 if type(costID)~="number" or value(S.bookAPI.IsSpellKnown or IsSpellKnown,costID)~=true then costID=0
 else cost=ns.features.CastTracking.manaFraction(costID,true) end
 return S.bytes(id,4)..S.bytes(reach,1)..S.bytes(costID,4)..S.bytes(cost,1)..near,id,reach
end
-- The same proven short-range probe can observe the selected target. Public
-- unit eligibility guards the query; only native colors receive secret range.
function X.targetMelee(id,reach)
 local S=ns.state;local range
 if id>0 and reach>0 and reach<=8 and value(UnitExists,"target")==true
  and value(UnitIsDeadOrGhost,"target")==false and value(UnitCanAttack,"player","target")==true then
  local ok,result=X.readMeleeRange("target",id)
  if ok then range=result end
 end
 local ok,painted=pcall(ns.features.RangeTracking.paintBoolean,X.meleeDot,range,{0,1,0,1},{1,0,0,1})
 if not ok or painted~=true then ns.features.RangeTracking.paintColor(X.meleeDot,1,.65,0,1) end
end
function X.effects(unit)
 local S=ns.state;local G=ns.features.GroupContext;local result={debuffs={}};local complete=false;local idsComplete=true;local seenIDs={}
 if value(UnitExists,unit)~=true then return result end
 local api=type(C_LossOfControl)=="table" and C_LossOfControl or {}
 local count
 if unit=="player" then count=value(api.GetActiveLossOfControlDataCount) else count=value(api.GetActiveLossOfControlDataCountByUnit,unit) end
 if type(count)=="number" and count>=0 and count<=64 and count==math.floor(count) then
  complete=true
  for i=1,count do
   local event
   if unit=="player" then event=value(api.GetActiveLossOfControlData,i) else event=value(api.GetActiveLossOfControlDataByUnit,unit,i) end
   local kind=S.safeField(event,"locType")
   local auraKind,excluded=controlKind(S.safeField(event,"spellID") or S.safeField(event,"spellId"))
   if type(kind)~="string" then complete=false end
   if auraKind then applyControl(result,auraKind)
   elseif excluded then -- known different mechanic; do not infer from a generic LoC type
   elseif kind=="ROOT" or kind=="SNARE" then result.movement=true
   elseif kind=="CHARM" or kind=="FEAR" or kind=="FEAR_MECHANIC" or kind=="SLEEP" then result.forsaken=true
   elseif kind=="STUN" or kind=="STUN_MECHANIC" then result.stun=true end
  end
 end
 if complete then result.forsaken=result.forsaken or false;result.stun=result.stun or false end
 local auraAPI=type(C_UnitAuras)=="table" and C_UnitAuras or {};local scanned=false;local unclassified=false;local classified=true;local dispelClassified=true
 for i=1,80 do
  if type(auraAPI.GetAuraDataByIndex)~="function" then break end
  local ok,aura=pcall(auraAPI.GetAuraDataByIndex,unit,i,"HARMFUL")
  if not ok or S.isSecret(aura) then break end
  if aura==nil then scanned=true;break end
  local name=S.safeField(aura,"name");local dispel=S.safeField(aura,"dispelName")
  local id=S.safeField(aura,"spellId") or S.safeField(aura,"spellID")
  local kind=debuffTypes[dispel]
  if kind then
   if type(id)~="number" or id<=0 or id>2147483647 or id~=math.floor(id) then idsComplete=false
   elseif seenIDs[id] then
    local old=seenIDs[id];if math.floor(old.types/kind)%2==0 then old.types=old.types+kind end
   elseif #result.debuffs<16 then local entry={id=id,types=kind};result.debuffs[#result.debuffs+1]=entry;seenIDs[id]=entry
   else idsComplete=false end
  end
  if type(name)~="string" or S.isSecret(aura.dispelName) then classified=false end
  if S.isSecret(aura.dispelName) then dispelClassified=false end
  local impairment=S.safeField(aura,"isMovementImpairing")
  local auraKind,excluded=controlKind(id)
  if auraKind then applyControl(result,auraKind) end
  if not auraKind and not excluded then
   -- Retained exact-name support covers older known ranks and NPC effects;
   -- new fear families use verified IDs, not broad name matching.
   if movementNames[name] or impairment==true then result.movement=true elseif impairment~=false then unclassified=true end
   if stunNames[name] then result.stun=true end
   if name=="Sleep" or name=="Deep Sleep" or name=="Charm" or name=="Mind Control" then result.forsaken=true end
  end
  if dispel=="Curse" then result.curse=true end
  if dispel=="Poison" or dispel=="Disease" or dispel=="Bleed" then result.stoneform=true end
  if dispel=="Poison" then result.poison=true end
  if dispel=="Disease" then result.disease=true end
 end
 if scanned and classified then result.curse=result.curse or false;result.stoneform=result.stoneform or false end
 if scanned and dispelClassified then result.poison=result.poison or false;result.disease=result.disease or false end
 result.debuffsComplete=scanned and dispelClassified and idsComplete
 -- LoC commonly omits slows. Never certify their absence from an empty LoC list.
 if scanned and complete and not unclassified then result.movement=result.movement or false end
 return result
end
local racialAuras={["Skysight"]="Elemental Blessing",["Read Ley Line"]="Energized"}
local function active(name,unit,cache)
 local S=ns.state;local api=type(C_UnitAuras)=="table" and C_UnitAuras or {}
 if type(api.GetAuraDataByIndex)~="function" then return nil end
 unit=unit or "player"
 local scan=cache[unit]
 if not scan then scan={names={},next=1};cache[unit]=scan end
 if scan.names[name] or scan.names[racialAuras[name]] then return true end
 if scan.done then if scan.complete then return false end;return nil end
 for i=scan.next,80 do
  local ok,a=pcall(api.GetAuraDataByIndex,unit,i,"HELPFUL")
  if not ok or S.isSecret(a) then scan.done=true;return nil end
  if a==nil then scan.done=true;scan.complete=true;return false end
  local n=S.safeField(a,"name");if type(n)~="string" then scan.done=true;return nil end
  scan.names[n]=true;scan.next=i+1
  if n==name or n==racialAuras[name] then return true end
 end
 scan.done=true
end
function X.tracking()
 local S=ns.state;local api=type(C_Minimap)=="table" and C_Minimap or {}
 local count=value(api.GetNumTrackingTypes or GetNumTrackingTypes)
 if type(count)~="number" or count<0 or count>64 then return nil end
 local complete=true;local other=false
 for i=1,count do
  local name,on
  if type(api.GetTrackingInfo)=="function" then local info=value(api.GetTrackingInfo,i);name=S.safeField(info,"name");on=S.safeField(info,"active")
  elseif type(GetTrackingInfo)=="function" then local ok,n,_,a=pcall(GetTrackingInfo,i);if ok and not S.isSecret(n) and not S.isSecret(a) then name=n;on=a==true or a==1 end end
  if type(name)~="string" or type(on)~="boolean" then complete=false
  elseif on and name=="Find Treasure" then return true
  elseif on then other=true end
 end
 if complete and not other then return false end -- do not replace another tracking choice
end
function X.native()
 if X.tiles or not ns.state.hud then return end
 local S=ns.state;X.tiles={};X.stamp={};X.ranges={};X.nearbyDots={}
 X.meleeDot=S.hud:CreateTexture(nil,"OVERLAY");X.meleeDot:SetSize(4,4);X.meleeDot:SetPoint("TOPLEFT",572,-2);ns.features.RangeTracking.initialize(X.meleeDot,1,.65,0,1)
 for i=1,40 do local p=S.hud:CreateTexture(nil,"OVERLAY");p:SetSize(2,2);p:SetPoint("TOPLEFT",580+(i-1)*2,-2);ns.features.RangeTracking.initialize(p,1,.65,0,1);X.nearbyDots[i]=p end
 for i=1,4 do
  local x=350+(i-1)*38;local tile={}
  tile.dial=S.hud:CreateTexture(nil,"BACKGROUND");tile.dial:SetSize(12,12);tile.dial:SetPoint("TOPLEFT",x,-1)
  tile.cooldown=CreateFrame("Cooldown",nil,S.hud,"CooldownFrameTemplate");tile.cooldown:SetAllPoints(tile.dial);tile.cooldown:SetDrawEdge(false);tile.cooldown:SetDrawSwipe(true);tile.cooldown:SetSwipeColor(0,0,0,1);tile.cooldown:SetHideCountdownNumbers(true)
  tile.signals={}
  for j=1,4 do local dot=S.hud:CreateTexture(nil,"OVERLAY");dot:SetSize(4,4);dot:SetPoint("TOPLEFT",x+14+(j-1)%2*5,-1-math.floor((j-1)/2)*5);ns.features.RangeTracking.initialize(dot,1,.65,0,1);tile.signals[j]=dot end
  X.tiles[i]=tile
 end
 for i=1,#X.units do local p=S.hud:CreateTexture(nil,"OVERLAY");p:SetSize(4,4);p:SetPoint("TOPLEFT",510+(i-1)*6,-2);ns.features.RangeTracking.initialize(p,1,.65,0,1);X.ranges[i]=p end
 -- Spare header space between the existing Freedom signals and range dots.
 local tile={};tile.dial=S.hud:CreateTexture(nil,"BACKGROUND");tile.dial:SetSize(8,8);tile.dial:SetPoint("TOPLEFT",490,-1)
 tile.cooldown=CreateFrame("Cooldown",nil,S.hud,"CooldownFrameTemplate");tile.cooldown:SetAllPoints(tile.dial);tile.cooldown:SetDrawEdge(false);tile.cooldown:SetDrawSwipe(true);tile.cooldown:SetSwipeColor(0,0,0,1);tile.cooldown:SetHideCountdownNumbers(true)
 tile.signals={};for j=1,4 do local dot=S.hud:CreateTexture(nil,"OVERLAY");dot:SetSize(4,4);dot:SetPoint("TOPLEFT",500+(j-1)%2*5,-1-math.floor((j-1)/2)*5);ns.features.RangeTracking.initialize(dot,1,.65,0,1);tile.signals[j]=dot end
 X.cleanseTile=tile
 for i=1,4 do local p=S.hud:CreateTexture(nil,"OVERLAY");p:SetSize(4,4);p:SetPoint("TOPLEFT",550+(i-1)*6,-2);X.stamp[i]=p end
end
function X.packet(tick)
 local S=ns.state;local G=ns.features.GroupContext;local F=ns.features.Healing
 -- Reuse only within this synchronous packet assembly. No value survives to
 -- another tick, event or publication; partial scans retain unknown absence.
 local helpful,unitEffects={},{}
 X.native()
 local class=value(function()local _,c=UnitClass("player");return c end)
 local race=value(function()local _,r=UnitRace("player");return r end) or ""
 if #race>32 then race="" end
 local roster=S.transportPackets[16];local rosterTick=roster and string.byte(roster.packet,9) and 0 or nil
 if roster then for i=0,3 do rosterTick=rosterTick+string.byte(roster.packet,9+i)*256^i end end
 local revision=F.revision or 0
 local packet="HHX5"..S.bytes(S.setupSession,4)..S.bytes(tick,4)..S.bytes(rosterTick or 0,4)..S.bytes(revision,4)..S.bytes(#race,1)..race
 local contexts={value(IsFalling),value(IsStealthed),value(UnitIsPlayer,"target"),value(UnitIsDeadOrGhost,"target"),value(UnitAffectingCombat,"player")}
 local corpseType=value(UnitCreatureType,"target")
 contexts[6]=(corpseType=="Humanoid" or corpseType=="Undead") and true or type(corpseType)=="string" and false or nil
 local now=value(GetTime)
 contexts[7]=type(now)=="number" and X.herbAt and now-X.herbAt>=0 and now-X.herbAt<=1 or false
 contexts[8]=X.tracking()
 local flags=0;for i=1,8 do flags=flags+flag(contexts[i])*4^(i-1) end
 local power=value(UnitPowerType,"player");local mana=type(power)=="number" and power==0 or nil
 if type(power)=="number" and power~=0 then mana=false end
 packet=packet..S.bytes(flags,2)..S.bytes(flag(mana),1)
 local list=ns.features.Racials.learned();packet=packet..S.bytes(#list,1)
 for i,spec in ipairs(list) do
  local spell=F.spell(spec,"player");local entry=S.managedSpells.entries[class..":"..spec.name]
  local code=S.managedSpells.current(entry) and entry.id==spec.id and S.compactBindingCode(entry.key) or 0
  local presence
  if spec.name=="Find Treasure" then presence=X.tracking() else presence=active(spec.name,nil,helpful) end
  local sf=G.code(spell.usable)+G.code(spell.mana)*4+G.code(spell.ready)*16+flag(presence)*64
  local range=ns.features.RangeTracking.readRange(S.spellAPI.IsSpellInRange,spec.id,"target")
  sf=sf+G.code(range)*256
  packet=packet..S.bytes(spec.index,1)..S.bytes(spec.id,4)..S.bytes(code,2)..S.bytes(sf,2)..S.bytes(S.spellUseCode(spec.key),1)
  if i<=3 and X.tiles then local tile=X.tiles[i];tile.spellID=spec.id;tile.known=learned(spell);tile.offGlobalCooldown=spec.offGlobalCooldown==true;S.renderCooldown(tile);ns.features.RangeTracking.render(tile.signals,spec.id,"player");if tile.useKey~=spec.key then S.attachSpellUse(S.hud,tile.dial,spec.key);tile.useKey=spec.key end end
 end
 local freedom,freedomRangeOK,freedomRangeRaw
 if class=="PALADIN" then freedom,freedomRangeOK,freedomRangeRaw=F.spell(X.freedom,"player") else freedom={id=0} end
 local entry=class=="PALADIN" and F.delivery(X.freedom) or nil
 packet=packet..S.bytes(freedom.id or 0,4)..S.bytes(entry and S.compactBindingCode(entry.key) or 0,2)..S.bytes(S.spellUseCode(X.freedom.key),1)
 if X.tiles then local tile=X.tiles[4];tile.spellID=(freedom.id or 0)>0 and freedom.id or nil;tile.known=learned(freedom);tile.offGlobalCooldown=true;S.renderCooldown(tile);ns.features.RangeTracking.render(tile.signals,freedom.id or 0,"player");if class=="PALADIN" and (freedom.id or 0)>0 and not tile.useKey then S.attachSpellUse(S.hud,tile.dial,X.freedom.key);tile.useKey=X.freedom.key end end
 for index,unit in ipairs(X.units) do
  -- Optional scopes must be friendly players; avoid scanning hostile hovers or
  -- adding aura work for other classes. The app joins their HHB3 identities.
  local covered=index<=5 or class=="PALADIN" and G.read(UnitIsPlayer,1,unit).value==true and G.read(UnitCanAssist,1,"player",unit).value==true
  local identity=covered and G.text(G.read(UnitGUID,1,unit),40) or "";local effects=covered and X.effects(unit) or {};unitEffects[unit]=effects;local ef=0
  for i,key in ipairs({"movement","forsaken","stun","curse","stoneform"}) do ef=ef+flag(effects[key])*4^(i-1) end
  local spell,rangeOK,rangeRaw
  if class=="PALADIN" and covered then
   if unit=="player" then spell,rangeOK,rangeRaw=freedom,freedomRangeOK,freedomRangeRaw else spell,rangeOK,rangeRaw=F.spell(X.freedom,unit) end
  else spell={id=0} end
  local sf=G.code(spell.learned)+G.code(spell.usable)*4+G.code(spell.mana)*16+G.code(spell.ready)*64+G.code(spell.range)*256
  local presence
  if class=="PALADIN" and covered then presence=active(X.freedom.name,unit,helpful) end
  packet=packet..S.bytes(#identity,1)..identity..S.bytes(ef,2)..S.bytes(sf,2)..S.bytes(flag(presence),1)
  if X.ranges and (freedom.id or 0)>0 then
   local painted,result=pcall(ns.features.RangeTracking.paintBoolean,X.ranges[index],rangeRaw,{0,1,0,1},{1,0,0,1})
   if not rangeOK or not painted or result~=true then ns.features.RangeTracking.paintColor(X.ranges[index],1,.65,0,1) end
  end
 end
 -- Freedom can happen during a heal. Its click/result must not replace the
 -- ordinary managed healing attempt or consume its eventual terminal event.
 local receipt=F.supportAttempt;local identity=receipt and receipt.identity or "";local now=value(GetTime)
 local age=receipt and type(now)=="number" and math.floor(math.max(0,now-(receipt.eventAt or receipt.at))*1000) or 65535
 packet=packet..S.bytes(receipt and receipt.sequence or 0,4)..S.bytes(receipt and receipt.revision or 0,4)..S.bytes(receipt and receipt.id or 0,4)..S.bytes(receipt and receipt.kind or 0,1)..S.bytes(math.min(65535,age),2)..S.bytes(#identity,1)..identity
 local nearby,probe,reach=X.nearby();packet=packet..nearby
 local spec;for _,candidate in ipairs(X.cleanseSpecs) do if candidate.class==class then spec=candidate;break end end
 local cleanse=spec and F.spell(spec,"player") or {id=0}
 local managed=spec and S.managedSpells.entries[class..":"..spec.name] or nil
 local valid=managed and S.bindingsValid and S.managedSpells.current(managed) and managed.unit=="player" and not managed.friendly and managed.id==cleanse.id
 local pf=G.code(cleanse.learned)+G.code(cleanse.usable)*4+G.code(cleanse.mana)*16+G.code(cleanse.ready)*64
 local effects=unitEffects.player
 packet=packet..S.bytes(spec and spec.index or 0,1)..S.bytes(cleanse.id or 0,4)..S.bytes(valid and S.compactBindingCode(managed.key) or 0,2)..S.bytes(spec and S.spellUseCode(spec.key) or 0,1)..S.bytes(pf,1)..S.bytes(flag(effects.poison)+flag(effects.disease)*4,1)
 packet=packet..S.bytes(flag(effects.debuffsComplete),1)..S.bytes(#effects.debuffs,1)
 for _,aura in ipairs(effects.debuffs) do packet=packet..S.bytes(aura.id,4)..S.bytes(aura.types,1) end
 if X.cleanseTile then local tile=X.cleanseTile;tile.spellID=(cleanse.id or 0)>0 and cleanse.id or nil;tile.known=learned(cleanse);S.renderCooldown(tile);ns.features.RangeTracking.render(tile.signals,cleanse.id or 0,"player");if spec and (cleanse.id or 0)>0 and tile.useKey~=spec.key then S.attachSpellUse(S.hud,tile.dial,spec.key);tile.useKey=spec.key end end
 -- Paint this final native witness beside the matching support stamp only
 -- after all packet assembly succeeds. A failed producer retains no new pair.
 X.targetMelee(probe,reach)
 local checksum=S.adler32(packet)
 for i,p in ipairs(X.stamp or {}) do local c=math.floor(checksum/256^(i-1))%256/255;p:SetColorTexture(c,c,c,1) end
 return packet..S.bytes(checksum,4)
end
local events=CreateFrame("Frame")
events:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED");events:RegisterEvent("UNIT_SPELLCAST_FAILED");events:RegisterEvent("LOOT_CLOSED");events:RegisterEvent("SPELLS_CHANGED");events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent",function(_,event,unit,cast,id)
 if event=="SPELLS_CHANGED" or event=="PLAYER_ENTERING_WORLD" then X.probeCache=nil;X.attackSlotCache=nil;return end
 if event=="LOOT_CLOSED" then X.herbAt=nil;return end
 local S=ns.state;if S.isSecret(unit) or unit~="player" or S.isSecret(id) then return end
 local name=value(S.spellAPI.GetSpellName,id)
 if name=="Cultivation" then X.herbAt=nil
 elseif event=="UNIT_SPELLCAST_SUCCEEDED" and (name=="Herb Gathering" or name=="Herbalism") then X.herbAt=value(GetTime) end
end)
