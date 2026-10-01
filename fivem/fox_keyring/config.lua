Config = {}

-- The keyring item (add it to tgiann-inventory's items, see README)
Config.KeyringItem = 'keyring'

-- The 0r-vehiclekeys key item (0r-vehiclekeys/config/main.lua -> VehicleKeys.itemName)
Config.KeyItem = 'vehiclekeys'

-- New 0r-vehiclekeys keys go straight onto a keyring you're carrying (if it has room)
Config.AutoAddKeys = true

-- Keyring container
Config.Label = 'Keyring'
Config.Slots = 25
Config.MaxWeight = 25000

-- Fallback used when tgiann-inventory has no export to read stash contents.
-- Run `keyringcheck <playerId>` in the server console to see which method your server uses.
Config.StashTable = {
    table = 'tgiann_inventory_stashitems',
    idColumn = 'stash',
    itemsColumn = 'items',
}

-- Players with this ace can run /keyringcheck in game (console can always run it)
Config.AdminAce = 'command'
