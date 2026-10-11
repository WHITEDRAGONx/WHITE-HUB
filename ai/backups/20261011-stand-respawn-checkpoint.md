# Stand R3 respawn checkpoint

Dev baseline: 63a4b82541de613b2f20e0433b99eac2f77a18c2.
Main: 718018dac21d9a51e1955f68b4a042f28a534ee1, unchanged.
Rollback: restore StandFarm.lua from baseline on dev only.
Delta runtime 778ed3ba confirms R2 Arrow -> Cream and Roka -> None, then second Arrow stalled after Continue; user stopped. This validates those two interactions, not continuous farming.
Investigate/fix only StandFarm: wait for a new ready Character after confirmed Roka, use existing Movement safe spot API, prepare existing Worthiness request once per Arrow phase, permit a verified Option1 selection to release a yielded Continue handler without firing another signal concurrently. Preserve Inventory, CombatFarm, XenonLock, Movement, Farm, UI, config and backend byte-for-byte.
Offline tests must cover actual simulated character replacement, delayed remotes/root, Stop during recovery, delayed skill request, pending callback released by Option1, and multiple cycles. Functional Delta validation remains required; no Render deploy.
