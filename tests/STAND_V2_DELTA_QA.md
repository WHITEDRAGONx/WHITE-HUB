# Stand V2 R9 package — experimental dev, NOT VALIDATED IN DELTA

## Delivered feature set

| Feature | Implementation | Remaining real-game evidence |
|---|---|---|
| Multiple Stand targets | R5 list; stop on any target | One owner's R5 continuation/stop log exists |
| Arrow / Rib source | Existing bounded dialogue + result/respawn guards | Rib still needs Delta QA; Worthiness remains manual |
| Shiny mode / exact wishlist | R6 any-skin protection; R9 semicolon-separated exact names | Natural skin result / real RPC identifiers not yet verified |
| Consumable restock | R7 targeted collection, one item, 90s / 8 attempts | Prompt/inventory/handoff needs Delta QA |
| Restock hop | R8 guarded, optional, private-server preference respected | Actual transfer needs Delta QA |
| Automatic owned-hop continuation | R9 one-use destination/expiry/config/state checks | Executor queue + files + native client marker need Delta QA |
| Pity Manager | Limit/remaining/delta, attempts, confirmed Arrow/Rib/Roka, restocks, active-time rate | Compare displayed counters with real stock/stat changes |

Wishlist matching does NOT permit destroying an unwanted skin. Every detected
skin stops and is preserved; unknown/empty/failed lookup also preserves the Stand.
No skin storage or automatic skin destruction is included. Exact wishlist names
must match ReturnStandSkin's returned string, not an invented internet catalog.

## Opt-in continuation contract

Enable Auto Restock, Hop After Restock Limit and Auto Resume Owned Hop explicitly.
Default resume is false. Auto hop limit defaults to 3, accepts 1–5, and survives
successful arrival claims; reaching the limit stops. Manually starting a new run
authorizes a fresh hop chain. Ordinary reload never authorizes consumption.

StandTransfer.lua writes only a strict non-secret intent to
WHITE_STAND_TRANSFER.json, plus an ID marker in the client's TeleportService
settings. No WHITE AI session/admin key, webhook, headers, source code or arbitrary
user code is serialized. The marker is a local intent ID, not a credential or
server authorization. The queue runs only the owner's existing dev loader URL.

Each intent targets the actual selected server ID, expires after 15 minutes and
is consumed/invalidated BEFORE the destination's up-to-30-second readiness wait.
Place, destination, unchanged Stand/pity, targets/skins/source/mode/pity/hop limits,
opt-in and farm exclusivity are checked. Start repeats skin and state checks.
Config edits, Stop, wrong server, expired intent, inability to claim once, failed
teleport or uncertain results hold the beta off. There is no blanket auto-start.

The queue checks the intent and marker both before and after fetching DevMain,
so cancellation or a manual claim during HTTP fetch cannot replay the loader.
Stop clears the native marker even if file invalidation fails. After a teleport
has been submitted, Start and statistics reset are blocked on the old runtime;
Stop can cancel continuation but cannot revoke a request already accepted by
Roblox. Verify failure/arrival before manually reloading.

Required support: readfile/writefile, a working queue_on_teleport (or recognized
equivalent), client SetTeleportSetting/GetTeleportSetting, and TeleportInitFailed.
If unavailable, a guarded hop requires manual restart. If persistence/queue setup
fails after capability detection, no automatic transfer is submitted. No support
for Delta is asserted from API names alone.

Primary references for the native lifecycle/marker semantics:
- https://create.roblox.com/docs/projects/teleport
- https://create.roblox.com/docs/reference/engine/classes/TeleportService

## Owner Delta procedure

1. Cold DevMain; confirm `SF-V2-20261011-R9` and successful downloads/Init of
   StandTransfer.lua and StandV2UI.lua. Keep all beta controls OFF initially.
2. With Resume OFF, run a short Arrow target-list regression and inspect pity,
   attempts and confirmed counters. No valued Stand/skin should be discarded.
   Existing R7/R8 guides apply with the extra resume option OFF.
3. For wishlist input, use exact known returned names separated by semicolons.
   Shiny mode continues through common Stand targets. Any skin still stops;
   wishlist match shows Desired skin found, other skins show protected stop.
   Do not spend hours waiting for a shiny just to declare validation. Keep this
   outcome pending until a natural observed result exists.
4. In a controlled low-stock session, enable the three restock/hop/resume options
   and choose a small hop budget. Keep Item/Quest/NPC Farm, Prestige and Auto Sell
   OFF. Verify local restock happens first. If it fails, expect one destination
   intent, transfer, dev loader boot, one-use claim, readiness/skin/state checks,
   then targeted collection/consumption. Verify actual server and inventory.
5. Test Stop during local collection, HTTP lookup, queued-loader wait and arrival
   recovery. Confirm no new input after cancellation. A previously submitted
   game action may still complete. Wrong destination or ordinary reload must not
   automatically consume. Confirm an already submitted transfer blocks old-server
   Start/reset and no stale queue can replay after the intent is claimed.
6. Exercise a 1-hop budget with no stock; after the valid arrival's next bounded
   restock failure it must stop rather than hop forever. Do not manually edit the
   intent, force replays, or send credential/session files as test evidence.
7. Pity/metrics: compare before/after stock and replicated Stand/Pity. Attempts
   mean item activation requests; confirmed counters require the expected Stand
   state and closed dialogue. Unknown outcome is NOT counted as a confirmed roll.
   Remaining is off for limit 0; rate uses active worker time, including local
   restock but excluding the paused transfer/readiness period. Counts continue
   through a claimed transfer; ordinary cold reload resets session metrics.
   Reset is permitted only when stopped with no pending action/transfer/recovery.

Export runtime, source/mode, settings, before/after stock/Stand/skin/pity, server
transition and Stop timing. Never include WHITE_AI_DEVICE_SESSION.json, keys,
private webhooks or raw personal settings. The handoff is non-secret but support
does not need its raw file; inspect statuses and logs instead.

## Offline verification / rollback

25 new tests execute the actual transfer/controller/UI code with mocked engine,
executor and inventory: valid resume, ordinary reload, bad destination, expiry,
settings/pity/skin drift, Stop, replay, file/queue failure, native marker revocation,
failed teleport, hop budgets, whitelist/schema, UI lists/limits, metrics and reset.
Original Lua is independently parsed; mock continue lowering does not alter repo
sources. Offline tests cannot establish executor delivery, actual skin schema,
server arrival, prompt semantics or inventory/skill behavior in YBA.

Pre-change runtime: `fd7829bc409c1eeee072f8f81cece0809912714b`.
Checkpoint: `0231257662be7d7e23fea81c3d474c83f349af9b`.
Rollback affected runtime files using a new dev commit, remove StandTransfer.lua
and StandV2UI.lua loader wiring, cancel/clear local intent, preserve AI history.
Inventory.lua, CombatFarm.lua, Farm.lua, Main.lua and backend are unchanged.
ai/test_server.py changes cover Lua parser/contracts only; no Render deploy.

V2 feature implementation is ready for beta review, not a stable release. The
next implementation milestone is Smart Farm Engine; all pending QA remains open.
