# Owner-authorized V5 public beta

Owner authorized main publication, including new Auto Prestige, on 2026-10-12
Brazil time. AP must be visibly beta; live full progression is still pending.
Owner reports completing other checks. Do not reinterpret this as proof of all
executors/edge cases. WHITE AI remains exclusively dev.

Checkpoint: 02b391bc16b3e25b750fa92559d5efc0429bb993.
Main rollback: 718018dac21d9a51e1955f68b4a042f28a534ee1.

scripts/build_public_release.py builds 16 Lua files from an isolated whitelist,
stripping WHITE AI UI/config/loader, changing the owned-hop loader to public Main,
and adding the AP beta display alias without changing toggle registry keys.
Inventory uses the old public blob byte for byte. Public README/changelog are in
release/public. Build output must go outside the dev checkout. Test actual public
loader with offline factory modules, parse every package Lua and reject private
references. Native main startup and AP progression still need player logs.

Publish as a normal child of old main, not a merge with dev. Include only public
Lua and release docs, leaving main's other existing files. Do not copy WhiteAI.lua,
DevMain.lua, ai/, incidents/proposals, tokens, sessions, backend or developer backups.
Update ref with exact expected main SHA; inspect any conflict before retrying.
No Render deployment. Preserve dev and its private incident/proposal history.
