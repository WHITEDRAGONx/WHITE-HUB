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
local pilot, afkConnection = nil, nil
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
    for _, name in ipairs({"FarmEnabled", "EventItemsFarmEnabled", "StandFarmEnabled", "QuestFarmEnabled", "NPCFarmEnabled", "AutoPrestige"}) do
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
local function candyCounts()
    local counts = {["Yellow Candy"]=0, ["Blue Candy"]=0, ["Green Candy"]=0, ["Red Candy"]=0}
    local sources = {Player:FindFirstChild("Backpack"), Player.Character}
    for _,root in ipairs(sources) do
        if root then
            for _,entry in ipairs(root:GetChildren()) do
                if counts[entry.Name]~=nil and entry:IsA("Tool") then
                    counts[entry.Name]=counts[entry.Name]+1
                end
            end
        end
    end
    return counts
end
function Community:ScanCandy()
    local found=candyCounts()
    local messages={}
    for _,name in ipairs({"Yellow Candy","Blue Candy","Green Candy","Red Candy"}) do
        messages[#messages+1]=name..": "..tostring(found[name])
    end
    local summary=table.concat(messages," | ")
    log("INFO", "[Halloween][Inventory] "..summary)
    return true,summary.." (Backpack + equipped only)"
end
function Community:ScanEvent()
    local found=probe("halloween")
    local candy=candyCounts()
    if #found == 0 then
        log("WARN","[Halloween] No loaded Halloween/Jack dialogue found. Exchange will require actual Jack dialogue.")
    else
        log("INFO", "[Halloween] Candidate nodes: " .. table.concat(found, " | "))
    end
    log("INFO",("[Halloween] Candy tools: Yellow=%d Blue=%d Green=%d Red=%d"):format(
        candy["Yellow Candy"],candy["Blue Candy"],candy["Green Candy"],candy["Red Candy"]))
    return #found>0,
        ("Event nodes: %d. Candy found: %d. Interact with Jack, then INSPECT EVENT DIALOGUE."):format(
        #found,candy["Yellow Candy"]+candy["Blue Candy"]+candy["Green Candy"]+candy["Red Candy"])
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
    -- Option names / visible state are needed to reconstruct the current
    -- event quest dialog safely. No callbacks are invoked by this inspector.
    for _,obj in ipairs(gui:GetDescendants()) do
        if obj.Name:match("^Option%d+$") then
            local labelText={}
            for _,label in ipairs(obj:GetDescendants()) do
                if (label:IsA("TextButton") or label:IsA("TextLabel")) and label.Text~="" then
                    labelText[#labelText+1]=label.Text:sub(1,140)
                end
                if #labelText>=8 then break end
            end
            log("INFO",("[Halloween][Option] %s visible=%s text=%s"):format(
                obj.Name,tostring(obj:IsA("GuiObject") and obj.Visible),
                table.concat(labelText," / ")))
        end
    end
    return true, "Event dialogue inspected (labels logged); no options clicked."
end
-- Timed, read-only discovery recorder. The user clicks Jack's options
-- normally while this watches *only* YBA's DialogueGui; no remote arguments,
-- purchases, or callbacks are fired by this feature.
function Community:WatchEventDialogue(seconds)
    if self._eventWatchActive then return false, "Jack dialogue capture is already running." end
    self._eventWatchActive=true
    local duration=math.clamp(tonumber(seconds) or 30,5,45)
    local expires=tick()+duration
    local lastSignature=nil
    local captured=0
    log("INFO","[Halloween][Watch] Started "..tostring(duration).."s capture. Interact with Jack; open turn-in (Option2) and points shop (Option3) manually.")
    while self._eventWatchActive and enabled and tick()<expires do
        local pg=Player:FindFirstChild("PlayerGui")
        local gui=pg and pg:FindFirstChild("DialogueGui")
        local entries={}
        if gui then
            for _,obj in ipairs(gui:GetDescendants()) do
                if obj.Name:match("^Option%d+$") and obj:IsA("GuiObject") and obj.Visible then
                    local fragments={}
                    for _,d in ipairs(obj:GetDescendants()) do
                        if (d:IsA("TextButton") or d:IsA("TextLabel")) and d.Text~="" then
                            local t=tostring(d.Text):gsub("[%c]"," "):sub(1,145)
                            if not table.find(fragments,t) then
                                fragments[#fragments+1]=t
                            end
                        end
                        if #fragments>=3 then break end
                    end
                    if #fragments>0 then
                        entries[#entries+1]=obj.Name.."="..table.concat(fragments," / ")
                    end
                end
                if #entries>=14 then break end
            end
            -- Reward pages often expose point balances in labels, not options.
            local extra=0
            for _,obj in ipairs(gui:GetDescendants()) do
                if obj:IsA("TextLabel") and obj.Visible then
                    local t=tostring(obj.Text or ""):gsub("[%c]"," "):sub(1,115)
                    local lower=t:lower()
                    if #t>3 and (lower:find("candy",1,true) or lower:find("point",1,true)
                        or lower:find("redeem",1,true) or lower:find("cost",1,true)) then
                        local tag="Info="..t
                        if not table.find(entries,tag) then
                            entries[#entries+1]=tag
                            extra=extra+1
                        end
                    end
                end
                if extra>=7 or #entries>=20 then break end
            end
        end
        table.sort(entries)
        local snapshot=gui and (#entries>0 and table.concat(entries," | ") or "Dialogue open; no visible options yet") or "Dialogue closed"
        if snapshot~=lastSignature then
            captured=captured+1
            log("INFO","[Halloween][Watch] state="..captured.." "..snapshot:sub(1,1800))
            lastSignature=snapshot
        end
        task.wait(0.28)
    end
    self._eventWatchActive=false
    log("INFO","[Halloween][Watch] Finished: "..captured.." distinct dialogue states captured. No purchases or candy turn-ins triggered by scanner.")
    return true, "Captured "..captured.." event dialogue states; copy the Console log."
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
    -- Restore the real player to the Stand before re-enabling physics. Anchored
    -- bodies below the map must never be released in that hidden position.
    if state.hrp and state.hrp.Parent and Player.Character==state.char then
        pcall(function()
            if state.root and state.root.Parent then
                state.hrp.CFrame=state.root.CFrame*CFrame.new(0,3,0)
            else
                state.hrp.CFrame=state.originalBodyCFrame
            end
            state.hrp.AssemblyLinearVelocity=Vector3.zero
            state.hrp.AssemblyAngularVelocity=Vector3.zero
            state.hrp.Anchored=state.originalBodyAnchored
        end)
    elseif state.hrp and state.hrp.Parent then
        pcall(function() state.hrp.Anchored=state.originalBodyAnchored end)
    end
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
    log("INFO","[Pilot] Stopped; hidden body/root/humanoid constraints restored; camera returned to player.")
    return true, "Stand Pilot OFF. Camera returned to player."
end

function Community:IsPiloting()
    return pilot ~= nil or self._pilotStarting == true
end

function Community:StartPilot()
    if pilot or self._pilotStarting then return false, "Stand Pilot is already starting or active" end
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
        originalSubject=camera.CameraSubject,
        originalBodyCFrame=hrp.CFrame,
        originalBodyAnchored=hrp.Anchored,
        bodyHideOffset=38,
        hiddenBodyEnabled=false
    }
    pilot=state
    -- Keep the real character safe in place; never set its CFrame below map.
    for child in pairs(constraints) do child.Enabled=false end
    root.Anchored=true
    root.AssemblyLinearVelocity=Vector3.zero
    -- Unlike making the local body invisible, positioning it below the Stand
    -- is spatially visible to other clients IF Roblox replicates the move.
    -- Anchor while hidden so gravity cannot drop it into the void.
    local minSafeY=workspace.FallenPartsDestroyHeight+80
    if root.Position.Y-state.bodyHideOffset>minSafeY then
        hrp.Anchored=true
        hrp.AssemblyLinearVelocity=Vector3.zero
        hrp.CFrame=root.CFrame*CFrame.new(0,-state.bodyHideOffset,0)
        state.hiddenBodyEnabled=true
        log("INFO", "[Pilot] Hidden body anchored below Stand; original body location saved.")
    else
        log("WARN", "[Pilot] Hidden body not available near destroy height; body stays in place.")
    end
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
        -- Keep the real character below the moving Stand with its root anchored.
        -- A floor-independent Y guard prevents the old falling-into-void failure.
        if state.hiddenBodyEnabled then
            if root.Position.Y-state.bodyHideOffset<=workspace.FallenPartsDestroyHeight+80 then
                log("WARN","[Pilot] Stand approached unsafe void height; Pilot stopped and body restored.")
                self:StopPilot()
                return
            end
            hrp.Anchored=true
            hrp.AssemblyLinearVelocity=Vector3.zero
            hrp.CFrame=root.CFrame*CFrame.new(0,-state.bodyHideOffset,0)
        end
        -- Some native camera controllers change CameraSubject after summon.
        local cam=workspace.CurrentCamera
        if cam and cam.CameraSubject~=root then
            cam.CameraType=Enum.CameraType.Custom
            cam.CameraSubject=root
        end
    end)
    log("INFO","[Pilot] Running beta; anchored body hidden="..tostring(state.hiddenBodyEnabled)..", restore on stop/respawn.")
    return true,state.hiddenBodyEnabled
        and "Stand Pilot ON: body anchored below Stand; OFF restores character."
        or "Stand Pilot ON: body hiding unavailable near void; OFF restores camera."
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
            if not ok then
                log("WARN", "[Action] "..tostring(text)..": "..tostring(success))
            elseif success==false then
                log("WARN", "[Action] "..tostring(text).." refused: "..tostring(message))
            end
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
    self._pilotToggle=UI:AddLabel(questPage, "Camera follows Stand; real body is anchored below it when safe. Stops/restores on desummon.")
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
-- Resolve interaction landmarks from live NPCs first. No unverified Merchant
-- or seasonal Jack coordinates are embedded in the script.
local function landmarkMatches(name, landmark)
    local n=tostring(name or ""):lower()
    if landmark=="jack" then
        return n=="jack, the cauldron specter" or n=="halloween event"
            or (n:find("jack",1,true) and n:find("cauldron",1,true))
    elseif landmark=="merchant" then
        return n=="merchant" or n=="item merchant" or n=="item seller"
            or n=="merchant npc"
    elseif landmark=="arcade" then
        return n=="arcade" or n=="item machine" or n=="the arcade"
    end
    return false
end
local function liveLandmarkPosition(landmark)
    local roots={
        workspace:FindFirstChild("Dialogues"),
        workspace:FindFirstChild("Living"),
        workspace:FindFirstChild("Locations"),
        workspace:FindFirstChild("NPCs"),
        workspace:FindFirstChild("Map"),
    }
    for _,root in ipairs(roots) do
        if root then
            local nodes={root}
            local total=0
            for _,desc in ipairs(root:GetDescendants()) do
                total=total+1
                if total>2200 then break end
                if landmarkMatches(desc.Name,landmark) then
                    nodes[#nodes+1]=desc
                end
            end
            for _,node in ipairs(nodes) do
                if landmarkMatches(node.Name,landmark) then
                    local part=findWorldPart(node)
                    -- ProximityPrompt / dialogue values often have their
                    -- physical interaction part as an ancestor.
                    if not part and node:IsA("ProximityPrompt") then
                        part=findWorldPart(node.Parent)
                    end
                    if part then return part.Position,node:GetFullName() end
                end
            end
        end
    end
    return nil
end
-- A calibrated destination is the player's root POSITION ON THE DESIRED FLOOR,
-- not a building's PrimaryPart/pivot. It must not be offset by +4 studs.
local function savedFloorPosition(key)
    local v=config and config:Get(key)
    if type(v)~="table" or type(v.x)~="number" or type(v.y)~="number" or type(v.z)~="number" then return nil end
    if v.x~=v.x or v.y~=v.y or v.z~=v.z
        or math.max(math.abs(v.x),math.abs(v.y),math.abs(v.z))>100000 then return nil end
    return Vector3.new(v.x,v.y,v.z)
end
local function saveFloorPosition(key,pos,placeName)
    if not config or typeof(pos)~="Vector3" then return false end
    config:Set(key,{x=pos.X,y=pos.Y,z=pos.Z})
    log("INFO","[Teleport] Saved "..placeName.." floor position ("..
        math.floor(pos.X+0.5)..","..math.floor(pos.Y+0.5)..","..math.floor(pos.Z+0.5)..")")
    return true
end
local function canCalibrateHere()
    if game.PlaceId~=2809202155 then return false,"Only supported in YBA main map" end
    local working,worker=activeWorkers()
    if working then
        return false,"Turn off farming before saving a teleport ("..tostring(worker or "worker busy")..")"
    end
    if pilot or Community._pilotStarting then return false,"Stop Stand Pilot before calibrating" end
    local char,h,root=charParts()
    if not root or not h or h.Health<=0 then return false,"Character unavailable" end
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={char}
    params.IgnoreWater=false
    params.RespectCanCollide=true -- Decorative noncollidable models are not standing floors.
    -- Never cast from above the ceiling: only validate the current standing floor.
    local hit=workspace:Raycast(root.Position+Vector3.new(0,0.5,0),Vector3.new(0,-10,0),params)
    if not hit then return false,"No solid ground detected below character; move onto the Arcade entrance floor" end
    local delta=root.Position.Y-hit.Position.Y
    if hit.Normal.Y<0.65 or hit.Material==Enum.Material.Water or delta<0.8 or delta>7 then
        return false,("Invalid standing floor (delta %.2f, normalY %.2f, material %s); stand still on Arcade ground."):
            format(delta,hit.Normal.Y,tostring(hit.Material))
    end
    return true,root.Position
end
function Community:SaveMerchantTeleportHere()
    local ok,position=canCalibrateHere()
    if not ok then return false,position end
    local npc,path=liveLandmarkPosition("merchant")
    if npc and (npc-position).Magnitude>35 then
        return false,"Approach the Merchant before saving"
    end
    saveFloorPosition("MerchantTeleportPosition",position,"Merchant")
    return true,"Merchant floor saved. Teleport now uses this exact standing position."
end
function Community:SaveArcadeTeleportHere()
    log("INFO","[Teleport][ArcadeSave] Button requested")
    local ok,position=canCalibrateHere()
    if not ok then
        log("WARN","[Teleport][ArcadeSave] Refused: "..tostring(position))
        return false,position
    end
    local landmark,path=liveLandmarkPosition("arcade")
    -- A roof-level model is suitable as a horizontal landmark, not a height.
    local anchor=landmark or Vector3.new(255,5,-239) -- legacy Arcade X/Z map position
    local gap=(Vector3.new(anchor.X,0,anchor.Z)-Vector3.new(position.X,0,position.Z)).Magnitude
    if gap>125 then
        local why=("Not near the Arcade (%.0f studs from %s); stand at its entrance, then SAVE."):
            format(gap,landmark and "live landmark" or "map preset")
        log("WARN","[Teleport][ArcadeSave] Refused: "..why)
        return false,why
    end
    -- SetMany stores the session value and reports whether it was written to disk.
    local savedToDisk=config:SetMany({ArcadeTeleportPosition={
        x=position.X,y=position.Y,z=position.Z
    }})
    local confirmed=savedFloorPosition("ArcadeTeleportPosition")
    if not confirmed or (confirmed-position).Magnitude>0.1 then
        log("WARN","[Teleport][ArcadeSave] Failed to store position in config")
        return false,"Arcade position could not be saved"
    end
    local info=("Arcade floor saved (X=%d Y=%d Z=%d, distance %.0f; %s)"):
        format(math.floor(position.X+0.5),math.floor(position.Y+0.5),
            math.floor(position.Z+0.5),gap,
            savedToDisk and "persistent" or "session-only")
    log(savedToDisk and "INFO" or "WARN","[Teleport][ArcadeSave] "..info)
    return true,info
end
function Community:TeleportToLandmark(landmark,allowEventTrade)
    if landmark=="merchant" then
        local saved=savedFloorPosition("MerchantTeleportPosition")
        if saved then
            log("INFO","[Teleport] Using calibrated Merchant floor; no +4 offset.")
            return self:TeleportTo(saved,"Merchant",false,"floor")
        end
        local live,path=liveLandmarkPosition("merchant")
        if not live then
            log("WARN","[Teleport] No saved Merchant floor; StreamingEnabled may hide the NPC.")
            return false,"Go to Merchant once and press SAVE MERCHANT POSITION."
        end
        -- Live NPC center is not a verified standing position on a multi-storey map.
        return false,"Merchant NPC detected ("..tostring(path).."); stand beside it and SAVE MERCHANT POSITION once."
    end
    if landmark=="arcade" then
        local saved=savedFloorPosition("ArcadeTeleportPosition")
        if saved then
            log("INFO","[Teleport] Using calibrated Arcade entrance/floor, not the roof landmark.")
            return self:TeleportTo(saved,"Arcade",false,"floor")
        end
        -- The observed Workspace.Locations.The Arcade marker is at roof height.
        -- Old preset could also land within the roof; fail closed until ground is saved.
        log("WARN","[Teleport] Arcade landmark is roof-level; a floor calibration is required.")
        return false,"Visit the Arcade entrance/floor and press SAVE ARCADE ENTRANCE once."
    end
    local label=landmark=="jack" and "Jack, The Cauldron Specter" or tostring(landmark)
    local live,path=liveLandmarkPosition(landmark)
    if not live then
        log("WARN","[Teleport] "..label.." has no streamed position.")
        return false,"Jack not streamed; approach its area and retry"
    end
    log("INFO","[Teleport] Live NPC for "..label..": "..tostring(path))
    return self:TeleportTo(live+Vector3.new(4,0,0),label,landmark=="jack" and allowEventTrade)
end
-- StreamingEnabled can leave only 2-3 physical quest NPCs in Workspace.
-- Include the known quest catalogue so the picker is not artificially tiny.
-- Teleporting still requires a real, currently visible NPC position.
local questNamesForTeleport={
    "Officer Sam [Lvl. 1+]",
    "Deputy Bertrude [Lvl. 10+]",
    "Abbacchio's Partner [Lvl 15+]",
    "Homeless Man Jill [Lvl. 15+]",
    "Dracula [Lvl. 20+]",
    "William Zeppeli [Lvl. 25+]",
    "Doppio [Lvl. 30+]",
    "Dio [Lvl. 35+]",
    "Darius, The Executioner [Lvl. 20+]",
    "Kars [Lvl. 30+]",
    "Pucci [Lvl. 40+]",
    "Jotaro (Tallest Peak)",
}
local function liveQuestNames()
    local results, seen={},{}
    local function add(name)
        if type(name)=="string" and name~="" and not seen[name] then
            seen[name]=true
            results[#results+1]=name
        end
    end
    for _,name in ipairs(questNamesForTeleport) do add(name) end
    for _, folder in ipairs({workspace:FindFirstChild("Dialogues"),
        ReplicatedStorage:FindFirstChild("NewDialogue")}) do
        if folder then
            for _,inst in ipairs(folder:GetChildren()) do
                local n=inst.Name
                if n:lower():find("lvl",1,true) or n:lower():find("jotaro",1,true)
                    or n:lower():find("quest",1,true) then add(n) end
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
function Community:TeleportTo(position, label, allowEventTrade, groundMode)
    if game.PlaceId~=2809202155 then return false,"Teleport destinations are only configured for main YBA." end
    if self._pilotStarting or pilot then
        return false,"Turn off Stand Pilot first."
    end
    local busy,why=activeWorkers()
    local isOwnedEventTrade=allowEventTrade==true and label=="Jack, The Cauldron Specter"
        and why=="EventItemsFarmEnabled" and modules and modules.HalloweenExchange
        and modules.HalloweenExchange:IsBusy()==true
        and config and config:Get("EventItemsFarmEnabled")==true
        and config:Get("FarmEnabled")~=true
        and config:Get("AutoPrestige")~=true
        and config:Get("StandFarmEnabled")~=true
        and config:Get("QuestFarmEnabled")~=true
        and config:Get("NPCFarmEnabled")~=true
    if busy and not isOwnedEventTrade then
        return false,"Stop running farms before teleporting: "..tostring(why)
    end
    local char,hum,hrp=charParts()
    if not char or not hum or not hrp or hum.Health<=0 then
        return false,"Character not ready for teleport."
    end
    if typeof(position)~="Vector3" then return false,"Invalid destination" end
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={char}
    params.IgnoreWater=false
    local floorMode=groundMode=="floor"
    local from=position+Vector3.new(0,floorMode and 1 or 18,0)
    local ray=workspace:Raycast(from,Vector3.new(0,floorMode and -9 or -65,0),params)
    if not ray or ray.Normal.Y<(floorMode and 0.7 or 0.5) or ray.Material==Enum.Material.Water then
        log("WARN","[Teleport] Unsafe or unverified surface: "..tostring(label))
        return false,"No safe ground at "..tostring(label)..". Destination may not be streamed."
    end
    local delta=position.Y-ray.Position.Y
    if floorMode then
        -- The saved point is a character root, usually ~3 studs above ground.
        -- Roofs or floors on a different level fail verification.
        if delta<1 or delta>6 then
            log("WARN","[Teleport] Saved floor mismatch at "..tostring(label)..": delta="..tostring(delta))
            return false,"Saved floor is not loaded or does not match; no teleport performed."
        end
    elseif math.abs(delta)>28 then
        return false,"Destination altitude changed too much; teleport skipped."
    end
    local safe=ray.Position+Vector3.new(0,floorMode and 3.25 or 4.5,0)
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
    -- Arcade is a multilevel building: never reuse the legacy map-preset raycast.
    if label=="Arcade" then return self:TeleportToLandmark("arcade") end
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
    section(page,"QUICK TRAVEL")
    UI:AddLabel(page,"Merchant and Arcade use saved floor points to avoid rooftops. Calibrate once at the correct floor; Jack uses its streamed NPC.").TextWrapped=true
    button(page,"TELEPORT TO MERCHANT",function()
        return self:TeleportToLandmark("merchant")
    end,UI,style,track)
    button(page,"SAVE MERCHANT POSITION",function()
        return self:SaveMerchantTeleportHere()
    end,UI,style,track)
    button(page,"TELEPORT TO ARCADE",function()
        return self:TeleportToLandmark("arcade")
    end,UI,style,track)
    local arcadeCalibrated=savedFloorPosition("ArcadeTeleportPosition")~=nil
    local arcadeStatus=UI:AddLabel(page,arcadeCalibrated and
        "ARCADE: saved floor found. TELEPORT TO ARCADE is ready." or
        "ARCADE: not calibrated. Stand on the real entrance floor, stop farms, then SAVE ARCADE ENTRANCE.")
    arcadeStatus.TextWrapped=true
    arcadeStatus.Size=UDim2.new(1,-4,0,42)
    button(page,"SAVE ARCADE ENTRANCE",function()
        local ok,msg=self:SaveArcadeTeleportHere()
        arcadeStatus.Text=(ok and "ARCADE: " or "ARCADE SAVE FAILED: ")..tostring(msg)
        return ok,msg
    end,UI,style,track)
    button(page,"TELEPORT TO HALLOWEEN JACK",function()
        return self:TeleportToLandmark("jack")
    end,UI,style,track)
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
    UI:AddLabel(page, "Scroll dropdown for all quests; remote NPCs may not be streamed in.").TextWrapped=true
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
    log("INFO","Community features opt-in (Stand Pilot / Halloween scanner / AFK). DIO:OH deferred until quest is verified.")
end
function Community:Destroy()
    enabled=false
    self._eventWatchActive=false
    self:StopPilot()
    disconnect(afkConnection);afkConnection=nil
    for _,con in ipairs(connections) do disconnect(con) end
    connections={}
end
return Community
