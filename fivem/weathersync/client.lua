-- ============================================================
--  WeatherSync :: client
--  Applies the server's weather/time, runs the flood water,
--  ground lightning, the NUI panel, HUDs and sounds.
-- ============================================================

local current = {
    weatherId = Config.StartWeatherId,
    value     = 'EXTRASUNNY',
    blackout  = Config.StartBlackout,
    freeze    = not Config.DynamicTime,
    dynamic   = Config.DynamicWeather,
    addon     = nil,
    alert     = false,
    lightning = (Config.Lightning and Config.Lightning.enabled) and true or false,
    purge     = (Config.Purge.schedule and Config.Purge.schedule.enabled) and true or false,
}
local clock    = { hour = Config.StartTime.hour, minute = Config.StartTime.minute, second = 0 }
local isAdmin  = not Config.RestrictToAdmins
local menuOpen = false

-- The purge broadcast is held until the player is actually in the world, so it
-- never shows over the loading screen.
local spawnedIn        = false
local pendingBroadcast = nil

local function nui(msg) SendNUIMessage(msg) end
local function nuiIfOpen(msg) if menuOpen then nui(msg) end end

-- ------------------------------------------------------------
--  Wind & waves
-- ------------------------------------------------------------
local defaultOcean = nil

local function applyWind(speed)
    speed = speed or 0.0
    SetWind(speed)
    SetWindSpeed(speed)
    SetWindDirection(math.random() * 6.2831)
end

local function applyWaves(target)
    if defaultOcean == nil then defaultOcean = GetDeepOceanScaler() or 0.0 end
    SetDeepOceanScaler((target and target > 0) and (target + 0.0) or defaultOcean)
end

-- ------------------------------------------------------------
--  Add-on effects (client side: events / particles).
--  Server-side add-ons such as gd_tornado are fired by the server.
-- ------------------------------------------------------------
local addonHandles = {}

local function addonResourceOk(cfg)
    return not (cfg.resource and cfg.resource ~= '' and GetResourceState(cfg.resource) ~= 'started')
end

local function stopAddon(key)
    local cfg = Config.AddonEffects[key]
    if not cfg then return end
    if cfg.clientStopEvent and cfg.clientStopEvent ~= '' then TriggerEvent(cfg.clientStopEvent) end
    local h = addonHandles[key]
    if type(h) == 'number' then
        StopParticleFxLooped(h, false)
        if cfg.ptfxAsset ~= '' then RemoveNamedPtfxAsset(cfg.ptfxAsset) end
    end
    addonHandles[key] = nil
end

local function startAddon(key)
    local cfg = Config.AddonEffects[key]
    if not cfg or not cfg.enabled or addonHandles[key] or not addonResourceOk(cfg) then return end

    if cfg.clientEvent and cfg.clientEvent ~= '' then
        TriggerEvent(cfg.clientEvent)
        addonHandles[key] = true
        return
    end

    if cfg.ptfxAsset ~= '' and cfg.ptfxName ~= '' then
        RequestNamedPtfxAsset(cfg.ptfxAsset)
        local deadline = GetGameTimer() + 1000
        while not HasNamedPtfxAssetLoaded(cfg.ptfxAsset) and GetGameTimer() < deadline do Wait(5) end
        if not HasNamedPtfxAssetLoaded(cfg.ptfxAsset) then return end
        local p = GetEntityCoords(PlayerPedId())
        local ang = math.random() * 6.2831
        local tx = p.x + math.cos(ang) * (cfg.distance or 60.0)
        local ty = p.y + math.sin(ang) * (cfg.distance or 60.0)
        local found, gz = GetGroundZFor_3dCoord(tx, ty, p.z + 80.0, false)
        UseParticleFxAssetNextCall(cfg.ptfxAsset)
        addonHandles[key] = StartParticleFxLoopedAtCoord(cfg.ptfxName, tx, ty, found and gz or p.z,
            0.0, 0.0, 0.0, cfg.ptfxScale or 6.0, false, false, false, false)
    end
end

-- ------------------------------------------------------------
--  Flooding: real rising water (FiveM water quad natives).
--  The water is real GTA water, so the game itself makes you swim,
--  dive, float and drown, and cars float/sink - no fake animations
--  (forcing swim anims on a walking ped is what caused the T-pose).
-- ------------------------------------------------------------
local FL = Config.Flood
local floodActive      = false
local floodRiseSeconds = nil   -- set by the server: fill over this many seconds (paced to the restart)

RegisterNetEvent('weathersync:client:floodPace', function(seconds)
    seconds = tonumber(seconds) or 0
    floodRiseSeconds = (seconds > 0) and seconds or nil
end)

local function shiftAllWater(delta)
    for i = 0, (GetWaterQuadCount() or 0) - 1 do
        local ok, lvl = GetWaterQuadLevel(i)
        if ok == 1 or ok == true then SetWaterQuadLevel(i, lvl + delta) end
    end
end

-- Raise the water from flood.xml's map-wide plane (or the existing water)
local function riseWater()
    local target, rate = FL.targetRise, FL.rate
    if floodRiseSeconds then
        rate = target / math.max(1, (floodRiseSeconds * 1000) / FL.interval)
    end

    if FL.useBigQuad then
        local ok = LoadWaterFromPath(GetCurrentResourceName(), 'flood.xml')
        if ok ~= 1 and ok ~= true then
            print('[WeatherSync] flood: LoadWaterFromPath returned ' .. tostring(ok) ..
                  ' (flood.xml must be in files{} + data_file WATER_FILE). Using the existing water instead.')
        end
        Wait(150)   -- let the new water plane settle before raising it
    end

    local raised = 0.0
    while floodActive and raised < target do
        shiftAllWater(rate)
        raised = raised + rate
        Wait(FL.interval)
    end
end

-- No ambient cars/peds driving through the flood
local function suppressTraffic()
    while floodActive do
        SetVehicleDensityMultiplierThisFrame(0.0)
        SetRandomVehicleDensityMultiplierThisFrame(0.0)
        SetParkedVehicleDensityMultiplierThisFrame(0.0)
        SetPedDensityMultiplierThisFrame(0.0)
        SetScenarioPedDensityMultiplierThisFrame(0.0, 0.0)
        Wait(0)
    end
end

-- Keeps you swimming on top of the flood:
--  * in deep water you always float back up to the surface and stay there
--    swimming (the game's own swim animations - nothing forced);
--  * if you're stuck (snagged under something, or still "standing" in deep
--    water) for a moment, you're popped straight up to the surface;
--  * buoyancy = false makes it a lethal flood instead: you're dragged under,
--    and lose health once your breath (breathSeconds) runs out.
local function floodSwimHelper()
    local minDepth = FL.minDepth or 1.5
    local breathMs = (FL.breathSeconds or 12) * 1000
    local dps      = FL.drownDps or 8
    local buoyant  = FL.buoyancy ~= false
    local air, dmgAcc, last = breathMs, 0.0, GetGameTimer()
    local stuckSince = nil

    while floodActive do
        local now = GetGameTimer()
        local dt = now - last
        last = now

        local ped = PlayerPedId()
        local headUnder, inDeep = false, false
        if not IsPedInAnyVehicle(ped, false) and not IsEntityDead(ped) then
            local c = GetEntityCoords(ped)
            local found, surf = GetWaterHeight(c.x, c.y, c.z)
            if found and surf and (surf - (c.z - 0.95)) > minDepth then
                inDeep = true
                local v = GetEntityVelocity(ped)
                local floatZ = surf - 0.55           -- head and shoulders out of the water
                if not buoyant then
                    if v.z > -0.8 then SetEntityVelocity(ped, v.x, v.y, -0.8) end
                    headUnder = (c.z + 0.6) < surf
                else
                    local below = floatZ - c.z       -- how far under the swimming height we are
                    if below > 0.25 then
                        -- rise to the top (faster the deeper you are)
                        local up = math.min(6.0, 1.2 + below * 1.5)
                        if v.z < up then SetEntityVelocity(ped, v.x, v.y, up) end
                    end
                    -- not swimming yet, or not getting any higher: pop up to the surface
                    local stuck = (not IsPedSwimming(ped)) or (below > 0.6 and v.z < 0.3)
                    if stuck then
                        stuckSince = stuckSince or now
                        if now - stuckSince > 1200 then
                            SetEntityCoordsNoOffset(ped, c.x, c.y, floatZ, false, false, false)
                            SetEntityVelocity(ped, v.x * 0.3, v.y * 0.3, 0.0)
                            stuckSince = nil
                        end
                    else
                        stuckSince = nil
                    end
                    headUnder = (c.z + 0.6) < surf
                end
            else
                stuckSince = nil
            end
        end

        if headUnder then
            air = air - dt
            if air <= 0 then
                dmgAcc = dmgAcc + dps * dt / 1000.0
                if dmgAcc >= 1.0 then
                    local whole = math.floor(dmgAcc)
                    dmgAcc = dmgAcc - whole
                    local hp = GetEntityHealth(ped)
                    if hp > 0 then SetEntityHealth(ped, math.max(0, hp - whole)) end
                end
            end
        else
            air, dmgAcc = breathMs, 0.0
        end

        Wait(inDeep and 0 or 250)
    end
end

local function startFlood()
    if floodActive or not FL.enabled then return end
    floodActive = true

    CreateThread(riseWater)
    if FL.suppressTraffic then CreateThread(suppressTraffic) end
    if FL.physics ~= false then CreateThread(floodSwimHelper) end
    if FL.drownPeds then
        CreateThread(function()
            while floodActive do SetPedDiesInWater(PlayerPedId(), true); Wait(3000) end
        end)
    end
end

local function stopFlood()
    if not floodActive then return end
    floodActive = false
    SetPedDiesInWater(PlayerPedId(), false)
    -- ease the water back down, then restore the game's normal water
    CreateThread(function()
        local steps = 20
        for _ = 1, steps do
            shiftAllWater(-(FL.targetRise / steps))
            Wait(70)
        end
        ResetWater()
    end)
end

-- ------------------------------------------------------------
--  Ground lightning
-- ------------------------------------------------------------
local function drawBolt(sx, sy, topZ, gx, gy, gz)
    local segs = 9
    local px, py, pz = sx, sy, topZ
    for i = 1, segs do
        local t = i / segs
        local jitter = 7.0 * (1.0 - t)
        local nx = gx + (sx - gx) * (1 - t) + (math.random() - 0.5) * jitter
        local ny = gy + (sy - gy) * (1 - t) + (math.random() - 0.5) * jitter
        local nz = topZ + (gz - topZ) * t
        for o = -2, 2 do   -- a few offset lines = visible thickness
            local d = o * 0.18
            DrawLine(px + d, py, pz, nx + d, ny, nz, 190, 220, 255, 255)
        end
        px, py, pz = nx, ny, nz
    end
end

local function strikeAt(gx, gy, gz)
    local topZ = gz + 130.0
    local sx = gx + (math.random() - 0.5) * 16.0
    local sy = gy + (math.random() - 0.5) * 16.0
    CreateThread(function()
        for _ = 1, 7 do   -- flicker the bolt for ~7 frames
            drawBolt(sx, sy, topZ, gx, gy, gz)
            DrawLightWithRange(gx, gy, gz + 1.5, 170, 210, 255, 24.0, 20.0)
            Wait(0)
        end
    end)
    if Config.Lightning.damage then
        AddExplosion(gx, gy, gz, 11, 0.3, true, false, 0.0)   -- optional impact (can injure/ignite)
    end
end

CreateThread(function()
    while true do
        if current.lightning and current.value == 'THUNDER' then
            local cfg = Config.Lightning
            local c = GetEntityCoords(PlayerPedId())
            ForceLightningFlash()   -- sky flash + thunder for the burst
            for _ = 1, (cfg.boltsPerBurst or 1) do
                local ang  = math.random() * 6.2831
                local minD = cfg.minDistance or 30.0
                local dist = minD + math.random() * ((cfg.radius or 200.0) - minD)
                local x, y = c.x + math.cos(ang) * dist, c.y + math.sin(ang) * dist
                RequestCollisionAtCoord(x, y, c.z)
                local found, gz = GetGroundZFor_3dCoord(x, y, c.z + 200.0, false)
                strikeAt(x, y, found and gz or c.z)
                Wait(math.random(50, 220))   -- stagger bolts within the burst
            end
            Wait(math.random(cfg.minDelay or 2500, cfg.maxDelay or 7000))
        else
            Wait(1000)
        end
    end
end)

-- ------------------------------------------------------------
--  Weather
-- ------------------------------------------------------------
local function applyEffects(entry)
    local fx = entry.effects or {}
    SetForceVehicleTrails(fx.snow == true)
    SetForcePedFootstepsTracks(fx.snow == true)
    applyWind(fx.wind or 1.0)
    applyWaves(fx.waves)

    if fx.flood == true then startFlood() else stopFlood() end

    local want = fx.addon
    if current.addon ~= want then
        if current.addon then stopAddon(current.addon) end
        current.addon = want
        if want then startAddon(want) end
    end
end

local function applyWeather(entry, blackout, instant)
    if not entry then return end
    local prevId = current.weatherId
    current.weatherId, current.value, current.blackout = entry.id, entry.value, blackout

    local w = entry.value
    if instant then
        SetWeatherTypeNow(w)
        SetWeatherTypeNowPersist(w)
    else
        SetWeatherTypeOverTime(w, Config.WeatherTransitionTime)
        SetTimeout(math.floor(Config.WeatherTransitionTime * 1000), function()
            if current.value == w then SetWeatherTypeNowPersist(w) end
        end)
    end
    SetWeatherTypePersist(w)

    applyEffects(entry)

    SetArtificialLightsState(blackout)
    SetArtificialLightsStateAffectsVehicles(false)

    -- one-shot tornado warning when tornado weather begins (not on a resync)
    if not instant and entry.id == 'tornado' and prevId ~= 'tornado' and Config.TornadoWarning then
        nui({ action = 'playWarning', volume = Config.TornadoWarningVolume })
    end

    if Config.StormRumble then
        if Config.StormRumbleWeather[entry.id] then
            nui({ action = 'startRumble', volume = Config.StormRumbleVolume })
        else
            nui({ action = 'stopRumble' })
        end
    end
end

-- ------------------------------------------------------------
--  Clock: the server sends hours/minutes, we fill in the seconds
-- ------------------------------------------------------------
CreateThread(function()
    while true do
        NetworkOverrideClockTime(math.floor(clock.hour) % 24, math.floor(clock.minute) % 60, math.floor(clock.second) % 60)
        Wait(0)
    end
end)

CreateThread(function()
    local step = math.max(1, math.floor(Config.MillisecondsPerMinute / 60))
    while true do
        Wait(step)
        if Config.DynamicTime and not current.freeze then
            clock.second = (clock.second + 1) % 60
        end
    end
end)

-- ------------------------------------------------------------
--  Server -> client: state
-- ------------------------------------------------------------
RegisterNetEvent('weathersync:client:setWeather', function(weatherId, blackout)
    local entry = Config.GetWeather(weatherId)
    applyWeather(entry, blackout, false)
    if entry then nuiIfOpen({ action = 'updateWeather', id = entry.id, value = entry.value, blackout = blackout }) end
end)

RegisterNetEvent('weathersync:client:setTime', function(hour, minute, freeze)
    clock.hour, clock.minute, clock.second = hour, minute, 0
    current.freeze = freeze and true or false
    nuiIfOpen({ action = 'updateTime', hour = hour, minute = minute, freeze = current.freeze })
end)

RegisterNetEvent('weathersync:client:setDynamic', function(value)
    current.dynamic = value and true or false
    nuiIfOpen({ action = 'updateDynamic', dynamic = current.dynamic })
end)

RegisterNetEvent('weathersync:client:setLightning', function(value)
    current.lightning = value and true or false
    nuiIfOpen({ action = 'updateLightning', lightning = current.lightning })
end)

RegisterNetEvent('weathersync:client:setAlert', function(value)
    current.alert = value and true or false
    nuiIfOpen({ action = 'updateAlert', alert = current.alert })
end)

RegisterNetEvent('weathersync:client:setPurge', function(value)
    current.purge = value and true or false
    nuiIfOpen({ action = 'updatePurge', purge = current.purge })
end)

RegisterNetEvent('weathersync:client:setAdmin', function(value)
    isAdmin = value and true or false
    nuiIfOpen({ action = 'setAdmin', isAdmin = isAdmin })
end)

RegisterNetEvent('weathersync:client:syncState', function(data)
    clock.hour, clock.minute, clock.second = data.hour, data.minute, 0
    current.freeze  = data.freeze and true or false
    current.dynamic = data.dynamic and true or false
    current.alert   = data.alert and true or false
    if data.lightning ~= nil then current.lightning = data.lightning and true or false end
    if data.purge ~= nil then current.purge = data.purge and true or false end
    applyWeather(Config.GetWeather(data.weatherId), data.blackout, true)
end)

-- ------------------------------------------------------------
--  Server -> client: alerts, HUDs, sounds, toasts
-- ------------------------------------------------------------
RegisterNetEvent('weathersync:client:siren', function(on, remaining)
    nui({ action = on and 'playSiren' or 'stopSiren', volume = Config.RestartAlert.sirenVolume, remaining = remaining })
end)

RegisterNetEvent('weathersync:client:restartHud', function(data)
    nui({ action = 'restartHud', active = data.active, seconds = data.seconds })
end)

RegisterNetEvent('weathersync:client:purgeHud', function(data)
    nui({ action = 'purgeHud', active = data.active, phase = data.phase,
          seconds = data.seconds, label = data.label, activeLabel = data.activeLabel })
end)

RegisterNetEvent('weathersync:client:purgeSiren', function(data)
    nui({ action = 'purgeSiren', on = data.on, volume = data.volume, sound = data.sound, loop = data.loop })
end)

local function showBroadcast(d)
    nui({ action = 'purgeBroadcast', kind = d.kind, title = d.title,
          heading = d.heading, message = d.message, seconds = d.seconds })
end

RegisterNetEvent('weathersync:client:purgeBroadcast', function(data)
    if spawnedIn then return showBroadcast(data) end
    -- still loading: queue the "commenced" banner; an "ending" cancels it
    pendingBroadcast = (data.kind ~= 'ending') and data or nil
end)

local function onSpawned()
    if spawnedIn then return end
    spawnedIn = true
    if pendingBroadcast then
        local d = pendingBroadcast
        pendingBroadcast = nil
        showBroadcast(d)
    end
end

RegisterNetEvent('weathersync:client:notify', function(msg, nType)
    nui({ action = 'notify', text = msg, kind = nType or 'primary' })
end)

-- The server can't read ground height, so the triggering player picks a
-- ground-level tornado spawn point (and a nearby destination) and sends it back.
RegisterNetEvent('weathersync:client:resolveTornado', function()
    local ped = PlayerPedId()
    if not ped or ped == 0 then return end
    local sp = Config.TornadoSpawn or {}
    local c = GetEntityCoords(ped)
    local ang = math.random() * 6.2831
    local d = sp.distance or 280.0
    local x, y = c.x + math.cos(ang) * d, c.y + math.sin(ang) * d

    RequestCollisionAtCoord(x, y, c.z)   -- stream collision so the ground probe works that far out
    local found, gz = GetGroundZFor_3dCoord(x, y, c.z + 500.0, false)
    for _ = 1, 14 do
        if found then break end
        Wait(50)
        RequestCollisionAtCoord(x, y, c.z)
        found, gz = GetGroundZFor_3dCoord(x, y, c.z + 500.0, false)
    end
    local z = found and gz or (c.z - 5.0)

    local ang2 = math.random() * 6.2831
    local r = sp.roamRadius or 90.0
    local dx, dy = x + math.cos(ang2) * r, y + math.sin(ang2) * r
    local found2, gz2 = GetGroundZFor_3dCoord(dx, dy, z + 500.0, false)

    TriggerServerEvent('weathersync:server:tornadoResolved',
        { x = x, y = y, z = z }, { x = dx, y = dy, z = found2 and gz2 or z })
end)

-- ------------------------------------------------------------
--  Panel (NUI)
-- ------------------------------------------------------------
local function openMenu()
    menuOpen = true
    TriggerServerEvent('weathersync:server:checkAdmin')
    SetNuiFocus(true, true)
    nui({
        action = 'open',
        weatherTypes = Config.WeatherTypes, timePresets = Config.TimePresets,
        currentId = current.weatherId, currentValue = current.value,
        blackout = current.blackout, freeze = current.freeze, dynamic = current.dynamic,
        alert = current.alert, lightning = current.lightning, purge = current.purge,
        hour = clock.hour, minute = clock.minute,
        isAdmin = isAdmin, restricted = Config.RestrictToAdmins,
    })
end

local function closeMenu()
    menuOpen = false
    SetNuiFocus(false, false)
    nui({ action = 'close' })
end

-- panel callback -> server event (the server checks admin on every one)
local function relay(cb, event, ...)
    local keys = { ... }
    RegisterNUICallback(cb, function(data, reply)
        local args = {}
        for i, k in ipairs(keys) do args[i] = data[k] end
        TriggerServerEvent(event, table.unpack(args, 1, #keys))
        reply('ok')
    end)
end
relay('setWeather',      'weathersync:server:setWeather',      'id')
relay('setTime',         'weathersync:server:setTime',         'hour', 'minute')
relay('toggleFreeze',    'weathersync:server:toggleFreeze',    'value')
relay('toggleBlackout',  'weathersync:server:toggleBlackout',  'value')
relay('toggleDynamic',   'weathersync:server:toggleDynamic',   'value')
relay('toggleLightning', 'weathersync:server:toggleLightning', 'value')
relay('toggleAlert',     'weathersync:server:toggleAlert',     'value', 'seconds')
relay('togglePurge',     'weathersync:server:togglePurge',     'value', 'seconds')

RegisterNUICallback('close', function(_, reply) closeMenu(); reply('ok') end)

-- the server only sends this to admins
RegisterNetEvent('weathersync:client:openMenu', openMenu)

RegisterCommand(Config.MenuCommand, function()
    if menuOpen then closeMenu()
    else TriggerServerEvent('weathersync:server:requestMenu') end
end, false)
if Config.OpenKey then
    RegisterKeyMapping(Config.MenuCommand, 'Open Weather & Time menu', 'keyboard', Config.OpenKey)
end

-- ------------------------------------------------------------
--  Boot
-- ------------------------------------------------------------
AddEventHandler('onClientResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    -- data_file WATER_FILE can pre-load flood.xml; keep the normal water until a real flood
    ResetWater()
    applyWeather(Config.GetWeather(current.weatherId), current.blackout, true)
    TriggerServerEvent('weathersync:server:requestSync')
    TriggerServerEvent('weathersync:server:checkAdmin')
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if floodActive then floodActive = false; ResetWater() end
end)

AddEventHandler('playerSpawned', function()
    onSpawned()
    TriggerServerEvent('weathersync:server:requestSync')
end)
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', onSpawned)

-- Fallback "spawned" check in case neither event fires on this framework
CreateThread(function()
    while not spawnedIn do
        if NetworkIsSessionStarted() and DoesEntityExist(PlayerPedId())
           and not IsPlayerSwitchInProgress() and not IsScreenFadedOut() then
            Wait(1500)
            onSpawned()
            break
        end
        Wait(500)
    end
end)
