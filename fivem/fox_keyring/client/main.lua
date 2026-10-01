RegisterNetEvent('fox_keyring:client:open', function(id)
    if type(id) ~= 'string' or not id:find('^keyring_') then return end

    local data = {
        label = Config.Label,
        slots = Config.Slots,
        maxweight = Config.MaxWeight,
        whitelist = Config.KeysOnly and { Config.KeyItem } or nil,
    }

    -- Using an item closes the inventory first; opening again in the same moment gets ignored.
    Wait(Config.OpenDelay)

    local ok, err = pcall(function()
        exports['tgiann-inventory']:OpenInventory('stash', id, data)
    end)

    if not ok then
        print(('[fox_keyring] OpenInventory export failed (%s), using tgiann\'s open event instead'):format(tostring(err)))
        TriggerServerEvent('inventory:server:OpenInventory', 'stash', id, data)
    end
end)
