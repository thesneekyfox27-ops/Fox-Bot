--[[ nrp-movingjob | server/main.lua
     Holds contract state, validates every step against real player positions,
     and is the only thing that ever touches money.
]]

local QBCore = exports['qb-core']:GetCoreObject()

local Jobs    = {}   -- [leaderSrc] = job
local Members = {}   -- [src] = leaderSrc
local Offers  = {}   -- [src] = { [id] = contract }
local LastEvent = {} -- [src] = timestamp
local Invites = {}   -- [targetSrc] = { from = src, expires = ms }

local function now() return GetGameTimer() end

local function warn(src, what)
    if not Config.LogSuspicious then return end
    local name = GetPlayerName(src) or 'unknown'
    print(('[nrp-movingjob] dropped event from %s (%s): %s'):format(name, src, what))
end

--- Rate limit. Returns false if this player is firing events too fast.
--- Rate limit, bucketed per event type. A single shared timestamp meant a
--- burst of one event could swallow an unrelated one and silently lose a
--- delivery.
local function throttled(src, bucket)
    bucket = bucket or 'default'
    LastEvent[src] = LastEvent[src] or {}
    local last = LastEvent[src][bucket]
    if last and now() - last < Config.EventCooldownMs then return true end
    LastEvent[src][bucket] = now()
    return false
end

local function tell(src, msg, kind)
    TriggerClientEvent('ox_lib:notify', src, {
        title = Config.CompanyName,
        description = msg,
        type = kind or 'error'
    })
end

local function playerCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

--- Every progress event has to come from someone actually standing there.
local function near(src, coords)
    local pos = playerCoords(src)
    if not pos then return false end
    return #(pos - coords) <= Config.MaxActionDistance
end

local function jobOf(src)
    local leader = Members[src]
    if not leader then return nil, nil end
    return Jobs[leader], leader
end

local function crewOf(job)
    local out = { job.leader }
    for _, m in ipairs(job.crew) do out[#out + 1] = m end
    return out
end

--- Push the server's own counts to the crew. The client keeps an optimistic
--- copy for responsiveness; this is what corrects it.
local function pushProgress(job)
    for _, src in ipairs(crewOf(job)) do
        TriggerClientEvent('nrp-movingjob:client:progress', src, {
            loaded    = job.loaded,
            delivered = job.delivered,
            damaged   = job.damaged,
            total     = job.contract.itemCount,
            stage     = job.stage
        })
    end
end

local function toCrew(job, event, ...)
    for _, src in ipairs(crewOf(job)) do
        TriggerClientEvent(event, src, ...)
    end
end

local function randomPlate()
    local chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    local plate = Config.Van.platePrefix
    for _ = 1, 8 - #plate do
        if math.random() > 0.5 then
            local i = math.random(#chars)
            plate = plate .. chars:sub(i, i)
        else
            plate = plate .. math.random(0, 9)
        end
    end
    return plate
end

-- ---------------------------------------------------------------------------
-- contract generation
-- ---------------------------------------------------------------------------
--- Price a contract from its items and how far the address is from the yard.
local function priceContract(items, drop)
    local P = Config.Pay
    local itemPay, byWeight = 0, {}
    for _, idx in ipairs(items) do
        local weight = (Config.Cargo[idx] and Config.Cargo[idx].weight) or 'medium'
        itemPay = itemPay + (P.perItem[weight] or P.perItem.medium or 0)
        byWeight[weight] = (byWeight[weight] or 0) + 1
    end

    local a, b = Config.Drops[drop].arrival, Config.Boss.coords
    local miles = #(vector3(a.x, a.y, a.z) - vector3(b.x, b.y, b.z)) * 0.000621371
    local mileage = math.floor(miles * (P.perMile or 0) + 0.5)

    return {
        itemPay  = itemPay,
        byWeight = byWeight,
        callout  = P.callout or 0,
        miles    = math.floor(miles * 10 + 0.5) / 10,
        mileage  = mileage,
        total    = itemPay + (P.callout or 0) + mileage
    }
end

--- What one person takes home with `size` people on the job.
local function shareFor(total, size)
    size = math.max(1, size)
    if not Config.Crew.splitPay then return total end
    local boosted = total * (1 + (Config.Pay.crewBonus or 0) * (size - 1))
    return math.floor(boosted / size)
end

local function makeContract(id)
    local count = math.random(Config.Contracts.minItems, Config.Contracts.maxItems)
    count = math.min(count, #Config.Van.slots)

    local items = {}
    for i = 1, count do
        items[i] = math.random(#Config.Cargo)
    end

    local drop  = math.random(#Config.Drops)
    local price = priceContract(items, drop)

    return {
        id         = id,
        customer   = Config.Customers[math.random(#Config.Customers)],
        drop       = drop,
        items      = items,
        itemCount  = count,
        price      = price,
        -- kept for the ox_lib menus: average per item, and the part paid on completion
        payPerItem = math.floor(price.itemPay / count + 0.5),
        bonus      = price.callout + price.mileage
    }
end

lib.callback.register('nrp-movingjob:server:getContracts', function(src)
    if Members[src] then return nil end

    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return nil end
    if Config.RequireJob and Player.PlayerData.job.name ~= Config.RequireJob then
        TriggerClientEvent('ox_lib:notify', src, {
            title = Config.CompanyName,
            description = 'They only hand contracts to their own crews.',
            type = 'error'
        })
        return nil
    end

    local list, public = {}, {}
    Offers[src] = {}
    for i = 1, Config.Contracts.offered do
        local c = makeContract(i)
        Offers[src][i] = c
        -- The item list stays server side until the contract is accepted.
        public[#public + 1] = {
            id = c.id, customer = c.customer, drop = c.drop,
            itemCount = c.itemCount, payPerItem = c.payPerItem, bonus = c.bonus,
            price = c.price
        }
    end
    return public
end)

-- ---------------------------------------------------------------------------
-- accept / abandon
-- ---------------------------------------------------------------------------
--- Invite `target` onto `src`'s crew. Shared by the crew sheet and the
--- crew picked on the contract before signing. Returns true if sent.
local function inviteToCrew(src, job, target)
    if #job.crew + 1 >= Config.Crew.maxMembers then
        tell(src, 'The crew is full.')
        return false
    end

    target = tonumber(target)
    if not target or target == src then return false end
    if Members[target] then
        tell(src, ('%s is already working.'):format(GetPlayerName(target) or ('ID ' .. target)))
        return false
    end

    local a, b = playerCoords(src), playerCoords(target)
    if not a or not b or #(a - b) > Config.Crew.inviteRange + 3.0 then
        tell(src, ('%s is too far away to invite.'):format(GetPlayerName(target) or ('ID ' .. target)))
        return false
    end

    Invites[target] = { from = src, expires = now() + Config.Crew.inviteMs }
    TriggerClientEvent('nrp-movingjob:client:invited', target, GetPlayerName(src), src)
    return true
end

--- "Bob  Myers", "bob myers", "Bob Myers." all count as the same name
local function normName(s)
    s = tostring(s or ''):lower():gsub("[^%a%s'%-]", ''):gsub('%s+', ' ')
    return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

RegisterNetEvent('nrp-movingjob:server:accept', function(id, signature, crew)
    local src = source
    if throttled(src) then return end
    if Members[src] then return end

    local offer = Offers[src] and Offers[src][id]
    if not offer then return warn(src, 'accepted a contract that was never offered') end
    if not near(src, vector3(Config.Boss.coords.x, Config.Boss.coords.y, Config.Boss.coords.z)) then
        return warn(src, 'accepted a contract from off site')
    end

    -- The clipboard contract has to be signed with the character's real name.
    local pw = Config.Paperwork
    if pw and pw.enabled ~= false and pw.mustMatchName ~= false then
        local Player = QBCore.Functions.GetPlayer(src)
        local ci = Player and Player.PlayerData and Player.PlayerData.charinfo
        local real = ci and normName(('%s %s'):format(ci.firstname or '', ci.lastname or '')) or ''
        if real ~= '' and normName(signature) ~= real then
            TriggerClientEvent('ox_lib:notify', src, {
                title = Config.CompanyName,
                description = ('Sign the contract with your real name: %s %s')
                    :format(ci.firstname or '', ci.lastname or ''),
                type = 'error'
            })
            return
        end
    end

    Offers[src] = nil

    local job = {
        leader    = src,
        crew      = {},
        contract  = offer,
        plate     = randomPlate(),
        stage     = 'loading',
        loaded    = 0,
        delivered = 0,
        damaged   = 0,
        started   = now()
    }
    Jobs[src] = job
    Members[src] = src

    local payload = {
        id = offer.id, customer = offer.customer, drop = offer.drop,
        items = offer.items, payPerItem = offer.payPerItem, bonus = offer.bonus,
        price = offer.price, plate = job.plate
    }
    TriggerClientEvent('nrp-movingjob:client:started', src, payload, true)

    -- crew picked on the contract before signing: invite them straight away
    if Config.Crew.enabled and type(crew) == 'table' then
        local sent = 0
        for _, target in ipairs(crew) do
            if sent >= Config.Crew.maxMembers - 1 then break end
            if inviteToCrew(src, job, target) then sent = sent + 1 end
        end
        if sent > 0 then
            tell(src, ('Crew invite sent to %d %s.'):format(sent, sent == 1 and 'person' or 'people'), 'success')
        end
    end
end)

local function endJob(job, reason, payload)
    for _, src in ipairs(crewOf(job)) do
        Members[src] = nil
        if reason then
            TriggerClientEvent('nrp-movingjob:client:cancelled', src, reason)
        else
            TriggerClientEvent('nrp-movingjob:client:stageChanged', src, 'done', payload)
        end
    end
    Jobs[job.leader] = nil
end

RegisterNetEvent('nrp-movingjob:server:abandon', function()
    local src = source
    local job, leader = jobOf(src)
    if not job then return end

    if src == leader then
        endJob(job, 'Contract abandoned.')
    else
        -- A hired hand quitting just leaves the crew.
        for i, m in ipairs(job.crew) do
            if m == src then table.remove(job.crew, i) break end
        end
        Members[src] = nil
        TriggerClientEvent('nrp-movingjob:client:cancelled', src, 'You left the crew.')
    end
end)

-- ---------------------------------------------------------------------------
-- progress
-- ---------------------------------------------------------------------------
RegisterNetEvent('nrp-movingjob:server:loaded', function(count)
    local src = source
    if throttled(src, 'loaded') then return end
    local job = jobOf(src)
    if not job or job.stage ~= 'loading' then return end
    if not near(src, Config.Depot.pallet) then
        return warn(src, 'loaded cargo from off site')
    end

    -- Trust our own counter, not the client's number.
    job.loaded = job.loaded + 1
    if job.loaded > job.contract.itemCount then
        job.loaded = job.contract.itemCount
        return warn(src, 'loaded more items than the contract has')
    end

    if job.loaded >= job.contract.itemCount then
        job.stage = 'transit'
        toCrew(job, 'nrp-movingjob:client:stageChanged', 'transit')
    end
end)

RegisterNetEvent('nrp-movingjob:server:arrived', function()
    local src = source
    local job = jobOf(src)
    if not job or job.stage ~= 'transit' then return end
    job.stage = 'unloading'
    toCrew(job, 'nrp-movingjob:client:stageChanged', 'unloading')
end)

RegisterNetEvent('nrp-movingjob:server:delivered', function(_, broken)
    local src = source
    if throttled(src, 'delivered') then return end
    local job = jobOf(src)
    if not job then return end
    if job.stage ~= 'unloading' and job.stage ~= 'transit' then return end

    -- Already counted everything. Nothing to do, but resync the client so it
    -- is not left thinking the job is unfinished.
    if job.delivered >= job.contract.itemCount then
        pushProgress(job)
        return
    end

    local drop = Config.Drops[job.contract.drop]
    if not near(src, drop.arrival) then
        -- Previously this dropped the event in silence. If it happened on the
        -- last item the contract could never complete and the player got no
        -- explanation at all, so say something.
        warn(src, 'delivered cargo from off site')
        tell(src, 'That was too far from the address to count. Move closer and set it down again.')
        pushProgress(job)
        return
    end

    job.delivered = job.delivered + 1
    if broken == true then job.damaged = job.damaged + 1 end

    if job.delivered >= job.contract.itemCount then
        job.delivered = job.contract.itemCount
        job.stage = 'returning'
        pushProgress(job)
        toCrew(job, 'nrp-movingjob:client:stageChanged', 'returning')
        return
    end

    pushProgress(job)
end)

--- Repair a desync. The client calls this when it believes the contract is
--- finished but the server has not moved to 'returning'.
lib.callback.register('nrp-movingjob:server:syncJob', function(src)
    local job = jobOf(src)
    if not job then return nil end

    -- If every item really is on the ground, let the stage catch up rather
    -- than stranding the player with an uncompletable contract.
    if job.stage == 'unloading' or job.stage == 'transit' then
        if job.delivered >= job.contract.itemCount then
            job.stage = 'returning'
            toCrew(job, 'nrp-movingjob:client:stageChanged', 'returning')
        end
    end

    pushProgress(job)
    return {
        loaded    = job.loaded,
        delivered = job.delivered,
        damaged   = job.damaged,
        total     = job.contract.itemCount,
        stage     = job.stage
    }
end)

-- ---------------------------------------------------------------------------
-- payout
-- ---------------------------------------------------------------------------
RegisterNetEvent('nrp-movingjob:server:finish', function(vanNet)
    local src = source
    if throttled(src, 'finish') then return end
    local job, leader = jobOf(src)
    if not job then return end
    if src ~= leader then
        return TriggerClientEvent('ox_lib:notify', src, {
            title = Config.CompanyName,
            description = 'The crew boss settles up, not you.',
            type = 'error'
        })
    end
    if job.stage ~= 'returning' then return warn(src, 'tried to cash out early') end
    if not near(src, vector3(Config.Boss.coords.x, Config.Boss.coords.y, Config.Boss.coords.z)) then
        return warn(src, 'tried to cash out from off site')
    end

    local contract = job.contract
    local price    = contract.price
    local count    = #contract.items
    local avgItem  = price.itemPay / count

    -- items are paid for what actually arrived; the callout and mileage come
    -- with the finished job. Broken pieces cost part of an item's pay.
    local gross   = avgItem * math.min(job.delivered, count) + price.callout + price.mileage
    local penalty = avgItem * Config.Contracts.damagePenalty * job.damaged
    local total   = math.max(0, math.floor(gross - penalty + 0.5))

    local crew  = crewOf(job)
    local share = shareFor(total, #crew)

    for _, member in ipairs(crew) do
        local Player = QBCore.Functions.GetPlayer(member)
        if Player then
            Player.Functions.AddMoney(Config.PayAccount, share, 'moving-contract')
            TriggerClientEvent('nrp-movingjob:client:stageChanged', member, 'done', {
                pay = share, damaged = job.damaged
            })
            Members[member] = nil
        end
    end

    -- The van is deleted client side by the leader; clean up the entity too in
    -- case it was orphaned.
    if vanNet then
        local veh = NetworkGetEntityFromNetworkId(vanNet)
        if veh and veh ~= 0 and DoesEntityExist(veh) then DeleteEntity(veh) end
    end

    Jobs[leader] = nil
end)

--- Server side key grant. Tries the known 0r-vehiclekeys server signatures and
--- stops at the first that does not error; falls back to the client event.
local function grantKeys(src, plate)
    if GetResourceState(Config.KeyResource) == 'started' then
        local attempts = {
            function() return exports[Config.KeyResource]:GiveKeys(src, plate) end,
            function() return exports[Config.KeyResource]:AddKey(src, plate) end,
            function() return exports[Config.KeyResource]:SetKey(src, plate, true) end
        }
        for i, attempt in ipairs(attempts) do
            if pcall(attempt) then
                if Config.KeyDebug then
                    print(('[nrp-movingjob] server key grant landed on attempt %d for %s -> %s'):format(i, plate, src))
                end
                return true
            end
        end
    end

    -- Nothing server side worked, so push it back to the client.
    TriggerClientEvent(Config.KeyResource .. ':client:AddKey', src, plate)
    return false
end

RegisterNetEvent('nrp-movingjob:server:grantKeys', function(plate, vanNet)
    local src = source
    local job, leader = jobOf(src)
    if not job or job.plate ~= plate then
        return warn(src, 'asked for keys to a van that is not theirs')
    end

    -- The leader is the one who spawned it, so that is the netId we trust.
    if vanNet and src == leader then
        job.vanNet = vanNet
        -- Anyone already on the crew gets the van and its keys now.
        for _, member in ipairs(job.crew) do
            TriggerClientEvent('nrp-movingjob:client:syncVan', member, vanNet)
        end
    end

    grantKeys(src, plate)
end)

-- ---------------------------------------------------------------------------
-- crew
-- ---------------------------------------------------------------------------
RegisterNetEvent('nrp-movingjob:server:invite', function(target)
    local src = source
    if not Config.Crew.enabled then return end
    if throttled(src, 'invite') then return end

    local job, leader = jobOf(src)
    if not job or src ~= leader then return end
    inviteToCrew(src, job, target)
end)

RegisterNetEvent('nrp-movingjob:server:inviteResponse', function(fromSrc, accepted)
    local src = source
    local invite = Invites[src]
    Invites[src] = nil
    if not invite or invite.from ~= fromSrc then return end
    if now() > invite.expires then return end
    if not accepted then
        return TriggerClientEvent('ox_lib:notify', fromSrc, {
            title = Config.CompanyName, description = 'They turned you down.', type = 'error'
        })
    end

    local job = Jobs[fromSrc]
    if not job or Members[src] then return end
    if #job.crew + 1 >= Config.Crew.maxMembers then return end

    job.crew[#job.crew + 1] = src
    Members[src] = fromSrc

    local contract = job.contract
    TriggerClientEvent('nrp-movingjob:client:started', src, {
        id = contract.id, customer = contract.customer, drop = contract.drop,
        items = contract.items, payPerItem = contract.payPerItem, bonus = contract.bonus,
        price = contract.price, plate = job.plate
    }, false)
    TriggerClientEvent('nrp-movingjob:client:stageChanged', src, job.stage)

    -- Hand them the van and its keys so they can drive it too.
    if job.vanNet then
        TriggerClientEvent('nrp-movingjob:client:syncVan', src, job.vanNet)
    end
    grantKeys(src, job.plate)

    TriggerClientEvent('ox_lib:notify', fromSrc, {
        title = Config.CompanyName,
        description = ('%s is on the crew.'):format(GetPlayerName(src)),
        type = 'success'
    })

    -- everyone's paperwork shows their share, so tell them the crew size
    local members = crewOf(job)
    for _, member in ipairs(members) do
        TriggerClientEvent('nrp-movingjob:client:crewSize', member, #members)
    end
end)

-- ---------------------------------------------------------------------------
-- cleanup
-- ---------------------------------------------------------------------------
AddEventHandler('playerDropped', function()
    local src = source
    local job, leader = jobOf(src)
    Offers[src] = nil
    LastEvent[src] = nil
    Invites[src] = nil

    if not job then return end
    if src == leader then
        endJob(job, 'The crew boss disconnected.')
    else
        for i, m in ipairs(job.crew) do
            if m == src then table.remove(job.crew, i) break end
        end
        Members[src] = nil
    end
end)

-- Expire stale invites.
CreateThread(function()
    while true do
        Wait(15000)
        for src, invite in pairs(Invites) do
            if now() > invite.expires then Invites[src] = nil end
        end
    end
end)
