--[[ nrp-movingjob | client/dolly.lua
     Hand truck. Push it around and stack several pieces on it, instead of
     walking one item at a time.

     Same rule as carry.lua: nothing is ever re-parented. Items move between
     hand, truck, van and doorstep by delete-and-respawn, so a prop can never
     end up owned by two things at once.
]]

Dolly = {
    loaded = true,   -- main.lua checks this to confirm the module is present
    entity = nil,
    items  = {}      -- { { entity = obj, cargoIdx = n } } bottom of stack first
}

print('^2[nrp-movingjob] hand truck module loaded.^7')

local pushing = false

local function requestModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if HasModelLoaded(hash) then return hash end
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(10) end
    return HasModelLoaded(hash) and hash or nil
end

function Dolly.isActive()
    return Dolly.entity ~= nil and DoesEntityExist(Dolly.entity)
end

function Dolly.count()
    return #Dolly.items
end

function Dolly.isFull()
    return #Dolly.items >= Config.Dolly.capacity
end

--- What is on top of the stack, without removing it.
function Dolly.peek()
    return Dolly.items[#Dolly.items]
end

local function attachToPed()
    local a = Config.Dolly.attach
    local ped = PlayerPedId()
    AttachEntityToEntity(Dolly.entity, ped, GetPedBoneIndex(ped, a.bone),
        a.pos.x, a.pos.y, a.pos.z,
        a.rot.x, a.rot.y, a.rot.z,
        true, true, false, true, 1, true)
end

--- Re-seat every item on the truck. Called after any add or remove so the
--- stack stays tidy with no gaps.
local function restack()
    for i, item in ipairs(Dolly.items) do
        local slot = Config.Dolly.slots[i]
        if slot and DoesEntityExist(item.entity) then
            local cargo = Config.Cargo[item.cargoIdx]
            local stack = (cargo and cargo.stack) or {}
            local rot = stack.rot or vector3(0.0, 0.0, 0.0)
            AttachEntityToEntity(item.entity, Dolly.entity, 0,
                slot.x, slot.y, slot.z,
                rot.x, rot.y, rot.z,
                true, true, false, false, 1, true)
        end
    end
end

--- Delete any cargo-model object still attached to the truck but not tracked.
local function purgeUntracked()
    if not Dolly.isActive() then return end
    local tracked = {}
    for _, item in ipairs(Dolly.items) do tracked[item.entity] = true end

    local models = {}
    for _, cargo in ipairs(Config.Cargo) do models[joaat(cargo.model)] = true end

    for _, obj in ipairs(GetGamePool('CObject')) do
        if DoesEntityExist(obj)
            and not tracked[obj]
            and models[GetEntityModel(obj)]
            and IsEntityAttachedToEntity(obj, Dolly.entity)
        then
            DetachEntity(obj, true, true)
            DeleteEntity(obj)
        end
    end
end

-- ---------------------------------------------------------------------------
-- push loop
-- ---------------------------------------------------------------------------
local function startPushing()
    if pushing then return end
    pushing = true

    CreateThread(function()
        local anim = Config.Dolly.anim
        RequestAnimDict(anim.dict)
        local timeout = GetGameTimer() + 3000
        while not HasAnimDictLoaded(anim.dict) and GetGameTimer() < timeout do Wait(10) end

        while Dolly.isActive() do
            local ped = PlayerPedId()

            SetPedMoveRateOverride(ped, Config.Dolly.speed)
            DisableControlAction(0, 21, true)   -- sprint
            DisableControlAction(0, 22, true)   -- jump
            DisableControlAction(0, 23, true)   -- enter vehicle
            DisableControlAction(0, 24, true)   -- attack
            DisableControlAction(0, 25, true)   -- aim
            DisableControlAction(0, 37, true)   -- weapon wheel
            DisablePlayerFiring(PlayerId(), true)

            if HasAnimDictLoaded(anim.dict)
                and not IsEntityPlayingAnim(ped, anim.dict, anim.clip, 3)
            then
                TaskPlayAnim(ped, anim.dict, anim.clip, 3.0, 3.0, -1, 49, 0, false, false, false)
            end

            if IsPedInAnyVehicle(ped, false) or IsPedRagdoll(ped) or IsPedDeadOrDying(ped, true) then
                Dolly.park()
                break
            end

            Wait(0)
        end

        pushing = false
        local ped = PlayerPedId()
        ClearPedTasks(ped)
        SetPedMoveRateOverride(ped, 1.0)
    end)
end

-- ---------------------------------------------------------------------------
-- grab / park
-- ---------------------------------------------------------------------------
--- Take hold of a hand truck.
function Dolly.grab()
    if not Config.Dolly.enabled then return false end
    if Dolly.isActive() then return false end
    if Carry.isCarrying() then return false end

    local hash = requestModel(Config.Dolly.model)
    if not hash then return false end

    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local obj = CreateObject(hash, pos.x, pos.y, pos.z, true, true, false)
    SetModelAsNoLongerNeeded(hash)
    SetEntityAsMissionEntity(obj, true, true)
    SetEntityCollision(obj, false, false)

    Dolly.entity = obj
    Dolly.items = {}
    attachToPed()
    startPushing()
    return true
end

--- Let go of the truck. Anything still on it is destroyed along with it, so
--- callers should unload first if the contents still matter.
function Dolly.park()
    if not Dolly.isActive() then
        Dolly.entity = nil
        Dolly.items = {}
        return
    end

    for _, item in ipairs(Dolly.items) do
        if DoesEntityExist(item.entity) then
            DetachEntity(item.entity, true, true)
            DeleteEntity(item.entity)
        end
    end
    Dolly.items = {}

    local obj = Dolly.entity
    Dolly.entity = nil

    DetachEntity(obj, true, true)
    DeleteEntity(obj)

    local ped = PlayerPedId()
    ClearPedTasks(ped)
    SetPedMoveRateOverride(ped, 1.0)
end

-- ---------------------------------------------------------------------------
-- loading / unloading
-- ---------------------------------------------------------------------------
--- Put a piece onto the truck. `fromEntity` is the source prop (pallet stack
--- or a van slot) and is destroyed.
function Dolly.load(cargoIdx, fromEntity)
    if not Dolly.isActive() then return false end
    if Dolly.isFull() then return false end

    local cargo = Config.Cargo[cargoIdx]
    if not cargo then return false end

    if not lib.progressCircle({
        duration = Config.Dolly.loadMs,
        label = ('Stacking %s'):format(cargo.label),
        position = 'bottom',
        canCancel = true,
        disable = { move = true, car = true, combat = true }
    }) then
        return false
    end

    if not Dolly.isActive() or Dolly.isFull() then return false end

    if fromEntity and DoesEntityExist(fromEntity) then
        DetachEntity(fromEntity, true, true)
        DeleteEntity(fromEntity)
    end

    local obj = Carry.spawnProp(cargoIdx, GetEntityCoords(Dolly.entity))
    if not obj then return false end

    Dolly.items[#Dolly.items + 1] = { entity = obj, cargoIdx = cargoIdx }
    restack()
    purgeUntracked()
    return true
end

--- Take the top piece off the truck. Returns its cargo index; the prop is
--- destroyed, so the caller spawns whatever comes next.
function Dolly.unload()
    if not Dolly.isActive() then return nil end
    if #Dolly.items == 0 then return nil end

    local top = Dolly.items[#Dolly.items]
    local cargo = Config.Cargo[top.cargoIdx]

    if not lib.progressCircle({
        duration = Config.Dolly.unloadMs,
        label = ('Taking off %s'):format(cargo and cargo.label or 'item'),
        position = 'bottom',
        canCancel = true,
        disable = { move = true, car = true, combat = true }
    }) then
        return nil
    end

    if not Dolly.isActive() or #Dolly.items == 0 then return nil end

    top = table.remove(Dolly.items, #Dolly.items)
    if DoesEntityExist(top.entity) then
        DetachEntity(top.entity, true, true)
        DeleteEntity(top.entity)
    end
    restack()
    return top.cargoIdx
end

-- ---------------------------------------------------------------------------
-- offset tuner
-- ---------------------------------------------------------------------------
--- /dollytune - same controls as /carrytune, for how the truck sits in front
--- of you while pushing.
RegisterCommand('dollytune', function()
    local hash = requestModel(Config.Dolly.model)
    if not hash then
        return lib.notify({
            title = 'Dolly tuner',
            description = ('\'%s\' does not exist.'):format(Config.Dolly.model),
            type = 'error'
        })
    end

    local ped = PlayerPedId()
    local pos0 = GetEntityCoords(ped)
    local obj = CreateObject(hash, pos0.x, pos0.y, pos0.z, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    SetEntityCollision(obj, false, false)

    local a = Config.Dolly.attach
    local pos = { x = a.pos.x, y = a.pos.y, z = a.pos.z }
    local rot = { x = a.rot.x, y = a.rot.y, z = a.rot.z }

    local anim = Config.Dolly.anim
    RequestAnimDict(anim.dict)
    local timeout = GetGameTimer() + 3000
    while not HasAnimDictLoaded(anim.dict) and GetGameTimer() < timeout do Wait(10) end
    TaskPlayAnim(PlayerPedId(), anim.dict, anim.clip, 3.0, 3.0, -1, 49, 0, false, false, false)

    local function apply()
        AttachEntityToEntity(obj, PlayerPedId(), GetPedBoneIndex(PlayerPedId(), a.bone),
            pos.x, pos.y, pos.z, rot.x, rot.y, rot.z,
            true, true, false, true, 1, true)
    end
    apply()

    lib.showTextUI(
        '**Tuning hand truck**  \n' ..
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

            if IsControlPressed(0, 172) then pos.y = pos.y + ps moved = true end
            if IsControlPressed(0, 173) then pos.y = pos.y - ps moved = true end
            if IsControlPressed(0, 174) then pos.x = pos.x - ps moved = true end
            if IsControlPressed(0, 175) then pos.x = pos.x + ps moved = true end
            if IsControlPressed(0, 10)  then pos.z = pos.z + ps moved = true end
            if IsControlPressed(0, 11)  then pos.z = pos.z - ps moved = true end

            if IsControlPressed(0, 108) then rot.z = rot.z - rs moved = true end
            if IsControlPressed(0, 109) then rot.z = rot.z + rs moved = true end
            if IsControlPressed(0, 111) then rot.x = rot.x - rs moved = true end
            if IsControlPressed(0, 112) then rot.x = rot.x + rs moved = true end
            if IsControlPressed(0, 117) then rot.y = rot.y - rs moved = true end
            if IsControlPressed(0, 118) then rot.y = rot.y + rs moved = true end

            if moved then apply() end

            if not IsEntityPlayingAnim(PlayerPedId(), anim.dict, anim.clip, 3) then
                TaskPlayAnim(PlayerPedId(), anim.dict, anim.clip, 3.0, 3.0, -1, 49, 0, false, false, false)
            end

            if IsControlJustReleased(0, 191) then
                local out = ('attach = { bone = %d, pos = vector3(%.3f, %.3f, %.3f), rot = vector3(%.1f, %.1f, %.1f) }')
                    :format(a.bone, pos.x, pos.y, pos.z, rot.x, rot.y, rot.z)
                print(('[nrp-movingjob] hand truck  ->  %s'):format(out))
                lib.setClipboard(out)
                lib.notify({
                    title = 'Dolly tuner',
                    description = 'Values printed to F8 and copied to your clipboard.',
                    type = 'success'
                })
                break
            end

            if IsControlJustReleased(0, 194) then break end
            Wait(0)
        end

        lib.hideTextUI()
        DetachEntity(obj, true, true)
        DeleteEntity(obj)
        ClearPedTasks(PlayerPedId())
    end)
end, false)

CreateThread(function()
    Wait(2500)
    if Config.Dolly.enabled and not IsModelInCdimage(joaat(Config.Dolly.model)) then
        print(('[nrp-movingjob] Config.Dolly model \'%s\' does not exist. '
            .. 'The hand truck will not spawn.'):format(Config.Dolly.model))
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    Dolly.park()
    lib.hideTextUI()
end)
