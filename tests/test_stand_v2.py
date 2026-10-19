from module_sources import module_source
"""Actual Lua transfer/skin/metric paths with mocked executor, not Delta QA."""
import json
import unittest
from pathlib import Path
from lupa import lua_type
import test_stand_dialogue as dialogue
import test_restock_hop as hopping
import test_stand_targets as targets
from ai.autofix import check_luau

ROOT=Path(__file__).resolve().parents[1]


class StandV2Tests(unittest.TestCase):
    setUp=dialogue.StandDialogueTests.setUp
    run_lua=dialogue.StandDialogueTests.run_lua

    def install_transfer(self):
        hopping.RestockHopTests.install_hop(self)

        def to_python(value):
            if lua_type(value)!='table':
                return value
            keys=list(value.keys())
            if not keys or set(keys)==set(range(1,len(keys)+1)):
                return [to_python(value[i]) for i in range(1,len(keys)+1)]
            return {k:to_python(v) for k,v in value.items()}

        def to_lua(value):
            if isinstance(value,dict):
                return self.lua.table_from({k:to_lua(v) for k,v in value.items()})
            if isinstance(value,list):
                return self.lua.table_from([to_lua(v) for v in value])
            return value

        self.lua.globals().jsonEncode=lambda value:json.dumps(to_python(value),allow_nan=False)
        self.lua.globals().jsonDecode=lambda raw:to_lua(json.loads(raw))
        self.run_lua('''
        files,queued,savedRecords={}, {}, {}; guidCounter=0; baseTime=1000000
        os.time=function() return baseTime+math.floor(now) end
        function readfile(path) if not files[path] then error("no file") end; return files[path] end
        function writefile(path,raw) if diskFails then error("disk failure") end; files[path]=raw end
        function queue_on_teleport(script)
            if queueFails then error("queue failure") end
            table.insert(queued,script); return queueResult
        end
        local original=game.GetService
        nativeHttp={JSONEncode=function(_,data) return jsonEncode(data) end,
            JSONDecode=function(_,raw) if raw=="mock-json" then return site end; return jsonDecode(raw) end,
            GenerateGUID=function() guidCounter=guidCounter+1; return string.format("%08x-1234-1234-1234-123456789abc",guidCounter) end}
        game.GetService=function(self,name)
            if name=="HttpService" then return nativeHttp end
            return original(self,name)
        end
        local ts=game:GetService("TeleportService")
        teleportSettings={}
        function ts:GetTeleportSetting(key) return teleportSettings[key] end
        function ts:SetTeleportSetting(key,value) teleportSettings[key]=value end
        ts.TeleportInitFailed={Connect=function(_,fn)
            failedEvent=fn; return {Disconnect=function() failedEvent=nil end}
        end}
        ''')
        source=(ROOT/'StandTransfer.lua').read_text()
        self.assertTrue(check_luau(source))
        self.lua.globals().transfer=self.lua.execute(source)
        self.run_lua('''
        farm:Init({Config=config,Inventory=inventory,Movement=movement,RuntimeLog=logger,
            Farm=items,ServerHop=hop,StandTransfer=transfer})
        values.StandFarmResumeAfterHop=true
        ''')

    def new_arrival_module(self, job='destination'):
        self.run_lua('game.JobId='+json.dumps(job))
        source=(ROOT/'StandFarm.lua').read_text()
        source=source.replace('            continue\n','            goto next_iteration\n')
        source=source.replace('    end\n    if runToken == token then','        ::next_iteration::\n    end\n    if runToken == token then')
        self.lua.globals().farm=self.lua.execute(source)
        self.run_lua('''
        farm:Init({Config=config,Inventory=inventory,Movement=movement,RuntimeLog=logger,
            Farm=items,ServerHop=hop,StandTransfer=transfer})
        ''')

    def issue_owned_hop(self):
        self.run_lua('assert(farm:Start()); advance(100); assert(teleports==1 and #queued==1); record=transfer:Read(); assert(record)')

    def test_owned_destination_resumes_once_with_metrics_and_restock(self):
        self.install_transfer(); self.issue_owned_hop(); self.new_arrival_module()
        self.run_lua('''
        addSpawn("Mysterious Arrow")
        onActivate=function() page("Option1","Arrow") end
        onClick=function() stand.Value="Aerosmith"; pity.Value=pity.Value+1; closeGui() end
        assert(not farm:IsRunning()); assert(farm:RecoverTransfer()); advance(12)
        assert(activations==1 and not farm:IsRunning() and transfer:Read()==nil)
        assert(not farm:RecoverTransfer())
        local m=farm:GetStatus().metrics
        assert(m.hops==1 and m.rolls==1 and m.arrows==1 and m.restocks==1 and m.pity_delta==1)
        ''')

    def test_ordinary_reload_wrong_place_and_wrong_destination_never_resume(self):
        for job,place in [('current',123),('other',123),('destination',456)]:
            with self.subTest(job=job,place=place):
                self.setUp(); self.install_transfer(); self.issue_owned_hop(); self.new_arrival_module(job)
                self.run_lua('game.PlaceId='+str(place)+'''; assert(not farm:RecoverTransfer()); advance(40)
                    assert(activations==0 and not farm:IsRunning() and transfer:Read()==nil)''')

    def test_expired_intent_does_not_resume(self):
        self.install_transfer(); self.issue_owned_hop(); self.new_arrival_module()
        self.run_lua('baseTime=baseTime+1000; assert(not farm:RecoverTransfer()); advance(40); assert(activations==0)')

    def test_changed_settings_opt_out_and_competing_farm_hold_resume(self):
        for action in ['values.StandFarmResumeAfterHop=false','values.StandFarmTarget="Cream"',
                       'values.StandFarmPityLimit=19','values.FarmEnabled=true','values.StandFarmSkinTargets={"New Skin"}']:
            with self.subTest(action=action):
                self.setUp(); self.install_transfer(); self.issue_owned_hop(); self.new_arrival_module()
                self.run_lua(action+'; assert(not farm:RecoverTransfer()); advance(40); assert(activations==0 and not farm:IsRunning())')

    def test_unconfirmed_stand_pity_or_skin_preserves_result(self):
        for action in ['stand.Value="Cream"','pity.Value=1']:
            with self.subTest(action=action):
                self.setUp(); self.install_transfer(); self.issue_owned_hop(); self.new_arrival_module()
                self.run_lua(action+'; assert(farm:RecoverTransfer()); advance(40); assert(activations==0 and not farm:IsRunning())')
        self.setUp(); self.install_transfer()
        self.run_lua('stand.Value="Cream"')
        self.issue_owned_hop(); self.new_arrival_module()
        self.run_lua('skin="Any Skin"; assert(farm:RecoverTransfer()); advance(8); assert(activations==0 and stand.Value=="Cream")')

    def test_stop_during_arrival_wait_consumes_intent_without_late_actions(self):
        self.install_transfer(); self.issue_owned_hop(); self.new_arrival_module()
        self.run_lua('''
        stand.Value="Cream"; assert(farm:RecoverTransfer()); advance(1); farm:Stop()
        local n=#logs; advance(40)
        assert(activations==0 and #logs==n and transfer:Read()==nil and not farm:IsRunning())
        ''')

    def test_queue_or_file_failure_does_not_submit_auto_transfer(self):
        for action in ['queueFails=true','queueResult=false','diskFails=true']:
            with self.subTest(action=action):
                self.setUp(); self.install_transfer()
                self.run_lua(action+'; assert(farm:Start()); advance(100); assert(teleports==0 and activations==0 and not farm:IsRunning())')

    def test_missing_executor_capabilities_falls_back_to_manual_restart(self):
        self.install_transfer()
        self.run_lua('queue_on_teleport=nil; assert(farm:Start()); advance(100); assert(teleports==1 and #queued==0 and not farm:IsRunning())')

    def test_failed_teleport_invalidates_queued_intent(self):
        self.install_transfer(); self.issue_owned_hop()
        self.run_lua('failedEvent(player); assert(transfer:Read()==nil and not farm:IsRunning()); advance(10); assert(activations==0)')

    def test_hop_budget_survives_multiple_arrivals(self):
        self.install_transfer(); self.run_lua('values.StandFarmMaxHops=2')
        self.issue_owned_hop(); self.new_arrival_module()
        self.run_lua('site={data={{id="destination2",playing=1,maxPlayers=20}}}; assert(farm:RecoverTransfer()); advance(100); assert(teleports==2)')
        self.new_arrival_module('destination2')
        self.run_lua('site={data={{id="destination3",playing=1,maxPlayers=20}}}; assert(farm:RecoverTransfer()); advance(100); assert(teleports==2 and not farm:IsRunning())')

    def test_schema_rejects_arbitrary_fields_repeated_jobs_and_bad_metrics(self):
        self.install_transfer(); self.issue_owned_hop()
        self.run_lua('''
        record.adminKey="not-allowed"; assert(not transfer:Validate(record)); record.adminKey=nil
        record.metrics.arrows=-1; assert(not transfer:Validate(record)); record.metrics.arrows=0
        record.visited[1]=record.destination; assert(not transfer:Validate(record))
        ''')

    def test_claim_requires_successful_invalidation(self):
        self.install_transfer(); self.issue_owned_hop(); self.new_arrival_module()
        self.run_lua('diskFails=true; assert(not farm:RecoverTransfer()); advance(40); assert(activations==0 and not farm:IsRunning())')

    def test_unclaimed_record_cannot_directly_start_resume(self):
        self.run_lua('assert(not farm:Start({})); advance(5); assert(activations==0)')

    def test_skin_wishlist_exact_match_preserves_desired_and_other_skins(self):
        for skin_name,desired in [('Wanted Skin',True),('Other Skin',False)]:
            with self.subTest(skin=skin_name):
                self.setUp()
                self.run_lua('values.StandFarmMode="shiny"; values.StandFarmSkinTargets={"Wanted Skin"}; skin='+json.dumps(skin_name)+'''
                    onActivate=function() page("Option1","Arrow") end
                    onClick=function() stand.Value="Cream"; closeGui() end
                    assert(farm:Start()); advance(8); assert(activations==1 and stand.Value=="Cream" and not farm:IsRunning())
                    assert(farm:GetStatus().metrics.lastSkin==skin)
                    ''')
                reason=self.lua.eval('farm:GetStatus().stop_reason')
                self.assertEqual('Desired skin found' in reason,desired)

    def test_invalid_skin_list_blocks_consumption(self):
        self.run_lua('''
        for _,v in ipairs({"bad",{"None"},{""},{false},{key="Skin"}}) do
            values.StandFarmSkinTargets=v; assert(not farm:Start())
        end
        assert(activations==0)
        ''')

    def test_metrics_count_confirmed_consumables_elapsed_and_pity(self):
        self.run_lua('''
        number=0
        onActivate=function(name) item=name; page("Option1",name) end
        onClick=function()
            if item=="Rokakaka" then stand.Value="None"; respawn()
            else number=number+1; stand.Value=number==1 and "Cream" or "Aerosmith"; pity.Value=pity.Value+1 end
            closeGui()
        end
        assert(farm:Start()); advance(18)
        local m=farm:GetStatus().metrics
        assert(m.attempts==3 and m.arrows==2 and m.rokas==1 and m.rolls==2 and m.ribs==0)
        assert(m.pity_delta==2 and m.pity_remaining==18 and m.rolls_per_hour>0)
        local elapsed=m.elapsed; advance(10); assert(farm:GetStatus().metrics.elapsed==elapsed)
        m.arrows=99; assert(farm:GetStatus().metrics.arrows==2)
        assert(farm:ResetStatistics()); assert(farm:GetStatus().metrics.attempts==0)
        ''')

    def test_uncertain_consumption_not_counted_as_confirmed_and_cannot_reset(self):
        self.run_lua('''
        onActivate=function() page("Option1","Stuck") end
        assert(farm:Start()); advance(8)
        local m=farm:GetStatus().metrics; assert(m.attempts==1 and m.arrows==0 and m.rolls==0)
        assert(not farm:ResetStatistics())
        ''')

    def test_submitted_transfer_blocks_local_start_and_stats_reset(self):
        self.install_transfer(); self.issue_owned_hop()
        self.run_lua('''
        assert(farm:GetStatus().awaiting_transfer and not farm:Start() and not farm:ResetStatistics())
        farm:Stop(); assert(transfer:Read()==nil and not farm:Start())
        ''')

    def test_queued_loader_replay_and_cancel_during_fetch_are_noops(self):
        self.install_transfer(); self.issue_owned_hop()
        self.run_lua('''
        game.JobId="destination"; loaderRuns,fetches=0,0
        function game:HttpGet(url) fetches=fetches+1; return "mock-loader" end
        function loadstring(source) return function() loaderRuns=loaderRuns+1; transfer:Claim(game.PlaceId,game.JobId) end end
        ''')
        script=self.lua.eval('queued[1]')
        self.lua.execute(script); self.lua.execute(script)
        self.run_lua('assert(loaderRuns==1 and fetches==1)')
        self.setUp(); self.install_transfer(); self.issue_owned_hop()
        self.run_lua('''
        game.JobId="destination"; loaderRuns=0
        function game:HttpGet() transfer:Invalidate(); return "mock-loader" end
        function loadstring() return function() loaderRuns=loaderRuns+1 end end
        ''')
        self.lua.execute(self.lua.eval('queued[1]'))
        self.run_lua('assert(loaderRuns==0)')

    def test_source_callback_failure_blocks_teleport_before_submission(self):
        self.install_transfer()
        self.run_lua('''
        assert(not hop:Hop(function() return true end,function() return false end))
        assert(teleports==0)
        ''')

    def install_v2_ui(self):
        targets.StandTargetTests.build_ui(self)
        source=module_source(ROOT,"StandV2UI.lua")
        self.assertTrue(check_luau(source))
        self.lua.globals().v2ui=self.lua.execute(source)
        self.run_lua('''
        toggles={}
        function MakeToggle(_,label,default,fn) toggles[label]={value=default,change=fn} end
        function stopForEdit() farm:Stop(); UI:SetToggleValue("Stand Farm (BETA)",false) end
        ''')

    def test_ui_skin_selector_preserves_exact_names_stops_and_rejects_invalid_choice(self):
        self.install_v2_ui()
        self.run_lua('''
        v2ui:BuildSkins(FarmPage,UI,config,farm,stopForEdit,trackConnection,THEME,_choices,_catalog)
        onActivate=function() page("Option1","Pending") end
        assert(farm:Start()); advance(2)
        skinChoice("Wanted Skin"); skinChoice("Other Skin")
        assert(not farm:IsRunning() and #values.StandFarmSkinTargets==2)
        assert(values.StandFarmSkinTargets[1]=="Other Skin")
        skinChoice("None"); assert(#values.StandFarmSkinTargets==2)
        skinChoice("Wanted Skin"); skinChoice("Other Skin"); assert(#values.StandFarmSkinTargets==0)
        ''')

    def test_ui_resume_opt_in_budget_and_unsupported_executor_message(self):
        self.install_v2_ui()
        self.run_lua('''
        v2ui:BuildResume(FarmPage,UI,config,farm,MakeToggle,trackConnection,THEME)
        assert(toggles["Auto Resume Owned Hop (BETA)"].value==false)
        toggles["Auto Resume Owned Hop (BETA)"].change(true)
        assert(values.StandFarmResumeAfterHop==true and popup:find("Manual restart"))
        local budget=buttons[#buttons]; budget.Text="Auto hop limit: 2"; budget.blur()
        assert(values.StandFarmMaxHops==2)
        budget.Text="Auto hop limit: 99"; budget.blur(); assert(values.StandFarmMaxHops==2)
        ''')

    def test_ui_statistics_show_counts_and_refuse_reset_with_pending_action(self):
        self.install_v2_ui()
        self.run_lua('''
        v2ui:BuildStats(FarmPage,UI,farm,trackConnection,styleActionButton)
        local label=labels[#labels]; assert(#buttons==0)
        assert(label.Text:find("Attempts: 0"))
        onActivate=function() page("Option1","Pending") end
        assert(farm:Start()); advance(2); local ok,reason=farm:ResetStatistics()
        assert(not ok and reason:find("pending") and farm:GetStatus().metrics.attempts==1)
        label.Parent=nil; farm:Stop(); advance(5)
        ''')

    def test_target_change_during_skin_check_cancels_start(self):
        self.run_lua('''
        stand.Value="Cream"
        function remote:InvokeServer() task.wait(1); return "None" end
        task.spawn(function() started=farm:Start() end)
        after(0.2,function() values.StandFarmTarget="Star Platinum" end)
        advance(4); assert(started==false and activations==0)
        ''')

    def test_stop_revokes_marker_even_when_file_writes_fail(self):
        self.install_transfer(); self.issue_owned_hop()
        self.run_lua('diskFails=true; farm:Stop(); game.JobId="destination"; loaderRuns=0; function loadstring() return function() loaderRuns=loaderRuns+1 end end')
        self.lua.execute(self.lua.eval('queued[1]'))
        self.run_lua('assert(loaderRuns==0 and teleportSettings["WHITE_HUB_STAND_TRANSFER_V1"]=="")')
