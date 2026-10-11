# WHITE AI durable queue checkpoint

Baseline dev: 871a51392d54dda91bd79e3c2d42d01ee83fbe82 (includes two existing AI proposals). Main: 718018dac21d9a51e1955f68b4a042f28a534ee1.
Render manual deploy, last LIVE 74d56ce; free service, no persistent disk.

Scope: encrypted sanitized incident records on existing dev GitHub, bounded retries, private retry/recovery endpoints, client status/recovery, read-only StandFarm routing. No raw credentials, sessions, source or provider responses in records; no automatic authority stored/replayed. Recovered analyses review-only.

Preserve Inventory.lua byte-for-byte (rollback retained), Combat/XenonLock, main and existing proposals. No paid infrastructure/provider. Source changes and backend deployment require tests; no claim of YBA validation.
Rollback: restore changed runtime/backend files from baseline and deploy that restored backend on dev only, preserving incident ciphertext for recovery with the original encryption key. Never reset shared history.
