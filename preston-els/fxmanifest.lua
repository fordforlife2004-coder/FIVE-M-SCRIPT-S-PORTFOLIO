fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'preston-els'
author 'Preston D'
description 'Preston ELS v2: emergency lights, siren tones and air horn, checked by the server and synced to every player'
version '2.1.0'
repository 'https://github.com/fordforlife2004-coder/FIVE-M-SCRIPT-S-PORTFOLIO'
portfolio_folder 'preston-els' -- this script's folder in the repository, for the update check

ui_page 'html/index.html'

shared_scripts {
    'config.lua',
    'shared/els.lua',
}

server_script 'server/main.lua'

client_scripts {
    'client/sync.lua',
    'client/main.lua',
}

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}

-- Says in the server console when a newer version is on GitHub. Turn it off with: set prest_check_updates false
server_script 'server/version.lua'
