-- Shared secure pet commands. Pet abilities and autocast stay player controlled.
local _,ns=...
local P={key="warlock.petAttack",name="Feuxton Pet Attack"}
ns.features.PetSupport=P

function P.candidate(class)
    if class~="WARLOCK" then return nil end
    -- A command has no player spell ID and never pretends to be Attack (6603).
    return {id=0,name=P.name,unit="target",petCommand=true}
end

function P.bytes()
    local S=ns.state
    local class=S.readableCall(function()local _,key=UnitClass("player");return key end)
    local M=S.managedSpells
    local entry=M and M.entries["WARLOCK:"..P.name]
    local valid=class=="WARLOCK" and S.bindingsValid and M and M.current(entry)
        and entry.petCommand==true and entry.id==0 and entry.unit=="target"
    return S.bytes(valid and S.compactBindingCode(entry.key) or 0,2)..S.bytes(S.spellUseCode(P.key),1)
end
