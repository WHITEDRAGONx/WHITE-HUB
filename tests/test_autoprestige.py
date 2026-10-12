"""Real AP scope/driver with simulated Roblox. Not YBA or Delta validation."""
from pathlib import Path
import unittest,subprocess
import test_stand_dialogue as dialogue
import test_rib_restock as restock
from ai.autofix import check_luau
ROOT=Path(__file__).resolve().parents[1]
class PrestigeTests(unittest.TestCase):
 setUpBase=dialogue.StandDialogueTests.setUp
 run_lua=dialogue.StandDialogueTests.run_lua
 enable_fast=dialogue.StandDialogueTests.enable_fast
 def setUp(self):
  dialogue.StandDialogueTests.setUp(self)
  self.run_lua('''
  getgenv=function() return _G end; __WhiteHubRuntimeId='AP-runtime'; tick=os.clock
  player.PlayerGui=pg; player.PlayerStats=stats; player.Backpack=bag; char.Parent=player
  function char:GetChildren() return self.children end
  function bag:GetChildren() return self.children end
  function pg:GetChildren() return self.children end
  function nodeChildren(n) n.GetChildren=function(self) return self.children end; return n end
  money=node('Money','NumberValue',stats); money.Value=100
  level=node('Level','NumberValue',stats); level.Value=1
  prestige=node('Prestige','NumberValue',stats); prestige.Value=0
  spec=node('Spec','StringValue',stats); spec.Value='None'
  questProgress=node('QuestProgress','NumberValue',stats); questProgress.Value=0
  questMax=node('QuestMaxProgress','NumberValue',stats); questMax.Value=0
  world=nodeChildren(node('Workspace','Folder')); rep=nodeChildren(node('ReplicatedStorage','Folder'))
  workspace=world
  local original=game.GetService
  game.PlaceId=123; game.JobId='current'
  game.GetService=function(self,name) if name=='ReplicatedStorage' then return rep end; return original(self,name) end
  inventory={GetMax=function() return 25 end,Count=function(_,name)
    local count=0; for _,c in ipairs({bag,player.Character}) do
      for _,t in ipairs(c.children) do if t.Name==name and t:IsA('Tool') then count=count+1 end end
    end; return count end,GetMoney=function() return money.Value end}
  function config:SetMany(data) for k,v in pairs(data) do values[k]=v end end
  combat={IsBusy=function() return combatBusy==true end}
  items={IsBusy=function() return itemBusy==true end,Restock=function() restockCalls=(restockCalls or 0)+1; return false,'not mocked' end}
  hop={Hop=function(_,guard) if beforeHopReturn then beforeHopReturn() end; return guard() end}
  ''')
  self.lua.globals().driver=self.lua.execute((ROOT/'PrestigeDialogue.lua').read_text())
  self.lua.globals().support=self.lua.execute((ROOT/'AutoPrestigeRuntime.lua').read_text())
  self.run_lua('''
  all={Config=config,RuntimeLog=logger,Movement=movement,StandFarm=farm,Farm=items,CombatFarm=combat,
    PrestigeDialogue=driver,Inventory=inventory,ServerHop=hop}
  driver:Init(); support:Init(all)
  function runContext(fn) support:Register(function(ctx) context=ctx; fn(ctx) end); assert(support:Start()) end
  function addPrompt(npc)
    local model=node(npc,'Model',world); local p=node('Prompt','ProximityPrompt',model); p.ObjectText=npc; return p
  end
  function fireproximityprompt(p) promptCalls=(promptCalls or 0)+1; if onPrompt then onPrompt(p) end end
  function hum:EquipTool(tool)
    for i,t in ipairs(bag.children) do if t==tool then table.remove(bag.children,i); break end end
    tool.Parent=player.Character; table.insert(player.Character.children,tool)
  end
  ''')
 def test_arrow_one_activation_multipage_and_state_confirmation(self):
  self.run_lua('''
  onActivate=function() page('ClickContinue','Intro') end
  onClick=function() if presses==1 then nextPage('Option1','Yes') else stand.Value='Cream'; closeGui() end end
  runContext(function(ctx) ctx:Consume('Mysterious Arrow') end); advance(5)
  assert(activations==1 and stand.Value=='Cream' and not support:IsBusy())
  ''')
 def test_fast_option_and_continue_without_vim(self):
  self.enable_fast()
  self.run_lua('''
  onActivate=function() fastPage('Option1','Yes',true) end
  onSelect=function() fastPage('ClickContinue','Finish') end
  onSignal=function() stand.Value='Cream'; closeGui() end
  runContext(function(ctx) ctx:Consume('Mysterious Arrow') end); advance(5)
  assert(activations==1 and presses==0 and not support:IsBusy())
  ''')
 def test_roka_waits_new_character_and_returns_safe(self):
  self.run_lua('''
  stand.Value='Cream'; onActivate=function() page('Option1','Roka') end
  onClick=function() stand.Value='None'; closeGui(); respawn(1,1); after(1.1,function() char.Parent=player end) end
  runContext(function(ctx) ctx:Consume('Rokakaka') end); advance(5)
  assert(activations==1 and safeMoves>=1 and not support:IsBusy())
  ''')
 def test_stop_during_dialogue_never_consumes_another_item(self):
  self.run_lua('''
  onActivate=function() page('Option1','Arrow') end
  runContext(function(ctx) ctx:Consume('Mysterious Arrow'); ctx:Consume('Rokakaka') end)
  advance(0.5); support:Stop(); advance(30)
  assert(activations==1 and support:IsBusy() and support:GetStatus().pending=='Mysterious Arrow')
  assert(not support:Start()); stand.Value='Cream'; closeGui(); assert(not support:IsBusy())
  ''')
 def test_unknown_and_skin_never_reset_or_upgrade(self):
  for value in ['Shiny Cream','',False]:
   self.setUp(); self.lua.globals().skin=value
   self.run_lua("stand.Value='Cream'; runContext(function(ctx) ctx:Consume('Rokakaka') end); advance(1); assert(activations==0 and not support:IsBusy())")
 def test_pity_guard_before_roka_or_arrow(self):
  self.run_lua("pity.Value=20; stand.Value='Cream'; runContext(function(ctx) ctx:Consume('Rokakaka') end); advance(1); assert(activations==0)")
 def test_stale_skin_result_cannot_reset_after_stop(self):
  self.run_lua('''
  stand.Value='Cream'; remote.InvokeServer=function() task.wait(3); return 'None' end
  runContext(function(ctx) ctx:Consume('Rokakaka') end); advance(0.5); support:Stop()
  assert(support:IsBusy()); advance(4); assert(activations==0 and not support:IsBusy())
  ''')
 def test_second_skin_check_protects_replication_change(self):
  self.run_lua('''
  stand.Value='Cream'; local calls=0; remote.InvokeServer=function() calls=calls+1; return calls==1 and 'None' or 'Shiny' end
  runContext(function(ctx) ctx:Consume('Rokakaka') end); advance(1); assert(activations==0)
  ''')
 def test_requiem_confirmed_by_new_stand(self):
  self.run_lua('''
  stand.Value='King Crimson'; makeTool('Requiem Arrow'); onActivate=function() page('Option1','Requiem') end
  onClick=function() stand.Value='King Crimson Requiem'; closeGui() end
  runContext(function(ctx) ctx:Consume('Requiem Arrow') end); advance(5); assert(activations==1 and not support:IsBusy())
  ''')
 def test_result_with_open_gui_not_success(self):
  self.run_lua('''
  onActivate=function() page('Option1','Arrow') end
  onClick=function() stand.Value='Cream' end
  runContext(function(ctx) ctx:Consume('Mysterious Arrow') end); advance(25)
  assert(support:IsBusy() and activations==1 and presses==1); closeGui(); assert(not support:IsBusy())
  ''')
 def test_npc_prestige_requires_increment(self):
  self.run_lua('''
  addPrompt('Prestige'); onPrompt=function() page('Option1','Prestige') end
  onClick=function() prestige.Value=1; closeGui() end
  runContext(function(ctx) ctx:Dialogue('Prestige',{'Option1'},function() return prestige.Value>0 end) end)
  advance(5); assert(promptCalls==1 and not support:IsBusy())
  ''')
 def test_closed_dialogue_alone_never_proves_prestige(self):
  self.run_lua('''
  addPrompt('Prestige'); onPrompt=function() page('Option1','Prestige') end; onClick=closeGui
  runContext(function(ctx) ctx:Dialogue('Prestige',{'Option1'},function() return prestige.Value>0 end) end)
  advance(15); assert(support:IsBusy() and prestige.Value==0)
  ''')
 def test_foreign_replacement_dialogue_is_not_clicked(self):
  self.run_lua("onActivate=function() page('Option1','Arrow') end; runContext(function(ctx) ctx:Consume('Mysterious Arrow') end); after(0.2,function() page('Option1','Merchant'); beforeForeign=presses end); advance(3); assert(presses==beforeForeign and support:IsBusy())")
 def test_unknown_option_stops_instead_of_guessing(self):
  self.run_lua('''
  onActivate=function() page('Option2','Unknown') end
  runContext(function(ctx) ctx:Consume('Mysterious Arrow') end); advance(1); assert(presses==0 and support:IsBusy())
  ''')
 def test_other_dialogue_and_competing_busy_worker_block_start(self):
  self.run_lua('support:Register(function() end); itemBusy=true; assert(not support:Start()); itemBusy=false; combatBusy=true; assert(not support:Start()); combatBusy=false; page("Option1","Merchant"); assert(not support:Start())')
 def test_stop_cancels_long_wait_within_one_tenth(self):
  self.run_lua('runContext(function(ctx) ctx:Wait(60); effect=true end); advance(0.2); support:Stop(); advance(0.2); assert(not effect and not support:IsBusy())')
 def test_child_callback_does_not_outlive_stop(self):
  self.run_lua('runContext(function(ctx) ctx:Spawn(function() ctx:Wait(2); effect=true end); ctx:Wait(10) end); advance(0.2); support:Stop(); advance(3); assert(not effect and not support:IsBusy())')
 def test_inflight_remote_counts_until_return(self):
  self.run_lua("remote.InvokeServer=function() task.wait(5); return true end; runContext(function(ctx) ctx:Invoke(remote,'LearnSkill'); effect=true end); advance(1); support:Stop(); assert(support:IsBusy()); advance(5); assert(not effect and not support:IsBusy())")
 def test_stale_remote_after_respawn_rejected(self):
  self.run_lua("runContext(function(ctx) player.Character=node('New','Model'); ctx:Invoke(remote,'Attack') end); advance(1); assert(not support:IsBusy())")
 def install_transfer(self):
  self.run_lua("local old=game.GetService; local ts={TeleportInitFailed={Connect=function(_,fn) transferFailed=fn; return {Disconnect=function() transferFailed=nil end} end}}; game.GetService=function(self,name) if name=='TeleportService' then return ts end; return old(self,name) end")
 def test_transfer_submission_remains_pending_until_failure_or_arrival(self):
  self.install_transfer()
  self.run_lua("runContext(function(ctx) ctx:Hop() end); assert(support:IsBusy() and support:GetStatus().pending=='server transfer'); transferFailed(player); assert(not support:IsBusy())")
 def test_stop_during_hop_lookup_does_not_submit_or_restart(self):
  self.install_transfer()
  self.run_lua("beforeHopReturn=function() support:Stop() end; runContext(function(ctx) ctx:Hop(); late=true end); assert(not late and not support:IsBusy())")
 def test_own_event_connections_are_disconnected_on_stop(self):
  self.run_lua("local signal={Connect=function(_,fn) handler=fn; return {Disconnect=function() disconnected=true end} end}; runContext(function(ctx) ctx:Connect(signal,function() ctx:Wait(2); eventEffect=true end); ctx:Wait(10) end); handler(); support:Stop(); advance(3); assert(disconnected and not eventEffect and not support:IsBusy())")
 def test_until_has_timeout_without_infinite_retry(self):
  self.run_lua("runContext(function(ctx) ctx:Until(function() return false end,1,'missing'); effect=true end); advance(2); assert(not effect and not support:IsBusy() and support:GetStatus().reason:find('TIMEOUT'))")
 def test_restart_same_module_after_safe_stop(self):
  self.run_lua('runContext(function(ctx) ctx:Wait(3) end); support:Stop(); advance(0.2); runContext(function() effect=true end); assert(effect and not support:IsBusy())')
 def test_reload_keeps_old_remote_fenced(self):
  self.run_lua("remote.InvokeServer=function() task.wait(5); return true end; runContext(function(ctx) ctx:Invoke(remote,'LearnSkill') end); support:Destroy(); __WhiteHubRuntimeId='new-runtime'")
  self.lua.globals().new=self.lua.execute((ROOT/'AutoPrestigeRuntime.lua').read_text())
  self.run_lua('new:Init(all); new:Register(function() end); assert(new:IsBusy() and not new:Start()); advance(6); assert(not new:IsBusy())')
 def test_source_metadata_is_used_but_unknown_never_swept(self):
  self.run_lua('''
  local panel=nodeChildren(node('Quests','Frame',pg)); local q=node('Defeat Bucciarati','Frame',panel)
  function q:GetAttribute(k) if k=='NPCName' then return 'Bruno' end end
  runContext(function(ctx) assert(ctx:StorySource()=='Bruno') end); assert(not support:IsBusy())
  q.GetAttribute=function() end
  runContext(function(ctx) ctx:StorySource() end); assert(support:GetStatus().reason:find('SOURCE_UNKNOWN'))
  ''')
 def test_missing_npc_has_no_pending_action(self):
  self.run_lua("runContext(function(ctx) ctx:Dialogue('Missing',{'Option1'},function() return false end) end); advance(1); assert(not support:IsBusy() and not promptCalls)")
 def test_money_does_not_serve_as_kill_signal(self):
  src=(ROOT/'AutoPrestige.lua').read_text()
  self.assertNotIn('DropMoney.Money.ChildAdded',src); self.assertNotIn('NPC:Destroy()',src)
  self.assertIn('health<=0',src)
 def test_engine_removed_and_protected_modules_equal(self):
  for path in ['SmartFarmEngine.lua','SmartFarmAdapters.lua','SmartFarmUI.lua','tests/test_smart_engine.py']: self.assertFalse((ROOT/path).exists())
  self.assertNotIn('{ key = "SmartFarmEngine"',(ROOT/'DevMain.lua').read_text())
  self.assertNotIn('Modules.SmartFarmEngine:Start()', (ROOT/'DevMain.lua').read_text())
  for path in ['Inventory.lua','Main.lua']:
   self.assertEqual((ROOT/path).read_bytes(),subprocess.check_output(['git','show','333ad75:'+path],cwd=ROOT))
  base=subprocess.check_output(['git','show','333ad75:CombatFarm.lua'],cwd=ROOT).decode()
  core=base[base.index('local function killTarget('):base.index('local function runNPCFarm(')]
  self.assertIn(core,(ROOT/'CombatFarm.lua').read_text())
 def test_sources_parse_and_no_legacy_dialogue_requests(self):
  for name in ['AutoPrestige.lua','AutoPrestigeRuntime.lua','PrestigeDialogue.lua']:
   self.assertTrue(check_luau((ROOT/name).read_text()),name)
  self.assertNotIn('"EndDialogue"',(ROOT/'AutoPrestige.lua').read_text())

class DelegationTests(unittest.TestCase):
 setUp=PrestigeTests.setUp
 run_lua=PrestigeTests.run_lua
 def install_items(self):
  restock.RibRestockTests.install_item_farm(self)
  self.run_lua("all.Farm=items; all.Inventory=inventory; inventory.GetMax=function() return 25 end; inventory.GetMoney=function() return money.Value end; support:Init(all); values.StandFarmEnabled=false")
 def test_prestige_restock_uses_existing_detector_without_normal_farm(self):
  self.install_items()
  self.run_lua("addSpawn('Mysterious Arrow'); removeTool('Mysterious Arrow'); runContext(function(ctx) ctx:Collect('Mysterious Arrow',1) end); advance(3); assert(inventory:Count('Mysterious Arrow')==1 and prompts==1 and not values.FarmEnabled and not support:IsBusy())")
 def test_sale_calls_existing_merchant_exclusively_and_restores_flags(self):
  self.install_items()
  self.run_lua("values.AutoSell=true; sales=0; inventory.SellAll=function() assert(values.FarmEnabled and values.AutoPrestige and items:IsBusy()); sales=sales+1; money.Value=money.Value+20; return true end; runContext(function(ctx) ctx:Sell() end); advance(1); assert(sales==1 and not values.FarmEnabled and not items:IsBusy() and not support:IsBusy())")
 def test_stop_during_sale_keeps_operation_fenced_until_return(self):
  self.install_items()
  self.run_lua("values.AutoSell=true; inventory.SellAll=function() task.wait(3); money.Value=120; return true end; runContext(function(ctx) ctx:Sell(); lateEffect=true end); advance(0.3); support:Stop(); assert(support:IsBusy() and items:IsBusy()); advance(4); assert(not values.FarmEnabled and not lateEffect and not support:IsBusy())")
 def test_disabled_autosell_is_respected(self):
  self.install_items()
  self.run_lua("values.AutoSell=false; inventory.SellAll=function() sales=true end; runContext(function(ctx) ctx:Sell() end); assert(not sales and not support:IsBusy())")
 def test_no_money_change_does_not_claim_sale_success(self):
  self.install_items()
  self.run_lua("values.AutoSell=true; inventory.SellAll=function() return true end; runContext(function(ctx) ctx:Sell(); claimed=true end); advance(5); assert(not claimed and not support:IsBusy())")

class WorkerTests(unittest.TestCase):
 setUp=PrestigeTests.setUp
 run_lua=PrestigeTests.run_lua
 def register_worker(self):
  self.run_lua("""
  _G.WhiteHubModules=all; all.AutoPrestigeRuntime=support; all.Webhook={SendPrestigeComplete=function() notices=(notices or 0)+1 end}
  for _,child in ipairs(stats.children) do stats[child.Name]=child end
  game.Players={LocalPlayer=player}; game.IsLoaded=function() return true end
  Instance={new=function(class,parent) local o=node(class,class,parent); o.Destroy=function(self) self.Parent=nil end; return o end}
  Vector3={new=function() return {} end}
  local event=node('RemoteEvent','RemoteEvent',char); event.FireServer=function() end
  """)
  self.lua.globals().worker=self.lua.execute('return function()\n'+(ROOT/'AutoPrestige.lua').read_text()+'\nend')
  self.run_lua('task.spawn(worker)')
 def test_real_worker_confirms_prestige_increment_not_just_dialogue_close(self):
  self.register_worker()
  self.run_lua("level.Value=36; addPrompt('Prestige'); onPrompt=function() page('Option1','Prestige') end; onClick=function() prestige.Value=1; level.Value=1; closeGui() end; assert(support:Start()); advance(0.6); assert(prestige.Value==1 and promptCalls==1)")
 def test_real_worker_max_prestige_notifies_once_and_stops(self):
  self.register_worker()
  self.run_lua("prestige.Value=3; level.Value=50; assert(support:Start()); advance(1); assert(not support:IsBusy() and notices==1 and values.AutoPrestige==false)")
 def test_real_worker_missing_quest_origin_stops_with_diagnostic(self):
  self.register_worker()
  self.run_lua("local panel=nodeChildren(node('Quests','Frame',pg)); node('Unknown story','Frame',panel); assert(support:Start()); advance(2); assert(not support:IsBusy() and support:GetStatus().reason:find('SOURCE_UNKNOWN'))")

if __name__=='__main__': unittest.main()
