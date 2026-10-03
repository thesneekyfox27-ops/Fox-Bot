-- ============================================================
--  MUSCLE SANDS GYM - server
--  Everything that matters is decided here: passes, energy,
--  decay and stat gains. The client only plays animations and
--  the rep minigame.
-- ============================================================

local QBCore = exports['qb-core']:GetCoreObject()
local SPOTS = GymSpots()

local active   = {}   -- [src] = { spot = i, started = ms }
local occupied = {}   -- [spot] = src
local lastSet  = {}   -- [src] = ms of last finished set

local function dbg(...) if Config.Debug then print('[muscle_sands_gym]', ...) end end

local function notify(src, msg, kind)
    TriggerClientEvent('ms_gym:notify', src, msg, kind or 'inform')
end

local function round1(v) return math.floor(v * 10 + 0.5) / 10 end
local function clampStat(v)
    v = tonumber(v) or 0
    if v < 0 then v = 0 elseif v > Config.MaxStat then v = Config.MaxStat end
    return round1(v)
end

local function tierById(id)
    for _, t in ipairs(Config.Pass.tiers) do if t.id == id then return t end end
end

-- ------------------------------------------------------------
--  Inventory (tgiann first, QBCore functions as fallback)
-- ------------------------------------------------------------
local function invStarted()
    return GetResourceState(Config.InventoryResource or '') == 'started'
end

local function hasItem(src, Player, item)
    if invStarted() then
        local ok, res = pcall(function() return exports[Config.InventoryResource]:HasItem(src, item, 1) end)
        if ok and res ~= nil then return res and true or false end
    end
    return Player.Functions.GetItemByName(item) ~= nil
end

local function giveItem(src, Player, item, info)
    if invStarted() then
        local ok, res = pcall(function() return exports[Config.InventoryResource]:AddItem(src, item, 1, nil, info) end)
        if ok and res ~= false then return true end
    end
    return Player.Functions.AddItem(item, 1, false, info)
end

local function takeItem(src, Player, item)
    if invStarted() then
        pcall(function() exports[Config.InventoryResource]:RemoveItem(src, item, 1) end)
    end
    local it = Player.Functions.GetItemByName(item)
    if it then Player.Functions.RemoveItem(item, it.amount or 1, it.slot) end
end

-- ------------------------------------------------------------
--  Player gym state (QBCore metadata - same keys as v1)
-- ------------------------------------------------------------
local function readState(Player)
    local m = Player.PlayerData.metadata
    local now = os.time()
    local s = {
        strength    = clampStat(m.strength),
        stamina     = clampStat(m.stamina),
        lastTrained = tonumber(m.gymLastTrained) or 0,
        energy      = tonumber(m.gymEnergy),
        energyStamp = tonumber(m.gymEnergyStamp) or 0,
        pass        = type(m.gympass) == 'table' and m.gympass or nil,
    }
    -- new player: full tank, decay clock starts now
    if s.energy == nil or s.energyStamp <= 0 then s.energy, s.energyStamp = Config.Energy.max, now end
    if s.lastTrained <= 0 then s.lastTrained = now end
    -- the v1 pass used in-game minutes; those can't be converted, so drop them
    if s.pass and not s.pass.expires then s.pass = nil end
    return s
end

local function writeState(Player, s)
    local f = Player.Functions
    f.SetMetaData('strength', s.strength)
    f.SetMetaData('stamina', s.stamina)
    f.SetMetaData('gymLastTrained', s.lastTrained)
    f.SetMetaData('gymEnergy', math.floor(s.energy + 0.5))
    f.SetMetaData('gymEnergyStamp', s.energyStamp)
    f.SetMetaData('gympass', s.pass or false)
end

local function regen(s)
    if not Config.Energy.enabled then s.energy = Config.Energy.max return end
    local now = os.time()
    local mins = (now - s.energyStamp) / 60
    if mins > 0 then
        s.energy = math.min(Config.Energy.max, s.energy + mins * Config.Energy.regenPerMin)
        s.energyStamp = now
    end
end

local function decay(s)
    if not Config.Decay.enabled then return false end
    local idle = os.time() - s.lastTrained - Config.Decay.graceHours * 3600
    local days = math.floor(idle / 86400)
    if days < 1 then return false end
    local loss = days * Config.Decay.lossPerDay
    s.strength = clampStat(s.strength - loss)
    s.stamina  = clampStat(s.stamina - loss)
    s.lastTrained = s.lastTrained + days * 86400
    return true
end

local function passActive(s) return s.pass and (s.pass.expires or 0) > os.time() end

local function canTrain(src, Player, s)
    if not passActive(s) then return false end
    if Config.Pass.requireItem and not hasItem(src, Player, Config.Pass.item) then return false end
    return true
end

local function snapshot(src, Player, s)
    return {
        strength = s.strength, stamina = s.stamina, max = Config.MaxStat,
        energy = math.floor(s.energy + 0.5), energyMax = Config.Energy.max,
        exhausted = Config.Energy.enabled and s.energy < Config.Energy.costPerWorkout,
        pass = passActive(s) and { tier = s.pass.tier, expires = s.pass.expires, left = s.pass.expires - os.time() } or nil,
        hasCard = (not Config.Pass.requireItem) or hasItem(src, Player, Config.Pass.item),
    }
end

local function sync(src, Player, s)
    TriggerClientEvent('ms_gym:sync', src, snapshot(src, Player, s))
end

local function expireIfDue(src, Player, s)
    if s.pass and (s.pass.expires or 0) <= os.time() then
        s.pass = nil
        if Config.Pass.requireItem then takeItem(src, Player, Config.Pass.item) end
        notify(src, 'Your Muscle Sands membership has expired.', 'error')
        return true
    end
    return false
end

local function refresh(src)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    local s = readState(Player)
    regen(s)
    decay(s)
    expireIfDue(src, Player, s)
    writeState(Player, s)
    sync(src, Player, s)
end

RegisterNetEvent('ms_gym:requestSync', function() refresh(source) end)
AddEventHandler('QBCore:Server:PlayerLoaded', function(Player)
    if Player and Player.PlayerData then SetTimeout(1500, function() refresh(Player.PlayerData.source) end) end
end)

-- membership expiry sweep (online players)
CreateThread(function()
    while true do
        Wait(60000)
        for _, src in ipairs(QBCore.Functions.GetPlayers()) do
            local Player = QBCore.Functions.GetPlayer(src)
            local gp = Player and Player.PlayerData.metadata.gympass
            if type(gp) == 'table' and gp.expires and gp.expires <= os.time() then refresh(src) end
        end
    end
end)

-- ------------------------------------------------------------
--  Buying a membership (at the trainer only)
-- ------------------------------------------------------------
local function nearTrainer(src)
    local c = Config.Trainer.coords
    local ped = GetPlayerPed(src)
    return ped ~= 0 and #(GetEntityCoords(ped) - vector3(c.x, c.y, c.z)) < 6.0
end

local function charge(Player, price)
    if price <= 0 then return true end
    local acc = Config.Pass.account or 'cash'
    if Player.Functions.GetMoney(acc) >= price then
        return Player.Functions.RemoveMoney(acc, price, 'muscle-sands-membership')
    end
    if Config.Pass.bankFallback and acc ~= 'bank' and Player.Functions.GetMoney('bank') >= price then
        return Player.Functions.RemoveMoney('bank', price, 'muscle-sands-membership')
    end
    return false
end

RegisterNetEvent('ms_gym:buy', function(tierId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local tier = tierById(tierId)
    if not Player or not tier or not nearTrainer(src) then return end

    local s = readState(Player)
    regen(s)
    if not charge(Player, tier.price) then
        notify(src, ('You need $%d for the %s.'):format(tier.price, tier.label), 'error')
        return sync(src, Player, s)
    end

    local base = passActive(s) and s.pass.expires or os.time()
    s.pass = { tier = tier.id, expires = base + tier.minutes * 60 }
    writeState(Player, s)

    -- one membership card; re-issued if they lost it
    if not hasItem(src, Player, Config.Pass.item) then
        local info = { tier = tier.label, expires = os.date('%m/%d %H:%M', s.pass.expires) }
        giveItem(src, Player, Config.Pass.item, info)
    end

    notify(src, ('%s activated. Welcome to Muscle Sands!'):format(tier.label), 'success')
    TriggerClientEvent('ms_gym:bought', src, tier.id)
    sync(src, Player, s)
end)

-- ------------------------------------------------------------
--  Workouts
-- ------------------------------------------------------------
local function release(src)
    local a = active[src]
    if a and occupied[a.spot] == src then occupied[a.spot] = nil end
    active[src] = nil
end

local function nearSpot(src, spot)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and #(GetEntityCoords(ped) - spot.coords) < 3.0
end

RegisterNetEvent('ms_gym:start', function(spotId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    spotId = tonumber(spotId) or -1
    local spot = SPOTS[spotId]
    if not Player or not spot then return end

    local function deny(msg) TriggerClientEvent('ms_gym:startDenied', src, msg) end

    if active[src] then return deny('You are already working out.') end
    if not nearSpot(src, spot) then return deny('Get closer to the equipment.') end
    if occupied[spotId] and occupied[spotId] ~= src then return deny('Someone is using this one.') end

    local s = readState(Player)
    regen(s)
    if expireIfDue(src, Player, s) then writeState(Player, s) sync(src, Player, s) end
    if not canTrain(src, Player, s) then
        return deny(passActive(s) and 'Bring your gym membership card.' or 'You need a membership. See the trainer.')
    end
    if Config.Energy.enabled and s.energy < Config.Energy.costPerWorkout then
        return deny("You're too exhausted. Rest up and come back.")
    end
    local cd = (Config.Workout.cooldown or 0) * 1000
    if lastSet[src] and GetGameTimer() - lastSet[src] < cd then
        return deny(('Catch your breath (%ds).'):format(math.ceil((cd - (GetGameTimer() - lastSet[src])) / 1000)))
    end

    active[src] = { spot = spotId, started = GetGameTimer() }
    occupied[spotId] = src
    TriggerClientEvent('ms_gym:startOk', src, spotId)
end)

RegisterNetEvent('ms_gym:cancel', function() release(source) end)

local function grade(score)
    if score >= 0.95 then return 'S' elseif score >= 0.8 then return 'A'
    elseif score >= 0.6 then return 'B' elseif score >= 0.4 then return 'C' end
    return 'D'
end

RegisterNetEvent('ms_gym:finish', function(good, perfect)
    local src = source
    local a = active[src]
    local Player = QBCore.Functions.GetPlayer(src)
    if not a or not Player then return end
    local spot = SPOTS[a.spot]
    release(src)

    local W = Config.Workout
    -- a set can't be finished faster than the reps physically take
    if GetGameTimer() - a.started < W.reps * W.repTime * 0.8 then
        dbg(('src %d finished a set too fast'):format(src))
        return
    end
    if not nearSpot(src, spot) then return end

    good    = math.max(0, math.min(W.reps, math.floor(tonumber(good) or 0)))
    perfect = math.max(0, math.min(good, math.floor(tonumber(perfect) or 0)))
    local score = (good + perfect * 0.5) / (W.reps * 1.5)

    local s = readState(Player)
    regen(s)
    if Config.Energy.enabled then
        if s.energy < Config.Energy.costPerWorkout then return sync(src, Player, s) end
        s.energy = math.max(0, s.energy - Config.Energy.costPerWorkout)
        s.energyStamp = os.time()
    end

    local stat = spot.stat
    local before = s[stat]
    local gain = 0
    if score >= Config.Gain.minScore then
        local ease = 1 - Config.Gain.falloff * (before / Config.MaxStat)
        gain = round1(Config.Gain.perfectSet * score * ease)
    end
    s[stat] = clampStat(before + gain)
    s.lastTrained = os.time()
    writeState(Player, s)
    lastSet[src] = GetGameTimer()

    TriggerClientEvent('ms_gym:result', src, {
        stat = stat, label = spot.label, gain = round1(s[stat] - before), value = s[stat],
        max = Config.MaxStat, score = score, grade = grade(score), good = good, perfect = perfect, reps = W.reps,
    })
    sync(src, Player, s)
end)

AddEventHandler('playerDropped', function()
    release(source)
    lastSet[source] = nil
end)

-- ------------------------------------------------------------
--  Leaderboard (strongest + fittest, from the players table)
-- ------------------------------------------------------------
local board, boardAt = nil, 0

local function topBy(key)
    local n = Config.Leaderboard.size or 5
    local q = ([[SELECT charinfo, JSON_EXTRACT(metadata, '$.%s') AS v FROM players
                 WHERE JSON_EXTRACT(metadata, '$.%s') > 0 ORDER BY v + 0 DESC LIMIT %d]]):format(key, key, n)
    local rows = MySQL.query.await(q) or {}
    local out = {}
    for _, r in ipairs(rows) do
        local ci = type(r.charinfo) == 'string' and json.decode(r.charinfo) or r.charinfo or {}
        out[#out + 1] = { name = ('%s %s.'):format(ci.firstname or '?', (ci.lastname or '?'):sub(1, 1)), value = round1(tonumber(r.v) or 0) }
    end
    return out
end

QBCore.Functions.CreateCallback('ms_gym:leaderboard', function(_, cb)
    if not Config.Leaderboard.enabled then return cb(nil) end
    if board and os.time() - boardAt < 120 then return cb(board) end
    local ok, res = pcall(function() return { strength = topBy('strength'), stamina = topBy('stamina') } end)
    if ok then board, boardAt = res, os.time() end
    cb(ok and res or nil)
end)
