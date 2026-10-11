# Merchant performance rollback

Pre-rollback dev: c9b5d31b0dae111548472d46c74cb444bea902d3.
Restore Inventory.lua byte-for-byte from b82831fa3b079068fac1b7df1d46662767f3edec.
Main remains 718018dac21d9a51e1955f68b4a042f28a534ee1.

Owner reports selling dialogue became worse after the performance change. No new runtime log was supplied, so root cause and precise timing are unconfirmed. Withdraw the entire Inventory optimization, including scan metrics, and preserve Stand/Quest changes. Prioritize the historically working Merchant behavior; do not experiment with replacement callbacks or reduce waits.

Regression: broad lookup must still find a visible named option outside an Options container and hidden templates must remain excluded. The narrowed candidate misses that layout in simulation; this is a coverage gap, not proof of the owner's current YBA layout.

Keep history: create a restoration commit on dev. No Render deploy or main changes. A new Delta sale test must confirm the functional result.

Verification limitation: Lua/backend suites could not run in the current environment (missing dependencies; network installation approval cancelled). Inventory matches the previously tested baseline exactly; other runtime files are unchanged, Python compileall and diff checks pass. New mock coverage remains unexecuted here.
