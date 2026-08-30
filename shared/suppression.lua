--- Suppression maths.
---
--- What an agent does to a fire class, at a flow, at a distance. Pure, so the answers can
--- be checked against the design intent outside the game -- the same reason
--- `shared/hydraulics.lua` is pure.
---
--- The value that matters most here is the sign. A negative knockdown rate is not an
--- error condition to be clamped away: it is water on a grease fire, and the engine is
--- expected to apply it as growth and fire the matching hazard.

MIFire = MIFire or {}

local Suppression = {}

-- ---------------------------------------------------------------------------

--- Look up an agent against a fire class.
---@param agentName string
---@param className string
---@return table|nil entry { effectiveness, hazard?, note? }
function Suppression.lookup(agentName, className)
    local agents = rawget(_G, 'MIFireAgents')
    if not agents or type(agents.matrix) ~= 'table' then return nil end

    local row = agents.matrix[agentName]
    if type(row) ~= 'table' then return nil end

    return row[className]
end

--- Effectiveness alone, defaulting to 0 for an unknown pairing.
---
--- Zero rather than 1: an agent with no entry does nothing, which is the safe reading.
--- Treating a missing entry as fully effective would silently make every unconfigured
--- combination a win. `shared/validate.lua` rejects a matrix with holes at boot, so this
--- default should never actually be reached in a valid configuration.
---@param agentName string
---@param className string
---@return number
function Suppression.effectiveness(agentName, className)
    local entry = Suppression.lookup(agentName, className)
    if not entry then return 0.0 end
    return tonumber(entry.effectiveness) or 0.0
end

--- The hazard this pairing fires, if any.
---@param agentName string
---@param className string
---@return string|nil hazardName
---@return table|nil hazardConfig
function Suppression.hazard(agentName, className)
    local entry = Suppression.lookup(agentName, className)
    if not entry or not entry.hazard then return nil end

    local agents = rawget(_G, 'MIFireAgents')
    local config = agents and agents.hazards and agents.hazards[entry.hazard]
    return entry.hazard, config
end

--- Is this agent actively harmful against this class?
---@param agentName string
---@param className string
---@return boolean
function Suppression.isCounterproductive(agentName, className)
    return Suppression.effectiveness(agentName, className) < 0
end

-- ---------------------------------------------------------------------------

--- Scale effectiveness by how far the stream is from the node.
---
--- Full strength at the nozzle, falling to `rangeFalloff` at maximum reach, and nothing
--- beyond. Linear, because a more elaborate curve would not be distinguishable in play.
---@param distance number Metres.
---@param maxRange number
---@param falloffAtMax number Effectiveness fraction at maximum range.
---@return number 0-1
function Suppression.rangeFactor(distance, maxRange, falloffAtMax)
    distance = tonumber(distance) or 0
    maxRange = tonumber(maxRange) or 0
    if maxRange <= 0 then return 0.0 end
    if distance >= maxRange then return 0.0 end
    if distance <= 0 then return 1.0 end

    local t = distance / maxRange
    return 1.0 - t * (1.0 - (tonumber(falloffAtMax) or 0.0))
end

--- Scale by flow, with diminishing returns.
---
--- Past the reference flow, extra gallons keep helping but less than linearly -- beyond a
--- point you are wetting things that are already wet. The exponent is configuration
--- because it is the main lever on how much a bigger line is worth.
---@param gpm number
---@param referenceGpm number
---@param exponent number
---@return number multiplier
function Suppression.flowFactor(gpm, referenceGpm, exponent)
    gpm = tonumber(gpm) or 0
    referenceGpm = tonumber(referenceGpm) or 0
    if gpm <= 0 or referenceGpm <= 0 then return 0.0 end
    return (gpm / referenceGpm) ^ (tonumber(exponent) or 1.0)
end

-- ---------------------------------------------------------------------------

--- Intensity change per second from applying an agent to a node.
---
--- **Positive means the fire is being knocked down. Negative means it is growing**, which
--- is what the wrong agent does and is deliberately not clamped.
---
---@param opts table
---   agent       string  agent key
---   class       table   a resolved class from `MIFire.FireClass.resolve`
---   gpm         number  flow reaching the node
---   distance    number  metres from applicator to node
---   maxRange    number|nil  overrides the configured range, for extinguishers
---   efficiency  number|nil  multiplier, e.g. sprinklers wet an area rather than aiming
---@return number intensityPerSecond
---@return number effectiveness The raw matrix value, for callers that need the sign.
function Suppression.rate(opts)
    opts = opts or {}
    local class = opts.class
    if type(class) ~= 'table' then return 0.0, 0.0 end

    local agents = rawget(_G, 'MIFireAgents')
    local tuning = agents and agents.suppression
    if not tuning then return 0.0, 0.0 end

    local effectiveness = Suppression.effectiveness(opts.agent, class.name)
    if effectiveness == 0 then return 0.0, 0.0 end

    local maxRange = tonumber(opts.maxRange) or tuning.maxRange
    local range = Suppression.rangeFactor(opts.distance or 0, maxRange, tuning.rangeFalloff)
    if range <= 0 then return 0.0, effectiveness end

    local flow = Suppression.flowFactor(opts.gpm, tuning.referenceFlowGpm, tuning.flowExponent)
    if flow <= 0 then return 0.0, effectiveness end

    local resistance = tonumber(class.resistance) or 1.0
    if resistance <= 0 then resistance = 1.0 end

    local base = tuning.intensityPerSecondAtReferenceFlow * flow * effectiveness / resistance
    return base * range * (tonumber(opts.efficiency) or 1.0), effectiveness
end

--- Flat-rate application from a hand extinguisher.
---
--- Deliberately not a tiny hose line: an extinguisher has a fixed discharge rate and a
--- short reach, so it gets its own path rather than being modelled as a very small gpm.
---@param opts table { agent, class, distance }
---@return number intensityPerSecond
---@return number effectiveness
function Suppression.extinguisherRate(opts)
    opts = opts or {}
    local class = opts.class
    if type(class) ~= 'table' then return 0.0, 0.0 end

    local agents = rawget(_G, 'MIFireAgents')
    local tuning = agents and agents.suppression and agents.suppression.extinguisher
    if not tuning then return 0.0, 0.0 end

    local effectiveness = Suppression.effectiveness(opts.agent, class.name)
    if effectiveness == 0 then return 0.0, 0.0 end

    local range = Suppression.rangeFactor(opts.distance or 0, tuning.maxRange,
        agents.suppression.rangeFalloff)
    if range <= 0 then return 0.0, effectiveness end

    local resistance = tonumber(class.resistance) or 1.0
    if resistance <= 0 then resistance = 1.0 end

    return tuning.intensityPerSecond * effectiveness / resistance * range, effectiveness
end

--- Seconds of correct application to take a node from full intensity to knocked down.
---
--- Used for balance checking rather than by the engine. A class that cannot be knocked
--- down in a reasonable time by its correct agent is a class nobody will fight twice.
---@param agentName string
---@param class table Resolved class.
---@param gpm number
---@return number seconds, or math.huge when the agent cannot knock it down at all.
function Suppression.timeToKnockdown(agentName, class, gpm)
    local rate = Suppression.rate({
        agent = agentName, class = class, gpm = gpm, distance = 0,
    })
    if rate <= 0 then return math.huge end
    return (tonumber(class.maxIntensity) or 100.0) / rate
end

MIFire.Suppression = Suppression

return Suppression
