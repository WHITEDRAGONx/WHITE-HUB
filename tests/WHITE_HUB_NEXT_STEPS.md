# WHITE HUB — experimental delivery and next gates

Only dev/2026-10-10-autosell-compat is authorized. Main, Inventory and XenonLock
remain protected. Offline tests and an HTTP health check are not YBA validation.

## Delivered in this package

- WHITE AI: encrypted durable incident records, bounded Gemini retry/recovery,
  owner controls, source revision tracking and StandFarm read-only routing.
  Backend 5a958f6 is LIVE; owner authenticated ingestion/recovery QA remains.
- Stand target-list beta: stop on any selected target, persistent additive list,
  immutable per-run snapshot and stop-before-edit controls. Empty list preserves
  legacy single-target mode. Existing item/dialogue/skin safeguards remain.
  Follow STAND_FARM_DELTA_QA.md before calling this stable.
- Shiny mode beta (R6): opt-in any-skin search, ignoring common Stand targets;
  preserves detected/unknown skins and checks again before Roka activation.
  Thirteen new offline simulations; no Shiny functional test in YBA yet.

## Owner evidence received

R5 ran in Delta with Aerosmith/Cream targets, continued across two unwanted Arrow
results and Roka/respawn recovery, then stopped on Cream. Other guards still need
specific evidence. WHITE AI wrote an encrypted incident and a real review-only
Inventory proposal at 2026-10-11 13:50:21 Brazil time (1ddfb9d). No patch was
produced or applied. Gemini outage/restart recovery is not established by that
successful job. Owner reports sales working; preserve Merchant as is.

## Owner QA now

1. Run DevMain on Delta, confirm R6 build and no bootstrap failures.
2. Follow the controlled list/Stop/respawn/skin/pity tests in the Stand QA guide.
3. On the already paired device, enable WHITE AI and send an actionable report.
   An idle manual report may legitimately return no_incident without Gemini.
   Confirm a saved proposal or waiting_retry with attempt count; then reload the
   hub and use RECOVER SAVED INCIDENTS. A transient failure must keep the incident;
   retries never apply an unreviewed patch. Do not expose the session file.
4. Compare Merchant with the restored baseline; this package does not change
   Inventory.lua. Record actual timings/counts if it still regresses.

## Remaining roadmap, in order

1. Stable QA: Quest/NPC credit and switching, farm cancellation, reload, respawn,
   hop and prolonged AutoPrestige. Fix only evidenced failures.
2. Stand V2 next slices: validate any-skin mode, then skin-specific selection, Rib-specific consumables,
   then controlled restock/handoff. Each needs its own checkpoint, tests and YBA
   evidence. No storage integration before functional validation.
3. Smart Farm Engine: one owner for character/dialogues, task priorities, bounded
   recovery and progress metrics. Integrate working modules incrementally.
4. UI V4: mobile scrolling/layout/dashboard after runtime stability; preserve
   controls and saved settings.
5. WHITE AI improvements: retention/discovery beyond this low-volume GitHub queue,
   regression history and owner audit/rollback. No paid infrastructure/provider
   or widened AutoFix allowlist without authorization.
6. Closed beta, changelog/versioning and public release only after QA and explicit
   approval to update main.
