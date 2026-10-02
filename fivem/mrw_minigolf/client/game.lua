-- Author : Morow (original) / Crazy Golf rework
-- Github : https://github.com/Morow73
--
-- Turn-based round. The server decides whose turn it is (the ball farthest
-- from the cup plays next), the client handles walking up, lining up and the
-- shot itself. No screen fades: you walk to your ball and press E.

local BALL_MODEL = `prop_golf_ball`

local inGame    = false
local hole      = nil      -- hole the group is on
local ball      = nil      -- our Object (see object.lua)
local club      = nil
local myTurn    = false
local phase     = 'idle'   -- idle | waiting | approach | lining | aim | shooting | holed
local turnName  = nil
local power     = 0.0
local myId      = GetPlayerServerId(PlayerId())
local scoreboardOpen = false

allGame = {}               -- { { hole = n, stroke = n } } our own strokes, for the quit card
s = nil                    -- scaleform banner (DisplayScaleform in thread.lua uses it)

function IsPlayingGolf()
    return inGame
end

function ScoreboardIsShowing()
    return scoreboardOpen
end

-- messages from the server (not enough money, turns, ...)
RegisterNetEvent("mrw_golf:Notification")
AddEventHandler("mrw_golf:Notification", function(msg)
    Ui:displayNotification(msg)
end)

-- ---------------------------------------------------------------- helpers
local function track() return Config.golf_track[hole] end

local function addLocalStroke()
    for _, v in ipairs(allGame) do
        if v.hole == hole then v.stroke = math.min(v.stroke + 1, Config.max_stroke) end
    end
end

local function banner(title, text)
    if not s then return end
    s:addContent(title, text)
    CreateThread(DisplayScaleform)
end

local function deleteBall()
    if ball then ball = ball:delete() end
end

local function spawnBall(pos)
    deleteBall()
    ball = Object('prop_golf_ball', pos)
    ApplyBallParams(ball.object)
    local net = ObjToNet(ball.object)
    if net and net ~= 0 then SetNetworkIdCanMigrate(net, false) end   -- stays ours
end

local function releasePed()
    local ped = PlayerPedId()
    DetachEntity(ped, true, true)
    FreezeEntityPosition(ped, false)
    ClearPedTasks(ped)
end

local function stopAiming()
    DrawLineActive = false
    Ui:displayPowerBar(false, 0)
end

--- Heading that faces the cup from where the ball lies (tee uses the course's own heading).
local function aimHeading()
    local b = GetEntityCoords(ball.object)
    local t = track()
    if #(b - t.start) < 0.3 then return t.heading end
    return Utils:deg(b.x - t.hole.x, b.y - t.hole.y)
end

local function dist2d(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

-- ------------------------------------------------------------------- aim
local function drawAimLine()
    DrawLineActive = true
    while DrawLineActive and inGame and ball do
        Ui:drawLine(GetEntityCoords(ball.object), Utils:rayCastGamePlayCamera(50.0))
        Wait(0)
    end
end

local shoot   -- forward declaration

local function aimLoop()
    power = 0.0
    while inGame and phase == 'aim' and ball do
        Ui:displayHelpNotification({
            translation["other_params"],
            translation["rotate_params"],
            translation["aim_params"]
        })

        if IsControlPressed(0, 24) then                       -- hold left mouse: charge
            power = math.min(power + 0.01, 1.0)
            Ui:displayPowerBar(true, power)

        elseif IsControlJustReleased(0, 24) and power > 0.0 then
            shoot()
            return

        elseif IsControlPressed(0, 174) or IsControlPressed(0, 175) then   -- arrows: walk round the ball
            local ped = PlayerPedId()
            local step = IsControlPressed(0, 174) and 1.0 or -1.0
            local h = GetEntityHeading(ped)
            FreezeEntityPosition(ped, false)
            Utils:placePed(ball.object, h + step)
            FreezeEntityPosition(ped, true)

        elseif IsControlJustPressed(0, 73) then                -- X: step away
            stopAiming()
            releasePed()
            phase = 'approach'
            CreateThread(function() ApproachLoop() end)
            return
        end
        Wait(0)
    end
    stopAiming()
end

--- Walk to the stance spot, then settle into the putting stance.
local function lineUp()
    phase = 'lining'
    local ped = PlayerPedId()
    local h = aimHeading()
    local spot = Utils:stanceFor(ball.object, h)

    TaskGoStraightToCoord(ped, spot.x, spot.y, spot.z, 1.0, 4000, h, 0.1)
    local deadline = GetGameTimer() + 4000
    while GetGameTimer() < deadline and dist2d(GetEntityCoords(ped), spot) > 0.25 do Wait(50) end
    if not inGame or phase ~= 'lining' then return end

    ClearPedTasks(ped)
    Utils:placePed(ball.object, h)                 -- last few cm, no fade
    Utils:playAnimation("mini@golfai", "wedge_idle_a", {}, -1, 1)
    FreezeEntityPosition(ped, true)

    phase = 'aim'
    CreateThread(drawAimLine)
    aimLoop()
end

function ApproachLoop()
    while inGame and myTurn and phase == 'approach' and ball do
        local bpos = GetEntityCoords(ball.object)
        local d = #(GetEntityCoords(PlayerPedId()) - bpos)

        if d <= 1.6 then
            Ui:displayHelpNotification({ translation['address_ball'] })
            if IsControlJustPressed(0, 38) then
                lineUp()
                return
            end
        else
            Ui:displayHelpNotification({ translation['walk_to_ball'] })
        end
        Wait(0)
    end
end

-- ------------------------------------------------------------------ shot
shoot = function()
    phase = 'shooting'
    stopAiming()

    local target = Utils:rayCastGamePlayCamera(90.0)
    local p = power
    TriggerServerEvent('mrw_minigolf:shot', hole)
    addLocalStroke()

    Utils:playAnimation("mini@golfai", "iron_swing_action", {}, 5000, 0)
    Wait(500)
    if not inGame or not ball then return end

    Utils:playSoundFromEntity("GOLF_SWING_FAIRWAY_IRON_LIGHT_MASTER")
    SetEntityHeading(ball.object, 0.0)
    local offset = GetOffsetFromEntityGivenWorldCoords(ball.object, target.x, target.y, target.z)

    FreezeEntityPosition(ball.object, false)
    SetEntityVelocity(ball.object, offset.x * p, offset.y * p, -0.1)
    ApplyForceToEntity(ball.object, 0, offset.x, offset.y, 0.0, 0.0, 0.0, 0.0, 0, false, false, false, false, true)
    Utils:createCamera(ball.object)

    -- let the swing finish, then free the player so they can follow the ball
    SetTimeout(1200, function() if inGame then releasePed() end end)

    local decay, started = p, GetGameTimer()
    while true do
        Wait(100)
        if not inGame or not ball or not DoesEntityExist(ball.object) then
            Utils:deleteCamera()
            return
        end
        if decay > 0.0 then
            decay = decay - 0.01
        elseif GetEntitySpeed(ball.object) < 1.0 or GetGameTimer() - started > 20000 then
            break
        end
    end

    SetEntityVelocity(ball.object, 0.0, 0.0, 0.0)
    FreezeEntityPosition(ball.object, true)
    Utils:deleteCamera()

    local pos = GetEntityCoords(ball.object)
    local t = track()
    local result
    if #(pos - t.hole) <= 0.15 then
        result = 'holed'
    elseif not Utils:groundMaterial(ball.object) then
        result = 'out'
        Ui:displayNotification(translation['off_side'])
        ball:setPosition(t.start)
        ball:setHeading(0.0)
        PlaceObjectOnGroundProperly(ball.object)
        FreezeEntityPosition(ball.object, true)
        pos = t.start
    else
        result = 'rest'
    end

    myTurn, phase = false, 'waiting'
    TriggerServerEvent('mrw_minigolf:ballState', hole, result, { x = pos.x, y = pos.y, z = pos.z })
end

-- ------------------------------------------------------------- the round
RegisterNetEvent("mrw_minigolf:st_game")
AddEventHandler("mrw_minigolf:st_game", function(startHole)
    if inGame then return end
    inGame, hole, myTurn, phase = true, startHole or 1, false, 'waiting'

    RequestScriptAudioBank("GOLF_I", 0)
    s = s or Scaleform()

    allGame = {}
    for i = 1, #Config.golf_track do allGame[i] = { hole = i, stroke = 0 } end

    local ped = PlayerPedId()
    club = Object('prop_golf_putter_01', GetEntityCoords(ped))
    AttachEntityToEntity(club.object, ped, GetPedBoneIndex(ped, 28422), 0, 0, 0, 0.0, 0.0, 0.0, false, false, false, true, 0, true)

    spawnBall(track().start)
    SetNewWaypoint(track().start.x, track().start.y)
end)

RegisterNetEvent("mrw_minigolf:newHole")
AddEventHandler("mrw_minigolf:newHole", function(newHole)
    if not inGame then return end
    hole, myTurn, phase = newHole, false, 'waiting'
    spawnBall(track().start)
    SetNewWaypoint(track().start.x, track().start.y)
    Ui:displayNotification((translation['hole_start'] or 'Hole %s'):format(hole))
end)

RegisterNetEvent("mrw_minigolf:turn")
AddEventHandler("mrw_minigolf:turn", function(turnSrc, name, turnHole)
    if not inGame then return end
    turnName = name

    -- the ball may still be spawning if the game only just started
    local deadline = GetGameTimer() + 5000
    while inGame and not ball and phase ~= 'holed' and GetGameTimer() < deadline do Wait(50) end

    myTurn = (tonumber(turnSrc) == myId) and ball ~= nil
    if myTurn then
        phase = 'approach'
        PlaySoundFrontend(-1, 'Out_Of_Area', 'DLC_Lowrider_Relay_Race_Sounds', false)
        Ui:displayNotification(translation['your_turn'] or 'Your turn - walk to your ball')
        CreateThread(ApproachLoop)
    elseif phase ~= 'holed' then
        phase = 'waiting'
    end
end)

-- our hole is over (in the cup, stroke limit or ran out of time)
RegisterNetEvent("mrw_minigolf:holeDone")
AddEventHandler("mrw_minigolf:holeDone", function(strokes, reason)
    if not inGame then return end
    myTurn, phase = false, 'holed'
    stopAiming()
    releasePed()
    deleteBall()
    if reason == 'holed' then
        banner(translation["congrats"], ("%s %s %s"):format(translation["round_win"], strokes, translation["stroke"]))
    elseif reason == 'timeout' then
        Ui:displayNotification(translation['you_timeout'] or 'Out of time - this hole is scored at the limit')
    else
        Ui:displayNotification(translation["max_stroke"])
    end
end)

-- whole group done with the last hole
RegisterNetEvent("mrw_minigolf:groupFinished")
AddEventHandler("mrw_minigolf:groupFinished", function(total)
    if not inGame then return end
    banner(translation["congrats"], ("%s %s %s"):format(translation["finish_game"], total or 0, translation["stroke"]))
    SetTimeout(2500, function()
        TriggerEvent("mrw_minigolf:cut_game", "done")
    end)
end)

--- Leave the game right now, wherever we are in it (aiming, mid-shot, walking).
function QuitGolf()
    if not inGame then return end
    Ui:displayNotification(translation['quit'])
    TriggerEvent("mrw_minigolf:cut_game", "quit")
end

RegisterNetEvent("mrw_minigolf:cut_game")
AddEventHandler("mrw_minigolf:cut_game", function(reason)
    if not inGame then return end
    inGame, myTurn, phase = false, false, 'idle'
    TriggerServerEvent(reason == "quit" and "mrw_minigolf:leave" or "mrw_minigolf:finished")

    ScaleformActive = false
    stopAiming()
    Utils:deleteCamera()
    Ui:displayScoreboard(false)
    scoreboardOpen = false
    releasePed()
    deleteBall()
    if club then club = club:delete() end
    if IsScreenFadedOut() or IsScreenFadingOut() then DoScreenFadeIn(300) end
    SetWaypointOff()
end)

-- --------------------------------------------- always-on while playing
local otherBalls, lastScan = {}, 0

CreateThread(function()
    while true do
        if not inGame then
            Wait(500)
        else
            local ped = PlayerPedId()

            -- scorecard: hold the key any time during the round
            if IsControlJustPressed(0, 121) and not scoreboardOpen then
                scoreboardOpen = true
                Ui:displayScoreboard(true)
            elseif IsControlJustReleased(0, 121) and scoreboardOpen then
                scoreboardOpen = false
                Ui:displayScoreboard(false)
            end

            if ball and DoesEntityExist(ball.object) then
                local bpos = GetEntityCoords(ball.object)

                -- arrow over our ball: orange when it's our turn
                local r, g, b = 255, 255, 255
                if myTurn then r, g, b = 240, 122, 26 end
                DrawMarker(2, bpos.x, bpos.y, bpos.z + 0.55, 0.0, 0.0, 0.0, 180.0, 0.0, 0.0,
                    0.18, 0.18, 0.18, r, g, b, 200, true, true, 2, false, nil, nil, false)

                -- nobody else can knock our ball: no collision with other players or other balls
                if GetGameTimer() - lastScan > 500 then
                    lastScan = GetGameTimer()
                    otherBalls = {}
                    for _, obj in ipairs(GetGamePool('CObject')) do
                        if obj ~= ball.object and GetEntityModel(obj) == BALL_MODEL
                            and #(GetEntityCoords(obj) - bpos) < 25.0 then
                            otherBalls[#otherBalls + 1] = obj
                        end
                    end
                end
                for _, obj in ipairs(otherBalls) do
                    if DoesEntityExist(obj) then
                        SetEntityNoCollisionEntity(ball.object, obj, true)
                        SetEntityNoCollisionEntity(obj, ball.object, true)
                    end
                end
                for _, pid in ipairs(GetActivePlayers()) do
                    local other = GetPlayerPed(pid)
                    if other ~= ped and #(GetEntityCoords(other) - bpos) < 25.0 then
                        SetEntityNoCollisionEntity(ball.object, other, true)
                    end
                end
            end

            if phase == 'waiting' and turnName and not myTurn then
                Ui:displayHelpNotification({ (translation['waiting_turn'] or 'Waiting for %s'):format(turnName) })
            elseif phase == 'holed' then
                Ui:displayHelpNotification({ translation['waiting_group'] or 'Waiting for the rest of your group' })
            end

            Wait(0)
        end
    end
end)

AddEventHandler("onResourceStop", function(name)
    if GetCurrentResourceName() ~= name then return end
    deleteBall()
    if club then club = club:delete() end
    if s then s:destruct() s = nil end
    if inGame then
        Utils:deleteCamera()
        releasePed()
        if IsScreenFadedOut() then DoScreenFadeIn(100) end
    end
end)
