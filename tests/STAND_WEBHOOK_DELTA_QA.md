# Stand/Shiny/Rib terminal webhook — R11

Offline simulation is not Discord or Roblox/Delta validation. No live URL is
included in these tests, commits, diagnostics or this guide.

1. Reload the permanent public loader in a fresh session; Console should show
   `SF-WEBHOOK-20261013-R11`. Save your own Discord webhook in the Webhook tab.
2. Confirm a harmless automatic-stop notification first: with a common unskinned
   Stand or an empty Stand slot and current pity above zero, select a different
   obtainable target and set the pity limit equal to current pity. Keep competing
   farms OFF and start. It must stop for `Pity limit` without activating any item
   and send exactly one message to the configured channel.
3. Check player, mode, source, pity, confirmed rolls and reason. Skin must be
   `Unknown / not checked` if no current skin was confirmed; never infer an old
   skin from session metrics. Waiting longer must not duplicate the message.
4. With expendable consumables and sufficient Worthiness, restore a normal pity
   limit and try an obtainable target. A confirmed target sends one result; Rib
   uses the same path and names its actual source. The farm must already be OFF
   before a slow HTTP request completes.
5. No need to hunt a rare shiny to test transport. Offline mocks cover desired
   and other skins, while real skin preservation remains a separate QA scenario.
   If a skin does occur, it must be preserved regardless of wishlist and named
   only after the existing skin check confirms it.
6. Stop/reload during a pending roll: no new terminal message or further item
   action. A notification already submitted to Discord cannot be recalled.
7. Missing URL skips notification. Unavailable HTTP/429/other errors must not
   restart the farm or retry; Console must not contain the webhook URL/token or
   response body. Unresolved item results remain fenced against another use.
8. Restock transfer in progress is not completion: no terminal message. Check the
   next server still follows the existing opt-in resume and inventory safeguards.

Report build, executor, steps, actual message and sanitized Console. Do not share
webhook URLs or device session files. Merchant, XenonLock and Item Farm are out
of scope for this change.
