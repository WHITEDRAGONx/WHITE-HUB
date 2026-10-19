"""Packaging, owner lifecycle and loader tests; not Roblox/Delta validation."""
import ast, os, re, subprocess, unittest
from pathlib import Path
from lupa import LuaRuntime
from ai.autofix import check_luau
from module_sources import module_source
import test_stand_dialogue as dialogue
from test_catalog_refresh import NETWORK
ROOT=Path(os.environ.get('WHITE_HUB_CANDIDATE',Path(__file__).resolve().parents[1]))
BASE=os.environ.get('WHITE_HUB_BASE','d259980660cb5e8acf7c2e4379fd8f4c5b2686d1')
class ConsolidationTests(unittest.TestCase):
 def test_all_root_modules_parse(self):
  for p in ROOT.glob('*.lua'):
   with self.subTest(file=p.name): self.assertTrue(check_luau(p.read_text()))
 def test_gameplay_and_private_backend_are_unchanged(self):
  for name in ['Inventory.lua','CombatFarm.lua','Farm.lua','StandFarm.lua','StandTransfer.lua','AutoPrestige.lua','Config.lua','CommunityFeatures.lua','HalloweenExchange.lua','Settings.lua','WhiteAI.lua']:
   if not (ROOT/name).exists(): continue
   self.assertEqual((ROOT/name).read_bytes(),subprocess.check_output(['git','show',BASE+':'+name],cwd=ROOT),name)
 def test_component_bodies_preserved(self):
  for name in ['UICompact.lua','ChoiceUI.lua','StandV2UI.lua','CatalogRefresh.lua','PrestigeDialogue.lua']:
   old=subprocess.check_output(['git','show',BASE+':'+name],cwd=ROOT).decode()
   if name=='StandV2UI.lua': old=old.replace('-- DEV ONLY: scoped Stand V2 controls; existing GOLD UI helpers own connections.','-- Scoped Stand controls; the parent UI owns connections.')
   self.assertEqual(module_source(ROOT,name),old,name)
 def test_removed_files_have_no_runtime_references(self):
  for name in ['UICompact','ChoiceUI','StandV2UI','CatalogRefresh','PrestigeDialogue','NPCFarm','QuestFarm']:
   self.assertFalse((ROOT/(name+'.lua')).exists())
   for p in ROOT.glob('*.lua'):
    self.assertNotRegex(p.read_text(),r'(?:file\s*=\s*[\'"]'+name+r'\.lua|(?:modules|Modules)\.'+name+r'\b)',str(p))
 def test_ui_component_owner_initializes_and_closes_selector(self):
  lua=LuaRuntime(unpack_returned_tuples=True)
  bundle=lua.execute((ROOT/'UIComponents.lua').read_text());lua.globals().bundle=bundle
  lua.execute('''local count=0; bundle.Compact.Init=function() count=count+1 end;
  bundle.Choice.Init=function(_,m) assert(m.marker);count=count+1 end;
  bundle.Stand.Init=function() count=count+1 end;bundle:Init({marker=true});assert(count==3);
  local closed=0;bundle.Choice.Destroy=function() closed=closed+1 end;bundle:Destroy();assert(closed==1)''')
 def test_catalog_owns_network_refresh_and_cancels_timer(self):
  lua=LuaRuntime(unpack_returned_tuples=True);lua.execute(dialogue.MOCK+NETWORK)
  lua.globals().catalog=lua.execute((ROOT/'GameCatalog.lua').read_text())
  lua.execute('''catalog:Init(all); assert(calls==2 and writes==1);
  assert(catalog.Online:GetNames()[1]=='Brand New Skin');
  catalog:Destroy();advance(22000);assert(calls==2 and catalog.Online:GetState()=='stopped')''')
 def test_transfer_cleanup_uses_new_owners(self):
  s=(ROOT/'ServerHop.lua').read_text()
  for key in ['"GameCatalog"','"UIComponents"','"AutoPrestigeRuntime"']: self.assertIn(key,s)
  for name in ['Main.lua','DevMain.lua']:
   p=ROOT/name
   if p.exists():
    s=p.read_text();self.assertIn('"GameCatalog", "UIComponents", "UI"',s)
 def test_public_source_and_loader_isolation(self):
  s=(ROOT/'Main.lua').read_text();self.assertIn('WHITE-HUB/main/',s)
  for p in ROOT.glob('*.lua'):
   if p.name=='DevMain.lua' or p.name=='WhiteAI.lua': continue
   if (ROOT/'DevMain.lua').exists() and p.name in ['UI.lua','Config.lua','ServerHop.lua']: continue
   self.assertNotRegex(p.read_text(),r'WhiteAI|WHITE AI|AI DEBUG|PAIR THIS DEVICE|DevMain|onrender')
 def test_actual_loaders_boot_with_consolidated_contracts(self):
  original=Path(__file__).with_name('test_public_release.py').read_text()
  cls=next(n for n in ast.parse(original).body if isinstance(n,ast.ClassDef))
  method=next(n for n in cls.body if isinstance(n,ast.FunctionDef) and n.name=='test_public_loader_boots_and_initializes_prestige_dependencies')
  src=ast.get_source_segment(original,method)
  src=src.replace('initialized.AutoPrestigeRuntime and initialized.PrestigeDialogue and initialized.UICompact','initialized.AutoPrestigeRuntime and initialized.UIComponents and initialized.GameCatalog')
  src=src.replace('module.RecoverTransfer=function() recovered=true end','''module.RecoverTransfer=function() recovered=true end
            module.ResumeSavedSession=function() resumed=true end
            module.ScanEvent=function() end; module.StartPilot=function() end; module.StopPilot=function() end
            module.TurnInCandy=function() end; module.BuySelectedReward=function() end
            module.GetCandyTotal=function() return 0 end; module.GetPoints=function() end
            module.SendManualReport=function() end; module.PairDevice=function() end''')
  ns={'LuaRuntime':LuaRuntime};exec(src,ns)
  self.files={p.name:p.read_text() for p in ROOT.glob('*.lua') if p.name not in ['DevMain.lua','WhiteAI.lua']}
  ns[method.name](self)
  if (ROOT/'DevMain.lua').exists():
   devsrc=src.replace("self.files['Main.lua']","(ROOT/'DevMain.lua').read_text()").replace('assert(oldDestroyed and uiCreated','assert(uiCreated')
   devsrc=devsrc.replace('assert(all.WhiteAI==nil)','assert(all.WhiteAI~=nil)').replace('assert(_G.WhiteHubModules.WhiteAI==nil)','assert(_G.WhiteHubModules.WhiteAI~=nil)')
   devsrc=devsrc.replace("url:find('/main/',1,true) and not url:find('WhiteAI',1,true)","url:find('/dev/2026-10-10-autosell-compat/',1,true)")
   self.files['WhiteAI.lua']=(ROOT/'WhiteAI.lua').read_text()
   ns={'LuaRuntime':LuaRuntime,'ROOT':ROOT};exec(devsrc,ns);ns[method.name](self)
if __name__=='__main__': unittest.main()
