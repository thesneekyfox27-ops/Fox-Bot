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

-- ---------------------------------------------------------------------------
-- groups: everyone plays their own ball at the same time, one shared scorecard
-- ---------------------------------------------------------------------------
local Groups, PlayerGroup, Invites, lastPress = {}, {}, {}, {}
local nextGroup = 0
local HOLES = #Config.golf_track

local function notify(src, msg)
    TriggerClientEvent("mrw_golf:Notification", src, msg)
end

local function nameOf(src)
    if Framework == 'qb' then
        local P = QBCore.Functions.GetPlayer(src)
        local ci = P and P.PlayerData and P.PlayerData.charinfo
        if ci and ci.firstname then return ('%s %s'):format(ci.firstname, ci.lastname or '') end
    elseif Framework == 'esx' then
        local x = ESX.GetPlayerFromId(src)
        if x and x.getName then return x.getName() end
    end
    return GetPlayerName(src) or ('Player ' .. src)
end

local function nearRental(src, range)
    local ped = GetPlayerPed(src)
    return ped and ped ~= 0 and #(GetEntityCoords(ped) - Config.locate_club) <= (range or 6.0)
end

local function broadcast(gid)
    local g = Groups[gid]
    if not g then return end
    local rows = {}
    for _, m in ipairs(g.order) do
        local p = g.players[m]
        rows[#rows + 1] = { id = m, name = p.name, strokes = p.strokes, status = p.status }
    end
    for _, m in ipairs(g.order) do
        if g.players[m].status == 'playing' then
            TriggerClientEvent('mrw_minigolf:groupScores', m, rows)
        end
    end
end

local function addToGroup(gid, src)
    local g = Groups[gid]
    local strokes = {}
    for i = 1, HOLES do strokes[i] = 0 end
    g.players[src] = { name = nameOf(src), strokes = strokes, status = 'playing' }
    g.order[#g.order + 1] = src
    PlayerGroup[src] = gid
end

--- player is done with the game (finished, quit or left the server)
local function leaveGroup(src, status)
    local gid = PlayerGroup[src]
    PlayerGroup[src] = nil
    local g = gid and Groups[gid]
    if not g or not g.players[src] then return end

    g.players[src].status = status
    if status == 'quit' then
        for _, m in ipairs(g.order) do
            if m ~= src and g.players[m].status == 'playing' then
                notify(m, (translation['group_left'] or '%s left the game'):format(g.players[src].name))
            end
        end
    end

    local anyone = false
    for _, m in ipairs(g.order) do
        if g.players[m].status == 'playing' then anyone = true break end
    end
    if anyone then broadcast(gid) else Groups[gid] = nil end
end

local function startGame(src)
    TriggerClientEvent("mrw_minigolf:st_game", src, 1)
    notify(src, (translation['game_started'] or 'Clubs rented for $%s - have fun!'):format(Config.club_price or 0))
end

-- E at the rental -> start card -> Start
RegisterNetEvent("mrw_minigolf:requestStart")
AddEventHandler("mrw_minigolf:requestStart", function(invite)
    local src, now = source, GetGameTimer()
    if lastPress[src] and now - lastPress[src] < 3000 then return end
    lastPress[src] = now

    if PlayerGroup[src] or not nearRental(src) then return end

    if not charge(src, Config.club_price or 0) then
        return notify(src, translation["no_money"])
    end

    nextGroup = nextGroup + 1
    local gid = nextGroup
    Groups[gid] = { host = src, players = {}, order = {} }
    addToGroup(gid, src)
    startGame(src)
    broadcast(gid)

    -- invites, checked server side: nearby, not already playing, group not full
    local sent, maxGroup = 0, Config.max_group or 4
    if type(invite) == 'table' then
        local hostPed = GetPlayerPed(src)
        local hostPos = GetEntityCoords(hostPed)
        for _, t in ipairs(invite) do
            t = tonumber(t)
            if t and t ~= src and GetPlayerPing(t) > 0 and not PlayerGroup[t]
                and 1 + sent < maxGroup then
                local ped = GetPlayerPed(t)
                if ped and ped ~= 0 and #(GetEntityCoords(ped) - hostPos) <= (Config.invite_range or 8.0) + 4.0 then
                    Invites[t] = { gid = gid, from = src, expires = now + 30000 }
                    TriggerClientEvent('mrw_minigolf:invited', t, nameOf(src), Config.club_price or 0, 30)
                    sent = sent + 1
                end
            end
        end
    end
    if sent > 0 then
        notify(src, (translation['invites_sent'] or 'Invited %s player(s)'):format(sent))
    end
end)

RegisterNetEvent("mrw_minigolf:inviteAnswer")
AddEventHandler("mrw_minigolf:inviteAnswer", function(accept)
    local src = source
    local inv = Invites[src]
    Invites[src] = nil
    if not inv then return end

    local g = Groups[inv.gid]
    if not accept then
        if g then notify(inv.from, (translation['invite_declined'] or '%s declined'):format(nameOf(src))) end
        return
    end

    if GetGameTimer() > inv.expires or not g then
        return notify(src, translation['invite_expired'] or 'That invite expired')
    end
    if PlayerGroup[src] or not nearRental(src, 25.0) then return end

    if not charge(src, Config.club_price or 0) then
        return notify(src, translation["no_money"])
    end

    addToGroup(inv.gid, src)
    startGame(src)
    notify(inv.from, (translation['invite_joined'] or '%s joined the game'):format(nameOf(src)))
    broadcast(inv.gid)
end)

RegisterNetEvent("mrw_minigolf:score")
AddEventHandler("mrw_minigolf:score", function(hole, strokes)
    local src = source
    local g = Groups[PlayerGroup[src] or -1]
    if not g then return end
    hole, strokes = tonumber(hole), tonumber(strokes)
    if not hole or hole < 1 or hole > HOLES or not strokes then return end
    g.players[src].strokes[hole] = math.max(0, math.min(math.floor(strokes), Config.max_stroke or 10))
    broadcast(PlayerGroup[src])
end)

RegisterNetEvent("mrw_minigolf:finished")
AddEventHandler("mrw_minigolf:finished", function()
    leaveGroup(source, 'done')
end)

RegisterNetEvent("mrw_minigolf:leave")
AddEventHandler("mrw_minigolf:leave", function()
    leaveGroup(source, 'quit')
end)

AddEventHandler('playerDropped', function()
    local src = source
    lastPress[src], Invites[src] = nil, nil
    leaveGroup(src, 'quit')
end)
