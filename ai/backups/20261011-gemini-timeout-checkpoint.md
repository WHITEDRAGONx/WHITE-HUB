# WHITE AI Gemini timeout / manual diagnostic rollback checkpoint

Pre-change dev commit: `04256857b088b86a284229f07d389e0cdf052efc`
Protected production main commit: `718018dac21d9a51e1955f68b4a042f28a534ee1`

Change scope: only `ai/server.py`, `ai/test_server.py`.

Restore both files from the pre-change dev commit if the backend regresses. Preserve `Inventory.lua`, `CombatFarm.lua`, `WhiteAI.lua`, `UI.lua`, `main`, XenonLock, Merchant, and all environment secrets.

This checkpoint contains no credentials.
