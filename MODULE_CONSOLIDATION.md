# Module consolidation — 2026-10-19

Checkpoint before consolidation: `cbe7d8e589853fbff606cb10ef1f3051cda81512`. Revert the consolidation commit
for rollback; do not reset shared branch history.

- Shared visual layout, searchable choices and Stand controls now live inside
  UIComponents.lua, with isolated subcomponent state.
- GameCatalog.lua owns online refresh/cache scheduling and cancels it on teardown.
- AutoPrestigeRuntime.lua owns its scoped dialogue driver and restores it on teardown.
- Removed the two unreferenced legacy combat files; active combat stays in CombatFarm.lua.
- Loaders and Clean Hop teardown use the new module owners. Permanent entry URLs unchanged.
- Inventory/Merchant, pickup, combat, Stand consumption and progression worker unchanged.

Public Lua file count: 24 to 18. Public boot downloads: 21 to 17.
This is a packaging/lifecycle refactor, not a new speed or FPS claim.
Roblox/Delta validation remains required, especially reload, Clean Hop,
selector reopening, cached/online skins and Auto Prestige dialogue cleanup.

Validation: 74 focused existing UI/catalog/prestige simulations passed, plus
nine consolidation checks on each candidate (92 checks total). Checks cover
component-body preservation, Luau parsing, gameplay byte comparisons, selector
teardown, catalog timer cancellation and both loader contracts. Public isolation
was checked independently. These results do not prove live Roblox behavior.
