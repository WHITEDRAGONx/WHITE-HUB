# Sale/pickup/hop performance R1 — Delta and Velocity QA

Baseline public SHA: b7a1a7c96c34dd2350a4165e27496f96b77af3b3.
Checkpoint: ai/backups/20261014-sale-collection-speed-checkpoint.md.
Only Inventory.lua, Farm.lua and ServerHop.lua changed in runtime. Quest/XenonLock,
Stand/Shiny/Rib consumption/skin guards, Auto Prestige, Settings and UI unchanged.

1. Fresh Roblox/executor session; run the permanent Main loader. Confirm Console
   builds SALE-20261014-R1 and PICKUP-20261014-R1. Do one comparison with Black
   screen and FPS cap OFF to separate renderer/frame delays from this patch.
2. Stop other farms, select one expendable item type for selling, record its
   count and money, press Items -> SELL NOW. Wait for SellPerf END. Only count
   decrease counts as sale; closing a dialogue alone proves nothing.
3. Copy SALE (all INFO/WARN events), not only WARN. Compare three repeats with
   the same item/count, executor and server. The historical ~0.70s is a goal,
   not a result of offline testing. Preserve records of fallbacks and stageWaitMs.
4. For Velocity's missing DialogueGui case, separately check manual Merchant
   opening with an equipped item and SELL NOW while nearby. The current patch
   optimizes lookup/advancement, not unverified executor prompt implementations.
5. Enable Item Farm, observe ready spawn -> first prompt -> inventory arrival.
   Confirm PickupPerf counts, 0/1 later retry, safe spot and no lingering freeze.
   A competing player's despawn must never emit Collected or increment stock.
6. Stop before first prompt, during delayed inventory arrival, and during a
   respawn. No further movement/prompt/hop after cancellation; freeze/noclip cleaned.
7. Normal empty servers use an 8s window after last confirmed pickup. Confirm
   list preparation is read-only and overlaps selling; no teleport before sale
   completes. StayInPrivateServer still blocks hops. Stop during HTTP prevents hop.
8. Restock still has a 90s/8-interaction limit, now at most two requests per
   interaction. Check Arrow/Roka/Rib, missing/late items, safe return and Stop.
   Owned resume and pending consumable locks must stay intact.
9. Check public SELL NOW/Console Follow/Copy SALE and terminal stand webhooks.
   Private WHITE AI remains dev-only. No Render deploy is needed for this patch.

Offline measurements count simulated waits and UI walks only. They cannot
predict YBA server replication, executor implementation, phone FPS or opponents.
Report build, executor, item counts, settings, full sanitized SALE/Console and a
short recording if possible. Never send webhook URLs/session credentials.
