local QBCore = exports['qb-core']:GetCoreObject()

-- ============================================================
--  NBHD ROOMS - multi-building room system (client)
--  All behavior is driven by Config.Buildings (config.lua)
-- ============================================================

local myRooms     = {} -- [bKey] = roomNumber
local doorLocked  = {} -- [bKey][n] = bool
local doors       = {} -- [bKey][n] = { coords, hash }
local safes       = {} -- [bKey][n] = object handle (only while you are near the building)
local receptions  = {} -- [bKey] = ped handle   (only while you are near the building)
local centers     = {} -- [bKey] = vector3, middle of the building
local activePanel = nil -- which panel is currently shown (string id)

local function unitOf(b, n) return ((n - 1) % b.roomsPerFloor) + 1 end
local function floorOf(b, n) return math.ceil(n / b.roomsPerFloor) end
local function floorLabel(b, n) return floorOf(b, n) + (b.floorOffset or 0) end

-- player-standing z on the floor room n is on
local function standZ(b, n) return b.baseZ + (floorOf(b, n) - 1) * b.floorHeight end

local function loadModel(model)
    if type(model) == 'string' then model = joaat(model) end
    if not IsModelInCdimage(model) then return nil end
    RequestModel(model)
    local t = GetGameTimer() + 5000
    while not HasModelLoaded(model) do
        if GetGameTimer() > t then return nil end
        Wait(25)
    end
    return model
end

-- ============================================================
--  DOORS (registered once for every room on every floor)
-- ============================================================

local function registerDoors()
    for bKey, b in pairs(Config.Buildings) do
        doors[bKey], doorLocked[bKey] = {}, {}
        local sx, sy, cnt = 0.0, 0.0, 0

        for floor = 1, b.floors do
            for unit = 1, b.roomsPerFloor do
                local n = (floor - 1) * b.roomsPerFloor + unit
                local d = b.rooms[unit].door
                local z = b.doorBaseZ + (floor - 1) * b.floorHeight
                local doorHash = GetHashKey(('%s_door_%d'):format(bKey, n))

                doors[bKey][n] = { coords = vector3(d.x, d.y, z), hash = doorHash }
                doorLocked[bKey][n] = true

                if not IsDoorRegisteredWithSystem(doorHash) then
                    AddDoorToSystem(doorHash, b.doorModel, d.x, d.y, z, false, false, false)
                end
                DoorSystemSetDoorState(doorHash, 1, false, true)

                if floor == 1 then sx, sy, cnt = sx + d.x, sy + d.y, cnt + 1 end
            end
        end

        local midZ = b.baseZ + (b.floors - 1) * b.floorHeight * 0.5
        centers[bKey] = cnt > 0 and vector3(sx / cnt, sy / cnt, midZ) or vector3(0, 0, 0)
    end
end

-- ============================================================
--  SAFES: one in every room, on every floor, at the exact
--  config spot. Spawned only while you are near the building so
--  the floors are loaded (that is why they used to go missing).
-- ============================================================

local function safeSpot(b, n)
    local s = b.rooms[unitOf(b, n)].safe
    if not s then return nil end
    return vector3(s.x, s.y, standZ(b, n) + (b.safeZOffset or -1.0)), (s.h + 180.0) % 360.0
end

local function clearLeftovers(model, pos)
    for _ = 1, 5 do
        local obj = GetClosestObjectOfType(pos.x, pos.y, pos.z, 1.5, model, false, false, false)
        if obj == 0 or not DoesEntityExist(obj) then return end
        SetEntityAsMissionEntity(obj, true, true)
        DeleteEntity(obj)
    end
end

local function spawnSafes(bKey, b)
    if not b.safeModel then return end
    local model = loadModel(b.safeModel)
    if not model then
        print(('[nbhd_rooms] safe model for %s is not valid, no safes spawned'):format(bKey))
        return
    end
    safes[bKey] = safes[bKey] or {}

    for n = 1, b.floors * b.roomsPerFloor do
        local obj = safes[bKey][n]
        if not (obj and DoesEntityExist(obj)) then
            local pos, heading = safeSpot(b, n)
            if pos then
                clearLeftovers(model, pos)
                obj = CreateObjectNoOffset(model, pos.x, pos.y, pos.z, false, false, false)
                SetEntityHeading(obj, heading)
                SetEntityCoordsNoOffset(obj, pos.x, pos.y, pos.z, false, false, false)
                FreezeEntityPosition(obj, true)
                SetEntityInvincible(obj, true)
                safes[bKey][n] = obj
            end
        end
    end
    SetModelAsNoLongerNeeded(model)
end

local function despawnSafes(bKey)
    for n, obj in pairs(safes[bKey] or {}) do
        if DoesEntityExist(obj) then DeleteEntity(obj) end
        safes[bKey][n] = nil
    end
end

-- ============================================================
--  RECEPTIONIST
-- ============================================================

local function spawnReceptionist(bKey, b)
    local r = b.receptionist
    if not r then return end
    local model = loadModel(r.model)
    if not model then
        print(('[nbhd_rooms] receptionist model %s is not valid'):format(tostring(r.model)))
        return
    end

    local c = r.coords
    local ped = CreatePed(4, model, c.x, c.y, c.z - 1.0, c.w, false, true)
    SetEntityCoordsNoOffset(ped, c.x, c.y, c.z - 1.0, false, false, false)
    SetEntityHeading(ped, c.w)
    SetEntityAsMissionEntity(ped, true, true)
    SetEntityInvincible(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedDiesWhenInjured(ped, false)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)
    if r.scenario then TaskStartScenarioInPlace(ped, r.scenario, 0, true) end
    SetModelAsNoLongerNeeded(model)
    receptions[bKey] = ped
end

local function despawnReceptionist(bKey)
    local ped = receptions[bKey]
    if ped and DoesEntityExist(ped) then DeleteEntity(ped) end
    receptions[bKey] = nil
end

-- ============================================================
--  STARTUP + STREAMING
-- ============================================================

CreateThread(function()
    while not LocalPlayer.state.isLoggedIn do Wait(500) end
    Wait(1000)
    registerDoors()
    TriggerServerEvent('nbhd_rooms:server:requestStates')

    local spawned = {}
    while true do
        local pC = GetEntityCoords(PlayerPedId())
        for bKey, b in pairs(Config.Buildings) do
            local c = centers[bKey]
            local dist = c and #(pC.xy - c.xy) or math.huge

            if dist < (Config.SpawnDistance or 90.0) then
                if not spawned[bKey] then
                    -- give the interior a moment to stream in
                    Wait(750)
                    spawned[bKey] = true
                end
                -- (re)spawn anything missing: also acts as the watchdog
                spawnSafes(bKey, b)
                local ped = receptions[bKey]
                if b.receptionist and not (ped and DoesEntityExist(ped)) then spawnReceptionist(bKey, b) end
            elseif spawned[bKey] and dist > (Config.DespawnDistance or 130.0) then
                despawnSafes(bKey)
                despawnReceptionist(bKey)
                spawned[bKey] = nil
            end
        end
        Wait(2000)
    end
end)

-- retry state sync until we know our rooms
CreateThread(function()
    while not LocalPlayer.state.isLoggedIn do Wait(500) end
    Wait(6000)
    for _ = 1, 5 do
        if next(myRooms) then break end
        TriggerServerEvent('nbhd_rooms:server:requestStates')
        Wait(4000)
    end
end)

-- ============================================================
--  STATE SYNC
-- ============================================================

local function applyDoorState(bKey, n, locked)
    if not doorLocked[bKey] then return end
    doorLocked[bKey][n] = locked
    local d = doors[bKey] and doors[bKey][n]
    if d then
        DoorSystemSetDoorState(d.hash, locked and 1 or 0, false, true)
    end
end

RegisterNetEvent('nbhd_rooms:client:allDoorStates', function(states)
    for bKey, list in pairs(states) do
        for n, locked in pairs(list) do
            applyDoorState(bKey, tonumber(n), locked)
        end
    end
end)

RegisterNetEvent('nbhd_rooms:client:doorState', function(bKey, n, locked)
    n = tonumber(n)
    applyDoorState(bKey, n, locked)
    if activePanel == ('door_' .. bKey) and myRooms[bKey] == n then
        SendNUIMessage({ action = 'state', locked = locked })
    end
end)

RegisterNetEvent('nbhd_rooms:client:setRoom', function(bKey, n)
    myRooms[bKey] = tonumber(n)
end)

RegisterNetEvent('nbhd_rooms:client:keycard', function(data)
    SendNUIMessage({ action = 'keycard', card = data })
end)

-- ============================================================
--  WARDROBE (17mov_CharacterSystem, illenium-appearance or qb-clothing)
-- ============================================================

local function openWardrobe()
    local ev = Config.WardrobeEvent or 'auto'
    if ev == 'auto' then
        if GetResourceState('17mov_CharacterSystem') == 'started' then
            ev = '17mov'
        elseif GetResourceState('illenium-appearance') == 'started' then
            ev = 'illenium-appearance:client:openOutfitMenu'
        else
            ev = 'qb-clothing:client:openOutfitMenu'
        end
    end
    if ev == '17mov' then
        ev = Config.Wardrobe17movEvent or 'qb-clothing:client:openOutfitMenu'
    end
    TriggerEvent(ev)
end

-- ============================================================
--  PROXIMITY INTERACTIONS (one thread per building)
-- ============================================================

local function showPanel(id, msg)
    if activePanel ~= id then
        activePanel = id
        SendNUIMessage(msg)
    end
end

local function hidePanel(id)
    if activePanel == id then
        activePanel = nil
        SendNUIMessage({ action = 'hide' })
    end
end

local function playSound(name)
    if name then TriggerEvent('InteractSound_CL:PlayOnOne', name, 0.4) end
end

for bKey, b in pairs(Config.Buildings) do
    CreateThread(function()
        local lockKey     = b.lockKey or 311
        local interactKey = b.interactKey or 38

        while true do
            local sleep = 1000
            local n = myRooms[bKey]
            local pC = GetEntityCoords(PlayerPedId())

            if n then
                local floor = floorLabel(b, n)

                -- DOOR
                local d = doors[bKey] and doors[bKey][n]
                if d then
                    local dist = #(pC - d.coords)
                    if dist < 15.0 then sleep = 0 end
                    if dist < 1.8 then
                        showPanel('door_' .. bKey, { action = 'show', kind = 'door', label = b.label, room = n, floor = floor, locked = doorLocked[bKey][n] })
                        if IsControlJustReleased(0, lockKey) then
                            TriggerServerEvent('nbhd_rooms:server:toggleDoor', bKey, n)
                            SendNUIMessage({ action = 'turnkey' })
                            playSound(b.lockSound)
                        end
                    else
                        hidePanel('door_' .. bKey)
                    end
                end

                -- SAFE
                local pos = b.locker and safeSpot(b, n)
                if pos then
                    local dist = #(pC - pos)
                    if dist < 10.0 then sleep = 0 end
                    if dist < 1.8 then
                        showPanel('locker_' .. bKey, { action = 'show', kind = 'locker', label = b.label, room = n, floor = floor })
                        if IsControlJustReleased(0, interactKey) then
                            playSound(b.lockerSound)
                            TriggerServerEvent('nbhd_rooms:server:openLocker', bKey)
                        end
                    else
                        hidePanel('locker_' .. bKey)
                    end
                end

                -- WARDROBE
                local w = b.rooms[unitOf(b, n)].wardrobe
                if w then
                    local dist = #(pC - vector3(w.x, w.y, standZ(b, n)))
                    if dist < 10.0 then sleep = 0 end
                    if dist < 1.6 then
                        showPanel('wardrobe_' .. bKey, { action = 'show', kind = 'wardrobe', label = b.label, room = n, floor = floor })
                        if IsControlJustReleased(0, interactKey) then openWardrobe() end
                    else
                        hidePanel('wardrobe_' .. bKey)
                    end
                end
            end

            -- RECEPTION (works whether or not you hold a room)
            local ped = receptions[bKey]
            if ped and DoesEntityExist(ped) then
                local dist = #(pC - GetEntityCoords(ped))
                if dist < 10.0 then sleep = 0 end
                if dist < 2.2 then
                    showPanel('reception_' .. bKey, { action = 'show', kind = 'reception', label = b.label, room = n, floor = n and floorLabel(b, n) or nil })
                    if IsControlJustReleased(0, interactKey) then
                        TriggerServerEvent('nbhd_rooms:server:checkRoom', bKey)
                    end
                else
                    hidePanel('reception_' .. bKey)
                end
            end

            Wait(sleep)
        end
    end)
end

-- ============================================================
--  SAFE OPEN (fallbacks; tgiann / qb open straight from the server)
-- ============================================================

RegisterNetEvent('nbhd_rooms:client:openOxStash', function(stashId)
    exports.ox_inventory:openInventory('stash', stashId)
end)

RegisterNetEvent('nbhd_rooms:client:doOpenLocker', function(stashId, slots, weight)
    TriggerServerEvent('inventory:server:OpenInventory', 'stash', stashId, {
        maxweight = weight,
        slots     = slots,
    })
    TriggerEvent('inventory:client:SetCurrentStash', stashId)
end)

-- ============================================================
--  CLEANUP
-- ============================================================

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for bKey in pairs(Config.Buildings) do
        despawnSafes(bKey)
        despawnReceptionist(bKey)
    end
end)

-- ============================================================
--  DEBUG COMMANDS
-- ============================================================

RegisterCommand('myroom', function()
    for bKey, n in pairs(myRooms) do
        local b = Config.Buildings[bKey]
        local d = doors[bKey] and doors[bKey][n]
        local dist = d and #(GetEntityCoords(PlayerPedId()) - d.coords) or -1
        local s = safes[bKey] and safes[bKey][n]
        print(('[nbhd_rooms] %s: room %d (floor %d) | door dist %.2f | locked %s | safe spawned %s'):format(
            bKey, n, floorLabel(b, n), dist, tostring(doorLocked[bKey] and doorLocked[bKey][n]),
            tostring(s ~= nil and DoesEntityExist(s))))
    end
    if not next(myRooms) then print('[nbhd_rooms] no rooms held') end
end, false)

RegisterCommand('roomfloors', function()
    for bKey, b in pairs(Config.Buildings) do
        for f = 1, b.floors do
            local first = (f - 1) * b.roomsPerFloor + 1
            print(('[nbhd_rooms] %s Floor %d: rooms %d-%d'):format(b.label, f + (b.floorOffset or 0), first, first + b.roomsPerFloor - 1))
        end
    end
end, false)

RegisterCommand('finddoor', function()
    local pC = GetEntityCoords(PlayerPedId())
    local objects = GetGamePool('CObject')
    local found = 0
    for i = 1, #objects do
        local oC = GetEntityCoords(objects[i])
        if #(pC - oC) < 3.0 then
            print(('[nbhd_rooms] object: hash %s | coords %.2f, %.2f, %.2f | heading %.2f'):format(
                GetEntityModel(objects[i]), oC.x, oC.y, oC.z, GetEntityHeading(objects[i])))
            found = found + 1
        end
    end
    if found == 0 then print('[nbhd_rooms] No objects within 3m.') end
end, false)
