# WHITE HUB — Public Beta

Modular YBA hub by WHITE DRAGON. Compact Silver interface, English controls
and a copyable runtime Console. The public Main.lua entry point stays the same
across feature and UI updates. The permanent public loader is hosted in WHITE-HUB.

## Loader

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/WHITEDRAGONx/WHITE-HUB/main/Main.lua"))()
```

Start in a fresh YBA session. Check Credits/Console for
`SILVER-V5-PUBLIC-BETA-20261013-R4`. Open the WHITE HUB launcher to configure modes.
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
- Quest/NPC Farm, manual or automatic quest selection and configurable skills.
- Stand/Shiny/Rib beta: searchable touch selection for Stands and skins, skin
  preservation, pity limit and session stats.
- Bounded consumable restock and optional owned-hop continuation.
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
They start OFF; saved FPS/graphics choices apply on the next load where supported.
The FPS cap restores its prior value (or an explicit 60 FPS fallback when unreadable).
Low mode reduces quality, shadows and local visual effects without deleting models.
Black screen now uses only a visual cover and must be enabled manually each load.
Hub controls and **SHOW GAME** stay accessible. Disabling/reloading restores the values owned
by Settings. RAM/temperature savings and actual Delta compatibility are unverified.

Settings beta (`SETTINGS-YBA-20261018-R4`): enabling Low graphics
also requests the existing native YBA **TOGGLE LOW GFX** click once per HUD,
when the exact known control and an inspectable handler are available. Local
quality/effects still apply when native input is unavailable. The owner's manual
test removes this control after use; native changes may require a rejoin to undo.
OFF restores only local properties owned by the hub. A removed native control is
UI acknowledgement, not proof of graphics improvement. Live activation by the
loader is pending; the owner authorized publishing this experimental option to
main before live activation validation. See `[NativeLowGFX]` in Console.
R4 prefers the single bound connection input over `firesignal`, logs the route
and handler count at dispatch, and retains issued-request guards across module
reloads for the same HUD. Actual Delta activation still needs a live retest.

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
Worthiness and a pity limit. Restock/hop/resume are optional; ordinary reload does
not automatically restart Stand consumption. The optional resume requires the
supported executor APIs and a valid one-use transfer from this hub.

For Auto Prestige, turn off the other farms and enable **Auto prestige (BETA)**.
Observe level, prestige and current quest. Test on a disposable account with
items you can afford to use. YBA account-entry requirements can prevent a new
account from joining before it becomes eligible.

If a routine stalls, press Stop and copy the complete Console log before reload.
Report build, executor, chosen mode, steps, expected/actual behavior and counts
before/after. Record a short video if possible. Never send secret keys, webhook
URLs or device session files. Do not repeatedly re-enable a pending consumable.

See [CHANGELOG.md](CHANGELOG.md) for changes and current limitations.

Discord: https://discord.gg/j3C4Xa6DzN

## Development

Use DevMain.lua on dev/2026-10-10-autosell-compat for owner testing. Private
development diagnostics remain outside the public module package.

## Module organization

UIComponents.lua groups layout, searchable selectors and Stand controls.
GameCatalog.lua owns local names, online refresh and cache lifecycle.
AutoPrestigeRuntime.lua owns execution and the scoped prestige dialogue driver;
AutoPrestige.lua retains progression. Combat remains in CombatFarm.lua.
The public package now has 18 Lua files and 17 boot downloads. Gameplay and
Merchant behavior are unchanged by this packaging update. See MODULE_CONSOLIDATION.md.
