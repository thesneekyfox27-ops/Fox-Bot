local QBCore = exports['qb-core']:GetCoreObject()

local Elevators   = {}      -- synced merged list from server
local zoneIds     = {}      -- ox_target zone ids for cleanup
local panelOpen   = false
local traveling   = false
local currentElev = nil     -- { elevIndex, floorIndex }
local pushAdminData         -- forward declare (assigned in admin section)

-- ============================================================
--  HELPERS
-- ============================================================
local function debugPrint(...)
    if Config.Debug then print('[nrp-elevators]', ...) end
end

local function hasJobAccess(jobs)
    if not jobs or #jobs == 0 then return true end
    local pd = QBCore.Functions.GetPlayerData()
    local myJob = pd and pd.job and pd.job.name or nil
    if not myJob then return false end
    for _, j in ipairs(jobs) do
        if j == myJob then return true end
    end
    return false
end

local function playSound(entry, volumeScale, id)
    if not Config.Transition.sounds then return end
    if not entry then return end
    if entry.file then
        SendNUIMessage({
            action = 'playSound',
            file   = entry.file,
            volume = (entry.volume or 1.0) * (volumeScale or 1.0),
            loop   = entry.loop or false,
            id     = id,
        })
    elseif entry.native then
        PlaySoundFrontend(-1, entry.native.name, entry.native.set, true)
    end
end

local function stopSound(id)
    SendNUIMessage({ action = 'stopSound', id = id })
end

local function panelColor()
    if Config.Panel.theme == 'custom' then return Config.Panel.customColor end
    return Config.PanelThemes[Config.Panel.theme] or Config.PanelThemes.teal
end

local function elevMode(elev)
    return elev.interaction or Config.Interaction
end

local function playCallAnim()
    local a = Config.CallAnimation
    if not a or not a.enabled then return end
    local ped = PlayerPedId()
    if lib.requestAnimDict(a.dict, 2000) then
        TaskPlayAnim(ped, a.dict, a.anim, 8.0, -8.0, a.durationMs, 48, 0, false, false, false)
        Wait(a.durationMs)
        RemoveAnimDict(a.dict)
    end
end

-- ============================================================
--  PLAYER PANEL (NUI)
-- ============================================================
local function openPanel(elevIndex, floorIndex)
    if panelOpen or traveling then return end
    local elev = Elevators[elevIndex]
    if not elev then return end

    if not hasJobAccess(elev.jobs) then
        lib.notify({ title = 'Elevator', description = 'You don\'t have access to this elevator.', type = 'error' })
        return
    end

    playCallAnim() -- reach out and press the call button

    local floors = {}
    for i, floor in ipairs(elev.floors) do
        floors[#floors + 1] = {
            index   = i,
            label   = floor.label or ('Floor ' .. i),
            current = (i == floorIndex),
            locked  = not hasJobAccess(floor.jobs),
        }
    end

    currentElev = { elevIndex = elevIndex, floorIndex = floorIndex }
    panelOpen = true

    SetNuiFocus(true, true)
    SendNUIMessage({
        action        = 'open',
        name          = elev.name,
        floors        = floors,
        color         = elev.color or panelColor(),
        position      = Config.Panel.position,
        showHereTag   = Config.Panel.showHereTag,
        topFloorFirst = Config.Panel.topFloorFirst,
        logo          = Config.Panel.logo,
    })
end

local function closePanel()
    if not panelOpen then return end
    panelOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

RegisterNUICallback('close', function(_, cb)
    closePanel()
    currentElev = nil
    cb('ok')
end)

RegisterNUICallback('selectFloor', function(data, cb)
    cb('ok')
    if not currentElev or traveling then return end
    local target = tonumber(data.index)
    if not target then return end
    if target == currentElev.floorIndex then
        closePanel()
        currentElev = nil
        return
    end

    playSound(Config.Sounds.buttonPress)
    local elevIndex = currentElev.elevIndex
    local fromFloor = currentElev.floorIndex
    closePanel()

    lib.callback('nrp-elevators:requestTravel', false, function(ok, dest, reason)
        if not ok then
            lib.notify({ title = 'Elevator', description = reason or 'Unable to travel.', type = 'error' })
            currentElev = nil
            return
        end
        doTravel(elevIndex, fromFloor, target, dest)
    end, elevIndex, fromFloor, target)
end)

-- ============================================================
--  SAFE TELEPORT  (MLO interior fix)
--  Pre-streams the destination, pins + waits for the interior,
--  then refreshes it so portals/occlusion render correctly when
--  jumping between inside floors and the exterior ground floor.
-- ============================================================
local function safeTeleport(x, y, z, w)
    local ped = PlayerPedId()

    -- remember the interior we're LEAVING (e.g. the motel MLO)
    local fromPos = GetEntityCoords(ped)
    local fromInterior = GetInteriorAtCoords(fromPos.x, fromPos.y, fromPos.z)

    -- start streaming the destination while the screen is black
    RequestCollisionAtCoord(x, y, z)
    SetFocusPosAndVel(x, y, z, 0.0, 0.0, 0.0)

    local interior = GetInteriorAtCoords(x, y, z)
    if interior ~= 0 then
        PinInteriorInMemory(interior)
        local t = GetGameTimer() + 3000
        while not IsInteriorReady(interior) and GetGameTimer() < t do Wait(25) end
    end

    SetEntityCoords(ped, x, y, z, false, false, false, false)
    SetEntityHeading(ped, w or 0.0)

    local t = GetGameTimer() + 5000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < t do Wait(50) end

    -- force the engine to re-evaluate which room/interior the player is in
    SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)

    if interior ~= 0 then
        RefreshInterior(interior) -- rebuild portals/occlusion (fixes see-through MLO walls)
    else
        -- arriving OUTSIDE: fully detach player + camera from the interior
        -- we just left, otherwise the viewport can stay "inside" the MLO
        -- and the exterior world renders as grey void
        ClearRoomForEntity(ped)
        ClearRoomForGameViewport()
        if fromInterior ~= 0 then
            RefreshInterior(fromInterior)
            UnpinInterior(fromInterior)
        end
    end

    ClearFocus()
    return interior
end

-- ============================================================
--  TRAVEL
-- ============================================================
function doTravel(elevIndex, fromFloor, toFloor, dest)
    if traveling then return end
    traveling = true

    local ped = PlayerPedId()
    local t = Config.Transition
    local elev = Elevators[elevIndex]

    if t.freezePlayer then FreezeEntityPosition(ped, true) end

    DoScreenFadeOut(t.fadeOutMs)
    while not IsScreenFadedOut() do Wait(10) end

    local interior = safeTeleport(dest.x, dest.y, dest.z, dest.w)

    -- travel HUD (NUI stays visible over the screen fade)
    local labels = {}
    if elev then
        for i, f in ipairs(elev.floors) do labels[i] = f.label or ('Floor ' .. i) end
    end
    SendNUIMessage({
        action = 'travelStart',
        name   = elev and elev.name or 'Elevator',
        from   = fromFloor,
        to     = toFloor,
        labels = labels,
        color  = (elev and elev.color) or panelColor(),
    })

    Wait(t.holdMs) -- doors closing

    playSound(Config.Sounds.moving, 1.0, 'moving') -- elevator hum (loops)

    -- step floor-by-floor, HUD counts along with each tick
    local dir  = (toFloor > fromFloor) and 1 or -1
    local step = fromFloor
    while step ~= toFloor do
        step = step + dir
        SendNUIMessage({ action = 'travelStep', floor = step })
        playSound(Config.Sounds.floorPass)
        Wait(t.msPerFloor)
    end

    stopSound('moving')
    SendNUIMessage({ action = 'travelEnd' })

    -- arrival ding: broadcast to everyone nearby, or just us
    local ding = Config.Sounds.arrival
    if ding and ding.broadcast then
        TriggerServerEvent('nrp-elevators:arrivalDing', { x = dest.x, y = dest.y, z = dest.z })
    else
        playSound(ding)
    end

    DoScreenFadeIn(t.fadeInMs)

    if t.freezePlayer then FreezeEntityPosition(ped, false) end

    -- one more refresh after everything settles, then release the pin
    if interior and interior ~= 0 then
        Wait(t.fadeInMs)
        RefreshInterior(interior)
        UnpinInterior(interior)
    end

    traveling = false
    currentElev = nil
end

-- ============================================================
--  ZONES  (rebuilt every time the server syncs)
-- ============================================================
local function clearZones()
    for _, id in ipairs(zoneIds) do
        exports.ox_target:removeZone(id)
    end
    zoneIds = {}
end

local function buildZones()
    clearZones()
    for ei, elev in ipairs(Elevators) do
        if elevMode(elev) ~= 'target' then goto continue end
        for fi, floor in ipairs(elev.floors) do
            local c = floor.coords
            local id = exports.ox_target:addSphereZone({
                coords = vec3(c.x, c.y, c.z),
                radius = Config.InteractDistance,
                debug  = Config.Debug,
                options = {
                    {
                        name     = ('nrp_elev_%s_%s'):format(ei, fi),
                        icon     = Config.TargetIcon,
                        label    = ('%s Elevator'):format(elev.name),
                        onSelect = function()
                            openPanel(ei, fi)
                        end,
                    },
                },
            })
            zoneIds[#zoneIds + 1] = id
        end
        ::continue::
    end
    debugPrint(('built zones for %s elevators'):format(#Elevators))
end

RegisterNetEvent('nrp-elevators:sync', function(list)
    Elevators = list or {}
    buildZones()
    if pushAdminData then pushAdminData() end
end)

CreateThread(function()
    local list = lib.callback.await('nrp-elevators:getElevators', false)
    Elevators = list or {}
    buildZones()
end)

-- ============================================================
--  MARKER + TEXTUI MODES  (per-elevator, live-updating)
-- ============================================================
CreateThread(function()
    local shown = false
    while true do
        local sleep = 500
        local pos = GetEntityCoords(PlayerPedId())
        local near = nil
        local m = Config.Marker

        for ei, elev in ipairs(Elevators) do
            local mode = elevMode(elev)
            if mode == 'marker' or mode == 'textui' then
                for fi, floor in ipairs(elev.floors) do
                    local c = floor.coords
                    local dist = #(pos - vec3(c.x, c.y, c.z))

                    if mode == 'marker' and dist < m.drawDistance then
                        sleep = 0
                        DrawMarker(m.type,
                            c.x, c.y, c.z + m.zOffset,
                            0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                            m.size.x, m.size.y, m.size.z,
                            m.color.r, m.color.g, m.color.b, m.color.a,
                            m.bobUpAndDown, false, 2, m.rotate, nil, nil, false)
                    end

                    if dist < Config.InteractDistance and not near then
                        near = { ei = ei, fi = fi, name = elev.name }
                    end
                end
            end
        end

        if near and not traveling and not panelOpen then
            sleep = 0
            if not shown then
                lib.showTextUI(('[E] %s Elevator'):format(near.name), { icon = 'elevator' })
                shown = true
            end
            if IsControlJustReleased(0, 38) then
                lib.hideTextUI()
                shown = false
                openPanel(near.ei, near.fi)
            end
        elseif shown then
            lib.hideTextUI()
            shown = false
        end

        Wait(sleep)
    end
end)

-- ============================================================
--  ADMIN PANEL  (custom NUI, matches the elevator panel design)
-- ============================================================
local adminOpen = false

local function dynIndexOf(mergedIndex)
    local elev = Elevators[mergedIndex]
    if not elev or elev.source ~= 'json' then return nil end
    local count = 0
    for i = 1, mergedIndex do
        if Elevators[i].source == 'json' then count = count + 1 end
    end
    return count
end

local function myVec4()
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local h = GetEntityHeading(ped)
    return { x = c.x, y = c.y, z = c.z, w = h }
end

local function stringToJobs(str)
    local jobs = {}
    if not str then return jobs end
    for job in string.gmatch(str, '([^,]+)') do
        job = job:gsub('^%%s+', ''):gsub('%%s+$', '')
        if job ~= '' then jobs[#jobs + 1] = job end
    end
    return jobs
end

local function adminPayload()
    local list = {}
    for i, e in ipairs(Elevators) do
        list[#list + 1] = {
            mergedIndex = i,
            dynIndex    = dynIndexOf(i),
            name        = e.name,
            jobs        = e.jobs,
            color       = e.color,
            interaction = e.interaction,
            floors      = e.floors,
            source      = e.source,
        }
    end
    return list
end

pushAdminData = function()
    if not adminOpen then return end
    SendNUIMessage({ action = 'adminData', elevators = adminPayload() })
end

local function openAdminPanel()
    if adminOpen or traveling or panelOpen then return end
    adminOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action             = 'adminOpen',
        elevators          = adminPayload(),
        interactionDefault = Config.Interaction,
        color              = panelColor(),
        logo               = Config.Panel.logo,
    })
end

RegisterNUICallback('adminClose', function(_, cb)
    adminOpen = false
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('adminAction', function(data, cb)
    local act = data.action
    local di  = tonumber(data.dynIndex)
    local fi  = tonumber(data.floorIndex)
    local ok, err = true, nil

    if act == 'create' then
        ok, err = lib.callback.await('nrp-elevators:createElevator', false, data.name)
    elseif act == 'rename' then
        ok, err = lib.callback.await('nrp-elevators:renameElevator', false, di, data.name)
    elseif act == 'jobs' then
        ok, err = lib.callback.await('nrp-elevators:setElevatorJobs', false, di, stringToJobs(data.jobs))
    elseif act == 'interaction' then
        ok, err = lib.callback.await('nrp-elevators:setInteraction', false, di, data.mode)
    elseif act == 'color' then
        ok, err = lib.callback.await('nrp-elevators:setColor', false, di, data.color)
    elseif act == 'delete' then
        ok, err = lib.callback.await('nrp-elevators:deleteElevator', false, di)
    elseif act == 'addFloorHere' then
        ok, err = lib.callback.await('nrp-elevators:addFloor', false, di, data.label, myVec4())
    elseif act == 'floorMoveHere' then
        ok, err = lib.callback.await('nrp-elevators:updateFloor', false, di, fi, { coords = myVec4() })
    elseif act == 'floorRename' then
        ok, err = lib.callback.await('nrp-elevators:updateFloor', false, di, fi, { label = data.label })
    elseif act == 'floorCoords' then
        ok, err = lib.callback.await('nrp-elevators:updateFloor', false, di, fi, {
            coords = { x = tonumber(data.x), y = tonumber(data.y), z = tonumber(data.z), w = tonumber(data.w) },
        })
    elseif act == 'floorJobs' then
        ok, err = lib.callback.await('nrp-elevators:updateFloor', false, di, fi, { jobs = stringToJobs(data.jobs) })
    elseif act == 'floorReorder' then
        ok, err = lib.callback.await('nrp-elevators:moveFloor', false, di, fi, tonumber(data.dir))
    elseif act == 'floorDelete' then
        ok, err = lib.callback.await('nrp-elevators:deleteFloor', false, di, fi)
    elseif act == 'floorTeleport' then
        local c = data.coords
        if c then
            safeTeleport(c.x + 0.0, c.y + 0.0, c.z + 0.0, (c.w or 0.0) + 0.0)
        end
    end

    cb({ ok = ok ~= false, err = err })
end)

RegisterNetEvent('nrp-elevators:openAdminMenu', function()
    openAdminPanel()
end)

-- keybind entry point (checked serverside before opening)
if Config.Admin.keybind and Config.Admin.keybind ~= '' then
    lib.addKeybind({
        name = 'nrp_elevators_admin',
        description = 'Open Elevator Manager (admin)',
        defaultKey = Config.Admin.keybind,
        onPressed = function()
            if panelOpen or traveling or adminOpen then return end
            local ok = lib.callback.await('nrp-elevators:isAdmin', false)
            if ok then openAdminPanel() end
        end,
    })
end

-- ============================================================
--  BROADCAST DING (hear elevators arriving near you)
-- ============================================================
RegisterNetEvent('nrp-elevators:playDing', function(dist, radius)
    local falloff = 1.0 - math.min(1.0, (dist or 0) / (radius or 20.0)) * 0.8
    playSound(Config.Sounds.arrival, falloff)
end)

-- ============================================================
--  CLEANUP
-- ============================================================
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if panelOpen or adminOpen then SetNuiFocus(false, false) end
    stopSound('moving')
    ClearFocus()
    clearZones()
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    if not IsScreenFadedIn() then DoScreenFadeIn(0) end
end)
