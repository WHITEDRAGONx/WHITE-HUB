# Silver R2 catalog and touch selection QA

Dev baseline: 81aa5051db6040ebccb624c74d38b74f2d75e657.
Main baseline: dab7e1c7f7821790beb514b3334b74ffa2d957be.
Checkpoint: a9d739a44ca7d237ca6a8009aedbea1a31a123e2.
Source audit: GAME_CATALOG_SOURCES.md. No Render deploy.

Removed target edit/clear and Reset Stats buttons. Existing saved target lists and
legacy single targets appear selected. Check/uncheck items directly; deselecting
all clears both list and legacy target so Start requires a new selection. Changes
stop the active Stand routine and preserve its existing pending-result lock.
Skin targets retain exact strings. A Trello title is not a verified server alias,
source eligibility, event availability or trade value. Any/unknown skin remains
protected regardless of wishlist. No new skin consumption/storage behavior.

Trello card titles and bounded workspace.Dialogues/ReplicatedStorage.NewDialogue
names enrich the quest list. INFO entries cannot change SelectedQuest, accept or
abandon quests, invoke remotes or start combat. Existing 8 manual objectives and
Auto Choose Vampire priority are unchanged; special chains/PvP need independent
mapping and live validation before automation.

## Native Delta check

1. Fresh Main/DevMain session, confirm SILVER-V5[-PUBLIC-BETA]-20261012-R2. Keep
   farms stopped and close existing game dialogues before UI testing.
2. Open Stands: previous selections should be checked. Search, select two targets,
   uncheck one, then uncheck all. Verify summary/config and that empty selection
   cannot start consumption. Restore your desired selection.
3. Open Skins: search a known name, check/uncheck it and verify saved names survive
   reload exactly, including older aliases missing from Trello. No name typing is
   necessary. Do not test by discarding a valuable skin.
4. Menu should fit mobile portrait/landscape. Outside touch, tab switch, close,
   reload, ancestor removal and rotation should close the overlay cleanly. Verify
   search, scrolling and visible checkmarks; statistics remain without Reset.
5. Open Quest: verify existing supported quests remain selectable. Touch an INFO
   entry: popup should explain that automation is not mapped, and the current
   SelectedQuest must remain unchanged. Client-specific NPC names may be discovered
   only after their dialogue objects have replicated.
6. Resume standard farm QA with disposable items only. Export complete Console and
   a screenshot/video on failure. Offline native-object mocks are not Roblox proof.

Inventory, CombatFarm/XenonLock, StandFarm, Farm and Auto Prestige sources are byte
identical to the baseline. Public package still excludes WHITE AI and administration.
