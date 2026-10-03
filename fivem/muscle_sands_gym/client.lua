-- ============================================================
--  MUSCLE SANDS GYM - client
--  Trainer, station markers, the rep minigame and stat effects.
--  The server owns the numbers; this side just shows them.
-- ============================================================

local QBCore = exports['qb-core']:GetCoreObject()
local SPOTS = GymSpots()

local state = { strength = 0, stamina = 0, max = Config.MaxStat, energy = 100, energyMax = 100, exhausted = false, pass = nil, hasCard = false }
local working   = false
local trainer   = nil
local menuOpen  = false
local prompt    = nil   -- id of the prompt currently shown

local function notify(msg, kind)
    if GetResourceState('ox_lib') == 'started' then
        TriggerEvent('ox_lib:notify', { title = 'Muscle Sands', description = msg, type = kind or 'inform', position = 'top' })
    else
        QBCore.Functions.Notify(msg, kind == 'inform' and 'primary' or kind)
    end
end
RegisterNetEvent('ms_gym:notify', notify)

local function canTrain() return state.pass ~= nil and state.hasCard end

local function showPrompt(id, key, text)
    if prompt == id then return end
    prompt = id
    SendNUIMessage({ action = 'prompt', key = key, text = text })
end

local function hidePrompt(id)
    if id and prompt ~= id then return end
    if prompt then SendNUIMessage({ action = 'prompt' }) end
    prompt = nil
end

-- ------------------------------------------------------------
--  Stats -> gameplay
-- ------------------------------------------------------------
local function lerp(a, b, t) return a + (b - a) * t end

local function applyEffects()
    local pid, E = PlayerId(), Config.Effects
    local str = math.min(math.max(state.strength / state.max, 0), 1)
    local sta = math.min(math.max(state.stamina / state.max, 0), 1)

    StatSetInt(`MP0_STRENGTH`, math.floor(state.strength), true)
    local game = state.stamina * (E.enabled and E.staminaGameRatio or 1.0)
    if state.exhausted then game = game * (Config.Energy.exhaustedStaminaMult or 0.3) end
    StatSetInt(`MP0_STAMINA`, math.floor(math.min(100, math.max(0, game))), true)

    if not E.enabled then return end
    SetRunSprintMultiplierForPlayer(pid, math.min(1.49, lerp(E.speedBase, E.speedMax, sta)))
    SetSwimMultiplierForPlayer(pid, math.min(1.49, lerp(E.swimBase, E.swimMax, sta)))
    SetPlayerMeleeWeaponDamageModifier(pid, lerp(E.meleeBase, E.meleeMax, str))
end

local function perks()
    local E = Config.Effects
    local str = state.strength / state.max
    local sta = state.stamina / state.max
    return {
        speed  = math.floor((lerp(E.speedBase, E.speedMax, sta) - 1) * 100 + 0.5),
        melee  = math.floor((lerp(E.meleeBase, E.meleeMax, str) - 1) * 100 + 0.5),
        sprint = math.floor(state.stamina * E.staminaGameRatio + 0.5),
    }
end

RegisterNetEvent('ms_gym:sync', function(s)
    state = s
    applyEffects()
    if menuOpen then SendNUIMessage({ action = 'state', state = state, perks = perks() }) end
end)

CreateThread(function()   -- natives reset on respawn / model change
    while true do
        Wait(5000)
        applyEffects()
    end
end)

CreateThread(function()   -- energy ticks back up server-side; check in now and then
    while not LocalPlayer.state.isLoggedIn do Wait(1000) end
    TriggerServerEvent('ms_gym:requestSync')
    while true do
        Wait(60000)
        TriggerServerEvent('ms_gym:requestSync')
    end
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    Wait(2000)
    TriggerServerEvent('ms_gym:requestSync')
end)

-- ------------------------------------------------------------
--  Trainer menu (NUI)
-- ------------------------------------------------------------
local function openMenu(atTrainer)
    if menuOpen or working then return end
    menuOpen = true
    hidePrompt()
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'menu', canBuy = atTrainer == true,
        state = state, perks = perks(), tiers = Config.Pass.tiers,
        reps = Config.Workout.reps, energyCost = Config.Energy.costPerWorkout,
    })
    TriggerServerEvent('ms_gym:requestSync')
    if Config.Leaderboard.enabled then
        QBCore.Functions.TriggerCallback('ms_gym:leaderboard', function(board)
            if menuOpen then SendNUIMessage({ action = 'board', board = board }) end
        end)
    end
end

RegisterNUICallback('close', function(_, cb)
    menuOpen = false
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('buy', function(data, cb)
    TriggerServerEvent('ms_gym:buy', tostring(data.tier or ''))
    cb('ok')
end)

-- ------------------------------------------------------------
--  Trainer ped (streamed) + blip
-- ------------------------------------------------------------
local function loadModel(m)
    m = type(m) == 'string' and joaat(m) or m
    if not IsModelInCdimage(m) then return nil end
    RequestModel(m)
    local t = GetGameTimer() + 5000
    while not HasModelLoaded(m) do
        if GetGameTimer() > t then return nil end
        Wait(25)
    end
    return m
end

local function addTarget(ped)
    local opts = {
        { label = 'Talk to the trainer', icon = 'fa-solid fa-dumbbell' },
    }
    local mode = Config.Target
    if mode == 'off' then return false end
    if (mode == 'auto' or mode == 'ox_target') and GetResourceState('ox_target') == 'started' then
        exports.ox_target:addLocalEntity(ped, { {
            name = 'ms_gym_trainer', label = opts[1].label, icon = opts[1].icon, distance = 2.5,
            onSelect = function() openMenu(true) end,
        } })
        return true
    end
    if (mode == 'auto' or mode == 'qb-target') and GetResourceState('qb-target') == 'started' then
        exports['qb-target']:AddTargetEntity(ped, {
            options = { { type = 'client', icon = opts[1].icon, label = opts[1].label, action = function() openMenu(true) end } },
            distance = 2.5,
        })
        return true
    end
    return false
end

local usingTarget = false

local function spawnTrainer()
    local T = Config.Trainer
    local m = loadModel(T.model)
    if not m then return print('[muscle_sands_gym] trainer model is not valid') end
    local c = T.coords
    RequestCollisionAtCoord(c.x, c.y, c.z)
    local ped = CreatePed(4, m, c.x, c.y, c.z, c.w, false, true)
    -- coords are standing coords on the boardwalk deck: place exactly, never ground-snap
    SetEntityCoordsNoOffset(ped, c.x, c.y, c.z, false, false, false)
    SetEntityHeading(ped, c.w)
    SetEntityAsMissionEntity(ped, true, true)
    SetEntityInvincible(ped, true)
    SetPedCanRagdoll(ped, false)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    local t = GetGameTimer() + 3000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < t do Wait(50) end
    FreezeEntityPosition(ped, true)
    if T.scenario then TaskStartScenarioInPlace(ped, T.scenario, 0, true) end
    SetModelAsNoLongerNeeded(m)
    trainer = ped
    usingTarget = addTarget(ped)
end

CreateThread(function()
    local B = Config.Trainer.blip
    if not B.enabled then return end
    local c = Config.Trainer.coords
    local blip = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(blip, B.sprite)
    SetBlipColour(blip, B.color)
    SetBlipScale(blip, B.scale + 0.0)
    SetBlipDisplay(blip, 4)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(B.name)
    EndTextCommandSetBlipName(blip)
end)

CreateThread(function()
    local T = Config.Trainer
    local tc = vector3(T.coords.x, T.coords.y, T.coords.z)
    while true do
        local d = #(GetEntityCoords(PlayerPedId()) - tc)
        if d < T.spawnDistance and not (trainer and DoesEntityExist(trainer)) then
            spawnTrainer()
        elseif d > T.despawnDistance and trainer then
            if DoesEntityExist(trainer) then DeleteEntity(trainer) end
            trainer = nil
        end
        Wait(1500)
    end
end)

-- ------------------------------------------------------------
--  Workout + rep minigame
-- ------------------------------------------------------------
local propModels = { `prop_curl_bar_01`, `prop_dumbbell_01`, `prop_barbell_01`, `prop_yoga_mat_01` }

local function cleanupProps(ped, radius, anyNearby)
    local c = GetEntityCoords(ped)
    for _, m in ipairs(propModels) do
        for _ = 1, 3 do
            local obj = GetClosestObjectOfType(c.x, c.y, c.z, radius, m, false, false, false)
            if obj == 0 or not DoesEntityExist(obj) then break end
            if not (IsEntityAttachedToEntity(obj, ped) or anyNearby) then break end
            DetachEntity(obj, true, true)
            SetEntityAsMissionEntity(obj, true, true)
            DeleteEntity(obj)
        end
    end
end

-- stray workout props stuck to your hands after an interrupted set
CreateThread(function()
    while true do
        Wait(1500)
        if not working then cleanupProps(PlayerPedId(), 2.0, false) end
    end
end)

local function startAnim(ped, sp)
    if sp.scenario then
        TaskStartScenarioInPlace(ped, sp.scenario, 0, true)
    elseif sp.animDict then
        RequestAnimDict(sp.animDict)
        local t = GetGameTimer() + 1500
        while not HasAnimDictLoaded(sp.animDict) and GetGameTimer() < t do Wait(10) end
        TaskPlayAnim(ped, sp.animDict, sp.animName, 8.0, -8.0, -1, 1, 0, false, false, false)
    end
end

local pendingStart = nil

RegisterNetEvent('ms_gym:startDenied', function(msg)
    pendingStart = false
    notify(msg, 'error')
end)

RegisterNetEvent('ms_gym:startOk', function(spotId)
    if pendingStart == spotId then pendingStart = true end
end)

local function runSet(spotId)
    local sp = SPOTS[spotId]
    local W = Config.Workout
    local ped = PlayerPedId()

    if sp.heading then SetEntityHeading(ped, sp.heading + 0.0) end
    ClearPedTasksImmediately(ped)
    startAnim(ped, sp)

    SendNUIMessage({ action = 'hud', show = true, label = sp.label, stat = sp.stat, reps = W.reps })
    Wait(900)   -- let the animation get going

    local good, perfect, cancelled = 0, 0, false
    for rep = 1, W.reps do
        local half = W.zoneSize / 2
        local center = 0.25 + math.random() * 0.6
        if center + half > 0.97 then center = 0.97 - half end
        SendNUIMessage({ action = 'rep', rep = rep, center = center, zone = W.zoneSize, perfect = W.perfectSize, time = W.repTime })

        local t0 = GetGameTimer()
        local result = 'miss'
        while true do
            Wait(0)
            DisableControlAction(0, W.pushKey, true)   -- no jumping out of the set
            local pos = (GetGameTimer() - t0) / W.repTime
            if IsDisabledControlJustPressed(0, W.pushKey) then
                local off = math.abs(pos - center)
                if off <= W.perfectSize / 2 then result = 'perfect'
                elseif off <= half then result = 'good' end
                break
            end
            if IsControlJustPressed(0, W.cancelKey) or IsEntityDead(ped) or IsPedRagdoll(ped) then
                cancelled = true
                break
            end
            if pos >= 1.0 then break end
        end
        if cancelled then break end

        if result ~= 'miss' then good = good + 1 end
        if result == 'perfect' then perfect = perfect + 1 end
        SendNUIMessage({ action = 'repResult', rep = rep, result = result, good = good })
        -- finish the rep's time so a set always takes the same time
        local rest = W.repTime - (GetGameTimer() - t0)
        Wait(math.max(200, rest))
    end

    cleanupProps(ped, 3.0, false)
    ClearPedTasks(ped)
    if sp.animDict then RemoveAnimDict(sp.animDict) end

    if cancelled then
        SendNUIMessage({ action = 'hud', show = false })
        TriggerServerEvent('ms_gym:cancel')
        notify('Set stopped early.', 'warning')
    else
        TriggerServerEvent('ms_gym:finish', good, perfect)
    end
end

RegisterNetEvent('ms_gym:result', function(r)
    SendNUIMessage({ action = 'result', result = r })
end)

local function tryWorkout(spotId)
    if working then return end
    working = true
    hidePrompt()
    pendingStart = spotId
    TriggerServerEvent('ms_gym:start', spotId)
    local t = GetGameTimer() + 4000
    while pendingStart == spotId and GetGameTimer() < t do Wait(25) end
    if pendingStart == true then runSet(spotId) end
    pendingStart = nil
    working = false
end

-- ------------------------------------------------------------
--  Main loop: trainer prompt (no target) + station markers
-- ------------------------------------------------------------
CreateThread(function()
    local T = Config.Trainer
    local tc = vector3(T.coords.x, T.coords.y, T.coords.z)
    local M = Config.Marker
    while true do
        local sleep = 1000
        local pos = GetEntityCoords(PlayerPedId())
        local shown = nil

        if not working and not menuOpen then
            -- trainer
            if not usingTarget then
                local d = #(pos - tc)
                if d < 10.0 then sleep = 0 end
                if d < 2.2 then
                    shown = 'trainer'
                    showPrompt('trainer', 'E', 'Talk to the trainer')
                    if IsControlJustReleased(0, Config.InteractKey) then openMenu(true) end
                end
            end

            -- stations (only with a membership)
            if canTrain() then
                for id, sp in ipairs(SPOTS) do
                    local d = #(pos - sp.coords)
                    if d < Config.DrawDistance then
                        sleep = 0
                        DrawMarker(M.type, sp.coords.x, sp.coords.y, sp.coords.z - 0.97, 0, 0, 0, 0, 0, 0,
                            M.size.x, M.size.y, M.size.z, M.color.r, M.color.g, M.color.b, M.color.a,
                            false, false, 2, false, nil, nil, false)
                        if d < Config.InteractDistance and not shown then
                            shown = 'spot' .. id
                            local icon = sp.stat == 'strength' and 'Strength' or 'Stamina'
                            showPrompt(shown, 'E', ('%s  -  %s'):format(sp.label, icon))
                            if IsControlJustReleased(0, Config.InteractKey) then
                                CreateThread(function() tryWorkout(id) end)
                            end
                        end
                    end
                end
            end
        end

        if not shown then hidePrompt() end
        Wait(sleep)
    end
end)

-- ------------------------------------------------------------
--  Commands + cleanup
-- ------------------------------------------------------------
RegisterCommand('gymstats', function() openMenu(false) end, false)
RegisterCommand('gympass', function() openMenu(false) end, false)

RegisterCommand('gymcoords', function()
    local p = GetEntityCoords(PlayerPedId())
    print(('[muscle_sands_gym] vector3(%.2f, %.2f, %.2f)  heading %.1f'):format(p.x, p.y, p.z, GetEntityHeading(PlayerPedId())))
    notify('Coords printed to F8.', 'inform')
end, false)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if trainer and DoesEntityExist(trainer) then DeleteEntity(trainer) end
    if menuOpen then SetNuiFocus(false, false) end
    if working then ClearPedTasks(PlayerPedId()) end
end)
