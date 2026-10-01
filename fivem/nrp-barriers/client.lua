--[[
    nrp-barriers  v6  -  solid invisible walls, auto saved
    ---------------------------------------------------------------
    Walls save to walls.json automatically when you press ENTER,
    and go live for every player instantly. No config editing.

    How blocking works (two layers):
      1. REAL COLLISION. Every wall is lined with invisible, frozen
         panel props. GTA's own physics stops you, so peds stop and
         cars crash exactly like hitting a real wall.
      2. SWEEP GUARD. Every frame your movement since last frame is
         swept against every wall segment. If anything got past the
         panels (lag spike, ragdoll, 200 km/h car) you are put back
         on the side you came from. It never relies on a remembered
         side, so it can not be fooled by crossing in one frame.

    /barrier                open the barrier manager (list / teleport)
    /barrier build          draw a wall
        LEFT CLICK           drop a point
        RIGHT CLICK          undo last point
        PgUp / PgDn          raise / lower height
        ENTER                finish + SAVE
        BACKSPACE            cancel

    /barrier list           print all walls with their numbers (F8)
    /barrier tp 3           teleport to wall 3
    /barrier delete 3       delete wall number 3, permanently
    /barrier name 3 stairs  rename wall 3
    /barrier undo           delete the most recent wall
    /barrier wipe confirm   delete every wall
    /barrier show           toggle outlines
    /barrier panels         toggle showing the collision panels (debug)
    /barrier off            disable blocking while editing
    /barrier reload         resync from server
    ---------------------------------------------------------------
]]

local walls      = {}
local showWalls  = Config.ShowWalls
local showPanels = false
local blocking   = true
local building   = false
local highlight  = nil      -- wall index highlighted from the UI
local uiOpen     = false

local sqrt, abs, huge = math.sqrt, math.abs, math.huge

-- ============================================================================
--  HELPERS
-- ============================================================================

local function notify(msg, kind)
    if GetResourceState('ox_lib') == 'started' then
        pcall(function()
            exports.ox_lib:notify({ description = msg, type = kind or 'inform' })
        end)
    else
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName(msg)
        EndTextCommandThefeedPostTicker(false, false)
    end
    print('[nrp-barriers] ' .. msg)
end

-- Turns raw saved data into a wall with precomputed segments and a 2D
-- bounding box, so the per frame work is just a few multiplications.
local function buildWall(name, height, rawPoints)
    local pts = {}
    for _, p in ipairs(rawPoints or {}) do
        pts[#pts + 1] = vector3(p.x + 0.0, p.y + 0.0, p.z + 0.0)
    end

    local wall = {
        name   = name or 'unnamed',
        height = (tonumber(height) or Config.DefaultHeight) + 0.0,
        points = pts,
        segs   = {},
        minX = huge, minY = huge, maxX = -huge, maxY = -huge,
        minZ = huge, maxZ = -huge,
    }

    for _, p in ipairs(pts) do
        if p.x < wall.minX then wall.minX = p.x end
        if p.x > wall.maxX then wall.maxX = p.x end
        if p.y < wall.minY then wall.minY = p.y end
        if p.y > wall.maxY then wall.maxY = p.y end
        if p.z < wall.minZ then wall.minZ = p.z end
        if p.z > wall.maxZ then wall.maxZ = p.z end
    end

    for i = 1, #pts - 1 do
        local a, b   = pts[i], pts[i + 1]
        local dx, dy = b.x - a.x, b.y - a.y
        local len    = sqrt(dx * dx + dy * dy)

        -- zero length segments add nothing; the neighbours' end caps cover the joint
        if len > 0.05 then
            local ux, uy = dx / len, dy / len
            wall.segs[#wall.segs + 1] = {
                ax = a.x, ay = a.y, az = a.z,
                bx = b.x, by = b.y, bz = b.z,
                len = len,
                ux = ux, uy = uy,       -- along the segment
                nx = -uy, ny = ux,      -- perpendicular
            }
        end
    end

    return wall
end

-- 2D distance from (x, y) to a wall's bounding box. 0 when inside it.
local function distToWall(w, x, y)
    local dx = math.max(w.minX - x, 0.0, x - w.maxX)
    local dy = math.max(w.minY - y, 0.0, y - w.maxY)
    return sqrt(dx * dx + dy * dy)
end

local function wallBounds(w)
    return w.minZ - Config.FloorOffset, w.maxZ + w.height
end

-- ============================================================================
--  LAYER 1 - INVISIBLE COLLISION PANELS
-- ============================================================================

local panelModels = nil     -- usable models, widest first
local panels      = {}      -- [wall table] = { object handles }
local panelCount  = 0

local function loadPanelModels()
    if panelModels then return panelModels end
    panelModels = {}

    for _, name in ipairs(Config.PanelModels or {}) do
        local hash = type(name) == 'number' and name or GetHashKey(name)

        if IsModelInCdimage(hash) and IsModelValid(hash) then
            RequestModel(hash)
            local timeout = GetGameTimer() + 5000
            while not HasModelLoaded(hash) and GetGameTimer() < timeout do
                Wait(0)
            end

            if HasModelLoaded(hash) then
                local mn, mx   = GetModelDimensions(hash)
                local sx, sy   = mx.x - mn.x, mx.y - mn.y
                local alongX   = sx >= sy
                local width    = alongX and sx or sy
                local thick    = alongX and sy or sx
                local tall     = mx.z - mn.z

                if thick <= Config.MaxPanelThickness and width >= 0.5 and tall >= 0.5 then
                    panelModels[#panelModels + 1] = {
                        name = name, hash = hash, alongX = alongX,
                        width = width, thick = thick, tall = tall,
                        -- centre of the model's box in its own space
                        cx = (mn.x + mx.x) * 0.5,
                        cy = (mn.y + mx.y) * 0.5,
                        cz = (mn.z + mx.z) * 0.5,
                    }
                else
                    SetModelAsNoLongerNeeded(hash)
                end
            end
        end
    end

    table.sort(panelModels, function(a, b) return a.width > b.width end)

    if #panelModels == 0 then
        print('^3[nrp-barriers]^7 no usable panel model found - running on the sweep guard only. '
            .. 'Add a thin solid prop to Config.PanelModels for real collision.')
    else
        local names = {}
        for _, m in ipairs(panelModels) do
            names[#names + 1] = ('%s (%.1fm x %.1fm x %.2fm)'):format(m.name, m.width, m.tall, m.thick)
        end
        print('^2[nrp-barriers]^7 collision panels: ' .. table.concat(names, ', '))
    end

    return panelModels
end

-- Widest model that fits inside the segment, so panels never stick out past
-- the wall ends. Very short segments get the narrowest model, centred.
local function pickModel(len)
    for _, m in ipairs(panelModels) do
        if m.width <= len then return m end
    end
    return panelModels[#panelModels]
end

local function placePanel(m, tx, ty, tz, heading, list)
    if panelCount >= Config.MaxPanels then return end

    -- Put the centre of the model's box (not its origin) on the target point.
    local h      = math.rad(heading)
    local c, s   = math.cos(h), math.sin(h)
    local ox     = tx - (m.cx * c - m.cy * s)
    local oy     = ty - (m.cx * s + m.cy * c)
    local oz     = tz - m.cz

    local obj = CreateObjectNoOffset(m.hash, ox, oy, oz, false, false, false)
    if obj == 0 then return end

    SetEntityAsMissionEntity(obj, true, true)
    SetEntityRotation(obj, 0.0, 0.0, heading, 2, true)
    SetEntityCoordsNoOffset(obj, ox, oy, oz, false, false, false)
    FreezeEntityPosition(obj, true)
    SetEntityInvincible(obj, true)
    SetEntityCanBeDamaged(obj, false)
    SetEntityCollision(obj, true, true)
    SetEntityDynamic(obj, false)

    if showPanels then
        SetEntityAlpha(obj, 150, false)
    else
        SetEntityAlpha(obj, 0, false)
        SetEntityVisible(obj, false, false)
    end

    list[#list + 1] = obj
    panelCount = panelCount + 1
end

local function spawnPanels(w)
    local list = {}
    panels[w] = list

    for _, seg in ipairs(w.segs) do
        local m       = pickModel(seg.len)
        local heading = math.deg(math.atan(seg.uy, seg.ux)) - (m.alongX and 0.0 or 90.0)

        -- columns sit flush with both ends of the segment and overlap in the middle
        local cols = math.max(1, math.ceil(seg.len / m.width))
        if cols > 1 and (cols * m.width - seg.len) < 0.1 then cols = cols + 1 end

        for ci = 1, cols do
            local t
            if cols == 1 then
                t = 0.5
            else
                local half = (m.width * 0.5) / seg.len
                t = half + (1.0 - 2.0 * half) * ((ci - 1) / (cols - 1))
            end

            -- vertical extent of this column, following the slope of the ground
            local halfT = math.min(0.5, (m.width * 0.5) / seg.len)
            local z1 = seg.az + (seg.bz - seg.az) * math.max(0.0, t - halfT)
            local z2 = seg.az + (seg.bz - seg.az) * math.min(1.0, t + halfT)
            local bottom = math.min(z1, z2) - Config.FloorOffset
            local top    = math.max(z1, z2) + w.height
            local span   = top - bottom

            local rows = math.max(1, math.ceil(span / m.tall))
            local tx   = seg.ax + seg.ux * seg.len * t
            local ty   = seg.ay + seg.uy * seg.len * t

            for ri = 1, rows do
                local tz
                if rows == 1 then
                    tz = bottom + m.tall * 0.5
                else
                    tz = bottom + m.tall * 0.5 + (span - m.tall) * ((ri - 1) / (rows - 1))
                end
                placePanel(m, tx, ty, tz, heading, list)
            end
        end
    end
end

local function despawnPanels(w)
    local list = panels[w]
    if not list then return end
    for _, obj in ipairs(list) do
        if DoesEntityExist(obj) then
            SetEntityAsMissionEntity(obj, true, true)
            DeleteObject(obj)
        end
        panelCount = panelCount - 1
    end
    panels[w] = nil
end

local function despawnAllPanels()
    for w in pairs(panels) do despawnPanels(w) end
    panels     = {}
    panelCount = 0
end

local function setPanelsVisible(state)
    for _, list in pairs(panels) do
        for _, obj in ipairs(list) do
            if DoesEntityExist(obj) then
                SetEntityVisible(obj, state, false)
                SetEntityAlpha(obj, state and 150 or 0, false)
            end
        end
    end
end

-- Streams panels in and out around the player.
CreateThread(function()
    if not Config.UsePanels then return end
    loadPanelModels()
    if #panelModels == 0 then return end

    while true do
        local pos = GetEntityCoords(PlayerPedId())

        for _, w in ipairs(walls) do
            local d = distToWall(w, pos.x, pos.y)
            if blocking and d < Config.PanelRange then
                if not panels[w] then spawnPanels(w) end
            elseif panels[w] and (not blocking or d > Config.PanelRange + 25.0) then
                despawnPanels(w)
            end
        end

        Wait(500)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    despawnAllPanels()
    if uiOpen then SetNuiFocus(false, false) end
end)

-- ============================================================================
--  SYNC
-- ============================================================================

CreateThread(function()
    Wait(1000)
    TriggerServerEvent('nrp-barriers:request')
    print('^2[nrp-barriers]^7 v6 ready - requesting walls from server. /barrier to open the menu')
end)

local function pushUi()
    if not uiOpen then return end
    local pos  = GetEntityCoords(PlayerPedId())
    local list = {}
    for i, w in ipairs(walls) do
        local lo, hi = wallBounds(w)
        list[#list + 1] = {
            index    = i,
            name     = w.name,
            points   = #w.points,
            height   = w.height,
            zMin     = lo,
            zMax     = hi,
            distance = distToWall(w, pos.x, pos.y),
            x        = (w.minX + w.maxX) * 0.5,
            y        = (w.minY + w.maxY) * 0.5,
        }
    end
    SendNUIMessage({
        action    = 'walls',
        walls     = list,
        highlight = highlight,
        blocking  = blocking,
        outlines  = showWalls,
    })
end

-- Server is the source of truth. Every add/remove rebroadcasts to everyone.
RegisterNetEvent('nrp-barriers:sync', function(data)
    despawnAllPanels()
    walls = {}

    for _, w in ipairs(data or {}) do
        walls[#walls + 1] = buildWall(w.name, w.height, w.points)
    end

    if highlight and not walls[highlight] then highlight = nil end

    print(('^2[nrp-barriers]^7 synced %d wall(s)'):format(#walls))
    pushUi()
end)

RegisterNetEvent('nrp-barriers:saved', function(name, total)
    notify(('Saved "%s" - %d wall(s) live for everyone'):format(name, total), 'success')
end)

RegisterNetEvent('nrp-barriers:removed', function(name)
    notify(('Deleted "%s"'):format(name), 'success')
end)

RegisterNetEvent('nrp-barriers:saveFailed', function()
    notify('Wall is live but SAVING FAILED - check server console', 'error')
end)

RegisterNetEvent('nrp-barriers:denied', function()
    notify('No permission. Add: add_ace group.admin nrp.barrier allow', 'error')
end)

-- ============================================================================
--  LAYER 2 - SWEEP GUARD
-- ============================================================================

-- Sample points for the controlled entity, in its local space. A ped is one
-- point; a vehicle is its outline, so the bumper hits the wall, not the middle.
local vehShapeCache = {}

local function vehicleShape(veh)
    local model = GetEntityModel(veh)
    local shape = vehShapeCache[model]
    if shape then return shape end

    local mn, mx = GetModelDimensions(model)
    local pts    = {}
    local m      = Config.VehicleMargin

    local x0, x1 = mn.x - m, mx.x + m
    local y0, y1 = mn.y - m, mx.y + m

    -- along both sides every ~1.5m, plus front and rear edges
    local n = math.max(2, math.ceil((y1 - y0) / 1.5) + 1)
    for i = 0, n - 1 do
        local y = y0 + (y1 - y0) * (i / (n - 1))
        pts[#pts + 1] = { x0, y }
        pts[#pts + 1] = { x1, y }
    end
    pts[#pts + 1] = { 0.0, y0 }
    pts[#pts + 1] = { 0.0, y1 }
    pts[#pts + 1] = { 0.0, 0.0 }

    shape = { pts = pts, zLo = mn.z, zHi = mx.z }
    vehShapeCache[model] = shape
    return shape
end

local PED_SHAPE = { pts = { { 0.0, 0.0 } }, zLo = -1.0, zHi = 0.9 }

-- One sample point against one segment.
--   x0,y0  where the point was last frame (already legal)
--   x1,y1  where it is now
-- Returns the x,y push needed, or nil.
local function resolve(seg, wall, x0, y0, x1, y1, r, bodyLo, bodyHi)
    local rx, ry = x1 - seg.ax, y1 - seg.ay
    local d1     = rx * seg.nx + ry * seg.ny                 -- signed distance now
    local t1     = (rx * seg.ux + ry * seg.uy) / seg.len     -- 0..1 along segment

    local qx, qy = x0 - seg.ax, y0 - seg.ay
    local d0     = qx * seg.nx + qy * seg.ny                 -- signed distance before
    local t0     = (qx * seg.ux + qy * seg.uy) / seg.len

    -- did the move pass through the wall line itself this frame?
    local crossed, tHit = false, t1
    if (d0 > 0.0) ~= (d1 > 0.0) and d0 ~= d1 then
        local f = d0 / (d0 - d1)
        tHit    = t0 + (t1 - t0) * f
        local eps = 0.02 / seg.len      -- no gaps at joints from float error
        crossed = tHit >= -eps and tHit <= 1.0 + eps
    end

    local tz = crossed and tHit or t1
    if tz < 0.0 then tz = 0.0 elseif tz > 1.0 then tz = 1.0 end

    -- height of the wall at this spot, following the slope
    local zg = seg.az + (seg.bz - seg.az) * tz
    if bodyHi < zg - Config.FloorOffset or bodyLo > zg + wall.height then
        return nil
    end

    if crossed then
        -- went through: back to the side it came from, kept r off the line,
        -- same position along the wall so you slide instead of stick
        local s    = d0 > 0.0 and 1.0 or -1.0
        local push = r - s * d1
        return seg.nx * s * push, seg.ny * s * push
    end

    if t1 >= 0.0 and t1 <= 1.0 then
        local ad = abs(d1)
        if ad >= r then return nil end
        local s = d1 > 0.0 and 1.0 or (d1 < 0.0 and -1.0 or (d0 >= 0.0 and 1.0 or -1.0))
        local push = r - ad
        return seg.nx * s * push, seg.ny * s * push
    end

    -- beyond an end: round end cap
    local ex, ey = (t1 < 0.0) and seg.ax or seg.bx, (t1 < 0.0) and seg.ay or seg.by
    local vx, vy = x1 - ex, y1 - ey
    local dist   = sqrt(vx * vx + vy * vy)
    if dist >= r then return nil end
    if dist < 0.0001 then
        local s = (t1 < 0.0) and -1.0 or 1.0
        return seg.ux * s * r, seg.uy * s * r
    end
    local push = (r - dist) / dist
    return vx * push, vy * push
end

-- Does the move x0,y0 -> x1,y1 pass through the wall line itself?
local function crosses(seg, wall, x0, y0, x1, y1, bodyLo, bodyHi)
    local d0 = (x0 - seg.ax) * seg.nx + (y0 - seg.ay) * seg.ny
    local d1 = (x1 - seg.ax) * seg.nx + (y1 - seg.ay) * seg.ny
    if (d0 > 0.0) == (d1 > 0.0) or d0 == d1 then return false end

    local f  = d0 / (d0 - d1)
    local hx = x0 + (x1 - x0) * f
    local hy = y0 + (y1 - y0) * f
    local t  = ((hx - seg.ax) * seg.ux + (hy - seg.ay) * seg.uy) / seg.len
    local eps = 0.02 / seg.len
    if t < -eps or t > 1.0 + eps then return false end

    if t < 0.0 then t = 0.0 elseif t > 1.0 then t = 1.0 end
    local zg = seg.az + (seg.bz - seg.az) * t
    return bodyHi >= zg - Config.FloorOffset and bodyLo <= zg + wall.height
end

local prevEntity = 0
local prevPts    = nil

CreateThread(function()
    while true do
        local sleep = 250

        if blocking and not building and #walls > 0 then
            local ped    = PlayerPedId()
            local entity = ped
            local inVeh  = false

            if IsPedInAnyVehicle(ped, false) then
                local v = GetVehiclePedIsIn(ped, false)
                if v ~= 0 and GetPedInVehicleSeat(v, -1) == ped and Config.BlockVehicles then
                    entity, inVeh = v, true
                else
                    -- passenger: the driver's client handles the vehicle
                    entity = 0
                end
            end

            local near = {}
            if entity ~= 0 then
                local pos = GetEntityCoords(entity)
                for _, w in ipairs(walls) do
                    if distToWall(w, pos.x, pos.y) < Config.ActiveRange then
                        near[#near + 1] = w
                    end
                end
            end

            if #near > 0 then
                sleep = 0

                local pos     = GetEntityCoords(entity)
                local hdg     = math.rad(GetEntityHeading(entity))
                local fx, fy  = -math.sin(hdg), math.cos(hdg)
                local rx, ry  = math.cos(hdg), math.sin(hdg)
                local shape   = inVeh and vehicleShape(entity) or PED_SHAPE
                local r       = inVeh and 0.05 or Config.Thickness

                -- world positions of every sample point this frame
                local cur = {}
                for i, p in ipairs(shape.pts) do
                    cur[i] = {
                        pos.x + rx * p[1] + fx * p[2],
                        pos.y + ry * p[1] + fy * p[2],
                    }
                end

                -- teleports, respawns, switching entity: start fresh, no check
                local valid = prevPts and prevEntity == entity and #prevPts == #cur
                if valid then
                    for i = 1, #cur do
                        local dx, dy = cur[i][1] - prevPts[i][1], cur[i][2] - prevPts[i][2]
                        if dx * dx + dy * dy > Config.MaxStep * Config.MaxStep then
                            valid = false
                            break
                        end
                    end
                end

                local offX, offY = 0.0, 0.0

                if valid then
                    local bodyLo, bodyHi = pos.z + shape.zLo, pos.z + shape.zHi

                    -- two passes so inside corners settle in a single frame
                    for _ = 1, 2 do
                        local moved = false
                        for i = 1, #cur do
                            local x1, y1 = cur[i][1] + offX, cur[i][2] + offY
                            local x0, y0 = prevPts[i][1], prevPts[i][2]
                            for _, w in ipairs(near) do
                                for _, seg in ipairs(w.segs) do
                                    local cx, cy = resolve(seg, w, x0, y0, x1, y1, r, bodyLo, bodyHi)
                                    if cx then
                                        offX, offY = offX + cx, offY + cy
                                        x1, y1     = x1 + cx, y1 + cy
                                        moved      = true
                                    end
                                end
                            end
                        end
                        if not moved then break end
                    end

                    -- Final check. At a sharp corner one push can land you
                    -- through the next segment. If the end result still went
                    -- through any wall, hold you where you were last frame.
                    if offX ~= 0.0 or offY ~= 0.0 then
                        local through = false
                        for i = 1, #cur do
                            local x1, y1 = cur[i][1] + offX, cur[i][2] + offY
                            local x0, y0 = prevPts[i][1], prevPts[i][2]
                            for _, w in ipairs(near) do
                                for _, seg in ipairs(w.segs) do
                                    if crosses(seg, w, x0, y0, x1, y1, bodyLo, bodyHi) then
                                        through = true
                                        break
                                    end
                                end
                                if through then break end
                            end
                            if through then break end
                        end
                        if through then
                            offX = prevPts[1][1] - cur[1][1]
                            offY = prevPts[1][2] - cur[1][2]
                        end
                    end
                end

                if offX ~= 0.0 or offY ~= 0.0 then
                    local vel = GetEntityVelocity(entity)

                    SetEntityCoordsNoOffset(entity, pos.x + offX, pos.y + offY, pos.z, false, false, false)

                    -- take away only the part of the velocity going into the wall,
                    -- so you keep sliding along it instead of stopping dead
                    local ol     = sqrt(offX * offX + offY * offY)
                    local nx, ny = offX / ol, offY / ol
                    local vi     = vel.x * nx + vel.y * ny
                    if vi < 0.0 then
                        SetEntityVelocity(entity, vel.x - vi * nx, vel.y - vi * ny, vel.z)
                    else
                        SetEntityVelocity(entity, vel.x, vel.y, vel.z)
                    end

                    if not inVeh then
                        -- no sprinting on the spot against the wall
                        DisableControlAction(0, 21, true)
                    end
                end

                for i = 1, #cur do
                    cur[i][1], cur[i][2] = cur[i][1] + offX, cur[i][2] + offY
                end
                prevPts, prevEntity = cur, entity
            else
                prevPts = nil
            end
        else
            prevPts = nil
        end

        Wait(sleep)
    end
end)

-- ============================================================================
--  DRAWING
-- ============================================================================

local function drawWallOutline(points, height, r, g, b)
    for i = 1, #points do
        local p = points[i]
        DrawLine(p.x, p.y, p.z, p.x, p.y, p.z + height, r, g, b, 220)

        if i < #points then
            local n = points[i + 1]
            DrawLine(p.x, p.y, p.z, n.x, n.y, n.z, r, g, b, 220)
            DrawLine(p.x, p.y, p.z + height, n.x, n.y, n.z + height, r, g, b, 220)
            DrawLine(p.x, p.y, p.z + height * 0.33, n.x, n.y, n.z + height * 0.33, r, g, b, 130)
            DrawLine(p.x, p.y, p.z + height * 0.66, n.x, n.y, n.z + height * 0.66, r, g, b, 130)
        end
    end
end

local function drawText(x, y, text, scale, centre)
    SetTextFont(4)
    SetTextScale(scale or 0.33, scale or 0.33)
    SetTextColour(255, 255, 255, 235)
    SetTextOutline()
    if centre then SetTextCentre(true) end
    SetTextEntry('STRING')
    AddTextComponentString(text)
    DrawText(x, y)
end

CreateThread(function()
    while true do
        local sleep = 700

        if (showWalls or highlight) and not building then
            local pos = GetEntityCoords(PlayerPedId())
            for i, w in ipairs(walls) do
                local isHl = (i == highlight)
                if (showWalls or isHl) and distToWall(w, pos.x, pos.y) < (isHl and 400.0 or 120.0) then
                    sleep = 0
                    if isHl then
                        drawWallOutline(w.points, w.height, 255, 200, 40)
                    else
                        drawWallOutline(w.points, w.height, 255, 70, 70)
                    end
                end
            end
        end

        Wait(sleep)
    end
end)

-- ============================================================================
--  TELEPORT
-- ============================================================================

local function teleportToWall(i)
    local w = walls[i]
    if not w or #w.points == 0 then
        notify('No such wall.', 'error')
        return
    end

    -- middle of the wall, stepped 2.5m off it so you never land inside it
    local x, y, z
    local seg = w.segs[math.max(1, math.ceil(#w.segs / 2))]
    if seg then
        local mx = (seg.ax + seg.bx) * 0.5
        local my = (seg.ay + seg.by) * 0.5
        x, y, z = mx + seg.nx * 2.5, my + seg.ny * 2.5, (seg.az + seg.bz) * 0.5
    else
        local p = w.points[1]
        x, y, z = p.x + 2.5, p.y, p.z
    end

    local ped    = PlayerPedId()
    local entity = ped
    if IsPedInAnyVehicle(ped, false) and GetPedInVehicleSeat(GetVehiclePedIsIn(ped, false), -1) == ped then
        entity = GetVehiclePedIsIn(ped, false)
    end

    DoScreenFadeOut(250)
    while not IsScreenFadedOut() do Wait(0) end

    prevPts = nil       -- a teleport is not a wall crossing
    RequestCollisionAtCoord(x, y, z)
    SetEntityCoords(entity, x, y, z + 1.0, false, false, false, false)
    FreezeEntityPosition(entity, true)

    -- wait for the ground to stream in, then put the player on it
    local timeout = GetGameTimer() + 3000
    while not HasCollisionLoadedAroundEntity(entity) and GetGameTimer() < timeout do
        RequestCollisionAtCoord(x, y, z)
        Wait(0)
    end

    local found, gz = GetGroundZFor_3dCoord(x, y, z + 5.0, false)
    if found then z = gz end

    SetEntityCoords(entity, x, y, z + 0.05, false, false, false, false)
    SetEntityHeading(entity, math.deg(math.atan(-(seg and seg.nx or 1.0), seg and seg.ny or 0.0)) + 180.0)
    FreezeEntityPosition(entity, false)
    prevPts = nil

    DoScreenFadeIn(250)
    highlight = i
    notify(('Teleported to "%s"'):format(w.name), 'success')
end

-- ============================================================================
--  UI
-- ============================================================================

local function openUi()
    if uiOpen then return end
    uiOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open' })
    pushUi()
end

local function closeUi()
    if not uiOpen then return end
    uiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

-- server decides whether you may open it
RegisterNetEvent('nrp-barriers:uiAllowed', function()
    openUi()
end)

-- keep distances fresh while it is open
CreateThread(function()
    while true do
        if uiOpen then pushUi() Wait(1000) else Wait(500) end
    end
end)

RegisterNUICallback('close', function(_, cb)
    closeUi()
    cb('ok')
end)

RegisterNUICallback('teleport', function(data, cb)
    cb('ok')
    local i = tonumber(data.index)
    closeUi()
    CreateThread(function() teleportToWall(i) end)
end)

RegisterNUICallback('highlight', function(data, cb)
    local i = tonumber(data.index)
    highlight = (highlight == i) and nil or i
    pushUi()
    cb('ok')
end)

RegisterNUICallback('rename', function(data, cb)
    local i = tonumber(data.index)
    if i and walls[i] and type(data.name) == 'string' and data.name ~= '' then
        TriggerServerEvent('nrp-barriers:rename', i, data.name)
    end
    cb('ok')
end)

RegisterNUICallback('delete', function(data, cb)
    local i = tonumber(data.index)
    if i and walls[i] then
        TriggerServerEvent('nrp-barriers:remove', i)
    end
    cb('ok')
end)

RegisterNUICallback('build', function(_, cb)
    cb('ok')
    closeUi()
    ExecuteCommand('barrier build')
end)

RegisterNUICallback('toggleOutlines', function(_, cb)
    showWalls = not showWalls
    pushUi()
    cb('ok')
end)

RegisterNUICallback('toggleBlocking', function(_, cb)
    blocking = not blocking
    pushUi()
    cb('ok')
end)

-- ============================================================================
--  BUILD MODE
-- ============================================================================

local function aimPoint()
    local cam    = GetGameplayCamCoord()
    local rot    = GetGameplayCamRot(2)
    local rx, rz = math.rad(rot.x), math.rad(rot.z)
    local cosRx  = abs(math.cos(rx))
    local dir    = vector3(-math.sin(rz) * cosRx, math.cos(rz) * cosRx, math.sin(rx))
    local dest   = cam + (dir * Config.RayDistance)

    -- world only, so the invisible panels of other walls do not catch the aim
    local ray = StartShapeTestRay(cam.x, cam.y, cam.z, dest.x, dest.y, dest.z, 1, PlayerPedId(), 4)
    local _, hit, endCoords = GetShapeTestResult(ray)

    if hit == 1 then return endCoords end
    return dest
end

local function startBuilding()
    if building then
        notify('Already building.')
        return
    end

    building = true

    local points = {}
    local height = Config.DefaultHeight

    CreateThread(function()
        notify('Build mode ON - LEFT CLICK to drop points', 'success')

        while building do
            for _, c in ipairs({ 24, 25, 47, 58, 140, 141, 142, 257, 263, 264, 10, 11, 176, 177 }) do
                DisableControlAction(0, c, true)
            end

            local aim = aimPoint()

            if IsDisabledControlPressed(0, 10) then height = math.min(height + 0.05, 30.0) end
            if IsDisabledControlPressed(0, 11) then height = math.max(height - 0.05, 0.5) end

            if IsDisabledControlJustPressed(0, 24) then
                points[#points + 1] = aim
                notify(('Point %d dropped'):format(#points))
            end

            if IsDisabledControlJustPressed(0, 25) then
                if #points > 0 then
                    table.remove(points)
                    notify(('Point removed (%d left)'):format(#points))
                end
            end

            if IsDisabledControlJustPressed(0, 176) then
                if #points < 2 then
                    notify('Need at least 2 points.', 'error')
                else
                    local payload = { name = ('wall %d'):format(#walls + 1), height = height, points = {} }
                    for _, p in ipairs(points) do
                        payload.points[#payload.points + 1] = {
                            x = p.x + 0.0, y = p.y + 0.0, z = p.z + 0.0,
                        }
                    end

                    -- add locally so it blocks instantly, then persist.
                    -- the server broadcast will replace this with the saved copy.
                    walls[#walls + 1] = buildWall(payload.name, height, payload.points)

                    TriggerServerEvent('nrp-barriers:add', payload)

                    notify(('Wall live - %d points, %.1fm tall. Saving...')
                        :format(#points, height), 'success')
                    building = false
                end
            end

            if IsDisabledControlJustPressed(0, 177) then
                notify('Build cancelled.')
                building = false
            end

            local preview = {}
            for i = 1, #points do preview[i] = points[i] end
            preview[#preview + 1] = aim

            drawWallOutline(preview, height, 80, 220, 255)

            DrawMarker(28, aim.x, aim.y, aim.z, 0, 0, 0, 0, 0, 0,
                0.15, 0.15, 0.15, 80, 220, 255, 200, false, false, 2, false, nil, nil, false)

            for _, p in ipairs(points) do
                DrawMarker(28, p.x, p.y, p.z, 0, 0, 0, 0, 0, 0,
                    0.12, 0.12, 0.12, 255, 190, 60, 220, false, false, 2, false, nil, nil, false)
            end

            DrawRect(0.5, 0.93, 0.66, 0.115, 0, 0, 0, 195)
            drawText(0.5, 0.885, ('~b~BUILD MODE~s~    points: ~y~%d~s~    height: ~y~%.1fm~s~')
                :format(#points, height), 0.35, true)
            drawText(0.5, 0.913, '~g~LEFT CLICK~s~ drop point    ~r~RIGHT CLICK~s~ undo point', 0.31, true)
            drawText(0.5, 0.939, '~b~PgUp / PgDn~s~ height    ~g~ENTER~s~ finish    ~r~BACKSPACE~s~ cancel', 0.31, true)
            drawText(0.5, 0.965, ('~c~aim: %.2f, %.2f, %.2f'):format(aim.x, aim.y, aim.z), 0.30, true)

            Wait(0)
        end
    end)
end

-- ============================================================================
--  COMMANDS
-- ============================================================================

RegisterCommand('barrier', function(_, args)
    CreateThread(function()
        local sub = (args[1] or ''):lower()

        if sub == 'build' then startBuilding() return end

        if sub == '' or sub == 'ui' or sub == 'menu' then
            TriggerServerEvent('nrp-barriers:openUi')
            return
        end

        if sub == 'tp' then
            local i = tonumber(args[2])
            if not i or not walls[i] then
                notify('Usage: /barrier tp 3   (see /barrier list)', 'error')
                return
            end
            -- same permission as the UI
            TriggerServerEvent('nrp-barriers:tp', i)
            return
        end

        if sub == 'show' then
            showWalls = not showWalls
            notify('Wall outlines ' .. (showWalls and 'ON' or 'OFF'))
            return
        end

        if sub == 'panels' then
            showPanels = not showPanels
            setPanelsVisible(showPanels)
            notify('Collision panels ' .. (showPanels and 'VISIBLE' or 'hidden'))
            return
        end

        if sub == 'off' then
            blocking = not blocking
            notify('Blocking ' .. (blocking and 'ON' or 'OFF'))
            return
        end

        -- delete the most recent wall, on disk, for everyone
        if sub == 'undo' then
            if #walls == 0 then
                notify('No walls to remove.', 'error')
                return
            end
            TriggerServerEvent('nrp-barriers:remove', #walls)
            return
        end

        -- delete a specific wall by its number from /barrier list
        if sub == 'delete' then
            local i = tonumber(args[2])
            if not i or not walls[i] then
                notify('Usage: /barrier delete 3   (see /barrier list)', 'error')
                return
            end
            TriggerServerEvent('nrp-barriers:remove', i)
            return
        end

        -- rename a wall
        if sub == 'name' then
            local i = tonumber(args[2])
            if not i or not walls[i] then
                notify('Usage: /barrier name 3 back stairs', 'error')
                return
            end
            local parts = {}
            for k = 3, #args do parts[#parts + 1] = args[k] end
            if #parts == 0 then
                notify('Give it a name: /barrier name 3 back stairs', 'error')
                return
            end
            TriggerServerEvent('nrp-barriers:rename', i, table.concat(parts, ' '))
            notify('Renamed.', 'success')
            return
        end

        -- delete every wall
        if sub == 'wipe' then
            if args[2] ~= 'confirm' then
                notify(('This deletes ALL %d wall(s) permanently. Type: /barrier wipe confirm')
                    :format(#walls), 'error')
                return
            end
            TriggerServerEvent('nrp-barriers:wipe')
            notify('All walls wiped.', 'success')
            return
        end

        if sub == 'list' then
            print('=====================================================')
            print(('  WALLS (%d)  - saved in walls.json'):format(#walls))
            print('=====================================================')
            for i, w in ipairs(walls) do
                local lo, hi = wallBounds(w)
                print(('  [%d] %s'):format(i, w.name))
                print(('      %d points   %.1fm tall   z %.2f -> %.2f   panels %d')
                    :format(#w.points, w.height, lo, hi, panels[w] and #panels[w] or 0))
            end
            print('=====================================================')
            print('  /barrier tp <n>       teleport to one')
            print('  /barrier delete <n>   removes one')
            print('=====================================================')
            notify(('%d wall(s) - see F8'):format(#walls))
            return
        end

        -- resync from server
        if sub == 'reload' then
            TriggerServerEvent('nrp-barriers:request')
            notify('Resyncing from server...')
            return
        end

        notify('/barrier (opens UI) | build | list | tp <n> | delete <n> | name <n> <text> | undo | show | panels | off | reload | wipe')
    end)
end, false)

RegisterNetEvent('nrp-barriers:tpAllowed', function(i)
    teleportToWall(tonumber(i))
end)
