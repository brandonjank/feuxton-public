-- Hunter spell catalogue, readable API helpers and update rate.
local _, ns = ...
local S = ns.state

-- Fixed, read-only hunter display. Icons are independent of action-bar layout.
-- Native cooldown widgets render timing directly; Lua never derives ready state
-- from secret cooldown numbers or duration objects.
S.hunterSpecs=ns.spellCatalog.HUNTER.specs
-- A queued melee strike must not toggle itself off when its binding is retried.
for _,spec in ipairs(S.hunterSpecs) do if spec.key=="hunter.raptorStrike" then spec.noToggle=true end end
S.spellAPI = type(C_Spell) == "table" and C_Spell or {}
S.bookAPI = type(C_SpellBook) == "table" and C_SpellBook or {}
function S.isSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end
function S.readableCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok or S.isSecret(value) then return nil end
    return value
end
function S.safeField(object, key)
    if S.isSecret(object) or type(object) ~= "table" then return nil end
    local ok, value = pcall(function() return object[key] end)
    if not ok or S.isSecret(value) then return nil end
    return value
end

S.updateRateMs=100
ns.setUpdateRate=function(value)
    if S.isSecret(value) or (type(value)~="number" and type(value)~="string") then return false end
    local rate=tonumber(value)
    if not rate or rate~=rate or rate<50 or rate>1000 then return false end
    S.updateRateMs=math.floor(rate+0.5)
    if type(FeuxtonDB)~="table" then FeuxtonDB={} end
    FeuxtonDB.updateRateMs=S.updateRateMs
    if ns.refreshRateSettings then ns.refreshRateSettings() end
    return true
end
function S.updateInterval() return S.updateRateMs/1000 end

-- Public configuration; nil follows the desktop preference (default ON).
function S.spellUseCode(key)
    local preferences=type(FeuxtonDB)=="table" and FeuxtonDB.spellUsage
    local value
    if type(preferences)=="table" then value=preferences[key] end
    if value==false then return 1 elseif value==true then return 2 end
    return 0
end
function S.setSpellUse(key,value)
    if type(FeuxtonDB)~="table" then FeuxtonDB={} end
    if type(FeuxtonDB.spellUsage)~="table" then FeuxtonDB.spellUsage={} end
    FeuxtonDB.spellUsage[key]=value
    if S.refreshSpellUse then S.refreshSpellUse() end
end
S.useButtons={}
function S.attachSpellUse(parent,icon,key)
    local button=CreateFrame("Button",nil,parent)
    button:SetAllPoints(icon);button:RegisterForClicks("LeftButtonUp","RightButtonUp")
    local dot=button:CreateTexture(nil,"OVERLAY");dot:SetSize(4,4);dot:SetPoint("TOPLEFT",icon,"TOPRIGHT",0,0)
    button.useKey=key;button.useDot=dot;S.useButtons[#S.useButtons+1]=button
    button:SetScript("OnClick",function(self,mouse)
        if mouse=="RightButton" then S.setSpellUse(key,nil)
        else S.setSpellUse(key,S.spellUseCode(key)==1) end
    end)
    button:SetScript("OnEnter",function(self)
        local enter=parent:GetScript("OnEnter")
        if enter then enter(parent) else
            GameTooltip:SetOwner(self,"ANCHOR_NONE");GameTooltip:SetText(key)
            GameTooltip:ClearAllPoints();GameTooltip:SetPoint("TOPLEFT",S.hud,"TOPLEFT",0,-(S.hud:GetHeight()+8))
        end
        local code=S.spellUseCode(key)
        GameTooltip:AddLine(code==0 and "Default ON; desktop preference controls use." or code==1 and "OFF in addon; overrides desktop." or "ON in addon; overrides desktop.",1,1,1)
        GameTooltip:AddLine("Left click: ON/OFF. Right click: follow desktop.",1,1,1);GameTooltip:Show()
        local top=S.hud:GetTop()*S.hud:GetEffectiveScale()
        local screenTop=UIParent:GetHeight()*UIParent:GetEffectiveScale()
        local height=GameTooltip:GetHeight()*GameTooltip:GetEffectiveScale()
        GameTooltip:ClearAllPoints()
        if screenTop-top>=height+8 then GameTooltip:SetPoint("BOTTOMLEFT",S.hud,"TOPLEFT",0,8)
        else GameTooltip:SetPoint("TOPLEFT",S.hud,"TOPLEFT",0,-(S.hud:GetHeight()+8)) end
    end)
    button:SetScript("OnLeave",function() GameTooltip:Hide() end)
    return button
end
function S.refreshSpellUse()
    for _,button in ipairs(S.useButtons) do
        local code=S.spellUseCode(button.useKey)
        button.useDot:SetColorTexture(code==1 and 1 or 0,code==1 and 0 or 1,code==0 and 1 or 0,1)
    end
end
