-- Warlock leveling catalog and WLS1 class packet. No rotation or input here.
local _,ns=...
local H={denseBridgeLayout={key="warlock-dense-v1",height=232,gauges=168,units=168,unitHeight=28,activity=14,headerActivity=true,resources=168,setup=196,grid=196,roster=196,coreStamp=108,targetStamp=122,marker={.5,.25,1}}}
ns.classes.WARLOCK=H
H.specs={
 {key="warlock.agony",name="Bane of Agony",petAttack=true,aura="target"},
 {key="warlock.corruption",name="Corruption",petAttack=true,aura="target"},
 {key="warlock.immolate",name="Immolate",petAttack=true,aura="target"},
 {key="warlock.shadowBolt",name="Shadow Bolt",petAttack=true,aura="player",auraName="Shadow Trance"},
 {key="warlock.searingPain",name="Searing Pain",petAttack=true,aura="target",auraName="Demonic Brand"},
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
 {key="warlock.createHealthstone",name="Create Healthstone",unit="player"}
}
function H.initializePreview()
 local S=ns.state;local G=ns.features.GroupContext
 if G.text(G.read(UnitClass,2,"player"),16)~="WARLOCK" then return end
 local B=ns.features.SpellBridge;local bridge=B.create(S.hud,H.specs);H.bridge=bridge;S.warlockNativePanel=bridge.panel
 local combatDot=bridge.panel:CreateTexture(nil,"OVERLAY");combatDot:SetSize(4,4);combatDot:SetPoint("TOPLEFT",220,-122)
 local function count(id)
  local api=type(C_Item)=="table" and C_Item.GetItemCount or GetItemCount
  local value=G.read(api,1,id,false,false)
  return value.status=="observed" and type(value.value)=="number" and value.value>=0 and value.value<65535 and value.value==math.floor(value.value) and value.value or 65535
 end
 local tick,elapsed=0,0
 local function render()
  if not S.executionBytes then return end
  local F=ns.features.Healing;F.spellStatus={};tick=(tick+1)%4294967296
  local level=S.readableCall(UnitLevel,"player");if type(level)~="number" or level<1 or level>100 then error("Level unavailable") end
  local readings={}
  for i,spec in ipairs(H.specs) do local r=F.spell(spec,spec.unit or "target");readings[i]=r;B.render(bridge,i,r.id,r.learned.status=="observed" and r.learned.value or nil,spec) end
  B.auras(bridge,H.specs,readings)
  local packet="WLS1"..S.bytes(S.setupSession,4)..S.bytes(tick,4)..S.bytes(level,1)..S.bytes(S.updateRateMs,2)..S.bytes(S.auraGeneration,1)..S.bytes(#H.specs,1)..S.bytes(S.bindingsValid and 2 or 0,1)
  for i,spec in ipairs(H.specs) do
   local r=readings[i];local entry=S.managedSpells and S.managedSpells.entries["WARLOCK:"..spec.name]
   local key=S.bindingsValid and S.managedSpells.current(entry) and S.compactBindingCode(entry.key) or 0
   local ready=r.ready
   local flags=0;for j,value in ipairs({r.learned,r.usable,r.mana,r.range,ready,r.aura or {}}) do flags=flags+G.code(value)*4^(j-1) end
   local info=S.readableCall(S.spellAPI.GetSpellInfo,r.id);local ms=S.safeField(info,"castTime");if type(ms)~="number" or ms<0 or ms>10000 then ms=65535 end
   local absent=bridge.absence and bridge.absence[i] and GetTime()>=(bridge.settledAt or math.huge)
   packet=packet..S.bytes(r.id,4)..S.bytes(key,2)..S.bytes(flags,2)..S.bytes(S.spellUseCode(spec.key)+(absent and 4 or 0),1)..S.bytes(ms,2)
  end
  local combat=G.read(UnitAffectingCombat,1,"player")
  combatDot:SetColorTexture(1,1,1,1)
  local painted,result=pcall(ns.features.RangeTracking.paintBoolean,combatDot,UnitAffectingCombat("player"),{0,1,0,1},{.2,.2,.2,1})
  if not painted or result~=true then combatDot:SetVertexColor(1,1,1,1);combatDot:SetColorTexture(1,.65,0,1) end
  local wand=G.read(IsAutoRepeatSpell,1,"Shoot")
  local stones=0
  for _,id in ipairs(ns.features.Consumables.ids) do local n=count(id);if n==65535 then stones=65535;break end;stones=math.min(65534,stones+n) end
  packet=packet..S.executionBytes(2)..S.bytes(G.code(combat),1)..S.bytes(count(6265),2)..S.bytes(G.code(wand),1)..S.bytes(stones,2)
  local sum=S.adler32(packet);for i,dot in ipairs(bridge.stamp) do local v=math.floor(sum/256^(i-1))%256/255;dot:SetColorTexture(v,v,v,1) end
  S.publishTransportPacket(11,packet..S.bytes(sum,4))
 end
 bridge.panel:SetScript("OnUpdate",function(self,dt) elapsed=elapsed+dt;if elapsed<S.updateInterval() then return end;elapsed=0;local ok,err=pcall(render);H.lastError=not ok and S.describe(err) or nil;if not ok then S.publishTransportPacket(11,nil) end end)
 S.profileScript(bridge.panel,"OnUpdate","Warlock bridge")
end
