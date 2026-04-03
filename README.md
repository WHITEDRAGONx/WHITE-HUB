📋 WHITE HUB - HOW IT WORKS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

The script automatically farms items that spawn on the map,
teleporting underground to grab them without being seen,
then returns to the hideout after each item collected.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔄 SERVER HOP
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

After every farm cycle the script automatically switches
to a new server to keep finding fresh item spawns.
If the server hop fails it will retry automatically.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🛒 AUTO SELL
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

After farming, the script automatically sells all items
that are set to true in the SellItems list.

✅ If an item is set to true:
The script will automatically sell it after each farm cycle.
Good for items you don't care about keeping.

❌ If an item is set to false:
The script will farm it but never sell it, so it stays
in your inventory. The server hopping works normally
while you still need more of that item. Once you reach
the maximum amount, the script will automatically stop
farming and server hopping until you use some of it.
When your count drops below the max, everything resumes
automatically.

📦 Example:
   ["Rokakaka"] = false  → farms it, keeps it, stops when maxed
   ["Gold Coin"] = true  → farms it and sells it automatically

⚠️ Note: If ALL items are set to true, the script will
farm and server hop forever without stopping.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🍀 AUTO BUY LUCKY ARROWS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

After each farm and sell cycle, the script checks how
many Lucky Arrows you have. If you have less than 10,
it will automatically buy more from the shop using your
in-game money ($75,000 per arrow) until you reach 10
or run out of money.

✅ BuyLucky = true  → buys Lucky Arrows automatically
❌ BuyLucky = false → you buy them manually yourself

⚠️ Notes:
   • Each Lucky Arrow costs $75,000
   • Only buys if you have enough money
   • Lucky Arrow is excluded from the "stop when maxed"
     check since it rarely spawns on the map, so the
     script keeps farming regardless of Lucky Arrow count
   • Auto Buy Lucky is enabled by default

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
💰 MAX MONEY STOP
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Once you have 10 Lucky Arrows AND $1,000,000 (max money)
at the same time, the script will automatically stop
farming and server hopping since there is nothing left
to spend money on. When you spend money or use Lucky
Arrows it will resume automatically.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔒 NOCLIP
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

When teleporting to grab an item the script activates
noclip so the character goes underground without
colliding with the floor and getting flung.
It disables automatically after returning to the hideout.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🛡️ ANTI AFK
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

The script automatically prevents you from being kicked
for inactivity, so you can leave it running overnight
or for long periods without worrying about AFK kicks.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
💥 CRASH BYPASS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

The script includes a bypass that prevents the game
from crashing your client when it detects cheating,
keeping the farm running stable for longer sessions.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
           CREDITS: WHITE DRAGON
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
