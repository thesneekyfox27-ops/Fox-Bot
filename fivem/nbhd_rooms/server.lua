local QBCore = exports['qb-core']:GetCoreObject()

-- ============================================================
--  NBHD ROOMS - multi-building room system (server)
--  All behavior is driven by Config.Buildings (config.lua)
-- ============================================================

-- ensure our own rooms table exists (no tk_housing dependency)
CreateThread(function()
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS nbhd_rooms (
            id INT AUTO_INCREMENT PRIMARY KEY,
            name VARCHAR(128) NOT NULL UNIQUE,
            owner VARCHAR(64) NOT NULL,
            rent INT DEFAULT 0,
            created INT DEFAULT 0,
            INDEX (owner)
        )
    ]])
end)

local function roomName(b, n)
    return b.label .. ' Room ' .. n
end

local function roomPattern(b)
    return b.label .. ' Room %'
end

local function totalRooms(b)
    return b.floors * b.roomsPerFloor
end

local function buildDoorsJson(b, unit, floor)
    local d = b.rooms[unit].door
    local z = b.doorBaseZ + (floor - 1) * b.floorHeight
    return json.encode({
        house = {
            { coords = { x = d.x, y = d.y, z = z, w = d.h }, exitIndex = 1, label = 'Front Door' }
        }
    })
end

-- ============================================================
--  ROOM ASSIGNMENT
-- ============================================================

local function getRandomRoom(bKey, b)
    local available = {}
    for floor = 1, b.floors do
        for unit = 1, b.roomsPerFloor do
            local n = (floor - 1) * b.roomsPerFloor + unit
            local name = roomName(b, n)
            local existing = MySQL.Sync.fetchScalar(
                'SELECT id FROM nbhd_rooms WHERE name = ? LIMIT 1', { name }
            )
            if not existing then
                available[#available + 1] = { floor = floor, unit = unit, number = n, name = name }
            end
        end
    end
    if #available == 0 then return nil end
    return available[math.random(1, #available)]
end

local function holdsRoomIn(citizenid, b)
    return MySQL.Sync.fetchScalar(
        'SELECT name FROM nbhd_rooms WHERE owner = ? AND name LIKE ? LIMIT 1',
        { citizenid, roomPattern(b) }
    )
end

local function ownsAnyProperty(citizenid)
    return MySQL.Sync.fetchScalar(
        'SELECT id FROM nbhd_rooms WHERE owner = ? LIMIT 1', { citizenid }
    ) ~= nil
end

local function assignRoom(src, citizenid, bKey)
    local b = Config.Buildings[bKey]
    if not b then return false end

    if holdsRoomIn(citizenid, b) then
        return false, 'has_room'
    end
    if b.skipIfOwnsAnyProperty and ownsAnyProperty(citizenid) then
        return false, 'has_home'
    end

    local pick = getRandomRoom(bKey, b)
    if not pick then
        TriggerClientEvent('ox_lib:notify', src, {
            title = b.label, description = 'No rooms available right now.',
            type = 'error', icon = 'bed', position = 'center-right'
        })
        return false, 'full'
    end

    MySQL.Sync.execute(
        'INSERT INTO nbhd_rooms (name, owner, rent, created) VALUES (?, ?, ?, ?)',
        { pick.name, citizenid, b.rent or 0, os.time() }
    )
    TriggerClientEvent('ox_lib:notify', src, {
        title = b.label,
        description = 'You have been assigned **' .. pick.name .. '** — Floor ' .. pick.floor .. '.',
        type = 'success', icon = 'key', position = 'center-right', duration = 8000
    })
    TriggerClientEvent('nbhd_rooms:client:setRoom', src, bKey, pick.number)

    print(('[nbhd_rooms] %s assigned %s'):format(citizenid, pick.name))
    return true
end

-- ============================================================
--  DOOR LOCKS (server-authoritative)
-- ============================================================

local doorLocked = {} -- [bKey][n] = bool
for bKey, b in pairs(Config.Buildings) do
    doorLocked[bKey] = {}
    for i = 1, totalRooms(b) do doorLocked[bKey][i] = true end
end

local function getRoomOwner(b, n)
    return MySQL.Sync.fetchScalar(
        'SELECT owner FROM nbhd_rooms WHERE name = ? LIMIT 1', { roomName(b, n) }
    )
end

local function lockRoomOf(citizenid, bKey, b)
    local row = holdsRoomIn(citizenid, b)
    if row then
        local n = tonumber(row:match('(%d+)$'))
        if n then
            doorLocked[bKey][n] = true
            TriggerClientEvent('nbhd_rooms:client:doorState', -1, bKey, n, true)
        end
    end
end

RegisterNetEvent('nbhd_rooms:server:requestStates', function()
    local src = source
    TriggerClientEvent('nbhd_rooms:client:allDoorStates', src, doorLocked)

    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    local citizenid = Player.PlayerData.citizenid

    for bKey, b in pairs(Config.Buildings) do
        local row = holdsRoomIn(citizenid, b)
        if row then
            TriggerClientEvent('nbhd_rooms:client:setRoom', src, bKey, tonumber(row:match('(%d+)$')))
        end
    end
end)

RegisterNetEvent('nbhd_rooms:server:toggleDoor', function(bKey, n)
    local src = source
    local b = Config.Buildings[bKey]
    local Player = QBCore.Functions.GetPlayer(src)
    if not b or not Player then return end

    n = tonumber(n)
    if not n or n < 1 or n > totalRooms(b) then return end
    if getRoomOwner(b, n) ~= Player.PlayerData.citizenid then return end

    doorLocked[bKey][n] = not doorLocked[bKey][n]
    TriggerClientEvent('nbhd_rooms:client:doorState', -1, bKey, n, doorLocked[bKey][n])
end)

-- ============================================================
--  SESSION RELEASE + AUTO ASSIGN
-- ============================================================

local sessionCitizen = {}

local function releaseSessionRooms(citizenid)
    if not citizenid then return end
    for bKey, b in pairs(Config.Buildings) do
        if b.sessionBased then
            lockRoomOf(citizenid, bKey, b)
            local affected = MySQL.Sync.execute(
                'DELETE FROM nbhd_rooms WHERE owner = ? AND name LIKE ?',
                { citizenid, roomPattern(b) }
            )
            if affected and affected > 0 then
                print(('[nbhd_rooms] Released %s room for %s'):format(b.label, citizenid))
            end
        end
    end
end

AddEventHandler('QBCore:Server:PlayerLoaded', function(Player)
    local src       = Player.PlayerData.source
    local citizenid = Player.PlayerData.citizenid
    sessionCitizen[src] = citizenid
    SetTimeout(3000, function()
        releaseSessionRooms(citizenid)
        for bKey, b in pairs(Config.Buildings) do
            if b.autoAssign then
                assignRoom(src, citizenid, bKey)
            end
        end
    end)
end)

AddEventHandler('playerDropped', function()
    local src = source
    local citizenid = sessionCitizen[src]
    if not citizenid then
        local Player = QBCore.Functions.GetPlayer(src)
        if Player then citizenid = Player.PlayerData.citizenid end
    end
    releaseSessionRooms(citizenid)
    sessionCitizen[src] = nil
end)

RegisterNetEvent('QBCore:Server:OnPlayerUnload', function(src)
    src = src or source
    local citizenid = sessionCitizen[src]
    if not citizenid then
        local Player = QBCore.Functions.GetPlayer(src)
        if Player then citizenid = Player.PlayerData.citizenid end
    end
    releaseSessionRooms(citizenid)
    sessionCitizen[src] = nil
end)

-- ============================================================
--  RECEPTION CHECK / CLAIM
-- ============================================================

RegisterNetEvent('nbhd_rooms:server:checkRoom', function(bKey)
    local src = source
    local b = Config.Buildings[bKey]
    local Player = QBCore.Functions.GetPlayer(src)
    if not b or not Player then return end

    local citizenid = Player.PlayerData.citizenid
    local row = holdsRoomIn(citizenid, b)

    if not row then
        local ok, reason = assignRoom(src, citizenid, bKey)
        if not ok and reason == 'has_home' then
            TriggerClientEvent('ox_lib:notify', src, {
                title = b.label, description = 'You already have a home elsewhere.',
                type = 'inform', icon = 'house', position = 'center-right'
            })
        end
        return
    end

    local n = tonumber(row:match('(%d+)$'))
    local floor = math.ceil(n / b.roomsPerFloor)
    TriggerClientEvent('ox_lib:notify', src, {
        title = b.label,
        description = 'Your room: **' .. row .. '** — Floor ' .. floor,
        type = 'inform', icon = 'key', position = 'center-right', duration = 7000
    })
    TriggerClientEvent('nbhd_rooms:client:setRoom', src, bKey, n)
end)

-- ============================================================
--  PERSONAL LOCKER (per building, citizenid-keyed)
-- ============================================================

RegisterNetEvent('nbhd_rooms:server:openLocker', function(bKey)
    local src = source
    local b = Config.Buildings[bKey]
    local Player = QBCore.Functions.GetPlayer(src)
    if not b or not b.locker or not Player then return end

    local citizenid = Player.PlayerData.citizenid
    if not holdsRoomIn(citizenid, b) then return end

    local stashId = bKey .. '_locker_' .. citizenid
    TriggerClientEvent('nbhd_rooms:client:doOpenLocker', src, stashId, b.locker.slots, b.locker.weight)
end)
