-- ============================================================
--  nrp-keepitems - keep your essentials when you die
--
--  Your respawn script still clears the inventory on death. This
--  watches every dead or downed player server-side; when the
--  inventory is wiped in one go (what death wipes do), every LEGAL
--  item is given straight back; drugs, dirty money, guns, crime
--  tools and stolen loot (Config.LoseItems / LosePatterns) stay gone.
--  Items taken one at a time (someone robbing you) are left alone,
--  so nothing can be duped.
-- ============================================================

local QBCore = exports['qb-core']:GetCoreObject()

local watching = {}   -- [src] = { snap = {...}, stacks = n, until = os.time() or nil }
local allowUntil = {} -- [src] = os.time() until which removals are allowed (export)

local function dbg(...) if Config.Debug then print('[nrp-keepitems]', ...) end end

-- ------------------------------------------------------------
--  Inventory snapshots
-- ------------------------------------------------------------
local function itemsOf(src)
    local P = QBCore.Functions.GetPlayer(src)
    if not P then return nil end
    return P.PlayerData.items or {}
end

local function keyOf(item)
    local info = item.info or item.metadata
    if type(info) == 'table' and next(info) then
        return item.name .. '|' .. json.encode(info)
    end
    return item.name
end

-- { [key] = { name, amount, info, slot }, ... }, number of stacks
local function snapshot(src)
    local items = itemsOf(src)
    if not items then return nil, 0 end
    local snap, stacks = {}, 0
    for _, it in pairs(items) do
        if type(it) == 'table' and it.name and (tonumber(it.amount) or 0) > 0 then
            stacks = stacks + 1
            local k = keyOf(it)
            local s = snap[k]
            if s then
                s.amount = s.amount + it.amount
            else
                snap[k] = { name = it.name, amount = tonumber(it.amount), info = it.info or it.metadata, slot = it.slot }
            end
        end
    end
    return snap, stacks
end

local function giveBack(src, item, amount)
    local P = QBCore.Functions.GetPlayer(src)
    if not P then return false end
    if GetResourceState(Config.InventoryResource or '') == 'started' then
        local ok, res = pcall(function()
            return exports[Config.InventoryResource]:AddItem(src, item.name, amount, item.slot, item.info)
        end)
        if ok and res ~= false then return true end
        -- slot taken? try any free slot
        ok, res = pcall(function()
            return exports[Config.InventoryResource]:AddItem(src, item.name, amount, nil, item.info)
        end)
        if ok and res ~= false then return true end
    end
    return P.Functions.AddItem(item.name, amount, item.slot, item.info) or P.Functions.AddItem(item.name, amount, nil, item.info)
end

local function log(src, restored)
    local P = QBCore.Functions.GetPlayer(src)
    local who = P and ('%s %s (%s)'):format(P.PlayerData.charinfo.firstname, P.PlayerData.charinfo.lastname, P.PlayerData.citizenid) or ('id ' .. src)
    local parts = {}
    for _, r in ipairs(restored) do parts[#parts + 1] = ('%dx %s'):format(r.amount, r.name) end
    local line = ('Death wipe for %s - kept: %s'):format(who, table.concat(parts, ', '))
    print('[nrp-keepitems] ' .. line)
    if Config.Webhook and Config.Webhook ~= '' then
        PerformHttpRequest(Config.Webhook, function() end, 'POST',
            json.encode({ username = 'Keep Items', embeds = { { title = 'Items kept on death', description = line, color = 3066993 } } }),
            { ['Content-Type'] = 'application/json' })
    end
end

-- legal = kept on death; illegal (lose list / patterns) = gone
local function keeps(name)
    if Config.KeepEverything or Config.KeepAnyway[name] then return true end
    if Config.LoseItems[name] then return false end
    local lname = name:lower()
    for _, p in ipairs(Config.LosePatterns) do
        if lname:find(p) then return false end
    end
    return true
end

-- put back everything in `snap` that is missing now
local function restore(src, snap)
    local now = snapshot(src) or {}
    local restored = {}
    for k, s in pairs(snap) do
        if keeps(s.name) then
            local have = now[k] and now[k].amount or 0
            local missing = s.amount - have
            if missing > 0 and giveBack(src, s, missing) then
                restored[#restored + 1] = { name = s.name, amount = missing }
            end
        end
    end
    if #restored > 0 then
        log(src, restored)
        TriggerClientEvent('QBCore:Notify', src, 'You kept your belongings. Anything illegal is gone.', 'primary')
    end
end

-- ------------------------------------------------------------
--  Who is dead / downed (decided by the server, not the client)
-- ------------------------------------------------------------
local function isDown(src)
    local P = QBCore.Functions.GetPlayer(src)
    if not P then return false end
    local m = P.PlayerData.metadata or {}
    if m.isdead or m.inlaststand then return true end
    local ped = GetPlayerPed(src)
    return ped ~= 0 and GetEntityHealth(ped) <= 0
end

-- ------------------------------------------------------------
--  Watch loop
-- ------------------------------------------------------------
local function check(src, w)
    local snap, stacks = snapshot(src)
    if not snap then return end

    local lost = w.stacks - stacks
    local allowed = allowUntil[src] and allowUntil[src] > os.time()
    if not allowed and lost >= Config.MinStacks and w.stacks > 0 and (lost / w.stacks) >= Config.WipeRatio then
        dbg(('src %d: %d of %d stacks gone at once - restoring'):format(src, lost, w.stacks))
        restore(src, w.snap)
        snap, stacks = snapshot(src)   -- re-read after giving back
        if not snap then return end
    end
    -- anything else (robbed one item, picked something up) is accepted as the new normal
    w.snap, w.stacks = snap, stacks
end

CreateThread(function()
    while true do
        Wait(Config.PollMs)
        if Config.Enabled then
            -- start / stop watching
            for _, src in ipairs(QBCore.Functions.GetPlayers()) do
                local down = isDown(src)
                local w = watching[src]
                if down then
                    if not w then
                        local snap, stacks = snapshot(src)
                        if snap then
                            watching[src] = { snap = snap, stacks = stacks }
                            dbg(('src %d down - watching %d stacks'):format(src, stacks))
                        end
                    else
                        w.stopAt = nil   -- still down
                    end
                elseif w and not w.stopAt then
                    w.stopAt = os.time() + Config.WatchAfterReviveSec   -- revived / respawned
                end
            end
            -- check everyone being watched
            for src, w in pairs(watching) do
                if not GetPlayerName(src) then
                    watching[src] = nil
                else
                    check(src, w)
                    if w.stopAt and os.time() > w.stopAt then
                        watching[src] = nil
                        dbg(('src %d - done watching'):format(src))
                    end
                end
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    watching[source] = nil
    allowUntil[source] = nil
end)

-- ------------------------------------------------------------
--  Exports for scripts that SHOULD be able to take everything
--  e.g. a jail script that confiscates items:
--    exports['nrp-keepitems']:AllowRemoval(src, 10)
-- ------------------------------------------------------------
exports('AllowRemoval', function(src, seconds)
    allowUntil[tonumber(src)] = os.time() + (tonumber(seconds) or 10)
end)

exports('IsWatching', function(src) return watching[tonumber(src)] ~= nil end)
exports('KeepsOnDeath', function(name) return keeps(tostring(name)) end)

print('[nrp-keepitems] loaded - items are kept on death')
