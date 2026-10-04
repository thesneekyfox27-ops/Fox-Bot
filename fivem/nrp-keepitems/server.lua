-- ============================================================
--  nrp-keepitems v2 - keep your legal items when you die
--
--  * Every player's inventory is snapshotted all the time, so the
--    state from BEFORE a death is always known (even if a script
--    wipes you the instant you die).
--  * While you are down, any KEPT item that disappears is given
--    straight back - unless a player standing next to you gained
--    that exact item at the same moment (they robbed you).
--  * For a while after you're revived / respawned, a wipe (most or
--    all of your inventory gone at once) is undone for kept items.
--  * Illegal items (Config.LoseItems / LosePatterns) are never
--    given back.
-- ============================================================

local QBCore = exports['qb-core']:GetCoreObject()

local state      = {}   -- [src] = { snap, stacks, down, verified, reviveUntil, lastDown }
local allowUntil = {}   -- [src] = os.time() until which removals are allowed
local readMethod = nil  -- how we read inventories (found at runtime)

local function dbg(...)
    if Config.Debug then print('[nrp-keepitems]', ...) end
end

-- ------------------------------------------------------------
--  Keep / lose rules
-- ------------------------------------------------------------
local function keeps(name)
    if not name then return false end
    if Config.KeepEverything or Config.KeepAnyway[name] then return true end
    if Config.LoseItems[name] then return false end
    local lname = name:lower()
    for _, p in ipairs(Config.LosePatterns) do
        if lname:find(p) then return false end
    end
    return true
end

-- ------------------------------------------------------------
--  Reading inventories (tgiann first, QBCore as fallback)
-- ------------------------------------------------------------
local INV = Config.InventoryResource or 'tgiann-inventory'

local readers = {
    { name = INV .. ':GetPlayerItems', fn = function(src) return exports[INV]:GetPlayerItems(src) end },
    { name = INV .. ':GetInventory',   fn = function(src) return exports[INV]:GetInventory(src) end },
    { name = INV .. ':GetPlayerInventory', fn = function(src) return exports[INV]:GetPlayerInventory(src) end },
    { name = 'QBCore PlayerData.items', fn = function(src)
        local P = QBCore.Functions.GetPlayer(src)
        return P and P.PlayerData.items or nil
    end },
}

local function tryRead(r, src)
    if r.name ~= 'QBCore PlayerData.items' and GetResourceState(INV) ~= 'started' then return nil end
    local ok, res = pcall(r.fn, src)
    if ok and type(res) == 'table' then
        if type(res.items) == 'table' then res = res.items end   -- some return { items = {...} }
        return res
    end
    return nil
end

local function rawItems(src)
    if readMethod then
        local res = tryRead(readMethod, src)
        if res then return res end
    end
    for _, r in ipairs(readers) do
        local res = tryRead(r, src)
        if res then
            if readMethod ~= r then
                readMethod = r
                print(('[nrp-keepitems] reading inventories with %s'):format(r.name))
            end
            return res
        end
    end
    return nil
end

local function infoOf(it) return it.info or it.metadata end

local function keyOf(it)
    local info = infoOf(it)
    if type(info) == 'table' and next(info) then
        return it.name .. '|' .. json.encode(info)
    end
    return it.name
end

-- { [key] = { name, amount, info, slot } }, stacks
local function snapshot(src)
    local items = rawItems(src)
    if not items then return nil, 0 end
    local snap, stacks = {}, 0
    for slot, it in pairs(items) do
        local amount = type(it) == 'table' and tonumber(it.amount or it.count) or 0
        if amount and amount > 0 and it.name then
            stacks = stacks + 1
            local k = keyOf(it)
            local s = snap[k]
            if s then s.amount = s.amount + amount
            else snap[k] = { name = it.name, amount = amount, info = infoOf(it), slot = it.slot or slot } end
        end
    end
    return snap, stacks
end

-- ------------------------------------------------------------
--  Giving items back
-- ------------------------------------------------------------
local function giveBack(src, s, amount)
    if GetResourceState(INV) == 'started' then
        for _, slot in ipairs({ s.slot, false }) do
            local ok, res = pcall(function() return exports[INV]:AddItem(src, s.name, amount, slot or nil, s.info) end)
            if ok and res ~= false then return true end
        end
    end
    local P = QBCore.Functions.GetPlayer(src)
    if not P then return false end
    return P.Functions.AddItem(s.name, amount, s.slot, s.info) or P.Functions.AddItem(s.name, amount, false, s.info)
end

local function logRestore(src, why, list)
    local P = QBCore.Functions.GetPlayer(src)
    local ci = P and P.PlayerData.charinfo or {}
    local who = P and ('%s %s (%s)'):format(ci.firstname or '?', ci.lastname or '?', P.PlayerData.citizenid) or ('id ' .. src)
    local parts = {}
    for _, r in ipairs(list) do parts[#parts + 1] = ('%dx %s'):format(r.amount, r.name) end
    local line = ('%s - %s - gave back: %s'):format(who, why, table.concat(parts, ', '))
    print('[nrp-keepitems] ' .. line)
    if Config.Webhook and Config.Webhook ~= '' then
        PerformHttpRequest(Config.Webhook, function() end, 'POST',
            json.encode({ username = 'Keep Items', embeds = { { title = 'Items kept on death', description = line, color = 3066993 } } }),
            { ['Content-Type'] = 'application/json' })
    end
end

-- give back every KEPT item that is in `old` but missing from `now`
-- (minus anything a nearby player just picked up: `taken[itemName] = amount`,
-- matched by NAME so a robbery is never undone even if metadata changed)
local function restoreMissing(src, old, now, taken, why)
    local list = {}
    for k, s in pairs(old) do
        if keeps(s.name) then
            local missing = s.amount - (now[k] and now[k].amount or 0)
            local robbed = math.min(missing, taken[s.name] or 0)
            if robbed > 0 then
                taken[s.name] = taken[s.name] - robbed
                missing = missing - robbed
            end
            if missing > 0 and giveBack(src, s, missing) then
                list[#list + 1] = { name = s.name, amount = missing }
            end
        end
    end
    if #list > 0 then
        logRestore(src, why, list)
        TriggerClientEvent('QBCore:Notify', src, 'You kept your belongings. Anything illegal is gone.', 'primary')
    end
    return #list
end

-- ------------------------------------------------------------
--  Who is down (several signals - any one of them counts)
-- ------------------------------------------------------------
local clientDown = {}   -- [src] = true while the client reports being dead/downed
local eventDown  = {}   -- [src] = true from ambulance-job events

local function serverSaysDown(src)
    local P = QBCore.Functions.GetPlayer(src)
    if P then
        local m = P.PlayerData.metadata or {}
        if m.isdead or m.inlaststand or m.isDead or m.dead then return true end
    end
    local sb = Player(src) and Player(src).state
    if sb and (sb.isDead or sb.dead or sb.down or sb.inlaststand or sb.isDown) then return true end
    local ped = GetPlayerPed(src)
    if ped ~= 0 and GetEntityHealth(ped) <= 0 then return true end
    return eventDown[src] == true
end

-- ------------------------------------------------------------
--  Main loop
-- ------------------------------------------------------------
local function near(a, b, range)
    local pa, pb = GetPlayerPed(a), GetPlayerPed(b)
    if pa == 0 or pb == 0 then return false end
    return #(GetEntityCoords(pa) - GetEntityCoords(pb)) <= range
end

local function tick()
    local players = QBCore.Functions.GetPlayers()
    local now = os.time()

    -- 1) read everyone once, and work out who gained what this tick
    local cur, gains = {}, {}
    for _, src in ipairs(players) do
        local snap, stacks = snapshot(src)
        if snap then
            cur[src] = { snap = snap, stacks = stacks }
            local st = state[src]
            if st then
                -- totals per item NAME, before vs now
                local was, is = {}, {}
                for _, s in pairs(st.snap) do was[s.name] = (was[s.name] or 0) + s.amount end
                for _, s in pairs(snap) do is[s.name] = (is[s.name] or 0) + s.amount end
                local g = {}
                for name, amt in pairs(is) do
                    if amt > (was[name] or 0) then g[name] = amt - (was[name] or 0) end
                end
                gains[src] = g
            end
        end
    end

    -- 2) apply the rules per player
    for _, src in ipairs(players) do
        local c, st = cur[src], state[src]
        if c and not st then
            state[src] = { snap = c.snap, stacks = c.stacks }
        elseif c and st then
            local sDown = serverSaysDown(src)
            local down = sDown or clientDown[src] == true
            if sDown then st.verified = true end

            if down and not st.down then
                dbg(('src %d went down'):format(src))
                st.down, st.reviveUntil = true, nil
            elseif not down and st.down then
                dbg(('src %d is back up - watching for a respawn wipe'):format(src))
                st.down = false
                st.reviveUntil = st.verified and (now + Config.WatchAfterReviveSec) or nil
                st.verified = st.verified and st.reviveUntil ~= nil
            end

            local allowed = allowUntil[src] and allowUntil[src] > now
            local restored = 0

            if not allowed and st.verified ~= false and (down or (st.reviveUntil and now <= st.reviveUntil)) then
                -- what did people around us pick up this tick? (= we were robbed)
                local taken = {}
                for other, g in pairs(gains) do
                    if other ~= src and near(src, other, Config.RobRange) then
                        for k, amt in pairs(g) do taken[k] = (taken[k] or 0) + amt end
                    end
                end

                if down then
                    -- dead/downed: you can't use items, so anything kept that vanished comes back
                    if st.verified or Config.TrustClientDeath then
                        restored = restoreMissing(src, st.snap, c.snap, taken, 'died')
                    end
                else
                    -- just revived/respawned: only undo a WIPE (most/all stacks gone at once),
                    -- so eating/using items normally is never reversed
                    local lost = st.stacks - c.stacks
                    if st.stacks > 0 and lost > 0 and (c.stacks == 0 or lost / st.stacks >= Config.WipeRatio) then
                        restored = restoreMissing(src, st.snap, c.snap, taken, 'respawn wipe')
                    end
                end
            end

            if restored > 0 then
                local snap, stacks = snapshot(src)
                if snap then st.snap, st.stacks = snap, stacks end
            else
                st.snap, st.stacks = c.snap, c.stacks
            end

            if not down and st.reviveUntil and now > st.reviveUntil then
                st.reviveUntil, st.verified = nil, nil
            end
        end
    end
end

CreateThread(function()
    Wait(2000)
    while true do
        if Config.Enabled then
            local ok, err = pcall(tick)
            if not ok then print('[nrp-keepitems] error: ' .. tostring(err)) end
        end
        Wait(Config.PollMs)
    end
end)

-- ------------------------------------------------------------
--  Death signals from the client and common ambulance scripts
-- ------------------------------------------------------------
RegisterNetEvent('nrp-keepitems:down', function(isDown)
    clientDown[source] = isDown == true or nil
end)

local function setEventDown(src, v)
    src = tonumber(src)
    if src then eventDown[src] = v and true or nil end
end
-- qb-ambulancejob
RegisterNetEvent('hospital:server:SetDeathStatus', function(v) setEventDown(source, v) end)
RegisterNetEvent('hospital:server:SetLaststandStatus', function(v) setEventDown(source, v) end)
-- respawning at the hospital = they were dead; make sure we're watching
RegisterNetEvent('hospital:server:RespawnAtHospital', function()
    local st = state[source]
    if st then st.verified = true; st.reviveUntil = os.time() + Config.WatchAfterReviveSec end
end)

AddEventHandler('playerDropped', function()
    state[source], allowUntil[source], clientDown[source], eventDown[source] = nil, nil, nil, nil
end)

-- ------------------------------------------------------------
--  Exports
-- ------------------------------------------------------------
-- let a script take everything (jail confiscation etc.)
exports('AllowRemoval', function(src, seconds)
    allowUntil[tonumber(src)] = os.time() + (tonumber(seconds) or 10)
end)
exports('KeepsOnDeath', function(name) return keeps(tostring(name)) end)
exports('IsWatching', function(src)
    local st = state[tonumber(src)]
    return st ~= nil and (st.down or st.reviveUntil ~= nil)
end)

-- ------------------------------------------------------------
--  /keepitems [id]   (console or admins) - shows what's happening
-- ------------------------------------------------------------
RegisterCommand('keepitems', function(source, args)
    if source ~= 0 and not QBCore.Functions.HasPermission(source, 'admin') and not QBCore.Functions.HasPermission(source, 'god') then return end
    local target = tonumber(args[1]) or (source ~= 0 and source) or nil
    local function out(msg)
        if source == 0 then print('[nrp-keepitems] ' .. msg)
        else TriggerClientEvent('chat:addMessage', source, { args = { 'keepitems', msg } }) end
    end
    if not target then return out('usage: keepitems <server id>') end
    local snap, stacks = snapshot(target)
    out(('reader: %s'):format(readMethod and readMethod.name or 'NONE FOUND - inventory cannot be read!'))
    if not snap then return out('could not read that player\'s inventory') end
    local kept, lost = {}, {}
    for _, s in pairs(snap) do
        local t = keeps(s.name) and kept or lost
        t[#t + 1] = ('%dx %s'):format(s.amount, s.name)
    end
    local st = state[target] or {}
    out(('player %d: %d stacks | down: %s | verified death: %s | watching after revive: %s'):format(
        target, stacks, tostring(st.down == true), tostring(st.verified == true),
        st.reviveUntil and (st.reviveUntil - os.time() .. 's') or 'no'))
    out('KEPT on death: ' .. (#kept > 0 and table.concat(kept, ', ') or '-'))
    out('LOST on death: ' .. (#lost > 0 and table.concat(lost, ', ') or '-'))
end, false)

print('[nrp-keepitems] v2 loaded - legal items are kept on death')
