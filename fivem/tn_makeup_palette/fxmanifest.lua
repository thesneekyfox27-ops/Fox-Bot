fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Daddy Brain - The Neighborhood RP'
description 'Makeup Palette - wipe off and put back on makeup, blush and lipstick with an item'
version '2.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'locales/en.lua'
}

client_scripts {
    'client/client.lua'
}

server_scripts {
    'server/server.lua'
}

dependencies {
    'qb-core',
    'ox_lib'
}
