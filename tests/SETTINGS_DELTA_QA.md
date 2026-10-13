# Settings — Delta validation

Experimental: SILVER-V5-20261013-R4. Public: SILVER-V5-PUBLIC-BETA-20261013-R4.
Offline results do not validate Roblox or the executor.

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
   turns OFF. If only the view can be hidden, status must say rendering stays ON.
5. Save each setting ON, re-execute the loader once and check that it reapplies,
   without duplicate recovery buttons or leaked listeners. Turn them OFF again.
6. Run Item Farm or one supported quest briefly, enable/disable settings, and
   confirm collection/dialogue/credit continue. Check Merchant with Black screen
   both ON and OFF before declaring all fast/fallback dialogue paths compatible.
7. Observe FPS, RAM and temperature over a comparable interval, same server and
   mode, with options OFF/ON. Record measurements instead of claiming that a
   black overlay by itself releases RAM.

Copy the Console log with the Settings messages if an API/restore fails.
SHOW GAME remains available to retry a failed render resume, even if runtime
cleanup has begun. No repeated scan or frame polling is used by Settings.

## Protected scope

Pre-change dev: c33ea596c8ec87d64d7809f87abc0cab57f1b76f.
Reconciled pre-change public: 652db568857e2c58c9fa3978ac0925db782e429d.
Checkpoint: 08e2ba0014dd18030b961e6676dad0d99f17a52c.
Inventory, CombatFarm, StandFarm, Farm and AutoPrestige sources are unchanged by
this update. Public promotion preserves the existing public SELL NOW, Console
Follow/Copy SALE and newer Merchant/Farm changes byte-for-byte where untouched.
