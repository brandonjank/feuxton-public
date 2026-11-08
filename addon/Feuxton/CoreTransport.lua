-- HHF4 single-frame core pixel transport.
local _, ns = ...
local S = ns.state

-- One-frame core link: never waits for the spellbook/talent page cycle.
S.fastFrame=CreateFrame("Frame",nil,S.hud)
S.fastFrame:SetPoint("TOPLEFT",S.metadataFrame,"BOTTOMLEFT",0,-4); S.fastFrame:SetSize(668,12)
function S.renderFastSetup()
    local class=S.setupString(S.setupValue(UnitClass,2,"player"))
    local classes={"HUNTER","SHAMAN","WARRIOR","WARLOCK","DRUID","ROGUE","PALADIN","PRIEST","MAGE"}
    local classID=0
    for i,name in ipairs(classes) do if class==name then classID=i; break end end
    local level=S.setupNumber(S.readableCall(UnitLevel,"player")) or 0
    if level<0 or level>100 then level=0 end
    local count=ns.classes[class] and ns.classes[class].coreSlotCount or 10
    local packet="HHF4"..S.bytes(S.setupSession,4)..S.bytes(S.setupRevision,2)..S.bytes(classID,1)..S.bytes(level,1)..S.bytes(S.bindingsValid and 1 or 0,1)..S.bytes(count,1)..S.bytes(S.updateRateMs,2)..S.bytes(S.auraGeneration,1)
    if classID~=1 then
        -- Positional placeholders match the registered class contract; current
        -- non-Hunter spell observations come from the class-owned packet.
        packet=packet..string.rep("\0",count*10)
    else
    for tileIndex,tile in ipairs(S.tiles) do
        if tileIndex>10 then break end
        local chosen=S.bindingsValid and S.preferredMapping(tile.mappings)
        local valid=S.mappingCurrent(chosen)
        local slot=valid and chosen.slot or 0
        local key=valid and S.setupString(chosen.key) or ""
        if not key or #key>20 then key="" end
        local id=S.setupNumber(S.boundSpellID(tile)) or 0
        packet=packet..S.bytes(id,4)..S.bytes(valid and slot or 0,2)..S.bytes(valid and (chosen.kind=="spell" and 1 or 2) or 0,1)..S.bytes(#key,1)..key..S.bytes(S.directSpellFlags(S.hunterSpecs[tileIndex].name,id,tile.known),1)..S.bytes(S.spellUseCode(S.hunterSpecs[tileIndex].key),1)
    end
    end
    packet=packet..S.bytes(classID==1 and (S.spellUseCode("hunter.aspectHawk")+S.spellUseCode("hunter.aspectCheetah")*4+S.spellUseCode("hunter.aspectMonkey")*16) or 0,1)
    packet=packet..S.bytes(S.adler32(packet),4)
    S.publishTransportPacket(1,packet)
end
S.fastElapsed=0
S.fastFrame:SetScript("OnUpdate",function(self,elapsed)
    S.fastElapsed=S.fastElapsed+elapsed
    if S.fastElapsed>=S.updateInterval() then
        S.fastElapsed=0
        local ok=pcall(S.renderFastSetup)
        if not ok then S.publishTransportPacket(1,nil) end
    end
end)
S.fastInitialOK=pcall(S.renderFastSetup)
S.previousSetupReport=ns.hudReport
ns.hudReport=function(add)
    S.previousSetupReport(add)
    add("Setup metadata revision",S.setupRevision)
    add("Setup metadata pending",S.setupDirty)
    add("Setup metadata bytes",#S.setupPayload)
    add("Setup metadata pages",#S.setupPages)
    if S.setupError then add("Setup metadata error",S.setupError) end
end

