-- HUD updates, event dispatch, invalidation and /feuxton.
local _, ns = ...
local S = ns.state

function S.mirrorColor(dot, source, method)
    dot:SetColorTexture(1, 1, 1, 1)
    if not source or type(source[method]) ~= "function" then return false end
    -- Forward the native color straight to another native renderer. Do not
    -- inspect, branch on, stringify or serialize any of its channels.
    return pcall(function() dot:SetVertexColor(source[method](source)) end)
end
S.signalElapsed = 0
S.signalUpdater = CreateFrame("Frame", nil, S.hud)
S.signalUpdater:SetScript("OnUpdate", function(self, elapsed)
    S.signalElapsed = S.signalElapsed + elapsed
    if S.signalElapsed < S.updateInterval() then return end
    S.signalElapsed = 0
    for _, tile in ipairs(S.tiles) do
        local chosen=S.bindingsValid and S.preferredMapping(tile.mappings)
        local button = chosen and chosen.button
        local visible = button and S.readableCall(button.IsVisible, button) == true
        local slot = button and button.action
        if S.isSecret(slot) or slot ~= (chosen and chosen.slot) then visible = false end
        local rangeOK, usableOK = false, false
        if chosen and chosen.managed then
            rangeOK,usableOK=ns.features.RangeTracking.render(tile.visualSignals,chosen.id,chosen.unit)
        elseif visible then
            local hotkey = button.HotKey or _G[button:GetName() .. "HotKey"]
            local rangeMethod = hotkey and type(hotkey.GetVertexColor) == "function" and "GetVertexColor" or "GetTextColor"
            rangeOK = S.mirrorColor(tile.visualSignals[1], hotkey, rangeMethod)
            usableOK = S.mirrorColor(tile.visualSignals[3], button.icon or button.Icon, "GetVertexColor")
            if rangeOK then
                pcall(function() tile.binding:SetVertexColor(hotkey[rangeMethod](hotkey)) end)
            end
        end
        S.drawFlag(tile.visualSignals[2], rangeOK)
        S.drawFlag(tile.visualSignals[4], usableOK)
        if not rangeOK then tile.visualSignals[1]:SetColorTexture(1, 0.65, 0, 1); tile.binding:SetVertexColor(1,1,1,1) end
        if not usableOK then tile.visualSignals[3]:SetColorTexture(1, 0.65, 0, 1) end
    end
end)

function S.alignHud()
    local parentScale = S.readableCall(UIParent.GetEffectiveScale, UIParent)
    local parentHeight = S.readableCall(UIParent.GetHeight, UIParent)
    local ok, width, height = pcall(function() return GetPhysicalScreenSize() end)
    if ok and not S.isSecret(height) and type(height) == "number" and height > 0
        and type(parentHeight) == "number" and type(parentScale) == "number" then
        -- WoW's root UI coordinates are not physical screen pixels. Cancelling
        -- UIParent scale alone still leaves the root-to-screen scaling factor.
        S.hud:SetScale(parentHeight / height)
    end
end
S.handlers = {}
S.handlers.PLAYER_LOGIN = function()
    local saved=type(FeuxtonDB)=="table" and FeuxtonDB.updateRateMs or 100
    if not ns.setUpdateRate(saved) then ns.setUpdateRate(100) end
    S.alignHud(); S.resolveSpells(); S.discoverBindings(); S.refreshCooldowns(); S.refreshFlags()
end
S.handlers.SPELLS_CHANGED = function() S.resolveSpells(); S.discoverBindings(); S.refreshCooldowns() end
S.handlers.SPELL_DATA_LOAD_RESULT = S.handlers.SPELLS_CHANGED
S.handlers.SPELL_UPDATE_COOLDOWN = S.refreshCooldowns
S.handlers.SPELL_UPDATE_USABLE = S.refreshCooldowns
S.handlers.PLAYER_TARGET_CHANGED = S.refreshFlags
S.handlers.UNIT_FLAGS = S.refreshFlags
S.handlers.UNIT_PET = S.refreshFlags
S.handlers.PLAYER_REGEN_DISABLED = function() S.refreshFlags(); S.refreshCooldowns() end
S.handlers.PLAYER_REGEN_ENABLED = function() S.resolveSpells(); S.discoverBindings(); S.refreshFlags(); S.refreshCooldowns() end
function S.bindingsChanged()
    S.bindingsValid=false
    S.discoverBindings()
end
S.handlers.UPDATE_BINDINGS = S.bindingsChanged
S.handlers.UPDATE_SHAPESHIFT_FORMS = S.bindingsChanged
function S.invalidateMappings(kind,slot)
    local function invalidate(list)
        for _,tile in ipairs(list) do for _,mapping in ipairs(tile.mappings or {}) do
            if not mapping.managed and (not kind or mapping.kind==kind) and (not slot or slot==0 or mapping.slot==slot) then mapping.invalidated=true end
        end end
    end
    invalidate(S.tiles); invalidate(ns.playerBuffSpecs or {})
    S.discoverBindings()
end
S.handlers.UPDATE_MACROS = function() S.invalidateMappings("macro candidate") end
S.handlers.ACTIONBAR_SLOT_CHANGED = function(slot)
    if S.isSecret(slot) or type(slot)~="number" then S.bindingsChanged() else S.invalidateMappings(nil,slot) end
end
-- Each visible button's current action slot is checked before export. A page
-- change must not invalidate direct spell bindings on unrelated fixed bars.
S.handlers.ACTIONBAR_PAGE_CHANGED = S.discoverBindings
S.handlers.UI_SCALE_CHANGED = S.alignHud
S.handlers.DISPLAY_SIZE_CHANGED = S.alignHud
S.handlers.START_AUTOREPEAT_SPELL = function() S.autoActive = true; S.autoStateSource="autorepeat event"; S.refreshFlags() end
S.handlers.STOP_AUTOREPEAT_SPELL = function() S.autoActive = false; S.autoStateSource="autorepeat event"; S.refreshFlags() end
S.handlers.PLAYER_ENTER_COMBAT = function() S.meleeActive=true;S.refreshFlags() end
S.handlers.PLAYER_LEAVE_COMBAT = function() S.meleeActive=false;S.refreshFlags() end
S.eventErrors = {}
S.hudEvents = CreateFrame("Frame")
S.hudEvents:SetScript("OnEvent", function(self, event, ...)
    local fn = S.handlers[event]
    if fn then
        local ok, err = pcall(fn, ...)
        if not ok then S.eventErrors[event] = S.describe(err) end
    end
end)
for event in pairs(S.handlers) do
    local ok, err = pcall(S.hudEvents.RegisterEvent, S.hudEvents, event)
    if not ok then S.eventErrors[event] = "registration failed: " .. S.describe(err) end
end

ns.hudReport = function(add)
    add("Live update rate (ms)",S.updateRateMs)
    for _,probe in ipairs(S.meleeProbes) do
        add(probe.name.." range probe ID",probe.spellID)
        add(probe.name.." learned",S.describe(probe.known))
        add(probe.name.." target in range",S.describe(probe.range))
    end
    add("Hunter panel schema", "HUNTER 02 / 0.2.0 / 668x142 physical pixels")
    add("Panel effective scale", S.query(S.hud.GetEffectiveScale, S.hud))
    add("Auto repeat event state", S.describe(S.autoActive))
    add("Auto state source",S.autoStateSource)
    for index, spec in ipairs(S.hunterSpecs) do
        local tile = S.tiles[index]
        add("Panel " .. spec.short .. " learned", S.describe(tile.known))
        add("Panel " .. spec.short .. " spell", S.describe(tile.spellID) .. " / " .. S.describe(tile.spellName))
        add("Panel " .. spec.short .. " render", tile.renderStatus)
        for _, mapping in ipairs(tile.mappings or {}) do
            add("Panel " .. spec.short .. " binding", mapping.key .. " / " .. mapping.kind .. " / slot " .. mapping.slot)
        end
    end
    for event, err in pairs(S.eventErrors) do add("Panel event " .. event, err) end
    for index, value in ipairs(S.bindingDiagnostics) do add("Bar discovery " .. index, value) end
end
SLASH_FEUXTONPANEL1 = "/feuxton"
SlashCmdList.FEUXTONPANEL = function(message)
    local rate=message:match("^rate%s+(.+)$")
    if message=="dense" or message=="standard" then
        if not ns.setDenseBridge(message=="dense") then print("Feuxton: dense layout requires Paladin and being outside combat.") end
    elseif message=="compact" or message=="legacy" then
        if not ns.setCompactBridge(message=="compact") then print("Feuxton: change layout outside combat.") end
    elseif rate then
        if ns.setUpdateRate(rate) then print("Feuxton: live update rate "..S.updateRateMs.." ms.")
        else print("Feuxton: use /feuxton rate 50 to 1000 (milliseconds).") end
    elseif message=="rate" then print("Feuxton: live update rate "..S.updateRateMs.." ms. Use /feuxton settings to change it.")
    elseif message=="settings" then if ns.rateSettings then ns.rateSettings:Show() end
    elseif message == "hide" then S.hud:Hide()
    elseif message == "lock" then S.hud:StopMovingOrSizing(); S.hudDragHandle:EnableMouse(false)
    elseif message == "unlock" then S.hudDragHandle:EnableMouse(true)
    elseif message == "reset" then
        S.hud:StopMovingOrSizing(); S.hud:SetUserPlaced(false); S.hud:ClearAllPoints()
        S.hud:SetPoint("TOPLEFT",UIParent,"TOPLEFT",32,-280); S.hudDragHandle:EnableMouse(true)
    elseif message == "report" then
        S.edit:SetText(S.report()); S.panel:Show(); S.edit:SetFocus(); S.edit:HighlightText()
    else
        S.hud:Show(); S.alignHud(); S.resolveSpells(); S.discoverBindings(); S.refreshCooldowns(); S.refreshFlags()
    end
end

