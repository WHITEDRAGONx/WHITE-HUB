# Guarded restock hop checkpoint — dev only

Baseline: `4cc8b0f8ac84b7bc69a4252aea6cb1f8234c0e1a`.
Main: `718018dac21d9a51e1955f68b4a042f28a534ee1`.

Scope: opt-in restock hop after a bounded local failure, cancellation guard in
ServerHop, Config/UI controls and StandFarm shutdown/restart notice. One hop
request per manually started run; no auto-consumption or queued loader after
reload. Unknown skin/result, private-server preference and competing farms
block the transfer. HTTP cancellation must be checked again before teleport.
No Inventory/CombatFarm/Farm/loader/backend changes or Render deployment.

Rollback the four affected runtime files from baseline with a new dev commit;
preserve incident/proposal history. Hop acknowledgement is NOT arrival proof.
