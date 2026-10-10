-- Native filtered aura widgets and rendered texture mirrors.
local _, ns = ...
local S = ns.state

-- Let the client render auras directly. CustomAuraContainer owns filtering,
-- texture bindings and visibility; addon Lua does not read aura contents.
S.nativeAuras, S.nativeAuraReady, S.nativeAuraError = nil, nil, nil
S.nativeAuraInitialized=0
S.nativeOK,S.nativeError=pcall(function()
    S.nativeAuras=CreateFrame("AuraContainer",nil,S.auraMirror,"CustomAuraContainerTemplate")
    S.nativeAuras:SetPoint("TOPLEFT",12,-20)
    S.nativeAuras:SetSize(624,24)
    local layout={elementWidth=24,elementHeight=24,elementSpacing=2,lineSpacing=2}
    S.nativeAuras:AddAuraGroup("targetDebuffs","HARMFUL",{
        maxFrameCount=24,candidateFilters={},layout=layout,
        initializeFrame=function(button)
            local ok,err=pcall(function()
                button:SetSize(24,24)
                button:EnableMouse(false)
                local icon=button:CreateTexture(nil,"ARTWORK")
                icon:SetAllPoints(button)
                button:SetIcon(icon)
                -- Parent visibility is handled by the aura engine, including
                -- pooled hidden frames. The reader scans only green markers.
                local dot=button:CreateTexture(nil,"OVERLAY")
                dot:SetSize(4,4)
                dot:SetPoint("TOPRIGHT",button,"TOPRIGHT",0,5)
                dot:SetColorTexture(0,1,0,1)
                S.nativeAuraInitialized=S.nativeAuraInitialized+1
            end)
            if not ok then S.nativeAuraError=S.describe(err) end
        end,
    })
    S.nativeAuras:SetAuraGroupLayout("targetDebuffs",layout)
    S.nativeAuras:SetFlowLayoutAnchorPoint("TOPLEFT")
    S.nativeAuras:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right,AnchorUtil.FlowDirection.Down)
    S.nativeAuras:SetFlowLayoutMaximumLineSize(624)
    S.nativeAuras:SetEnabled(true)
    S.nativeAuras:SetUnit("target")
    S.nativeAuraReady=true
end)
if not S.nativeOK then
    S.nativeAuraError=S.describe(S.nativeError)
    if S.nativeAuras then pcall(S.nativeAuras.Hide,S.nativeAuras) end
end
-- Dedicated native slots render filtered presence without exposing aura data
-- or inspecting protected frame visibility in addon Lua.
S.filteredAuras, S.filteredReady, S.filteredError = nil, nil, nil
S.filteredSettledAt=GetTime()+0.6
S.filteredNonce=math.random(1,16777215)
S.filteredReadyDot=S.auraMirror:CreateTexture(nil,"OVERLAY")
S.filteredReadyDot:SetSize(4,4); S.filteredReadyDot:SetPoint("TOPLEFT",438,-6)
S.filteredSessionDot=S.auraMirror:CreateTexture(nil,"OVERLAY")
S.filteredSessionDot:SetSize(4,4); S.filteredSessionDot:SetPoint("TOPLEFT",448,-6)
S.filteredSessionDot:SetColorTexture(math.floor(S.filteredNonce/65536)/255,math.floor(S.filteredNonce/256)%256/255,S.filteredNonce%256/255,1)
S.filteredSchema=S.auraMirror:CreateTexture(nil,"OVERLAY")
S.filteredSchema:SetSize(4,4); S.filteredSchema:SetPoint("TOPLEFT",426,-6)
S.filteredSchema:SetColorTexture(1,0.5,0,1)
S.filteredSpecs={
    {key="mark",name="Hunter's Mark",x=300,ids={1130,14323,14324,14325}},
    {key="sting",name="Serpent Sting",x=360,ids={1978,13549,13550,13551,13552,13553,13554,13555,25295}},
}
S.filteredOK,S.filteredSetupError=pcall(function()
    S.filteredAuras=CreateFrame("AuraContainer",nil,S.auraMirror,"CustomAuraContainerTemplate")
    S.filteredAuras:SetPoint("TOPLEFT",0,0); S.filteredAuras:SetSize(400,16)
    for _,spec in ipairs(S.filteredSpecs) do
        local ids={}
        -- IDs are fixed configuration, not values extracted from target auras.
        for _,id in ipairs(spec.ids) do ids[id]=true end
        local background=S.auraMirror:CreateTexture(nil,"ARTWORK")
        spec.background=background
        background:SetSize(12,12); background:SetPoint("TOPLEFT",spec.x,-2)
        background:SetColorTexture(0,0.25,1,1)
        local guard=S.auraMirror:CreateTexture(nil,"OVERLAY")
        spec.guard=guard
        guard:SetSize(4,4); guard:SetPoint("TOPLEFT",spec.x+14,-6)
        guard:SetColorTexture(spec.key=="mark" and 0 or 1, spec.key=="mark" and 1 or 0,1,1)
        local label=S.auraMirror:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        spec.label=label
        label:SetPoint("TOPLEFT",spec.x-34,-2); label:SetText(spec.key=="mark" and "Mark" or "Sting")
        local slotX=spec.x
        S.filteredAuras:AddAuraSlot(spec.key,"HARMFUL",{
            candidateFilters={includeSpellIDs=ids},
            initializeFrame=function(button)
                button:SetSize(12,12); button:SetPoint("TOPLEFT",S.filteredAuras,"TOPLEFT",slotX,-2)
                local icon=button:CreateTexture(nil,"ARTWORK"); icon:SetAllPoints(button); button:SetIcon(icon)
                local signal=button:CreateTexture(nil,"OVERLAY"); signal:SetAllPoints(button); signal:SetColorTexture(0,1,0,1)
            end,
        })
    end
    S.filteredAuras:SetUnit("target"); S.filteredAuras:SetEnabled(true)
    S.filteredReady=true
end)
if not S.filteredOK then S.filteredError=S.describe(S.filteredSetupError) end
-- Geometry only: native aura engines retain ownership of values and visibility.
ns.configureHeaderTargetAuras=function(profile)
    local packed=profile and profile.headerTargetAuras
    local function point(widget,parent,x,y)
        if widget then widget:ClearAllPoints();widget:SetPoint("TOPLEFT",parent,"TOPLEFT",x,-y) end
    end
    S.auraMirror:SetHeight(packed and 32 or 46)
    point(S.nativeAuras,S.auraMirror,12,packed and 6 or 20)
    for i,slot in ipairs(S.auraSlots) do
        point(slot.icon,S.auraMirror,12+(i-1)*26,packed and 6 or 20)
        point(slot.dot,S.auraMirror,32+(i-1)*26,packed and 1 or 15)
    end
    point(S.filteredAuras,packed and S.hud or S.auraMirror,packed and -120 or 0,packed and 14 or 0)
    for _,spec in ipairs(S.filteredSpecs) do
        local parent=packed and S.hud or S.auraMirror;local x=spec.x-(packed and 120 or 0)
        point(spec.background,parent,x,packed and 16 or 2)
        point(spec.guard,parent,x+14,packed and 20 or 6)
        if spec.label then if packed then spec.label:Hide() else spec.label:Show() end end
    end
    for _,entry in ipairs({{S.filteredSchema,426},{S.filteredReadyDot,438},{S.filteredSessionDot,448}}) do
        point(entry[1],packed and S.hud or S.auraMirror,entry[2]-(packed and 120 or 0),packed and 20 or 6)
    end
end
function S.refreshFilteredAuras()
    local hostile=S.readableCall(UnitExists,"target")==true and S.readableCall(UnitCanAttack,"player","target")==true
        and S.readableCall(UnitIsDeadOrGhost,"target")==false and S.readableCall(UnitIsUnit,"target","player")==false
    S.drawFlag(S.filteredReadyDot,S.filteredReady==true and hostile and GetTime()>=S.filteredSettledAt)
end
function S.refreshAuraMirror()
    S.clearAuraMirror()
    S.auraGenerationPixel:SetColorTexture(S.auraGeneration/255,0,0,1)
    if S.nativeAuraReady then
        S.auraTitle:SetText("TARGET DEBUFFS")
        if S.readableCall(UnitExists,"target")==true then S.nativeAuras:Show()
        else S.nativeAuras:Hide() end
        S.auraDiagnostic=S.nativeAuraError and ("Native aura rendering error: "..S.nativeAuraError)
            or "Native target aura engine / HARMFUL / 24 slots / no aura values read by Lua"
        S.auraStatus:SetText(S.auraDiagnostic)
        return
    end
    if S.readableCall(UnitExists,"target") ~= true then
        S.auraDiagnostic = "no target"; S.auraStatus:SetText(S.auraDiagnostic); return
    end
    local sources, visited, sourceTextures = {}, {}, {}
    local sourceKind = "target frame"
    local inspected, hiddenIcons, unknownVisibility = 0, 0, 0
    local function addIcon(icon,frame)
        if not icon or S.isSecret(icon) or sourceTextures[icon] or #sources>=24 then return end
        if type(icon.GetTexture)~="function" then return end
        local visible=S.readableCall(frame.IsVisible,frame)
        if visible==false then hiddenIcons=hiddenIcons+1; return end
        if visible==nil then
            unknownVisibility=unknownVisibility+1
            -- Only forward unreadable visibility to a native renderer. Never
            -- branch on its value or display stale hidden pooled aura textures.
            if type(S.auraSlots[1].icon.SetAlphaFromBoolean)~="function"
                or type(S.auraSlots[1].dot.SetAlphaFromBoolean)~="function" then return end
        end
        sources[#sources+1]={icon=icon,frame=frame}; sourceTextures[icon]=true
    end
    local function visit(frame, depth)
        if not frame or S.isSecret(frame) or visited[frame] or #sources >= 24 or inspected>=160 then return end
        visited[frame] = true
        inspected=inspected+1
        if S.readableCall(frame.IsForbidden,frame) == true then return end
        local name=S.readableCall(frame.GetName,frame)
        -- These native subtrees contain non-aura icons, or another unit's auras.
        if frame==TargetFrameToT or frame==TargetFrameSpellBar
            or (type(name)=="string" and (name:find("TargetFrameToT",1,true)
                or name:find("SpellBar",1,true) or name:find("PowerBar",1,true)
                or name:find("Combo",1,true))) then return end
        local icon = frame.Icon or frame.icon
        if not icon and type(name)=="string" then icon=_G[name.."Icon"] end
        if icon and not S.isSecret(icon) and type(icon.GetTexture) == "function" then
            addIcon(icon,frame)
            return
        end
        if depth >= 6 or type(frame.GetChildren) ~= "function" then return end
        local children = { frame:GetChildren() }
        for _, child in ipairs(children) do visit(child,depth+1) end
    end
    -- Support the current target container and older named target aura buttons.
    local enumerationOK, enumerationError = pcall(function()
        if TargetFrame and type(TargetFrame.GetAuraContainer) == "function" then
            visit(TargetFrame:GetAuraContainer(),0)
        end
        -- Some clients use unnamed aura children instead of the mainline
        -- container or Classic's numbered globals.
        if TargetFrame then
            visit(TargetFrame.AurasFrame,0)
            visit(TargetFrame.BuffFrame,0)
            local content=TargetFrame.TargetFrameContent
            local contextual=content and content.TargetFrameContentContextual
            if contextual then visit(contextual.Auras,0) end
        end
        for index=1,40 do
            for _,kind in ipairs({"Debuff","Buff"}) do
                local button = _G["TargetFrame"..kind..index]
                if button then
                    local icon = _G["TargetFrame"..kind..index.."Icon"]
                    if icon then
                        addIcon(icon,button)
                    else visit(button,0) end
                end
            end
        end
        -- Discover named aura buttons under the native target only. Do not
        -- treat portrait, cast-bar or other arbitrary textures as aura icons.
        local function findAuraChildren(frame,depth)
            if not frame or S.isSecret(frame) or depth>6 or type(frame.GetChildren)~="function" then return end
            if S.readableCall(frame.IsForbidden,frame)==true then return end
            local name=S.readableCall(frame.GetName,frame)
            local instance=frame.auraInstanceID
            local auraWidget=S.isSecret(instance) or instance~=nil
            if auraWidget or (type(name)=="string" and (name:find("Debuff",1,true) or name:find("Buff",1,true) or name:find("Aura",1,true))) then
                visit(frame,0)
                return
            end
            for _,child in ipairs({frame:GetChildren()}) do findAuraChildren(child,depth+1) end
        end
        findAuraChildren(TargetFrame,0)
        -- This client's report shows unnamed target-content children. Walk
        -- that native tree, with cast-bar, power-bar and ToT subtrees excluded.
        visit(TargetFrame,0)
        -- Some client branches assign different native target-frame prefixes.
        -- Read only named aura buttons; never scan arbitrary icon textures.
        for name,button in pairs(_G) do
            if type(name)=="string" and name:find("TargetFrame",1,true)
                and not name:find("TargetFrameToT",1,true)
                and (name:find("Debuff",1,true) or name:find("Buff",1,true))
                and not S.isSecret(button) and type(button)=="table"
                and type(button.GetChildren)=="function" then
                local icon=_G[name.."Icon"]
                if icon then addIcon(icon,button) else visit(button,0) end
            end
        end
        -- The capability probe already found this client's nameplate aura
        -- widgets. Use only the plate whose readable unit match is the target.
        if #sources == 0 and C_NamePlate and type(C_NamePlate.GetNamePlateForUnit)=="function" then
            for index=1,40 do
                local token="nameplate"..index
                if S.readableCall(UnitIsUnit,token,"target")==true then
                    local plate=C_NamePlate.GetNamePlateForUnit(token)
                    if plate and not S.isSecret(plate) and S.readableCall(plate.IsForbidden,plate)~=true then
                        -- Plater keeps its displayed frame in lowercase
                        -- unitFrame; Blizzard's UnitFrame can remain hidden.
                        for _,key in ipairs({"unitFrame","UnitFrame"}) do
                            local unitFrame=plate[key]
                            if unitFrame and not S.isSecret(unitFrame) then
                                sourceKind="target nameplate / "..key
                                for _,containerKey in ipairs({"AurasFrame","BuffFrame","BuffFrame2"}) do
                                    local container=unitFrame[containerKey]
                                    visit(container,0)
                                    -- Older Plater pools may reparent buttons;
                                    -- inspect only this target's explicit pool.
                                    local pool=container and container.PlaterBuffList
                                    if not S.isSecret(pool) and type(pool)=="table" then
                                        for i=1,math.min(#pool,40) do visit(pool[i],0) end
                                    end
                                end
                            end
                        end
                    end
                    break
                end
            end
        end
    end)
    local copied, failed = 0, 0
    for index, source in ipairs(sources) do
        local slot = S.auraSlots[index]
        local ok, err = pcall(function()
            -- Pass the native texture value directly, without inspecting it.
            slot.icon:SetAlpha(1); slot.dot:SetAlpha(1)
            slot.icon:SetTexture(source.icon:GetTexture())
            if type(slot.icon.SetAlphaFromBoolean)=="function"
                and type(slot.dot.SetAlphaFromBoolean)=="function" then
                slot.icon:SetAlphaFromBoolean(source.frame:IsVisible(),1,0)
                slot.dot:SetAlphaFromBoolean(source.frame:IsVisible(),1,0)
            elseif S.readableCall(source.frame.IsVisible,source.frame)~=true then
                error("Aura visibility unavailable")
            end
        end)
        if ok then copied=copied+1; slot.error=nil; S.drawFlag(slot.dot,true)
        else failed=failed+1; slot.error=S.describe(err); slot.icon:SetTexture(nil) end
    end
    S.auraDiagnostic = "Copied "..copied.." / failed "..failed.." / hidden "..hiddenIcons.." / visibility unknown "..unknownVisibility.." / scanned "..inspected.." / "..sourceKind.." / target generation "..S.auraGeneration
    if not enumerationOK then S.auraDiagnostic=S.auraDiagnostic.." / "..S.describe(enumerationError) end
    if S.nativeAuraError then S.auraDiagnostic=S.auraDiagnostic.." / native setup: "..S.nativeAuraError end
    S.auraStatus:SetText(S.auraDiagnostic)
end
S.auraElapsed = 0
S.auraMirror:SetScript("OnUpdate",function(self,elapsed)
    S.auraElapsed=S.auraElapsed+elapsed
    if S.auraElapsed<S.updateInterval() then return end
    S.auraElapsed=0
    pcall(S.refreshFilteredAuras)
    local ok,err=pcall(S.refreshAuraMirror)
    if not ok then S.clearAuraMirror(); S.auraDiagnostic=S.describe(err); S.auraStatus:SetText(S.auraDiagnostic) end
end)
S.auraEvents = CreateFrame("Frame")
S.auraEvents:RegisterEvent("PLAYER_TARGET_CHANGED")
S.auraEvents:SetScript("OnEvent",function()
    S.auraGeneration=(S.auraGeneration+1)%256
    S.filteredSettledAt=GetTime()+0.6
    S.drawFlag(S.filteredReadyDot,false)
    if S.filteredReady then
        local ok,err=pcall(S.filteredAuras.UpdateAllAuras,S.filteredAuras)
        if not ok then S.filteredReady=false; S.filteredError=S.describe(err) end
    end
    S.clearAuraMirror()
    if S.nativeAuraReady then
        local ok,err=pcall(S.nativeAuras.UpdateAllAuras,S.nativeAuras)
        if not ok then S.nativeAuraError=S.describe(err) end
    end
end)
S.previousHudReport = ns.hudReport
ns.hudReport=function(add)
    S.previousHudReport(add)
    add("Aura mirror",S.auraDiagnostic)
    add("Native aura renderer ready",S.describe(S.nativeAuraReady))
    add("Native aura buttons initialized",S.describe(S.nativeAuraInitialized))
    add("Filtered aura slots ready",S.describe(S.filteredReady))
    if S.filteredError then add("Filtered aura error",S.filteredError) end
    if S.nativeAuraError then add("Native aura renderer error",S.nativeAuraError) end
    add("Native target frame",TargetFrame and S.query(TargetFrame.GetName,TargetFrame) or "missing")
    add("Native target visible",TargetFrame and S.query(TargetFrame.IsVisible,TargetFrame) or "missing")
    local diagnosticCount=0
    local function frameLayout(frame,path,depth)
        if not frame or S.isSecret(frame) or diagnosticCount>=60 or depth>5 then return end
        if S.readableCall(frame.IsForbidden,frame)==true then return end
        diagnosticCount=diagnosticCount+1
        add(path,S.query(frame.GetName,frame).." / visible "..S.query(frame.IsVisible,frame))
        if type(frame.GetChildren)=="function" then
            for index,child in ipairs({frame:GetChildren()}) do frameLayout(child,path.."."..index,depth+1) end
        end
    end
    pcall(frameLayout,TargetFrame,"Target layout",0)
    for _,display in ipairs(S.unitDisplays) do
        if display.error then add("Unit display "..display.token,display.error) end
    end
    for index,slot in ipairs(S.auraSlots) do
        if slot.error then add("Aura mirror slot "..index,slot.error) end
    end
end

