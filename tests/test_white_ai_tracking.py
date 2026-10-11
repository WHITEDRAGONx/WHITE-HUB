"""Real Lua job watcher simulated with bounded HTTP payloads, no network."""
import unittest
from pathlib import Path
from lupa import LuaRuntime
from test_stand_dialogue import MOCK


class WhiteAITrackingTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(MOCK + '''
        _running=true; _epoch=1; _config=config; values.WhiteAIEnabled=true
        _jobHistory={}; _watching={}; _lastStatus="ready"; calls=0; payloads={}
        safeText=function(v) return tostring(v) end
        sessionHeaders=function() return {} end
        request=function()
            calls=calls+1
            return {StatusCode=200,Body="payload"}
        end
        HttpService={JSONDecode=function() return payloads[math.min(calls,#payloads)] end}
        ''')
        source = (Path(__file__).resolve().parents[1] / 'WhiteAI.lua').read_text()
        chunk = source[source.index('local function recordJob('):source.index('function WhiteAI:GetStatus()')]
        self.lua.globals().watch = self.lua.execute(chunk + '\nreturn watchJob')

    def test_waiting_retry_then_proposal_is_tracked(self):
        self.lua.execute('''
        payloads={{status="waiting_retry",attempts=1},{status="proposal_ready",diagnosis="safe"}}
        task.spawn(function() watch("https://example.test/reports","","aaaaaaaaaaaaaaaaaaaa",1) end)
        advance(8); assert(_lastStatus:find("Incidente salvo",1,true))
        advance(8); assert(calls==2 and _jobHistory[1].status=="proposal_ready")
        ''')

    def test_exhausted_stops_without_pairing_failure(self):
        self.lua.execute('''
        payloads={{status="retry_exhausted",attempts=3}}
        task.spawn(function() watch("https://example.test/reports","","aaaaaaaaaaaaaaaaaaaa",1) end)
        advance(100); assert(calls==1 and _jobHistory[1].status=="retry_exhausted")
        assert(_lastStatus:find("Incidente salvo",1,true))
        ''')

    def test_duplicate_watchers_do_not_duplicate_requests(self):
        self.lua.execute('''
        payloads={{status="queued"},{status="proposal_ready"}}
        for i=1,2 do task.spawn(function() watch("https://example.test/reports","","aaaaaaaaaaaaaaaaaaaa",1) end) end
        advance(20); assert(calls==2)
        ''')

    def test_optout_and_epoch_cancel_pending_poll(self):
        self.lua.execute('''
        payloads={{status="queued"}}
        task.spawn(function() watch("https://example.test/reports","","aaaaaaaaaaaaaaaaaaaa",1) end)
        values.WhiteAIEnabled=false; advance(20); assert(calls==0)
        values.WhiteAIEnabled=true
        task.spawn(function() watch("https://example.test/reports","","aaaaaaaaaaaaaaaaaaaa",1) end)
        _epoch=2; advance(20); assert(calls==0 and _lastStatus=="ready")
        ''')
