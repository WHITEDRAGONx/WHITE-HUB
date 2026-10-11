# Stand Farm R4 performance checkpoint

Pre-change dev SHA: c51cb69d14101d6749a123f3547080948783f176.
Main remains 718018dac21d9a51e1955f68b4a042f28a534ee1.

Owner runtime 8bab0a5f confirms R3 Arrow -> Stone Free, Roka -> new Character/safe spot -> Arrow -> Aerosmith, desired-result stop, and a later Whitesnake roll followed by out-of-Roka stop. This validates those scenarios only; skin, cancellation and pity edges still require real QA.

R4 scope: StandFarm.lua dialogue polling/signatures, verified fast-handler latency and timing diagnostics; isolated offline tests and QA notes. Inventory.lua, CombatFarm.lua and other runtime modules are protected and unchanged. No backend deployment.

Rollback: restore StandFarm.lua from the pre-change SHA on dev, run syntax/regression tests, then commit the restoration on dev. Do not reset or rewrite shared history.
