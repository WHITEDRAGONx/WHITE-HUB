-- =====================
-- CombatFarm.lua
-- Unified combat: NPC and Quest farming.
-- QUEST/COMBAT BUILD: R15-COMBAT-STABLE-LOCAL-DIALOGUE
-- Logic identical to Xenon V5 (stand positioning, attacks, death detection).
-- FIXED: player positioned underground (yOffset -35) with noclip for safety.
-- =====================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Player = Players.LocalPlayer

-- Observational task accounting; attack/movement/dialogue algorithms unchanged.
local nativeTask = task
local outstandingTasks = 0
local task = setmetatable({spawn = function(callback, ...)
    local args = table.pack(...)
    outstandingTasks = outstandingTasks + 1
    return nativeTask.spawn(function()
        local ok, failure = pcall(callback, table.unpack(args, 1, args.n))
        outstandingTasks = outstandingTasks - 1
        if not ok then error(failure, 0) end
    end)
end}, {__index = nativeTask})

local CombatFarm = {}

local _config    = nil
local _inventory = nil
local _movement  = nil
local _serverHop = nil
local _webhook   = nil

local activeMode = nil
local isRunning = false
local stopRequested = false
local runId = 0
local questWatcherConnection = nil
local currentQuest = nil
-- Only a quest dialogue confirmed by this worker is eligible for the
-- shortcut/turn-in logic. Global QuestProgress cannot identify quest owner.
local sessionQuestName = nil
local questCompleted = false
local questOnCooldown = false
local cooldownUntil = 0

-- Only one movement controller can own the character at a time.
-- Pause Item Farm in memory while NPC/Quest Farm runs, without editing Farm.lua,
-- Inventory.lua or the saved configuration on disk.
local itemFarmPausedByCombat = false
local itemFarmWasEnabled = false

local SAFE_SPOT = CFrame.new(978, -42, -49)
local lastSafeTeleportAt = 0
local lastStandSummonLogAt = 0

local questInfo = {
    ["Officer Sam [Lvl. 1+]"] = { enemy = "Thug", autoChoose = true },
    ["Deputy Bertrude [Lvl. 10+]"] = { enemy = "Corrupt Police", autoChoose = true },

    -- The current game uses this no-dot level format. DialogueAnalyzer confirmed
    -- its updated quest dialogue is Option1 -> Option1 -> Option1.
    ["Abbacchio's Partner [Lvl 15+]"] = { enemy = "Alpha Thug", autoChoose = true },
    -- Alias retained in case YBA changes only the display punctuation.
    ["Abbacchio's Partner [Lvl. 15+]"] = { enemy = "Alpha Thug", autoChoose = true },

    -- Fetch/daily quest: selectable manually, but intentionally skipped by Auto Choose.
    ["Homeless Man Jill [Lvl. 15+]"] = { item = "Gold Coin", amount = 10, autoChoose = false },

    ["Dracula [Lvl. 20+]"] = { enemy = "Zombie Henchman", autoChoose = true },
    ["William Zeppeli [Lvl. 25+]"] = { enemy = "Vampire", autoChoose = true },
    ["Doppio [Lvl. 30+]"] = { enemy = "Dio", autoChoose = true },
    ["Dio [Lvl. 35+]"] = { enemy = "Jotaro", autoChoose = false },

    -- Detected level quests which need their own objective/controller mapping.
    ["Darius, The Executioner [Lvl. 20+]"] = { special = "PVP_STAND", autoChoose = false },
    ["Kars [Lvl. 30+]"] = { special = "PVP_HAMON", autoChoose = false },
    ["Pucci [Lvl. 40+]"] = { special = "PUCCI_CHAIN", autoChoose = false },
}


-- =============================================
-- MOBILE SKILL CATALOG / CAST PROFILES
-- =============================================
-- Keys here are intentionally limited to offensive moves. Utility moves such as
-- Time Skip / Time Stop are not auto-enabled by the UI.
local function normalizeName(value)
    return tostring(value or ""):lower():gsub("[^%w]", "")
end

local STAND_ALIASES = {
    ["platinumsun"] = "starplatinum",
    ["platinumsuntheuniverse"] = "starplatinumtheworld",
    ["theuniverse"] = "theworld",
    ["theuniverseoverheaven"] = "theworldoverheaven",
    ["purplefume"] = "purplehaze",
    ["whiteice"] = "whitealbum",
    ["frighteningmonsters"] = "scarymonsters",
}

local STAND_SKILL_PRESETS = {
    starplatinum = {
        { key = "E", name = "Stand Barrage" },
        { key = "R", name = "Barrage Finisher" },
        { key = "T", name = "Star Finger" },
        { key = "Y", name = "Ora Kicks" },
        { key = "G", name = "Inhale" },
        { key = "C", name = "Platinum Slam", closeCast = true, hold = 0.28 },
    },
    starplatinumtheworld = {
        { key = "E", name = "Stand Barrage" },
        { key = "R", name = "Barrage Finisher" },
        { key = "T", name = "Bearing Shot" },
        { key = "Y", name = "Ora Kicks" },
        { key = "X", name = "Platinum Slam", closeCast = true, hold = 0.28 },
        { key = "C", name = "Skull Crusher" },
    },
    theworld = {
        { key = "E", name = "Stand Barrage" },
        { key = "R", name = "Barrage Finisher" },
        { key = "T", name = "Knife Throw" },
        { key = "Y", name = "Road Sign Slam", closeCast = true, hold = 0.30 },
        { key = "X", name = "Kick Barrage" },
        { key = "C", name = "SHINEI" },
    },
    theworldoverheaven = {
        { key = "E", name = "Stand Barrage" },
        { key = "R", name = "Barrage Finisher" },
        { key = "T", name = "Knife Throw" },
        { key = "Y", name = "Reality Overwriting Punch" },
        { key = "G", name = "Heaven Ascended Smite", closeCast = true, hold = 0.32 },
    },
    purplehaze = {
        { key = "E", name = "Stand Barrage" },
        { key = "R", name = "Barrage Finisher" },
        { key = "T", name = "Bulb Breaker Punch" },
        { key = "Y", name = "Bulb Breaker Ground Punch", closeCast = true, hold = 0.32 },
        { key = "Z", name = "Bulb Throw" },
    },
    whitealbum = {
        { key = "E", name = "Barrage" },
        { key = "R", name = "Barrage Finisher" },
        { key = "T", name = "Ice Punch" },
        { key = "Y", name = "Ice Sweeps" },
        { key = "X", name = "Flash Freeze", closeCast = true, hold = 0.30 },
        { key = "C", name = "Ice Swipe" },
    },
    cream = {
        { key = "E", name = "Stand Barrage" },
        { key = "R", name = "Barrage Finisher" },
        { key = "T", name = "Devastation" },
        { key = "Y", name = "Dark Space" },
        { key = "Z", name = "Void Surprise" },
        { key = "X", name = "Madness Sorrow", closeCast = true, hold = 0.34 },
    },
    scarymonsters = {
        { key = "E", name = "Claw Barrage" },
        { key = "R", name = "Finisher" },
        { key = "T", name = "Tail Whip" },
        { key = "Y", name = "Fossilization" },
        { key = "Z", name = "Dino Dash / Slam", closeCast = true, hold = 0.24 },
        { key = "X", name = "Dino Army" },
        { key = "C", name = "Dino Barrage" },
    },
    anubis = {
        { key = "E", name = "Slice Barrage" },
        { key = "R", name = "Finisher" },
        { key = "T", name = "Curse Imbued Slice", closeCast = true, hold = 0.24 },
        { key = "X", name = "Enraged Fury" },
    },
    silverchariot = {
        { key = "E", name = "Stand Barrage" },
        { key = "R", name = "Barrage Finisher" },
        { key = "Y", name = "Cycle Slash", closeCast = true, hold = 0.24 },
        { key = "Z", name = "Last Shot" },
    },
}

local GENERIC_MOBILE_SKILLS = {
    { key = "E", name = "Primary Skill" },
    { key = "R", name = "Heavy Skill" },
    { key = "T", name = "Skill T" },
    { key = "Y", name = "Skill Y" },
    { key = "G", name = "Skill G" },
    { key = "X", name = "Skill X" },
    { key = "C", name = "Skill C" },
}

local function getCurrentStandName()
    local stats = Player:FindFirstChild("PlayerStats")
    local stand = stats and stats:FindFirstChild("Stand")
    return stand and tostring(stand.Value) or "None"
end

local function getStandPreset()
    local rawName = getCurrentStandName()
    local key = normalizeName(rawName)
    key = STAND_ALIASES[key] or key
    return rawName, key, STAND_SKILL_PRESETS[key]
end

local function getSkillProfile(keyName)
    local _, _, preset = getStandPreset()
    if not preset then return nil end
    for _, entry in ipairs(preset) do
        if entry.key == keyName then
            return entry
        end
    end
    return nil
end


local GUI_SKILL_KEYS = {
    E=true, R=true, T=true, Y=true, U=true, G=true, H=true,
    Z=true, X=true, C=true, V=true, B=true, N=true, J=true,
}

local function scanGuiSkillCatalog()
    local found = {}
    local playerGui = Player:FindFirstChild("PlayerGui")
    if not playerGui then return {} end

    for _, obj in ipairs(playerGui:GetDescendants()) do
        if obj:IsA("TextLabel") or obj:IsA("TextButton") then
            local text = tostring(obj.Text or ""):gsub("\n", " ")
            local key, name = text:match("^%s*([A-Z])%s*[-:%|•]%s*(.+)")
            if key and GUI_SKILL_KEYS[key] and name and #name <= 80 then
                name = name:gsub("^%s+", ""):gsub("%s+$", "")
                if name ~= "" and not found[key] then
                    found[key] = { key = key, name = name }
                end
            end
        end
    end

    local ordered = {}
    local order = {"E","R","T","Y","U","G","H","Z","X","C","V","B","N","J"}
    for _, key in ipairs(order) do
        if found[key] then ordered[#ordered + 1] = found[key] end
    end
    return ordered
end

local lastStandSummonAt = 0
local function ensureStandSummoned(character)
    if not character then return false, false end
    local summoned = character:FindFirstChild("SummonedStand")
    if not summoned then
        return character:FindFirstChild("StandMorph") ~= nil, false
    end
    if summoned.Value == true then return true, false end

    -- The authoritative flag explicitly says the Stand is OFF. Request the
    -- summon immediately, but keep a short anti-toggle cooldown so repeated
    -- combat frames cannot accidentally spam ToggleStand.
    if tick() - lastStandSummonAt < 0.30 then return false, false end
    local remoteFunc = character:FindFirstChild("RemoteFunction")
    if not remoteFunc then return false, false end
    lastStandSummonAt = tick()
    lastStandSummonLogAt = tick()
    task.spawn(function()
        pcall(function() remoteFunc:InvokeServer("ToggleStand", "Toggle") end)
    end)
    return false, true
end

local _runtimeLog = nil
local _rawPrint, _rawWarn = print, warn
local function moduleLog(level, ...)
    if _runtimeLog and type(_runtimeLog.Write) == "function" then
        pcall(_runtimeLog.Write, _runtimeLog, level, "CombatFarm", ...)
    end
    if level == "WARN" or level == "ERROR" then
        _rawWarn(...)
    else
        _rawPrint(...)
    end
end

local function pauseItemFarmForCombat()
    if not _config or itemFarmPausedByCombat then return end
    itemFarmWasEnabled = _config:Get("FarmEnabled") == true
    itemFarmPausedByCombat = true
    if itemFarmWasEnabled then
        _config:Set("FarmEnabled", false, true)
        moduleLog("INFO", "[CombatFarm][MovementLock] Item Farm temporarily paused; Merchant code unchanged.")
    end
end

local function resumeItemFarmAfterCombat()
    if not itemFarmPausedByCombat then return end
    local shouldResume = itemFarmWasEnabled
    itemFarmPausedByCombat = false
    itemFarmWasEnabled = false
    if shouldResume and _config and _config:Get("FarmEnabled") == false then
        _config:Set("FarmEnabled", true, true)
        moduleLog("INFO", "[CombatFarm][MovementLock] Item Farm resumed.")
    end
end

local function goToSafeSpot(reason)
    if not _movement then return false end
    local hrp = _movement:GetCharacter("HumanoidRootPart")
    if not hrp then return false end
    local distance = (hrp.Position - SAFE_SPOT.Position).Magnitude
    if distance <= 6 then return true end
    if tick() - lastSafeTeleportAt < 0.75 then return true end
    lastSafeTeleportAt = tick()
    _movement:SetNoclip(true)
    _movement:ClearFocus()
    pcall(function() _movement:Teleport(SAFE_SPOT) end)
    pcall(function()
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end)
    _movement:SetNoclip(false)
    _movement:FixCamera()
    moduleLog("INFO", "[CombatFarm][SafeSpot] " .. tostring(reason or "No active target") .. ".")
    return true
end

function CombatFarm:Init(Modules)
    _runtimeLog = Modules.RuntimeLog
    _config    = Modules.Config
    _inventory = Modules.Inventory
    _movement  = Modules.Movement
    _serverHop = Modules.ServerHop
    _webhook   = Modules.Webhook

    if questWatcherConnection then
        pcall(function() questWatcherConnection:Disconnect() end)
        questWatcherConnection = nil
    end

    -- Event-driven quest completion watcher instead of a permanent 0.5s polling loop.
    local function hookHUD()
        local hud = Player.PlayerGui:FindFirstChild("HUD")
        if not hud then return end
        local completedFrame = hud:FindFirstChild("QuestCompleted")
        if completedFrame and completedFrame:IsA("GuiObject") then
            questWatcherConnection = completedFrame:GetPropertyChangedSignal("Visible"):Connect(function()
                if completedFrame.Visible then
                    moduleLog("INFO", "[CombatFarm] Quest completion UI pulse detected; waiting for PlayerStats confirmation.")
                end
            end)
        end
    end

    hookHUD()
    if not questWatcherConnection then
        task.spawn(function()
            for _ = 1, 20 do
                task.wait(0.5)
                if questWatcherConnection then return end
                hookHUD()
            end
        end)
    end
end

-- =============================================
-- HELPER FUNCTIONS
-- =============================================

local function useMove(move)
    local char = _movement:GetCharacter()
    if not char then return end
    if move == "m1" or move == "m2" then
        local remoteFunc = char:FindFirstChild("RemoteFunction")
        if remoteFunc then
            remoteFunc:InvokeServer("Attack", move)
        end
    elseif typeof(move) == "Enum" then
        local remoteEvent = char:FindFirstChild("RemoteEvent")
        if remoteEvent then
            remoteEvent:FireServer("InputBegan", { Input = move })
        end
    end
end

local function equipStand()
    local char = _movement:GetCharacter()
    if not char then return false end
    return ensureStandSummoned(char)
end

local function getNPCHealthState(npc)
    if not npc or not npc.Parent then
        return nil, "despawned"
    end

    -- YBA NPCs expose their authoritative combat health through a custom Health
    -- Value. Xenon V5 relied on this value instead of Humanoid.Health. The
    -- Humanoid may enter a death/ragdoll state before YBA has actually credited
    -- the kill, so prefer Health.Value whenever it exists.
    local healthValue = npc:FindFirstChild("Health")
    if healthValue then
        local hp = tonumber(healthValue.Value)
        if hp ~= nil then
            return hp, "HealthValue"
        end
    end

    local hum = npc:FindFirstChildWhichIsA("Humanoid")
    if hum then
        return tonumber(hum.Health), "Humanoid"
    end

    return nil, "unknown"
end

local function isNPCAlive(npc)
    if not npc or not npc.Parent then return false end
    local hp = getNPCHealthState(npc)
    if hp ~= nil then
        return hp > 0
    end
    return npc:FindFirstChild("HumanoidRootPart") ~= nil
end

local function getClosestNPC(npcName, excludeTarget)
    local closest = nil
    local closestDist = math.huge
    local hrp = _movement:GetCharacter("HumanoidRootPart")
    if not hrp then return nil end

    local living = workspace:FindFirstChild("Living")
    if not living then return nil end

    for _, npc in pairs(living:GetChildren()) do
        if npc ~= excludeTarget and npc.Name == npcName and isNPCAlive(npc) then
            local npcHRP = npc:FindFirstChild("HumanoidRootPart")
            if npcHRP then
                local dist = (hrp.Position - npcHRP.Position).Magnitude
                if dist < closestDist then
                    closestDist = dist
                    closest = npc
                end
            end
        end
    end
    return closest
end

local function isTokenActive(token, expectedMode)
    if stopRequested or token ~= runId then return false end
    if expectedMode and activeMode ~= expectedMode then return false end

    -- Extra safety: even if a UI callback ever fails, the persisted toggle state
    -- can still stop an old worker on the next frame.
    if _config then
        if activeMode == "NPC" and _config:Get("NPCFarmEnabled") ~= true then
            return false
        end
        if activeMode == "Quest" and _config:Get("QuestFarmEnabled") ~= true then
            return false
        end
    end
    return true
end

-- Forward declaration: killTarget waits for QuestProgress credit before the
-- concrete readQuestState implementation later in this module.
local readQuestState
local runPromptDialogueFast

local function waitToken(seconds, token, expectedMode)
    local deadline = tick() + seconds
    while tick() < deadline do
        if not isTokenActive(token, expectedMode) then return false end
        task.wait(math.min(0.05, math.max(0, deadline - tick())))
    end
    return true
end

-- Build: R11-NO-DAMAGE-MELEE-FALLBACK
-- =============================================
-- COMBAT CORE (Xenon V5 style)
-- =============================================
local function killTarget(targetName, token)
    local target = getClosestNPC(targetName)
    if not target then
        moduleLog("INFO", "[CombatFarm] No alive target found: " .. targetName)
        return false
    end

    local character = _movement:GetCharacter()
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    local remoteFunc = character and character:FindFirstChild("RemoteFunction")
    if not character or not hrp or not remoteFunc then
        return false
    end

    local oldPos = hrp.CFrame
    local questProgressBefore, questMaxBefore = nil, nil
    if activeMode == "Quest" then
        questProgressBefore, questMaxBefore = readQuestState()
    end

    local hasStand = _inventory:HasStand()
    if hasStand then
        ensureStandSummoned(character)
    end

    local standMorph = hasStand and character:FindFirstChild("StandMorph") or nil
    local standPart = standMorph and standMorph.PrimaryPart or nil

    local focusCam = character:FindFirstChild("FocusCam")
    local createdFocusCam = false
    local previousFocusValue = focusCam and focusCam.Value or nil
    if not focusCam then
        focusCam = Instance.new("ObjectValue")
        focusCam.Name = "FocusCam"
        focusCam.Parent = character
        createdFocusCam = true
    end

    _movement:SetNoclip(true)

    local safeYOffset = (targetName == "The Idol") and 35 or -35
    local startTime = tick()
    local killed = false
    local lastKnownHp, hpSource = getNPCHealthState(target)
    local lastDamageAt = tick()
    local previousHp = lastKnownHp
    local missingPartsSince = nil
    local attackBusy = false
    local playerMeleeFallback = not hasStand
    local nextSkillAt = 0
    local skillIndex = 1
    local perSkillLastUse = {}
    local closeCastUntil = 0
    local closeCastKey = nil
    local nextM1At = 0
    local suppressM1Until = 0
    local lastSkillCastAt = -math.huge
    local closeCastWasActive = false
    local standGraceUntil = hasStand and (tick() + 1.25) or 0
    local meleeFallbackGraceUntil = 0
    local skillLogSeen = {}

    moduleLog("INFO", ("[CombatFarm][XenonLock] Locked %s | hp=%s source=%s stand=%s"):format(
        tostring(targetName), tostring(lastKnownHp), tostring(hpSource), tostring(getCurrentStandName())
    ))

    while isTokenActive(token) and tick() - startTime < 60 do
        if not target or not target.Parent then
            killed = true
            break
        end

        local hp, source = getNPCHealthState(target)
        if hp ~= nil then
            lastKnownHp = hp
            hpSource = source
            if previousHp ~= nil and hp < previousHp - 0.001 then
                lastDamageAt = tick()
            end
            previousHp = hp
            if hp <= 0 then
                task.wait(0.215)
                killed = true
                break
            end
        end

        local enemyHRP = target:FindFirstChild("HumanoidRootPart")
        local enemyHumanoid = target:FindFirstChildWhichIsA("Humanoid")
        if not enemyHRP or not enemyHumanoid then
            if not missingPartsSince then missingPartsSince = tick() end
            if tick() - missingPartsSince > 1.0 then
                local currentHp = getNPCHealthState(target)
                if currentHp ~= nil and currentHp <= 0 then
                    killed = true
                    break
                elseif not target.Parent then
                    killed = true
                    break
                end
                missingPartsSince = tick()
            end
            task.wait(0.03)
            continue
        end
        missingPartsSince = nil

        if focusCam and focusCam.Parent then
            focusCam.Value = enemyHRP
        end

        if hasStand then
            local _, summonRequested = ensureStandSummoned(character)
            if summonRequested then
                -- A manual desummon should be recovered immediately. Keep the
                -- player underground while replication catches up; do not enter
                -- melee fallback just because the Stand was temporarily absent.
                playerMeleeFallback = false
                standGraceUntil = tick() + 1.35
            end
            if not standPart or not standPart.Parent then
                standMorph = character:FindFirstChild("StandMorph")
                standPart = standMorph and standMorph.PrimaryPart or nil
            end
        end

        local standCF = enemyHRP.CFrame - enemyHRP.CFrame.LookVector * 1.1
        if standPart and standPart.Parent then
            standPart.CFrame = standCF
        end

        -- IMPORTANT: do NOT move the player into melee range just because the
        -- Stand has not dealt damage recently. Time-stop, invulnerability,
        -- ragdoll and other YBA states can legitimately pause damage and made
        -- the old detector pull the player out of the safe underground position.
        -- Player melee positioning is now used only when the account has no Stand
        -- (plus temporary CLOSE AOE casts below).

        local closeCasting = tick() < closeCastUntil
        if closeCastWasActive and not closeCasting then
            -- CLOSE AOE is only a temporary hitbox reposition. Always return
            -- underground after the cast even if melee fallback had previously
            -- activated; it may re-enable later only after a fresh no-damage test.
            closeCastKey = nil
            playerMeleeFallback = not hasStand
            lastDamageAt = tick()
            meleeFallbackGraceUntil = tick() + 1.75
        end
        closeCastWasActive = closeCasting
        if closeCasting or playerMeleeFallback then
            -- Player-centered hitboxes/AOE need the character itself close to the
            -- victim. Face the NPC from just behind it so short-radius moves land.
            local nearCF = enemyHRP.CFrame - enemyHRP.CFrame.LookVector * 2.0
            hrp.CFrame = CFrame.lookAt(nearCF.Position, enemyHRP.Position)
        elseif standPart and standPart.Parent then
            hrp.CFrame = standCF + standCF.LookVector * -2.5 + Vector3.new(0, safeYOffset, 0)
        else
            -- Stand exists in PlayerStats but is temporarily not materialized.
            -- Keep the player safe while the summon cooldown tries again.
            hrp.CFrame = enemyHRP.CFrame - enemyHRP.CFrame.LookVector * 2.3 + Vector3.new(0, safeYOffset, 0)
        end

        pcall(function()
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end)

        -- Auto Skills are checked before M1. If no skills are enabled, preserve
        -- the original full-speed M1 spam exactly. If skills are enabled, create
        -- tiny input windows so a skill is not starved by continuous M1 requests.
        local skills = _config:Get("AutoSkills")
        local hasAutoSkills = type(skills) == "table" and #skills > 0
        local castedSkillThisFrame = false

        if hasAutoSkills and tick() >= nextSkillAt then
            if skillIndex > #skills then skillIndex = 1 end
            local sk = tostring(skills[skillIndex])
            skillIndex = skillIndex + 1
            local keyCode = Enum.KeyCode[sk]
            local since = tick() - (perSkillLastUse[sk] or 0)
            if keyCode and since >= 2.0 then
                local profile = getSkillProfile(sk)
                perSkillLastUse[sk] = tick()
                lastSkillCastAt = tick()
                nextSkillAt = tick() + 0.28
                castedSkillThisFrame = true

                local skillWindow = 0.18
                if profile and profile.closeCast then
                    local hold = profile.hold or 0.28
                    closeCastKey = sk
                    closeCastUntil = tick() + hold
                    closeCastWasActive = true
                    skillWindow = math.max(skillWindow, hold)
                    -- Prevent the generic no-damage detector from converting this
                    -- temporary AOE reposition into permanent melee fallback.
                    lastDamageAt = tick()
                    playerMeleeFallback = not hasStand
                    meleeFallbackGraceUntil = closeCastUntil + 1.75
                    local nearCF = enemyHRP.CFrame - enemyHRP.CFrame.LookVector * 1.8
                    hrp.CFrame = CFrame.lookAt(nearCF.Position, enemyHRP.Position)
                    pcall(function()
                        hrp.AssemblyLinearVelocity = Vector3.zero
                        hrp.AssemblyAngularVelocity = Vector3.zero
                    end)
                end

                if not skillLogSeen[sk] then
                    skillLogSeen[sk] = true
                    moduleLog("INFO", ("[CombatFarm][Skill] Casting %s%s"):format(
                        tostring(sk), (profile and profile.closeCast) and " [CLOSE AOE]" or ""
                    ))
                end
                suppressM1Until = tick() + skillWindow
                task.spawn(function() pcall(function() useMove(keyCode) end) end)
            else
                nextSkillAt = tick() + 0.08
            end
        end

        local canM1 = (not hasAutoSkills) or (not castedSkillThisFrame and tick() >= suppressM1Until and tick() >= nextM1At)
        if canM1 and not attackBusy then
            attackBusy = true
            if hasAutoSkills then
                nextM1At = tick() + 0.075
            end
            task.spawn(function()
                pcall(function() remoteFunc:InvokeServer("Attack", "m1") end)
                attackBusy = false
            end)
        end

        task.wait()
    end

    if killed and activeMode == "Quest" and isTokenActive(token, "Quest") then
        -- Confirm the server-side quest credit, but do NOT wait for an automatic
        -- DialogueGui here. DialogueAnalyzer/logs proved Dio/Jotaro's completion
        -- page is created only after interacting with the quest NPC again.
        local settleDeadline = tick() + 1.50
        while tick() < settleDeadline and isTokenActive(token, "Quest") do
            local progress, maxProgress = readQuestState()
            local credited = progress ~= questProgressBefore
                or maxProgress ~= questMaxBefore
                or ((maxProgress or 0) > 0 and (progress or 0) >= (maxProgress or 0))

            if credited then
                moduleLog("INFO", ("[CombatFarm][XenonLock] Kill credited | progress=%s/%s"):format(
                    tostring(progress), tostring(maxProgress)
                ))
                if (maxProgress or 0) > 0 and (progress or 0) >= (maxProgress or 0) then
                    -- The combat position is ~35 studs under the victim. Park on
                    -- the real safe spot immediately so gravity cannot drop the
                    -- character into the void while the quest is being turned in.
                    goToSafeSpot("Quest objective complete; preparing instant turn-in")
                end
                break
            end
            task.wait(0.005)
        end
    elseif killed then
        task.wait(0.15)
    end

    local chainedToNext = false
    local questFinishedNow = false
    if killed and activeMode == "Quest" then
        local progress, maxProgress = readQuestState()
        questFinishedNow = ((maxProgress or 0) > 0 and (progress or 0) >= (maxProgress or 0))
    end

    if killed and token == runId and isTokenActive(token) and not questFinishedNow then
        local nextTarget = getClosestNPC(targetName, target)
        local nextHRP = nextTarget and nextTarget:FindFirstChild("HumanoidRootPart")
        if nextTarget and nextHRP and hrp and hrp.Parent then
            if focusCam and focusCam.Parent then
                focusCam.Value = nextHRP
            end

            if hasStand then
                local _, summonRequested = ensureStandSummoned(character)
                if summonRequested then
                    playerMeleeFallback = false
                    standGraceUntil = tick() + 1.35
                end
                standMorph = character:FindFirstChild("StandMorph")
                standPart = standMorph and standMorph.PrimaryPart or nil
            end

            local nextStandCF = nextHRP.CFrame - nextHRP.CFrame.LookVector * 1.1
            if standPart and standPart.Parent then
                standPart.CFrame = nextStandCF
            end

            if playerMeleeFallback then
                local nearCF = nextHRP.CFrame - nextHRP.CFrame.LookVector * 2.0
                hrp.CFrame = CFrame.lookAt(nearCF.Position, nextHRP.Position)
            elseif standPart and standPart.Parent then
                hrp.CFrame = nextStandCF + nextStandCF.LookVector * -2.5 + Vector3.new(0, safeYOffset, 0)
            else
                hrp.CFrame = nextHRP.CFrame - nextHRP.CFrame.LookVector * 2.3 + Vector3.new(0, safeYOffset, 0)
            end

            pcall(function()
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
            end)

            chainedToNext = true
            moduleLog("INFO", ("[CombatFarm][XenonChain] Handoff %s -> next spawn"):format(tostring(targetName)))
        end
    end

    if not chainedToNext then
        if focusCam and focusCam.Parent then
            pcall(function()
                if createdFocusCam then
                    focusCam:Destroy()
                else
                    focusCam.Value = previousFocusValue
                end
            end)
        end
        if token == runId then
            _movement:SetNoclip(false)
            if not killed and hrp and hrp.Parent then
                pcall(function() hrp.CFrame = oldPos end)
            end
        end
    end

    if killed then
        moduleLog("INFO", ("[CombatFarm][XenonLock] Confirmed death: %s | lastHp=%s source=%s"):format(
            tostring(targetName), tostring(lastKnownHp), tostring(hpSource)
        ))
    else
        moduleLog("WARN", ("[CombatFarm][XenonLock] Target lock ended without confirmed death: %s | lastHp=%s source=%s"):format(
            tostring(targetName), tostring(lastKnownHp), tostring(hpSource)
        ))
    end

    return killed
end

-- =============================================
-- NPC FARM
-- =============================================
local function runNPCFarm(token)
    local npcName = _config:Get("SelectedNPC")
    if not npcName or npcName == "" then
        moduleLog("INFO", "[CombatFarm] No NPC selected.")
        return false
    end
    return killTarget(npcName, token)
end

-- =============================================
-- QUEST FARM
-- =============================================
local function questLevelFromName(name)
    local n = tostring(name or "")
    return tonumber(n:match("%[Lvl%.?%s*(%d+)%+%]"))
        or tonumber(n:match("[Ll]vl%.?%s*(%d+)%+"))
end

local function getBestQuest()
    local stats = Player:FindFirstChild("PlayerStats")
    local levelObj = stats and stats:FindFirstChild("Level")
    local level = levelObj and tonumber(levelObj.Value) or 0
    -- User-selected Auto Choose policy: once level 25 is reached, keep
    -- choosing William Zeppeli's Vampire quest rather than Doppio/Dio.
    -- Do not touch the battle controller or change manually selected quests.
    local vampireQuest = "William Zeppeli [Lvl. 25+]"
    if level >= 25 then
        moduleLog("INFO", ("[CombatFarm][QuestChoice] Auto Choose priority: %s -> Vampire (level %d)")
            :format(vampireQuest, level))
        return vampireQuest
    end

    local best = nil
    local bestReq = -1

    for questName, data in pairs(questInfo) do
        if data.autoChoose == true and data.enemy and not data.special then
            local req = questLevelFromName(questName)
            if req and req <= level and req > bestReq then
                bestReq = req
                best = questName
            elseif req and req <= level and req == bestReq and best then
                local dialogues = workspace:FindFirstChild("Dialogues")
                if dialogues and dialogues:FindFirstChild(questName) and not dialogues:FindFirstChild(best) then
                    best = questName
                end
            end
        end
    end

    if best then
        moduleLog("INFO", ("[CombatFarm] Auto Choose selected highest normal quest: %s (player level %s)"):format(
            tostring(best), tostring(level)
        ))
    end
    return best
end

readQuestState = function()
    local stats = Player:FindFirstChild("PlayerStats")
    if not stats then return nil, nil end

    local progressObj = stats:FindFirstChild("QuestProgress")
    local maxProgressObj = stats:FindFirstChild("QuestMaxProgress")

    local progress = progressObj and tonumber(progressObj.Value) or 0
    local maxProgress = maxProgressObj and tonumber(maxProgressObj.Value) or 0
    return progress, maxProgress
end

local function clickDialogueButton(btn)
    if not btn or not btn:IsA("GuiButton") then return false end

    local signal = btn.MouseButton1Click
    -- TestAll proved connection:Fire() is often the only effective input
    -- for YBA's ClientFunctions dialogue callbacks.
    if type(getconnections) == "function" then
        local ok, connections = pcall(getconnections, signal)
        if ok and type(connections) == "table" then
            for _, connection in pairs(connections) do
                if connection then
                    local fire = nil
                    pcall(function() fire = connection.Fire end)
                    if type(fire) == "function" then
                        local fired = pcall(function() connection:Fire() end)
                        if fired then return true end
                    end
                    local fn = nil
                    pcall(function() fn = connection.Function end)
                    if type(fn) == "function" and pcall(fn) then
                        return true
                    end
                end
            end
        end
    end

    if type(firesignal) == "function" and pcall(firesignal, signal) then
        return true
    end

    -- VIM needs a visible GUI. Only use when internal input APIs are missing;
    -- caller restores the original ScreenGui state on failure/exit.
    local gui = btn:FindFirstAncestorWhichIsA("ScreenGui")
    if gui then
        pcall(function() gui.Enabled = true end)
    end
    local ok = pcall(function()
        local pos = btn.AbsolutePosition
        local size = btn.AbsoluteSize
        local x = pos.X + size.X * 0.5
        local y = pos.Y + size.Y * 0.5
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 1)
        task.wait(0.03)
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 1)
    end)
    return ok
end

local function findDialogueOption(optionName)
    local gui = Player.PlayerGui:FindFirstChild("DialogueGui")
    if not gui then return nil end
    local options = gui:FindFirstChild("Options", true)
    if not options then return nil end
    local option = options:FindFirstChild(optionName)
    if not option then return nil end
    return option:FindFirstChildWhichIsA("GuiButton", true)
end


-- New YBA dialogue callbacks (v1.7974+) store the selected option in callback U[1].
-- DialogueAnalyzer confirmed the quest NPC uses the same ClientFunctions callback shape
-- as Merchant: one MouseButton1Click callback, with U[2] pointing at the option ImageLabel.
local function injectDialogueOption(optionName)
    local btn = findDialogueOption(optionName)
    if not btn or not btn.Visible then return false, "not-ready" end

    local getCon = type(getconnections) == "function" and getconnections or nil
    local setUp = type(setupvalue) == "function" and setupvalue
        or (debug and type(debug.setupvalue) == "function" and debug.setupvalue)
    local getUp = type(getupvalue) == "function" and getupvalue
        or (debug and type(debug.getupvalue) == "function" and debug.getupvalue)

    if not getCon or not setUp then return false, "unsupported" end

    local okConnections, connections = pcall(getCon, btn.MouseButton1Click)
    if not okConnections or type(connections) ~= "table" then
        return false, "no-connections"
    end

    for _, connection in ipairs(connections) do
        local fn = connection and (connection.Function or connection["function"])
        if type(fn) == "function" then
            local structurallyValid = true
            if getUp then
                local okU2, u2 = pcall(getUp, fn, 2)
                -- On the mapped ClientFunctions:2063 callback U[2] is the option ImageLabel.
                -- If the executor exposes U[2], reject unrelated callbacks instead of writing U[1].
                if okU2 and u2 ~= nil then
                    structurallyValid = typeof(u2) == "Instance" and (u2 == btn.Parent or btn:IsDescendantOf(u2))
                end
            end

            if structurallyValid then
                local okSet = pcall(setUp, fn, 1, optionName)
                if okSet then
                    if getUp then
                        local okVerify, selected = pcall(getUp, fn, 1)
                        if okVerify and selected ~= nil and tostring(selected) ~= tostring(optionName) then
                            -- The callback shape changed; do not claim success.
                        else
                            return true, "internal"
                        end
                    else
                        return true, "internal"
                    end
                end
            end
        end
    end

    return false, "callback-mismatch"
end

local function dialogueStageSignature()
    local gui = Player.PlayerGui:FindFirstChild("DialogueGui")
    if not gui then return nil end
    local options = gui:FindFirstChild("Options", true)
    if not options then return nil end

    local parts = {}
    for i = 1, 8 do
        local option = options:FindFirstChild("Option" .. i)
        if option and option.Visible then
            local label = option:FindFirstChildWhichIsA("TextLabel", true)
            local button = option:FindFirstChildWhichIsA("TextButton", true)
            local text = (button and button.Text) or (label and label.Text) or ""
            parts[#parts + 1] = "Option" .. i .. "=" .. tostring(text)
        end
    end
    return #parts > 0 and table.concat(parts, " | ") or nil
end

local function findQuestPrompt(questName)
    local cleanName = tostring(questName):gsub("%s*%[Lvl%.?%s*%d+%+%]%s*$", "")
    -- Build a packed list: ipairs stops at the first nil root in a sparse list.
    local roots = {}
    for _, root in ipairs({
        workspace, ReplicatedStorage
    }) do
        for _, name in ipairs(root == workspace and {"Dialogues"} or {"Dialogue", "NewDialogue"}) do
            local found = root:FindFirstChild(name)
            if found then roots[#roots + 1] = found end
        end
    end

    local best, bestScore = nil, -1
    for _, root in ipairs(roots) do
        if root then
            for _, obj in ipairs(root:GetDescendants()) do
                if obj:IsA("ProximityPrompt") then
                    local score = 0
                    local ancestry = obj:GetFullName():lower()
                    local q = questName:lower()
                    local c = cleanName:lower()
                    if ancestry:find(q, 1, true) then score = score + 100 end
                    if c ~= "" and ancestry:find(c, 1, true) then score = score + 60 end
                    local objectText = tostring(obj.ObjectText or ""):lower()
                    if objectText == q or objectText == c then score = score + 80 end
                    if c ~= "" and objectText:find(c, 1, true) then score = score + 40 end
                    if score > bestScore then
                        best, bestScore = obj, score
                    end
                end
            end
        end
    end
    return bestScore > 0 and best or nil
end

local function acceptQuest(questName, token)
    if questOnCooldown and tick() < cooldownUntil then
        local remaining = math.ceil(cooldownUntil - tick())
        moduleLog("INFO", "[CombatFarm] Quest on cooldown, waiting " .. remaining .. " seconds.")
        return false
    end
    questOnCooldown = false

    local beforeProgress, beforeMax = readQuestState()
    local activeIncomplete = (beforeMax or 0) > 0 and (beforeProgress or 0) < (beforeMax or 0)
    local previousCompleted = (beforeMax or 0) > 0 and (beforeProgress or 0) >= (beforeMax or 0)

    local isQuestSwitch = sessionQuestName ~= questName
    if activeIncomplete and not isQuestSwitch then
        questCompleted = false
        return true
    end
    if isQuestSwitch then
        moduleLog("INFO", ("[CombatFarm][QuestSwitch] Requesting %s with previous global progress=%s/%s. Existing quests will not be completed or abandoned.")
            :format(tostring(questName), tostring(beforeProgress), tostring(beforeMax)))
    end

    local prompt = findQuestPrompt(questName)
    if not prompt then
        moduleLog("WARN", "[CombatFarm] New quest ProximityPrompt not found: " .. questName)
        return false
    end

    -- A completed quest must be turned in first. The Dio/Jotaro logs proved that
    -- the ClickContinue page does not spawn automatically after the kill: it is
    -- created only when Dio's prompt is fired again. Do the turn-in explicitly,
    -- invisibly, using the same line-2088 connection:Fire path proven by Analyzer.
    if previousCompleted and not isQuestSwitch then
        moduleLog("INFO", ("[CombatFarm] Previous quest finished (%s/%s). Instant turn-in: %s...")
            :format(tostring(beforeProgress), tostring(beforeMax), tostring(questName)))

        goToSafeSpot("Turning in completed quest")
        local hold = nil
        pcall(function() hold = _movement:Freeze() end)

        local okTurn, turnInfo = runPromptDialogueFast(prompt, token, nil, 4.00, "Quest turn-in")

        if hold then
            pcall(function() _movement:Unfreeze(hold) end)
        end

        if not okTurn then
            moduleLog("WARN", "[CombatFarm][FastDialogue] Quest turn-in was not confirmed: " .. tostring(turnInfo or "unknown"))
            return false
        end

        -- Give PlayerStats a tiny settle window. If the same interaction already
        -- activated the repeat quest, avoid firing the prompt a second time.
        local settleUntil = tick() + 0.25
        repeat
            local p, m = readQuestState()
            if (m or 0) > 0 and (p or 0) < (m or 0) then
                questCompleted = false
                sessionQuestName = questName
                moduleLog("INFO", ("[CombatFarm][FastDialogue] Quest reactivated during turn-in: %s | %s/%s")
                    :format(tostring(questName), tostring(p), tostring(m)))
                return true
            end
            task.wait(0.005)
        until tick() >= settleUntil or not isTokenActive(token, "Quest")

        beforeProgress, beforeMax = readQuestState()
        previousCompleted = (beforeMax or 0) > 0 and (beforeProgress or 0) >= (beforeMax or 0)
    end

    moduleLog("INFO", "[CombatFarm] Opening updated quest dialogue: " .. questName)

    -- Use the already-proven existing-dialogue engine AFTER firing the prompt.
    -- Unlike the older quest fast path this handles both Option1 pages (2063)
    -- and option-less ClickContinue pages (2088), which fixes Officer Sam and
    -- other NPCs whose first page is text-only.
    if type(runPromptDialogueFast) == "function" then
        -- A global progress counter may already be 0/1 for a DIFFERENT quest.
        -- For a switch, confirm dialogue completion rather than treating
        -- the old nonzero QuestMaxProgress as an immediate success.
        local completionCheck = nil
        if not isQuestSwitch then
            completionCheck = function()
                local p, m = readQuestState()
                return (m or 0) > 0 and (p or 0) < (m or 0)
            end
        end
        local okFast, fastInfo = runPromptDialogueFast(
            prompt, token, completionCheck, 4.00, "Quest accept")

        if okFast then
            local p, m = readQuestState()
            if (m or 0) > 0 and (p or 0) < (m or 0) then
                sessionQuestName = questName
                questCompleted = false
                moduleLog("INFO", ("[CombatFarm][QuestSwitch] Dialogue completed for %s | progress=%s/%s | %s. Kill credit will be verified independently.")
                    :format(tostring(questName), tostring(p), tostring(m), tostring(fastInfo or "fast")))
                return true
            end
            moduleLog("WARN", ("[CombatFarm][QuestSwitch] Dialogue finished for %s but quest progress is not active (%s/%s).")
                :format(tostring(questName), tostring(p), tostring(m)))
        end

        moduleLog("INFO", "[CombatFarm][FastDialogue] Automatic quest route not confirmed; using compatibility route. " .. tostring(fastInfo or ""))
    end

    -- Compatibility route retained for executors where connection/upvalue APIs
    -- are incomplete. This route may be visible/slower but keeps the farm usable.
    -- Do not fire a second prompt on top of an already-open dialogue.
    local existingDialogue = Player.PlayerGui:FindFirstChild("DialogueGui")
    local opened = existingDialogue ~= nil or pcall(function() fireproximityprompt(prompt) end)
    if not opened then
        moduleLog("WARN", "[CombatFarm] Could not trigger quest prompt: " .. questName)
        return false
    end

    local deadline = tick() + 8
    local lastStageSignature = nil
    local lastAdvanceAt = 0
    local internalStages = 0
    local fallbackClicks = 0

    while tick() < deadline and isTokenActive(token, "Quest") do
        local progress, maxProgress = readQuestState()
        local nowActive = (maxProgress or 0) > 0 and (progress or 0) < (maxProgress or 0)
        if nowActive and (not isQuestSwitch or internalStages > 0 or fallbackClicks > 0) then
            sessionQuestName = questName
            questCompleted = false
            moduleLog("INFO", ("[CombatFarm] Quest dialogue advanced: %s | progress=%s/%s internalStages=%d fallbackClicks=%d; kill credit pending")
                :format(questName, tostring(progress), tostring(maxProgress), internalStages, fallbackClicks))
            return true
        end

        local btn = findDialogueOption("Option1")
        local signature = dialogueStageSignature()
        if btn and btn.Visible and signature then
            local isNewStage = signature ~= lastStageSignature
            local retryExpired = (tick() - lastAdvanceAt) >= 0.45
            if isNewStage or retryExpired then
                local okInject = injectDialogueOption("Option1")
                if okInject then
                    internalStages = internalStages + 1
                    lastStageSignature = signature
                    lastAdvanceAt = tick()
                    task.wait(0.04)
                else
                    if clickDialogueButton(btn) then
                        fallbackClicks = fallbackClicks + 1
                        lastStageSignature = signature
                        lastAdvanceAt = tick()
                    end
                    task.wait(0.08)
                end
            else
                task.wait(0.03)
            end
        else
            -- Some quest pages have no options: advance the actual ClickContinue.
            local dlg = Player.PlayerGui:FindFirstChild("DialogueGui")
            local cont = dlg and dlg:FindFirstChild("ClickContinue", true)
            if cont and cont:IsA("GuiButton") then
                clickDialogueButton(cont)
            end
            task.wait(0.04)
        end
    end

    local progress, maxProgress = readQuestState()
    if (maxProgress or 0) > 0 and (progress or 0) < (maxProgress or 0)
        and (not isQuestSwitch or internalStages > 0 or fallbackClicks > 0) then
        sessionQuestName = questName
        questCompleted = false
        moduleLog("INFO", "[CombatFarm] Quest dialogue accepted after settle: " .. questName)
        return true
    end

    local data = questInfo[questName]
    local mappedCooldown = data and tonumber(data.cooldownSeconds) or 0
    if mappedCooldown and mappedCooldown > 0 then
        questOnCooldown = true
        cooldownUntil = tick() + mappedCooldown
        moduleLog("INFO", ("[CombatFarm] Quest appears unavailable; mapped cooldown %ss: %s")
            :format(tostring(mappedCooldown), tostring(questName)))
    else
        questOnCooldown = false
        moduleLog("WARN", "[CombatFarm] Quest acceptance failed; no cooldown is mapped for this normal quest, so it will retry.")
    end
    return false
end

local function collectItem(itemName, requiredAmount, token)
    local inventory = _inventory
    local movement  = _movement
    local startTime = tick()
    while isTokenActive(token, "Quest") and inventory:Count(itemName) < requiredAmount and (tick() - startTime) < 120 do
        local itemModel = nil
        local itemsFolder = workspace.Item_Spawns and workspace.Item_Spawns.Items
        if itemsFolder then
            for _, model in pairs(itemsFolder:GetChildren()) do
                if model:IsA("Model") then
                    local prompt = model:FindFirstChildWhichIsA("ProximityPrompt")
                    if prompt and prompt.ObjectText == itemName and prompt.MaxActivationDistance == 8 then
                        itemModel = model
                        break
                    end
                end
            end
        end
        if itemModel and itemModel.PrimaryPart then
            local hrp = movement:GetCharacter("HumanoidRootPart")
            if hrp then
                local oldCF = hrp.CFrame
                local bv = movement:Freeze()
                movement:SetNoclip(true)
                movement:Teleport(itemModel.PrimaryPart.CFrame - Vector3.new(0, 10, 0))
                task.wait(0.3)
                local prompt = itemModel:FindFirstChildWhichIsA("ProximityPrompt")
                if prompt then fireproximityprompt(prompt) end
                task.wait(0.6)
                movement:Unfreeze(bv)
                movement:Teleport(oldCF)
                movement:SetNoclip(false)
            end
        end
        task.wait(1)
    end
    return inventory:Count(itemName) >= requiredAmount
end

-- Some normal leveling quests open an automatic final DialogueGui after the
-- objective is complete. DialogueAnalyzer mapped Dio/Jotaro's final page as
-- Option1 = "Very well." using the same ClientFunctions:2063 callback used by
-- Merchant and quest acceptance. Hide and clear it before re-taking the quest.
runPromptDialogueFast = function(prompt, token, isComplete, waitTimeout, label)
    if not prompt then return false, "missing ProximityPrompt" end

    waitTimeout = math.max(0.75, tonumber(waitTimeout) or 3.50)
    label = tostring(label or "Quest dialogue")
    local dialogueStartedAt = tick()

    local playerGui = Player:FindFirstChild("PlayerGui")
    if not playerGui then return false, "PlayerGui missing" end

    -- IMPORTANT: this fast quest driver is fully local to CombatFarm.
    -- It does NOT call Inventory dialogue helpers, so Merchant/Auto Sell remains isolated.
    local hiddenGuis = {}
    local function hideDialogue(gui)
        if gui and gui.Parent and gui:IsA("ScreenGui") then
            if hiddenGuis[gui] == nil then
                hiddenGuis[gui] = gui.Enabled
            end
            pcall(function() gui.Enabled = false end)
        end
    end

    -- Never leave a stuck invisible DialogueGui behind after a failed quest.
    -- Restoring the UI is especially important before a future Merchant sale.
    local function finishDialogue(ok, reason)
        for gui, originallyEnabled in pairs(hiddenGuis) do
            if gui and gui.Parent then
                pcall(function() gui.Enabled = originallyEnabled end)
            end
        end
        moduleLog("INFO", ("[CombatFarm][DialogueTiming] %s elapsed=%.3fs; confirmed=%s; %s")
            :format(label, tick() - dialogueStartedAt, tostring(ok), tostring(reason or "")))
        return ok, reason
    end

    local function dialogueGone(originalGui)
        local current = playerGui:FindFirstChild("DialogueGui")
        return current == nil or current ~= originalGui
    end

    local function fireContinueButton(gui)
        if not gui or not gui.Parent then return false, "no-gui" end
        local continueButton = gui:FindFirstChild("ClickContinue", true)
        if not continueButton or not continueButton:IsA("GuiButton") then
            return false, "continue-not-ready"
        end

        local signal = nil
        pcall(function() signal = continueButton.MouseButton1Click end)
        if not signal then
            pcall(function() signal = continueButton.Activated end)
        end
        if not signal then
            return false, "continue-signal-missing"
        end

        -- Same proven order as DialogueAnalyzer TEST ALL, but scoped only to Quest Farm.
        if type(getconnections) == "function" then
            local okConnections, connections = pcall(getconnections, signal)
            if okConnections and type(connections) == "table" then
                for _, connection in ipairs(connections) do
                    local fired = false
                    if connection then
                        if type(connection.Fire) == "function" then
                            fired = pcall(function() connection:Fire() end)
                        end
                        if not fired then
                            local fn = nil
                            pcall(function() fn = connection.Function end)
                            if type(fn) == "function" then
                                fired = pcall(fn)
                            end
                        end
                    end
                    if fired then
                        return true, "connection"
                    end
                end
            end
        end

        if type(firesignal) == "function" then
            local ok = pcall(function() firesignal(signal) end)
            if ok then
                return true, "firesignal"
            end
        end

        return false, "continue-fire-failed"
    end

    local function processExistingDialogue(gui, timeout)
        if not gui or not gui.Parent then return true, "already-closed" end
        hideDialogue(gui)

        local originalGui = gui
        local deadline = tick() + math.max(0.35, timeout or 1.50)
        local lastOptionAdvanceAt = 0
        local lastOptionSignature = nil
        local stuckSince = 0
        local lastContinueAt = 0
        local optionAdvances = 0
        local continueAdvances = 0

        while tick() < deadline and isTokenActive(token, "Quest") do
            if type(isComplete) == "function" then
                local okDone, done = pcall(isComplete)
                if okDone and done == true then
                    return true, ("complete option=%d continue=%d"):format(optionAdvances, continueAdvances)
                end
            elseif dialogueGone(originalGui) then
                return true, ("closed option=%d continue=%d"):format(optionAdvances, continueAdvances)
            end

            local current = playerGui:FindFirstChild("DialogueGui")
            if current ~= originalGui then
                if type(isComplete) ~= "function" then
                    return true, ("closed option=%d continue=%d"):format(optionAdvances, continueAdvances)
                end
                originalGui = current
                if not originalGui then
                    task.wait(0.01)
                    continue
                end
            end

            if originalGui then
                hideDialogue(originalGui)

                local option = findDialogueOption("Option1")
                if option and option.Visible then
                    local stage = dialogueStageSignature()
                    -- A genuinely new option page need not wait for the old
                    -- page's retry cooldown. Unchanged pages remain throttled.
                    local pageChanged = stage ~= lastOptionSignature
                    if stage ~= lastOptionSignature then
                        lastOptionSignature = stage
                        stuckSince = tick()
                    end

                    if pageChanged or tick() - lastOptionAdvanceAt >= 0.10 then
                        local advanced = false
                        if tick() - stuckSince < 0.30 then
                            local okInject = injectDialogueOption("Option1")
                            advanced = okInject == true
                        end
                        -- If the same page is still present after injection, TEST ALL
                        -- showed connection:Fire can advance it when upvalues cannot.
                        if not advanced then
                            advanced = clickDialogueButton(option)
                            stuckSince = tick()
                        end

                        if advanced then
                            optionAdvances = optionAdvances + 1
                            lastOptionAdvanceAt = tick()
                            task.wait(0.025)
                        else
                            task.wait(0.01)
                        end
                    else
                        task.wait(0.01)
                    end
                else
                    if tick() - lastContinueAt >= 0.03 then
                        local okContinue = fireContinueButton(originalGui)
                        if okContinue then
                            continueAdvances = continueAdvances + 1
                            lastContinueAt = tick()
                            task.wait(0.01)
                        else
                            task.wait(0.01)
                        end
                    else
                        task.wait(0.005)
                    end
                end
            else
                task.wait(0.01)
            end
        end

        if type(isComplete) == "function" then
            local okDone, done = pcall(isComplete)
            if okDone and done == true then
                return true, ("complete option=%d continue=%d"):format(optionAdvances, continueAdvances)
            end
        elseif dialogueGone(originalGui) then
            return true, ("closed option=%d continue=%d"):format(optionAdvances, continueAdvances)
        end

        return false, ("timeout option=%d continue=%d"):format(optionAdvances, continueAdvances)
    end

    -- Clear only a stale QUEST dialogue. No Inventory/merchant code is touched.
    local stale = playerGui:FindFirstChild("DialogueGui")
    if stale then
        hideDialogue(stale)
        local staleOk = select(1, processExistingDialogue(stale, 1.25))
        if not staleOk and stale.Parent then
            return finishDialogue(false, "stale quest DialogueGui could not be cleared")
        end
        task.wait(0.01)
    end

    local gui = nil
    local childConnection = nil
    childConnection = playerGui.ChildAdded:Connect(function(child)
        if child.Name == "DialogueGui" then
            gui = child
            hideDialogue(child)
        end
    end)

    local fired, fireErr = pcall(function()
        fireproximityprompt(prompt)
    end)
    if not fired then
        if childConnection then pcall(function() childConnection:Disconnect() end) end
        return finishDialogue(false, "prompt failed: " .. tostring(fireErr))
    end

    local appearDeadline = tick() + math.min(waitTimeout, 3.50)
    while not gui and tick() < appearDeadline and isTokenActive(token, "Quest") do
        if type(isComplete) == "function" then
            local okDone, done = pcall(isComplete)
            if okDone and done == true then
                if childConnection then
                    pcall(function() childConnection:Disconnect() end)
                end
                return finishDialogue(true, "quest state changed before DialogueGui")
            end
        end
        local existing = playerGui:FindFirstChild("DialogueGui")
        if existing then
            gui = existing
            hideDialogue(existing)
            break
        end
        task.wait(0.002)
    end

    if childConnection then
        pcall(function() childConnection:Disconnect() end)
    end

    if not gui then
        -- Some quests can update PlayerStats without ever rendering a dialogue.
        if type(isComplete) == "function" then
            local okDone, done = pcall(isComplete)
            if okDone and done == true then
                return finishDialogue(true, "state changed without DialogueGui")
            end
        end
        return finishDialogue(false, label .. " DialogueGui did not appear")
    end

    local okFast, info = processExistingDialogue(gui, waitTimeout)
    if okFast then
        moduleLog("INFO", ("[CombatFarm][LocalDialogue] %s cleared: %s"):format(label, tostring(info or "fast")))
        return finishDialogue(true, info)
    end

    return finishDialogue(false, tostring(info or (label .. " local route failed")))
end

local function runQuestFarm(token)
    local autoChoose = _config:Get("AutoChooseQuest")
    if autoChoose then
        currentQuest = getBestQuest()
    else
        currentQuest = _config:Get("SelectedQuest")
    end

    if not currentQuest or currentQuest == "" then
        moduleLog("INFO", "[CombatFarm] No quest selected or found.")
        return false
    end

    local data = questInfo[currentQuest]
    if not data then
        moduleLog("WARN", "[CombatFarm] Quest was detected by the UI but its objective is not mapped yet: " .. tostring(currentQuest))
        return false
    end
    if data.special then
        moduleLog("WARN", "[CombatFarm] Special quest is visible but not automated yet: " .. tostring(currentQuest) .. " (" .. tostring(data.special) .. ").")
        return false
    end

    local beforeProgress, beforeMax = readQuestState()
    moduleLog("INFO", ("[CombatFarm][QuestState] Starting %s quest=%s target=%s previous=%s/%s")
        :format(autoChoose and "AutoChoose" or "Manual", tostring(currentQuest),
            tostring(data.enemy or data.item or "unknown"), tostring(beforeProgress), tostring(beforeMax)))

    if not acceptQuest(currentQuest, token) then
        return false
    end
    -- PlayerStats can replicate one or two ticks after DialogueGui closes.
    -- Confirm an active quest before targeting any NPC.
    local progress, maxProgress = readQuestState()
    local syncDeadline = tick() + 1.25
    while (maxProgress or 0) <= 0 and tick() < syncDeadline do
        if not waitToken(0.05, token, "Quest") then return false end
        progress, maxProgress = readQuestState()
    end
    if (maxProgress or 0) <= 0 then
        moduleLog("WARN", "[CombatFarm] Quest dialogue ended but no active QuestMaxProgress replicated.")
        return false
    end

    if data.enemy then
        local consecutiveUncreditedKills = 0
        while isTokenActive(token, "Quest") do
            progress, maxProgress = readQuestState()
            if (maxProgress or 0) > 0 and (progress or 0) >= (maxProgress or 0) then
                questCompleted = true
                moduleLog("INFO", ("[CombatFarm] Quest objective complete: %s | %s/%s")
                    :format(tostring(currentQuest), tostring(progress), tostring(maxProgress)))
                goToSafeSpot("Quest objective complete; ready to turn in")
                return true
            end

            local progressBeforeKill, maxBeforeKill = progress, maxProgress
            local ok = killTarget(data.enemy, token)
            if not isTokenActive(token, "Quest") then return false end
            if ok then
                local afterProgress, afterMax = readQuestState()
                if afterProgress ~= progressBeforeKill or afterMax ~= maxBeforeKill then
                    consecutiveUncreditedKills = 0
                else
                    consecutiveUncreditedKills = consecutiveUncreditedKills + 1
                    moduleLog("WARN", ("[CombatFarm][QuestSwitch] %s kill not credited to %s (%d/2); checking dialogue again if repeated.")
                        :format(tostring(data.enemy), tostring(currentQuest), consecutiveUncreditedKills))
                    if consecutiveUncreditedKills >= 2 then
                        sessionQuestName = nil
                        moduleLog("WARN", "[CombatFarm][QuestSwitch] Quest objective did not credit two confirmed kills. Reopening selected quest instead of endlessly attacking.")
                        return false
                    end
                end
                if not waitToken(0.02, token, "Quest") then return false end
            else
                if not waitToken(0.50, token, "Quest") then return false end
            end
        end
        return false
    elseif data.item then
        local ok = collectItem(data.item, data.amount, token)
        if ok then
            local p, m = readQuestState()
            if (m or 0) > 0 and (p or 0) >= (m or 0) then
                questCompleted = true
            end
        end
        return ok
    end
    return false
end

-- =============================================
-- MAIN LOOP
-- =============================================
local function waitCancelable(seconds, token)
    local deadline = tick() + seconds
    while tick() < deadline do
        if not isTokenActive(token) then return false end
        task.wait(math.min(0.10, math.max(0, deadline - tick())))
    end
    return true
end

local function farmLoop(token)
    while isTokenActive(token) do
        if activeMode == "NPC" then
            local ok = runNPCFarm(token)
            if token ~= runId or stopRequested then break end
            if ok then
                moduleLog("INFO", "[CombatFarm] NPC killed. Looking for another alive spawn...")
                local selectedNPC = _config:Get("SelectedNPC")
                if not selectedNPC or selectedNPC == "" or not getClosestNPC(selectedNPC) then
                    goToSafeSpot("All selected NPC spawns are currently dead")
                end
                if not waitCancelable(0.02, token) then break end
            else
                goToSafeSpot("Waiting for selected NPC to respawn")
                moduleLog("INFO", "[CombatFarm] No alive NPC found. Retrying shortly...")
                if not waitCancelable(0.75, token) then break end
            end

        elseif activeMode == "Quest" then
            local ok = runQuestFarm(token)
            if token ~= runId or stopRequested then break end

            if ok then
                moduleLog("INFO", "[CombatFarm] Quest completed. Re-taking highest/selected quest...")
                questCompleted = false
                questOnCooldown = false
                if not waitCancelable(0.05, token) then break end
            else
                if questOnCooldown then
                    local remaining = math.max(1, math.ceil(cooldownUntil - tick()))
                    moduleLog("INFO", "[CombatFarm] Quest on cooldown, waiting " .. remaining .. " seconds...")
                    if not waitCancelable(remaining, token) then break end
                else
                    moduleLog("INFO", "[CombatFarm] Quest failed. Retrying in 5 seconds...")
                    if not waitCancelable(5, token) then break end
                end
            end
        else
            break
        end

        if not waitCancelable(0.25, token) then break end
    end

    if token == runId then
        isRunning = false
        activeMode = nil
    end
end

-- =============================================
-- PUBLIC API
-- =============================================
local function startMode(mode)
    local m=_G.WhiteHubModules
    if m and m.AutoPrestigeRuntime and m.AutoPrestigeRuntime:IsBusy() then return false,"Auto Prestige pending" end
    if isRunning and activeMode == mode then return end

    -- Invalidate any previous worker before starting a new one.
    runId = runId + 1
    stopRequested = false
    activeMode = mode
    isRunning = true

    local token = runId
    if mode == "Quest" then
        sessionQuestName = nil
        questCompleted = false
        questOnCooldown = false
    end

    pauseItemFarmForCombat()
    moduleLog("INFO", "[CombatFarm] Starting " .. mode .. " farming (single-worker mode).")
    task.spawn(function()
        -- Let an in-flight item pickup finish before owning HRP movement.
        if not waitToken(0.85, token, mode) then return end
        local ok, err = pcall(farmLoop, token)
        if not ok then
            moduleLog("ERROR", "[CombatFarm][Worker] " .. tostring(err))
        end
        if token == runId then
            isRunning = false
            activeMode = nil
            _movement:SetNoclip(false)
            _movement:ClearFocus()
            _movement:FixCamera()
            goToSafeSpot("Combat worker ended")
            resumeItemFarmAfterCombat()
        end
    end)
end


function CombatFarm:GetSkillCatalog()
    local standName, _, preset = getStandPreset()
    local source = "generic"
    local sourceSkills = preset

    if preset then
        source = "stand-preset"
    else
        local guiDetected = scanGuiSkillCatalog()
        if #guiDetected > 0 then
            source = "gui-detected"
            sourceSkills = guiDetected
        else
            sourceSkills = GENERIC_MOBILE_SKILLS
        end
    end

    local skills = {}
    for _, entry in ipairs(sourceSkills) do
        local profile = getSkillProfile(entry.key)
        skills[#skills + 1] = {
            key = entry.key,
            name = entry.name,
            closeCast = (entry.closeCast == true) or (profile and profile.closeCast == true) or false,
        }
    end
    return {
        stand = standName,
        source = source,
        skills = skills,
    }
end

function CombatFarm:StartNPC()
    startMode("NPC")
end

function CombatFarm:StartQuest()
    startMode("Quest")
end

function CombatFarm:Stop()
    local previousMode = activeMode
    runId = runId + 1
    stopRequested = true
    isRunning = false
    activeMode = nil
    sessionQuestName = nil
    questCompleted = false
    _movement:SetNoclip(false)
    _movement:ClearFocus()
    _movement:FixCamera()
    if previousMode == "NPC" or previousMode == "Quest" then
        goToSafeSpot(tostring(previousMode) .. " Farm disabled")
    end
    resumeItemFarmAfterCombat()
    moduleLog("INFO", "[CombatFarm] Stopped immediately and cleaned combat state.")
end

function CombatFarm:IsBusy() return isRunning or outstandingTasks > 0 end

function CombatFarm:IsRunning()
    return isRunning, activeMode
end

function CombatFarm:Destroy()
    self:Stop()
    resumeItemFarmAfterCombat()
    if questWatcherConnection then
        pcall(function() questWatcherConnection:Disconnect() end)
        questWatcherConnection = nil
    end
end

-- Export contract guard: fail during module load instead of later inside UI.Create.
assert(type(CombatFarm.Init) == "function", "CombatFarm export missing Init")
assert(type(CombatFarm.StartNPC) == "function", "CombatFarm export missing StartNPC")
assert(type(CombatFarm.StartQuest) == "function", "CombatFarm export missing StartQuest")
assert(type(CombatFarm.Stop) == "function", "CombatFarm export missing Stop")
assert(type(CombatFarm.IsRunning) == "function", "CombatFarm export missing IsRunning")

return CombatFarm