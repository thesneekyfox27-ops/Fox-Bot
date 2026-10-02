fx_version 'cerulean'
game'gta5'
name 'mrw_minigolf'
description 'script for patoche golf mapping - QBCore / ESX / standalone'
author 'Morow'
lua54 'yes'

client_scripts{
    'client/*.lua'
}

server_script{
    'server/*.lua'
}

shared_scripts{
    'shared/*.lua',
    'shared/translation/*.lua'
}

files{
    'ui/ui.html',
    'ui/script/app.js',
    'ui/css/app.css',
    'ui/font/*.woff',
    'ui/font/*.woff2'
}

ui_page 'ui/ui.html'