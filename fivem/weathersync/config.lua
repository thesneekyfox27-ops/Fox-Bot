Config = {}

---------------------------------------------------------------------
-- FRAMEWORK
---------------------------------------------------------------------
Config.Framework = 'auto'   -- 'auto' | 'qbcore' | 'standalone'

---------------------------------------------------------------------
-- COMMAND & KEYBIND  (one command opens the whole panel)
---------------------------------------------------------------------
Config.MenuCommand    = 'weathermenu'   -- /weathermenu -> opens the all-in-one UI
Config.WeatherCommand = 'weather'        -- /weather <id>
Config.TimeCommand    = 'time'           -- /time <hour> [minute]
Config.OpenKey        = 'F7'             -- rebindable in GTA Settings; false to disable

---------------------------------------------------------------------
-- PERMISSIONS
---------------------------------------------------------------------
Config.RestrictToAdmins = true
Config.AdminGroups   = { 'admin', 'god' }
Config.AcePermission = 'weathersync.admin'

-- How WeatherSync shows its confirmations ("Weather set to…", etc.)
--   'clean' = built-in dark toasts that match the panel (recommended)
--   'qb'    = QBCore:Notify (the green boxes)
--   'chat'  = a line in the chat box
--   'off'   = no notifications at all
Config.Notify = 'clean'

-- Always-allowed admins by identifier (server owner / trusted staff). Add the
-- owner's license/steam/discord here so they can ALWAYS open the menu, even
-- without a QBCore admin group or ACE perm. To find an identifier: open the
-- txAdmin player page, or run  /weathersync_whoami  in chat (it prints yours).
Config.AdminIdentifiers = {
    -- 'license:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
    -- 'steam:11000010xxxxxxx',
    -- 'discord:123456789012345678',
    -- 'fivem:1234567',
}

---------------------------------------------------------------------
-- TIME
---------------------------------------------------------------------
Config.DynamicTime = true
Config.MillisecondsPerMinute = 2000      -- 2000 ≈ a 48-minute day
Config.StartTime = { hour = 9, minute = 0 }

---------------------------------------------------------------------
-- WEATHER
---------------------------------------------------------------------
Config.StartWeatherId = 'sunny'
Config.WeatherTransitionTime = 12.0
Config.StartBlackout = false

-- AUTO WEATHER — a realistic weather system with momentum, not random rolls.
-- Every DynamicWeatherInterval in-game minutes the server does ONE check:
--   1) most of the time the current weather simply persists (calm, stable days),
--   2) when it does change, it only shifts to a NEIGHBOURING weather, so you get
--      natural runs like  clear -> clouds -> cloudy -> rain -> clearing -> clear,
--      never a jarring jump from bright sun straight to a thunderstorm.
-- Time of day then biases the odds (sun midday, fog at dawn/night, storms only
-- really build in the afternoon), so rain is occasional and earned, not constant.
Config.DynamicWeather = false
Config.DynamicWeatherInterval = 20   -- in-game minutes between checks (higher = calmer)

-- Persistence: chance (0.0-1.0) the weather simply STAYS the same on each check.
-- This is the main "calm vs changeable" dial. 0.6 = weather holds most of the time
-- and a full day sees only a handful of natural shifts. Raise it for even calmer days.
Config.WeatherStability = 0.6

-- Transition graph: from each weather, the realistic next steps (weighted, higher =
-- more likely). Weather can ONLY move to a listed neighbour, which is what keeps the
-- progression natural. Note rain is only reachable via 'cloudy', and always has a
-- strong pull back to 'clearing', so storms roll through and clear instead of lingering.
Config.WeatherTransitions = {
    extrasunny = { extrasunny = 4, clear = 3, clouds = 1 },
    clear      = { clear = 4, extrasunny = 2, clouds = 2 },
    clouds     = { clouds = 3, clear = 2, extrasunny = 1, cloudy = 2, clearing = 1 },
    cloudy     = { cloudy = 3, clouds = 2, clearing = 2, rain = 1 },          -- 'cloudy' = grey/overcast
    clearing   = { clearing = 2, clear = 3, clouds = 2, extrasunny = 1 },
    rain       = { rain = 2, cloudy = 2, clearing = 3, thunder = 1 },          -- rain clears fast
    thunder    = { thunder = 1, rain = 3, cloudy = 2 },
    foggy      = { foggy = 3, clearing = 2, clouds = 2 },
    smog       = { smog = 2, clouds = 2, clearing = 2 },
}

-- Time-of-day bias: multiplies the transition weights by hour so the day feels
-- natural. Anything not listed keeps a neutral 1.0. Values < 1 suppress, > 1 favour.
Config.WeatherTimeBias = {
    { from = 5,  to = 8,  mult = { foggy = 3.0, clearing = 2.0, extrasunny = 0.5, rain = 0.4, thunder = 0.2 } }, -- dawn mist
    { from = 8,  to = 11, mult = { extrasunny = 2.0, clear = 2.0, foggy = 0.2, rain = 0.4, thunder = 0.2 } },    -- bright morning
    { from = 11, to = 16, mult = { extrasunny = 3.0, clear = 2.0, rain = 0.3, thunder = 0.15, foggy = 0.1 } },   -- midday sun (rain rare)
    { from = 16, to = 19, mult = { clouds = 1.5, cloudy = 1.5, rain = 1.3, thunder = 1.0, clearing = 1.3 } },    -- afternoon storms build
    { from = 19, to = 22, mult = { clearing = 1.5, clouds = 1.2, rain = 0.6, foggy = 1.2 } },                    -- evening settles
    { from = 22, to = 24, mult = { clear = 1.8, foggy = 1.5, rain = 0.3, thunder = 0.15 } },                     -- night clears
    { from = 0,  to = 5,  mult = { clear = 1.5, foggy = 2.0, rain = 0.3, thunder = 0.15 } },                     -- late night / pre-dawn
}

---------------------------------------------------------------------
-- SERVER RESTART ALERT
-- Plays an emergency siren on every client + forces extreme weather, so a
-- restart feels like the world is ending. Trigger it from the UI toggle, or
-- let it fire automatically before a txAdmin scheduled restart.
---------------------------------------------------------------------
Config.RestartAlert = {
    enabled        = true,
    weatherId      = 'flooding',-- weather forced during the alert. 'flooding' makes the water rise in
                                -- as the restart timer counts down. Use 'storm'/'tornado' for other looks.
    blackout       = true,      -- kill the city grid during the alert
    siren          = true,      -- play the emergency siren on all clients
    sirenVolume    = 0.6,       -- 0.0 - 1.0
    countdownSeconds = 300,     -- default timer length; the UI can override per-use
    -- Command run on the server when the countdown hits 0. 'quit' stops FXServer,
    -- and txAdmin / your host's supervisor brings it back up = a real restart.
    -- The reason MUST be quoted, or `quit` errors with "Argument count mismatch".
    -- IMPORTANT: a resource isn't allowed to run 'quit' by default, so you MUST add
    -- this line to server.cfg (then restart once) or nothing will happen:
    --     add_ace resource.weathersync command.quit allow
    -- Test it any time with the /weathersync_testrestart command. Set to '' for
    -- alert-only (no actual restart).
    restartCommand = 'quit "WeatherSync scheduled restart"',
    -- Auto-fire before a txAdmin scheduled restart when this many seconds (or
    -- fewer) remain. Set to 0 to disable the automatic trigger (UI only).
    -- (txAdmin performs that restart itself, so WeatherSync won't also quit.)
    autoTriggerSeconds = 300,
}

---------------------------------------------------------------------
-- THE PURGE  (custom countdown → blackout, with your own siren sound)
-- Arm it from the panel (purge toggle + its own timer slider). A big HUD
-- counts down for every player; when it hits 0 the city grid goes dark
-- (blackout) and the HUD flips to "in progress" until you toggle it off.
---------------------------------------------------------------------
Config.Purge = {
    enabled          = true,
    countdownSeconds = 600,     -- default timer; the panel slider overrides per-use
    blackout         = true,    -- kill the city grid the moment the timer hits 0
    keepVehicleLights = true,   -- cars keep their headlights during the blackout

    -- ---- WEATHER DURING THE PURGE -----------------------------------------
    -- Force an ominous weather while the purge is active; the previous weather is
    -- restored when it ends. GTA runs one weather at a time, so pick the look you want:
    --   fog:  'foggy'  or  'smog'
    --   bad:  'storm', 'thunder', 'heavyrain', 'rain'
    weather = {
        enabled   = true,
        weatherId = 'foggy',
    },

    -- ---- YOUR SOUND --------------------------------------------------------
    -- 1) Drop your audio file into  weathersync/html/sounds/
    -- 2) Put its EXACT filename here. mp3/ogg/wav all work.
    -- (A placeholder name is set; rename it to your file or rename your file to this.)
    siren            = true,    -- play your sound while the purge is active
    sirenSound       = 'purge_start.mp3',
    sirenVolume      = 0.8,      -- 0.0 - 1.0
    sirenLoop        = true,     -- true: loop through the whole countdown.
                                 -- false: play once the moment you arm it (good for a one-shot announcement).
    playOnZero       = false,    -- also (re)play the sound at 0 when the purge actually begins

    -- ---- END SOUND (plays once when the purge concludes) -------------------
    -- Drop this file in html/sounds/ too, then put its filename here.
    endSound         = 'purge_end.mp3',
    endSoundVolume   = 0.8,
    playEndSound     = true,

    -- ---- HUD text ----------------------------------------------------------
    label            = 'THE PURGE BEGINS IN',  -- shown during the countdown
    activeLabel      = 'PURGE IN PROGRESS',     -- shown after it hits 0
    activeSeconds    = 0,        -- how long the purge stays "in progress" after 0 before
                                 -- auto-ending (restores lights). 0 = stays until you toggle it
                                 -- off OR until the schedule end time below.

    -- ---- EMERGENCY BROADCAST POP-UPS --------------------------------------
    -- A full-width "emergency alert" banner slides in at the top of every screen
    -- the moment the purge starts, and again when it ends. Edit the wording freely.
    broadcast = {
        enabled = true,
        start = {
            seconds = 12,       -- how long the "commenced" banner stays on screen (set it here)
            title   = 'EMERGENCY ALERT SYSTEM',
            heading = 'THE ANNUAL PURGE HAS COMMENCED',
            message = 'All emergency services are suspended until dawn. All weapons are authorized. Commencing at the siren.',
        },
        ending = {
            seconds = 45,       -- how long the "concluded" banner stays — set anywhere from 30-60s
            title   = 'EMERGENCY ALERT SYSTEM',
            heading = 'THE PURGE HAS CONCLUDED',
            message = 'Emergency services have resumed. Stand down. This concludes the Annual Purge.',
        },
    },

    -- ---- SCHEDULE (auto-run between two in-game times) --------------------
    -- The panel's "The Purge" button is the master ENABLE for this. When enabled,
    -- the purge runs itself on WeatherSync's synced clock: at startHour:startMin the
    -- timer + siren begin and the blackout lands when the timer hits 0; at
    -- endHour:endMin it ends (broadcast + end sound + lights back). Wraps past
    -- midnight. `enabled` here is just the value the button starts at after a boot.
    schedule = {
        enabled   = false,              -- OFF by default — the panel button starts off every reset;
                                        -- turn the button on to arm the schedule for that session
        startHour = 0,  startMin = 0,   -- begins at 00:00 (midnight in-game)
        endHour   = 5,  endMin   = 0,   -- ends at 05:00
    },
}

---------------------------------------------------------------------
-- TORNADO / STORM SOUNDS (bundled from your uploaded TornadoScript assets)
---------------------------------------------------------------------
-- One-shot warning siren played for everyone the moment tornado weather starts.
Config.TornadoWarning       = true
Config.TornadoWarningVolume = 0.7
-- Optional low ambient rumble looped during heavy storms (storm/thunder/tornado).
-- Off by default — it's a constant 2D loop, so enable only if you want it.
Config.StormRumble          = false
Config.StormRumbleVolume    = 0.35
Config.StormRumbleWeather   = { storm = true, thunder = true, tornado = true }

---------------------------------------------------------------------
-- FLOODING (real rising water)
-- Uses FiveM's runtime water natives to actually raise the sea/water level
-- when "Flooding" weather is active, then ResetWater() restores defaults when
-- it ends. Synced to all players via the weather broadcast.
-- Technique credit: tofu-dynamic-water / Nikez.
---------------------------------------------------------------------
Config.Flood = {
    enabled    = true,
    useBigQuad = true,    -- true:  load a map-wide water plane (flood.xml) and raise THAT, so the
                          --        whole area (incl. the inland city) floods uniformly. RECOMMENDED.
                          -- false: only raise water bodies that already exist (ocean/lakes). This
                          --        leaves the inland city dry and can look like a floating sheet.
    targetRise = 75.0,    -- metres the water climbs above sea level. Higher = floods more of the
                          -- city (75 ≈ whole low city). Crank toward 120 for a biblical, hills-too flood.
    rate       = 0.2,     -- metres added per tick for a STANDALONE flood (Flooding weather on its own)
    interval   = 80,      -- ms between ticks (lower = faster rise)
    drownPeds  = false,   -- (legacy) also ask the engine to kill peds that stay in the water.
    suppressTraffic = true, -- during a flood, stop ambient cars/peds spawning so nothing drives through
                            -- the water (real NPC cars can't be made to float client-side)

    -- ----- Swimming in the flood ---------------------------------------------
    -- The flood is real GTA water, so the game itself swims you, lets you dive,
    -- floats/sinks cars and plays the proper swim animations (no more T-pose).
    -- This layer only helps it along: if you're in deep water but still standing on
    -- the street, it lifts you up until the game switches you to swimming.
    physics       = true,  -- master switch for the swim helper + drowning below
    buoyancy      = true,  -- true:  you float up and swim normally
                           -- false: you're dragged under - a LETHAL flood; pair with a low breathSeconds
    minDepth      = 1.5,   -- metres of water over your feet before physics kick in (ignores puddles)
    breathSeconds = 12,    -- seconds your head can stay under before health starts draining
    drownDps      = 8,     -- health points lost per second once your breath runs out underwater
    -- When the flood is triggered by the RESTART timer, it ignores `rate` above and
    -- instead rises slowly across the whole countdown, peaking right at restart — so
    -- a 5-minute timer creeps in over 5 minutes and players can evacuate.
}

-- ===================================================================
-- GROUND LIGHTNING
-- Jagged bolts that strike the ground around players during stormy
-- weather (any weather using the THUNDER value: Thunderstorm, Thunder,
-- Tornado, Flooding). Each strike flashes the sky + cracks thunder.
-- Toggle it live from the panel; this is just the startup default.
-- ===================================================================
Config.Lightning = {
    enabled       = true,     -- default on/off (admins can flip it in the panel)
    minDelay      = 2500,     -- ms between strike bursts (minimum)
    maxDelay      = 7000,     -- ms between strike bursts (maximum)
    boltsPerBurst = 2,        -- bolts dropped per burst (2-3 looks like a real storm)
    radius        = 240.0,    -- how far around each player bolts can land
    minDistance   = 35.0,     -- never strike closer than this to the player
    thunder       = true,     -- play a thunder crack at each strike
    damage        = false,    -- if true, a strike near a ped/vehicle can injure/ignite it
}

---------------------------------------------------------------------
-- TORNADO PLACEMENT (where gd_tornado's funnel actually appears)
-- gd_tornado's default summon spawns it at distant preset spots, so it's barely
-- visible. This places it close enough to see and (optionally) keeps it local.
---------------------------------------------------------------------
Config.TornadoSpawn = {
    mode       = 'player',   -- 'player' = near whoever triggers it | 'coords' = fixed spot below
    distance   = 280.0,      -- metres from the player it appears (farther = safer/wider shot of the funnel).
                             -- (gd_tornado starts pulling entities ~57m out, so 60 is "right there".)
    keepLocal  = true,       -- give it a nearby destination so it stays put instead of wandering off
    roamRadius = 90.0,       -- how far that local destination sits (smaller = stays in view longer)
    -- Used in 'coords' mode, or as a fallback when no player is online.
    -- Default is downtown Los Santos (Legion Square area).
    coords     = { x = 215.0, y = -810.0, z = 30.0 },
}

---------------------------------------------------------------------
-- ADD-ON EFFECTS  (plug in a real tornado / flooding asset here)
--
-- This script does NOT ship a fake tornado. Instead, tornado & flooding
-- apply REAL storm effects (heavy sky + max wind + camera rumble + rough
-- seas). If you install a proper effect resource, point an entry below at
-- it and it fires automatically whenever that weather is selected — no
-- code changes needed.
--
-- Each entry can fire on the SERVER and/or each CLIENT when its weather is
-- chosen, and the matching stop when the weather changes away:
--   resource         only fire if this resource is started (safety guard)
--   command          ExecuteCommand on the server  (e.g. a /spawntornado cmd)
--   stopCommand      ExecuteCommand on the server to stop
--   serverEvent      TriggerEvent on the server
--   serverStopEvent  TriggerEvent on the server to stop
--   clientEvent      TriggerEvent on every client
--   clientStopEvent  TriggerEvent on every client to stop
--   ptfxAsset/Name   alternatively, play a streamed particle on each client
--
-- >>> TORNADO :: glitchdetector/gd_tornado <<<  (pre-wired & confirmed)
--   1. Download: https://github.com/glitchdetector/gd_tornado
--   2. Put the 'gd_tornado' folder in resources/
--   3. server.cfg:  ensure gd_tornado   (start it BEFORE weathersync)
--   That's it. gd_tornado exposes the server events `gd_tornado:summon` and
--   `gd_tornado:dismiss`, which are filled in below. When tornado weather is
--   selected, WeatherSync's server triggers the summon (gd_tornado spawns the
--   funnel and syncs it to all players) and dismisses it when weather changes.
--   The hook is skipped automatically if gd_tornado isn't running, so it's
--   safe to leave enabled even before you install it.
--   Note: gd_tornado spawns at one of its preset map locations and doesn't
--   re-sync players who join AFTER it spawned — that's a gd_tornado limitation.
---------------------------------------------------------------------
Config.AddonEffects = {
    tornado = {
        enabled         = true,             -- on; auto-skipped unless gd_tornado is running
        resource        = 'gd_tornado',     -- hook is skipped unless this is running
        command         = '',
        stopCommand     = '',
        positioned      = true,             -- spawn at exact coords (see Config.TornadoSpawn)
        serverEvent     = 'gd_tornado:summon_right_here', -- spawns the funnel AT x,y,z
        serverEventLocal= 'gd_tornado:move_here',         -- gives it a nearby destination
        serverStopEvent = 'gd_tornado:dismiss',           -- removes it
        clientEvent = '', clientStopEvent = '',
        ptfxAsset = '', ptfxName = '', ptfxScale = 8.0, distance = 70.0,
    },
    flooding = {
        -- No solid public asset for true land flooding; leave off. If you find
        -- a rising-water resource, wire it the same way as tornado above.
        enabled         = false,
        resource        = '',
        command = '', stopCommand = '',
        serverEvent     = '', serverStopEvent = '',
        clientEvent     = '', clientStopEvent = '',
        ptfxAsset = '', ptfxName = '', ptfxScale = 6.0, distance = 50.0,
    },
}

---------------------------------------------------------------------
-- WEATHER LIST
-- id/value/featured/desc/sim as before. effects:
--   wind (float) waves (float) snow (bool)
--   addon (string) -> key in Config.AddonEffects, fired if enabled
---------------------------------------------------------------------
Config.WeatherTypes = {
    -- ===== Quick conditions (the big buttons) =====
    { id = 'sunny',    label = 'Sunny',        value = 'EXTRASUNNY', icon = '☀️', featured = true, desc = 'Clear skies',       effects = { wind = 2.0 } },
    { id = 'cloudy',   label = 'Cloudy',       value = 'OVERCAST',   icon = '☁️', featured = true, desc = 'Grey & overcast',   effects = { wind = 8.0 } },
    { id = 'heavyrain',label = 'Heavy Rain',   value = 'RAIN',       icon = '🌧️', featured = true, desc = 'Wind-driven rain',  effects = { wind = 26.0 } },
    { id = 'storm',    label = 'Thunderstorm', value = 'THUNDER',    icon = '⛈️', featured = true, desc = 'Lightning & gusts', effects = { wind = 45.0 } },
    { id = 'snow',     label = 'Snow',         value = 'SNOW',       icon = '❄️', featured = true, desc = 'Snowfall',          effects = { wind = 10.0, snow = true } },
    { id = 'blizzard', label = 'Blizzard',     value = 'BLIZZARD',   icon = '🌬️', featured = true, desc = 'Heavy snowstorm',   effects = { wind = 42.0, snow = true } },
    { id = 'tornado',  label = 'Tornado',      value = 'THUNDER',    icon = '🌪️', featured = true, desc = 'Extreme storm',     sim = true, effects = { wind = 95.0, waves = 6.0, addon = 'tornado' } },
    { id = 'flooding', label = 'Flooding',     value = 'THUNDER',    icon = '🌊', featured = true, desc = 'Rising water',      effects = { wind = 55.0, waves = 9.0, flood = true } },

    -- ===== All other base types =====
    { id = 'extrasunny', label = 'Extra Sunny', value = 'EXTRASUNNY', icon = '🌞', effects = { wind = 1.0 } },
    { id = 'clear',      label = 'Clear',       value = 'CLEAR',      icon = '🌤️', effects = { wind = 3.0 } },
    { id = 'clouds',     label = 'Clouds',      value = 'CLOUDS',     icon = '⛅', effects = { wind = 6.0 } },
    { id = 'smog',       label = 'Smog',        value = 'SMOG',       icon = '🌫️', effects = { wind = 2.0 } },
    { id = 'foggy',      label = 'Foggy',       value = 'FOGGY',      icon = '🌁', effects = { wind = 2.0 } },
    { id = 'clearing',   label = 'Clearing',    value = 'CLEARING',   icon = '🌥️', effects = { wind = 5.0 } },
    { id = 'rain',       label = 'Rain',        value = 'RAIN',       icon = '🌦️', effects = { wind = 12.0 } },
    { id = 'thunder',    label = 'Thunder',     value = 'THUNDER',    icon = '⚡', effects = { wind = 30.0 } },
    { id = 'snowlight',  label = 'Snow Light',  value = 'SNOWLIGHT',  icon = '🌨️', effects = { wind = 6.0, snow = true } },
    { id = 'xmas',       label = 'Xmas',        value = 'XMAS',       icon = '🎄', effects = { wind = 8.0, snow = true } },
    { id = 'halloween',  label = 'Halloween',   value = 'HALLOWEEN',  icon = '🎃', effects = { wind = 4.0 } },
    { id = 'neutral',    label = 'Neutral',     value = 'NEUTRAL',    icon = '◽' },
}

function Config.GetWeather(key)
    if not key then return nil end
    local k = string.lower(tostring(key))
    for _, w in ipairs(Config.WeatherTypes) do
        if string.lower(w.id) == k then return w end
    end
    local up = string.upper(tostring(key))
    for _, w in ipairs(Config.WeatherTypes) do
        if w.value == up then return w end
    end
    return nil
end

---------------------------------------------------------------------
-- TIME PRESETS
---------------------------------------------------------------------
Config.TimePresets = {
    { label = 'Dawn',    hour = 6,  minute = 0 },
    { label = 'Morning', hour = 9,  minute = 0 },
    { label = 'Noon',    hour = 12, minute = 0 },
    { label = 'Evening', hour = 18, minute = 0 },
    { label = 'Night',   hour = 0,  minute = 0 },
}
