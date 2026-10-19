# WHITE HUB — Public Beta

Modular YBA hub by WHITE DRAGON. Compact Silver interface, English controls
and a copyable runtime Console. The public Main.lua entry point stays the same
across feature and UI updates. The permanent public loader is hosted in WHITE-HUB.

### Halloween Jack fix (2026-10-18)

Event Turn-In uses a verified live Jack ProximityPrompt and checks the real Option2
before submitting. Auto event trades return the player to the pre-transaction
position. Auto Buy remains locked until a trusted event-point balance is available.
The console shows candidate point-stat labels when no trusted balance is found.
No purchase is attempted on an unverified balance.

## Loader

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/WHITEDRAGONx/WHITE-HUB/main/Main.lua"))()
```

Start in a fresh YBA session. Check Credits/Console for
`SILVER-V5-PUBLIC-20261018-DEV-SYNC-R5`. Open the WHITE HUB launcher to configure modes.
Settings persist in WhiteHubConfig.json when filesystem APIs are available.

Tap Stands or Skins, search and check/uncheck names to edit your selection.
The skin catalog reads recognized client containers and confirmed farm results,
refreshes public Trello skin titles automatically and keeps a six-hour data cache.
A fixed fallback combines 461 distinct Trello/Xenon names and aliases;
entries do not guarantee current obtainability or Arrow/Rib eligibility. Every
skin is protected, even when unselected. The Quest selector prioritizes names detected in the game, using documented
extras when client dialogue objects are unavailable. Unmapped quests appear as INFO when their objectives are not mapped; these entries
cannot replace your current automated quest.

## Requirements

- Access to the current YBA experience with an eligible Roblox account.
- An executor supporting `loadstring`, `game:HttpGet`, `getgenv` and the Roblox
  APIs used by the hub. Executor compatibility can vary; Delta is the primary
  owner-tested environment.
- HTTPS access to GitHub raw files. Skin catalog online refresh also uses the
  public Trello API; fixed names remain available when Trello is unreachable.
- Filesystem APIs (`isfile`, `readfile`, `writefile`) for saved settings.
- Optional owned-hop resume additionally needs a supported teleport queue API.
- Fast dialogue paths depend on executor capabilities and may use fallbacks.

Auto Prestige and Stand features remain beta. Use one character-controlling farm
at a time; Auto Sell can remain ON while Stand Farm runs with Item Farm OFF.

## Features

- Item Farm, item sell/keep selection and the existing Merchant workflow.
- **Events Items Farm** in Events (directly below Farm): exclusive opt-in pickup
  of Yellow, Blue, Green and Red Candy using the normal inventory-confirmed collector.
  Event mode does not trigger Merchant sales or Lucky purchases; a dry server can
  hop without selling/buying unless Stay in Private Server is enabled.
- Halloween reward preview/wishlist based on observed Jack menus, with prices.
  Auto Turn-In is opt-in and runs at serialized farm/event checkpoints or while
  both item farms are OFF, provided no competing worker owns the character.
  Auto Buy is a single explicit purchase attempt only with readable event points
  and the exact item/category selected; unknown confirmations cause a safe stop.
  Buy authorization is not persisted across reloads. Live YBA verification pending.
- Quest/NPC Farm, manual or automatic quest selection and configurable skills.
- Stand/Shiny/Rib beta: searchable touch selection for Stands and skins, skin
  preservation, pity limit and session stats.
- Consumable restock bounded to 25 seconds/eight attempts, with optional owned-hop
  continuation and preserved skin, pity and inventory checks.
- Classic server hop by default; optional Clean Hop selects a distinct server
  and releases old-runtime workers after transfer begins.
- Auto Prestige beta: updated dialogue and character lifecycle handling.
- Webhook notifications, manual server hop and runtime diagnostics.
- Stand/Shiny/Rib terminal webhook: target found, any detected skin preserved,
  or automatic stop, with source, pity, confirmed rolls and reason.
- Settings: saved 30 FPS cap, low graphics and black screen options.

Stand features and Auto Prestige are experimental. Auto Prestige has passed
offline tests but its complete progression has not been validated in YBA. An
unknown quest origin or unresolved result may stop the routine. Executor support
and game updates can affect behavior. A syntax test is not proof of live behavior.

## Settings

Open **Settings** to enable **Cap FPS at 30**, **Low graphics** or **Black screen**.
They start OFF. Saved FPS/graphics choices apply on the next load where supported.
Black screen requires manual enable each load. They do not enable or stop a farm.

The FPS setting uses the executor's cap API and restores the prior cap on OFF.
If the prior cap cannot be read, OFF returns to 60 FPS; the status says so.
Low graphics requests quality level 1, disables shadows and reduces local
particles, trails, beams and post effects. Disabling it restores the values
changed by the hub, preserving values subsequently changed elsewhere.

Low graphics also attempts the native YBA **TOGGLE LOW GFX** action once per HUD,
using the exact known control and an inspectable click handler. This is an
experimental integration (`SETTINGS-YBA-20261018-R4`), published at the owner's
request before live activation validation. Missing/unsupported native input
keeps the local quality/effect options available. A request is never retried
automatically after dispatch. The native control disappeared after manual use
in the owner's test; a removed control is UI acknowledgement, not an FPS result.
Native YBA changes may require rejoining to undo. OFF restores only the hub's
recorded local properties. Check `[NativeLowGFX]` in Console and report results.
R4 prefers the unique bound connection input over `firesignal` and records the
dispatch route/handler count. An issued-request guard survives module reloads
for the same HUD. The R3 live attempt was unconfirmed; R4 needs a Delta retest.

Black screen draws a visual cover and keeps 3D rendering running. Native renderer
control was removed after a tester reported delay/crash; the cause is not confirmed
by a crash trace. WHITE HUB controls and **SHOW GAME** stay accessible. A saved
black-screen preference is cleared on load, so this mode requires manual enable.
The cover does not release game memory or promise lower graphics load. FPS/low
graphics are the separate performance options. Delta retesting is still required.

These options passed offline checks; executor support and actual YBA behavior
still require Delta testing. See the current build in Console before testing.

## Beta testing

Pickup compatibility hotfix (2026-10-14): after a tester reported a moderation
kick during item teleport, the faster pickup cadence was withdrawn. New spawns
wait one second, pickup settles for 350 ms, fires once and waits 150 ms after
returning. Normal cycles and dry-server timing are restored to 1s/20s. Inventory
confirmation, cancellation and cleanup remain; a despawn alone is not collection.
Merchant keeps the proven Option1/Option1/Option6 flow, using a live button index
and frame-paced advancement. Server-list preparation overlaps automatic selling.
The historical 0.70-second Delta sale is not a current timing guarantee. Check
SALE-20261014-R1 / PICKUP-COMPAT-20261014-R2 in Console and copy SALE after a test.
Auto Rejoin waits for a visible completed disconnect prompt and attempts one
native rejoin per runtime. It does not restart the script, suppress moderation
or retry indefinitely. Native rejoin and the kick rollback need a live retest.

Configure your own Discord URL in **Webhook** and save it. Stand/Shiny/Rib uses
that same URL automatically. It sends one asynchronous notification per completed
run, not per roll. Manual Stop, reload and an active restock transfer do not send
terminal notifications. An unknown skin is reported as unknown, never as a shiny.
Delivery failures do not change the result or retry; check Console for a sanitized
HTTP status. Actual Discord delivery through Delta still needs a live test.

Choose one farm at a time. Auto Sell may stay ON during Stand/Shiny/Rib Farm
when Item Farm is OFF. Restock collects consumables without selling. A finishing
Item Farm action or sale must complete before Stand Farm can start.

Stand/Shiny mode protects detected skins and stops when
skin identification is inconclusive. Configure obtainable targets, sufficient
Worthiness and a pity limit. An explicitly saved ON Stand Farm choice is restored
after player readiness through the normal guarded startup; Stop clears it.
Owned restock-hop continuation additionally requires supported executor APIs,
the resume option and a valid one-use transfer from this hub.

For Auto Prestige, turn off the other farms and enable **Auto prestige (BETA)**.
Observe level, prestige and current quest. Test on a disposable account with
items you can afford to use. YBA account-entry requirements can prevent a new
account from joining before it becomes eligible.

If a routine stalls, press Stop and copy the complete Console log before reload.
Report build, executor, chosen mode, steps, expected/actual behavior and counts
before/after. Record a short video if possible. Never send secret keys, webhook
URLs or device session files. Do not repeatedly re-enable a pending consumable.

See [CHANGELOG.md](CHANGELOG.md) and [RELEASE_AUDIT.md](RELEASE_AUDIT.md) for changes,
source comparison and current validation limits.

Discord: https://discord.gg/j3C4Xa6DzN

## Module organization

UIComponents.lua groups layout, searchable selectors and Stand controls.
GameCatalog.lua owns local names, online refresh and cache lifecycle.
AutoPrestigeRuntime.lua owns execution and the scoped prestige dialogue driver;
AutoPrestige.lua retains progression. Combat remains in CombatFarm.lua.
The public package now has 18 Lua files and 17 boot downloads. Gameplay and
Merchant behavior are unchanged by this packaging update. See MODULE_CONSOLIDATION.md.
