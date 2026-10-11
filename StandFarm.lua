-- WHITE HUB V3 - StandFarm.lua - EXPERIMENTAL, DEV ONLY
-- Original implementation; no Xenon source, webhooks, raw Pastebin, or Inventory edits.
-- Never discard a stand when its skin cannot be safely determined.
local Players = game:GetService("Players")
local VirtualInputManager = game:GetService("VirtualInputManager")
local player = Players.LocalPlayer
local StandFarm = {}

local config, inventory, logger
local running, runToken = false, 0
local status = "Idle"
local rolls, stoppedOn = 0, nil
local interactionBusy, pending = false, nil

local function log(level, message)
    status = message
    if logger and type(logger.Write) == "function" then
        pcall(logger.Write, logger, level, "StandFarm", "[StandFarm] " .. message)
    else
        print("[StandFarm] " .. message)
    end
end

local function active(token)
    return running and runToken == token and config
        and config:Get("StandFarmEnabled") == true
        and not config:Get("FarmEnabled") and not config:Get("QuestFarmEnabled")
        and not config:Get("NPCFarmEnabled") and not config:Get("AutoPrestige")
        and not config:Get("AutoSell")
end

local function waitActive(token, seconds)
    local started = os.clock()
    while active(token) and os.clock() - started < seconds do
        task.wait(math.min(0.2, seconds))
    end
    return active(token)
end

local function stats()
    return player and player:FindFirstChild("PlayerStats")
end

local function readStand()
    local s = stats()
    local val = s and s:FindFirstChild("Stand")
    return val and tostring(val.Value) or nil
end

local function readPity()
    local s = stats()
    local val = s and s:FindFirstChild("PityCount")
    return val and tonumber(val.Value) or nil
end

local function getCharacter()
    local char = player and player.Character
    if not char then return nil end
    local humanoid = char:FindFirstChildWhichIsA("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return nil end
    return char, humanoid
end

local function getTool(name)
    local char = player and player.Character
    local backpack = player and player:FindFirstChildOfClass("Backpack")
    local charTool = char and char:FindFirstChild(name)
    if charTool and charTool:IsA("Tool") then return charTool end
    local item = backpack and backpack:FindFirstChild(name)
    return item and item:IsA("Tool") and item or nil
end

local function getSkin(char, token)
    local remote = char and char:FindFirstChild("RemoteFunction")
    if not remote then return nil, "Stand skin check unavailable: missing RemoteFunction" end
    local finished, ok, result = false, false, nil
    task.spawn(function()
        ok, result = pcall(function()
            return remote:InvokeServer("ReturnStandSkin", "Stand")
        end)
        finished = true
    end)
    local started = os.clock()
    while not finished and os.clock() - started < 3 do
        if token and not active(token) then return nil, "Stopped" end
        task.wait(0.1)
    end
    if not finished or not ok or type(result) ~= "string" then
        return nil, "Stand skin check unavailable; preserving current Stand"
    end
    return result
end

-- Returns true only when a stand is safe to overwrite.
local function shouldReplace(stand, selected, char, token)
    if stand == nil then return false, "PlayerStats.Stand unavailable" end
    if stand == "None" then return false, nil end
    if stand == selected then return false, "Desired Stand found: " .. stand end
    local skin, reason = getSkin(char, token)
    if not skin then return false, reason end
    if readStand() ~= stand or getCharacter() ~= char then
        return false, "Stand/character changed during skin check; preserving result"
    end
    if skin == "" then return false, "Stand skin check inconclusive; preserving current Stand" end
    if skin ~= "None" and skin ~= "" then
        return false, "Skin detected (" .. skin .. "); preserved, stopping."
    end
    return true, nil
end

-- Inspect rendered ancestors; hidden template buttons must never be clicked.
local function visible(object, gui)
    if not object or not object:IsDescendantOf(gui) then return false end
    local node = object
    while node do
        if node:IsA("GuiObject") and not node.Visible then return false end
        if node:IsA("ScreenGui") and not node.Enabled then return false end
        if node == gui then return true end
        node = node.Parent
    end
    return false
end

local function dialogueGui()
    local gui = player and player:FindFirstChild("PlayerGui")
    return gui and gui:FindFirstChild("DialogueGui")
end

local function resolveButton(object, gui)
    if not object then return nil end
    local button = object:IsA("GuiButton") and object
        or object:FindFirstChildWhichIsA("GuiButton", true)
    if button and visible(button, gui) and button.AbsoluteSize.X > 0
        and button.AbsoluteSize.Y > 0 then return button end
    return nil
end

local function dialogueButton(gui)
    local options = gui:FindFirstChild("Options", true)
    local first = options and resolveButton(options:FindFirstChild("Option1"), gui)
    if first then return first, "Option1" end
    -- An unsupported visible option page must not be skipped by Continue.
    if options and visible(options, gui) then
        for _, object in ipairs(options:GetDescendants()) do
            if object:IsA("GuiButton") and visible(object, gui) then
                return nil, "unsupported-options"
            end
        end
    end
    return resolveButton(gui:FindFirstChild("ClickContinue", true), gui), "ClickContinue"
end

local function stageSignature(gui, kind)
    local parts = {kind}
    for _, object in ipairs(gui:GetDescendants()) do
        if (object:IsA("TextLabel") or object:IsA("TextButton")) and visible(object, gui) then
            parts[#parts + 1] = object.Name .. "=" .. tostring(object.Text):sub(1, 200)
        end
    end
    table.sort(parts)
    return table.concat(parts, "|")
end

local function clickButton(token, button, gui)
    if not active(token) or not visible(button, gui) then return false end
    -- Only visible input. Do not inspect or rewrite game callback upvalues.
    local ok = pcall(function()
        local p, size = button.AbsolutePosition, button.AbsoluteSize
        local x, y = p.X + size.X / 2, p.Y + size.Y / 2
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
        -- Always release the input; no yield between press/release.
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
    end)
    return ok
end

local function resultConfirmed(name)
    local stand = readStand()
    if name == "Rokakaka" then return stand == "None" end
    return stand ~= nil and stand ~= "None"
end

local function clearConfirmedPending()
    if pending and resultConfirmed(pending.name) and not dialogueGui() then
        pending = nil
    end
end

local function interact(token, name)
    if not active(token) then return false, "Stopped" end
    if interactionBusy or pending or dialogueGui() then
        return false, "Existing dialogue or pending result; close and verify it manually"
    end
    local char, humanoid = getCharacter()
    if not char or not humanoid then return false, "Character unavailable" end
    local before = readStand()
    if before == nil or (name == "Mysterious Arrow" and before ~= "None")
        or (name == "Rokakaka" and before == "None") then
        return false, "Stand state changed before " .. name
    end
    local tool = getTool(name)
    if not tool then return false, "Out of " .. name end
    local equipped = pcall(function() humanoid:EquipTool(tool) end)
    if not equipped then return false, "Could not equip " .. name end
    if not waitActive(token, 0.2) then return false, "Stopped" end
    if dialogueGui() then return false, "Another dialogue opened before activation" end
    if getCharacter() ~= char or readStand() ~= before then
        return false, "Stand/character changed before activation; nothing consumed"
    end
    local limit = tonumber(config:Get("StandFarmPityLimit")) or 0
    local pity = readPity()
    if pity == nil or (limit > 0 and pity >= limit) then
        return false, "Pity protection changed before activation; nothing consumed"
    end

    interactionBusy = true
    pending = {name = name}
    local function finish(ok, reason)
        interactionBusy = false
        -- Keep an uncertain consumption locked even after Stop/restart.
        clearConfirmedPending()
        return ok, reason
    end
    -- Exactly one activation per item. A missing GUI is not permission to retry.
    local activated = pcall(function() tool:Activate() end)
    if not activated then return finish(false, "Could not activate " .. name .. "; result pending") end
    local openedAt = os.clock()
    local ownedGui, button, signature, stableSince
    local lastClick, clicks = 0, 0
    local stageAttempts = {}
    while active(token) and os.clock() - openedAt < 22 do
        if resultConfirmed(name) then
            if not dialogueGui() then
                log("INFO", name .. " confirmed by PlayerStats.Stand; clicks=" .. clicks)
                return finish(true)
            end
            -- Result exists: never send another confirmation input.
        else
            local gui = dialogueGui()
            if gui then
                if ownedGui and ownedGui ~= gui then
                    return finish(false, "Dialogue replaced unexpectedly; result pending")
                end
                ownedGui = gui
                local nextButton, kind = dialogueButton(gui)
                local nextSignature = stageSignature(gui, kind)
                if nextSignature ~= signature or nextButton ~= button then
                    signature, button, stableSince = nextSignature, nextButton, os.clock()
                end
                if button and os.clock() - stableSince >= 0.3
                    and os.clock() - lastClick >= 0.8 then
                    local attempts = stageAttempts[signature] or 0
                    if attempts >= 2 or clicks >= 12 then
                        return finish(false, name .. " dialogue stalled; clicks=" .. clicks .. "; result pending")
                    end
                    if not clickButton(token, button, gui) then
                        return finish(false, name .. " visible input unavailable; result pending")
                    end
                    if not active(token) then return finish(false, "Stopped") end
                    clicks, stageAttempts[signature], lastClick = clicks + 1, attempts + 1, os.clock()
                    log("INFO", name .. " dialogue input " .. kind .. " #" .. clicks .. "; result pending")
                end
            elseif not ownedGui and os.clock() - openedAt >= 6 then
                return finish(false, name .. " dialogue not detected; no further items consumed")
            end
        end
        task.wait(0.1)
    end
    if not active(token) then return finish(false, "Stopped") end
    return finish(false, name .. " result/closed dialogue not confirmed within 22s; clicks=" .. clicks)
end

local function awaitStand(token, wanted, timeout)
    local started = os.clock()
    while active(token) and os.clock() - started < timeout do
        local current = readStand()
        if current == wanted then return true end
        task.wait(0.25)
    end
    return false
end

local function loop(token)
    local selected = config:Get("StandFarmTarget")
    if type(selected) ~= "string" or selected == "" then
        log("WARN", "Select a target Stand before enabling the farm")
        return
    end
    log("INFO", "Searching for " .. selected .. "; rare skins are always protected")
    local unavailableSince
    while active(token) do
        local char = getCharacter()
        local stand = readStand()
        local pity = readPity()
        if not char or not stand or pity == nil then
            unavailableSince = unavailableSince or os.clock()
            if os.clock() - unavailableSince >= 15 then
                stoppedOn = "Character/Stand/pity unavailable for 15s"
                log("WARN", stoppedOn)
                break
            end
            if not waitActive(token, 1.0) then break end
            continue
        end

        unavailableSince = nil
        local limit = tonumber(config:Get("StandFarmPityLimit")) or 0
        if limit > 0 and pity >= limit then
            stoppedOn = "Pity limit"
            log("INFO", ("Pity protection reached: %d/%d"):format(pity, limit))
            break
        end

        local replace, reason = shouldReplace(stand, selected, char, token)
        if not active(token) then break end
        if reason then
            stoppedOn = reason
            log("INFO", reason)
            break
        end

        if replace then
            local ok, err = interact(token, "Rokakaka")
            if not active(token) then break end
            if not ok then
                stoppedOn = err
                log("WARN", err)
                break
            end
            if not awaitStand(token, "None", 12) then
                if not active(token) then break end
                stoppedOn = "Rokakaka not confirmed"
                log("WARN", "Rokakaka did not clear the Stand; stopped to avoid duplicate use")
                break
            end
            if not waitActive(token, 0.6) then break end
        else
            local beforeStand = readStand()
            if beforeStand ~= "None" then
                -- Unexpected state: never use Arrow on a nonempty Stand slot.
                stoppedOn = "Unexpected Stand state"
                log("WARN", stoppedOn)
                break
            end
            if not getTool("Mysterious Arrow") then
                stoppedOn = "Out of Mysterious Arrow"
                log("WARN", stoppedOn)
                break
            end
            local ok, err = interact(token, "Mysterious Arrow")
            if not active(token) then break end
            if not ok then
                stoppedOn = err
                log("WARN", err)
                break
            end
            -- Some Arrow interactions respawn the character. Check the actual
            -- authoritative Stand stat; never count a dialog click as success.
            local started = os.clock()
            local obtained
            while active(token) and os.clock() - started < 15 do
                obtained = readStand()
                if obtained and obtained ~= "None" then break end
                task.wait(0.25)
            end
            if not active(token) then break end
            if not obtained or obtained == "None" then
                stoppedOn = "Arrow result unconfirmed"
                log("WARN", "Stand not obtained after Arrow; stopped safely")
                break
            end
            rolls = rolls + 1
            log("INFO", ("Arrow result %d: %s | pity=%s"):format(
                rolls, tostring(obtained), tostring(readPity())))
            if not waitActive(token, 0.8) then break end
        end
    end
    if runToken == token then
        running = false
        config:Set("StandFarmEnabled", false)
        if not stoppedOn then log("INFO", "Stand Farm stopped") end
    end
end

function StandFarm:Init(modules)
    runToken = runToken + 1
    config, inventory, logger = modules.Config, modules.Inventory, modules.RuntimeLog
    running, rolls, stoppedOn = false, 0, nil
    -- Never resume potentially destructive item consumption after reload.
    -- The owner must re-enable the beta manually in the current session.
    if config:Get("StandFarmEnabled") == true then
        config:Set("StandFarmEnabled", false)
    end
end

function StandFarm:Start()
    clearConfirmedPending()
    if running or interactionBusy then return false, "Stand Farm already running or cancelling" end
    if pending then return false, "Previous item result unresolved; verify manually before reloading" end
    if dialogueGui() then return false, "Close existing dialogue before starting Stand Farm" end
    local selected = config and config:Get("StandFarmTarget")
    if type(selected) ~= "string" or selected == "" then
        return false, "Choose target Stand first"
    end
    if config:Get("FarmEnabled") or config:Get("QuestFarmEnabled")
        or config:Get("NPCFarmEnabled") or config:Get("AutoPrestige") or config:Get("AutoSell") then
        return false, "Disable Item/Quest/NPC Farm, Auto Prestige and Auto Sell first"
    end
    local startToken = runToken
    local stand = readStand()
    if not stand then return false, "PlayerStats.Stand unavailable" end
    -- Inspect an already owned Stand before starting; never consume while
    -- skin verification is missing or indicates a skin.
    if stand ~= "None" then
        local char = getCharacter()
        if not char then return false, "Character not ready" end
        local _, reason = shouldReplace(stand, selected, char)
        if reason then return false, reason end
    end
    -- Skin lookup yields: a Stop or competing Start invalidates this request.
    if runToken ~= startToken or running then return false, "Start cancelled" end
    if dialogueGui() then return false, "Dialogue opened during skin check" end
    runToken = runToken + 1
    local token = runToken
    running, stoppedOn = true, nil
    config:Set("StandFarmEnabled", true)
    task.spawn(function()
        local ok, err = xpcall(function() loop(token) end, debug.traceback)
        if not ok then interactionBusy = false end
        if not ok and runToken == token then
            running = false
            config:Set("StandFarmEnabled", false)
            log("ERROR", "Stand Farm runtime failed: " .. tostring(err):sub(1, 240))
        end
    end)
    return true, "Stand Farm started"
end

function StandFarm:Stop()
    runToken = runToken + 1
    running = false
    if config then config:Set("StandFarmEnabled", false) end
    stoppedOn = "Stopped by user"
    log("INFO", "Stand Farm stopped by user")
    return true
end

function StandFarm:IsRunning()
    return running
end

function StandFarm:GetStatus()
    return { running = running, message = status,
        rolls = rolls, pity = readPity(), stand = readStand(), stop_reason = stoppedOn, pending_item = pending and pending.name or nil }
end

function StandFarm:Destroy()
    runToken = runToken + 1
    running = false
end

return StandFarm
