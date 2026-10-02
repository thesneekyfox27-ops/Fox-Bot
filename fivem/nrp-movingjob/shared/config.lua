Config = {}

-- ---------------------------------------------------------------------------
-- Company
-- ---------------------------------------------------------------------------
Config.CompanyName = 'Haulaway Moving Co.'

-- Set to a job name to gate the work behind employment, or false for open work.
Config.RequireJob = false          -- e.g. 'mover'

-- Clipboard paperwork (the contract board UI). false = the old ox_lib menus.
Config.Paperwork = {
    enabled       = true,
    address       = 'Haulaway Yard, Elysian Island',   -- printed on the contract
    phone         = '(555) 010-4285',
    yardLabel     = 'the Haulaway yard',
    mustMatchName = true    -- the contract must be signed with the character's real name
}
Config.PayAccount = 'cash'         -- cash | bank

-- ---------------------------------------------------------------------------
-- Depot / boss
-- ---------------------------------------------------------------------------
-- These are staging coords. Re-place them in-game before you ship it.
Config.Boss = {
    model  = 's_m_m_dockwork_01',
    coords = vector4(1010.16, -2528.88, 28.30, 88.00),
    scenario = 'WORLD_HUMAN_CLIPBOARD'
}

Config.Blip = {
    enabled = true,
    sprite  = 479,
    colour  = 3,
    scale   = 0.75,
    label   = 'Haulaway Moving Co.'
}

Config.Depot = {
    -- Where the crates/furniture sit waiting to be carried to the van.
    pallet = vector3(1013.28, -2521.57, 28.30),
    -- The van has to be parked within this range of the pallet to load.
    vanRange = 25.0
}

-- ---------------------------------------------------------------------------
-- Van
-- ---------------------------------------------------------------------------
Config.Van = {
    model       = 'boxville2',
    platePrefix = 'HAUL',
    livery      = nil,               -- set an index if you stream a branded van

    -- First free bay wins.
    bays = {
        vector4(1002.42, -2522.62, 28.30, 88.00),
        vector4(1002.18, -2527.95, 28.30, 88.00),
        vector4(1002.68, -2517.35, 28.30, 88.00),
        vector4(995.34,  -2522.50, 28.30, 88.00)
    },
    bayClearRadius = 7.0,

    -- Rear door interaction point, in vehicle space.
    rearOffset = vector3(0.0, -3.85, 0.35),
    rearRange  = 2.6,

    -- Cargo door indices. 2 and 3 are the rear pair on boxville2. If you swap
    -- van model, check these with a door test before you ship it.
    rearDoors = { 2, 3 },

    -- Doors swing open on their own when a loader walks up behind the van with
    -- the job running, and shut when everyone steps away or someone gets in.
    autoDoors = true,
    autoDoorRange = 4.0,

    -- Cargo cannot go in or out while the doors are shut.
    requireDoorsOpen = true,

    -- Where cargo physically stacks inside the box, in vehicle space.
    -- Filled front to back, and emptied back to front.
    slots = {
        vector3(-0.28, -1.65, 0.12),
        vector3( 0.00, -1.65, 0.12),
        vector3( 0.28, -1.65, 0.12),
        vector3(-0.28, -2.25, 0.12),
        vector3( 0.00, -2.25, 0.12),
        vector3( 0.28, -2.25, 0.12),
        vector3( 0.00, -2.85, 0.12)
    }
}

-- ---------------------------------------------------------------------------
-- Cargo
-- ---------------------------------------------------------------------------
-- carry = how the prop sits in the hand while walking it across the lot.
-- stack = how it sits once it is in the van.
-- Bone the carried prop hangs off. 28422 is IK_R_Hand, which is what the
-- box-carry animation is built around. Override per item with carry.bone.
Config.CarryBone = 28422

-- carry = how the prop sits in the hands while walking.
-- stack = how it sits once it is in the van.
--
-- These are starting points. Prop pivots are all over the place, so dial each
-- one in with /carrytune <index> in game - it prints a ready-to-paste block.
Config.Cargo = {
    {
        label = 'Moving Box',
        model = 'prop_cs_cardbox_01',
        weight = 'light',
        carry = { pos = vector3(0.025, -0.116, -0.133), rot = vector3(-76.0, 326.0, 5.0) }
    },
    {
        label = 'Small Box',
        model = 'prop_cardbordbox_02a',
        weight = 'light',
        carry = { pos = vector3(0.016, -0.301, -0.022), rot = vector3(-77.0, 290.0, 0.0) }
    },
    {
        label = 'Office Chair',
        model = 'prop_off_chair_04',
        weight = 'medium',
        carry = { pos = vector3(0.012, 0.062, -0.488), rot = vector3(-74.0, 290.0, -112.0) }
    },
    {
        label = 'Dining Chair',
        model = 'prop_chair_04a',
        weight = 'medium',
        carry = { pos = vector3(-0.045, -0.004, -0.524), rot = vector3(-77.0, 290.0, -115.0) }
    },
    {
        -- prop_table_04 is a dining table, not a nightstand. Renamed rather
        -- than swapped so your tuned offsets still hold.
        label = 'Dining Table',
        model = 'prop_table_04',
        weight = 'heavy',
        carry = { pos = vector3(0.252, -0.182, -0.460), rot = vector3(19.0, -3.0, 2.0) },
        stack = { rot = vector3(0.0, 0.0, 90.0), z = -0.08 }
    },
    {
        -- prop_tv_flat_03 is a full-size panel. Swap the model if you want
        -- something crate-sized; you would need to re-tune the carry block.
        label = 'Boxed TV',
        model = 'prop_tv_flat_03',
        weight = 'fragile',
        carry = { pos = vector3(-0.204, -0.046, -0.036), rot = vector3(179.0, 225.0, -2.0) },
        stack = { z = 0.64 }
    },
    {
        -- NOT TUNED YET. Pick a model with /testprop, then run /carrytune 7
        -- and paste the result over this line.
        label = 'Microwave',
        model = 'prop_micro_01',
        weight = 'medium',
        carry = { pos = vector3(0.025, -0.116, -0.045), rot = vector3(-76.0, 326.0, 5.0) }
    },
    {
        -- NOT TUNED. /carrytune 8
        label = 'Floor Lamp',
        model = 'h4_mp_h_yacht_floor_lamp_01',
        weight = 'medium',
        carry = { pos = vector3(-0.135, 0.020, -0.221), rot = vector3(282.0, 341.0, 277.0) }
    },
    {
        -- NOT TUNED. /carrytune 9
        label = 'BBQ Grill',
        model = 'prop_bbq_4_l1',
        weight = 'heavy',
        carry = { pos = vector3(0.073, 0.220, -0.945), rot = vector3(-375.0, 357.0, -176.0) }
    },
    {
        -- NOT TUNED. /carrytune 10
        label = 'Security Camera',
        model = 'v_res_cctv',
        weight = 'light',
        carry = { pos = vector3(0.025, -0.116, -0.045), rot = vector3(-76.0, 326.0, 5.0) }
    }
}

-- ---------------------------------------------------------------------------
-- Hand truck
-- ---------------------------------------------------------------------------
-- A dolly you push around. Load several pieces onto it at the pallet or out of
-- the van, wheel it over, then unload one at a time. Slower than carrying, but
-- it moves three pieces per trip instead of one.
Config.Dolly = {
    enabled  = false,   -- see fxmanifest.lua to re-enable
    model    = 'prop_sacktruck_01',
    capacity = 3,
    speed    = 0.88,        -- move rate override while pushing

    -- How the truck sits in front of you while pushing.
    -- Tune live with /dollytune.
    attach = {
        bone = 28422,       -- IK_R_Hand
        pos  = vector3(0.13, 0.36, -0.55),
        rot  = vector3(-95.0, 180.0, 0.0)
    },

    -- Push animation. Swap this if you have one you prefer.
    anim = { dict = 'anim@heists@box_carry@', clip = 'idle' },

    -- Where pieces stack on the truck plate, in truck-local space.
    -- Bottom of the stack first.
    slots = {
        vector3(0.0, 0.06, 0.20),
        vector3(0.0, 0.06, 0.52),
        vector3(0.0, 0.06, 0.84)
    },

    -- Timings
    loadMs   = 900,
    unloadMs = 900
}

-- Carry animation + timings per weight class. Heavier boxes walk slower and
-- take longer to set down, which is the whole reason a crew is worth splitting
-- the pay with.
Config.Weights = {
    light   = { dict = 'anim@heists@box_carry@', clip = 'idle', liftMs = 1200, setMs = 1100, speed = 1.0 },
    medium  = { dict = 'anim@heists@box_carry@', clip = 'idle', liftMs = 1600, setMs = 1400, speed = 0.86 },
    heavy   = { dict = 'anim@heists@box_carry@', clip = 'idle', liftMs = 2200, setMs = 1900, speed = 0.72 },
    fragile = { dict = 'anim@heists@box_carry@', clip = 'idle', liftMs = 2000, setMs = 2100, speed = 0.78 }
}

-- ---------------------------------------------------------------------------
-- Contracts
-- ---------------------------------------------------------------------------
Config.Contracts = {
    offered      = 3,        -- how many jobs the boss shows on the board
    minItems     = 4,
    maxItems     = 7,
    payPerItem   = { min = 95,  max = 160 },
    bonus        = { min = 275, max = 475 },

    -- The van has to be near the drop before cargo can come out of it.
    vanDropRange = 30.0,

    -- Fragile cargo dropped from a height, or delivered after the van has been
    -- rolled, comes off the final payout.
    damagePenalty = 0.45     -- fraction of one item's pay lost per broken item
}

Config.Customers = {
    'Marlene Carter', 'DeShawn Price', 'Ari Morgan', 'Noah Brooks',
    'Rosa Delgado', 'Marcus Reed', 'Kelly Stone', 'Andre Wilson',
    'Tamika Boyd', 'Vic Salerno', 'Priya Raman', 'Chuck Hardaway'
}

-- Doorstep drops. `door` is the front door, `arrival` is the spot on the
-- pavement the items get stacked around.
Config.Drops = {
    { label = 'Mirror Park house',     door = vector3(1229.68, -725.52, 60.80), arrival = vector3(1228.70, -724.25, 60.58) },
    { label = 'Vespucci apartment',    door = vector3(-1118.30, -938.63, 2.15), arrival = vector3(-1120.92, -940.95, 2.15) },
    { label = 'Del Perro condo',       door = vector3(-1452.92, -653.19, 29.58), arrival = vector3(-1454.18, -655.04, 29.58) },
    { label = 'Vinewood Hills home',   door = vector3(340.94, 437.06, 149.39),  arrival = vector3(338.88, 436.02, 149.14) },
    { label = 'Alta Street loft',      door = vector3(299.72, -902.88, 29.29),  arrival = vector3(297.12, -902.78, 29.18) }
}

-- Doorstep stacking pattern, measured out from the door toward the arrival
-- point. forward = away from the door, side = left/right spread.
Config.DropPattern = {
    { forward = 0.90, side =  0.00 },
    { forward = 1.00, side =  0.65 },
    { forward = 1.00, side = -0.65 },
    { forward = 1.60, side =  0.00 },
    { forward = 1.65, side =  0.65 },
    { forward = 1.65, side = -0.65 },
    { forward = 2.25, side =  0.00 }
}

-- ---------------------------------------------------------------------------
-- Crew
-- ---------------------------------------------------------------------------
Config.Crew = {
    enabled     = true,
    maxMembers  = 4,          -- including the leader
    inviteRange = 8.0,
    inviteMs    = 45000,
    splitPay    = true        -- false pays every member the full amount
}

-- ---------------------------------------------------------------------------
-- Uniform
-- ---------------------------------------------------------------------------
Config.Uniform = {
    enabled = false,
    restore = true,

    -- What happens to your own clothes when the job ends, or when you come
    -- back to a character that was still in the vest after a crash/restart.
    --   'auto'   put them back straight away
    --   'prompt' ask first
    --   'off'    leave the vest on; /myclothes changes back on demand
    -- Defaults to 'prompt' so nothing silently overwrites an outfit you
    -- changed into. Coming back after a crash always asks, whatever this says.
    restoreMode = 'prompt',

    -- Your character system. The reapply bridge below routes through it.
    clothingResource = '17mov_CharacterSystem',
    clothingDebug = false,

    -- Preferred restore route. Your character system already knows this
    -- character's real appearance, so letting it re-apply is more reliable
    -- than this script replaying a snapshot of five component slots.
    -- Return true if you handled it; false falls back to the snapshot.
    --
    -- Export names differ between versions, so this tries the known shapes
    -- and stops at the first that does not error. The caller then checks the
    -- ped afterwards: if you are still in the vest, it falls back to the
    -- snapshot regardless of what this returned.
    reapply = function()
        local res = Config.Uniform.clothingResource
        local attempts = {}

        if res and GetResourceState(res) == 'started' then
            attempts[#attempts + 1] = function() return exports[res]:ApplySkin() end
            attempts[#attempts + 1] = function() return exports[res]:ReloadSkin() end
            attempts[#attempts + 1] = function() return exports[res]:LoadSkin() end
            attempts[#attempts + 1] = function() return exports[res]:SetPlayerSkin() end
            attempts[#attempts + 1] = function()
                TriggerEvent(res .. ':ReloadSkin') return true
            end
        end

        -- QBCore clothing fallbacks.
        if GetResourceState('qb-clothing') == 'started' then
            attempts[#attempts + 1] = function()
                TriggerEvent('qb-clothing:client:loadPlayerClothing') return true
            end
        end
        if GetResourceState('qb-clothes') == 'started' then
            attempts[#attempts + 1] = function()
                TriggerServerEvent('qb-clothes:loadPlayerSkin') return true
            end
        end

        for i, attempt in ipairs(attempts) do
            if pcall(attempt) then
                if Config.Uniform.clothingDebug then
                    print(('[nrp-movingjob] clothing reapply: attempt %d ran'):format(i))
                end
                return true
            end
        end

        if Config.Uniform.clothingDebug then
            print('[nrp-movingjob] clothing reapply: nothing worked, using snapshot')
        end
        return false
    end,
    male = {
        components = {
            [3]  = { drawable = 41, texture = 0 },
            [4]  = { drawable = 36, texture = 0 },
            [6]  = { drawable = 12, texture = 0 },
            [8]  = { drawable = 59, texture = 1 },
            [11] = { drawable = 56, texture = 0 }
        }
    },
    female = {
        components = {
            [3]  = { drawable = 44, texture = 0 },
            [4]  = { drawable = 35, texture = 0 },
            [6]  = { drawable = 27, texture = 0 },
            [8]  = { drawable = 36, texture = 1 },
            [11] = { drawable = 48, texture = 0 }
        }
    }
}

-- ---------------------------------------------------------------------------
-- Integrations - edit these two and nothing else
-- ---------------------------------------------------------------------------
Config.UseTarget = true            -- ox_target / nrp-target for the boss ped

-- The van rear is always a plain [E] prompt regardless of the setting above.
-- Targeting a moving box panel while holding a sofa is miserable.
Config.RearUseKey = true

-- ---------------------------------------------------------------------------
-- Rear doors
-- ---------------------------------------------------------------------------
Config.RearDoors = {
    enabled   = true,
    indices   = { 2, 3 },   -- boxville2 rear barn doors; speedo uses the same
    autoClose = true,       -- shut them once you walk away from the back
    closeRange = 6.0
}

-- ---------------------------------------------------------------------------
-- Placement indicators
-- ---------------------------------------------------------------------------
Config.Indicators = {
    enabled      = true,
    markers      = true,    -- ground markers + bobbing arrows
    ghosts       = true,    -- translucent preview of the piece at the drop spot
    ghostAlpha   = 120,     -- 0-255
    drawDistance = 18.0,    -- range for the small on-foot markers

    -- The delivery address marker. Shows as a tall column while you are
    -- driving in, then flattens to a landing circle as you pull up.
    zoneRadius       = 4.0,
    zoneDrawDistance = 150.0,   -- start drawing it from here
    zoneBeaconRange  = 45.0,    -- further than this, draw the tall column
    zoneBeaconHeight = 30.0,    -- how tall that column is

    colours = {
        pickup = { 255, 199, 0, 90 },    -- next item on the pallet
        van    = { 12, 150, 220, 70 },   -- van rear
        drop   = { 60, 220, 120, 90 },   -- exact doorstep spot for this piece
        spot   = { 255, 255, 255, 30 },  -- the other spots still to be filled
        zone   = { 60, 220, 120, 55 }    -- the address itself
    }
}

-- Name of your key resource. Everything below routes through this.
Config.KeyResource = '0r-vehiclekeys'

-- Set true once to print which of the attempts below actually landed, then
-- delete the ones that failed and set this back to false.
Config.KeyDebug = false

--- Hand the van's keys to the player. Called client side, right after the van
--- spawns, and again for each crew member once the van streams in for them.
---
--- 0r-vehiclekeys has changed its API across versions and yours is a patched
--- fork, so this tries the known shapes in order and stops at the first one
--- that does not error. If none land, the server side grant in server/main.lua
--- is the backstop.
function Config.GiveKeys(vehicle, plate)
    if GetResourceState(Config.KeyResource) ~= 'started' then return end

    local attempts = {
        -- exports, newest first
        function() return exports[Config.KeyResource]:GiveKeys(plate) end,
        function() return exports[Config.KeyResource]:AddKey(plate) end,
        function() return exports[Config.KeyResource]:SetVehicleKey(vehicle, true) end,
        -- client events
        function() TriggerEvent(Config.KeyResource .. ':client:AddKey', plate) return true end,
        function() TriggerEvent('vehiclekeys:client:SetOwner', plate) return true end
    }

    for i, attempt in ipairs(attempts) do
        local ok = pcall(attempt)
        if ok then
            if Config.KeyDebug then
                print(('[nrp-movingjob] client key grant landed on attempt %d for %s'):format(i, plate))
            end
            return true
        end
    end

    if Config.KeyDebug then
        print(('[nrp-movingjob] no client key method worked for %s, leaning on the server grant'):format(plate))
    end
    return false
end

function Config.SetFuel(vehicle, amount)
    if GetResourceState('LegacyFuel') == 'started' then
        exports['LegacyFuel']:SetFuel(vehicle, amount)
    else
        SetVehicleFuelLevel(vehicle, amount + 0.0)
    end
end

-- ---------------------------------------------------------------------------
-- Server anti-cheat distances. Anything further than this from the action gets
-- the event dropped and logged.
-- ---------------------------------------------------------------------------
Config.MaxActionDistance = 12.0
Config.EventCooldownMs   = 800
Config.LogSuspicious     = true
