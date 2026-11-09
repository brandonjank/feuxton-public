-- HHM1 setup collection, serialization and paged pixel transport.
local _, ns = ...
local S = ns.state

-- HHM1: paged setup metadata only. All exported values are whitelisted,
-- checked for secrets, and collected outside combat. No combat timings,
-- unit aura contents or macro bodies are serialized.
S.metadataFrame=CreateFrame("Frame",nil,S.hud)
S.metadataFrame:SetPoint("TOPLEFT",S.unitHud,"BOTTOMLEFT",0,-4)
S.metadataFrame:SetSize(668,12)
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
    local byte=string.byte
    -- Reduce once per bounded block. With reduced starting sums, 5552 bytes
    -- keep even the worst all-255 intermediate sum within an exact integer.
    for first=1,#data,5552 do
        for i=first,math.min(first+5551,#data) do a=a+byte(data,i);b=b+a end
        a=a%65521;b=b%65521
    end
    return b*65536+a
end
function S.bytes(value,count)
    local result={}
    for i=1,count do result[i]=string.char(value%256); value=math.floor(value/256) end
    return table.concat(result)
end
S.setupSession=math.random(0,65535)*65536+math.random(0,65535)
-- Runtime identity belongs to this Lua load, not the files currently on disk.
-- Parse static metadata once. Publication uses only the existing batch counter;
-- inventory, targets, combat and the slower paged setup cannot hold it up.
local loadedAddonBytes
do
    local major,minor,patch
    if type(ns.version)=="string" and #ns.version<=17 then major,minor,patch=ns.version:match("^(%d+)%.(%d+)%.(%d+)$") end
    major,minor,patch=tonumber(major),tonumber(minor),tonumber(patch)
    local contract=ns.contractRevision
    local function uint16(v)return type(v)=="number" and v>=0 and v<=65535 and v==math.floor(v) end
    if uint16(major) and uint16(minor) and uint16(patch) and uint16(contract) and contract>0 then
        loadedAddonBytes=S.bytes(major,2)..S.bytes(minor,2)..S.bytes(patch,2)..S.bytes(contract,2)
    end
end
function S.loadedAddonPacket(tick)
    if not loadedAddonBytes or type(tick)~="number" or tick<0 or tick>4294967295 or tick~=math.floor(tick) then return nil end
    local packet="HHV1"..S.bytes(S.setupSession,4)..S.bytes(tick,4)..loadedAddonBytes
    return packet..S.bytes(S.adler32(packet),4)
end
-- Completed guarded producer packets feed one current HHD3 envelope.
S.transportPackets={}
local sourceSchemas={[1]="HHF4",[2]="HHG7",[3]="HHPD",[4]="HHB3",[5]="HHM1",[6]="SHS2",[7]="HHT5",[8]="HHE2",[9]="HHI5",[10]="HHX5",[11]="WLS5",[12]="DRS2",[13]="PCS1",[14]="HHV1",[15]="HHJ1"}
local sourceSession=S.setupSession
local sourceSessionBytes=S.bytes(sourceSession,4)
local function packedSource(id,packet,classID)
    local schema=sourceSchemas[id]
    if id>=16 and id<=21 then schema=classID==7 and "HHR8" or classID==2 and "HHR4" or classID==5 and "HHR7" or "HHR1" end
    assert(schema and type(packet)=="string" and #packet>=12 and packet:sub(1,4)==schema and packet:sub(5,8)==sourceSessionBytes,"Invalid current source context")
    -- Schema and session are determined by this checksummed envelope. Keep
    -- the original source checksum so the decoder still validates producer
    -- integrity and native stamp witnesses; never manufacture one on receipt.
    return packet:sub(9)
end
local setupFragmentPayload,setupFragmentTick,setupFragmentOffset,setupFragmentLength=nil,nil,0,0
local function unsignedAt(packet,offset,size)
    local value=0;for i=size-1,0,-1 do value=value*256+packet:byte(offset+i) end;return value
end
local function setupFragmentChunk(entry,tick,budget)
    -- A fragment is still one checksummed HHM1 source. It uses the reserved
    -- flag2/count0 encoding and a byte offset instead of a fixed page index.
    -- Core/party/native observations never yield their budget to this stream.
    local original=entry and entry.packet
    local payload=S.setupPayload
    if budget<27 or type(payload)~="string" or #payload==0 or #payload>65536 or not original or #original<29
        or original:sub(1,4)~="HHM1" or original:byte(11)~=0 or unsignedAt(original,18,4)~=#payload then return nil end
    if payload~=setupFragmentPayload then setupFragmentPayload=payload;setupFragmentTick=nil;setupFragmentOffset=0;setupFragmentLength=0 end
    if setupFragmentTick~=tick then
        if setupFragmentTick~=nil then setupFragmentOffset=(setupFragmentOffset+setupFragmentLength)%#payload end
        setupFragmentTick=tick
    end
    local length=math.min(328,budget-26,#payload-setupFragmentOffset)
    if length<1 then return nil end
    setupFragmentLength=length
    local packet="HHM1"..original:sub(5,10)..S.bytes(2,1)..S.bytes(setupFragmentOffset,2)..S.bytes(0,2)
        ..S.bytes(length,2)..original:sub(18,25)..payload:sub(setupFragmentOffset+1,setupFragmentOffset+length)
    packet=packet..S.bytes(S.adler32(packet),4)
    local body=packedSource(5,packet,0)
    return S.bytes(5,1)..S.bytes(0,2)..S.bytes(#body,2)..body
end
function S.denseStatePacket(now,tick)
    if sourceSession~=S.setupSession then sourceSession=S.setupSession;sourceSessionBytes=S.bytes(sourceSession,4) end
    local core=S.transportPackets[1];local classID=core and string.byte(core.packet,11) or 0
    local ids={1};if classID==1 then ids[#ids+1]=2 elseif classID==7 then ids[#ids+1]=3 elseif classID==2 then ids[#ids+1]=6 elseif classID==4 then ids[#ids+1]=11 elseif classID==5 then ids[#ids+1]=12 end
    for id=16,21 do ids[#ids+1]=id end
    if classID==7 then ids[#ids+1]=4 end -- optional public courtesy recipients
    ids[#ids+1]=5;if classID==7 or classID==2 or classID==5 then ids[#ids+1]=7 end;if classID==7 or classID==2 or classID==1 or classID==4 or classID==5 then ids[#ids+1]=8 end -- setup, recipients and shared enemy cast
    if ns.features.Consumables then
        local ok,packet=pcall(ns.features.Consumables.packet,tick)
        S.transportPackets[9]=ok and {packet=packet,at=now} or nil
        ids[#ids+1]=9
    end
    if ns.features.ControlEffects then
        local ok,packet=pcall(ns.features.ControlEffects.packet,tick)
        S.transportPackets[10]=ok and {packet=packet,at=now} or nil
        ids[#ids+1]=10
    end
    if ns.features.CastTracking and type(ns.features.CastTracking.activityPacket)=="function" then
        local ok,packet=pcall(ns.features.CastTracking.activityPacket)
        S.transportPackets[13]=ok and {packet=packet,at=now} or nil
        ids[#ids+1]=13
    end
    do
        local packet=S.loadedAddonPacket(tick)
        S.transportPackets[14]=packet and {packet=packet,at=now} or nil
        ids[#ids+1]=14
    end
    do
        local ok,packet=pcall(ns.features.CastTracking.feedbackPacket,tick,now)
        S.transportPackets[15]=ok and {packet=packet,at=now} or nil
        ids[#ids+1]=15
    end
    local chunks,count={},0;local setupChunk,courtesyChunk;local liveBytes=23
    for _,id in ipairs(ids) do
        local entry=S.transportPackets[id];local age=entry and now and math.floor((now-entry.at)*1000)
        local maxAge=2*S.updateRateMs+100+(id==5 and math.max(250,2*S.updateRateMs) or 0)
        -- A session transition cannot relabel a cached old producer packet.
        -- Wait for that producer's new packet; missing remains unavailable.
        if age and age>=0 and age<=maxAge and entry.packet:sub(5,8)==sourceSessionBytes then
            local body=packedSource(id,entry.packet,classID)
            local chunk=S.bytes(id,1)..S.bytes(age,2)..S.bytes(#body,2)..body
            if id==5 then setupChunk=chunk
            elseif id==4 then courtesyChunk=chunk
            else chunks[#chunks+1]=chunk;count=count+1;liveBytes=liveBytes+#chunk end
        end
    end
    -- Core, party and shared runtime data always retain their budget. Optional
    -- courtesy recipients take priority over paged setup, but also yield when
    -- maximum party identities would otherwise invalidate the whole frame.
    S.courtesyDeferred=courtesyChunk~=nil and liveBytes+#courtesyChunk>2304
    if courtesyChunk and not S.courtesyDeferred then chunks[#chunks+1]=courtesyChunk;count=count+1;liveBytes=liveBytes+#courtesyChunk end
    -- Full pages retain normal throughput. When optional courtesy recipients
    -- leave too little room, send only the setup bytes that fit. Once every
    -- four completed batches courtesy may yield for one fragment; its absent
    -- observation stays unavailable, never inherited as fresh.
    local selectedSetup=setupChunk
    if setupChunk and liveBytes+#setupChunk>2304 then
        if 2304-liveBytes<27 and courtesyChunk and not S.courtesyDeferred and tick%4==0 then
            chunks[#chunks]=nil;count=count-1;liveBytes=liveBytes-#courtesyChunk;S.courtesyDeferred=true
        end
        selectedSetup=setupFragmentChunk(S.transportPackets[5],tick,2304-liveBytes)
    end
    if selectedSetup then chunks[#chunks+1]=selectedSetup;count=count+1 end
    S.setupPageDeferred=setupChunk~=nil and selectedSetup==nil
    S.setupPageFragmented=selectedSetup~=nil and selectedSetup~=setupChunk
    local payload=table.concat(chunks)
    local packet="HHD3"..S.bytes(S.setupSession,4)..S.bytes(tick,4)..S.bytes(classID,1)..S.bytes(S.updateRateMs,2)..S.bytes(S.auraGeneration,1)..S.bytes(count,1)..S.bytes(#payload,2)..payload
    packet=packet..S.bytes(S.adler32(packet),4);assert(#packet<=2304,"dense packet capacity exceeded: "..#packet)
    return packet
end
function S.refreshTransportPacketState(now)
    if S.packetUpdateActive then return end
    now=now or S.setupNumber(S.readableCall(GetTime))
    local bridge=S.denseBridge
    if bridge and bridge.enabled and bridge.publishState then
        local ok,err=pcall(bridge.publishState,now)
        if not ok then bridge.errors.state=S.describe(err);bridge.lastStatePacket=nil;bridge.paint(bridge.stateCells,"") end
    end
end
function S.publishTransportPacket(id,packet,defer)
    local bridge=S.denseBridge
    local enabled=bridge and bridge.enabled
    if not packet then S.transportPackets[id]=nil
    elseif not enabled then return
    else
        local now=S.setupNumber(S.readableCall(GetTime))
        if now and type(packet)=="string" then S.transportPackets[id]={packet=packet,at=now} end
    end
    if S.packetUpdateActive then
        S.packetUpdateStamps[id]=packet or false
        return
    end
    if bridge and bridge.enabled and bridge.stamp then bridge.stamp(id,packet) end
    if not defer then S.refreshTransportPacketState() end
end
-- The scheduler owns periodic publication. Explicit refreshes outside a batch
-- (login, layout changes and diagnostics) retain their immediate behavior.
function S.beginPacketUpdate()
    assert(not S.packetUpdateActive,"Nested packet update")
    S.packetUpdateActive=true;S.packetUpdateStamps={}
    local bridge=S.denseBridge
    if bridge and bridge.enabled and bridge.stamp then
        for _,id in ipairs({1,2,16,17,18,19,20,21}) do bridge.stamp(id,nil) end
    end
end
function S.endPacketUpdate(ok,reason)
    local stamps=S.packetUpdateStamps or {}
    S.packetUpdateActive=false;S.packetUpdateStamps=nil
    local bridge=S.denseBridge
    if not ok then
        S.transportPackets={}
        if bridge and bridge.enabled then
            bridge.errors.state=reason or "Coordinated update failed";bridge.lastStatePacket=nil
            bridge.paint(bridge.stateCells,"")
        end
        return
    end
    if bridge and bridge.enabled and bridge.stamp then
        for id,packet in pairs(stamps) do bridge.stamp(id,packet or nil) end
    end
    S.refreshTransportPacketState()
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
-- Realm-list records are optional in the in-game environment. Only inspect
-- the existing list; do not request a refresh, select a realm or infer type
-- from a player's PvP flag or current zone.
function S.collectRealmInfo()
    local realm=S.setupString(S.readableCall(GetRealmName))
    if not realm or realm=="" or #realm>80 then return nil,nil end
    local api=type(C_RealmList)=="table" and C_RealmList or nil
    if not api or type(api.GetAvailableCategories)~="function" or type(api.GetRealmsInCategory)~="function" or type(api.GetRealmInfo)~="function" then return realm,nil end
    local categories=S.readableCall(api.GetAvailableCategories)
    if S.isSecret(categories) or type(categories)~="table" or #categories>32 then return realm,nil end
    local found,count,seen=nil,0,{}
    for _,category in ipairs(categories) do
        if S.isSecret(category) then return realm,nil end
        local realms=S.readableCall(api.GetRealmsInCategory,category)
        if S.isSecret(realms) or type(realms)~="table" or #realms>128 then return realm,nil end
        for _,address in ipairs(realms) do
            if S.isSecret(address) or (type(address)~="string" and type(address)~="number") then return realm,nil end
            if not seen[address] then
                seen[address]=true;count=count+1
                if count>512 then return realm,nil end
                local info=S.readableCall(api.GetRealmInfo,address)
                if not S.isSecret(info) and type(info)=="table" then
                    local name=S.setupString(S.setupValue(function() return info.name end,1))
                    if name==realm then
                        if found then return realm,nil end
                        local pvp=S.setupValue(function() return info.isPvP end,1)
                        local rp=S.setupValue(function() return info.isRP end,1)
                        if type(pvp)~="boolean" or type(rp)~="boolean" then return realm,nil end
                        found=pvp and (rp and "RP PvP" or "PvP") or (rp and "RP" or "Normal")
                    end
                end
            end
        end
    end
    return realm,found
end
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
    local realm,serverType=S.collectRealmInfo()
    local character=S.jsonObject({name=S.setupString(S.readableCall(UnitName,"player")),class=class,level=level,spec=specName,realm=realm,serverType=serverType,
        race=S.setupString(S.readableCall(UnitRace,"player")),zone=S.setupString(S.readableCall(GetRealZoneText)) or S.setupString(S.readableCall(GetZoneText)),
        subzone=S.setupString(S.readableCall(GetSubZoneText)),scannedAt=S.setupNumber(S.readableCall(GetServerTime))})
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
    local directHeals={['paladin.holyLight']=true,['paladin.flashLight']=true,['shaman.healingWave']=true,['shaman.lesserHealingWave']=true,['druid.healingTouch']=true,['druid.healingTouchEfficient']=true}
    local function addSpell(id,name,key)
        id=S.setupNumber(id)
        if not id or id<=0 or seen[id] then return end
        local known=S.readableCall(S.bookAPI.IsSpellKnown,id)
        if type(known)~="boolean" then known=S.readableCall(IsSpellKnown,id) end
        if known~=true then return end
        seen[id]=true
        local info=S.readableCall(S.spellAPI.GetSpellInfo,id)
        if not key then
            local spellName=name or S.safeField(info,"name")
            for _,spec in ipairs(ns.classes[class] and ns.classes[class].specs or {}) do
                if spec.name==spellName then key=spec.key;break end
            end
        end
        if not key and class=="HUNTER" then
            local spellName=name or S.safeField(info,"name")
            for _,aspect in ipairs(ns.playerBuffSpecs or {}) do
                if spellName==aspect.name then key=aspect.key; break end
            end
        end
        -- Optional routine-heal estimates. Descriptions are public setup data;
        -- they never delay the fast/native unit observations or emergency heals.
        local description,locale,cost
        if directHeals[key] then
            description=S.setupString(S.readableCall(S.spellAPI.GetSpellDescription or GetSpellDescription,id))
            if description and #description>512 then description=nil end
            if description then
                locale=S.setupString(S.readableCall(GetLocale))
                local tracker=ns.features.CastTracking
                local fraction=tracker and tracker.manaFraction and S.setupNumber(S.readableCall(tracker.manaFraction,id,true))
                if fraction and fraction>=0 and fraction<=200 then cost=fraction/200 end
            end
        end
        knownSpells[#knownSpells+1]=S.jsonObject({id=id,name=S.setupString(name) or S.setupString(S.safeField(info,"name")),abilityKey=key or ("spell."..id),castTimeMs=S.setupNumber(S.safeField(info,"castTime")),description=description,descriptionLocale=locale,manaCostFraction=cost})
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
function S.renderSetupPage()
    local published=#S.setupPayload>0
    local payload=published and (S.setupPages[S.setupPage+1] or "") or ""
    local count=published and #S.setupPages or 1
    local header="HHM1"..S.bytes(S.setupSession,4)..S.bytes(S.setupPublishedRevision,2)..S.bytes(published and 0 or 1,1)
        ..S.bytes(S.setupPage,2)..S.bytes(count,2)..S.bytes(#payload,2)..S.bytes(#S.setupPayload,4)..S.bytes(S.adler32(S.setupPayload),4)
    local packet=header..payload
    packet=packet..S.bytes(S.adler32(packet),4)
    S.publishTransportPacket(5,packet)
    if published then S.setupPage=(S.setupPage+1)%count end
end
S.setupEvents=CreateFrame("Frame")
for _,event in ipairs({"PLAYER_LOGIN","PLAYER_ENTERING_WORLD","PLAYER_LEVEL_UP","ZONE_CHANGED","ZONE_CHANGED_INDOORS","ZONE_CHANGED_NEW_AREA","REALM_LIST_UPDATED","SPELLS_CHANGED","UPDATE_BINDINGS","UPDATE_MACROS","ACTIONBAR_SLOT_CHANGED","ACTIONBAR_PAGE_CHANGED","PLAYER_TALENT_UPDATE","TRAIT_CONFIG_UPDATED","ACTIVE_TALENT_GROUP_CHANGED","PLAYER_REGEN_ENABLED","PET_BAR_UPDATE","PET_BAR_UPDATE_USABLE","UNIT_PET","PLAYER_EQUIPMENT_CHANGED","SPELL_POWER_CHANGED","UNIT_STATS","UNIT_AURA","UNIT_SPELL_HASTE"}) do
    pcall(S.setupEvents.RegisterEvent,S.setupEvents,event)
end
S.setupEvents:SetScript("OnEvent",function(_,event,unit)
    if event=="UNIT_STATS" or event=="UNIT_AURA" or event=="UNIT_SPELL_HASTE" then
        if S.isSecret(unit) or unit~="player" then return end
    end
    ns.markSetupDirty()
end)
S.metadataFrame:SetScript("OnUpdate",function(self,elapsed)
    S.setupElapsed=S.setupElapsed+elapsed
    S.setupDelay=S.setupDelay+elapsed
    if S.setupDirty and S.setupDelay>=0.3 then S.refreshSetup() end
    if S.setupElapsed>=math.max(0.25,S.updateInterval()*2) then S.setupElapsed=0; S.renderSetupPage() end
end)
S.renderSetupPage()
