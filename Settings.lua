-- Client presentation settings only; no farm, dialogue or inventory ownership.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Settings = {}
local config, logger, ui, statusLabel
local alive, capOn, lowOn, blackOn = false, false, false, false
local lowEpoch, lowConnections = 0, {}
local originals = setmetatable({}, {__mode="k"})
local fpsSetter, fpsPrevious, fpsAssumed
local overlay, recoveryConnection, renderChanged, renderPrevious, renderPaused
local qualityApplied, effectsChanged = false, 0
local messages = {cap="Off", low="Off", black="Off"}
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
        statusLabel.Text = "FPS: "..messages.cap.."\nGraphics: "..messages.low.."\nScreen: "..messages.black
    end
    if ui then
        ui:SetToggleValue(labels.SettingsCapFPS30, capOn)
        ui:SetToggleValue(labels.SettingsLowGraphics, lowOn)
        ui:SetToggleValue(labels.SettingsBlackScreen, blackOn)
    end
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
    local epoch=lowEpoch
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
    local parent=player and (player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui",10))
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
    recoveryConnection=button.Activated:Connect(function()
        -- Recovery also remains available after a failed Destroy-time resume.
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
        renderPrevious=true
        pcall(function()
            local value=RunService:Is3dRenderingEnabled()
            if type(value)=="boolean" then renderPrevious=value end
        end)
        local ok,result=pcall(function() return RunService:Set3dRenderingEnabled(false) end)
        local paused=ok and result~=false
        renderPaused=paused
        renderChanged=paused and renderPrevious
        blackOn=true
        messages.black=paused and "Black screen; 3D rendering paused" or "View hidden; 3D rendering still on"
    else
        if renderChanged then
            local ok,result=pcall(function() return RunService:Set3dRenderingEnabled(renderPrevious) end)
            if not ok or result==false then return false,"Could not resume 3D rendering. Try SHOW GAME again." end
        end
        if recoveryConnection then recoveryConnection:Disconnect(); recoveryConnection=nil end
        if overlay then overlay:Destroy(); overlay=nil end
        renderChanged=nil; renderPrevious=nil; renderPaused=nil; blackOn=false; messages.black="Off"
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
    return {cap30=capOn,low=lowOn,black=blackOn,rendering_paused=renderPaused==true,
        message="FPS: "..messages.cap.." | Graphics: "..messages.low.." | Screen: "..messages.black}
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
    statusLabel=owner:AddLabel(page,"")
    statusLabel.Size=UDim2.new(1,-4,0,66); statusLabel.TextWrapped=true; statusLabel.TextSize=10
    statusLabel.TextColor3=theme.MUTED
    local note=owner:AddLabel(page,"Saved options apply on the next load.\nSHOW GAME restores the view.")
    note.Size=UDim2.new(1,-4,0,38); note.TextWrapped=true; note.TextSize=10
    ui=owner; refresh()
end
function Settings:Init(modules)
    self:Destroy()
    config,logger=modules.Config,modules.RuntimeLog
    alive=true
    for _,key in ipairs({"SettingsCapFPS30","SettingsLowGraphics","SettingsBlackScreen"}) do
        if config:Get(key)==true then
            local ok,reason=actions[key](true)
            if not ok then log("WARN",tostring(reason)) end
        end
    end
    log("INFO","Settings ready; saved performance options applied where supported.")
end
function Settings:Destroy()
    alive=false; ui=nil; statusLabel=nil
    setLow(false)
    local capOk,capReason=setCap(false)
    local blackOk,blackReason=setBlack(false)
    if not capOk then log("WARN",tostring(capReason)) end
    if not blackOk then log("WARN",tostring(blackReason)) end
end
return Settings
