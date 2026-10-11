# WHITE HUB experimental checkpoint: Stand Farm updated dialogue / Gemini 503

Pre-change tested dev commit: `74d56cef38f676e2c6c216729911d4d33c35c575`

Production main: `718018dac21d9a51e1955f68b4a042f28a534ee1`

Problem evidence: Stand Farm opened Arrow dialogue but failed to finish updated Option1/ClickContinue pages; user logs 02:20:17–02:20:50. Remote Gemini provider returned HTTP 503 after timeout at 05:22 UTC; not a Lua crash or owner authentication issue.

Change scope: StandFarm.lua, offline tests and (if demonstrably necessary) backend diagnostics. No edits to main, Inventory.lua, CombatFarm.lua, Merchant, or XenonLock.

Rollback: restore changed dev files from `74d56cef38f676e2c6c216729911d4d33c35c575`; preserve this checkpoint. Gameplay behavior must be tested within YBA.
