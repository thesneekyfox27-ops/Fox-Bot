Config = {}

Config.Enabled = true
Config.Debug   = false

-- How often (ms) a dead/downed player's inventory is checked.
Config.PollMs = 500

-- A "wipe" = this share of your item stacks disappearing in ONE check
-- (half a second). Clear-on-death scripts remove everything at once;
-- a player robbing you takes items one at a time, so that is never
-- treated as a wipe (and is never given back - no duping).
Config.WipeRatio = 0.6   -- 60% of your stacks...
Config.MinStacks = 2     -- ...and at least this many stacks at once

-- Keep watching for this many seconds after you're revived/respawned
-- (hospital respawn scripts usually wipe right at respawn).
Config.WatchAfterReviveSec = 90

-- Items that are allowed to be lost on death (never given back).
-- e.g. dirty money if you want death to cost something:
Config.NeverRestore = {
    -- markedbills = true,
}

-- Inventory resource used to give items back (tgiann-inventory is used through
-- its AddItem export; anything else uses the QBCore player functions).
Config.InventoryResource = 'tgiann-inventory'

-- Optional Discord webhook for a log line every time a wipe is blocked.
-- Leave '' to only print in the server console.
Config.Webhook = ''
