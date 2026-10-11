"""Guarded transfer tests using actual Lua modules; not Roblox arrival proof."""
import unittest
from pathlib import Path
import test_stand_dialogue as dialogue
import test_rib_restock as restock
import test_stand_targets as targets
from ai.autofix import check_luau

ROOT = Path(__file__).resolve().parents[1]


class RestockHopTests(unittest.TestCase):
    setUp = dialogue.StandDialogueTests.setUp
    run_lua = dialogue.StandDialogueTests.run_lua

    def install_hop(self):
        restock.RibRestockTests.install_item_farm(self)
        self.run_lua('''
        local originalService=game.GetService
        site={data={{id="destination",maxPlayers=20,playing=1}}}
        httpCalls,teleports,cameraFixes=0,0,0
        local httpService={JSONDecode=function() return site end,JSONEncode=function() return "mock-json" end}
        local teleportService={TeleportToPlaceInstance=function(_,place,id) teleports=teleports+1; destination=id end}
        local coreGui={DescendantAdded={Connect=function() return {Disconnect=function() end} end}}
        game.PlaceId=123; game.JobId="current"
        game.GetService=function(self,name)
            if name=="HttpService" then return httpService end
            if name=="TeleportService" then return teleportService end
            if name=="CoreGui" then return coreGui end
            return originalService(self,name)
        end
        function game:HttpGet()
            httpCalls=httpCalls+1
            if httpDelay then task.wait(httpDelay) end
            if onHttpReturn then onHttpReturn() end
            if httpFails then error("mock network failure") end
            return "mock-json"
        end
        task.delay=function(seconds,fn) after(seconds,fn) end
        function movement:FixCamera() cameraFixes=cameraFixes+1 end
        ''')
        source = (ROOT / 'ServerHop.lua').read_text()
        self.assertTrue(check_luau(source))
        self.lua.globals().hop = self.lua.execute(source)
        self.run_lua('''
        hop:Init({Config=config,Movement=movement,RuntimeLog=logger})
        farm:Init({Config=config,Inventory=inventory,Movement=movement,RuntimeLog=logger,Farm=items,ServerHop=hop})
        values.StandFarmAutoRestock=true; values.StandFarmRestockHop=true
        removeTool("Mysterious Arrow")
        ''')

    def test_exhausted_restock_requests_one_hop_and_stays_off_after_reload(self):
        self.install_hop()
        self.run_lua('''
        assert(farm:Start()); advance(100)
        assert(teleports==1 and httpCalls==1 and activations==0 and not farm:IsRunning())
        assert(values.StandFarmEnabled==false and values.StandFarmRestockPendingItem=="Mysterious Arrow")
        farm:Init({Config=config,Inventory=inventory,Movement=movement,RuntimeLog=logger,Farm=items,ServerHop=hop})
        advance(100)
        assert(teleports==1 and activations==0 and not farm:IsRunning())
        assert(farm:GetStatus().message:find("enable beta manually"))
        ''')

    def test_disabled_option_private_preference_and_collection_success_never_hop(self):
        for action in ['values.StandFarmRestockHop=false', 'values.StayInPrivateServer=true', 'addSpawn("Mysterious Arrow")']:
            with self.subTest(action=action):
                self.setUp(); self.install_hop()
                self.run_lua(action + '''
                onActivate=function() page("Option1","Arrow") end
                onClick=function() stand.Value="Aerosmith"; closeGui() end
                assert(farm:Start()); advance(100)
                assert(teleports==0 and httpCalls==0 and not farm:IsRunning())
                ''')

    def test_stop_during_http_prevents_teleport_and_late_logs(self):
        self.install_hop()
        self.run_lua('''
        httpDelay=4
        after(92,function() farm:Stop(); stoppedLogs=#logs; assert(not farm:Start()) end)
        assert(farm:Start()); advance(100)
        assert(httpCalls==1 and teleports==0 and activations==0 and #logs==stoppedLogs)
        assert(not farm:GetStatus().hopping and values.StandFarmRestockPendingItem=="")
        ''')

    def test_pity_competing_farm_dialogue_and_character_changes_abort_delayed_hop(self):
        for action in ['pity.Value=20', 'values.FarmEnabled=true', 'page("Option1","Other dialogue")', 'player.Character=node("New","Model")']:
            with self.subTest(action=action):
                self.setUp(); self.install_hop()
                self.run_lua('httpDelay=3; onHttpReturn=function() ' + action + ''' end
                assert(farm:Start()); advance(100)
                assert(httpCalls==1 and teleports==0 and activations==0 and not farm:IsRunning())
                assert(values.StandFarmRestockPendingItem=="")
                ''')

    def test_unknown_skin_after_server_query_blocks_transfer(self):
        self.install_hop()
        self.run_lua('''
        stand.Value="Cream"; httpDelay=2; onHttpReturn=function() skin="" end
        assert(farm:Start()); advance(100)
        assert(httpCalls==1 and teleports==0 and activations==0 and stand.Value=="Cream")
        ''')

    def test_pending_consumption_still_prevents_start_and_hop(self):
        self.install_hop()
        self.run_lua('''
        makeTool("Mysterious Arrow")
        onActivate=function() page("Option1","Pending") end
        assert(farm:Start()); advance(2); farm:Stop(); closeGui(); removeTool("Mysterious Arrow")
        assert(not farm:Start()); advance(100)
        assert(activations==1 and httpCalls==0 and teleports==0)
        ''')

    def test_http_failure_or_no_destination_leaves_beta_off_without_notice(self):
        for action in ['httpFails=true', 'site={data={}}']:
            with self.subTest(action=action):
                self.setUp(); self.install_hop()
                self.run_lua(action + '''
                assert(farm:Start()); advance(100)
                assert(teleports==0 and activations==0 and not farm:IsRunning())
                assert(values.StandFarmRestockPendingItem=="")
                ''')

    def test_guarded_hop_skips_current_server_and_legacy_hop_keeps_camera_cleanup(self):
        self.install_hop()
        self.run_lua('''
        site={data={{id="current",maxPlayers=20,playing=1},{id="other",maxPlayers=20,playing=1}}}
        assert(hop:Hop(function() return true end)); assert(destination=="other" and teleports==1)
        advance(4); assert(cameraFixes==0)
        site={data={{id="legacy",maxPlayers=20,playing=1}}}
        assert(hop:Hop()); advance(4)
        assert(destination=="legacy" and teleports==2 and cameraFixes==1)
        ''')

    def test_option_toggle_cancels_running_beta_and_does_not_enable_restock(self):
        targets.StandTargetTests.build_ui(self)
        self.run_lua('''
        function MakeToggle(_,label,default,fn) hopChange=fn; hopDefault=default end
        ''')
        source = (ROOT / 'UI.lua').read_text()
        chunk = source[source.index('    MakeToggle(FarmPage, "Hop After Restock Limit'):source.index('    local refreshTargetList')]
        self.lua.execute(chunk)
        self.run_lua('''
        assert(hopDefault==false)
        onActivate=function() page("Option1","Pending") end
        assert(farm:Start()); advance(2); hopChange(true)
        assert(not farm:IsRunning() and values.StandFarmRestockHop==true and values.StandFarmAutoRestock==nil)
        closeGui(); assert(not farm:Start()); advance(8); assert(activations==1)
        ''')

    def test_ui_cancel_button_remains_available_while_beta_toggle_is_off(self):
        self.install_hop()
        targets.StandTargetTests.build_ui(self)
        self.run_lua('function MakeToggle() end')
        source = (ROOT / 'UI.lua').read_text()
        chunk = source[source.index('    local cancelRestockHop ='):source.index('    local refreshTargetList')]
        self.lua.execute(chunk)
        self.run_lua('''
        httpDelay=4
        after(92,function() assert(not farm:IsRunning()); buttons[#buttons].click(); stoppedLogs=#logs end)
        assert(farm:Start()); advance(100)
        assert(teleports==0 and httpCalls==1 and #logs==stoppedLogs and values.StandFarmRestockPendingItem=="")
        ''')

    def test_parallel_manual_hop_is_rejected_while_guarded_request_is_in_flight(self):
        self.install_hop()
        self.run_lua('''
        httpDelay=4
        task.spawn(function() first=hop:Hop(function() return true end) end)
        after(1,function() second=hop:Hop() end)
        advance(5)
        assert(first==true and second==false and httpCalls==1 and teleports==1)
        ''')
