# Repository name migration checkpoint

The owner renamed repository id 1232157515 from WHITE-HUB-V3 to WHITE-HUB, and
id 1200853879 from WHITE-HUB to WHITE-HUB-Legacy. Legacy has not been modified.

Pre-reference-update dev: 4c8b3c9b2bc0be00f87d416fe925c660e3796095.
Pre-reference-update main: 9e8711d038605feceee0d23008f155632fdfca7c.
The Stand invocation fix is already included in these commits.

Update canonical Lua download and owned-hop URLs, public installation docs and
backend repository-name defaults. Preserve runtime algorithms, Inventory and
private/public separation. Old GitHub API references redirect to the renamed repo;
current backend deployment can continue using that redirect, source defaults will
be current on its next deployment. No Render deploy for these URL-only changes.
