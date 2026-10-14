"""Actual Stand/Farm Lua with mocked prompts/inventory; no YBA validation."""
import unittest
from pathlib import Path
import test_stand_dialogue as dialogue
import test_stand_targets as targets
from ai.autofix import check_luau

ROOT = Path(__file__).resolve().parents[1]


class RibRestockTests(unittest.TestCase):
    setUp = dialogue.StandDialogueTests.setUp
    run_lua = dialogue.StandDialogueTests.run_lua

    def install_item_farm(self):
        self.run_lua('''
        tick=os.clock; warn=function() end; print=function() end
        local originalService=game.GetService
        testFolder=node("Items","Folder")
        function testFolder:GetChildren() return self.children end
        function movement:GetCharacter(part) return player.Character and player.Character:FindFirstChild(part) end
        root.CFrame=CFrame.new(0,0,0)
        freezes,unfreezes,prompts=0,0,0
        function movement:Freeze() freezes=freezes+1; return {alive=true} end
        function movement:Unfreeze(bv) if bv and bv.alive then bv.alive=false; unfreezes=unfreezes+1 end end
        function movement:SetNoclip(value) noclip=value end
        function movement:Teleport(cf) safeMoves=safeMoves+1; root.CFrame=cf; return true end
        game.GetService=function(self,name)
            if name=="Workspace" then return {} end
            return originalService(self,name)
        end
        function addSpawn(name)
            local model=node(name,"Model",testFolder)
            model.PrimaryPart={Position={X=20,Y=30,Z=40}}
            function model:GetChildren() return self.children end
            local prompt=node("Prompt","ProximityPrompt",model)
            prompt.ObjectText=name; prompt.MaxActivationDistance=10
            return model,prompt
        end
        inventory={Count=function(_,name)
            local count=0
            for _,container in ipairs({bag,player.Character}) do
                for _,tool in ipairs(container.children) do if tool.Name==name and tool:IsA("Tool") then count=count+1 end end
            end
            return count
        end,HasMax=function() return false end}
        function removeTool(name)
            for i=#bag.children,1,-1 do if bag.children[i].Name==name then table.remove(bag.children,i) end end
        end
        function fireproximityprompt(prompt)
            prompts=prompts+1
            if onPrompt then onPrompt(prompt)
            else makeTool(prompt.ObjectText); prompt.Parent.Parent=nil end
        end
        ''')
        source = (ROOT / 'Farm.lua').read_text()
        self.assertTrue(check_luau(source))
        # Populate the real detection source in isolation; no executor hooks are run.
        source = source.replace('return Farm', '''
        ItemSpawnFolder=testFolder
        function Farm:_setBusyForTest(value) cycleBusy=value end
        function Farm:_queueForTest(model) SpawnedItems[model]=GetItemInfo(model) end
        function Farm:_skipStartupForTest() runtimeSetup=true end
        function Farm:_collectForTest(info,index,guard) return CollectItem(info,index,guard) end
        function Farm:_detectForTest() return InitItemDetection() end
        function Farm:_queuedForTest(model) return SpawnedItems[model]~=nil end
        return Farm''')
        self.lua.globals().items = self.lua.execute(source)
        self.run_lua('''
        items:Init({Config=config,Inventory=inventory,Movement=movement,RuntimeLog=logger})
        farm:Init({Config=config,Inventory=inventory,Movement=movement,RuntimeLog=logger,Farm=items})
        ''')

    def test_rib_uses_selected_tool_and_confirms_target_without_arrow_skill_request(self):
        self.run_lua('''
        values.StandFarmConsumable="Rib Cage of The Saint's Corpse"; values.StandFarmTarget="D4C"
        makeTool(values.StandFarmConsumable)
        onActivate=function(name) used=name; page("Option1",name) end
        onClick=function() stand.Value="D4C"; closeGui() end
        assert(farm:Start()); advance(8)
        assert(used==values.StandFarmConsumable and activations==1 and worthRequests==0)
        assert(not farm:IsRunning() and farm:GetStatus().stop_reason=="Desired Stand found: D4C")
        ''')

    def test_rib_roka_respawn_then_second_rib_stops_at_target(self):
        self.run_lua('''
        values.StandFarmConsumable="Rib Cage of The Saint's Corpse"; values.StandFarmTarget="D4C"
        makeTool(values.StandFarmConsumable); rollsSeen=0
        onActivate=function(name) item=name; page("Option1",name) end
        onClick=function()
            if item=="Rokakaka" then stand.Value="None"; respawn()
            else rollsSeen=rollsSeen+1; stand.Value=rollsSeen==1 and "Scary Monsters" or "D4C" end
            closeGui()
        end
        assert(farm:Start()); advance(18)
        assert(activations==3 and rollsSeen==2 and worthRequests==0 and stand.Value=="D4C")
        assert(not farm:IsRunning())
        ''')

    def test_rib_uncertain_result_blocks_restart(self):
        self.run_lua('''
        values.StandFarmConsumable="Rib Cage of The Saint's Corpse"; makeTool(values.StandFarmConsumable)
        onActivate=function() page("Option1","Pending Rib") end
        assert(farm:Start()); advance(3); farm:Stop(); closeGui()
        assert(not farm:Start()); advance(25); assert(activations==1 and worthRequests==0)
        ''')

    def test_invalid_source_and_source_changed_during_start_are_refused(self):
        self.run_lua('''
        values.StandFarmConsumable="Lucky Arrow"; assert(not farm:Start())
        values.StandFarmConsumable="Mysterious Arrow"; stand.Value="Cream"
        function remote:InvokeServer() task.wait(1); return "None" end
        task.spawn(function() started=farm:Start() end)
        after(0.2,function() values.StandFarmConsumable="Rib Cage of The Saint's Corpse" end)
        advance(3); assert(started==false and activations==0)
        ''')

    def test_restock_missing_arrow_collects_only_arrow_then_resumes(self):
        self.install_item_farm()
        self.run_lua('''
        removeTool("Mysterious Arrow"); addSpawn("Gold Coin"); addSpawn("Mysterious Arrow")
        values.StandFarmAutoRestock=true
        onActivate=function() page("Option1","Arrow") end
        onClick=function() stand.Value="Aerosmith"; closeGui() end
        assert(farm:Start()); advance(12)
        assert(prompts==1 and inventory:Count("Gold Coin")==0 and activations==1)
        assert(not farm:IsRunning() and stand.Value=="Aerosmith" and freezes==unfreezes and noclip==false)
        assert(values.FarmEnabled==nil and values.AutoSell==nil)
        ''')

    def test_restock_missing_roka_checks_next_rib_stock_before_reset(self):
        self.install_item_farm()
        self.run_lua('''
        removeTool("Rokakaka"); stand.Value="Cream"; values.StandFarmTarget="D4C"
        values.StandFarmConsumable="Rib Cage of The Saint's Corpse"; values.StandFarmAutoRestock=true
        addSpawn(values.StandFarmConsumable); addSpawn("Rokakaka")
        onActivate=function(name) item=name; page("Option1",name) end
        onClick=function() stand.Value=item=="Rokakaka" and "None" or "D4C"; closeGui(); if item=="Rokakaka" then respawn() end end
        assert(farm:Start()); advance(22)
        assert(prompts==2 and activations==2 and stand.Value=="D4C" and worthRequests==0)
        ''')

    def test_restock_off_does_not_discard_stand_when_roll_item_missing(self):
        self.install_item_farm()
        self.run_lua('''
        removeTool("Mysterious Arrow"); stand.Value="Cream"; addSpawn("Mysterious Arrow")
        assert(farm:Start()); advance(6)
        assert(prompts==0 and activations==0 and stand.Value=="Cream")
        assert(farm:GetStatus().stop_reason=="Out of Mysterious Arrow")
        ''')

    def test_no_spawn_timeout_preserves_stand_and_stops(self):
        self.install_item_farm()
        self.run_lua('''
        removeTool("Mysterious Arrow"); stand.Value="Cream"; values.StandFarmAutoRestock=true
        assert(farm:Start()); advance(98)
        assert(not farm:IsRunning() and activations==0 and prompts==0 and stand.Value=="Cream")
        assert(farm:GetStatus().stop_reason:find("Restock limit reached"))
        ''')

    def test_stop_before_prompt_no_late_click_move_or_consumption(self):
        self.install_item_farm()
        self.run_lua('''
        removeTool("Mysterious Arrow"); addSpawn("Mysterious Arrow"); values.StandFarmAutoRestock=true
        local move=movement.Teleport
        function movement:Teleport(cf)
            local result=move(self,cf)
            if cf.X==20 then after(0.025,function() farm:Stop(); stoppedMoves=safeMoves; stoppedLogs=#logs end) end
            return result
        end
        assert(farm:Start()); advance(12)
        assert(prompts==0 and activations==0 and safeMoves==stoppedMoves and #logs==stoppedLogs)
        assert(freezes==unfreezes and noclip==false)
        ''')

    def test_despawn_without_inventory_is_not_restock_success(self):
        self.install_item_farm()
        self.run_lua('''
        removeTool("Mysterious Arrow"); addSpawn("Mysterious Arrow"); values.StandFarmAutoRestock=true
        onPrompt=function(prompt) prompt.Parent.Parent=nil end
        assert(farm:Start()); advance(98)
        assert(prompts==1 and activations==0 and not farm:IsRunning())
        ''')

    def test_eight_attempt_limit_no_infinite_collection(self):
        self.install_item_farm()
        self.run_lua('''
        removeTool("Mysterious Arrow"); addSpawn("Mysterious Arrow"); values.StandFarmAutoRestock=true
        onPrompt=function() end
        assert(farm:Start()); advance(30)
        assert(prompts==8 and activations==0 and not farm:IsRunning() and freezes==unfreezes)
        ''')

    def test_competing_farm_character_death_and_dialogue_cancel_collection(self):
        for action in ['values.FarmEnabled=true', 'hum.Health=0', 'page("Option1","Other dialogue")']:
            with self.subTest(action=action):
                self.setUp(); self.install_item_farm()
                self.run_lua('''
                removeTool("Mysterious Arrow"); addSpawn("Mysterious Arrow"); values.StandFarmAutoRestock=true
                local move=movement.Teleport
                function movement:Teleport(cf)
                    local result=move(self,cf)
                    if cf.X==20 then after(0.025,function() ''' + action + ''' end) end
                    return result
                end
                assert(farm:Start()); advance(10)
                assert(prompts==0 and activations==0 and not farm:IsRunning() and freezes==unfreezes)
                ''')

    def test_stock_recovery_rechecks_skin_before_roka(self):
        self.install_item_farm()
        self.run_lua('''
        removeTool("Mysterious Arrow"); stand.Value="Cream"; values.StandFarmAutoRestock=true
        addSpawn("Mysterious Arrow")
        onPrompt=function(prompt) makeTool(prompt.ObjectText); prompt.Parent.Parent=nil; skin="Late Skin" end
        assert(farm:Start()); advance(12)
        assert(prompts==1 and activations==0 and stand.Value=="Cream" and not farm:IsRunning())
        assert(farm:GetStatus().stop_reason:find("Skin detected"))
        ''')

    def test_no_parallel_restock_or_collection_while_normal_cycle_busy(self):
        self.install_item_farm()
        self.run_lua('''
        values.StandFarmEnabled=true; owner=true; removeTool("Mysterious Arrow"); addSpawn("Mysterious Arrow")
        items:_setBusyForTest(true)
        task.spawn(function() recovered=items:Restock("Mysterious Arrow",function() return owner end) end)
        after(0.1,function() duplicate=items:Restock("Mysterious Arrow",function() return owner end) end)
        advance(1); assert(prompts==0 and duplicate==false)
        items:_setBusyForTest(false); advance(3)
        assert(recovered==true and prompts==1 and freezes==unfreezes)
        ''')

    def test_normal_item_phase_collects_and_stops_without_restock_or_sales(self):
        self.install_item_farm()
        self.run_lua('''
        function config:GetSellItems() return {} end
        function config:SetMany(data) for k,v in pairs(data) do values[k]=v end end
        function inventory:ShouldStopPhase1() return false end
        function inventory:SellAll() error("unexpected sale") end
        function inventory:BuyLucky() error("unexpected purchase") end
        values.FarmEnabled=true; local model=addSpawn("Gold Coin"); items:_queueForTest(model)
        items:_skipStartupForTest()
        task.spawn(function() items:Start() end)
        after(0.8,function() items:Stop() end); advance(3)
        assert(prompts==1 and inventory:Count("Gold Coin")==1 and not items:IsRunning())
        assert(freezes==unfreezes and noclip==false and values.StandFarmEnabled==false)
        ''')

    def test_handoff_waits_for_actual_normal_cycle_to_finish(self):
        self.install_item_farm()
        self.run_lua('''
        function config:GetSellItems() return {} end
        function config:SetMany(data) for k,v in pairs(data) do values[k]=v end end
        function inventory:ShouldStopPhase1() return false end
        function inventory:SellAll() error("unexpected sale") end
        function inventory:BuyLucky() error("unexpected purchase") end
        removeTool("Mysterious Arrow"); values.FarmEnabled=true
        local gold=addSpawn("Gold Coin"); items:_queueForTest(gold); items:_skipStartupForTest()
        onPrompt=function(prompt)
            if prompt.ObjectText=="Gold Coin" then
                collectingGold=true
                after(0.05,function()
                    values.FarmEnabled=false; values.StandFarmEnabled=true; addSpawn("Mysterious Arrow")
                    task.spawn(function() restored=items:Restock("Mysterious Arrow",function() return true end) end)
                end)
                task.wait(0.3); collectingGold=false
            end
            if prompt.ObjectText=="Mysterious Arrow" then assert(not collectingGold and unfreezes==1); restockPromptAt=now end
            makeTool(prompt.ObjectText); prompt.Parent.Parent=nil
        end
        task.spawn(function() items:Start() end)
        advance(4)
        assert(restored and prompts==2 and restockPromptAt>0.65 and freezes==unfreezes)
        items:Stop(); advance(1)
        ''')

    def test_collection_error_releases_lock_freeze_and_noclip(self):
        self.install_item_farm()
        self.run_lua('''
        values.StandFarmEnabled=true; removeTool("Mysterious Arrow"); addSpawn("Mysterious Arrow")
        function movement:Teleport() error("mock move failure") end
        task.spawn(function() restored=items:Restock("Mysterious Arrow",function() return true end) end)
        advance(1); assert(restored==false and freezes==unfreezes and noclip==false)
        function movement:Teleport() return true end
        task.spawn(function() restoredAgain=items:Restock("Mysterious Arrow",function() return true end) end)
        advance(3); assert(restoredAgain and prompts==1 and freezes==unfreezes)
        ''')

    def test_ui_source_and_restock_controls_stop_and_preserve_pending_lock(self):
        targets.StandTargetTests.build_ui(self)
        self.run_lua('''
        function MakeStyledDropdown(_,label,options,fn) sourceChange=fn; return node("Source","TextButton") end
        function MakeToggle(_,label,default,fn)
            if label=="Auto Restock Consumables (BETA)" then restockChange=fn; restockDefault=default end
        end
        ''')
        source = (ROOT / 'UI.lua').read_text()
        chunk = source[source.index('    local sourceDropdown ='):source.index('    local refreshTargetList')]
        self.lua.execute(chunk)
        self.run_lua('''
        assert(restockDefault==false)
        onActivate=function() page("Option1","Pending") end
        assert(farm:Start()); advance(2)
        sourceChange("Rib Cage of The Saint's Corpse")
        assert(not farm:IsRunning() and values.StandFarmConsumable=="Rib Cage of The Saint's Corpse")
        restockChange(true); assert(values.StandFarmAutoRestock==true)
        closeGui(); assert(not farm:Start()); advance(8); assert(activations==1)
        ''')

    def test_old_config_gains_opt_in_defaults_without_resetting_settings(self):
        self.run_lua('''
        saved={StandFarmTarget="Cream",FarmEnabled=false,AutoSell=false,StandFarmMode="shiny"}
        game={GetService=function() return {JSONDecode=function() return saved end} end}
        isfile=function() return true end; readfile=function() return "mock-json" end; print=function() end
        ''')
        self.lua.globals().savedConfig = self.lua.execute((ROOT / 'Config.lua').read_text())
        self.run_lua('''
        assert(savedConfig:Load())
        assert(savedConfig:Get("StandFarmConsumable")=="Mysterious Arrow")
        assert(savedConfig:Get("StandFarmAutoRestock")==false)
        assert(savedConfig:Get("StandFarmMode")=="shiny" and savedConfig:Get("StandFarmTarget")=="Cream")
        assert(savedConfig:Get("FarmEnabled")==false and savedConfig:Get("AutoSell")==false)
        ''')
