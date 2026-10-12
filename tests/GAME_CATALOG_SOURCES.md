# Game catalog provenance — 2026-10-12

Public API reads succeeded for the primary and secondary YBA boards:

- https://trello.com/b/nV2ngLeZ/yba-primary-board
- https://trello.com/b/ROfFdASc/yba-secondary-board

Only card titles were retained: 236 distinct titles from Stand Skins lists, and 34 from Quests/Stand Quests/Story Quests. Item skins, cosmetics, prices, descriptions, images, webhooks and third-party code are excluded. A title does not establish present obtainability, arrow/rib eligibility or the exact server-returned alias. All skins, including unselected/unknown skins, remain protected. Saved/observed names are preserved as exact options.

Snapshot title hashes (UTF-8 sorted JSON):

- Skins: b540e605aed02433ac7299c5909c6fc3c7fd80b39e8d70166165c400593f63ca
- Quests: 6e2967c2a632acf1e25eb833a1eee1d9543b1f6822a765e5fd328ef54a9ccaee

Uploaded Xenon was inspected as text only. Its 378 skin candidates were not imported; network/hooks and external webhook handlers were not executed or copied. Its quest map covered the same basic objectives and does not validate the other discovered quests.

Runtime discovery reads names of bounded children in workspace.Dialogues and ReplicatedStorage.NewDialogue, and known skin containers; no game ModuleScript is required, edited or decompiled. Undocumented quests are shown as INFO and cannot become SelectedQuest. CombatFarm mappings, Auto Choose Vampire priority and XenonLock are unchanged. Native game schema/aliases still need Delta logs.
