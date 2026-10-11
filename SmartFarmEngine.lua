-- Experimental coordinator. Step is deterministic; no forced release of unresolved work.
local Engine = {}
local adapters, config, logger, alive, worker, generation, busy
local queue, owner, transition, history, profiles, serial, bootMode, subscription
local metrics, inFlightStarts
local MODES = {item=true, quest=true, npc=true, stand=true, prestige=true, hop=true}
local BOOLS = {AutoSell=true, BuyLucky=true, AutoChooseQuest=true, StandFarmAutoRestock=true,
    StandFarmRestockHop=true, StandFarmResumeAfterHop=true}
local TEXTS = {SelectedQuest=true, SelectedNPC=true, StandFarmTarget=true}
local LISTS = {StandFarmTargets=true, StandFarmSkinTargets=true}
local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}; for k,v in pairs(value) do result[k]=copy(v) end; return result
end
local function finite(n, lo, hi)
    return type(n)=='number' and n==n and n>=lo and n<=hi
end
local function cleanTask(raw)
    if type(raw)~='table' or not MODES[raw.mode] then return nil, 'invalid_mode' end
    local allowed={mode=true,priority=true,timeout=true,stall=true,retries=true,goal=true,settings=true}
    for key in pairs(raw) do if not allowed[key] then return nil,'unknown_task_field' end end
    local t={mode=raw.mode,priority=raw.priority==nil and 0 or raw.priority,timeout=raw.timeout==nil and 1800 or raw.timeout,
        stall=raw.stall==nil and 180 or raw.stall,retries=raw.retries==nil and 0 or raw.retries,goal=raw.goal==nil and 0 or raw.goal,settings={}}
    if not finite(t.priority,0,100) or not finite(t.timeout,10,86400)
        or not finite(t.stall,0,3600) or (t.stall>0 and t.stall<30)
        or not finite(t.retries,0,2) or t.retries%1~=0 or not finite(t.goal,0,100000)
        or t.goal%1~=0 then return nil,'invalid_limits' end
    if raw.settings~=nil and type(raw.settings)~='table' then return nil,'invalid_settings' end
    for key,value in pairs(raw.settings or {}) do
        if BOOLS[key] then
            if type(value)~='boolean' then return nil,'invalid_boolean' end
        elseif TEXTS[key] then
            if type(value)~='string' or #value>100 or value:find('%c') then return nil,'invalid_text' end
        elseif LISTS[key] then
            if type(value)~='table' or #value>25 then return nil,'invalid_list' end
            local count=0
            for i,name in pairs(value) do
                count=count+1
                if type(i)~='number' or i%1~=0 or i<1 or i>#value or type(name)~='string'
                    or #name==0 or #name>100 or name:find('%c') then return nil,'invalid_list' end
            end
            if count~=#value then return nil,'invalid_list' end
        elseif key=='StandFarmMode' then
            if value~='stand' and value~='shiny' then return nil,'invalid_stand_mode' end
        elseif key=='StandFarmConsumable' then
            if value~='Mysterious Arrow' and value~="Rib Cage of The Saint's Corpse" then return nil,'invalid_source' end
        elseif key=='StandFarmPityLimit' then
            if not finite(value,0,125) then return nil,'invalid_pity' end
        elseif key=='StandFarmMaxHops' then
            if not finite(value,1,5) or value%1~=0 then return nil,'invalid_hops' end
        else return nil,'forbidden_setting' end
        t.settings[key]=copy(value)
    end
    return t
end
local function log(reason, mode)
    if logger then pcall(logger.Write,logger,'INFO','SmartFarmEngine',
        '[Engine] '..reason..(mode and (' | mode='..mode) or '')) end
end
local function record(reason, task, now)
    metrics.last_reason=reason
    table.insert(history,{reason=reason,mode=task and task.mode,id=task and task.id,time=now})
    if #history>50 then table.remove(history,1) end
    log(reason,task and task.mode)
end
local function finish(reason,now,retry)
    if not owner or transition then return end
    transition={task=owner,reason=reason,since=now,retry=retry==true}
    owner=nil -- cancellation is visible before calling any yielding module Stop.
    adapters:Stop()
end
function Engine:Init(modules)
    adapters=modules.SmartFarmAdapters; config=modules.Config; logger=modules.RuntimeLog
    queue,history,profiles={}, {}, {}; owner,transition=nil,nil
    inFlightStarts=0
    alive=true; worker=false; generation=(generation or 0)+1; busy=false; serial=0
    metrics={started=0,completed=0,failed=0,retries=0,progress=0,by_mode={},active_seconds=0,last_reason='idle'}
    bootMode=adapters:PrepareBoot()
    log("Build SFE-E1-20261011; experimental coordinator, Roblox validation pending")
    local stored=config:Get('SmartFarmProfiles')
    if type(stored)=='table' then
        local count=0
        for name,tasks in pairs(stored) do
            count=count+1
            if count<=10 then self:SaveProfile(name,tasks,true) end
        end
    end
    if logger and type(logger.Subscribe)=='function' then
        subscription=logger:Subscribe(function(entry)
            if not alive or not owner then return end
            local module=entry.Module or entry.module or entry.moduleName
            local message=tostring(entry.Message or entry.message or '')
            local valid=(owner.mode=='item' and module=='Farm' and message:find('Collected:',1,true))
                or ((owner.mode=='npc' or owner.mode=='quest') and module=='CombatFarm'
                    and message:find('Confirmed death',1,true))
                or (owner.mode=='stand' and module=='StandFarm'
                    and (message:find('Arrow result ',1,true) or message:find('Rib result ',1,true)))
            if valid then self:Progress(owner.id,1) end
        end)
    end
end
function Engine:Enqueue(raw)
    if not alive then return false,'destroyed' end
    if #queue>=20 then return false,'queue_full' end
    local t,reason=cleanTask(raw); if not t then return false,reason end
    serial=serial+1; t.id=serial; t.attempt=0; table.insert(queue,t)
    log('queued',t.mode); return true,t.id
end
function Engine:RequestMode(mode,enabled)
    if not alive then return false,'destroyed' end
    if not MODES[mode] then return false,'invalid_mode' end
    if enabled==false then
        if transition and transition.task.mode==mode then transition.retry=false end
        for i=#queue,1,-1 do if queue[i].mode==mode then table.remove(queue,i) end end
        if owner and owner.mode==mode then generation=generation+1; finish('user_stop',os.clock(),false) end
        if mode=='stand' and not owner then adapters:StopStand() end
        return true
    end
    local t,reason=cleanTask({mode=mode,timeout=86400,stall=0})
    if not t then return false,reason end
    generation=generation+1
    queue={}; serial=serial+1; t.id=serial; t.attempt=0; queue[1]=t
    if owner then finish('mode_switch',os.clock(),false) else adapters:Stop() end
    return true,'queued'
end
function Engine:Cancel(id)
    if owner and owner.id==id then generation=generation+1 end
    for i,t in ipairs(queue) do if t.id==id then table.remove(queue,i); return true end end
    if owner and owner.id==id then finish('cancelled',os.clock(),false); return true end
    if transition and transition.task.id==id then transition.retry=false; return true end
    return false,'not_found'
end
function Engine:StopAll()
    generation=generation+1; queue={}
    if transition then transition.retry=false; transition.reason='user_stop' end
    if owner then finish('user_stop',os.clock(),false) else adapters:Stop() end
    metrics.last_reason='user_stop'; log('user_stop')
end
function Engine:Progress(id,count)
    if not owner or owner.id~=id or not finite(count or 1,1,10000) then return false end
    owner.progress=owner.progress+(count or 1); owner.lastProgress=os.clock()
    metrics.progress=metrics.progress+(count or 1)
    metrics.by_mode[owner.mode]=(metrics.by_mode[owner.mode] or 0)+(count or 1); return true
end
function Engine:SaveProfile(name,tasks,noSave)
    if type(name)~='string' or #name<1 or #name>40 or name:find('%c') or type(tasks)~='table'
        or #tasks<1 or #tasks>20 then return false,'invalid_profile' end
    local result={}; local count=0
    for i,raw in pairs(tasks) do
        count=count+1
        if type(i)~='number' or i%1~=0 or i<1 or i>#tasks then return false,'invalid_profile' end
        local t,reason=cleanTask(raw); if not t then return false,reason end
        result[i]=t
    end
    if count~=#tasks then return false,'invalid_profile' end
    local total=0; for _ in pairs(profiles) do total=total+1 end
    if not profiles[name] and total>=10 then return false,'profile_limit' end
    profiles[name]=result
    if not noSave then config:Set('SmartFarmProfiles',copy(profiles)) end
    return true
end
function Engine:DeleteProfile(name)
    if not profiles[name] then return false,'not_found' end
    profiles[name]=nil; config:Set('SmartFarmProfiles',copy(profiles)); return true
end
function Engine:RunProfile(name)
    if not profiles[name] then return false,'not_found' end
    if #queue+#profiles[name]>20 then return false,'queue_full' end
    -- Validated again; append atomically, never start work while editing config.
    local staged={}
    for _,raw in ipairs(profiles[name]) do local t,r=cleanTask(raw); if not t then return false,r end; staged[#staged+1]=t end
    for _,t in ipairs(staged) do self:Enqueue(t) end
    return true
end
function Engine:BuildTask(mode,limits)
    local task=copy(limits or {}); task.mode=mode; task.settings={}
    local keys={}
    if mode=='item' then keys={'AutoSell','BuyLucky'}
    elseif mode=='quest' then keys={'SelectedQuest','AutoChooseQuest'}
    elseif mode=='npc' then keys={'SelectedNPC'}
    elseif mode=='stand' then keys={'StandFarmTarget','StandFarmTargets','StandFarmSkinTargets',
        'StandFarmMode','StandFarmConsumable','StandFarmPityLimit','StandFarmMaxHops',
        'StandFarmAutoRestock','StandFarmRestockHop','StandFarmResumeAfterHop'} end
    for _,key in ipairs(keys) do task.settings[key]=copy(config:Get(key)) end
    return cleanTask(task)
end
function Engine:SaveQueueProfile(name)
    if transition then return false,'release_pending' end
    local tasks={}
    if owner then
        local t=owner
        local settings=copy(t.settings)
        if next(settings)==nil then
            local snapshot=self:BuildTask(t.mode)
            if snapshot then settings=snapshot.settings end
        end
        tasks[1]={mode=t.mode,priority=t.priority,timeout=t.timeout,stall=t.stall,retries=t.retries,
            goal=t.goal,settings=settings}
    end
    for _,t in ipairs(queue) do
        tasks[#tasks+1]={mode=t.mode,priority=t.priority,timeout=t.timeout,stall=t.stall,
            retries=t.retries,goal=t.goal,settings=copy(t.settings)}
    end
    return self:SaveProfile(name,tasks)
end
function Engine:SetItemPreference(key,value) return adapters:SetItemPreference(key,value) end
function Engine:ClearQueue() queue={} end
function Engine:GetStatus()
    return {state=transition and 'releasing' or (owner and 'running' or 'idle'),
        owner=copy(owner),queue=copy(queue),history=copy(history),metrics=copy(metrics),
        profiles=copy(profiles),blocked=(not owner or transition) and adapters:GetBlockReason() or nil}
end
function Engine:Step(now)
    if not alive or busy then return end
    busy=true
    local epoch=generation
    local ok,err=pcall(function()
        if transition then
            local quiet,reason=adapters:IsQuiet()
            if inFlightStarts>0 then quiet=false; reason="start_pending" end
            if not quiet then
                metrics.last_reason='release_pending:'..tostring(reason)
                if now-transition.since>=20 and not transition.warned then
                    transition.warned=true; record('release_timeout:'..tostring(reason),transition.task,now)
                    -- Keep ownership fence: timeout never authorizes another farm.
                end
                return
            end
            local old=transition; transition=nil
            if adapters.Release then adapters:Release() end
            record(old.reason,old.task,now)
            if old.reason=='goal_reached' or old.reason=='module_completed' then metrics.completed=metrics.completed+1
            elseif old.reason~='user_stop' and old.reason~='mode_switch' and old.reason~='cancelled' then metrics.failed=metrics.failed+1 end
            if old.retry and old.task.attempt<old.task.retries and #queue<20 then
                local t=old.task; t.attempt=t.attempt+1; t.notBefore=now+5
                t.started=nil; t.progress=nil; t.lastProgress=nil; t.lastTick=nil
                table.insert(queue,t); metrics.retries=metrics.retries+1
            end
        end
        if owner then
            if owner.starting then
                if now-owner.started>=owner.timeout then finish('start_timeout',now,true) end
                return
            end
            local delta=math.max(0,now-(owner.lastTick or now)); owner.lastTick=now
            metrics.active_seconds=metrics.active_seconds+delta
            local running,reason=adapters:Running(owner.mode)
            if not running then finish(reason or 'module_completed',now,false)
            elseif owner.goal>0 and owner.progress>=owner.goal then finish('goal_reached',now,false)
            elseif now-owner.started>=owner.timeout then finish('task_timeout',now,true)
            elseif owner.stall>0 and now-owner.lastProgress>=owner.stall then finish('progress_timeout',now,true) end
            return
        end
        -- Adopt the explicitly authorized Stand-owned transfer recovery; never duplicate it.
        local external=adapters:ExternalMode()
        if external then
            serial=serial+1
            owner={id=serial,mode=external,priority=0,timeout=86400,stall=0,retries=0,goal=0,
                settings={},attempt=0,started=now,lastProgress=now,lastTick=now,progress=0}
            record('adopted_existing_owner',owner,now); return
        end
        local quiet=adapters:IsQuiet(); if not quiet or #queue==0 then return end
        local index=nil
        for i,t in ipairs(queue) do
            if (not t.notBefore or now>=t.notBefore) and (not index or t.priority>queue[index].priority) then index=i end
        end
        if not index then return end
        local t=table.remove(queue,index)
        owner=t; t.started=now; t.lastProgress=now; t.lastTick=now; t.progress=0
        t.starting=true; inFlightStarts=inFlightStarts+1
        task.spawn(function()
            local called,started,reason=pcall(adapters.Start,adapters,t.mode,t.settings)
            inFlightStarts=inFlightStarts-1; t.starting=false
            -- A delayed HTTP/skin response cannot resurrect a cancelled task.
            if not alive or epoch~=generation or owner~=t then
                adapters:Stop()
                if not transition then transition={task=t,reason='cancelled',since=os.clock(),retry=false} end
                return
            end
            if not called then
                record('engine_error',t,os.clock()); queue={}; finish('engine_error',os.clock(),false)
            elseif not started then finish('start_denied:'..tostring(reason),os.clock(),false)
            else metrics.started=metrics.started+1; record('started',t,os.clock()) end
        end)
    end)
    busy=false
    if not ok then
        record('engine_error',owner,now)
        queue={}; if owner then finish('engine_error',now,false) else adapters:Stop() end
        if logger then pcall(logger.Write,logger,'WARN','SmartFarmEngine','Engine halted after adapter error') end
    end
end
function Engine:CanRecoverTransfer() return bootMode==nil end
function Engine:Start()
    if worker or not alive then return end
    worker=true
    if not adapters:ExternalMode() and bootMode then self:Enqueue({mode=bootMode,timeout=86400,stall=0}) end
    task.spawn(function()
        while alive do self:Step(os.clock()); task.wait(0.25) end
        worker=false
    end)
end
function Engine:Destroy()
    self:StopAll(); alive=false
    local env=getgenv and getgenv() or _G
    env.__WhiteHubEngineReleaseFence={job=game.JobId,place=game.PlaceId,
        released=function() return inFlightStarts==0 and adapters:IsQuiet() end}
    if subscription then
        if type(subscription)=='function' then pcall(subscription)
        elseif subscription.Disconnect then pcall(function() subscription:Disconnect() end) end
    end
    subscription=nil
    if adapters.Destroy then adapters:Destroy() end
end
return Engine
