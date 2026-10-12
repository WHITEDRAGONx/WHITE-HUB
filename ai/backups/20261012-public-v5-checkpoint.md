# Public Silver V5 beta publication checkpoint

Owner explicitly authorized main publication including the new Auto Prestige beta on 2026-10-12 (Brazil time). WHITE AI must remain dev-only.

Public rollback source: 718018dac21d9a51e1955f68b4a042f28a534ee1.
Experimental source inspected: 2ddce2a7921e92f02563f4226fbeac382d43eb25.

Build a whitelist-only public tree on the existing main history, not a dev merge. Exclude WHITE AI client/UI/config, backend, owner sessions, proposals/incidents, DevMain and developer backups. Retain public Inventory.lua byte for byte. Rewrite StandTransfer owned-hop loader to main/Main.lua. Include AP runtime/dialogue dependencies and mark AP beta/unvalidated in YBA. Validate public boot/dependencies, syntax, private separation, transfer isolation and regression before moving main with an expected-head lease. No Render deploy.

Rollback: create a normal revert commit for the public release on main, restoring the previous tree; never force-reset shared branches. Public release notes must record previous/source SHA and remaining AP QA.
