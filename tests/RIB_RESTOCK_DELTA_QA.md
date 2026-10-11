# R7 Rib / auto-restock beta — NOT VALIDATED IN ROBLOX

Current build is R8; keep Hop After Restock Limit OFF for the R7 procedures below.
Optional guarded server transfer and manual restart are covered in
RESTOCK_HOP_DELTA_QA.md. The Farm.lua local restock API itself still never hops.

The same StandFarm worker handles Arrow/Rib, target lists and Shiny mode. No
Xenon code is imported. Inventory.lua, Merchant and XenonLock are unchanged.
Config.lua, StandFarm.lua, UI.lua and a small Farm.lua handoff are in scope.

## Controls and limits

- Build: `SF-RIB-RESTOCK-20261011-R7` in Console after DevMain cold start.
- Stand consumable: Mysterious Arrow or Rib Cage of The Saint's Corpse.
- Shiny mode OFF: stop on selected Stand(s). ON: stop on any detected skin,
  ignoring common target names. Unknown skin lookup always preserves the Stand.
- Auto Restock Consumables is opt-in, default false. Keep Item Farm, Auto Sell,
  Quest/NPC Farm and Auto Prestige OFF; the API does not enable normal phases.
- A missing roll item is checked BEFORE Roka, preventing a reset without stock.
- Restock collects ONE unit of only the missing Arrow/Rib/Roka on the current
  server, verifies actual inventory/tool presence, returns to the safe spot and
  rechecks Stand/skin/pity before consumption. Cache refresh is bounded to 1 Hz.
- Maximum 90 seconds or 8 collection attempts per request. No sale, purchase,
  restock hop, persisted item-filter change or auto-start after reload.
- Rib uses EXISTING Worthiness. Allocate the game's required skills manually
  before starting. The Arrow's existing LearnSkill request is not assumed to
  prepare Rib; no unverified higher-level skill allocation is implemented.
- Select results actually obtainable from the chosen source. The shared list
  does not promise every Stand is obtainable from Arrow or Rib.

## Delta owner procedure

1. Fresh DevMain session; confirm R7 and clean module boot. Close other dialogues.
2. First test Rib with restock OFF, Shiny OFF, empty Stand slot, one Rib and
   manually prepared Worthiness. Select a known Rib result you want to keep.
   Verify exactly one Rib activation and confirmation by PlayerStats.Stand.
3. With limited Ribs/Rokas and only an unwanted non-skin Stand, test continuation
   through Roka -> None -> NEW Character -> safe spot -> next Rib. Stop on target.
   Do not use a valuable Stand or skin as a destructive test fixture.
4. Restock test: enable Auto Restock, keep other farms OFF, deliberately lack ONE
   consumable while it exists in workspace.Item_Spawns.Items. Start and expect
   `Restock handoff`, one matching collection, `Restock confirmed`, safe spot,
   then the normal state/skin/pity checks before another item is activated.
   Repeat separately for Arrow, Roka and Rib. Other items must not be collected.
5. With no matching spawn, verify it waits and stops at the bound without consuming
   the currently owned Stand. No automatic server hop is part of this beta.
6. Press Stop during restock before pickup, during dialogue and while waiting for
   an item result. No later prompt or item input may be issued by that run. A
   request already sent to the game can still complete; uncertain consumption
   continues to block Start. Freeze/noclip cleanup must occur.
7. Test a competing farm activation, death/respawn or unrelated dialogue during
   restock: it must cancel, not resume consumption blindly. Restart manually only
   after the actual Stand, dialogue and inventory are verified.
8. Regression: disable Auto Restock, select Arrow, and repeat the observed R5 target
   list behavior. Shiny/skin/pity safeguards from STAND_FARM_DELTA_QA.md still apply.
   Run ordinary Item Farm briefly, confirming collection and Stop still work.

Export Console and record source, mode, Stand/skin, pity, before/after consumable
counts, prompt/respawn sequence and Delta platform/version. Never include keys,
webhooks or WHITE_AI_DEVICE_SESSION.json.

## Offline evidence / rollback

Actual Lua runs in mocked scheduler/UI/prompt/inventory tests. New cases cover
Rib result/respawn, pending-result lock, wrong source, bounded stock recovery,
despawn without inventory, skin changes, cancellation and cleanup, normal Item
Farm collection, and waiting for an actual normal cycle before handoff. These
do NOT emulate YBA dialogue semantics, Worthiness rules or Delta delivery.

Rollback the four runtime files from `f066809a2b0d5af0f9473af77bd3f7dbefabd989`
using a new dev commit; preserve AI incident/proposal history. Checkpoint:
`726f90a034944a3b42ff658b93e3e8287adb44e5`. No Render deployment for this slice.
