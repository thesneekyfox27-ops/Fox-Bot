-- ===== SAFETY NET: if config.lua is missing/broken, use defaults =====
if Config == nil then
    print('^1[clipboard_rentals] WARNING: config.lua is missing or broken! Using built-in defaults (airport location). Restore your config.lua!^7')
    Config = {
        Framework = 'auto', Target = 'none', Currency = '$',
        InteractKey = 38, InteractDistance = 2.2,
        PapersCommand = 'papers', PapersKey = '',
        Blip = { enabled = true, sprite = 326, color = 27, scale = 0.75, label = 'Car Rentals' },
        Locations = {
            {
                ped = vector4(-1037.91, -2737.32, 20.17, 327.0),
                spawnPoints = {
                    vector4(-1031.83, -2731.45, 20.07, 240.0),
                    vector4(-1028.92, -2726.84, 20.07, 240.0),
                },
            },
        },
        PedModel = 'a_m_y_business_01', PedScenario = 'WORLD_HUMAN_CLIPBOARD',
        ReturnRadius = 30.0,
        DepositRefundPct = 0.75, DamagePenalty = true, MaxActiveRentals = 1,
        Contract = { enabled = true, requireAgree = true, requireSignature = true, mustMatchName = true, company = 'Clipboard Rentals LLC', terms = {} },
        TempRegistration = { enabled = true, minutes = 60, notifyOnExpire = true, authority = 'Los Santos DMV' },
        Vehicles = {
            { model = 'panto',  label = 'Panto',  category = 'Economy', price = 50,  deposit = 50,  desc = 'Technically a car.' },
            { model = 'blista', label = 'Blista', category = 'Economy', price = 75,  deposit = 75,  desc = 'Cheap and cheerful.' },
            { model = 'faggio', label = 'Faggio', category = 'Bikes',   price = 30,  deposit = 30,  desc = 'Maximum style. Minimum speed.' },
        },
    }
end

local rentalPeds = {}        -- [locIndex] = ped handle
local rentalVehicle = nil
local activeRental = nil
local uiOpen = false
local docsOpen = false
local targetSystem = 'none'
local papers = { contract = nil, registration = nil }
local expiryNotified = false

-- ===================== HELPERS =====================
local function loadModel(model)
    local hash = type(model) == 'string' and joaat(model) or model
    if not IsModelValid(hash) then return nil end
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(10) end
    return HasModelLoaded(hash) and hash or nil
end

local function nearestLocation(pos)
    local best, bestDist = nil, math.huge
    for i, loc in ipairs(Config.Locations) do
        local d = #(pos - vector3(loc.ped.x, loc.ped.y, loc.ped.z))
        if d < bestDist then best, bestDist = i, d end
    end
    return best, bestDist
end

-- ===================== TARGET =====================
local function detectTarget()
    local mode = Config.Target or 'auto'
    if mode == 'ox' or (mode == 'auto' and GetResourceState('ox_target') == 'started') then
        return 'ox'
    elseif mode == 'qb' or (mode == 'auto' and GetResourceState('qb-target') == 'started') then
        return 'qb'
    end
    return 'none'
end

local function setupTarget(ped)
    if targetSystem == 'ox' then
        local ok, err = pcall(function()
            exports.ox_target:addLocalEntity(ped, {
                {
                    name = 'clipboard_rentals_browse_' .. tostring(ped),
                    icon = 'fa-solid fa-clipboard-list',
                    label = 'Browse rentals',
                    distance = 2.5,
                    canInteract = function() return activeRental == nil end,
                    onSelect = function() OpenRentalUI() end
                },
                {
                    name = 'clipboard_rentals_return_' .. tostring(ped),
                    icon = 'fa-solid fa-key',
                    label = 'Return rental vehicle',
                    distance = 2.5,
                    canInteract = function() return activeRental ~= nil end,
                    onSelect = function() TryReturnVehicle() end
                },
                {
                    name = 'clipboard_rentals_papers_' .. tostring(ped),
                    icon = 'fa-solid fa-file-contract',
                    label = 'View rental papers',
                    distance = 2.5,
                    canInteract = function() return papers.contract ~= nil end,
                    onSelect = function() OpenPapers() end
                }
            })
        end)
        if not ok then
            targetSystem = 'none'
            print('[clipboard_rentals] ox_target setup failed, using E key: ' .. tostring(err))
        end
    elseif targetSystem == 'qb' then
        local ok, err = pcall(function()
            exports['qb-target']:AddTargetEntity(ped, {
                options = {
                    {
                        icon = 'fa-solid fa-clipboard-list',
                        label = 'Browse rentals',
                        canInteract = function() return activeRental == nil end,
                        action = function() OpenRentalUI() end
                    },
                    {
                        icon = 'fa-solid fa-key',
                        label = 'Return rental vehicle',
                        canInteract = function() return activeRental ~= nil end,
                        action = function() TryReturnVehicle() end
                    },
                    {
                        icon = 'fa-solid fa-file-contract',
                        label = 'View rental papers',
                        canInteract = function() return papers.contract ~= nil end,
                        action = function() OpenPapers() end
                    }
                },
                distance = 2.5
            })
        end)
        if not ok then
            targetSystem = 'none'
            print('[clipboard_rentals] qb-target setup failed, using E key: ' .. tostring(err))
        end
    end
end

-- ===================== PED + BLIP SPAWN =====================
local function spawnPedAt(locIndex)
    local loc = Config.Locations[locIndex]
    local hash = loadModel(Config.PedModel)
    if not hash then
        print('[clipboard_rentals] could not load ped model: ' .. tostring(Config.PedModel))
        return
    end
    local ped = CreatePed(4, hash, loc.ped.x, loc.ped.y, loc.ped.z - 1.0, loc.ped.w, false, true)
    if not DoesEntityExist(ped) then
        print(('[clipboard_rentals] CreatePed failed at location %d, will retry'):format(locIndex))
        return
    end
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)
    TaskStartScenarioInPlace(ped, Config.PedScenario, 0, true)
    SetModelAsNoLongerNeeded(hash)
    setupTarget(ped)
    rentalPeds[locIndex] = ped
    print(('[clipboard_rentals] ped spawned at location %d'):format(locIndex))
end

CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(500) end

    targetSystem = detectTarget()
    print('[clipboard_rentals] target system: ' .. targetSystem)

    if Config.Blip.enabled then
        for _, loc in ipairs(Config.Locations) do
            local blip = AddBlipForCoord(loc.ped.x, loc.ped.y, loc.ped.z)
            SetBlipSprite(blip, Config.Blip.sprite)
            SetBlipColour(blip, Config.Blip.color)
            SetBlipScale(blip, Config.Blip.scale)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(Config.Blip.label)
            EndTextCommandSetBlipName(blip)
        end
    end

    -- Watchdog: keep every location's ped alive
    while true do
        for i = 1, #Config.Locations do
            if not rentalPeds[i] or not DoesEntityExist(rentalPeds[i]) then
                spawnPedAt(i)
            end
        end
        Wait(10000)
    end
end)

-- ===================== E-KEY INTERACTION (styled prompt) =====================
local promptShown = false

local function showPrompt(text)
    if not promptShown then
        promptShown = true
        SendNUIMessage({ action = 'prompt', show = true, text = text })
    end
end

local function hidePrompt()
    if promptShown then
        promptShown = false
        SendNUIMessage({ action = 'prompt', show = false })
    end
end

CreateThread(function()
    while true do
        local sleep = 1000
        if targetSystem == 'none' and not uiOpen and not docsOpen then
            local pos = GetEntityCoords(PlayerPedId())
            local _, dist = nearestLocation(pos)
            if dist and dist < Config.InteractDistance then
                sleep = 0
                showPrompt(activeRental and 'Return rental vehicle' or 'Browse rentals')
                if IsControlJustReleased(0, Config.InteractKey) then
                    hidePrompt()
                    if activeRental then TryReturnVehicle() else OpenRentalUI() end
                end
            else
                hidePrompt()
                if dist and dist < 20.0 then sleep = 250 end
            end
        else
            hidePrompt()
        end
        Wait(sleep)
    end
end)

-- ===================== NUI: RENTAL BROWSER =====================
local uiConfirmed = false

RegisterNetEvent('clipboard_rentals:client:signerName', function(name, required)
    SendNUIMessage({ action = 'signerName', name = name, required = required })
end)

function OpenRentalUI()
    TriggerServerEvent('clipboard_rentals:server:getSignerName')
    local ok, err = pcall(function()
        uiOpen = true
        uiConfirmed = false
        SetNuiFocus(true, true)
        SendNUIMessage({
            action = 'open',
            vehicles = Config.Vehicles,
            currency = Config.Currency,
            refundPct = math.floor((Config.DepositRefundPct or 0.75) * 100),
            contract = {
                enabled = Config.Contract and Config.Contract.enabled or false,
                requireAgree = Config.Contract and Config.Contract.requireAgree or false,
                requireSignature = Config.Contract and Config.Contract.requireSignature or false,
                company = Config.Contract and Config.Contract.company or 'Clipboard Rentals LLC',
                terms = Config.Contract and Config.Contract.terms or {},
                duration = Config.TempRegistration and Config.TempRegistration.minutes or 60,
            }
        })
    end)
    if not ok then
        uiOpen = false
        SetNuiFocus(false, false)
        print('[clipboard_rentals] OpenRentalUI error: ' .. tostring(err))
        return
    end

    Citizen.SetTimeout(2000, function()
        if uiOpen and not uiConfirmed then
            uiOpen = false
            SetNuiFocus(false, false)
            print('[clipboard_rentals] NUI did not respond - check F8 for js errors')
        end
    end)
end

-- ===================== NUI: PAPERS =====================
function OpenPapers()
    if not papers.contract then
        Notify('You have no active rental papers.', 'error')
        return
    end
    docsOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openPapers',
        contract = papers.contract,
        registration = papers.registration,
        currency = Config.Currency,
    })
end

RegisterCommand(Config.PapersCommand or 'papers', function()
    OpenPapers()
end, false)

-- Opening the papers via the inventory item. The item carries its own data in
-- metadata, so it works even after a relog when session papers are gone.
-- ox_inventory triggers this locally (items.lua client.event); qb-inventory
-- triggers it from the server (CreateUseableItem). One handler covers both.
local function buildTermsFromConfig()
    local out = {}
    local company = (Config.Contract and Config.Contract.company) or 'Clipboard Rentals LLC'
    local minutes = (Config.TempRegistration and Config.TempRegistration.minutes) or 60
    for _, t in ipairs((Config.Contract and Config.Contract.terms) or {}) do
        out[#out + 1] = tostring(t):gsub('{company}', company):gsub('{duration}', tostring(minutes))
    end
    return out
end

RegisterNetEvent('clipboard_rentals:client:usePapers', function(data)
    local meta = data and (data.metadata or data.info or data) or nil
    if type(meta) == 'table' and meta.plate then
        local contract = {
            company = meta.company, id = meta.id, holder = meta.holder,
            vehicle = meta.vehicle, plate = meta.plate, price = meta.price,
            deposit = meta.deposit, currency = meta.currency, signature = meta.signature,
            issuedAt = meta.issuedAt, terms = buildTermsFromConfig(),
        }
        local registration = nil
        if meta.regNumber then
            registration = {
                regNumber = meta.regNumber, authority = meta.authority, holder = meta.holder,
                vehicle = meta.vehicle, plate = meta.plate, issuedAt = meta.issuedAt,
                expiresAt = meta.expiresAt, minutes = meta.minutes,
            }
        end
        docsOpen = true
        SetNuiFocus(true, true)
        SendNUIMessage({ action = 'openPapers', contract = contract, registration = registration, currency = Config.Currency })
    else
        OpenPapers() -- fall back to synced session papers
    end
end)

if Config.PapersKey and Config.PapersKey ~= '' then
    RegisterKeyMapping(Config.PapersCommand or 'papers', 'Show rental papers', 'keyboard', Config.PapersKey)
end

-- ===================== NUI CALLBACKS =====================
RegisterNUICallback('pageLoaded', function(_, cb)
    print('[clipboard_rentals] NUI page loaded OK')
    cb('ok')
end)

RegisterNUICallback('uiReady', function(_, cb)
    uiConfirmed = true
    cb('ok')
end)

RegisterNUICallback('close', function(_, cb)
    uiOpen = false
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('closePapers', function(_, cb)
    docsOpen = false
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('rent', function(data, cb)
    uiOpen = false
    SetNuiFocus(false, false)
    if data and data.model then
        TriggerServerEvent('clipboard_rentals:requestRent', data.model, data.signature)
    end
    cb('ok')
end)

-- ===================== VEHICLE KEYS (client-side) =====================
local function detectKeySystem()
    if GetResourceState('qbx_vehiclekeys') == 'started' then return 'qbx' end
    if GetResourceState('wasabi_carlock') == 'started' then return 'wasabi' end
    if GetResourceState('MrNewbVehicleKeys') == 'started' then return 'mrnewb' end
    if GetResourceState('qs-vehiclekeys') == 'started' then return 'qs' end
    if GetResourceState('Renewed-Vehiclekeys') == 'started' then return 'renewed' end
    if GetResourceState('0r-vehiclekeys') == 'started' then return '0r' end
    if GetResourceState('qb-vehiclekeys') == 'started' then return 'qb' end
    return 'qb' -- sensible QBCore default
end

local function resolveKeySystem()
    local sys = (Config.VehicleKeys and Config.VehicleKeys.system) or 'auto'
    if sys == 'auto' then sys = detectKeySystem() end
    return sys
end

local function keysDebug(msg)
    if Config.VehicleKeys and Config.VehicleKeys.debug then
        print('[clipboard_rentals][keys] ' .. msg)
    end
end

function GiveVehicleKeys(veh, plate)
    if not (Config.VehicleKeys and Config.VehicleKeys.enabled) then return end
    local sys = resolveKeySystem()
    keysDebug(('giving keys via "%s" for plate %s'):format(sys, tostring(plate)))
    local ok, err = pcall(function()
        if sys == 'qb' then
            TriggerEvent('vehiclekeys:client:SetOwner', plate)
        elseif sys == 'qbx' then
            exports.qbx_vehiclekeys:GiveKeys(veh, plate)
        elseif sys == 'wasabi' then
            exports.wasabi_carlock:GiveKey(plate)
        elseif sys == 'mrnewb' then
            exports.MrNewbVehicleKeys:GiveKeys(plate)
        elseif sys == 'qs' then
            exports['qs-vehiclekeys']:GiveKeys(plate)
        elseif sys == 'renewed' then
            exports['Renewed-Vehiclekeys']:addKey(plate)
        elseif sys == '0r' then
            exports['0r-vehiclekeys']:GiveKeys(plate)
        elseif sys == 'custom' then
            -- >>> PUT YOUR KEYS CALL HERE <<<
            -- example: exports['my-keys']:GiveKeys(plate)
        end
    end)
    if not ok then keysDebug('give FAILED: ' .. tostring(err) .. ' (check the system name / export)') end
end

function RemoveVehicleKeys(veh, plate)
    if not (Config.VehicleKeys and Config.VehicleKeys.enabled) then return end
    local sys = resolveKeySystem()
    pcall(function()
        if sys == 'qbx' then
            exports.qbx_vehiclekeys:RemoveKeys(veh, plate)
        elseif sys == 'wasabi' then
            exports.wasabi_carlock:RemoveKey(plate)
        elseif sys == 'mrnewb' then
            exports.MrNewbVehicleKeys:RemoveKeys(plate)
        elseif sys == 'qs' then
            exports['qs-vehiclekeys']:RemoveKeys(plate)
        elseif sys == 'renewed' then
            exports['Renewed-Vehiclekeys']:removeKey(plate)
        elseif sys == '0r' then
            exports['0r-vehiclekeys']:RemoveKeys(plate)
        end
        -- 'qb'/'custom': keys are tied to the plate; deleting the car on return
        -- makes the plate meaningless, so no explicit removal is needed.
    end)
end

-- ===================== VEHICLE SPAWN =====================
local function findFreeSpawn()
    local pos = GetEntityCoords(PlayerPedId())
    local locIndex = nearestLocation(pos) or 1
    local points = Config.Locations[locIndex].spawnPoints
    for _, sp in ipairs(points) do
        if not IsPositionOccupied(sp.x, sp.y, sp.z, 3.0, false, true, true, false, false, 0, false) then
            return sp
        end
    end
    return points[1]
end

RegisterNetEvent('clipboard_rentals:spawnVehicle', function(model, plate)
    local hash = loadModel(model)
    if not hash then return end

    local sp = findFreeSpawn()
    local veh = CreateVehicle(hash, sp.x, sp.y, sp.z, sp.w, true, false)
    SetVehicleNumberPlateText(veh, plate)
    SetVehicleOnGroundProperly(veh)
    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleFuelLevel(veh, 100.0)
    SetVehRadioStation(veh, 'OFF')
    SetModelAsNoLongerNeeded(hash)

    TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)

    -- Hand over keys client-side, now that the vehicle physically exists.
    GiveVehicleKeys(veh, plate)

    rentalVehicle = veh
    activeRental = { model = model, plate = plate }
    expiryNotified = false
end)

-- ===================== RETURN =====================
function TryReturnVehicle()
    if not activeRental then return end

    if not rentalVehicle or not DoesEntityExist(rentalVehicle) then
        TriggerServerEvent('clipboard_rentals:returnVehicle', 0.0)
        activeRental = nil
        rentalVehicle = nil
        return
    end

    local vehPos = GetEntityCoords(rentalVehicle)
    local _, dist = nearestLocation(vehPos)
    if not dist or dist > Config.ReturnRadius then
        Notify('Bring the vehicle back to a rental lot first.', 'error')
        return
    end

    local engine = GetVehicleEngineHealth(rentalVehicle)
    local body = GetVehicleBodyHealth(rentalVehicle)
    local healthPct = math.min(engine, body) / 1000.0
    if healthPct < 0 then healthPct = 0 end

    TriggerServerEvent('clipboard_rentals:returnVehicle', healthPct)
    RemoveVehicleKeys(rentalVehicle, activeRental and activeRental.plate)
    DeleteEntity(rentalVehicle)
    rentalVehicle = nil
    activeRental = nil
end

-- ===================== NOTIFY / SYNC =====================
function Notify(msg, ntype)
    SendNUIMessage({ action = 'notify', message = msg, type = ntype or 'info' })
end

RegisterNetEvent('clipboard_rentals:notify', function(msg, ntype)
    Notify(msg, ntype)
end)

RegisterNetEvent('clipboard_rentals:syncRental', function(rental)
    activeRental = rental
end)

RegisterNetEvent('clipboard_rentals:setPapers', function(contract, registration)
    papers.contract = contract
    papers.registration = registration
    expiryNotified = false
    -- If the papers window is open, push the fresh copy through.
    if docsOpen then
        SendNUIMessage({
            action = 'openPapers',
            contract = papers.contract,
            registration = papers.registration,
            currency = Config.Currency,
        })
    end
end)

CreateThread(function()
    Wait(2000)
    TriggerServerEvent('clipboard_rentals:syncRequest')
end)

-- ===================== PERMIT EXPIRY WATCH =====================
CreateThread(function()
    while true do
        Wait(5000)
        if papers.registration and not expiryNotified
           and Config.TempRegistration and Config.TempRegistration.notifyOnExpire then
            local now = GetCloudTimeAsInt()   -- client-safe epoch (os.* is server-only)
            if now > 0 then
                local remaining = (papers.registration.expiresAt or 0) - now
                if remaining <= 0 then
                    expiryNotified = true
                    Notify('Your temporary operating permit has expired. Renew or return the vehicle.', 'error')
                end
            end
        end
    end
end)

-- ===================== ESC ESCAPE HATCH =====================
CreateThread(function()
    while true do
        if uiOpen or docsOpen then
            DisableControlAction(0, 200, true)
            if IsDisabledControlJustReleased(0, 200) or IsControlJustReleased(0, 177) then
                if docsOpen then
                    docsOpen = false
                    SetNuiFocus(false, false)
                    SendNUIMessage({ action = 'forceClosePapers' })
                elseif uiOpen then
                    uiOpen = false
                    SetNuiFocus(false, false)
                    SendNUIMessage({ action = 'forceClose' })
                end
            end
            Wait(0)
        else
            Wait(500)
        end
    end
end)
