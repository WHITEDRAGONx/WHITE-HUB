# Owner authentication rollback checkpoint

Branch: dev/2026-10-10-autosell-compat

Pre-change commit: 395a3310fe185b8933b4e7391e668831dcab5c54

Restore authentication files from this commit to undo the implementation.
Main, Inventory.lua, CombatFarm.lua (XenonLock), and Merchant were not modified.
No credentials or session tokens are included in this checkpoint.
