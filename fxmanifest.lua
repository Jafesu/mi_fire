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
    'shared/validate.lua',
    'shared/fireclass.lua',
    'shared/suppression.lua',
    'shared/pass.lua',
    'shared/exposure.lua',
    'shared/smoke.lua',
    'shared/gearmatch.lua',
    'shared/integrity.lua',
    'shared/scorch.lua',
    'config/config.lua',
    'config/dispatch.lua',
    'config/zones.lua',
    'config/fire_classes.lua',
    'config/agents.lua',
    'config/gear.lua',
    'config/stations.lua',
    'config/sprinklers.lua',
    'config/scba.lua',
    'config/smoke.lua',
    'config/scorch.lua',
}

client_scripts {
    'bridge/framework/init.lua',
    'bridge/target/ox_target.lua',
    'bridge/appearance/illenium.lua',
    'bridge/medical/init.lua',
    'client/main.lua',
    'client/modules/notify.lua',
    'client/modules/hud.lua',
    'client/modules/fire/render.lua',
    'client/modules/fire/init.lua',
    'client/modules/turnout/init.lua',
    'client/modules/scba/pass.lua',
    'client/modules/exposure/init.lua',
    'client/modules/smoke/init.lua',
    'client/modules/scorch/init.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'bridge/framework/init.lua',
    'bridge/dispatch/init.lua',
    'bridge/inventory/ox_inventory.lua',
    'bridge/medical/init.lua',
    'server/core/db.lua',
    'server/core/state.lua',
    'server/core/permissions.lua',
    'server/main.lua',
    'server/modules/fire/init.lua',
    'server/modules/fire/spread.lua',
    'server/modules/turnout/appearance.lua',
    'server/modules/turnout/init.lua',
    'server/modules/scba/pass.lua',
    'server/modules/exposure/init.lua',
    'server/modules/smoke/init.lua',
    'server/modules/scorch/init.lua',
    'server/modules/admin/init.lua',
    'server/api/exports.lua',
}

-- Hard dependencies. The framework, dispatch, inventory, and appearance integrations all
-- degrade gracefully through bridge/ and are deliberately absent from this list, so
-- servers that do not run them are not blocked.
--
-- oxmysql is here because `@oxmysql/lib/MySQL.lua` above is a load-time include: without
-- it the resource does not start at all, so listing it anywhere else would be a lie.
-- Qbox and ESX both require it already. server/core/db.lua still handles the database
-- being unreachable at runtime, which is a different failure from it being absent.
dependencies {
    'ox_lib',
    'ox_target',
    'oxmysql',
}

ui_page 'web/index.html'

files {
    'install/migrations/*.sql',
    'web/index.html',
    'web/sounds.js',
    'web/hud.js',
    'web/sounds/*.ogg',
}
