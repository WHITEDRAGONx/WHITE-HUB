# Canonical WHITE HUB address

The owner renamed the modular repository (id 1232157515) to WHITE-HUB and the
old repository (id 1200853879) to WHITE-HUB-Legacy during preparation. The legacy
repository has not been changed. Both histories remain intact.

Canonical public code: WHITE-HUB/main/Main.lua. Runtime module downloads,
owned-hop loaders, source backend defaults and render.yaml now use the new name.
Experimental source remains on the same dev branch; private components remain
excluded from main. The optional release/alias wrapper is not needed for normal
installation. Earlier alias preparation did not modify the legacy repository.

Renamed main before URL correction: 9e8711d038605feceee0d23008f155632fdfca7c.
Renamed dev before URL correction: 4c8b3c9b2bc0be00f87d416fe925c660e3796095.
GitHub old-name API redirects preserve current deployed backend reads; repository
name defaults are updated in source for the next backend deployment. No unrelated
requirements/dependencies changed. Verify raw loader and all download URLs after
publication; do not substitute dev or touch legacy.
