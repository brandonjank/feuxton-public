-- Hunter owns its native atlas; shared code owns framing and public transport.
local _, ns = ...
local H = {
    denseBridgeLayout={key="hunter-slim-v1",gauges=172,units=172,unitHeight=20,activity=14,headerActivity=true,headerTargetAuras=true,resources=172,setup=192,grid=192,roster=192,coreStamp=136,targetStamp=150,guideStamp=156,marker={0.5,1,0.25}},
    nativeLayout={columns=12,x=4,pitch=55,firstRow=32,rowPitch=38,player=112,target=140,filteredTop=18},
}
ns.classes.HUNTER=H

function H.nativeTile(index)
    local L=H.nativeLayout
    return L.x+(index-1)%L.columns*L.pitch,L.firstRow+math.floor((index-1)/L.columns)*L.rowPitch
end

function ns.configureHunterCompact()
    local S,L=ns.state,H.nativeLayout
    local function point(widget,parent,x,y)
        widget:ClearAllPoints();widget:SetPoint("TOPLEFT",parent,"TOPLEFT",x,-y)
    end
    for i,tile in ipairs(S.tiles) do
        local x,y=H.nativeTile(i)
        point(tile,S.hud,x,y);tile:SetSize(L.pitch,L.rowPitch)
        tile.label:Hide();tile.binding:Hide();tile:EnableMouse(false);tile:Show()
        for j,dot in ipairs(tile.visualSignals) do point(dot,tile,29+(j-1)*7,33) end
    end
    point(S.playerPanel,S.hud,0,L.player)
    point(S.auraMirror,S.hud,0,L.target)
end
