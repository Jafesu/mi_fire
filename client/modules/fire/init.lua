--- Fire client.
---
--- Mirrors the server's node list and decides what is close enough to draw. Drawing itself
--- is `render.lua`.
---
--- This file decides nothing about the fire: intensity, state, and lifetime all arrive from
--- the server. If a fire behaves wrong, the fix is on the other side. If a fire is
--- *invisible*, the fix is almost certainly in `render.lua` -- run `/fire render` to find
--- out which.

MIFire = MIFire or {}

local FireClient = {}

local Util = MIFire.Util
local Render = MIFire.Render

---@type table<string, table>
local nodes = {}

-- ---------------------------------------------------------------------------
-- Sync
-- ---------------------------------------------------------------------------

---@param row table
local function upsert(row)
    nodes[row.id] = row
    if Render.isLive(row.id) then Render.update(row) end
end

---@param nodeId string
local function drop(nodeId)
    nodes[nodeId] = nil
    Render.stop(nodeId)
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
    Util.debug('render', 'received snapshot of %d node(s)', #snapshot)
end)

RegisterNetEvent('mi_fire:client:teardown', function()
    Render.stopAll()
    nodes = {}
end)

--- Report what this client knows and is drawing. Answered locally rather than round-tripped,
--- since everything interesting is client-side state.
RegisterNetEvent('mi_fire:client:diagnose', function()
    local lines = Render.diagnose(nodes)
    for i = 1, #lines do
        TriggerEvent('chat:addMessage', { args = { 'mi_fire', lines[i] } })
    end
    print('[mi_fire] render diagnosis:')
    for i = 1, #lines do print('  ' .. lines[i]) end
end)

-- ---------------------------------------------------------------------------
-- Render loop
-- ---------------------------------------------------------------------------

--- Start and stop visuals by distance, so a fire on the far side of the map costs a table
--- entry rather than a particle system.
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

                if shouldRender and not Render.isLive(nodeId) then
                    Render.start(node)
                elseif not shouldRender and Render.isLive(nodeId) then
                    Render.stop(nodeId)
                elseif shouldRender then
                    Render.update(node)
                end
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Hazards
-- ---------------------------------------------------------------------------

--- The visible half of using the wrong agent. Damage is applied here because the client
--- owns its own ped, but whether the hazard fired at all was decided server side.
RegisterNetEvent('mi_fire:client:hazard', function(data)
    if type(data) ~= 'table' or type(data.coords) ~= 'table' then return end

    local playerCoords = GetEntityCoords(cache.ped)
    local distance = #(playerCoords - vec3(data.coords.x, data.coords.y, data.coords.z))
    local radius = data.radius or 5.0

    if distance > radius then return end

    local falloff = 1.0 - (distance / radius)

    if data.damage and data.damage > 0 then
        local damage = data.damage * falloff

        -- Whoever was holding the nozzle takes the full hit; anyone else on the line takes
        -- the reduced share.
        if data.backupDamageFraction and data.source
            and data.source ~= GetPlayerServerId(PlayerId()) then
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

--- Every node this client knows about, in the shape consumers expect.
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

MIFire.FireClient = FireClient

return FireClient
