Config = {}

-- ===================== GENERAL =====================
Config.Framework = 'auto'      -- 'auto' | 'esx' | 'qb' | 'standalone'
Config.Target = 'none'         -- 'none' (styled E prompt) | 'auto' | 'ox' | 'qb'
Config.Currency = '$'
Config.InteractKey = 38        -- E (only used if no target system)
Config.InteractDistance = 2.2
Config.Blip = {
    enabled = true,
    sprite = 326,
    color = 5,
    scale = 0.75,
    label = 'Car Rentals'
}

-- Command + keybind to pull up your rental papers (contract + temp reg) while driving.
Config.PapersCommand = 'papers'
Config.PapersKey = ''          -- default keybind, e.g. 'K'. Leave '' to let players bind it themselves.

-- ===================== LOCATIONS =====================
-- Add as many as you want. Each has a ped spot + its own parking spaces.
-- PUT YOUR OWN COORDS HERE. Return works at any location.
Config.Locations = {
    { -- LOCATION 1 (your spot)
        ped = vector4(-1330.48, -811.87, 17.20, 97.83),
        spawnPoints = {
            vector4(-1326.32, -801.09, 17.77, 128.03),
        },
    },
    { -- LOCATION 2 (your spot)
        ped = vector4(-442.86, -992.92, 23.47, 186.37),
        spawnPoints = {
            vector4(-443.70, -1003.33, 23.41, 73.69),
        },
    },

    -- ===== NOTABLE EXTRA SPOTS (uncomment any to enable) =====

     { -- LSIA Airport
         ped = vector4(-1037.91, -2737.32, 20.17, 327.0),
         spawnPoints = { vector4(-1031.83, -2731.45, 20.07, 240.0) },
     },
     { -- Route 68 / Sandy Shores gas
         ped = vector4(1712.0, 6424.13, 32.71, 238.03),
         spawnPoints = { vector4(1716.30, 6417.44, 33.27, 150.54) },
     },
     { -- Vinewood Blvd
         ped = vector4(292.20, -1105.17, 29.41, 260.97),
         spawnPoints = { vector4(307.08, -1102.51, 29.36, 357.70) },
     },
}

Config.PedModel = 'a_m_y_business_01'
Config.PedScenario = 'WORLD_HUMAN_CLIPBOARD'
Config.ReturnRadius = 30.0

-- ===================== ECONOMY =====================
-- You pay: price + deposit. Return undamaged: get DepositRefundPct of deposit back.
Config.DepositRefundPct = 0.75
Config.DamagePenalty = true
Config.MaxActiveRentals = 1

-- ===================== CONTRACT =====================
-- A signed rental agreement the renter reviews before paying.
Config.Contract = {
    enabled = true,
    requireAgree = true,        -- must tick "I agree" to rent
    requireSignature = true,    -- must type a signature to rent
    company = 'Clipboard Rentals LLC',
    -- {label} tokens are filled in live from the rental. Edit freely.
    terms = {
        'The renter is fully liable for all damage to the vehicle for the duration of the rental.',
        'The refundable deposit is returned in full only if the vehicle is returned undamaged to a rental lot.',
        'Damage is deducted from the deposit. Severe damage may void the refund entirely.',
        'This vehicle remains the property of {company} and may be recovered at any time.',
        'The temporary operating permit is valid for {duration} minutes from the time of issue.',
        'Sub-letting, racing, and use in the commission of a crime are strictly prohibited.',
    },
}

-- ===================== TEMPORARY REGISTRATION =====================
-- A DMV-style temporary operating permit issued with every rental.
Config.TempRegistration = {
    enabled = true,
    minutes = 60,               -- how long the permit is valid
    notifyOnExpire = true,      -- ping the renter once when it lapses
    authority = 'Los Santos DMV',
}

-- ===================== REGISTRATION PAPERS ITEM =====================
-- On rent, the renter also receives a physical "registration papers" inventory item.
-- Using the item opens the same contract + permit viewer. The signing flow is unchanged.
-- NOTE: you must register the item in your inventory first (see README for the snippet).
Config.PaperItem = {
    enabled = true,
    inventory = 'auto',        -- 'auto' | 'ox' | 'qb'
    name = 'rental_papers',    -- item name as registered in your inventory
    removeOnReturn = true,     -- take the papers back when the vehicle is returned
}

-- ===================== VEHICLE KEYS =====================
-- Keys are handed out CLIENT-SIDE the moment the car spawns (most reliable).
-- 'auto' detects a running keys resource. Or force one explicitly:
--   'qb'      -> classic QBCore event (vehiclekeys:client:SetOwner) — works with
--                qb-vehiclekeys and most forks. If you're on QBCore, try this first.
--   'qbx'     -> qbx_vehiclekeys
--   'wasabi'  -> wasabi_carlock
--   'mrnewb'  -> MrNewbVehicleKeys
--   'qs'      -> qs-vehiclekeys
--   'renewed' -> Renewed-Vehiclekeys
--   '0r'      -> 0r-vehiclekeys
--   'custom'  -> edit GiveVehicleKeys()/RemoveVehicleKeys() in client.lua
Config.VehicleKeys = {
    enabled = true,
    system = 'auto',
    debug = true,   -- prints the chosen system + any errors to F8 / server console
}

-- ===================== FLEET =====================
-- Add `image = 'https://...'` to any entry to override the auto vehicle photo.
Config.Vehicles = {
    { model = 'panto',     label = 'Panto',    category = 'Economy', price = 50,  deposit = 50,  desc = 'Technically a car.' },
    { model = 'blista',    label = 'Blista',   category = 'Economy', price = 75,  deposit = 75,  desc = 'Cheap, cheerful, gets you there.' },
    { model = 'asea',      label = 'Asea',     category = 'Economy', price = 90,  deposit = 90,  desc = 'A sensible sedan for sensible people.' },
    { model = 'minivan',   label = 'Minivan',  category = 'Family',  price = 110, deposit = 110, desc = 'Room for the whole crew.' },
    { model = 'gresley',   label = 'Gresley',  category = 'Family',  price = 160, deposit = 160, desc = 'A proper SUV with proper presence.' },
    { model = 'fugitive',  label = 'Fugitive', category = 'Comfort', price = 180, deposit = 180, desc = 'Smooth ride, tinted dignity.' },
    { model = 'oracle2',   label = 'Oracle',   category = 'Comfort', price = 220, deposit = 220, desc = 'Executive comfort by the hour.' },
    { model = 'faggio',    label = 'Faggio',   category = 'Bikes',   price = 30,  deposit = 30,  desc = 'Maximum style. Minimum speed.' },
    { model = 'sanchez',   label = 'Sanchez',  category = 'Bikes',   price = 80,  deposit = 80,  desc = 'Dirt-ready two wheels.' },
    { model = 'felon',     label = 'Felon',    category = 'Premium', price = 380, deposit = 380, desc = 'A coupe that means business.' },
    { model = 'comet2',    label = 'Comet',    category = 'Premium', price = 450, deposit = 450, desc = 'For when the deposit is no object.' },
}
