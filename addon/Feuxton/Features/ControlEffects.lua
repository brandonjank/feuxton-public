-- HHX6: shared control, friendly target/mouseover and independent Freedom receipt.
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
 -- Root/snare IDs: decoded Forever 1.60.1.70888 categories, preserving prior verified ranks.
 {kind="root",name="Aqua Strike",ids={404275}},
 {kind="root",name="Battle Net",ids={10852}},
 {kind="root",name="Boar Charge",ids={25999}},
 {kind="root",name="Chains of Ice",ids={113,512,22744}},
 {kind="root",name="Chastise",ids={1277331,1277332,1277333,1277334,1277335}},
 {kind="root",name="Citizen's Arrest",ids={1231280}},
 {kind="root",name="Counterattack",ids={19306,20909,20910,1242634}},
 {kind="root",name="Crushing Brambles",ids={1271000}},
 {kind="root",name="Cursed Webbing",ids={1220845}},
 {kind="root",name="Devilsaur Glare",ids={1300493,1300496}},
 {kind="root",name="Drowning Grasp",ids={1306224}},
 {kind="root",name="Earthbound",ids={1238289}},
 {kind="root",name="Earthgrab",ids={8377,440574,1269433}},
 {kind="root",name="Electrified Net",ids={11820,441453}},
 {kind="root",name="Encasing Webs",ids={4962}},
 {kind="root",name="Entangle",ids={22994,1240688}},
 {kind="root",name="Entangling Roots",ids={339,1062,5195,5196,9852,9853,11922,12747,19970,19971,19972,19973,19974,19975,20654,20699,21331,22127,22415,22800,24648,26071,28858,435991,460690,1213253,1263640,1281781,1294112,1303308,1316480,1320095}},
 {kind="root",name="Entrapment",ids={19185,465230}},
 {kind="root",name="Enveloping Web",ids={15471}},
 {kind="root",name="Enveloping Webs",ids={24110}},
 {kind="root",name="Feral Charge",ids={19675}},
 {kind="root",name="Fox-Catching Net",ids={1280481}},
 {kind="root",name="Frost Hold",ids={10017}},
 {kind="root",name="Frost Nova",ids={122,865,6131,9915,10230,11831,12674,12748,14907,15063,15531,15532,22645,29849,30094,463448,1220855,1289447,1300716,1310354}},
 {kind="root",name="Frostbite",ids={12494}},
 {kind="root",name="Frozen",ids={1306620}},
 {kind="root",name="Grasping Vines",ids={8142,22924}},
 {kind="root",name="Headhunter's Barbed Spear",ids={446731}},
 {kind="root",name="Hooked Net",ids={13608,14030,15609}},
 {kind="root",name="Ice Blast",ids={11264,467370,467832}},
 {kind="root",name="Ice Nova",ids={22519}},
 {kind="root",name="Improved Hamstring",ids={23694}},
 {kind="root",name="Improved Wing Clip",ids={19229}},
 {kind="root",name="Infernal Lasso",ids={447590,1312052}},
 {kind="root",name="Miring Mud",ids={5567}},
 {kind="root",name="Mobility Malfunction",ids={8346}},
 {kind="root",name="Naraxis Web",ids={3542}},
 {kind="root",name="Net",ids={6533,12024,1283364,1303136}},
 {kind="root",name="Net-o-Matic",ids={13099,13119,13138,16566}},
 {kind="root",name="Nightmare Brambles",ids={368329}},
 {kind="root",name="Pet Submerge",ids={42598}},
 {kind="root",name="Rootbinder's Will",ids={1307520}},
 {kind="root",name="Silken Tomb",ids={1269767}},
 {kind="root",name="Spare Change",ids={446631,448156,450005}},
 {kind="root",name="Spider's Kiss",ids={17333}},
 {kind="root",name="Trap",ids={8312}},
 {kind="root",name="Web",ids={745,12023,28991,1265843,1265878,1265880,1265881,1265883}},
 {kind="root",name="Web Explosion",ids={15474,16469}},
 {kind="root",name="Web Spray",ids={12252}},
 {kind="root",name="Whipweed Roots",ids={24152}},
 {kind="snare",name="Aftermath",ids={18118}},
 {kind="snare",name="Avenger's Shield",ids={470265}},
 {kind="snare",name="Baron Rivendare's Soul Drain",ids={27640}},
 {kind="snare",name="Black Sludge",ids={7279}},
 {kind="snare",name="Blast Wave",ids={11113,13018,13019,13020,13021}},
 {kind="snare",name="Blizzard",ids={1271394,1291168}},
 {kind="snare",name="Buriza-Do Spike",ids={1309005}},
 {kind="snare",name="Caustic Slime",ids={468925}},
 {kind="snare",name="Chew Hamstring",ids={1231397}},
 {kind="snare",name="Chilled",ids={6136,7321,12484,16927,20005,1296223}},
 {kind="snare",name="Chilling Blade",ids={1294273}},
 {kind="snare",name="Chilling Touch",ids={12531}},
 {kind="snare",name="Cold Eye",ids={1139}},
 {kind="snare",name="Concussed",ids={1318163}},
 {kind="snare",name="Concussive Shot",ids={5116,17174,22914,27634,1236191}},
 {kind="snare",name="Cone of Cold",ids={120,8492,10159,10160,10161}},
 {kind="snare",name="Confession",ids={1231873}},
 {kind="snare",name="Copy of Frostbolt",ids={29163}},
 {kind="snare",name="Creeping Chill",ids={367740}},
 {kind="snare",name="Cripple",ids={89,11443,20812,29212,1238366,1239241,1250426}},
 {kind="snare",name="Crippling Poison",ids={3409,11201,25809}},
 {kind="snare",name="Curse of Exhaustion",ids={18223}},
 {kind="snare",name="Cursed Blade",ids={462228}},
 {kind="snare",name="Debug Frost Spell",ids={29607}},
 {kind="snare",name="Demolishing Smash",ids={437617}},
 {kind="snare",name="Desert Winds",ids={1320579,1320580}},
 {kind="snare",name="Devour",ids={438101}},
 {kind="snare",name="Discombobulate",ids={4060}},
 {kind="snare",name="Diseased Slime",ids={6907}},
 {kind="snare",name="Earthbind",ids={3600}},
 {kind="snare",name="Eskhandar's Rake",ids={22639}},
 {kind="snare",name="Exhaustion",ids={24225}},
 {kind="snare",name="Feral Charge",ids={414923}},
 {kind="snare",name="Freezing",ids={438720}},
 {kind="snare",name="Freezing Arrow",ids={407548}},
 {kind="snare",name="Frigid Depths",ids={1313978}},
 {kind="snare",name="Frost",ids={18977}},
 {kind="snare",name="Frost Breath",ids={31688}},
 {kind="snare",name="Frost Shock",ids={8056,8058,10472,10473,12548,15089,15499,19133,21030,21401,22582,23115,1248001}},
 {kind="snare",name="Frost Shot",ids={6984,6985,12551,18802}},
 {kind="snare",name="Frost Trap Aura",ids={13810}},
 {kind="snare",name="Frostbolt",ids={116,205,837,7322,8406,8407,8408,9672,10179,10180,10181,11538,12675,13322,13439,15043,15497,15530,16249,16799,17503,20297,20792,20806,20819,20822,21369,23102,24942,25304,28478,28479,350025,406680,420526,1213276,1220854,1244970,1248148,1283410,1283420,1293790,1298416,1300715,1303226,1310353}},
 {kind="snare",name="Frostbolt Volley",ids={8398,12737,22643,1220853,1266642,1289448}},
 {kind="snare",name="Frostbrand Attack",ids={8034,8037,10458,16352,16353}},
 {kind="snare",name="Frostfire Bolt",ids={401502,1237312,1237313}},
 {kind="snare",name="Frozen Orb",ids={440809}},
 {kind="snare",name="Geyser",ids={10987}},
 {kind="snare",name="Greater Frostbolt",ids={404316}},
 {kind="snare",name="Gunk",ids={438142}},
 {kind="snare",name="Hallow's End Fright",ids={25022}},
 {kind="snare",name="Hamstring",ids={1715,7372,7373,9080,26141,26211,27584,1236177}},
 {kind="snare",name="High-Yield Radiation Bomb",ids={443813}},
 {kind="snare",name="Hive'Zara Catalyst",ids={25187}},
 {kind="snare",name="Howling Blast",ids={1310514}},
 {kind="snare",name="Hurricane",ids={1289130}},
 {kind="snare",name="Hydra Strike",ids={1292739}},
 {kind="snare",name="Incapacitating Shout",ids={18328}},
 {kind="snare",name="Lacerate",ids={5422}},
 {kind="snare",name="Lag",ids={10855}},
 {kind="snare",name="Long Daze",ids={12705}},
 {kind="snare",name="Low Swipe",ids={8716}},
 {kind="snare",name="Magma Shackles",ids={19496}},
 {kind="snare",name="Melt Ore",ids={5159}},
 {kind="snare",name="Might of Vis'era",ids={1231541}},
 {kind="snare",name="Mind Flay",ids={15407,16568,17165,17311,17312,17313,17314,18807,22919,23953,26044,26143,28310,29407,412526,474204,474268,1215740}},
 {kind="snare",name="OLDFrost Trap Effect",ids={14207}},
 {kind="snare",name="Piercing Howl",ids={12323,23600}},
 {kind="snare",name="Piercing Shriek",ids={26379}},
 {kind="snare",name="Pinch",ids={1264735,1264736,1264739,1264741,1264742}},
 {kind="snare",name="Plague Nova",ids={1293327}},
 {kind="snare",name="Plagued Shot",ids={446573}},
 {kind="snare",name="Quick Draw",ids={398196}},
 {kind="snare",name="Riverglades Marsh Gas",ids={1295639}},
 {kind="snare",name="Rotted Strike",ids={1282519}},
 {kind="snare",name="Shadowy Chains",ids={425239,426495}},
 {kind="snare",name="Sliced Ankle",ids={1316346}},
 {kind="snare",name="Slow",ids={246,6146,11436,13747,18972,19137,22356,24415,1236220,1240686,1303350}},
 {kind="snare",name="Slow Poison",ids={1294208}},
 {kind="snare",name="Slowing Ooze",ids={16050}},
 {kind="snare",name="Slowing Poison",ids={7992,14897}},
 {kind="snare",name="Spellfrost Bolt",ids={412532}},
 {kind="snare",name="Stomp",ids={27993}},
 {kind="snare",name="Stygian Grasp",ids={29164,1219270,1220520}},
 {kind="snare",name="Stygian Grip",ids={1220533}},
 {kind="snare",name="Tendon Rip",ids={3604,1265038,1265039,1265040,1265041,1265042}},
 {kind="snare",name="Theka's Last Breath",ids={1294617,1294626}},
 {kind="snare",name="Thunderclap",ids={8078,8147,15548,15588,23931,1213464}},
 {kind="snare",name="Triple Bolt",ids={448573,448574}},
 {kind="snare",name="Unstable Fuel Cell",ids={1251362}},
 {kind="snare",name="Vekniss Catalyst",ids={26078}},
 {kind="snare",name="Waylay",ids={408699}},
 {kind="snare",name="Wing Clip",ids={2974,14267,14268,27633,1310180}},
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
local function prepareNativeMovement()
 if X.movementNativeAttempted or not ns.state.hud or value(InCombatLockdown)~=false then return end
 X.movementNativeAttempted=true
 local S=ns.state
 X.movementNativeReady=false;X.movementNativeError=nil
 -- The native aura engine owns filtering and protected visibility. No aura
 -- field, secret numeric argument or visibility result is read by Lua.
 local base=S.hud:CreateTexture(nil,"OVERLAY");base:SetSize(4,4);base:SetPoint("TOPLEFT",316,-2);base:SetColorTexture(1,.65,0,1)
 local native
 local ok,err=pcall(function()
  local ids={};for id,kind in pairs(controlByID)do if kind=="root"or kind=="snare"then ids[id]=true end end
  native=CreateFrame("AuraContainer",nil,S.hud,"CustomAuraContainerTemplate")
  native:SetPoint("TOPLEFT",S.hud,"TOPLEFT",316,-2);native:SetSize(4,4)
  native:AddAuraSlot("selfMovement","HARMFUL",{candidateFilters={includeSpellIDs=ids},initializeFrame=function(button)
   local rendered,why=pcall(function()
    button:SetSize(4,4);button:SetPoint("TOPLEFT",native,"TOPLEFT",0,0);button:EnableMouse(false)
    local dot=button:CreateTexture(nil,"OVERLAY");dot:SetAllPoints(button);dot:SetColorTexture(0,1,0,1)
   end)
   if not rendered then X.movementNativeReady=false;X.movementNativeError=S.describe(why)end
  end})
  native:SetUnit("player");native:SetEnabled(true)
 end)
 X.movementNativeReady=ok and X.movementNativeError==nil;X.movementAuraContainer=native
 if not ok then X.movementNativeError=S.describe(err);if native then pcall(native.Hide,native)end end
end
function X.native()
 prepareNativeMovement()
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
 -- Invalidate the old native witness before repainting any current values.
 -- A capture during assembly cannot join a new root cell to an old packet.
 if X.stamp and X.stamp[1]then X.stamp[1]:SetColorTexture(1,0,1,1)end
 local class=value(function()local _,c=UnitClass("player");return c end)
 local race=value(function()local _,r=UnitRace("player");return r end) or ""
 if #race>32 then race="" end
 local roster=S.transportPackets[ns.wire.ids.rosterFirst];local rosterTick=roster and string.byte(roster.packet,9) and 0 or nil
 if roster then for i=0,3 do rosterTick=rosterTick+string.byte(roster.packet,9+i)*256^i end end
 local revision=F.revision or 0
 local packet=ns.wire.schemas.sharedSupport..S.bytes(S.setupSession,4)..S.bytes(tick,4)..S.bytes(rosterTick or 0,4)..S.bytes(revision,4)..S.bytes(#race,1)..race
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
  local spell,rangeOK,rangeRaw,usableOK,usableRaw,manaRaw,rangeSource,usableSource=F.spell(spec,"player");local entry=S.managedSpells.entries[class..":"..spec.name]
  local code=S.managedSpells.current(entry) and entry.id==spec.id and S.compactBindingCode(entry.key) or 0
  local presence
  if spec.name=="Find Treasure" then presence=X.tracking() else presence=active(spec.name,nil,helpful) end
  local sf=G.code(spell.usable)+G.code(spell.mana)*4+G.code(spell.ready)*16+flag(presence)*64
  local range=ns.features.RangeTracking.readRange(S.spellAPI.IsSpellInRange,spec.id,"target")
  sf=sf+G.code(range)*256
  packet=packet..S.bytes(spec.index,1)..S.bytes(spec.id,4)..S.bytes(code,2)..S.bytes(sf,2)..S.bytes(S.spellUseCode(spec.key),1)
  if i<=3 and X.tiles then local tile=X.tiles[i];tile.spellID=spec.id;tile.known=learned(spell);tile.offGlobalCooldown=spec.offGlobalCooldown==true;S.renderCooldown(tile);local same=spell.id==spec.id;ns.features.RangeTracking.render(tile.signals,spec.id,"player",same and rangeOK or nil,rangeRaw,same and usableOK or nil,usableRaw,manaRaw,rangeSource,usableSource);if tile.useKey~=spec.key then S.attachSpellUse(S.hud,tile.dial,spec.key);tile.useKey=spec.key end end
 end
 local freedom,freedomRangeOK,freedomRangeRaw,freedomUsableOK,freedomUsableRaw,freedomManaRaw,freedomRangeSource,freedomUsableSource
 if class=="PALADIN" then freedom,freedomRangeOK,freedomRangeRaw,freedomUsableOK,freedomUsableRaw,freedomManaRaw,freedomRangeSource,freedomUsableSource=F.spell(X.freedom,"player") else freedom={id=0} end
 local entry=class=="PALADIN" and F.delivery(X.freedom) or nil
 packet=packet..S.bytes(freedom.id or 0,4)..S.bytes(entry and S.compactBindingCode(entry.key) or 0,2)..S.bytes(S.spellUseCode(X.freedom.key),1)
 if X.tiles then local tile=X.tiles[4];tile.spellID=(freedom.id or 0)>0 and freedom.id or nil;tile.known=learned(freedom);tile.offGlobalCooldown=true;S.renderCooldown(tile);ns.features.RangeTracking.render(tile.signals,freedom.id or 0,"player",freedomRangeOK,freedomRangeRaw,freedomUsableOK,freedomUsableRaw,freedomManaRaw,freedomRangeSource,freedomUsableSource);if class=="PALADIN" and (freedom.id or 0)>0 and not tile.useKey then S.attachSpellUse(S.hud,tile.dial,X.freedom.key);tile.useKey=X.freedom.key end end
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
 local receipt=F.supportAttempt
 -- A binding refresh does not make an older click/result current. Retire its
 -- receipt without touching the independent heal attempt or losing the rest
 -- of this support packet after a spell/binding revision changes.
 if receipt and (receipt.revision~=revision or receipt.id~=(freedom.id or 0)) then
  F.supportAttempt=nil;receipt=nil
 end
 local identity=receipt and receipt.identity or "";local now=value(GetTime)
 local age=receipt and type(now)=="number" and math.floor(math.max(0,now-(receipt.eventAt or receipt.at))*1000) or 65535
 packet=packet..S.bytes(receipt and receipt.sequence or 0,4)..S.bytes(receipt and receipt.revision or 0,4)..S.bytes(receipt and receipt.id or 0,4)..S.bytes(receipt and receipt.kind or 0,1)..S.bytes(math.min(65535,age),2)..S.bytes(#identity,1)..identity
 local nearby,probe,reach=X.nearby();packet=packet..nearby
 local spec;for _,candidate in ipairs(X.cleanseSpecs) do if candidate.class==class then spec=candidate;break end end
 local cleanse,cleanseRangeOK,cleanseRangeRaw,cleanseUsableOK,cleanseUsableRaw,cleanseManaRaw,cleanseRangeSource,cleanseUsableSource
 if spec then cleanse,cleanseRangeOK,cleanseRangeRaw,cleanseUsableOK,cleanseUsableRaw,cleanseManaRaw,cleanseRangeSource,cleanseUsableSource=F.spell(spec,"player") else cleanse={id=0} end
 local managed=spec and S.managedSpells.entries[class..":"..spec.name] or nil
 local valid=managed and S.bindingsValid and S.managedSpells.current(managed) and managed.unit=="player" and not managed.friendly and managed.id==cleanse.id
 local pf=G.code(cleanse.learned)+G.code(cleanse.usable)*4+G.code(cleanse.mana)*16+G.code(cleanse.ready)*64
 local effects=unitEffects.player
 packet=packet..S.bytes(spec and spec.index or 0,1)..S.bytes(cleanse.id or 0,4)..S.bytes(valid and S.compactBindingCode(managed.key) or 0,2)..S.bytes(spec and S.spellUseCode(spec.key) or 0,1)..S.bytes(pf,1)..S.bytes(flag(effects.poison)+flag(effects.disease)*4+(X.movementNativeReady and 16 or 0),1)
 packet=packet..S.bytes(flag(effects.debuffsComplete),1)..S.bytes(#effects.debuffs,1)
 for _,aura in ipairs(effects.debuffs) do packet=packet..S.bytes(aura.id,4)..S.bytes(aura.types,1) end
 if X.cleanseTile then local tile=X.cleanseTile;tile.spellID=(cleanse.id or 0)>0 and cleanse.id or nil;tile.known=learned(cleanse);S.renderCooldown(tile);ns.features.RangeTracking.render(tile.signals,cleanse.id or 0,"player",cleanseRangeOK,cleanseRangeRaw,cleanseUsableOK,cleanseUsableRaw,cleanseManaRaw,cleanseRangeSource,cleanseUsableSource);if spec and (cleanse.id or 0)>0 and tile.useKey~=spec.key then S.attachSpellUse(S.hud,tile.dial,spec.key);tile.useKey=spec.key end end
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
