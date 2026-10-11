# WHITE AI incident retention audit — 2026-10-11

Investigation only; no backend code, provider settings, authentication or deployment changed.
Inspected server.py at dev baseline b5783ac, unchanged in Stand Farm fix 0f6c2f0.
Render still LIVE at 74d56ce with auto-deploy off. Public health returned status=ok and configured=true; this does not verify Gemini availability.

## Reproduced findings

An offline mocked run_job with a StandFarm incident and GeminiAPIError(gemini_unavailable) retained only status, error, error_code and hint in _jobs.
The cleaned report was not retained. No proposal or auto-patch call occurred.
_jobs is an in-memory dict; a service restart loses these job records.
There is no persistent incident queue or endpoint for later re-analysis.
Timeouts follow the same failure storage path (gemini_timeout).
StandFarm.lua is absent from PATCH_ALLOWLIST and READ_ONLY_FILES, so allowed_module_path resolves its report to CombatFarm.lua. Stand Farm should be added to diagnosis READ-ONLY access first, without granting AutoFix permission.

## Bounded recovery design to implement separately

Persist a validated, sanitized incident BEFORE scheduling analysis; acknowledge receipt only after durable storage succeeds.
The existing free Render service has no configured persistent disk. Use an explicitly chosen durable store; writing local JSON to its ephemeral filesystem would not meet restart recovery.
Keep request/admin/session headers, keys, source code and raw provider responses out of incident records. Validate redaction with adversarial cases before writing to any publicly visible repository path.
Store job ID, cleaned report, state, attempts, timestamps, retry-after and the analyzed dev commit/blob SHA.
Queue only transient gemini_unavailable/gemini_timeout, with bounded retries/backoff and an authenticated manual retry path.
Lock individual jobs and enforce rate limits to prevent concurrent/repeated analyses.
Recovered/retried reports must be review-only; never persist/replay owner_auto_patch authorization.
Re-read source on retry and require all existing source freshness/static gates before any separately authorized patch.
No paid fallback. Auth/configuration/invalid-response failures require explicit diagnosis instead of endless retries.
Expose queued/retry_exhausted/storage_failure distinctly from pairing failure.

## Verification for the future backend change

Mock 503 and timeout to assert durable incident before provider call and no patch.
Simulate process restart and recover the job/report from durable storage.
Test exhaustion, retry eligibility, auth, competing retries, failed persistence, rate limiting, secret redaction and changed dev source.
Confirm recovered jobs cannot inherit automatic commit authority.
Run existing owner-session and backend regression tests.
Deploy only when that backend change is implemented and validated; no deployment is warranted by this audit or the Lua fix.
