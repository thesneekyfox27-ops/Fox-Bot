local QBCore = exports['qb-core']:GetCoreObject()

-- ============================================================
--  STORAGE  (elevators.json — created in-game, no SQL, no config edits)
-- ============================================================
local DATA_FILE = 'elevators.json'
local dynamicElevators = {}

local function loadElevators()
    local raw = LoadResourceFile(GetCurrentResourceName(), DATA_FILE)
    if raw and raw ~= '' then
        local ok, data = pcall(json.decode, raw)
        if ok and type(data) == 'table' then
            dynamicElevators = data
            return
        end
    end
    dynamicElevators = {}
end

local function saveElevators()
    SaveResourceFile(GetCurrentResourceName(), DATA_FILE, json.encode(dynamicElevators), -1)
end

-- Merge static config elevators + in-game created ones into one list.
-- Static ones get source='config' (not editable in-game), dynamic get source='json'.
local function buildList()
    local list = {}
    for _, e in ipairs(Config.Elevators) do
        local floors = {}
        for _, f in ipairs(e.floors) do
            floors[#floors + 1] = {
                label  = f.label,
                button = f.button,
                jobs   = f.jobs,
                coords = { x = f.coords.x, y = f.coords.y, z = f.coords.z, w = f.coords.w },
            }
        end
        list[#list + 1] = {
            name = e.name, jobs = e.jobs, floors = floors, source = 'config',
            numberFrom = e.numberFrom, color = e.color, interaction = e.interaction,
        }
    end
    for _, e in ipairs(dynamicElevators) do
        e.source = 'json'
        list[#list + 1] = e
    end
    return list
end

local function syncAll()
    TriggerClientEvent('nrp-elevators:sync', -1, buildList())
end

loadElevators()

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    Wait(500)
    syncAll()
end)

lib.callback.register('nrp-elevators:getElevators', function()
    return buildList()
end)

-- ============================================================
--  HELPERS
-- ============================================================
local function isAdmin(src)
    -- Discord ID allowlist (primary)
    local discord = GetPlayerIdentifierByType(src, 'discord')
    if discord then
        local myId = discord:gsub('discord:', '')
        for _, allowed in ipairs(Config.Admin.discordIds or {}) do
            local a = tostring(allowed):gsub('discord:', '')
            if a ~= '' and a == myId then return true end
        end
    end
    -- optional QBCore group fallback
    for _, grp in ipairs(Config.Admin.groups or {}) do
        if QBCore.Functions.HasPermission(src, grp) then return true end
    end
    return false
end

local function playerHasJob(src, jobs)
    if not jobs or #jobs == 0 then return true end
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return false end
    local myJob = Player.PlayerData.job and Player.PlayerData.job.name or nil
    if not myJob then return false end
    for _, j in ipairs(jobs) do
        if j == myJob then return true end
    end
    return false
end

-- combined merged-list accessor for travel validation
local function getMerged(elevIndex)
    return buildList()[elevIndex]
end

-- ============================================================
--  TRAVEL VALIDATION
-- ============================================================
lib.callback.register('nrp-elevators:requestTravel', function(source, elevIndex, fromFloor, toFloor)
    local elev = getMerged(elevIndex)
    if not elev then return false, nil, 'Invalid elevator.' end

    local fromF = elev.floors[fromFloor]
    local toF   = elev.floors[toFloor]
    if not fromF or not toF then return false, nil, 'Invalid floor.' end

    if not playerHasJob(source, elev.jobs) then
        return false, nil, 'You don\'t have access to this elevator.'
    end
    if not playerHasJob(source, toF.jobs) then
        return false, nil, 'You don\'t have access to that floor.'
    end

    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return false, nil, 'Player not found.' end
    local pos = GetEntityCoords(ped)
    local fc  = fromF.coords
    if #(pos - vector3(fc.x, fc.y, fc.z)) > 10.0 then
        return false, nil, 'Too far from the elevator.'
    end

    local tc = toF.coords
    return true, { x = tc.x, y = tc.y, z = tc.z, w = tc.w }
end)

-- ============================================================
--  ADMIN: menu access check
-- ============================================================
lib.callback.register('nrp-elevators:isAdmin', function(source)
    return isAdmin(source)
end)

-- ============================================================
--  ADMIN: CRUD (everything in-game, saved to elevators.json)
--  Dynamic indexes are positions within dynamicElevators.
-- ============================================================
lib.callback.register('nrp-elevators:createElevator', function(source, name)
    if not isAdmin(source) then return false, 'No permission.' end
    if type(name) ~= 'string' or name == '' then return false, 'Invalid name.' end
    dynamicElevators[#dynamicElevators + 1] = { name = name, floors = {} }
    saveElevators()
    syncAll()
    return true
end)

lib.callback.register('nrp-elevators:renameElevator', function(source, dynIndex, name)
    if not isAdmin(source) then return false, 'No permission.' end
    local e = dynamicElevators[dynIndex]
    if not e then return false, 'Not found.' end
    if type(name) ~= 'string' or name == '' then return false, 'Invalid name.' end
    e.name = name
    saveElevators()
    syncAll()
    return true
end)

lib.callback.register('nrp-elevators:setElevatorJobs', function(source, dynIndex, jobs)
    if not isAdmin(source) then return false, 'No permission.' end
    local e = dynamicElevators[dynIndex]
    if not e then return false, 'Not found.' end
    e.jobs = (jobs and #jobs > 0) and jobs or nil
    saveElevators()
    syncAll()
    return true
end)

lib.callback.register('nrp-elevators:setInteraction', function(source, dynIndex, mode)
    if not isAdmin(source) then return false, 'No permission.' end
    local e = dynamicElevators[dynIndex]
    if not e then return false, 'Not found.' end
    local valid = { target = true, marker = true, textui = true }
    e.interaction = valid[mode] and mode or nil -- 'default' / anything else clears the override
    saveElevators()
    syncAll()
    return true
end)

lib.callback.register('nrp-elevators:setNumbering', function(source, dynIndex, value)
    if not isAdmin(source) then return false, 'No permission.' end
    local e = dynamicElevators[dynIndex]
    if not e then return false, 'Not found.' end
    local v = tonumber(value)
    e.numberFrom = (v == 0 or v == 1) and v or nil   -- nil = use Config.Panel.firstFloorNumber
    saveElevators()
    syncAll()
    return true
end)

lib.callback.register('nrp-elevators:setColor', function(source, dynIndex, color)
    if not isAdmin(source) then return false, 'No permission.' end
    local e = dynamicElevators[dynIndex]
    if not e then return false, 'Not found.' end
    if type(color) == 'string' and color:match('^#%x%x%x%x%x%x$') then
        e.color = color
    else
        e.color = nil -- reset to the global config theme
    end
    saveElevators()
    syncAll()
    return true
end)

lib.callback.register('nrp-elevators:deleteElevator', function(source, dynIndex)
    if not isAdmin(source) then return false, 'No permission.' end
    if not dynamicElevators[dynIndex] then return false, 'Not found.' end
    table.remove(dynamicElevators, dynIndex)
    saveElevators()
    syncAll()
    return true
end)

lib.callback.register('nrp-elevators:addFloor', function(source, dynIndex, label, coords)
    if not isAdmin(source) then return false, 'No permission.' end
    local e = dynamicElevators[dynIndex]
    if not e then return false, 'Not found.' end
    if type(coords) ~= 'table' then return false, 'Bad coords.' end
    e.floors[#e.floors + 1] = {
        label  = (type(label) == 'string' and label ~= '') and label or ('Floor ' .. (#e.floors + 1)),
        coords = { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0, w = coords.w + 0.0 },
    }
    saveElevators()
    syncAll()
    return true
end)

lib.callback.register('nrp-elevators:updateFloor', function(source, dynIndex, floorIndex, patch)
    if not isAdmin(source) then return false, 'No permission.' end
    local e = dynamicElevators[dynIndex]
    if not e then return false, 'Not found.' end
    local f = e.floors[floorIndex]
    if not f then return false, 'Floor not found.' end
    if patch.label and patch.label ~= '' then f.label = patch.label end
    if patch.coords then
        f.coords = { x = patch.coords.x + 0.0, y = patch.coords.y + 0.0, z = patch.coords.z + 0.0, w = patch.coords.w + 0.0 }
    end
    if patch.jobs ~= nil then
        f.jobs = (#patch.jobs > 0) and patch.jobs or nil
    end
    if patch.button ~= nil then
        local b = tostring(patch.button):gsub('^%s+', ''):gsub('%s+$', ''):upper():sub(1, 3)
        f.button = (b ~= '') and b or nil
    end
    saveElevators()
    syncAll()
    return true
end)

lib.callback.register('nrp-elevators:moveFloor', function(source, dynIndex, floorIndex, dir)
    if not isAdmin(source) then return false, 'No permission.' end
    local e = dynamicElevators[dynIndex]
    if not e then return false, 'Not found.' end
    local target = floorIndex + dir
    if not e.floors[floorIndex] or not e.floors[target] then return false, 'Cannot move.' end
    e.floors[floorIndex], e.floors[target] = e.floors[target], e.floors[floorIndex]
    saveElevators()
    syncAll()
    return true
end)

lib.callback.register('nrp-elevators:deleteFloor', function(source, dynIndex, floorIndex)
    if not isAdmin(source) then return false, 'No permission.' end
    local e = dynamicElevators[dynIndex]
    if not e then return false, 'Not found.' end
    if not e.floors[floorIndex] then return false, 'Floor not found.' end
    table.remove(e.floors, floorIndex)
    saveElevators()
    syncAll()
    return true
end)

-- ============================================================
--  ARRIVAL DING BROADCAST
--  Everyone within radius of the destination hears the ding,
--  volume scaled by distance on each client.
-- ============================================================
RegisterNetEvent('nrp-elevators:arrivalDing', function(coords)
    local src = source
    if type(coords) ~= 'table' then return end
    local c = vector3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)

    -- sanity: sender must actually be near where they claim the elevator arrived
    local srcPed = GetPlayerPed(src)
    if not srcPed or srcPed == 0 then return end
    if #(GetEntityCoords(srcPed) - c) > 15.0 then return end

    local radius = (Config.Sounds.arrival and Config.Sounds.arrival.radius) or 20.0
    for _, pid in ipairs(GetPlayers()) do
        local ped = GetPlayerPed(pid)
        if ped and ped ~= 0 then
            local dist = #(GetEntityCoords(ped) - c)
            if dist <= radius then
                TriggerClientEvent('nrp-elevators:playDing', pid, dist, radius)
            end
        end
    end
end)

-- ============================================================
--  ALARM BELL  (panel bell button, heard by everyone nearby)
-- ============================================================
local lastAlarm = {}
RegisterNetEvent('nrp-elevators:alarm', function(coords)
    local src = source
    if type(coords) ~= 'table' then return end
    if lastAlarm[src] and os.time() - lastAlarm[src] < 4 then return end
    lastAlarm[src] = os.time()

    local srcPed = GetPlayerPed(src)
    if not srcPed or srcPed == 0 then return end
    local c = GetEntityCoords(srcPed)   -- use where they really are

    -- must actually be standing at an elevator
    local nearElevator = false
    for _, e in ipairs(buildList()) do
        for _, f in ipairs(e.floors or {}) do
            if #(c - vector3(f.coords.x, f.coords.y, f.coords.z)) < 6.0 then nearElevator = true break end
        end
        if nearElevator then break end
    end
    if not nearElevator then return end

    local radius = (Config.Sounds.alarm and Config.Sounds.alarm.radius) or 15.0
    for _, pid in ipairs(GetPlayers()) do
        local ped = GetPlayerPed(pid)
        if ped and ped ~= 0 then
            local dist = #(GetEntityCoords(ped) - c)
            if dist <= radius then TriggerClientEvent('nrp-elevators:playBell', pid, dist, radius) end
        end
    end
end)

AddEventHandler('playerDropped', function() lastAlarm[source] = nil end)

-- ============================================================
--  Single fallback command (admins can also just use the keybind)
-- ============================================================
RegisterCommand(Config.Admin.command, function(source)
    if source == 0 then return end
    if not isAdmin(source) then
        TriggerClientEvent('QBCore:Notify', source, 'No permission.', 'error')
        return
    end
    TriggerClientEvent('nrp-elevators:openAdminMenu', source)
end, false)
