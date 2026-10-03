local QBCore = exports['qb-core']:GetCoreObject()

-- ============================================================
--  NBHD ROOMS - multi-building room system (server)
--  All behavior is driven by Config.Buildings (config.lua)
-- ============================================================

local homeTables = {}   -- Config.HomeTables entries that actually exist

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS nbhd_rooms (
            id INT AUTO_INCREMENT PRIMARY KEY,
            name VARCHAR(128) NOT NULL UNIQUE,
            owner VARCHAR(64) NOT NULL,
            rent INT DEFAULT 0,
            created INT DEFAULT 0,
            INDEX (owner)
        )
    ]])
    -- the room each character had last, so they get it back next time
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS nbhd_rooms_last (
            citizenid VARCHAR(64) NOT NULL,
            building VARCHAR(64) NOT NULL,
            room INT NOT NULL,
            PRIMARY KEY (citizenid, building)
        )
    ]])

    for _, t in ipairs(Config.HomeTables or {}) do
        local exists = MySQL.scalar.await([[
            SELECT COUNT(*) FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?
        ]], { t.table, t.column })
        if exists and exists > 0 then homeTables[#homeTables + 1] = t end
    end
end)

-- ============================================================
--  HELPERS
-- ============================================================

local function roomName(b, n)      return b.label .. ' Room ' .. n end
local function roomPattern(b)      return b.label .. ' Room %' end
local function totalRooms(b)       return b.floors * b.roomsPerFloor end
local function floorIndex(b, n)    return math.ceil(n / b.roomsPerFloor) end
local function unitOf(b, n)        return ((n - 1) % b.roomsPerFloor) + 1 end
local function numberFromName(nm)  return nm and tonumber(nm:match('(%d+)$')) end

--- The floor number the front desk says out loud.
local function floorLabel(b, n)
    return floorIndex(b, n) + (b.floorOffset or 0)
end

local function notify(src, b, msg, kind, icon, duration)
    TriggerClientEvent('ox_lib:notify', src, {
        title = b.label, description = msg, type = kind or 'inform',
        icon = icon or 'key', position = 'center-right', duration = duration or 6000
    })
end

local function citizenOf(src)
    local P = QBCore.Functions.GetPlayer(src)
    return P and P.PlayerData.citizenid, P
end

local function nameOf(P)
    local ci = P and P.PlayerData.charinfo
    if ci then return ('%s %s'):format(ci.firstname or '', ci.lastname or '') end
    return 'Guest'
end

local function holdsRoomIn(citizenid, b)
    return MySQL.scalar.await(
        'SELECT name FROM nbhd_rooms WHERE owner = ? AND name LIKE ? LIMIT 1',
        { citizenid, roomPattern(b) })
end

--- Owns a home in another housing script (only tables that exist are checked).
local function ownsHome(citizenid)
    for _, t in ipairs(homeTables) do
        local q = ('SELECT 1 FROM `%s` WHERE `%s` = ? LIMIT 1'):format(t.table, t.column)
        if MySQL.scalar.await(q, { citizenid }) then return true end
    end
    return false
end

-- where things are, for distance checks (first-floor x/y, per-floor z)
local function doorPos(b, n)
    local d = b.rooms[unitOf(b, n)].door
    return vector3(d.x, d.y, b.doorBaseZ + (floorIndex(b, n) - 1) * b.floorHeight)
end

local function safePos(b, n)
    local s = b.rooms[unitOf(b, n)].safe
    if not s then return nil end
    return vector3(s.x, s.y, b.baseZ + (floorIndex(b, n) - 1) * b.floorHeight)
end

local function near(src, pos, range)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and pos and #(GetEntityCoords(ped) - pos) <= range
end

-- ============================================================
--  ROOM ASSIGNMENT
-- ============================================================

--- Free rooms in a building (one query instead of one per room).
local function freeRooms(b)
    local taken = {}
    for _, row in ipairs(MySQL.query.await('SELECT name FROM nbhd_rooms WHERE name LIKE ?', { roomPattern(b) }) or {}) do
        local n = numberFromName(row.name)
        if n then taken[n] = true end
    end
    local free = {}
    for n = 1, totalRooms(b) do
        if not taken[n] then free[#free + 1] = n end
    end
    return free, taken
end

--- Claim room n for this citizen. False if someone got it first.
local function claim(b, n, citizenid)
    local affected = MySQL.update.await(
        'INSERT IGNORE INTO nbhd_rooms (name, owner, rent, created) VALUES (?, ?, ?, ?)',
        { roomName(b, n), citizenid, b.rent or 0, os.time() })
    return affected and affected > 0
end

local function rememberRoom(citizenid, bKey, n)
    MySQL.update.await(
        'INSERT INTO nbhd_rooms_last (citizenid, building, room) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE room = VALUES(room)',
        { citizenid, bKey, n })
end

local function lastRoom(citizenid, bKey)
    return MySQL.scalar.await('SELECT room FROM nbhd_rooms_last WHERE citizenid = ? AND building = ?', { citizenid, bKey })
end

--- Returns room number, reason ('has_room' | 'has_home' | 'full'), sameAsLast
local function assignRoom(src, citizenid, bKey)
    local b = Config.Buildings[bKey]
    if not b then return nil end

    local held = numberFromName(holdsRoomIn(citizenid, b))
    if held then return held, 'has_room' end
    if b.skipIfOwnsAnyProperty and ownsHome(citizenid) then return nil, 'has_home' end

    local free, taken = freeRooms(b)

    -- their old room first, if nobody else is in it
    local prev = Config.KeepLastRoom and tonumber(lastRoom(citizenid, bKey)) or nil
    if prev and prev >= 1 and prev <= totalRooms(b) and not taken[prev] and claim(b, prev, citizenid) then
        rememberRoom(citizenid, bKey, prev)
        return prev, nil, true
    end

    -- otherwise a random free one (retry if two people grab the same room at once)
    for _ = 1, 5 do
        if #free == 0 then break end
        local i = math.random(1, #free)
        local n = table.remove(free, i)
        if claim(b, n, citizenid) then
            rememberRoom(citizenid, bKey, n)
            return n, nil, false
        end
    end
    return nil, 'full'
end

-- ============================================================
--  DOOR LOCKS (server-authoritative)
-- ============================================================

local doorLocked = {} -- [bKey][n] = bool
for bKey, b in pairs(Config.Buildings) do
    doorLocked[bKey] = {}
    for i = 1, totalRooms(b) do doorLocked[bKey][i] = true end
end

local function lockRoomOf(citizenid, bKey, b)
    local n = numberFromName(holdsRoomIn(citizenid, b))
    if n then
        doorLocked[bKey][n] = true
        TriggerClientEvent('nbhd_rooms:client:doorState', -1, bKey, n, true)
    end
end

RegisterNetEvent('nbhd_rooms:server:requestStates', function()
    local src = source
    TriggerClientEvent('nbhd_rooms:client:allDoorStates', src, doorLocked)

    local citizenid = citizenOf(src)
    if not citizenid then return end
    for bKey, b in pairs(Config.Buildings) do
        local n = numberFromName(holdsRoomIn(citizenid, b))
        if n then TriggerClientEvent('nbhd_rooms:client:setRoom', src, bKey, n) end
    end
end)

RegisterNetEvent('nbhd_rooms:server:toggleDoor', function(bKey, n)
    local src = source
    local b = Config.Buildings[bKey]
    local citizenid = citizenOf(src)
    if not b or not citizenid then return end

    n = tonumber(n)
    if not n or n < 1 or n > totalRooms(b) then return end
    if numberFromName(holdsRoomIn(citizenid, b)) ~= n then return end
    if not near(src, doorPos(b, n), 3.0) then return end      -- has to be at the door

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
            local affected = MySQL.update.await(
                'DELETE FROM nbhd_rooms WHERE owner = ? AND name LIKE ?', { citizenid, roomPattern(b) })
            if affected and affected > 0 then
                print(('[nbhd_rooms] released %s room for %s (kept as their last room)'):format(b.label, citizenid))
            end
        end
    end
end

local function welcome(src, bKey, n, sameAsLast)
    local b = Config.Buildings[bKey]
    notify(src, b, ('%s **Room %d** - Floor %d.'):format(
        sameAsLast and 'Welcome back, you have' or 'You have been assigned', n, floorLabel(b, n)),
        'success', 'key', 8000)
    TriggerClientEvent('nbhd_rooms:client:setRoom', src, bKey, n)
end

AddEventHandler('QBCore:Server:PlayerLoaded', function(Player)
    local src       = Player.PlayerData.source
    local citizenid = Player.PlayerData.citizenid
    sessionCitizen[src] = citizenid
    SetTimeout(3000, function()
        releaseSessionRooms(citizenid)
        for bKey, b in pairs(Config.Buildings) do
            if b.autoAssign then
                local n, reason, same = assignRoom(src, citizenid, bKey)
                if n and reason ~= 'has_room' then
                    welcome(src, bKey, n, same)
                    print(('[nbhd_rooms] %s -> %s Room %d%s'):format(citizenid, b.label, n, same and ' (same as last time)' or ''))
                elseif reason == 'full' then
                    notify(src, b, 'No rooms available right now.', 'error', 'bed')
                end
            end
        end
    end)
end)

local function onLeave(src)
    local citizenid = sessionCitizen[src] or citizenOf(src)
    releaseSessionRooms(citizenid)
    sessionCitizen[src] = nil
end

AddEventHandler('playerDropped', function() onLeave(source) end)
RegisterNetEvent('QBCore:Server:OnPlayerUnload', function(src) onLeave(src or source) end)

-- ============================================================
--  FRONT DESK: shows your key card (and finds you a room if needed)
-- ============================================================

RegisterNetEvent('nbhd_rooms:server:checkRoom', function(bKey)
    local src = source
    local b = Config.Buildings[bKey]
    local citizenid, P = citizenOf(src)
    if not b or not citizenid then return end
    if b.receptionist and not near(src, b.receptionist.coords.xyz, 4.0) then return end

    local n, reason, same = assignRoom(src, citizenid, bKey)
    if not n then
        if reason == 'has_home' then
            notify(src, b, 'You already have a home elsewhere.', 'inform', 'house')
        else
            notify(src, b, 'Sorry, we are fully booked right now.', 'error', 'bed')
        end
        return
    end

    TriggerClientEvent('nbhd_rooms:client:setRoom', src, bKey, n)
    TriggerClientEvent('nbhd_rooms:client:keycard', src, {
        building = b.label,
        room     = n,
        floor    = floorLabel(b, n),
        guest    = nameOf(P),
        fresh    = reason ~= 'has_room',      -- just checked in
        same     = same == true,              -- the room they had last time
    })
end)

-- ============================================================
--  ROOM SAFE (per building, citizenid-keyed: your stuff follows you)
-- ============================================================

local function inventoryType()
    local want = Config.Inventory or 'auto'
    if want ~= 'auto' then return want end
    if GetResourceState('tgiann-inventory') == 'started' then return 'tgiann' end
    if GetResourceState('ox_inventory') == 'started' then return 'ox' end
    if GetResourceState('qb-inventory') == 'started' then return 'qb' end
    return 'legacy'
end

local function openStash(src, stashId, label, slots, weight)
    local inv = inventoryType()
    local ok = false

    if inv == 'tgiann' then
        ok = pcall(function()
            exports['tgiann-inventory']:OpenInventory(src, 'stash', stashId, { maxweight = weight, slots = slots, label = label })
        end)
    elseif inv == 'ox' then
        ok = pcall(function()
            exports.ox_inventory:RegisterStash(stashId, label, slots, weight, false)
        end)
        if ok then TriggerClientEvent('nbhd_rooms:client:openOxStash', src, stashId) end
    elseif inv == 'qb' then
        ok = pcall(function()
            exports['qb-inventory']:OpenInventory(src, stashId, { maxweight = weight, slots = slots, label = label })
        end)
    end

    if not ok then
        -- older inventories: the client-side stash event this resource used before
        TriggerClientEvent('nbhd_rooms:client:doOpenLocker', src, stashId, slots, weight)
    end
end

RegisterNetEvent('nbhd_rooms:server:openLocker', function(bKey)
    local src = source
    local b = Config.Buildings[bKey]
    local citizenid = citizenOf(src)
    if not b or not b.locker or not citizenid then return end

    local n = numberFromName(holdsRoomIn(citizenid, b))
    if not n or not near(src, safePos(b, n), 3.0) then return end   -- at your own room's safe

    -- same id as before, so everything already stored is still there
    local stashId = bKey .. '_locker_' .. citizenid
    openStash(src, stashId, ('%s - Room %d Safe'):format(b.label, n), b.locker.slots, b.locker.weight)
end)
