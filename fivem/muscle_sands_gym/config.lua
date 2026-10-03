Config = {}

-- ============================================================
--  MUSCLE SANDS GYM  (Vespucci Beach)  -  QBCore
--  Stats, energy, passes and gains all live on the SERVER
--  (player metadata), so nobody can give themselves 100 strength.
-- ============================================================

Config.Debug = false

-- 'auto' picks ox_target, then qb-target. 'off' = walk up and press E.
Config.Target = 'auto'

-- Inventory used for the gym_pass item ('tgiann-inventory' works through its exports,
-- anything else uses the QBCore player functions).
Config.InventoryResource = 'tgiann-inventory'

Config.InteractKey      = 38      -- E
Config.DrawDistance     = 20.0    -- markers show within this range (with a pass)
Config.InteractDistance = 1.6
Config.Marker = { type = 1, size = vector3(0.7, 0.7, 0.35), color = { r = 242, g = 178, b = 61, a = 120 } }

-- ============================================================
--  STATS & GAINS
-- ============================================================
Config.MaxStat = 100

Config.Workout = {
    reps        = 8,      -- reps per set (each rep is one press of the timing bar)
    repTime     = 1500,   -- ms the marker takes to cross the bar
    zoneSize    = 0.22,   -- width of the green "good" zone (0-1 of the bar)
    perfectSize = 0.07,   -- width of the gold "perfect" centre
    pushKey     = 22,     -- SPACE: push the rep
    cancelKey   = 73,     -- X: stop the set
    cooldown    = 5,      -- seconds of rest between sets
}

Config.Gain = {
    perfectSet = 1.0,     -- points for a flawless set at 0 stat
    minScore   = 0.25,    -- sets worse than this give nothing
    -- gains shrink as you get stronger: at the max stat you gain (1 - falloff) of normal
    falloff    = 0.6,
}

-- ============================================================
--  EFFECTS (what the stats actually do)
-- ============================================================
Config.Effects = {
    enabled          = true,
    staminaGameRatio = 0.6,    -- share of stamina the game uses for sprint endurance (lower = tire faster)
    speedBase = 1.00, speedMax = 1.25,   -- run speed at 0 / 100 stamina (game cap is 1.49)
    swimBase  = 1.00, swimMax  = 1.25,
    meleeBase = 1.00, meleeMax = 1.30,   -- melee damage at 0 / 100 strength
}

-- Skip the gym and you slowly lose it (real time).
Config.Decay = {
    enabled    = true,
    graceHours = 48,   -- no loss for this long after your last workout
    lossPerDay = 2,    -- points lost per idle day after that (both stats)
}

-- Every set burns energy; it comes back over real time.
Config.Energy = {
    enabled        = true,
    max            = 100,
    costPerWorkout = 20,
    regenPerMin    = 6,
    exhaustedStaminaMult = 0.3,   -- sprint stamina while exhausted
}

-- ============================================================
--  MEMBERSHIPS
-- ============================================================
-- Real-time durations. Buying while active ADDS the time on top.
Config.Pass = {
    item         = 'gym_pass',
    requireItem  = true,        -- must actually carry the card to train
    account      = 'cash',      -- charged from here first...
    bankFallback = true,        -- ...then the bank if cash is short
    tiers = {
        { id = 'day',   label = 'Day Pass',       price = 50,   minutes = 120,          perks = 'Full gym access for 2 hours' },
        { id = 'week',  label = 'Weekly Member',  price = 300,  minutes = 60 * 24 * 7,  perks = '7 days of access - best for regulars' },
        { id = 'month', label = 'Monthly VIP',    price = 1000, minutes = 60 * 24 * 30, perks = '30 days of access - VIP card' },
    },
}

-- ============================================================
--  TRAINER (sells passes, shows your stats + leaderboard)
-- ============================================================
Config.Trainer = {
    model    = 'a_m_m_beach_01',
    coords   = vector4(-1208.44, -1569.55, 4.61, 107.05),   -- standing coords (/gymcoords)
    scenario = 'WORLD_HUMAN_CLIPBOARD',
    spawnDistance   = 60.0,
    despawnDistance = 90.0,
    blip = { enabled = true, sprite = 311, color = 47, scale = 0.7, name = 'Muscle Sands Gym' },
}

Config.Leaderboard = { enabled = true, size = 5 }

-- ============================================================
--  STATIONS
-- ============================================================
-- coords, coords2, coords3 ... = extra spots for the same exercise.
-- headings = { [1] = 35.0, [2] = 215.0 } for per-spot facing (else `heading`).
-- Use a scenario OR animDict + animName.
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
        animDict = 'timetable@reunited@ig_2',
        animName = 'jimmy_getknocked',
    },
}

-- Flattened list of every usable spot (shared by client + server, same order on both).
function GymSpots()
    local out = {}
    for _, st in ipairs(Config.Stations) do
        local list = {}
        if st.coords then list[#list + 1] = st.coords end
        local i = 2
        while st['coords' .. i] do list[#list + 1] = st['coords' .. i]; i = i + 1 end
        for idx, c in ipairs(list) do
            out[#out + 1] = {
                label = st.label, coords = c, stat = st.stat,
                heading = (st.headings and st.headings[idx]) or st.heading,
                scenario = st.scenario, animDict = st.animDict, animName = st.animName,
            }
        end
    end
    return out
end
