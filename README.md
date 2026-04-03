# WHITE HUB - YBA ITEM FARM

Automatically farms items that spawn on the map, teleporting underground to grab them, then returns to the hideout after each collect.

---

## 🔄 Server Hop

After every farm cycle the script automatically switches to a new server to keep finding fresh item spawns. If the server hop fails it retries automatically.

---

## 🛒 Auto Sell

After farming, the script automatically sells all items set to `true` in the `SellItems` list.

| Value | Behavior |
|-------|----------|
| `true` | Farms and sells automatically after each cycle |
| `false` | Farms and keeps in inventory — stops server hopping once maxed, resumes when count drops |

> ⚠️ If **all** items are set to `true`, the script will farm and server hop forever without stopping.

**Example:**
```lua
["Rokakaka"] = false  -- farms, keeps, stops when maxed
["Gold Coin"] = true  -- farms and sells automatically
```

---

## 🍀 Auto Buy Lucky Arrows

After each farm and sell cycle, if you have less than 10 Lucky Arrows the script automatically buys more from the shop.

| Setting | Behavior |
|---------|----------|
| `BuyLucky = true` | Buys Lucky Arrows automatically |
| `BuyLucky = false` | You buy them manually |

> ⚠️ Each arrow costs **$75,000**. Lucky Arrow is excluded from the "stop when maxed" check since it rarely spawns naturally.

---

## 💰 Max Money Stop

Once you have **10 Lucky Arrows** AND **$1,000,000** at the same time, the script stops farming and server hopping automatically. Resumes when you spend money or use arrows.

---

## 🔒 Noclip

Activates automatically when teleporting to grab an item so the character goes underground without colliding with the floor. Disables automatically after returning to the hideout.

---

## 🛡️ Anti AFK

Prevents AFK kicks automatically, so you can leave it running overnight without worrying.

---

## 💥 Crash Bypass

Prevents the game from crashing your client when it detects cheating, keeping the farm stable for longer sessions.

---

## Credits

Made by **WHITE DRAGON**
