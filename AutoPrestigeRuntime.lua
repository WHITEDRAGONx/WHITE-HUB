-- DEV compatibility scope. No scheduler/profiles; tracks only Auto Prestige work.
local Runtime={}
local modules, registered, current, serial, previous
local nativeTask=task
local CANCEL='AP_CANCELLED'
local function log(level,message)
    local logger=modules and modules.RuntimeLog
    if logger then pcall(logger.Write,logger,level,'AutoPrestige',message) end
end
local function player() return game:GetService('Players').LocalPlayer end
local function gui()
    local p=player(); local pg=p and p:FindFirstChild('PlayerGui')
    return pg and pg:FindFirstChild('DialogueGui')
end
local function stat(name)
    local p=player(); local stats=p and p:FindFirstChild('PlayerStats'); local value=stats and stats:FindFirstChild(name)
    return value and value.Value
end
local Context={}; Context.__index=Context
function Context:Active()
    local env=getgenv and getgenv() or _G
    return current==self and self.running and env.__WhiteHubRuntimeId==self.runtime
        and env.AutoPrestigeEnabled==true and modules.Config:Get('AutoPrestige')==true
        and not modules.Config:Get('NPCFarmEnabled') and not modules.Config:Get('QuestFarmEnabled')
        and not modules.Config:Get('StandFarmEnabled')
        and (not modules.Config:Get('FarmEnabled') or self.selling==true)
end
function Context:Check()
    if not self:Active() then error(CANCEL,0) end
    if os.clock()>self.deadline then error('AP_SESSION_TIMEOUT',0) end
end
function Context:Wait(seconds)
    self:Check(); local endAt=os.clock()+(tonumber(seconds) or 0.03)
    repeat nativeTask.wait(math.min(0.1,math.max(0.01,endAt-os.clock()))); self:Check() until os.clock()>=endAt
end
function Context:Until(predicate,seconds,label)
    local deadline=os.clock()+seconds
    repeat self:Check(); if predicate() then return true end; self:Wait(0.05) until os.clock()>=deadline
    error('AP_TIMEOUT:'..label,0)
end
function Context:Invoke(remote,...)
    self:Check(); if not remote then error('AP_REMOTE_MISSING',0) end
    if remote.Name=='RemoteFunction' and remote.Parent~=player().Character then error('AP_STALE_CHARACTER_REMOTE',0) end
    self.calls=self.calls+1
    local result=table.pack(pcall(remote.InvokeServer,remote,...)); self.calls=self.calls-1
    self:Check(); if not result[1] then error('AP_REMOTE_FAILED',0) end
    return table.unpack(result,2,result.n)
end
function Context:Fire(remote,...)
    self:Check(); if not remote then error('AP_REMOTE_MISSING',0) end
    remote:FireServer(...)
end
function Context:Spawn(callback,...)
    if not self:Active() then return end
    self.tasks=self.tasks+1; local args=table.pack(...)
    return nativeTask.spawn(function()
        local ok,reason=pcall(function() self:Check(); callback(table.unpack(args,1,args.n)) end)
        self.tasks=self.tasks-1
        if not ok and reason~=CANCEL and self:Active() then self.reason=tostring(reason):sub(1,180); Runtime:Stop(self.reason) end
    end)
end
function Context:Connect(signal,callback)
    self:Check()
    local connection=signal:Connect(function(...) if self:Active() then self:Spawn(callback,...) end end)
    self.connections[#self.connections+1]=connection; return connection
end
function Context:Track(object) self.objects[#self.objects+1]=object; return object end
function Context:Fingerprint()
    local parts={tostring(stat('Level')),tostring(stat('Prestige')),tostring(stat('Stand')),
        tostring(stat('Spec')),tostring(stat('Money')),tostring(stat('QuestProgress')),tostring(stat('QuestMaxProgress'))}
    local p=player(); local pg=p and p:FindFirstChild('PlayerGui')
    local panel=pg and pg:FindFirstChild('Quests',true)
    for _,child in ipairs(panel and panel:GetChildren() or {}) do parts[#parts+1]=child.Name end
    table.sort(parts); return table.concat(parts,'|')
end
function Context:QuestFingerprint()
    local parts={tostring(stat('QuestProgress')),tostring(stat('QuestMaxProgress'))}
    local panel=player().PlayerGui:FindFirstChild('Quests',true)
    for _,q in ipairs(panel and panel:GetChildren() or {}) do
        parts[#parts+1]=q.Name
        for _,child in ipairs(q:GetDescendants()) do
            if child:IsA('TextLabel') then parts[#parts+1]=tostring(child.Text):sub(1,150) end
        end
    end
    table.sort(parts); return table.concat(parts,'|')
end
function Context:StorySource()
    local panel=player().PlayerGui:FindFirstChild('Quests',true)
    local candidates={}; local any=false; local questNames={}
    for _,quest in ipairs(panel and panel:GetChildren() or {}) do
        if not quest:IsA('UIListLayout') and not quest:IsA('UIPadding') then
            any=true; questNames[#questNames+1]=quest.Name:sub(1,100)
            for _,key in ipairs({'NPC','NPCName','QuestGiver','DialogueNPC','Source'}) do
                local attr=quest.GetAttribute and quest:GetAttribute(key)
                local object=quest:FindFirstChild(key,true); local stored
                if object then pcall(function() stored=object.Value end) end
                local value=attr or stored
                if type(value)=='string' and value~='' then candidates[value]=true end
            end
            local id=quest.Name:match('Storyline%s*(#%d+)')
            if id then candidates['Storyline '..id]=true end
        end
    end
    local source=nil
    for name in pairs(candidates) do
        if source and source~=name then error('AP_STORY_SOURCE_AMBIGUOUS',0) end
        source=name
    end
    if source then return source end
    if not any then return 'Storyline #1' end
    if self.storySource then return self.storySource end
    self:Log('WARN','Story quest source not identified; active quests: '..table.concat(questNames,' | '):sub(1,500))
    error('AP_STORY_SOURCE_UNKNOWN: export quest/NPC runtime log; no blind dialogue sweep',0)
end
function Context:Dialogue(npc,options,confirm,label)
    self:Check(); if self.pending then error('AP_RESULT_PENDING',0) end
    local ok,reason=modules.PrestigeDialogue:Run(self,npc,options,confirm,label)
    if not ok then error('AP_DIALOGUE:'..tostring(reason),0) end
    if label and label:sub(1,6)=='Story ' then self.storySource=npc end
    log('INFO',(label or npc)..' confirmed by player state')
    return true
end
function Context:Consume(name)
    self:Check(); if self.pending or gui() then error('AP_RESULT_OR_DIALOGUE_PENDING',0) end
    if name~='Mysterious Arrow' and name~='Rokakaka' and name~='Requiem Arrow' then error('AP_ITEM_UNSUPPORTED',0) end
    local p=player(); local oldChar=p.Character; local before=stat('Stand')
    if before==nil then error('AP_STAND_UNAVAILABLE',0) end
    if name=='Mysterious Arrow' and before~='None' then error('AP_ARROW_REQUIRES_NONE',0) end
    if name~='Mysterious Arrow' then
        local skin=self:Invoke(oldChar and oldChar:FindFirstChild('RemoteFunction'),'ReturnStandSkin','Stand')
        if skin~='None' then error('AP_SKIN_PROTECTED_OR_UNKNOWN',0) end
        if p.Character~=oldChar or stat('Stand')~=before then error('AP_STATE_CHANGED',0) end
    end
    local limit=tonumber(modules.Config:Get('StandFarmPityLimit')) or 0
    local pity=tonumber(stat('PityCount'))
    if not pity or (limit>0 and pity>=limit) then error('AP_PITY_PROTECTED_OR_UNKNOWN',0) end
    local bag=p:FindFirstChild('Backpack'); local tool=(bag and bag:FindFirstChild(name)) or (oldChar and oldChar:FindFirstChild(name))
    if not tool then error('AP_ITEM_MISSING:'..name,0) end
    if name=='Mysterious Arrow' and self.worthy~=oldChar then
        self:Invoke(oldChar:FindFirstChild('RemoteFunction'),'LearnSkill',{Skill='Worthiness',SkillTreeType='Character'})
        self.worthy=oldChar
    end
    self:Check()
    local hum=oldChar and oldChar:FindFirstChildOfClass('Humanoid')
    if not hum or hum.Health<=0 then error('AP_CHARACTER_NOT_READY',0) end
    hum:EquipTool(tool)
    self:Until(function() return tool.Parent==oldChar end,2,'equip '..name)
    if name~='Mysterious Arrow' then
        local skin=self:Invoke(oldChar:FindFirstChild('RemoteFunction'),'ReturnStandSkin','Stand')
        if skin~='None' or p.Character~=oldChar or stat('Stand')~=before then error('AP_SKIN_OR_STATE_CHANGED',0) end
    end
    local function confirmed()
        local stand=stat('Stand')
        if name=='Rokakaka' then return stand=='None' end
        return stand~=nil and stand~='None' and stand~=before
    end
    local latest=tonumber(stat('PityCount'))
    if not latest or (limit>0 and latest>=limit) then error('AP_PITY_CHANGED_BEFORE_ACTIVATION',0) end
    self.pending={name=name,confirmed=confirmed}
    self:Check(); tool:Activate() -- exactly once; never activate in a detection loop.
    local ok,reason=modules.PrestigeDialogue:Drive(self,confirmed,name,22)
    if not ok then error('AP_CONSUME:'..tostring(reason),0) end
    self.pending=nil
    log('INFO',name..' confirmed by PlayerStats.Stand')
    if name=='Rokakaka' then
        self.pending={name='Rokakaka respawn',confirmed=function()
            local c=p.Character; local h=c and c:FindFirstChildOfClass('Humanoid')
            return c~=oldChar and c and c.Parent and h and h.Health>0
                and c:FindFirstChild('HumanoidRootPart') and c:FindFirstChild('RemoteFunction')
        end}
        self:Until(self.pending.confirmed,20,'NEW Character after Rokakaka')
        self:Wait(1); self.pending=nil; self.worthy=nil
        modules.Movement:Teleport(CFrame.new(978,-42,-49))
    end
    return true
end
function Context:Collect(name,amount)
    local inventory=modules.Inventory
    if (tonumber(inventory:GetMax(name)) or 0)<=0 then error('AP_ITEM_NAME_UNSUPPORTED:'..name,0) end
    amount=math.min(amount or 1,inventory:GetMax(name))
    for _=1,amount do
        self:Check(); if inventory:Count(name)>=amount then return true end
        local ok,reason=modules.Farm:Restock(name,function() return self:Active() end,'prestige',amount)
        if not ok then error('AP_RESTOCK:'..tostring(reason),0) end
    end
    return inventory:Count(name)>=amount
end
function Context:Sell()
    self:Check()
    if modules.Config:Get('AutoSell')~=true then error('AP_AUTOSELL_DISABLED',0) end
    local beforeMoney=modules.Inventory:GetMoney()
    self.selling=true
    local ok,reason=modules.Farm:PrestigeSell(function() return self:Active() end,function()
        return modules.Inventory:SellAll()
    end)
    self.selling=false
    self:Check(); if not ok then error('AP_SELL:'..tostring(reason),0) end
    self:Until(function() return modules.Inventory:GetMoney()>beforeMoney end,3,'Merchant money confirmation')
end
function Context:Log(level,message) log(level,message) end
function Context:Hop()
    self:Check()
    local before=game.JobId
    local service=game:GetService('TeleportService')
    local failed=false
    if service.TeleportInitFailed then
        self.transferFailureConnection=service.TeleportInitFailed:Connect(function(failedPlayer)
            if failedPlayer==player() then
                failed=true
                if self.pending and self.pending.name=='server transfer' then self.pending=nil end
                if self.transferFailureConnection then self.transferFailureConnection:Disconnect(); self.transferFailureConnection=nil end
            end
        end)
    end
    local requested=modules.ServerHop:Hop(function() return self:Active() and not self.pending end)
    if requested and not failed then
        self.pending={name='server transfer',confirmed=function() return game.JobId~=before end}
        Runtime:Stop('transfer requested; restart beta manually after arrival')
    else
        if self.transferFailureConnection then self.transferFailureConnection:Disconnect(); self.transferFailureConnection=nil end
        error('AP_TRANSFER_NOT_REQUESTED',0)
    end
end
function Runtime:Watch()
    local env=getgenv and getgenv() or _G
    local runtime=env.__WhiteHubRuntimeId
    local waitingSince=nil
    while env.__WhiteHubRuntimeId==runtime do
        local enabled=env.AutoPrestigeEnabled==true and modules.Config:Get('AutoPrestige')==true
        if enabled and not (current and current.running) then
            local ok,reason=self:Start()
            if not ok then
                waitingSince=waitingSince or os.clock()
                if os.clock()-waitingSince>20 then self:Stop(reason); waitingSince=nil end
            else waitingSince=nil end
        elseif not enabled and current and current.running then self:Stop('Stopped by user') end
        nativeTask.wait(0.1)
    end
end
function Runtime:Init(all)
    modules=all; registered=nil; current=nil; serial=0
    local env=getgenv and getgenv() or _G
    local scope=env.__WhiteHubAPScope
    previous=type(scope)=="table" and scope.job==game.JobId and scope.place==game.PlaceId and scope or nil
    log('INFO','Build AP-COMPAT-20261012-R1; dialogue/lifecycle beta, YBA validation pending')
end
function Runtime:Register(callback) registered=callback end
function Runtime:Start()
    if not registered then return false,'Auto Prestige not registered yet' end
    if self:IsBusy() then return false,'Previous Auto Prestige work/result unresolved' end
    local s=modules.StandFarm:GetStatus()
    if modules.StandFarm:HasPendingWork() or s.running or s.pending_item or s.hopping or s.recovering or s.awaiting_transfer or gui() then return false,'Stand/dialogue pending' end
    if modules.Config:Get('StandFarmEnabled') or modules.Config:Get('NPCFarmEnabled') or modules.Config:Get('QuestFarmEnabled') then return false,'Disable other farms first' end
    if modules.Farm:IsBusy() or modules.CombatFarm:IsBusy() then return false,'Other farm operation pending; retry after it finishes' end
    serial=serial+1
    local env=getgenv and getgenv() or _G
    modules.Config:SetMany({AutoPrestige=true,FarmEnabled=false,QuestFarmEnabled=false,NPCFarmEnabled=false})
    env.AutoPrestigeEnabled=true
    current=setmetatable({id=serial,runtime=env.__WhiteHubRuntimeId,job=game.JobId,place=game.PlaceId,running=true,tasks=0,calls=0,
        connections={},objects={},deadline=os.clock()+1800,reason='running'},Context)
    env.__WhiteHubAPScope=current
    local ctx=current
    ctx.Task={wait=function(seconds) return ctx:Wait(seconds) end,
        spawn=function(fn,...) return ctx:Spawn(fn,...) end}
    ctx:Spawn(function()
        registered(ctx)
        if ctx:Active() then self:Stop('completed') end
    end)
    return true
end
function Runtime:Stop(reason)
    local ctx=current
    local wasActive=ctx and (ctx.running or ctx.tasks>0 or ctx.calls>0 or ctx.pending~=nil)
    if wasActive then ctx.running=false; ctx.reason=reason or 'Stopped by user' end
    local env=getgenv and getgenv() or _G
    if not ctx or ctx.runtime==env.__WhiteHubRuntimeId then
        env.AutoPrestigeEnabled=false
        if modules then modules.Config:Set('AutoPrestige',false) end
    end
    if wasActive then
        for _,c in ipairs(ctx.connections) do pcall(function() c:Disconnect() end) end; ctx.connections={}
        for _,o in ipairs(ctx.objects) do pcall(function() o:Destroy() end) end; ctx.objects={}
        modules.PrestigeDialogue:Restore()
        pcall(function() modules.Movement:SetNoclip(false); modules.Movement:ClearFocus(); modules.Movement:FixCamera()
            if ctx.runtime==env.__WhiteHubRuntimeId then
                local char=player().Character; local hum=char and char:FindFirstChildOfClass('Humanoid')
                if hum and hum.Health>0 then modules.Movement:Teleport(CFrame.new(978,-42,-49)) end
            end
        end)
        log('INFO','Stopped: '..ctx.reason..'; pending tasks/results remain fenced')
    end
end
local function busy(ctx)
    if not ctx then return false end
    if ctx.pending and ctx.pending.confirmed then
        local ok,result=pcall(ctx.pending.confirmed)
        if ok and result and not gui() then ctx.pending=nil end
    end
    return ctx.running or ctx.tasks>0 or ctx.calls>0 or ctx.pending~=nil
end
function Runtime:IsBusy()
    if previous==current then previous=nil end
    if previous and busy(previous) then return true end
    previous=nil
    return busy(current)
end
function Runtime:GetStatus()
    return {running=current and current.running or false,busy=self:IsBusy(),
        reason=current and current.reason or 'idle',pending=current and current.pending and current.pending.name,
        tasks=current and current.tasks or 0}
end
function Runtime:BuildStatus(parent,UI)
    local label=UI:AddLabel(parent,'Auto Prestige: idle')
    label.TextWrapped=true; label.Size=UDim2.new(1,-4,0,55)
    nativeTask.spawn(function()
        while label.Parent do
            local state=self:GetStatus()
            label.Text='Auto Prestige: '..tostring(state.reason)..' | pending: '..tostring(state.pending or 'none')
            UI:SetToggleValue('Auto Prestige',state.running)
            nativeTask.wait(1)
        end
    end)
end
function Runtime:Destroy() self:Stop('runtime replaced') end
return Runtime
