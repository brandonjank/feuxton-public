-- Adaptive Shaman catalog and SHS1 class packet. No rotation or input here.
local _,ns=...
local H={denseBridgeLayout={key="shaman-dense-v1",height=232,gauges=168,units=168,unitHeight=28,activity=14,headerActivity=true,resources=168,setup=196,grid=196,roster=196,coreStamp=108,targetStamp=122,marker={.25,.5,1}}}
ns.classes.SHAMAN=H
H.specs={
 {key="shaman.lightningBolt",name="Lightning Bolt"},{key="shaman.chainLightning",name="Chain Lightning"},
 {key="shaman.earthShock",name="Earth Shock"},{key="shaman.flameShock",name="Flame Shock",aura="target"},{key="shaman.frostShock",name="Frost Shock"},
 {key="shaman.stormstrike",name="Stormstrike",startAttack=true},{key="shaman.fireNova",name="Fire Nova",unit="player"},
 {key="shaman.lightningShield",name="Lightning Shield",unit="player",aura="player"},{key="shaman.waterShield",name="Water Shield",unit="player",aura="player"},
 {key="shaman.rockbiter",name="Rockbiter Weapon",unit="player"},{key="shaman.flametongue",name="Flametongue Weapon",unit="player"},{key="shaman.windfuryWeapon",name="Windfury Weapon",unit="player"},
 {key="shaman.healingWave",name="Healing Wave",healing=true,unit="player"},{key="shaman.lesserHealingWave",name="Lesser Healing Wave",healing=true,unit="player"},{key="shaman.riptide",name="Riptide",healing=true,unit="player"},
 {key="shaman.naturesSwiftness",name="Nature's Swiftness",unit="player",aura="player"},{key="shaman.manaTide",name="Mana Tide Totem",element=3,unit="player"},
 {key="shaman.searing",name="Searing Totem",element=1,unit="player"},{key="shaman.magma",name="Magma Totem",element=1,unit="player"},
 {key="shaman.strengthEarth",name="Strength of Earth Totem",element=2,unit="player"},{key="shaman.stoneskin",name="Stoneskin Totem",element=2,unit="player"},
 {key="shaman.manaSpring",name="Mana Spring Totem",element=3,unit="player"},{key="shaman.healingStream",name="Healing Stream Totem",element=3,unit="player"},
 {key="shaman.windfuryTotem",name="Windfury Totem",element=4,unit="player"},{key="shaman.graceAir",name="Grace of Air Totem",element=4,unit="player"},
 {key="shaman.tremor",name="Tremor Totem",element=2,unit="player"},{key="shaman.grounding",name="Grounding Totem",element=4,unit="player"},{key="shaman.earthbind",name="Earthbind Totem",element=2,unit="player"},
 {key="shaman.chainHeal",name="Chain Heal",healing=true,unit="player"},{key="shaman.autoAttack",name="Attack",startAttack=true},{key="shaman.earthShockInterrupt",name="Earth Shock"}
}
function H.initializePreview()
 local S=ns.state;local G=ns.features.GroupContext
 if G.text(G.read(UnitClass,2,"player"),16)~="SHAMAN" then return end
 local B=ns.features.SpellBridge;local bridge=B.create(S.hud,H.specs);H.bridge=bridge;S.shamanNativePanel=bridge.panel
 ns.features.Totems.initialize(S.hud)
 local tick,elapsed=0,0
 local function render()
  if not S.executionBytes then return end
  local F=ns.features.Healing;F.spellStatus={};tick=(tick+1)%4294967296
  local level=S.readableCall(UnitLevel,"player");if type(level)~="number" or level<1 or level>100 then error("Level unavailable") end
  local readings={}
  for i,spec in ipairs(H.specs) do local r=F.spell(spec,spec.unit or "target");readings[i]=r;B.render(bridge,i,r.id,r.learned.status=="observed" and r.learned.value or nil,spec) end
  B.auras(bridge,H.specs,readings)
  local packet="SHS1"..S.bytes(S.setupSession,4)..S.bytes(tick,4)..S.bytes(level,1)..S.bytes(S.updateRateMs,2)..S.bytes(S.auraGeneration,1)..S.bytes(#H.specs,1)..S.bytes(S.bindingsValid and 2 or 0,1)
  for i,spec in ipairs(H.specs) do
   local r=readings[i];local entry=S.managedSpells and S.managedSpells.entries["SHAMAN:"..spec.name]
   local key=S.bindingsValid and S.managedSpells.current(entry) and S.compactBindingCode(entry.key) or 0
   local ready=r.ready
   if spec.key=="shaman.autoAttack" then r.learned={status="observed",value=r.id==6603};r.usable={status="observed",value=true};r.mana={status="observed",value=false};ready={status="observed",value=true} end
   local flags=0;for j,value in ipairs({r.learned,r.usable,r.mana,r.range,ready,r.aura or {}}) do flags=flags+G.code(value)*4^(j-1) end
   local info=S.readableCall(S.spellAPI.GetSpellInfo,r.id);local ms=S.safeField(info,"castTime");if type(ms)~="number" or ms<0 or ms>10000 then ms=0 end
   local absent=bridge.absence and bridge.absence[i] and GetTime()>=(bridge.settledAt or math.huge)
   packet=packet..S.bytes(r.id,4)..S.bytes(key,2)..S.bytes(flags,2)..S.bytes(S.spellUseCode(spec.key)+(absent and 4 or 0),1)..S.bytes(ms,2)
  end
  local inside,kind=G.read(IsInInstance,1),G.read(IsInInstance,2);local dungeon={}
  if inside.status=="observed" and type(inside.value)=="boolean" then if not inside.value then dungeon={status="observed",value=false} elseif kind.status=="observed" and type(kind.value)=="string" then dungeon={status="observed",value=kind.value=="party"} end end
  local main,off={},{};local ok,a,b,c,d,e=pcall(GetWeaponEnchantInfo)
  if ok and not S.isSecret(a) and type(a)=="boolean" then main={status="observed",value=a} end
  if ok and not S.isSecret(e) and type(e)=="boolean" then off={status="observed",value=e} end
  local stop=S.managedSpells and S.managedSpells.entries["SHAMAN:Feuxton Stop Casting"]
  local stopKey=S.bindingsValid and S.managedSpells.current(stop) and S.compactBindingCode(stop.key) or 0
  local combat=G.read(UnitAffectingCombat,1,"player")
  local combatDot=ns.features.Totems.combat;combatDot:SetColorTexture(1,1,1,1)
  local painted,result=pcall(ns.features.RangeTracking.paintBoolean,combatDot,UnitAffectingCombat("player"),{0,1,0,1},{.2,.2,.2,1})
  if not painted or result~=true then combatDot:SetVertexColor(1,1,1,1);combatDot:SetColorTexture(1,.65,0,1) end
  packet=packet..S.executionBytes(2)..S.bytes(G.code(dungeon),1)..S.bytes(G.code(combat),1)..ns.features.Totems.observe(H.specs)..S.bytes(G.code(main),1)..S.bytes(G.code(off),1)..S.bytes(stopKey,2)
  local sum=S.adler32(packet);for i,dot in ipairs(bridge.stamp) do local v=math.floor(sum/256^(i-1))%256/255;dot:SetColorTexture(v,v,v,1) end
  S.publishTransportPacket(6,packet..S.bytes(sum,4))
 end
 bridge.panel:SetScript("OnUpdate",function(self,dt) elapsed=elapsed+dt;if elapsed<S.updateInterval() then return end;elapsed=0;local ok,err=pcall(render);H.lastError=not ok and S.describe(err) or nil;if not ok then S.publishTransportPacket(6,nil) end end)
 S.profileScript(bridge.panel,"OnUpdate","Shaman bridge")
end
