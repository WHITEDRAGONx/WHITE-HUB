-- WHITE HUB V5 SILVER - community features (opt-in / fail closed)
-- Independent of Inventory, Merchant Zero Delay, XenonLock and White AI.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Player = Players.LocalPlayer

local Community = {}
local modules, config, logger
local pilot, boss, afkConnection = nil, nil, nil
local connections = {}
local enabled = true
local function log(level, message)
    if logger then pcall(logger.Write, logger, level, "Community", tostring(message)) end
end
local function disconnect(connection)
    if connection then pcall(function() connection:Disconnect() end) end
end
local function activeWorkers()
    if not config then return true end
    for _, name in ipairs({"FarmEnabled", "StandFarmEnabled", "QuestFarmEnabled", "NPCFarmEnabled", "AutoPrestige"}) do
        if config:Get(name) == true then return true, name end
    end
    if modules and modules.Farm and modules.Farm.IsBusy and modules.Farm:IsBusy() then
        return true, "Farm busy"
    end
    if modules and modules.AutoPrestigeRuntime and modules.AutoPrestigeRuntime:IsBusy() then
        return true, "Prestige busy"
    end
    return false
end
local function charParts()
    local c = Player.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    local hrp = c and c:FindFirstChild("HumanoidRootPart")
    return c, h, hrp
end
local function inventoryInfo()
    local stats = Player:FindFirstChild("PlayerStats")
    return stats and stats:FindFirstChild("QuestProgress"), stats and stats:FindFirstChild("QuestMaxProgress")
end
local function labelCheck()
    -- Only the game's own HUD can confirm a boss quest. Ignore WHITE HUB UI.
    local hud = Player:FindFirstChild("PlayerGui") and Player.PlayerGui:FindFirstChild("HUD")
    if not hud then return false end
    local scanned = 0
    for _, d in ipairs(hud:GetDescendants()) do
        if d:IsA("TextLabel") and #d.Text < 500 then
            local v = d.Text:lower()
            if (v:find("dio", 1, true) and (v:find("heaven", 1, true) or v:find("oh", 1, true)))
                and (v:find("kill", 1, true) or v:find("defeat", 1, true) or v:find("quest", 1, true)) then
                return true
            end
        end
        scanned = scanned + 1
        if scanned > 850 then break end
    end
    return false
end
local function findBoss()
    local living = workspace:FindFirstChild("Living")
    if not living then return nil end
    for _, model in ipairs(living:GetChildren()) do
        local key = model.Name:lower():gsub("[^%a%d]", "")
        if key:find("heavenascensiondio", 1, true) or key:find("diooverheaven", 1, true) then
            return model.Name
        end
    end
end
local function probe(text)
    local matches = {}
    for _, root in ipairs({workspace:FindFirstChild("Dialogues"),
        ReplicatedStorage:FindFirstChild("NewDialogue"), ReplicatedStorage:FindFirstChild("Dialogue")}) do
        if root then
            local count = 0
            for _, obj in ipairs(root:GetDescendants()) do
                local n = obj.Name:lower()
                if n:find(text, 1, true) or
                    (text == "halloween" and (n:find("candy",1,true) or n:find("jack",1,true))) then
                    local path = obj:GetFullName()
                    if #path > 180 then path = path:sub(1,180) end
                    matches[#matches+1] = path
                    if #matches >= 12 then return matches end
                end
                count = count + 1
                if count >= 1200 then break end
            end
        end
    end
    return matches
end
function Community:ScanEvent()
    local found = probe("halloween")
    if #found == 0 then
        log("WARN","[Halloween] No verified candy/event dialogue found. Purchases and turn-in remain locked.")
        return false, "No Halloween dialogue detected. Keep purchases locked."
    end
    log("INFO", "[Halloween] Discovered: " .. table.concat(found, " | "))
    return true, "Event NPC candidates: "..tostring(#found)..". Review Console first."
end
function Community:OpenHalloweenDialogue()
    local dlg = ReplicatedStorage:FindFirstChild("NewDialogue")
    local npc = dlg and dlg:FindFirstChild("Halloween Event")
    local c = Player.Character
    local remote = c and c:FindFirstChild("RemoteEvent")
    if not npc or not remote then return false,"Current Halloween event dialogue is not available." end
    local ok, err = pcall(function() remote:FireServer("PromptTriggered", npc) end)
    if not ok then log("WARN", "[Halloween] "..tostring(err)); return false,"Event dialogue request failed" end
    log("INFO","[Halloween] Opened NPC dialogue only; no candy or money spent.")
    return true,"Halloween dialogue requested. Select an option manually."
end
function Community:ScanDioOH()
    local list = probe("jotaro")
    local bossName = findBoss()
    log("INFO", "[DIOOH] Jotaro sources: "..(#list>0 and table.concat(list, " | ") or "none"))
    log("INFO", "[DIOOH] Boss NPC="..tostring(bossName)..", HUD quest verified="..tostring(labelCheck()))
    return #list>0, "Jotaro sources "..#list.."; boss "..tostring(bossName or "not spawned")..
        ". Review Console; accept Jotaro quest manually."
end
function Community:StartDioOH()
    if boss then return false, "DIO:OH Farm already running" end
    if pilot then return false, "Stop Stand Pilot first" end
    local busy, name = activeWorkers()
    if busy then return false,"Disable other farms first: "..tostring(name) end
    if not labelCheck() then
        log("WARN", "[DIOOH] No confirmed Jotaro -> DIO:OH quest in YBA HUD; refusing to farm unrelated NPCs.")
        return false, "Accept the Jotaro DIO:OH quest first; HUD verification missing."
    end
    local b = findBoss()
    if not b then return false, "Heaven Ascension DIO not spawned/visible in workspace.Living" end
    local progress, maximum = inventoryInfo()
    if not maximum or maximum.Value <= 0 or progress.Value >= maximum.Value then
        return false,"Quest inactive or already complete. Turn in at Jotaro first."
    end
    local combat = modules and modules.CombatFarm
    if not combat then return false,"Combat module unavailable" end
    boss = {oldNPC=config:Get("SelectedNPC"), npc=b, oldQuest=config:Get("QuestFarmEnabled"),
        oldFarm=config:Get("FarmEnabled")}
    config:SetMany({SelectedNPC=b, NPCFarmEnabled=true, QuestFarmEnabled=false})
    local ok, err = pcall(function() combat:StartNPC() end)
    if not ok then
        self:StopDioOH()
        return false,"Combat worker failed: "..tostring(err)
    end
    log("INFO","[DIOOH] Started combat against "..b.." only. Quest turn-in remains manual.")
    local this = boss
    task.spawn(function()
        while boss == this do
            local p,m=inventoryInfo()
            if not p or not m or (m.Value>0 and p.Value>=m.Value) then
                log("INFO","[DIOOH] Objective complete/unknown; stopping boss farm; turn in manually.")
                self:StopDioOH()
                break
            end
            if not labelCheck() then
                log("WARN","[DIOOH] Verified HUD quest disappeared; stopping.")
                self:StopDioOH()
                break
            end
            task.wait(0.5)
        end
    end)
    return true, "Farming "..b..". Stop/turn-in remains under your control."
end
function Community:StopDioOH()
    local state=boss
    if not state then return false, "DIO:OH Farm not running" end
    boss=nil
    local combat=modules and modules.CombatFarm
    if combat then pcall(function() combat:Stop() end) end
    if config then
        config:SetMany({NPCFarmEnabled=false, SelectedNPC=state.oldNPC or ""})
    end
    log("INFO","[DIOOH] Stopped and restored selected NPC.")
    return true,"DIO:OH combat stopped."
end
function Community:StopPilot()
    local state=pilot
    if not state then return false, "Pilot not running" end
    pilot=nil
    disconnect(state.move); disconnect(state.respawn)
    for obj, old in pairs(state.constraints) do
        if obj and obj.Parent then pcall(function() obj.Enabled=old end) end
    end
    if state.focus and state.focus.Parent then pcall(function() state.focus:Destroy() end) end
    local c,h,hrp=charParts()
    if c == state.char and hrp and state.stand and state.stand.Parent then
        local root=state.stand:FindFirstChild("HumanoidRootPart") or state.stand.PrimaryPart
        if root then pcall(function() hrp.CFrame=root.CFrame+CFrame.new(0,2,0) end) end
    end
    log("INFO","[Pilot] Stopped; local constraints and camera restored.")
    return true, "Stand Pilot stopped"
end
function Community:StartPilot()
    if pilot then return false, "Stand Pilot already active" end
    if boss then return false,"Stop DIO:OH first" end
    local busy, name=activeWorkers()
    if busy then return false, "Disable other farms first: "..tostring(name) end
    local c,h,hrp=charParts()
    if not c or not h or not hrp or h.Health<=0 then return false,"Character not ready" end
    local stand=c:FindFirstChild("StandMorph")
    local root=stand and (stand:FindFirstChild("HumanoidRootPart") or stand.PrimaryPart)
    if not root or not root:IsA("BasePart") then return false,"Summon your Stand before enabling Pilot." end
    local attach=root:FindFirstChild("StandAttach")
    if not attach then return false,"StandAttach missing; pilot safely disabled." end
    local constraints={}
    for _,child in ipairs(attach:GetDescendants()) do
        if child:IsA("AlignPosition") or child:IsA("AlignOrientation") then
            constraints[child]=child.Enabled
        end
    end
    if not next(constraints) then return false,"Stand constraints not supported." end
    for child in pairs(constraints) do child.Enabled=false end
    local focus
    if not c:FindFirstChild("FocusCam") then
        focus=Instance.new("ObjectValue")
        focus.Name="FocusCam"
        focus.Value=root
        focus.Parent=c
    end
    local state={char=c,stand=stand,root=root,hrp=hrp,hum=h,focus=focus,constraints=constraints}
    pilot=state
    state.respawn=Player.CharacterAdded:Connect(function() self:StopPilot() end)
    state.move=RunService.Heartbeat:Connect(function(dt)
        if pilot~=state then return end
        if Player.Character~=c or not root.Parent or h.Health<=0 or not hrp.Parent then
            self:StopPilot()
            return
        end
        if config and activeWorkers() then
            self:StopPilot()
            return
        end
        local vec=h.MoveDirection
        -- Keyboard fallback while humanoid is moved below the Stand.
        if vec.Magnitude<0.05 and not UIS.TouchEnabled then
            local look=workspace.CurrentCamera and workspace.CurrentCamera.CFrame
            if look then
                local f=Vector3.new(look.LookVector.X,0,look.LookVector.Z)
                local r=Vector3.new(look.RightVector.X,0,look.RightVector.Z)
                if f.Magnitude>0.05 and r.Magnitude>0.05 then
                    f=f.Unit; r=r.Unit
                    vec=(UIS:IsKeyDown(Enum.KeyCode.W) and f or Vector3.zero)
                       -(UIS:IsKeyDown(Enum.KeyCode.S) and f or Vector3.zero)
                       +(UIS:IsKeyDown(Enum.KeyCode.D) and r or Vector3.zero)
                       -(UIS:IsKeyDown(Enum.KeyCode.A) and r or Vector3.zero)
                end
            end
        end
        if vec.Magnitude>0.05 then
            local direction=Vector3.new(vec.X,0,vec.Z)
            if direction.Magnitude>0 then
                local pos=root.Position+direction.Unit*math.min(dt,0.05)*28
                root.CFrame=CFrame.lookAt(pos,pos+direction.Unit)
            end
        end
        -- Character remains locally below the Stand for familiar Pilot behavior.
        hrp.CFrame=root.CFrame*CFrame.new(0,-30,0)
    end)
    log("INFO","[Pilot] Running (beta). Character and Stand are locally repositioned.")
    return true,"Stand Pilot ON. Move normally; STOP to return."
end
function Community:SetAntiAFK(on)
    if config then config:Set("CommunityAntiAFK", on==true) end
    disconnect(afkConnection);afkConnection=nil
    if on then
        local ok, con=pcall(function()
            return Player.Idled:Connect(function()
                pcall(function()
                    VirtualUser:CaptureController()
                    VirtualUser:ClickButton2(Vector2.new())
                end)
                log("INFO","[Safety] AFK activity requested; kick protection not guaranteed.")
            end)
        end)
        if ok then afkConnection=con else return false,"Anti-AFK not supported by executor" end
    end
    return true,on and "Anti-AFK enabled" or "Anti-AFK disabled"
end
local function button(page, text, callback, UI, style, track)
    local b=Instance.new("TextButton")
    b.Name="CommunityAction"
    b.Size=UDim2.new(1,-4,0,34)
    b.Text=text
    b.Font=Enum.Font.GothamBold
    b.TextSize=12
    b.Parent=page
    style(b,false)
    local connection=b.MouseButton1Click:Connect(function()
        b.Text="WORKING..."
        task.spawn(function()
            local ok, success, message=pcall(callback)
            if not ok then log("WARN", "[Action] "..tostring(success)) end
            local msg=ok and message or "Action failed; check Console."
            if UI and UI.ShowPopup then UI:ShowPopup(tostring(msg),5) end
            if b and b.Parent then b.Text=text end
        end)
    end)
    if track then track(connection) else table.insert(connections,connection) end
    return b
end
function Community:Build(standPage, questPage, eventsPage, settingsPage, UI, section, style, track)
    section(standPage, "STAND PILOT - BETA")
    button(standPage,"START STAND PILOT",function() return self:StartPilot() end,UI,style,track)
    button(standPage,"STOP STAND PILOT",function() return self:StopPilot() end,UI,style,track)
    section(questPage, "JOTARO / DIO:OH - BETA")
    button(questPage,"SCAN JOTARO + DIO:OH",function() return self:ScanDioOH() end,UI,style,track)
    button(questPage,"START DIO:OH BOSS FARM",function() return self:StartDioOH() end,UI,style,track)
    button(questPage,"STOP DIO:OH BOSS FARM",function() return self:StopDioOH() end,UI,style,track)
    section(eventsPage,"HALLOWEEN EVENT - DISCOVERY")
    button(eventsPage,"SCAN HALLOWEEN CANDY / NPCS",function() return self:ScanEvent() end,UI,style,track)
    button(eventsPage,"OPEN HALLOWEEN DIALOGUE",function() return self:OpenHalloweenDialogue() end,UI,style,track)
    local label=UI:AddLabel(eventsPage,"Candy turn-in and auto purchase: locked pending verified item/cost/dialogue mapping. Nothing will be spent blindly.")
    label.TextWrapped=true
    section(settingsPage,"AFK / STABILITY")
    button(settingsPage,"TOGGLE ANTI-AFK",function()
        return self:SetAntiAFK(not (config:Get("CommunityAntiAFK")==true))
    end,UI,style,track)
end
function Community:Init(all)
    modules,config,logger=all,all.Config,all.RuntimeLog
    self:SetAntiAFK(config:Get("CommunityAntiAFK")==true)
    log("INFO","Community features opt-in (Pilot / DIO:OH beta / Halloween scout / AFK). No automatic purchases.")
end
function Community:Destroy()
    enabled=false
    self:StopPilot();self:StopDioOH()
    disconnect(afkConnection);afkConnection=nil
    for _,con in ipairs(connections) do disconnect(con) end
    connections={}
end
return Community
