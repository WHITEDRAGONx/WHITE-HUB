-- =====================
-- UI.lua (WHITE HUB V3)
-- FUTURE GOLD UI: optimized black/white/bright-gold theme with lightweight glow.
-- =====================

local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local TextService      = game:GetService("TextService")
local HttpService      = game:GetService("HttpService")

local Player    = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local UI = {}

local UI_BUILD = "SILVER-V5-PRIVATE-DEV-20261018-FLOOR-AI-R6"
UI.Build = UI_BUILD

local THEME = {
    BG = Color3.fromRGB(10, 13, 18),
    BG2 = Color3.fromRGB(15, 19, 25),
    PANEL = Color3.fromRGB(20, 25, 32),
    PANEL2 = Color3.fromRGB(28, 35, 44),
    PANEL3 = Color3.fromRGB(36, 45, 56),
    WHITE = Color3.fromRGB(218, 226, 236),
    MUTED = Color3.fromRGB(170, 174, 184),
    MUTED2 = Color3.fromRGB(112, 116, 128),
    GOLD = Color3.fromRGB(145, 163, 184),
    GOLD_BRIGHT = Color3.fromRGB(188, 207, 228),
    GOLD_WHITE = Color3.fromRGB(222, 233, 245),
    GOLD_DARK = Color3.fromRGB(66, 83, 103),
    GOLD_EDGE = Color3.fromRGB(98, 120, 146),
    RED = Color3.fromRGB(135, 45, 52),
    RED_BRIGHT = Color3.fromRGB(215, 74, 82),
    GREEN = Color3.fromRGB(72, 170, 105),
}

local function addGradient(parent, c1, c2, rotation)
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, c1),
        ColorSequenceKeypoint.new(1, c2),
    })
    g.Rotation = rotation or 90
    g.Parent = parent
    return g
end

local function addStroke(parent, color, thickness, transparency)
    local s = Instance.new("UIStroke")
    s.Color = color or THEME.GOLD_EDGE
    s.Thickness = thickness or 1.1
    s.Transparency = transparency or 0
    s.Parent = parent
    return s
end

-- Only used on the main window + launcher. No RenderStepped loops.
local function pulseStroke(stroke, brightColor, dimColor)
    if not stroke then return end
    task.spawn(function()
        while stroke.Parent do
            local up = TweenService:Create(stroke, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
                Color = brightColor or THEME.GOLD_BRIGHT,
                Transparency = 0.02,
                Thickness = 1.8,
            })
            up:Play()
            up.Completed:Wait()
            if not stroke.Parent then break end
            local down = TweenService:Create(stroke, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
                Color = dimColor or THEME.GOLD_EDGE,
                Transparency = 0.28,
                Thickness = 1.15,
            })
            down:Play()
            down.Completed:Wait()
        end
    end)
end

local function styleActionButton(button, primary)
    button.BorderSizePixel = 0
    button.BackgroundColor3 = primary and THEME.GOLD or THEME.PANEL2
    button.TextColor3 = primary and THEME.BG or THEME.WHITE
    local corner = button:FindFirstChildOfClass("UICorner") or Instance.new("UICorner", button)
    corner.CornerRadius = UDim.new(0, 7)
    local stroke = button:FindFirstChildOfClass("UIStroke") or addStroke(button, primary and THEME.GOLD_BRIGHT or THEME.GOLD_EDGE, 1.1, primary and 0.05 or 0.25)
    stroke.Color = primary and THEME.GOLD_BRIGHT or THEME.GOLD_EDGE
    return stroke
end

local _config      = nil
local _farm        = nil
local _webhook     = nil
local _combatFarm  = nil
local _standFarm = nil
local _standV2UI = nil
local _prestigeRuntime = nil
local _compactUI = nil
local _settings = nil
local _community = nil
local _whiteAI = nil
local _halloween = nil
local _catalog, _choices = nil, nil
local _serverHop   = nil
local _runtimeLog   = nil

local toggleObjects = {}
local dropdownContainer = nil
local mainScreenGui = nil
local uiConnections = {}
local activeSkillCapture = nil

local function trackConnection(connection)
    if connection then table.insert(uiConnections, connection) end
    return connection
end

-- Dynamic NPC list (unique names)
local dynamicNPCList = {}
local npcDropdownRefresh = nil

function UI:Init(Modules)
    _config      = Modules.Config
    _farm        = Modules.Farm
    _webhook     = Modules.Webhook
    _combatFarm  = Modules.CombatFarm
    _standFarm   = Modules.StandFarm
    _standV2UI = Modules.StandV2UI
    _prestigeRuntime = Modules.AutoPrestigeRuntime
    _compactUI = Modules.UICompact
    _settings = Modules.Settings
    _community = Modules.CommunityFeatures
    _whiteAI = Modules.WhiteAI
    _halloween = Modules.HalloweenExchange
    _catalog, _choices = Modules.GameCatalog, Modules.ChoiceUI
    _serverHop   = Modules.ServerHop
    _runtimeLog  = Modules.RuntimeLog
end

local function stopPrestigeForSwitch(label)
    if not _prestigeRuntime then return true end
    _prestigeRuntime:Stop()
    if _prestigeRuntime:IsBusy() then
        UI:SetToggleValue(label,false)
        UI:ShowPopup("Auto Prestige result pending. Wait for confirmation before switching.",6)
        return false
    end
    return true
end

local function runtimeLog(level, message)
    if _runtimeLog and type(_runtimeLog.Write) == "function" then
        pcall(_runtimeLog.Write, _runtimeLog, level, "UI", message)
    end
end

local function copyToClipboard(text)
    if type(setclipboard) == "function" then
        local ok = pcall(setclipboard, text)
        if ok then return true end
    end
    if type(toclipboard) == "function" then
        local ok = pcall(toclipboard, text)
        if ok then return true end
    end
    if Clipboard and type(Clipboard.set) == "function" then
        local ok = pcall(function() Clipboard.set(text) end)
        if ok then return true end
    end
    return false
end

-- =====================
-- CREDITS POPUP
-- =====================
local function CreateCreditsPopup()
    local gui = Instance.new("ScreenGui")
    gui.Name = "WhiteHubCreditsPopup"
    gui.DisplayOrder = 30
    gui.Parent = PlayerGui
    gui.ResetOnSpawn = false

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 190, 0, 54)
    frame.Position = UDim2.new(0, -205, 1, -170)
    frame.BackgroundColor3 = THEME.PANEL
    frame.BorderSizePixel = 0
    frame.Parent = gui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)
    local fs = addStroke(frame, THEME.GOLD, 1.15, 0.12)
    addGradient(frame, THEME.PANEL2, THEME.BG2, 90)

    local accent = Instance.new("Frame")
    accent.Size = UDim2.new(0, 3, 1, -14)
    accent.Position = UDim2.new(0, 7, 0, 7)
    accent.BackgroundColor3 = THEME.GOLD_BRIGHT
    accent.BorderSizePixel = 0
    accent.Parent = frame
    Instance.new("UICorner", accent).CornerRadius = UDim.new(1, 0)

    local t1 = Instance.new("TextLabel", frame)
    t1.Size = UDim2.new(1, -24, 0, 26)
    t1.Position = UDim2.new(0, 17, 0, 5)
    t1.BackgroundTransparency = 1
    t1.Text = "WHITE HUB  //  V5"
    t1.TextColor3 = THEME.WHITE
    t1.TextSize = 15
    t1.Font = Enum.Font.GothamBold
    t1.TextXAlignment = Enum.TextXAlignment.Left

    local t2 = Instance.new("TextLabel", frame)
    t2.Size = UDim2.new(1, -24, 0, 17)
    t2.Position = UDim2.new(0, 17, 0, 30)
    t2.BackgroundTransparency = 1
    t2.Text = "SILVER • " .. UI_BUILD
    t2.TextColor3 = THEME.GOLD_BRIGHT
    t2.TextSize = 9
    t2.Font = Enum.Font.GothamMedium
    t2.TextXAlignment = Enum.TextXAlignment.Left

    TweenService:Create(frame, TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
        Position = UDim2.new(0, 10, 1, -170)
    }):Play()
    task.delay(4, function()
        if not frame.Parent then return end
        local t = TweenService:Create(frame, TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
            Position = UDim2.new(0, -205, 1, -170)
        })
        t:Play()
        t.Completed:Connect(function() if gui.Parent then gui:Destroy() end end)
    end)
end

-- =====================
-- UI HELPERS
-- =====================
local function AutoCanvas(scroll)
    local list = scroll:FindFirstChildOfClass("UIListLayout")
    if not list then return end
    local function update()
        scroll.CanvasSize = UDim2.new(0,0,0, list.AbsoluteContentSize.Y / (_compactUI and _compactUI:ScaleFor(scroll) or 1) + 10)
    end
    update()
    list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(update)
end

local function MakeSection(parent, text)
    local frame = Instance.new("Frame")
    frame.Name = "Section"
    frame.Size = UDim2.new(1, -4, 0, 20)
    frame.BackgroundColor3 = THEME.BG2
    frame.BorderSizePixel = 0
    frame.Parent = parent
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 7)
    local stroke = addStroke(frame, THEME.GOLD_EDGE, 1, 0.42)

    local accent = Instance.new("Frame")
    accent.Size = UDim2.new(0, 3, 0.58, 0)
    accent.Position = UDim2.new(0, 6, 0.21, 0)
    accent.BackgroundColor3 = THEME.GOLD_BRIGHT
    accent.BorderSizePixel = 0
    accent.Parent = frame
    Instance.new("UICorner", accent).CornerRadius = UDim.new(1, 0)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -18, 1, 0)
    lbl.Position = UDim2.new(0, 14, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = _compactUI and _compactUI:Caption(text) or text
    lbl.TextColor3 = THEME.GOLD_BRIGHT
    lbl.TextSize = 11
    lbl.Font = Enum.Font.GothamBold
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = frame
end

local function MakeToggle(parent, labelText, default, onChanged)
    local holder = Instance.new("Frame")
    holder.Name             = "ToggleRow"
    holder.Size             = UDim2.new(1,-4,0,28)
    holder.BackgroundColor3 = THEME.PANEL
    holder.BorderSizePixel  = 0
    holder.Parent           = parent
    Instance.new("UICorner", holder).CornerRadius = UDim.new(0,7)
    local stroke = Instance.new("UIStroke", holder)
    stroke.Color = THEME.GOLD_EDGE
    stroke.Transparency = 0.48
    stroke.Thickness = 1

    local lbl = Instance.new("TextLabel")
    lbl.Size             = UDim2.new(1,-58,1,0)
    lbl.Position         = UDim2.new(0,8,0,0)
    lbl.BackgroundTransparency = 1
    lbl.Text             = _compactUI and _compactUI:Caption(labelText) or labelText
    lbl.TextColor3       = THEME.WHITE
    lbl.TextScaled       = false
    lbl.TextSize         = 12
    lbl.TextTruncate     = Enum.TextTruncate.AtEnd
    lbl.Font             = Enum.Font.Gotham
    lbl.TextXAlignment   = Enum.TextXAlignment.Left
    lbl.Parent           = holder

    local state = { enabled = (default == nil) and true or default }

    local track = Instance.new("TextButton")
    track.Size             = UDim2.new(0,44,0,22)
    track.Position         = UDim2.new(1,-52,0.5,-11)
    track.BackgroundColor3 = state.enabled and THEME.GOLD or THEME.PANEL2
    track.Text             = ""
    track.BorderSizePixel  = 0
    track.Parent           = holder
    Instance.new("UICorner", track).CornerRadius = UDim.new(1,0)
    local trackStroke = addStroke(track, state.enabled and THEME.GOLD_BRIGHT or THEME.GOLD_EDGE, 1, state.enabled and 0.05 or 0.55)

    local circle = Instance.new("Frame")
    circle.Size             = UDim2.new(0,15,0,15)
    circle.Position         = state.enabled and UDim2.new(1,-18,0.5,-7.5) or UDim2.new(0,3,0.5,-7.5)
    circle.BackgroundColor3 = THEME.WHITE
    circle.BorderSizePixel  = 0
    circle.Parent           = track
    Instance.new("UICorner", circle).CornerRadius = UDim.new(1,0)

    local function render(animated)
        local bg = state.enabled and THEME.GOLD or THEME.PANEL2
        local pos = state.enabled and UDim2.new(1,-18,0.5,-7.5) or UDim2.new(0,3,0.5,-7.5)
        local strokeColor = state.enabled and THEME.GOLD_BRIGHT or THEME.GOLD_EDGE
        local strokeTransparency = state.enabled and 0.05 or 0.55
        if animated then
            TweenService:Create(track, TweenInfo.new(0.18), {BackgroundColor3 = bg}):Play()
            TweenService:Create(circle, TweenInfo.new(0.18), {Position = pos}):Play()
            TweenService:Create(trackStroke, TweenInfo.new(0.18), {Color = strokeColor, Transparency = strokeTransparency}):Play()
        else
            track.BackgroundColor3 = bg
            circle.Position = pos
            trackStroke.Color = strokeColor
            trackStroke.Transparency = strokeTransparency
        end
    end

    track.MouseButton1Click:Connect(function()
        state.enabled = not state.enabled
        render(true)
        onChanged(state.enabled)
    end)

    toggleObjects[labelText] = {
        holder = holder,
        track = track,
        circle = circle,
        state = state,
        render = render,
    }
end

function UI:AddLabel(parent, text)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1,-4,0,24)
    lbl.Position = UDim2.new(0,2,0,0)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.TextColor3 = THEME.WHITE
    lbl.TextSize = 11
    lbl.Font = Enum.Font.Gotham
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = parent
    return lbl
end

local function ensureDropdownContainer()
    if not dropdownContainer or not dropdownContainer.Parent then
        dropdownContainer = Instance.new("ScreenGui")
        dropdownContainer.Name = "DropdownContainer"
        dropdownContainer.DisplayOrder = 31
        dropdownContainer.ResetOnSpawn = false
        dropdownContainer.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        dropdownContainer.Parent = PlayerGui
    end
    return dropdownContainer
end

-- Styled dropdown with auto-close on selection (versão corrigida)
local function MakeStyledDropdown(parent, labelText, options, callback)
    local holder = Instance.new("Frame")
    holder.Name = "DropdownRow"
    holder.Size = UDim2.new(1,-4,0,30)
    holder.BackgroundColor3 = THEME.PANEL
    holder.BorderSizePixel = 0
    holder.Parent = parent
    Instance.new("UICorner", holder).CornerRadius = UDim.new(0,7)
    local stroke = Instance.new("UIStroke", holder)
    stroke.Color = THEME.GOLD_EDGE
    stroke.Thickness = 1.2

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.5,0,1,0)
    lbl.Position = UDim2.new(0,8,0,0)
    lbl.BackgroundTransparency = 1
    lbl.Text = _compactUI and _compactUI:Caption(labelText) or labelText
    lbl.TextColor3 = THEME.WHITE
    lbl.TextScaled = false
    lbl.TextSize = 12
    lbl.TextTruncate = Enum.TextTruncate.AtEnd
    lbl.Font = Enum.Font.Gotham
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = holder

    local dropdownBtn = Instance.new("TextButton")
    dropdownBtn.Size = UDim2.new(0.45,0,1,0)
    dropdownBtn.Position = UDim2.new(0.5,0,0,0)
    dropdownBtn.BackgroundColor3 = THEME.PANEL3
    dropdownBtn.BorderSizePixel = 0
    dropdownBtn.Text = options[1] or "None"
    dropdownBtn.TextColor3 = THEME.WHITE
    dropdownBtn.TextSize = 11
    dropdownBtn.TextTruncate = Enum.TextTruncate.AtEnd
    dropdownBtn.Font = Enum.Font.Gotham
    dropdownBtn.Parent = holder
    Instance.new("UICorner", dropdownBtn).CornerRadius = UDim.new(0,7)
    local btnStroke = Instance.new("UIStroke", dropdownBtn)
    btnStroke.Color = THEME.GOLD_DARK
    btnStroke.Thickness = 1.2

    local currentOptions = options
    local menu = nil
    local outsideConnection = nil

    local function hideMenu()
        if outsideConnection then
            outsideConnection:Disconnect()
            outsideConnection = nil
        end
        if menu then
            menu:Destroy()
            menu = nil
        end
    end

    local function showMenu()
        hideMenu()
        local container = ensureDropdownContainer()
        menu = Instance.new("ScrollingFrame")
        menu.BackgroundColor3 = THEME.PANEL2
        menu.BorderSizePixel = 0
        menu.ScrollBarThickness = 7
        menu.Active = true
        menu.ScrollingEnabled = true
        menu.ScrollingDirection = Enum.ScrollingDirection.Y
        menu.ScrollBarImageColor3 = THEME.GOLD
        menu.ZIndex = 20
        menu.Parent = container
        Instance.new("UICorner", menu).CornerRadius = UDim.new(0,7)
        local menuStroke = Instance.new("UIStroke", menu)
        menuStroke.Color = THEME.GOLD
        menuStroke.Thickness = 1.2

        local menuLayout = Instance.new("UIListLayout", menu)
        menuLayout.Padding = UDim.new(0,2)

        for _, opt in ipairs(currentOptions) do
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.new(1,-5,0,30)
            btn.BackgroundColor3 = THEME.PANEL3
            btn.Text = opt
            btn.TextColor3 = THEME.WHITE
            btn.TextSize = 14
            btn.Font = Enum.Font.Gotham
            btn.ZIndex = 21
            btn.Parent = menu
            Instance.new("UICorner", btn).CornerRadius = UDim.new(0,4)
            btn.MouseButton1Click:Connect(function()
                dropdownBtn.Text = opt
                callback(opt)
                hideMenu()
            end)
        end

        local count = #currentOptions
        local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
            or Vector2.new(720, 520)
        local height = math.min(math.max(count, 1)*32, math.max(100, viewport.Y*0.48), 280)
        local width = math.min(280, math.max(120, viewport.X-16))
        menu.Size = UDim2.fromOffset(width, height)
        menu.CanvasSize = UDim2.fromOffset(0, count*32)
        local btnAbsPos = dropdownBtn.AbsolutePosition
        local btnSize = dropdownBtn.AbsoluteSize
        -- Keep the full scrolling popup inside the display on mobile.
        local x = math.clamp(btnAbsPos.X, 8, math.max(8, viewport.X-width-8))
        local below = btnAbsPos.Y + btnSize.Y + 4
        local above = btnAbsPos.Y-height-4
        local y = below + height <= viewport.Y-8 and below
            or (above >= 8 and above or math.clamp(below,8,math.max(8,viewport.Y-height-8)))
        menu.Position = UDim2.fromOffset(x,y)

        outsideConnection = UserInputService.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
            task.wait()
            if not menu then return end
            local mousePos = UserInputService:GetMouseLocation()
            local p, s = menu.AbsolutePosition, menu.AbsoluteSize
            if mousePos.X < p.X or mousePos.X > p.X + s.X or mousePos.Y < p.Y or mousePos.Y > p.Y + s.Y then
                hideMenu()
            end
        end)
    end

    dropdownBtn.MouseButton1Click:Connect(function()
        if menu then hideMenu() else showMenu() end
    end)

    return dropdownBtn, function(newOptions)
        hideMenu()
        currentOptions = newOptions or {}
        if #currentOptions == 0 then
            dropdownBtn.Text = "None"
        elseif not table.find(currentOptions, dropdownBtn.Text) then
            dropdownBtn.Text = currentOptions[1]
        end
    end
end

function UI:ShowPopup(message, duration)
    duration = duration or 3
    local screenGui = PlayerGui:FindFirstChild("WhiteHubPopup")
    if not screenGui then
        screenGui = Instance.new("ScreenGui")
        screenGui.Name = "WhiteHubPopup"
        screenGui.DisplayOrder = 31
        screenGui.ResetOnSpawn = false
        screenGui.Parent = PlayerGui
    end

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 270, 0, 50)
    frame.Position = UDim2.new(1, -282, 1, -70)
    frame.BackgroundColor3 = THEME.PANEL
    frame.BackgroundTransparency = 0.03
    frame.BorderSizePixel = 0
    frame.Parent = screenGui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)
    addStroke(frame, THEME.GOLD, 1.15, 0.12)
    addGradient(frame, THEME.PANEL2, THEME.BG2, 90)

    local accent = Instance.new("Frame")
    accent.Size = UDim2.new(0, 3, 1, -12)
    accent.Position = UDim2.new(0, 7, 0, 6)
    accent.BackgroundColor3 = THEME.GOLD_BRIGHT
    accent.BorderSizePixel = 0
    accent.Parent = frame
    Instance.new("UICorner", accent).CornerRadius = UDim.new(1,0)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -22, 1, 0)
    label.Position = UDim2.new(0, 16, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = message
    label.TextColor3 = THEME.WHITE
    label.TextSize = 12
    label.Font = Enum.Font.GothamMedium
    label.TextWrapped = true
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame

    frame.Position = UDim2.new(1, 10, 1, -70)
    TweenService:Create(frame, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Position = UDim2.new(1,-282,1,-70)}):Play()
    task.delay(duration, function()
        if not frame.Parent then return end
        local t = TweenService:Create(frame, TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {Position = UDim2.new(1,10,1,-70), BackgroundTransparency = 1})
        t:Play()
        t.Completed:Connect(function() if frame.Parent then frame:Destroy() end end)
    end)
end

function UI:SetToggleValue(toggleName, value)
    local toggle = toggleObjects[toggleName]
    if toggle then
        toggle.state.enabled = value == true
        toggle.render(false)
        return true
    end
    warn("[UI] Toggle not found: " .. toggleName)
    return false
end

-- =====================
-- DYNAMIC NPC DETECTION (unique names, Xenon V5 style)
-- =====================
local function updateNPCList()
    local uniqueNames = {}
    local living = workspace:FindFirstChild("Living")
    if not living then
        dynamicNPCList = {}
        return dynamicNPCList
    end
    for _, obj in pairs(living:GetChildren()) do
        if obj:FindFirstChild("Spawn") then
            uniqueNames[obj.Name] = true
        end
    end
    local newList = {}
    for name in pairs(uniqueNames) do
        table.insert(newList, name)
    end
    table.sort(newList)
    dynamicNPCList = newList
    return newList
end

function UI:Create()
    self:Destroy()
    toggleObjects = {}
    runtimeLog("INFO", "UI build loaded: " .. UI_BUILD)

    for _, guiName in ipairs({"WhiteHubV3", "DropdownContainer", "WhiteHubCreditsPopup"}) do
        local old = PlayerGui:FindFirstChild(guiName)
        if old then old:Destroy() end
    end

    CreateCreditsPopup()

    -- Initial NPC scan
    updateNPCList()
    local living = workspace:FindFirstChild("Living")
    if living then
        trackConnection(living.ChildAdded:Connect(function(child)
            if child:FindFirstChild("Spawn") then
                updateNPCList()
                if npcDropdownRefresh then npcDropdownRefresh(dynamicNPCList) end
            end
        end))
        trackConnection(living.ChildRemoved:Connect(function()
            updateNPCList()
            if npcDropdownRefresh then npcDropdownRefresh(dynamicNPCList) end
        end))
    end

    local W, H = 380, 290

    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "WhiteHubV3"
    ScreenGui.DisplayOrder = 30
    mainScreenGui = ScreenGui
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ScreenGui.ResetOnSpawn   = false
    ScreenGui.Parent         = PlayerGui

    local MainFrame = Instance.new("Frame", ScreenGui)
    MainFrame.Name             = "MainFrame"
    MainFrame.BackgroundColor3 = THEME.BG
    MainFrame.BorderSizePixel  = 0
    MainFrame.AnchorPoint      = Vector2.new(0.5,0.5)
    MainFrame.Position         = UDim2.new(0.5,0,0.44,0)
    MainFrame.Size             = UDim2.new(0,W,0,H)
    MainFrame.Visible          = false
    if _compactUI then _compactUI:Responsive(MainFrame,W,H,trackConnection) end
    Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0,12)
    local mfStroke = addStroke(MainFrame, THEME.GOLD_EDGE, 1.25, 0.24)
    addGradient(MainFrame, THEME.BG, THEME.BG2, 90)
    pulseStroke(mfStroke, THEME.GOLD_BRIGHT, THEME.GOLD_EDGE)

    local TopBar = Instance.new("Frame", MainFrame)
    TopBar.Name             = "TopBar"
    TopBar.BackgroundColor3 = THEME.PANEL
    TopBar.BorderSizePixel  = 0
    TopBar.Size             = UDim2.new(1,0,0,35)
    Instance.new("UICorner", TopBar).CornerRadius = UDim.new(0,12)
    addGradient(TopBar, THEME.PANEL2, THEME.PANEL, 0)
    local topFix = Instance.new("Frame", TopBar)
    topFix.BackgroundColor3 = THEME.PANEL
    topFix.BorderSizePixel  = 0
    topFix.Position         = UDim2.new(0,0,0.5,0)
    topFix.Size             = UDim2.new(1,0,0.5,0)

    local bolt = Instance.new("TextLabel", TopBar)
    bolt.BackgroundTransparency = 1
    bolt.Position = UDim2.new(0, 12, 0, 0)
    bolt.Size = UDim2.new(0, 18, 1, 0)
    bolt.Text = "⚡"
    bolt.TextColor3 = THEME.GOLD_BRIGHT
    bolt.TextSize = 17
    bolt.Font = Enum.Font.GothamBold

    local Title = Instance.new("TextLabel", TopBar)
    Title.BackgroundTransparency = 1
    Title.BorderSizePixel = 0
    Title.Position = UDim2.new(0, 34, 0, 0)
    Title.Size = UDim2.new(0, 115, 1, 0)
    Title.Text = "WHITE DEV"
    Title.TextColor3 = THEME.WHITE
    Title.TextSize = 18
    Title.Font = Enum.Font.GothamBold
    Title.TextXAlignment = Enum.TextXAlignment.Left

    local versionLabel = Instance.new("TextLabel", TopBar)
    versionLabel.BackgroundTransparency = 1
    versionLabel.Position = UDim2.new(0, 145, 0, 1)
    versionLabel.Size = UDim2.new(0, 94, 1, -2)
    versionLabel.Text = "// WHITE AI"
    versionLabel.TextColor3 = THEME.GOLD_BRIGHT
    versionLabel.TextSize = 11
    versionLabel.Font = Enum.Font.GothamBold
    versionLabel.TextXAlignment = Enum.TextXAlignment.Left

    local topLine = Instance.new("Frame", TopBar)
    topLine.Size = UDim2.new(1, -20, 0, 1)
    topLine.Position = UDim2.new(0, 10, 1, -1)
    topLine.BackgroundColor3 = THEME.GOLD
    topLine.BackgroundTransparency = 0.2
    topLine.BorderSizePixel = 0

    local CloseButton = Instance.new("TextButton", TopBar)
    CloseButton.BackgroundColor3 = THEME.RED
    CloseButton.BorderSizePixel  = 0
    CloseButton.Position         = UDim2.new(1,-34,0.5,-12)
    CloseButton.Size             = UDim2.new(0,26,0,26)
    CloseButton.Text             = "X"
    CloseButton.TextColor3       = THEME.WHITE
    CloseButton.TextSize         = 16
    CloseButton.Font             = Enum.Font.GothamBold
    Instance.new("UICorner", CloseButton).CornerRadius = UDim.new(1,0)
    addStroke(CloseButton, THEME.RED_BRIGHT, 1, 0.2)
    CloseButton.MouseEnter:Connect(function()
        TweenService:Create(CloseButton, TweenInfo.new(0.12), {BackgroundColor3 = THEME.RED_BRIGHT}):Play()
    end)
    CloseButton.MouseLeave:Connect(function()
        TweenService:Create(CloseButton, TweenInfo.new(0.12), {BackgroundColor3 = THEME.RED}):Play()
    end)

    local Sidebar = Instance.new("ScrollingFrame", MainFrame)
    Sidebar.Active = true
    Sidebar.ScrollBarThickness = 2
    Sidebar.ScrollBarImageColor3 = THEME.GOLD
    Sidebar.CanvasSize = UDim2.new(0,0,0,0)
    Sidebar.AutomaticCanvasSize = Enum.AutomaticSize.Y
    Sidebar.BackgroundTransparency = 1
    Sidebar.BorderSizePixel        = 0
    Sidebar.Position               = UDim2.new(0,7,0,40)
    Sidebar.Size                   = UDim2.new(0,80,1,-48)
    local sideLayout = Instance.new("UIListLayout", Sidebar)
    sideLayout.Padding   = UDim.new(0,3)
    sideLayout.SortOrder = Enum.SortOrder.LayoutOrder

    local PagesFrame = Instance.new("Frame", MainFrame)
    PagesFrame.BackgroundTransparency = 1
    PagesFrame.BorderSizePixel        = 0
    PagesFrame.Position               = UDim2.new(0,94,0,40)
    PagesFrame.Size                   = UDim2.new(1,-104,1,-48)

    local function MakePage(name)
        local scroll = Instance.new("ScrollingFrame", PagesFrame)
        scroll.Name                    = name
        scroll.Active                  = true
        scroll.BackgroundTransparency  = 1
        scroll.BorderSizePixel         = 0
        scroll.ScrollBarThickness      = 4
        scroll.ScrollBarImageColor3    = THEME.GOLD
        scroll.Size                    = UDim2.new(1,0,1,0)
        scroll.Visible                 = false
        local layout = Instance.new("UIListLayout", scroll)
        layout.Padding   = UDim.new(0,4)
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        local pad = Instance.new("UIPadding", scroll)
        pad.PaddingLeft  = UDim.new(0,4)
        pad.PaddingRight = UDim.new(0,4)
        pad.PaddingTop   = UDim.new(0,4)
        scroll.ClipsDescendants = true
        if _compactUI then _compactUI:Observe(scroll,trackConnection) end
        return scroll
    end

    local FarmPage    = MakePage("FarmPage")
    local StandPage   = MakePage("StandPage")
    local ItemsPage   = MakePage("ItemsPage")
    local QuestPage   = MakePage("QuestPage")
    local TeleportPage = MakePage("TeleportPage")
    local WebhookPage = MakePage("WebhookPage")
    local ConsolePage = MakePage("ConsolePage")
    local AIPage = MakePage("AIPage")
    local SettingsPage = MakePage("SettingsPage")
    local EventsPage = MakePage("EventsPage")
    local CreditsPage = MakePage("CreditsPage")
    FarmPage.Visible = true

    local tabDefs = {
        { name="Farm",    page=FarmPage    },
        { name="Events",  page=EventsPage  },
        { name="AI DEBUG", page=AIPage },
        { name="Stand",   page=StandPage   },
        { name="Items",   page=ItemsPage   },
        { name="Combat", page=QuestPage },
        { name="Teleport", page=TeleportPage },
        { name="Webhook", page=WebhookPage },
        { name="Console", page=ConsolePage },
        { name="Settings", page=SettingsPage },
        { name="Credits", page=CreditsPage },
    }
    local tabButtons = {}
    local tabIndicators = {}

    local C_BG2      = THEME.PANEL
    local C_BG3      = THEME.PANEL2
    local C_Stroke   = THEME.GOLD_EDGE
    local C_StrokeAct= THEME.GOLD_BRIGHT
    local C_Text     = THEME.WHITE

    local function SetActiveTab(activePage)
        if _choices then _choices:Close() end
        for _, def in ipairs(tabDefs) do
            def.page.Visible = (def.page == activePage)
            local btn = tabButtons[def.name]
            if btn then
                local s = btn:FindFirstChildOfClass("UIStroke")
                local indicator = tabIndicators[def.name]
                if def.page == activePage then
                    TweenService:Create(btn, TweenInfo.new(.15), {BackgroundColor3=C_BG3, TextColor3=THEME.WHITE}):Play()
                    if s then TweenService:Create(s, TweenInfo.new(.15), {Color=C_StrokeAct, Transparency=0.05}):Play() end
                    if indicator then indicator.Visible = true end
                else
                    TweenService:Create(btn, TweenInfo.new(.15), {BackgroundColor3=C_BG2, TextColor3=THEME.MUTED}):Play()
                    if s then TweenService:Create(s, TweenInfo.new(.15), {Color=C_Stroke, Transparency=0.45}):Play() end
                    if indicator then indicator.Visible = false end
                end
            end
        end
    end

    for _, def in ipairs(tabDefs) do
        local btn = Instance.new("TextButton", Sidebar)
        btn.BackgroundColor3 = C_BG2
        btn.BorderSizePixel  = 0
        btn.Size             = UDim2.new(1,0,0,27)
        btn.Text             = def.name
        btn.TextColor3       = C_Text
        btn.TextSize         = 11
        btn.Font             = Enum.Font.GothamBold
        btn.TextXAlignment   = Enum.TextXAlignment.Left
        btn.Text             = "   " .. def.name
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0,7)
        local bs = Instance.new("UIStroke", btn)
        bs.Color = C_Stroke
        bs.Transparency = 0.45
        local indicator = Instance.new("Frame", btn)
        indicator.Size = UDim2.new(0, 3, 0.58, 0)
        indicator.Position = UDim2.new(0, 5, 0.21, 0)
        indicator.BackgroundColor3 = THEME.GOLD_BRIGHT
        indicator.BorderSizePixel = 0
        indicator.Visible = false
        Instance.new("UICorner", indicator).CornerRadius = UDim.new(1,0)
        tabButtons[def.name] = btn
        tabIndicators[def.name] = indicator
        btn.MouseButton1Click:Connect(function()
            SetActiveTab(def.page)
        end)
    end

    runtimeLog("INFO", "[Dev UI] AI DEBUG tab created at sidebar position 3; WhiteAI module " .. (_whiteAI and "loaded" or "missing"))

    do
        local s = tabButtons["Farm"]:FindFirstChildOfClass("UIStroke")
        tabButtons["Farm"].BackgroundColor3 = C_BG3
        tabButtons["Farm"].TextColor3 = THEME.WHITE
        if tabIndicators["Farm"] then tabIndicators["Farm"].Visible = true end
        if s then s.Color = C_StrokeAct; s.Transparency = 0.05 end
    end

    -- =====================
    -- SETTINGS PAGE
    -- =====================
    MakeSection(SettingsPage, "PERFORMANCE")
    if _settings then _settings:Build(SettingsPage,UI,MakeToggle,THEME) end
    AutoCanvas(SettingsPage)

    -- =====================
    -- FARM PAGE
    -- =====================
    MakeSection(FarmPage, "FARM SETTINGS")
    
    MakeToggle(FarmPage, "Enable Farm", _config and _config:Get("FarmEnabled"), function(v)
        if v and not stopPrestigeForSwitch("Enable Farm") then return end
        if v and _standFarm and _standFarm:IsRunning() then
            _standFarm:Stop()
            UI:SetToggleValue("Stand Farm (BETA)", false)
        end
        if _config then
            if v then
                _config:SetMany({FarmEnabled=true, EventItemsFarmEnabled=false, HalloweenAutoBuy=false})
                UI:SetToggleValue("Events Items Farm", false)
                UI:SetToggleValue("Auto Buy Selected Reward (once)",false)
            else
                _config:Set("FarmEnabled", false)
            end
        end
        if not v then
            print("[UI] Farm disabled by user.")
            runtimeLog("INFO", "Farm disabled by user.")
            if _webhook then _webhook:SendFarmDisabled() end
        else
            print("[UI] Farm enabled. Resuming...")
            runtimeLog("INFO", "Farm enabled by user.")
            if _webhook then _webhook:SendFarmResumed() end
        end
    end)
    
    MakeToggle(FarmPage, "Fast Pickup (BETA)",_config and _config:Get("FastPickupEnabled")==true,function(v)
        if _config then _config:Set("FastPickupEnabled",v==true) end
        runtimeLog("INFO","[PickupTune] "..(v and "Optional faster pickup enabled: original safeguards retained"
            or "Fast pickup disabled: original delays restored"))
    end)

    MakeToggle(FarmPage, "Auto Sell", _config and _config:Get("AutoSell"), function(v)
        if _config then _config:Set("AutoSell", v) end
    end)
    MakeToggle(FarmPage, "Auto Buy Lucky", _config and _config:Get("BuyLucky"), function(v)
        if _config then _config:Set("BuyLucky", v) end
    end)

    MakeToggle(FarmPage, "Stay in Private Server", _config and _config:Get("StayInPrivateServer"), function(v)
        if _config then _config:Set("StayInPrivateServer", v) end
        print("[UI] Stay in Private Server set to " .. tostring(v))
        runtimeLog("INFO", "Stay in Private Server = " .. tostring(v))
    end)

    -- Manual Server Hop uses the existing ServerHop.lua logic. No automatic
    -- hop timers or Merchant code are changed.
    local manualHopBusy = false
    local manualHopButton = Instance.new("TextButton")
    manualHopButton.Size = UDim2.new(1, -4, 0, 34)
    manualHopButton.Font = Enum.Font.GothamBold
    manualHopButton.TextSize = 13
    manualHopButton.Text = "SERVER HOP NOW"
    manualHopButton.Parent = FarmPage
    styleActionButton(manualHopButton, false)
    trackConnection(manualHopButton.MouseButton1Click:Connect(function()
        if not stopPrestigeForSwitch("Auto Prestige") then return end
        if manualHopBusy then return end
        manualHopBusy = true
        manualHopButton.Text = "HOPPING..."
        task.spawn(function()
            local ok, result = pcall(function()
                return _serverHop and _serverHop:Hop() or false
            end)
            if not ok or result ~= true then
                runtimeLog("WARN", "Manual Server Hop did not start: " .. tostring(result))
            end
            task.wait(1.2)
            if manualHopButton.Parent then
                manualHopButton.Text = "SERVER HOP NOW"
            end
            manualHopBusy = false
        end)
    end))

    MakeSection(FarmPage, "PRESTIGE")
    MakeToggle(FarmPage, "Auto Prestige", _config and _config:Get("AutoPrestige"), function(v)
        if _prestigeRuntime then
            if not v then _prestigeRuntime:Stop(); return end
            _config:SetMany({FarmEnabled=false,EventItemsFarmEnabled=false,QuestFarmEnabled=false,NPCFarmEnabled=false,AutoPrestige=false})
            if _standFarm then _standFarm:Stop() end
            if _combatFarm then _combatFarm:Stop() end
            UI:SetToggleValue("Enable Farm",false); UI:SetToggleValue("Events Items Farm",false); UI:SetToggleValue("Stand Farm (BETA)",false)
            UI:SetToggleValue("Quest Farm",false); UI:SetToggleValue("NPC Farm",false)
            if _farm and _farm.WaitForCollection and not _farm:WaitForCollection(3) then
                UI:SetToggleValue("Auto Prestige", false)
                UI:ShowPopup("Pickup is still finishing; retry Auto Prestige.", 5)
                return
            end
            local ok,reason=_prestigeRuntime:Start()
            if not ok then UI:SetToggleValue("Auto Prestige",false); UI:ShowPopup(tostring(reason),6) end
            return
        end
        if _config then
            if v then
                _config:SetMany({ AutoPrestige = true, EventItemsFarmEnabled = false, QuestFarmEnabled = false, NPCFarmEnabled = false })
            else
                _config:Set("AutoPrestige", false)
            end
        end
        getgenv().AutoPrestigeEnabled = v
        if v then
            if _standFarm and _standFarm:IsRunning() then
                _standFarm:Stop()
                UI:SetToggleValue("Stand Farm (BETA)", false)
            end
            UI:SetToggleValue("Quest Farm", false)
            UI:SetToggleValue("NPC Farm", false)
            UI:SetToggleValue("Events Items Farm", false)
            if _combatFarm then _combatFarm:Stop() end
            print("[UI] Auto Prestige enabled.")
            runtimeLog("INFO", "Auto Prestige enabled.")
        else
            print("[UI] Auto Prestige disabled.")
            runtimeLog("INFO", "Auto Prestige disabled.")
        end
    end)

    if _prestigeRuntime then _prestigeRuntime:BuildStatus(FarmPage,UI) end

    do
    local FarmPage = StandPage
    -- WHITE STAND FARM target list (DEV BETA): no inventory/merchant core changes.
    MakeSection(FarmPage, "STAND FARM - EXPERIMENTAL")

    local sourceDropdown = MakeStyledDropdown(FarmPage, "Stand consumable",
        {"Mysterious Arrow", "Rib Cage of The Saint's Corpse"}, function(selected)
            if _standFarm then _standFarm:Stop(); UI:SetToggleValue("Stand Farm (BETA)", false) end
            if _config then _config:Set("StandFarmConsumable", selected) end
        end)
    local savedSource = _config and _config:Get("StandFarmConsumable")
    sourceDropdown.Text = (savedSource == "Mysterious Arrow" or savedSource == "Rib Cage of The Saint's Corpse")
        and savedSource or "Mysterious Arrow"
    MakeToggle(FarmPage, "Auto Restock Consumables (BETA)",
        (_config and _config:Get("StandFarmAutoRestock")) == true, function(enabled)
            if _standFarm then _standFarm:Stop(); UI:SetToggleValue("Stand Farm (BETA)", false) end
            if _config then _config:Set("StandFarmAutoRestock", enabled) end
        end)
    MakeToggle(FarmPage, "Hop After Restock Limit (BETA)",
        (_config and _config:Get("StandFarmRestockHop")) == true, function(enabled)
            if _standFarm then _standFarm:Stop(); UI:SetToggleValue("Stand Farm (BETA)", false) end
            if _config then _config:Set("StandFarmRestockHop", enabled) end
        end)
    if _standV2UI then _standV2UI:BuildResume(FarmPage,UI,_config,_standFarm,MakeToggle,trackConnection,THEME) end
    local cancelRestockHop = Instance.new("TextButton", FarmPage)
    cancelRestockHop.Size = UDim2.new(1, -4, 0, 32)
    cancelRestockHop.Text = "CANCEL RESTOCK TRANSFER / STOP"
    cancelRestockHop.Font = Enum.Font.GothamBold
    cancelRestockHop.TextSize = 11
    styleActionButton(cancelRestockHop, false)
    trackConnection(cancelRestockHop.MouseButton1Click:Connect(function()
        if _standFarm then _standFarm:Stop() end
        UI:SetToggleValue("Stand Farm (BETA)", false)
    end))

    local refreshTargetList
    MakeToggle(FarmPage, "Shiny Farm Mode (BETA)", (_config and _config:Get("StandFarmMode") == "shiny") == true, function(enabled)
        if _standFarm and _standFarm:IsRunning() then
            _standFarm:Stop()
            UI:SetToggleValue("Stand Farm (BETA)", false)
        end
        if _config then _config:Set("StandFarmMode", enabled and "shiny" or "stand") end
        if refreshTargetList then refreshTargetList() end
        runtimeLog("INFO", enabled and "Shiny mode selected: common Stand targets ignored; every skin protected"
            or "Stand target mode selected")
    end)

    local availableStands = {
        "Star Platinum", "The World", "Crazy Diamond", "Killer Queen",
        "Gold Experience", "King Crimson", "Silver Chariot", "Whitesnake",
        "Stone Free", "The Hand", "Hierophant Green", "Magician's Red",
        "Purple Haze", "White Album", "Aerosmith", "Six Pistols", "Cream",
        "Mr. President", "Scary Monsters", "The World Alternate Universe",
        "D4C", "Tusk ACT 1", "Soft & Wet", "Sticky Fingers", "Anubis",
        "Hermit Purple", "Beach Boy", "Red Hot Chili Pepper",
    }
    local function stopForTargetEdit()
        if _standFarm and _standFarm:IsRunning() then
            _standFarm:Stop()
            UI:SetToggleValue("Stand Farm (BETA)", false)
        end
    end
    local targetListLabel = UI:AddLabel(FarmPage, "")
    targetListLabel.TextWrapped = true
    targetListLabel.Size = UDim2.new(1,-4,0,28)
    local function selectedStands()
        local list = _config and _config:Get("StandFarmTargets")
        if type(list)=="table" and #list>0 then return _catalog:Names(list) end
        local single = _config and _config:Get("StandFarmTarget")
        return _catalog:Names({}, {single})
    end
    local standRefresh
    refreshTargetList = function()
        local names=selectedStands()
        targetListLabel.Text = _config and _config:Get("StandFarmMode")=="shiny"
            and "ANY skin protected | saved targets inactive"
            or (#names>0 and "Targets: "..table.concat(names,", ") or "Select at least one Stand")
        if standRefresh then standRefresh() end
    end
    local standDropdown
    standDropdown,standRefresh = _choices:Build(FarmPage,"Stands",
        function() return availableStands end,selectedStands,function(names)
            if not _config then return false end
            _config:Set("StandFarmTargets",names)
            _config:Set("StandFarmTarget",names[1] or "")
            refreshTargetList()
        end,stopForTargetEdit,UI,THEME,trackConnection)
    refreshTargetList()
    if _standV2UI then
        _standV2UI:BuildSkins(FarmPage,UI,_config,_standFarm,stopForTargetEdit,trackConnection,THEME,_choices,_catalog)
    end

    local pityInput = Instance.new("TextBox", FarmPage)
    pityInput.Size = UDim2.new(1, -4, 0, 30)
    pityInput.BackgroundColor3 = THEME.PANEL2
    pityInput.BorderSizePixel = 0
    pityInput.Font = Enum.Font.Code
    pityInput.TextColor3 = THEME.WHITE
    pityInput.TextSize = 12
    pityInput.ClearTextOnFocus = false
    pityInput.PlaceholderText = "Stop at pity (0 disables limit)"
    pityInput.Text = "Stop at pity: " .. tostring(_config and _config:Get("StandFarmPityLimit") or 20)
    Instance.new("UICorner", pityInput).CornerRadius = UDim.new(0, 6)
    trackConnection(pityInput.FocusLost:Connect(function()
        local raw = pityInput.Text:match("(%d+)")
        local num = raw and tonumber(raw)
        if num == nil or num < 0 or num > 125 then
            num = _config and _config:Get("StandFarmPityLimit") or 20
        elseif _config then
            _config:Set("StandFarmPityLimit", num)
        end
        pityInput.Text = "Stop at pity: " .. tostring(num)
    end))

    MakeToggle(FarmPage, "Stand Farm (BETA)", false, function(enabled)
        if enabled and _config and _config:Get("EventItemsFarmEnabled") then
            UI:SetToggleValue("Stand Farm (BETA)", false)
            UI:ShowPopup("Disable Events Items Farm before starting Stand Farm.", 5)
            return
        end
        if enabled and not stopPrestigeForSwitch("Stand Farm (BETA)") then return end
        if not _standFarm then
            UI:SetToggleValue("Stand Farm (BETA)", false)
            return
        end
        if enabled then
            local ok, reason = _standFarm:Start()
            if not ok then
                UI:SetToggleValue("Stand Farm (BETA)", false)
                runtimeLog("WARN", "Stand Farm not started: " .. tostring(reason))
                UI:ShowPopup(tostring(reason), 5)
            end
        else
            _standFarm:Stop()
        end
    end)

    local standStatus = UI:AddLabel(FarmPage, "Stand Farm: idle")
    standStatus.TextScaled = false
    standStatus.TextWrapped = true
    standStatus.Size = UDim2.new(1, -4, 0, 40)
    task.spawn(function()
        while standStatus.Parent do
            task.wait(2)
            if not standStatus.Parent then break end
            if _standFarm then
                local state = _standFarm:GetStatus()
                standStatus.Text = ("%s | %s | Pity %s | Rolls %d\n%s"):format(
                    tostring(state.mode or "stand"), tostring(state.stand or "?"), tostring(state.pity or "?"),
                    tonumber(state.rolls) or 0, tostring(state.message or "Idle"))
                if not state.running then
                    UI:SetToggleValue("Stand Farm (BETA)", false)
                end
            end
        end
    end)

    if _standV2UI then _standV2UI:BuildStats(FarmPage,UI,_standFarm,trackConnection,styleActionButton) end
    AutoCanvas(FarmPage)

    end
    AutoCanvas(FarmPage)

    -- =====================
    -- ITEMS PAGE
    -- =====================
    MakeSection(ItemsPage, "SELL ITEMS")

    MakeToggle(ItemsPage, "Merchant Callback Pacing (BETA)",
        _config and _config:Get("MerchantPacingBeta")==true, function(v)
            if _config then _config:Set("MerchantPacingBeta",v==true) end
            runtimeLog("INFO","[MerchantPacing] "..(v and
                "Opt-in 75ms dialogue callback pacing enabled" or "Proven FINAL signal cadence restored"))
        end)

    -- Manual one-shot Merchant sale: independent of the Auto Sell toggle and
    -- the Server Hop timer. The same saved item selection is respected.
    local sellNowButton = Instance.new("TextButton")
    sellNowButton.Name = "SellNow"
    sellNowButton.Size = UDim2.new(1, -4, 0, 36)
    sellNowButton.Text = "SELL NOW"
    sellNowButton.Font = Enum.Font.GothamBold
    sellNowButton.TextSize = 13
    sellNowButton.Parent = ItemsPage
    styleActionButton(sellNowButton, true)

    local manualSaleUiBusy = false
    trackConnection(sellNowButton.MouseButton1Click:Connect(function()
        if manualSaleUiBusy then return end
        if not _farm or type(_farm.SellNow) ~= "function" then
            UI:ShowPopup("Manual Merchant sale is unavailable.", 4)
            return
        end
        manualSaleUiBusy = true
        sellNowButton.Text = "SELLING..."
        task.spawn(function()
            local ok, sold, description = pcall(function()
                return _farm:SellNow()
            end)
            if ok and sold then
                runtimeLog("INFO", "SELL NOW: " .. tostring(description))
                UI:ShowPopup(tostring(description), 4)
            else
                local reason = ok and tostring(description) or "Unexpected sale error; see Console"
                runtimeLog("WARN", "SELL NOW: " .. reason)
                UI:ShowPopup(reason, 5)
            end
            if sellNowButton and sellNowButton.Parent then
                sellNowButton.Text = "SELL NOW"
            end
            manualSaleUiBusy = false
        end)
    end))

    local itemOrder = { "Gold Coin","Diamond","Rokakaka","Pure Rokakaka","Mysterious Arrow","Lucky Arrow","Lucky Stone Mask","Ancient Scroll","Caesar's Headband","Stone Mask","Rib Cage of The Saint's Corpse","Quinton's Glove","Zeppeli's Hat","Clackers","Steel Ball","Dio's Diary", }
    for _, name in ipairs(itemOrder) do
        local default = _config and _config:GetSellItem(name)
        if default == nil then default = true end
        MakeToggle(ItemsPage, name, default, function(v)
            if _config then _config:SetSellItem(name, v) end
        end)
    end
    AutoCanvas(ItemsPage)

    -- =====================
    -- QUESTS & NPCS TAB
    -- =====================
    MakeSection(QuestPage, "QUEST FARM")
    
    MakeToggle(QuestPage, "Auto Choose Quest", _config and _config:Get("AutoChooseQuest"), function(v)
        if _config then _config:Set("AutoChooseQuest", v) end
        print("[UI] Auto Choose Quest set to " .. tostring(v))
        runtimeLog("INFO", "Auto Choose Quest = " .. tostring(v))
    end)
    
    local questList = {
        "Officer Sam [Lvl. 1+]",
        "Deputy Bertrude [Lvl. 10+]",
        "Abbacchio's Partner [Lvl 15+]",
        "Homeless Man Jill [Lvl. 15+]",
        "Dracula [Lvl. 20+]",
        "William Zeppeli [Lvl. 25+]",
        "Doppio [Lvl. 30+]",
        "Dio [Lvl. 35+]"
    }
    local questDropdown = _choices:Build(QuestPage,"Quest",
        function() return _catalog:GetQuests(questList) end,
        function() return _catalog:Names({}, {_config and _config:Get("SelectedQuest")}) end,
        function(names)
            local selected=names[1]
            if _catalog:IsInfo(selected) or not table.find(questList,selected) then
                UI:ShowPopup("Quest catalog only: objective not mapped. Current quest selection unchanged.",5)
                return false
            end
            if _config then _config:Set("SelectedQuest",selected) end
        end,nil,UI,THEME,trackConnection,true)

    -- Quest/NPC are mutually exclusive and CombatFarm enforces one worker.
    MakeToggle(QuestPage, "Quest Farm", _config and _config:Get("QuestFarmEnabled"), function(v)
        if v and not stopPrestigeForSwitch("Quest Farm") then return end
        if v and _config and _config:Get("EventItemsFarmEnabled") then
            _config:Set("EventItemsFarmEnabled", false)
            UI:SetToggleValue("Events Items Farm", false)
            if _farm and _farm.WaitForCollection and not _farm:WaitForCollection(3) then
                UI:SetToggleValue("Quest Farm", false)
                UI:ShowPopup("Event pickup is still in progress. Try Quest Farm again.", 5)
                return
            end
        end
        if _config then
            if v then
                _config:SetMany({ QuestFarmEnabled = true, NPCFarmEnabled = false, EventItemsFarmEnabled = false, AutoPrestige = false })
            else
                _config:Set("QuestFarmEnabled", false)
            end
        end
        if v then
            if _standFarm and _standFarm:IsRunning() then
                _standFarm:Stop()
                UI:SetToggleValue("Stand Farm (BETA)", false)
            end
            getgenv().AutoPrestigeEnabled = false
            UI:SetToggleValue("NPC Farm", false)
            UI:SetToggleValue("Events Items Farm", false)
            UI:SetToggleValue("Auto Prestige", false)
            runtimeLog("INFO", "Quest Farm enabled.")
            if _combatFarm then _combatFarm:StartQuest() end
        else
            runtimeLog("INFO", "Quest Farm disabled.")
            if _combatFarm then
                local running, mode = _combatFarm:IsRunning()
                if running and mode == "Quest" then _combatFarm:Stop() end
            end
        end
    end)
    
    MakeSection(QuestPage, "NPC FARM")
    
    -- Dynamic NPC dropdown (unique names) with refresh support
    local npcBtn, npcRefresh = MakeStyledDropdown(QuestPage, "Select NPC", dynamicNPCList, function(selected)
        if _config then _config:Set("SelectedNPC", selected) end
    end)
    npcDropdownRefresh = npcRefresh
    local savedNPC = _config and _config:Get("SelectedNPC")
    if savedNPC and savedNPC ~= "" and table.find(dynamicNPCList, savedNPC) then
        npcBtn.Text = savedNPC
    end
    
    MakeToggle(QuestPage, "NPC Farm", _config and _config:Get("NPCFarmEnabled"), function(v)
        if v and not stopPrestigeForSwitch("NPC Farm") then return end
        if v and _config and _config:Get("EventItemsFarmEnabled") then
            _config:Set("EventItemsFarmEnabled", false)
            UI:SetToggleValue("Events Items Farm", false)
            if _farm and _farm.WaitForCollection and not _farm:WaitForCollection(3) then
                UI:SetToggleValue("NPC Farm", false)
                UI:ShowPopup("Event pickup is still in progress. Try NPC Farm again.", 5)
                return
            end
        end
        if _config then
            if v then
                _config:SetMany({ NPCFarmEnabled = true, QuestFarmEnabled = false, EventItemsFarmEnabled = false, AutoPrestige = false })
            else
                _config:Set("NPCFarmEnabled", false)
            end
        end
        if v then
            if _standFarm and _standFarm:IsRunning() then
                _standFarm:Stop()
                UI:SetToggleValue("Stand Farm (BETA)", false)
            end
            getgenv().AutoPrestigeEnabled = false
            UI:SetToggleValue("Quest Farm", false)
            UI:SetToggleValue("Events Items Farm", false)
            UI:SetToggleValue("Auto Prestige", false)
            runtimeLog("INFO", "NPC Farm enabled.")
            if _combatFarm then _combatFarm:StartNPC() end
        else
            runtimeLog("INFO", "NPC Farm disabled.")
            if _combatFarm then
                local running, mode = _combatFarm:IsRunning()
                if running and mode == "NPC" then _combatFarm:Stop() end
            end
        end
    end)
    
    MakeSection(QuestPage, "AUTO SKILLS")
    local skillsLabel = UI:AddLabel(QuestPage, "Skills: None")
    
    local function updateSkillsLabel()
        local skills = _config:Get("AutoSkills") or {}
        local text = #skills > 0 and "Skills: " .. table.concat(skills, ", ") or "Skills: None"
        skillsLabel.Text = text
    end
    updateSkillsLabel()
    
    MakeToggle(QuestPage, "Add Skill (press a key)", false, function(v)
        if activeSkillCapture then
            activeSkillCapture:Disconnect()
            activeSkillCapture = nil
        end
        if not v then return end

        activeSkillCapture = UserInputService.InputBegan:Connect(function(input, gp)
            if gp then return end
            local key = input.KeyCode.Name
            if key and key ~= "Unknown" then
                local current = _config:Get("AutoSkills") or {}
                if not table.find(current, key) then
                    table.insert(current, key)
                    _config:Set("AutoSkills", current)
                    updateSkillsLabel()
                end
                if activeSkillCapture then
                    activeSkillCapture:Disconnect()
                    activeSkillCapture = nil
                end
                UI:SetToggleValue("Add Skill (press a key)", false)
            end
        end)
    end)
    
    MakeToggle(QuestPage, "Clear Skills", false, function(v)
        if v then
            _config:Set("AutoSkills", {})
            updateSkillsLabel()
            UI:SetToggleValue("Clear Skills", false)
        end
    end)
    

    -- Separate item collection mode, reusing Farm.lua and original pickup guards.
    MakeSection(EventsPage, "EVENT ITEMS FARM")
    MakeToggle(EventsPage, "Events Items Farm",
        _config and _config:Get("EventItemsFarmEnabled") == true, function(on)
        if not _config then return end
        if on then
            local blocked = _config:Get("AutoPrestige") or _config:Get("StandFarmEnabled")
                or _config:Get("QuestFarmEnabled") or _config:Get("NPCFarmEnabled")
            if _prestigeRuntime and _prestigeRuntime:IsBusy() then blocked = true end
            if _standFarm and _standFarm:IsRunning() then blocked = true end
            if _combatFarm then
                local combatRunning = _combatFarm:IsRunning()
                if combatRunning then blocked = true end
            end
            if _community and _community.IsPiloting and _community:IsPiloting() then
                blocked = true
            end
            if _farm and _farm.CanEnableEvent and not _farm:CanEnableEvent() then blocked = true end
            if blocked then
                UI:SetToggleValue("Events Items Farm",false)
                UI:ShowPopup("Stop Prestige, Stand, Quest or NPC Farm before enabling Event Farm.",6)
                return
            end
            _config:SetMany({FarmEnabled=false, EventItemsFarmEnabled=true})
            UI:SetToggleValue("Enable Farm", false)
            runtimeLog("INFO", "[EventFarm] Candy-only mode enabled.")
            UI:ShowPopup("Event Farm ON: only Yellow, Blue, Green and Red Candy.",5)
        else
            _config:SetMany({EventItemsFarmEnabled=false,HalloweenAutoBuy=false})
            UI:SetToggleValue("Auto Buy Selected Reward (once)",false)
            runtimeLog("INFO", "[EventFarm] Disabled; normal farm remains OFF.")
        end
    end)
    -- Read-only reward wishlist based on 39 captured dialogue states from Jack.
    -- User can choose target; no purchase/candy action until server behavior is proven.
    MakeSection(EventsPage, "HALLOWEEN REWARDS - BETA")
    local rewards={
        ["2026 Halloween Event Items"]={
            {"Boxing Blobs (Boxing Gloves Skin)",60},
            {"Spectral Marrow (Pluck Skin)",70},
            {"Jack-o-Ball (Steel Ball Skin)",45},
            {"Sanguine Veil (Umbrella Skin)",75}
        },
        ["2022 Halloween Event Items"]={
            {"Eye of The Saint's Corpse (Steel Ball Skin)",45},
            {"Bone Gloves (Boxing Gloves Skin)",60},
            {"Cursed Scythe (Pluck Skin)",70}
        },
        ["2021 Halloween Event Items"]={
            {"Stop Sign",45},{"Boxing Claws (Boxing Gloves Skin)",60},
            {"Scythe (Pluck Skin)",70},{"Random Halloween Cosmetic",25}
        },
        ["Normal Items"]={
            {"Mysterious Arrow",2},{"Rokakaka",3},
            {"Rib Cage of The Saint's Corpse",5},{"DIO's Diary",10},
            {"Green Baby",15},{"Lucky Arrow",100}
        },
    }
    local categoryNames={
        "2026 Halloween Event Items", "2022 Halloween Event Items",
        "2021 Halloween Event Items", "Normal Items"
    }
    local currentCategory=_config:Get("HalloweenRewardCategory")
    if not rewards[currentCategory] then currentCategory=categoryNames[1] end
    local function labelsFor(category)
        local options={"Choose reward..."}
        for _,record in ipairs(rewards[category] or {}) do
            options[#options+1]=record[1].." - "..tostring(record[2]).." points"
        end
        return options
    end
    local refreshRewards=nil
    local categoryBtn=MakeStyledDropdown(EventsPage,"Category",categoryNames,function(category)
        currentCategory=category
        _config:SetMany({HalloweenRewardCategory=category,HalloweenRewardTarget=""})
        if refreshRewards then refreshRewards(labelsFor(category)) end
        UI:ShowPopup("Category saved. Auto Buy is not enabled.",4)
    end)
    categoryBtn.Text=currentCategory
    local choices=labelsFor(currentCategory)
    local rewardBtn
    rewardBtn,refreshRewards=MakeStyledDropdown(EventsPage,"Reward",choices,function(selection)
        _config:Set("HalloweenRewardTarget",selection=="Choose reward..." and "" or selection)
        UI:ShowPopup("Reward saved; no purchase yet. Use opt-in controls below.",4)
    end)
    local savedReward=_config:Get("HalloweenRewardTarget")
    if table.find(choices,savedReward) then rewardBtn.Text=savedReward end
    -- Autotrade executes only at a dry-server checkpoint in Events Items Farm.
    -- Saved reward is not permission to spend. Buy permission is per-runtime.
    MakeSection(EventsPage, "JACK EXCHANGE - OPT IN BETA")
    MakeToggle(EventsPage,"Invisible Jack Dialogue (BETA)",
        _config and _config:Get("HalloweenFastDialogue")==true,function(v)
            if _config then _config:Set("HalloweenFastDialogue",v==true) end
            runtimeLog("INFO","[Halloween] Hidden Jack dialogue "..(v and "ON" or "OFF"))
        end)
    MakeToggle(EventsPage, "Auto Turn-In Candy",
        _config and _config:Get("HalloweenAutoTurnIn")==true, function(on)
            if _config then _config:Set("HalloweenAutoTurnIn",on==true) end
            runtimeLog("INFO", "[Halloween] Auto Turn-In "..(on and "ON" or "OFF"))
            UI:ShowPopup(on and "Candy conversion enabled at next dry-server checkpoint."
                or "Auto Turn-In disabled.",5)
        end)
    MakeToggle(EventsPage, "Auto Buy Selected Reward (once)",
        false, function(on)
            if not _config or not _halloween then return end
            if on then
                if (_config:Get("HalloweenRewardTarget") or "")=="" then
                    UI:SetToggleValue("Auto Buy Selected Reward (once)",false)
                    UI:ShowPopup("Select a reward first. No points spent.",5)
                    return
                end
                local points=_halloween:GetPoints()
                if not points then
                    UI:SetToggleValue("Auto Buy Selected Reward (once)",false)
                    UI:ShowPopup("Halloween points are not exposed; Auto Buy is locked.",5)
                    return
                end
                if _config:Get("EventItemsFarmEnabled")~=true then
                    UI:SetToggleValue("Auto Buy Selected Reward (once)",false)
                    UI:ShowPopup("Enable Events Items Farm for automatic one-shot buy.",5)
                    return
                end
            end
            _config:Set("HalloweenAutoBuy",on==true)
            runtimeLog("INFO","[Halloween] Auto Buy (one attempt) "..(on and "ON" or "OFF"))
        end)
    local function eventAction(text,handler)
        local b=Instance.new("TextButton")
        b.Name="HalloweenAction"
        b.Size=UDim2.new(1,-4,0,34)
        b.Text=text
        b.TextSize=12
        b.Font=Enum.Font.GothamBold
        b.Parent=EventsPage
        styleActionButton(b,false)
        local running=false
        trackConnection(b.MouseButton1Click:Connect(function()
            if running then return end
            running=true
            b.Text="WORKING..."
            task.spawn(function()
                local ok,success,message=pcall(handler)
                local report=ok and tostring(message) or "Unexpected Halloween error; inspect Console."
                runtimeLog(ok and success and "INFO" or "WARN", "[Halloween] "..report)
                UI:ShowPopup(report,6)
                if b.Parent then b.Text=text end
                running=false
            end)
        end))
    end
    eventAction("GO TO HALLOWEEN JACK",function()
        if not _community then return false,"Jack teleport unavailable" end
        return _community:TeleportToLandmark("jack")
    end)
    eventAction("TURN IN CANDY NOW (ONCE)",function()
        if not _halloween then return false,"Exchange module unavailable" end
        return _halloween:TurnInCandy("manual")
    end)
    eventAction("BUY SELECTED REWARD NOW (ONCE)",function()
        if not _halloween then return false,"Exchange module unavailable" end
        return _halloween:BuySelectedReward("manual")
    end)

    -- Community features are separate opt-in tools; do not modify core workers.
    -- Reflow all affected pages after inserting buttons/sections.
    if _community then
        -- Reuse the native Silver toggle visual and registry. A stopped Pilot
        -- resets this switch through UI:SetToggleValue without re-firing callbacks.
        UI._buildCommunityPilotToggle = function(page, label, callback)
            MakeToggle(page, label, false, callback)
        end
        _community:Build(StandPage, QuestPage, EventsPage, SettingsPage,
            UI, MakeSection, styleActionButton, trackConnection)
        _community:BuildTeleports(TeleportPage, UI, MakeSection,
            styleActionButton, trackConnection, MakeStyledDropdown)
    end
    AutoCanvas(StandPage)
    AutoCanvas(QuestPage)
    AutoCanvas(TeleportPage)
    AutoCanvas(EventsPage)
    AutoCanvas(SettingsPage)

    -- =====================
    -- WEBHOOK PAGE
    -- =====================
    MakeSection(WebhookPage, "DISCORD WEBHOOK")
    local whHolder = Instance.new("Frame")
    whHolder.Size             = UDim2.new(1,-4,0,42)
    whHolder.BackgroundColor3 = THEME.PANEL
    whHolder.BorderSizePixel  = 0
    whHolder.Parent           = WebhookPage
    Instance.new("UICorner", whHolder).CornerRadius = UDim.new(0,7)
    local whStroke = Instance.new("UIStroke", whHolder)
    whStroke.Color = THEME.GOLD_EDGE
    local whBox = Instance.new("TextBox")
    whBox.Size               = UDim2.new(1,-12,1,0)
    whBox.Position           = UDim2.new(0,8,0,0)
    whBox.BackgroundColor3   = THEME.PANEL3
    whBox.BackgroundTransparency = 0
    whBox.Text               = (_config and _config:Get("WebhookURL")) or ""
    whBox.PlaceholderText    = "https://discord.com/api/webhooks/..."
    whBox.TextColor3         = THEME.WHITE
    whBox.PlaceholderColor3  = THEME.MUTED
    whBox.TextSize           = 14
    whBox.Font               = Enum.Font.Gotham
    whBox.TextXAlignment     = Enum.TextXAlignment.Left
    whBox.ClearTextOnFocus   = false
    whBox.Parent             = whHolder
    whBox.Focused:Connect(function()
        TweenService:Create(whStroke, TweenInfo.new(0.1), {Color=THEME.GOLD_BRIGHT}):Play()
        whBox.BackgroundColor3 = THEME.PANEL3
    end)
    whBox.FocusLost:Connect(function()
        if _config then _config:Set("WebhookURL", whBox.Text) end
        TweenService:Create(whStroke, TweenInfo.new(0.1), {Color=THEME.GOLD_EDGE}):Play()
        whBox.BackgroundColor3 = THEME.PANEL3
    end)

    local resetBtn = Instance.new("TextButton")
    resetBtn.Size = UDim2.new(1,-4,0,36)
    resetBtn.Position = UDim2.new(0,0,0,50)
    resetBtn.BackgroundColor3 = THEME.GOLD_DARK
    resetBtn.BorderSizePixel = 0
    resetBtn.Text = "RESET WEBHOOK FLAGS"
    resetBtn.TextColor3 = THEME.WHITE
    resetBtn.TextScaled = false
    resetBtn.TextSize = 12
    resetBtn.Font = Enum.Font.GothamBold
    resetBtn.Parent = WebhookPage
    Instance.new("UICorner", resetBtn).CornerRadius = UDim.new(0,7)
    styleActionButton(resetBtn, true)
    resetBtn.MouseButton1Click:Connect(function()
        if _config then
            _config:Set("Phase1Notified", false)
            _config:Set("Phase3Notified", false)
            print("[UI] Webhook flags reset.")
            runtimeLog("INFO", "Webhook notification flags reset.")
            if _webhook then
                _webhook:Send("🔄 **Webhook flags reset**\nPlayer: `" .. Player.Name .. "`\nPhase1 and Phase3 notifications will be re‑sent on next completion.")
            end
        end
    end)
    resetBtn.MouseEnter:Connect(function()
        TweenService:Create(resetBtn, TweenInfo.new(0.15), {BackgroundColor3=THEME.GOLD_BRIGHT}):Play()
    end)
    resetBtn.MouseLeave:Connect(function()
        TweenService:Create(resetBtn, TweenInfo.new(0.15), {BackgroundColor3=THEME.GOLD}):Play()
    end)

    AutoCanvas(WebhookPage)

    -- =====================
    -- RUNTIME CONSOLE PAGE
    -- =====================
    MakeSection(ConsolePage, "RUNTIME CONSOLE")

    local consoleStatus = Instance.new("TextLabel")
    consoleStatus.Size = UDim2.new(1,-4,0,28)
    consoleStatus.BackgroundColor3 = THEME.PANEL
    consoleStatus.BorderSizePixel = 0
    consoleStatus.TextColor3 = THEME.MUTED
    consoleStatus.TextSize = 12
    consoleStatus.Font = Enum.Font.Gotham
    consoleStatus.TextXAlignment = Enum.TextXAlignment.Left
    consoleStatus.Text = " Runtime log unavailable"
    consoleStatus.Parent = ConsolePage
    Instance.new("UICorner", consoleStatus).CornerRadius = UDim.new(0,6)

    local consoleHolder = Instance.new("Frame")
    consoleHolder.Size = UDim2.new(1,-4,0,150)
    consoleHolder.BackgroundColor3 = THEME.BG2
    consoleHolder.BorderSizePixel = 0
    consoleHolder.Parent = ConsolePage
    Instance.new("UICorner", consoleHolder).CornerRadius = UDim.new(0,7)
    local consoleStroke = Instance.new("UIStroke", consoleHolder)
    consoleStroke.Color = THEME.GOLD_EDGE

    local logScroll = Instance.new("ScrollingFrame")
    logScroll.Size = UDim2.new(1,-8,1,-8)
    logScroll.Position = UDim2.new(0,4,0,4)
    logScroll.BackgroundTransparency = 1
    logScroll.BorderSizePixel = 0
    logScroll.ScrollBarThickness = 4
    logScroll.ScrollBarImageColor3 = THEME.GOLD
    logScroll.CanvasSize = UDim2.new(0,0,0,0)
    logScroll.Parent = consoleHolder

    local logLabel = Instance.new("TextLabel")
    logLabel.Size = UDim2.new(1,-8,0,20)
    logLabel.Position = UDim2.new(0,4,0,0)
    logLabel.BackgroundTransparency = 1
    logLabel.TextColor3 = THEME.WHITE
    logLabel.TextSize = 11
    logLabel.Font = Enum.Font.Code
    logLabel.TextXAlignment = Enum.TextXAlignment.Left
    logLabel.TextYAlignment = Enum.TextYAlignment.Top
    logLabel.TextWrapped = true
    logLabel.Text = "No runtime entries yet."
    logLabel.Parent = logScroll

    local consoleButtons = Instance.new("Frame")
    consoleButtons.Size = UDim2.new(1,-4,0,34)
    consoleButtons.BackgroundTransparency = 1
    consoleButtons.Parent = ConsolePage

    local function makeConsoleButton(text, xScale, widthScale, accent)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(widthScale,-3,1,0)
        btn.Position = UDim2.new(xScale,0,0,0)
        btn.BackgroundColor3 = accent and THEME.GOLD_DARK or THEME.PANEL3
        btn.BorderSizePixel = 0
        btn.Text = text
        btn.TextColor3 = THEME.WHITE
        btn.TextSize = 11
        btn.Font = Enum.Font.GothamBold
        btn.AutoButtonColor = false
        btn.Parent = consoleButtons
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0,7)
        styleActionButton(btn, accent)
        return btn
    end

    local copyLogBtn   = makeConsoleButton("Copy All",   0.00, 0.28, true)
    local copyWarnBtn  = makeConsoleButton("Copy WARN",  0.28, 0.26, false)
    local copyErrorBtn = makeConsoleButton("Copy ERROR", 0.54, 0.27, false)
    local clearLogBtn  = makeConsoleButton("Clear",      0.81, 0.19, false)

    -- Controls stay separate from the existing four buttons for mobile readability.
    local consoleTools = Instance.new("Frame")
    consoleTools.Size = UDim2.new(1,-4,0,34)
    consoleTools.BackgroundTransparency = 1
    consoleTools.Parent = ConsolePage

    local function makeConsoleTool(text, x, w)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(w,-3,1,0)
        btn.Position = UDim2.new(x,0,0,0)
        btn.BackgroundColor3 = THEME.PANEL3
        btn.BorderSizePixel = 0
        btn.Text = text
        btn.TextColor3 = THEME.WHITE
        btn.TextSize = 11
        btn.Font = Enum.Font.GothamBold
        btn.AutoButtonColor = false
        btn.Parent = consoleTools
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0,7)
        styleActionButton(btn, false)
        return btn
    end

    local followLogBtn = makeConsoleTool("Follow: ON", 0.00, 0.50)
    local copySaleBtn = makeConsoleTool("Copy SALE", 0.50, 0.50)
    local followConsole = not _config or _config:Get("ConsoleFollow") ~= false
    followLogBtn.Text = followConsole and "Follow: ON" or "Follow: OFF"

    local warnStroke = copyWarnBtn:FindFirstChildOfClass("UIStroke")
    if warnStroke then warnStroke.Color = THEME.GOLD end
    local errorStroke = copyErrorBtn:FindFirstChildOfClass("UIStroke")
    if errorStroke then errorStroke.Color = THEME.RED or Color3.fromRGB(190,72,72) end

    local function refreshConsole()
        if not _runtimeLog then
            consoleStatus.Text = " Runtime log unavailable"
            logLabel.Text = "RuntimeLog was not provided by Main.lua."
            return
        end

        local stats = _runtimeLog:GetStats()
        local lastIssue = _runtimeLog:GetLastError()
        consoleStatus.Text = (" INFO %d   WARN %d   ERROR %d"):format(stats.INFO, stats.WARN, stats.ERROR)
        if lastIssue then
            consoleStatus.Text = consoleStatus.Text .. "   | Last: " .. tostring(lastIssue.Module)
        end

        local text = _runtimeLog:GetText()
        logLabel.Text = text

        task.defer(function()
            if not logScroll.Parent then return end
            local width = math.max(120, logScroll.AbsoluteSize.X - 12)
            local ok, bounds = pcall(function()
                return TextService:GetTextSize(text, 11, Enum.Font.Code, Vector2.new(width, 100000))
            end)
            local height = ok and math.max(20, bounds.Y + 10) or math.max(20, (#text / 45) * 14)
            -- Do not force the view to the bottom while the user is reading old entries.
            -- Always clamp the retained position to the new canvas dimensions.
            local retainedY = logScroll.CanvasPosition.Y
            logLabel.Size = UDim2.new(1,-8,0,height)
            logScroll.CanvasSize = UDim2.new(0,0,0,height + 6)
            local maxY = math.max(0, height + 6 - logScroll.AbsoluteSize.Y)
            logScroll.CanvasPosition = Vector2.new(0, followConsole and maxY or math.clamp(retainedY, 0, maxY))
        end)
    end

    local function executorName()
        local exec = "Unknown"
        pcall(function()
            if type(identifyexecutor) == "function" then
                local a, b = identifyexecutor()
                exec = b ~= nil and (tostring(a) .. " " .. tostring(b)) or tostring(a)
            end
        end)
        return exec
    end

    local function buildFilteredRuntimeLog(level)
        level = tostring(level or ""):upper()
        if not _runtimeLog then
            return "WHITE HUB V3 - RuntimeLog unavailable"
        end

        local entries = {}
        if type(_runtimeLog.GetEntries) == "function" then
            local ok, result = pcall(function()
                return _runtimeLog:GetEntries()
            end)
            if ok and type(result) == "table" then
                entries = result
            end
        end

        local lines = {
            "WHITE HUB V3 - " .. level .. " REPORT",
            "========================================",
            "UI Build: " .. tostring(UI_BUILD),
            "Runtime ID: " .. tostring(_runtimeLog.RuntimeId or "unknown"),
            "PlaceId: " .. tostring(game.PlaceId),
            "JobId: " .. tostring(game.JobId),
            "Player: " .. tostring(Player and Player.Name or "unknown"),
            "Executor: " .. executorName(),
            "",
            level .. " EVENTS",
            "----------------------------------------",
        }

        local count = 0
        for _, entry in ipairs(entries) do
            if tostring(entry.Level or ""):upper() == level then
                count = count + 1
                lines[#lines + 1] = ("[%s] [%s] [%s] %s"):format(
                    tostring(entry.Time or "?"),
                    level,
                    tostring(entry.Module or "General"),
                    tostring(entry.Message or "")
                )
            end
        end

        if count == 0 then
            lines[#lines + 1] = "No " .. level .. " entries recorded."
        end

        table.insert(lines, 9, "Matching entries: " .. tostring(count))
        return table.concat(lines, "\n")
    end

    -- Export only Auto Sell performance and Inventory events. Unlike the scrolling
    -- label, this report can be pasted and searched even as new entries arrive.
    local function buildSaleRuntimeLog()
        if not _runtimeLog or type(_runtimeLog.GetEntries) ~= "function" then
            return "WHITE HUB V5 - Sell performance log unavailable"
        end

        local lines = {
            "WHITE HUB V5 - AUTO SELL DIAGNOSTICS",
            "========================================",
            "Runtime ID: " .. tostring(_runtimeLog.RuntimeId or "unknown"),
            "",
            "AUTO SELL EVENTS",
            "----------------------------------------",
        }
        local count, completed = 0, 0
        local ok, entries = pcall(function() return _runtimeLog:GetEntries() end)
        if ok and type(entries) == "table" then
            for _, entry in ipairs(entries) do
                local message = tostring(entry.Message or "")
                local isSellPerf = message:find("[SellPerf]", 1, true) ~= nil
                local isInventory = tostring(entry.Module or "") == "Inventory"
                    and (message:find("Sell", 1, true) ~= nil
                        or message:find("Sold", 1, true) ~= nil
                        or message:find("Merchant", 1, true) ~= nil)
                if isSellPerf or isInventory then
                    count = count + 1
                    if isSellPerf and message:find("END id=", 1, true) then
                        completed = completed + 1
                    end
                    lines[#lines + 1] = ("[%s] [%s] [%s] %s"):format(
                        tostring(entry.Time or "?"),
                        tostring(entry.Level or "INFO"),
                        tostring(entry.Module or "General"), message
                    )
                end
            end
        end
        if count == 0 then
            lines[#lines + 1] = "No Auto Sell events recorded in this runtime."
        elseif completed == 0 then
            lines[#lines + 1] = "Sale has not finished yet: wait for [SellPerf] END before copying the final measurements."
        end

        -- The sale normally finishes immediately before Server Hop. Show the
        -- last completed report saved by Farm.lua in the previous server.
        -- Never execute file contents: this is plain-text diagnostic output.
        if completed == 0 and type(readfile) == "function" then
            local savedOk, saved = pcall(readfile, "WhiteHubLastSellReport.txt")
            if savedOk and type(saved) == "string"
                and saved:find("WHITE HUB V5 - LAST COMPLETED AUTO SELL", 1, true) == 1
                and #saved <= 50000 then
                lines[#lines + 1] = ""
                lines[#lines + 1] = "LAST COMPLETED SALE (SAVED ON DEVICE / MAY BE FROM PREVIOUS SERVER)"
                lines[#lines + 1] = saved
            end
        end
        return table.concat(lines, "\n")
    end

    local function copyConsoleReport(button, idleText, report, successMessage)
        if copyToClipboard(report) then
            button.Text = "Copied!"
            runtimeLog("INFO", successMessage)
        else
            button.Text = "No clipboard"
            runtimeLog("WARN", "Clipboard API unavailable; report printed to executor console.")
            print(report)
        end
        task.delay(2, function()
            if button and button.Parent then button.Text = idleText end
        end)
    end

    copyLogBtn.MouseButton1Click:Connect(function()
        local report = _runtimeLog and _runtimeLog:GetText() or "WHITE HUB V3 - RuntimeLog unavailable"
        copyConsoleReport(copyLogBtn, "Copy All", report, "Full runtime log copied to clipboard.")
    end)

    copyWarnBtn.MouseButton1Click:Connect(function()
        copyConsoleReport(copyWarnBtn, "Copy WARN", buildFilteredRuntimeLog("WARN"), "WARN-only runtime report copied to clipboard.")
    end)

    copyErrorBtn.MouseButton1Click:Connect(function()
        copyConsoleReport(copyErrorBtn, "Copy ERROR", buildFilteredRuntimeLog("ERROR"), "ERROR-only runtime report copied to clipboard.")
    end)

    copySaleBtn.MouseButton1Click:Connect(function()
        copyConsoleReport(copySaleBtn, "Copy SALE", buildSaleRuntimeLog(), "Auto Sell diagnostic report copied to clipboard.")
    end)

    followLogBtn.MouseButton1Click:Connect(function()
        followConsole = not followConsole
        followLogBtn.Text = followConsole and "Follow: ON" or "Follow: OFF"
        if _config then _config:Set("ConsoleFollow", followConsole) end
        if followConsole then refreshConsole() end
    end)

    clearLogBtn.MouseButton1Click:Connect(function()
        if _runtimeLog then _runtimeLog:Clear() end
        refreshConsole()
    end)

    if _runtimeLog and type(_runtimeLog.Subscribe) == "function" then
        local consoleRefreshPending = false
        trackConnection(_runtimeLog:Subscribe(function()
            if consoleRefreshPending then return end
            consoleRefreshPending = true
            task.delay(0.15, function()
                consoleRefreshPending = false
                if logLabel and logLabel.Parent then
                    refreshConsole()
                end
            end)
        end))
    end

    refreshConsole()
    AutoCanvas(ConsolePage)

    -- =====================
    -- =====================
    -- WHITE AI DEBUG PAGE (NO AGENT CODE EXECUTION)
    -- =====================
    MakeSection(AIPage, "WHITE AI V1 - DIAGNOSTICS")

    MakeToggle(AIPage, "Send to AI server", _config and _config:Get("WhiteAIEnabled") == true, function(value)
        if _whiteAI then _whiteAI:SetEnabled(value) end
        runtimeLog("INFO", "WhiteAI external reports: " .. tostring(value))
    end)

    local aiStatus = Instance.new("TextLabel", AIPage)
    aiStatus.BackgroundTransparency = 1
    aiStatus.Size = UDim2.new(1, -8, 0, 72)
    aiStatus.TextWrapped = true
    aiStatus.TextYAlignment = Enum.TextYAlignment.Top
    aiStatus.TextColor3 = THEME.GOLD_WHITE
    aiStatus.TextSize = 10
    aiStatus.Font = Enum.Font.Code
    aiStatus.Text = "Local diagnostics initializing..."

    local endpointBox = Instance.new("TextBox", AIPage)
    endpointBox.Size = UDim2.new(1, -8, 0, 34)
    endpointBox.BackgroundColor3 = THEME.PANEL2
    endpointBox.BorderSizePixel = 0
    endpointBox.Font = Enum.Font.Code
    endpointBox.TextSize = 12
    endpointBox.ClearTextOnFocus = false
    endpointBox.TextColor3 = THEME.WHITE
    endpointBox.PlaceholderText = "https://your-server.example/reports"
    endpointBox.Text = _config and tostring(_config:Get("WhiteAIEndpoint") or "") or ""
    Instance.new("UICorner", endpointBox).CornerRadius = UDim.new(0, 6)

    local aiEndpointButton = Instance.new("TextButton", AIPage)
    aiEndpointButton.Size = UDim2.new(1, -8, 0, 32)
    aiEndpointButton.Text = "SAVE HTTPS ENDPOINT"
    aiEndpointButton.Font = Enum.Font.GothamBold
    aiEndpointButton.TextSize = 12
    styleActionButton(aiEndpointButton, false)
    trackConnection(aiEndpointButton.MouseButton1Click:Connect(function()
        if not _whiteAI then return end
        local ok, why = _whiteAI:SetEndpoint(endpointBox.Text)
        aiStatus.Text = ok and "HTTPS backend address saved." or tostring(why)
    end))

    local keyBox = Instance.new("TextBox", AIPage)
    keyBox.Size = UDim2.new(1, -8, 0, 34)
    keyBox.BackgroundColor3 = THEME.PANEL2
    keyBox.BorderSizePixel = 0
    keyBox.Font = Enum.Font.Code
    keyBox.TextSize = 12
    keyBox.TextColor3 = THEME.WHITE
    keyBox.ClearTextOnFocus = false
    keyBox.PlaceholderText = "Report ingestion key (session only)"
    keyBox.Text = ""
    Instance.new("UICorner", keyBox).CornerRadius = UDim.new(0, 6)

    local aiKeyButton = Instance.new("TextButton", AIPage)
    aiKeyButton.Size = UDim2.new(1, -8, 0, 32)
    aiKeyButton.Text = "USE INGEST KEY FOR THIS SESSION"
    aiKeyButton.Font = Enum.Font.GothamBold
    aiKeyButton.TextSize = 12
    styleActionButton(aiKeyButton, false)
    trackConnection(aiKeyButton.MouseButton1Click:Connect(function()
        if not _whiteAI then return end
        local ok, why = _whiteAI:SetIngestKey(keyBox.Text)
        keyBox.Text = "" -- do not persist or show authentication value
        aiStatus.Text = ok and "Ingestion key stored in memory for this session." or tostring(why)
    end))

    -- Owner-only dev: never persist admin credential in public Config or logs.
    local adminBox = Instance.new("TextBox", AIPage)
    adminBox.Size = UDim2.new(1, -8, 0, 34)
    adminBox.BackgroundColor3 = THEME.PANEL2
    adminBox.BorderSizePixel = 0
    adminBox.Font = Enum.Font.Code
    adminBox.TextSize = 12
    adminBox.TextColor3 = THEME.WHITE
    adminBox.ClearTextOnFocus = false
    adminBox.PlaceholderText = "Owner admin key (private dev only, optional)"
    adminBox.Text = ""
    Instance.new("UICorner", adminBox).CornerRadius = UDim.new(0, 6)

    local aiAdminButton = Instance.new("TextButton", AIPage)
    aiAdminButton.Size = UDim2.new(1, -8, 0, 32)
    aiAdminButton.Text = "PAIR THIS DEVICE"
    aiAdminButton.Font = Enum.Font.GothamBold
    aiAdminButton.TextSize = 12
    styleActionButton(aiAdminButton, false)
    trackConnection(aiAdminButton.MouseButton1Click:Connect(function()
        if not _whiteAI or type(_whiteAI.PairDevice) ~= "function" then return end
        local credential = adminBox.Text
        adminBox.Text = ""
        local ok, why = _whiteAI:PairDevice(credential)
        credential = nil
        adminBox.Text = "" -- key exists only in private session memory
        aiStatus.Text = tostring(why or (ok and "Authorized." or "Not authorized."))
    end))

    local aiCopyButton = Instance.new("TextButton", AIPage)
    aiCopyButton.Size = UDim2.new(1, -8, 0, 32)
    aiCopyButton.Text = "COPY SANITIZED DIAGNOSTIC"
    aiCopyButton.Font = Enum.Font.GothamBold
    aiCopyButton.TextSize = 12
    styleActionButton(aiCopyButton, false)
    trackConnection(aiCopyButton.MouseButton1Click:Connect(function()
        if not _whiteAI then return end
        local report = _whiteAI:BuildReport("manual_diagnostic", "Manual investigation requested", "General")
        local success = copyToClipboard(HttpService:JSONEncode(report))
        aiStatus.Text = success and "Diagnostic copied (no account token)." or "Clipboard unavailable."
    end))

    local aiSendButton = Instance.new("TextButton", AIPage)
    aiSendButton.Size = UDim2.new(1, -8, 0, 32)
    aiSendButton.Text = "SEND REPORT TO AI BACKEND"
    aiSendButton.Font = Enum.Font.GothamBold
    aiSendButton.TextSize = 12
    styleActionButton(aiSendButton, true)
    trackConnection(aiSendButton.MouseButton1Click:Connect(function()
        if not _whiteAI then return end
        local ok, reason = _whiteAI:SendManualReport()
        aiStatus.Text = ok and "Report received; checking backend job status..." or tostring(reason)
    end))

    for _, action in ipairs({
        {label = "RECOVER SAVED INCIDENTS", method = "RecoverSavedIncidents"},
        {label = "RETRY LAST INCIDENT", method = "RetryLastJob"},
    }) do
        local actionButton = Instance.new("TextButton", AIPage)
        actionButton.Size = UDim2.new(1, -8, 0, 32)
        actionButton.Text = action.label
        actionButton.Font = Enum.Font.GothamBold
        actionButton.TextSize = 12
        styleActionButton(actionButton, false)
        local method = action.method
        trackConnection(actionButton.MouseButton1Click:Connect(function()
            if not _whiteAI or type(_whiteAI[method]) ~= "function" then return end
            local _, reason = _whiteAI[method](_whiteAI)
            aiStatus.Text = tostring(reason)
        end))
    end

    local aiCopyProposal = Instance.new("TextButton", AIPage)
    aiCopyProposal.Size = UDim2.new(1, -8, 0, 32)
    aiCopyProposal.Text = "COPY LATEST PROPOSAL LINK"
    aiCopyProposal.Font = Enum.Font.GothamBold
    aiCopyProposal.TextSize = 12
    styleActionButton(aiCopyProposal, false)
    trackConnection(aiCopyProposal.MouseButton1Click:Connect(function()
        if not _whiteAI then return end
        local status = _whiteAI:GetStatus()
        local url = status and status.proposal_url
        if type(url) ~= "string" or not url:match("^https://github%.com/") then
            aiStatus.Text = "No completed GitHub proposal in this session."
            return
        end
        aiStatus.Text = copyToClipboard(url) and "Proposal URL copied." or "Clipboard unavailable."
    end))

    task.spawn(function()
        while aiStatus.Parent do
            task.wait(3)
            if not aiStatus.Parent then break end
            if _whiteAI and type(_whiteAI.GetStatus) == "function" then
                local status = _whiteAI:GetStatus()
                local lines = {
                    tostring(status.message or "Ready"),
                    "Detected incidents: " .. tostring(status.incidents or 0)
                        .. " | External reports: " .. (status.enabled and "ON" or "OFF"),
                }
                local jobs = status.jobs or {}
                for i = 1, math.min(1, #jobs) do
                    local job = jobs[i]
                    if type(job) == "table" then
                        local confidence = type(job.confidence) == "number"
                            and (" confidence=" .. string.format("%.2f", job.confidence)) or ""
                        lines[#lines + 1] = ("Job %d: %s | %s%s"):format(
                            i, tostring(job.module or "-"), tostring(job.status or "?"), confidence)
                        if i == 1 and type(job.diagnosis) == "string" and job.diagnosis ~= "" then
                            lines[#lines + 1] = "Diagnosis: " .. job.diagnosis:sub(1, 80)
                        end
                    end
                end
                aiStatus.Text = table.concat(lines, "\n")
            end
        end
    end)
    AutoCanvas(AIPage)

    -- CREDITS PAGE
    -- =====================
    MakeSection(CreditsPage, "WHITE HUB")
    local creditLabel = Instance.new("TextLabel")
    creditLabel.Size             = UDim2.new(1,-4,0,44)
    creditLabel.BackgroundColor3 = THEME.PANEL
    creditLabel.BorderSizePixel  = 0
    creditLabel.Text             = "WHITE HUB V5  •  " .. UI_BUILD .. "  •  WHITE DRAGON"
    creditLabel.TextColor3       = THEME.WHITE
    creditLabel.TextScaled       = false
    creditLabel.TextSize         = 12
    creditLabel.Font             = Enum.Font.GothamBold
    creditLabel.Parent           = CreditsPage
    Instance.new("UICorner", creditLabel).CornerRadius = UDim.new(0,7)
    local creditStroke = Instance.new("UIStroke", creditLabel)
    creditStroke.Color = THEME.GOLD_EDGE
    local discordBtn = Instance.new("TextButton")
    discordBtn.Size             = UDim2.new(1,-4,0,36)
    discordBtn.BackgroundColor3 = THEME.GOLD_DARK
    discordBtn.BorderSizePixel  = 0
    discordBtn.Text             = "DISCORD  //  discord.gg/j3C4Xa6DzN"
    discordBtn.TextColor3       = THEME.WHITE
    discordBtn.TextScaled       = false
    discordBtn.TextSize         = 12
    discordBtn.Font             = Enum.Font.GothamBold
    discordBtn.Parent           = CreditsPage
    Instance.new("UICorner", discordBtn).CornerRadius = UDim.new(0,7)
    styleActionButton(discordBtn, true)
    discordBtn.MouseEnter:Connect(function()
        TweenService:Create(discordBtn, TweenInfo.new(0.15), {BackgroundColor3=THEME.GOLD_BRIGHT}):Play()
    end)
    discordBtn.MouseLeave:Connect(function()
        TweenService:Create(discordBtn, TweenInfo.new(0.15), {BackgroundColor3=THEME.GOLD}):Play()
    end)
    discordBtn.MouseButton1Click:Connect(function()
        pcall(function() setclipboard("https://discord.gg/j3C4Xa6DzN") end)
        local orig = discordBtn.Text
        discordBtn.Text = "✅ Copied!"
        TweenService:Create(discordBtn, TweenInfo.new(0.15), {BackgroundColor3=THEME.GREEN}):Play()
        task.delay(2, function()
            discordBtn.Text = orig
            TweenService:Create(discordBtn, TweenInfo.new(0.15), {BackgroundColor3=THEME.GOLD}):Play()
        end)
    end)
    AutoCanvas(CreditsPage)

    -- =====================
    -- TOGGLE BUTTON
    -- =====================
    local ToggleBtn = Instance.new("TextButton", ScreenGui)
    ToggleBtn.BackgroundColor3 = THEME.PANEL
    ToggleBtn.BorderSizePixel = 0
    ToggleBtn.Position = UDim2.new(0, 10, 1, -276)
    ToggleBtn.Size = UDim2.new(0, 108, 0, 30)
    ToggleBtn.Text = ""
    ToggleBtn.AutoButtonColor = false
    ToggleBtn.Font = Enum.Font.GothamBold
    Instance.new("UICorner", ToggleBtn).CornerRadius = UDim.new(0, 8)
    addGradient(ToggleBtn, THEME.PANEL2, THEME.BG2, 90)
    local tStroke = addStroke(ToggleBtn, THEME.GOLD_EDGE, 1.15, 0.25)
    pulseStroke(tStroke, THEME.GOLD_BRIGHT, THEME.GOLD_EDGE)

    local launcherBolt = Instance.new("TextLabel", ToggleBtn)
    launcherBolt.BackgroundTransparency = 1
    launcherBolt.Position = UDim2.new(0, 7, 0, 0)
    launcherBolt.Size = UDim2.new(0, 20, 1, 0)
    launcherBolt.Text = "⚡"
    launcherBolt.TextColor3 = THEME.GOLD_BRIGHT
    launcherBolt.TextSize = 14
    launcherBolt.Font = Enum.Font.GothamBold

    local launcherText = Instance.new("TextLabel", ToggleBtn)
    launcherText.BackgroundTransparency = 1
    launcherText.Position = UDim2.new(0, 28, 0, 0)
    launcherText.Size = UDim2.new(1, -34, 1, 0)
    launcherText.Text = "WHITE DEV"
    launcherText.TextColor3 = THEME.WHITE
    launcherText.TextSize = 11
    launcherText.Font = Enum.Font.GothamBold
    launcherText.TextXAlignment = Enum.TextXAlignment.Left

    ToggleBtn.MouseEnter:Connect(function()
        TweenService:Create(ToggleBtn, TweenInfo.new(0.14), {BackgroundColor3 = THEME.PANEL3}):Play()
        TweenService:Create(launcherBolt, TweenInfo.new(0.14), {TextColor3 = THEME.GOLD_WHITE}):Play()
    end)
    ToggleBtn.MouseLeave:Connect(function()
        TweenService:Create(ToggleBtn, TweenInfo.new(0.14), {BackgroundColor3 = THEME.PANEL}):Play()
        TweenService:Create(launcherBolt, TweenInfo.new(0.14), {TextColor3 = THEME.GOLD_BRIGHT}):Play()
    end)

    local isOpen = false
    local function ToggleWindow()
        isOpen = not isOpen
        if not isOpen and _choices then _choices:Close() end
        if isOpen then
            MainFrame.Visible = true
            MainFrame.Size = UDim2.new(0,0,0,0)
            MainFrame.Position = UDim2.new(0.5,0,0.44,0)
            TweenService:Create(MainFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
                Size = UDim2.new(0,W,0,H),
                Position = UDim2.new(0.5,0,0.44,0),
            }):Play()
        else
            local t = TweenService:Create(MainFrame, TweenInfo.new(0.15, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
                Size = UDim2.new(0,0,0,0),
                Position = UDim2.new(0.5,0,0.44,0),
            })
            t:Play()
            t.Completed:Connect(function() MainFrame.Visible = false end)
        end
    end

    ToggleBtn.MouseButton1Click:Connect(ToggleWindow)
    -- Private dev-only AI launcher: visible even if the sidebar has been scrolled.
    local aiQuick=Instance.new("TextButton",ScreenGui)
    aiQuick.Name="WhiteAIQuickLauncher"
    aiQuick.Size=UDim2.new(0,60,0,30)
    aiQuick.Position=UDim2.new(0,125,1,-276)
    aiQuick.BackgroundColor3=THEME.PANEL2
    aiQuick.TextColor3=THEME.GOLD_BRIGHT
    aiQuick.Text="AI DEBUG"
    aiQuick.TextSize=10
    aiQuick.Font=Enum.Font.GothamBold
    aiQuick.BorderSizePixel=0
    Instance.new("UICorner",aiQuick).CornerRadius=UDim.new(0,8)
    aiQuick.MouseButton1Click:Connect(function()
        if not isOpen then ToggleWindow() end
        SetActiveTab(AIPage)
        Sidebar.CanvasPosition=Vector2.new(0,0)
        runtimeLog("INFO","[Dev UI] WhiteAI quick launcher opened AI DEBUG page.")
    end)
    runtimeLog("INFO","[Dev UI] WhiteAI quick launcher ready; private dev module="..tostring(_whiteAI~=nil))

    CloseButton.MouseButton1Click:Connect(function() if isOpen then ToggleWindow() end end)

    trackConnection(UserInputService.InputBegan:Connect(function(input, gp)
        if gp then return end
        if input.KeyCode == Enum.KeyCode.RightAlt then ToggleWindow()
        elseif input.KeyCode == Enum.KeyCode.RightControl then
            ToggleBtn.Visible = not ToggleBtn.Visible
        end
    end))

    local dragging, dragStart, startPos = false, nil, nil
    TopBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = MainFrame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    trackConnection(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))

    if _compactUI then
        for _,page in ipairs({FarmPage,StandPage,ItemsPage,QuestPage,TeleportPage,SettingsPage,EventsPage,AIPage}) do
            _compactUI:Arrange(page,trackConnection,THEME)
        end
    end

    -- Restore a persisted combat mode, resolving old configs that had both enabled.
    if _config then
        if _config:Get("QuestFarmEnabled") then
            _config:Set("NPCFarmEnabled", false)
            UI:SetToggleValue("NPC Farm", false)
            if _combatFarm then _combatFarm:StartQuest() end
        elseif _config:Get("NPCFarmEnabled") then
            if _combatFarm then _combatFarm:StartNPC() end
        end
    end
end

function UI:Notify(msg) print("[UI] " .. tostring(msg)) end

function UI:SetVisible(value)
    if mainScreenGui then
        mainScreenGui.Enabled = value == true
    end
end

function UI:Destroy()
    if _choices then _choices:Close() end
    if activeSkillCapture then
        pcall(function() activeSkillCapture:Disconnect() end)
        activeSkillCapture = nil
    end
    for _, connection in ipairs(uiConnections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(uiConnections)
    if dropdownContainer then
        pcall(function() dropdownContainer:Destroy() end)
        dropdownContainer = nil
    end
    if mainScreenGui then
        pcall(function() mainScreenGui:Destroy() end)
        mainScreenGui = nil
    end
    toggleObjects = {}
end

return UI
