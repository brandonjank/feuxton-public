-- In-game addon settings controls.
local _, ns = ...
local S = ns.state

-- This changes ordinary layout configuration only, outside combat. Native
-- widgets keep their qualified physical sizes; Paladin keeps its heal clock.
ns.extendedHudDiagnostics=function()
    if S.isSecret(FeuxtonDB) or type(FeuxtonDB)~="table" then return false end
    local value=FeuxtonDB.extendedHudDiagnostics
    return not S.isSecret(value) and value==true
end
ns.setExtendedHudDiagnostics=function(enabled)
    if type(enabled)~="boolean" or S.readableCall(InCombatLockdown)~=false then return false end
    if S.isSecret(FeuxtonDB) then return false end
    if type(FeuxtonDB)~="table" then FeuxtonDB={} end
    local previous=FeuxtonDB.extendedHudDiagnostics
    FeuxtonDB.extendedHudDiagnostics=enabled
    local ok,applied=false,false
    if type(ns.applyCurrentBridge)=="function" then ok,applied=pcall(ns.applyCurrentBridge) end
    if not ok or not applied then
        FeuxtonDB.extendedHudDiagnostics=previous;return false
    end
    return true
end

-- Ordinary configuration widgets; they do not inspect combat state.
do
    local settings=CreateFrame("Frame",nil,UIParent)
    ns.rateSettings=settings
    settings:SetSize(360,340); settings:SetPoint("CENTER"); settings:SetFrameStrata("DIALOG")
    settings:EnableMouse(true); settings:SetMovable(true); settings:RegisterForDrag("LeftButton")
    settings:SetScript("OnDragStart",function(self) self:StartMoving() end)
    settings:SetScript("OnDragStop",function(self) self:StopMovingOrSizing() end)
    local background=settings:CreateTexture(nil,"BACKGROUND")
    background:SetAllPoints(); background:SetColorTexture(0.03,0.03,0.03,0.97)
    local title=settings:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    title:SetPoint("TOPLEFT",16,-16); title:SetText("Feuxton settings")
    local label=settings:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    label:SetPoint("TOPLEFT",16,-52); label:SetText("Live update rate (50–1000 ms)")
    local input=CreateFrame("EditBox",nil,settings)
    input:SetSize(90,30); input:SetPoint("TOPLEFT",16,-76); input:SetFontObject("GameFontHighlight")
    input:SetAutoFocus(false); input:SetNumeric(true); input:SetMaxLetters(4)
    input:SetTextInsets(8,8,0,0)
    local inputBackground=input:CreateTexture(nil,"BACKGROUND")
    inputBackground:SetAllPoints(); inputBackground:SetColorTexture(0.16,0.16,0.16,1)
    local status=settings:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    status:SetPoint("TOPLEFT",16,-124); status:SetWidth(320); status:SetJustifyH("LEFT")
    local function button(text,x,width,action,y)
        local b=CreateFrame("Button",nil,settings)
        b:SetSize(width,30); b:SetPoint("TOPLEFT",x,-(y or 76))
        local bg=b:CreateTexture(nil,"BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.1,0.2,0.3,1)
        local font=b:CreateFontString(nil,"OVERLAY","GameFontHighlight"); font:SetAllPoints(); font:SetText(text)
        b.hhText=font; b:SetScript("OnClick",action)
        return b
    end
    local function apply()
        if ns.setUpdateRate(input:GetText()) then
            status:SetText("Applied immediately. Reader follows this rate."); input:ClearFocus()
        else status:SetText("Enter a number between 50 and 1000.") end
    end
    button("Apply",118,90,apply)
    button("Close",220,90,function() settings:Hide() end)
    input:SetScript("OnEnterPressed",apply)
    input:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    local extended=CreateFrame("CheckButton",nil,settings,"UICheckButtonTemplate")
    extended:SetSize(24,24);extended:SetPoint("TOPLEFT",16,-154)
    local extendedLabel=settings:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    extendedLabel:SetPoint("TOPLEFT",44,-160);extendedLabel:SetWidth(294);extendedLabel:SetJustifyH("LEFT")
    extendedLabel:SetText("Extended HUD diagnostics (larger HUD)")
    extended:SetScript("OnClick",function(self)
        if ns.setExtendedHudDiagnostics(self:GetChecked()==true) then
            status:SetText("Layout updated. Paladin's essential heal timer stays enabled.")
        else status:SetText("Change HUD diagnostics outside combat.") end
        self:SetChecked(ns.extendedHudDiagnostics())
    end)
    local blessings={}
    for i,key in ipairs({"paladin.blessingMight","paladin.blessingWisdom","paladin.blessingKings","paladin.retributionAura"}) do
        local label=i==1 and "Might" or i==2 and "Wisdom" or i==3 and "Kings" or "Retribution"
        local b=button(label,16+((i-1)%2)*152,142,function(_,mouse)
            if mouse=="RightButton" then S.setSpellUse(key,nil) else S.setSpellUse(key,S.spellUseCode(key)==1) end
            ns.refreshRateSettings()
        end,190+math.floor((i-1)/2)*36)
        -- Right click restores app control; left click toggles addon ON/OFF.
        b:RegisterForClicks("LeftButtonUp","RightButtonUp")
        blessings[i]={button=b,key=key,label=label}
    end
    local hint=settings:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    local itemButton=button("Healthstone",16,294,function(_,mouse)
        if mouse=="RightButton" then S.setSpellUse("shared.healthstone",nil) else S.setSpellUse("shared.healthstone",S.spellUseCode("shared.healthstone")==1) end
        ns.refreshRateSettings()
    end,266)
    itemButton:RegisterForClicks("LeftButtonUp","RightButtonUp")
    hint:SetPoint("TOPLEFT",16,-304);hint:SetText("Spells/items: left click toggles; right click follows app.")
    ns.refreshRateSettings=function()
        local itemCode=S.spellUseCode("shared.healthstone")
        itemButton.hhText:SetText("Healthstone: "..(itemCode==1 and "OFF" or itemCode==2 and "ON" or "Follow app"))
        input:SetText(tostring(S.updateRateMs))
        extended:SetChecked(ns.extendedHudDiagnostics())
        local paladin=S.readableCall(function() local _,class=UnitClass("player");return class end)=="PALADIN"
        for _,entry in ipairs(blessings) do
            if paladin then entry.button:Show() else entry.button:Hide() end
            local code=S.spellUseCode(entry.key)
            entry.button.hhText:SetText(entry.label..": "..(code==1 and "OFF" or code==2 and "ON" or "Follow app"))
        end
    end
    settings:SetScript("OnShow",function() ns.refreshRateSettings(); status:SetText("Default: 100 ms. Lower rates use more CPU.") end)
    settings:Hide()
end

