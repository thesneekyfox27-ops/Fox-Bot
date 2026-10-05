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
-- Bowler's stance: both hands holding the ball at the chest (no weapon needed,
-- so no T-pose). Release: a low crouching put-down, like letting the ball go.
local STANCE  = { dict = 'anim@heists@box_carry@', anim = 'idle' }
local RELEASE = { dict = 'pickup_object', anim = 'putdown_low' }

local function stance(ped)
    if not IsEntityPlayingAnim(ped, STANCE.dict, STANCE.anim, 3) then
        TaskPlayAnim(ped, loadDict(STANCE.dict), STANCE.anim, 4.0, -4.0, -1, 1, 0, false, false, false)
    end
end

local function holdBall(ped)
    if not ball or not DoesEntityExist(ball) then
        local m = loadModel('prop_bowling_ball')
        if not m then return end
        local c = GetEntityCoords(ped)
        ball = CreateObject(m, c.x, c.y, c.z, true, true, false)
        SetModelAsNoLongerNeeded(m)
    end
    -- held in front of the chest, between both hands
    AttachEntityToEntity(ball, ped, GetPedBoneIndex(ped, 24818), 0.08, 0.30, 0.0, 0.0, 0.0, 0.0, false, true, false, true, 0, true)
end

-- an indicator that swings -1..1 and back; `rate` = sweeps per second
local function swing(t, rate)
    local x = (t * rate) % 2.0
    local tri01 = x < 1.0 and x or (2.0 - x)
    return tri01 * 2.0 - 1.0
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

    TaskPlayAnim(ped, loadDict(RELEASE.dict), RELEASE.anim, 4.0, -4.0, 1400, 0, 0, false, false, false)
    Wait(550)   -- ball leaves the hand at the bottom of the crouch
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
    -- hand control back: walk back to the marker and pick up the ball for the next one
    FreezeEntityPosition(ped, false)
    ClearPedTasks(ped)
    camOff()
    TriggerServerEvent('nrp-bowling:roll', knocked)
end

local STEPS = {
    { id = 'position',  text = 'Select initial bowling ball\'s', hi = 'position' },
    { id = 'direction', text = 'Select bowling ball', hi = 'direction' },
    { id = 'spin',      text = 'Select bowling ball', hi = 'spin' },
    { id = 'power',     text = 'Select bowling ball', hi = 'power' },
}

local function aimLoop()
    local ped = PlayerPedId()
    local g = geo(myLane)
    local offset, aim, spin, power = 0.0, 0.0, 0.0, 0.0
    local step, stepStart = 1, GetGameTimer()
    local camMode = 1

    FreezeEntityPosition(ped, true)
    placePed(ped, g, 0.0, 0.0)
    holdBall(ped)
    camOn()
    phase = 'aim'
    updateControls()

    local function setStep(n)
        step, stepStart = n, GetGameTimer()
        ui({ action = 'caption', text = STEPS[n].text, hi = STEPS[n].hi, step = n, steps = #STEPS })
        if STEPS[n].id == 'power' then ui({ action = 'power', value = 0, sweet = B.sweetSpot })
        else ui({ action = 'power', hide = true, value = 0 }) end
    end
    setStep(1)

    local lastUi, lastView = 0, 0
    while phase == 'aim' do
        Wait(0)
        DisableAllControlActions(0)
        EnableControlAction(0, 245, true)   -- chat
        EnableControlAction(0, 249, true)   -- push to talk

        stance(ped)

        local t = (GetGameTimer() - stepStart) / 1000.0
        local id = STEPS[step].id
        -- the live (swinging) value for this step
        if id == 'position' then
            offset = swing(t + 0.5 / B.positionSpeed, B.positionSpeed) * B.maxOffset
        elseif id == 'direction' then
            aim = swing(t + 0.5 / B.directionSpeed, B.directionSpeed) * B.maxAim
        elseif id == 'spin' then
            spin = swing(t + 0.5 / B.spinSpeed, B.spinSpeed)
        elseif id == 'power' then
            power = (swing(t, B.meterSpeed) + 1.0) / 2.0
            if GetGameTimer() - lastUi > 30 then
                lastUi = GetGameTimer()
                ui({ action = 'power', value = power, sweet = B.sweetSpot })
            end
        end

        -- update the on-screen lane panel (UI only, nothing is drawn on the real lane)
        if GetGameTimer() - lastView > 33 then
            lastView = GetGameTimer()
            ui({ action = 'aimview', step = step, offset = offset, aim = aim, spin = spin,
                 maxOffset = B.maxOffset, maxAim = B.maxAim, laneHalf = Config.LaneHalfWidth,
                 length = g.D, hook = B.maxHook, speed = (B.minSpeed + B.maxSpeed) / 2,
                 standing = turn and turn.standing or 10 })
        end

        -- SPACE locks the current step
        if IsDisabledControlJustPressed(0, 22) then
            PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
            if step < #STEPS then
                setStep(step + 1)
            else
                ui({ action = 'caption' })
                ui({ action = 'aimview', hide = true })
                ui({ action = 'power', hide = true, value = power, sweet = B.sweetSpot })
                roll(g, offset, aim, spin, power, sweetError(power))
                break
            end
        -- BACKSPACE: back one step (or put the ball down)
        elseif IsDisabledControlJustPressed(0, 177) then
            if step > 1 then setStep(step - 1)
            else phase = 'pickup'; break end
        -- C: camera
        elseif IsDisabledControlJustPressed(0, 26) then
            camMode = camMode == 1 and 2 or 1
        end

        if camMode == 1 then
            -- in front of the bowler, low over the lane, looking at the pins (nothing in the way)
            camAt(along(g, 1.6, 0.0, g.laneZ + 0.95), along(g, g.D, 0.0, g.laneZ + 0.1))
        else
            -- turned round to watch the bowler in their stance
            camAt(along(g, 3.4, 1.1, g.A.z + 0.7), along(g, 0.0, 0.0, g.A.z + 0.15))
        end
    end

    if phase == 'pickup' then
        ClearPedTasks(ped)
        if ball then DetachEntity(ball, true, false); del(ball); ball = nil end
        FreezeEntityPosition(ped, false)
        camOff()
        ui({ action = 'caption' })
        ui({ action = 'aimview', hide = true })
        ui({ action = 'power', hide = true, value = 0 })
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

local turnBlip = nil
local function clearTurnBlip()
    if turnBlip and DoesBlipExist(turnBlip) then RemoveBlip(turnBlip) end
    turnBlip = nil
end

local function setTurnBlip(id)
    clearTurnBlip()
    local a = Config.Lanes[id].approach
    turnBlip = AddBlipForCoord(a.x, a.y, a.z)
    SetBlipSprite(turnBlip, 103)
    SetBlipColour(turnBlip, 48)
    SetBlipScale(turnBlip, 0.85)
    SetBlipAsShortRange(turnBlip, false)
    SetBlipFlashes(turnBlip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(('Bowl here - lane %d'):format(id))
    EndTextCommandSetBlipName(turnBlip)
end

RegisterNetEvent('nrp-bowling:yourTurn', function(id, t)
    if id ~= myLane then return end
    setTurnBlip(id)
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
    clearTurnBlip()
    phase, myLane, laneView, turn = nil, nil, nil, nil
    clearRack()
    if ball then del(ball); ball = nil end
    camOff()
    local ped = PlayerPedId()
    ClearPedTasks(ped)
    FreezeEntityPosition(ped, false)
    ui({ action = 'board', hide = true })
    ui({ action = 'aimview', hide = true })
    ui({ action = 'caption' })
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
                local fz = g.laneZ   -- lane floor height (the old marker was a metre under it)
                DrawMarker(1, g.A.x, g.A.y, fz - 0.05, 0, 0, 0, 0, 0, 0, 1.1, 1.1, 0.35, 255, 63, 134, 110, false, false, 2, false, nil, nil, false)
                DrawMarker(25, g.A.x, g.A.y, fz + 0.03, 0, 0, 0, 0, 0, 0, 1.3, 1.3, 1.0, 255, 210, 63, 200, false, false, 2, true, nil, nil, false)
                DrawMarker(0, g.A.x, g.A.y, fz + 1.9, 0, 0, 0, 0, 0, 0, 0.35, 0.35, 0.35, 255, 210, 63, 220, true, true, 2, false, nil, nil, false)
                local d2 = #(GetEntityCoords(ped).xy - g.A.xy)
                if d2 < 1.3 then
                    if not ballPrompt then ui({ action = 'prompt', key = 'E', text = 'Pick up your ball' }); ballPrompt = true end
                    if IsControlJustReleased(0, 38) then
                        ui({ action = 'prompt' }); ballPrompt = false
                        clearTurnBlip()
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
local function unfocus()
    deskOpen = false
    SetNuiFocus(false, false)
end

RegisterNUICallback('close', function(_, cb) unfocus(); cb('ok') end)

RegisterNUICallback('buy', function(order, cb)
    TriggerServerEvent('nrp-bowling:buy', order)
    cb('ok')
end)

RegisterNUICallback('chooseLane', function(d, cb)
    unfocus()
    TriggerServerEvent('nrp-bowling:chooseLane', d.lane)
    cb('ok')
end)

RegisterNUICallback('cancelBooking', function(_, cb)
    unfocus()
    TriggerServerEvent('nrp-bowling:cancelBooking')
    cb('ok')
end)

RegisterNUICallback('inviteAnswer', function(d, cb)
    SetNuiFocus(false, false)
    TriggerServerEvent('nrp-bowling:inviteAnswer', d.accept == true, d.ticket)
    cb('ok')
end)

local function openMenu()
    if deskOpen or myLane then
        if myLane then notify(('You\'re on lane %d. Press DELETE to leave it first.'):format(myLane), 'error') end
        return
    end
    QBCore.Functions.TriggerCallback('nrp-bowling:menu', function(data)
        deskOpen = true
        SetNuiFocus(true, true)
        ui({ action = 'menu', data = data })
    end)
end

RegisterNetEvent('nrp-bowling:pickLane', function(list)
    deskOpen = true
    SetNuiFocus(true, true)
    ui({ action = 'lanes', lanes = list })
end)

RegisterNetEvent('nrp-bowling:closeMenu', function()
    unfocus()
    ui({ action = 'closeMenu' })
end)

RegisterNetEvent('nrp-bowling:invited', function(d)
    if myLane then return end
    SetNuiFocus(true, true)
    ui({ action = 'invite', data = d })
    PlaySoundFrontend(-1, 'Text_Arrive_Tone', 'Phone_SoundSet_Default', true)
end)

RegisterNetEvent('nrp-bowling:inviteGone', function()
    ui({ action = 'inviteGone' })
    if not deskOpen then SetNuiFocus(false, false) end
end)

-- ------------------------------------------------------------
--  Staff ped (streamed in when you're nearby)
-- ------------------------------------------------------------
local staff = nil
local usingTarget = false
local staffPos = Config.Staff.coords   -- the server sends the saved spot (/bowlstaff)

local function addTarget(ped)
    local mode = Config.Target
    if mode == 'off' then return false end
    if GetResourceState('ox_target') == 'started' then
        exports.ox_target:addLocalEntity(ped, { {
            name = 'nrp_bowling_staff', label = 'Buy a game', icon = 'fa-solid fa-bowling-ball', distance = 2.5,
            onSelect = openMenu,
        } })
        return true
    end
    if GetResourceState('qb-target') == 'started' then
        exports['qb-target']:AddTargetEntity(ped, {
            options = { { type = 'client', icon = 'fas fa-bowling-ball', label = 'Buy a game', action = openMenu } },
            distance = 2.5,
        })
        return true
    end
    return false
end

local function floorZ(x, y, z)
    for _ = 1, 20 do
        local ok, gz = GetGroundZFor_3dCoord(x, y, z + 1.5, false)
        if ok and gz > z - 2.0 and gz < z + 1.5 then return gz end
        Wait(50)
    end
    return z
end

local function spawnStaff()
    local S = Config.Staff
    local m = loadModel(S.model)
    if not m then return print('[nrp-bowling] staff model is not valid: ' .. tostring(S.model)) end
    local c = staffPos
    RequestCollisionAtCoord(c.x, c.y, c.z)
    local interior = GetInteriorAtCoords(c.x, c.y, c.z)
    if interior ~= 0 then
        PinInteriorInMemory(interior)
        local t = GetGameTimer() + 4000
        while not IsInteriorReady(interior) and GetGameTimer() < t do Wait(50) end
    end
    local z = floorZ(c.x, c.y, c.z)
    local ped = CreatePed(4, m, c.x, c.y, z, c.w, false, true)
    SetEntityCoords(ped, c.x, c.y, z, false, false, false, false)
    SetEntityHeading(ped, c.w)
    SetEntityInvincible(ped, true)
    SetPedCanRagdoll(ped, false)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    local t = GetGameTimer() + 3000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < t do Wait(50) end
    Wait(250)
    FreezeEntityPosition(ped, true)
    if S.scenario then TaskStartScenarioInPlace(ped, S.scenario, 0, true) end
    SetModelAsNoLongerNeeded(m)
    staff = ped
    usingTarget = addTarget(ped)
end

CreateThread(function()
    local shown = false
    while true do
        local sleep = 1000
        local c = staffPos
        local d = #(GetEntityCoords(PlayerPedId()) - vector3(c.x, c.y, c.z))
        if d < Config.Staff.spawnDistance then
            if not (staff and DoesEntityExist(staff)) then spawnStaff() end
        elseif staff and d > Config.Staff.spawnDistance + 30.0 then
            del(staff); staff = nil
        end
        if staff and not usingTarget and not myLane then
            if d < 10.0 then sleep = 0 end
            if d < 2.2 and not deskOpen then
                if not shown then ui({ action = 'prompt', key = 'E', text = 'Buy a game' }); shown = true end
                if IsControlJustReleased(0, 38) then ui({ action = 'prompt' }); shown = false; openMenu() end
            elseif shown then ui({ action = 'prompt' }); shown = false end
        elseif shown then ui({ action = 'prompt' }); shown = false end
        Wait(sleep)
    end
end)

RegisterNetEvent('nrp-bowling:staffPos', function(p)
    staffPos = vector4(p.x, p.y, p.z, p.w)
    if staff then del(staff); staff = nil end   -- respawns at the new spot on the next check
end)

CreateThread(function()
    Wait(1500)
    TriggerServerEvent('nrp-bowling:staffPos')
end)

RegisterCommand('bowlcoords', function()
    local p, h = GetEntityCoords(PlayerPedId()), GetEntityHeading(PlayerPedId())
    print(('[nrp-bowling] vector4(%.2f, %.2f, %.2f, %.1f)'):format(p.x, p.y, p.z, h))
    notify('Coords printed in F8.', 'primary')
end, false)

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

        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    cleanupAll()
    for _, o in ipairs(rackBalls) do del(o) end
    del(staff)
    SetNuiFocus(false, false)
end)
