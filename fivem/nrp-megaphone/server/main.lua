local QBCore = GetResourceState('qb-core') ~= 'missing' and exports['qb-core']:GetCoreObject() or nil

local function getPlayer(src) return QBCore and QBCore.Functions.GetPlayer(src) or nil end

local function hasItem(src)
    if GetResourceState('tgiann-inventory') == 'started' then
        local ok, n = pcall(function() return exports['tgiann-inventory']:GetItemCount(src, Config.ItemName) end)
        if ok and type(n) == 'number' then return n > 0 end
    end
    local P = getPlayer(src)
    if P then
        local it = P.Functions.GetItemByName(Config.ItemName)
        return it ~= nil and (it.amount or it.count or 0) > 0
    end
    return false
end

local function jobAllowed(src, jobs)
    if not jobs then return true end
    local P = getPlayer(src)
    local job = P and P.PlayerData.job and P.PlayerData.job.name
    for _, j in ipairs(jobs) do if j == job then return true end end
    return false
end

local function setState(src, mode)
    Player(src).state:set('megaphone', mode or false, true)
end

-- the client asks; the server checks and sets the state everyone listens to
RegisterNetEvent('nrp-megaphone:server:setMode', function(mode)
    local src = source
    if mode == nil or mode == false then return setState(src, false) end
    if type(mode) ~= 'string' or not Config.Range[mode] then return end

    local ok, why = true, nil
    if mode == 'handheld' then
        if not Config.Handheld.Enabled then ok, why = false, 'disabled'
        elseif not hasItem(src) then ok, why = false, "You don't have a megaphone."
        elseif not jobAllowed(src, Config.Handheld.Jobs) then ok, why = false, "You can't use this." end
    elseif mode == 'vehicle' then
        local ped = GetPlayerPed(src)
        if not Config.Vehicle.Enabled then ok, why = false, 'disabled'
        elseif ped == 0 or GetVehiclePedIsIn(ped, false) == 0 then ok, why = false, 'Get in the vehicle first.'
        elseif not jobAllowed(src, Config.Vehicle.Jobs) then ok, why = false, 'This PA is for emergency services.' end
    elseif mode == 'stage' then
        if not Config.Stage.Enabled then ok, why = false, 'disabled' end
    end

    if not ok then
        setState(src, false)
        TriggerClientEvent('nrp-megaphone:client:denied', src, why)
        return
    end
    setState(src, mode)
end)

-- using the item toggles the handheld
CreateThread(function()
    if not QBCore then return end
    QBCore.Functions.CreateUseableItem(Config.ItemName, function(source)
        if getPlayer(source) then TriggerClientEvent('nrp-megaphone:client:useItem', source) end
    end)
end)

-- character switch / logout: never carry it over
AddEventHandler('QBCore:Server:OnPlayerUnload', function(src) setState(tonumber(src), false) end)
