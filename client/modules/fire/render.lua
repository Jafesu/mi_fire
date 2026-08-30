--- Fire visuals.
---
--- Split out of `init.lua` because rendering is where the first version failed silently and
--- it deserves to be readable on its own.
---
--- Two layers of visual, for different reasons:
---
---   **Particles** are the fire. Layered -- a flame effect plus a smoke plume, since one
---   effect on its own does not read as a fire. Fully controlled: scale follows intensity,
---   so a crew can see the water working.
---
---   **A native script fire** underneath, purely for light. Particles cast none, and a
---   night-time fire that lights nothing looks wrong in a way no amount of particle tuning
---   fixes. GTA owns the light and the heat haze; mi_fire still owns whether the fire
---   exists at all.
---
--- The failure mode to know about: `StartParticleFxLoopedAtCoord` with a dictionary or
--- effect name that does not exist returns 0 and prints nothing. No fire, no error. That is
--- how this shipped looking broken, which is why `/fire render` exists below.

MIFire = MIFire or {}

local Render = {}

local Util = MIFire.Util

---@type table<string, table> Live visuals, keyed by node id.
local live = {}

local assetState = {}   ---@type table<string, boolean|string> true, false, or 'pending'

--- GTA will not hold many script fires at once. Past this, particles carry on alone rather
--- than silently failing or evicting someone else's fire.
local SCRIPT_FIRE_BUDGET = 40
local scriptFireCount = 0

-- ---------------------------------------------------------------------------
-- Assets
-- ---------------------------------------------------------------------------

--- Load a particle dictionary, remembering failures so a bad name is not retried every
--- half second for the life of the session.
---@param dict string
---@return boolean
local function ensureAsset(dict)
    local state = assetState[dict]
    if state == true then return true end
    if state == false then return false end

    if HasNamedPtfxAssetLoaded(dict) then
        assetState[dict] = true
        return true
    end

    RequestNamedPtfxAsset(dict)

    local deadline = GetGameTimer() + 5000
    while not HasNamedPtfxAssetLoaded(dict) do
        if GetGameTimer() > deadline then
            assetState[dict] = false
            Util.warn('particle dictionary "%s" would not load; effects using it are disabled', dict)
            return false
        end
        Wait(0)
    end

    assetState[dict] = true
    return true
end

-- ---------------------------------------------------------------------------
-- Scale
-- ---------------------------------------------------------------------------

--- Particle scale for a node.
---
--- Intensity drives size, so a fire visibly grows as it develops and visibly shrinks as a
--- crew knocks it down. That is the main feedback a firefighter gets that the water is
--- doing anything, so it is worth more than it looks.
---@param node table
---@param layerScale number
---@return number
local function scaleFor(node, layerScale)
    local intensity = Util.clamp(node.intensity or 0, 0, 100)
    return (0.4 + (intensity / 100.0) * 1.0) * (node.scale or 1.0) * (layerScale or 1.0)
end

-- ---------------------------------------------------------------------------
-- Starting and stopping
-- ---------------------------------------------------------------------------

--- The resolved class visuals for a node, merged the same way the server merges them.
---@param node table
---@return table|nil
local function visualsFor(node)
    local class = MIFireClasses.classes[node.class]
    local base = MIFireClasses.base or {}
    if not class then return base end

    return {
        ptfx = class.ptfx or base.ptfx,
        scriptFire = class.scriptFire ~= nil and class.scriptFire or base.scriptFire,
    }
end

---@param node table
function Render.start(node)
    if live[node.id] then return end

    local visuals = visualsFor(node)
    if not visuals or type(visuals.ptfx) ~= 'table' then return end

    local entry = { layers = {}, scriptFire = nil, intensity = node.intensity or 0 }

    for i = 1, #visuals.ptfx do
        local layer = visuals.ptfx[i]

        if ensureAsset(layer.dict) then
            local scale = scaleFor(node, layer.scale)

            UseParticleFxAssetNextCall(layer.dict)
            local handle = StartParticleFxLoopedAtCoord(
                layer.name,
                node.coords.x, node.coords.y, node.coords.z + (layer.z or 0.0),
                0.0, 0.0, 0.0,
                scale,
                false, false, false, false)

            -- 0 means the effect name is not in that dictionary. The native does not say so.
            if handle and handle ~= 0 and handle ~= -1 then
                entry.layers[#entry.layers + 1] = { handle = handle, scale = scale, cfg = layer }
                MIFire.trackPtfx(handle)
            else
                Util.warn('particle "%s" is not in dictionary "%s"; nothing will draw for it',
                    tostring(layer.name), tostring(layer.dict))
            end
        end
    end

    -- Light. Not the fire itself -- if this fails, the fire is still there and still works.
    if visuals.scriptFire and scriptFireCount < SCRIPT_FIRE_BUDGET then
        local fire = StartScriptFire(node.coords.x, node.coords.y, node.coords.z, 25, false)
        if fire and fire ~= 0 then
            entry.scriptFire = fire
            scriptFireCount = scriptFireCount + 1
        end
    end

    if #entry.layers > 0 or entry.scriptFire then
        live[node.id] = entry
    end
end

---@param nodeId string
function Render.stop(nodeId)
    local entry = live[nodeId]
    if not entry then return end

    for i = 1, #entry.layers do
        local handle = entry.layers[i].handle
        if DoesParticleFxLoopedExist(handle) then
            StopParticleFxLooped(handle, false)
        end
    end

    if entry.scriptFire then
        RemoveScriptFire(entry.scriptFire)
        scriptFireCount = math.max(0, scriptFireCount - 1)
    end

    live[nodeId] = nil
end

--- Follow a node's intensity.
---@param node table
function Render.update(node)
    local entry = live[node.id]
    if not entry then return end

    -- Only touch the natives when the change would be visible. Setting scale every tick for
    -- every node is how a fireground becomes a frame rate problem.
    if math.abs((node.intensity or 0) - entry.intensity) < 3.0 then return end
    entry.intensity = node.intensity or 0

    for i = 1, #entry.layers do
        local layer = entry.layers[i]
        local scale = scaleFor(node, layer.cfg.scale)

        if DoesParticleFxLoopedExist(layer.handle) then
            SetParticleFxLoopedScale(layer.handle, scale)
            layer.scale = scale
        end
    end
end

function Render.stopAll()
    for nodeId in pairs(live) do Render.stop(nodeId) end
    live = {}
    scriptFireCount = 0
end

---@param nodeId string
---@return boolean
function Render.isLive(nodeId)
    return live[nodeId] ~= nil
end

-- ---------------------------------------------------------------------------
-- Diagnostics
-- ---------------------------------------------------------------------------

--- What the client actually knows and is actually drawing.
---
--- This exists because "I ran the command and nothing happened" was impossible to diagnose
--- from the outside: the server said it started a fire, and it had. Being able to see
--- whether the client received the node, whether the dictionary loaded, and whether the
--- effect handle came back non-zero separates three completely different bugs.
---@param nodes table<string, table> The client's node mirror.
---@return string[]
function Render.diagnose(nodes)
    local lines = {}
    local nodeCount, renderCount = 0, 0

    for _ in pairs(nodes) do nodeCount = nodeCount + 1 end
    for _ in pairs(live) do renderCount = renderCount + 1 end

    lines[#lines + 1] = ('nodes known to this client: %d'):format(nodeCount)
    lines[#lines + 1] = ('nodes currently rendering: %d'):format(renderCount)
    lines[#lines + 1] = ('script fires: %d of %d'):format(scriptFireCount, SCRIPT_FIRE_BUDGET)
    lines[#lines + 1] = ('render distance: %.0fm'):format(Config.renderDistance)

    if nodeCount == 0 then
        lines[#lines + 1] = 'no nodes: the client never received them. Server-side or sync problem.'
        return lines
    end

    local playerCoords = GetEntityCoords(cache.ped)

    for nodeId, node in pairs(nodes) do
        local distance = #(playerCoords - vec3(node.coords.x, node.coords.y, node.coords.z))
        local entry = live[nodeId]

        lines[#lines + 1] = ('%s  class %s  intensity %.0f  %.0fm  %s'):format(
            nodeId, node.class or '?', node.intensity or 0, distance,
            entry and ('drawing %d layer(s)'):format(#entry.layers)
                or (distance > Config.renderDistance and 'out of range' or 'NOT DRAWING'))
    end

    for dict, state in pairs(assetState) do
        lines[#lines + 1] = ('dictionary %s: %s'):format(dict,
            state == true and 'loaded' or 'FAILED TO LOAD')
    end

    return lines
end

MIFire.Render = Render

return Render
