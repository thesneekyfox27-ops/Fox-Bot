-- ============================================================
--  muscle_sands_gym  ->  gym_pass membership item
-- ============================================================
-- QB-CORE: paste this inside qb-core/shared/items.lua (in the items table).
-- TGIANN-INVENTORY: paste this inside tgiann-inventory/items/items.lua instead.
--
-- Then copy  images/gym_pass.png  into your inventory's image folder:
--   qb-inventory:      qb-inventory/html/images/gym_pass.png
--   ox_inventory:      ox_inventory/web/images/gym_pass.png
--   tgiann-inventory:  tgiann-inventory/html/images/gym_pass.png  (or web/images on some builds)
--
-- The pass auto-expires at the end of the in-game day it was bought on; the
-- script removes the item for you, so it does NOT need to be "useable".
-- ============================================================

['gym_pass'] = {
    ['name']        = 'gym_pass',
    ['label']       = 'Gym Membership',
    ['weight']      = 0,
    ['type']        = 'item',
    ['image']       = 'gym_pass.png',
    ['unique']      = true,
    ['useable']     = false,
    ['shouldClose'] = false,
    ['description'] = 'Muscle Sands day pass - expires 24 in-game hours after purchase',
},
