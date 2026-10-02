-- Author : Morow
-- Github : https://github.com/Morow73
-- QBCore / ESX / standalone payment

local Framework, QBCore, ESX = 'none', nil, nil

local function detectFramework()
    local want = Config.Framework or 'auto'

    if (want == 'auto' or want == 'qb') and GetResourceState('qb-core') == 'started' then
        QBCore = exports['qb-core']:GetCoreObject()
        return 'qb'
    end

    if (want == 'auto' or want == 'esx') and GetResourceState('es_extended') == 'started' then
        local ok, obj = pcall(function() return exports['es_extended']:getSharedObject() end)
        if ok and obj then
            ESX = obj
        else
            TriggerEvent('esx:getSharedObject', function(o) ESX = o end)   -- old ESX
        end
        return ESX and 'esx' or 'none'
    end

    if want ~= 'auto' and want ~= 'none' then
        print(('^1[mrw_minigolf] Config.Framework is "%s" but that framework is not running. '
            .. 'Playing will be free.^7'):format(want))
    end
    return 'none'
end

CreateThread(function()
    Framework = detectFramework()
    print(('[mrw_minigolf] framework: %s, clubs cost $%d'):format(Framework, Config.club_price or 0))
end)

--- Take the club rental from the player. Returns true if paid.
local function charge(src, price)
    if price <= 0 or Framework == 'none' then return true end

    if Framework == 'qb' then
        local Player = QBCore.Functions.GetPlayer(src)
        if not Player then return false end

        local account = Config.pay_account or 'cash'
        if Player.Functions.GetMoney(account) >= price then
            return Player.Functions.RemoveMoney(account, price, 'minigolf-clubs') ~= false
        end

        if Config.allow_bank_fallback and account ~= 'bank'
            and Player.Functions.GetMoney('bank') >= price then
            return Player.Functions.RemoveMoney('bank', price, 'minigolf-clubs') ~= false
        end
        return false
    end

    if Framework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(src)
        if not xPlayer then return false end
        if xPlayer.getMoney() >= price then
            xPlayer.removeMoney(price)
            return true
        end
        return false
    end

    return false
end

-- one charge per press: stops a double tap of E paying twice
local lastRent = {}

RegisterNetEvent("mrw_minigolf:locateClub")
AddEventHandler("mrw_minigolf:locateClub", function()
    local src = source
    local now = GetGameTimer()

    if lastRent[src] and now - lastRent[src] < 3000 then return end
    lastRent[src] = now

    -- has to be standing at the club rental, not anywhere on the map
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or #(GetEntityCoords(ped) - Config.locate_club) > 6.0 then
        return
    end

    if charge(src, Config.club_price or 0) then
        TriggerClientEvent("mrw_minigolf:st_game", src, 1)
    else
        TriggerClientEvent("mrw_golf:Notification", src, translation["no_money"])
    end
end)

AddEventHandler('playerDropped', function()
    lastRent[source] = nil
end)
