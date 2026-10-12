# Silver R3 automatic catalogs

Dev baseline a83a4af0bc0e30435adf0dacc4916072184ab2f2.
Main baseline 8a5a249f1c9157870f60fbbe5eb9829de1b1885f.
Checkpoint 5b415c5a381772ac06f8dd3c9e8a478cf49084eb.
No Render deployment; private components and farm behavior unchanged.

1. Fresh Main/DevMain session, confirm Silver R3 and CatalogRefresh boot.
2. Console should show automatic skin title refresh or a safe offline/timeout
   message. Open/reopen Skins after refresh: newly received titles should appear
   without editing source. A fresh SkinCatalogCache skips HTTP for six hours.
3. Existing selected aliases remain checked. All/unknown skins remain protected.
   Names in the catalog do not establish that a skin can be rolled right now.
4. Quest choices prioritize client Dialogue/NewDialogue names. Reopen after NPC
   dialogue objects replicate. INFO entries must not change the active quest.
   NPC list already uses Living names and ChildAdded/ChildRemoved updates.
5. If the executor blocks Trello HTTP, verify that the fixed 461-name alias set
   remains usable and that no repeated request loop or freeze occurs.
6. Reload during refresh; old results must not write config after cleanup. HTTP
   cannot always be aborted, but expired results are rejected. The current
   bounded detector does not guarantee access to the complete game skin registry.
7. Send the Console/build and screenshots of unexpected names or missing new
   names. Never include personal config/session files, keys or webhook URLs.

Sixteen new offline tests cover cache TTL/schema, source filtering, response size,
invalid data, concurrent refresh, timeout, reload cancellation, late client data,
confirmed skin names and live quest preference. Full native behavior is pending.
