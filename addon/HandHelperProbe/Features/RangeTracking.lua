-- Native spell colors, independent of the player's action bars. Secret
-- booleans go directly to supported native color APIs, never Lua decisions.
local _, ns = ...
local R={}
ns.features.RangeTracking=R
local function color(dot,value,yes,no)
    if ns.state.isSecret(value) then
        if type(C_CurveUtil)~="table" or type(C_CurveUtil.EvaluateColorFromBoolean)~="function" or type(CreateColor)~="function" then return false end
        local result=C_CurveUtil.EvaluateColorFromBoolean(value,CreateColor(unpack(yes)),CreateColor(unpack(no)))
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
    if type(id)~="number" or id<=0 then return false,false end
    local api=S.spellAPI or {}
    signals[1]:SetColorTexture(1,1,1,1);signals[3]:SetColorTexture(1,1,1,1)
    local rangeOK,usableOK=false,false
    local ok,range=pcall(api.IsSpellInRange or function() end,id,unit or "target")
    if ok then
        local painted,result=pcall(color,signals[1],range,{1,1,1,1},{1,0,0,1})
        rangeOK=painted and result==true
    end
    local ok,usable,mana=pcall(api.IsSpellUsable or function() end,id)
    if ok then
        local painted,result=pcall(function()
            if S.isSecret(mana) then
                if type(C_CurveUtil)~="table" or type(C_CurveUtil.EvaluateColorFromBoolean)~="function" or type(CreateColor)~="function" then return false end
                local blocked
                if S.isSecret(usable) then blocked=C_CurveUtil.EvaluateColorFromBoolean(usable,CreateColor(1,1,1,1),CreateColor(.4,.4,.4,1))
                elseif type(usable)=="boolean" then blocked=usable and CreateColor(1,1,1,1) or CreateColor(.4,.4,.4,1)
                else return false end
                local result=C_CurveUtil.EvaluateColorFromBoolean(mana,CreateColor(.5,.5,1,1),blocked)
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
