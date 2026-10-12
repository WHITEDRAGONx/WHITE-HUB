# WHITE HUB — Public Beta

Modular YBA hub by WHITE DRAGON. Compact Silver interface, English controls
and a copyable runtime Console. The public Main.lua entry point stays the same
across feature and UI updates. The permanent public loader is hosted in WHITE-HUB.

## Loader

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/WHITEDRAGONx/WHITE-HUB/main/Main.lua"))()
```

Start in a fresh YBA session. Check Credits/Console for
`SILVER-V5-PUBLIC-BETA-20261012-R3`. Open the WHITE HUB launcher to configure modes.
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

Stand features and Auto Prestige are experimental. Auto Prestige has passed
offline tests but its complete progression has not been validated in YBA. An
unknown quest origin or unresolved result may stop the routine. Executor support
and game updates can affect behavior. A syntax test is not proof of live behavior.

## Beta testing

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

Discord: https://discord.gg/Qwd23ZRNxJ

## Development

Use DevMain.lua on dev/2026-10-10-autosell-compat for owner testing. Private
development diagnostics remain outside the public module package.
