"""Presentation helpers and wiring; native Roblox rendering still needs Delta QA."""
from pathlib import Path
import re,subprocess,unittest
from lupa import LuaRuntime
from ai.autofix import check_luau
ROOT=Path(__file__).resolve().parents[1]
MOCK=r'''
Enum={SortOrder={LayoutOrder='LayoutOrder'},TextTruncate={AtEnd='end'}}
UDim={new=function(a,b) return {a,b} end}
UDim2={new=function(a,b,c,d) return {X={Scale=a,Offset=b},Y={Scale=c,Offset=d}} end}
local methods={}
local function signal()
 return {Connect=function(self,fn) self.fn=fn; return {Disconnect=function() self.disconnected=true end} end}
end
function methods:IsA(class) return self.class==class or class=='GuiObject' and self.class~='UIListLayout' and self.class~='UICorner' and self.class~='UIStroke' and self.class~='UIScale' end
function methods:GetChildren() local out={} for _,c in ipairs(self.children) do if c.Parent==self then out[#out+1]=c end end return out end
function methods:GetAttribute(k) return self.attributes[k] end
function methods:SetAttribute(k,v) self.attributes[k]=v end
function methods:FindFirstChildOfClass(class) for _,c in ipairs(self:GetChildren()) do if c:IsA(class) then return c end end end
function methods:GetPropertyChangedSignal(k) self.signals[k]=self.signals[k] or signal(); return self.signals[k] end
local mt={__index=function(t,k) if k=='Parent' then return rawget(t,'parent') end; return methods[k] end,
 __newindex=function(t,k,v) if k=='Parent' then rawset(t,'parent',v); if v then table.insert(v.children,t); if v.ChildAdded.fn then v.ChildAdded.fn(t) end end else rawset(t,k,v) end end}
function node(class,parent,name)
 local n=setmetatable({class=class,Name=name or class,children={},signals={},attributes={},LayoutOrder=0,AbsoluteContentSize={Y=0},ChildAdded=signal()},mt)
 if parent then n.Parent=parent end
 return n
end
Instance={new=node}
tracked={}; function track(c) table.insert(tracked,c); return c end
theme={PANEL='charcoal',GOLD_EDGE='silver'}
workspace={CurrentCamera={ViewportSize={X=1108,Y=512},GetPropertyChangedSignal=function(self,k) self.changed=signal(); return self.changed end}}
'''
class SilverHelperTests(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime(unpack_returned_tuples=True);self.lua.execute(MOCK)
  self.lua.globals().compact=self.lua.execute((ROOT/'UICompact.lua').read_text())
 def run_lua(self,s):self.lua.execute(s)
 def test_groups_types_and_retains_callback_objects(self):
  self.run_lua('''
  page=node('ScrollingFrame'); compact:Observe(page,track)
  h=node('Frame',page,'Section'); sw=node('Frame',page,'ToggleRow')
  box=node('TextBox',page); action=node('TextButton',page); action.Text='CLEAR LIST / USE SINGLE TARGET'
  status=node('TextLabel',page); dd=node('Frame',page,'DropdownRow')
  action.callback=function() fired=true end
  compact:Arrange(page,track,theme)
  assert(sw.Parent.Name=='Switches' and box.Parent.Name=='Fields' and dd.Parent==box.Parent)
  assert(action.Parent.Name=='Actions' and status.Parent.Name=='Status')
  action.callback(); assert(fired and action.Text=='CLEAR TARGETS')
  assert(sw.Parent.Parent==h.Parent and box.TextSize==11 and action.Size.Y.Offset==27)
  ''')
 def test_separate_sections_stay_separate_and_arrange_is_idempotent(self):
  self.run_lua("page=node('ScrollingFrame'); compact:Observe(page,track); h=node('Frame',page,'Section'); a=node('Frame',page,'ToggleRow'); h2=node('Frame',page,'Section'); b=node('Frame',page,'ToggleRow'); compact:Arrange(page,track,theme); assert(a.Parent.Parent~=b.Parent.Parent); local n=#page:GetChildren(); compact:Arrange(page,track,theme); assert(#page:GetChildren()==n)")
 def test_capture_order_is_stable_without_destroying_controls(self):
  self.run_lua("page=node('ScrollingFrame'); compact:Observe(page,track); a=node('TextButton',page); a.Text='A'; b=node('TextButton',page); b.Text='B'; assert(a.LayoutOrder<b.LayoutOrder); compact:Arrange(page,track,theme); assert(a.LayoutOrder<b.LayoutOrder and a.Parent==b.Parent)")
 def test_scale_is_accounted_for_in_group_height(self):
  self.run_lua("root=node('Frame'); sc=node('UIScale',root); sc.Scale=0.5; page=node('ScrollingFrame',root); compact:Observe(page,track); a=node('Frame',page,'ToggleRow'); compact:Arrange(page,track,theme); local group=a.Parent; local layout=group:FindFirstChildOfClass('UIListLayout'); layout.AbsoluteContentSize.Y=20; layout.signals.AbsoluteContentSize.fn(); assert(group.Size.Y.Offset==44 and compact:ScaleFor(group)==0.5)")
 def test_viewport_resize_bounds_and_tracked_connection(self):
  self.run_lua("f=node('Frame'); compact:Responsive(f,380,290,track); local scale=f:FindFirstChildOfClass('UIScale'); assert(scale.Scale==1); workspace.CurrentCamera.ViewportSize={X=640,Y=360}; workspace.CurrentCamera.changed.fn(); assert(scale.Scale<1 and 380*scale.Scale<=640 and 290*scale.Scale<=360)")
 def test_alias_does_not_replace_functional_registry_key(self):
  self.run_lua("assert(compact:Caption('Stand Farm (BETA)')=='Stand farm'); assert(compact:Caption('Unknown')=='Unknown')")

class SilverWiringTests(unittest.TestCase):
 def test_syntax_and_loader_contract(self):
  for name in ['UI.lua','UICompact.lua','StandV2UI.lua','WhiteAI.lua','DevMain.lua']:
   self.assertTrue(check_luau((ROOT/name).read_text()),name)
  loader=(ROOT/'DevMain.lua').read_text(); self.assertIn('{ key = "UICompact", file = "UICompact.lua" }',loader)
  self.assertIn('"UICompact", "WhiteAI", "UI"',loader)
 def test_stand_is_separate_and_keys_callbacks_preserved(self):
  src=(ROOT/'UI.lua').read_text()
  self.assertIn('local StandPage   = MakePage("StandPage")',src)
  self.assertIn('local FarmPage = StandPage',src)
  self.assertIn('{ name="Stand",   page=StandPage',src)
  self.assertIn('toggleObjects[labelText]',src)
  for key in ['StandFarmResumeAfterHop','StandFarmMode','StandFarmTargets','QuestFarmEnabled','NPCFarmEnabled','WhiteAIEnabled']:
   # Resume key lives in the existing helper.
   self.assertIn(key,src+(ROOT/'StandV2UI.lua').read_text())
 def test_no_scaled_text_or_explanatory_blocks(self):
  src=(ROOT/'UI.lua').read_text()
  self.assertNotRegex(src,r'TextScaled\s*=\s*true')
  self.assertNotIn('Uses Rokakaka +',src)
  self.assertNotIn('Local error detection is always on.',src)
  self.assertLess(len(src.encode()),80000)
 def test_english_user_facing_strings(self):
  for name in ['UI.lua','WhiteAI.lua','StandV2UI.lua','UICompact.lua']:
   src=(ROOT/name).read_text()
   for literal in re.findall(r'"(?:[^"\\]|\\.)*"',src):
    self.assertNotRegex(literal,r'[ãáéíóõúçê]',name+': '+literal)
 def test_no_farm_backend_or_protected_code_changed(self):
  for name in ['Inventory.lua','CombatFarm.lua','StandFarm.lua','AutoPrestige.lua','AutoPrestigeRuntime.lua','Farm.lua','ServerHop.lua','Config.lua','Main.lua','ai/server.py']:
   expected=subprocess.check_output(['git','show','0cb6b60:'+name],cwd=ROOT)
   actual=subprocess.check_output(['git','show','b8e5b61:'+name],cwd=ROOT)
   self.assertEqual(actual,expected,name)
if __name__=='__main__':unittest.main()
