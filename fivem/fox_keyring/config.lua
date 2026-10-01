Config = {}

-- Key used to lock/unlock (players can rebind it in Settings > Key Bindings > FiveM)
Config.LockKey = 'L'

-- How far (meters) a player can be from a vehicle to lock/unlock it
Config.LockDistance = 15.0

-- Milliseconds between lock toggles per player (anti-spam)
Config.LockCooldown = 1000

-- How far (meters) two players can be from each other to hand over a key
Config.GiveDistance = 5.0

-- true: /givekey hands over your key (you lose it). false: gives a copy.
Config.TransferOnGive = false

-- Maximum number of keys a single player can hold
Config.MaxKeys = 25

-- Save permanent keys to data/keys.json so they survive restarts
Config.Persist = true
Config.SaveFile = 'data/keys.json'

-- 'auto' uses QBCore when qb-core is running (keyrings are per character / citizenid),
-- otherwise falls back to standalone. Force with 'qb' or 'standalone'.
Config.Framework = 'auto'

-- Standalone only: identifier used to tie keyrings to players ('license', 'fivem', 'discord', ...)
Config.IdentifierType = 'license'

-- Owned vehicles (requires oxmysql). Garages and dealerships ask fox_keyring for a key, and the
-- server only hands out a permanent key when the plate is really owned by that player (or their job).
Config.OwnedVehicles = {
    enabled = true,
    table = 'player_vehicles',
    ownerColumn = 'citizenid',  -- ESX: 'owner'
    jobColumn = 'job',          -- lunar_garage society vehicles; set to nil if your table has no job column
    modelColumn = 'vehicle',    -- used to label the key, set to nil to label keys by plate
}

-- Handle the events other QBCore scripts use to give keys (qb-vehicleshop, qb-policejob, ...):
-- vehiclekeys:client:SetOwner and qb-vehiclekeys:server:AcquireVehicleKeys.
-- Owned plates get a permanent key. Unowned plates (job cars, rentals) get a temporary key, but only
-- when the player is standing right next to a vehicle with that plate.
Config.QBCompat = true
Config.TempKeyDistance = 10.0

-- Stop players from starting a vehicle's engine without its key
Config.RequireKeyForEngine = true

-- Vehicle classes that never need a key (13 = cycles, 14 = boats, 15 = helicopters, 16 = planes, 21 = trains)
Config.EngineExemptClasses = {
    [13] = true,
    [21] = true,
}

-- Ace permission for the /addkey admin command (add_ace group.admin command.addkey allow)
Config.AdminCommand = 'addkey'

-- Play the key fob animation and prop when locking
Config.UseKeyFobAnimation = true
