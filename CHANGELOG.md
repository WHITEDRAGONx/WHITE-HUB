# Changelog

## Arcade calibration failure & Merchant latency diagnostics — 2026-10-18

- Fix `canCalibrateHere` referencing nil `self._pilotStarting`.
  Arcade and Merchant floor save buttons now query the Community module state.
- Route old "Arcade" selection in TELEPORT TO PLACE through the safe
  saved Arcade floor instead of the old multistorey preset.
- Add passive `[Inventory][Latency]` timing per FINAL Merchant sale,
  splitting tool equip/prep, opening, stage wait, option injection,
  inventory confirmation, and cleanup.
- Preserve Option1 -> Option1 -> Option6, safety checks and existing
  inventory-based sale confirmation. Merchant callback pacing remains opt-in.
- Runtime validation in Delta is still required; diagnostics do not
  imply faster selling or bypass game enforcement.

## Floor-accurate Merchant / Arcade teleport & private DEV UI — 2026-10-18

- Merchant: SAVE MERCHANT POSITION records the player's root at the actual
  standing floor, even when StreamingEnabled hides the NPC. The teleport
  reuses it without the old +4-stud horizontal offset.
- Arcade: Workspace.Locations.The Arcade can point to roof geometry. A
  SAVE ARCADE ENTRANCE calibration button stores a user-confirmed standing
  floor; otherwise TELEPORT TO ARCADE intentionally refuses an unknown
  rooftop destination instead of falsely claiming a safe arrival.
- Calibrated teleport casts from just above the saved player root downward,
  requires a level match of 1-6 studs, and never chooses surfaces 18 studs
  above or floors up to 28 studs away.
- Stand Pilot, Event Jack trading and combat teleports retain existing
  ground rules. No changes to Merchant Zero Delay/Inventory.
- The AI DEBUG UI is PRIVATE-DEV ONLY (DevMain.lua), not the public Main.lua;
  public boot logs / public screenshots cannot verify a missing dev tab.

## FPS unlock & Merchant callback pacing diagnostics — 2026-10-18 (V5 Silver R4)

- Settings: added opt-in **Unlock FPS (BETA)**. Requests setfpscap(0),
  falling back to 999 if that call explicitly fails; the live FPS counter
  remains the ground truth, because the executor may silently clamp.
- Unlock FPS and Cap FPS at 30 are mutually exclusive. When disabling an
  unlock, the module restores the previously reported FPS cap where safe;
  if the old cap was unreadable it uses 60, with a warning.
- Items: added **Merchant Callback Pacing (BETA)**, OFF by default. When
  enabled, avoids firing ClickContinue more often than once per 75ms.
  Continues using the original FINAL Merchant dialogue/inventory verification
  and compatibility fallbacks, plus new per-stage loop and signal diagnostics.
- Benchmark logs on 2026-10-18 showed 0.543s versus 1.498s mean per type
  for two separate manual sales; this comparison DOES NOT prove the cause.
  Re-test both settings on the same server and with similar inventories.
- Does not change XenonLock, StandFarm, WhiteAI or Merchant item selection.

## Pickup timing, Merchant calibration, Jack hidden mode & FPS — 2026-10-18 (V5 R3)

- Opt-in Fast Pickup (BETA): new spawn settle 1.00s -> 0.55s; pre-prompt
  settle 0.35s -> 0.26s; original inventory confirmation retained.
  Minimum 0.75s between prompts and revert to normal timings after 3
  unconfirmed attempts. This does NOT guarantee avoiding server kicks.
- Merchant teleport caches position from live streamed NPC or via one-time
  SAVE MERCHANT POSITION button while standing beside Merchant. On subsequent
  sessions it can use that point when the NPC is unstreamed; raycast-based
  ground safety checks remain in effect.
- Opt-in Invisible Jack Dialogue: uses internally fired GUI callbacks when
  available and hides only the dialogue ScreenGui, restoring it after each
  transaction. Unsupported paths revert to visible UI.
- Settings R5 records measured FPS via RenderStepped, updating at ~0.8s
  intervals in the Settings panel and on the visual Black Screen overlay.
- No modifications to Inventory.lua, Merchant Zero Delay, XenonLock or
  automatic kick recovery. Features require real Delta validation.

## Halloween Jack live dialogue fix — 2026-10-18 (V5 SILVER R2)

- Turn-In first resolves a real Jack ProximityPrompt under Workspace.Dialogues,
  then verifies the captured Option2/Option3 page. It no longer assumes
  ReplicatedStorage.NewDialogue["Halloween Event"] must exist.
- If a live prompt is absent/unusable, fallback only to an exact, observed
  Jack/Halloween dialogue definition in NewDialogue/Dialogue.
- Events Items Farm can travel to the real Jack with the existing raycast-validated
  landmark teleport during a serialized trade, then return to its original position.
- Selected dialogue option text matches one visible text fragment exactly instead
  of concatenating duplicated TextLabels / buttons.
- Missing event-point balances stay fail-closed. Console now lists candidate
  event/point statistic names for later verification; no blind purchase occurs.
- Main and private dev remain separate; real Delta/YBA behavior needs new logs.

## Halloween Exchange opt-in beta — 2026-10-18 (V5 Silver R2)

- User confirmed that Jack's "I want to turn in my candy." converts collected
  event candies into event points; previous scanner output showed the dialogue
  but did not capture pre/post point balances.
- HalloweenExchange.lua handles a single Jack Option2 turn-in with inventory
  before/after verification. When an event-specific points Value is exposed,
  also requires a points increase; unresolved outcomes lock retries this runtime.
- Events tab now has Auto Turn-In Candy (opt-in) at the next event-farm dry server
  checkpoint, and a TURN IN CANDY NOW one-shot button when farms are disabled.
- Explicit Auto Buy Selected Reward (once) or BUY SELECTED REWARD NOW: resolves
  exact 2026/2022/2021/normal items and observed prices, requires a validated
  event-specific numeric point balance, checks category/item option labels,
  dispatches only one selected item and verifies point deduction.
- Buy permission resets OFF on every load/server hop, a selected target is not
  spending authorization, and ambiguous buy results block repeats. No unknown
  purchase-confirmation pages are blindly advanced.
- Only the existing Events Farm worker runs automatic trades; no parallel movement
  worker and no changes to Inventory.lua or Merchant. Live Delta tests required.

## Events Items Farm and Halloween reward preview — 2026-10-18 (V5 Silver R1)

- Sidebar order: Farm, Events, Stand; Events toggle is "Events Items Farm".
- Opt-in event mode in the original Farm.lua worker collects only verified Yellow,
  Blue, Green and Red Candy. Uses existing ProximityPrompt, inventory confirmation,
  safe spot restoration and no-dry-item 20s server hop respecting private-server mode.
- Normal Farm and Event Farm are mutually exclusive. No automatic Merchant selling,
  Lucky purchases, normal farm phases, or unverified candy turn-ins in event mode.
- Persisted configurations with conflicting farms are normalized to safe OFF.
- Saved rewards preview: 2026, 2022, 2021 Halloween and normal shop items with
  prices observed in the owner's 39-state Jack dialogue capture. No purchases made.
- Candy exchange and post-purchase confirmation remain unverified; Auto Turn-In and
  Auto Buy are deliberately not activated.
- Preserves Inventory.lua Merchant Zero Delay, CombatFarm XenonLock, Settings Low GFX,
  StandFarm, and private WHITE AI separation. Requires Delta/YBA runtime validation.

## Native Low GFX input compatibility — 2026-10-18 (Settings R4)

- Prefers one bound connection:Fire or Function input over firesignal for the
  known native button. Multiple handlers still require one signal dispatch.
- Reproduced offline: a no-op firesignal shadows a working bound connection in
  R3. This is compatible with the owner's symptom, not proof of Delta's cause.
- Logs route/handler count before the native request and prior state when a
  repeated request is blocked. Issued guards also survive module redownload for
  the same HUD. No automatic retry after a dispatched call.
- Native Delta activation remains unconfirmed. Only Settings runtime changed;
  Merchant, farms, combat and backend remain unchanged.
- 42 Settings and 9 public-packaging checks passed offline; live retest pending.

## Native YBA Low GFX beta — 2026-10-18 (Settings R3)

- Low graphics retains local quality/effect reduction and attempts the observed
  native Settings/List/ToggleLowGFX/Button action once per HUD.
- Requires the exact known button/label and an inspectable click binding; no
  guessed remotes. Bounded UI/result waits, OFF/reload guards, no retry after an
  issued action, and explicit unsupported/unconfirmed status.
- Native changes may persist after OFF and may require a rejoin to undo. A
  disappearing control acknowledges the UI action; it does not prove FPS gains.
- Runtime change is isolated to Settings.lua. Merchant, pickup, combat, Stand
  Farm, Auto Prestige, loaders and private WHITE AI distribution are unchanged.
- 46 offline Settings/packaging checks passed on the identical module. Native
  activation through Delta is still pending; owner authorized this public beta.

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
