-- Current public main-hand evidence. No cached possession or name matching.
local _,ns=...
local E={revision=1}
ns.features.Equipment=E
local function number(value,maximum)
    return not ns.state.isSecret(value) and type(value)=="number" and value>=0 and value==math.floor(value) and value<=(maximum or 2147483647) and value or nil
end
local function instantAPI()
    local S=ns.state
    local api=not S.isSecret(C_Item) and type(C_Item)=="table" and S.safeField(C_Item,"GetItemInfoInstant") or nil
    if not S.isSecret(api) and type(api)=="function"then return api end
    return not S.isSecret(GetItemInfoInstant) and type(GetItemInfoInstant)=="function" and GetItemInfoInstant or nil
end
local function advance()
    E.revision=E.revision%4294967295+1
end
function E.observe()
    local S=ns.state;local state,id,classID,subclassID=0,0,255,255
    if not S.isSecret(GetInventoryItemID) and type(GetInventoryItemID)=="function"then
        local ok,value=pcall(GetInventoryItemID,"player",16)
        if ok and not S.isSecret(value)then
            if value==nil then state=1
            else
                local observed=number(value)
                if observed and observed>0 then
                    state=2;id=observed
                    local api=instantAPI()
                    if api then
                        local values={pcall(api,id)}
                        if values[1]==true and number(values[2])==id then
                            local c,s=number(values[7],254),number(values[8],254)
                            if c~=nil and s~=nil then classID,subclassID=c,s end
                        end
                    end
                end
            end
        end
    end
    -- These previous values only detect changes. They never fill missing reads.
    if state~=0 then
        if E.lastState~=nil and (E.lastState~=state or E.lastItem~=id)then advance()end
        E.lastState,E.lastItem=state,id
    end
    return state,id,classID,subclassID
end
function E.packet(tick)
    local S=ns.state;local state,id,classID,subclassID=E.observe()
    local controls,key=0,""
    local F=ns.features.Fishing
    if state==2 and classID==2 and subclassID==20 and F then controls,key=F.controlsObservation() end
    assert(#key<=24,"fishing controls key capacity")
    local packet=ns.wire.schemas.equipment..S.bytes(S.setupSession,4)..S.bytes(tick,4)..S.bytes(state,1)..S.bytes(id,4)
        ..S.bytes(classID,1)..S.bytes(subclassID,1)..S.bytes(E.revision,4)
        ..S.bytes(controls,1)..S.bytes(#key,1)..key
    return packet..S.bytes(S.adler32(packet),4)
end
local events=CreateFrame("Frame");E.events=events
for _,event in ipairs({"PLAYER_EQUIPMENT_CHANGED","PLAYER_ENTERING_WORLD"})do pcall(events.RegisterEvent,events,event)end
events:SetScript("OnEvent",function(_,event,slot)
    local knownSlot=number(slot,255)
    if event=="PLAYER_ENTERING_WORLD" or knownSlot==nil or knownSlot==16 then advance();E.lastState,E.lastItem=nil,nil end
end)
