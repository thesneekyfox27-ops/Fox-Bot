--[[ nrp-movingjob | client/carry.lua
     Prop handling: lifting cargo, stacking it in the van, setting it down.

     Nothing here ever re-parents a prop. Every hand-off deletes the old entity
     and spawns a fresh one at the destination. Re-parenting is what left props
     welded to the hand: if the detach or the re-attach failed, the object was
     still on the ped but the script had already forgotten about it, so the next
     pickup stacked a second prop on top of the first.
]]

Carry = {
    prop       = nil,   -- entity currently in hand
    cargoIdx   = nil,   -- index into Config.Cargo
    dropHeight = 0.0    -- highest Z reached while carrying, for damage checks
}

local loadedDicts = {}

local function requestDict(dict)
    if loadedDicts[dict] then return true end
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 3000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Wait(10) end
    loadedDicts[dict] = HasAnimDictLoaded(dict)
    return loadedDicts[dict]
end

local function requestModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if HasModelLoaded(hash) then return hash end
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(10) end
    return HasModelLoaded(hash) and hash or nil
end

function Carry.weightOf(cargoIdx)
    local cargo = Config.Cargo[cargoIdx]
    return Config.Weights[cargo and cargo.weight or 'light'] or Config.Weights.light
end

function Carry.isCarrying()
    return Carry.prop ~= nil and DoesEntityExist(Carry.prop)
end

--- Delete every cargo-model object currently attached to the player.
--- This is the backstop against a prop the script has lost track of. It runs
--- before each lift and on every job exit, so a welded prop cannot survive
--- into the next pickup.
function Carry.purge()
    local ped = PlayerPedId()
    local models = {}
    for _, cargo in ipairs(Config.Cargo) do
        models[joaat(cargo.model)] = true
    end

    for _, obj in ipairs(GetGamePool('CObject')) do
        if DoesEntityExist(obj)
            and models[GetEntityModel(obj)]
            and IsEntityAttachedToEntity(obj, ped)
        then
            DetachEntity(obj, true, true)
            DeleteEntity(obj)
        end
    end

    Carry.prop = nil
    Carry.cargoIdx = nil
end

--- First cargo entry whose model actually exists, cached. Used as a stand-in
--- when a configured model turns out to be invalid.
local fallbackIdx
local function getFallback()
    if fallbackIdx ~= nil then return fallbackIdx end
    for i, cargo in ipairs(Config.Cargo) do
        if IsModelInCdimage(joaat(cargo.model)) then
            fallbackIdx = i
            return i
        end
    end
    fallbackIdx = false
    return false
end

--- Spawn a cargo prop as a networked object so the rest of the crew sees it.
--- A bad model would otherwise soft-lock the contract - the piece could never
--- be picked up, so the job could never reach a full load. Substituting a
--- valid prop is the wrong model on screen, but the job still finishes.
function Carry.spawnProp(cargoIdx, coords, heading)
    local cargo = Config.Cargo[cargoIdx]
    if not cargo then return nil end

    if not IsModelInCdimage(joaat(cargo.model)) then
        local fb = getFallback()
        if not fb then return nil end
        print(('[nrp-movingjob] cargo %d (%s) has an invalid model \'%s\' - '
            .. 'substituting \'%s\'. Fix the entry in shared/config.lua.')
            :format(cargoIdx, cargo.label, cargo.model, Config.Cargo[fb].model))
        cargo = Config.Cargo[fb]
    end

    local hash = requestModel(cargo.model)
    if not hash then return nil end

    local obj = CreateObject(hash, coords.x, coords.y, coords.z, true, true, false)
    SetModelAsNoLongerNeeded(hash)
    if heading then SetEntityHeading(obj, heading) end
    SetEntityAsMissionEntity(obj, true, true)
    return obj
end

--- Put a prop in the player's hands using the proven attach signature for the
--- box-carry animation. pos/rot come from Config.Cargo[i].carry.
function Carry.attachToHand(obj, cargoIdx)
    local cargo = Config.Cargo[cargoIdx]
    local c = cargo.carry
    local ped = PlayerPedId()
    local bone = GetPedBoneIndex(ped, c.bone or Config.CarryBone)

    AttachEntityToEntity(obj, ped, bone,
        c.pos.x, c.pos.y, c.pos.z,
        c.rot.x, c.rot.y, c.rot.z,
        true,    -- p9
        true,    -- useSoftPinning
        false,   -- collision off while held
        true,    -- isPed
        1,       -- rotation order
        true)    -- sync rotation
end

--- Lift a piece of cargo into the player's hands.
--- `fromEntity` is the prop being picked up (pallet stack or van slot); it is
--- deleted, and a fresh one is spawned in hand.
function Carry.lift(cargoIdx, fromEntity)
    if Carry.isCarrying() then return false end
    local cargo = Config.Cargo[cargoIdx]
    if not cargo then return false end

    local weight = Carry.weightOf(cargoIdx)

    if not lib.progressCircle({
        duration = weight.liftMs,
        label = ('Lifting %s'):format(cargo.label),
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'anim@heists@box_carry@', clip = 'idle' }
    }) then
        return false
    end

    -- Clear anything left welded on before adding another.
    Carry.purge()

    if fromEntity and DoesEntityExist(fromEntity) then
        DetachEntity(fromEntity, true, true)
        DeleteEntity(fromEntity)
    end

    local ped = PlayerPedId()
    local obj = Carry.spawnProp(cargoIdx, GetEntityCoords(ped))
    if not obj then return false end

    Carry.attachToHand(obj, cargoIdx)

    local dict = weight.dict
    if requestDict(dict) then
        TaskPlayAnim(ped, dict, weight.clip, 3.0, 3.0, -1, 49, 0, false, false, false)
    end

    Carry.prop = obj
    Carry.cargoIdx = cargoIdx
    Carry.dropHeight = GetEntityCoords(ped).z
    Carry.startLoop()
    return true
end

--- Release whatever is in hand. With coords, the prop is left standing there;
--- without, it is destroyed.
function Carry.drop(placeCoords, placeRot)
    if not Carry.isCarrying() then
        Carry.purge()
        return nil
    end

    local held = Carry.prop
    local cargoIdx = Carry.cargoIdx
    local ped = PlayerPedId()

    -- Clear our own bookkeeping first so the carry loop stops this frame.
    Carry.prop = nil
    Carry.cargoIdx = nil

    DetachEntity(held, true, true)
    DeleteEntity(held)
    ClearPedTasks(ped)
    SetPedMoveRateOverride(ped, 1.0)

    if not placeCoords then
        Carry.purge()
        return nil
    end

    local obj = Carry.spawnProp(cargoIdx, placeCoords)
    if obj then
        if placeRot then
            SetEntityRotation(obj, placeRot.x, placeRot.y, placeRot.z, 2, true)
        end
        PlaceObjectOnGroundProperly(obj)
        FreezeEntityPosition(obj, true)
    end

    Carry.purge()
    return obj
end

--- Stack the carried item into a van cargo slot. The held prop is destroyed and
--- a new one is created already attached to the van, so there is no window
--- where the object belongs to both.
function Carry.stow(vehicle, slotIndex)
    if not Carry.isCarrying() then return nil end
    if not vehicle or not DoesEntityExist(vehicle) then return nil end

    local cargoIdx = Carry.cargoIdx
    local cargo = Config.Cargo[cargoIdx]
    local weight = Carry.weightOf(cargoIdx)
    local slot = Config.Van.slots[slotIndex]
    if not slot then return nil end

    if not lib.progressCircle({
        duration = weight.setMs,
        label = ('Loading %s'):format(cargo.label),
        position = 'bottom',
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'anim@heists@box_carry@', clip = 'idle' }
    }) then
        return nil
    end

    -- The player may have been knocked out of the carry during the bar.
    if not Carry.isCarrying() then return nil end

    local held = Carry.prop
    local ped = PlayerPedId()

    Carry.prop = nil
    Carry.cargoIdx = nil

    DetachEntity(held, true, true)
    DeleteEntity(held)
    ClearPedTasks(ped)
    SetPedMoveRateOverride(ped, 1.0)
    Carry.purge()

    local stack = cargo.stack or {}
    local rot = stack.rot or vector3(0.0, 0.0, 0.0)
    local z = slot.z + (stack.z or 0.0)

    local obj = Carry.spawnProp(cargoIdx, GetEntityCoords(vehicle))
    if not obj then return nil end

    AttachEntityToEntity(obj, vehicle, 0,
        slot.x, slot.y, z,
        rot.x, rot.y, rot.z,
        true, true, false, false, 1, true)

    return obj
end

--- Pull a stowed item back out of the van and into the hands.
function Carry.unstow(entity, cargoIdx)
    if Carry.isCarrying() then return false end
    return Carry.lift(cargoIdx, entity)
end

--- Set the carried item down on a doorstep spot.
function Carry.place(coords, heading)
    if not Carry.isCarrying() then return nil end
    local cargo = Config.Cargo[Carry.cargoIdx]
    local weight = Carry.weightOf(Carry.cargoIdx)

    if not lib.progressCircle({
        duration = weight.setMs,
        label = ('Setting down %s'):format(cargo.label),
        position = 'bottom',
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'anim@heists@box_carry@', clip = 'idle' }
    }) then
        return nil
    end

    if not Carry.isCarrying() then return nil end
    return Carry.drop(coords, vector3(0.0, 0.0, heading or 0.0))
end

--- Fragile cargo doesn't like being carried off a roof.
function Carry.damageCheck()
    if Carry.cargoIdx == nil then return false end
    local cargo = Config.Cargo[Carry.cargoIdx]
    if cargo.weight ~= 'fragile' then return false end
    local z = GetEntityCoords(PlayerPedId()).z
    if Carry.dropHeight - z > 4.0 then
        return true
    end
    if z > Carry.dropHeight then Carry.dropHeight = z end
    return false
end

--- While carrying: keep the anim alive, slow the walk, block sprinting,
--- weapons and vehicles.
function Carry.startLoop()
    CreateThread(function()
        local weight = Carry.weightOf(Carry.cargoIdx)
        while Carry.isCarrying() do
            local ped = PlayerPedId()

            SetPedMoveRateOverride(ped, weight.speed)
            DisableControlAction(0, 21, true)   -- sprint
            DisableControlAction(0, 22, true)   -- jump
            DisableControlAction(0, 23, true)   -- enter vehicle
            DisableControlAction(0, 24, true)   -- attack
            DisableControlAction(0, 25, true)   -- aim
            DisableControlAction(0, 37, true)   -- weapon wheel
            DisablePlayerFiring(PlayerId(), true)

            if not IsEntityPlayingAnim(ped, weight.dict, weight.clip, 3) then
                if requestDict(weight.dict) then
                    TaskPlayAnim(ped, weight.dict, weight.clip, 3.0, 3.0, -1, 49, 0, false, false, false)
                end
            end

            if IsPedInAnyVehicle(ped, false) or IsPedRagdoll(ped) or IsPedDeadOrDying(ped, true) then
                Carry.drop(GetEntityCoords(ped))
                TriggerEvent('nrp-movingjob:client:cargoDropped')
                break
            end

            Wait(0)
        end

        local ped = PlayerPedId()
        ClearPedTasks(ped)
        SetPedMoveRateOverride(ped, 1.0)
    end)
end

-- ---------------------------------------------------------------------------
-- offset tuner
-- ---------------------------------------------------------------------------
--- /carrytune [index]
---
--- Puts a cargo piece in your hand and lets you nudge it into place live, then
--- prints the exact carry block to paste into shared/config.lua. Guessing these
--- numbers blind never works - every prop has its own pivot.
---
---   Arrow keys      move forward/back and left/right
---   Page Up/Down    move up/down
---   Num 4 / Num 6   yaw
---   Num 8 / Num 2   pitch
---   Num 7 / Num 9   roll
---   Left Shift      hold for coarse steps
---   Enter           print the values and finish
---   Backspace       cancel
RegisterCommand('carrytune', function(_, args)
    local idx = tonumber(args[1] or '1') or 1
    local cargo = Config.Cargo[idx]
    if not cargo then
        return lib.notify({
            title = 'Carry tuner',
            description = ('No cargo at index %d. There are %d.'):format(idx, #Config.Cargo),
            type = 'error'
        })
    end

    Carry.purge()

    local ped = PlayerPedId()
    local obj = Carry.spawnProp(idx, GetEntityCoords(ped))
    if not obj then return end

    local c = cargo.carry
    local pos = { x = c.pos.x, y = c.pos.y, z = c.pos.z }
    local rot = { x = c.rot.x, y = c.rot.y, z = c.rot.z }
    local bone = c.bone or Config.CarryBone

    if requestDict('anim@heists@box_carry@') then
        TaskPlayAnim(ped, 'anim@heists@box_carry@', 'idle', 3.0, 3.0, -1, 49, 0, false, false, false)
    end

    local function apply()
        AttachEntityToEntity(obj, PlayerPedId(), GetPedBoneIndex(PlayerPedId(), bone),
            pos.x, pos.y, pos.z, rot.x, rot.y, rot.z,
            true, true, false, true, 1, true)
    end
    apply()

    lib.showTextUI(
        ('**Tuning %s**  \n'):format(cargo.label) ..
        'Arrows move · PgUp/PgDn height  \n' ..
        'Num 4/6 yaw · 8/2 pitch · 7/9 roll  \n' ..
        'Shift = coarse · Enter save · Backspace cancel',
        { position = 'right-center' }
    )

    CreateThread(function()
        while true do
            local coarse = IsControlPressed(0, 21)
            local ps = coarse and 0.02 or 0.004
            local rs = coarse and 5.0 or 1.0
            local moved = false

            if IsControlPressed(0, 172) then pos.y = pos.y + ps moved = true end -- up arrow
            if IsControlPressed(0, 173) then pos.y = pos.y - ps moved = true end -- down arrow
            if IsControlPressed(0, 174) then pos.x = pos.x - ps moved = true end -- left arrow
            if IsControlPressed(0, 175) then pos.x = pos.x + ps moved = true end -- right arrow
            if IsControlPressed(0, 10)  then pos.z = pos.z + ps moved = true end -- page up
            if IsControlPressed(0, 11)  then pos.z = pos.z - ps moved = true end -- page down

            if IsControlPressed(0, 108) then rot.z = rot.z - rs moved = true end -- num 4
            if IsControlPressed(0, 109) then rot.z = rot.z + rs moved = true end -- num 6
            if IsControlPressed(0, 111) then rot.x = rot.x - rs moved = true end -- num 8
            if IsControlPressed(0, 112) then rot.x = rot.x + rs moved = true end -- num 2
            if IsControlPressed(0, 117) then rot.y = rot.y - rs moved = true end -- num 7
            if IsControlPressed(0, 118) then rot.y = rot.y + rs moved = true end -- num 9

            if moved then apply() end

            if not IsEntityPlayingAnim(PlayerPedId(), 'anim@heists@box_carry@', 'idle', 3) then
                TaskPlayAnim(PlayerPedId(), 'anim@heists@box_carry@', 'idle', 3.0, 3.0, -1, 49, 0, false, false, false)
            end

            if IsControlJustReleased(0, 191) then -- enter
                local out = ('carry = { pos = vector3(%.3f, %.3f, %.3f), rot = vector3(%.1f, %.1f, %.1f) }')
                    :format(pos.x, pos.y, pos.z, rot.x, rot.y, rot.z)
                print(('[nrp-movingjob] %s  ->  %s'):format(cargo.label, out))
                lib.setClipboard(out)
                lib.notify({
                    title = 'Carry tuner',
                    description = 'Values printed to F8 and copied to your clipboard.',
                    type = 'success'
                })
                break
            end

            if IsControlJustReleased(0, 194) then -- backspace
                break
            end

            Wait(0)
        end

        lib.hideTextUI()
        DetachEntity(obj, true, true)
        DeleteEntity(obj)
        ClearPedTasks(PlayerPedId())
        Carry.purge()
    end)
end, false)

-- ---------------------------------------------------------------------------
-- prop finder
-- ---------------------------------------------------------------------------
--- Candidate household props for moving cargo. Not all of these exist in every
--- build, which is the point - /testprop reports which ones do.
local PROP_CANDIDATES = {
    -- bedside / small tables
    'v_res_d_bedsidetbl', 'v_res_fa_bedsidetbl', 'v_res_m_bedsidetbl',
    'v_res_tre_bedsidetbl', 'v_res_mp_bedsidetbl', 'v_res_bedsidetable',
    'prop_table_03', 'prop_table_03b', 'prop_table_05', 'prop_table_06',
    'prop_side_table_01',
    -- appliances
    'prop_micro_01', 'prop_micro_02', 'prop_washer_01', 'prop_washer_02',
    'prop_fridge_01', 'prop_fridge_03', 'prop_toaster_01', 'prop_cooker_03',
    -- electronics
    'prop_monitor_01a', 'prop_monitor_02', 'prop_printer_01', 'prop_printer_02',
    'prop_tv_flat_01', 'prop_tv_flat_02', 'prop_pc_01a',
    -- misc household
    'prop_toolchest_01', 'prop_toolchest_02', 'prop_crate_02a',
    'prop_box_wood02a_pu', 'prop_paper_box_01', 'prop_ld_suitcase_01',
    'prop_luggage_01a', 'prop_luggage_03a', 'prop_rolled_sock_01',
    'v_res_tt_bed', 'prop_off_chair_01', 'prop_off_chair_05'
}

--- /testprop                 -> test the built-in candidate list
--- /testprop model1 model2   -> test specific names
---
--- Prints which models actually exist in this build, so you are picking from
--- real props instead of guessing and restarting.
RegisterCommand('testprop', function(_, args)
    local list = (#args > 0) and args or PROP_CANDIDATES
    local valid, invalid = {}, 0

    for _, name in ipairs(list) do
        if IsModelInCdimage(joaat(name)) then
            valid[#valid + 1] = name
        else
            invalid = invalid + 1
        end
    end

    print('[nrp-movingjob] ---- valid props ----')
    for _, name in ipairs(valid) do
        print(('  %s'):format(name))
    end
    print(('[nrp-movingjob] %d valid, %d missing, %d tested')
        :format(#valid, invalid, #list))

    lib.notify({
        title = 'Prop finder',
        description = ('%d of %d exist. Full list in F8.'):format(#valid, #list),
        type = #valid > 0 and 'success' or 'error'
    })
end, false)

--- /propview <model>
--- Spawns a model in front of you so you can eyeball its size and shape before
--- committing it to the cargo list.
RegisterCommand('propview', function(_, args)
    local name = args[1]
    if not name then
        return lib.notify({ title = 'Prop viewer', description = 'Give it a model name.', type = 'error' })
    end
    if not IsModelInCdimage(joaat(name)) then
        return lib.notify({ title = 'Prop viewer', description = ('\'%s\' does not exist.'):format(name), type = 'error' })
    end

    local hash = requestModel(name)
    if not hash then return end

    local ped = PlayerPedId()
    local fwd = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.6, 0.0)
    local obj = CreateObject(hash, fwd.x, fwd.y, fwd.z, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)

    lib.notify({ title = 'Prop viewer', description = ('Spawned %s. Gone in 20s.'):format(name), type = 'inform' })
    SetTimeout(20000, function()
        if DoesEntityExist(obj) then DeleteEntity(obj) end
    end)
end, false)

--- Verify every cargo model actually exists. An invalid model would otherwise
--- fail silently at the pallet and soft-lock the contract, since the piece can
--- never be picked up.
CreateThread(function()
    Wait(2000)
    local bad = 0
    for i, cargo in ipairs(Config.Cargo) do
        if not IsModelInCdimage(joaat(cargo.model)) then
            bad = bad + 1
            print(('[nrp-movingjob] Config.Cargo[%d] "%s" - model \'%s\' does not exist. '
                .. 'That piece cannot be picked up; fix the model name.')
                :format(i, cargo.label, cargo.model))
        end
    end
    if bad > 0 then
        print(('[nrp-movingjob] %d invalid cargo model(s). See above.'):format(bad))
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    Carry.purge()
    ClearPedTasks(PlayerPedId())
    SetPedMoveRateOverride(PlayerPedId(), 1.0)
    lib.hideTextUI()
end)
