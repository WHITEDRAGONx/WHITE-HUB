# Stand target-list checkpoint — experimental dev only

Pre-change commit: `5a958f6a8c23813a759bd9512a176c6311ab89a1`.
Main remains `718018dac21d9a51e1955f68b4a042f28a534ee1`.

Scope: additive Config target list, StandFarm target matching/snapshot, small UI
list controls and offline tests. Dialogue timing, respawn recovery, skin checks,
pending-item locks, pity and farm exclusivity are preserved. Inventory.lua and
CombatFarm.lua remain byte-identical. No backend deployment for this slice.

Rollback: restore Config.lua, StandFarm.lua and UI.lua from the pre-change commit
on dev using a new restoration commit. Preserve WHITE AI controls from that
baseline. An empty StandFarmTargets list keeps the legacy single-target setting.
Never reload or discard a Stand while an item result is unresolved.
