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
            if ((v:find("dio", 1, true) or v:find("deo", 1, true)) and (v:find("heaven", 1, true) or v:find("oh", 1, true)))
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
        if key:find("heavenascensiondio", 1, true) or key:find("heavenascensiondeo", 1, true)
            or key:find("diooverheaven", 1, true) then
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
-- Inspect only the currently open game dialogue. We do not press buttons,
-- buy rewards or reveal private arguments; this supplies verified labels for a later release.
function Community:InspectEventDialogue()
    local pg = Player:FindFirstChild("PlayerGui")
    local gui = pg and pg:FindFirstChild("DialogueGui")
    if not gui then return false, "Open Jack's dialogue first, then inspect it." end
    local names = {}
    for _, d in ipairs(gui:GetDescendants()) do
        if d:IsA("TextButton") or d:IsA("TextLabel") then
            local textValue = tostring(d.Text or ""):gsub("[\\r\\n]", " ")
            if #textValue>0 then names[#names+1] = d.Name .. ":" .. textValue:sub(1,110) end
            if #names>=35 then break end
        end
    end
    log("INFO", "[Halloween][Dialogue] "..table.concat(names, " | "))
    return true, "Event dialogue inspected (labels logged); no options clicked."
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
    for _, candidate in ipairs(probe("joe")) do
        if not table.find(list, candidate) then list[#list+1] = candidate end
    end
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
    local running, mode = false, nil
    if combat and type(combat.IsRunning) == "function" then
        local ok, a, b = pcall(function() return combat:IsRunning() end)
        if ok then running, mode = a, b end
    end
    -- Never terminate a different farm started after this beta tool.
    if combat and running and mode == "NPC" and config
        and config:Get("SelectedNPC") == state.npc then
        pcall(function() combat:Stop() end)
    end
    if config and config:Get("SelectedNPC") == state.npc then
        config:SetMany({NPCFarmEnabled=false, SelectedNPC=state.oldNPC or ""})
    end
    log("INFO","[DIOOH] Stopped and restored selected NPC.")
    return true,"DIO:OH combat stopped."
end
-- Camera follows the Stand itself, never a HumanoidRootPart moved under the map.
-- While piloting the character is kept safely where it was.
function Community:StopPilot()
    local state=pilot
    if not state then
        if self._pilotStarting then
            self._pilotStartCancelled=true
            return true, "Pilot activation cancelled."
        end
        return false, "Pilot not running"
    end
    pilot=nil
    disconnect(state.move)
    disconnect(state.respawn)
    disconnect(state.unsummon)
    disconnect(state.standGone)
    for obj, old in pairs(state.constraints) do
        if obj and obj.Parent then pcall(function() obj.Enabled=old end) end
    end
    if state.root and state.root.Parent then
        pcall(function()
            state.root.Anchored=state.rootAnchored
            state.root.AssemblyLinearVelocity=Vector3.zero
        end)
    end
    local human=state.hum
    if human and human.Parent then
        pcall(function()
            human.WalkSpeed=state.walkSpeed
            human.JumpPower=state.jumpPower
            human.AutoRotate=state.autoRotate
        end)
    end
    if state.focus and state.focus.Parent then
        if state.createdFocus then
            pcall(function() state.focus:Destroy() end)
        else
            pcall(function() state.focus.Value=state.oldFocus end)
        end
    end
    -- Force a real player CameraSubject even when StandMorph was unsummoned.
    local camera=workspace.CurrentCamera
    local current=Player.Character
    local playerHumanoid=current and current:FindFirstChildOfClass("Humanoid")
    if camera then
        pcall(function()
            camera.CameraType=Enum.CameraType.Custom
            camera.CameraSubject=playerHumanoid or state.hum or state.originalSubject
        end)
    end
    if self._pilotUI and self._pilotUI.SetToggleValue then
        pcall(function() self._pilotUI:SetToggleValue("Stand Pilot", false) end)
    end
    log("INFO","[Pilot] Stopped; Stand root/humanoid constraints restored; camera returned to player.")
    return true, "Stand Pilot OFF. Camera returned to player."
end

function Community:StartPilot()
    if pilot or self._pilotStarting then return false, "Stand Pilot is already starting or active" end
    if boss then return false, "Stop DIO:OH first" end
    local busy, name=activeWorkers()
    if busy then return false,"Disable other farms first: "..tostring(name) end
    local c,h,hrp=charParts()
    if not c or not h or not hrp or h.Health<=0 then return false,"Character not ready" end

    self._pilotStarting=true
    self._pilotStartCancelled=false
    local stand=c:FindFirstChild("StandMorph")
    if not stand then
        -- Current YBA exposes ToggleStand through RemoteEvent. This is one
        -- normal summon request, not a repeated remote call loop.
        local remote=c:FindFirstChild("RemoteEvent")
        if not remote then
            self._pilotStarting=false
            return false,"No Stand summoned and ToggleStand remote is unavailable."
        end
        local ok=pcall(function() remote:FireServer("ToggleStand", "Toggle") end)
        if not ok then
            self._pilotStarting=false
            return false,"Could not request Stand summon."
        end
        stand=c:WaitForChild("StandMorph",3)
    end
    local root=stand and (stand:FindFirstChild("HumanoidRootPart") or stand.PrimaryPart)
    if stand and not root then root=stand:WaitForChild("HumanoidRootPart",2) end
    self._pilotStarting=false
    if self._pilotStartCancelled then
        return false,"Stand Pilot was cancelled before activation."
    end
    if Player.Character~=c or not root or not root:IsA("BasePart") then
        return false,"Stand did not summon; no character movement was changed."
    end
    local attach=root:FindFirstChild("StandAttach") or root:WaitForChild("StandAttach",2)
    if not attach then return false,"StandAttach not found; pilot remains OFF." end
    local constraints={}
    for _,child in ipairs(attach:GetDescendants()) do
        if child:IsA("AlignPosition") or child:IsA("AlignOrientation") then
            constraints[child]=child.Enabled
        end
    end
    if not next(constraints) then return false,"Stand constraints not supported." end

    local camera=workspace.CurrentCamera
    if not camera then return false,"Camera not ready." end
    local focus=c:FindFirstChild("FocusCam")
    local createdFocus=false
    local previousFocus=focus and focus.Value
    if not focus then
        focus=Instance.new("ObjectValue")
        focus.Name="FocusCam"
        focus.Parent=c
        createdFocus=true
    end
    local state={
        char=c,stand=stand,root=root,hrp=hrp,hum=h,focus=focus,
        createdFocus=createdFocus,oldFocus=previousFocus,constraints=constraints,
        rootAnchored=root.Anchored,walkSpeed=h.WalkSpeed,
        jumpPower=h.JumpPower,autoRotate=h.AutoRotate,
        originalSubject=camera.CameraSubject
    }
    pilot=state
    -- Keep the real character safe in place; never set its CFrame below map.
    for child in pairs(constraints) do child.Enabled=false end
    root.Anchored=true
    root.AssemblyLinearVelocity=Vector3.zero
    h.WalkSpeed=0
    h.JumpPower=0
    h.AutoRotate=false
    focus.Value=root
    camera.CameraType=Enum.CameraType.Custom
    camera.CameraSubject=root

    state.respawn=Player.CharacterAdded:Connect(function() self:StopPilot() end)
    local summoned=c:FindFirstChild("SummonedStand")
    if summoned and summoned:IsA("BoolValue") then
        state.unsummon=summoned:GetPropertyChangedSignal("Value"):Connect(function()
            if not summoned.Value then self:StopPilot() end
        end)
    end
    state.standGone=stand.AncestryChanged:Connect(function()
        if pilot==state and not stand:IsDescendantOf(c) then self:StopPilot() end
    end)
    state.move=RunService.Heartbeat:Connect(function(dt)
        if pilot~=state then return end
        if Player.Character~=c or not root:IsDescendantOf(c) or h.Health<=0 or not hrp.Parent
            or (summoned and summoned:IsA("BoolValue") and not summoned.Value) then
            self:StopPilot()
            return
        end
        if activeWorkers() then
            self:StopPilot()
            return
        end
        local direction=h.MoveDirection
        if direction.Magnitude<0.05 and not UIS.TouchEnabled then
            local view=workspace.CurrentCamera and workspace.CurrentCamera.CFrame
            if view then
                local f=Vector3.new(view.LookVector.X,0,view.LookVector.Z)
                local r=Vector3.new(view.RightVector.X,0,view.RightVector.Z)
                if f.Magnitude>0.05 and r.Magnitude>0.05 then
                    f=f.Unit;r=r.Unit
                    direction=(UIS:IsKeyDown(Enum.KeyCode.W) and f or Vector3.zero)
                        -(UIS:IsKeyDown(Enum.KeyCode.S) and f or Vector3.zero)
                        +(UIS:IsKeyDown(Enum.KeyCode.D) and r or Vector3.zero)
                        -(UIS:IsKeyDown(Enum.KeyCode.A) and r or Vector3.zero)
                end
            end
        end
        if direction.Magnitude>0.05 then
            local vector=Vector3.new(direction.X,0,direction.Z)
            if vector.Magnitude>0 then
                local pos=root.Position+vector.Unit*math.min(dt,0.05)*28
                root.CFrame=CFrame.lookAt(pos,pos+vector.Unit)
            end
        end
        -- Some native camera controllers change CameraSubject after summon.
        local cam=workspace.CurrentCamera
        if cam and cam.CameraSubject~=root then
            cam.CameraType=Enum.CameraType.Custom
            cam.CameraSubject=root
        end
    end)
    log("INFO","[Pilot] Running beta; Stand root stabilized, character stays safely on map.")
    return true,"Stand Pilot ON. Desummon Stand or toggle OFF to restore the player camera."
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
    self._pilotUI=UI
    section(questPage, "STAND PILOT - BETA")
    self._pilotToggle=UI:AddLabel(questPage, "Camera follows Stand. Character stays on map; auto-summons when possible.")
    self._pilotToggle.TextWrapped=true
    UI._buildCommunityPilotToggle(questPage, "Stand Pilot", function(on)
        if on then
            local ok,reason=self:StartPilot()
            if not ok then
                if self._pilotUI then self._pilotUI:SetToggleValue("Stand Pilot", false) end
                UI:ShowPopup(reason,5)
            else
                UI:ShowPopup(reason,4)
            end
        else
            local ok,reason=self:StopPilot()
            UI:ShowPopup(reason,3)
        end
    end)
    section(questPage, "JOTARO / DIO:OH - BETA")
    button(questPage,"SCAN JOTARO + DIO:OH",function() return self:ScanDioOH() end,UI,style,track)
    button(questPage,"START DIO:OH BOSS FARM",function() return self:StartDioOH() end,UI,style,track)
    button(questPage,"STOP DIO:OH BOSS FARM",function() return self:StopDioOH() end,UI,style,track)
    section(eventsPage,"HALLOWEEN EVENT - DISCOVERY")
    button(eventsPage,"SCAN HALLOWEEN CANDY / NPCS",function() return self:ScanEvent() end,UI,style,track)
    button(eventsPage,"OPEN HALLOWEEN DIALOGUE",function() return self:OpenHalloweenDialogue() end,UI,style,track)
    button(eventsPage,"INSPECT EVENT DIALOGUE",function() return self:InspectEventDialogue() end,UI,style,track)
    local label=UI:AddLabel(eventsPage,"Candy turn-in and auto purchase: locked pending verified item/cost/dialogue mapping. Nothing will be spent blindly.")
    label.TextWrapped=true
    section(settingsPage,"AFK / STABILITY")
    button(settingsPage,"TOGGLE ANTI-AFK",function()
        return self:SetAntiAFK(not (config:Get("CommunityAntiAFK")==true))
    end,UI,style,track)
end
-- Historical coordinates from Xenon are used as map presets only. Each
-- destination is validated with a raycast before moving the character.
local teleportPresets={
    {"Newbie Giorno (Spawn)",Vector3.new(1,0,-697)},
    {"Train Station - Front",Vector3.new(-214,0,18)},
    {"Train Station - Back",Vector3.new(-265,-30,-447)},
    {"Arcade",Vector3.new(255,5,-239)},
    {"Pizza Place",Vector3.new(113,6,71)},
    {"Boss Cafe",Vector3.new(-544,-25,-174)},
    {"Diavolo Castle",Vector3.new(1126,116,-129)},
    {"DIO Part 3",Vector3.new(-44,0,-973)},
    {"Jotaro Part 3",Vector3.new(182,-25,578)},
    {"Jotaro Part 6",Vector3.new(784,-42,144)},
    {"Tallest Peak (JOE / Heaven)",Vector3.new(-237,284,305)},
    {"Hamon Trainer",Vector3.new(421,8,-287)},
    {"Boxing Trainer",Vector3.new(281,0,101)},
    {"Pluck Trainer",Vector3.new(125,-27,438)},
    {"Arrowsmith",Vector3.new(-667,16,-299)},
    {"Cosmetics Merchants",Vector3.new(512,2,22)},
    {"Leaky Eye Luca",Vector3.new(-382,0,-711)},
    {"Dracula",Vector3.new(-420,-34,-75)},
    {"Kars",Vector3.new(264,-33,112)},
    {"Homeless Man Jill",Vector3.new(-142,-31,-577)},
    {"Vampire Room",Vector3.new(391,-31,-166)},
    {"Enrico Pucci",Vector3.new(917,34,-17)},
}
local function findWorldPart(inst)
    if not inst or not inst:IsDescendantOf(workspace) then return nil end
    if inst:IsA("BasePart") then return inst end
    if inst:IsA("Model") and inst.PrimaryPart then return inst.PrimaryPart end
    return inst:FindFirstChildWhichIsA("BasePart",true)
end
local function liveQuestNames()
    local folder=workspace:FindFirstChild("Dialogues")
    local results={}
    local seen={}
    if folder then
        for _, inst in ipairs(folder:GetChildren()) do
            if inst.Name~="" and not seen[inst.Name] then
                results[#results+1]=inst.Name
                seen[inst.Name]=true
            end
        end
    end
    table.sort(results)
    return results
end
local function liveNPCNames()
    local folder=workspace:FindFirstChild("Living")
    local results={}
    local seen={}
    if folder then
        for _, inst in ipairs(folder:GetChildren()) do
            if not Players:FindFirstChild(inst.Name) and inst.Name~=""
                and not seen[inst.Name] and inst:FindFirstChild("HumanoidRootPart") then
                results[#results+1]=inst.Name
                seen[inst.Name]=true
            end
        end
    end
    table.sort(results)
    return results
end
local function getNearbyNPCPosition(name, quest)
    local folder=quest and workspace:FindFirstChild("Dialogues") or workspace:FindFirstChild("Living")
    local inst=folder and folder:FindFirstChild(name)
    local part=findWorldPart(inst)
    if not part and quest then
        -- A quest entry may be a logical Dialogue node rather than a physical NPC.
        local living=workspace:FindFirstChild("Living")
        local fallback=living and living:FindFirstChild(name)
        part=findWorldPart(fallback)
    end
    if not part then return nil end
    return part.Position
end
function Community:TeleportTo(position, label)
    if game.PlaceId~=2809202155 then return false,"Teleport destinations are only configured for main YBA." end
    if self._pilotStarting or pilot or boss then
        return false,"Turn off Stand Pilot and DIO:OH first."
    end
    local busy,why=activeWorkers()
    if busy then return false,"Stop running farms before teleporting: "..tostring(why) end
    local char,hum,hrp=charParts()
    if not char or not hum or not hrp or hum.Health<=0 then
        return false,"Character not ready for teleport."
    end
    if typeof(position)~="Vector3" then return false,"Invalid destination" end
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={char}
    params.IgnoreWater=false
    local from=position+Vector3.new(0,18,0)
    local ray=workspace:Raycast(from,Vector3.new(0,-65,0),params)
    if not ray or ray.Normal.Y<0.5 or ray.Material==Enum.Material.Water then
        log("WARN","[Teleport] Unsafe or unverified surface: "..tostring(label))
        return false,"No safe ground at "..tostring(label)..". Old coordinate may have changed."
    end
    if math.abs(position.Y-ray.Position.Y)>28 then
        return false,"Destination altitude changed too much; teleport skipped."
    end
    local safe=ray.Position+Vector3.new(0,4.5,0)
    self._lastTeleportPosition=hrp.Position
    local facing=hrp.CFrame.LookVector
    local horizontal=Vector3.new(facing.X,0,facing.Z)
    if horizontal.Magnitude<0.01 then horizontal=Vector3.new(0,0,-1) end
    local ok,err=pcall(function() hrp.CFrame=CFrame.lookAt(safe,safe+horizontal.Unit) end)
    if not ok then
        log("WARN","[Teleport] "..tostring(err))
        return false,"Could not move character."
    end
    log("INFO","[Teleport] Arrived near "..tostring(label))
    return true,"Teleported to "..tostring(label)
end
function Community:TeleportToPreset(label)
    for _, row in ipairs(teleportPresets) do
        if row[1]==label then return self:TeleportTo(row[2],label) end
    end
    return false,"Place not found"
end
function Community:TeleportToNPC(name, quest)
    if not name or name=="" then return false,"Select an NPC first." end
    local position=getNearbyNPCPosition(name,quest)
    if not position then
        return false,"This NPC has no visible world position. Try the nearby place preset."
    end
    return self:TeleportTo(position+Vector3.new(4,0,0),name)
end
function Community:ReturnFromTeleport()
    local pos=self._lastTeleportPosition
    if not pos then return false,"No previous teleport position recorded" end
    return self:TeleportTo(pos,"Previous location")
end
function Community:BuildTeleports(page,UI,section,style,track,dropdown)
    section(page,"PLACES / LANDMARKS")
    UI:AddLabel(page,"Presets from older YBA map; destinations require verified ground.").TextWrapped=true
    local places={}
    for _,v in ipairs(teleportPresets) do places[#places+1]=v[1] end
    local selectedPlace=places[1]
    dropdown(page,"Destination",places,function(name) selectedPlace=name end)
    button(page,"TELEPORT TO PLACE",function()
        return self:TeleportToPreset(selectedPlace)
    end,UI,style,track)

    section(page,"QUEST NPCS")
    local quests=liveQuestNames()
    local selectedQuest=quests[1]
    local _,updateQuests=dropdown(page,"Quest NPC",quests,function(name) selectedQuest=name end)
    button(page,"TELEPORT TO QUEST NPC",function()
        return self:TeleportToNPC(selectedQuest,true)
    end,UI,style,track)

    section(page,"NPCS / BOSSES")
    local npcNames=liveNPCNames()
    local selectedNPC=npcNames[1]
    local _,updateNPCs=dropdown(page,"Target NPC",npcNames,function(name) selectedNPC=name end)
    button(page,"TELEPORT TO NPC",function()
        return self:TeleportToNPC(selectedNPC,false)
    end,UI,style,track)
    button(page,"REFRESH NPC LISTS",function()
        quests=liveQuestNames()
        npcNames=liveNPCNames()
        selectedQuest=quests[1]
        selectedNPC=npcNames[1]
        updateQuests(quests)
        updateNPCs(npcNames)
        return true,("Found %d quest entries and %d NPCs."):format(#quests,#npcNames)
    end,UI,style,track)
    button(page,"RETURN TO LAST POSITION",function()
        return self:ReturnFromTeleport()
    end,UI,style,track)
end

function Community:Init(all)
    modules,config,logger=all,all.Config,all.RuntimeLog
    if config:Get("CommunityAntiAFK")==true then self:SetAntiAFK(true) end
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
