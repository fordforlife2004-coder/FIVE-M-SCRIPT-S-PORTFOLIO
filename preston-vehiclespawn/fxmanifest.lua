fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'preston-vehiclespawn'
author 'Preston D'
description 'Preston Vehicle Spawn v2: /car and /dv, spawned and checked by the server'
version '2.1.0'
repository 'https://github.com/fordforlife2004-coder/FIVE-M-SCRIPT-S-PORTFOLIO'
portfolio_folder 'preston-vehiclespawn' -- this script's folder in the repository, for the update check

shared_scripts {
    'config.lua',
    'shared/vehicle_types.lua',
    'shared/rules.lua',
}

server_script 'server/main.lua'
client_script 'client/main.lua'

-- Says in the server console when a newer version is on GitHub. Turn it off with: set prest_check_updates false
server_script 'server/version.lua'
