fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'preston-iowapolice'
author 'Preston D'
description 'Preston Iowa Police v2: spawn and style Iowa patrol vehicles with unit-number plates, checked by the server'
version '2.1.0'
repository 'https://github.com/fordforlife2004-coder/FIVE-M-SCRIPT-S-PORTFOLIO'
portfolio_folder 'preston-iowapolice' -- this script's folder in the repository, for the update check

shared_scripts {
    'config.lua',
    'shared/iowa.lua',
}

server_script 'server/main.lua'
client_script 'client/main.lua'

-- Says in the server console when a newer version is on GitHub. Turn it off with: set prest_check_updates false
server_script 'server/version.lua'
