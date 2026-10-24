-- BEGIN Dialogue
local Dialogue = (function()
-- Scoped reuse of WHITE HUB's verified Stand dialogue primitives; Merchant untouched.
local Driver={}
local player=game:GetService("Players").LocalPlayer
local VirtualInputManager=game:GetService("VirtualInputManager")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local hiddenDialogues,selectedCallbacks={},{}
local callbackInFlight=0
local cleanupDialogue,currentContext
local function active(ctx) return currentContext==ctx and ctx:Active() end
local function visible(object, gui)
    if not object or not object:IsDescendantOf(gui) then return false end
    local node = object
    while node do
        if node:IsA("GuiObject") and not node.Visible then return false end
        if node:IsA("ScreenGui") and not node.Enabled
            and hiddenDialogues[node] == nil then return false end
        if node == gui then return true end
        node = node.Parent
    end
    return false
end

local function dialogueGui()
    local gui = player and player:FindFirstChild("PlayerGui")
    return gui and gui:FindFirstChild("DialogueGui")
end

local function resolveButton(object, gui)
    if not object then return nil end
    local button = object:IsA("GuiButton") and object
        or object:FindFirstChildWhichIsA("GuiButton", true)
    if button and visible(button, gui) and button.AbsoluteSize.X > 0
        and button.AbsoluteSize.Y > 0 then return button end
    return nil
end

local function dialogueButton(gui)
    local options = gui:FindFirstChild("Options", true)
    local first = options and resolveButton(options:FindFirstChild("Option1"), gui)
    if first then return first, "Option1" end
    -- An unsupported visible option page must not be skipped by Continue.
    if options and visible(options, gui) then
        for _, object in ipairs(options:GetDescendants()) do
            if object:IsA("GuiButton") and visible(object, gui) then
                return nil, "unsupported-options"
            end
        end
    end
    local continueButton = gui:FindFirstChild("ClickContinue", true)
    local ready = resolveButton(continueButton, gui)
    if ready then return ready, "ClickContinue" end
    -- The Quest fast path also advances a hidden Continue during text animation.
    -- Accept it only when its own signal already has an actual bound handler.
    if continueButton and continueButton:IsA("GuiButton") and type(getconnections) == "function" then
        local ok, connections = pcall(getconnections, continueButton.MouseButton1Click)
        if ok and type(connections) == "table" then
            for _, connection in pairs(connections) do
                local fire, fn
                pcall(function() fire, fn = connection.Fire, connection.Function end)
                if type(fire) == "function" or type(fn) == "function" then
                    return continueButton, "ClickContinue"
                end
            end
        end
    end
    return nil, "ClickContinue"
end

local function stageSignature(gui, kind)
    if kind == "ClickContinue" then
        -- Animated body text is not a new Continue page; do not wait for its
        -- typewriter to settle before using the already-bound fast callback.
        return kind .. "|" .. tostring(gui:FindFirstChild("ClickContinue", true))
    end
    -- Only the option controls describe a choice page. Scanning the whole GUI
    -- every poll adds work and makes body typewriter updates delay selection.
    local options = gui:FindFirstChild("Options", true)
    local parts = {kind}
    for _, object in ipairs(options and options:GetDescendants() or {}) do
        if (object:IsA("TextLabel") or object:IsA("TextButton")) and visible(object, gui) then
            parts[#parts + 1] = object.Name .. "=" .. tostring(object.Text):sub(1, 200)
        end
    end
    return table.concat(parts, "|")
end

local function clickButton(token, button, gui)
    if not active(token) or not visible(button, gui) then return false end
    -- Rendered input fallback when fast dialogue APIs are unavailable.
    local ok = pcall(function()
        local p, size = button.AbsolutePosition, button.AbsoluteSize
        local x, y = p.X + size.X / 2, p.Y + size.Y / 2
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
        -- Always release the input; no yield between press/release.
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
    end)
    return ok
end

-- Adapted from the current Quest fast-dialogue path, scoped to the owned
-- consumable GUI. No GC scans, constant patches or Merchant state sharing.
local function indexedUpvalue(reader, fn, index)
    local values = table.pack(pcall(reader, fn, index))
    if not values[1] then return false end
    if values.n >= 3 and type(values[2]) == "string" then
        return true, values[3] -- standard debug API: name, value
    end
    if values.n >= 2 then return true, values[2] end -- executor API: value
    return false
end

local function hideOwnedDialogue(gui)
    if not gui or dialogueGui() ~= gui or not gui:IsA("ScreenGui") then return end
    if hiddenDialogues[gui] == nil then hiddenDialogues[gui] = gui.Enabled end
    pcall(function() gui.Enabled = false end)
end

cleanupDialogue = function(restoreSelection)
    if restoreSelection then
        for fn, record in pairs(selectedCallbacks) do
            if dialogueGui() == record.gui then
                local okAnchor, anchor = indexedUpvalue(record.reader, fn, 2)
                local okValue, value = indexedUpvalue(record.reader, fn, 1)
                if okAnchor and anchor == record.anchor and okValue and value == "Option1" then
                    pcall(record.setter, fn, 1, record.original)
                end
            end
        end
    end
    selectedCallbacks = {}
    for gui, enabled in pairs(hiddenDialogues) do
        pcall(function() gui.Enabled = enabled end)
    end
    hiddenDialogues = {}
end

local function selectFastOption(token, button, gui)
    local reader, setter
    if type(getupvalue) == "function" and type(setupvalue) == "function" then
        reader, setter = getupvalue, setupvalue
    elseif debug and type(debug.getupvalue) == "function" and type(debug.setupvalue) == "function" then
        reader, setter = debug.getupvalue, debug.setupvalue
    end
    if type(getconnections) ~= "function" or not reader or not setter then
        return false, "fast-option-unsupported"
    end
    local ok, connections = pcall(getconnections, button.MouseButton1Click)
    if not ok or type(connections) ~= "table" then return false, "no-connections" end
    for _, connection in pairs(connections) do
        local fn
        pcall(function() fn = connection.Function end)
        if type(fn) == "function" then
            local okAnchor, anchor = indexedUpvalue(reader, fn, 2)
            local okValue, value = indexedUpvalue(reader, fn, 1)
            -- Require the proven U[2] option container binding BEFORE writing.
            if okAnchor and typeof(anchor) == "Instance"
                and anchor == button.Parent and anchor.Name == "Option1"
                and okValue and (value == nil or type(value) == "string") then
                if not active(token) or dialogueGui() ~= gui then return false, "Stopped" end
                if not selectedCallbacks[fn] then
                    selectedCallbacks[fn] = {gui = gui, anchor = anchor, reader = reader,
                        setter = setter, original = value}
                end
                local written = pcall(setter, fn, 1, "Option1")
                local verified, selected = indexedUpvalue(reader, fn, 1)
                if written and verified and selected == "Option1" then
                    if not active(token) then cleanupDialogue(true); return false, "Stopped" end
                    hideOwnedDialogue(gui)
                    return true, "fast-option"
                end
            end
        end
    end
    return false, "callback-mismatch"
end

local function dispatchBoundSignal(token, button, gui)
    if callbackInFlight > 0 then return false, "callback-pending" end
    local signal = button.MouseButton1Click
    local call, method
    if type(getconnections) == "function" then
        local ok, connections = pcall(getconnections, signal)
        if ok and type(connections) == "table" then
            for _, connection in pairs(connections) do
                local fire, fn
                pcall(function() fire, fn = connection.Fire, connection.Function end)
                if type(fire) == "function" then
                    call, method = function() connection:Fire() end, "connection-fire"
                elseif type(fn) == "function" then
                    call, method = fn, "bound-callback"
                end
                if call then break end
            end
        end
    end
    if not call and type(firesignal) == "function" then
        call, method = function() firesignal(signal) end, "firesignal"
    end
    if not call then return false, "signal-unsupported" end
    if not active(token) or dialogueGui() ~= gui then return false, "Stopped" end
    hideOwnedDialogue(gui)
    callbackInFlight = callbackInFlight + 1
    local requestContext=token
    requestContext.calls=requestContext.calls+1
    -- A game handler may yield. Stop must not wait for it, and a second
    -- handler must not overlap while it is still in flight.
    task.spawn(function()
        if active(token) and dialogueGui() == gui then pcall(call) end
        callbackInFlight = callbackInFlight - 1
        requestContext.calls=requestContext.calls-1
    end)
    return true, method
end

local function advanceDialogue(token, button, gui, kind, attempt, renderedReady)
    if not active(token) or dialogueGui() ~= gui then return false, "Stopped" end
    if not visible(button, gui) then
        if kind == "ClickContinue" then return dispatchBoundSignal(token, button, gui) end
        return false, "hidden-option"
    end
    local reason = "continue"
    if kind == "Option1" and attempt == 0 then
        local ok
        ok, reason = selectFastOption(token, button, gui)
        if ok then return true, reason end
    end
    if callbackInFlight > 0 then return false, "callback-pending" end
    -- Quest TEST ALL route: if selection did not advance, dispatch ONLY
    -- this button's actual connected handler, not an unrelated game closure.
    local ok, method = dispatchBoundSignal(token, button, gui)
    if ok then return true, method end
    if not active(token) or method == "callback-pending" then return false, method end
    -- Verified internal handlers need no rendered-page settling delay. Keep
    -- that delay for physical input, which depends on a stable visible button.
    if not renderedReady then return false, "render-wait" end
    cleanupDialogue(true) -- real input requires a rendered ScreenGui
    if clickButton(token, button, gui) then
        return true, "visible-fallback:" .. reason .. ":" .. method
    end
    return false, "input-unavailable:" .. reason .. ":" .. method
end


function Driver:Init() end
function Driver:Restore() cleanupDialogue(true) end
function Driver:Drive(ctx,confirmed,label,timeout)
    if currentContext and currentContext~=ctx and callbackInFlight>0 then return false,"callback pending" end
    currentContext=ctx
    local deadline=os.clock()+(timeout or 12)
    local clicks,signature,attempts,lastAt=0,nil,0,0
    local seen=false; local ownedGui=nil
    while ctx:Active() and os.clock()<deadline do
        local gui=dialogueGui()
        local result=confirmed()
        if result and not gui and callbackInFlight==0 then cleanupDialogue(true); return true end
        if gui then
            if ownedGui and ownedGui~=gui then cleanupDialogue(true); return false,"dialogue replaced; result unresolved" end
            ownedGui=gui; seen=true
        end
        if gui and not result then
            local button,kind=dialogueButton(gui)
            if kind=="unsupported-options" then cleanupDialogue(true); return false,kind end
            if button then
                local stage=stageSignature(gui,kind)
                if stage~=signature then signature=stage; attempts=0; lastAt=0 end
                if callbackInFlight==0 and (attempts==0 or os.clock()-lastAt>=0.8) then
                    if attempts>=2 or clicks>=12 then cleanupDialogue(true); return false,"dialogue stalled" end
                    local ok,method=advanceDialogue(ctx,button,gui,kind,attempts,true)
                    if ok then
                        clicks=clicks+1; attempts=attempts+1; lastAt=os.clock()
                        ctx:Log("INFO",label.." input "..kind.." via "..tostring(method).."; result pending")
                    end
                end
            end
        elseif not gui and not seen and os.clock()>deadline-(timeout or 12)+5 then
            cleanupDialogue(true); return false,"dialogue not detected"
        end
        ctx:Wait(0.03)
    end
    cleanupDialogue(true)
    return false,ctx:Active() and "result timeout" or "cancelled"
end
local promptCache={}
local function findPrompt(npc)
    if promptCache[npc] and promptCache[npc].Parent then return promptCache[npc] end
    local best=nil
    local roots={workspace:FindFirstChild("Dialogues") or workspace}
    local definition=ReplicatedStorage:FindFirstChild("Dialogue") or ReplicatedStorage:FindFirstChild("NewDialogue")
    if definition then roots[#roots+1]=definition end
    for _,root in ipairs(roots) do
        for _,object in ipairs(root:GetDescendants()) do
            if object:IsA("ProximityPrompt") then
                local text=tostring(object.ObjectText or "")
                local parent=object.Parent
                local matched=text==npc
                while parent and parent~=root do
                    if parent.Name==npc then matched=true; break end
                    parent=parent.Parent
                end
                if matched then
                    if best and best~=object then return nil,"ambiguous NPC prompt" end
                    best=object
                end
            end
        end
        if best then break end
    end
    if best then promptCache[npc]=best end
    return best
end
function Driver:Run(ctx,npc,options,confirmed,label)
    if dialogueGui() or callbackInFlight>0 then return false,"existing dialogue/callback" end
    if type(npc)~="string" or type(confirmed)~="function" then return false,"invalid dialogue request" end
    for _,option in ipairs(options or {"Option1"}) do
        if option~="Option1" then return false,"unknown option sequence" end
    end
    if confirmed() then return true,"already reflected in player state" end
    local prompt,reason=findPrompt(npc)
    if reason then return false,reason end
    currentContext=ctx; ctx:Check()
    ctx.pending={name=label or npc,confirmed=confirmed}
    if prompt and type(fireproximityprompt)=="function" then
        fireproximityprompt(prompt)
    else
        local root=ReplicatedStorage:FindFirstChild("NewDialogue")
        local target=root and root:FindFirstChild(npc)
        if not target then ctx.pending=nil; return false,"NPC prompt/definition not found: "..npc end
        local char=player.Character
        ctx:Fire(char and char:FindFirstChild("RemoteEvent"),"PromptTriggered",target)
    end
    local ok,info=self:Drive(ctx,confirmed,label or npc,12)
    if ok then ctx.pending=nil end
    return ok,info
end
return Driver

end)()
-- END Dialogue

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

    -- Fresh YBA accounts can expose a single placeholder child named "Patch"
    -- under PlayerGui.Quests before the first Giorno story quest exists.
    -- Treat that exact empty-state shape as no active quest, so the first
    -- Storyline dialogue can start. Do not generalize this to unknown quests.
    local onlyQuestEntriesArePlaceholders=#questNames==1
        and questNames[1]:lower()=='patch'
    if onlyQuestEntriesArePlaceholders then
        self:Log('INFO','Quest panel contains only the Patch placeholder; starting Storyline #1 for a fresh account')
        return 'Storyline #1'
    end

    self:Log('WARN','Story quest source not identified; active quests: '..table.concat(questNames,' | '):sub(1,500))
    error('AP_STORY_SOURCE_UNKNOWN: export quest/NPC runtime log; no blind dialogue sweep',0)
end
function Context:Dialogue(npc,options,confirm,label)
    self:Check(); if self.pending then error('AP_RESULT_PENDING',0) end
    local ok,reason=Dialogue:Run(self,npc,options,confirm,label)
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
    local ok,reason=Dialogue:Drive(self,confirmed,name,22)
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
Runtime.Dialogue=Dialogue
function Runtime:Init(all)
    Dialogue:Init()
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
        Dialogue:Restore()
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
function Runtime:Destroy() self:Stop('runtime replaced'); Dialogue:Restore() end
return Runtime
