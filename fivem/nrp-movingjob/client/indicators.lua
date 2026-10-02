--[[ nrp-movingjob | client/indicators.lua
     Markers and ghost previews. main.lua sets fields on Indicators.state each
     frame and this draws whatever is set.

     The destination marker changes shape with range: a tall beacon you can
     pick out through a windscreen at 150m, a landing circle as you pull up,
     and the individual placement spots once you are on foot at the door.
]]

Indicators = {
    state = {
        pallet = nil,   -- vector3, next item waiting at the depot
        rear   = nil,   -- vector3, van rear loading point
        drop   = nil,   -- { coords, heading, cargoIdx } next placement spot
        zone   = nil,   -- vector3, the delivery address
        spots  = nil    -- { vector3, ... } every spot still to be filled
    },
    ghost = nil,
    ghostKey = nil
}

local function marker(coords, colour, scale, height)
    DrawMarker(
        1,                                      -- vertical cylinder
        coords.x, coords.y, coords.z - 0.95,
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        scale, scale, height or 0.55,
        colour[1], colour[2], colour[3], colour[4],
        false, false, 2, false, nil, nil, false
    )
end

local function arrow(coords, colour, height)
    local bob = math.sin(GetGameTimer() / 350.0) * 0.08
    DrawMarker(
        2,                                      -- down arrow
        coords.x, coords.y, coords.z + (height or 1.15) + bob,
        0.0, 0.0, 0.0,
        180.0, 0.0, 0.0,
        0.22, 0.22, 0.22,
        colour[1], colour[2], colour[3], colour[4],
        false, false, 2, false, nil, nil, false
    )
end

--- Tall translucent column, readable from a long way off.
local function beacon(coords, colour, radius, height)
    DrawMarker(
        1,
        coords.x, coords.y, coords.z - 1.0,
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        radius, radius, height,
        colour[1], colour[2], colour[3], colour[4],
        false, false, 2, false, nil, nil, false
    )
end

--- Translucent copy of the actual cargo piece, sat where it will end up.
function Indicators.setGhost(cargoIdx, coords, heading)
    if not cargoIdx then return Indicators.clearGhost() end
    local key = ('%s:%0.2f:%0.2f:%0.2f'):format(cargoIdx, coords.x, coords.y, coords.z)
    if Indicators.ghostKey == key and Indicators.ghost and DoesEntityExist(Indicators.ghost) then
        return
    end
    Indicators.clearGhost()

    local obj = Carry.spawnProp(cargoIdx, coords, heading)
    if not obj then return end

    SetEntityCollision(obj, false, false)
    SetEntityAlpha(obj, Config.Indicators.ghostAlpha, false)
    FreezeEntityPosition(obj, true)
    SetEntityInvincible(obj, true)
    SetEntityCanBeDamaged(obj, false)
    PlaceObjectOnGroundProperly(obj)

    Indicators.ghost = obj
    Indicators.ghostKey = key
end

function Indicators.clearGhost()
    if Indicators.ghost and DoesEntityExist(Indicators.ghost) then
        DeleteEntity(Indicators.ghost)
    end
    Indicators.ghost = nil
    Indicators.ghostKey = nil
end

function Indicators.clear()
    Indicators.state.pallet = nil
    Indicators.state.rear = nil
    Indicators.state.drop = nil
    Indicators.state.zone = nil
    Indicators.state.spots = nil
    Indicators.clearGhost()
end

CreateThread(function()
    while true do
        local wait = 500
        local cfg = Config.Indicators

        if cfg.enabled then
            local s = Indicators.state
            local pos = GetEntityCoords(PlayerPedId())

            -- Delivery address ---------------------------------------------
            if s.zone then
                local dist = #(pos - s.zone)
                if dist < cfg.zoneDrawDistance then
                    wait = 0
                    local c = cfg.colours.zone

                    if dist > cfg.zoneBeaconRange then
                        -- Far: a column tall enough to see over buildings.
                        beacon(s.zone, c, cfg.zoneRadius * 0.45, cfg.zoneBeaconHeight)
                        beacon(s.zone, c, cfg.zoneRadius, 0.6)
                    else
                        -- Close: just the landing circle, fading out as the
                        -- individual placement spots take over.
                        local fade = dist < cfg.drawDistance and 0.45 or 1.0
                        local faded = { c[1], c[2], c[3], math.floor(c[4] * fade) }
                        beacon(s.zone, faded, cfg.zoneRadius, 0.6)
                        if dist > cfg.drawDistance then
                            arrow(s.zone, c, 2.2)
                        end
                    end
                end
            end

            -- Next item at the depot ---------------------------------------
            if s.pallet and #(pos - s.pallet) < cfg.drawDistance then
                wait = 0
                if cfg.markers then
                    marker(s.pallet, cfg.colours.pickup, 0.9)
                    arrow(s.pallet, cfg.colours.pickup)
                end
            end

            -- Van rear ------------------------------------------------------
            if s.rear and #(pos - s.rear) < cfg.drawDistance then
                wait = 0
                if cfg.markers then
                    marker(s.rear, cfg.colours.van, 1.1)
                end
            end

            -- Every spot still to be filled ---------------------------------
            if s.spots and cfg.markers then
                local c = cfg.colours.spot
                for _, spot in ipairs(s.spots) do
                    if #(pos - spot) < cfg.drawDistance then
                        wait = 0
                        marker(spot, c, 0.55, 0.12)
                    end
                end
            end

            -- Where this piece goes -----------------------------------------
            if s.drop and #(pos - s.drop.coords) < cfg.drawDistance then
                wait = 0
                if cfg.markers then
                    marker(s.drop.coords, cfg.colours.drop, 0.8)
                    arrow(s.drop.coords, cfg.colours.drop)
                end
                if cfg.ghosts then
                    Indicators.setGhost(s.drop.cargoIdx, s.drop.coords, s.drop.heading)
                end
            elseif Indicators.ghost then
                Indicators.clearGhost()
            end
        end

        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    Indicators.clearGhost()
end)
