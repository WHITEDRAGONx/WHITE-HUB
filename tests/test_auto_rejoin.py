"""Roblox prompt lifecycle simulation; not proof of post-kick native teleport."""
import unittest
from pathlib import Path
from lupa import LuaRuntime
from ai.autofix import check_luau
from test_stand_dialogue import MOCK

ROOT = Path(__file__).resolve().parents[1]


class AutoRejoinTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(MOCK+'''
            tick=os.clock; warn=function() end; print=function() end
            core=node("CoreGui","Folder"); rejoins=0; disconnected=0
            core.DescendantAdded={Connect=function(_,fn)
                deliver=fn
                return {Disconnect=function() if deliver==fn then deliver=nil end; disconnected=disconnected+1 end}
            end}
            tele={Teleport=function(_,place,who)
                rejoins=rejoins+1; assert(place==123 and who==player)
                if rejoinDelay then task.wait(rejoinDelay) end
                if rejoinFails then error("mock native teleport failure") end
            end}
            local original=game.GetService
            game.PlaceId=123
            game.GetService=function(self,name)
                if name=="CoreGui" then return core end
                if name=="TeleportService" then return tele end
                if name=="HttpService" then return {JSONEncode=function() return "{}" end} end
                return original(self,name)
            end
            function errorWindow(text,delay)
                local root=node("ErrorPrompt","Frame",core)
                if deliver then deliver(root) end
                if delay then after(delay,function() node("ErrorMessage","TextLabel",root).Text=text end)
                else node("ErrorMessage","TextLabel",root).Text=text end
                return root
            end
        ''')
        source=(ROOT/'ServerHop.lua').read_text()
        self.assertTrue(check_luau(source))
        self.lua.globals().hop=self.lua.execute(source)
        self.lua.execute('hop:Init({Config=config,Movement=movement,RuntimeLog=logger})')

    def run_lua(self,code):
        self.lua.execute(code)

    def test_delayed_error_message_is_detected_once(self):
        self.run_lua('''
            root=errorWindow("Kicked by experience",0.3)
            deliver(root); advance(3)
            assert(rejoins==1); deliver(root); errorWindow("Another error"); advance(8)
            assert(rejoins==1)
        ''')

    def test_existing_prompt_on_reload_is_detected(self):
        self.run_lua('''
            deliver=nil; root=errorWindow("Disconnected")
            hop:Init({Config=config,Movement=movement,RuntimeLog=logger}); advance(3)
            assert(rejoins==1 and disconnected==1)
        ''')

    def test_placeholder_and_missing_label_time_out_without_join(self):
        for text in ('Label',''):
            with self.subTest(text=text):
                self.setUp(); self.run_lua('errorWindow("'+text+'",0.1); advance(7); assert(rejoins==0 and #jobs==0)')

    def test_hidden_or_removed_prompt_does_not_trigger_join(self):
        for action in ('root.Visible=false','root.Parent=nil'):
            with self.subTest(action=action):
                self.setUp()
                self.run_lua('root=errorWindow("Disconnected"); after(0.3,function() '+action+' end); advance(7); assert(rejoins==0)')

    def test_destroy_or_reinit_cancels_old_queued_rejoin(self):
        for action in ('hop:Destroy()',
                       'root.Parent=nil; hop:Init({Config=config,Movement=movement,RuntimeLog=logger})'):
            with self.subTest(action=action):
                self.setUp()
                self.run_lua('root=errorWindow("Disconnected"); after(0.3,function() '+action+' end); advance(7); assert(rejoins==0)')

    def test_native_failure_does_not_retry_infinite_error_windows(self):
        self.run_lua('''
            rejoinFails=true; errorWindow("Disconnected"); advance(3)
            errorWindow("Teleport failed"); advance(20)
            assert(rejoins==1 and #jobs==0)
        ''')

    def test_manual_rejoin_in_flight_is_not_duplicated_by_auto_rejoin(self):
        self.run_lua('''
            rejoinDelay=3; task.spawn(function() manual=hop:Rejoin() end)
            errorWindow("Disconnected"); advance(5)
            assert(rejoins==1 and manual)
        ''')


if __name__=='__main__': unittest.main()
