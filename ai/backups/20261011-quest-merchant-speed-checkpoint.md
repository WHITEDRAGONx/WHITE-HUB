# Quest and Merchant dialogue performance checkpoint

Pre-change dev SHA: b82831fa3b079068fac1b7df1d46662767f3edec.
Main: 718018dac21d9a51e1955f68b4a042f28a534ee1, protected.

Owner explicitly requested performance improvements for all dialogue types, including selling, authorizing this task's isolated Inventory.lua changes. Preserve Merchant FINAL Zero Delay, Option1 -> Option1 -> Option6, all fallbacks, equip/inventory confirmation, state restoration and Real Injector scan guard. Preserve XenonLock byte-for-byte.

Scope: quest dialogue new-page cooldown only and timing; Merchant option lookup scope and scan timing. No generic wait removal, global hooks, shared dialogue controller, backend deploy or changes to combat/AutoPrestige progression. AutoPrestige legacy dialogue compatibility needs separate functional investigation.

Rollback: restore Inventory.lua and CombatFarm.lua from this SHA on dev, run syntax/regression tests and commit the restoration. Retain history; never reset main.

Verification: execute actual extracted Lua option helpers and quest dialogue driver in deterministic mocks; cover same-page throttling, newly changed options, cancellation, closure/state confirmation, hidden templates, Merchant option lookup and fallback behavior. Offline timings are not Delta benchmarks.
