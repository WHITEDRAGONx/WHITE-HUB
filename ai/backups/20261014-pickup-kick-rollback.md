# Pickup kick regression checkpoint — 2026-10-14

Pre-change main: 736f3fd7018c4907df3a1bbc5e4a29fbd3c450c4
Pre-change dev: 3d1273fe867ee768ec70380b850323297db2b783
Historical movement/pickup cadence: b7a1a7c96c34dd2350a4165e27496f96b77af3b3

Owner supplied tester report of a kick when teleporting to an item after the speed update. Screenshot: 'No exploiting! (bruh)', Error Code 267. Timing causality is unconfirmed; no runtime log or independent reproduction was supplied.

Emergency scope: withdraw the earlier/duplicate pickup prompt and faster normal movement cadence in Farm.lua. Restore 350ms settle, one prompt per pickup, 150ms post-return, 1s normal cycles/new spawn delay, and the historical 20s dry window. Retain actual inventory confirmation, character/cancellation guards and cleanup. Keep Inventory sale optimization, ServerHop read-only preparation, UI, combat, Stand safeguards and backend unchanged. Do not add detection bypasses, stealth, or kick suppression.

Rollback is a new scoped commit restoring the previous Farm.lua only if deliberately reauthorized after live diagnosis. Preserve both branch histories. This compatibility rollback is not proof the game's kick condition is resolved. Ask tester for one fresh-session trace and stop further attempts if the same moderation kick recurs.
