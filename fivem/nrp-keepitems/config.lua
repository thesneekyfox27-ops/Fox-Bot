Config = {}

Config.Enabled = true
Config.Debug   = false

-- How often (ms) a dead/downed player's inventory is checked.
Config.PollMs = 500

-- A "wipe" = this share of your item stacks disappearing in ONE check
-- (half a second). Clear-on-death scripts remove everything at once;
-- a player robbing you takes items one at a time, so that is never
-- treated as a wipe (and is never given back - no duping).
Config.WipeRatio = 0.6   -- 60% of your stacks...
Config.MinStacks = 2     -- ...and at least this many stacks at once

-- Keep watching for this many seconds after you're revived/respawned
-- (hospital respawn scripts usually wipe right at respawn).
Config.WatchAfterReviveSec = 90

-- ============================================================
--  KEEP LIST: the items you DON'T lose when you die + respawn.
--  Everything else is still removed by your respawn/hospital script
--  as normal. Only these come back. Names = keys in tgiann items.lua.
-- ============================================================
Config.KeepItems = {
    -- ID & licenses
    id_card         = true,
    driver_license  = true,
    weaponlicense   = true,
    lawyerpass      = true,
    certificate     = true,
    vending_permit  = true,

    -- phones & radios
    phone           = true,
    iphone          = true,
    smartphone      = true,
    samsungphone    = true,
    sim             = true,
    radio           = true,
    rt90x_radio     = true,
    pd_radio        = true,
    ems_radio       = true,

    -- keys
    car_key         = true,
    vehiclekeys     = true,
    housekey        = true,
    door_key        = true,

    -- wallet / bank
    wallet          = true,
    bank_card       = true,

    -- server items
    gym_pass            = true,
    rental_papers       = true,
    minigolf_scorecard  = true,
}

-- true = ignore the list above and keep EVERYTHING on death.
Config.KeepEverything = false

-- Inventory resource used to give items back (tgiann-inventory is used through
-- its AddItem export; anything else uses the QBCore player functions).
Config.InventoryResource = 'tgiann-inventory'

-- Optional Discord webhook for a log line every time a wipe is blocked.
-- Leave '' to only print in the server console.
Config.Webhook = ''
