"""Actual Lua helpers with simulated time/network; NOT a Delta speed benchmark."""
import unittest
from pathlib import Path
import test_stand_dialogue as dialogue
import test_rib_restock as restock
import test_restock_hop as hopping
import test_dialogue_performance as merchant

ROOT = Path(__file__).resolve().parents[1]


class PickupSpeedTests(unittest.TestCase):
    run_lua = dialogue.StandDialogueTests.run_lua

    def setUp(self):
        dialogue.StandDialogueTests.setUp(self)
        restock.RibRestockTests.install_item_farm(self)
        self.run_lua('values.FarmEnabled=true')

    def collect(self, extra=''):
        self.run_lua('''
            model,prompt=addSpawn("Gold Coin")
            info={Name="Gold Coin",Model=model,ProximityPrompt=prompt,Position=model.PrimaryPart.Position}
        ''' + extra + '''
            task.spawn(function() local t=now; result=items:_collectForTest(info,model); duration=now-t end)
        ''')

    def test_confirmed_immediate_pickup_removes_old_half_second_wait(self):
        self.collect(); self.run_lua('advance(1); assert(result and prompts==1 and duration<=0.06 and freezes==unfreezes and not noclip)')

    def test_one_later_retry_uses_old_position_settle_window(self):
        self.collect('''
            onPrompt=function(p)
                if prompts==2 then makeTool(p.ObjectText); p.Parent.Parent=nil end
            end
        ''')
        self.run_lua('advance(2); assert(result and prompts==2 and duration>=0.35 and duration<0.4)')

    def test_inventory_replication_delayed_after_despawn_still_confirms(self):
        self.collect('''
            onPrompt=function(p)
                p.Parent.Parent=nil; after(0.2,function() makeTool(p.ObjectText) end)
            end
        ''')
        self.run_lua('advance(2); assert(result and prompts==1 and inventory:Count("Gold Coin")==1)')

    def test_competitor_despawn_does_not_claim_collection(self):
        self.collect('onPrompt=function(p) p.Parent.Parent=nil end')
        self.run_lua('''
            advance(2); assert(result==false and prompts==1 and inventory:Count("Gold Coin")==0)
            for _,line in ipairs(logs) do assert(not line:find("Collected: Gold Coin",1,true)) end
        ''')

    def test_stop_before_early_prompt_and_respawn_during_wait_clean_up(self):
        for action in ('values.FarmEnabled=false', 'player.Character=node("Replacement","Model")'):
            with self.subTest(action=action):
                self.setUp(); self.collect('after(0.025,function() '+action+' end)')
                self.run_lua('advance(2); assert(not result and prompts==0 and freezes==unfreezes and not noclip)')

    def test_two_prompt_limit_on_live_unresponsive_item(self):
        self.collect('onPrompt=function() end')
        self.run_lua('advance(3); assert(not result and prompts==2 and duration<1.6 and freezes==unfreezes)')

    def test_readiness_detection_is_immediate_or_bounded_until_replication(self):
        self.run_lua('''
            signals={}
            testFolder.ChildAdded={Connect=function(_,fn) signals.added=fn; return {Disconnect=function() signals.added=nil end} end}
            local spawns={WaitForChild=function() return testFolder end}
            local world={WaitForChild=function() return spawns end}
            local original=game.GetService
            game.GetService=function(self,name) if name=="Workspace" then return world end; return original(self,name) end
        ''')
        # The already loaded module holds its original Workspace reference.
        source = (ROOT / 'Farm.lua').read_text().replace('return Farm', '''
            function Farm:_detectForTest() InitItemDetection() end
            function Farm:_queuedForTest(model) return SpawnedItems[model]~=nil end
            return Farm''')
        self.lua.globals().detector = self.lua.execute(source)
        self.run_lua('''
            detector:Init({Config=config,Inventory=inventory,Movement=movement,RuntimeLog=logger})
            detector:_detectForTest()
            local ready=addSpawn("Gold Coin"); signals.added(ready); assert(detector:_queuedForTest(ready))
            local partial=addSpawn("Diamond"); local pp=partial.PrimaryPart; partial.PrimaryPart=nil
            signals.added(partial); assert(not detector:_queuedForTest(partial))
            after(0.08,function() partial.PrimaryPart=pp end); advance(0.1)
            assert(detector:_queuedForTest(partial))
            local missing=addSpawn("Rokakaka"); missing.PrimaryPart=nil; signals.added(missing)
            advance(3); assert(not detector:_queuedForTest(missing) and #jobs==0)
        ''')


class MerchantIndexTests(unittest.TestCase):
    setUp = merchant.MerchantLookupTests.setUp

    def test_large_gui_scanned_once_but_text_visibility_and_new_options_stay_live(self):
        self.lua.execute('''
            local b,gui=page("Option1","Merchant"); b.Text="Sell one"
            local listeners={}; disconnected=0
            local function event(key) return {Connect=function(_,fn) listeners[key]=fn;
                return {Disconnect=function() disconnected=disconnected+1; listeners[key]=nil end} end} end
            gui.DescendantAdded=event("add"); gui.DescendantRemoving=event("remove")
            for i=1,500 do node("Text"..i,"TextLabel",gui) end
            local descendants=gui.GetDescendants; scans=0
            function gui:GetDescendants() scans=scans+1; return descendants(self) end
            for i=1,30 do assert(#lookup()==1) end
            assert(scans==1)
            b.Text="Confirm"; assert(signature():find("Confirm")); assert(scans==1)
            b.Visible=false; assert(#lookup()==0); b.Visible=true
            local outside=node("Option6","TextButton",gui); outside.Text="Sell all"; listeners.add(outside)
            assert(findOption("Option6")==outside and scans==2)
            closeGui(); assert(#lookup()==0 and disconnected==2)
        ''')


class PreparedHopTests(unittest.TestCase):
    setUp = dialogue.StandDialogueTests.setUp
    run_lua = dialogue.StandDialogueTests.run_lua

    def install(self):
        hopping.RestockHopTests.install_hop(self)

    def test_preparation_overlaps_sale_wait_and_hop_reuses_one_request(self):
        self.install()
        self.run_lua('''
            httpDelay=1; assert(hop:Prepare()); advance(1.1)
            assert(httpCalls==1 and teleports==0)
            assert(hop:Hop(function() return true end)); assert(httpCalls==1 and teleports==1)
        ''')

    def test_in_flight_preparation_is_not_duplicated(self):
        self.install()
        self.run_lua('''
            httpDelay=1; assert(hop:Prepare()); assert(not hop:Prepare())
            task.spawn(function() hopped=hop:Hop(function() return true end) end)
            advance(2); assert(hopped and httpCalls==1 and teleports==1)
        ''')

    def test_guard_stop_while_waiting_cache_prevents_teleport(self):
        self.install()
        self.run_lua('''
            httpDelay=1; canHop=true; hop:Prepare()
            task.spawn(function() hopped=hop:Hop(function() return canHop end) end)
            after(0.1,function() canHop=false end); advance(2)
            assert(not hopped and httpCalls==1 and teleports==0)
        ''')

    def test_expired_cache_requeries_and_current_server_always_skipped(self):
        self.install()
        self.run_lua('''
            site={data={{id="current",playing=1,maxPlayers=20},{id="other",playing=1,maxPlayers=20}}}
            assert(hop:Prepare()); advance(16); assert(hop:Hop())
            assert(httpCalls==2 and destination=="other")
        ''')

    def test_destroy_invalidates_late_preparation(self):
        self.install()
        self.run_lua('''
            httpDelay=1; assert(hop:Prepare()); hop:Destroy(); advance(2)
            assert(httpCalls==1 and teleports==0)
            task.spawn(function() hopped=hop:Hop(function() return true end) end)
            advance(2); assert(httpCalls==2 and hopped)
        ''')

    def test_destroy_during_ordinary_hop_http_prevents_late_teleport(self):
        self.install()
        self.run_lua('''
            httpDelay=1; task.spawn(function() hopped=hop:Hop() end)
            after(0.1,function() hop:Destroy() end); advance(5)
            assert(not hopped and httpCalls==1 and teleports==0 and cameraFixes==0)
        ''')


if __name__ == '__main__':
    unittest.main()
