# R8 optional restock hop — NOT VALIDATED IN ROBLOX

Build: `SF-RESTOCK-HOP-20261011-R8`. R7's local restock and consumable protections
remain; Hop After Restock Limit is an additional opt-in, default false.

## Behavior and limits

1. Auto Restock must be ON. Its existing current-server bound is still 90 seconds
   or eight collection attempts. Only that limit can trigger the optional hop;
   collection errors, cancellation, pending results or successful stock recovery
   do not trigger a transfer.
2. StandFarm checks character/Stand/skin/pity/dialogue/other-farm state before the
   hop and again after HTTP lookup, immediately before requesting teleport.
   StayInPrivateServer blocks the hop. Current JobId is skipped by guarded hops.
3. It turns consumption OFF, remembers only the missing item's name as a restart
   notice, and requests at most ONE teleport per manually started run. No sale,
   purchase, auto-loader queue or automatic item activation is performed.
4. After joining, load DevMain as usual and manually enable the beta. Config file
   persistence is needed to retain the reminder; the reminder is not a resume
   command and cannot authorize consumption. Start reruns all safety checks.
5. Hop returning true means a teleport request was submitted, NOT that arrival was
   confirmed. Failed/no-destination lookup leaves the beta off. A server query
   can still be in flight after Stop; new Start waits until it returns. There is
   no fabricated network timeout/arrival detector in this release.
6. CANCEL RESTOCK TRANSFER / STOP remains available when the beta toggle is off.
   Cancellation before submission prevents teleport after a delayed HTTP query.
   A teleport already submitted to Roblox may still complete.

## Delta owner test

- Fresh DevMain boot, confirm R8. Keep Item/Quest/NPC Farm, Auto Sell and Prestige
  OFF. Start with None or an unwanted non-skin Stand, low pity budget and limited
  stock. Shiny-specific stopping still awaits natural in-game evidence.
- Enable Auto Restock and Hop After Restock Limit. Choose a missing consumable
  with no eligible spawn. Verify the normal local wait happens first, consumption
  stops, and only one transfer is requested. Check actual arrival manually.
- In the destination, verify the beta is OFF, inspect Stand/skin/pity/inventory,
  load DevMain if necessary and manually restart. No automatic AFK continuation
  across servers is claimed.
- Test cancellation using the dedicated button during lookup, before teleport
  submission. Expect no late transfer from a cancelled lookup. Capture logs.
- With StayInPrivateServer ON, with Hop OFF, or with successful local stock pickup,
  verify no restock transfer is requested.
- Repeat ordinary manual Server Hop and R7 local restock with the new option OFF.
  Unguarded/manual hop API and delayed camera cleanup remain backward compatible.

Offline: eleven tests execute the actual Lua modules with mocked HTTP/teleport,
including delayed Stop, unknown skin, pity/character/dialogue/competing-farm
changes, private preference, unsuccessful destination, UI cancellation, legacy
camera behavior, concurrent hop rejection and reload staying off. Not equivalent to Delta/YBA validation.

Rollback Config.lua, StandFarm.lua, ServerHop.lua and UI.lua from
`4cc8b0f8ac84b7bc69a4252aea6cb1f8234c0e1a` using a new dev commit. Preserve AI
incident/proposal history. Checkpoint: `c1c0dae6528f308fba61eabc0dc38a46a7679145`.
Inventory, CombatFarm, Farm, loaders and backend are unchanged. No Render deploy.
