local QBCore = exports['qb-core']:GetCoreObject()

-- The parts you have wiped off, kept so they can go back on exactly as they were.
-- Mirrors the copy in player metadata.
-- Shape: { [overlayIndex] = { value, colourType, first, second, opacity } }
local saved = {}
local busy = false
local loggedIn = false

local NONE = 255
local HEAD_BONE = 31086

local partByIndex = {}
for _, part in ipairs(Config.Parts) do partByIndex[part.index] = part end

--------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------

local function notify(msg, kind)
    lib.notify({ title = Locales.menu_title, description = msg, type = kind or 'inform' })
end

local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function hasSaved()
    return next(saved) ~= nil
end

--- What the ped has on for one overlay, or nil when it's bare.
local function readPart(ped, index)
    local ok, value, colourType, first, second, opacity = GetPedHeadOverlayData(ped, index)
    if not ok or value == NONE then return nil end
    return { value = value, colourType = colourType, first = first, second = second, opacity = opacity }
end

--- Every configured part the ped is wearing right now.
local function readWorn()
    local ped, worn = PlayerPedId(), {}
    for _, part in ipairs(Config.Parts) do
        worn[part.index] = readPart(ped, part.index)
    end
    return worn
end

local function strip(indices)
    local ped = PlayerPedId()
    for _, index in ipairs(indices) do
        SetPedHeadOverlay(ped, index, NONE, 0.0)
    end
end

local function restore(index, o)
    local ped = PlayerPedId()
    SetPedHeadOverlay(ped, index, o.value, (o.opacity or 1.0) + 0.0)
    SetPedHeadOverlayColor(ped, index, o.colourType or 0, o.first or 0, o.second or 0)
end

--- Same makeup as the saved copy? (the appearance script put it back)
local function sameLook(a, b)
    return a.value == b.value
        and (a.first or 0) == (b.first or 0)
        and math.abs((a.opacity or 1.0) - (b.opacity or 1.0)) < 0.05
end

local function pushSaved()
    TriggerServerEvent('tn_makeup:server:save', hasSaved() and saved or nil)
end

local function setSaved(data)
    saved = {}
    if type(data) ~= 'table' then return end
    for key, o in pairs(data) do
        local index = tonumber(key)
        if index and partByIndex[index] and type(o) == 'table' and tonumber(o.value) then
            saved[index] = o
        end
    end
end

local function canUse()
    local ped = PlayerPedId()
    local r = Config.Restrictions
    local meta = QBCore.Functions.GetPlayerData().metadata or {}

    if not r.dead and (IsEntityDead(ped) or meta.isdead or meta.inlaststand) then return false end
    if not r.cuffed and meta.ishandcuffed then return false end
    if not r.swimming and IsPedSwimming(ped) then return false end
    if not r.falling and IsPedFalling(ped) then return false end
    if not r.inVehicle and IsPedInAnyVehicle(ped, false) then return false end
    if not r.ragdoll and IsPedRagdoll(ped) then return false end

    return true
end

--------------------------------------------------------------------
-- Keeping the saved look in step with what's on your face
--
-- Appearance scripts (17mov, illenium, qb-clothing) reload the whole ped on
-- spawn, relog and outfit changes, makeup included. So while something is
-- wiped off we keep checking:
--   * the saved makeup came back   -> take it off again
--   * different makeup appeared    -> you got a new look at the barber, keep
--                                     it and forget the old saved one
--------------------------------------------------------------------

local function reconcile()
    if not hasSaved() then return end
    local ped = PlayerPedId()
    local changed = false

    for index, o in pairs(saved) do
        local now = readPart(ped, index)
        if now then
            if sameLook(now, o) then
                SetPedHeadOverlay(ped, index, NONE, 0.0)
            else
                saved[index] = nil
                changed = true
            end
        end
    end

    if changed then pushSaved() end
end

CreateThread(function()
    while true do
        Wait(Config.WatchEvery or 1500)
        -- Not while a menu has focus: that's the barber / clothing UI
        -- previewing looks, and the result only counts once it's closed.
        if loggedIn and hasSaved() and not busy and not IsNuiFocused() and not IsPauseMenuActive() then
            reconcile()
        end
    end
end)

--------------------------------------------------------------------
-- Animation + "mirror" camera
--
-- Everything here degrades instead of throwing: a bad dict or prop just means
-- no animation, the palette still works.
--------------------------------------------------------------------

local function tryLoadAnimDict(dict)
    if not dict or not DoesAnimDictExist(dict) then return false end
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 3000
    while not HasAnimDictLoaded(dict) do
        if GetGameTimer() > timeout then return false end
        Wait(10)
    end
    return true
end

local function tryLoadModel(model)
    if not model then return false end
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelValid(hash) then return false end
    RequestModel(hash)
    local timeout = GetGameTimer() + 3000
    while not HasModelLoaded(hash) do
        if GetGameTimer() > timeout then return false end
        Wait(10)
    end
    return hash
end

local cam

local function stopCamera()
    if not cam then return end
    RenderScriptCams(false, true, 400, true, true)
    DestroyCam(cam, false)
    cam = nil
end

local function startCamera()
    local c = Config.Camera
    if not c or not c.Enabled or cam then return end
    local ped = PlayerPedId()
    local head = GetPedBoneCoords(ped, HEAD_BONE, 0.0, 0.0, 0.0)
    local fwd = GetEntityForwardVector(ped)
    local pos = head + fwd * (c.Distance or 0.55)

    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', pos.x, pos.y, pos.z + 0.02, 0.0, 0.0, 0.0, (c.Fov or 40.0) + 0.0, false, 0)
    PointCamAtCoord(cam, head.x, head.y, head.z)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 400, true, true)
end

local function playMakeupAnim(label, duration)
    local ped = PlayerPedId()
    local a = Config.Anim
    local prop

    local dictLoaded = tryLoadAnimDict(a.dict)
    if dictLoaded then
        TaskPlayAnim(ped, a.dict, a.name, 3.0, 3.0, -1, a.flag, 0, false, false, false)
    end

    if a.prop then
        local hash = tryLoadModel(a.prop)
        if hash then
            prop = CreateObject(hash, 0.0, 0.0, 0.0, true, true, false)
            AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, a.bone),
                a.offset.x, a.offset.y, a.offset.z,
                a.rot.x, a.rot.y, a.rot.z,
                true, true, false, true, 1, true)
            SetModelAsNoLongerNeeded(hash)
        end
    end

    startCamera()

    local opts = {
        duration = duration,
        label = label,
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
    }

    local completed
    if Config.ProgressCircle and lib.progressCircle then
        opts.position = 'bottom'
        completed = lib.progressCircle(opts)
    else
        completed = lib.progressBar(opts)
    end

    -- Cleanup always runs, whatever the progress bar returned
    stopCamera()
    ClearPedTasks(ped)
    if prop and DoesEntityExist(prop) then DeleteEntity(prop) end
    if dictLoaded then RemoveAnimDict(a.dict) end

    return completed == true
end

local function durationFor(n)
    return n > 1 and Config.Progress or (Config.ProgressSingle or Config.Progress)
end

--------------------------------------------------------------------
-- Actions
--------------------------------------------------------------------

local function removeParts(indices)
    local worn = readWorn()
    local todo = {}
    for _, index in ipairs(indices) do
        if worn[index] then todo[#todo + 1] = index end
    end
    if #todo == 0 then return notify(Locales.nothing, 'error') end

    if not playMakeupAnim(Locales.progress_remove, durationFor(#todo)) then
        return notify(Locales.cancelled, 'error')
    end

    -- Read again: something may have changed during the animation
    worn = readWorn()
    for _, index in ipairs(todo) do
        if worn[index] then saved[index] = worn[index] end
    end
    strip(todo)
    pushSaved()

    if #todo == 1 then
        notify(Locales.removed_one:format(partByIndex[todo[1]].label), 'success')
    else
        notify(Locales.removed, 'success')
    end
end

local function applyParts(indices)
    local todo = {}
    for _, index in ipairs(indices) do
        if saved[index] then todo[#todo + 1] = index end
    end
    if #todo == 0 then return notify(Locales.nothing, 'error') end

    if not playMakeupAnim(Locales.progress_apply, durationFor(#todo)) then
        return notify(Locales.cancelled, 'error')
    end

    for _, index in ipairs(todo) do
        if saved[index] then
            restore(index, saved[index])
            saved[index] = nil
        end
    end
    pushSaved()

    if #todo == 1 then
        notify(Locales.reapplied_one:format(partByIndex[todo[1]].label), 'success')
    else
        notify(Locales.reapplied, 'success')
    end
end

--- Wraps an action so `busy` is ALWAYS released, even if the action errors.
local function run(action, ...)
    busy = true
    local ok, err = pcall(action, ...)
    busy = false

    if not ok then
        print('^1[tn_makeup_palette]^7 action failed: ' .. tostring(err))
        stopCamera()
        ClearPedTasks(PlayerPedId())
        notify('Something went wrong. Try again.', 'error')
    end
end

--------------------------------------------------------------------
-- Menu
--------------------------------------------------------------------

local function openMenu()
    reconcile()
    local worn = readWorn()
    local wornList, savedList = {}, {}
    for _, part in ipairs(Config.Parts) do
        if worn[part.index] then
            wornList[#wornList + 1] = part
        elseif saved[part.index] then
            savedList[#savedList + 1] = part
        end
    end

    if #wornList == 0 and #savedList == 0 then
        return notify(Locales.nothing, 'error')
    end

    local options = {}

    if #wornList > 1 then
        local all = {}
        for i, part in ipairs(wornList) do all[i] = part.index end
        options[#options + 1] = {
            title = Locales.remove_all,
            description = Locales.remove_all_desc,
            icon = 'droplet',
            onSelect = function() run(removeParts, all) end,
        }
    end
    for _, part in ipairs(wornList) do
        options[#options + 1] = {
            title = Locales.remove_one:format(part.label),
            description = Locales.wearing,
            icon = part.icon,
            onSelect = function() run(removeParts, { part.index }) end,
        }
    end

    if #savedList > 1 then
        local all = {}
        for i, part in ipairs(savedList) do all[i] = part.index end
        options[#options + 1] = {
            title = Locales.apply_all,
            description = Locales.apply_all_desc,
            icon = 'wand-magic-sparkles',
            onSelect = function() run(applyParts, all) end,
        }
    end
    for _, part in ipairs(savedList) do
        options[#options + 1] = {
            title = Locales.apply_one:format(part.label),
            description = Locales.saved,
            icon = part.icon,
            onSelect = function() run(applyParts, { part.index }) end,
        }
    end

    options[#options + 1] = { title = Locales.close, icon = 'xmark' }

    lib.registerContext({ id = 'tn_makeup_menu', title = Locales.menu_title, options = options })
    lib.showContext('tn_makeup_menu')
end

--------------------------------------------------------------------
-- Loading the saved look
--
-- Asked for by the client whenever a character is ready, so it no longer
-- depends on the server seeing one particular "player loaded" event.
--------------------------------------------------------------------

local function fetchSaved()
    local data = lib.callback.await('tn_makeup:getSaved', false)
    setSaved(data)
    loggedIn = true
    -- The appearance script usually loads a moment later; the watcher
    -- takes it off again whenever it comes back.
    if hasSaved() then SetTimeout(500, reconcile) end
end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    SetTimeout(1000, fetchSaved)
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    loggedIn = false
    saved = {}
end)

AddEventHandler('onClientResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    if LocalPlayer.state.isLoggedIn then CreateThread(fetchSaved) end
end)

AddEventHandler('playerSpawned', function()
    if loggedIn then CreateThread(fetchSaved) end
end)

-- Server push (kept so other resources can still send it)
RegisterNetEvent('tn_makeup:client:sync', function(data)
    setSaved(data)
    loggedIn = true
    if hasSaved() then SetTimeout(500, reconcile) end
end)

--------------------------------------------------------------------
-- Item use
--------------------------------------------------------------------

RegisterNetEvent('tn_makeup:client:use', function()
    if busy then
        -- Say so out loud rather than failing silently. If this ever fires
        -- when you are not mid-animation, /makeupreset clears it.
        return notify(Locales.busy, 'error')
    end
    if not canUse() then
        return notify(Locales.cant_use, 'error')
    end
    openMenu()
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    stopCamera()
    if busy then ClearPedTasks(PlayerPedId()) end
end)

--------------------------------------------------------------------
-- Escape hatch
--------------------------------------------------------------------

RegisterCommand('makeupreset', function()
    busy = false
    stopCamera()
    ClearPedTasks(PlayerPedId())
    notify(Locales.reset, 'success')
end, false)

--------------------------------------------------------------------
-- Exports
--------------------------------------------------------------------

-- Forget the saved look (e.g. call it after the barber saves a new one).
exports('ClearSaved', function()
    saved = {}
    pushSaved()
end)

exports('HasSavedMakeup', function()
    return hasSaved()
end)

-- Which parts are wiped off right now, e.g. { [8] = true } for lipstick.
exports('GetSavedParts', function()
    local out = {}
    for index in pairs(saved) do out[index] = true end
    return out
end)
