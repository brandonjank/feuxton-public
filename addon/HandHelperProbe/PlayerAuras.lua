-- Native player-aspect widgets and flags.
local _, ns = ...
local S = ns.state

-- Optional player-buff extension. Native widgets render the player's auras;
-- no aura contents or protected visibility are inspected by addon Lua.
do
    local panel=CreateFrame("Frame",nil,S.hud)
    S.playerPanel=panel
    panel:SetPoint("TOPLEFT",S.hud,"TOPLEFT",0,-248); panel:SetSize(668,68)
    S.hud:SetClampRectInsets(0,0,0,-202)
    local bg=panel:CreateTexture(nil,"BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0,0,0,1)
    for i,color in ipairs({{0,1,1},{1,1,0},{1,0,1}}) do
        local dot=panel:CreateTexture(nil,"OVERLAY"); dot:SetSize(4,4)
        dot:SetPoint("TOPLEFT",4+(i-1)*6,0); dot:SetColorTexture(color[1],color[2],color[3],1)
    end
    local combat=panel:CreateTexture(nil,"OVERLAY"); combat:SetSize(8,8); combat:SetPoint("TOPLEFT",12,-14)
    local moving=panel:CreateTexture(nil,"OVERLAY"); moving:SetSize(8,8); moving:SetPoint("TOPLEFT",94,-14)
    for i,name in ipairs({"COMBAT","MOVING"}) do
        local label=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    S.bridgeLabel(label)
        label:SetPoint("TOPLEFT",24+(i-1)*82,-14); label:SetText(name)
    end
    local readyDot=panel:CreateTexture(nil,"OVERLAY"); readyDot:SetSize(4,4); readyDot:SetPoint("TOPLEFT",638,-16)
    local nonce=math.random(1,16777215)
    local sessionDot=panel:CreateTexture(nil,"OVERLAY"); sessionDot:SetSize(4,4); sessionDot:SetPoint("TOPLEFT",648,-16)
    sessionDot:SetColorTexture(math.floor(nonce/65536)/255,math.floor(nonce/256)%256/255,nonce%256/255,1)
    local specs={
        {key="hunter.aspectHawk",name="Aspect of the Hawk",short="Hawk",base=13165,x=200,ids={13165,14318,14319,14320,14321,14322,25296}},
        {key="hunter.aspectCheetah",name="Aspect of the Cheetah",short="Cheetah",base=5118,x=340,ids={5118}},
        {key="hunter.aspectMonkey",name="Aspect of the Monkey",short="Monkey",base=13163,x=480,ids={13163}},
    }
    ns.playerBuffSpecs=specs
    for _,spec in ipairs(specs) do
        spec.icon=panel:CreateTexture(nil,"ARTWORK"); spec.icon:SetSize(24,24); spec.icon:SetPoint("TOPLEFT",spec.x,-12)
        spec.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        local backing=panel:CreateTexture(nil,"ARTWORK"); backing:SetSize(12,12); backing:SetPoint("TOPLEFT",spec.x+28,-12)
        backing:SetColorTexture(0,0.25,1,1)
        spec.learnedDot=panel:CreateTexture(nil,"OVERLAY"); spec.learnedDot:SetSize(4,4); spec.learnedDot:SetPoint("TOPLEFT",spec.x+128,-16)
        local label=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); label:SetPoint("TOPLEFT",spec.x+44,-12); label:SetText(spec.short)
    S.bridgeLabel(label)
        spec.binding=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); spec.binding:SetPoint("TOPLEFT",spec.x+44,-26); spec.binding:SetText("--")
        -- Keep the readiness dial above the panel backdrop; the native cooldown draws its swipe above it.
        spec.dial=panel:CreateTexture(nil,"ARTWORK"); spec.dial:SetSize(22,22); spec.dial:SetPoint("TOPLEFT",spec.x+104,-13)
        spec.cooldown=CreateFrame("Cooldown",nil,panel,"CooldownFrameTemplate"); spec.cooldown:SetAllPoints(spec.dial)
        spec.cooldown:SetDrawEdge(false); spec.cooldown:SetDrawSwipe(true); spec.cooldown:SetSwipeColor(0,0,0,1); spec.cooldown:SetHideCountdownNumbers(true)
        spec.warning=panel:CreateTexture(nil,"OVERLAY"); spec.warning:SetSize(4,4); spec.warning:SetPoint("TOPLEFT",spec.x+28,-30)
        spec.warningSource=panel:CreateTexture(nil,"OVERLAY"); spec.warningSource:SetSize(4,4); spec.warningSource:SetPoint("TOPLEFT",spec.x+34,-30)
    end
    for _,spec in ipairs(specs) do S.attachSpellUse(panel,spec.icon,spec.key) end
    S.refreshSpellUse()
    local native,filtered,ready,errorText
    local settledAt=GetTime()+0.6
    local ok,err=pcall(function()
        native=CreateFrame("AuraContainer",nil,panel,"CustomAuraContainerTemplate")
        native:SetPoint("TOPLEFT",12,-40); native:SetSize(624,24)
        local layout={elementWidth=24,elementHeight=24,elementSpacing=2,lineSpacing=2}
        native:AddAuraGroup("playerBuffs","HELPFUL",{maxFrameCount=24,candidateFilters={},layout=layout,
            initializeFrame=function(button)
                button:SetSize(24,24); button:EnableMouse(false)
                local icon=button:CreateTexture(nil,"ARTWORK"); icon:SetAllPoints(button); button:SetIcon(icon)
                local dot=button:CreateTexture(nil,"OVERLAY"); dot:SetSize(4,4); dot:SetPoint("TOPRIGHT",button,"TOPRIGHT",0,5); dot:SetColorTexture(0,1,0,1)
            end})
        native:SetAuraGroupLayout("playerBuffs",layout); native:SetFlowLayoutAnchorPoint("TOPLEFT")
        native:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right,AnchorUtil.FlowDirection.Down)
        native:SetFlowLayoutMaximumLineSize(624); native:SetUnit("player"); native:SetEnabled(true)
        filtered=CreateFrame("AuraContainer",nil,panel,"CustomAuraContainerTemplate")
        filtered:SetAllPoints(panel)
        for _,spec in ipairs(specs) do
            local ids={}; for _,id in ipairs(spec.ids) do ids[id]=true end
            local slotX=spec.x+28
            filtered:AddAuraSlot(spec.key,"HELPFUL",{candidateFilters={includeSpellIDs=ids},initializeFrame=function(button)
                button:SetSize(12,12); button:SetPoint("TOPLEFT",filtered,"TOPLEFT",slotX,-12); button:EnableMouse(false)
                local icon=button:CreateTexture(nil,"ARTWORK"); icon:SetAllPoints(button); button:SetIcon(icon)
                local signal=button:CreateTexture(nil,"OVERLAY"); signal:SetAllPoints(button); signal:SetColorTexture(0,1,0,1)
            end})
        end
        filtered:SetUnit("player"); filtered:SetEnabled(true); ready=true
    end)
    if not ok then errorText=S.describe(err); if native then pcall(native.Hide,native) end; if filtered then pcall(filtered.Hide,filtered) end end
    local function resolve()
        if S.readableCall(InCombatLockdown)~=false then return end
        for _,spec in ipairs(specs) do
            local info=S.readableCall(S.spellAPI.GetSpellInfo,spec.name)
            if type(info)~="table" then info=S.readableCall(S.spellAPI.GetSpellInfo,spec.base) end
            spec.spellID=S.safeField(info,"spellID"); spec.spellName=S.safeField(info,"name")
            local icon=S.safeField(info,"iconID"); if icon then spec.icon:SetTexture(icon) end
            spec.known=type(spec.spellID)=="number" and S.readableCall(S.bookAPI.IsSpellKnown,spec.spellID) or nil
            if type(spec.known)~="boolean" and type(spec.spellID)=="number" then spec.known=S.readableCall(IsSpellKnown,spec.spellID) end
            S.drawFlag(spec.learnedDot,spec.known)
        end
        S.discoverBindings()
    end
    panel:RegisterEvent("PLAYER_LOGIN"); panel:RegisterEvent("SPELLS_CHANGED"); panel:RegisterEvent("SPELL_DATA_LOAD_RESULT"); panel:RegisterEvent("PLAYER_REGEN_ENABLED")
    panel:SetScript("OnEvent",function() local eventOK,eventError=pcall(resolve); if not eventOK then errorText=S.describe(eventError) end end)
    local elapsedTotal=0
    panel:SetScript("OnUpdate",function(self,elapsed)
        elapsedTotal=elapsedTotal+elapsed; if elapsedTotal<S.updateInterval() then return end; elapsedTotal=0
        S.drawFlag(combat,S.readableCall(UnitAffectingCombat,"player"))
        ns.features.RangeTracking.movement(moving)
        S.drawFlag(readyDot,ready==true and GetTime()>=settledAt)
        for _,spec in ipairs(specs) do
            pcall(S.renderCooldown,spec)
            local selected=S.bindingsValid and S.preferredMapping(spec.mappings)
            local button=selected and selected.button
            local slot=button and S.readableCall(function() return button.action end)
            local valid=button and slot==selected.slot and S.readableCall(button.IsVisible,button)==true
            local source=valid and S.mirrorColor(spec.warning,button.icon or button.Icon,"GetVertexColor") or false
            if selected and selected.managed then
                spec.nativeSignals=spec.nativeSignals or {spec.warning,spec.warningSource,spec.warning,spec.warningSource}
                local _,usable=ns.features.RangeTracking.render(spec.nativeSignals,selected.id,"player");source=usable
            end
            S.drawFlag(spec.warningSource,source); if not source then spec.warning:SetColorTexture(1,0.65,0,1) end
        end
    end)
    local report=ns.hudReport
    ns.hudReport=function(add) report(add); add("Player aura widget ready",S.describe(ready)); if errorText then add("Player aura widget error",errorText) end end
    resolve()
end

