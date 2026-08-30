--- Server state.
---
--- The single source of truth for everything live: incidents, nodes, hose lines, pump
--- state, crew slots, gear tiers. Clients render this and request changes to it; they
--- never assert it.
---
--- Modules read and write through the accessors here rather than reaching into the
--- tables, so that adding persistence or a sync hook later is one file's problem.

MIFire = MIFire or {}

local State = {}

local incidents = {}      ---@type table<string, table>
local nodes = {}          ---@type table<string, table>  every node, keyed by node id
local nodesByIncident = {}---@type table<string, table<string, true>>
local gearByPlayer = {}   ---@type table<integer, table>
local scbaByPlayer = {}   ---@type table<integer, table>
local counters = { incident = 0, node = 0 }

-- ---------------------------------------------------------------------------
-- Identity
-- ---------------------------------------------------------------------------

---@param kind string 'incident' or 'node'
---@return string
local function nextId(kind)
    counters[kind] = (counters[kind] or 0) + 1
    return ('%s:%d'):format(kind, counters[kind])
end

State.nextId = nextId

-- ---------------------------------------------------------------------------
-- Incidents
-- ---------------------------------------------------------------------------

---@param incident table
---@return string id
function State.addIncident(incident)
    incident.id = incident.id or nextId('incident')
    incident.createdAt = incident.createdAt or os.time()
    incident.state = incident.state or MIFire.Enums.IncidentState.ACTIVE

    incidents[incident.id] = incident
    nodesByIncident[incident.id] = nodesByIncident[incident.id] or {}

    return incident.id
end

---@param id string
---@return table|nil
function State.getIncident(id)
    if id == nil then return nil end
    return incidents[tostring(id)]
end

---@return table<string, table>
function State.getIncidents()
    return incidents
end

---@return integer
function State.countIncidents()
    return MIFire.Util.count(incidents)
end

--- Remove an incident and every node under it.
---@param id string
---@return boolean removed
function State.removeIncident(id)
    id = tostring(id)
    if not incidents[id] then return false end

    for nodeId in pairs(nodesByIncident[id] or {}) do
        nodes[nodeId] = nil
    end

    nodesByIncident[id] = nil
    incidents[id] = nil
    return true
end

-- ---------------------------------------------------------------------------
-- Nodes
-- ---------------------------------------------------------------------------

---@param node table Must carry `incidentId`.
---@return string|nil id
function State.addNode(node)
    if not node.incidentId or not incidents[node.incidentId] then return nil end

    node.id = node.id or nextId('node')
    node.createdAt = node.createdAt or os.time()
    node.state = node.state or MIFire.Enums.NodeState.IGNITING

    nodes[node.id] = node
    nodesByIncident[node.incidentId] = nodesByIncident[node.incidentId] or {}
    nodesByIncident[node.incidentId][node.id] = true

    return node.id
end

---@param id string
---@return table|nil
function State.getNode(id)
    if id == nil then return nil end
    return nodes[tostring(id)]
end

---@return table<string, table>
function State.getNodes()
    return nodes
end

---@return integer
function State.countNodes()
    return MIFire.Util.count(nodes)
end

--- Every node belonging to an incident, as an array.
---@param incidentId string
---@return table[]
function State.getNodesForIncident(incidentId)
    local out = {}
    for nodeId in pairs(nodesByIncident[tostring(incidentId)] or {}) do
        local node = nodes[nodeId]
        if node then out[#out + 1] = node end
    end
    return out
end

---@param incidentId string
---@return integer
function State.countNodesForIncident(incidentId)
    return MIFire.Util.count(nodesByIncident[tostring(incidentId)] or {})
end

---@param id string
---@return boolean removed
function State.removeNode(id)
    id = tostring(id)
    local node = nodes[id]
    if not node then return false end

    if nodesByIncident[node.incidentId] then
        nodesByIncident[node.incidentId][id] = nil
    end
    nodes[id] = nil

    return true
end

-- ---------------------------------------------------------------------------
-- Protective equipment
-- ---------------------------------------------------------------------------

--- The tier a player is actually wearing, as set by donning at an apparatus.
---
--- This is the only thing the exposure model consults. It is deliberately not derived
--- from the player's clothing -- see `bridge/appearance/illenium.lua`.
---@param source integer
---@return table entry { tier, integrity, donnedAt, storedAppearance }
function State.getGear(source)
    local entry = gearByPlayer[source]
    if not entry then
        entry = { tier = MIFireGear.defaultTier, integrity = 0.0 }
        gearByPlayer[source] = entry
    end
    return entry
end

---@param source integer
---@param tierName string
---@param integrity number|nil
function State.setGear(source, tierName, integrity)
    local tier = MIFireGear.tiers[tierName]
    if not tier then
        MIFire.Util.warn('unknown gear tier %s', tostring(tierName))
        return
    end

    local entry = State.getGear(source)
    entry.tier = tierName
    entry.integrity = integrity or tier.integrity or 0.0
    entry.donnedAt = os.time()
end

---@param source integer
function State.clearGear(source)
    gearByPlayer[source] = nil
end

-- ---------------------------------------------------------------------------
-- SCBA
-- ---------------------------------------------------------------------------

--- Breathing apparatus, kept separate from turnout because they are independent.
---
--- `worn` is having the set on your back. `active` is the valve open and the mask sealed.
--- Only `active` protects, and only `active` burns air -- that distinction is the whole
--- reason there are two appearance sets.
---@param source integer
---@return table entry { worn, active, air, exertion, inSmoke, fromRack }
function State.getScba(source)
    local entry = scbaByPlayer[source]
    if not entry then
        entry = { worn = false, active = false, air = 0.0, exertion = 'idle', inSmoke = false }
        scbaByPlayer[source] = entry
    end
    return entry
end

---@param source integer
---@param entry table
function State.setScba(source, entry)
    local current = State.getScba(source)
    for key, value in pairs(entry) do current[key] = value end
end

---@param source integer
function State.clearScba(source)
    scbaByPlayer[source] = nil
end

--- Is this player protected from smoke right now?
---
--- The single question the exposure model asks. Deliberately one function so there is one
--- place to get it wrong, and so "wearing a set" can never be mistaken for "breathing air".
---@param source integer
---@return boolean
function State.hasAir(source)
    local entry = scbaByPlayer[source]
    return entry ~= nil and entry.worn and entry.active and entry.air > 0
end

--- Resolved tier table for a player, never nil -- falls back to the default tier so
--- the exposure model never has to nil-check mid-calculation.
---@param source integer
---@return table tier
---@return table entry
function State.getGearTier(source)
    local entry = State.getGear(source)
    local tier = MIFireGear.tiers[entry.tier] or MIFireGear.tiers[MIFireGear.defaultTier]
    return tier, entry
end

-- ---------------------------------------------------------------------------
-- Teardown
-- ---------------------------------------------------------------------------

--- Wipe everything. Called on resource stop so a restart starts genuinely clean.
function State.reset()
    incidents = {}
    nodes = {}
    nodesByIncident = {}
    gearByPlayer = {}
    scbaByPlayer = {}
    counters = { incident = 0, node = 0 }
end

AddEventHandler('playerDropped', function()
    gearByPlayer[source] = nil
    scbaByPlayer[source] = nil
end)

MIFire.State = State

return State
