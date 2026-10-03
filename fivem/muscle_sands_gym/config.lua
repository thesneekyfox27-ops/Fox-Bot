Config = {}
-- 'auto'      -> use a QB-style core if one is running, otherwise standalone
-- 'qbcore'    -> force core mode (gym_pass item + metadata, synced server-side)
-- 'standalone'-> force standalone (saves locally per-client via KVP, no item)
Config.Framework = 'auto'

-- Resource names. 'auto' core-detect covers qb-core, qbx_core and tgiann-core.
-- Set these explicitly if your resources are named differently.
Config.CoreResource      = 'auto'              -- or 'tgiann-core' / 'qb-core' / 'qbx_core'
Config.InventoryResource = 'tgiann-inventory'  -- used for HasItem / RemoveItem exports
Config.TargetResource    = 'qb-target'         -- e.g. 'ox_target' if that's what you run

-- qb-target for the vendor NPC: 'auto' uses it if the target resource is running.
-- When off (or standalone), you buy from a press-E marker on the NPC instead.
Config.UseTarget = 'auto'

Config.MaxStat          = 100     -- max value for strength / stamina (GTA caps at 100)
Config.GainPerSession   = 1       -- points gained per completed workout (1 = slow grind to max)
Config.WorkoutDuration  = 15000   -- ms a workout takes (longer = more effort per point)
Config.WorkoutCooldown  = 5       -- seconds you must rest between workouts (0 = none)
Config.DrawDistance     = 20.0    -- distance (m) at which markers appear
Config.InteractDistance = 1.6     -- distance (m) at which you can press E
Config.ShowMarkers      = true
Config.MarkerColor      = { r = 0, g = 180, b = 255, a = 120 }
-- Keys (FiveM control IDs)
Config.InteractKey = 38  -- E
Config.CancelKey   = 73  -- X

-- ============================ NOTIFICATIONS ============================
-- Lightweight on-screen text notifications (no dependency).
Config.Notify = {
    x        = 0.90,    -- screen X (0 left .. 1 right)
    y        = 0.85,   -- screen Y (0 top .. 1 bottom)
    scale    = 0.42,
    duration = 4000,   -- ms each message stays up
}

-- ============================ EFFECTS ============================
-- Stamina drives how long you can sprint AND how fast you run.
-- Low stamina = you gas out quickly; train it up to last longer and move faster.
Config.Effects = {
    enabled = true,
    -- TIREDNESS: fraction of your stored stamina the game actually uses for sprint
    -- endurance. 1.0 = vanilla. Lower = tire faster across the board. 0.6 means
    -- even maxed stamina tires sooner than a vanilla maxed character; an untrained
    -- player gasses out very quickly.
    staminaGameRatio = 0.6,
    -- RUN SPEED boost from stamina. 1.0 is normal; ~1.49 is the game's effective max.
    speedBase = 1.00,   -- at 0 stamina   -> normal speed
    speedMax  = 1.49,   -- at 100 stamina -> noticeable speed boost
    -- SWIM SPEED boost from stamina (same scale/caps).
    swimBase  = 1.00,
    swimMax   = 1.49,
}

-- ============================ DECAY ============================
-- Skip the gym for a while and your stats slowly drop.
Config.Decay = {
    enabled    = true,
    graceHours = 48,   -- no decay until this many (real) hours since your last workout
    lossPerDay = 2,    -- points lost per full day idle after the grace period (both stats)
}

-- ============================ ENERGY / EXHAUSTION ============================
-- Stops players grinding the gym all day. Every workout burns energy; run out
-- and you're "too exhausted to work out" until you've rested. Energy regens over
-- REAL time (so relogging won't refill it). While exhausted, your sprint stamina
-- is cut, so you also tire much faster until you recover.
Config.Energy = {
    enabled        = true,
    max            = 100,
    costPerWorkout = 25,    -- energy per workout (max / cost = sessions before exhausted)
    regenPerMin    = 8,     -- energy recovered per REAL minute of rest
    exhaustedStaminaMult = 0.3,  -- sprint stamina multiplier while exhausted (lower = tire faster)
}

-- ============================ STATS BOARD ============================
-- A board near the gym showing your current Strength/Stamina and the boosts they
-- give. Decay is silent - players check their numbers here instead of a popup.
-- Move it anywhere by changing coords (use /gymcoords in-game to grab a spot).
Config.StatsBoard = {
    enabled      = true,
    coords       = vector3(-1201.54, -1569.25, 4.61),
    heading      = 120.0,
    drawDistance = 10.0,
    prop         = true,   -- false = floating text only. Set a model name to spawn a
                            -- physical board, e.g. 'prop_noticeboard_01' or 'prop_inscroll_01a'.
    groundSnap   = true,   -- false = place the prop at the exact Z above (recommended on the
                            -- boardwalk). true = drop it to the ground (sinks into deck sand).
}

-- ============================ APPEARANCE ============================
-- GTA has no native muscle slider for the freemode player ped, so a real body
-- morph requires your clothing/appearance resource. When enabled, the hook in
-- client.lua (applyAppearance) runs as Strength changes - drop your resource's
-- export in there. Left disabled (no-op) by default so nothing breaks.
Config.Appearance = {
    enabled = false,
}

-- ============================ GYM PASS ============================
-- Buy a pass from the NPC. It lasts for the rest of the in-game day it was
-- bought on, then auto-removes when that day ends. Machine markers only appear
-- while a valid pass is held.
Config.GymPass = {
    price       = 50,        -- cost (QBCore only; standalone has no economy so it's free)
    account     = 'cash',      -- 'cash' or 'bank' (QBCore)
    -- QBCore membership item (matches the dynyx gym_pass item + image).
    item        = 'gym_pass',
    durationIgHours = 24,      -- pass lasts this many IN-GAME hours from purchase, then auto-removes
    requireItem = true,        -- QBCore: must actually hold the item to train (drop it = no access)
    hasItemExport = true,     -- set true to use exports['tgiann-inventory']:HasItem instead of qb-core's
    -- Vendor NPC you buy the pass from (Vespucci boardwalk).
    spawnPed    = true,
    pedModel    = 'a_m_m_beach_01',
    pedCoords   = vector4(-1208.44, -1569.55, 4.61, 107.05),  -- set Z to the DECK surface
    groundSnap  = false,       -- false = use the exact Z above (the gym is on a raised
                               -- boardwalk; snapping finds the sand UNDER it and sinks the
                               -- ped). Stand where you want him, /gymcoords, paste the Z.
    -- The "muscle" blip (dumbbell icon) at the gym.
    showBlip   = true,
    blipSprite = 311,          -- dumbbell icon
    blipColor  = 7,
    blipScale  = 0.65,
    blipName   = 'Muscle Sands Gym',
}

-- Each station: label, stat it trains ('strength' or 'stamina'), and the animation
-- (EITHER scenario = '...'  OR  animDict + animName).
--
-- MULTIPLE SPOTS FOR THE SAME EXERCISE:
--   Add coords2, coords3, coords4, ... (any number). Each becomes its own usable
--   point sharing the same label/stat/animation.
--   Optional per-spot facing: headings = { [1] = 35.0, [2] = 215.0, ... }
--   (otherwise every spot uses the station's single `heading`).
--
-- TIP: run /gymcoords in-game to print your exact position + heading, then paste.
Config.Stations = {
    {
        label    = 'Free Weights',
        coords   = vector3(-1209.36, -1559.27, 4.61),
        coords2  = vector3(-1202.51, -1572.86, 4.61),
        coords3  = vector3(-1198.61, -1565.92, 4.62),
        heading  = 35.0,
        stat     = 'strength',
        scenario = 'WORLD_HUMAN_MUSCLE_FREE_WEIGHTS',
    },
    {
        label    = 'Pull-Up Bar',
        coords   = vector3(-1204.98, -1564.03, 4.61),
        coords2  = vector3(-1199.93, -1571.07, 4.61),
        heading  = 215.0,
        stat     = 'strength',
        scenario = 'PROP_HUMAN_MUSCLE_CHIN_UPS',
    },
    {
        label    = 'Push-Ups',
        coords   = vector3(-1200.02, -1564.03, 4.61),
        coords2  = vector3(-1199.89, -1576.76, 4.61),
        heading  = 215.0,
        stat     = 'strength',
        animDict = 'amb@world_human_push_ups@male@base',
        animName = 'base',
    },
    {
        label    = 'Sit-Ups',
        coords   = vector3(-1197.96, -1571.08, 4.61),
        heading  = 215.0,
        stat     = 'stamina',
        animDict = 'amb@world_human_sit_ups@male@base',
        animName = 'base',
    },
    {
        label    = 'Stretching',
        coords   = vector3(-1204.63, -1560.88, 4.61),
        heading  = 35.0,
        stat     = 'stamina',
        scenario = 'WORLD_HUMAN_YOGA',
    },

    {
        label    = 'Jumping Jacks',
        coords   = vector3(-1207.58, -1566.09, 4.61),
        heading  = 215.0,
        stat     = 'stamina',
        -- NOTE: GTA has no real jumping-jacks anim. animDict is the '@' path, animName
        -- is the short clip name. Swap these for any valid pair you like.
        animDict = 'timetable@reunited@ig_2',
        animName = 'jimmy_getknocked',
    },
}
