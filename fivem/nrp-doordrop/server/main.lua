local QBCore = exports['qb-core']:GetCoreObject()

local MILE = 1609.34
local Profiles = {} -- [citizenid] = persistent driver profile
local Sessions = {} -- [src] = live driver state (online, offer, order)
local Orders   = {} -- [id] = player-placed food order
local Rateable = {} -- [citizenid] = delivered player order the customer can still rate
local seq = 0

local function nextId() seq = seq + 1 return seq end
local function dbg(...) if Config.Debug then print('^3[nrp-doordrop]^7', ...) end end
local function round1(n) return math.floor(n * 10 + 0.5) / 10 end

---------------------------------------------------------------------
-- DB (export wrapper so we never depend on @oxmysql/lib auto-inject)
---------------------------------------------------------------------
local function dbAwait(method, query, params)
    local p = promise.new()
    exports.oxmysql[method](exports.oxmysql, query, params or {}, function(result) p:resolve(result) end)
    return Citizen.Await(p)
end

local function ensureColumn(col, def)
    local n = dbAwait('scalar', [[SELECT COUNT(*) FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'nrp_doordrop' AND COLUMN_NAME = ?]], { col })
    if tonumber(n) == 0 then dbAwait('query', ('ALTER TABLE `nrp_doordrop` ADD COLUMN `%s` %s'):format(col, def)) end
end

CreateThread(function()
    dbAwait('query', [[
        CREATE TABLE IF NOT EXISTS `nrp_doordrop` (
            `citizenid`  VARCHAR(64) NOT NULL,
            `offers`     LONGTEXT NULL,
            `ratings`    LONGTEXT NULL,
            `deliveries` INT NOT NULL DEFAULT 0,
            `earned`     INT NOT NULL DEFAULT 0,
            `history`    LONGTEXT NULL,
            `reviews`    LONGTEXT NULL,
            `refund`     INT NOT NULL DEFAULT 0,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`citizenid`)
        )
    ]])
    -- upgrade tables created by 1.0 / 1.1
    ensureColumn('reviews', 'LONGTEXT NULL')
    ensureColumn('refund', 'INT NOT NULL DEFAULT 0')
end)

local function decode(s, fallback)
    if not s or s == '' then return fallback end
    local ok, v = pcall(json.decode, s)
    return (ok and type(v) == 'table') and v or fallback
end

local function loadProfile(cid)
    if Profiles[cid] then return Profiles[cid] end
    local row = dbAwait('single', 'SELECT * FROM nrp_doordrop WHERE citizenid = ?', { cid })
    Profiles[cid] = {
        offers     = decode(row and row.offers, {}),
        ratings    = decode(row and row.ratings, {}),
        deliveries = row and row.deliveries or 0,
        earned     = row and row.earned or 0,
        history    = decode(row and row.history, {}),
        reviews    = decode(row and row.reviews, {}),
        refund     = row and row.refund or 0,
    }
    return Profiles[cid]
end

local function saveProfile(cid)
    local p = Profiles[cid]
    if not p then return end
    exports.oxmysql:update([[
        INSERT INTO nrp_doordrop (citizenid, offers, ratings, deliveries, earned, history, reviews, refund)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE offers = VALUES(offers), ratings = VALUES(ratings), deliveries = VALUES(deliveries),
            earned = VALUES(earned), history = VALUES(history), reviews = VALUES(reviews), refund = VALUES(refund)
    ]], { cid, json.encode(p.offers), json.encode(p.ratings), p.deliveries, p.earned,
          json.encode(p.history), json.encode(p.reviews), p.refund })
end

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------
local function push(list, v)
    list[#list + 1] = v
    while #list > Config.Rating.window do table.remove(list, 1) end
end

local function distXY(a, b)
    return #(vector2(a.x, a.y) - vector2(b.x, b.y))
end

local function getPlayer(src) return QBCore.Functions.GetPlayer(src) end

local function citizenId(src)
    local P = getPlayer(src)
    return P and P.PlayerData.citizenid
end

local function charName(src)
    local P = getPlayer(src)
    local ci = P and P.PlayerData.charinfo or {}
    local last = tostring(ci.lastname or '')
    return ('%s %s'):format(ci.firstname or 'Customer', last ~= '' and (last:sub(1, 1) .. '.') or '')
end

local function clean(s, max)
    if type(s) ~= 'string' then return '' end
    s = s:gsub('[%c]', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    return s:sub(1, max)
end

local function getStats(p)
    local acc = 100
    if #p.offers > 0 then
        local sum = 0
        for _, v in ipairs(p.offers) do sum = sum + v end
        acc = math.floor(sum / #p.offers * 100 + 0.5)
    end
    local rating = 5.0
    if #p.ratings > 0 then
        local sum = 0
        for _, v in ipairs(p.ratings) do sum = sum + v end
        rating = math.floor(sum / #p.ratings * 100 + 0.5) / 100
    end
    local tier = Config.Tiers[#Config.Tiers]
    for _, t in ipairs(Config.Tiers) do
        if acc >= t.minAcceptance and rating >= t.minRating and p.deliveries >= t.minDeliveries then tier = t break end
    end
    return acc, rating, tier
end

local function addReview(p, stars, text, name)
    table.insert(p.reviews, 1, { stars = stars, text = text, name = name, t = os.time() })
    while #p.reviews > Config.Reviews.keep do table.remove(p.reviews) end
end

local function npcName()
    local R = Config.Reviews
    return ('%s %s.'):format(R.names[math.random(#R.names)], string.char(math.random(65, 90)))
end

local function npcReviewText(stars, ctx)
    local R = Config.Reviews
    local pool
    if ctx.noShow then pool = R.noShow
    elseif ctx.spilled then pool = R.spilled
    elseif ctx.late > 0 then pool = R.late
    elseif stars >= 5 then pool = ctx.handedOff and R.handoff or (ctx.fast and R.fast or R.great)
    else pool = R.okay end
    return pool[math.random(#pool)]
end

local function refund(cid, src, amount, reason)
    if amount <= 0 then return end
    local P = src and getPlayer(src)
    if P and P.PlayerData.citizenid == cid then
        P.Functions.AddMoney('bank', amount, 'doordrop-refund')
        TriggerClientEvent('ox_lib:notify', src, { title = Config.AppName, description = reason or ('Refunded $%d.'):format(amount), type = 'inform' })
    else
        local p = loadProfile(cid) -- customer is offline: credit on next load
        p.refund = p.refund + amount
        saveProfile(cid)
    end
end

---------------------------------------------------------------------
-- Driver sessions
---------------------------------------------------------------------
local function getSession(src)
    if Sessions[src] then return Sessions[src] end
    local cid = citizenId(src)
    if not cid then return nil end
    loadProfile(cid)
    Sessions[src] = { src = src, cid = cid, online = false, nextOfferAt = 0, streak = 0, today = { earned = 0, count = 0 } }
    return Sessions[src]
end

local function activeOrderFor(cid)
    for _, o in pairs(Orders) do
        if o.cid == cid then return o end
    end
end

local function customerPayload(o)
    if not o then return nil end
    local r = Config.Restaurants[o.r]
    return {
        id = o.id, status = o.status, restaurant = r.label, area = r.area, items = o.list,
        subtotal = o.subtotal, deliveryFee = o.deliveryFee, serviceFee = o.serviceFee, tip = o.tip, total = o.total,
        handoff = o.handoff, driverName = o.driverName, driverMiles = o.driverMiles, street = o.street,
        npc = o.npc == true, courierPos = o.courierPos, progress = o.progress or 0, eta = o.etaSecs,
        pickup = { x = r.pickup.x, y = r.pickup.y }, dest = o.coords and { x = o.coords.x, y = o.coords.y } or nil,
        condition = o.condition, ruined = o.ruined,
    }
end

local routeForApp -- defined below (thinned road path for the app)

local function snapshot(src)
    local s = getSession(src)
    if not s then return nil end
    local p = Profiles[s.cid]
    local acc, rating, tier = getStats(p)
    local tiers = {}
    for i, t in ipairs(Config.Tiers) do
        tiers[i] = { name = t.name, minAcceptance = t.minAcceptance, minRating = t.minRating, minDeliveries = t.minDeliveries }
    end
    local rate = Rateable[s.cid]
    if rate and os.time() > rate.expires then Rateable[s.cid], rate = nil, nil end
    return {
        online = s.online, acceptance = acc, rating = rating,
        ratingCount = #p.ratings, offerCount = #p.offers,
        deliveries = p.deliveries, earned = p.earned, today = s.today,
        tier = tier.name, tiers = tiers, history = p.history, reviews = p.reviews, window = Config.Rating.window,
        customer = (function()
            local o = activeOrderFor(s.cid)
            local c = customerPayload(o)
            if c and o.route then c.route = routeForApp(o) end
            return c
        end)(),
        rateable = rate and { id = rate.id, driverName = rate.driverName, restaurant = rate.restaurant } or nil,
        streak = s.streak or 0, streakEvery = Config.Streak.every, streakBonus = Config.Streak.bonus,
        waitMult = tier.waitMult or 1.0,
    }
end

local function sendState(src)
    TriggerClientEvent('nrp-doordrop:client:state', src, snapshot(src))
end

-- The road path, thinned out for the app's map (about one point per 100 m).
routeForApp = function(o)
    local rt = o.route
    if not rt then return nil end
    local out, last = {}, nil
    for i, p in ipairs(rt.pts) do
        if i == 1 or i == #rt.pts or not last or distXY(p, last) >= 100.0 then
            out[#out + 1] = { x = math.floor(p.x), y = math.floor(p.y) }
            last = p
        end
    end
    return { leg = rt.leg, pts = out }
end

local function sendCustomer(o)
    if GetPlayerPed(o.src) ~= 0 then
        local payload = customerPayload(o)
        if o.route and o.routeSent ~= o.routeVer then
            payload.route, o.routeSent = routeForApp(o), o.routeVer
        elseif not o.route and o.routeSent then
            payload.route, o.routeSent = false, nil -- straight-line again: clear the drawn path
        end
        TriggerClientEvent('nrp-doordrop:client:customer', o.src, payload)
    end
end

---------------------------------------------------------------------
-- Hot zones
---------------------------------------------------------------------
local Hot = {}      -- [zoneIndex] = { endsAt, bonus }
local HotRest = {}  -- [zoneIndex] = cold until
local HZ = Config.HotZones

local function isPeak()
    local h = tonumber(os.date('%H'))
    for _, w in ipairs(HZ.peakHours or {}) do
        if h >= w[1] and h < w[2] then return true end
    end
    return false
end

local function hotZoneAt(pos)
    if not HZ.enabled then return nil end
    for i, h in pairs(Hot) do
        local z = HZ.zones[i]
        if distXY(pos, z) <= z.radius then return z, h, i end
    end
end

local function srcPos(src)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and GetEntityCoords(ped) or nil
end

local function broadcastHot()
    local now, list = os.time(), {}
    for i, h in pairs(Hot) do
        local z = HZ.zones[i]
        list[#list + 1] = { id = i, name = z.name, x = z.x, y = z.y, radius = z.radius, bonus = h.bonus, endsIn = h.endsAt - now }
    end
    GlobalState.ddHotZones = { list = list, peak = isPeak(), at = now }
end

local function notifyDrivers(msg, kind)
    for src, s in pairs(Sessions) do
        if s.online then TriggerClientEvent('nrp-doordrop:client:zoneAlert', src, msg, kind) end
    end
end

local function rotateHot()
    if not HZ.enabled then return end
    local now, changed = os.time(), false
    for i, h in pairs(Hot) do
        if now >= h.endsAt then
            Hot[i], HotRest[i], changed = nil, now + HZ.rest, true
            notifyDrivers(('%s cooled off.'):format(HZ.zones[i].name), 'cold')
        end
    end
    local peak = isPeak()
    local want = peak and HZ.activePeak or HZ.active
    local count = 0
    for _ in pairs(Hot) do count = count + 1 end
    local tries = 0
    while count < want and tries < 40 do
        tries = tries + 1
        local i = math.random(#HZ.zones)
        if not Hot[i] and (HotRest[i] or 0) <= now then
            local b = peak and HZ.bonusPeak or HZ.bonus
            Hot[i] = { endsAt = now + math.random(HZ.duration[1], HZ.duration[2]), bonus = math.random(b[1], b[2]) }
            count, changed = count + 1, true
            notifyDrivers(('%s is hot! +$%d per order in there.'):format(HZ.zones[i].name, Hot[i].bonus), 'hot')
        end
    end
    if changed then broadcastHot() end
end

CreateThread(function()
    Wait(2000)
    rotateHot()
    broadcastHot()
    while true do
        Wait(15000)
        rotateHot()
        broadcastHot() -- keeps the countdowns honest
    end
end)

local function scheduleNext(s, extra)
    local _, _, tier = getStats(Profiles[s.cid])
    local wait = math.random(Config.Offer.waitMin, Config.Offer.waitMax) * (tier.waitMult or 1.0)
    if HZ.enabled and next(Hot) then
        local pos = s.src and srcPos(s.src)
        wait = wait * ((pos and hotZoneAt(pos)) and HZ.insideWaitMult or HZ.outsideWaitMult)
    end
    s.nextOfferAt = os.time() + math.floor(wait) + (extra or 0)
end

local function isFree(s) return s.online and not s.offer and not s.order end

---------------------------------------------------------------------
-- Offers
---------------------------------------------------------------------
local function nearestN(list, n)
    table.sort(list, function(a, b) return a.d < b.d end)
    local out = {}
    for i = 1, math.min(n, #list) do out[i] = list[i] end
    return out
end

local function payFor(miles, tier)
    local pay = math.max(Config.Pay.minBase, math.floor(Config.Pay.base + miles * Config.Pay.perMile + 0.5))
    return Config.Pay.maxBase and math.min(pay, Config.Pay.maxBase) or pay
end

local function npcOffer(src, s)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local pc = GetEntityCoords(ped)

    local maxPick, near, all = Config.MaxPickupMiles * MILE, {}, {}
    for i, r in ipairs(Config.Restaurants) do
        if not r.disabled and r.menu and #r.menu > 0 then
            local e = { i = i, d = distXY(pc, r.pickup) }
            all[#all + 1] = e
            if e.d <= maxPick then near[#near + 1] = e end
        end
    end
    if #near == 0 then near = nearestN(all, 3) end
    if #near == 0 then return nil end
    local zone = hotZoneAt(pc)
    if zone then
        local inside = {}
        for _, e in ipairs(near) do
            if distXY(Config.Restaurants[e.i].pickup, zone) <= zone.radius + 150.0 then inside[#inside + 1] = e end
        end
        if #inside > 0 then near = inside end
    end
    local pick = near[math.random(#near)]
    local r = Config.Restaurants[pick.i]

    local minD, maxD = Config.DropoffMiles.min * MILE, Config.DropoffMiles.max * MILE
    local drops, allDrops = {}, {}
    for i, d in ipairs(Config.Dropoffs) do
        local e = { i = i, d = distXY(r.pickup, d.door) }
        allDrops[#allDrops + 1] = e
        if e.d >= minD and e.d <= maxD then drops[#drops + 1] = e end
    end
    if #drops == 0 then drops = nearestN(allDrops, 3) end
    if #drops == 0 then return nil end
    local drop = drops[math.random(#drops)]
    local miles = ((pick.d + drop.d) * Config.RoadFactor) / MILE

    local acc, _, tier = getStats(Profiles[s.cid])
    local tip, bigTip = 0, false
    if math.random() < tier.bigTipChance * (acc / 100) then
        tip, bigTip = math.random(Config.Tips.big.min, Config.Tips.big.max), true
    elseif math.random() >= tier.zeroTipChance then
        tip = math.random(Config.Tips.normal.min, Config.Tips.normal.max)
    end
    tip = math.floor(tip * tier.tipMult + 0.5)
    local base = payFor(miles)

    local items, used = {}, {}
    local count = math.random(1, math.min(3, #r.menu))
    while #items < count do
        local n = math.random(#r.menu)
        if not used[n] then
            used[n] = true
            items[#items + 1] = { name = r.menu[n].label, qty = math.random(1, 2) }
        end
    end

    local d = Config.Dropoffs[drop.i]
    return {
        id = nextId(), r = pick.i, drop = { label = d.label, area = d.area, door = d.door },
        miles = round1(miles), base = base, tip = tip, total = base + tip, bigTip = bigTip,
        faceToFace = math.random() < Config.FaceToFaceChance, items = items,
        eta = math.floor(Config.Eta.base + miles * Config.Eta.perMile),
    }
end

local function playerOffer(src, o)
    local r = Config.Restaurants[o.r]
    local pd = distXY(GetEntityCoords(GetPlayerPed(src)), r.pickup)
    local miles = ((pd + distXY(r.pickup, o.coords)) * Config.RoadFactor) / MILE
    local base = payFor(miles)
    local items = {}
    for i, it in ipairs(o.list) do items[i] = { name = it.label, qty = it.qty } end
    return {
        id = nextId(), r = o.r, playerOrder = o.id,
        drop = { label = o.street, area = o.area, door = o.coords },
        customerSrc = o.src, customerName = o.name,
        miles = round1(miles), base = base, tip = o.tip, total = base + o.tip, bigTip = o.tip >= Config.Tips.big.min,
        faceToFace = o.handoff == 'hand', items = items,
        eta = math.floor(Config.Eta.base + miles * Config.Eta.perMile),
    }
end

local function publicOrder(o)
    local r = Config.Restaurants[o.r]
    return {
        id = o.id, miles = o.miles, base = o.base, tip = o.tip, total = o.total, bigTip = o.bigTip,
        faceToFace = o.faceToFace, items = o.items, eta = o.eta, stage = o.stage,
        deadlineIn = o.deadlineAt and (o.deadlineAt - os.time()) or o.eta,
        player = o.playerOrder ~= nil, customerSrc = o.customerSrc, customerName = o.customerName,
        hotBonus = o.hotBonus, hotZone = o.hotZone,
        restaurant = { label = r.label, area = r.area, category = r.category, bag = r.bag, pickup = r.pickup, worker = r.worker },
        dropoff = { label = o.drop.label, area = o.drop.area, door = o.drop.door },
    }
end

local function sendOffer(src, s, offer)
    local pos = srcPos(src)
    local zone, h = nil, nil
    if pos then zone, h = hotZoneAt(pos) end
    if zone then
        offer.hotBonus, offer.hotZone = h.bonus, zone.name
        offer.total = offer.total + h.bonus
    end
    offer.expiresAt = os.time() + Config.Offer.timeout
    s.offer = offer
    TriggerClientEvent('nrp-doordrop:client:offer', src, publicOrder(offer), Config.Offer.timeout)
end

local function flipLastAccept(p)
    for i = #p.offers, 1, -1 do
        if p.offers[i] == 1 then p.offers[i] = 0 return end
    end
    push(p.offers, 0)
end

-- A player order lost its driver: back to searching if the food is still at the restaurant.
local function releasePlayerOrder(orderId, driverSrc, pickedUp)
    local o = Orders[orderId]
    if not o then return end
    if pickedUp then
        Orders[o.id] = nil
        o.status = 'cancelled'
        refund(o.cid, o.src, o.total, 'Your driver cancelled after pickup. You were refunded.')
        TriggerClientEvent('nrp-doordrop:client:customer', o.src, { id = o.id, status = 'cancelled', reason = 'Your driver cancelled. You were refunded.' })
    else
        o.status, o.driver, o.driverName, o.offeredTo, o.driverMiles = 'searching', nil, nil, nil, nil
        o.tried[driverSrc] = true
        o.createdAt = os.time()
        sendCustomer(o)
    end
end

local function unassign(src, s, penalize)
    local o = s.order
    if not o then return end
    local p = Profiles[s.cid]
    if penalize then
        flipLastAccept(p)
        if o.stage == 'dropoff' then
            push(p.ratings, Config.Rating.unassignAfterPickupStars)
            local R = Config.Reviews
            addReview(p, Config.Rating.unassignAfterPickupStars, R.noShow[math.random(#R.noShow)], o.customerName or npcName())
        end
        saveProfile(s.cid)
    end
    if o.playerOrder then releasePlayerOrder(o.playerOrder, src, o.stage == 'dropoff') end
    s.order = nil
    scheduleNext(s, Config.Offer.declineCooldown)
end

---------------------------------------------------------------------
-- Live courier (server): route state, physical spawns near players,
-- attack / theft detection, lootable bags. See Config.NpcCourier.live.
---------------------------------------------------------------------
local Leaving = {} -- couriers driving off after a delivery, or bodies to clear: [key] = { ped, veh, phase, until }
local Loot    = {} -- [netId] = { obj, items, restaurant, expires }
local liveKey = 0

local function LIVE() return Config.NpcCourier.live end

local function waitExists(ent, ms)
    local t = GetGameTimer() + ms
    while not DoesEntityExist(ent) and GetGameTimer() < t do Wait(25) end
    return DoesEntityExist(ent)
end

local function safeDelete(ent)
    if ent and ent ~= 0 and DoesEntityExist(ent) then DeleteEntity(ent) end
end

local function nearestPlayer(pos, radius)
    local best, bestD
    for _, id in ipairs(GetPlayers()) do
        local ped = GetPlayerPed(id)
        if ped ~= 0 then
            local d = distXY(GetEntityCoords(ped), pos)
            if d <= radius and (not bestD or d < bestD) then best, bestD = tonumber(id), d end
        end
    end
    return best, bestD
end

local function syncCouriers()
    local list = {}
    for _, o in pairs(Orders) do
        local l = o.live
        if l and l.pedNet then
            list[tostring(o.id)] = { ped = l.pedNet, veh = l.vehNet, phase = l.phase, dest = l.dest, speed = LIVE().driveSpeed }
        end
    end
    for k, e in pairs(Leaving) do
        if e.phase == 'leave' and e.pedNet then
            list[k] = { ped = e.pedNet, veh = e.vehNet, phase = 'leave', dest = e.dest }
        end
    end
    GlobalState.ddCouriers = list
end

local function toV3(p) return vector3(p.x, p.y, p.z or 0.0) end

-- Where the courier is heading right now.
local function legTarget(o)
    if o.leg == 'shop' then return toV3(Config.Restaurants[o.r].pickup) end
    if o.handoff == 'hand' then
        local cped = GetPlayerPed(o.src)
        if cped ~= 0 then return GetEntityCoords(cped) end
    end
    return toV3(o.coords)
end

-- Hand the physical courier over to "leaving" (drive off, then cleaned up) or clear a body.
local function releaseCourier(o, phase, secs)
    local l = o.live
    o.live = nil
    if not l then return end
    liveKey = liveKey + 1
    Leaving['x' .. liveKey] = {
        ped = l.ped, veh = l.veh, pedNet = l.pedNet, vehNet = l.vehNet, phase = phase or 'leave',
        dest = l.dest, untilT = os.time() + (secs or 45),
    }
    syncCouriers()
end

-- Pick somewhere in the city for a courier to start from, so you can watch them drive to the restaurant.
local function courierStart(o)
    local shop = Config.Restaurants[o.r].pickup
    local lo, hi = LIVE().startDistance[1], LIVE().startDistance[2]
    local pool = {}
    for _, d in ipairs(Config.Dropoffs) do
        local dist = distXY(d.door, shop)
        if dist >= lo and dist <= hi then pool[#pool + 1] = d.door end
    end
    for _, r in ipairs(Config.Restaurants) do
        local dist = distXY(r.pickup, shop)
        if not r.disabled and dist >= lo and dist <= hi then pool[#pool + 1] = r.pickup end
    end
    local p = #pool > 0 and pool[math.random(#pool)] or vector3(shop.x + 600.0, shop.y, shop.z)
    return { x = p.x, y = p.y, z = p.z }
end

local function newCourier(o)
    local N = Config.NpcCourier
    local prev = o.driverName
    repeat o.driverName = N.names[math.random(#N.names)] until o.driverName ~= prev or #N.names < 2
    o.pedModel = N.peds[math.random(#N.peds)]
    o.leg = 'shop'
    o.cpos = LIVE().enabled and courierStart(o) or { x = Config.Restaurants[o.r].pickup.x, y = Config.Restaurants[o.r].pickup.y, z = Config.Restaurants[o.r].pickup.z }
    o.lastTick, o.nextSpawn, o.spawnFails = os.time(), 0, 0
end

local function spawnLive(o, helper)
    o.spawning = true
    CreateThread(function()
        local target = legTarget(o)
        local ok, spot = pcall(lib.callback.await, 'nrp-doordrop:roadSpawn', helper, o.cpos, { x = target.x, y = target.y })
        if not ok or not spot or not Orders[o.id] or o.live or not o.npc then
            o.spawning, o.nextSpawn = false, os.time() + 10
            o.spawnFails = (o.spawnFails or 0) + 1
            return
        end
        local v = LIVE().vehicles[math.random(#LIVE().vehicles)]
        local veh = CreateVehicleServerSetter(GetHashKey(v.model), v.type, spot.x, spot.y, spot.z + 0.4, spot.h + 0.0)
        local r = math.rad(spot.h)
        local side = vector3(math.cos(r), math.sin(r), 0.0) * 1.3
        local ped = CreatePed(4, GetHashKey(o.pedModel), spot.x + side.x, spot.y + side.y, spot.z + 0.2, spot.h + 0.0, true, true)
        if not (waitExists(veh, 3000) and waitExists(ped, 3000)) or not Orders[o.id] then
            safeDelete(ped) safeDelete(veh)
            o.spawning, o.nextSpawn = false, os.time() + 10
            o.spawnFails = (o.spawnFails or 0) + 1
            return
        end
        pcall(SetEntityOrphanMode, veh, 2) -- we decide when they go away
        pcall(SetEntityOrphanMode, ped, 2)
        Entity(ped).state:set('ddCourier', o.id, true)
        local now = os.time()
        o.live = {
            ped = ped, veh = veh,
            pedNet = NetworkGetNetworkIdFromEntity(ped), vehNet = NetworkGetNetworkIdFromEntity(veh),
            phase = 'drive', dest = { x = target.x, y = target.y, z = target.z },
            born = now, boarded = false, moveRef = { pos = vector3(spot.x, spot.y, spot.z), t = now },
        }
        o.spawning, o.spawnFails = false, 0
        dbg(('courier for order %d spawned near player %d'):format(o.id, helper))
        syncCouriers()
    end)
end

local function dropLoot(o, pos)
    local r = Config.Restaurants[o.r]
    local model = (Config.Bags[r.bag] or Config.Bags.bag).model
    local items = {}
    for _, it in ipairs(o.list) do
        if it.qty > 0 then items[#items + 1] = { item = it.item, label = it.label, qty = it.qty } end
    end
    CreateThread(function()
        local obj = CreateObjectNoOffset(GetHashKey(model), pos.x + 0.6, pos.y + 0.3, pos.z - 0.6, true, true, false)
        if not waitExists(obj, 3000) then return end
        pcall(SetEntityOrphanMode, obj, 2)
        Entity(obj).state:set('ddLoot', { restaurant = r.label }, true)
        Loot[NetworkGetNetworkIdFromEntity(obj)] = {
            obj = obj, items = items, restaurant = r.label, expires = os.time() + LIVE().lootLifetime,
        }
    end)
end

local DOWN_TEXT = {
    attacked = 'Your courier was attacked',
    stolen   = "Someone stole your courier's ride",
    wrecked  = "Your courier's ride got wrecked",
    stranded = 'Your courier lost their ride',
}

local function courierDown(o, reason)
    local l = o.live
    local pos = (l and DoesEntityExist(l.ped)) and GetEntityCoords(l.ped) or toV3(o.cpos)
    if l then
        local stolen = reason == 'stolen'
        o.live = nil
        liveKey = liveKey + 1
        -- leave the scene for a bit (body, wreck); a stolen ride belongs to the thief now
        Leaving['x' .. liveKey] = { ped = l.ped, veh = not stolen and l.veh or nil, phase = 'down', untilT = os.time() + 90 }
        if stolen then pcall(SetEntityOrphanMode, l.veh, 0) end
    end
    local msg = DOWN_TEXT[reason] or DOWN_TEXT.attacked
    dbg(('order %d courier down: %s'):format(o.id, reason))

    if o.leg == 'shop' then
        -- no food on them yet: send someone else
        local shop = Config.Restaurants[o.r].label
        newCourier(o)
        o.status = 'accepted'
        TriggerClientEvent('ox_lib:notify', o.src, { title = Config.AppName, type = 'warning',
            description = ('%s on the way to %s. %s is taking over.'):format(msg, shop, o.driverName) })
        sendCustomer(o)
    else
        dropLoot(o, pos)
        Orders[o.id] = nil
        refund(o.cid, o.src, o.total, ('%s. You were refunded $%d.'):format(msg, o.total))
        TriggerClientEvent('nrp-doordrop:client:customer', o.src, {
            id = o.id, status = 'cancelled',
            reason = ('%s and your food was left in the street. You were refunded.'):format(msg),
        })
    end
    syncCouriers()
end

-- A client saw the courier die. Never trusted on its own: the server re-checks health next tick.
RegisterNetEvent('nrp-doordrop:server:courierDown', function(id)
    local o = Orders[tonumber(id) or -1]
    if o and o.live then o.live.recheck = true end
end)

RegisterNetEvent('nrp-doordrop:server:takeLoot', function(netId)
    local src = source
    local l = Loot[tonumber(netId) or -1]
    if not l or not DoesEntityExist(l.obj) then return end
    if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(l.obj)) > 4.0 then return end
    Loot[netId] = nil
    DeleteEntity(l.obj)
    for _, it in ipairs(l.items) do pcall(Config.GiveItem, src, it.item, it.qty) end
    TriggerClientEvent('ox_lib:notify', src, { title = Config.AppName, type = 'inform',
        description = ("You grabbed someone's %s order."):format(l.restaurant) })
end)

-- Health / theft / wreck checks on the physical courier. Returns true if they went down.
local function checkLive(o, now)
    local l = o.live
    local ped, veh = l.ped, l.veh
    if not DoesEntityExist(ped) then
        -- deleted by something else (admin, cleanup): carry on "on the map" from the last spot
        safeDelete(veh)
        o.live = nil
        syncCouriers()
        return false
    end
    if GetEntityHealth(ped) <= 0 then courierDown(o, 'attacked') return true end
    l.recheck = nil
    if l.phase == 'deliver' then return false end -- on foot handing it over; only death matters now
    if not DoesEntityExist(veh) or GetEntityHealth(veh) <= 0 then courierDown(o, 'wrecked') return true end
    local drv = GetPedInVehicleSeat(veh, -1)
    if drv ~= 0 and drv ~= ped and IsPedAPlayer(drv) then courierDown(o, 'stolen') return true end

    if GetVehiclePedIsIn(ped, false) == veh then
        l.boarded, l.outSince = true, nil
    elseif l.boarded then
        l.outSince = l.outSince or now
        if now - l.outSince > 30 then courierDown(o, 'stranded') return true end
    elseif now - l.born > 25 then
        -- never managed to get in: try again a bit further along
        safeDelete(ped) safeDelete(veh)
        o.live, o.nextSpawn = nil, now + 15
        syncCouriers()
    end
    return false
end

local function arriveLive(o, now)
    o.status, o.arrivedAt, o.progress = 'arriving', now, 0.95
    o.live.phase = 'deliver'
    syncCouriers()
    TriggerClientEvent('nrp-doordrop:client:npcArriveLive', o.src, {
        id = o.id, pedNet = o.live.pedNet, vehNet = o.live.vehNet, bag = Config.Restaurants[o.r].bag,
        handoff = o.handoff, name = o.driverName, from = o.cpos, coords = o.coords,
    })
end

-- refundAmt: what the customer gets back (defaults to everything they paid)
local function cancelPlayerOrder(o, reason, customerLeaving, refundAmt)
    Orders[o.id] = nil
    if o.npc then releaseCourier(o, 'leave', 45) end
    local afterPickup = o.status == 'pickedup' or o.status == 'arriving'
    o.status = 'cancelled'
    -- pull the offer / job back from the driver
    if o.offeredTo and Sessions[o.offeredTo] and Sessions[o.offeredTo].offer and Sessions[o.offeredTo].offer.playerOrder == o.id then
        Sessions[o.offeredTo].offer = nil
        TriggerClientEvent('nrp-doordrop:client:offerGone', o.offeredTo, 'cancelled')
    end
    local ds = o.driver and Sessions[o.driver]
    if ds and ds.order and ds.order.playerOrder == o.id then
        local msg = 'The customer cancelled the order. No penalty.'
        if afterPickup then
            -- they already drove to the restaurant: pay them for that part of the job
            local pay = math.floor((ds.order.total or 0) * (Config.Customer.lateCancelDriverPay or 0) + 0.5)
            local P = pay > 0 and getPlayer(o.driver)
            if P then
                P.Functions.AddMoney('bank', pay, 'doordrop-cancelled')
                msg = ('The customer cancelled after pickup. You were paid $%d for your time.'):format(pay)
            end
        end
        ds.order = nil
        TriggerClientEvent('nrp-doordrop:client:orderCancelled', o.driver, msg)
        sendState(o.driver)
    end
    -- a leaving customer gets the refund credited on their next login instead
    refundAmt = math.max(0, math.floor(refundAmt or o.total))
    refund(o.cid, not customerLeaving and o.src or nil, refundAmt, reason)
    -- always tell the customer's game it's over: clears the timer, the tracking blip and the courier
    if not customerLeaving and GetPlayerPed(o.src) ~= 0 then
        TriggerClientEvent('nrp-doordrop:client:customer', o.src, {
            id = o.id, status = 'cancelled', quiet = refundAmt > 0, -- the refund notice already said it
            reason = reason or 'Your order was cancelled.',
        })
        sendState(o.src)
    end
end

---------------------------------------------------------------------
-- NPC courier
---------------------------------------------------------------------
local function assignNpc(o)
    local N = Config.NpcCourier
    o.npc, o.offeredTo = true, nil
    o.status = 'accepted'
    o.readyAt = os.time() + math.random(N.prepTime[1], N.prepTime[2])
    newCourier(o)
    o.courierPos = { x = o.cpos.x, y = o.cpos.y }
    o.progress = 0
    dbg(('order %d -> NPC courier'):format(o.id))
    sendCustomer(o)
end

local function giveOrderItems(o)
    for _, it in ipairs(o.list) do
        if it.qty > 0 then
            local ok, err = pcall(Config.GiveItem, o.src, it.item, it.qty)
            if not ok then print(('^1[nrp-doordrop]^7 GiveItem failed for %s x%d: %s'):format(it.item, it.qty, err)) end
        end
    end
end

-- No tip (or a tiny one) on a courier order: some of it might not make it.
-- Only NPC couriers do this. Player drivers always hand over the whole order.
local function shortChange(o)
    local M = Config.NpcCourier.missing
    if not M or not M.enabled then return {} end
    local chance = (o.tip <= 0 and M.noTipChance) or (o.tip <= M.lowTip and M.lowTipChance) or 0
    if chance <= 0 or math.random() >= chance then return {} end

    local units = 0
    for _, it in ipairs(o.list) do units = units + it.qty end
    local take = math.min(math.random(1, M.maxMissing), units - 1) -- always leave something in the bag
    local missing = {}
    while take > 0 do
        local it = o.list[math.random(#o.list)]
        if it.qty > 0 then
            it.qty, units, take = it.qty - 1, units - 1, take - 1
            missing[it.label] = (missing[it.label] or 0) + 1
        end
    end
    local out = {}
    for label, qty in pairs(missing) do out[#out + 1] = { label = label, qty = qty } end
    return out
end

local function completeNpc(o, note)
    if not Orders[o.id] then return false end
    Orders[o.id] = nil
    releaseCourier(o, 'leave', 45)
    local missing = shortChange(o)
    giveOrderItems(o) -- only what's left in the bag
    o.status, o.progress, o.driverMiles, o.etaSecs = 'delivered', 1, 0, 0
    local payload = customerPayload(o)
    payload.note = note
    payload.missing = #missing > 0 and missing or nil
    if #missing > 0 and Config.NpcCourier.missing.refund then
        local amt = 0
        for _, m in ipairs(missing) do
            for _, it in ipairs(o.list) do
                if it.label == m.label then amt = amt + it.price * m.qty break end
            end
        end
        refund(o.cid, o.src, amt, ('$%d refunded for missing items.'):format(amt))
        payload.refunded = amt
    end
    if GetPlayerPed(o.src) ~= 0 then
        TriggerClientEvent('nrp-doordrop:client:customer', o.src, payload)
        sendState(o.src)
    end
    return true
end

---------------------------------------------------------------------
-- Road routes: the customer's game asks GTA's GPS for the real road path of the current leg
-- (hidden, nothing shows on their map) and sends it here. The courier then moves along it
-- even where nobody is around to physically see them.
---------------------------------------------------------------------
local function d3(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

local function buildRoute(pts)
    local cum, total = { 0.0 }, 0.0
    for i = 2, #pts do
        total = total + d3(pts[i - 1], pts[i])
        cum[i] = total
    end
    return { pts = pts, cum = cum, total = total }
end

-- how far along the route the closest point to `pos` is
local function routeProject(rt, pos)
    local bestD, bestAlong = nil, 0.0
    for i = 2, #rt.pts do
        local a, b = rt.pts[i - 1], rt.pts[i]
        local vx, vy = b.x - a.x, b.y - a.y
        local len2 = vx * vx + vy * vy
        local t = len2 > 0 and math.max(0, math.min(1, ((pos.x - a.x) * vx + (pos.y - a.y) * vy) / len2)) or 0
        local px, py = a.x + vx * t, a.y + vy * t
        local dd = (pos.x - px) ^ 2 + (pos.y - py) ^ 2
        if not bestD or dd < bestD then bestD, bestAlong = dd, rt.cum[i - 1] + t * math.sqrt(len2) end
    end
    return bestAlong
end

local function routePoint(rt, along)
    if along <= 0 then return rt.pts[1] end
    for i = 2, #rt.pts do
        if rt.cum[i] >= along then
            local a, b = rt.pts[i - 1], rt.pts[i]
            local seg = rt.cum[i] - rt.cum[i - 1]
            local t = seg > 0 and (along - rt.cum[i - 1]) / seg or 1
            return { x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t, z = a.z + (b.z - a.z) * t }
        end
    end
    return rt.pts[#rt.pts]
end

local function requestRoute(o, now)
    if GetPlayerPed(o.src) == 0 then return end
    if o.routeAsked and now - o.routeAsked < 20 then return end
    o.routeAsked = now
    local to = legTarget(o)
    local nxt
    if o.leg == 'shop' then
        local c = legTarget({ leg = 'customer', handoff = o.handoff, src = o.src, coords = o.coords, r = o.r })
        nxt = { x = c.x, y = c.y, z = c.z }
    end
    TriggerClientEvent('nrp-doordrop:client:routeRequest', o.src, {
        id = o.id, leg = o.leg,
        from = { x = o.cpos.x, y = o.cpos.y, z = o.cpos.z or to.z },
        to = { x = to.x, y = to.y, z = to.z },
        next = nxt, -- restaurant -> customer, just for drawing
    })
end

RegisterNetEvent('nrp-doordrop:server:route', function(id, leg, pts)
    local src = source
    local o = Orders[tonumber(id) or -1]
    if not o or o.src ~= src or not o.npc or o.leg ~= leg or type(pts) ~= 'table' or #pts < 2 or #pts > 1000 then return end
    local clean = {}
    for _, p in ipairs(pts) do
        local x, y, z = tonumber(p.x), tonumber(p.y), tonumber(p.z)
        if not (x and y and z) or math.abs(x) > 10000 or math.abs(y) > 10000 then return end
        clean[#clean + 1] = { x = x, y = y, z = z }
    end
    local to = legTarget(o)
    local straight = distXY(o.cpos, to)
    -- sanity: starts where the courier is, ends where they're going, and isn't absurdly long
    if distXY(clean[1], o.cpos) > 400.0 or distXY(clean[#clean], to) > 400.0 then return end
    local rt = buildRoute(clean)
    if rt.total > straight * 4 + 800.0 then return end
    rt.leg, rt.to = leg, { x = to.x, y = to.y }
    o.route = rt
    o.routeD = routeProject(rt, o.cpos)
    o.routeVer = (o.routeVer or 0) + 1
    dbg(('order %d: road route for %s leg, %.0f m (%d points)'):format(o.id, leg, rt.total, #clean))
end)

-- One second of a courier's life. Physically real near players, "on the map" everywhere else.
local function npcTick(o, now)
    local N, L = Config.NpcCourier, Config.NpcCourier.live
    local dt = math.max(0, now - (o.lastTick or now))
    o.lastTick = now
    if o.status == 'arriving' then
        if o.live and checkLive(o, now) then return end
        if now - o.arrivedAt > N.arriveTimeout then completeNpc(o, 'Your courier left your order for you.') end
        return
    end

    local target = legTarget(o)
    local shop = Config.Restaurants[o.r].pickup

    -- move: follow the real courier if there is one, otherwise advance along the way
    if o.live then
        if checkLive(o, now) then return end
    end
    -- the route belongs to one leg and one destination; plan again if either changed
    local rt = o.route
    if rt and (rt.leg ~= o.leg or distXY(rt.to, target) > 150.0) then
        o.route, rt = nil, nil
    end
    if not rt and N.roadRoutes ~= false then requestRoute(o, now) end

    if o.live then
        local p = GetEntityCoords(o.live.ped)
        o.cpos = { x = p.x, y = p.y, z = p.z }
        if rt then o.routeD = routeProject(rt, o.cpos) end -- pick up from here if they despawn
        local ref = o.live.moveRef
        if #(p - ref.pos) > 8.0 then
            o.live.moveRef = { pos = p, t = now }
        elseif o.live.phase == 'drive' and now - ref.t > L.stuckSeconds then
            -- boxed in or lost: pull them out and let them reappear further along
            safeDelete(o.live.ped) safeDelete(o.live.veh)
            o.live, o.nextSpawn = nil, now + 25
            syncCouriers()
        end
    elseif rt then
        -- on the road: advance along the real route at driving speed
        local before = o.routeD or 0
        o.routeD = math.min(rt.total, before + dt * N.speed)
        local over = (before + dt * N.speed) - rt.total
        local p = routePoint(rt, o.routeD)
        o.cpos = { x = p.x, y = p.y, z = p.z }
        if over > 0 then
            -- route ends a little short of a moving customer: close the gap
            local d = distXY(o.cpos, target)
            local t = d > 0 and math.min(1, over / d) or 1
            o.cpos = { x = o.cpos.x + (target.x - o.cpos.x) * t, y = o.cpos.y + (target.y - o.cpos.y) * t, z = target.z }
        end
    else
        local step = dt * N.speed / Config.RoadFactor
        local d = distXY(o.cpos, target)
        if d <= step then
            o.cpos = { x = target.x, y = target.y, z = target.z }
        elseif d > 0 then
            local t = step / d
            o.cpos = { x = o.cpos.x + (target.x - o.cpos.x) * t, y = o.cpos.y + (target.y - o.cpos.y) * t, z = target.z }
        end
    end
    o.courierPos = { x = o.cpos.x, y = o.cpos.y }

    -- restaurant: wait out the prep, then head to the customer
    if o.leg == 'shop' and distXY(o.cpos, shop) < 30.0 then
        if now >= o.readyAt then
            o.leg, o.status = 'customer', 'pickedup'
            o.legTotal = distXY(shop, legTarget(o))
            target = legTarget(o)
            o.route, o.routeAsked = nil, nil
            requestRoute(o, now) -- plan the drive to the customer right away
        end
    end

    -- physical courier: appear when a player is close, go back to "map only" when nobody is
    if L.enabled then
        if o.live then
            o.live.phase = (o.leg == 'shop' and distXY(o.cpos, shop) < 30.0) and 'wait' or 'drive'
            local dest = { x = target.x, y = target.y, z = target.z }
            -- follow the line drawn on the map: aim ~250 m ahead on the planned route and move that point
            -- forward as they get close, so the AI takes the same streets instead of its own shortcut
            if rt and rt.leg == o.leg and o.live.phase == 'drive' and (o.routeD or 0) + 250.0 < rt.total then
                if not o.live.onRoute or distXY(o.cpos, o.live.dest) < 70.0 then
                    local p = routePoint(rt, (o.routeD or 0) + 250.0)
                    dest = { x = p.x, y = p.y, z = p.z }
                    o.live.onRoute = true
                else
                    dest = o.live.dest
                end
            else
                o.live.onRoute = false
            end
            if distXY(dest, o.live.dest) > 20.0 then o.live.dest = dest syncCouriers() end
            if not nearestPlayer(o.cpos, L.despawnRange) then
                safeDelete(o.live.ped) safeDelete(o.live.veh)
                o.live = nil
                syncCouriers()
            end
        elseif not o.spawning and now >= (o.nextSpawn or 0) then
            local helper = nearestPlayer(o.cpos, L.materializeRange)
            if helper then spawnLive(o, helper) end
        end
    end

    -- numbers for the app
    -- road meters left on this leg (real route if we have one, estimate otherwise)
    local legLeft = (rt and rt.leg == o.leg) and (rt.total - (o.routeD or 0) + distXY(rt.pts[#rt.pts], target))
        or distXY(o.cpos, target) * Config.RoadFactor
    local custTarget = legTarget({ leg = 'customer', handoff = o.handoff, src = o.src, coords = o.coords, r = o.r })
    local roadLeft = o.leg == 'shop' and (legLeft + distXY(shop, custTarget) * Config.RoadFactor) or legLeft
    local toShop = o.leg == 'shop' and legLeft or 0
    local prepLeft = math.max(0, o.readyAt - now - math.floor(toShop / N.speed))
    o.etaSecs = math.floor(roadLeft / N.speed) + (o.leg == 'shop' and prepLeft or 0)
    o.driverMiles = round1(roadLeft / MILE)
    if o.leg == 'customer' then
        o.progress = (rt and rt.total > 0) and math.min(0.95, (o.routeD or 0) / rt.total)
            or math.max(0, math.min(0.95, 1 - distXY(o.cpos, target) / math.max(1, o.legTotal or 1)))
    else
        o.progress = 0
    end

    -- arrival
    if o.leg == 'customer' then
        local remaining = distXY(o.cpos, target)
        if o.live and o.live.boarded and remaining < 35.0 then
            arriveLive(o, now)
        elseif not o.live and (remaining < 60.0 or (remaining <= N.arriveDistance and ((o.spawnFails or 0) >= 2 or not L.enabled))) then
            -- nobody could see them drive up (or no road): fall back to the short local arrival
            o.status, o.arrivedAt, o.progress = 'arriving', now, 0.95
            if GetPlayerPed(o.src) ~= 0 then
                TriggerClientEvent('nrp-doordrop:client:npcArrive', o.src, {
                    id = o.id, bag = Config.Restaurants[o.r].bag, handoff = o.handoff,
                    name = o.driverName, from = o.courierPos, coords = o.coords,
                })
            else
                completeNpc(o)
                return
            end
        end
    end
    sendCustomer(o)
end

-- Couriers tick every second, separate from the offer dispatcher.
CreateThread(function()
    while true do
        Wait(1000)
        local now = os.time()
        for _, o in pairs(Orders) do
            if o.npc and o.status ~= 'searching' then
                local ok, err = pcall(npcTick, o, now)
                if not ok then print(('^1[nrp-doordrop]^7 courier tick error (order %d): %s'):format(o.id, err)) end
            end
        end
        -- couriers driving off / bodies: gone after a while or when nobody's around
        local changed = false
        for k, e in pairs(Leaving) do
            local anchor = (e.ped and DoesEntityExist(e.ped)) and GetEntityCoords(e.ped) or ((e.veh and DoesEntityExist(e.veh)) and GetEntityCoords(e.veh))
            if not anchor or now > e.untilT or not nearestPlayer(anchor, Config.NpcCourier.live.despawnRange) then
                safeDelete(e.ped)
                if e.veh and DoesEntityExist(e.veh) then
                    local drv = GetPedInVehicleSeat(e.veh, -1)
                    if drv == 0 or not IsPedAPlayer(drv) then DeleteEntity(e.veh) end
                end
                Leaving[k] = nil
                changed = true
            end
        end
        for net, l in pairs(Loot) do
            if now > l.expires or not DoesEntityExist(l.obj) then safeDelete(l.obj) Loot[net] = nil end
        end
        if changed then syncCouriers() end
    end
end)

---------------------------------------------------------------------
-- Dispatcher
---------------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(3000)
        local now = os.time()

        -- expire offers
        for src, s in pairs(Sessions) do
            if s.offer and now > s.offer.expiresAt + 2 then
                local off = s.offer
                s.offer = nil
                push(Profiles[s.cid].offers, 0)
                saveProfile(s.cid)
                scheduleNext(s, Config.Offer.declineCooldown)
                if off.playerOrder and Orders[off.playerOrder] then
                    Orders[off.playerOrder].tried[src] = true
                    Orders[off.playerOrder].offeredTo = nil
                end
                TriggerClientEvent('nrp-doordrop:client:offerGone', src, 'expired')
                sendState(src)
            end
        end

        -- player orders first: they go to the closest free driver
        for _, o in pairs(Orders) do
            local npcOn = Config.NpcCourier.enabled
            if o.npc then
                -- couriers have their own 1s thread
            elseif o.status == 'searching' and not o.offeredTo and npcOn and now - o.createdAt > Config.NpcCourier.fallbackAfter then
                assignNpc(o)
            elseif o.status == 'searching' and not o.offeredTo then
                if not npcOn and now - o.createdAt > Config.Customer.searchTimeout then
                    cancelPlayerOrder(o, 'No drivers took your order. You were refunded.')
                else
                    local best, bestD
                    local rp = Config.Restaurants[o.r].pickup
                    for src, s in pairs(Sessions) do
                        if isFree(s) and src ~= o.src and not o.tried[src] then
                            local d = distXY(GetEntityCoords(GetPlayerPed(src)), rp)
                            if not bestD or d < bestD then best, bestD = src, d end
                        end
                    end
                    if best then
                        o.offeredTo = best
                        sendOffer(best, Sessions[best], playerOffer(best, o))
                    end
                end
            elseif o.driver and (o.status == 'accepted' or o.status == 'pickedup') then
                local ped = GetPlayerPed(o.driver)
                if ped ~= 0 then
                    local dp = GetEntityCoords(ped)
                    local target = o.coords
                    if o.status == 'accepted' then target = Config.Restaurants[o.r].pickup end
                    local rem = distXY(dp, o.coords)
                    o.courierPos = { x = dp.x, y = dp.y }
                    o.driverMiles = round1(rem * Config.RoadFactor / MILE)
                    o.etaSecs = math.floor((distXY(dp, target) + (o.status == 'accepted' and distXY(target, o.coords) or 0)) * Config.RoadFactor / 15.0)
                    o.progress = o.status == 'pickedup' and math.max(0, math.min(0.95, 1 - rem / math.max(1, o.legTotal or rem))) or 0
                    sendCustomer(o)
                end
            end
        end

        -- drove into a hot zone: the next offer comes soon
        if HZ.enabled and next(Hot) then
            for src, s in pairs(Sessions) do
                if isFree(s) then
                    local pos = srcPos(src)
                    local inZone = pos and hotZoneAt(pos) ~= nil
                    if inZone and not s.inZone then
                        s.nextOfferAt = math.min(s.nextOfferAt, now + math.random(6, 14))
                    end
                    s.inZone = inZone
                end
            end
        end

        -- NPC orders
        for src, s in pairs(Sessions) do
            if isFree(s) and now >= s.nextOfferAt then
                local offer = npcOffer(src, s)
                if offer then sendOffer(src, s, offer) else scheduleNext(s) end
            end
        end
    end
end)

---------------------------------------------------------------------
-- Driver events
---------------------------------------------------------------------
lib.callback.register('nrp-doordrop:getState', function(src)
    return snapshot(src)
end)

RegisterNetEvent('nrp-doordrop:server:setOnline', function(state)
    local src = source
    local s = getSession(src)
    if not s then return end

    if state and not s.online then
        s.online = true
        s.nextOfferAt = os.time() + math.random(5, 12)
    elseif not state and s.online then
        s.online = false
        if s.offer then
            local off = s.offer
            s.offer = nil
            if off.playerOrder and Orders[off.playerOrder] then
                Orders[off.playerOrder].tried[src] = true
                Orders[off.playerOrder].offeredTo = nil
            end
            TriggerClientEvent('nrp-doordrop:client:offerGone', src, 'offline')
        end
        if s.order then
            unassign(src, s, true)
            TriggerClientEvent('nrp-doordrop:client:orderCancelled', src, 'You clocked out, so the order was unassigned.')
        end
    end
    sendState(src)
end)

RegisterNetEvent('nrp-doordrop:server:respond', function(id, accept)
    local src = source
    local s = Sessions[src]
    if not s or not s.offer or s.offer.id ~= id then return end

    local o, p = s.offer, Profiles[s.cid]
    s.offer = nil
    local po = o.playerOrder and Orders[o.playerOrder]
    if o.playerOrder and not po then
        TriggerClientEvent('nrp-doordrop:client:offerGone', src, 'cancelled')
        return sendState(src)
    end

    if accept == true and not s.order then
        push(p.offers, 1)
        local now = os.time()
        local r = Config.Restaurants[o.r]
        o.stage      = 'pickup'
        o.acceptedAt = now
        o.deadlineAt = now + o.eta
        o.pickDist   = distXY(GetEntityCoords(GetPlayerPed(src)), r.pickup)
        o.dropDist   = distXY(r.pickup, o.drop.door)
        s.order = o
        if po then
            po.status, po.driver, po.driverName, po.offeredTo = 'accepted', src, charName(src), nil
            sendCustomer(po)
        end
        TriggerClientEvent('nrp-doordrop:client:orderStarted', src, publicOrder(o))
    else
        push(p.offers, 0)
        s.streak = 0
        scheduleNext(s, Config.Offer.declineCooldown)
        if po then po.tried[src] = true po.offeredTo = nil end
        TriggerClientEvent('nrp-doordrop:client:offerGone', src, 'declined')
    end

    saveProfile(s.cid)
    sendState(src)
end)

lib.callback.register('nrp-doordrop:pickup', function(src)
    local s = Sessions[src]
    if not s or not s.order or s.order.stage ~= 'pickup' then return false, 'No order to pick up.' end
    local o, r = s.order, Config.Restaurants[s.order.r]

    if #(GetEntityCoords(GetPlayerPed(src)) - r.pickup.xyz) > Config.InteractRange then
        return false, 'You are not at the pickup.'
    end
    if os.time() - o.acceptedAt < math.floor(o.pickDist / Config.MaxSpeed) then
        return false, 'Pickup rejected.'
    end

    o.stage = 'dropoff'
    o.pickedUpAt = os.time()
    local po = o.playerOrder and Orders[o.playerOrder]
    if po then
        po.status = 'pickedup'
        po.legTotal = distXY(r.pickup, po.coords)
        sendCustomer(po)
    end
    return true
end)

lib.callback.register('nrp-doordrop:deliver', function(src, data)
    local s = Sessions[src]
    if not s or not s.order or s.order.stage ~= 'dropoff' then return { ok = false, reason = 'No order to deliver.' } end
    local o = s.order
    local r = Config.Restaurants[o.r]
    data = type(data) == 'table' and data or {}
    local now = os.time()
    local driverPos = GetEntityCoords(GetPlayerPed(src))
    local po = o.playerOrder and Orders[o.playerOrder]

    if o.playerOrder and not po then
        s.order = nil
        return { ok = false, reason = 'This order was cancelled.' }
    end

    -- location checks
    if po and o.faceToFace then
        local cped = GetPlayerPed(po.src)
        if cped == 0 or #(driverPos - GetEntityCoords(cped)) > Config.Customer.handoffRange + 2.0 then
            return { ok = false, reason = ('%s needs to be right in front of you.'):format(po.name) }
        end
    elseif #(driverPos - o.drop.door.xyz) > Config.InteractRange then
        return { ok = false, reason = 'You are not at the customer.' }
    end
    if now - o.pickedUpAt < math.floor(o.dropDist / Config.MaxSpeed) then
        return { ok = false, reason = 'Delivery rejected.' }
    end
    if o.faceToFace and data.handedOff ~= true then
        return { ok = false, reason = 'This customer wants it handed to them.' }
    end

    local Player = getPlayer(src)
    if not Player then return { ok = false } end

    local p = Profiles[s.cid]
    local late = now - o.deadlineAt
    local stars
    local cond = math.max(0, math.min(100, math.floor(tonumber(data.condition) or 100)))
    local messy = cond < 75
    local ruined

    if po then
        -- real customer: the food goes into their inventory, and they rate the driver themselves
        if cond < Config.Driving.ruinBelow then
            local units = 0
            for _, it in ipairs(po.list) do units = units + it.qty end
            if units > 1 then
                local it = po.list[math.random(#po.list)]
                while it.qty <= 0 do it = po.list[math.random(#po.list)] end
                it.qty = it.qty - 1
                ruined = it.label
            end
        end
        po.condition, po.ruined = cond, ruined
        for _, it in ipairs(po.list) do
            if it.qty > 0 then
                local ok, err = pcall(Config.GiveItem, po.src, it.item, it.qty)
                if not ok then print(('^1[nrp-doordrop]^7 GiveItem failed for %s x%d: %s'):format(it.item, it.qty, err)) end
            end
        end
        Orders[po.id] = nil
        po.status = 'delivered'
        Rateable[po.cid] = { id = po.id, driverCid = s.cid, driverSrc = src, driverName = charName(src),
                             restaurant = r.label, expires = now + Config.Customer.rateWindow }
        sendCustomer(po)
        sendState(po.src)
        if o.faceToFace then TriggerClientEvent('nrp-doordrop:client:receive', po.src, r.bag) end
    else
        -- NPC customer rates immediately and may write a review
        stars = 5
        if late > 0 then stars = stars - math.min(3, math.ceil(late / Config.Rating.lateStep)) end
        local pen = 0 -- worst matching penalty, not the sum
        for _, rule in ipairs(Config.Driving.starPenalty) do
            if cond < rule.below then pen = math.max(pen, rule.stars) end
        end
        stars = stars - pen
        if stars == 5 and math.random() < Config.Rating.randomFourChance then stars = 4 end
        stars = math.max(1, math.min(5, stars))
        push(p.ratings, stars)

        local chance = stars <= 3 and Config.Reviews.npcChanceBad or Config.Reviews.npcChance
        if math.random() < chance then
            addReview(p, stars, npcReviewText(stars, {
                late = late, spilled = messy, handedOff = o.faceToFace,
                fast = late < -(o.eta * 0.4),
            }), npcName())
        end
    end

    -- streak: on time and in good shape, several in a row
    local streakBonus = 0
    if late <= 0 and cond >= Config.Streak.minCondition then
        s.streak = (s.streak or 0) + 1
        if s.streak % Config.Streak.every == 0 then streakBonus = Config.Streak.bonus end
    else
        s.streak = 0
    end
    local paid = o.total + streakBonus

    Player.Functions.AddMoney('bank', paid, 'doordrop-delivery')
    p.deliveries = p.deliveries + 1
    p.earned = p.earned + paid
    table.insert(p.history, 1, {
        restaurant = r.label, dropoff = o.drop.label, total = paid, tip = o.tip, stars = stars, miles = o.miles, t = now,
    })
    while #p.history > 10 do table.remove(p.history) end

    s.today.earned = s.today.earned + paid
    s.today.count = s.today.count + 1
    s.order = nil
    s.nextOfferAt = now + Config.Offer.afterDelivery
    saveProfile(s.cid)

    return {
        ok = true,
        result = {
            total = paid, base = o.base, tip = o.tip, stars = stars, hotBonus = o.hotBonus, hotZone = o.hotZone,
            streakBonus = streakBonus > 0 and streakBonus or nil, streak = s.streak, streakEvery = Config.Streak.every,
            condition = cond, ruined = ruined,
            late = math.max(0, late), spilled = messy, faceToFace = o.faceToFace,
            restaurant = r.label, dropoff = o.drop.label, player = po ~= nil, customerName = o.customerName,
        },
        snapshot = snapshot(src),
    }
end)

RegisterNetEvent('nrp-doordrop:server:unassign', function()
    local src = source
    local s = Sessions[src]
    if not s or not s.order then return end
    unassign(src, s, true)
    TriggerClientEvent('nrp-doordrop:client:orderCancelled', src, 'Order unassigned. It counts as a decline.')
    sendState(src)
end)

---------------------------------------------------------------------
-- Customer (player ordering)
---------------------------------------------------------------------
-- Opening hours: { open, close } on the in-game clock; close can be past midnight
local function storeHours(r)
    local H = Config.StoreHours
    if not H or not H.enabled then return nil end
    return r.hours or (H.byCategory and H.byCategory[r.category]) or H.default
end

local function isOpen(r, hour)
    local h = storeHours(r)
    hour = tonumber(hour)
    if not h or not hour then return true end
    local o, c = h[1] or 0, h[2] or 24
    if c - o >= 24 or o == c then return true end
    if o < c then return hour >= o and hour < c end
    return hour >= o or hour < c   -- wraps past midnight
end

local function hourLabel(h)
    h = math.floor(h) % 24
    if h == 0 then return '12am' elseif h == 12 then return '12pm' end
    return h < 12 and (h .. 'am') or ((h - 12) .. 'pm')
end

---------------------------------------------------------------------
-- Store pictures: drop an image named after the restaurant into html/stores/
-- (e.g. html/stores/burger-shot-del-perro.jpg) and it's used as that card's picture.
-- The names are printed in the console on start (`ddstores` lists them again).
---------------------------------------------------------------------
local RES = GetCurrentResourceName()
local PHOTO_DIR = 'html/stores/'
local PHOTO_EXT = { 'jpg', 'png', 'webp', 'jpeg' }
local storePics = {}

local function slugify(str)
    return (str or ''):lower():gsub('[^%w]+', '-'):gsub('^%-+', ''):gsub('%-+$', '')
end
local function storeSlug(r) return slugify((r.label or '') .. '-' .. (r.area or '')) end
local function chainSlug(r) return slugify(r.label) end   -- one picture for every 24/7, LTD, ...

local function scanStorePics()
    local found = 0
    for _, r in ipairs(Config.Restaurants) do
        local slug = storeSlug(r)
        storePics[slug] = nil
        for _, name in ipairs({ slug, chainSlug(r) }) do   -- this location first, then the chain picture
            for _, ext in ipairs(PHOTO_EXT) do
                if not storePics[slug] and LoadResourceFile(RES, PHOTO_DIR .. name .. '.' .. ext) then
                    storePics[slug] = ('https://cfx-nui-%s/%s%s.%s'):format(RES, PHOTO_DIR, name, ext)
                end
            end
        end
        if storePics[slug] then found = found + 1 end
    end
    return found
end

local function storePhoto(r) return storePics[storeSlug(r)] end

local function listStorePics()
    print(('[nrp-doordrop] Store pictures: %d of %d found in %s'):format(scanStorePics(), #Config.Restaurants, PHOTO_DIR))
    for _, r in ipairs(Config.Restaurants) do
        print(('   %s  %s%s.jpg  (or %s.jpg for every %s)'):format(storePhoto(r) and '[x]' or '[ ]', PHOTO_DIR, storeSlug(r), chainSlug(r), r.label))
    end
end

CreateThread(function() Wait(1000) listStorePics() end)
RegisterCommand('ddstores', function(src) if src == 0 then listStorePics() end end, true)

-- Recent player orders per character, for the Orders tab (kept until a restart)
local Recent = {}
local function rememberOrder(cid, o)
    local list = Recent[cid] or {}
    table.insert(list, 1, o)
    while #list > 8 do table.remove(list) end
    Recent[cid] = list
end

local function recentFor(cid)
    local out = {}
    for _, o in ipairs(Recent[cid] or {}) do
        local r = Config.Restaurants[o.r]
        local status = o.status
        if Orders[o.id] then status = 'active'
        elseif status ~= 'delivered' and status ~= 'cancelled' then status = 'ended' end
        local n = 0
        for _, it in ipairs(o.list or {}) do n = n + (it.qty or 0) end
        out[#out + 1] = { id = o.id, restaurant = r and r.label or '?', area = r and r.area or '', r = o.r,
                          total = o.total, count = n, t = o.createdAt, status = status }
    end
    return out
end

local function freeDriverCount(exceptSrc)
    local n = 0
    for src, s in pairs(Sessions) do
        if src ~= exceptSrc and s.online and not s.order then n = n + 1 end
    end
    return n
end

lib.callback.register('nrp-doordrop:customer:menu', function(src, opts)
    if not Config.Customer.enabled then return { disabled = true } end
    local s = getSession(src)
    if not s then return nil end
    local hour = type(opts) == 'table' and tonumber(opts.hour) or nil
    local pc = GetEntityCoords(GetPlayerPed(src))
    local list = {}
    for i, r in ipairs(Config.Restaurants) do
        local menu = {}
        for j, m in ipairs(r.menu or {}) do
            if m.item and m.price then
                menu[#menu + 1] = { i = j, label = m.label, price = m.price, item = m.item, image = m.image or (m.item .. '.png') }
            end
        end
        if #menu > 0 and not r.disabled then
            local art = (Config.StoreArt and Config.StoreArt[r.label]) or {}
            local h = storeHours(r)
            local open = isOpen(r, hour)
            list[#list + 1] = { i = i, label = r.label, area = r.area, category = r.category, menu = menu,
                                miles = round1(distXY(pc, r.pickup) * Config.RoadFactor / MILE),
                                meters = math.floor(distXY(pc, r.pickup)), x = r.pickup.x, y = r.pickup.y,
                                open = open,
                                hours = h and not (h[2] - h[1] >= 24 or h[1] == h[2]) and ('%s - %s'):format(hourLabel(h[1]), hourLabel(h[2])) or nil,
                                opensAt = (not open and h) and hourLabel(h[1]) or nil,
                                color = r.color or art.color, icon = r.icon or art.icon,
                                banner = r.banner or storePhoto(r) or art.banner, logo = r.logo or art.logo }
        end
    end
    table.sort(list, function(a, b) return a.meters < b.meters end)
    return {
        restaurants = list,
        deliveryFee = Config.Customer.deliveryFee,
        serviceRate = Config.Customer.serviceRate,
        tipPercents = Config.Customer.tipPercents, defaultTip = Config.Customer.defaultTip,
        minTip = Config.Customer.minTip, maxTip = Config.Customer.maxTip,
        maxQty = Config.Customer.maxQty, maxItems = Config.Customer.maxItems,
        drivers = freeDriverCount(src),
        npcCourier = Config.NpcCourier.enabled,
        recent = recentFor(s.cid),
    }
end)

lib.callback.register('nrp-doordrop:customer:place', function(src, data)
    if not Config.Customer.enabled then return { ok = false, reason = 'Ordering is turned off.' } end
    local s = getSession(src)
    if not s or type(data) ~= 'table' then return { ok = false, reason = 'Try again.' } end
    if activeOrderFor(s.cid) then return { ok = false, reason = 'You already have an order on the way.' } end

    local r = Config.Restaurants[tonumber(data.restaurant) or -1]
    if not r or r.disabled or type(data.items) ~= 'table' then return { ok = false, reason = 'Pick a restaurant and some food.' } end
    if not isOpen(r, data.hour) then return { ok = false, reason = ('%s is closed right now.'):format(r.label) } end
    local noDrivers = freeDriverCount(src) == 0
    if noDrivers and not Config.NpcCourier.enabled then return { ok = false, reason = 'No drivers are clocked in right now.' } end

    local list, subtotal, count = {}, 0, 0
    for k, q in pairs(data.items) do
        local m = r.menu[tonumber(k) or -1]
        q = math.floor(tonumber(q) or 0)
        if m and m.item and q > 0 then
            q = math.min(q, Config.Customer.maxQty)
            list[#list + 1] = { item = m.item, label = m.label, qty = q, price = m.price }
            subtotal = subtotal + m.price * q
            count = count + q
        end
    end
    if count == 0 then return { ok = false, reason = 'Your cart is empty.' } end
    if count > Config.Customer.maxItems then return { ok = false, reason = ('Max %d items per order.'):format(Config.Customer.maxItems) } end

    local tip = math.max(0, math.min(Config.Customer.maxTip, math.floor(tonumber(data.tip) or 0)))
    local deliveryFee = Config.Customer.deliveryFee
    local serviceFee = math.ceil(subtotal * Config.Customer.serviceRate)
    local total = subtotal + deliveryFee + serviceFee + tip

    local Player = getPlayer(src)
    if not Player or not Player.Functions.RemoveMoney('bank', total, 'doordrop-order') then
        return { ok = false, reason = ('Not enough in your bank for $%d.'):format(total) }
    end

    local ped = GetPlayerPed(src)
    local c = GetEntityCoords(ped)
    local o = {
        id = nextId(), src = src, cid = s.cid, name = charName(src), r = tonumber(data.restaurant),
        list = list, subtotal = subtotal, deliveryFee = deliveryFee, serviceFee = serviceFee, tip = tip, total = total,
        handoff = data.handoff == 'door' and 'door' or 'hand',
        coords = vector4(c.x, c.y, c.z, GetEntityHeading(ped)),
        street = clean(data.street, 40) ~= '' and clean(data.street, 40) or 'Customer',
        area = clean(data.area, 40),
        status = 'searching', tried = {}, createdAt = os.time(),
    }
    Orders[o.id] = o
    Rateable[s.cid] = nil
    rememberOrder(s.cid, o)
    if noDrivers then assignNpc(o) end
    dbg(('player order %d by %s: $%d'):format(o.id, o.name, total))
    return { ok = true, order = customerPayload(o) }
end)

lib.callback.register('nrp-doordrop:customer:cancel', function(src)
    local cid = citizenId(src)
    local o = cid and activeOrderFor(cid)
    if not o then return { ok = false, reason = 'No order to cancel.' } end
    if o.status == 'arriving' then return { ok = false, reason = 'Your courier is already at your door.' } end
    local refundAmt = o.total
    if o.status == 'pickedup' then
        -- the food is already made and on the way, like the real thing: only part (or none) comes back
        refundAmt = math.floor(o.total * (Config.Customer.lateCancelRefund or 0) + 0.5)
    end
    local msg = refundAmt > 0 and ('Order cancelled. $%d refunded.'):format(refundAmt)
        or 'Order cancelled. Your food was already picked up, so there was no refund.'
    cancelPlayerOrder(o, msg, false, refundAmt)
    dbg(('order %d cancelled by the customer (%s), refunded $%d'):format(o.id, o.status, refundAmt))
    return { ok = true, refunded = refundAmt, message = msg }
end)

lib.callback.register('nrp-doordrop:customer:rate', function(src, stars, text)
    local cid = citizenId(src)
    local rate = cid and Rateable[cid]
    if not rate or os.time() > rate.expires then return { ok = false, reason = 'Nothing to rate.' } end
    Rateable[cid] = nil
    stars = math.floor(tonumber(stars) or 0)
    if stars < 1 or stars > 5 then return { ok = true } end -- skipped

    local p = loadProfile(rate.driverCid)
    push(p.ratings, stars)
    text = clean(text, 200)
    if text ~= '' then addReview(p, stars, text, charName(src)) end
    -- fill in the star count on the driver's history entry
    for _, h in ipairs(p.history) do
        if h.stars == nil and h.restaurant == rate.restaurant then h.stars = stars break end
    end
    saveProfile(rate.driverCid)

    local driverSrc = rate.driverSrc
    if GetPlayerPed(driverSrc) ~= 0 and citizenId(driverSrc) == rate.driverCid then
        TriggerClientEvent('nrp-doordrop:client:review', driverSrc, stars, text ~= '' and text or nil)
        sendState(driverSrc)
    end
    return { ok = true }
end)

-- The customer's client finished the courier hand-off / drop.
lib.callback.register('nrp-doordrop:customer:npcDelivered', function(src, id, note)
    local cid = citizenId(src)
    local o = cid and activeOrderFor(cid)
    if not o or not o.npc or o.id ~= id or o.status ~= 'arriving' then return false end
    return completeNpc(o, type(note) == 'string' and clean(note, 120) or nil)
end)

---------------------------------------------------------------------
-- Cleanup & refunds
---------------------------------------------------------------------
local function dropSession(src)
    -- as a customer
    for _, o in pairs(Orders) do
        if o.src == src then
            if o.status == 'pickedup' and o.driver then
                -- driver already has the food: they still get paid, order ends
                local ds = Sessions[o.driver]
                if ds and ds.order and ds.order.playerOrder == o.id then
                    local pay = ds.order.total
                    local P = getPlayer(o.driver)
                    if P then P.Functions.AddMoney('bank', pay, 'doordrop-delivery') end
                    ds.order = nil
                    TriggerClientEvent('nrp-doordrop:client:orderCancelled', o.driver, ('The customer left the city. You were paid $%d.'):format(pay))
                    sendState(o.driver)
                end
                Orders[o.id] = nil
            else
                cancelPlayerOrder(o, nil, true)
            end
        end
    end
    -- as a driver
    local s = Sessions[src]
    if not s then return end
    if s.offer and s.offer.playerOrder and Orders[s.offer.playerOrder] then
        Orders[s.offer.playerOrder].offeredTo = nil
    end
    if s.order then unassign(src, s, false) end
    saveProfile(s.cid)
    Sessions[src] = nil
end

AddEventHandler('playerDropped', function() dropSession(source) end)
AddEventHandler('QBCore:Server:OnPlayerUnload', function(src) dropSession(src) end)

-- Pay out refunds owed from orders cancelled while the customer was offline.
AddEventHandler('QBCore:Server:PlayerLoaded', function(Player)
    local src, cid = Player.PlayerData.source, Player.PlayerData.citizenid
    CreateThread(function()
        local p = loadProfile(cid)
        if p.refund > 0 then
            local amt = p.refund
            p.refund = 0
            Player.Functions.AddMoney('bank', amt, 'doordrop-refund')
            saveProfile(cid)
            TriggerClientEvent('ox_lib:notify', src, { title = Config.AppName, description = ('$%d refunded for a cancelled order.'):format(amt), type = 'inform' })
        end
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, o in pairs(Orders) do
        refund(o.cid, o.src, o.total, 'DoorDrop restarted. Your order was refunded.')
        if o.live then safeDelete(o.live.ped) safeDelete(o.live.veh) end
    end
    for _, e in pairs(Leaving) do safeDelete(e.ped) safeDelete(e.veh) end
    for _, l in pairs(Loot) do safeDelete(l.obj) end
    GlobalState.ddCouriers = {}
    for _, s in pairs(Sessions) do saveProfile(s.cid) end
end)
