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

    def test_black_screen_only_covers_view_and_touch_recovery_removes_cover(self):
        self.run_lua("settings:Init(all);settings:SetOption('SettingsBlackScreen',true);local gui=playerGui:FindFirstChild('WhiteHubBlackScreen');assert(gui and gui.ResetOnSpawn==false and run.rendering and not settings:GetStatus().rendering_paused and #run.requests==0);gui:FindFirstChild('BlackBackground'):FindFirstChild('ShowGame').Activated:Fire();assert(run.rendering and not settings:GetStatus().black and values.SettingsBlackScreen==false and not playerGui:FindFirstChild('WhiteHubBlackScreen'))")

    def test_unavailable_3d_api_is_not_needed_or_probed(self):
        self.run_lua("run.Set3dRenderingEnabled=nil;run.Is3dRenderingEnabled=function() error('must not probe renderer') end;settings:Init(all);assert(settings:SetOption('SettingsBlackScreen',true));assert(run.rendering and not settings:GetStatus().rendering_paused and settings:GetStatus().message:find('visual only',1,true));assert(settings:RestoreView())")

    def test_missing_playergui_does_not_disable_3d(self):
        self.run_lua("playerGui.Parent=nil;settings:Init(all);assert(not settings:SetOption('SettingsBlackScreen',true));assert(run.rendering and #run.requests==0)")

    def test_prior_disabled_rendering_is_preserved(self):
        self.run_lua("run.rendering=false;settings:Init(all);settings:SetOption('SettingsBlackScreen',true);settings:RestoreView();assert(run.rendering==false)")

    def test_destroy_removes_cover_without_renderer_resume_or_late_callbacks(self):
        self.run_lua("renderFail=true;resumeFail=true;settings:Init(all);settings:SetOption('SettingsBlackScreen',true);local button=playerGui:FindFirstChild('WhiteHubBlackScreen'):FindFirstChild('BlackBackground'):FindFirstChild('ShowGame');settings:Destroy();local before=saves;button.Activated:Fire();assert(run.rendering and not settings:GetStatus().black and not playerGui:FindFirstChild('WhiteHubBlackScreen') and #run.requests==0 and saves==before)")

    def test_saved_black_is_cleared_but_fps_and_quality_choices_reapply(self):
        self.run_lua("values.SettingsCapFPS30=true;values.SettingsLowGraphics=true;values.SettingsBlackScreen=true;settings:Init(all);assert(fps==30 and quality.SavedQualityLevel==1 and run.rendering and not values.SettingsBlackScreen and not settings:GetStatus().black);settings:SetOption('SettingsBlackScreen',true);settings:Destroy();assert(fps==90 and quality.SavedQualityLevel==3 and run.rendering and values.SettingsBlackScreen and values.SettingsLowGraphics and values.SettingsCapFPS30);settings:Init(all);assert(fps==30 and quality.SavedQualityLevel==1 and run.rendering and not settings:GetStatus().black and not values.SettingsBlackScreen)")

    def test_repeated_black_toggles_create_no_workers_or_renderer_calls(self):
        self.run_lua("settings:Init(all);for i=1,20 do settings:SetOption('SettingsBlackScreen',true);settings:SetOption('SettingsBlackScreen',true);settings:SetOption('SettingsBlackScreen',false) end;assert(#jobs==0 and #run.requests==0 and not playerGui:FindFirstChild('WhiteHubBlackScreen'))")

    def test_ui_toggles_stay_in_sync_with_recovery(self):
        self.run_lua("settings:Init(all);local page=node('SettingsPage','Frame');local callbacks={};local states={};local ui={SetToggleValue=function(_,label,value) states[label]=value end,AddLabel=function(_,p,text) local label=node('Label','TextLabel',p);label.Text=text;return label end,ShowPopup=function() end};settings:Build(page,ui,function(_,label,default,fn) callbacks[label]=fn end,{MUTED={}});callbacks['Black screen'](true);assert(states['Black screen']);settings:RestoreView();assert(states['Black screen']==false)")

    def test_only_known_boolean_preferences_are_accepted(self):
        self.run_lua("settings:Init(all);assert(not settings:SetOption('FarmEnabled',true));assert(not settings:SetOption('SettingsLowGraphics','true'));assert(saves==0)")

    def test_syntax_wiring_opt_in_defaults_and_no_farm_dependency(self):
        for name in ('Settings.lua','Config.lua','UI.lua','DevMain.lua'):
            self.assertTrue(check_luau((ROOT/name).read_text()),name)
        source=(ROOT/'Settings.lua').read_text()
        self.assertNotRegex(source,r'Inventory|CombatFarm|FireServer|InvokeServer|Destroy\(.*workspace|setfflag|hookfunction')
        self.assertNotRegex(source,r'Set3dRenderingEnabled|Is3dRenderingEnabled|RunService')
        config=(ROOT/'Config.lua').read_text()
        for key in ('SettingsCapFPS30','SettingsLowGraphics','SettingsBlackScreen'):
            self.assertIn(key+' = false',config)
        ui=(ROOT/'UI.lua').read_text()
        self.assertIn('{ name="Settings", page=SettingsPage }',ui)
        self.assertIn('Sidebar.AutomaticCanvasSize = Enum.AutomaticSize.Y',ui)


NATIVE_MOCK = r'''
nativeCalls,nativeSignals=0,0
getconnections=function(event)
 local found={}
 for _,c in ipairs(event.connections) do
  local entry={Enabled=c.Enabled,Connected=c.Connected,Function=c.fn}
  if not functionOnly then entry.Fire=function() return c.fn() end end
  found[#found+1]=entry
 end
 return found
end
firesignal=function(event) nativeSignals=nativeSignals+1;event:Fire() end
function nativeMenu(noHandler)
 nativeHud=node('HUD','ScreenGui',playerGui)
 local main=node('Main','Frame',nativeHud);local frames=node('Frames','Frame',main)
 local menu=node('Settings','Frame',frames);nativeList=node('List','ScrollingFrame',menu)
 nativeRow=node('ToggleLowGFX','ImageLabel',nativeList)
 nativeButton=node('Button','TextButton',nativeRow);nativeButton.Text='TOGGLE LOW GFX'
 nativeButton.MouseButton1Click=signal()
 if not noHandler then nativeButton.MouseButton1Click:Connect(function()
  nativeCalls=nativeCalls+1
  if holdNative then task.wait() end
  if nativeError then error('private exception must not be logged') end
  if not keepNativeControl then nativeRow:Destroy() end
 end) end
end
'''


class NativeSettingsTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(MOCK+NATIVE_MOCK)
        self.lua.globals().settings=self.lua.execute((ROOT/'Settings.lua').read_text())

    def run_lua(self, script):
        self.lua.execute(script)

    def test_native_click_once_and_off_reload_does_not_claim_native_rollback(self):
        self.run_lua("nativeMenu();settings:Init(all);settings:SetOption('SettingsLowGraphics',true);assert(nativeCalls==1 and nativeSignals==0 and nativeRow.Parent==nil);assert(settings:GetStatus().native_low_gfx=='control_removed');settings:SetOption('SettingsLowGraphics',false);assert(quality.SavedQualityLevel==3 and settings:GetStatus().message:find('rejoin',1,true));settings:SetOption('SettingsLowGraphics',true);settings:Init(all);assert(nativeCalls==1 and nativeSignals==0)")

    def test_noop_firesignal_does_not_shadow_working_connection_fire(self):
        self.run_lua("nativeMenu();firesignal=function() nativeSignals=nativeSignals+1 end;settings:Init(all);settings:SetOption('SettingsLowGraphics',true);advance(1);assert(nativeCalls==1 and nativeSignals==0 and settings:GetStatus().native_low_gfx=='control_removed')")

    def test_noop_firesignal_does_not_shadow_unique_function_fallback(self):
        self.run_lua("nativeMenu();functionOnly=true;firesignal=function() nativeSignals=nativeSignals+1 end;settings:Init(all);settings:SetOption('SettingsLowGraphics',true);advance(1);assert(nativeCalls==1 and nativeSignals==0 and settings:GetStatus().native_low_gfx=='control_removed')")

    def test_multiple_handlers_still_use_one_signal_dispatch(self):
        self.run_lua("nativeMenu();nativeButton.MouseButton1Click:Connect(function() extraNativeHandler=true end);settings:Init(all);settings:SetOption('SettingsLowGraphics',true);assert(nativeSignals==1 and nativeCalls==1 and extraNativeHandler)")

    def test_dispatch_route_and_prior_state_are_visible_without_private_errors(self):
        self.run_lua("nativeMenu();values.SettingsLowGraphics=true;keepNativeControl=true;settings:Init(all);advance(1);settings:SetOption('SettingsLowGraphics',false);settings:SetOption('SettingsLowGraphics',true);local text=table.concat(logs,' ');assert(text:find('Dispatch route=connection-fire; handlers=1',1,true));assert(text:find('Prior state=unconfirmed; route=connection-fire',1,true));assert(nativeCalls==1)")

    def test_redownloaded_module_keeps_guard_for_same_hud(self):
        self.run_lua("nativeMenu();keepNativeControl=true;settings:Init(all);settings:SetOption('SettingsLowGraphics',true);advance(1);settings:Destroy();assert(nativeCalls==1)")
        self.lua.globals().replacement=self.lua.execute((ROOT/'Settings.lua').read_text())
        self.run_lua("replacement:Init(all);assert(nativeCalls==1 and replacement:GetStatus().native_low_gfx=='unconfirmed');replacement:SetOption('SettingsLowGraphics',false);assert(replacement:GetStatus().message:find('rejoin',1,true))")

    def test_saved_low_preference_can_request_native_once_on_init(self):
        self.run_lua("nativeMenu();values.SettingsLowGraphics=true;settings:Init(all);assert(nativeCalls==1 and settings:GetStatus().low and settings:GetStatus().native_low_gfx=='control_removed')")

    def test_already_used_control_is_not_reported_as_fresh_success(self):
        self.run_lua("nativeMenu();nativeRow:Destroy();settings:Init(all);settings:SetOption('SettingsLowGraphics',true);assert(nativeCalls==0 and nativeSignals==0 and settings:GetStatus().native_low_gfx=='unavailable' and quality.SavedQualityLevel==1)")

    def test_missing_inspection_or_handler_preserves_local_low_mode(self):
        self.run_lua("nativeMenu(true);settings:Init(all);settings:SetOption('SettingsLowGraphics',true);assert(nativeSignals==0 and settings:GetStatus().native_low_gfx=='unsupported' and settings:GetStatus().low);settings:SetOption('SettingsLowGraphics',false);getconnections=nil;settings:SetOption('SettingsLowGraphics',true);assert(nativeSignals==0 and settings:GetStatus().native_low_gfx=='unsupported')")

    def test_unexpected_native_label_is_not_invoked(self):
        self.run_lua("nativeMenu();nativeButton.Text='TOGGLE MUSIC VOLUME';settings:Init(all);settings:SetOption('SettingsLowGraphics',true);assert(nativeCalls==0 and nativeSignals==0 and settings:GetStatus().native_low_gfx=='unavailable')")

    def test_unique_callback_fallback_without_firesignal(self):
        self.run_lua("nativeMenu();firesignal=nil;functionOnly=true;settings:Init(all);settings:SetOption('SettingsLowGraphics',true);assert(nativeCalls==1 and nativeSignals==0 and settings:GetStatus().native_low_gfx=='control_removed')")

    def test_ambiguous_callbacks_without_signal_dispatch_are_not_guessed(self):
        self.run_lua("nativeMenu();nativeButton.MouseButton1Click:Connect(function() nativeCalls=nativeCalls+100 end);firesignal=nil;settings:Init(all);settings:SetOption('SettingsLowGraphics',true);assert(nativeCalls==0 and settings:GetStatus().native_low_gfx=='unsupported')")

    def test_failed_callback_is_not_retried_or_logged_with_private_exception(self):
        self.run_lua("nativeMenu();nativeError=true;settings:Init(all);settings:SetOption('SettingsLowGraphics',true);assert(nativeCalls==1 and settings:GetStatus().native_low_gfx=='failed');settings:SetOption('SettingsLowGraphics',false);settings:SetOption('SettingsLowGraphics',true);assert(nativeCalls==1);for _,line in ipairs(logs) do assert(not line:find('private exception',1,true)) end")

    def test_unchanged_control_is_unconfirmed_and_is_not_clicked_again(self):
        self.run_lua("nativeMenu();keepNativeControl=true;settings:Init(all);settings:SetOption('SettingsLowGraphics',true);advance(1);assert(nativeCalls==1 and settings:GetStatus().native_low_gfx=='unconfirmed');settings:SetOption('SettingsLowGraphics',false);settings:SetOption('SettingsLowGraphics',true);assert(nativeCalls==1)")

    def test_delayed_ui_can_arrive_but_off_cancels_old_wait(self):
        self.run_lua("settings:Init(all);settings:SetOption('SettingsLowGraphics',true);advance(0.02);settings:SetOption('SettingsLowGraphics',false);nativeMenu();advance(1);assert(nativeCalls==0);settings:SetOption('SettingsLowGraphics',true);assert(nativeCalls==1)")

    def test_missing_ui_wait_is_bounded(self):
        self.run_lua("settings:Init(all);settings:SetOption('SettingsLowGraphics',true);advance(1);assert(#jobs==0 and nativeCalls==0 and settings:GetStatus().native_low_gfx=='unavailable' and settings:GetStatus().low)")

    def test_destroy_during_issued_callback_has_no_late_status_or_second_request(self):
        self.run_lua("nativeMenu();holdNative=true;settings:Init(all);settings:SetOption('SettingsLowGraphics',true);assert(nativeCalls==1 and settings:GetStatus().native_low_gfx=='requested');settings:Destroy();local count=#logs;advance(1);assert(#logs==count and nativeCalls==1 and not settings:GetStatus().low)")

if __name__=='__main__':
    unittest.main()
