-- nrp-megaphone client
-- Based on fd-megaphones (GPL-3.0). Rewritten: server-validated state,
-- statebag-synced voice effect (late joiners hear it too), auto-off,
-- prop cleanup, vehicle PA job lock, stage mics via ox_target / nrp-target.

local QBCore = GetResourceState('qb-core') ~= 'missing' and exports['qb-core']:GetCoreObject() or nil

local mode       = nil     -- 'handheld' | 'vehicle' | 'stage' | nil
local prop       = 0
local stageMic   = 0

local function dbg(...) if Config.Debug then print('[nrp-megaphone]', ...) end end

-- am I talking right now?
-- The game's voice state first; if it has never reported us talking this
-- session ('auto'), fall back to the mic level measured by the NUI page.
local gameTalkSeen, micTalking = false, false
local function gameTalking()
    local pid = PlayerId()
    local t = NetworkIsPlayerTalking(pid) or MumbleIsPlayerTalking(pid)
    if t then gameTalkSeen = true end
    return t
end
local function useMicGate()
    local g = Config.Monitor and Config.Monitor.Gate or 'auto'
    if g == 'mic' then return true end
    if g == 'game' then return false end
    return not gameTalkSeen
end
-- Push-to-talk: the game's PTT control (whatever key the player bound in
-- Settings > Key Bindings). Once we've seen it pressed this session we assume
-- the player uses PTT, and the mic level only counts while it's held - so you
-- never hear yourself when you aren't actually transmitting.
local PTT = 249   -- INPUT_PUSH_TO_TALK
local pttSeen = false
local function pttHeld()
    local held = IsControlPressed(0, PTT) or IsDisabledControlPressed(0, PTT)
    if held then pttSeen = true end
    return held
end
local function micCounts()
    if not micTalking then return false end
    if Config.Monitor and Config.Monitor.RequirePtt == false then return true end
    return (not pttSeen and not pttHeld()) or pttHeld()
end
local function meTalking()
    return gameTalking() or (useMicGate() and micCounts())
end
local notify = Config.Notify

------------------------------------------------------------------------
-- helpers
------------------------------------------------------------------------
local function playerData()
    if not QBCore then return {} end
    local ok, pd = pcall(function() return QBCore.Functions.GetPlayerData() end)
    return ok and pd or {}
end

local function jobAllowed(jobs)
    if not jobs then return true end
    local job = playerData().job and playerData().job.name
    for _, j in ipairs(jobs) do if j == job then return true end end
    return false
end

-- true / false, or nil when we can't tell (then we never switch it off for it)
local function hasItem()
    if GetResourceState('tgiann-inventory') == 'started' then
        local ok, res = pcall(function() return exports['tgiann-inventory']:HasItem(Config.ItemName, 1) end)
        if ok and (res == true or (type(res) == 'number' and res > 0)) then return true end
        if ok and (res == false or res == 0) then return false end
    end
    local items = playerData().items
    if type(items) ~= 'table' or next(items) == nil then return nil end
    for _, v in pairs(items) do
        if v.name == Config.ItemName and (v.amount or v.count or 0) > 0 then return true end
    end
    return false
end

-- returns 'down' | 'restrained' | 'swimming' | nil
local function blockedReason()
    local ped = PlayerPedId()
    local meta = playerData().metadata or {}
    if Config.AutoOff.Dead and (meta.isdead or meta.inlaststand or IsEntityDead(ped)) then return 'down' end
    if Config.AutoOff.Cuffed and (meta.ishandcuffed or meta.isziptied or IsPedCuffed(ped)) then return 'restrained' end
    if Config.AutoOff.Swimming and IsPedSwimming(ped) then return 'swimming' end
    return nil
end
local function cantNow(why) notify(("You can't use that while %s."):format(why), 'error') end

local function vehicleHasPA(veh)
    if veh == 0 then return false end
    local model = GetEntityModel(veh)
    for _, m in ipairs(Config.Vehicle.Models or {}) do
        if model == (type(m) == 'string' and joaat(m) or m) then return true end
    end
    local class = GetVehicleClass(veh)
    for _, c in ipairs(Config.Vehicle.Classes or {}) do if class == c then return true end end
    return false
end

local function inFrontSeat(veh)
    if not Config.Vehicle.FrontSeatsOnly then return true end
    local ped = PlayerPedId()
    return GetPedInVehicleSeat(veh, -1) == ped or GetPedInVehicleSeat(veh, 0) == ped
end

------------------------------------------------------------------------
-- handheld animation + prop
------------------------------------------------------------------------
local function removeProp()
    if prop ~= 0 and DoesEntityExist(prop) then DeleteEntity(prop) end
    prop = 0
end

local function startHandheld()
    local a, ped = Config.Anim, PlayerPedId()
    lib.requestAnimDict(a.dict, 5000)
    lib.requestModel(a.prop, 5000)
    removeProp()
    local c = GetEntityCoords(ped)
    prop = CreateObject(joaat(a.prop), c.x, c.y, c.z + 0.2, true, true, false)
    SetEntityCollision(prop, false, false)
    AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, a.bone), a.pos.x, a.pos.y, a.pos.z, a.rot.x, a.rot.y, a.rot.z, true, true, false, false, 2, true)
    SetModelAsNoLongerNeeded(joaat(a.prop))
    TaskPlayAnim(ped, a.dict, a.clip, 3.0, 3.0, -1, 49, 0, false, false, false)
end

local function stopHandheld()
    StopAnimTask(PlayerPedId(), Config.Anim.dict, Config.Anim.clip, 3.0)
    removeProp()
end

------------------------------------------------------------------------
-- on / off
------------------------------------------------------------------------
local MODE_LABEL = { handheld = 'Megaphone', vehicle = 'Vehicle PA', stage = 'Microphone' }

local function setMode(newMode, quiet, reason)
    if newMode == mode then return end
    local old = mode
    mode = newMode

    if old == 'handheld' then stopHandheld() end
    if old == 'stage' then stageMic = 0 end

    if newMode then
        pcall(function() exports['pma-voice']:overrideProximityRange(Config.Range[newMode], true) end)
        MumbleSetAudioInputIntent(`music`)
        if newMode == 'handheld' then startHandheld() end
    else
        pcall(function() exports['pma-voice']:clearProximityOverride() end)
        MumbleSetAudioInputIntent(`speech`)
    end

    TriggerServerEvent('nrp-megaphone:server:setMode', newMode)

    if not quiet then
        if newMode then
            notify(('%s on - your voice carries %dm.'):format(MODE_LABEL[newMode], math.floor(Config.Range[newMode])), 'success')
        else
            notify(reason or (MODE_LABEL[old] .. ' off.'), reason and 'error' or 'inform')
        end
    end
    dbg('mode', tostring(old), '->', tostring(newMode))
end

RegisterNetEvent('nrp-megaphone:client:denied', function(why)
    setMode(nil, true)
    if why and why ~= 'disabled' then notify(why, 'error') end
end)

-- HANDHELD: use the item
RegisterNetEvent('nrp-megaphone:client:useItem', function()
    if mode == 'handheld' then return setMode(nil) end
    if not Config.Handheld.Enabled then return end
    if not jobAllowed(Config.Handheld.Jobs) then return notify("You can't use this.", 'error') end
    local why = blockedReason()
    if why then return cantNow(why) end
    setMode('handheld')
end)

-- VEHICLE PA: key / command
RegisterCommand('vehmega', function()
    if not Config.Vehicle.Enabled then return end
    if mode == 'vehicle' then return setMode(nil) end
    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    if veh == 0 then return end
    if not vehicleHasPA(veh) then return notify("This vehicle doesn't have a PA.", 'error') end
    if not inFrontSeat(veh) then return notify('Only the front seats can use the PA.', 'error') end
    if not jobAllowed(Config.Vehicle.Jobs) then return notify('This PA is for emergency services.', 'error') end
    local why = blockedReason()
    if why then return cantNow(why) end
    setMode('vehicle')
end, false)
RegisterKeyMapping('vehmega', '(Voice) Vehicle PA / megaphone', 'keyboard', Config.Vehicle.Key)

-- STAGE MICS: third eye / [E]
CreateThread(function()
    if not Config.Stage.Enabled then return end
    Wait(1000)
    local opts = {
        {
            name = 'nrp_mega_mic_on', icon = 'fa-solid fa-microphone', label = 'Use microphone', distance = 1.5,
            canInteract = function() return mode ~= 'stage' end,
            onSelect = function(data)
                local why = blockedReason()
                if why then return cantNow(why) end
                stageMic = data.entity or 0
                if stageMic == 0 then return end
                setMode('stage')
            end,
        },
        {
            name = 'nrp_mega_mic_off', icon = 'fa-solid fa-microphone-slash', label = 'Step away from microphone', distance = 1.5,
            canInteract = function() return mode == 'stage' end,
            onSelect = function() setMode(nil) end,
        },
    }
    if GetResourceState('ox_target') == 'started' then
        exports.ox_target:addModel(Config.Stage.Models, opts)
    elseif GetResourceState('qb-target') == 'started' then
        exports['qb-target']:AddTargetModel(Config.Stage.Models, {
            options = {
                { icon = opts[1].icon, label = opts[1].label, canInteract = opts[1].canInteract,
                  action = function(entity) opts[1].onSelect({ entity = entity }) end },
                { icon = opts[2].icon, label = opts[2].label, canInteract = opts[2].canInteract,
                  action = function() setMode(nil) end },
            },
            distance = 1.5,
        })
    end
end)

------------------------------------------------------------------------
-- watcher: switch off when the reason to be on goes away
------------------------------------------------------------------------
CreateThread(function()
    while true do
        if not mode then
            Wait(1000)
        else
            Wait(400)
            local ped = PlayerPedId()
            local why = blockedReason()
            if why then
                setMode(nil, false, ('%s off - you are %s.'):format(MODE_LABEL[mode], why))
            elseif mode == 'handheld' then
                if hasItem() == false then
                    setMode(nil, false, 'Megaphone off - you no longer have it.')
                elseif prop == 0 or not DoesEntityExist(prop) or not IsEntityAttachedToEntity(prop, ped) then
                    startHandheld()          -- prop got lost (ragdoll, model change...)
                elseif not IsEntityPlayingAnim(ped, Config.Anim.dict, Config.Anim.clip, 3) and not IsPedInAnyVehicle(ped, false) then
                    TaskPlayAnim(ped, Config.Anim.dict, Config.Anim.clip, 3.0, 3.0, -1, 49, 0, false, false, false)
                end
            elseif mode == 'vehicle' then
                local veh = GetVehiclePedIsIn(ped, false)
                if veh == 0 or not vehicleHasPA(veh) or not inFrontSeat(veh) then setMode(nil) end
            elseif mode == 'stage' then
                if stageMic == 0 or not DoesEntityExist(stageMic)
                   or #(GetEntityCoords(ped) - GetEntityCoords(stageMic)) > Config.Stage.Radius then
                    setMode(nil, false, 'Microphone off - you stepped away.')
                end
            end
        end
    end
end)

------------------------------------------------------------------------
-- the voice effect other players hear (synced by statebag)
------------------------------------------------------------------------
-- Two versions of the megaphone voice:
--   'clear'   - you can see the speaker
--   'muffled' - a wall / building is between you (or one of you is inside and
--               the other isn't): low-passed and quieter, but still audible
local submixes = {}
local LOUD = Config.Loudness or {}

local function gainFor(mode)
    if not LOUD.Enabled then return 1.0 end
    return (LOUD.Gain and LOUD.Gain[mode]) or 1.0
end

-- one submix per look (clear / muffled) and mode (handheld / vehicle / stage), so each can be its own loudness
local function buildSubmix(kind, mode)
    local key = kind .. '_' .. (mode or 'handheld')
    if submixes[key] then return submixes[key] end
    local e = Config.Effect
    local m = (kind == 'muffled') and (Config.Occlusion or {}) or nil
    local id = CreateAudioSubmix('nrp_megaphone_' .. key)
    SetAudioSubmixEffectRadioFx(id, 1)
    SetAudioSubmixEffectParamInt(id, 1, `default`, 1)
    SetAudioSubmixEffectParamFloat(id, 1, `freq_low`, e.freq_low)
    SetAudioSubmixEffectParamFloat(id, 1, `freq_hi`, m and m.CutOff or e.freq_hi)
    SetAudioSubmixEffectParamFloat(id, 1, `rm_mod_freq`, e.rm_mod_freq)
    SetAudioSubmixEffectParamFloat(id, 1, `rm_mix`, m and (e.rm_mix * 0.5) or e.rm_mix)
    SetAudioSubmixEffectParamFloat(id, 1, `fudge`, e.fudge)
    SetAudioSubmixEffectParamFloat(id, 1, `o_freq_lo`, m and 80.0 or e.o_freq_lo)
    SetAudioSubmixEffectParamFloat(id, 1, `o_freq_hi`, m and m.CutOff or e.o_freq_hi)
    local v = gainFor(mode) * (m and (m.Volume or 0.85) or 1.0)
    SetAudioSubmixOutputVolumes(id, 0, v, v, v, v, v, v)
    AddAudioSubmixOutput(id, 1)
    submixes[key] = id
    return id
end

local effected = {}   -- serverId -> 'clear_vehicle' etc. while applied
local overridden = {} -- serverId -> volume we set (steady loudness instead of the normal fade)

local function applyEffect(serverId, kind, mode)
    if serverId == GetPlayerServerId(PlayerId()) then return end
    if kind then
        local key = kind .. '_' .. (mode or 'handheld')
        if effected[serverId] ~= key then
            MumbleSetSubmixForServerId(serverId, buildSubmix(kind, mode))
            effected[serverId] = key
        end
    elseif effected[serverId] then
        MumbleSetSubmixForServerId(serverId, -1)
        effected[serverId] = nil
    end
end

-- Loud and steady across the whole range: full volume near the speaker, FarVolume at the edge.
local function setLoudness(serverId, dist, range, force)
    if not LOUD.Enabled then return end
    if not dist then
        if overridden[serverId] then
            MumbleSetVolumeOverrideByServerId(serverId, -1.0)
            overridden[serverId] = nil
        end
        return
    end
    local far = LOUD.FarVolume or 0.5
    local vol = far + (1.0 - far) * math.max(0.0, 1.0 - dist / range)
    if force or not overridden[serverId] or math.abs(overridden[serverId] - vol) > 0.04 then
        MumbleSetVolumeOverrideByServerId(serverId, vol)
        overridden[serverId] = vol
    end
end

-- Is there something solid between me and this speaker?
local function isOccluded(pid)
    local O = Config.Occlusion
    if not O or not O.Enabled then return false end
    local me, them = PlayerPedId(), GetPlayerPed(pid)
    if them == 0 or not DoesEntityExist(them) then return false end

    -- one of us is inside a building (MLO / interior) and the other isn't, or different buildings
    if O.Interiors then
        local a, b = GetInteriorFromEntity(me), GetInteriorFromEntity(them)
        if a ~= b then return true end
    end

    -- walls in the way (world geometry only; people and cars don't count)
    if O.Walls then
        local p1 = GetPedBoneCoords(me, 31086, 0.0, 0.0, 0.0)     -- head
        local p2 = GetPedBoneCoords(them, 31086, 0.0, 0.0, 0.0)
        local ray = StartExpensiveSynchronousShapeTestLosProbe(p1.x, p1.y, p1.z, p2.x, p2.y, p2.z, 1, me, 4)
        local _, hit = GetShapeTestResult(ray)
        if hit == 1 then return true end
    end
    return false
end

local function kindFor(pid)
    return isOccluded(pid) and 'muffled' or 'clear'
end

AddStateBagChangeHandler('megaphone', nil, function(bagName, _, value)
    local sid = tonumber(bagName:match('^player:(%d+)$'))
    if not sid then return end
    if not value then
        applyEffect(sid, nil)
        return setLoudness(sid, nil)
    end
    local pid = GetPlayerFromServerId(sid)
    applyEffect(sid, pid ~= -1 and kindFor(pid) or 'clear', value)
end)

-- Keep it right: re-check walls as people move (fast while someone nearby is on
-- a megaphone), and re-apply after pma-voice resets a submix (radio use).
CreateThread(function()
    local lastFull = 0
    while true do
        local busy = false
        local now = GetGameTimer()
        local full = now - lastFull > 2500
        if full then lastFull = now end
        local myPos = GetEntityCoords(PlayerPedId())
        for _, pid in ipairs(GetActivePlayers()) do
            local sid = GetPlayerServerId(pid)
            local st = Player(sid).state.megaphone
            if st then
                local dist = #(myPos - GetEntityCoords(GetPlayerPed(pid)))
                local range = (Config.Range[st] or 50.0) + 10.0
                if dist <= range then
                    busy = true
                    local kind = kindFor(pid)
                    if full and not MumbleIsPlayerTalking(pid) then effected[sid] = nil end   -- force a re-apply
                    applyEffect(sid, kind, st)
                    -- re-set every few seconds: pma-voice resets volumes after radio / phone calls
                    setLoudness(sid, dist, Config.Range[st] or 50.0, full)
                elseif full then
                    applyEffect(sid, 'clear', st)
                    setLoudness(sid, nil)
                end
            elseif effected[sid] or overridden[sid] then
                applyEffect(sid, nil)
                setLoudness(sid, nil)
            end
        end
        Wait(busy and ((Config.Occlusion and Config.Occlusion.CheckEvery) or 400) or 1000)
    end
end)

------------------------------------------------------------------------
-- talk clicks: start / stop sound while a megaphone is on
------------------------------------------------------------------------
local function click(sound, volume)
    if volume <= 0.001 then return end
    SendNUIMessage({ action = 'click', sound = sound, volume = volume })
end

CreateThread(function()
    local TS = Config.TalkSounds
    if not TS or not TS.Enabled then return end
    local selfTalking = false
    local othersTalking = {}   -- serverId -> bool
    while true do
        local busy = false

        -- me
        if mode then
            busy = true
            local now = meTalking()
            if now ~= selfTalking then
                selfTalking = now
                click(now and 'start' or 'stop', TS.Volume)
            end
        elseif selfTalking then
            selfTalking = false
        end

        -- people near me who have a megaphone on
        if TS.OthersHear then
            local myPos = GetEntityCoords(PlayerPedId())
            local myId = PlayerId()
            for _, pid in ipairs(GetActivePlayers()) do
                if pid ~= myId then
                    local sid = GetPlayerServerId(pid)
                    if Player(sid).state.megaphone then
                        local dist = #(myPos - GetEntityCoords(GetPlayerPed(pid)))
                        if dist <= TS.OthersRange then
                            busy = true
                            local now = MumbleIsPlayerTalking(pid)
                            if now ~= (othersTalking[sid] or false) then
                                othersTalking[sid] = now
                                local v = TS.Volume * (1.0 - dist / TS.OthersRange)
                                if effected[sid] and effected[sid]:find('^muffled') then v = v * ((Config.Occlusion and Config.Occlusion.Volume) or 0.6) * 0.6 end
                                click(now and 'start' or 'stop', v)
                            end
                        else
                            othersTalking[sid] = nil
                        end
                    else
                        othersTalking[sid] = nil
                    end
                end
            end
        end

        Wait(busy and 100 or 750)
    end
end)

------------------------------------------------------------------------
-- hear yourself (self-monitor)
------------------------------------------------------------------------
local MON = Config.Monitor or {}
local monitorPref = GetResourceKvpInt('nrp_mega_monitor')   -- 0 = unset, 1 = on, 2 = off
local function monitorWanted()
    if not MON.Enabled then return false end
    if monitorPref == 0 then return MON.DefaultOn ~= false end
    return monitorPref == 1
end
local monitorLive, monitorWarned = false, false

local function monitorSet(on)
    if on == monitorLive then return end
    monitorLive = on
    SendNUIMessage({ action = 'monitor', state = on, cfg = {
        volume = MON.Volume, echoDelay = MON.EchoDelay, echoFeedback = MON.EchoFeedback,
        echoMix = MON.EchoMix, drive = MON.Drive, micThreshold = MON.MicThreshold,
    } })
    if not on then micTalking = false end
end

RegisterNUICallback('monitorStarted', function(_, cb) dbg('monitor running') cb(1) end)
RegisterNUICallback('vad', function(d, cb) micTalking = d and d.state == true cb(1) end)
RegisterNUICallback('monitorFailed', function(data, cb)
    print(('[nrp-megaphone] hear-yourself unavailable: %s'):format(tostring(data and data.reason)))
    if not monitorWarned then
        monitorWarned = true
        notify("Your game didn't allow the mic playback, so you can't hear yourself - others still hear the megaphone.", 'error')
    end
    cb(1)
end)

RegisterCommand('megamonitor', function()
    monitorPref = monitorWanted() and 2 or 1
    SetResourceKvpInt('nrp_mega_monitor', monitorPref)
    if monitorPref == 1 then SendNUIMessage({ action = 'monitorRetry' }) monitorWarned = false end
    notify(monitorPref == 1 and 'You will hear yourself on the megaphone.' or "You won't hear yourself on the megaphone.", 'inform')
end, false)

CreateThread(function()
    local wasTalking, lastUseMic = false, nil
    while true do
        local want = mode ~= nil and monitorWanted()
        monitorSet(want)
        if want then
            local now = gameTalking()
            if now ~= wasTalking then
                wasTalking = now
                SendNUIMessage({ action = 'monitorTalk', state = now })
            end
            -- mic level may open the playback only while it would really be transmitting
            local um = useMicGate() and (Config.Monitor.RequirePtt == false or not pttSeen or pttHeld())
            if um ~= lastUseMic then
                lastUseMic = um
                SendNUIMessage({ action = 'gateMode', useMic = um })
            end
            Wait(30)
        else
            wasTalking, lastUseMic = false, nil
            Wait(500)
        end
    end
end)

------------------------------------------------------------------------
-- /megadebug - paste the F8 output
------------------------------------------------------------------------
local nui = { ready = false, lastClick = 'none', monitor = 'never started', clicksPlayed = 0, clickErrors = 0 }
RegisterNUICallback('ready', function(_, cb) nui.ready = true cb(1) end)
RegisterNUICallback('clickResult', function(d, cb)
    if d and d.ok then nui.clicksPlayed = nui.clicksPlayed + 1 else nui.clickErrors = nui.clickErrors + 1 nui.lastClick = tostring(d and d.err) end
    cb(1)
end)
RegisterNUICallback('monitorStatus', function(d, cb) nui.monitor = tostring(d and d.status) cb(1) end)

RegisterCommand('megadebug', function()
    local pid = PlayerId()
    print(('[nrp-megaphone] mode=%s  pageLoaded=%s  talkingNow: network=%s mumble=%s'):format(
        tostring(mode), tostring(nui.ready), tostring(NetworkIsPlayerTalking(pid)), tostring(MumbleIsPlayerTalking(pid))))
    print(('[nrp-megaphone] clicks played=%d  click errors=%d (last: %s)  talkSounds=%s vol=%.2f'):format(
        nui.clicksPlayed, nui.clickErrors, nui.lastClick, tostring(Config.TalkSounds and Config.TalkSounds.Enabled), Config.TalkSounds and Config.TalkSounds.Volume or 0))
    print(('[nrp-megaphone] hear-yourself: wanted=%s  live=%s  status=%s'):format(
        tostring(monitorWanted()), tostring(monitorLive), nui.monitor))
    SendNUIMessage({ action = 'testClick' })
    notify('Close F8 now. In 3 seconds: hold push-to-talk and TALK for 5 seconds.', 'inform')
    CreateThread(function()
        Wait(3000)
        notify('Talk now...', 'inform')
        local net, mum, mic, ptt, total = 0, 0, 0, 0, 0
        local t0 = GetGameTimer()
        while GetGameTimer() - t0 < 5000 do
            total = total + 1
            if NetworkIsPlayerTalking(pid) then net = net + 1 end
            if MumbleIsPlayerTalking(pid) then mum = mum + 1 end
            if micTalking then mic = mic + 1 end
            if pttHeld() then ptt = ptt + 1 end
            Wait(100)
        end
        print(('[nrp-megaphone] 5s talk test: game %d%% / mumble %d%% / mic level %d%% / PTT held %d%%  (using %s, ptt seen=%s)  clicks played=%d errors=%d'):format(
            math.floor(net * 100 / total), math.floor(mum * 100 / total), math.floor(mic * 100 / total), math.floor(ptt * 100 / total),
            useMicGate() and 'mic level' or 'game voice', tostring(pttSeen), nui.clicksPlayed, nui.clickErrors))
        notify('Talk test done - open F8 to see the result.', 'inform')
    end)
end, false)

------------------------------------------------------------------------
-- cleanup
------------------------------------------------------------------------
RegisterNetEvent('QBCore:Client:OnPlayerUnload', function() setMode(nil, true) end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if mode then
        pcall(function() exports['pma-voice']:clearProximityOverride() end)
        MumbleSetAudioInputIntent(`speech`)
        stopHandheld()
    end
    for sid in pairs(effected) do MumbleSetSubmixForServerId(sid, -1) end
    for sid in pairs(overridden) do MumbleSetVolumeOverrideByServerId(sid, -1.0) end
    SendNUIMessage({ action = 'monitor', state = false })
end)
