-- WHITE HUB V3 - StandFarm.lua - EXPERIMENTAL, DEV ONLY
-- Original implementation; no Xenon source, webhooks, raw Pastebin, or Inventory edits.
-- Never discard a stand when its skin cannot be safely determined.
local Players = game:GetService("Players")
local VirtualInputManager = game:GetService("VirtualInputManager")
local player = Players.LocalPlayer
local StandFarm = {}

local config, inventory, logger, movement
local running, runToken = false, 0
local status = "Idle"
local rolls, stoppedOn = 0, nil
local interactionBusy, pending = false, nil
local hiddenDialogues, selectedCallbacks = {}, {}
local callbackInFlight, skillInFlight = 0, 0
local preparedCharacter, respawnFrom, worthinessCharacter
local cleanupDialogue

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
        if node:IsA("ScreenGui") and not node.Enabled
            and hiddenDialogues[node] == nil then return false end
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
    local continueButton = gui:FindFirstChild("ClickContinue", true)
    local ready = resolveButton(continueButton, gui)
    if ready then return ready, "ClickContinue" end
    -- The Quest fast path also advances a hidden Continue during text animation.
    -- Accept it only when its own signal already has an actual bound handler.
    if continueButton and continueButton:IsA("GuiButton") and type(getconnections) == "function" then
        local ok, connections = pcall(getconnections, continueButton.MouseButton1Click)
        if ok and type(connections) == "table" then
            for _, connection in pairs(connections) do
                local fire, fn
                pcall(function() fire, fn = connection.Fire, connection.Function end)
                if type(fire) == "function" or type(fn) == "function" then
                    return continueButton, "ClickContinue"
                end
            end
        end
    end
    return nil, "ClickContinue"
end

local function stageSignature(gui, kind)
    if kind == "ClickContinue" then
        -- Animated body text is not a new Continue page; do not wait for its
        -- typewriter to settle before using the already-bound fast callback.
        return kind .. "|" .. tostring(gui:FindFirstChild("ClickContinue", true))
    end
    -- Only the option controls describe a choice page. Scanning the whole GUI
    -- every poll adds work and makes body typewriter updates delay selection.
    local options = gui:FindFirstChild("Options", true)
    local parts = {kind}
    for _, object in ipairs(options and options:GetDescendants() or {}) do
        if (object:IsA("TextLabel") or object:IsA("TextButton")) and visible(object, gui) then
            parts[#parts + 1] = object.Name .. "=" .. tostring(object.Text):sub(1, 200)
        end
    end
    return table.concat(parts, "|")
end

local function clickButton(token, button, gui)
    if not active(token) or not visible(button, gui) then return false end
    -- Rendered input fallback when fast dialogue APIs are unavailable.
    local ok = pcall(function()
        local p, size = button.AbsolutePosition, button.AbsoluteSize
        local x, y = p.X + size.X / 2, p.Y + size.Y / 2
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
        -- Always release the input; no yield between press/release.
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
    end)
    return ok
end

-- Adapted from the current Quest fast-dialogue path, scoped to the owned
-- consumable GUI. No GC scans, constant patches or Merchant state sharing.
local function indexedUpvalue(reader, fn, index)
    local values = table.pack(pcall(reader, fn, index))
    if not values[1] then return false end
    if values.n >= 3 and type(values[2]) == "string" then
        return true, values[3] -- standard debug API: name, value
    end
    if values.n >= 2 then return true, values[2] end -- executor API: value
    return false
end

local function hideOwnedDialogue(gui)
    if not gui or dialogueGui() ~= gui or not gui:IsA("ScreenGui") then return end
    if hiddenDialogues[gui] == nil then hiddenDialogues[gui] = gui.Enabled end
    pcall(function() gui.Enabled = false end)
end

cleanupDialogue = function(restoreSelection)
    if restoreSelection then
        for fn, record in pairs(selectedCallbacks) do
            if dialogueGui() == record.gui then
                local okAnchor, anchor = indexedUpvalue(record.reader, fn, 2)
                local okValue, value = indexedUpvalue(record.reader, fn, 1)
                if okAnchor and anchor == record.anchor and okValue and value == "Option1" then
                    pcall(record.setter, fn, 1, record.original)
                end
            end
        end
    end
    selectedCallbacks = {}
    for gui, enabled in pairs(hiddenDialogues) do
        pcall(function() gui.Enabled = enabled end)
    end
    hiddenDialogues = {}
end

local function selectFastOption(token, button, gui)
    local reader, setter
    if type(getupvalue) == "function" and type(setupvalue) == "function" then
        reader, setter = getupvalue, setupvalue
    elseif debug and type(debug.getupvalue) == "function" and type(debug.setupvalue) == "function" then
        reader, setter = debug.getupvalue, debug.setupvalue
    end
    if type(getconnections) ~= "function" or not reader or not setter then
        return false, "fast-option-unsupported"
    end
    local ok, connections = pcall(getconnections, button.MouseButton1Click)
    if not ok or type(connections) ~= "table" then return false, "no-connections" end
    for _, connection in pairs(connections) do
        local fn
        pcall(function() fn = connection.Function end)
        if type(fn) == "function" then
            local okAnchor, anchor = indexedUpvalue(reader, fn, 2)
            local okValue, value = indexedUpvalue(reader, fn, 1)
            -- Require the proven U[2] option container binding BEFORE writing.
            if okAnchor and typeof(anchor) == "Instance"
                and anchor == button.Parent and anchor.Name == "Option1"
                and okValue and (value == nil or type(value) == "string") then
                if not active(token) or dialogueGui() ~= gui then return false, "Stopped" end
                if not selectedCallbacks[fn] then
                    selectedCallbacks[fn] = {gui = gui, anchor = anchor, reader = reader,
                        setter = setter, original = value}
                end
                local written = pcall(setter, fn, 1, "Option1")
                local verified, selected = indexedUpvalue(reader, fn, 1)
                if written and verified and selected == "Option1" then
                    if not active(token) then cleanupDialogue(true); return false, "Stopped" end
                    hideOwnedDialogue(gui)
                    return true, "fast-option"
                end
            end
        end
    end
    return false, "callback-mismatch"
end

local function dispatchBoundSignal(token, button, gui)
    if callbackInFlight > 0 then return false, "callback-pending" end
    local signal = button.MouseButton1Click
    local call, method
    if type(getconnections) == "function" then
        local ok, connections = pcall(getconnections, signal)
        if ok and type(connections) == "table" then
            for _, connection in pairs(connections) do
                local fire, fn
                pcall(function() fire, fn = connection.Fire, connection.Function end)
                if type(fire) == "function" then
                    call, method = function() connection:Fire() end, "connection-fire"
                elseif type(fn) == "function" then
                    call, method = fn, "bound-callback"
                end
                if call then break end
            end
        end
    end
    if not call and type(firesignal) == "function" then
        call, method = function() firesignal(signal) end, "firesignal"
    end
    if not call then return false, "signal-unsupported" end
    if not active(token) or dialogueGui() ~= gui then return false, "Stopped" end
    hideOwnedDialogue(gui)
    callbackInFlight = callbackInFlight + 1
    -- A game handler may yield. Stop must not wait for it, and a second
    -- handler must not overlap while it is still in flight.
    task.spawn(function()
        if active(token) and dialogueGui() == gui then pcall(call) end
        callbackInFlight = callbackInFlight - 1
    end)
    return true, method
end

local function advanceDialogue(token, button, gui, kind, attempt, renderedReady)
    if not active(token) or dialogueGui() ~= gui then return false, "Stopped" end
    if not visible(button, gui) then
        if kind == "ClickContinue" then return dispatchBoundSignal(token, button, gui) end
        return false, "hidden-option"
    end
    local reason = "continue"
    if kind == "Option1" and attempt == 0 then
        local ok
        ok, reason = selectFastOption(token, button, gui)
        if ok then return true, reason end
    end
    if callbackInFlight > 0 then return false, "callback-pending" end
    -- Quest TEST ALL route: if selection did not advance, dispatch ONLY
    -- this button's actual connected handler, not an unrelated game closure.
    local ok, method = dispatchBoundSignal(token, button, gui)
    if ok then return true, method end
    if not active(token) or method == "callback-pending" then return false, method end
    -- Verified internal handlers need no rendered-page settling delay. Keep
    -- that delay for physical input, which depends on a stable visible button.
    if not renderedReady then return false, "render-wait" end
    cleanupDialogue(true) -- real input requires a rendered ScreenGui
    if clickButton(token, button, gui) then
        return true, "visible-fallback:" .. reason .. ":" .. method
    end
    return false, "input-unavailable:" .. reason .. ":" .. method
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
        cleanupDialogue(not ok)
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
    local lastClick, clicks, lastSignature = 0, 0, nil
    local stageAttempts = {}
    local callbackWaitLogged = false
    local firstInputAt, lastInputAt, statAt, closedAt
    local pageNumber = 0
    while active(token) and os.clock() - openedAt < 22 do
        local now = os.clock()
        local pollDelay = 0.1
        if ownedGui and not dialogueGui() and not closedAt then closedAt = now end
        if resultConfirmed(name) then
            if not statAt then statAt = now end
            if not dialogueGui() then
                log("INFO", name .. " confirmed by PlayerStats.Stand; clicks=" .. clicks)
                log("INFO", ("%s timing: inputs=%.2fs; stat=%.2fs; closed=%.2fs; after-input=%.2fs")
                    :format(name, firstInputAt and lastInputAt - firstInputAt or 0,
                        statAt - openedAt, (closedAt or now) - openedAt,
                        lastInputAt and statAt - lastInputAt or statAt - openedAt))
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
                    pageNumber = pageNumber + 1
                    signature, button, stableSince = nextSignature, nextButton, os.clock()
                end
                local pageKey = pageNumber .. "|" .. signature
                if button
                    and (callbackInFlight == 0 or kind == "Option1")
                    and (pageKey ~= lastSignature or os.clock() - lastClick >= 0.8) then
                    local attempts = stageAttempts[pageKey] or 0
                    if attempts >= 2 or clicks >= 12 then
                        return finish(false, name .. " dialogue stalled; clicks=" .. clicks .. "; result pending")
                    end
                    local advanced, method = advanceDialogue(token, button, gui, kind, attempts,
                        os.clock() - stableSince >= 0.1)
                    if not active(token) then return finish(false, "Stopped") end
                    if advanced then
                        clicks, stageAttempts[pageKey], lastClick = clicks + 1, attempts + 1, os.clock()
                        firstInputAt, lastInputAt = firstInputAt or lastClick, lastClick
                        lastSignature = pageKey
                        pollDelay = 0.03
                        log("INFO", name .. " dialogue " .. method .. " " .. kind .. " #" .. clicks .. "; result pending")
                    elseif method == "render-wait" then
                        pollDelay = 0.03
                    elseif method ~= "callback-pending" then
                        return finish(false, name .. " dialogue " .. method .. "; result pending")
                    end
                end
            elseif not ownedGui and os.clock() - openedAt >= 6 then
                return finish(false, name .. " dialogue not detected; no further items consumed")
            end
        end
        if callbackInFlight > 0 and not callbackWaitLogged and os.clock() - openedAt >= 2 then
            callbackWaitLogged = true
            log("INFO", name .. " dialogue handler pending; waiting for Option1/result, no extra signal fired")
        end
        -- Briefly watch for the next page after input; pending results and
        -- unchanged pages remain at 10 Hz throughout the item animation.
        task.wait(pollDelay)
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

-- Recovery belongs to this Stand worker; Item Farm is deliberately disabled.
-- Roka's None stat can replicate BEFORE the old Character dies/replaces.
local function prepareCharacter(token)
    if not movement then return false, "Movement module unavailable" end
    local started, stableSince, candidate = os.clock(), nil, nil
    local announced = false
    while active(token) and os.clock() - started < 20 do
        local char, humanoid = getCharacter()
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local remote = char and char:FindFirstChild("RemoteFunction")
        local bag = player and player:FindFirstChildOfClass("Backpack")
        local ready = char and humanoid and root and remote and bag
            and (not respawnFrom or char ~= respawnFrom)
            and callbackInFlight == 0 and skillInFlight == 0
        if ready then
            if char == preparedCharacter and not respawnFrom then return true end
            if candidate ~= char then candidate, stableSince = char, os.clock() end
            if os.clock() - stableSince >= 1.5 then
                if not active(token) then return false, "Stopped" end
                local ok, moved = pcall(function()
                    movement:SetNoclip(true)
                    movement:ClearFocus()
                    return movement:Teleport(CFrame.new(978, -42, -49))
                end)
                pcall(function() movement:SetNoclip(false) end)
                if not active(token) then return false, "Stopped" end
                if not ok or moved ~= true then return false, "Safe spot teleport not confirmed" end
                if player.Character ~= char or humanoid.Health <= 0 then
                    candidate, stableSince = nil, nil
                else
                    pcall(function() movement:FixCamera() end)
                    preparedCharacter, respawnFrom = char, nil
                    log("INFO", "Character ready; returned to safe spot before next consumable")
                    return true
                end
            end
        else
            candidate, stableSince = nil, nil
        end
        if not announced then
            announced = true
            log("INFO", respawnFrom and "Rokakaka confirmed; waiting for NEW Character/root/remotes"
                or "Waiting for ready Character/root/remotes before Stand Farm")
        end
        task.wait(0.1)
    end
    if not active(token) then return false, "Stopped" end
    return false, "Character recovery timed out after 20s; nothing else consumed"
end

local function prepareWorthiness(token)
    local char = getCharacter()
    if not char or char ~= preparedCharacter then return false, "Character changed before Worthiness" end
    if worthinessCharacter == char then return true end
    local remote = char:FindFirstChild("RemoteFunction")
    if not remote then return false, "Worthiness RemoteFunction unavailable" end
    if not active(token) then return false, "Stopped" end
    local finished, ok, result = false, false, nil
    skillInFlight = skillInFlight + 1
    log("INFO", "Preparing Worthiness for Arrow (single existing LearnSkill request)")
    task.spawn(function()
        if active(token) and player.Character == char then
            ok, result = pcall(function()
                return remote:InvokeServer("LearnSkill", {Skill = "Worthiness", SkillTreeType = "Character"})
            end)
        end
        finished = true
        skillInFlight = skillInFlight - 1
    end)
    local started = os.clock()
    while active(token) and not finished and os.clock() - started < 5 do task.wait(0.1) end
    if not active(token) then return false, "Stopped" end
    if not finished or not ok then return false, "Worthiness request failed/timed out; Arrow not activated" end
    if player.Character ~= char or getCharacter() ~= char then
        return false, "Character changed during Worthiness; Arrow not activated"
    end
    -- The game's return schema is not verified. Do not claim skill allocation
    -- succeeded from a nil/bool reply; the actual Arrow result remains required.
    worthinessCharacter = char
    log("INFO", "Worthiness request returned (" .. type(result) .. "); Arrow result still requires confirmation")
    return true
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
        local ready, readyReason = prepareCharacter(token)
        if not active(token) then break end
        if not ready then
            stoppedOn = readyReason
            log("WARN", readyReason)
            break
        end
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
            -- Require replacement, not just an early replicated None value.
            respawnFrom, preparedCharacter, worthinessCharacter = char, nil, nil
            log("INFO", "Rokakaka result confirmed; suspending consumption until respawn recovery")
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
            local skillReady, skillReason = prepareWorthiness(token)
            if not active(token) then break end
            if not skillReady then
                stoppedOn = skillReason
                log("WARN", skillReason)
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
    cleanupDialogue(true)
    runToken = runToken + 1
    config, inventory, logger, movement = modules.Config, modules.Inventory, modules.RuntimeLog, modules.Movement
    preparedCharacter, respawnFrom, worthinessCharacter = nil, nil, nil
    running, rolls, stoppedOn = false, 0, nil
    log("INFO", "Build SF-SPEED-20261011-R4; experimental dialogue timing, Roblox validation pending")
    status = "Idle"
    -- Never resume potentially destructive item consumption after reload.
    -- The owner must re-enable the beta manually in the current session.
    if config:Get("StandFarmEnabled") == true then
        config:Set("StandFarmEnabled", false)
    end
end

function StandFarm:Start()
    clearConfirmedPending()
    if running or interactionBusy or callbackInFlight > 0 or skillInFlight > 0 then
        return false, "Stand Farm already running or cancelling callbacks"
    end
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
    preparedCharacter, worthinessCharacter = nil, nil
    config:Set("StandFarmEnabled", true)
    task.spawn(function()
        local ok, err = xpcall(function() loop(token) end, debug.traceback)
        if not ok then cleanupDialogue(true); interactionBusy = false end
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
    cleanupDialogue(true)
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
    cleanupDialogue(true)
end

return StandFarm
