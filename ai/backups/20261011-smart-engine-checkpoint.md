# Smart Farm Engine checkpoint

Baseline: 333ad750b5dd44ffd569ab0bae6b69d0f17fa445
Branch: dev/2026-10-10-autosell-compat
Main protected: 718018dac21d9a51e1955f68b4a042f28a534ee1

Scope: central scheduler, validated profiles, bounded queue, lifecycle adapters, UI and dev loader wiring; preserve Inventory and XenonLock. Offline tests do not validate Roblox.
Rollback: restore changed files from baseline, preserving later incident/proposal commits. No Render deploy for this Lua change.
