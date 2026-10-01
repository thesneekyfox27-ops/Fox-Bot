--[[
    nrp-barriers - server
    Persists walls to walls.json inside this resource folder and keeps
    every connected client in sync.
]]

local RES   = GetCurrentResourceName()
local walls = {}

-- ============================================================================
--  STORAGE
-- ============================================================================

local function saveToDisk()
    local ok, encoded = pcall(json.encode, walls, { indent = true })
    if not ok then
        print('^1[nrp-barriers]^7 failed to encode walls')
        return false
    end

    local written = SaveResourceFile(RES, 'walls.json', encoded, -1)
    if not written then
        print('^1[nrp-barriers]^7 SaveResourceFile failed - check folder write permissions')
        return false
    end

    return true
end

local function loadFromDisk()
    local raw = LoadResourceFile(RES, 'walls.json')

    if raw and raw ~= '' then
        local ok, data = pcall(json.decode, raw)
        if ok and type(data) == 'table' then
            walls = data
            print(('^2[nrp-barriers]^7 loaded %d wall(s) from walls.json'):format(#walls))
            return
        end
        print('^1[nrp-barriers]^7 walls.json is corrupt - starting empty')
    end

    -- first run: seed from Config.Walls if the user put any there by hand
    if Config.Walls and #Config.Walls > 0 then
        for _, w in ipairs(Config.Walls) do
            local pts = {}
            for _, p in ipairs(w.points) do
                pts[#pts + 1] = { x = p.x + 0.0, y = p.y + 0.0, z = p.z + 0.0 }
            end
            walls[#walls + 1] = {
                name   = w.name or 'unnamed',
                height = w.height or Config.DefaultHeight,
                points = pts,
            }
        end
        saveToDisk()
        print(('^2[nrp-barriers]^7 migrated %d wall(s) from config.lua into walls.json')
            :format(#walls))
    else
        print('^2[nrp-barriers]^7 no saved walls yet')
    end
end

AddEventHandler('onResourceStart', function(res)
    if res ~= RES then return end
    loadFromDisk()
end)

-- ============================================================================
--  PERMISSION
-- ============================================================================

local function canEdit(src)
    if not Config.RequireAce then return true end

    -- 'command' is granted to group.admin in most QBCore setups, so admins
    -- pass without you having to add a second ace.
    return IsPlayerAceAllowed(src, 'nrp.barrier')
        or IsPlayerAceAllowed(src, 'command')
end

-- ============================================================================
--  VALIDATION
-- ============================================================================

local function validWall(w)
    if type(w) ~= 'table' then return false end
    if type(w.points) ~= 'table' then return false end
    if #w.points < 2 or #w.points > 64 then return false end

    local h = tonumber(w.height)
    if not h or h < 0.5 or h > 50.0 then return false end

    for _, p in ipairs(w.points) do
        if type(p) ~= 'table' then return false end
        if type(p.x) ~= 'number' or type(p.y) ~= 'number' or type(p.z) ~= 'number' then
            return false
        end
        -- reject NaN / inf, they would break the geometry for everyone
        if p.x ~= p.x or p.y ~= p.y or p.z ~= p.z
            or math.abs(p.x) > 1e5 or math.abs(p.y) > 1e5 or math.abs(p.z) > 1e5 then
            return false
        end
    end

    return true
end

-- ============================================================================
--  SYNC
-- ============================================================================

local function broadcast()
    TriggerClientEvent('nrp-barriers:sync', -1, walls)
end

RegisterNetEvent('nrp-barriers:request', function()
    TriggerClientEvent('nrp-barriers:sync', source, walls)
end)

RegisterNetEvent('nrp-barriers:add', function(wall)
    local src = source

    if not canEdit(src) then
        TriggerClientEvent('nrp-barriers:denied', src)
        return
    end

    if not validWall(wall) then
        print(('[nrp-barriers] rejected malformed wall from %s'):format(src))
        return
    end

    local pts = {}
    for _, p in ipairs(wall.points) do
        pts[#pts + 1] = { x = p.x + 0.0, y = p.y + 0.0, z = p.z + 0.0 }
    end

    walls[#walls + 1] = {
        name   = tostring(wall.name or ('wall %d'):format(#walls + 1)):sub(1, 40),
        height = tonumber(wall.height),
        points = pts,
    }

    if saveToDisk() then
        print(('[nrp-barriers] %s added "%s" (%d total)')
            :format(GetPlayerName(src), walls[#walls].name, #walls))
        TriggerClientEvent('nrp-barriers:saved', src, walls[#walls].name, #walls)
    else
        TriggerClientEvent('nrp-barriers:saveFailed', src)
    end

    broadcast()
end)

RegisterNetEvent('nrp-barriers:remove', function(index)
    local src = source

    if not canEdit(src) then
        TriggerClientEvent('nrp-barriers:denied', src)
        return
    end

    index = tonumber(index)
    if not index or not walls[index] then return end

    local removed = table.remove(walls, index)
    saveToDisk()

    print(('[nrp-barriers] %s removed "%s"'):format(GetPlayerName(src), removed.name))
    TriggerClientEvent('nrp-barriers:removed', src, removed.name)

    broadcast()
end)

RegisterNetEvent('nrp-barriers:rename', function(index, name)
    local src = source

    if not canEdit(src) then
        TriggerClientEvent('nrp-barriers:denied', src)
        return
    end

    index = tonumber(index)
    if not index or not walls[index] then return end
    if type(name) ~= 'string' then return end

    walls[index].name = name:sub(1, 40)
    saveToDisk()
    broadcast()
end)

RegisterNetEvent('nrp-barriers:wipe', function()
    local src = source

    if not canEdit(src) then
        TriggerClientEvent('nrp-barriers:denied', src)
        return
    end

    walls = {}
    saveToDisk()
    print(('[nrp-barriers] %s wiped all walls'):format(GetPlayerName(src)))
    broadcast()
end)

-- ============================================================================
--  UI / TELEPORT
-- ============================================================================

RegisterNetEvent('nrp-barriers:openUi', function()
    local src = source

    if not canEdit(src) then
        TriggerClientEvent('nrp-barriers:denied', src)
        return
    end

    TriggerClientEvent('nrp-barriers:sync', src, walls)
    TriggerClientEvent('nrp-barriers:uiAllowed', src)
end)

RegisterNetEvent('nrp-barriers:tp', function(index)
    local src = source

    if not canEdit(src) then
        TriggerClientEvent('nrp-barriers:denied', src)
        return
    end

    index = tonumber(index)
    if not index or not walls[index] then return end

    TriggerClientEvent('nrp-barriers:tpAllowed', src, index)
end)
