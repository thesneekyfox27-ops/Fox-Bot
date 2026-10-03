fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'The Neighborhood RP'
description 'NBHD Rooms - Configurable Multi-Building Room System'
version '3.1.0'

ui_page 'ui/index.html'

files {
    'ui/index.html',
}

shared_scripts {
    'config.lua',
}

client_scripts {
    'client.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua',
}

dependencies {
    'qb-core',
    'oxmysql',
}
