# AutoPrestige Rebuild — implementation plan

## Goal

Replace the current compatibility-beta progression loop with a state-driven AutoPrestige controller for a fresh YBA account. Preserve the public WHITE HUB entry point and isolate the rewrite on `dev/2026-10-24-autoprestige-rebuild`; do not modify `main` during development.

## Evidence from the 2026-10-24 Delta run

- All modules downloaded and compiled successfully.
- AutoPrestige identified the quest panel as the `Patch` placeholder and selected `Storyline #1`.
- It found `Workspace.Dialogues.Storyline #1 (Giorno)` and fired `ClickContinue` twice.
- The run never logged a confirmed dialogue result or a Security Guard combat start. The user stopped AutoPrestige at 01:19:52.
- Therefore, this run validates boot and target discovery only; it does not validate quest acceptance, combat, skill allocation, Stand Farm orchestration, Hamon acquisition, or prestige completion.

## Architecture

### 1. Controller/state machine

One controller owns the progression and exposes one current phase at a time. Each phase must return a structured result (`complete`, `retry`, `blocked`, or `fatal`) with a reason. Never launch overlapping story workers. A phase advances only after observable game state confirms its postcondition.

Suggested phases:

1. `BOOTSTRAP` — wait for character, PlayerStats, remotes, quest UI and inventory.
2. `READ_STATE` — snapshot level, prestige, stand, spec, money, quest objective, available skill points, and relevant inventory.
3. `DIALOGUE` — interact with the intended NPC using the shared fast-dialogue primitives.
4. `QUEST_ACCEPT` — verify the accepted objective using quest state/progress, not the placeholder UI alone.
5. `QUEST_PROGRESS` — dispatch the appropriate combat, collection, or turn-in action.
6. `SKILL_ALLOCATE` — buy only eligible upgrades; verify points/unlocks after each purchase.
7. `STAND_SETUP` — delegate to the existing Stand Farm only when no other farm/controller owns the character.
8. `HAMON_SETUP` — verify money and prerequisites, acquire Hamon, then verify PlayerStats.Spec.
9. `PRESTIGE` — request prestige only when the level/quest requirements are met and verify the Prestige stat changed.
10. `RECOVER` — bounded retries with a useful diagnostic; never silently loop forever.
11. `COMPLETE` — stop cleanly when the configured prestige/level target is reached.

The exact quest route and unlock requirements must be confirmed against live YBA state before being encoded as facts.

### 2. Dialogue adapter

Reuse the proven dialogue primitives already present in `CombatFarm.lua` / `StandFarm.lua` and the scoped dialogue driver in `AutoPrestigeRuntime.lua`. Do not touch Merchant-specific dialogue behavior. The adapter should:
- identify the intended NPC and current dialogue instance;
- inspect available options/text and advance using the existing fast path;
- track a dialogue signature and deadline;
- detect completion from objective/quest/player state changes;
- return an explicit failure reason when there is no observable progress;
- restore any GUI visibility/connection state it changed.

Do not treat two fired input events as success. Do not use the generic `Patch` placeholder as proof that a quest was accepted.

### 3. Quest and NPC executor

Keep quest routing separate from the dialogue engine. Each objective defines its accepted-state predicate, progress reader, executor, and completion predicate. Combat must use existing supported combat helpers where possible and confirm each target defeat through live character/NPC state before incrementing progress.

### 4. Skill-tree planner

Read available skill points and the current unlock state. Use a per-build ordered allowlist of skill names and tree types. Attempt one purchase at a time and verify the server-side result before continuing. If the game rejects a purchase, log the skill, tree, response, and current points; do not repeatedly spam the remote.

### 5. Stand Farm and Hamon orchestration

Treat existing Stand Farm as a delegated worker with exclusive ownership. Start it only when safe, wait for a verifiable outcome, then resume the progression controller. For Hamon, check prerequisites and funds, interact with the correct trainer using the dialogue adapter, verify the resulting specialization, and allocate only eligible Hamon skills.

### 6. Diagnostics

Every phase transition should log:
- previous phase -> next phase;
- reason / observed evidence;
- retry count and deadline;
- relevant state fingerprint (level, prestige, spec, stand, quest progress, points).

Timeouts must say which observable condition was missing. Stop requests must cancel or fence pending work so an old callback cannot resume progression.

## Validation gates

1. Boot and controller lifecycle; start/stop must not leave duplicate workers.
2. Dialogue adapter: target discovery, option progression, completion detection, timeout and cleanup.
3. Fresh-account Giorno quest: verify objective accepted before combat starts.
4. Security Guard combat: confirm 5 actual defeats and quest completion.
5. Skill-tree allocation: one valid purchase, rejected purchase, and zero-points case.
6. Stand Farm handoff: no overlapping farms and clean resume.
7. Hamon: prerequisite handling, purchase, specialization verification and skill allocation.
8. Full prestige loop only after the individual gates pass.

## Scope guardrails

- Work on this branch only; do not modify protected/stable `main` while rebuilding.
- Preserve `Inventory.lua`, `StandFarm.lua`, `CombatFarm.lua`, and Merchant dialogue behavior unless a specific, independently verified integration fix is necessary.
- Do not claim Roblox/Delta validation without an actual run and logs.
- Prefer bounded retries and observable postconditions over timing guesses.
