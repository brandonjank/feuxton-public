-- HUD updates, event dispatch, invalidation and /feuxton.
local _, ns = ...
local S = ns.state

function S.mirrorColor(dot, source, method,whiteBase)
    if not whiteBase then dot:SetColorTexture(1, 1, 1, 1) end
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
    if S.setupString(S.setupValue(UnitClass,2,"player"))~="HUNTER" then return end
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
            rangeOK = S.mirrorColor(tile.visualSignals[1], hotkey, rangeMethod,true)
            usableOK = S.mirrorColor(tile.visualSignals[3], button.icon or button.Icon, "GetVertexColor",true)
            if rangeOK then
                pcall(function() tile.binding:SetVertexColor(hotkey[rangeMethod](hotkey)) end)
            end
        end
        local R=ns.features.RangeTracking
        R.paintFlag(tile.visualSignals[2], rangeOK)
        R.paintFlag(tile.visualSignals[4], usableOK)
        if not rangeOK then R.paintColor(tile.visualSignals[1],1,.65,0,1); tile.binding:SetVertexColor(1,1,1,1) end
        if not usableOK then R.paintColor(tile.visualSignals[3],1,.65,0,1) end
    end
end)

local function positiveGeometry(value)
    return type(value)=="number" and value==value and value>0 and value<math.huge
end
local function finiteGeometry(value)
    return type(value)=="number" and value==value and math.abs(value)<math.huge
end
local function hudPhysicalOrigin()
    local parentScale=S.readableCall(UIParent.GetEffectiveScale,UIParent)
    local parentHeight=S.readableCall(UIParent.GetHeight,UIParent)
    local hudScale=S.readableCall(S.hud.GetEffectiveScale,S.hud)
    local physicalHeight=S.readableCall(function() local _,height=GetPhysicalScreenSize();return height end)
    local left=S.readableCall(S.hud.GetLeft,S.hud)
    local top=S.readableCall(S.hud.GetTop,S.hud)
    if not positiveGeometry(parentScale) or not positiveGeometry(parentHeight)
        or not positiveGeometry(hudScale) or not positiveGeometry(physicalHeight)
        or not finiteGeometry(left) or not finiteGeometry(top) then return end
    local pixelsPerUnit=hudScale/parentScale*physicalHeight/parentHeight
    if not positiveGeometry(pixelsPerUnit) then return end
    return left*pixelsPerUnit,top*pixelsPerUnit,pixelsPerUnit
end
-- A restored movable anchor is interpreted at the calibrated HUD scale and
-- final class size. The temporary 114px startup frame is not its placement.
S.hudInitialLayoutPending=true
S.hudInitialLayoutApplied=false
function S.snapHudToPixels(physicalLeft,physicalTop)
    -- Saved movable frames may use LEFT/CENTER anchors. An odd-height layout
    -- then shifts their top edge by half a pixel, distorting the whole raster.
    -- Keep the current physical origin, rounded by at most half a pixel, and
    -- anchor the TOPLEFT to the screen origin before any later size changes.
    if S.readableCall(InCombatLockdown)~=false then S.hudPixelSnapPending=true;return false end
    local left,top,pixelsPerUnit=hudPhysicalOrigin()
    if not pixelsPerUnit then S.hudPixelSnapPending=true;return false end
    if S.isSecret(physicalLeft) or S.isSecret(physicalTop) then S.hudPixelSnapPending=true;return false end
    if physicalLeft==nil and physicalTop==nil then physicalLeft,physicalTop=left,top end
    if not finiteGeometry(physicalLeft) or not finiteGeometry(physicalTop) then
        S.hudPixelSnapPending=true;return false
    end
    local ok=pcall(function()
        S.hud:ClearAllPoints()
        S.hud:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",
            math.floor(physicalLeft+.5)/pixelsPerUnit,math.floor(physicalTop+.5)/pixelsPerUnit)
    end)
    S.hudPixelSnapPending=not ok
    return ok
end
function S.alignHud()
    if S.readableCall(InCombatLockdown)~=false then S.hudPixelSnapPending=true;return false end
    local initial=S.hudInitialLayoutPending
    local left,top
    if not initial then
        left,top=hudPhysicalOrigin()
        if not finiteGeometry(left) or not finiteGeometry(top) then S.hudPixelSnapPending=true;return false end
    end
    local parentScale = S.readableCall(UIParent.GetEffectiveScale, UIParent)
    local parentHeight = S.readableCall(UIParent.GetHeight, UIParent)
    local height=S.readableCall(function() local _,value=GetPhysicalScreenSize();return value end)
    if positiveGeometry(height) and positiveGeometry(parentHeight) and positiveGeometry(parentScale) then
        -- WoW's root UI coordinates are not physical screen pixels. Cancelling
        -- UIParent scale alone still leaves the root-to-screen scaling factor.
        S.hud:SetScale(parentHeight / height)
    else S.hudPixelSnapPending=true;return false end
    if initial and not S.hudInitialLayoutApplied then
        S.hudPixelSnapPending=true;return true
    end
    local aligned=S.snapHudToPixels(left,top)
    if aligned and initial then S.hudInitialLayoutPending=false end
    return aligned
end
S.handlers = {}
function S.retryHudInitialLayout()
    if S.hudLoginSeen and S.hudInitialLayoutPending and type(ns.applyCurrentBridge)=="function" then
        return ns.applyCurrentBridge()
    end
end
S.handlers.PLAYER_LOGIN = function()
    S.hudLoginSeen=true
    local saved=type(FeuxtonDB)=="table" and FeuxtonDB.updateRateMs or 100
    if not ns.setUpdateRate(saved) then ns.setUpdateRate(100) end
    S.alignHud(); S.resolveSpells(); S.discoverBindings(); S.refreshCooldowns(); S.refreshFlags()
end
S.handlers.SPELLS_CHANGED = function()
    S.resolveSpells(); S.discoverBindings(); S.refreshCooldowns();S.retryHudInitialLayout()
end
S.handlers.PLAYER_ENTERING_WORLD = S.retryHudInitialLayout
S.handlers.SPELL_DATA_LOAD_RESULT = S.handlers.SPELLS_CHANGED
S.handlers.SPELL_UPDATE_COOLDOWN = S.refreshCooldowns
S.handlers.SPELL_UPDATE_USABLE = S.refreshCooldowns
S.handlers.PLAYER_TARGET_CHANGED = S.refreshFlags
S.handlers.UNIT_FLAGS = S.refreshFlags
S.handlers.UNIT_PET = S.refreshFlags
S.handlers.PLAYER_REGEN_DISABLED = function() S.refreshFlags(); S.refreshCooldowns() end
S.handlers.PLAYER_REGEN_ENABLED = function()
    if S.hudInitialLayoutPending and type(ns.applyCurrentBridge)=="function" then
        S.retryHudInitialLayout()
    elseif S.hudPixelSnapPending then S.alignHud() end
    S.resolveSpells(); S.discoverBindings(); S.refreshFlags(); S.refreshCooldowns()
end
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
local function hudGeometryChanged()
    if S.hudLoginSeen and S.hudInitialLayoutPending then return S.retryHudInitialLayout() end
    return S.alignHud()
end
S.handlers.UI_SCALE_CHANGED = hudGeometryChanged
S.handlers.DISPLAY_SIZE_CHANGED = hudGeometryChanged
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
    add("Current bridge profile",S.compactBridgeLayout)
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
    local shortcut=message:match("^%s*[Kk][Ee][Yy][Ss]%s+(.+)%s*$")
    if message:match("^%s*[Kk][Ee][Yy][Ss]%s*$") then shortcut="" end
    if shortcut~=nil and S.shortcutCommand then S.shortcutCommand(shortcut);return end
    local rate=message:match("^rate%s+(.+)$")
    if message=="dense" or message=="compact" then
        if not ns.applyCurrentBridge() then print("Feuxton: current layout requires a supported class outside combat.") end
    elseif message=="standard" or message=="legacy" then
        print("Feuxton: retired layout. Use /feuxton dense for the current bridge.")
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
        S.hud:SetPoint("TOPLEFT",UIParent,"TOPLEFT",32,-280); S.alignHud(); S.hudDragHandle:EnableMouse(true)
    elseif message == "report" then
        S.edit:SetText(S.report()); S.panel:Show(); S.edit:SetFocus(); S.edit:HighlightText()
    else
        S.hud:Show(); S.alignHud(); S.resolveSpells(); S.discoverBindings(); S.refreshCooldowns(); S.refreshFlags()
    end
end

