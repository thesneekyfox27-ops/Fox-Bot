-- Author : Morow
-- Github : https://github.com/Morow73

_G.language = "en" -- change translation: 'en', 'es' or 'fr'
_G.translation = {}

Config = {}
Config.__index = Config

-- Which framework takes the money for the clubs.
--   'auto' : qb-core if it is running, otherwise es_extended, otherwise free
--   'qb'   : QBCore
--   'esx'  : ESX
--   'none' : no framework, playing is free
Config.Framework = 'auto'

-- Tickets shown on the pricing board. Everyone picks their own.
-- Add  jobs = { 'police', 'army' }  to a ticket to limit who can buy it.
Config.tickets = {
    { id = 'adult',  label = 'Adults',            price = 15 },
    { id = 'kid',    label = 'Kids',              price = 12 },
    { id = 'senior', label = 'Seniors/Military',  price = 10 },
}
Config.club_price = 15           -- fallback if a ticket can't be found

-- Scorecard item: at the end of a round you can keep your scorecard.
Config.scorecard_item = {
    enabled   = true,
    name      = 'minigolf_scorecard',   -- must exist in your inventory's item list (see README)
    inventory = 'auto'                  -- 'auto', 'tgiann', 'ox' or 'qb'
}
Config.course_name = 'Portside Minigolf'
Config.pay_account = 'cash'      -- QBCore: 'cash' or 'bank'
Config.allow_bank_fallback = true -- QBCore: if cash is short, take it from the bank

Config.max_group = 4              -- players per group (everyone rents their own clubs)
Config.invite_range = 8.0         -- how close friends must be to get invited
Config.quit_key = 'DELETE'        -- default key to quit early (players can rebind it in Settings > Key Bindings > FiveM)

do
    Config.max_stroke = 10 -- max stroke
    Config.locate_club = vector3(-1734.24, -1135.17, 12.79) -- locate club position
    Config.golf_track = {
        [1] = {
            start = vector3(-1753.32, -1166.31, 12.79), -- fisrt position
            hole = vector3(-1744.81, -1150.25, 11.96), -- hole position
            heading = 240.0 -- heading for first position
        },
        [2] = {
            start = vector3(-1743.29, -1182.03, 12.79),
            hole = vector3(-1738.33, -1164.27, 11.96),
            heading = 244.0
        },
        [3] = {
            start = vector3(-1730.49, -1179.09, 12.79),
            hole = vector3(-1723.03, -1181.61, 11.96),
            heading = 282.0
        },
        [4] = {
            start = vector3(-1713.28, -1167.88, 12.79),
            hole = vector3(-1716.87, -1172.23, 11.96),
            heading = 290.0
        },
        [5] = {
            start = vector3(-1760.85, -1190.26, 12.79),
            hole = vector3(-1769.87, -1177.45, 11.96),
            heading = 227.0
        },
        [6] = {
            start = vector3(-1772.51, -1220.72, 12.79),
            hole = vector3(-1769.00, -1224.46, 11.96),
            heading = 263.0
        },
        [7] = {
            start = vector3(-1746.66, -1192.76, 12.79),
            hole = vector3(-1747.94, -1194.80, 11.96),
            heading = 130.0
        },
        [8] = {
            start = vector3(-1752.10, -1225.11, 12.79),
            hole = vector3(-1748.39, -1217.06, 11.96),
            heading = 245.0
        },
        [9] = {
            start = vector3(-1741.43, -1238.41, 12.79),
            hole = vector3(-1743.40, -1240.87, 11.78),
            heading = 224.0
        },
        [10] = {
            start = vector3(-1729.42, -1210.54, 12.79),
            hole = vector3(-1730.75, -1206.63, 11.80),
            heading = 281.0
        },
        [11] = {
            start = vector3(-1719.01, -1209.35, 12.79),
            hole = vector3(-1704.51, -1192.00, 11.78),
            heading = 222.0
        },
        [12] = {
            start = vector3(-1694.93, -1172.71, 12.79),
            hole = vector3(-1690.35, -1184.38, 11.96),
            heading = 250.0
        }
    }
end
