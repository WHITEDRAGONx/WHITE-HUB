"""Simulated visible UI/input and replicated stats, NOT Roblox/Delta validation.
Run: python -m unittest discover -s tests -v (requires local-only lupa).
Luau source is parsed separately. Only `continue` is lowered for Lua 5.4.
"""
import unittest
from pathlib import Path
from lupa import LuaRuntime
from ai.autofix import check_luau

MOCK = r'''
now, jobs, events, logs, presses, activations = 0, {}, {}, {}, 0, 0
os.clock = function() return now end
function after(delay, fn) table.insert(events, {at=now+delay, fn=fn}) end
function resume(co)
    local ok, delay = coroutine.resume(co)
    if not ok then error(delay) end
    if coroutine.status(co) ~= "dead" then table.insert(jobs, {at=now+(delay or 0), co=co}) end
end
task = {spawn=function(fn) resume(coroutine.create(fn)) end,
        wait=function(delay) return coroutine.yield(delay or 0.01) end}
function advance(seconds)
    local untilTime = now + seconds
    while true do
        local at, index, source = untilTime+1, nil, nil
        for i,v in ipairs(events) do if v.at < at then at,index,source=v.at,i,events end end
        for i,v in ipairs(jobs) do if v.at < at then at,index,source=v.at,i,jobs end end
        if not index or at > untilTime then break end
        now = at
        local v = table.remove(source,index)
        if v.fn then v.fn() else resume(v.co) end
    end
    now=untilTime
end
function node(name, class, parent)
    local n = {Name=name, class=class, Parent=parent, children={}, Visible=true, Enabled=true,
               AbsolutePosition={X=10,Y=10}, AbsoluteSize={X=100,Y=30}, Text=name}
    if parent then table.insert(parent.children,n) end
    function n:IsA(c)
        return c==self.class or c=="GuiButton" and (self.class=="TextButton" or self.class=="ImageButton")
            or c=="GuiObject" and (self.class=="Frame" or self.class=="TextButton" or self.class=="TextLabel" or self.class=="ImageButton")
    end
    function n:IsDescendantOf(p) local a=self.Parent while a do if a==p then return true end a=a.Parent end return false end
    function n:GetDescendants()
        local out={} for _,c in ipairs(self.children) do table.insert(out,c) for _,d in ipairs(c:GetDescendants()) do table.insert(out,d) end end return out
    end
    function n:FindFirstChild(name, recursive)
        for _,c in ipairs(self.children) do if c.Name==name then return c end end
        if recursive then for _,c in ipairs(self:GetDescendants()) do if c.Name==name then return c end end end
    end
    function n:FindFirstChildWhichIsA(c, recursive)
        local list=recursive and self:GetDescendants() or self.children
        for _,o in ipairs(list) do if o:IsA(c) then return o end end
    end
    n.FindFirstChildOfClass=n.FindFirstChildWhichIsA
    return n
end
player=node("Player","Player")
pg=node("PlayerGui","PlayerGui",player)
stats=node("PlayerStats","Folder",player)
stand=node("Stand","StringValue",stats); stand.Value="None"
pity=node("PityCount","NumberValue",stats); pity.Value=0
bag=node("Backpack","Backpack",player)
char=node("Character","Model"); player.Character=char
hum=node("Humanoid","Humanoid",char); hum.Health=100
root=node("HumanoidRootPart","Part",char)
function hum:EquipTool(tool) end
remote=node("RemoteFunction","RemoteFunction",char)
skin="None"
worthRequests, safeMoves = 0, 0
function remote:InvokeServer(action)
    if action=="LearnSkill" then worthRequests=worthRequests+1; return true end
    return skin
end
CFrame={new=function(x,y,z) return {X=x,Y=y,Z=z} end}
movement={SetNoclip=function() end,ClearFocus=function() end,FixCamera=function() end,
    Teleport=function(_,cf) safeMoves=safeMoves+1; movedCharacter=player.Character; return true end}
function respawn(delay,readyDelay)
    local previous=player.Character
    after(delay or 0.5,function()
        hum.Health=0
        char=node("Character","Model"); player.Character=char
        hum=node("Humanoid","Humanoid",char); hum.Health=100
        function hum:EquipTool(tool) end
        after(readyDelay or 0,function()
            root=node("HumanoidRootPart","Part",char)
            remote=node("RemoteFunction","RemoteFunction",char)
            function remote:InvokeServer(action)
                if action=="LearnSkill" then worthRequests=worthRequests+1; return true end
                return skin
            end
        end)
    end)
end
function closeGui() pg.children={} end
function page(kind, text, hidden)
    closeGui()
    local gui=node("DialogueGui","ScreenGui",pg)
    local frame=node("Frame","Frame",gui)
    node("Message","TextLabel",frame).Text=text
    local parent=frame
    if kind=="Option1" or kind=="Option2" then
        local options=node("Options","Frame",frame)
        parent=node(kind,"Frame",options)
        parent.Visible=not hidden
    end
    local b=node(kind,"TextButton",parent)
    return b,gui
end
-- Update pages within the SAME GUI, as the observed YBA dialogue does.
function nextPage(kind,text,hidden)
    local gui=pg.children[1]
    local b,new=page(kind,text,hidden)
    gui.children=new.children
    for _,c in ipairs(gui.children) do c.Parent=gui end
    pg.children={gui}
    return b,gui
end
function makeTool(name)
    local tool=node(name,"Tool",bag)
    function tool:Activate() activations=activations+1; if onActivate then onActivate(name) end end
end
makeTool("Mysterious Arrow"); makeTool("Rokakaka")
local vim={}
function vim:SendMouseButtonEvent(x,y,button,down)
    if down then presses=presses+1; if onClick then onClick() end end
end
game={GetService=function(_,name)
    if name=="Players" then return {LocalPlayer=player} end
    if name=="VirtualInputManager" then return vim end
end}
values={StandFarmTarget="Aerosmith",StandFarmEnabled=false,StandFarmPityLimit=20}
config={Get=function(_,k) return values[k] end,Set=function(_,k,v) values[k]=v end}
logger={Write=function(_,level,module,msg) table.insert(logs,level..":"..msg) end}
'''

class StandDialogueTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(MOCK)
        source = (Path(__file__).resolve().parents[1] / 'StandFarm.lua').read_text()
        self.assertTrue(check_luau(source))
        source = source.replace('            continue\n', '            goto next_iteration\n')
        source = source.replace('    end\n    if runToken == token then',
                                '        ::next_iteration::\n    end\n    if runToken == token then')
        self.lua.globals().farm = self.lua.execute(source)
        self.lua.execute('farm:Init({Config=config,RuntimeLog=logger,Movement=movement})')

    def run_lua(self, code):
        self.lua.execute(code)

    def test_multipage_arrow_and_continue_confirm_stat(self):
        self.run_lua('''
        stage=0
        onActivate=function() page("Option1","Use arrow?") end
        onClick=function()
            stage=stage+1
            if stage==1 then nextPage("ClickContinue","Continue using arrow")
            elseif stage==2 then nextPage("Option1","Confirm use")
            else stand.Value="Aerosmith"; closeGui() end
        end
        assert(farm:Start()); advance(8)
        assert(activations==1 and presses==3 and farm:GetStatus().rolls==1)
        assert(not farm:IsRunning() and farm:GetStatus().stand=="Aerosmith")
        ''')

    def test_roka_then_arrow_sequential(self):
        self.run_lua('''
        stand.Value="Star Platinum"
        onActivate=function(name) item=name; page("Option1",name) end
        onClick=function() stand.Value=item=="Rokakaka" and "None" or "Aerosmith"; closeGui(); if item=="Rokakaka" then respawn() end end
        assert(farm:Start()); advance(10)
        assert(activations==2 and presses==2 and farm:GetStatus().rolls==1)
        ''')

    def test_hidden_ancestor_not_clicked_and_timeout_locks_restart(self):
        self.run_lua('''
        onActivate=function() page("Option1","Hidden",true) end
        assert(farm:Start()); advance(25)
        assert(presses==0 and activations==1 and not farm:IsRunning())
        closeGui(); assert(not farm:Start()); advance(25); assert(activations==1)
        ''')

    def test_unchanged_page_bounded_to_two_inputs(self):
        self.run_lua('''
        onActivate=function() page("Option1","Stuck") end
        assert(farm:Start()); advance(8)
        assert(presses==2 and activations==1 and not farm:IsRunning())
        assert(farm:GetStatus().rolls==0)
        ''')

    def test_stop_no_late_logs_or_inputs_pending_result_locked(self):
        self.run_lua('''
        onActivate=function() page("Option1","Confirm") end
        assert(farm:Start()); advance(2); farm:Stop()
        local count, inputCount=#logs, presses; advance(30)
        assert(#logs==count and presses==inputCount and activations==1)
        closeGui(); assert(not farm:Start())
        ''')

    def test_stop_before_activation(self):
        self.run_lua('''
        assert(farm:Start()); farm:Stop(); local count=#logs; advance(25)
        assert(activations==0 and presses==0 and #logs==count)
        ''')

    def test_existing_dialogue_refused(self):
        self.run_lua('page("Option1","Merchant"); assert(not farm:Start()); advance(30); assert(activations==0 and presses==0)')

    def test_result_delayed_no_second_activation(self):
        self.run_lua('''
        onActivate=function() page("Option1","Use") end
        onClick=function() closeGui(); after(8,function() stand.Value="Aerosmith" end) end
        assert(farm:Start()); advance(6); assert(activations==1 and farm:GetStatus().rolls==0)
        advance(10); assert(activations==1 and farm:GetStatus().rolls==1)
        ''')

    def test_skin_unknown_and_skin_present_preserved(self):
        self.run_lua('''
        stand.Value="Star Platinum"; skin="Rare Skin"
        resume(coroutine.create(function() assert(not farm:Start()) end)); advance(1)
        assert(activations==0)
        skin=""; resume(coroutine.create(function() assert(not farm:Start()) end)); advance(1)
        assert(activations==0)
        skin=nil; resume(coroutine.create(function() assert(not farm:Start()) end)); advance(1)
        assert(activations==0)
        ''')

    def test_unknown_option_not_skipped(self):
        self.run_lua('''
        onActivate=function() local _,gui=page("Option2","Unknown"); node("ClickContinue","TextButton",gui) end
        assert(farm:Start()); advance(25); assert(presses==0 and activations==1)
        ''')

    def test_pity_and_other_modes_prevent_consumption(self):
        self.run_lua('''
        pity.Value=20; assert(farm:Start()); advance(1); assert(activations==0)
        pity.Value=0; values.AutoSell=true; assert(not farm:Start()); assert(activations==0)
        ''')

    def test_mode_enabled_during_dialogue_cancels(self):
        self.run_lua('''
        onActivate=function() page("Option1","Use") end
        assert(farm:Start()); advance(2); local inputCount=presses; values.QuestFarmEnabled=true; advance(10)
        assert(presses==inputCount and activations==1 and not farm:IsRunning())
        ''')

    def test_skin_read_timeout_preserves_stand(self):
        self.run_lua('''
        stand.Value="Star Platinum"
        function remote:InvokeServer() task.wait(10); return "None" end
        resume(coroutine.create(function() assert(not farm:Start()) end)); advance(4)
        assert(activations==0); advance(12); assert(activations==0)
        ''')

    def test_stand_change_during_skin_read_preserved(self):
        self.run_lua('''
        stand.Value="Star Platinum"
        function remote:InvokeServer() task.wait(1); stand.Value="Other"; return "None" end
        resume(coroutine.create(function() assert(not farm:Start()) end)); advance(3)
        assert(activations==0)
        ''')

    def test_stop_during_skin_read_no_late_logs(self):
        self.run_lua('''
        stand.Value="Star Platinum"
        calls=0
        function remote:InvokeServer() calls=calls+1; if calls>1 then task.wait(2) end return "None" end
        resume(coroutine.create(function() farm:Start() end)); advance(0.4)
        farm:Stop(); local count=#logs; advance(8)
        assert(#logs==count and activations==0)
        ''')

    def test_result_with_open_gui_does_not_click_again(self):
        self.run_lua('''
        onActivate=function() page("Option1","Use") end
        onClick=function() stand.Value="Aerosmith" end
        assert(farm:Start()); advance(25)
        assert(presses==1 and activations==1 and farm:GetStatus().rolls==0)
        ''')

    def test_pity_changes_while_equipping_no_consumption(self):
        self.run_lua('''
        assert(farm:Start()); after(0.1,function() pity.Value=20 end); advance(3)
        assert(activations==0)
        ''')

    def enable_fast(self):
        self.run_lua(r'''
        ups, signals, mutations, signalCalls = {}, {}, {}, 0
        typeof=function(v) return type(v)=="table" and v.class and "Instance" or type(v) end
        getconnections=function(signal) return signals[signal] or {} end
        getupvalue=function(fn,index) return ups[fn] and ups[fn][index] end
        setupvalue=function(fn,index,value)
            table.insert(mutations,{fn=fn,index=index,value=value})
            ups[fn][index]=value
            if index==1 and value=="Option1" and onSelect then
                after(selectDelay or 0.05,function()
                    if ups[fn][1]=="Option1" then ups[fn][1]=""; onSelect() end
                end)
            end
        end
        function fastPage(kind,text,initial)
            local b,gui
            if initial then b,gui=page(kind,text) else b,gui=nextPage(kind,text) end
            b.MouseButton1Click={}
            local fn=function() signalCalls=signalCalls+1; if onSignal then onSignal(kind) end end
            ups[fn]={[1]="",[2]=b.Parent}
            signals[b.MouseButton1Click]={{Function=fn,Fire=function() fn() end}}
            lastFn,lastButton=fn,b
            return b,gui
        end
        ''')

    def test_fast_option_continue_without_virtual_mouse(self):
        self.enable_fast()
        self.run_lua('''
        selected=0
        onActivate=function() fastPage("Option1","Use?",true) end
        onSelect=function()
            selected=selected+1
            if selected==1 then fastPage("ClickContinue","Continue")
            else stand.Value="Aerosmith"; closeGui() end
        end
        onSignal=function(kind) assert(kind=="ClickContinue"); fastPage("Option1","Confirm") end
        assert(farm:Start()); advance(8)
        assert(presses==0 and selected==2 and signalCalls==1 and activations==1)
        assert(farm:GetStatus().rolls==1)
        ''')

    def test_fast_roka_then_arrow(self):
        self.enable_fast()
        self.run_lua('''
        stand.Value="Star Platinum"
        onActivate=function(name) item=name; fastPage("Option1",name,true) end
        onSelect=function() stand.Value=item=="Rokakaka" and "None" or "Aerosmith"; closeGui(); if item=="Rokakaka" then respawn() end end
        assert(farm:Start()); advance(8)
        assert(presses==0 and activations==2 and farm:GetStatus().rolls==1)
        ''')

    def test_fast_stop_restores_gui_and_selection(self):
        self.enable_fast()
        self.run_lua('''
        selectDelay=1
        onActivate=function() fastPage("Option1","Use?",true) end
        onSelect=function() error("selection should be cancelled") end
        assert(farm:Start()); advance(2.4)
        local gui=pg.children[1]; assert(not gui.Enabled and ups[lastFn][1]=="Option1")
        farm:Stop(); assert(gui.Enabled and ups[lastFn][1]=="")
        local count=#logs; advance(10); assert(#logs==count and activations==1 and signalCalls==0)
        ''')

    def test_mismatched_callback_never_modified(self):
        self.enable_fast()
        self.run_lua('''
        onActivate=function() fastPage("Option1","Use?",true); ups[lastFn][2]=node("Other","Frame") end
        onSignal=function() stand.Value="Aerosmith"; closeGui() end
        assert(farm:Start()); advance(6)
        assert(#mutations==0 and presses==0 and signalCalls==1 and farm:GetStatus().rolls==1)
        ''')

    def test_standard_debug_upvalue_return_shape(self):
        self.enable_fast()
        self.run_lua('''
        getupvalue=function(fn,index) return "upvalue"..index, ups[fn][index] end
        onActivate=function() fastPage("Option1","Use?",true) end
        onSelect=function() stand.Value="Aerosmith"; closeGui() end
        assert(farm:Start()); advance(6); assert(presses==0 and farm:GetStatus().rolls==1)
        ''')

    def test_pending_callback_never_overlaps_or_logs_after_stop(self):
        self.enable_fast()
        self.run_lua('''
        onActivate=function() fastPage("ClickContinue","Continue",true) end
        onSignal=function() task.wait(30) end
        assert(farm:Start()); advance(2.4); local gui=pg.children[1]
        assert(not gui.Enabled and signalCalls==1)
        farm:Stop(); assert(gui.Enabled); local count=#logs
        advance(25); assert(signalCalls==1 and #logs==count and not farm:Start())
        advance(10); assert(signalCalls==1 and #logs==count and activations==1)
        ''')

    def test_stalled_fast_selection_restored_on_failure(self):
        self.enable_fast()
        self.run_lua('''
        onActivate=function() fastPage("Option1","Stuck",true) end
        assert(farm:Start()); advance(8)
        assert(not farm:IsRunning() and pg.children[1].Enabled and ups[lastFn][1]=="")
        assert(signalCalls==1 and activations==1 and presses==0)
        ''')

    def test_no_fast_api_uses_bound_signal_before_mouse(self):
        self.enable_fast()
        self.run_lua('''
        setupvalue=nil
        onActivate=function() fastPage("Option1","Use?",true) end
        onSignal=function() stand.Value="Aerosmith"; closeGui() end
        assert(farm:Start()); advance(6)
        assert(#mutations==0 and signalCalls==1 and presses==0 and farm:GetStatus().rolls==1)
        ''')

    def test_hidden_continue_fast_skips_animated_text(self):
        self.enable_fast()
        self.run_lua('''
        onActivate=function()
            fastPage("ClickContinue","Animated text",true); lastButton.Visible=false
            for i=1,30 do after(i*0.1,function()
                local gui=pg.children[1]
                if gui then gui:FindFirstChild("Message",true).Text=tostring(now) end
            end) end
        end
        onSignal=function() stand.Value="Aerosmith"; closeGui() end
        assert(farm:Start()); advance(4)
        assert(signalCalls==1 and presses==0 and farm:GetStatus().rolls==1)
        ''')

    def test_yielded_continue_released_by_fast_option(self):
        self.enable_fast()
        self.run_lua('''
        onActivate=function() fastPage("ClickContinue","Intro",true) end
        onSignal=function()
            fastPage("Option1","Choose")
            local fn=lastFn
            while ups[fn][1]~="Option1" do task.wait(0.1) end
            stand.Value="Aerosmith"; closeGui()
        end
        assert(farm:Start()); advance(8)
        assert(signalCalls==1 and presses==0 and farm:GetStatus().rolls==1)
        ''')

    def test_roka_waits_for_new_root_and_remote_before_arrow(self):
        self.enable_fast()
        self.run_lua('''
        stand.Value="Cream"
        onActivate=function(name) item=name; fastPage("Option1",name,true) end
        onSelect=function()
            if item=="Rokakaka" then stand.Value="None"; closeGui(); respawn(4,2)
            else stand.Value="Aerosmith"; closeGui() end
        end
        assert(farm:Start()); advance(6)
        assert(activations==1 and worthRequests==0 and safeMoves==1)
        advance(2); assert(activations==1 and worthRequests==0)
        advance(10)
        assert(activations==2 and safeMoves==2 and movedCharacter==player.Character)
        assert(worthRequests==1 and farm:GetStatus().rolls==1)
        ''')

    def test_three_rolls_across_two_roka_respawns(self):
        self.enable_fast()
        self.run_lua('''
        arrows=0
        onActivate=function(name) item=name; fastPage("Option1",name,true) end
        onSelect=function()
            if item=="Rokakaka" then stand.Value="None"; closeGui(); respawn(1,0.5)
            else arrows=arrows+1; stand.Value=arrows==3 and "Aerosmith" or "Cream"; closeGui() end
        end
        assert(farm:Start()); advance(35)
        assert(arrows==3 and activations==5 and farm:GetStatus().rolls==3)
        assert(safeMoves==3 and worthRequests==3 and not farm:IsRunning())
        ''')

    def test_stop_during_respawn_no_new_move_skill_or_item(self):
        self.enable_fast()
        self.run_lua('''
        stand.Value="Cream"
        onActivate=function(name) fastPage("Option1",name,true) end
        onSelect=function() stand.Value="None"; closeGui(); respawn(10,1) end
        assert(farm:Start()); advance(4); farm:Stop()
        local count, moves=#logs,safeMoves
        advance(30)
        assert(#logs==count and safeMoves==moves and activations==1 and worthRequests==0)
        ''')

    def test_worthiness_timeout_never_activates_arrow(self):
        self.run_lua('''
        function remote:InvokeServer(action)
            if action=="LearnSkill" then task.wait(12); return true end
            return "None"
        end
        assert(farm:Start()); advance(8)
        assert(activations==0 and not farm:IsRunning() and not farm:Start())
        local count=#logs; advance(20); assert(#logs==count and activations==0)
        ''')

    def test_stop_during_worthiness_no_late_activation(self):
        self.run_lua('''
        function remote:InvokeServer(action) task.wait(4); return true end
        assert(farm:Start()); advance(2); farm:Stop()
        local count=#logs; advance(10); assert(#logs==count and activations==0)
        ''')

    def test_failed_safe_spot_teleport_prevents_consumption(self):
        self.run_lua('''
        movement.Teleport=function() return false end
        assert(farm:Start()); advance(5)
        assert(not farm:IsRunning() and activations==0 and worthRequests==0)
        ''')

    def test_roka_none_without_replacement_times_out_no_arrow(self):
        self.enable_fast()
        self.run_lua('''
        stand.Value="Cream"
        onActivate=function(name) fastPage("Option1",name,true) end
        onSelect=function() stand.Value="None"; closeGui() end
        assert(farm:Start()); advance(30)
        assert(not farm:IsRunning() and activations==1 and worthRequests==0)
        ''')

if __name__ == '__main__':
    unittest.main()
