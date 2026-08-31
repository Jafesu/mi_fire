--- The fire engine.
---
--- Server-authoritative. Nodes live here, they are advanced here, and clients are told
--- what to draw. A client never asserts that a fire is out.
---
--- The tick is deliberately simple: every node grows, burns fuel, maybe spreads, and
--- eventually runs out. Everything interesting -- classes behaving differently, the wrong
--- agent making things worse, knockdowns that reflash -- comes from configuration acting
--- on that one loop, not from special cases in it.

MIFire = MIFire or {}

local Fire = {}

local Enums = MIFire.Enums
local Util = MIFire.Util
local State = MIFire.State

--- Nodes whose state changed this tick, flushed to clients as one batch.
local dirty = {}
local removed = {}

-- ---------------------------------------------------------------------------
-- Sync
-- ---------------------------------------------------------------------------

--- The client only needs enough to draw and to answer `IsFireNearby`. Sending the whole
--- node would ship fuel pools and timers to every player for no reason.
---@param node table
---@return table
local function wireFormat(node)
    return {
        id = node.id,
        incidentId = node.incidentId,
        coords = node.coords,
        class = node.class,
        intensity = Util.round(node.intensity, 1),
        state = node.state,
        live = node.state ~= Enums.NodeState.OUT
            and node.state ~= Enums.NodeState.OVERHAULED
            and node.intensity > 0,
        interiorId = node.interiorId,
        generation = node.generation,
        scale = node.scale,
    }
end

local function markDirty(node)
    dirty[node.id] = node
end

local function markRemoved(nodeId)
    dirty[nodeId] = nil
    removed[#removed + 1] = nodeId
end

--- Push everything that changed. One event per tick rather than one per node, because a
--- spreading wildland fire changes dozens of nodes in the same tick.
local function flush()
    local updates = nil
    for _, node in pairs(dirty) do
        updates = updates or {}
        updates[#updates + 1] = wireFormat(node)
    end

    if updates or #removed > 0 then
        TriggerClientEvent('mi_fire:client:sync', -1, updates, #removed > 0 and removed or nil)
    end

    dirty = {}
    removed = {}
end

--- Everything a joining client needs to catch up.
---@return table[]
function Fire.snapshot()
    local out = {}
    for _, node in pairs(State.getNodes()) do
        out[#out + 1] = wireFormat(node)
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Nodes
-- ---------------------------------------------------------------------------

--- Add one node to an incident.
---@param incidentId string
---@param coords table { x, y, z }
---@param className string
---@param opts table|nil { intensity, generation, interiorId, variant, scale }
---@return string|nil nodeId
function Fire.addNode(incidentId, coords, className, opts)
    opts = opts or {}

    local incident = State.getIncident(incidentId)
    if not incident then return nil end

    if State.countNodes() >= Config.limits.maxNodesTotal then
        Util.debug('fire', 'node cap reached (%d); refusing to add', Config.limits.maxNodesTotal)
        return nil
    end

    if State.countNodesForIncident(incidentId) >= Config.limits.maxNodesPerIncident then
        return nil
    end

    local class = MIFire.FireClass.resolve(className, opts.variant)
    if not class then
        Util.warn('unknown fire class "%s"', tostring(className))
        return nil
    end

    local node = {
        incidentId = incidentId,
        coords = { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0 },
        class = className,
        variant = opts.variant,
        resolved = class,

        intensity = tonumber(opts.intensity) or class.ignitionIntensity,
        fuel = class.fuel,
        state = Enums.NodeState.IGNITING,

        generation = tonumber(opts.generation) or 0,
        interiorId = opts.interiorId,
        scale = tonumber(opts.scale) or class.scale or 1.0,

        lastSpreadAt = os.time(),
        overhaulProgress = 0.0,
        agentApplied = 0.0,
    }

    local nodeId = State.addNode(node)
    if nodeId then markDirty(node) end
    return nodeId
end

--- Remove a node outright. Used by teardown and admin, not by burning out -- a node that
--- runs out of fuel goes to OUT first so clients can stop drawing it cleanly.
---@param nodeId string
function Fire.removeNode(nodeId)
    if State.removeNode(nodeId) then markRemoved(nodeId) end
end

-- ---------------------------------------------------------------------------
-- Incidents
-- ---------------------------------------------------------------------------

--- Start an incident and seed it with nodes.
---@param spec table
---   coords    table   required
---   class     string  a key from MIFireClasses.classes
---   nodeCount integer|nil
---   radius    number|nil  how far seed nodes scatter
---   origin    string|nil  MIFire.Enums.IncidentOrigin
---   interiorId, floor, district, description, suppressDispatch, variant
---@return string|nil incidentId
---@return string|nil error
function Fire.startIncident(spec)
    spec = spec or {}

    if type(spec.coords) ~= 'table' then return nil, 'NO_COORDS' end

    local className = spec.class or Enums.FireClass.A
    if not MIFire.FireClass.exists(className) then return nil, 'UNKNOWN_CLASS' end

    if State.countIncidents() >= Config.limits.maxIncidents then
        return nil, 'INCIDENT_CAP'
    end

    local incident = {
        coords = { x = spec.coords.x + 0.0, y = spec.coords.y + 0.0, z = spec.coords.z + 0.0 },
        class = className,
        variant = spec.variant,
        origin = spec.origin or Enums.IncidentOrigin.EXPORT,
        state = Enums.IncidentState.ACTIVE,
        interiorId = spec.interiorId,
        floor = spec.floor,
        district = spec.district,
        districtLabel = spec.districtLabel,
        locationLabel = spec.locationLabel,
        description = spec.description,
        suppressDispatch = spec.suppressDispatch == true,
        hydrantDensity = spec.hydrantDensity,
        assignment = spec.assignment,
    }

    local incidentId = State.addIncident(incident)

    local count = math.max(1, math.floor(tonumber(spec.nodeCount) or 1))
    local radius = tonumber(spec.radius) or 0.0
    local seeded = 0

    for i = 1, count do
        local coords = incident.coords

        -- Seed nodes scatter around the origin so a fresh incident is not a single point.
        if radius > 0 and i > 1 then
            local angle = Util.randomFloat(0, math.pi * 2)
            local distance = Util.randomFloat(radius * 0.25, radius)
            coords = {
                x = incident.coords.x + math.cos(angle) * distance,
                y = incident.coords.y + math.sin(angle) * distance,
                z = incident.coords.z,
            }
        end

        if Fire.addNode(incidentId, coords, className, {
            interiorId = spec.interiorId,
            variant = spec.variant,
            scale = spec.scale,
        }) then
            seeded = seeded + 1
        end
    end

    if seeded == 0 then
        State.removeIncident(incidentId)
        return nil, 'NO_NODES_PLACED'
    end

    Util.debug('fire', 'started %s: class=%s nodes=%d origin=%s',
        incidentId, className, seeded, incident.origin)

    flush()
    return incidentId
end

--- Stop an incident and every node under it.
---@param incidentId string
---@return boolean
function Fire.stopIncident(incidentId)
    local incident = State.getIncident(incidentId)
    if not incident then return false end

    for _, node in ipairs(State.getNodesForIncident(incidentId)) do
        markRemoved(node.id)
    end

    State.removeIncident(incidentId)
    Util.debug('fire', 'stopped %s', tostring(incidentId))

    flush()
    return true
end

--- Stop everything. Returns how many incidents were stopped.
---@return integer
function Fire.stopAll()
    local ids = {}
    for id in pairs(State.getIncidents()) do ids[#ids + 1] = id end
    for i = 1, #ids do Fire.stopIncident(ids[i]) end
    return #ids
end

--- A summary of an incident and how it is going, for `/fire info` and for exports.
---@param incidentId string
---@return table|nil
function Fire.describe(incidentId)
    local incident = State.getIncident(incidentId)
    if not incident then return nil end

    local nodes = State.getNodesForIncident(incidentId)
    local live, knockedDown, totalIntensity, totalFuel = 0, 0, 0.0, 0.0

    for i = 1, #nodes do
        local node = nodes[i]
        totalIntensity = totalIntensity + node.intensity
        totalFuel = totalFuel + node.fuel
        if node.state == Enums.NodeState.KNOCKED_DOWN
            or node.state == Enums.NodeState.OVERHAULED then
            knockedDown = knockedDown + 1
        elseif node.intensity > 0 then
            live = live + 1
        end
    end

    return {
        id = incidentId,
        class = incident.class,
        origin = incident.origin,
        state = incident.state,
        coords = incident.coords,
        district = incident.district,
        nodeCount = #nodes,
        liveNodes = live,
        knockedDownNodes = knockedDown,
        averageIntensity = #nodes > 0 and Util.round(totalIntensity / #nodes, 1) or 0,
        fuelRemaining = Util.round(totalFuel, 1),
        createdAt = incident.createdAt,
        ageSeconds = os.time() - (incident.createdAt or os.time()),
    }
end

-- ---------------------------------------------------------------------------
-- Suppression
-- ---------------------------------------------------------------------------

--- Apply an extinguishing agent to everything in a radius.
---
--- This is the one entry point for putting fire out. Hose lines, extinguishers,
--- sprinklers, and the admin command all come through here, so the agent matrix cannot be
--- bypassed by adding a new water source later.
---
---@param coords table Where the agent is being applied from.
---@param radius number Metres.
---@param agentName string
---@param opts table|nil { gpm, seconds, extinguisher, efficiency, source }
---@return table result { nodesAffected, knockedDown, intensityRemoved, hazards }
function Fire.applyAgent(coords, radius, agentName, opts)
    opts = opts or {}

    local seconds = tonumber(opts.seconds) or 1.0
    local gpm = tonumber(opts.gpm) or 0
    local result = { nodesAffected = 0, knockedDown = 0, intensityRemoved = 0.0, hazards = {} }

    if type(coords) ~= 'table' or not agentName then return result end

    local radiusSq = radius * radius

    for _, node in pairs(State.getNodes()) do
        if node.state ~= Enums.NodeState.OUT and node.state ~= Enums.NodeState.OVERHAULED then
            local distSq = Util.distance3dSq(
                coords.x, coords.y, coords.z,
                node.coords.x, node.coords.y, node.coords.z)

            if distSq <= radiusSq then
                local distance = math.sqrt(distSq)

                local rate, effectiveness
                if opts.extinguisher then
                    rate, effectiveness = MIFire.Suppression.extinguisherRate({
                        agent = agentName, class = node.resolved, distance = distance,
                    })
                else
                    rate, effectiveness = MIFire.Suppression.rate({
                        agent = agentName, class = node.resolved,
                        gpm = gpm, distance = distance, efficiency = opts.efficiency,
                    })
                end

                if rate ~= 0 then
                    result.nodesAffected = result.nodesAffected + 1
                    local delta = rate * seconds

                    node.intensity = Util.clamp(node.intensity - delta, 0.0,
                        node.resolved.maxIntensity)
                    node.agentApplied = node.agentApplied + math.abs(delta)
                    result.intensityRemoved = result.intensityRemoved + delta

                    if delta > 0 then
                        -- Correct agent. Sustained application on a knocked-down node is
                        -- overhaul, which is what stops it coming back.
                        if node.state == Enums.NodeState.KNOCKED_DOWN then
                            node.overhaulProgress = node.overhaulProgress + seconds
                            if node.overhaulProgress >= node.resolved.overhaulSeconds then
                                node.state = Enums.NodeState.OVERHAULED
                                node.reflashAt = nil
                            end
                        elseif node.intensity <= 0 then
                            node.state = Enums.NodeState.KNOCKED_DOWN
                            node.knockedDownAt = os.time()
                            node.overhaulProgress = 0.0
                            result.knockedDown = result.knockedDown + 1

                            -- A knockdown that is not overhauled can come back, unless
                            -- the fuel is gone.
                            if node.fuel > 0 and Util.chance(node.resolved.reflashChance) then
                                node.reflashAt = os.time() + node.resolved.reflashDelaySeconds
                            end
                        end
                    else
                        -- Wrong agent. The fire grew; see if the hazard fires too.
                        if node.state == Enums.NodeState.KNOCKED_DOWN then
                            node.state = Enums.NodeState.GROWING
                            node.reflashAt = nil
                        end
                    end

                    markDirty(node)

                    if effectiveness < 0 then
                        local hazardName = Fire.rollHazard(node, agentName, opts.source)
                        if hazardName then
                            result.hazards[#result.hazards + 1] = hazardName
                        end
                    end
                end
            end
        end
    end

    if result.nodesAffected > 0 then flush() end
    return result
end

--- Roll and apply the hazard for an agent used on the wrong class.
---
--- Separate from `applyAgent` so the consequences of a mistake are all in one place and
--- can be read without wading through the suppression loop.
---@param node table
---@param agentName string
---@param source integer|nil The player who did it, for damage and notifications.
---@return string|nil hazardName Nil when nothing fired.
function Fire.rollHazard(node, agentName, source)
    local hazardName, hazard = MIFire.Suppression.hazard(agentName, node.class)
    if not hazardName or not hazard then return nil end
    if not Util.chance(hazard.chancePerTick) then return nil end

    Util.debug('fire', 'hazard %s fired on %s (%s on class %s)',
        hazardName, node.id, agentName, node.class)

    if hazard.intensityBoost then
        node.intensity = Util.clamp(node.intensity + hazard.intensityBoost, 0.0,
            node.resolved.maxIntensity)
        if node.state == Enums.NodeState.KNOCKED_DOWN then
            node.state = Enums.NodeState.GROWING
            node.reflashAt = nil
        end
        markDirty(node)
    end

    if hazard.spawnNodes then
        for _ = 1, hazard.spawnNodes do
            local angle = Util.randomFloat(0, math.pi * 2)
            local distance = Util.randomFloat(1.0, hazard.spawnRadius or 4.0)
            Fire.addNode(node.incidentId, {
                x = node.coords.x + math.cos(angle) * distance,
                y = node.coords.y + math.sin(angle) * distance,
                z = node.coords.z,
            }, node.class, {
                generation = node.generation + 1,
                interiorId = node.interiorId,
                variant = node.variant,
            })
        end
    end

    TriggerClientEvent('mi_fire:client:hazard', -1, {
        hazard = hazardName,
        coords = node.coords,
        radius = hazard.radius,
        damage = hazard.damage,
        ragdollMs = hazard.ragdollMs,
        cameraShake = hazard.cameraShake,
        backupDamageFraction = hazard.backupDamageFraction,
        notify = hazard.notify,
        source = source,
    })

    return hazardName
end

-- ---------------------------------------------------------------------------
-- Tick
-- ---------------------------------------------------------------------------

--- Advance one node by `dt` seconds.
---@param node table
---@param dt number
---@return boolean alive False when the node should be removed.
local function tickNode(node, dt)
    local class = node.resolved
    local now = os.time()

    if node.state == Enums.NodeState.OVERHAULED then
        -- Done. Held briefly so clients can fade it out, then dropped.
        if node.intensity <= 0 then return false end
        node.intensity = math.max(0.0, node.intensity - 20.0 * dt)
        markDirty(node)
        return true
    end

    if node.state == Enums.NodeState.KNOCKED_DOWN then
        if node.reflashAt and now >= node.reflashAt then
            node.state = Enums.NodeState.GROWING
            node.intensity = class.ignitionIntensity * 0.6
            node.reflashAt = nil
            node.overhaulProgress = 0.0
            Util.debug('fire', '%s reflashed', node.id)
            markDirty(node)
        elseif not node.reflashAt then
            -- Knocked down with no reflash pending and nobody overhauling it. Fuel keeps
            -- smouldering away, so it eventually resolves on its own.
            node.fuel = node.fuel - class.fuelBurnPerSecond * 0.25 * dt
            if node.fuel <= 0 then
                node.state = Enums.NodeState.OVERHAULED
                markDirty(node)
            end
        end
        return true
    end

    -- Growing or steady.
    if node.state == Enums.NodeState.IGNITING then
        node.state = Enums.NodeState.GROWING
    end

    local previousIntensity = node.intensity

    if node.intensity < class.maxIntensity then
        node.intensity = math.min(class.maxIntensity,
            node.intensity + class.growthPerSecond * dt)
    end

    -- Fuel burns proportionally to how hard the node is burning, so a fully developed
    -- fire consumes its fuel faster than a smouldering one.
    node.fuel = node.fuel - class.fuelBurnPerSecond * (node.intensity / 100.0) * dt

    if node.fuel <= 0 then
        node.state = Enums.NodeState.OUT
        node.intensity = 0.0
        markDirty(node)
        return false
    end

    if node.intensity >= class.maxIntensity and node.state ~= Enums.NodeState.STEADY then
        node.state = Enums.NodeState.STEADY
    end

    -- The hardest it ever burned, for sizing the scorch it leaves. A fire knocked down and
    -- reflashing should be marked by its worst moment, not by whatever it was doing at the
    -- instant the fuel ran out.
    if node.intensity > (node.peakIntensity or 0) then
        node.peakIntensity = node.intensity
    end

    if math.abs(node.intensity - previousIntensity) >= 0.5 then
        markDirty(node)
    end

    return true
end

--- One simulation step across every node.
---@param dt number Seconds since the last tick.
function Fire.tick(dt)
    local doomed = nil

    for nodeId, node in pairs(State.getNodes()) do
        if not tickNode(node, dt) then
            doomed = doomed or {}
            doomed[#doomed + 1] = nodeId
        end
    end

    MIFire.Spread.tick(dt, markDirty)

    if doomed then
        for i = 1, #doomed do
            local nodeId = doomed[i]
            local node = State.getNode(nodeId)

            -- Leave a mark before the node goes. Done here rather than while it burns
            -- because a decal under an active fire is invisible under the flames and would
            -- have to be resized every tick to follow it.
            if node and MIFire.ScorchServer then
                MIFire.ScorchServer.mark(node.coords,
                    os.time() - (node.createdAt or os.time()),
                    node.peakIntensity or node.intensity or 0)
            end

            State.removeNode(nodeId)
            markRemoved(nodeId)
        end
    end

    -- An incident with nothing left burning is over.
    for incidentId, incident in pairs(State.getIncidents()) do
        if State.countNodesForIncident(incidentId) == 0
            and incident.state ~= Enums.IncidentState.OUT then
            incident.state = Enums.IncidentState.OUT
            Util.debug('fire', '%s is out', incidentId)
            State.removeIncident(incidentId)
        end
    end

    flush()
end

-- ---------------------------------------------------------------------------

CreateThread(function()
    while not MIFire.ready do Wait(250) end

    local interval = math.max(100, Config.tickMs)
    local dt = interval / 1000.0

    while true do
        Wait(interval)
        if MIFire.ready then
            local ok, err = pcall(Fire.tick, dt)
            if not ok then
                Util.warn('fire tick failed: %s', tostring(err))
            end
        end
    end
end)

--- Catch a joining player up on what is already burning.
RegisterNetEvent('mi_fire:server:requestSnapshot', function()
    TriggerClientEvent('mi_fire:client:snapshot', source, Fire.snapshot())
end)

MIFire.Fire = Fire

return Fire
