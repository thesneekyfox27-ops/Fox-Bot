-- Lets the server check whether this player has their hands up before their keyring can be searched.
lib.callback.register('fox_keyring:client:handsUp', function()
    local ped = PlayerPedId()
    for _, anim in ipairs(Config.Search.handsUpAnims) do
        if IsEntityPlayingAnim(ped, anim[1], anim[2], 3) then return true end
    end
    return false
end)

local function closestPlayer(maxDistance)
    local myPed = PlayerPedId()
    local coords = GetEntityCoords(myPed)
    local closest, closestDist = nil, maxDistance
    for _, player in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(player)
        if ped ~= myPed then
            local dist = #(coords - GetEntityCoords(ped))
            if dist < closestDist then
                closest, closestDist = GetPlayerServerId(player), dist
            end
        end
    end
    return closest
end

local function searchKeyring(serverId)
    if serverId then TriggerServerEvent('fox_keyring:server:searchKeyring', serverId) end
end

if not Config.Search.enabled then return end

RegisterCommand(Config.Search.command, function()
    local target = closestPlayer(Config.Search.distance)
    if not target then
        return TriggerEvent('QBCore:Notify', 'Nobody close enough.', 'error')
    end
    searchKeyring(target)
end, false)

CreateThread(function()
    if GetResourceState('ox_target') ~= 'started' then return end
    exports.ox_target:addGlobalPlayer({
        {
            name = 'fox_keyring_search',
            icon = 'fa-solid fa-key',
            label = 'Search keyring',
            distance = Config.Search.distance,
            onSelect = function(data)
                searchKeyring(GetPlayerServerId(NetworkGetPlayerIndexFromPed(data.entity)))
            end,
        },
    })
end)
