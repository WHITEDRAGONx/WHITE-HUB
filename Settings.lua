-- Client presentation settings only; no farm, dialogue or inventory ownership.
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Settings = {}
local BUILD = "SETTINGS-YBA-20261018-R5-FPS"
local config, logger, ui, statusLabel, fpsLabel, overlayFpsLabel
local alive, capOn, lowOn, blackOn = false, false, false, false
local lowEpoch, lowConnections = 0, {}
local originals = setmetatable({}, {__mode="k"})
local fpsSetter, fpsPrevious, fpsAssumed
local overlay, recoveryConnection, fpsConnection
local qualityApplied, effectsChanged = false, 0
local messages = {cap="Off", low="Off", black="Off"}
local measuredFps=nil
local function publishFps()
    local reading=measuredFps and string.format("%d FPS",math.floor(measuredFps+0.5)) or "Measuring FPS..."
    if fpsLabel and fpsLabel.Parent then fpsLabel.Text="LIVE FPS: "..reading end
    if overlayFpsLabel and overlayFpsLabel.Parent then overlayFpsLabel.Text=reading end
end
local function startFpsMonitor()
    if fpsConnection then fpsConnection:Disconnect();fpsConnection=nil end
    local frames,seconds=0,0
    measuredFps=nil
    fpsConnection=RunService.RenderStepped:Connect(function(dt)
        if not alive then return end
        if type(dt)~="number" or dt<=0 or dt>1 then return end
        frames+=1;seconds+=dt
        if seconds>=0.8 then
            measuredFps=frames/seconds
            frames,seconds=0,0
            publishFps()
        end
    end)
end
local nativeState, nativeMessage = "idle", "Not requested"
local nativeIssued = false
-- The owner's R4 shows that YBA removes this control after activation. Keep an
-- issued request across Init/OFF to avoid toggling the native feature twice.
local nativeRequests = rawget(_G,"WhiteHubNativeLowGFXRequests")
if type(nativeRequests)~="table" then
    nativeRequests=setmetatable({}, {__mode="k"})
    rawset(_G,"WhiteHubNativeLowGFXRequests",nativeRequests)
end
local labels = {
    SettingsCapFPS30="Cap FPS at 30",
    SettingsLowGraphics="Low graphics",
    SettingsBlackScreen="Black screen",
}

local function log(level, message)
    if logger then pcall(logger.Write, logger, level, "Settings", message) end
end

local function refresh()
    if statusLabel and statusLabel.Parent then
        statusLabel.Text = "FPS: "..messages.cap.."\nGraphics: "..messages.low.."\nYBA: "..nativeMessage.."\nScreen: "..messages.black
    end
    if ui then
        ui:SetToggleValue(labels.SettingsCapFPS30, capOn)
        ui:SetToggleValue(labels.SettingsLowGraphics, lowOn)
        ui:SetToggleValue(labels.SettingsBlackScreen, blackOn)
    end
end

local function nativeTarget()
    local player=Players.LocalPlayer
    local parent=player and player:FindFirstChild("PlayerGui")
    local hud=parent and parent:FindFirstChild("HUD")
    local main=hud and hud:FindFirstChild("Main")
    local frames=main and main:FindFirstChild("Frames")
    local settings=frames and frames:FindFirstChild("Settings")
    local list=settings and settings:FindFirstChild("List")
    local row=list and list:FindFirstChild("ToggleLowGFX")
    local button=row and row:FindFirstChild("Button")
    return hud,list,row,button
end

local function nativeInput(button)
    if type(getconnections)~="function" then return nil,"Click inspection unsupported" end
    local ok,signal=pcall(function() return button.MouseButton1Click end)
    if not ok or not signal then return nil,"Click signal unavailable" end
    local inspected,connections=pcall(getconnections,signal)
    if not inspected or type(connections)~="table" then return nil,"Click inspection failed" end
    local handlers={}
    for _,connection in pairs(connections) do
        local enabled,connected,fire,fn
        pcall(function() enabled=connection.Enabled end)
        pcall(function() connected=connection.Connected end)
        pcall(function() fire=connection.Fire end)
        pcall(function() fn=connection.Function end)
        if enabled~=false and connected~=false and
            (type(fire)=="function" or type(fn)=="function") then
            handlers[#handlers+1]={connection=connection,fire=fire,fn=fn}
            if #handlers>16 then return nil,"Too many click handlers" end
        end
    end
    if #handlers==0 then return nil,"No inspectable click handler" end
    if #handlers==1 then
        local handler=handlers[1]
        -- Delta's bound connection input is already used by our dialogue code.
        -- A present firesignal can silently do nothing; do not prefer it here.
        if type(handler.fire)=="function" then
            return function() return handler.fire(handler.connection) end,"connection-fire",1
        end
        return handler.fn,"connection-function",1
    end
    if type(firesignal)=="function" then
        return function() return firesignal(signal) end,"firesignal",#handlers
    end
    return nil,"Multiple handlers need signal dispatch"
end

local function requestNativeLow(epoch)
    local function active() return alive and lowOn and epoch==lowEpoch end
    local function report(state,message,level)
        if not active() then return end
        nativeState,nativeMessage=state,message
        log(level or "INFO","[NativeLowGFX] "..message)
        refresh()
    end
    task.spawn(function()
        local hud,list,row,button
        -- UI may not have loaded yet. This bounded wait is cancelled by OFF/reload.
        for _=1,40 do
            if not active() then return end
            hud,list,row,button=nativeTarget()
            if list then break end
            task.wait(0.25)
        end
        if not active() then return end
        if not list then report("unavailable","Native menu unavailable; local effects only","WARN");return end
        local previous=nativeRequests[hud]
        if previous and previous.issued then
            nativeIssued=true
            if previous.state=="control_removed" then
                report("control_removed","Control removed after request; session change")
            else
                report(previous.state or "requested","Prior state="..tostring(previous.state).."; route="..tostring(previous.route).."; no retry")
            end
            return
        end
        if not row or not button then
            report("unavailable","Control absent: used already or unavailable","WARN");return
        end
        if not button:IsA("TextButton") or button.Text~="TOGGLE LOW GFX" then
            report("unavailable","Unexpected native control; local effects only","WARN");return
        end
        local dispatch,route,count=nativeInput(button)
        if not active() then return end
        if not dispatch then report("unsupported",route.."; local effects only","WARN");return end
        local record={issued=false,state="pending",route=route}
        nativeRequests[hud]=record
        local finished,callOk=false,false
        task.spawn(function()
            if not active() or nativeRequests[hud]~=record then return end
            local currentHud,currentList,currentRow,currentButton=nativeTarget()
            if currentHud~=hud or currentList~=list or currentRow~=row or currentButton~=button then
                finished=true;return
            end
            log("INFO","[NativeLowGFX] Dispatch route="..route.."; handlers="..tostring(count).."; result pending")
            if not active() then return end
            -- Set the guard before entering a yielding/native callback. A failure
            -- may already have side effects, so never try another input afterward.
            record.issued=true;record.state="requested"
            nativeIssued=true
            nativeState,nativeMessage="requested","Request issued; waiting for native UI"
            local ok,result=pcall(dispatch)
            callOk=ok and result~=false
            finished=true
        end)
        -- A game callback may yield. Observe its UI outcome for at most 8 seconds.
        for _=1,32 do
            if not active() then
                if record.issued and record.state=="requested" then record.state="observation_cancelled" end
                return
            end
            local currentHud,currentList=nativeTarget()
            if record.issued and currentHud==hud and currentList==list and row.Parent~=list then
                record.state="control_removed"
                report("control_removed","Control removed after request; session change")
                return
            end
            if finished and not callOk then
                record.state=record.issued and "failed" or "not_sent"
                report(record.state,"Request failed/changed UI; no automatic retry","WARN");return
            end
            task.wait(0.25)
        end
        if not active() then return end
        record.state="unconfirmed"
        report("unconfirmed","Request unconfirmed; no automatic retry","WARN")
    end)
end

local function fpsValue()
    local getter = getfpscap or get_fps_cap
    if type(getter) ~= "function" then return nil end
    local ok, value = pcall(getter)
    if ok and type(value)=="number" and value==value and value>=0 and value<math.huge then return value end
end

local function setCap(enabled)
    if enabled == capOn then return true end
    if enabled then
        local setter = setfpscap or set_fps_cap
        if type(setter) ~= "function" then
            messages.cap="Not supported by this executor"
            return false, "This executor does not support an FPS cap."
        end
        local previous = fpsValue()
        local ok, result = pcall(setter, 30)
        if not ok or result==false then
            messages.cap="Request failed"
            return false, "Could not apply the 30 FPS cap."
        end
        fpsSetter, fpsPrevious, fpsAssumed = setter, previous or 60, previous==nil
        capOn=true
        messages.cap=fpsAssumed and "30 requested; OFF restores 60" or "30 requested"
        if fpsAssumed then log("WARN", "Previous FPS cap unreadable; disabling will restore 60 FPS.") end
    else
        local current = fpsValue()
        -- Keep a cap changed by the player/another tool after our request.
        if current==nil or current==30 then
            local ok, result = pcall(fpsSetter, fpsPrevious)
            if not ok or result==false then
                messages.cap="Restore failed; retry OFF"
                return false, "Could not restore the previous FPS cap."
            end
        end
        capOn=false; fpsSetter=nil; fpsPrevious=nil; fpsAssumed=nil
        messages.cap="Off"
    end
    return true
end

local function change(object, property, value)
    local ok, before = pcall(function() return object[property] end)
    if not ok or before==nil or before==value then return false end
    local fields=originals[object]
    if fields and fields[property] then return false end
    local written = pcall(function() object[property]=value end)
    if not written then return false end
    fields=fields or {}; originals[object]=fields
    fields[property]={before=before, applied=value}
    return true
end

local function reduceEffect(object)
    if not lowOn then return end
    if object:IsA("PostEffect") or object:IsA("ParticleEmitter")
        or object:IsA("Trail") or object:IsA("Beam") then
        if change(object,"Enabled",false) then effectsChanged=effectsChanged+1 end
    end
end

local function restoreGraphics()
    for object, fields in pairs(originals) do
        for property, entry in pairs(fields) do
            pcall(function()
                if object[property]==entry.applied then object[property]=entry.before end
            end)
        end
    end
    originals=setmetatable({}, {__mode="k"})
end

local function setLow(enabled)
    if enabled==lowOn then return true end
    lowEpoch=lowEpoch+1
    for _,connection in ipairs(lowConnections) do pcall(function() connection:Disconnect() end) end
    lowConnections={}
    lowOn=enabled
    if not enabled then
        restoreGraphics(); qualityApplied=false; effectsChanged=0; messages.low="Off"
        if nativeState=="control_removed" then nativeMessage="Session change remains; rejoin to reset"
        elseif nativeIssued then nativeMessage="Local OFF; native request may need rejoin"
        else nativeState="idle";nativeMessage="Not requested" end
        return true
    end
    local ok, gameSettings=pcall(function() return UserSettings():GetService("UserGameSettings") end)
    if ok and gameSettings then
        local target=Enum.SavedQualitySetting.QualityLevel1
        local readable,current=pcall(function() return gameSettings.SavedQualityLevel end)
        qualityApplied=change(gameSettings,"SavedQualityLevel",target)
            or (readable and current==target)
    end
    change(Lighting,"GlobalShadows",false)
    messages.low=qualityApplied and "Low quality; reducing effects" or "Effects only; lower quality manually"
    nativeState,nativeMessage="pending","Waiting for native control"
    local epoch=lowEpoch
    requestNativeLow(epoch)
    local roots={workspace,Lighting}
    for _,root in ipairs(roots) do
        local connected, connection=pcall(function()
            return root.DescendantAdded:Connect(function(object)
                if alive and lowOn and epoch==lowEpoch then reduceEffect(object) end
            end)
        end)
        if connected then lowConnections[#lowConnections+1]=connection end
    end
    -- One initial scan, in small batches; no frame polling or geometry deletion.
    task.spawn(function()
        for _,root in ipairs(roots) do
            if not alive or not lowOn or epoch~=lowEpoch then return end
            local found, objects=pcall(function() return root:GetDescendants() end)
            if found then
                for index,object in ipairs(objects) do
                    if not alive or not lowOn or epoch~=lowEpoch then return end
                    reduceEffect(object)
                    if index%120==0 then task.wait() end
                end
            end
        end
        if not alive or not lowOn or epoch~=lowEpoch then return end
        messages.low=qualityApplied and "Low quality; effects reduced" or "Effects only; lower quality manually"
        refresh()
    end)
    return true
end

local function makeOverlay()
    local player=Players.LocalPlayer
    local parent=player and player:FindFirstChild("PlayerGui")
    if not parent then return false end
    overlay=Instance.new("ScreenGui")
    overlay.Name="WhiteHubBlackScreen"
    overlay.IgnoreGuiInset=true; overlay.ResetOnSpawn=false
    overlay.DisplayOrder=20; overlay.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
    overlay.Parent=parent
    local background=Instance.new("Frame",overlay)
    background.Name="BlackBackground"; background.Size=UDim2.new(1,0,1,0)
    background.BackgroundColor3=Color3.fromRGB(0,0,0)
    background.BorderSizePixel=0; background.Active=false
    local text=Instance.new("TextLabel",background)
    text.AnchorPoint=Vector2.new(0.5,0.5); text.Position=UDim2.new(0.5,0,0.25,0)
    text.Size=UDim2.new(0.9,0,0,68); text.BackgroundTransparency=1
    text.Text="BLACK SCREEN MODE\nWHITE HUB is still running."
    text.TextColor3=Color3.fromRGB(188,207,228); text.TextSize=16
    text.Font=Enum.Font.GothamMedium; text.TextWrapped=true
    local button=Instance.new("TextButton",background)
    button.Name="ShowGame"; button.AnchorPoint=Vector2.new(0.5,1)
    button.Position=UDim2.new(0.5,0,1,-28); button.Size=UDim2.new(0,180,0,44)
    button.Text="SHOW GAME"; button.TextSize=14; button.Font=Enum.Font.GothamBold
    button.BackgroundColor3=Color3.fromRGB(145,163,184)
    button.TextColor3=Color3.fromRGB(10,13,18); button.BorderSizePixel=0
    Instance.new("UICorner",button).CornerRadius=UDim.new(0,8)
    overlayFpsLabel=Instance.new("TextLabel",background)
    overlayFpsLabel.Name="LiveFPS"
    overlayFpsLabel.BackgroundTransparency=1
    overlayFpsLabel.AnchorPoint=Vector2.new(0.5,0.5)
    overlayFpsLabel.Position=UDim2.new(0.5,0,0.45,0)
    overlayFpsLabel.Size=UDim2.new(0.9,0,0,38)
    overlayFpsLabel.TextColor3=Color3.fromRGB(204,223,241)
    overlayFpsLabel.TextSize=24
    overlayFpsLabel.Font=Enum.Font.GothamBold
    overlayFpsLabel.Text="Measuring FPS..."
    publishFps()
    recoveryConnection=button.Activated:Connect(function()
        Settings:RestoreView()
    end)
    return true
end

local function setBlack(enabled)
    if enabled==blackOn then return true end
    if enabled then
        local ok, created=pcall(makeOverlay)
        if not ok or not created then
            if overlay then pcall(function() overlay:Destroy() end); overlay=nil end
            return false,"Could not create the black screen controls."
        end
        -- A native renderer pause can affect the game/executor's frame-driven
        -- code. This mode only draws a UI cover; the engine keeps running.
        blackOn=true
        messages.black="Black screen: visual only"
    else
        if recoveryConnection then recoveryConnection:Disconnect(); recoveryConnection=nil end
        if overlay then overlay:Destroy(); overlay=nil end
        overlayFpsLabel=nil
        blackOn=false; messages.black="Off"
    end
    return true
end

local actions={SettingsCapFPS30=setCap, SettingsLowGraphics=setLow, SettingsBlackScreen=setBlack}
function Settings:SetOption(key,enabled)
    if not alive or not actions[key] or type(enabled)~="boolean" then return false,"Unknown setting." end
    local ok, reason=actions[key](enabled)
    if ok then config:Set(key,enabled) end
    log(ok and "INFO" or "WARN", ok and labels[key].." = "..tostring(enabled) or tostring(reason))
    refresh()
    return ok,reason
end
function Settings:GetStatus()
    return {build=BUILD,cap30=capOn,low=lowOn,black=blackOn,rendering_paused=false,
        native_low_gfx=nativeState,
        message="FPS: "..messages.cap.." | Graphics: "..messages.low.." | YBA: "..nativeMessage.." | Screen: "..messages.black}
end
function Settings:RestoreView()
    local ok,reason=setBlack(false)
    if ok and config then config:Set("SettingsBlackScreen",false) end
    if not ok then log("WARN",tostring(reason)) end
    refresh()
    return ok,reason
end
function Settings:Build(page,owner,makeToggle,theme)
    local status=self:GetStatus()
    for _,option in ipairs({{"SettingsCapFPS30",status.cap30},{"SettingsLowGraphics",status.low},{"SettingsBlackScreen",status.black}}) do
        local key=option[1]
        makeToggle(page,labels[key],option[2],function(enabled)
            local ok,reason=self:SetOption(key,enabled)
            if not ok then owner:ShowPopup(reason,5) end
        end)
    end
    fpsLabel=owner:AddLabel(page,"LIVE FPS: Measuring FPS...")
    fpsLabel.Size=UDim2.new(1,-4,0,26)
    fpsLabel.TextSize=15
    fpsLabel.Font=Enum.Font.GothamBold
    fpsLabel.TextColor3=theme.GOLD_BRIGHT or theme.WHITE
    publishFps()
    statusLabel=owner:AddLabel(page,"")
    statusLabel.Size=UDim2.new(1,-4,0,86); statusLabel.TextWrapped=true; statusLabel.TextSize=10
    statusLabel.TextColor3=theme.MUTED
    local note=owner:AddLabel(page,"Graphics: includes one native YBA Low GFX request.\nNative changes may need a rejoin to undo.\nEnable Black screen manually each load.")
    note.Size=UDim2.new(1,-4,0,52); note.TextWrapped=true; note.TextSize=10
    ui=owner; refresh()
end
function Settings:Init(modules)
    self:Destroy()
    config,logger=modules.Config,modules.RuntimeLog
    alive=true
    startFpsMonitor()
    if config:Get("SettingsBlackScreen")==true then
        config:Set("SettingsBlackScreen",false)
        log("INFO","Saved Black screen reset to OFF; enable the visual mode manually.")
    end
    for _,key in ipairs({"SettingsCapFPS30","SettingsLowGraphics"}) do
        if config:Get(key)==true then
            local ok,reason=actions[key](true)
            if not ok then log("WARN",tostring(reason)) end
        end
    end
    log("INFO","Build "..BUILD.."; Black screen is visual only and starts OFF.")
end
function Settings:Destroy()
    alive=false; ui=nil; statusLabel=nil; fpsLabel=nil;overlayFpsLabel=nil
    if fpsConnection then fpsConnection:Disconnect();fpsConnection=nil end
    measuredFps=nil
    setLow(false)
    local capOk,capReason=setCap(false)
    local blackOk,blackReason=setBlack(false)
    if not capOk then log("WARN",tostring(capReason)) end
    if not blackOk then log("WARN",tostring(blackReason)) end
end
return Settings
