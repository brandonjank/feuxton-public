-- Shared addon namespace. Keep this file first in the TOC.
local addonName, ns = ...
ns.addonName = addonName
ns.version = "0.70.0"
ns.state = {bridgeLabels={}}
function ns.state.bridgeLabel(label) ns.state.bridgeLabels[#ns.state.bridgeLabels+1]=label end
ns.classes = {}
ns.features = {}

-- Shared delivery policy. WoW cannot enumerate other applications' global
-- hotkeys, so an empty GetBindingAction is not enough to call a key unused.
local K={defaults={
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
function K.reason(key)
    key=K.canonical(key)
    if not key then return "Invalid shortcut" end
    if key:find("WIN-",1,true)==1 then return "Windows shortcut" end
    if type(FeuxtonDB)=="table" and type(FeuxtonDB.keyBlacklist)=="table" and FeuxtonDB.keyBlacklist[key] then return "User blacklist" end
    if K.defaults[key] then return K.defaults[key] end
    if key:match("^ALT%-CTRL%-[A-Z]$") or key:match("^ALT%-SHIFT%-[A-Z]$") or key:match("^CTRL%-SHIFT%-[A-Z]$") then return "Two-modifier letter shortcuts reserved for other apps" end
end
