fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'Prest_Sector-Cuffs'
author 'Preston D'
description 'Prest_Sector Cuffs: realistic handcuffing with the cuffs on the wrists, checked by the server'
version '1.1.0'
repository 'https://github.com/fordforlife2004-coder/FIVE-M-SCRIPT-S-PORTFOLIO'
portfolio_folder 'Prest_Sector-Cuffs' -- this script's folder in the repository, for the update check

-- Player state and the server's view of where players are both need OneSync.
dependency '/onesync'

shared_scripts {
    'config.lua',
    'shared/cuffs.lua',
}

server_script 'server/main.lua'

client_scripts {
    'client/props.lua',
    'client/main.lua',
    'client/adjust.lua',
}

-- Says in the server console when a newer version is on GitHub. Turn it off with: set prest_check_updates false
server_script 'server/version.lua'
