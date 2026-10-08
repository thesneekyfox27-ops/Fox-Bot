# nrp-doordrop 3.0

Gig food delivery app for NRP. Players open DoorDrop on their phone and pick **Drive** or **Order food**.

Author: Fox

## Drive
Clock in, get offers with pay and tip shown up front, and accept or decline. A restaurant worker hands you the bag outside (or the bag waits on the ground, see `Config.Pickup.style`), and you photograph the pickup. Then you either leave it at the door with a photo or hand it to the customer. Declines lower your acceptance rate and tier, which means fewer high tippers. Customers leave star ratings and written reviews, readable under Ratings.

## Order food
Pick a restaurant, fill a cart from a vending-style menu grid, choose "Hand it to me" or "Leave it here", and tip. Checkout charges your bank (food + delivery fee + service fee + tip). The order goes to the nearest clocked-in driver first. You track it live (driver name, miles away), and the food lands in your tgiann inventory on delivery. Afterward you rate and review the driver. If no driver takes it within `Config.Customer.searchTimeout` it's refunded, and you can cancel for a full refund until the driver picks it up.

## NPC courier
If nobody is clocked in when someone orders, or no player driver takes the order within `Config.NpcCourier.fallbackAfter` seconds, a DoorDrop courier delivers it instead:
- It waits at the restaurant during prep, then travels toward the customer. The customer sees a moving blip on the map and a live progress bar with miles and ETA in the app. Player drivers show up the same way.
- About 180 m out, a real scooter or car spawns on a nearby road and drives in. For "Hand it to me," the courier walks up and hands over the bag. For "Leave it here," the bag is set down where the customer ordered, and the customer can pick it up.
- The food lands in the customer's inventory. If anything goes wrong with the spawn, the server finishes the order after `arriveTimeout` so nobody loses their food.

## Main screen
The app opens on a full map (DoorDash style): your location, hot zones drawn as tinted areas with "Busy +$2/order" / "Very busy" chips, and floating buttons for the menu (earnings and history), today's earnings, and your rating. The bottom sheet shows your area, "It's peak pay time!" or the nearest busy area with when the bonus ends, the average offer wait, and a big **Dash** button with **Order** beside it. While dashing, the same screen shows "Looking for orders", this dash's earnings, your streak, and **Stop dashing**.

## Tips and NPC couriers
Player drivers always hand over the whole order. NPC couriers don't: with no tip there's a 50% chance up to 2 items go missing, and 15% on a tip of $2 or less. The bag is never left empty. The customer sees what was missing in the app, and checkout warns them when a courier will bring a no-tip order. Tune or turn off in `Config.NpcCourier.missing`.

## Courier arrival
The courier spawns off screen on a road 45-110 m away (with collision loaded first), drives up, parks, and walks to you. If they get stuck, they're moved closer while you're not looking. If they can't reach you at all, the bag is left visibly next to you. The food is never handed over by someone who isn't standing in front of you. Set `Config.Debug = true` and use `/ddtestcourier` or `/ddtestcourier door` to rehearse the arrival anywhere without placing an order.

## Menus and pictures
Menus use real items from the NRP items list (the nrp-vending consumables), and each entry carries the item's own image file. Pictures load from `Config.ItemImage` (`https://cfx-nui-inventory_images/images/%s`). UwU Café and Noodle Exchange menus are ready but `disabled` until you set their pickup spots.

## Mini map and delivery timer
- **Mini map in the app:** on the offer screen (you, restaurant, drop-off), during a delivery (it follows you as you drive), and when tracking a food order (the driver or courier moving toward you). It uses the 17mov_Phone Maps picture and its world bounds (`Config.MiniMap`).
- **On-screen timer:** a card on the right side of the screen, clear of the corner, while you're on a delivery. It shows time left, the stop, live distance, and pay, turns red when you're late, and slides left of the phone while the phone is open. People who ordered food get the same card with the driver's ETA. Position is set in `Config.Hud`.

## 2.0: the grind update
- **30 places across the whole map:** the pier, Rex's Diner, Paleto (Mojito Inn, Hen House), Sandy, Harmony, Grapeseed, Chumash, Senora, plus every 24/7 and LTD. 35 customer drop-offs from Chamberlain Hills to Paleto. Drivers get work within 4 mi, and deliveries run up to 5 mi.
- **Pay:** $12 base + $4/mile (min $19, max $31), plus tips of $6-10 ($12-22 for high tippers). Tipped orders run about $25-40. No-tip orders pay less, so tips still matter when choosing what to accept.
- **Hot zones:** 2 are hot at once (4 during the 11-14 and 17-21 rush), each for 8-15 min, then they cool off and move. Inside one, offers come about 3x faster and pay +$1-2 (+$2-3 at peak). Outside, offers slow down a little. They show on the map as red circles, in the app's zones map, and with alerts when they heat up or cool off.
- **Food condition:** crashes, jumps, hard braking, flipping, speeding, and falling with the bag all knock it down, with an alert each time. It shows on the app and the on-screen timer. NPC customers take 1-2 stars and leave "your food was smashed" reviews. Real customers see the condition, and under 40% one item is ruined.
- **On-time streak:** 4 on-time, good-condition deliveries in a row pay +$5.
- **Live courier:** when no drivers are on, a real ped and vehicle drive from across town to the restaurant, then to you. Everyone can see them, shoot them, run them over, or carjack them. After pickup, that drops the food bag for anyone to grab, and the customer is refunded. Before pickup, a new courier is sent.
- **Courier on real roads:** even when nobody is close enough to spawn them, the courier moves along the actual road route. The customer's game asks GTA's GPS for it silently, with no waypoint or line on their map. The app draws that route in blue, the courier dot and radar blip glide instead of jumping, and the ETA uses the real road distance. If the GPS can't plan a route, it falls back to the old straight line (`Config.NpcCourier.roadRoutes`).
- **Tipping:** checkout offers 10 / 15 / 20 / 25% of the food total (15% preselected, at least $1), a Custom box to type any amount up to $100, or No tip (`Config.Customer.tipPercents`).
- **Road lines everywhere:** the offer map and your active delivery show the real road route (you → restaurant → customer), re-planned if you go more than about 80 m off it. The courier's restaurant → you leg is drawn on roads too.
- **Delivery timer card:** compact, and hidden while the pause menu / big map is open, during fades and cutscenes, when the HUD is hidden, or when another script's menu has the mouse. Players can toggle it with `/ddhud` (remembered).
- **Waypoints:** accepting an order and picking it up both set a normal GPS waypoint (`Config.AutoWaypoint`). The hidden route planner puts your route line and waypoint back after it runs.
- **Braking alerts:** only a real slam counts, losing about 31 mph in half a second from 50+ mph with no crash, at most once every 10 s (`Config.Driving.hardBrake*`).
- **Courier drives the drawn line:** a spawned courier is steered along the planned route with waypoints 250 m ahead, so they take the same streets you see on the map.
- **Map:** scroll the mouse wheel to zoom (after zooming, the map keeps the moving car centered; dragging stops that until you press ⌖), drag to pan, and use + / − or ⌖ to snap back to the whole route.

## 2.5: cancelling and the order ring
- Cancelling actually ends the order now: the timer, the tracking blip and the courier all go away, and nothing gets delivered.
- Full refund until the food is picked up. After pickup you can still cancel, but you get `Config.Customer.lateCancelRefund` back (default 0, like the real app). Once the courier is at your door it can't be cancelled.
- A player driver whose order is cancelled after pickup gets `lateCancelDriverPay` (default half) of the job's pay.
- If the game ever misses an update, it checks with the server every 10 seconds and clears a leftover timer.
- New orders play `html/sounds/order-ring.mp3` (Config.Sounds). It stops as soon as you accept, decline, or the offer expires.

## 3.0: new app look
- **Dark delivery-app design** with three tabs at the bottom: **Order**, **Orders** and **Drive**.
- **Order:** "Delivery, Deliver to <your street>" (tap ⟳ to refresh). Each restaurant is a card with a picture,
  its logo, an OPEN badge, the number of items and how far it is ("3 min walk", "4 min drive").
  Closed places are folded into "N closed" at the bottom, showing when they open and how far away they are.
- **Opening hours** use the in-game clock: `Config.StoreHours` sets hours per kind of food, and any
  restaurant can have its own `hours = { 8, 22 }`. Closed places can't be ordered from (checked by the server too).
- **Store pictures:** without a picture, each card shows the map around the restaurant tinted in its colour
  (`Config.StoreArt`). To use real photos, give a restaurant `banner = 'https://...'` and `logo = 'https://...'`.
- **Orders:** your live order with the driver on the map, plus your recent orders (Delivered / Cancelled).
- **Drive:** the dashing map screen, offers, deliveries, earnings (☰) and ratings (★) as before.
- **Fixes:** couriers arriving near you no longer throw a script error (`NetworkDoesNetIdExist` doesn't exist;
  it's `NetworkDoesNetworkIdExist`). The tracker's house icon no longer jumps to the corner of the screen.

## Install
1. `ensure nrp-doordrop` after ox_lib, ox_target, oxmysql, qb-core, tgiann-inventory and 17mov_Phone.
2. The table is created/upgraded automatically (`sql/install.sql` if you prefer to run it yourself).
3. **Menu items:** built from NRP's items.lua. If you rename or remove an item there, update the menu entry too.
4. Optional: `screenshot-basic` for real photo thumbnails.

## Pay
Realistic gig pay: $3 base + $1.50/mile, tips $2-6 (high tippers $8-18). Most orders pay $5-$12. All in `Config.Pay` / `Config.Tips`.

## Things to verify in game
- Pickup/dropoff coords (`/ddcoords` copies your position). Pickup heading = the way the worker faces.
- Bag hand offsets in `Config.Bags`.
- `Config.GiveItem` uses `exports['tgiann-inventory']:AddItem(src, item, amount)`. Adjust if your tgiann version differs.
- Menu pictures: if you see letter tiles instead of food, check that your tgiann image resource is named `inventory_images` and adjust `Config.ItemImage`.
