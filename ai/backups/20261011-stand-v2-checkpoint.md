# Stand V2 completion checkpoint — dev only

Baseline: `fd7829bc409c1eeee072f8f81cece0809912714b`.
Main: `718018dac21d9a51e1955f68b4a042f28a534ee1`.

Authorized V2 scope: opt-in automatic continuation only after a hub-initiated
restock transfer; exact skin wishlist while preserving all skins; pity/session
metrics. New non-secret one-use handoff module and experimental loader wiring.
Ordinary reload must remain stopped. Bound hops and validity; verify destination
and unchanged Stand/pity/settings. Require executor file and teleport queue APIs.
Never store credentials, session/admin keys, webhook or arbitrary code in handoff.
No storage or automatic skin destruction. Inventory/CombatFarm/Farm/backend stay
unchanged. No Render deploy for this Lua package.

Rollback affected runtime files from baseline with a new dev commit and remove
StandTransfer.lua / local WHITE_STAND_TRANSFER.json if cancelling this feature.
Preserve AI incident/proposal history; never reload while an item is unresolved.
