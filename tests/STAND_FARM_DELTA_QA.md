# Stand Farm V1 — experimental visible dialogue driver

NOT VALIDATED IN ROBLOX. Offline: 17 simulated tests + 34 existing backend/static tests.
Uses visible mouse input only, no callback/upvalue injection. Delta/mobile support must be measured in game.

## Delta test procedure (owner)

1. Load the existing DevMain.lua from dev/2026-10-10-autosell-compat in a fresh YBA session. Keep Stand Farm off until ready. Confirm the GOLD UI loads with no compilation/init errors.
2. Disable Item Farm, Quest Farm, NPC Farm, Auto Prestige AND Auto Sell. Close all existing game dialogues. Keep the YBA dialogue area visible and unobstructed by the hub. Do not open other dialogues or use items manually during the run.
3. Arrow case: start with Stand=None, at least one Mysterious Arrow and enough Worthiness for normal manual use. Select Aerosmith; keep a conservative pity limit above current pity. Enable Stand Farm (BETA).
4. Watch Console for dialogue input Option1 / ClickContinue, then 'Mysterious Arrow confirmed by PlayerStats.Stand'. Verify the actual Stand and inventory in YBA. An input log alone does NOT mean an item succeeded. Each interaction is limited to one activation, 22 seconds, 12 total clicks and two clicks per unchanged page.
5. Rokakaka case: only use an unwanted NON-SKIN Stand, known safe to discard, with one Roka and Arrow. Expect Rokakaka confirmation with Stand=None before the Arrow starts. Never test by sacrificing a valued Stand.
6. Stop: disable the beta while a dialogue is open and while waiting for the result. Confirm no additional clicks/items and no late timeout warnings from that run. A server action already submitted may still finish. The script leaves the game dialogue intact; it does not destroy GUI or reset server state.
7. Skin protection: with a skin, Start must refuse without consuming. Missing/invalid/empty skin responses must also preserve the Stand. Do not bypass refusal. When pity is at the limit, no item may activate.
8. Failure: if stalled, hidden, unsupported or unresolved, the run stops and another consumption remains blocked. Manually inspect the Stand, items and dialogue. Do NOT repeatedly re-enable. Close/finish manually only after understanding the pending action; reload the hub only after verifying no pending consumption. A confirmed late result with closed dialogue can release the lock on the next Start.
9. Repeat controlled tests for respawn and Stop/restart. Export Console logs and record before/after Stand, skin, pity, Arrow/Roka counts, Delta version/platform, observed pages and whether Stop preceded the final confirmation. Do not include WHITE AI device session files or secrets.

## Offline verification

Install ai/requirements.txt and tests/requirements.txt in a local environment.
Run python -m unittest ai.test_server and python -m unittest discover -s tests -v.
The simulation lowers only Luau continue to Lua goto for lupa; the original source is independently parsed by tree-sitter-luau. It cannot reproduce Delta input delivery, YBA page layout or server replication.

Protected runtime modules remain byte-identical to baseline. No Render deployment for this Lua change.
Rollback: restore StandFarm.lua from b5783ac4a735082b4fd3c49966f462a20a7dd4d5 on dev only.
