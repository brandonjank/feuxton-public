-- Paladin catalog, capability probe and class observation transport.
local _, ns = ...
local paladin={}
ns.classes.PALADIN=paladin
paladin.bridgeLayout={key="paladin-v2",height=300,native=28,units=68,activity=90,resources=102,setup=138,core=150,guide=162,roster=178,classPacket=280}
paladin.denseBridgeLayout={key="paladin-dense-v4",height=132,gauges=68,native=28,units=68,unitHeight=28,activity=14,headerActivity=true,resources=68,setup=96,grid=96,roster=96,coreStamp=108,targetStamp=122,marker={1,0.25,0.5}}
paladin.specs={
 {key="paladin.holyStrike",name="Holy Strike"},
 {key="paladin.judgement",name="Judgement"},
 {key="paladin.consecration",name="Consecration"},
 {key="paladin.sealRighteousness",name="Seal of Righteousness",unit="player"},
 {key="paladin.sealCommand",name="Seal of Command",unit="player"},
 {key="paladin.sealCrusader",name="Seal of the Crusader",unit="player"},
 {key="paladin.sealFury",name="Seal of Fury",unit="player"},
 {key="paladin.righteousFury",name="Righteous Fury",unit="player"},
 {key="paladin.holyLight",name="Holy Light",healing=true},
 {key="paladin.flashLight",name="Flash of Light",healing=true},
 {key="paladin.blessingMight",name="Blessing of Might"},
 {key="paladin.blessingWisdom",name="Blessing of Wisdom"},
 {key="paladin.blessingKings",name="Blessing of Kings"},
 {key="paladin.devotionAura",name="Devotion Aura",unit="player"},
 {key="paladin.retributionAura",name="Retribution Aura",unit="player"},
 {key="paladin.hammerJustice",name="Hammer of Justice"},
 {key="paladin.exorcism",name="Exorcism"},
 {key="paladin.purify",name="Purify"},
 {key="paladin.divineProtection",name="Divine Protection",unit="player"},
 {key="paladin.divineShield",name="Divine Shield",unit="player"},
 {key="paladin.layHands",name="Lay on Hands"},
 {key="paladin.autoAttack",name="Attack",startAttack=true},
}
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
            spell.usable=group.read(api.IsSpellUsable or IsUsableSpell,1,id.value)
            spell.insufficientPower=group.read(api.IsSpellUsable or IsUsableSpell,2,id.value)
            spell.targetRange=group.read(api.IsSpellInRange or IsSpellInRange,1,api.IsSpellInRange and id.value or spec.name,"target")
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
    local lines={"Hand Helper Paladin/party capability probe", "Class: "..signal(snapshot.class).." | Level: "..signal(snapshot.level).." | Combat: "..signal(snapshot.combat),"Main-hand attack speed (may include haste): "..signal(snapshot.mainHandAttackSpeed),"Main-hand item: "..signal(snapshot.mainHandItem).." | Offhand item: "..signal(snapshot.shieldItem)}
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
SLASH_HANDHELPERPALADIN1="/hhpaladinprobe"
SlashCmdList.HANDHELPERPALADIN=function()
    local ok,text=pcall(paladin.report)
    if not ok then print("Hand Helper: Paladin/party probe failed.");return end
    if type(HandHelperProbeDB)~="table" then HandHelperProbeDB={} end
    HandHelperProbeDB.paladinPartyReport=text
    HandHelperProbeDB.paladinPartyReportAt=type(GetServerTime)=="function" and ns.features.GroupContext.read(GetServerTime,1) or nil
    HandHelperProbeDB.paladinPartyReportVersion=2
    local S=ns.state
    if not S.panel or not S.edit then print("Hand Helper: diagnostic window not ready.");return end
    S.edit:SetText(text);S.panel:Show();S.edit:SetFocus();S.edit:HighlightText()
end
end


-- HHP5 observation stream. The desktop owns foreground-only input; Lua sends no casts.
paladin.previewKeys={"holyStrike","judgement","sealRighteousness","sealCommand","sealCrusader","holyLight","sealFury","consecration","hammerJustice","devotionAura"}
paladin.packetKeys={}
for i,key in ipairs(paladin.previewKeys) do paladin.packetKeys[i]=key end
paladin.packetKeys[11]="retributionAura"
paladin.packetKeys[12]="righteousFury";paladin.packetKeys[13]="layHands";paladin.packetKeys[14]="divineProtection"
function paladin.bindingCode(key)
    if type(key)~="string" then return 0 end
    key=string.upper(key);local flags=0
    while true do
        local bit,prefix
        if key:sub(1,4)=="ALT-" then bit,prefix=1,4 elseif key:sub(1,5)=="CTRL-" then bit,prefix=2,5 elseif key:sub(1,6)=="SHIFT-" then bit,prefix=4,6 else break end
        if math.floor(flags/bit)%2==1 then return 0 end
        flags=flags+bit;key=key:sub(prefix+1)
    end
    local code=#key==1 and key:byte() or 0
    if not (code>=65 and code<=90 or code>=48 and code<=57) then
        local fn=tonumber(key:match("^F(%d+)$"));local special={SPACE=32,["-"]=189,["="]=187,["["]=219,["]"]=221,[";"]=186,["'"]=222,[","]=188,["."]=190,["/"]=191}
        local pad=tonumber(key:match("^NUMPAD(%d)$"))
        code=pad and 96+pad or fn and fn>=1 and fn<=12 and 111+fn or special[key] or 0
    end
    return code>0 and flags*256+code or 0
end
-- Restricted remaining time goes directly through the native color API. Lua
-- never compares or serializes it. Orange means no supported rendering path.
function paladin.renderHealWindows(readings,healMs,S)
    for i=1,2 do
        local tile=paladin.nativeTiles[i];local pixel=tile.healWindow
        if not pixel then pixel=S.paladinNativePanel:CreateTexture(nil,"OVERLAY");pixel:SetSize(4,4);pixel:SetPoint("TOPLEFT",12+(i-1)*46+30,-32);tile.healWindow=pixel end
        pixel:SetColorTexture(1,.65,0,1)
        if healMs>0 then pcall(function()
            local rate=(S.updateRateMs or 100)/1000
            local threshold=healMs/1000+.35+rate+math.max(.25,math.min(1.5,3*rate))
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
local auraSlots={[3]=true,[4]=true,[5]=true,[7]=true,[10]=true,[11]=true,[12]=true,[14]=true}

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

local function initializeNative(S)
    local panel=CreateFrame("Frame",nil,S.hud);S.paladinNativePanel=panel
    panel:SetSize(668,40);panel:SetPoint("TOPLEFT",S.hud,"TOPLEFT",0,-626);panel:Hide()
    local bg=panel:CreateTexture(nil,"BACKGROUND");bg:SetAllPoints();bg:SetColorTexture(0,0,0,1)
    for i,color in ipairs({{0,1,1},{1,0.5,0},{1,0,1}}) do
        local dot=panel:CreateTexture(nil,"OVERLAY");dot:SetSize(4,4);dot:SetPoint("TOPLEFT",4+(i-1)*6,0);dot:SetColorTexture(color[1],color[2],color[3],1)
    end
    paladin.nativeStamp={};paladin.nativeTiles={}
    for i=1,4 do
        local dot=panel:CreateTexture(nil,"OVERLAY");dot:SetSize(4,4);dot:SetPoint("TOPLEFT",626+(i-1)*6,0);paladin.nativeStamp[i]=dot
    end
    for i=1,14 do
        local tile={};local x=12+(i-1)*46
        tile.icon=panel:CreateTexture(nil,"ARTWORK");tile.icon:SetSize(16,16);tile.icon:SetPoint("TOPLEFT",x,-6)
        tile.dial=panel:CreateTexture(nil,"BACKGROUND");tile.dial:SetSize(16,16);tile.dial:SetPoint("TOPLEFT",x+18,-6)
        tile.cooldown=CreateFrame("Cooldown",nil,panel,"CooldownFrameTemplate");tile.cooldown:SetAllPoints(tile.dial)
        tile.cooldown:SetDrawEdge(false);tile.cooldown:SetDrawSwipe(true);tile.cooldown:SetSwipeColor(0,0,0,1);tile.cooldown:SetHideCountdownNumbers(true)
        tile.aura=panel:CreateTexture(nil,"ARTWORK");tile.aura:SetSize(8,8);tile.aura:SetPoint("TOPLEFT",x+36,-6);tile.aura:SetColorTexture(0,0.25,1,1)
        tile.visualSignals={}
        for j=1,4 do
            local dot=panel:CreateTexture(nil,"OVERLAY");dot:SetSize(4,4);dot:SetPoint("TOPLEFT",x+(j-1)*6,-32);tile.visualSignals[j]=dot
        end
        paladin.nativeTiles[i]=tile
        local useButton=S.attachSpellUse(panel,tile.icon,"paladin."..paladin.packetKeys[i])
        -- Keep the switch marker inside the compact icon. The shared outside
        -- marker would overlap two columns of this tile's cooldown renderer.
        useButton.useDot:ClearAllPoints()
        useButton.useDot:SetPoint("TOPRIGHT",tile.icon,"TOPRIGHT",0,0)
    end
end

local function renderNative(tile,bound,learned,chosen,info,S)
    tile.spellID=bound>0 and bound or nil;tile.known=learned.status=="observed" and learned.value or false
    tile.icon:SetTexture(S.safeField(info,"iconID") or "Interface\\Icons\\INV_Misc_QuestionMark")
    S.renderCooldown(tile)
    local button=chosen and chosen.kind=="spell" and chosen.button
    local visible=button and S.readableCall(button.IsVisible,button)==true
    local slot=button and S.safeField(button,"action")
    local valid=visible and slot==chosen.slot
    local rangeOK,usableOK=false,false
    if chosen and chosen.managed then
        rangeOK,usableOK=ns.features.RangeTracking.render(tile.visualSignals,bound,chosen.unit)
    elseif valid then
        local hotkey=button.HotKey
        if type(hotkey)~="table" and type(hotkey)~="userdata" then hotkey=nil end
        local method=hotkey and type(hotkey.GetVertexColor)=="function" and "GetVertexColor" or "GetTextColor"
        rangeOK=S.mirrorColor(tile.visualSignals[1],hotkey,method)
        local icon=button.icon or button.Icon
        if type(icon)=="table" or type(icon)=="userdata" then usableOK=S.mirrorColor(tile.visualSignals[3],icon,"GetVertexColor") end
    end
    S.drawFlag(tile.visualSignals[2],rangeOK);S.drawFlag(tile.visualSignals[4],usableOK)
    -- Cyan certifies a direct spell-range result; legacy non-red bar text
    -- alone cannot prove that a spell has a meaningful range check.
    if chosen and chosen.managed and rangeOK then tile.visualSignals[2]:SetColorTexture(0,1,1,1) end
    if not rangeOK then tile.visualSignals[1]:SetColorTexture(1,0.65,0,1) end
    if not usableOK then tile.visualSignals[3]:SetColorTexture(1,0.65,0,1) end
end

local function refreshNativeAuras(readings,S)
    local signature={tostring(S.setupKnownSpellRevision or 0),S.setupBookAvailable==true and "complete" or "partial"}
    for i,reading in ipairs(readings) do signature[#signature+1]=reading.name..":"..reading.bound..":"..tostring(reading.learned)..":"..tostring(reading.auraID or 0) end
    signature=table.concat(signature,"|")
    if signature==paladin.auraSignature then return end
    if S.readableCall(InCombatLockdown)~=false then
        paladin.auraSignature=nil;paladin.auraMask=0;paladin.auraAbsenceMask=0
        return
    end
    paladin.auraSignature=signature;paladin.auraMask=0;paladin.auraAbsenceMask=0;paladin.auraSettledAt=GetTime()+0.6
    if paladin.nativeAuras then
        pcall(paladin.nativeAuras.SetEnabled,paladin.nativeAuras,false);pcall(paladin.nativeAuras.SetUnit,paladin.nativeAuras,nil);pcall(paladin.nativeAuras.Hide,paladin.nativeAuras)
        paladin.nativeAuras=nil
    end
    local container
    local ok=pcall(function()
        container=CreateFrame("AuraContainer",nil,S.paladinNativePanel,"CustomAuraContainerTemplate");container:SetAllPoints(S.paladinNativePanel)
        local mask,absence=0,0
        for i,reading in ipairs(readings) do
            if auraSlots[i] and reading.learned==true then
                local ids={[reading.bound]=true}
                for _,spell in ipairs(S.setupKnownSpells or {}) do if spell.name==reading.name then ids[spell.id]=true end end
                -- A public player aura identifies this server's actual aura ID,
                -- which can differ from the cast ID. Include it in the native
                -- filter before certifying its blue background as absence.
                if reading.auraID then ids[reading.auraID]=true;absence=absence+2^(i-1) end
                local slotX=12+(i-1)*46+36
                container:AddAuraSlot("paladin."..paladin.packetKeys[i],"HELPFUL",{candidateFilters={includeSpellIDs=ids},initializeFrame=function(button)
                    button:SetSize(8,8);button:SetPoint("TOPLEFT",container,"TOPLEFT",slotX,-6);button:EnableMouse(false)
                    local icon=button:CreateTexture(nil,"ARTWORK");icon:SetAllPoints(button);button:SetIcon(icon)
                    local signal=button:CreateTexture(nil,"OVERLAY");signal:SetAllPoints(button);signal:SetColorTexture(0,1,0,1)
                end})
                mask=mask+2^(i-1)
            end
        end
        container:SetUnit("player");container:SetEnabled(true);paladin.auraMask=mask;paladin.auraAbsenceMask=absence
    end)
    if ok then paladin.nativeAuras=container
    elseif container then pcall(container.SetEnabled,container,false);pcall(container.Hide,container) end
end

function paladin.initializePreview()
    local S=ns.state;local group=ns.features.GroupContext
    local panel=CreateFrame("Frame",nil,S.hud);S.paladinPanel=panel;panel:SetSize(668,12);panel:SetPoint("TOPLEFT",S.hud,"TOPLEFT",0,-614)
    local background=panel:CreateTexture(nil,"BACKGROUND");background:SetAllPoints();background:SetColorTexture(0,0,0,1)
    local cells=group.cells(panel,24,0,160,3)
    initializeNative(S)
    local tick,total,weaponRetry=0,0,0
    panel:RegisterEvent("PLAYER_LOGIN");panel:RegisterEvent("PLAYER_EQUIPMENT_CHANGED");panel:RegisterEvent("PLAYER_REGEN_ENABLED")
    panel:SetScript("OnEvent",function(self,event,slot)
        if event=="PLAYER_EQUIPMENT_CHANGED" and (S.isSecret(slot) or slot~=16) then return end
        if event=="PLAYER_REGEN_ENABLED" and (paladin.weaponDelayMs or 0)>0 then return end
        if group.text(group.read(UnitClass,2,"player"),16)=="PALADIN" then pcall(paladin.refreshWeapon) end
    end)
    local function render()
        if group.text(group.read(UnitClass,2,"player"),16)~="PALADIN" then group.paint(cells,"");S.publishTransportPacket(3,nil);S.paladinNativePanel:Hide();return end
        S.paladinNativePanel:Show()
        if GetTime()>=weaponRetry and (paladin.weaponDelayMs or 0)==0 and S.readableCall(InCombatLockdown)==false then paladin.refreshWeapon();weaponRetry=GetTime()+1 end
        local api=type(C_Spell)=="table" and C_Spell or {};local book=type(C_SpellBook)=="table" and C_SpellBook or {}
        tick=(tick+1)%4294967296
        local level=group.read(UnitLevel,1,"player");level=level.status=="observed" and type(level.value)=="number" and level.value>=1 and level.value<=100 and math.floor(level.value)==level.value and level.value or 0
        local packet="HHP7"..S.bytes(S.setupSession,4)..S.bytes(tick,4)..S.bytes(level,1)..S.bytes(S.updateRateMs,2)..S.bytes(S.bindingsValid and 2 or 0,1)
        -- One guarded scan for all abilities. A restricted/incomplete list is not absence.
        local auras,auraIDs,complete={},{},false
        if type(C_UnitAuras)=="table" and type(C_UnitAuras.GetAuraDataByIndex)=="function" then
            for i=1,40 do
                local ok,aura=pcall(C_UnitAuras.GetAuraDataByIndex,"player",i,"HELPFUL")
                if not ok or S.isSecret(aura) then break end
                if aura==nil then complete=true;break end
                local name=group.text(group.field(aura,"name"),80)
                if name=="" then break end;auras[name]=true
                local auraID=group.field(aura,"spellId")
                if auraID.status=="observed" and type(auraID.value)=="number" and auraID.value>0 and auraID.value<2147483648 and math.floor(auraID.value)==auraID.value then auraIDs[name]=auraID.value end
            end
        end
        paladin.rangeSpecs={};local nativeReadings={}
        for index,shortKey in ipairs(paladin.packetKeys) do
            local spec
            for _,entry in ipairs(paladin.specs) do if entry.key=="paladin."..shortKey then spec=entry;break end end
            local ok,info=pcall(api.GetSpellInfo or function() end,spec.name)
            local id=ok and group.field(info,"spellID") or {};id=id.status=="observed" and type(id.value)=="number" and id.value>0 and math.floor(id.value)==id.value and id.value or 0
            local chosen
            if S.bindingsValid then for _,mapping in ipairs(S.setupMappings or {}) do
                if ((mapping.id==id and id>0) or mapping.name==spec.name) and (mapping.managed and S.mappingCurrent(mapping) or not mapping.managed and not mapping.invalidated and S.specialMappingCurrent(mapping)) then
                    if mapping.key and (not chosen or (chosen.kind~="spell" and mapping.kind=="spell")) then chosen=mapping end
                end
            end end
            local visualChosen=chosen
            if shortKey=="layHands" then
                local entry=ns.features.Healing.assignments[17]
                if entry and entry.key and entry.button.hhSpellID then chosen={key=entry.key,id=entry.button.hhSpellID,slot=1,kind="spell"} else chosen=nil end
            end
            local key=chosen and chosen.key or "";local keyCode=paladin.bindingCode(key)
            if keyCode==0 then chosen=nil end
            local bound=chosen and chosen.id or id;bound=type(bound)=="number" and bound>0 and bound==math.floor(bound) and bound or 0
            local learned=bound>0 and group.read(book.IsSpellKnown or IsSpellKnown,1,bound) or {}
            local usable=bound>0 and group.read(api.IsSpellUsable or IsUsableSpell,1,bound) or {}
            local mana=bound>0 and group.read(api.IsSpellUsable or IsUsableSpell,2,bound) or {}
            local range=bound>0 and group.read(api.IsSpellInRange or IsSpellInRange,1,api.IsSpellInRange and bound or spec.name,"target") or {}
            local ready={}
            if bound>0 and type(api.GetSpellCooldown)=="function" then
                local cdOK,cd=pcall(api.GetSpellCooldown,bound)
                local start=cdOK and group.field(cd,"startTime") or {};local duration=cdOK and group.field(cd,"duration") or {};local enabled=cdOK and group.field(cd,"isEnabled") or {}
                if start.status=="observed" and duration.status=="observed" and type(start.value)=="number" and type(duration.value)=="number" and enabled.status=="observed" and enabled.value==true then
                    ready={status="observed",value=duration.value==0 or start.value+duration.value<=GetTime()}
                end
            end
            local aura=auras[spec.name] and {status="observed",value=true} or complete and {status="observed",value=false} or {}
            local flags=0
            for i,value in ipairs({learned,usable,mana,range,ready,aura}) do flags=flags+group.code(value)*4^(i-1) end
            packet=packet..S.bytes(bound,4)..S.bytes(chosen and chosen.slot or 0,2)..S.bytes(chosen and (chosen.kind=="spell" and 1 or 2) or 0,1)..S.bytes(keyCode,2)..S.bytes(flags,2)
            if index<=14 then renderNative(paladin.nativeTiles[index],bound,learned,visualChosen,ok and not S.isSecret(info) and info or nil,S) end
            paladin.verifiedAuraIDs=paladin.verifiedAuraIDs or {}
            local family=spec.key..":"..bound
            if learned.status=="observed" and learned.value==true and auraIDs[spec.name] and S.readableCall(InCombatLockdown)==false then paladin.verifiedAuraIDs[family]=auraIDs[spec.name] end
            if index<=14 then nativeReadings[index]={name=spec.name,bound=bound,learned=learned.status=="observed" and learned.value or false,auraID=paladin.verifiedAuraIDs[family]} end
            if spec.healing and bound>0 and learned.value==true then paladin.rangeSpecs[#paladin.rangeSpecs+1]={id=bound,name=spec.name} end
        end
        local movement=group.read(GetUnitSpeed,1,"player");movement=movement.status=="observed" and type(movement.value)=="number" and {status="observed",value=movement.value>0} or {}
        packet=packet..S.bytes(group.code(movement),1)..S.bytes(group.code(group.read(UnitAffectingCombat,1,"player")),1)..S.bytes(group.code(group.read(IsMounted,1)),1)..S.bytes(group.code(group.read(UnitOnTaxi,1,"player")),1)
        refreshNativeAuras(nativeReadings,S)
        local auraMask=GetTime()>=(paladin.auraSettledAt or math.huge) and (paladin.auraMask or 0) or 0
        -- Absence is available only for a native filter built with an actual
        -- public player aura identity for this bound spell rank.
        local absenceMask=auraMask~=0 and (paladin.auraAbsenceMask or 0) or 0
        packet=packet..S.bytes(paladin.weaponID or 0,4)..S.bytes(paladin.weaponDelayMs or 0,2)..S.bytes(auraMask,2)..S.bytes(absenceMask,2)
        local usage=0
        for i,key in ipairs(paladin.packetKeys) do usage=usage+S.spellUseCode("paladin."..key)*4^(i-1) end
        packet=packet..S.bytes(S.auraGeneration,1)..S.bytes(usage,4)..S.executionBytes(2)
        -- Instance type is public context; unavailable/secret values stay unknown.
        local inside=group.read(IsInInstance,1);local kind=group.read(IsInInstance,2)
        local dungeon={}
        if inside.status=="observed" and type(inside.value)=="boolean" then
            if inside.value==false then dungeon={status="observed",value=false}
            elseif kind.status=="observed" and type(kind.value)=="string" and kind.value~="" then dungeon={status="observed",value=kind.value=="party"} end
        end
        packet=packet..S.bytes(group.code(dungeon),1)
        local healInfo=group.read(function() return api.GetSpellInfo(nativeReadings[6].bound).castTime end,1)
        local healMs=healInfo.status=="observed" and type(healInfo.value)=="number" and healInfo.value>0 and healInfo.value<=10000 and math.floor(healInfo.value)==healInfo.value and healInfo.value or 0
        paladin.renderHealWindows(nativeReadings,healMs,S)
        local cancel=ns.features.Healing.assignments[18]
        local cancelKey=cancel and cancel.key and not ns.keyPolicy.reason(cancel.key) and GetBindingAction(cancel.key,true)=="CLICK "..cancel.name..":LeftButton" and paladin.bindingCode(cancel.key) or 0
        packet=packet..S.bytes(healMs,2)..S.bytes(cancelKey,2)
        local attackKey=0
        if S.bindingsValid then for _,mapping in ipairs(S.setupMappings or {}) do
            if mapping.id==6603 and mapping.startAttack and S.mappingCurrent(mapping) then attackKey=paladin.bindingCode(mapping.key);break end
        end end
        local attacking=group.read(api.IsCurrentSpell or IsCurrentSpell,1,6603)
        if attacking.status~="observed" and type(S.meleeActive)=="boolean" then attacking={status="observed",value=S.meleeActive} end
        packet=packet..S.bytes(group.code(attacking),1)..S.bytes(attackKey,2)..S.bytes(S.spellUseCode("paladin.autoAttack"),1)
        local stopEntry=S.managedSpells and S.managedSpells.entries["PALADIN:Hand Helper Stop Casting"]
        local stopKey=S.bindingsValid and S.managedSpells.current(stopEntry) and paladin.bindingCode(stopEntry.key) or 0
        packet=packet..S.bytes(stopKey,2)
        local checksum=S.adler32(packet)
        for i,dot in ipairs(paladin.nativeStamp) do local value=math.floor(checksum/256^(i-1))%256/255;dot:SetColorTexture(value,value,value,1) end
        packet=packet..S.bytes(checksum,4);assert(#packet<=357);group.paint(cells,packet)
        S.publishTransportPacket(3,packet)
    end
    panel:SetScript("OnUpdate",function(self,elapsed)
        total=total+elapsed;if total<S.updateInterval() then return end;total=0
        local ok,err=pcall(render);paladin.lastPreviewError=not ok and S.describe(err) or nil
        if not ok then group.paint(cells,"");S.publishTransportPacket(3,nil);S.paladinNativePanel:Hide() end
    end)
    S.profileScript(panel,"OnUpdate","paladin preview")
end
