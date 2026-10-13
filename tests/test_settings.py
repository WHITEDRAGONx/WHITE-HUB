"""Real Settings.lua with offline API/lifecycle mocks; not Delta validation."""
from pathlib import Path
import unittest
from lupa import LuaRuntime
from ai.autofix import check_luau

ROOT = Path(__file__).resolve().parents[1]
MOCK = r'''
now,jobs,logs,saves=0,{}, {},0
local function resume(co)
 local ok,delay=coroutine.resume(co); assert(ok,delay)
 if coroutine.status(co)~='dead' then jobs[#jobs+1]={co=co,at=now+(delay or 0.01)} end
end
task={spawn=function(fn) resume(coroutine.create(fn)) end,wait=function() coroutine.yield(0.01) end}
function advance(n)
 local target=now+n
 while true do
  local index,at=nil,target+1
  for i,v in ipairs(jobs) do if v.at<at then index,at=i,v.at end end
  if not index or at>target then break end
  now=at;local job=table.remove(jobs,index);resume(job.co)
 end
 now=target
end
function signal()
 local event={connections={}}
 function event:Connect(fn)
  local c={fn=fn,Connected=true};function c:Disconnect() self.Connected=false end
  self.connections[#self.connections+1]=c; return c
 end
 function event:Fire(...)
  for _,c in ipairs(self.connections) do if c.Connected then c.fn(...) end end
 end
 return event
end
local methods={}
function node(name,class,parent)
 local a={Name=name,ClassName=class,children={},DescendantAdded=signal(),Activated=signal(),Enabled=true,Text='',failReads={},failWrites={}}
 local object={attrs=a}
 setmetatable(object,{
  __index=function(_,key) if a.failReads[key] then error('read denied') end;return methods[key] or a[key] end,
  __newindex=function(self,key,value)
   if a.failWrites[key] then error('write denied') end
   if key=='Parent' then
    local old=a.Parent
    if old then for i,v in ipairs(old.children) do if v==self then table.remove(old.children,i);break end end end
    a.Parent=value
    if value then
     value.children[#value.children+1]=self
     local root=value
     while root do root.DescendantAdded:Fire(self);root=root.Parent end
    end
   else a[key]=value end
  end
 })
 if parent then object.Parent=parent end
 return object
end
function methods:IsA(class)
 return self.ClassName==class or class=='PostEffect' and self.ClassName=='BloomEffect'
end
function methods:FindFirstChild(name)
 for _,v in ipairs(self.children) do if v.Name==name then return v end end
end
methods.WaitForChild=methods.FindFirstChild
function methods:GetDescendants()
 local result={}
 local function visit(root) for _,v in ipairs(root.children) do result[#result+1]=v;visit(v) end end
 visit(self);return result
end
function methods:Destroy()
 while #self.children>0 do self.children[1]:Destroy() end
 self.destroyed=true;self.Parent=nil
end
Instance={new=function(class,parent) return node(class,class,parent) end}
local tuple=function(...) return {...} end
UDim2={new=tuple};UDim={new=tuple};Vector2={new=tuple};Color3={fromRGB=tuple}
Enum={SavedQualitySetting={QualityLevel1=1},ZIndexBehavior={Sibling='Sibling'},Font={GothamMedium='Medium',GothamBold='Bold'}}
player=node('Player','Player');playerGui=node('PlayerGui','PlayerGui',player)
workspace=node('Workspace','Workspace');lighting=node('Lighting','Lighting');lighting.GlobalShadows=true
quality=node('GameSettings','UserGameSettings');quality.SavedQualityLevel=3
run={rendering=true,requests={}}
function run:Is3dRenderingEnabled() return self.rendering end
function run:Set3dRenderingEnabled(value)
 if renderFail or value==true and resumeFail then error('render unavailable') end
 self.requests[#self.requests+1]=value;self.rendering=value
end
game={GetService=function(_,key) return ({Players={LocalPlayer=player},RunService=run,Lighting=lighting})[key] end}
UserSettings=function() return {GetService=function() return quality end} end
fps,capRequests=90,{}
getfpscap=function() return fps end
setfpscap=function(value)
 if capFail then error('cap unavailable') end
 capRequests[#capRequests+1]=value;fps=value
end
values={};config={Get=function(_,key) return values[key] end,Set=function(_,key,value) values[key]=value;saves=saves+1 end}
all={Config=config,RuntimeLog={Write=function(_,level,module,message) logs[#logs+1]=message end}}
'''

class SettingsTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(MOCK)
        self.lua.globals().settings=self.lua.execute((ROOT/'Settings.lua').read_text())
    def run_lua(self,script):
        self.lua.execute(script)

    def test_defaults_do_not_change_client_or_run_workers(self):
        self.run_lua("settings:Init(all);assert(fps==90 and quality.SavedQualityLevel==3 and run.rendering and #jobs==0 and #capRequests==0 and #run.requests==0 and saves==0)")

    def test_cap_round_trip_restores_original_and_persists_only_preference(self):
        self.run_lua("settings:Init(all);assert(settings:SetOption('SettingsCapFPS30',true));assert(fps==30 and values.SettingsCapFPS30);assert(settings:SetOption('SettingsCapFPS30',false));assert(fps==90 and values.SettingsCapFPS30==false)")

    def test_repeat_enable_does_not_capture_30_as_original_cap(self):
        self.run_lua("settings:Init(all);settings:SetOption('SettingsCapFPS30',true);settings:SetOption('SettingsCapFPS30',true);settings:SetOption('SettingsCapFPS30',false);assert(fps==90 and #capRequests==2)")

    def test_missing_cap_setter_does_not_break_init_or_other_settings(self):
        self.run_lua("setfpscap=nil;values.SettingsCapFPS30=true;settings:Init(all);assert(not settings:GetStatus().cap30);assert(not settings:SetOption('SettingsCapFPS30',true));assert(settings:SetOption('SettingsBlackScreen',true))")

    def test_failed_cap_request_does_not_persist_an_enabled_option(self):
        self.run_lua("capFail=true;settings:Init(all);assert(not settings:SetOption('SettingsCapFPS30',true));assert(not values.SettingsCapFPS30 and not settings:GetStatus().cap30 and fps==90)")

    def test_alias_apis_are_supported(self):
        self.run_lua("set_fps_cap=setfpscap;get_fps_cap=getfpscap;setfpscap=nil;getfpscap=nil;settings:Init(all);settings:SetOption('SettingsCapFPS30',true);settings:Destroy();assert(fps==90)")

    def test_unreadable_original_cap_has_explicit_60_fps_restore(self):
        self.run_lua("getfpscap=nil;settings:Init(all);settings:SetOption('SettingsCapFPS30',true);assert(settings:GetStatus().message:find('restores 60',1,true));settings:SetOption('SettingsCapFPS30',false);assert(fps==60)")

    def test_external_cap_change_is_not_overwritten_on_disable(self):
        self.run_lua("settings:Init(all);settings:SetOption('SettingsCapFPS30',true);fps=144;settings:SetOption('SettingsCapFPS30',false);assert(fps==144 and #capRequests==1)")

    def test_failed_restore_keeps_cap_state_and_allows_retry(self):
        self.run_lua("settings:Init(all);settings:SetOption('SettingsCapFPS30',true);capFail=true;assert(not settings:SetOption('SettingsCapFPS30',false));assert(settings:GetStatus().cap30 and values.SettingsCapFPS30);capFail=false;assert(settings:SetOption('SettingsCapFPS30',false));assert(fps==90)")

    def test_low_quality_reduces_effects_and_restores_exact_values(self):
        self.run_lua("local bloom=node('Bloom','BloomEffect',lighting);local particle=node('Particle','ParticleEmitter',workspace);local beam=node('Beam','Beam',workspace);local trail=node('Trail','Trail',workspace);local part=node('Part','Part',workspace);part.Material='Metal';settings:Init(all);settings:SetOption('SettingsLowGraphics',true);advance(1);assert(quality.SavedQualityLevel==1 and not lighting.GlobalShadows and not bloom.Enabled and not particle.Enabled and not beam.Enabled and not trail.Enabled and part.Material=='Metal');settings:SetOption('SettingsLowGraphics',false);assert(quality.SavedQualityLevel==3 and lighting.GlobalShadows and bloom.Enabled and particle.Enabled and beam.Enabled and trail.Enabled)")

    def test_preexisting_disabled_effect_stays_disabled(self):
        self.run_lua("local particle=node('Particle','ParticleEmitter',workspace);particle.Enabled=false;settings:Init(all);settings:SetOption('SettingsLowGraphics',true);settings:SetOption('SettingsLowGraphics',false);assert(not particle.Enabled)")

    def test_low_mode_handles_new_effects_without_polling(self):
        self.run_lua("settings:Init(all);settings:SetOption('SettingsLowGraphics',true);local effect=node('New','ParticleEmitter',workspace);assert(not effect.Enabled);settings:SetOption('SettingsLowGraphics',false);assert(effect.Enabled);local later=node('Later','ParticleEmitter',workspace);assert(later.Enabled)")

    def test_stop_during_initial_scan_cannot_disable_later_objects(self):
        self.run_lua("for i=1,260 do node('P'..i,'ParticleEmitter',workspace) end;settings:Init(all);settings:SetOption('SettingsLowGraphics',true);assert(#jobs>0);settings:SetOption('SettingsLowGraphics',false);advance(1);for _,effect in ipairs(workspace.children) do assert(effect.Enabled) end")

    def test_graphics_changed_elsewhere_are_not_overwritten_by_rollback(self):
        self.run_lua("settings:Init(all);settings:SetOption('SettingsLowGraphics',true);quality.SavedQualityLevel=5;settings:SetOption('SettingsLowGraphics',false);assert(quality.SavedQualityLevel==5)")

    def test_denied_quality_property_uses_effect_only_mode(self):
        self.run_lua("quality.failReads.SavedQualityLevel=true;values.SettingsLowGraphics=true;settings:Init(all);assert(settings:GetStatus().low and settings:GetStatus().message:find('Effects only',1,true));settings:Destroy()")

    def test_black_screen_pauses_3d_and_touch_recovery_restores_view(self):
        self.run_lua("settings:Init(all);settings:SetOption('SettingsBlackScreen',true);local gui=playerGui:FindFirstChild('WhiteHubBlackScreen');assert(gui and gui.ResetOnSpawn==false and not run.rendering and settings:GetStatus().rendering_paused);gui:FindFirstChild('BlackBackground'):FindFirstChild('ShowGame').Activated:Fire();assert(run.rendering and not settings:GetStatus().black and values.SettingsBlackScreen==false and not playerGui:FindFirstChild('WhiteHubBlackScreen'))")

    def test_unsupported_3d_api_uses_truthful_visual_only_mode(self):
        self.run_lua("run.Set3dRenderingEnabled=nil;settings:Init(all);assert(settings:SetOption('SettingsBlackScreen',true));assert(run.rendering and not settings:GetStatus().rendering_paused and settings:GetStatus().message:find('still on',1,true));assert(settings:RestoreView())")

    def test_missing_playergui_does_not_disable_3d(self):
        self.run_lua("playerGui.Parent=nil;settings:Init(all);assert(not settings:SetOption('SettingsBlackScreen',true));assert(run.rendering and #run.requests==0)")

    def test_prior_disabled_rendering_is_preserved(self):
        self.run_lua("run.rendering=false;settings:Init(all);settings:SetOption('SettingsBlackScreen',true);settings:RestoreView();assert(run.rendering==false)")

    def test_failed_destroy_resume_keeps_recovery_button_usable(self):
        self.run_lua("settings:Init(all);settings:SetOption('SettingsBlackScreen',true);local button=playerGui:FindFirstChild('WhiteHubBlackScreen'):FindFirstChild('BlackBackground'):FindFirstChild('ShowGame');resumeFail=true;settings:Destroy();assert(settings:GetStatus().black);resumeFail=false;button.Activated:Fire();assert(run.rendering and not settings:GetStatus().black)")

    def test_destroy_restores_without_erasing_saved_choices_and_reinit_applies_them(self):
        self.run_lua("values.SettingsCapFPS30=true;values.SettingsLowGraphics=true;values.SettingsBlackScreen=true;settings:Init(all);assert(fps==30 and quality.SavedQualityLevel==1 and not run.rendering);settings:Destroy();assert(fps==90 and quality.SavedQualityLevel==3 and run.rendering and values.SettingsBlackScreen and values.SettingsLowGraphics and values.SettingsCapFPS30);settings:Init(all);assert(fps==30 and quality.SavedQualityLevel==1 and not run.rendering)")

    def test_ui_toggles_stay_in_sync_with_recovery(self):
        self.run_lua("settings:Init(all);local page=node('SettingsPage','Frame');local callbacks={};local states={};local ui={SetToggleValue=function(_,label,value) states[label]=value end,AddLabel=function(_,p,text) local label=node('Label','TextLabel',p);label.Text=text;return label end,ShowPopup=function() end};settings:Build(page,ui,function(_,label,default,fn) callbacks[label]=fn end,{MUTED={}});callbacks['Black screen'](true);assert(states['Black screen']);settings:RestoreView();assert(states['Black screen']==false)")

    def test_only_known_boolean_preferences_are_accepted(self):
        self.run_lua("settings:Init(all);assert(not settings:SetOption('FarmEnabled',true));assert(not settings:SetOption('SettingsLowGraphics','true'));assert(saves==0)")

    def test_syntax_wiring_opt_in_defaults_and_no_farm_dependency(self):
        for name in ('Settings.lua','Config.lua','UI.lua','DevMain.lua'):
            self.assertTrue(check_luau((ROOT/name).read_text()),name)
        source=(ROOT/'Settings.lua').read_text()
        self.assertNotRegex(source,r'Inventory|CombatFarm|FireServer|InvokeServer|Destroy\(.*workspace|setfflag|hookfunction')
        config=(ROOT/'Config.lua').read_text()
        for key in ('SettingsCapFPS30','SettingsLowGraphics','SettingsBlackScreen'):
            self.assertIn(key+' = false',config)
        ui=(ROOT/'UI.lua').read_text()
        self.assertIn('{ name="Settings", page=SettingsPage }',ui)
        self.assertIn('Sidebar.AutomaticCanvasSize = Enum.AutomaticSize.Y',ui)

if __name__=='__main__':
    unittest.main()
