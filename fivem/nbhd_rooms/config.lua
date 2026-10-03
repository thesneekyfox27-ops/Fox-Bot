Config = {}

-- ============================================================
--  GLOBAL OPTIONS
-- ============================================================

-- Give players the SAME room back when they log in again (if it's free).
-- Their safe storage is always theirs either way (keyed by citizenid).
Config.KeepLastRoom = true

-- Safes and the receptionist are only spawned while you are this close to the
-- building (so the floors are loaded and nothing ends up under the map).
Config.SpawnDistance   = 90.0
Config.DespawnDistance = 130.0

-- Which inventory opens the room safe: 'auto', 'tgiann', 'ox', 'qb' or 'legacy'
-- ('legacy' = the old client event 'inventory:server:OpenInventory').
Config.Inventory = 'auto'

-- Wardrobe: client event that opens the outfit menu. 'auto' picks
-- illenium-appearance, then qb-clothing.
Config.WardrobeEvent = 'auto'

-- "Already owns a home" check for skipIfOwnsAnyProperty. Any of these tables
-- that exist on your database are checked (missing ones are ignored).
Config.HomeTables = {
    { table = 'player_houses', column = 'citizenid' },        -- qb-houses
    { table = 'properties',    column = 'owner_citizenid' },  -- ps-housing
}

--[[
    MULTI-BUILDING ROOM SYSTEM
    ==========================
    Each entry in Config.Buildings is one building. Copy a block, change the
    data, restart — no code edits needed.

    Per building:
      label          - display name; also used in DB rows as '<label> Room N'
      autoAssign     - true: players get a free room here on login (if they
                       don't already have one in THIS building)
      skipIfOwnsAnyProperty - with autoAssign: skip players who own ANY
                       property in tk_housing (so homeowners don't get rooms)
      sessionBased   - true: room is released when the player logs out
      rent           - rent value written to the property row
      roomsPerFloor  - units per floor
      floors         - number of room floors
      baseZ          - player-standing Z on the FIRST room floor
      floorHeight    - Z offset per floor up
      doorModel      - door prop model hash for the lock system (use
                       /findmoteldoor at a door to discover it)
      doorBaseZ      - door prop Z on the first room floor
      lockKey        - control id for lock/unlock at the door (311 = K)
      interactKey    - control id for locker/wardrobe/reception (38 = E)
      lockSound      - interact-sound file name played on door toggle (or false)
      lockerSound    - interact-sound file name played on locker open (or false)
      locker         - { slots, weight } or false to disable lockers
      safeModel      - prop spawned as the room safe (false = no safe prop,
                       locker disabled too)
      receptionist   - { model, coords(vec4), scenario } or false
      floorOffset    - added to the floor number the receptionist says (0 = rooms
                       1-8 are "Floor 1"; set 1 if the lobby counts as floor 1)
      safeZOffset    - safe height relative to the player-standing Z (-1.0 = floor)
      rooms          - one entry per unit, measured on the FIRST room floor:
          door     = { x, y, h }   door prop position + heading
          safe     = { x, y, h }   exact safe position + door-facing heading
          wardrobe = { x, y }      change-outfit spot
        (safe / wardrobe can be omitted per room to disable there)
]]

Config.Buildings = {

    piermotel = {
        label                 = 'Pier Motel',
        autoAssign            = true,
        skipIfOwnsAnyProperty = true,
        sessionBased          = true,
        rent                  = 0,

        roomsPerFloor = 8,
        floors        = 6,
        baseZ         = 29.56,
        floorHeight   = 3.64,

        doorModel   = 1436076651,
        doorBaseZ   = 29.65,
        lockKey     = 311, -- K
        interactKey = 38,  -- E
        lockSound   = 'motel_doorlock',
        lockerSound = 'LockerOpen',

        locker      = { slots = 10, weight = 50000 },
        safeModel   = `prop_ld_int_safe_01`,
        safeZOffset = -1.0,
        floorOffset = 0,   -- rooms 1-8 Floor 1, 9-16 Floor 2, ... 41-48 Floor 6

        receptionist = {
            model    = 'a_f_y_business_02',
            coords   = vector4(-1347.93, -788.87, 20.24, 19.09),
            scenario = nil,
        },

        rooms = {
            { door = { x = -1331.72, y = -771.97, h = 126.97 }, safe = { x = -1328.59, y = -769.65, h = 121.93 }, wardrobe = { x = -1333.49, y = -769.09 } },
            { door = { x = -1331.68, y = -775.06, h = 36.62  }, safe = { x = -1328.87, y = -781.30, h = 26.36  }, wardrobe = { x = -1332.04, y = -781.60 } },
            { door = { x = -1337.44, y = -779.34, h = 36.62  }, safe = { x = -1335.51, y = -780.60, h = 124.15 }, wardrobe = { x = -1333.82, y = -783.61 } },
            { door = { x = -1343.57, y = -783.90, h = 36.62  }, safe = { x = -1346.53, y = -790.26, h = 217.65 }, wardrobe = { x = -1342.36, y = -785.30 } },
            { door = { x = -1349.65, y = -786.90, h = 306.62 }, safe = { x = -1356.05, y = -789.61, h = 308.13 }, wardrobe = { x = -1349.16, y = -789.39 } },
            { door = { x = -1349.59, y = -783.71, h = 216.62 }, safe = { x = -1352.30, y = -777.40, h = 211.81 }, wardrobe = { x = -1351.56, y = -782.64 } },
            { door = { x = -1343.46, y = -779.16, h = 216.62 }, safe = { x = -1345.43, y = -778.28, h = 306.18 }, wardrobe = { x = -1347.35, y = -774.92 } },
            { door = { x = -1337.53, y = -774.75, h = 216.62 }, safe = { x = -1339.26, y = -773.13, h = 305.78 }, wardrobe = { x = -1337.05, y = -772.47 } },
        },
    },

    -- Add more buildings by copying the block above, e.g.:
    -- mymotel2 = { label = 'Sandy Shores Motel', autoAssign = false, ... },
}
