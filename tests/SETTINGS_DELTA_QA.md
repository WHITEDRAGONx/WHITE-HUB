# Settings — Delta validation

Experimental: SILVER-V5-20261013-R4. Public: SILVER-V5-PUBLIC-BETA-20261013-R4.
Current Settings beta: SETTINGS-YBA-20261018-R4 (native Low GFX request).
Black screen retains the visual-only behaviour of SETTINGS-BLACK-20261013-R2.
Offline results do not validate Roblox or the executor.

## Native YBA Low GFX experiment — owner-authorized public beta

Owner R4 OFF/ON captures identify the exact native click control:
`PlayerGui/HUD/Main/Frames/Settings/List/ToggleLowGFX/Button`, a TextButton
labelled `TOGGLE LOW GFX`. The row and button disappear after manual activation;
this is observed UI behaviour, not a reversible boolean flag or an FPS benchmark.

1. Rejoin YBA for a fresh native button. Use the public or dev loader and confirm
   SETTINGS-YBA-20261018-R4. Keep other farms OFF for this short check.
2. Ensure native Low GFX was not already used. Open the hub's Settings and enable
   Low graphics once. The adapter waits up to ten seconds for the native menu,
   verifies the exact path/label and a bound MouseButton1Click handler, and
   issues at most one native click per HUD. It never guesses a remote.
3. Check `[NativeLowGFX]` in Console. `control_removed` means the same native
   List remains but its Low GFX row disappeared after our request. Verify actual
   graphics yourself. `unconfirmed`/`failed` never trigger another input.
4. OFF restores the hub's recorded local quality/effects only. Native YBA
   modifications may remain until rejoining. OFF/ON or reloading the hub must
   not issue a second click against the same HUD. Capture both results.
5. If the native button was already removed, no native click occurs. If the
   executor cannot inspect/fire its handler, the status explains that local
   effects still apply. No unrelated settings, farms or dialogs are touched.
6. OFF or reload while waiting for delayed UI must cancel the old request. An
   already issued game callback cannot be recalled; we do not claim otherwise.

Native request/visual result through Delta remains unvalidated until owner
returns a fresh runtime log. On 2026-10-18 the owner explicitly requested main
publication before live activation validation. The identical module passed
37 Settings and 9 public-packaging checks offline; these do not replace Delta QA.

R4 follow-up: the owner loaded R3 but its saved-ON attempt was unconfirmed;
OFF/ON then showed only the issued-request guard. R4 logs its dispatch route
immediately and prefers a unique connection:Fire/Function over firesignal.
An offline no-op firesignal case fails against R3 and passes against R4; it is
a reproduced possible failure mode, not proof of the executor's actual cause.
Rejoin for a fresh HUD/request guard, enable Low graphics once, wait ten seconds
without toggling OFF/ON and copy Console. Expect a route/handler log and either
control-removed acknowledgement or a specific unsupported/failed/unconfirmed
result. Full module redownload on the same HUD must not repeat an issued call.
R4 offline verification: 42 Settings plus 9 packaging checks passed. No live
success claim follows from these checks.

A tester reported delay/crash with the original Black screen. The R2 module
removes native renderer control; the cause is not confirmed by a crash trace.
Close Roblox and start a fresh Delta/YBA session before retesting, so an old
paused renderer or old client hooks do not contaminate the result.

## Small test sequence

1. Fresh session, existing loader. Open Settings and confirm all three options
   are OFF in a new configuration. Confirm every tab is accessible by scrolling
   the sidebar on phone, including Credits and dev-only AI DEBUG.
2. Record the existing FPS limit. Enable Cap FPS at 30, then OFF and confirm the
   prior limit returns. Compare actual FPS using the executor's display. If the
   prior cap is unreadable, the status specifies a 60 FPS restore. Unsupported
   or failed APIs must show a message rather than fail boot.
3. Record the Roblox quality setting and a visible effect. Enable Low graphics,
   then OFF. Confirm quality/effects restore. Test respawn and newly spawned
   effects while ON. Check that quest, inventory and item models remain available.
4. Enable Black screen. Confirm the launcher, Settings and SHOW GAME are usable
   with touch and mouse. Tap SHOW GAME; verify the image returns and the toggle
   turns OFF. Status must say visual only; the module must never pause the renderer.
5. Save FPS/graphics ON and black screen ON, re-execute the loader once. FPS/graphics
   should reapply; black screen must start OFF and clear its saved ON preference.
   Confirm there are no duplicate recovery buttons/listeners. Turn options OFF.
6. Run Item Farm or one supported quest briefly, enable/disable settings, and
   confirm collection/dialogue/credit continue. Check Merchant with Black screen
   both ON and OFF before declaring all fast/fallback dialogue paths compatible.
7. Observe FPS, RAM and temperature over a comparable interval, same server and
   mode, with options OFF/ON. Record measurements instead of claiming that a
   black overlay by itself releases RAM.

Copy the Console log with the Settings messages if an API/restore fails.
SHOW GAME removes the visual cover; cleanup disconnects its button and removes
the cover. No renderer API, frame polling or per-frame scan is used by Black screen.

## Protected scope

Pre-change dev: c33ea596c8ec87d64d7809f87abc0cab57f1b76f.
Reconciled pre-change public: 652db568857e2c58c9fa3978ac0925db782e429d.
Checkpoint: 08e2ba0014dd18030b961e6676dad0d99f17a52c.
Inventory, CombatFarm, StandFarm, Farm and AutoPrestige sources are unchanged by
this update. Public promotion preserves the existing public SELL NOW, Console
Follow/Copy SALE and newer Merchant/Farm changes byte-for-byte where untouched.

R2 hotfix pre-change dev: 5812b9859ffe27396ea6f160b86a910369622105.
R2 hotfix pre-change public: 22d16af1e34f4301cfea4ecb385e2c729c40f060.

## Existing restock / Auto Sell requests from the same tester

Stand > Auto restock is already the opt-in stock replenishment feature. With Item
Farm OFF and a common unprotected Stand, missing Arrow/Roka/Rib is delegated to
Farm.Restock. It searches the current server for up to 90s/eight pickup attempts.
An enabled Restock hop may transfer if stock cannot be obtained; continuation also
requires Resume owned hop and compatible executor teleport/file APIs. Skin/pity,
pending-result, character and stop guards are preserved. This hotfix adds no new
restock implementation and makes no new live-validation claim.

For Auto Sell speed, reproduce one SELL NOW with Black screen OFF, then copy
Console > Copy SALE after a completed SellPerf END. Include executor, sold item
types/counts, duration, stageWaitMs and gcScans if present. Compare settings only
one at a time. Do not guess that all latency comes from one module.
