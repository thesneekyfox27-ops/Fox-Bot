fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name        'nrp-elevators'
description 'The Neighborhood RP - Config-based Elevator System'
author      'NRP / Daddy Brain'
version     '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    'server/main.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/logo.png',
    'html/sounds/ding.wav',
    'html/sounds/elevator_moving.wav',
    'html/sounds/*.wav',
    'html/sounds/*.ogg',
    'html/sounds/*.mp3',
    'html/*.png',
    'html/*.jpg',
    'html/*.jpeg',
    'html/*.webp',
}
