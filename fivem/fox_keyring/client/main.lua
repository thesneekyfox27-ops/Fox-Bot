local myKeys = {}   -- [plate] = { label = string, temp = boolean }
local keyList = {}  -- sorted list from the server, used for menus
local engineWarned = false

local function hasOxLib()
    return GetResourceState('ox_lib') == 'started'
end

local function notify(message, kind)
    if hasOxLib() then
        exports.ox_lib:notify({ title = 'Keyring', description = message, type = kind or 'inform' })
        return
    end
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(message)
    EndTextCommandThefeedPostTicker(false, true)
end

local function hasKey(plate)
    plate = Keyring.NormalizePlate(plate)
    return plate ~= nil and myKeys[plate] ~= nil
end

exports('HasKey', hasKey)

RegisterNetEvent('fox_keyring:client:notify', notify)

RegisterNetEvent('fox_keyring:client:sync', function(list)
    keyList = list
    myKeys = {}
    for _, key in ipairs(list) do
        myKeys[key.plate] = key
    end
end)

RegisterNetEvent('fox_keyring:client:setWaypoint', function(x, y)
    SetNewWaypoint(x + 0.0, y + 0.0)
end)

AddEventHandler('onClientResourceStart', function(name)
    if name == GetCurrentResourceName() then
        TriggerServerEvent('fox_keyring:server:requestSync')
    end
end)

-- QBCore: fetch the character's keyring once they've picked a character.
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    TriggerServerEvent('fox_keyring:server:requestSync')
end)

-- Ask the server for a key. It only gives one if you own the plate (or, for job cars, are next to it).
local function claimKey(plate)
    plate = Keyring.NormalizePlate(plate)
    if plate and not myKeys[plate] then
        TriggerServerEvent('fox_keyring:server:claimKey', plate)
    end
end

exports('ClaimKey', claimKey)

if Config.QBCompat then
    -- Used by qb-vehicleshop, qb-policejob, qb-ambulancejob and most QBCore garages.
    RegisterNetEvent('vehiclekeys:client:SetOwner', claimKey)
end

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------

local function getPlate(veh)
    return Keyring.NormalizePlate(GetVehicleNumberPlateText(veh))
end

--- The vehicle you're in, otherwise the closest vehicle within range.
--- With onlyOwned, only vehicles you hold a key for are considered.
local function getTargetVehicle(onlyOwned)
    local ped = PlayerPedId()
    local current = GetVehiclePedIsIn(ped, false)
    if current ~= 0 then return current end

    local coords = GetEntityCoords(ped)
    local closest, closestDist = nil, Config.LockDistance
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        local dist = #(coords - GetEntityCoords(veh))
        if dist < closestDist and (not onlyOwned or hasKey(getPlate(veh))) then
            closest, closestDist = veh, dist
        end
    end
    return closest
end

local function getClosestPlayer(maxDist)
    local myPed = PlayerPedId()
    local coords = GetEntityCoords(myPed)
    local closest, closestDist = nil, maxDist
    for _, player in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(player)
        if ped ~= myPed then
            local dist = #(coords - GetEntityCoords(ped))
            if dist < closestDist then
                closest, closestDist = GetPlayerServerId(player), dist
            end
        end
    end
    return closest
end

local function playKeyFob()
    if not Config.UseKeyFobAnimation or IsPedInAnyVehicle(PlayerPedId(), false) then return end

    CreateThread(function()
        local ped = PlayerPedId()
        local dict, model = 'anim@mp_player_intmenu@key_fob@', `p_car_keys_01`

        RequestAnimDict(dict)
        RequestModel(model)
        local timeout = GetGameTimer() + 1000
        while (not HasAnimDictLoaded(dict) or not HasModelLoaded(model)) and GetGameTimer() < timeout do
            Wait(10)
        end
        if not HasAnimDictLoaded(dict) or not HasModelLoaded(model) then return end

        local prop = CreateObject(model, 0.0, 0.0, 0.0, true, true, false)
        AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, 57005), 0.09, 0.03, -0.02, -76.0, 13.0, 28.0, false, true, true, true, 0, true)
        TaskPlayAnim(ped, dict, 'fob_click', 3.0, 3.0, -1, 48, 0, false, false, false)

        Wait(1000)
        DeleteObject(prop)
        StopAnimTask(ped, dict, 'fob_click', 1.0)
        RemoveAnimDict(dict)
        SetModelAsNoLongerNeeded(model)
    end)
end

---------------------------------------------------------------------
-- Locking
---------------------------------------------------------------------

RegisterCommand('togglelock', function()
    local veh = getTargetVehicle(true)
    if not veh then
        return notify('No vehicle you have keys for nearby.', 'error')
    end
    if not NetworkGetEntityIsNetworked(veh) then
        return notify("This vehicle can't be locked.", 'error')
    end
    TriggerServerEvent('fox_keyring:server:toggleLock', VehToNet(veh))
end, false)

RegisterKeyMapping('togglelock', 'Lock / unlock vehicle', 'keyboard', Config.LockKey)

RegisterNetEvent('fox_keyring:client:lockFx', function(netId, locked, actor)
    if not NetworkDoesNetworkIdExist(netId) then return end
    local veh = NetToVeh(netId)
    if veh == 0 or not DoesEntityExist(veh) then return end

    -- The server sets the lock state; the entity owner mirrors it so it applies instantly.
    if NetworkHasControlOfEntity(veh) then
        SetVehicleDoorsLocked(veh, locked and 2 or 1)
    end

    if actor == GetPlayerServerId(PlayerId()) then playKeyFob() end

    if #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(veh)) > 50.0 then return end

    CreateThread(function()
        local flashes = locked and 2 or 1
        for _ = 1, flashes do
            SetVehicleLights(veh, 2)
            StartVehicleHorn(veh, 80, `HELDDOWN`, false)
            Wait(200)
            SetVehicleLights(veh, 0)
            Wait(200)
        end
    end)
end)

---------------------------------------------------------------------
-- Engine protection
---------------------------------------------------------------------

CreateThread(function()
    while true do
        local sleep = 500

        if Config.RequireKeyForEngine then
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)

            if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped
                and not Config.EngineExemptClasses[GetVehicleClass(veh)]
                and not hasKey(getPlate(veh)) then
                sleep = 0
                SetVehicleEngineOn(veh, false, true, true)
                if not engineWarned then
                    engineWarned = true
                    notify("You don't have the keys to this vehicle.", 'error')
                end
            else
                engineWarned = false
            end
        end

        Wait(sleep)
    end
end)

---------------------------------------------------------------------
-- Keyring menu
---------------------------------------------------------------------

local function giveToClosest(plate)
    local target = getClosestPlayer(Config.GiveDistance)
    if not target then return notify('Nobody is close enough.', 'error') end
    TriggerServerEvent('fox_keyring:server:giveKey', target, plate)
end

local function printKeysToChat()
    if #keyList == 0 then return notify('Your keyring is empty.', 'inform') end
    TriggerEvent('chat:addMessage', { args = { '^3Keyring', ('%d key(s):'):format(#keyList) } })
    for _, key in ipairs(keyList) do
        local line = key.label == key.plate and key.plate or ('%s (%s)'):format(key.label, key.plate)
        if key.temp then line = line .. ' [temp]' end
        TriggerEvent('chat:addMessage', { args = { '^3Keyring', line } })
    end
end

RegisterNetEvent('fox_keyring:client:menuAction', function(data)
    if type(data) ~= 'table' or not data.plate then return end

    if data.action == 'open' then
        local key = myKeys[data.plate]
        if not key then return end
        exports.ox_lib:registerContext({
            id = 'fox_keyring_key',
            title = key.label,
            menu = 'fox_keyring',
            options = {
                { title = 'Locate', description = 'Set a waypoint to this vehicle', icon = 'location-dot',
                  event = 'fox_keyring:client:menuAction', args = { action = 'locate', plate = data.plate } },
                { title = 'Give to nearest player', icon = 'hand-holding',
                  event = 'fox_keyring:client:menuAction', args = { action = 'give', plate = data.plate } },
                { title = 'Remove key', icon = 'trash',
                  event = 'fox_keyring:client:menuAction', args = { action = 'remove', plate = data.plate } },
            },
        })
        exports.ox_lib:showContext('fox_keyring_key')
    elseif data.action == 'locate' then
        TriggerServerEvent('fox_keyring:server:locate', data.plate)
    elseif data.action == 'give' then
        giveToClosest(data.plate)
    elseif data.action == 'remove' then
        TriggerServerEvent('fox_keyring:server:removeKey', data.plate)
    end
end)

RegisterCommand('keyring', function()
    if not hasOxLib() then return printKeysToChat() end
    if #keyList == 0 then return notify('Your keyring is empty.', 'inform') end

    local options = {}
    for _, key in ipairs(keyList) do
        options[#options + 1] = {
            title = key.label,
            description = key.temp and (key.plate .. ' - temporary') or key.plate,
            icon = 'key',
            arrow = true,
            event = 'fox_keyring:client:menuAction',
            args = { action = 'open', plate = key.plate },
        }
    end

    exports.ox_lib:registerContext({ id = 'fox_keyring', title = ('Keyring (%d)'):format(#keyList), options = options })
    exports.ox_lib:showContext('fox_keyring')
end, false)

-- /givekey [playerId] [plate] - defaults to the closest player and your current/nearest vehicle
RegisterCommand('givekey', function(_, args)
    local target = tonumber(args[1]) or getClosestPlayer(Config.GiveDistance)
    if not target then return notify('Nobody is close enough.', 'error') end

    local plate = Keyring.NormalizePlate(args[2])
    if not plate then
        local veh = getTargetVehicle(true)
        plate = veh and getPlate(veh)
    end
    if not plate then return notify('Specify a plate or stand near your vehicle.', 'error') end

    TriggerServerEvent('fox_keyring:server:giveKey', target, plate)
end, false)

-- /dropkey [plate]
RegisterCommand('dropkey', function(_, args)
    local plate = Keyring.NormalizePlate(args[1])
    if not plate then return notify('Usage: /dropkey [plate]', 'error') end
    TriggerServerEvent('fox_keyring:server:removeKey', plate)
end, false)

-- /labelkey [plate] [name...]
RegisterCommand('labelkey', function(_, args)
    local plate = Keyring.NormalizePlate(args[1])
    if not plate then return notify('Usage: /labelkey [plate] [name]', 'error') end
    TriggerServerEvent('fox_keyring:server:labelKey', plate, table.concat(args, ' ', 2))
end, false)

TriggerEvent('chat:addSuggestion', '/keyring', 'Open your keyring')
TriggerEvent('chat:addSuggestion', '/givekey', 'Give a copy of a vehicle key', {
    { name = 'playerId', help = 'Optional, defaults to closest player' },
    { name = 'plate', help = 'Optional, defaults to nearest vehicle you have keys for' },
})
TriggerEvent('chat:addSuggestion', '/dropkey', 'Remove a key from your keyring', { { name = 'plate', help = 'Plate' } })
TriggerEvent('chat:addSuggestion', '/labelkey', 'Name a key', {
    { name = 'plate', help = 'Plate' },
    { name = 'name', help = 'e.g. Daily driver' },
})
