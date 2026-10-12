"""Actual catalog/selector Lua in offline mocks; no native Delta or server proof."""
import re
import subprocess
import unittest
from pathlib import Path
from lupa import LuaRuntime
from ai.autofix import check_luau
import test_silver_ui as silver
import test_stand_targets as targets

ROOT=Path(__file__).resolve().parents[1]
TREE=r'''
function tree(name,class,children)
 local n={Name=name,class=class or 'Folder',children=children or {}}
 function n:GetChildren() return self.children end
 function n:FindFirstChild(key) for _,c in ipairs(self.children) do if c.Name==key then return c end end end
 function n:IsA(kind) return self.class==kind end
 return n
end
rs=tree('ReplicatedStorage'); workspace=tree('Workspace')
game={GetService=function(_,name) if name=='ReplicatedStorage' then return rs end end}
table.find=function(t,x) for i,v in ipairs(t) do if v==x then return i end end end
'''

class CatalogTests(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime(unpack_returned_tuples=True); self.lua.execute(TREE)
  self.lua.globals().catalog=self.lua.execute((ROOT/'GameCatalog.lua').read_text())
  self.lua.globals().choice=self.lua.execute((ROOT/'ChoiceUI.lua').read_text())
  self.lua.execute('choice:Init({GameCatalog=catalog})')
 def run_lua(self,s):self.lua.execute(s)
 def test_facts_snapshot_is_unique_and_only_stand_skins(self):
  self.run_lua("local names=catalog:GetSkins(); assert(#names==461 and table.find(names,'Action-Figure Platinum')); assert(not table.find(names,'Road Sign')); for i=2,#names do assert(names[i-1]<names[i]) end")
 def test_saved_unknown_names_preserved_without_invented_aliases(self):
  self.run_lua("local names=catalog:GetSkins({'Exact live name','Aero OH','Aero OH'}); assert(#names==462 and table.find(names,'Aero OH') and table.find(names,'Exact live name')); assert(not table.find(names,'None'))")
 def test_invalid_values_control_characters_and_duplicates_filtered(self):
  self.run_lua("local names=catalog:Names({'None','',false,'Valid','Valid','bad\\nname',string.rep('x',101)}); assert(#names==1 and names[1]=='Valid')")
 def test_skin_container_scan_is_bounded(self):
  self.run_lua("local a,b={},{}; for i=1,600 do a[i]=tree('RuntimeA'..i,'Model'); b[i]=tree('RuntimeB'..i,'Model') end; rs.children={tree('StandSkins','Folder',a),tree('Skins','Folder',b)}; local names=catalog:GetSkins(); assert(#names==461+256 and table.find(names,'RuntimeA128') and not table.find(names,'RuntimeA129') and not table.find(names,'RuntimeB129'))")
 def test_nested_skin_names_are_read_without_requiring_module_scripts(self):
  self.run_lua("rs.children={tree('Objects','Folder',{tree('StandSkins','Folder',{tree('Family','Folder',{tree('Live Skin','Model')})})})}; local names=catalog:GetSkins(); assert(table.find(names,'Live Skin') and not table.find(names,'Family'))")
 def test_quest_catalog_keeps_supported_ids_and_marks_unknown_as_info(self):
  self.run_lua("local names=catalog:GetQuests({'Officer Sam [Lvl. 1+]'}); assert(names[1]=='Officer Sam [Lvl. 1+]' and #names==35); for i=2,#names do assert(catalog:IsInfo(names[i])) end")
 def test_live_dialogue_names_discovered_with_a_fixed_bound(self):
  self.run_lua("local d={}; for i=1,600 do d[i]=tree('New quest '..i..' [Lvl. 50+]') end; workspace.children={tree('Dialogues','Folder',d)}; rs.children={tree('NewDialogue','Folder',{tree('Storyline#19'),tree('Merchant')})}; local names=catalog:GetQuests({}); assert(table.find(names,'INFO | New quest 128 [Lvl. 50+]') and not table.find(names,'INFO | New quest 129 [Lvl. 50+]')); assert(table.find(names,'INFO | Storyline#19') and not table.find(names,'INFO | Merchant'))")
 def test_missing_game_containers_do_not_break_snapshot(self):
  self.run_lua("game.GetService=function() error('not loaded') end; workspace=nil; assert(#catalog:GetSkins()==461 and #catalog:GetQuests({})==34)")
 def test_toggle_copies_list_and_preserves_exact_selected_names(self):
  self.run_lua("local old={'Saved unknown','Cream'}; local value=choice:Toggle(old,'Aerosmith'); assert(#old==2 and #value==3 and table.find(value,'Saved unknown')); value=choice:Toggle(value,'Cream'); assert(#value==2 and not table.find(value,'Cream'))")
 def test_selection_limit_blocks_add_but_allows_removal(self):
  self.run_lua("local old={}; for i=1,25 do old[i]='Skin '..i end; local value=choice:Toggle(old,'New'); assert(not value and #old==25); value=choice:Toggle(old,'Skin 1'); assert(#value==24)")
 def test_search_is_case_insensitive_and_literal(self):
  self.run_lua("local names={'Cream','Aerosmith','A.B','AXB'}; assert(#choice:Filter(names,'A.B')==1); assert(choice:Filter(names,'AERO')[1]=='Aerosmith'); assert(#choice:Filter(names,'%')==0)")

NATIVE=r'''
Enum.Font={Gotham='Gotham'}; Enum.TextXAlignment={Left='Left'}
Vector2={new=function(x,y) return {X=x,Y=y} end}
table.find=function(t,x) for i,v in ipairs(t) do if v==x then return i end end end
local original=Instance.new
local function signal()
 return {Connect=function(self,fn) self.fn=fn; local c={}; function c:Disconnect() self.disconnected=true end; self.connection=c; return c end}
end
Instance.new=function(class,parent)
 local n=original(class,parent); n.MouseButton1Click=signal(); n.AncestryChanged=signal()
 n.AbsolutePosition={X=620,Y=350}; n.AbsoluteSize={X=100,Y=26}
 function n:GetPropertyChangedSignal(k) self.signals[k]=self.signals[k] or signal(); return self.signals[k] end
 function n:Destroy() self.destroyed=true; self.Parent=nil end
 return n
end
pg=Instance.new('Frame'); game={GetService=function() return {LocalPlayer={WaitForChild=function() return pg end}} end}
function openPanel(button)
 button.MouseButton1Click.fn(); screen=pg:GetChildren()[#pg:GetChildren()]
 panel=screen:GetChildren()[2]; search=panel:GetChildren()[2]; list=panel:GetChildren()[3]
end
function option(name)
 for _,c in ipairs(list:GetChildren()) do if c.class=='TextButton' and c.Text:sub(5)==name then return c end end
end
beforeCount=0; selected={'Cream'}; ui={ShowPopup=function(_,s) popup=s end}
theme.PANEL2='panel2'; theme.PANEL3='panel3'; theme.WHITE='white'
'''
class NativeChoiceTests(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime(unpack_returned_tuples=True);self.lua.execute(silver.MOCK+NATIVE)
  self.lua.globals().catalog=self.lua.execute((ROOT/'GameCatalog.lua').read_text())
  self.lua.globals().choice=self.lua.execute((ROOT/'ChoiceUI.lua').read_text())
  self.lua.execute("choice:Init({GameCatalog=catalog}); parent=Instance.new('Frame'); button,refresh=choice:Build(parent,'Stands',function() return {'Cream','Aerosmith'} end,function() return selected end,function(names) selected=names end,function() beforeCount=beforeCount+1 end,ui,theme,track)")
 def run_lua(self,s):self.lua.execute(s)
 def test_actual_multi_select_marks_selection_and_calls_stop_before_edit(self):
  self.run_lua("assert(button.Text=='Cream'); openPanel(button); option('Aerosmith').MouseButton1Click.fn(); assert(beforeCount==1 and #selected==2 and button.Text=='2 selected' and option('Aerosmith').Text=='[x] Aerosmith'); option('Cream').MouseButton1Click.fn(); assert(#selected==1 and button.Text=='Aerosmith')")
 def test_native_search_filters_visible_rows_and_canvas(self):
  self.run_lua("openPanel(button); search.Text='aero'; search:GetPropertyChangedSignal('Text').fn(); assert(option('Aerosmith').Visible and not option('Cream').Visible and list.CanvasSize.Y.Offset==28)")
 def test_overlay_geometry_is_clamped_to_viewport(self):
  self.run_lua("openPanel(button); assert(panel.Position.X.Offset+panel.Size.X.Offset<=1108 and panel.Position.Y.Offset+panel.Size.Y.Offset<=512)")
 def test_close_destroy_and_rotation_disconnect_and_remove_overlay(self):
  self.run_lua("openPanel(button); local s=screen; local c=search:GetPropertyChangedSignal('Text').connection; workspace.CurrentCamera.changed.fn(); assert(s.destroyed and c.disconnected); openPanel(button); s=screen; choice:Destroy(); assert(s.destroyed)")
 def test_outside_touch_closes_menu(self):
  self.run_lua("openPanel(button); local s=screen; s:GetChildren()[1].MouseButton1Click.fn(); assert(s.destroyed)")
 def test_single_unsupported_option_cannot_change_saved_quest(self):
  self.run_lua("selected={'Officer Sam [Lvl. 1+]'}; local b=choice:Build(parent,'Quest',function() return {'INFO | Unknown'} end,function() return selected end,function(names) if catalog:IsInfo(names[1]) then popup='Not mapped'; return false end; selected=names end,nil,ui,theme,track,true); openPanel(b); option('INFO | Unknown').MouseButton1Click.fn(); assert(selected[1]=='Officer Sam [Lvl. 1+]' and popup=='Not mapped' and not screen.destroyed)")

class CatalogWiringTests(unittest.TestCase):
 def test_no_legacy_buttons_or_skin_name_entry_remain(self):
  ui=(ROOT/'UI.lua').read_text();helper=(ROOT/'StandV2UI.lua').read_text()
  for old in ('targetListButton','clearTargetsButton','resetStats','Desired skins separated by semicolons'):
   self.assertNotIn(old,ui+helper)
  self.assertIn('choices:Build(FarmPage,"Skins"',helper)
 def test_runtime_has_no_external_code_loads_or_heavy_heap_scan(self):
  src=(ROOT/'GameCatalog.lua').read_text()+(ROOT/'ChoiceUI.lua').read_text()
  self.assertNotRegex(src,r'HttpGet|loadstring|require\(|getgc|InvokeServer|FireServer|webhook')
 def test_loader_and_public_builder_include_new_dependencies(self):
  loader=(ROOT/'DevMain.lua').read_text();builder=(ROOT/'scripts/build_public_release.py').read_text()
  for n in ('GameCatalog','ChoiceUI'):
   self.assertIn('file = "'+n+'.lua"',loader);self.assertIn("'"+n+".lua'",builder)
   self.assertTrue(check_luau((ROOT/(n+'.lua')).read_text()))
 def test_combat_inventory_consumption_and_backend_unchanged(self):
  for n in ('Inventory.lua','CombatFarm.lua','StandFarm.lua','Farm.lua','AutoPrestige.lua','AutoPrestigeRuntime.lua','PrestigeDialogue.lua','WhiteAI.lua','ai/server.py'):
   actual=subprocess.check_output(['git','show','91f87b3:'+n],cwd=ROOT) if n=='CombatFarm.lua' else (ROOT/n).read_bytes()
   self.assertEqual(actual,subprocess.check_output(['git','show','81aa505:'+n],cwd=ROOT),n)
 def test_quest_selection_ui_rejects_info_without_config_write(self):
  # Execute the new UI callback wiring with real catalog and minimal native wrapper.
  lua=LuaRuntime(unpack_returned_tuples=True);lua.execute(TREE)
  lua.globals()._catalog=lua.execute((ROOT/'GameCatalog.lua').read_text())
  lua.execute("_config={Get=function() return 'Officer Sam [Lvl. 1+]' end,Set=function(_,k,v) written=v end}; UI={ShowPopup=function(_,s) popup=s end}; _choices={Build=function(_,p,l,opts,get,set) choose=set; return {} end}; questList={'Officer Sam [Lvl. 1+]'}")
  src=(ROOT/'UI.lua').read_text();a=src.index('    local questDropdown = _choices:Build');b=src.index('    -- Quest/NPC are mutually exclusive',a)
  lua.execute(src[a:b]);lua.execute("assert(choose({'INFO | New Quest'})==false and written==nil); assert(choose({'Unknown raw quest'})==false and written==nil); choose({'Officer Sam [Lvl. 1+]'}); assert(written=='Officer Sam [Lvl. 1+]')")
