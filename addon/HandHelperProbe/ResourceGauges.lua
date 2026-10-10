-- Native player / pet health and resource gauges.
local _, ns = ...
local S = ns.state

-- Player/pet gauges render secret values through native StatusBars. Only the
-- success/existence markers are readable in Lua; the app estimates visible fill.
do
    local panel=CreateFrame("Frame",nil,S.hud)
    S.resourcePanel=panel
    panel:SetPoint("TOPLEFT",S.hud,"TOPLEFT",0,-356); panel:SetSize(668,52)
    S.hud:SetClampRectInsets(0,0,0,-394)
    local bg=panel:CreateTexture(nil,"BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0,0,0,1);S.resourceBackground=bg
    for i,color in ipairs({{0,1,1},{1,0,1},{1,1,0}}) do
        local marker=panel:CreateTexture(nil,"OVERLAY"); marker:SetSize(4,4)
        marker:SetPoint("TOPLEFT",4+(i-1)*6,0); marker:SetColorTexture(color[1],color[2],color[3],1)
    end
    local displays={}; S.resourceDisplays=displays
    for i,unit in ipairs({"player","pet"}) do
        local x=12+(i-1)*328
        local label=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    S.bridgeLabel(label)
        label:SetPoint("TOPLEFT",x,-5); label:SetText(i==1 and "PLAYER" or "PET")
        for j,kind in ipairs({"health","power"}) do
            local bar=CreateFrame("StatusBar",nil,panel)
            bar:SetPoint("TOPLEFT",x,-20-(j-1)*16); bar:SetSize(250,10)
            bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
            bar:SetStatusBarColor(0,kind=="health" and 1 or 0.5,kind=="health" and 0 or 1,1)
            local background=bar:CreateTexture(nil,"BACKGROUND"); background:SetAllPoints(); background:SetColorTexture(0.18,0.18,0.18,1)
            local dot=panel:CreateTexture(nil,"OVERLAY"); dot:SetSize(6,6)
            dot:SetPoint("TOPLEFT",x+255,-22-(j-1)*16); S.drawFlag(dot,nil)
            displays[#displays+1]={unit=unit,kind=kind,bar=bar,dot=dot}
        end
    end
    local elapsedTotal=0
    panel:SetScript("OnUpdate",function(self,elapsed)
        elapsedTotal=elapsedTotal+elapsed; if elapsedTotal<S.updateInterval() then return end; elapsedTotal=0
        for _,display in ipairs(displays) do
            local exists=S.readableCall(UnitExists,display.unit)
            local rendered=false
            if exists==true then
                rendered=pcall(function()
                    local maximum
                    if display.kind=="health" then maximum=UnitHealthMax(display.unit) else maximum=UnitPowerMax(display.unit) end
                    -- Check only a readable zero maximum; secret maxima go
                    -- straight to the native widget without comparisons.
                    if not S.isSecret(maximum) and type(maximum)=="number" and maximum<=0 then error("No gauge maximum") end
                    display.bar:SetMinMaxValues(0,maximum)
                    if display.kind=="health" then display.bar:SetValue(UnitHealth(display.unit))
                    else display.bar:SetValue(UnitPower(display.unit)) end
                end)
            end
            S.drawFlag(display.dot,rendered and true or nil)
            if not rendered then display.bar:SetMinMaxValues(0,1); display.bar:SetValue(0) end
        end
    end)
end

-- One shared native gauge layout for every class. Secret values still go
-- directly to StatusBars; geometry and labels are ordinary configuration.
do
    local labels={}
    for i,name in ipairs({"PLAYER","PET","TARGET","TARGET'S TARGET"}) do
        local label=S.resourcePanel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        label:SetPoint("TOPLEFT",i==1 and 32 or 12+(i-1)*164,0);label:SetWidth(128);label:SetJustifyH("LEFT");label:SetText(name);label:Hide();labels[i]=label
    end
    ns.configureCompactGauges=function(profile)
        local enabled=profile and profile.gauges~=nil
        local function point(widget,x,y) widget:ClearAllPoints();widget:SetPoint("TOPLEFT",S.hud,"TOPLEFT",x,-y) end
        for _,label in ipairs(labels) do if enabled then label:Show() else label:Hide() end end
        if enabled then S.unitBackground:Hide();S.resourceBackground:Hide() else S.unitBackground:Show();S.resourceBackground:Show() end
        for _,display in ipairs(S.unitDisplays) do
            display.health:SetSize(enabled and 128 or 250,enabled and 4 or 16)
            display.health:SetStatusBarTexture(enabled and "Interface\\Buttons\\WHITE8X8" or "Interface\\TargetingFrame\\UI-StatusBar")
        end
        for _,display in ipairs(S.resourceDisplays) do display.bar:SetSize(enabled and 128 or 250,enabled and 4 or 10) end
        if not enabled then return end
        local top=profile.gauges
        for i,display in ipairs(S.resourceDisplays) do
            local x=i<=2 and 12 or 176;local y=top+12+((i-1)%2)*8
            point(display.bar,x,y);point(display.dot,x+132,y)
        end
        for i,display in ipairs(S.unitDisplays) do
            local x=340+(i-1)*164
            point(display.health,x,top+12);point(display.available,x+132,top+12);point(display.combat,x+142,top+12)
            display.name:Hide()
        end
        point(S.playerAlive,644,top)
        -- Keep the absolute Sting budget at its proven 250-pixel precision.
        point(S.stingBudget,340,top+20)
        for i,dot in ipairs({S.stingBudgetReady,S.stingBudgetMarkerA,S.stingBudgetMarkerB,S.stingBudgetDamage,S.stingBudgetID,S.stingBudgetDirect}) do point(dot,596+(i-1)*8,top+20) end
        if profile.guideStamp then
            point(S.tiles[21],126,114)
            for i,dot in ipairs(S.tiles[21].visualSignals) do dot:ClearAllPoints();dot:SetPoint("TOPLEFT",S.tiles[21],"TOPLEFT",30+(i-1)*7,-34) end
        end
    end
end



ns.features.Interrupts.initialize()
ns.features.GroupContext.initialize()
ns.classes.PALADIN.initializePreview()
ns.initializePixelExperiment()
ns.initializeDenseBridge()

-- Read-only, lazy native-gauge laboratory. Never supplies production readings.
SLASH_HANDHELPERGAUGETEST1="/hhgaugetest"
SlashCmdList.HANDHELPERGAUGETEST=function(message)
    message=(message or ""):lower():match("^%s*(.-)%s*$")
    local lab=ns.gaugeExperiment
    if message=="off" then if lab then lab.frame:Hide() end;return end
    if message=="report" then
        if not lab then print("Hand Helper: run /hhgaugetest on first.");return end
        for _,name in ipairs({"reference","folded"}) do
            local stat=lab.costs[name]
            if stat.calls>0 then print(string.format("Gauge %s: %.4f ms average, %.4f ms max, %d updates",name,stat.total/stat.calls,stat.maximum,stat.calls))
            else print("Gauge "..name..": timings unavailable") end
        end
        print("Native update submission only; excludes deferred rendering. Saved on /reload.");return
    end
    if message~="" and message~="on" then print("Hand Helper: /hhgaugetest on, off, report.");return end
    if not lab then
        lab={rows={},errors={},costs={reference={calls=0,total=0,maximum=0},folded={calls=0,total=0,maximum=0}}};ns.gaugeExperiment=lab
        -- Bounded, public timings only. Never save unit values or native geometry.
        HandHelperProbeDB.gaugeExperiment={version=2,costs=lab.costs,scope="Native SetMinMaxValues/SetValue submission; excludes deferred rendering",mirrorAvailable={}}
        local frame=CreateFrame("Frame",nil,S.hud);lab.frame=frame
        frame:SetSize(424,172);frame:SetPoint("BOTTOMLEFT",S.hud,"TOPLEFT",0,8);frame:SetFrameStrata("HIGH");frame:SetClampedToScreen(true)
        frame:SetMovable(true);frame:EnableMouse(true);frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart",function()frame:StartMoving()end);frame:SetScript("OnDragStop",function()frame:StopMovingOrSizing()end)
        local bg=frame:CreateTexture(nil,"BACKGROUND");bg:SetAllPoints();bg:SetColorTexture(0,0,0,1)
        local function patch(x,y,w,h,r,g,b)
            local p=frame:CreateTexture(nil,"OVERLAY");p:SetSize(w,h);p:SetPoint("TOPLEFT",x,-y);p:SetColorTexture(r,g,b,1);return p
        end
        for i,c in ipairs({{1,0,1},{0,1,1},{1,1,0},{1,1,1}}) do patch(4+(i-1)*6,2,4,4,unpack(c));patch(416-(i-1)*6,166,4,4,unpack(c)) end
        local title=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");title:SetPoint("TOPLEFT",34,0);title:SetText("GAUGE LAB / READ ONLY / DRAG")
        for _,entry in ipairs({{8,"REFERENCE"},{152,"THIN / DUAL RAIL"},{296,"M/F"},{338,"G"},{358,"V"}}) do
            local label=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");label:SetPoint("TOPLEFT",entry[1],-14);label:SetText(entry[2])
        end
        local function bar(parent,x,y,w,h,power,reverse,vertical)
            local b=CreateFrame("StatusBar",nil,parent);b:SetPoint("TOPLEFT",x,-y);b:SetSize(w,h);b:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
            b:SetStatusBarColor(0,power and .5 or 1,power and 1 or 0,1)
            if reverse then b:SetReverseFill(true) end;if vertical then b:SetOrientation("VERTICAL") end
            local back=b:CreateTexture(nil,"BACKGROUND");back:SetAllPoints();back:SetColorTexture(.18,.18,.18,1);return b
        end
        local ok,curve=pcall(function()local c=C_CurveUtil.CreateColorCurve();c:AddPoint(0,CreateColor(0,0,0,1));c:AddPoint(1,CreateColor(1,1,1,1));return c end)
        lab.curve=ok and curve or nil
        for i,spec in ipairs({{"player","health"},{"player","power"},{"target","health"},{"pet","health"}}) do
            local y=28+(i-1)*32;local power=spec[2]=="power"
            local row={unit=spec[1],kind=spec[2],bars={}}
            local label=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");label:SetPoint("TOPLEFT",8,-y);label:SetText(spec[1].." "..spec[2])
            row.reference=bar(frame,8,y+12,128,4,power);row.bars[#row.bars+1]=row.reference
            row.bars[#row.bars+1]=bar(frame,152,y+9,128,1,power)
            row.bars[#row.bars+1]=bar(frame,152,y+14,128,2,power)
            row.bars[#row.bars+1]=bar(frame,152,y+17,128,2,power,true)
            for fold=0,3 do
                local clip=CreateFrame("Frame",nil,frame);clip:SetPoint("TOPLEFT",296,-y-9-fold*2);clip:SetSize(32,2)
                local clipped=pcall(clip.SetClipsChildren,clip,true)
                local b=bar(clip,-fold*32,0,128,2,power);row.bars[#row.bars+1]=b
                if not clipped then clip:Hide();row.foldUnavailable=true end
            end
            -- The native fill texture supplies both anchors. Only constant
            -- translations are used: no restricted width/position is queried.
            row.mirrorClips={}
            local mirrored,mirrorError=pcall(function()
                local source=row.reference:GetStatusBarTexture();assert(source,"fill texture unavailable")
                for fold=0,3 do
                    local clip=CreateFrame("Frame",nil,frame);row.mirrorClips[#row.mirrorClips+1]=clip
                    clip:SetPoint("TOPLEFT",296,-y-fold*2);clip:SetSize(32,2);clip:SetClipsChildren(true)
                    local back=clip:CreateTexture(nil,"BACKGROUND");back:SetAllPoints();back:SetColorTexture(.18,.18,.18,1)
                    local fill=clip:CreateTexture(nil,"ARTWORK");fill:SetColorTexture(0,power and .5 or 1,power and 1 or 0,1);fill:SetHeight(2)
                    fill:SetPoint("TOPLEFT",source,"TOPLEFT",288-fold*32,12-fold*2)
                    fill:SetPoint("TOPRIGHT",source,"TOPRIGHT",288-fold*32,12-fold*2)
                end
            end)
            row.mirrorUnavailable=not mirrored
            if not mirrored then for _,clip in ipairs(row.mirrorClips) do clip:Hide() end;row.mirrorError=S.describe(mirrorError) end
            HandHelperProbeDB.gaugeExperiment.mirrorAvailable[i]=mirrored
            if i==1 then row.bars[#row.bars+1]=bar(frame,360,28,2,128,false,false,true) end
            row.gray=patch(336,y+9,8,8,1,.65,0);row.valid=patch(384,y+9,4,4,1,.65,0);row.grayValid=patch(392,y+9,4,4,1,.65,0);row.foldValid=patch(400,y+9,4,4,1,.65,0);row.mirrorValid=patch(408,y+9,4,4,1,.65,0)
            lab.rows[i]=row
        end
        local function clock()
            if type(debugprofilestop)~="function" then return nil end
            local v=debugprofilestop();if not S.isSecret(v) and type(v)=="number" then return v end
        end
        local function submit(row,first,last,maximum,value,name)
            local start=clock()
            for index=first,last do local b=row.bars[index];b:SetMinMaxValues(0,maximum);b:SetValue(value) end
            local finish=clock()
            if start and finish and finish>=start then
                local stat=lab.costs[name];local elapsed=finish-start
                stat.calls=stat.calls+1;stat.total=stat.total+elapsed;stat.maximum=math.max(stat.maximum,elapsed)
            end
        end
        function lab.render()
            for i,row in ipairs(lab.rows) do
                local exists=S.readableCall(UnitExists,row.unit)==true
                local ok,err=pcall(function()
                    assert(exists,"unit unavailable")
                    local maximum
                    if row.kind=="health" then maximum=UnitHealthMax(row.unit) else maximum=UnitPowerMax(row.unit) end
                    -- Never branch on or perform arithmetic with secret values.
                    if not S.isSecret(maximum) and (type(maximum)~="number" or maximum<=0) then error("maximum unavailable") end
                    local value
                    if row.kind=="health" then value=UnitHealth(row.unit) else value=UnitPower(row.unit) end
                    submit(row,1,1,maximum,value,"reference")
                    submit(row,5,8,maximum,value,"folded")
                    for index=2,4 do local b=row.bars[index];b:SetMinMaxValues(0,maximum);b:SetValue(value) end
                    if row.bars[9] then row.bars[9]:SetMinMaxValues(0,maximum);row.bars[9]:SetValue(value) end
                end)
                lab.errors[i]=not ok and S.describe(err) or nil;S.drawFlag(row.valid,ok and true or nil)
                S.drawFlag(row.foldValid,ok and not row.foldUnavailable and true or nil)
                S.drawFlag(row.mirrorValid,ok and not row.mirrorUnavailable and true or nil)
                if not ok then for _,b in ipairs(row.bars) do b:SetMinMaxValues(0,1);b:SetValue(0) end end
                local gray=pcall(function()
                    assert(exists and lab.curve,"percentage unavailable")
                    local color
                    if row.kind=="health" then color=UnitHealthPercent(row.unit,false,lab.curve) else color=UnitPowerPercent(row.unit,nil,false,lab.curve) end
                    row.gray:SetColorTexture(color:GetRGBA())
                end)
                if not gray then row.gray:SetColorTexture(1,.65,0,1) end;S.drawFlag(row.grayValid,gray and true or nil)
            end
        end
        local elapsed=0
        frame:SetScript("OnUpdate",function(_,dt)elapsed=elapsed+dt;if elapsed>=S.updateInterval() then elapsed=0;lab.render() end end)
    end
    lab.frame:Show();lab.render()
    print("Hand Helper gauge lab ON (read only). /hhgaugetest off hides it.")
end
