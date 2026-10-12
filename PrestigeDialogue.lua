-- Scoped reuse of WHITE HUB's verified Stand dialogue primitives; Merchant untouched.
local Driver={}
local player=game:GetService("Players").LocalPlayer
local VirtualInputManager=game:GetService("VirtualInputManager")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local hiddenDialogues,selectedCallbacks={},{}
local callbackInFlight=0
local cleanupDialogue,currentContext
local function active(ctx) return currentContext==ctx and ctx:Active() end
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
    local requestContext=token
    requestContext.calls=requestContext.calls+1
    -- A game handler may yield. Stop must not wait for it, and a second
    -- handler must not overlap while it is still in flight.
    task.spawn(function()
        if active(token) and dialogueGui() == gui then pcall(call) end
        callbackInFlight = callbackInFlight - 1
        requestContext.calls=requestContext.calls-1
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


function Driver:Init() end
function Driver:Restore() cleanupDialogue(true) end
function Driver:Drive(ctx,confirmed,label,timeout)
    if currentContext and currentContext~=ctx and callbackInFlight>0 then return false,"callback pending" end
    currentContext=ctx
    local deadline=os.clock()+(timeout or 12)
    local clicks,signature,attempts,lastAt=0,nil,0,0
    local seen=false; local ownedGui=nil
    while ctx:Active() and os.clock()<deadline do
        local gui=dialogueGui()
        local result=confirmed()
        if result and not gui and callbackInFlight==0 then cleanupDialogue(true); return true end
        if gui then
            if ownedGui and ownedGui~=gui then cleanupDialogue(true); return false,"dialogue replaced; result unresolved" end
            ownedGui=gui; seen=true
        end
        if gui and not result then
            local button,kind=dialogueButton(gui)
            if kind=="unsupported-options" then cleanupDialogue(true); return false,kind end
            if button then
                local stage=stageSignature(gui,kind)
                if stage~=signature then signature=stage; attempts=0; lastAt=0 end
                if callbackInFlight==0 and (attempts==0 or os.clock()-lastAt>=0.8) then
                    if attempts>=2 or clicks>=12 then cleanupDialogue(true); return false,"dialogue stalled" end
                    local ok,method=advanceDialogue(ctx,button,gui,kind,attempts,true)
                    if ok then
                        clicks=clicks+1; attempts=attempts+1; lastAt=os.clock()
                        ctx:Log("INFO",label.." input "..kind.." via "..tostring(method).."; result pending")
                    end
                end
            end
        elseif not gui and not seen and os.clock()>deadline-(timeout or 12)+5 then
            cleanupDialogue(true); return false,"dialogue not detected"
        end
        ctx:Wait(0.03)
    end
    cleanupDialogue(true)
    return false,ctx:Active() and "result timeout" or "cancelled"
end
local promptCache={}
local function findPrompt(npc)
    if promptCache[npc] and promptCache[npc].Parent then return promptCache[npc] end
    local best=nil
    local roots={workspace:FindFirstChild("Dialogues") or workspace}
    local definition=ReplicatedStorage:FindFirstChild("Dialogue") or ReplicatedStorage:FindFirstChild("NewDialogue")
    if definition then roots[#roots+1]=definition end
    for _,root in ipairs(roots) do
        for _,object in ipairs(root:GetDescendants()) do
            if object:IsA("ProximityPrompt") then
                local text=tostring(object.ObjectText or "")
                local parent=object.Parent
                local matched=text==npc
                while parent and parent~=root do
                    if parent.Name==npc then matched=true; break end
                    parent=parent.Parent
                end
                if matched then
                    if best and best~=object then return nil,"ambiguous NPC prompt" end
                    best=object
                end
            end
        end
        if best then break end
    end
    if best then promptCache[npc]=best end
    return best
end
function Driver:Run(ctx,npc,options,confirmed,label)
    if dialogueGui() or callbackInFlight>0 then return false,"existing dialogue/callback" end
    if type(npc)~="string" or type(confirmed)~="function" then return false,"invalid dialogue request" end
    for _,option in ipairs(options or {"Option1"}) do
        if option~="Option1" then return false,"unknown option sequence" end
    end
    if confirmed() then return true,"already reflected in player state" end
    local prompt,reason=findPrompt(npc)
    if reason then return false,reason end
    currentContext=ctx; ctx:Check()
    ctx.pending={name=label or npc,confirmed=confirmed}
    if prompt and type(fireproximityprompt)=="function" then
        fireproximityprompt(prompt)
    else
        local root=ReplicatedStorage:FindFirstChild("NewDialogue")
        local target=root and root:FindFirstChild(npc)
        if not target then ctx.pending=nil; return false,"NPC prompt/definition not found: "..npc end
        local char=player.Character
        ctx:Fire(char and char:FindFirstChild("RemoteEvent"),"PromptTriggered",target)
    end
    local ok,info=self:Drive(ctx,confirmed,label or npc,12)
    if ok then ctx.pending=nil end
    return ok,info
end
return Driver
