# Changelog

## Permanent WHITE HUB loader — 2026-10-12

Public installation now uses WHITE-HUB/main/Loader.lua, a versionless entry point
that forwards to the current public modular release. Existing repository history
and legacy source are preserved. README requirements updated. 307 offline checks
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
