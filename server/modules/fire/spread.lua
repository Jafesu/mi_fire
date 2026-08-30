--- Propagation.
---
--- Separate from the lifecycle in `init.lua` because spreading is where a fire stops
--- being a timer and starts being a scene. Keeping it apart makes it possible to change
--- how fire moves without touching how it burns.
---
--- Spread is server-side and blind to geometry: there is no collision data on the server,
--- so a node cannot know a wall is in the way. What it can do is refuse to spread on top
--- of an existing node and respect per-class caps, which is enough to keep a scene
--- coherent. Ground and interior validation happens on a client during generation
--- (`GEN-002`), not here.

MIFire = MIFire or {}

local Spread = {}

local Enums = MIFire.Enums
local Util = MIFire.Util
local State = MIFire.State

--- Wind. One vector for the whole map, drifting slowly, because a wildland fire that
--- runs in a consistent direction reads as weather and one that jitters reads as noise.
local wind = {
    heading = math.random() * math.pi * 2,
    speed = 0.5,
    nextChangeAt = 0,
}

--- Nudge the wind occasionally rather than every tick.
local function updateWind()
    local now = os.time()
    if now < wind.nextChangeAt then return end

    wind.nextChangeAt = now + math.random(45, 120)
    -- Small turns. A wind that swings ninety degrees between gusts is not weather.
    wind.heading = wind.heading + Util.randomFloat(-0.6, 0.6)
    wind.speed = Util.clamp(wind.speed + Util.randomFloat(-0.25, 0.25), 0.0, 1.0)
end

--- Current wind, for the client and for anything that wants to reason about it.
---@return table { heading, speed }
function Spread.getWind()
    return { heading = wind.heading, speed = wind.speed }
end

---@param heading number Radians.
---@param speed number 0-1
function Spread.setWind(heading, speed)
    wind.heading = tonumber(heading) or wind.heading
    wind.speed = Util.clamp(tonumber(speed) or wind.speed, 0.0, 1.0)
    wind.nextChangeAt = os.time() + 300
end

-- ---------------------------------------------------------------------------

--- Is there already a node close enough that another would just be a brighter patch?
---@param incidentId string
---@param coords table
---@param minimumGap number
---@return boolean
local function occupied(incidentId, coords, minimumGap)
    local gapSq = minimumGap * minimumGap
    for _, node in ipairs(State.getNodesForIncident(incidentId)) do
        if Util.distance3dSq(coords.x, coords.y, coords.z,
            node.coords.x, node.coords.y, node.coords.z) <= gapSq then
            return true
        end
    end
    return false
end

--- Pick where a node spreads to.
---
--- Direction is uniformly random for most classes and biased downwind for wildland, which
--- is the class where wind is the story rather than decoration. `windInfluence` blends
--- between the two, so a class can be partly wind-driven.
---@param node table
---@param class table
---@return table coords
local function spreadTarget(node, class)
    local influence = tonumber(class.windInfluence) or 0.0
    local heading

    if influence > 0 then
        -- Blend a random heading toward the wind. At influence 1 the spread is tightly
        -- downwind; at 0 it is uniform.
        local randomHeading = Util.randomFloat(0, math.pi * 2)
        local spreadArc = (1.0 - influence) * math.pi
        heading = wind.heading + Util.randomFloat(-spreadArc, spreadArc)
        heading = heading * influence + randomHeading * (1.0 - influence)
    else
        heading = Util.randomFloat(0, math.pi * 2)
    end

    -- Wind carries fire further as well as steering it.
    local reach = class.spreadRadius * (1.0 + influence * wind.speed * 0.8)
    local distance = Util.randomFloat(reach * 0.5, reach)

    return {
        x = node.coords.x + math.cos(heading) * distance,
        y = node.coords.y + math.sin(heading) * distance,
        z = node.coords.z,
    }
end

--- Try to spread one node.
---@param node table
---@param markDirty function
---@return boolean spread
local function trySpread(node, markDirty)
    local class = node.resolved
    if not class.canSpread then return false end

    -- Only a developed fire throws off new nodes. A knocked-down or barely-lit node has
    -- no business starting another one.
    if node.state ~= Enums.NodeState.GROWING and node.state ~= Enums.NodeState.STEADY then
        return false
    end
    if node.intensity < class.ignitionIntensity then return false end

    local now = os.time()
    if now - (node.lastSpreadAt or 0) < class.spreadIntervalSeconds then return false end

    node.lastSpreadAt = now

    if State.countNodesForIncident(node.incidentId) >= class.spreadMaxNodes then
        return false
    end

    -- Chance scales with how hard the node is burning, so a fire that is being held down
    -- spreads more slowly even before it is knocked out.
    local chance = class.spreadChance * (node.intensity / class.maxIntensity)
    if not Util.chance(chance) then return false end

    local target = spreadTarget(node, class)

    -- Do not stack nodes on top of each other. Half the spread radius keeps a scene
    -- looking like a fire rather than a pile.
    if occupied(node.incidentId, target, class.spreadRadius * 0.5) then return false end

    local newId = MIFire.Fire.addNode(node.incidentId, target, node.class, {
        generation = node.generation + 1,
        interiorId = node.interiorId,
        variant = node.variant,
        -- A new node starts small and grows, so spread reads as creeping rather than
        -- as fires popping into existence fully formed.
        intensity = class.ignitionIntensity * 0.5,
    })

    if newId then
        Util.debug('fire', '%s spread to %s (gen %d)', node.id, newId, node.generation + 1)
        markDirty(node)
        return true
    end

    return false
end

-- ---------------------------------------------------------------------------

--- Advance propagation for every node.
---@param _dt number
---@param markDirty function
function Spread.tick(_dt, markDirty)
    updateWind()

    -- Snapshot the node list first. `trySpread` adds nodes, and mutating the table being
    -- iterated is how a spread turns into an infinite loop.
    local nodes = {}
    for _, node in pairs(State.getNodes()) do nodes[#nodes + 1] = node end

    for i = 1, #nodes do
        -- Re-check existence: a node can burn out inside this same tick.
        if State.getNode(nodes[i].id) then
            trySpread(nodes[i], markDirty)
        end
    end
end

MIFire.Spread = Spread

return Spread
