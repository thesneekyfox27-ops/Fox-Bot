Config = {}

-- ============================================================
--  GENERAL
-- ============================================================
Config.Debug = false

-- How players open the elevator panel (GLOBAL DEFAULT):
--   'target' = ox_target eye (recommended for NRP)
--   'marker' = glowing floor marker + press E
--   'textui' = ox_lib textUI + press E
-- Each elevator can override this individually from the in-game
-- admin menu (F7 -> elevator -> Interaction Mode).
Config.Interaction = 'target'

Config.InteractDistance = 1.8   -- meters
Config.TargetIcon       = 'fas fa-elevator'

-- ---- MARKER mode look ----
Config.Marker = {
    type         = 1,                                    -- 1 = soft light circle, 25/27 = flat ring, 36 = chevron
    size         = vec3(0.9, 0.9, 0.4),
    color        = { r = 71, g = 199, b = 212, a = 110 },-- RGBA (teal to match the panel)
    zOffset      = -0.9,                                 -- negative = sit on the floor
    rotate       = false,
    bobUpAndDown = false,
    drawDistance = 12.0,                                 -- meters before markers start drawing
}

-- ---- CALL ANIMATION ----
-- Player reaches out and presses the call button before the panel opens.
Config.CallAnimation = {
    enabled    = true,
    dict       = 'anim@mp_player_intmenu@key_fob@',
    anim       = 'fob_click',   -- arm-out button press
    durationMs = 900,           -- panel opens right after
}

-- ============================================================
--  ADMIN ACCESS  (all in-game, menu driven — no command spam)
--  One entry point: keybind OR /elevators. Everything else is menus.
-- ============================================================
Config.Admin = {
    -- Discord ID allowlist (same style as nrp-carperf).
    -- Right click your name in Discord -> Copy User ID (Developer Mode on).
    -- Works with or without the 'discord:' prefix.
    discordIds = {
        '558189139107905537',   -- Daddy Brain
        -- '123456789012345678',  -- car dev
    },
    groups  = {},                 -- optional QBCore group fallback, e.g. { 'god' } ({} = discord only)
    command = 'elevators',        -- single fallback command
    keybind = '',               -- open admin menu ('' = disabled, rebindable in GTA settings > keybinds > FiveM)
}

-- ============================================================
--  PANEL LOOK  (fully customizable)
-- ============================================================
Config.Panel = {
    theme       = 'teal',      -- teal | amber | red | pink | purple | cyan | green | white | custom
    customColor = '#9b5dff',   -- used only when theme = 'custom' (any hex)
    position    = 'right',     -- right | left | center
    -- Floor numbers on the buttons. 1 = floors are 1,2,3...  0 = 0,1,2... (0 = ground).
    -- This is the default; each elevator can override it in the F7 manager
    -- ("Floor Numbering"), so elevators that are perfect with 1 stay as they are.
    -- A floor can also have its own button text (P, G, R, B1...) set in its EDIT box.
    firstFloorNumber = 1,
    logo        = 'logo.png',  -- 100x100 image shown at the top of the panel.
                               -- Replace html/logo.png with your own (keep the
                               -- name, or change it here). false = no logo.
}

Config.PanelThemes = {
    teal   = '#47c7d4',
    amber  = '#ffb300',
    red    = '#ff3b3b',
    pink   = '#ff5bcf',
    purple = '#9b5dff',
    cyan   = '#47abe9',
    green  = '#39ff88',
    white  = '#f2f2f2',
}

-- ============================================================
--  TRANSITION (screen fade when riding)
-- ============================================================
Config.Transition = {
    fadeOutMs    = 600,   -- fade to black
    holdMs       = 600,   -- "doors closing" pause before the ride starts
    msPerFloor   = 800,   -- ride time PER FLOOR — the travel HUD counts floors in sync with this
    fadeInMs     = 600,   -- fade back in
    freezePlayer = true,
    sounds       = true,  -- master toggle (native GTA sounds, no audio files)
}

-- ============================================================
--  SOUNDS
--  Two kinds per entry:
--    native = { name, set }  -> GTA frontend sound
--    file   = 'name.wav'     -> custom file from html/sounds/
--                               (wav / ogg / mp3 — just drop them in)
--  If both are set, the file wins. Set an entry to false to mute it.
--
--  Ships with two synthesized sounds ready to go:
--    ding.wav            -> real elevator chime
--    elevator_moving.wav -> loopable mechanical hum
--  Swap them for any sound you like, same filenames or update below.
-- ============================================================
Config.Sounds = {
    -- pressing a floor button (local only)
    buttonPress = { native = { name = 'SELECT', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' } },

    -- soft tick each floor the HUD counts past (local only)
    floorPass   = { native = { name = 'HIGHLIGHT_NAV_UP_DOWN', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' } },

    -- elevator hum while riding (loops, stops on arrival — local only)
    moving      = { file = 'elevator_moving.wav', volume = 0.45, loop = true },

    -- arrival ding — broadcast = everyone within radius meters of the
    -- destination hears it (volume falls off with distance), so people
    -- on the floor hear the elevator arrive before the doors open.
    arrival     = { file = 'ding.wav', volume = 0.8, broadcast = true, radius = 20.0 },

    -- the bell button on the panel: an alarm bell everyone within radius hears
    -- (synthesised in the UI, no file needed). false = bell button does nothing.
    alarm       = { volume = 0.7, radius = 15.0 },
}

-- ============================================================
--  STATIC ELEVATORS (optional)
--  You normally DON'T need this — create elevators in-game with
--  the admin menu (F7 or /elevators) and they save automatically.
--  This table is for elevators you want locked into the config.
--  In-game created elevators live in elevators.json.
-- ============================================================
Config.Elevators = {

    -- Example (uncomment / edit if you prefer config-managed):
    -- {
    --     name = 'Pier Motel',
    --     numberFrom = 0,          -- optional: 0 = ground floor is "0"
    --     floors = {
    --         { label = 'Ground Floor', coords = vec4(-1345.33, -784.6, 20.24, 127.64) },   -- button "0"
    --         { label = 'Parking', button = 'P', coords = vec4(...) },                      -- custom button
    --         { label = '2nd Floor',    coords = vec4(-1333.93, -772.85, 29.55, 212.32) },
    --     },
    -- },

}
