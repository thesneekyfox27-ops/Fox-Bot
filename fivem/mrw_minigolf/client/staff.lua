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

local function spawnStaff()
    local cfg = Config.staff or {}
    local pos = cfg.coords or Config.locate_club
    local model = GetHashKey(cfg.model or 'a_f_y_beach_01')

    RequestModel(model)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(model) and GetGameTimer() < timeout do Wait(10) end
    if not HasModelLoaded(model) then
        print('^1[mrw_minigolf] staff ped model failed to load: ' .. tostring(cfg.model) .. '^7')
        return
    end

    -- the configured spot is where a player stands (about 1m above the ground)
    local z = pos.z - 1.0
    local found, ground = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 1.0, false)
    if found then z = ground end

    staffPed = CreatePed(4, model, pos.x, pos.y, z, cfg.heading or 0.0, false, true)
    SetModelAsNoLongerNeeded(model)
    SetEntityAsMissionEntity(staffPed, true, true)
    SetBlockingOfNonTemporaryEvents(staffPed, true)
    SetEntityInvincible(staffPed, true)
    FreezeEntityPosition(staffPed, true)
    SetPedCanRagdoll(staffPed, false)
    SetPedFleeAttributes(staffPed, 0, false)
    if cfg.scenario then TaskStartScenarioInPlace(staffPed, cfg.scenario, 0, true) end

    targetSystem = pickTarget()
    if not targetSystem then return end

    local label = (translation['talk_staff'] or 'Talk to %s staff'):format(Config.course_name or 'Minigolf')
    local canInteract = function() return not IsPlayingGolf() end

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
end

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

CreateThread(function()
    createBlip()
    spawnStaff()
    faceThread()
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    if staffPed and DoesEntityExist(staffPed) then
        if targetSystem == 'qb-target' then
            pcall(function() exports['qb-target']:RemoveTargetEntity(staffPed) end)
        elseif targetSystem then
            pcall(function() exports[targetSystem]:removeLocalEntity(staffPed, 'mrw_minigolf_staff') end)
        end
        DeleteEntity(staffPed)
    end
    if blip then RemoveBlip(blip) end
end)
