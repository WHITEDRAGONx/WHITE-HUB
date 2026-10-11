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

local function getSkin(char)
    local remote = char and char:FindFirstChild("RemoteFunction")
    if not remote then return nil, "Stand skin check unavailable: missing RemoteFunction" end
    local ok, result = pcall(function()
        return remote:InvokeServer("ReturnStandSkin", "Stand")
    end)
    if not ok or type(result) ~= "string" then
        return nil, "Stand skin check unavailable; preserving current Stand"
    end
    return result
end

-- Returns true only when a stand is safe to overwrite.
local function shouldReplace(stand, selected, char)
    if stand == nil then return false, "PlayerStats.Stand unavailable" end
    if stand == "None" then return false, nil end
    if stand == selected then return false, "Desired Stand found: " .. stand end
    local skin, reason = getSkin(char)
    if not skin then return false, reason end
    if skin ~= "None" and skin ~= "" then
        return false, "Skin detected (" .. skin .. "); preserved, stopping."
    end
    return true, nil
end

local function clickButton(button)
    if not button or not button:IsA("GuiButton") or not button.Visible then
        return false
    end
    -- Prefer a real input event on mobile/PC to calling unknown game scripts.
    local ok = pcall(function()
        local p, size = button.AbsolutePosition, button.AbsoluteSize
        local x, y = p.X + size.X / 2, p.Y + size.Y / 2
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
    end)
    return ok
end

local function dialogueButton()
    local gui = player and player:FindFirstChild("PlayerGui")
    local dialogue = gui and gui:FindFirstChild("DialogueGui")
    local frame = dialogue and dialogue:FindFirstChild("Frame")
    local options = frame and frame:FindFirstChild("Options")
    local first = options and options:FindFirstChild("Option1")
    if not first then return nil end
    if first:IsA("GuiButton") then return first end
    return first:FindFirstChildWhichIsA("GuiButton", true)
end

local function interact(token, name)
    local char, humanoid = getCharacter()
    if not char or not humanoid then return false, "Character unavailable" end
    local tool = getTool(name)
    if not tool then return false, "Out of " .. name end

    local equipped = pcall(function() humanoid:EquipTool(tool) end)
    if not equipped then return false, "Could not equip " .. name end
    if not waitActive(token, 0.2) then return false, "Stopped" end

    local gui = player:FindFirstChild("PlayerGui")
    local opened = false
    local started = os.clock()
    while active(token) and os.clock() - started < 6 do
        if gui and gui:FindFirstChild("DialogueGui") then
            opened = true
            break
        end
        pcall(function() tool:Activate() end)
        task.wait(0.4)
    end
    if not opened then
        return false, name .. " dialogue not detected; no further items consumed"
    end

    local clicked = false
    local begin = os.clock()
    while active(token) and os.clock() - begin < 5 do
        local btn = dialogueButton()
        if btn and clickButton(btn) then
            clicked = true
            break
        end
        task.wait(0.15)
    end
    if not clicked then
        return false, "Could not confirm " .. name .. " dialogue"
    end
    return true
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
    while active(token) do
        local char = getCharacter()
        local stand = readStand()
        local pity = readPity()
        if not char or not stand or pity == nil then
            if not waitActive(token, 1.0) then break end
            continue
        end

        local limit = tonumber(config:Get("StandFarmPityLimit")) or 0
        if limit > 0 and pity >= limit then
            stoppedOn = "Pity limit"
            log("INFO", ("Pity protection reached: %d/%d"):format(pity, limit))
            break
        end

        local replace, reason = shouldReplace(stand, selected, char)
        if reason then
            stoppedOn = reason
            log("INFO", reason)
            break
        end

        if replace then
            local ok, err = interact(token, "Rokakaka")
            if not ok then
                stoppedOn = err
                log("WARN", err)
                break
            end
            if not awaitStand(token, "None", 12) then
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
    config, inventory, logger = modules.Config, modules.Inventory, modules.RuntimeLog
    running, rolls, stoppedOn = false, 0, nil
    -- Never resume potentially destructive item consumption after reload.
    -- The owner must re-enable the beta manually in the current session.
    if config:Get("StandFarmEnabled") == true then
        config:Set("StandFarmEnabled", false)
    end
end

function StandFarm:Start()
    if running then return false, "Stand Farm already running" end
    local selected = config and config:Get("StandFarmTarget")
    if type(selected) ~= "string" or selected == "" then
        return false, "Choose target Stand first"
    end
    if config:Get("FarmEnabled") or config:Get("QuestFarmEnabled")
        or config:Get("NPCFarmEnabled") or config:Get("AutoPrestige") then
        return false, "Disable Item/Quest/NPC Farm and Auto Prestige first"
    end
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
    runToken = runToken + 1
    local token = runToken
    running, stoppedOn = true, nil
    config:Set("StandFarmEnabled", true)
    task.spawn(function()
        local ok, err = xpcall(function() loop(token) end, debug.traceback)
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
    log("INFO", "Stand Farm stopped by user")
    return true
end

function StandFarm:IsRunning()
    return running
end

function StandFarm:GetStatus()
    return { running = running, message = status,
        rolls = rolls, pity = readPity(), stand = readStand(), stop_reason = stoppedOn }
end

function StandFarm:Destroy()
    runToken = runToken + 1
    running = false
end

return StandFarm
