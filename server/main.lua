--- Server entry point.
---
--- Boot ordering, config validation, and teardown. Feature modules register themselves;
--- this file does not know what they do.

MIFire = MIFire or {}
MIFire.ready = false

-- ---------------------------------------------------------------------------
-- Config validation
-- ---------------------------------------------------------------------------

--- Fail loudly at boot rather than quietly at 2am.
---
--- The gear check is the important one: a config that grants immunity to fire would
--- silently break the whole exposure model, and the design rule is that no tier may.
---@return string[] problems
local function validateConfig()
    local problems = {}

    if type(Config.fireJobs) ~= 'table' or next(Config.fireJobs) == nil then
        problems[#problems + 1] = 'Config.fireJobs is empty; nobody can be a firefighter'
    end

    for name, tier in pairs(MIFireGear.tiers or {}) do
        local resist = tonumber(tier.fireResist)
        if resist == nil then
            problems[#problems + 1] = ('gear tier "%s" has no fireResist'):format(name)
        elseif resist >= 1.0 then
            problems[#problems + 1] = ('gear tier "%s" has fireResist %.2f; nothing may grant immunity to fire')
                :format(name, resist)
        elseif resist < 0.0 then
            problems[#problems + 1] = ('gear tier "%s" has a negative fireResist'):format(name)
        end
    end

    if not MIFireGear.tiers[MIFireGear.defaultTier] then
        problems[#problems + 1] = ('MIFireGear.defaultTier "%s" is not a real tier')
            :format(tostring(MIFireGear.defaultTier))
    end

    for name, district in pairs(MIFireZones.districts or {}) do
        if type(district.shape) ~= 'table' then
            problems[#problems + 1] = ('district "%s" has no shape'):format(name)
        end
        if type(district.fireClasses) ~= 'table' or next(district.fireClasses) == nil then
            problems[#problems + 1] = ('district "%s" can generate no fire classes'):format(name)
        end
    end

    for _, districtName in ipairs(MIFireZones.aop.default or {}) do
        if not MIFireZones.districts[districtName] then
            problems[#problems + 1] = ('AOP default names unknown district "%s"'):format(districtName)
        end
    end

    return problems
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

    MIFire.ready = true
    MIFire.Util.debug('boot', 'framework=%s dispatch=%s', MIFire.Framework.name, dispatchDetail)
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
