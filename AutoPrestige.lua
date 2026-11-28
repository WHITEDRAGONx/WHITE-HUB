-- WHITE HUB Auto Prestige compatibility beta. Existing progression branches retained.
-- No EndDialogue, money-drop kill credit, detached item loops or recursive story workers.
local env=getgenv and getgenv() or _G
local modules=assert(_G.WhiteHubModules,"WHITE HUB modules missing")
local support=assert(modules.AutoPrestigeRuntime,"Auto Prestige runtime missing")
local function moduleLog(level,...)
    if modules.RuntimeLog then modules.RuntimeLog:Write(level,"AutoPrestige",...) end
end
local function auditStage(stage,details)
    local audit=modules.RemoteAudit
    if audit and type(audit.Stage)=="function" then
        pcall(audit.Stage,audit,"AutoPrestige",stage,details)
    end
end
support:Register(function(ctx)
    moduleLog("INFO","Build AP-AFK-20261128-R10.16-POST-GHIACCIO-MISTA; resume Storyline #15 after Ghiaccio; confirm Diavolo quest")
    local nativeTask=task
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
-- No AutoPrestige NPC deadline: XenonLock waits until defeat or user cancellation.
getgenv().HamonCharge      = 90

ctx:Until(function() return game:IsLoaded() and game.Players.LocalPlayer and game.Players.LocalPlayer.Character end,nil,"initial Character")

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
    end,nil,"ready Character/root/remotes")
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
    local attempt=0
    while ctx:Active() do
        attempt=attempt+1
        ctx:Check()
        refreshCharacter()

        local stand=LocalPlayer.PlayerStats.Stand.Value
        if getgenv().standList[stand] then
            moduleLog("INFO","[AutoPrestige] Accepted Stand obtained after "..tostring(attempt-1).." roll(s): "..tostring(stand))
            return true
        end

        -- Keep rolling until an accepted Stand is actually confirmed. No
        -- attempt cap: AFK progression must not stop on an unlucky sequence.
        if stand~="None" then
            moduleLog("INFO",("[AutoPrestige] Stand roll %d: resetting %s with one Rokakaka")
                :format(attempt,tostring(stand)))
            farmItem("Rokakaka",1)
            ctx:Check()
            useItem("Rokakaka")
            refreshCharacter()
            ctx:Until(function()
                return LocalPlayer.PlayerStats.Stand.Value=="None"
            end,nil,"Rokakaka Stand reset")
        end

        moduleLog("INFO",("[AutoPrestige] Stand roll %d: collecting one Mysterious Arrow through stable Farm restock")
            :format(attempt))
        farmItem("Mysterious Arrow",1)
        ctx:Check()
        useItem("Mysterious Arrow")
        refreshCharacter()
    end
    ctx:Check()
    return false
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

local function storyDialogue(sourceOverride,expectedQuest)
    local source=sourceOverride
    if not source then
        local reason
        source,reason=ctx:TryStorySource()
        if not source then
            moduleLog("WARN","[AutoPrestige] Story dialogue skipped: no confirmed Storyline source ("..tostring(reason)..")")
            return false,"story source unknown"
        end
    end
    local before=ctx:QuestFingerprint()
    local function confirmed()
        if expectedQuest=="Defeat Pesci" then
            return ctx:HasQuestTitle("Defeat Pesci")
        elseif expectedQuest=="Defeat Fugo" then
            return ctx:HasQuestTitle("Defeat Fugo")
        elseif expectedQuest=="Defeat Diavolo" then
            return ctx:HasQuestTitle("Defeat Diavolo")
        elseif expectedQuest=="Post-Ghiaccio handoff" then
            local objective=ctx:StoryObjective()
            return objective=="Talk to Bruno at the castle"
                or objective=="Talk to Giorno about Diavolo"
                or ctx:HasQuestTitle("Defeat Diavolo")
        elseif expectedQuest=="Post-Bruno handoff" then
            local objective=ctx:StoryObjective()
            return objective=="Talk to Giorno about Diavolo"
                or ctx:HasQuestTitle("Defeat Diavolo")
        elseif expectedQuest=="Final story reward" then
            return not ctx:HasQuestTitle("Defeat Diavolo")
                and ctx:QuestFingerprint()~=before
        elseif source=="Storyline #4" then
            local backpack=LocalPlayer:FindFirstChildOfClass("Backpack")
            local character=LocalPlayer.Character
            local lighterPresent=(backpack and backpack:FindFirstChild("Lighter")~=nil)
                or (character and character:FindFirstChild("Lighter")~=nil)
            if lighterPresent then return true end
            local objective=ctx:StoryObjective()
            return objective=="Deliver Lighter to Giorno"
        end
        return ctx:QuestFingerprint()~=before
    end
    local label="Story "..source
    if source=="Storyline #11" and expectedQuest=="Defeat Pesci" then
        label="Story Trish after Fugo"
    end
    local retryOnClose=expectedQuest=="Post-Ghiaccio handoff"
        or expectedQuest=="Post-Bruno handoff"
        or expectedQuest=="Final story reward"
    auditStage("STORY_DIALOGUE_REQUEST",{source=source,expected=expectedQuest or "quest fingerprint"})
    local ok,result=pcall(function()
        return ctx:Dialogue(source,{"Option1"},confirmed,label,retryOnClose)
    end)
    if not ok then
        auditStage("STORY_DIALOGUE_FAILED",{source=source,error=tostring(result)})
        moduleLog("WARN","[AutoPrestige] "..label.." did not confirm: "..tostring(result))
        if ctx.pending then ctx.pending=nil end
        return false,tostring(result)
    end
    auditStage("STORY_DIALOGUE_CONFIRMED",{source=source,expected=expectedQuest or "quest fingerprint"})
    return result
end

-- These are dialogue-only transitions documented by the YBA Story/Trello route.
-- Combat and money-gated steps are intentionally handled by their own branches below.
local STORY_DIALOGUE_NEXT = {
    ["Storyline #2"]="Storyline #3",
    ["Storyline #4"]="Storyline #5",
    ["Storyline #5"]="Storyline #6",
    ["Storyline #6"]="Storyline #7",
    ["Storyline #7"]="Storyline #8",
    ["Storyline #8"]="Storyline #9",
    ["Storyline #9"]="Storyline #10",
    ["Storyline #13"]="Storyline #14",
    ["Storyline #15"]="Storyline #16",
    ["Storyline #16"]="Storyline #17",
}

local function advanceKnownStoryDialogue()
    local current=tostring(ctx.storySource or "")
    local nextSource=STORY_DIALOGUE_NEXT[current]
    if not nextSource then return false end
    moduleLog("INFO","[AutoPrestige] Storyline handoff "..current.." -> "..nextSource)
    local expected=nextSource=="Storyline #16" and "Post-Bruno handoff"
        or (nextSource=="Storyline #17" and "Defeat Diavolo" or nil)
    storyDialogue(nextSource,expected)
    ctx:Wait(0.2)
    return true
end

-- Auto Prestige delegates NPC combat to the shared CombatFarm/XenonLock core.
local function killNPC(npcName,playerDistance,dontDestroyOnKill,extraParameters)
    ctx:Check()
    local combat=modules.CombatFarm
    if not combat or type(combat.DefeatTarget)~="function" then
        error("AP_COMBAT_API_MISSING",0)
    end
    local defeated,reason=combat:DefeatTarget(npcName,extraParameters)
    ctx:Check()
    if not defeated and reason then
        moduleLog("WARN","[AutoPrestige] Shared combat will retry "..tostring(npcName)..": "..tostring(reason))
    end
    return defeated==true
end

local function checkPrestige(level, prestige)
    if (level >= 35 and prestige == 0) or (level >= 40 and prestige == 1) or (level >= 45 and prestige == 2) then
        endDialogue("Prestige", "Dialogue2", "Option1")
        return LocalPlayer.PlayerStats.Prestige.Value>prestige
    end
    return false
end

local skillAllocationPending=false
local function allocateSkills()
    local currentStand=LocalPlayer.PlayerStats.Stand.Value
    if ctx.skillCharacter==Character and ctx.skillStand==currentStand then return end
    if skillAllocationPending then return end
    ctx.skillCharacter=Character
    ctx.skillStand=currentStand
    skillAllocationPending=true

    -- Skill allocation is optional support, never a gate in the story worker.
    -- A yielding LearnSkill RemoteFunction must not freeze AutoPrestige progress.
    local skills={
        {Skill="Destructive Power V",SkillTreeType="Stand"},
        {Skill="Destructive Power IV",SkillTreeType="Stand"},
        {Skill="Destructive Power III",SkillTreeType="Stand"},
        {Skill="Destructive Power II",SkillTreeType="Stand"},
        {Skill="Destructive Power I",SkillTreeType="Stand"},
    }
    if LocalPlayer.PlayerStats.Spec.Value=="Hamon (William Zeppeli)" then
        skills[#skills+1]={Skill="Hamon Punch III",SkillTreeType="Spec"}
        skills[#skills+1]={Skill="Lung Capacity III",SkillTreeType="Spec"}
        skills[#skills+1]={Skill="Breathing Technique III",SkillTreeType="Spec"}
    end

    nativeTask.spawn(function()
        local completed,failed=0,0
        for _,skill in ipairs(skills) do
            if not ctx:Active() then break end
            local character=LocalPlayer.Character
            local remote=character and character:FindFirstChild("RemoteFunction")
            while ctx:Active() and (not remote or remote.Parent~=character) do
                nativeTask.wait(0.25)
                character=LocalPlayer.Character
                remote=character and character:FindFirstChild("RemoteFunction")
            end
            if not ctx:Active() then break end
            local ok,reason=pcall(function()
                local audit=modules.RemoteAudit
                if audit and type(audit.Invoke)=="function" then
                    return audit:Invoke("AutoPrestige",remote,"LearnSkill",skill)
                end
                return remote:InvokeServer("LearnSkill",skill)
            end)
            if ok then
                completed=completed+1
            else
                failed=failed+1
                moduleLog("WARN","[AutoPrestige] Optional skill allocation failed for "
                    ..tostring(skill.Skill)..": "..tostring(reason))
            end
        end
        skillAllocationPending=false
        if ctx:Active() then
            moduleLog("INFO",("[AutoPrestige] Optional skill allocation finished: %d confirmed call(s), %d failed call(s)")
                :format(completed,failed))
        end
    end)
end

local function normalizeQuestText(value)
    return tostring(value or ""):lower():gsub("[%c]+"," "):gsub("%s+"," "):gsub("^%s+",""):gsub("%s+$","")
end

local function hasQuest(panel, questName)
    if not panel then return false end
    if panel:FindFirstChild(questName) then return true end

    -- Keep this scan inside the small Quests container. Searching all of
    -- PlayerGui every 0.5s was expensive and caused avoidable frame spikes.
    local wanted=normalizeQuestText(questName)
    for _,object in ipairs(panel:GetDescendants()) do
        if object:IsA("TextLabel") or object:IsA("TextButton") then
            local value=normalizeQuestText(object.Text)
            if value~="" and (value==wanted or value:find(wanted,1,true)) then
                return true
            end
        end
    end
    return false
end

local function hasOnlyGenericPatchRow(panel)
    if not panel then return false end
    local rows={}
    for _,child in ipairs(panel:GetChildren()) do
        if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
            rows[#rows+1]=child
        end
    end
    return #rows==1 and tostring(rows[1].Name):lower()=="patch"
end

local function questProgressState()
    local stats=LocalPlayer:FindFirstChild("PlayerStats")
    local progress=stats and stats:FindFirstChild("QuestProgress")
    local maximum=stats and stats:FindFirstChild("QuestMaxProgress")
    return tonumber(progress and progress.Value) or 0,tonumber(maximum and maximum.Value) or 0
end

local function hasKnownStoryQuest(panel)
    for _,name in ipairs({
        "Help Giorno by Defeating Security Guards",
        "Defeat Leaky Eye Luca",
        "Defeat Bucciarati",
        "Return Koichi's Suitcase",
        "Deliver Lighter to Giorno",
        "Bring the Lighter to Giorno",
        "Talk to the members of Bucciarati's gang",
        "Meet the members of Bucciarati's gang",
        "Talk to Fugo",
        "Meet Fugo",
        "Talk to Mista",
        "Meet Mista",
        "Talk to Narancia",
        "Meet Narancia",
        "Talk to Abbacchio",
        "Meet Abbacchio",
        "Talk to Bruno",
        "Meet Bruno",
        "Talk to Trish",
        "Meet Trish",
        "Collect $5,000 To Cover For Popo's Real Fortune",
        "Defeat Fugo And His Purple Haze",
        "Defeat Pesci",
        "Defeat Ghiaccio",
        "Defeat Diavolo",
        "Take down 3 vampires",
    }) do
        if hasQuest(panel,name) then return true end
    end
    return false
end

local function autoStoryStep()
    if not autoPrestigeActive() then
        moduleLog("INFO", "[AutoPrestige] Disabled — autoStoryStep() returning.")
        return
    end

    local questPanel
    local questPanelWaitStarted=os.clock()
    ctx:Until(function() questPanel=LocalPlayer.PlayerGui:FindFirstChild("Quests",true); return questPanel~=nil end,nil,"quest panel")
    local questPanelWait=os.clock()-questPanelWaitStarted
    if questPanelWait>1.5 then
        moduleLog("INFO",("[AutoPrestige] Quest panel became available after %.1fs; continuing first objective scan"):format(questPanelWait))
    end
    ctx:QuestEntries(questPanel)
    allocateSkills()

    local observedProgress,observedMaximum=questProgressState()
    local observedState=table.concat({
        tostring(LocalPlayer.PlayerStats.Level.Value),
        tostring(LocalPlayer.PlayerStats.Prestige.Value),
        tostring(LocalPlayer.PlayerStats.Stand.Value),
        tostring(LocalPlayer.PlayerStats.Spec.Value),
        tostring(observedProgress).."/"..tostring(observedMaximum)
    },"|")
    if observedState~=ctx.lastAutoStoryState then
        ctx.lastAutoStoryState=observedState
        moduleLog("INFO","[AutoPrestige] Progression snapshot: Level="
            ..tostring(LocalPlayer.PlayerStats.Level.Value)
            .." Prestige="..tostring(LocalPlayer.PlayerStats.Prestige.Value)
            .." Stand="..tostring(LocalPlayer.PlayerStats.Stand.Value)
            .." Spec="..tostring(LocalPlayer.PlayerStats.Spec.Value)
            .." Quest="..tostring(observedProgress).."/"..tostring(observedMaximum))
    end
    local observedStand=LocalPlayer.PlayerStats.Stand.Value
    if getgenv().standList[observedStand] and ctx.lastAcceptedStandLog~=observedStand then
        ctx.lastAcceptedStandLog=observedStand
        moduleLog("INFO","[AutoPrestige] Valid Stand confirmed: "..tostring(observedStand).."; continuing Storyline progression")
    end

    if LocalPlayer.PlayerStats.Level.Value >= 25 and LocalPlayer.PlayerStats.Prestige.Value >= 1
    and LocalPlayer.Backpack:FindFirstChild("Requiem Arrow")
    and (LocalPlayer.PlayerStats.Stand.Value == "King Crimson" or LocalPlayer.PlayerStats.Stand.Value == "Star Platinum") then
        LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(500, 2010, 500)
        local oldStand = LocalPlayer.PlayerStats.Stand.Value
        useItem("Requiem Arrow", "V")
        ctx:Until(function() return LocalPlayer.PlayerStats.Stand.Value~=oldStand end,nil,"Requiem result")
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

    local questProgress,questMaxProgress=questProgressState()
    local questIncomplete=questMaxProgress>0 and questProgress<questMaxProgress
    local questComplete=questMaxProgress>0 and questProgress>=questMaxProgress

    -- Fresh YBA accounts can render only a generic "Patch" row. Giorno's
    -- first Security Guard mission is the known 5-step objective; use the
    -- replicated quest counter instead of scanning the entire PlayerGui.
    local genericPatchActive=hasOnlyGenericPatchRow(questPanel) and questMaxProgress>0

    -- Reconcile the saved checkpoint BEFORE reading/mapping dialogue objectives.
    -- Otherwise an old visible Giorno/Lighter label could be mistaken for the
    -- active stage and reopen a completed earlier Storyline after rejoin.
    local storyLevel=tonumber(LocalPlayer.PlayerStats.Level.Value) or 0
    local storyPrestige=tonumber(LocalPlayer.PlayerStats.Prestige.Value) or 0
    local savedStoryIndex=tonumber(tostring(ctx.storySource or ""):match("^Storyline #(%d+)$"))
    if storyPrestige==0 and storyLevel>=13 and storyLevel<15
        and savedStoryIndex and savedStoryIndex>=4 and savedStoryIndex<10 then
        moduleLog("WARN","[AutoPrestige] Ignoring stale saved Storyline #"..tostring(savedStoryIndex)
            .." checkpoint at Level "..tostring(storyLevel).." before objective mapping; resuming from live progression/Trish #11")
        ctx.storySource=nil
    end

    local storyObjective,mappedStorySource=ctx:StoryObjective()
    local koichiSuitcaseQuest=storyObjective=="Return Koichi's Suitcase"
        or hasQuest(questPanel,"Return Koichi's Suitcase")
    local backpack=LocalPlayer:FindFirstChildOfClass("Backpack")
    local character=LocalPlayer.Character
    local hasLighter=(backpack and backpack:FindFirstChild("Lighter")~=nil)
        or (character and character:FindFirstChild("Lighter")~=nil)
        or hasQuest(questPanel,"Deliver Lighter to Giorno")
        or hasQuest(questPanel,"Bring the Lighter to Giorno")
    local talkObjective=storyObjective and (
        storyObjective:lower():find("talk to",1,true)
        or storyObjective:lower():find("meet ",1,true)
        or storyObjective:lower():find("deliver lighter",1,true)
    )

    -- Quest UI can retain the previous talk objective for a few frames after
    -- a dialogue is credited. Never rewind to an earlier Storyline once this
    -- runtime has confirmed a later one (e.g. stale Giorno #5 after Fugo #6).
    local function storyIndex(source)
        return tonumber(tostring(source or ""):match("^Storyline #(%d+)$"))
    end
    local activeStoryIndex=storyIndex(ctx.storySource)
    local objectiveStoryIndex=storyIndex(mappedStorySource)
    if talkObjective and activeStoryIndex and objectiveStoryIndex
        and objectiveStoryIndex<activeStoryIndex then
        local staleKey=tostring(mappedStorySource).."<"..tostring(ctx.storySource)
        if ctx.lastIgnoredStoryObjective~=staleKey then
            ctx.lastIgnoredStoryObjective=staleKey
            moduleLog("INFO","[AutoPrestige] Ignoring stale Storyline objective "
                ..tostring(mappedStorySource).." because progression is already at "..tostring(ctx.storySource))
        end
        talkObjective=false
        mappedStorySource=nil
    elseif not talkObjective then
        ctx.lastIgnoredStoryObjective=nil
    end
    local genericGiornoGuardQuest=genericPatchActive
        and questMaxProgress==5 and questProgress<questMaxProgress
    local isSecurityQuest=(genericPatchActive and questMaxProgress==5)
        or storyObjective=="Help Giorno by Defeating Security Guards"
        or hasQuest(questPanel,"Help Giorno by Defeating Security Guards")
    local isLucaQuest=storyObjective=="Defeat Leaky Eye Luca"
        or hasQuest(questPanel,"Defeat Leaky Eye Luca")
    local isBucciaratiQuest=storyObjective=="Defeat Bucciarati"
        or hasQuest(questPanel,"Defeat Bucciarati")
    local isMoneyQuest=storyObjective=="Collect $5,000 To Cover For Popo's Real Fortune"
        or hasQuest(questPanel,"Collect $5,000 To Cover For Popo's Real Fortune")
    if isMoneyQuest and ctx.storySource=="Storyline #11" then
        if not ctx.lastMoneyQuestStaleLog then
            ctx.lastMoneyQuestStaleLog=true
            moduleLog("INFO","[AutoPrestige] Trish Storyline #11 already accepted; ignoring the stale $5,000 objective while the Fugo mission refreshes")
        end
        isMoneyQuest=false
    elseif not isMoneyQuest then
        ctx.lastMoneyQuestStaleLog=nil
    end
    local isFugoQuest=storyObjective=="Defeat Fugo And His Purple Haze"
        or hasQuest(questPanel,"Defeat Fugo And His Purple Haze")
    local isPesciQuest=storyObjective=="Defeat Pesci"
        or hasQuest(questPanel,"Defeat Pesci")
    local isGhiaccioQuest=storyObjective=="Defeat Ghiaccio"
        or hasQuest(questPanel,"Defeat Ghiaccio")
    local isDiavoloQuest=storyObjective=="Defeat Diavolo"
        or hasQuest(questPanel,"Defeat Diavolo")
    local auditStoryState=table.concat({
        tostring(storyObjective or "none"),
        tostring(mappedStorySource or "none"),
        tostring(ctx.storySource or "none"),
        tostring(questProgress).."/"..tostring(questMaxProgress),
        tostring(storyLevel),
        tostring(storyPrestige)
    },"|")
    if ctx.lastRemoteAuditStoryState~=auditStoryState then
        ctx.lastRemoteAuditStoryState=auditStoryState
        auditStage("STORY_STATE",{
            objective=storyObjective or "none",
            nextSource=mappedStorySource or "none",
            checkpoint=ctx.storySource or "none",
            quest=tostring(questProgress).."/"..tostring(questMaxProgress),
            level=storyLevel,
            prestige=storyPrestige
        })
    end
    local mappedCombatQuest=isSecurityQuest or isLucaQuest or isBucciaratiQuest
        or isMoneyQuest or isFugoQuest or isPesciQuest or isGhiaccioQuest or isDiavoloQuest
    local namedStoryQuest=hasKnownStoryQuest(questPanel) or koichiSuitcaseQuest or mappedCombatQuest
    local knownStoryQuest=genericGiornoGuardQuest or namedStoryQuest

    -- On Prestige, YBA clears its quest UI. Use the account-wide confirmed
    -- Storyline high-water mark to resume the current arc instead of replaying
    -- the first missions. A completed #17 chain is never started again.
    local liveStoryStage=0
    if isSecurityQuest then liveStoryStage=1
    elseif isLucaQuest then liveStoryStage=3
    elseif isBucciaratiQuest then liveStoryStage=4
    elseif isMoneyQuest then liveStoryStage=10
    elseif isFugoQuest then liveStoryStage=11
    elseif isPesciQuest then liveStoryStage=12
    elseif isGhiaccioQuest then liveStoryStage=14
    elseif isDiavoloQuest then liveStoryStage=17
    elseif objectiveStoryIndex then liveStoryStage=objectiveStoryIndex end

    -- A manually accepted Ghiaccio mission is stronger evidence than the
    -- previous dialogue checkpoint. Persist it before any dialogue handoff so
    -- a Prestige/rejoin resumes at this arc instead of replaying old chapters.
    if isGhiaccioQuest and not ctx.storyPreviouslyCompleted then
        local checkpointSource="Storyline #14"
        local accountKey=tostring(LocalPlayer.UserId)
        local saved=modules.Config:Get("AutoPrestigeStoryProgress")
        if type(saved)~="table" then saved={} end
        local previous=saved[accountKey]
        local previousIndex=type(previous)=="table" and (tonumber(previous.index) or 0) or 0
        local previousHigh=type(previous)=="table" and (tonumber(previous.highestIndex) or previousIndex) or 0
        local previousSource=type(previous)=="table" and previous.source or nil
        local previousHighSource=type(previous)=="table" and (previous.highestSource or previous.source) or nil
        local checkpointIndex=math.max(previousIndex,14)
        local checkpointSavedSource=checkpointIndex==14 and checkpointSource or (previousSource or checkpointSource)
        local highestIndex=math.max(previousHigh,14)
        local highestSource=highestIndex==14 and checkpointSource or (previousHighSource or checkpointSavedSource)
        local currentIndex=tonumber(tostring(ctx.storySource or ""):match("^Storyline #(%d+)$")) or 0
        local checkpointRecord={
            source=checkpointSavedSource,
            index=checkpointIndex,
            prestige=storyPrestige,
            highestIndex=highestIndex,
            highestSource=highestSource,
            completed=(type(previous)=="table" and previous.completed==true)
        }
        local changed=type(previous)~="table"
            or checkpointIndex>previousIndex
            or highestIndex>previousHigh
            or tonumber(previous.prestige)~=storyPrestige
            or previous.source~=checkpointSavedSource
        if changed then
            saved[accountKey]=checkpointRecord
            local persisted,persistErr=pcall(function()
                modules.Config:Set("AutoPrestigeStoryProgress",saved)
            end)
            if persisted then
                moduleLog("INFO","[SessionResume] Active Defeat Ghiaccio quest confirmed; saved Storyline #14 checkpoint at Prestige "
                    ..tostring(storyPrestige).." so Prestige will not replay earlier chapters")
            else
                moduleLog("WARN","[SessionResume] Could not persist active Ghiaccio checkpoint: "..tostring(persistErr))
            end
        end
        if checkpointIndex>=currentIndex then ctx.storySource=checkpointSavedSource end
        ctx.storyHighWaterIndex=highestIndex
        ctx.storyResumeSource=highestSource
    end

    local savedStoryHigh=tonumber(ctx.storyHighWaterIndex) or 0
    if ctx.storyResumeAfterPrestige and ctx.storyPreviouslyCompleted then
        ctx.storyResumeAfterPrestige=false
        moduleLog("INFO","[AutoPrestige] Storyline was explicitly marked complete after the final Giorno reward; skipping repeated main-story quests")
    elseif ctx.storyResumeAfterPrestige and savedStoryHigh>=11 and savedStoryHigh<=17 then
        if liveStoryStage==0 or liveStoryStage<savedStoryHigh then
            local resumeSource=savedStoryHigh>=17 and "Storyline #17" or (ctx.storyResumeSource or ctx.storySource)
            if resumeSource and ctx:HasStoryDefinition(resumeSource) then
                moduleLog("INFO","[AutoPrestige] Prestige carryover: resuming from last confirmed checkpoint "
                    ..tostring(resumeSource).." instead of replaying early Storyline steps")
                storyDialogue(resumeSource,resumeSource=="Storyline #17" and "Defeat Diavolo" or nil)
                ctx.storyResumeAfterPrestige=false
                return true
            end
        else
            ctx.storyResumeAfterPrestige=false
            moduleLog("INFO","[AutoPrestige] Live Storyline objective is already at/after the saved Prestige checkpoint; following live quest state")
        end
    end

    if ctx.storyPreviouslyCompleted then
        koichiSuitcaseQuest=false
        talkObjective=false
        isSecurityQuest=false
        isLucaQuest=false
        isBucciaratiQuest=false
        isMoneyQuest=false
        isFugoQuest=false
        isPesciQuest=false
        isGhiaccioQuest=false
        isDiavoloQuest=false
        mappedCombatQuest=false
        namedStoryQuest=false
        genericGiornoGuardQuest=false
        knownStoryQuest=false
    end

    -- Generic Patch/Sample rows may be unrelated side quests. Only the confirmed
    -- StoryObjective mapper or a live known Storyline NPC can authorize dialogue.
    -- A restart can happen after XenonLock has already defeated a boss.
    -- If the replicated objective counter is complete, go straight to its exact
    -- quest-giver dialogue instead of waiting for a boss that has already despawned.
    if questComplete and mappedCombatQuest then
        local turnInSource=nil
        if isSecurityQuest then
            turnInSource="Storyline #1"
        elseif isLucaQuest then
            turnInSource="Storyline #3"
        elseif isBucciaratiQuest then
            turnInSource="Storyline #4"
        elseif isFugoQuest then
            turnInSource="Storyline #11"
        elseif isPesciQuest then
            turnInSource="Storyline #13"
        elseif isGhiaccioQuest then
            turnInSource="Storyline #15"
        elseif isDiavoloQuest then
            turnInSource="Storyline #17"
        end
        if turnInSource then
            moduleLog("INFO","[AutoPrestige] Completed story objective detected; resuming turn-in at "..turnInSource)
            local turnInConfirmed=false
            if isFugoQuest then
                turnInConfirmed=storyDialogue(turnInSource,"Defeat Pesci")
            elseif isGhiaccioQuest then
                turnInConfirmed=storyDialogue(turnInSource,"Post-Ghiaccio handoff")
            elseif isDiavoloQuest then
                turnInConfirmed=storyDialogue(turnInSource,"Final story reward")
            else
                turnInConfirmed=storyDialogue(turnInSource)
            end
            if isDiavoloQuest and turnInConfirmed then
                ctx.storyFinalComplete=true
                ctx:MarkStoryCompleted()
                moduleLog("INFO","[AutoPrestige] Final Storyline #17 turn-in confirmed after recovery")
            end
            ctx:Wait(0.2)
            return true
        end
    end

    if koichiSuitcaseQuest and ctx.storySource~="Storyline #2" then
        moduleLog("INFO","[AutoPrestige] Quest: Return Koichi's Suitcase; opening Storyline #2")
        storyDialogue("Storyline #2")
        ctx:Wait(0.2)
        return true
    end

    -- Recover cleanly when the executor/runtime is restarted mid-story. Only
    -- talk objectives get mapped here; combat targets remain handled by XenonLock.
    if talkObjective and mappedStorySource and mappedStorySource~=ctx.storySource
        and not hasQuest(questPanel,"Defeat Fugo And His Purple Haze")
        and not hasQuest(questPanel,"Defeat Pesci")
        and not hasQuest(questPanel,"Defeat Ghiaccio")
        and not hasQuest(questPanel,"Defeat Diavolo")
        and not hasQuest(questPanel,"Defeat Bucciarati")
        and not hasQuest(questPanel,"Defeat Leaky Eye Luca") then
        moduleLog("INFO","[AutoPrestige] Story talk objective mapped to "..mappedStorySource
            .." ("..tostring(storyObjective)..")")
        if storyObjective=="Talk to Trish after Fugo" then
            storyDialogue(mappedStorySource,"Defeat Pesci")
        elseif storyObjective=="Talk to Bruno at the castle" then
            storyDialogue(mappedStorySource,"Post-Bruno handoff")
        elseif storyObjective=="Talk to Giorno about Diavolo" then
            storyDialogue(mappedStorySource,"Defeat Diavolo")
        else
            storyDialogue(mappedStorySource)
        end
        ctx:Wait(0.2)
        return true
    end

    -- An accepted main-story objective always has priority over a saved
    -- dialogue handoff. In particular, never open Storyline #14 while the
    -- active Defeat Ghiaccio quest is waiting to be completed.
    if not knownStoryQuest and not mappedCombatQuest and not talkObjective
        and advanceKnownStoryDialogue() then
        return true
    end

    -- A saved #14 checkpoint means Mista already sent the player to defeat
    -- Ghiaccio. After that boss is gone, the next Mista conversation is #15.
    -- The prior build incorrectly reopened #14 and waited for Diavolo directly.
    if not knownStoryQuest and not mappedCombatQuest and not talkObjective
        and not ctx.storyPreviouslyCompleted and ctx.storySource=="Storyline #14"
        and storyPrestige==0 and storyLevel>=20 and storyLevel<50 then
        local retryAt=tonumber(ctx.lastPostGhiaccioRecoveryAt) or 0
        if os.clock()-retryAt>=12 then
            ctx.lastPostGhiaccioRecoveryAt=os.clock()
            local available,reason=ctx:HasStoryDefinition("Storyline #15")
            if available then
                moduleLog("INFO","[AutoPrestige] Post-Ghiaccio recovery: checkpoint #14 found with no active story quest; opening Mista Storyline #15")
                auditStage("POST_GHIACCIO_RECOVERY",{checkpoint="Storyline #14",next="Storyline #15"})
                storyDialogue("Storyline #15","Post-Ghiaccio handoff")
            else
                moduleLog("WARN","[AutoPrestige] Mista Storyline #15 is not replicated yet: "..tostring(reason))
            end
        end
        return true
    end

    -- Storyline #4 hands over the lighter; #5 is the Giorno hand-in/recruit step.
    if hasLighter and storyLevel<=10
        and (ctx.storySource==nil or ctx.storySource=="Storyline #4") then
        moduleLog("INFO","[AutoPrestige] Lighter detected; opening Giorno Storyline #5")
        storyDialogue("Storyline #5")
        return true
    end

    -- The user's current progression is post-Bruno-boss: Bruno #4 at the
    -- Cafeteria gives the lighter. A generic Sample "KILL 5 THUGS" side quest
    -- and PlayerStats.QuestProgress 1/1 must never be mistaken for a Storyline.
    -- This bootstrap is only for the original Level 10 handoff; a rejoin at
    -- Level 11+ must resume from its saved Storyline, never restart at Bruno.
    if not knownStoryQuest and not talkObjective
        and ctx.storySource==nil
        and storyPrestige==0 and storyLevel==10 then
        local brunoAvailable,brunoInfo=ctx:HasStoryDefinition("Storyline #4")
        if brunoAvailable then
            moduleLog("INFO","[AutoPrestige] No active Storyline objective; detected live Bruno Bucciarati #4 at Cafeteria. Starting lighter handoff.")
            storyDialogue("Storyline #4")
            return true
        else
            moduleLog("WARN","[AutoPrestige] Waiting for Bruno Bucciarati #4 Cafeteria prompt: "..tostring(brunoInfo))
        end
    end

    -- Rejoin recovery for the observed Level 13 stage: the earlier gang arc
    -- has ended and Trish #11 is the next dialogue once the player has $5,000.
    -- This path is also used when the quest UI only exposes a generic Sample row.
    local moneyNow=tonumber(LocalPlayer.PlayerStats.Money.Value) or 0
    local resumeTrishFromSaved=(ctx.storySource=="Storyline #10")
    local resumeTrishFromLevel=(ctx.storySource==nil and storyPrestige==0
        and storyLevel>=13 and storyLevel<15)
    if not knownStoryQuest and not talkObjective
        and (resumeTrishFromSaved or resumeTrishFromLevel) and moneyNow>=5000 then
        local trishAvailable,trishInfo=ctx:HasStoryDefinition("Storyline #11")
        if trishAvailable then
            moduleLog("INFO","[AutoPrestige] Rejoin recovery: resuming Trish Una Storyline #11 automatically (Level="
                ..tostring(storyLevel)..", Money="..tostring(moneyNow).."); no manual quest acceptance required")
            storyDialogue("Storyline #11")
            return true
        else
            moduleLog("WARN","[AutoPrestige] Trish Storyline #11 definition unavailable during rejoin recovery: "..tostring(trishInfo))
        end
    elseif resumeTrishFromLevel and moneyNow<5000 then
        moduleLog("INFO","[AutoPrestige] Trish rejoin checkpoint detected, waiting until wallet reaches $5,000 (current $"
            ..tostring(moneyNow)..")")
    end

    -- Post-Fugo rejoin checkpoint: Trish's next conversation is still
    -- Storyline #11. Reuse that exact definition and wait for the Pesci row.
    local resumeTrishAfterFugoFromSaved=(ctx.storySource=="Storyline #11"
        or ctx.storySource=="Storyline #12")
    local resumeTrishAfterFugoFromLevel=(ctx.storySource==nil and storyPrestige==0
        and storyLevel>=16 and storyLevel<=17)
    if not knownStoryQuest and not talkObjective
        and (resumeTrishAfterFugoFromSaved or resumeTrishAfterFugoFromLevel) then
        local trishAfterFugoAvailable,trishAfterFugoInfo=ctx:HasStoryDefinition("Storyline #11")
        if trishAfterFugoAvailable then
            moduleLog("INFO","[AutoPrestige] Post-Fugo checkpoint detected; returning to Trish Storyline #11 (Level="
                ..tostring(storyLevel)..", source="..tostring(ctx.storySource or "live-level")..")")
            storyDialogue("Storyline #11","Defeat Pesci")
            return true
        else
            moduleLog("WARN","[AutoPrestige] Trish Storyline #11 unavailable during post-Fugo recovery: "
                ..tostring(trishAfterFugoInfo))
        end
    end

    if genericPatchActive and not genericGiornoGuardQuest and not namedStoryQuest and not ctx.storyPreviouslyCompleted then
        local source,reason=ctx:TryStorySource()
        if source then
            moduleLog("INFO","[AutoPrestige] Generic Patch objective "..tostring(questProgress).."/"
                ..tostring(questMaxProgress).." has a Storyline source "..tostring(source).."; opening it")
            storyDialogue(source)
        else
            moduleLog("WARN","[AutoPrestige] Generic Patch counter is not a Storyline objective; ignoring it and waiting for a mapped story task: "
                ..tostring(reason))
        end
        ctx:Wait(0.2)
        return true
    end

    -- A Sample/Thug quest counter is not proof that the Storyline itself is complete.
    -- Never call StorySource solely because PlayerStats.QuestProgress says X/X.

    if genericGiornoGuardQuest then
        moduleLog("INFO","[AutoPrestige] Generic Patch + active 5-step counter identified as Giorno Security Guards")
    end

    if isSecurityQuest then
        moduleLog("INFO", "[AutoPrestige] Quest: Security Guard")
        local progress,maxProgress=questProgressState()
        local goal=maxProgress>0 and maxProgress or 5
        local attempts=0

        while progress<goal and attempts<20 do
            ctx:Check()
            attempts=attempts+1
            moduleLog("INFO",("[AutoPrestige] Security Guard progress: %s/%s")
                :format(tostring(progress),tostring(goal)))

            if not killNPC("Security Guard",15) then
                moduleLog("WARN","[AutoPrestige] Security Guard not confirmed; retrying on the next cycle")
                return true
            end

            local previousProgress=progress
            local creditDeadline=tick()+5
            repeat
                ctx:Wait(0.1)
                progress,maxProgress=questProgressState()
                if maxProgress>0 then goal=maxProgress end
            until progress>previousProgress or tick()>=creditDeadline

            if progress<=previousProgress then
                moduleLog("WARN","[AutoPrestige] Guard defeated but quest credit has not replicated; checking again next cycle")
                return true
            end
        end

        if progress>=goal then
            moduleLog("INFO","[AutoPrestige] Security Guard objective complete; returning to Giorno")
            ctx:Wait(1)
            storyDialogue("Storyline #1")
        else
            moduleLog("WARN","[AutoPrestige] Security Guard loop reached its safety limit; rechecking quest state")
        end
        return true

    elseif not getgenv().standList[LocalPlayer.PlayerStats.Stand.Value]
    and LocalPlayer.PlayerStats.Level.Value >= 3 and dontTPOnDeath then
        moduleLog("INFO", "[AutoPrestige] No valid stand — farming arrows.")
        attemptStandFarm()
        dontTPOnDeath = true
        return true

    elseif isLucaQuest and getgenv().standList[LocalPlayer.PlayerStats.Stand.Value] then
        moduleLog("INFO", "[AutoPrestige] Quest: Leaky Eye Luca")
        if killNPC("Leaky Eye Luca", 15) then
            task.wait(1)
            storyDialogue("Storyline #3")
            return true
        else
            return true
        end

    elseif isBucciaratiQuest then
        moduleLog("INFO", "[AutoPrestige] Quest: Bucciarati")
        if killNPC("Bucciarati", 15) then
            task.wait(1)
            moduleLog("INFO", "[AutoPrestige] Bucciarati defeated; opening Storyline #4 to accept the next mission")
            storyDialogue("Storyline #4")
            return true
        else
            return true
        end

    elseif isMoneyQuest then
        moduleLog("INFO", "[AutoPrestige] Quest: Collect $5,000")
        if LocalPlayer.PlayerStats.Money.Value >= 5000 then
            moduleLog("INFO","[AutoPrestige] $5,000 requirement confirmed; opening Trish Storyline #11")
            storyDialogue("Storyline #11","Defeat Fugo")
            return true
        end
        if LocalPlayer.PlayerStats.Money.Value < 5000 then
            local function collectAndSell(toolName, amount)
                if countItems(toolName) <= amount then
                    if LocalPlayer.PlayerStats.Money.Value>=5000 then return true end
                    farmItem(toolName, 1)
                    endDialogue("Merchant", "Dialogue5", "Option2")
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

    elseif isFugoQuest then
        moduleLog("INFO", "[AutoPrestige] Quest: Fugo")
        if killNPC("Fugo", 15) then
            task.wait(1)
            storyDialogue("Storyline #11","Defeat Pesci")
            return true
        else
            return true
        end

    elseif isPesciQuest then
        moduleLog("INFO", "[AutoPrestige] Quest: Pesci")
        if killNPC("Pesci", 15) then
            task.wait(1)
            storyDialogue("Storyline #13")
            return true
        else
            return true
        end

    elseif isGhiaccioQuest then
        moduleLog("INFO", "[AutoPrestige] Quest: Ghiaccio")
        if killNPC("Ghiaccio", 15) then
            task.wait(1)
            moduleLog("INFO","[AutoPrestige] Ghiaccio defeated; returning to Mista Storyline #15 before Bruno #16 and Giorno #17")
            auditStage("GHIACCIO_DEFEATED",{next="Storyline #15",target="Mista"})
            storyDialogue("Storyline #15","Post-Ghiaccio handoff")
            return true
        else
            return true
        end

    elseif isDiavoloQuest then
        moduleLog("INFO", "[AutoPrestige] Quest: Diavolo")
        if killNPC("Diavolo", 15) then
            task.wait(1)
            moduleLog("INFO","[AutoPrestige] Diavolo defeated; opening Giorno Storyline #17 reward dialogue")
            local finalTurnIn=storyDialogue("Storyline #17","Final story reward")
            if finalTurnIn then
                ctx.storyFinalComplete=true
                ctx:MarkStoryCompleted()
                moduleLog("INFO","[AutoPrestige] Storyline #17 reward dialogue confirmed; story chain marked complete for this runtime")
            else
                moduleLog("WARN","[AutoPrestige] Diavolo was defeated, but the final Giorno reward dialogue is not yet confirmed; preserving checkpoint")
            end
        end
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

    elseif hasQuest(questPanel, "Take down 3 vampires")
    and LocalPlayer.PlayerStats.Spec.Value ~= "None"
    and LocalPlayer.PlayerStats.Level.Value >= 25
    and LocalPlayer.PlayerStats.Level.Value ~= 50 then
        moduleLog("INFO", "[AutoPrestige] Quest: Vampires")
        getgenv().HamonCharge = 10
        local vampireDialogueAttempted=false
        local function vampire()
            local living=workspace:FindFirstChild("Living")
            local vampireNPC=living and living:FindFirstChild("Vampire")
            local vampireRoot=vampireNPC and vampireNPC:FindFirstChild("HumanoidRootPart")
            local character=LocalPlayer.Character
            if vampireRoot and character and character.PrimaryPart then
                character.PrimaryPart.CFrame=vampireRoot.CFrame-Vector3.new(0,15,0)
            end
            if not hasQuest(questPanel,"Take down 3 vampires") and not vampireDialogueAttempted then
                vampireDialogueAttempted=true
                if (tick()-lastTick)>=5 then lastTick=tick() end
                endDialogue("William Zeppeli","Dialogue4","Option1")
                return true
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


    moduleLog("INFO","[AutoPrestige] Story worker active; running first quest scan immediately")
    local lastProgressLogAt=os.clock()+30
    while ctx:Active() do
        local characterReadyStarted=os.clock()
        refreshCharacter()
        local characterReadyWait=os.clock()-characterReadyStarted
        if characterReadyWait>1.5 and not ctx.characterReadyDelayLogged then
            ctx.characterReadyDelayLogged=true
            moduleLog("INFO",("[AutoPrestige] Character/remotes became ready after %.1fs; resuming quest scan"):format(characterReadyWait))
        end
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
        if os.clock()>=lastProgressLogAt then
            lastProgressLogAt=os.clock()+30
            moduleLog("INFO","[AutoPrestige] Still progressing; no progress timeout. Current state: "
                ..ctx:Fingerprint())
        end
        ctx:Wait(0.2)
    end
end)
support:Watch()
