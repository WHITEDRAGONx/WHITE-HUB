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
