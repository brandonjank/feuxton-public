-- Shaman elemental slots. Readable values are transported; protected presence
-- and icons go directly to native textures. No totem is cast by this module.
local _,ns=...
local T={slots={}}
ns.features.Totems=T
function T.initialize(parent)
    if T.panel then return end
    local panel=CreateFrame("Frame",nil,parent);panel:SetSize(228,20);panel:SetPoint("TOPLEFT",0,-144);T.panel=panel
    T.combat=panel:CreateTexture(nil,"OVERLAY");T.combat:SetSize(4,4);T.combat:SetPoint("TOPLEFT",220,-4)
    for slot=1,4 do
        local active=panel:CreateTexture(nil,"OVERLAY");active:SetSize(4,4);active:SetPoint("TOPLEFT",12+(slot-1)*50,-4)
        local icon=panel:CreateTexture(nil,"ARTWORK");icon:SetSize(16,16);icon:SetPoint("TOPLEFT",18+(slot-1)*50,0)
        T.slots[slot]={active=active,icon=icon}
    end
end
function T.observe(specs)
    local S=ns.state;local G=ns.features.GroupContext;local bytes=""
    for slot=1,4 do
        local tile=T.slots[slot];local available,name,start,duration,icon,modRate,spellID
        local ok=pcall(function() available,name,start,duration,icon,modRate,spellID=GetTotemInfo(slot) end)
        -- haveTotem means the elemental tool/slot is available, not that a
        -- summoned totem occupies it. Never paint that flag as presence.
        local active
        local state,id,remaining=0,0,4294967295
        if ok then
            if not S.isSecret(name) and type(name)=="string" then
                active=name~=""
                for _,spec in ipairs(specs) do if spec.element==slot and spec.name==name then
                    local spell=S.readableCall(S.spellAPI.GetSpellInfo,spec.name);id=S.safeField(spell,"spellID") or 0;break
                end end
            end
            if not S.isSecret(spellID) and type(spellID)=="number" and spellID>0 and spellID<16777216 and spellID==math.floor(spellID) then id=spellID end
            local now=S.readableCall(GetTime)
            if not S.isSecret(start) and not S.isSecret(duration) and type(start)=="number" and type(duration)=="number" and type(now)=="number" and start>=0 and start<=now+1 and duration>=0 and duration<=86400 then
                remaining=math.min(86400000,math.max(0,math.floor((start+duration-now)*1000)))
                if active==nil then active=remaining>0 end
            end
            if active~=nil then state=active and 2 or 1 end
        end
        tile.active:SetColorTexture(1,1,1,1)
        local rendered,value=pcall(function()
            if active~=nil then return ns.features.RangeTracking.paintBoolean(tile.active,active,{0,1,0,1},{.2,.2,.2,1}) end
            -- Restricted lifetime data stays native. No comparison, negation
            -- or serialization of the duration object's secret expiry flag.
            if not ok or type(GetTotemDuration)~="function" then return false end
            local timer=GetTotemDuration(slot)
            if S.isSecret(timer) then return false end
            -- This client's successful query returns nil for an empty own
            -- slot, and a duration object for a summon (verified in combat).
            -- Missing APIs and failed queries still take the unknown path.
            if timer==nil then return ns.features.RangeTracking.paintBoolean(tile.active,false,{0,1,0,1},{.2,.2,.2,1}) end
            return ns.features.RangeTracking.paintBoolean(tile.active,timer:HasExpired(),{.2,.2,.2,1},{0,1,0,1})
        end)
        if not ok or not rendered or value~=true then tile.active:SetVertexColor(1,1,1,1);tile.active:SetColorTexture(1,.65,0,1) end
        if ok then pcall(tile.icon.SetTexture,tile.icon,icon) else tile.icon:SetTexture(nil) end
        bytes=bytes..S.bytes(state,1)..S.bytes(id,4)..S.bytes(remaining,4)
    end
    return bytes
end
