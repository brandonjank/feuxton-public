-- Reusable native spell tiles for class bridges. Native cooldown/range/aura
-- rendering is shared; each class owns catalog, packet order and semantics.
local _,ns=...
local B={}
ns.features.SpellBridge=B
function B.create(parent,specs)
    local S=ns.state;local panel=CreateFrame("Frame",nil,parent);panel:SetSize(668,120);panel:SetPoint("TOPLEFT",0,-26)
    local result={panel=panel,tiles={},stamp={},verifiedAuras={}}
    for i=1,4 do local dot=panel:CreateTexture(nil,"OVERLAY");dot:SetSize(4,4);dot:SetPoint("TOPLEFT",626+(i-1)*6,0);result.stamp[i]=dot end
    for i,spec in ipairs(specs) do
        local tile={};local x,y=12+(i-1)%14*46,6+math.floor((i-1)/14)*40
        tile.icon=panel:CreateTexture(nil,"ARTWORK");tile.icon:SetSize(16,16);tile.icon:SetPoint("TOPLEFT",x,-y)
        tile.dial=panel:CreateTexture(nil,"BACKGROUND");tile.dial:SetSize(16,16);tile.dial:SetPoint("TOPLEFT",x+18,-y)
        tile.cooldown=CreateFrame("Cooldown",nil,panel,"CooldownFrameTemplate");tile.cooldown:SetAllPoints(tile.dial);tile.cooldown:SetDrawEdge(false);tile.cooldown:SetDrawSwipe(true);tile.cooldown:SetSwipeColor(0,0,0,1);tile.cooldown:SetHideCountdownNumbers(true)
        tile.aura=panel:CreateTexture(nil,"ARTWORK");tile.aura:SetSize(8,8);tile.aura:SetPoint("TOPLEFT",x+36,-y);tile.aura:SetColorTexture(0,.25,1,1)
        tile.visualSignals={}
        for j=1,4 do local dot=panel:CreateTexture(nil,"OVERLAY");dot:SetSize(4,4);dot:SetPoint("TOPLEFT",x+(j-1)*6,-y-26);tile.visualSignals[j]=dot end
        -- The default usage dot extends past the icon's right edge into this
        -- compact tile's cooldown sample. Keep controls below the icon instead.
        local useButton=S.attachSpellUse(panel,tile.icon,spec.key)
        useButton.useDot:ClearAllPoints();useButton.useDot:SetPoint("TOPLEFT",tile.icon,"BOTTOMLEFT",0,-2)
        result.tiles[i]=tile
    end
    return result
end
function B.render(bridge,index,id,learned,spec)
    local S=ns.state;local tile=bridge.tiles[index];tile.spellID=id>0 and id or nil;tile.known=learned;tile.offGlobalCooldown=spec.offGlobalCooldown==true
    local info=S.readableCall(S.spellAPI.GetSpellInfo,id);tile.icon:SetTexture(S.safeField(info,"iconID") or "Interface\\Icons\\INV_Misc_QuestionMark")
    S.renderCooldown(tile)
    local range,usable=ns.features.RangeTracking.render(tile.visualSignals,id,spec.unit or "target")
    tile.visualSignals[2]:SetColorTexture(range and 0 or 1,range and 1 or .65,range and 1 or 0,1);S.drawFlag(tile.visualSignals[4],usable)
    if not range then tile.visualSignals[1]:SetVertexColor(1,1,1,1);tile.visualSignals[1]:SetColorTexture(1,.65,0,1) end
    if not usable then tile.visualSignals[3]:SetVertexColor(1,1,1,1);tile.visualSignals[3]:SetColorTexture(1,.65,0,1) end
    return tile
end
function B.auras(bridge,specs,readings)
    local S=ns.state;local G=ns.features.GroupContext;local signature={}
    -- One guarded scan per unit, reused by every aura family.
    local scans={}
    for _,unit in ipairs({"player","target"}) do
        local scan={complete=false,names={}};scans[unit]=scan
        if type(C_UnitAuras)=="table" and type(C_UnitAuras.GetAuraDataByIndex)=="function" then
            for j=1,80 do
                local ok,aura=pcall(C_UnitAuras.GetAuraDataByIndex,unit,j,unit=="target" and "HARMFUL|PLAYER" or "HELPFUL")
                if not ok or S.isSecret(aura) then break end
                if aura==nil then scan.complete=true;break end
                local name=G.text(G.field(aura,"name"),80);if name=="" then break end
                scan.names[name]=true
                local id=G.field(aura,"spellId")
                if id.status=="observed" and type(id.value)=="number" and id.value>0 then bridge.verifiedAuras[name]=id.value end
            end
        end
    end
    for i,spec in ipairs(specs) do if spec.aura then
        local scan=scans[spec.aura];local found=scan.names[spec.auraName or spec.name]
        readings[i].aura=found and {status="observed",value=true} or scan.complete and {status="observed",value=false} or {}
        signature[#signature+1]=i..":"..readings[i].id..":"..G.code(readings[i].learned)..":"..(bridge.verifiedAuras[spec.auraName or spec.name] or 0)
    end end
    signature=table.concat(signature,"|")
    if signature==bridge.auraSignature then return end
    if S.readableCall(InCombatLockdown)~=false then return end
    bridge.auraSignature=signature;bridge.absence={};bridge.settledAt=GetTime()+.6
    for _,container in ipairs(bridge.containers or {}) do pcall(container.SetEnabled,container,false);pcall(container.Hide,container) end
    bridge.containers={}
    for _,unit in ipairs({"player","target"}) do
        local container;local certified={}
        local ok=pcall(function()
            container=CreateFrame("AuraContainer",nil,bridge.panel,"CustomAuraContainerTemplate");container:SetAllPoints(bridge.panel)
            for i,spec in ipairs(specs) do if spec.aura==unit and readings[i].learned.status=="observed" and readings[i].learned.value==true then
                local ids=spec.auraName and {} or {[readings[i].id]=true};local actual=bridge.verifiedAuras[spec.auraName or spec.name]
                for _,known in ipairs(S.setupKnownSpells or {}) do if known.name==(spec.auraName or spec.name) then ids[known.id]=true end end
                if actual then ids[actual]=true;certified[i]=true end
                local x,y=12+(i-1)%14*46+36,6+math.floor((i-1)/14)*40
                -- An unresolved alias must not create an empty filter that
                -- the client could interpret as matching every aura.
                if next(ids) then container:AddAuraSlot(spec.key,unit=="target" and "HARMFUL|PLAYER" or "HELPFUL",{candidateFilters={includeSpellIDs=ids},initializeFrame=function(button)
                    button:SetSize(8,8);button:SetPoint("TOPLEFT",container,"TOPLEFT",x,-y);button:EnableMouse(false)
                    local icon=button:CreateTexture(nil,"ARTWORK");icon:SetAllPoints();button:SetIcon(icon)
                    local signal=button:CreateTexture(nil,"OVERLAY");signal:SetAllPoints();signal:SetColorTexture(0,1,0,1)
                end}) end
            end end
            container:SetUnit(unit);container:SetEnabled(true)
        end)
        if ok then bridge.containers[#bridge.containers+1]=container;for i in pairs(certified) do bridge.absence[i]=true end elseif container then pcall(container.Hide,container) end
    end
end
