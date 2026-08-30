fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'mi_fire'
author 'MI Development'
description 'Fire generation, suppression, and fireground operations'
version '0.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/enums.lua',
    'shared/util.lua',
    'shared/hydraulics.lua',
    'config/config.lua',
    'config/dispatch.lua',
    'config/zones.lua',
    'config/fire_classes.lua',
    'config/agents.lua',
    'config/gear.lua',
}

client_scripts {
    'bridge/framework/init.lua',
    'bridge/target/ox_target.lua',
    'bridge/appearance/illenium.lua',
    'client/main.lua',
}

server_scripts {
    'bridge/framework/init.lua',
    'bridge/dispatch/init.lua',
    'bridge/inventory/ox_inventory.lua',
    'server/core/state.lua',
    'server/core/permissions.lua',
    'server/main.lua',
}

-- Hard dependencies only. The framework, dispatch, inventory, and appearance
-- integrations all degrade gracefully through bridge/ when their resource is absent,
-- so listing them here would break servers that legitimately do not run them.
dependencies {
    'ox_lib',
    'ox_target',
}
