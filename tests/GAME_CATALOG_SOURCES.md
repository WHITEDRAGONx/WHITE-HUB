# Game catalog provenance — 2026-10-12

Public API reads succeeded for the primary and secondary YBA boards:

- https://trello.com/b/nV2ngLeZ/yba-primary-board
- https://trello.com/b/ROfFdASc/yba-secondary-board

Only card titles were retained: 236 distinct titles from Stand Skins lists, and 34 from Quests/Stand Quests/Story Quests. Item skins, cosmetics, prices, descriptions, images, webhooks and third-party code are excluded. A title does not establish present obtainability, arrow/rib eligibility or the exact server-returned alias. All skins, including unselected/unknown skins, remain protected. Saved/observed names are preserved as exact options.

Snapshot title hashes (UTF-8 sorted JSON):

- Skins: b540e605aed02433ac7299c5909c6fc3c7fd80b39e8d70166165c400593f63ca
- Quests: 6e2967c2a632acf1e25eb833a1eee1d9543b1f6822a765e5fd328ef54a9ccaee

Uploaded Xenon was inspected as text only. Its 378 skin candidates were not imported; network/hooks and external webhook handlers were not executed or copied. Its quest map covered the same basic objectives and does not validate the other discovered quests.

Runtime discovery reads names of bounded children in workspace.Dialogues and ReplicatedStorage.NewDialogue, and known skin containers; no game ModuleScript is required, edited or decompiled. Undocumented quests are shown as INFO and cannot become SelectedQuest. CombatFarm mappings, Auto Choose Vampire priority and XenonLock are unchanged. Native game schema/aliases still need Delta logs.

## Owner-requested automatic catalog R3

The owner subsequently authorized importing the fixed Xenon names as fallback.
Only its 378 quoted AllShinys entries were extracted as strings; combining them
with the 236 Trello titles yields 461 distinct names/aliases. No handlers, hooks,
network code or webhooks were imported. This historical alias set is not a claim
of obtainability or completeness.

CatalogRefresh now reads two fixed public Trello API JSON endpoints (list names
and card names/idList), accepts only Stand Skins lists and updates a names-only
cache every six hours. Responses are limited to 250 KB, 128 lists/1000 cards,
validated names and a ten-second result window. HTTP APIs may not support request
cancellation; timed-out/old-runtime responses cannot modify cache. No concurrent
refresh worker or immediate retry storm. Epoch checks and Destroy cancel schedules.
No credentials/player data are sent. Cache uses SkinCatalogCache in existing config.

Skin discovery remains bounded to named client containers (256 processed objects),
StringValue data and an already confirmed StandFarm metrics.lastSkin. No heap scan,
require of game scripts or added ReturnStandSkin RPC. Quest detection is attempted
on each menu open, using static documented extras only if no quest names appear.
Actual client schema must still be verified in Delta; no full game-file extraction
or guarantee that every newly released skin is exposed is claimed.
