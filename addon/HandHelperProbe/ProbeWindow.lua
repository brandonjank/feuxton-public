-- Diagnostic report window and /hhprobe command.
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
S.title:SetText("Hand Helper — select text and press Ctrl+C")
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
SLASH_HANDHELPERPROBE1 = "/hhprobe"
SlashCmdList.HANDHELPERPROBE = function(message)
    message=(message or ""):lower():match("^%s*(.-)%s*$")
    if message=="capture" then
        local ok,snapshot=pcall(S.captureCapabilities)
        if ok then print("Hand Helper: saved "..snapshot.mode.." API snapshot ("..S.capabilitySummary(snapshot)..").")
        else print("Hand Helper: API snapshot failed: "..S.describe(snapshot)) end
        return
    elseif message~="" and message~="compare" then
        print("Hand Helper: /hhprobe, /hhprobe capture (no popup), /hhprobe compare")
        return
    end
    local ok,text=pcall(message=="compare" and S.compareCapabilities or S.report)
    if not ok then print("Hand Helper: capability report failed: "..S.describe(text)); return end
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
        SLASH_HANDHELPERPIXELTEST1="/hhpixeltest"
        SlashCmdList.HANDHELPERPIXELTEST=function(message)
            message=(message or ""):lower():match("^%s*(.-)%s*$")
            if message=="off" or message=="report" then print("Hand Helper pixel lab: OFF (not allocated)");return end
            ns.initializePixelExperiment(true)
            SlashCmdList.HANDHELPERPIXELTEST(message)
        end
        return
    end
    local lab={enabled=false,tick=0,mask=0,errors={},metrics={},grids={}}
    ns.pixelExperiment=lab
    -- Inherit the bridge's root-to-physical scaling, including changes at login.
    local frame=CreateFrame("Frame","HandHelperPixelExperiment",S.hud)
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
        if type(HandHelperProbeDB)=="table" then
            HandHelperProbeDB.pixelExperimentReport={version=1,tick=lab.tick,mask=mask,errors=lab.errors}
        end
    end
    local total=0
    frame:SetScript("OnUpdate",function(self,elapsed)
        if not lab.enabled then return end
        total=total+elapsed;if total<S.updateInterval() then return end;total=0
        local ok,err=pcall(lab.render);if not ok then lab.errors.render=S.describe(err);frame:Hide();lab.enabled=false end
    end)
    frame:Hide()
    SLASH_HANDHELPERPIXELTEST1="/hhpixeltest"
    SlashCmdList.HANDHELPERPIXELTEST=function(message)
        message=(message or ""):lower():match("^%s*(.-)%s*$")
        if message=="off" then lab.enabled=false;frame:Hide()
        elseif message=="report" then print("Hand Helper pixel lab: tick="..lab.tick.." mask="..lab.mask);for key,err in pairs(lab.errors) do print(key..": "..err) end
        else
            lab.enabled=true;frame:Show()
            local ok,err=pcall(lab.render)
            if not ok then lab.errors.render=S.describe(err);lab.enabled=false;frame:Hide();print("Hand Helper: pixel lab failed: "..lab.errors.render)
            else print("Hand Helper: pixel lab ON; /hhpixeltest off to hide. Read only.") end
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
    for i=0,767 do local p=patch(frame,8+i%128*3,10+math.floor(i/128)*3);p:SetColorTexture(0,0,0,1);p.hhBridgeColor=0;bridge.stateCells[#bridge.stateCells+1]=p end
    -- Production owns its painter; the optional laboratory is not a dependency.
    -- Visit only current/previous payload cells, clearing a shrinking packet tail.
    function bridge.paint(cells,packet)
        local used=math.ceil(#packet/3);local limit=math.max(used,bridge.paintedCells or 0)
        assert(used<=#cells,"dense paint capacity exceeded")
        local writes=0
        for i=1,limit do
            local at=(i-1)*3+1;local r,g,b=string.byte(packet,at,at+2)
            r,g,b=r or 0,g or 0,b or 0
            local value=r*65536+g*256+b;local p=cells[i]
            if p.hhBridgeColor~=value then p:SetColorTexture(r/255,g/255,b/255,1);p.hhBridgeColor=value;writes=writes+1 end
        end
        bridge.paintedCells=used;bridge.paintVisits=limit;bridge.paintWrites=writes
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
