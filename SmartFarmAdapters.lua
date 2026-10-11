-- Lifecycle boundaries only. Inventory and combat algorithms remain unchanged.
local Adapters={}
local modules,config,env,prestigeLaunched,blocked
local hopPending,transferPending,hopEpoch,hopFailedConnection,savedAutoSell
local readyCharacter, readySince, previousFence
local function prestigeFence()
    prestigeLaunched=true
    env.__WhiteHubPrestigeReleaseFence={job=game.JobId,place=game.PlaceId}
end
local function off()
    config:SetMany({FarmEnabled=false,QuestFarmEnabled=false,NPCFarmEnabled=false,
        AutoPrestige=false})
    env.AutoPrestigeEnabled=false
end
local function characterReady()
    local player=game:GetService('Players').LocalPlayer
    local char=player and player.Character
    local hum=char and char:FindFirstChildOfClass('Humanoid')
    if not char or not char.Parent or not hum or hum.Health<=0
        or not char:FindFirstChild('HumanoidRootPart') or not char:FindFirstChild('RemoteFunction') then
        readyCharacter=nil; readySince=nil; return false
    end
    if readyCharacter~=char then readyCharacter=char; readySince=os.clock(); return false end
    return os.clock()-(readySince or os.clock())>=1
end
local function dialogueOpen()
    local player=game:GetService('Players').LocalPlayer
    local gui=player and player:FindFirstChild('PlayerGui')
    local dialogue=gui and gui:FindFirstChild('DialogueGui')
    if not dialogue and gui and gui.GetChildren then
        for _,child in ipairs(gui:GetChildren()) do
            if tostring(child.Name):lower():find('dialog',1,true) then dialogue=child; break end
        end
    end
    -- Rendering can be suppressed by fast dialogue; existence still retains ownership.
    return dialogue~=nil
end
function Adapters:Init(all)
    modules=all; config=all.Config; env=getgenv and getgenv() or _G
    readyCharacter=nil; readySince=nil
    local previous=env.__WhiteHubEngineReleaseFence
    previousFence=type(previous)=='table' and previous.job==game.JobId and previous.place==game.PlaceId
        and type(previous.released)=='function' and previous or nil
    local fence=env.__WhiteHubPrestigeReleaseFence
    prestigeLaunched=type(fence)=='table' and fence.job==game.JobId and fence.place==game.PlaceId
    blocked=nil; hopPending=false; transferPending=false; hopEpoch=0; savedAutoSell=nil
end
function Adapters:PrepareBoot()
    local mode=config:Get('QuestFarmEnabled') and 'quest' or config:Get('NPCFarmEnabled') and 'npc'
        or config:Get('AutoPrestige') and 'prestige' or config:Get('FarmEnabled') and 'item' or nil
    off(); return mode
end
function Adapters:StopStand() modules.StandFarm:Stop() end
function Adapters:Stop()
    if env.AutoPrestigeEnabled==true then prestigeFence() end
    hopEpoch=hopEpoch+1
    off()
    modules.CombatFarm:Stop()
    modules.StandFarm:Stop()
    -- Combat's old resume flag must not reenable Item Farm during a handoff.
    off()
end
function Adapters:IsQuiet()
    local reason=nil
    if previousFence then
        local ok,released=pcall(previousFence.released)
        if not ok or not released then blocked='previous_runtime_pending'; return false,blocked end
        previousFence=nil
    end
    if prestigeLaunched then reason='prestige_release_unverified'
    elseif hopPending or transferPending or modules.ServerHop:IsBusy() then reason='transfer_pending'
    elseif modules.Farm:IsBusy() then reason='item_operation_pending'
    elseif modules.CombatFarm:IsBusy() then reason='combat_operation_pending'
    elseif modules.StandFarm:IsBusy() then reason='stand_result_or_operation_pending'
    elseif dialogueOpen() then reason='dialogue_open'
    elseif not characterReady() then reason='character_not_ready' end
    blocked=reason; return reason==nil,reason
end
function Adapters:SetItemPreference(key,value)
    if (key~='AutoSell' and key~='BuyLucky') or type(value)~='boolean' then return false,'invalid_preference' end
    if key=='AutoSell' and savedAutoSell~=nil then savedAutoSell=value
    else config:Set(key,value) end
    return true
end
function Adapters:Release()
    if savedAutoSell~=nil then config:Set('AutoSell',savedAutoSell); savedAutoSell=nil end
end
function Adapters:GetBlockReason() self:IsQuiet(); return blocked end
function Adapters:ExternalMode()
    if transferPending or hopPending then return 'hop' end
    if modules.StandFarm:IsRunning() then return 'stand' end
    local running,mode=modules.CombatFarm:IsRunning()
    if running then return mode=='Quest' and 'quest' or 'npc' end
    if env.AutoPrestigeEnabled==true then prestigeFence(); return 'prestige' end
    if config:Get('FarmEnabled')==true then return 'item' end
end
function Adapters:Start(mode,settings)
    local quiet,reason=self:IsQuiet(); if not quiet then return false,reason end
    off()
    if savedAutoSell~=nil then config:Set("AutoSell",savedAutoSell); savedAutoSell=nil end
    config:SetMany(settings)
    if mode=='item' then
        if not modules.Farm:IsRunning() then return false,'item_worker_unavailable' end
        config:Set('FarmEnabled',true)
    elseif mode=='quest' or mode=='npc' then
        config:Set(mode=='quest' and 'QuestFarmEnabled' or 'NPCFarmEnabled',true)
        if mode=='quest' then modules.CombatFarm:StartQuest() else modules.CombatFarm:StartNPC() end
    elseif mode=='stand' then
        -- Selling is a preference of the Item owner, never a parallel Stand operation.
        savedAutoSell=config:Get('AutoSell'); config:Set('AutoSell',false)
        return modules.StandFarm:Start()
    elseif mode=='hop' then
        hopPending=true; hopEpoch=hopEpoch+1; local epoch=hopEpoch
        if hopFailedConnection then hopFailedConnection:Disconnect(); hopFailedConnection=nil end
        local ts=game:GetService('TeleportService')
        if ts.TeleportInitFailed then
            hopFailedConnection=ts.TeleportInitFailed:Connect(function(player)
                if player==game:GetService('Players').LocalPlayer then transferPending=false end
            end)
        end
        local ok,requested=pcall(function()
            return modules.ServerHop:Hop(function() return epoch==hopEpoch end)
        end)
        hopPending=false
        if ok and requested then transferPending=true; return true end
        return false,'transfer_not_requested'
    elseif mode=='prestige' then
        prestigeFence(); config:Set('AutoPrestige',true); env.AutoPrestigeEnabled=true
    else return false,'invalid_mode' end
    return true
end
function Adapters:Running(mode)
    if mode=='hop' then return hopPending or transferPending,'transfer_failed' end
    if mode=='item' then return config:Get('FarmEnabled')==true and modules.Farm:IsRunning(),'item_stopped' end
    if mode=='prestige' then return env.AutoPrestigeEnabled==true,'prestige_stopped' end
    if mode=='quest' or mode=='npc' then
        local running,current=modules.CombatFarm:IsRunning()
        return running and current==(mode=='quest' and 'Quest' or 'NPC'),'combat_stopped'
    end
    local status=modules.StandFarm:GetStatus()
    if status.running or status.recovering or status.awaiting_transfer then return true end
    local reason=status.stop_reason or 'stand_stopped'
    if reason:find('Desired',1,true) then return false,'module_completed' end
    return false,'stand_stopped:'..reason
end
function Adapters:Destroy()
    self:Stop()
    if hopFailedConnection then hopFailedConnection:Disconnect(); hopFailedConnection=nil end
end
return Adapters
