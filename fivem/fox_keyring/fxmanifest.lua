fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'fox_keyring'
author 'Fox'
description 'Keyring item for tgiann-inventory that holds 0r-vehiclekeys keys'
version '3.1.0'

dependencies {
    'qb-core',
    'ox_lib',
    'tgiann-inventory',
}

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/utils.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}
