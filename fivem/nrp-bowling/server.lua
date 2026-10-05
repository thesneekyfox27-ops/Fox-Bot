-- ============================================================
--  nrp-bowling - server
--  Bookings (price sheet), lanes, invites, turns and scoring.
--  The bowler's client rolls the ball and reports how many pins
--  fell; the server checks it's their turn and that it's possible.
-- ============================================================

local QBCore = exports['qb-core']:GetCoreObject()

local lanes      = {}   -- [id] = lane
local playerLane = {}   -- [src] = lane id
local bookings   = {}   -- [src] = { games, seats, prepaid, ticket, invite = {ids}, paid, expires }
local invites    = {}   -- [src] = { lane, from, expires }

local function notify(src, msg, kind)
    TriggerClientEvent('QBCore:Notify', src, msg, kind or 'primary')
end

local function nameOf(src)
    local P = QBCore.Functions.GetPlayer(src)
    if not P then return GetPlayerName(src) or ('Player ' .. src) end
    local ci = P.PlayerData.charinfo or {}
    return ('%s %s.'):format(ci.firstname or '?', (ci.lastname or '?'):sub(1, 1))
end

-- the payment method the player picked (cash / card); anything else -> the default
local function payMethod(m)
    for _, pm in ipairs(Config.PayMethods) do if pm.id == m then return pm end end
    for _, pm in ipairs(Config.PayMethods) do if pm.id == Config.Account then return pm end end
    return Config.PayMethods[1]
end

-- charge from the chosen account only; returns the account used, or nil + a reason
local function charge(src, amount, why, method)
    local pm = payMethod(method)
    if amount <= 0 then return pm.id end
    local P = QBCore.Functions.GetPlayer(src)
    if not P then return nil end
    if P.Functions.GetMoney(pm.id) < amount then
        return nil, ('Not enough %s - that costs $%d.'):format(pm.id == 'bank' and 'in the bank' or 'cash', amount)
    end
    if P.Functions.RemoveMoney(pm.id, amount, why or 'bowling') then return pm.id end
    return nil
end

local function refund(src, amount, account)
    local P = QBCore.Functions.GetPlayer(src)
    if P and amount > 0 then P.Functions.AddMoney(account or Config.Account, amount, 'bowling-refund') end
end

local function coordsOf(src)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and GetEntityCoords(ped) or nil
end

-- ------------------------------------------------------------
--  Staff ped position (admins move her in game with /bowlstaff;
--  saved to staff.json so it survives restarts)
-- ------------------------------------------------------------
-- Saved spots live in the server's resource KVP store, which survives restarts
-- AND replacing the resource folder with a new zip. The .json file is a backup
-- copy (and is read once to migrate older saves).
local function loadSaved(key, file)
    local raw = GetResourceKvpString(key)
    if not raw or raw == '' then raw = LoadResourceFile(GetCurrentResourceName(), file) end
    local ok, d = pcall(json.decode, raw or '')
    if ok and type(d) == 'table' then return d end
end

local function saveSpot(key, file, data)
    local raw = json.encode(data)
    SetResourceKvp(key, raw)
    SaveResourceFile(GetCurrentResourceName(), file, raw, -1)
end

local STAFF_FILE = 'staff.json'
local staffPos = Config.Staff.coords

do
    local d = loadSaved('staff', STAFF_FILE)
    if d and d.x then staffPos = vector4(d.x, d.y, d.z, d.w or 0.0) end
end

local function staffPayload() return { x = staffPos.x, y = staffPos.y, z = staffPos.z, w = staffPos.w } end

RegisterNetEvent('nrp-bowling:staffPos', function()
    TriggerClientEvent('nrp-bowling:staffPos', source, staffPayload())
end)

local function isAdmin(src)
    return src == 0 or QBCore.Functions.HasPermission(src, 'admin') or QBCore.Functions.HasPermission(src, 'god')
        or IsPlayerAceAllowed(src, 'command')
end

RegisterCommand('bowlstaff', function(src)
    if src == 0 or not isAdmin(src) then return end
    local ped = GetPlayerPed(src)
    local c = GetEntityCoords(ped)
    staffPos = vector4(c.x, c.y, c.z, (GetEntityHeading(ped) + 180.0) % 360.0)   -- she faces you
    saveSpot('staff', STAFF_FILE, staffPayload())
    TriggerClientEvent('nrp-bowling:staffPos', -1, staffPayload())
    notify(src, 'Bowling staff moved here and saved. She faces the way you came from.', 'success')
end, false)

-- ------------------------------------------------------------
--  Ball return spots (where you grab your ball). Admins stand at
--  a lane's ball return and type /bowlreturn [lane]; saved to
--  returns.json. Lanes without one use Config / an auto guess.
-- ------------------------------------------------------------
local RETURN_FILE = 'returns.json'
local returns = {}

do
    local d = loadSaved('returns', RETURN_FILE)
    if d then
        for k, v in pairs(d) do
            local id = tonumber(k)
            if id and type(v) == 'table' and v.x then returns[id] = { x = v.x, y = v.y, z = v.z } end
        end
    end
end

local function returnsPayload()
    local out = {}
    for id, v in pairs(returns) do out[tostring(id)] = v end
    return out
end

RegisterNetEvent('nrp-bowling:returns', function()
    TriggerClientEvent('nrp-bowling:returns', source, returnsPayload())
end)

RegisterCommand('bowlreturn', function(src, args)
    if src == 0 or not isAdmin(src) then return end
    local c = GetEntityCoords(GetPlayerPed(src))
    local id = tonumber(args[1])
    if not id then   -- no number: the lane whose stand spot is closest
        local best
        for i, L in ipairs(Config.Lanes) do
            local d = #(c - vector3(L.approach.x, L.approach.y, L.approach.z))
            if not best or d < best then best, id = d, i end
        end
    end
    if not Config.Lanes[id] then return notify(src, 'No such lane.', 'error') end
    returns[id] = { x = c.x, y = c.y, z = c.z - 1.0 }   -- floor height
    saveSpot('returns', RETURN_FILE, returnsPayload())
    TriggerClientEvent('nrp-bowling:returns', -1, returnsPayload())
    notify(src, ('Ball return for lane %d set here and saved.'):format(id), 'success')
end, false)

local function nearStaff(src)
    local c, s = coordsOf(src), staffPos
    return c and #(c - vector3(s.x, s.y, s.z)) < 6.0
end

local function approachOf(id)
    local a = Config.Lanes[id].approach
    return vector3(a.x, a.y, a.z)
end

local function ticketById(id)
    for _, t in ipairs(Config.Tickets) do if t.id == id then return t end end
    return Config.Tickets[1]
end

local function playerIndex(lane, src)
    for i, p in ipairs(lane.players) do if p.src == src then return i end end
end

-- ------------------------------------------------------------
--  Score sheet -> everyone on the lane
-- ------------------------------------------------------------
local function view(lane)
    local players = {}
    for i, p in ipairs(lane.players) do
        local card, total = Scoring.card(p.rolls, Config.Frames)
        local st = Scoring.state(p.rolls, Config.Frames)
        players[i] = {
            src = p.src, name = p.name, frames = card, total = total,
            max = Scoring.maxPossible(p.rolls, Config.Frames),
            done = st.done == true, owner = p.src == lane.owner,
        }
    end
    local cur = lane.players[lane.turn]
    return {
        id = lane.id, status = lane.status, frames = Config.Frames,
        game = lane.gameNo, games = lane.games,
        players = players, turn = cur and cur.src or nil,
        frame = cur and Scoring.state(cur.rolls, Config.Frames).frame or nil,
        last = lane.last, maxPlayers = lane.seats or Config.MaxPlayers,
    }
end

local function broadcast(lane)
    local v = view(lane)
    for _, p in ipairs(lane.players) do TriggerClientEvent('nrp-bowling:lane', p.src, v) end
end

local function banner(lane, name, text, extra)
    lane.seq = (lane.seq or 0) + 1
    lane.last = { name = name, text = text, seq = lane.seq }
    if extra then for k, v in pairs(extra) do lane.last[k] = v end end
end

local function freeLane(id)
    local lane = lanes[id]
    if not lane then return end
    for _, p in ipairs(lane.players) do
        playerLane[p.src] = nil
        TriggerClientEvent('nrp-bowling:left', p.src)
    end
    for src, inv in pairs(invites) do
        if inv.lane == id then invites[src] = nil; TriggerClientEvent('nrp-bowling:inviteGone', src) end
    end
    lanes[id] = nil
end

local function startTurn(lane)
    local cur = lane.players[lane.turn]
    if not cur then return end
    local st = Scoring.state(cur.rolls, Config.Frames)
    lane.turnStarted = os.time()
    TriggerClientEvent('nrp-bowling:yourTurn', cur.src, lane.id, {
        frame = st.frame, roll = st.roll, standing = st.standing, reset = st.reset,
    })
    broadcast(lane)
end

local function finishGame(lane)
    local best, winners = -1, {}
    for _, p in ipairs(lane.players) do
        local t = Scoring.total(p.rolls, Config.Frames)
        if t > best then best, winners = t, { p.name } elseif t == best then winners[#winners + 1] = p.name end
    end
    local nameList = table.concat(winners, ' & ')

    if lane.gameNo < lane.games then
        -- next game of the session
        banner(lane, nameList, ('WINS GAME %d WITH %d'):format(lane.gameNo, best), { final = true })
        lane.status = 'between'
        broadcast(lane)
        local id = lane.id
        SetTimeout(7000, function()
            if lanes[id] ~= lane then return end
            lane.gameNo = lane.gameNo + 1
            for _, p in ipairs(lane.players) do p.rolls = {} end
            lane.status, lane.turn = 'playing', 1
            banner(lane, ('LANE %d'):format(id), ('GAME %d'):format(lane.gameNo))
            startTurn(lane)
        end)
        return
    end

    lane.status = 'done'
    banner(lane, nameList, ('WINS WITH %d'):format(best), { final = true })
    broadcast(lane)
    local id = lane.id
    SetTimeout(15000, function() if lanes[id] == lane then freeLane(id) end end)
end

-- everyone bowls frame f before anyone bowls f+1
local function nextTurn(lane)
    local n = #lane.players
    if n == 0 then return freeLane(lane.id) end
    local function framesDone(p)
        local st = Scoring.state(p.rolls, Config.Frames)
        if st.done then return Config.Frames + 1 end
        return st.frame - 1
    end
    local bestIdx, bestDone
    for step = 1, n do
        local idx = ((lane.turn - 1 + step) % n) + 1
        local d = framesDone(lane.players[idx])
        if d <= Config.Frames and (bestDone == nil or d < bestDone) then bestIdx, bestDone = idx, d end
    end
    if not bestIdx then return finishGame(lane) end
    lane.turn = bestIdx
    startTurn(lane)
end

local function removePlayer(src, why)
    local id = playerLane[src]
    local lane = id and lanes[id]
    playerLane[src] = nil
    if not lane then return end
    local idx = playerIndex(lane, src)
    if not idx then return end
    local wasTurn = lane.status == 'playing' and idx == lane.turn
    table.remove(lane.players, idx)
    TriggerClientEvent('nrp-bowling:left', src)
    if why then notify(src, why, 'error') end

    if #lane.players == 0 then return freeLane(id) end
    if lane.owner == src then lane.owner = lane.players[1].src end
    if lane.status == 'playing' then
        if idx < lane.turn then lane.turn = lane.turn - 1 end
        if wasTurn then
            lane.turn = lane.turn - 1
            if lane.turn < 1 then lane.turn = #lane.players end
            return nextTurn(lane)
        end
    end
    broadcast(lane)
end

local function addToLane(lane, src)
    lane.players[#lane.players + 1] = { src = src, name = nameOf(src), rolls = {} }
    playerLane[src] = lane.id
    TriggerClientEvent('nrp-bowling:joined', src, lane.id)
    broadcast(lane)
end

-- ------------------------------------------------------------
--  Price sheet: what's on offer + who's nearby to invite
-- ------------------------------------------------------------
QBCore.Functions.CreateCallback('nrp-bowling:menu', function(src, cb)
    local me = coordsOf(src)
    local nearby = {}
    if me then
        for _, id in ipairs(QBCore.Functions.GetPlayers()) do
            if id ~= src and not playerLane[id] then
                local c = coordsOf(id)
                if c and #(c - me) <= Config.InviteRange then
                    nearby[#nearby + 1] = { id = id, name = nameOf(id) }
                end
            end
        end
    end
    cb({
        name = Config.AlleyName, tickets = Config.Tickets, gameDeals = Config.GameDeals,
        familyDeals = Config.FamilyDeals, maxPlayers = Config.MaxPlayers, nearby = nearby,
        payMethods = Config.PayMethods, defaultPay = payMethod(Config.Account).id,
        onLane = playerLane[src], booked = bookings[src] ~= nil,
    })
end)

local function freeLanes()
    local list = {}
    for id = 1, #Config.Lanes do
        local lane = lanes[id]
        list[id] = { id = id, status = lane and lane.status or 'free', players = lane and #lane.players or 0 }
    end
    return list
end

-- buy: { kind = 'ticket'|'game'|'family', ticket = 'adult', games = 1|2, players = n, invite = {ids} }
RegisterNetEvent('nrp-bowling:buy', function(order)
    local src = source
    if type(order) ~= 'table' then return end
    if playerLane[src] then return notify(src, 'You already have a lane.', 'error') end
    if bookings[src] then return TriggerClientEvent('nrp-bowling:pickLane', src, freeLanes()) end
    if not nearStaff(src) then return end

    local price, games, seats, prepaid, label
    if order.kind == 'game' then
        for _, d in ipairs(Config.GameDeals) do
            if d.players == tonumber(order.players) then price, games, seats, prepaid = d.price, 2, d.players, true end
        end
        label = ('%d player game deal'):format(seats or 0)
    elseif order.kind == 'family' then
        for _, d in ipairs(Config.FamilyDeals) do
            if d.players == tonumber(order.players) then price, games, seats, prepaid = d.price, 1, d.players, true end
        end
        label = ('family of %d deal'):format(seats or 0)
    else
        local t = ticketById(order.ticket)
        games = (tonumber(order.games) == 2) and 2 or 1
        price, seats, prepaid = t.prices[games], Config.MaxPlayers, false
        label = ('%s ticket, %d game%s'):format(t.label:lower(), games, games == 2 and 's' or '')
    end
    if not price then return end

    -- invitees: valid, nearby, not busy, and no more than the seats left
    local inv, seen = {}, {}
    local me = coordsOf(src)
    for _, id in ipairs(type(order.invite) == 'table' and order.invite or {}) do
        id = tonumber(id)
        if id and id ~= src and not seen[id] and not playerLane[id] and #inv < seats - 1 then
            local c = coordsOf(id)
            if c and me and #(c - me) <= Config.InviteRange * 1.5 then inv[#inv + 1] = id; seen[id] = true end
        end
    end

    -- group deals need the group: every seat must have an invited friend
    if prepaid and #inv < seats - 1 then
        return notify(src, ('Invite %d more friend%s nearby to buy this deal.'):format(seats - 1 - #inv, (seats - 1 - #inv) == 1 and '' or 's'), 'error')
    end

    local account, why = charge(src, price, 'bowling-' .. (order.kind or 'ticket'), order.pay)
    if not account then
        return notify(src, why or ('That costs $%d.'):format(price), 'error')
    end
    bookings[src] = {
        games = games, seats = seats, prepaid = prepaid, ticket = order.ticket, account = account,
        invite = inv, paid = price, label = label, expires = os.time() + Config.BookingSeconds,
    }
    notify(src, ('Paid $%d by %s - %s. Pick your lane.'):format(price, payMethod(account).label:lower(), label), 'success')
    TriggerClientEvent('nrp-bowling:pickLane', src, freeLanes())
end)

-- choose a lane (or 'auto') after paying
RegisterNetEvent('nrp-bowling:chooseLane', function(id)
    local src = source
    local b = bookings[src]
    if not b or playerLane[src] then return end

    if id == 'auto' then
        id = nil
        for i = 1, #Config.Lanes do if not lanes[i] then id = i; break end end
        if not id then return notify(src, 'Every lane is busy right now - you can wait or cancel for a refund.', 'error') end
    else
        id = tonumber(id)
        if not id or not Config.Lanes[id] then return end
        if lanes[id] then
            notify(src, ('Lane %d was just taken - pick another.'):format(id), 'error')
            return TriggerClientEvent('nrp-bowling:pickLane', src, freeLanes())
        end
    end

    bookings[src] = nil
    local lane = {
        id = id, status = 'lobby', owner = src, players = {},
        games = b.games, gameNo = 1, seats = b.seats, prepaid = b.prepaid,
        seatsPaid = b.prepaid and (b.seats - 1) or 0, ticket = b.ticket,
        turn = 1, turnStarted = 0,
    }
    lanes[id] = lane
    addToLane(lane, src)
    notify(src, ('Lane %d is yours! Press G at the lane when everyone is ready.'):format(id), 'success')

    local hostName = nameOf(src)
    for _, other in ipairs(b.invite) do
        if not playerLane[other] then
            invites[other] = { lane = id, from = src, expires = os.time() + Config.InviteSeconds }
            local t = ticketById(b.ticket)
            TriggerClientEvent('nrp-bowling:invited', other, {
                host = hostName, lane = id, games = b.games, prepaid = b.prepaid,
                tickets = (not b.prepaid) and Config.Tickets or nil,
                payMethods = (not b.prepaid) and Config.PayMethods or nil, defaultPay = payMethod(Config.Account).id,
                seconds = Config.InviteSeconds, defaultTicket = t.id,
            })
        end
    end
end)

RegisterNetEvent('nrp-bowling:cancelBooking', function()
    local src = source
    local b = bookings[src]
    if not b then return end
    bookings[src] = nil
    refund(src, b.paid, b.account)
    notify(src, ('Refunded $%d.'):format(b.paid), 'primary')
end)

-- answer an invite: prepaid deals are free, otherwise pay your own ticket
RegisterNetEvent('nrp-bowling:inviteAnswer', function(accept, ticketId, pay)
    local src = source
    local inv = invites[src]
    invites[src] = nil
    if not inv then return end
    local lane = lanes[inv.lane]
    if not accept then
        if lane then notify(inv.from, ('%s passed on bowling.'):format(nameOf(src)), 'primary') end
        return
    end
    if not lane or lane.status ~= 'lobby' then return notify(src, 'That lane already started.', 'error') end
    if playerLane[src] then return end
    if #lane.players >= (lane.seats or Config.MaxPlayers) then return notify(src, 'That lane is full.', 'error') end

    if lane.prepaid and lane.seatsPaid > 0 then
        lane.seatsPaid = lane.seatsPaid - 1
    else
        local t = ticketById(ticketId)
        local price = t.prices[lane.games] or t.prices[1]
        local account, why = charge(src, price, 'bowling-ticket', pay)
        if not account then
            return notify(src, why or ('A %s ticket is $%d.'):format(t.label:lower(), price), 'error')
        end
    end
    addToLane(lane, src)
    notify(src, ('Shoes on! Head to lane %d.'):format(lane.id), 'success')
    notify(lane.owner, ('%s joined your lane.'):format(nameOf(src)), 'success')
end)

-- ------------------------------------------------------------
--  Start / leave
-- ------------------------------------------------------------
RegisterNetEvent('nrp-bowling:start', function()
    local src = source
    local lane = lanes[playerLane[src] or -1]
    if not lane or lane.status ~= 'lobby' or lane.owner ~= src then return end
    local c = coordsOf(src)
    if not c or #(c - approachOf(lane.id)) > 8.0 then
        return notify(src, 'Walk over to your lane to start.', 'error')
    end
    lane.status, lane.turn = 'playing', 1
    for o, inv in pairs(invites) do
        if inv.lane == lane.id then invites[o] = nil; TriggerClientEvent('nrp-bowling:inviteGone', o) end
    end
    banner(lane, ('LANE %d'):format(lane.id), lane.games > 1 and 'GAME 1' or "LET'S BOWL!")
    startTurn(lane)
end)

RegisterNetEvent('nrp-bowling:leave', function() removePlayer(source) end)

-- ------------------------------------------------------------
--  A ball was bowled
-- ------------------------------------------------------------
RegisterNetEvent('nrp-bowling:roll', function(knocked)
    local src = source
    local lane = lanes[playerLane[src] or -1]
    if not lane or lane.status ~= 'playing' then return end
    local cur = lane.players[lane.turn]
    if not cur or cur.src ~= src then return end

    local st = Scoring.state(cur.rolls, Config.Frames)
    if st.done then return end
    knocked = math.floor(tonumber(knocked) or 0)
    if knocked < 0 then knocked = 0 end
    if knocked > st.standing then knocked = st.standing end

    cur.rolls[#cur.rolls + 1] = knocked
    local call = Scoring.callout(st.standing, knocked)
    banner(lane, cur.name, call, { knocked = knocked })
    if call == 'STRIKE!' then TriggerClientEvent('nrp-bowling:sfx', -1, 'strike', lane.id)
    elseif call == 'SPARE!' then TriggerClientEvent('nrp-bowling:sfx', -1, 'spare', lane.id) end

    local after = Scoring.state(cur.rolls, Config.Frames)
    if after.done or after.frame ~= st.frame then
        TriggerClientEvent('nrp-bowling:turnOver', src)
        nextTurn(lane)
    else
        startTurn(lane)
    end
end)

-- the bowler's ball sounds -> everyone (each client checks if they're close enough)
local lastSfx = {}
RegisterNetEvent('nrp-bowling:sfx', function(kind)
    local src = source
    if kind ~= 'release' and kind ~= 'pins' then return end
    local id = playerLane[src]
    local lane = id and lanes[id]
    local cur = lane and lane.status == 'playing' and lane.players[lane.turn]
    if not cur or cur.src ~= src then return end
    local now = GetGameTimer()
    if lastSfx[src] and now - lastSfx[src] < 400 then return end
    lastSfx[src] = now
    TriggerClientEvent('nrp-bowling:sfx', -1, kind, id, src)
end)

AddEventHandler('playerDropped', function() lastSfx[source] = nil end)

-- ------------------------------------------------------------
--  Housekeeping: AFK, walked away, expired bookings/invites
-- ------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(5000)
        local now = os.time()
        for id, lane in pairs(lanes) do
            for i = #lane.players, 1, -1 do
                local p = lane.players[i]
                local c = coordsOf(p.src)
                if not c then
                    removePlayer(p.src)
                elseif #(c - approachOf(id)) > Config.LeaveDistance then
                    removePlayer(p.src, 'You left the bowling alley - your game ended.')
                end
            end
            local cur = lanes[id] and lane.status == 'playing' and lane.players[lane.turn]
            if cur and now - lane.turnStarted > Config.TurnTimeout then
                removePlayer(cur.src, 'You took too long to bowl and were removed from the lane.')
            end
        end
        for src, b in pairs(bookings) do
            if now > b.expires then
                bookings[src] = nil
                refund(src, b.paid, b.account)
                notify(src, ('You didn\'t pick a lane - refunded $%d.'):format(b.paid), 'primary')
                TriggerClientEvent('nrp-bowling:closeMenu', src)
            end
        end
        for src, inv in pairs(invites) do
            if now > inv.expires then invites[src] = nil; TriggerClientEvent('nrp-bowling:inviteGone', src) end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    removePlayer(src)
    bookings[src], invites[src] = nil, nil
end)
