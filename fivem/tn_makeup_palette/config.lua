Config = {}

-- Item name (must match the item registered in tgiann-inventory items.lua)
Config.Item = 'makeup_palette'

-- Consume the item on use? false = reusable palette
Config.ConsumeItem = false

-- Progress duration in ms (wiping everything off / putting it all back on)
Config.Progress = 4000
-- Doing just one part (only lipstick, only blush...) is quicker
Config.ProgressSingle = 2500

-- Use ox_lib circle progress (true) or bar (false)
Config.ProgressCircle = true

-- "Mirror" camera: a close-up on your face while you wipe off / put on makeup
Config.Camera = {
    Enabled  = true,
    Distance = 0.55,   -- metres in front of your face
    Fov      = 40.0,
}

-- Animation + prop
-- If the dict or prop below does not exist on your build, the script skips the
-- animation instead of erroring - you still get the progress bar.
Config.Anim = {
    -- 'clothingtie' ships with the base game (qb-clothing uses it). Alternatives:
    --   dict 'amb@world_human_mirror@female@base'               name 'base'
    --   dict 'mp_player_int_uppergrab'                          name 'idle_a'
    --   dict 'anim@mp_player_intcelebrationfemale@face_palm'    name 'face_palm'
    dict = 'clothingtie',
    name = 'try_tie_negative_a',
    flag = 49,

    -- Prop is OFF by default. Turn it on only after checking the model streams
    -- in on your server (e.g. 'prop_cs_lipstick').
    prop = nil,
    bone = 28422,                    -- right hand
    offset = vec3(0.10, 0.02, 0.03),
    rot    = vec3(-100.0, 20.0, -20.0),
}

-- The parts of your look the palette handles. GTA V has no separate eyeshadow
-- overlay - it's part of Eye makeup (index 4). Remove a line to leave that part alone.
Config.Parts = {
    { index = 4, label = 'Eye makeup', icon = 'eye' },
    { index = 5, label = 'Blush',      icon = 'heart' },
    { index = 8, label = 'Lipstick',   icon = 'face-kiss-wink-heart' },
}

-- Your appearance script can put makeup back on by itself (respawn, outfit
-- change, reconnect). While makeup is wiped off, the palette checks every
-- this-many ms and takes it off again. New makeup from the barber is kept.
Config.WatchEvery = 1500

-- Usage restrictions (false = can NOT use in that state)
Config.Restrictions = {
    dead        = false,
    cuffed      = false,
    swimming    = false,
    falling     = false,
    inVehicle   = true,   -- doing your makeup in the car mirror is fine
    ragdoll     = false,
}
