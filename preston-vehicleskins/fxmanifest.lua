fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'preston-vehicleskins'
author 'Preston D'
description 'Preston Vehicle Skins v2: liveries, extras, colors, plates and performance tuning, checked by the server'
version '2.1.0'
repository 'https://github.com/fordforlife2004-coder/FIVE-M-SCRIPT-S-PORTFOLIO'
portfolio_folder 'preston-vehicleskins' -- this script's folder in the repository, for the update check

shared_scripts {
    'config.lua',
    'shared/vehicle_types.lua',
    'shared/skins.lua',
}

server_script 'server/main.lua'
client_script 'client/main.lua'

-- Says in the server console when a newer version is on GitHub. Turn it off with: set prest_check_updates false
server_script 'server/version.lua'
