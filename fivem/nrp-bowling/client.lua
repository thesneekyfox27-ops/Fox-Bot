-- ============================================================
--  nrp-bowling - client
--  Front desk, lane flow, aiming, the roll itself and pin counting.
-- ============================================================

local QBCore = exports['qb-core']:GetCoreObject()

local myLane   = nil    -- lane id we're on
local laneView = nil    -- last score sheet from the server
local phase    = nil    -- nil | 'lobby' | 'wait' | 'pickup' | 'aim' | 'rolling'
local turn     = nil    -- { frame, roll, standing, reset, frames }
local rack     = {}     -- [i] = { obj, spot, standing }
local ball     = nil
local cam      = nil
local lastSeq  = 0
local deskOpen = false
local ballPrompt = false

local B = Config.Ball

-- ------------------------------------------------------------
--  Helpers
-- ------------------------------------------------------------
local function notify(msg, kind) QBCore.Functions.Notify(msg, kind or 'primary') end

local function loadModel(name)
    local m = joaat(name)
    if not IsModelInCdimage(m) then return nil end
    RequestModel(m)
    local t = GetGameTimer() + 5000
    while not HasModelLoaded(m) and GetGameTimer() < t do Wait(10) end
    return HasModelLoaded(m) and m or nil
end

local function loadDict(d)
    RequestAnimDict(d)
    local t = GetGameTimer() + 3000
    while not HasAnimDictLoaded(d) and GetGameTimer() < t do Wait(10) end
    return d
end

local function del(ent)
    if ent and DoesEntityExist(ent) then
        SetEntityAsMissionEntity(ent, true, true)
        DeleteEntity(ent)
    end
end

local function headingOf(dx, dy) return (math.deg(math.atan(-dx, dy)) + 360.0) % 360.0 end

-- Lane geometry: approach A, head pin H, unit forward `dir`, unit right `lat`, length D
local geoCache = {}
local function geo(id)
    if geoCache[id] then return geoCache[id] end
    local L = Config.Lanes[id]
    local A, H = L.approach, L.pins[1]
    local dx, dy = H.x - A.x, H.y - A.y
    local D = math.sqrt(dx * dx + dy * dy)
    local g = {
        A = vector3(A.x, A.y, A.z), H = H, D = D,
        dir = vector2(dx / D, dy / D), lat = vector2(dy / D, -dx / D),
        laneZ = H.z,
    }
    geoCache[id] = g
    return g
end

local function along(g, fwd, side, z)
    local p = g.A.xy + g.dir * fwd + g.lat * side
    return vector3(p.x, p.y, z or g.laneZ)
end

local function rotate(v, deg)
    local r = math.rad(deg)
    local c, s = math.cos(r), math.sin(r)
    return vector2(v.x * c - v.y * s, v.x * s + v.y * c)
end

-- ------------------------------------------------------------
--  UI
-- ------------------------------------------------------------
local function ui(msg) SendNUIMessage(msg) end

local function controls(kind, extra)
    ui({ action = 'controls', kind = kind, extra = extra })
end

local function updateControls()
    if not myLane then return controls(nil) end
    local v = laneView
    if phase == 'lobby' then
        local isOwner = false
        if v then for _, p in ipairs(v.players) do if p.owner and p.src == GetPlayerServerId(PlayerId()) then isOwner = true end end end
        return controls(isOwner and 'lobbyOwner' or 'lobby', { lane = myLane, players = v and #v.players or 1 })
    elseif phase == 'wait' then
        local who = '...'
        if v and v.turn then for _, p in ipairs(v.players) do if p.src == v.turn then who = p.name end end end
        return controls('wait', { lane = myLane, who = who })
    end
    controls(phase, { lane = myLane, frame = turn and turn.frame, roll = turn and turn.roll, standing = turn and turn.standing })
end

-- ------------------------------------------------------------
--  Pins
-- ------------------------------------------------------------
local function clearRack()
    for _, p in ipairs(rack) do del(p.obj) end
    rack = {}
end

local function spawnRack(id)
    clearRack()
    local m = loadModel('prop_bowling_pin')
    if not m then return end
    for i, spot in ipairs(Config.Lanes[id].pins) do
        local obj = CreateObject(m, spot.x, spot.y, spot.z, true, true, false)
        SetEntityRotation(obj, 0.0, 0.0, 0.0, 2, true)
        SetEntityCoordsNoOffset(obj, spot.x, spot.y, spot.z, false, false, false)
        FreezeEntityPosition(obj, true)
        rack[i] = { obj = obj, spot = spot, standing = true }
    end
    SetModelAsNoLongerNeeded(m)
end

local function releasePins()
    for _, p in ipairs(rack) do
        if p.standing and DoesEntityExist(p.obj) then
            FreezeEntityPosition(p.obj, false)
            ActivatePhysics(p.obj)
        end
    end
end

local function isDown(p)
    if not DoesEntityExist(p.obj) then return true end
    local pos = GetEntityCoords(p.obj)
    local rot = GetEntityRotation(p.obj, 2)
    if math.abs(rot.x) > 20.0 or math.abs(rot.y) > 20.0 then return true end   -- tipped over
    if pos.z < p.spot.z - 0.25 then return true end                          -- fell into the pit
    if #(pos.xy - p.spot.xy) > 1.2 then return true end                      -- knocked off the deck
    return false
end

-- count pins that fell this ball, sweep them away, stand the rest back up
local function countAndSweep()
    local knocked = 0
    for _, p in ipairs(rack) do
        if p.standing then
            if isDown(p) then
                knocked = knocked + 1
                p.standing = false
                del(p.obj)
            else
                local pos = GetEntityCoords(p.obj)
                SetEntityRotation(p.obj, 0.0, 0.0, 0.0, 2, true)
                SetEntityCoordsNoOffset(p.obj, pos.x, pos.y, p.spot.z, false, false, false)
                FreezeEntityPosition(p.obj, true)
            end
        end
    end
    return knocked
end

-- ------------------------------------------------------------
--  Camera
-- ------------------------------------------------------------
local function camOn()
    if not cam then
        cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
        SetCamFov(cam, 55.0)
        RenderScriptCams(true, true, 600, true, false)
    end
end

local function camOff()
    if cam then
        RenderScriptCams(false, true, 600, true, false)
        DestroyCam(cam, false)
        cam = nil
    end
end

local function camAt(pos, look)
    SetCamCoord(cam, pos.x, pos.y, pos.z)
    PointCamAtCoord(cam, look.x, look.y, look.z)
end

-- ------------------------------------------------------------
--  Aim + throw
-- ------------------------------------------------------------
local ANIM = 'weapons@projectile@'

local function holdBall(ped)
    if not ball or not DoesEntityExist(ball) then
        local m = loadModel('prop_bowling_ball')
        if not m then return end
        local c = GetEntityCoords(ped)
        ball = CreateObject(m, c.x, c.y, c.z, true, true, false)
        SetModelAsNoLongerNeeded(m)
    end
    AttachEntityToEntity(ball, ped, GetPedBoneIndex(ped, 57005), 0.09, 0.03, -0.02, -78.0, 13.0, 28.0, false, true, true, true, 0, true)
end

-- dots showing where the ball will go (aim + hook at medium power)
local function drawGuide(g, offset, aim, spin)
    local d = rotate(g.dir, aim)
    local latSpeed = (d.x * g.lat.x + d.y * g.lat.y)   -- sideways share of the aim
    local speed = (B.minSpeed + B.maxSpeed) / 2
    local side, sideV, fwd = offset, latSpeed * speed, 1.2
    local fwdV = speed * math.sqrt(math.max(0.0, 1 - latSpeed * latSpeed))
    local dt = 0.05
    local last = along(g, fwd, side, g.laneZ + 0.03)
    for i = 1, 400 do
        if fwd > g.D then break end
        if fwd > g.D * 0.4 then sideV = sideV + spin * B.maxHook * dt end
        fwd, side = fwd + fwdV * dt, side + sideV * dt
        if i % 6 == 0 then
            local p = along(g, fwd, side, g.laneZ + 0.03)
            local off = math.abs(side) > Config.LaneHalfWidth
            DrawLine(last.x, last.y, last.z, p.x, p.y, p.z, off and 255 or 242, off and 80 or 178, off and 80 or 61, 200)
            last = p
            if off then break end
        end
    end
end

local function sweetError(power)
    local a, b = B.sweetSpot[1], B.sweetSpot[2]
    if power >= a and power <= b then return 0.0 end
    local dist = power < a and (a - power) / a or (power - b) / (1 - b)
    local e = B.maxError * math.min(1.0, dist)
    return (math.random() < 0.5 and -e or e)
end

local function placePed(ped, g, offset, aim)
    local p = along(g, 0.0, offset, g.A.z)
    SetEntityCoords(ped, p.x, p.y, p.z, false, false, false, false)
    local d = rotate(g.dir, aim)
    SetEntityHeading(ped, headingOf(d.x, d.y))
end

-- the roll: scripted down the lane, real physics from just before the pins
local function roll(g, offset, aim, spin, power, err)
    local ped = PlayerPedId()
    phase = 'rolling'
    updateControls()

    TaskPlayAnim(ped, loadDict(ANIM), 'throw_l_fb_stand', 8.0, -8.0, 900, 48, 0, false, false, false)
    Wait(320)
    DetachEntity(ball, true, false)
    local start = along(g, 1.2, offset, g.laneZ + 0.13)
    SetEntityCoordsNoOffset(ball, start.x, start.y, start.z, false, false, false)
    FreezeEntityPosition(ball, false)

    local speed = B.minSpeed + (B.maxSpeed - B.minSpeed) * power
    local d = rotate(g.dir, aim + err)
    local latShare = d.x * g.lat.x + d.y * g.lat.y
    local fwdV = speed * math.sqrt(math.max(0.0, 1 - latShare * latShare))
    local sideV = latShare * speed
    local gutter, gutterSide, impact = false, 0, false
    local t0, impactAt, slowSince = GetGameTimer(), nil, nil

    while true do
        Wait(0)
        DisableAllControlActions(0)
        local dt = GetFrameTime()
        local pos = GetEntityCoords(ball)
        local rel = pos.xy - g.A.xy
        local prog = rel.x * g.dir.x + rel.y * g.dir.y
        local side = rel.x * g.lat.x + rel.y * g.lat.y

        if not impact then
            if not gutter and math.abs(side) > Config.LaneHalfWidth then
                gutter, gutterSide = true, (side > 0) and 1 or -1
            end
            if gutter then
                -- in the gutter: rolls straight past the pins
                local p = along(g, prog, gutterSide * Config.GutterOffset, g.laneZ + 0.06)
                SetEntityCoordsNoOffset(ball, p.x, p.y, p.z, false, false, false)
                local v = g.dir * fwdV
                SetEntityVelocity(ball, v.x, v.y, 0.0)
            else
                if prog > g.D * 0.4 then sideV = sideV + spin * B.maxHook * dt end   -- the hook
                fwdV = fwdV * (1.0 - 0.025 * dt)
                local v = g.dir * fwdV + g.lat * sideV
                local vz = math.min(0.0, GetEntityVelocity(ball).z)
                SetEntityVelocity(ball, v.x, v.y, vz)
            end
            camAt(along(g, prog - 2.8, side * 0.5, g.laneZ + 1.15), along(g, prog + 3.0, side, g.laneZ + 0.2))

            if prog > g.D - 1.3 then
                impact, impactAt = true, GetGameTimer()
                if not gutter then releasePins() end
            end
        else
            -- pin cam: watch them fall
            camAt(along(g, g.D - 2.4, 1.3, g.laneZ + 1.3), along(g, g.D + 0.4, 0.0, g.laneZ + 0.2))
            if gutter then
                local p = along(g, prog, gutterSide * Config.GutterOffset, g.laneZ + 0.06)
                SetEntityCoordsNoOffset(ball, p.x, p.y, p.z, false, false, false)
                local v = g.dir * fwdV
                SetEntityVelocity(ball, v.x, v.y, 0.0)
            end
            local spd = #GetEntityVelocity(ball)
            if spd < 0.3 then slowSince = slowSince or GetGameTimer() else slowSince = nil end
            if prog > g.D + 1.6 or (slowSince and GetGameTimer() - slowSince > 800) or GetGameTimer() - impactAt > 5000 then
                break
            end
        end
        if GetGameTimer() - t0 > 12000 then break end   -- safety
    end

    -- let the pins settle, then count
    local settle = GetGameTimer() + 2200
    while GetGameTimer() < settle do
        Wait(0)
        DisableAllControlActions(0)
        camAt(along(g, g.D - 2.4, 1.3, g.laneZ + 1.3), along(g, g.D + 0.4, 0.0, g.laneZ + 0.2))
    end
    del(ball); ball = nil
    local knocked = countAndSweep()
    phase = 'wait'
    updateControls()
    TriggerServerEvent('nrp-bowling:roll', knocked)
end

local function aimLoop()
    local ped = PlayerPedId()
    local g = geo(myLane)
    local offset, aim, spin = 0.0, 0.0, 0.0
    local charging, power, dirSign = false, 0.0, 1
    local camMode, lastPower = 1, 0

    FreezeEntityPosition(ped, true)
    placePed(ped, g, offset, aim)
    holdBall(ped)
    camOn()
    phase = 'aim'
    updateControls()
    ui({ action = 'aim', offset = 0, aim = 0, spin = 0 })

    while phase == 'aim' do
        Wait(0)
        DisableAllControlActions(0)
        EnableControlAction(0, 245, true)   -- chat
        EnableControlAction(0, 249, true)   -- push to talk
        local dt = GetFrameTime()

        if not IsEntityPlayingAnim(ped, ANIM, 'aimlive_l', 3) then
            TaskPlayAnim(ped, loadDict(ANIM), 'aimlive_l', 8.0, -8.0, -1, 49, 0, false, false, false)
        end

        local moved = false
        if not charging then
            -- A / D: step left / right on the approach
            if IsDisabledControlPressed(0, 34) then offset = math.max(-B.maxOffset, offset - 0.6 * dt); moved = true end
            if IsDisabledControlPressed(0, 35) then offset = math.min(B.maxOffset, offset + 0.6 * dt); moved = true end
            -- arrows or mouse: aim
            local turnIn = GetDisabledControlNormal(0, 1) * 0.6
            if IsDisabledControlPressed(0, 174) then turnIn = turnIn - 2.0 * dt end
            if IsDisabledControlPressed(0, 175) then turnIn = turnIn + 2.0 * dt end
            if turnIn ~= 0 then aim = math.max(-B.maxAim, math.min(B.maxAim, aim - turnIn)); moved = true end
            -- Q / E: spin (hook)
            if IsDisabledControlJustPressed(0, 44) then spin = math.max(-1.0, spin - 0.25); moved = true end
            if IsDisabledControlJustPressed(0, 38) then spin = math.min(1.0, spin + 0.25); moved = true end
            -- C: camera
            if IsDisabledControlJustPressed(0, 26) then camMode = camMode == 1 and 2 or 1 end
            -- BACKSPACE: step off
            if IsDisabledControlJustPressed(0, 177) then
                phase = 'pickup'
                break
            end
        end
        if moved then
            placePed(ped, g, offset, aim)
            ui({ action = 'aim', offset = offset / B.maxOffset, aim = aim / B.maxAim, spin = spin })
        end

        -- SPACE: hold to charge, release to bowl
        if IsDisabledControlPressed(0, 22) then
            if not charging then charging, power, dirSign = true, 0.0, 1 end
            power = power + dirSign * B.meterSpeed * 2 * dt
            if power >= 1.0 then power, dirSign = 1.0, -1 elseif power <= 0.0 then power, dirSign = 0.0, 1 end
            if GetGameTimer() - lastPower > 30 then
                lastPower = GetGameTimer()
                ui({ action = 'power', value = power, sweet = B.sweetSpot })
            end
        elseif charging then
            ui({ action = 'power', hide = true, value = power, sweet = B.sweetSpot })
            local err = sweetError(power)
            roll(g, offset, aim, spin, power, err)
            break
        end

        drawGuide(g, offset, aim, spin)
        if camMode == 1 then
            local p = along(g, -2.6, offset * 0.6, g.A.z + 1.45)
            camAt(p, along(g, g.D * 0.6, 0.0, g.laneZ))
        else
            local p = along(g, -0.9, offset + 0.35, g.laneZ + 0.55)
            camAt(p, along(g, g.D, offset * 0.3, g.laneZ + 0.2))
        end
    end

    if phase == 'pickup' then
        -- stepped off without bowling
        ClearPedTasks(ped)
        if ball then DetachEntity(ball, true, false); del(ball); ball = nil end
        FreezeEntityPosition(ped, false)
        camOff()
        ui({ action = 'aim', hide = true })
        updateControls()
    end
end

-- ------------------------------------------------------------
--  Server events
-- ------------------------------------------------------------
RegisterNetEvent('nrp-bowling:joined', function(id)
    myLane = id
    phase = 'lobby'
    updateControls()
    SetNewWaypoint(Config.Lanes[id].approach.x, Config.Lanes[id].approach.y)
end)

RegisterNetEvent('nrp-bowling:lane', function(v)
    laneView = v
    ui({ action = 'board', view = v, me = GetPlayerServerId(PlayerId()) })
    if v.last and v.last.seq and v.last.seq ~= lastSeq then
        lastSeq = v.last.seq
        ui({ action = 'banner', name = v.last.name, text = v.last.text, final = v.last.final })
    end
    if phase == 'lobby' and v.status == 'playing' then phase = 'wait' end
    if v.status == 'done' and phase ~= 'rolling' then phase = 'wait' end
    if phase ~= 'aim' and phase ~= 'rolling' and phase ~= 'pickup' then updateControls() end
end)

RegisterNetEvent('nrp-bowling:yourTurn', function(id, t)
    if id ~= myLane then return end
    turn = t
    if t.reset or #rack == 0 then spawnRack(id) end
    phase = 'pickup'
    updateControls()
    if t.roll == 1 then
        PlaySoundFrontend(-1, 'Text_Arrive_Tone', 'Phone_SoundSet_Default', true)
        notify(('Your turn - frame %d'):format(t.frame), 'success')
    end
end)

RegisterNetEvent('nrp-bowling:turnOver', function()
    SetTimeout(2500, function()
        if phase ~= 'aim' and phase ~= 'pickup' then
            clearRack()
            camOff()
            ClearPedTasks(PlayerPedId())
            FreezeEntityPosition(PlayerPedId(), false)
            ui({ action = 'aim', hide = true })
        end
    end)
end)

local function cleanupAll()
    phase, myLane, laneView, turn = nil, nil, nil, nil
    clearRack()
    if ball then del(ball); ball = nil end
    camOff()
    local ped = PlayerPedId()
    ClearPedTasks(ped)
    FreezeEntityPosition(ped, false)
    ui({ action = 'board', hide = true })
    ui({ action = 'aim', hide = true })
    ui({ action = 'power', hide = true })
    controls(nil)
end

RegisterNetEvent('nrp-bowling:left', function()
    cleanupAll()
end)

-- ------------------------------------------------------------
--  Lane loop: pick up the ball on your turn, owner starts game
-- ------------------------------------------------------------
CreateThread(function()
    while true do
        local sleep = 500
        if myLane then
            local ped = PlayerPedId()
            local g = geo(myLane)
            local dist = #(GetEntityCoords(ped) - g.A)

            if phase == 'pickup' then
                sleep = 0
                DrawMarker(27, g.A.x, g.A.y, g.A.z - 0.95, 0, 0, 0, 0, 0, 0, 0.9, 0.9, 0.9, 242, 178, 61, 160, false, false, 2, true, nil, nil, false)
                if dist < 1.6 then
                    if not ballPrompt then ui({ action = 'prompt', key = 'E', text = 'Pick up your ball' }); ballPrompt = true end
                    if IsControlJustReleased(0, 38) then
                        ui({ action = 'prompt' }); ballPrompt = false
                        aimLoop()
                    end
                elseif ballPrompt then
                    ui({ action = 'prompt' }); ballPrompt = false
                end
            elseif phase == 'lobby' then
                local owner = false
                if laneView then for _, p in ipairs(laneView.players) do if p.owner and p.src == GetPlayerServerId(PlayerId()) then owner = true end end end
                if owner and dist < 6.0 then
                    sleep = 0
                    if IsControlJustReleased(0, 47) then TriggerServerEvent('nrp-bowling:start') end
                end
            end

            -- show the score sheet while you're around your lane
            ui({ action = 'boardVisible', show = dist < 30.0 })
        end
        Wait(sleep)
    end
end)

RegisterCommand('bowlleave', function()
    if not myLane then return end
    TriggerServerEvent('nrp-bowling:leave')
end, false)
RegisterKeyMapping('bowlleave', 'Bowling: leave your lane', 'keyboard', 'DELETE')

-- ------------------------------------------------------------
--  Front desk + rack balls + blip
-- ------------------------------------------------------------
RegisterNUICallback('close', function(_, cb)
    deskOpen = false
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('open', function(d, cb)
    deskOpen = false
    SetNuiFocus(false, false)
    TriggerServerEvent('nrp-bowling:open', tonumber(d.lane), tonumber(d.frames))
    cb('ok')
end)

RegisterNUICallback('join', function(d, cb)
    deskOpen = false
    SetNuiFocus(false, false)
    TriggerServerEvent('nrp-bowling:join', tonumber(d.lane))
    cb('ok')
end)

local function openDesk()
    QBCore.Functions.TriggerCallback('nrp-bowling:lanes', function(data)
        deskOpen = true
        SetNuiFocus(true, true)
        ui({ action = 'desk', data = data })
    end)
end

CreateThread(function()
    local b = AddBlipForCoord(Config.Desk.x, Config.Desk.y, Config.Desk.z)
    SetBlipSprite(b, Config.Blip.sprite)
    SetBlipColour(b, Config.Blip.color)
    SetBlipScale(b, Config.Blip.scale)
    SetBlipAsShortRange(b, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(Config.AlleyName)
    EndTextCommandSetBlipName(b)
end)

local rackBalls = {}
CreateThread(function()
    local shown = false
    while true do
        local sleep = 1000
        local pos = GetEntityCoords(PlayerPedId())
        local d = #(pos - Config.Desk)

        -- decorative rack balls: local only, only while nearby
        if d < 60.0 and #rackBalls == 0 then
            local m = loadModel('prop_bowling_ball')
            if m then
                for _, v in ipairs(Config.RackBalls) do
                    local o = CreateObject(m, v.x, v.y, v.z - 0.15, false, false, false)
                    FreezeEntityPosition(o, true)
                    rackBalls[#rackBalls + 1] = o
                end
                SetModelAsNoLongerNeeded(m)
            end
        elseif d > 80.0 and #rackBalls > 0 then
            for _, o in ipairs(rackBalls) do del(o) end
            rackBalls = {}
        end

        if d < 12.0 and not myLane then
            sleep = 0
            DrawMarker(2, Config.Desk.x, Config.Desk.y, Config.Desk.z + 0.2, 0, 0, 0, 0, 180.0, 0, 0.25, 0.25, 0.2, 242, 178, 61, 200, true, true, 2, false, nil, nil, false)
            if d < 1.8 and not deskOpen then
                if not shown then ui({ action = 'prompt', key = 'E', text = 'Rent a lane' }); shown = true end
                if IsControlJustReleased(0, 38) then
                    ui({ action = 'prompt' }); shown = false
                    openDesk()
                end
            elseif shown then ui({ action = 'prompt' }); shown = false end
        elseif shown then ui({ action = 'prompt' }); shown = false end
        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    cleanupAll()
    for _, o in ipairs(rackBalls) do del(o) end
    SetNuiFocus(false, false)
end)
