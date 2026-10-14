fx_version 'cerulean'
game 'gta5'

author 'SeaM Development'
description 'SeaM Admin - in-city and browser administration for SeaM Core'
version '1.0.0'

lua54 'yes'

ui_page 'web/dist/index.html'

shared_scripts {
    'config.lua',
    'shared/permissions.lua'
}

client_scripts {
    'client/main.lua',
    'client/powers.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/actions.lua',
    'server/reports.lua',
    'server/web.js'
}

files {
    'web/dist/index.html',
    'web/dist/assets/*'
}

dependencies {
    'SeaM_Core',
    'oxmysql',
    'SeaM_Inventory'
}

provide 'seam_admin'
