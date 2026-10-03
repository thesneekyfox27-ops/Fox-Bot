fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'muscle_sands_gym'
author 'The Neighborhood RP'
description 'Muscle Sands Gym (Vespucci Beach) - memberships, rep minigame, server-side stats'
version '2.0.0'

ui_page 'html/index.html'
files { 'html/index.html' }

shared_script 'config.lua'
client_script 'client.lua'
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua',
}

dependencies {
    'qb-core',
    'oxmysql',
}
