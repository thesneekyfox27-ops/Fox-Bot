-- Author : Morow
-- Github : https://github.com/Morow73

-- Credit for research
-- https://github.com/Sainan/GTA-V-Decompiled-Scripts/blob/master/decompiled_scripts/golf_mp.c
-- https://www.vespura.com/fivem/scaleform/

Ui = {}
Ui.__index = Ui

function Ui:displayNotification(str)
    BeginTextCommandThefeedPost("STRING")
    AddTextComponentString(str)
    EndTextCommandThefeedPostTicker(false, true)
end

function Ui:displayHelpNotification(request)
    BeginTextCommandDisplayHelp("THREESTRINGS")

    for i = 1,#request,1 do
        AddTextComponentSubstringPlayerName(request[i])
    end

    EndTextCommandDisplayHelp(0, false, true, request.duration or 5000)
end

function Ui:fadeOut(time)
    CreateThread(function()
        if not IsScreenFadedOut() then
            DoScreenFadeOut(time)
        else
            DoScreenFadeIn(100)
        end
    end)
end

function Ui:fadeIn()
    DoScreenFadeIn(150)
end

function Ui:drawLine(coords, coords2)
    DrawLine(coords.x, coords.y, coords.z, coords2.x, coords2.y, coords2.z, 255, 0, 0, 0.8)
end

function Ui:displayScoreboard(display)
    if display then
        -- the group's scorecard from the server, or just our own if it hasn't arrived
        local rows = GroupRows
        if not rows or #rows == 0 then
            local strokes = {}
            for i, h in ipairs(allGame or {}) do strokes[i] = h.stroke or 0 end
            rows = { { id = GetPlayerServerId(PlayerId()), name = GetPlayerName(PlayerId()), strokes = strokes, me = true } }
        end
        SendNuiMessage(json.encode({
            status = true,
            ui = 'Scoreboard',
            holes = #Config.golf_track,
            rows = rows,
            myId = GetPlayerServerId(PlayerId()),
            course = Config.course_name,
            labels = {
                hole = translation["hole"] or "Hole", total = translation["total"] or "Total",
                card_title = translation["card_title"] or "Scorecard", card_name = translation["card_name"] or "Participant's name",
                card_holeno = translation["card_holeno"] or "Hole no", card_score = translation["card_score"] or "Score",
                card_total = translation["card_total"] or "Total", card_group = translation["card_group"] or "Your group"
            }
        }))
    else
        SendNuiMessage(json.encode({
            status = false,
            ui = 'Scoreboard'
        }))
    end
end

function Ui:displayPowerBar(display, power)
    if display then
        SendNuiMessage(json.encode({
            status = true,
            ui = 'Power',
            data = tonumber(power * 100)
        }))
  
    else
        SendNuiMessage(json.encode({
            status = false,
            ui = 'Power',
            data = 0
        }))
    end
end

--- Controls card on the right side while lined up to putt.
function Ui:displayControls(display)
    if not display then
        SendNuiMessage(json.encode({ ui = 'Controls', status = false }))
        return
    end
    local k = Config.control_keys or {}
    SendNuiMessage(json.encode({
        ui = 'Controls',
        status = true,
        title = translation['controls_title'] or 'Controls',
        items = {
            { key = k.putt or 'LMB',          label = translation['ctl_putt'] or 'Hold to charge, release to putt' },
            { key = k.turn or '\u{2190} \u{2192}', label = translation['ctl_turn'] or 'Turn around the ball' },
            { key = k.step or 'X',            label = translation['ctl_step'] or 'Step away' },
            { key = k.card or 'INSERT',       label = translation['ctl_card'] or 'Scorecard (hold)' },
            { key = Config.quit_key or 'DELETE', label = translation['ctl_quit'] or 'Quit game' },
        }
    }))
end
