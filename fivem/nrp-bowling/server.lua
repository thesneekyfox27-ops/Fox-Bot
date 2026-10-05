-- ============================================================
--  nrp-bowling - server
--  Lanes, players, turns and scoring live here. The bowler's
--  client rolls the ball and reports how many pins fell; the
--  server checks it's their turn and that the count is possible.
-- ============================================================

local QBCore = exports['qb-core']:GetCoreObject()

local lanes = {}        -- [id] = lane (see newLane)
local playerLane = {}   -- [src] = lane id

local function newLane(id, frames)
    return {
        id = id, status = 'lobby', frames = frames,
        owner = nil, players = {},          -- ordered list of { src, name, rolls = {} }
        turn = 1,                           -- index into players
        turnStarted = 0, lastRoll = 0,
        last = nil,                         -- { name, text } shown as a banner
    }
end

local function notify(src, msg, kind)
    TriggerClientEvent('QBCore:Notify', src, msg, kind or 'primary')
end

local function nameOf(src)
    local P = QBCore.Functions.GetPlayer(src)
    if not P then return GetPlayerName(src) or ('Player ' .. src) end
    local ci = P.PlayerData.charinfo or {}
    return ('%s %s.'):format(ci.firstname or '?', (ci.lastname or '?'):sub(1, 1))
end

local function charge(src, amount)
    if amount <= 0 then return true end
    local P = QBCore.Functions.GetPlayer(src)
    if not P then return false end
    if P.Functions.GetMoney(Config.Account) >= amount then
        return P.Functions.RemoveMoney(Config.Account, amount, 'bowling-game')
    end
    if Config.Account ~= 'bank' and P.Functions.GetMoney('bank') >= amount then
        return P.Functions.RemoveMoney('bank', amount, 'bowling-game')
    end
    return false
end

local function nearDesk(src)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and #(GetEntityCoords(ped) - Config.Desk) < 6.0
end

local function approachOf(id)
    local a = Config.Lanes[id].approach
    return vector3(a.x, a.y, a.z)
end

local function playerIndex(lane, src)
    for i, p in ipairs(lane.players) do if p.src == src then return i end end
end

-- ------------------------------------------------------------
--  Public view of a lane (score sheet) -> everyone on it
-- ------------------------------------------------------------
local function view(lane)
    local players = {}
    for i, p in ipairs(lane.players) do
        local card, total = Scoring.card(p.rolls, lane.frames)
        local st = Scoring.state(p.rolls, lane.frames)
        players[i] = { src = p.src, name = p.name, frames = card, total = total, done = st.done == true, owner = p.src == lane.owner }
    end
    local cur = lane.players[lane.turn]
    return {
        id = lane.id, status = lane.status, frames = lane.frames,
        players = players, turn = cur and cur.src or nil,
        frame = cur and (Scoring.state(cur.rolls, lane.frames).frame) or nil,
        last = lane.last, maxPlayers = Config.MaxPlayers,
    }
end

local function broadcast(lane)
    local v = view(lane)
    for _, p in ipairs(lane.players) do TriggerClientEvent('nrp-bowling:lane', p.src, v) end
end

local function freeLane(id)
    local lane = lanes[id]
    if not lane then return end
    for _, p in ipairs(lane.players) do
        playerLane[p.src] = nil
        TriggerClientEvent('nrp-bowling:left', p.src)
    end
    lanes[id] = nil
end

-- tell the current bowler it's their go
local function startTurn(lane)
    local cur = lane.players[lane.turn]
    if not cur then return end
    local st = Scoring.state(cur.rolls, lane.frames)
    lane.turnStarted = os.time()
    TriggerClientEvent('nrp-bowling:yourTurn', cur.src, lane.id, {
        frame = st.frame, roll = st.roll, standing = st.standing, reset = st.reset, frames = lane.frames,
    })
    broadcast(lane)
end

local function finishGame(lane)
    lane.status = 'done'
    local best, winners = -1, {}
    for _, p in ipairs(lane.players) do
        local t = Scoring.total(p.rolls, lane.frames)
        if t > best then best, winners = t, { p.name } elseif t == best then winners[#winners + 1] = p.name end
    end
    lane.seq = (lane.seq or 0) + 1
    lane.last = { name = table.concat(winners, ' & '), text = ('WINS WITH %d'):format(best), final = true, seq = lane.seq }
    broadcast(lane)
    local id = lane.id
    SetTimeout(15000, function()
        if lanes[id] == lane then freeLane(id) end
    end)
end

-- move to the next player who still has frames left
local function nextTurn(lane)
    local n = #lane.players
    if n == 0 then return freeLane(lane.id) end
    -- everyone bowls frame f before anyone bowls f+1: pick the player with the
    -- fewest completed frames, starting after the current one
    local function framesDone(p)
        local st = Scoring.state(p.rolls, lane.frames)
        if st.done then return lane.frames + 1 end
        return st.frame - 1
    end
    local bestIdx, bestDone
    for step = 1, n do
        local idx = ((lane.turn - 1 + step) % n) + 1
        local d = framesDone(lane.players[idx])
        if d <= lane.frames and (bestDone == nil or d < bestDone) then bestIdx, bestDone = idx, d end
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
            nextTurn(lane)
            return
        end
    end
    broadcast(lane)
end

-- ------------------------------------------------------------
--  Front desk
-- ------------------------------------------------------------
QBCore.Functions.CreateCallback('nrp-bowling:lanes', function(src, cb)
    local list = {}
    for id = 1, #Config.Lanes do
        local lane = lanes[id]
        local names = {}
        if lane then for _, p in ipairs(lane.players) do names[#names + 1] = p.name end end
        list[id] = {
            id = id,
            status = lane and lane.status or 'free',
            players = names,
            frames = lane and lane.frames or nil,
            mine = playerLane[src] == id,
        }
    end
    cb({ lanes = list, price = Config.Price, max = Config.MaxPlayers, lengths = Config.GameLengths, name = Config.AlleyName, myLane = playerLane[src] })
end)

local function join(src, id, frames)
    if playerLane[src] then return notify(src, 'You are already on a lane.', 'error') end
    if not nearDesk(src) then return end
    local lane = lanes[id]
    if not Config.Lanes[id] then return end

    if lane then
        if lane.status ~= 'lobby' then return notify(src, 'That lane is mid-game.', 'error') end
        if #lane.players >= Config.MaxPlayers then return notify(src, 'That lane is full.', 'error') end
    end
    if not charge(src, Config.Price) then
        return notify(src, ('A game is $%d.'):format(Config.Price), 'error')
    end

    if not lane then
        local valid = false
        for _, f in ipairs(Config.GameLengths) do if f == frames then valid = true end end
        lane = newLane(id, valid and frames or Config.GameLengths[1])
        lane.owner = src
        lanes[id] = lane
    end
    lane.players[#lane.players + 1] = { src = src, name = nameOf(src), rolls = {} }
    playerLane[src] = id
    notify(src, ('Lane %d - shoes on! Head to your lane.'):format(id), 'success')
    TriggerClientEvent('nrp-bowling:joined', src, id)
    broadcast(lane)
end

RegisterNetEvent('nrp-bowling:open', function(id, frames) join(source, tonumber(id), tonumber(frames)) end)
RegisterNetEvent('nrp-bowling:join', function(id) join(source, tonumber(id)) end)

RegisterNetEvent('nrp-bowling:start', function()
    local src = source
    local lane = lanes[playerLane[src] or -1]
    if not lane or lane.status ~= 'lobby' or lane.owner ~= src then return end
    local ped = GetPlayerPed(src)
    if #(GetEntityCoords(ped) - approachOf(lane.id)) > 8.0 then
        return notify(src, 'Walk over to your lane to start.', 'error')
    end
    lane.status = 'playing'
    lane.turn = 1
    lane.last = nil
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

    local st = Scoring.state(cur.rolls, lane.frames)
    if st.done then return end
    knocked = math.floor(tonumber(knocked) or 0)
    if knocked < 0 then knocked = 0 end
    if knocked > st.standing then knocked = st.standing end

    cur.rolls[#cur.rolls + 1] = knocked
    lane.lastRoll = os.time()
    lane.seq = (lane.seq or 0) + 1
    lane.last = { name = cur.name, text = Scoring.callout(st.standing, knocked), seq = lane.seq, knocked = knocked }

    local after = Scoring.state(cur.rolls, lane.frames)
    local frameOver = after.done or after.frame ~= st.frame
    if frameOver then
        TriggerClientEvent('nrp-bowling:turnOver', src)
        nextTurn(lane)
    else
        startTurn(lane)   -- same player, next ball of the frame
    end
end)

-- ------------------------------------------------------------
--  AFK / walked away / disconnected
-- ------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(5000)
        local now = os.time()
        for id, lane in pairs(lanes) do
            for i = #lane.players, 1, -1 do
                local p = lane.players[i]
                local ped = GetPlayerPed(p.src)
                if ped == 0 then
                    removePlayer(p.src)
                elseif #(GetEntityCoords(ped) - approachOf(id)) > Config.LeaveDistance then
                    removePlayer(p.src, 'You left the bowling alley - your game ended.')
                end
            end
            local cur = lanes[id] and lane.status == 'playing' and lane.players[lane.turn]
            if cur and now - lane.turnStarted > Config.TurnTimeout then
                removePlayer(cur.src, 'You took too long to bowl and were removed from the lane.')
            end
        end
    end
end)

AddEventHandler('playerDropped', function() removePlayer(source) end)
