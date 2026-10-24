-- WHITE HUB Auto Prestige compatibility beta. Existing progression branches retained.
-- No EndDialogue, money-drop kill credit, detached item loops or recursive story workers.
local env=getgenv and getgenv() or _G
local modules=assert(_G.WhiteHubModules,"WHITE HUB modules missing")
local support=assert(modules.AutoPrestigeRuntime,"Auto Prestige runtime missing")
local function moduleLog(level,...)
    if modules.RuntimeLog then modules.RuntimeLog:Write(level,"AutoPrestige",...) end
end
support:Register(function(ctx)
    local task=ctx.Task
    local function autoPrestigeActive() return ctx:Active() end
    ctx:Wait(0.25)
getgenv().standList = {
    ["The World"] = true,
    ["Star Platinum"] = true,
    ["Star Platinum: The World"] = true,
    ["Crazy Diamond"] = true,
    ["King Crimson"] = true,
    ["King Crimson Requiem"] = true,
}
getgenv().waitUntilCollect = 0.6
getgenv().sortOrder        = "Asc"
getgenv().lessPing         = false
getgenv().autoRequiem      = true
getgenv().NPCTimeOut       = 15
getgenv().HamonCharge      = 90

ctx:Until(function() return game:IsLoaded() and game.Players.LocalPlayer and game.Players.LocalPlayer.Character end,20,"initial Character")

local LocalPlayer = game.Players.LocalPlayer
local Character = nil
local RemoteFunction, RemoteEvent = nil, nil
local HRP = nil
local part
local dontTPOnDeath = true

local function refreshCharacter(character)
    ctx:Until(function()
        Character=LocalPlayer.Character
        local hum=Character and Character:FindFirstChildOfClass("Humanoid")
        RemoteEvent=Character and Character:FindFirstChild("RemoteEvent")
        RemoteFunction=Character and Character:FindFirstChild("RemoteFunction")
        HRP=Character and Character:FindFirstChild("HumanoidRootPart")
        return Character and Character.Parent and hum and hum.Health>0 and HRP and RemoteEvent and RemoteFunction
    end,20,"ready Character/root/remotes")
    return true
end

refreshCharacter(LocalPlayer.Character)

local function disableAutoPrestige() support:Stop("completed") end

local function isMaxPrestige()
    return LocalPlayer.PlayerStats.Prestige.Value >= 3 and LocalPlayer.PlayerStats.Level.Value >= 50
end

if isMaxPrestige() then
    local config = _G.WhiteHubModules and _G.WhiteHubModules.Config
    if config and not config:Get("PrestigeMaxNotified") then
        local webhook = _G.WhiteHubModules and _G.WhiteHubModules.Webhook
        if webhook and webhook.SendPrestigeComplete then
            webhook:SendPrestigeComplete()
        end
        config:Set("PrestigeMaxNotified", true)
    end
    moduleLog("INFO", "[AutoPrestige] Already max prestige. Disabling.")
    disableAutoPrestige()
    return
end

local lastTick = tick()
-- Shared ServerHop: one guarded request, never the old repeated teleport loop.
local function Teleport()
    ctx:Hop()
    error("AP_TRANSFER_REQUESTED",0)
end

part = ctx:Track(Instance.new("Part"))
part.Parent   = workspace
part.Anchored = true
part.Size     = Vector3.new(25, 1, 25)
part.Position = Vector3.new(500, 2000, 500)

local function countItems(name) return modules.Inventory:Count(name) end
local function farmItem(name,amount) return ctx:Collect(name,amount) end
local function useItem(name,amount) return ctx:Consume(name) end
local function attemptStandFarm()
    for attempt=1,25 do
        ctx:Check(); refreshCharacter()
        local stand=LocalPlayer.PlayerStats.Stand.Value
        if getgenv().standList[stand] then return true end
        farmItem("Mysterious Arrow",1)
        if stand~="None" then farmItem("Rokakaka",1); useItem("Rokakaka"); refreshCharacter() end
        useItem("Mysterious Arrow"); refreshCharacter()
    end
    error("AP_STAND_ROLL_LIMIT",0)
end

local function endDialogue(NPC, Dialogue, Option)
    if NPC=="Merchant" then return ctx:Sell() end
    local before=ctx:QuestFingerprint()
    local oldPrestige=LocalPlayer.PlayerStats.Prestige.Value
    return ctx:Dialogue(NPC,{"Option1"},function()
        if NPC=="Prestige" then return LocalPlayer.PlayerStats.Prestige.Value>oldPrestige end
        return ctx:QuestFingerprint()~=before
    end,"NPC "..NPC)
end

local function storyDialogue()
    local source=ctx:StorySource()
    local before=ctx:QuestFingerprint()
    local result=ctx:Dialogue(source,{"Option1"},function() return ctx:QuestFingerprint()~=before end,"Story "..source)
    -- The generic Patch quest panel is not evidence by itself. Arm its
    -- compatibility combat path only after this run observed a story-state change.
    if source=="Storyline #1" then
        ctx.storyFallbackReady=true
        moduleLog("INFO","[AutoPrestige] Storyline #1 state changed; one guarded Security Guard fallback is armed")
    end
    return result
end

-- Auto Prestige's own controller; CombatFarm/XenonLock is not modified.
local function killNPC(npcName,playerDistance,dontDestroyOnKill,extraParameters)
    ctx:Check(); refreshCharacter()
    local living=workspace:FindFirstChild("Living")
    local NPC=nil
    ctx:Until(function()
        NPC=living and living:FindFirstChild(npcName)
        local h=NPC and NPC:FindFirstChildOfClass("Humanoid")
        return h and h.Health>0 and NPC:FindFirstChild("HumanoidRootPart")
    end,15,"NPC "..npcName)
    local deadline= tick()+90
    local nextAttack,nextSkill,nextHamon=0,0,0
    while ctx:Active() and tick()<deadline do
        refreshCharacter()
        local hp=NPC:FindFirstChild("HealthValue") or NPC:FindFirstChildOfClass("Humanoid")
        local health=hp and (hp:IsA("Humanoid") and hp.Health or tonumber(hp.Value))
        if health and health<=0 then
            moduleLog("INFO","[AutoPrestige] Confirmed death: "..npcName)
            return true
        end
        local targetRoot=NPC:FindFirstChild("HumanoidRootPart")
        if not NPC.Parent or not targetRoot then return false end
        local summoned=Character:FindFirstChild("SummonedStand")
        if summoned and not summoned.Value and tick()>=nextSkill then
            nextSkill=tick()+0.5; ctx:Invoke(RemoteFunction,"ToggleStand","Toggle")
        end
        local morph=Character:FindFirstChild("StandMorph")
        if morph and morph.PrimaryPart then
            morph.PrimaryPart.CFrame=targetRoot.CFrame+targetRoot.CFrame.lookVector*-1.1
            HRP.CFrame=morph.PrimaryPart.CFrame+targetRoot.CFrame.lookVector-Vector3.new(0,playerDistance,0)
        else HRP.CFrame=targetRoot.CFrame-Vector3.new(0,playerDistance,0) end
        if extraParameters then extraParameters() end
        if tick()>=nextHamon then
            nextHamon=tick()+1
            local hamon=Character:FindFirstChild("Hamon")
            if hamon and hamon.Value<=getgenv().HamonCharge then
                ctx:Invoke(RemoteFunction,"AssignSkillKey",{Type="Spec",Key="Enum.KeyCode.L",Skill="Hamon Breathing"})
                ctx:Fire(RemoteEvent,"InputBegan",{Input=Enum.KeyCode.L})
            end
        end
        if tick()>=nextAttack then
            nextAttack=tick()+0.1
            if game:GetService("CollectionService"):HasTag(NPC,"Blocking") then
                ctx:Fire(RemoteEvent,"InputBegan",{Input=Enum.KeyCode.R})
            else ctx:Invoke(RemoteFunction,"Attack","m1") end
        end
        ctx:Wait(0.05)
    end
    error("AP_NPC_TIMEOUT:"..npcName,0)
end

local function checkPrestige(level, prestige)
    if (level >= 35 and prestige == 0) or (level >= 40 and prestige == 1) or (level >= 45 and prestige == 2) then
        endDialogue("Prestige", "Dialogue2", "Option1")
        return LocalPlayer.PlayerStats.Prestige.Value>prestige
    end
    return false
end

local function allocateSkills()
    if ctx.skillCharacter==Character and ctx.skillStand==LocalPlayer.PlayerStats.Stand.Value then return end
    ctx.skillCharacter=Character; ctx.skillStand=LocalPlayer.PlayerStats.Stand.Value
    do
        ctx:Invoke(RemoteFunction,"LearnSkill", {["Skill"]="Destructive Power V",  ["SkillTreeType"]="Stand"})
        ctx:Invoke(RemoteFunction,"LearnSkill", {["Skill"]="Destructive Power IV", ["SkillTreeType"]="Stand"})
        ctx:Invoke(RemoteFunction,"LearnSkill", {["Skill"]="Destructive Power III",["SkillTreeType"]="Stand"})
        ctx:Invoke(RemoteFunction,"LearnSkill", {["Skill"]="Destructive Power II", ["SkillTreeType"]="Stand"})
        ctx:Invoke(RemoteFunction,"LearnSkill", {["Skill"]="Destructive Power I",  ["SkillTreeType"]="Stand"})
        if LocalPlayer.PlayerStats.Spec.Value == "Hamon (William Zeppeli)" then
            ctx:Invoke(RemoteFunction,"LearnSkill", {["Skill"]="Hamon Punch III",       ["SkillTreeType"]="Spec"})
            ctx:Invoke(RemoteFunction,"LearnSkill", {["Skill"]="Lung Capacity III",     ["SkillTreeType"]="Spec"})
            ctx:Invoke(RemoteFunction,"LearnSkill", {["Skill"]="Breathing Technique III",["SkillTreeType"]="Spec"})
        end
    end
end

local function hasQuest(panel, questName)
    if not panel then return false end
    if panel:FindFirstChild(questName) then return true end
    -- Some live quest panels use a generic child name (observed: "Patch")
    -- and store the actual quest title in a descendant TextLabel/TextButton.
    local wanted = tostring(questName):lower():gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    for _, object in ipairs(panel:GetDescendants()) do
        if object:IsA("TextLabel") or object:IsA("TextButton") then
            local text = tostring(object.Text or ""):lower():gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
            if text == wanted then return true end
        end
    end
    return false
end

local function autoStoryStep()
    if not autoPrestigeActive() then
        moduleLog("INFO", "[AutoPrestige] Disabled — autoStoryStep() returning.")
        return
    end

    local questPanel
    ctx:Until(function() questPanel=LocalPlayer.PlayerGui:FindFirstChild("Quests",true); return questPanel~=nil end,5,"quest panel")
    allocateSkills()

    if LocalPlayer.PlayerStats.Level.Value >= 25 and LocalPlayer.PlayerStats.Prestige.Value >= 1
    and LocalPlayer.Backpack:FindFirstChild("Requiem Arrow")
    and (LocalPlayer.PlayerStats.Stand.Value == "King Crimson" or LocalPlayer.PlayerStats.Stand.Value == "Star Platinum") then
        LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(500, 2010, 500)
        local oldStand = LocalPlayer.PlayerStats.Stand.Value
        useItem("Requiem Arrow", "V")
        ctx:Until(function() return LocalPlayer.PlayerStats.Stand.Value~=oldStand end,15,"Requiem result")
        return true
    end

    if LocalPlayer.PlayerStats.Spec.Value == "None" and LocalPlayer.PlayerStats.Level.Value >= 25 then
        local function collectAndSell(toolName, amount)
            if LocalPlayer.PlayerStats.Money.Value>=10000 then return end
            farmItem(toolName, 1)
            endDialogue("Merchant", "Dialogue5", "Option2")
        end

        if not LocalPlayer.Backpack:FindFirstChild("Zeppeli's Hat") then
            farmItem("Zeppeli's Hat", 1)
        end

        if LocalPlayer.PlayerStats.Money.Value <= 10000 then
            moduleLog("INFO", "[AutoPrestige] Low money — collecting and selling items for Hamon.")
            collectAndSell("Mysterious Arrow", 25)
            collectAndSell("Rokakaka", 25)
            collectAndSell("Diamond", 10)
            collectAndSell("Steel Ball", 10)
            collectAndSell("Quinton's Glove", 10)
            collectAndSell("Pure Rokakaka", 10)
            collectAndSell("Rib Cage of The Saint's Corpse", 10)
            collectAndSell("Ancient Scroll", 10)
            collectAndSell("Clackers", 10)
            collectAndSell("Caesar's Headband", 10)
        end

        if LocalPlayer.Backpack:FindFirstChild("Zeppeli's Hat") then
            local hat=LocalPlayer.Backpack:FindFirstChild("Zeppeli's Hat")
            if not hat then farmItem("Zeppeli's Hat",1); hat=LocalPlayer.Backpack:FindFirstChild("Zeppeli's Hat") end
            LocalPlayer.Character.Humanoid:EquipTool(hat)
            local beforeSpec=LocalPlayer.PlayerStats.Spec.Value
            ctx:Dialogue("Lisa Lisa",{"Option1"},function()
                return LocalPlayer.PlayerStats.Spec.Value~=beforeSpec
            end,"Hamon purchase")
            task.wait(10)
            return true
        else
            Teleport()
        end
    end

    local questChildren = questPanel:GetChildren()
    local onlyPlaceholder = #questChildren == 1 and questChildren[1].Name:lower() == "patch"

    -- The live YBA quest UI can keep a generic "Patch" child even after
    -- Giorno accepts the first objective. Once the Storyline #1 dialogue has
    -- been confirmed, do not reopen it every tick: run the Security Guard
    -- combat step and then return to Giorno for the next objective.
    if #questChildren < 2 and not (onlyPlaceholder and ctx.storySource == "Storyline #1") then
        storyDialogue()
        ctx:Wait(0.2)
    end

    local useStoryFallback=onlyPlaceholder and ctx.storySource=="Storyline #1"
        and ctx.storyFallbackReady==true
    if hasQuest(questPanel, "Help Giorno by Defeating Security Guards") or useStoryFallback then
        -- Consume the fallback before combat. It can only be re-armed by a later
        -- Giorno dialogue whose observable quest/player fingerprint changes.
        if useStoryFallback then ctx.storyFallbackReady=false end
        moduleLog("INFO", "[AutoPrestige] Quest: Security Guard" ..
            (useStoryFallback and " (one-shot Patch-panel fallback)" or ""))
        for guardIndex = 1, 5 do
            ctx:Check()
            moduleLog("INFO", "[AutoPrestige] Security Guard progress: " .. tostring(guardIndex) .. "/5")
            if not killNPC("Security Guard", 15) then
                moduleLog("WARN", "[AutoPrestige] Security Guard target disappeared before confirmed defeat; retrying next cycle")
                return true
            end
            if guardIndex < 5 then ctx:Wait(0.75) end
        end
        moduleLog("INFO", "[AutoPrestige] Security Guard objective loop finished; returning to Giorno")
        ctx:Wait(1)
        storyDialogue()
        return true

    elseif not getgenv().standList[LocalPlayer.PlayerStats.Stand.Value]
    and LocalPlayer.PlayerStats.Level.Value >= 3 and dontTPOnDeath then
        moduleLog("INFO", "[AutoPrestige] No valid stand — farming arrows.")
        attemptStandFarm()
        dontTPOnDeath = true
        return true

    elseif hasQuest(questPanel, "Defeat Leaky Eye Luca") and getgenv().standList[LocalPlayer.PlayerStats.Stand.Value] then
        moduleLog("INFO", "[AutoPrestige] Quest: Leaky Eye Luca")
        if killNPC("Leaky Eye Luca", 15) then
            task.wait(1)
            storyDialogue()
            return true
        else
            return true
        end

    elseif hasQuest(questPanel, "Defeat Bucciarati") then
        moduleLog("INFO", "[AutoPrestige] Quest: Bucciarati")
        if killNPC("Bucciarati", 15) then
            task.wait(1)
            storyDialogue()
            return true
        else
            return true
        end

    elseif hasQuest(questPanel, "Collect $5,000 To Cover For Popo's Real Fortune") then
        moduleLog("INFO", "[AutoPrestige] Quest: Collect $5,000")
        if LocalPlayer.PlayerStats.Money.Value < 5000 then
            local function collectAndSell(toolName, amount)
                if countItems(toolName) <= amount then
                    if LocalPlayer.PlayerStats.Money.Value>=5000 then return true end
                    farmItem(toolName, 1)
                    endDialogue("Merchant", "Dialogue5", "Option2")
                    if LocalPlayer.PlayerStats.Money.Value>=5000 then storyDialogue() end
                    return true
                end

            end
            task.wait(10)
            collectAndSell("Mysterious Arrow", 25)
            collectAndSell("Rokakaka", 25)
            collectAndSell("Diamond", 10)
            collectAndSell("Steel Ball", 10)
            collectAndSell("Quinton's Glove", 10)
            collectAndSell("Pure Rokakaka", 10)
            collectAndSell("Rib Cage of The Saint's Corpse", 10)
            collectAndSell("Ancient Scroll", 10)
            collectAndSell("Clackers", 10)
            collectAndSell("Caesar's Headband", 10)
        end
        return true

    elseif hasQuest(questPanel, "Defeat Fugo And His Purple Haze") then
        moduleLog("INFO", "[AutoPrestige] Quest: Fugo")
        if killNPC("Fugo", 15) then
            task.wait(1)
            storyDialogue()
            return true
        else
            return true
        end

    elseif hasQuest(questPanel, "Defeat Pesci") then
        moduleLog("INFO", "[AutoPrestige] Quest: Pesci")
        if killNPC("Pesci", 15) then
            task.wait(1)
            storyDialogue()
            return true
        else
            return true
        end

    elseif hasQuest(questPanel, "Defeat Ghiaccio") then
        moduleLog("INFO", "[AutoPrestige] Quest: Ghiaccio")
        if killNPC("Ghiaccio", 15) then
            task.wait(1)
            storyDialogue()
            return true
        else
            return true
        end

    elseif hasQuest(questPanel, "Defeat Diavolo") then
        moduleLog("INFO", "[AutoPrestige] Quest: Diavolo")
        killNPC("Diavolo", 15)
        endDialogue("Storyline #14", "Dialogue7", "Option1")
        if LocalPlayer.Backpack:FindFirstChild("Requiem Arrow") or Character:FindFirstChild("Requiem Arrow") then
            return true
        else
            return true
        end

    elseif LocalPlayer.PlayerStats.Level.Value >= 50 then
        if Character:FindFirstChild("FocusCam") then
            Character.FocusCam:Destroy()
            pcall(function() delfile("AutoPres3_" .. LocalPlayer.Name .. ".txt") end)
        end
        if LocalPlayer.PlayerStats.Prestige.Value >= 3 then
            local config = _G.WhiteHubModules and _G.WhiteHubModules.Config
            if config then
                if not config:Get("PrestigeMaxNotified") then
                    local webhook = _G.WhiteHubModules and _G.WhiteHubModules.Webhook
                    if webhook and webhook.SendPrestigeComplete then
                        webhook:SendPrestigeComplete()
                    end
                    config:Set("PrestigeMaxNotified", true)
                end
                disableAutoPrestige()
            end
            return
        end

    elseif hasQuest(questPanel, "Take down 3 vampires")
    and LocalPlayer.PlayerStats.Spec.Value ~= "None"
    and LocalPlayer.PlayerStats.Level.Value >= 25
    and LocalPlayer.PlayerStats.Level.Value ~= 50 then
        moduleLog("INFO", "[AutoPrestige] Quest: Vampires")
        getgenv().HamonCharge = 10
        local function vampire()
            LocalPlayer.Character.PrimaryPart.CFrame = workspace.Living:FindFirstChild("Vampire").HumanoidRootPart.CFrame - Vector3.new(0, 15, 0)
            if not hasQuest(questPanel, "Take down 3 vampires") then
                if (tick() - lastTick) >= 5 then lastTick = tick() end
                endDialogue("William Zeppeli", "Dialogue4", "Option1")
            end
        end
        killNPC("Vampire", 15, false, vampire)
        return true

    elseif LocalPlayer.PlayerStats.Level.Value >= 50 then
        if Character:FindFirstChild("FocusCam") then
            Character.FocusCam:Destroy()
            pcall(function() delfile("AutoPres3_" .. LocalPlayer.Name .. ".txt") end)
        end
        if LocalPlayer.PlayerStats.Prestige.Value >= 3 then
            local config = _G.WhiteHubModules and _G.WhiteHubModules.Config
            if config then
                if not config:Get("PrestigeMaxNotified") then
                    local webhook = _G.WhiteHubModules and _G.WhiteHubModules.Webhook
                    if webhook and webhook.SendPrestigeComplete then
                        webhook:SendPrestigeComplete()
                    end
                    config:Set("PrestigeMaxNotified", true)
                end
                disableAutoPrestige()
            end
            return
        end
    end
end


    local unchangedSince,lastState=os.clock(),ctx:Fingerprint()
    while ctx:Active() do
        refreshCharacter()
        if isMaxPrestige() then
            local config=modules.Config
            if not config:Get("PrestigeMaxNotified") then
                modules.Webhook:SendPrestigeComplete(); config:Set("PrestigeMaxNotified",true)
            end
            return
        end
        if not checkPrestige(LocalPlayer.PlayerStats.Level.Value,LocalPlayer.PlayerStats.Prestige.Value) then
            autoStoryStep()
        end
        local state=ctx:Fingerprint()
        if state~=lastState then lastState=state; unchangedSince=os.clock() end
        if os.clock()-unchangedSince>120 then error("AP_PROGRESS_TIMEOUT",0) end
        ctx:Wait(0.5)
    end
end)
support:Watch()
