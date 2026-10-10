-- Target aura row and native target / target-of-target frames.
local _, ns = ...
local S = ns.state

-- Mirror only already-rendered target-frame aura textures. Never identify an
-- aura by comparing secret IDs; the desktop reader recognizes rendered pixels.
S.auraMirror = CreateFrame("Frame", nil, S.hud)
S.auraMirror:SetSize(668, 46)
S.auraMirror:SetPoint("TOPLEFT", S.hud, "BOTTOMLEFT", 0, -4)
S.auraBackground = S.auraMirror:CreateTexture(nil, "BACKGROUND")
S.auraBackground:SetAllPoints(); S.auraBackground:SetColorTexture(0, 0, 0, 1)
S.auraTitle = S.auraMirror:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
S.auraTitle:SetPoint("TOPLEFT", 12, -5)
S.auraTitle:SetText("TARGET DEBUFFS")
S.auraStatus = S.auraMirror:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
S.auraStatus:SetPoint("BOTTOMLEFT", 12, 6)
S.auraStatus:Hide()
S.auraSlots = {}
for index = 1, 24 do
    local slot = {}
    slot.icon = S.auraMirror:CreateTexture(nil, "ARTWORK")
    slot.icon:SetSize(24, 24)
    slot.icon:SetPoint("TOPLEFT", 12 + (index - 1) * 26, -20)
    slot.dot = S.auraMirror:CreateTexture(nil, "OVERLAY")
    slot.dot:SetSize(4, 4)
    slot.dot:SetPoint("TOPLEFT", 32 + (index - 1) * 26, -15)
    S.auraSlots[index] = slot
end
for index, color in ipairs({ {1,0.5,0}, {0,0.5,1}, {0.5,1,0} }) do
    local marker = S.auraMirror:CreateTexture(nil, "OVERLAY")
    marker:SetSize(4,4); marker:SetPoint("TOPRIGHT", -4 - (index - 1) * 6, -3)
    marker:SetColorTexture(color[1],color[2],color[3],1)
end
S.auraDiagnostic = "not refreshed"
S.auraGeneration = 0
S.unitHud = CreateFrame("Frame",nil,S.hud)
S.unitHud:SetSize(668,44)
S.unitHud:SetPoint("TOPLEFT",S.auraMirror,"BOTTOMLEFT",0,-4)
S.unitBackground=S.unitHud:CreateTexture(nil,"BACKGROUND")
S.unitBackground:SetAllPoints(); S.unitBackground:SetColorTexture(0,0,0,1)
S.unitDisplays={}
S.playerAlive=S.unitHud:CreateTexture(nil,"OVERLAY")
S.playerAlive:SetSize(6,6); S.playerAlive:SetPoint("TOPLEFT",318,-22)
S.aliveLabel=S.unitHud:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
S.aliveLabel:SetPoint("TOPLEFT",294,-7); S.aliveLabel:SetText("ALIVE")
for index,token in ipairs({"target","targettarget"}) do
    local display={token=token}
    local x=12+(index-1)*328
    display.name=S.unitHud:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    display.name:SetPoint("TOPLEFT",x,-7)
    display.name:SetWidth(250); display.name:SetJustifyH("LEFT")
    display.name:SetText(index==1 and "TARGET" or "TARGET OF TARGET")
    display.health=CreateFrame("StatusBar",nil,S.unitHud)
    display.health:SetSize(250,16); display.health:SetPoint("TOPLEFT",x,-20)
    display.health:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    display.health:SetStatusBarColor(0,1,0,1)
    local bg=display.health:CreateTexture(nil,"BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.18,0.18,0.18,1)
    display.combat=S.unitHud:CreateTexture(nil,"OVERLAY")
    display.combat:SetSize(6,6); display.combat:SetPoint("TOPLEFT",x+270,-22)
    display.available=S.unitHud:CreateTexture(nil,"OVERLAY")
    display.available:SetSize(6,6); display.available:SetPoint("TOPLEFT",x+254,-22)
    local label=S.unitHud:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    S.bridgeLabel(label)
    label:SetPoint("TOPLEFT",x+279,-20); label:SetText("C")
    display.status=S.unitHud:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    display.status:SetPoint("TOPLEFT",x,-43)
    display.status:Hide()
    S.unitDisplays[index]=display
end
-- Compare readable health directly; restricted health goes only to a native bar.
S.stingBudget=CreateFrame("StatusBar",nil,S.unitHud)
S.stingBudget:SetSize(250,4); S.stingBudget:SetPoint("TOPLEFT",12,-38)
S.stingBudget:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
S.stingBudget:SetStatusBarColor(0,1,0,1)
local budgetBackground=S.stingBudget:CreateTexture(nil,"BACKGROUND")
budgetBackground:SetAllPoints(); budgetBackground:SetColorTexture(0.18,0.18,0.18,1)
local function budgetDot(x)
    local dot=S.unitHud:CreateTexture(nil,"OVERLAY");dot:SetSize(4,4);dot:SetPoint("TOPLEFT",x,-38);return dot
end
S.stingBudgetReady=budgetDot(268)
S.stingBudgetMarkerA=budgetDot(276);S.stingBudgetMarkerA:SetColorTexture(1,0,1,1)
S.stingBudgetMarkerB=budgetDot(284);S.stingBudgetMarkerB:SetColorTexture(0,1,1,1)
S.stingBudgetDamage=budgetDot(292);S.stingBudgetID=budgetDot(300);S.stingBudgetDirect=budgetDot(308)
local function encodeBudget(dot,n)
    n=n or 0;dot:SetColorTexture(math.floor(n/65536)/255,math.floor(n/256)%256/255,n%256/255,1)
end
function S.parseStingDamage(description)
    if S.isSecret(description) or type(description)~="string" then return nil end
    description=description:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")
    if description:match("%d%s+to%s+%d") or description:find("%",1,true) then return nil end
    local total=description:match("(%d[%d,]*%.?%d*)%s+Nature damage over%s+[%d%.]+%s+sec")
    local damage=total and tonumber((total:gsub(",","")))
    if not damage or damage<=0 or damage>16777215 then return nil end
    return math.ceil(damage)
end
function S.refreshStingBudget()
    local tile=S.tiles and S.tiles[7]
    local id=S.boundSpellID(tile)
    local damage=type(id)=="number" and S.parseStingDamage(S.readableCall(S.spellAPI.GetSpellDescription or GetSpellDescription,id)) or nil
    local exists=S.readableCall(UnitExists,"target")
    local ready=false;local direct
    if damage and exists==true then
        local health=S.readableCall(UnitHealth,"target")
        if type(health)=="number" then direct=health>=damage end
        ready=pcall(function()
            -- One pixel of headroom makes visual eligibility conservative.
            S.stingBudget:SetMinMaxValues(0,damage+math.ceil(damage/250))
            S.stingBudget:SetValue(UnitHealth("target"))
        end)
    end
    if not ready then S.stingBudget:SetMinMaxValues(0,1);S.stingBudget:SetValue(0) end
    S.drawFlag(S.stingBudgetReady,ready and true or nil)
    S.drawFlag(S.stingBudgetDirect,direct)
    encodeBudget(S.stingBudgetDamage,damage);encodeBudget(S.stingBudgetID,type(id)=="number" and id or nil)
end
function S.refreshUnitDisplays()
    S.refreshStingBudget()
    local dead=S.readableCall(UnitIsDeadOrGhost,"player")
    if type(dead)=="boolean" then S.drawFlag(S.playerAlive,not dead) else S.drawFlag(S.playerAlive,nil) end
    for _,display in ipairs(S.unitDisplays) do
        local exists=S.readableCall(UnitExists,display.token)
        if exists~=true then
            display.name:SetText(display.token=="target" and "TARGET: --" or "TARGET OF TARGET: --")
            display.health:SetMinMaxValues(0,1); display.health:SetValue(0)
            display.status:SetText(exists==false and "No unit" or "Unit unavailable")
            S.drawFlag(display.combat,nil)
            if exists==false then S.drawFlag(display.available,false) else S.drawFlag(display.available,nil) end
        else
            local rendered,err=pcall(function()
                display.name:SetText(UnitName(display.token))
                display.health:SetMinMaxValues(0,UnitHealthMax(display.token))
                display.health:SetValue(UnitHealth(display.token))
            end)
            display.status:SetText(rendered and (display.token=="target" and "Target health" or "Target-of-target health") or "Health unavailable")
            display.error=not rendered and S.describe(err) or nil
            S.drawFlag(display.available,rendered and true or nil)
            if not rendered then display.health:SetMinMaxValues(0,1); display.health:SetValue(0) end
            S.drawFlag(display.combat,S.readableCall(UnitAffectingCombat,display.token))
        end
    end
end
-- Shared observations must keep updating when a class hides Hunter's aura mirror.
S.unitElapsed = 0
S.unitHud:SetScript("OnUpdate",function(self,elapsed)
    S.unitElapsed=S.unitElapsed+elapsed
    if S.unitElapsed<S.updateInterval() then return end
    S.unitElapsed=0
    pcall(S.refreshFlags)
    pcall(S.refreshUnitDisplays)
end)
S.auraGenerationPixel = S.auraMirror:CreateTexture(nil,"OVERLAY")
S.auraGenerationPixel:SetSize(4,4); S.auraGenerationPixel:SetPoint("TOPRIGHT",-4,-9)
function S.clearAuraMirror()
    for _, slot in ipairs(S.auraSlots) do
        slot.icon:SetTexture(nil); S.drawFlag(slot.dot,nil)
    end
end
