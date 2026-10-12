"""Shiny beta runs actual Lua with mocked game stats; not YBA validation."""
import unittest
from pathlib import Path
import test_stand_dialogue as dialogue
import test_stand_targets as targets


class ShinyModeTests(unittest.TestCase):
    setUp = dialogue.StandDialogueTests.setUp
    run_lua = dialogue.StandDialogueTests.run_lua

    def test_shiny_needs_no_stand_target_and_preserves_first_skin(self):
        self.run_lua('''
        values.StandFarmMode="shiny"; values.StandFarmTarget=""
        onActivate=function() page("Option1","Use arrow") end
        onClick=function() stand.Value="Cream"; skin="Any Skin"; closeGui() end
        assert(farm:Start()); advance(8)
        assert(activations==1 and not farm:IsRunning() and stand.Value=="Cream")
        assert(farm:GetStatus().mode=="shiny" and #farm:GetStatus().targets==0)
        assert(farm:GetStatus().stop_reason:find("Skin detected"))
        ''')

    def test_common_target_replaced_until_any_skin(self):
        self.run_lua('''
        values.StandFarmMode="shiny"; values.StandFarmTargets={"Cream"}
        result=0
        onActivate=function(name) item=name; page("Option1",name) end
        onClick=function()
            if item=="Rokakaka" then stand.Value="None"; skin="None"; respawn()
            else result=result+1; stand.Value="Cream"; skin=result==2 and "Any Skin" or "None" end
            closeGui()
        end
        assert(farm:Start()); advance(18)
        assert(activations==3 and result==2 and farm:GetStatus().rolls==2)
        assert(not farm:IsRunning() and farm:GetStatus().stop_reason:find("Skin detected"))
        ''')

    def test_owned_common_target_can_be_replaced_only_in_shiny_mode(self):
        self.run_lua('''
        values.StandFarmMode="shiny"; values.StandFarmTargets={"Cream"}; stand.Value="Cream"
        onActivate=function(name) item=name; page("Option1",name) end
        onClick=function()
            stand.Value=item=="Rokakaka" and "None" or "Aerosmith"
            skin=item=="Rokakaka" and "None" or "Any Skin"
            if item=="Rokakaka" then respawn() end; closeGui()
        end
        assert(farm:Start()); advance(12)
        assert(activations==2 and stand.Value=="Aerosmith" and not farm:IsRunning())
        ''')

    def test_owned_skin_and_inconclusive_skin_never_consume(self):
        self.run_lua('''
        values.StandFarmMode="shiny"; stand.Value="Cream"
        for _,response in ipairs({"Any Skin","",false,{}}) do
            skin=response; local ok=farm:Start(); assert(not ok and activations==0)
        end
        skin=nil; assert(not farm:Start()); advance(8); assert(activations==0)
        ''')

    def test_unknown_skin_after_arrow_stops_without_roka(self):
        self.run_lua('''
        values.StandFarmMode="shiny"
        onActivate=function() page("Option1","Use arrow") end
        onClick=function() stand.Value="Cream"; skin=nil; closeGui() end
        assert(farm:Start()); advance(8)
        assert(activations==1 and not farm:IsRunning() and stand.Value=="Cream")
        assert(farm:GetStatus().stop_reason:find("skin check unavailable"))
        ''')

    def test_skin_replicating_while_equipping_roka_is_preserved(self):
        self.run_lua('''
        values.StandFarmMode="shiny"; stand.Value="Cream"; skin="None"
        function hum:EquipTool(tool) if tool.Name=="Rokakaka" then skin="Late Skin" end end
        assert(farm:Start()); advance(8)
        assert(activations==0 and stand.Value=="Cream" and not farm:IsRunning())
        assert(farm:GetStatus().stop_reason:find("Skin detected"))
        ''')

    def test_mode_is_fixed_during_run(self):
        self.run_lua('''
        values.StandFarmMode="shiny"
        onActivate=function() page("Option1","Use arrow") end
        onClick=function() stand.Value="Cream"; skin="Any Skin"; closeGui() end
        assert(farm:Start()); values.StandFarmMode="stand"; advance(8)
        assert(activations==1 and farm:GetStatus().mode=="shiny")
        ''')

    def test_mode_changed_during_start_skin_lookup_cancels_start(self):
        self.run_lua('''
        values.StandFarmMode="shiny"; stand.Value="Cream"
        function remote:InvokeServer() task.wait(1); return "None" end
        task.spawn(function() started,startReason=farm:Start() end)
        after(0.2,function() values.StandFarmMode="stand" end)
        advance(3)
        assert(started==false and not farm:IsRunning() and activations==0)
        assert(startReason:find("mode changed"))
        ''')

    def test_invalid_modes_refused_and_reload_never_autostarts(self):
        self.run_lua('''
        for _,mode in ipairs({"unknown",true,false,{}}) do
            values.StandFarmMode=mode; assert(not farm:Start())
        end
        values.StandFarmMode="shiny"; values.StandFarmEnabled=true
        farm:Init({Config=config,RuntimeLog=logger,Movement=movement}); advance(8)
        assert(not farm:IsRunning() and not values.StandFarmEnabled and activations==0)
        assert(values.StandFarmMode=="shiny")
        ''')

    def test_pity_stock_and_exclusivity_still_guard_shiny(self):
        self.run_lua('''
        values.StandFarmMode="shiny"; values.QuestFarmEnabled=true
        assert(not farm:Start()); values.QuestFarmEnabled=false
        pity.Value=20; assert(farm:Start()); advance(4); assert(activations==0)
        pity.Value=0; stand.Value="Cream"
        for i,tool in ipairs(bag.children) do if tool.Name=="Rokakaka" then table.remove(bag.children,i); break end end
        assert(farm:Start()); advance(4)
        assert(activations==0 and farm:GetStatus().stop_reason=="Out of Rokakaka")
        ''')

    def test_stop_during_skin_rpc_no_late_consumption_or_log(self):
        self.run_lua('''
        values.StandFarmMode="shiny"
        onActivate=function() page("Option1","Use arrow") end
        onClick=function()
            stand.Value="Cream"; closeGui()
            function remote:InvokeServer(action) if action=="ReturnStandSkin" then task.wait(2) end; return "None" end
            after(1,function() farm:Stop(); logCount=#logs; pressCount=presses end)
        end
        assert(farm:Start()); advance(12)
        assert(not farm:IsRunning() and activations==1 and #logs==logCount and presses==pressCount)
        ''')

    def test_shiny_mode_does_not_bypass_uncertain_item_lock(self):
        self.run_lua('''
        values.StandFarmMode="shiny"
        onActivate=function() page("Option1","Pending") end
        assert(farm:Start()); advance(2); farm:Stop(); closeGui()
        values.StandFarmMode="stand"; assert(not farm:Start()); advance(20)
        assert(activations==1)
        ''')

    def test_ui_mode_switch_stops_current_run_then_changes_config(self):
        targets.StandTargetTests.build_ui(self)
        self.run_lua('''
        function MakeToggle(_,label,default,fn) modeToggle=fn; toggleDefault=default end
        function runtimeLog() end
        ''')
        source = (Path(__file__).resolve().parents[1] / 'UI.lua').read_text()
        chunk = source[source.index('    MakeToggle(FarmPage, "Shiny Farm Mode'):source.index('    local availableStands = {')]
        self.lua.execute(chunk)
        self.run_lua('''
        onActivate=function() page("Option1","Pending") end
        assert(farm:Start()); advance(2); modeToggle(true)
        assert(not farm:IsRunning() and toggleValue==false and values.StandFarmMode=="shiny")
        assert(labels[1].Text:find("saved targets inactive"))
        local n=#logs; advance(10); assert(activations==1 and #logs==n)
        modeToggle(false); assert(values.StandFarmMode=="stand")
        ''')
