-- =====================
-- ServerHop.lua (WHITE HUB V3)
-- Handles server hopping and auto rejoin.
-- =====================

local HttpService      = game:GetService("HttpService")
local TeleportService  = game:GetService("TeleportService")
local CoreGui          = game:GetService("CoreGui")
local Players          = game:GetService("Players")

local Player  = Players.LocalPlayer
local PlaceID = game.PlaceId

local ServerHop = {}
local _movement = nil
local _config = nil
local _kickConnection = nil
local hopBusy = false
local kickEpoch, rejoinBusy, autoRejoinAttempted = 0, false, false
local seenErrorPrompts = setmetatable({}, {__mode="k"})
local preparedSite, preparedURL, preparedAt = nil, nil, 0
local prepareBusy, prepareEpoch = false, 0

local AllIDs = {}
local foundAnything = ""
local actualHour = os.date("!*t").hour

local fileOk = pcall(function()
    if type(readfile) == "function" then
        AllIDs = HttpService:JSONDecode(readfile("NotSameServers.json"))
    end
end)
if not fileOk or type(AllIDs) ~= "table" then
    AllIDs = { actualHour }
    pcall(function()
        if type(writefile) == "function" then
            writefile("NotSameServers.json", HttpService:JSONEncode(AllIDs))
        end
    end)
end

local function saveIds()
    pcall(function()
        if type(writefile) == "function" then
            writefile("NotSameServers.json", HttpService:JSONEncode(AllIDs))
        end
    end)
end

local function resetHourlyCacheIfNeeded()
    actualHour = os.date("!*t").hour
    if tonumber(AllIDs[1]) ~= tonumber(actualHour) then
        AllIDs = { actualHour }
        pcall(function()
            if type(delfile) == "function" then delfile("NotSameServers.json") end
        end)
        saveIds()
    end
end

local function serverListURL()
    local url = "https://games.roblox.com/v1/games/" .. PlaceID .. "/servers/Public?sortOrder=Asc&limit=100"
    if foundAnything ~= "" then url = url .. "&cursor=" .. foundAnything end
    return url
end

local function TPReturner(canContinue, onDestination)
    if canContinue and not canContinue() then return false end
    resetHourlyCacheIfNeeded()

    local url = serverListURL()
    local waitDeadline = tick() + 5
    while prepareBusy and tick() < waitDeadline do
        if canContinue and not canContinue() then return false end
        task.wait(0.03)
    end
    if prepareBusy then return false end -- Never duplicate an in-flight API request.
    local Site
    if preparedSite and preparedURL == url and tick() - preparedAt <= 15 then
        Site = preparedSite
        preparedSite, preparedURL = nil, nil
    else
        Site = HttpService:JSONDecode(game:HttpGet(url))
    end
    -- HttpGet can yield: a Stop during the request must prevent the teleport.
    if canContinue and not canContinue() then return false end
    if Site.nextPageCursor and Site.nextPageCursor ~= "null" then
        foundAnything = Site.nextPageCursor
    else
        foundAnything = ""
    end

    for _, server in ipairs(Site.data or {}) do
        local id = tostring(server.id)
        if tonumber(server.maxPlayers) > tonumber(server.playing) then
            local seen = false
            for i = 2, #AllIDs do
                if tostring(AllIDs[i]) == id then
                    seen = true
                    break
                end
            end

            if not seen and id ~= tostring(game.JobId) then
                if canContinue and not canContinue() then return false end
                table.insert(AllIDs, id)
                saveIds()
                if canContinue and not canContinue() then return false end
                if onDestination and not onDestination(id) then return false end
                if canContinue and not canContinue() then return false end
                TeleportService:TeleportToPlaceInstance(PlaceID, id, Player)
                return true
            end
        end
    end
    return false
end

local _runtimeLog = nil
local _rawPrint, _rawWarn = print, warn
local function moduleLog(level, ...)
    if _runtimeLog and type(_runtimeLog.Write) == "function" then
        pcall(_runtimeLog.Write, _runtimeLog, level, "ServerHop", ...)
    end
    if level == "WARN" or level == "ERROR" then
        _rawWarn(...)
    else
        _rawPrint(...)
    end
end

-- Fetch one read-only page while Merchant work is already running. A guarded
-- Hop still validates state/destination before teleport; no automatic transfer.
function ServerHop:Prepare()
    if prepareBusy or hopBusy or (_config and _config:Get("StayInPrivateServer")) then return false end
    resetHourlyCacheIfNeeded()
    local url = serverListURL()
    if preparedSite and preparedURL == url and tick()-preparedAt <= 15 then return true end
    prepareBusy = true
    local epoch = prepareEpoch
    task.spawn(function()
        local ok, site = pcall(function() return HttpService:JSONDecode(game:HttpGet(url)) end)
        if epoch ~= prepareEpoch then return end
        prepareBusy = false
        if ok and type(site) == "table" and type(site.data) == "table" then
            preparedSite, preparedURL, preparedAt = site, url, tick()
        else
            moduleLog("WARN", "[ServerHop] Server list preparation failed; Hop will use its normal request")
        end
    end)
    return true
end

function ServerHop:Init(Modules)
    _runtimeLog = Modules.RuntimeLog
    _movement = Modules.Movement
    _config = Modules.Config
    kickEpoch = kickEpoch + 1
    autoRejoinAttempted = false
    seenErrorPrompts = setmetatable({}, {__mode="k"})
    local epoch = kickEpoch

    if _kickConnection then
        pcall(function() _kickConnection:Disconnect() end)
    end

    local function readyErrorPrompt(child)
        if not child.Parent then return false end
        local grabError = child:FindFirstChild("ErrorMessage", true)
        local text = ""
        if grabError then pcall(function() text=tostring(grabError.Text or "") end) end
        if text == "" or text == "Label" then return false end
        local parent = child
        while parent and parent ~= CoreGui do
            if parent:IsA("GuiObject") and parent.Visible == false
                or parent:IsA("ScreenGui") and parent.Enabled == false then return false end
            parent = parent.Parent
        end
        return parent == CoreGui
    end
    local function observeErrorPrompt(child)
        if child.Name ~= "ErrorPrompt" or seenErrorPrompts[child] or autoRejoinAttempted then return end
        seenErrorPrompts[child] = true
        task.spawn(function()
            local deadline = tick() + 5
            while epoch == kickEpoch and child.Parent and not autoRejoinAttempted and tick() < deadline do
                if readyErrorPrompt(child) then
                    task.wait(1)
                    if epoch ~= kickEpoch or not readyErrorPrompt(child) or autoRejoinAttempted then return end
                    autoRejoinAttempted = true
                    moduleLog("INFO", "[ServerHop][AutoRejoin] Kick/disconnect detected; requesting ONE rejoin")
                    ServerHop:Rejoin()
                    return
                end
                task.wait(0.1)
            end
        end)
    end
    _kickConnection = CoreGui.DescendantAdded:Connect(observeErrorPrompt)
    -- Reload can occur after Roblox has already built the disconnect prompt.
    pcall(function()
        local existing = CoreGui:FindFirstChild("ErrorPrompt", true)
        if existing then observeErrorPrompt(existing) end
    end)
    moduleLog("INFO", "[ServerHop] Auto Rejoin enabled; one attempt per runtime, no automatic retry loop")
end

function ServerHop:Hop(canContinue, onDestination)
    if canContinue ~= nil and type(canContinue) ~= "function" then return false end
    if onDestination ~= nil and type(onDestination) ~= "function" then return false end
    if hopBusy then return false end
    if _config and _config:Get("StayInPrivateServer") then
        moduleLog("INFO", "[ServerHop] StayInPrivateServer is ON — skipping hop.")
        return false
    end

    moduleLog("INFO", "[ServerHop] Hopping to a new server...")
    hopBusy = true
    local epoch = prepareEpoch
    local function permitted()
        return epoch == prepareEpoch and (not canContinue or canContinue())
    end
    local ok, result = pcall(function()
        if TPReturner(permitted,onDestination) then return true end
        if not permitted() then return false end
        if foundAnything ~= "" then return TPReturner(permitted,onDestination) end
        return false
    end)
    hopBusy = false

    if _movement and not canContinue and epoch == prepareEpoch then
        task.delay(3, function() if epoch == prepareEpoch then _movement:FixCamera() end end)
    end

    if not ok then moduleLog("WARN", "[ServerHop] Hop failed: " .. tostring(result)) end
    return ok and result == true
end

function ServerHop:Rejoin()
    if rejoinBusy then return false end
    rejoinBusy = true
    moduleLog("INFO", "[ServerHop] Rejoining game...")
    local ok, err = pcall(function()
        TeleportService:Teleport(PlaceID, Player)
    end)
    rejoinBusy = false
    if not ok then moduleLog("WARN", "[ServerHop] Rejoin failed: " .. tostring(err)) end
    return ok
end

function ServerHop:Destroy()
    kickEpoch = kickEpoch + 1
    prepareEpoch = prepareEpoch + 1
    prepareBusy, preparedSite, preparedURL = false, nil, nil
    if _kickConnection then
        pcall(function() _kickConnection:Disconnect() end)
        _kickConnection = nil
    end
end

return ServerHop
