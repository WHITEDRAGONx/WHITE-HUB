# Settings performance checkpoint — 2026-10-13

Before code changes:
- Repository: WHITEDRAGONx/WHITE-HUB
- Experimental branch: dev/2026-10-10-autosell-compat
- Dev source HEAD: c33ea596c8ec87d64d7809f87abc0cab57f1b76f
- Public HEAD: e25ea522deec85758c1c641d55654e37414ec04d

Latest dev changes 2a22fcb / c33ea59 add Auto Sell frame diagnostics and the
fresh-session ClientFX A/B test. Preserve those changes in dev. Do not promote
them as part of Settings.

Scope: isolated Settings.lua module; three saved opt-in preferences;
UI Settings page and scrollable navigation; loader contracts/cleanup;
public-package inclusion; targeted lifecycle/rollback tests and documentation.
Inventory.lua, Merchant, CombatFarm.lua/XenonLock, farms and private AI are
outside this change. Public promotion uses only the Settings-related files.

Verification: exercise the real Settings module with offline Roblox mocks:
API unavailable/failed, cap restoration, opt-in saved settings, visual fallback,
SHOW GAME recovery, low-effects restoration, cancellation during scene scan,
new visual effects, respawn persistence and Destroy/reload cleanup. Parse the
changed Lua and run public-loader/isolation checks. Functional Delta validation
remains required; there is no claim that these checks reproduce the client.

Rollback: restore Settings-related source/loader/UI/Config files from the source
HEAD above on dev; restore public Settings-related files from the public HEAD.
Remove Settings.lua only together with its loader/UI references. Preserve later
unrelated commits. Never reset or force-update either branch.
