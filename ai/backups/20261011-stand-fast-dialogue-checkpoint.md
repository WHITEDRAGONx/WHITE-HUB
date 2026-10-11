# Stand fast dialogue checkpoint

Dev before edit: d63cdf49767ea98f44af7e1730ef779b70f658d0.
Main preserved: 718018dac21d9a51e1955f68b4a042f28a534ee1.
Restore StandFarm.lua from the dev commit above to roll back.
Delta 1.0.739.687 runtime 8ba5a5cc: Option1 input twice; same page stalled. Screenshot shows Arrow Yes/No unchanged. Previous visible-input candidate is NOT functionally validated.
Plan: isolated adaptation of existing quest fast Option1 callback selection and Continue callback dispatch. Strict button binding, original value capture/restoration on cancellation/failure, scoped GUI suppression with restoration. Never change Inventory.lua, CombatFarm.lua, XenonLock, main, loader, configuration or backend.
Verification: original Luau parser; callback-simulated tests including unsupported/mismatched callbacks, Stop, UI restoration, late results and unchanged-page limits; existing regression.
Real Delta validation remains required. No Render deploy.
