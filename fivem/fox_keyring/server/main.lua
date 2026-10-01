local RESOURCE = GetCurrentResourceName()

-- keyrings[identifier][plate] = { label = string, temp = boolean }
local keyrings = {}
local lastLock = {}
local saveQueued = false

local function notify(src, message, kind)
    TriggerClientEvent('fox_keyring:client:notify', src, message, kind or 'inform')
end

local QBCore
local function getQBCore()
    if Config.Framework == 'standalone' then return nil end
    if not QBCore and GetResourceState('qb-core') == 'started' then
        QBCore = exports['qb-core']:GetCoreObject()
    end
    return QBCore
end

local function getQBPlayer(src)
    local qb = getQBCore()
    return qb and qb.Functions.GetPlayer(src)
end

-- Last identifier seen per player, so we can clean up after QBCore has already unloaded them.
local identifierCache = {}

local function getIdentifier(src)
    local identifier
    if getQBCore() then
        -- Keyrings are per character. No character loaded = no keyring.
        local player = getQBPlayer(src)
        identifier = player and player.PlayerData.citizenid
    else
        identifier = GetPlayerIdentifierByType(src, Config.IdentifierType)
            or GetPlayerIdentifierByType(src, 'license')
    end
    if identifier then identifierCache[src] = identifier end
    return identifier
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

---------------------------------------------------------------------
-- Owned vehicles (oxmysql)
---------------------------------------------------------------------

local function dbSingle(query, params)
    if GetResourceState('oxmysql') ~= 'started' then return nil end
    local p = promise.new()
    exports.oxmysql:single(query, params, function(row) p:resolve(row or false) end)
    SetTimeout(5000, function()
        if p.state == 0 then p:resolve(false) end
    end)
    return Citizen.Await(p) or nil
end

--- Returns the vehicle row when the plate belongs to this player (or their job), otherwise nil.
local function getOwnedVehicle(src, plate)
    local cfg = Config.OwnedVehicles
    if not cfg or not cfg.enabled then return nil end

    local owner = getIdentifier(src)
    if not owner then return nil end

    local where = ('`%s` = ?'):format(cfg.ownerColumn)
    local params = { plate, owner }

    local player = getQBPlayer(src)
    local job = player and player.PlayerData.job and player.PlayerData.job.name
    if cfg.jobColumn and job then
        where = ('%s OR `%s` = ?'):format(where, cfg.jobColumn)
        params[#params + 1] = job
    end

    local columns = cfg.modelColumn and ('plate, `%s` AS model'):format(cfg.modelColumn) or 'plate'
    local query = ('SELECT %s FROM `%s` WHERE UPPER(TRIM(plate)) = ? AND (%s) LIMIT 1'):format(columns, cfg.table, where)

    local ok, row = pcall(dbSingle, query, params)
    if not ok then
        print(('^1[%s] Owned vehicle lookup failed: %s^0'):format(RESOURCE, tostring(row)))
        return nil
    end
    return row
end

local function vehicleLabel(row, plate)
    local model = row and row.model
    if type(model) ~= 'string' or model == '' then return plate end

    local qb = getQBCore()
    local shared = qb and qb.Shared.Vehicles and qb.Shared.Vehicles[model]
    if shared and shared.name then
        return shared.brand and ('%s %s'):format(shared.brand, shared.name) or shared.name
    end
    return model:sub(1, 1):upper() .. model:sub(2)
end

--- Removes a plate from every keyring, online or offline. Use it when a vehicle is sold.
local function resetKeys(plate)
    plate = Keyring.NormalizePlate(plate)
    if not plate then return 0 end

    local affected, removed = {}, 0
    for identifier, ring in pairs(keyrings) do
        if ring[plate] then
            local wasTemp = ring[plate].temp
            ring[plate] = nil
            if not wasTemp then queueSave() end
            affected[identifier] = true
            removed = removed + 1
        end
    end

    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        if affected[identifierCache[src] or ''] then syncPlayer(src) end
    end
    return removed
end

exports('ResetKeys', resetKeys)
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

-- A garage/dealership/job asks for a key. Owned plates get a permanent key; anything else only
-- gets a temporary key when the player is standing next to that vehicle (job cars, rentals).
local lastClaim = {}
local function claimKey(src, plate)
    plate = Keyring.NormalizePlate(plate)
    if not plate or hasKey(src, plate) then return end

    local now = GetGameTimer()
    if (lastClaim[src] or 0) + 250 > now then return end
    lastClaim[src] = now

    local row = getOwnedVehicle(src, plate)
    if row then
        local ok, reason = giveKey(src, plate, vehicleLabel(row, plate), false)
        if ok then
            notify(src, ('You received the keys to %s'):format(plate), 'success')
        else
            notify(src, failMessage(reason), 'error')
        end
        return
    end

    if not Config.QBCompat then return end

    local veh = findVehicleByPlate(plate)
    if veh and distanceBetween(src, veh) <= Config.TempKeyDistance then
        local ok, reason = giveKey(src, plate, nil, true)
        if ok then
            notify(src, ('You received temporary keys to %s'):format(plate), 'success')
        else
            notify(src, failMessage(reason), 'error')
        end
    end
end

exports('ClaimKey', claimKey)

RegisterNetEvent('fox_keyring:server:claimKey', function(plate)
    claimKey(source, plate)
end)

if Config.QBCompat then
    RegisterNetEvent('qb-vehiclekeys:server:AcquireVehicleKeys', function(plate)
        claimKey(source, plate)
    end)
end

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

-- Temporary keys (rentals, jobs, etc.) only last for the session / character.
local function clearTempKeys(src)
    local identifier = identifierCache[src]
    local ring = identifier and keyrings[identifier]
    if not ring then return end
    for plate, key in pairs(ring) do
        if key.temp then ring[plate] = nil end
    end
end

AddEventHandler('playerDropped', function()
    local src = source
    clearTempKeys(src)
    lastLock[src] = nil
    lastClaim[src] = nil
    identifierCache[src] = nil
end)

-- QBCore: load the character's keyring on spawn, clear it when they go back to character select.
AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    local src = player and player.PlayerData and player.PlayerData.source
    if src then syncPlayer(src) end
end)

AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
    clearTempKeys(src)
    identifierCache[src] = nil
    TriggerClientEvent('fox_keyring:client:sync', src, {})
end)

AddEventHandler('onResourceStop', function(name)
    if name == RESOURCE and Config.Persist then saveKeys() end
end)

loadKeys()
