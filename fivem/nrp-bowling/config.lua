Config = {}

Config.AlleyName = 'Neighborhood Lanes'

-- ── Prices (the neon price sheet at the desk) ──────────────────
Config.Account = 'cash'    -- default payment picked on the menu: 'cash' or 'bank'
-- Payment options players choose from (price sheet + invite card).
-- Remove one to force the other. 'bank' = paying by card.
Config.PayMethods = {
    { id = 'cash', label = 'Cash' },
    { id = 'bank', label = 'Card' },
}

-- Single tickets: every player pays their own (invited friends pay when they accept)
Config.Tickets = {
    { id = 'adult', label = 'Adult', sub = '', prices = { [1] = 9, [2] = 17 } },
}

-- Game deals: based on 2 games, the host pays for the whole group.
-- You have to invite enough friends to fill the deal before you can buy it.
Config.GameDeals = {
    { players = 2, price = 34 },
    { players = 3, price = 51 },
    { players = 4, price = 68 },
    { players = 5, price = 85 },
    { players = 6, price = 102 },
}

-- Family deals: turned off (adult tickets only). Add entries to bring them back, e.g.
-- { players = 4, label = '2 adults + 2 juniors', price = 34 },
Config.FamilyDeals = {}

Config.MaxPlayers  = 6     -- per lane
Config.Frames      = 10    -- frames per game
Config.InviteRange   = 12.0   -- metres: who shows up in the invite list
Config.InviteSeconds = 45     -- how long an invite stays open
Config.BookingSeconds = 90    -- pick a lane within this time or you're refunded

-- ── Staff ped (sells games) ───────────────────────────────────
-- Stand where you want her, type /bowlcoords, paste the vector4 here.
Config.Staff = {
    model    = 'a_f_y_hipster_01',
    coords   = vector4(-142.55, -251.95, 43.2, 250.0),
    scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
    spawnDistance = 70.0,
}
Config.Target = 'auto'     -- 'auto' (ox_target, then qb-target) or 'off' (press E)

-- ── Timers ─────────────────────────────────────────────────────
Config.TurnTimeout  = 120  -- seconds to bowl before you're removed (AFK)
Config.LeaveDistance = 45.0 -- walk this far from your lane and you leave the game

-- ── Animations ─────────────────────────────────────────────────
-- GTA has no real bowling animation, so every bowling script borrows one.
--   'original' = what loaf_bowling used: ball in the right hand at your side (default)
--   'bowling'  = two-hand hold at the waist + low underhand swing
-- Or put any dict/anim of your own (e.g. a custom bowling animation) in Config.Anims.
Config.AnimPreset = 'original'

local ANIM_PRESETS = {
    bowling = {
        stance  = { dict = 'anim@heists@box_carry@', anim = 'idle', flag = 1, ballBone = 0, ballOffset = vector3(0.0, 0.40, 0.08) },
        release = { dict = 'anim@heists@narcotics@trash', anim = 'throw_b', duration = 1500, releaseAt = 620 },
    },
    original = {
        stance  = { dict = 'weapons@projectile@', anim = 'aimlive_l', flag = 17, ballBone = 57005, ballOffset = vector3(0.09, 0.03, -0.02), ballRot = vector3(-78.0, 13.0, 28.0) },
        release = { dict = 'weapons@projectile@', anim = 'throw_l_fb_stand', duration = 900, releaseAt = 150 },
        carry   = false,   -- walk normally, ball in your right hand at your side
    },
}
Config.Anims = ANIM_PRESETS[Config.AnimPreset] or ANIM_PRESETS.original

-- Grabbing the ball off the ball return, then carrying it to the circle
-- (flag 49 = upper body only + loop, so you can walk while holding it;
--  carry = false walks normally with the ball in hand)
Config.Anims.pickup = Config.Anims.pickup or { dict = 'anim@mp_snowball', anim = 'pickup_snowball', duration = 1100, grabAt = 550 }
if Config.Anims.carry == nil then Config.Anims.carry = { dict = 'anim@heists@box_carry@', anim = 'idle', flag = 49 } end

-- ── Ball physics ───────────────────────────────────────────────
Config.Ball = {
    minSpeed   = 6.5,   -- m/s at 0% power
    maxSpeed   = 12.5,  -- m/s at 100% power
    maxHook    = 0.9,   -- sideways m/s² at full spin (kicks in after 40% of the lane)
    maxAim     = 4.5,   -- degrees left/right the direction arrow swings
    maxOffset  = 0.42,  -- metres left/right the position marker slides
    -- skill input: how fast each indicator swings (sweeps per second, higher = harder)
    positionSpeed  = 0.55,
    directionSpeed = 0.70,
    spinSpeed      = 0.65,
    meterSpeed     = 0.85,
    sweetSpot  = { 0.80, 0.94 },  -- release in this band = perfect accuracy
    maxError   = 2.2,   -- degrees of random error at the worst release
}

-- Lane geometry (metres). Lane is 1.05 m wide; gutters run outside that.
Config.LaneHalfWidth = 0.53
Config.GutterOffset  = 0.68

-- ── Places ─────────────────────────────────────────────────────
Config.Desk = vector3(-141.83, -252.71, 44.0)   -- ball rack (blip + decorative balls)

Config.Blip = { sprite = 103, color = 27, scale = 0.75 }

-- ── Sounds ──────────────────────────────────────────────────────
-- Files live in html/sounds/. Drop in your own mp3 with the same name to swap one.
-- Lane sounds are heard by everyone near that lane (quieter further away).
Config.Sounds = {
    volume       = 1.0,     -- master volume for everything below (0.0 - 1.0)
    hearDistance = 25.0,    -- lane sounds fade out to nothing at this distance
    release = { file = 'release.mp3', volume = 0.7 },   -- ball leaves the hand
    pins    = { file = 'pins.mp3',    volume = 0.8 },   -- ball hits the pins
    spare   = { file = 'spare.mp3',   volume = 0.7 },
    strike  = { file = 'strike.mp3',  volume = 0.8 },   -- add html/sounds/strike.mp3 (silent until you do)
    -- background music inside the building: plays the files in order and loops
    -- back round (1, 2, 1, 2 ...), fading in/out as you walk in or out
    ambient = {
        enabled = true,
        files   = { 'ambient1.mp3', 'ambient2.mp3' },
        volume  = 0.25,
        center  = vector3(-157.7, -263.9, 44.0),   -- middle of the alley
        radius  = 26.0,                             -- you hear it inside this distance
        height  = 6.0,                              -- ...and within this many metres up/down
    },
}

-- Decorative balls on the rack (only spawned locally when you're nearby)
Config.RackBalls = {
    vector3(-141.0396, -252.3092, 43.82756), vector3(-141.1883, -252.7568, 43.82756),
    vector3(-141.2772, -253.1083, 43.82756), vector3(-141.4393, -253.4855, 43.82756),
    vector3(-141.4393, -253.4855, 43.5381),  vector3(-141.2557, -253.0987, 43.5381),
    vector3(-141.1771, -252.7275, 43.5381),  vector3(-141.0329, -252.2919, 43.5381),
    vector3(-141.0329, -252.2919, 43.22288), vector3(-141.1889, -252.734, 43.22288),
    vector3(-141.33, -253.1166, 43.22288),   vector3(-141.4617, -253.4859, 43.22288),
}

-- Ball return (where you grab your ball each turn). Best way: stand at a
-- lane's ball return in game and type /bowlreturn [lane] (admin) - it's saved
-- to returns.json. Or add `ret = vector3(x, y, floorZ)` to a lane below.
-- Lanes with neither use a guess: behind the stand spot, between the lane pair.
Config.ReturnBack = 2.4    -- guess: metres behind the stand spot
Config.ReturnSide = 1.5    -- guess: metres sideways toward the paired lane

-- One entry per lane: where you stand to bowl, and the 10 pin spots
-- (first pin = head pin). Taken from the original script / Breze MLO.
Config.Lanes = {
    { approach = vector4(-146.25, -260.86, 43.16, 158.0), pins = {
        vector3(-152.1756, -278.0237, 43.24929), vector3(-152.1174, -278.2685, 43.24929), vector3(-152.3687, -278.1628, 43.24929),
        vector3(-152.3105, -278.3871, 43.24929), vector3(-152.558, -278.2952, 43.24929),  vector3(-152.0571, -278.479, 43.24929),
        vector3(-151.9918, -278.7413, 43.24929), vector3(-152.2504, -278.6514, 43.24929), vector3(-152.5192, -278.565, 43.24929),
        vector3(-152.7647, -278.4796, 43.24929) } },
    { approach = vector4(-149.21, -259.63, 43.16, 158.0), pins = {
        vector3(-155.1486, -276.8353, 43.24929), vector3(-155.0905, -277.0801, 43.24929), vector3(-155.3417, -276.9744, 43.24929),
        vector3(-155.2835, -277.1987, 43.24929), vector3(-155.531, -277.1068, 43.24929),  vector3(-155.0301, -277.2906, 43.24929),
        vector3(-154.9648, -277.5529, 43.24929), vector3(-155.2234, -277.463, 43.24929),  vector3(-155.4922, -277.3766, 43.24929),
        vector3(-155.7377, -277.2912, 43.24929) } },
    { approach = vector4(-151.88, -258.71, 43.16, 158.0), pins = {
        vector3(-157.7556, -275.7554, 43.24929), vector3(-157.6975, -276.0002, 43.24929), vector3(-157.9488, -275.8944, 43.24929),
        vector3(-157.8906, -276.1187, 43.24929), vector3(-158.138, -276.0268, 43.24929),  vector3(-157.6372, -276.2107, 43.24929),
        vector3(-157.5719, -276.473, 43.24929),  vector3(-157.8305, -276.3831, 43.24929), vector3(-158.0992, -276.2967, 43.24929),
        vector3(-158.3448, -276.2113, 43.24929) } },
    { approach = vector4(-154.84, -257.7, 43.16, 158.0), pins = {
        vector3(-160.5427, -274.0963, 43.24881), vector3(-160.4901, -274.4021, 43.24881), vector3(-160.7729, -274.2939, 43.24881),
        vector3(-160.9759, -274.4997, 43.24881), vector3(-160.7207, -274.5862, 43.24881), vector3(-160.5059, -274.6621, 43.24881),
        vector3(-160.4403, -274.8927, 43.24881), vector3(-160.6632, -274.8186, 43.24881), vector3(-160.895, -274.7328, 43.24881),
        vector3(-161.1401, -274.643, 43.24881) } },
    { approach = vector4(-158.68, -256.34, 43.16, 158.0), pins = {
        vector3(-164.3882, -272.7944, 43.24929), vector3(-164.3301, -273.0392, 43.24929), vector3(-164.5814, -272.9335, 43.24929),
        vector3(-164.5231, -273.1578, 43.24929), vector3(-164.7706, -273.0659, 43.24929), vector3(-164.2697, -273.2498, 43.24929),
        vector3(-164.2045, -273.5121, 43.24929), vector3(-164.463, -273.4221, 43.24929),  vector3(-164.7318, -273.3358, 43.24929),
        vector3(-164.9773, -273.2504, 43.24929) } },
    { approach = vector4(-161.6, -255.3, 43.16, 158.0), pins = {
        vector3(-167.3406, -271.7319, 43.24929), vector3(-167.2825, -271.9767, 43.24929), vector3(-167.5338, -271.8709, 43.24929),
        vector3(-167.4755, -272.0952, 43.24929), vector3(-167.723, -272.0033, 43.24929),  vector3(-167.2221, -272.1872, 43.24929),
        vector3(-167.1569, -272.4495, 43.24929), vector3(-167.4154, -272.3596, 43.24929), vector3(-167.6842, -272.2732, 43.24929),
        vector3(-167.9297, -272.1878, 43.24929) } },
    { approach = vector4(-164.28, -254.32, 43.16, 158.0), pins = {
        vector3(-169.938, -270.6638, 43.24929),  vector3(-169.8799, -270.9086, 43.24929), vector3(-170.1311, -270.8029, 43.24929),
        vector3(-170.0729, -271.0272, 43.24929), vector3(-170.3204, -270.9353, 43.24929), vector3(-169.8195, -271.1191, 43.24929),
        vector3(-169.7543, -271.3814, 43.24929), vector3(-170.0128, -271.2915, 43.24929), vector3(-170.2816, -271.2051, 43.24929),
        vector3(-170.5271, -271.1198, 43.24929) } },
    { approach = vector4(-167.2, -253.3, 43.16, 158.0), pins = {
        vector3(-172.7789, -269.1845, 43.24929), vector3(-172.7208, -269.4294, 43.24929), vector3(-172.9721, -269.3236, 43.24929),
        vector3(-172.9139, -269.5479, 43.24929), vector3(-173.1613, -269.456, 43.24929),  vector3(-172.6605, -269.6399, 43.24929),
        vector3(-172.5952, -269.9022, 43.24929), vector3(-172.8538, -269.8123, 43.24929), vector3(-173.1225, -269.7259, 43.24929),
        vector3(-173.3681, -269.6405, 43.24929) } },
}
