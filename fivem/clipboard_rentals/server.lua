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
        VehicleKeys = { enabled = true, system = 'auto', debug = true },
        Vehicles = {
            { model = 'panto',  label = 'Panto',  category = 'Economy', price = 50,  deposit = 50,  desc = 'Technically a car.' },
            { model = 'blista', label = 'Blista', category = 'Economy', price = 75,  deposit = 75,  desc = 'Cheap and cheerful.' },
            { model = 'faggio', label = 'Faggio', category = 'Bikes',   price = 30,  deposit = 30,  desc = 'Maximum style. Minimum speed.' },
        },
    }
end

local ESX, QBCore = nil, nil
local Framework = 'standalone'

-- Active rentals: [src] = { model, label, plate, deposit, price, contract, registration }
local Rentals = {}

CreateThread(function()
    if Config.Framework == 'esx' or (Config.Framework == 'auto' and GetResourceState('es_extended') == 'started') then
        ESX = exports['es_extended']:getSharedObject()
        Framework = 'esx'
    elseif Config.Framework == 'qb' or (Config.Framework == 'auto' and GetResourceState('qb-core') == 'started') then
        QBCore = exports['qb-core']:GetCoreObject()
        Framework = 'qb'
    end
    print(('[clipboard_rentals] running in %s mode'):format(Framework))

    -- Make the registration papers item open the viewer (qb-inventory path).
    -- ox_inventory uses a client.event in its items.lua instead (see README).
    if Framework == 'qb' and Config.PaperItem and Config.PaperItem.enabled and QBCore then
        QBCore.Functions.CreateUseableItem(Config.PaperItem.name or 'rental_papers', function(source, item)
            TriggerClientEvent('clipboard_rentals:client:usePapers', source, item and item.info or nil)
        end)
    end
end)

-- ===================== MONEY HELPERS =====================
local function removeMoney(src, amount)
    if Framework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer and xPlayer.getMoney() >= amount then
            xPlayer.removeMoney(amount)
            return true
        end
        return false
    elseif Framework == 'qb' then
        local Player = QBCore.Functions.GetPlayer(src)
        if not Player then return false end
        -- Return value check (not a balance pre-check) so money-as-item
        -- systems like SA-Money-v2 that hook RemoveMoney work correctly.
        return Player.Functions.RemoveMoney('cash', amount, 'car-rental') and true or false
    end
    return true
end

local function addMoney(src, amount)
    if amount <= 0 then return end
    if Framework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer then xPlayer.addMoney(amount) end
    elseif Framework == 'qb' then
        local Player = QBCore.Functions.GetPlayer(src)
        if Player then Player.Functions.AddMoney('cash', amount, 'rental-refund') end
    end
end

-- ===================== IDENTITY HELPER =====================
local function getCharName(src)
    if Framework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer then
            local n = xPlayer.getName and xPlayer.getName() or nil
            if n and n ~= '' then return n end
        end
    elseif Framework == 'qb' then
        local Player = QBCore.Functions.GetPlayer(src)
        if Player and Player.PlayerData and Player.PlayerData.charinfo then
            local ci = Player.PlayerData.charinfo
            return (('%s %s'):format(ci.firstname or '', ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
        end
    end
    local n = GetPlayerName(src)
    return n and n or 'Renter'
end

-- "Bob  Myers", "bob myers", "Bob Myers." all count as the same name
local function normName(s)
    s = tostring(s or ''):lower():gsub("[^%a%s'%-]", ''):gsub('%s+', ' ')
    return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function mustMatchName()
    return Config.Contract and Config.Contract.mustMatchName ~= false
end

-- the client asks for the name the renter has to sign with
RegisterNetEvent('clipboard_rentals:server:getSignerName', function()
    local src = source
    TriggerClientEvent('clipboard_rentals:client:signerName', src,
        getCharName(src), mustMatchName() and Config.Contract and Config.Contract.requireSignature or false)
end)

-- ===================== HELPERS =====================
local function findVehicleConfig(model)
    for _, v in ipairs(Config.Vehicles) do
        if v.model == model then return v end
    end
    return nil
end

local function randId(prefix, len)
    local chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ0123456789'
    local out = prefix
    for _ = 1, (len or 6) do
        local i = math.random(1, #chars)
        out = out .. chars:sub(i, i)
    end
    return out
end

local function generatePlate()
    local chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    local plate = 'RNT'
    for _ = 1, 5 do
        if math.random(1, 2) == 1 then
            plate = plate .. tostring(math.random(0, 9))
        else
            local i = math.random(1, #chars)
            plate = plate .. chars:sub(i, i)
        end
    end
    return plate
end

-- Fill {company}/{duration} tokens in a term line.
local function fillToken(str, company, minutes)
    str = str:gsub('{company}', company or 'the company')
    str = str:gsub('{duration}', tostring(minutes or 0))
    return str
end

local function buildPapers(src, veh, plate)
    local now = os.time()
    local company = (Config.Contract and Config.Contract.company) or 'Clipboard Rentals LLC'
    local minutes = (Config.TempRegistration and Config.TempRegistration.minutes) or 60
    local holder = getCharName(src)

    -- Contract
    local terms = {}
    if Config.Contract and Config.Contract.terms then
        for _, t in ipairs(Config.Contract.terms) do
            terms[#terms + 1] = fillToken(t, company, minutes)
        end
    end
    local contract = {
        id = randId('CR-', 6),
        company = company,
        holder = holder,
        vehicle = veh.label,
        plate = plate,
        price = veh.price,
        deposit = veh.deposit,
        refundPct = math.floor((Config.DepositRefundPct or 0.75) * 100),
        currency = Config.Currency,
        terms = terms,
        issuedAt = now,
    }

    -- Temporary registration
    local registration = nil
    if Config.TempRegistration and Config.TempRegistration.enabled then
        registration = {
            regNumber = randId('TMP-', 6),
            authority = Config.TempRegistration.authority or 'Los Santos DMV',
            holder = holder,
            vehicle = veh.label,
            plate = plate,
            minutes = minutes,
            issuedAt = now,
            expiresAt = now + (minutes * 60),
        }
    end

    return contract, registration
end

-- ===================== INVENTORY (registration papers item) =====================
local function detectInventory()
    if GetResourceState('ox_inventory') == 'started' then return 'ox' end
    if GetResourceState('qb-inventory') == 'started' then return 'qb' end
    return Framework == 'qb' and 'qb' or 'ox'
end

local function paperInv()
    local inv = (Config.PaperItem and Config.PaperItem.inventory) or 'auto'
    if inv == 'auto' then inv = detectInventory() end
    return inv
end

local function givePaperItem(src, contract, registration)
    if not (Config.PaperItem and Config.PaperItem.enabled) then return end
    local name = Config.PaperItem.name or 'rental_papers'
    local reg = registration or {}
    local info = {
        id = contract.id, signature = contract.signature, holder = contract.holder,
        vehicle = contract.vehicle, plate = contract.plate,
        price = contract.price, deposit = contract.deposit, refundPct = contract.refundPct,
        currency = contract.currency, company = contract.company,
        regNumber = reg.regNumber, authority = reg.authority,
        issuedAt = contract.issuedAt, expiresAt = reg.expiresAt, minutes = reg.minutes,
        description = ('%s — plate %s'):format(contract.vehicle or 'Rental', contract.plate or ''),
    }
    local inv = paperInv()
    if inv == 'ox' then
        pcall(function() exports.ox_inventory:AddItem(src, name, 1, info) end)
    elseif inv == 'qb' then
        local Player = QBCore and QBCore.Functions.GetPlayer(src)
        if Player then pcall(function() Player.Functions.AddItem(name, 1, false, info) end) end
    end
end

local function removePaperItem(src)
    if not (Config.PaperItem and Config.PaperItem.enabled and Config.PaperItem.removeOnReturn) then return end
    local name = Config.PaperItem.name or 'rental_papers'
    local inv = paperInv()
    if inv == 'ox' then
        pcall(function() exports.ox_inventory:RemoveItem(src, name, 1) end)
    elseif inv == 'qb' then
        local Player = QBCore and QBCore.Functions.GetPlayer(src)
        if Player then pcall(function() Player.Functions.RemoveItem(name, 1) end) end
    end
end

-- ===================== EVENTS =====================
RegisterNetEvent('clipboard_rentals:requestRent', function(model, signature)
    local src = source
    if Rentals[src] then
        TriggerClientEvent('clipboard_rentals:notify', src, 'You already have a rental out. Return it first.', 'error')
        return
    end

    local veh = findVehicleConfig(model)
    if not veh then
        TriggerClientEvent('clipboard_rentals:notify', src, 'That vehicle is not in our fleet.', 'error')
        return
    end

    -- Server-side contract validation (never trust the client).
    if Config.Contract and Config.Contract.enabled and Config.Contract.requireSignature then
        signature = type(signature) == 'string' and signature:gsub('^%s+', ''):gsub('%s+$', '') or ''
        if signature == '' then
            TriggerClientEvent('clipboard_rentals:notify', src, 'You must sign the rental agreement first.', 'error')
            return
        end
        if #signature > 32 then signature = signature:sub(1, 32) end

        -- must be the character's real name, not a made up one
        if mustMatchName() then
            local real = getCharName(src)
            if normName(signature) ~= normName(real) then
                TriggerClientEvent('clipboard_rentals:notify', src,
                    ('Sign with your real name: %s'):format(real), 'error')
                return
            end
            signature = real
        end
    else
        signature = getCharName(src)
    end

    local total = veh.price + veh.deposit
    if not removeMoney(src, total) then
        TriggerClientEvent('clipboard_rentals:notify', src, ('You need %s%d in cash (fee + deposit).'):format(Config.Currency, total), 'error')
        return
    end

    local plate = generatePlate()
    local contract, registration = buildPapers(src, veh, plate)
    contract.signature = signature

    Rentals[src] = {
        model = veh.model, label = veh.label, plate = plate,
        deposit = veh.deposit, price = veh.price,
        contract = contract, registration = registration,
    }

    TriggerClientEvent('clipboard_rentals:spawnVehicle', src, veh.model, plate)
    TriggerClientEvent('clipboard_rentals:setPapers', src, contract, registration)
    givePaperItem(src, contract, registration)

    TriggerClientEvent('clipboard_rentals:notify', src,
        ('Rented a %s for %s%d (+%s%d deposit). Plate: %s'):format(veh.label, Config.Currency, veh.price, Config.Currency, veh.deposit, plate), 'success')
end)

RegisterNetEvent('clipboard_rentals:returnVehicle', function(healthPct)
    local src = source
    local rental = Rentals[src]
    if not rental then
        TriggerClientEvent('clipboard_rentals:notify', src, 'You have no active rental.', 'error')
        return
    end

    healthPct = math.min(math.max(tonumber(healthPct) or 0, 0), 1.0)

    local refund = math.floor(rental.deposit * Config.DepositRefundPct)
    if Config.DamagePenalty then
        refund = math.floor(refund * healthPct)
    end

    addMoney(src, refund)
    removePaperItem(src)
    Rentals[src] = nil
    TriggerClientEvent('clipboard_rentals:setPapers', src, nil, nil)

    if refund > 0 then
        TriggerClientEvent('clipboard_rentals:notify', src,
            ('%s returned. Deposit refund: %s%d'):format(rental.label, Config.Currency, refund), 'success')
    else
        TriggerClientEvent('clipboard_rentals:notify', src,
            ('%s returned... in that condition? No refund for you.'):format(rental.label), 'error')
    end
end)

-- Used by client to restore UI + papers state (e.g. after a resource restart).
RegisterNetEvent('clipboard_rentals:syncRequest', function()
    local src = source
    local rental = Rentals[src]
    if rental then
        TriggerClientEvent('clipboard_rentals:syncRental', src, {
            model = rental.model, plate = rental.plate, label = rental.label,
        })
        TriggerClientEvent('clipboard_rentals:setPapers', src, rental.contract, rental.registration)
    else
        TriggerClientEvent('clipboard_rentals:syncRental', src, nil)
    end
end)

AddEventHandler('playerDropped', function()
    Rentals[source] = nil
end)
