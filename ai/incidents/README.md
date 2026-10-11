# Private incident queue — encrypted records only

Runtime records are AES-256-GCM authenticated ciphertext; keys stay in Render. Sanitized incident data is encrypted before writing to the existing dev branch. No credentials, headers, session tokens, source code or raw provider replies are serialized. Random 12-byte nonce per write, job ID as associated data; compare-and-swap GitHub blob SHA for updates.

By default the encryption key is purpose-separated from WHITEAI_ADMIN_KEY. Optional WHITEAI_INCIDENT_KEY (at least 32 characters) makes queue key rotation independent of owner pairing. Before rotating the admin key when the optional key is unset, preserve the OLD secret privately as WHITEAI_INCIDENT_KEY in Render to retain decryption of existing records. Never put either secret in GitHub/chat/logs. A wrong key fails closed; it does not erase the ciphertext.

The repository is public. File names, update times and commit history are public metadata; report bodies are ciphertext. Git history retains previous ciphertext revisions: no deletion/TTL guarantee is made. This low-volume development queue is not a general database. Contents listing is limited by GitHub directory limits; owner recovery scans up to ten recent IDs, watches at most three, and a known job ID can always be queried directly. UTC-day deduplication for the same client report ID and sanitized payload.

Accepted reports are persisted BEFORE HTTP 202. Maximum three analyses, transient Gemini errors only (unavailable/timeout), cooldowns 60s then 300s. Existing provider retries/free fallback stay bounded. A running record holds a 600s lease; restart recovers it after expiry, without inheriting AutoFix authorization. New analyses pin the fresh dev commit and blob; retries create attempt-specific proposal paths.

The free Render service can sleep. Pending retries resume during authenticated job polling, not while the service is offline. Owner-only POST /jobs/{id}/retry obeys the same cooldown/cap; GET /incidents discovers saved pending/failed IDs. Ingest credentials cannot call these owner endpoints. No paid service/provider was added.

For Delta: pair, enable external reporting, send an actionable incident, and inspect queued/analyzing/proposal/failure status. Use RECOVER SAVED INCIDENTS after restart and RETRY LAST INCIDENT when eligible. Error 503 from storage means delivery is NOT acknowledged; verify/recover before duplicate submission. Do not equate successful pairing or receipt with successful Gemini analysis or YBA functionality.

Offline checks: python -m unittest ai.test_server (includes auth/queue tests), python -m unittest discover -s tests, compileall and git diff --check. Real Render/GitHub persistence and Delta behavior require separate HTTP/in-game evidence.
