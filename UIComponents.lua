-- WHITE HUB shared UI components; subcomponents retain isolated local state.
-- BEGIN Compact
local Compact = (function()
-- Presentation only: reparent controls without replacing callbacks or config keys.
local Compact={}
local captions={
 ['Auto Prestige']='Auto prestige (BETA)',
 ['Enable Farm']='Item farm', ['Auto Buy Lucky']='Buy Lucky',
 ['Stay in Private Server']='Stay in server', ['Auto Restock Consumables (BETA)']='Auto restock',
 ['Hop After Restock Limit (BETA)']='Restock hop', ['Auto Resume Owned Hop (BETA)']='Resume owned hop',
 ['Shiny Farm Mode (BETA)']='Shiny mode', ['Stand Farm (BETA)']='Stand farm',
 ['Add Skill (press a key)']='Add skill', ['Clear Skills']='Clear skills',
 ['CANCEL RESTOCK TRANSFER / STOP']='STOP / CANCEL HOP',

 ['Stand consumable']='Consumable', ['Target Stand']='Stand', ['Select Quest']='Quest', ['Select NPC']='NPC',
 ['STAND FARM - EXPERIMENTAL']='STAND / BETA',
 ['FARM SETTINGS']='AUTOMATION', ['QUEST FARM']='QUEST', ['NPC FARM']='NPC',
}
function Compact:Init() end
function Compact:Caption(text) return captions[text] or text end
function Compact:Observe(page,track)
 local serial=0
 track(page.ChildAdded:Connect(function(child)
  if child:IsA('GuiObject') then serial=serial+1; child.LayoutOrder=serial end
 end))
end
function Compact:ScaleFor(object)
 local factor=1
 local node=object
 while node do
  local scale=node:FindFirstChildOfClass('UIScale')
  if scale then factor=factor*scale.Scale end
  node=node.Parent
 end
 return factor>0 and factor or 1
end
local function list(parent,track,padding)
 local layout=Instance.new('UIListLayout',parent)
 layout.SortOrder=Enum.SortOrder.LayoutOrder; layout.Padding=UDim.new(0,padding or 3)
 local function fit() parent.Size=UDim2.new(1,-4,0,layout.AbsoluteContentSize.Y / Compact:ScaleFor(parent)+4) end
 track(layout:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(fit)); fit()
 return layout
end
function Compact:Arrange(page,track,theme)
 if page:GetAttribute('CompactGrouped') then return end
 page:SetAttribute('CompactGrouped',true)
 local nodes={}
 for _,child in ipairs(page:GetChildren()) do if child:IsA('GuiObject') then nodes[#nodes+1]=child end end
 table.sort(nodes,function(a,b) return a.LayoutOrder<b.LayoutOrder end)
 local card,groups=nil,nil
 local function createCard(header)
  local root=Instance.new('Frame',page); root.Name='ControlCard'
  root.BackgroundColor3=theme.PANEL; root.BorderSizePixel=0
  Instance.new('UICorner',root).CornerRadius=UDim.new(0,7)
  local stroke=Instance.new('UIStroke',root); stroke.Color=theme.GOLD_EDGE; stroke.Transparency=0.78
  list(root,track,3)
  if header then header.Parent=root; header.LayoutOrder=0; header.BackgroundTransparency=1 end
  return root,{}
 end
 for _,node in ipairs(nodes) do
  if node.Name=='Section' then card,groups=createCard(node)
  else
   if not card then card,groups=createCard() end
   local kind,order
   if node.Name=='ToggleRow' then kind,order='Switches',10
   elseif node.Name=='DropdownRow' or node:IsA('TextBox') then kind,order='Fields',20
   elseif node:IsA('TextButton') then kind,order='Actions',30
   else kind,order='Status',40 end
   local group=groups[kind]
   if not group then
    group=Instance.new('Frame',card); group.Name=kind; group.LayoutOrder=order
    group.BackgroundTransparency=1; list(group,track,3); groups[kind]=group
   end
   node.Parent=group
   if node:IsA('TextButton') then
    node.Text=self:Caption(node.Text); node.TextScaled=false; node.TextSize=10
    node.TextTruncate=Enum.TextTruncate.AtEnd; node.Size=UDim2.new(1,-4,0,27)
   elseif node:IsA('TextBox') then
    node.TextSize=11; node.Size=UDim2.new(1,-4,0,28)
   end
  end
 end
end
function Compact:Responsive(frame,width,height,track)
 local camera=workspace.CurrentCamera
 if not camera then return end
 local scale=Instance.new('UIScale',frame)
 local function update()
  local view=camera.ViewportSize
  scale.Scale=math.min(1,view.X*0.78/width,view.Y*0.68/height)
 end
 update(); track(camera:GetPropertyChangedSignal('ViewportSize'):Connect(update))
end
return Compact

end)()
-- END Compact

-- BEGIN Choice
local Choice = (function()
-- Native compact searchable choices. Only selection/config callbacks run here.
local Choice={}
local catalog,overlay,connections=nil,nil,{}
function Choice:Init(modules) catalog=modules.GameCatalog end
function Choice:Close()
 for _,c in ipairs(connections) do pcall(function() c:Disconnect() end) end
 connections={}
 if overlay then overlay:Destroy(); overlay=nil end
end
function Choice:Destroy() self:Close() end
function Choice:Toggle(current,name,limit)
 if type(name)~='string' or name=='' or name=='None' or #name>100 or name:find('%c') then return nil,'Invalid choice' end
 local names=catalog:Names(current); local index=table.find(names,name)
 if index then table.remove(names,index)
 elseif #names<(limit or 25) then names[#names+1]=name; table.sort(names)
 else return nil,'Selection limit: '..tostring(limit or 25) end
 return names
end
function Choice:Filter(options,query)
 local result={}; query=tostring(query or ''):lower()
 for _,name in ipairs(options) do
  if type(name)=='string' and (query=='' or name:lower():find(query,1,true)) then result[#result+1]=name end
 end
 return result
end
function Choice:Build(parent,label,getOptions,getSelected,setSelected,beforeChange,UI,theme,track,single)
 local row=Instance.new('Frame',parent); row.Name='DropdownRow'; row.Size=UDim2.new(1,-4,0,30)
 row.BackgroundColor3=theme.PANEL; row.BorderSizePixel=0
 Instance.new('UICorner',row).CornerRadius=UDim.new(0,7)
 local title=Instance.new('TextLabel',row); title.BackgroundTransparency=1
 title.Position=UDim2.new(0,8,0,0); title.Size=UDim2.new(0.4,-8,1,0)
 title.Text=label; title.TextSize=11; title.Font=Enum.Font.Gotham; title.TextColor3=theme.WHITE
 title.TextXAlignment=Enum.TextXAlignment.Left
 local button=Instance.new('TextButton',row); button.Position=UDim2.new(0.4,0,0,3)
 button.Size=UDim2.new(0.6,-6,1,-6); button.BackgroundColor3=theme.PANEL2
 button.TextColor3=theme.WHITE; button.TextSize=11; button.Font=Enum.Font.Gotham
 button.TextTruncate=Enum.TextTruncate.AtEnd; button.BorderSizePixel=0
 Instance.new('UICorner',button).CornerRadius=UDim.new(0,6)
 local function refresh()
  local selected=getSelected()
  button.Text=#selected==0 and 'Select...' or (#selected==1 and selected[1] or tostring(#selected)..' selected')
 end
 refresh()
 track(button.MouseButton1Click:Connect(function()
  self:Close()
  overlay=Instance.new('ScreenGui',game:GetService('Players').LocalPlayer:WaitForChild('PlayerGui'))
  overlay.Name='WhiteHubChoices'; overlay.IgnoreGuiInset=true; overlay.ResetOnSpawn=false; overlay.DisplayOrder=100
  local outside=Instance.new('TextButton',overlay); outside.BackgroundTransparency=1; outside.Text=''
  outside.Size=UDim2.new(1,0,1,0)
  connections[#connections+1]=outside.MouseButton1Click:Connect(function() self:Close() end)
  local panel=Instance.new('Frame',overlay); panel.Active=true; panel.ZIndex=2
  panel.BackgroundColor3=theme.PANEL2; panel.BorderSizePixel=0
  local view=workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(640,360)
  local width,height=math.min(280,view.X-16),math.min(224,view.Y-16)
  local p=button.AbsolutePosition; local size=button.AbsoluteSize
  panel.Size=UDim2.new(0,width,0,height)
  panel.Position=UDim2.new(0,math.max(8,math.min(p.X,view.X-width-8)),0,math.max(8,math.min(p.Y+size.Y,view.Y-height-8)))
  Instance.new('UICorner',panel).CornerRadius=UDim.new(0,8)
  if workspace.CurrentCamera then
   connections[#connections+1]=workspace.CurrentCamera:GetPropertyChangedSignal('ViewportSize'):Connect(function() self:Close() end)
  end
  local search=Instance.new('TextBox',panel); search.ZIndex=3; search.Size=UDim2.new(1,-12,0,28)
  search.Position=UDim2.new(0,6,0,6); search.BackgroundColor3=theme.PANEL; search.TextColor3=theme.WHITE
  search.PlaceholderText='Search...'; search.Text=''; search.TextSize=12; search.Font=Enum.Font.Gotham
  search.ClearTextOnFocus=false; search.BorderSizePixel=0
  local list=Instance.new('ScrollingFrame',panel); list.ZIndex=3; list.BackgroundTransparency=1; list.BorderSizePixel=0
  list.Position=UDim2.new(0,6,0,38); list.Size=UDim2.new(1,-12,1,-44); list.ScrollBarThickness=3
  local layout=Instance.new('UIListLayout',list); layout.Padding=UDim.new(0,2); layout.SortOrder=Enum.SortOrder.LayoutOrder
  local options=catalog:Names(getOptions(),getSelected()); local rows={}
  local function mark()
   local selected=getSelected()
   for _,entry in ipairs(rows) do entry.button.Text=(table.find(selected,entry.name) and '[x] ' or '[ ] ')..entry.name end
   refresh()
  end
  for i,name in ipairs(options) do
   local option=Instance.new('TextButton',list); option.ZIndex=4; option.LayoutOrder=i
   option.Size=UDim2.new(1,-5,0,26); option.BackgroundColor3=theme.PANEL3; option.BorderSizePixel=0
   option.TextColor3=theme.WHITE; option.TextSize=11; option.Font=Enum.Font.Gotham
   option.TextXAlignment=Enum.TextXAlignment.Left; option.TextTruncate=Enum.TextTruncate.AtEnd
   rows[#rows+1]={button=option,name=name}
   connections[#connections+1]=option.MouseButton1Click:Connect(function()
    local value,reason
    if single then value={name} else value,reason=self:Toggle(getSelected(),name,25) end
    if not value then UI:ShowPopup(reason,4); return end
    if beforeChange then beforeChange() end
    if setSelected(value)==false then return end
    mark(); if single then self:Close() end
   end)
  end
  local function filter()
   local matches={}; for _,name in ipairs(self:Filter(options,search.Text)) do matches[name]=true end
   local count=0
   for _,entry in ipairs(rows) do entry.button.Visible=matches[entry.name]==true; if entry.button.Visible then count=count+1 end end
   list.CanvasSize=UDim2.new(0,0,0,count*28); list.CanvasPosition=Vector2.new(0,0)
  end
  connections[#connections+1]=search:GetPropertyChangedSignal('Text'):Connect(filter)
  connections[#connections+1]=row.AncestryChanged:Connect(function() self:Close() end)
  mark(); filter()
 end))
 return button,refresh
end
return Choice

end)()
-- END Choice

-- BEGIN Stand
local Stand = (function()
-- Scoped Stand controls; the parent UI owns connections.
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

end)()
-- END Stand

local Components={Compact=Compact,Choice=Choice,Stand=Stand}
function Components:Init(modules)
    Compact:Init(modules); Choice:Init(modules); Stand:Init(modules)
end
function Components:Destroy() Choice:Destroy() end
return Components
