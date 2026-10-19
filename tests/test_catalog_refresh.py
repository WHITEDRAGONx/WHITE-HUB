from module_sources import module_source
"""Names-only refresh/cache/cancellation tests. No YBA schema guarantee."""
from pathlib import Path
import unittest
from lupa import LuaRuntime
import test_stand_dialogue as dialogue
import test_game_catalog as catalog_tests
ROOT=Path(__file__).resolve().parents[1]
NETWORK=r'''
task.delay=function(n,fn) after(n,fn) end
os.time=function() return 1000000+math.floor(now) end
calls,writes=0,0
lists={{id='skins',name='Stand Skins: New Part'},{id='cosmetics',name='Cosmetics'}}
cards={{name='Brand New Skin',idList='skins'},{name='Do Not Import Hat',idList='cosmetics'}}
http={JSONDecode=function(_,raw) if raw=='lists' then return lists else return cards end end}
game={GetService=function(_,name) return http end,HttpGet=function(_,url)
 calls=calls+1; lastURL=url
 if httpDelay then task.wait(httpDelay) end
 if fails then error('offline') end
 if oversize then return string.rep('x',250001) end
 return url:find('/lists?',1,true) and 'lists' or 'cards'
end}
config={Get=function() return cache end,Set=function(_,key,data) writes=writes+1; cachedKey=key; cache=data end}
logger={Write=function(_,level,mod,text) lastLog=text end}
all={Config=config,RuntimeLog=logger}
'''
class RefreshTests(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime(unpack_returned_tuples=True);self.lua.execute(dialogue.MOCK+NETWORK)
  self.lua.globals().refresh=self.lua.execute((ROOT/"GameCatalog.lua").read_text()).Online
 def run_lua(self,s):self.lua.execute(s)
 def test_only_skin_cards_imported_cached_and_returned_by_copy(self):
  self.run_lua("refresh:Init(all); assert(calls==2 and writes==1 and refresh:GetState()=='trello'); local names=refresh:GetNames(); assert(#names==1 and names[1]=='Brand New Skin'); names[1]='edited'; assert(refresh:GetNames()[1]=='Brand New Skin' and cachedKey=='SkinCatalogCache')")
 def test_fresh_cache_avoids_http_until_refresh_interval(self):
  self.run_lua("cache={schema=1,board='ROfFdASc',time=os.time(),names={'Saved Skin'}}; refresh:Init(all); assert(calls==0 and refresh:GetState()=='cache'); advance(21600); assert(calls==2 and refresh:GetNames()[1]=='Brand New Skin')")
 def test_stale_cache_is_retained_if_network_fails(self):
  self.run_lua("cache={schema=1,board='ROfFdASc',time=os.time()-30000,names={'Saved Skin'}}; fails=true; refresh:Init(all); assert(calls==1 and writes==0 and refresh:GetState()=='offline' and refresh:GetNames()[1]=='Saved Skin')")
 def test_invalid_cache_board_and_sparse_names_not_trusted(self):
  self.run_lua("cache={schema=1,board='different',time=os.time(),names={'Forged'}}; fails=true; refresh:Init(all); assert(#refresh:GetNames()==0); refresh:Destroy(); cache={schema=1,board='ROfFdASc',names={[2]='Sparse'}}; refresh:Init(all); assert(#refresh:GetNames()==0)")
 def test_no_recognized_skin_list_does_not_request_cards(self):
  self.run_lua("lists={{id='other',name='Cosmetics'}}; refresh:Init(all); assert(calls==1 and writes==0 and #refresh:GetNames()==0)")
 def test_invalid_names_reject_whole_refresh(self):
  self.run_lua("cards={{name='bad\\nname',idList='skins'}}; refresh:Init(all); assert(calls==2 and writes==0 and #refresh:GetNames()==0)")
 def test_oversized_response_is_rejected(self):
  self.run_lua("oversize=true; refresh:Init(all); assert(calls==1 and writes==0 and #refresh:GetNames()==0)")
 def test_timeout_cannot_apply_late_results_or_start_second_request(self):
  self.run_lua("httpDelay=20; refresh:Init(all); advance(11); assert(refresh:GetState()=='timeout' and not refresh:Refresh()); advance(10); assert(calls==1 and writes==0 and #refresh:GetNames()==0)")
 def test_destroy_cancels_late_response_and_future_refresh(self):
  self.run_lua("httpDelay=5; refresh:Init(all); refresh:Destroy(); advance(22000); assert(calls==1 and writes==0 and refresh:GetState()=='stopped')")
 def test_reinit_prevents_previous_worker_overwriting_new_cache(self):
  self.run_lua("httpDelay=5; refresh:Init(all); cache={schema=1,board='ROfFdASc',time=os.time(),names={'New owner cache'}}; refresh:Init(all); advance(6); assert(writes==0 and refresh:GetNames()[1]=='New owner cache' and refresh:GetState()=='cache')")
 def test_no_network_retry_storm_or_duplicate_worker(self):
  self.run_lua("httpDelay=2; refresh:Init(all); for i=1,30 do assert(not refresh:Refresh()) end; advance(5); assert(calls==2); advance(300); assert(calls==2)")
 def test_refresh_has_only_fixed_public_endpoint_and_no_code_execution(self):
  source=module_source(ROOT,"CatalogRefresh.lua")
  self.assertIn('https://api.trello.com/1/boards/ROfFdASc/',source)
  self.assertNotRegex(source,r'loadstring|require\(|getgc|InvokeServer|FireServer|Bearer|GITHUB_TOKEN|WhiteAI')

class LiveAdditions(unittest.TestCase):
 setUp=catalog_tests.CatalogTests.setUp
 run_lua=catalog_tests.CatalogTests.run_lua
 def test_live_quest_names_take_priority_over_fixed_extra_cards(self):
  self.run_lua("workspace.children={tree('Dialogues','Folder',{tree('Live NPC [Lvl. 10+]')})}; local names=catalog:GetQuests({}); assert(#names==1 and names[1]=='INFO | Live NPC [Lvl. 10+]')")
 def test_names_arriving_later_are_detected_on_next_open(self):
  self.run_lua("assert(#catalog:GetQuests({})==34); workspace.children={tree('Dialogues','Folder',{tree('Later NPC [Lvl. 50+]')})}; assert(catalog:GetQuests({})[1]=='INFO | Later NPC [Lvl. 50+]')")
 def test_server_confirmed_observed_skin_added_without_new_rpc(self):
  self.run_lua("catalog:Init({StandFarm={GetStatus=function() return {metrics={lastSkin='New confirmed skin'}} end}}); assert(table.find(catalog:GetSkins(),'New confirmed skin'))")
 def test_online_names_and_client_stringvalue_are_added(self):
  self.run_lua("local value=tree('InternalId','StringValue'); value.Value='New client skin'; rs.children={tree('SkinNames','Folder',{value})}; catalog:Init({}); catalog.Online.GetNames=function() return {'New online skin'} end; local names=catalog:GetSkins(); assert(table.find(names,'New online skin') and table.find(names,'New client skin') and not table.find(names,'InternalId'))")
