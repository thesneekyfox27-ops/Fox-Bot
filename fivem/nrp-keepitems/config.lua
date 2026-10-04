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
--  WHAT YOU KEEP WHEN YOU DIE + RESPAWN
--  Everything LEGAL is kept: ID, phone, keys, cash, food, drinks,
--  tools, clothes, car parts, medical supplies, job gear...
--  Everything on the LOSE list below (drugs, dirty money, guns,
--  ammo, explosives, heist/crime tools, stolen loot) is lost.
--  Names = keys in your tgiann items.lua.
-- ============================================================

-- Lost if the name MATCHES one of these (so new drugs/guns you add later
-- are covered automatically). Lua patterns: ^ = starts with, $ = ends with.
Config.LosePatterns = {
    '^weapon_',      -- all guns / melee / throwables
    '_ammo$',        -- every ammo type (incl. police ammo)
    '^ammobox_',
    '^weed_',        -- weed strains, seeds, bags, bricks
    'meth',          -- every meth item
    'coke', 'cocaine', 'crack',
    '_baggy$',       -- every drug baggy
    '^heist',        -- heist packs / heist paints
    '^painting',     -- stolen art
    'lockpick',      -- all lockpicks
    '^security_c',   -- heist security cards / chips
    '^creditcard_lvl_', -- stolen "lost credit cards"
    '^stolen_',      -- stolen bag / TV / toolbox
}

-- Lost (exact names)
Config.LoseItems = {
    -- drugs & drug making
    adderall = true, oxy = true, percocet = true, xanax_bar = true, codeine_bottle = true, lean_cup = true,
    ecstasy_pill = true, molly_capsule = true, xtcbaggy = true, lsd_tab = true, blotter_sheet = true,
    pcp_vial = true, shrooms_dried = true, joint = true, rolled_weed = true, packed_weed = true,
    unpacked_weed = true, empty_weed_bag = true, bong = true, cutting_agent = true, empty_capsule = true,
    pill_press = true, coca_leaf = true, mega_death = true, humaneco2 = true, plant_spray = true,
    moonshine = true, moonshine_pack = true, moonshine_still = true, baggy_small = true,

    -- dirty money
    black_money = true, markedbills = true, bandsofnotes = true, stacksofcash = true,
    cutted_money = true, uncutted_money = true, money_sheet = true, moneybag = true,

    -- explosives & armed-crime gear
    bomb = true, c4 = true, thermite = true, empty_ammobox = true,
    zipties = true, head_bag = true, headbag = true, t_handcuffs = true, t_handcuffs_key = true,

    -- heist / hacking / break-in tools
    access_card = true, card = true, door_card = true, labkey = true, group6card = true,
    bankcard = true, paletobankcard = true, bigbankcard = true, gruppesechstablet = true,
    atm_hack_device = true, rd_hacking_device = true, rd_breacher = true, illegal_tablet = true,
    robban_tablet = true, trojan_usb = true, purpleusb = true, humaneusb = true, cryptostick = true,
    pincracker = true, gatecrack = true, glass_cutter = true, drill = true, unlock_tool = true,
    signal_jammer = true, code_list = true, blank_card = true, fake_credit_card = true,
    trapphone = true, unmarkedsimcard = true, rt90x_radio_bm = true, illegalbait = true,
    catalytic_converter = true, harddrive = true,

    -- stolen jewellery, valuables & house-robbery loot (fenced, not owned)
    diamond = true, rare_diamond = true, diamond_ring = true, diamondring = true, diamond_watch = true,
    diamondnecklace = true, emerald_bracelet = true, ruby_necklace = true, rubynecklace = true,
    sapphire_earrings = true, cheap_ring = true, luxury_watch = true, rolex = true,
    gold = true, gold_bar = true, goldbar = true, goldbarstack = true, gold_scrap = true,
    gold_chain = true, goldchain = true, tenkgoldchain = true, gold_necklace = true, gold_ring = true,
    gold_bracelet = true, goldbracelet = true, gold_watch = true, goldwatch = true,
    platinum_bar = true, silver_bar = true, silverbar = true, silver_chain = true, silver_ring = true,
    silverring = true, silver_scrap = true, silverware = true,
    sculpture_small = true, obelisk_figurine = true, flamenco_figurine = true, decorative_head = true,
    fur_coat = true, designer_handbag = true, designer_sneakers = true, designer_sunglasses = true,
    flat_tv = true, old_tv = true, television = true, computer_monitor = true, game_console = true,
    gaming_laptop = true, gaming_keyboard = true, graphics_card = true, vr_headset = true,
    bluetooth_speaker = true, wireless_headphones = true, desk_lamp = true, standing_fan = true,
    microwave = true, toaster = true, air_fryer = true, coffee_machine = true, electric_kettle = true,
    kettle = true, ironing_board = true, rgb_controller = true, inverter = true,
}

-- Always kept even if a pattern above matches.
Config.KeepAnyway = {
    weapon_petrolcan = true,   -- just a jerry can
}

-- true = keep EVERYTHING on death (ignores the lose list).
Config.KeepEverything = false

-- Inventory resource used to give items back (tgiann-inventory is used through
-- its AddItem export; anything else uses the QBCore player functions).
Config.InventoryResource = 'tgiann-inventory'

-- Optional Discord webhook for a log line every time a wipe is blocked.
-- Leave '' to only print in the server console.
Config.Webhook = ''
