"""Actual Lua target matching/UI callbacks in mocks; no Delta/YBA claim."""
import unittest
from pathlib import Path
import test_stand_dialogue as dialogue


class StandTargetTests(unittest.TestCase):
    setUp = dialogue.StandDialogueTests.setUp
    run_lua = dialogue.StandDialogueTests.run_lua

    def test_second_target_obtained_stops_before_roka(self):
        self.run_lua('''
        values.StandFarmTargets={"Star Platinum","Aerosmith"}
        onActivate=function() page("Option1","Use arrow?") end
        onClick=function() stand.Value="Aerosmith"; closeGui() end
        assert(farm:Start()); advance(8)
        assert(activations==1 and farm:GetStatus().rolls==1 and not farm:IsRunning())
        assert(farm:GetStatus().stop_reason=="Desired Stand found: Aerosmith")
        ''')

    def test_owned_list_target_preserved_without_skin_lookup(self):
        self.run_lua('''
        values.StandFarmTargets={"Cream","Aerosmith"}; stand.Value="Cream"; skin=nil
        local ok,reason=farm:Start(); assert(not ok and reason=="Desired Stand found: Cream")
        advance(5); assert(activations==0)
        ''')

    def test_list_overrides_legacy_single_and_skin_still_protected(self):
        self.run_lua('''
        values.StandFarmTargets={"Cream"}; stand.Value="Aerosmith"; skin="Rare Skin"
        local ok,reason=farm:Start(); assert(not ok and reason:find("Skin detected"))
        advance(5); assert(activations==0)
        ''')

    def test_snapshot_and_public_status_cannot_change_targets(self):
        self.run_lua('''
        values.StandFarmTargets={"Aerosmith","Cream","Aerosmith"}
        onActivate=function() page("Option1","Use arrow?") end
        onClick=function() stand.Value="Cream"; closeGui() end
        assert(farm:Start())
        values.StandFarmTargets[2]="Star Platinum"
        local state=farm:GetStatus(); assert(#state.targets==2); state.targets[2]="Whitesnake"
        advance(8)
        assert(activations==1 and farm:GetStatus().stop_reason=="Desired Stand found: Cream")
        ''')

    def test_invalid_or_oversized_lists_never_consume(self):
        self.run_lua('''
        for _,list in ipairs({"bad", {false}, {"None"}, {""}, {name="Aerosmith"}, {[2]="Cream"}}) do
            values.StandFarmTargets=list; assert(not farm:Start())
        end
        values.StandFarmTargets={}
        for i=1,26 do values.StandFarmTargets[i]="Cream" end
        assert(not farm:Start()); advance(10); assert(activations==0)
        ''')

    def test_empty_list_keeps_single_mode(self):
        self.run_lua('''
        values.StandFarmTargets={}; stand.Value="Aerosmith"
        local ok,reason=farm:Start(); assert(not ok and reason=="Desired Stand found: Aerosmith")
        assert(activations==0)
        ''')

    def test_config_upgrade_keeps_existing_settings_and_persisted_list(self):
        self.run_lua('''
        saved={StandFarmTarget="Cream",AutoSell=false,StandFarmPityLimit=9,
            SellItems={Rokakaka=false},StandFarmTargets={"Cream","Aerosmith"}}
        game={GetService=function() return {JSONDecode=function() return saved end,
            JSONEncode=function(_,data) written=data; return "mock-json" end} end}
        isfile=function() return true end; readfile=function() return "mock-json" end
        writefile=function() end; print=function() end
        ''')
        source = (Path(__file__).resolve().parents[1] / 'Config.lua').read_text()
        self.lua.globals().persisted_config = self.lua.execute(source)
        self.run_lua('''
        assert(persisted_config:Load())
        assert(persisted_config:Get("StandFarmTargets")[2]=="Aerosmith")
        assert(persisted_config:Get("StandFarmTarget")=="Cream")
        assert(persisted_config:Get("AutoSell")==false and persisted_config:GetSellItem("Rokakaka")==false)
        assert(persisted_config:Get("StandFarmPityLimit")==9)
        persisted_config:Set("StandFarmTargets",{"Whitesnake"})
        assert(written.StandFarmTargets[1]=="Whitesnake" and written.AutoSell==false)
        ''')

    def build_ui(self):
        self.run_lua('''
        table.find=function(t,x) for i,v in ipairs(t) do if v==x then return i end end end
        UDim2={new=function() return {} end}; Enum={AutomaticSize={Y="Y"},Font={GothamBold="Bold"}}
        THEME={PANEL2="panel",WHITE="white"}
        buttons,labels={},{}
        Instance={new=function(class,parent)
            local n=node(class,class,parent)
            n.MouseButton1Click={Connect=function(_,fn) n.click=fn; return {} end}
            n.FocusLost={Connect=function(_,fn) n.blur=fn; return {} end}
            table.insert(buttons,n); return n
        end}
        FarmPage=node("Farm","Frame"); _config=config; _standFarm=farm
        UI={AddLabel=function(_,parent,text) local n=node("Label","TextLabel",parent); n.Text=text; table.insert(labels,n); return n end,
            SetToggleValue=function(_,label,value) toggleValue=value end,
            ShowPopup=function(_,msg) popup=msg end}
        function MakeStyledDropdown(parent,label,names,fn)
            local n=node("Dropdown","TextButton",parent)
            selectStand=function(name) n.Text=name; fn(name) end
            return n
        end
        function styleActionButton() end
        function trackConnection(x) return x end
        ''')
        source = (Path(__file__).resolve().parents[1] / 'UI.lua').read_text()
        fragment = source[source.index('    local availableStands = {'):source.index('    local pityInput =')]
        self.lua.execute(fragment)

    def test_ui_add_remove_clear_list_and_label(self):
        self.build_ui()
        self.run_lua('''
        buttons[1].click(); assert(values.StandFarmTargets[1]=="Aerosmith")
        selectStand("Cream"); buttons[1].click()
        assert(#values.StandFarmTargets==2 and labels[1].Text:find("Cream"))
        assert(buttons[1].Text=="REMOVE SELECTED STAND FROM LIST")
        buttons[1].click(); assert(#values.StandFarmTargets==1)
        buttons[2].click(); assert(#values.StandFarmTargets==0 and values.StandFarmTarget=="Cream")
        assert(labels[1].Text:find("Single target"))
        ''')

    def test_ui_edit_stops_pending_run_without_extra_consumption(self):
        self.build_ui()
        self.run_lua('''
        onActivate=function() page("Option1","Pending") end
        assert(farm:Start()); advance(2)
        buttons[1].click(); assert(not farm:IsRunning() and toggleValue==false)
        local inputs=presses; advance(30)
        assert(activations==1 and presses==inputs)
        closeGui(); assert(not farm:Start())
        ''')
