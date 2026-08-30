--- Fire rendering.
---
--- Mirrors the server's node list and draws what is close enough to matter. This file
--- decides nothing: intensity, state, and lifetime all arrive from the server. If a fire
--- looks wrong here, the fix is almost always on the other side.
---
--- Particles rather than `StartScriptFire`. Script fires are capped at a few dozen per
--- session, spread on their own schedule, and cannot be told how big to be -- all three
--- of which fight a server-authoritative model. Particles cost more to manage and give
--- complete control, and the cleanup burden is why `client/main.lua` tracks handles.

MIFire = MIFire or {}

local FireRender = {}

local Util = MIFire.Util

---@type table<string, table>
local nodes = {}

---@type table<string, table> Live particle handles, keyed by node id.
local effects = {}

local assetsLoaded = {}

-- ---------------------------------------------------------------------------
-- Assets
-- ---------------------------------------------------------------------------

---@param asset string
---@return boolean
local function ensureAsset(asset)
    if assetsLoaded[asset] then return true end

    if not HasNamedPtfxAssetLoaded(asset) then
        RequestNamedPtfxAsset(asset)

        local deadline = GetGameTimer() + 5000
        while not HasNamedPtfxAssetLoaded(asset) do
            if GetGameTimer() > deadline then
                Util.warn('particle asset "%s" would not load', asset)
                return false
            end
            Wait(0)
        end
    end

    assetsLoaded[asset] = true
    return true
end

-- ---------------------------------------------------------------------------
-- Effects
-- ---------------------------------------------------------------------------

--- Particle scale for a node. Intensity drives size, so a fire visibly grows as it
--- develops and visibly shrinks as a crew knocks it down -- which is the main feedback a
--- firefighter gets that the water is working.
---@param node table
---@return number
local function scaleFor(node)
    local intensity = Util.clamp(node.intensity or 0, 0, 100)
    return (0.35 + (intensity / 100.0) * 0.9) * (node.scale or 1.0)
end

---@param node table
local function startEffect(node)
    local classConfig = MIFireClasses.classes[node.class] or {}
    local base = MIFireClasses.base or {}

    local asset = classConfig.ptfxAsset or base.ptfxAsset
    local name = classConfig.ptfxName or base.ptfxName
    if not asset or not name then return end
    if not ensureAsset(asset) then return end

    UseParticleFxAssetNextCall(asset)

    local handle = StartParticleFxLoopedAtCoord(
        name,
        node.coords.x, node.coords.y, node.coords.z,
        0.0, 0.0, 0.0,
        scaleFor(node),
        false, false, false, false)

    if handle and handle ~= 0 then
        effects[node.id] = { handle = handle, scale = scaleFor(node) }
        MIFire.trackPtfx(handle)
    end
end

---@param nodeId string
local function stopEffect(nodeId)
    local effect = effects[nodeId]
    if not effect then return end

    if DoesParticleFxLoopedExist(effect.handle) then
        StopParticleFxLooped(effect.handle, false)
    end

    effects[nodeId] = nil
end

---@param node table
local function updateEffect(node)
    local effect = effects[node.id]
    if not effect then return end

    local scale = scaleFor(node)

    -- Only touch the native when the change would be visible. Setting evolution every
    -- frame for every node is how a fireground turns into a frame-rate problem.
    if math.abs(scale - effect.scale) < 0.05 then return end

    if DoesParticleFxLoopedExist(effect.handle) then
        SetParticleFxLoopedScale(effect.handle, scale)
        effect.scale = scale
    end
end

-- ---------------------------------------------------------------------------
-- Sync
-- ---------------------------------------------------------------------------

---@param row table
local function upsert(row)
    local existing = nodes[row.id]
    nodes[row.id] = row

    if existing and effects[row.id] then
        updateEffect(row)
    end
end

---@param nodeId string
local function drop(nodeId)
    nodes[nodeId] = nil
    stopEffect(nodeId)
end

RegisterNetEvent('mi_fire:client:sync', function(updates, removals)
    if updates then
        for i = 1, #updates do upsert(updates[i]) end
    end

    if removals then
        for i = 1, #removals do drop(removals[i]) end
    end
end)

RegisterNetEvent('mi_fire:client:snapshot', function(snapshot)
    for nodeId in pairs(nodes) do drop(nodeId) end
    if not snapshot then return end
    for i = 1, #snapshot do upsert(snapshot[i]) end
end)

RegisterNetEvent('mi_fire:client:teardown', function()
    for nodeId in pairs(nodes) do stopEffect(nodeId) end
    nodes = {}
    effects = {}
end)

-- ---------------------------------------------------------------------------
-- Render loop
-- ---------------------------------------------------------------------------

--- Start and stop effects based on distance, so a fire on the far side of the map costs
--- a table entry rather than a particle system.
CreateThread(function()
    while true do
        Wait(500)

        if MIFire.ready and next(nodes) ~= nil then
            local playerCoords = GetEntityCoords(cache.ped)
            local renderSq = Config.renderDistance * Config.renderDistance

            for nodeId, node in pairs(nodes) do
                local distSq = Util.distance3dSq(
                    playerCoords.x, playerCoords.y, playerCoords.z,
                    node.coords.x, node.coords.y, node.coords.z)

                local shouldRender = distSq <= renderSq
                    and node.live ~= false
                    and (node.intensity or 0) > 0

                if shouldRender and not effects[nodeId] then
                    startEffect(node)
                elseif not shouldRender and effects[nodeId] then
                    stopEffect(nodeId)
                elseif shouldRender then
                    updateEffect(node)
                end
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Hazards
-- ---------------------------------------------------------------------------

--- The visible half of doing the wrong thing. Damage is applied here because the client
--- owns its own ped, but whether the hazard fired at all was decided server side.
RegisterNetEvent('mi_fire:client:hazard', function(data)
    if type(data) ~= 'table' or type(data.coords) ~= 'table' then return end

    local playerCoords = GetEntityCoords(cache.ped)
    local distance = #(playerCoords - vec3(data.coords.x, data.coords.y, data.coords.z))
    local radius = data.radius or 5.0

    if distance > radius then return end

    -- Closer hurts more.
    local falloff = 1.0 - (distance / radius)

    if data.damage and data.damage > 0 then
        local damage = data.damage * falloff

        -- Whoever was holding the nozzle takes the full hit; anyone else on the line
        -- takes the reduced share.
        if data.backupDamageFraction and data.source and data.source ~= GetPlayerServerId(PlayerId()) then
            damage = damage * data.backupDamageFraction
        end

        local health = GetEntityHealth(cache.ped)
        SetEntityHealth(cache.ped, math.max(0, math.floor(health - damage)))
    end

    if data.ragdollMs and data.ragdollMs > 0 then
        SetPedToRagdoll(cache.ped, data.ragdollMs, data.ragdollMs, 0, false, false, false)
    end

    if data.cameraShake then
        ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', data.cameraShake * falloff)
    end

    if data.notify and lib and lib.notify then
        lib.notify({ description = data.notify, type = 'error' })
    end
end)

-- ---------------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------------

--- Every live node this client knows about, in the shape consumers expect.
---@return table[]
local function getAllFires()
    local out = {}
    for _, node in pairs(nodes) do
        out[#out + 1] = {
            id = node.id,
            coords = vec3(node.coords.x, node.coords.y, node.coords.z),
            incidentId = node.incidentId,
            sourceIncidentId = node.incidentId,
            type = node.interiorId and 'indoors' or 'outdoors',
            active = true,
            live = node.live ~= false,
            pendingSeed = false,
            strength = node.intensity,
            isDead = node.live == false,
            generation = node.generation or 0,
        }
    end
    return out
end

exports('GetAllFires', getAllFires)

exports('IsFireNearby', function(radius)
    radius = tonumber(radius) or 20.0
    local playerCoords = GetEntityCoords(cache.ped)
    local radiusSq = radius * radius
    local nearest

    for _, node in pairs(nodes) do
        if node.live ~= false then
            local distSq = Util.distance3dSq(
                playerCoords.x, playerCoords.y, playerCoords.z,
                node.coords.x, node.coords.y, node.coords.z)
            if distSq <= radiusSq and (not nearest or distSq < nearest) then
                nearest = distSq
            end
        end
    end

    if not nearest then return false end
    return true, math.sqrt(nearest)
end)

exports('IsFireStillActive', function(incidentId)
    if incidentId == nil then return false end
    local key = tostring(incidentId)
    for _, node in pairs(nodes) do
        if tostring(node.incidentId) == key and node.live ~= false then return true end
    end
    return false
end)

--- No smoke system yet. Returning an empty table is honest and keeps consumers written
--- against the old resource from erroring; see `FIRE-008`.
exports('GetAllSmokes', function() return {} end)

-- ---------------------------------------------------------------------------

CreateThread(function()
    while not MIFire.ready do Wait(250) end
    TriggerServerEvent('mi_fire:server:requestSnapshot')
end)

MIFire.FireRender = FireRender

return FireRender
