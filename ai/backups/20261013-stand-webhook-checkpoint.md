# Stand/Shiny/Rib webhook checkpoint — 2026-10-13

Pre-change dev: 5a3f98d2e57299c3a36e2f8ab3f02f9b2ebd2ce3
Pre-change main: fd2fc92386d1fcc6e898f0e0b7e3e26363a95850

Scope: StandFarm.lua + Webhook.lua, targeted offline tests, notification QA and documentation. Reuse the configured owner webhook; one asynchronous terminal notification per run. No requests per roll, no notification on manual Stop/reload/active server transfer. Keep existing Merchant, XenonLock, Item Farm and settings unchanged.

Rollback: restore only StandFarm.lua and Webhook.lua from the matching branch pre-change SHA in a new commit. Preserve unrelated later changes and never force-reset main. Offline tests cannot establish Roblox/Delta or Discord delivery success.
