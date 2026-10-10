-- Public player / pet activity strip.
local _, ns = ...
local S = ns.state

-- Optional live activity strip. Readable booleans only; secrets remain unknown.
do
    local panel=CreateFrame("Frame",nil,S.hud)
    S.activityPanel=panel
    panel:SetPoint("TOPLEFT",S.hud,"TOPLEFT",0,-316); panel:SetSize(668,40)
    S.hud:SetClampRectInsets(0,0,0,-242)
    local bg=panel:CreateTexture(nil,"BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0,0,0,1)
    ns.configureHeaderActivity=function(profile)
        local packed=profile and profile.headerActivity
        if packed then bg:Hide();panel:SetHeight(12) else bg:Show();panel:SetHeight(40) end
        local function point(widget,x,y) widget:ClearAllPoints();widget:SetPoint("TOPLEFT",panel,"TOPLEFT",x,-y) end
        for i,dot in ipairs(S.activityDots or {}) do if packed then point(dot,340+(i-1)*12,4) end end
        if packed then
            for i,dot in ipairs(S.activityMovementMarkers) do point(dot,540+(i-1)*6,4) end
            point(S.activityMovement,552,4)
        end
    end
    for i,color in ipairs({{1,1,0},{0,1,1},{1,0,1}}) do
        local marker=panel:CreateTexture(nil,"OVERLAY"); marker:SetSize(4,4)
        marker:SetPoint("TOPLEFT",4+(i-1)*6,0); marker:SetColorTexture(color[1],color[2],color[3],1)
    end
    local labels={"CAST","CHAN","ALIVE","PCMB","PTGT","SAME","ATK","FOLL","ASST","DEF","PASS","AC4","AC5","AC6","AC7"}
    local dots={}; S.activityDots=dots
    for i,name in ipairs(labels) do
        local label=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    S.bridgeLabel(label)
        label:SetPoint("TOPLEFT",12+(i-1)*44,-8); label:SetText(name)
        local dot=panel:CreateTexture(nil,"OVERLAY"); dot:SetSize(8,8)
        dot:SetPoint("TOPLEFT",12+(i-1)*44,-26); dots[i]=dot; S.drawFlag(dot,nil)
    end
    -- Shared movement survives class layouts that hide the Hunter aura strip.
    S.activityMovement=panel:CreateTexture(nil,"OVERLAY")
    S.activityMovement:SetSize(8,8);S.activityMovement:SetPoint("TOPLEFT",652,-26)
    S.activityMovementMarkers={}
    for i,c in ipairs({{0,1,1},{1,0,1}}) do
        local marker=panel:CreateTexture(nil,"OVERLAY");marker:SetSize(4,4)
        marker:SetPoint("TOPLEFT",640+(i-1)*6,-26);marker:SetColorTexture(unpack(c))
        S.activityMovementMarkers[i]=marker
    end
    local tracking=ns.features.CastTracking
    local castActivity=tracking.newActivityState()
    panel:SetScript("OnEvent",function(self,event,unit,guid,id)
        if event=="PLAYER_ENTERING_WORLD" or event=="PLAYER_DEAD" then tracking.activityEvent(castActivity,event);return end
        if S.isSecret(unit) or unit~="player" then return end
        if tracking.activityEvent(castActivity,event,guid,id) then
            -- Publish START before the next periodic update/receipt packet.
            S.drawFlag(dots[1],castActivity.cast);S.drawFlag(dots[2],castActivity.channel)
        end
    end)
    for _,event in ipairs({"UNIT_SPELLCAST_START","UNIT_SPELLCAST_STOP","UNIT_SPELLCAST_FAILED","UNIT_SPELLCAST_INTERRUPTED","UNIT_SPELLCAST_SUCCEEDED","UNIT_SPELLCAST_CHANNEL_START","UNIT_SPELLCAST_CHANNEL_STOP","PLAYER_ENTERING_WORLD","PLAYER_DEAD"}) do pcall(panel.RegisterEvent,panel,event) end
    local elapsedTotal=0
    panel:SetScript("OnUpdate",function(self,elapsed)
        elapsedTotal=elapsedTotal+elapsed; if elapsedTotal<S.updateInterval() then return end; elapsedTotal=0
        S.drawFlag(dots[1],tracking.activityFlag(castActivity,UnitCastingInfo,"cast")); S.drawFlag(dots[2],tracking.activityFlag(castActivity,UnitChannelInfo,"channel"))
        ns.features.RangeTracking.movement(S.activityMovement)
        local exists=S.readableCall(UnitExists,"pet")
        local dead
        if exists==true then dead=S.readableCall(UnitIsDeadOrGhost,"pet") end
        local alive
        if exists==false then alive=false elseif type(dead)=="boolean" then alive=not dead end
        S.drawFlag(dots[3],alive)
        local petCombat,target
        if exists==true then petCombat=S.readableCall(UnitAffectingCombat,"pet"); target=S.readableCall(UnitExists,"pettarget") end
        S.drawFlag(dots[4],petCombat)
        S.drawFlag(dots[5],target)
        local same
        if target==true and S.readableCall(UnitExists,"target")==true then same=S.readableCall(UnitIsUnit,"pettarget","target")
        elseif target==false then same=false end
        S.drawFlag(dots[6],same)
        for i,slot in ipairs({1,2,8,9,10}) do
            local active
            if exists==true then active=S.setupValue(GetPetActionInfo,4,slot) end
            if type(active)=="number" then active=active==1 end
            S.drawFlag(dots[6+i],active)
        end
        for slot=4,7 do
            local enabled
            if exists==true then enabled=S.setupValue(GetPetActionInfo,6,slot) end
            if type(enabled)=="number" then enabled=enabled==1 end
            S.drawFlag(dots[8+slot],enabled)
        end
    end)
end

