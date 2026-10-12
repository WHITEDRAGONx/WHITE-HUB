# Compact Silver V5 — Delta visual QA

Experimental build: SILVER-V5-20261012-R1. Dev branch only.
Baseline: 0cb6b60e1631489ba8166b2f2f74b975b08a8351.
Rollback checkpoint: 64f9fa8180cbbd1be02c50065cb5ebbb07451ddb.

The owner requested a small silver/off-white UI, English text and controls
organized by type. The window is 380 x 290 before viewport scaling. Toggles and
dropdowns use fixed text sizes. Stand/Shiny/Rib have a separate Stand tab; switches,
fields, actions and status are grouped within their original sections. Existing
control objects, callbacks and config keys remain. WHITE AI changes translate
client status strings only. Main, Inventory, combat, consumables, progression,
server switching and backend are unchanged. Smart Farm Engine remains removed.
No Render deploy is required.

Offline validation covers Luau parsing, grouping and stable order, retained
callbacks/keys, viewport scaling, content heights, English literals and protected
source equality. These mocks do not render Roblox and are not Delta evidence.

## Native visual check

1. Start DevMain in a fresh Delta session. Confirm UICompact boot and
   SILVER-V5-20261012-R1 in Console. Keep farms and consumables disabled initially.
2. Open and close the launcher repeatedly. Check the silver palette, compact
   centered panel, subtle animation, readable English labels and all eight tabs.
3. In landscape and portrait, rotate/resize while open. Check that the panel stays
   within the viewport, text remains readable and scroll reaches the last control.
4. Check Farm, Stand, Items, Combat and AI DEBUG: switches together, fields
   together and actions together. Long dropdown values may truncate on the button;
   open the list to read/select the full value. Verify menus remain selectable.
5. With farms disabled, change and restore non-destructive saved selections and
   verify the displayed values. Check popup, console filters/copy, webhook field
   and Credits. Do not press hop, consume or pair using test credentials.
6. Only after visual checks, follow each existing farm QA guide using disposable
   items. A visual redesign does not validate consumption, skin protection or AP.
7. Send a screenshot/video plus build and runtime log if controls overlap, disappear,
   clip or fail to react. Never include device session files or secret keys.

## Separate runtime finding

The owner's latest video shows an Arrow dialogue stalled with a pending result.
This package deliberately leaves the dialogue and pending guard untouched. That
failure needs its own full runtime log and reproduction; do not clear the guard
or repeatedly consume items to test UI styling.
