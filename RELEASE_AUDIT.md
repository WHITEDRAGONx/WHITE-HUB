# Public synchronization audit — 2026-10-19

Public baseline: `d81f2ba77f6fea297329d5ce09e44d2430bf4a7f`.
Development source inspected: `d259980660cb5e8acf7c2e4379fd8f4c5b2686d1`.
Staging: `release/2026-10-18-public-dev-sync-no-ai`.
Existing backup preserved: `backup/2026-10-18-public-before-dev-sync`
(`6c8bf7ec244463a3b1602f98305da0c5312d2cbf`).

The backup predates the public baseline above. To undo this audit, revert its
release commit onto main; do not reset main to the older backup.

## Comparison result

Most requested functional updates had already reached the public baseline in
prior public commits. No blanket merge or development-history merge is needed.
Every tracked baseline file was compared at pinned source revisions.

Byte-identical between the source revisions:
`AutoPrestige.lua`, `AutoPrestigeRuntime.lua`, `CHANGELOG.md`, `CatalogRefresh.lua`, `ChoiceUI.lua`, `CombatFarm.lua`, `Farm.lua`, `GameCatalog.lua`, `Movement.lua`, `NPCFarm.lua`, `PrestigeDialogue.lua`, `QuestFarm.lua`, `Settings.lua`, `StandFarm.lua`, `StandTransfer.lua`, `StandV2UI.lua`, `UICompact.lua`, `Webhook.lua`.

Differences reviewed individually:
`CommunityFeatures.lua`, `Config.lua`, `HalloweenExchange.lua`, `Inventory.lua`, `Main.lua`, `README.md`, `ServerHop.lua`, `UI.lua`.

The public loader retains guarded saved Stand startup, which would be lost by
copying the development loader. The public interface and config retain their
public identity and exclude owner-only administration. Community and Halloween
module differences are header comments only. Server Hop differs only in its
owner-worker cleanup list. The development inventory delta adds sale diagnostics;
it is deliberately excluded because sales are outside this update's scope.

## Preserved functionality

- Item Farm and opt-in Fast Pickup with confirmed inventory acquisition and
  performance logs. No additional acceleration in this audit.
- Stand/Shiny/Rib: saved ON startup, guarded one-use owned-hop continuation,
  25-second restock loop deadline and eight-attempt limit, cancellation, skin,
  pity and inventory checks. A pickup already underway can finish after the
  loop deadline; this is not a hard 25-second teleport guarantee.
- Classic hop default; opt-in distinct-server Clean Hop and transfer teardown.
- Independent idle/farm/event candy turn-in, terminal Jack dialogue recovery,
  one-shot purchase authorization, verified balance/price and no uncertain retry.
- Community movement ownership and calibration compatibility fixes.

## Changes in this audit

`ServerHop.lua`: remove an obsolete development-loader comment only.
`Config.lua`: correct comments describing existing saved Stand resume and idle
candy exchange behavior; defaults and executable behavior are unchanged.
`README.md` and `CHANGELOG.md`: correct stale build/resume/exchange descriptions
and remove owner-only documentation references. `RELEASE_AUDIT.md`: this record.

`Inventory.lua`, `Main.lua`, `Farm.lua`, `StandFarm.lua`, `StandTransfer.lua`,
`CommunityFeatures.lua`, `HalloweenExchange.lua`, `UI.lua` and combat/progression
code remain byte-identical to the public baseline.

## Validation

Eight validation groups passed against the actual staging sources:

1. Tree-sitter Luau syntax for every public Lua file (24 files).
2. Complete public-file inventory and content scan for owner-only files,
   administration UI, endpoints, authentication and development-loader references.
3. Public loader dependency inventory and public-only queued entry point.
4. Byte comparison of protected/current functional modules against the baseline.
5. Actual Config execution under Lupa: classic hop/Fast Pickup default OFF,
   purchase authorization reset on load, saved Stand ON retained.
6. Actual extracted Restock execution: no-item timeout at 25 seconds,
   cancellation without collection, existing stock confirmed immediately.
7. Source contracts for serialized idle Jack execution, one-shot buy gates,
   terminal dialogue handling and community movement ownership.
8. Existing public-loader boot simulation adapted to current module contracts:
   initialization, startup, resume entry and public-only requests.

`git diff --check` passed. These are static checks and offline Lua simulations,
not Roblox/Delta validation. No backend deployment is part of this release.

## Pending live checks

- Post-hop Stand switch/owned resume and bounded restock on Delta.
- Idle candy delivery, final Jack Continue and verified-balance purchase.
- Clean Hop destination/startup and executor queue compatibility.
- Sale latency after hops: separate investigation; no sale fix claimed here.
- Native low graphics activation remains unconfirmed in prior owner logs.
