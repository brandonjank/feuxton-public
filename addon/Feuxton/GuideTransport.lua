-- HHG6 guide widgets, Hawk count, cast receipts and readiness flags.
local _, ns = ...
local S = ns.state

-- Guide supplement: all spell widgets use the same native rendering path.
-- Hawk count stays unknown until this session has actually observed a Hawk slot.
do
    local observedHawkSlot=false
    local function hawkCount()
        if type(GetTotemInfo)~="function" then return nil end
        local count=0
        for slot=1,4 do
            local ok,present,name=pcall(GetTotemInfo,slot)
            if not ok or S.isSecret(present) or S.isSecret(name) or type(present)~="boolean" then return nil end
            if present then
                if type(name)~="string" then return nil end
                if string.find(string.lower(name),"hawk",1,true) then count=count+1 end
            end
        end
        if count>0 then observedHawkSlot=true end
        if not observedHawkSlot or count>2 then return nil end
        return count
    end
    ns.guideHawkCount=hawkCount
    local panel=CreateFrame("Frame",nil,S.hud)
    S.guidePanel=panel
    panel:SetPoint("TOPLEFT",S.hud,"TOPLEFT",0,-492); panel:SetSize(668,16)
    -- Read-only event receipts. Secret spell IDs are omitted, never inferred.
    local probeTick,eventSequence=0,0
    local receipts={}
    local function readinessPublic(value)
        if type(issecretvalue)~="function" then return false end
        local ok,secret=pcall(issecretvalue,value)
        return ok and not secret
    end
    local worldReady=true
    local eventKinds={UNIT_SPELLCAST_START=1,UNIT_SPELLCAST_SUCCEEDED=2,UNIT_SPELLCAST_FAILED=3,UNIT_SPELLCAST_INTERRUPTED=4,UNIT_SPELLCAST_CHANNEL_START=5,UNIT_SPELLCAST_CHANNEL_STOP=6}
    local eventsAvailable=type(issecretvalue)=="function"
    local eventFrame=CreateFrame("Frame",nil,S.hud)
    for event in pairs(eventKinds) do if not pcall(eventFrame.RegisterEvent,eventFrame,event) then eventsAvailable=false end end
    for _,event in ipairs({"PLAYER_LEAVING_WORLD","PLAYER_ENTERING_WORLD"}) do pcall(eventFrame.RegisterEvent,eventFrame,event) end
    eventFrame:SetScript("OnEvent",function(self,event,unit,castGUID,spellID)
        if event=="PLAYER_LEAVING_WORLD" then worldReady=false; return end
        if event=="PLAYER_ENTERING_WORLD" then worldReady=true; return end
        if not readinessPublic(unit) or unit~="player" or not readinessPublic(spellID) then return end
        local id=S.setupNumber(spellID)
        if not id or id<=0 or id~=math.floor(id) then return end
        local at=S.setupNumber(S.readableCall(GetTime))
        if not at then return end
        eventSequence=(eventSequence+1)%4294967296
        receipts[#receipts+1]={sequence=eventSequence,kind=eventKinds[event],id=id,generation=S.auraGeneration,at=at}
        if #receipts>4 then table.remove(receipts,1) end
    end)
    S.executionBytes=function(count)
        local packet=""
        local focusCode=0
        if type(GetCurrentKeyBoardFocus)=="function" then
            local ok,focus=pcall(GetCurrentKeyBoardFocus)
            if ok and readinessPublic(focus) then focusCode=focus==nil and 1 or 2 end
        end
        packet=packet..S.bytes(focusCode+(worldReady and 4 or 8)+(eventsAvailable and 16 or 0),1)
        local mounted=S.readableCall(IsMounted)
        local taxi=S.readableCall(UnitOnTaxi,"player")
        local mountedCode=readinessPublic(mounted) and (mounted==true and 2 or mounted==false and 1 or 0) or 0
        local taxiCode=readinessPublic(taxi) and (taxi==true and 2 or taxi==false and 1 or 0) or 0
        packet=packet..S.bytes(mountedCode+taxiCode*4,1)
        local now=S.setupNumber(S.readableCall(GetTime))
        for index=1,count do
            local receipt=receipts[(count==4 and 0 or math.max(0,#receipts-count))+index]
            local age=receipt and now and math.min(65535,math.max(0,math.floor((now-receipt.at)*1000))) or 65535
            packet=packet..S.bytes(receipt and receipt.sequence or 0,4)..S.bytes(receipt and receipt.kind or 0,1)..S.bytes(receipt and receipt.id or 0,4)..S.bytes(receipt and receipt.generation or 0,1)..S.bytes(age,2)
        end
        return packet
    end
    local function render()
        local class=S.setupString(S.setupValue(UnitClass,2,"player"))
        if class~="HUNTER" then
            -- Other classes consume their own ability packet. Keep the shared
            -- enemy-cast source current without querying hidden Hunter tiles.
            probeTick=(probeTick+1)%4294967296
            S.publishTransportPacket(2,nil,true)
            if class=="PALADIN" or class=="SHAMAN" or class=="DRUID" or class=="WARLOCK" then
                local enemyCast=ns.features.Interrupts.bytes()
                S.publishTransportPacket(8,ns.features.Interrupts.packet(probeTick,enemyCast))
            else S.publishTransportPacket(8,nil) end
            return
        end
        local level=S.setupNumber(S.readableCall(UnitLevel,"player")) or 0
        if level<0 or level>100 then level=0 end
        local packet="HHG7"..S.bytes(S.setupSession,4)..S.bytes(S.setupRevision,2)..S.bytes(class=="HUNTER" and 1 or 0,1)..S.bytes(level,1)..S.bytes(S.bindingsValid and 1 or 0,1)..S.bytes(11,1)..S.bytes(S.updateRateMs,2)..S.bytes(S.auraGeneration,1)
        for tileIndex=11,21 do
            local tile=S.tiles[tileIndex]
            local chosen=S.bindingsValid and S.preferredMapping(tile.mappings)
            local valid=S.mappingCurrent(chosen)
            local slot=valid and chosen.slot or 0
            local key=valid and S.setupString(chosen.key) or ""
            if not key or #key>20 then key="" end
            local id=S.setupNumber(S.boundSpellID(tile)) or 0
            local active
            if tile.known==true then active=S.readableCall(S.spellAPI.IsCurrentSpell or IsCurrentSpell,id) end
            local current=active==true and 2 or active==false and 1 or 0
            packet=packet..S.bytes(id,4)..S.bytes(valid and slot or 0,2)..S.bytes(valid and (chosen.kind=="spell" and 1 or 2) or 0,1)..S.bytes(#key,1)..key..S.bytes(S.directSpellFlags(S.hunterSpecs[tileIndex].name,id,tile.known,S.hunterSpecs[tileIndex].unit)+current*64,1)..S.bytes(S.spellUseCode(S.hunterSpecs[tileIndex].key),1)
        end
        local count=hawkCount()
        local threat=S.setupNumber(S.readableCall(UnitThreatSituation,"player","target"))
        if not threat or threat<0 or threat>3 or threat~=math.floor(threat) then threat=255 end
        local targetExists=S.readableCall(UnitExists,"targettarget")
        local onPlayer
        if targetExists==true then onPlayer=S.readableCall(UnitIsUnit,"targettarget","player")
        elseif targetExists==false then onPlayer=false end
        packet=packet..S.bytes(count or 255,1)..S.bytes(threat,1)..S.bytes(onPlayer==true and 2 or onPlayer==false and 1 or 0,1)
        probeTick=(probeTick+1)%4294967296
        packet=packet..S.bytes(probeTick,4)..S.executionBytes(4)
        local enemyCast=ns.features.Interrupts.bytes()
        packet=packet..enemyCast
        if class=="PALADIN" or class=="SHAMAN" or class=="HUNTER" then S.publishTransportPacket(8,ns.features.Interrupts.packet(probeTick,enemyCast),true) end
        for _,tile in ipairs(S.tiles) do packet=packet..S.bytes(ns.features.CastTracking.manaFraction(S.boundSpellID(tile),tile.known),1) end
        for _,spec in ipairs(ns.playerBuffSpecs or {}) do packet=packet..S.bytes(ns.features.CastTracking.manaFraction(S.boundSpellID(spec),spec.known),1) end
        packet=packet..S.bytes(S.adler32(packet),4)
        S.publishTransportPacket(2,packet)
    end
    local total=0
    panel:SetScript("OnUpdate",function(self,elapsed)
        total=total+elapsed; if total<S.updateInterval() then return end; total=0
        local ok=pcall(render)
        if not ok then S.publishTransportPacket(2,nil) end
    end)
    local previous=ns.hudReport
    ns.hudReport=function(add)
        previous(add); add("Guide ability tiles",9); add("Hawk slot count",hawkCount()); add("Hawk slot observed this session",observedHawkSlot)
        add("Player target threat",S.readableCall(UnitThreatSituation,"player","target"))
    end
end

-- The five current packed layouts share this geometry owner. Packet schemas,
-- native witness ownership and secret-value guards remain unchanged.
do
    local function point(widget,parent,x,y)
        widget:ClearAllPoints(); widget:SetPoint("TOPLEFT",parent,"TOPLEFT",x,-y)
    end
    local signature={}
    for i,color in ipairs({{1,0.5,0},{0,0.5,1},{0.5,1,0},{0.25,0.5,0.75}}) do
        local dot=S.hud:CreateTexture(nil,"OVERLAY"); dot:SetSize(4,4)
        dot:SetPoint("TOPLEFT",28+(i-1)*6,-3); dot:SetColorTexture(color[1],color[2],color[3],1); signature[i]=dot
    end
    local footer=CreateFrame("Frame",nil,S.hud)
    footer:SetSize(24,8); footer:SetPoint("BOTTOMRIGHT",0,0); footer:SetFrameLevel(100)
    for i,color in ipairs({{1,0,1},{0,1,1},{1,1,0}}) do
        local dot=footer:CreateTexture(nil,"OVERLAY"); dot:SetSize(4,4)
        dot:SetPoint("TOPLEFT",16-(i-1)*6,-1); dot:SetColorTexture(color[1],color[2],color[3],1)
    end
    local title=S.hud:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    title:SetPoint("TOPLEFT",70,0); title:SetText("FEUXTON v"..ns.version)
    local settingsButton=CreateFrame("Button",nil,S.hud)
    settingsButton:SetSize(60,14); settingsButton:SetPoint("TOPLEFT",576,0)
    local text=settingsButton:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    text:SetAllPoints(); text:SetText("Options")
    settingsButton:SetScript("OnClick",function() ns.rateSettings:Show() end)
    ns.applyCurrentBridge=function()
        if S.readableCall(InCombatLockdown)~=false then return false end
        local class=ns.features.GroupContext.text(ns.features.GroupContext.read(UnitClass,2,"player"),16)
        local base=ns.bridgeLayouts[class]
        if not base then
            S.hudPixelSnapPending=S.hudInitialLayoutPending or S.hudPixelSnapPending
            -- An unsupported or unavailable class has no physical wire profile.
            -- Do not keep another class's completed packet live.
            if S.denseBridge then S.denseBridge.setEnabled(false) end
            return false
        end
        -- Both current modes use one native geometry. Optional diagnostic
        -- signals change only the trailing band, never the health/power grid.
        -- Paladin's near-finished-heal guard always retains its cast clock.
        local profile={};for key,value in pairs(base) do profile[key]=value end
        profile.extendedSignals=class=="PALADIN" or type(ns.extendedHudDiagnostics)=="function" and ns.extendedHudDiagnostics()==true
        -- Leave a blank discovery-marker tail when the native number grid is
        -- last; its final full-width UInt32 cell must never share marker ink.
        profile.height=profile.nativeVitalsTop+profile.nativeVitalsHeight+(profile.extendedSignals and profile.nativeSignalsHeight or 8)
        if profile.extendedSignals and class~="PALADIN" then profile.key=profile.key.."-diagnostics" end
        local initial=S.hudInitialLayoutPending
        if initial then
            if not S.alignHud() then return false end
        elseif not S.snapHudToPixels() then return false end
        S.denseBridge.setEnabled(false)
        S.compactBridge=true
        S.compactBridgeLayout=profile.key
        S.currentBridgeProfile=profile
        S.hud:SetSize(668,profile.height)
        S.hud:SetClampRectInsets(0,0,0,0)
        if initial then
            S.hudInitialLayoutApplied=true
            if not S.alignHud() then return false end
        end
        S.hudDragHandle:SetSize(548,14)
        local colors={{1,0.5,0},{0,0.5,1},profile.marker,profile.extendedSignals and {0,1,1} or {0,1,0}}
        for i,dot in ipairs(signature) do dot:SetColorTexture(unpack(colors[i]));dot:Show() end
        footer:Show();title:Show();settingsButton:Show()
        S.hudTitle:Hide();S.auraTitle:Hide();S.aliveLabel:Hide()
        for _,label in ipairs(S.bridgeLabels) do label:Hide() end
        for i,dot in ipairs(S.targetFlags) do point(dot,S.hud,24+(i-1)*10,class=="HUNTER" and 16 or 18) end
        for i,probe in ipairs(S.meleeProbes) do point(probe.dot,S.hud,84+(i-1)*10,16) end
        for i,dot in ipairs(S.meleeMarkers) do point(dot,S.hud,108+(i-1)*10,18) end
        for i,tile in ipairs(S.tiles) do
            local x=12+((i<=10 and i-1 or i-11)*65)
            point(tile,S.hud,x,i<=10 and 30 or 74);tile:SetSize(58,40)
            tile.label:Hide();tile.binding:Hide();tile:EnableMouse(false)
            for j,dot in ipairs(tile.visualSignals) do point(dot,tile,30+(j-1)*7,i==21 and 30 or 34) end
            if i==21 then point(tile,S.hud,276,268) end
            if class=="HUNTER" then tile:Show() else tile:Hide() end
        end
        for _,spec in ipairs(ns.playerBuffSpecs or {}) do spec.binding:Hide() end
        point(S.playerPanel,S.hud,0,114);point(S.auraMirror,S.hud,0,182)
        for _,widget in ipairs({S.playerPanel,S.auraMirror,S.stingBudget,S.stingBudgetReady,S.stingBudgetMarkerA,S.stingBudgetMarkerB,S.stingBudgetDamage,S.stingBudgetID,S.stingBudgetDirect}) do
            if class=="HUNTER" then widget:Show() else widget:Hide() end
        end
        for _,probe in ipairs(S.meleeProbes) do if class=="HUNTER" then probe.dot:Show() else probe.dot:Hide() end end
        for _,dot in ipairs(S.meleeMarkers) do if class=="HUNTER" then dot:Show() else dot:Hide() end end
        point(S.unitHud,S.hud,0,profile.units);S.unitHud:SetSize(668,profile.unitHeight)
        for _,display in ipairs(S.unitDisplays) do display.name:Hide() end
        point(S.activityPanel,S.hud,0,profile.activity)
        point(S.resourcePanel,S.hud,0,profile.resources);S.resourcePanel:SetSize(668,20)
        point(S.metadataFrame,S.hud,0,profile.setup)
        point(S.fastFrame,S.hud,0,316);point(S.guidePanel,S.hud,0,328)
        point(S.groupPanel,S.hud,0,profile.roster);S.groupPanel:SetSize(668,12)
        if S.paladinPanel then point(S.paladinPanel,S.hud,0,450) end
        if class=="PALADIN" then point(S.paladinNativePanel,S.hud,0,profile.native)
        elseif class=="SHAMAN" then
            point(S.shamanNativePanel,S.hud,0,26);point(ns.features.Totems.panel,S.hud,0,130)
        elseif class=="WARLOCK" then point(S.warlockNativePanel,S.hud,0,26)
        elseif class=="DRUID" then point(S.druidNativePanel,S.hud,0,26) end
        title:SetText("FEUXTON v"..ns.version.." | "..class)
        ns.configureCompactGauges(profile)
        ns.configureHeaderActivity(profile)
        ns.configureHeaderTargetAuras(profile)
        if type(ns.configureProductionVitals)=="function" then
            local ok,err=pcall(ns.configureProductionVitals,profile)
            if not ok and type(ns.clearProductionVitals)=="function" then pcall(ns.clearProductionVitals,S.describe(err)) end
        end
        if type(ns.configureNativeSignals)=="function" then
            local ok,err=pcall(ns.configureNativeSignals,profile.extendedSignals and profile or nil)
            if not ok and type(ns.clearNativeSignals)=="function" then pcall(ns.clearNativeSignals,S.describe(err)) end
        end
        -- Keep the producer frames visible for their scheduled callbacks.
        for _,panel in ipairs({S.metadataFrame,S.fastFrame,S.guidePanel,S.paladinPanel}) do panel:SetAlpha(0) end
        for i,display in ipairs(S.groupDisplays) do point(display.bar,S.hud,408+((i-1)%2)*132,profile.roster+math.floor((i-1)/2)*10) end
        S.denseBridge.configure(profile)
        S.denseBridge.setEnabled(true)
        -- Retire old layout choices only after guarded placement succeeds.
        -- The existing table retains all player options and spell overrides.
        if type(FeuxtonDB)~="table" then FeuxtonDB={} end
        FeuxtonDB.compactBridge=true;FeuxtonDB.denseBridge=true
        if ns.refreshRateSettings then ns.refreshRateSettings() end
        return true
    end
    local previous=S.handlers.PLAYER_LOGIN
    S.handlers.PLAYER_LOGIN=function(...)
        previous(...)
        ns.applyCurrentBridge()
    end
end

-- Registered once after all bridge modules exist; /feuxtonperf toggles sampling.
for _,entry in ipairs({
    {S.hud,"hud"},{S.signalUpdater,"signals"},{S.metadataFrame,"setup"},
    {S.fastFrame,"core"},{S.guidePanel,"guide"},{S.auraMirror,"target auras"},{S.unitHud,"shared units"},
    {S.playerPanel,"player auras"},{S.activityPanel,"activity"},{S.resourcePanel,"gauges"}
}) do S.profileScript(entry[1],"OnUpdate",entry[2]) end
S.profileScript(S.hudEvents,"OnEvent","hud events")
S.profileScript(S.setupEvents,"OnEvent","setup events")

-- One periodic owner. Metadata may change bindings; class rendering supplies
-- group range specs; core observes the completed batch before one publication.
-- Cast/target event handlers remain immediate and are not moved into this loop.
do
    local coordinator={entries={},elapsed=0,updates=0}
    S.updateCoordinator=coordinator
    -- Nested attribution for the final publication work. Wrappers preserve
    -- return values/errors and do not query a clock while profiling is OFF.
    S.denseStatePacket=S.profileFunction(S.denseStatePacket,"packet assembly (includes support)")
    ns.features.ControlEffects.packet=S.profileFunction(ns.features.ControlEffects.packet,"support packet")
    ns.features.Consumables.packet=S.profileFunction(ns.features.Consumables.packet,"consumable packet")
    S.denseBridge.paint=S.profileFunction(S.denseBridge.paint,"packet paint")
    local function register(frame,name)
        if not frame then return end
        local callback=frame:GetScript("OnUpdate")
        if type(callback)~="function" then return end
        frame.feuxtonUpdateCallback=callback
        coordinator.entries[#coordinator.entries+1]={frame=frame,callback=callback,name=name}
        frame:SetScript("OnUpdate",nil)
    end
    register(S.metadataFrame,"setup")
    register(S.hud,"hud")
    register(S.unitHud,"shared units")
    register(S.activityPanel,"activity")
    register(S.resourcePanel,"gauges")
    register(S.auraMirror,"target auras")
    register(S.playerPanel,"player auras")
    register(S.signalUpdater,"signals")
    register(S.paladinPanel,"paladin preview")
    register(S.shamanNativePanel,"Shaman bridge")
    register(S.druidNativePanel,"Druid bridge")
    register(S.warlockNativePanel,"Warlock bridge")
    register(S.guidePanel,"guide")
    register(S.groupPanel,"group")
    register(S.fastFrame,"core")
    local update=S.profileFunction(function(delta)
        if ns.beginNativeCooldownBatch then pcall(ns.beginNativeCooldownBatch) end
        S.beginPacketUpdate()
        local ok,err=true,nil
        for _,entry in ipairs(coordinator.entries) do
            if S.readableCall(entry.frame.IsShown,entry.frame)==true then
                ok,err=pcall(entry.callback,entry.frame,delta)
                if not ok then err=entry.name..": "..S.describe(err);break end
            end
        end
        coordinator.updates=coordinator.updates+1;coordinator.lastError=not ok and err or nil
        S.endPacketUpdate(ok,err)
        if ns.endNativeCooldownBatch then pcall(ns.endNativeCooldownBatch) end
    end,"coordinated total (includes producers)")
    local frame=CreateFrame("Frame",nil,S.hud);coordinator.frame=frame
    frame:SetScript("OnUpdate",function(_,elapsed)
        if S.readableCall(S.hud.IsShown,S.hud)~=true then return end
        coordinator.elapsed=coordinator.elapsed+elapsed
        if coordinator.elapsed<S.updateInterval() then return end
        local delta=coordinator.elapsed;coordinator.elapsed=0
        update(delta)
    end)
end
