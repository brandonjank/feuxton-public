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
        -- This row is a data link; captions belong in the app and options.
        for _,label in ipairs(labels) do label:Hide() end
        if enabled then S.unitBackground:Hide();S.resourceBackground:Hide() else S.unitBackground:Show();S.resourceBackground:Show() end
        for _,display in ipairs(S.unitDisplays) do
            display.health:SetSize(enabled and 128 or 250,enabled and 4 or 16)
            display.health:SetStatusBarTexture(enabled and "Interface\\Buttons\\WHITE8X8" or "Interface\\TargetingFrame\\UI-StatusBar")
        end
        for _,display in ipairs(S.resourceDisplays) do display.bar:SetSize(enabled and 128 or 250,enabled and 4 or 10) end
        if not enabled then
            for i,dot in ipairs(ns.features.Interrupts.stamp or {}) do dot:ClearAllPoints();dot:SetPoint("TOPLEFT",S.resourcePanel,"TOPLEFT",628+(i-1)*6,-4) end
            return
        end
        local top=profile.gauges
        if ns.features.Interrupts.dot then point(ns.features.Interrupts.dot,152,top+4) end
        for i,dot in ipairs(ns.features.Interrupts.stamp or {}) do point(dot,316+(i-1)*6,top+12) end
        for i,display in ipairs(S.resourceDisplays) do
            local x=i<=2 and 12 or 176;local y=top+4+((i-1)%2)*8
            point(display.bar,x,y);point(display.dot,x+132,y)
        end
        for i,display in ipairs(S.unitDisplays) do
            local x=340+(i-1)*164
            point(display.health,x,top+4);point(display.available,x+132,top+4);point(display.combat,x+142,top+4)
            display.name:Hide()
        end
        -- Separate from target-of-target combat after removing the caption row.
        point(S.playerAlive,656,top)
        -- Keep the absolute Sting budget at its proven 250-pixel precision.
        point(S.stingBudget,340,top+12)
        for i,dot in ipairs({S.stingBudgetReady,S.stingBudgetMarkerA,S.stingBudgetMarkerB,S.stingBudgetDamage,S.stingBudgetID,S.stingBudgetDirect}) do point(dot,596+(i-1)*8,top+12) end
        if profile.guideStamp then
            point(S.tiles[21],126,114)
            for i,dot in ipairs(S.tiles[21].visualSignals) do dot:ClearAllPoints();dot:SetPoint("TOPLEFT",S.tiles[21],"TOPLEFT",30+(i-1)*7,-34) end
        end
    end
end



ns.features.Interrupts.initialize()
ns.features.GroupContext.initialize()
for _,class in pairs(ns.classes) do
    if type(class.initializePreview)=="function" then class.initializePreview() end
end
ns.initializeDenseBridge()

