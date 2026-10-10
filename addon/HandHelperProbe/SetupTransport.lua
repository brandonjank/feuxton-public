-- HHM1 setup collection, serialization and paged pixel transport.
local _, ns = ...
local S = ns.state

-- HHM1: paged setup metadata only. All exported values are whitelisted,
-- checked for secrets, and collected outside combat. No combat timings,
-- unit aura contents or macro bodies are serialized.
S.metadataFrame=CreateFrame("Frame",nil,S.hud)
S.metadataFrame:SetPoint("TOPLEFT",S.unitHud,"BOTTOMLEFT",0,-4)
S.metadataFrame:SetSize(668,12)
S.metadataBackground=S.metadataFrame:CreateTexture(nil,"BACKGROUND")
S.metadataBackground:SetAllPoints(); S.metadataBackground:SetColorTexture(0,0,0,1)
for index,color in ipairs({{1,0.5,0},{0,0.5,1},{0.5,1,0}}) do
    local dot=S.metadataFrame:CreateTexture(nil,"OVERLAY")
    dot:SetSize(4,4); dot:SetPoint("TOPLEFT",4+(index-1)*6,0)
    dot:SetColorTexture(color[1],color[2],color[3],1)
end
S.metadataCells={}
for row=0,2 do
    for column=0,159 do
        local pixel=S.metadataFrame:CreateTexture(nil,"ARTWORK")
        pixel:SetSize(4,4); pixel:SetPoint("TOPLEFT",24+column*4,-row*4)
        if row==0 and column<4 then
            local shade=column/3; pixel:SetColorTexture(shade,shade,shade,1)
        else S.metadataCells[#S.metadataCells+1]=pixel end
    end
end
function S.setupValue(fn,index,...)
    if type(fn)~="function" then return nil end
    local values={pcall(fn,...)}
    if values[1]~=true then return nil end
    local value=values[index+1]
    if S.isSecret(value) then return nil end
    return value
end
function S.setupNumber(value)
    if S.isSecret(value) or type(value)~="number" or value~=value then return nil end
    return value
end
function S.setupString(value)
    if S.isSecret(value) or type(value)~="string" then return nil end
    return value
end
function S.jsonValue(value)
    if S.isSecret(value) then return "null" end
    if value==nil then return "null" end
    if type(value)=="boolean" then return value and "true" or "false" end
    if type(value)=="number" then
        if value~=value or value==math.huge or value==-math.huge then return "null" end
        return tostring(value)
    end
    if type(value)~="string" then return "null" end
    return '"'..value:gsub('[%z\1-\31\\"]',function(c)
        if c=='"' then return '\\"' end
        if c=='\\' then return '\\\\' end
        return string.format("\\u%04x",string.byte(c))
    end)..'"'
end
function S.jsonObject(fields)
    local keys={}
    for key in pairs(fields) do keys[#keys+1]=key end
    table.sort(keys)
    local values={}
    for _,key in ipairs(keys) do values[#values+1]=S.jsonValue(key)..":"..S.jsonValue(fields[key]) end
    return "{"..table.concat(values,",").."}"
end
function S.adler32(data)
    local a,b=1,0
    for i=1,#data do a=(a+string.byte(data,i))%65521; b=(b+a)%65521 end
    return b*65536+a
end
function S.bytes(value,count)
    local result={}
    for i=1,count do result[i]=string.char(value%256); value=math.floor(value/256) end
    return table.concat(result)
end
S.setupSession=math.random(0,65535)*65536+math.random(0,65535)
-- Read-only dense transport experiments reuse completed, guarded packets.
-- Producers do not query additional game state or cache data when disabled.
S.transportPackets={}
function S.denseStatePacket(now,tick,unified)
    local core=S.transportPackets[1];local classID=core and string.byte(core.packet,11) or 0
    local ids={1};if classID==1 then ids[#ids+1]=2 elseif classID==7 then ids[#ids+1]=3 end
    for id=16,21 do ids[#ids+1]=id end
    if classID==7 then ids[#ids+1]=4 end -- optional public courtesy recipients
    if unified then ids[#ids+1]=5 end -- slow, cached character/setup page
    local chunks,count={},0
    for _,id in ipairs(ids) do
        local entry=S.transportPackets[id];local age=entry and now and math.floor((now-entry.at)*1000)
        local maxAge=2*S.updateRateMs+100+(id==5 and math.max(250,2*S.updateRateMs) or 0)
        if age and age>=0 and age<=maxAge then
            chunks[#chunks+1]=S.bytes(id,1)..S.bytes(age,2)..S.bytes(#entry.packet,2)..entry.packet;count=count+1
        end
    end
    local payload=table.concat(chunks)
    local packet=(unified and "HHD2" or "HHD1")..S.bytes(S.setupSession,4)..S.bytes(tick,4)..S.bytes(classID,1)..S.bytes(S.updateRateMs,2)..S.bytes(S.auraGeneration,1)..S.bytes(count,1)..S.bytes(#payload,2)..payload
    packet=packet..S.bytes(S.adler32(packet),4);assert(#packet<=(unified and 2304 or 1536),"dense packet capacity exceeded")
    return packet
end
function S.refreshTransportPacketState(now)
    now=now or S.setupNumber(S.readableCall(GetTime))
    for _,bridge in ipairs({ns.pixelExperiment or false,S.denseBridge or false}) do
        if bridge and bridge.enabled and bridge.publishState then
            local ok,err=pcall(bridge.publishState,now)
            if not ok then bridge.errors.state=S.describe(err);bridge.lastStatePacket=nil;bridge.paint(bridge.stateCells,"",24) end
        end
    end
end
function S.publishTransportPacket(id,packet,defer)
    local lab=ns.pixelExperiment;local bridge=S.denseBridge
    local enabled=(lab and lab.enabled) or (bridge and bridge.enabled)
    if not packet then S.transportPackets[id]=nil
    elseif not enabled then return
    else
        local now=S.setupNumber(S.readableCall(GetTime))
        if now and type(packet)=="string" then S.transportPackets[id]={packet=packet,at=now} end
    end
    if bridge and bridge.enabled and bridge.stamp then bridge.stamp(id,packet) end
    if not defer then S.refreshTransportPacketState() end
end
S.setupRevision,S.setupPage,S.setupDirty=0,0,true
S.setupPayload,S.setupPages,S.setupError="",{},nil
S.setupPublishedRevision,S.setupFingerprint=0,nil
S.setupElapsed,S.setupDelay=0,0
ns.markSetupDirty=function()
    if ns.metadataBuilding then return end
    if not S.setupDirty then S.setupRevision=(S.setupRevision+1)%65536; S.setupDelay=0 end
    -- Keep the published page cycle intact while checking for real changes.
    -- The separate core link invalidates and updates live bindings promptly.
    S.setupDirty=true
end
S.setupAbilityKeys={"hunter.autoShot","hunter.arcaneShot","hunter.concussiveShot","hunter.aimedShot","hunter.multiShot","hunter.huntersMark","hunter.serpentSting","hunter.rapidFire","hunter.bestialWrath","hunter.volley","hunter.summonHawk","hunter.raptorStrike","hunter.mongooseBite","hunter.wingClip","hunter.intimidation","hunter.feignDeath","hunter.immolationTrap","hunter.freezingTrap","hunter.frostTrap","hunter.mendPet"}
function S.collectSetup()
    local class=S.setupString(S.setupValue(UnitClass,2,"player"))
    local level=S.setupNumber(S.readableCall(UnitLevel,"player"))
    local specIndex=S.setupNumber(S.readableCall(GetSpecialization))
    if not specIndex and type(C_SpecializationInfo)=="table" then
        specIndex=S.setupNumber(S.readableCall(C_SpecializationInfo.GetSpecialization))
    end
    local specName=specIndex and S.setupString(S.setupValue(GetSpecializationInfo,2,specIndex)) or nil
    if not specName and specIndex and type(C_SpecializationInfo)=="table" then
        specName=S.setupString(S.setupValue(C_SpecializationInfo.GetSpecializationInfo,2,specIndex))
    end
    local character=S.jsonObject({name=S.setupString(S.readableCall(UnitName,"player")),class=class,level=level,spec=specName,scannedAt=S.setupNumber(S.readableCall(GetServerTime))})
    local bindings={}
    for _,mapping in ipairs(S.setupMappings) do
        local id=S.setupNumber(mapping.id)
        if id then
            local key="spell."..id
            if class=="HUNTER" then
                for i,tile in ipairs(S.tiles) do
                    if tile.spellID==id or (mapping.name and tile.spellName==mapping.name) then key=S.setupAbilityKeys[i]; break end
                end
                for _,aspect in ipairs(ns.playerBuffSpecs or {}) do
                    if aspect.spellID==id or (mapping.name and aspect.name==mapping.name) then key=aspect.key; break end
                end
            end
            bindings[#bindings+1]=S.jsonObject({abilityKey=key,id=id,name=S.setupString(mapping.name),
                slot=S.setupNumber(mapping.slot),key=S.setupString(mapping.key),key2=S.setupString(mapping.key2),
                kind=S.setupString(mapping.kind),action=S.setupString(mapping.action)})
        end
    end
    local knownSpells,seen,nativeSpells={},{},{}
    local function addSpell(id,name,key)
        id=S.setupNumber(id)
        if not id or id<=0 or seen[id] then return end
        local known=S.readableCall(S.bookAPI.IsSpellKnown,id)
        if type(known)~="boolean" then known=S.readableCall(IsSpellKnown,id) end
        if known~=true then return end
        seen[id]=true
        local info=S.readableCall(S.spellAPI.GetSpellInfo,id)
        if not key and class=="HUNTER" then
            local spellName=name or S.safeField(info,"name")
            for _,aspect in ipairs(ns.playerBuffSpecs or {}) do
                if spellName==aspect.name then key=aspect.key; break end
            end
        end
        knownSpells[#knownSpells+1]=S.jsonObject({id=id,name=S.setupString(name) or S.setupString(S.safeField(info,"name")),abilityKey=key or ("spell."..id),castTimeMs=S.setupNumber(S.safeField(info,"castTime"))})
        nativeSpells[#nativeSpells+1]={id=id,name=S.setupString(name) or S.setupString(S.safeField(info,"name"))}
    end
    if class=="HUNTER" then
        for i,tile in ipairs(S.tiles) do addSpell(tile.spellID,tile.spellName,S.setupAbilityKeys[i]) end
    end
    local bookLines=S.setupNumber(S.readableCall(S.bookAPI.GetNumSpellBookSkillLines))
    local bank=type(Enum)=="table" and S.safeField(S.safeField(Enum,"SpellBookSpellBank"),"Player") or nil
    local bookAvailable=false
    if bookLines and bookLines>=0 and bookLines<=64 and S.setupNumber(bank) then
        bookAvailable=true
        for line=1,bookLines do
            local info=S.readableCall(S.bookAPI.GetSpellBookSkillLineInfo,line)
            local offset=S.setupNumber(S.safeField(info,"itemIndexOffset"))
            local count=S.setupNumber(S.safeField(info,"numSpellBookItems"))
            if offset and count and count>=0 and count<=1024 then
                for index=1,count do
                    local item=S.readableCall(S.bookAPI.GetSpellBookItemInfo,offset+index,bank)
                    addSpell(S.safeField(item,"spellID"),S.safeField(item,"name"))
                end
            else bookAvailable=false end
        end
    end
    -- Reuse this out-of-combat scan for native aura rank filters, never rescan
    -- the spellbook in the fast observation callback.
    local fingerprint={bookAvailable and "complete" or "partial"}
    for _,spell in ipairs(nativeSpells) do fingerprint[#fingerprint+1]=spell.id..":"..(spell.name or "") end
    fingerprint=table.concat(fingerprint,"|")
    if fingerprint~=S.setupKnownSpellFingerprint then
        S.setupKnownSpellFingerprint=fingerprint;S.setupKnownSpellRevision=(S.setupKnownSpellRevision or 0)+1
    end
    S.setupKnownSpells=nativeSpells;S.setupBookAvailable=bookAvailable
    local talents,trees={},{}
    local talentAvailable=false
    local tabs=S.setupNumber(S.readableCall(GetNumTalentTabs))
    if tabs and tabs>=0 and tabs<=8 and type(GetTalentInfo)=="function" then
        talentAvailable=true
        for tab=1,tabs do
            trees[#trees+1]=S.jsonObject({name=S.setupString(S.setupValue(GetTalentTabInfo,1,tab)),points=S.setupNumber(S.setupValue(GetTalentTabInfo,3,tab))})
            local count=S.setupNumber(S.readableCall(GetNumTalents,tab))
            if count and count<=200 then
                for index=1,count do
                    local rank=S.setupNumber(S.setupValue(GetTalentInfo,5,tab,index))
                    if rank and rank>0 then talents[#talents+1]=S.jsonObject({name=S.setupString(S.setupValue(GetTalentInfo,1,tab,index)),rank=rank,tree=tab}) end
                end
            else talentAvailable=false end
        end
    elseif type(C_ClassTalents)=="table" and type(C_Traits)=="table" then
        local configID=S.setupNumber(S.readableCall(C_ClassTalents.GetActiveConfigID))
        local config=configID and S.readableCall(C_Traits.GetConfigInfo,configID) or nil
        local treeIDs=S.safeField(config,"treeIDs")
        if type(treeIDs)=="table" and not S.isSecret(treeIDs) then
            talentAvailable=true
            for _,treeID in ipairs(treeIDs) do
                treeID=S.setupNumber(treeID)
                local nodes=treeID and S.readableCall(C_Traits.GetTreeNodes,treeID) or nil
                if type(nodes)=="table" and not S.isSecret(nodes) and #nodes<=2000 then
                    for _,nodeID in ipairs(nodes) do
                        nodeID=S.setupNumber(nodeID)
                        local node=nodeID and S.readableCall(C_Traits.GetNodeInfo,configID,nodeID) or nil
                        local rank=S.setupNumber(S.safeField(node,"currentRank"))
                        if rank and rank>0 then
                            local entry=S.safeField(node,"activeEntry")
                            local entryID=S.setupNumber(S.safeField(entry,"entryID"))
                            local entryInfo=entryID and S.readableCall(C_Traits.GetEntryInfo,configID,entryID) or nil
                            local definitionID=S.setupNumber(S.safeField(entryInfo,"definitionID"))
                            local definition=definitionID and S.readableCall(C_Traits.GetDefinitionInfo,definitionID) or nil
                            local spellID=S.setupNumber(S.safeField(definition,"spellID"))
                            local spell=spellID and S.readableCall(S.spellAPI.GetSpellInfo,spellID) or nil
                            talents[#talents+1]=S.jsonObject({id=nodeID,spellID=spellID,name=S.setupString(S.safeField(spell,"name")),rank=rank,tree=treeID})
                        end
                    end
                else talentAvailable=false end
            end
        end
    end
    local petActions={}
    for slot=1,10 do
        local name=S.setupString(S.setupValue(GetPetActionInfo,1,slot))
        local token=S.setupValue(GetPetActionInfo,3,slot)
        if name and token==true then name=S.setupString(_G[name]) or name end
        local bindingOK=type(GetBindingKey)=="function" and pcall(GetBindingKey,"BONUSACTIONBUTTON"..slot)
        petActions[#petActions+1]=S.jsonObject({slot=slot,name=name,
            spellID=S.setupNumber(S.setupValue(GetPetActionInfo,7,slot)),
            key=S.setupString(S.setupValue(GetBindingKey,1,"BONUSACTIONBUTTON"..slot)),
            key2=S.setupString(S.setupValue(GetBindingKey,2,"BONUSACTIONBUTTON"..slot)),bindingAvailable=bindingOK==true})
    end
    return '{"v":1,"character":'..character..',"bindings":['..table.concat(bindings,",")..'],"spells":['..table.concat(knownSpells,",")..'],"talents":['..table.concat(talents,",")..'],"trees":['..table.concat(trees,",")..'],"petActions":['..table.concat(petActions,",")..'],"bookAvailable":'..S.jsonValue(bookAvailable)..',"talentAvailable":'..S.jsonValue(talentAvailable)..'}'
end
function S.refreshSetup()
    if S.readableCall(InCombatLockdown)~=false then return end
    ns.metadataBuilding=true
    local ok,result=pcall(function()
        S.resolveSpells(); S.discoverBindings()
        return S.collectSetup()
    end)
    ns.metadataBuilding=false
    if not ok or type(result)~="string" or #result>65536 then
        S.setupError=ok and "setup payload too large" or S.describe(result)
        S.setupDelay=-1; return
    end
    -- The scan timestamp alone must not restart a multi-page transfer.
    local fingerprint=result:gsub('"scannedAt":%d+','"scannedAt":0')
    if S.setupFingerprint==fingerprint then
        S.setupRevision=S.setupPublishedRevision
        S.setupDirty=false; S.setupError=nil
        return
    end
    S.setupFingerprint=fingerprint; S.setupPublishedRevision=S.setupRevision
    S.setupPayload=result; S.setupPages={}
    for start=1,#result,328 do S.setupPages[#S.setupPages+1]=result:sub(start,start+327) end
    if #S.setupPages==0 then S.setupPages[1]="" end
    S.setupDirty=false; S.setupError=nil; S.setupPage=0
end
function S.setTransportColor(pixel,value)
    if pixel.hhTransportValue==value then return end
    pixel.hhTransportValue=value
    pixel:SetColorTexture(math.floor(value/16)/3,(math.floor(value/4)%4)/3,(value%4)/3,1)
end
function S.renderSetupPage()
    local published=#S.setupPayload>0
    local payload=published and (S.setupPages[S.setupPage+1] or "") or ""
    local count=published and #S.setupPages or 1
    local header="HHM1"..S.bytes(S.setupSession,4)..S.bytes(S.setupPublishedRevision,2)..S.bytes(published and 0 or 1,1)
        ..S.bytes(S.setupPage,2)..S.bytes(count,2)..S.bytes(#payload,2)..S.bytes(#S.setupPayload,4)..S.bytes(S.adler32(S.setupPayload),4)
    local packet=header..payload
    packet=packet..S.bytes(S.adler32(packet),4)
    S.publishTransportPacket(5,packet)
    if not S.denseBridgeActive then
    local buffer,bits,cursor=0,0,1
    for _,pixel in ipairs(S.metadataCells) do
        while bits<6 do buffer=buffer*256+(string.byte(packet,cursor) or 0); cursor=cursor+1; bits=bits+8 end
        local factor=2^(bits-6)
        local value=math.floor(buffer/factor); buffer=buffer%factor; bits=bits-6
        S.setTransportColor(pixel,value)
    end
    end
    if published then S.setupPage=(S.setupPage+1)%count end
end
S.setupEvents=CreateFrame("Frame")
for _,event in ipairs({"PLAYER_LOGIN","PLAYER_ENTERING_WORLD","PLAYER_LEVEL_UP","SPELLS_CHANGED","UPDATE_BINDINGS","UPDATE_MACROS","ACTIONBAR_SLOT_CHANGED","ACTIONBAR_PAGE_CHANGED","PLAYER_TALENT_UPDATE","TRAIT_CONFIG_UPDATED","ACTIVE_TALENT_GROUP_CHANGED","PLAYER_REGEN_ENABLED","PET_BAR_UPDATE","PET_BAR_UPDATE_USABLE","UNIT_PET"}) do
    pcall(S.setupEvents.RegisterEvent,S.setupEvents,event)
end
S.setupEvents:SetScript("OnEvent",ns.markSetupDirty)
S.metadataFrame:SetScript("OnUpdate",function(self,elapsed)
    S.setupElapsed=S.setupElapsed+elapsed
    S.setupDelay=S.setupDelay+elapsed
    if S.setupDirty and S.setupDelay>=0.3 then S.refreshSetup() end
    if S.setupElapsed>=math.max(0.25,S.updateInterval()*2) then S.setupElapsed=0; S.renderSetupPage() end
end)
S.renderSetupPage()
