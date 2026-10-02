--[[ nrp-movingjob | client/main.lua
     Contract board -> van -> load at the depot -> drive -> stack it on the
     customer's step -> back to the yard for the cheque.
]]

local QBCore = exports['qb-core']:GetCoreObject()

-- client/dolly.lua defines the Dolly global. If that file is missing from the
-- server, truncated by a half-finished upload, or dropped from fxmanifest.lua,
-- every interaction that asks about the hand truck would throw. Fall back to a
-- stub that reports "no truck", so the job still runs on plain hand-carry.
if not Dolly then
    -- Only a problem if the truck was meant to be running.
    if Config.Dolly and Config.Dolly.enabled then
        print('^1[nrp-movingjob] client/dolly.lua did not load but Config.Dolly.enabled '
            .. 'is true - hand truck unavailable. Check the file is on the server '
            .. 'and uncommented in fxmanifest.lua.^7')
    end
    Dolly = {
        loaded   = false,
        isActive = function() return false end,
        isFull   = function() return true end,
        count    = function() return 0 end,
        peek     = function() return nil end,
        grab     = function() return false end,
        park     = function() end,
        load     = function() return false end,
        unload   = function() return nil end
    }
end

-- Same guard for the config block, which lives in shared/config.lua.
if not Config.Dolly then
    Config.Dolly = { enabled = false, capacity = 0, slots = {} }
end

local Job = {
    active     = false,
    leader     = false,
    contract   = nil,   -- { id, customer, drop, items = {cargoIdx...}, payPerItem, bonus }
    stage      = 'idle',-- idle | loading | transit | unloading | returning
    van        = nil,
    plate      = nil,
    stowed     = {},    -- { {entity, cargoIdx} } - back of the van, in load order
    delivered  = 0,
    damaged    = 0,
    palletProp = nil,
    blip       = nil,
    uniform    = nil
}

local bossPed, bossBlip

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------
local function notify(msg, kind)
    lib.notify({ title = Config.CompanyName, description = msg, type = kind or 'inform' })
end

local function miles(metres)
    return metres * 0.000621371
end

local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(10) end
    return HasModelLoaded(hash) and hash or nil
end

--- How many pieces are staged on the hand truck right now.
local function onDolly()
    return (Dolly and Dolly.isActive()) and Dolly.count() or 0
end

--- Index of the next piece still waiting on the pallet.
local function nextPalletIndex()
    return #Job.stowed + Job.delivered + onDolly() + 1
end

local function remaining()
    if not Job.contract then return 0 end
    return #Job.contract.items - Job.delivered - #Job.stowed - onDolly()
end

-- ---------------------------------------------------------------------------
-- uniform
-- ---------------------------------------------------------------------------
local UNIFORM_KVP = 'nrp_movingjob_clothes'

--- Which character this snapshot belongs to. Without this the saved clothing
--- is per-client, so switching characters - or reconnecting as someone else -
--- would replay one character's outfit onto another.
local function citizenId()
    local data = QBCore.Functions.GetPlayerData()
    return data and data.citizenid or nil
end

--- Stash the player's own clothing to disk as well as memory, so a crash or a
--- restart mid-contract can still put them back.
local function wearUniform()
    if not Config.Uniform.enabled then return end
    local ped = PlayerPedId()
    local set = IsPedMale(ped) and Config.Uniform.male or Config.Uniform.female

    Job.uniform = {}
    for component in pairs(set.components) do
        Job.uniform[component] = {
            drawable = GetPedDrawableVariation(ped, component),
            texture  = GetPedTextureVariation(ped, component)
        }
    end

    Job.uniformProps = {}
    if set.props then
        for prop in pairs(set.props) do
            Job.uniformProps[prop] = {
                drawable = GetPedPropIndex(ped, prop),
                texture  = GetPedPropTextureIndex(ped, prop)
            }
        end
    end

    SetResourceKvp(UNIFORM_KVP, json.encode({
        citizenid = citizenId(),
        saved     = Job.uniform,
        props     = Job.uniformProps
    }))

    for component, v in pairs(set.components) do
        SetPedComponentVariation(ped, component, v.drawable, v.texture, 0)
    end
    if set.props then
        for prop, v in pairs(set.props) do
            if v.drawable == -1 then
                ClearPedProp(ped, prop)
            else
                SetPedPropIndex(ped, prop, v.drawable, v.texture or 0, true)
            end
        end
    end
end

--- Is the ped still wearing any part of the work uniform?
local function stillWearingUniform()
    local ped = PlayerPedId()
    local set = IsPedMale(ped) and Config.Uniform.male or Config.Uniform.female
    for component, piece in pairs(set.components) do
        if GetPedDrawableVariation(ped, component) == piece.drawable then
            return true
        end
    end
    return false
end

--- Replay the stored component snapshot. Only touches a slot if the player is
--- still wearing our uniform piece there, so a trip to a clothing store
--- mid-contract does not get stomped.
local function applySnapshot(saved)
    local ped = PlayerPedId()
    local set = IsPedMale(ped) and Config.Uniform.male or Config.Uniform.female
    local changed = 0

    for component, v in pairs(saved) do
        local uniformPiece = set.components[component]
        local current = GetPedDrawableVariation(ped, component)
        if not uniformPiece or current == uniformPiece.drawable then
            SetPedComponentVariation(ped, component, v.drawable, v.texture, 0)
            changed = changed + 1
        end
    end

    if Job.uniformProps then
        for prop, v in pairs(Job.uniformProps) do
            if v.drawable == -1 then
                ClearPedProp(ped, prop)
            else
                SetPedPropIndex(ped, prop, v.drawable, v.texture or 0, true)
            end
        end
        Job.uniformProps = nil
    end

    return changed
end

--- Put the player back in their own clothes.
--- Tries the character system first (it holds the real appearance), and only
--- falls back to replaying the five saved slots if that hook is not wired up.
--- `immediate` skips the verify step. Used on resource stop, where a Wait
--- would never resume and the snapshot fallback would never be reached.
local function restoreClothes(saved, immediate)
    local handled = false

    if immediate then
        if saved then applySnapshot(saved) end
        Job.uniform = nil
        DeleteResourceKvp(UNIFORM_KVP)
        return false
    end

    if type(Config.Uniform.reapply) == 'function' then
        pcall(Config.Uniform.reapply)
        -- Do not trust the return value. Some clothing resources fire an
        -- event that succeeds without doing anything, so check the ped: if
        -- the vest is gone, it worked.
        Wait(400)
        handled = not stillWearingUniform()
    end

    if not handled and saved then
        applySnapshot(saved)
    end

    Job.uniform = nil
    DeleteResourceKvp(UNIFORM_KVP)
    return handled
end

--- Called when the job ends. Honours Config.Uniform.restoreMode.
local function removeUniform(saved)
    if not Config.Uniform.enabled or not Config.Uniform.restore then return end

    saved = saved or Job.uniform
    local mode = Config.Uniform.restoreMode or 'auto'

    if mode == 'off' then
        Job.uniform = nil
        lib.notify({
            title = Config.CompanyName,
            description = 'Still in the vest. /myclothes when you want to change back.',
            type = 'inform'
        })
        return
    end

    if mode == 'prompt' then
        CreateThread(function()
            local answer = lib.alertDialog({
                header = 'Change out of the vest?',
                content = 'Put your own clothes back on, or keep the hi-vis for now. '
                    .. 'You can change later with /myclothes.',
                centered = true,
                cancel = true,
                labels = { confirm = 'Change back', cancel = 'Keep it on' }
            })
            if answer == 'confirm' then
                restoreClothes(saved)
            else
                Job.uniform = nil
            end
        end)
        return
    end

    restoreClothes(saved)
end

--- On load, put back a uniform left on by a crash or a restart - but only for
--- the character it was saved against, and only once that character has
--- actually finished loading, so this cannot race the character system.
local function recoverUniform()
    local stored = GetResourceKvpString(UNIFORM_KVP)
    if not stored then return end

    local ok, payload = pcall(json.decode, stored)
    if not ok or type(payload) ~= 'table' then
        DeleteResourceKvp(UNIFORM_KVP)
        return
    end

    -- Old single-table format from before this was keyed per character.
    local saved = payload.saved or payload
    local owner = payload.citizenid

    CreateThread(function()
        -- Give the character system time to apply the real appearance first.
        local deadline = GetGameTimer() + 30000
        while GetGameTimer() < deadline do
            if citizenId() then break end
            Wait(500)
        end
        Wait(3000)

        local me = citizenId()
        if owner and me and owner ~= me then
            -- Saved against a different character. Not ours to undo.
            DeleteResourceKvp(UNIFORM_KVP)
            return
        end

        -- If nothing on the ped still looks like the uniform, the character
        -- system already dressed them correctly and there is nothing to fix.
        local ped = PlayerPedId()
        local set = IsPedMale(ped) and Config.Uniform.male or Config.Uniform.female
        local wearingIt = false
        for component, piece in pairs(set.components) do
            if GetPedDrawableVariation(ped, component) == piece.drawable then
                wearingIt = true
                break
            end
        end

        if not wearingIt then
            DeleteResourceKvp(UNIFORM_KVP)
            return
        end

        -- Always ask here, whatever restoreMode says. This snapshot could be
        -- hours old and the character may have changed clothes since, so
        -- silently replaying it is the one case that loses an outfit.
        local answer = lib.alertDialog({
            header = 'Still in work clothes',
            content = ('You were wearing %s work clothes when your last session '
                .. 'ended. Change back into your own?'):format(Config.CompanyName),
            centered = true,
            cancel = true,
            labels = { confirm = 'Change back', cancel = 'Keep the vest' }
        })

        if answer == 'confirm' then
            restoreClothes(saved)
        else
            -- Keep the snapshot so /myclothes still works this session.
            Job.uniform = saved
            lib.notify({
                title = Config.CompanyName,
                description = 'Keeping the vest. /myclothes to change back.',
                type = 'inform'
            })
        end
    end)
end

--- /myclothes - change out of the vest whenever you like.
RegisterCommand('myclothes', function()
    local saved = Job.uniform
    if not saved then
        local stored = GetResourceKvpString(UNIFORM_KVP)
        if stored then
            local ok, payload = pcall(json.decode, stored)
            if ok and type(payload) == 'table' then
                saved = payload.saved or payload
            end
        end
    end

    local handled = restoreClothes(saved)
    lib.notify({
        title = Config.CompanyName,
        description = handled and 'Back in your own clothes.'
            or (saved and 'Back in your own clothes.'
                       or 'Nothing saved to change back into.'),
        type = (handled or saved) and 'success' or 'error'
    })
end, false)


-- ---------------------------------------------------------------------------
-- uniform editor
-- ---------------------------------------------------------------------------
--- Every slot you can put a uniform piece on. `comp` slots are clothing,
--- `prop` slots are worn accessories.
local UNIFORM_SLOTS = {
    { kind = 'comp', id = 1,  name = 'Mask' },
    { kind = 'comp', id = 3,  name = 'Arms / gloves' },
    { kind = 'comp', id = 4,  name = 'Legs / pants' },
    { kind = 'comp', id = 5,  name = 'Backpack' },
    { kind = 'comp', id = 6,  name = 'Shoes' },
    { kind = 'comp', id = 7,  name = 'Accessory' },
    { kind = 'comp', id = 8,  name = 'Undershirt' },
    { kind = 'comp', id = 9,  name = 'Body armour' },
    { kind = 'comp', id = 10, name = 'Decal / badge' },
    { kind = 'comp', id = 11, name = 'Top / jacket' },
    { kind = 'prop', id = 0,  name = 'Hat' },
    { kind = 'prop', id = 1,  name = 'Glasses' },
    { kind = 'prop', id = 2,  name = 'Earpiece' }
}

local function slotMaxDrawable(ped, slot)
    if slot.kind == 'comp' then
        return GetNumberOfPedDrawableVariations(ped, slot.id) - 1
    end
    return GetNumberOfPedPropDrawableVariations(ped, slot.id) - 1
end

local function slotMaxTexture(ped, slot, drawable)
    if drawable < 0 then return 0 end
    if slot.kind == 'comp' then
        return math.max(0, GetNumberOfPedTextureVariations(ped, slot.id, drawable) - 1)
    end
    return math.max(0, GetNumberOfPedPropTextureVariations(ped, slot.id, drawable) - 1)
end

local function slotApply(ped, slot, drawable, texture)
    if slot.kind == 'comp' then
        SetPedComponentVariation(ped, slot.id, drawable, texture, 0)
    elseif drawable < 0 then
        ClearPedProp(ped, slot.id)
    else
        SetPedPropIndex(ped, slot.id, drawable, texture, true)
    end
end

local function slotRead(ped, slot)
    if slot.kind == 'comp' then
        return GetPedDrawableVariation(ped, slot.id), GetPedTextureVariation(ped, slot.id)
    end
    return GetPedPropIndex(ped, slot.id), GetPedPropTextureIndex(ped, slot.id)
end

--- /uniformtune
---
--- Dress the uniform on your own ped and print the config block. Edits
--- whichever gender you currently are - male and female drawable numbers are
--- completely different garments, so each needs its own pass.
RegisterCommand('uniformtune', function()
    local ped = PlayerPedId()
    local female = not IsPedMale(ped)
    local key = female and 'female' or 'male'

    -- Remember what they walked in wearing, for cancel and for the parts of
    -- the outfit we never touch.
    local original = {}
    for i, slot in ipairs(UNIFORM_SLOTS) do
        local d, t = slotRead(ped, slot)
        original[i] = { drawable = d, texture = t }
    end

    -- Start from whatever is already configured for this gender.
    local set = Config.Uniform[key] or {}
    local work = {}
    for i, slot in ipairs(UNIFORM_SLOTS) do
        local cfg = slot.kind == 'comp'
            and (set.components and set.components[slot.id])
            or  (set.props and set.props[slot.id])
        if cfg then
            work[i] = { drawable = cfg.drawable, texture = cfg.texture or 0, use = true }
        else
            work[i] = { drawable = original[i].drawable, texture = original[i].texture, use = false }
        end
    end

    local function paint()
        for i, slot in ipairs(UNIFORM_SLOTS) do
            local w = work[i]
            if w.use then
                slotApply(ped, slot, w.drawable, w.texture)
            else
                slotApply(ped, slot, original[i].drawable, original[i].texture)
            end
        end
    end
    paint()

    local cur = 1
    local function draw()
        local slot = UNIFORM_SLOTS[cur]
        local w = work[cur]
        local maxD = slotMaxDrawable(ped, slot)
        local maxT = slotMaxTexture(ped, slot, w.drawable)
        lib.showTextUI(
            ('**Uniform editor — %s**  \n'):format(key:upper()) ..
            ('Slot: **%s**  (%s %d)  \n'):format(slot.name, slot.kind, slot.id) ..
            ('Drawable: **%d** / %d   Texture: **%d** / %d  \n'):format(
                w.drawable, maxD, w.texture, maxT) ..
            ('In uniform: **%s**  \n'):format(w.use and 'yes' or 'no') ..
            '---  \n' ..
            'PgUp/PgDn slot · ←→ drawable · ↑↓ texture  \n' ..
            'Shift = ±10 · SPACE include/exclude slot  \n' ..
            'ENTER print config · BACKSPACE cancel',
            { position = 'right-center' }
        )
    end
    draw()

    CreateThread(function()
        while true do
            local slot = UNIFORM_SLOTS[cur]
            local w = work[cur]
            local maxD = slotMaxDrawable(ped, slot)
            local step = IsControlPressed(0, 21) and 10 or 1
            local dirty = false

            if IsControlJustPressed(0, 10) then         -- page up
                cur = cur - 1; if cur < 1 then cur = #UNIFORM_SLOTS end
                dirty = true
            elseif IsControlJustPressed(0, 11) then     -- page down
                cur = cur + 1; if cur > #UNIFORM_SLOTS then cur = 1 end
                dirty = true
            elseif IsControlJustPressed(0, 174) then    -- left
                w.drawable = w.drawable - step
                local floor = slot.kind == 'prop' and -1 or 0
                if w.drawable < floor then w.drawable = maxD end
                w.texture = 0
                w.use = true
                dirty = true
            elseif IsControlJustPressed(0, 175) then    -- right
                w.drawable = w.drawable + step
                if w.drawable > maxD then w.drawable = slot.kind == 'prop' and -1 or 0 end
                w.texture = 0
                w.use = true
                dirty = true
            elseif IsControlJustPressed(0, 172) then    -- up
                local maxT = slotMaxTexture(ped, slot, w.drawable)
                w.texture = w.texture + 1
                if w.texture > maxT then w.texture = 0 end
                w.use = true
                dirty = true
            elseif IsControlJustPressed(0, 173) then    -- down
                local maxT = slotMaxTexture(ped, slot, w.drawable)
                w.texture = w.texture - 1
                if w.texture < 0 then w.texture = maxT end
                w.use = true
                dirty = true
            elseif IsControlJustPressed(0, 22) then     -- space
                w.use = not w.use
                dirty = true
            end

            if dirty then
                paint()
                draw()
            end

            if IsControlJustReleased(0, 191) then       -- enter
                local comps, props = {}, {}
                for i, sl in ipairs(UNIFORM_SLOTS) do
                    if work[i].use then
                        local line = ('            [%d] = { drawable = %d, texture = %d },')
                            :format(sl.id, work[i].drawable, work[i].texture)
                        if sl.kind == 'comp' then comps[#comps + 1] = line
                        else props[#props + 1] = line end
                    end
                end

                local function strip(t)
                    if #t > 0 then t[#t] = t[#t]:gsub(',$', '') end
                    return table.concat(t, '\n')
                end

                local block = ('    %s = {\n        components = {\n%s\n        }'):format(
                    key, strip(comps))
                if #props > 0 then
                    block = block .. (',\n        props = {\n%s\n        }'):format(strip(props))
                end
                block = block .. '\n    },'

                print('[nrp-movingjob] paste this over the ' .. key
                    .. ' block in Config.Uniform:')
                print(block)
                lib.setClipboard(block)
                lib.notify({
                    title = 'Uniform editor',
                    description = ('%s block printed to F8 and copied.'):format(key),
                    type = 'success'
                })
                break
            end

            if IsControlJustReleased(0, 194) then       -- backspace
                for i, sl in ipairs(UNIFORM_SLOTS) do
                    slotApply(ped, sl, original[i].drawable, original[i].texture)
                end
                lib.notify({
                    title = 'Uniform editor',
                    description = 'Cancelled, back in your own clothes.',
                    type = 'inform'
                })
                break
            end

            Wait(0)
        end

        lib.hideTextUI()
    end)
end, false)

-- ---------------------------------------------------------------------------
-- waypoints
-- ---------------------------------------------------------------------------
local function setWaypoint(coords, label, sprite, colour)
    if Job.blip and DoesBlipExist(Job.blip) then RemoveBlip(Job.blip) end
    Job.blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(Job.blip, sprite or 1)
    SetBlipColour(Job.blip, colour or 3)
    SetBlipScale(Job.blip, 0.85)
    SetBlipRoute(Job.blip, true)
    SetBlipRouteColour(Job.blip, colour or 3)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandSetBlipName(Job.blip)
end

local function clearWaypoint()
    if Job.blip and DoesBlipExist(Job.blip) then RemoveBlip(Job.blip) end
    Job.blip = nil
end

-- ---------------------------------------------------------------------------
-- van
-- ---------------------------------------------------------------------------
local function freeBay()
    for _, bay in ipairs(Config.Van.bays) do
        local clear = true
        local objs = GetGamePool('CVehicle')
        for _, veh in ipairs(objs) do
            if #(GetEntityCoords(veh) - vector3(bay.x, bay.y, bay.z)) < Config.Van.bayClearRadius then
                clear = false
                break
            end
        end
        if clear then return bay end
    end
    return nil
end

local function spawnVan(plate)
    local bay = freeBay()
    if not bay then
        notify('Every bay is blocked. Move something.', 'error')
        return nil
    end

    local hash = loadModel(Config.Van.model)
    if not hash then return nil end

    local veh = CreateVehicle(hash, bay.x, bay.y, bay.z, bay.w, true, false)
    SetModelAsNoLongerNeeded(hash)
    SetVehicleNumberPlateText(veh, plate)
    SetVehicleDirtLevel(veh, 3.0)
    SetVehicleDoorsLocked(veh, 1)
    if Config.Van.livery then SetVehicleLivery(veh, Config.Van.livery) end
    SetEntityAsMissionEntity(veh, true, true)

    Config.SetFuel(veh, 100.0)

    -- Client grant for the immediate case, server grant so it survives a
    -- resource restart or a key store that lives server side.
    Config.GiveKeys(veh, plate)
    TriggerServerEvent('nrp-movingjob:server:grantKeys', plate, VehToNet(veh))

    return veh
end

local function despawnVan()
    if Job.van and DoesEntityExist(Job.van) then
        for _, s in ipairs(Job.stowed) do
            if DoesEntityExist(s.entity) then DeleteEntity(s.entity) end
        end
        DeleteEntity(Job.van)
    end
    Job.van = nil
    Job.stowed = {}
end

local function vanRearCoords()
    if not Job.van or not DoesEntityExist(Job.van) then return nil end
    local o = Config.Van.rearOffset
    return GetOffsetFromEntityInWorldCoords(Job.van, o.x, o.y, o.z)
end

-- ---------------------------------------------------------------------------
-- depot pallet
-- ---------------------------------------------------------------------------
local function refreshPallet()
    if Job.palletProp and DoesEntityExist(Job.palletProp) then
        DeleteEntity(Job.palletProp)
        Job.palletProp = nil
    end
    if Job.stage ~= 'loading' then return end

    local nextIdx = Job.contract.items[nextPalletIndex()]
    if not nextIdx then return end

    local p = Config.Depot.pallet
    Job.palletProp = Carry.spawnProp(nextIdx, vector3(p.x, p.y, p.z + 0.5))
    if Job.palletProp then
        PlaceObjectOnGroundProperly(Job.palletProp)
        FreezeEntityPosition(Job.palletProp, true)
    end
end

-- ---------------------------------------------------------------------------
-- clipboard paperwork (NUI)
-- Set Config.Paperwork.enabled = false to go back to the ox_lib menus below.
-- ---------------------------------------------------------------------------
local paperOpen = false
local nuiReady  = false     -- the html page reported in
local nuiAck    = 0         -- bumped every time the page confirms it opened
local openMenus             -- the ox_lib menus, used as a fallback

RegisterNUICallback('nuiReady', function(_, cb)
    nuiReady = true
    cb({ ok = true })
end)

RegisterNUICallback('opened', function(_, cb)
    nuiAck = nuiAck + 1
    cb('ok')
end)

local function charName()
    local data = QBCore.Functions.GetPlayerData()
    local ci = data and data.charinfo
    if ci then
        local n = (('%s %s'):format(ci.firstname or '', ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
        if n ~= '' then return n end
    end
    return GetPlayerName(PlayerId())
end

--- A stable made-up phone number for the client line of the contract.
local function phoneFor(id, customer)
    local h = 0
    for i = 1, #customer do h = (h * 31 + customer:byte(i)) % 10000 end
    return ('(555) %03d-%04d'):format(100 + (id * 37) % 900, h)
end

local function jobPayload()
    local c = Job.contract
    local items = {}
    for i, idx in ipairs(c.items) do
        local cargo = Config.Cargo[idx] or {}
        items[i] = { label = cargo.label or 'Item', weight = cargo.weight, fragile = cargo.weight == 'fragile' }
    end
    local drop = Config.Drops[c.drop]
    return {
        customer = c.customer, address = drop and drop.label or '', plate = Job.plate,
        stage = Job.stage, items = items, delivered = Job.delivered,
        payPerItem = c.payPerItem, bonus = c.bonus, price = c.price,
        crewSize = Job.crewSize or 1
    }
end

local function closePaper()
    if not paperOpen then return end
    paperOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function openPaper()
    local p = Config.Paperwork or {}
    local msg = {
        action  = 'open',
        company = {
            name    = Config.CompanyName,
            address = p.address or 'Haulaway Yard',
            phone   = p.phone or '',
            yard    = p.yardLabel or 'the yard'
        },
        penalty = Config.Contracts.damagePenalty or 0,
        signer  = { name = charName(), required = p.mustMatchName ~= false },
        rates   = {
            perItem   = Config.Pay.perItem,
            perMile   = Config.Pay.perMile,
            crewBonus = Config.Pay.crewBonus,
            splitPay  = Config.Crew.splitPay and true or false
        }
    }

    if Job.active then
        msg.mode     = 'active'
        msg.job      = jobPayload()
        msg.isLeader = Job.leader and true or false
        msg.canHire  = (Config.Crew.enabled and Job.leader) and true or false
        msg.splitPay = Config.Crew.splitPay
    else
        local contracts = lib.callback.await('nrp-movingjob:server:getContracts', false)
        if not contracts then return true end   -- server already told them why

        local here, list = GetEntityCoords(cache.ped), {}
        for _, c in ipairs(contracts) do
            local drop = Config.Drops[c.drop]
            list[#list + 1] = {
                id = c.id, customer = c.customer, address = drop.label,
                itemCount = c.itemCount, payPerItem = c.payPerItem, bonus = c.bonus,
                price = c.price, miles = c.price and c.price.miles or miles(#(drop.arrival - here)),
                phone = phoneFor(c.id, c.customer)
            }
        end
        msg.mode = 'board'
        msg.contracts = list
        msg.crew = {
            enabled  = Config.Crew.enabled and true or false,
            max      = math.max(0, (Config.Crew.maxMembers or 1) - 1),
            splitPay = Config.Crew.splitPay and true or false
        }
    end

    paperOpen = true
    local ack = nuiAck
    SendNUIMessage(msg)

    CreateThread(function()
        -- let the target eye finish closing first, or it takes the cursor back
        Wait(150)
        if paperOpen then SetNuiFocus(true, true) end

        -- the page confirms it drew; if it never does, fall back to the menus
        local deadline = GetGameTimer() + 1500
        while nuiAck == ack and GetGameTimer() < deadline do Wait(50) end
        if nuiAck == ack and paperOpen then
            print(('^1[nrp-movingjob] clipboard UI did not open (page loaded: %s). Check html/ is on the '
                .. 'server, fxmanifest.lua has ui_page + files, then restart the resource. Using the menus.^7')
                :format(tostring(nuiReady)))
            closePaper()
            openMenus()
        end
    end)
    return true
end

-- /movingpaper opens the clipboard directly, handy to test the UI
RegisterCommand('movingpaper', function()
    CreateThread(function()
        print(('[nrp-movingjob] paperwork enabled=%s, page loaded=%s')
            :format(tostring(not Config.Paperwork or Config.Paperwork.enabled ~= false), tostring(nuiReady)))
        openPaper()
    end)
end, false)

RegisterNUICallback('close', function(_, cb)
    closePaper()
    cb('ok')
end)

RegisterNUICallback('accept', function(data, cb)
    closePaper()
    local crew = {}
    if type(data.crew) == 'table' then
        for _, id in ipairs(data.crew) do
            if tonumber(id) then crew[#crew + 1] = tonumber(id) end
        end
    end
    TriggerServerEvent('nrp-movingjob:server:accept', tonumber(data.id), tostring(data.signature or ''), crew)
    cb('ok')
end)

RegisterNUICallback('finish', function(_, cb)
    closePaper()
    TriggerEvent('nrp-movingjob:client:finish')
    cb('ok')
end)

RegisterNUICallback('abandon', function(_, cb)
    closePaper()
    TriggerServerEvent('nrp-movingjob:server:abandon')
    cb('ok')
end)

RegisterNUICallback('nearby', function(_, cb)
    local out = {}
    -- before a job (picking a crew on the contract) or as the crew boss during one
    if Config.Crew.enabled and (Job.leader or not Job.active) then
        for _, pl in ipairs(lib.getNearbyPlayers(GetEntityCoords(cache.ped), Config.Crew.inviteRange, false)) do
            out[#out + 1] = { id = GetPlayerServerId(pl.id), name = GetPlayerName(pl.id) }
        end
    end
    cb(out)
end)

RegisterNUICallback('invite', function(data, cb)
    if Config.Crew.enabled and Job.leader and tonumber(data.id) then
        TriggerServerEvent('nrp-movingjob:server:invite', tonumber(data.id))
        notify('Invite sent.', 'inform')
    end
    cb('ok')
end)

-- keep the work order live while it is open; close it if the job ends
CreateThread(function()
    while true do
        if paperOpen and Job.active and Job.contract then
            SendNUIMessage({ action = 'update', job = jobPayload() })
            Wait(500)
        else
            Wait(1000)
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and paperOpen then SetNuiFocus(false, false) end
end)

-- ---------------------------------------------------------------------------
-- contract board
-- ---------------------------------------------------------------------------
openMenus = function()
    if Job.active then
        local opts = {
            {
                title = 'Hand in the contract',
                description = Job.stage == 'returning'
                    and ('Collect payment for %s'):format(Job.contract.customer)
                    or 'The job is not finished yet',
                icon = 'dollar-sign',
                disabled = Job.stage ~= 'returning',
                onSelect = function() TriggerEvent('nrp-movingjob:client:finish') end
            },
            {
                title = 'Abandon the contract',
                description = 'No pay, and the van goes back in the yard',
                icon = 'ban',
                onSelect = function()
                    local ok = lib.alertDialog({
                        header = 'Walk away?',
                        content = 'You will not be paid for anything already delivered.',
                        centered = true, cancel = true
                    })
                    if ok == 'confirm' then TriggerServerEvent('nrp-movingjob:server:abandon') end
                end
            }
        }
        if Config.Crew.enabled and Job.leader then
            table.insert(opts, 2, {
                title = 'Hire a hand',
                description = 'Invite someone standing nearby onto the crew',
                icon = 'user-plus',
                onSelect = function() TriggerEvent('nrp-movingjob:client:invite') end
            })
        end
        lib.registerContext({ id = 'nrp_moving_active', title = Config.CompanyName, options = opts })
        return lib.showContext('nrp_moving_active')
    end

    local contracts = lib.callback.await('nrp-movingjob:server:getContracts', false)
    if not contracts then return end

    local opts = {}
    for _, c in ipairs(contracts) do
        local dist = #(vector3(Config.Drops[c.drop].arrival.x, Config.Drops[c.drop].arrival.y, Config.Drops[c.drop].arrival.z) - GetEntityCoords(cache.ped))
        opts[#opts + 1] = {
            title = Config.Drops[c.drop].label,
            description = ('%s | %d items | about %.1f mi | $%d base'):format(
                c.customer, c.itemCount, miles(dist), c.itemCount * c.payPerItem),
            icon = 'truck-moving',
            metadata = {
                { label = 'Customer', value = c.customer },
                { label = 'Items',    value = c.itemCount },
                { label = 'Per item', value = ('$%d'):format(c.payPerItem) },
                { label = 'Completion bonus', value = ('$%d'):format(c.bonus) }
            },
            onSelect = function()
                TriggerServerEvent('nrp-movingjob:server:accept', c.id)
            end
        }
    end

    if #opts == 0 then
        opts[1] = { title = 'Nothing on the board', description = 'Check back shortly', disabled = true }
    end

    lib.registerContext({
        id = 'nrp_moving_board',
        title = Config.CompanyName,
        options = opts
    })
    lib.showContext('nrp_moving_board')
end

local function openBoard()
    if Config.Paperwork and Config.Paperwork.enabled ~= false and openPaper() then return end
    openMenus()
end

-- ---------------------------------------------------------------------------
-- job lifecycle
-- ---------------------------------------------------------------------------
RegisterNetEvent('nrp-movingjob:client:crewSize', function(size)
    Job.crewSize = tonumber(size) or 1
end)

RegisterNetEvent('nrp-movingjob:client:started', function(contract, isLeader)
    Job.active    = true
    Job.leader    = isLeader
    Job.contract  = contract
    Job.stage     = 'loading'
    Job.stowed    = {}
    Job.delivered = 0
    Job.damaged   = 0
    Job.plate     = contract.plate
    Job.crewSize  = 1

    wearUniform()

    if isLeader then
        Job.van = spawnVan(contract.plate)
        if not Job.van then
            TriggerServerEvent('nrp-movingjob:server:abandon')
            return
        end
    end

    refreshPallet()
    setWaypoint(Config.Depot.pallet, 'Load the van', 478, 3)
    notify(('%s, %d items. Load up at the pallet.'):format(contract.customer, #contract.items), 'success')
end)

RegisterNetEvent('nrp-movingjob:client:syncVan', function(netId)
    if Job.van then return end
    local timeout = GetGameTimer() + 5000
    while not NetworkDoesEntityExistWithNetworkId(netId) and GetGameTimer() < timeout do Wait(50) end
    if NetworkDoesEntityExistWithNetworkId(netId) then
        Job.van = NetToVeh(netId)
        Config.GiveKeys(Job.van, Job.plate)
        TriggerServerEvent('nrp-movingjob:server:grantKeys', Job.plate, netId)
    end
end)

--- The server owns the counts. The client increments optimistically so
--- placing an item feels instant; this corrects it straight after.
RegisterNetEvent('nrp-movingjob:client:progress', function(p)
    if not Job.active or not p then return end
    Job.delivered = p.delivered or Job.delivered
    Job.damaged   = p.damaged or Job.damaged
end)

--- If the client thinks every piece is down but the server has not moved on,
--- a delivery was rejected somewhere. Ask the server to reconcile rather than
--- leaving the contract uncompletable with no explanation.
local function verifyCompletion()
    CreateThread(function()
        Wait(2500)
        if not Job.active then return end
        if Job.stage == 'returning' or Job.stage == 'done' then return end
        if Job.delivered < #Job.contract.items then return end

        local state = lib.callback.await('nrp-movingjob:server:syncJob', false)
        if not state then return end

        if state.stage ~= 'returning' and state.delivered < state.total then
            notify(('%d of %d actually counted. Pick the rest back up and set them '
                .. 'down closer to the marker.'):format(state.delivered, state.total), 'error')
        end
    end)
end

RegisterNetEvent('nrp-movingjob:client:stageChanged', function(stage, payload)
    Job.stage = stage

    if stage == 'transit' then
        local drop = Config.Drops[Job.contract.drop]
        setWaypoint(drop.arrival, Job.contract.customer, 478, 5)
        notify('Van is loaded. Take it to the address.', 'success')
        if Job.palletProp and DoesEntityExist(Job.palletProp) then
            DeleteEntity(Job.palletProp)
            Job.palletProp = nil
        end

    elseif stage == 'unloading' then
        notify('Unload at the door.', 'inform')

    elseif stage == 'returning' then
        clearWaypoint()
        setWaypoint(Config.Boss.coords, 'Return to the yard', 479, 3)
        Indicators.clear()
        PlaySoundFrontend(-1, 'BASE_JUMP_PASSED', 'HUD_AWARDS', true)
        notify(('Delivery complete for %s. Take the van back to the yard to get paid.')
            :format(Job.contract and Job.contract.customer or 'the customer'), 'success')
        lib.notify({
            title = Config.CompanyName,
            description = 'Marker set for the yard.',
            type = 'inform',
            duration = 6000
        })

    elseif stage == 'done' then
        Job.active = false
        Job.stage = 'idle'
        clearWaypoint()
        removeUniform()
        despawnVan()
        Indicators.clear()
        Carry.purge()
        Dolly.park()
        Job.contract = nil
        if payload and payload.pay then
            notify(('Paid $%d%s'):format(payload.pay,
                payload.damaged > 0 and (' (%d damaged)'):format(payload.damaged) or ''), 'success')
        end
    end
end)

RegisterNetEvent('nrp-movingjob:client:cancelled', function(reason)
    Carry.drop()
    Carry.purge()
    Dolly.park()
    Job.active = false
    Job.stage = 'idle'
    Job.contract = nil
    clearWaypoint()
    removeUniform()
    despawnVan()
    Indicators.clear()
    if Job.palletProp and DoesEntityExist(Job.palletProp) then DeleteEntity(Job.palletProp) end
    Job.palletProp = nil
    notify(reason or 'Contract cancelled.', 'error')
end)

-- ---------------------------------------------------------------------------
-- loading at the depot
-- ---------------------------------------------------------------------------
-- Forward declaration: the dolly helpers below need this, and it is defined
-- further down with the rest of the doorstep logic.
local doorstepSpot

local function grabFromPallet()
    if Job.stage ~= 'loading' then return end
    if Carry.isCarrying() then return notify('Your hands are full.', 'error') end
    if not Job.van or not DoesEntityExist(Job.van) then return notify('Where is the van?', 'error') end
    if #(GetEntityCoords(Job.van) - Config.Depot.pallet) > Config.Depot.vanRange then
        return notify('Back the van up to the pallet first.', 'error')
    end
    if #Job.stowed + onDolly() >= #Config.Van.slots then
        return notify('No room left for this load.', 'error')
    end

    local idx = Job.contract.items[nextPalletIndex()]
    if not idx then return end

    -- With the truck out, pieces stack onto it instead of into your arms.
    if Dolly.isActive() then
        if Dolly.isFull() then return notify('The hand truck is loaded.', 'error') end
        if Dolly.load(idx, Job.palletProp) then
            Job.palletProp = nil
            refreshPallet()
        end
        return
    end

    if Carry.lift(idx, Job.palletProp) then
        Job.palletProp = nil
    end
end

--- Move one piece off the hand truck into the van.
local function dollyIntoVan()
    if not Dolly.isActive() or Dolly.count() == 0 then return end
    if Job.stage ~= 'loading' then return notify('Not right now.', 'error') end
    if #Job.stowed >= #Config.Van.slots then return notify('The box is full.', 'error') end

    local cargoIdx = Dolly.unload()
    if not cargoIdx then return end

    local slot = #Job.stowed + 1
    local stack = Config.Cargo[cargoIdx].stack or {}
    local rot = stack.rot or vector3(0.0, 0.0, 0.0)
    local s = Config.Van.slots[slot]

    local obj = Carry.spawnProp(cargoIdx, GetEntityCoords(Job.van))
    if not obj then return end
    AttachEntityToEntity(obj, Job.van, 0,
        s.x, s.y, s.z + (stack.z or 0.0),
        rot.x, rot.y, rot.z,
        true, true, false, false, 1, true)

    Job.stowed[slot] = { entity = obj, cargoIdx = cargoIdx }
    TriggerServerEvent('nrp-movingjob:server:loaded')
    PlaySoundFrontend(-1, 'PICK_UP', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
    refreshPallet()
end

--- Move one piece out of the van onto the hand truck.
local function vanOntoDolly()
    if not Dolly.isActive() then return end
    if Dolly.isFull() then return notify('The hand truck is loaded.', 'error') end
    if #Job.stowed == 0 then return notify('The van is empty.', 'error') end

    local drop = Config.Drops[Job.contract.drop]
    if #(GetEntityCoords(Job.van) - drop.arrival) > Config.Contracts.vanDropRange then
        return notify('Park closer to the address.', 'error')
    end

    local top = Job.stowed[#Job.stowed]
    if Dolly.load(top.cargoIdx, top.entity) then
        table.remove(Job.stowed, #Job.stowed)
        if Job.stage == 'transit' then
            Job.stage = 'unloading'
            TriggerServerEvent('nrp-movingjob:server:arrived')
        end
    end
end

--- Take the top piece off the truck and set it on the doorstep.
local function dollyToDoor()
    if not Dolly.isActive() or Dolly.count() == 0 then return end

    local drop = Config.Drops[Job.contract.drop]
    if #(GetEntityCoords(PlayerPedId()) - drop.arrival) > 5.0 then
        return notify('Get closer to the door.', 'error')
    end

    local cargoIdx = Dolly.unload()
    if not cargoIdx then return end

    local coords, heading = doorstepSpot(Job.delivered + 1)
    local obj = Carry.spawnProp(cargoIdx, coords)
    if obj then
        SetEntityRotation(obj, 0.0, 0.0, heading or 0.0, 2, true)
        PlaceObjectOnGroundProperly(obj)
        FreezeEntityPosition(obj, true)
    end

    Job.delivered = Job.delivered + 1
    PlaySoundFrontend(-1, 'CHECKPOINT_PERFECT', 'HUD_MINI_GAME_SOUNDSET', true)
    TriggerServerEvent('nrp-movingjob:server:delivered', Job.delivered, false)

    if Job.delivered < #Job.contract.items then
        notify(('%d to go'):format(#Job.contract.items - Job.delivered), 'inform')
    else
        verifyCompletion()
    end
end

local function stowInVan()
    if not Carry.isCarrying() then return end
    if Job.stage ~= 'loading' then return notify('Not right now.', 'error') end
    local slot = #Job.stowed + 1
    local cargoIdx = Carry.cargoIdx          -- stow() clears this, so grab it first
    local entity = Carry.stow(Job.van, slot)
    if not entity then return end

    Job.stowed[slot] = { entity = entity, cargoIdx = cargoIdx }

    TriggerServerEvent('nrp-movingjob:server:loaded')
    PlaySoundFrontend(-1, 'PICK_UP', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
    refreshPallet()
end

-- ---------------------------------------------------------------------------
-- unloading at the door
-- ---------------------------------------------------------------------------
local function takeFromVan()
    if Carry.isCarrying() then return notify('Your hands are full.', 'error') end
    if Job.stage ~= 'transit' and Job.stage ~= 'unloading' then
        return notify('Not yet.', 'error')
    end
    if #Job.stowed == 0 then return notify('The van is empty.', 'error') end

    local drop = Config.Drops[Job.contract.drop]
    if #(GetEntityCoords(Job.van) - drop.arrival) > Config.Contracts.vanDropRange then
        return notify('Park closer to the address.', 'error')
    end

    local top = Job.stowed[#Job.stowed]
    if Carry.unstow(top.entity, top.cargoIdx) then
        table.remove(Job.stowed, #Job.stowed)
        if Job.stage == 'transit' then
            Job.stage = 'unloading'
            TriggerServerEvent('nrp-movingjob:server:arrived')
        end
    end
end

--- Work out the doorstep spot for delivery number n.
--- Where piece number n goes, laid out from the drop's own axes.
---
--- Two forms are supported. If the entry has a `heading`, the stack is built
--- around `arrival` facing that way - that is what /dropeditor writes, and it
--- is the one to use, because you can stand in the spot and capture it.
--- Otherwise it falls back to the old door -> arrival pair.
function doorstepSpot(n)
    local drop = Config.Drops[Job.contract.drop]
    local pattern = Config.DropPattern[((n - 1) % #Config.DropPattern) + 1]
    local base, dir

    if drop.heading then
        base = drop.arrival
        local rad = math.rad(drop.heading)
        dir = vector3(-math.sin(rad), math.cos(rad), 0.0)
    else
        base = drop.door
        local v = drop.arrival - drop.door
        local len = #(vector3(v.x, v.y, 0.0))
        dir = (len < 0.01) and vector3(1.0, 0.0, 0.0)
                           or vector3(v.x / len, v.y / len, 0.0)
    end

    local side = vector3(-dir.y, dir.x, 0.0)
    local pos = base + (dir * pattern.forward) + (side * pattern.side)
    local heading = GetHeadingFromVector_2d(-dir.x, -dir.y)
    return vector3(pos.x, pos.y, drop.arrival.z), heading
end

local function placeAtDoor()
    if not Carry.isCarrying() then return end
    local drop = Config.Drops[Job.contract.drop]
    if #(GetEntityCoords(cache.ped) - drop.arrival) > 5.0 then
        return notify('Get closer to the door.', 'error')
    end

    local broken = Carry.damageCheck()
    local coords, heading = doorstepSpot(Job.delivered + 1)

    if Carry.place(coords, heading) then
        Job.delivered = Job.delivered + 1
        if broken then Job.damaged = Job.damaged + 1 end
        PlaySoundFrontend(-1, 'CHECKPOINT_PERFECT', 'HUD_MINI_GAME_SOUNDSET', true)
        TriggerServerEvent('nrp-movingjob:server:delivered', Job.delivered, broken)

        local left = #Job.contract.items - Job.delivered
        if left > 0 then
            notify(('%d to go'):format(left), 'inform')
        else
            verifyCompletion()
        end
    end
end

AddEventHandler('nrp-movingjob:client:cargoDropped', function()
    notify('You dropped it.', 'error')
end)

-- ---------------------------------------------------------------------------
-- finish
-- ---------------------------------------------------------------------------
RegisterNetEvent('nrp-movingjob:client:finish', function()
    if Job.stage ~= 'returning' then return notify('Finish the job first.', 'error') end
    if not Job.van or not DoesEntityExist(Job.van) then
        return notify('Bring the van back to the yard.', 'error')
    end
    if #(GetEntityCoords(Job.van) - vector3(Config.Boss.coords.x, Config.Boss.coords.y, Config.Boss.coords.z)) > 35.0 then
        return notify('The van belongs in the yard.', 'error')
    end
    TriggerServerEvent('nrp-movingjob:server:finish', VehToNet(Job.van))
end)

-- ---------------------------------------------------------------------------
-- crew
-- ---------------------------------------------------------------------------
RegisterNetEvent('nrp-movingjob:client:invite', function()
    if not Config.Crew.enabled or not Job.leader then return end

    local players = lib.getNearbyPlayers(GetEntityCoords(cache.ped), Config.Crew.inviteRange, false)
    local opts = {}
    for _, p in ipairs(players) do
        local serverId = GetPlayerServerId(p.id)
        opts[#opts + 1] = {
            title = ('%s [%d]'):format(GetPlayerName(p.id), serverId),
            icon = 'user',
            onSelect = function()
                TriggerServerEvent('nrp-movingjob:server:invite', serverId)
                notify('Invite sent.', 'inform')
            end
        }
    end
    if #opts == 0 then
        opts[1] = { title = 'Nobody nearby', disabled = true }
    end

    lib.registerContext({ id = 'nrp_moving_crew', title = 'Hire a hand', menu = 'nrp_moving_active', options = opts })
    lib.showContext('nrp_moving_crew')
end)

RegisterNetEvent('nrp-movingjob:client:invited', function(fromName, fromSrc)
    local accept = lib.alertDialog({
        header = 'Moving crew',
        content = ('%s wants you on their moving crew.%s'):format(
            fromName, Config.Crew.splitPay and ' Pay is split across the crew.' or ''),
        centered = true, cancel = true
    })
    TriggerServerEvent('nrp-movingjob:server:inviteResponse', fromSrc, accept == 'confirm')
end)

-- ---------------------------------------------------------------------------
-- interaction: targets, or [E] fallback
-- ---------------------------------------------------------------------------
local function setupTargets()
    if not Config.UseTarget then return end
    local target = GetResourceState('nrp-target') == 'started' and 'nrp-target' or 'ox_target'

    exports[target]:addLocalEntity(bossPed, {
        {
            name = 'nrp_moving_boss',
            icon = 'fa-solid fa-truck-moving',
            label = 'Moving contracts',
            distance = 2.5,
            onSelect = openBoard
        }
    })

    exports[target]:addSphereZone({
        coords = Config.Depot.pallet,
        radius = 2.0,
        debug = false,
        options = {
            {
                name = 'nrp_moving_pallet',
                icon = 'fa-solid fa-box',
                label = 'Pick up',
                canInteract = function() return Job.stage == 'loading' and not Carry.isCarrying() end,
                onSelect = grabFromPallet
            }
        }
    })

    -- The van rear is deliberately NOT a target zone. See the interaction
    -- thread below.
end

-- ---------------------------------------------------------------------------
-- rear doors
-- ---------------------------------------------------------------------------
local rearOpen = false

local function setRearDoors(open)
    if not Config.RearDoors.enabled then return end
    if not Job.van or not DoesEntityExist(Job.van) then return end
    if rearOpen == open then return end

    for _, idx in ipairs(Config.RearDoors.indices) do
        if open then
            SetVehicleDoorOpen(Job.van, idx, false, false)
        else
            SetVehicleDoorShut(Job.van, idx, false)
        end
    end
    rearOpen = open
end

-- ---------------------------------------------------------------------------
-- interaction
-- ---------------------------------------------------------------------------
--- One loop drives the rear of the van, the pallet and the doorstep. All three
--- are plain [E] prompts - you are usually holding something with both hands,
--- and aiming a target reticle at a door panel while carrying a couch is not
--- fun.
CreateThread(function()
    while true do
        local wait = 500
        local ped = PlayerPedId()
        local pos = GetEntityCoords(ped)
        local prompt, action

        Indicators.state.pallet = nil
        Indicators.state.rear = nil
        Indicators.state.drop = nil
        Indicators.state.zone = nil
        Indicators.state.spots = nil

        if Job.active then
            local inVehicle = IsPedInAnyVehicle(ped, false)
            local rear = vanRearCoords()
            local nearRear = (not inVehicle) and rear and #(pos - rear) <= Config.Van.rearRange
            local carrying = Carry.isCarrying()

            -- Destination zone -------------------------------------------------
            -- Big marker at the address, so you can see where you are headed
            -- while driving and where the stack goes once you arrive.
            if (Job.stage == 'transit' or Job.stage == 'unloading')
                and Job.delivered < #Job.contract.items
            then
                local drop = Config.Drops[Job.contract.drop]
                Indicators.state.zone = drop.arrival
            end

            -- Rear of the van --------------------------------------------------
            -- Skipped while sitting in the van: the rear point is only a few
            -- metres behind the driver's seat, so the marker would follow you
            -- down the road.
            if not inVehicle and rear and #(pos - rear) < Config.RearDoors.closeRange then
                wait = 0
                local wantDoors = (Job.stage == 'loading' and #Job.stowed < #Config.Van.slots)
                    or ((Job.stage == 'transit' or Job.stage == 'unloading') and #Job.stowed > 0)
                setRearDoors(wantDoors and nearRear)

                if wantDoors then
                    Indicators.state.rear = rear
                end

                if nearRear then
                    if Dolly.isActive() then
                        if Job.stage == 'loading' and Dolly.count() > 0 then
                            prompt = ('[E] Load into the van (%d on the truck)'):format(Dolly.count())
                            action = dollyIntoVan
                        elseif (Job.stage == 'transit' or Job.stage == 'unloading')
                            and #Job.stowed > 0 and not Dolly.isFull() then
                            prompt = ('[E] Onto the truck (%d/%d)'):format(Dolly.count(), Config.Dolly.capacity)
                            action = vanOntoDolly
                        end
                    elseif carrying and Job.stage == 'loading' then
                        prompt = '[E] Load into the van'
                        action = stowInVan
                    elseif not carrying and #Job.stowed > 0
                        and (Job.stage == 'transit' or Job.stage == 'unloading') then
                        prompt = '[E] Take out of the van'
                        action = takeFromVan
                    end
                end
            else
                setRearDoors(false)
            end

            -- Depot pallet -----------------------------------------------------
            if Job.stage == 'loading' and not carrying
                and #Job.stowed + onDolly() < #Config.Van.slots
                and not (Dolly.isActive() and Dolly.isFull())
            then
                Indicators.state.pallet = Config.Depot.pallet
                if #(pos - Config.Depot.pallet) < 2.2 then
                    wait = 0
                    prompt = Dolly.isActive()
                        and ('[E] Stack on the truck (%d/%d)'):format(Dolly.count(), Config.Dolly.capacity)
                        or '[E] Pick up'
                    action = grabFromPallet
                end
            end

            -- Doorstep ---------------------------------------------------------
            -- Faint outline of every spot still to be filled, so the layout
            -- reads even with empty hands.
            if (Job.stage == 'unloading' or Job.stage == 'transit')
                and Job.delivered < #Job.contract.items
            then
                local drop = Config.Drops[Job.contract.drop]
                if #(pos - drop.arrival) < Config.Indicators.drawDistance then
                    local spots = {}
                    for n = Job.delivered + 1, #Job.contract.items do
                        spots[#spots + 1] = (doorstepSpot(n))
                    end
                    Indicators.state.spots = spots
                end
            end

            local hasLoad = carrying or (Dolly.isActive() and Dolly.count() > 0)
            if hasLoad and (Job.stage == 'unloading' or Job.stage == 'transit') then
                local drop = Config.Drops[Job.contract.drop]
                if #(pos - drop.arrival) < Config.Indicators.drawDistance then
                    local coords, heading = doorstepSpot(Job.delivered + 1)
                    local previewIdx = carrying and Carry.cargoIdx
                        or (Dolly.peek() and Dolly.peek().cargoIdx)
                    Indicators.state.drop = {
                        coords = coords,
                        heading = heading,
                        cargoIdx = previewIdx
                    }
                    if #(pos - drop.arrival) < 6.0 then
                        wait = 0
                        prompt = '[E] Set it down'
                        action = carrying and placeAtDoor or dollyToDoor
                    end
                end
            end
        else
            setRearDoors(false)
        end

        -- Hand truck, parked by the pallet at the yard.
        if not prompt and Config.Dolly.enabled and Job.active then
            local rack = Config.Depot.pallet
            if #(pos - rack) < 3.5 and not Carry.isCarrying() then
                wait = 0
                if Dolly.isActive() then
                    if Dolly.count() == 0 then
                        prompt = '[G] Put the hand truck back'
                    end
                else
                    prompt = '[G] Grab a hand truck'
                end
                if prompt and IsControlJustReleased(0, 47) then -- G
                    if Dolly.isActive() then Dolly.park() else Dolly.grab() end
                    lib.hideTextUI()
                    prompt = nil
                end
            end
        end

        -- Boss ped, when targeting is off.
        if not prompt and not Config.UseTarget then
            local boss = vector3(Config.Boss.coords.x, Config.Boss.coords.y, Config.Boss.coords.z)
            if #(pos - boss) < 2.5 then
                wait = 0
                prompt = '[E] Moving contracts'
                action = openBoard
            end
        end

        if prompt then
            lib.showTextUI(prompt, { position = 'left-center' })
            if IsControlJustReleased(0, 38) then
                lib.hideTextUI()
                action()
            end
        else
            lib.hideTextUI()
        end

        Wait(wait)
    end
end)



-- ---------------------------------------------------------------------------
-- drop point editor
-- ---------------------------------------------------------------------------
--- /dropeditor
---
--- Stand where the stack should end up - a driveway, a path, beside a garage -
--- face the house, and this shows you the whole delivery laid out before you
--- commit. Enter prints a ready-to-paste Config.Drops entry.
---
--- Interiors are the reason this exists: a `door` coordinate taken from a
--- building that cannot be entered puts the stack inside the shell where
--- nobody can reach it.
RegisterCommand('dropeditor', function()
    local ghosts = {}
    local count = math.min(#Config.DropPattern, Config.Contracts.maxItems)

    local function clearGhosts()
        for _, obj in ipairs(ghosts) do
            if DoesEntityExist(obj) then DeleteEntity(obj) end
        end
        ghosts = {}
    end

    --- Lay the pattern out from a position and heading, exactly the way
    --- doorstepSpot will at delivery time.
    local function spotsFor(base, heading)
        local rad = math.rad(heading)
        local dir = vector3(-math.sin(rad), math.cos(rad), 0.0)
        local side = vector3(-dir.y, dir.x, 0.0)
        local out = {}
        for i = 1, count do
            local pat = Config.DropPattern[i]
            out[i] = base + (dir * pat.forward) + (side * pat.side)
        end
        return out
    end

    local function preview(base, heading)
        clearGhosts()
        for i, spot in ipairs(spotsFor(base, heading)) do
            local cargoIdx = ((i - 1) % #Config.Cargo) + 1
            local obj = Carry.spawnProp(cargoIdx, spot)
            if obj then
                SetEntityCollision(obj, false, false)
                SetEntityAlpha(obj, Config.Indicators.ghostAlpha, false)
                SetEntityHeading(obj, (heading + 180.0) % 360.0)
                PlaceObjectOnGroundProperly(obj)
                FreezeEntityPosition(obj, true)
                ghosts[#ghosts + 1] = obj
            end
        end
    end

    local ped = PlayerPedId()
    local base = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    preview(base, heading)

    lib.showTextUI(
        '**Drop point editor**  \n' ..
        'Walk to where the stack should go and face the house.  \n' ..
        '---  \n' ..
        '**R** re-read your position  \n' ..
        '**Arrows** nudge · **Shift** coarse  \n' ..
        '**[ ]** rotate the layout  \n' ..
        '**ENTER** print entry · **BACKSPACE** cancel',
        { position = 'right-center' }
    )

    CreateThread(function()
        local lastRefresh = 0
        while true do
            local step = IsControlPressed(0, 21) and 0.25 or 0.05
            local rstep = IsControlPressed(0, 21) and 15.0 or 3.0
            local dirty = false

            if IsControlJustPressed(0, 45) then        -- R, snap to the player
                base = GetEntityCoords(PlayerPedId())
                heading = GetEntityHeading(PlayerPedId())
                dirty = true
            end

            local rad = math.rad(heading)
            local fwd = vector3(-math.sin(rad), math.cos(rad), 0.0)
            local sde = vector3(-fwd.y, fwd.x, 0.0)

            if IsControlPressed(0, 172) then base = base + (fwd * step) dirty = true end
            if IsControlPressed(0, 173) then base = base - (fwd * step) dirty = true end
            if IsControlPressed(0, 174) then base = base - (sde * step) dirty = true end
            if IsControlPressed(0, 175) then base = base + (sde * step) dirty = true end
            if IsControlPressed(0, 39)  then heading = (heading - rstep) % 360.0 dirty = true end
            if IsControlPressed(0, 40)  then heading = (heading + rstep) % 360.0 dirty = true end

            -- Redraw at most ~12x a second; respawning props every frame is
            -- heavy and makes nudging feel worse, not better.
            if dirty and GetGameTimer() - lastRefresh > 80 then
                preview(base, heading)
                lastRefresh = GetGameTimer()
            end

            -- Outline so the footprint reads even where a ghost failed.
            for _, spot in ipairs(spotsFor(base, heading)) do
                DrawMarker(1, spot.x, spot.y, spot.z - 0.95, 0,0,0, 0,0,0,
                    0.5, 0.5, 0.15, 60, 220, 120, 90, false, false, 2, false, nil, nil, false)
            end
            DrawMarker(1, base.x, base.y, base.z - 0.95, 0,0,0, 0,0,0,
                3.0, 3.0, 0.4, 60, 220, 120, 40, false, false, 2, false, nil, nil, false)

            if IsControlJustReleased(0, 191) then      -- enter
                lib.hideTextUI()
                local label = lib.inputDialog('Drop point', {
                    { type = 'input', label = 'Name', description = 'Shown on the contract board',
                      required = true, default = 'New address' }
                })
                local name = (label and label[1]) or 'New address'
                local entry = ("    { label = '%s', arrival = vector3(%.2f, %.2f, %.2f), heading = %.1f },")
                    :format(name:gsub("'", ""), base.x, base.y, base.z, heading)
                print('[nrp-movingjob] add to Config.Drops:')
                print(entry)
                lib.setClipboard(entry)
                lib.notify({
                    title = 'Drop point editor',
                    description = 'Entry printed to F8 and copied.',
                    type = 'success'
                })
                break
            end

            if IsControlJustReleased(0, 194) then break end
            Wait(0)
        end

        clearGhosts()
        lib.hideTextUI()
    end)
end, false)

--- Flag drop points that sit inside an interior. A stack placed in a shell
--- the player cannot walk into is unreachable, and the contract cannot be
--- finished. Runs once, a little after load, so interiors have populated.
CreateThread(function()
    Wait(8000)
    local bad = 0
    for i, drop in ipairs(Config.Drops) do
        local a = drop.arrival
        if GetInteriorAtCoords(a.x, a.y, a.z) ~= 0 then
            bad = bad + 1
            print(('^3[nrp-movingjob] drop %d "%s" is inside an interior. Items left '
                .. 'there may be unreachable - re-place it outdoors with /dropeditor.^7')
                :format(i, drop.label))
        end
    end
    if bad > 0 then
        print(('^3[nrp-movingjob] %d drop point(s) need re-placing.^7'):format(bad))
    end
end)

--- /droptest <n> - teleport to a configured drop and see its layout.
RegisterCommand('droptest', function(_, args)
    local idx = tonumber(args[1] or '1') or 1
    local drop = Config.Drops[idx]
    if not drop then
        return lib.notify({ title = 'Drop points',
            description = ('No drop %d. There are %d.'):format(idx, #Config.Drops),
            type = 'error' })
    end
    local a = drop.arrival
    SetEntityCoords(PlayerPedId(), a.x, a.y, a.z + 1.0, false, false, false, false)
    lib.notify({ title = 'Drop points',
        description = ('%s. Interior check: %s'):format(drop.label,
            GetInteriorAtCoords(a.x, a.y, a.z) ~= 0 and 'INSIDE an interior' or 'outdoors'),
        type = GetInteriorAtCoords(a.x, a.y, a.z) ~= 0 and 'error' or 'success' })
end, false)

local function spawnBoss()
    local hash = loadModel(Config.Boss.model)
    if not hash then return end

    bossPed = CreatePed(4, hash, Config.Boss.coords.x, Config.Boss.coords.y, Config.Boss.coords.z - 1.0,
        Config.Boss.coords.w, false, true)
    SetModelAsNoLongerNeeded(hash)
    FreezeEntityPosition(bossPed, true)
    SetEntityInvincible(bossPed, true)
    SetBlockingOfNonTemporaryEvents(bossPed, true)
    if Config.Boss.scenario then
        TaskStartScenarioInPlace(bossPed, Config.Boss.scenario, 0, true)
    end

    if Config.Blip.enabled then
        bossBlip = AddBlipForCoord(Config.Boss.coords.x, Config.Boss.coords.y, Config.Boss.coords.z)
        SetBlipSprite(bossBlip, Config.Blip.sprite)
        SetBlipColour(bossBlip, Config.Blip.colour)
        SetBlipScale(bossBlip, Config.Blip.scale)
        SetBlipAsShortRange(bossBlip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(Config.Blip.label)
        EndTextCommandSetBlipName(bossBlip)
    end

    setupTargets()
end

CreateThread(function()
    while not LocalPlayer.state.isLoggedIn do Wait(500) end
    -- Clean up a uniform left on by a crash or a restart before anything else.
    recoverUniform()
    spawnBoss()
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end

    -- Straight restore, not removeUniform(): the resource is unloading, so a
    -- 'prompt' dialog would never get answered and 'off' would strand them in
    -- the vest with no /myclothes to change out of.
    if Job.uniform and Config.Uniform.enabled and Config.Uniform.restore then
        restoreClothes(Job.uniform, true)
    end

    if bossPed and DoesEntityExist(bossPed) then DeleteEntity(bossPed) end
    if bossBlip and DoesBlipExist(bossBlip) then RemoveBlip(bossBlip) end
    clearWaypoint()
    lib.hideTextUI()
    if Job.palletProp and DoesEntityExist(Job.palletProp) then DeleteEntity(Job.palletProp) end
    despawnVan()
end)
