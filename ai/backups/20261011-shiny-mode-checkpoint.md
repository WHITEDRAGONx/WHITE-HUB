# Shiny mode checkpoint — experimental dev only

Baseline: `6581f5840c371719b60fa607a4e8e057cafc361f`.
Runtime baseline: `dcac46f1c56154b8ec11604ebf97f337b4b07968`.
Main: `718018dac21d9a51e1955f68b4a042f28a534ee1` (unchanged).

Scope: additive opt-in Shiny mode in Config.lua, StandFarm.lua and UI.lua,
with offline simulations and Delta QA. Existing target-list mode remains the
default. Shiny mode may replace common target-list Stands, but preserves any
skin or inconclusive skin result. No automatic storage, skin whitelist or Rib.
Inventory.lua, CombatFarm.lua, loaders and backend remain unchanged.

Rollback: restore Config.lua, StandFarm.lua and UI.lua from the baseline using
a new dev commit; preserve all AI incident/proposal commits. Do not rewrite
history or reload while an item outcome is unresolved. No Render deployment.
