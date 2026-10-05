fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nrp-bowling'
author 'The Neighborhood RP'
description 'Bowling for the Breze bowling MLO - lanes, real scoring, multiplayer, aim/spin/power'
version '2.8.4'

ui_page 'html/index.html'
files {
    'html/index.html',
    'html/sounds/release.mp3',
    'html/sounds/pins.mp3',
    'html/sounds/spare.mp3',
    'html/sounds/strike.mp3',
    'html/sounds/gutter.mp3',
    'html/sounds/ambient1.mp3',
    'html/sounds/ambient2.mp3',
    'html/sounds/*.mp3',   -- any extra files you add
}

shared_scripts {
    'config.lua',
    'shared/scoring.lua',
}
client_script 'client.lua'
server_script 'server.lua'

dependencies {
    'qb-core',
    'bowling',   -- the map (MLO) resource
}
