-- Spell widgets, spell resolution and native cooldown rendering.
local _, ns = ...
local S = ns.state

S.tiles, S.requested = {}, {}
S.bindingsValid = false
for index, spec in ipairs(S.hunterSpecs) do
    local tile = CreateFrame("Frame", nil, S.hud)
    tile:SetSize(58, 66)
    tile:SetPoint("TOPLEFT", 12 + (index<=10 and index-1 or index-11) * 65, index<=10 and -49 or -420)
    tile.icon = tile:CreateTexture(nil, "ARTWORK")
    tile.icon:SetSize(32, 32)
    tile.icon:SetPoint("TOPLEFT", 0, 0)
    tile.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    tile.dial = tile:CreateTexture(nil, "BACKGROUND")
    tile.dial:SetSize(22, 22)
    tile.dial:SetPoint("TOPRIGHT", 0, -5)
    tile.dial:SetColorTexture(0.35, 0.35, 0.35, 1)
    tile.cooldown = CreateFrame("Cooldown", nil, tile, "CooldownFrameTemplate")
    tile.cooldown:SetAllPoints(tile.dial)
    tile.cooldown:SetDrawEdge(false)
    tile.cooldown:SetDrawSwipe(true)
    tile.cooldown:SetSwipeColor(0, 0, 0, 1)
    tile.cooldown:SetHideCountdownNumbers(true)
    tile.learnedDot = tile:CreateTexture(nil, "OVERLAY")
    tile.learnedDot:SetSize(5, 5)
    tile.learnedDot:SetPoint("TOPRIGHT", -1, -1)
    tile.label = tile:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tile.label:SetPoint("TOPLEFT", 0, -36)
    tile.label:SetText(spec.short)
    tile.binding = tile:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tile.binding:SetPoint("TOPLEFT", 0, -50)
    tile.binding:SetText("--")
    tile.binding:SetWidth(28)
    tile.binding:SetJustifyH("LEFT")
    -- R/color, R/source, U/color, U/source. Colors are rendered directly;
    -- Lua does not compare or decode protected action-button values.
    tile.visualSignals = {}
    for signal = 1, 4 do
        local dot = tile:CreateTexture(nil, "OVERLAY")
        dot:SetSize(5, 5)
        dot:SetPoint("TOPLEFT", 30 + (signal - 1) * 7, -50)
        dot:SetColorTexture(1, 0.65, 0, 1)
        tile.visualSignals[signal] = dot
    end
    tile.renderStatus = "not queried"
    tile:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_NONE")
        GameTooltip:SetText(spec.name)
        GameTooltip:AddLine("Learned: " .. S.describe(self.known))
        GameTooltip:AddLine("Cooldown: " .. self.renderStatus)
        GameTooltip:AddLine("Small dots mirror bar range-key and usability-icon colors.", 1, 1, 1)
        for _, mapping in ipairs(self.mappings or {}) do
            GameTooltip:AddLine(mapping.key .. " | " .. mapping.kind .. " | slot " .. mapping.slot, 1, 1, 1)
        end
        GameTooltip:Show()
        -- Keep hover details outside the entire HUD, including the setup strip.
        -- Prefer above; when the HUD is near the top, use the space below it.
        local top = S.hud:GetTop() * S.hud:GetEffectiveScale()
        local screenTop = UIParent:GetHeight() * UIParent:GetEffectiveScale()
        local tooltipHeight = GameTooltip:GetHeight() * GameTooltip:GetEffectiveScale()
        GameTooltip:ClearAllPoints()
        if screenTop - top >= tooltipHeight + 8 then
            GameTooltip:SetPoint("BOTTOMLEFT", S.hud, "TOPLEFT", 0, 8)
        else
            GameTooltip:SetPoint("TOPLEFT", S.hud, "TOPLEFT", 0, -(S.compactBridge and 356 or 512))
        end
    end)
    tile:SetScript("OnLeave", function() GameTooltip:Hide() end)
    tile:EnableMouse(true)
    S.attachSpellUse(tile,tile.icon,spec.key)
    if index==21 then
        tile:SetFrameLevel(20)
        tile:ClearAllPoints();tile:SetPoint("TOPLEFT",276,-356)
        tile.label:Hide();tile.binding:Hide()
    end
    S.tiles[index] = tile
end

function S.resolveSpells()
    S.refreshSpellUse()
    for index, spec in ipairs(S.hunterSpecs) do
        local tile = S.tiles[index]
        local info = S.readableCall(S.spellAPI.GetSpellInfo, spec.name)
        if type(info) ~= "table" then info = S.readableCall(S.spellAPI.GetSpellInfo, spec.base) end
        tile.spellID = S.safeField(info, "spellID")
        tile.spellName = S.safeField(info, "name")
        local icon = S.safeField(info, "iconID")
        if icon then tile.icon:SetTexture(icon) end
        tile.known = nil
        if type(tile.spellID) == "number" then
            tile.known = S.readableCall(S.bookAPI.IsSpellKnown, tile.spellID)
            if type(tile.known) ~= "boolean" then tile.known = S.readableCall(IsSpellKnown, tile.spellID) end
        elseif spec.base>0 and not S.requested[spec.base] and type(S.spellAPI.RequestLoadSpellData) == "function" then
            S.requested[spec.base] = true
            pcall(S.spellAPI.RequestLoadSpellData, spec.base)
        end
        S.drawFlag(tile.learnedDot, tile.known)
        tile.icon:SetDesaturated(tile.known == false)
    end
    for _,probe in ipairs(S.meleeProbes) do
        local info=S.readableCall(S.spellAPI.GetSpellInfo,probe.name)
        if type(info)~="table" then info=S.readableCall(S.spellAPI.GetSpellInfo,probe.base) end
        probe.spellID=S.safeField(info,"spellID")
        probe.known=nil
        if type(probe.spellID)=="number" then
            probe.known=S.readableCall(S.bookAPI.IsSpellKnown,probe.spellID)
            if type(probe.known)~="boolean" then probe.known=S.readableCall(IsSpellKnown,probe.spellID) end
        elseif not S.requested[probe.base] and type(S.spellAPI.RequestLoadSpellData)=="function" then
            S.requested[probe.base]=true; pcall(S.spellAPI.RequestLoadSpellData,probe.base)
        end
    end
    S.refreshMeleeRanges()
end

function S.renderCooldown(tile)
    tile.dial:SetColorTexture(0.35, 0.35, 0.35, 1)
    if type(tile.spellID) ~= "number" or tile.known == false then
        tile.cooldown:Clear()
        tile.renderStatus = tile.known == false and "not learned" or "spell data unavailable"
        return
    end
    if type(S.spellAPI.GetSpellCooldownDuration) == "function" and type(tile.cooldown.SetCooldownFromDurationObject) == "function" then
        -- Only explicitly off-GCD abilities exclude it. Their actual cooldown
        -- remains native, including when its duration is restricted.
        local ignoreGCD=tile.offGlobalCooldown==true
        local ok, duration = pcall(S.spellAPI.GetSpellCooldownDuration, tile.spellID, ignoreGCD)
        if ok and not S.isSecret(duration) and duration ~= nil then
            local rendered, err = pcall(tile.cooldown.SetCooldownFromDurationObject, tile.cooldown, duration)
            if rendered then
                tile.dial:SetColorTexture(1, 1, 1, 1)
                tile.renderStatus = ignoreGCD and "native ability cooldown (off GCD)" or "duration object passed to native widget (includes GCD)"
                return
            end
            tile.renderStatus = "duration render failed: " .. S.describe(err)
        elseif not ok then
            tile.renderStatus = "duration query failed: " .. S.describe(duration)
        else
            tile.renderStatus = "duration unavailable"
        end
    else
        tile.renderStatus = "duration API missing"
    end
    -- Some builds offer only numeric timing. Pass it directly to the widget;
    -- do not inspect, compare, or do arithmetic with secret timing fields.
    if type(S.spellAPI.GetSpellCooldown) == "function" then
        local ok, data = pcall(S.spellAPI.GetSpellCooldown, tile.spellID)
        if ok and not S.isSecret(data) and type(data) == "table" then
            local rendered, err = pcall(function()
                tile.cooldown:SetCooldown(data.startTime, data.duration)
            end)
            if rendered then
                tile.dial:SetColorTexture(1, 1, 1, 1)
                tile.renderStatus = "numeric timing passed to native widget (includes GCD)"
                return
            end
            tile.renderStatus = tile.renderStatus .. "; numeric render failed: " .. S.describe(err)
        end
    end
    tile.cooldown:Clear()
end
function S.refreshCooldowns()
    for _, tile in ipairs(S.tiles) do S.renderCooldown(tile) end
end

