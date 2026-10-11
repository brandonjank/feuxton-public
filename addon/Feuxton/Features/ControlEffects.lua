-- HHX2: atomic shared control effects, racial spells and Freedom recipients.
-- All secret fields remain unknown; native cooldown/usability stays rendered.
local _,ns=...
local X={cache={}}
ns.features.ControlEffects=X
X.freedom={key="paladin.freedom",name="Blessing of Freedom",support=true}
local movementNames={['Frostbolt']=true,['Frost Shock']=true,['Hamstring']=true,['Wing Clip']=true,['Concussive Shot']=true,['Crippling Poison']=true,['Entangling Roots']=true,['Frost Nova']=true,['Frost Trap Aura']=true,['Ensnare']=true,['Net']=true,['Web']=true,['Tendon Rip']=true}
local function flag(v)return v==true and 2 or v==false and 1 or 0 end
local function value(fn,...)return ns.state.readableCall(fn,...) end
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
 if type(now)=="number" then X.probeCache={id,reach};X.probeAt=now end
 return id,reach
end
function X.engaged(unit)
 local threat=value(UnitThreatSituation,"player",unit)
 if type(threat)=="number" and threat>=0 and threat<=3 then return true end
 for _,friend in ipairs({"player","pet","party1","party2","party3","party4"}) do if value(UnitIsUnit,unit.."target",friend)==true then return true end end
 return nil -- another fight or unavailable threat/target data is not our pack
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
    local ok,result=pcall(S.spellAPI.IsSpellInRange,id,unit);if ok then range=result end
   end
  end
  packed=packed+(S.isSecret(range) and 0 or flag(range))*4^((i-1)%4)
  if i%4==0 then near=near..S.bytes(packed,1);packed=0 end
  local dot=X.nearbyDots and X.nearbyDots[i]
  if dot then
   dot:SetColorTexture(1,1,1,1)
   local ok,painted=pcall(ns.features.RangeTracking.paintBoolean,dot,range,{0,1,0,1},{1,0,0,1})
   if not ok or painted~=true then dot:SetVertexColor(1,1,1,1);dot:SetColorTexture(1,.65,0,1) end
  end
 end
 local info=value(S.spellAPI.GetSpellInfo,"Consecration");local costID=S.safeField(info,"spellID");local cost=255
 if type(costID)~="number" or value(S.bookAPI.IsSpellKnown or IsSpellKnown,costID)~=true then costID=0
 else cost=ns.features.CastTracking.manaFraction(costID,true) end
 return S.bytes(id,4)..S.bytes(reach,1)..S.bytes(costID,4)..S.bytes(cost,1)..near
end
function X.effects(unit)
 local S=ns.state;local G=ns.features.GroupContext;local result={};local complete=false
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
   if type(kind)~="string" then complete=false
   elseif kind=="ROOT" or kind=="SNARE" then result.movement=true
   elseif kind=="CHARM" or kind=="FEAR" or kind=="FEAR_MECHANIC" or kind=="SLEEP" then result.forsaken=true
   elseif kind=="STUN" or kind=="STUN_MECHANIC" then result.stun=true end
  end
 end
 if complete then result.forsaken=result.forsaken or false;result.stun=result.stun or false end
 local auraAPI=type(C_UnitAuras)=="table" and C_UnitAuras or {};local scanned=false;local unclassified=false;local classified=true
 for i=1,80 do
  if type(auraAPI.GetAuraDataByIndex)~="function" then break end
  local ok,aura=pcall(auraAPI.GetAuraDataByIndex,unit,i,"HARMFUL")
  if not ok or S.isSecret(aura) then break end
  if aura==nil then scanned=true;break end
  local name=S.safeField(aura,"name");local dispel=S.safeField(aura,"dispelName")
  if type(name)~="string" or S.isSecret(aura.dispelName) then classified=false end
  local impairment=S.safeField(aura,"isMovementImpairing")
  if movementNames[name] or impairment==true then result.movement=true elseif impairment~=false then unclassified=true end
  if name=="Sleep" or name=="Deep Sleep" or name=="Charm" or name=="Mind Control" then result.forsaken=true end
  if dispel=="Curse" then result.curse=true end
  if dispel=="Poison" or dispel=="Disease" or dispel=="Bleed" then result.stoneform=true end
 end
 if scanned and classified then result.curse=result.curse or false;result.stoneform=result.stoneform or false end
 -- LoC commonly omits slows. Never certify their absence from an empty LoC list.
 if scanned and complete and not unclassified then result.movement=result.movement or false end
 return result
end
local racialAuras={["Skysight"]="Elemental Blessing",["Read Ley Line"]="Energized"}
local function active(name,unit)
 local S=ns.state;local api=type(C_UnitAuras)=="table" and C_UnitAuras or {}
 if type(api.GetAuraDataByIndex)~="function" then return nil end
 for i=1,80 do
  local ok,a=pcall(api.GetAuraDataByIndex,unit or "player",i,"HELPFUL")
  if not ok or S.isSecret(a) then return nil end
  if a==nil then return false end
  local n=S.safeField(a,"name");if type(n)~="string" then return nil end
  if n==name or n==racialAuras[name] then return true end
 end
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
 for i=1,40 do local p=S.hud:CreateTexture(nil,"OVERLAY");p:SetSize(2,2);p:SetPoint("TOPLEFT",580+(i-1)*2,-2);X.nearbyDots[i]=p end
 for i=1,4 do
  local x=350+(i-1)*38;local tile={}
  tile.dial=S.hud:CreateTexture(nil,"BACKGROUND");tile.dial:SetSize(12,12);tile.dial:SetPoint("TOPLEFT",x,-1)
  tile.cooldown=CreateFrame("Cooldown",nil,S.hud,"CooldownFrameTemplate");tile.cooldown:SetAllPoints(tile.dial);tile.cooldown:SetDrawEdge(false);tile.cooldown:SetDrawSwipe(true);tile.cooldown:SetSwipeColor(0,0,0,1);tile.cooldown:SetHideCountdownNumbers(true)
  tile.signals={}
  for j=1,4 do local dot=S.hud:CreateTexture(nil,"OVERLAY");dot:SetSize(4,4);dot:SetPoint("TOPLEFT",x+14+(j-1)%2*5,-1-math.floor((j-1)/2)*5);tile.signals[j]=dot end
  X.tiles[i]=tile
 end
 for i=1,5 do local p=S.hud:CreateTexture(nil,"OVERLAY");p:SetSize(4,4);p:SetPoint("TOPLEFT",510+(i-1)*6,-2);X.ranges[i]=p end
 for i=1,4 do local p=S.hud:CreateTexture(nil,"OVERLAY");p:SetSize(4,4);p:SetPoint("TOPLEFT",550+(i-1)*6,-2);X.stamp[i]=p end
end
function X.packet(tick)
 local S=ns.state;local G=ns.features.GroupContext;local F=ns.features.Healing
 X.native()
 local class=value(function()local _,c=UnitClass("player");return c end)
 local race=value(function()local _,r=UnitRace("player");return r end) or ""
 if #race>32 then race="" end
 local roster=S.transportPackets[16];local rosterTick=roster and string.byte(roster.packet,9) and 0 or nil
 if roster then for i=0,3 do rosterTick=rosterTick+string.byte(roster.packet,9+i)*256^i end end
 local revision=F.revision or 0
 local packet="HHX2"..S.bytes(S.setupSession,4)..S.bytes(tick,4)..S.bytes(rosterTick or 0,4)..S.bytes(revision,4)..S.bytes(#race,1)..race
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
  if spec.name=="Find Treasure" then presence=X.tracking() else presence=active(spec.name) end
  local sf=G.code(spell.usable)+G.code(spell.mana)*4+G.code(spell.ready)*16+flag(presence)*64
  local range=G.read(S.spellAPI.IsSpellInRange,1,spec.id,"target")
  sf=sf+G.code(range)*256
  packet=packet..S.bytes(spec.index,1)..S.bytes(spec.id,4)..S.bytes(code,2)..S.bytes(sf,2)..S.bytes(S.spellUseCode(spec.key),1)
  if i<=3 and X.tiles then local tile=X.tiles[i];tile.spellID=spec.id;S.renderCooldown(tile);ns.features.RangeTracking.render(tile.signals,spec.id,"player");if tile.useKey~=spec.key then S.attachSpellUse(S.hud,tile.dial,spec.key);tile.useKey=spec.key end end
 end
 local freedom=class=="PALADIN" and F.spell(X.freedom,"player") or {id=0}
 local entry=class=="PALADIN" and F.delivery(X.freedom) or nil
 packet=packet..S.bytes(freedom.id or 0,4)..S.bytes(entry and S.compactBindingCode(entry.key) or 0,2)..S.bytes(S.spellUseCode(X.freedom.key),1)
 if X.tiles then local tile=X.tiles[4];tile.spellID=(freedom.id or 0)>0 and freedom.id or nil;S.renderCooldown(tile);ns.features.RangeTracking.render(tile.signals,freedom.id or 0,"player");if class=="PALADIN" and (freedom.id or 0)>0 and not tile.useKey then S.attachSpellUse(S.hud,tile.dial,X.freedom.key);tile.useKey=X.freedom.key end end
 for index,unit in ipairs({"player","party1","party2","party3","party4"}) do
  local identity=G.text(G.read(UnitGUID,1,unit),40);local effects=X.effects(unit);local ef=0
  for i,key in ipairs({"movement","forsaken","stun","curse","stoneform"}) do ef=ef+flag(effects[key])*4^(i-1) end
  local spell=class=="PALADIN" and F.spell(X.freedom,unit) or {id=0};local sf=G.code(spell.learned)+G.code(spell.usable)*4+G.code(spell.mana)*16+G.code(spell.ready)*64+G.code(spell.range)*256
  local presence
  if class=="PALADIN" then presence=active(X.freedom.name,unit) end
  packet=packet..S.bytes(#identity,1)..identity..S.bytes(ef,2)..S.bytes(sf,2)..S.bytes(flag(presence),1)
  if X.ranges and (freedom.id or 0)>0 then
   local ok,r=pcall(S.spellAPI.IsSpellInRange,freedom.id,unit)
   if not ok then r=nil end
   local painted,result=pcall(ns.features.RangeTracking.paintBoolean,X.ranges[index],r,{0,1,0,1},{1,0,0,1})
   if not painted or result~=true then X.ranges[index]:SetVertexColor(1,1,1,1);X.ranges[index]:SetColorTexture(1,.65,0,1) end
  end
 end
 packet=packet..X.nearby()
 local checksum=S.adler32(packet)
 for i,p in ipairs(X.stamp or {}) do local c=math.floor(checksum/256^(i-1))%256/255;p:SetColorTexture(c,c,c,1) end
 return packet..S.bytes(checksum,4)
end
local events=CreateFrame("Frame")
events:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED");events:RegisterEvent("UNIT_SPELLCAST_FAILED");events:RegisterEvent("LOOT_CLOSED");events:RegisterEvent("SPELLS_CHANGED");events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent",function(_,event,unit,cast,id)
 if event=="SPELLS_CHANGED" or event=="PLAYER_ENTERING_WORLD" then X.probeCache=nil;return end
 if event=="LOOT_CLOSED" then X.herbAt=nil;return end
 local S=ns.state;if S.isSecret(unit) or unit~="player" or S.isSecret(id) then return end
 local name=value(S.spellAPI.GetSpellName,id)
 if name=="Cultivation" then X.herbAt=nil
 elseif event=="UNIT_SPELLCAST_SUCCEEDED" and (name=="Herb Gathering" or name=="Herbalism") then X.herbAt=value(GetTime) end
end)
