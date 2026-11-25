-- Paladin catalog, capability probe and class observation transport.
local _, ns = ...
local paladin={}
ns.classes.PALADIN=paladin
paladin.denseBridgeLayout={key="paladin-slim-v1",gauges=68,native=28,units=68,unitHeight=20,activity=14,headerActivity=true,resources=68,setup=88,grid=88,roster=88,coreStamp=108,targetStamp=122,marker={1,0.25,0.5}}
paladin.specs=ns.spellCatalog.PALADIN.specs
local buildOK,_,buildID,_,interface=pcall(GetBuildInfo)
local clientBuild=buildOK and interface==16001 and tonumber(buildID)
-- The launch rules replaced the self reset with a targeted Seal attack.
local swiftUnleashesSeal=type(clientBuild)=="number" and clientBuild>=70938
local holyShieldRanks={[20925]=true,[20927]=true,[20928]=true}
local wisdomRanks={[20166]=true,[20356]=true,[20357]=true}
local utilitySpellIDs={sealWisdom=wisdomRanks,templarsBulwark={[1311015]=true}}
local targetClassifications={normal=1,elite=2,rareelite=3,rare=4,worldboss=5,trivial=6,minus=7}
local previewSpecs={}
-- Stop melee swings before selected-target incapacitation; recovery owns any follow-up.
for _,spec in ipairs(paladin.specs) do
    previewSpecs[spec.key:sub(9)]=spec
    if spec.key=="paladin.repentance" then spec.stopAttack=true end
    if spec.key=="paladin.swiftJudgement" and swiftUnleashesSeal then spec.unit="target" end
end
function paladin.capture()
    local group=ns.features.GroupContext
    local S=ns.state
    -- Explicit diagnostic collection only. Existing scans preserve bars/macros/keys.
    local combat=group.read(InCombatLockdown,1)
    if combat.status=="observed" and combat.value==false and type(S.discoverBindings)=="function" then S.discoverBindings() end
    local api=type(C_Spell)=="table" and C_Spell or {}
    local book=type(C_SpellBook)=="table" and C_SpellBook or {}
    local snapshot={class=group.read(UnitClass,2,"player"),level=group.read(UnitLevel,1,"player"),combat=group.read(InCombatLockdown,1),mainHandAttackSpeed=group.read(UnitAttackSpeed,1,"player"),mainHandItem=group.read(GetInventoryItemID,1,"player",16),shieldItem=group.read(GetInventoryItemID,1,"player",17),spells={}}
    local heals={}
    for _,spec in ipairs(paladin.specs) do
        local ok,info=false,nil
        if type(api.GetSpellInfo)=="function" then ok,info=pcall(api.GetSpellInfo,spec.name) end
        local id=ok and group.field(info,"spellID") or {status="error"}
        local spell={key=spec.key,name=spec.name,id=id,castTimeMs=group.field(info,"castTime"),minimumRange=group.field(info,"minRange"),maximumRange=group.field(info,"maxRange"),learned={status="unknown"},usable={status="unknown"},insufficientPower={status="unknown"},targetRange={status="unknown"}}
        if id.status=="observed" and type(id.value)=="number" then
            spell.learned=group.read(book.IsSpellKnown or IsSpellKnown,1,id.value)
            spell.usable,spell.insufficientPower=ns.features.RangeTracking.readUsability(api.IsSpellUsable or IsUsableSpell,id.value)
            spell.targetRange=ns.features.RangeTracking.readRange(api.IsSpellInRange or IsSpellInRange,api.IsSpellInRange and id.value or spec.name,"target")
        end
        spell.bindings={}
        for _,mapping in ipairs(S.setupMappings or {}) do
            local mappedID,mappedName=group.field(mapping,"id"),group.field(mapping,"name")
            if (id.status=="observed" and mappedID.status=="observed" and mappedID.value==id.value) or (mappedName.status=="observed" and mappedName.value==spec.name) then
                spell.bindings[#spell.bindings+1]={id=mappedID,slot=group.field(mapping,"slot"),key=group.field(mapping,"key"),key2=group.field(mapping,"key2"),kind=group.field(mapping,"kind"),action=group.field(mapping,"action")}
            end
        end
        spell.bindingScan=group.read(function() return S.bindingsValid end,1)
        spell.bindingScanCombat=combat
        snapshot.spells[#snapshot.spells+1]=spell
        if spec.healing then heals[#heals+1]=spell end
    end
    snapshot.party=group.capture(heals)
    return snapshot
end
local function signal(value)
    return value and value.status=="observed" and tostring(value.value) or value and value.status or "unknown"
end
function paladin.report()
    local snapshot=paladin.capture()
    local lines={"Feuxton Paladin/party capability probe", "Class: "..signal(snapshot.class).." | Level: "..signal(snapshot.level).." | Combat: "..signal(snapshot.combat),"Main-hand attack speed (may include haste): "..signal(snapshot.mainHandAttackSpeed),"Main-hand item: "..signal(snapshot.mainHandItem).." | Offhand item: "..signal(snapshot.shieldItem)}
    lines[#lines+1]="Preview error: "..(paladin.lastPreviewError or "none").." | Cached base delay ms: "..(paladin.weaponDelayMs or 0).." | Native absence: awaiting live rank-family validation"
    for _,spell in ipairs(snapshot.spells) do
        lines[#lines+1]=spell.name..": ID="..signal(spell.id).." | Learned="..signal(spell.learned).." | Cast ms="..signal(spell.castTimeMs).." | Range="..signal(spell.minimumRange).."-"..signal(spell.maximumRange).." | Usable="..signal(spell.usable).." | Mana shortage="..signal(spell.insufficientPower).." | Enemy range="..signal(spell.targetRange)
        lines[#lines+1]="  Binding scan="..signal(spell.bindingScan).." | Collected in combat="..signal(spell.bindingScanCombat).." | Mappings="..#spell.bindings
        for _,binding in ipairs(spell.bindings) do lines[#lines+1]="  Binding: "..signal(binding.key).." / "..signal(binding.key2).." | Bound ID="..signal(binding.id).." | Slot="..signal(binding.slot).." | Kind="..signal(binding.kind).." | Action="..signal(binding.action) end
    end
    lines[#lines+1]="Party: "..signal(snapshot.party.groupCount).." | Raid: "..signal(snapshot.party.inRaid)
    for _,member in ipairs(snapshot.party.members) do
        lines[#lines+1]=member.unit..": Exists="..signal(member.exists).." | Name="..signal(member.name).." | Identity="..signal(member.identity).." | Class="..signal(member.class)
        lines[#lines+1]="  Is self="..signal(member.isPlayer).." | Is focus="..signal(member.isFocus).." | Main tank assignment="..signal(member.mainTank)
        lines[#lines+1]="  Dead="..signal(member.dead).." | Connected="..signal(member.connected).." | Visible="..signal(member.visible).." | Assistable="..signal(member.assistable).." | Combat="..signal(member.combat).." | Role="..signal(member.role)
        lines[#lines+1]="  Health="..signal(member.health).." / "..signal(member.maximumHealth).." | Fraction="..signal(member.healthFraction)
        for _,key in ipairs({"paladin.holyLight","paladin.flashLight"}) do lines[#lines+1]="  "..key.." range to this member="..signal(member.ranges[key]) end
        for index,aura in ipairs(member.auras) do lines[#lines+1]="  Aura "..index..": "..(aura.status or "ID="..signal(aura.spellID).." Name="..signal(aura.name)) end
    end
    lines[#lines+1]="Restricted health/aura data requires native HUD widgets; it is never treated as absent or zero. This command sends no gameplay keys."
    return table.concat(lines,"\n")
end
if type(SlashCmdList)=="table" then
SLASH_FEUXTONPALADIN1="/feuxtonpaladinprobe"
SlashCmdList.FEUXTONPALADIN=function()
    local ok,text=pcall(paladin.report)
    if not ok then print("Feuxton: Paladin/party probe failed.");return end
    if type(FeuxtonDB)~="table" then FeuxtonDB={} end
    FeuxtonDB.paladinPartyReport=text
    FeuxtonDB.paladinPartyReportAt=type(GetServerTime)=="function" and ns.features.GroupContext.read(GetServerTime,1) or nil
    FeuxtonDB.paladinPartyReportVersion=2
    local S=ns.state
    if not S.panel or not S.edit then print("Feuxton: diagnostic window not ready.");return end
    S.edit:SetText(text);S.panel:Show();S.edit:SetFocus();S.edit:HighlightText()
end
end


-- HHP5 observation stream. The desktop owns foreground-only input; Lua sends no casts.
paladin.previewKeys={};paladin.packetKeys={}
for i,key in ipairs(ns.spellCatalog.PALADIN.previewKeys) do paladin.previewKeys[i]=key:match("%.(.+)") end
for i,key in ipairs(ns.spellCatalog.PALADIN.packetKeys) do paladin.packetKeys[i]=key:match("%.(.+)") end
local protectionKeys={unpack(paladin.packetKeys)}
for _,key in ipairs(ns.spellCatalog.PALADIN.protectionKeys) do protectionKeys[#protectionKeys+1]=key:match("%.(.+)") end
local retKeys={unpack(paladin.packetKeys)}
retKeys[#retKeys+1]="hammerWrath"
local ordinaryKeys={unpack(paladin.packetKeys)}
local utilitySlots={}
for index,key in ipairs(ns.spellCatalog.PALADIN.utilityKeys) do
    local short=key:match("%.(.+)")
    utilitySlots[short]=index
    for _,keys in ipairs({ordinaryKeys,retKeys,protectionKeys}) do keys[#keys+1]=short end
end
for _,keys in ipairs({ordinaryKeys,retKeys,protectionKeys}) do keys[#keys+1]="divineShield" end
local baseSlots=#paladin.packetKeys
paladin.bindingCode=ns.state.compactBindingCode
-- Restricted remaining time goes directly through the native color API. Lua
-- never compares or serializes it. Orange means no supported rendering path.
function paladin.renderHealWindows(readings,healMs,S)
    for i=1,2 do
        local tile=paladin.nativeTiles[i];local pixel=tile.healWindow
        if not pixel then pixel=S.paladinNativePanel:CreateTexture(nil,"OVERLAY");pixel:SetSize(4,4);pixel:SetPoint("TOPLEFT",12+(i-1)*46+30,-32);tile.healWindow=pixel end
        pixel:SetColorTexture(1,.65,0,1)
        if healMs>0 then pcall(function()
            -- Fixed user policy: both damage cooldowns must have at least
            -- 2.5 seconds remaining, independent of update rate/cast rank.
            local threshold=2.5
            if tile.windowThreshold~=threshold then
                local curve=C_CurveUtil.CreateColorCurve();curve:SetType(Enum.LuaCurveType.Step)
                curve:AddPoint(0,CreateColor(1,0,0,1));curve:AddPoint(threshold,CreateColor(0,1,0,1))
                tile.windowCurve=curve;tile.windowThreshold=threshold
            end
            local duration=C_Spell.GetSpellCooldownDuration(readings[i].bound,true)
            local color=duration:EvaluateRemainingDuration(tile.windowCurve)
            pixel:SetColorTexture(color:GetRGBA())
        end) end
    end
end
local auraSlots={[3]=true,[4]=true,[5]=true,[7]=true,[10]=true,[11]=true,[12]=true,[14]=true,[17]=true}

-- Static weapon tooltip speed is the base delay. UnitAttackSpeed includes haste.
-- Missing, secret, localized or conflicting tooltip lines remain unknown.
function paladin.refreshWeapon()
    paladin.weaponID,paladin.weaponDelayMs=0,0
    local S=ns.state;local group=ns.features.GroupContext
    if S.readableCall(InCombatLockdown)~=false then return end
    local item=group.read(GetInventoryItemID,1,"player",16)
    if item.status~="observed" or type(item.value)~="number" or item.value<=0 or item.value>=2147483648 or item.value~=math.floor(item.value) then return end
    paladin.weaponID=item.value
    local api=type(C_TooltipInfo)=="table" and C_TooltipInfo or {}
    local ok,data=pcall(api.GetInventoryItem or function() end,"player",16)
    if not ok or S.isSecret(data) or type(data)~="table" then return end
    local lines;ok,lines=pcall(function() return data.lines end)
    if not ok or S.isSecret(lines) or type(lines)~="table" then return end
    local found
    for i=1,80 do
        local line;ok,line=pcall(function() return lines[i] end)
        if not ok or S.isSecret(line) then return end
        if line==nil then break end
        local text=group.text(group.field(line,"rightText"),100)
        local speed=tonumber(text:match("^%s*Speed%s+(%d+%.?%d*)%s*$"))
        if speed then
            local ms=math.floor(speed*1000+0.5)
            if ms<500 or ms>10000 or (found and found~=ms) then return end
            found=ms
        end
    end
    paladin.weaponDelayMs=found or 0
end

-- PLAYER_SWING is a native clock anchor, not proof that damage landed or that
-- a seal was consumed. Preserve that distinction in the read-only transport.
local function publicNumber(S,value,minimum,maximum)
    return not S.isSecret(value) and type(value)=="number" and value==value and value>=minimum and value<=maximum
end

-- Bulwark is an absorb, so aura presence alone cannot postpone a real heal.
-- Publish positive recovery proof only for the exact aura's readable capacity
-- and lifetime. Restricted or unavailable values leave the LoH fallback open.
function paladin.bulwarkRecoveryProof(S,group,spellID)
    local api=type(C_UnitAuras)=="table" and C_UnitAuras or {}
    if type(api.GetPlayerAuraBySpellID)~="function" or not publicNumber(S,spellID,1,2147483647) then return false end
    local ok,aura=pcall(api.GetPlayerAuraBySpellID,spellID)
    if not ok or S.isSecret(aura) or type(aura)~="table" then return false end
    local id=group.field(aura,"spellId")
    local expires=group.field(aura,"expirationTime")
    local now=S.readableCall(GetTime)
    if id.value~=spellID or not publicNumber(S,now,0,math.huge) or now==math.huge
        or not publicNumber(S,expires.value,now+3,now+60) then return false end
    local pointsOK,points=pcall(function() return aura.points end)
    if not pointsOK or S.isSecret(points) or type(points)~="table" then return false end
    local absorbOK,absorb=pcall(function() return points[1] end)
    local maximum=group.read(UnitHealthMax,1,"player")
    return absorbOK and publicNumber(S,maximum.value,1,2147483647)
        and publicNumber(S,absorb,maximum.value/4,2147483647)
end

function paladin.resetSwingClock()
    local previous=paladin.swingClock
    paladin.swingClock={sequence=previous and previous.sequence or 0}
end
function paladin.observeSwingClock(duration,hand)
    local S=ns.state;local group=ns.features.GroupContext
    if not publicNumber(S,hand,0,2) or hand~=math.floor(hand) then paladin.resetSwingClock();return end
    if hand~=0 then return end
    local previous=paladin.swingClock or {sequence=0}
    local clock={sequence=(previous.sequence+1)%4294967296}
    local now=S.readableCall(GetTime)
    if publicNumber(S,now,0,math.huge) and now~=math.huge then clock.at=now end
    if publicNumber(S,duration,0.001,60) then clock.durationMs=math.floor(duration*1000+0.5) end
    local generation=S.auraGeneration
    local exists=group.read(UnitExists,1,"target")
    local dead=group.read(UnitIsDeadOrGhost,1,"target")
    local attackable=group.read(UnitCanAttack,1,"player","target")
    if publicNumber(S,generation,0,255) and generation==math.floor(generation)
        and exists.status=="observed" and exists.value==true and dead.status=="observed" and dead.value==false
        and attackable.status=="observed" and attackable.value==true then clock.targetGeneration=generation end
    paladin.swingClock=clock
end
function paladin.swingClockBytes()
    local S=ns.state;local clock=paladin.swingClock or {sequence=0};local flags=paladin.swingClockRegistered and 1 or 0
    local age,duration,generation=65535,65535,0
    local now=S.readableCall(GetTime)
    if flags==1 and publicNumber(S,now,0,math.huge) and now~=math.huge and clock.at and now>=clock.at then
        flags=flags+2;age=math.min(65534,math.floor((now-clock.at)*1000))
        if clock.durationMs then flags=flags+4;duration=clock.durationMs end
        if clock.targetGeneration then flags=flags+8;generation=clock.targetGeneration end
    end
    return S.bytes(flags,1)..S.bytes(clock.sequence,4)..S.bytes(age,2)..S.bytes(duration,2)..S.bytes(generation,1)
end

local function initializeNative(S)
    local panel=CreateFrame("Frame",nil,S.hud);S.paladinNativePanel=panel
    panel:SetSize(668,40);panel:SetPoint("TOPLEFT",S.hud,"TOPLEFT",0,-626);panel:Hide()
    local bg=panel:CreateTexture(nil,"BACKGROUND");bg:SetAllPoints();bg:SetColorTexture(0,0,0,1)
    for i,color in ipairs({{0,1,1},{1,0.5,0},{1,0,1}}) do
        local dot=panel:CreateTexture(nil,"OVERLAY");dot:SetSize(4,4);dot:SetPoint("TOPLEFT",4+(i-1)*6,0);dot:SetColorTexture(color[1],color[2],color[3],1)
    end
    paladin.shieldSource=panel:CreateTexture(nil,"OVERLAY");paladin.shieldSource:SetSize(4,4);paladin.shieldSource:SetPoint("TOPLEFT",342,-25);paladin.shieldSource:SetColorTexture(0,0,0,1)
    paladin.shieldAura=panel:CreateTexture(nil,"ARTWORK");paladin.shieldAura:SetSize(8,8);paladin.shieldAura:SetPoint("TOPLEFT",330,-23);paladin.shieldAura:SetColorTexture(0,0.25,1,1)
    local holyShield=panel:CreateTexture(nil,"ARTWORK");holyShield:SetSize(8,8);holyShield:SetPoint("TOPLEFT",578,-23);holyShield:SetColorTexture(0,0.25,1,1)
    paladin.forbearanceSource=panel:CreateTexture(nil,"OVERLAY");paladin.forbearanceSource:SetSize(4,4);paladin.forbearanceSource:SetPoint("TOPLEFT",640,-25);paladin.forbearanceSource:SetColorTexture(0,0,0,1)
    paladin.nativeStamp={};paladin.nativeTiles={}
    paladin.castIdentityCells={}
    for i=1,3 do
        local dot=panel:CreateTexture(nil,"OVERLAY");dot:SetSize(4,4);dot:SetPoint("TOPLEFT",610+(i-1)*6,0)
        paladin.castIdentityCells[i]=dot
    end
    paladin.divineShieldCells={}
    for i=1,6 do
        local dot=panel:CreateTexture(nil,"OVERLAY");dot:SetSize(4,4);dot:SetPoint("TOPLEFT",538+(i-1)*6,-36)
        dot:SetColorTexture(0,0,0,1);paladin.divineShieldCells[i]=dot
    end
    for i=1,4 do
        local dot=panel:CreateTexture(nil,"OVERLAY");dot:SetSize(4,4);dot:SetPoint("TOPLEFT",626+(i-1)*6,0);paladin.nativeStamp[i]=dot
    end
    for i=1,18 do
        local tile={};local x=12+(i-1)*46
        -- The reset uses the remaining right-hand strip; existing tile geometry
        -- stays intact for recorded frames and legacy readers.
        local small=i>=15;if small then x=i==15 and 656 or 0 end
        for _,spec in ipairs(paladin.specs) do if spec.key=="paladin."..paladin.packetKeys[i] then tile.offGlobalCooldown=spec.offGlobalCooldown==true;break end end
        tile.icon=panel:CreateTexture(nil,"ARTWORK");tile.icon:SetSize(16,16);tile.icon:SetPoint("TOPLEFT",x,-6)
        tile.dial=panel:CreateTexture(nil,"BACKGROUND");tile.dial:SetSize(16,16);tile.dial:SetPoint("TOPLEFT",x+18,-6)
        tile.cooldown=CreateFrame("Cooldown",nil,panel,"CooldownFrameTemplate");tile.cooldown:SetAllPoints(tile.dial)
        tile.cooldown:SetDrawEdge(false);tile.cooldown:SetDrawSwipe(true);tile.cooldown:SetSwipeColor(0,0,0,1);tile.cooldown:SetHideCountdownNumbers(true)
        tile.aura=panel:CreateTexture(nil,"ARTWORK");tile.aura:SetSize(8,8);tile.aura:SetPoint("TOPLEFT",x+36,-6);tile.aura:SetColorTexture(0,0.25,1,1)
        if small then
            tile.icon:SetSize(8,8);tile.dial:SetSize(8,8)
            tile.dial:ClearAllPoints();tile.dial:SetPoint("TOPLEFT",x,-16)
            tile.aura:Hide()
        end
        if i>=17 then
            local bx=i==18 and 230 or 160
            tile.icon:ClearAllPoints();tile.icon:SetPoint("TOPLEFT",bx,-23)
            tile.dial:ClearAllPoints();tile.dial:SetPoint("TOPLEFT",bx+10,-23)
            tile.aura:ClearAllPoints();tile.aura:SetPoint("TOPLEFT",bx+54,-23);if i==17 then tile.aura:Show() end
        end
        tile.visualSignals={}
        for j=1,4 do
            local dot=panel:CreateTexture(nil,"OVERLAY");dot:SetSize(4,4);dot:SetPoint("TOPLEFT",x+(j-1)*6,-32);ns.features.RangeTracking.initialize(dot,1,.65,0,1);tile.visualSignals[j]=dot
            if small then dot:ClearAllPoints();dot:SetPoint("TOPLEFT",x+((j-1)%2)*6,-26-math.floor((j-1)/2)*6) end
            if i>=17 then dot:ClearAllPoints();dot:SetPoint("TOPLEFT",(i==18 and 252 or 182)+(j-1)*6,-25) end
        end
        if i<=16 then tile.manaCost=ns.features.SpellBridge.createManaCost(panel,30+(i-1)*36,0,28)
        elseif i==18 then tile.manaCost=ns.features.SpellBridge.createManaCost(panel,284,24,28) end
        paladin.nativeTiles[i]=tile
        local useButton=S.attachSpellUse(panel,tile.icon,"paladin."..paladin.packetKeys[i])
        -- Keep the switch marker inside the compact icon. The shared outside
        -- marker would overlap two columns of this tile's cooldown renderer.
        useButton.useDot:ClearAllPoints()
        useButton.useDot:SetPoint("TOPRIGHT",tile.icon,"TOPRIGHT",0,0)
    end
    local function extensionTile(key,x,compactSelf)
        local function cell(layer,size,dx,y)
            local region=panel:CreateTexture(nil,layer);region:SetSize(size,size);region:SetPoint("TOPLEFT",x+dx,-y);return region
        end
        local tile={icon=cell("ARTWORK",8,0,23),dial=cell("BACKGROUND",8,10,23),visualSignals={}}
        for _,spec in ipairs(paladin.specs) do if spec.key==key then tile.offGlobalCooldown=spec.offGlobalCooldown==true;break end end
        tile.cooldown=CreateFrame("Cooldown",nil,panel,"CooldownFrameTemplate");tile.cooldown:SetAllPoints(tile.dial)
        tile.cooldown:SetDrawEdge(false);tile.cooldown:SetDrawSwipe(true);tile.cooldown:SetSwipeColor(0,0,0,1);tile.cooldown:SetHideCountdownNumbers(true)
        for j=1,4 do
            local dx=compactSelf and j==4 and 38 or 22+(j-1)*6
            local dot=cell("OVERLAY",4,dx,25);ns.features.RangeTracking.initialize(dot,1,.65,0,1);tile.visualSignals[j]=dot
        end
        tile.manaCost=ns.features.SpellBridge.createManaCost(panel,x,36,28)
        local use=S.attachSpellUse(panel,tile.icon,key);use.useDot:ClearAllPoints();use.useDot:SetPoint("TOPRIGHT",tile.icon,"TOPRIGHT",0,0)
        return tile
    end
    paladin.protectionTiles={}
    for i,key in ipairs(ns.spellCatalog.PALADIN.protectionKeys) do
        paladin.protectionTiles[i]=extensionTile(key,350+(i-1)*72)
    end
    paladin.utilityTiles={}
    for i,key in ipairs(ns.spellCatalog.PALADIN.utilityKeys) do
        paladin.utilityTiles[i]=extensionTile(key,18+(i-1)*72)
    end
    paladin.divineShieldTile=extensionTile("paladin.divineShield",586,true)
    local wisdom=panel:CreateTexture(nil,"ARTWORK");wisdom:SetSize(8,8);wisdom:SetPoint("TOPLEFT",72,-23);wisdom:SetColorTexture(0,0.25,1,1)
end

local function paintRGB(cells,bytes)
    for i,dot in ipairs(cells) do
        local r,g,b=string.byte(bytes,(i-1)*3+1,i*3)
        dot:SetColorTexture(r/255,g/255,b/255,1)
    end
end

local function renderNative(tile,bound,learned,chosen,info,S,rangeRead,rangeRaw,usableRead,usableRaw,manaRaw,rangeSource,usableSource)
    tile.spellID=bound>0 and bound or nil;tile.known=learned.status=="observed" and learned.value or false
    S.renderSpellIcon(tile,info)
    S.renderCooldown(tile)
    local rangeOK,usableOK=false,false
    if chosen and chosen.managed then
        -- The public packet checks target range. Self/pet native indicators
        -- still need their own direct range query; usability has no unit.
        rangeOK,usableOK=ns.features.RangeTracking.render(tile.visualSignals,bound,chosen.unit,chosen.unit=="target" and rangeRead or nil,rangeRaw,usableRead,usableRaw,manaRaw,rangeSource,usableSource)
    elseif chosen and chosen.kind=="spell" then
        local button=chosen.button
        if button and S.readableCall(button.IsVisible,button)==true and S.safeField(button,"action")==chosen.slot then
            local hotkey=button.HotKey
            if type(hotkey)~="table" and type(hotkey)~="userdata" then hotkey=nil end
            local method=hotkey and type(hotkey.GetVertexColor)=="function" and "GetVertexColor" or "GetTextColor"
            rangeOK=S.mirrorColor(tile.visualSignals[1],hotkey,method,true)
            local icon=button.icon or button.Icon
            if type(icon)=="table" or type(icon)=="userdata" then usableOK=S.mirrorColor(tile.visualSignals[3],icon,"GetVertexColor",true) end
        end
    end
    local R=ns.features.RangeTracking
    R.paintFlag(tile.visualSignals[2],rangeOK);R.paintFlag(tile.visualSignals[4],usableOK)
    -- Cyan certifies a direct spell-range result; legacy non-red bar text
    -- alone cannot prove that a spell has a meaningful range check.
    if chosen and chosen.managed and rangeOK then R.paintColor(tile.visualSignals[2],0,1,1,1) end
    if not rangeOK then R.paintColor(tile.visualSignals[1],1,.65,0,1) end
    if not usableOK then R.paintColor(tile.visualSignals[3],1,.65,0,1) end
end

local function retSignalContext(S)
    local echoes=S.setupTalentNames and S.setupTalentNames["Unsealed Wrath"]==true
    return not S.paladinProtectionActive and not S.paladinProtectionPending and (S.paladinRetributionActive or echoes),echoes
end
local function sameAuraReadings(current,previous)
    local nextSlot=1
    for i,reading in ipairs(current) do
        local old=previous[i]
        if not old or reading.name~=old.name or reading.bound~=old.bound or reading.learned~=old.learned or
                (reading.auraID or 0)~=(old.auraID or 0) then return false end
        nextSlot=i+1
    end
    return previous[nextSlot]==nil
end
local function refreshNativeAuras(readings,wisdomID,bulwarkID,S)
    local bulwarkKey="paladin.templarsBulwark"
    local retTiming,echoes=retSignalContext(S)
    local revision,complete=S.setupKnownSpellRevision or 0,S.setupBookAvailable==true
    local previous=paladin.auraConfiguration
    -- Compare public filter configuration without serializing every slot on every update.
    retTiming,echoes=not not retTiming,not not echoes
    if previous and previous.revision==revision and previous.complete==complete and previous.echoes==echoes and
            previous.retTiming==retTiming and previous.wisdomID==wisdomID and previous.bulwarkID==bulwarkID and
            sameAuraReadings(readings,previous.readings) then return end
    if S.readableCall(InCombatLockdown)~=false then
        paladin.auraConfiguration=nil;paladin.auraMask=0;paladin.auraAbsenceMask=0;paladin.wisdomAuraReady=false;paladin.combatAuraPage=nil
        return
    end
    paladin.auraConfiguration={revision=revision,complete=complete,retTiming=retTiming,echoes=echoes,
        wisdomID=wisdomID,bulwarkID=bulwarkID,readings=readings}
    paladin.auraMask=0;paladin.auraAbsenceMask=0;paladin.wisdomAuraReady=false;paladin.forbearanceAuraReady=false;paladin.auraSettledAt=GetTime()+0.6
    paladin.signalAuraRevision=((paladin.signalAuraRevision or 0)+1)%4294967296
    paladin.combatAuraPage=nil
    if ns.retireNativeSignalAuras then pcall(ns.retireNativeSignalAuras,paladin) end
    if paladin.nativeAuras then
        pcall(paladin.nativeAuras.SetEnabled,paladin.nativeAuras,false);pcall(paladin.nativeAuras.SetUnit,paladin.nativeAuras,nil);pcall(paladin.nativeAuras.Hide,paladin.nativeAuras)
        paladin.nativeAuras=nil
    end
    local container,forbearance
    local ok=pcall(function()
        container=CreateFrame("AuraContainer",nil,S.paladinNativePanel,"CustomAuraContainerTemplate");container:SetAllPoints(S.paladinNativePanel)
        local mask,absence=0,0
        local echoFilters={{"paladin.echoFury",1311701},{"paladin.echoRighteousness",1311704}}
        -- Reserve the same five native slots for every Paladin profile. A
        -- placeholder has no button or identity proof.
        local _,page=pcall(function()
            local wanted
            for _,key in ipairs({"paladin.sealRighteousness","paladin.sealFury",echoFilters[1][1],echoFilters[2][1],bulwarkKey}) do
                local index=ns.declareNativeSignalAura(paladin,key,"player",paladin.signalAuraRevision,"HELPFUL",0)
                if not index then return nil end
                local candidate=math.floor((index-1)/5)
                if wanted and candidate~=wanted then return nil end
                wanted=candidate
            end
            return wanted
        end)
        if retTiming and type(page)=="number" then paladin.combatAuraPage=page end
        for i,reading in ipairs(readings) do
            if (auraSlots[i] or i==19 or i==20) and reading.learned==true then
                local ids={[reading.bound]=true}
                for _,spell in ipairs(S.setupKnownSpells or {}) do if spell.name==reading.name then ids[spell.id]=true end end
                -- A public player aura identifies this server's actual aura ID,
                -- which can differ from the cast ID. Include it in the native
                -- filter before certifying its blue background as absence.
                if reading.auraID then ids[reading.auraID]=true;absence=absence+2^(i-1) end
                local slotX=i==20 and 578 or i==19 and 330 or i==17 and 214 or 12+(i-1)*46+36
                local auraKey=i==20 and "paladin.holyShield" or i==19 and "paladin.divineShield" or "paladin."..paladin.packetKeys[i]
                local signalIndex
                if ns.declareNativeSignalAura and i~=19 then local declared,index=pcall(ns.declareNativeSignalAura,paladin,auraKey,"player",paladin.signalAuraRevision,"HELPFUL",reading.auraID and 2 or 1);if declared then signalIndex=index end end
                container:AddAuraSlot(auraKey,"HELPFUL",{candidateFilters={includeSpellIDs=ids},initializeFrame=function(button)
                    button:SetSize(8,8);button:SetPoint("TOPLEFT",container,"TOPLEFT",slotX,(i==17 or i>=19) and -23 or -6);button:EnableMouse(false)
                    local icon=button:CreateTexture(nil,"ARTWORK");icon:SetAllPoints(button);button:SetIcon(icon)
                    local signal=button:CreateTexture(nil,"OVERLAY");signal:SetAllPoints(button);signal:SetColorTexture(0,1,0,1)
                    if signalIndex and ns.attachNativeSignalAura then pcall(ns.attachNativeSignalAura,signalIndex,button) end
                end})
                mask=mask+2^(i-1)
            end
        end
        if wisdomID then
            -- All three verified self-applied Wisdom ranks share this slot so
            -- manual rank changes cannot be mistaken for absence in combat.
            container:AddAuraSlot("paladin.sealWisdom","HELPFUL",{candidateFilters={includeSpellIDs=wisdomRanks},initializeFrame=function(button)
                button:SetSize(8,8);button:SetPoint("TOPLEFT",container,"TOPLEFT",72,-23);button:EnableMouse(false)
                local icon=button:CreateTexture(nil,"ARTWORK");icon:SetAllPoints(button);button:SetIcon(icon)
                local signal=button:CreateTexture(nil,"OVERLAY");signal:SetAllPoints(button);signal:SetColorTexture(0,1,0,1)
            end})
        end
        -- Exact Forever aura IDs. Restricted durations and counts stay on
        -- the existing native widgets.
        local function exactTimedAura(key,id)
            if not ns.declareNativeSignalAura or not ns.attachNativeSignalAura then return false end
            local declared,signalIndex=pcall(ns.declareNativeSignalAura,paladin,key,"player",paladin.signalAuraRevision,"HELPFUL",2)
            if not declared or not signalIndex then return false end
            return pcall(container.AddAuraSlot,container,key,"HELPFUL",{candidateFilters={includeSpellIDs={[id]=true}},initializeFrame=function(button)
                button:SetSize(1,1);button:SetPoint("TOPLEFT",container,"TOPLEFT",0,0);button:EnableMouse(false)
                local icon=button:CreateTexture(nil,"ARTWORK");icon:SetAllPoints(button);icon:SetAlpha(0);button:SetIcon(icon)
                pcall(ns.attachNativeSignalAura,signalIndex,button)
            end})
        end
        if retTiming and echoes then
            for _,echo in ipairs(echoFilters) do
                exactTimedAura(echo[1],echo[2])
            end
        end
        -- Aura page visibility freezes in combat. Bulwark needs this page
        -- before a pull even in Protection, without pinning cooldown pages.
        if bulwarkID and type(page)=="number" and exactTimedAura(bulwarkKey,bulwarkID) then paladin.combatAuraPage=page end
        -- Forbearance can outlast Bulwark or come from another protection.
        -- Only a positive native match suppresses a self-protection request.
        forbearance=pcall(container.AddAuraSlot,container,"paladin.forbearance","HARMFUL",{candidateFilters={includeSpellIDs={[25771]=true}},initializeFrame=function(button)
            button:SetSize(8,8);button:SetPoint("TOPLEFT",container,"TOPLEFT",628,-23);button:EnableMouse(false)
            local icon=button:CreateTexture(nil,"ARTWORK");icon:SetAllPoints(button);button:SetIcon(icon)
            local signal=button:CreateTexture(nil,"OVERLAY");signal:SetAllPoints(button);signal:SetColorTexture(0,1,0,1)
        end})
        container:SetUnit("player");container:SetEnabled(true);paladin.auraMask=mask;paladin.auraAbsenceMask=absence
    end)
    if ok then paladin.nativeAuras=container;paladin.wisdomAuraReady=wisdomID~=nil;paladin.forbearanceAuraReady=forbearance
    else paladin.combatAuraPage=nil;if container then pcall(container.SetEnabled,container,false);pcall(container.Hide,container) end end
end

function paladin.initializePreview()
    local S=ns.state;local group=ns.features.GroupContext
    local panel=CreateFrame("Frame",nil,S.hud);S.paladinPanel=panel;panel:SetSize(668,12);panel:SetPoint("TOPLEFT",S.hud,"TOPLEFT",0,-614)
    local background=panel:CreateTexture(nil,"BACKGROUND");background:SetAllPoints();background:SetColorTexture(0,0,0,1)
    initializeNative(S)
    local tick,total,weaponRetry=0,0,0
    local mappingSource,mappingCandidates
    local function previewBinding(spec,id)
        local mappings=S.bindingsValid and S.setupMappings or nil
        if mappings~=mappingSource then
            mappingSource,mappingCandidates=mappings,mappings and {} or nil
        end
        if not mappings then return end
        local candidates=mappingCandidates[spec]
        if not candidates or candidates.id~=id then
            -- Discovery publishes a new mapping array after refreshing delivery identities.
            candidates={id=id}
            for _,mapping in ipairs(mappings) do
                if (id>0 and mapping.id==id) or (not mapping.playerOwned and mapping.name==spec.name) then
                    candidates[#candidates+1]=mapping
                end
            end
            mappingCandidates[spec]=candidates
        end
        local chosen
        for _,mapping in ipairs(candidates) do
            -- Recheck the actual action and key on every observation, including in combat.
            if mapping.key and (not chosen or mapping.playerOwned and not chosen.playerOwned or
                mapping.playerOwned==chosen.playerOwned and chosen.kind~="spell" and mapping.kind=="spell") and S.mappingCurrent(mapping) then
                chosen=mapping
            end
        end
        return chosen
    end
    panel:RegisterEvent("PLAYER_LOGIN");panel:RegisterEvent("PLAYER_EQUIPMENT_CHANGED");panel:RegisterEvent("PLAYER_REGEN_ENABLED")
    for _,event in ipairs({"PLAYER_ENTERING_WORLD","PLAYER_DEAD","PLAYER_LEAVE_COMBAT","PLAYER_SWING"}) do pcall(panel.RegisterEvent,panel,event) end
    paladin.swingClockRegistered=S.readableCall(panel.IsEventRegistered,panel,"PLAYER_SWING")==true
    paladin.resetSwingClock()
    panel:SetScript("OnEvent",function(self,event,slot,hand)
        if event=="PLAYER_SWING" then
            if group.text(group.read(UnitClass,2,"player"),16)=="PALADIN" then paladin.observeSwingClock(slot,hand) end
            return
        end
        if event=="PLAYER_LOGIN" or event=="PLAYER_ENTERING_WORLD" or event=="PLAYER_DEAD" or event=="PLAYER_LEAVE_COMBAT" or event=="PLAYER_EQUIPMENT_CHANGED" then paladin.resetSwingClock() end
        if event=="PLAYER_ENTERING_WORLD" or event=="PLAYER_DEAD" or event=="PLAYER_LEAVE_COMBAT" then return end
        if event=="PLAYER_EQUIPMENT_CHANGED" and (S.isSecret(slot) or slot~=16) then return end
        if event=="PLAYER_REGEN_ENABLED" and (paladin.weaponDelayMs or 0)>0 then return end
        if group.text(group.read(UnitClass,2,"player"),16)=="PALADIN" then pcall(paladin.refreshWeapon) end
    end)
    -- Diagnostic scopes exist only during this synchronous preview render.
    -- OFF still calls the original helpers and does not read a profiling clock.
    local previewProfile
    local function timedPart(part,original,...)
        local context=previewProfile
        local start=S.profileClock()
        local ok,reason=pcall(original,...)
        local finish=S.profileClock()
        if start and finish and finish>=start then context[part]=context[part]+finish-start
        else context.valid=false end
        if not ok then error(reason,0) end
    end
    -- Preserve return arity and native scalars on the Lua stack only. No
    -- raw API result is inspected, put in a table or retained by diagnostics.
    local function finishValues(part,start,...)
        local context=previewProfile;local finish=S.profileClock()
        if start and finish and finish>=start then context[part]=context[part]+finish-start
        else context.valid=false end
        return ...
    end
    local function timedValues(part,original,...)
        local start=S.profileClock()
        return finishValues(part,start,original(...))
    end
    local function valueScope(part,original)
        if type(original)~="function" then return original end
        return function(...)return timedValues(part,original,...)end
    end
    local function timedNative(...)timedPart("native",renderNative,...)end
    local function timedMana(...)timedPart("native",ns.features.SpellBridge.renderManaCost,...)end
    local function timedHeal(...)timedPart("native",paladin.renderHealWindows,...)end
    local function timedRGB(...)timedPart("native",paintRGB,...)end
    local function timedAuras(...)timedPart("auras",refreshNativeAuras,...)end
    local function bindingSelection(spec,id)
        local chosen=previewBinding(spec,id)
        local visualChosen=chosen
        local key=chosen and chosen.key or "";local keyCode=paladin.bindingCode(key)
        if keyCode==0 then chosen=nil end
        return chosen,visualChosen,keyCode
    end
    local function encodeRecord(bound,chosen,keyCode,flags)
        return S.bytes(bound,4)..S.bytes(chosen and chosen.slot or 0,2)..S.bytes(chosen and (chosen.kind=="spell" and 1 or 2) or 0,1)..S.bytes(keyCode,2)..S.bytes(flags,2)
    end
    local function render()
        if group.text(group.player("class"),16)~="PALADIN" then S.publishTransportPacket(ns.wire.ids.paladinPreview,nil);S.paladinNativePanel:Hide();return end
        if previewProfile then previewProfile.active=true end
        local drawNative=previewProfile and timedNative or renderNative
        local drawMana=previewProfile and timedMana or ns.features.SpellBridge.renderManaCost
        local drawHeal=previewProfile and timedHeal or paladin.renderHealWindows
        local drawRGB=previewProfile and timedRGB or paintRGB
        local updateAuras=previewProfile and timedAuras or refreshNativeAuras
        S.paladinNativePanel:Show()
        if GetTime()>=weaponRetry and (paladin.weaponDelayMs or 0)==0 and S.readableCall(InCombatLockdown)==false then paladin.refreshWeapon();weaponRetry=GetTime()+1 end
        local api=type(C_Spell)=="table" and C_Spell or {};local book=type(C_SpellBook)=="table" and C_SpellBook or {}
        -- Profiling OFF only selects existing function references. The ON
        -- closures capture functions, never observations or restricted scalars.
        local readInfo=api.GetSpellInfo;local readKnown=book.IsSpellKnown or IsSpellKnown
        local readCooldown=api.GetSpellCooldown
        local readUsability=ns.features.RangeTracking.readUsability
        local readRange=ns.features.RangeTracking.observeRange
        local chooseBinding=bindingSelection;local validateKey=paladin.bindingCode
        local currentMapping=S.mappingCurrent
        local currentManaged=S.managedSpells and S.managedSpells.current
        local threatBinding=ns.features.Threat.readyBinding
        local encodeAbility=encodeRecord;local encodeChecksum=S.adler32
        if previewProfile then
            readInfo=valueScope("reads",readInfo);readKnown=valueScope("reads",readKnown)
            readCooldown=valueScope("reads",readCooldown)
            readUsability=valueScope("reads",readUsability);readRange=valueScope("reads",readRange)
            chooseBinding=valueScope("binding",chooseBinding);validateKey=valueScope("binding",validateKey)
            currentMapping=valueScope("binding",currentMapping);currentManaged=valueScope("binding",currentManaged)
            threatBinding=valueScope("binding",threatBinding)
            encodeAbility=valueScope("encoding",encodeAbility);encodeChecksum=valueScope("encoding",encodeChecksum)
        end
        tick=(tick+1)%4294967296
        local level=group.player("level");level=level.status=="observed" and type(level.value)=="number" and level.value>=1 and level.value<=100 and math.floor(level.value)==level.value and level.value or 0
        local swiftMode=swiftUnleashesSeal and 4 or 0
        local packet=ns.wire.schemas.paladinPreview..S.bytes(S.setupSession,4)..S.bytes(tick,4)..S.bytes(level,1)..S.bytes(S.updateRateMs,2)..S.bytes((S.bindingsValid and 2 or 0)+swiftMode,1)
        -- The first readable aura match owns the proc count, even if later rows are restricted.
        local protection=S.paladinProtectionActive==true
        local auras,auraIDs,complete={},{},false
        local holyShieldCount,wrathStacks,continueWrath
        local B=ns.features.SpellBridge
        if type(C_UnitAuras)=="table" and type(C_UnitAuras.GetAuraDataByIndex)=="function" then
            for i=1,40 do
                local ok,aura=pcall(C_UnitAuras.GetAuraDataByIndex,"player",i,"HELPFUL")
                if not ok or S.isSecret(aura) then break end
                if aura==nil then complete=true;break end
                local name=group.text(group.field(aura,"name"),80)
                if name=="" then break end;auras[name]=true
                local auraID=group.field(aura,"spellId")
                if auraID.status=="observed" and type(auraID.value)=="number" and auraID.value>0 and auraID.value<2147483648 and math.floor(auraID.value)==auraID.value then auraIDs[name]=auraID.value end
                if wrathStacks==nil and name=="Unsealed Wrath" then wrathStacks=B.stackCountFromAura("player",name,3,aura,auraID) end
                if protection and name=="Holy Shield" then
                    local count=group.field(aura,"applications")
                    if count.status=="observed" and publicNumber(S,count.value,0,32) and math.floor(count.value)==count.value then holyShieldCount=count.value end
                end
                if i==40 then continueWrath=true end
            end
        end
        if wrathStacks==nil then
            if complete then wrathStacks=B.stackCountFromAura("player","Unsealed Wrath",3,nil)
            elseif continueWrath then wrathStacks=B.stackCount("player","Unsealed Wrath",3,41) end
        end
        paladin.rangeSpecs={};local nativeReadings={};local protectionRecords={};local utilityRecords={}
        local wisdomID,bulwarkID,utilityMask=nil,nil,0
        local divineShieldRecord
        local retTiming=retSignalContext(S)
        local retClocks=retTiming and {} or nil
        local records=protection and protectionKeys or retTiming and retKeys or ordinaryKeys
        for index,shortKey in ipairs(records) do
            local divineShield=shortKey=="divineShield"
            local spec=previewSpecs[shortKey]
            local ok,info=pcall(readInfo or function() end,spec.name)
            local id=ok and group.field(info,"spellID") or {};id=id.status=="observed" and type(id.value)=="number" and id.value>0 and math.floor(id.value)==id.value and id.value or 0
            local chosen,visualChosen,keyCode=chooseBinding(spec,id)
            local bound=chosen and chosen.id or id;bound=type(bound)=="number" and bound>0 and bound==math.floor(bound) and bound or 0
            if divineShield and bound>=2147483648 then bound=0;chosen=nil;visualChosen=nil;keyCode=0 end
            local learned=bound>0 and group.read(readKnown,1,bound) or {}
            local utilityIndex=utilitySlots[shortKey]
            local isLearned=learned.status=="observed" and learned.value==true
            if not utilityIndex or isLearned and utilitySpellIDs[shortKey][bound] then
            local usable,mana,usableRead,usableRaw,manaRaw,usableSource
            if bound>0 then usable,mana,usableRead,usableRaw,manaRaw,usableSource=readUsability(api.IsSpellUsable or IsUsableSpell,bound) end
            local range,rangeRead,rangeRaw;local rangeSource=api.IsSpellInRange
            if bound>0 and not divineShield then range,rangeRead,rangeRaw=readRange(rangeSource or IsSpellInRange,rangeSource and bound or spec.name,"target") end
            local readyCode=0
            -- The readable API includes the global cooldown. Off-GCD abilities
            -- leave this field unknown and use the native ignore-GCD widget,
            -- otherwise an unrelated GCD would override their own readiness.
            if bound>0 and not spec.offGlobalCooldown and type(api.GetSpellCooldown)=="function" then
                local cdOK,cd=pcall(readCooldown,bound)
                if cdOK then
                    local start,duration,enabled=group.field(cd,"startTime"),group.field(cd,"duration"),group.field(cd,"isEnabled")
                    if start.status=="observed" and duration.status=="observed" and type(start.value)=="number" and type(duration.value)=="number" and enabled.status=="observed" and enabled.value==true then
                        readyCode=(duration.value==0 or start.value+duration.value<=GetTime()) and 2 or 1
                    end
                end
            end
            local auraCode=auras[spec.name] and 2 or complete and 1 or 0
            local flags=group.code(learned)+4*group.code(usable)+16*group.code(mana)+64*group.code(range)+256*readyCode+1024*auraCode
            local record=encodeAbility(bound,chosen,keyCode,flags)
            local extension=index-baseSlots
            if extension>0 and not protection then extension=2 end -- Reuse the Hammer tile's calibration.
            if divineShield then
                if isLearned then divineShieldRecord=record end
            elseif utilityIndex then
                utilityRecords[utilityIndex]=record;utilityMask=utilityMask+2^(utilityIndex-1)
                if shortKey=="sealWisdom" then wisdomID=bound else bulwarkID=bound end
            elseif extension>0 then protectionRecords[extension]=record else packet=packet..record end
            local tile=divineShield and paladin.divineShieldTile or utilityIndex and paladin.utilityTiles[utilityIndex] or extension>0 and paladin.protectionTiles[extension] or paladin.nativeTiles[index]
            drawNative(tile,bound,learned,visualChosen,ok and not S.isSecret(info) and info or nil,S,rangeRead,rangeRaw,usableRead,usableRaw,manaRaw,rangeSource,usableSource)
            if retClocks and isLearned and (shortKey=="judgement" or shortKey=="holyStrike" or shortKey=="hammerWrath") then retClocks[#retClocks+1]=bound end
            if not divineShield and not utilityIndex and extension==2 and not protection and not isLearned then protectionRecords[2]=nil end
            if tile.manaCost then
                local freeIfNoCostRecord=shortKey=="swiftJudgement" and bound==1310994 and bound==id
                drawMana(tile.manaCost,bound,isLearned,freeIfNoCostRecord)
            end
            paladin.verifiedAuraIDs=paladin.verifiedAuraIDs or {}
            local family=spec.key..":"..bound
            if learned.status=="observed" and learned.value==true and auraIDs[spec.name] and S.readableCall(InCombatLockdown)==false then paladin.verifiedAuraIDs[family]=auraIDs[spec.name] end
            local auraID=paladin.verifiedAuraIDs[family]
            if extension==1 and isLearned and not auraID and holyShieldRanks[bound] and bound==id and S.safeField(info,"name")==spec.name then
                -- These exact ranks self-apply their own spell ID. The native
                -- slot must still demonstrate presence or absence each frame.
                auraID=bound
            end
            local reading={name=spec.name,bound=bound,learned=isLearned,auraID=auraID}
            if divineShield then nativeReadings[19]=reading
            elseif not utilityIndex then
                if extension<=0 then nativeReadings[index]=reading
                elseif extension==1 then paladin.protectionShield=reading end
            end
            if spec.healing and bound>0 and learned.value==true then paladin.rangeSpecs[#paladin.rangeSpecs+1]={id=bound,name=spec.name} end
            end
        end
        if protection then nativeReadings[20]=paladin.protectionShield end
        local movement=group.read(GetUnitSpeed,1,"player");movement=movement.status=="observed" and type(movement.value)=="number" and {status="observed",value=movement.value>0} or {}
        packet=packet..S.bytes(group.code(movement),1)..S.bytes(group.code(group.player("combat")),1)..S.bytes(group.code(group.player("mounted")),1)..S.bytes(group.code(group.player("taxi")),1)
        updateAuras(nativeReadings,wisdomID,bulwarkID,S)
        local auraMask=GetTime()>=(paladin.auraSettledAt or math.huge) and (paladin.auraMask or 0) or 0
        -- The source marker proves that this frame owns a settled Shield filter.
        -- A blue/hidden/occluded cell is unknown, never inferred protection.
        local shieldReady=math.floor(auraMask/262144)%2==1
        paladin.shieldSource:SetColorTexture(0,shieldReady and 1 or 0,0,1)
        local forbearanceReady=paladin.forbearanceAuraReady and GetTime()>=(paladin.auraSettledAt or math.huge)
        paladin.forbearanceSource:SetColorTexture(0,forbearanceReady and 1 or 0,forbearanceReady and 1 or 0,1)
        -- Absence is available only for a native filter built with an actual
        -- public player aura identity for this bound spell rank.
        local absenceMask=auraMask~=0 and (paladin.auraAbsenceMask or 0) or 0
        packet=packet..S.bytes(paladin.weaponID or 0,4)..S.bytes(paladin.weaponDelayMs or 0,2)..S.bytes(auraMask,2)..S.bytes(absenceMask,2)
        local usage=0
        for i,key in ipairs(ns.spellCatalog.PALADIN.packetKeys) do if i>16 then break end;usage=usage+S.spellUseCode(key)*4^(i-1) end
        packet=packet..S.bytes(S.auraGeneration,1)..S.bytes(usage,4)..S.executionBytes(2)
        -- Instance type is public context; unavailable/secret values stay unknown.
        local inside,kind=group.playerInstance()
        local dungeon={}
        if inside.status=="observed" and type(inside.value)=="boolean" then
            if inside.value==false then dungeon={status="observed",value=false}
            elseif kind.status=="observed" and type(kind.value)=="string" and kind.value~="" then dungeon={status="observed",value=kind.value=="party"} end
        end
        packet=packet..S.bytes(group.code(dungeon),1)
        local healInfo=group.read(function() return readInfo(nativeReadings[6].bound).castTime end,1)
        local healMs=healInfo.status=="observed" and type(healInfo.value)=="number" and healInfo.value>0 and healInfo.value<=10000 and math.floor(healInfo.value)==healInfo.value and healInfo.value or 0
        drawHeal(nativeReadings,healMs,S)
        local cancel=S.managedSpells and S.managedSpells.entries["PALADIN:Feuxton Remove Fury"]
        local cancelKey=S.bindingsValid and currentManaged(cancel) and validateKey(cancel.key) or 0
        packet=packet..S.bytes(healMs,2)..S.bytes(cancelKey,2)
        local attackKey=0
        if S.bindingsValid then for _,mapping in ipairs(S.setupMappings or {}) do
            if mapping.id==6603 and mapping.startAttack and currentMapping(mapping) then attackKey=validateKey(mapping.key);break end
        end end
        local attacking=group.read(api.IsCurrentSpell or IsCurrentSpell,1,6603)
        if attacking.status~="observed" and type(S.meleeActive)=="boolean" then attacking={status="observed",value=S.meleeActive} end
        packet=packet..S.bytes(group.code(attacking),1)..S.bytes(attackKey,2)..S.bytes(S.spellUseCode("paladin.autoAttack"),1)
        local stopEntry=S.managedSpells and S.managedSpells.entries["PALADIN:Feuxton Stop Casting"]
        local stopKey=S.bindingsValid and currentManaged(stopEntry) and validateKey(stopEntry.key) or 0
        packet=packet..S.bytes(stopKey,2)
        packet=packet..S.bytes(validateKey(threatBinding()),2)
        packet=packet..S.bytes(wrathStacks or 255,1)
        local creature=S.readableCall(UnitCreatureType,"target")
        packet=packet..S.bytes(creature=="Undead" and 2 or creature=="Demon" and 3 or type(creature)=="string" and 1 or 0,1)
        packet=packet..S.bytes(S.spellUseCode("paladin.blessingProtection"),1)..S.bytes(math.floor(auraMask/65536)%2+2*(math.floor(absenceMask/65536)%2),1)
        local flashInfo=group.read(function() return readInfo(nativeReadings[18].bound).castTime end,1)
        local flashMs=flashInfo.status=="observed" and type(flashInfo.value)=="number" and flashInfo.value>0 and flashInfo.value<=10000 and math.floor(flashInfo.value)==flashInfo.value and flashInfo.value or 0
        packet=packet..S.bytes(S.spellUseCode("paladin.flashLight"),1)..S.bytes(flashMs,2)
        local targetLevel=S.readableCall(UnitLevel,"target")
        targetLevel=publicNumber(S,targetLevel,-1,100) and targetLevel==math.floor(targetLevel) and targetLevel or nil
        local classification=group.text(group.read(UnitClassification,1,"target"),20)
        packet=packet..S.bytes(targetLevel==-1 and 65534 or targetLevel or 65535,2)..S.bytes(targetClassifications[classification] or 0,1)..paladin.swingClockBytes()
        if protection then
            local shield=paladin.protectionShield
            local count=holyShieldCount or (complete and not auras["Holy Shield"] and 0 or 255)
            local proof=math.floor(auraMask/524288)%2+2*(math.floor(absenceMask/524288)%2)
            if not shield or not shield.learned then count=255;proof=0 end
            local protectionUsage=0
            for index,key in ipairs(ns.spellCatalog.PALADIN.protectionKeys) do protectionUsage=protectionUsage+S.spellUseCode(key)*4^(index-1) end
            packet=packet..table.concat(protectionRecords)..S.bytes(count,1)..S.bytes(proof,1)..S.bytes(protectionUsage,1)
        elseif S.paladinProtectionPending then
            -- The former active tree was invalidated. Hold dispatch until
            -- the locally refreshed tree settles, even as setup pages lag.
            packet=packet..S.bytes(1,1)
        elseif protectionRecords[2] then
            packet=packet..protectionRecords[2]..S.bytes(S.spellUseCode("paladin.hammerWrath"),1)
        end
        if utilityMask>0 then
            packet=packet:sub(1,15)..S.bytes((S.bindingsValid and 2 or 0)+swiftMode+8*utilityMask,1)..packet:sub(17)
            local utilityFlags=0
            for index,key in ipairs(ns.spellCatalog.PALADIN.utilityKeys) do
                if utilityRecords[index] then
                    packet=packet..utilityRecords[index]
                    utilityFlags=utilityFlags+S.spellUseCode(key)*4^(index-1)
                end
            end
            if wisdomID and paladin.wisdomAuraReady and GetTime()>=(paladin.auraSettledAt or math.huge) then utilityFlags=utilityFlags+48 end
            if bulwarkID and paladin.bulwarkRecoveryProof and paladin.bulwarkRecoveryProof(S,group,bulwarkID) then utilityFlags=utilityFlags+64 end
            packet=packet..S.bytes(utilityFlags,1)
        end
        local checksum=encodeChecksum(packet)
        local activeID,activeKind=ns.features.CastTracking.activityIdentity()
        local active=S.bytes(activeID,4)..S.bytes(activeKind,1)
        -- Associate public RGB identity with this exact checksummed class frame.
        active=active..S.bytes(encodeChecksum(active..S.bytes(checksum,4)),4)
        drawRGB(paladin.castIdentityCells,active)
        -- An optional record in unused pixels preserves existing HHPD framing.
        -- Only the record attached to this packet's checksum can own the tile.
        if divineShieldRecord then
            local shield=string.char(1)..divineShieldRecord..S.bytes(S.spellUseCode("paladin.divineShield"),1)
            drawRGB(paladin.divineShieldCells,shield..S.bytes(encodeChecksum(shield..S.bytes(checksum,4)),4)..string.char(0))
        elseif paladin.divineShieldPainted then
            drawRGB(paladin.divineShieldCells,string.rep(string.char(0),18))
        end
        paladin.divineShieldPainted=divineShieldRecord~=nil
        for i,dot in ipairs(paladin.nativeStamp) do local value=math.floor(checksum/256^(i-1))%256/255;dot:SetColorTexture(value,value,value,1) end
        packet=packet..S.bytes(checksum,4);assert(#packet<=357)
        S.publishTransportPacket(ns.wire.ids.paladinPreview,packet)
        if (retClocks or paladin.combatAuraPage) and ns.setPaladinCombatSignalPage then ns.setPaladinCombatSignalPage(paladin.combatAuraPage,retClocks) end
    end
    local function renderProfiled()
        local start=S.profileClock()
        if not start then return render() end
        local context={native=0,auras=0,reads=0,binding=0,encoding=0,valid=true};previewProfile=context
        local ok,reason=pcall(render)
        previewProfile=nil
        local finish=S.profileClock()
        if ok and context.active and context.valid and finish and finish>=start then
            local residual=finish-start-context.native-context.auras-context.reads-context.binding-context.encoding
            if residual>=0 then
                S.profileElapsed("paladin spell API reads",context.reads)
                S.profileElapsed("paladin binding validation",context.binding)
                S.profileElapsed("paladin records and checksums",context.encoding)
                S.profileElapsed("paladin other preview work",residual)
                S.profileElapsed("paladin native render helpers",context.native)
                S.profileElapsed("paladin aura filters",context.auras)
            end
        end
        if not ok then error(reason,0) end
    end
    panel:SetScript("OnUpdate",function(self,elapsed)
        total=total+elapsed;if total<S.updateInterval() then return end;total=0
        local ok,err=pcall(S.performance.enabled and renderProfiled or render);paladin.lastPreviewError=not ok and S.describe(err) or nil
        if not ok then S.publishTransportPacket(ns.wire.ids.paladinPreview,nil);S.paladinNativePanel:Hide() end
    end)
    S.profileScript(panel,"OnUpdate","paladin preview")
end
