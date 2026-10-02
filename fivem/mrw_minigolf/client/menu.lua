-- Start card, group invites, quit confirmation and the group scorecard.

local menuOpen = false
GroupRows = {}      -- scorecard rows for everyone in our group, from the server

local function nearbyPlayers()
    local me, myPos, out = PlayerId(), GetEntityCoords(PlayerPedId()), {}
    for _, pid in ipairs(GetActivePlayers()) do
        if pid ~= me then
            local ped = GetPlayerPed(pid)
            if DoesEntityExist(ped) and #(GetEntityCoords(ped) - myPos) <= (Config.invite_range or 8.0) then
                out[#out + 1] = { id = GetPlayerServerId(pid), name = GetPlayerName(pid) }
            end
        end
    end
    return out
end

local function labels()
    local keys = { 'menu_title', 'menu_price', 'menu_holes', 'menu_invite', 'menu_nobody', 'menu_start',
        'menu_cancel', 'menu_refresh', 'invite_title', 'invite_text', 'invite_accept', 'invite_decline',
        'quit_title', 'quit_text', 'quit_yes', 'quit_no', 'hole', 'score', 'total', 'menu_solo', 'menu_group',
        'pricing', 'card_title', 'card_name', 'card_keep', 'card_close', 'card_left', 'card_group', 'card_total',
        'card_ticket', 'card_holeno', 'card_score' }
    local out = {}
    for _, k in ipairs(keys) do out[k] = translation[k] or k end
    return out
end

local function setFocus(on)
    SetNuiFocus(on, on)
end

-- ------------------------------------------------------------------ start
function OpenStartMenu()
    if menuOpen or IsPlayingGolf() then return end
    menuOpen = true
    setFocus(true)
    SendNUIMessage({
        ui = 'Start', status = true,
        tickets = Config.tickets,
        holes = #Config.golf_track,
        course = Config.course_name,
        players = nearbyPlayers(),
        maxGroup = Config.max_group or 4,
        labels = labels()
    })
end

local function closeStart()
    menuOpen = false
    setFocus(false)
    SendNUIMessage({ ui = 'Start', status = false })
end

RegisterNUICallback('start', function(data, cb)
    closeStart()
    local ids = {}
    if type(data.invite) == 'table' then
        for _, id in ipairs(data.invite) do
            if tonumber(id) then ids[#ids + 1] = tonumber(id) end
        end
    end
    TriggerServerEvent('mrw_minigolf:requestStart', ids, tostring(data.ticket or ''))
    cb('ok')
end)

RegisterNUICallback('cancel', function(_, cb)
    closeStart()
    cb('ok')
end)

RegisterNUICallback('refresh', function(_, cb)
    cb(nearbyPlayers())
end)

-- ---------------------------------------------------------------- invites
RegisterNetEvent('mrw_minigolf:invited')
AddEventHandler('mrw_minigolf:invited', function(hostName, seconds)
    if IsPlayingGolf() then return end
    setFocus(true)
    SendNUIMessage({
        ui = 'Invite', status = true,
        host = hostName, tickets = Config.tickets, seconds = seconds or 30,
        labels = labels()
    })
end)

RegisterNUICallback('inviteAnswer', function(data, cb)
    setFocus(false)
    TriggerServerEvent('mrw_minigolf:inviteAnswer', data.accept == true, tostring(data.ticket or ''))
    cb('ok')
end)

-- ------------------------------------------------------------------- quit
local function strokesSoFar()
    local n = 0
    for _, h in ipairs(allGame or {}) do n = n + (h.stroke or 0) end
    return n
end

RegisterCommand('golfquit', function()
    if not IsPlayingGolf() then return end
    setFocus(true)
    SendNUIMessage({ ui = 'Quit', status = true, strokes = strokesSoFar(), labels = labels() })
end, false)
RegisterKeyMapping('golfquit', 'Minigolf: quit the game', 'keyboard', Config.quit_key or 'DELETE')

RegisterNUICallback('quitAnswer', function(data, cb)
    setFocus(false)
    if data.quit == true then QuitGolf() end
    cb('ok')
end)

-- -------------------------------------------------------------- scorecard
RegisterNetEvent('mrw_minigolf:groupScores')
AddEventHandler('mrw_minigolf:groupScores', function(rows)
    GroupRows = rows or {}
    if ScoreboardIsShowing and ScoreboardIsShowing() then Ui:displayScoreboard(true) end
end)

-- --------------------------------------------------------------- scorecard
-- end of a round: show the card, offer to keep it
RegisterNetEvent('mrw_minigolf:finalCard')
AddEventHandler('mrw_minigolf:finalCard', function(card, canKeep)
    Wait(800)   -- let the "nice shot" banner and fade finish first
    setFocus(true)
    SendNUIMessage({ ui = 'Card', status = true, card = card, canKeep = canKeep, labels = labels() })
end)

-- using the scorecard item (qb-inventory from the server, ox_inventory client.event)
RegisterNetEvent('mrw_minigolf:viewCard')
AddEventHandler('mrw_minigolf:viewCard', function(data, slot)
    local meta = (slot and slot.metadata) or (data and (data.metadata or data.info)) or data
    if type(meta) ~= 'table' or not meta.strokes then return end
    setFocus(true)
    SendNUIMessage({ ui = 'Card', status = true, card = meta, canKeep = false, labels = labels() })
end)

RegisterNUICallback('keepCard', function(_, cb)
    setFocus(false)
    TriggerServerEvent('mrw_minigolf:keepCard')
    cb('ok')
end)

RegisterNUICallback('closeCard', function(_, cb)
    setFocus(false)
    cb('ok')
end)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then SetNuiFocus(false, false) end
end)
