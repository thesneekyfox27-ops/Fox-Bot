fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nrp-bowling'
author 'The Neighborhood RP'
description 'Bowling for the Breze bowling MLO - lanes, real scoring, multiplayer, aim/spin/power'
version '2.0.0'

ui_page 'html/index.html'
files { 'html/index.html' }

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
