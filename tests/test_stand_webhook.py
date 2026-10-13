"""Terminal webhook paths using actual Lua modules; no real Discord/Delta calls."""
import unittest
from pathlib import Path
from lupa import LuaRuntime
import test_stand_dialogue as dialogue
import test_stand_v2 as v2
from ai.autofix import check_luau

ROOT = Path(__file__).resolve().parents[1]


class StandWebhookTests(unittest.TestCase):
    run_lua = dialogue.StandDialogueTests.run_lua

    def setUp(self):
        dialogue.StandDialogueTests.setUp(self)
        self.run_lua('''
            notices={}; values.WebhookURL="https://example.invalid/mock"
            webhook={SendStandFarmResult=function(_,result) table.insert(notices,result) end}
            farm:Init({Config=config,RuntimeLog=logger,Movement=movement,Webhook=webhook})
            onActivate=function() page("Option1","Use item") end
            onClick=function() stand.Value="Aerosmith"; pity.Value=3; closeGui() end
        ''')

    def test_confirmed_target_sends_once_with_snapshot_and_no_skin_claim(self):
        self.run_lua('''
            assert(farm:Start()); advance(8); advance(30)
            assert(#notices==1 and activations==1 and not farm:IsRunning())
            local n=notices[1]
            assert(n.kind=="target" and n.stand=="Aerosmith" and n.skin==nil)
            assert(n.pity==3 and n.rolls==1 and n.consumable=="Mysterious Arrow" and not n.pending)
        ''')

    def test_rib_result_uses_same_notification_and_correct_source(self):
        self.run_lua('''
            values.StandFarmConsumable="Rib Cage of The Saint's Corpse"
            makeTool(values.StandFarmConsumable)
            assert(farm:Start()); advance(8)
            assert(#notices==1 and notices[1].consumable==values.StandFarmConsumable)
        ''')

    def test_any_and_desired_skin_notify_as_preserved(self):
        for desired in (False, True):
            with self.subTest(desired=desired):
                self.setUp()
                self.run_lua('''
                    values.StandFarmMode="shiny"; skin="Test Skin"
                    values.StandFarmSkinTargets=''' + ('{"Test Skin"}' if desired else '{}') + '''
                    onClick=function() stand.Value="Cream"; closeGui() end
                    assert(farm:Start()); advance(8)
                    assert(#notices==1 and activations==1 and stand.Value=="Cream")
                    assert(notices[1].kind=="skin" and notices[1].skin=="Test Skin")
                    assert(notices[1].desired_skin==''' + str(desired).lower() + ''')
                ''')

    def test_inconclusive_skin_is_stop_never_false_shiny(self):
        self.run_lua('''
            values.StandFarmMode="shiny"; skin=""
            onClick=function() stand.Value="Cream"; closeGui() end
            assert(farm:Start()); advance(8)
            assert(#notices==1 and notices[1].kind=="stopped" and notices[1].skin==nil)
            assert(activations==1 and stand.Value=="Cream")
        ''')

    def test_pity_and_missing_items_send_stop_reason(self):
        for action, reason in [('pity.Value=20', 'Pity limit'),
                               ('bag.children={}', 'Out of Mysterious Arrow')]:
            with self.subTest(reason=reason):
                self.setUp()
                self.run_lua(action + '''; assert(farm:Start()); advance(8)
                    assert(#notices==1 and notices[1].kind=="stopped" and activations==0)
                ''')
                self.assertEqual(self.lua.eval('notices[1].reason'), reason)

    def test_unconfirmed_result_warns_pending_never_target(self):
        self.run_lua('''
            onClick=function() end
            assert(farm:Start()); advance(30)
            assert(#notices==1 and notices[1].kind=="stopped" and notices[1].pending)
            assert(notices[1].rolls==0 and not farm:Start())
        ''')

    def test_manual_stop_and_destroy_do_not_notify(self):
        for action in ('farm:Stop()', 'farm:Destroy()'):
            with self.subTest(action=action):
                self.setUp()
                self.run_lua('assert(farm:Start()); advance(0.1); ' + action + '; advance(30); assert(#notices==0)')

    def test_missing_url_skips_and_old_skin_is_not_reused_next_run(self):
        self.run_lua('''
            values.StandFarmMode="shiny"; skin="Previous Skin"
            onClick=function() stand.Value="Cream"; closeGui() end
            assert(farm:Start()); advance(8); assert(#notices==1)
            skin="None"; stand.Value="None"; values.StandFarmMode="stand"
            onClick=function() stand.Value="Aerosmith"; closeGui() end
            assert(farm:Start()); advance(8); assert(#notices==2 and notices[2].skin==nil)
            stand.Value="None"; values.WebhookURL=""
            assert(farm:Start()); advance(8); assert(#notices==2)
        ''')

    def test_queued_notice_cancelled_on_stop_destroy_or_new_start(self):
        for action in ('farm:Stop()', 'farm:Destroy()',
                       'stand.Value="None"; onClick=function() end; assert(farm:Start())'):
            with self.subTest(action=action):
                self.setUp()
                self.run_lua('''
                    assert(farm:Start())
                    local spawn=task.spawn
                    task.spawn=function(fn)
                        if farm:IsRunning() then spawn(fn)
                        else after(100,function() spawn(fn) end) end
                    end
                    advance(8); assert(not farm:IsRunning() and #notices==0)
                ''' + action + '''; advance(105)
                    assert(#notices<=1)
                    for _,notice in ipairs(notices) do assert(notice.kind~="target") end
                ''')

    def test_slow_or_failed_delivery_cannot_change_farm_result(self):
        self.run_lua('''
            webhook.SendStandFarmResult=function(_,result)
                task.wait(30); error("https://example.invalid/private-error")
            end
            assert(farm:Start()); advance(8)
            assert(not farm:IsRunning() and farm:GetStatus().stand=="Aerosmith" and activations==1)
            advance(40); assert(activations==1)
            for _,line in ipairs(logs) do assert(not line:find("private%-error")) end
        ''')

    def test_successful_restock_transfer_does_not_send_terminal_notice(self):
        v2.StandV2Tests.install_transfer(self)
        self.run_lua('''
            farm:Init({Config=config,Inventory=inventory,Movement=movement,RuntimeLog=logger,
                Farm=items,ServerHop=hop,StandTransfer=transfer,Webhook=webhook})
            values.StandFarmResumeAfterHop=true
            assert(farm:Start()); advance(100)
            assert(teleports==1 and #notices==0 and farm:GetStatus().awaiting_transfer)
        ''')


class WebhookPayloadTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            payloads,requests,logs={}, {}, {}; httpCode=204
            config={Get=function() return "https://example.invalid/mock" end}
            logger={Write=function(_,level,_,message) table.insert(logs,level..":"..message) end}
            game={GetService=function(_,name)
                if name=="Players" then return {LocalPlayer={Name="TestPlayer"}} end
                return {JSONEncode=function(_,value) table.insert(payloads,value); return "mock-json" end}
            end}
            request=function(value) table.insert(requests,value); return {StatusCode=httpCode} end
            result={kind="skin",desired_skin=true,mode="shiny",consumable="Mysterious Arrow",
                stand="Cream",skin="Test Skin",pity=15,rolls=3,elapsed=12.9,reason="Skin preserved"}
        ''')
        source = (ROOT / 'Webhook.lua').read_text()
        self.assertTrue(check_luau(source))
        self.lua.globals().webhook = self.lua.execute(source)
        self.lua.execute('webhook:Init({Config=config,RuntimeLog=logger})')

    def test_bounded_snapshot_payload_and_204_confirmed(self):
        self.lua.execute('''
            assert(webhook:SendStandFarmResult(result))
            assert(#requests==1 and requests[1].Method=="POST")
            local p=payloads[1]
            assert(#p.allowed_mentions.parse==0 and #p.embeds[1].description<1500)
            local d=p.embeds[1].description
            assert(d:find("Target skin found") and d:find("Test Skin") and d:find("12s"))
        ''')

    def test_request_exceptions_and_http_errors_do_not_leak_or_claim_success(self):
        for script in ('httpCode=429', 'httpCode=500',
                       'request=function() error("https://example.invalid/private-error") end',
                       'request=nil', 'request=function() return nil end'):
            with self.subTest(script=script):
                self.setUp()
                self.lua.execute(script + '''
                    assert(not webhook:SendStandFarmResult(result))
                    assert(#logs==1 and logs[1]:find("WARN:"))
                    assert(not logs[1]:find("private%-error") and not logs[1]:find("request sent"))
                    assert(#requests<=1)
                ''')

    def test_untrusted_fields_are_bounded_and_mentions_removed(self):
        self.lua.execute('''
            result.skin=string.rep("@`A",1000); result.reason="https://example.invalid/private "..string.rep("R",5000)
            assert(webhook:SendStandFarmResult(result))
            local d=payloads[1].embeds[1].description
            assert(#d<1500 and not d:find("@") and not d:find("example.invalid"))
        ''')

    def test_existing_notifications_retain_old_payload_and_transport(self):
        self.lua.execute('''
            webhook:SendPhase1Complete(9,9,1000000)
            assert(#requests==1 and payloads[1].allowed_mentions==nil)
            assert(payloads[1].embeds[1].description:find("Phase 1 complete"))
        ''')


if __name__ == '__main__':
    unittest.main()
