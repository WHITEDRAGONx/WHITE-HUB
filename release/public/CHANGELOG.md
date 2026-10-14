# Changelog

## Pickup compatibility rollback / Auto Rejoin — 2026-10-14 (R2)

- Withdraws the faster pickup cadence after an owner-supplied tester screenshot
  showed a moderation kick during item teleport. Timing causality is unconfirmed.
- Restores 350 ms before one pickup prompt, 150 ms after return, one-second new
  spawn/normal-cycle cadence and the historical 20-second dry-server window.
  Inventory-only confirmation, character guards and cleanup remain.
- Auto Rejoin now waits for ErrorMessage construction and visible text, handles
  a prompt already present on reload, deduplicates attempts and cancels stale
  tasks on Destroy/reinit. One native request per runtime; no retry loop or
  automatic script replay. A rejected native request is logged.
- Auto Sell optimization, ServerHop list preparation, combat/Stand/Settings/UI
  remain intact. Farm build: PICKUP-COMPAT-20261014-R2.
- Offline checks only. This rollback does not establish that a game's kick
  condition or native rejoin behavior is resolved; live retest is required.

## Sale/pickup/hop performance beta — 2026-10-14 (R1)

- Retains the proven Merchant FINAL sequence, callback handling, restoration,
  GC backoff and inventory confirmation. Live dialogue button indexing preserves
  broad/renamed layouts while avoiding repeated walks through animated text.
- FINAL advancement yields one frame; the ready option lookup is reused.
- Ready item spawns are queued immediately; partial models have bounded retries.
  Pickup begins after 50 ms and can retry once at the old position-settle window.
  Inventory increase is required; another player's despawn is not our collection.
- Removes the fixed 150 ms post-pickup wait, uses 100 ms normal cycles and an
  eight-second normal dry-server timer. Restock interaction/time limits retained;
  each of its eight collection attempts can issue at most two prompt requests.
- A short-lived server-list cache is prepared during automatic sales and reused
  once by Hop, with cancellation, destination and duplicate-request guards.
- Preserves SELL NOW/SellPerf and public Console diagnostics, synchronized into
  dev. Builds: SALE-20261014-R1 and PICKUP-20261014-R1.
- Offline simulations only. Actual 0.70s-or-faster sale, Velocity prompt support
  and competitive pickup/hop performance are not established without live logs.

## Stand/Shiny/Rib webhook — 2026-10-13 (Stand R11)

- Reuses the configured Webhook URL for one terminal notification: desired Stand,
  any confirmed skin (including wishlist matches), or automatic stop/protection.
- Includes player, mode, consumable, Stand/skin, pity, confirmed rolls, elapsed
  time and stop reason. Unknown skin checks are never announced as shiny results.
- Asynchronous delivery; no per-roll spam, automatic retries, or messages for
  manual Stop/reload/ongoing restock transfers. Stale queued tasks are cancelled.
- HTTP errors are logged without the private URL or provider response body.
- Stand build: SF-WEBHOOK-20261013-R11. Offline validation only; actual Delta and
  Discord delivery require a live test. Merchant, combat and restock are unchanged.

## Black screen compatibility hotfix — 2026-10-13 (Settings R2)

- Removed native 3D renderer control after a tester reported delay/crash when
  enabling Black screen. The cause remains unconfirmed without a runtime trace.
- Black screen is now only a visual cover; SHOW GAME and hub controls remain
  accessible. It starts OFF each load, including previously saved ON values.
- FPS cap and low graphics remain separate saved options. No changes to Merchant,
  Auto Sell, restock, combat or consumable guards.
- Settings build: SETTINGS-BLACK-20261013-R2. Offline tests verify zero renderer
  calls, recovery, cleanup and saved-state handling; live Delta retest is pending.

## Settings performance options — 2026-10-13 (Silver R4)

- New Settings tab: opt-in 30 FPS cap, low graphics and black screen; saved choices
  apply on load. Scrollable navigation keeps every tab accessible on mobile.
- Black screen has a SHOW GAME recovery button and reports a visual-only fallback
  when 3D rendering control is unavailable. Hub controls remain above its overlay.
- FPS and graphics restore the prior values on OFF/reload where supported.
  A missing FPS getter uses an explicit 60 FPS restore. Low mode reduces visual
  effects without deleting geometry or changing dialogue/consumable logic.
- 24 offline Settings simulations plus public-loader, syntax and UI checks.
  Actual Delta behavior, RAM usage and device temperature remain unverified.
- Existing Merchant, combat and farms preserved, including the latest public
  SELL NOW, Console Follow/Copy SALE and Merchant timing changes.

## Permanent WHITE HUB loader — 2026-10-12

Public installation now uses WHITE-HUB/main/Main.lua, the canonical public modular entry point. The owner renamed the current
repository to WHITE-HUB and the old repository to WHITE-HUB-Legacy. Both histories
are preserved. README requirements updated. 307 offline checks
passed, including the Quest/NPC invocation adapter and permanent loader routing.

## V5 beta combat invocation hotfix — 2026-10-12

- Quest/NPC Stand invocation requests are serialized while waiting for replicated
  confirmation, preventing duplicate ToggleStand requests under latency.
- A missing SummonedStand flag with no StandMorph no longer skips the request.
- Bounded retries, Stop/respawn guards and StandSummon diagnostics added.
- Combat positioning, attacks, kill credit and Merchant unchanged.
- 305 offline checks passed; actual Quest/NPC invocation needs Delta validation.

## V5 beta automatic catalog update — 2026-10-12 (Silver R3)

- Quests prioritize names detected in the game; NPC discovery stays live.
- Broader bounded read-only skin container discovery and confirmed-result names.
- Automatic names-only Trello refresh/cache every six hours. Offline fallback
  combines 461 distinct names/aliases, including the supplied Xenon skin list.
- No third-party code imported; no game modules executed to guess skin data.
- 290 offline checks passed. Actual YBA skin-container exposure and exact aliases
  remain unverified; offline availability or complete automatic discovery is not
  guaranteed. Every skin remains protected regardless of the wishlist.

## V5 beta UI/catalog update — 2026-10-12 (Silver R2)

- Replaced target edit/clear buttons with searchable multi-selection.
- Removed Reset Stats from the interface; live statistics remain.
- Replaced typed skin wishlist with a searchable 236-name Trello catalog, preserving
  saved and recognized client names. All skins remain protected.
- Added a quest catalog and bounded read-only client discovery. Unknown objectives
  are INFO only; no new automatic quest controllers or PvP behavior are claimed.
- Added Hermit Purple, Beach Boy and Red Hot Chili Pepper to Stand choices.
- No external code imported. Merchant, combat and consumption logic unchanged.
- 274 offline checks passed; native Delta selector/discovery validation pending.

## V5 beta hotfix — 2026-10-12 (Stand R10)

- Auto Sell may remain enabled during Stand/Shiny/Rib Farm when Item Farm is off.
- The same preference is accepted for local restock, owned hop and resume.
- Actual Item Farm work/sales still block Stand startup until they finish.
- Pending results, active competing farms, skin and pity safeguards remain.
- Merchant unchanged. Six new offline regression checks; 252 checks total.
  This hotfix still needs confirmation in Delta.

## V5 Public Beta — 2026-10-12

- Compact Silver UI with English labels, grouped switches/fields/actions and a
  dedicated Stand tab. Viewport-aware sizing and fixed-size text.
- Stand V2 beta: multiple targets, Shiny mode, Arrow/Rib sources, skin safeguards,
  pity/statistics, bounded restock and optional owned-hop resume.
- Quest/NPC compatibility improvements while retaining the combat core.
- Auto Prestige compatibility beta: modern multipage dialogue, tracked pending
  actions, cancellation, respawn recovery, existing Item Farm restock and
  delegation to the unchanged public Merchant.
- Public loader updated to include every new public dependency. Owned-hop
  continuation loads the public entry point.

Auto Prestige is included at the owner's request for beta testing. Complete live
progression remains unvalidated. The owner reports completion of other available
checks; those reports do not establish compatibility with all executors or game
updates. No storage integration or deliberate skin destruction is included.

Offline validation: 246 checks (56 backend/static plus 190 Lua/release simulations),
including 8 dedicated public-package checks. Boot is simulated with mock modules;
these checks do not reproduce Roblox, Delta, server responses or native rendering.

### Publication audit and rollback

Previous public commit: 718018dac21d9a51e1955f68b4a042f28a534ee1.
Experimental source: 02b391bc16b3e25b750fa92559d5efc0429bb993.
Public tree is selected by file whitelist on the existing main history. Merchant
Inventory.lua remains byte-identical to the previous public commit. Private
administration, backend and development records are excluded. No backend deploy.

If rollback is necessary, revert this release commit on main to restore the
previous public tree. Keep shared history; do not force-reset the branch.
