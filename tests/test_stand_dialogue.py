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
function hum:EquipTool(tool) end
remote=node("RemoteFunction","RemoteFunction",char)
skin="None"
function remote:InvokeServer() return skin end
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
        self.lua.execute('farm:Init({Config=config,RuntimeLog=logger})')

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
        onClick=function() stand.Value=item=="Rokakaka" and "None" or "Aerosmith"; closeGui() end
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
        assert(farm:Start()); advance(0.4); farm:Stop()
        local count=#logs; advance(30)
        assert(#logs==count and presses==0 and activations==1)
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
        assert(farm:Start()); advance(0.4); values.QuestFarmEnabled=true; advance(10)
        assert(presses==0 and activations==1 and not farm:IsRunning())
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

if __name__ == '__main__':
    unittest.main()
