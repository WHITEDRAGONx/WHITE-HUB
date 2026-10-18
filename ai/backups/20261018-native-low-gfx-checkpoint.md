# Native YBA Low GFX checkpoint — 2026-10-18

Pre-change dev: 538ebacc2f9b5a3b0a021743626a479f55364ee3
Pre-change main (read-only): e08e9e28c599af0acbf4d053178b4fe0d4c86dc7

Owner Delta 1.0.741.1062 R4 captures identify:
PlayerGui/HUD/Main/Frames/Settings/List/ToggleLowGFX/Button (TextButton).
After manual activation, ToggleLowGFX and Button disappear while Settings/List
remains. Treat this as a single native request, not a reversible hub setting or
proof of actual FPS improvement. No PlayerStats graphics flag was found.

Scope: Settings.lua native UI adapter, focused tests and dev documentation only.
Preserve Inventory.lua, Farm.lua, CombatFarm.lua/XenonLock, StandFarm.lua,
AutoPrestige, loaders and all public files. No Render deploy.

Before native dispatch: verify exact UI path/label, current runtime/low-mode token,
and an inspectable bound click handler. At most one dispatch per native HUD.
No guessed remotes, decompilation/upvalue extraction, bulk scan or retry after an issued call.
Only the existing binding of the exact native click control may be invoked.
Local quality/effects still work if the native API is unavailable. Native changes
may require rejoining to undo; never claim they are restored by the hub's OFF.

Verification: existing Settings regression plus focused native action/no-handler,
missing/delayed UI, failure/no-double-dispatch and lifecycle tests. Parser, diff
and protected-file checks. Native activation remains unvalidated until owner
rejoins for a fresh YBA button and tests the dev loader in Delta.

Rollback: restore Settings.lua from the pre-change dev SHA above; retain this
checkpoint and development history. Main is not changed by this experiment.
