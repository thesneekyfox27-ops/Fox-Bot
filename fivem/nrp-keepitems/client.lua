-- Tells the server when you're dead / downed (one of several signals it uses).
local QBCore = exports['qb-core']:GetCoreObject()
local last = false

CreateThread(function()
    while true do
        Wait(500)
        local ped = PlayerPedId()
        local pd = QBCore.Functions.GetPlayerData() or {}
        local m = pd.metadata or {}
        local sb = LocalPlayer.state
        local down = IsEntityDead(ped) or IsPedFatallyInjured(ped)
            or m.isdead == true or m.inlaststand == true
            or sb.isDead == true or sb.dead == true or sb.down == true
        if down ~= last then
            last = down
            TriggerServerEvent('nrp-keepitems:down', down)
        end
    end
end)
