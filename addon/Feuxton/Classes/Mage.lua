-- Mage catalog, current MGS1 packet and native widgets. Rotation/input remain app-owned.
local _,ns=...
local H={coreSlotCount=2,denseBridgeLayout={key="mage-slim-v1",requiredSignals=true,gauges=102,units=102,unitHeight=20,activity=14,headerActivity=true,resources=102,setup=122,grid=122,roster=122,coreStamp=108,targetStamp=122,marker={140/255,191/255,1}}}
ns.classes.MAGE=H
H.specs=ns.spellCatalog.MAGE.specs
local function obs(value) if type(value)=="boolean" then return {status="observed",value=value} end;return {} end
local function count(id)
 local S=ns.state;local n=S.readableCall(C_Item and C_Item.GetItemCount or GetItemCount,id,false,false,false,false)
 return type(n)=="number" and n>=0 and n<=65534 and n==math.floor(n) and n or nil
end
-- Reuse the shared, deferred bag index. Only immutable item classification is
-- retained; every quantity/cooldown is read anew, never cached across combat.
H.items={};H.foodKinds={}
local function inventory()
 local C=ns.features.Consumables;local S=ns.state;if not C then return nil,nil end
 local rows,complete=C.bagLocations();local seen={};local pending=false;local budget=8;local food,water=0,0;local selected={}
 for _,row in ipairs(rows or {}) do local id=row.itemID;if not seen[id] then seen[id]=true
  local facts=C.publicItemFacts(id);local name=facts and facts.name
  if not facts then pending=true
  elseif name and name:find("^Conjured ") then
   local kind=H.foodKinds[id]
   if not kind and budget>0 then
    budget=budget-1;local _,_,spell=C.itemState(id);local description=spell and S.readableCall(S.spellAPI.GetSpellDescription,spell)
    if type(description)=="string" then description=description:lower();kind={food=description:find("health",1,true)~=nil,water=description:find("mana",1,true)~=nil};H.foodKinds[id]=kind end
   end
   local n=count(id);if not kind or not n then pending=true else if kind.food then food=food+n end;if kind.water then water=water+n end end
  end
  if name=="Major Spellblasting Potion" then selected["mage.spellblastingPotion"]=id end
 end end
 local changed=false
 for _,spec in ipairs(H.specs) do if spec.itemID then
  local id=spec.itemID>0 and spec.itemID or selected[spec.key] or 0
  if H.items[spec.key]~=id then H.items[spec.key]=id;changed=true end
 end end
 if changed and ns.markSetupDirty then ns.markSetupDirty() end
 if not complete or pending then return nil,nil end
 return math.min(food,65534),math.min(water,65534)
end
function H.extraCandidates()
 local C=ns.features.Consumables;local out={{id=0,name="Feuxton Stop Casting",unit="player",stopCasting=true}}
 if C then for _,spec in ipairs(H.specs) do if spec.itemID then local id=H.items[spec.key] or spec.itemID;local n=id>0 and count(id)
  if n and n>0 then local _,_,spell=C.itemState(id);if spell and spell>0 then out[#out+1]={id=spell,name="Feuxton "..spec.name,abilityKey=spec.key,itemID=id,unit="player"} end end
 end end end
 return out
end
function H.initializePreview()
 local S=ns.state;local G=ns.features.GroupContext;if G.text(G.read(UnitClass,2,"player"),16)~="MAGE" then return end
 local B=ns.features.SpellBridge;local bridge=B.create(S.hud,H.specs,true);H.bridge=bridge;S.mageNativePanel=bridge.panel
 local combatDot=bridge.panel:CreateTexture(nil,"OVERLAY");combatDot:SetSize(6,6);combatDot:SetPoint("TOPLEFT",bridge.panel,"TOPLEFT",120,-52)
 local wandDot=bridge.panel:CreateTexture(nil,"OVERLAY");wandDot:SetSize(6,6);wandDot:SetPoint("TOPLEFT",bridge.panel,"TOPLEFT",132,-52)
 local tick,elapsed=0,0
 local function render()
  if not S.executionBytes then return end
  tick=(tick+1)%4294967296;local food,water=inventory();local F=ns.features.Healing
  local level=S.readableCall(UnitLevel,"player");if type(level)~="number" or level<1 or level>100 then error("Level unavailable") end
  local readings={}
  for i,spec in ipairs(H.specs) do
   local r,a,b,c,d,e,f,g
   if spec.itemID then
    local id=H.items[spec.key] or spec.itemID;local n=id>0 and count(id);local ready,usable,useSpell
    if id>0 then ready,usable,useSpell=ns.features.Consumables.itemState(id) end
    r={id=useSpell or 0,learned=obs(n and n>0 and useSpell~=nil),usable=obs(usable),mana=obs(false),range=obs(true),ready=obs(ready),itemID=id,count=n}
   else
    r,a,b,c,d,e,f,g=F.spell(spec,spec.unit or "target")
    if spec.passive and S.setupTalentNames then
     local source=spec.knownFrom;local talent=S.setupTalentNames[spec.name] or source and S.setupTalentNames[source]
     for _,known in ipairs(S.setupKnownSpells or {}) do if known.name==source then talent=true;break end end
     if talent then r.learned=obs(true) elseif S.setupTalentsAvailable==true and S.setupBookAvailable==true and r.learned.value~=true then r.learned=obs(false) end
    end
   end
   readings[i]=r
   if not spec.itemID and not spec.passive then B.render(bridge,i,r.id,r.learned.value,spec,a,b,c,d,e,f,g);B.renderManaCost(bridge.tiles[i].manaCost,r.id,r.learned.value==true) end
  end
  B.auras(bridge,H.specs,readings)
  local packet=ns.wire.schemas.magePreview..S.bytes(S.setupSession,4)..S.bytes(tick,4)..S.bytes(level,1)..S.bytes(S.updateRateMs,2)..S.bytes(S.auraGeneration,1)..S.bytes(#H.specs,1)..S.bytes(S.bindingsValid and 2 or 0,1)
  for i,spec in ipairs(H.specs) do
   local r=readings[i];local M=S.managedSpells;local key=0
   if spec.itemID then
    local entry=M and S.bindingsValid and M.entries["MAGE:Feuxton "..spec.name]
    if entry and entry.itemID==r.itemID and entry.id==r.id and M.current(entry) then key=S.compactBindingCode(entry.key) end
   elseif not spec.passive then key=M and M.deliveryCode("MAGE",spec.managedName or spec.name) or 0 end
   local flags=0;for j,value in ipairs({r.learned,r.usable,r.mana,r.range,r.ready,r.aura or {}}) do flags=flags+G.code(value)*4^(j-1) end
   local info=r.id>0 and S.readableCall(S.spellAPI.GetSpellInfo,r.id);local ms=spec.itemID and 0 or S.safeField(info,"castTime");if type(ms)~="number" or ms<0 or ms>10000 then ms=65535 end
   local absent=bridge.absence and bridge.absence[i] and GetTime()>=(bridge.settledAt or math.huge)
   local meta=S.spellUseCode(spec.key)+(absent and 4 or 0)+(bridge.configured and bridge.configured[i] and 8 or 0)
   packet=packet..S.bytes(r.id,4)..S.bytes(key,2)..S.bytes(flags,2)..S.bytes(meta,1)..S.bytes(ms,2)..S.bytes(r.itemID or 0,4)..S.bytes(r.count or 65535,2)
  end
  local combat=G.read(UnitAffectingCombat,1,"player");combatDot:SetColorTexture(1,1,1,1)
  local ok,painted=pcall(ns.features.RangeTracking.paintBoolean,combatDot,UnitAffectingCombat("player"),{0,1,0,1},{.2,.2,.2,1});if not ok or painted~=true then combatDot:SetVertexColor(1,1,1,1);combatDot:SetColorTexture(1,.65,0,1) end
  -- IsAutoRepeatSpell is a type query, not active state. Explicit start/stop
  -- events stay authoritative between shots, as in the existing Warlock bridge.
  local wand,wandRaw={},nil
  if S.autoStateSource=="autorepeat event" and type(S.autoActive)=="boolean" then wand=obs(S.autoActive);wandRaw=S.autoActive
  else local current=S.spellAPI.IsCurrentSpell or IsCurrentSpell
   if type(current)=="function" then local ok,value=pcall(current,5019);if ok then wandRaw=value;if not S.isSecret(value) and type(value)=="boolean" then wand=obs(value) end end end
  end
  wandDot:SetColorTexture(1,1,1,1);local painted,result=pcall(ns.features.RangeTracking.paintBoolean,wandDot,wandRaw,{0,1,0,1},{.2,.2,.2,1});if not painted or result~=true then wandDot:SetVertexColor(1,1,1,1);wandDot:SetColorTexture(1,.65,0,1) end
  packet=packet..S.executionBytes(2)..S.bytes(G.code(combat),1)..S.bytes(G.code(wand),1)
  for i=1,3 do local p=S.setupTalentPoints and S.setupTalentPoints[i];packet=packet..S.bytes(type(p)=="number" and p>=0 and p<=100 and p or 255,1) end
  local stop=S.managedSpells and S.managedSpells.entries["MAGE:Feuxton Stop Casting"]
  local stopKey=S.bindingsValid and S.managedSpells.current(stop) and S.compactBindingCode(stop.key) or 0
  packet=packet..S.bytes(food or 65535,2)..S.bytes(water or 65535,2)..S.bytes(stopKey,2)..S.bytes(bridge.auraRevision or 0,4)
  local sum=S.adler32(packet);for i,dot in ipairs(bridge.stamp) do local v=math.floor(sum/256^(i-1))%256/255;dot:SetColorTexture(v,v,v,1) end
  S.publishTransportPacket(ns.wire.ids.magePreview,packet..S.bytes(sum,4))
 end
 bridge.panel:SetScript("OnUpdate",function(_,dt) elapsed=elapsed+dt;if elapsed<S.updateInterval() then return end;elapsed=0;local ok,err=pcall(render);H.lastError=not ok and S.describe(err) or nil;if not ok then S.publishTransportPacket(ns.wire.ids.magePreview,nil) end end)
 S.profileScript(bridge.panel,"OnUpdate","Mage bridge")
end
