-- =====================
-- Farm.lua
-- Main farm controller.
-- =====================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")

local Player = Players.LocalPlayer
local Farm   = {}

local _config    = nil
local _inventory = nil
local _movement  = nil
local _serverHop = nil
local _webhook   = nil

local SpawnedItems    = {}
local ItemSpawnFolder = nil
local NO_ITEM_TIMEOUT = 20 -- Historical normal cadence; restock keeps its separate 90s limit.
local detectionEpoch = 0
local lastItemTime    = tick()

local lastSellItemsSnapshot = nil
local isRunning = false
local stopRequested = false
local runtimeSetup = false
local runtimeConnections = {}
local restockBusy, cycleBusy, startupBusy = false, false, false
local prestigeSaleBusy=false
-- One manual sale at a time; park normal collection while a sale runs.
local manualSellBusy, sellBusy, collectBusy = false, false, false
local restockFreeze, restockEpoch = nil, 0

local function prestigePending()
    local m=_G.WhiteHubModules
    return m and m.AutoPrestigeRuntime and m.AutoPrestigeRuntime:IsBusy()
end
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

-- DEV-ONLY diagnostics: observe sale frame times without changing Inventory.lua.
-- This is intentionally read-only. One Heartbeat connection exists only during SellAll.
local sellPerfSerial = 0
local function SellAllWithDiagnostics(source, manualRequest)
    if sellBusy then return false, 0, 0, "Another Merchant sale is already running" end
    sellBusy = true

    -- Preserve the original automatic behavior if its toggles are disabled.
    -- Explicit manual sales still receive the standard SellPerf measurements.
    if not manualRequest and not (_config and _config:Get("FarmEnabled") and _config:Get("AutoSell")) then
        local ok, sold, types, failed, reason = pcall(function() return _inventory:SellAll(false) end)
        sellBusy = false
        if not ok then error(sold, 0) end
        return sold, types, failed, reason
    end

    sellPerfSerial = sellPerfSerial + 1
    local id = sellPerfSerial
    local sampleCount, over50ms, over100ms = 0, 0, 0
    local maxFrameSeconds, totalFrameSeconds = 0, 0
    local listening = true
    local heartbeatConnection = nil

    -- The sampler is best-effort and must never prevent a sale.
    pcall(function()
        heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
            if not listening or type(dt) ~= "number" or dt < 0 then return end
            sampleCount = sampleCount + 1
            totalFrameSeconds = totalFrameSeconds + dt
            if dt > maxFrameSeconds then maxFrameSeconds = dt end
            if dt >= 0.05 then over50ms = over50ms + 1 end
            if dt >= 0.10 then over100ms = over100ms + 1 end
        end)
    end)

    moduleLog("INFO", ("[Farm][SellPerf] BEGIN id=%d source=%s"):format(id, tostring(source)))
    local startedAt = tick()
    local ok, sold, types, failed, reason = pcall(function()
        return _inventory:SellAll(manualRequest == true)
    end)
    local elapsedSeconds = math.max(0, tick() - startedAt)

    listening = false
    if heartbeatConnection then
        pcall(function() heartbeatConnection:Disconnect() end)
    end

    local avgFrameMs = sampleCount > 0 and (totalFrameSeconds * 1000 / sampleCount) or 0
    local message = ("[Farm][SellPerf] END id=%d source=%s ok=%s duration=%.3fs frames=%d avgFrame=%.1fms maxFrame=%.1fms slow50ms=%d slow100ms=%d"):format(
        id, tostring(source), tostring(ok), elapsedSeconds, sampleCount, avgFrameMs,
        maxFrameSeconds * 1000, over50ms, over100ms
    )
    -- Slow frames are correlation evidence, not proof that SellAll caused them.
    moduleLog((not ok or over100ms > 0) and "WARN" or "INFO", message)
    sellBusy = false
    if not ok then error(sold, 0) end
    return sold, types, failed, reason
end

-- Halloween item allowlist comes from observed live YBA spawn labels, never a generic "event" substring.
local EVENT_CANDY = {
    ["Yellow Candy"] = true, ["Blue Candy"] = true,
    ["Green Candy"] = true, ["Red Candy"] = true,
}
local function eventModeEnabled()
    return _config and _config:Get("EventItemsFarmEnabled") == true
end
local function eventModeReady()
    return eventModeEnabled() and not stopRequested
        and _config:Get("FarmEnabled") ~= true
        and not _config:Get("AutoPrestige")
        and not _config:Get("StandFarmEnabled")
        and not _config:Get("QuestFarmEnabled")
        and not _config:Get("NPCFarmEnabled")
        and not restockBusy and not prestigeSaleBusy
        and not manualSellBusy and not sellBusy
        and not prestigePending()
end

function Farm:Init(Modules)
    _runtimeLog = Modules.RuntimeLog
    _config    = Modules.Config
    _inventory = Modules.Inventory
    _movement  = Modules.Movement
    _serverHop = Modules.ServerHop
    _webhook   = Modules.Webhook
    moduleLog("INFO", "[Farm] Build PICKUP-COMPAT-20261014-R2; original cadence restored after kick report, live retest pending")
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
    -- A/B diagnostic only. Set BEFORE the dev loader in a fresh client session.
    local env = getgenv and getgenv() or _G
    if env.WhiteHubDevSkipCrashBypass == true then
        moduleLog("WARN", "[Farm][ClientFXTest] FunctionLibrary.pcall hook skipped by DEV flag (fresh-session A/B test).")
        return
    end
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
    detectionEpoch = detectionEpoch + 1
    local epoch = detectionEpoch
    local function detect(model, announce)
        if not model:IsA("Model") then return end
        if announce then task.wait(1) end -- Restore the pre-speed new-spawn settle window.
        local deadline = tick() + 2
        -- Initial items keep their original immediate scan; new spawns settle first.
        while epoch == detectionEpoch and model.Parent == ItemSpawnFolder do
            local info = GetItemInfo(model)
            if info then
                SpawnedItems[model] = info
                if announce then moduleLog("INFO", "[Farm] Item detected: " .. info.Name) end
                return
            end
            if tick() >= deadline then return end
            task.wait(0.03)
        end
    end
    for _, model in pairs(ItemSpawnFolder:GetChildren()) do
        pcall(function()
            if model:IsA("Model") then
                task.spawn(function() pcall(detect, model, false) end)
            end
        end)
    end
    local connection = ItemSpawnFolder.ChildAdded:Connect(function(model)
        task.spawn(function() pcall(detect, model, true) end)
    end)
    table.insert(runtimeConnections, connection)
end

local SAFE_SPOT = CFrame.new(978, -42, -49)

local function CollectItem(itemInfo, index, restockGuard, collectionMode)
    local character = Player.Character
    local function allowed()
        if Player.Character ~= character then return false end
        if restockGuard then return restockGuard() end
        if collectionMode == "event" then
            return eventModeReady() and itemInfo and EVENT_CANDY[itemInfo.Name] == true
        end
        return _config:Get("FarmEnabled") and not eventModeEnabled() and not stopRequested
    end
    if not allowed() then return false end

    local hrp = _movement:GetCharacter("HumanoidRootPart")
    if not hrp or not itemInfo or not itemInfo.Model or not itemInfo.Model.Parent then
        SpawnedItems[index] = nil
        return false
    end
    if _inventory:HasMax(itemInfo.Name) then
        SpawnedItems[index] = nil
        return false
    end

    local beforeCount = _inventory:Count(itemInfo.Name)
    local model = itemInfo.Model or index
    local started, bv, requests = tick(), nil, 0
    local ok, collected = pcall(function()
        bv = _movement:Freeze()
        if restockGuard then restockFreeze = bv end
        _movement:SetNoclip(true)
        _movement:Teleport(CFrame.new(itemInfo.Position.X, itemInfo.Position.Y - 25, itemInfo.Position.Z))
        task.wait(0.35)
        local function fire()
            if not allowed() or not model.Parent or not itemInfo.ProximityPrompt.Parent then return false end
            requests = requests + 1
            local fired, result = pcall(fireproximityprompt, itemInfo.ProximityPrompt)
            return fired and result ~= false
        end
        if not fire() then return false end
        local deadline, disappeared = tick() + 1.5, nil
        while tick() < deadline and allowed() do
            if _inventory:Count(itemInfo.Name) > beforeCount then return true end
            if not model.Parent then
                disappeared = disappeared or tick()
                -- Give a removed spawn a replication grace, but never call a
                -- competitor's pickup our own successful acquisition.
                if tick() - disappeared >= 0.35 then break end
            end
            task.wait(0.1)
        end
        return _inventory:Count(itemInfo.Name) > beforeCount
    end)
    if bv then pcall(function() _movement:Unfreeze(bv) end) end
    if restockFreeze == bv then restockFreeze = nil end
    -- Event cancellation still restores the real character to the safe spot.
    -- Collection ownership remains serialized by collectBusy.
    if hrp.Parent and (allowed() or (not restockGuard and Player.Character == character and (collectionMode == "event" or eventModeEnabled()))) then
        pcall(function() _movement:Teleport(SAFE_SPOT) end)
    end
    if allowed() then task.wait(0.15) end
    pcall(function() _movement:SetNoclip(false) end)
    if not allowed() then return false end
    if not ok then error("Item collection operation failed after cleanup", 0) end

    if ok and collected then
        SpawnedItems[index] = nil
        lastItemTime = tick()
        moduleLog("INFO", "[Farm] Collected: " .. itemInfo.Name)
        moduleLog("INFO", ("[Farm][PickupPerf] %s confirmed in %.3fs | prompts=%d"):format(itemInfo.Name, tick()-started, requests))
        return true
    end

    -- Keep a live item in the queue so a transient prompt failure can retry.
    if model and model.Parent then
        local refreshed = GetItemInfo(model)
        if refreshed then SpawnedItems[index] = refreshed end
    else
        SpawnedItems[index] = nil
    end
    moduleLog(model and model.Parent and "WARN" or "INFO", "[Farm] Collection was not confirmed: " .. tostring(itemInfo.Name))
    return false
end

-- Avoid racing a manual Merchant sale against an in-flight pickup.
-- The collection operation may yield while moving or waiting for a prompt.
local function CollectItemFromCycle(itemInfo, index)
    collectBusy = true
    local ok, result = pcall(CollectItem, itemInfo, index)
    collectBusy = false
    if not ok then error(result, 0) end
    return result
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
    if not _config:Get("FarmEnabled") or eventModeEnabled() or manualSellBusy then return end

    if shouldSkipHop() then
        moduleLog("INFO", "[Farm] DoHop aborted – skipping hop.")
        return
    end

    moduleLog("INFO", "[Farm] Server dry — selling, buying, then hopping...")
    if type(_serverHop.Prepare) == "function" then pcall(_serverHop.Prepare, _serverHop) end
    SellAllWithDiagnostics("server-hop")
    if manualSellBusy or stopRequested or not _config:Get("FarmEnabled") then return end
    _inventory:BuyLucky()
    if manualSellBusy or stopRequested or not _config:Get("FarmEnabled") then return end
    _serverHop:Hop(function()
        return not stopRequested and not manualSellBusy and _config:Get("FarmEnabled")
            and not _config:Get("AutoPrestige") and not _config:Get("StandFarmEnabled")
    end)
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
    return stopRequested or restockBusy or prestigeSaleBusy or manualSellBusy or prestigePending()
        or eventModeEnabled() or not _config:Get("FarmEnabled") or _config:Get("AutoPrestige")
end

-- Synchronous handoff from StandFarm. It never enables the normal phases,
-- sells/buys, changes persistent item filters, or hops with a result in flight.
function Farm:Restock(name, ownerActive, ownerKind, required)
    local allowedNames = { ["Rokakaka"]=true, ["Mysterious Arrow"]=true,
        ["Rib Cage of The Saint's Corpse"]=true }
    local prestige=ownerKind=="prestige"
    if prestige then allowedNames[name]=(_inventory:GetMax(name) or 0)>0 and name~="Lucky Arrow" and name~="Lucky Stone Mask" end
    required=prestige and math.min(tonumber(required) or 1,_inventory:GetMax(name) or 1) or 1
    if required<1 or required>50 or required%1~=0 then return false,"Invalid restock amount" end
    if not allowedNames[name] or type(ownerActive) ~= "function" then return false, "Invalid restock request" end
    if restockBusy or manualSellBusy or sellBusy or prestigeSaleBusy or stopRequested then return false, "Item Farm unavailable/busy" end
    restockBusy = true
    local epoch, char, movementUsed = restockEpoch, Player.Character, false
    local function permitted()
        local humanoid = char and char:FindFirstChildWhichIsA("Humanoid")
        return epoch == restockEpoch and not stopRequested and ownerActive()
            and humanoid and humanoid.Health > 0
            and Player.Character == char and not _config:Get("FarmEnabled") and not eventModeEnabled()
            and ((prestige and _config:Get("AutoPrestige")==true and not _config:Get("StandFarmEnabled"))
                or (not prestige and _config:Get("StandFarmEnabled")==true and not _config:Get("AutoPrestige")))
            and not _config:Get("QuestFarmEnabled") and not _config:Get("NPCFarmEnabled")
    end
    local ok, success, reason = pcall(function()
        local deadline, attempts, nextScan = tick() + 90, 0, 0
        while permitted() and tick() < deadline and attempts < 8 do
            if _inventory:Count(name) >= required then return true, "Stock confirmed" end
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
                    if permitted() and _inventory:Count(name) >= required then return true, "Stock confirmed" end
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

-- An independent MODE of this worker, not a second competing movement loop.
-- Reuses the original pickup path, inventory confirmation, and SAFE_SPOT cleanup.
-- Never calls SellAll, BuyLucky, the Merchant, or normal phase completion.
local function runEventCycle()
    moduleLog("INFO", "[EventFarm] Candy-only collection started: Yellow/Blue/Green/Red Candy.")
    lastItemTime = tick()
    local nextScan, nextAttempt = 0, {}
    local lastWaiting = false
    while eventModeReady() do
        local now = tick()
        if ItemSpawnFolder and now >= nextScan then
            nextScan = now + 1
            -- Normal phases can discard their cached items; rescan actual live spawns.
            for _, model in ipairs(ItemSpawnFolder:GetChildren()) do
                local info = GetItemInfo(model)
                if info and EVENT_CANDY[info.Name] then
                    SpawnedItems[model] = info
                end
            end
        end
        local snapshot = {}
        for model, info in pairs(SpawnedItems) do
            if EVENT_CANDY[info.Name] and info.Model and info.Model.Parent
                and (nextAttempt[model] or 0) <= now then
                snapshot[#snapshot + 1] = {Index=model, ItemInfo=info}
            end
        end
        for _, entry in ipairs(snapshot) do
            if not eventModeReady() then break end
            local item = entry.ItemInfo
            -- Unknown candy caps must never be fabricated; confirmation is inventory-only.
            if not _inventory:HasMax(item.Name) then
                local ok, confirmed = pcall(CollectItem, item, entry.Index, nil, "event")
                if not ok then
                    moduleLog("WARN", "[EventFarm] Pickup failed: "..tostring(item.Name))
                end
                if not ok or not confirmed then
                    -- Prevent spamming a failing prompt or full unknown-cap inventory.
                    nextAttempt[entry.Index] = tick() + 8
                else
                    nextAttempt[entry.Index] = nil
                    lastWaiting = false
                end
            end
        end
        if not eventModeReady() then break end
        if tick() - lastItemTime > NO_ITEM_TIMEOUT then
            if shouldSkipHop() then
                if not lastWaiting then
                    moduleLog("INFO", "[EventFarm] No confirmed candy for 20s; staying in private server.")
                    lastWaiting = true
                end
                lastItemTime = tick()
            else
                moduleLog("INFO", "[EventFarm] Server dry; hopping without selling or buying.")
                _serverHop:Hop(function() return eventModeReady() end)
                lastItemTime = tick()
            end
        end
        task.wait(0.7)
    end
    moduleLog("INFO", "[EventFarm] Candy-only collection paused/stopped.")
end

local function runCycle()
    lastItemTime = tick()
    _config:SetMany({ Phase1Notified = false, Phase3Notified = false })
    local lastWaitMessage
    local function logWait(message)
        if message ~= lastWaitMessage then moduleLog("INFO", message); lastWaitMessage=message end
    end

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
            CollectItemFromCycle(entry.ItemInfo, entry.Index)
        end

        if shouldPauseCycle() then return end

        local elapsed = tick() - lastItemTime
        if elapsed > NO_ITEM_TIMEOUT then
            if not _inventory:ShouldStopPhase1() then DoHop() end
        elseif #snapshot == 0 then
            logWait("[Farm] Waiting for items... (" .. math.max(0, math.floor(NO_ITEM_TIMEOUT - elapsed)) .. "s until hop)")
        end
        task.wait(1)
    end

    -- A pause/prestige transition is not a completed phase.
    if shouldPauseCycle() then return end

    SellAllWithDiagnostics("phase-1")
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
                CollectItemFromCycle(entry.ItemInfo, entry.Index)
            end

            if shouldPauseCycle() then return end

            local elapsed = tick() - lastItemTime
            if elapsed > NO_ITEM_TIMEOUT then
                if not _inventory:AllKeepItemsFull() then
                    moduleLog("INFO", "[Farm] Phase 2 — server dry, hopping...")
                    DoHop()
                end
            elseif #snapshot == 0 then
                logWait("[Farm] Waiting for keep-items... (" .. math.max(0, math.floor(NO_ITEM_TIMEOUT - elapsed)) .. "s until hop)")
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
            CollectItemFromCycle(entry.ItemInfo, entry.Index)
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
        while not stopRequested and (restockBusy or prestigeSaleBusy or manualSellBusy or prestigePending()
            or (not _config:Get("FarmEnabled") and not eventModeEnabled())
            or (eventModeEnabled() and not eventModeReady())) do
            task.wait(0.5)
        end
        while not stopRequested and _config:Get("AutoPrestige") do
            task.wait(0.5)
        end
        if stopRequested then break end

        cycleBusy = true
        local ok, err = pcall(eventModeEnabled() and runEventCycle or runCycle)
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

-- Manual sale from the Items tab. Never hops, buys, or permanently changes
-- FarmEnabled/AutoSell. Preserve item filter selection and use the same Merchant.
function Farm:SellNow()
    if not (_config and _inventory) then return false, "Farm modules not initialized" end
    if eventModeEnabled() then return false, "Disable Events Items Farm before using SELL NOW" end
    if manualSellBusy or sellBusy then return false, "A Merchant sale is already running" end
    if stopRequested or restockBusy or startupBusy or prestigeSaleBusy or prestigePending()
        or _config:Get("AutoPrestige") or _config:Get("StandFarmEnabled")
        or _config:Get("QuestFarmEnabled") or _config:Get("NPCFarmEnabled") then
        return false, "Another farm or prestige operation is active; stop it first"
    end

    -- Set the flag before yielding, so the regular worker stops starting new
    -- pickups. Wait for an already-started pickup to release its movement.
    manualSellBusy = true
    moduleLog("INFO", "[Farm][SellNow] Manual sale requested from Items tab.")
    local deadline = tick() + 8
    while collectBusy and tick() < deadline do task.wait(0.05) end
    if collectBusy then
        manualSellBusy = false
        moduleLog("WARN", "[Farm][SellNow] Pickup still active; sale safely skipped.")
        return false, "Wait for item collection to finish and try again"
    end

    -- Other modes can change while waiting for collection.
    if restockBusy or prestigeSaleBusy or prestigePending()
        or _config:Get("AutoPrestige") or _config:Get("StandFarmEnabled")
        or _config:Get("QuestFarmEnabled") or _config:Get("NPCFarmEnabled") then
        manualSellBusy = false
        return false, "Another operation started; manual sale cancelled"
    end

    local ok, sold, soldTypes, failedTypes, reason = pcall(SellAllWithDiagnostics, "manual", true)
    lastItemTime = tick() -- A completed manual sale should not immediately trigger a server hop.
    manualSellBusy = false

    if not ok then
        moduleLog("WARN", "[Farm][SellNow] Merchant failed: " .. tostring(sold))
        return false, "Merchant error; inspect Console"
    end
    if sold then
        moduleLog("INFO", ("[Farm][SellNow] Completed: %d type(s) sold, %d failed."):format(soldTypes or 0, failedTypes or 0))
        return true, ("Sold %d item type(s)%s. No server hop."):format(
            soldTypes or 0, (failedTypes or 0) > 0 and (", " .. tostring(failedTypes) .. " failed") or "")
    end
    moduleLog("INFO", "[Farm][SellNow] No sale confirmed: " .. tostring(reason or "nothing to sell"))
    return false, reason or "No sale confirmed"
end

-- Exclusive delegation to existing Merchant; normal Item Farm remains paused.
function Farm:PrestigeSell(ownerActive,sell)
    if restockBusy or cycleBusy or startupBusy or prestigeSaleBusy or manualSellBusy or sellBusy or stopRequested
        or type(ownerActive)~="function" or not ownerActive() or type(sell)~="function"
        or not _config:Get("AutoPrestige") or _config:Get("StandFarmEnabled")
        or _config:Get("QuestFarmEnabled") or _config:Get("NPCFarmEnabled") then return false,"Sale ownership unavailable" end
    prestigeSaleBusy=true
    local before=_config:Get("FarmEnabled")
    _config:Set("FarmEnabled",true,true)
    local ok,result=pcall(sell)
    _config:Set("FarmEnabled",before,true)
    prestigeSaleBusy=false
    return ok and result~=false,ok and "Merchant returned" or "Merchant failed"
end
function Farm:CanEnableEvent()
    return not (restockBusy or sellBusy or prestigeSaleBusy or manualSellBusy)
end
-- Before Quest/NPC takeover, allow a cancelled event pickup to finish cleanup.
function Farm:WaitForCollection(maxSeconds)
    local deadline=tick()+math.clamp(tonumber(maxSeconds) or 3,0,5)
    while collectBusy and tick()<deadline do task.wait(0.05) end
    return not collectBusy
end
function Farm:IsBusy() return restockBusy or cycleBusy or startupBusy or prestigeSaleBusy or manualSellBusy or sellBusy end

function Farm:IsRunning()
    return isRunning
end

function Farm:Destroy()
    detectionEpoch = detectionEpoch + 1
    self:Stop()
    for _, connection in ipairs(runtimeConnections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(runtimeConnections)
    runtimeSetup = false
    table.clear(SpawnedItems)
end

return Farm
