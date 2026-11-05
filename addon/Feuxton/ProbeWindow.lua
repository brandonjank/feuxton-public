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

-- Opt-in transport/native-color laboratory. Loaded through the existing TOC;
-- independent of the production bridge and never supplies casting observations.
function ns.initializePixelExperiment(requested)
    if ns.pixelExperiment and ns.pixelExperiment.frame then return end
    if not requested then
        -- No laboratory textures, status bars or update callbacks in production.
        ns.pixelExperiment={enabled=false,tick=0,errors={}}
        SLASH_FEUXTONPIXELTEST1="/feuxtonpixeltest"
        SlashCmdList.FEUXTONPIXELTEST=function(message)
            message=(message or ""):lower():match("^%s*(.-)%s*$")
            if message=="off" or message=="report" then print("Feuxton pixel lab: OFF (not allocated)");return end
            ns.initializePixelExperiment(true)
            SlashCmdList.FEUXTONPIXELTEST(message)
        end
        return
    end
    local lab={enabled=false,tick=0,mask=0,errors={},metrics={},grids={}}
    ns.pixelExperiment=lab
    -- Inherit the bridge's root-to-physical scaling, including changes at login.
    local frame=CreateFrame("Frame","FeuxtonPixelExperiment",S.hud)
    lab.frame=frame;frame:SetSize(208,152);frame:SetFrameStrata("HIGH")
    frame:SetPoint("BOTTOMLEFT",S.hud,"TOPLEFT",0,8)
    frame:SetMovable(true);frame:SetClampedToScreen(true)
    local bg=frame:CreateTexture(nil,"BACKGROUND");bg:SetAllPoints();bg:SetColorTexture(0,0,0,1)
    local function patch(x,y,size)
        local p=frame:CreateTexture(nil,"ARTWORK");p:SetSize(size,size);p:SetPoint("TOPLEFT",x,-y)
        p:SetColorTexture(1,.65,0,1);return p
    end
    for i,c in ipairs({{1,0,1},{0,1,1},{1,0,0},{0,1,0}}) do patch(4+(i-1)*5,3,3):SetColorTexture(unpack(c)) end
    for i,c in ipairs({{0,0,1},{1,1,0},{0,1,1}}) do patch(192-(i-1)*5,146,3):SetColorTexture(unpack(c)) end
    local title=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    title:SetPoint("TOPLEFT",30,-2);title:SetText("PIXEL LAB / DRAG")
    local handle=CreateFrame("Frame",nil,frame);handle:SetPoint("TOPLEFT",28,0);handle:SetSize(170,15)
    handle:EnableMouse(true);handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart",function() frame:StartMoving() end)
    handle:SetScript("OnDragStop",function() frame:StopMovingOrSizing() end)
    lab.ramp={}
    for value=0,255 do
        local p=patch(8+(value%64)*3,18+math.floor(value/64)*3,3)
        p:SetColorTexture(value/255,value/255,value/255,1);lab.ramp[#lab.ramp+1]=p
    end
    for mode,y in pairs({[12]=34,[24]=44}) do
        local cells={};lab.grids[mode]=cells
        for index=0,127 do cells[#cells+1]=patch(8+(index%64)*3,y+math.floor(index/64)*3,3) end
    end
    lab.stateCells={}
    for index=0,511 do lab.stateCells[#lab.stateCells+1]=patch(8+(index%64)*3,116+math.floor(index/64)*3,3) end
    local function curve(endpoint)
        if type(C_CurveUtil)~="table" or type(C_CurveUtil.CreateColorCurve)~="function" or type(CreateColor)~="function" then return end
        local c=C_CurveUtil.CreateColorCurve()
        c:AddPoint(0,CreateColor(0,0,0,1));c:AddPoint(endpoint,CreateColor(1,1,1,1))
        return c
    end
    for _,endpoint in ipairs({1,100}) do
        local ok,c=pcall(curve,endpoint);if ok then lab[endpoint==1 and "curve1" or "curve100"]=c end
    end
    local specs={{"player","health"},{"player","power"},{"target","health"},{"pet","health"},{"focus","health"}}
    for i,spec in ipairs(specs) do
        local bar=CreateFrame("StatusBar",nil,frame);bar:SetSize(100,4);bar:SetPoint("TOPLEFT",8,-(78+(i-1)*7))
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8");bar:SetStatusBarColor(0,1,0,1)
        local back=bar:CreateTexture(nil,"BACKGROUND");back:SetAllPoints();back:SetColorTexture(.18,.18,.18,1)
        lab.metrics[i]={unit=spec[1],kind=spec[2],one=patch(8+(i-1)*32,56,6),hundred=patch(8+(i-1)*32,64,6),vertex=patch(8+(i-1)*32,72,6),vertexValid=patch(16+(i-1)*32,73,3),bar=bar}
    end
    lab.cooldowns={}
    for i,name in ipairs({"Holy Strike","Judgement"}) do
        lab.cooldowns[i]={name=name,one=patch(124+(i-1)*32,80,6),hundred=patch(124+(i-1)*32,88,6),expired=patch(124+(i-1)*32,96,6)}
    end
    local function color(p,c) p:SetColorTexture(c:GetRGBA()) end
    local function attempt(key,p,fn)
        p:SetColorTexture(1,.65,0,1)
        local ok,err=pcall(fn)
        lab.errors[key]=not ok and S.describe(err) or nil
        return ok
    end
    local function paint(cells,packet,bits)
        local buffer,available,cursor=0,0,1
        local perChannel=bits/3;local levels=2^perChannel
        for _,p in ipairs(cells) do
            while available<bits do buffer=buffer*256+(string.byte(packet,cursor) or 0);cursor=cursor+1;available=available+8 end
            local factor=2^(available-bits);local value=math.floor(buffer/factor);buffer=buffer%factor;available=available-bits
            if p.hhLabColor~=value then
                p:SetColorTexture(math.floor(value/(levels*levels))/(levels-1),(math.floor(value/levels)%levels)/(levels-1),(value%levels)/(levels-1),1)
                p.hhLabColor=value
            end
        end
    end
    lab.paint=paint
    function lab.statePacket(now) return S.denseStatePacket(now,lab.tick) end
    function lab.publishState(now)
        local state=lab.statePacket(now);lab.lastStatePacket=state
        paint(lab.stateCells,state,24);lab.errors.state=nil
    end
    function lab.render()
        lab.tick=(lab.tick+1)%4294967296;local mask=0
        for i,m in ipairs(lab.metrics) do
            local exists=S.readableCall(UnitExists,m.unit)==true
            for domain,p in ipairs({m.one,m.hundred}) do
                local c=domain==1 and lab.curve1 or lab.curve100
                local ok=attempt(m.unit.."."..m.kind.."."..domain,p,function()
                    assert(exists and c,"native percentage unavailable")
                    if m.kind=="health" then color(p,UnitHealthPercent(m.unit,false,c))
                    else color(p,UnitPowerPercent(m.unit,nil,false,c)) end
                end)
                if ok then mask=mask+2^((domain-1)*5+i-1) end
            end
            m.vertex:SetColorTexture(1,1,1,1);m.vertex:SetVertexColor(1,1,1,1)
            local vertexOK,vertexError=pcall(function()
                assert(exists and lab.curve1,"native percentage unavailable")
                local c
                if m.kind=="health" then c=UnitHealthPercent(m.unit,false,lab.curve1)
                else c=UnitPowerPercent(m.unit,nil,false,lab.curve1) end
                m.vertex:SetVertexColor(c:GetRGBA())
            end)
            lab.errors[m.unit.."."..m.kind..".vertex"]=not vertexOK and S.describe(vertexError) or nil
            m.vertexValid:SetColorTexture(vertexOK and 0 or .2,vertexOK and 1 or .2,vertexOK and 0 or .2,1)
            local ok=pcall(function()
                assert(exists,"unit missing")
                local maximum
                if m.kind=="health" then maximum=UnitHealthMax(m.unit) else maximum=UnitPowerMax(m.unit) end
                if not S.isSecret(maximum) and (type(maximum)~="number" or maximum<=0) then error("no maximum") end
                m.bar:SetMinMaxValues(0,maximum)
                if m.kind=="health" then m.bar:SetValue(UnitHealth(m.unit)) else m.bar:SetValue(UnitPower(m.unit)) end
            end)
            if ok then mask=mask+2^(10+i-1) else m.bar:SetMinMaxValues(0,1);m.bar:SetValue(0) end
        end
        for i,m in ipairs(lab.cooldowns) do
            local duration
            local ok,value=pcall(function()
                local info=C_Spell.GetSpellInfo(m.name);local id=S.safeField(info,"spellID");assert(type(id)=="number","spell unavailable")
                return C_Spell.GetSpellCooldownDuration(id,true)
            end)
            if ok then duration=value end
            for domain,p in ipairs({m.one,m.hundred}) do
                local c=domain==1 and lab.curve1 or lab.curve100
                local ready=attempt(m.name..".remaining."..domain,p,function() assert(duration and c,"duration unavailable");color(p,duration:EvaluateRemainingPercent(c)) end)
                if ready then mask=mask+2^(15+(i-1)*3+domain-1) end
            end
            local ready=attempt(m.name..".expired",m.expired,function()
                assert(duration and type(C_CurveUtil.EvaluateColorFromBoolean)=="function","expiry color unavailable")
                color(m.expired,C_CurveUtil.EvaluateColorFromBoolean(duration:HasExpired(),CreateColor(0,1,0,1),CreateColor(.2,.2,.2,1)))
            end)
            if ready then mask=mask+2^(17+(i-1)*3) end
        end
        lab.mask=mask
        for mode,cells in pairs(lab.grids) do
            local length=mode==12 and 169 or 361
            local parts={S.bytes(mask,3)}
            for index=4,length do parts[#parts+1]=string.char((index*73+math.floor(lab.tick/17)*29+lab.tick*7)%256) end
            local packet="HHX1"..S.bytes(S.setupSession,4)..S.bytes(lab.tick,4)..S.bytes(mode,1)..S.bytes(length,2)..table.concat(parts)
            packet=packet..S.bytes(S.adler32(packet),4);paint(cells,packet,mode)
        end
        local now=S.setupNumber(S.readableCall(GetTime))
        lab.publishState(now)
        if type(FeuxtonDB)=="table" then
            FeuxtonDB.pixelExperimentReport={version=1,tick=lab.tick,mask=mask,errors=lab.errors}
        end
    end
    local total=0
    frame:SetScript("OnUpdate",function(self,elapsed)
        if not lab.enabled then return end
        total=total+elapsed;if total<S.updateInterval() then return end;total=0
        local ok,err=pcall(lab.render);if not ok then lab.errors.render=S.describe(err);frame:Hide();lab.enabled=false end
    end)
    frame:Hide()
    SLASH_FEUXTONPIXELTEST1="/feuxtonpixeltest"
    SlashCmdList.FEUXTONPIXELTEST=function(message)
        message=(message or ""):lower():match("^%s*(.-)%s*$")
        if message=="off" then lab.enabled=false;frame:Hide()
        elseif message=="report" then print("Feuxton pixel lab: tick="..lab.tick.." mask="..lab.mask);for key,err in pairs(lab.errors) do print(key..": "..err) end
        else
            lab.enabled=true;frame:Show()
            local ok,err=pcall(lab.render)
            if not ok then lab.errors.render=S.describe(err);lab.enabled=false;frame:Hide();print("Feuxton: pixel lab failed: "..lab.errors.render)
            else print("Feuxton: pixel lab ON; /feuxtonpixeltest off to hide. Read only.") end
        end
    end
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
        local packet=S.denseStatePacket(now,bridge.tick,true);bridge.lastStatePacket=packet
        bridge.paint(bridge.stateCells,packet,24);bridge.errors.state=nil
    end
    function bridge.setEnabled(enabled)
        bridge.enabled=enabled;S.denseBridgeActive=enabled
        for _,cells in ipairs({bridge.coreStamp,unpack(bridge.rosterStamps)}) do for _,p in ipairs(cells) do if enabled then p:Show() else p:Hide() end end end
        for _,p in ipairs(bridge.guideStamp) do if enabled and bridge.profile and bridge.profile.guideStamp then p:Show() else p:Hide() end end
        if enabled then frame:Show();S.denseTargetStamp:Show();S.refreshFlags();S.renderSetupPage();S.refreshTransportPacketState()
        else frame:Hide();S.denseTargetStamp:Hide() end
    end
    bridge.setEnabled(false)
end

-- Isolated, opt-in native paint comparison. No production cells, packets or
-- gameplay observations are read or changed by this experiment.
do
    local warmups,samples,cellCount=5,48,88
    local methodOrder={"direct","tint","noop"}
    local function finite(value)
        return not S.isSecret(value) and type(value)=="number" and value==value and value~=math.huge and value~=-math.huge
    end
    local function placement()
        if not S.hud or S.readableCall(S.hud.IsShown,S.hud)~=true then return nil,"Show the Feuxton HUD first." end
        local scale=S.readableCall(S.hud.GetEffectiveScale,S.hud)
        local top=S.readableCall(S.hud.GetTop,S.hud)
        local bottom=S.readableCall(S.hud.GetBottom,S.hud)
        local ok,_,height=pcall(GetPhysicalScreenSize or function()end)
        if not ok or not finite(scale) or scale<=0 or not finite(top) or not finite(bottom) or not finite(height) then return nil,"HUD screen geometry is unavailable." end
        if top*scale+148*scale<=height then return "above" end
        if bottom*scale>=148*scale then return "below" end
        return nil,"Move the HUD to leave room above or below it, then run the test again."
    end
    local function paintColors()
        local colors={}
        for channel=0,3 do for value=0,255 do
            colors[#colors+1]={(channel==0 or channel==1) and value or 0,(channel==0 or channel==2) and value or 0,(channel==0 or channel==3) and value or 0}
        end end
        for i=0,127 do colors[#colors+1]={(i*73+17)%256,(i*151+31)%256,(i*29+93)%256} end
        return colors
    end
    local function statsRow(stats)
        local sorted={}
        for i,value in ipairs(stats.values) do sorted[i]=value end
        table.sort(sorted)
        local count=#sorted
        return {calls=stats.calls,measuredCalls=stats.measuredCalls,sampleCount=count,invalidCount=stats.invalid,
            averageMs=count>0 and stats.total/count or nil,p95Ms=count>0 and sorted[math.ceil(count*.95)] or nil,maximumMs=count>0 and stats.maximum or nil}
    end
    local function writeFooter(lab,report)
        local status={idle=0,running=1,complete=2,failed=3,invalid=4,stopped=5}
        local function micros(value)
            if finite(value) and value>=0 and value<=4294967.294 then return math.floor(value*1000+.5) end
            return 4294967295
        end
        local packet="FPT1"..S.bytes(1,1)..S.bytes(status[report.status] or 0,1)..S.bytes(report.run%65536,2)..S.bytes(report.completedRounds,1)..S.bytes(cellCount,1)
        for _,method in ipairs(methodOrder) do
            local row=report.methods[method]
            packet=packet..S.bytes(micros(row.averageMs),4)..S.bytes(micros(row.p95Ms),4)..S.bytes(micros(row.maximumMs),4)..S.bytes(row.sampleCount,2)..S.bytes(row.invalidCount,2)
        end
        packet=packet..S.bytes(S.adler32(packet),4)
        assert(#packet==62,"paint-test footer capacity")
        for i,pixel in ipairs(lab.footer) do
            local at=(i-1)*3+1;local r,g,b=packet:byte(at,at+2)
            pixel:SetColorTexture((r or 0)/255,(g or 0)/255,(b or 0)/255,1)
        end
        lab.footerPacket=packet
    end
    local function save(lab,footer)
        local report={schema="FPT1",addonVersion=ns.version,status=lab.status,run=lab.run,warmupRounds=warmups,sampleRounds=samples,
            completedRounds=lab.completedRounds or 0,attemptedRounds=lab.round,witnessColors=1152,dynamicCells=cellCount,placement=lab.placement,error=lab.error,methods={}}
        for _,method in ipairs(methodOrder) do report.methods[method]=statsRow(lab.stats[method]) end
        if type(FeuxtonDB)=="table" then FeuxtonDB.paintTestReport=report end
        lab.report=report
        if footer then writeFooter(lab,report) end
        return report
    end
    local function stop(lab,status,reason)
        lab.running=false;lab.status=status;lab.error=reason
        lab.frame:SetScript("OnUpdate",nil)
        lab.title:SetText(status=="complete" and "PAINT A/B DONE / REPORT" or "PAINT A/B "..string.upper(status))
        save(lab,true)
    end
    local function initialize()
        if ns.paintMethodTest then return ns.paintMethodTest end
        local lab={round=0,run=0,stats={},running=false,status="idle",colors=paintColors(),dynamic={direct={},tint={},noop={}},orders={}}
        local frame=CreateFrame("Frame",nil,S.hud);lab.frame=frame
        frame:SetSize(400,140);frame:SetFrameStrata("TOOLTIP");frame:EnableMouse(false)
        local bg=frame:CreateTexture(nil,"BACKGROUND");bg:SetAllPoints();bg:SetColorTexture(0,0,0,1)
        local function patch(x,y,size)
            local pixel=frame:CreateTexture(nil,"ARTWORK");pixel:SetSize(size,size);pixel:SetPoint("TOPLEFT",x,-y)
            return pixel
        end
        lab.fiducials={}
        for i,color in ipairs({{1,0,1},{0,1,1},{0,1,0},{1,0,0},{0,0,1},{1,1,0}}) do
            local pixel=patch(4+(i-1)*6,3,4);pixel:SetColorTexture(unpack(color));lab.fiducials[i]=pixel
        end
        local function label(x,y,text)
            local font=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");font:SetPoint("TOPLEFT",x,-y);font:SetText(text);return font
        end
        lab.title=label(46,2,"PAINT A/B")
        label(8,11,"SetColorTexture / grayscale + RGB + mixed")
        label(8,53,"White texture + SetVertexColor / same colors")
        lab.witness={direct={},tint={}}
        for index,color in ipairs(lab.colors) do
            local x=8+((index-1)%128)*3;local row=math.floor((index-1)/128)*3
            local direct=patch(x,24+row,3);direct:SetVertexColor(1,1,1,1);direct:SetColorTexture(color[1]/255,color[2]/255,color[3]/255,1)
            local tint=patch(x,66+row,3);tint:SetColorTexture(1,1,1,1);tint:SetVertexColor(color[1]/255,color[2]/255,color[3]/255,1)
            lab.witness.direct[index]=direct;lab.witness.tint[index]=tint
        end
        for i=1,cellCount do
            local x=8+(i-1)*3
            local direct=patch(x,104,3);direct:SetVertexColor(1,1,1,1);direct:SetColorTexture(0,0,0,1)
            local tint=patch(x,110,3);tint:SetColorTexture(1,1,1,1);tint:SetVertexColor(0,0,0,1)
            lab.dynamic.direct[i]=direct;lab.dynamic.tint[i]=tint
            lab.dynamic.noop[i]={SetColorTexture=function()end}
        end
        lab.footer={}
        for i=0,20 do local pixel=patch(8+i*3,128,3);pixel:SetColorTexture(0,0,0,1);lab.footer[#lab.footer+1]=pixel end
        frame:Hide();ns.paintMethodTest=lab
        return lab
    end
    local function preparedColors(round)
        local colors={}
        for i=1,cellCount do colors[i]={((i*73+17+round*31)%256)/255,((i*151+31+round*43)%256)/255,((i*29+93+round*59)%256)/255} end
        return colors
    end
    local function apply(lab,method,colors)
        local cells=lab.dynamic[method]
        if method=="tint" then
            for i,color in ipairs(colors) do cells[i]:SetVertexColor(color[1],color[2],color[3],1) end
        else
            for i,color in ipairs(colors) do cells[i]:SetColorTexture(color[1],color[2],color[3],1) end
        end
    end
    local function step(lab)
        lab.round=lab.round+1
        -- All RGB generation/division occurs before any measurement clock.
        local colors=preparedColors(lab.round);lab.preparedColors=colors;local order={}
        for offset=0,2 do order[#order+1]=methodOrder[(lab.round-1+offset)%3+1] end
        lab.orders[#lab.orders+1]=table.concat(order,",")
        for _,method in ipairs(order) do
            local before=S.profileClock()
            local ok,err=pcall(apply,lab,method,colors)
            local after=S.profileClock()
            if not ok then stop(lab,"failed",method..": "..S.describe(err));print("Feuxton paint test failed; /feuxtonpainttest report for details.");return end
            local row=lab.stats[method];row.calls=row.calls+cellCount
            if lab.round>warmups then
                row.measuredCalls=row.measuredCalls+cellCount
                if finite(before) and finite(after) and after>=before then
                    local elapsed=after-before;row.values[#row.values+1]=elapsed;row.total=row.total+elapsed;row.maximum=math.max(row.maximum,elapsed)
                else row.invalid=row.invalid+1 end
            end
        end
        lab.completedRounds=lab.round
        lab.title:SetText("PAINT A/B "..lab.round.."/"..(warmups+samples))
        if lab.round>=warmups+samples then
            local valid=true;for _,method in ipairs(methodOrder) do if lab.stats[method].invalid>0 then valid=false end end
            stop(lab,valid and "complete" or "invalid",valid and nil or "Some timing samples were unavailable.")
            print("Feuxton paint test finished; /feuxtonpainttest report. Witness colors remain visible; /feuxtonpainttest off hides them.")
        end
    end
    function ns.runPaintMethodTest()
        if S.performance and S.performance.enabled then print("Feuxton: run /feuxtonperf off before the paint test.");return false end
        if ns.pixelExperiment and ns.pixelExperiment.enabled then print("Feuxton: run /feuxtonpixeltest off before the paint test.");return false end
        local position,reason=placement()
        if not position then print("Feuxton: "..reason);return false end
        local lab=initialize();lab.frame:SetScript("OnUpdate",nil);lab.frame:ClearAllPoints()
        if position=="above" then lab.frame:SetPoint("BOTTOMLEFT",S.hud,"TOPLEFT",0,8)
        else lab.frame:SetPoint("TOPLEFT",S.hud,"BOTTOMLEFT",0,-8) end
        lab.placement=position;lab.run=lab.run+1;lab.round=0;lab.completedRounds=0;lab.elapsed=0;lab.orders={};lab.error=nil;lab.status="running";lab.running=true;lab.stats={}
        for _,method in ipairs(methodOrder) do lab.stats[method]={calls=0,measuredCalls=0,values={},invalid=0,total=0,maximum=0} end
        lab.title:SetText("PAINT A/B RUNNING");lab.frame:Show()
        save(lab,true)
        lab.frame:SetScript("OnUpdate",function(_,elapsed)
            if not lab.running then return end
            lab.elapsed=lab.elapsed+elapsed;if lab.elapsed<.1 then return end;lab.elapsed=0
            step(lab)
        end)
        print("Feuxton: paint test running for 53 bounded rounds; production rendering is unchanged.")
        return true
    end
    SLASH_FEUXTONPAINTTEST1="/feuxtonpainttest"
    SlashCmdList.FEUXTONPAINTTEST=function(message)
        message=(message or ""):lower():match("^%s*(.-)%s*$")
        if message=="run" or message=="on" then ns.runPaintMethodTest();return end
        local lab=ns.paintMethodTest
        if message=="off" then
            if lab then if lab.running then stop(lab,"stopped") end;lab.frame:SetScript("OnUpdate",nil);lab.frame:Hide() end
            print("Feuxton paint test OFF.");return
        end
        if message=="report" then
            if not lab then print("Feuxton: no paint test yet; /feuxtonpainttest run.");return end
            local report=save(lab)
            local lines={"Feuxton paint comparison · "..ns.version,"Schema FPT1 · "..report.status.." · "..report.completedRounds.."/53 rounds",
                "5 warm-up rounds; 48 measured rounds; 88 calls per method per round. Alternating order; identical prepared colors.",
                "Witness: 1152 colors per method (256 grayscale, 256 each red/green/blue, 128 mixed). Production painter unchanged."}
            for _,method in ipairs(methodOrder) do
                local row=report.methods[method]
                local result=row.sampleCount>0 and string.format("avg %.4f / p95 %.4f / max %.4f ms",row.averageMs,row.p95Ms,row.maximumMs) or "timing unavailable"
                lines[#lines+1]=string.format("%s: %s; %d/48 samples, %d invalid; %d measured / %d completed-batch calls",method,result,row.sampleCount,row.invalidCount,row.measuredCalls,row.calls)
            end
            if report.error then lines[#lines+1]="Failure: "..report.error end
            lines[#lines+1]="Batch times include loop/call overhead; noop is only a control. Deferred GPU cost is not measured. Screen RGB agreement must be verified separately."
            S.edit:SetText(table.concat(lines,"\n"));S.panel:Show();S.edit:SetFocus();S.edit:HighlightText();return
        end
        print("Feuxton: /feuxtonpainttest run, /feuxtonpainttest report, /feuxtonpainttest off.")
    end
end
