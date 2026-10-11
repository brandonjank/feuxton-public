-- Shared Forever racial catalog. Learned spells, not class bars, own delivery.
local _,ns=...
local R={}
ns.features.Racials=R
R.specs={
 {key="racial.forsaken",name="Will of the Forsaken",race="Scourge"},
 {key="racial.cannibalize",name="Cannibalize"},
 {key="racial.bloodFury",name="Blood Fury"},
 {key="racial.shatterCurse",name="Shatter Curse"},
 {key="racial.warStomp",name="War Stomp"},
 {key="racial.cultivation",name="Cultivation"},
 {key="racial.berserking",name="Berserking"},
 {key="racial.regeneration",name="Rapid Regeneration"},
 {key="racial.walkAir",name="Walk on Air"},
 {key="racial.skysight",name="Skysight"},
 {key="racial.survive",name="Will to Survive"},
 {key="racial.perception",name="Perception"},
 {key="racial.stoneform",name="Stoneform"},
 {key="racial.treasure",name="Find Treasure"},
 {key="racial.elune",name="Elune's Light"},
 {key="racial.shadowmeld",name="Shadowmeld"},
 {key="racial.escape",name="Escape Artist"},
 {key="racial.eureka",name="Eureka!"},
 {key="racial.leyLine",name="Read Ley Line"},
}
function R.learned()
 local S=ns.state;local list={}
 local now=S.readableCall(GetTime)
 if R.cache and type(now)=="number" and now>=R.at and now-R.at<1 then return R.cache end
 for index,spec in ipairs(R.specs) do
  local info=S.readableCall(S.spellAPI.GetSpellInfo,spec.name)
  local id=S.safeField(info,"spellID")
  if type(id)=="number" and id>0 and S.readableCall(S.bookAPI.IsSpellKnown or IsSpellKnown,id)==true and S.readableCall(S.spellAPI.IsSpellPassive or IsPassiveSpell,id)~=true then
   list[#list+1]={index=index,key=spec.key,name=spec.name,id=id,unit="player"}
  end
 end
 if type(now)=="number" then R.cache=list;R.at=now end
 return list
end
local events=CreateFrame("Frame")
events:RegisterEvent("SPELLS_CHANGED");events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent",function()R.cache=nil end)
