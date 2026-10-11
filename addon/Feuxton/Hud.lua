-- Movable HUD, schema markers, target flags and melee probes.
local _, ns = ...
local S = ns.state

-- Shared packet/gauge sections plus one active-class widget section.
-- Geometry changes here are mirrored by the desktop atlas. A class contributes
-- native widgets; framing, setup, RGB transport and roster rows stay shared.
ns.bridgeLayouts,ns.denseBridgeLayouts={},{}
for class,module in pairs(ns.classes) do
    if module.bridgeLayout then ns.bridgeLayouts[class]=module.bridgeLayout end
    if module.denseBridgeLayout then ns.denseBridgeLayouts[class]=module.denseBridgeLayout end
end

S.hud = CreateFrame("Frame", "FeuxtonHud", UIParent)
ns.hud = S.hud
-- Keep the wire above fullscreen low-health flashes. Their tint corrupts RGB
-- cells and native gauges precisely when survival observations matter most.
S.hud:SetFrameStrata("TOOLTIP")
S.hud:SetSize(668, 114)
S.hud:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 32, -280)
S.hud:SetMovable(true)
S.hud:SetClampedToScreen(true)
-- Include the compact aura and unit rows in the screen clamp.
S.hud:SetClampRectInsets(0,0,0,-114)
S.hudDragHandle=CreateFrame("Frame",nil,S.hud)
S.hudDragHandle:SetPoint("TOPLEFT",24,0)
S.hudDragHandle:SetSize(610,25)
S.hudDragHandle:EnableMouse(true)
S.hudDragHandle:RegisterForDrag("LeftButton")
S.hudDragHandle:SetScript("OnMouseDown",function() S.hudDragMoved=false end)
S.hudDragHandle:SetScript("OnMouseUp",function(self,button)
    if button=="LeftButton" and not S.hudDragMoved and ns.rateSettings then ns.rateSettings:Show() end
end)
S.hudDragHandle:SetScript("OnDragStart",function() S.hudDragMoved=true;S.hud:StartMoving() end)
S.hudDragHandle:SetScript("OnDragStop",function()
    S.hud:StopMovingOrSizing(); S.hud:SetUserPlaced(true)
end)
S.hudBackground = S.hud:CreateTexture(nil, "BACKGROUND")
S.hudBackground:SetAllPoints()
S.hudBackground:SetColorTexture(0, 0, 0, 1)
-- Fixed schema markers validate both corners before desktop interpretation.
for index, color in ipairs({ {1,0,1}, {0,1,1}, {1,1,0} }) do
    for _, corner in ipairs({ "TOPLEFT", "BOTTOMRIGHT" }) do
        local marker = S.hud:CreateTexture(nil, "OVERLAY")
        marker:SetSize(4, 4)
        if corner == "TOPLEFT" then marker:SetPoint(corner, 4 + (index - 1) * 6, -3)
        else marker:SetPoint(corner, -4 - (index - 1) * 6, 3) end
        marker:SetColorTexture(color[1], color[2], color[3], 1)
    end
end
S.hudTitle = S.hud:CreateFontString(nil, "OVERLAY", "GameFontNormal")
S.hudTitle:SetPoint("TOPLEFT", 12, -8)
S.hudTitle:SetWidth(290)
S.hudTitle:SetText("FEUXTON v"..ns.version.." | OPTIONS / DRAG")
S.hudFooter = S.hud:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
S.hudFooter:Hide()
S.hudFooter:SetPoint("BOTTOMLEFT", 12, 8)
S.hudFooter:SetText("White dial + black swipe: native cooldown display. Binding labels do not change your bars.")

S.heartbeat = S.hud:CreateTexture(nil, "OVERLAY")
S.heartbeat:SetSize(8, 8)
S.heartbeat:SetPoint("TOPRIGHT", -10, -8)
S.phase, S.elapsedTotal = 0, 0
S.hud:SetScript("OnUpdate", function(self, elapsed)
    S.elapsedTotal = S.elapsedTotal + elapsed
    if S.elapsedTotal < 0.25 then return end
    S.elapsedTotal = 0
    S.phase = 1 - S.phase
    S.heartbeat:SetColorTexture(S.phase, 1 - S.phase, 1, 1)
end)

S.targetFlags = {}
for index, name in ipairs({ "TARGET", "DEAD", "SELF", "ENEMY", "PET", "AUTO" }) do
    local dot = S.hud:CreateTexture(nil, "OVERLAY")
    dot:SetSize(8, 8)
    dot:SetPoint("TOPLEFT", 12 + (index - 1) * 82, -30)
    local label = S.hud:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    S.bridgeLabel(label)
    label:SetPoint("LEFT", dot, "RIGHT", 4, 0)
    label:SetText(name)
    S.targetFlags[index] = dot
end
S.autoActive = nil
S.autoStateSource = "not refreshed"
function S.drawFlag(dot, value)
    if S.isSecret(value) or type(value) ~= "boolean" then
        dot:SetColorTexture(1, 0.65, 0, 1)
    elseif value then
        dot:SetColorTexture(0, 1, 0, 1)
    else
        dot:SetColorTexture(0.2, 0.2, 0.2, 1)
    end
end
-- Range probes do not cast spells or depend on cooldown/resource usability.
-- Their own markers let older readers safely ignore this optional extension.
S.meleeProbes = {
    {name="Wing Clip",short="WING",base=2974},
    {name="Disengage",short="DIS",base=781},
}
for index,probe in ipairs(S.meleeProbes) do
    probe.dot=S.hud:CreateTexture(nil,"OVERLAY")
    probe.dot:SetSize(8,8); probe.dot:SetPoint("TOPLEFT",504+(index-1)*82,-30)
    S.drawFlag(probe.dot,nil)
    local label=S.hud:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    S.bridgeLabel(label)
    label:SetPoint("LEFT",probe.dot,"RIGHT",4,0); label:SetText(probe.short)
end
S.meleeMarkers={}
for index,color in ipairs({{0,1,1},{1,0,1}}) do
    local marker=S.hud:CreateTexture(nil,"OVERLAY")
    marker:SetSize(4,4); marker:SetPoint("TOPLEFT",640+(index-1)*10,-30)
    marker:SetColorTexture(color[1],color[2],color[3],1)
    S.meleeMarkers[index]=marker
end
function S.refreshMeleeRanges()
    local hostile=S.readableCall(UnitExists,"target")==true
        and S.readableCall(UnitIsDeadOrGhost,"target")==false
        and S.readableCall(UnitIsUnit,"target","player")==false
        and S.readableCall(UnitCanAttack,"player","target")==true
    for _,probe in ipairs(S.meleeProbes) do
        local value
        if hostile and probe.known==true and type(probe.spellID)=="number" then
            if type(S.spellAPI.IsSpellInRange)=="function" then
                value=S.readableCall(S.spellAPI.IsSpellInRange,probe.spellID,"target")
            else value=S.readableCall(IsSpellInRange,probe.name,"target") end
            if type(value)=="number" then
                if value==1 then value=true elseif value==0 then value=false else value=nil end
            end
        end
        probe.range=value
        S.drawFlag(probe.dot,value)
    end
end
function S.refreshFlags()
    -- IsAutoRepeatSpell describes the spell's type, not whether it is enabled.
    -- Read the current/queued Auto Shot state; fall back to explicit events.
    local current = S.readableCall(S.spellAPI.IsCurrentSpell, 75)
    if S.autoStateSource=="autorepeat event" then
        -- Explicit start/stop events remain authoritative once received.
    elseif type(current)=="boolean" then S.autoActive=current; S.autoStateSource="C_Spell.IsCurrentSpell(75)"
    elseif S.autoStateSource=="C_Spell.IsCurrentSpell(75)" then S.autoActive=nil; S.autoStateSource="current state unavailable" end
    S.drawFlag(S.targetFlags[1], S.readableCall(UnitExists, "target"))
    S.drawFlag(S.targetFlags[2], S.readableCall(UnitIsDeadOrGhost, "target"))
    S.drawFlag(S.targetFlags[3], S.readableCall(UnitIsUnit, "target", "player"))
    S.drawFlag(S.targetFlags[4], S.readableCall(UnitCanAttack, "player", "target"))
    S.drawFlag(S.targetFlags[5], S.readableCall(UnitExists, "pet"))
    S.targetFlags[6]:SetVertexColor(1,1,1,1)
    S.drawFlag(S.targetFlags[6], S.autoActive)
    local meleeClass=S.readableCall(function() local _,class=UnitClass("player");return class end)
    if meleeClass=="PALADIN" or meleeClass=="SHAMAN" then
        local ok,value=pcall(S.spellAPI.IsCurrentSpell or IsCurrentSpell,6603)
        if ok and not S.isSecret(value) and type(value)=="boolean" then S.drawFlag(S.targetFlags[6],value)
        elseif ok and S.isSecret(value) then
            S.targetFlags[6]:SetColorTexture(1,1,1,1)
            local rendered=pcall(function() local c=C_CurveUtil.EvaluateColorFromBoolean(value,CreateColor(0,1,0,1),CreateColor(.2,.2,.2,1));S.targetFlags[6]:SetVertexColor(c:GetRGBA()) end)
            if not rendered then S.targetFlags[6]:SetVertexColor(1,1,1,1);S.drawFlag(S.targetFlags[6],S.meleeActive) end
        else S.drawFlag(S.targetFlags[6],S.meleeActive) end
    end
    if S.denseTargetStamp then local c=S.auraGeneration/255;S.denseTargetStamp:SetColorTexture(c,c,c,1) end
    S.refreshMeleeRanges()
end

