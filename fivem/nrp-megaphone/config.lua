Config = {}

Config.ItemName = 'megaphone'     -- your existing item in tgiann-inventory

-- How far your voice carries in each mode (pma-voice proximity, metres)
Config.Range = {
    handheld = 60.0,
    vehicle  = 100.0,
    stage    = 130.0,
}

-- LOUDNESS: a normal voice fades out a few metres away, so a megaphone did too.
-- Now everyone in range hears it loud and steady, only dropping a little toward the edge.
Config.Loudness = {
    Enabled   = true,
    Gain      = { handheld = 1.6, vehicle = 2.2, stage = 2.0 },   -- 1.0 = normal voice loudness
    FarVolume = 0.5,     -- loudness at the edge of the range (1.0 = right next to the speaker)
}

-- HANDHELD: use the item to raise / lower the megaphone
Config.Handheld = {
    Enabled = true,
    Jobs    = false,              -- false = anyone holding the item. Or e.g. { 'police', 'sheriff' }
}

-- VEHICLE PA: press the key while sitting up front in an allowed vehicle
Config.Vehicle = {
    Enabled    = true,
    Key        = 'F12',           -- players can rebind in Settings > Key Bindings > FiveM
    Classes    = { 18, 15 },      -- 18 = emergency, 15 = helicopters
    Models     = {},              -- extra models that also get a PA, e.g. { 'riot', 'sheriff2' }
    Jobs       = { 'police', 'sheriff', 'ambulance', 'ems' },   -- false = anyone
    FrontSeatsOnly = true,
}

-- STAGE MICS: third-eye / [E] on these props, then talk while you stay next to it
Config.Stage = {
    Enabled = true,
    Models  = { `v_club_roc_micstd`, `prop_table_mic_01` },
    Radius  = 1.6,                -- step further than this from the mic and it switches off
}

-- The megaphone switches itself off when you:
Config.AutoOff = {
    Dead     = true,              -- downed or dead
    Cuffed   = true,
    Swimming = true,
}

-- Click when you start talking (talk_start.ogg) and when you stop (talk_stop.ogg)
-- while the megaphone / PA / mic is on. Works with any push-to-talk key or open mic.
Config.TalkSounds = {
    Enabled    = true,
    Volume     = 0.15,      -- what YOU hear (0.0 - 1.0, kept low)
    OthersHear = true,      -- people nearby hear it too, fading with distance
    OthersRange = 30.0,     -- metres
}

-- HEAR YOURSELF: plays your own voice back to you through a megaphone filter
-- with a short echo, while the megaphone / PA / mic is on and you're talking.
-- Uses your Windows DEFAULT microphone. Headphones recommended (speakers can feed back).
-- Players can turn it off / on for themselves with /megamonitor.
Config.Monitor = {
    Enabled      = true,
    DefaultOn    = true,
    Volume       = 0.25,    -- how loud you hear yourself (0.0 - 1.0)
    EchoDelay    = 0.14,    -- seconds
    EchoFeedback = 0.28,    -- how many repeats (0.0 - 0.6)
    EchoMix      = 0.45,    -- echo loudness vs. your direct voice
    Drive        = 25,      -- megaphone crunch
    -- What counts as "talking" for hearing yourself + the clicks:
    --   'auto' = the game's voice state, falling back to your mic level if the game never reports it
    --   'mic'  = always your mic level      'game' = only the game's voice state
    Gate         = 'auto',
    MicThreshold = 0.02,    -- mic level that counts as talking (raise if background noise triggers it)
    RequirePtt   = true,    -- push-to-talk users: only while the PTT key is held (open-mic users are detected automatically)
}

-- Handheld animation + prop
Config.Anim = {
    dict = 'amb@world_human_mobile_film_shocking@female@base',
    clip = 'base',
    prop = 'prop_megaphone_01',
    bone = 28422,
    pos  = vec3(0.04, -0.01, 0.0),
    rot  = vec3(22.0, -4.0, 87.0),
}

-- Voice effect everyone else hears on you
Config.Effect = {
    freq_low    = 10.0,
    freq_hi     = 10000.0,
    rm_mod_freq = 300.0,
    rm_mix      = 0.2,
    fudge       = 0.0,
    o_freq_lo   = 200.0,
    o_freq_hi   = 5000.0,
}

-- MUFFLED THROUGH WALLS: someone inside a building (or behind walls) still hears
-- the megaphone, but low and muffled - like it really comes from outside.
-- Range itself stays limited by Config.Range above, so it never carries across the map.
Config.Occlusion = {
    Enabled    = true,
    Interiors  = true,     -- inside a building vs outside (or a different building) = muffled
    Walls      = true,     -- solid world geometry between the two heads = muffled
    CutOff     = 2200.0,   -- Hz - lower = more muffled (900 very muffled, 3000 barely). Words stay clear above ~1800
    Volume     = 0.85,     -- loudness when muffled, as a share of the normal megaphone loudness
    CheckEvery = 400,      -- ms between re-checks while someone near you is on a megaphone
}

Config.Debug = false

Config.Notify = function(msg, typ)
    lib.notify({ title = 'Megaphone', description = msg, type = typ or 'inform', position = 'bottom-right' })
end
