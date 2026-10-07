-- ============================================================
--  WeatherSync :: server
--  Owns the weather/time state and syncs it to every player.
--  Restart alert, the Purge, auto weather, gd_tornado, commands.
-- ============================================================

local QBCore = nil
if (Config.Framework == 'qbcore' or Config.Framework == 'auto') and GetResourceState('qb-core') == 'started' then
    QBCore = exports['qb-core']:GetCoreObject()
end

local state = {
    weatherId = Config.StartWeatherId,
    blackout  = Config.StartBlackout,
    freeze    = not Config.DynamicTime,
    dynamic   = Config.DynamicWeather,
    hour      = Config.StartTime.hour,
    minute    = Config.StartTime.minute,
    addon     = nil,
    alert     = false,
    lightning = (Config.Lightning and Config.Lightning.enabled) and true or false,
    purge     = false,
}

-- restart alert
local alertSaved    = nil   -- weather/blackout to restore after the alert
local restartToken  = 0     -- bumped to cancel a running countdown
local restartRemain = 0     -- seconds left (for players who join mid-countdown)

-- the Purge
local purgeToken     = 0
local purgeRemain    = 0
local purgePhase     = 'idle'   -- 'idle' | 'active'
local purgeSaved     = nil      -- weather/blackout to restore after the purge
local purgeScheduled = false    -- the running purge came from the schedule
-- The panel button is the master ENABLE for the scheduled purge; it never starts one early.
local scheduleOn = (Config.Purge.schedule and Config.Purge.schedule.enabled) and true or false
-- Treat the current window as handled (enabling mid-window waits for the next start)
local scheduleRanWindow = false
local broadcastSeconds = (Config.Purge.broadcast and Config.Purge.broadcast.start and Config.Purge.broadcast.start.seconds) or 12

-- ------------------------------------------------------------
--  Helpers
-- ------------------------------------------------------------
local function isAdmin(src)
    if src == 0 or not Config.RestrictToAdmins then return true end
    for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
        for _, allowed in ipairs(Config.AdminIdentifiers or {}) do
            if id == allowed then return true end
        end
    end
    if QBCore then
        for _, group in ipairs(Config.AdminGroups) do
            if QBCore.Functions.HasPermission(src, group) then return true end
        end
    end
    return IsPlayerAceAllowed(src, Config.AcePermission)
end

local function notify(src, msg, nType)
    if src == 0 then print('[WeatherSync] ' .. msg) return end
    local mode = Config.Notify or 'clean'
    if mode == 'off' then return end
    if mode == 'clean' then
        TriggerClientEvent('weathersync:client:notify', src, msg, nType or 'primary')
    elseif mode == 'qb' and QBCore then
        TriggerClientEvent('QBCore:Notify', src, msg, nType or 'primary')
    else
        TriggerClientEvent('chat:addMessage', src, { color = { 0, 170, 255 }, args = { 'WeatherSync', msg } })
    end
end

-- run fn only for admins (console counts as admin)
local function adminOnly(src)
    if isAdmin(src) then return true end
    notify(src, 'No permission.', 'error')
    return false
end

local function resourceStarted(name)
    return not name or name == '' or GetResourceState(name) == 'started'
end

-- ------------------------------------------------------------
--  Add-on effects (gd_tornado etc.)
-- ------------------------------------------------------------
local pendingTornadoResolver = nil

-- gd_tornado's client makes a new funnel on every spawn and never frees the old
-- one, so always delete first and send exactly one spawn.
local function doSpawnTornado(pos, dest)
    if GetResourceState('gd_tornado') ~= 'started' then return end
    TriggerClientEvent('gd_tornado:delete', -1)
    SetTimeout(450, function() TriggerClientEvent('gd_tornado:spawn', -1, pos, dest) end)
end

-- spawn point without a client's help: config coords, or near a player at their height
local function fallbackTornado(src)
    local sp = Config.TornadoSpawn or {}
    local c = sp.coords or { x = 215.0, y = -810.0, z = 30.0 }
    local x, y, z = c.x, c.y, c.z
    if sp.mode ~= 'coords' then
        local ped = (src and tonumber(src) and tonumber(src) > 0) and GetPlayerPed(src) or 0
        if ped == 0 then
            local players = GetPlayers()
            if #players > 0 then ped = GetPlayerPed(players[math.random(#players)]) end
        end
        if ped ~= 0 then
            local p = GetEntityCoords(ped)
            local ang = math.random() * 6.2831
            local d = sp.distance or 60.0
            x, y, z = p.x + math.cos(ang) * d, p.y + math.sin(ang) * d, p.z
        end
    end
    local ang = math.random() * 6.2831
    local r = sp.roamRadius or 90.0
    doSpawnTornado({ x = x, y = y, z = z }, { x = x + math.cos(ang) * r, y = y + math.sin(ang) * r, z = z })
end

-- The server can't read ground height, so a player resolves a ground-level spawn
-- point and sends it back (weathersync:server:tornadoResolved).
local function spawnGdTornado(src)
    if GetResourceState('gd_tornado') ~= 'started' then return end
    local resolver = (src and tonumber(src) and tonumber(src) > 0) and tostring(src) or nil
    if not resolver then
        local players = GetPlayers()
        if #players > 0 then resolver = players[math.random(#players)] end
    end
    if not resolver then return fallbackTornado(nil) end

    pendingTornadoResolver = resolver
    TriggerClientEvent('weathersync:client:resolveTornado', tonumber(resolver))
    SetTimeout(2500, function()   -- the client never answered
        if pendingTornadoResolver == resolver and state.addon == 'tornado' then
            pendingTornadoResolver = nil
            fallbackTornado(tonumber(resolver))
        end
    end)
end

RegisterNetEvent('weathersync:server:tornadoResolved', function(pos, dest)
    local src = source
    if pendingTornadoResolver and tostring(src) ~= tostring(pendingTornadoResolver) then return end
    pendingTornadoResolver = nil
    if state.addon ~= 'tornado' or type(pos) ~= 'table' or type(dest) ~= 'table' then return end
    doSpawnTornado(pos, dest)
end)

local function serverAddonStart(key, src)
    local cfg = Config.AddonEffects[key]
    if not cfg or not cfg.enabled then return end
    if not resourceStarted(cfg.resource) then
        print(('[WeatherSync] Add-on "%s" needs resource "%s" started - skipping.'):format(key, cfg.resource))
        return
    end
    if key == 'tornado' then return spawnGdTornado(src) end
    if cfg.command and cfg.command ~= '' then ExecuteCommand(cfg.command) end
    if cfg.serverEvent and cfg.serverEvent ~= '' then TriggerEvent(cfg.serverEvent) end
end

local function serverAddonStop(key)
    local cfg = Config.AddonEffects[key]
    if not cfg or not resourceStarted(cfg.resource) then return end
    if key == 'tornado' then return TriggerClientEvent('gd_tornado:delete', -1) end
    if cfg.stopCommand and cfg.stopCommand ~= '' then ExecuteCommand(cfg.stopCommand) end
    if cfg.serverStopEvent and cfg.serverStopEvent ~= '' then TriggerEvent(cfg.serverStopEvent) end
end

local function updateServerAddon(entry, src)
    local want = entry and entry.effects and entry.effects.addon or nil
    if state.addon == want then return end
    if state.addon then serverAddonStop(state.addon) end
    state.addon = want
    if want then serverAddonStart(want, src) end
end

-- ------------------------------------------------------------
--  Broadcasting state
-- ------------------------------------------------------------
local function broadcastWeather()
    TriggerClientEvent('weathersync:client:setWeather', -1, state.weatherId, state.blackout)
end

local function broadcastTime()
    TriggerClientEvent('weathersync:client:setTime', -1, state.hour, state.minute, state.freeze)
end

local function purgeSirenPayload(on)
    return { on = on, volume = Config.Purge.sirenVolume, sound = Config.Purge.sirenSound, loop = Config.Purge.sirenLoop }
end

local function purgeHudPayload()
    return { active = true, phase = purgePhase, seconds = purgeRemain,
             label = Config.Purge.label, activeLabel = Config.Purge.activeLabel }
end

-- everything a (re)joining player needs
local function pushFullState(target)
    TriggerClientEvent('weathersync:client:syncState', target, {
        weatherId = state.weatherId, blackout = state.blackout, freeze = state.freeze,
        dynamic = state.dynamic, hour = state.hour, minute = state.minute, alert = state.alert,
        lightning = state.lightning, purge = scheduleOn,
    })
    if state.alert and Config.RestartAlert.siren then
        TriggerClientEvent('weathersync:client:siren', target, true)
    end
    if state.alert and restartRemain > 0 then
        TriggerClientEvent('weathersync:client:restartHud', target, { active = true, seconds = restartRemain })
    end
    if state.purge and purgePhase ~= 'idle' then
        -- only a LOOPING siren is re-sent; a one-shot start sound already played
        if Config.Purge.siren and Config.Purge.sirenLoop then
            TriggerClientEvent('weathersync:client:purgeSiren', target, purgeSirenPayload(true))
        end
        TriggerClientEvent('weathersync:client:purgeHud', target, purgeHudPayload())
    end
end

-- ------------------------------------------------------------
--  Weather & time
-- ------------------------------------------------------------
local function setWeather(key, fromDynamic, src)
    local entry = Config.GetWeather(key)
    if not entry then return false end
    state.weatherId = entry.id
    if not fromDynamic then state.dynamic = false end
    updateServerAddon(entry, src)
    broadcastWeather()
    return true, entry
end

local function setTime(hour, minute)
    hour, minute = tonumber(hour), tonumber(minute) or 0
    if not hour or hour < 0 or hour > 23 or minute < 0 or minute > 59 then return false end
    state.hour, state.minute = math.floor(hour), math.floor(minute)
    broadcastTime()
    return true
end

-- the clock
CreateThread(function()
    while true do
        Wait(Config.MillisecondsPerMinute)
        if Config.DynamicTime and not state.freeze then
            state.minute = state.minute + 1
            if state.minute >= 60 then state.minute, state.hour = 0, (state.hour + 1) % 24 end
            broadcastTime()
        end
    end
end)

-- ------------------------------------------------------------
--  Auto weather (momentum: mostly stays, otherwise moves to a
--  neighbouring weather, biased by time of day)
-- ------------------------------------------------------------
local function inHourRange(h, from, to)
    if from <= to then return h >= from and h < to end
    return h >= from or h < to   -- wraps past midnight
end

local function rollNextWeather()
    local cur = state.weatherId
    if math.random() < (Config.WeatherStability or 0.6) then return cur end

    -- weather outside the natural cycle (snow, tornado...) eases back toward clear
    local trans = (Config.WeatherTransitions and Config.WeatherTransitions[cur]) or { clear = 3, clouds = 2, extrasunny = 1 }

    local bias
    for _, b in ipairs(Config.WeatherTimeBias or {}) do
        if inHourRange(state.hour, b.from, b.to) then bias = b.mult; break end
    end

    local weighted, total = {}, 0
    for id, w in pairs(trans) do
        local ww = w * ((bias and bias[id]) or 1.0)
        if ww > 0 and Config.GetWeather(id) then
            weighted[id] = ww
            total = total + ww
        end
    end
    if total <= 0 then return cur end

    local pick, acc = math.random() * total, 0
    for id, ww in pairs(weighted) do
        acc = acc + ww
        if pick <= acc then return id end
    end
    return cur
end

CreateThread(function()
    while true do
        Wait(Config.MillisecondsPerMinute * Config.DynamicWeatherInterval)
        if state.dynamic and not state.alert and not state.purge then
            setWeather(rollNextWeather(), true)
        end
    end
end)

-- ------------------------------------------------------------
--  Server restart alert
-- ------------------------------------------------------------
-- A resource needs permission to run `quit`: returns ok, the ace, the principal
local function restartAceOk()
    local principal = 'resource.' .. GetCurrentResourceName()
    local cmd = (Config.RestartAlert.restartCommand or ''):match('^%s*(%S+)')
    if not cmd or cmd == '' then return true, nil, principal end
    local ace = 'command.' .. cmd
    return IsPrincipalAceAllowed(principal, ace), ace, principal
end

local function fireRestartCommand()
    local cmd = Config.RestartAlert.restartCommand
    if not cmd or cmd == '' then return end
    local ok, ace, principal = restartAceOk()
    if not ok then
        print('[WeatherSync] ^1RESTART BLOCKED^7 - the resource is not allowed to run "' .. cmd .. '".')
        print(('[WeatherSync] Add this to server.cfg (then restart the server once):  add_ace %s %s allow'):format(principal, ace))
        return
    end
    print('[WeatherSync] Restart countdown finished - executing: ' .. cmd)
    ExecuteCommand(cmd)
end

local function startRestartCountdown(seconds, doRestart)
    seconds = math.floor(tonumber(seconds) or Config.RestartAlert.countdownSeconds)
    seconds = math.max(5, math.min(7200, seconds))
    restartToken = restartToken + 1
    restartRemain = seconds
    local myToken = restartToken

    local cmd = Config.RestartAlert.restartCommand
    if doRestart and cmd and cmd ~= '' then
        print(('[WeatherSync] Restart armed: will run "%s" in %d seconds.'):format(cmd, seconds))
        local ok, ace, principal = restartAceOk()
        if not ok then
            print('[WeatherSync] ^3WARNING:^7 the resource cannot run that command yet, so the restart will be IGNORED.')
            print(('[WeatherSync] Fix: add to server.cfg ->  add_ace %s %s allow  (then restart once)'):format(principal, ace))
        end
    else
        print(('[WeatherSync] Restart alert armed for %d seconds (warning only - no restart command).'):format(seconds))
    end

    TriggerClientEvent('weathersync:client:restartHud', -1, { active = true, seconds = seconds })
    CreateThread(function()
        local remain = seconds
        while myToken == restartToken and state.alert and remain > 0 do
            Wait(1000)
            remain = remain - 1
            restartRemain = remain
        end
        if myToken == restartToken and state.alert and remain <= 0 and doRestart then fireRestartCommand() end
    end)
end

local function cancelRestartCountdown()
    restartToken = restartToken + 1
    restartRemain = 0
    TriggerClientEvent('weathersync:client:restartHud', -1, { active = false })
end

-- doRestart = run the restart command at 0 (false for txAdmin, which restarts itself)
local function setAlert(on, seconds, doRestart)
    on = on and true or false
    if not Config.RestartAlert.enabled then return end
    if on == state.alert then
        if on then startRestartCountdown(seconds, doRestart ~= false) end   -- re-arm the timer
        return
    end

    if on then
        alertSaved = { weatherId = state.weatherId, blackout = state.blackout, dynamic = state.dynamic }
        state.alert, state.dynamic = true, false
        state.blackout = Config.RestartAlert.blackout and true or state.blackout
        -- a flood alert fills the water across the whole countdown (sent before the weather)
        if Config.RestartAlert.weatherId == 'flooding' then
            TriggerClientEvent('weathersync:client:floodPace', -1,
                math.floor(tonumber(seconds) or Config.RestartAlert.countdownSeconds))
        end
        setWeather(Config.RestartAlert.weatherId, true)
        if Config.RestartAlert.siren then TriggerClientEvent('weathersync:client:siren', -1, true) end
        startRestartCountdown(seconds, doRestart ~= false)
    else
        state.alert = false
        cancelRestartCountdown()
        TriggerClientEvent('weathersync:client:floodPace', -1, 0)
        TriggerClientEvent('weathersync:client:siren', -1, false)
        if alertSaved then
            state.blackout, state.dynamic = alertSaved.blackout, alertSaved.dynamic
            setWeather(alertSaved.weatherId, true)
            alertSaved = nil
        end
    end
    TriggerClientEvent('weathersync:client:setAlert', -1, state.alert)
    TriggerClientEvent('weathersync:client:setDynamic', -1, state.dynamic)
end

-- ------------------------------------------------------------
--  The Purge
-- ------------------------------------------------------------
local function startPurgeSiren(on)
    if not Config.Purge.siren then
        if on then print('[WeatherSync] Purge siren NOT sent - Config.Purge.siren is false in config.lua.') end
        return
    end
    if on then
        print(('[WeatherSync] Purge siren -> all clients (sound=%s, vol=%s, loop=%s).')
            :format(tostring(Config.Purge.sirenSound), tostring(Config.Purge.sirenVolume), tostring(Config.Purge.sirenLoop)))
    end
    TriggerClientEvent('weathersync:client:purgeSiren', -1, purgeSirenPayload(on))
end

-- Emergency Alert System banner: kind = 'start' | 'ending'
local function sendBroadcast(kind, target)
    local b = Config.Purge.broadcast
    if not (b and b.enabled) then return end
    local block = (kind == 'start') and b.start or b.ending
    if not block then return end
    local secs = (kind == 'start' and broadcastSeconds) or block.seconds or 9
    TriggerClientEvent('weathersync:client:purgeBroadcast', target or -1, {
        kind = kind, title = block.title, heading = block.heading, message = block.message, seconds = secs,
    })
end

local function endPurge()
    if not state.purge then return end
    purgeToken = purgeToken + 1
    state.purge, purgeScheduled = false, false
    purgePhase, purgeRemain = 'idle', 0

    startPurgeSiren(false)
    if Config.Purge.playEndSound and Config.Purge.endSound and Config.Purge.endSound ~= '' then
        print(('[WeatherSync] Purge END sound -> all clients (sound=%s, vol=%s).')
            :format(tostring(Config.Purge.endSound), tostring(Config.Purge.endSoundVolume)))
        TriggerClientEvent('weathersync:client:purgeSiren', -1, {
            on = true, volume = Config.Purge.endSoundVolume or 0.8, sound = Config.Purge.endSound, loop = false,
        })
    else
        print('[WeatherSync] Purge END sound NOT sent - playEndSound is false or endSound is empty.')
    end
    sendBroadcast('ending')
    TriggerClientEvent('weathersync:client:purgeHud', -1, { active = false })

    if purgeSaved then
        state.blackout = purgeSaved.blackout
        if Config.Purge.weather and Config.Purge.weather.enabled and purgeSaved.weatherId then
            state.dynamic = purgeSaved.dynamic
            setWeather(purgeSaved.weatherId, true)
        end
        purgeSaved = nil
        broadcastWeather()
    end
end

-- The purge goes live straight away: blackout, weather, broadcast
local function beginPurgeActive()
    purgeToken = purgeToken + 1
    purgePhase, purgeRemain = 'active', 0
    if Config.Purge.blackout then
        state.blackout = true
        broadcastWeather()
    end
    local w = Config.Purge.weather
    if w and w.enabled and w.weatherId then
        state.dynamic = false
        setWeather(w.weatherId, true)
    end
    -- (the start siren is already playing - don't restart it here)
    sendBroadcast('start')
    TriggerClientEvent('weathersync:client:purgeHud', -1, purgeHudPayload())
    print('[WeatherSync] The Purge has begun (blackout ' .. (Config.Purge.blackout and 'ON' or 'off') .. ').')

    -- optional auto-end - manual purges only (scheduled ones end at the end time)
    local hold = tonumber(Config.Purge.activeSeconds) or 0
    if hold > 0 and not purgeScheduled then
        local myToken = purgeToken
        SetTimeout(hold * 1000, function()
            if myToken == purgeToken and state.purge then endPurge() end
        end)
    end
end

local function startPurge(scheduled)
    if not state.purge then
        purgeSaved = { blackout = state.blackout, weatherId = state.weatherId, dynamic = state.dynamic }
        state.purge = true
    end
    purgeScheduled = scheduled
    startPurgeSiren(true)
    beginPurgeActive()
end

-- /purgenow: start or stop one right now
local function setPurge(on, seconds)
    if not Config.Purge.enabled then return end
    if on then
        if seconds then broadcastSeconds = math.floor(tonumber(seconds) or broadcastSeconds) end
        startPurge(false)
    else
        endPurge()
    end
end

-- the panel button: enable/disable the schedule (never starts a purge right away)
local function setSchedule(on, seconds)
    scheduleOn = on and true or false
    if seconds then broadcastSeconds = math.floor(tonumber(seconds) or broadcastSeconds) end
    if scheduleOn then
        scheduleRanWindow = true   -- wait for the next scheduled start
    elseif state.purge and purgeScheduled then
        endPurge()
    end
    TriggerClientEvent('weathersync:client:setPurge', -1, scheduleOn)
end

-- inside the schedule window? (handles windows that wrap past midnight)
local function inPurgeWindow(h, m)
    local sc = Config.Purge.schedule
    local cur = h * 60 + m
    local s = (sc.startHour or 0) * 60 + (sc.startMin or 0)
    local e = (sc.endHour or 0) * 60 + (sc.endMin or 0)
    if s == e then return false end
    if s < e then return cur >= s and cur < e end
    return cur >= s or cur < e
end

CreateThread(function()
    Wait(4000)   -- let the clock settle after boot
    local sc0 = Config.Purge.schedule or {}
    print(('[WeatherSync] Purge schedule: enabled=%s, window %02d:%02d->%02d:%02d, siren=%s/%s. Use /purgestatus any time.')
        :format(tostring(scheduleOn), sc0.startHour or 0, sc0.startMin or 0, sc0.endHour or 0, sc0.endMin or 0,
                tostring(Config.Purge.siren), tostring(Config.Purge.sirenSound)))
    while true do
        if Config.Purge.enabled and scheduleOn and Config.Purge.schedule then
            if inPurgeWindow(state.hour, state.minute) then
                if not state.purge and not scheduleRanWindow then
                    print(('[WeatherSync] SCHEDULE fired at %02d:%02d - starting the purge.'):format(state.hour, state.minute))
                    startPurge(true)
                    scheduleRanWindow = true
                end
            else
                scheduleRanWindow = false   -- window passed: arm again for the next night
                if state.purge and purgeScheduled then endPurge() end
            end
        end
        Wait(2000)
    end
end)

-- ------------------------------------------------------------
--  Sync & panel events
-- ------------------------------------------------------------
RegisterNetEvent('weathersync:server:requestSync', function() pushFullState(source) end)

AddEventHandler('playerJoining', function()
    local src = source
    SetTimeout(2000, function()
        pushFullState(src)
        -- the client holds the banner until they've loaded in
        if state.purge and purgePhase == 'active' then sendBroadcast('start', src) end
    end)
end)

RegisterNetEvent('weathersync:server:checkAdmin', function()
    TriggerClientEvent('weathersync:client:setAdmin', source, isAdmin(source))
end)

RegisterNetEvent('weathersync:server:requestMenu', function()
    local src = source
    if isAdmin(src) then TriggerClientEvent('weathersync:client:openMenu', src)
    else notify(src, 'You do not have permission to use this.', 'error') end
end)

RegisterNetEvent('weathersync:server:setWeather', function(key)
    local src = source
    if not adminOnly(src) then return end
    local ok, entry = setWeather(key, false, src)
    if ok then notify(src, 'Weather set to ' .. entry.label, 'success') else notify(src, 'Invalid weather.', 'error') end
end)

RegisterNetEvent('weathersync:server:setTime', function(hour, minute)
    local src = source
    if not adminOnly(src) then return end
    if setTime(hour, minute) then notify(src, ('Time set to %02d:%02d'):format(state.hour, state.minute), 'success')
    else notify(src, 'Invalid time.', 'error') end
end)

-- simple on/off switches from the panel
local function onOff(v) return v and 'on' or 'off' end
local SWITCHES = {
    toggleFreeze    = function(v) state.freeze = v; broadcastTime(); return 'Time freeze ' .. onOff(v) .. '.' end,
    toggleBlackout  = function(v) state.blackout = v; broadcastWeather(); return 'Blackout ' .. onOff(v) .. '.' end,
    toggleDynamic   = function(v)
        state.dynamic = v
        TriggerClientEvent('weathersync:client:setDynamic', -1, v)
        return 'Auto weather ' .. onOff(v) .. '.'
    end,
    toggleLightning = function(v)
        state.lightning = v
        TriggerClientEvent('weathersync:client:setLightning', -1, v)
        return 'Ground lightning ' .. onOff(v) .. '.'
    end,
}
for name, apply in pairs(SWITCHES) do
    RegisterNetEvent('weathersync:server:' .. name, function(value)
        local src = source
        if not adminOnly(src) then return end
        notify(src, apply(value and true or false), 'primary')
    end)
end

RegisterNetEvent('weathersync:server:toggleAlert', function(value, seconds)
    local src = source
    if not adminOnly(src) then return end
    setAlert(value, seconds, true)   -- from the panel = run the real restart at 0
    notify(src, 'Restart alert ' .. (state.alert and 'ACTIVE' or 'cleared') .. '.', state.alert and 'error' or 'success')
end)

RegisterNetEvent('weathersync:server:togglePurge', function(value, seconds)
    local src = source
    if not adminOnly(src) then return end
    setSchedule(value, seconds)
    if scheduleOn then notify(src, 'Scheduled purge ENABLED - it will run at the set time.', 'primary')
    else notify(src, 'Scheduled purge disabled.', 'success') end
end)

-- warn before a txAdmin scheduled restart (txAdmin does the restart itself)
local alertFiredForRestart = false
AddEventHandler('txAdmin:events:scheduledRestart', function(data)
    if not Config.RestartAlert.enabled then return end
    local threshold = Config.RestartAlert.autoTriggerSeconds or 0
    local remaining = data and data.secondsRemaining
    if threshold <= 0 or type(remaining) ~= 'number' then return end
    if remaining <= threshold and not alertFiredForRestart then
        alertFiredForRestart = true
        setAlert(true, remaining, false)
    end
end)

-- ------------------------------------------------------------
--  Commands (admin-only)
-- ------------------------------------------------------------
RegisterCommand(Config.WeatherCommand, function(source, args)
    if not adminOnly(source) then return end
    if not args[1] then return notify(source, 'Usage: /' .. Config.WeatherCommand .. ' <id>', 'error') end
    local ok, entry = setWeather(args[1], false, source)
    if ok then notify(source, 'Weather set to ' .. entry.label, 'success')
    else notify(source, 'Invalid. Try: sunny, cloudy, heavyrain, storm, snow, tornado, flooding...', 'error') end
end, false)

RegisterCommand(Config.TimeCommand, function(source, args)
    if not adminOnly(source) then return end
    if not args[1] then return notify(source, 'Usage: /' .. Config.TimeCommand .. ' <hour 0-23> [minute]', 'error') end
    if setTime(args[1], args[2]) then notify(source, ('Time set to %02d:%02d'):format(state.hour, state.minute), 'success')
    else notify(source, 'Invalid time.', 'error') end
end, false)

-- runs the restart command right now (says in console if permission is missing)
RegisterCommand('weathersync_testrestart', function(source)
    if not adminOnly(source) then return end
    local cmd = Config.RestartAlert.restartCommand or ''
    if cmd == '' then
        print('[WeatherSync] restartCommand is empty - nothing to run.')
        if source ~= 0 then notify(source, 'restartCommand is empty in config.lua.', 'error') end
        return
    end
    local ok, ace, principal = restartAceOk()
    if not ok then
        print(('[WeatherSync] Cannot run "%s" - missing permission. Add to server.cfg:  add_ace %s %s allow'):format(cmd, principal, ace))
        if source ~= 0 then notify(source, 'Restart is blocked by permissions - check the server console for the server.cfg line to add.', 'error') end
        return
    end
    if source ~= 0 then notify(source, 'Running restart command now...', 'primary') end
    print('[WeatherSync] Test restart - executing: ' .. cmd)
    ExecuteCommand(cmd)
end, false)

-- /purgenow [seconds]: start a purge right now (run again to end it)
RegisterCommand('purgenow', function(source, args)
    if not adminOnly(source) then return end
    if state.purge then
        setPurge(false)
        if source ~= 0 then notify(source, 'Purge ended.', 'success') end
    else
        setPurge(true, args[1])
        if source ~= 0 then notify(source, 'Purge started (test).', 'error') end
    end
end, false)

RegisterCommand('purgestatus', function(source)
    if not adminOnly(source) then return end
    local sc = Config.Purge.schedule or {}
    print('==== WeatherSync Purge status ====')
    print(('  Config.Purge.enabled        : %s'):format(tostring(Config.Purge.enabled)))
    print(('  schedule ON (button)        : %s'):format(tostring(scheduleOn)))
    print(('  window                      : %02d:%02d -> %02d:%02d'):format(sc.startHour or 0, sc.startMin or 0, sc.endHour or 0, sc.endMin or 0))
    print(('  current in-game time        : %02d:%02d   (frozen: %s)'):format(state.hour, state.minute, tostring(state.freeze)))
    print(('  inside window right now     : %s'):format(tostring(inPurgeWindow(state.hour, state.minute))))
    print(('  purge running               : %s  (scheduled=%s, phase=%s)'):format(tostring(state.purge), tostring(purgeScheduled), purgePhase))
    print(('  siren enabled / file        : %s / %s'):format(tostring(Config.Purge.siren), tostring(Config.Purge.sirenSound)))
    print(('  start loop sound            : %s'):format(tostring(Config.Purge.sirenLoop)))
    print(('  end sound on / file         : %s / %s'):format(tostring(Config.Purge.playEndSound), tostring(Config.Purge.endSound)))
    print(('  start broadcast (seconds)   : %s'):format(tostring(broadcastSeconds)))
    print('==================================')
    if source ~= 0 then notify(source, 'Purge status printed to the server console.', 'primary') end
end, false)

-- drop the gd_tornado funnel near you
RegisterCommand('tornadohere', function(source)
    if source == 0 then return print('[WeatherSync] /tornadohere must be run in-game.') end
    if not adminOnly(source) then return end
    if GetResourceState('gd_tornado') ~= 'started' then
        return notify(source, 'gd_tornado is not running - the folder must be named exactly "gd_tornado".', 'error')
    end
    if state.addon == 'tornado' then serverAddonStop('tornado'); state.addon = nil end   -- force a fresh spawn
    setWeather('tornado', false, source)
    notify(source, 'Tornado spawned near you.', 'success')
end, false)

-- prints your identifiers for Config.AdminIdentifiers
RegisterCommand('weathersync_whoami', function(source)
    if source == 0 then return print('[WeatherSync] Run this in-game to see your identifiers.') end
    notify(source, 'Your identifiers were printed to the F8 console (copy one into Config.AdminIdentifiers).', 'primary')
    print(('[WeatherSync] Identifiers for %s:'):format(GetPlayerName(source) or source))
    for _, id in ipairs(GetPlayerIdentifiers(source) or {}) do
        print('   ' .. id)
        TriggerClientEvent('chat:addMessage', source, { color = { 0, 170, 255 }, args = { 'WeatherSync', id } })
    end
end, false)

-- ------------------------------------------------------------
--  Boot
-- ------------------------------------------------------------
AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    math.randomseed(os.time())
    SetTimeout(1500, function()
        updateServerAddon(Config.GetWeather(state.weatherId))
        broadcastWeather()
        broadcastTime()
    end)
end)
