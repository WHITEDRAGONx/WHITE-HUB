-- Presentation only: reparent controls without replacing callbacks or config keys.
local Compact={}
local captions={
 ['Enable Farm']='Item farm', ['Auto Buy Lucky']='Buy Lucky',
 ['Stay in Private Server']='Stay in server', ['Auto Restock Consumables (BETA)']='Auto restock',
 ['Hop After Restock Limit (BETA)']='Restock hop', ['Auto Resume Owned Hop (BETA)']='Resume owned hop',
 ['Shiny Farm Mode (BETA)']='Shiny mode', ['Stand Farm (BETA)']='Stand farm',
 ['Add Skill (press a key)']='Add skill', ['Clear Skills']='Clear skills',
 ['CANCEL RESTOCK TRANSFER / STOP']='STOP / CANCEL HOP',
 ['CLEAR LIST / USE SINGLE TARGET']='CLEAR TARGETS',
 ['RESET STAND SESSION STATISTICS']='RESET STATS',
 ['COPY LATEST PROPOSAL LINK']='COPY PROPOSAL', ['SAVE HTTPS ENDPOINT']='SAVE ENDPOINT',
 ['Stand consumable']='Consumable', ['Target Stand']='Stand', ['Select Quest']='Quest', ['Select NPC']='NPC',
 ['WHITE AI V1 - DIAGNOSTICS']='AI DIAGNOSTICS', ['STAND FARM - EXPERIMENTAL']='STAND / BETA',
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
