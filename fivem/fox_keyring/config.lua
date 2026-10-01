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

-- Fallback used when tgiann-inventory has no export to read stash contents.
-- Run `keyringcheck <playerId>` in the server console to see which method your server uses.
Config.StashTable = {
    table = 'tgiann_inventory_stashitems',
    idColumn = 'stash',
    itemsColumn = 'items',
}

-- Players with this ace can run /keyringcheck in game (console can always run it)
Config.AdminAce = 'command'
