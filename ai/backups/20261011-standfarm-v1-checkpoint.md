# WHITE HUB V3 Stand Farm V1 rollback checkpoint

Pre-change working development commit: `57752d0179b5f2c577e9cf4ba472ef2e92ce2596`
Production main commit: `718018dac21d9a51e1955f68b4a042f28a534ee1`

Planned additions (dev only): `StandFarm.lua`, plus module loading, disabled-by-default config, UI and offline syntax tests.

Rollback: restore changed files from the pre-change commit and delete only new StandFarm files. Existing combat, Inventory, Merchant and WhiteAI remain protected.

This checkpoint contains no secrets or imported third-party webhook URLs. Actual Roblox behavior is NOT validated by static tests.
