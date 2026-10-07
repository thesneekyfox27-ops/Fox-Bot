fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'WeatherSync'
description 'Realistic Time & Weather Sync with NUI control panel (QBCore / Standalone)'
version '2.2.0'

shared_script 'config.lua'
client_script 'client.lua'
server_script 'server.lua'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/sounds/restart_siren.ogg',
    'html/sounds/tornado_warning.mp3',
    'html/sounds/storm_rumble.mp3',
    'html/sounds/purge_start.mp3',
    'html/sounds/purge_end.mp3',
    -- any sound you drop into html/sounds/ (e.g. your purge siren) is served automatically
    'html/sounds/*.mp3',
    'html/sounds/*.ogg',
    'html/sounds/*.wav',
    'flood.xml',
}

-- Registers flood.xml so LoadWaterFromPath can load it for the flood.
-- WeatherSync calls ResetWater() on start, so normal water is untouched until a flood.
data_file 'WATER_FILE' 'flood.xml'
