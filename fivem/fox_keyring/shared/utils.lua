Keyring = Keyring or {}

-- GTA plates are padded with spaces and are case insensitive, so always compare normalized plates.
function Keyring.NormalizePlate(plate)
    if type(plate) ~= 'string' then return nil end
    plate = plate:gsub('^%s+', ''):gsub('%s+$', ''):upper()
    if plate == '' or #plate > 8 then return nil end
    return plate
end

function Keyring.SanitizeLabel(label)
    if type(label) ~= 'string' then return nil end
    -- Strip GTA (~r~), chat (^1) and HTML (<b>) formatting so labels can't inject styling.
    label = label:gsub('~%w*~', ''):gsub('%^%d', ''):gsub('<[^>]*>', ''):gsub('[<>%^~]', '')
    label = label:gsub('^%s+', ''):gsub('%s+$', '')
    if label == '' then return nil end
    return label:sub(1, 32)
end
