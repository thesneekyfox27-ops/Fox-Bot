local isWorking     = false
local passIsValid   = false
local pass          = { active = false, buyMin = 0 }
local expireHandled = false
local gymPed        = nil
local pedSpawned    = false
local boardProp     = nil
local boardSpawned  = false
local lastTrained   = 0
local lastWorkoutAt = 0
local energy        = 0
local energyStamp   = 0
local notifications = {}

local stats = { strength = 0, stamina = 0 }
local statHashes = {
    strength = GetHashKey('MP0_STRENGTH'),
    stamina  = GetHashKey('MP0_STAMINA'),
}

----------------------------------------------------------------
-- Framework
----------------------------------------------------------------
-- Find the core resource. tgiann-core / qbx_core are qb-core forks, so we detect
-- whichever is running (or use Config.CoreResource if you set it explicitly).
local CORE_CANDIDATES = { 'qb-core', 'qbx_core', 'tgiann-core' }

local function detectCore()
    local forced = Config.CoreResource
    if forced and forced ~= 'auto' then
        if GetResourceState(forced) == 'started' then return forced end
        return nil
    end
    for _, r in ipairs(CORE_CANDIDATES) do
        if GetResourceState(r) == 'started' then return r end
    end
    return nil
end

local coreName = detectCore()
local QBCore = nil
if coreName then
    local ok, core = pcall(function() return exports[coreName]:GetCoreObject() end)
    if ok then QBCore = core end
end

local function usingQB()
    if Config.Framework == 'standalone' then return false end
    if Config.Framework == 'qbcore' then return QBCore ~= nil end
    return QBCore ~= nil   -- auto
end

local function invName()
    return Config.InventoryResource or 'tgiann-inventory'
end

local function targetName()
    return Config.TargetResource or 'qb-target'
end

local function useTarget()
    if not usingQB() then return false end
    if Config.UseTarget == 'on'  then return true end
    if Config.UseTarget == 'off' then return false end
    return GetResourceState(targetName()) == 'started'
end

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------
local function firstUpper(s) return (s:gsub('^%l', string.upper)) end

-- On-screen notification (drawn at Config.Notify position, not the native feed)
local function notify(msg)
    notifications[#notifications + 1] = {
        text   = msg,
        expire = GetGameTimer() + (Config.Notify.duration or 4000),
    }
end

local function DrawText3D(x, y, z, text)
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    SetTextEntry('STRING')
    SetTextCentre(true)
    AddTextComponentString(text)
    SetDrawOrigin(x, y, z, 0)
    DrawText(0.0, 0.0)
    ClearDrawOrigin()
end

local function currentDateIndex()
    return (GetClockYear() * 10000) + (GetClockMonth() * 100) + GetClockDayOfMonth()
end

-- A continuous in-game minute counter, so we can measure a rolling 24-in-game-hour
-- window from the moment of purchase (not just "until midnight").
-- Assumes the in-game date advances normally (standard with time-sync resources).
local function currentIgMinute()
    local ord = (GetClockYear() * 372) + (GetClockMonth() * 31) + (GetClockDayOfMonth() - 1)
    return (ord * 1440) + (GetClockHours() * 60) + GetClockMinutes()
end

local function nowEpoch()
    -- os.time works on the FiveM client; fall back to game timer seconds if not.
    if os and os.time then return os.time() end
    return math.floor(GetGameTimer() / 1000)
end

----------------------------------------------------------------
-- Energy / exhaustion
----------------------------------------------------------------
local function regenEnergy()
    if not Config.Energy.enabled then return end
    local now = nowEpoch()
    if energyStamp <= 0 then energyStamp = now end
    local mins = (now - energyStamp) / 60.0
    if mins > 0 then
        energy = math.min(Config.Energy.max, energy + mins * (Config.Energy.regenPerMin or 0))
        if energy < 0 then energy = 0 end
        energyStamp = now
    end
end

local function isExhausted()
    if not Config.Energy.enabled then return false end
    return energy < (Config.Energy.costPerWorkout or 25)
end

-- Stats board: shows current strength/stamina and the live boosts from stamina.
local function drawStatsBoard()
    local b = Config.StatsBoard
    local c = b.coords
    local frac = math.min(math.max(stats.stamina / Config.MaxStat, 0.0), 1.0)
    local e = Config.Effects
    local speed  = e.speedBase  + (e.speedMax  - e.speedBase)  * frac
    local speedPct = math.floor((speed - 1.0) * 100 + 0.5)
    local endurance = math.floor(stats.stamina * (e.staminaGameRatio or 1.0) + 0.5)

    local lines = {
        '~y~- MUSCLE SANDS -',
        ('~w~Strength: ~b~%d/%d'):format(stats.strength, Config.MaxStat),
        ('~w~Stamina:  ~b~%d/%d'):format(stats.stamina, Config.MaxStat),
        ('~w~Move speed: ~g~+%d%%'):format(speedPct),
        ('~w~Sprint endurance: ~g~%d/100'):format(endurance),
    }
    if Config.Energy.enabled then
        lines[#lines + 1] = ('~w~Energy: ~b~%d/%d'):format(math.floor(energy + 0.5), Config.Energy.max)
        if isExhausted() then
            lines[#lines + 1] = '~r~EXHAUSTED - rest to recover'
        end
    end
    lines[#lines + 1] = '~w~Strength = stronger melee + build'
    local top = c.z + 1.4
    for i, line in ipairs(lines) do
        DrawText3D(c.x, c.y, top - (i - 1) * 0.18, line)
    end
end

----------------------------------------------------------------
-- Appearance hook (optional - requires your own appearance resource)
----------------------------------------------------------------
local function applyAppearance()
    if not Config.Appearance.enabled then return end
    -- The strength stat below already drives muscle where the game supports it.
    -- To force a live body morph, call your appearance resource here, e.g.:
    --   exports['illenium-appearance']:setPedAppearance(...)
    -- using a muscle value scaled from stats.strength (0-100).
end

----------------------------------------------------------------
-- Stamina / strength gameplay effects
----------------------------------------------------------------
local function applyEffects()
    if not Config.Effects.enabled then return end
    local e = Config.Effects
    local pid = PlayerId()
    local frac = math.min(math.max(stats.stamina / Config.MaxStat, 0.0), 1.0)
    local speed = e.speedBase + (e.speedMax - e.speedBase) * frac
    local swim  = (e.swimBase or 1.0) + ((e.swimMax or 1.0) - (e.swimBase or 1.0)) * frac
    if speed > 1.49 then speed = 1.49 elseif speed < 1.0 then speed = 1.0 end
    if swim  > 1.49 then swim  = 1.49 elseif swim  < 1.0 then swim  = 1.0 end
    SetRunSprintMultiplierForPlayer(pid, speed)   -- higher = run faster (cap ~1.49)
    SetSwimMultiplierForPlayer(pid, swim)         -- higher = swim faster (cap ~1.49)
end

----------------------------------------------------------------
-- Stat handling
----------------------------------------------------------------
local function applyStats()
    StatSetInt(statHashes.strength, stats.strength, true)
    -- Tiredness: feed the game only a fraction of stored stamina so players tire
    -- faster. Training raises stored stamina, which raises the sprint duration.
    local ratio = (Config.Effects.enabled and Config.Effects.staminaGameRatio) or 1.0
    local gameStam = stats.stamina * ratio
    if isExhausted() then
        gameStam = gameStam * (Config.Energy.exhaustedStaminaMult or 0.3)
    end
    gameStam = math.floor(gameStam + 0.5)
    if gameStam < 0 then gameStam = 0 elseif gameStam > 100 then gameStam = 100 end
    StatSetInt(statHashes.stamina, gameStam, true)
    applyEffects()
    applyAppearance()
end

local function saveStats()
    if usingQB() then
        TriggerServerEvent('ms_gym:save', stats.strength, stats.stamina, lastTrained,
            math.floor(energy + 0.5), energyStamp)
    else
        SetResourceKvpInt('ms_strength', stats.strength)
        SetResourceKvpInt('ms_stamina', stats.stamina)
        SetResourceKvpInt('ms_lasttrained', lastTrained)
        SetResourceKvpInt('ms_energy', math.floor(energy + 0.5))
        SetResourceKvpInt('ms_energy_stamp', energyStamp)
    end
end

local function loadStats()
    if usingQB() then
        local pd = QBCore and QBCore.Functions.GetPlayerData() or nil
        if pd and pd.metadata then
            stats.strength = pd.metadata.strength or 0
            stats.stamina  = pd.metadata.stamina or 0
            lastTrained    = pd.metadata.gymLastTrained or 0
            energy         = pd.metadata.gymEnergy or 0
            energyStamp    = pd.metadata.gymEnergyStamp or 0
        end
    else
        stats.strength = GetResourceKvpInt('ms_strength') or 0
        stats.stamina  = GetResourceKvpInt('ms_stamina') or 0
        lastTrained    = GetResourceKvpInt('ms_lasttrained') or 0
        energy         = GetResourceKvpInt('ms_energy') or 0
        energyStamp    = GetResourceKvpInt('ms_energy_stamp') or 0
    end
    if stats.strength < 0 then stats.strength = 0 end
    if stats.stamina  < 0 then stats.stamina  = 0 end
    if lastTrained <= 0 then         -- never trained before: start the clock now
        lastTrained = nowEpoch()
        saveStats()
    end
    if energyStamp <= 0 then         -- new player: start with a full tank
        energy = Config.Energy.max
        energyStamp = nowEpoch()
    else
        regenEnergy()                -- returning player: credit rest time since last save
    end
end

local function addStat(kind, amount)
    local current = stats[kind] or 0
    lastTrained = nowEpoch()
    if current >= Config.MaxStat then
        notify(('Your ~b~%s~s~ is already maxed out!'):format(kind))
        saveStats()
        return
    end
    stats[kind] = math.min(current + amount, Config.MaxStat)
    applyStats()
    saveStats()
    notify(('~g~%s~s~ increased to ~b~%d/%d'):format(firstUpper(kind), stats[kind], Config.MaxStat))
end

----------------------------------------------------------------
-- Decay: lose stats when you don't train for a while
----------------------------------------------------------------
local function applyDecay()
    if not Config.Decay.enabled then return end
    local d = Config.Decay
    local idle = nowEpoch() - lastTrained
    local graceSec = (d.graceHours or 24) * 3600
    if idle <= graceSec then return end
    local daysIdle = math.floor((idle - graceSec) / 86400)
    if daysIdle < 1 then return end

    local loss = (d.lossPerDay or 1) * daysIdle
    stats.strength = math.max(0, stats.strength - loss)
    stats.stamina  = math.max(0, stats.stamina  - loss)
    -- consume the days we just applied so it doesn't recompound
    lastTrained = lastTrained + daysIdle * 86400

    applyStats()
    saveStats()
    -- silent: no popup. Players see their current numbers on the gym stats board.
end

----------------------------------------------------------------
-- Gym pass (gym_pass item + rolling 24-in-game-hour expiry)
----------------------------------------------------------------
local function passWindowMins()
    return ((Config.GymPass.durationIgHours or 24) * 60)
end

local function hasPassItem()
    if not usingQB() then return true end
    if not Config.GymPass.requireItem then return true end
    if Config.GymPass.hasItemExport then
        return exports[invName()]:HasItem(Config.GymPass.item, 1)
    end
    return QBCore.Functions.HasItem(Config.GymPass.item) and true or false
end

local function expirePass()
    if expireHandled then return end
    expireHandled = true
    pass.active = false
    pass.buyMin = 0
    passIsValid = false
    if usingQB() then
        TriggerServerEvent('ms_gym:clearPass', currentIgMinute())   -- server validates + removes once
    else
        DeleteResourceKvp('ms_pass_active')
        DeleteResourceKvp('ms_pass_buymin')
    end
    notify('~r~Your gym pass has expired.')
end

local function refreshPass()
    if usingQB() then
        local pd = QBCore and QBCore.Functions.GetPlayerData() or nil
        local gp = pd and pd.metadata and pd.metadata.gympass or nil
        if gp and gp.buyMin then
            pass.active = true
            pass.buyMin = gp.buyMin
        elseif not pass.active then
            pass.buyMin = 0
        end
    else
        pass.active = (GetResourceKvpInt('ms_pass_active') == 1)
        pass.buyMin = GetResourceKvpInt('ms_pass_buymin')
    end

    if not pass.active then passIsValid = false; return end

    local elapsed = currentIgMinute() - pass.buyMin
    if elapsed < 0 then elapsed = 0 end          -- clock/date drift safety
    if elapsed >= passWindowMins() then          -- 24 in-game hours have passed
        expirePass()
        return
    end
    passIsValid = hasPassItem()
end

local function buyPass()
    if passIsValid then
        notify('~y~You already have an active gym pass.')
        return
    end
    if usingQB() then
        TriggerServerEvent('ms_gym:buyPass', currentIgMinute())
    else
        pass.active = true
        pass.buyMin = currentIgMinute()
        expireHandled = false
        SetResourceKvpInt('ms_pass_active', 1)
        SetResourceKvpInt('ms_pass_buymin', pass.buyMin)
        passIsValid = true
        notify(('~g~Gym pass purchased!~s~ Valid for %d in-game hours.'):format(Config.GymPass.durationIgHours or 24))
    end
end

RegisterNetEvent('ms_gym:passGranted', function(buyMin)
    pass.active = true
    pass.buyMin = buyMin
    expireHandled = false
    passIsValid = true
    notify(('~g~Gym pass purchased!~s~ Valid for %d in-game hours.'):format(Config.GymPass.durationIgHours or 24))
end)

RegisterNetEvent('ms_gym:passDenied', function(reason)
    notify('~r~' .. (reason or 'Could not buy a gym pass.'))
end)

----------------------------------------------------------------
-- Workout
----------------------------------------------------------------
local function startAnim(ped, st)
    if st.scenario then
        TaskStartScenarioInPlace(ped, st.scenario, 0, true)
    elseif st.animDict then
        RequestAnimDict(st.animDict)
        local timeout = 0
        while not HasAnimDictLoaded(st.animDict) and timeout < 1500 do
            Wait(10); timeout = timeout + 10
        end
        TaskPlayAnim(ped, st.animDict, st.animName, 8.0, -8.0, -1, 1, 0, false, false, false)
    end
end

local scenarioPropModels = {
    `prop_curl_bar_01`,
    `prop_dumbbell_01`,
}

local function cleanupScenarioProps(ped)
    local coords = GetEntityCoords(ped)
    for _, model in ipairs(scenarioPropModels) do
        local obj = GetClosestObjectOfType(coords.x, coords.y, coords.z, 3.0, model, false, false, false)
        if obj ~= 0 and DoesEntityExist(obj) and IsEntityAttachedToEntity(obj, ped) then
            DetachEntity(obj, true, true)
            SetEntityAsMissionEntity(obj, true, true)
            DeleteObject(obj)
            if DoesEntityExist(obj) then DeleteEntity(obj) end
        end
    end
end

-- Safety net: if a workout gets interrupted (e.g. pressing B to point mid-set),
-- the scenario's prop can stay stuck to your hand. While you're NOT working out,
-- delete any such prop attached to you, or sitting right on top of you.
CreateThread(function()
    while true do
        Wait(1000)
        if not isWorking then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            for _, model in ipairs(scenarioPropModels) do
                local obj = GetClosestObjectOfType(coords.x, coords.y, coords.z, 2.0, model, false, false, false)
                if obj ~= 0 and DoesEntityExist(obj) then
                    local stuck = IsEntityAttachedToEntity(obj, ped)
                        or (#(GetEntityCoords(obj) - coords) < 1.1)
                    if stuck then
                        DetachEntity(obj, true, true)
                        SetEntityAsMissionEntity(obj, true, true)
                        DeleteObject(obj)
                        if DoesEntityExist(obj) then DeleteEntity(obj) end
                    end
                end
            end
        end
    end
end)

local function doWorkout(st)
    if isWorking then return end
    if not passIsValid then
        notify('~r~You need a gym pass to use the equipment.')
        return
    end
    regenEnergy()
    if isExhausted() then
        notify("~r~You're too exhausted to work out.~s~ Rest and recover first.")
        return
    end
    local cd = (Config.WorkoutCooldown or 0) * 1000
    if cd > 0 and (GetGameTimer() - lastWorkoutAt) < cd then
        local remain = math.ceil((cd - (GetGameTimer() - lastWorkoutAt)) / 1000)
        notify(('~y~Catch your breath - rest %ds.'):format(remain))
        return
    end
    isWorking = true

    local ped = PlayerPedId()
    if st.heading then SetEntityHeading(ped, st.heading + 0.0) end
    ClearPedTasksImmediately(ped)
    startAnim(ped, st)

    local elapsed = 0
    local cancelled = false
    while elapsed < Config.WorkoutDuration do
        Wait(0)
        elapsed = elapsed + GetFrameTime() * 1000.0
        local pct = math.floor((elapsed / Config.WorkoutDuration) * 100)
        DrawText3D(st.coords.x, st.coords.y, st.coords.z + 1.0,
            ('~w~%s  ~b~%d%%~s~   [~r~X~s~] Stop'):format(st.label, pct))
        if IsControlJustReleased(0, Config.CancelKey) then
            cancelled = true
            break
        end
    end

    cleanupScenarioProps(ped)
    ClearPedTasksImmediately(ped)
    if st.animDict then RemoveAnimDict(st.animDict) end
    isWorking = false

    if cancelled then
        notify('~y~Workout stopped early.')
    else
        lastWorkoutAt = GetGameTimer()
        regenEnergy()
        energy = math.max(0, energy - (Config.Energy.costPerWorkout or 25))
        energyStamp = nowEpoch()
        addStat(st.stat, Config.GainPerSession)   -- saves stats + energy
        applyStats()                              -- re-apply (exhaustion may now debuff stamina)
        if isExhausted() then
            notify('~o~You\'re wiped out. Time to rest before your next session.')
        end
    end
end

----------------------------------------------------------------
-- Vendor NPC (managed: spawns only when you're near, snaps to ground)
----------------------------------------------------------------
local function clearStrayVendorPeds()
    local c = Config.GymPass.pedCoords
    local model = GetHashKey(Config.GymPass.pedModel)
    for _, p in ipairs(GetGamePool('CPed')) do
        if DoesEntityExist(p) and not IsPedAPlayer(p) and p ~= gymPed
           and GetEntityModel(p) == model then
            if #(GetEntityCoords(p) - vector3(c.x, c.y, c.z)) < 6.0 then
                SetEntityAsMissionEntity(p, true, true)
                DeleteEntity(p)
            end
        end
    end
end

local function spawnVendorPed()
    local g = Config.GymPass
    if not g.spawnPed then return end
    clearStrayVendorPeds()

    local m = GetHashKey(g.pedModel)
    RequestModel(m)
    local t = 0
    while not HasModelLoaded(m) and t < 5000 do Wait(10); t = t + 10 end
    if not HasModelLoaded(m) then return end

    local c = g.pedCoords
    gymPed = CreatePed(1, m, c.x, c.y, c.z, c.w, false, true)

    -- The gym is on a raised boardwalk; ground-snapping finds the sand UNDER the
    -- deck and sinks the ped. So snap only if explicitly enabled; otherwise place
    -- the ped at the exact configured Z.
    if g.groundSnap then
        RequestCollisionAtCoord(c.x, c.y, c.z)
        for _ = 1, 30 do
            local found, groundZ = GetGroundZFor_3dCoord(c.x, c.y, c.z + 3.0, false)
            if found and groundZ ~= 0.0 then
                SetEntityCoordsNoOffset(gymPed, c.x, c.y, groundZ, false, false, false)
                break
            end
            Wait(50)
        end
    else
        SetEntityCoordsNoOffset(gymPed, c.x, c.y, c.z, false, false, false)
    end
    SetEntityHeading(gymPed, c.w)
    FreezeEntityPosition(gymPed, true)
    SetEntityInvincible(gymPed, true)
    SetBlockingOfNonTemporaryEvents(gymPed, true)
    TaskStartScenarioInPlace(gymPed, 'WORLD_HUMAN_CLIPBOARD', 0, true)
    SetModelAsNoLongerNeeded(m)

    if useTarget() then
        pcall(function()
            exports[targetName()]:AddTargetEntity(gymPed, {
                options = {
                    { type = 'client', icon = 'fa-solid fa-dumbbell', label = 'Buy Gym Pass',
                      action = function() buyPass() end },
                },
                distance = 2.0,
            })
        end)
    end
end

local function spawnBoardProp()
    local b = Config.StatsBoard
    if not (b.enabled and b.prop) then return end
    local m = GetHashKey(b.prop)
    RequestModel(m)
    local t = 0
    while not HasModelLoaded(m) and t < 5000 do Wait(10); t = t + 10 end
    if not HasModelLoaded(m) then return end
    local c = b.coords
    boardProp = CreateObject(m, c.x, c.y, c.z, false, true, false)
    if b.groundSnap then
        PlaceObjectOnGroundProperly(boardProp)   -- sinks on the boardwalk; off by default
    else
        SetEntityCoords(boardProp, c.x, c.y, c.z, false, false, false, false)
    end
    SetEntityHeading(boardProp, b.heading or 0.0)
    FreezeEntityPosition(boardProp, true)
    SetModelAsNoLongerNeeded(m)
end

CreateThread(function()
    local c = Config.GymPass.pedCoords
    while true do
        local dist = #(GetEntityCoords(PlayerPedId()) - vector3(c.x, c.y, c.z))
        if dist < 50.0 then
            if not (gymPed and DoesEntityExist(gymPed)) then
                spawnVendorPed()
            else
                clearStrayVendorPeds()   -- delete ambient lookalikes so only ours remains
            end
            if not boardSpawned then
                spawnBoardProp()
                boardSpawned = true
            end
        end
        Wait(2000)
    end
end)

----------------------------------------------------------------
-- Map blip (own thread so it always shows, independent of the ped)
----------------------------------------------------------------
CreateThread(function()
    local g = Config.GymPass
    if not g.showBlip then return end
    local c = g.pedCoords
    local blip = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(blip, g.blipSprite)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, g.blipScale + 0.0)
    SetBlipColour(blip, g.blipColor)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(g.blipName)
    EndTextCommandSetBlipName(blip)
end)

----------------------------------------------------------------
-- Notification renderer
----------------------------------------------------------------
CreateThread(function()
    while true do
        if #notifications > 0 then
            for i = #notifications, 1, -1 do
                if GetGameTimer() > notifications[i].expire then
                    table.remove(notifications, i)
                end
            end
            local nx, ny = Config.Notify.x, Config.Notify.y
            local sc = Config.Notify.scale or 0.42
            for i, note in ipairs(notifications) do
                SetTextScale(sc, sc)
                SetTextFont(4)
                SetTextProportional(1)
                SetTextColour(255, 255, 255, 225)
                SetTextOutline()
                SetTextCentre(true)
                SetTextEntry('STRING')
                AddTextComponentString(note.text)
                DrawText(nx, ny + (i - 1) * 0.035)
            end
            Wait(0)
        else
            Wait(250)
        end
    end
end)

----------------------------------------------------------------
-- Effects re-apply + energy regen (natives reset on respawn)
----------------------------------------------------------------
CreateThread(function()
    while true do
        regenEnergy()
        applyStats()   -- re-applies run/swim speed AND the exhaustion stamina debuff/recovery
        Wait(5000)
    end
end)

----------------------------------------------------------------
-- Build interaction spots (coords, coords2, coords3, ... + optional spots list)
----------------------------------------------------------------
local gymSpots = {}
local function buildSpots()
    gymSpots = {}
    for _, st in ipairs(Config.Stations) do
        local list = {}
        if st.coords then list[#list + 1] = st.coords end
        local i = 2
        while st['coords' .. i] do
            list[#list + 1] = st['coords' .. i]; i = i + 1
        end
        if st.spots then for _, cc in ipairs(st.spots) do list[#list + 1] = cc end end
        for idx, cc in ipairs(list) do
            gymSpots[#gymSpots + 1] = {
                label = st.label, coords = cc,
                heading = (st.headings and st.headings[idx]) or st.heading,
                stat = st.stat, scenario = st.scenario,
                animDict = st.animDict, animName = st.animName,
            }
        end
    end
end
buildSpots()

----------------------------------------------------------------
-- Load + pass refresh + decay loop
----------------------------------------------------------------
CreateThread(function()
    Wait(1500)
    loadStats()
    applyStats()
    refreshPass()
    applyDecay()
    local tick = 0
    while true do
        Wait(3000)
        refreshPass()
        tick = tick + 3
        if tick >= 300 then   -- check decay every ~5 minutes
            applyDecay()
            tick = 0
        end
    end
end)

----------------------------------------------------------------
-- Main loop: buy point (no target) + pass-gated station markers
----------------------------------------------------------------
CreateThread(function()
    while true do
        local sleep = 1000
        local pos = GetEntityCoords(PlayerPedId())

        if not useTarget() then
            local bp = Config.GymPass.pedCoords
            local bdist = #(pos - vector3(bp.x, bp.y, bp.z))
            if bdist < Config.DrawDistance then
                sleep = 0
                if bdist < Config.InteractDistance and not isWorking then
                    if passIsValid then
                        DrawText3D(bp.x, bp.y, bp.z + 1.0, '~g~Gym Pass active~s~ (expires end of day)')
                    else
                        local priceTxt = usingQB() and ('$' .. Config.GymPass.price) or 'free'
                        DrawText3D(bp.x, bp.y, bp.z + 1.0, ('[~b~E~s~] Buy Gym Pass (%s)'):format(priceTxt))
                        if IsControlJustReleased(0, Config.InteractKey) then buyPass() end
                    end
                end
            end
        end

        if passIsValid then
            for _, st in ipairs(gymSpots) do
                local dist = #(pos - st.coords)
                if dist < Config.DrawDistance then
                    sleep = 0
                    if Config.ShowMarkers then
                        local c = Config.MarkerColor
                        DrawMarker(1, st.coords.x, st.coords.y, st.coords.z - 0.95,
                            0, 0, 0, 0, 0, 0, 0.6, 0.6, 0.4,
                            c.r, c.g, c.b, c.a, false, false, 2, false, nil, nil, false)
                    end
                    if dist < Config.InteractDistance and not isWorking then
                        DrawText3D(st.coords.x, st.coords.y, st.coords.z + 0.9,
                            ('[~b~E~s~] %s'):format(st.label))
                        if IsControlJustReleased(0, Config.InteractKey) then doWorkout(st) end
                    end
                end
            end
        end

        -- Stats board (visible whether or not you hold a pass)
        if Config.StatsBoard.enabled then
            local bc = Config.StatsBoard.coords
            if #(pos - bc) < Config.StatsBoard.drawDistance then
                sleep = 0
                drawStatsBoard()
            end
        end

        Wait(sleep)
    end
end)

----------------------------------------------------------------
-- QBCore: reload on player loaded
----------------------------------------------------------------
if usingQB() then
    RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
        Wait(500)
        loadStats()
        applyStats()
        refreshPass()
        applyDecay()
    end)
end

----------------------------------------------------------------
-- Cleanup ped on resource stop
----------------------------------------------------------------
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if gymPed and DoesEntityExist(gymPed) then DeleteEntity(gymPed) end
    if boardProp and DoesEntityExist(boardProp) then DeleteEntity(boardProp) end
end)

----------------------------------------------------------------
-- Commands
----------------------------------------------------------------
RegisterCommand('gympass', function()
    if passIsValid then
        notify('~g~Gym pass: ACTIVE~s~ (expires when the in-game day ends).')
    else
        notify('~r~Gym pass: NONE.~s~ Buy one from the trainer at the gym.')
    end
end, false)

RegisterCommand('gymstats', function()
    regenEnergy()   -- bring energy current, then show it from wherever you are
    local msg = ('Strength ~b~%d/%d~s~  |  Stamina ~b~%d/%d')
        :format(stats.strength, Config.MaxStat, stats.stamina, Config.MaxStat)
    if Config.Energy.enabled then
        msg = msg .. ('~s~  |  Energy ~b~%d/%d'):format(math.floor(energy + 0.5), Config.Energy.max)
        if isExhausted() then msg = msg .. ' ~r~(exhausted)' end
    end
    notify(msg)
end, false)

RegisterCommand('gymcoords', function()
    local p = GetEntityCoords(PlayerPedId())
    local h = GetEntityHeading(PlayerPedId())
    local line = ('vector3(%.2f, %.2f, %.2f)  heading %.1f'):format(p.x, p.y, p.z, h)
    print('[muscle_sands_gym] ' .. line)
    notify('Coords printed to F8 console.')
end, false)
