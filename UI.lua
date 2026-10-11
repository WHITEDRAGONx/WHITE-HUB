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

local UI_BUILD = "FUTURE-GOLD-2026.09.14-R4-CONSOLE-FILTERS"
UI.Build = UI_BUILD

local THEME = {
    BG = Color3.fromRGB(6, 7, 10),
    BG2 = Color3.fromRGB(10, 11, 15),
    PANEL = Color3.fromRGB(14, 15, 20),
    PANEL2 = Color3.fromRGB(20, 21, 28),
    PANEL3 = Color3.fromRGB(27, 28, 36),
    WHITE = Color3.fromRGB(248, 249, 252),
    MUTED = Color3.fromRGB(170, 174, 184),
    MUTED2 = Color3.fromRGB(112, 116, 128),
    GOLD = Color3.fromRGB(255, 195, 35),
    GOLD_BRIGHT = Color3.fromRGB(255, 224, 104),
    GOLD_WHITE = Color3.fromRGB(255, 244, 188),
    GOLD_DARK = Color3.fromRGB(130, 88, 10),
    GOLD_EDGE = Color3.fromRGB(190, 132, 16),
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
local _webhook     = nil
local _combatFarm  = nil
local _serverHop   = nil
local _whiteAI     = nil
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
    _webhook     = Modules.Webhook
    _combatFarm  = Modules.CombatFarm
    _serverHop   = Modules.ServerHop
    _whiteAI    = Modules.WhiteAI
    _runtimeLog  = Modules.RuntimeLog
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
    t1.Text = "WHITE HUB  //  V3"
    t1.TextColor3 = THEME.WHITE
    t1.TextSize = 15
    t1.Font = Enum.Font.GothamBold
    t1.TextXAlignment = Enum.TextXAlignment.Left

    local t2 = Instance.new("TextLabel", frame)
    t2.Size = UDim2.new(1, -24, 0, 17)
    t2.Position = UDim2.new(0, 17, 0, 30)
    t2.BackgroundTransparency = 1
    t2.Text = "FUTURE GOLD • " .. UI_BUILD
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
        scroll.CanvasSize = UDim2.new(0,0,0, list.AbsoluteContentSize.Y + 10)
    end
    update()
    list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(update)
end

local function MakeSection(parent, text)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, -4, 0, 26)
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
    lbl.Text = text
    lbl.TextColor3 = THEME.GOLD_BRIGHT
    lbl.TextSize = 11
    lbl.Font = Enum.Font.GothamBold
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = frame
end

local function MakeToggle(parent, labelText, default, onChanged)
    local holder = Instance.new("Frame")
    holder.Size             = UDim2.new(1,-4,0,32)
    holder.BackgroundColor3 = THEME.PANEL
    holder.BorderSizePixel  = 0
    holder.Parent           = parent
    Instance.new("UICorner", holder).CornerRadius = UDim.new(0,7)
    local stroke = Instance.new("UIStroke", holder)
    stroke.Color = THEME.GOLD_EDGE
    stroke.Transparency = 0.48
    stroke.Thickness = 1

    local lbl = Instance.new("TextLabel")
    lbl.Size             = UDim2.new(0.65,0,1,0)
    lbl.Position         = UDim2.new(0,8,0,0)
    lbl.BackgroundTransparency = 1
    lbl.Text             = labelText
    lbl.TextColor3       = THEME.WHITE
    lbl.TextScaled       = true
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
    lbl.TextSize = 14
    lbl.Font = Enum.Font.Gotham
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = parent
    return lbl
end

local function ensureDropdownContainer()
    if not dropdownContainer or not dropdownContainer.Parent then
        dropdownContainer = Instance.new("ScreenGui")
        dropdownContainer.Name = "DropdownContainer"
        dropdownContainer.ResetOnSpawn = false
        dropdownContainer.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        dropdownContainer.Parent = PlayerGui
    end
    return dropdownContainer
end

-- Styled dropdown with auto-close on selection (versão corrigida)
local function MakeStyledDropdown(parent, labelText, options, callback)
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1,-4,0,36)
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
    lbl.Text = labelText
    lbl.TextColor3 = THEME.WHITE
    lbl.TextScaled = true
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
    dropdownBtn.TextSize = 14
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
        menu.ScrollBarThickness = 5
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
        local height = math.min(math.max(count, 1) * 32, 150)
        menu.Size = UDim2.new(0, 200, 0, height)
        menu.CanvasSize = UDim2.new(0,0,0,count * 32)
        local btnAbsPos = dropdownBtn.AbsolutePosition
        local btnSize = dropdownBtn.AbsoluteSize
        menu.Position = UDim2.new(0, btnAbsPos.X, 0, btnAbsPos.Y + btnSize.Y)

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

    local W, H = 410, 338

    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "WhiteHubV3"
    mainScreenGui = ScreenGui
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ScreenGui.ResetOnSpawn   = false
    ScreenGui.Parent         = PlayerGui

    local MainFrame = Instance.new("Frame", ScreenGui)
    MainFrame.Name             = "MainFrame"
    MainFrame.BackgroundColor3 = THEME.BG
    MainFrame.BorderSizePixel  = 0
    MainFrame.Position         = UDim2.new(0.5,-W/2,0.5,-H/2)
    MainFrame.Size             = UDim2.new(0,W,0,H)
    MainFrame.Visible          = false
    Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0,12)
    local mfStroke = addStroke(MainFrame, THEME.GOLD_EDGE, 1.25, 0.24)
    addGradient(MainFrame, THEME.BG, THEME.BG2, 90)
    pulseStroke(mfStroke, THEME.GOLD_BRIGHT, THEME.GOLD_EDGE)

    local TopBar = Instance.new("Frame", MainFrame)
    TopBar.Name             = "TopBar"
    TopBar.BackgroundColor3 = THEME.PANEL
    TopBar.BorderSizePixel  = 0
    TopBar.Size             = UDim2.new(1,0,0,43)
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
    Title.Text = "WHITE HUB"
    Title.TextColor3 = THEME.WHITE
    Title.TextSize = 18
    Title.Font = Enum.Font.GothamBold
    Title.TextXAlignment = Enum.TextXAlignment.Left

    local versionLabel = Instance.new("TextLabel", TopBar)
    versionLabel.BackgroundTransparency = 1
    versionLabel.Position = UDim2.new(0, 145, 0, 1)
    versionLabel.Size = UDim2.new(0, 94, 1, -2)
    versionLabel.Text = "// V3 GOLD"
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

    local Sidebar = Instance.new("Frame", MainFrame)
    Sidebar.BackgroundTransparency = 1
    Sidebar.BorderSizePixel        = 0
    Sidebar.Position               = UDim2.new(0,7,0,48)
    Sidebar.Size                   = UDim2.new(0,104,1,-56)
    local sideLayout = Instance.new("UIListLayout", Sidebar)
    sideLayout.Padding   = UDim.new(0,5)
    sideLayout.SortOrder = Enum.SortOrder.LayoutOrder

    local PagesFrame = Instance.new("Frame", MainFrame)
    PagesFrame.BackgroundTransparency = 1
    PagesFrame.BorderSizePixel        = 0
    PagesFrame.Position               = UDim2.new(0,118,0,48)
    PagesFrame.Size                   = UDim2.new(1,-128,1,-56)

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
        return scroll
    end

    local FarmPage    = MakePage("FarmPage")
    local ItemsPage   = MakePage("ItemsPage")
    local QuestPage   = MakePage("QuestPage")
    local WebhookPage = MakePage("WebhookPage")
    local ConsolePage = MakePage("ConsolePage")
    local AIPage      = MakePage("AIPage")
    local CreditsPage = MakePage("CreditsPage")
    FarmPage.Visible = true

    local tabDefs = {
        { name="Farm",    page=FarmPage    },
        { name="Items",   page=ItemsPage   },
        { name="Combat", page=QuestPage },
        { name="Webhook", page=WebhookPage },
        { name="Console", page=ConsolePage },
        { name="AI DEBUG", page=AIPage },
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
        btn.Size             = UDim2.new(1,0,0,36)
        btn.Text             = def.name
        btn.TextColor3       = C_Text
        btn.TextSize         = 12
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

    do
        local s = tabButtons["Farm"]:FindFirstChildOfClass("UIStroke")
        tabButtons["Farm"].BackgroundColor3 = C_BG3
        tabButtons["Farm"].TextColor3 = THEME.WHITE
        if tabIndicators["Farm"] then tabIndicators["Farm"].Visible = true end
        if s then s.Color = C_StrokeAct; s.Transparency = 0.05 end
    end

    -- =====================
    -- FARM PAGE
    -- =====================
    MakeSection(FarmPage, "FARM SETTINGS")
    
    MakeToggle(FarmPage, "Enable Farm", _config and _config:Get("FarmEnabled"), function(v)
        if _config then _config:Set("FarmEnabled", v) end
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
        if _config then
            if v then
                _config:SetMany({ AutoPrestige = true, QuestFarmEnabled = false, NPCFarmEnabled = false })
            else
                _config:Set("AutoPrestige", false)
            end
        end
        getgenv().AutoPrestigeEnabled = v
        if v then
            UI:SetToggleValue("Quest Farm", false)
            UI:SetToggleValue("NPC Farm", false)
            if _combatFarm then _combatFarm:Stop() end
            print("[UI] Auto Prestige enabled.")
            runtimeLog("INFO", "Auto Prestige enabled.")
        else
            print("[UI] Auto Prestige disabled.")
            runtimeLog("INFO", "Auto Prestige disabled.")
        end
    end)

    AutoCanvas(FarmPage)

    -- =====================
    -- ITEMS PAGE
    -- =====================
    MakeSection(ItemsPage, "SELL ITEMS")
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
    local questDropdown = MakeStyledDropdown(QuestPage, "Select Quest", questList, function(selected)
        if _config then _config:Set("SelectedQuest", selected) end
    end)
    local savedQuest = _config and _config:Get("SelectedQuest")
    if savedQuest and savedQuest ~= "" and table.find(questList, savedQuest) then
        questDropdown.Text = savedQuest
    end
    
    -- Quest/NPC are mutually exclusive and CombatFarm enforces one worker.
    MakeToggle(QuestPage, "Quest Farm", _config and _config:Get("QuestFarmEnabled"), function(v)
        if _config then
            if v then
                _config:SetMany({ QuestFarmEnabled = true, NPCFarmEnabled = false, AutoPrestige = false })
            else
                _config:Set("QuestFarmEnabled", false)
            end
        end
        if v then
            getgenv().AutoPrestigeEnabled = false
            UI:SetToggleValue("NPC Farm", false)
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
        if _config then
            if v then
                _config:SetMany({ NPCFarmEnabled = true, QuestFarmEnabled = false, AutoPrestige = false })
            else
                _config:Set("NPCFarmEnabled", false)
            end
        end
        if v then
            getgenv().AutoPrestigeEnabled = false
            UI:SetToggleValue("Quest Farm", false)
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
    
    AutoCanvas(QuestPage)

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
    resetBtn.TextScaled = true
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
            logLabel.Size = UDim2.new(1,-8,0,height)
            logScroll.CanvasSize = UDim2.new(0,0,0,height + 6)
            logScroll.CanvasPosition = Vector2.new(0, math.max(0, height - logScroll.AbsoluteSize.Y))
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
    -- WHITE AI DEBUG PAGE (NO AGENT CODE EXECUTION)
    -- =====================
    MakeSection(AIPage, "WHITE AI V1 - DIAGNOSTICS")

    local aiDescription = Instance.new("TextLabel", AIPage)
    aiDescription.BackgroundTransparency = 1
    aiDescription.Size = UDim2.new(1, -8, 0, 55)
    aiDescription.TextWrapped = true
    aiDescription.TextYAlignment = Enum.TextYAlignment.Top
    aiDescription.TextColor3 = THEME.MUTED
    aiDescription.TextSize = 12
    aiDescription.Font = Enum.Font.Gotham
    aiDescription.Text = "Local error detection is always on. External AI and draft patch proposals are OFF until you configure an HTTPS backend."
    aiDescription.LayoutOrder = 1

    MakeToggle(AIPage, "Send to AI server", _config and _config:Get("WhiteAIEnabled") == true, function(value)
        if _whiteAI then _whiteAI:SetEnabled(value) end
        runtimeLog("INFO", "WhiteAI external reports: " .. tostring(value))
    end)

    local aiStatus = Instance.new("TextLabel", AIPage)
    aiStatus.BackgroundTransparency = 1
    aiStatus.Size = UDim2.new(1, -8, 0, 152)
    aiStatus.TextWrapped = true
    aiStatus.TextYAlignment = Enum.TextYAlignment.Top
    aiStatus.TextColor3 = THEME.GOLD_WHITE
    aiStatus.TextSize = 12
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
    aiAdminButton.Text = "AUTHORIZE PRIVATE DEV AUTO-PATCH"
    aiAdminButton.Font = Enum.Font.GothamBold
    aiAdminButton.TextSize = 12
    styleActionButton(aiAdminButton, false)
    trackConnection(aiAdminButton.MouseButton1Click:Connect(function()
        if not _whiteAI or type(_whiteAI.SetAdminKey) ~= "function" then return end
        local ok, why = _whiteAI:SetAdminKey(adminBox.Text)
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
                for i = 1, math.min(2, #jobs) do
                    local job = jobs[i]
                    if type(job) == "table" then
                        local confidence = type(job.confidence) == "number"
                            and (" confidence=" .. string.format("%.2f", job.confidence)) or ""
                        lines[#lines + 1] = ("Job %d: %s | %s%s"):format(
                            i, tostring(job.module or "-"), tostring(job.status or "?"), confidence)
                        if i == 1 and type(job.diagnosis) == "string" and job.diagnosis ~= "" then
                            lines[#lines + 1] = "Diagnosis: " .. job.diagnosis:sub(1, 140)
                        end
                    end
                end
                aiStatus.Text = table.concat(lines, "\n")
            end
        end
    end)
    AutoCanvas(AIPage)

    -- =====================
    -- CREDITS PAGE
    -- =====================
    MakeSection(CreditsPage, "WHITE HUB")
    local creditLabel = Instance.new("TextLabel")
    creditLabel.Size             = UDim2.new(1,-4,0,44)
    creditLabel.BackgroundColor3 = THEME.PANEL
    creditLabel.BorderSizePixel  = 0
    creditLabel.Text             = "WHITE HUB V3  •  " .. UI_BUILD .. "  •  WHITE DRAGON"
    creditLabel.TextColor3       = THEME.WHITE
    creditLabel.TextScaled       = true
    creditLabel.Font             = Enum.Font.GothamBold
    creditLabel.Parent           = CreditsPage
    Instance.new("UICorner", creditLabel).CornerRadius = UDim.new(0,7)
    local creditStroke = Instance.new("UIStroke", creditLabel)
    creditStroke.Color = THEME.GOLD_EDGE
    local discordBtn = Instance.new("TextButton")
    discordBtn.Size             = UDim2.new(1,-4,0,36)
    discordBtn.BackgroundColor3 = THEME.GOLD_DARK
    discordBtn.BorderSizePixel  = 0
    discordBtn.Text             = "DISCORD  //  discord.gg/Qwd23ZRNxJ"
    discordBtn.TextColor3       = THEME.WHITE
    discordBtn.TextScaled       = true
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
        pcall(function() setclipboard("https://discord.gg/Qwd23ZRNxJ") end)
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
    launcherText.Text = "WHITE HUB"
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
        if isOpen then
            MainFrame.Visible = true
            MainFrame.Size = UDim2.new(0,0,0,0)
            MainFrame.Position = UDim2.new(0.5,0,0.5,0)
            TweenService:Create(MainFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
                Size = UDim2.new(0,W,0,H),
                Position = UDim2.new(0.5,-W/2,0.5,-H/2),
            }):Play()
        else
            local t = TweenService:Create(MainFrame, TweenInfo.new(0.15, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
                Size = UDim2.new(0,0,0,0),
                Position = UDim2.new(0.5,0,0.5,0),
            })
            t:Play()
            t.Completed:Connect(function() MainFrame.Visible = false end)
        end
    end

    ToggleBtn.MouseButton1Click:Connect(ToggleWindow)
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
