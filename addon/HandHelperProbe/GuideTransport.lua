-- HHG6 guide widgets, Hawk count, cast receipts and readiness flags.
local _, ns = ...
local S = ns.state

-- Guide supplement: all spell widgets use the same native rendering path.
-- Hawk count stays unknown until this session has actually observed a Hawk slot.
do
    local observedHawkSlot=false
    local rowBackground=S.hud:CreateTexture(nil,"BACKGROUND"); S.guideBackground=rowBackground
    rowBackground:SetPoint("TOPLEFT",0,-408); rowBackground:SetSize(668,84); rowBackground:SetColorTexture(0,0,0,0.9)
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
    local background=panel:CreateTexture(nil,"BACKGROUND"); background:SetAllPoints(); background:SetColorTexture(0,0,0,1)
    local markers={}
    for index,color in ipairs({{1,0,1},{0,1,1},{1,0.5,0}}) do
        local dot=panel:CreateTexture(nil,"OVERLAY"); dot:SetSize(4,4); dot:SetPoint("TOPLEFT",4+(index-1)*6,0)
        dot:SetColorTexture(color[1],color[2],color[3],1); markers[index]=dot
    end
    local cells={}
    for row=0,3 do for column=0,(row==3 and 153 or 159) do
        local pixel=panel:CreateTexture(nil,"ARTWORK"); pixel:SetSize(4,4); pixel:SetPoint("TOPLEFT",24+column*4,-row*4)
        if row==0 and column<4 then local shade=column/3; pixel:SetColorTexture(shade,shade,shade,1)
        else cells[#cells+1]=pixel end
    end end
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
        packet=packet..ns.features.Interrupts.bytes()
        for _,tile in ipairs(S.tiles) do packet=packet..S.bytes(ns.features.CastTracking.manaFraction(S.boundSpellID(tile),tile.known),1) end
        for _,spec in ipairs(ns.playerBuffSpecs or {}) do packet=packet..S.bytes(ns.features.CastTracking.manaFraction(S.boundSpellID(spec),spec.known),1) end
        packet=packet..S.bytes(S.adler32(packet),4)
        local buffer,bits,cursor=0,0,1
        for _,pixel in ipairs(S.denseBridgeActive and {} or cells) do
            while bits<6 do buffer=buffer*256+(string.byte(packet,cursor) or 0); cursor=cursor+1; bits=bits+8 end
            local factor=2^(bits-6); local value=math.floor(buffer/factor); buffer=buffer%factor; bits=bits-6
            S.setTransportColor(pixel,value)
        end
        S.publishTransportPacket(2,packet)
    end
    local total=0
    panel:SetScript("OnUpdate",function(self,elapsed)
        total=total+elapsed; if total<S.updateInterval() then return end; total=0
        local ok=pcall(render); markers[1]:SetColorTexture(ok and 1 or 0,0,ok and 1 or 0,1)
        if not ok then S.publishTransportPacket(2,nil) end
    end)
    local previous=ns.hudReport
    ns.hudReport=function(add)
        previous(add); add("Guide ability tiles",9); add("Hawk slot count",hawkCount()); add("Hawk slot observed this session",observedHawkSlot)
        add("Player target threat",S.readableCall(UnitThreatSituation,"player","target"))
    end
end

-- Compact bridge v1: geometry only. Packet schemas and secret-value guards stay intact.
-- The desktop expands these explicitly owned widgets to the existing logical atlas.
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
    title:SetPoint("TOPLEFT",70,0); title:SetText("HAND HELPER v"..ns.version)
    local settingsButton=CreateFrame("Button",nil,S.hud)
    settingsButton:SetSize(60,14); settingsButton:SetPoint("TOPLEFT",576,0)
    local text=settingsButton:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    text:SetAllPoints(); text:SetText("Options")
    settingsButton:SetScript("OnClick",function() ns.rateSettings:Show() end)
    ns.setCompactBridge=function(compact)
        if type(compact)~="boolean" or S.readableCall(InCombatLockdown)~=false then return false end
        S.compactBridge=compact
        if type(HandHelperProbeDB)~="table" then HandHelperProbeDB={} end
        HandHelperProbeDB.compactBridge=compact
        local class=ns.features.GroupContext.text(ns.features.GroupContext.read(UnitClass,2,"player"),16)
        local profile=compact and ns.bridgeLayouts[class] or nil
        local dense=compact and ns.denseBridgeLayouts[class] and HandHelperProbeDB.denseBridge~=false
        if dense then profile=ns.denseBridgeLayouts[class] end
        if S.denseBridge then S.denseBridge.setEnabled(false) end
        S.compactBridgeLayout=profile and profile.key or (compact and "hunter-v1" or "diagnostic")
        S.hud:SetSize(668,profile and profile.height or (compact and 348 or 114))
        local paladin=class=="PALADIN"
        S.hud:SetClampRectInsets(0,0,0,compact and (paladin and -154 or -114) or (paladin and -552 or -512))
        if profile then S.hud:SetClampRectInsets(0,0,0,0) end
        S.hudDragHandle:SetSize(compact and 548 or 610,compact and 14 or 25)
        for _,dot in ipairs(signature) do if compact then dot:Show() else dot:Hide() end end
        local version=dense and {{1,0.5,0},{0,0.5,1},{1,1,1},{0,1,1}} or profile and {{1,0.5,0},{0,0.5,1},{1,0,1},{0,1,1}} or {{1,0.5,0},{0,0.5,1},{0.5,1,0},{0.25,0.5,0.75}}
        if dense then version[3]=profile.marker end
        for i,dot in ipairs(signature) do dot:SetColorTexture(unpack(version[i])) end
        if compact then footer:Show(); title:Show(); settingsButton:Show(); S.hudTitle:Hide(); S.auraTitle:Hide(); S.aliveLabel:Hide()
        else footer:Hide(); title:Hide(); settingsButton:Hide(); S.hudTitle:Show(); S.auraTitle:Show(); S.aliveLabel:Show() end
        for _,label in ipairs(S.bridgeLabels) do if compact then label:Hide() else label:Show() end end
        for i,dot in ipairs(S.targetFlags) do point(dot,S.hud,compact and 24+(i-1)*10 or 12+(i-1)*82,compact and 16 or 30) end
        for i,probe in ipairs(S.meleeProbes) do point(probe.dot,S.hud,compact and 84+(i-1)*10 or 504+(i-1)*82,compact and 16 or 30) end
        for i,dot in ipairs(S.meleeMarkers) do point(dot,S.hud,compact and 108+(i-1)*10 or 640+(i-1)*10,compact and 18 or 30) end
        for i,tile in ipairs(S.tiles) do
            local x=12+((i<=10 and i-1 or i-11)*65)
            point(tile,S.hud,x,compact and (i<=10 and 30 or 74) or (i<=10 and 49 or 420))
            tile:SetSize(58,compact and 40 or 66)
            if compact then tile.label:Hide(); tile.binding:Hide(); tile:EnableMouse(false)
            else tile.label:Show(); tile.binding:Show(); tile:EnableMouse(true) end
            for j,dot in ipairs(tile.visualSignals) do point(dot,tile,30+(j-1)*7,compact and (i==21 and 30 or 34) or 50) end
            if i==21 then
                point(tile,S.hud,276,compact and 268 or 356)
                tile.label:Hide();tile.binding:Hide()
            end
        end
        for _,spec in ipairs(ns.playerBuffSpecs or {}) do if compact then spec.binding:Hide() else spec.binding:Show() end end
        point(S.playerPanel,S.hud,0,compact and 114 or 248)
        point(S.auraMirror,S.hud,0,compact and 182 or 118)
        point(S.unitHud,S.hud,0,compact and 228 or 168)
        S.unitHud:SetSize(668,compact and 28 or 44)
        for i,display in ipairs(S.unitDisplays) do
            local x=12+(i-1)*328
            point(display.health,S.unitHud,x,compact and 4 or 20)
            point(display.combat,S.unitHud,x+270,compact and 6 or 22)
            point(display.available,S.unitHud,x+254,compact and 6 or 22)
            if compact then display.name:Hide() else display.name:Show() end
        end
        point(S.playerAlive,S.unitHud,318,compact and 6 or 22)
        point(S.stingBudget,S.unitHud,12,compact and 22 or 38)
        for i,dot in ipairs({S.stingBudgetReady,S.stingBudgetMarkerA,S.stingBudgetMarkerB,S.stingBudgetDamage,S.stingBudgetID,S.stingBudgetDirect}) do point(dot,S.unitHud,268+(i-1)*8,compact and 22 or 38) end
        point(S.activityPanel,S.hud,0,compact and 256 or 316)
        S.activityPanel:SetSize(668,compact and 12 or 40)
        for i,dot in ipairs(S.activityDots) do point(dot,S.activityPanel,12+(i-1)*44,compact and 4 or 26) end
        point(S.activityMovement,S.activityPanel,652,compact and 4 or 26)
        for i,dot in ipairs(S.activityMovementMarkers) do point(dot,S.activityPanel,640+(i-1)*6,compact and 4 or 26) end
        point(S.resourcePanel,S.hud,0,compact and 268 or 356)
        S.resourcePanel:SetSize(668,compact and 36 or 52)
        for i,display in ipairs(S.resourceDisplays) do
            local x=i<=2 and 12 or 340; local j=(i-1)%2
            point(display.bar,S.resourcePanel,x,(compact and 4 or 20)+j*16)
            point(display.dot,S.resourcePanel,x+255,(compact and 6 or 22)+j*16)
        end
        point(S.metadataFrame,S.hud,0,compact and 304 or 216)
        point(S.fastFrame,S.hud,0,compact and 316 or 232)
        point(S.guidePanel,S.hud,0,compact and 328 or 492)
        point(S.groupPanel,S.hud,0,compact and 348 or 512)
        if S.paladinPanel then point(S.paladinPanel,S.hud,0,compact and 450 or 614) end
        if S.paladinNativePanel then point(S.paladinNativePanel,S.hud,0,compact and 462 or 626) end
        -- Only the active class's native spells/auras occupy screen space.
        for _,tile in ipairs(S.tiles) do if class=="HUNTER" then tile:Show() else tile:Hide() end end
        for _,widget in ipairs({S.playerPanel,S.auraMirror,S.stingBudget,S.stingBudgetReady,S.stingBudgetMarkerA,S.stingBudgetMarkerB,S.stingBudgetDamage,S.stingBudgetID,S.stingBudgetDirect}) do
            if class=="HUNTER" then widget:Show() else widget:Hide() end
        end
        for _,probe in ipairs(S.meleeProbes) do if class=="HUNTER" then probe.dot:Show() else probe.dot:Hide() end end
        for _,dot in ipairs(S.meleeMarkers) do if class=="HUNTER" then dot:Show() else dot:Hide() end end
        title:SetText("HAND HELPER v"..ns.version.." | "..class)
        S.hudTitle:SetText("HAND HELPER v"..ns.version.." | "..class.." | DRAG HEADER / CLICK FOR OPTIONS")
        if profile then
            if paladin then
                for i,dot in ipairs(S.targetFlags) do point(dot,S.hud,24+(i-1)*10,18) end
                point(S.paladinNativePanel,S.hud,0,profile.native)
            end
            point(S.unitHud,S.hud,0,profile.units);S.unitHud:SetSize(668,profile.unitHeight or 22)
            point(S.activityPanel,S.hud,0,profile.activity)
            point(S.resourcePanel,S.hud,0,profile.resources)
            point(S.metadataFrame,S.hud,0,profile.setup)
            if profile.core then point(S.fastFrame,S.hud,0,profile.core) end
            if profile.guide then point(S.guidePanel,S.hud,0,profile.guide) end
            point(S.groupPanel,S.hud,0,profile.roster)
            if profile.classPacket then point(S.paladinPanel,S.hud,0,profile.classPacket) end
        end
        ns.configureCompactGauges(dense and profile or nil)
        ns.configureHeaderActivity(dense and profile or nil)
        ns.configureHeaderTargetAuras(dense and profile or nil)
        -- Transparent public producers remain visible so their OnUpdate runs.
        for _,panel in ipairs({S.metadataFrame,S.fastFrame,S.guidePanel,S.paladinPanel}) do panel:SetAlpha(dense and 0 or 1) end
        for i,display in ipairs(S.groupDisplays) do
            for _,pixel in ipairs(display.cells.all) do if dense then pixel:Hide() else pixel:Show() end end
            point(display.bar,dense and S.hud or S.groupPanel,dense and 408+((i-1)%2)*132 or 12,dense and profile.roster+math.floor((i-1)/2)*10 or 10+(i-1)*16)
        end
        if dense then S.groupBackground:Hide() else S.groupBackground:Show() end
        for _,marker in ipairs(S.groupMarkers) do if dense then marker:Hide() else marker:Show() end end
        S.groupPanel:SetSize(668,dense and 12 or 102)
        if dense then S.denseBridge.configure(profile) end
        if S.denseBridge then S.denseBridge.setEnabled(dense and true or false) end
        if compact or class~="HUNTER" then S.guideBackground:Hide() else S.guideBackground:Show() end
        if ns.refreshRateSettings then ns.refreshRateSettings() end
        return true
    end
    ns.setDenseBridge=function(enabled)
        if type(enabled)~="boolean" or S.readableCall(InCombatLockdown)~=false then return false end
        local class=ns.features.GroupContext.text(ns.features.GroupContext.read(UnitClass,2,"player"),16)
        if enabled and not ns.denseBridgeLayouts[class] then return false end
        if type(HandHelperProbeDB)~="table" then HandHelperProbeDB={} end
        HandHelperProbeDB.denseBridge=enabled
        return ns.setCompactBridge(true)
    end
    local previous=S.handlers.PLAYER_LOGIN
    S.handlers.PLAYER_LOGIN=function(...)
        previous(...)
        ns.setCompactBridge(type(HandHelperProbeDB)~="table" or HandHelperProbeDB.compactBridge~=false)
    end
end

-- Registered once after all bridge modules exist; /hhperf toggles sampling.
for _,entry in ipairs({
    {S.hud,"hud"},{S.signalUpdater,"signals"},{S.metadataFrame,"setup"},
    {S.fastFrame,"core"},{S.guidePanel,"guide"},{S.auraMirror,"target auras"},{S.unitHud,"shared units"},
    {S.playerPanel,"player auras"},{S.activityPanel,"activity"},{S.resourcePanel,"gauges"}
}) do S.profileScript(entry[1],"OnUpdate",entry[2]) end
S.profileScript(S.hudEvents,"OnEvent","hud events")
S.profileScript(S.setupEvents,"OnEvent","setup events")
