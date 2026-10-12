# Quest/NPC automatic Stand invocation

Dev baseline 91f87b30314bbcc20aa8bead60d94be3f226606c.
Main baseline fbed6d6cc61a25c2384dbe6526446635069eb17c.
Checkpoint 3d8e26606f55bddf29fdb0238eaa069ffe65ef11.

Only ensureStandSummoned adapter changed. Every byte outside its region in
CombatFarm.lua remains identical, including XenonLock movement, attacks, death
confirmation and quest credit. Inventory.lua unchanged. Existing game RPC remains
ToggleStand/Toggle; no unverified remote names or injected handlers added.

Old helper did nothing when SummonedStand and StandMorph were both absent. It also
sent asynchronous toggles every 0.30 seconds while the server flag stayed false.
The new helper keeps one pending RPC/confirmation window, requests once when both
indicators are absent, uses BoolValue state when present and retains the old morph
fallback when no flag exists. Unknown flag types are reported without blind toggles.
Confirmation is state-based; a successful RPC return is insufficient.

Maximum 3 attempts per run/character until confirmation or restart. One-second
request cooldown and four-second confirmation window. RPCs cannot always be
cancelled once sent; no new RPC runs after Stop or Character change, and late
results do not log/mutate the cancelled routine. [StandSummon] logs identify
requests, confirmation, unknown state, missing remote and unresolved attempts.

## Delta check

1. Fresh public Main session. Disable other farms. Own a normal Stand and leave it
   unsummoned. Start NPC Farm with a known available target; expect automatic
   invocation, [StandSummon] confirmation and existing combat behavior.
2. Stop NPC Farm. Manually unsummon, select a normal supported quest and start
   Quest Farm. Check invocation, quest progress and turn-in without repeated toggles.
3. Start with Stand already out: it should remain out, with no extra toggling.
4. While farming, manually unsummon once. Verify bounded recovery. Repeat after
   respawn; character-local remotes must be ready before invocation.
5. Stop during a pending request. No new invocation request should follow Stop.
6. If it fails, export the COMPLETE runtime log showing StandSummon plus the Stand
   name, selected quest/NPC and PlayerStats state. A showcase video alone does not
   show replication/RPC status. Do not repeatedly restart unresolved work.

Fifteen offline scenarios passed; live gameplay remains pending. No Render deploy.
