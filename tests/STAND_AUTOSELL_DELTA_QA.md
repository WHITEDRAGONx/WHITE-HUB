# Stand R10 — Auto Sell preference compatibility

Baseline dev: 844e9c58021a3d9172b895f8a96c589d2513e24e.
Baseline main: 86d511532b8b82fb62c9ea20870fd92da9ca67ce.
Checkpoint: f41baa0d4f53d5ff17e6e6acb07ee63cad26a558.

Auto Sell may remain ON during Stand/Shiny/Rib, restock and owned-hop resume.
Earlier QA guides instructed turning it OFF; that extra restriction is obsolete
from SF-V2-20261012-R10 onward. Other competing farms remain OFF. Existing dialogue,
pending-result, skin/pity and cancellation guards remain. Item Farm.IsBusy tracks
actual work, including a finishing cycle/sale, and blocks startup until complete.
The optional arrival routine waits for Item Farm startup work within its existing
30-second bound. Restock itself never calls selling/buying. Inventory unchanged.

Six new offline tests exercise all source/mode combinations, changing the sale
preference mid-dialogue, collector-only restock, an async sale still finishing,
a new busy action during skin lookup and owned-hop/resume with busy arrival.
The Silver UI protected-file test is anchored to its original delivery commit,
so it keeps auditing that UI change without rejecting later authorized farm fixes.

## Delta check

1. Use a fresh session and the existing public Main or dev loader. Confirm R10.
2. Leave Auto Sell ON; disable Item/Quest/NPC Farm and Auto Prestige. Close old
   dialogues and wait for any current Merchant action to finish.
3. With disposable consumables and no valuable Stand/skin, start Stand Farm.
   Confirm actual PlayerStats result and that Auto Sell remains ON.
4. Enable optional restock with a missing consumable available in the server.
   Confirm collection only, no Merchant/sales, then the confirmed Stand result.
5. Optional owned hop: same toggle settings; confirm one transfer and guarded
   resume. Ordinary reload stays stopped.
6. If Item Farm was selling when disabled, Stand must refuse to start while that
   work remains busy. Retry only after it completes and the dialogue closes.
7. Confirm Item Farm ON still prevents concurrent Stand farming. Export Console
   on failure; never include tokens/session files/webhooks. No Render deployment.

No functional Roblox result is claimed for this hotfix before these checks.
