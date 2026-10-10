-- In-game addon settings controls.
local _, ns = ...
local S = ns.state

-- Ordinary configuration widgets; they do not inspect combat state.
do
    local settings=CreateFrame("Frame",nil,UIParent)
    ns.rateSettings=settings
    settings:SetSize(360,370); settings:SetPoint("CENTER"); settings:SetFrameStrata("DIALOG")
    settings:EnableMouse(true); settings:SetMovable(true); settings:RegisterForDrag("LeftButton")
    settings:SetScript("OnDragStart",function(self) self:StartMoving() end)
    settings:SetScript("OnDragStop",function(self) self:StopMovingOrSizing() end)
    local background=settings:CreateTexture(nil,"BACKGROUND")
    background:SetAllPoints(); background:SetColorTexture(0.03,0.03,0.03,0.97)
    local title=settings:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    title:SetPoint("TOPLEFT",16,-16); title:SetText("Hand Helper settings")
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
    local layout=button("Compact bridge",16,294,function()
        if ns.setCompactBridge and ns.setCompactBridge(not S.compactBridge) then status:SetText("Layout saved. Reader detects either layout automatically.")
        else status:SetText("Change the layout outside combat.") end
    end,164)
    button("Toggle dense bridge",16,294,function()
        if ns.setDenseBridge and ns.setDenseBridge(not S.denseBridgeActive) then status:SetText("Layout saved. Standard/diagnostic remain available.")
        else status:SetText("Use a supported class outside combat.") end
    end,200)
    local blessings={}
    for i,key in ipairs({"paladin.blessingMight","paladin.blessingWisdom","paladin.retributionAura"}) do
        local label=i==1 and "Might" or i==2 and "Wisdom" or "Retribution"
        local b=button(label,16+((i-1)%2)*152,142,function(_,mouse)
            if mouse=="RightButton" then S.setSpellUse(key,nil) else S.setSpellUse(key,S.spellUseCode(key)==1) end
            ns.refreshRateSettings()
        end,240+math.floor((i-1)/2)*36)
        -- Right click restores app control; left click toggles addon ON/OFF.
        b:RegisterForClicks("LeftButtonUp","RightButtonUp")
        blessings[i]={button=b,key=key,label=label}
    end
    local hint=settings:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT",16,-320);hint:SetText("Spells: left click toggles; right click follows app.")
    ns.refreshRateSettings=function()
        input:SetText(tostring(S.updateRateMs)); layout.hhText:SetText(S.compactBridge and "Switch to diagnostic HUD" or "Switch to compact bridge")
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

