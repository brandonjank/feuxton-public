-- Reusable native spell tiles for class bridges. Native cooldown/range/aura
-- rendering is shared; each class owns catalog, packet order and semantics.
local _,ns=...
local B={}
ns.features.SpellBridge=B
-- Costs and maximum mana may be secret. Only native widgets receive them.
function B.createManaCost(parent,x,y,width)
    local bar=CreateFrame("StatusBar",nil,parent);bar:SetPoint("TOPLEFT",x,-y);bar:SetSize(width,4)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8");bar:SetStatusBarColor(0,.5,1,1)
    local bg=bar:CreateTexture(nil,"BACKGROUND");bg:SetAllPoints();bg:SetColorTexture(.18,.18,.18,1)
    local valid=parent:CreateTexture(nil,"OVERLAY");valid:SetSize(4,4);valid:SetPoint("TOPLEFT",x+width+2,-y)
    return {bar=bar,valid=valid}
end
local function manaStatus(widget,status)
    if widget.feuxtonManaStatus~=status then
        widget.feuxtonManaStatus=nil
        if status==0 then widget.valid:SetColorTexture(1,.65,0,1)
        else widget.valid:SetColorTexture(0,1,status==2 and 1 or 0,1) end
        widget.feuxtonManaStatus=status
    end
end
function B.renderPowerCost(widget,id,learned,powerType)
    local S=ns.state
    if learned~=true or type(id)~="number" or id<=0 then manaStatus(widget,0);return end
    local zero=false
    local ok=pcall(function()
        local api=S.spellAPI.GetSpellPowerCost or GetSpellPowerCost
        if type(api)~="function" then error("Cost API unavailable") end
        local queried,costs=pcall(api,id)
        if not queried then error("Cost query failed") end
        -- Nil can mean either no resource costs or an unresolved spell. It
        -- cannot certify zero; an explicit empty cost table can.
        if S.isSecret(costs) then error("Cost unavailable") end
        if costs==nil then error("Cost unavailable") end
        if type(costs)~="table" or #costs>8 then error("Cost unavailable") end
        local cost,found=0,false
        for _,entry in ipairs(costs) do
            if S.isSecret(entry) or type(entry)~="table" then error("Cost entry unavailable") end
            local kind=S.safeField(entry,"type")
            if type(kind)~="number" or kind<0 or kind>255 or kind~=math.floor(kind) then error("Cost type unavailable") end
            if kind==(powerType or 0) then
                if found then error("Multiple mana costs") end
                found=true
                for _,key in ipairs({"costPerSec","costPerSecond"}) do
                    local extra=entry[key]
                    if S.isSecret(extra) or extra~=nil and (type(extra)~="number" or extra~=0) then error("Variable cost") end
                end
                cost=entry.cost
                if not S.isSecret(cost) and (type(cost)~="number" or cost<0 or cost~=cost or cost==math.huge) then error("Cost unavailable") end
                local minimum=entry.minCost
                if S.isSecret(minimum) or minimum~=nil and (type(minimum)~="number" or minimum<0 or minimum~=minimum or minimum>0 and (S.isSecret(cost) or minimum>cost)) then error("Variable cost") end
            end
        end
        local maximum=UnitPowerMax("player",powerType or 0)
        if not S.isSecret(maximum) and (type(maximum)~="number" or maximum<=0 or maximum~=maximum or maximum==math.huge) then error("Mana maximum unavailable") end
        widget.bar:SetMinMaxValues(0,maximum);widget.bar:SetValue(cost)
        zero=not S.isSecret(cost) and cost==0
    end)
    manaStatus(widget,ok and (zero and 2 or 1) or 0)
end
function B.renderManaCost(widget,id,learned) return B.renderPowerCost(widget,id,learned,0) end
-- Public proc counts only. An incomplete/restricted scan cannot prove zero.
-- This also serves class bridges which do not use the shared native tiles.
function B.stackCount(unit,name,maximum)
    local S=ns.state;local G=ns.features.GroupContext
    if B.stackSession~=S.setupSession then B.stackSession=S.setupSession;B.stackIdentities={} end
    B.stackIdentities=B.stackIdentities or {};local key=unit..":"..name
    if type(C_UnitAuras)~="table" or type(C_UnitAuras.GetAuraDataByIndex)~="function" then return 255 end
    for i=1,80 do
        local ok,aura=pcall(C_UnitAuras.GetAuraDataByIndex,unit,i,"HELPFUL")
        if not ok or S.isSecret(aura) then return 255 end
        if aura==nil then return B.stackIdentities[key] and 0 or 255 end
        local label=G.text(G.field(aura,"name"),80)
        if label=="" then return 255 end
        if label==name then
            local count=G.field(aura,"applications")
            if count.status=="observed" and type(count.value)=="number" and count.value==math.floor(count.value) and count.value>=0 and count.value<=maximum then
                local id=G.field(aura,"spellId")
                if id.status=="observed" and type(id.value)=="number" and id.value>0 and id.value==math.floor(id.value) then B.stackIdentities[key]=id.value end
                return count.value
            end
            return 255
        end
    end
    return 255
end
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
        for j=1,4 do local dot=panel:CreateTexture(nil,"OVERLAY");dot:SetSize(4,4);dot:SetPoint("TOPLEFT",x+(j-1)*6,-y-26);ns.features.RangeTracking.initialize(dot,1,.65,0,1);tile.visualSignals[j]=dot end
        -- The default usage dot extends past the icon's right edge into this
        -- compact tile's cooldown sample. Keep controls below the icon instead.
        local useButton=S.attachSpellUse(panel,tile.icon,spec.usageKey or spec.key)
        useButton.useDot:ClearAllPoints();useButton.useDot:SetPoint("TOPLEFT",tile.icon,"BOTTOMLEFT",0,-2)
        result.tiles[i]=tile
    end
    return result
end
function B.render(bridge,index,id,learned,spec)
    local S=ns.state;local tile=bridge.tiles[index];tile.spellID=id>0 and id or nil;tile.known=learned;tile.offGlobalCooldown=spec.offGlobalCooldown==true
    local info=S.readableCall(S.spellAPI.GetSpellInfo,id);S.renderSpellIcon(tile,info)
    S.renderCooldown(tile)
    local range,usable=ns.features.RangeTracking.render(tile.visualSignals,id,spec.unit or "target")
    local R=ns.features.RangeTracking
    R.paintColor(tile.visualSignals[2],range and 0 or 1,range and 1 or .65,range and 1 or 0,1);R.paintFlag(tile.visualSignals[4],usable)
    if not range then R.paintColor(tile.visualSignals[1],1,.65,0,1) end
    if not usable then R.paintColor(tile.visualSignals[3],1,.65,0,1) end
    return tile
end
function B.auras(bridge,specs,readings)
    local S=ns.state;local G=ns.features.GroupContext;local signature={}
    -- Candidate effect IDs only configure a name-checked native filter. They
    -- do not certify absence; the app must observe the exact filter match first.
    bridge.candidateAuraIDs=bridge.candidateAuraIDs or {}
    bridge.candidateAuraRetry=bridge.candidateAuraRetry or {}
    local function candidates(spec)
        local ids={};local now=GetTime()
        for _,id in ipairs(spec.nativeAuraCandidates or {}) do
            if not S.isSecret(id) and type(id)=="number" and id>0 and id<2147483648 and id==math.floor(id) then
            if not bridge.candidateAuraIDs[id] and now>=(bridge.candidateAuraRetry[id] or 0) then
                bridge.candidateAuraRetry[id]=now+1
                local info=S.readableCall(S.spellAPI.GetSpellInfo,id)
                local name=S.safeField(info,"name")
                if type(name)=="string" and name~="" then bridge.candidateAuraIDs[id]=name end
            end
            if bridge.candidateAuraIDs[id]==(spec.auraName or spec.name) then ids[#ids+1]=id end
            end
        end
        return ids
    end
    local function actualAuraID(spec,reading)
        local observed=bridge.verifiedAuras[spec.auraName or spec.name]
        if observed then return observed end
        -- Optional class calibration certifies only the exact client build,
        -- bound spell rank and currently readable effect name. It configures
        -- a native filter; it never supplies an aura presence/absence value.
        if not spec.nativeAuraIDs then return nil end
        local build=G.text(G.read(GetBuildInfo,2),16)
        local ranks=spec.nativeAuraIDs[build];local id=ranks and ranks[reading.id]
        if not id then return nil end
        local info=S.readableCall(S.spellAPI.GetSpellInfo,id)
        if S.safeField(info,"name")~=(spec.auraName or spec.name) then return nil end
        return id
    end
    -- One guarded scan per unit, reused by every aura family.
    local scans={};local units=bridge.onlySpecifiedAuras and {} or {"player","target"};local filters={player="HELPFUL",target="HARMFUL|PLAYER"};local listed=bridge.onlySpecifiedAuras and {} or {player=true,target=true}
    for _,spec in ipairs(specs) do if spec.aura then
        if not listed[spec.aura] then units[#units+1]=spec.aura;listed[spec.aura]=true end
        if spec.auraFilter then filters[spec.aura]=spec.auraFilter end
    end end
    for _,unit in ipairs(units) do
        local scan={complete=false,names={}};scans[unit]=scan
        local filter=filters[unit] or "HARMFUL|PLAYER"
        if type(C_UnitAuras)=="table" and type(C_UnitAuras.GetAuraDataByIndex)=="function" then
            for j=1,80 do
                local ok,aura=pcall(C_UnitAuras.GetAuraDataByIndex,unit,j,filter)
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
        signature[#signature+1]=i..":"..readings[i].id..":"..G.code(readings[i].learned)..":"..(actualAuraID(spec,readings[i]) or 0)..":"..table.concat(candidates(spec),",")..":"..(filters[spec.aura] or "HARMFUL|PLAYER")
    end end
    signature=table.concat(signature,"|")
    if signature==bridge.auraSignature then return end
    if S.readableCall(InCombatLockdown)~=false then return end
    bridge.auraSignature=signature;bridge.absence={};bridge.configured={};bridge.auraRevision=((bridge.auraRevision or 0)+1)%4294967296;bridge.settledAt=GetTime()+.6
    for _,container in ipairs(bridge.containers or {}) do pcall(container.SetEnabled,container,false);pcall(container.Hide,container) end
    bridge.containers={}
    if ns.retireNativeSignalAuras then pcall(ns.retireNativeSignalAuras,bridge) end
    for _,unit in ipairs(units) do
        local container;local certified,configured={},{}
        local ok=pcall(function()
            container=CreateFrame("AuraContainer",nil,bridge.panel,"CustomAuraContainerTemplate");container:SetAllPoints(bridge.panel)
            for i,spec in ipairs(specs) do if spec.aura==unit and readings[i].learned.status=="observed" and readings[i].learned.value==true then
                local ids=spec.auraName and {} or {[readings[i].id]=true};local actual=actualAuraID(spec,readings[i])
                for _,known in ipairs(S.setupKnownSpells or {}) do if known.name==(spec.auraName or spec.name) then ids[known.id]=true end end
                if actual then ids[actual]=true;certified[i]=true end
                for _,id in ipairs(candidates(spec)) do ids[id]=true end
                local x,y=spec.auraX or 12+(i-1)%14*46+36,spec.auraY or 6+math.floor((i-1)/14)*40
                -- An unresolved alias must not create an empty filter that
                -- the client could interpret as matching every aura.
                local signalIndex
                if next(ids) and ns.declareNativeSignalAura then local declared,index=pcall(ns.declareNativeSignalAura,bridge,spec.key,unit,bridge.auraRevision,filters[unit] or "HARMFUL|PLAYER",actual and 2 or 1);if declared then signalIndex=index end end
                if next(ids) then container:AddAuraSlot(spec.key,filters[unit] or "HARMFUL|PLAYER",{candidateFilters={includeSpellIDs=ids},initializeFrame=function(button)
                    button:SetSize(spec.auraSize or 8,spec.auraSize or 8);button:SetPoint("TOPLEFT",container,"TOPLEFT",x,-y);button:EnableMouse(false)
                    local icon=button:CreateTexture(nil,"ARTWORK");icon:SetAllPoints();button:SetIcon(icon)
                    local signal=button:CreateTexture(nil,"OVERLAY");signal:SetAllPoints();signal:SetColorTexture(0,1,0,1)
                    if signalIndex and ns.attachNativeSignalAura then pcall(ns.attachNativeSignalAura,signalIndex,button) end
                end});configured[i]=true end
            end end
            container:SetUnit(unit);container:SetEnabled(true)
        end)
        if ok then bridge.containers[#bridge.containers+1]=container;for i in pairs(certified) do bridge.absence[i]=true end;for i in pairs(configured) do bridge.configured[i]=true end elseif container then pcall(container.Hide,container) end
    end
end
