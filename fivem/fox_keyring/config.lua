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

-- Identifier used to tie keyrings to players ('license', 'fivem', 'discord', ...)
Config.IdentifierType = 'license'

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
