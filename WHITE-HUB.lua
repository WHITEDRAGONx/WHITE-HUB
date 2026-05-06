repeat task.wait(1) until game:IsLoaded()

print("Script Loading...")
warn("Script Loading...")

wait(6)

print("WHITE HUB Loaded!")
warn("WHITE HUB Loaded!")

wait(2)

-- =====================
-- LOAD / SAVE CONFIG
-- =====================
local HttpService = game:GetService("HttpService")
local CONFIG_FILE = "WhiteHubConfig.json"

local DefaultConfig = {
    BuyLucky = true,
    AutoSell = true,
    WebhookURL = "",
    SellItems = {
        ["Gold Coin"] = true,
        ["Rokakaka"] = true,
        ["Pure Rokakaka"] = true,
        ["Mysterious Arrow"] = true,
        ["Diamond"] = true,
        ["Ancient Scroll"] = true,
        ["Caesar's Headband"] = true,
        ["Stone Mask"] = true,
        ["Rib Cage of The Saint's Corpse"] = true,
        ["Quinton's Glove"] = true,
        ["Zeppeli's Hat"] = true,
        ["Lucky Arrow"] = false,
        ["Lucky Stone Mask"] = false,
        ["Clackers"] = true,
        ["Steel Ball"] = true,
        ["Dio's Diary"] = true
    }
}

local function LoadConfig()
    if not getgenv().WHConfig then
        local success, data = pcall(function()
            if isfile(CONFIG_FILE) then
                return HttpService:JSONDecode(readfile(CONFIG_FILE))
            end
        end)
        if success and data then
            for k, v in pairs(DefaultConfig.SellItems) do
                if data.SellItems[k] == nil then
                    data.SellItems[k] = v
                end
            end
            if data.WebhookURL == nil then data.WebhookURL = "" end
            getgenv().WHConfig = data
        else
            getgenv().WHConfig = {
                BuyLucky = DefaultConfig.BuyLucky,
                AutoSell = DefaultConfig.AutoSell,
                WebhookURL = "",
                SellItems = {}
            }
            for k, v in pairs(DefaultConfig.SellItems) do
                getgenv().WHConfig.SellItems[k] = v
            end
        end
    end
end

local function SaveConfig()
    pcall(function()
        writefile(CONFIG_FILE, HttpService:JSONEncode(getgenv().WHConfig))
    end)
end

LoadConfig()

local BuyLucky  = getgenv().WHConfig.BuyLucky
local AutoSell  = getgenv().WHConfig.AutoSell
local SellItems = getgenv().WHConfig.SellItems

-- =====================
-- SERVICES
-- =====================
local Workspace          = game:GetService("Workspace")
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService       = game:GetService("TweenService")
local UserInputService   = game:GetService("UserInputService")
local TeleportService    = game:GetService("TeleportService")
local CoreGui            = game:GetService("CoreGui")

local Player    = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- =====================
-- WEBHOOK
-- =====================
local function SendWebhook(message)
    local url = getgenv().WHConfig.WebhookURL
    if not url or url == "" then return end
    pcall(function()
        local body = HttpService:JSONEncode({
            content = nil,
            embeds = {{
                title = "WHITE HUB — Notification",
                description = message,
                color = 3447003,
                footer = { text = "WHITE HUB by WHITE DRAGON" },
                timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
            }}
        })
        local req = http_request or request or syn and syn.request
        if req then
            req({ Url = url, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = body })
        end
    end)
end

-- =====================
-- XENON STYLE COLORS
-- =====================
local C = {
    BG        = Color3.fromRGB(22, 29, 33),
    BG2       = Color3.fromRGB(28, 37, 42),
    BG3       = Color3.fromRGB(34, 46, 52),
    Stroke    = Color3.fromRGB(44, 58, 66),
    StrokeHov = Color3.fromRGB(65, 86, 97),
    StrokeAct = Color3.fromRGB(84, 111, 126),
    Text      = Color3.fromRGB(210, 220, 225),
    TextDim   = Color3.fromRGB(120, 145, 158),
    Green     = Color3.fromRGB(50, 180, 80),
    Red       = Color3.fromRGB(180, 50, 50),
    White     = Color3.fromRGB(255, 255, 255),
}

-- =====================
-- CREDITS POP UP
-- =====================
local CreditsGui = Instance.new("ScreenGui")
CreditsGui.Parent = PlayerGui
CreditsGui.ResetOnSpawn = false

local CreditsFrame = Instance.new("Frame")
CreditsFrame.Size = UDim2.new(0, 155, 0, 46)
CreditsFrame.Position = UDim2.new(0, -165, 1, -160)
CreditsFrame.BackgroundColor3 = C.BG2
CreditsFrame.BackgroundTransparency = 0.05
CreditsFrame.BorderSizePixel = 0
CreditsFrame.Parent = CreditsGui
Instance.new("UICorner", CreditsFrame).CornerRadius = UDim.new(0, 8)
local cs = Instance.new("UIStroke", CreditsFrame)
cs.Color = C.Stroke cs.Transparency = 0 cs.Thickness = 1.2

local ct = Instance.new("TextLabel", CreditsFrame)
ct.Size = UDim2.new(1,-10,0.52,0) ct.Position = UDim2.new(0,8,0,2)
ct.BackgroundTransparency = 1 ct.Text = "WHITE HUB"
ct.TextColor3 = C.White ct.TextScaled = true
ct.Font = Enum.Font.GothamBold ct.TextXAlignment = Enum.TextXAlignment.Left

local cl = Instance.new("TextLabel", CreditsFrame)
cl.Size = UDim2.new(1,-10,0.42,0) cl.Position = UDim2.new(0,8,0.55,0)
cl.BackgroundTransparency = 1 cl.Text = "by WHITE DRAGON"
cl.TextColor3 = C.TextDim cl.TextScaled = true
cl.Font = Enum.Font.Gotham cl.TextXAlignment = Enum.TextXAlignment.Left

TweenService:Create(CreditsFrame, TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
    Position = UDim2.new(0, 8, 1, -160)
}):Play()
task.delay(5, function()
    local so = TweenService:Create(CreditsFrame, TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
        Position = UDim2.new(0, -165, 1, -160)
    })
    so:Play()
    so.Completed:Connect(function() CreditsGui:Destroy() end)
end)

-- =====================
-- MAIN UI
-- =====================
local MainGui = Instance.new("ScreenGui")
MainGui.Parent = PlayerGui
MainGui.ResetOnSpawn = false
MainGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Size = UDim2.new(0, 100, 0, 28)
ToggleBtn.Position = UDim2.new(0, 8, 1, -200)
ToggleBtn.BackgroundColor3 = C.BG2
ToggleBtn.BackgroundTransparency = 0.05
ToggleBtn.BorderSizePixel = 0
ToggleBtn.Text = "⚙  WHITE HUB"
ToggleBtn.TextColor3 = C.Text
ToggleBtn.TextScaled = true
ToggleBtn.Font = Enum.Font.GothamBold
ToggleBtn.Parent = MainGui
Instance.new("UICorner", ToggleBtn).CornerRadius = UDim.new(0, 6)
local tbs = Instance.new("UIStroke", ToggleBtn)
tbs.Color = C.Stroke tbs.Transparency = 0 tbs.Thickness = 1.2
ToggleBtn.MouseEnter:Connect(function() TweenService:Create(tbs, TweenInfo.new(0.1), {Color=C.StrokeHov}):Play() end)
ToggleBtn.MouseLeave:Connect(function() TweenService:Create(tbs, TweenInfo.new(0.1), {Color=C.Stroke}):Play() end)

local W, H = 260, 340
local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, W, 0, H)
MainFrame.Position = UDim2.new(0.5, -W/2, 0.5, -H/2)
MainFrame.BackgroundColor3 = C.BG
MainFrame.BackgroundTransparency = 0.02
MainFrame.BorderSizePixel = 0
MainFrame.Visible = false
MainFrame.Parent = MainGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 10)
local mfs = Instance.new("UIStroke", MainFrame)
mfs.Color = C.Stroke mfs.Transparency = 0 mfs.Thickness = 1.5

local TitleBar = Instance.new("Frame")
TitleBar.Size = UDim2.new(1, 0, 0, 38)
TitleBar.BackgroundColor3 = C.BG2
TitleBar.BorderSizePixel = 0
TitleBar.Parent = MainFrame
Instance.new("UICorner", TitleBar).CornerRadius = UDim.new(0, 10)
local TFix = Instance.new("Frame", TitleBar)
TFix.Size = UDim2.new(1,0,0.5,0) TFix.Position = UDim2.new(0,0,0.5,0)
TFix.BackgroundColor3 = C.BG2 TFix.BorderSizePixel = 0
local TLine = Instance.new("Frame", TitleBar)
TLine.Size = UDim2.new(1,0,0,1) TLine.Position = UDim2.new(0,0,1,-1)
TLine.BackgroundColor3 = C.Stroke TLine.BorderSizePixel = 0

local TitleLabel = Instance.new("TextLabel", TitleBar)
TitleLabel.Size = UDim2.new(1,-46,1,0) TitleLabel.Position = UDim2.new(0,12,0,0)
TitleLabel.BackgroundTransparency = 1 TitleLabel.Text = "WHITE HUB"
TitleLabel.TextColor3 = C.White TitleLabel.TextScaled = true
TitleLabel.Font = Enum.Font.GothamBold TitleLabel.TextXAlignment = Enum.TextXAlignment.Left

local SubLabel = Instance.new("TextLabel", TitleBar)
SubLabel.Size = UDim2.new(0.5,0,0,11) SubLabel.Position = UDim2.new(0,12,1,-13)
SubLabel.BackgroundTransparency = 1 SubLabel.Text = "by WHITE DRAGON"
SubLabel.TextColor3 = C.TextDim SubLabel.TextScaled = true
SubLabel.Font = Enum.Font.Gotham SubLabel.TextXAlignment = Enum.TextXAlignment.Left

local CloseBtn = Instance.new("TextButton", TitleBar)
CloseBtn.Size = UDim2.new(0,22,0,22) CloseBtn.Position = UDim2.new(1,-30,0.5,-11)
CloseBtn.BackgroundColor3 = C.Red CloseBtn.BorderSizePixel = 0
CloseBtn.Text = "✕" CloseBtn.TextColor3 = C.White
CloseBtn.TextScaled = true CloseBtn.Font = Enum.Font.GothamBold
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 5)

local dragging, dragStart, startPos = false, nil, nil
TitleBar.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        dragging = true dragStart = i.Position startPos = MainFrame.Position
        i.Changed:Connect(function()
            if i.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
UserInputService.InputChanged:Connect(function(i)
    if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - dragStart
        TweenService:Create(MainFrame, TweenInfo.new(0.08), {
            Position = UDim2.new(startPos.X.Scale, startPos.X.Offset+d.X, startPos.Y.Scale, startPos.Y.Offset+d.Y)
        }):Play()
    end
end)

local ScrollFrame = Instance.new("ScrollingFrame")
ScrollFrame.Size = UDim2.new(1,-8,1,-96)
ScrollFrame.Position = UDim2.new(0,4,0,42)
ScrollFrame.BackgroundTransparency = 1
ScrollFrame.BorderSizePixel = 0
ScrollFrame.ScrollBarThickness = 2
ScrollFrame.ScrollBarImageColor3 = C.StrokeHov
ScrollFrame.Parent = MainFrame

local ListLayout = Instance.new("UIListLayout", ScrollFrame)
ListLayout.Padding = UDim.new(0, 3)
local UIPad = Instance.new("UIPadding", ScrollFrame)
UIPad.PaddingLeft = UDim.new(0,4) UIPad.PaddingRight = UDim.new(0,4) UIPad.PaddingTop = UDim.new(0,4)

local OptionsBar = Instance.new("Frame")
OptionsBar.Size = UDim2.new(1,-8,0,50)
OptionsBar.Position = UDim2.new(0,4,1,-54)
OptionsBar.BackgroundColor3 = C.BG2
OptionsBar.BorderSizePixel = 0
OptionsBar.Parent = MainFrame
Instance.new("UICorner", OptionsBar).CornerRadius = UDim.new(0, 8)
local obs = Instance.new("UIStroke", OptionsBar)
obs.Color = C.Stroke obs.Transparency = 0 obs.Thickness = 1
local OptLine = Instance.new("Frame", OptionsBar)
OptLine.Size = UDim2.new(0,1,0.6,0) OptLine.Position = UDim2.new(0.5,0,0.2,0)
OptLine.BackgroundColor3 = C.Stroke OptLine.BorderSizePixel = 0

local function MakeToggle(parent, label, val, xPos, yLblPos, onChange)
    local lbl = Instance.new("TextLabel", parent)
    lbl.Size = UDim2.new(0.4,0,0,14) lbl.Position = UDim2.new(xPos,6,0,yLblPos)
    lbl.BackgroundTransparency = 1 lbl.Text = label
    lbl.TextColor3 = C.Text lbl.TextScaled = true
    lbl.Font = Enum.Font.Gotham lbl.TextXAlignment = Enum.TextXAlignment.Left

    local trackBG = Instance.new("Frame", parent)
    trackBG.Size = UDim2.new(0,36,0,18)
    trackBG.Position = UDim2.new(xPos,6,0,yLblPos+17)
    trackBG.BackgroundColor3 = val and C.BG3 or C.BG
    trackBG.BorderSizePixel = 0
    Instance.new("UICorner", trackBG).CornerRadius = UDim.new(1,0)
    local ts = Instance.new("UIStroke", trackBG)
    ts.Color = val and C.StrokeAct or C.Stroke ts.Transparency = 0 ts.Thickness = 1

    local circle = Instance.new("Frame", trackBG)
    circle.Size = UDim2.new(0,12,0,12)
    circle.Position = val and UDim2.new(1,-15,0.5,-6) or UDim2.new(0,3,0.5,-6)
    circle.BackgroundColor3 = val and C.StrokeAct or C.StrokeHov
    circle.BorderSizePixel = 0
    Instance.new("UICorner", circle).CornerRadius = UDim.new(1,0)

    local btn = Instance.new("TextButton", parent)
    btn.Size = UDim2.new(0.48,0,1,0) btn.Position = UDim2.new(xPos,0,0,0)
    btn.BackgroundTransparency = 1 btn.Text = ""

    btn.MouseButton1Click:Connect(function()
        val = onChange()
        TweenService:Create(trackBG, TweenInfo.new(0.2), {BackgroundColor3 = val and C.BG3 or C.BG}):Play()
        TweenService:Create(ts, TweenInfo.new(0.2), {Color = val and C.StrokeAct or C.Stroke}):Play()
        TweenService:Create(circle, TweenInfo.new(0.2), {
            Position = val and UDim2.new(1,-15,0.5,-6) or UDim2.new(0,3,0.5,-6),
            BackgroundColor3 = val and C.StrokeAct or C.StrokeHov
        }):Play()
    end)
end

MakeToggle(OptionsBar, "AutoSell", AutoSell, 0.02, 6, function()
    AutoSell = not AutoSell
    getgenv().WHConfig.AutoSell = AutoSell
    SaveConfig() return AutoSell
end)

MakeToggle(OptionsBar, "BuyLucky", BuyLucky, 0.52, 6, function()
    BuyLucky = not BuyLucky
    getgenv().WHConfig.BuyLucky = BuyLucky
    SaveConfig() return BuyLucky
end)

local function CreateSection(text)
    local f = Instance.new("Frame", ScrollFrame)
    f.Size = UDim2.new(1,-8,0,20) f.BackgroundColor3 = C.BG3 f.BorderSizePixel = 0
    Instance.new("UICorner", f).CornerRadius = UDim.new(0, 6)
    local fs = Instance.new("UIStroke", f)
    fs.Color = C.Stroke fs.Transparency = 0 fs.Thickness = 1
    local l = Instance.new("TextLabel", f)
    l.Size = UDim2.new(1,-10,1,0) l.Position = UDim2.new(0,8,0,0)
    l.BackgroundTransparency = 1 l.Text = text
    l.TextColor3 = C.TextDim l.TextScaled = true
    l.Font = Enum.Font.GothamBold l.TextXAlignment = Enum.TextXAlignment.Left
end

local function CreateItemRow(itemName, currentVal)
    local row = Instance.new("Frame", ScrollFrame)
    row.Size = UDim2.new(1,-8,0,30) row.BackgroundColor3 = C.BG2 row.BorderSizePixel = 0
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 7)
    local rs = Instance.new("UIStroke", row)
    rs.Color = C.Stroke rs.Transparency = 0 rs.Thickness = 1

    local lbl = Instance.new("TextLabel", row)
    lbl.Size = UDim2.new(0.62,0,1,0) lbl.Position = UDim2.new(0,10,0,0)
    lbl.BackgroundTransparency = 1 lbl.Text = itemName
    lbl.TextColor3 = C.Text lbl.TextScaled = true
    lbl.Font = Enum.Font.Gotham lbl.TextXAlignment = Enum.TextXAlignment.Left

    local trackBG = Instance.new("Frame", row)
    trackBG.Size = UDim2.new(0,36,0,18) trackBG.Position = UDim2.new(1,-46,0.5,-9)
    trackBG.BackgroundColor3 = currentVal and C.BG3 or C.BG trackBG.BorderSizePixel = 0
    Instance.new("UICorner", trackBG).CornerRadius = UDim.new(1,0)
    local ts = Instance.new("UIStroke", trackBG)
    ts.Color = currentVal and C.StrokeAct or C.Stroke ts.Transparency = 0 ts.Thickness = 1

    local circle = Instance.new("Frame", trackBG)
    circle.Size = UDim2.new(0,12,0,12)
    circle.Position = currentVal and UDim2.new(1,-15,0.5,-6) or UDim2.new(0,3,0.5,-6)
    circle.BackgroundColor3 = currentVal and C.StrokeAct or C.StrokeHov circle.BorderSizePixel = 0
    Instance.new("UICorner", circle).CornerRadius = UDim.new(1,0)

    local btn = Instance.new("TextButton", row)
    btn.Size = UDim2.new(1,0,1,0) btn.BackgroundTransparency = 1 btn.Text = ""

    btn.MouseEnter:Connect(function() TweenService:Create(rs, TweenInfo.new(0.1), {Color=C.StrokeHov}):Play() end)
    btn.MouseLeave:Connect(function() TweenService:Create(rs, TweenInfo.new(0.1), {Color=C.Stroke}):Play() end)

    btn.MouseButton1Click:Connect(function()
        SellItems[itemName] = not SellItems[itemName]
        getgenv().WHConfig.SellItems[itemName] = SellItems[itemName]
        SaveConfig()
        local v = SellItems[itemName]
        TweenService:Create(trackBG, TweenInfo.new(0.2), {BackgroundColor3 = v and C.BG3 or C.BG}):Play()
        TweenService:Create(ts, TweenInfo.new(0.2), {Color = v and C.StrokeAct or C.Stroke}):Play()
        TweenService:Create(circle, TweenInfo.new(0.2), {
            Position = v and UDim2.new(1,-15,0.5,-6) or UDim2.new(0,3,0.5,-6),
            BackgroundColor3 = v and C.StrokeAct or C.StrokeHov
        }):Play()
        TweenService:Create(rs, TweenInfo.new(0.1), {Color=C.StrokeAct}):Play()
        task.delay(0.2, function() TweenService:Create(rs, TweenInfo.new(0.15), {Color=C.Stroke}):Play() end)
    end)
end

CreateSection("SELL ITEMS")

local itemOrder = {
    "Gold Coin","Diamond","Rokakaka","Pure Rokakaka",
    "Mysterious Arrow","Lucky Arrow","Lucky Stone Mask","Ancient Scroll",
    "Caesar's Headband","Stone Mask","Rib Cage of The Saint's Corpse",
    "Quinton's Glove","Zeppeli's Hat","Clackers","Steel Ball","Dio's Diary"
}
for _, name in ipairs(itemOrder) do
    if SellItems[name] ~= nil then
        CreateItemRow(name, SellItems[name])
    end
end

ListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    ScrollFrame.CanvasSize = UDim2.new(0,0,0,ListLayout.AbsoluteContentSize.Y+8)
end)

CreateSection("WEBHOOK")
local whRow = Instance.new("Frame", ScrollFrame)
whRow.Size = UDim2.new(1,-8,0,30) whRow.BackgroundColor3 = C.BG2 whRow.BorderSizePixel = 0
Instance.new("UICorner", whRow).CornerRadius = UDim.new(0,7)
local whStroke = Instance.new("UIStroke", whRow)
whStroke.Color = C.Stroke whStroke.Transparency = 0 whStroke.Thickness = 1

local whBox = Instance.new("TextBox", whRow)
whBox.Size = UDim2.new(1,-10,1,0) whBox.Position = UDim2.new(0,8,0,0)
whBox.BackgroundTransparency = 1
whBox.Text = getgenv().WHConfig.WebhookURL ~= "" and getgenv().WHConfig.WebhookURL or "Paste webhook URL here..."
whBox.TextColor3 = C.TextDim whBox.TextScaled = true whBox.Font = Enum.Font.Gotham
whBox.TextXAlignment = Enum.TextXAlignment.Left whBox.ClearTextOnFocus = false

whBox.Focused:Connect(function()
    if whBox.Text == "Paste webhook URL here..." then whBox.Text = "" end
    whBox.TextColor3 = C.Text
    TweenService:Create(whStroke, TweenInfo.new(0.1), {Color=C.StrokeAct}):Play()
end)
whBox.FocusLost:Connect(function()
    local url = whBox.Text
    if url == "" then
        whBox.Text = "Paste webhook URL here..."
        whBox.TextColor3 = C.TextDim
        url = ""
    end
    getgenv().WHConfig.WebhookURL = url
    SaveConfig()
    TweenService:Create(whStroke, TweenInfo.new(0.1), {Color=C.Stroke}):Play()
end)

local uiOpen = false
local function ToggleUI()
    uiOpen = not uiOpen
    if uiOpen then
        MainFrame.Visible = true
        MainFrame.Size = UDim2.new(0,0,0,0)
        MainFrame.Position = UDim2.new(0.5,0,0.5,0)
        TweenService:Create(MainFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
            Size = UDim2.new(0,W,0,H), Position = UDim2.new(0.5,-W/2,0.5,-H/2)
        }):Play()
    else
        local t = TweenService:Create(MainFrame, TweenInfo.new(0.15, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
            Size = UDim2.new(0,0,0,0), Position = UDim2.new(0.5,0,0.5,0)
        })
        t:Play()
        t.Completed:Connect(function() MainFrame.Visible = false end)
    end
end

local btnVisible = true
local function ToggleBtn_Visibility()
    btnVisible = not btnVisible
    ToggleBtn.Visible = btnVisible
end

ToggleBtn.MouseButton1Click:Connect(ToggleUI)
CloseBtn.MouseButton1Click:Connect(ToggleUI)
UserInputService.InputBegan:Connect(function(i, gp)
    if gp then return end
    if i.KeyCode == Enum.KeyCode.RightAlt then ToggleUI() end
    if i.KeyCode == Enum.KeyCode.RightControl then ToggleBtn_Visibility() end
end)

-- =====================
-- ANTI AFK
-- =====================
pcall(function()
    Player.Idled:Connect(function()
        game:GetService("VirtualUser"):ClickButton2(Vector2.new())
    end)
end)

-- =====================
-- CRASH BYPASS
-- =====================
task.delay(3, function()
    pcall(function()
        local Modules = ReplicatedStorage:WaitForChild("Modules", 10)
        if not Modules then return end
        local FunctionLibrary = require(Modules:WaitForChild("FunctionLibrary", 10))
        if not FunctionLibrary or type(FunctionLibrary) ~= "table" then return end
        local OldPcall = FunctionLibrary.pcall
        if type(OldPcall) ~= "function" then return end
        FunctionLibrary.pcall = function(...)
            local f = ...
            if type(f) == "function" and #getupvalues(f) == 11 then return end
            return OldPcall(...)
        end
    end)
end)

-- =====================
-- AUTO REJOIN
-- =====================
CoreGui.DescendantAdded:Connect(function(child)
    if child.Name == "ErrorPrompt" then
        local GrabError = child:FindFirstChild("ErrorMessage", true)
        if GrabError then
            repeat task.wait() until GrabError.Text ~= "Label"
            print("Kick detected: " .. GrabError.Text .. " - Rejoining...")
            task.wait(1)
            TeleportService:Teleport(2809202155, Player)
        end
    end
end)

-- =====================
-- HOOKS
-- =====================
local Has2x = MarketplaceService:UserOwnsGamePassAsync(Player.UserId, 14597778)

local oldMagnitude
pcall(function()
    oldMagnitude = hookmetamethod(Vector3.new(), "__index", newcclosure(function(self, index)
        local CallingScript = tostring(getcallingscript())
        if not checkcaller() and index == "magnitude" and CallingScript == "ItemSpawn" then
            return 0
        end
        return oldMagnitude(self, index)
    end))
end)

-- =====================
-- ITEM SPAWN FOLDER
-- =====================
local ItemSpawnFolder = nil
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
    warn("ERROR: Could not find Item_Spawns/Items folder")
else
    print("Item_Spawns/Items found!")
end

-- =====================
-- UTILITY FUNCTIONS
-- =====================
local function GetCharacter(Part)
    if Player.Character then
        if not Part then return Player.Character
        elseif typeof(Part) == "string" then return Player.Character:FindFirstChild(Part) or nil end
    end
    return nil
end

local function TeleportTo(Position)
    local HRP = GetCharacter("HumanoidRootPart")
    if HRP and typeof(Position) == "CFrame" then HRP.CFrame = Position end
end

local noclipActive = false
RunService.Stepped:Connect(function()
    if not noclipActive then return end
    local c = GetCharacter()
    if not c then return end
    for _, v in pairs(c:GetDescendants()) do
        if v:IsA("BasePart") then v.CanCollide = false end
    end
end)

local function SetNoclip(Value)
    noclipActive = Value
    if Value then return end
    local c = GetCharacter()
    if not c then return end
    for _, v in pairs(c:GetDescendants()) do
        if v:IsA("BasePart") then v.CanCollide = true end
    end
end

local MaxItemAmounts = {
    ["Gold Coin"]=45, ["Rokakaka"]=25, ["Pure Rokakaka"]=10, ["Mysterious Arrow"]=25,
    ["Diamond"]=30, ["Ancient Scroll"]=10, ["Caesar's Headband"]=10, ["Stone Mask"]=10,
    ["Rib Cage of The Saint's Corpse"]=20, ["Quinton's Glove"]=10, ["Zeppeli's Hat"]=10,
    ["Lucky Arrow"]=10, ["Lucky Stone Mask"]=10, ["Clackers"]=10, ["Steel Ball"]=10, ["Dio's Diary"]=10
}
if Has2x then
    for i, m in pairs(MaxItemAmounts) do MaxItemAmounts[i] = m*2 end
end

local function CountItem(name)
    local count = 0
    for _, t in pairs(Player.Backpack:GetChildren()) do
        if t.Name == name then count += 1 end
    end
    if Player.Character then
        for _, t in pairs(Player.Character:GetChildren()) do
            if t:IsA("Tool") and t.Name == name then count += 1 end
        end
    end
    return count
end

local function HasMaxItem(Item)
    return MaxItemAmounts[Item] and CountItem(Item) >= MaxItemAmounts[Item] or false
end

local function GetMoney()
    local ok, val = pcall(function() return Player.PlayerStats.Money.Value end)
    return ok and val or 0
end

-- =====================
-- STOP CONDITIONS
-- Para com 9+ Lucky Arrows + $1kk
-- (YBA bug: game prevents buying the 10th Lucky Arrow)
-- =====================
local LUCKY_STOP = 9    -- stop at 9 (YBA bug prevents buying the 10th)
local MONEY_STOP = 1000000

local function HasEnoughLucky()
    return CountItem("Lucky Arrow") >= LUCKY_STOP
end

local function IsMoneyMaxed()
    return GetMoney() >= MONEY_STOP
end

local function ShouldStopFarming()
    return HasEnoughLucky() and IsMoneyMaxed()
end

local function AllKeepItemsFull()
    local hasAny = false
    for Item, Sell in pairs(SellItems) do
        if not Sell and Item ~= "Lucky Arrow" and Item ~= "Lucky Stone Mask" then
            hasAny = true
            if not HasMaxItem(Item) then return false end
        end
    end
    return hasAny
end

-- =====================
-- ITEM DETECTION
-- =====================
getgenv().SpawnedItems = {}

local function GetItemInfo(Model)
    if not (Model and Model:IsA("Model") and Model.Parent and Model.Parent.Name == "Items") then return nil end
    local PP = Model.PrimaryPart
    if not PP then return nil end
    local Prompt
    for _, v in pairs(Model:GetChildren()) do
        if v:IsA("ProximityPrompt") and v.MaxActivationDistance ~= 0 then
            Prompt = v break
        end
    end
    if not Prompt then return nil end
    return {Name=Prompt.ObjectText, ProximityPrompt=Prompt, Position=PP.Position}
end

if ItemSpawnFolder then
    for _, Model in pairs(ItemSpawnFolder:GetChildren()) do
        pcall(function()
            if Model:IsA("Model") then
                local info = GetItemInfo(Model)
                if info then
                    getgenv().SpawnedItems[Model] = info
                    print("Existing item detected: " .. info.Name)
                end
            end
        end)
    end

    ItemSpawnFolder.ChildAdded:Connect(function(Model)
        task.wait(1)
        pcall(function()
            if Model:IsA("Model") then
                local info = GetItemInfo(Model)
                if info then
                    getgenv().SpawnedItems[Model] = info
                    print("Item detected: " .. info.Name)
                end
            end
        end)
    end)
else
    warn("ItemSpawnFolder does not exist, items will not be detected")
end

-- =====================
-- TELEPORT BYPASS
-- =====================
local oldNc
oldNc = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
    local Args = {...}
    if not checkcaller() and rawequal(self.Name,"Returner") and rawequal(Args[1],"idklolbrah2de") then
        return "  ___XP DE KEY"
    end
    return oldNc(self, ...)
end))

-- =====================
-- SERVER HOP
-- =====================
local ServerHop = loadstring(game:HttpGet("https://raw.githubusercontent.com/rinqedd/pub_rblx/main/ServerHop", true))

-- =====================
-- SKIP LOADING SCREEN
-- =====================
task.wait(1)
pcall(function()
    if not PlayerGui:FindFirstChild("HUD") then
        local HUD = ReplicatedStorage.Objects.HUD:Clone()
        HUD.Parent = PlayerGui
    end
end)
task.spawn(function()
    pcall(function() PlayerGui:WaitForChild("LoadingScreen1", 5):Destroy() end)
    task.wait(.5)
    pcall(function() PlayerGui:WaitForChild("LoadingScreen", 5):Destroy() end)
    pcall(function() workspace.LoadingScreen.Song:Destroy() end)
end)

repeat task.wait() until GetCharacter() and GetCharacter("RemoteEvent")
print("Character loaded successfully")
pcall(function() GetCharacter("RemoteEvent"):FireServer("PressedPlay") end)

print("Teleporting to safe spot...")
TeleportTo(CFrame.new(978, -42, -49))
task.wait(1)

local HRP2 = GetCharacter("HumanoidRootPart")
if HRP2 then print("Position: " .. tostring(HRP2.Position))
else warn("HumanoidRootPart not found") end

print("Waiting 5 seconds before starting farm...")
task.wait(5)
print("Starting farm loop...")

-- =====================
-- WEBHOOK TRIGGER em tempo real
-- =====================
Player.Backpack.ChildAdded:Connect(function(tool)
    if tool.Name == "Lucky Arrow" then
        if ShouldStopFarming() then
            SendWebhook("✅ **Farm conditions met!**\nPlayer: `" .. Player.Name .. "`\nLucky Arrows: `" .. CountItem("Lucky Arrow") .. "/" .. LUCKY_STOP .. "`\nMoney: `$" .. tostring(GetMoney()) .. "`")
        end
    end
end)

-- =====================
-- FARM LOOP
-- Stops when $1kk + 9 Lucky Arrows are reached
-- Does not sell when money is already maxed
-- Keeps collecting Lucky Arrows from the ground even while paused
-- =====================
local NO_ITEM_TIMEOUT = 20
local lastItemTime = tick()

local function DoSell()
    -- Skip sell if money is already maxed
    if IsMoneyMaxed() then
        print("Money maxed — skipping sell.")
        return
    end
    if not AutoSell then return end
    for Item, Sell in pairs(SellItems) do
        if Sell and Player.Backpack and Player.Backpack:FindFirstChild(Item) then
            pcall(function()
                GetCharacter("Humanoid"):EquipTool(Player.Backpack:FindFirstChild(Item))
                GetCharacter("RemoteEvent"):FireServer("EndDialogue", {
                    NPC="Merchant", Dialogue="Dialogue5", Option="Option2"
                })
            end)
            task.wait(.1)
        end
    end
end

local function DoBuyLucky()
    -- Only buy if below 9 (avoids YBA bug on the 10th arrow)
    if not BuyLucky then return end
    if CountItem("Lucky Arrow") >= LUCKY_STOP then return end
    local money = GetMoney()
    if money < 75000 then return end
    print("Buying Lucky Arrows... ($" .. money .. ")")
    local attempts = 0
    while GetMoney() >= 75000 and attempts < 15 do
        pcall(function()
            Player.Character.RemoteEvent:FireServer("PurchaseShopItem", {ItemName="1x Lucky Arrow"})
        end)
        task.wait(1)
        attempts += 1
        local count = CountItem("Lucky Arrow")
        print("Lucky Arrows: " .. count .. "/" .. LUCKY_STOP)
        -- Stop buying at 9 (YBA bug blocks the 10th)
        if count >= LUCKY_STOP then
            print("Reached " .. LUCKY_STOP .. " Lucky Arrows — stopping purchase (YBA bug prevents buying the last one)")
            break
        end
    end
end

local function DoServerHop()
    print("=== Server dry — switching servers ===")
    local hopStart = tick()
    ServerHop() task.wait(10)
    if tick() - hopStart < 15 then
        print("Hop failed, retrying...")
        task.wait(5) ServerHop() task.wait(10)
    end
    lastItemTime = tick()
end

local function CollectItem(ItemInfo, Index)
    local HumanoidRootPart = GetCharacter("HumanoidRootPart")
    if not HumanoidRootPart then return end
    getgenv().SpawnedItems[Index] = nil
    if HasMaxItem(ItemInfo.Name) then return end
    local BV = Instance.new("BodyVelocity")
    BV.Parent = HumanoidRootPart
    BV.Velocity = Vector3.new(0,0,0)
    SetNoclip(true)
    TeleportTo(CFrame.new(ItemInfo.Position.X, ItemInfo.Position.Y-25, ItemInfo.Position.Z))
    task.wait(.5)
    pcall(function() fireproximityprompt(ItemInfo.ProximityPrompt) end)
    task.wait(.5)
    BV:Destroy()
    TeleportTo(CFrame.new(978,-42,-49))
    task.wait(.3)
    SetNoclip(false)
    lastItemTime = tick()
    print("Collected: " .. ItemInfo.Name)
end

while true do
    -- Conditions met — wait but keep collecting Lucky Arrows from the ground
    if ShouldStopFarming() then
        print("Conditions met ($1kk + " .. LUCKY_STOP .. " Lucky Arrows) — waiting...")
        SendWebhook("🛑 **Farm paused — conditions met!**\nPlayer: `" .. Player.Name .. "`\nLucky Arrows: `" .. CountItem("Lucky Arrow") .. "/" .. LUCKY_STOP .. "`\nMoney: `$" .. tostring(GetMoney()) .. "`")

        -- Stay in loop, only pick up Lucky Arrows that spawn
        repeat
            local snapshot = {}
            for Index, ItemInfo in pairs(getgenv().SpawnedItems) do
                if ItemInfo.Name == "Lucky Arrow" or ItemInfo.Name == "Lucky Stone Mask" then
                    table.insert(snapshot, {Index=Index, ItemInfo=ItemInfo})
                end
            end
            for _, entry in ipairs(snapshot) do
                CollectItem(entry.ItemInfo, entry.Index)
            end
            task.wait(3)
        until not ShouldStopFarming()

        print("Conditions changed — resuming full farm!")
        lastItemTime = tick()
    end

    -- Collect all available items
    local itemSnapshot = {}
    for Index, ItemInfo in pairs(getgenv().SpawnedItems) do
        table.insert(itemSnapshot, {Index=Index, ItemInfo=ItemInfo})
    end

    for _, entry in ipairs(itemSnapshot) do
        CollectItem(entry.ItemInfo, entry.Index)
    end

    -- Check if server has dried up
    local timeSinceLast = tick() - lastItemTime
    if timeSinceLast > NO_ITEM_TIMEOUT then
        print(string.format("No items for %.0fs — selling + hopping...", timeSinceLast))
        DoSell()
        DoBuyLucky()
        if ShouldStopFarming() then
            -- Do not hop, just wait
            lastItemTime = tick()
        else
            DoServerHop()
        end
    else
        if #itemSnapshot == 0 then
            local waiting = math.floor(NO_ITEM_TIMEOUT - timeSinceLast)
            print("Waiting for items... (" .. waiting .. "s until hop)")
        end
    end

    task.wait(1)
end
