--- Server export surface.
---
--- Two sets. The first deliberately matches the names and return shapes of the resource
--- mi_fire replaces, so add-ons written against it -- `mi_fire_rescue` in particular --
--- migrate by changing one config string. The second is the native API, which is not
--- constrained by an older resource's decisions and is what new work should use.
---
--- These are transports. Every one is a thin wrapper over a service, and none of them
--- contain logic. See `docs/internal/CONTRACTS.md`.

MIFire = MIFire or {}

local Enums = MIFire.Enums
local State = MIFire.State
local Util = MIFire.Util

-- ---------------------------------------------------------------------------
-- Row shapes
-- ---------------------------------------------------------------------------

--- The row shape consumers expect back from `GetAllFires`.
---
--- `live` is the field that matters to `mi_fire_rescue`: it decides whether a civilian is
--- still in danger. A knocked-down node is present but not live.
---@param node table
---@return table
local function fireRow(node)
    return {
        id = node.id,
        coords = vector3(node.coords.x, node.coords.y, node.coords.z),
        incidentId = node.incidentId,
        sourceIncidentId = node.incidentId,
        type = node.interiorId and 'indoors' or 'outdoors',
        active = true,
        live = node.state ~= Enums.NodeState.OUT
            and node.state ~= Enums.NodeState.KNOCKED_DOWN
            and node.state ~= Enums.NodeState.OVERHAULED
            and node.intensity > 0,
        pendingSeed = false,
        strength = node.intensity,
        isDead = node.intensity <= 0,
        generation = node.generation or 0,
    }
end

-- ---------------------------------------------------------------------------
-- Compatibility surface
-- ---------------------------------------------------------------------------

--- Create a fire. Positional arguments, matching the resource being replaced.
---@return string|nil incidentId
exports('CreateFire', function(x, y, z, fireType, radius, count, explicitInteriorId, suppressExternalDispatch)
    local incidentId = MIFire.Fire.startIncident({
        coords = { x = tonumber(x) or 0.0, y = tonumber(y) or 0.0, z = tonumber(z) or 0.0 },
        class = fireType or Enums.FireClass.A,
        radius = tonumber(radius),
        nodeCount = tonumber(count),
        interiorId = explicitInteriorId,
        suppressDispatch = suppressExternalDispatch == true,
        origin = Enums.IncidentOrigin.EXPORT,
    })
    return incidentId
end)

exports('StopFire', function(incidentId)
    return MIFire.Fire.stopIncident(tostring(incidentId)) == true
end)

exports('GetAllFires', function()
    local out = {}
    for _, node in pairs(State.getNodes()) do out[#out + 1] = fireRow(node) end
    return out
end)

exports('GetFiresForIncident', function(incidentId)
    if incidentId == nil then return {} end
    local out = {}
    for _, node in ipairs(State.getNodesForIncident(tostring(incidentId))) do
        local row = fireRow(node)
        if row.live then out[#out + 1] = row end
    end
    return out
end)

exports('GetIncidentStatus', function(incidentId)
    local incident = State.getIncident(incidentId)
    return incident and incident.state or nil
end)

--- Incidents do not merge yet (`FIRE-004`), so an id is always its own host. Present so
--- consumers written against the old resource do not have to branch on its absence.
exports('GetCanonicalIncidentId', function(incidentId)
    return incidentId
end)

--- Vehicle fires are not implemented yet (`FIRE-010`). Returning empty is honest;
--- returning nil would break callers that iterate the result.
exports('GetActiveVehicleFires', function() return {} end)

--- Smoke is a separate system that does not exist yet (`FIRE-008`).
exports('GetAllSmokes', function() return {} end)
exports('CreateSmoke', function() return nil end)
exports('StopSmoke', function() return false end)

--- Interior probing needs a client (`FIRE-009`). Nil means "outdoors as far as we know",
--- which is what a caller should assume rather than treating it as an error.
exports('ProbeInteriorAtCoords', function() return nil end)

--- Apply damage-equivalent suppression at a point. The old resource used this to let
--- other scripts knock fire down; here it routes through the agent matrix like everything
--- else, so the same rules apply.
exports('ApplyFireDamageAtCoords', function(x, y, z, radius, amount, opts)
    opts = opts or {}
    local result = MIFire.Fire.applyAgent(
        { x = tonumber(x) or 0.0, y = tonumber(y) or 0.0, z = tonumber(z) or 0.0 },
        tonumber(radius) or 5.0,
        opts.agent or Enums.Agent.WATER,
        {
            gpm = tonumber(opts.gpm) or 150.0,
            seconds = tonumber(amount) or 1.0,
            efficiency = tonumber(opts.efficiency),
        })
    return result.nodesAffected
end)

-- ---------------------------------------------------------------------------
-- Native surface
-- ---------------------------------------------------------------------------

--- Start an incident from a table. Preferred over `CreateFire`.
---@return string|nil incidentId
---@return string|nil error
exports('StartIncident', function(spec)
    if type(spec) ~= 'table' then return nil, 'NO_SPEC' end
    spec.origin = spec.origin or Enums.IncidentOrigin.EXPORT
    return MIFire.Fire.startIncident(spec)
end)

exports('GetIncident', function(incidentId)
    return MIFire.Fire.describe(tostring(incidentId))
end)

exports('GetIncidents', function()
    local out = {}
    for incidentId in pairs(State.getIncidents()) do
        out[#out + 1] = MIFire.Fire.describe(incidentId)
    end
    return out
end)

exports('StopIncident', function(incidentId)
    return MIFire.Fire.stopIncident(tostring(incidentId)) == true
end)

exports('StopAllIncidents', function()
    return MIFire.Fire.stopAll()
end)

--- Apply an agent at a point. The single entry for suppression, so no future water
--- source can bypass the agent matrix.
---@return table result { nodesAffected, knockedDown, intensityRemoved, hazards }
exports('ExtinguishAt', function(coords, radius, agent, opts)
    if type(coords) ~= 'table' then return { nodesAffected = 0 } end
    return MIFire.Fire.applyAgent(coords, tonumber(radius) or 5.0,
        agent or Enums.Agent.WATER, opts)
end)

--- How effective an agent is against a class, and what it risks. Lets another resource
--- ask before doing something stupid, rather than finding out.
---@return table { effectiveness, hazard, note, counterproductive }
exports('GetAgentEffect', function(agent, className)
    local entry = MIFire.Suppression.lookup(agent, className)
    if not entry then return nil end
    return {
        effectiveness = entry.effectiveness,
        hazard = entry.hazard,
        note = entry.note,
        counterproductive = (tonumber(entry.effectiveness) or 0) < 0,
    }
end)

exports('GetFireClasses', function()
    return MIFire.FireClass.names()
end)

exports('GetWind', function()
    return MIFire.Spread.getWind()
end)

--- Nodes within a radius, for anything that needs to reason about a scene.
exports('GetFiresInRadius', function(coords, radius)
    if type(coords) ~= 'table' then return {} end
    local radiusSq = (tonumber(radius) or 10.0) ^ 2
    local out = {}

    for _, node in pairs(State.getNodes()) do
        if Util.distance3dSq(coords.x, coords.y, coords.z,
            node.coords.x, node.coords.y, node.coords.z) <= radiusSq then
            out[#out + 1] = fireRow(node)
        end
    end

    return out
end)
