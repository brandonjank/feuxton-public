-- Shared recipient selectors and public confirmation. No ordinary Lua targets
-- or casts; native secure buttons are activated only by hardware input.
local _,ns=...
local T={revision=0,entries={},reserved={}}
ns.features.RecipientTargeting=T
T.units={"player","party1","party2","party3","party4","focus","mouseover","lasttarget","clear"}
T.commands={"TARGETSELF","TARGETPARTYMEMBER1","TARGETPARTYMEMBER2","TARGETPARTYMEMBER3","TARGETPARTYMEMBER4","TARGETFOCUS","TARGETMOUSEOVER","TARGETLASTTARGET"}
local function action(key,override) return ns.state.readableCall(GetBindingAction,key,override) end
function T.current(e)
 return e and e.key and not ns.keyPolicy.reason(e.key) and ns.state.compactBindingCode(e.key)>0
  and action(e.key,true)==e.action and (e.existing or action(e.key,false)=="")
end
function T.refresh()
 local S=ns.state
 if S.readableCall(InCombatLockdown)~=false or not S.managedSpells.available() then return end
 local now=S.readableCall(GetTime)
 if type(now)~="number" or T.nextScan and now<T.nextScan then return end
 T.nextScan=now+1
 if not T.owner then
  T.owner=CreateFrame("Frame",nil,UIParent);T.owner:RegisterEvent("UPDATE_BINDINGS")
  T.owner:SetScript("OnEvent",function() T.nextScan=nil end)
 end
 local signature={}
 for i,unit in ipairs(T.units) do
  local e=T.entries[i]
  local existing
  local command=T.commands[i]
  if command and type(GetBindingKey)=="function" then
   local ok,a,b=pcall(GetBindingKey,command)
   if ok then for _,key in ipairs({a or false,b or false}) do
    if type(key)=="string" and not ns.keyPolicy.reason(key) and S.compactBindingCode(key)>0 and action(key,true)==command then existing=key;break end
   end end
  end
  if existing then
   if not e or e.key~=existing or not e.existing then
    if e and e.owner then ClearOverrideBindings(e.owner) end
    e={key=existing,action=command,existing=true};T.entries[i]=e
   end
  elseif not T.current(e) or e.existing then
   e=e and not e.existing and e or {};e.key=nil;e.existing=false
   if e.owner then ClearOverrideBindings(e.owner) else e.owner=CreateFrame("Frame",nil,UIParent) end
   if not e.button then
    e.name="FeuxtonRecipient"..i;e.action="CLICK "..e.name..":LeftButton"
    e.button=CreateFrame("Button",e.name,UIParent,"SecureActionButtonTemplate")
    e.button:SetSize(1,1);e.button:SetPoint("TOPLEFT",UIParent,"TOPLEFT",-10000,10000);e.button:SetAlpha(0)
    e.button:RegisterForClicks("AnyDown","AnyUp");e.button:SetAttribute("useOnKeyDown",true)
    e.button:SetAttribute("checkselfcast",false);e.button:SetAttribute("checkfocuscast",false);e.button:SetAttribute("checkmouseovercast",false)
    if i<=7 then e.button:SetAttribute("type","target");e.button:SetAttribute("unit",unit)
    else e.button:SetAttribute("type","macro");e.button:SetAttribute("macrotext",i==8 and "/targetlasttarget" or "/cleartarget") end
   end
   for n=0,19 do local key=n<10 and "CTRL-SHIFT-NUMPAD"..n or "ALT-CTRL-"..(n-10)
    if not T.reserved[key] and not ns.keyPolicy.reason(key) and action(key,false)=="" and action(key,true)=="" then
     local ok=pcall(SetOverrideBindingClick,e.owner,false,key,e.name,"LeftButton")
     T.reserved[key]=true
     if ok and action(key,true)==e.action then e.key=key;break end
    end
   end
   T.entries[i]=e
  end
  signature[i]=T.current(e) and e.key..":"..e.action or ""
 end
 local value=table.concat(signature,"|")
 if value~=T.signature then T.signature=value;T.revision=(T.revision+1)%4294967296 end
end
function T.packet(now,tick)
 local S=ns.state;local G=ns.features.GroupContext;local F=ns.features.Healing
 local flags=G.code(G.read(UnitExists,1,"target"))
 for i=1,7 do flags=flags+G.code(G.read(UnitIsUnit,1,"target",T.units[i]))*4^i end
 local identity=G.text(G.read(UnitGUID,1,"target"),40)
 local packet=(F.shaman and "HHT1" or "HHT2")..S.bytes(S.setupSession,4)..S.bytes(tick,4)..S.bytes(S.auraGeneration,1)..S.bytes(F.revision,4)..S.bytes(flags,2)..S.bytes(#identity,1)..identity
 local existing=0
 for i=1,9 do local e=T.entries[i];local valid=T.current(e)
  packet=packet..S.bytes(valid and S.compactBindingCode(e.key) or 0,2)
  if valid and e.existing then existing=existing+2^(i-1) end
 end
 packet=packet..S.bytes(existing,2)
 for _,spec in ipairs(F.deliverySpecs()) do
  local e=F.delivery(spec);packet=packet..S.bytes(e and e.id or 0,4)..S.bytes(e and S.compactBindingCode(e.key) or 0,2)
 end
 return packet..S.bytes(S.adler32(packet),4)
end
