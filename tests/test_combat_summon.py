"""Invocation adapter tests; XenonLock body remains byte-identical."""
import subprocess
from pathlib import Path
import unittest
from lupa import LuaRuntime
import test_stand_dialogue as dialogue
ROOT=Path(__file__).resolve().parents[1]

class CombatSummonTests(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime(unpack_returned_tuples=True);self.lua.execute(dialogue.MOCK)
  self.lua.execute('''
  tick=os.clock; task.delay=function(t,f) after(t,f) end
  values.NPCFarmEnabled=true; values.QuestFarmEnabled=true
  summonCalls=0
  remote.InvokeServer=function(_,a,b)
   assert(a=='ToggleStand' and b=='Toggle'); summonCalls=summonCalls+1
   if replyDelay then task.wait(replyDelay) end
   if fails then error('mock failure') end
   if onInvoke then onInvoke() end
   return true
  end
  _G.WhiteHubModules={RuntimeLog=logger}
  ''')
  source=(ROOT/'CombatFarm.lua').read_text();a=source.index('local lastStandSummonAt =');b=source.index('\nlocal _runtimeLog =',a)
  prefix='local Player=player; local _config=config; local activeMode="NPC"; local isRunning=true; local stopRequested=false; local runId=1; local lastStandSummonLogAt=0\n'
  suffix='\nreturn {ensure=ensureStandSummoned,stop=function() runId=runId+1; isRunning=false; stopRequested=true end,start=function(mode) runId=runId+1; isRunning=true; stopRequested=false; activeMode=mode or "NPC" end}'
  self.lua.globals().summon=self.lua.execute(prefix+source[a:b]+suffix)
 def run_lua(self,s):self.lua.execute(s)
 def test_missing_flag_and_morph_requests_and_confirms_spawned_morph(self):
  self.run_lua("onInvoke=function() node('StandMorph','Model',char) end; local ready,requested=summon.ensure(char); assert(not ready and requested and summonCalls==1); assert(summon.ensure(char)==true)")
 def test_false_flag_uses_existing_remote_and_confirms_replication(self):
  self.run_lua("flag=node('SummonedStand','BoolValue',char); flag.Value=false; onInvoke=function() flag.Value=true end; summon.ensure(char); assert(summonCalls==1 and summon.ensure(char)==true)")
 def test_already_summoned_never_toggles_off(self):
  self.run_lua("flag=node('SummonedStand','BoolValue',char); flag.Value=true; assert(summon.ensure(char)==true and summonCalls==0)")
 def test_false_authoritative_flag_overrides_existing_morph(self):
  self.run_lua("flag=node('SummonedStand','BoolValue',char); flag.Value=false; node('StandMorph','Model',char); onInvoke=function() flag.Value=true end; summon.ensure(char); assert(summonCalls==1)")
 def test_unknown_flag_schema_never_toggles_blindly(self):
  self.run_lua("flag=node('SummonedStand','StringValue',char); flag.Value='unknown'; for i=1,100 do summon.ensure(char) end; assert(summonCalls==0 and #logs==1)")
 def test_inflight_rpc_prevents_toggle_spam(self):
  self.run_lua("replyDelay=10; summon.ensure(char); for i=1,100 do advance(0.03); summon.ensure(char) end; advance(5); summon.ensure(char); assert(summonCalls==1); onInvoke=function() node('StandMorph','Model',char) end; advance(3); assert(summon.ensure(char)==true and summonCalls==1)")
 def test_success_reply_alone_is_not_confirmation(self):
  self.run_lua("summon.ensure(char); advance(4.1); assert(summonCalls==1); local ready=summon.ensure(char); assert(not ready and summonCalls==2)")
 def test_unconfirmed_attempts_are_bounded(self):
  self.run_lua("for i=1,5 do summon.ensure(char); advance(4.1) end; for i=1,100 do summon.ensure(char) end; assert(summonCalls==3)")
 def test_new_run_can_retry_after_limit(self):
  self.run_lua("for i=1,3 do summon.ensure(char); advance(4.1) end; summon.start(); summon.ensure(char); assert(summonCalls==4)")
 def test_stop_blocks_deferred_call_and_late_logs(self):
  self.run_lua("local old=task.spawn; task.spawn=function(fn) queued=fn end; summon.ensure(char); summon.stop(); local count=#logs; queued(); advance(5); assert(summonCalls==0 and #logs==count)")
 def test_respawn_blocks_deferred_call_on_old_character(self):
  self.run_lua("task.spawn=function(fn) queued=fn end; summon.ensure(char); player.Character=node('New','Model'); queued(); advance(5); assert(summonCalls==0)")
 def test_stop_during_rpc_prevents_late_logs_and_additional_requests(self):
  self.run_lua("replyDelay=3; summon.ensure(char); summon.stop(); local count=#logs; advance(6); summon.ensure(char); assert(summonCalls==1 and #logs==count)")
 def test_missing_remote_recovers_when_it_replicates(self):
  self.run_lua("local saved=remote; char.children={}; summon.ensure(char); assert(summonCalls==0); table.insert(char.children,saved); onInvoke=function() node('StandMorph','Model',char) end; summon.ensure(char); assert(summonCalls==1)")
 def test_quest_mode_uses_same_adapter_and_honors_toggle_stop(self):
  self.run_lua("summon.start('Quest'); onInvoke=function() node('StandMorph','Model',char) end; summon.ensure(char); assert(summonCalls==1); char.children={remote}; values.QuestFarmEnabled=false; summon.ensure(char); assert(summonCalls==1)")
 def test_only_invocation_helper_changed_outside_xenonlock(self):
  old=subprocess.check_output(['git','show','91f87b3:CombatFarm.lua'],cwd=ROOT,text=True)
  new=(ROOT/'CombatFarm.lua').read_text()
  a=old.index('local lastStandSummonAt =');b=old.index('\nlocal _runtimeLog =',a)
  c=new.index('-- Stand invocation adapter;');d=new.index('\nlocal _runtimeLog =',c)
  self.assertEqual(old[:a]+old[b:],new[:c]+new[d:])
