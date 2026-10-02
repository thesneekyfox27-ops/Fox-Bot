-- Author : Morow
-- Github : https://github.com/Morow73

DrawLineActive, ScaleformActive = false, false

function CheapestTicket()
    local low
    for _, tk in ipairs(Config.tickets or {}) do
        if not low or tk.price < low then low = tk.price end
    end
    return low or Config.club_price or 0
end

-- [E] at the club rental when no target system is running
function ZoneThread()
    while true do
        local d = 500
        local distance = #(GetEntityCoords(PlayerPedId()) - Config.locate_club)

        if distance <= 1.8 and not IsPlayingGolf() and not UsingTarget() then
            d = 1
            Ui:displayHelpNotification({
                translation['locate_club']:format(CheapestTicket())
            })
            if IsControlJustPressed(0, 38) then
                OpenStartMenu()
            end
        end

        Wait(d)
    end
end

function DisplayScaleform()
    if not s then return end
    if not ScaleformActive then ScaleformActive = true end

    while ScaleformActive do Wait(1)
        s:display()
    end
end

CreateThread(ZoneThread)
