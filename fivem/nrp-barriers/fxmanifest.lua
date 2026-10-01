fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'NRP'
description 'Solid invisible walls - draw in game, auto saved to walls.json, managed from /barrier ui'
version '6.0.0'

shared_script 'config.lua'
client_script 'client.lua'
server_script 'server.lua'

ui_page 'html/index.html'

files {
    'walls.json',
    'html/index.html',
    'html/style.css',
    'html/script.js',
}
