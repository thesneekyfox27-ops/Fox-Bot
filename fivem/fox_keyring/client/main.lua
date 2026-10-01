RegisterNetEvent('fox_keyring:client:open', function(id)
    if type(id) ~= 'string' or not id:find('^keyring_') then return end

    exports['tgiann-inventory']:OpenInventory('stash', id, {
        label = Config.Label,
        slots = Config.Slots,
        maxweight = Config.MaxWeight,
        whitelist = Config.KeysOnly and { Config.KeyItem } or nil,
    })
end)
