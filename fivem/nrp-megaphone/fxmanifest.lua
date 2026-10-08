fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nrp-megaphone'
author 'foxscripts (based on fd-megaphones by pen / FD-Scripts, GPL-3.0)'
description 'Handheld, vehicle PA and stage-mic megaphones for The Neighborhood RP'
version '2.5.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_script 'client/main.lua'
server_script 'server/main.lua'

ui_page 'html/index.html'
files {
    'html/index.html',
    'html/talk_start.ogg',
    'html/talk_stop.ogg',
}

dependencies {
    'ox_lib',
    'pma-voice',
}
