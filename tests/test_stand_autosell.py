"""Auto Sell is a preference; actual competing work remains exclusive."""
import unittest
import test_stand_dialogue as dialogue
import test_rib_restock as restock
import test_stand_v2 as v2

class StandAutoSellTests(unittest.TestCase):
    setUp = dialogue.StandDialogueTests.setUp
    run_lua = dialogue.StandDialogueTests.run_lua
    install_transfer = v2.StandV2Tests.install_transfer
    issue_owned_hop = v2.StandV2Tests.issue_owned_hop
    new_arrival_module = v2.StandV2Tests.new_arrival_module

    def test_stand_shiny_and_rib_accept_enabled_auto_sell(self):
        for mode, source in [('stand', 'Mysterious Arrow'), ('shiny', 'Mysterious Arrow'), ('stand', "Rib Cage of The Saint's Corpse")]:
            with self.subTest(mode=mode, source=source):
                self.setUp()
                self.lua.globals().selectedMode = mode
                self.lua.globals().selectedSource = source
                self.run_lua('''
                values.AutoSell=true; values.StandFarmMode=selectedMode
                values.StandFarmConsumable=selectedSource
                if selectedSource~='Mysterious Arrow' then makeTool(selectedSource) end
                onActivate=function() page('Option1','Use') end
                onClick=function() stand.Value='Aerosmith'; if selectedMode=='shiny' then skin='Detected skin' end; closeGui() end
                assert(farm:Start()); advance(8)
                assert(activations==1 and not farm:IsRunning() and values.AutoSell==true)
                assert(stand.Value=='Aerosmith')
                ''')

    def test_enabling_auto_sell_during_pending_dialogue_does_not_cancel(self):
        self.run_lua('''
        onActivate=function() page('Option1','Use') end
        onClick=function() if values.AutoSell then stand.Value='Aerosmith'; closeGui() end end
        assert(farm:Start()); advance(1.6); values.AutoSell=true; advance(8)
        assert(activations==1 and stand.Value=='Aerosmith' and values.AutoSell==true)
        assert(not farm:IsRunning())
        ''')

    def test_restock_collects_without_selling_with_auto_sell_enabled(self):
        restock.RibRestockTests.install_item_farm(self)
        self.run_lua('''
        sales,purchases=0,0
        inventory.SellAll=function() sales=sales+1; error('Restock must not sell') end
        inventory.BuyLucky=function() purchases=purchases+1; error('Restock must not buy') end
        removeTool('Mysterious Arrow'); addSpawn('Mysterious Arrow')
        values.AutoSell=true; values.StandFarmAutoRestock=true
        onActivate=function() page('Option1','Arrow') end
        onClick=function() stand.Value='Aerosmith'; closeGui() end
        assert(farm:Start()); advance(12)
        assert(prompts==1 and activations==1 and sales==0 and purchases==0)
        assert(values.AutoSell==true and not values.FarmEnabled)
        ''')

    def test_actual_sale_finishing_blocks_start_even_after_toggles_are_off(self):
        restock.RibRestockTests.install_item_farm(self)
        self.run_lua('''
        values.AutoSell=true; values.AutoPrestige=true; sales=0
        inventory.SellAll=function()
            sales=sales+1; values.AutoPrestige=false; values.FarmEnabled=false
            task.wait(3); return true
        end
        task.spawn(function() items:PrestigeSell(function() return true end,function() return inventory:SellAll() end) end)
        advance(0.2); assert(items:IsBusy() and not values.FarmEnabled and not values.AutoPrestige)
        local ok,reason=farm:Start(); assert(not ok and reason:find('finishing') and activations==0)
        advance(3); assert(not items:IsBusy() and sales==1)
        onActivate=function() page('Option1','Arrow') end
        onClick=function() stand.Value='Aerosmith'; closeGui() end
        assert(farm:Start()); advance(8); assert(activations==1 and values.AutoSell==true)
        ''')

    def test_busy_work_during_skin_lookup_is_rechecked_before_start(self):
        restock.RibRestockTests.install_item_farm(self)
        self.run_lua('''
        values.AutoSell=true; stand.Value='Cream'
        remote.InvokeServer=function() items:_setBusyForTest(true); return 'None' end
        local ok,reason=farm:Start()
        assert(not ok and reason:find('during skin check') and activations==0)
        ''')

    def test_owned_hop_resume_keeps_auto_sell_and_waits_for_startup_work(self):
        self.install_transfer()
        self.run_lua('values.AutoSell=true')
        self.issue_owned_hop(); self.new_arrival_module()
        self.run_lua('''
        addSpawn('Mysterious Arrow'); items:_setBusyForTest(true)
        onActivate=function() page('Option1','Arrow') end
        onClick=function() stand.Value='Aerosmith'; closeGui() end
        assert(farm:RecoverTransfer()); advance(2); assert(activations==0)
        items:_setBusyForTest(false); advance(12)
        assert(teleports==1 and activations==1 and values.AutoSell==true and not values.FarmEnabled)
        assert(not farm:RecoverTransfer())
        ''')
