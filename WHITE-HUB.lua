repeat task.wait(1) until game:IsLoaded()

print("Script Loading...")
warn("Script Loading...")

wait(6)

print("WHITE HUB Loaded!")
warn("WHITE HUB Loaded!")

wait(2)

local BuyLucky = true
local AutoSell = true
local SellItems = {
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
    ["Clackers"] = true,
    ["Steel Ball"] = true,
    ["Dio's Diary"] = true
}

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- Credits pop up
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Parent = PlayerGui
ScreenGui.ResetOnSpawn = false

local Frame = Instance.new("Frame")
Frame.Size = UDim2.new(0, 150, 0, 48)
Frame.Position = UDim2.new(0, -160, 1, -120)
Frame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
Frame.BackgroundTransparency = 0.2
Frame.BorderSizePixel = 0
Frame.Parent = ScreenGui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 8)
Corner.Parent = Frame

local Stroke = Instance.new("UIStroke")
Stroke.Color = Color3.fromRGB(255, 255, 255)
Stroke.Transparency = 0.6
Stroke.Thickness = 1.5
Stroke.Parent = Frame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0.52, 0)
Title.Position = UDim2.new(0, 0, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "WHITE HUB"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.TextScaled = true
Title.Font = Enum.Font.GothamBold
Title.Parent = Frame

local Credits = Instance.new("TextLabel")
Credits.Size = UDim2.new(1, 0, 0.48, 0)
Credits.Position = UDim2.new(0, 0, 0.52, 0)
Credits.BackgroundTransparency = 1
Credits.Text = "by WHITE DRAGON"
Credits.TextColor3 = Color3.fromRGB(160, 160, 160)
Credits.TextScaled = true
Credits.Font = Enum.Font.Gotham
Credits.Parent = Frame

-- Slide in
local slideIn = TweenService:Create(Frame, TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
    Position = UDim2.new(0, 8, 1, -120)
})
slideIn:Play()

-- Slide out depois de 5 segundos
task.delay(5, function()
    local slideOut = TweenService:Create(Frame, TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
        Position = UDim2.new(0, -160, 1, -120)
    })
    slideOut:Play()
    slideOut.Completed:Connect(function()
        ScreenGui:Destroy()
    end)
end)

-- Anti AFK
pcall(function()
    Player.Idled:Connect(function()
        game:GetService("VirtualUser"):ClickButton2(Vector2.new())
    end)
end)

-- Crash Bypass
pcall(function()
    local FunctionLibrary = require(ReplicatedStorage:WaitForChild("Modules").FunctionLibrary)
    local OldPcall = FunctionLibrary.pcall
    FunctionLibrary.pcall = function(...)
        local f = ...
        if type(f) == "function" and #getupvalues(f) == 11 then
            return
        end
        return OldPcall(...)
    end
end)

game:GetService("CoreGui").DescendantAdded:Connect(function(child)
    if child.Name == "ErrorPrompt" then
        local GrabError = child:FindFirstChild("ErrorMessage", true)
        repeat task.wait() until GrabError.Text ~= "Label"
        local Reason = GrabError.Text
        if Reason:match("kick") or Reason:match("You") or Reason:match("conn") or Reason:match("rejoin") then
            game:GetService("TeleportService"):Teleport(2809202155, game:GetService("Players").LocalPlayer)
        end
    end
end)

local Has2x = MarketplaceService:UserOwnsGamePassAsync(Player.UserId, 14597778)

local oldMagnitude
local hookSuccess = pcall(function()
    oldMagnitude = hookmetamethod(Vector3.new(), "__index", newcclosure(function(self, index)
        local CallingScript = tostring(getcallingscript())
        if not checkcaller() and index == "magnitude" and CallingScript == "ItemSpawn" then
            return 0
        end
        return oldMagnitude(self, index)
    end))
end)

if not hookSuccess then
    warn("Hook failed, continuing without it...")
end

-- Move map parts to separate folder to improve noclip
local MapFolder = Instance.new("Folder", workspace)
pcall(function()
    for _, Part in pairs(workspace.Map:GetChildren()) do
        Part.Parent = MapFolder
    end
end)

local ItemSpawnFolder
local folderSuccess = pcall(function()
    ItemSpawnFolder = Workspace:WaitForChild("Item_Spawns", 10):WaitForChild("Items", 10)
end)

if not folderSuccess or not ItemSpawnFolder then
    warn("Item_Spawns not found, retrying...")
    task.wait(5)
    ItemSpawnFolder = Workspace:FindFirstChild("Item_Spawns")
    if ItemSpawnFolder then
        ItemSpawnFolder = ItemSpawnFolder:FindFirstChild("Items")
    end
    if not ItemSpawnFolder then
        warn("ERROR: Could not find items folder")
    end
end

local function GetCharacter(Part)
    if Player.Character then
        if not Part then
            return Player.Character
        elseif typeof(Part) == "string" then
            return Player.Character:FindFirstChild(Part) or nil
        end
    end
    return nil
end

local function TeleportTo(Position)
    local HumanoidRootPart = GetCharacter("HumanoidRootPart")
    if HumanoidRootPart then
        local PositionType = typeof(Position)
        if PositionType == "CFrame" then
            HumanoidRootPart.CFrame = Position
        end
    end
end

-- Improved noclip using RunService
local noclipActive = false

RunService.Stepped:Connect(function()
    if noclipActive then
        local Character = GetCharacter()
        if Character then
            for _, Child in pairs(Character:GetDescendants()) do
                if Child:IsA("BasePart") then
                    Child.CanCollide = false
                end
            end
        end
    end
end)

local function SetNoclip(Value)
    noclipActive = Value
    if not Value then
        local Character = GetCharacter()
        if Character then
            for _, Child in pairs(Character:GetDescendants()) do
                if Child:IsA("BasePart") then
                    Child.CanCollide = true
                end
            end
        end
    end
end

local MaxItemAmounts = {
    ["Gold Coin"] = 45,
    ["Rokakaka"] = 25,
    ["Pure Rokakaka"] = 10,
    ["Mysterious Arrow"] = 25,
    ["Diamond"] = 30,
    ["Ancient Scroll"] = 10,
    ["Caesar's Headband"] = 10,
    ["Stone Mask"] = 10,
    ["Rib Cage of The Saint's Corpse"] = 20,
    ["Quinton's Glove"] = 10,
    ["Zeppeli's Hat"] = 10,
    ["Lucky Arrow"] = 10,
    ["Clackers"] = 10,
    ["Steel Ball"] = 10,
    ["Dio's Diary"] = 10
}

if Has2x then
    for Index, Max in pairs(MaxItemAmounts) do
        MaxItemAmounts[Index] = Max * 2
    end
end

local function HasMaxItem(Item)
    local Count = 0
    for _, Tool in pairs(Player.Backpack:GetChildren()) do
        if Tool.Name == Item then
            Count += 1
        end
    end
    if MaxItemAmounts[Item] then
        return Count >= MaxItemAmounts[Item]
    else
        return false
    end
end

local function HasLuckyArrows()
    local Count = 0
    for _, Tool in pairs(Player.Backpack:GetChildren()) do
        if Tool.Name == "Lucky Arrow" then
            Count += 1
        end
    end
    if Player.Character then
        for _, Tool in pairs(Player.Character:GetChildren()) do
            if Tool:IsA("Tool") and Tool.Name == "Lucky Arrow" then
                Count += 1
            end
        end
    end
    return Count >= 10
end

local function IsMoneyMaxed()
    local Money = Player.PlayerStats.Money
    return Money.Value >= 1000000
end

local function AllKeepItemsFull()
    local hasAnyKeepItem = false
    for Item, Sell in pairs(SellItems) do
        if not Sell and Item ~= "Lucky Arrow" then
            hasAnyKeepItem = true
            if not HasMaxItem(Item) then
                print("Still need more: " .. Item)
                return false
            end
        end
    end
    if not hasAnyKeepItem then
        return false
    end
    print("All kept items are maxed out!")
    return true
end

local function ShouldStopFarming()
    if AllKeepItemsFull() then return true end
    if HasLuckyArrows() and IsMoneyMaxed() then
        print("Max Lucky Arrows and max money reached! Stopping farm.")
        return true
    end
    return false
end

local ServerHop = loadstring(game:HttpGet("https://raw.githubusercontent.com/rinqedd/pub_rblx/main/ServerHop", true))

-- Ghost item bypass: checks ~= 0 instead of == 8
local function GetItemInfo(Model)
    if Model and Model:IsA("Model") and Model.Parent and Model.Parent.Name == "Items" then
        local PrimaryPart = Model.PrimaryPart
        local Position = PrimaryPart.Position
        local ProximityPrompt
        for _, ItemInstance in pairs(Model:GetChildren()) do
            if ItemInstance:IsA("ProximityPrompt") and ItemInstance.MaxActivationDistance ~= 0 then
                ProximityPrompt = ItemInstance
            end
        end
        if ProximityPrompt then
            return {["Name"] = ProximityPrompt.ObjectText, ["ProximityPrompt"] = ProximityPrompt, ["Position"] = Position}
        end
    end
    return nil
end

getgenv().SpawnedItems = {}

if ItemSpawnFolder then
    ItemSpawnFolder.ChildAdded:Connect(function(Model)
        task.wait(1)
        if Model:IsA("Model") then
            local ItemInfo = GetItemInfo(Model)
            if ItemInfo then
                getgenv().SpawnedItems[Model] = ItemInfo
                print("Item detected: " .. ItemInfo.Name)
            end
        end
    end)
else
    warn("ItemSpawnFolder does not exist, items will not be detected automatically")
end

local UzuKeeIsRetardedAndDoesntKnowHowToMakeAnAntiCheatOnTheServerSideAlsoVexStfuIKnowTheCodeIsBadYouDontNeedToTellMe = "  ___XP DE KEY"

local oldNc
oldNc = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
    local Method = getnamecallmethod()
    local Args = {...}
    if not checkcaller() and rawequal(self.Name, "Returner") and rawequal(Args[1], "idklolbrah2de") then
        return UzuKeeIsRetardedAndDoesntKnowHowToMakeAnAntiCheatOnTheServerSideAlsoVexStfuIKnowTheCodeIsBadYouDontNeedToTellMe
    end
    return oldNc(self, ...)
end))

task.wait(1)

if not PlayerGui:FindFirstChild("HUD") then
    local HUD = ReplicatedStorage.Objects.HUD:Clone()
    HUD.Parent = PlayerGui
end

task.spawn(function()
    PlayerGui:WaitForChild("LoadingScreen1"):Destroy()
    task.wait(.5)
    pcall(function()
        PlayerGui:WaitForChild("LoadingScreen"):Destroy()
    end)
    pcall(function()
        workspace.LoadingScreen.Song:Destroy()
    end)
end)

repeat task.wait() until GetCharacter() and GetCharacter("RemoteEvent")

print("Character loaded successfully")

GetCharacter("RemoteEvent"):FireServer("PressedPlay")

print("Teleporting...")
TeleportTo(CFrame.new(978, -42, -49))
task.wait(1)

local HRP = GetCharacter("HumanoidRootPart")
if HRP then
    print("Current position: " .. tostring(HRP.Position))
else
    warn("ERROR: HumanoidRootPart not found")
end

print("Waiting 5 seconds before starting farm...")
task.wait(5)

print("Starting farm loop...")

local cyclesCompleted = 0
local maxCycles = 1
local maxCycleTime = 60

while true do
    if ShouldStopFarming() then
        print("All conditions met, waiting...")
        repeat
            task.wait(5)
        until not ShouldStopFarming()
        print("Conditions changed, resuming farm!")
        cyclesCompleted = 0
    end

    print("=== Cycle #" .. (cyclesCompleted + 1) .. " ===")

    for Index, ItemInfo in pairs(getgenv().SpawnedItems) do
        local HumanoidRootPart = GetCharacter("HumanoidRootPart")
        if HumanoidRootPart then
            local Name = ItemInfo.Name
            local HasMax = HasMaxItem(Name)
            if not HasMax then
                local ProximityPrompt = ItemInfo.ProximityPrompt
                local Position = ItemInfo.Position
                table.remove(getgenv().SpawnedItems, table.find(getgenv().SpawnedItems, ItemInfo))
                local BodyVelocity = Instance.new("BodyVelocity")
                BodyVelocity.Parent = HumanoidRootPart
                BodyVelocity.Velocity = Vector3.new(0, 0, 0)
                SetNoclip(true)
                TeleportTo(CFrame.new(Position.X, Position.Y - 25, Position.Z))
                task.wait(.5)
                fireproximityprompt(ProximityPrompt)
                task.wait(.5)
                BodyVelocity:Destroy()
                TeleportTo(CFrame.new(978, -42, -49))
                task.wait(.3)
                SetNoclip(false)
            else
                table.remove(getgenv().SpawnedItems, table.find(getgenv().SpawnedItems, ItemInfo))
            end
        end
    end

    task.wait(3)

    local cycleStartTime = tick()
    print("Farm done, starting sell...")

    if AutoSell then
        for Item, Sell in pairs(SellItems) do
            if Sell and Player.Backpack and Player.Backpack:FindFirstChild(Item) then
                GetCharacter("Humanoid"):EquipTool(Player.Backpack:FindFirstChild(Item))
                GetCharacter("RemoteEvent"):FireServer("EndDialogue", {
                    ["NPC"] = "Merchant",
                    ["Dialogue"] = "Dialogue5",
                    ["Option"] = "Option2"
                })
                task.wait(.1)
            end
        end
    end

    -- Buy Lucky Arrows
    local Money = Player.PlayerStats.Money
    if BuyLucky and not HasLuckyArrows() then
        print("Buying Lucky Arrows... (Money: $" .. Money.Value .. ")")
        local purchaseAttempts = 0
        while Money.Value >= 75000 and purchaseAttempts < 15 do
            Player.Character.RemoteEvent:FireServer("PurchaseShopItem", {["ItemName"] = "1x Lucky Arrow"})
            task.wait(1)
            purchaseAttempts = purchaseAttempts + 1

            local currentCount = 0
            for _, Tool in pairs(Player.Backpack:GetChildren()) do
                if Tool.Name == "Lucky Arrow" then
                    currentCount = currentCount + 1
                end
            end
            if Player.Character then
                for _, Tool in pairs(Player.Character:GetChildren()) do
                    if Tool:IsA("Tool") and Tool.Name == "Lucky Arrow" then
                        currentCount = currentCount + 1
                    end
                end
            end

            print("Lucky Arrows: " .. currentCount .. "/10")

            if currentCount >= 10 then
                print("Max Lucky Arrows reached!")
                break
            end

            if purchaseAttempts > 3 and currentCount == 9 then
                print("Could not purchase the 10th Lucky Arrow")
                break
            end
        end
    end

    cyclesCompleted = cyclesCompleted + 1
    print("Cycle completed (" .. cyclesCompleted .. "/" .. maxCycles .. ")")

    if tick() - cycleStartTime > maxCycleTime then
        print("TIMEOUT: Cycle took too long, forcing server hop...")
        cyclesCompleted = 0
        ServerHop()
        task.wait(10)
    end

    if cyclesCompleted >= maxCycles then
        if ShouldStopFarming() then
            print("All conditions met! Stopping server hop.")
            cyclesCompleted = 0
        else
            print("=== " .. maxCycles .. " cycles completed, switching servers ===")
            cyclesCompleted = 0
            local hopStartTime = tick()
            ServerHop()
            task.wait(10)

            if tick() - hopStartTime < 15 then
                print("Server hop failed, retrying...")
                task.wait(5)
                ServerHop()
                task.wait(10)
            end
        end
    end

    task.wait(2)
end
