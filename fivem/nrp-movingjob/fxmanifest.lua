fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Fox'
description 'Haulaway Moving Co. - contract moving job for The Neighborhood RP'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua'
}

client_scripts {
    'client/carry.lua',
    -- Hand truck. Disabled for now. To turn it back on: uncomment this line,
    -- set Config.Dolly.enabled = true, restart the resource, and confirm you
    -- see "hand truck module loaded" in console.
    -- 'client/dolly.lua',
    'client/indicators.lua',
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

dependencies {
    'ox_lib',
    'qb-core'
}
