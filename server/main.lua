--- Server entry point.
---
--- Boot ordering, config validation, and teardown. Feature modules register themselves;
--- this file does not know what they do.

MIFire = MIFire or {}
MIFire.ready = false

-- ---------------------------------------------------------------------------
-- Config validation
-- ---------------------------------------------------------------------------

--- Validation itself lives in `shared/validate.lua` as a pure function, so the real
--- boot check can be exercised by `tools/run_tests.lua` outside FiveM. Discovering a
--- broken config on a live server is the expensive way to find out.
---@return string[] problems
local function validateConfig()
    return MIFire.Validate.configuration(
        Config, MIFireGear, MIFireZones, MIFireClasses, MIFireAgents)
end

-- ---------------------------------------------------------------------------
-- Boot
-- ---------------------------------------------------------------------------

CreateThread(function()
    local problems = validateConfig()

    if #problems > 0 then
        print('[mi_fire] configuration problems found:')
        for i = 1, #problems do
            print(('  - %s'):format(problems[i]))
        end
        print('[mi_fire] refusing to start with an invalid configuration')
        return
    end

    -- Dispatch is optional but a silent board is confusing, so say which way it went.
    local dispatchOk, dispatchDetail = MIFire.Dispatch.status()
    if not dispatchOk then
        MIFire.Util.warn('dispatch unavailable (%s); fires will still start but nobody will be toned',
            dispatchDetail)
    end

    -- Stations are the only thing that needs the database. Everything else runs without
    -- it, so a failure here is a warning rather than a refusal to start.
    local dbOk = MIFire.DB.init()

    MIFire.ready = true
    MIFire.Util.debug('boot', 'framework=%s dispatch=%s database=%s',
        MIFire.Framework.name, dispatchDetail, dbOk and 'ready' or 'unavailable')
end)

-- ---------------------------------------------------------------------------
-- Teardown
-- ---------------------------------------------------------------------------

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    -- Tell every client to clean up its own side before state disappears underneath it.
    TriggerClientEvent('mi_fire:client:teardown', -1)
    MIFire.State.reset()
    MIFire.ready = false
end)
