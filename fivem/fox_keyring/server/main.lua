local tgiann = exports['tgiann-inventory']
local QBCore = exports['qb-core']:GetCoreObject()

-- tgiann-inventory opens the keyring itself (config.itemStash). Each keyring item stores the name of
-- its stash in info.id, the same as tgiann's wallets and bags.

local function newStashId(src)
    local player = QBCore.Functions.GetPlayer(src)
    local cid = player and player.PlayerData.citizenid or tostring(src)
    return ('%s%s%d%04d'):format(Config.KeyringItem, cid, os.time(), math.random(0, 9999))
end

--- Returns the stash id of a keyring item, giving it one when needed.
--- Keyrings made by fox_keyring 2.x stored a ringId instead; they keep their old stash (and keys)
--- by pointing info.id at it before tgiann ever opens them.
local function ringStashId(src, item, slot, create)
    local info = Keyring.ItemInfo(item) or {}
    if info.id then return info.id end

    if info.ringId then
        info.id = ('keyring_%s'):format(info.ringId)
    elseif create then
        info.id = newStashId(src)
    else
        return nil
    end

    tgiann:UpdateItemMetadata(src, Config.KeyringItem, slot, info)
    return info.id
end

---------------------------------------------------------------------
-- Reading a keyring's contents
---------------------------------------------------------------------

local databaseUsable = true

local function readStashFromExport(id)
    local ok, items = pcall(function()
        return tgiann:GetSecondaryInventoryItems('stash', id)
    end)
    if ok and type(items) == 'table' then return items end
end

local function readStashFromDatabase(id)
    if not databaseUsable then return nil end

    local cfg = Config.StashTable
    local query = ('SELECT `%s` FROM `%s` WHERE `%s` = ? LIMIT 1'):format(cfg.itemsColumn, cfg.table, cfg.idColumn)
    local ok, raw = pcall(MySQL.scalar.await, query, { id })
    if not ok then
        -- Wrong table/column names: stop retrying so the console isn't spammed.
        databaseUsable = false
        print(('^1[fox_keyring] Could not read %s, check Config.StashTable: %s^0'):format(cfg.table, tostring(raw)))
        return nil
    end
    if type(raw) ~= 'string' or raw == '' then return nil end

    local decoded
    ok, decoded = pcall(json.decode, raw)
    if ok and type(decoded) == 'table' then return decoded end
end

--- Returns the items inside a keyring stash (or an empty table), plus where they were read from.
--- The export is the live copy; the database covers stashes tgiann hasn't loaded yet (e.g. after a restart).
local function readStash(id)
    local items = readStashFromExport(id)
    if items and next(items) then return items, 'export' end

    local saved = readStashFromDatabase(id)
    if saved and next(saved) then return saved, 'database' end

    return items or {}, items and 'export' or nil
end

local function ssnMatches(have, want)
    if want == nil then return true end
    -- 0r-vehiclekeys treats keys made before ssn tracking as ssn 0.
    if have == nil then have = 0 end
    return tostring(have) == tostring(want)
end

--- Calls cb(stashId) for every keyring item the player is carrying. Return true from cb to stop.
local function forEachRing(src, cb)
    local items = tgiann:GetPlayerItems(src)
    if type(items) ~= 'table' then return end

    for k, item in pairs(items) do
        if type(item) == 'table' and item.name == Config.KeyringItem then
            local id = ringStashId(src, item, item.slot or tonumber(k), false)
            if id and cb(id) then return end
        end
    end
end

--- True when a key for this plate is on any keyring the player is carrying.
local function ringHasPlate(src, plate, ssn)
    plate = Keyring.NormalizePlate(plate)
    if not plate then return false end

    local found = false
    forEachRing(src, function(id)
        for _, key in pairs(readStash(id)) do
            if type(key) == 'table' and key.name == Config.KeyItem then
                local keyInfo = Keyring.ItemInfo(key)
                if keyInfo and Keyring.NormalizePlate(keyInfo.plate) == plate and ssnMatches(keyInfo.ssn, ssn) then
                    found = true
                    return true
                end
            end
        end
    end)
    return found
end

--- Every plate on every keyring the player is carrying.
local function getRingPlates(src)
    local plates = {}
    forEachRing(src, function(id)
        for _, key in pairs(readStash(id)) do
            local keyInfo = type(key) == 'table' and key.name == Config.KeyItem and Keyring.ItemInfo(key)
            local plate = keyInfo and Keyring.NormalizePlate(keyInfo.plate)
            if plate then plates[#plates + 1] = plate end
        end
    end)
    return plates
end

exports('RingHasPlate', ringHasPlate)
exports('GetRingPlates', getRingPlates)

---------------------------------------------------------------------
-- Moving old keyrings over to tgiann's container system
---------------------------------------------------------------------

local function migratePlayer(src)
    forEachRing(src, function() end) -- ringStashId updates any old keyring it finds
end


CreateThread(function()
    for _, id in ipairs(GetPlayers()) do
        migratePlayer(tonumber(id))
    end
end)

---------------------------------------------------------------------
-- New keys go straight onto the keyring
---------------------------------------------------------------------

local function freeRingSlot(contents)
    local used, count = {}, 0
    for k, entry in pairs(contents) do
        if type(entry) == 'table' then
            count = count + 1
            used[tonumber(entry.slot) or tonumber(k) or 0] = true
        end
    end
    if count >= Config.Slots then return nil end
    for i = 1, Config.Slots do
        if not used[i] then return i end
    end
end

local function keyOnRing(id, plate, ssn)
    local items = readStashFromExport(id)
    if not items then return nil end -- can't check live contents
    for _, key in pairs(items) do
        local keyInfo = type(key) == 'table' and key.name == Config.KeyItem and Keyring.ItemInfo(key)
        if keyInfo and Keyring.NormalizePlate(keyInfo.plate) == plate and ssnMatches(keyInfo.ssn, ssn) then
            return true
        end
    end
    return false
end

--- True when the plate is the player's own car: their row in player_vehicles with no job/society.
--- Job cars, society cars, and stolen or hotwired cars all return false, so their keys stay in the pockets.
local function isPersonalVehicle(src, plate)
    local cfg = Config.PersonalVehicles
    if not cfg then return true end

    local player = QBCore.Functions.GetPlayer(src)
    local citizenid = player and player.PlayerData.citizenid
    if not citizenid then return false end

    local where = ('`%s` = ? AND UPPER(TRIM(plate)) = ?'):format(cfg.ownerColumn)
    if cfg.jobColumn then
        where = ('%s AND (`%s` IS NULL OR `%s` = \'\')'):format(where, cfg.jobColumn, cfg.jobColumn)
    end

    local ok, found = pcall(MySQL.scalar.await, ('SELECT 1 FROM `%s` WHERE %s LIMIT 1'):format(cfg.table, where), { citizenid, plate })
    if not ok then
        print(('^1[fox_keyring] Personal vehicle check failed, check Config.PersonalVehicles: %s^0'):format(tostring(found)))
        return false
    end
    return found ~= nil
end

--- Puts a key on the first keyring the player carries that has room.
--- Returns true when it was placed; false means the caller should give it the normal way.
local function addKeyToRing(src, item, metadata)
    if not Config.AutoAddKeys or item ~= Config.KeyItem or type(metadata) ~= 'table' then return false end
    local plate = Keyring.NormalizePlate(metadata.plate)
    if not plate or not isPersonalVehicle(src, plate) then return false end

    local items = tgiann:GetPlayerItems(src)
    if type(items) ~= 'table' then return false end

    for k, ring in pairs(items) do
        if type(ring) == 'table' and ring.name == Config.KeyringItem then
            local id = ringStashId(src, ring, ring.slot or tonumber(k), true)
            local slot = freeRingSlot(readStash(id))

            if slot then
                local ok, result = pcall(function()
                    return tgiann:AddItemToSecondaryInventory('stash', id, item, 1, slot, metadata)
                end)

                if ok then
                    -- Confirm from the live stash when we can; otherwise trust tgiann's return value.
                    local placed = keyOnRing(id, plate, metadata.ssn)
                    if placed == nil then placed = result ~= nil and result ~= false end

                    if placed then
                        TriggerClientEvent('QBCore:Notify', src, ('Key for %s added to your keyring'):format(plate), 'success')
                        return true
                    end
                else
                    print(('^1[fox_keyring] Could not add key to %s: %s^0'):format(id, tostring(result)))
                end
            end
        end
    end

    return false
end

exports('AddKeyToRing', addKeyToRing)

--- Takes a key off whichever keyring the player carries it on (e.g. a job car was returned).
--- Returns true when a key was removed.
local function removeKeyFromRing(src, item, metadata)
    if item ~= Config.KeyItem or type(metadata) ~= 'table' then return false end
    local plate = Keyring.NormalizePlate(metadata.plate)
    if not plate then return false end

    local removed = false
    forEachRing(src, function(id)
        for k, key in pairs(readStash(id)) do
            local keyInfo = type(key) == 'table' and key.name == Config.KeyItem and Keyring.ItemInfo(key)
            if keyInfo and Keyring.NormalizePlate(keyInfo.plate) == plate and ssnMatches(keyInfo.ssn, metadata.ssn) then
                local slot = tonumber(key.slot) or tonumber(k)
                local ok, result = pcall(function()
                    return tgiann:RemoveItemFromSecondaryInventory('stash', id, item, 1, slot)
                end)
                if not ok then
                    print(('^1[fox_keyring] Could not remove key %s from %s: %s^0'):format(plate, id, tostring(result)))
                    return true
                end
                -- Confirm from the live stash when we can; otherwise trust tgiann's return value.
                local stillThere = keyOnRing(id, plate, metadata.ssn)
                if stillThere == nil then
                    removed = result ~= nil and result ~= false
                else
                    removed = not stillThere
                end
                return true
            end
        end
    end)
    return removed
end

exports('RemoveKeyFromRing', removeKeyFromRing)

---------------------------------------------------------------------
-- Server restart: car keys reset
---------------------------------------------------------------------

-- When the server process started. GetGameTimer() counts from server start, so this stays the
-- same when only fox_keyring is restarted and only changes on a real server restart.
local serverStartedAt = os.time() - math.floor(GetGameTimer() / 1000)

local function notify(src, message, kind)
    TriggerClientEvent('QBCore:Notify', src, message, kind or 'primary')
end

--- Removes every car key from the player's pockets and from the keyrings they carry.
--- Only Config.KeyItem is touched, so other keys (businesses, houses...) stay.
local function wipeCarKeys(src)
    local removed = 0

    local items = tgiann:GetPlayerItems(src)
    if type(items) == 'table' then
        for k, item in pairs(items) do
            if type(item) == 'table' and item.name == Config.KeyItem then
                local amount = tonumber(item.amount or item.count) or 1
                if tgiann:RemoveItem(src, Config.KeyItem, amount, item.slot or tonumber(k)) then
                    removed = removed + amount
                end
            end
        end
    end

    forEachRing(src, function(id)
        for k, key in pairs(readStash(id)) do
            if type(key) == 'table' and key.name == Config.KeyItem then
                local amount = tonumber(key.amount or key.count) or 1
                local ok, result = pcall(function()
                    return tgiann:RemoveItemFromSecondaryInventory('stash', id, Config.KeyItem, amount, tonumber(key.slot) or tonumber(k))
                end)
                if ok and result ~= false then
                    removed = removed + amount
                else
                    print(('^1[fox_keyring] Could not clear key from %s: %s^0'):format(id, tostring(result)))
                end
            end
        end
    end)

    return removed
end

local function handleRestartWipe(src, citizenid)
    if not Config.WipeKeysOnRestart or not citizenid then return end

    local kvp = ('wiped:%s'):format(citizenid)
    -- Already cleared since this server start (relog, or fox_keyring restarted): leave their keys alone.
    if math.abs(GetResourceKvpInt(kvp) - serverStartedAt) <= 300 then return end

    -- Give tgiann a moment to finish loading the character's inventory.
    SetTimeout(Config.WipeDelay, function()
        if not GetPlayerName(src) then return end
        local removed = wipeCarKeys(src)
        SetResourceKvpInt(kvp, serverStartedAt)
        if removed > 0 then
            print(('[fox_keyring] restart reset: removed %d car key(s) from %s'):format(removed, citizenid))
            notify(src, Config.WipeMessage, 'primary')
        end
    end)
end

AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    local data = player and player.PlayerData
    local src = data and data.source
    if not src then return end
    migratePlayer(src)
    handleRestartWipe(src, data.citizenid)
end)

---------------------------------------------------------------------
-- Robbing: search another player's keyring
---------------------------------------------------------------------

local function canBeSearched(target)
    local player = QBCore.Functions.GetPlayer(target)
    local meta = player and player.PlayerData.metadata or {}
    if meta.isdead or meta.inlaststand or meta.ishandcuffed then return true end
    return lib.callback.await('fox_keyring:client:handsUp', target) == true
end

--- The first keyring the player carries, giving it a stash id if it has never been used.
local function firstRingId(src)
    local items = tgiann:GetPlayerItems(src)
    if type(items) ~= 'table' then return nil end
    for k, item in pairs(items) do
        if type(item) == 'table' and item.name == Config.KeyringItem then
            return ringStashId(src, item, item.slot or tonumber(k), true)
        end
    end
end

RegisterNetEvent('fox_keyring:server:searchKeyring', function(target)
    local src = source
    target = tonumber(target)
    if not Config.Search.enabled or not target or target == src or not GetPlayerName(target) then return end

    if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(GetPlayerPed(target))) > Config.Search.distance then
        return notify(src, 'You need to be closer.', 'error')
    end
    if not canBeSearched(target) then
        return notify(src, 'They need to have their hands up, be cuffed or be down.', 'error')
    end

    local id = firstRingId(target)
    if not id then return notify(src, "They don't have a keyring.", 'error') end

    -- Added to tgiann-inventory/server/editable.lua (see README); it registers the stash so keys can be taken.
    local ok, opened = pcall(function()
        return tgiann:OpenKeyringStash(src, id)
    end)
    if not ok or not opened then
        print(('^1[fox_keyring] OpenKeyringStash failed: %s. Did you add the fox_keyring block to tgiann-inventory/server/editable.lua?^0'):format(tostring(opened)))
        return notify(src, "Couldn't open their keyring.", 'error')
    end
end)

---------------------------------------------------------------------
-- Diagnostics: keyringcheck <playerId>
---------------------------------------------------------------------

RegisterCommand('keyringcheck', function(source, args)
    if source ~= 0 and not IsPlayerAceAllowed(source, Config.AdminAce) then return end

    local target = tonumber(args[1]) or (source ~= 0 and source or nil)
    if not target or not GetPlayerName(target) then
        return print('[fox_keyring] usage: keyringcheck <playerId>')
    end

    print(('^3[fox_keyring] ---- keyrings carried by %s (%d) ----^0'):format(GetPlayerName(target), target))
    local rings = 0
    forEachRing(target, function(id)
        rings = rings + 1
        local items, method = readStash(id)
        local count = 0
        for _, key in pairs(items) do
            if type(key) == 'table' then
                local keyInfo = Keyring.ItemInfo(key) or {}
                count = count + 1
                print(('  %s: %s plate=%s ssn=%s'):format(id, tostring(key.name), tostring(keyInfo.plate), tostring(keyInfo.ssn)))
            end
        end
        print(('  %s holds %d item(s), read via %s'):format(id, count, tostring(method or 'nothing (empty or unreadable)')))
    end)

    if rings == 0 then
        print('  No used keyring found. Use the keyring once so it gets an id, then run this again.')
    end
    print('^3[fox_keyring] ---- end ----^0')
end, false)
