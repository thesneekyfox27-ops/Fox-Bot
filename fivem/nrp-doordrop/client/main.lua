local S = {
    phone        = 'closed', -- closed | peek | open (standalone overlay only)
    online       = false,
    offer        = nil,
    offerEnds    = 0,
    order        = nil,
    deadlineAt   = 0,
    bag          = nil, -- bag in the player's hand
    pickupProp   = nil, -- 'shelf' style: bag on the ground
    worker       = nil, -- 'employee' style: worker ped holding the bag
    workerBag    = nil,
    customer     = nil, -- NPC customer ped
    playerTarget = false,
    zone         = nil,
    blip         = nil,
    busy         = false,
    damage       = 0,
    dropped      = false,
    condition    = 100, -- food condition while carrying (0-100)
    handedOff    = false,
    photos       = {},
    lastResult   = nil,
    custStatus   = nil,
    custData     = nil, -- last customer payload (for the on-screen ETA)
    custAt       = 0,
    trackBlip    = nil, -- customer: map blip following their driver / courier
    courier      = nil, -- customer: spawned NPC courier { veh, ped, bag, blip }
}

local function notify(desc, kind)
    lib.notify({ title = Config.AppName, description = desc, type = kind or 'inform' })
end

local Phone = Config.Phone
local phoneApp = { registered = false, loaded = false }

local function phoneMode()
    return Phone.Enabled and phoneApp.registered and GetResourceState(Phone.Resource) == 'started'
end

-- Every message goes to our own page (flash overlay + standalone fallback) and,
-- when the 17mov app is installed, into the app's iframe as well.
local function nui(action, data)
    SendNUIMessage({ action = action, data = data })
    if phoneMode() and phoneApp.loaded then
        pcall(function()
            exports[Phone.Resource]:SendAppMessage(Phone.AppName, { action = action, payload = data })
        end)
    end
end

-- Offer ringtone, played by our own page so it works whether the phone is open or not
local function playRing()
    local snd = Config.Sounds and Config.Sounds.offer
    if not snd or not snd.enabled or not snd.file then
        return PlaySoundFrontend(-1, 'Text_Arrive_Tone', 'Phone_SoundSet_Default', true)
    end
    SendNUIMessage({ action = 'sound', data = { file = snd.file, volume = snd.volume or 0.45, loop = snd.loop == true } })
end

local function stopRing()
    SendNUIMessage({ action = 'sound', data = { stop = true } })
end

-- Phone notification when the phone app is in use, ox_lib otherwise.
local function alert(title, message)
    if phoneMode() then
        local ok = pcall(function()
            local ph = exports[Phone.Resource]
            ph:CreateNotification({ number = ph:GetPlayerNumber(), app = Phone.AppName, title = title, message = message, data = { alwaysShow = true } })
        end)
        if ok then return end
    end
    notify(message)
end

-- vectors don't belong in NUI; send a clean copy
local function toNui(o)
    if not o then return nil end
    local left = S.order == o and math.floor((S.deadlineAt - GetGameTimer()) / 1000) or o.deadlineIn
    return {
        id = o.id, miles = o.miles, base = o.base, tip = o.tip, total = o.total, bigTip = o.bigTip,
        faceToFace = o.faceToFace, items = o.items, eta = o.eta, stage = o.stage, deadlineIn = left,
        player = o.player, customerName = o.customerName,
        restaurant = { label = o.restaurant.label, area = o.restaurant.area, category = o.restaurant.category,
                       x = o.restaurant.pickup.x, y = o.restaurant.pickup.y },
        dropoff = { label = o.dropoff.label, area = o.dropoff.area, x = o.dropoff.door.x, y = o.dropoff.door.y },
    }
end

local function bagCfg()
    return (S.order and Config.Bags[S.order.restaurant.bag]) or Config.Bags.bag
end

---------------------------------------------------------------------
-- Phone
---------------------------------------------------------------------
local function registerPhoneApp()
    if not Phone.Enabled or GetResourceState(Phone.Resource) ~= 'started' then return end
    local res = GetCurrentResourceName()
    local ok, err = pcall(function()
        exports[Phone.Resource]:AddApplication({
            name           = Phone.AppName,
            label          = Phone.Label,
            ui             = ('https://cfx-nui-%s/html/phone.html'):format(res),
            icon           = ('https://cfx-nui-%s/html/icon.svg'):format(res),
            iconBackground = Phone.IconBackground,
            default        = Phone.Default,
            preInstalled   = Phone.PreInstalled,
            resourceName   = res,
            rating         = Phone.Rating,
            job            = Phone.Job,
        })
    end)
    phoneApp.registered = ok
    if not ok then
        print(('^3[nrp-doordrop]^7 Could not add the app to %s, using the standalone phone. (%s)'):format(Phone.Resource, err))
    end
end

CreateThread(registerPhoneApp)
RegisterNetEvent('17mov_Phone:Client:Ready', registerPhoneApp)

local function nuiConfig()
    nui('config', {
        app = Config.AppName, key = Config.OpenKey, imagePath = Config.ItemImage, ordering = Config.Customer.enabled,
        lateCancelRefund = Config.Customer.lateCancelRefund or 0,
        map = Config.MiniMap.enabled and { image = Config.MiniMap.image, bounds = Config.MiniMap.bounds } or nil,
        hud = Config.Hud,
        offerWait = {
            min = Config.Offer.waitMin, max = Config.Offer.waitMax,
            inside = Config.HotZones.enabled and Config.HotZones.insideWaitMult or 1.0,
            outside = Config.HotZones.enabled and Config.HotZones.outsideWaitMult or 1.0,
        },
    })
end

local function syncPayload()
    return {
        snapshot   = lib.callback.await('nrp-doordrop:getState', false),
        offer      = S.offer and toNui(S.offer) or nil,
        offerLeft  = S.offer and math.max(0, math.floor((S.offerEnds - GetGameTimer()) / 1000)) or nil,
        offerTotal = Config.Offer.timeout,
        order      = S.order and toNui(S.order) or nil,
        result     = S.lastResult,
        photos     = S.photos,
    }
end

local function setPhone(mode)
    if phoneMode() then mode = 'closed' end -- the 17mov phone owns focus in phone mode
    S.phone = mode
    SetNuiFocus(mode == 'open', mode == 'open')
    nuiConfig()
    nui('phone', { mode = mode })
end

local function openPhone()
    if phoneMode() then
        local ph = exports[Phone.Resource]
        if not ph:HasPhoneItem() then return notify('You need a phone.', 'error') end
        if not ph:IsPhoneOpen() then ph:OpenPhone() Wait(300) end
        ph:OpenApp(Phone.AppName)
        return
    end
    if not Config.CanOpen() then return notify('You need a phone to open the app.', 'error') end
    nuiConfig()
    nui('sync', syncPayload())
    setPhone('open')
end

local function closePhone()
    setPhone(S.offer and 'peek' or 'closed')
end

RegisterNUICallback('appLoaded', function(_, cb)
    cb(1)
    phoneApp.loaded = true
    CreateThread(function()
        nuiConfig()
        nui('sync', syncPayload())
    end)
end)

RegisterNUICallback('dismissResult', function(_, cb)
    S.lastResult = nil
    cb(1)
end)

RegisterCommand(Config.OpenCommand, function()
    if S.phone == 'open' then closePhone() else openPhone() end
end, false)
RegisterKeyMapping(Config.OpenCommand, ('Open the %s app'):format(Config.AppName), 'keyboard', Config.OpenKey)

RegisterCommand('ddaccept', function()
    if S.offer then TriggerServerEvent('nrp-doordrop:server:respond', S.offer.id, true) end
end, false)
RegisterCommand('dddecline', function()
    if S.offer then TriggerServerEvent('nrp-doordrop:server:respond', S.offer.id, false) end
end, false)
if Config.QuickAcceptKey ~= '' then RegisterKeyMapping('ddaccept', ('%s: accept offer'):format(Config.AppName), 'keyboard', Config.QuickAcceptKey) end
if Config.QuickDeclineKey ~= '' then RegisterKeyMapping('dddecline', ('%s: decline offer'):format(Config.AppName), 'keyboard', Config.QuickDeclineKey) end

RegisterCommand(Config.DevCommand, function()
    local ped = PlayerPedId()
    local c, h = GetEntityCoords(ped), GetEntityHeading(ped)
    local str = ('vec4(%.1f, %.1f, %.1f, %.1f)'):format(c.x, c.y, c.z, h)
    print(str)
    lib.setClipboard(str)
    notify('Copied ' .. str)
end, false)

---------------------------------------------------------------------
-- World helpers
---------------------------------------------------------------------
local function clearBlip()
    if S.blip then RemoveBlip(S.blip) S.blip = nil end
end

local function setBlip(c, cfg, label)
    clearBlip()
    if Config.AutoWaypoint then SetNewWaypoint(c.x, c.y) end
    S.blip = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(S.blip, cfg.sprite)
    SetBlipColour(S.blip, cfg.color)
    SetBlipScale(S.blip, 0.85)
    SetBlipRoute(S.blip, true)
    SetBlipRouteColour(S.blip, cfg.color)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(label)
    EndTextCommandSetBlipName(S.blip)
end

local function forward(heading)
    local r = math.rad(heading)
    return vector3(-math.sin(r), math.cos(r), 0.0)
end

local function attachTo(ent, ped, cfg)
    SetEntityCollision(ent, false, false)
    AttachEntityToEntity(ent, ped, GetPedBoneIndex(ped, cfg.bone),
        cfg.pos.x, cfg.pos.y, cfg.pos.z, cfg.rot.x, cfg.rot.y, cfg.rot.z,
        true, true, false, true, 1, true)
end

local function attachBag(ent)
    attachTo(ent, PlayerPedId(), bagCfg())
    S.bag = ent
end

local function spawnBag(cfg, networked, at)
    lib.requestModel(cfg.model)
    local obj = CreateObject(joaat(cfg.model), at.x, at.y, at.z, networked, networked, false)
    SetModelAsNoLongerNeeded(joaat(cfg.model))
    return obj
end

local function stopCarryAnim(ped)
    local cfg = bagCfg()
    if cfg.anim and IsEntityPlayingAnim(ped, cfg.anim.dict, cfg.anim.clip, 3) then
        StopAnimTask(ped, cfg.anim.dict, cfg.anim.clip, 2.0)
    end
end

local function playGive(giver, taker)
    lib.requestAnimDict('mp_common')
    TaskPlayAnim(giver, 'mp_common', 'givetake1_a', 8.0, -8.0, 2000, 0, 0, false, false, false)
    if taker then TaskPlayAnim(taker, 'mp_common', 'givetake1_b', 8.0, -8.0, 2000, 0, 0, false, false, false) end
end

-- Walks a local NPC back inside and deletes it (plus anything it carries).
local function sendInside(ped, heading, extra)
    FreezeEntityPosition(ped, false)
    local inside = GetEntityCoords(ped) - forward(heading) * 3.0
    TaskGoStraightToCoord(ped, inside.x, inside.y, inside.z, 1.0, 5000, heading + 180.0, 0.1)
    SetTimeout(4500, function()
        if extra and DoesEntityExist(extra) then DeleteEntity(extra) end
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end)
end

-- Hides the bag in vehicles, plays the carry anim on foot, and tracks damage for the spill check.
-- Food condition: starts at 100 and your driving knocks it down, with an alert each time.
local DRIVE_ALERTS = {
    crash    = { 'Ouch! That hit rattled the bag.', 'Crash! Something definitely spilled.', 'You felt that. So did the food.' },
    air      = { 'Airtime! The drinks did not enjoy that.', 'Big jump. Hope the lids held.', 'The food left the seat for a second there.' },
    brake    = { 'Hard brake. Something slid across the bag.', 'Easy on the brakes, the fries are everywhere now.' },
    flip     = { 'You flipped it. That order is a mess.', 'Upside down. The customer is getting a surprise.' },
    speeding = { 'Slow down, the bag is sliding around.', "You're driving like a maniac. The food feels it.", 'Too fast! Hold on to that order.' },
    drop     = { 'You dropped the bag!', 'Whoops, the bag hit the pavement.' },
}
local lastAlert = 0

local function hit(kind, amount)
    if not S.order or S.order.stage ~= 'dropoff' then return end
    local before = S.condition
    S.condition = math.max(0, S.condition - amount)
    local lost = math.floor(before - S.condition + 0.5)
    if lost <= 0 then return end
    if GetGameTimer() - lastAlert > Config.Driving.alertCooldown * 1000 then
        lastAlert = GetGameTimer()
        local pool = DRIVE_ALERTS[kind]
        lib.notify({
            title = ('Food condition %d%%'):format(math.floor(S.condition)),
            description = pool[math.random(#pool)],
            type = S.condition < 50 and 'error' or 'warning', duration = 3500,
        })
        PlaySoundFrontend(-1, 'CHECKPOINT_MISSED', 'HUD_MINI_GAME_SOUNDSET', true)
    end
    nui('condition', { value = math.floor(S.condition) })
end

-- Hides the bag in vehicles, plays the carry anim on foot, and watches your driving.
local function carryLoop()
    CreateThread(function()
        local cfg, D = bagCfg(), Config.Driving
        local lastVeh, lastBody, lastSpeed = 0, 0.0, 0.0
        local airSince, speedSince, flipped, wasRagdoll = nil, nil, false, false
        local speedHist, lastBrake = {}, 0
        while S.bag and DoesEntityExist(S.bag) do
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)
            if veh ~= 0 then
                SetEntityVisible(S.bag, false, false)
                stopCarryAnim(ped)
                local body = GetVehicleBodyHealth(veh)
                local speed = GetEntitySpeed(veh)
                local crashed = false
                if veh == lastVeh and body < lastBody then
                    hit('crash', (lastBody - body) * D.crashPerDamage)
                    crashed = true
                end
                -- jumps
                if IsEntityInAir(veh) then
                    airSince = airSince or GetGameTimer()
                elseif airSince then
                    if GetGameTimer() - airSince > 600 then hit('air', D.airtime) end
                    airSince = nil
                end
                -- slamming the brakes (without crashing)
                -- slamming the brakes: a huge drop from real speed, no crash involved, not too often
                speedHist[#speedHist + 1] = speed
                if #speedHist > 3 then table.remove(speedHist, 1) end
                local halfSecondAgo = speedHist[1]
                if veh == lastVeh and not crashed and not HasEntityCollidedWithAnything(veh)
                    and halfSecondAgo >= D.hardBrakeFrom and halfSecondAgo - speed >= D.hardBrakeDrop
                    and GetGameTimer() - lastBrake > D.hardBrakeCooldown * 1000 then
                    lastBrake = GetGameTimer()
                    speedHist = {}
                    hit('brake', D.hardBrake)
                end
                -- rolled it
                local up = IsEntityUpsidedown(veh) or math.abs(GetEntityRoll(veh)) > 75.0
                if up and not flipped then hit('flip', D.flip) end
                flipped = up
                -- speeding
                if speed * 2.23694 > D.speedingMph then
                    speedSince = speedSince or GetGameTimer()
                    if GetGameTimer() - speedSince > 5000 then hit('speeding', D.speeding) speedSince = GetGameTimer() end
                else
                    speedSince = nil
                end
                lastVeh, lastBody, lastSpeed = veh, body, speed
            else
                lastVeh, airSince, speedSince, speedHist = 0, nil, nil, {}
                SetEntityVisible(S.bag, true, false)
                local rag = IsPedRagdoll(ped)
                if rag and not wasRagdoll then hit('drop', D.dropBag) end
                wasRagdoll = rag
                if cfg.anim and not S.busy and not IsEntityPlayingAnim(ped, cfg.anim.dict, cfg.anim.clip, 3) then
                    lib.requestAnimDict(cfg.anim.dict)
                    TaskPlayAnim(ped, cfg.anim.dict, cfg.anim.clip, 8.0, -8.0, -1, 49, 0, false, false, false)
                end
            end
            Wait(250)
        end
    end)
end

local function takePhoto(target, stage)
    local ped, pa = PlayerPedId(), Config.PhotoAnim
    TaskTurnPedToFaceCoord(ped, target.x, target.y, target.z, 700)
    Wait(700)

    lib.requestAnimDict(pa.dict)
    lib.requestModel(pa.prop)
    local phone = CreateObject(joaat(pa.prop), GetEntityCoords(ped), true, true, false)
    AttachEntityToEntity(phone, ped, GetPedBoneIndex(ped, 28422), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(joaat(pa.prop))
    TaskPlayAnim(ped, pa.dict, pa.clip, 3.0, -3.0, -1, 49, 0, false, false, false)
    Wait(1200)

    if Config.Screenshots and GetResourceState('screenshot-basic') == 'started' then
        exports['screenshot-basic']:requestScreenshot({ encoding = 'jpg', quality = 0.35 }, function(data)
            S.photos[stage] = data
            nui('photo', { stage = stage, img = data })
        end)
        Wait(250)
    else
        S.photos[stage] = true
        nui('photo', { stage = stage })
    end

    PlaySoundFrontend(-1, 'Camera_Shoot', 'Phone_Soundset_Franklin', true)
    nui('flash')
    Wait(700)
    StopAnimTask(ped, pa.dict, pa.clip, 2.0)
    DeleteEntity(phone)
end

---------------------------------------------------------------------
-- Order lifecycle
---------------------------------------------------------------------
local function removeTarget(ent)
    if ent and DoesEntityExist(ent) then exports.ox_target:removeLocalEntity(ent) end
end

local function cleanupOrder()
    clearBlip()
    if S.pickupProp then removeTarget(S.pickupProp) DeleteEntity(S.pickupProp) S.pickupProp = nil end
    if S.worker then removeTarget(S.worker) DeleteEntity(S.worker) S.worker = nil end
    if S.workerBag then DeleteEntity(S.workerBag) S.workerBag = nil end
    if S.zone then exports.ox_target:removeZone(S.zone) S.zone = nil end
    if S.customer then removeTarget(S.customer) DeleteEntity(S.customer) S.customer = nil end
    if S.playerTarget then exports.ox_target:removeGlobalPlayer('dd_handoff_player') S.playerTarget = false end
    if S.bag then
        stopCarryAnim(PlayerPedId())
        DeleteEntity(S.bag)
        S.bag = nil
    end
    S.order, S.busy = nil, false
end

local function submitDelivery()
    local res = lib.callback.await('nrp-doordrop:deliver', false, { condition = math.floor(S.condition), handedOff = S.handedOff })
    if not res or not res.ok then
        notify(res and res.reason or 'Delivery failed.', 'error')
        return nil
    end
    local r = res.result
    if r.player then
        notify(('Delivered to %s. +$%d'):format(r.customerName or 'the customer', r.total), 'success')
    else
        notify(('Delivered. +$%d (%d★)'):format(r.total, r.stars), 'success')
    end
    S.lastResult = r
    nui('delivered', r)
    nui('state', res.snapshot)
    return r
end

local startDropoff -- forward decl

local function doPickup()
    if S.busy or not S.order or S.order.stage ~= 'pickup' then return end
    local focusEnt = S.worker or S.pickupProp
    if not focusEnt then return end
    S.busy = true
    local ped = PlayerPedId()

    takePhoto(GetEntityCoords(focusEnt), 'pickup')

    local ok, reason = lib.callback.await('nrp-doordrop:pickup', false)
    if not ok then
        S.busy = false
        return notify(reason or 'Pickup failed.', 'error')
    end

    -- flip the stage first so the pickup loop can never respawn a bag
    S.order.stage = 'dropoff'

    if S.worker then
        local worker, wbag = S.worker, S.workerBag
        S.worker, S.workerBag = nil, nil
        removeTarget(worker)
        FreezeEntityPosition(worker, false)
        ClearPedTasks(worker)
        TaskTurnPedToFaceEntity(ped, worker, 600)
        TaskTurnPedToFaceEntity(worker, ped, 600)
        Wait(600)
        playGive(worker, ped)
        Wait(1100)
        if wbag and DoesEntityExist(wbag) then DeleteEntity(wbag) end
        PlayPedAmbientSpeechNative(worker, 'GENERIC_BYE', 'SPEECH_PARAMS_FORCE_NORMAL')
        sendInside(worker, S.order.restaurant.pickup.w)
    else
        lib.requestAnimDict('random@domestic')
        TaskPlayAnim(ped, 'random@domestic', 'pickup_low', 8.0, -8.0, 1200, 0, 0, false, false, false)
        Wait(700)
        removeTarget(S.pickupProp)
        DeleteEntity(S.pickupProp)
        S.pickupProp = nil
        Wait(300)
    end

    ClearPedTasks(ped)
    attachBag(spawnBag(bagCfg(), true, GetEntityCoords(ped)))

    S.condition, S.handedOff = 100, false
    nui('condition', { value = 100 })
    S.busy = false
    carryLoop()
    startDropoff()
    nui('stage', { stage = 'dropoff' })
    if S.order.player then
        notify(S.order.faceToFace and ('Picked up. Hand it to %s.'):format(S.order.customerName)
            or ('Picked up. Leave it where %s ordered from.'):format(S.order.customerName))
    else
        notify(S.order.faceToFace and 'Picked up. The customer wants it handed to them.' or 'Picked up. Leave it at the door and take a photo.')
    end
end

local function spawnPickup()
    local r, cfg = S.order.restaurant, bagCfg()
    local option = {{
        name = 'dd_pickup',
        icon = 'fa-solid fa-camera',
        label = 'Photo & take order',
        distance = 2.2,
        canInteract = function() return not S.busy and S.order and S.order.stage == 'pickup' end,
        onSelect = doPickup,
    }}

    if Config.Pickup.style == 'employee' then
        local model = r.worker or Config.Pickup.workers[math.random(#Config.Pickup.workers)]
        lib.requestModel(model)
        local ped = CreatePed(4, joaat(model), r.pickup.x, r.pickup.y, r.pickup.z - 1.0, r.pickup.w, false, true)
        SetModelAsNoLongerNeeded(joaat(model))
        SetEntityInvincible(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        FreezeEntityPosition(ped, true)
        local bag = spawnBag(cfg, false, r.pickup)
        attachTo(bag, ped, cfg)
        if cfg.anim then
            lib.requestAnimDict(cfg.anim.dict)
            TaskPlayAnim(ped, cfg.anim.dict, cfg.anim.clip, 8.0, -8.0, -1, 49, 0, false, false, false)
        end
        S.worker, S.workerBag = ped, bag
        exports.ox_target:addLocalEntity(ped, option)
    else
        local obj = spawnBag(cfg, false, r.pickup)
        SetEntityHeading(obj, r.pickup.w)
        PlaceObjectOnGroundProperly(obj)
        FreezeEntityPosition(obj, true)
        S.pickupProp = obj
        exports.ox_target:addLocalEntity(obj, option)
    end
end

local function startPickup()
    local r = S.order.restaurant
    setBlip(r.pickup, Config.Blips.pickup, ('%s pickup'):format(Config.AppName))
    local id = S.order.id

    CreateThread(function()
        while S.order and S.order.id == id and S.order.stage == 'pickup' do
            local dist = #(GetEntityCoords(PlayerPedId()) - r.pickup.xyz)
            local sleep = 750
            local ent = S.worker or S.pickupProp

            if dist < Config.SpawnRadius and not ent then spawnPickup() end

            if ent and dist < 35.0 and not S.busy then
                local p = GetEntityCoords(ent)
                DrawMarker(2, p.x, p.y, p.z + (S.worker and 1.25 or 0.55), 0.0, 0.0, 0.0, 180.0, 0.0, 0.0, 0.22, 0.22, 0.18,
                    228, 65, 43, 210, true, true, 2, false, nil, nil, false)
                sleep = 0
            end
            Wait(sleep)
        end
    end)
end

local function leaveAtDoor()
    if S.busy or not S.bag or not S.order then return end
    S.busy = true
    local ped, door = PlayerPedId(), S.order.dropoff.door
    local spot = door.xyz + forward(door.w) * 0.5

    TaskTurnPedToFaceCoord(ped, spot.x, spot.y, spot.z, 600)
    Wait(600)
    stopCarryAnim(ped)
    lib.requestAnimDict('pickup_object')
    TaskPlayAnim(ped, 'pickup_object', 'putdown_low', 8.0, -8.0, 1000, 0, 0, false, false, false)
    Wait(800)

    local placed = S.bag
    S.bag = nil -- stops the carry loop
    DetachEntity(placed, true, false)
    SetEntityVisible(placed, true, false)
    SetEntityCoords(placed, spot.x, spot.y, spot.z, false, false, false, false)
    SetEntityHeading(placed, door.w)
    PlaceObjectOnGroundProperly(placed)
    FreezeEntityPosition(placed, true)
    Wait(400)

    takePhoto(GetEntityCoords(placed), 'dropoff')

    if submitDelivery() then
        SetTimeout(Config.LeftoverSeconds * 1000, function()
            if DoesEntityExist(placed) then DeleteEntity(placed) end
        end)
        cleanupOrder()
    else
        FreezeEntityPosition(placed, false)
        attachBag(placed)
        carryLoop()
        S.busy = false
    end
end

-- Hand-off to an NPC customer
local function handOff()
    if S.busy or not S.bag or not S.customer then return end
    S.busy = true
    local ped, cust, door = PlayerPedId(), S.customer, S.order.dropoff.door

    FreezeEntityPosition(cust, false)
    ClearPedTasksImmediately(cust)
    TaskTurnPedToFaceEntity(ped, cust, 700)
    TaskTurnPedToFaceEntity(cust, ped, 700)
    Wait(700)

    stopCarryAnim(ped)
    playGive(ped, cust)
    Wait(1100)

    local bag, cfg = S.bag, bagCfg()
    S.bag = nil
    DetachEntity(bag, true, false)
    attachTo(bag, cust, cfg)
    S.handedOff = true
    PlayPedAmbientSpeechNative(cust, 'GENERIC_THANKS', 'SPEECH_PARAMS_FORCE_NORMAL')
    Wait(900)

    if submitDelivery() then
        removeTarget(cust)
        S.customer = nil
        sendInside(cust, door.w, bag)
        cleanupOrder()
    else
        DetachEntity(bag, true, false)
        attachBag(bag)
        carryLoop()
        S.handedOff = false
        S.busy = false
    end
end

-- Hand-off to a real player who ordered
local function handOffPlayer(target)
    if S.busy or not S.bag or not S.order then return end
    S.busy = true
    local ped = PlayerPedId()
    TaskTurnPedToFaceEntity(ped, target, 600)
    Wait(600)
    stopCarryAnim(ped)
    playGive(ped)
    Wait(1100)
    S.handedOff = true

    if submitDelivery() then
        cleanupOrder()
    else
        S.handedOff = false
        S.busy = false
    end
end

local function spawnCustomer()
    local door = S.order.dropoff.door
    local model = Config.CustomerModels[math.random(#Config.CustomerModels)]
    lib.requestModel(model)
    local ped = CreatePed(4, joaat(model), door.x, door.y, door.z - 1.0, door.w, false, true)
    SetModelAsNoLongerNeeded(joaat(model))
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_STAND_IMPATIENT', 0, true)
    S.customer = ped
    exports.ox_target:addLocalEntity(ped, {{
        name = 'dd_handoff',
        icon = 'fa-solid fa-hand-holding',
        label = 'Hand over order',
        distance = 2.5,
        canInteract = function() return not S.busy and S.bag ~= nil and not IsPedInAnyVehicle(PlayerPedId(), false) end,
        onSelect = handOff,
    }})
end

local function addPlayerHandoff()
    exports.ox_target:addGlobalPlayer({{
        name = 'dd_handoff_player',
        icon = 'fa-solid fa-hand-holding',
        label = ('Hand over %s order'):format(Config.AppName),
        distance = 2.5,
        canInteract = function(entity)
            if S.busy or not S.bag or not S.order or not S.order.player or IsPedInAnyVehicle(PlayerPedId(), false) then return false end
            local idx = NetworkGetPlayerIndexFromPed(entity)
            return idx ~= -1 and GetPlayerServerId(idx) == S.order.customerSrc
        end,
        onSelect = function(data) handOffPlayer(data.entity) end,
    }})
    S.playerTarget = true
end

local function addDoorZone(d)
    S.zone = exports.ox_target:addSphereZone({
        coords = d.door.xyz,
        radius = 1.5,
        debug = Config.Debug,
        options = {{
            name = 'dd_leave',
            icon = 'fa-solid fa-box',
            label = 'Leave order here',
            distance = 2.5,
            canInteract = function() return not S.busy and S.bag ~= nil and not IsPedInAnyVehicle(PlayerPedId(), false) end,
            onSelect = leaveAtDoor,
        }},
    })
end

startDropoff = function()
    local d = S.order.dropoff
    local label = S.order.player and ('%s: %s'):format(Config.AppName, S.order.customerName) or ('%s customer'):format(Config.AppName)
    setBlip(d.door, Config.Blips.dropoff, label)
    local id = S.order.id

    CreateThread(function()
        while S.order and S.order.id == id and S.order.stage == 'dropoff' do
            local dist = #(GetEntityCoords(PlayerPedId()) - d.door.xyz)
            local sleep = 750
            local f2f, player = S.order.faceToFace, S.order.player

            -- real customers can hand-off anywhere (they may have wandered); NPCs/doors spawn when close
            if f2f and player and not S.playerTarget then addPlayerHandoff() end
            if dist < Config.SpawnRadius then
                if f2f and not player and not S.customer then spawnCustomer()
                elseif not f2f and not S.zone then addDoorZone(d) end
            end

            if dist < 35.0 and not f2f then
                DrawMarker(2, d.door.x, d.door.y, d.door.z + 0.3, 0.0, 0.0, 0.0, 180.0, 0.0, 0.0, 0.25, 0.25, 0.2,
                    23, 138, 76, 210, true, true, 2, false, nil, nil, false)
                sleep = 0
            end
            Wait(sleep)
        end
    end)
end

---------------------------------------------------------------------
-- Driver events
---------------------------------------------------------------------
local resyncCustomer -- defined with the customer code below

RegisterNetEvent('nrp-doordrop:client:state', function(snap)
    if not snap then return end
    S.online = snap.online
    nui('state', snap)
    if resyncCustomer then resyncCustomer(snap.customer) end
end)

RegisterNetEvent('nrp-doordrop:client:offer', function(offer, timeout)
    S.offer = offer
    S.offerEnds = GetGameTimer() + timeout * 1000
    S.lastResult = nil
    nui('offer', { offer = toNui(offer), left = timeout, total = timeout })

    if phoneMode() then
        if Phone.NotifyOffers then
            alert(('New order: %s'):format(offer.restaurant.label),
                ('$%d guaranteed, %s mi. %ds to accept.'):format(offer.total, offer.miles, timeout))
        end
    elseif S.phone == 'closed' then
        setPhone('peek')
    end
    playRing()
end)

RegisterNetEvent('nrp-doordrop:client:offerGone', function(reason)
    S.offer = nil
    stopRing()
    nui('offerGone', { reason = reason })
    if reason == 'expired' then notify('Offer expired. It counts as a decline.', 'warning') end
    if S.phone == 'peek' then setPhone('closed') end
end)

RegisterNetEvent('nrp-doordrop:client:orderStarted', function(order)
    stopRing()
    cleanupOrder()
    S.offer = nil
    S.order = order
    S.photos, S.lastResult = {}, nil
    S.deadlineAt = GetGameTimer() + order.deadlineIn * 1000
    nui('order', toNui(order))
    if S.phone == 'peek' then setPhone('closed') end
    notify(('Head to %s to grab the order.'):format(order.restaurant.label))
    startPickup()
end)

RegisterNetEvent('nrp-doordrop:client:orderCancelled', function(reason)
    cleanupOrder()
    nui('orderCancelled', { reason = reason })
    notify(reason, 'error')
end)

RegisterNetEvent('nrp-doordrop:client:review', function(stars, text)
    alert(('New %d★ rating'):format(stars), text and ('"%s"'):format(text) or 'A customer rated your delivery.')
end)

---------------------------------------------------------------------
-- Customer (ordering food)
---------------------------------------------------------------------
local custMessages = {
    accepted = function(c) return ('%s is picking up your order from %s.'):format(c.driverName or 'A driver', c.restaurant) end,
    pickedup = function(c) return ('%s has your food and is on the way.'):format(c.driverName or 'Your driver') end,
    delivered = function(c)
        if c.npc and c.missing then
            local parts = {}
            for _, m in ipairs(c.missing) do parts[#parts + 1] = ('%dx %s'):format(m.qty, m.label) end
            return ('Your order came up short. Missing: %s.'):format(table.concat(parts, ', '))
        end
        if c.npc then return c.note or ('%s delivered your food. It\'s in your pockets.'):format(c.driverName) end
        return c.handoff == 'door' and 'Your food was left for you. Rate your driver in the app.'
            or 'Your food was delivered. Rate your driver in the app.'
    end,
    cancelled = function(c) return c.reason or 'Your order was cancelled.' end,
}

local function clearTrackBlip()
    if S.trackBlip then RemoveBlip(S.trackBlip) S.trackBlip = nil end
end

-- Moving blip for whoever is bringing the customer's food (hidden once the real courier vehicle has its own blip).
local trackFrom, trackTo, trackAt = nil, nil, 0

CreateThread(function()
    while true do
        if S.trackBlip and trackFrom and trackTo and DoesBlipExist(S.trackBlip) then
            local t = math.min(1.0, (GetGameTimer() - trackAt) / 1000.0)
            SetBlipCoords(S.trackBlip, trackFrom.x + (trackTo.x - trackFrom.x) * t, trackFrom.y + (trackTo.y - trackFrom.y) * t, 0.0)
            Wait(50)
        else
            Wait(500)
        end
    end
end)

local function updateTrackBlip(c)
    local live = c and c.courierPos and (c.status == 'accepted' or c.status == 'pickedup' or c.status == 'arriving')
    if not live or S.courier then return clearTrackBlip() end
    local now = GetGameTimer()
    if not S.trackBlip then trackTo = nil end -- new blip: start where they are, don't glide from an old order
    local t = trackTo and math.min(1.0, (now - trackAt) / 1000.0) or 1.0
    trackFrom = trackTo and { x = trackFrom.x + (trackTo.x - trackFrom.x) * t, y = trackFrom.y + (trackTo.y - trackFrom.y) * t } or c.courierPos
    trackTo, trackAt = c.courierPos, now
    local b = Config.NpcCourier.blip
    if not S.trackBlip then
        S.trackBlip = AddBlipForCoord(c.courierPos.x, c.courierPos.y, 0.0)
        SetBlipSprite(S.trackBlip, b.sprite)
        SetBlipColour(S.trackBlip, b.color)
        SetBlipScale(S.trackBlip, 0.9)
        SetBlipAsShortRange(S.trackBlip, false)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(c.npc and b.label or ('%s: %s'):format(Config.AppName, c.driverName or 'Driver'))
        EndTextCommandSetBlipName(S.trackBlip)
    end -- position is glided by the thread above
end

-- An order that's finished is finished: drop the timer, the tracking blip and any late updates for it.
local function endCustomerOrder(id)
    S.custEnded = id or S.custEnded
    S.custData, S.custStatus = nil, nil
    clearTrackBlip()
end

RegisterNetEvent('nrp-doordrop:client:customer', function(c)
    if not c then return end
    -- an update that was already in flight when the order was cancelled/delivered
    if c.id and c.id == S.custEnded and c.status ~= 'cancelled' and c.status ~= 'delivered' then return end
    nui('customer', c)
    if c.status ~= S.custStatus then
        local fn = custMessages[c.status]
        if fn and not c.quiet then alert(Config.AppName, fn(c)) end
    end
    if c.status == 'delivered' or c.status == 'cancelled' then
        endCustomerOrder(c.id)
        return
    end
    updateTrackBlip(c)
    if c.status then S.custData, S.custAt, S.custStatus = c, GetGameTimer(), c.status end
end)

---------------------------------------------------------------------
-- NPC courier: the last stretch is a real vehicle + ped near the customer.
-- Every step checks the courier really exists and really got there; nothing
-- is handed over from a distance. If the AI gets stuck it is moved closer
-- while off screen, and as a last resort the bag is left visibly at your feet.
---------------------------------------------------------------------
local function cleanupCourier()
    local c = S.courier
    if not c then return end
    S.courier = nil
    if c.blip and DoesBlipExist(c.blip) then RemoveBlip(c.blip) end
    if c.live then
        -- the live courier is a server entity: just let go of it
        if c.bag and DoesEntityExist(c.bag) then DeleteEntity(c.bag) end
        for _, e in ipairs({ c.ped, c.veh }) do
            if e and DoesEntityExist(e) and NetworkGetEntityIsNetworked(e) then
                SetNetworkIdCanMigrate(NetworkGetNetworkIdFromEntity(e), true)
            end
        end
        return
    end
    for _, e in ipairs({ c.bag, c.ped, c.veh }) do
        if e and e ~= 0 and DoesEntityExist(e) then
            removeTarget(e)
            SetEntityAsMissionEntity(e, true, true)
            DeleteEntity(e)
        end
    end
end

-- a cancelled order takes its courier with it (they never hand anything over)
AddEventHandler('nrp-doordrop:client:customer', function(c)
    if c and c.status == 'cancelled' then cleanupCourier() end
end)

local function courierAlive()
    local c = S.courier
    return c and c.ped and DoesEntityExist(c.ped) and not IsEntityDead(c.ped)
end

local function flat(a, b)
    return #(vector2(a.x, a.y) - vector2(b.x, b.y))
end

local function offScreen(pos)
    return not IsSphereVisible(pos.x, pos.y, pos.z + 1.0, 2.5)
end

local function loadArea(pos)
    RequestCollisionAtCoord(pos.x, pos.y, pos.z)
    local t = GetGameTimer() + 1500
    while GetGameTimer() < t do
        RequestCollisionAtCoord(pos.x, pos.y, pos.z)
        Wait(50)
    end
end

-- A road node near `center`, between minD and maxD from `me`, off screen, preferring the side the courier comes from.
local function findRoadSpawn(center, me, fromDir, minD, maxD)
    local best, bestHeading, bestScore
    for n = 1, 60 do
        local ok, pos, heading = GetNthClosestVehicleNodeWithHeading(center.x, center.y, center.z, n, 1, 3.0, 0)
        if ok then
            local d = flat(pos, me)
            if d >= minD and d <= maxD and offScreen(pos) then
                local dir = vector2(pos.x - me.x, pos.y - me.y) / math.max(d, 0.01)
                local score = dir.x * fromDir.x + dir.y * fromDir.y -- 1 = straight from the courier's direction
                if not bestScore or score > bestScore then best, bestHeading, bestScore = pos, heading, score end
            end
        end
    end
    return best, bestHeading
end

local function closestRoad(p)
    local ok, pos = GetClosestVehicleNode(p.x, p.y, p.z, 1, 3.0, 0)
    if ok and pos and (pos.x ~= 0.0 or pos.y ~= 0.0) then return pos end
end

-- A walkable spot near `pos` (sidewalk / ground), or pos itself.
local function safeFoot(pos)
    local ok, p = GetSafeCoordForPed(pos.x, pos.y, pos.z, false, 16)
    if ok then return p end
    local okZ, z = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 5.0, false)
    return vector3(pos.x, pos.y, okZ and z or pos.z)
end

local function prepCourierPed(ped)
    SetEntityAsMissionEntity(ped, true, true) -- stops population culling from deleting them mid-delivery
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCanRagdoll(ped, false)
    SetEntityInvincible(ped, true)
    SetPedKeepTask(ped, true)
    SetEntityVisible(ped, true, false)
    ResetEntityAlpha(ped)
end

local function spawnCourierPed(model, pos, heading)
    lib.requestModel(model)
    local ped = CreatePed(4, joaat(model), pos.x, pos.y, pos.z, heading or 0.0, false, true)
    SetModelAsNoLongerNeeded(joaat(model))
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    prepCourierPed(ped)
    return ped
end

local function addCourierBlip(ent)
    local b = Config.NpcCourier.blip
    local blip = AddBlipForEntity(ent)
    SetBlipSprite(blip, b.sprite)
    SetBlipColour(blip, b.color)
    SetBlipScale(blip, 0.9)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(b.label)
    EndTextCommandSetBlipName(blip)
    return blip
end

-- Walk the courier to a moving or fixed target. Re-issues the task, detects being stuck,
-- and hops them closer while nobody is looking. Returns true only when they are really there.
local function walkCourierTo(getTarget, reach, timeoutMs)
    local c = S.courier
    local lastD, stuckSince, lastTask = math.huge, GetGameTimer(), 0
    local deadline = GetGameTimer() + timeoutMs
    while GetGameTimer() < deadline do
        if not courierAlive() then return false end
        local target = getTarget()
        local pos = GetEntityCoords(c.ped)
        local d = #(pos - target)
        if d <= reach then return true end

        if GetGameTimer() - lastTask > 2500 then
            if d > 5.0 then
                -- pathfinds around walls, cars and fences
                TaskGoToCoordAnyMeans(c.ped, target.x, target.y, target.z, d > 15.0 and 2.0 or 1.3, 0, false, 786603, -1.0)
            else
                TaskGoStraightToCoord(c.ped, target.x, target.y, target.z, 1.0, -1, 0.0, reach * 0.5)
            end
            lastTask = GetGameTimer()
        end
        if d < lastD - 0.6 then
            lastD, stuckSince = d, GetGameTimer()
        elseif GetGameTimer() - stuckSince > 5000 then
            -- stuck: hop closer, but only somewhere the player can't see
            local me = GetEntityCoords(PlayerPedId())
            for _, dist in ipairs({ 8.0, 12.0, 6.0, 16.0 }) do
                local back = me - GetEntityForwardVector(PlayerPedId()) * dist
                local spot = safeFoot(back)
                if offScreen(spot) or dist == 16.0 then
                    SetEntityCoords(c.ped, spot.x, spot.y, spot.z, false, false, false, false)
                    break
                end
            end
            lastD, stuckSince, lastTask = math.huge, GetGameTimer(), 0
        end
        Wait(250)
    end
    return false
end

-- Drive the courier's vehicle toward `dest`. Returns true when parked close enough.
local function driveCourierTo(dest)
    local c = S.courier
    local N = Config.NpcCourier
    TaskVehicleDriveToCoordLongrange(c.ped, c.veh, dest.x, dest.y, dest.z, 12.0, 786603, 8.0)
    local lastD, stuckSince, hops = math.huge, GetGameTimer(), 0
    local deadline = GetGameTimer() + N.driveTimeout * 1000
    while GetGameTimer() < deadline do
        Wait(500)
        if not courierAlive() or not DoesEntityExist(c.veh) then return false end
        if not IsPedInVehicle(c.ped, c.veh, false) then return false end
        local d = flat(GetEntityCoords(c.veh), dest)
        if d < 14.0 then return true end
        if d < lastD - 1.5 then
            lastD, stuckSince = d, GetGameTimer()
        elseif GetGameTimer() - stuckSince > 6000 then
            hops = hops + 1
            if hops > 2 then return false end
            -- jump to a road node closer in, off screen, and try again
            local me = GetEntityCoords(PlayerPedId())
            local node, heading = findRoadSpawn(me, me, vector2(0.0, 0.0), 25.0, math.max(30.0, d * 0.6))
            if node then
                SetEntityCoords(c.veh, node.x, node.y, node.z + 0.3, false, false, false, false)
                SetEntityHeading(c.veh, heading)
                SetVehicleOnGroundProperly(c.veh)
                TaskVehicleDriveToCoordLongrange(c.ped, c.veh, dest.x, dest.y, dest.z, 12.0, 786603, 8.0)
            end
            lastD, stuckSince = math.huge, GetGameTimer()
        end
    end
    return false
end

-- Last resort: the bag is placed next to you where you can see it, never an invisible handoff.
local function dropAtFeet(cfg)
    local me = PlayerPedId()
    local spot = GetOffsetFromEntityInWorldCoords(me, 0.6, 0.6, 0.0)
    local bag = spawnBag(cfg, false, spot)
    PlaceObjectOnGroundProperly(bag)
    FreezeEntityPosition(bag, true)
    return bag
end

local function makeTakeable(bag)
    exports.ox_target:addLocalEntity(bag, {{
        name = 'dd_takebag', icon = 'fa-solid fa-bag-shopping', label = 'Pick up your order', distance = 2.0,
        onSelect = function()
            lib.requestAnimDict('random@domestic')
            TaskPlayAnim(PlayerPedId(), 'random@domestic', 'pickup_low', 8.0, -8.0, 1200, 0, 0, false, false, false)
            Wait(700)
            removeTarget(bag)
            DeleteEntity(bag)
        end,
    }})
    SetTimeout(Config.LeftoverSeconds * 1000, function()
        if DoesEntityExist(bag) then removeTarget(bag) DeleteEntity(bag) end
    end)
end

local courierHandover -- defined below

local function exitCourierVehicle(ped, veh)
    TaskVehicleTempAction(ped, veh, 27, 2000) -- brake
    Wait(1000)
    TaskLeaveVehicle(ped, veh, 256)
    local t = GetGameTimer() + 5000
    while IsPedInAnyVehicle(ped, false) and GetGameTimer() < t do Wait(100) end
    if IsPedInAnyVehicle(ped, false) then
        local out = GetOffsetFromEntityInWorldCoords(veh, -1.5, 0.0, 0.0)
        SetEntityCoords(ped, out.x, out.y, out.z, false, false, false, false)
    end
    RemovePedHelmet(ped, true)
end

local function runCourier(d, finish)
    local N = Config.NpcCourier
    local me = GetEntityCoords(PlayerPedId())
    local handoff = d.handoff ~= 'door'
    local orderPos = vector3(d.coords.x, d.coords.y, d.coords.z)
    local cfg = Config.Bags[d.bag] or Config.Bags.bag

    -- "leave it here" but the customer is far from that spot: nothing to watch, just complete it
    if not handoff and #(me - orderPos) > 250.0 then return finish() end

    local focus = handoff and me or orderPos
    local fromDir = vector2(d.from.x - focus.x, d.from.y - focus.y)
    fromDir = #fromDir > 1.0 and fromDir / #fromDir or vector2(1.0, 0.0)

    local pedModel = N.peds[math.random(#N.peds)]
    local vehModel = N.vehicles[math.random(#N.vehicles)]
    S.courier = {}
    clearTrackBlip()

    -- 1) try to arrive by vehicle: off-screen road spawn 45-110 m out, with collision loaded
    local roadNear = closestRoad(focus)
    local nearRoad = roadNear and flat(roadNear, focus) < 60.0
    local spawn, heading
    if nearRoad then
        spawn, heading = findRoadSpawn(focus, me, fromDir, 45.0, 110.0)
    end

    if spawn then
        loadArea(spawn)
        lib.requestModel(vehModel)
        local veh = CreateVehicle(joaat(vehModel), spawn.x, spawn.y, spawn.z + 0.3, heading, false, false)
        SetModelAsNoLongerNeeded(joaat(vehModel))
        if veh and veh ~= 0 and DoesEntityExist(veh) then
            SetEntityAsMissionEntity(veh, true, true)
            SetVehicleOnGroundProperly(veh)
            SetVehicleEngineOn(veh, true, true, false)
            SetVehicleDoorsLocked(veh, 1)
            lib.requestModel(pedModel)
            local ped = CreatePedInsideVehicle(veh, 4, joaat(pedModel), -1, false, false)
            SetModelAsNoLongerNeeded(joaat(pedModel))
            if ped and ped ~= 0 and DoesEntityExist(ped) then
                prepCourierPed(ped)
                local cls = GetVehicleClass(veh)
                if cls == 8 or cls == 13 then GivePedHelmet(ped, true, 4096, -1) end
                S.courier = { veh = veh, ped = ped, blip = addCourierBlip(veh) }
                local parkAt = roadNear or focus
                if handoff then
                    parkAt = closestRoad(me) or me
                end
                driveCourierTo(parkAt)
                if courierAlive() and IsPedInAnyVehicle(ped, false) then exitCourierVehicle(ped, veh) end
            else
                DeleteEntity(veh)
            end
        end
    end

    -- 2) no vehicle (no road nearby, spawn failed, AI gave up): arrive on foot from off screen
    if not courierAlive() then
        if S.courier.veh and DoesEntityExist(S.courier.veh) then DeleteEntity(S.courier.veh) end
        if S.courier.blip then RemoveBlip(S.courier.blip) end
        local spot
        for _, dist in ipairs({ 25.0, 18.0, 35.0, 12.0 }) do
            local p = safeFoot(focus + vector3(fromDir.x, fromDir.y, 0.0) * dist)
            if offScreen(p) then spot = p break end
            p = safeFoot(focus - GetEntityForwardVector(PlayerPedId()) * dist)
            if offScreen(p) then spot = p break end
        end
        spot = spot or safeFoot(focus - GetEntityForwardVector(PlayerPedId()) * 12.0)
        loadArea(spot)
        local ped = spawnCourierPed(pedModel, spot, 0.0)
        S.courier = { ped = ped, blip = ped and addCourierBlip(ped) or nil }
    end

    if not courierAlive() then
        -- the game refused to spawn anyone; still no invisible handoff
        local bag = dropAtFeet(cfg)
        makeTakeable(bag)
        return finish('Your courier left your order next to you.')
    end

    return courierHandover(d, finish)
end

-- Courier is standing near you (local or live): carry the bag over, hand it off or drop it, then leave.
courierHandover = function(d, finish)
    local handoff = d.handoff ~= 'door'
    local orderPos = vector3(d.coords.x, d.coords.y, d.coords.z)
    local cfg = Config.Bags[d.bag] or Config.Bags.bag
    local ped = S.courier.ped
    local bag = spawnBag(cfg, false, GetEntityCoords(ped))
    attachTo(bag, ped, cfg)
    S.courier.bag = bag

    if handoff then
        local reached = walkCourierTo(function()
            local p = PlayerPedId()
            local veh = GetVehiclePedIsIn(p, false)
            if veh ~= 0 then return GetOffsetFromEntityInWorldCoords(veh, -1.6, 0.4, 0.0) end -- driver window
            return GetEntityCoords(p)
        end, 1.6, 60000)

        local meNow = PlayerPedId()
        if reached then
            ClearPedTasks(ped)
            TaskTurnPedToFaceEntity(ped, meNow, 700)
            local inVeh = IsPedInAnyVehicle(meNow, false)
            if not inVeh then TaskTurnPedToFaceEntity(meNow, ped, 700) end
            Wait(700)
            playGive(ped, not inVeh and meNow or nil)
            Wait(1100)
            S.courier.bag = nil
            DetachEntity(bag, true, false)
            if inVeh then
                DeleteEntity(bag)
            else
                attachTo(bag, meNow, cfg)
                SetTimeout(3000, function() if DoesEntityExist(bag) then DeleteEntity(bag) end end)
            end
            PlayPedAmbientSpeechNative(ped, 'GENERIC_HI', 'SPEECH_PARAMS_FORCE_NORMAL')
            finish()
        else
            -- couldn't reach you (you kept moving / somewhere unreachable): leave it right by you, visibly
            S.courier.bag = nil
            DeleteEntity(bag)
            makeTakeable(dropAtFeet(cfg))
            finish('Your courier couldn\'t reach you, so they left it right next to you.')
        end
    else
        local dropSpot = safeFoot(orderPos)
        local reached = walkCourierTo(function() return dropSpot end, 1.4, 45000)
        if not reached and courierAlive() and offScreen(dropSpot) then
            SetEntityCoords(ped, dropSpot.x, dropSpot.y, dropSpot.z, false, false, false, false)
            reached = true
        end
        ClearPedTasks(ped)
        lib.requestAnimDict('pickup_object')
        TaskPlayAnim(ped, 'pickup_object', 'putdown_low', 8.0, -8.0, 1000, 0, 0, false, false, false)
        Wait(800)
        S.courier.bag = nil
        DetachEntity(bag, true, false)
        local p = reached and dropSpot or GetEntityCoords(ped)
        SetEntityCoords(bag, p.x, p.y, p.z, false, false, false, false)
        PlaceObjectOnGroundProperly(bag)
        FreezeEntityPosition(bag, true)
        makeTakeable(bag)
        finish()
    end

    -- head off: back to the vehicle if there is one, otherwise walk away, then clean up
    if not courierAlive() then return cleanupCourier() end
    local c = S.courier
    if c.live then
        -- the server tells every client the courier is leaving; whoever owns them drives off
        ClearPedTasks(c.ped)
        return cleanupCourier()
    end
    if c.veh and DoesEntityExist(c.veh) then
        TaskEnterVehicle(c.ped, c.veh, 10000, -1, 1.5, 1, 0)
        local t = GetGameTimer() + 10000
        while not IsPedInVehicle(c.ped, c.veh, false) and GetGameTimer() < t do Wait(250) end
        if IsPedInVehicle(c.ped, c.veh, false) then TaskVehicleDriveWander(c.ped, c.veh, 15.0, 786603) end
    else
        TaskWanderStandard(c.ped, 10.0, 10)
    end
    SetTimeout(20000, cleanupCourier)
end

local function startCourier(d, test)
    if S.courier then return end
    CreateThread(function()
        local done = false
        local function finish(note)
            if done then return end
            done = true
            if test then
                notify(note or 'Test courier delivered.', 'success')
            else
                lib.callback.await('nrp-doordrop:customer:npcDelivered', false, d.id, note)
            end
        end
        local ok, err = pcall(runCourier, d, finish)
        if not ok then
            print(('^1[nrp-doordrop]^7 courier error: %s'):format(err))
            cleanupCourier()
            if not done and S.custEnded ~= d.id then
                -- never an invisible handoff: put the bag down next to the player
                pcall(function() makeTakeable(dropAtFeet(Config.Bags[d.bag] or Config.Bags.bag)) end)
                finish('Your courier left your order next to you.')
            end
        end
    end)
end

RegisterNetEvent('nrp-doordrop:client:npcArrive', function(d) startCourier(d, false) end)

-- /ddtestcourier [hand|door] : rehearse the courier arrival without placing an order (Config.Debug only)
if Config.Debug then
    RegisterCommand('ddtestcourier', function(_, args)
        local me = GetEntityCoords(PlayerPedId())
        local from = GetOffsetFromEntityInWorldCoords(PlayerPedId(), 0.0, -300.0, 0.0)
        startCourier({
            id = 0, bag = 'bag', handoff = args[1] == 'door' and 'door' or 'hand', name = 'Test Courier',
            from = { x = from.x, y = from.y }, coords = { x = me.x, y = me.y, z = me.z, w = GetEntityHeading(PlayerPedId()) },
        }, true)
    end, false)
end

---------------------------------------------------------------------
-- Live courier: a real networked ped + vehicle driving the city.
-- The server creates them; whichever client the game makes their owner
-- runs this "brain" so the drive task survives ownership changes.
---------------------------------------------------------------------
local TASK_DRIVE_LONGRANGE = 0x21D33957
local TASK_ENTER_VEHICLE   = 0x950B6492
local brainSeen, brainDest, brainLeaving, downReported = {}, {}, {}, {}

local function setupCourierEntities(ped, veh)
    if brainSeen[ped] then return end
    brainSeen[ped] = true
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedKeepTask(ped, true)
    SetDriverAbility(ped, 1.0)
    SetDriverAggressiveness(ped, 0.0)
    SetPedCanBeDraggedOut(ped, true)       -- carjackable
    SetPedFleeAttributes(ped, 0, false)
    SetPedConfigFlag(ped, 32, false)       -- stays on the bike / in the seat on small bumps
    SetVehicleEngineOn(veh, true, true, false)
    SetVehicleDoorsLocked(veh, 1)
    local cls = GetVehicleClass(veh)
    if cls == 8 or cls == 13 then GivePedHelmet(ped, true, 4096, -1) end
end

local function brainTick(id, c)
    if not (NetworkDoesNetworkIdExist(c.ped) and NetworkDoesNetworkIdExist(c.veh)) then return end
    local ped, veh = NetToPed(c.ped), NetToVeh(c.veh)
    if not DoesEntityExist(ped) or not DoesEntityExist(veh) then return end

    -- anyone close enough to see a dead courier reports it (server double-checks)
    if IsEntityDead(ped) then
        if not downReported[id] then
            downReported[id] = true
            TriggerServerEvent('nrp-doordrop:server:courierDown', tonumber(id), 'attacked')
        end
        return
    end
    if not NetworkHasControlOfEntity(ped) then return end
    if c.phase == 'deliver' then return end -- the customer's client runs the hand-off
    setupCourierEntities(ped, veh)

    if not IsPedInVehicle(ped, veh, false) then
        if GetPedInVehicleSeat(veh, -1) ~= 0 then return end -- someone else is driving it (server handles theft)
        local d = #(GetEntityCoords(ped) - GetEntityCoords(veh))
        if d < 3.0 then
            TaskWarpPedIntoVehicle(ped, veh, -1) -- fresh spawn beside the vehicle
        elseif d < 40.0 and GetScriptTaskStatus(ped, TASK_ENTER_VEHICLE) == 7 then
            TaskEnterVehicle(ped, veh, 20000, -1, 2.0, 1, 0)
        end
        return
    end

    if c.phase == 'leave' then
        if not brainLeaving[ped] then
            brainLeaving[ped] = true
            TaskVehicleDriveWander(ped, veh, 15.0, 786603)
        end
        return
    end

    local dest = vector3(c.dest.x, c.dest.y, c.dest.z)
    local here = GetEntityCoords(veh)
    if c.phase == 'wait' or #(here - dest) < 15.0 then
        if GetEntitySpeed(veh) > 1.0 then TaskVehicleTempAction(ped, veh, 27, 3000) end -- pull up and wait
        brainDest[ped] = nil
        return
    end
    local last = brainDest[ped]
    if not last or #(last - dest) > 5.0 or GetScriptTaskStatus(ped, TASK_DRIVE_LONGRANGE) == 7 then
        TaskVehicleDriveToCoordLongrange(ped, veh, dest.x, dest.y, dest.z, c.speed or 13.0, 786603, 12.0)
        brainDest[ped] = dest
    end
end

CreateThread(function()
    while true do
        local list = GlobalState.ddCouriers
        if list and next(list) then
            for id, c in pairs(list) do pcall(brainTick, id, c) end
            Wait(1000)
        else
            Wait(2500)
        end
    end
end)

-- The server asks a nearby player's game for a real road spot (road data only exists near players).
lib.callback.register('nrp-doordrop:roadSpawn', function(pos, toward)
    local p = vector3(pos.x, pos.y, pos.z or 0.0)
    if p.z == 0.0 then
        local ok, z = GetGroundZFor_3dCoord(p.x, p.y, 1000.0, false)
        p = vector3(p.x, p.y, ok and z or 30.0)
    end
    local best, bestH, bestScore
    local dir = vector2(toward.x - p.x, toward.y - p.y)
    dir = #dir > 1.0 and dir / #dir or vector2(0.0, 1.0)
    for n = 1, 8 do
        local ok, node, heading = GetNthClosestVehicleNodeWithHeading(p.x, p.y, p.z, n, 1, 3.0, 0)
        if ok and #(vector2(node.x, node.y) - p.xy) < 80.0 then
            local r = math.rad(heading)
            local fwd = vector2(-math.sin(r), math.cos(r))
            local score = fwd.x * dir.x + fwd.y * dir.y -- prefer lanes already pointing the right way
            if not bestScore or score > bestScore then best, bestH, bestScore = node, heading, score end
        end
    end
    if not best then return nil end
    if bestScore < 0 then bestH = (bestH + 180.0) % 360.0 end
    return { x = best.x, y = best.y, z = best.z, h = bestH }
end)

-- The live courier pulled up near us: take control and walk the bag over.
RegisterNetEvent('nrp-doordrop:client:npcArriveLive', function(d)
    if S.courier then return end
    CreateThread(function()
        local t = GetGameTimer() + 4000
        while GetGameTimer() < t and not (NetworkDoesNetworkIdExist(d.pedNet) and NetworkDoesNetworkIdExist(d.vehNet)) do Wait(100) end
        local ped = NetworkDoesNetworkIdExist(d.pedNet) and NetToPed(d.pedNet) or 0
        local veh = NetworkDoesNetworkIdExist(d.vehNet) and NetToVeh(d.vehNet) or 0
        if ped == 0 or not DoesEntityExist(ped) or IsEntityDead(ped) then
            return startCourier(d, false) -- couldn't see them: fall back to a local courier
        end
        for _, e in ipairs({ ped, veh }) do
            if e ~= 0 then
                local tt = GetGameTimer() + 2000
                while not NetworkHasControlOfEntity(e) and GetGameTimer() < tt do
                    NetworkRequestControlOfEntity(e)
                    Wait(50)
                end
                if NetworkHasControlOfEntity(e) then SetNetworkIdCanMigrate(NetworkGetNetworkIdFromEntity(e), false) end
            end
        end
        S.courier = { ped = ped, veh = veh ~= 0 and veh or nil, live = true }
        clearTrackBlip()
        S.courier.blip = addCourierBlip(ped)

        local done = false
        local function finish(note)
            if done then return end
            done = true
            lib.callback.await('nrp-doordrop:customer:npcDelivered', false, d.id, note)
        end
        local ok, err = pcall(function()
            if veh ~= 0 and IsPedInVehicle(ped, veh, false) then exitCourierVehicle(ped, veh) end
            courierHandover(d, finish)
        end)
        if not ok then
            print(('^1[nrp-doordrop]^7 live courier error: %s'):format(err))
            if not done and S.custEnded ~= d.id then
                pcall(function() makeTakeable(dropAtFeet(Config.Bags[d.bag] or Config.Bags.bag)) end)
                finish('Your courier left your order next to you.')
            end
            cleanupCourier()
        end
    end)
end)

-- Road routes from the game's own GPS: a hidden multi-route (nothing is drawn, your waypoint is
-- untouched). GPS routing covers the whole map, unlike the streamed road nodes. One at a time.
local routerBusy = false

local function sampleGpsRoute(points)
    ClearGpsMultiRoute()
    StartGpsMultiRoute(6, false, false)
    for _, p in ipairs(points) do AddPointToGpsMultiRoute(p.x, p.y, p.z or 0.0) end
    SetGpsMultiRouteRender(false)

    local pts
    for _, p1 in ipairs({ true, false }) do
        local ready = false
        local t = GetGameTimer() + 2500 -- the route is calculated over a few frames
        while GetGameTimer() < t do
            if GetPosAlongGpsTypeRoute(p1, 0.0, 1) then ready = true break end
            Wait(100)
        end
        if ready then
            pts = {}
            local last, d = nil, 0.0
            for _ = 1, 1400 do
                local ok, pos = GetPosAlongGpsTypeRoute(p1, d, 1)
                if not ok or not pos or (pos.x == 0.0 and pos.y == 0.0) then break end
                if last and #(pos.xy - last.xy) < 0.5 then break end -- past the end: position stops moving
                pts[#pts + 1] = { x = math.floor(pos.x * 10) / 10, y = math.floor(pos.y * 10) / 10, z = math.floor(pos.z * 10) / 10 }
                last = pos
                d = d + 25.0
            end
            if #pts >= 2 then break end
        end
    end
    ClearGpsMultiRoute()
    -- the hidden route shares the GPS with your own: put your route line and waypoint back
    local wpOn = IsWaypointActive()
    local wp = wpOn and GetBlipInfoIdCoord(GetFirstBlipInfoId(8)) or nil
    if S.blip and DoesBlipExist(S.blip) then
        SetBlipRoute(S.blip, false)
        SetBlipRoute(S.blip, true)
    end
    if wp then SetNewWaypoint(wp.x, wp.y) end
    return (pts and #pts >= 2) and pts or nil
end

-- queue behind any route already being planned
local function planRoute(points)
    local t = GetGameTimer() + 8000
    while routerBusy and GetGameTimer() < t do Wait(100) end
    if routerBusy then return nil end
    routerBusy = true
    local ok, pts = pcall(sampleGpsRoute, points)
    routerBusy = false
    return ok and pts or nil
end

-- fewer points for the app's small map
local function thinRoute(pts, spacing)
    local out, last = {}, nil
    for i, p in ipairs(pts) do
        if i == 1 or i == #pts or not last or #(vector2(p.x, p.y) - vector2(last.x, last.y)) >= spacing then
            out[#out + 1] = { x = math.floor(p.x), y = math.floor(p.y) }
            last = p
        end
    end
    return out
end

-- courier: the server asks the customer's game for the road route of the current leg
RegisterNetEvent('nrp-doordrop:client:routeRequest', function(r)
    CreateThread(function()
        local pts = planRoute({ r.from, r.to })
        if pts then TriggerServerEvent('nrp-doordrop:server:route', r.id, r.leg, pts) end
        -- on the way to the restaurant: also draw the restaurant -> you part on roads
        if r.next then
            local nxt = planRoute({ r.to, r.next })
            if nxt then nui('custNextRoute', { id = r.id, pts = thinRoute(nxt, 80.0) }) end
        end
    end)
end)

---------------------------------------------------------------------
-- Driver route: you -> restaurant -> customer on real roads, for the app's map.
-- Re-planned when you head off it.
---------------------------------------------------------------------
local driverRoute = nil -- { key, pts }

local function routeKey()
    if S.order then return ('order:%s:%s'):format(S.order.id, S.order.stage) end
    if S.offer then return ('offer:%s'):format(S.offer.id) end
end

local function planDriverRoute()
    local key = routeKey()
    if not key then return end
    local me = GetEntityCoords(PlayerPedId())
    local o = S.order or S.offer
    local pts = { { x = me.x, y = me.y, z = me.z } }
    local r, d = o.restaurant.pickup, o.dropoff.door
    if not S.order or S.order.stage == 'pickup' then pts[#pts + 1] = { x = r.x, y = r.y, z = r.z } end
    pts[#pts + 1] = { x = d.x, y = d.y, z = d.z }
    local route = planRoute(pts)
    if route and routeKey() == key then
        driverRoute = { key = key, pts = route }
        nui('driverRoute', { key = key, pts = thinRoute(route, 60.0) })
    end
end

local function offRoute(pos)
    if not driverRoute then return math.huge end
    local best = math.huge
    local pts = driverRoute.pts
    for i = 2, #pts, 1 do
        local a, b = pts[i - 1], pts[i]
        local vx, vy = b.x - a.x, b.y - a.y
        local l2 = vx * vx + vy * vy
        local t = l2 > 0 and math.max(0.0, math.min(1.0, ((pos.x - a.x) * vx + (pos.y - a.y) * vy) / l2)) or 0.0
        local dx, dy = pos.x - (a.x + vx * t), pos.y - (a.y + vy * t)
        local dd = dx * dx + dy * dy
        if dd < best then best = dd end
    end
    return math.sqrt(best)
end

CreateThread(function()
    local lastKey, lastPlan = nil, 0
    while true do
        local sleep = 2000
        local key = routeKey()
        if key then
            sleep = 1000
            local stale = key ~= lastKey
            local drifted = not stale and GetGameTimer() - lastPlan > 12000 and offRoute(GetEntityCoords(PlayerPedId())) > 80.0
            if stale or drifted then
                lastKey, lastPlan = key, GetGameTimer()
                planDriverRoute()
            end
        else
            lastKey, driverRoute = nil, nil
        end
        Wait(sleep)
    end
end)

-- Food bags dropped by a courier who got robbed or wrecked: anyone can grab them.
exports.ox_target:addGlobalObject({{
    name = 'dd_loot',
    icon = 'fa-solid fa-bag-shopping',
    label = 'Take the food bag',
    distance = 2.0,
    canInteract = function(entity)
        return NetworkGetEntityIsNetworked(entity) and Entity(entity).state.ddLoot ~= nil
    end,
    onSelect = function(data)
        lib.requestAnimDict('random@domestic')
        TaskPlayAnim(PlayerPedId(), 'random@domestic', 'pickup_low', 8.0, -8.0, 1200, 0, 0, false, false, false)
        Wait(600)
        TriggerServerEvent('nrp-doordrop:server:takeLoot', NetworkGetNetworkIdFromEntity(data.entity))
    end,
}})

-- The driver handed us the bag: play the receive anim and hold it for a moment.
RegisterNetEvent('nrp-doordrop:client:receive', function(bagKey)
    local ped = PlayerPedId()
    local cfg = Config.Bags[bagKey] or Config.Bags.bag
    lib.requestAnimDict('mp_common')
    TaskPlayAnim(ped, 'mp_common', 'givetake1_b', 8.0, -8.0, 2000, 0, 0, false, false, false)
    Wait(900)
    local bag = spawnBag(cfg, true, GetEntityCoords(ped))
    attachTo(bag, ped, cfg)
    SetTimeout(4000, function() if DoesEntityExist(bag) then DeleteEntity(bag) end end)
end)

local function streetHere()
    local c = GetEntityCoords(PlayerPedId())
    local street = GetStreetNameFromHashKey((GetStreetNameAtCoord(c.x, c.y, c.z)))
    return street ~= '' and street or GetLabelText(GetNameOfZone(c.x, c.y, c.z))
end

RegisterNUICallback('customer:menu', function(_, cb)
    CreateThread(function()
        local res = lib.callback.await('nrp-doordrop:customer:menu', false, { hour = GetClockHours() }) or {}
        res.street = streetHere()
        cb(res)
    end)
end)

RegisterNUICallback('customer:place', function(d, cb)
    CreateThread(function()
        d = type(d) == 'table' and d or {}
        local c = GetEntityCoords(PlayerPedId())
        local street = GetStreetNameAtCoord(c.x, c.y, c.z)
        d.street = GetStreetNameFromHashKey(street)
        d.area = GetLabelText(GetNameOfZone(c.x, c.y, c.z))
        d.hour = GetClockHours()
        local res = lib.callback.await('nrp-doordrop:customer:place', false, d) or { ok = false, reason = 'Try again.' }
        if res.ok then S.custStatus, S.custData, S.custAt = 'searching', res.order, GetGameTimer() end
        cb(res)
    end)
end)

RegisterNUICallback('customer:cancel', function(_, cb)
    CreateThread(function()
        local id = S.custData and S.custData.id
        local res = lib.callback.await('nrp-doordrop:customer:cancel', false) or { ok = false }
        if res.ok then
            endCustomerOrder(id)
            cleanupCourier()
        end
        cb(res)
    end)
end)

RegisterNUICallback('customer:rate', function(d, cb)
    CreateThread(function()
        d = type(d) == 'table' and d or {}
        cb(lib.callback.await('nrp-doordrop:customer:rate', false, d.stars, d.text) or { ok = false })
    end)
end)

---------------------------------------------------------------------
-- Driver NUI callbacks
---------------------------------------------------------------------
RegisterNUICallback('close', function(_, cb) closePhone() cb(1) end)

RegisterNUICallback('toggleOnline', function(d, cb)
    TriggerServerEvent('nrp-doordrop:server:setOnline', d and d.online == true)
    cb(1)
end)

RegisterNUICallback('respond', function(d, cb)
    stopRing()
    if S.offer then TriggerServerEvent('nrp-doordrop:server:respond', S.offer.id, d and d.accept == true) end
    cb(1)
end)

RegisterNUICallback('gps', function(_, cb)
    if S.order then
        local c = S.order.stage == 'pickup' and S.order.restaurant.pickup or S.order.dropoff.door
        SetNewWaypoint(c.x, c.y)
        notify('GPS set.')
    end
    cb(1)
end)

RegisterNUICallback('unassign', function(_, cb)
    if S.order and not S.busy then TriggerServerEvent('nrp-doordrop:server:unassign') end
    cb(1)
end)

---------------------------------------------------------------------
-- Live feeds: your position for the app's mini map, and the on-screen timer
---------------------------------------------------------------------
local MILE = 1609.34

local function appVisible()
    if phoneMode() then
        local ok, open = pcall(function() return exports[Phone.Resource]:IsPhoneOpen() end)
        return ok and open
    end
    return S.phone == 'open'
end

local function custActive()
    local c = S.custData
    return c and (c.status == 'searching' or c.status == 'accepted' or c.status == 'pickedup' or c.status == 'arriving')
end

-- The server's word on whether we still have an order. Clears a timer that's left over for any reason.
resyncCustomer = function(c)
    if c and c.id ~= S.custEnded then
        if not S.custData or S.custData.id ~= c.id or S.custData.status ~= c.status then
            S.custData, S.custStatus = c, c.status
        end
        S.custAt = GetGameTimer()
    elseif custActive() then
        endCustomerOrder(S.custData.id)
        cleanupCourier()
        nui('customer', { status = 'none' })
    end
end

-- safety net: if we haven't heard about our order for a while, ask the server
CreateThread(function()
    while true do
        Wait(10000)
        if custActive() and GetGameTimer() - (S.custAt or 0) > 20000 then
            local ok, snap = pcall(lib.callback.await, 'nrp-doordrop:getState', false)
            if ok and snap then resyncCustomer(snap.customer) end
        end
    end
end)

-- position for the mini map, only while the app is actually on screen
CreateThread(function()
    while true do
        local sleep = 1500
        if Config.MiniMap.enabled and appVisible() then
            local c = GetEntityCoords(PlayerPedId())
            nui('pos', { x = c.x, y = c.y, h = GetEntityHeading(PlayerPedId()), area = GetLabelText(GetNameOfZone(c.x, c.y, c.z)) })
            sleep = 1000
        end
        Wait(sleep)
    end
end)

local function hudPayload()
    if S.order then
        local o = S.order
        local pickup = o.stage == 'pickup'
        local target = pickup and o.restaurant.pickup or o.dropoff.door
        local d = #(GetEntityCoords(PlayerPedId()).xy - vector2(target.x, target.y))
        return {
            kind = 'driver', stage = pickup and 'pickup' or 'dropoff',
            place = pickup and o.restaurant.label or (o.player and o.customerName or o.dropoff.label),
            area = pickup and o.restaurant.area or o.dropoff.area,
            left = math.floor((S.deadlineAt - GetGameTimer()) / 1000),
            miles = math.floor(d * Config.RoadFactor / MILE * 10 + 0.5) / 10,
            pay = o.total, handoff = (not pickup) and o.faceToFace or false,
            condition = (not pickup) and math.floor(S.condition) or nil,
        }
    end
    if Config.Hud.customer and custActive() then
        local c = S.custData
        local elapsed = math.floor((GetGameTimer() - S.custAt) / 1000)
        return {
            kind = 'customer', status = c.status, name = c.driverName, npc = c.npc, restaurant = c.restaurant,
            miles = c.driverMiles, eta = c.eta and math.max(0, c.eta - elapsed) or nil,
        }
    end
end

-- the player's choice to hide the card sticks between sessions
local hudOff = GetResourceKvpInt('doordrop_hud_off') == 1
if Config.Hud.toggleCommand and Config.Hud.toggleCommand ~= '' then
    RegisterCommand(Config.Hud.toggleCommand, function()
        hudOff = not hudOff
        SetResourceKvpInt('doordrop_hud_off', hudOff and 1 or 0)
        notify(hudOff and 'Delivery timer hidden. Type /' .. Config.Hud.toggleCommand .. ' to bring it back.' or 'Delivery timer shown.')
    end, false)
end

-- nothing of ours should sit on top of the pause menu, the big map, a fade, or another script's menu
local function hudBlocked()
    if hudOff or IsPauseMenuActive() or IsScreenFadedOut() or IsScreenFadingOut() or IsHudHidden()
        or IsPlayerSwitchInProgress() or IsCutsceneActive() or IsEntityDead(PlayerPedId()) then
        return true
    end
    -- another resource has the mouse (inventory, menus...). Our phone app is fine: we slide beside it.
    if IsNuiFocused() and not appVisible() and S.phone ~= 'open' then return true end
    return false
end

-- on-screen timer: our own page only (never the phone), and only when something changed
CreateThread(function()
    local last, lastShift = nil, nil
    while true do
        local sleep = 1000
        if Config.Hud.enabled then
            local data = hudPayload()
            if data and hudBlocked() then data = nil end
            local shift = data and appVisible() or false -- 17mov phone or the built-in one
            local key = data and json.encode(data) or 'none'
            if key ~= last or shift ~= lastShift then
                SendNUIMessage({ action = 'hud', data = data, shift = shift, cfg = Config.Hud })
                last, lastShift = key, shift
            end
            if data or hudPayload() then sleep = 150 end -- react quickly when the pause menu opens
        end
        Wait(sleep)
    end
end)

---------------------------------------------------------------------
-- Hot zones: map blips while you're clocked in, alerts, and your status for the app
---------------------------------------------------------------------
local zoneBlips, zoneList, zoneAt, inZone = {}, {}, 0, nil

local function clearZoneBlips()
    for _, b in pairs(zoneBlips) do
        if DoesBlipExist(b.area) then RemoveBlip(b.area) end
        if DoesBlipExist(b.icon) then RemoveBlip(b.icon) end
    end
    zoneBlips = {}
end

local function drawZoneBlips()
    clearZoneBlips()
    if not S.online then return end
    local B = Config.HotZones.blip
    for _, z in ipairs(zoneList) do
        local area = AddBlipForRadius(z.x, z.y, 0.0, z.radius)
        SetBlipColour(area, B.color)
        SetBlipAlpha(area, B.alpha)
        local icon = AddBlipForCoord(z.x, z.y, 0.0)
        SetBlipSprite(icon, B.sprite)
        SetBlipColour(icon, B.color)
        SetBlipScale(icon, 0.8)
        SetBlipAsShortRange(icon, false)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(('Hot zone: %s (+$%d)'):format(z.name, z.bonus))
        EndTextCommandSetBlipName(icon)
        zoneBlips[#zoneBlips + 1] = { area = area, icon = icon }
    end
end

local function zonesForNui()
    local out, elapsed = {}, math.floor((GetGameTimer() - zoneAt) / 1000)
    for _, z in ipairs(zoneList) do
        out[#out + 1] = { name = z.name, x = z.x, y = z.y, radius = z.radius, bonus = z.bonus, endsIn = math.max(0, z.endsIn - elapsed) }
    end
    return out
end

local function applyZones(v)
    zoneList, zoneAt = (v and v.list) or {}, GetGameTimer()
    drawZoneBlips()
    nui('zones', { list = zonesForNui(), peak = v and v.peak or false })
end

AddStateBagChangeHandler('ddHotZones', 'global', function(_, _, value) applyZones(value) end)
CreateThread(function()
    while not GlobalState do Wait(100) end
    applyZones(GlobalState.ddHotZones)
end)

RegisterNetEvent('nrp-doordrop:client:zoneAlert', function(msg, kind)
    lib.notify({ title = kind == 'hot' and 'Hot zone' or Config.AppName, description = msg,
        type = kind == 'hot' and 'success' or 'inform', icon = kind == 'hot' and 'fire' or 'snowflake' })
end)

-- where you stand: inside a hot zone, or how far the nearest one is
CreateThread(function()
    local wasOnline = false
    while true do
        local sleep = 3000
        if S.online ~= wasOnline then wasOnline = S.online drawZoneBlips() end
        if Config.HotZones.enabled and (S.online or appVisible()) then
            sleep = 2000
            local me = GetEntityCoords(PlayerPedId())
            local here, nearest, nearestD = nil, nil, nil
            for _, z in ipairs(zoneList) do
                local d = #(me.xy - vector2(z.x, z.y))
                if d <= z.radius then here = z end
                local edge = math.max(0, d - z.radius)
                if not nearestD or edge < nearestD then nearest, nearestD = z, edge end
            end
            local name = here and here.name or nil
            if not S.online then inZone = name end -- no alerts while clocked out
            if name ~= inZone then
                if name then
                    lib.notify({ title = 'Hot zone', icon = 'fire', type = 'success',
                        description = ('You\'re in %s. Orders come faster here, +$%d each.'):format(here.name, here.bonus) })
                elseif inZone then
                    lib.notify({ title = Config.AppName, description = ('You left the %s hot zone.'):format(inZone) })
                end
                inZone = name
            end
            nui('zoneStatus', {
                inZone = here and { name = here.name, bonus = here.bonus, endsIn = here.endsIn - math.floor((GetGameTimer() - zoneAt) / 1000) } or nil,
                nearest = (not here and nearest) and { name = nearest.name, bonus = nearest.bonus,
                    miles = math.floor(nearestD * Config.RoadFactor / MILE * 10 + 0.5) / 10 } or nil,
                zones = zonesForNui(),
            })
        end
        Wait(sleep)
    end
end)

---------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------
RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    cleanupOrder()
    S.offer = nil
    setPhone('closed')
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    cleanupOrder()
    cleanupCourier()
    clearTrackBlip()
    SetNuiFocus(false, false)
    if phoneApp.registered then
        pcall(function()
            exports[Phone.Resource]:RemoveApplication({ name = Phone.AppName, resourceName = res })
        end)
    end
end)
