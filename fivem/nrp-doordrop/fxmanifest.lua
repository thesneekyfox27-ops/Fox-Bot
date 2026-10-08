fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'nrp-doordrop'
author 'Fox'
description 'DoorDrop: gig food delivery through a phone app, with offers, tips, ratings and photo proof'
version '3.0.0'

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
    'html/phone.html',
    'html/icon.svg',
    'html/style.css',
    'html/app.js',
    'html/sounds/*.mp3',
}

dependencies {
    'qb-core',
    'ox_lib',
    'ox_target',
    'oxmysql',
}
