"""Release isolation and actual public loader execution with offline module mocks."""
from pathlib import Path
import re
import subprocess
import unittest
from lupa import LuaRuntime
from ai.autofix import check_luau
from scripts.build_public_release import build, ROOT, PUBLIC_PREVIOUS

class PublicReleaseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.files = build()

    def test_every_public_luau_file_parses(self):
        for name, source in self.files.items():
            with self.subTest(name=name):
                self.assertTrue(check_luau(source))

    def test_public_loader_dependencies_are_all_shipped(self):
        loader = self.files['Main.lua']
        loaded = re.findall(r'file = "([^"]+\.lua)"', loader) + ['AutoPrestige.lua']
        self.assertEqual(set(loaded) | {'Main.lua'}, set(self.files))
        self.assertIn('file = "AutoPrestigeRuntime.lua"', loader)
        self.assertIn('file = "PrestigeDialogue.lua"', loader)

    def test_private_components_cannot_enter_public_package(self):
        for name, source in self.files.items():
            with self.subTest(name=name):
                self.assertNotRegex(source, r'WhiteAI|WHITE AI|AI DEBUG|AIPage|_whiteAI|DevMain|dev/2026|white-ai-v1|/auth/pair|WHITE_AI_DEVICE_SESSION')
        self.assertNotIn('WhiteAI.lua', self.files)
        self.assertNotIn('DevMain.lua', self.files)
        self.assertFalse(any(name.startswith('ai/') for name in self.files))

    def test_merchant_byte_identical_to_existing_main(self):
        original = subprocess.check_output(['git', 'show', PUBLIC_PREVIOUS + ':Inventory.lua'], cwd=ROOT)
        self.assertEqual(original, self.files['Inventory.lua'].encode())

    def test_farm_and_progression_code_preserved(self):
        for name in ('Farm.lua', 'CombatFarm.lua', 'AutoPrestige.lua', 'AutoPrestigeRuntime.lua', 'PrestigeDialogue.lua'):
            self.assertEqual(self.files[name], (ROOT / name).read_text())
        before = (ROOT / 'StandFarm.lua').read_text()
        self.assertEqual(self.files['StandFarm.lua'], before.replace('reload DevMain', 'reload Main'))

    def test_public_owned_hop_returns_only_to_public_loader(self):
        transfer = self.files['StandTransfer.lua']
        self.assertIn('WHITE-HUB-V3/main/Main.lua', transfer)
        self.assertNotIn('dev/', transfer)
        # Guard/claim logic is preserved; only the queued loader URL/comment changes.
        original = (ROOT / 'StandTransfer.lua').read_text()
        self.assertEqual(transfer, original.replace('dev/2026-10-10-autosell-compat/DevMain.lua', 'main/Main.lua').replace('Only our dev loader is queued.', 'Only our public loader is queued.'))

    def test_beta_caption_preserves_auto_prestige_registry_key(self):
        self.assertIn("['Auto Prestige']='Auto prestige (BETA)'", self.files['UICompact.lua'])
        self.assertIn('MakeToggle(FarmPage, "Auto Prestige",', self.files['UI.lua'])
        self.assertIn('AutoPrestige = false', self.files['Config.lua'])

    def test_public_loader_boots_and_initializes_prestige_dependencies(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute('''
        now=0; requests={}; initialized={}; bootPrints={}; bootWarnings={}
        tick=function() return now end
        getgenv=function() return _G end
        warn=function(x) table.insert(bootWarnings,tostring(x)) end
        print=function(x) table.insert(bootPrints,tostring(x)) end
        loadstring=load; typeof=type
        task={wait=function(n) now=now+(n or 0.01) end,spawn=function(f,...) f(...) end}
        player={Name='OfflineTester'}
        game={PlaceId=2809202155,JobId='offline',IsLoaded=function() return true end}
        local services={Players={LocalPlayer=player},HttpService={GenerateGUID=function() return 'offline-runtime' end},TextService={}}
        function game:GetService(name) return services[name] end
        function game:HttpGet(url)
            table.insert(requests,url)
            local name=url:match('/([^/?]+%.lua)%?')
            assert(name and payloads[name], 'Missing public dependency: '..tostring(name))
            return payloads[name]
        end
        function factory(name)
            local module={}
            local function init(self,all)
                self.all=all; initialized[name]=true
                assert(all.WhiteAI==nil)
            end
            module.Init=init; module.Load=function() return true end
            module.Get=function(self,key) return false end
            module.Set=function() end; module.SetMany=function() end
            module.Create=function(self)
                assert(initialized.AutoPrestigeRuntime and initialized.PrestigeDialogue and initialized.UICompact)
                uiCreated=true
            end
            module.Start=function() farmStarted=true end
            module.Stop=function() end; module.IsBusy=function() return false end
            module.GetStatus=function() return {} end
            module.RecoverTransfer=function() recovered=true end
            module.GetResumeSupport=function() return {} end
            module.ResetStatistics=function() end
            module.Issue=function() end; module.Claim=function() end; module.Invalidate=function() end
            module.BuildResume=function() end; module.BuildSkins=function() end; module.BuildStats=function() end
            module.Names=function() return {} end; module.GetSkins=function() return {} end; module.GetNames=function() return {} end; module.GetState=function() end; module.Refresh=function() end; module.GetQuests=function() return {} end; module.IsInfo=function() return false end
            module.Build=function() end; module.Toggle=function() end; module.Filter=function() end; module.Close=function() end; module.Destroy=function() end
            module.Caption=function() end; module.Arrange=function() end; module.Observe=function() end
            module.Responsive=function() end; module.ScaleFor=function() return 1 end
            module.Register=function() apRegistered=true end; module.Watch=function() apWatched=true end
            module.BuildStatus=function() end; module.Run=function() end; module.Drive=function() end; module.Restore=function() end
            return module
        end
        ''')
        payloads = {}
        for name in self.files:
            if name not in ('Main.lua', 'AutoPrestige.lua'):
                payloads[name] = f'return factory("{name[:-4]}")'
        payloads['AutoPrestige.lua'] = 'assert(_G.WhiteHubModules.AutoPrestigeRuntime); _G.WhiteHubModules.AutoPrestigeRuntime:Register(); _G.WhiteHubModules.AutoPrestigeRuntime:Watch()'
        lua.globals().payloads = lua.table_from(payloads)
        lua.execute('_G.WhiteHubModules={OldPrivateWorker={Destroy=function() oldDestroyed=true end}}')
        lua.execute(self.files['Main.lua'])
        lua.execute('''
        assert(oldDestroyed and uiCreated and farmStarted and apRegistered and apWatched and recovered)
        assert(_G.WhiteHubModules.WhiteAI==nil)
        assert(#bootWarnings==0 and _G.WhiteHubModules.RuntimeLog:GetStats().ERROR==0)
        for _,url in ipairs(requests) do assert(url:find('/main/',1,true) and not url:find('WhiteAI',1,true)) end
        ''')
