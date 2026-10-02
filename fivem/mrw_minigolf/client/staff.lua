-- Crazy Golf staff member at the club rental, the map blip, and how you talk to them.

local staffPed, blip, targetSystem = nil, nil, nil

--- nrp-target / ox_target / qb-target if one is running (Config.staff.target), else nil = [E] prompt
function UsingTarget()
    return targetSystem ~= nil
end

local function pickTarget()
    local want = (Config.staff and Config.staff.target) or 'auto'
    if want == 'none' then return nil end
    for _, name in ipairs({ 'nrp-target', 'ox_target', 'qb-target' }) do
        if (want == 'auto' or want == name) and GetResourceState(name) == 'started' then return name end
    end
    return nil
end

local function staffPos()
    local cfg = Config.staff or {}
    return cfg.coords or Config.locate_club
end

local function addTarget()
    if not targetSystem then return end
    local label = (translation['talk_staff'] or 'Talk to %s staff'):format(Config.course_name or 'Minigolf')
    local canInteract = function() return not IsPlayingGolf() end

    local ok, err = pcall(function()
        if targetSystem == 'qb-target' then
            exports['qb-target']:AddTargetEntity(staffPed, {
                options = { { icon = 'fas fa-golf-ball-tee', label = label, action = OpenStartMenu, canInteract = canInteract } },
                distance = 2.5
            })
        else
            exports[targetSystem]:addLocalEntity(staffPed, {
                {
                    name = 'mrw_minigolf_staff', icon = 'fa-solid fa-golf-ball-tee', label = label,
                    distance = 2.5, canInteract = canInteract,
                    onSelect = function() OpenStartMenu() end
                }
            })
        end
    end)
    if not ok then
        print(('^1[mrw_minigolf] could not add %s target to the staff ped: %s - using the [E] prompt^7'):format(targetSystem, tostring(err)))
        targetSystem = nil
    end
end

local function despawnStaff()
    if staffPed and DoesEntityExist(staffPed) then
        if targetSystem == 'qb-target' then
            pcall(function() exports['qb-target']:RemoveTargetEntity(staffPed) end)
        elseif targetSystem then
            pcall(function() exports[targetSystem]:removeLocalEntity(staffPed, 'mrw_minigolf_staff') end)
        end
        DeleteEntity(staffPed)
    end
    staffPed = nil
end

--- Only called once the player is close, so the area (and its ground) is loaded.
local function spawnStaff()
    local cfg = Config.staff or {}
    local pos = staffPos()
    local model = GetHashKey(cfg.model or 'a_f_y_beach_01')

    if not IsModelInCdimage(model) then
        print(('^1[mrw_minigolf] staff ped model "%s" does not exist - set Config.staff.model^7'):format(tostring(cfg.model)))
        return false
    end
    RequestModel(model)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(model) and GetGameTimer() < timeout do Wait(10) end
    if not HasModelLoaded(model) then
        print('^1[mrw_minigolf] staff ped model failed to load: ' .. tostring(cfg.model) .. '^7')
        return false
    end

    -- the configured spot is where a player stands (about 1m above the ground);
    -- only trust the ground probe if it lands near there
    RequestCollisionAtCoord(pos.x, pos.y, pos.z)
    local z = pos.z - 1.0
    local found, ground = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 1.0, false)
    if found and math.abs(ground - (pos.z - 1.0)) < 2.5 then z = ground end

    staffPed = CreatePed(4, model, pos.x, pos.y, z, cfg.heading or 0.0, false, true)
    SetModelAsNoLongerNeeded(model)
    if not staffPed or staffPed == 0 or not DoesEntityExist(staffPed) then
        staffPed = nil
        return false
    end

    SetEntityAsMissionEntity(staffPed, true, true)
    SetBlockingOfNonTemporaryEvents(staffPed, true)
    SetEntityInvincible(staffPed, true)
    SetPedCanRagdoll(staffPed, false)
    SetPedFleeAttributes(staffPed, 0, false)
    SetPedDiesWhenInjured(staffPed, false)
    FreezeEntityPosition(staffPed, true)
    if cfg.scenario then TaskStartScenarioInPlace(staffPed, cfg.scenario, 0, true) end

    addTarget()
    return true
end

-- spawn when you get near the course, remove when you leave
local SPAWN_DIST, DESPAWN_DIST = 80.0, 120.0
local function streamThread()
    targetSystem = pickTarget()
    while true do
        local d = #(GetEntityCoords(PlayerPedId()) - staffPos())
        if d < SPAWN_DIST and not (staffPed and DoesEntityExist(staffPed)) then
            targetSystem = pickTarget()
            if not spawnStaff() then Wait(5000) end
        elseif d > DESPAWN_DIST and staffPed then
            despawnStaff()
        end
        Wait(1000)
    end
end

-- /golfstaff        -> where the staff member is and whether they spawned
-- /golfstaff here   -> print your spot, ready to paste into Config.staff.coords
RegisterCommand('golfstaff', function(_, args)
    local me = GetEntityCoords(PlayerPedId())
    if args[1] == 'here' then
        local line = ('coords = vector3(%.2f, %.2f, %.2f), heading = %.1f,'):format(me.x, me.y, me.z, GetEntityHeading(PlayerPedId()))
        print('[mrw_minigolf] ' .. line)
        Ui:displayNotification('Staff spot printed in F8')
        return
    end
    local pos = staffPos()
    print(('[mrw_minigolf] staff spot %.2f, %.2f, %.2f | you are %.1fm away | spawned: %s | target: %s'):format(
        pos.x, pos.y, pos.z, #(me - pos), tostring(staffPed ~= nil and DoesEntityExist(staffPed)), tostring(targetSystem or 'E prompt')))
    Ui:displayNotification('Staff info printed in F8')
end, false)

local function createBlip()
    local cfg = Config.blip or {}
    if cfg.enabled == false then return end
    local pos = (Config.staff and Config.staff.coords) or Config.locate_club
    blip = AddBlipForCoord(pos.x, pos.y, pos.z)
    SetBlipSprite(blip, cfg.sprite or 109)
    SetBlipColour(blip, cfg.colour or 2)
    SetBlipScale(blip, cfg.scale or 0.8)
    SetBlipAsShortRange(blip, cfg.shortRange ~= false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(cfg.label or Config.course_name or 'Minigolf')
    EndTextCommandSetBlipName(blip)
end

-- the staff member turns to face you as you walk up
local function faceThread()
    while true do
        local sleep = 1000
        if staffPed and DoesEntityExist(staffPed) and not IsPlayingGolf() then
            local me = PlayerPedId()
            local d = #(GetEntityCoords(me) - GetEntityCoords(staffPed))
            if d < 6.0 then
                sleep = 400
                if not IsPedHeadingTowardsPosition(staffPed, GetEntityCoords(me), 30.0) then
                    FreezeEntityPosition(staffPed, false)
                    TaskTurnPedToFaceEntity(staffPed, me, 1200)
                    Wait(1300)
                    FreezeEntityPosition(staffPed, true)
                end
            end
        end
        Wait(sleep)
    end
end

CreateThread(createBlip)
CreateThread(streamThread)
CreateThread(faceThread)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    despawnStaff()
    if blip then RemoveBlip(blip) end
end)
