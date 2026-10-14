# Sale, collection and hop performance checkpoint — 2026-10-14

Pre-change dev: d9383eb600473a664f5b52bd5750f9701691bb6e
Pre-change main: b7a1a7c96c34dd2350a4165e27496f96b77af3b3

Owner specifically authorized Inventory.lua optimization for restoring historical ~0.70s selling and improving collection/hop. Use the latest public Inventory.lua and Farm.lua as implementation baselines so SELL NOW, SellPerf and signal/GC diagnostics are preserved. Synchronize those existing public additions into dev rather than replacing public files with older dev code.

Planned scoped changes: cache dialogue button candidates without narrowing supported layouts; frame-paced FINAL advance; readiness-based spawn detection; earlier bounded pickup with inventory confirmation and cancellation cleanup; shorter idle cycle; prepare a short-lived server-list cache during sale. Do not rewrite Merchant option callbacks, XenonLock, Stand/Shiny guards, Auto Prestige, UI, Settings, private AI or loader. No Render deploy.

Rollback: restore Inventory.lua, Farm.lua and ServerHop.lua from the corresponding pre-change SHA in a new scoped commit; keep all unrelated later work. Restore packaging baseline if required. Never force-reset either branch.

Historical 0.70s is an owner measurement in an earlier Delta session, not a promise for current Delta/Velocity or network conditions. Offline mocks will measure removed waits only; real SALE/colection/hop traces are still required.
