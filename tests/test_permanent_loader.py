from pathlib import Path
import unittest
from lupa import LuaRuntime
from ai.autofix import check_luau
ROOT=Path(__file__).resolve().parents[1]
class PermanentLoaderTests(unittest.TestCase):
 def test_alias_parses_and_routes_only_to_existing_public_main(self):
  source=(ROOT/'release/alias/Loader.lua').read_text()
  self.assertTrue(check_luau(source));self.assertNotIn('DevMain',source)
  lua=LuaRuntime(unpack_returned_tuples=True)
  lua.execute("requests=0; executed=0; os.time=function() return 123 end; game={HttpGet=function(_,url) requests=requests+1; target=url; return 'source' end}; loadstring=function(s) assert(s=='source'); return function() executed=executed+1 end end")
  lua.execute(source);lua.execute("assert(requests==1 and executed==1 and target=='https://raw.githubusercontent.com/WHITEDRAGONx/WHITE-HUB-V3/main/Main.lua?whitehub=123')")
 def test_user_facing_loader_is_versionless_and_requirements_documented(self):
  source=(ROOT/'release/public/README.md').read_text()
  self.assertIn('WHITE-HUB/main/Loader.lua',source)
  self.assertIn('getgenv',source);self.assertIn('Filesystem APIs',source)
  self.assertTrue(source.startswith('# WHITE HUB — Public Beta'))
