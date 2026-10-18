# Owner-authorized native Low GFX public checkpoint — 2026-10-18

Main before publication: e08e9e28c599af0acbf4d053178b4fe0d4c86dc7
Dev implementation: 787db7d7f1f85a6b39243e8acd3aaba654a9d4c9
Original adapter checkpoint: 8a6e14ef1c865eefe07715ec829533073f9c38af

Owner instruction: "Faz na main" after being informed native activation still
requires a real Delta test. Publish the identical Settings.lua validated by
37 Settings + 9 packaging checks; add honest public README/changelog notes.
Main scope is exactly Settings.lua, README.md and CHANGELOG.md.

No Inventory, Farm, Combat/XenonLock, Stand, AutoPrestige, loader, configuration,
AI distribution or backend changes. No Render deploy. Native control removal
was observed only after manual use; our adapter's Delta activation remains
unvalidated. A missing native button may mean already used or unavailable.

Rollback: restore the three public paths from the pre-publication main SHA.
Native YBA changes already requested in a running client cannot be undone by
rolling back code; rejoin for a fresh client/session if needed.
