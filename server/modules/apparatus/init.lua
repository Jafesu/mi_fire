--- Apparatus, server side.
---
--- Resolves a vehicle to a profile, and owns what is in its tank. The tank matters more than
--- it looks: it is the clock a crew works against before a supply line is established, and it
--- is the reason laying a line is a decision rather than a formality.

MIFire = MIFire or {}

local ApparatusServer = {}

local Util = MIFire.Util
local Apparatus = MIFire.Apparatus

--- Profiles keyed by model hash, resolved at boot.
---
--- The config is keyed by model *name* because a hash literal in a config file is unreadable,
--- and because the backtick hash form does not parse under the Lua 5.1 the test harness uses.
---@type table<number, table>
local byHash = {}

--- Live state per vehicle, keyed by network id. Not by entity handle: handles are per-client
--- and meaningless on the server across a respawn.
---@type table<number, table>
local tanks = {}

-- ---------------------------------------------------------------------------
-- Boot
-- ---------------------------------------------------------------------------

--- Resolve names to hashes and validate every profile.
---
--- Validation is a boot failure rather than a warning for ports, because a bad port surfaces
--- as a hose connecting to nothing halfway through an incident, and by then nobody is going to
--- connect it to a config file they edited last week.
---@return string[] errors
function ApparatusServer.build()
    local errors = {}

    for name, profile in pairs(MIFireApparatus.profiles) do
        local resolved = Apparatus.resolve(profile, MIFireApparatus.defaults)
        resolved.modelName = name

        local problems = Apparatus.validate(resolved, MIFireApparatus.portTypes)

        for i = 1, #problems do
            errors[#errors + 1] = ('apparatus "%s": %s'):format(name, problems[i])
        end

        -- Ergonomics rather than correctness, so these are said and then ignored. Refusing to
        -- boot a server over a confusing eye menu would be absurd; letting one ship without
        -- anyone noticing is how it stays confusing.
        for _, warning in ipairs(Apparatus.warnings(resolved, MIFireApparatus.portReach)) do
            Util.warn('apparatus "%s": %s', name, warning)
        end

        byHash[GetHashKey(name)] = resolved
    end

    return errors
end

--- The profile for a vehicle, or nil.
---@param entity integer
---@return table|nil
function ApparatusServer.profile(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end

    local profile = byHash[GetEntityModel(entity)]
    if profile then return profile end

    -- An unprofiled rig is usable rather than broken, so a server running trucks nobody has
    -- authored yet still works. Turn `allowUnprofiled` off once your fleet is done and an
    -- unconfigured rig becomes obvious instead of quietly behaving like something it is not.
    if MIFireApparatus.allowUnprofiled and GetVehicleClass(entity) == 18 then
        return Apparatus.resolve(MIFireApparatus.unprofiled, MIFireApparatus.defaults)
    end

    return nil
end

---@param entity integer
---@return boolean
function ApparatusServer.isApparatus(entity)
    return ApparatusServer.profile(entity) ~= nil
end

-- ---------------------------------------------------------------------------
-- Tanks
-- ---------------------------------------------------------------------------

--- Tank state for a vehicle, created on first use at full.
---
--- A rig arriving at a call with a full tank is the right default: apparatus are filled at the
--- station, and starting them empty would make every first call a water supply exercise.
---@param entity integer
---@return table|nil { water, foam, capacity, foamCapacity, pumpEngaged }
function ApparatusServer.tank(entity)
    local profile = ApparatusServer.profile(entity)
    if not profile then return nil end

    local netId = NetworkGetNetworkIdFromEntity(entity)
    if not netId or netId == 0 then return nil end

    local tank = tanks[netId]

    if not tank then
        tank = {
            water = profile.tankGallons or 0.0,
            capacity = profile.tankGallons or 0.0,
            foam = profile.foamGallons or 0.0,
            foamCapacity = profile.foamGallons or 0.0,
            pumpEngaged = false,
        }
        tanks[netId] = tank
    end

    return tank
end

--- Draw water. Returns what was actually available, which is the whole point -- a pump asking
--- for 150 gpm from a tank with 20 gallons in it gets 20, and then the line goes soft.
---@param entity integer
---@param gallons number
---@return number drawn
function ApparatusServer.draw(entity, gallons)
    local tank = ApparatusServer.tank(entity)
    if not tank then return 0.0 end

    local drawn = math.min(math.max(0.0, gallons), tank.water)
    tank.water = tank.water - drawn

    return drawn
end

--- Put water in. Returns what fitted, so a supply line filling a full tank does not silently
--- discard the rest of the flow.
---@param entity integer
---@param gallons number
---@return number accepted
function ApparatusServer.fill(entity, gallons)
    local tank = ApparatusServer.tank(entity)
    if not tank then return 0.0 end

    local space = math.max(0.0, tank.capacity - tank.water)
    local accepted = math.min(math.max(0.0, gallons), space)
    tank.water = tank.water + accepted

    return accepted
end

--- Engage or disengage the pump.
---@param entity integer
---@param engaged boolean
---@return boolean ok
---@return string|nil reason
function ApparatusServer.setPump(entity, engaged)
    local profile = ApparatusServer.profile(entity)
    if not profile then return false, 'that is not fire apparatus' end

    if engaged and not Apparatus.hasPump(profile) then
        return false, ('a %s has no pump'):format(profile.label or 'rig')
    end

    -- Almost everything has to be stopped and in neutral to pump. A brush rig is the exception
    -- and that is the whole tactic: pump-and-roll is how a wildland fire gets fought.
    if engaged and not profile.pumpAndRoll then
        local speed = GetEntitySpeed(entity)
        if speed > 1.0 then
            return false, 'stop the rig before engaging the pump'
        end
    end

    local tank = ApparatusServer.tank(entity)
    if tank then tank.pumpEngaged = engaged end

    return true
end

---@param netId number
function ApparatusServer.forget(netId)
    tanks[netId] = nil
end

exports('GetApparatusProfile', function(entity) return ApparatusServer.profile(entity) end)
exports('GetApparatusTank', function(entity) return ApparatusServer.tank(entity) end)
exports('IsApparatus', function(entity) return ApparatusServer.isApparatus(entity) end)
exports('DrawWater', function(entity, gallons) return ApparatusServer.draw(entity, gallons) end)
exports('FillTank', function(entity, gallons) return ApparatusServer.fill(entity, gallons) end)

MIFire.ApparatusServer = ApparatusServer

return ApparatusServer
