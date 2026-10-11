# Rib / bounded restock checkpoint — dev only

Baseline: `f066809a2b0d5af0f9473af77bd3f7dbefabd989`.
Main: `718018dac21d9a51e1955f68b4a042f28a534ee1`.

Authorized scope: Config.lua, StandFarm.lua, UI.lua, and a bounded opt-in
Farm.lua restock API sharing existing detection/collection. Inventory, Merchant,
CombatFarm/XenonLock, loaders, ServerHop and backend stay unchanged.
Rib uses the player's existing skill allocation; do not invent a Worthiness API.
Restock collects only one missing consumable on the current server, verifies
inventory, stops after 90s / 8 collection attempts, and never sells/buys/hops.
No automatic destructive consumption after reload or unresolved result.

Rollback: restore the four runtime files from baseline with a new dev commit,
preserving subsequent AI incident/proposal commits. No Render deployment.
