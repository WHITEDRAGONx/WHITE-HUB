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
local _modules = nil
local _kickConnection = nil
local cleanHopConnections = {}
local cleanHopEpoch = 0
local cleanHopRequested = false
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
    -- Both classic and clean hops now prefetch eligible public servers.
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
    _modules = Modules
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

-- CLEAN HOP (opt-in): choose a DIFFERENT live JobId and request an explicit
-- instance transfer, then clean up only after Roblox confirms InProgress.
-- Fresh Place matchmaking was removed: it can route us back to the same JobId.
-- Unlike relaunching from Play, neither teleport resets the Roblox/Delta VM.
-- Do not destroy running modules until Roblox reports InProgress: a request
-- can fail or be refused, in which case the current Farm must remain usable.
local function disconnectCleanHopListeners()
    for _,connection in ipairs(cleanHopConnections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(cleanHopConnections)
end

local function cleanHopShutdown(epoch)
    if epoch~=cleanHopEpoch then return end
    moduleLog("INFO","[CleanHop] Teleport InProgress; releasing old-runtime connections and GUI")
    local modules=_modules
    if not modules then return end
    -- Leave installed native metamethod hooks alone. Unhooking them or blindly
    -- rehooking on destination can corrupt the Delta environment; the new
    -- Main will reload modules and check the retained hook marker.
    for _,name in ipairs({
        "Farm","HalloweenExchange","CommunityFeatures",
        "AutoPrestigeRuntime","StandFarm","GameCatalog","Settings",
        "UIComponents","UI","Movement"
    }) do
        local m=modules[name]
        if m then
            local method=type(m.Destroy)=="function" and "Destroy"
                or (type(m.Stop)=="function" and "Stop" or nil)
            if method then
                local ok,err=pcall(m[method],m)
                if not ok then
                    moduleLog("WARN","[CleanHop] Cleanup "..name.." failed: "..tostring(err))
                end
            end
        end
    end
    if _G.WhiteHubModules==modules then _G.WhiteHubModules=nil end
    moduleLog("INFO","[CleanHop] Old runtime released; destination loader should reinitialize modules")
end

function ServerHop:CleanHop(canContinue)
    if canContinue~=nil and type(canContinue)~="function" then return false end
    if hopBusy or cleanHopRequested then return false end
    if _config and _config:Get("StayInPrivateServer") then
        moduleLog("INFO","[CleanHop] StayInPrivateServer ON; clean hop skipped")
        return false
    end
    if canContinue and not canContinue() then return false end
    if _modules and _modules.AutoPrestigeRuntime and
        type(_modules.AutoPrestigeRuntime.IsBusy)=="function" and
        _modules.AutoPrestigeRuntime:IsBusy() then
        moduleLog("WARN","[CleanHop] AutoPrestige has work pending; postponing teleport")
        return false
    end
    hopBusy=true
    cleanHopRequested=true
    cleanHopEpoch=cleanHopEpoch+1
    local epoch=cleanHopEpoch
    local transitionStarted=false
    local cleanupPerformed=false
    local originJob=tostring(game.JobId)
    local targetJob=nil
    disconnectCleanHopListeners()
    local function fail(reason)
        if epoch~=cleanHopEpoch then return end
        moduleLog("WARN","[CleanHop] Teleport request failed: "..tostring(reason)..
            "; existing runtime preserved")
        hopBusy=false
        cleanHopRequested=false
        disconnectCleanHopListeners()
    end
    local okSignal,signal=pcall(function()
        return Player.OnTeleport:Connect(function(state)
            if epoch~=cleanHopEpoch then return end
            if state==Enum.TeleportState.Failed then
                if not cleanupPerformed then fail("TeleportState.Failed") end
            elseif state==Enum.TeleportState.Started then
                transitionStarted=true
                moduleLog("INFO","[CleanHop] Teleport Started: source="..originJob..
                    " target="..tostring(targetJob).."; waiting for transfer confirmation")
            elseif state==Enum.TeleportState.InProgress then
                if cleanupPerformed then return end
                transitionStarted=true
                cleanupPerformed=true
                cleanHopShutdown(epoch)
                -- No old runtime updates after a confirmed transfer.
                disconnectCleanHopListeners()
            end
        end)
    end)
    if okSignal and signal then table.insert(cleanHopConnections,signal)
    else
        fail("Cannot monitor OnTeleport; clean transfer refused for safety")
        return false
    end
    local okFailure,failureSignal=pcall(function()
        return TeleportService.TeleportInitFailed:Connect(function(player,result,description)
            if epoch~=cleanHopEpoch or player~=Player then return end
            if not cleanupPerformed then
                fail(tostring(result)..": "..tostring(description))
            else
                moduleLog("WARN","[CleanHop] TeleportInitFailed after transfer began; relaunch WHITE HUB if still in old server")
            end
        end)
    end)
    if okFailure and failureSignal then table.insert(cleanHopConnections,failureSignal) end

    -- Matchmaking by PlaceId alone often returns to originJob. Reuse the
    -- proven server-list selector (which excludes game.JobId and visited IDs)
    -- while retaining the separate transfer-confirmed cleanup lifecycle.
    local function permitted()
        return epoch==cleanHopEpoch and cleanHopRequested and
            (not canContinue or canContinue())
    end
    local function selected(id)
        if not permitted() or tostring(id)==originJob then return false end
        targetJob=tostring(id)
        moduleLog("INFO","[CleanHop] Selected distinct destination: source="..
            originJob.." target="..targetJob)
        return true
    end
    moduleLog("INFO","[CleanHop] Searching for a different public JobId; source="..originJob)
    local ok,requested=pcall(function()
        if TPReturner(permitted,selected) then return true end
        if not permitted() then return false end
        -- Inspect at most the next page. Never fall back to PlaceId matchmaking
        -- or silently send the player to the original JobId.
        if foundAnything~="" then return TPReturner(permitted,selected) end
        return false
    end)
    if not ok then
        fail("server selection/teleport error: "..tostring(requested))
        return false
    end
    if not requested then
        fail("no eligible different public JobId found, or request canceled")
        return false
    end
    moduleLog("INFO","[CleanHop] Instance teleport requested: "..originJob..
        " -> "..tostring(targetJob).."; arrival NOT confirmed yet")
    -- A long transfer wait must not initiate a second teleport.
    -- Failure is handled by TeleportInitFailed / TeleportState.Failed.
    task.delay(45,function()
        if epoch==cleanHopEpoch and cleanHopRequested and not cleanupPerformed then
            moduleLog("WARN","[CleanHop] Still awaiting teleport after 45s (started="..
                tostring(transitionStarted).."); no automatic retry")
        end
    end)
    return true
end

function ServerHop:Hop(canContinue, onDestination)
    if canContinue ~= nil and type(canContinue) ~= "function" then return false end
    if onDestination ~= nil and type(onDestination) ~= "function" then return false end
    if hopBusy then return false end
    local cleanRequested=_config and _config:Get("CleanHopBeta")==true
    local prestigeTransfer=_modules and _modules.AutoPrestigeRuntime
        and type(_modules.AutoPrestigeRuntime.IsBusy)=="function"
        and _modules.AutoPrestigeRuntime:IsBusy()
    if cleanRequested and onDestination==nil and not prestigeTransfer then
        return self:CleanHop(canContinue)
    end
    if cleanRequested and (onDestination~=nil or prestigeTransfer) then
        moduleLog("INFO","[CleanHop] Protected transfer/ownership requires an exact server; using classic hop")
    end
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
    cleanHopEpoch=cleanHopEpoch+1
    cleanHopRequested=false
    disconnectCleanHopListeners()
    hopBusy=false
    kickEpoch = kickEpoch + 1
    prepareEpoch = prepareEpoch + 1
    prepareBusy, preparedSite, preparedURL = false, nil, nil
    if _kickConnection then
        pcall(function() _kickConnection:Disconnect() end)
        _kickConnection = nil
    end
end

return ServerHop
