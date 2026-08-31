--- Boot simulation.
---
--- Loads every file in the order `fxmanifest.lua` declares, against stubbed FiveM
--- natives, and then runs the real configuration validation.
---
--- This is not a substitute for starting a server. What it does catch is the class of
--- failure that is most annoying to find on one: a file that references something not
--- loaded yet, a global that never gets set, a typo in a table access that only executes
--- at boot. Those cost a server restart each to find in game and cost nothing here.
---
--- What it deliberately does NOT prove: that the natives behave, that ox_lib is present,
--- that the migrations are valid SQL, or that anything works. Only a real boot does that.

return function(t)

    -- -----------------------------------------------------------------------
    -- Native stubs
    -- -----------------------------------------------------------------------

    local threads = {}
    local eventHandlers = {}
    local printed = {}

    --- Threads in this resource are `while true do Wait(n) ... end`. A no-op `Wait` turns
    --- every one of them into an infinite loop, so the stub throws a sentinel instead:
    --- the thread unwinds at its first yield point and the runner treats that as success.
    --- Reaching a Wait is exactly what "the thread started correctly" means.
    local YIELD = {}

    local stubs = {
        --- Nothing is "started" in a bare interpreter, so every bridge takes its
        --- absent path. That is the interesting case anyway: it proves the resource
        --- survives its optional integrations all being missing.
        GetResourceState = function() return 'missing' end,
        GetCurrentResourceName = function() return 'mi_fire' end,

        --- Apparatus profiles are keyed by model name in config and resolved to hashes at
        --- boot, so this has to exist for the boot check to run at all. A real hash is not
        --- needed -- only that distinct names give distinct keys, which is what the profile
        --- table depends on.
        GetHashKey = function(name)
            local hash = 0
            for i = 1, #tostring(name) do
                hash = (hash * 31 + tostring(name):byte(i)) % 2147483647
            end
            return hash
        end,
        IsDuplicityVersion = function() return true end,
        LoadResourceFile = function() return nil end,

        CreateThread = function(fn) threads[#threads + 1] = fn end,
        AddEventHandler = function(name, fn) eventHandlers[name] = fn end,
        RegisterNetEvent = function(name, fn) eventHandlers[name] = fn end,
        RegisterCommand = function() end,
        TriggerClientEvent = function() end,
        TriggerEvent = function() end,
        Wait = function() error(YIELD) end,

        -- Deliberately deny everything: the interesting case for permissions is the
        -- player who has nothing, since that is the one that produces a support ticket.
        IsPedMale = function() return true end,
        IsPlayerAceAllowed = function() return false end,
        IsPrincipalAceAllowed = function() return false end,
        GetPlayerPed = function() return 0 end,
        GetPlayers = function() return {} end,
        GetEntityCoords = function() return { x = 0.0, y = 0.0, z = 0.0 } end,
        DoesEntityExist = function() return false end,
        NetworkGetEntityFromNetworkId = function() return 0 end,

        vector2 = function(x, y) return { x = x, y = y } end,
        vector3 = function(x, y, z) return { x = x, y = y, z = z } end,

        --- `exports` is indexed as `exports.name:Method()` and called as
        --- `exports('Name', fn)`. Both shapes have to work.
        exports = setmetatable({}, {
            __index = function()
                return setmetatable({}, { __index = function() return function() end end })
            end,
            __call = function() end,
        }),

        cache = { ped = 1, serverId = 1 },
        lib = setmetatable({}, { __index = function() return function() end end }),
    }

    -- Keep the real print but capture it, so a noisy boot is visible in the test output
    -- without drowning it.
    local realPrint = print
    stubs.print = function(...)
        local parts = {}
        for i = 1, select('#', ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        printed[#printed + 1] = table.concat(parts, ' ')
    end

    for name, value in pairs(stubs) do
        if rawget(_G, name) == nil then rawset(_G, name, value) end
    end

    -- -----------------------------------------------------------------------
    -- Load in manifest order
    -- -----------------------------------------------------------------------

    t.describe('files load in manifest order')

    --- Mirrors fxmanifest.lua. If a file is added there and not here, this list drifts --
    --- which is a real risk, so the next check compares the two.
    local sharedFiles = {
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
        'shared/apparatus.lua',
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
        'config/apparatus.lua',
    }

    local serverFiles = {
        'bridge/framework/init.lua',
        'bridge/dispatch/init.lua',
        'bridge/inventory/ox_inventory.lua',
        'bridge/medical/init.lua',
        'server/core/db.lua',
        'server/core/state.lua',
        'server/core/permissions.lua',
        'server/modules/apparatus/init.lua',
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

    --- Client files whose top level is pure enough to load here.
    ---
    --- The appearance bridge is client-side but its slot resolution is arithmetic on
    --- tables, and it is exactly the kind of logic worth testing -- a helmet routed to the
    --- wrong native fails silently. Files that genuinely need natives at load time stay
    --- out; a fake pass there would be worse than no test.
    local pureClientFiles = {
        'bridge/appearance/illenium.lua',
    }

    local function load(path)
        local chunk, err = loadfile(path)
        if not chunk then
            t.ok(false, ('%s failed to parse: %s'):format(path, tostring(err)))
            return false
        end

        local ok, runErr = pcall(chunk)
        t.ok(ok, ('%s loads'):format(path))
        if not ok then realPrint(('    -> %s'):format(tostring(runErr))) end
        return ok
    end

    for _, path in ipairs(sharedFiles) do load(path) end
    for _, path in ipairs(serverFiles) do load(path) end
    for _, path in ipairs(pureClientFiles) do load(path) end

    -- -----------------------------------------------------------------------

    t.describe('the manifest and this test agree')

    -- A file added to the manifest but not to this test would silently stop being boot
    -- checked, which is the failure mode that makes a test like this rot.
    local manifest = io.open('fxmanifest.lua', 'r')
    t.ok(manifest ~= nil, 'fxmanifest.lua is readable')

    if manifest then
        local body = manifest:read('*a')
        manifest:close()

        local declared = {}
        for path in body:gmatch("'([%w_/]+%.lua)'") do declared[path] = true end

        local known = {}
        for _, path in ipairs(sharedFiles) do known[path] = true end
        for _, path in ipairs(serverFiles) do known[path] = true end
        for _, path in ipairs(pureClientFiles) do known[path] = true end
        -- Client files are not loadable here; they are excluded on purpose.
        for _, path in ipairs({
            'bridge/target/ox_target.lua',
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
            'client/modules/placement/init.lua',
            'client/modules/offsetfinder/init.lua',
        }) do known[path] = true end

        for path in pairs(declared) do
            t.ok(known[path] == true,
                ('%s is declared in the manifest and known to the boot test'):format(path))
        end
    end

    -- -----------------------------------------------------------------------

    t.describe('globals the modules promise')

    local expected = {
        'Enums', 'Util', 'Hydraulics', 'Validate', 'FireClass', 'Suppression',
        'Framework', 'Dispatch', 'Inventory', 'DB', 'State', 'Permissions',
        'Fire', 'Spread', 'Admin', 'Turnout', 'Appearance', 'GearAppearance',
        'Pass', 'PassServer', 'Exposure', 'ExposureServer', 'Medical', 'Smoke', 'SmokeServer', 'GearMatch', 'Integrity', 'Scorch', 'Apparatus',
    }
    for _, name in ipairs(expected) do
        t.ok(type(MIFire) == 'table' and MIFire[name] ~= nil,
            ('MIFire.%s is set after load'):format(name))
    end

    local configGlobals = {
        'Config', 'MIFireGear', 'MIFireZones', 'MIFireClasses', 'MIFireAgents',
        'MIFireStations', 'MIFireSprinklers', 'MIFireScba', 'MIFireSmoke',
    }
    for _, name in ipairs(configGlobals) do
        t.ok(rawget(_G, name) ~= nil, ('%s is set after load'):format(name))
    end

    -- -----------------------------------------------------------------------

    t.describe('the shipped configuration validates')

    local problems = MIFire.Validate.configuration(
        Config, MIFireGear, MIFireZones, MIFireClasses, MIFireAgents)

    if #problems > 0 then
        for i = 1, #problems do
            realPrint(('    -> %s'):format(problems[i]))
        end
    end

    t.equal(#problems, 0, 'the configuration this repo ships boots without complaint')

    -- -----------------------------------------------------------------------

    t.describe('validation catches a broken configuration')

    -- The checks are only worth having if they fire. Each case is a mistake a server
    -- owner could plausibly make while editing a config file.

    local U = MIFire.Util

    local immuneGear = U.deepCopy(MIFireGear)
    immuneGear.tiers.structural.fireResist = 1.0
    t.ok(#MIFire.Validate.configuration(Config, immuneGear, MIFireZones) > 0,
        'a gear tier granting immunity to fire is rejected')

    local badDefault = U.deepCopy(MIFireGear)
    badDefault.defaultTier = 'nonexistent'
    t.ok(#MIFire.Validate.configuration(Config, badDefault, MIFireZones) > 0,
        'a defaultTier naming no real tier is rejected')

    local noJobs = U.deepCopy(Config)
    noJobs.fireJobs = {}
    t.ok(#MIFire.Validate.configuration(noJobs, MIFireGear, MIFireZones) > 0,
        'an empty fireJobs table is rejected')

    local badAop = U.deepCopy(MIFireZones)
    badAop.aop.default = { 'a_district_that_does_not_exist' }
    t.ok(#MIFire.Validate.configuration(Config, MIFireGear, badAop) > 0,
        'an AOP naming an unknown district is rejected')

    local badMode = U.deepCopy(MIFireZones)
    badMode.aop.mode = 'sometimes'
    t.ok(#MIFire.Validate.configuration(Config, MIFireGear, badMode) > 0,
        'an unknown AOP mode is rejected')

    local shapeless = U.deepCopy(MIFireZones)
    shapeless.districts.pillbox_hill.shape = nil
    t.ok(#MIFire.Validate.configuration(Config, MIFireGear, shapeless) > 0,
        'a district with no shape is rejected')

    local unknownClass = U.deepCopy(MIFireZones)
    unknownClass.districts.pillbox_hill.fireClasses = { not_a_class = 1.0 }
    t.ok(#MIFire.Validate.configuration(Config, MIFireGear, unknownClass, MIFireClasses) > 0,
        'a district naming an unknown fire class is rejected')

    local holedMatrix = U.deepCopy(MIFireAgents)
    holedMatrix.matrix.water.D = nil
    t.ok(#MIFire.Validate.configuration(Config, MIFireGear, MIFireZones, MIFireClasses, holedMatrix) > 0,
        'an agent missing a fire class is rejected, because that silently does nothing')

    -- The bug this whole check exists for: an invented particle name draws nothing and
    -- reports nothing, so the server logs look perfect while the game looks broken.
    local madeUpEffect = U.deepCopy(MIFireClasses)
    madeUpEffect.classes.A.ptfx = { { dict = 'core', name = 'fire_wrecked_plane_cabin' } }
    t.ok(#MIFire.Validate.configuration(Config, MIFireGear, MIFireZones, madeUpEffect) > 0,
        'an unverified particle effect name is rejected at boot rather than failing silently')

    local madeUpDict = U.deepCopy(MIFireClasses)
    madeUpDict.classes.A.ptfx = { { dict = 'not_a_dictionary', name = 'whatever' } }
    t.ok(#MIFire.Validate.configuration(Config, MIFireGear, MIFireZones, madeUpDict) > 0,
        'so is an unverified dictionary')

    local noPtfx = U.deepCopy(MIFireClasses)
    noPtfx.classes.A.ptfx = {}
    t.ok(#MIFire.Validate.configuration(Config, MIFireGear, MIFireZones, noPtfx) > 0,
        'and a class with no layers at all, which would be an invisible fire')

    local ghostHazard = U.deepCopy(MIFireAgents)
    ghostHazard.matrix.water.B.hazard = 'not_a_real_hazard'
    t.ok(#MIFire.Validate.configuration(Config, MIFireGear, MIFireZones, MIFireClasses, ghostHazard) > 0,
        'an undefined hazard is rejected, because it would crash exactly when it mattered')

    -- -----------------------------------------------------------------------

    t.describe('boot thread runs')

    -- server/main.lua registers its work in a CreateThread. Run it and confirm it does
    -- not throw against a world where nothing else is started.
    t.ok(#threads > 0, 'server/main.lua queued a boot thread')

    for i = 1, #threads do
        local ok, err = pcall(threads[i])
        -- Unwinding at a Wait is the expected outcome for a looping thread.
        local yielded = (not ok) and err == YIELD
        t.ok(ok or yielded,
            ('boot thread %d runs to completion or to its first yield'):format(i))
        if not ok and not yielded then realPrint(('    -> %s'):format(tostring(err))) end
    end

    t.ok(eventHandlers['onResourceStop'] ~= nil,
        'a teardown handler is registered, so a restart cleans up')
end
