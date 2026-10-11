"""Actual source helper/driver simulations; no Roblox or Delta benchmark."""
import unittest
from pathlib import Path

from lupa import LuaRuntime
from ai.autofix import check_luau
from test_stand_dialogue import MOCK

ROOT = Path(__file__).resolve().parents[1]


class MerchantLookupTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(MOCK + '\nPlayer=player; player.PlayerGui=pg; function pg:GetChildren() return self.children end\n')
        source = (ROOT / 'Inventory.lua').read_text()
        self.assertTrue(check_luau(source))
        chunk = source[source.index('local function normalizeText('):source.index('local function describeButtons(')]
        chunk += source[source.index('local function optionNameForButton('):source.index('local function getMouseClickCallback(')]
        self.lua.execute(chunk + '''
        lookup=getVisibleDialogueButtons; signature=getDialogueStateSignature
        findOption=findDialogueButtonByOptionName
        ''')

    def test_internal_lookup_skips_unrelated_ui_and_hidden_templates(self):
        self.lua.execute('''
        local b,gui=page("Option1","Merchant")
        b.Text="Sell one"
        local opts=gui:FindFirstChild("Options",true)
        local o6=node("Option6","Frame",opts); node("Sell","TextButton",o6).Text="Sell all"
        local hidden=node("Option2","Frame",opts); hidden.Visible=false
        node("Template","TextButton",hidden).Text="Hidden"
        local continue=node("ClickContinue","TextButton",gui); continue.Text="Continue"
        for i=1,500 do node("Body"..i,"TextLabel",gui) end
        function gui:GetDescendants() error("internal lookup must not scan whole GUI") end
        local sig,buttons=signature()
        assert(#buttons==2 and sig:find("Option1=Sell one",1,true) and sig:find("Option6=Sell all",1,true))
        assert(findOption("Option1")==b and not findOption("Option2"))
        gui.Enabled=false; assert(#lookup(true)==2)
        ''')

    def test_adaptive_lookup_keeps_buttons_outside_options(self):
        self.lua.execute('''
        local b,gui=page("Option1","Merchant"); b.Text="Sell"
        node("ClickContinue","TextButton",gui).Text="Continue"
        assert(#lookup()==2 and #lookup(true)==1)
        ''')

    def test_renamed_layout_retains_broad_fallback(self):
        self.lua.execute('''
        local b,gui=page("Option1","Merchant"); b.Text="Sell"
        gui:FindFirstChild("Options",true).Name="Choices"
        assert(#lookup(true)==1 and findOption("Option1")==b)
        ''')

    def test_image_button_text_and_empty_buttons(self):
        self.lua.execute('''
        local b=page("Option1","Merchant"); b.class="ImageButton"
        node("Label","TextLabel",b).Text="Sell all"
        local buttons=lookup(true); assert(#buttons==1 and buttons[1].Normalized=="sell all")
        b.children={}; assert(#lookup(true)==0)
        closeGui(); assert(#lookup(true)==0 and signature()=="")
        ''')


class QuestPageTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(MOCK + '''
        Player=player; playerGui=pg; tick=os.clock; alive=true; inputTimes={}; continues=0
        isTokenActive=function() return alive end
        hideDialogue=function(gui) gui.Enabled=false end
        dialogueGone=function(gui) return pg:FindFirstChild("DialogueGui")~=gui end
        findDialogueOption=function()
            local option=pg:FindFirstChild("Option1",true)
            return option and (option:IsA("GuiButton") and option or option:FindFirstChildWhichIsA("GuiButton",true))
        end
        dialogueStageSignature=function() local b=findDialogueOption(); return b and b.Text end
        injectDialogueOption=function()
            table.insert(inputTimes,now)
            if onQuestInput then onQuestInput() end
            return true
        end
        clickDialogueButton=function() error("unexpected physical fallback") end
        fireContinueButton=function() continues=continues+1; return false end
        ''')
        source = (ROOT / 'CombatFarm.lua').read_text()
        self.assertTrue(check_luau(source))
        chunk = source[source.index('    local function processExistingDialogue('):source.index('    -- Clear only a stale QUEST dialogue.')]
        chunk = chunk.replace('                    continue\n', '                    goto next_dialogue_poll\n')
        chunk = chunk.replace('        end\n\n        if type(isComplete)', '            ::next_dialogue_poll::\n        end\n\n        if type(isComplete)', 1)
        self.lua.globals().process = self.lua.execute(chunk + '\nreturn processExistingDialogue')

    def test_new_option_page_does_not_wait_old_page_cooldown(self):
        self.lua.execute('''
        local b,gui=page("Option1","Quest"); b.Text="Accept"
        onQuestInput=function()
            if #inputTimes==1 then b.Text="Confirm" else closeGui() end
        end
        resume(coroutine.create(function() ok=process(gui,1) end)); advance(1)
        assert(ok and #inputTimes==2 and inputTimes[2]-inputTimes[1]<0.1)
        assert(continues==0)
        ''')

    def test_unchanged_option_page_keeps_retry_cooldown(self):
        self.lua.execute('''
        local b,gui=page("Option1","Quest"); b.Text="Stuck"
        clickDialogueButton=function() table.insert(inputTimes,now); return true end
        resume(coroutine.create(function() ok=process(gui,0.29) end)); advance(1)
        assert(not ok and #inputTimes==4 and continues==0)
        for i=2,#inputTimes do assert(inputTimes[i]-inputTimes[i-1]>=0.1) end
        ''')

    def test_stop_prevents_later_input(self):
        self.lua.execute('''
        local b,gui=page("Option1","Quest"); b.Text="Accept"
        onQuestInput=function() alive=false end
        resume(coroutine.create(function() ok=process(gui,1) end)); advance(2)
        assert(not ok and #inputTimes==1 and continues==0)
        ''')

    def test_completion_requires_quest_state_when_predicate_supplied(self):
        self.lua.execute('''
        local b,gui=page("Option1","Quest"); b.Text="Accept"
        local confirmed=false
        isComplete=function() return confirmed end
        onQuestInput=function() closeGui(); after(0.4,function() confirmed=true end) end
        resume(coroutine.create(function() ok=process(gui,1) end)); advance(0.2)
        assert(not ok and #inputTimes==1)
        advance(1); assert(ok and confirmed and #inputTimes==1)
        ''')


class MerchantFinalRouteTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(MOCK + '''
        tick=os.clock; Player=player; count=3; selections={}; restored=0; closed=0
        hasFinalZeroDelaySupport=function() return true end
        Inventory={Count=function() return count end}
        equipSellTool=function() return {Parent=char} end
        closeDialogueIfOpen=function() closed=closed+1 end
        restoreDialogueRendering=function() end
        newFinalState=function() return {signalFires=0,direct1982Calls=0,richObjects=0,constantsZeroed=0,gcScans=0,gcSeconds=0} end
        installFastDialogueWait=function() end
        fireproximityprompt=function() end
        waitForDialogueGuiHidden=function() return true end
        waitForFinalStage=function() return {},"stage"..(#selections+1),1 end
        injectDialogueOption=function(option)
            table.insert(selections,option)
            if failAt==#selections then return false,"mock failure" end
            if option=="Option6" and not noResult then after(0.1,function() count=1 end) end
            return true
        end
        restoreFinalState=function() restored=restored+1 end
        moduleLog=function(level,msg) table.insert(logs,msg) end
        ''')
        source = (ROOT / 'Inventory.lua').read_text()
        chunk = source[source.index('local function tryFinalMerchantSell('):source.index('-- Original internal state route retained')]
        self.lua.globals().sell = self.lua.execute(chunk + '\nreturn tryFinalMerchantSell')

    def test_final_keeps_sequence_and_inventory_confirmation(self):
        self.lua.execute('''
        resume(coroutine.create(function() ok,sold=sell("Gold Coin",{}) end)); advance(2)
        assert(ok and sold==2 and count==1 and restored==1)
        assert(table.concat(selections,",")=="Option1,Option1,Option6")
        assert(closed==2 and logs[#logs]:find("gcTime=",1,true))
        ''')

    def test_dialogue_without_inventory_result_is_not_success(self):
        self.lua.execute('''
        noResult=true
        resume(coroutine.create(function() ok,sold=sell("Gold Coin",{}) end)); advance(2)
        assert(not ok and sold==0 and count==3 and restored==1 and closed==2)
        ''')

    def test_failure_restores_state_before_return(self):
        self.lua.execute('''
        failAt=2
        resume(coroutine.create(function() ok,sold=sell("Gold Coin",{}) end)); advance(2)
        assert(not ok and sold==0 and restored==1 and #selections==2 and closed==2)
        ''')


if __name__ == '__main__':
    unittest.main()
