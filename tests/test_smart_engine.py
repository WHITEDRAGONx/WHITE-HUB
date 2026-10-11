"""Execute actual Lua coordinator/adapters with mock lifecycle acknowledgements."""
from pathlib import Path
import unittest
from lupa import LuaRuntime
from ai.autofix import check_luau
ROOT=Path(__file__).resolve().parents[1]
MOCK=r'''
now=0; os.clock=function() return now end
getgenv=function() return _G end
game={JobId='same-server',PlaceId=123}
values={SmartFarmProfiles={},StandFarmMode='stand',StandFarmConsumable='Mysterious Arrow',
 StandFarmPityLimit=20,StandFarmMaxHops=3,StandFarmTargets={},StandFarmSkinTargets={},
 AutoSell=true,BuyLucky=true,AutoChooseQuest=false,SelectedQuest='William',SelectedNPC='Vampire',StandFarmTarget='Aerosmith'}
config={Get=function(_,k) return values[k] end,Set=function(_,k,v) values[k]=v end,
 SetMany=function(_,t) for k,v in pairs(t) do values[k]=v end end}
logs={}; logger={Write=function(_,level,mod,msg) table.insert(logs,{Module=mod,Message=msg}) end,
 Subscribe=function(_,fn) listener=fn; return {Disconnect=function() listener=nil end} end}
spawned={}; task={spawn=function(fn) table.insert(spawned,fn); return fn() end,wait=function() end}
started={}; stopCalls=0; quiet=true; external=nil; modeRunning=false
fake={PrepareBoot=function() return nil end,GetBlockReason=function() return quiet and nil or 'pending' end,
 IsQuiet=function() return quiet,'pending' end,ExternalMode=function() return external end,
 Start=function(_,mode,settings) table.insert(started,{mode=mode,settings=settings}); modeRunning=true; return true end,
 Stop=function() modeRunning=false; external=nil; stopCalls=stopCalls+1 end,
 StopStand=function() stopCalls=stopCalls+1 end,
 Running=function() return modeRunning,'module_completed' end}
'''
class EngineTests(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime(unpack_returned_tuples=True)
  self.lua.execute(MOCK)
  source=(ROOT/'SmartFarmEngine.lua').read_text(); self.assertTrue(check_luau(source))
  self.lua.globals().engine=self.lua.execute(source)
  self.run_lua('engine:Init({Config=config,RuntimeLog=logger,SmartFarmAdapters=fake})')
 def run_lua(self,code): self.lua.execute(code)
 def test_priority_fifo_and_copy(self):
  self.run_lua("assert(engine:Enqueue({mode='item',priority=1})); assert(engine:Enqueue({mode='npc',priority=8})); assert(engine:Enqueue({mode='quest',priority=8})); engine:Step(0); assert(started[1].mode=='npc'); local s=engine:GetStatus(); s.queue[1].mode='stand'; assert(engine:GetStatus().queue[1].mode=='item')")
 def test_natural_completion_releases_before_next_owner(self):
  self.run_lua("engine:Enqueue({mode='stand'}); engine:Enqueue({mode='item'}); engine:Step(0); modeRunning=false; quiet=false; engine:Step(1); engine:Step(40); assert(#started==1 and engine:GetStatus().state=='releasing'); quiet=true; engine:Step(41); assert(#started==2 and engine:GetStatus().metrics.completed==1)")
 def test_manual_switch_cannot_ignore_pending_even_after_timeout(self):
  self.run_lua("engine:RequestMode('stand',true); engine:Step(0); quiet=false; engine:RequestMode('item',true); engine:Step(50); assert(#started==1 and #engine:GetStatus().queue==1); quiet=true; engine:Step(51); assert(started[2].mode=='item')")
 def test_stop_all_removes_work_and_retry(self):
  self.run_lua("engine:Enqueue({mode='item',timeout=10,retries=2}); engine:Step(0); now=11; engine:Step(now); engine:StopAll(); engine:Step(12); engine:Step(100); assert(#started==1 and #engine:GetStatus().queue==0)")
 def test_bounded_recovery_backoff_and_goal(self):
  self.run_lua("engine:Enqueue({mode='npc',timeout=10,retries=1,goal=2}); engine:Step(0); now=11; engine:Step(now); engine:Step(12); assert(#started==1); engine:Step(16); assert(#started==1); now=17; engine:Step(now); assert(#started==2); local id=engine:GetStatus().owner.id; assert(engine:Progress(id,2)); engine:Step(18); engine:Step(19); assert(engine:GetStatus().metrics.completed==1 and engine:GetStatus().metrics.retries==1)")
 def test_retry_budget_exhausted(self):
  self.run_lua("engine:Enqueue({mode='item',timeout=10,retries=1}); engine:Step(0); engine:Step(11); engine:Step(12); engine:Step(17); engine:Step(28); engine:Step(29); engine:Step(100); assert(#started==2 and #engine:GetStatus().queue==0)")
 def test_stall_resets_only_for_confirmed_progress(self):
  self.run_lua("engine:Enqueue({mode='item',stall=30}); engine:Step(0); now=29; listener({Module='Farm',Message='Item detected: Arrow'}); engine:Step(now); assert(engine:GetStatus().state=='running'); now=30; listener({Module='Farm',Message='Collected: Arrow'}); engine:Step(now); engine:Step(59); assert(engine:GetStatus().state=='running'); engine:Step(61); assert(engine:GetStatus().state=='releasing')")
 def test_logging_filters_wrong_owner_and_counts_kills(self):
  self.run_lua("engine:Enqueue({mode='npc'}); engine:Step(0); listener({Module='Farm',Message='Collected: Arrow'}); listener({Module='CombatFarm',Message='Kill credited'}); listener({Module='CombatFarm',Message='Confirmed death'}); assert(engine:GetStatus().metrics.progress==1 and engine:GetStatus().metrics.by_mode.npc==1)")
 def test_profile_validated_persisted_and_not_auto_run(self):
  self.run_lua("assert(engine:SaveProfile('AFK',{{mode='item',goal=2},{mode='stand'}})); assert(values.SmartFarmProfiles.AFK[1].goal==2); assert(#engine:GetStatus().queue==0); assert(engine:RunProfile('AFK')); engine:Step(0); assert(started[1].mode=='item')")
 def test_save_running_task_and_queue_without_replaying_automatically(self):
  self.run_lua("engine:Enqueue({mode='npc',goal=3}); engine:Enqueue({mode='stand'}); engine:Step(0); assert(engine:SaveQueueProfile('AFK')); local p=engine:GetStatus().profiles.AFK; assert(#p==2 and p[1].mode=='npc' and p[1].goal==3); assert(#started==1)")
 def test_forbidden_settings_never_saved(self):
  self.run_lua("assert(not engine:SaveProfile('bad',{{mode='stand',settings={WebhookURL='secret'}}})); assert(not engine:Enqueue({mode='npc',settings={WhiteAIAdminKey='secret'}})); assert(not values.SmartFarmProfiles.bad)")
 def test_profile_all_or_nothing_and_capacity(self):
  self.run_lua("assert(not engine:SaveProfile('bad',{{mode='item'},{mode='invalid'}})); assert(engine:SaveProfile('good',{{mode='item'},{mode='npc'}})); for i=1,19 do assert(engine:Enqueue({mode='item'})) end; assert(not engine:RunProfile('good')); assert(#engine:GetStatus().queue==19); assert(engine:Enqueue({mode='item'})); assert(not engine:Enqueue({mode='item'}))")
 def test_invalid_limits_lists_and_modes(self):
  self.run_lua("for _,t in ipairs({{mode='foo'},{mode='stand',timeout=0},{mode='stand',stall=1},{mode='stand',retries=3},{mode='stand',settings={StandFarmTargets={[2]='Cream'}}},{mode='stand',settings={StandFarmConsumable='Lucky Arrow'}}}) do assert(not engine:Enqueue(t)) end")
 def test_snapshot_settings_and_profile_copy(self):
  self.run_lua("local t=engine:BuildTask('stand',{goal=2}); assert(t and t.settings.StandFarmTarget=='Aerosmith'); engine:Enqueue(t); assert(engine:SaveQueueProfile('AFK')); values.StandFarmTarget='Cream'; local p=engine:GetStatus().profiles; p.AFK[1].settings.StandFarmTarget='Changed'; assert(engine:GetStatus().profiles.AFK[1].settings.StandFarmTarget=='Aerosmith')")
 def test_original_competing_boot_preference_cannot_authorize_stand_resume(self):
  self.run_lua("fake.PrepareBoot=function() return 'item' end; engine:Init({Config=config,RuntimeLog=logger,SmartFarmAdapters=fake}); assert(not engine:CanRecoverTransfer())")
 def test_async_start_timeout_retains_fence_and_never_resurrects(self):
  self.run_lua("task.spawn=function(fn) startThread=coroutine.create(fn); assert(coroutine.resume(startThread)) end; fake.Start=function() coroutine.yield(); modeRunning=true; return true end; engine:Enqueue({mode='hop',timeout=10,retries=1}); engine:Step(0); engine:Step(11); engine:Step(100); assert(engine:GetStatus().state=='releasing'); assert(coroutine.resume(startThread)); assert(not modeRunning and engine:GetStatus().owner==nil)")
 def test_external_stand_arrival_adopted_once(self):
  self.run_lua("external='stand'; modeRunning=true; engine:Enqueue({mode='item'}); engine:Step(0); engine:Step(1); assert(#started==0 and engine:GetStatus().owner.mode=='stand'); external=nil; modeRunning=false; engine:Step(2); engine:Step(3); assert(#started==1 and started[1].mode=='item')")
 def test_disabling_unrelated_toggle_does_not_cancel_delayed_start(self):
  self.run_lua("fake.Start=function() engine:RequestMode('npc',false); modeRunning=true; return true end; engine:Enqueue({mode='stand'}); engine:Step(0); assert(modeRunning and engine:GetStatus().owner.mode=='stand')")
 def test_stop_during_yielding_start_never_resurrects(self):
  self.run_lua("fake.Start=function() table.insert(started,{}); engine:StopAll(); modeRunning=true; return true end; engine:Enqueue({mode='stand'}); engine:Step(0); assert(engine:GetStatus().owner==nil and not modeRunning and #engine:GetStatus().queue==0)")
 def test_step_reentrance_guard(self):
  self.run_lua("fake.Start=function() table.insert(started,{}); engine:Step(0); modeRunning=true; return true end; engine:Enqueue({mode='npc'}); engine:Step(0); assert(#started==1)")
 def test_cancel_retry_while_releasing(self):
  self.run_lua("local ok,id=engine:Enqueue({mode='stand',timeout=10,retries=2}); engine:Step(0); engine:Step(11); assert(engine:Cancel(id)); engine:Step(12); engine:Step(100); assert(#started==1)")
 def test_adapter_error_halts_queue(self):
  self.run_lua("fake.Start=function() error('mock failure') end; engine:Enqueue({mode='item'}); engine:Enqueue({mode='npc'}); engine:Step(0); assert(#engine:GetStatus().queue==0 and engine:GetStatus().metrics.last_reason=='engine_error')")
 def test_destroy_disconnects_and_no_restart(self):
  self.run_lua("engine:Destroy(); assert(listener==nil and not engine:Enqueue({mode='item'})); engine:Step(0); assert(#started==0)")

ADAPTER_MOCK=r'''
character={Parent=true,FindFirstChildOfClass=function() return {Health=100} end,FindFirstChild=function() return {} end}
player={Character=character}; player.FindFirstChild=function(_,name) return gui end
players={LocalPlayer=player}; gui={FindFirstChild=function() return dialog end}
teleport={TeleportInitFailed={Connect=function(_,fn) failureEvent=fn; return {Disconnect=function() failureEvent=nil end} end}}
game={JobId='same-server',PlaceId=123,GetService=function(_,name) if name=='Players' then return players else return teleport end end}
itemBusy=false;combatBusy=false;standBusy=false;standRunning=false;combatRunning=false;hopBusy=false
item={IsBusy=function() return itemBusy end,IsRunning=function() return true end}
combat={IsBusy=function() return combatBusy end,IsRunning=function() return combatRunning,'Quest' end,
 Stop=function() combatRunning=false; values.FarmEnabled=true end,
 StartQuest=function() combatRunning=true end,StartNPC=function() combatRunning=true end}
stand={IsBusy=function() return standBusy or standRunning end,IsRunning=function() return standRunning end,
 Stop=function() standRunning=false end,Start=function() standRunning=true; return true end,
 GetStatus=function() return {running=standRunning,stop_reason='Desired Stand found: Cream'} end}
hop={IsBusy=function() return hopBusy end,Hop=function(_,guard) assert(guard()); return true end}
all={Config=config,Farm=item,CombatFarm=combat,StandFarm=stand,ServerHop=hop}
'''
class AdapterTests(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime(unpack_returned_tuples=True); self.lua.execute(MOCK+ADAPTER_MOCK)
  src=(ROOT/'SmartFarmAdapters.lua').read_text(); self.assertTrue(check_luau(src))
  self.lua.globals().adapter=self.lua.execute(src); self.run_lua('adapter:Init(all); adapter:IsQuiet(); now=2')
 def run_lua(self,code): self.lua.execute(code)
 def test_idle_item_worker_not_an_owner(self): self.run_lua("assert(adapter:IsQuiet()); values.FarmEnabled=true; assert(adapter:ExternalMode()=='item')")
 def test_respawn_readiness_requires_live_root_and_stability(self):
  self.run_lua("player.Character=nil; assert(not adapter:IsQuiet()); player.Character=character; assert(not adapter:IsQuiet()); now=4; assert(adapter:IsQuiet()); character.FindFirstChildOfClass=function() return {Health=0} end; assert(not adapter:IsQuiet())")
 def test_preference_edits_do_not_enable_sales_during_stand_ownership(self):
  self.run_lua("adapter:Start('stand',{}); assert(adapter:SetItemPreference('AutoSell',true)); assert(values.AutoSell==false); adapter:SetItemPreference('AutoSell',false); adapter:Stop(); adapter:Release(); assert(values.AutoSell==false)")
 def test_all_pending_operations_fence(self):
  for flag in ['itemBusy','combatBusy','standBusy','hopBusy']:
   self.run_lua(f'{flag}=true; assert(not adapter:IsQuiet()); {flag}=false')
  self.run_lua('dialog={Enabled=true}; assert(not adapter:IsQuiet()); dialog.Enabled=false; assert(not adapter:IsQuiet()); dialog=nil; assert(adapter:IsQuiet())')
 def test_stop_suppresses_combat_legacy_restore(self): self.run_lua('values.FarmEnabled=true; adapter:Stop(); assert(not values.FarmEnabled and not AutoPrestigeEnabled)')
 def test_stand_disables_sales_and_restores_item_preference(self): self.run_lua("assert(adapter:Start('stand',{})); assert(not values.AutoSell); adapter:Stop(); assert(adapter:Start('item',{})); assert(values.AutoSell and values.FarmEnabled)")
 def test_prestige_cannot_be_blindly_released(self): self.run_lua("assert(adapter:Start('prestige',{})); adapter:Stop(); local quiet,r=adapter:IsQuiet(); assert(not quiet and r=='prestige_release_unverified'); assert(not adapter:Start('stand',{}))")
 def test_previous_runtime_must_acknowledge_release_before_new_owner(self):
  self.run_lua("__WhiteHubEngineReleaseFence={job=game.JobId,place=game.PlaceId,released=function() return oldReleased==true end}; adapter:Init(all); local quiet,r=adapter:IsQuiet(); assert(not quiet and r=='previous_runtime_pending'); oldReleased=true; adapter:IsQuiet(); now=4; assert(adapter:IsQuiet())")
 def test_previous_runtime_ack_error_is_not_a_release(self):
  self.run_lua("__WhiteHubEngineReleaseFence={job=game.JobId,place=game.PlaceId,released=function() error('mock') end}; adapter:Init(all); assert(not adapter:IsQuiet())")
 def test_prestige_fence_survives_reload_on_same_server(self):
  self.run_lua("adapter:Start('prestige',{}); adapter:Stop(); adapter:Init(all); local quiet,r=adapter:IsQuiet(); assert(not quiet and r=='prestige_release_unverified'); game.JobId='new-server'; adapter:Init(all); adapter:IsQuiet(); now=4; assert(adapter:IsQuiet())")
 def test_boot_single_persisted_owner_and_off_before_initialization(self): self.run_lua("values.FarmEnabled=true; values.QuestFarmEnabled=true; assert(adapter:PrepareBoot()=='quest'); assert(not values.FarmEnabled and not values.QuestFarmEnabled)")
 def test_hop_submission_not_arrival_and_stop_not_release(self): self.run_lua("assert(adapter:Start('hop',{})); adapter:Stop(); assert(not adapter:IsQuiet()); failureEvent(player); assert(adapter:IsQuiet())")
 def test_hop_callback_checks_stop_after_http(self): self.run_lua("hop.Hop=function(_,guard) adapter:Stop(); assert(not guard()); return false end; assert(not adapter:Start('hop',{})); assert(adapter:IsQuiet())")
 def test_adopt_does_not_consume_or_reset_stand(self): self.run_lua("standRunning=true; assert(adapter:ExternalMode()=='stand'); assert(standRunning)")


class WiringTests(unittest.TestCase):
 def test_each_existing_toggle_routes_its_own_mode(self):
  import re
  src=(ROOT/'UI.lua').read_text()
  for label,mode,arg in [('Enable Farm','item','v'),('Auto Prestige','prestige','v'),('Quest Farm','quest','v'),('NPC Farm','npc','v'),('Stand Farm (BETA)','stand','enabled')]:
   pattern=r'MakeToggle\([^,\n]+,\s*"'+re.escape(label)+r'",[\s\S]*?function\('+arg+r'\)\s*if _engine then _engine:RequestMode\("'+mode+'", '+arg+r'\)'
   self.assertRegex(src,pattern)
  self.assertNotIn('RequestMode',src[src.index('for _, name in ipairs(itemList)'):src.index('-- QUEST FARM')]) if 'for _, name in ipairs(itemList)' in src and '-- QUEST FARM' in src else None
 def test_protected_code_and_boot_order(self):
  import subprocess
  for name in ['Inventory.lua','Main.lua','AutoPrestige.lua']:
   baseline=subprocess.check_output(['git','show','333ad750b5dd44ffd569ab0bae6b69d0f17fa445:'+name],cwd=ROOT)
   self.assertEqual((ROOT/name).read_bytes(),baseline)
  combat=(ROOT/'CombatFarm.lua').read_text()
  base=subprocess.check_output(['git','show','333ad750b5dd44ffd569ab0bae6b69d0f17fa445:CombatFarm.lua'],cwd=ROOT).decode()
  core=base[base.index('local function killTarget('):base.index('local function runNPCFarm(')]
  self.assertIn(core,combat)
  loader=(ROOT/'DevMain.lua').read_text()
  self.assertLess(loader.index('Modules.StandFarm:RecoverTransfer()'),loader.index('Modules.SmartFarmEngine:Start()'))
 def test_profile_settings_cannot_store_secrets(self):
  src=(ROOT/'SmartFarmEngine.lua').read_text()
  self.assertIn("else return nil,'forbidden_setting'",src)
  self.assertNotIn('WhiteAIEndpoint=true',src)

class IntegrationTests(unittest.TestCase):
 def setUp(self):
  import test_stand_dialogue as dialogue
  import test_restock_hop as hopping
  dialogue.StandDialogueTests.setUp(self)
  hopping.RestockHopTests.install_hop(self)
  self.lua.execute('''
  char.Parent=player
  function config:SetMany(t) for k,v in pairs(t) do values[k]=v end end
  getgenv=function() return _G end
  fakeCombat={IsBusy=function() return combatOutstanding==true end,
    IsRunning=function() return combatStarted==true,'Quest' end,
    Stop=function() combatStarted=false end,StartQuest=function() combatStarted=true end}
  nativeModules={Config=config,RuntimeLog=logger,Farm=items,StandFarm=farm,ServerHop=hop,CombatFarm=fakeCombat}
  ''')
  self.lua.globals().adapter=self.lua.execute((ROOT/'SmartFarmAdapters.lua').read_text())
  self.lua.globals().engine=self.lua.execute((ROOT/'SmartFarmEngine.lua').read_text())
  self.lua.execute('nativeModules.SmartFarmAdapters=adapter; adapter:Init(nativeModules); engine:Init(nativeModules)')
  self.lua.execute('items:_skipStartupForTest(); task.spawn(function() items:Start() end); engine:Step(now); advance(2)')
 def run_lua(self,code): self.lua.execute(code)
 def test_actual_stand_result_releases_then_quest_starts(self):
  self.run_lua('''
  makeTool('Mysterious Arrow')
  onActivate=function() page('Option1','Arrow') end
  onClick=function() stand.Value='Aerosmith'; closeGui() end
  assert(engine:Enqueue({mode='stand',stall=0})); assert(engine:Enqueue({mode='quest',stall=0}))
  engine:Step(now); advance(10); assert(activations==1 and not farm:IsRunning())
  engine:Step(now); engine:Step(now); assert(combatStarted and not values.FarmEnabled)
  ''')
 def test_actual_unresolved_arrow_blocks_quest_after_stop(self):
  self.run_lua('''
  makeTool('Mysterious Arrow'); onActivate=function() page('Option1','Arrow') end
  engine:RequestMode('stand',true); engine:Step(now); advance(3)
  assert(activations==1); engine:RequestMode('quest',true); advance(30); engine:Step(now)
  assert(not combatStarted and engine:GetStatus().state=='releasing' and farm:IsBusy())
  ''')
 def test_actual_respawn_window_is_not_released_on_stop(self):
  self.run_lua('''
  stand.Value='Cream'; makeTool('Mysterious Arrow')
  onActivate=function() page('Option1','Roka') end
  onClick=function() stand.Value='None'; closeGui() end
  engine:RequestMode('stand',true); engine:Step(now); advance(5)
  engine:RequestMode('quest',true); engine:Step(now); assert(not combatStarted and farm:IsBusy())
  respawn(1,1); advance(2.5); char.Parent=player; engine:Step(now); advance(1.2); engine:Step(now)
  assert(combatStarted and activations==1)
  ''')
 def test_actual_item_restock_is_busy_without_running_normal_cycle(self):
  self.run_lua('''
  values.StandFarmEnabled=true
  task.spawn(function() items:Restock('Mysterious Arrow',function() return true end) end)
  assert(items:IsBusy()); engine:RequestMode('quest',true); engine:Step(now)
  assert(not combatStarted); advance(1); engine:Step(now); assert(combatStarted)
  ''')


class PanelTests(unittest.TestCase):
 setUp=EngineTests.setUp
 run_lua=EngineTests.run_lua
 def install_panel(self):
  self.run_lua("""
  controls={}; boxes={}; parent={}; UDim2={new=function() return {} end}
  Enum={Font={Code='Code',GothamBold='Bold'}}; theme={PANEL2='panel',WHITE='white'}
  Instance={new=function(class,parent)
    local obj={Parent=parent}; if class=='TextBox' then boxes[#boxes+1]=obj end
    obj.MouseButton1Click={Connect=function(_,fn) controls[obj.Text]=fn; return {} end}
    return obj
  end}
  ui={AddLabel=function(_,parent,text) return {Parent=parent,Text=text} end,
    RefreshEngineMode=function(_,mode) displayedMode=mode end,
    ShowPopup=function(_,text) popup=text end}
  task.spawn=function(fn) uiThread=coroutine.create(fn); assert(coroutine.resume(uiThread)) end
  task.wait=coroutine.yield
  """)
  self.lua.globals().panel=self.lua.execute((ROOT/'SmartFarmUI.lua').read_text())
  self.run_lua('panel:Build(parent,ui,engine,config,function(x) return x end,function() end,theme)')
 def test_controls_enqueue_save_run_remove_and_stop(self):
  self.install_panel()
  self.run_lua("controls['ADICIONAR À FILA'](); assert(#engine:GetStatus().queue==1); controls['SALVAR ATIVIDADE + FILA COMO PERFIL'](); controls['EXECUTAR PERFIL'](); assert(#engine:GetStatus().queue==2); boxes[4].Text='1'; controls['REMOVER TAREFA'](); assert(#engine:GetStatus().queue==1); controls['PARAR TUDO'](); assert(#engine:GetStatus().queue==0); controls['EXCLUIR PERFIL'](); assert(next(engine:GetStatus().profiles)==nil)")
 def test_invalid_controls_never_start_or_persist(self):
  self.install_panel()
  self.run_lua("boxes[1].Text='arbitrary'; controls['ADICIONAR À FILA'](); assert(popup and #engine:GetStatus().queue==0); boxes[1].Text='item'; boxes[2].Text='1,no,0,0,0'; controls['ADICIONAR À FILA'](); assert(#engine:GetStatus().queue==0)")

class CombatAccountingTests(unittest.TestCase):
 def test_task_release_waits_for_yielding_callback(self):
  import test_stand_dialogue as dialogue
  lua=LuaRuntime(unpack_returned_tuples=True); lua.execute(dialogue.MOCK)
  src=(ROOT/'CombatFarm.lua').read_text()
  prefix=src[src.index('local nativeTask = task'):src.index('local CombatFarm = {}')]
  busy=src[src.index('function CombatFarm:IsBusy()'):src.index('function CombatFarm:IsRunning()')]
  lua.globals().account=lua.execute(prefix+"local CombatFarm={}; local isRunning=false\n"+busy+"\nreturn {spawn=task.spawn,busy=function() return CombatFarm:IsBusy() end}")
  lua.execute('account.spawn(function(value) assert(value==123); task.wait(5) end,123); assert(account.busy()); advance(4); assert(account.busy()); advance(2); assert(not account.busy())')

if __name__=="__main__": unittest.main()
