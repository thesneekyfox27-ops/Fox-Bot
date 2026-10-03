local QBCore = exports['qb-core']:GetCoreObject()

-- ============================================================
--  NBHD ROOMS - multi-building room system (client)
--  All behavior is driven by Config.Buildings (config.lua)
-- ============================================================

local myRooms     = {} -- [bKey] = roomNumber
local doorLocked  = {} -- [bKey][n] = bool
local doors       = {} -- [bKey][n] = { coords, hash }
local safes       = {} -- [bKey][n] = object handle
local receptions  = {} -- [bKey] = ped handle
local activePanel = nil -- which panel is currently shown (string id)

local function totalRooms(b) return b.floors * b.roomsPerFloor end
local function unitOf(b, n) return ((n - 1) % b.roomsPerFloor) + 1 end
local function floorOf(b, n) return math.ceil(n / b.roomsPerFloor) end

-- ============================================================
--  SETUP: doors, safes, receptionists per building
-- ============================================================

local function spawnReceptionist(bKey, b)
    if not b.receptionist then return end
    local model = GetHashKey(b.receptionist.model)
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(50) end

    local ped = CreatePed(4, model,
        b.receptionist.coords.x, b.receptionist.coords.y, b.receptionist.coords.z,
        b.receptionist.coords.w, false, true)

    SetEntityCoordsNoOffset(ped, b.receptionist.coords.x, b.receptionist.coords.y, b.receptionist.coords.z, false, false, false)
    SetEntityAsMissionEntity(ped, true, true)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    if b.receptionist.scenario then
        TaskStartScenarioInPlace(ped, b.receptionist.scenario, 0, true)
    end
    SetModelAsNoLongerNeeded(model)
    receptions[bKey] = ped
end

CreateThread(function()
    while not LocalPlayer.state.isLoggedIn do Wait(500) end
    Wait(1500)

    for bKey, b in pairs(Config.Buildings) do
        doors[bKey] = {}
        safes[bKey] = {}
        doorLocked[bKey] = {}

        -- door registration
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
            end
        end

        -- safes
        if b.safeModel then
            RequestModel(b.safeModel)
            local tries = 0
            while not HasModelLoaded(b.safeModel) and tries < 100 do Wait(50) tries = tries + 1 end

            if HasModelLoaded(b.safeModel) then
                for floor = 1, b.floors do
                    for unit = 1, b.roomsPerFloor do
                        local s = b.rooms[unit].safe
                        if s then
                            local n = (floor - 1) * b.roomsPerFloor + unit
                            local z = b.baseZ + (floor - 1) * b.floorHeight

                            -- clear leftovers from a previous session
                            local leftover = GetClosestObjectOfType(s.x, s.y, z - 1.0, 1.5, b.safeModel, false, false, false)
                            while leftover ~= 0 and DoesEntityExist(leftover) do
                                SetEntityAsMissionEntity(leftover, true, true)
                                DeleteEntity(leftover)
                                leftover = GetClosestObjectOfType(s.x, s.y, z - 1.0, 1.5, b.safeModel, false, false, false)
                            end

                            local obj = CreateObjectNoOffset(b.safeModel, s.x, s.y, z - 1.0, false, false, false)
                            SetEntityHeading(obj, (s.h + 180.0) % 360.0)
                            PlaceObjectOnGroundProperly(obj)
                            FreezeEntityPosition(obj, true)
                            safes[bKey][n] = obj
                        end
                    end
                end
                SetModelAsNoLongerNeeded(b.safeModel)
            end
        end

        spawnReceptionist(bKey, b)
    end

    TriggerServerEvent('nbhd_rooms:server:requestStates')
end)

-- receptionist watchdog
CreateThread(function()
    while not LocalPlayer.state.isLoggedIn do Wait(500) end
    while true do
        Wait(10000)
        for bKey, b in pairs(Config.Buildings) do
            if b.receptionist and (not receptions[bKey] or not DoesEntityExist(receptions[bKey])) then
                spawnReceptionist(bKey, b)
            end
        end
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

for bKey, b in pairs(Config.Buildings) do
    CreateThread(function()
        local lockKey     = b.lockKey or 311
        local interactKey = b.interactKey or 38

        while true do
            local sleep = 1000
            local n = myRooms[bKey]

            if n then
                local pC = GetEntityCoords(PlayerPedId())

                -- DOOR
                local d = doors[bKey] and doors[bKey][n]
                if d then
                    local dist = #(pC - d.coords)
                    if dist < 15.0 then sleep = 0 end
                    if dist < 1.8 then
                        showPanel('door_' .. bKey, { action = 'show', kind = 'door', label = b.label, room = n, locked = doorLocked[bKey][n] })
                        if IsControlJustReleased(0, lockKey) then
                            TriggerServerEvent('nbhd_rooms:server:toggleDoor', bKey, n)
                            SendNUIMessage({ action = 'turnkey' })
                            if b.lockSound then
                                TriggerEvent('InteractSound_CL:PlayOnOne', b.lockSound, 0.4)
                            end
                        end
                    else
                        hidePanel('door_' .. bKey)
                    end
                end

                -- LOCKER (safe)
                local s = safes[bKey] and safes[bKey][n]
                if b.locker and s and DoesEntityExist(s) then
                    local dist = #(pC - GetEntityCoords(s))
                    if dist < 10.0 then sleep = 0 end
                    if dist < 1.6 then
                        showPanel('locker_' .. bKey, { action = 'show', kind = 'locker', label = b.label, room = n })
                        if IsControlJustReleased(0, interactKey) then
                            if b.lockerSound then
                                TriggerEvent('InteractSound_CL:PlayOnOne', b.lockerSound, 0.4)
                            end
                            TriggerServerEvent('nbhd_rooms:server:openLocker', bKey)
                        end
                    else
                        hidePanel('locker_' .. bKey)
                    end
                end

                -- WARDROBE
                local w = b.rooms[unitOf(b, n)].wardrobe
                if w then
                    local z = b.baseZ + (floorOf(b, n) - 1) * b.floorHeight
                    local dist = #(pC - vector3(w.x, w.y, z))
                    if dist < 10.0 then sleep = 0 end
                    if dist < 1.6 then
                        showPanel('wardrobe_' .. bKey, { action = 'show', kind = 'wardrobe', label = b.label, room = n })
                        if IsControlJustReleased(0, interactKey) then
                            TriggerEvent('qb-clothing:client:openOutfitMenu')
                        end
                    else
                        hidePanel('wardrobe_' .. bKey)
                    end
                end
            end

            -- RECEPTION (works whether or not you hold a room)
            local ped = receptions[bKey]
            if ped and DoesEntityExist(ped) then
                local dist = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(ped))
                if dist < 10.0 then sleep = 0 end
                if dist < 2.2 then
                    showPanel('reception_' .. bKey, { action = 'show', kind = 'reception', label = b.label })
                    if IsControlJustReleased(0, b.interactKey or 38) then
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
--  LOCKER OPEN (tgiann / qb-inventory compatible)
-- ============================================================

RegisterNetEvent('nbhd_rooms:client:doOpenLocker', function(stashId, slots, weight)
    TriggerServerEvent('inventory:server:OpenInventory', 'stash', stashId, {
        maxweight = weight,
        slots     = slots,
    })
end)

-- ============================================================
--  CLEANUP
-- ============================================================

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, ped in pairs(receptions) do
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end
    for _, list in pairs(safes) do
        for _, obj in pairs(list) do
            if DoesEntityExist(obj) then DeleteEntity(obj) end
        end
    end
end)

-- ============================================================
--  DEBUG COMMANDS
-- ============================================================

RegisterCommand('myroom', function()
    for bKey, n in pairs(myRooms) do
        local d = doors[bKey] and doors[bKey][n]
        local dist = d and #(GetEntityCoords(PlayerPedId()) - d.coords) or -1
        print(('[nbhd_rooms] %s: room %d | door dist %.2f | locked %s'):format(
            bKey, n, dist, tostring(doorLocked[bKey] and doorLocked[bKey][n])))
    end
    if not next(myRooms) then print('[nbhd_rooms] no rooms held') end
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
