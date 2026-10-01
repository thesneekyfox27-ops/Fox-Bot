local RESOURCE = GetCurrentResourceName()

-- keyrings[identifier][plate] = { label = string, temp = boolean }
local keyrings = {}
local lastLock = {}
local saveQueued = false

local function notify(src, message, kind)
    TriggerClientEvent('fox_keyring:client:notify', src, message, kind or 'inform')
end

local function getIdentifier(src)
    return GetPlayerIdentifierByType(src, Config.IdentifierType)
        or GetPlayerIdentifierByType(src, 'license')
end

local function getKeyring(src)
    local identifier = getIdentifier(src)
    if not identifier then return nil end
    keyrings[identifier] = keyrings[identifier] or {}
    return keyrings[identifier]
end

local function countKeys(ring)
    local count = 0
    for _ in pairs(ring) do count = count + 1 end
    return count
end

---------------------------------------------------------------------
-- Persistence
---------------------------------------------------------------------

local function loadKeys()
    if not Config.Persist then return end
    local raw = LoadResourceFile(RESOURCE, Config.SaveFile)
    if not raw or raw == '' then return end

    local ok, data = pcall(json.decode, raw)
    if not ok or type(data) ~= 'table' then
        print(('^1[%s] Could not read %s, starting with empty keyrings^0'):format(RESOURCE, Config.SaveFile))
        return
    end

    for identifier, plates in pairs(data) do
        keyrings[identifier] = {}
        for plate, label in pairs(plates) do
            keyrings[identifier][plate] = { label = type(label) == 'string' and label or plate, temp = false }
        end
    end
end

local function saveKeys()
    local out = {}
    for identifier, ring in pairs(keyrings) do
        local plates = {}
        local any = false
        for plate, key in pairs(ring) do
            if not key.temp then
                plates[plate] = key.label
                any = true
            end
        end
        if any then out[identifier] = plates end
    end

    if not SaveResourceFile(RESOURCE, Config.SaveFile, json.encode(out), -1) then
        print(('^1[%s] Failed to write %s^0'):format(RESOURCE, Config.SaveFile))
    end
end

local function queueSave()
    if not Config.Persist or saveQueued then return end
    saveQueued = true
    SetTimeout(5000, function()
        saveQueued = false
        saveKeys()
    end)
end

---------------------------------------------------------------------
-- Core API
---------------------------------------------------------------------

local function syncPlayer(src)
    local ring = getKeyring(src)
    if not ring then return end
    local list = {}
    for plate, key in pairs(ring) do
        list[#list + 1] = { plate = plate, label = key.label, temp = key.temp }
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    TriggerClientEvent('fox_keyring:client:sync', src, list)
end

local function hasKey(src, plate)
    plate = Keyring.NormalizePlate(plate)
    local ring = plate and getKeyring(src)
    return ring ~= nil and ring[plate] ~= nil
end

--- Gives a player a key. Returns true on success, or false and a reason.
local function giveKey(src, plate, label, temp)
    plate = Keyring.NormalizePlate(plate)
    if not plate then return false, 'invalid_plate' end

    local ring = getKeyring(src)
    if not ring then return false, 'no_identifier' end

    local existing = ring[plate]
    if existing then
        -- Upgrading a temporary key to a permanent one is allowed.
        if existing.temp and not temp then
            existing.temp = false
            queueSave()
            syncPlayer(src)
        end
        return true
    end

    if countKeys(ring) >= Config.MaxKeys then return false, 'keyring_full' end

    ring[plate] = { label = Keyring.SanitizeLabel(label) or plate, temp = temp == true }
    if not temp then queueSave() end
    syncPlayer(src)
    return true
end

local function removeKey(src, plate)
    plate = Keyring.NormalizePlate(plate)
    local ring = plate and getKeyring(src)
    if not ring or not ring[plate] then return false end

    local wasTemp = ring[plate].temp
    ring[plate] = nil
    if not wasTemp then queueSave() end
    syncPlayer(src)
    return true
end

local function failMessage(reason)
    if reason == 'keyring_full' then return ('Keyring is full (max %d keys).'):format(Config.MaxKeys) end
    if reason == 'invalid_plate' then return 'That plate is not valid.' end
    return 'Could not add the key.'
end

local function findVehicleByPlate(plate)
    for _, veh in ipairs(GetAllVehicles()) do
        if Keyring.NormalizePlate(GetVehicleNumberPlateText(veh)) == plate then
            return veh
        end
    end
end

local function distanceBetween(src, entity)
    return #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(entity))
end

exports('HasKey', hasKey)
exports('GiveKey', function(src, plate, label) return giveKey(src, plate, label, false) end)
exports('GiveTempKey', function(src, plate, label) return giveKey(src, plate, label, true) end)
exports('RemoveKey', removeKey)
exports('GetKeys', function(src)
    local ring = getKeyring(src)
    local plates = {}
    if ring then
        for plate in pairs(ring) do plates[#plates + 1] = plate end
    end
    return plates
end)

---------------------------------------------------------------------
-- Events from clients
---------------------------------------------------------------------

RegisterNetEvent('fox_keyring:server:requestSync', function()
    syncPlayer(source)
end)

RegisterNetEvent('fox_keyring:server:toggleLock', function(netId)
    local src = source
    if type(netId) ~= 'number' then return end

    local now = GetGameTimer()
    if (lastLock[src] or 0) + Config.LockCooldown > now then return end
    lastLock[src] = now

    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) or GetEntityType(veh) ~= 2 then return end

    local plate = Keyring.NormalizePlate(GetVehicleNumberPlateText(veh))
    if not plate or not hasKey(src, plate) then
        return notify(src, "You don't have a key for this vehicle.", 'error')
    end

    -- Small buffer over the client distance to account for movement and latency.
    if distanceBetween(src, veh) > Config.LockDistance + 5.0 then return end

    local locked = GetVehicleDoorLockStatus(veh) >= 2
    SetVehicleDoorsLocked(veh, locked and 1 or 2)

    TriggerClientEvent('fox_keyring:client:lockFx', -1, netId, not locked, src)
    notify(src, locked and ('Unlocked %s'):format(plate) or ('Locked %s'):format(plate), locked and 'success' or 'inform')
end)

RegisterNetEvent('fox_keyring:server:giveKey', function(targetId, plate)
    local src = source
    targetId = tonumber(targetId)
    plate = Keyring.NormalizePlate(plate)

    if not plate or not hasKey(src, plate) then
        return notify(src, "You don't have that key.", 'error')
    end
    if not targetId or targetId == src or not GetPlayerName(targetId) then
        return notify(src, 'That player is not available.', 'error')
    end
    if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(GetPlayerPed(targetId))) > Config.GiveDistance then
        return notify(src, 'You need to be closer to that player.', 'error')
    end

    local ring = getKeyring(src)
    local key = ring[plate]
    local ok, reason = giveKey(targetId, plate, key.label, key.temp)
    if not ok then
        return notify(src, reason == 'keyring_full' and "Their keyring is full." or failMessage(reason), 'error')
    end

    if Config.TransferOnGive then removeKey(src, plate) end

    notify(src, ('Gave key for %s to %s'):format(plate, GetPlayerName(targetId)), 'success')
    notify(targetId, ('%s gave you a key for %s'):format(GetPlayerName(src), plate), 'success')
end)

RegisterNetEvent('fox_keyring:server:removeKey', function(plate)
    local src = source
    if removeKey(src, plate) then
        notify(src, ('Removed key for %s'):format(Keyring.NormalizePlate(plate)), 'inform')
    else
        notify(src, "You don't have that key.", 'error')
    end
end)

RegisterNetEvent('fox_keyring:server:labelKey', function(plate, label)
    local src = source
    plate = Keyring.NormalizePlate(plate)
    label = Keyring.SanitizeLabel(label)
    local ring = getKeyring(src)
    if not plate or not ring or not ring[plate] then
        return notify(src, "You don't have that key.", 'error')
    end

    ring[plate].label = label or plate
    if not ring[plate].temp then queueSave() end
    syncPlayer(src)
    notify(src, ('Renamed %s to "%s"'):format(plate, ring[plate].label), 'success')
end)

RegisterNetEvent('fox_keyring:server:locate', function(plate)
    local src = source
    plate = Keyring.NormalizePlate(plate)
    if not plate or not hasKey(src, plate) then
        return notify(src, "You don't have that key.", 'error')
    end

    local veh = findVehicleByPlate(plate)
    if not veh then
        return notify(src, ('%s is not out right now.'):format(plate), 'error')
    end

    local coords = GetEntityCoords(veh)
    TriggerClientEvent('fox_keyring:client:setWaypoint', src, coords.x, coords.y)
    notify(src, ('Waypoint set to %s'):format(plate), 'success')
end)

---------------------------------------------------------------------
-- Admin command: /addkey [playerId] - key for the vehicle you're in
---------------------------------------------------------------------

RegisterCommand(Config.AdminCommand, function(src, args)
    if src == 0 then
        return print(('[%s] /%s must be used in-game while sitting in a vehicle'):format(RESOURCE, Config.AdminCommand))
    end

    local veh = GetVehiclePedIsIn(GetPlayerPed(src), false)
    if veh == 0 then return notify(src, 'Get in a vehicle first.', 'error') end

    local target = tonumber(args[1]) or src
    if not GetPlayerName(target) then return notify(src, 'That player is not online.', 'error') end

    local plate = GetVehicleNumberPlateText(veh)
    local ok, reason = giveKey(target, plate)
    if not ok then return notify(src, failMessage(reason), 'error') end

    notify(src, ('Gave key for %s to %s'):format(Keyring.NormalizePlate(plate), GetPlayerName(target)), 'success')
    if target ~= src then
        notify(target, ('You received a key for %s'):format(Keyring.NormalizePlate(plate)), 'success')
    end
end, true)

---------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------

AddEventHandler('playerDropped', function()
    local src = source
    lastLock[src] = nil

    -- Temporary keys (rentals, jobs, etc.) only last for the session.
    local identifier = getIdentifier(src)
    local ring = identifier and keyrings[identifier]
    if ring then
        for plate, key in pairs(ring) do
            if key.temp then ring[plate] = nil end
        end
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name == RESOURCE and Config.Persist then saveKeys() end
end)

loadKeys()
