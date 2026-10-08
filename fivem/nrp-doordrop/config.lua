Config = {}

Config.Debug   = false
Config.AppName = 'DoorDrop'

---------------------------------------------------------------------
-- Opening the app
---------------------------------------------------------------------
Config.OpenCommand     = 'doordrop'
Config.OpenKey         = 'F6'   -- players can rebind under Settings > Key Bindings > FiveM
Config.QuickAcceptKey  = ''     -- optional: accept an offer without opening the phone ('' = unbound)
Config.QuickDeclineKey = ''
Config.DevCommand      = 'ddcoords' -- prints + copies your vector4 (for adding pickups / dropoffs)

-- Return false to block opening the standalone app (only used when the phone app isn't running).
Config.CanOpen = function()
    return true
end

---------------------------------------------------------------------
-- 17mov_Phone integration
-- When the phone is running, DoorDrop installs as a real app on it.
-- If the phone isn't started, the built-in standalone phone overlay is used instead.
---------------------------------------------------------------------
Config.Phone = {
    Enabled        = true,
    Resource       = '17mov_Phone',
    AppName        = 'doordrop',
    Label          = 'DoorDrop',
    PreInstalled   = true,
    Default        = false,
    Rating         = 4.7,
    IconBackground = { angle = 135, colors = { '#FF6A4D', '#C7301B' } },
    NotifyOffers   = true,
    Job            = nil, -- e.g. { name = 'doordrop', grade = 0 } to restrict the app to a job
}

---------------------------------------------------------------------
-- Offers
---------------------------------------------------------------------
-- Long range: drivers get work anywhere on the map. Offers prefer restaurants within MaxPickupMiles of you,
-- and customers can be anywhere from DropoffMiles.min to .max away from the restaurant.
Config.MaxPickupMiles = 4.0
Config.DropoffMiles   = { min = 0.3, max = 5.0 }
Config.RoadFactor     = 1.3

Config.Offer = {
    timeout         = 30,
    waitMin         = 25,
    waitMax         = 70,
    declineCooldown = 15,
    afterDelivery   = 10,
}

-- A typical order pays about $25-40 with the tip. Longer hauls pay more, capped at maxBase.
Config.Pay = {
    base    = 12,   -- flat pay per order
    perMile = 4,    -- per estimated mile
    minBase = 19,
    maxBase = 31,
}

Config.Tips = {
    normal = { min = 6, max = 10 },
    big    = { min = 12, max = 22 },
}

Config.FaceToFaceChance = 0.30
Config.Eta = { base = 240, perMile = 150 }

---------------------------------------------------------------------
-- Pickup style
--   'employee' = a worker comes out holding the bag and hands it to you
--   'shelf'    = the bag waits outside on the ground and disappears when you grab it
---------------------------------------------------------------------
Config.Pickup = {
    style   = 'employee',
    workers = { 'u_m_y_burgerdrug_01', 's_m_m_linecook', 's_m_y_chef_01', 's_f_y_shop_mid' },
}

---------------------------------------------------------------------
-- Hot zones: busy areas that heat up at peak times, then cool off and move.
-- Drive INTO one to get offers much faster, plus a bonus on every order you take there.
-- Outside hot zones offers slow down a little while any zone is hot.
---------------------------------------------------------------------
Config.HotZones = {
    enabled         = true,
    active          = 2,                     -- zones hot at once normally
    activePeak      = 4,                     -- ...during peak hours
    peakHours       = { { 11, 14 }, { 17, 21 } }, -- server clock (24h): lunch and dinner rush
    duration        = { 480, 900 },          -- seconds a zone stays hot
    rest            = 300,                   -- seconds a zone stays cold before it can heat up again
    bonus           = { 1, 2 },              -- extra dollars per order taken inside a hot zone
    bonusPeak       = { 2, 3 },
    insideWaitMult  = 0.35,                  -- offers come about 3x faster inside a hot zone
    outsideWaitMult = 1.25,                  -- and a bit slower everywhere else
    blip            = { color = 1, alpha = 90, sprite = 436 },
    zones = {
        { name = 'Downtown',        x = 150.0,   y = -850.0,  radius = 450.0 },
        { name = 'Del Perro',       x = -1350.0, y = -900.0,  radius = 450.0 },
        { name = 'Del Perro Pier',  x = -1750.0, y = -1150.0, radius = 350.0 },
        { name = 'Vespucci',        x = -1150.0, y = -1400.0, radius = 400.0 },
        { name = 'Vinewood',        x = 250.0,   y = 250.0,   radius = 450.0 },
        { name = 'Rockford Hills',  x = -700.0,  y = 150.0,   radius = 400.0 },
        { name = 'Little Seoul',    x = -700.0,  y = -900.0,  radius = 350.0 },
        { name = 'Mirror Park',     x = 1150.0,  y = -450.0,  radius = 400.0 },
        { name = 'South Los Santos', x = 50.0,   y = -1650.0, radius = 450.0 },
        { name = 'Harmony',         x = 1000.0,  y = 2700.0,  radius = 600.0 },
        { name = 'Sandy Shores',    x = 1750.0,  y = 3700.0,  radius = 550.0 },
        { name = 'Grapeseed',       x = 1700.0,  y = 4800.0,  radius = 500.0 },
        { name = 'Paleto Bay',      x = -250.0,  y = 6300.0,  radius = 550.0 },
        { name = 'Chumash',         x = -3100.0, y = 800.0,   radius = 550.0 },
    },
}

---------------------------------------------------------------------
-- Driving & food condition. The food starts at 100%. Crashes, air time, hard braking, flipping
-- and speeding knock it down (with an alert each time). Low condition costs stars, earns bad
-- reviews, and for real customers can ruin part of the order.
---------------------------------------------------------------------
Config.Driving = {
    crashPerDamage = 0.25,  -- % lost per point of vehicle body damage
    airtime        = 6,     -- % lost per jump (airborne over 0.6s)
    hardBrake      = 2,     -- % lost for slamming the brakes (not normal hard stops)
    hardBrakeDrop  = 14.0,  -- m/s lost within half a second to count as a slam (~31 mph gone instantly)
    hardBrakeFrom  = 22.0,  -- only from real speed (m/s, ~50 mph)
    hardBrakeCooldown = 10, -- seconds before another brake alert can count
    flip           = 25,    -- % lost if the vehicle ends up on its roof or side
    dropBag        = 15,    -- % lost falling over on foot with the bag
    speedingMph    = 95,    -- sustained speed over this...
    speeding       = 2,     -- ...costs this much every 5 seconds
    alertCooldown  = 4,     -- seconds between alerts
    starPenalty    = { { below = 75, stars = 1 }, { below = 45, stars = 2 } }, -- NPC customers
    ruinBelow      = 40,    -- real customers: under this, one item is ruined and doesn't arrive
}

-- On-time, good-condition deliveries in a row. Every `every` in a row pays `bonus` extra.
Config.Streak = { every = 4, bonus = 5, minCondition = 80 }

---------------------------------------------------------------------
-- Ratings, reviews & tiers
---------------------------------------------------------------------
Config.Rating = {
    window                   = 50,
    lateStep                 = 90,
    spillPenalty             = 1,
    randomFourChance         = 0.06,
    unassignAfterPickupStars = 1,
}


Config.Tiers = {
    { name = 'Platinum', minAcceptance = 85, minRating = 4.8, minDeliveries = 50, tipMult = 1.30, bigTipChance = 0.35, zeroTipChance = 0.03, waitMult = 0.70 },
    { name = 'Gold',     minAcceptance = 70, minRating = 4.6, minDeliveries = 20, tipMult = 1.15, bigTipChance = 0.20, zeroTipChance = 0.08, waitMult = 0.85 },
    { name = 'Silver',   minAcceptance = 50, minRating = 4.3, minDeliveries = 5,  tipMult = 1.00, bigTipChance = 0.10, zeroTipChance = 0.15, waitMult = 1.00 },
    { name = 'Bronze',   minAcceptance = 0,  minRating = 0.0, minDeliveries = 0,  tipMult = 0.80, bigTipChance = 0.03, zeroTipChance = 0.35, waitMult = 1.25 },
}

-- NPC customers always rate you; these decide when they also leave a written review.
Config.Reviews = {
    keep           = 30,   -- reviews kept per driver
    npcChance      = 0.45, -- chance an NPC writes a review on a good delivery
    npcChanceBad   = 0.90, -- ...on a delivery rated 3 stars or less
    names = { 'Tanisha', 'Marcus', 'Brittany', 'Deshawn', 'Kyle', 'Maria', 'Jerome', 'Ashley', 'Tyrone', 'Becky',
              'Luis', 'Keisha', 'Chad', 'Priya', 'Andre', 'Megan', 'Hector', 'Jasmine', 'Trevor', 'Destiny' },
    fast    = { 'Super fast, food was still hot!', 'Got here way quicker than the app said.', 'Speedy and polite. Thank you!',
                'Fastest delivery I\'ve had in Los Santos.', 'Driver was on it. 10/10.' },
    great   = { 'Everything was perfect.', 'Great service, will order again.', 'Food was hot and nothing missing.',
                'Left it right where I asked. Appreciate it.', 'Smooth delivery, thanks!' },
    handoff = { 'Really friendly, handed it right to me.', 'Nice driver, even said have a good night.',
                'Quick handoff, super polite.', 'Met me at the door, no issues.' },
    okay    = { 'It was fine.', 'Food got here. Nothing special.', 'Took a bit but it was okay.', 'Decent.' },
    late    = { 'Took forever. Food was cold.', 'App said 10 minutes, it was way longer.', 'Fries were soggy by the time it got here.',
                'Why did this take so long?', 'Late again. Not happy.' },
    spilled = { 'Drink spilled all over the bag.', 'Bag looked like it went through a car wash.', 'Food was smashed. Were you drag racing?',
                'Half my order was on the bottom of the bag.' },
    noShow  = { 'Driver took my food and never showed up.', 'Never got my order.', 'Where did my food go??' },
}

---------------------------------------------------------------------
-- Player ordering ("Order food" in the app)
---------------------------------------------------------------------
Config.Customer = {
    enabled       = true,
    deliveryFee   = 4,      -- charged to the customer
    serviceRate   = 0.15,   -- service fee as a share of the subtotal
    tipPercents   = { 10, 15, 20, 25 }, -- tip buttons at checkout, as a share of the food total
    defaultTip    = 15,                 -- preselected percent (0 = no tip)
    minTip        = 1,                  -- a percent tip is never less than this many dollars
    maxTip        = 100,                -- cap for any tip, including a custom amount
    maxQty        = 10,     -- per menu item
    maxItems      = 15,     -- per order
    searchTimeout = 180,    -- seconds to find a driver before refunding
    handoffRange  = 5.0,    -- driver must be this close to the customer to hand it over
    rateWindow    = 1800,   -- seconds after delivery the customer can still rate
    -- Cancelling: a full refund until the food is picked up. After that (driver/courier on the way)
    -- you can still cancel, but the food is already made, so only this share comes back (0 = none).
    -- Once the courier is at your door it can't be cancelled.
    lateCancelRefund   = 0.0,
    lateCancelDriverPay = 0.5,  -- share of the job's pay a player driver still gets if cancelled after pickup
}

-- NPC courier: delivers player orders when no drivers are clocked in, or none take it in time.
-- Tracked on the customer's map + in the app. A real vehicle and ped show up for the last stretch.
Config.NpcCourier = {
    enabled        = true,
    fallbackAfter  = 90,           -- seconds searching for a player driver before a courier takes it
    prepTime       = { 45, 90 },   -- seconds the courier waits at the restaurant
    speed          = 13.0,         -- m/s along the road (about 29 mph)
    arriveDistance = 180.0,        -- meters out: the courier spawns in a real vehicle near you
    driveTimeout   = 45,           -- seconds the courier gets to drive up before they park and walk the rest
    roadRoutes     = true,         -- follow GTA's GPS road route on the map (false = straight line)
    arriveTimeout  = 240,          -- safety net: order completes if the courier hasn't finished by then

    -- Live courier: a real ped + vehicle driving from somewhere in the city to the restaurant, then to you.
    -- Everyone sees them. They exist physically wherever any player is close enough for the game to run them,
    -- and can be shot, rammed, or carjacked. If that happens after pickup, the food bag drops for anyone to grab
    -- and the customer is refunded. Before pickup, a new courier is sent.
    live = {
        enabled          = true,
        driveSpeed       = 13.0,   -- m/s the AI aims for (about 29 mph)
        materializeRange = 250.0,  -- a player this close makes the courier physically appear
        despawnRange     = 380.0,  -- nobody this close: the courier goes back to "on the map only"
        startDistance    = { 400, 1600 }, -- how far from the restaurant the courier starts (meters)
        stuckSeconds     = 45,     -- hasn't moved in this long: respawn them further along the route
        lootLifetime     = 300,    -- seconds a dropped food bag stays in the world
        vehicles = {               -- `type` is required to spawn server-side: 'bike' or 'automobile'
            { model = 'faggio',  type = 'bike' },
            { model = 'faggio2', type = 'bike' },
            { model = 'blista',  type = 'automobile' },
            { model = 'panto',   type = 'automobile' },
            { model = 'issi2',   type = 'automobile' },
        },
    },

    -- Couriers aren't paid by the customer's goodwill like player drivers are:
    -- skip the tip and some of your order might not make it. Player drivers ALWAYS deliver everything.
    missing = {
        enabled      = true,
        noTipChance  = 0.50,   -- $0 tip: 50% chance something is missing
        lowTip       = 2,      -- tips at or under this count as low
        lowTipChance = 0.15,   -- low tip: 15% chance
        maxMissing   = 2,      -- at most this many items go missing (always leaves at least one)
        refund       = false,  -- true = refund the missing items' price
    },
    blip           = { sprite = 226, color = 1, label = 'DoorDrop courier' },
    vehicles       = { 'faggio', 'faggio2', 'blista', 'panto', 'issi2' },
    peds           = { 'a_m_y_hipster_02', 'a_f_y_hipster_01', 'a_m_y_stbla_01', 'a_f_y_eastsa_01', 'a_m_y_genstreet_01' },
    names          = { 'Jordan (Courier)', 'Sam (Courier)', 'Alex (Courier)', 'Riley (Courier)', 'Casey (Courier)' },
}

---------------------------------------------------------------------
-- Mini map (in the app) and the on-screen delivery timer
---------------------------------------------------------------------
-- The app's mini map uses the same map picture as the 17mov_Phone Maps app, with its world bounds.
Config.MiniMap = {
    enabled = true,
    image   = 'https://cfx-nui-17mov_Phone/web/images/Map.png',
    bounds  = { xMin = -5688, yMin = -4048, xMax = 6724, yMax = 8364 },
}

-- Delivery timer on screen, outside the phone. Any CSS length works.
-- Ringtone when a new order comes in (plays from html/sounds, phone open or not).
-- Swap the file for your own .mp3 in html/sounds. enabled = false uses GTA's text tone instead.
Config.Sounds = {
    offer = {
        enabled = true,
        file    = 'sounds/order-ring.mp3',
        volume  = 0.45,   -- 0.0 - 1.0
        loop    = false,  -- true = keeps ringing until you accept/decline
    },
}

Config.Hud = {
    enabled     = true,
    right       = '2.5vw',  -- distance from the right edge of the screen
    bottom      = '30vh',   -- distance from the bottom (lower right, clear of the corner)
    phoneOpenRight = '390px', -- slides left of the phone while it's open, so it's never covered
    customer    = true,     -- also show the courier/driver ETA to people who ordered food
    compact     = true,     -- smaller card
    toggleCommand = 'ddhud', -- players can hide/show the card (remembered between sessions)
    -- hidden automatically while the pause menu / big map is open, the screen is faded,
    -- the game HUD is hidden, or another script's menu has the mouse (inventory, etc.)
}

-- Put a normal GPS waypoint on the next stop when you accept an order and when you pick it up.
Config.AutoWaypoint = true

-- Menu pictures. %s = the menu entry's `image` (the same file tgiann-inventory shows).
-- tgiann keeps item images in the inventory_images resource, images/ folder. Shows a letter tile if one is missing.
Config.ItemImage = 'https://cfx-nui-inventory_images/images/%s'

-- Gives a delivered menu item to the customer. Runs server-side.
Config.GiveItem = function(src, item, amount)
    return exports['tgiann-inventory']:AddItem(src, item, amount)
end

---------------------------------------------------------------------
-- Anti-exploit
---------------------------------------------------------------------
Config.InteractRange = 12.0
Config.MaxSpeed      = 70.0

---------------------------------------------------------------------
-- World
---------------------------------------------------------------------
Config.SpawnRadius     = 80.0
Config.LeftoverSeconds = 60
Config.Screenshots     = true

Config.Blips = {
    pickup  = { sprite = 52, color = 1 },
    dropoff = { sprite = 40, color = 2 },
}

Config.PhotoAnim = {
    dict = 'amb@world_human_tourist_mobile@male@base',
    clip = 'base',
    prop = 'prop_npc_phone_02',
}

Config.Bags = {
    bag   = { model = 'prop_food_bs_bag_01', bone = 57005, pos = vec3(0.32, 0.0, -0.02), rot = vec3(-90.0, 0.0, 80.0) },
    cluck = { model = 'prop_food_cb_bag_01', bone = 57005, pos = vec3(0.32, 0.0, -0.02), rot = vec3(-90.0, 0.0, 80.0) },
    paper = { model = 'prop_paper_bag_small', bone = 57005, pos = vec3(0.30, 0.0, -0.02), rot = vec3(-90.0, 0.0, 80.0) },
    pizza = { model = 'prop_pizza_box_02', bone = 28422, pos = vec3(0.01, -0.10, -0.159), rot = vec3(20.0, 0.0, 0.0),
              anim = { dict = 'anim@heists@box_carry@', clip = 'idle' } },
}

Config.CustomerModels = {
    'a_m_y_hipster_01', 'a_f_y_hipster_02', 'a_m_m_business_01', 'a_f_m_bevhills_01',
    'a_m_y_stbla_02', 'a_f_y_tourist_01', 'a_m_m_eastsa_02', 'a_f_y_eastsa_03',
}

---------------------------------------------------------------------
-- Opening hours (in-game clock, 24h). The Order tab shows open places first and the rest
-- under "closed"; closed places can't be ordered from. { open, close } - close can be past
-- midnight ({ 17, 3 } = 5pm to 3am). { 0, 24 } = always open.
-- A restaurant can set its own:  hours = { 8, 22 }
---------------------------------------------------------------------
Config.StoreHours = {
    enabled = true,
    default = { 0, 24 },
    byCategory = {
        ['Burgers']              = { 7, 3 },
        ['Pizza & pasta']        = { 11, 1 },
        ['Coffee']               = { 6, 19 },
        ['Tacos & bar food']     = { 11, 3 },
        ['Seafood']              = { 11, 23 },
        ['Bar food']             = { 15, 4 },
        ['Convenience']          = { 0, 24 },
        ['Hot dogs & ice cream'] = { 9, 21 },
        ['Diner']                = { 6, 23 },
        ['Chicken & grill']      = { 10, 23 },
        ['Café & boba']          = { 8, 20 },
        ['Ramen & sushi']        = { 11, 23 },
    },
}

---------------------------------------------------------------------
-- Store pictures on the Order tab. Without a picture, each card shows the map around the
-- restaurant with its colour. Any image URL works for a restaurant's own:
--   banner = 'https://cfx-nui-my-images/burgershot.png', logo = '...'
-- `color` tints the card when there's no picture.
---------------------------------------------------------------------
Config.StoreArt = {
    ['Burger Shot']     = { color = '#E8452C', icon = '🍔' },
    ['Up-n-Atom']       = { color = '#E43D3D', icon = '🍔' },
    ['Pizza This']      = { color = '#2E9E5B', icon = '🍕' },
    ['Bean Machine']    = { color = '#7A4A2A', icon = '☕' },
    ["Horny's Burgers"] = { color = '#D9312B', icon = '🍔' },
    ['Tequi-la-la']     = { color = '#B0388A', icon = '🌮' },
    ["Pearl's Seafood"] = { color = '#1F7FB5', icon = '🦐' },
    ['Hookies']         = { color = '#2B6CB0', icon = '🐟' },
    ['Yellow Jack Inn'] = { color = '#C9962B', icon = '🍺' },
    ['24/7']            = { color = '#1E9A4A', icon = '🏪' },
    ['LTD Gasoline']    = { color = '#2F6FD6', icon = '⛽' },
    ['Pier Snack Shack'] = { color = '#E58A1F', icon = '🌭' },
    ["Rex's Diner"]     = { color = '#C2403A', icon = '🥞' },
    ['Mojito Inn']      = { color = '#2FA39B', icon = '🍹' },
    ['Hen House']       = { color = '#D07A21', icon = '🍗' },
    ['Liquor Ace']      = { color = '#8B5CF6', icon = '🛒' },
    ['UwU Café']        = { color = '#E86AA6', icon = '🧋' },
    ['Noodle Exchange'] = { color = '#D9472B', icon = '🍜' },
}

---------------------------------------------------------------------
-- Restaurants. `pickup` = where the worker / bag waits outside; heading = the way the worker faces (toward the street).
-- Menus use real NRP tgiann-inventory items (nrp-vending consumables). `image` is the item's image file from
-- items.lua, so the app shows the same picture as the inventory. Verify coords in game with /ddcoords.
-- `disabled = true` hides a restaurant until you've set its pickup spot.
---------------------------------------------------------------------
Config.Restaurants = {
    { label = 'Burger Shot', area = 'Del Perro', category = 'Burgers', bag = 'bag', pickup = vec4(-1183.4, -884.1, 13.8, 300.0),
      menu = {
          { item = 'burger_cheese',                label = 'Cheeseburger',                    price =  7, image = 'cheeseburger.png' },
          { item = 'burger_beef_double',           label = 'Double Beef Burger',              price =  9, image = 'burger.png' },
          { item = 'burger_chicken',               label = 'Chicken Burger',                  price =  7, image = 'chickenburger.png' },
          { item = 'burger_veggie',                label = 'Veggie Burger',                   price =  6, image = 'burger.png' },
          { item = 'chicken_nugget_pack',          label = 'Chicken Nuggets',                 price =  5, image = 'nuggets.png' },
          { item = 'fries_pack',                   label = 'Portion of Fries',                price =  3, image = 'fries.png' },
          { item = 'onion_ring_pack',              label = 'Onion Rings',                     price =  4, image = 'bbs_octupus_rings.png' },
          { item = 'milkshake_vanilya',            label = 'Vanilla Milkshake',               price =  4, image = 'cb_milkshake.png' },
          { item = 'milkshake_cikolata',           label = 'Chocolate Milkshake',             price =  4, image = 'cb_milkshake.png' },
          { item = 'ecola',                        label = 'Cola',                            price =  2, image = 'ecola.png' },
          { item = 'sprunk',                       label = 'Sprite',                          price =  2, image = 'sprunk.png' },
      } },
    { label = 'Up-n-Atom', area = 'Vinewood', category = 'Burgers', bag = 'paper', pickup = vec4(88.5, 285.5, 110.2, 250.0),
      menu = {
          { item = 'burger_2x',                    label = 'Double Burger',                   price =  8, image = 'hamburger.png' },
          { item = 'burger_3x',                    label = 'Triple Burger',                   price = 10, image = 'hamburger.png' },
          { item = 'burger_4x',                    label = 'Stack Burger',                    price = 12, image = 'hamburger.png' },
          { item = 'cheeseburger',                 label = 'Cheese Burger',                   price =  7, image = 'cheeseburger.png' },
          { item = 'serratedfrenchfries',          label = 'Crinkle Fries',                   price =  3, image = 'frenchfries_generic.png' },
          { item = 'milkshake_cilek',              label = 'Strawberry Milkshake',            price =  4, image = 'cb_milkshake.png' },
          { item = 'milkshake_karamel',            label = 'Caramel Milkshake',               price =  4, image = 'cb_milkshake.png' },
          { item = 'ecolalight',                   label = 'Cola Light',                      price =  2, image = 'ecolalight.png' },
          { item = 'sprunklight',                  label = 'Sprite Light',                    price =  2, image = 'sprunklight.png' },
      } },
    { label = 'Pizza This', area = 'Mirror Park', category = 'Pizza & pasta', bag = 'pizza', pickup = vec4(795.9, -751.6, 26.8, 90.0),
      menu = {
          { item = 'pizza_margherita',             label = 'Margherita Pizza',                price = 13, image = 'pizza_margherita.png' },
          { item = 'pizza_etli',                   label = 'Beef Pizza',                      price = 15, image = 'pizza.png' },
          { item = 'pizza_karisik',                label = 'Supreme Pizza',                   price = 15, image = 'pizza.png' },
          { item = 'pizza_tavuklu',                label = 'Chicken Pizza',                   price = 15, image = 'bbs_chicken_pizza.png' },
          { item = 'pizza_ananasli',               label = 'Hawaiian Pizza',                  price = 14, image = 'pizza.png' },
          { item = 'pizza_mantarli',               label = 'Mushroom Pizza',                  price = 14, image = 'pmushroomspizza.png' },
          { item = 'pizza_sebzeli',                label = 'Vegetable Pizza',                 price = 13, image = 'pizza.png' },
          { item = 'plate_pasta_carbonara',        label = 'Pasta Carbonara',                 price = 12, image = 'pastafresca.png' },
          { item = 'plate_pasta_bolognese',        label = 'Pasta Bolognese',                 price = 12, image = 'bolognese.png' },
          { item = 'plate_pasta_alfredo',          label = 'Pasta Alfredo',                   price = 12, image = 'bbs_italian_fettuccine_alfredo.png' },
          { item = 'tiramisu',                     label = 'Tiramisu',                        price =  6, image = 'tiramisu.png' },
          { item = 'ecola',                        label = 'Cola',                            price =  2, image = 'ecola.png' },
      } },
    { label = 'Bean Machine', area = 'Rockford Hills', category = 'Coffee', bag = 'paper', pickup = vec4(-628.2, 238.7, 81.9, 90.0),
      menu = {
          { item = 'coffee_americano',             label = 'Americano',                       price =  3, image = 'bbs_americano.png' },
          { item = 'coffee_espresso',              label = 'Espresso',                        price =  3, image = 'bbs_espresso.png' },
          { item = 'coffee_cappuccino',            label = 'Cappuccino',                      price =  4, image = 'bbs_cappuccino.png' },
          { item = 'coffee_caramel_latte',         label = 'Caramel Latte',                   price =  5, image = 'bean_carmalcoffee.png' },
          { item = 'coffee_iced_latte',            label = 'Iced Latte',                      price =  5, image = 'bbs_icedlatte.png' },
          { item = 'coffee_mocha',                 label = 'Mocha',                           price =  5, image = 'bbs_mocha.png' },
          { item = 'coffee_matcha_latte',          label = 'Matcha Latte',                    price =  5, image = 'coffee.png' },
          { item = 'donut_choco',                  label = 'Chocolate Donut',                 price =  2, image = 'donut5.png' },
          { item = 'donut_strawberry',             label = 'Strawberry Donut',                price =  2, image = 'donut7.png' },
          { item = 'berry_muffin',                 label = 'Berry Muffin',                    price =  3, image = 'muffin.png' },
          { item = 'cookie_choco',                 label = 'Chocolate Cookie',                price =  2, image = 'cookie.png' },
          { item = 'plate_toast',                  label = 'Toasted Sandwich',                price =  6, image = 'tosti.png' },
      } },
    { label = "Horny's Burgers", area = 'Mirror Park', category = 'Burgers', bag = 'bag', pickup = vec4(1240.4, -357.0, 69.1, 165.0),
      menu = {
          { item = 'burger_beef',                  label = 'Beef Burger',                     price =  7, image = 'burger.png' },
          { item = 'burger_cheese',                label = 'Cheeseburger',                    price =  7, image = 'cheeseburger.png' },
          { item = 'hotdog_ketchup',               label = 'Hot Dog with Ketchup',            price =  4, image = 'hotdog_ketchup.png' },
          { item = 'hotdog_ketchup_mayo',          label = 'Hot Dog with Ketchup & Mayo',     price =  4, image = 'hotdog_ketchup.png' },
          { item = 'chicken_wing_pack',            label = 'Chicken Wings',                   price =  8, image = 'wings.png' },
          { item = 'onion_ring_pack',              label = 'Onion Rings',                     price =  4, image = 'bbs_octupus_rings.png' },
          { item = 'fries_pack',                   label = 'Portion of Fries',                price =  3, image = 'fries.png' },
          { item = 'milkshake_muz',                label = 'Banana Milkshake',                price =  4, image = 'cb_milkshake.png' },
          { item = 'ecola',                        label = 'Cola',                            price =  2, image = 'ecola.png' },
      } },
    { label = 'Tequi-la-la', area = 'West Vinewood', category = 'Tacos & bar food', bag = 'paper', pickup = vec4(-563.8, 273.5, 83.0, 175.0),
      menu = {
          { item = 'vutacos',                      label = 'Taco Plate',                      price =  8, image = 'taco_plate.png' },
          { item = 'nplate',                       label = 'Nachos Plate',                    price =  9, image = 'nacho_plate.png' },
          { item = 'taco_birria',                  label = 'Birria Taco',                     price =  4, image = 'taco_plate.png' },
          { item = 'taco_al_pastor',               label = 'Al Pastor Taco',                  price =  4, image = 'taco_plate.png' },
          { item = 'taco_asada',                   label = 'Carne Asada Taco',                price =  4, image = 'taco_plate.png' },
          { item = 'quesadilla',                   label = 'Quesadilla',                      price =  7, image = 'grilled_wrap.png' },
          { item = 'chicken_wing_pack',            label = 'Chicken Wings',                   price =  8, image = 'wings.png' },
          { item = 'lemonade_juice',               label = 'Lemonade',                        price =  3, image = 'farming_lemonjuice.png' },
      } },
    { label = "Pearl's Seafood", area = 'Del Perro Pier', category = 'Seafood', bag = 'paper', pickup = vec4(-1837.5, -1182.3, 14.3, 145.0),
      menu = {
          { item = 'plate_fish',                   label = 'Grilled Fish',                    price = 16, image = 'seafood_grilledfish.png' },
          { item = 'plate_shrimp',                 label = 'Shrimp',                          price = 15, image = 'seafood_shrimpcocktail.png' },
          { item = 'plate_calamari',               label = 'Calamari',                        price = 13, image = 'seafood_calamari.png' },
          { item = 'plate_crab',                   label = 'Crab',                            price = 22, image = 'seafood_kingcrab.png' },
          { item = 'plate_oysters',                label = 'Oysters',                         price = 18, image = 'oyster.png' },
          { item = 'plate_mussels',                label = 'Mussels',                         price = 14, image = 'mussels.png' },
          { item = 'plate_octopus',                label = 'Grilled Octopus',                 price = 17, image = 'octopus.png' },
          { item = 'taco_fish',                    label = 'Fish Taco',                       price =  5, image = 'taco_fish.png' },
          { item = 'water_bottle',                 label = 'Water Bottle',                    price =  2, image = 'water_bottle.png' },
      } },
    { label = 'Hookies', area = 'Chumash', category = 'Seafood', bag = 'paper', pickup = vec4(-2193.0, 4289.0, 49.2, 60.0),
      menu = {
          { item = 'taco_fish',                    label = 'Fish Taco',                       price =  5, image = 'taco_fish.png' },
          { item = 'taco_shrimp',                  label = 'Shrimp Taco',                     price =  5, image = 'bbs_shrimp_taco.png' },
          { item = 'plate_hamsi',                  label = 'Fried Anchovies',                 price = 11, image = 'seafood_grilledfish.png' },
          { item = 'plate_calamari',               label = 'Calamari',                        price = 12, image = 'seafood_calamari.png' },
          { item = 'plate_fish',                   label = 'Grilled Fish',                    price = 15, image = 'seafood_grilledfish.png' },
          { item = 'fries_pack',                   label = 'Portion of Fries',                price =  3, image = 'fries.png' },
          { item = 'lemonade_juice',               label = 'Lemonade',                        price =  3, image = 'farming_lemonjuice.png' },
      } },
    { label = 'Yellow Jack Inn', area = 'Sandy Shores', category = 'Bar food', bag = 'paper', pickup = vec4(1986.0, 3054.0, 47.2, 330.0),
      menu = {
          { item = 'vusliders',                    label = 'Sliders',                         price =  8, image = 'burger.png' },
          { item = 'tots',                         label = 'Tits or Tots',                    price =  5, image = 'tots.png' },
          { item = 'nplate',                       label = 'Nachos Plate',                    price =  8, image = 'nacho_plate.png' },
          { item = 'chicken_wing_pack',            label = 'Chicken Wings',                   price =  8, image = 'wings.png' },
          { item = 'hotdog',                       label = 'Hotdog',                          price =  3, image = 'hotdog.png' },
          { item = 'burger_beef_double',           label = 'Double Beef Burger',              price =  9, image = 'burger.png' },
          { item = 'ecola',                        label = 'Cola',                            price =  2, image = 'ecola.png' },
      } },
    { label = '24/7', area = 'Strawberry', category = 'Convenience', bag = 'paper', pickup = vec4(29.3, -1350.8, 29.3, 180.0),
      menu = {
          { item = 'water_bottle',                 label = 'Water Bottle',                    price =  1, image = 'water_bottle.png' },
          { item = 'ecola',                        label = 'Cola',                            price =  2, image = 'ecola.png' },
          { item = 'sprunk',                       label = 'Sprite',                          price =  2, image = 'sprunk.png' },
          { item = 'crisps',                       label = 'Crisps',                          price =  2, image = 'chips.png' },
          { item = 'snikkel_candy',                label = 'Snikkel',                         price =  2, image = 'snikkel_candy.png' },
          { item = 'twerks_candy',                 label = 'Twerks',                          price =  2, image = 'twerks_candy.png' },
          { item = 'sandwich',                     label = 'Sandwich',                        price =  5, image = 'sandwich.png' },
          { item = 'sandwich_chicken',             label = 'Chicken Sandwich',                price =  6, image = 'chickensandwich.png' },
          { item = 'hotdog',                       label = 'Hotdog',                          price =  3, image = 'hotdog.png' },
          { item = 'orange_juice',                 label = 'Orange Juice',                    price =  3, image = 'farming_orangejuice.png' },
          { item = 'coffee',                       label = 'Coffee',                          price =  2, image = 'coffee.png' },
      } },
    { label = 'LTD Gasoline', area = 'Grove Street', category = 'Convenience', bag = 'paper', pickup = vec4(-53.5, -1757.0, 29.4, 50.0),
      menu = {
          { item = 'water_bottle',                 label = 'Water Bottle',                    price =  1, image = 'water_bottle.png' },
          { item = 'ecola',                        label = 'Cola',                            price =  2, image = 'ecola.png' },
          { item = 'sprunk',                       label = 'Sprite',                          price =  2, image = 'sprunk.png' },
          { item = 'crisps',                       label = 'Crisps',                          price =  2, image = 'chips.png' },
          { item = 'snikkel_candy',                label = 'Snikkel',                         price =  2, image = 'snikkel_candy.png' },
          { item = 'twerks_candy',                 label = 'Twerks',                          price =  2, image = 'twerks_candy.png' },
          { item = 'sandwich',                     label = 'Sandwich',                        price =  5, image = 'sandwich.png' },
          { item = 'sandwich_chicken',             label = 'Chicken Sandwich',                price =  6, image = 'chickensandwich.png' },
          { item = 'hotdog',                       label = 'Hotdog',                          price =  3, image = 'hotdog.png' },
          { item = 'orange_juice',                 label = 'Orange Juice',                    price =  3, image = 'farming_orangejuice.png' },
          { item = 'coffee',                       label = 'Coffee',                          price =  2, image = 'coffee.png' },
      } },
    { label = '24/7', area = 'Downtown Vinewood', category = 'Convenience', bag = 'paper', pickup = vec4(374.9, 321.9, 103.4, 165.0),
      menu = {
          { item = 'water_bottle',                 label = 'Water Bottle',                    price =  1, image = 'water_bottle.png' },
          { item = 'ecola',                        label = 'Cola',                            price =  2, image = 'ecola.png' },
          { item = 'sprunk',                       label = 'Sprite',                          price =  2, image = 'sprunk.png' },
          { item = 'crisps',                       label = 'Crisps',                          price =  2, image = 'chips.png' },
          { item = 'snikkel_candy',                label = 'Snikkel',                         price =  2, image = 'snikkel_candy.png' },
          { item = 'twerks_candy',                 label = 'Twerks',                          price =  2, image = 'twerks_candy.png' },
          { item = 'sandwich',                     label = 'Sandwich',                        price =  5, image = 'sandwich.png' },
          { item = 'sandwich_chicken',             label = 'Chicken Sandwich',                price =  6, image = 'chickensandwich.png' },
          { item = 'hotdog',                       label = 'Hotdog',                          price =  3, image = 'hotdog.png' },
          { item = 'orange_juice',                 label = 'Orange Juice',                    price =  3, image = 'farming_orangejuice.png' },
          { item = 'coffee',                       label = 'Coffee',                          price =  2, image = 'coffee.png' },
      } },
    { label = '24/7', area = 'Sandy Shores', category = 'Convenience', bag = 'paper', pickup = vec4(1966.0, 3737.0, 32.2, 30.0),
      menu = {
          { item = 'water_bottle',                 label = 'Water Bottle',                    price =  1, image = 'water_bottle.png' },
          { item = 'ecola',                        label = 'Cola',                            price =  2, image = 'ecola.png' },
          { item = 'sprunk',                       label = 'Sprite',                          price =  2, image = 'sprunk.png' },
          { item = 'crisps',                       label = 'Crisps',                          price =  2, image = 'chips.png' },
          { item = 'snikkel_candy',                label = 'Snikkel',                         price =  2, image = 'snikkel_candy.png' },
          { item = 'twerks_candy',                 label = 'Twerks',                          price =  2, image = 'twerks_candy.png' },
          { item = 'sandwich',                     label = 'Sandwich',                        price =  5, image = 'sandwich.png' },
          { item = 'sandwich_chicken',             label = 'Chicken Sandwich',                price =  6, image = 'chickensandwich.png' },
          { item = 'hotdog',                       label = 'Hotdog',                          price =  3, image = 'hotdog.png' },
          { item = 'orange_juice',                 label = 'Orange Juice',                    price =  3, image = 'farming_orangejuice.png' },
          { item = 'coffee',                       label = 'Coffee',                          price =  2, image = 'coffee.png' },
      } },
    { label = '24/7', area = 'Paleto Bay', category = 'Convenience', bag = 'paper', pickup = vec4(1735.0, 6419.0, 35.0, 150.0),
      menu = {
          { item = 'water_bottle',                 label = 'Water Bottle',                    price =  1, image = 'water_bottle.png' },
          { item = 'ecola',                        label = 'Cola',                            price =  2, image = 'ecola.png' },
          { item = 'sprunk',                       label = 'Sprite',                          price =  2, image = 'sprunk.png' },
          { item = 'crisps',                       label = 'Crisps',                          price =  2, image = 'chips.png' },
          { item = 'snikkel_candy',                label = 'Snikkel',                         price =  2, image = 'snikkel_candy.png' },
          { item = 'twerks_candy',                 label = 'Twerks',                          price =  2, image = 'twerks_candy.png' },
          { item = 'sandwich',                     label = 'Sandwich',                        price =  5, image = 'sandwich.png' },
          { item = 'sandwich_chicken',             label = 'Chicken Sandwich',                price =  6, image = 'chickensandwich.png' },
          { item = 'hotdog',                       label = 'Hotdog',                          price =  3, image = 'hotdog.png' },
          { item = 'orange_juice',                 label = 'Orange Juice',                    price =  3, image = 'farming_orangejuice.png' },
          { item = 'coffee',                       label = 'Coffee',                          price =  2, image = 'coffee.png' },
      } },
    -- Across the map: the pier, the desert, Paleto, Grapeseed, the coast. Verify each spot with /ddcoords.
    { label = 'Pier Snack Shack', area = 'Del Perro Pier', category = 'Hot dogs & ice cream', bag = 'paper', pickup = vec4(-1690.0, -1081.5, 13.2, 140.0),
      menu = {
          { item = 'hotdog_ketchup',              label = 'Hot Dog with Ketchup',            price =  4, image = 'hotdog_ketchup.png' },
          { item = 'hotdog_ketchup_mayo',         label = 'Hot Dog with Ketchup & Mayo',     price =  4, image = 'hotdog_ketchup.png' },
          { item = 'hotdog_mayo',                 label = 'Hot Dog with Mayo',               price =  4, image = 'hotdog.png' },
          { item = 'fries_pack',                  label = 'Portion of Fries',                price =  3, image = 'fries.png' },
          { item = 'icecream_strawberry',         label = 'Strawberry Ice Cream',            price =  3, image = 'strawberry_icecream.png' },
          { item = 'icecream_choco',              label = 'Chocolate Ice Cream',             price =  3, image = 'chocolate_icecream.png' },
          { item = 'icecream_plain',              label = 'Vanilla Ice Cream',               price =  3, image = 'vanilla_icecream.png' },
          { item = 'icecream_mint',               label = 'Mint Ice Cream',                  price =  3, image = 'mint_icecream.png' },
          { item = 'lemonade_juice',              label = 'Lemonade',                        price =  3, image = 'farming_lemonjuice.png' },
          { item = 'soda_karpuz',                 label = 'Watermelon Sparkling Water',      price =  2, image = 'watermelon-punch.png' },
      } },
    { label = "Rex's Diner", area = 'Harmony', category = 'Diner', bag = 'bag', pickup = vec4(2562.0, 2590.0, 38.1, 270.0),
      menu = {
          { item = 'burger_beef_double',          label = 'Double Beef Burger',              price =  9, image = 'burger.png' },
          { item = 'burger_cheese',               label = 'Cheeseburger',                    price =  7, image = 'cheeseburger.png' },
          { item = 'plate_omelette',              label = 'Omelette',                        price =  7, image = 'cc-omurice.png' },
          { item = 'plate_steak',                 label = 'Steak',                           price = 16, image = 'sirloinsteak.png' },
          { item = 'hotdog',                      label = 'Hotdog',                          price =  3, image = 'hotdog.png' },
          { item = 'fries_pack',                  label = 'Portion of Fries',                price =  3, image = 'fries.png' },
          { item = 'plate_cake_chocolate',        label = 'Chocolate Cake Slice',            price =  5, image = 'cake_chocolate.png' },
          { item = 'milkshake_vanilya',           label = 'Vanilla Milkshake',               price =  4, image = 'cb_milkshake.png' },
          { item = 'coffee_americano',            label = 'Americano',                       price =  3, image = 'bbs_americano.png' },
      } },
    { label = 'Mojito Inn', area = 'Paleto Bay', category = 'Bar food', bag = 'paper', pickup = vec4(-121.2, 6394.1, 31.5, 45.0),
      menu = {
          { item = 'chicken_wing_pack',           label = 'Chicken Wings',                   price =  8, image = 'wings.png' },
          { item = 'nplate',                      label = 'Nachos Plate',                    price =  8, image = 'nacho_plate.png' },
          { item = 'vusliders',                   label = 'Sliders',                         price =  8, image = 'burger.png' },
          { item = 'tots',                        label = 'Tits or Tots',                    price =  5, image = 'tots.png' },
          { item = 'plate_fish',                  label = 'Grilled Fish',                    price = 14, image = 'seafood_grilledfish.png' },
          { item = 'plate_shrimp',                label = 'Shrimp',                          price = 14, image = 'seafood_shrimpcocktail.png' },
          { item = 'lemonade_juice',              label = 'Lemonade',                        price =  3, image = 'farming_lemonjuice.png' },
      } },
    { label = 'Hen House', area = 'Paleto Bay', category = 'Chicken & grill', bag = 'bag', pickup = vec4(-300.9, 6256.2, 31.5, 45.0),
      menu = {
          { item = 'plate_chicken_legs',          label = 'Roast Chicken Legs',              price = 11, image = 'bbs_chicen_leg.png' },
          { item = 'chicken_wing_pack',           label = 'Chicken Wings',                   price =  8, image = 'wings.png' },
          { item = 'burger_chicken',              label = 'Chicken Burger',                  price =  7, image = 'chickenburger.png' },
          { item = 'plate_chicken_rice',          label = 'Chicken with Rice',               price = 10, image = 'bbs_japanese_curryrice.png' },
          { item = 'chicken_nugget_pack',         label = 'Chicken Nuggets',                 price =  5, image = 'nuggets.png' },
          { item = 'fries_pack',                  label = 'Portion of Fries',                price =  3, image = 'fries.png' },
          { item = 'ecola',                       label = 'Cola',                            price =  2, image = 'ecola.png' },
      } },
    { label = 'Liquor Ace', area = 'Sandy Shores', category = 'Convenience', bag = 'paper', pickup = vec4(1392.6, 3604.7, 34.9, 200.0),
      menu = {
          { item = 'water_bottle',                label = 'Water Bottle',                    price =  1, image = 'water_bottle.png' },
          { item = 'ecola',                       label = 'Cola',                            price =  2, image = 'ecola.png' },
          { item = 'sprunk',                      label = 'Sprite',                          price =  2, image = 'sprunk.png' },
          { item = 'crisps',                      label = 'Crisps',                          price =  2, image = 'chips.png' },
          { item = 'snikkel_candy',               label = 'Snikkel',                         price =  2, image = 'snikkel_candy.png' },
          { item = 'twerks_candy',                label = 'Twerks',                          price =  2, image = 'twerks_candy.png' },
          { item = 'sandwich',                    label = 'Sandwich',                        price =  5, image = 'sandwich.png' },
          { item = 'sandwich_chicken',            label = 'Chicken Sandwich',                price =  6, image = 'chickensandwich.png' },
          { item = 'hotdog',                      label = 'Hotdog',                          price =  3, image = 'hotdog.png' },
          { item = 'orange_juice',                label = 'Orange Juice',                    price =  3, image = 'farming_orangejuice.png' },
          { item = 'coffee',                      label = 'Coffee',                          price =  2, image = 'coffee.png' },
      } },
    { label = '24/7', area = 'Harmony', category = 'Convenience', bag = 'paper', pickup = vec4(547.8, 2671.8, 42.2, 10.0),
      menu = {
          { item = 'water_bottle',                label = 'Water Bottle',                    price =  1, image = 'water_bottle.png' },
          { item = 'ecola',                       label = 'Cola',                            price =  2, image = 'ecola.png' },
          { item = 'sprunk',                      label = 'Sprite',                          price =  2, image = 'sprunk.png' },
          { item = 'crisps',                      label = 'Crisps',                          price =  2, image = 'chips.png' },
          { item = 'snikkel_candy',               label = 'Snikkel',                         price =  2, image = 'snikkel_candy.png' },
          { item = 'twerks_candy',                label = 'Twerks',                          price =  2, image = 'twerks_candy.png' },
          { item = 'sandwich',                    label = 'Sandwich',                        price =  5, image = 'sandwich.png' },
          { item = 'sandwich_chicken',            label = 'Chicken Sandwich',                price =  6, image = 'chickensandwich.png' },
          { item = 'hotdog',                      label = 'Hotdog',                          price =  3, image = 'hotdog.png' },
          { item = 'orange_juice',                label = 'Orange Juice',                    price =  3, image = 'farming_orangejuice.png' },
          { item = 'coffee',                      label = 'Coffee',                          price =  2, image = 'coffee.png' },
      } },
    { label = '24/7', area = 'Senora Freeway', category = 'Convenience', bag = 'paper', pickup = vec4(2679.3, 3280.1, 55.2, 330.0),
      menu = {
          { item = 'water_bottle',                label = 'Water Bottle',                    price =  1, image = 'water_bottle.png' },
          { item = 'ecola',                       label = 'Cola',                            price =  2, image = 'ecola.png' },
          { item = 'sprunk',                      label = 'Sprite',                          price =  2, image = 'sprunk.png' },
          { item = 'crisps',                      label = 'Crisps',                          price =  2, image = 'chips.png' },
          { item = 'snikkel_candy',               label = 'Snikkel',                         price =  2, image = 'snikkel_candy.png' },
          { item = 'twerks_candy',                label = 'Twerks',                          price =  2, image = 'twerks_candy.png' },
          { item = 'sandwich',                    label = 'Sandwich',                        price =  5, image = 'sandwich.png' },
          { item = 'sandwich_chicken',            label = 'Chicken Sandwich',                price =  6, image = 'chickensandwich.png' },
          { item = 'hotdog',                      label = 'Hotdog',                          price =  3, image = 'hotdog.png' },
          { item = 'orange_juice',                label = 'Orange Juice',                    price =  3, image = 'farming_orangejuice.png' },
          { item = 'coffee',                      label = 'Coffee',                          price =  2, image = 'coffee.png' },
      } },
    { label = 'LTD Gasoline', area = 'Grapeseed', category = 'Convenience', bag = 'paper', pickup = vec4(1698.0, 4924.4, 42.1, 55.0),
      menu = {
          { item = 'water_bottle',                label = 'Water Bottle',                    price =  1, image = 'water_bottle.png' },
          { item = 'ecola',                       label = 'Cola',                            price =  2, image = 'ecola.png' },
          { item = 'sprunk',                      label = 'Sprite',                          price =  2, image = 'sprunk.png' },
          { item = 'crisps',                      label = 'Crisps',                          price =  2, image = 'chips.png' },
          { item = 'snikkel_candy',               label = 'Snikkel',                         price =  2, image = 'snikkel_candy.png' },
          { item = 'twerks_candy',                label = 'Twerks',                          price =  2, image = 'twerks_candy.png' },
          { item = 'sandwich',                    label = 'Sandwich',                        price =  5, image = 'sandwich.png' },
          { item = 'sandwich_chicken',            label = 'Chicken Sandwich',                price =  6, image = 'chickensandwich.png' },
          { item = 'hotdog',                      label = 'Hotdog',                          price =  3, image = 'hotdog.png' },
          { item = 'orange_juice',                label = 'Orange Juice',                    price =  3, image = 'farming_orangejuice.png' },
          { item = 'coffee',                      label = 'Coffee',                          price =  2, image = 'coffee.png' },
      } },
    { label = '24/7', area = 'Chumash', category = 'Convenience', bag = 'paper', pickup = vec4(-3241.5, 1001.1, 12.8, 265.0),
      menu = {
          { item = 'water_bottle',                label = 'Water Bottle',                    price =  1, image = 'water_bottle.png' },
          { item = 'ecola',                       label = 'Cola',                            price =  2, image = 'ecola.png' },
          { item = 'sprunk',                      label = 'Sprite',                          price =  2, image = 'sprunk.png' },
          { item = 'crisps',                      label = 'Crisps',                          price =  2, image = 'chips.png' },
          { item = 'snikkel_candy',               label = 'Snikkel',                         price =  2, image = 'snikkel_candy.png' },
          { item = 'twerks_candy',                label = 'Twerks',                          price =  2, image = 'twerks_candy.png' },
          { item = 'sandwich',                    label = 'Sandwich',                        price =  5, image = 'sandwich.png' },
          { item = 'sandwich_chicken',            label = 'Chicken Sandwich',                price =  6, image = 'chickensandwich.png' },
          { item = 'hotdog',                      label = 'Hotdog',                          price =  3, image = 'hotdog.png' },
          { item = 'orange_juice',                label = 'Orange Juice',                    price =  3, image = 'farming_orangejuice.png' },
          { item = 'coffee',                      label = 'Coffee',                          price =  2, image = 'coffee.png' },
      } },
    { label = '24/7', area = 'Banham Canyon', category = 'Convenience', bag = 'paper', pickup = vec4(-3038.7, 585.9, 7.9, 20.0),
      menu = {
          { item = 'water_bottle',                label = 'Water Bottle',                    price =  1, image = 'water_bottle.png' },
          { item = 'ecola',                       label = 'Cola',                            price =  2, image = 'ecola.png' },
          { item = 'sprunk',                      label = 'Sprite',                          price =  2, image = 'sprunk.png' },
          { item = 'crisps',                      label = 'Crisps',                          price =  2, image = 'chips.png' },
          { item = 'snikkel_candy',               label = 'Snikkel',                         price =  2, image = 'snikkel_candy.png' },
          { item = 'twerks_candy',                label = 'Twerks',                          price =  2, image = 'twerks_candy.png' },
          { item = 'sandwich',                    label = 'Sandwich',                        price =  5, image = 'sandwich.png' },
          { item = 'sandwich_chicken',            label = 'Chicken Sandwich',                price =  6, image = 'chickensandwich.png' },
          { item = 'hotdog',                      label = 'Hotdog',                          price =  3, image = 'hotdog.png' },
          { item = 'orange_juice',                label = 'Orange Juice',                    price =  3, image = 'farming_orangejuice.png' },
          { item = 'coffee',                      label = 'Coffee',                          price =  2, image = 'coffee.png' },
      } },
    { label = '24/7', area = 'Tataviam', category = 'Convenience', bag = 'paper', pickup = vec4(2557.9, 382.1, 108.6, 355.0),
      menu = {
          { item = 'water_bottle',                label = 'Water Bottle',                    price =  1, image = 'water_bottle.png' },
          { item = 'ecola',                       label = 'Cola',                            price =  2, image = 'ecola.png' },
          { item = 'sprunk',                      label = 'Sprite',                          price =  2, image = 'sprunk.png' },
          { item = 'crisps',                      label = 'Crisps',                          price =  2, image = 'chips.png' },
          { item = 'snikkel_candy',               label = 'Snikkel',                         price =  2, image = 'snikkel_candy.png' },
          { item = 'twerks_candy',                label = 'Twerks',                          price =  2, image = 'twerks_candy.png' },
          { item = 'sandwich',                    label = 'Sandwich',                        price =  5, image = 'sandwich.png' },
          { item = 'sandwich_chicken',            label = 'Chicken Sandwich',                price =  6, image = 'chickensandwich.png' },
          { item = 'hotdog',                      label = 'Hotdog',                          price =  3, image = 'hotdog.png' },
          { item = 'orange_juice',                label = 'Orange Juice',                    price =  3, image = 'farming_orangejuice.png' },
          { item = 'coffee',                      label = 'Coffee',                          price =  2, image = 'coffee.png' },
      } },
    { label = 'LTD Gasoline', area = 'Mirror Park', category = 'Convenience', bag = 'paper', pickup = vec4(1163.4, -323.8, 69.2, 100.0),
      menu = {
          { item = 'water_bottle',                label = 'Water Bottle',                    price =  1, image = 'water_bottle.png' },
          { item = 'ecola',                       label = 'Cola',                            price =  2, image = 'ecola.png' },
          { item = 'sprunk',                      label = 'Sprite',                          price =  2, image = 'sprunk.png' },
          { item = 'crisps',                      label = 'Crisps',                          price =  2, image = 'chips.png' },
          { item = 'snikkel_candy',               label = 'Snikkel',                         price =  2, image = 'snikkel_candy.png' },
          { item = 'twerks_candy',                label = 'Twerks',                          price =  2, image = 'twerks_candy.png' },
          { item = 'sandwich',                    label = 'Sandwich',                        price =  5, image = 'sandwich.png' },
          { item = 'sandwich_chicken',            label = 'Chicken Sandwich',                price =  6, image = 'chickensandwich.png' },
          { item = 'hotdog',                      label = 'Hotdog',                          price =  3, image = 'hotdog.png' },
          { item = 'orange_juice',                label = 'Orange Juice',                    price =  3, image = 'farming_orangejuice.png' },
          { item = 'coffee',                      label = 'Coffee',                          price =  2, image = 'coffee.png' },
      } },
    { label = 'LTD Gasoline', area = 'Little Seoul', category = 'Convenience', bag = 'paper', pickup = vec4(-707.5, -914.3, 19.2, 90.0),
      menu = {
          { item = 'water_bottle',                label = 'Water Bottle',                    price =  1, image = 'water_bottle.png' },
          { item = 'ecola',                       label = 'Cola',                            price =  2, image = 'ecola.png' },
          { item = 'sprunk',                      label = 'Sprite',                          price =  2, image = 'sprunk.png' },
          { item = 'crisps',                      label = 'Crisps',                          price =  2, image = 'chips.png' },
          { item = 'snikkel_candy',               label = 'Snikkel',                         price =  2, image = 'snikkel_candy.png' },
          { item = 'twerks_candy',                label = 'Twerks',                          price =  2, image = 'twerks_candy.png' },
          { item = 'sandwich',                    label = 'Sandwich',                        price =  5, image = 'sandwich.png' },
          { item = 'sandwich_chicken',            label = 'Chicken Sandwich',                price =  6, image = 'chickensandwich.png' },
          { item = 'hotdog',                      label = 'Hotdog',                          price =  3, image = 'hotdog.png' },
          { item = 'orange_juice',                label = 'Orange Juice',                    price =  3, image = 'farming_orangejuice.png' },
          { item = 'coffee',                      label = 'Coffee',                          price =  2, image = 'coffee.png' },
      } },
    { label = 'LTD Gasoline', area = 'Richman Glen', category = 'Convenience', bag = 'paper', pickup = vec4(-1820.5, 794.2, 138.1, 130.0),
      menu = {
          { item = 'water_bottle',                label = 'Water Bottle',                    price =  1, image = 'water_bottle.png' },
          { item = 'ecola',                       label = 'Cola',                            price =  2, image = 'ecola.png' },
          { item = 'sprunk',                      label = 'Sprite',                          price =  2, image = 'sprunk.png' },
          { item = 'crisps',                      label = 'Crisps',                          price =  2, image = 'chips.png' },
          { item = 'snikkel_candy',               label = 'Snikkel',                         price =  2, image = 'snikkel_candy.png' },
          { item = 'twerks_candy',                label = 'Twerks',                          price =  2, image = 'twerks_candy.png' },
          { item = 'sandwich',                    label = 'Sandwich',                        price =  5, image = 'sandwich.png' },
          { item = 'sandwich_chicken',            label = 'Chicken Sandwich',                price =  6, image = 'chickensandwich.png' },
          { item = 'hotdog',                      label = 'Hotdog',                          price =  3, image = 'hotdog.png' },
          { item = 'orange_juice',                label = 'Orange Juice',                    price =  3, image = 'farming_orangejuice.png' },
          { item = 'coffee',                      label = 'Coffee',                          price =  2, image = 'coffee.png' },
      } },
    -- Ready-made menus for your cafe / noodle MLOs. Stand at the pickup spot, /ddcoords, paste it in, remove `disabled`.
    { label = 'UwU Café', area = 'Little Seoul', category = 'Café & boba', bag = 'paper', pickup = vec4(-580.9, -1069.0, 22.3, 180.0), disabled = true,
      menu = {
          { item = 'kawaii_boba_matcha',           label = 'Matcha Cat Bubble Tea',           price =  5, image = 'bubbletea.png' },
          { item = 'kawaii_boba_taro',             label = 'Taro Bear Bubble Tea',            price =  5, image = 'bubbletea.png' },
          { item = 'kawaii_donut_bear',            label = 'Bear Donut',                      price =  3, image = 'donut.png' },
          { item = 'kawaii_bao_plain',             label = 'Smiling Bao Bun',                 price =  4, image = 'kittyricecake.png' },
          { item = 'kawaii_onigiri_panda',         label = 'Panda Rice Ball',                 price =  4, image = 'kittyricecake.png' },
          { item = 'kawaii_mochi_set',             label = 'Mochi Trio Plate',                price =  6, image = 'mochi.png' },
          { item = 'kawaii_pudding_bunny',         label = 'Bunny Pudding',                   price =  4, image = 'chocpudding.png' },
          { item = 'kawaii_smoothie_cat',          label = 'Cat Mango Smoothie',              price =  5, image = 'fruit_smoothie.png' },
          { item = 'kawaii_hotchoco_bear',         label = 'Bear Hot Chocolate',              price =  4, image = 'bean_hotchocolate.png' },
          { item = 'nekolatte',                    label = 'Neko Latte',                      price =  4, image = 'latte.png' },
      } },
    { label = 'Noodle Exchange', area = 'Little Seoul', category = 'Ramen & sushi', bag = 'paper', pickup = vec4(-655.0, -883.0, 24.7, 0.0), disabled = true,
      menu = {
          { item = 'bowl_ramen_tonkotsu',          label = 'Tonkotsu Ramen',                  price = 11, image = 'ramen.png' },
          { item = 'bowl_ramen_miso',              label = 'Miso Ramen',                      price = 10, image = 'ramen.png' },
          { item = 'bowl_ramen_spicy',             label = 'Spicy Ramen',                     price = 11, image = 'ramen.png' },
          { item = 'shrimp_ramen',                 label = 'Shrimp Ramen',                    price = 12, image = 'bbs_shrimp_ramen.png' },
          { item = 'plate_sushi_california',       label = 'California Roll Plate',           price = 12, image = 'sushi1.png' },
          { item = 'plate_sushi_nigiri_salmon',    label = 'Salmon Nigiri Plate',             price = 13, image = 'sushi1.png' },
          { item = 'plate_sushi_maki_avocado',     label = 'Avocado Maki Plate',              price = 10, image = 'sushi1.png' },
          { item = 'bento',                        label = 'Bento Box',                       price = 12, image = 'bento.png' },
          { item = 'miso',                         label = 'Miso Soup',                       price =  4, image = 'miso.png' },
          { item = 'tea_yesil',                    label = 'Green Tea',                       price =  2, image = 'tea_green.png' },
      } },
}

---------------------------------------------------------------------
-- Customer doors. Heading = the direction the customer faces standing
-- in the doorway looking out at the street. Verify with /ddcoords.
---------------------------------------------------------------------
Config.Dropoffs = {
    { label = 'Forum Drive',          area = 'Chamberlain Hills', door = vec4(-14.1, -1441.3, 31.1, 180.0) },
    { label = 'Forum Drive',          area = 'Chamberlain Hills', door = vec4(-64.5, -1449.5, 32.5, 275.0) },
    { label = 'Grove Street',         area = 'Davis',          door = vec4(126.8, -1929.9, 21.4, 210.0) },
    { label = 'Grove Street',         area = 'Davis',          door = vec4(114.4, -1961.0, 21.3, 25.0) },
    { label = 'Grove Street',         area = 'Davis',          door = vec4(85.9, -1959.1, 21.1, 320.0) },
    { label = 'Amarillo Vista',       area = 'El Burro Heights', door = vec4(1273.9, -1719.6, 54.8, 30.0) },
    { label = 'Mirror Park Blvd',     area = 'Mirror Park',    door = vec4(1060.5, -378.2, 68.2, 40.0) },
    { label = 'Nikola Place',         area = 'Mirror Park',    door = vec4(1100.9, -411.3, 67.6, 80.0) },
    { label = 'Whispymound Drive',    area = 'Vinewood Hills', door = vec4(7.9, 538.3, 176.0, 150.0) },
    { label = 'Portola Drive',        area = 'Rockford Hills', door = vec4(-816.3, 178.1, 72.2, 110.0) },
    { label = 'Vespucci Beach',       area = 'Vespucci',       door = vec4(-1150.2, -1521.2, 10.6, 35.0) },
    { label = 'Canal houses',         area = 'Vespucci Canals', door = vec4(-1114.4, -1069.2, 2.15, 210.0) },
    { label = 'Del Perro Heights',    area = 'Del Perro',      door = vec4(-1447.2, -537.8, 34.7, 215.0) },
    { label = 'Eclipse Towers',       area = 'West Vinewood',  door = vec4(-773.9, 312.2, 85.7, 180.0) },
    { label = 'Integrity Way',        area = 'Pillbox Hill',   door = vec4(-47.3, -585.9, 37.95, 70.0) },
    { label = 'Richards Majestic',    area = 'Richards Majestic', door = vec4(-935.2, -378.5, 38.9, 115.0) },
    { label = 'Zancudo Ave trailer',  area = 'Sandy Shores',   door = vec4(1973.6, 3815.4, 33.4, 300.0) },
    { label = 'Marina Drive',         area = 'Sandy Shores',   door = vec4(1899.0, 3781.3, 32.9, 300.0) },
    { label = 'Procopio Drive',       area = 'Paleto Bay',     door = vec4(-360.1, 6260.5, 31.9, 45.0) },
    -- More customers across the map (approximate doorsteps, check with /ddcoords)
    { label = 'Wild Oats Drive',      area = 'Vinewood Hills', door = vec4(-174.3, 502.6, 137.4, 190.0) },
    { label = 'Mirror Park Blvd',     area = 'Mirror Park',    door = vec4(1204.7, -557.7, 69.6, 90.0) },
    { label = 'Nikola Avenue',        area = 'Mirror Park',    door = vec4(1302.8, -528.4, 71.5, 160.0) },
    { label = 'Great Ocean Hwy',      area = 'Chumash',        door = vec4(-3093.6, 349.6, 7.5, 250.0) },
    { label = 'Banham Canyon Dr',     area = 'Banham Canyon',  door = vec4(-3017.2, 746.9, 27.6, 110.0) },
    { label = 'Route 68 Motel',       area = 'Harmony',        door = vec4(1142.6, 2663.8, 38.2, 90.0) },
    { label = 'Alhambra Drive',       area = 'Sandy Shores',   door = vec4(1842.9, 3778.3, 33.2, 210.0) },
    { label = 'Niland Avenue',        area = 'Sandy Shores',   door = vec4(1435.4, 3657.1, 34.4, 200.0) },
    { label = 'Armadillo Avenue',     area = 'Sandy Shores',   door = vec4(1777.4, 3790.5, 34.3, 30.0) },
    { label = 'Grapeseed Main St',    area = 'Grapeseed',      door = vec4(1662.9, 4776.4, 42.0, 280.0) },
    { label = 'Grapeseed Ave',        area = 'Grapeseed',      door = vec4(1683.9, 4689.2, 43.1, 90.0) },
    { label = 'Paleto Blvd',          area = 'Paleto Bay',     door = vec4(-374.6, 6190.9, 31.7, 225.0) },
    { label = 'Procopio Promenade',   area = 'Paleto Bay',     door = vec4(-437.6, 6272.0, 30.1, 70.0) },
    { label = 'Pyrite Avenue',        area = 'Paleto Bay',     door = vec4(-105.7, 6528.8, 30.2, 315.0) },
    { label = 'Duluoz Avenue',        area = 'Paleto Bay',     door = vec4(-15.1, 6557.8, 33.2, 315.0) },
    { label = 'Paleto Coast',         area = 'Paleto Bay',     door = vec4(35.3, 6663.4, 32.2, 170.0) },
}
