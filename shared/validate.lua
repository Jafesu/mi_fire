--- Configuration validation.
---
--- Pure: takes the config tables, returns a list of problems. No natives, no globals
--- read directly, no printing. That is what lets `tools/run_tests.lua` exercise the real
--- validation path outside FiveM instead of discovering a broken config on a live server.
---
--- `server/main.lua` calls this at boot and refuses to start if anything comes back. A
--- resource that boots into a half-working state is harder to debug than one that says
--- why it will not.

MIFire = MIFire or {}

local Validate = {}

--- Check every config table for problems that would make the resource misbehave.
---
--- Pass the tables explicitly rather than reading globals, so a test can feed it a
--- deliberately broken config without mutating the real one.
---
---@param cfg table Config
---@param gear table MIFireGear
---@param zones table MIFireZones
---@param classes table|nil MIFireClasses
---@param agents table|nil MIFireAgents
---@return string[] problems Empty when the configuration is sound.
function Validate.configuration(cfg, gear, zones, classes, agents)
    local problems = {}

    local function fail(message, ...)
        problems[#problems + 1] = select('#', ...) > 0 and message:format(...) or message
    end

    -- --- Jobs ---------------------------------------------------------------

    if type(cfg) ~= 'table' then
        fail('Config is missing entirely')
        return problems
    end

    if type(cfg.fireJobs) ~= 'table' or next(cfg.fireJobs) == nil then
        fail('Config.fireJobs is empty; nobody can be a firefighter')
    end

    -- --- Gear ---------------------------------------------------------------
    --
    -- The invariant from ADR 0001. Enforced here as well as in a test, because a server
    -- owner editing config/gear.lua never runs the test suite.

    if type(gear) ~= 'table' or type(gear.tiers) ~= 'table' then
        fail('MIFireGear.tiers is missing; there are no protective equipment tiers')
    else
        for name, tier in pairs(gear.tiers) do
            local resist = tonumber(tier.fireResist)
            if resist == nil then
                fail('gear tier "%s" has no fireResist', name)
            elseif resist >= 1.0 then
                fail('gear tier "%s" has fireResist %.2f; nothing may grant immunity to fire',
                    name, resist)
            elseif resist < 0.0 then
                fail('gear tier "%s" has a negative fireResist', name)
            end
        end

        if not gear.tiers[gear.defaultTier] then
            fail('MIFireGear.defaultTier "%s" is not a real tier', tostring(gear.defaultTier))
        end
    end

    -- --- Districts and AOP --------------------------------------------------

    if type(zones) ~= 'table' or type(zones.districts) ~= 'table' then
        fail('MIFireZones.districts is missing; nothing can generate anywhere')
    else
        if next(zones.districts) == nil then
            fail('MIFireZones.districts is empty; nothing can generate anywhere')
        end

        for name, district in pairs(zones.districts) do
            if type(district.shape) ~= 'table' then
                fail('district "%s" has no shape', name)
            elseif district.shape.type == 'sphere' then
                if type(district.shape.coords) ~= 'table' then
                    fail('district "%s" is a sphere with no coords', name)
                end
                if (tonumber(district.shape.radius) or 0) <= 0 then
                    fail('district "%s" is a sphere with no radius', name)
                end
            elseif district.shape.type == 'poly' then
                if type(district.shape.points) ~= 'table' or #district.shape.points < 3 then
                    fail('district "%s" is a polygon with fewer than three points', name)
                end
            else
                fail('district "%s" has an unknown shape type "%s"',
                    name, tostring(district.shape.type))
            end

            if type(district.fireClasses) ~= 'table' or next(district.fireClasses) == nil then
                fail('district "%s" can generate no fire classes', name)
            elseif classes and type(classes.classes) == 'table' then
                for className in pairs(district.fireClasses) do
                    if not classes.classes[className] then
                        fail('district "%s" names unknown fire class "%s"', name, className)
                    end
                end
            end
        end

        if type(zones.aop) == 'table' then
            for _, districtName in ipairs(zones.aop.default or {}) do
                if not zones.districts[districtName] then
                    fail('AOP default names unknown district "%s"', districtName)
                end
            end

            local mode = zones.aop.mode
            if mode ~= 'manual' and mode ~= 'auto' and mode ~= 'all' then
                fail('MIFireZones.aop.mode "%s" is not manual, auto, or all', tostring(mode))
            end

            local auto = zones.aop.auto
            if type(auto) == 'table' then
                local minimum = tonumber(auto.minimumActive) or 0
                local maximum = tonumber(auto.maximumActive) or 0
                if maximum > 0 and minimum > maximum then
                    fail('AOP minimumActive (%d) is above maximumActive (%d); no district set can satisfy both',
                        minimum, maximum)
                end
            end
        else
            fail('MIFireZones.aop is missing')
        end

        -- Run cards reference stations by name. A card naming a station that does not
        -- exist is only detectable once stations are loaded, so this checks the shape
        -- rather than the target.
        if type(zones.runCards) == 'table' then
            if type(zones.runCards.default) ~= 'table' then
                fail('MIFireZones.runCards has no default card')
            end
            for districtName in pairs(zones.runCards.byDistrict or {}) do
                if not zones.districts[districtName] then
                    fail('a run card is defined for unknown district "%s"', districtName)
                end
            end
        end
    end

    -- --- Agents -------------------------------------------------------------
    --
    -- Every fire class must be scored by every agent, or applying that agent to that
    -- class silently does nothing at all -- which looks like a bug in the fire engine
    -- and is actually a hole in a table.

    if classes and agents and type(classes.classes) == 'table' and type(agents.matrix) == 'table' then
        for agentName, row in pairs(agents.matrix) do
            for className in pairs(classes.classes) do
                if row[className] == nil then
                    fail('agent "%s" has no entry for fire class "%s"', agentName, className)
                elseif tonumber(row[className].effectiveness) == nil then
                    fail('agent "%s" against class "%s" has no numeric effectiveness',
                        agentName, className)
                end
            end
        end

        -- A hazard named by the matrix but not defined would error the moment someone
        -- did the wrong thing, which is exactly when you least want a crash.
        for agentName, row in pairs(agents.matrix) do
            for className, entry in pairs(row) do
                if entry.hazard and type(agents.hazards) == 'table'
                    and not agents.hazards[entry.hazard] then
                    fail('agent "%s" against class "%s" names undefined hazard "%s"',
                        agentName, className, entry.hazard)
                end
            end
        end
    end

    return problems
end

MIFire.Validate = Validate

return Validate
