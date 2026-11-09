-- Shared presentation primitives. Field declarations and publication ownership
-- stay with their producers; this module never reads or retains game state.
local _, ns = ...
local S = ns.state
local R = {}
ns.rendering = R

-- Cache only public serialized bytes/colors, separately for each destination.
-- A failed native write leaves the color/block uncommitted and retains the
-- attempted extent so a later short/blank publication clears partial output.
function R.paintRGB(state,cells,packet,detail)
    local used=math.ceil(#packet/3)
    assert(used<=#cells,"dense paint capacity exceeded")
    local limit=math.max(used,state.extent or 0)
    state.extent=limit
    local visits,writes,skipped=0,0,0
    local setterMs,controlMs,setterSamples,controlSamples=0,0,0,0
    for first=1,limit,16 do
        local index=math.floor((first-1)/16)+1
        local chunk=string.sub(packet,(first-1)*3+1,(first+15)*3)
        if state.blocks[index]==chunk then skipped=skipped+1
        else
            state.blocks[index]=nil
            for i=first,math.min(first+15,limit) do
                visits=visits+1
                local at=(i-1)*3+1;local r,g,b=string.byte(packet,at,at+2)
                r,g,b=r or 0,g or 0,b or 0
                local value=r*65536+g*256+b
                if state.colors[i]~=value then
                    state.colors[i]=nil
                    if detail then
                        local before=S.profileClock()
                        cells[i]:SetVertexColor(r/255,g/255,b/255,1)
                        local after=S.profileClock()
                        local controlBefore=S.profileClock()
                        local controlAfter=S.profileClock()
                        if before and after and after>=before then setterMs=setterMs+after-before;setterSamples=setterSamples+1 end
                        if controlBefore and controlAfter and controlAfter>=controlBefore then controlMs=controlMs+controlAfter-controlBefore;controlSamples=controlSamples+1 end
                    else cells[i]:SetVertexColor(r/255,g/255,b/255,1) end
                    state.colors[i]=value;writes=writes+1
                end
            end
            state.blocks[index]=chunk
        end
    end
    state.extent=used
    -- Only a fully completed paint contributes diagnostic timing.
    if detail then
        detail.updates=detail.updates+1;detail.writes=detail.writes+writes
        detail.setterMs=detail.setterMs+setterMs;detail.controlMs=detail.controlMs+controlMs
        detail.setterSamples=detail.setterSamples+setterSamples;detail.controlSamples=detail.controlSamples+controlSamples
    end
    return used,visits,writes,skipped
end

function R.clearText(text) pcall(text.SetText,text,"") end

function R.numberFont(parent,x,y,width,height)
    local text=parent:CreateFontString(nil,"OVERLAY")
    text:SetPoint("TOPLEFT",x,-y);text:SetSize(width,height)
    text:SetFont("Fonts\\ARIALN.TTF",14,"MONOCHROME")
    text:SetJustifyH("LEFT");text:SetJustifyV("TOP");text:SetTextColor(1,1,1,1)
    text:SetShadowOffset(0,0);text:SetShadowColor(0,0,0,0)
    return text
end

function R.numberFormatter(format)
    assert(type(C_StringUtil)=="table" and type(C_StringUtil.CreateNumericRuleFormatter)=="function","Native number formatter unavailable")
    local formatter=C_StringUtil.CreateNumericRuleFormatter();formatter:SetBreakpoints({{threshold=0,format=format}});return formatter
end

-- Restricted scalars flow directly from the native getter to the font setter.
-- Only guarded public numbers may be inspected or represented in RGB metadata.
function R.nativeNumber(text,getter,unit,exists,powerType)
    R.clearText(text)
    if not exists or type(getter)~="function" then return {status=0,value=0},false end
    local ok,value
    if powerType~=nil then ok,value=pcall(getter,unit,powerType) else ok,value=pcall(getter,unit) end
    if not ok then return {status=3,value=0},false end
    local status,numeric
    if S.isSecret(value) then status=2
    elseif value==nil then return {status=0,value=0},false
    elseif type(value)=="number" and value>=0 and value<=4294967295 and value==math.floor(value) then numeric=value;status=1
    else return {status=3,value=0},false end
    local accepted=pcall(text.SetFormattedText,text,"%d",value)
    if not accepted then R.clearText(text) end
    return {status=status,value=numeric or 0},accepted
end

function R.nativeTimer(text,getter,unit,allowed)
    R.clearText(text)
    if not allowed or type(getter)~="function" then return {status=0,value=0},false end
    local ok,duration=pcall(getter,unit)
    if not ok then return {status=3,value=0},false end
    if not S.isSecret(duration) and duration==nil then return {status=0,value=0},false end
    local obtained,value=pcall(function()return duration:GetRemainingDuration()end)
    if not obtained then return {status=3,value=0},false end
    local status,numeric
    if S.isSecret(value) then status=2
    elseif type(value)=="number" and value>=0 and value<=86400 and value==value then
        status=1;numeric=math.floor(tonumber(string.format("%.1f",value))*10+.5)
    elseif value==nil then return {status=0,value=0},false
    else return {status=3,value=0},false end
    local accepted=pcall(text.SetFormattedText,text,"%.1f",value)
    if not accepted then R.clearText(text) end
    return {status=status,value=numeric or 0},accepted
end
