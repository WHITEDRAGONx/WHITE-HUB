# Stand Farm beta — current Shiny R6 / target-list R5 / dialogue speed R4

## R6 Shiny mode (not validated in Roblox)

Confirm `SF-SHINY-20261011-R6` after loading DevMain. R6 uses the same Stand Farm
worker, dialogue driver and consumption locks; no parallel Shiny worker exists.
`Shiny Farm Mode (BETA)` selects the mode; `Stand Farm (BETA)` starts/stops it.
Default mode is stand. Reload keeps the preference but never starts consumption.

1. Disable Item/Quest/NPC Farm, Auto Prestige and Auto Sell; close old dialogues.
2. Start only with None or a common Stand you explicitly accept replacing. Set a
   small pity budget and limited stock. Shiny mode IGNORES the Stand target list,
   and can replace a common Cream/Aerosmith even when it is a desired Stand.
3. Enable Shiny Farm Mode, then Stand Farm. Expect `Searching for ANY skin`.
   No Stand selection is required. It uses only Mysterious Arrow and Rokakaka.
4. Confirm normal results continue through verified Roka/NEW Character/safe spot.
   Any detected skin must stop the farm without another Roka. Missing/invalid,
   empty or timed-out skin lookup must also stop and preserve the current Stand.
   Only the exact existing game response `None` authorizes replacement.
5. With an already owned skin, Start must refuse without consumption. Do not
   risk a valuable skin to stress-test this beta. Keep the result if detection
   is uncertain; never bypass it by repeated reloads.
6. Change modes during a controlled run and test Stop during dialogue, replication
   and skin lookup. Mode changes through UI stop first; an action already sent
   may still finish on the server. An uncertain result continues locking Start.
7. Confirm pity/stock/exclusivity safeguards and single/multiple target behavior
   with Shiny mode OFF. Export before/after Stand, skin, pity, stock and logs;
   never include session files or credentials.

Offline coverage: 13 new Shiny simulations, including late skin replication
while equipping Roka, config/mode guards, and cancellation. Actual YBA skin
replication and Delta behavior remain unverified. No skin-specific selection,
storage, Rib consumables or restock in R6.
Rollback runtime files to `6581f5840c371719b60fa607a4e8e057cafc361f` on dev using
a new commit. Preserve incident/proposal files. No Render deployment required.

## R5 observed owner runtime

The owner's Delta 1.0.739.687 log from 2026-10-11 13:50–13:52 showed selection
Aerosmith/Cream, Six Pistols then Stone Free then Cream, verified Roka resets,
NEW Character safe-spot recovery, and stopping on Cream with no later consumption
shown. No WARN/ERROR occurred in that supplied log. This validates those observed
R5 paths only; not Shiny R6, Stop, skin detection or pity edge cases.
Arrow input spans were 0.73–0.83s; Stand confirmation followed the last input by
8.48–8.56s. The log does not identify the source of that later game delay.

## Current R5 target-list test (not validated in Roblox)

Load DevMain in a fresh session and confirm the current R6 build in Console.
Keep Shiny mode OFF for the following target-list tests.
Keep all other farms, Auto Prestige and Auto Sell off; close existing dialogues.
Use only an empty Stand slot or a known unwanted non-skin Stand, with conservative
pity and consumable limits. The R4 speed protections and tests below still apply.

1. Choose Aerosmith in Target Stand and press ADD SELECTED STAND TO LIST.
2. Choose Cream and add it too. Confirm the label shows `Stop on ANY: Aerosmith, Cream`.
   A nonempty list overrides the single dropdown choice; it is not a priority queue.
3. Enable the beta. Check `Searching for` lists both targets. On either result,
   confirm the real Stand is preserved, no next Roka is used, and the toggle stops.
4. Test REMOVE for the selected entry and CLEAR LIST / USE SINGLE TARGET.
   Empty list must use the current dropdown target exactly as before. Reload with
   the farm off to verify settings persist without reactivating consumption.
5. Edit the list during a controlled run: it must stop immediately. Check no late
   inputs. A submitted item can still finish on the server; an unresolved result
   must continue blocking Start. Never clear that lock by repeated reloads.
6. Repeat Stop, skin/unknown-skin, pity, missing-stock and Roka/respawn tests below.
   Export logs plus before/after inventory, Stand and pity. Do not send session files.

R5 changes target selection only; it does not implement Rib, Shiny or restock.
The existing dropdown includes results from different sources; adding a result
does not make it obtainable from Mysterious Arrow. Use known Arrow results for QA.
Rollback R5 runtime files to `5a958f6a8c23813a759bd9512a176c6311ab89a1` on dev
with a new commit (Config.lua, StandFarm.lua, UI.lua). No Render redeploy is needed.

## Historical R4 dialogue baseline

R4 NOT VALIDATED IN ROBLOX. Offline: 40 simulated tests + 34 existing backend/static tests. R3 runtime 8bab0a5f confirms two rolls reaching Aerosmith across a Roka/respawn/safe-spot recovery, plus a later Whitesnake roll stopping on missing Roka. This does not validate all protections or R4 performance.
Adapts the existing quest fast Option1 selection and bound Continue handlers. Strict U[2] button-container checks gate U[1] selection. No GC scans or constant patches. Delta/mobile support must be measured in game.

## Delta test procedure (owner)

1. Load the existing DevMain.lua from dev/2026-10-10-autosell-compat in a fresh YBA session. Keep Stand Farm off until ready. Confirm the GOLD UI loads with no compilation/init errors. Current R5 uses SF-MULTI-20261011-R5; the R4 timing driver remains unchanged.
2. Disable Item Farm, Quest Farm, NPC Farm, Auto Prestige AND Auto Sell. Close all existing game dialogues. Keep the YBA dialogue area visible and unobstructed by the hub. Do not open other dialogues or use items manually during the run.
3. Arrow case: start with Stand=None, at least one Mysterious Arrow and enough Worthiness for normal manual use. Select Aerosmith; keep a conservative pity limit above current pity. Enable Stand Farm (BETA).
4. Watch Console for dialogue fast-option Option1 / connection-fire ClickContinue (or bound-callback/firesignal), then 'Mysterious Arrow confirmed by PlayerStats.Stand'. Verify the actual Stand and inventory in YBA. An input log alone does NOT mean an item succeeded. Each interaction is limited to one activation, 22 seconds, 12 total clicks and two clicks per unchanged page.
5. R3 continuation: verify the log sequence after Roka: 'suspending consumption until respawn recovery' -> NEW Character/root/remotes -> 'Character ready; returned to safe spot' -> Worthiness request -> next Arrow. Read Stand/skin/pity and physical position in-game, not only logs. The existing LearnSkill(Worthiness, Character) request may spend the required skill point; one request per ready Character, bounded to 5 seconds. Its return does NOT prove skill allocation. R3 requires a replacement living Character after Roka and stops after 20 seconds if not ready. Test 2-3 controlled rolls with enough Roka/Arrows and a conservative pity cap.

Rokakaka case: only use an unwanted NON-SKIN Stand, known safe to discard, with one Roka and Arrow. Expect Rokakaka confirmation with Stand=None before the Arrow starts. Never test by sacrificing a valued Stand.
6. Stop: disable the beta while a dialogue is open and while waiting for the result. Confirm no additional clicks/items and no late timeout warnings from that run. A server action already submitted may still finish. The script restores any GUI it hid and any still-pending option selection it wrote in the same live dialogue. It does not destroy GUI or reset server state.
7. Skin protection: with a skin, Start must refuse without consuming. Missing/invalid/empty skin responses must also preserve the Stand. Do not bypass refusal. When pity is at the limit, no item may activate.
8. Failure: if stalled, hidden, unsupported or unresolved, the run stops and another consumption remains blocked. Manually inspect the Stand, items and dialogue. Do NOT repeatedly re-enable. Close/finish manually only after understanding the pending action; reload the hub only after verifying no pending consumption. A confirmed late result with closed dialogue can release the lock on the next Start.
9. Repeat controlled tests for respawn and Stop/restart. Export Console logs and record before/after Stand, skin, pity, Arrow/Roka counts, Delta version/platform, observed pages and whether Stop preceded the final confirmation. Do not include WHITE AI device session files or secrets.

## Offline verification

Install ai/requirements.txt and tests/requirements.txt in a local environment.
Run python -m unittest ai.test_server and python -m unittest discover -s tests -v.
The simulation lowers only Luau continue to Lua goto for lupa; the original source is independently parsed by tree-sitter-luau. It cannot reproduce Delta input delivery, YBA page layout or server replication.

Protected runtime modules remain byte-identical to baseline. No Render deployment for this Lua change. The previous visible-only candidate stalled on real Delta (two Option1 inputs with no page advancement); R2 subsequently confirmed one Arrow (Cream) and one Roka (None) in runtime 778ed3ba, but stalled on the second Arrow after Continue. R3 continuation was observed in runtime 8bab0a5f; R4 still requires Delta validation. It permits a verified Option1 selection while a Continue handler waits, without firing a second concurrent signal.
Rollback R4: restore StandFarm.lua from c51cb69d14101d6749a123f3547080948783f176 on dev only; create a restoration commit without rewriting shared history.

## Handoff reconciliation

The newly received dossiers refer to older OpenAI/proposal-only code and d63cdf4's visible driver. Current source at baseline 63a4b82 already has Gemini, job polling and owner sessions; no historical 391b412 deployment should be replayed. No backend change/deploy is part of R3. WHITE AI persistence remains pending as recorded in WHITE_AI_INCIDENT_AUDIT.md.


## R4 speed test / timing interpretation

Keep the same safeguards and test conditions above. Export the full Console after 2-3 controlled cycles; include Stop during dialogue/result waiting, before/after stock and pity, and confirm the target is preserved. R4 keeps the 22s timeout, 12-input total cap, two inputs per unchanged page, 0.8s retry cooldown, one activation and uncertain-result lock. Respawn readiness and skin checks remain required.

R4 dispatches verified internal handlers without a 0.1s rendered settling delay; physical-input fallback still waits for a stable visible button. It watches briefly at 0.03s after an input and otherwise polls unchanged pages/results at 0.1s. Option signatures inspect the option subtree instead of scanning/sorting the entire dialogue or waiting for animated body text. The 0.8s post-Arrow pause is retained before inspecting the result/skin on the next cycle. There are no animation/constant patches, global hooks or GC scans.

A new confirmation log gives `timing: inputs=...; stat=...; closed=...; after-input=...` in seconds:
- inputs: interval from first to last dispatched input (not the item's complete execution).
- stat: activation to first observed expected PlayerStats.Stand state.
- closed: activation to first observed absent owned dialogue.
- after-input: final dispatched input to first observed expected Stand.
Measurements include scheduling/network/game delays; polling granularity is roughly 0.1s. They cannot prove which server or animation code caused a delay. If closed is short but stat/after-input is near 8s, repeating clicks cannot safely make the already-submitted item finish sooner. If stat is short but closed is long, investigate dialogue cleanup separately; no further consumable is allowed meanwhile.

Local deterministic mock comparison using the same immediate-result Option1 -> Continue -> Option1 sequence: R3 activation-to-result 0.65s, R4 0.21s, three dispatched inputs in both. This is a mock timing result only, not a Delta benchmark or an estimate for YBA's item processing. Remaining mobile lag and actual speed require owner's runtime evidence.
