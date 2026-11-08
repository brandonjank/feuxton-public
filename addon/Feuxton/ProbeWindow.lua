-- Diagnostic report window and /feuxtonprobe command.
local _, ns = ...
local S = ns.state

S.panel = CreateFrame("Frame", nil, UIParent)
S.panel:SetSize(700, 560)
S.panel:SetPoint("CENTER")
S.panel:SetFrameStrata("DIALOG")
S.panel:Hide()
S.background = S.panel:CreateTexture(nil, "BACKGROUND")
S.background:SetAllPoints()
S.background:SetColorTexture(0.04, 0.04, 0.04, 0.98)
S.title = S.panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
S.title:SetPoint("TOPLEFT", 16, -16)
S.title:SetText("Feuxton — select text and press Ctrl+C")
S.close = CreateFrame("Button", nil, S.panel, "UIPanelCloseButton")
S.close:SetPoint("TOPRIGHT", -4, -4)
S.scroll = CreateFrame("ScrollFrame", nil, S.panel, "UIPanelScrollFrameTemplate")
S.scroll:SetPoint("TOPLEFT", 16, -48)
S.scroll:SetPoint("BOTTOMRIGHT", -36, 16)
S.edit = CreateFrame("EditBox", nil, S.scroll)
S.edit:SetMultiLine(true)
S.edit:SetAutoFocus(false)
S.edit:SetFontObject(ChatFontNormal)
S.edit:SetWidth(630)
S.edit:SetHeight(1400)
S.edit:SetScript("OnEscapePressed", function() S.panel:Hide() end)
S.edit:SetScript("OnTextChanged", function() S.scroll:UpdateScrollChildRect() end)
S.scroll:SetScrollChild(S.edit)

ns.report = S.report
SLASH_FEUXTONPROBE1 = "/feuxtonprobe"
SlashCmdList.FEUXTONPROBE = function(message)
    message=(message or ""):lower():match("^%s*(.-)%s*$")
    if message=="capture" then
        local ok,snapshot=pcall(S.captureCapabilities)
        if ok then print("Feuxton: saved "..snapshot.mode.." API snapshot ("..S.capabilitySummary(snapshot)..").")
        else print("Feuxton: API snapshot failed: "..S.describe(snapshot)) end
        return
    elseif message~="" and message~="compare" then
        print("Feuxton: /feuxtonprobe, /feuxtonprobe capture (no popup), /feuxtonprobe compare")
        return
    end
    local ok,text=pcall(message=="compare" and S.compareCapabilities or S.report)
    if not ok then print("Feuxton: capability report failed: "..S.describe(text)); return end
    S.edit:SetText(text)
    S.panel:Show()
    S.edit:SetFocus()
    S.edit:HighlightText()
end

-- Production dense cells share the public envelope; private values remain native.
function ns.initializeDenseBridge()
    local bridge={enabled=false,tick=0,errors={}};S.denseBridge=bridge
    local frame=CreateFrame("Frame",nil,S.hud);bridge.frame=frame
    frame:SetSize(400,28);frame:SetPoint("TOPLEFT",S.hud,"TOPLEFT",0,-138)
    local bg=frame:CreateTexture(nil,"BACKGROUND");bg:SetAllPoints();bg:SetColorTexture(0,0,0,1)
    local function patch(parent,x,y)
        local p=parent:CreateTexture(nil,"OVERLAY");p:SetSize(3,3);p:SetPoint("TOPLEFT",x,-y);return p
    end
    for value=0,255 do local p=patch(frame,8+value%128*3,math.floor(value/128)*3);local c=value/255;p:SetColorTexture(c,c,c,1) end
    bridge.stateCells={}
    bridge.paintStates=setmetatable({}, {__mode="k"})
    local initialPaint={colors={},blocks={},extent=0}
    bridge.paintStates[bridge.stateCells]=initialPaint
    for i=0,767 do
        local p=patch(frame,8+i%128*3,10+math.floor(i/128)*3)
        -- Keep the public RGB cell's texture fixed and change only its tint.
        -- Calibration, native stamps and diagnostic grids retain their setters.
        p:SetColorTexture(1,1,1,1);p:SetVertexColor(0,0,0,1)
        bridge.stateCells[#bridge.stateCells+1]=p;initialPaint.colors[i+1]=0
    end
    -- Production owns its painter; the optional laboratory is not a dependency.
    -- Compare fixed 48-byte blocks before decoding their 16 RGB cells. Cache
    -- only public packet bytes/colors, separately for each destination array.
    function bridge.paint(cells,packet)
        local used=math.ceil(#packet/3)
        assert(used<=#cells,"dense paint capacity exceeded")
        local state=bridge.paintStates[cells]
        if not state then state={colors={},blocks={},extent=0};bridge.paintStates[cells]=state end
        local limit=math.max(used,state.extent)
        -- Retain the attempted extent on failure so a later blank packet also
        -- clears cells written by a partially completed growing publication.
        state.extent=limit
        local visits,writes,skipped=0,0,0
        local detail=S.performance and S.performance.enabled and S.performance.detail and S.performance.paintDetail
        local setterMs,controlMs,setterSamples,controlSamples=0,0,0,0
        for first=1,limit,16 do
            local index=math.floor((first-1)/16)+1
            local chunk=string.sub(packet,(first-1)*3+1,(first+15)*3)
            if state.blocks[index]==chunk then skipped=skipped+1
            else
                -- An interrupted block must be retried, even if the following
                -- packet equals the block which preceded that failed attempt.
                state.blocks[index]=nil
                for i=first,math.min(first+15,limit) do
                    visits=visits+1
                    local at=(i-1)*3+1;local r,g,b=string.byte(packet,at,at+2)
                    r,g,b=r or 0,g or 0,b or 0
                    local value=r*65536+g*256+b
                    if state.colors[i]~=value then
                        -- A setter may fail after touching the widget. Unknown
                        -- cached color forces the next attempt to repaint it.
                        state.colors[i]=nil
                        if detail then
                            local before=S.profileClock()
                            cells[i]:SetVertexColor(r/255,g/255,b/255,1)
                            local after=S.profileClock()
                            -- Adjacent guarded reads expose clock/control cost
                            -- under this same workload; never subtract blindly.
                            local controlBefore=S.profileClock()
                            local controlAfter=S.profileClock()
                            if before and after and after>=before then setterMs=setterMs+after-before;setterSamples=setterSamples+1 end
                            if controlBefore and controlAfter and controlAfter>=controlBefore then controlMs=controlMs+controlAfter-controlBefore;controlSamples=controlSamples+1 end
                        else cells[i]:SetVertexColor(r/255,g/255,b/255,1) end
                        state.colors[i]=value;writes=writes+1
                    end
                end
                state.blocks[index]=chunk
            end
        end
        state.extent=used
        bridge.paintedCells=used;bridge.paintVisits=visits;bridge.paintWrites=writes;bridge.paintSkippedBlocks=skipped
        local metrics=S.performance and S.performance.enabled and S.performance.paint
        if metrics then
            metrics.updates=metrics.updates+1;metrics.visits=metrics.visits+visits
            metrics.writes=metrics.writes+writes;metrics.skippedBlocks=metrics.skippedBlocks+skipped
        end
        -- Publish timing only after the whole paint succeeds. A partial failed
        -- paint cannot masquerade as a completed low-cost update.
        if detail then
            detail.updates=detail.updates+1;detail.writes=detail.writes+writes
            detail.setterMs=detail.setterMs+setterMs;detail.controlMs=detail.controlMs+controlMs
            detail.setterSamples=detail.setterSamples+setterSamples;detail.controlSamples=detail.controlSamples+controlSamples
        end
    end
    -- Even-size stamps align with the native widget grid. RGB data cells are
    -- sampled at their centers; stamps validate a three-pixel interior.
    local function stampPatch(parent,x,y)
        local p=patch(parent,x,y);p:SetSize(4,4);return p
    end
    bridge.coreStamp={stampPatch(S.hud,108,18),stampPatch(S.hud,114,18)}
    bridge.guideStamp={stampPatch(S.hud,156,18),stampPatch(S.hud,162,18)}
    S.denseTargetStamp=stampPatch(S.hud,122,18)
    bridge.rosterStamps={}
    for i=1,6 do local x=12+(i-1)*108;bridge.rosterStamps[i]={stampPatch(S.hud,x+98,200),stampPatch(S.hud,x+102,200)} end
    function bridge.configure(profile)
        bridge.profile=profile
        local function point(p,x,y) p:ClearAllPoints();p:SetPoint("TOPLEFT",S.hud,"TOPLEFT",x,-y) end
        point(frame,0,profile.grid)
        for i,p in ipairs(bridge.coreStamp) do point(p,profile.coreStamp+(i-1)*6,18) end
        point(S.denseTargetStamp,profile.targetStamp,18)
        for i,p in ipairs(bridge.guideStamp) do point(p,(profile.guideStamp or 156)+(i-1)*6,18) end
        for i,cells in ipairs(bridge.rosterStamps) do for j,p in ipairs(cells) do point(p,506+((i-1)%2)*132+(j-1)*4,profile.roster+math.floor((i-1)/2)*10) end end
    end
    local function stamp(cells,packet)
        local n=packet and #packet or 0
        local a,b,c,d=0,0,0,0
        if n>=4 then a,b,c,d=string.byte(packet,n-3,n) end
        cells[1]:SetColorTexture(a/255,b/255,c/255,1);cells[2]:SetColorTexture(d/255,0,0,1)
    end
    function bridge.stamp(id,packet)
        if id==1 then stamp(bridge.coreStamp,packet)
        elseif id==2 then stamp(bridge.guideStamp,packet)
        elseif id>=16 and id<=21 then stamp(bridge.rosterStamps[id-15],packet) end
    end
    function bridge.publishState(now)
        bridge.tick=(bridge.tick+1)%4294967296
        local packet=S.denseStatePacket(now,bridge.tick);bridge.lastStatePacket=packet
        bridge.paint(bridge.stateCells,packet,24);bridge.errors.state=nil
        -- Numeric native fields are an independently stamped extension of this
        -- exact completed envelope. A footer failure cannot blank HHD2.
        if type(ns.refreshProductionVitals)=="function" then
            local ok,err=pcall(ns.refreshProductionVitals,bridge.tick,packet)
            bridge.errors.vitals=not ok and S.describe(err) or nil
            if not ok and type(ns.clearProductionVitals)=="function" then pcall(ns.clearProductionVitals,bridge.errors.vitals) end
        end
        if type(ns.refreshNativeSignals)=="function" then
            local ok,err=true,nil
            if type(ns.commitNativeCooldownBatch)=="function" then ok,err=pcall(ns.commitNativeCooldownBatch) end
            if ok then ok,err=pcall(ns.refreshNativeSignals,bridge.tick,packet) end
            bridge.errors.signals=not ok and S.describe(err) or nil
            if not ok and type(ns.clearNativeSignals)=="function" then pcall(ns.clearNativeSignals,bridge.errors.signals) end
        end
    end
    function bridge.setEnabled(enabled)
        bridge.enabled=enabled;S.denseBridgeActive=enabled
        for _,cells in ipairs({bridge.coreStamp,unpack(bridge.rosterStamps)}) do for _,p in ipairs(cells) do if enabled then p:Show() else p:Hide() end end end
        for _,p in ipairs(bridge.guideStamp) do if enabled and bridge.profile and bridge.profile.guideStamp then p:Show() else p:Hide() end end
        if enabled then frame:Show();S.denseTargetStamp:Show();S.refreshFlags();S.renderSetupPage();S.refreshTransportPacketState()
        else
            frame:Hide();S.denseTargetStamp:Hide()
            if type(ns.configureProductionVitals)=="function" then pcall(ns.configureProductionVitals,nil) end
            if type(ns.configureNativeSignals)=="function" then pcall(ns.configureNativeSignals,nil) end
        end
    end
    bridge.setEnabled(false)
end

-- Production native-number footer. Restricted numbers go only to native text,
-- never into readable RGB metadata. Historical FHL1 lives in test support.
do
    -- Exact maxima of the current bounded wire schemas. Keep the 328-column
    -- raster and reader capacity; do not allocate textures for impossible tail
    -- bytes. A schema extension must deliberately update these bounds.
    local nativeVitalsMaximumBytes=24+9*(6+64+5*5)+(15+42*4)+4
    local nativeSignalsMaximumBytes=78+5*(11+80)+18+3*12+4
    local nativeVitalsCellCount=math.ceil(nativeVitalsMaximumBytes/3)
    local nativeSignalsCellCount=math.ceil(nativeSignalsMaximumBytes/3)
    ns.nativeMetadataLimits={vitalsBytes=nativeVitalsMaximumBytes,vitalsCells=nativeVitalsCellCount,
        signalsBytes=nativeSignalsMaximumBytes,signalsCells=nativeSignalsCellCount}
    local function public(value)
        if S.isSecret(value) then return nil end
        return value
    end
    local function query(fn,...)
        if type(fn)~="function" then return nil end
        local ok,value=pcall(fn,...);if not ok then return nil end
        return public(value)
    end
    local function number(value,maximum)
        value=public(value)
        return type(value)=="number" and value>=0 and value<=maximum and value==math.floor(value) and value or nil
    end
    local function tri(value)return value==true and 2 or value==false and 1 or 0 end
    local function clearText(text)pcall(text.SetText,text,"")end
    local function nativeNumber(text,getter,unit,exists,powerType)
        clearText(text)
        if not exists or type(getter)~="function" then return {status=0,value=0},false end
        local ok,value
        if powerType~=nil then ok,value=pcall(getter,unit,powerType) else ok,value=pcall(getter,unit) end
        if not ok then return {status=3,value=0},false end
        local status,numeric
        if S.isSecret(value) then status=2
        elseif value==nil then return {status=0,value=0},false
        else numeric=number(value,4294967295);if numeric==nil then return {status=3,value=0},false end;status=1 end
        -- No tostring/string.format, arithmetic, comparison or GetText on a
        -- secret. Setter acceptance is not proof that readable digits appeared.
        local accepted=pcall(text.SetFormattedText,text,"%d",value)
        if not accepted then clearText(text) end
        return {status=status,value=numeric or 0},accepted
    end
    local function font(parent,x,y,width,height)
        local text=parent:CreateFontString(nil,"OVERLAY")
        text:SetPoint("TOPLEFT",x,-y);text:SetSize(width,height)
        text:SetFont("Fonts\\ARIALN.TTF",14,"MONOCHROME")
        text:SetJustifyH("LEFT");text:SetJustifyV("TOP");text:SetTextColor(1,1,1,1)
        text:SetShadowOffset(0,0);text:SetShadowColor(0,0,0,0)
        return text
    end

    -- Production health/power footer. Public metadata names the completed HHD2
    -- frame; native glyphs are assigned before the metadata/checksum commit.
    -- No event handler, update callback, cached maximum or lab state is shared.
    local productionUnits={"player","target","pet","focus","party1","party2","party3","party4","mouseover"}
    local productionGetters={"UnitHealth","UnitHealthMax","UnitHealthMissing","UnitPower","UnitPowerMax"}
    local function guidFor(unit)
        local value=query(UnitGUID,unit)
        if type(value)=="string" and #value>0 and #value<=64 and not value:find("[^A-Za-z0-9%-]") then return value end
        return ""
    end
    local function unsignedLE(packet,at,count)
        local value,factor=0,1
        for i=at,at+count-1 do local byte=string.byte(packet,i);if byte==nil then return nil end;value=value+byte*factor;factor=factor*256 end
        return value
    end
    local function productionState()
        if ns.productionVitals then return ns.productionVitals end
        local state={enabled=false,rows={},cells={},colors={},blocks={},stamp={},paintedCells=0,maximumPacketBytes=nativeVitalsMaximumBytes}
        local frame=CreateFrame("Frame",nil,S.hud);state.frame=frame
        frame:SetSize(668,87);frame:EnableMouse(false)
        local back=frame:CreateTexture(nil,"BACKGROUND");back:SetAllPoints();back:SetColorTexture(0,0,0,1)
        local function patch(x,y,width,height)
            local cell=frame:CreateTexture(nil,"ARTWORK");cell:SetSize(width,height);cell:SetPoint("TOPLEFT",x,-y)
            cell:SetColorTexture(1,1,1,1);cell:SetVertexColor(0,0,0,1);return cell
        end
        for index=0,nativeVitalsCellCount-1 do state.cells[index+1]=patch(6+(index%328)*2,math.floor(index/328)*2,2,2);state.colors[index+1]=0 end
        for digit=0,9 do font(frame,8+digit*11,4,10,18):SetFormattedText("%d",digit) end
        state.stamp[1]=patch(126,8,4,4);state.stamp[2]=patch(130,8,4,4)
        for index,unit in ipairs(productionUnits) do
            local row={unit=unit,fields={}};state.rows[index]=row
            for col=1,5 do
                local flat=(index-1)*5+col-1
                row.fields[col]=font(frame,10+flat%9*72,22+math.floor(flat/9)*13,72,13)
            end
        end
        frame:Hide();ns.productionVitals=state;return state
    end
    function ns.clearProductionVitals(reason)
        local state=ns.productionVitals;if not state then return end
        state.packet=nil;state.lastError=reason
        -- Invalidate the visible commit before attempting any other cleanup.
        for _,stamp in ipairs(state.stamp) do pcall(stamp.SetVertexColor,stamp,0,0,0,1) end
        for _,cell in ipairs(state.cells) do pcall(cell.SetVertexColor,cell,0,0,0,1) end
        for _,row in ipairs(state.rows) do for _,text in ipairs(row.fields) do clearText(text) end end
        -- A native setter can mutate and then fail. Force a complete repaint on
        -- recovery rather than trusting any cached successful color/block.
        state.colors={};state.blocks={};state.paintedCells=0
    end
    function ns.configureProductionVitals(profile)
        if not profile or number(profile.nativeVitalsTop,65535)==nil or profile.nativeVitalsHeight~=87 then
            local state=ns.productionVitals
            if state then state.enabled=false;ns.clearProductionVitals();state.frame:Hide() end
            return
        end
        local state=productionState();state.enabled=false;ns.clearProductionVitals()
        state.frame:ClearAllPoints();state.frame:SetPoint("TOPLEFT",S.hud,"TOPLEFT",0,-profile.nativeVitalsTop)
        state.enabled=true;state.frame:Show()
    end
    local function paintProduction(state,packet)
        assert(#packet<=state.maximumPacketBytes,"Native metadata schema maximum exceeded")
        local used=math.ceil(#packet/3);assert(used<=#state.cells,"Native vitals metadata capacity exceeded")
        local limit=math.max(used,state.paintedCells);state.paintedCells=limit
        for first=1,limit,16 do
            local block=math.floor((first-1)/16)+1;local chunk=string.sub(packet,(first-1)*3+1,(first+15)*3)
            if state.blocks[block]~=chunk then
                state.blocks[block]=nil
                for index=first,math.min(first+15,limit) do
                    local offset=(index-1)*3+1;local r,g,b=string.byte(packet,offset,offset+2);r,g,b=r or 0,g or 0,b or 0
                    local color=r*65536+g*256+b
                    if state.colors[index]~=color then
                        state.colors[index]=nil;state.cells[index]:SetVertexColor(r/255,g/255,b/255,1);state.colors[index]=color
                    end
                end
                state.blocks[block]=chunk
            end
        end
        state.paintedCells=used
    end
    local function productionMouseoverGeneration(classID)
        if classID~=4 then return 0 end
        local warlock=ns.classes and ns.classes.WARLOCK
        return number(warlock and warlock.mouseoverGeneration,4294967295)
    end
    function ns.refreshProductionVitals(tick,outer)
        local state=ns.productionVitals;if not state or not state.enabled then return end
        assert(type(outer)=="string" and #outer>=23 and outer:sub(1,4)=="HHD2","Native health envelope unavailable")
        local session=number(S.setupSession,4294967295);local targetGeneration=number(S.auraGeneration,255)
        local outerChecksum=unsignedLE(outer,#outer-3,4);local classID=string.byte(outer,13)
        assert(session and targetGeneration and number(tick,4294967295) and unsignedLE(outer,5,4)==session
            and unsignedLE(outer,9,4)==tick and string.byte(outer,16)==targetGeneration
            and outerChecksum==S.adler32(outer:sub(1,-5)),"Native health envelope context changed")
        local mouseoverGeneration=productionMouseoverGeneration(classID)
        assert(mouseoverGeneration,"Native health mouseover context unavailable")
        -- Blank the prior native commit while fields and metadata are replaced.
        for _,stamp in ipairs(state.stamp) do stamp:SetVertexColor(0,0,0,1) end
        state.packet=nil
        local rows={}
        for index,row in ipairs(state.rows) do
            local unit=row.unit;local generationBefore=number(S.auraGeneration,255)
            local exists=query(UnitExists,unit)
            local flags=tri(exists)+tri(query(UnitIsVisible,unit))*4+tri(query(UnitIsDeadOrGhost,unit))*16
            local guid=exists==true and guidFor(unit) or ""
            -- The selected target can be owned by this exact rendered frame's
            -- public target generation when combat hides its GUID. This scope
            -- is never a GUID, alias identity, or friendly-delivery proof.
            local identityKind=guid~="" and 1 or unit=="target" and exists==true and generationBefore==targetGeneration and 2 or 0
            local powerType=exists==true and identityKind~=0 and number(query(UnitPowerType,unit),254) or nil
            local values,mask={},0
            for col,text in ipairs(row.fields) do
                local value,valid=nativeNumber(text,_G[productionGetters[col]],unit,exists==true and identityKind~=0 and (col<=3 or powerType~=nil),col>3 and powerType or nil)
                values[col]=value;if valid then mask=mask+2^(col-1) end
            end
            local powerAfter=exists==true and identityKind~=0 and number(query(UnitPowerType,unit),254) or nil
            if powerType==nil or powerAfter~=powerType then
                -- Form/resource changes invalidate only the typed power pair.
                -- Health numbers are independent of the current power type.
                powerType=nil;mask=mask%8
                for col=4,5 do clearText(row.fields[col]);values[col]={status=0,value=0} end
            end
            local existsAfter=query(UnitExists,unit);local guidAfter=guidFor(unit)
            -- A unit token may change recipient during a native getter batch.
            -- Never downgrade a changed/known GUID to generation ownership.
            local identityStable=existsAfter==true and (identityKind==1 and guidAfter==guid or identityKind==2 and guidAfter==""
                and generationBefore==targetGeneration and number(S.auraGeneration,255)==targetGeneration)
            if not identityStable then
                guid="";identityKind=0;powerType=nil;mask=0
                for col,text in ipairs(row.fields) do clearText(text);values[col]={status=0,value=0} end
            end
            local parts={S.bytes(index,1),S.bytes(flags,1),S.bytes(powerType or 255,1),S.bytes(identityKind,1),S.bytes(#guid,1),guid,S.bytes(mask,1)}
            for _,value in ipairs(values) do parts[#parts+1]=S.bytes(value.status,1)..S.bytes(value.value,4) end
            rows[#rows+1]=table.concat(parts)
        end
        local sampler=ns.features and ns.features.RangeCensus;local census={}
        if sampler and type(sampler.capture)=="function" then
            local ok,value=pcall(sampler.capture,true)
            assert(ok and not S.isSecret(value) and type(value)=="table","Native health census unavailable");census=value
        end
        local records={}
        if type(census.records)=="table" then
            for index,record in ipairs(census.records) do
                assert(index<=42 and type(record)=="table","Native health census record invalid")
                local status,reason,alias=number(record.status,3),number(record.reason,13),number(record.alias,42)
                assert(status and reason and alias,"Native health census record invalid")
                records[#records+1]=S.bytes(index,1)..S.bytes(status,1)..S.bytes(reason,1)..S.bytes(alias,1)
            end
        end
        local minimum=number(census.minRangeYards,65534) or 65535
        local maximum=number(census.maxRangeYards,65534) or 65535
        local tail={S.bytes(number(census.probeID,4294967295) or 0,4),S.bytes(minimum,2),S.bytes(maximum,2)}
        for _,key in ipairs({"confirmed","unknown","excluded","sampled","duplicate","identityUnknown"}) do tail[#tail+1]=S.bytes(number(census[key],255) or 0,1) end
        tail[#tail+1]=S.bytes(#records,1);tail[#tail+1]=table.concat(records)
        assert(number(S.setupSession,4294967295)==session and number(S.auraGeneration,255)==targetGeneration
            and productionMouseoverGeneration(classID)==mouseoverGeneration,"Native health context changed during rendering")
        local body=S.bytes(session,4)..S.bytes(tick,4)..S.bytes(outerChecksum,4)..S.bytes(targetGeneration,1)
            ..S.bytes(mouseoverGeneration,4)..S.bytes(9,1)..table.concat(rows)..table.concat(tail)
        local packet="FHV3"..S.bytes(4+2+#body+4,2)..body
        packet=packet..S.bytes(S.adler32(packet),4)
        paintProduction(state,packet)
        local a,b,c,d=string.byte(packet,#packet-3,#packet)
        state.stamp[1]:SetVertexColor(a/255,b/255,c/255,1);state.stamp[2]:SetVertexColor(d/255,0,0,1)
        state.packet=packet;state.lastError=nil;state.tick=tick;state.session=session
    end

    -- Diagnostic native counters/timers. This uses the same main capture and
    -- publication batch, but never supplies rotation or execution observations.
    local signalUnits={player=1,target=2,mouseover=3}
    local signalFilters={HELPFUL=1,HARMFUL=2,["HELPFUL|PLAYER"]=3,["HARMFUL|PLAYER"]=4}
    local function signalState()
        if ns.nativeSignals then return ns.nativeSignals end
        local state={enabled=false,entries={},byKey={},revision=0,page=-1,cells={},colors={},blocks={},stamp={},fast={},paintedCells=0,cooldownIDs={},cooldownRevision=0,cooldownSignature="",cooldownTexts={},maximumPacketBytes=nativeSignalsMaximumBytes}
        local frame=CreateFrame("Frame",nil,S.hud);state.frame=frame;frame:SetSize(668,58);frame:EnableMouse(false)
        local back=frame:CreateTexture(nil,"BACKGROUND");back:SetAllPoints();back:SetColorTexture(0,0,0,1)
        local function patch(x,y,w,h)
            local p=frame:CreateTexture(nil,"ARTWORK");p:SetSize(w,h);p:SetPoint("TOPLEFT",x,-y);p:SetColorTexture(1,1,1,1);p:SetVertexColor(0,0,0,1);return p
        end
        for index=0,nativeSignalsCellCount-1 do state.cells[index+1]=patch(6+index%328*2,math.floor(index/328)*2,2,2);state.colors[index+1]=0 end
        for digit=0,9 do font(frame,8+digit*11,4,10,18):SetFormattedText("%d",digit) end
        font(frame,118,4,6,18):SetText(".")
        state.stamp[1]=patch(126,8,4,4);state.stamp[2]=patch(130,8,4,4)
        font(frame,480,4,48,18):SetText("GCD")
        state.gcdText=font(frame,528,4,112,18)
        state.gcdEligibility=patch(648,8,4,4);state.gcdEligibility:SetVertexColor(1,.65,0,1)
        for i=1,5 do state.fast[i]=font(frame,80+(i-1)*112,22,112,18) end
        for i=1,3 do state.cooldownTexts[i]=font(frame,144+(i-1)*112,4,112,18);state.cooldownTexts[i]:Show() end
        -- Ordinary diagnostic text only; never adopted by an aura button or
        -- used as a native data field. It remains readable after invalidation.
        state.errorText=font(frame,8,22,652,18)
        frame:Hide();ns.nativeSignals=state;return state
    end
    local function hideSignalWrappers(state,strict)
        -- AuraButton descendants become forbidden to ordinary visibility
        -- mutations in combat. Unknown lock state is equally ineligible.
        if query(InCombatLockdown)~=false then return false end
        local complete=true
        for _,entry in ipairs(state.entries) do if entry.wrapper then
            local ok=pcall(entry.wrapper.SetAlpha,entry.wrapper,0)
            if not ok then complete=false end
        end end
        return complete
    end
    local function recordNativeError(state,reason,visible)
        local restricted=S.isSecret(reason)
        if not restricted and reason==nil then if visible then clearText(state.errorText) end;return end
        local message="Native signals error unavailable"
        if not restricted and type(reason)=="string" then
            message=reason:gsub("[%z\1-\31\127]"," ")
            message=message:match("([^/\\]+%.lua:%d+:.*)") or message
            message=message:sub(1,256)
            if message=="" then message="Native signals error unavailable" end
        end
        if visible then state.lastError=message;pcall(state.errorText.SetText,state.errorText,"Signals: "..message:sub(1,110))
        else state.lastAuraError=message end
        -- Only public bounded error text and a counter persist. No timing,
        -- spell/aura value, object or secret reason is stored here.
        if S.isSecret(FeuxtonDB) then return end
        if type(FeuxtonDB)=="nil" then FeuxtonDB={} elseif type(FeuxtonDB)~="table" then return end
        local previous=public(FeuxtonDB.nativeSignalsDiagnostic)
        local count=type(previous)=="table" and number(previous.count,4294967295) or 0
        FeuxtonDB.nativeSignalsDiagnostic={lastError=message,count=math.min(4294967295,(count or 0)+1)}
    end
    function ns.clearNativeSignals(reason)
        local state=ns.nativeSignals;if not state then return end
        state.packet=nil;state.lastError=nil
        for _,stamp in ipairs(state.stamp) do pcall(stamp.SetVertexColor,stamp,0,0,0,1) end
        for _,cell in ipairs(state.cells) do pcall(cell.SetVertexColor,cell,0,0,0,1) end
        for _,text in ipairs(state.fast) do clearText(text) end
        clearText(state.gcdText)
        pcall(state.gcdEligibility.SetVertexColor,state.gcdEligibility,1,.65,0,1)
        for _,text in ipairs(state.cooldownTexts) do clearText(text) end
        state.cooldownCollecting=false;state.cooldownBatchReady=false
        if query(InCombatLockdown)==false then hideSignalWrappers(state,false);state.auraVisibilityCertified=false;state.auraVisiblePage=nil end
        state.colors={};state.blocks={};state.paintedCells=0
        recordNativeError(state,reason,true)
    end
    -- Only the coordinated producer batch may contribute spell identities.
    -- These tables contain guarded public IDs, never native timing objects.
    function ns.beginNativeCooldownBatch()
        local state=ns.nativeSignals;if not state or not state.enabled then return end
        state.cooldownCollecting=true;state.cooldownBatchReady=false;state.cooldownSeen={};state.cooldownSeenCount=0;state.cooldownOverflow=false
        state.packet=nil
        for _,stamp in ipairs(state.stamp) do stamp:SetVertexColor(0,0,0,1) end
        clearText(state.gcdText)
        state.gcdEligibility:SetVertexColor(1,.65,0,1)
        for _,text in ipairs(state.cooldownTexts) do clearText(text) end
    end
    function ns.observeNativeCooldown(tile)
        local state=ns.nativeSignals
        if not state or not state.enabled or not state.cooldownCollecting or state.cooldownOverflow then return end
        local known=public(tile.known);local id=number(tile.spellID,2147483647)
        if known~=true or not id or id==0 or state.cooldownSeen[id] then return end
        state.cooldownSeenCount=state.cooldownSeenCount+1
        if state.cooldownSeenCount>128 then state.cooldownOverflow=true;return end
        state.cooldownSeen[id]=true
    end
    function ns.commitNativeCooldownBatch()
        local state=ns.nativeSignals;if not state or not state.enabled then return end
        local ids={}
        if state.cooldownCollecting and not state.cooldownOverflow then for id in pairs(state.cooldownSeen) do ids[#ids+1]=id end end
        table.sort(ids)
        local signature=table.concat(ids,",")
        if state.cooldownSignature~=signature then state.cooldownRevision=(state.cooldownRevision+1)%4294967296;state.cooldownSignature=signature end
        state.cooldownIDs=ids;state.cooldownBatchReady=state.cooldownCollecting==true;state.cooldownCollecting=false;state.cooldownSeen=nil
    end
    function ns.endNativeCooldownBatch()
        local state=ns.nativeSignals;if not state then return end
        -- A failed/non-dense publication has no current batch to commit.
        if state.cooldownCollecting then state.cooldownCollecting=false;state.cooldownBatchReady=false;state.cooldownSeen=nil end
    end
    function ns.configureNativeSignals(profile)
        if not profile or number(profile.nativeSignalsTop,65535)==nil or profile.nativeSignalsHeight~=58 then
            local state=ns.nativeSignals;if state then state.enabled=false;ns.clearNativeSignals();state.frame:Hide() end;return
        end
        local state=signalState();state.enabled=false;ns.clearNativeSignals()
        state.frame:ClearAllPoints();state.frame:SetPoint("TOPLEFT",S.hud,"TOPLEFT",0,-profile.nativeSignalsTop)
        state.page=-1;state.enabled=true;state.frame:Show()
    end
    function ns.retireNativeSignalAuras(owner)
        local state=ns.nativeSignals;if not state then return end
        for _,entry in ipairs(state.entries) do if entry.owner==owner then
            entry.active=false;entry.assigned=0
            if entry.wrapper and query(InCombatLockdown)==false then pcall(entry.wrapper.SetAlpha,entry.wrapper,0) end
        end end
        state.auraVisibilityCertified=false;state.auraVisiblePage=nil
        state.revision=(state.revision+1)%4294967296
    end
    -- Declare in the ordered public spec loop, before any native button is
    -- allocated. Aura arrival order can therefore never renumber a page.
    function ns.declareNativeSignalAura(owner,key,unit,revision,filter,proof)
        if query(InCombatLockdown)~=false or type(key)~="string" or #key<1 or #key>80 or key:find("[^A-Za-z0-9_.%-]") or not signalUnits[unit] then return nil end
        local family=key:match("^([a-z]+)%.");local class=ns.features.GroupContext.text(ns.features.GroupContext.read(UnitClass,2,"player"),16)
        if not family or family:upper()~=class then return nil end
        local state=signalState();local lookup=unit..":"..key;local entry=state.byKey[lookup]
        if not entry then
            if #state.entries>=64 then state.registryFull=true;return nil end
            entry={index=#state.entries+1,key=key,unit=unit};state.entries[entry.index]=entry;state.byKey[lookup]=entry
        end
        if entry.wrapper then pcall(entry.wrapper.SetAlpha,entry.wrapper,0) end
        entry.owner=owner;entry.revision=number(revision,4294967295) or 0;entry.filter=signalFilters[filter] or 0
        entry.proof=number(proof,2) or 0;entry.assigned=0;entry.active=true;entry.wrapper=nil
        state.auraVisibilityCertified=false;state.auraVisiblePage=nil
        state.revision=(state.revision+1)%4294967296
        return entry.index
    end
    local function numberFormatter(format)
        assert(type(C_StringUtil)=="table" and type(C_StringUtil.CreateNumericRuleFormatter)=="function","Native number formatter unavailable")
        local formatter=C_StringUtil.CreateNumericRuleFormatter();formatter:SetBreakpoints({{threshold=0,format=format}});return formatter
    end
    function ns.attachNativeSignalAura(index,button)
        local state=ns.nativeSignals;local entry=state and state.entries[index or 0]
        if not entry or not entry.active or query(InCombatLockdown)~=false then return false end
        state.auraVisibilityCertified=false;state.auraVisiblePage=nil
        local ok,err=pcall(function()
            local x=80+(entry.index-1)%5*112
            -- These ordinary wrappers/fonts must remain descendants of the
            -- AuraButton. Their anchors never change after native adoption.
            local wrapper=CreateFrame("Frame",nil,button);entry.wrapper=wrapper
            wrapper:SetSize(112,18);wrapper:SetPoint("TOPLEFT",state.frame,"TOPLEFT",x,-40);wrapper:SetAlpha(0);wrapper:EnableMouse(false)
            local presence=wrapper:CreateTexture(nil,"OVERLAY");presence:SetSize(4,4);presence:SetPoint("TOPLEFT",8+(entry.index-1)%5*10-x,-7);presence:SetColorTexture(0,1,0,1)
            entry.duration=font(wrapper,0,0,80,18);entry.stacks=font(wrapper,80,0,32,18)
            local durationOK=pcall(function()button:SetDurationText(entry.duration,{textFormatter=numberFormatter("%.1f")})end)
            local countOK=pcall(function()button:SetApplicationCount(entry.stacks,{formatter=numberFormatter("%.0f")})end)
            entry.assigned=(durationOK and 1 or 0)+(countOK and 2 or 0)
        end)
        if not ok then entry.assigned=0;entry.error=S.describe(err);if entry.wrapper then pcall(entry.wrapper.SetAlpha,entry.wrapper,0) end;return false end
        entry.error=nil;return true
    end
    local function nativeTimer(text,fn,unit,allowed)
        clearText(text)
        if not allowed or type(fn)~="function" then return {status=0,value=0},false end
        local ok,duration=pcall(fn,unit)
        if not ok then return {status=3,value=0},false end
        if not S.isSecret(duration) and duration==nil then return {status=0,value=0},false end
        local obtained,value=pcall(function()return duration:GetRemainingDuration()end)
        if not obtained then return {status=3,value=0},false end
        local status,numeric
        if S.isSecret(value) then status=2
        elseif type(value)=="number" and value>=0 and value<=86400 and value==value then
            -- Match native %.1f rounding only after the public-value guard.
            status=1;numeric=math.floor(tonumber(string.format("%.1f",value))*10+.5)
        elseif value==nil then return {status=0,value=0},false
        else return {status=3,value=0},false end
        local accepted=pcall(text.SetFormattedText,text,"%.1f",value);if not accepted then clearText(text) end
        return {status=status,value=numeric or 0},accepted
    end
    local function outerSources(outer)
        local result={};local at=20;local count=string.byte(outer,17)
        for _=1,count do
            local id=string.byte(outer,at);local length=unsignedLE(outer,at+3,2)
            assert(id and length and at+4+length<=#outer-4,"Native signal main source invalid")
            result[id]=outer:sub(at+5,at+4+length);at=at+5+length
        end
        assert(at==#outer-3,"Native signal main framing invalid");return result
    end
    local function gcdProbe(state,session,classID)
        if not state.cooldownBatchReady then return 0 end
        local signature=session..":"..classID..":"..state.cooldownSignature
        if state.gcdProbeSignature~=signature then
            state.gcdProbeSignature=signature;state.gcdProbeID=0;state.gcdProbeCandidates={};state.gcdProbeCursor=1
            if type(GetSpellBaseCooldown)=="function" then
                for _,id in ipairs(state.cooldownIDs) do
                    -- The old virtual probe is retained by historical readers,
                    -- never queried by this current known-spell producer.
                    if id~=61304 then
                        local ok,base,global=pcall(GetSpellBaseCooldown,id)
                        base=ok and public(base) or nil;global=ok and public(global) or nil
                        if type(base)=="number" and base==0 and type(global)=="number" and global>0 and global<math.huge then state.gcdProbeCandidates[#state.gcdProbeCandidates+1]=id end
                    end
                end
            end
        end
        state.gcdProbeID=state.gcdProbeCandidates[state.gcdProbeCursor] or 0
        return state.gcdProbeID
    end
    local function gcdEligibility(state,id)
        local marker=state.gcdEligibility
        if not pcall(marker.SetVertexColor,marker,1,.65,0,1) then return false end
        if id==0 then return false end
        local enabled=S.safeField(S.readableCall(S.spellAPI.GetSpellCooldown,id),"isEnabled")
        if enabled~=true then
            if enabled==false then marker:SetVertexColor(1,0,0,1) end
            -- Select at most one candidate per batch. Only public eligibility
            -- is cached; held/unavailable sources advance on the NEXT batch.
            state.gcdProbeCursor=state.gcdProbeCursor%math.max(1,#state.gcdProbeCandidates)+1
            return false
        end
        if type(S.spellAPI.GetSpellCooldownDuration)~="function" then return false end
        local ok,duration=pcall(S.spellAPI.GetSpellCooldownDuration,id,true)
        if not ok or not S.isSecret(duration) and duration==nil then return false end
        local got,expired=pcall(function()return duration:HasExpired()end)
        if not got or not S.isSecret(expired) and type(expired)~="boolean" then return false end
        return pcall(function()
            assert(type(C_CurveUtil)=="table" and type(C_CurveUtil.EvaluateColorFromBoolean)=="function" and type(CreateColor)=="function")
            if state.gcdColorFactory~=CreateColor then
                local colors={CreateColor(0,1,0,1),CreateColor(1,0,0,1)}
                state.gcdColors=colors;state.gcdColorFactory=CreateColor
            end
            -- Forward even a restricted boolean directly to native color.
            -- No branch, comparison, serialization or cached observation.
            local color=C_CurveUtil.EvaluateColorFromBoolean(expired,state.gcdColors[1],state.gcdColors[2])
            marker:SetVertexColor(color:GetRGBA())
        end)
    end
    function ns.refreshNativeSignals(tick,outer)
        local state=ns.nativeSignals;if not state or not state.enabled then return end
        local vitals=ns.productionVitals
        assert(vitals and vitals.packet and vitals.tick==tick and vitals.packet:sub(1,4)=="FHV3","Native signals await current vitals")
        local session=number(S.setupSession,4294967295);local generation=number(S.auraGeneration,255)
        assert(type(outer)=="string" and outer:sub(1,4)=="HHD2" and unsignedLE(outer,5,4)==session and unsignedLE(outer,9,4)==tick and string.byte(outer,16)==generation,"Native signal envelope context changed")
        local sources=outerSources(outer);local lifecycle=sources[13]
        assert(lifecycle and #lifecycle==21 and lifecycle:sub(1,4)=="PCS1" and unsignedLE(lifecycle,5,4)==session,"Native signal lifecycle source unavailable")
        local serial,kind,id=unsignedLE(lifecycle,9,4),string.byte(lifecycle,13),unsignedLE(lifecycle,14,4)
        local currentSerial,currentKind,currentID=ns.features.CastTracking.activityRecord()
        assert(serial==currentSerial and kind==currentKind and id==currentID,"Native signal player lifecycle changed")
        local enemy=sources[8];local targetSequence,targetChecksum,targetLead,targetKind=0,0,0,0
        if enemy and enemy:sub(1,4)=="HHE2" and unsignedLE(enemy,5,4)==session and string.byte(enemy,13)==generation then
            local n=string.byte(enemy,18)
            if n and #enemy==32+n then
                targetSequence=unsignedLE(enemy,20+n,2);targetChecksum=unsignedLE(enemy,#enemy-3,4);targetLead=unsignedLE(enemy,23+n,2)
                if string.byte(enemy,19+n)==2 then targetKind=string.byte(enemy,22+n) end
            end
        end
        local enemySequence=ns.features.Interrupts and ns.features.Interrupts.activitySequence
        if type(enemySequence)~="function" or query(enemySequence)~=targetSequence then targetKind=0 end
        for _,stamp in ipairs(state.stamp) do stamp:SetVertexColor(0,0,0,1) end
        state.packet=nil
        local values,mask={},0;local classID=string.byte(outer,13)
        local comboAllowed=(classID==5 or classID==6) and query(UnitExists,"player")==true
        local combo,comboValid=nativeNumber(state.fast[1],function()return GetComboPoints("player","target")end,"player",comboAllowed)
        values[1]=combo;if comboValid then mask=1 end
        local comboMax=255
        local enum=type(Enum)=="table" and type(Enum.PowerType)=="table" and number(Enum.PowerType.ComboPoints,254) or nil
        if comboAllowed and enum then local maximum=number(query(UnitPowerMax,"player",enum),254);if maximum and maximum>0 then comboMax=maximum end end
        for i,spec in ipairs({{UnitCastingDuration,"player",kind==2},{UnitChannelDuration,"player",kind==3},{UnitCastingDuration,"target",targetKind==1},{UnitChannelDuration,"target",targetKind==2}}) do
            local value,valid=nativeTimer(state.fast[i+1],spec[1],spec[2],spec[3]);values[i+1]=value;if valid then mask=mask+2^i end
        end
        local pages=math.max(1,math.ceil(#state.entries/5))
        local cdIDs=state.cooldownBatchReady and state.cooldownIDs or {}
        local cdPages=math.max(1,math.ceil(#cdIDs/3))
        state.cooldownPage=((state.cooldownPage or -1)+1)%cdPages
        local cdPage=state.cooldownPage
        local pageKind=3
        if query(InCombatLockdown)==false then
            state.page=(state.page+1)%pages
            local configured=hideSignalWrappers(state,false)
            if configured then
                for index=state.page*5+1,math.min(state.page*5+5,#state.entries) do
                    local entry=state.entries[index]
                    if entry.active and entry.wrapper and not pcall(entry.wrapper.SetAlpha,entry.wrapper,1) then configured=false end
                end
            end
            state.auraVisibilityCertified=configured
            state.auraVisiblePage=configured and state.page or nil
            if configured then pageKind=2;state.lastAuraError=nil
            else recordNativeError(state,"Native aura page visibility unavailable",false) end
        end
        local auraPage=state.auraVisibilityCertified and number(state.auraVisiblePage,pages-1) or nil
        local records={}
        for _,text in ipairs(state.cooldownTexts) do clearText(text) end
        for index=(auraPage or 0)*5+1,math.min((auraPage or 0)*5+5,#state.entries) do
            local entry=state.entries[index]
            if auraPage~=nil and entry.active then
                records[#records+1]=S.bytes(index,1)..S.bytes(#entry.key,1)..entry.key..S.bytes(signalUnits[entry.unit],1)..S.bytes(entry.revision,4)
                    ..S.bytes(entry.filter,1)..S.bytes(entry.proof,1)..S.bytes(0,1)..S.bytes(entry.assigned,1)
            end
        end
        local api=S.spellAPI.GetSpellCooldownDuration
        local function cooldown(text,id,ignoreGCD,allowed)
            local getter=type(api)=="function" and function()return api(id,ignoreGCD)end or nil
            return nativeTimer(text,getter,nil,allowed)
        end
        local gcdID=gcdProbe(state,session,classID)
        local gcdWitnessValid=gcdEligibility(state,gcdID)
        local gcd,gcdValid=cooldown(state.gcdText,gcdID,false,gcdID>0)
        if not gcdWitnessValid then gcd={status=0,value=0};gcdValid=false;clearText(state.gcdText) end
        local cooldownRecords={}
        do
            for index=cdPage*3+1,math.min(cdPage*3+3,#cdIDs) do
                local text=state.cooldownTexts[(index-1)%3+1]
                local remaining,assigned=cooldown(text,cdIDs[index],true,true)
                cooldownRecords[#cooldownRecords+1]=S.bytes(index,1)..S.bytes(cdIDs[index],4)..S.bytes(2,1)
                    ..S.bytes(remaining.status,1)..S.bytes(remaining.value,4)..S.bytes(assigned and 1 or 0,1)
            end
        end
        local finalSerial,finalKind,finalID=ns.features.CastTracking.activityRecord()
        assert(session==number(S.setupSession,4294967295) and generation==number(S.auraGeneration,255) and serial==finalSerial and kind==finalKind and id==finalID,"Native signal batch context changed")
        local hover=productionMouseoverGeneration(classID)
        assert(hover and hover==unsignedLE(vitals.packet,20,4),"Native signal hover context changed")
        if targetKind~=0 then assert(query(enemySequence)==targetSequence,"Native signal enemy lifecycle changed") end
        local body=S.bytes(session,4)..S.bytes(tick,4)..S.bytes(unsignedLE(outer,#outer-3,4),4)..S.bytes(unsignedLE(vitals.packet,#vitals.packet-3,4),4)
            ..S.bytes(generation,1)..S.bytes(hover,4)..S.bytes(serial,4)..S.bytes(kind,1)..S.bytes(id,4)
            ..S.bytes(targetSequence,2)..S.bytes(targetChecksum,4)..S.bytes(targetLead,2)..S.bytes(state.revision,4)..S.bytes(auraPage or 0,1)..S.bytes(pages,1)..S.bytes(#records,1)
        for _,value in ipairs(values) do body=body..S.bytes(value.status,1)..S.bytes(value.value,4) end
        body=body..S.bytes(mask,1)..S.bytes(comboMax,1)..table.concat(records)
        body=body..S.bytes(pageKind,1)..S.bytes(gcdID,4)..S.bytes(gcd.status,1)..S.bytes(gcd.value,4)..S.bytes(gcdValid and 1 or 0,1)
            ..S.bytes(state.cooldownRevision,4)..S.bytes(cdPage,1)..S.bytes(cdPages,1)..S.bytes(#cooldownRecords,1)..table.concat(cooldownRecords)
        local packet="FHS3"..S.bytes(4+2+#body+4,2)..body;packet=packet..S.bytes(S.adler32(packet),4)
        paintProduction(state,packet)
        local a,b,c,d=string.byte(packet,#packet-3,#packet)
        state.stamp[1]:SetVertexColor(a/255,b/255,c/255,1);state.stamp[2]:SetVertexColor(d/255,0,0,1)
        state.packet=packet;state.tick=tick;state.lastError=nil;clearText(state.errorText)
    end


end
