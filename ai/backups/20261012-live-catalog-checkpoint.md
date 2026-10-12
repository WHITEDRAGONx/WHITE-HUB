# Automatic catalog checkpoint

Dev rollback: a83a4af0bc0e30435adf0dacc4916072184ab2f2.
Main rollback: 8a5a249f1c9157870f60fbbe5eb9829de1b1885f.

Owner requested Xenon-style live quest/NPC discovery, automatic skins where possible and its fixed skin names otherwise. Keep NPC discovery, prefer present game quests, broaden bounded read-only skin metadata and add names-only automatic public Trello refresh/cache. Only fixed string data may be extracted from uploaded reference; no code/hooks/network/webhooks. Preserve mapped quest controllers and any/unknown skin protection. No private components on main, no Inventory/Combat/consumption/backend edits or Render deploy. Tests must cover offline fallback, cache, timeouts/cancellation, data validation, live names, schema uncertainty and public wiring. Native YBA catalog schema remains unverified.
