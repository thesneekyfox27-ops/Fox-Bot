local QBCore = exports['qb-core']:GetCoreObject()

local META_KEY = 'savedmakeup'

local allowed = {}
for _, part in ipairs(Config.Parts) do allowed[part.index] = true end

--------------------------------------------------------------------
-- Item use
--------------------------------------------------------------------

QBCore.Functions.CreateUseableItem(Config.Item, function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    TriggerClientEvent('tn_makeup:client:use', source)
end)

--------------------------------------------------------------------
-- Persistence via player metadata (no SQL needed - QBCore already writes
-- the metadata column to the players table on save/logout)
--------------------------------------------------------------------

local function getSaved(Player)
    local saved = Player.PlayerData.metadata[META_KEY]
    return type(saved) == 'table' and next(saved) and saved or nil
end

--- Only keep configured parts and plain numbers, so a client can't stuff
--- garbage into metadata.
local function sanitize(data)
    if type(data) ~= 'table' then return nil end
    local clean, n = {}, 0
    for key, o in pairs(data) do
        local index = tonumber(key)
        if index and allowed[index] and type(o) == 'table' and tonumber(o.value) then
            clean[index] = {
                value      = math.floor(tonumber(o.value)),
                colourType = tonumber(o.colourType) or 0,
                first      = tonumber(o.first) or 0,
                second     = tonumber(o.second) or 0,
                opacity    = math.min(math.max(tonumber(o.opacity) or 1.0, 0.0), 1.0),
            }
            n = n + 1
        end
    end
    return n > 0 and clean or nil, n
end

local function countSaved(saved)
    local n = 0
    if saved then for _ in pairs(saved) do n = n + 1 end end
    return n
end

RegisterNetEvent('tn_makeup:server:save', function(data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local before = countSaved(getSaved(Player))
    local clean, after = sanitize(data)
    Player.Functions.SetMetaData(META_KEY, clean or false)

    -- A single-use palette is used up when something gets wiped off,
    -- not when the saved look changes for any other reason.
    if Config.ConsumeItem and (after or 0) > before then
        Player.Functions.RemoveItem(Config.Item, 1)
    end
end)

lib.callback.register('tn_makeup:getSaved', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    return Player and getSaved(Player) or nil
end)

-- Push the saved state down on load. This is a server-side event with the
-- Player object as its argument (the old version listened for it as a net
-- event, so it never fired). The client also asks for itself.
AddEventHandler('QBCore:Server:PlayerLoaded', function(Player)
    if not Player or not Player.PlayerData then return end
    local saved = getSaved(Player)
    if saved then
        TriggerClientEvent('tn_makeup:client:sync', Player.PlayerData.source, saved)
    end
end)
