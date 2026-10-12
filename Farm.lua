-- =====================
-- Farm.lua
-- Main farm controller.
-- =====================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local Player = Players.LocalPlayer
local Farm   = {}

local _config    = nil
local _inventory = nil
local _movement  = nil
local _serverHop = nil
local _webhook   = nil

local SpawnedItems    = {}
local ItemSpawnFolder = nil
local NO_ITEM_TIMEOUT = 20   -- wait longer before treating the server as having no spawned items
local lastItemTime    = tick()

local lastSellItemsSnapshot = nil
local isRunning = false
local stopRequested = false
local runtimeSetup = false
local runtimeConnections = {}
local restockBusy, cycleBusy, startupBusy = false, false, false
local restockFreeze, restockEpoch = nil, 0

local _runtimeLog = nil
local _rawPrint, _rawWarn = print, warn
local function moduleLog(level, ...)
    if _runtimeLog and type(_runtimeLog.Write) == "function" then
        pcall(_runtimeLog.Write, _runtimeLog, level, "Farm", ...)
    end
    if level == "WARN" or level == "ERROR" then
        _rawWarn(...)
    else
        _rawPrint(...)
    end
end

function Farm:Init(Modules)
    _runtimeLog = Modules.RuntimeLog
    _config    = Modules.Config
    _inventory = Modules.Inventory
    _movement  = Modules.Movement
    _serverHop = Modules.ServerHop
    _webhook   = Modules.Webhook
end

-- Config change detection
local function updateConfigSnapshot()
    lastSellItemsSnapshot = {}
    local sellItems = _config:GetSellItems()
    for k, v in pairs(sellItems) do
        lastSellItemsSnapshot[k] = v
    end
end

local function hasConfigChanged()
    if lastSellItemsSnapshot == nil then
        updateConfigSnapshot()
        return false
    end
    local current = _config:GetSellItems()
    for k, v in pairs(current) do
        if lastSellItemsSnapshot[k] ~= v then
            return true
        end
    end
    return false
end

-- Hooks & bypasses
local function ApplyHooks()
    local env = getgenv and getgenv() or _G
    if env.__WhiteHubFarmHooksApplied then return end
    env.__WhiteHubFarmHooksApplied = true

    pcall(function()
        local oldMag
        oldMag = hookmetamethod(Vector3.new(), "__index", newcclosure(function(self, index)
            local src = tostring(getcallingscript())
            if not checkcaller() and index == "magnitude" and src == "ItemSpawn" then return 0 end
            return oldMag(self, index)
        end))
    end)
    pcall(function()
        local oldNc
        oldNc = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
            local args = {...}
            if not checkcaller() and rawequal(self.Name, "Returner") and rawequal(args[1], "idklolbrah2de") then
                return "  ___XP DE KEY"
            end
            return oldNc(self, ...)
        end))
    end)
end

local function ApplyCrashBypass()
    task.delay(3, function()
        pcall(function()
            local Modules = ReplicatedStorage:WaitForChild("Modules", 10)
            if not Modules then return end
            local FuncLib = require(Modules:WaitForChild("FunctionLibrary", 10))
            if not FuncLib or type(FuncLib) ~= "table" then return end
            local OldPcall = FuncLib.pcall
            if type(OldPcall) ~= "function" then return end
            FuncLib.pcall = function(...)
                local f = ...
                if type(f) == "function" and #getupvalues(f) == 11 then return end
                return OldPcall(...)
            end
        end)
    end)
end

local function ApplyAntiAfk()
    pcall(function()
        local connection = Player.Idled:Connect(function()
            game:GetService("VirtualUser"):ClickButton2(Vector2.new())
        end)
        table.insert(runtimeConnections, connection)
    end)
end

local function SkipLoadingScreen()
    task.wait(1)
    pcall(function()
        if not Player.PlayerGui:FindFirstChild("HUD") then
            local HUD = ReplicatedStorage.Objects.HUD:Clone()
            HUD.Parent = Player.PlayerGui
        end
    end)
    task.spawn(function()
        pcall(function() Player.PlayerGui:WaitForChild("LoadingScreen1", 5):Destroy() end)
        task.wait(.5)
        pcall(function() Player.PlayerGui:WaitForChild("LoadingScreen", 5):Destroy() end)
        pcall(function() Workspace.LoadingScreen.Song:Destroy() end)
    end)
end

-- Item detection
local function GetItemInfo(model)
    if not (model and model:IsA("Model") and model.Parent and model.Parent.Name == "Items") then return nil end
    local pp = model.PrimaryPart
    if not pp then return nil end
    local prompt
    for _, v in pairs(model:GetChildren()) do
        if v:IsA("ProximityPrompt") and v.MaxActivationDistance ~= 0 then prompt = v break end
    end
    if not prompt then return nil end
    return { Name = prompt.ObjectText, ProximityPrompt = prompt, Position = pp.Position, Model = model }
end

local function InitItemDetection()
    pcall(function()
        local spawns = Workspace:WaitForChild("Item_Spawns", 15)
        if spawns then ItemSpawnFolder = spawns:WaitForChild("Items", 15) end
    end)
    if not ItemSpawnFolder then
        pcall(function()
            local spawns = Workspace:FindFirstChild("Item_Spawns")
            if spawns then ItemSpawnFolder = spawns:FindFirstChild("Items") end
        end)
    end
    if not ItemSpawnFolder then
        moduleLog("WARN", "[Farm] ERROR: Item_Spawns/Items folder not found.")
        return
    end
    moduleLog("INFO", "[Farm] Item_Spawns/Items folder found.")
    for _, model in pairs(ItemSpawnFolder:GetChildren()) do
        pcall(function()
            if model:IsA("Model") then
                local info = GetItemInfo(model)
                if info then SpawnedItems[model] = info end
            end
        end)
    end
    local connection = ItemSpawnFolder.ChildAdded:Connect(function(model)
        task.wait(1)
        pcall(function()
            if model:IsA("Model") then
                local info = GetItemInfo(model)
                if info then
                    SpawnedItems[model] = info
                    moduleLog("INFO", "[Farm] Item detected: " .. info.Name)
                end
            end
        end)
    end)
    table.insert(runtimeConnections, connection)
end

local SAFE_SPOT = CFrame.new(978, -42, -49)

local function CollectItem(itemInfo, index, restockGuard)
    local function allowed()
        if restockGuard then return restockGuard() end
        return _config:Get("FarmEnabled") and not stopRequested
    end
    if not allowed() then return false end

    local hrp = _movement:GetCharacter("HumanoidRootPart")
    if not hrp or not itemInfo then return false end
    if _inventory:HasMax(itemInfo.Name) then
        SpawnedItems[index] = nil
        return false
    end

    local beforeCount = _inventory:Count(itemInfo.Name)
    local model = itemInfo.Model or index
    local oldCF = hrp.CFrame
    local bv = _movement:Freeze()
    if restockGuard then restockFreeze = bv end
    _movement:SetNoclip(true)
    _movement:Teleport(CFrame.new(itemInfo.Position.X, itemInfo.Position.Y - 25, itemInfo.Position.Z))
    task.wait(.35)

    local fired = pcall(function()
        if allowed() and itemInfo.ProximityPrompt and itemInfo.ProximityPrompt.Parent then
            fireproximityprompt(itemInfo.ProximityPrompt)
        end
    end)

    local deadline = tick() + 1.5
    local collected = false
    while tick() < deadline and allowed() do
        if _inventory:Count(itemInfo.Name) > beforeCount then
            collected = true
            break
        end
        if model and not model.Parent then
            collected = true
            break
        end
        task.wait(0.1)
    end

    _movement:Unfreeze(bv)
    if oldCF and hrp.Parent and (not restockGuard or allowed()) then
        _movement:Teleport(SAFE_SPOT)
    end
    task.wait(.15)
    _movement:SetNoclip(false)

    if restockGuard and not allowed() then return false end

    if collected and fired then
        SpawnedItems[index] = nil
        lastItemTime = tick()
        moduleLog("INFO", "[Farm] Collected: " .. itemInfo.Name)
        return true
    end

    -- Keep a live item in the queue so a transient prompt failure can retry.
    if model and model.Parent then
        local refreshed = GetItemInfo(model)
        if refreshed then SpawnedItems[index] = refreshed end
    else
        SpawnedItems[index] = nil
    end
    moduleLog("WARN", "[Farm] Collection was not confirmed: " .. tostring(itemInfo.Name))
    return false
end

-- Helper to check if we should skip hopping (based solely on UI toggle)
local function shouldSkipHop()
    local stay = _config:Get("StayInPrivateServer")
    if stay then
        moduleLog("INFO", "[Farm] StayInPrivateServer is ON – skipping all hops.")
        return true
    end
    return false
end

local function DoHop()
    if not _config:Get("FarmEnabled") then return end

    if shouldSkipHop() then
        moduleLog("INFO", "[Farm] DoHop aborted – skipping hop.")
        return
    end

    moduleLog("INFO", "[Farm] Server dry — selling, buying, then hopping...")
    _inventory:SellAll()
    _inventory:BuyLucky()
    _serverHop:Hop()
    lastItemTime = tick()
end

local function SetupWebhookListener()
    local connection = Player.Backpack.ChildAdded:Connect(function(tool)
        if tool.Name == "Lucky Arrow" and _inventory:ShouldStopPhase1() then
            _webhook:SendLuckyFound(
                _inventory:Count("Lucky Arrow"),
                _inventory:GetLuckyStop(),
                _inventory:GetMoney()
            )
        end
    end)
    table.insert(runtimeConnections, connection)
end

local function Startup()
    SkipLoadingScreen()

    local waitTime = 0
    repeat
        task.wait(0.5)
        waitTime = waitTime + 0.5
        if waitTime > 30 then
            moduleLog("WARN", "[Farm] Timeout waiting for RemoteEvent — continuing anyway.")
            break
        end
    until _movement:GetCharacter("RemoteEvent")

    moduleLog("INFO", "[Farm] Character loaded.")
    pcall(function()
        _movement:GetCharacter("RemoteEvent"):FireServer("PressedPlay")
    end)

    moduleLog("INFO", "[Farm] Teleporting to safe spot...")
    _movement:Teleport(SAFE_SPOT)
    task.wait(1)
    _movement:FixCamera()

    local hrp = _movement:GetCharacter("HumanoidRootPart")
    if hrp then moduleLog("INFO", "[Farm] Position: " .. tostring(hrp.Position))
    else moduleLog("WARN", "[Farm] HumanoidRootPart not found.") end

    moduleLog("INFO", "[Farm] Waiting 5 seconds before starting farm loop...")
    task.wait(5)
end

local function shouldPauseCycle()
    return stopRequested or restockBusy or not _config:Get("FarmEnabled") or _config:Get("AutoPrestige")
end

-- Synchronous handoff from StandFarm. It never enables the normal phases,
-- sells/buys, changes persistent item filters, or hops with a result in flight.
function Farm:Restock(name, ownerActive)
    local allowedNames = { ["Rokakaka"]=true, ["Mysterious Arrow"]=true,
        ["Rib Cage of The Saint's Corpse"]=true }
    if not allowedNames[name] or type(ownerActive) ~= "function" then return false, "Invalid restock request" end
    if restockBusy or stopRequested then return false, "Item Farm unavailable/busy" end
    restockBusy = true
    local epoch, char, movementUsed = restockEpoch, Player.Character, false
    local function permitted()
        local humanoid = char and char:FindFirstChildWhichIsA("Humanoid")
        return epoch == restockEpoch and not stopRequested and ownerActive()
            and humanoid and humanoid.Health > 0
            and Player.Character == char and _config:Get("StandFarmEnabled") == true and not _config:Get("FarmEnabled")
            and not _config:Get("AutoSell") and not _config:Get("AutoPrestige")
            and not _config:Get("QuestFarmEnabled") and not _config:Get("NPCFarmEnabled")
    end
    local ok, success, reason = pcall(function()
        local deadline, attempts, nextScan = tick() + 90, 0, 0
        while permitted() and tick() < deadline and attempts < 8 do
            if _inventory:Count(name) >= 1 then return true, "Stock confirmed" end
            if not cycleBusy and not startupBusy then
                -- Refresh from the existing detection source: phase filters may
                -- have removed previously cached items which are still alive.
                if ItemSpawnFolder and tick() >= nextScan then
                    nextScan = tick() + 1
                    for _, model in ipairs(ItemSpawnFolder:GetChildren()) do
                        local info = GetItemInfo(model)
                        if info and info.Name == name then SpawnedItems[model] = info end
                    end
                end
                local candidate, index
                for key, info in pairs(SpawnedItems) do
                    if info.Name == name and info.Model and info.Model.Parent then
                        candidate, index = info, key; break
                    end
                end
                if candidate then
                    attempts = attempts + 1
                    movementUsed = true
                    CollectItem(candidate, index, permitted)
                    -- A despawn is not proof of inventory acquisition.
                    if permitted() and _inventory:Count(name) >= 1 then return true, "Stock confirmed" end
                end
            end
            task.wait(0.2)
        end
        if not permitted() then return false, "Restock cancelled/character changed" end
        return false, "Restock limit reached (90s/8 attempts); missing " .. name
    end)
    if restockFreeze then pcall(function() _movement:Unfreeze(restockFreeze) end) end
    if movementUsed then pcall(function() _movement:SetNoclip(false) end) end
    restockFreeze, restockBusy = nil, false
    if not ok then return false, "Restock collection failed; nothing consumed" end
    return success, reason
end

local function runCycle()
    lastItemTime = tick()
    _config:SetMany({ Phase1Notified = false, Phase3Notified = false })

    -- ===== PHASE 1 =====
    moduleLog("INFO", "[Farm] >>> Phase 1 started — farming normally.")
    while not stopRequested and _config:Get("FarmEnabled") and not _config:Get("AutoPrestige")
      and not _inventory:ShouldStopPhase1() do
        local snapshot = {}
        for idx, info in pairs(SpawnedItems) do
            table.insert(snapshot, {Index=idx, ItemInfo=info})
        end

        for _, entry in ipairs(snapshot) do
            if shouldPauseCycle() or _inventory:ShouldStopPhase1() then break end
            CollectItem(entry.ItemInfo, entry.Index)
        end

        if shouldPauseCycle() then return end

        local elapsed = tick() - lastItemTime
        if elapsed > NO_ITEM_TIMEOUT then
            if not _inventory:ShouldStopPhase1() then DoHop() end
        elseif #snapshot == 0 then
            moduleLog("INFO", "[Farm] Waiting for items... (" .. math.max(0, math.floor(NO_ITEM_TIMEOUT - elapsed)) .. "s until hop)")
        end
        task.wait(1)
    end

    -- A pause/prestige transition is not a completed phase.
    if shouldPauseCycle() then return end

    _inventory:SellAll()
    if shouldPauseCycle() then return end
    _inventory:BuyLucky()
    if shouldPauseCycle() then return end
    moduleLog("INFO", "[Farm] >>> Phase 1 complete.")

    -- ===== PHASE 2 =====
    local keepItems = _inventory:GetKeepItems()
    if #keepItems > 0 then
        if not _config:Get("Phase1Notified") then
            _webhook:SendPhase1Complete(_inventory:Count("Lucky Arrow"), _inventory:GetLuckyStop(), _inventory:GetMoney())
            _config:Set("Phase1Notified", true)
        end

        moduleLog("INFO", "[Farm] >>> Phase 2 started — farming keep-items: " .. table.concat(keepItems, ", "))
        while not stopRequested and _config:Get("FarmEnabled") and not _config:Get("AutoPrestige")
          and not _inventory:AllKeepItemsFull() do
            local snapshot = {}
            for idx, info in pairs(SpawnedItems) do
                local isKeep = _config:GetSellItem(info.Name) == false
                if isKeep and not _inventory:HasMax(info.Name) then
                    table.insert(snapshot, {Index=idx, ItemInfo=info})
                elseif not isKeep then
                    SpawnedItems[idx] = nil
                end
            end

            for _, entry in ipairs(snapshot) do
                if shouldPauseCycle() or _inventory:AllKeepItemsFull() then break end
                CollectItem(entry.ItemInfo, entry.Index)
            end

            if shouldPauseCycle() then return end

            local elapsed = tick() - lastItemTime
            if elapsed > NO_ITEM_TIMEOUT then
                if not _inventory:AllKeepItemsFull() then
                    moduleLog("INFO", "[Farm] Phase 2 — server dry, hopping...")
                    DoHop()
                end
            elseif #snapshot == 0 then
                moduleLog("INFO", "[Farm] Waiting for keep-items... (" .. math.max(0, math.floor(NO_ITEM_TIMEOUT - elapsed)) .. "s until hop)")
            end
            task.wait(1)
        end

        if shouldPauseCycle() then return end
        moduleLog("INFO", "[Farm] >>> Phase 2 complete — all keep-items maxed.")
    else
        moduleLog("INFO", "[Farm] >>> No keep-items configured — skipping Phase 2.")
    end

    if shouldPauseCycle() then return end

    -- ===== PHASE 3 =====
    if not _config:Get("Phase3Notified") then
        moduleLog("INFO", "[Farm] Sending 'All farming complete' webhook...")
        _webhook:SendAllComplete(_inventory:Count("Lucky Arrow"), _inventory:GetLuckyStop(), _inventory:GetMoney())
        _config:Set("Phase3Notified", true)
    end

    moduleLog("INFO", "[Farm] >>> Phase 3 — idle; collecting Lucky Arrow / Lucky Stone Mask only.")
    updateConfigSnapshot()

    while not stopRequested and _config:Get("FarmEnabled") and not _config:Get("AutoPrestige") do
        if not _inventory:ShouldStopPhase1() then
            moduleLog("INFO", "[Farm] >>> Lucky count or money dropped below minimum — returning to Phase 1.")
            _config:SetMany({ Phase1Notified = false, Phase3Notified = false })
            lastItemTime = tick()
            return
        end

        if hasConfigChanged() then
            moduleLog("INFO", "[Farm] >>> Item configuration changed — returning to Phase 1.")
            updateConfigSnapshot()
            _config:SetMany({ Phase1Notified = false, Phase3Notified = false })
            lastItemTime = tick()
            return
        end

        local snapshot = {}
        for idx, info in pairs(SpawnedItems) do
            if info.Name == "Lucky Arrow" or info.Name == "Lucky Stone Mask" then
                table.insert(snapshot, {Index=idx, ItemInfo=info})
            else
                SpawnedItems[idx] = nil
            end
        end
        for _, entry in ipairs(snapshot) do
            if shouldPauseCycle() then return end
            CollectItem(entry.ItemInfo, entry.Index)
        end
        task.wait(1)
    end
end

function Farm:Start()
    if isRunning then
        moduleLog("INFO", "[Farm] Start ignored — already running.")
        return
    end

    isRunning = true
    stopRequested = false

    if not runtimeSetup then
        runtimeSetup = true
        ApplyHooks()
        ApplyCrashBypass()
        ApplyAntiAfk()
        InitItemDetection()
        SetupWebhookListener()
        startupBusy = true
        local startupOk, startupError = pcall(Startup)
        startupBusy = false
        if not startupOk then isRunning = false; error(startupError) end
    end

    moduleLog("INFO", "[Farm] Farm loop started.")

    while not stopRequested do
        while not stopRequested and (restockBusy or not _config:Get("FarmEnabled")) do
            task.wait(0.5)
        end
        while not stopRequested and _config:Get("AutoPrestige") do
            task.wait(0.5)
        end
        if stopRequested then break end

        cycleBusy = true
        local ok, err = pcall(runCycle)
        cycleBusy = false
        if not ok then
            moduleLog("WARN", "[Farm] Cycle error: " .. tostring(err))
            task.wait(2)
        end
    end

    isRunning = false
    _movement:SetNoclip(false)
    moduleLog("INFO", "[Farm] Farm loop stopped.")
end

function Farm:Stop()
    restockEpoch = restockEpoch + 1
    stopRequested = true
    _movement:SetNoclip(false)
    moduleLog("INFO", "[Farm] Stop requested.")
end

function Farm:IsRunning()
    return isRunning
end

function Farm:Destroy()
    self:Stop()
    for _, connection in ipairs(runtimeConnections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(runtimeConnections)
    runtimeSetup = false
    table.clear(SpawnedItems)
end

return Farm
