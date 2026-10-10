-- =====================
-- Inventory.lua
-- BUILD: ZERO-DELAY-2026.09.14-R1
-- Handles item counting, selling, buying, and keep-item logic.
-- Updated for YBA's new dialogue system (v1.7974+).
-- ZERO-DELAY build: proven Merchant FINAL path (~0.70s) with safe restoration and fallbacks.
-- =====================

local Players             = game:GetService("Players")
local VirtualInputManager = game:GetService("VirtualInputManager")
local MarketplaceService  = game:GetService("MarketplaceService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")

local Player    = Players.LocalPlayer
local Inventory = {}

local _config   = nil
local _movement = nil

-- =====================
-- CONSTANTS
-- =====================
local LUCKY_STOP  = 9
local MONEY_STOP  = 1000000
local GAMEPASS_2X = 14597778
local _has2x      = false

-- Maximum item counts per item type (doubled if player owns 2x gamepass)
local MaxItemAmounts = {
    ["Gold Coin"]                      = 45,
    ["Rokakaka"]                       = 25,
    ["Pure Rokakaka"]                  = 10,
    ["Mysterious Arrow"]               = 25,
    ["Diamond"]                        = 30,
    ["Ancient Scroll"]                 = 10,
    ["Caesar's Headband"]              = 10,
    ["Stone Mask"]                     = 10,
    ["Rib Cage of The Saint's Corpse"] = 20,
    ["Quinton's Glove"]                = 10,
    ["Zeppeli's Hat"]                  = 10,
    ["Lucky Arrow"]                    = 10,
    ["Lucky Stone Mask"]               = 10,
    ["Clackers"]                       = 10,
    ["Steel Ball"]                     = 10,
    ["Dio's Diary"]                    = 10,
}

local _runtimeLog = nil
local _rawPrint, _rawWarn = print, warn
local function moduleLog(level, ...)
    if _runtimeLog and type(_runtimeLog.Write) == "function" then
        pcall(_runtimeLog.Write, _runtimeLog, level, "Inventory", ...)
    end
    if level == "WARN" or level == "ERROR" then
        _rawWarn(...)
    else
        _rawPrint(...)
    end
end

-- =====================
-- INIT
-- =====================
function Inventory:Init(Modules)
    _runtimeLog = Modules.RuntimeLog
    _config   = Modules.Config
    _movement = Modules.Movement

    -- Detect 2x gamepass and double all item caps
    pcall(function()
        _has2x = MarketplaceService:UserOwnsGamePassAsync(Player.UserId, GAMEPASS_2X)
    end)
    if _has2x then
        for k, v in pairs(MaxItemAmounts) do
            MaxItemAmounts[k] = v * 2
        end
        moduleLog("INFO", "[Inventory] 2x gamepass detected — item caps doubled.")
    else
        moduleLog("INFO", "[Inventory] Initialized (no 2x gamepass).")
    end
end

-- =====================
-- ITEM COUNTING
-- =====================

-- Counts how many of a given item the player currently has
-- (checks both Backpack and Character)
function Inventory:Count(name)
    local count = 0

    -- Count in backpack
    if Player.Backpack then
        for _, tool in pairs(Player.Backpack:GetChildren()) do
            if tool.Name == name then
                count = count + 1
            end
        end
    end

    -- Count equipped tools in character
    if Player.Character then
        for _, obj in pairs(Player.Character:GetChildren()) do
            if obj:IsA("Tool") and obj.Name == name then
                count = count + 1
            end
        end
    end

    return count
end

-- Returns true if the player has reached the max cap for the item
function Inventory:HasMax(name)
    local cap = MaxItemAmounts[name]
    if not cap then return false end
    return self:Count(name) >= cap
end

-- Returns the max cap for the given item (or 0 if unknown)
function Inventory:GetMax(name)
    return MaxItemAmounts[name] or 0
end

-- =====================
-- PLAYER STATS HELPERS
-- =====================

-- Returns the player's current money (from PlayerStats)
function Inventory:GetMoney()
    local ok, val = pcall(function()
        return Player.PlayerStats.Money.Value
    end)
    return ok and val or 0
end

-- Phase 1 thresholds
function Inventory:GetLuckyStop()     return LUCKY_STOP end
function Inventory:GetMoneyStop()     return MONEY_STOP end
function Inventory:HasEnoughLucky()   return self:Count("Lucky Arrow") >= LUCKY_STOP end
function Inventory:IsMoneyMaxed()     return self:GetMoney() >= MONEY_STOP end
function Inventory:ShouldStopPhase1() return self:HasEnoughLucky() and self:IsMoneyMaxed() end

-- =====================
-- KEEP ITEMS LOGIC
-- =====================

-- Returns a list of items the user wants to keep (sell = false)
-- Lucky Arrow and Lucky Stone Mask are always excluded
function Inventory:GetKeepItems()
    local sellItems = _config:GetSellItems()
    local list = {}
    for name, sell in pairs(sellItems) do
        if not sell and name ~= "Lucky Arrow" and name ~= "Lucky Stone Mask" then
            table.insert(list, name)
        end
    end
    return list
end

-- Returns true if ALL keep-items are at max capacity
function Inventory:AllKeepItemsFull()
    local keepItems = self:GetKeepItems()
    if #keepItems == 0 then return true end
    for _, name in ipairs(keepItems) do
        if not self:HasMax(name) then
            return false
        end
    end
    return true
end

-- =====================
-- DIALOGUE CLICKING HELPERS
-- YBA 1.7974+ uses the newer client-side dialogue system.
-- The Merchant wording/options can change, so selling is intent-based
-- instead of depending on one exact sentence sequence.
-- =====================

local function normalizeText(text)
    text = tostring(text or ""):lower()
    text = text:gsub("[%c%p]", " ")
    text = text:gsub("%s+", " ")
    return text:match("^%s*(.-)%s*$") or ""
end

local function getButtonText(btn)
    if not btn then return "" end

    if btn:IsA("TextButton") then
        local direct = tostring(btn.Text or "")
        if direct ~= "" then
            return direct
        end
    end

    -- Some dialogue versions put the visible text in a child TextLabel.
    for _, child in ipairs(btn:GetDescendants()) do
        if child:IsA("TextLabel") and tostring(child.Text or "") ~= "" then
            return child.Text
        end
    end

    return ""
end

local function isActuallyVisible(guiObject)
    if not guiObject or not guiObject.Parent then return false end
    if guiObject:IsA("GuiObject") and guiObject.Visible == false then return false end

    local parent = guiObject.Parent
    while parent and parent ~= Player.PlayerGui do
        if parent:IsA("GuiObject") and parent.Visible == false then
            return false
        end
        parent = parent.Parent
    end

    return true
end

local function getDialogueGui()
    local direct = Player.PlayerGui:FindFirstChild("DialogueGui")
    if direct then return direct end

    -- Fallback for renamed/new dialogue containers.
    for _, obj in ipairs(Player.PlayerGui:GetChildren()) do
        local lowered = tostring(obj.Name):lower()
        if lowered:find("dialog", 1, true) then
            return obj
        end
    end

    return nil
end

local function getVisibleDialogueButtons()
    local dlg = getDialogueGui()
    if not dlg then return {} end

    local buttons = {}
    for _, obj in ipairs(dlg:GetDescendants()) do
        if obj:IsA("GuiButton") and isActuallyVisible(obj) then
            local text = getButtonText(obj)
            if normalizeText(text) ~= "" then
                table.insert(buttons, {
                    Button = obj,
                    Text = text,
                    Normalized = normalizeText(text),
                })
            end
        end
    end

    return buttons
end

local function describeButtons(buttons)
    local texts = {}
    for _, entry in ipairs(buttons) do
        table.insert(texts, tostring(entry.Text))
    end
    return table.concat(texts, " | ")
end

-- Internal click support lets Fast Sell drive dialogue without visibly clicking it.
local function hasInternalClickSupport()
    return type(firesignal) == "function" or type(getconnections) == "function"
end

local function fastClickButton(btn)
    if not btn or not btn.Parent then return false end

    -- Preferred path: directly fire the Roblox signal. This does not require
    -- the button to be visible on screen.
    if type(firesignal) == "function" then
        local ok = pcall(function()
            firesignal(btn.MouseButton1Click)
        end)
        if ok then return true end
    end

    -- Executor fallback: call MouseButton1Click connections directly.
    -- MouseButton1Click carries no arguments, so this is safer than trying
    -- to invoke Activated callbacks with fabricated InputObjects.
    if type(getconnections) == "function" then
        local ok, connections = pcall(function()
            return getconnections(btn.MouseButton1Click)
        end)
        if ok and type(connections) == "table" then
            local invoked = false
            for _, connection in ipairs(connections) do
                local enabled = true
                pcall(function()
                    if connection.Enabled ~= nil then
                        enabled = connection.Enabled
                    end
                end)

                if enabled then
                    local fn = nil
                    pcall(function() fn = connection.Function end)
                    if type(fn) == "function" then
                        if pcall(fn) then
                            invoked = true
                        end
                    end
                end
            end
            if invoked then return true end
        end
    end

    return false
end

-- Attempts an internal click first, then a physical-screen click as the
-- compatibility fallback used by the normal visible dialogue mode.
local function clickButton(btn)
    if fastClickButton(btn) then return true end
    if not btn or not btn.Parent then return false end

    local ok = pcall(function()
        local absPos  = btn.AbsolutePosition
        local absSize = btn.AbsoluteSize
        local x = absPos.X + absSize.X / 2
        local y = absPos.Y + absSize.Y / 2

        VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 1)
        task.wait(0.05)
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 1)
    end)

    return ok
end

-- Fast Sell suppresses ScreenGui rendering while leaving the dialogue tree
-- alive. This means signals/connections can still be invoked internally.
local suppressedDialogueGuis = {}

local function suppressDialogueRendering()
    local dlg = getDialogueGui()
    if not dlg then return false end

    if dlg:IsA("ScreenGui") then
        if suppressedDialogueGuis[dlg] == nil then
            local state = { Enabled = dlg.Enabled, Connection = nil }
            state.Connection = dlg:GetPropertyChangedSignal("Enabled"):Connect(function()
                -- YBA may try to re-enable the dialogue while opening the next
                -- page. Keep it hidden for the duration of Fast Sell.
                if suppressedDialogueGuis[dlg] and dlg.Enabled then
                    dlg.Enabled = false
                end
            end)
            suppressedDialogueGuis[dlg] = state
        end
        dlg.Enabled = false
        return true
    end

    -- If YBA changes DialogueGui into a non-ScreenGui container, do not hide
    -- it here because Visible=false would also make our option scanner ignore it.
    return false
end

local function restoreDialogueRendering()
    for dlg, state in pairs(suppressedDialogueGuis) do
        if state and state.Connection then
            pcall(function() state.Connection:Disconnect() end)
        end
        if dlg and dlg.Parent and dlg:IsA("ScreenGui") then
            pcall(function() dlg.Enabled = state and state.Enabled ~= false end)
        end
        suppressedDialogueGuis[dlg] = nil
    end
end

local NEGATIVE_WORDS = {
    "buy", "leave", "cancel", "nevermind", "never mind",
    "no thanks", "no thank", "goodbye", "exit", "nothing",
}

local function containsAny(text, words)
    for _, word in ipairs(words) do
        if text:find(word, 1, true) then
            return true
        end
    end
    return false
end

-- Scores an option by SELL intent. This intentionally does not require
-- exact English sentences so wording/format changes are less likely to break it.
local function scoreSellOption(entry)
    local text = entry.Normalized
    if text == "" then return -math.huge end
    if containsAny(text, NEGATIVE_WORDS) then return -1000 end

    local score = 0
    local hasSell = text:find("sell", 1, true) ~= nil
    local hasAll = text:find("all", 1, true) ~= nil
    local hasEverything = text:find("everything", 1, true) ~= nil
    local hasMax = text:find("max", 1, true) ~= nil

    -- Quantity selection: strongly prefer ALL/MAX/EVERYTHING.
    if hasSell and (hasAll or hasEverything or hasMax) then score = score + 220 end
    if hasAll or hasEverything or hasMax then score = score + 150 end

    -- General sell route / currently equipped item route.
    if hasSell then score = score + 100 end
    if text:find("this", 1, true) and hasSell then score = score + 30 end
    if text:find("item", 1, true) and hasSell then score = score + 20 end

    -- Confirmation pages in the new dialogue system.
    if text:find("deal", 1, true) then score = score + 90 end
    if text:find("confirm", 1, true) then score = score + 80 end
    if text == "yes" or text:find("yes ", 1, true) == 1 then score = score + 70 end
    if text == "ok" or text == "okay" or text:find("sure", 1, true) then score = score + 55 end

    -- If quantity choices are numbers only, prefer the largest-looking option
    -- only as a weak fallback; explicit ALL/MAX always wins above.
    local quantity = tonumber(text:match("(%d+)%s*x")) or tonumber(text:match("sell%s+(%d+)"))
    if quantity then
        score = score + math.min(quantity, 50)
    end

    return score
end

local function waitForDialogueButtons(timeout, fastMode)
    timeout = timeout or 3
    local started = tick()

    while tick() - started < timeout do
        local buttons = getVisibleDialogueButtons()
        if #buttons > 0 then
            return buttons
        end
        task.wait(fastMode and 0.02 or 0.1)
    end

    return {}
end

local function chooseBestSellButton(buttons)
    local bestEntry = nil
    local bestScore = -math.huge

    for _, entry in ipairs(buttons) do
        local score = scoreSellOption(entry)
        if score > bestScore then
            bestScore = score
            bestEntry = entry
        end
    end

    if bestScore <= 0 then
        return nil, bestScore
    end

    return bestEntry, bestScore
end

local function findMerchantPrompt()
    -- Known/new dialogue storage path first.
    local dlgFolder = ReplicatedStorage:FindFirstChild("Dialogue")
    if dlgFolder then
        local merchant = dlgFolder:FindFirstChild("Merchant", true)
        if merchant then
            local prompt = merchant:FindFirstChildWhichIsA("ProximityPrompt", true)
            if prompt then return prompt end
        end
    end

    -- Search models/folders whose ancestry identifies the Merchant.
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") then
            local parent = obj.Parent
            local matchedMerchant = false
            local depth = 0
            while parent and parent ~= workspace and depth < 6 do
                if tostring(parent.Name):lower():find("merchant", 1, true) then
                    matchedMerchant = true
                    break
                end
                parent = parent.Parent
                depth = depth + 1
            end

            local objectText = normalizeText(obj.ObjectText)
            local actionText = normalizeText(obj.ActionText)
            if matchedMerchant or objectText:find("merchant", 1, true) or actionText:find("merchant", 1, true) then
                return obj
            end
        end
    end

    return nil
end

local function closeDialogueIfOpen()
    local dlg = getDialogueGui()
    if not dlg then return end

    -- Prefer a harmless close/cancel button after a failed attempt.
    local buttons = getVisibleDialogueButtons()
    for _, entry in ipairs(buttons) do
        local t = entry.Normalized
        if t:find("leave", 1, true) or t:find("cancel", 1, true)
            or t:find("nevermind", 1, true) or t:find("never mind", 1, true)
            or t:find("goodbye", 1, true) or t:find("exit", 1, true) then
            clickButton(entry.Button)
            task.wait(0.2)
            return
        end
    end
end

-- Drives the current Merchant dialogue dynamically until the item count drops.
-- Returns true if at least one item was sold.
local function runMerchantSellDialogue(itemName, beforeCount, fastMode)
    local lastOptions = ""
    local repeatedSameState = 0
    local stepDelay = fastMode and 0.06 or 0.5

    for step = 1, 7 do
        if Inventory:Count(itemName) < beforeCount then
            return true
        end

        local timeout
        if fastMode then
            timeout = step == 1 and 0.9 or 0.65
        else
            timeout = step == 1 and 3 or 2
        end

        local buttons = waitForDialogueButtons(timeout, fastMode)
        if #buttons == 0 then
            task.wait(fastMode and 0.08 or 0.35)
            if Inventory:Count(itemName) < beforeCount then
                return true
            end
            moduleLog("WARN", "[Inventory][Dialogue] No visible dialogue options at step " .. tostring(step) .. ".")
            return false
        end

        if fastMode then
            suppressDialogueRendering()
        end

        local description = describeButtons(buttons)
        moduleLog("INFO", "[Inventory][Dialogue] Step " .. tostring(step) .. " options: " .. description)

        if description == lastOptions then
            repeatedSameState = repeatedSameState + 1
        else
            repeatedSameState = 0
            lastOptions = description
        end

        if repeatedSameState >= 2 then
            moduleLog("WARN", "[Inventory][Dialogue] Dialogue did not advance. Options: " .. description)
            return false
        end

        local chosen, score = chooseBestSellButton(buttons)
        if not chosen then
            moduleLog("WARN", "[Inventory][Dialogue] Could not identify a sell option. Options: " .. description)
            return false
        end

        moduleLog("INFO", "[Inventory][Dialogue] " .. (fastMode and "Fast-clicking: " or "Clicking: ")
            .. tostring(chosen.Text) .. " (score " .. tostring(score) .. ")")

        local clicked
        if fastMode then
            clicked = fastClickButton(chosen.Button)
        else
            clicked = clickButton(chosen.Button)
        end

        if not clicked then
            moduleLog("WARN", "[Inventory][Dialogue] Failed to activate option: " .. tostring(chosen.Text))
            return false
        end

        task.wait(stepDelay)
    end

    return Inventory:Count(itemName) < beforeCount
end

local equipSellTool

-- =====================
-- INTERNAL / FALLBACK SELLING
-- YBA 1.7974+ Merchant option callbacks (ClientFunctions:2063) only write
-- the selected option name into callback upvalue #1.  Writing that upvalue
-- directly advances the dialogue without firesignal/VIM clicks.
-- =====================

local _env = (getgenv and getgenv()) or _G
local _rawGetConnections = rawget(_env, "getconnections") or getconnections
local _rawSetupvalue = rawget(_env, "setupvalue") or setupvalue
local _rawGetUpvalue = rawget(_env, "getupvalue") or getupvalue
local _rawGetGC = rawget(_env, "getgc") or getgc
local _rawGetConstants = rawget(_env, "getconstants") or getconstants
local _rawSetConstant = rawget(_env, "setconstant") or setconstant
local _rawFireSignal = rawget(_env, "firesignal") or firesignal

if debug then
    if type(_rawSetupvalue) ~= "function" then _rawSetupvalue = debug.setupvalue end
    if type(_rawGetUpvalue) ~= "function" then _rawGetUpvalue = debug.getupvalue end
    if type(_rawGetConstants) ~= "function" then _rawGetConstants = debug.getconstants end
    if type(_rawSetConstant) ~= "function" then _rawSetConstant = debug.setconstant end
end

local _cachedDialogueType = nil
local FINAL_SMALL_CONSTANT_MAX = 2.0
-- Performance guardrails for Delta/mobile. The FINAL route stays fast, but avoids
-- full getgc scans and deep patch work every rendered frame.
local FINAL_FORCE_INTERVAL = 0.02
local FINAL_GC_RESCAN_INTERVAL = 0.035

-- Experimental compatibility guard for executors reporting themselves as Real Injector.
-- getgc(true) is a synchronous full heap scan and can freeze on some executors.
-- Keep Delta/other existing Zero Delay behavior unchanged until live logs confirm a fix.
local function identifySellExecutor()
    if type(identifyexecutor) ~= "function" then return "unknown" end
    local ok, name, version = pcall(identifyexecutor)
    if not ok then return "unknown" end
    return tostring(name or "unknown") .. (version and (" " .. tostring(version)) or "")
end

local SELL_EXECUTOR_NAME = identifySellExecutor()
local _realName = SELL_EXECUTOR_NAME:lower()
local SKIP_HEAVY_GC = _realName == "real"
    or _realName:match("^real[%s%-%_]") ~= nil
    or _realName:find("real injector", 1, true) ~= nil
    or _realName:find("realexecutor", 1, true) ~= nil

local function getIndexedUpvalue(fn, index)
    if type(_rawGetUpvalue) ~= "function" or type(fn) ~= "function" then
        return false, nil, nil
    end

    local packed = table.pack(pcall(_rawGetUpvalue, fn, index))
    if not packed[1] then return false, nil, nil end

    local returned = packed.n - 1
    if returned >= 2 and type(packed[2]) == "string" then
        return packed[2] ~= nil, packed[3], packed[2]
    elseif returned >= 1 then
        return packed[2] ~= nil, packed[2], nil
    end
    return false, nil, nil
end

local function functionSourceLine(fn)
    local source, line = nil, nil
    if debug and type(debug.info) == "function" and type(fn) == "function" then
        pcall(function()
            source = debug.info(fn, "s")
            line = debug.info(fn, "l")
        end)
    end
    return source, tonumber(line)
end

local function isClientFunctionsLine(fn, wantedLine)
    local source, line = functionSourceLine(fn)
    return line == wantedLine and type(source) == "string" and source:find("ClientFunctions", 1, true) ~= nil
end

local function findLiveDialogueType()
    if _cachedDialogueType and isClientFunctionsLine(_cachedDialogueType, 2035) then
        return _cachedDialogueType
    end
    if type(_rawGetGC) ~= "function" then return nil end

    local ok, objects = pcall(_rawGetGC, true)
    if not ok or type(objects) ~= "table" then return nil end

    local fallback = nil
    for _, obj in pairs(objects) do
        if type(obj) == "function" and isClientFunctionsLine(obj, 2035) then
            fallback = fallback or obj
            local exists, functionTable = getIndexedUpvalue(obj, 1)
            if exists and type(functionTable) == "table" and functionTable.DialogueType == obj then
                _cachedDialogueType = obj
                return obj
            end
        end
    end

    _cachedDialogueType = fallback
    return fallback
end

local function hasInternalDialogueStateSupport()
    return type(_rawGetConnections) == "function" and type(_rawSetupvalue) == "function"
end

local function hasFinalZeroDelaySupport()
    return not SKIP_HEAVY_GC
        and hasInternalDialogueStateSupport()
        and type(_rawGetUpvalue) == "function"
        and type(_rawGetGC) == "function"
end

local function optionNameForButton(btn)
    local node = btn
    for _ = 1, 5 do
        if not node then break end
        local name = tostring(node.Name or "")
        if name:match("^Option%d+$") then
            return name
        end
        node = node.Parent
    end
    return nil
end

local function getDialogueStateSignature()
    local buttons = getVisibleDialogueButtons()
    if #buttons == 0 then return "", buttons end

    local parts = {}
    for _, entry in ipairs(buttons) do
        local name = optionNameForButton(entry.Button) or "?"
        table.insert(parts, name .. "=" .. tostring(entry.Text))
    end
    table.sort(parts)
    return table.concat(parts, " | "), buttons
end

local function findDialogueButtonByOptionName(wantedName)
    for _, entry in ipairs(getVisibleDialogueButtons()) do
        if optionNameForButton(entry.Button) == wantedName then
            return entry.Button, entry
        end
    end
    return nil, nil
end

local function getMouseClickCallback(btn)
    if not btn or type(_rawGetConnections) ~= "function" then return nil end
    local ok, conns = pcall(_rawGetConnections, btn.MouseButton1Click)
    if not ok or type(conns) ~= "table" then return nil end

    for _, conn in pairs(conns) do
        local enabled = true
        pcall(function()
            if conn.Enabled ~= nil then enabled = conn.Enabled end
        end)
        if enabled then
            local fn = nil
            pcall(function() fn = conn.Function end)
            if type(fn) == "function" then return fn end
        end
    end
    return nil
end

local function injectDialogueOption(wantedName)
    local btn = findDialogueButtonByOptionName(wantedName)
    if not btn then
        return false, "option " .. tostring(wantedName) .. " not found"
    end

    local fn = getMouseClickCallback(btn)
    if type(fn) ~= "function" then
        return false, "MouseButton1Click callback unavailable"
    end

    local ok, err = pcall(_rawSetupvalue, fn, 1, wantedName)
    if not ok then return false, tostring(err) end
    task.wait()
    return true
end

local function waitForDialogueGuiHidden(timeout)
    local deadline = tick() + (timeout or 1.5)
    while tick() < deadline do
        local dlg = getDialogueGui()
        if dlg then
            suppressDialogueRendering()
            return dlg
        end
        task.wait()
    end
    return nil
end

-- ---------------------
-- FINAL ZERO-DELAY PATH
-- Proven in MerchantAnalyzer_FINAL at ~0.70s after Merchant opens.
-- ---------------------
local FINAL_DELAY_KEYS = {
    AnimateStepTime = true,
    AnimateYield = true,
    AnimateDelay = true,
    StepTime = true,
    TextDelay = true,
    CharacterDelay = true,
    TypeDelay = true,
}

local function newFinalState()
    return {
        fieldPatches = {}, fieldSeen = setmetatable({}, {__mode = "k"}),
        animatePatches = {}, animateSeen = setmetatable({}, {__mode = "k"}),
        upvaluePatches = {}, upvalueSeen = setmetatable({}, {__mode = "k"}),
        constantPatches = {}, constantSeen = setmetatable({}, {__mode = "k"}),
        richSeen = setmetatable({}, {__mode = "k"}),
        constantScanned = setmetatable({}, {__mode = "k"}),
        waitPatch = nil,
        active1982 = nil,
        lastGCScan = 0,
        clickContinue = nil,
        signalFires = 0,
        direct1982Calls = 0,
        richObjects = 0,
        constantsZeroed = 0,
        gcScans = 0,
    }
end

local function rememberField(state, tbl, key, originalValue)
    if type(tbl) ~= "table" then return end
    state.fieldSeen[tbl] = state.fieldSeen[tbl] or {}
    if state.fieldSeen[tbl][key] then return end
    state.fieldSeen[tbl][key] = true
    table.insert(state.fieldPatches, {tbl = tbl, key = key, value = originalValue})
end

local function rememberUpvalue(state, fn, index, originalValue)
    state.upvalueSeen[fn] = state.upvalueSeen[fn] or {}
    if state.upvalueSeen[fn][index] then return end
    state.upvalueSeen[fn][index] = true
    table.insert(state.upvaluePatches, {fn = fn, index = index, value = originalValue})
end

local function rememberConstant(state, fn, index, originalValue)
    state.constantSeen[fn] = state.constantSeen[fn] or {}
    if state.constantSeen[fn][index] then return end
    state.constantSeen[fn][index] = true
    table.insert(state.constantPatches, {fn = fn, index = index, value = originalValue})
end

local function zeroDelayFields(state, tbl, depth, seen)
    if type(tbl) ~= "table" then return end
    depth = depth or 0
    if depth > 2 then return end
    seen = seen or {}
    if seen[tbl] then return end
    seen[tbl] = true

    for key, value in pairs(tbl) do
        if FINAL_DELAY_KEYS[tostring(key)] and type(value) == "number" then
            rememberField(state, tbl, key, value)
            pcall(function() tbl[key] = 0 end)
        elseif type(value) == "table" then
            zeroDelayFields(state, value, depth + 1, seen)
        end
    end
end

local function patchRichObject(state, richObject)
    if type(richObject) ~= "table" then return end
    -- A RichText result is immutable enough for this dialogue stage. Re-walking
    -- the same nested table every force tick wastes CPU and causes mobile FPS drops.
    if state.richSeen[richObject] then return end
    state.richSeen[richObject] = true
    state.richObjects = state.richObjects + 1

    zeroDelayFields(state, richObject, 0, {})

    if richObject.Overflown ~= nil then
        rememberField(state, richObject, "Overflown", richObject.Overflown)
        pcall(function() richObject.Overflown = true end)
    end

    if richObject.OverflowPickupIndex ~= nil then
        local old = richObject.OverflowPickupIndex
        rememberField(state, richObject, "OverflowPickupIndex", old)
        local len = 9999
        pcall(function() len = math.max(9999, #(tostring(richObject.Text or "")) + 8) end)
        pcall(function() richObject.OverflowPickupIndex = len end)
    end

    if type(richObject.Animate) == "function" and not state.animateSeen[richObject] then
        state.animateSeen[richObject] = true
        table.insert(state.animatePatches, {tbl = richObject, value = richObject.Animate})
        pcall(function()
            richObject.Animate = function(...) return true end
        end)
    end
end

local function patchSmallConstants(state, fn)
    if type(_rawSetConstant) ~= "function" or type(_rawGetConstants) ~= "function" then return end
    if state.constantScanned[fn] then return end
    state.constantScanned[fn] = true
    local ok, constants = pcall(_rawGetConstants, fn)
    if not ok or type(constants) ~= "table" then return end

    for index, value in pairs(constants) do
        if type(index) == "number" and type(value) == "number"
            and value > 0 and value <= FINAL_SMALL_CONSTANT_MAX then
            rememberConstant(state, fn, index, value)
            if pcall(_rawSetConstant, fn, index, 0) then
                state.constantsZeroed = state.constantsZeroed + 1
            end
        end
    end
end

local function installFastDialogueWait(state)
    local fn = findLiveDialogueType()
    if type(fn) ~= "function" then return false end

    local exists, originalWait = getIndexedUpvalue(fn, 2)
    if not exists or type(originalWait) ~= "function" then return false end

    local fastWait = function(_)
        return task.wait()
    end
    local ok = pcall(_rawSetupvalue, fn, 2, fastWait)
    if not ok then return false end

    state.waitPatch = {fn = fn, value = originalWait}
    return true
end

local function findClickContinue(dialogueGui)
    if not dialogueGui then return nil end
    local frame = dialogueGui:FindFirstChild("Frame") or dialogueGui:FindFirstChildWhichIsA("Frame")
    if not frame then return nil end

    local direct = frame:FindFirstChild("ClickContinue", true)
    if direct and direct:IsA("GuiButton") then return direct end

    for _, obj in ipairs(frame:GetDescendants()) do
        if obj:IsA("GuiButton") then
            local lowered = tostring(obj.Name):lower()
            if lowered:find("continue", 1, true) then return obj end
        end
    end
    return nil
end

local function fireButtonSignal(button, state)
    if not button then return false end
    local signal = nil
    pcall(function() signal = button.MouseButton1Click end)
    if not signal then pcall(function() signal = button.Activated end) end
    if not signal then return false end

    if type(_rawFireSignal) == "function" and pcall(_rawFireSignal, signal) then
        state.signalFires = state.signalFires + 1
        return true
    end

    if type(_rawGetConnections) == "function" then
        local ok, conns = pcall(_rawGetConnections, signal)
        if ok and type(conns) == "table" then
            for _, conn in pairs(conns) do
                local fn = nil
                pcall(function() fn = conn.Function end)
                if type(fn) == "function" and pcall(fn) then return true end
            end
        end
    end
    return false
end

local function findFresh1982Closure(state)
    if type(_rawGetGC) ~= "function" then return nil end

    -- Reuse the current stage closure. getgc(true) is one of the most expensive
    -- executor operations here, so only scan again after the stage changes or
    -- when no usable closure has been discovered yet.
    if state and type(state.active1982) == "function" then
        return state.active1982
    end

    local now = tick()
    if state and (now - (state.lastGCScan or 0)) < FINAL_GC_RESCAN_INTERVAL then
        return nil
    end
    if state then
        state.lastGCScan = now
        state.gcScans = (state.gcScans or 0) + 1
    end

    local ok, objects = pcall(_rawGetGC, true)
    if not ok or type(objects) ~= "table" then return nil end

    local best, fallback = nil, nil
    local bestTimestamp = -math.huge

    for _, obj in pairs(objects) do
        if type(obj) == "function" and isClientFunctionsLine(obj, 1982) then
            fallback = fallback or obj
            local exists, timestamp = getIndexedUpvalue(obj, 1)
            if exists and type(timestamp) == "number" and timestamp > bestTimestamp then
                bestTimestamp = timestamp
                best = obj
            end
        end
    end

    local found = best or fallback
    if state then state.active1982 = found end
    return found
end

local function patchAndInvoke1982(state)
    local fn = findFresh1982Closure(state)
    if type(fn) ~= "function" then return false end

    local hasTimestamp, timestamp = getIndexedUpvalue(fn, 1)
    if hasTimestamp and type(timestamp) == "number" then
        rememberUpvalue(state, fn, 1, timestamp)
        pcall(_rawSetupvalue, fn, 1, -1e9)
    end

    local hasRich, richObject = getIndexedUpvalue(fn, 4)
    if hasRich and type(richObject) == "table" then
        patchRichObject(state, richObject)
    end

    patchSmallConstants(state, fn)
    pcall(fn)
    state.direct1982Calls = state.direct1982Calls + 1
    return true
end

local function forceDialogueAdvance(dialogueGui, state)
    if not dialogueGui then return end
    suppressDialogueRendering()

    local clickContinue = state.clickContinue
    if not clickContinue or not clickContinue.Parent then
        clickContinue = findClickContinue(dialogueGui)
        state.clickContinue = clickContinue
    end
    if clickContinue then fireButtonSignal(clickContinue, state) end
    patchAndInvoke1982(state)
end

local function waitForFinalStage(previousSignature, timeout, state)
    local deadline = tick() + (timeout or 1.35)
    local loops = 0

    while tick() < deadline do
        loops = loops + 1
        local gui = getDialogueGui()
        if gui then
            suppressDialogueRendering()
            local sig = select(1, getDialogueStateSignature())
            if sig ~= "" and sig ~= previousSignature then
                return gui, sig, loops
            end
            forceDialogueAdvance(gui, state)
        end
        task.wait(FINAL_FORCE_INTERVAL)
    end
    return nil, nil, loops
end

local function restoreFinalState(state)
    for i = #state.animatePatches, 1, -1 do
        local patch = state.animatePatches[i]
        pcall(function() patch.tbl.Animate = patch.value end)
    end
    for i = #state.fieldPatches, 1, -1 do
        local patch = state.fieldPatches[i]
        pcall(function() patch.tbl[patch.key] = patch.value end)
    end
    if type(_rawSetConstant) == "function" then
        for i = #state.constantPatches, 1, -1 do
            local patch = state.constantPatches[i]
            pcall(_rawSetConstant, patch.fn, patch.index, patch.value)
        end
    end
    for i = #state.upvaluePatches, 1, -1 do
        local patch = state.upvaluePatches[i]
        pcall(_rawSetupvalue, patch.fn, patch.index, patch.value)
    end
    if state.waitPatch then
        pcall(_rawSetupvalue, state.waitPatch.fn, 2, state.waitPatch.value)
    end
end

-- Proven current route:
--   Merchant prompt -> force ClickContinue/1982 -> Option1 -> Option1 -> Option6.
-- The visible GUI stays hidden. On Delta this completed in ~0.70s in testing.
local function tryFinalMerchantSell(itemName, merchantPrompt)
    if not hasFinalZeroDelaySupport() then
        return false, 0, "FINAL APIs unsupported"
    end

    local before = Inventory:Count(itemName)
    if before <= 0 then return true, 0 end

    local tool = equipSellTool(itemName)
    if not tool then return false, 0, "could not equip item" end

    -- Important: the Merchant validates that the Tool is actually held.
    local char = Player.Character
    local equipDeadline = tick() + 0.35
    while tick() < equipDeadline and tool.Parent ~= char do
        task.wait()
    end
    if tool.Parent ~= char then
        return false, 0, "item was not held by character"
    end
    task.wait(0.08)

    closeDialogueIfOpen()
    restoreDialogueRendering()

    local state = newFinalState()
    local startedAt = tick()
    installFastDialogueWait(state)

    local okRun, soldAmount, reason = xpcall(function()
        local opened = pcall(function() fireproximityprompt(merchantPrompt) end)
        if not opened then return 0, "Merchant prompt failed" end

        if not waitForDialogueGuiHidden(1.0) then
            return 0, "DialogueGui did not appear"
        end

        local desired = {"Option1", "Option1", "Option6"}
        local previousSignature = nil

        for stage, optionName in ipairs(desired) do
            local _, signature, loops = waitForFinalStage(previousSignature, 1.35, state)
            if not signature then
                return 0, "stage " .. tostring(stage) .. " timed out"
            end

            local selected, selectReason = injectDialogueOption(optionName)
            if not selected then
                return 0, "stage " .. tostring(stage) .. " injection failed: " .. tostring(selectReason)
            end
            previousSignature = signature

            -- The next dialogue page creates a new line-1982 closure. Drop only
            -- this tiny cache so the next stage performs one fresh GC discovery.
            state.active1982 = nil
            state.lastGCScan = 0
        end

        local verifyDeadline = tick() + 0.55
        while tick() < verifyDeadline do
            local now = Inventory:Count(itemName)
            if now < before then
                task.wait(0.03)
                return before - Inventory:Count(itemName), nil
            end
            task.wait(0.02)
        end

        return 0, "dialogue completed but inventory did not change"
    end, function(err)
        return tostring(err)
    end)

    restoreFinalState(state)
    closeDialogueIfOpen()
    restoreDialogueRendering()

    if not okRun then
        return false, 0, soldAmount
    end

    if soldAmount and soldAmount > 0 then
        moduleLog("INFO", string.format(
            "[Inventory][ZeroDelay] ✅ Sold %dx %s in %.3fs | signals=%d direct1982=%d rich=%d constants=%d gcScans=%d",
            soldAmount, itemName, tick() - startedAt, state.signalFires, state.direct1982Calls,
            state.richObjects, state.constantsZeroed, state.gcScans or 0
        ))
        return true, soldAmount
    end

    return false, 0, reason or "no progress"
end

-- Original internal state route retained as the first compatibility fallback.
local function tryInternalMerchantSell(itemName, merchantPrompt)
    if not hasInternalDialogueStateSupport() then
        return false, 0, "setupvalue/getconnections unsupported"
    end

    local before = Inventory:Count(itemName)
    if before <= 0 then return true, 0 end

    local tool = equipSellTool(itemName)
    if not tool then return false, 0, "could not equip item" end

    closeDialogueIfOpen()
    restoreDialogueRendering()

    local opened = pcall(function() fireproximityprompt(merchantPrompt) end)
    if not opened then return false, 0, "Merchant prompt failed" end

    if not waitForDialogueGuiHidden(1.8) then
        return false, 0, "DialogueGui did not appear"
    end

    local desired = {"Option1", "Option1", "Option6"}
    local previousSignature = nil

    for stage, optionName in ipairs(desired) do
        local deadline = tick() + (stage == 1 and 3.0 or 1.2)
        local sig = nil
        while tick() < deadline do
            suppressDialogueRendering()
            local current = select(1, getDialogueStateSignature())
            if current ~= "" and current ~= previousSignature then
                sig = current
                break
            end
            task.wait(0.01)
        end

        if not sig then
            restoreDialogueRendering()
            return false, 0, "stage " .. tostring(stage) .. " timed out"
        end

        local ok, reason = injectDialogueOption(optionName)
        if not ok then
            restoreDialogueRendering()
            return false, 0, "stage " .. tostring(stage) .. " injection failed: " .. tostring(reason)
        end
        previousSignature = sig
    end

    local deadline = tick() + 0.8
    while tick() < deadline do
        local now = Inventory:Count(itemName)
        if now < before then
            task.wait(0.05)
            local final = Inventory:Count(itemName)
            closeDialogueIfOpen()
            restoreDialogueRendering()
            return true, before - final
        end
        task.wait(0.02)
    end

    closeDialogueIfOpen()
    restoreDialogueRendering()
    return false, 0, "dialogue advanced but inventory did not change"
end

local DIRECT_SELL_ARGS = {
    NPC = "Merchant",
    Dialogue = "Dialogue5",
    Option = "Option1",
}

local function getCharacterRemoteEvent()
    local char = Player.Character
    return char and char:FindFirstChild("RemoteEvent") or nil
end

equipSellTool = function(itemName)
    local char = Player.Character
    local hum = char and char:FindFirstChildWhichIsA("Humanoid")
    if not hum then return nil end

    local tool = Player.Backpack:FindFirstChild(itemName)
    if not tool and char then
        tool = char:FindFirstChild(itemName)
    end
    if not tool then return nil end

    if tool.Parent == Player.Backpack then
        local ok = pcall(function() hum:EquipTool(tool) end)
        if not ok then return nil end
        task.wait(0.08)
    end

    local deadline = tick() + 0.35
    while tool.Parent ~= char and tick() < deadline do
        task.wait()
    end
    if tool.Parent ~= char then return nil end

    return tool
end

-- Attempts to sell the equipped item without ever opening Merchant UI.
-- Returns:
--   true, soldAmount   -> direct server call worked
--   false, 0           -> no inventory progress; caller should use UI fallback
local function tryDirectMerchantSell(itemName)
    local before = Inventory:Count(itemName)
    if before <= 0 then return true, 0 end

    local tool = equipSellTool(itemName)
    if not tool then
        return false, 0
    end

    local remoteEvent = getCharacterRemoteEvent()
    if not remoteEvent then
        moduleLog("WARN", "[Inventory][DirectSell] Character RemoteEvent not found.")
        return false, 0
    end

    -- The pre-1.7974 Merchant used this exact action. Some current YBA systems
    -- still keep server compatibility even though the visible dialogue changed.
    -- Try twice only when the first packet makes no progress, then stop and let
    -- the new dialogue fallback handle it.
    for attempt = 1, 2 do
        local fired = pcall(function()
            remoteEvent:FireServer("EndDialogue", {
                NPC = DIRECT_SELL_ARGS.NPC,
                Dialogue = DIRECT_SELL_ARGS.Dialogue,
                Option = DIRECT_SELL_ARGS.Option,
            })
        end)

        if not fired then
            return false, 0
        end

        local deadline = tick() + 0.35
        while tick() < deadline do
            local now = Inventory:Count(itemName)
            if now < before then
                -- Give the server one tiny replication window; on the old route
                -- a single call normally removes the whole stack immediately.
                task.wait(0.04)
                local final = Inventory:Count(itemName)
                return true, before - final
            end
            task.wait(0.025)
        end
    end

    return false, 0
end

local function sellItemViaDialogueFallback(itemName, merchantPrompt, fastMode)
    local initialCount = Inventory:Count(itemName)
    local currentCount = initialCount
    local attempts = 0

    while currentCount > 0 and attempts < 4 and not Inventory:IsMoneyMaxed() do
        attempts = attempts + 1

        local tool = equipSellTool(itemName)
        if not tool then break end

        closeDialogueIfOpen()
        restoreDialogueRendering()

        if fastMode then
            suppressDialogueRendering()
        end

        local opened = pcall(function()
            fireproximityprompt(merchantPrompt)
        end)
        if not opened then
            moduleLog("WARN", "[Inventory] Could not trigger Merchant prompt for " .. itemName)
            break
        end

        task.wait(fastMode and 0.06 or 0.45)

        local beforeAttempt = Inventory:Count(itemName)
        local dialogueWorked = runMerchantSellDialogue(itemName, beforeAttempt, fastMode)
        task.wait(fastMode and 0.12 or 0.75)

        local afterAttempt = Inventory:Count(itemName)

        if fastMode and afterAttempt >= beforeAttempt then
            moduleLog("WARN", "[Inventory] Hidden dialogue made no progress for " .. itemName
                .. " — retrying with visible dialogue fallback.")
            restoreDialogueRendering()
            closeDialogueIfOpen()
            task.wait(0.15)

            local reopened = pcall(function()
                fireproximityprompt(merchantPrompt)
            end)
            if reopened then
                task.wait(0.4)
                dialogueWorked = runMerchantSellDialogue(itemName, beforeAttempt, false)
                task.wait(0.65)
                afterAttempt = Inventory:Count(itemName)
            end
        end

        if afterAttempt < beforeAttempt then
            moduleLog("INFO", "[Inventory] Sold " .. tostring(beforeAttempt - afterAttempt) .. "x " .. itemName
                .. " through dialogue fallback (remaining: " .. tostring(afterAttempt) .. ")")
        elseif dialogueWorked then
            local deadline = tick() + 1.5
            while tick() < deadline and Inventory:Count(itemName) >= beforeAttempt do
                task.wait(0.1)
            end
            afterAttempt = Inventory:Count(itemName)
        end

        currentCount = Inventory:Count(itemName)
        if currentCount >= beforeAttempt then
            moduleLog("WARN", "[Inventory] Merchant dialogue made no inventory progress for: " .. itemName)
            closeDialogueIfOpen()
            restoreDialogueRendering()
            break
        end

        closeDialogueIfOpen()
        restoreDialogueRendering()
        task.wait(fastMode and 0.06 or 0.25)
    end

    return Inventory:Count(itemName) < initialCount, initialCount - Inventory:Count(itemName)
end

-- =====================
-- SELL ALL
-- 1) Internal Merchant state injection: hidden Option1 > Option1 > Option6.
-- 2) If unsupported/failed, use adaptive DialogueGui fallback.
-- =====================
function Inventory:SellAll()
    if not _config:Get("FarmEnabled") then return end
    if self:IsMoneyMaxed() then
        moduleLog("INFO", "[Inventory] Money already maxed — skipping sell.")
        return
    end
    if not _config:Get("AutoSell") then
        moduleLog("INFO", "[Inventory] AutoSell disabled — skipping sell.")
        return
    end

    local sellItems = _config:GetSellItems()
    local toSell = {}

    for name, sell in pairs(sellItems) do
        if sell and self:Count(name) > 0 then
            table.insert(toSell, name)
        end
    end

    if #toSell == 0 then
        moduleLog("INFO", "[Inventory] No items to sell.")
        return
    end

    table.sort(toSell)
    moduleLog("INFO", "[Inventory] Selling " .. #toSell .. " item type(s)...")

    local soldTypes = 0
    local failedTypes = 0
    local merchantPrompt = findMerchantPrompt()
    local zeroDelaySupported = hasFinalZeroDelaySupport()
    local internalSupported = hasInternalDialogueStateSupport()
    local fallbackFastMode = hasInternalClickSupport()

    moduleLog("INFO", "[Inventory][Compatibility] Executor=" .. SELL_EXECUTOR_NAME
        .. " | ZeroDelay=" .. tostring(zeroDelaySupported)
        .. " | Internal=" .. tostring(internalSupported))
    if SKIP_HEAVY_GC then
        moduleLog("WARN", "[Inventory][Compatibility] Real Injector detected: skipping getgc(true) Zero Delay scans; trying existing hidden internal route.")
    end

    if zeroDelaySupported then
        moduleLog("INFO", "[Inventory][ZeroDelay] FINAL Merchant route available — target is sub-1s hidden selling.")
    elseif internalSupported then
        moduleLog("WARN", "[Inventory][ZeroDelay] FINAL APIs unavailable — using proven hidden internal Option1 > Option1 > Option6 fallback.")
    else
        moduleLog("WARN", "[Inventory][ZeroDelay] Internal APIs unavailable — using adaptive dialogue fallback.")
    end

    for _, itemName in ipairs(toSell) do
        if self:IsMoneyMaxed() then
            moduleLog("INFO", "[Inventory] Money reached max while selling — stopping.")
            break
        end

        local initialCount = self:Count(itemName)
        local finalCount = initialCount

        -- 1) FINAL zero-delay route discovered by MerchantAnalyzer_FINAL.
        if zeroDelaySupported and merchantPrompt then
            local ok, sold, reason = tryFinalMerchantSell(itemName, merchantPrompt)
            finalCount = self:Count(itemName)
            if ok and sold > 0 then
                moduleLog("INFO", "[Inventory][ZeroDelay] Sold " .. tostring(sold) .. "x " .. itemName
                    .. " with FINAL route (remaining: " .. tostring(finalCount) .. ").")
            else
                moduleLog("WARN", "[Inventory][ZeroDelay] FINAL route made no confirmed progress for " .. itemName
                    .. " — " .. tostring(reason or "unknown reason") .. ". Falling back.")
            end
        end

        -- 2) Proven internal Option1 -> Option1 -> Option6 route.
        if finalCount >= initialCount and internalSupported and merchantPrompt then
            local ok, sold, reason = tryInternalMerchantSell(itemName, merchantPrompt)
            finalCount = self:Count(itemName)
            if ok and sold > 0 then
                moduleLog("INFO", "[Inventory][InternalSell] Sold " .. tostring(sold) .. "x " .. itemName
                    .. " through hidden internal state fallback.")
            else
                moduleLog("WARN", "[Inventory][InternalSell] Fallback made no progress for " .. itemName
                    .. " — " .. tostring(reason or "unknown reason") .. ".")
            end
        end

        -- 3) Adaptive DialogueGui driver as final compatibility fallback.
        if finalCount >= initialCount then
            if merchantPrompt then
                local ok, sold = sellItemViaDialogueFallback(itemName, merchantPrompt, fallbackFastMode)
                finalCount = self:Count(itemName)
                if ok and sold > 0 then
                    moduleLog("INFO", "[Inventory] Dialogue fallback sold " .. tostring(sold) .. "x " .. itemName .. ".")
                end
            else
                moduleLog("WARN", "[Inventory] Merchant ProximityPrompt not found — cannot sell " .. itemName .. ".")
            end
        end

        finalCount = self:Count(itemName)
        if finalCount < initialCount then
            soldTypes = soldTypes + 1
            moduleLog("INFO", "[Inventory] ✅ Sold " .. tostring(initialCount - finalCount) .. "/" .. tostring(initialCount)
                .. " of " .. itemName)
        else
            failedTypes = failedTypes + 1
            moduleLog("WARN", "[Inventory] ❌ Failed to sell: " .. itemName)
        end

        task.wait(0.03)
    end

    closeDialogueIfOpen()
    restoreDialogueRendering()
    moduleLog("INFO", "[Inventory] SellAll done — Types sold: " .. soldTypes .. " | Failed: " .. failedTypes)
end

-- Prevent duplicate calls (e.g. overlapping cycles or manual triggers) from
-- manipulating the same Merchant dialogue concurrently.
-- The existing, proven selling implementation above is deliberately unchanged.
local _sellAllBusy = false
local _sellAllOriginal = Inventory.SellAll
function Inventory:SellAll()
    if _sellAllBusy then
        moduleLog("WARN", "[Inventory][SellGuard] Duplicate SellAll call skipped.")
        return false
    end

    _sellAllBusy = true
    local ok, result = pcall(_sellAllOriginal, self)
    _sellAllBusy = false

    if not ok then
        moduleLog("ERROR", "[Inventory][SellGuard] SellAll raised an error: " .. tostring(result))
        pcall(closeDialogueIfOpen)
        pcall(restoreDialogueRendering)
        return false
    end
    return true
end

-- =====================
-- BUY LUCKY ARROWS
-- =====================
function Inventory:BuyLucky()
    if not _config:Get("FarmEnabled") then return end
    if not _config:Get("BuyLucky")     then return end
    if self:Count("Lucky Arrow") >= LUCKY_STOP then return end

    local money = self:GetMoney()
    if money < 75000 then return end

    moduleLog("INFO", "[Inventory] Buying Lucky Arrows... ($" .. money .. ")")
    local attempts = 0

    while self:GetMoney() >= 75000 and attempts < 15 do
        pcall(function()
            local char = Player.Character
            if not char then return end
            local re = char:FindFirstChild("RemoteEvent")
            if not re then return end
            re:FireServer("PurchaseShopItem", { ItemName = "1x Lucky Arrow" })
        end)
        task.wait(1)
        attempts = attempts + 1

        local count = self:Count("Lucky Arrow")
        moduleLog("INFO", "[Inventory] Lucky Arrows: " .. count .. "/" .. LUCKY_STOP)

        if count >= LUCKY_STOP then
            moduleLog("INFO", "[Inventory] Reached " .. LUCKY_STOP .. " Lucky Arrows — stopping purchase (YBA bug).")
            break
        end
    end
end

-- =====================
-- STAND UTILITIES (used by CombatFarm)
-- =====================

-- Returns the name of the player's currently equipped stand
function Inventory:GetCurrentStand()
    if Player and Player.PlayerStats and Player.PlayerStats.Stand then
        return Player.PlayerStats.Stand.Value
    end
    return "None"
end

-- Returns true if the player has any stand equipped
function Inventory:HasStand()
    return self:GetCurrentStand() ~= "None"
end

-- Attempts to summon the stand if it is currently unsummoned.
-- Returns true if the stand was summoned by this call.
function Inventory:SummonStand()
    local char = Player.Character
    if not char then return false end

    local remoteFunc = char:FindFirstChild("RemoteFunction")
    if not remoteFunc then return false end

    local summoned = char:FindFirstChild("SummonedStand")
    if summoned and summoned.Value == false then
        remoteFunc:InvokeServer("ToggleStand", "Toggle")
        task.wait(0.3)
        return true
    end

    return false
end

return Inventory
