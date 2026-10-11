-- Shared addon namespace. Keep this file first in the TOC.
local addonName, ns = ...
ns.addonName = addonName
ns.version = "0.80.0"
ns.state = {bridgeLabels={}}
function ns.state.bridgeLabel(label) ns.state.bridgeLabels[#ns.state.bridgeLabels+1]=label end
ns.classes = {}
ns.features = {}

-- Shared delivery policy. WoW cannot enumerate other applications' global
-- hotkeys, so an empty GetBindingAction is not enough to call a key unused.
local K={defaults={
    ["ALT-CTRL-SHIFT-C"]="Reported desktop notification shortcut conflict",
    ["ALT-F1"]="Graphics screenshot shortcut",["ALT-F2"]="Graphics photo shortcut",
    ["ALT-F8"]="Password display shortcut",["ALT-F9"]="Graphics recording shortcut",["ALT-F10"]="Graphics replay shortcut",
    ["ALT-F12"]="Graphics overlay shortcut",["CTRL-F12"]="Graphics / print shortcut",
    ["ALT-R"]="Graphics overlay shortcut",["ALT-Z"]="Graphics overlay shortcut",
    ["CTRL-SHIFT-C"]="Camera / reported notification shortcut",
    ["CTRL-SHIFT-D"]="Discord deafen shortcut",["CTRL-SHIFT-M"]="Microphone / Discord mute shortcut",
    ["CTRL-SHIFT-E"]="Graphics screenshot shortcut",["CTRL-SHIFT-G"]="Graphics streaming shortcut",
    ["CTRL-SHIFT-O"]="Graphics metrics shortcut",["CTRL-SHIFT-R"]="Graphics recording shortcut",["CTRL-SHIFT-S"]="Graphics replay shortcut",
    ["ALT-CTRL-G"]="Google Drive search",
    ["ALT-F4"]="Close application",["CTRL-F4"]="Close document",
    ["ALT-SHIFT-F4"]="Close application variant",
    ["ALT-CTRL-F12"]="Graphics control shortcut",
    ["CTRL-SHIFT-F12"]="Common print shortcut",
    ["ALT-SPACE"]="Window menu / application launcher",
    ["CTRL-SPACE"]="Input language / application shortcut",
    ["ALT-TAB"]="Switch application",["ALT-SHIFT-TAB"]="Switch application",
    ["ALT-CTRL-DELETE"]="Windows security",
    ["CTRL-SHIFT-ESCAPE"]="Task Manager",
}}
-- Reserve the whole Alt/function family: closing, window, graphics and OEM
-- handlers may ignore additional modifiers. Do not enumerate just one variant.
for i=1,12 do local key="ALT-F"..i;K.defaults[key]=K.defaults[key] or "Alt function shortcuts reserved for Windows / overlays" end
ns.keyPolicy=K
function K.canonical(key)
    if type(key)~="string" or #key>80 then return nil end
    key=key:upper():gsub("%s",""):gsub("%+","-")
    local mods={}
    while true do
        local mod=key:match("^(ALT)%-") or key:match("^(CTRL)%-") or key:match("^(SHIFT)%-") or key:match("^(WIN)%-")
        if not mod then break end
        if mods[mod] then return nil end
        mods[mod]=true;key=key:sub(#mod+2)
    end
    if key=="" or #key>16 then return nil end
    if key=="ESC" then key="ESCAPE" end
    return (mods.WIN and "WIN-" or "")..(mods.ALT and "ALT-" or "")..(mods.CTRL and "CTRL-" or "")..(mods.SHIFT and "SHIFT-" or "")..key
end
function K.parts(key)
    key=K.canonical(key);if not key then return nil end
    local mask=0
    for _,mod in ipairs({{"WIN-",8},{"ALT-",1},{"CTRL-",2},{"SHIFT-",4}}) do
        if key:sub(1,#mod[1])==mod[1] then mask=mask+mod[2];key=key:sub(#mod[1]+1) end
    end
    return key,mask
end
local function contains(mask,required)
    for _,bit in ipairs({1,2,4,8}) do if math.floor(required/bit)%2==1 and math.floor(mask/bit)%2~=1 then return false end end
    return true
end
local shortcutRules={}
for shortcut,reason in pairs(K.defaults) do local base,mask=K.parts(shortcut);shortcutRules[#shortcutRules+1]={base,mask,reason} end
function K.builtinReason(key)
    local base,mask=K.parts(key)
    if not base then return "Invalid shortcut" end
    if mask>=8 then return "Windows shortcut" end
    -- Additional modifiers never make a known OS/global shortcut safe.
    for _,rule in ipairs(shortcutRules) do if base==rule[1] and contains(mask,rule[2]) then return rule[3] end end
    if base:match("^[A-Z]$") and (mask==3 or mask==5 or mask==6) then return "Two-modifier letter shortcuts reserved for other apps" end
end
function K.reason(key)
    local reason=K.builtinReason(key);if reason then return reason end
    local base,mask=K.parts(key)
    if type(FeuxtonDB)=="table" and type(FeuxtonDB.keyBlacklist)=="table" then
        for shortcut,blocked in pairs(FeuxtonDB.keyBlacklist) do
            local rule,required=K.parts(shortcut)
            if blocked and rule and base==rule and contains(mask,required) then return "User blacklist" end
        end
    end
end

function ns.state.compactBindingCode(key)
    if type(key)~="string" then return 0 end
    key=string.upper(key);local flags=0
    while true do
        local bit,prefix
        if key:sub(1,4)=="ALT-" then bit,prefix=1,4 elseif key:sub(1,5)=="CTRL-" then bit,prefix=2,5 elseif key:sub(1,6)=="SHIFT-" then bit,prefix=4,6 else break end
        if math.floor(flags/bit)%2==1 then return 0 end
        flags=flags+bit;key=key:sub(prefix+1)
    end
    local code=#key==1 and key:byte() or 0
    if not (code>=65 and code<=90 or code>=48 and code<=57) then
        local fn=tonumber(key:match("^F(%d+)$"));local special={SPACE=32,["-"]=189,["="]=187,["["]=219,["]"]=221,[";"]=186,["'"]=222,[","]=188,["."]=190,["/"]=191}
        local pad=tonumber(key:match("^NUMPAD(%d)$"))
        code=pad and 96+pad or fn and fn>=1 and fn<=12 and 111+fn or special[key] or 0
    end
    return code>0 and flags*256+code or 0
end
