-- Only does anything when a QB-style core is present. Standalone saves client-side.

local CORE_CANDIDATES = { 'qb-core', 'qbx_core', 'tgiann-core' }

local function detectCore()
    local forced = Config.CoreResource
    if forced and forced ~= 'auto' then
        if GetResourceState(forced) == 'started' then return forced end
        return nil
    end
    for _, r in ipairs(CORE_CANDIDATES) do
        if GetResourceState(r) == 'started' then return r end
    end
    return nil
end

local coreName = detectCore()
local function usingQB()
    if Config.Framework == 'standalone' then return false end
    return coreName ~= nil
end

local function invName()
    return Config.InventoryResource or 'tgiann-inventory'
end

if usingQB() then
    local QBCore = exports[coreName]:GetCoreObject()

    local function clamp(v)
        v = tonumber(v) or 0
        if v < 0 then v = 0 end
        if v > Config.MaxStat then v = Config.MaxStat end
        return math.floor(v)
    end

    ------------------------------------------------------------------
    -- Strength / stamina persistence
    ------------------------------------------------------------------
    RegisterNetEvent('ms_gym:save', function(strength, stamina, lastTrained, energy, energyStamp)
        local src = source
        local Player = QBCore.Functions.GetPlayer(src)
        if not Player then return end
        Player.Functions.SetMetaData('strength', clamp(strength))
        Player.Functions.SetMetaData('stamina', clamp(stamina))
        if lastTrained ~= nil then
            Player.Functions.SetMetaData('gymLastTrained', math.floor(tonumber(lastTrained) or 0))
        end
        if energy ~= nil then
            Player.Functions.SetMetaData('gymEnergy', math.floor(tonumber(energy) or 0))
        end
        if energyStamp ~= nil then
            Player.Functions.SetMetaData('gymEnergyStamp', math.floor(tonumber(energyStamp) or 0))
        end
    end)

    ------------------------------------------------------------------
    -- Gym pass (gym_pass item + rolling 24-in-game-hour expiry)
    -- The client sends its current in-game-minute counter; the server stamps and
    -- validates against it, so removal is a legitimate server-authored action.
    ------------------------------------------------------------------
    local function passWindow()
        return (Config.GymPass.durationIgHours or 24) * 60
    end

    RegisterNetEvent('ms_gym:buyPass', function(nowMin)
        local src = source
        local Player = QBCore.Functions.GetPlayer(src)
        if not Player then return end

        nowMin = math.floor(tonumber(nowMin) or 0)
        local cfg     = Config.GymPass
        local price   = cfg.price or 0
        local account = cfg.account or 'cash'

        -- Still inside an active window? Re-grant without charging again.
        local existing = Player.PlayerData.metadata.gympass
        if existing and existing.buyMin and (nowMin - existing.buyMin) < passWindow()
           and (nowMin - existing.buyMin) >= 0 then
            TriggerClientEvent('ms_gym:passGranted', src, existing.buyMin)
            return
        end

        if Player.Functions.RemoveMoney(account, price, 'muscle-sands-gym-pass') then
            Player.Functions.SetMetaData('gympass', { buyMin = nowMin })
            Player.Functions.AddItem(cfg.item, 1, false, { buyMin = nowMin })
            TriggerClientEvent('ms_gym:passGranted', src, nowMin)
        else
            TriggerClientEvent('ms_gym:passDenied', src,
                ('You need $%d (%s) for a gym pass.'):format(price, account))
        end
    end)

    -- Client reports its in-game time when it believes the pass expired. The
    -- server only removes the item if ITS OWN stored stamp confirms the window
    -- has elapsed, and removes exactly once (no loop) to stay anticheat-safe.
    RegisterNetEvent('ms_gym:clearPass', function(nowMin)
        local src = source
        local Player = QBCore.Functions.GetPlayer(src)
        if not Player then return end

        nowMin = math.floor(tonumber(nowMin) or 0)
        local gp = Player.PlayerData.metadata.gympass
        if not (gp and gp.buyMin) then
            Player.Functions.SetMetaData('gympass', false)
            return
        end

        if (nowMin - gp.buyMin) >= passWindow() then
            Player.Functions.SetMetaData('gympass', false)
            if Config.GymPass.requireItem then
                local itemName = Config.GymPass.item
                -- tgiann-inventory: remove via its server export when configured.
                -- pcall guards a mismatched signature; the qb removal below clears
                -- whatever is left (item is unique, so there's no double-remove).
                if Config.GymPass.hasItemExport then
                    pcall(function()
                        exports[invName()]:RemoveItem(src, itemName, 1)
                    end)
                end
                local item = Player.Functions.GetItemByName(itemName)
                if item then
                    Player.Functions.RemoveItem(itemName, item.amount or 1, item.slot)
                end
            end
        end
    end)
end
