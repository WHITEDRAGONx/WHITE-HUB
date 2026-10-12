# Combat Stand invocation checkpoint

Dev rollback: 91f87b30314bbcc20aa8bead60d94be3f226606c.
Main rollback: fbed6d6cc61a25c2384dbe6526446635069eb17c.

Owner reported Quest/NPC farm not automatically invoking Stand during showcase. Existing helper refuses to request when SummonedStand is absent and no morph exists; repeated RPC every 0.30 seconds can also double-toggle during delayed replication. Patch only ensureStandSummoned adapter outside XenonLock, preserving combat body byte for byte and Inventory unchanged. Allow a bounded request when flag/morph absent, prevent overlapping ToggleStand RPC, confirm replicated state, bound retries and cancel deferred work after Stop/respawn/runtime replacement. Add diagnostic logs; do not invent game remote names or assert Roblox success without logs. Public/dev hotfix, no Render deployment.
