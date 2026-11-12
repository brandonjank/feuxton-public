-- Shared delivery: current player bindings first, owned secure keys otherwise.
local _, ns = ...
local S = ns.state

-- Each spell family keeps one key for this addon session. Removed/conflicting
-- keys are never recycled for another spell: an older app reading cannot cast
-- a different ability. This pool is disjoint from recipient keys and excludes
-- common two-modifier letters even when WoW reports them as unassigned.
local M={entries={},reserved={},deliveries={},playerMappings={},nextSlot=200,revision=0}
S.managedSpells=M
M.keys={}
for code=65,90 do
    local key="ALT-CTRL-SHIFT-"..string.char(code)
    if not ns.keyPolicy.builtinReason(key) then M.keys[#M.keys+1]=key end
end
for _,key in ipairs({"-","=","[","]",";","'",",",".","/"}) do M.keys[#M.keys+1]="ALT-CTRL-SHIFT-"..key end
for code=0,9 do M.keys[#M.keys+1]="ALT-CTRL-NUMPAD"..code end
-- Preserve the global 36-key vocabulary and its 16-byte legacy wire limit.
-- Druid and Warlock counted compact protocols can additionally carry longer
-- numpad chords, disjoint from courtesy's plain digits and +/- quarantine banks.
M.extendedKeys={}
for code=0,9 do
    local key="ALT-CTRL-SHIFT-NUMPAD"..code
    if not ns.keyPolicy.builtinReason(key) then M.extendedKeys[#M.extendedKeys+1]=key end
end
local druidKeys={};for _,key in ipairs(M.keys)do druidKeys[#druidKeys+1]=key end
for _,key in ipairs(M.extendedKeys)do druidKeys[#druidKeys+1]=key end
function M.keysForClass(class)return (class=="DRUID" or class=="WARLOCK")and druidKeys or M.keys end
-- Recovery items and explicit safety commands must remain available when
-- optional spellbook utilities fill the class pool. Keeping the
-- original allocation first preserves every existing spell/item family key.
-- No Alt function chords, close/print shortcuts or F10 menu activation.
M.itemKeys={}
for _,number in ipairs({1,2,3,5,6,7,8,9,11})do M.itemKeys[#M.itemKeys+1]="CTRL-SHIFT-F"..number end
local function bindingAction(key,overrides)
    return S.readableCall(GetBindingAction,key,overrides)
end
local scanPlayerBindings,playerMappingCurrent,selectPlayerMapping
function M.available()
    return type(SetOverrideBindingClick)=="function" and type(ClearOverrideBindings)=="function" and type(GetBindingAction)=="function"
end
function M.current(entry)
    return entry and entry.managed and entry.active and not entry.invalidated and entry.key
        and not ns.keyPolicy.reason(entry.key)
        and bindingAction(entry.key,false)=="" and bindingAction(entry.key,true)==entry.action
        and (not entry.petAbility or ns.features.PetSupport and ns.features.PetSupport.current(entry))
end
-- Two auxiliary guild controls share the safe-key reservations without joining
-- class-spell refresh ownership. Each family allocates once per addon session;
-- a conflict pauses that control instead of lending its key to another action.
function M.auxiliaryCurrent(family,buttonName,key)
    local entry=M.auxiliary and M.auxiliary[family]
    return entry and entry.key==key and entry.buttonName==buttonName and M.reserved[key]==family and not ns.keyPolicy.reason(key)
        and bindingAction(key,false)=="" and bindingAction(key,true)==entry.action or false
end
function M.claimAuxiliaryBinding(family,buttonName)
    if not M.available() or S.readableCall(InCombatLockdown)~=false then return nil end
    M.auxiliary=M.auxiliary or {};local entry=M.auxiliary[family]
    if not entry then
        entry={owner=CreateFrame("Frame",nil,UIParent),buttonName=buttonName,action="CLICK "..buttonName..":LeftButton"};M.auxiliary[family]=entry
    end
    if not entry.key then
        local pools={M.itemKeys,M.extendedKeys,M.keys}
        for _,keys in ipairs(pools)do
            for _,key in ipairs(keys)do
                if not M.reserved[key] and not ns.keyPolicy.reason(key) and bindingAction(key,false)=="" and bindingAction(key,true)==""then entry.key=key;M.reserved[key]=family;break end
            end
            if entry.key then break end
        end
    end
    if not entry.key or entry.buttonName~=buttonName or ns.keyPolicy.reason(entry.key) or bindingAction(entry.key,false)~=""then return nil end
    local observed=bindingAction(entry.key,true)
    if observed==""then pcall(SetOverrideBindingClick,entry.owner,false,entry.key,entry.buttonName,"LeftButton")end
    return M.auxiliaryCurrent(family,buttonName,entry.key)and entry.key or nil
end
function S.mappingCurrent(mapping)
    if not mapping or mapping.invalidated then return false end
    if mapping.playerOwned then return playerMappingCurrent(mapping) end
    if mapping.managed then return M.current(mapping) and true or false end
    if mapping.specialIndex then return S.specialMappingCurrent(mapping) end
    local button=mapping.button
    return button and S.readableCall(button.IsVisible,button)==true and S.safeField(button,"action")==mapping.slot or false
end
function S.preferredMapping(mappings)
    local chosen
    for _,mapping in ipairs(mappings or {}) do
        if S.mappingCurrent(mapping) and (not chosen or mapping.playerOwned and not chosen.playerOwned or
            mapping.playerOwned==chosen.playerOwned and chosen.kind~="spell" and mapping.kind=="spell") then chosen=mapping end
    end
    return chosen
end
function M.deliveryCurrent(entry)
    return entry and (entry.playerOwned and playerMappingCurrent(entry) or not entry.playerOwned and M.current(entry)) and true or false
end
function M.delivery(class,family)
    local key=class..":"..family
    local chosen=M.deliveries[key]
    if M.deliveryCurrent(chosen) then return chosen end
    local managed=M.entries[key]
    return M.current(managed) and managed or nil
end
local function known(id)
    local value=S.readableCall(S.bookAPI.IsSpellKnown,id)
    if type(value)~="boolean" then value=S.readableCall(IsSpellKnown,id) end
    return value==true
end
function M.catalog()
    local class=S.readableCall(function() local _,key=UnitClass("player");return key end)
    local candidates,byName={},{}
    local function add(id,name,unit,explicit,startAttack,petAttack,managedName,spec)
        if S.isSecret(id) or type(id)~="number" or id<=0 or id>=2147483648 or id~=math.floor(id) or not known(id) then return end
        local info=S.readableCall(S.spellAPI.GetSpellInfo,id)
        name=S.safeField(info,"name") or name
        if S.isSecret(name) or type(name)~="string" or name=="" then return end
        if S.readableCall(S.spellAPI.IsSpellPassive or IsPassiveSpell,id)==true then return end
        local family=managedName or name
        local existing=byName[family]
        -- Name resolution chooses the client's current learned rank, never a
        -- macro-selected rank or a guessed ordering of spell IDs.
        if not (spec and spec.pinnedSpellID) then
            local resolved=S.readableCall(S.spellAPI.GetSpellInfo,name)
            local current=S.safeField(resolved,"spellID")
            if type(current)=="number" and current>0 and known(current) then id=current end
        end
        if existing then if explicit then existing.unit=existing.friendly and "target" or unit;existing.id=id;existing.startAttack=startAttack;existing.petAttack=petAttack end;return end
        local declaredHelpful=spec and (spec.healing==true or spec.support==true or spec.friendly==true) and spec.directSelf~=true and unit~="pet"
        local friendly=declaredHelpful or (class=="PALADIN" and (name=="Holy Light" or name=="Flash of Light" or name=="Blessing of Might" or name=="Blessing of Wisdom" or name=="Blessing of Kings" or name=="Blessing of Freedom")) or (class=="SHAMAN" and (name=="Healing Wave" or name=="Lesser Healing Wave" or name=="Riptide")) or (class=="DRUID" and name=="Healing Touch")
        local buff=spec and spec.buff==true or class=="PALADIN" and (name=="Blessing of Might" or name=="Blessing of Wisdom" or name=="Blessing of Kings")
        local entry={id=id,name=name,abilityKey=spec and spec.key,managedName=managedName,pinnedSpellID=spec and spec.pinnedSpellID,unit=friendly and "target" or unit,friendly=friendly,support=name=="Blessing of Freedom" or spec and spec.support==true,buff=buff,healing=friendly and not buff and name~="Blessing of Freedom",startAttack=startAttack,petAttack=petAttack,noToggle=spec and spec.noToggle,groundAtCursor=spec and spec.groundAtCursor,stopAttack=spec and spec.stopAttack};byName[family]=entry;candidates[#candidates+1]=entry
    end
    if class=="DRUID" then
        candidates[#candidates+1]={id=0,name="Feuxton Stop Casting",unit="player",stopCasting=true}
        candidates[#candidates+1]={id=0,name="Feuxton Cancel Form",unit="player",cancelForm=true}
        if ns.features.Consumables then candidates[#candidates+1]=ns.features.Consumables.candidate() end
    end
    local catalog=ns.classes[class]
    local specs=class=="HUNTER" and S.hunterSpecs or catalog and catalog.specs or {}
    -- Reserve an emergency pet key before optional spellbook utilities. Pet
    -- ranks belong to the current demon, not IsSpellKnown's player bank.
    if class=="WARLOCK" and ns.features.PetSupport and ns.features.PetSupport.abilityCandidate then
        local candidate=ns.features.PetSupport.abilityCandidate();if candidate then candidates[#candidates+1]=candidate;byName[candidate.name]=candidate end
    end
    for _,spec in ipairs(specs) do
        if not spec.petAbility then
            local info=S.readableCall(S.spellAPI.GetSpellInfo,spec.pinnedSpellID or spec.name)
            local unit=spec.unit or "target"
            add(spec.pinnedSpellID or S.safeField(info,"spellID"),spec.name,unit,true,spec.startAttack,spec.petAttack,spec.managedName,spec)
        end
    end
    if ns.features.PetSupport and ns.features.PetSupport.candidate then
        local candidate=ns.features.PetSupport.candidate(class);if candidate then candidates[#candidates+1]=candidate end
    end
    -- Reserve the Warlock channel safety action before optional spellbook
    -- utilities can exhaust the finite, non-recycled managed-key pool.
    if class=="WARLOCK" then
        candidates[#candidates+1]={id=0,name="Feuxton Stop Casting",unit="player",stopCasting=true}
        if ns.features.Consumables then candidates[#candidates+1]=ns.features.Consumables.candidate() end
    end
    if class=="HUNTER" then for _,spec in ipairs(ns.playerBuffSpecs or {}) do add(spec.spellID,spec.name,"player",true) end end
    if ns.features.Racials then for _,spec in ipairs(ns.features.Racials.learned()) do
        -- Reserve the control break before optional spellbook utilities can
        -- exhaust the key pool. Druid already reserves all learned racials.
        if class=="DRUID" or spec.key=="racial.forsaken" then add(spec.id,spec.name,"player",true) end
    end end
    local lines=S.readableCall(S.bookAPI.GetNumSpellBookSkillLines)
    local bank=type(Enum)=="table" and S.safeField(S.safeField(Enum,"SpellBookSpellBank"),"Player")
    if type(lines)=="number" and lines>=0 and lines<=64 and type(bank)=="number" then
        for line=1,lines do
            local info=S.readableCall(S.bookAPI.GetSpellBookSkillLineInfo,line)
            local offset,count=S.safeField(info,"itemIndexOffset"),S.safeField(info,"numSpellBookItems")
            -- General includes professions, racial/passive and utility entries.
            -- Explicit class catalog entries above still work in any tab.
            local className=S.readableCall(UnitClass,"player")
            if (line>1 or S.safeField(info,"name")==className) and type(offset)=="number" and offset>=0 and type(count)=="number" and count>=0 and count<=1024 then
                for index=1,count do
                    local item=S.readableCall(S.bookAPI.GetSpellBookItemInfo,offset+index,bank)
                    if S.safeField(item,"isPassive")~=true then add(S.safeField(item,"spellID"),S.safeField(item,"name"),"target",false) end
                end
            end
        end
    end
    if class=="PALADIN" or class=="SHAMAN" then candidates[#candidates+1]={id=0,name="Feuxton Stop Casting",unit="player",stopCasting=true}
        if class=="PALADIN" then
            candidates[#candidates+1]={id=0,name="Feuxton Remove Fury",unit="player",cancelFury=true}
            candidates[#candidates+1]={id=0,name="Feuxton Skull",unit="target",skull=true}
        end end
    if class~="DRUID" and ns.features.Racials then for _,spec in ipairs(ns.features.Racials.learned()) do add(spec.id,spec.name,"player",true) end end
    if class=="PALADIN" and ns.features.ControlEffects then
        local spec=ns.features.ControlEffects.freedom;local info=S.readableCall(S.spellAPI.GetSpellInfo,spec.name)
        add(S.safeField(info,"spellID"),spec.name,"target",true)
    end
    if class~="WARLOCK" and class~="DRUID" and ns.features.Consumables then candidates[#candidates+1]=ns.features.Consumables.candidate() end
    if ns.features.Bandages then local bandage=ns.features.Bandages.candidate();if bandage then candidates[#candidates+1]=bandage end end
    if ns.features.Potions then for _,potion in ipairs(ns.features.Potions.candidates())do candidates[#candidates+1]=potion end end
    return candidates,class
end
function M.refresh()
    if not M.available() or S.readableCall(InCombatLockdown)~=false or M.refreshing then return false end
    M.refreshing=true
    if not M.owner then M.owner=CreateFrame("Frame",nil,UIParent) end
    local candidates,class=M.catalog()
    local keys=M.keysForClass(class)
    local signature={class or ""};local selected={}
    for _,candidate in ipairs(candidates) do
        local family=class..":"..(candidate.managedName or candidate.name)
        local player=selectPlayerMapping(candidate,M.playerMappings);selected[family]=player
        signature[#signature+1]=(candidate.managedName or candidate.name)..":"..candidate.id..":"..candidate.unit..":"..tostring(candidate.startAttack==true)..":"..tostring(candidate.petAttack==true)..":"..tostring(candidate.petCommand==true)..":"..tostring(candidate.itemID or 0)..":"..tostring(candidate.cancelForm==true)..":"..tostring(candidate.noToggle==true)..":"..tostring(candidate.groundAtCursor==true)..":"..tostring(candidate.stopAttack==true)..":"..tostring(candidate.petActionSlot or 0)..":"..(candidate.petIdentity or "")..":"..(player and (player.action..":"..player.slot..":"..player.id..":"..player.key..":"..player.kind) or "managed")
    end
    signature=table.concat(signature,"|")
    local changed=signature~=M.signature or M.retry
    M.retry=false
    for _,entry in pairs(M.entries) do if entry.active and not M.current(entry) then changed=true end end
    if changed then
        ClearOverrideBindings(M.owner)
        for _,entry in pairs(M.entries) do entry.active=false;entry.button:SetAttribute("type",nil) end
        M.deliveries={}
        for _,candidate in ipairs(candidates) do
            local family=class..":"..(candidate.managedName or candidate.name)
            local entry=M.entries[family]
            local player=selected[family]
            if player then
                -- Keep any old secure key quarantined for this same family.
                -- Never reserve a second key, or lend its retired key elsewhere.
                M.deliveries[family]=player
            else
            if not entry and M.nextSlot<400 then
                local name="FeuxtonClassSpell"..M.nextSlot
                local button=CreateFrame("Button",name,UIParent,"SecureActionButtonTemplate,SecureHandlerBaseTemplate")
                button:SetSize(1,1);button:SetPoint("TOPLEFT",UIParent,"TOPLEFT",-10000,10000);button:SetAlpha(0)
                button:RegisterForClicks("AnyDown","AnyUp");button:SetAttribute("useOnKeyDown",true)
                button:SetAttribute("checkselfcast",false);button:SetAttribute("checkfocuscast",false);button:SetAttribute("checkmouseovercast",false)
                entry={managed=true,kind="spell",slot=M.nextSlot,button=button,action="CLICK "..name..":LeftButton",buttonName=name}
                M.nextSlot=M.nextSlot+1;M.entries[family]=entry
            end
            if entry then
                if entry.key and (ns.keyPolicy.reason(entry.key) or bindingAction(entry.key,false)~="" or bindingAction(entry.key,true)~="") then entry.key=nil end
                if not entry.key then
                    for _,key in ipairs(keys) do
                        if not M.reserved[key] and not ns.keyPolicy.reason(key) and bindingAction(key,false)=="" and bindingAction(key,true)=="" then entry.key=key;M.reserved[key]=family;break end
                    end
                    if not entry.key and (candidate.itemID~=nil or candidate.stopCasting or candidate.cancelForm or candidate.cancelFury or candidate.skull or candidate.petCommand)then
                        for _,key in ipairs(M.itemKeys)do
                            if not M.reserved[key] and not ns.keyPolicy.reason(key) and bindingAction(key,false)=="" and bindingAction(key,true)=="" then entry.key=key;M.reserved[key]=family;break end
                        end
                    end
                end
                entry.id=candidate.id;entry.spellID=candidate.id;entry.name=candidate.name;entry.unit=candidate.unit;entry.invalidated=nil;entry.stopAttack=candidate.stopAttack;entry.startAttack=candidate.startAttack;entry.stopCasting=candidate.stopCasting;entry.cancelForm=candidate.cancelForm;entry.cancelFury=candidate.cancelFury;entry.petAttack=candidate.petAttack;entry.friendly=candidate.friendly;entry.itemID=candidate.itemID;entry.skull=candidate.skull;entry.petCommand=candidate.petCommand
                entry.petAbility=candidate.petAbility;entry.petActionSlot=candidate.petActionSlot;entry.petIdentity=candidate.petIdentity
                entry.button:SetAttribute("item",candidate.itemID and candidate.itemID>0 and "item:"..candidate.itemID or nil)
                entry.button:SetAttribute("spell",candidate.cancelFury and "Righteous Fury" or candidate.id>0 and candidate.id or nil);entry.button:SetAttribute("unit",candidate.unit)
                -- One secure click commands the pet before the attack. This
                -- also covers target changes while Mark is rate-limited; the
                -- app never waits for pet arrival or a separate pet receipt.
                local macro=candidate.petCommand and "/petattack [@target,harm,nodead]" or candidate.unit=="mouseover" and
                    (class=="WARLOCK" and ("/petattack [combat,@target,harm,nodead]\n/cast [combat,@mouseover,harm,nodead] "..candidate.name) or ("/cast [@mouseover,harm,nodead] "..candidate.name))
                    or candidate.stopAttack and ("/stopattack\n/cast [@target,harm,nodead] "..candidate.name)
                    or candidate.stopCasting and "/stopcasting" or candidate.cancelForm and "/cancelform"
                    or candidate.noToggle and not candidate.startAttack and not candidate.petAttack and ("/cast !"..candidate.name)
                    or candidate.groundAtCursor and ("/cast [@cursor] "..candidate.name)
                    or candidate.startAttack and ((candidate.petAttack and "/petattack [@target,harm,nodead]\n" or "").."/startattack [harm,nodead]"..
                    (candidate.id~=6603 and "\n/cast [@target,harm,nodead] "..(candidate.noToggle and "!" or "")..candidate.name or ""))
                    or candidate.petAttack and ("/petattack [@target,harm,nodead]\n/cast [@target,harm,nodead] "..((candidate.noToggle or class=="WARLOCK" and candidate.name=="Shoot") and "!" or "")..candidate.name) or nil
                entry.button:SetAttribute("macrotext",macro)
                if entry.key then
                    local ok=pcall(SetOverrideBindingClick,M.owner,false,entry.key,entry.buttonName,"LeftButton")
                    entry.active=ok and bindingAction(entry.key,false)=="" and bindingAction(entry.key,true)==entry.action
                end
                entry.button:SetAttribute("marker",candidate.skull and 8 or nil)
                entry.button:SetAttribute("action",candidate.skull and "set" or candidate.petAbility and candidate.petActionSlot or nil)
                entry.button:SetAttribute("type",entry.active and (candidate.petAbility and "pet" or candidate.skull and "raidtarget" or candidate.itemID and "item" or candidate.cancelFury and "cancelaura" or macro and "macro" or "spell") or nil)
                entry.button.hhSpellID=candidate.id
                entry.button.hhSelfFallback=candidate.friendly==true
                if candidate.skull and not entry.tankMarkHook then
                    entry.button:HookScript("PreClick",function(button,mouse,down)
                        local threat=ns.features.Threat
                        if threat then threat.clicked(down) end
                    end)
                    entry.tankMarkHook=true
                end
                if (candidate.friendly or candidate.name=="Lay on Hands") and not entry.recipientHook then
                    local spec={healing=candidate.healing or candidate.name=="Lay on Hands",support=candidate.support,buff=candidate.buff,abilityKey=candidate.abilityKey,name=candidate.name,directSelf=candidate.name=="Lay on Hands"}
                    entry.button:SetScript("PreClick",function(button,mouse,down) ns.features.Healing.track(button,spec,down) end)
                    if candidate.friendly then
                        entry.button:SetAttribute("hh-heal",candidate.healing==true or candidate.support==true)
                        SecureHandlerWrapScript(entry.button,"OnClick",entry.button,[[
                            local recipient = SecureCmdOptionParse("[@target,help,nodead]target;[@target,harm][noexists]player")
                            local allowed = recipient == "target" or recipient == "player"
                            if not self:GetAttribute("hh-heal") then allowed = allowed and SecureCmdOptionParse("[nocombat]1;0") == "1" end
                            self:SetAttribute("unit",allowed and recipient or "target")
                            self:SetAttribute("type",allowed and "spell" or nil)
                        ]])
                    end
                    entry.recipientHook=true
                end
                if not entry.active then M.retry=true end
            end
            M.deliveries[family]=entry
            end
        end
        M.signature=signature;M.revision=M.revision+1
    else
        -- Discovery creates new identity objects even when keys are unchanged.
        -- Never retain one invalidated by a preceding binding/macro event.
        for _,candidate in ipairs(candidates) do local family=class..":"..(candidate.managedName or candidate.name);M.deliveries[family]=selected[family] or M.entries[family] end
    end
    M.deliveryCandidates=candidates;M.deliveryClass=class
    M.refreshing=false
    return true
end
function M.export(bindingTiles)
    local result={}
    for _,entry in pairs(M.deliveries) do if entry.id>0 and M.deliveryCurrent(entry) then result[#result+1]=entry end end
    table.sort(result,function(a,b) return a.slot<b.slot end)
    S.setupMappings=result
    for _,tile in ipairs(bindingTiles) do
        tile.mappings={}
        for _,entry in ipairs(result) do
            if entry.id==tile.spellID or entry.name==(tile.spellName or tile.name) then tile.mappings[#tile.mappings+1]=entry end
        end
        local chosen=S.preferredMapping(tile.mappings)
        tile.binding:SetText(chosen and chosen.key or "--")
    end
    local playerCount=0;for _,entry in ipairs(result)do if entry.playerOwned then playerCount=playerCount+1 end end
    S.bindingDiagnostics={"Class spell delivery: "..#result.." / revision "..M.revision.."; "..playerCount.." current player bindings"}
end

-- Compatibility discovery for clients without the managed binding API.
-- It reads existing bars/macros without editing them; the supported client
-- takes the managed path above and never enters this scanner.
S.buttonGroups = {
    { "ActionButton", "ACTIONBUTTON" },
    { "MultiBarBottomLeftButton", "MULTIACTIONBAR1BUTTON" },
    { "MultiBarBottomRightButton", "MULTIACTIONBAR2BUTTON" },
    { "MultiBarRightButton", "MULTIACTIONBAR3BUTTON" },
    { "MultiBarLeftButton", "MULTIACTIONBAR4BUTTON" },
    { "MultiBar5Button", "MULTIACTIONBAR5BUTTON" },
    { "MultiBar6Button", "MULTIACTIONBAR6BUTTON" },
    { "MultiBar7Button", "MULTIACTIONBAR7BUTTON" },
}
S.bindingDiagnostics = {}
S.setupMappings = {}
-- Retail special actions (auras/stances/forms) have their own indices, not
-- GetActionInfo slots. Only use a public spell identity from that index.
function S.specialActionSpell(index)
    if type(index)~="number" or index<1 or index>10 or index~=math.floor(index) or type(GetShapeshiftFormInfo)~="function" then return nil end
    local ok,texture,active,castable,id=pcall(GetShapeshiftFormInfo,index)
    if not ok or S.isSecret(id) or type(id)~="number" or id<=0 or id>=2147483648 or id~=math.floor(id) then return nil end
    return id
end
function S.specialMappingCurrent(mapping)
    return not mapping.specialIndex or S.specialActionSpell(mapping.specialIndex)==mapping.id
end
local function playerKey(key,action)
    key=ns.keyPolicy.canonical(key)
    if not key or ns.keyPolicy.reason(key) or S.compactBindingCode(key)==0 then return nil end
    -- A visible action and a saved base binding do not prove who receives the
    -- key: another addon may currently own its override.
    if bindingAction(key,false)~=action or bindingAction(key,true)~=action then return nil end
    return key
end
local function playerKeys(action)
    local ok,first,second=pcall(GetBindingKey or function() end,action)
    if not ok then return nil end
    first=not S.isSecret(first) and playerKey(first,action) or nil
    second=not S.isSecret(second) and playerKey(second,action) or nil
    return first or second,first and second or nil
end
local function actionSpell(slot,kind,actionID)
    local api=type(C_ActionBar)=="table" and C_ActionBar.GetSpell
    local resolved=type(api)=="function" and S.readableCall(api,slot) or nil
    if kind=="spell" then
        local id=type(resolved)=="number" and resolved>0 and resolved or actionID
        return S.setupNumber(id),"spell"
    end
    if kind=="macro" and type(GetMacroSpell)=="function" then
        local ok,first,_,third=pcall(GetMacroSpell,actionID)
        if not ok then return nil end
        local id=not S.isSecret(first) and type(first)=="number" and first or not S.isSecret(third) and type(third)=="number" and third or nil
        if type(resolved)=="number" and resolved>0 and resolved~=id then return nil end
        return S.setupNumber(id),"macro candidate"
    end
end
local function macroTargetsSelected(id)
    local body=S.readableCall(GetMacroBody,id)
    if type(body)~="string" or body=="" then return false end
    body=body:lower()
    -- Authorization is unchanged. These are delivery/identity constraints, not
    -- a macro approval gate or an attempt to interpret a rotation language.
    for unit in body:gmatch("@([%w_]+)")do if unit~="target" then return false end end
    for unit in body:gmatch("target%s*=%s*([%w_]+)")do if unit~="target" then return false end end
    -- Sending the selected chord changes its modifiers/button conditions.
    -- The spell reported before that input cannot certify the resulting branch.
    for conditions in body:gmatch("%[([^%]]*)%]")do for condition in conditions:gmatch("[^,]+")do
        local token=condition:match("^%s*([%a]+)")
        if token=="mod" or token=="modifier" or token=="nomod" or token=="nomodifier" or token=="button" or token=="btn" or token=="nobutton" or token=="nobtn" then return false end
    end end
    for line in (body.."\n"):gmatch("([^\n]*)\n")do
        local command=line:match("^%s*/([%a]+)")
        if command and (command:match("^target") or command=="assist" or command=="focus" or command=="click" or command=="castsequence" or command=="castrandom") then return false end
    end
    return true
end
playerMappingCurrent=function(mapping)
    if not mapping or not mapping.playerOwned or mapping.invalidated or playerKey(mapping.key,mapping.action)~=mapping.key then return false end
    if mapping.specialIndex then return S.specialMappingCurrent(mapping) end
    local button=mapping.button
    if not button or S.readableCall(button.IsVisible,button)~=true or S.safeField(button,"action")~=mapping.slot then return false end
    local ok,kind,id=pcall(GetActionInfo or function() end,mapping.slot)
    if not ok or S.isSecret(kind) or S.isSecret(id) or kind~=mapping.actionType or id~=mapping.actionID then return false end
    local spell=actionSpell(mapping.slot,kind,id)
    return spell~=nil and spell==mapping.id
end
scanPlayerBindings=function()
    local result={}
    for _,group in ipairs(S.buttonGroups)do for index=1,12 do
        local name=group[1]..index;local button=_G[name]
        if button and S.readableCall(button.IsVisible,button)==true then
            local slot=S.setupNumber(S.safeField(button,"action"))
            if slot and slot>0 then
                local ok,actionType,actionID=pcall(GetActionInfo or function()end,slot)
                if ok and not S.isSecret(actionType) and not S.isSecret(actionID) and type(actionID)=="number" and actionID>0 then
                    local id,kind=actionSpell(slot,actionType,actionID)
                    if id and id>0 then
                        local action=S.safeField(button,"bindingAction")
                        if type(action)~="string" or action=="" then action=group[2]..index end
                        local key,key2=playerKeys(action)
                        if not key then action="CLICK "..name..":LeftButton";key,key2=playerKeys(action) end
                        if key and not action:match("^CLICK Feuxton") then
                            local info=S.readableCall(S.spellAPI.GetSpellInfo,id)
                            result[#result+1]={playerOwned=true,id=id,spellID=id,name=S.safeField(info,"name"),slot=slot,key=key,key2=key2,kind=kind,action=action,button=button,actionType=actionType,actionID=actionID,selectedMacro=actionType~="macro" or macroTargetsSelected(actionID)}
                        end
                    end
                end
            end
        end
    end end
    local forms=S.readableCall(GetNumShapeshiftForms)
    if type(forms)=="number" and forms>=0 and forms<=10 and forms==math.floor(forms)then for index=1,forms do
        local id=S.specialActionSpell(index)
        if id then
            local action="SHAPESHIFTBUTTON"..index;local key,key2=playerKeys(action)
            if key then local info=S.readableCall(S.spellAPI.GetSpellInfo,id);result[#result+1]={playerOwned=true,id=id,spellID=id,name=S.safeField(info,"name"),slot=900+index,key=key,key2=key2,kind="spell",action=action,specialIndex=index} end
        end
    end end
    return result
end
selectPlayerMapping=function(candidate,mappings)
    -- Friendly delivery needs our secure recipient routing and exact receipt
    -- hooks. Augmented actions also retain their pet/start/stop/non-toggle
    -- semantics; matching only a displayed spell ID would lose that behavior.
    if not candidate or candidate.id<=0 or candidate.unit~="target" or candidate.friendly or candidate.healing or candidate.support or candidate.buff or candidate.pinnedSpellID or candidate.managedName or candidate.name=="Lay on Hands" or
        candidate.itemID or candidate.startAttack or candidate.petAttack or candidate.noToggle or candidate.groundAtCursor or candidate.stopAttack or candidate.petCommand or candidate.petAbility then return nil end
    local chosen
    for _,mapping in ipairs(mappings or {})do
        if mapping.id==candidate.id and not mapping.specialIndex and mapping.selectedMacro~=false and playerMappingCurrent(mapping) and
            (not chosen or chosen.kind~="spell" and mapping.kind=="spell")then chosen=mapping end
    end
    if chosen then chosen.unit=candidate.unit;chosen.abilityKey=candidate.abilityKey end
    return chosen
end
function M.invalidatePlayerMappings(kind,slot)
    -- Only an authoritative binding/macro/slot event revokes these identities
    -- in combat. Routine discovery requests cannot mutate or revoke them.
    for _,mapping in ipairs(M.playerMappings)do
        if (not kind or mapping.kind==kind) and (not slot or slot==0 or mapping.slot==slot)then mapping.invalidated=true end
    end
end
function S.discoverBindings()
    if M.refreshing then return end
    if ns.markSetupDirty then ns.markSetupDirty() end
    if S.readableCall(InCombatLockdown) ~= false then
        -- Public bars can page/rebind during combat. Refresh only their
        -- identity metadata against the last complete OOC candidate catalog;
        -- no spellbook scan, secure mutation or new key allocation occurs.
        local class=S.readableCall(function()local _,key=UnitClass("player");return key end)
        if not M.available()then return end
        if not M.deliveryCandidates or class~=M.deliveryClass then S.bindingsValid=false;return end
        M.invalidatePlayerMappings();M.playerMappings=scanPlayerBindings();M.deliveries={}
        for _,candidate in ipairs(M.deliveryCandidates)do
            local family=class..":"..(candidate.managedName or candidate.name)
            M.deliveries[family]=selectPlayerMapping(candidate,M.playerMappings)or M.entries[family]
        end
        local tiles={};for _,tile in ipairs(S.tiles)do tiles[#tiles+1]=tile end;for _,tile in ipairs(ns.playerBuffSpecs or {})do tiles[#tiles+1]=tile end
        M.export(tiles);S.bindingsValid=true
        return
    end
    M.invalidatePlayerMappings()
    if ns.features.Consumables and ns.features.Consumables.refreshRestBindings then pcall(ns.features.Consumables.refreshRestBindings)end
    S.bindingsValid = false
    S.bindingDiagnostics = {}
    S.setupMappings = {}
    local bindingTiles={}
    for _,tile in ipairs(S.tiles) do bindingTiles[#bindingTiles+1]=tile end
    for _,tile in ipairs(ns.playerBuffSpecs or {}) do bindingTiles[#bindingTiles+1]=tile end
    for _, tile in ipairs(bindingTiles) do tile.mappings = {} end
    M.playerMappings=scanPlayerBindings()
    if M.available() then
        local ok,result=pcall(M.refresh)
        M.refreshing=false
        if not ok or not result then
            if M.owner then pcall(ClearOverrideBindings,M.owner) end
            for _,entry in pairs(M.entries) do entry.active=false end
            M.signature=nil;S.bindingDiagnostics={"Managed spell setup failed: "..S.describe(result)};return
        end
        M.export(bindingTiles);S.bindingsValid=true;return
    end
    for _, group in ipairs(S.buttonGroups) do
        for index = 1, 12 do
            local button = _G[group[1] .. index]
            if button and S.readableCall(button.IsVisible, button) == true then
                local slot = button.action
                if not S.isSecret(slot) and type(slot) == "number" and type(GetActionInfo) == "function" then
                    local ok, actionType, actionID = pcall(GetActionInfo, slot)
                    if ok and not S.isSecret(actionType) and not S.isSecret(actionID) then
                        local mappedID, kind = nil, nil
                        local actionSpell = type(C_ActionBar) == "table" and S.readableCall(C_ActionBar.GetSpell, slot) or nil
                        if actionType == "spell" then
                            mappedID = type(actionSpell) == "number" and actionSpell > 0 and actionSpell or actionID
                            kind = "spell"
                        elseif actionType == "macro" and type(GetMacroSpell) == "function" then
                            if type(actionSpell) == "number" and actionSpell > 0 then mappedID = actionSpell end
                            if not mappedID then
                                local macroOK, first, second, third = pcall(GetMacroSpell, actionID)
                                if macroOK then
                                    if not S.isSecret(first) and type(first) == "number" then mappedID = first end
                                    if not mappedID and not S.isSecret(third) and type(third) == "number" then mappedID = third end
                                end
                            end
                            kind = "macro candidate"
                        end
                        if type(mappedID) == "number" then
                            local mappedInfo = S.readableCall(S.spellAPI.GetSpellInfo, mappedID)
                            local mappedName = S.safeField(mappedInfo, "name")
                            local bindingAction = button.bindingAction
                            if S.isSecret(bindingAction) or type(bindingAction) ~= "string" then bindingAction = group[2] .. index end
                            local key = S.readableCall(GetBindingKey, bindingAction)
                            if not key then bindingAction = "CLICK " .. group[1] .. index .. ":LeftButton"; key = S.readableCall(GetBindingKey, bindingAction) end
                            local key2
                            if type(GetBindingKey) == "function" then
                                local keyOK, firstKey, secondKey = pcall(GetBindingKey, bindingAction)
                                if keyOK and not S.isSecret(secondKey) and type(secondKey)=="string" then key2=secondKey end
                            end
                            -- Internal native source only; setup/report serializers
                            -- explicitly select scalar fields and never send the frame.
                            S.setupMappings[#S.setupMappings+1] = {id=mappedID,name=mappedName,slot=slot,key=key,key2=key2,kind=kind,action=bindingAction,button=button}
                            S.bindingDiagnostics[#S.bindingDiagnostics + 1] = group[1] .. index .. " / slot " .. slot
                                .. " / " .. S.describe(actionType) .. " " .. S.describe(actionID)
                                .. " / " .. S.describe(mappedName) .. " / key " .. S.describe(key)
                            if type(key) == "string" then
                                for _, tile in ipairs(bindingTiles) do
                                    if tile.spellID == mappedID or (mappedName and tile.spellName == mappedName) then
                                        tile.mappings[#tile.mappings + 1] = { slot = slot, key = key, kind = kind, button = button, spellID = mappedID }
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    local forms=S.readableCall(GetNumShapeshiftForms)
    if type(forms)=="number" and forms>=0 and forms<=10 and forms==math.floor(forms) then
        for index=1,forms do
            local id=S.specialActionSpell(index)
            if id then
                local action="SHAPESHIFTBUTTON"..index
                local key=S.readableCall(GetBindingKey,action)
                local key2
                if type(GetBindingKey)=="function" then
                    local ok,first,second=pcall(GetBindingKey,action)
                    if ok and not S.isSecret(second) and type(second)=="string" then key2=second end
                end
                if type(key)~="string" or key=="" then key=key2;key2=nil end
                if type(key)=="string" and key~="" then
                    local info=S.readableCall(S.spellAPI.GetSpellInfo,id)
                    local name=S.safeField(info,"name")
                    -- 901..910 are transport identifiers for special indices.
                    -- They must never be passed to GetActionInfo/GetActionSpell.
                    S.setupMappings[#S.setupMappings+1]={id=id,name=name,slot=900+index,key=key,key2=key2,kind="spell",action=action,specialIndex=index}
                    S.bindingDiagnostics[#S.bindingDiagnostics+1]=action.." / spell "..id.." / key "..key
                end
            end
        end
    end
    for _, tile in ipairs(bindingTiles) do
        local mapping = tile.mappings[1]
        tile.binding:SetText(mapping and mapping.key or "--")
    end
    S.bindingsValid = true
end


-- Public spell identity of the same preferred visible mapping used by the fast link.
-- Macro-selected ranks can differ from the name-resolved spellbook rank.
function S.boundSpellID(tile)
    if not tile then return nil end
    local chosen=S.bindingsValid and S.preferredMapping(tile.mappings)
    if chosen and chosen.managed then return S.setupNumber(chosen.id) end
    local button=chosen and chosen.button
    local slot=button and S.setupNumber(button.action)
    if chosen and slot==chosen.slot and S.readableCall(button.IsVisible,button)==true then
        if S.isSecret(chosen.spellID) then return nil end
        if chosen.spellID==nil then return tile.spellID end
        return S.setupNumber(chosen.spellID)
    end
    return tile.spellID
end

-- Persist only user exclusions; built-in shortcut families cannot be unblocked.
SLASH_FEUXTONKEYS1="/feuxtonkeys"
S.shortcutCommand=function(text)
    -- Chat pastes can retain code quotes, nonbreaking spaces or a full command.
    -- Normalize only presentation characters, never execute pasted Lua/text.
    text=type(text)=="string" and text or ""
    text=text:gsub("\194\160"," "):gsub("\226\128\175"," "):gsub("`","")
    text=text:match("^%s*(.-)%s*$")
    text=text:gsub("^/[Ff][Ee][Uu][Xx][Tt][Oo][Nn][Kk][Ee][Yy][Ss]%s+","")
    local action,key=text:match("^(%S+)%s*(.-)%s*$")
    action=action and action:lower() or "list"
    if action=="block" or action=="unblock" then
        if S.readableCall(InCombatLockdown)~=false then print("Feuxton: change shortcut exclusions outside combat.");return end
        key=ns.keyPolicy.canonical(key)
        if not key then print("Feuxton: use /feuxtonkeys block CTRL+ALT+SHIFT+G");return end
        if type(FeuxtonDB)~="table" then FeuxtonDB={} end
        if type(FeuxtonDB.keyBlacklist)~="table" then FeuxtonDB.keyBlacklist={} end
        FeuxtonDB.keyBlacklist[key]=action=="block" and true or nil
        M.retry=true
        S.discoverBindings()
        print("Feuxton: "..key.." / "..(ns.keyPolicy.reason(key) or "not excluded"));return
    end
    if action~="list" then print("Feuxton: unknown shortcut action '"..action.."'. Use /feuxtonkeys block KEY, unblock KEY, or list. Turn casting OFF before changing exclusions.");return end
    print("Feuxton: blocks two-modifier letter shortcuts, Windows keys and common system/app shortcuts. Turn casting OFF before edits.")
    local keys={}
    for key in pairs(ns.keyPolicy.defaults) do keys[#keys+1]=key end
    local custom=type(FeuxtonDB)=="table" and FeuxtonDB.keyBlacklist or {}
    for key in pairs(type(custom)=="table" and custom or {}) do if not ns.keyPolicy.defaults[key] then keys[#keys+1]=key end end
    table.sort(keys);for _,key in ipairs(keys) do print(key.." / "..ns.keyPolicy.reason(key)) end
end
SlashCmdList.FEUXTONKEYS=S.shortcutCommand
