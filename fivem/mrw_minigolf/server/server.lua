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
    print(('[mrw_minigolf] framework: %s, %d ticket types'):format(Framework, #(Config.tickets or {})))

    -- qb-inventory style: using the scorecard item opens it
    local item = Config.scorecard_item
    if Framework == 'qb' and item and item.enabled then
        QBCore.Functions.CreateUseableItem(item.name, function(source, it)
            TriggerClientEvent('mrw_minigolf:viewCard', source, it and (it.info or it.metadata) or nil)
        end)
    end
end)

--- The ticket a player picked, if they are allowed to buy it.
local function ticketFor(src, id)
    for _, t in ipairs(Config.tickets or {}) do
        if t.id == id then
            if t.jobs then
                local job
                if Framework == 'qb' then
                    local P = QBCore.Functions.GetPlayer(src)
                    job = P and P.PlayerData.job and P.PlayerData.job.name
                elseif Framework == 'esx' then
                    local x = ESX.GetPlayerFromId(src)
                    job = x and x.job and x.job.name
                end
                local ok = false
                for _, j in ipairs(t.jobs) do if j == job then ok = true break end end
                if not ok then return nil end
            end
            return t
        end
    end
    return nil
end

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

local function addToGroup(gid, src, ticket)
    local g = Groups[gid]
    local strokes = {}
    for i = 1, HOLES do strokes[i] = 0 end
    g.players[src] = {
        name = nameOf(src), strokes = strokes, status = 'playing', ticket = ticket.label,
        ball = nil,       -- where their ball rests on the current hole (nil = on the tee)
        holed = false     -- done with the current hole
    }
    g.order[#g.order + 1] = src
    PlayerGroup[src] = gid
end

-- ---------------------------------------------------------------------------
-- turns: the ball farthest from the cup plays next, like real golf.
-- Ties (everyone on the tee) go in the order people joined.
-- ---------------------------------------------------------------------------
local function totalOf(p)
    local t = 0
    for i = 1, HOLES do t = t + (p.strokes[i] or 0) end
    return t
end

local function tellGroup(g, event, ...)
    for _, m in ipairs(g.order) do
        if g.players[m].status == 'playing' then TriggerClientEvent(event, m, ...) end
    end
end

local nextTurn

local function finishHoleFor(gid, src, reason)
    local g = Groups[gid]
    local p = g.players[src]
    p.holed, p.ball = true, nil
    TriggerClientEvent('mrw_minigolf:holeDone', src, p.strokes[g.hole] or 0, reason)
end

nextTurn = function(gid)
    local g = Groups[gid]
    if not g then return end
    local t = Config.golf_track[g.hole]

    -- farthest from the cup first; about level (within half a metre, e.g. both on
    -- the tee) -> whoever has taken fewer strokes on this hole, then join order
    local best, bestDist, bestStrokes
    for _, m in ipairs(g.order) do
        local p = g.players[m]
        if p.status == 'playing' and not p.holed then
            local b = p.ball or t.start
            local d = #(vector3(b.x, b.y, b.z) - t.hole)
            local st = p.strokes[g.hole] or 0
            if not best
                or d > bestDist + 0.5
                or (math.abs(d - bestDist) <= 0.5 and st < bestStrokes) then
                best, bestDist, bestStrokes = m, d, st
            end
        end
    end

    if best then
        g.turn, g.turnStarted, g.awaiting = best, GetGameTimer(), false
        tellGroup(g, 'mrw_minigolf:turn', best, g.players[best].name, g.hole)
        return
    end

    -- everyone is done with this hole
    g.turn = nil
    local anyone = false
    for _, m in ipairs(g.order) do
        if g.players[m].status == 'playing' then anyone = true break end
    end
    if not anyone then return end

    if g.hole >= HOLES then
        for _, m in ipairs(g.order) do
            local p = g.players[m]
            if p.status == 'playing' then TriggerClientEvent('mrw_minigolf:groupFinished', m, totalOf(p)) end
        end
        return
    end

    g.hole = g.hole + 1
    for _, m in ipairs(g.order) do
        g.players[m].holed, g.players[m].ball = false, nil
    end
    tellGroup(g, 'mrw_minigolf:newHole', g.hole)
    SetTimeout(1500, function() nextTurn(gid) end)   -- give everyone a moment to spawn the new ball
end

-- the player whose turn it is hit the ball
RegisterNetEvent("mrw_minigolf:shot")
AddEventHandler("mrw_minigolf:shot", function(hole)
    local src = source
    local gid = PlayerGroup[src]
    local g = gid and Groups[gid]
    if not g or g.turn ~= src or g.awaiting or tonumber(hole) ~= g.hole then return end

    local p = g.players[src]
    p.strokes[g.hole] = math.min((p.strokes[g.hole] or 0) + 1, Config.max_stroke or 10)
    g.awaiting, g.turnStarted = true, GetGameTimer()
    broadcast(gid)
end)

-- where the ball stopped
RegisterNetEvent("mrw_minigolf:ballState")
AddEventHandler("mrw_minigolf:ballState", function(hole, result, pos)
    local src = source
    local gid = PlayerGroup[src]
    local g = gid and Groups[gid]
    if not g or g.turn ~= src or not g.awaiting or tonumber(hole) ~= g.hole then return end
    g.awaiting = false

    local p = g.players[src]
    local t = Config.golf_track[g.hole]

    if result == 'holed' then
        finishHoleFor(gid, src, 'holed')
    else
        if result == 'out' or type(pos) ~= 'table' or not tonumber(pos.x) then
            p.ball = nil                                    -- back on the tee
        else
            local b = vector3(tonumber(pos.x), tonumber(pos.y), tonumber(pos.z) or t.start.z)
            p.ball = #(b - t.hole) < 80.0 and b or nil      -- nonsense positions go back to the tee
        end
        if (p.strokes[g.hole] or 0) >= (Config.max_stroke or 10) then
            finishHoleFor(gid, src, 'max')
        end
    end

    broadcast(gid)
    nextTurn(gid)
end)

-- nobody holds the group up: a turn that sits too long is scored at the limit
CreateThread(function()
    while true do
        Wait(5000)
        local now = GetGameTimer()
        for gid, g in pairs(Groups) do
            if g.turn then
                local playing = 0
                for _, m in ipairs(g.order) do
                    if g.players[m].status == 'playing' then playing = playing + 1 end
                end
                local limit = (g.awaiting and 30 or (Config.turn_seconds or 90)) * 1000
                if playing > 1 and now - (g.turnStarted or now) > limit then
                    local src = g.turn
                    local p = g.players[src]
                    g.awaiting = false
                    p.strokes[g.hole] = Config.max_stroke or 10
                    finishHoleFor(gid, src, 'timeout')
                    for _, m in ipairs(g.order) do
                        if m ~= src and g.players[m].status == 'playing' then
                            notify(m, (translation['group_timeout'] or '%s ran out of time on this hole'):format(p.name))
                        end
                    end
                    broadcast(gid)
                    nextTurn(gid)
                end
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- scorecards: built from the server's own record, so they can't be faked
-- ---------------------------------------------------------------------------
local PendingCard = {}   -- [src] = card they can still choose to keep

local function sumStrokes(strokes)
    local total, played = 0, 0
    for i = 1, HOLES do
        local v = strokes[i] or 0
        total = total + v
        if v > 0 then played = played + 1 end
    end
    return total, played
end

local function buildCard(g, src)
    local p = g.players[src]
    local total, played = sumStrokes(p.strokes)
    local list, others = {}, {}
    for i = 1, HOLES do list[i] = tostring(p.strokes[i] or 0) end
    for _, m in ipairs(g.order) do
        if m ~= src then
            local o = g.players[m]
            local t = sumStrokes(o.strokes)
            others[#others + 1] = ('%s: %d%s'):format(o.name, t, o.status == 'quit' and ' (left)' or '')
        end
    end
    local date = os.date('%b %d, %Y')
    return {
        course   = Config.course_name or 'Minigolf',
        name     = p.name,
        date     = date,
        ticket   = p.ticket,
        strokes  = table.concat(list, ','),   -- plain string: safe in any inventory's metadata
        total    = total,
        holes    = HOLES,
        played   = played,
        finished = p.status == 'done',
        group    = table.concat(others, '; '),
        description = ('%s - %d strokes over %d holes%s'):format(date, total, played,
            p.status == 'done' and '' or ' (left early)')
    }
end

local function inventoryType()
    local want = (Config.scorecard_item and Config.scorecard_item.inventory) or 'auto'
    if want == 'tgiann' or (want == 'auto' and GetResourceState('tgiann-inventory') == 'started') then return 'tgiann' end
    if want == 'ox' or (want == 'auto' and GetResourceState('ox_inventory') == 'started') then return 'ox' end
    if want == 'qb' or (want == 'auto' and Framework == 'qb') then return 'qb' end
    return nil
end

local function giveCard(src, card)
    local item = Config.scorecard_item
    if not (item and item.enabled) then return false end
    local inv, ok = inventoryType(), false

    if inv == 'tgiann' then
        ok = pcall(function() ok = exports['tgiann-inventory']:AddItem(src, item.name, 1, nil, card) end) and ok
    elseif inv == 'ox' then
        ok = pcall(function() ok = exports.ox_inventory:AddItem(src, item.name, 1, card) end) and ok
    elseif inv == 'qb' and QBCore then
        local Player = QBCore.Functions.GetPlayer(src)
        if Player then
            ok = Player.Functions.AddItem(item.name, 1, false, card) ~= false
            if ok and QBCore.Shared.Items[item.name] then
                TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[item.name], 'add')
            end
        end
    end
    return ok and true or false
end

RegisterNetEvent("mrw_minigolf:keepCard")
AddEventHandler("mrw_minigolf:keepCard", function()
    local src = source
    local card = PendingCard[src]
    PendingCard[src] = nil
    if not card then return end
    if giveCard(src, card) then
        notify(src, translation['card_saved'] or 'Scorecard saved to your inventory')
    else
        notify(src, translation['card_failed'] or "Couldn't save the scorecard - inventory full or item missing")
    end
end)

--- player is done with the game (finished, quit or left the server)
local function leaveGroup(src, status)
    local gid = PlayerGroup[src]
    PlayerGroup[src] = nil
    local g = gid and Groups[gid]
    if not g or not g.players[src] then return end

    g.players[src].status = status

    -- show them their card and let them keep it
    if status ~= 'dropped' then
        local card = buildCard(g, src)
        PendingCard[src] = card
        TriggerClientEvent('mrw_minigolf:finalCard', src, card,
            Config.scorecard_item and Config.scorecard_item.enabled or false)
    end
    if status == 'dropped' then g.players[src].status = 'quit' status = 'quit' end
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
    if not anyone then Groups[gid] = nil return end

    broadcast(gid)
    if g.turn == src then nextTurn(gid) end
end

local function startGame(src, ticket, hole)
    TriggerClientEvent("mrw_minigolf:st_game", src, hole or 1)
    notify(src, (translation['game_started'] or 'Clubs rented for $%s - have fun!'):format(ticket.price))
end

-- E at the rental -> start card -> Start
RegisterNetEvent("mrw_minigolf:requestStart")
AddEventHandler("mrw_minigolf:requestStart", function(invite, ticketId)
    local src, now = source, GetGameTimer()
    if lastPress[src] and now - lastPress[src] < 3000 then return end
    lastPress[src] = now

    if PlayerGroup[src] or not nearRental(src) then return end

    local ticket = ticketFor(src, ticketId)
    if not ticket then
        return notify(src, translation['ticket_denied'] or "You can't buy that ticket")
    end
    if not charge(src, ticket.price) then
        return notify(src, translation["no_money"])
    end

    nextGroup = nextGroup + 1
    local gid = nextGroup
    Groups[gid] = { host = src, players = {}, order = {}, hole = 1 }
    addToGroup(gid, src, ticket)
    startGame(src, ticket, 1)
    broadcast(gid)
    SetTimeout(1500, function() nextTurn(gid) end)

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
                    TriggerClientEvent('mrw_minigolf:invited', t, nameOf(src), 30)
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
AddEventHandler("mrw_minigolf:inviteAnswer", function(accept, ticketId)
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

    local ticket = ticketFor(src, ticketId)
    if not ticket then
        return notify(src, translation['ticket_denied'] or "You can't buy that ticket")
    end
    if not charge(src, ticket.price) then
        return notify(src, translation["no_money"])
    end

    addToGroup(inv.gid, src, ticket)
    startGame(src, ticket, g.hole)
    notify(inv.from, (translation['invite_joined'] or '%s joined the game'):format(nameOf(src)))
    broadcast(inv.gid)
    SetTimeout(1500, function()
        local gg = Groups[inv.gid]
        if not gg or not gg.players[src] then return end
        if gg.turn then
            TriggerClientEvent('mrw_minigolf:turn', src, gg.turn, gg.players[gg.turn].name, gg.hole)
        else
            nextTurn(inv.gid)
        end
    end)
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
    lastPress[src], Invites[src], PendingCard[src] = nil, nil, nil
    leaveGroup(src, 'dropped')
end)
