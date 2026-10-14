# Pickup compatibility rollback + Auto Rejoin

Reported after the performance update: teleport to item -> moderation message
`No exploiting! (bruh)` / 267. A screenshot alone does not establish the triggering
check. Withdraw the faster movement/prompt cadence before another live test.

Current build: `PICKUP-COMPAT-20261014-R2`; sale remains `SALE-20261014-R1`.
Earlier 50ms pickup, retry prompt, 100ms cycle and 8s dry-window notes in the R1
speed QA are historical and superseded by this guide.

- New spawns wait 1s. Existing initial spawns retain their original immediate scan.
- Pickup waits 350ms, requests the prompt once and waits 150ms after safe return.
- Normal cycles/dry-window are restored to 1s/20s. Restock stays at 90s/8 attempts,
  one prompt each. Actual inventory, cancellation and cleanup remain required.
- Merchant cache/sequence and read-only server preparation are unchanged.

Live retest: reload in a fresh session, confirm the R2 build and record the first
pickup, character position, item count and complete sanitized Console. If the
same moderation kick recurs, stop further farm attempts and send that trace;
do not claim the intervals resolved the game's enforcement condition.

Auto Rejoin: one native Teleport request after a visible disconnect/kick prompt
has a real message. Missing/hidden/removed templates do not trigger requests.
Destroy/reload cancels queued old tasks. Failure is logged without retries or
script replay. Do not deliberately provoke a moderation kick to test it; report
behavior if a normal disconnect occurs. Offline prompt mocks cannot prove native
Teleport works from every disconnected client state.

Public source changes only Farm.lua and ServerHop.lua, plus README/changelog.
No Inventory/Merchant changes, private AI publication, or Render deploy.
