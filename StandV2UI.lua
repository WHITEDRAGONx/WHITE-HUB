-- DEV ONLY: scoped Stand V2 controls; existing GOLD UI helpers own connections.
local StandV2UI={}
function StandV2UI:Init() end
function StandV2UI:BuildResume(FarmPage,UI,_config,_standFarm,MakeToggle,trackConnection,THEME)
    MakeToggle(FarmPage, "Auto Resume Owned Hop (BETA)",
        (_config and _config:Get("StandFarmResumeAfterHop")) == true, function(enabled)
            if _standFarm then _standFarm:Stop(); UI:SetToggleValue("Stand Farm (BETA)", false) end
            if _config then _config:Set("StandFarmResumeAfterHop", enabled) end
            if enabled and _standFarm and not _standFarm:GetResumeSupport() then
                UI:ShowPopup("Executor lacks files/teleport queue support. Manual restart remains required.",6)
            end
        end)
    local hopBudgetInput=Instance.new("TextBox",FarmPage)
    hopBudgetInput.Size=UDim2.new(1,-4,0,30)
    hopBudgetInput.Font=Enum.Font.Code
    hopBudgetInput.TextSize=12
    hopBudgetInput.BackgroundColor3=THEME.PANEL2
    hopBudgetInput.TextColor3=THEME.WHITE
    hopBudgetInput.Text="Auto hop limit: " .. tostring(_config and _config:Get("StandFarmMaxHops") or 3)
    hopBudgetInput.ClearTextOnFocus=false
    trackConnection(hopBudgetInput.FocusLost:Connect(function()
        local value=tonumber(hopBudgetInput.Text:match("(%d+)"))
        if value and value>=1 and value<=5 and _config then
            if _standFarm then _standFarm:Stop(); UI:SetToggleValue("Stand Farm (BETA)",false) end
            _config:Set("StandFarmMaxHops",value)
        end
        hopBudgetInput.Text="Auto hop limit: " .. tostring(_config and _config:Get("StandFarmMaxHops") or 3)
    end))
end
function StandV2UI:BuildSkins(FarmPage,UI,_config,_standFarm,stopForTargetEdit,trackConnection,THEME,choices,catalog)
    choices:Build(FarmPage,"Skins",
        function() return catalog:GetSkins(_config and _config:Get("StandFarmSkinTargets")) end,
        function() return catalog:Names(_config and _config:Get("StandFarmSkinTargets")) end,
        function(names)
            if not _config then return false end
            _config:Set("StandFarmSkinTargets",names)
        end,stopForTargetEdit,UI,THEME,trackConnection)
end
function StandV2UI:BuildStats(FarmPage,UI,_standFarm,trackConnection,styleActionButton)
    local pityStats=UI:AddLabel(FarmPage,"")
    pityStats.TextScaled=false
    pityStats.TextWrapped=true
    pityStats.Size=UDim2.new(1,-4,0,50)
    pityStats.TextSize=10
    task.spawn(function()
        while pityStats.Parent do
            if _standFarm then
                local state=_standFarm:GetStatus()
                local m=state.metrics or {}
                pityStats.Text=("Pity: %s | Remaining: %s | Delta: %s\nAttempts: %d | Arrow: %d | Rib: %d | Roka: %d\nRolls/h: %.1f | Restocks: %d | Chain hops: %d | Last skin: %s"):format(
                    tostring(state.pity or "?"),tostring(m.pity_remaining or "off"),tostring(m.pity_delta or "?"),
                    m.attempts or 0,m.arrows or 0,m.ribs or 0,m.rokas or 0,m.rolls_per_hour or 0,
                    m.restocks or 0,m.hops or 0,tostring(m.lastSkin or ""))
            end
            task.wait(2)
        end
    end)
end
return StandV2UI
