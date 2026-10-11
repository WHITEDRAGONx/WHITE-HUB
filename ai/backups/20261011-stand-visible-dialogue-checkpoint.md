# Stand Farm visible dialogue checkpoint

Before changes: dev `b5783ac4a735082b4fd3c49966f462a20a7dd4d5`.
Main preserved: `718018dac21d9a51e1955f68b4a042f28a534ee1`.
StandFarm original blob: `17d879237c29ce1010845d39446dd5efe4600f77`.
Rollback: restore StandFarm.lua from that dev commit; no other runtime module changes authorized in this task.
Protected: Inventory.lua, CombatFarm.lua (including XenonLock), Main.lua, UI.lua, Config.lua, DevMain.lua.
Plan: bounded visible Option1/ClickContinue input, real Stand state confirmation, cancellation and unresolved consumption lock.
Verification: Luau parser, simulated UI/state/cancellation tests, offline backend regression. Roblox/Delta validation still required.
