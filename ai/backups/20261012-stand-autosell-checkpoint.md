# Stand Farm Auto Sell compatibility checkpoint

Owner requested that enabled Auto Sell should not block Stand/Shiny/Rib Farm when Item Farm is off. Main hotfix included under this request.

Dev rollback: 844e9c58021a3d9172b895f8a96c589d2513e24e.
Main rollback: 86d511532b8b82fb62c9ea20870fd92da9ca67ce.

Remove preference-only guards in StandFarm start/active/restock-hop/resume and shared Farm.Restock. Preserve competing farm/pending/dialogue/skin/pity guards. Block startup while the actual Item Farm cycle/sale is finishing, using existing Farm.IsBusy; do not edit Inventory. Ensure optional resume waits for startup work. Test enabled Auto Sell consumption, restock without sales, owned-hop resume and real busy handoff. Publish only public hotfix modules/notes; keep WHITE AI dev-only. No Render deploy.
