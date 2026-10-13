# Black screen regression checkpoint — 2026-10-13

Dev before hotfix: 5812b9859ffe27396ea6f160b86a910369622105
Public before hotfix: 22d16af1e34f4301cfea4ecb385e2c729c40f060

Owner supplied a Discord screenshot: tester reports delay/crash when enabling
Black screen. No runtime log or crash trace was provided. Native 3D rendering
control in Settings.lua is a plausible contributing mechanism, not a confirmed
root cause. Remove that mechanism rather than ship another unverified native
renderer workaround.

Scope: Settings.lua, its targeted tests and Settings README/QA/changelog.
Keep FPS/low-graphics behavior and SHOW GAME. Make black screen a visual-only
overlay and require explicit manual enable per runtime. No render API calls,
frame workers or geometry deletion. No changes to Inventory, Merchant,
CombatFarm, StandFarm, Farm, AutoPrestige, or loaders.

Restock investigation: existing StandFarm.ensureItem delegates missing Arrow/
Roka/Rib to Farm.Restock when StandFarmAutoRestock is enabled. Both stock checks
precede discarding a common Stand; limits, skin/pity and pending guards remain.
Auto Sell already has public stage-wait/SellPerf diagnostics and SELL NOW.
Collect Copy SALE output for speed changes; no Inventory patch in this task.

Verify zero native renderer calls with the real Lua module in mocks; overlay
on/off/Destroy/unsupported APIs; clearing saved black-screen preference on boot;
unchanged FPS/graphics rollback; syntax and public isolation. Retest on a fresh
Roblox/Delta session. Offline checks do not establish crash resolution in YBA.

Rollback references above remain in Git. Restoring the old Black screen would
reintroduce the reported regression risk; keep it OFF pending investigation.

