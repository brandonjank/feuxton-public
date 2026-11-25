-- Capability inventory, reports and optional client disk logging.
local _, ns = ...
local S = ns.state

-- Fixed read-only client diagnostics, sampled by the existing out-of-combat
-- setup scan. No settings setters, chat commands, or extra update loop.
function S.collectClientPerformance()
    local function number(value,maximum)
        value=S.setupNumber(value)
        return value and value>=0 and value<=maximum and value or nil
    end
    local function text(value,maximum)
        value=S.setupString(value)
        return value and #value<=maximum and not value:find("[%z\1-\31\127]") and value or nil
    end
    local report={v=1,at=number(S.readableCall(GetServerTime),9007199254740991),fps=number(S.readableCall(GetFramerate),10000)}
    local cvars={};local read=S.safeField(C_CVar,"GetCVar") or GetCVar
    for _,key in ipairs({"useMaxFPS","maxFPS","useMaxFPSBk","maxFPSBk","gxVSync","scriptProfile","gxApi","graphicsQuality","graphicsViewDistance","graphicsEnvironmentDetail","graphicsGroundClutter","graphicsShadowQuality","RenderScale","gxAdapter","RAIDsettingsEnabled","useTargetFPS","targetFPS"})do
        cvars[key]=text(S.readableCall(read,key),128)
    end
    local top="null";local profiler=C_AddOnProfiler
    local enabled=S.readableCall(S.safeField(profiler,"IsEnabled"))
    if type(enabled)=="boolean"then report.profilerEnabled=enabled end
    local metric=number(S.safeField(S.safeField(Enum,"AddOnProfilerMetric"),"RecentAverageTime"),100)
    if enabled==true and metric then
        report.allAddonsMs=number(S.readableCall(S.safeField(profiler,"GetOverallMetric"),metric),60000)
        report.applicationMs=number(S.readableCall(S.safeField(profiler,"GetApplicationMetric"),metric),60000)
        report.feuxtonMs=number(S.readableCall(S.safeField(profiler,"GetAddOnMetric"),"Feuxton",metric),60000)
        local rows=S.readableCall(S.safeField(profiler,"GetTopKAddOnsForMetric"),metric,5)
        if type(rows)=="table"and not S.isSecret(rows)and #rows<=5 then
            local values,seen={},{};local complete=true
            for _,row in ipairs(rows)do
                local name=text(S.safeField(row,"addOnName"),80)
                local cost=number(S.safeField(row,"metricValue"),60000)
                if not name or name==""or not cost or seen[name]then complete=false;break end
                seen[name]=true;values[#values+1]=S.jsonObject({name=name,ms=cost})
            end
            if complete then top="["..table.concat(values,",").."]"end
        end
    end
    local value=S.jsonObject(report)
    value=value:sub(1,-2)..',"cvars":'..S.jsonObject(cvars)..',"topAddons":'..top..'}'
    return #value<=4096 and value or nil
end

-- Do not compare, stringify, or export restricted values.
function S.describe(value)
    if type(issecretvalue) == "function" and issecretvalue(value) then
        return "restricted"
    end
    local kind = type(value)
    if kind == "nil" then return "nil" end
    if kind == "boolean" or kind == "number" or kind == "string" then
        return tostring(value)
    end
    return kind
end

function S.query(fn, ...)
    if type(fn) ~= "function" then return "API missing" end
    local ok, value = pcall(fn, ...)
    if not ok then return "query failed: " .. S.describe(value) end
    return S.describe(value)
end

function S.fieldQuery(fn, field, ...)
    if type(fn) ~= "function" then return "API missing" end
    local ok, result = pcall(fn, ...)
    if not ok then return "query failed: " .. S.describe(result) end
    if type(issecretvalue) == "function" and issecretvalue(result) then
        return "restricted"
    end
    if type(result) ~= "table" then return S.describe(result) end
    local fieldOK, value = pcall(function() return result[field] end)
    if not fieldOK then return "field inaccessible: " .. S.describe(value) end
    return S.describe(value)
end

S.spells = {
    "Hunter's Mark", "Auto Shot", "Serpent Sting", "Arcane Shot",
    "Multi-Shot", "Aimed Shot", "Rapid Fire", "Bestial Wrath", "Volley",
    "Summon Hawk", "Raptor Strike", "Mongoose Bite", "Wing Clip", "Intimidation",
    "Feign Death", "Immolation Trap", "Freezing Trap", "Frost Trap",
}

function S.inspectNameplate(add)
    local api = type(C_NamePlate) == "table" and C_NamePlate or {}
    if type(api.GetNamePlateForUnit) ~= "function" then
        add("Nameplate lookup", "API missing")
        return
    end
    -- Use a real nameplate unit token and guard the target-match result.
    local plate, token
    for index = 1, 40 do
        local candidate = "nameplate" .. index
        if S.query(UnitIsUnit, candidate, "target") == "true" then
            local ok, result = pcall(api.GetNamePlateForUnit, candidate)
            if not ok then
                add("Nameplate lookup", "query failed: " .. S.describe(result))
                return
            end
            if S.describe(result) == "restricted" then
                add("Nameplate lookup", "restricted")
                return
            end
            plate, token = result, candidate
            break
        end
    end
    add("Target nameplate token", S.describe(token))
    if not plate then
        add("Target nameplate", "not found; enable enemy nameplates and keep target in view")
        return
    end
    if S.query(plate.IsForbidden, plate) == "true" then
        add("Target nameplate", "forbidden")
        return
    end
    -- All frame reads are caught by the outer diagnostic pcall. Never mutate
    -- Blizzard frames or derive decisions from secret fields.
    local unitFrame = plate.UnitFrame
    if S.describe(unitFrame) == "restricted" then
        add("Nameplate UnitFrame", "restricted")
        return
    end
    add("Nameplate UnitFrame", S.describe(unitFrame))
    if not unitFrame then return end
    if S.query(unitFrame.IsForbidden, unitFrame) == "true" then
        add("Nameplate UnitFrame", "forbidden")
        return
    end
    add("Nameplate unit field", S.describe(unitFrame.unit))
    local auraAPI = type(C_UnitAuras) == "table" and C_UnitAuras or {}
    add("Nameplate-token debuff 1 ID", S.fieldQuery(auraAPI.GetAuraDataByIndex,
        "spellId", token, 1, "HARMFUL"))

    local visited, count = {}, 0
    local function walk(frame, path, depth)
        if S.describe(frame) == "restricted" then
            add(path, "restricted")
            return
        end
        if not frame or visited[frame] or count >= 24 then return end
        visited[frame] = true
        count = count + 1
        if S.query(frame.IsForbidden, frame) == "true" then
            add(path, "forbidden")
            return
        end
        add(path .. " visible", S.query(frame.IsVisible, frame))
        for _, field in ipairs({ "spellID", "spellId", "auraInstanceID" }) do
            add(path .. " " .. field, S.describe(frame[field]))
        end
        local icon = frame.Icon
        if S.describe(icon) == "nil" then icon = frame.icon end
        if S.describe(icon) == "restricted" then
            add(path .. " icon", "restricted")
        elseif icon then
            add(path .. " icon texture", S.query(icon.GetTexture, icon))
        end
        local cooldown = frame.Cooldown
        if S.describe(cooldown) == "nil" then cooldown = frame.cooldown end
        if S.describe(cooldown) == "restricted" then
            add(path .. " cooldown", "restricted")
        elseif cooldown and type(cooldown.GetCooldownTimes) == "function" then
            add(path .. " cooldown start", S.query(cooldown.GetCooldownTimes, cooldown))
            add(path .. " cooldown duration", S.query(function()
                local start, duration = cooldown:GetCooldownTimes()
                return duration
            end))
        end
        if depth >= 3 or type(frame.GetChildren) ~= "function" then return end
        local children = { frame:GetChildren() }
        for index, child in ipairs(children) do
            walk(child, path .. ".child" .. index, depth + 1)
        end
    end
    for _, field in ipairs({ "AurasFrame", "BuffFrame" }) do
        add("Nameplate " .. field, S.describe(unitFrame[field]))
        walk(unitFrame[field], field, 0)
    end
    add("Nameplate widgets inspected", tostring(count))
end

-- Capability inventory is diagnostic only. Never copy a secret value into the
-- report or SavedVariables, and never treat an empty result as an absent aura.
function S.capabilityValue(value)
    if type(issecretvalue) ~= "function" then return "unverified", "secret detection API missing" end
    local ok, secret = pcall(issecretvalue, value)
    if not ok then return "error", "secret check failed" end
    if secret then return "restricted", nil end
    local kind = type(value)
    if kind == "nil" then return "empty", nil end
    if kind == "boolean" or kind == "number" or kind == "string" then
        return "readable", value
    end
    return "opaque", kind
end

function S.buildCapabilityInventory()
    local snapshot = { version=1, rows={}, counts={} }
    local function record(label, fn, field, resultIndex, ...)
        local state, value
        if type(fn) ~= "function" then state="unavailable"; value="API missing"
        else
            local args={...}
            local ok, result=pcall(function()
                local result=select(resultIndex or 1, fn(unpack(args)))
                local state=S.capabilityValue(result)
                if state=="restricted" or state=="unverified" or state=="error" then return result end
                if field and type(result)=="table" then return result[field] end
                return result
            end)
            if not ok then state="error"; value="query or field access failed"
            else state,value=S.capabilityValue(result) end
        end
        snapshot.rows[#snapshot.rows+1]={key=label,state=state,value=value}
        snapshot.counts[state]=(snapshot.counts[state] or 0)+1
        return state,value
    end
    local _,combat=record("Context.combatLockdown",InCombatLockdown)
    snapshot.mode=type(combat)=="boolean" and (combat and "combat" or "outside") or "unknown"
    local _,timestamp=record("Context.serverTime",GetServerTime)
    snapshot.timestamp=type(timestamp)=="number" and timestamp or nil
    local _,client=record("Context.client",GetBuildInfo)
    snapshot.client=client
    local _,build=record("Context.build",GetBuildInfo,nil,2)
    snapshot.build=build
    record("Context.interface",GetBuildInfo,nil,4)
    record("Player.movingSpeed",GetUnitSpeed,nil,1,"player")
    record("Player.autoShotActive",IsCurrentSpell,nil,1,75)
    for _,unit in ipairs({"player","target","targettarget","pet","pettarget"}) do
        record(unit..".exists",UnitExists,nil,1,unit)
        record(unit..".dead",UnitIsDeadOrGhost,nil,1,unit)
        record(unit..".combat",UnitAffectingCombat,nil,1,unit)
        record(unit..".health",UnitHealth,nil,1,unit)
        record(unit..".maxHealth",UnitHealthMax,nil,1,unit)
        record(unit..".power",UnitPower,nil,1,unit)
        record(unit..".maxPower",UnitPowerMax,nil,1,unit)
        record(unit..".name",UnitName,nil,1,unit)
    end
    record("Target.attackable",UnitCanAttack,nil,1,"player","target")
    record("Target.isSelf",UnitIsUnit,nil,1,"target","player")
    record("Pet.targetMatches",UnitIsUnit,nil,1,"pettarget","target")
    for slot=1,12 do
        local prefix="Action["..slot.."]."
        record(prefix.."type",GetActionInfo,nil,1,slot)
        record(prefix.."range",IsActionInRange,nil,1,slot,"target")
        record(prefix.."usable",IsUsableAction,nil,1,slot)
        record(prefix.."insufficientPower",IsUsableAction,nil,2,slot)
        record(prefix.."cooldownStart",GetActionCooldown,nil,1,slot)
        record(prefix.."cooldownDuration",GetActionCooldown,nil,2,slot)
        record(prefix.."binding",GetBindingKey,nil,1,"ACTIONBUTTON"..slot)
    end
    for slot=1,10 do
        local prefix="PetAction["..slot.."]."
        record(prefix.."name",GetPetActionInfo,nil,1,slot)
        record(prefix.."active",GetPetActionInfo,nil,4,slot)
        record(prefix.."autocast",GetPetActionInfo,nil,6,slot)
        record(prefix.."binding",GetBindingKey,nil,1,"BONUSACTIONBUTTON"..slot)
    end
    for _,unit in ipairs({"player","target"}) do
        for _,cast in ipairs({{name="cast",fn=UnitCastingInfo},{name="channel",fn=UnitChannelInfo}}) do
            for _,field in ipairs({{name="name",index=1},{name="startTime",index=4},{name="endTime",index=5}}) do
                record(unit.."."..cast.name.."."..field.name,cast.fn,nil,field.index,unit)
            end
        end
    end
    local spellAPI=type(C_Spell)=="table" and C_Spell or {}
    local names={}
    record("target.guid",UnitGUID,nil,1,"target")
    record("player.targetThreat",UnitThreatSituation,nil,1,"player","target")
    for slot=1,4 do
        for _,field in ipairs({{name="present",index=1},{name="name",index=2},{name="start",index=3},{name="duration",index=4}}) do
            record("summonSlot["..slot.."]."..field.name,GetTotemInfo,nil,field.index,slot)
        end
    end
    for _,name in ipairs(S.spells) do names[#names+1]=name end
    for _,name in ipairs({"Disengage","Aspect of the Hawk","Aspect of the Monkey","Aspect of the Cheetah"}) do names[#names+1]=name end
    for _,name in ipairs(names) do
        local state,id=record(name..".spellID",spellAPI.GetSpellInfo,"spellID",1,name)
        if state=="readable" and type(id)=="number" then
            record(name..".castTime",spellAPI.GetSpellInfo,"castTime",1,id)
            record(name..".range",spellAPI.IsSpellInRange or IsSpellInRange,nil,1,spellAPI.IsSpellInRange and id or name,"target")
            record(name..".usable",spellAPI.IsSpellUsable or IsUsableSpell,nil,1,id)
            record(name..".insufficientPower",spellAPI.IsSpellUsable or IsUsableSpell,nil,2,id)
            for _,field in ipairs({"startTime","duration","isEnabled","modRate"}) do
                record(name..".cooldown."..field,spellAPI.GetSpellCooldown,field,1,id)
            end
        end
    end
    local auraAPI=type(C_UnitAuras)=="table" and C_UnitAuras or {}
    for _,unit in ipairs({"player","target"}) do
        for _,filter in ipairs({"HELPFUL","HARMFUL"}) do
            for index=1,5 do
                for _,field in ipairs({"spellId","name","duration","expirationTime","applications","sourceUnit"}) do
                    record(unit.."."..filter.."["..index.."]."..field,auraAPI.GetAuraDataByIndex,field,1,unit,index,filter)
                end
            end
        end
    end
    return snapshot
end
ns.buildCapabilityInventory=S.buildCapabilityInventory

function S.capabilitySummary(snapshot)
    local items={}
    for _,state in ipairs({"readable","restricted","empty","unavailable","error","opaque","unverified"}) do
        items[#items+1]=state.."="..(snapshot.counts[state] or 0)
    end
    return table.concat(items,", ")
end

function S.appendCapabilities(lines, snapshot)
    lines[#lines+1]="\nDirect Lua API inventory: "..snapshot.mode.." ("..S.capabilitySummary(snapshot)..")"
    for _,row in ipairs(snapshot.rows) do
        lines[#lines+1]=row.key..": ["..row.state.."]"..(row.value~=nil and " "..tostring(row.value) or "")
    end
    lines[#lines+1]="Empty = readable call with nil result; NOT proof of aura absence. Errors are isolated per field."
    lines[#lines+1]="This is diagnostic evidence only; the live reader still uses its existing sources."
end

function S.captureCapabilities()
    local snapshot=S.buildCapabilityInventory()
    if type(FeuxtonDB)~="table" then FeuxtonDB={} end
    if type(FeuxtonDB.capabilities)~="table" then FeuxtonDB.capabilities={} end
    -- Only retain the most recent snapshot for each mode, not an event history.
    FeuxtonDB.capabilities[snapshot.mode]=snapshot
    return snapshot
end

function S.compareCapabilities()
    local saved=type(FeuxtonDB)=="table" and FeuxtonDB.capabilities or nil
    local lines={"Feuxton direct API comparison 0.3.0"}
    if type(saved)~="table" or not saved.outside or not saved.combat then
        lines[#lines+1]="Run /feuxtonprobe once outside combat and once in combat, then /feuxtonprobe compare."
        return table.concat(lines,"\n")
    end
    for _,mode in ipairs({"outside","combat"}) do
        local snapshot=saved[mode]
        lines[#lines+1]=mode..": client "..tostring(snapshot.client)..", build "..tostring(snapshot.build)..", server time "..tostring(snapshot.timestamp)
        lines[#lines+1]=S.capabilitySummary(snapshot)
    end
    if saved.outside.build~=saved.combat.build then lines[#lines+1]="WARNING: snapshots are from different builds; capture both again." end
    local outside={}
    for _,row in ipairs(saved.outside.rows) do outside[row.key]=row end
    lines[#lines+1]="\nField | outside -> combat (status only; values naturally change)"
    for _,row in ipairs(saved.combat.rows) do
        local previous=outside[row.key]
        lines[#lines+1]=row.key.." | "..(previous and previous.state or "not sampled").." -> "..row.state
        outside[row.key]=nil
    end
    for key,row in pairs(outside) do lines[#lines+1]=key.." | "..row.state.." -> not sampled" end
    lines[#lines+1]="Readable is specific to these samples, not a guarantee in every combat situation. Empty does not establish aura absence."
    return table.concat(lines,"\n")
end
ns.compareCapabilities=S.compareCapabilities

-- Three independent two-bit flags: 0 unknown, 1 false, 2 true.
-- A restricted return never makes it into the transport. Do not infer a flag
-- from cooldowns, auras, another return value, or an unlearned spell ID.
function S.directSpellFlags(name,id,known,unit)
    if known~=true or type(id)~="number" then return 0 end
    local api=type(C_Spell)=="table" and C_Spell or {}
    local function flag(ok,value)
        if not ok then return 0 end
        local state=S.capabilityValue(value)
        if state~="readable" then return 0 end
        if value==true or value==1 then return 2 end
        if value==false or value==0 then return 1 end
        return 0
    end
    local R=ns.features.RangeTracking
    local rangeOK,rangeValue=R.range(api.IsSpellInRange or IsSpellInRange,api.IsSpellInRange and id or name,unit or "target")
    local usableOK,usableValue,powerValue=R.usability(api.IsSpellUsable or IsUsableSpell,id)
    local range=flag(rangeOK,rangeValue)
    local usable=flag(usableOK,usableValue)
    local power=flag(usableOK,powerValue)
    return range+usable*4+power*16
end
ns.directSpellFlags=S.directSpellFlags

function S.report()
    local lines = { "Feuxton capability report 0.3.0" }
    local snapshot=S.captureCapabilities()
    local function add(label, value)
        lines[#lines + 1] = label .. ": " .. value
    end
    if type(GetBuildInfo) == "function" then
        local ok, version, build, date, interface = pcall(GetBuildInfo)
        if ok then
            add("Client", S.describe(version))
            add("Build", S.describe(build))
            add("Interface", S.describe(interface))
        else
            add("Build info", "query failed")
        end
    end
    add("Secret-value detection", type(issecretvalue))
    add("In combat", S.query(InCombatLockdown))
    add("Target exists", S.query(UnitExists, "target"))
    add("Target dead", S.query(UnitIsDeadOrGhost, "target"))
    add("Target is self", S.query(UnitIsUnit, "target", "player"))
    add("Target attackable", S.query(UnitCanAttack, "player", "target"))
    add("Pet exists", S.query(UnitExists, "pet"))
    add("Player power", S.query(UnitPower, "player"))
    add("Native disk logging", S.query(LoggingCombat))
    add("Legacy combat-log reader", type(CombatLogGetCurrentEventInfo))
    add("Combat log restricted", type(C_CombatLog)=="table" and S.query(C_CombatLog.IsCombatLogRestricted) or "API missing")
    local spellAPI = type(C_Spell) == "table" and C_Spell or {}
    for _, spell in ipairs(S.spells) do
        add(spell .. " ID", S.fieldQuery(spellAPI.GetSpellInfo, "spellID", spell))
        add(spell .. " CD start", S.fieldQuery(spellAPI.GetSpellCooldown, "startTime", spell))
        add(spell .. " CD duration", S.fieldQuery(spellAPI.GetSpellCooldown, "duration", spell))
    end
    local auraAPI = type(C_UnitAuras) == "table" and C_UnitAuras or {}
    -- Inspect several slots, without deciding whether restricted auras are present.
    for index = 1, 5 do
        add("Debuff " .. index .. " spell ID",
            S.fieldQuery(auraAPI.GetAuraDataByIndex, "spellId", "target", index, "HARMFUL"))
        add("Debuff " .. index .. " name",
            S.fieldQuery(auraAPI.GetAuraDataByIndex, "name", "target", index, "HARMFUL"))
    end
    local plateOK, plateError = pcall(S.inspectNameplate, add)
    if not plateOK then
        add("Nameplate inspection error", S.describe(plateError))
    end
    if ns.hudReport then
        local ok=pcall(ns.hudReport,add)
        if not ok then add("HUD inspection", "query failed") end
    end
    local diagnostic=type(FeuxtonDB)=="table" and not S.isSecret(FeuxtonDB) and S.safeField(FeuxtonDB,"nativeSignalsDiagnostic") or nil
    if type(diagnostic)=="table" then
        local count=S.safeField(diagnostic,"count");local lastError=S.safeField(diagnostic,"lastError")
        if type(count)=="number" and count>=0 and count<=4294967295 and count==math.floor(count) then add("Native signals failure count",S.describe(count)) end
        if type(lastError)=="string" then add("Native signals last failure",lastError:sub(1,256)) end
    end
    S.appendCapabilities(lines,snapshot)
    lines[#lines + 1] = "Spell names above assume an English client. nil may mean no aura or uncached spell."
    lines[#lines + 1] = "Run outside and inside combat with Mark/Sting active; this is a snapshot."
    return table.concat(lines, "\n")
end

-- Request the client's own disk logger. This does not read protected events
-- or alter combat-log filtering, advanced logging, or other client settings.
SLASH_FEUXTONLOG1="/feuxtonlog"
SlashCmdList.FEUXTONLOG=function(message)
    message=(message or ""):lower():match("^%s*(.-)%s*$")
    if type(LoggingCombat)~="function" then print("Feuxton: native disk logging API missing; try /combatlog."); return end
    if message=="start" or message=="stop" then
        local ok,err=pcall(LoggingCombat,message=="start")
        if not ok then print("Feuxton: disk logging request failed: "..S.describe(err)); return end
    elseif message~="" and message~="status" then
        print("Feuxton: /feuxtonlog start, /feuxtonlog stop, /feuxtonlog status"); return
    end
    print("Feuxton: native disk logging = "..S.query(LoggingCombat)..". Files are in the client's Logs folder.")
end

-- Opt-in profiling uses only the client's public monotonic profiler clock.
-- Bounded storage; disabled profiling does not call the clock or allocate samples.
S.performance = {enabled=false, detail=false, stages={},paint={updates=0,visits=0,writes=0,skippedBlocks=0}}
-- Profiler clocks are diagnostic only. Missing, restricted or failing clocks
-- must never prevent the actual pixel write or become a zero-cost sample.
function S.profileClock()
    if type(debugprofilestop)~="function" then return nil end
    local ok,value=pcall(debugprofilestop)
    if not ok or S.isSecret(value) or type(value)~="number" or value~=value or value==math.huge or value==-math.huge then return nil end
    return value
end
-- One bounded recorder for ordinary callbacks and externally timed scopes.
local function recordProfile(name,elapsed)
    local stage=S.performance.stages[name]
    if not stage then stage={samples={},cursor=0,calls=0,totalMs=0,peakMs=0};S.performance.stages[name]=stage end
    stage.cursor=stage.cursor%120+1;stage.samples[stage.cursor]=elapsed;stage.calls=stage.calls+1
    stage.totalMs=(stage.totalMs or 0)+elapsed;stage.peakMs=math.max(stage.peakMs or 0,elapsed)
end
function S.profileElapsed(name,elapsed)
    if not S.performance.enabled or S.isSecret(name) or type(name)~="string" or #name<1 or #name>64
        or name:find("[^A-Za-z0-9 ()_%-]") or not name:match("^[A-Za-z]")
        or S.isSecret(elapsed) or type(elapsed)~="number" or elapsed~=elapsed or elapsed<0 or elapsed==math.huge then return false end
    recordProfile(name,elapsed)
    return true
end
local function profileResults(...) return {n=select("#",...),...} end
function S.profileFunction(original,name)
    return function(...)
        if not S.performance.enabled or type(debugprofilestop)~="function" then return original(...) end
        local start=S.profileClock()
        local results=profileResults(pcall(original,...))
        local finish=S.profileClock()
        if start and finish and finish>=start then
            recordProfile(name,finish-start)
        end
        if not results[1] then error(results[2],0) end
        return unpack(results,2,results.n)
    end
end
function S.profileScript(frame, script, name)
    if not frame then return end
    local original=frame:GetScript(script)
    if original then frame:SetScript(script,S.profileFunction(original,name)) end
end
local function startProfile(at,detail)
    local p=S.performance
    p.stages={};p.enabled=true;p.started=at;p.stopped=nil;p.detail=detail
    p.paint={updates=0,visits=0,writes=0,skippedBlocks=0}
    p.paintDetail={updates=0,writes=0,setterSamples=0,controlSamples=0,setterMs=0,controlMs=0}
end
local function stopProfile(at)
    S.performance.stopped=at;S.performance.enabled=false;S.performance.detail=false
end
local function profileNames()
    local names={}
    for name in pairs(S.performance.stages)do names[#names+1]=name end
    table.sort(names)
    return names
end
local function profileStatistics(stage)
    local sorted,sum={},0
    for _,value in ipairs(stage.samples)do sorted[#sorted+1]=value;sum=sum+value end
    table.sort(sorted)
    return #sorted,sum,sorted[math.ceil(#sorted*.95)]
end

-- The two fixed diagnostic actions never claim keys used by gameplay or
-- control a locally started profile. A remote run ends even if the app exits.
local remote={run=0,duration=180}
local controls={
    {family="addonperf.start",name="FeuxtonAddonProfilerStart",field="startBinding"},
    {family="addonperf.stop",name="FeuxtonAddonProfilerStop",field="stopBinding"},
}
local diagnosticKeys={}
for digit=0,9 do diagnosticKeys[#diagnosticKeys+1]="ALT-CTRL-SHIFT-"..digit end
local diagnosticBindingPools={diagnosticKeys}
local function finite(value,max)
    return type(value)=="number" and value>=0 and value<=max
end
local function profileTime()
    local at=S.readableCall(GetTime)
    if finite(at,9007199254740991)then return at end
end
local function profileDate()
    local at=S.readableCall(GetServerTime)
    if finite(at,253402300799) and at>=1 and at==math.floor(at)then return at end
end
local function metric(value)
    if finite(value,1000000)then return math.floor(value*1000+.5)/1000 end
end
local function completeRemoteProfile(at)
    if not remote.running then return end
    remote.running=false
    stopProfile(at)
    local completedAt=profileDate()
    local elapsed=finite(at,9007199254740991) and at-S.performance.started
    if completedAt and finite(elapsed,3600)then
        local rows={}
        local stages,names=S.performance.stages,profileNames()
        if #names>24 then
            table.sort(names,function(a,b)
                local left,right=stages[a].totalMs,stages[b].totalMs
                if left==right then return a<b end
                return left>right
            end)
        end
        -- Keep the inclusive parent and its six diagnostic children together.
        -- Other rows retain their existing cost order and the 24-row wire cap.
        if #names>24 and stages["paladin other preview work"] then
            local selected,seen={},{}
            for _,name in ipairs({"paladin preview","paladin spell API reads","paladin binding validation","paladin records and checksums","paladin other preview work","paladin native render helpers","paladin aura filters"}) do
                if stages[name] then selected[#selected+1]=name;seen[name]=true end
            end
            for _,name in ipairs(names) do if not seen[name] then selected[#selected+1]=name end end
            names=selected
        end
        for _,name in ipairs(names)do
            if #rows>=24 then break end
            local stage=stages[name]
            local samples,sum,p95=profileStatistics(stage)
            local mean,peak=metric(sum/samples),metric(stage.peakMs)
            p95=metric(p95)
            local rate=metric(elapsed>0 and stage.totalMs/elapsed or nil)
            if #name<=64 and name:match("^[ -~]+$") and stage.calls<=4294967295 and mean and p95 and peak and rate then
                rows[#rows+1]=S.jsonObject({name=name,calls=stage.calls,samples=samples,meanMs=mean,p95Ms=p95,maxMs=peak,cpuMsPerSecond=rate})
            end
        end
        local report=S.jsonObject({elapsedMs=math.floor(elapsed*1000+.5)})
        report=report:sub(1,-2)..',"rows":['..table.concat(rows,",")..']'
        local p=S.performance.paint
        if p.updates>0 and p.updates<=4294967295 then
            local cells,writes,unchanged=metric(p.visits/p.updates),metric(p.writes/p.updates),metric(p.skippedBlocks/p.updates)
            if cells and writes and unchanged then
                report=report..',"paint":'..S.jsonObject({frames=p.updates,cellsPerFrame=cells,writesPerFrame=writes,unchangedPerFrame=unchanged})
            end
        end
        remote.report=report..'}';remote.completedAt=completedAt
    end
    if ns.markSetupDirty then ns.markSetupDirty()end
end
local function clearFocus(api,...)
    if type(api)~="function" then return false end
    local ok,value=pcall(api,...)
    return ok and not S.isSecret(value) and value==nil
end
local function profileControlSafe()
    if S.readableCall(InCombatLockdown)~=false or S.readableCall(UnitAffectingCombat,"player")~=false or
        S.readableCall(UnitIsDeadOrGhost,"player")~=false or S.readableCall(UnitOnTaxi,"player")~=false or
        S.readableCall(GetUnitSpeed,"player")~=0 or not clearFocus(GetCurrentKeyBoardFocus) or
        not clearFocus(UnitCastingInfo,"player") or not clearFocus(UnitChannelInfo,"player") then return false end
    local c=ns.features.Consumables
    if not c or c.restPauseRequested or c.lootState()~=false then return false end
    local eating,drinking=c.recovery()
    return eating==false and drinking==false
end
local function runProfileControl(control,start)
    if start and S.performance.enabled or not start and not remote.running then return end
    local managed=S.managedSpells
    if not managed or not managed.auxiliaryCurrent(control.family,control.name,control.key) or not profileControlSafe()then return end
    local at=profileTime()
    if not at then return end
    if not start then completeRemoteProfile(at);return end
    if not profileDate() or not S.profileClock() then return end
    local after=S.safeField(C_Timer,"After")
    if type(after)~="function"then return end
    local run=remote.run%4294967295+1
    local scheduled,result=pcall(after,remote.duration,function()
        if remote.running and remote.run==run then completeRemoteProfile(profileTime())end
    end)
    if not scheduled or S.isSecret(result) or result==false then return end
    remote.run=run;remote.running=true;remote.report=nil;remote.completedAt=nil
    startProfile(at,false)
    if ns.markSetupDirty then ns.markSetupDirty()end
end
function S.collectAddonProfiler()
    if type(debugprofilestop)~="function" or type(S.safeField(C_Timer,"After"))~="function" then return end
    local managed=S.managedSpells
    if not managed then return end
    local phase=remote.running and "running" or S.performance.enabled and "local" or remote.run>0 and "complete" or "idle"
    local fields={schemaVersion=1,run=remote.run,phase=phase}
    if phase=="complete"then fields.completedAtUnixSeconds=remote.completedAt end
    if S.readableCall(InCombatLockdown)==false then
        for index,control in ipairs(controls)do
            if not control.button then
                local button=CreateFrame("Button",control.name,UIParent)
                button:SetSize(1,1);button:SetPoint("TOPLEFT",UIParent,"TOPLEFT",-10000,10000);button:SetAlpha(0)
                button:RegisterForClicks("AnyDown")
                local start=index==1
                button:SetScript("OnClick",function()runProfileControl(control,start)end)
                control.button=button
            end
            if not managed.auxiliaryCurrent(control.family,control.name,control.key) then
                control.key=managed.claimAuxiliaryBinding(control.family,control.name,diagnosticBindingPools)
            end
            fields[control.field]=control.key
        end
    end
    local result=S.jsonObject(fields)
    if phase=="complete" and remote.report then result=result:sub(1,-2)..',"report":'..remote.report..'}'end
    return result
end
SLASH_FEUXTONPERF1="/feuxtonperf"
SlashCmdList.FEUXTONPERF=function(message)
    message=(message or ""):lower():match("^%s*(.-)%s*$")
    if message=="on" or message=="detail" then
        local at=S.readableCall(GetTime)
        completeRemoteProfile(at)
        startProfile(at,message=="detail")
        if ns.markSetupDirty then ns.markSetupDirty()end
        print(S.performance.detail and "Feuxton: detail profiling ON. Extra clock reads perturb timing; /feuxtonperf report shows setter and clock-control totals." or "Feuxton: profiling ON. /feuxtonperf report shows due-update and event costs; nested totals include their children.")
    elseif message=="off" then
        local at=S.readableCall(GetTime)
        if remote.running then completeRemoteProfile(at)else stopProfile(at)end
        if ns.markSetupDirty then ns.markSetupDirty()end
        print("Feuxton: profiling OFF.")
    elseif message=="report" then
        local lines={"Feuxton addon performance · "..(S.performance.enabled and "ON" or "OFF"),"Milliseconds per callback, last 120 samples. Coordinated total includes producers, assembly and painting; assembly includes support/consumables."}
        local now=S.performance.enabled and S.readableCall(GetTime) or S.performance.stopped
        local elapsed=type(now)=="number" and type(S.performance.started)=="number" and now-S.performance.started or 0
        lines[#lines+1]="Measured callback CPU ms/s is elapsed-window cost, not percent of all addon CPU. Deferred client/GPU rendering is excluded; native API call time is included."
        local names=profileNames()
        for _,name in ipairs(names) do
            local stage=S.performance.stages[name]
            local samples,sum,p95=profileStatistics(stage)
            lines[#lines+1]=string.format("%s: avg %.3f / p95 %.3f ms (%d samples, %d calls)",name,sum/samples,p95,samples,stage.calls)
            if elapsed>0 then lines[#lines+1]=string.format("  window %.1fs: %.3f CPU ms/s; peak %.3f ms",elapsed,(stage.totalMs or sum)/elapsed,stage.peakMs or 0) end
        end
        local paint=S.performance.paint
        if paint and paint.updates>0 then
            lines[#lines+1]=string.format("RGB work per successful paint: %.1f cells decoded; %.1f color writes; %.1f unchanged blocks skipped (%d paints).",paint.visits/paint.updates,paint.writes/paint.updates,paint.skippedBlocks/paint.updates,paint.updates)
        end
        local detail=S.performance.paintDetail
        if detail and detail.updates>0 then
            local function timing(label,total,samples)
                if samples==0 then return string.format("%s: unavailable (0/%d writes timed)",label,detail.writes) end
                if elapsed>0 then return string.format("%s: %.3f CPU ms/s (%d/%d writes timed)",label,total/elapsed,samples,detail.writes) end
                return string.format("%s: %.3f ms total (%d/%d writes timed)",label,total,samples,detail.writes)
            end
            lines[#lines+1]=timing("RGB native setter",detail.setterMs,detail.setterSamples)
            lines[#lines+1]=timing("RGB adjacent two-clock control",detail.controlMs,detail.controlSamples)
            lines[#lines+1]="Detail adds four guarded clock reads per changed color and perturbs total time; do not compare this total directly with normal mode. Setter/control subtraction is only approximate, not pure scan CPU."
        end
        if #names==0 then lines[#lines+1]="No samples. Run /feuxtonperf on and play normally first." end
        if type(debugprofilestop)~="function" then lines[#lines+1]="Client profiler clock unavailable." end
        S.edit:SetText(table.concat(lines,"\n"));S.panel:Show();S.edit:SetFocus();S.edit:HighlightText()
    else print("Feuxton: /feuxtonperf on, /feuxtonperf detail, /feuxtonperf report, /feuxtonperf off.") end
end


-- Diagnostic presentation is independent of the telemetry publisher.
S.panel = CreateFrame("Frame", nil, UIParent)
S.panel:SetSize(700, 560)
S.panel:SetPoint("CENTER")
S.panel:SetFrameStrata("DIALOG")
S.panel:Hide()
S.background = S.panel:CreateTexture(nil, "BACKGROUND")
S.background:SetAllPoints()
S.background:SetColorTexture(0.04, 0.04, 0.04, 0.98)
S.title = S.panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
S.title:SetPoint("TOPLEFT", 16, -16)
S.title:SetText("Feuxton — select text and press Ctrl+C")
S.close = CreateFrame("Button", nil, S.panel, "UIPanelCloseButton")
S.close:SetPoint("TOPRIGHT", -4, -4)
S.scroll = CreateFrame("ScrollFrame", nil, S.panel, "UIPanelScrollFrameTemplate")
S.scroll:SetPoint("TOPLEFT", 16, -48)
S.scroll:SetPoint("BOTTOMRIGHT", -36, 16)
S.edit = CreateFrame("EditBox", nil, S.scroll)
S.edit:SetMultiLine(true)
S.edit:SetAutoFocus(false)
S.edit:SetFontObject(ChatFontNormal)
S.edit:SetWidth(630)
S.edit:SetHeight(1400)
S.edit:SetScript("OnEscapePressed", function() S.panel:Hide() end)
S.edit:SetScript("OnTextChanged", function() S.scroll:UpdateScrollChildRect() end)
S.scroll:SetScrollChild(S.edit)

ns.report = S.report
SLASH_FEUXTONPROBE1 = "/feuxtonprobe"
SlashCmdList.FEUXTONPROBE = function(message)
    message=(message or ""):lower():match("^%s*(.-)%s*$")
    if message=="capture" then
        local ok,snapshot=pcall(S.captureCapabilities)
        if ok then print("Feuxton: saved "..snapshot.mode.." API snapshot ("..S.capabilitySummary(snapshot)..").")
        else print("Feuxton: API snapshot failed: "..S.describe(snapshot)) end
        return
    elseif message~="" and message~="compare" then
        print("Feuxton: /feuxtonprobe, /feuxtonprobe capture (no popup), /feuxtonprobe compare")
        return
    end
    local ok,text=pcall(message=="compare" and S.compareCapabilities or S.report)
    if not ok then print("Feuxton: capability report failed: "..S.describe(text)); return end
    S.edit:SetText(text)
    S.panel:Show()
    S.edit:SetFocus()
    S.edit:HighlightText()
end


function S.recordNativeSignalError(state,reason,visible)
    local restricted=S.isSecret(reason)
    if not restricted and reason==nil then if visible then ns.rendering.clearText(state.errorText) end;return end
    local message="Native signals error unavailable"
    if not restricted and type(reason)=="string" then
        message=reason:gsub("[%z\1-\31\127]"," ")
        message=message:match("([^/\\]+%.lua:%d+:.*)") or message
        message=message:sub(1,256)
        if message=="" then message="Native signals error unavailable" end
    end
    if visible then state.lastError=message;pcall(state.errorText.SetText,state.errorText,"Signals: "..message:sub(1,110))
    else state.lastAuraError=message end
    -- Only public bounded error text and a counter persist. No timing,
    -- spell/aura value, object or secret reason is stored here.
    if S.isSecret(FeuxtonDB) then return end
    if type(FeuxtonDB)=="nil" then FeuxtonDB={} elseif type(FeuxtonDB)~="table" then return end
    local previous=not S.isSecret(FeuxtonDB.nativeSignalsDiagnostic) and FeuxtonDB.nativeSignalsDiagnostic or nil
    local count=type(previous)=="table" and previous.count or nil
    if S.isSecret(count) or type(count)~="number" or count<0 or count>4294967295 or count~=math.floor(count) then count=0 end
    FeuxtonDB.nativeSignalsDiagnostic={lastError=message,count=math.min(4294967295,(count or 0)+1)}
end
