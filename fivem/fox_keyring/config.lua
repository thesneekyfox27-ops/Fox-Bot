Config = {}

-- The keyring item (add it to tgiann-inventory's items, see README)
Config.KeyringItem = 'keyring'

-- The 0r-vehiclekeys key item (0r-vehiclekeys/config/main.lua -> VehicleKeys.itemName)
Config.KeyItem = 'vehiclekeys'

-- New 0r-vehiclekeys keys go straight onto a keyring you're carrying (if it has room)
Config.AutoAddKeys = true

-- Only keys for your own cars go on the keyring: a row in this table with your citizenid and no job.
-- Job cars, lunar_garage society cars and stolen/hotwired cars always go to your pockets so they can be
-- taken back when the car is returned. Set jobColumn = nil if your table has no job column.
Config.PersonalVehicles = {
    table = 'player_vehicles',
    ownerColumn = 'citizenid',
    jobColumn = 'job',
}

-- Number of slots on a keyring. Must match `slots` in the keyring's entry in
-- tgiann-inventory/configs/configItemStash.lua (see README).
Config.Slots = 25

-- Server restart: every owned car gets a new key_id (0r-vehiclekeys' key code), so every old key
-- stops working wherever it is - pockets, keyrings, house stashes, trunks, the ground.
-- Stops people hoarding stolen keys. Owners get a new key from the garage or the locksmith.
Config.RotateKeysOnRestart = true

-- Server restart: every car key (Config.KeyItem only - business/house keys are other items and stay)
-- is taken from a player's pockets and keyrings the first time they load in after a restart.
-- Owners get keys back by taking the car out of the garage, or from the locksmith.
Config.WipeKeysOnRestart = true
Config.WipeDelay = 5000 -- ms after the character loads, so tgiann has their inventory ready
Config.WipeMessage = 'Your car keys were reset by the city. Take your car out of the garage or visit the locksmith.'

-- Robbing: search a player's keyring when they're dead, cuffed or have their hands up.
-- Adds a "Search keyring" ox_target option on players, plus a command for the closest player.
Config.Search = {
    enabled = true,
    distance = 2.5,
    command = 'searchkeyring',
    -- Hands-up animations to accept ({ dict, anim }). Add yours if your hands-up script uses another.
    handsUpAnims = {
        { 'missminuniversity_bs', 'hands_up_base' },
        { 'random@mugging3', 'handsup_standing_base' },
        { 'random@arrests@busted', 'idle_a' },
    },
}

-- Fallback used when tgiann-inventory has no export to read stash contents.
-- Run `keyringcheck <playerId>` in the server console to see which method your server uses.
Config.StashTable = {
    table = 'tgiann_inventory_stashitems',
    idColumn = 'stash',
    itemsColumn = 'items',
}

-- Players with this ace can run /keyringcheck in game (console can always run it)
Config.AdminAce = 'command'
