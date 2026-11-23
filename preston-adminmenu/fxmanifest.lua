fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'preston-adminmenu'
author 'Preston D'
description 'Preston Admin Menu v2: NUI admin panel with server-side permissions, saved bans, reports and Discord logs'
version '2.1.0'
repository 'https://github.com/fordforlife2004-coder/FIVE-M-SCRIPT-S-PORTFOLIO'
portfolio_folder 'preston-adminmenu' -- this script's folder in the repository, for the update check

ui_page 'html/index.html'

shared_scripts {
    'config.lua',
    'shared/vehicle_types.lua',
}

server_scripts {
    'server/util.lua',
    'server/storage.lua',
    'server/logs.lua',
    'server/bans.lua',
    'server/reports.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
    'client/modes.lua',
    'client/spectate.lua',
}

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}

-- Says in the server console when a newer version is on GitHub. Turn it off with: set prest_check_updates false
server_script 'server/version.lua'
