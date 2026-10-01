Keyring = Keyring or {}

-- GTA plates are padded with spaces and are case insensitive, so always compare normalized plates.
function Keyring.NormalizePlate(plate)
    if type(plate) ~= 'string' then return nil end
    plate = plate:gsub('^%s+', ''):gsub('%s+$', ''):upper()
    if plate == '' then return nil end
    return plate
end

-- tgiann returns item metadata as .info or .metadata, as a table or a JSON string.
function Keyring.ItemInfo(item)
    if type(item) ~= 'table' then return nil end
    local info = item.info ~= nil and item.info or item.metadata
    if type(info) == 'table' then return info end
    if type(info) == 'string' and info ~= '' then
        local ok, decoded = pcall(json.decode, info)
        if ok and type(decoded) == 'table' then return decoded end
    end
    return nil
end
