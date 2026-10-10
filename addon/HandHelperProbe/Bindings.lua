-- Managed class spell delivery, with legacy discovery for unsupported clients.
local _, ns = ...
local S = ns.state

-- Each spell family keeps one key for this addon session. Removed/conflicting
-- keys are never recycled for another spell: an older app reading cannot cast
-- a different ability. This pool is disjoint from recipient keys and excludes
-- common two-modifier letters even when WoW reports them as unassigned.
local M={entries={},reserved={},nextSlot=200,revision=0}
S.managedSpells=M
M.keys={}
for code=65,90 do M.keys[#M.keys+1]="ALT-CTRL-SHIFT-"..string.char(code) end
for _,key in ipairs({"-","=","[","]",";","'",",",".","/","8","9"}) do M.keys[#M.keys+1]="ALT-CTRL-SHIFT-"..key end
for code=0,9 do M.keys[#M.keys+1]="ALT-CTRL-NUMPAD"..code end
local function bindingAction(key,overrides)
    return S.readableCall(GetBindingAction,key,overrides)
end
function M.available()
    return type(SetOverrideBindingClick)=="function" and type(ClearOverrideBindings)=="function" and type(GetBindingAction)=="function"
end
function M.current(entry)
    return entry and entry.managed and entry.active and not entry.invalidated and entry.key
        and not ns.keyPolicy.reason(entry.key)
        and bindingAction(entry.key,false)=="" and bindingAction(entry.key,true)==entry.action
end
function S.mappingCurrent(mapping)
    if not mapping or mapping.invalidated then return false end
    if mapping.managed then return M.current(mapping) and true or false end
    if mapping.specialIndex then return S.specialMappingCurrent(mapping) end
    local button=mapping.button
    return button and S.readableCall(button.IsVisible,button)==true and S.safeField(button,"action")==mapping.slot or false
end
function S.preferredMapping(mappings)
    local chosen
    for _,mapping in ipairs(mappings or {}) do
        if S.mappingCurrent(mapping) and (not chosen or mapping.managed and not chosen.managed or chosen.kind~="spell" and mapping.kind=="spell") then chosen=mapping end
    end
    return chosen
end
local function known(id)
    local value=S.readableCall(S.bookAPI.IsSpellKnown,id)
    if type(value)~="boolean" then value=S.readableCall(IsSpellKnown,id) end
    return value==true
end
function M.catalog()
    local class=S.readableCall(function() local _,key=UnitClass("player");return key end)
    local candidates,byName={},{}
    local function add(id,name,unit,explicit,startAttack,petAttack)
        if S.isSecret(id) or type(id)~="number" or id<=0 or id>=2147483648 or id~=math.floor(id) or not known(id) then return end
        local info=S.readableCall(S.spellAPI.GetSpellInfo,id)
        name=S.safeField(info,"name") or name
        if S.isSecret(name) or type(name)~="string" or name=="" then return end
        if S.readableCall(S.spellAPI.IsSpellPassive or IsPassiveSpell,id)==true then return end
        local existing=byName[name]
        -- Name resolution chooses the client's current learned rank, never a
        -- macro-selected rank or a guessed ordering of spell IDs.
        local resolved=S.readableCall(S.spellAPI.GetSpellInfo,name)
        local current=S.safeField(resolved,"spellID")
        if type(current)=="number" and current>0 and known(current) then id=current end
        if existing then if explicit then existing.unit=unit;existing.id=id;existing.petAttack=petAttack end;return end
        local entry={id=id,name=name,unit=unit,startAttack=startAttack,petAttack=petAttack};byName[name]=entry;candidates[#candidates+1]=entry
    end
    local catalog=ns.classes[class]
    local specs=class=="HUNTER" and S.hunterSpecs or catalog and catalog.specs or {}
    for _,spec in ipairs(specs) do
        local info=S.readableCall(S.spellAPI.GetSpellInfo,spec.name)
        local unit=spec.unit or "target"
        add(S.safeField(info,"spellID"),spec.name,unit,true,spec.startAttack,spec.petAttack)
    end
    if class=="HUNTER" then for _,spec in ipairs(ns.playerBuffSpecs or {}) do add(spec.spellID,spec.name,"player",true) end end
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
    if class=="PALADIN" then candidates[#candidates+1]={id=0,name="Hand Helper Stop Casting",unit="player",stopCasting=true} end
    return candidates,class
end
function M.refresh()
    if not M.available() or S.readableCall(InCombatLockdown)~=false or M.refreshing then return false end
    M.refreshing=true
    if not M.owner then M.owner=CreateFrame("Frame",nil,UIParent) end
    local candidates,class=M.catalog()
    local signature={class or ""}
    for _,candidate in ipairs(candidates) do signature[#signature+1]=candidate.name..":"..candidate.id..":"..candidate.unit..":"..tostring(candidate.petAttack==true) end
    signature=table.concat(signature,"|")
    local changed=signature~=M.signature or M.retry
    M.retry=false
    for _,entry in pairs(M.entries) do if entry.active and not M.current(entry) then changed=true end end
    if changed then
        ClearOverrideBindings(M.owner)
        for _,entry in pairs(M.entries) do entry.active=false;entry.button:SetAttribute("type",nil) end
        for _,candidate in ipairs(candidates) do
            local family=class..":"..candidate.name
            local entry=M.entries[family]
            if not entry and M.nextSlot<400 then
                local name="HandHelperClassSpell"..M.nextSlot
                local button=CreateFrame("Button",name,UIParent,"SecureActionButtonTemplate")
                button:SetSize(1,1);button:SetPoint("TOPLEFT",UIParent,"TOPLEFT",-10000,10000);button:SetAlpha(0)
                button:RegisterForClicks("AnyDown","AnyUp");button:SetAttribute("useOnKeyDown",true)
                button:SetAttribute("checkselfcast",false);button:SetAttribute("checkfocuscast",false);button:SetAttribute("checkmouseovercast",false)
                entry={managed=true,kind="spell",slot=M.nextSlot,button=button,action="CLICK "..name..":LeftButton",buttonName=name}
                M.nextSlot=M.nextSlot+1;M.entries[family]=entry
            end
            if entry then
                if entry.key and (ns.keyPolicy.reason(entry.key) or bindingAction(entry.key,false)~="" or bindingAction(entry.key,true)~="") then entry.key=nil end
                if not entry.key then
                    for _,key in ipairs(M.keys) do
                        if not M.reserved[key] and not ns.keyPolicy.reason(key) and bindingAction(key,false)=="" and bindingAction(key,true)=="" then entry.key=key;M.reserved[key]=family;break end
                    end
                end
                entry.id=candidate.id;entry.spellID=candidate.id;entry.name=candidate.name;entry.unit=candidate.unit;entry.invalidated=nil;entry.startAttack=candidate.startAttack;entry.stopCasting=candidate.stopCasting;entry.petAttack=candidate.petAttack
                entry.button:SetAttribute("spell",candidate.id>0 and candidate.id or nil);entry.button:SetAttribute("unit",candidate.unit)
                -- One secure click commands the pet before the attack. This
                -- also covers target changes while Mark is rate-limited; the
                -- app never waits for pet arrival or a separate pet receipt.
                local macro=candidate.stopCasting and "/stopcasting" or candidate.startAttack and "/startattack [harm,nodead]"
                    or candidate.petAttack and ("/petattack [@target,harm,nodead]\n/cast [@target,harm,nodead] "..candidate.name) or nil
                entry.button:SetAttribute("macrotext",macro)
                if entry.key then
                    local ok=pcall(SetOverrideBindingClick,M.owner,false,entry.key,entry.buttonName,"LeftButton")
                    entry.active=ok and bindingAction(entry.key,false)=="" and bindingAction(entry.key,true)==entry.action
                end
                entry.button:SetAttribute("type",entry.active and (macro and "macro" or "spell") or nil)
                if not entry.active then M.retry=true end
            end
        end
        M.signature=signature;M.revision=M.revision+1
    end
    M.refreshing=false
    return true
end
function M.export(bindingTiles)
    local result={}
    for _,entry in pairs(M.entries) do if entry.id>0 and M.current(entry) then result[#result+1]=entry end end
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
    S.bindingDiagnostics={"Managed class spells: "..#result.." / revision "..M.revision.."; player bars/macros are independent"}
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
function S.discoverBindings()
    if M.refreshing then return end
    if ns.markSetupDirty then ns.markSetupDirty() end
    if S.readableCall(InCombatLockdown) ~= false then return end
    S.bindingsValid = false
    S.bindingDiagnostics = {}
    S.setupMappings = {}
    local bindingTiles={}
    for _,tile in ipairs(S.tiles) do bindingTiles[#bindingTiles+1]=tile end
    for _,tile in ipairs(ns.playerBuffSpecs or {}) do bindingTiles[#bindingTiles+1]=tile end
    for _, tile in ipairs(bindingTiles) do tile.mappings = {} end
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
SLASH_HANDHELPERKEYS1="/hhkeys"
SlashCmdList.HANDHELPERKEYS=function(text)
    local action,key=(text or ""):match("^%s*(%S+)%s*(.-)%s*$")
    action=action and action:lower() or "list"
    if action=="block" or action=="unblock" then
        if S.readableCall(InCombatLockdown)~=false then print("Hand Helper: change shortcut exclusions outside combat.");return end
        key=ns.keyPolicy.canonical(key)
        if not key then print("Hand Helper: use /hhkeys block CTRL+ALT+SHIFT+G");return end
        if type(HandHelperProbeDB)~="table" then HandHelperProbeDB={} end
        if type(HandHelperProbeDB.keyBlacklist)~="table" then HandHelperProbeDB.keyBlacklist={} end
        HandHelperProbeDB.keyBlacklist[key]=action=="block" and true or nil
        M.retry=true
        S.discoverBindings()
        print("Hand Helper: "..key.." / "..(ns.keyPolicy.reason(key) or "not excluded"));return
    end
    if action~="list" then print("Hand Helper: /hhkeys list | block KEY | unblock KEY. Turn casting OFF before changing exclusions.");return end
    print("Hand Helper: blocks two-modifier letter shortcuts, Windows keys and common system/app shortcuts. Turn casting OFF before edits.")
    local keys={}
    for key in pairs(ns.keyPolicy.defaults) do keys[#keys+1]=key end
    local custom=type(HandHelperProbeDB)=="table" and HandHelperProbeDB.keyBlacklist or {}
    for key in pairs(type(custom)=="table" and custom or {}) do if not ns.keyPolicy.defaults[key] then keys[#keys+1]=key end end
    table.sort(keys);for _,key in ipairs(keys) do print(key.." / "..ns.keyPolicy.reason(key)) end
end
