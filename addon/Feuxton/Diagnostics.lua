-- Capability inventory, reports and optional client disk logging.
local _, ns = ...
local S = ns.state

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
    local function flag(fn,index,...)
        if type(fn)~="function" then return 0 end
        local args={...}
        local ok,value=pcall(function() return select(index,fn(unpack(args))) end)
        if not ok then return 0 end
        local state=S.capabilityValue(value)
        if state~="readable" then return 0 end
        if value==true or value==1 then return 2 end
        if value==false or value==0 then return 1 end
        return 0
    end
    local range=flag(api.IsSpellInRange or IsSpellInRange,1,api.IsSpellInRange and id or name,unit or "target")
    local usable=flag(api.IsSpellUsable or IsUsableSpell,1,id)
    local power=flag(api.IsSpellUsable or IsUsableSpell,2,id)
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
S.performance = {enabled=false, stages={}}
function S.profileScript(frame, script, name)
    if not frame then return end
    local original=frame:GetScript(script)
    if not original then return end
    frame:SetScript(script,function(...)
        if not S.performance.enabled or type(debugprofilestop)~="function" then return original(...) end
        local start=debugprofilestop()
        local ok,err=pcall(original,...)
        local finish=debugprofilestop()
        if not S.isSecret(start) and not S.isSecret(finish) and type(start)=="number" and type(finish)=="number" and finish>=start then
            local stage=S.performance.stages[name]
            if not stage then stage={samples={},cursor=0,calls=0};S.performance.stages[name]=stage end
            stage.cursor=stage.cursor%120+1;stage.samples[stage.cursor]=finish-start;stage.calls=stage.calls+1
        end
        if not ok then error(err) end
    end)
end
SLASH_FEUXTONPERF1="/feuxtonperf"
SlashCmdList.FEUXTONPERF=function(message)
    message=(message or ""):lower():match("^%s*(.-)%s*$")
    if message=="on" then
        S.performance.stages={};S.performance.enabled=true
        print("Feuxton: profiling ON. /feuxtonperf report shows average / p95 milliseconds per callback (including idle frames).")
    elseif message=="off" then
        S.performance.enabled=false;print("Feuxton: profiling OFF.")
    elseif message=="report" then
        local lines={"Feuxton addon performance · "..(S.performance.enabled and "ON" or "OFF"),"Milliseconds per callback, last 120 samples; includes idle OnUpdate calls."}
        local names={};for name in pairs(S.performance.stages) do names[#names+1]=name end;table.sort(names)
        for _,name in ipairs(names) do
            local stage=S.performance.stages[name];local sorted={};local sum=0
            for _,value in ipairs(stage.samples) do sorted[#sorted+1]=value;sum=sum+value end
            table.sort(sorted)
            lines[#lines+1]=string.format("%s: avg %.3f / p95 %.3f ms (%d samples, %d calls)",name,sum/#sorted,sorted[math.ceil(#sorted*.95)],#sorted,stage.calls)
        end
        if #names==0 then lines[#lines+1]="No samples. Run /feuxtonperf on and play normally first." end
        if type(debugprofilestop)~="function" then lines[#lines+1]="Client profiler clock unavailable." end
        S.edit:SetText(table.concat(lines,"\n"));S.panel:Show();S.edit:SetFocus();S.edit:HighlightText()
    else print("Feuxton: /feuxtonperf on, /feuxtonperf report, /feuxtonperf off.") end
end

