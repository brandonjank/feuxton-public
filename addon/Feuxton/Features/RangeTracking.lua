-- Native spell colors, independent of the player's action bars. Secret
-- booleans go directly to supported native color APIs, never Lua decisions.
local _, ns = ...
local R={}
ns.features.RangeTracking=R
-- These helpers are for owned solid-color signals only. Factories establish
-- the white base once; live public or restricted colors always reach vertices.
function R.initialize(dot,r,g,b,a)
    dot:SetColorTexture(1,1,1,1)
    dot:SetVertexColor(r,g,b,a)
end
function R.paintColor(dot,r,g,b,a) dot:SetVertexColor(r,g,b,a) end
function R.paintFlag(dot,value)
    if ns.state.isSecret(value) or type(value)~="boolean" then R.paintColor(dot,1,.65,0,1)
    elseif value then R.paintColor(dot,0,1,0,1)
    else R.paintColor(dot,.2,.2,.2,1) end
end
-- Native-client comparison found broad per-update lookup/validation more
-- expensive than these reads. Keep direct guarded calls; a producer may share
-- one explicitly observed raw result locally with its own native pixel.
function R.range(fn,arg,unit)
    return pcall(fn,arg,unit)
end
function R.usability(fn,arg)
    return pcall(fn,arg)
end
function R.observeRange(fn,arg,unit)
    if type(fn)~="function" then return {status="unavailable"},false,nil end
    local ok,value=R.range(fn,arg,unit)
    if not ok then return {status="error"},false,value end
    return ns.features.GroupContext.scalar(value),true,value
end
function R.readRange(fn,arg,unit)
    local observation=R.observeRange(fn,arg,unit)
    return observation
end
function R.readUsability(fn,arg)
    if type(fn)~="function" then return {status="unavailable"},{status="unavailable"} end
    local ok,usable,mana=R.usability(fn,arg)
    if not ok then return {status="error"},{status="error"} end
    local G=ns.features.GroupContext
    return G.scalar(usable),G.scalar(mana)
end
-- Reuse immutable public palette endpoints, never a game observation or the
-- result of evaluating a restricted boolean. Reset if the API is replaced.
local paletteFactory,palette=nil,{}
local function publicColor(r,g,b,a)
    local S=ns.state
    if S.isSecret(r) or S.isSecret(g) or S.isSecret(b) or S.isSecret(a)
        or type(r)~="number" or type(g)~="number" or type(b)~="number" or type(a)~="number"
        or r~=r or g~=g or b~=b or a~=a then
        return CreateColor(r,g,b,a)
    end
    if paletteFactory~=CreateColor then paletteFactory=CreateColor;palette={} end
    local red=palette[r];if not red then red={};palette[r]=red end
    local green=red[g];if not green then green={};red[g]=green end
    local blue=green[b];if not blue then blue={};green[b]=blue end
    local result=blue[a]
    if not result then result=CreateColor(r,g,b,a);blue[a]=result end
    return result
end
local function color(dot,value,yes,no)
    if ns.state.isSecret(value) then
        if type(C_CurveUtil)~="table" or type(C_CurveUtil.EvaluateColorFromBoolean)~="function" or type(CreateColor)~="function" then return false end
        local result=C_CurveUtil.EvaluateColorFromBoolean(value,publicColor(unpack(yes)),publicColor(unpack(no)))
        dot:SetVertexColor(result:GetRGBA());return true
    end
    if type(value)~="boolean" then return false end
    dot:SetVertexColor(unpack(value and yes or no));return true
end
R.paintBoolean=color
-- Movement may also be restricted in combat. Paint the native boolean without
-- testing its value in Lua; the desktop observes the rendered flag.
function R.movement(dot)
    local S=ns.state
    local ok,value=pcall(IsPlayerMoving or function() end)
    if not ok or (not S.isSecret(value) and type(value)~="boolean") then
        local speed=S.readableCall(GetUnitSpeed,"player")
        value=nil
        if type(speed)=="number" then value=speed>0 end
    end
    dot:SetColorTexture(1,1,1,1)
    local painted,result=pcall(color,dot,value,{0,1,0,1},{.2,.2,.2,1})
    if not painted or result~=true then
        dot:SetVertexColor(1,1,1,1)
        dot:SetColorTexture(1,.65,0,1)
        return false
    end
    return true
end
function R.render(signals,id,unit)
    local S=ns.state
    R.paintColor(signals[1],1,.65,0,1);R.paintColor(signals[3],1,.65,0,1)
    if type(id)~="number" or id<=0 then return false,false end
    local api=S.spellAPI or {}
    local rangeOK,usableOK=false,false
    local ok,range=R.range(api.IsSpellInRange or function() end,id,unit or "target")
    if ok then
        local painted,result=pcall(color,signals[1],range,{1,1,1,1},{1,0,0,1})
        rangeOK=painted and result==true
    end
    local ok,usable,mana=R.usability(api.IsSpellUsable or function() end,id)
    if ok then
        local painted,result=pcall(function()
            if S.isSecret(mana) then
                if type(C_CurveUtil)~="table" or type(C_CurveUtil.EvaluateColorFromBoolean)~="function" or type(CreateColor)~="function" then return false end
                local blocked
                if S.isSecret(usable) then blocked=C_CurveUtil.EvaluateColorFromBoolean(usable,publicColor(1,1,1,1),publicColor(.4,.4,.4,1))
                elseif type(usable)=="boolean" then blocked=usable and publicColor(1,1,1,1) or publicColor(.4,.4,.4,1)
                else return false end
                local result=C_CurveUtil.EvaluateColorFromBoolean(mana,publicColor(.5,.5,1,1),blocked)
                signals[3]:SetVertexColor(result:GetRGBA());return true
            end
            if mana==true then signals[3]:SetVertexColor(.5,.5,1,1);return true end
            if mana~=false then return false end
            return color(signals[3],usable,{1,1,1,1},{.4,.4,.4,1})
        end)
        usableOK=painted and result==true
    end
    return rangeOK,usableOK
end

-- Lazy, finite native-client comparison. It never paints gameplay state or
-- changes production sampling. Saved results contain timings/counts only.
do
    local lab
    local warmupCycles,measuredCycles=4,24
    -- Former 0.213 sampler, retained only for the isolated comparison. Its
    -- maps and raw references are never read by production spell updates.
    local legacy={}
    local updateToken,rangeSamples,usabilitySamples
    local function legacyCounter(key)
        local performance=ns.state.performance
        if not performance or not performance.enabled then return end
    end
    function legacy.beginUpdate()
        updateToken={};rangeSamples={};usabilitySamples={};return updateToken
    end
    function legacy.endUpdate()
        updateToken=nil;rangeSamples=nil;usabilitySamples=nil
    end
    local function sampleKey(fn,arg,unit,withUnit)
        local S=ns.state
        if not updateToken or S.isSecret(fn) or type(fn)~="function" or S.isSecret(arg) then return false end
        local kind=type(arg)
        if kind~="number" and kind~="string" then return false end
        if kind=="number" and (arg~=arg or arg==math.huge or arg==-math.huge) then return false end
        if withUnit and (S.isSecret(unit) or type(unit)~="string") then return false end
        return true
    end
    function legacy.range(fn,arg,unit)
        if not sampleKey(fn,arg,unit,true) then return pcall(fn,arg,unit) end
        local spells=rangeSamples[fn];if not spells then spells={};rangeSamples[fn]=spells end
        local units=spells[arg];if not units then units={};spells[arg]=units end
        local sample=units[unit]
        if not sample then legacyCounter("rangeQueries");local ok,value=pcall(fn,arg,unit);sample={ok,value};units[unit]=sample
        else legacyCounter("rangeReused") end
        return sample[1],sample[2]
    end
    function legacy.usability(fn,arg)
        if not sampleKey(fn,arg,nil,false) then return pcall(fn,arg) end
        local spells=usabilitySamples[fn];if not spells then spells={};usabilitySamples[fn]=spells end
        local sample=spells[arg]
        if not sample then legacyCounter("usabilityQueries");local ok,usable,mana=pcall(fn,arg);sample={ok,usable,mana};spells[arg]=sample
        else legacyCounter("usabilityReused") end
        return sample[1],sample[2],sample[3]
    end
    local function publicNumber(value)
        return not ns.state.isSecret(value) and type(value)=="number" and value==value and value~=math.huge and value~=-math.huge
    end
    local function clock()
        if type(debugprofilestop)~="function" then return nil end
        local ok,value=pcall(debugprofilestop)
        if ok and publicNumber(value) then return value end
    end
    local function publicFlag(fn,...)
        if type(fn)~="function" then return 0 end
        local ok,value=pcall(fn,...)
        if not ok or ns.state.isSecret(value) or type(value)~="boolean" then return 0 end
        return value and 2 or 1
    end
    local function stats()
        return {values={},invalidClock=0,errors=0,batches=0,requests=0}
    end
    local function summary(row)
        local values,total,maximum={},0,0
        for _,value in ipairs(row.values) do values[#values+1]=value;total=total+value;maximum=math.max(maximum,value) end
        table.sort(values)
        local count=#values
        return {sampleCount=count,meanMs=count>0 and total/count or 0,
            p50Ms=count>0 and values[math.ceil(count*.5)] or 0,p95Ms=count>0 and values[math.ceil(count*.95)] or 0,
            maximumMs=maximum,totalMs=total,invalidClock=row.invalidClock,errors=row.errors,batches=row.batches,requests=row.requests,
            samples=values}
    end
    local function save()
        if not lab then return end
        local direct,sampled=summary(lab.direct),summary(lab.sampled)
        local orders={};for i,value in ipairs(lab.orders) do orders[i]=value end
        local report={schema=1,samplerRevision=213,status=lab.status,errorCode=lab.errorCode or 0,build=lab.build,interface=lab.interface,
            combat=lab.combat,targetAvailable=lab.targetAvailable,combatAfter=lab.combatAfter or lab.combat,targetAfter=lab.targetAfter or lab.targetAvailable,
            contextChanges=lab.contextChanges or 0,knownSpellCount=lab.knownSpellCount,
            rangeAPI=lab.rangeDescriptor,usabilityAPI=lab.useDescriptor,clockAPI="debugprofilestop",
            rangeUnique=lab.rangeUnique,rangeRequests=lab.rangeRequests,usabilityUnique=lab.useUnique,usabilityRequests=lab.useRequests,
            requestsPerBatch=lab.traceCount,warmupCycles=warmupCycles,measuredCycles=measuredCycles,completedCycles=lab.cycle,
            directQueries=lab.directQueries or 0,sampledQueries=lab.sampledQueries or 0,
            directQueryErrors=lab.directQueryErrors or 0,sampledQueryErrors=lab.sampledQueryErrors or 0,
            direct=direct,sampled=sampled,orders=orders,ratioAvailable=direct.sampleCount>0 and sampled.sampleCount>0 and direct.meanMs>0 and 1 or 0,
            sampledToDirect=direct.meanMs>0 and sampled.meanMs/direct.meanMs or 0}
        if type(FeuxtonDB)~="table" then FeuxtonDB={} end
        FeuxtonDB.readTest=report
        return report
    end
    local function stop(status,code)
        if not lab then return end
        lab.status=status;lab.errorCode=code or 0
        lab.frame:SetScript("OnUpdate",nil);lab.trace=nil
        save()
    end
    local function execute(trace,sampled)
        local failures=0
        for _,request in ipairs(trace) do
            local ok
            if request.kind==1 then
                if sampled then ok=legacy.range(request.fn,request.arg,request.unit)
                else ok=pcall(request.fn,request.arg,request.unit) end
            elseif sampled then ok=legacy.usability(request.fn,request.arg)
            else ok=pcall(request.fn,request.arg) end
            if not ok then failures=failures+1 end
        end
        return failures
    end
    local function batch(trace,sampled,timed)
        -- Reentrant diagnostics must not replace a comparison's private scope.
        if updateToken then return false,0,nil,1 end
        local performance=ns.state.performance
        local enabled=performance and performance.enabled
        if performance then performance.enabled=false end
        local started=timed and clock() or nil
        local scope
        local ok,failures=pcall(function()
            if sampled then scope=legacy.beginUpdate() end
            return execute(trace,sampled)
        end)
        if sampled then legacy.endUpdate(scope) end
        local finished=timed and clock() or nil
        if performance then performance.enabled=enabled end
        if not ok then return false,0,nil,2 end
        local duration
        if started and finished and finished>=started then
            local elapsed=finished-started;if publicNumber(elapsed) then duration=elapsed end
        end
        return true,failures,duration,0
    end
    local function counted(trace,sampled)
        local wrapped,prepared,calls={},{},0
        for _,request in ipairs(trace) do
            local fn=wrapped[request.fn]
            if not fn then
                local original=request.fn
                fn=function(...) calls=calls+1;return original(...) end
                wrapped[original]=fn
            end
            prepared[#prepared+1]={kind=request.kind,fn=fn,arg=request.arg,unit=request.unit}
        end
        local ok,failures,_,code=batch(prepared,sampled,false)
        return ok,calls,failures,code
    end
    local function prepare()
        local S=ns.state;local api=S.spellAPI or {};local book=S.bookAPI or {}
        local rangeFn,useFn=api.IsSpellInRange or IsSpellInRange,api.IsSpellUsable or IsUsableSpell
        if type(rangeFn)~="function" or type(useFn)~="function" then return nil,3 end
        local ok,_,class=pcall(UnitClass,"player")
        if not ok or S.isSecret(class) or type(class)~="string" then return nil,4 end
        local module=ns.classes and ns.classes[class]
        local specs=class=="HUNTER" and S.hunterSpecs or module and module.specs
        if type(specs)~="table" then return nil,4 end
        local spells,seen={},{}
        for _,spec in ipairs(specs) do
            local info=S.readableCall(api.GetSpellInfo,spec.name);local id=S.safeField(info,"spellID")
            local known=publicNumber(id) and id>0 and id==math.floor(id) and S.readableCall(book.IsSpellKnown or IsSpellKnown,id)
            if known==true and not seen[id] then
                spells[#spells+1]={id=id,name=spec.name};seen[id]=true
                if #spells==15 then break end
            end
        end
        if #spells<3 then return nil,5 end
        local targetAvailable=publicFlag(UnitExists,"target")
        if targetAvailable~=2 then return nil,6 end
        local trace={}
        for _,spell in ipairs(spells) do for _,unit in ipairs({"target","player"}) do
            trace[#trace+1]={kind=1,fn=rangeFn,arg=api.IsSpellInRange and spell.id or spell.name,unit=unit}
        end end
        local rangeUnique=#trace;local repeated=math.floor(rangeUnique*.37+.5)
        for i=1,repeated do trace[#trace+1]=trace[i] end
        local rangeRequests=#trace
        for _,spell in ipairs(spells) do trace[#trace+1]={kind=2,fn=useFn,arg=spell.id} end
        for i=1,#spells do trace[#trace+1]=trace[rangeRequests+i] end
        assert(#trace<=80,"Read comparison request bound")
        local build,interface=0,0
        if type(GetBuildInfo)=="function" then
            local valid,_,rawBuild,_,rawInterface=pcall(GetBuildInfo)
            if valid then
                if not S.isSecret(rawBuild) and (type(rawBuild)=="string" or type(rawBuild)=="number") then
                    local number=tonumber(rawBuild);if publicNumber(number) and number>=0 then build=number end
                end
                if publicNumber(rawInterface) and rawInterface>=0 then interface=rawInterface end
            end
        end
        return {trace=trace,traceCount=#trace,knownSpellCount=#spells,rangeUnique=rangeUnique,rangeRequests=rangeRequests,
            useUnique=#spells,useRequests=#spells*2,build=build,interface=interface,combat=publicFlag(UnitAffectingCombat,"player"),targetAvailable=targetAvailable,
            rangeDescriptor=api.IsSpellInRange and "C_Spell.IsSpellInRange" or "IsSpellInRange",
            useDescriptor=api.IsSpellUsable and "C_Spell.IsSpellUsable" or "IsUsableSpell"}
    end
    local function step()
        if not lab or lab.status~=1 then return end
        lab.combatAfter=publicFlag(UnitAffectingCombat,"player");lab.targetAfter=publicFlag(UnitExists,"target")
        if lab.combatAfter~=lab.combat then lab.contextChanges=(lab.contextChanges or 0)+1 end
        if lab.targetAfter~=2 then stop(4,9);return end
        local cycle=lab.cycle+1;local order=cycle%2==1 and {false,true,true,false} or {true,false,false,true}
        local measured=cycle>warmupCycles
        for _,sampled in ipairs(order) do
            local ok,failures,duration,code=batch(lab.trace,sampled,true)
            if not ok then stop(4,code);return end
            local row=sampled and lab.sampled or lab.direct
            row.errors=row.errors+failures
            if measured then
                row.batches=row.batches+1;row.requests=row.requests+lab.traceCount
                if duration then row.values[#row.values+1]=duration else row.invalidClock=row.invalidClock+1 end
            end
            if failures>0 then stop(4,7);return end
        end
        lab.cycle=cycle;lab.orders[#lab.orders+1]=cycle%2==1 and 1 or 2
        if cycle>=warmupCycles+measuredCycles then
            stop(2);print("Feuxton read comparison complete; /feuxtonreadtest report. A later /reload saves the numeric report.")
        else save() end
    end
    local function run()
        if lab and lab.status==1 then stop(3) end
        local ok,prepared,code=pcall(prepare)
        if not ok or not prepared then
            print("Feuxton: read comparison unavailable ("..tostring(ok and code or 8).."). Select a target and use a loaded class with at least three learned spells.")
            return
        end
        local frame=lab and lab.frame or CreateFrame("Frame")
        lab=prepared;lab.frame=frame;lab.status=1;lab.errorCode=0;lab.cycle=0;lab.orders={};lab.direct=stats();lab.sampled=stats();lab.elapsed=0
        local directOK,directCalls,directErrors,directCode=counted(lab.trace,false)
        local sampledOK,sampledCalls,sampledErrors,sampledCode=counted(lab.trace,true)
        lab.directQueries=directCalls;lab.sampledQueries=sampledCalls;lab.directQueryErrors=directErrors;lab.sampledQueryErrors=sampledErrors
        if not directOK or not sampledOK or directErrors>0 or sampledErrors>0 then stop(4,not directOK and directCode or not sampledOK and sampledCode or 7);return end
        save()
        frame:SetScript("OnUpdate",function(_,elapsed)
            if not lab or lab.status~=1 then return end
            lab.elapsed=lab.elapsed+elapsed;if lab.elapsed<.1 then return end;lab.elapsed=0
            local completed=pcall(step)
            if not completed then stop(4,8) end
        end)
        print("Feuxton: read comparison running for 28 bounded cycles; production sampling and casting are unchanged.")
    end
    local function report()
        local result=lab and save() or type(FeuxtonDB)=="table" and FeuxtonDB.readTest
        if type(result)~="table" then print("Feuxton: no read comparison; /feuxtonreadtest run.");return end
        local state=({"Running","Complete","Stopped","Failed"})[result.status] or "Unknown"
        local lines={"Feuxton native read comparison · direct versus former 0.213 sampler",string.format("%s; build %d / interface %d; combat %d to %d / target available %d to %d (0 unknown, 1 no, 2 yes); %d changed-context cycles.",state,result.build,result.interface,result.combat,result.combatAfter,result.targetAvailable,result.targetAfter,result.contextChanges),
            string.format("%d learned spells; range %d unique / %d requests; usability %d unique / %d requests; %d requests per batch.",result.knownSpellCount,result.rangeUnique,result.rangeRequests,result.usabilityUnique,result.usabilityRequests,result.requestsPerBatch),
            string.format("%d/%d cycles; first %d warm-up; ABBA/BAAB alternation; two guarded clocks per batch.",result.completedCycles,result.warmupCycles+result.measuredCycles,result.warmupCycles),
            string.format("Untimed native-call check: direct %d / sampled %d; query failures %d / %d.",result.directQueries,result.sampledQueries,result.directQueryErrors,result.sampledQueryErrors)}
        for _,key in ipairs({"direct","sampled"}) do
            local row=result[key]
            lines[#lines+1]=string.format("%s: mean %.4f / p50 %.4f / p95 %.4f ms; %d samples; %d invalid clocks; %d query errors.",key,row.meanMs,row.p50Ms,row.p95Ms,row.sampleCount,row.invalidClock,row.errors)
        end
        lines[#lines+1]=result.ratioAvailable==1 and string.format("Sampled/direct %.4f; below 1 favors sampling. Error code %d. Counters disabled for both methods.",result.sampledToDirect,result.errorCode) or string.format("Ratio unavailable. Error code %d. Counters disabled for both methods.",result.errorCode)
        lines[#lines+1]="Read-only fixed trace on selected target and player. Public/restricted query values are neither inspected nor saved. This comparison does not measure whole-addon savings."
        local S=ns.state
        if S.edit and S.panel then S.edit:SetText(table.concat(lines,"\n"));S.panel:Show();S.edit:SetFocus();S.edit:HighlightText()
        else print(table.concat(lines,"\n")) end
    end
    if type(SlashCmdList)=="table" then
        SLASH_FEUXTONREADTEST1="/feuxtonreadtest"
        SlashCmdList.FEUXTONREADTEST=function(message)
            message=(message or ""):lower():match("^%s*(.-)%s*$")
            if message=="run" then run()
            elseif message=="report" then report()
            elseif message=="off" then if lab and lab.status==1 then stop(3) end;print("Feuxton read comparison OFF.")
            else print("Feuxton: /feuxtonreadtest run, /feuxtonreadtest report, /feuxtonreadtest off.") end
        end
    end
end
