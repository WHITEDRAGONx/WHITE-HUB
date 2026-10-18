# Native Low GFX R4 rollback checkpoint — 2026-10-18

Dev before change: 99627331c21d09d691c880e420f2c7ad1daac300
Main before change: 0a61119bcd1b6e612fd9585b449cf01e309f3b3f

Owner Delta 1.0.741.1062 runtime confirms Settings R3 loaded. OFF/ON logs
"Request already issued; no retry" without a native UI confirmation. Initial
saved-ON dispatch was not logged, and OFF cancelled the observation window.
This proves an unconfirmed issued request was preserved; it does not prove
which executor primitive failed. R3 prefers firesignal, which can be simulated
as a no-op while a bound connection:Fire remains usable.

R4 scope: prefer one inspectable bound connection:Fire/Function when unique;
retain one signal dispatch for multiple handlers; log route/handler count and
prior state. Preserve the no-retry-after-dispatch guard. No guessed remotes,
UI-state fabrication, code extraction or unrelated runtime changes.

Main may receive only Settings.lua, README.md, CHANGELOG.md under the owner's
ongoing explicit main authorization. Keep WHITE AI private. No Render deploy.
Rollback: restore those public paths from the main SHA above. Native effects
already issued in a client may require rejoin; code rollback does not undo them.
Verification: Settings regression, no-op firesignal reproduction, public
packaging, diff/protected-file checks. Delta validation still required.
