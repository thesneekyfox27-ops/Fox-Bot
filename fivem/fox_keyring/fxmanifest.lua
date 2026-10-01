fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'fox_keyring'
author 'Fox'
description 'Standalone vehicle keyring: keys, locking, sharing and engine protection'
version '1.0.0'

shared_scripts {
    'config.lua',
    'shared/utils.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    'server/main.lua',
}

files {
    'data/keys.json',
}
