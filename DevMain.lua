-- WHITE HUB V3 EXPERIMENTAL LOADER
-- Only for manual testing, never merge this as Main.lua without approval.
-- Loads all modules from the dev branch; production Main.lua remains unchanged.

-- =====================
-- Main.lua (WHITE HUB V3 modular)
-- Safe re-execution + fail-fast boot diagnostics.
-- =====================

repeat task.wait(0.25) until game:IsLoaded() and game:GetService("Players").LocalPlayer

local Players     = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TextService = game:GetService("TextService")

local Player = Players.LocalPlayer
local env = getgenv and getgenv() or _G

-- ============================================================
-- BOOT LOGGER
-- ============================================================
local bootLog = {}
local bootStartedAt = tick()
local fatalShown = false

local function clockText()
    local ok, result = pcall(function()
        return os.date("%H:%M:%S")
    end)
    return ok and result or string.format("%.2f", tick() - bootStartedAt)
end

local RuntimeLog = {
    _entries = {},
    _listeners = {},
    _nextListenerId = 0,
    _maxEntries = 500,
    RuntimeId = "pending",
}

local function joinArgs(...)
    local out = {}
    for i = 1, select("#", ...) do
        out[#out + 1] = tostring(select(i, ...))
    end
    return table.concat(out, " ")
end

function RuntimeLog:Write(level, moduleName, ...)
    level = tostring(level or "INFO"):upper()
    moduleName = tostring(moduleName or "General")
    local message = joinArgs(...)
    local entry = {
        Time = clockText(),
        Level = level,
        Module = moduleName,
        Message = message,
    }

    table.insert(self._entries, entry)
    while #self._entries > self._maxEntries do
        table.remove(self._entries, 1)
    end

    for id, callback in pairs(self._listeners) do
        local ok = pcall(callback, entry)
        if not ok then
            self._listeners[id] = nil
        end
    end
end

function RuntimeLog:Info(moduleName, ...) self:Write("INFO", moduleName, ...) end
function RuntimeLog:Warn(moduleName, ...) self:Write("WARN", moduleName, ...) end
function RuntimeLog:Error(moduleName, ...) self:Write("ERROR", moduleName, ...) end

function RuntimeLog:GetEntries()
    local copy = {}
    for i, entry in ipairs(self._entries) do
        copy[i] = {
            Time = entry.Time,
            Level = entry.Level,
            Module = entry.Module,
            Message = entry.Message,
        }
    end
    return copy
end

function RuntimeLog:GetStats()
    local stats = { INFO = 0, WARN = 0, ERROR = 0, Total = #self._entries }
    for _, entry in ipairs(self._entries) do
        if stats[entry.Level] ~= nil then
            stats[entry.Level] = stats[entry.Level] + 1
        end
    end
    return stats
end

function RuntimeLog:GetLastError()
    for i = #self._entries, 1, -1 do
        local entry = self._entries[i]
        if entry.Level == "ERROR" or entry.Level == "WARN" then
            return entry
        end
    end
    return nil
end

function RuntimeLog:GetText()
    local stats = self:GetStats()
    local exec = "Unknown"
    pcall(function()
        if type(identifyexecutor) == "function" then
            local a, b = identifyexecutor()
            exec = b ~= nil and (tostring(a) .. " " .. tostring(b)) or tostring(a)
        end
    end)

    local lines = {
        "WHITE HUB V3 - RUNTIME LOG",
        "========================================",
        "Runtime ID: " .. tostring(self.RuntimeId or "unknown"),
        "PlaceId: " .. tostring(game.PlaceId),
        "JobId: " .. tostring(game.JobId),
        "Player: " .. tostring(Player and Player.Name or "unknown"),
        "Executor: " .. tostring(exec),
        ("Entries: %d | INFO: %d | WARN: %d | ERROR: %d"):format(stats.Total, stats.INFO, stats.WARN, stats.ERROR),
        "",
        "RUNTIME EVENTS",
        "----------------------------------------",
    }

    for _, entry in ipairs(self._entries) do
        lines[#lines + 1] = ("[%s] [%s] [%s] %s"):format(entry.Time, entry.Level, entry.Module, entry.Message)
    end

    return table.concat(lines, "\n")
end

function RuntimeLog:Clear()
    table.clear(self._entries)
    self:Write("INFO", "Console", "Runtime log cleared by user.")
end

function RuntimeLog:Subscribe(callback)
    if type(callback) ~= "function" then return nil end
    self._nextListenerId = self._nextListenerId + 1
    local id = self._nextListenerId
    self._listeners[id] = callback

    local disconnected = false
    return {
        Disconnect = function()
            if disconnected then return end
            disconnected = true
            self._listeners[id] = nil
        end
    }
end

local function pushLog(level, tag, msg)
    local line = ("[%s] [%s] [%s] %s"):format(clockText(), tostring(level), tostring(tag), tostring(msg))
    table.insert(bootLog, line)
    RuntimeLog:Write(level, tag, msg)

    if level == "ERROR" or level == "WARN" then
        warn("[WHITE HUB V3] " .. line)
    else
        print("[WHITE HUB V3] " .. line)
    end
end

local function LOG(tag, msg)
    pushLog("INFO", tag, msg)
end

local function ERR(tag, msg)
    pushLog("ERROR", tag, msg)
end

local function tracebackFor(err)
    local message = tostring(err)
    local ok, trace = pcall(function()
        if debug and type(debug.traceback) == "function" then
            return debug.traceback(message, 2)
        end
        return message
    end)
    return ok and tostring(trace) or message
end

local function executorName()
    local ok, name = pcall(function()
        if type(identifyexecutor) == "function" then
            local a, b = identifyexecutor()
            if b ~= nil then
                return tostring(a) .. " " .. tostring(b)
            end
            return tostring(a)
        end
        return "Unknown / identifyexecutor unavailable"
    end)
    return ok and name or "Unknown"
end

-- ============================================================
-- STANDALONE BOOT ERROR UI
-- This intentionally does NOT depend on UI.lua. If UI.lua itself fails,
-- the bootstrap can still explain the error and expose the full log.
-- ============================================================
local function destroyOldBootErrorUI()
    local locations = {}

    local okGui, playerGui = pcall(function()
        return Player:FindFirstChildOfClass("PlayerGui") or Player:WaitForChild("PlayerGui", 2)
    end)
    if okGui and playerGui then table.insert(locations, playerGui) end

    if type(gethui) == "function" then
        local ok, hui = pcall(gethui)
        if ok and hui then table.insert(locations, hui) end
    end

    for _, parent in ipairs(locations) do
        local old = parent:FindFirstChild("WhiteHubBootErrorUI")
        if old then pcall(function() old:Destroy() end) end
    end
end

destroyOldBootErrorUI()

local function copyText(text)
    local candidates = {}
    if type(setclipboard) == "function" then table.insert(candidates, setclipboard) end
    if type(toclipboard) == "function" then table.insert(candidates, toclipboard) end
    if type(setrbxclipboard) == "function" then table.insert(candidates, setrbxclipboard) end

    for _, fn in ipairs(candidates) do
        local ok = pcall(fn, text)
        if ok then return true end
    end

    if type(clipboard) == "table" and type(clipboard.set) == "function" then
        local ok = pcall(function() clipboard.set(text) end)
        if ok then return true end
    end

    return false
end

local function buildDetailedLog(failure)
    local lines = {
        "WHITE HUB V3 - BOOT DIAGNOSTIC",
        "========================================",
        "Runtime ID: " .. tostring(failure.runtimeId or "N/A"),
        "Failed module: " .. tostring(failure.module or "Unknown"),
        "Stage: " .. tostring(failure.stage or "Unknown"),
        "Reason: " .. tostring(failure.reason or "Unknown"),
        "PlaceId: " .. tostring(game.PlaceId),
        "JobId: " .. tostring(game.JobId),
        "Player: " .. tostring(Player and Player.Name or "Unknown"),
        "Executor: " .. executorName(),
        "Elapsed before failure: " .. string.format("%.2fs", tick() - bootStartedAt),
        "",
        "TRACEBACK / DETAILS",
        "----------------------------------------",
        tostring(failure.trace or failure.reason or "No traceback available."),
        "",
        "BOOT LOG",
        "----------------------------------------",
        table.concat(bootLog, "\n"),
    }
    return table.concat(lines, "\n")
end

local function showBootErrorUI(failure)
    local detailedLog = buildDetailedLog(failure)

    local ok, uiErr = pcall(function()
        destroyOldBootErrorUI()

        local parent
        if type(gethui) == "function" then
            local okHui, hui = pcall(gethui)
            if okHui and hui then parent = hui end
        end
        if not parent then
            parent = Player:FindFirstChildOfClass("PlayerGui") or Player:WaitForChild("PlayerGui", 5)
        end
        if not parent then error("Could not resolve a GUI parent for diagnostic UI") end

        local ScreenGui = Instance.new("ScreenGui")
        ScreenGui.Name = "WhiteHubBootErrorUI"
        ScreenGui.ResetOnSpawn = false
        ScreenGui.IgnoreGuiInset = false
        ScreenGui.DisplayOrder = 999999
        ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        ScreenGui.Parent = parent

        local Shade = Instance.new("Frame")
        Shade.Name = "Shade"
        Shade.Size = UDim2.new(1, 0, 1, 0)
        Shade.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        -- Keep the diagnostic readable without covering the entire mobile screen.
        Shade.BackgroundTransparency = 0.65
        Shade.BorderSizePixel = 0
        Shade.Parent = ScreenGui

        local Main = Instance.new("Frame")
        Main.Name = "ErrorWindow"
        Main.AnchorPoint = Vector2.new(0.5, 0.5)
        Main.Position = UDim2.new(0.5, 0, 0.5, 0)
        local viewport = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(800, 600)
        local compactWidth = math.clamp(viewport.X - 28, 300, 430)
        local compactHeight = math.clamp(viewport.Y - 90, 260, 340)
        Main.Size = UDim2.fromOffset(compactWidth, compactHeight)
        Main.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
        Main.BorderSizePixel = 0
        Main.Parent = Shade
        Instance.new("UICorner", Main).CornerRadius = UDim.new(0, 12)
        local mainStroke = Instance.new("UIStroke", Main)
        mainStroke.Color = Color3.fromRGB(210, 72, 72)
        mainStroke.Thickness = 1.5

        local sizeConstraint = Instance.new("UISizeConstraint", Main)
        sizeConstraint.MinSize = Vector2.new(300, 260)
        sizeConstraint.MaxSize = Vector2.new(430, 340)

        local Top = Instance.new("Frame")
        Top.Size = UDim2.new(1, 0, 0, 40)
        Top.BackgroundColor3 = Color3.fromRGB(34, 20, 24)
        Top.BorderSizePixel = 0
        Top.Parent = Main
        Instance.new("UICorner", Top).CornerRadius = UDim.new(0, 12)

        local topFix = Instance.new("Frame")
        topFix.Size = UDim2.new(1, 0, 0, 12)
        topFix.Position = UDim2.new(0, 0, 1, -12)
        topFix.BackgroundColor3 = Top.BackgroundColor3
        topFix.BorderSizePixel = 0
        topFix.Parent = Top

        local Title = Instance.new("TextLabel")
        Title.Position = UDim2.new(0, 12, 0, 0)
        Title.Size = UDim2.new(1, -58, 1, 0)
        Title.BackgroundTransparency = 1
        Title.Text = "WHITE HUB — BOOT FAILED"
        Title.TextColor3 = Color3.fromRGB(255, 225, 225)
        Title.TextSize = 15
        Title.Font = Enum.Font.GothamBold
        Title.TextXAlignment = Enum.TextXAlignment.Left
        Title.Parent = Top

        local Close = Instance.new("TextButton")
        Close.AnchorPoint = Vector2.new(1, 0.5)
        Close.Position = UDim2.new(1, -8, 0.5, 0)
        Close.Size = UDim2.new(0, 26, 0, 26)
        Close.BackgroundColor3 = Color3.fromRGB(130, 45, 52)
        Close.BorderSizePixel = 0
        Close.Text = "×"
        Close.TextColor3 = Color3.fromRGB(255,255,255)
        Close.TextSize = 18
        Close.Font = Enum.Font.GothamBold
        Close.Parent = Top
        Instance.new("UICorner", Close).CornerRadius = UDim.new(0, 7)

        local Summary = Instance.new("Frame")
        Summary.Position = UDim2.new(0, 10, 0, 48)
        Summary.Size = UDim2.new(1, -20, 0, 78)
        Summary.BackgroundColor3 = Color3.fromRGB(25, 25, 34)
        Summary.BorderSizePixel = 0
        Summary.Parent = Main
        Instance.new("UICorner", Summary).CornerRadius = UDim.new(0, 8)
        local summaryStroke = Instance.new("UIStroke", Summary)
        summaryStroke.Color = Color3.fromRGB(74, 58, 68)

        local ModuleLabel = Instance.new("TextLabel")
        ModuleLabel.Position = UDim2.new(0, 9, 0, 5)
        ModuleLabel.Size = UDim2.new(1, -18, 0, 19)
        ModuleLabel.BackgroundTransparency = 1
        ModuleLabel.Text = "Module: " .. tostring(failure.module or "Unknown")
        ModuleLabel.TextColor3 = Color3.fromRGB(255, 205, 205)
        ModuleLabel.TextSize = 13
        ModuleLabel.Font = Enum.Font.GothamBold
        ModuleLabel.TextXAlignment = Enum.TextXAlignment.Left
        ModuleLabel.Parent = Summary

        local StageLabel = Instance.new("TextLabel")
        StageLabel.Position = UDim2.new(0, 9, 0, 24)
        StageLabel.Size = UDim2.new(1, -18, 0, 17)
        StageLabel.BackgroundTransparency = 1
        StageLabel.Text = "Stage: " .. tostring(failure.stage or "Unknown")
        StageLabel.TextColor3 = Color3.fromRGB(220, 190, 190)
        StageLabel.TextSize = 11
        StageLabel.Font = Enum.Font.Gotham
        StageLabel.TextXAlignment = Enum.TextXAlignment.Left
        StageLabel.Parent = Summary

        local ReasonLabel = Instance.new("TextLabel")
        ReasonLabel.Position = UDim2.new(0, 9, 0, 42)
        ReasonLabel.Size = UDim2.new(1, -18, 0, 31)
        ReasonLabel.BackgroundTransparency = 1
        ReasonLabel.Text = "Reason: " .. tostring(failure.reason or "Unknown")
        ReasonLabel.TextColor3 = Color3.fromRGB(235, 235, 240)
        ReasonLabel.TextSize = 10
        ReasonLabel.Font = Enum.Font.Code
        ReasonLabel.TextWrapped = true
        ReasonLabel.TextXAlignment = Enum.TextXAlignment.Left
        ReasonLabel.TextYAlignment = Enum.TextYAlignment.Top
        ReasonLabel.Parent = Summary

        local LogTitle = Instance.new("TextLabel")
        LogTitle.Position = UDim2.new(0, 12, 0, 132)
        LogTitle.Size = UDim2.new(1, -24, 0, 16)
        LogTitle.BackgroundTransparency = 1
        LogTitle.Text = "Diagnostic log"
        LogTitle.TextColor3 = Color3.fromRGB(190, 190, 205)
        LogTitle.TextSize = 10
        LogTitle.Font = Enum.Font.GothamBold
        LogTitle.TextXAlignment = Enum.TextXAlignment.Left
        LogTitle.Parent = Main

        local LogBox = Instance.new("ScrollingFrame")
        LogBox.Position = UDim2.new(0, 10, 0, 151)
        LogBox.Size = UDim2.new(1, -20, 1, -198)
        LogBox.BackgroundColor3 = Color3.fromRGB(10, 10, 15)
        LogBox.BorderSizePixel = 0
        LogBox.ScrollBarThickness = 4
        LogBox.ScrollBarImageColor3 = Color3.fromRGB(130, 80, 95)
        LogBox.CanvasSize = UDim2.new(0, 0, 0, 0)
        LogBox.Parent = Main
        Instance.new("UICorner", LogBox).CornerRadius = UDim.new(0, 8)

        local LogText = Instance.new("TextLabel")
        LogText.Position = UDim2.new(0, 7, 0, 6)
        LogText.Size = UDim2.new(1, -14, 0, 10)
        LogText.BackgroundTransparency = 1
        LogText.Text = detailedLog
        LogText.TextColor3 = Color3.fromRGB(215, 215, 225)
        LogText.TextSize = 9
        LogText.Font = Enum.Font.Code
        LogText.TextWrapped = true
        LogText.TextXAlignment = Enum.TextXAlignment.Left
        LogText.TextYAlignment = Enum.TextYAlignment.Top
        LogText.Parent = LogBox

        local function resizeLog()
            local width = math.max(240, LogBox.AbsoluteSize.X - 22)
            local bounds = TextService:GetTextSize(detailedLog, LogText.TextSize, LogText.Font, Vector2.new(width, 100000))
            LogText.Size = UDim2.new(1, -14, 0, bounds.Y + 10)
            LogBox.CanvasSize = UDim2.new(0, 0, 0, bounds.Y + 20)
        end
        task.defer(resizeLog)
        LogBox:GetPropertyChangedSignal("AbsoluteSize"):Connect(resizeLog)

        local Copy = Instance.new("TextButton")
        Copy.Position = UDim2.new(0, 10, 1, -39)
        Copy.Size = UDim2.new(0.66, -14, 0, 30)
        Copy.BackgroundColor3 = Color3.fromRGB(115, 72, 190)
        Copy.BorderSizePixel = 0
        Copy.Text = "Copy Log"
        Copy.TextColor3 = Color3.fromRGB(255,255,255)
        Copy.TextSize = 11
        Copy.Font = Enum.Font.GothamBold
        Copy.Parent = Main
        Instance.new("UICorner", Copy).CornerRadius = UDim.new(0, 8)

        local AbortLabel = Instance.new("TextLabel")
        AbortLabel.AnchorPoint = Vector2.new(1, 0)
        AbortLabel.Position = UDim2.new(1, -10, 1, -39)
        AbortLabel.Size = UDim2.new(0.34, -2, 0, 30)
        AbortLabel.BackgroundColor3 = Color3.fromRGB(42, 42, 52)
        AbortLabel.BorderSizePixel = 0
        AbortLabel.Text = "Aborted safely"
        AbortLabel.TextColor3 = Color3.fromRGB(190, 190, 200)
        AbortLabel.TextSize = 9
        AbortLabel.Font = Enum.Font.Gotham
        AbortLabel.Parent = Main
        Instance.new("UICorner", AbortLabel).CornerRadius = UDim.new(0, 8)

        Copy.MouseButton1Click:Connect(function()
            if copyText(detailedLog) then
                local oldText = Copy.Text
                Copy.Text = "Copied!"
                Copy.BackgroundColor3 = Color3.fromRGB(50, 145, 82)
                task.delay(2, function()
                    if Copy and Copy.Parent then
                        Copy.Text = oldText
                        Copy.BackgroundColor3 = Color3.fromRGB(115, 72, 190)
                    end
                end)
            else
                Copy.Text = "No clipboard API"
                Copy.BackgroundColor3 = Color3.fromRGB(120, 72, 72)
                task.delay(3, function()
                    if Copy and Copy.Parent then
                        Copy.Text = "Copy Log"
                        Copy.BackgroundColor3 = Color3.fromRGB(115, 72, 190)
                    end
                end)
            end
        end)

        Close.MouseButton1Click:Connect(function()
            ScreenGui:Destroy()
        end)

        -- Basic dragging so the diagnostic window does not block a fixed area.
        local UIS = game:GetService("UserInputService")
        local dragging, dragStart, startPos = false, nil, nil
        Top.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragStart = input.Position
                startPos = Main.Position
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then dragging = false end
                end)
            end
        end)
        UIS.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                local delta = input.Position - dragStart
                Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end)
    end)

    if not ok then
        warn("[WHITE HUB V3][BOOT ERROR UI FAILED] " .. tostring(uiErr))
        warn(detailedLog)
    end
end

-- ============================================================
-- PREVIOUS RUNTIME CLEANUP
-- ============================================================
env.AutoPrestigeEnabled = false
local previous = _G.WhiteHubModules
if previous then
    -- Retire the removed E1 scheduler when upgrading an already-running Hub.
    if previous.SmartFarmEngine and previous.SmartFarmEngine.Destroy then
        pcall(function() previous.SmartFarmEngine:Destroy() end)
    end
    for _, name in ipairs({"AutoPrestigeRuntime", "CatalogRefresh", "UI", "WhiteAI", "StandFarm", "CombatFarm", "Farm", "ServerHop", "Movement"}) do
        local module = previous[name]
        if module and module.Destroy then
            pcall(function() module:Destroy() end)
        elseif module and module.Stop then
            pcall(function() module:Stop() end)
        end
    end
end
_G.WhiteHubModules = nil

task.wait(0.25)
env.__WhiteHubRuntimeId = HttpService:GenerateGUID(false)
local runtimeId = env.__WhiteHubRuntimeId
RuntimeLog.RuntimeId = runtimeId

LOG("BOOT", "Starting runtime " .. runtimeId)

local BASE_URL = "https://raw.githubusercontent.com/WHITEDRAGONx/WHITE-HUB/dev/2026-10-10-autosell-compat/"
local Modules = { RuntimeLog = RuntimeLog }

local function cleanupLoadedModules()
    env.AutoPrestigeEnabled = false

    for _, name in ipairs({"AutoPrestigeRuntime", "CatalogRefresh", "UI", "WhiteAI", "StandFarm", "CombatFarm", "Farm", "ServerHop", "Movement", "Inventory", "Webhook", "Config"}) do
        local module = Modules[name]
        if module then
            if type(module.Destroy) == "function" then
                pcall(function() module:Destroy() end)
            elseif type(module.Stop) == "function" then
                pcall(function() module:Stop() end)
            end
        end
    end

    if _G.WhiteHubModules == Modules then
        _G.WhiteHubModules = nil
    end
end

local function abortBoot(moduleName, stage, reason, trace)
    if fatalShown then return false end
    fatalShown = true

    ERR("ABORT", ("%s failed during %s: %s"):format(tostring(moduleName), tostring(stage), tostring(reason)))

    if env.__WhiteHubRuntimeId == runtimeId then
        env.__WhiteHubRuntimeId = nil
    end
    cleanupLoadedModules()

    showBootErrorUI({
        runtimeId = runtimeId,
        module = moduleName,
        stage = stage,
        reason = reason,
        trace = trace or reason,
    })

    return false
end

local function runtimeFatal(moduleName, stage, err)
    if env.__WhiteHubRuntimeId ~= runtimeId then return end
    local trace = tostring(err)
    local reason = trace:match("^[^\n]+") or trace
    abortBoot(moduleName, stage, reason, trace)
end

-- ============================================================
-- MODULE DOWNLOAD / COMPILE / EXECUTE / VALIDATE
-- ============================================================
local function fetchSource(file)
    -- Cache-bust every module request so Delta/GitHub raw cannot serve an older revision.
    local url = BASE_URL .. file .. "?whv3=" .. tostring(runtimeId)
    LOG("DOWNLOAD", "Fetching " .. file)

    local response, fetchError, done = nil, nil, false
    task.spawn(function()
        local ok, res = pcall(function()
            return game:HttpGet(url, true)
        end)
        if ok and type(res) == "string" and res ~= "" then
            response = res
        elseif ok then
            fetchError = "HTTP request returned an empty/non-string response"
        else
            fetchError = tostring(res)
        end
        done = true
    end)

    local deadline = tick() + 15
    while not done and tick() < deadline and env.__WhiteHubRuntimeId == runtimeId do
        task.wait(0.1)
    end

    if env.__WhiteHubRuntimeId ~= runtimeId then
        return nil, "Runtime was replaced while downloading the module"
    end
    if not done then
        return nil, "Download timed out after 15 seconds\nURL: " .. url
    end
    if not response then
        return nil, (fetchError or "Download failed") .. "\nURL: " .. url
    end
    if response:find("<!DOCTYPE", 1, true) or response:sub(1, 3) == "404" then
        return nil, "Remote file was not found or returned an HTML/404 response\nURL: " .. url
    end

    LOG("DOWNLOAD", ("%s downloaded (%d bytes)"):format(file, #response))
    return response
end

local moduleRequirements = {
    Config     = {"Load", "Get", "Set"},
    Webhook    = {"Init"},
    Movement   = {"Init"},
    ServerHop  = {"Init"},
    Inventory  = {"Init"},
    CombatFarm = {"Init"},
    StandFarm  = {"Init", "Start", "Stop", "GetStatus", "RecoverTransfer", "GetResumeSupport", "ResetStatistics"},
    StandTransfer = {"Init", "Issue", "Claim", "Invalidate"},
    StandV2UI = {"Init", "BuildResume", "BuildSkins", "BuildStats"},
    CatalogRefresh = {"Init", "GetNames", "GetState", "Refresh", "Destroy"},
    GameCatalog = {"Init", "Names", "GetSkins", "GetQuests", "IsInfo"},
    ChoiceUI = {"Init", "Build", "Toggle", "Filter", "Close", "Destroy"},
    UICompact = {"Init", "Caption", "Arrange", "Observe", "Responsive", "ScaleFor"},
    AutoPrestigeRuntime = {"Init", "Start", "Stop", "IsBusy", "Register", "Watch", "GetStatus", "BuildStatus"},
    PrestigeDialogue = {"Init", "Run", "Drive", "Restore"},
    Farm       = {"Init", "Start"},
    UI         = {"Init", "Create"},
}

local function validateModule(moduleName, result)
    if type(result) ~= "table" then
        return false, ("Module returned %s instead of a table. It must end with 'return %s' (or its module table)."):format(type(result), moduleName)
    end

    for _, methodName in ipairs(moduleRequirements[moduleName] or {}) do
        if type(result[methodName]) ~= "function" then
            return false, ("Required method '%s:%s()' is missing or is not a function."):format(moduleName, methodName)
        end
    end

    return true
end

local function loadModule(entry)
    local source, fetchErr = fetchSource(entry.file)
    if not source then
        return nil, {
            stage = "DOWNLOAD",
            reason = fetchErr,
            trace = fetchErr,
        }
    end

    local compiler = loadstring or load
    if type(compiler) ~= "function" then
        return nil, {
            stage = "COMPILE",
            reason = "Neither loadstring nor load is available in this executor.",
            trace = "The executor cannot compile downloaded Lua source because loadstring/load is unavailable.",
        }
    end

    local func, compileErr = compiler(source, "@" .. entry.file)
    if not func then
        return nil, {
            stage = "COMPILE",
            reason = tostring(compileErr),
            trace = tostring(compileErr),
        }
    end
    LOG("COMPILE", entry.file .. " compiled successfully")

    local ok, result = xpcall(func, tracebackFor)
    if not ok then
        return nil, {
            stage = "MODULE RUNTIME",
            reason = tostring(result):match("^[^\n]+") or tostring(result),
            trace = tostring(result),
        }
    end

    local valid, validationErr = validateModule(entry.key, result)
    if not valid then
        return nil, {
            stage = "VALIDATION",
            reason = validationErr,
            trace = validationErr,
        }
    end

    LOG("LOAD", entry.key .. " loaded and validated")
    return result
end

local moduleFiles = {
    { key = "Config",     file = "Config.lua" },
    { key = "Webhook",    file = "Webhook.lua" },
    { key = "Movement",   file = "Movement.lua" },
    { key = "ServerHop",  file = "ServerHop.lua" },
    { key = "Inventory",  file = "Inventory.lua" },
    { key = "CombatFarm", file = "CombatFarm.lua" },
    { key = "StandFarm",  file = "StandFarm.lua" },
    { key = "StandTransfer", file = "StandTransfer.lua" },
    { key = "StandV2UI", file = "StandV2UI.lua" },
    { key = "CatalogRefresh", file = "CatalogRefresh.lua" },
    { key = "GameCatalog", file = "GameCatalog.lua" },
    { key = "ChoiceUI", file = "ChoiceUI.lua" },
    { key = "UICompact", file = "UICompact.lua" },
    { key = "PrestigeDialogue", file = "PrestigeDialogue.lua" },
    { key = "AutoPrestigeRuntime", file = "AutoPrestigeRuntime.lua" },
    { key = "Farm",       file = "Farm.lua" },
    { key = "WhiteAI",    file = "WhiteAI.lua" },
    { key = "UI",         file = "UI.lua" },
}

for _, entry in ipairs(moduleFiles) do
    local mod, failure = loadModule(entry)
    if not mod then
        abortBoot(entry.key, failure.stage, failure.reason, failure.trace)
        return
    end
    Modules[entry.key] = mod
end

-- AutoPrestige is a standalone worker rather than a table module. Download and
-- compile it during boot so a missing/broken file aborts before the main UI starts.
local autoPrestigeSource, autoPrestigeFetchErr = fetchSource("AutoPrestige.lua")
if not autoPrestigeSource then
    abortBoot("AutoPrestige", "DOWNLOAD", autoPrestigeFetchErr, autoPrestigeFetchErr)
    return
end

local compiler = loadstring or load
if type(compiler) ~= "function" then
    abortBoot("AutoPrestige", "COMPILE", "loadstring/load is unavailable", "Cannot compile AutoPrestige.lua in this executor.")
    return
end

local autoPrestigeFunc, autoPrestigeCompileErr = compiler(autoPrestigeSource, "@AutoPrestige.lua")
if not autoPrestigeFunc then
    abortBoot("AutoPrestige", "COMPILE", tostring(autoPrestigeCompileErr), tostring(autoPrestigeCompileErr))
    return
end
LOG("COMPILE", "AutoPrestige.lua compiled successfully")

-- ============================================================
-- CONFIG + INIT
-- ============================================================
local okConfig, configResult = xpcall(function()
    Modules.Config:Load()
end, tracebackFor)
if not okConfig then
    abortBoot("Config", "CONFIG LOAD", tostring(configResult):match("^[^\n]+") or tostring(configResult), tostring(configResult))
    return
end
LOG("CONFIG", "Config loaded")

local initOrder = {"Webhook", "Movement", "ServerHop", "Inventory", "CombatFarm", "StandTransfer", "StandV2UI", "StandFarm", "Farm", "PrestigeDialogue", "AutoPrestigeRuntime", "UICompact", "CatalogRefresh", "GameCatalog", "ChoiceUI", "WhiteAI", "UI"}
for _, name in ipairs(initOrder) do
    local module = Modules[name]
    local ok, initResult = xpcall(function()
        module:Init(Modules)
    end, tracebackFor)

    if not ok then
        abortBoot(name, "INIT", tostring(initResult):match("^[^\n]+") or tostring(initResult), tostring(initResult))
        return
    end
    LOG("INIT", name .. " initialized")
end

_G.WhiteHubModules = Modules

-- ============================================================
-- UI CREATE
-- ============================================================
local okUI, uiResult = xpcall(function()
    Modules.UI:Create()
end, tracebackFor)
if not okUI then
    abortBoot("UI", "CREATE", tostring(uiResult):match("^[^\n]+") or tostring(uiResult), tostring(uiResult))
    return
end
LOG("UI", "Main UI created")

-- ============================================================
-- LONG-RUNNING WORKERS
-- ============================================================
-- Item farm controller remains alive and pauses itself for Auto Prestige.
task.spawn(function()
    local ok, result = xpcall(function()
        Modules.Farm:Start()
    end, tracebackFor)

    if not ok and env.__WhiteHubRuntimeId == runtimeId then
        runtimeFatal("Farm", "START / RUNTIME", result)
    end
end)

-- Auto Prestige remains a standalone worker, but its source was already fetched
-- and compiled above. Runtime errors are promoted to the same diagnostic UI.
env.AutoPrestigeEnabled = Modules.Config:Get("AutoPrestige") == true

task.spawn(function()
    local ok, result = xpcall(autoPrestigeFunc, tracebackFor)
    if not ok and env.__WhiteHubRuntimeId == runtimeId then
        runtimeFatal("AutoPrestige", "START / RUNTIME", result)
    end
end)

LOG("BOOT", "WHITE HUB V3 running. All critical modules passed boot validation.")
-- Only a valid one-use arrival intent can authorize the opt-in exception.
Modules.StandFarm:RecoverTransfer()
