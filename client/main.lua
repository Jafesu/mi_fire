--- Client entry point.
---
--- The client renders and reports. It does not decide whether a fire is out, how much
--- water a tank has, or what pressure a discharge is at -- it asks, and it is told.
---
--- Teardown matters here more than anywhere else in the resource. Ropes, props, PTFX
--- loops, and target zones all survive a resource stop unless something removes them,
--- and the "restart twice" verification step exists because the second restart is where
--- a leak becomes obvious.

MIFire = MIFire or {}
MIFire.ready = false

--- Everything this client created that will not clean itself up.
local owned = {
    props = {},
    ropes = {},
    ptfx = {},
    blips = {},
}

-- ---------------------------------------------------------------------------
-- Ownership tracking
-- ---------------------------------------------------------------------------

---@param entity integer
---@return integer entity
function MIFire.trackProp(entity)
    owned.props[#owned.props + 1] = entity
    return entity
end

---@param rope integer
---@return integer rope
function MIFire.trackRope(rope)
    owned.ropes[#owned.ropes + 1] = rope
    return rope
end

---@param handle integer
---@return integer handle
function MIFire.trackPtfx(handle)
    owned.ptfx[#owned.ptfx + 1] = handle
    return handle
end

---@param blip integer
---@return integer blip
function MIFire.trackBlip(blip)
    owned.blips[#owned.blips + 1] = blip
    return blip
end

-- ---------------------------------------------------------------------------
-- Teardown
-- ---------------------------------------------------------------------------

local function cleanup()
    for i = 1, #owned.ptfx do
        local handle = owned.ptfx[i]
        if DoesParticleFxLoopedExist(handle) then
            StopParticleFxLooped(handle, false)
        end
    end

    for i = 1, #owned.ropes do
        local rope = owned.ropes[i]
        if rope and rope ~= 0 then
            DeleteRope(rope)
        end
    end

    for i = 1, #owned.props do
        local entity = owned.props[i]
        if entity and entity ~= 0 and DoesEntityExist(entity) then
            DeleteEntity(entity)
        end
    end

    for i = 1, #owned.blips do
        local blip = owned.blips[i]
        if blip and DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end

    owned = { props = {}, ropes = {}, ptfx = {}, blips = {} }

    if MIFire.Target then
        MIFire.Target.removeAll()
    end

    RopeUnloadTextures()
end

RegisterNetEvent('mi_fire:client:teardown', function()
    cleanup()
    MIFire.ready = false
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    cleanup()
end)

-- ---------------------------------------------------------------------------
-- Boot
-- ---------------------------------------------------------------------------

CreateThread(function()
    -- ox_lib's cache is used throughout; wait for a ped before anything reads it.
    while not cache or not cache.ped or cache.ped == 0 do
        Wait(100)
    end

    MIFire.ready = true
    MIFire.Util.debug('boot', 'client ready, framework=%s', MIFire.Framework.name)
end)
