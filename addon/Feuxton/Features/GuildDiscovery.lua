-- Bounded social discovery only. No timer/event sends queries or invitations.
-- Who requests are executed by GuildRecruitment's existing native-click key.
local _,ns=...
local D={rows={},count=0,nextScan=0,nextWho=0,whoStatus=0}
ns.features.GuildDiscovery=D
local statKeys={"attempts","confirmed","joins","declines","welcomes","whoQueries","whoReplies"}
D.statisticsKeys=statKeys
function D.statistics(context,key)
    if not context or not context.ledger or not context.utc then return nil end
    local stats=context.ledger.statistics
    if stats==nil then
        stats={schema=1,since=context.utc};for _,name in ipairs(statKeys)do stats[name]=0 end
        context.ledger.statistics=stats
    end
    if type(stats)~="table"or stats.schema~=1 or type(stats.since)~="number"or stats.since<0 or stats.since>context.utc then return nil end
    for _,name in ipairs(statKeys)do local v=stats[name];if type(v)~="number"or v<0 or v>2147483647 or v~=math.floor(v)then return nil end end
    if key then for _,name in ipairs(statKeys)do if name==key then stats[name]=math.min(2147483647,stats[name]+1);break end end end
    return stats
end
local function public(v)
    if type(issecretvalue)~="function"then return false end
    local ok,secret=pcall(issecretvalue,v);return ok and not secret
end
local function read(fn,...)
    if type(fn)~="function"then return nil end
    local ok,v=pcall(fn,...);if ok and public(v)then return v end
end
local function shown(frame)return frame and read(frame.IsShown,frame)==true end
local function whoOpen()
    return shown(WhoFrame)and(not FriendsFrame or shown(FriendsFrame))
        or shown(LFGWhoListFrame)and(not LFGParentFrame or shown(LFGParentFrame))
end
local function zone()return read(GetRealZoneText)end
local function restoreWhoUI()
    local lease=D.whoUI;if not lease then return true end
    for frame in pairs(lease.frames)do
        local ok=pcall(frame.RegisterEvent,frame,"WHO_LIST_UPDATE")
        if ok and read(frame.IsEventRegistered,frame,"WHO_LIST_UPDATE")==true then lease.frames[frame]=nil end
    end
    if not next(lease.frames)then D.whoUI=nil;return true end
    return false
end
function D.cancelWho()
    D.pending=nil;D.plan=nil;restoreWhoUI()
end
-- Both native Who result handlers open panels. Temporarily release only that
-- event, retaining its scripts, other events and the global Who routing mode.
local function quietWhoUI(at)
    if D.whoUI and not restoreWhoUI()then return false end
    local lease={frames={},expires=at+15};D.whoUI=lease;local found=false
    for _,name in ipairs({"FriendsFrame","LFGWhoListFrame"})do
        local frame=_G[name]
        if frame then
            found=true
            if type(frame.RegisterEvent)~="function"or type(frame.UnregisterEvent)~="function"then restoreWhoUI();return false end
            local registered=read(frame.IsEventRegistered,frame,"WHO_LIST_UPDATE")
            if registered==true then
                lease.frames[frame]=true
                local ok=pcall(frame.UnregisterEvent,frame,"WHO_LIST_UPDATE")
                if not ok or read(frame.IsEventRegistered,frame,"WHO_LIST_UPDATE")~=false then restoreWhoUI();return false end
            elseif registered~=false then restoreWhoUI();return false end
        end
    end
    if not next(lease.frames)then D.whoUI=nil end
    return found
end
function D.addonLoaded()
    if D.pending and not quietWhoUI(D.pending.at)then D.cancelWho();D.whoStatus=5 end
end
function D.maintain()
    local at=read(GetTime)
    if type(at)~="number"then return end
    if D.pending and whoOpen()then
        D.cancelWho();D.whoStatus=3;D.nextWho=math.max(D.nextWho,at+60)
    elseif D.pending and(at<D.pending.at or at-D.pending.at>15)then
        D.cancelWho();D.whoStatus=4
    end
    -- Restore on the next coordinated update, never inside WHO_LIST_UPDATE:
    -- registering during dispatch can deliver the same event to FriendsFrame.
    local lease=D.whoUI
    if lease and(lease.release or at>lease.expires or at<lease.expires-15)then restoreWhoUI()end
end
function D.reset(owner)
    D.cancelWho()
    D.owner=owner;D.rows={};D.count=0;D.scan=nil;D.nextScan=0;D.pending=nil;D.whoStatus=0
    -- Query throttling and observed foreign Who ownership survive context changes.
end
function D.remove(name)
    if D.rows[name]then D.rows[name]=nil;D.count=D.count-1 end
end
local function prune(context)
    for name,c in pairs(D.rows)do if context.at<c.seenAt or context.at-c.seenAt>300 then D.remove(name)end end
end
function D.remember(c,context)
    if not c or not c.name or not c.guid then return end
    local old=D.rows[c.name]
    if not old and D.count>=256 then
        local oldest;for _,row in pairs(D.rows)do if not oldest or row.seenAt<oldest.seenAt then oldest=row end end
        if oldest then D.remove(oldest.name)end
    end
    -- An observed unit replaces a name-only Who identity, never its inverse.
    if old and old.guid~=c.guid and c.who then c.guid=old.guid end
    c.seenAt=context.at
    if c.qualified then c.guildAt=context.at end
    if old and not c.qualified then c.guildAt=nil end
    if not old then D.count=D.count+1 end
    D.rows[c.name]=c
end
function D.installWhoObserver()
    if D.hooked then return true end
    local api=C_FriendList
    if type(api)~="table"or type(api.SendWho)~="function"or type(api.GetWhoInfo)~="function"or type(api.GetNumWhoResults)~="function"or type(hooksecurefunc)~="function"then return false end
    local ok=pcall(hooksecurefunc,api,"SendWho",function()
        if not D.sending then
            D.cancelWho();D.whoStatus=3
            local at=read(GetTime);if type(at)=="number"then D.externalUntil=at+60;D.nextWho=math.max(D.nextWho,at+60)end
        end
    end)
    D.hooked=ok;if ok and not D.blocked and D.whoStatus==5 then D.whoStatus=0 end;return ok
end
function D.collect(context,plates,probe,level)
    D.installWhoObserver()
    if not D.scan then
        if context.at<D.nextScan then return end
        prune(context)
        local units={"target","mouseover"};for unit in pairs(plates)do units[#units+1]=unit end
        table.sort(units);D.scan={units=units,index=0};D.nextScan=context.at+.5
    end
    local scan=D.scan
    for _=1,math.min(8,#scan.units-scan.index)do
        scan.index=scan.index+1;local c=probe(scan.units[scan.index],context)
        if c then c.level=level(c.unit);D.remember(c,context)end
    end
    if scan.index>=#scan.units then D.scan=nil end
end
function D.current(c,context,probe,level)
    local row=c and D.rows[c.name]
    if not row or row.guid~=c.guid then return nil end
    if row.unit then
        local exists=read(UnitExists,row.unit);local guid=read(UnitGUID,row.unit)
        if exists~=false and not guid then row.qualified=false;row.guildAt=nil;return nil end
        if guid==row.guid then
            local current=probe(row.unit,context)
            if not current or current.name~=row.name or current.guid~=row.guid then row.qualified=false;row.guildAt=nil;return nil end
            current.level=level(current.unit);D.remember(current,context);row=current
        end
    end
    if D.rows[c.name]~=row or not row.qualified or not row.guildAt or context.at<row.guildAt or context.at-row.guildAt>60 then return nil end
    return row
end
function D.best(context,probe,level,suppressed,before)
    local best
    for _,row in pairs(D.rows)do
        if row.qualified and row.guildAt and context.at>=row.guildAt and context.at-row.guildAt<=60 and not suppressed(context,row)and(not best or before(row,best))then best=row end
    end
    return D.current(best,context,probe,level)
end
function D.whoRequest(context,scope,validText)
    if scope==0 then D.whoStatus=0;return nil end
    if D.blocked or not D.installWhoObserver()then D.whoStatus=5;return nil end
    if D.pending or context.at<D.nextWho or D.externalUntil and context.at<D.externalUntil then return nil end
    local last=context.ledger and context.ledger.lastWhoAt
    if last~=nil then
        if type(last)~="number"or last<0 or last~=math.floor(last)or context.utc<last then D.whoStatus=5;return nil end
        if D.lastWhoOwner~=D.owner and context.utc-last<61 then return nil end
    end
    -- Do not replace a player's active Who search or edit its UI/filter.
    if whoOpen()then D.whoStatus=3;return nil end
    local currentZone=validText(zone(),96)
    if scope==1 and(not currentZone or currentZone:find('["{}]'))then D.whoStatus=5;return nil end
    local plan=D.plan
    if not plan or plan.scope~=scope or plan.zone~=currentZone or #plan.tasks==0 then
        plan={scope=scope,zone=currentZone,tasks={{low=1,high=60,root=true}}};D.plan=plan
    end
    local task=plan.tasks[1]
    local query=scope==1 and 'z-"'..currentZone..'"'or ''
    if scope~=1 or not task.root then query=query..(query~=''and' 'or'')..task.low..'-'..task.high end
    if task.class then query=query..' c-"'..task.class..'"'end
    return {query=query,zone=currentZone,scope=scope,low=task.low,high=task.high,class=task.class}
end
function D.sendWho(context,request,validText)
    local current=D.whoRequest(context,request.scope,validText)
    if not current or current.query~=request.query or current.zone~=request.zone then return false end
    if not quietWhoUI(context.at)then D.whoStatus=5;return false end
    D.nextWho=context.at+60;D.lastWhoOwner=D.owner;context.ledger.lastWhoAt=context.utc
    D.statistics(context,"whoQueries")
    table.remove(D.plan.tasks,1)
    D.pending={at=context.at,owner=D.owner,zone=request.zone,scope=request.scope,request=current,plan=D.plan};D.whoStatus=1
    D.sending=true;local ok=pcall(C_FriendList.SendWho,request.query);D.sending=false
    if not ok or D.blocked then D.cancelWho();D.blocked=true;D.whoStatus=5 end
    return ok and not D.blocked
end
local function field(row,key)return read(function()return row[key]end)end
function D.whoResults(context,validText)
    local pending=D.pending
    if not pending then return end
    D.pending=nil
    if D.whoUI then D.whoUI.release=true end
    if not context or pending.owner~=D.owner or context.at<pending.at or context.at-pending.at>15 then D.plan=nil;return end
    if pending.scope==1 and zone()~=pending.zone then D.plan=nil;D.whoStatus=3;return end
    local ok,count,total=pcall(C_FriendList.GetNumWhoResults)
    if not ok or not public(count)then count=nil end
    if type(count)~="number"or count<0 or count>50 or count~=math.floor(count)then D.whoStatus=5;return end
    D.statistics(context,"whoReplies")
    local capped=count==50 or public(total)and type(total)=="number"and total>count
    local task=pending.request;local plan=pending.plan
    if capped and plan==D.plan then
        if task.low<task.high then
            local mid=math.floor((task.low+task.high)/2)
            table.insert(plan.tasks,1,{low=task.low,high=mid})
            table.insert(plan.tasks,1,{low=mid+1,high=task.high}) -- highest levels first
        elseif not task.class then
            local names={};local seen={}
            -- Class IDs can have holes; the number of classes is not the
            -- largest ID. This is a bounded native enumeration, not a catalog.
            for id=1,32 do
                local name=validText(read(GetClassInfo,id),64)
                if name and not name:find('["{}\\/]')and not seen[name]then seen[name]=true;names[#names+1]=name end
            end
            for index=#names,1,-1 do table.insert(plan.tasks,1,{low=task.low,high=task.high,class=names[index]})end
        end
    end
    D.whoStatus=2
    for index=1,count do
        local info=read(C_FriendList.GetWhoInfo,index)
        if type(info)=="table"then
            local name=validText(field(info,"fullName"),96)
            if name and(name:find('[{}"/]')or name:find("\\",1,true))then name=nil end
            local guild=field(info,"fullGuildName");local area=validText(field(info,"area"),96)
            -- Missing/secret guild strings never mean guildless here.
            if name then
                local suffix="-"..context.realm:gsub("%s","")
                if name:sub(-#suffix)==suffix then name=name:sub(1,-#suffix-1)end
                if guild~=""then
                    if type(guild)=="string"then D.remove(name)end
                elseif name~=context.name and(pending.scope~=1 or area==pending.zone)then
                    local level=field(info,"level")
                    if type(level)~="number"or level<=0 or level>255 or level~=math.floor(level)then level=nil end
                    D.remember({guid="name:"..name,name=name,level=level,qualified=true,who=true},context)
                end
            end
        end
    end
end
function D.rejected(fn)
    if D.sending or D.pending then
        if public(fn)and type(fn)=="string"and fn:find("SendWho",1,true)then D.cancelWho();D.blocked=true;D.whoStatus=5;return true end
    end
end
