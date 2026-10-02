fx_version 'cerulean'
game 'gta5'

author 'foxscripts'
description 'Clipboard Rentals — a man with a clipboard who rents you cars. Now with signed contracts & temporary registration.'
version '2.0.0'

shared_script 'config.lua'
client_script 'client.lua'
server_script 'server.lua'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/fonts.css',
    'html/fonts/*.woff2'
}

lua54 'yes'
