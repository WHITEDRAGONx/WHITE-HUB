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
function StandV2UI:BuildSkins(FarmPage,UI,_config,_standFarm,stopForTargetEdit,trackConnection,THEME)
    local skinInput=Instance.new("TextBox",FarmPage)
    skinInput.Size=UDim2.new(1,-4,0,36)
    skinInput.Font=Enum.Font.Code
    skinInput.TextSize=12
    skinInput.BackgroundColor3=THEME.PANEL2
    skinInput.TextColor3=THEME.WHITE
    skinInput.ClearTextOnFocus=false
    skinInput.PlaceholderText="Desired skins separated by semicolons"
    local savedSkins=_config and _config:Get("StandFarmSkinTargets")
    local safeSkins={}
    if type(savedSkins)=="table" then
        for _,name in ipairs(savedSkins) do if type(name)=="string" then safeSkins[#safeSkins+1]=name end end
    end
    skinInput.Text=table.concat(safeSkins,"; ")
    trackConnection(skinInput.FocusLost:Connect(function()
        if not _config then return end
        local names,seen={},{}
        for entry in skinInput.Text:gmatch("[^;]+") do
            local name=entry:match("^%s*(.-)%s*$")
            if name=="None" or #name>100 or name:find("%c") then
                UI:ShowPopup("Invalid skin name; list unchanged",4); return
            end
            if name~="" and not seen[name] then names[#names+1]=name; seen[name]=true end
        end
        if #names>25 then UI:ShowPopup("Skin list limit: 25",4); return end
        stopForTargetEdit()
        _config:Set("StandFarmSkinTargets",names)
        skinInput.Text=table.concat(names,"; ")
    end))

end
function StandV2UI:BuildStats(FarmPage,UI,_standFarm,trackConnection,styleActionButton)
    local pityStats=UI:AddLabel(FarmPage,"")
    pityStats.TextScaled=false
    pityStats.TextWrapped=true
    pityStats.Size=UDim2.new(1,-4,0,50)
    pityStats.TextSize=10
    local resetStats=Instance.new("TextButton",FarmPage)
    resetStats.Size=UDim2.new(1,-4,0,32)
    resetStats.Text="RESET STAND SESSION STATISTICS"
    resetStats.Font=Enum.Font.GothamBold
    resetStats.TextSize=11
    styleActionButton(resetStats,false)
    trackConnection(resetStats.MouseButton1Click:Connect(function()
        if _standFarm then
            local ok,reason=_standFarm:ResetStatistics()
            if not ok then UI:ShowPopup(tostring(reason),5) end
        end
    end))
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
