--- Apparatus, client side: which rig is this, and where are its ports?
---
--- Exists so an interaction can be at the *compartment* rather than anywhere on a twelve
--- metre truck. Third-eyeing the front bumper to get your turnout out of a locker behind the
--- rear wheel is the kind of thing that reads as a script rather than as a fire truck.

MIFire = MIFire or {}

local ApparatusClient = {}

local Apparatus = MIFire.Apparatus

--- Resolved profiles, keyed by model hash. Built lazily: most vehicles a client sees are not
--- apparatus, and resolving every profile on join to answer a question nobody asked is waste.
---@type table<number, table|false>
local cache_ = {}

--- The profile for a vehicle, or nil.
---@param entity integer
---@return table|nil
function ApparatusClient.profile(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end

    local model = GetEntityModel(entity)
    local cached = cache_[model]

    if cached ~= nil then return cached or nil end

    local name = GetDisplayNameFromVehicleModel(model)
    local profile = name and MIFireApparatus.profiles[name:lower()]

    if profile then
        cache_[model] = Apparatus.resolve(profile, MIFireApparatus.defaults)
    elseif MIFireApparatus.allowUnprofiled and GetVehicleClass(entity) == 18 then
        cache_[model] = Apparatus.resolve(MIFireApparatus.unprofiled, MIFireApparatus.defaults)
    else
        cache_[model] = false
    end

    return cache_[model] or nil
end

---@param entity integer
---@return boolean
function ApparatusClient.isApparatus(entity)
    return ApparatusClient.profile(entity) ~= nil
end

--- Where a port actually is, in the world.
---@param entity integer
---@param port table
---@return vector3
function ApparatusClient.portCoords(entity, port)
    if Apparatus.anchor(port) == 'bone' then
        local index = GetEntityBoneIndexByName(entity, port.bone)

        if index and index ~= -1 then
            local world = GetWorldPositionOfEntityBone(entity, index)

            -- The offsets on a bone-anchored port are a nudge from the bone, expressed in
            -- vehicle space rather than bone space -- which is what the offset finder writes
            -- and what a person nudging one would expect.
            if (port.x or 0) ~= 0 or (port.y or 0) ~= 0 or (port.z or 0) ~= 0 then
                local base = GetOffsetFromEntityGivenWorldCoords(entity, world.x, world.y, world.z)
                return GetOffsetFromEntityInWorldCoords(entity,
                    base.x + port.x, base.y + port.y, base.z + port.z)
            end

            return world
        end
        -- Bone is missing on this model. Fall through to the offset, which is zero unless
        -- someone nudged it -- better than returning nothing and hiding the interaction.
    end

    return GetOffsetFromEntityInWorldCoords(entity, port.x or 0.0, port.y or 0.0, port.z or 0.0)
end

---@param entity integer
---@param portType string
---@return table[]
function ApparatusClient.ports(entity, portType)
    local profile = ApparatusClient.profile(entity)
    if not profile then return {} end

    return Apparatus.portsOfType(profile, portType)
end

--- Is the player targeting at or near a port of this type?
---
--- The important half is the fallback: a rig with **no** port of this type authored yet
--- answers true anywhere on the vehicle. A server that has not run `/fireoffset` on its fleet
--- still works exactly as it did before, and authoring ports tightens the interaction rather
--- than being the thing that makes it exist. Nobody should have to author a truck before they
--- can get a coat out of it.
---@param entity integer
---@param coords vector3|nil Where the player is aiming, from ox_target.
---@param portType string
---@param radius number|nil
---@return boolean
function ApparatusClient.atPort(entity, coords, portType, radius)
    local ports = ApparatusClient.ports(entity, portType)

    if #ports == 0 then return true end
    if not coords then return true end

    local reach = radius or 1.3

    for i = 1, #ports do
        local world = ApparatusClient.portCoords(entity, ports[i])

        if #(coords - world) <= reach then return true end
    end

    return false
end

--- The nearest port of a type, for anything that needs the position rather than a yes or no.
---@param entity integer
---@param portType string
---@param from vector3|nil Defaults to the player.
---@return table|nil port
---@return vector3|nil coords
function ApparatusClient.nearestPort(entity, portType, from)
    local ports = ApparatusClient.ports(entity, portType)
    if #ports == 0 then return nil end

    from = from or GetEntityCoords(cache.ped)

    local bestPort, bestCoords, bestDist

    for i = 1, #ports do
        local world = ApparatusClient.portCoords(entity, ports[i])
        local distance = #(from - world)

        if not bestDist or distance < bestDist then
            bestPort, bestCoords, bestDist = ports[i], world, distance
        end
    end

    return bestPort, bestCoords
end

--- A config change should not need a restart to be seen.
AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    cache_ = {}
end)

exports('GetApparatusProfile', function(entity) return ApparatusClient.profile(entity) end)
exports('GetApparatusPorts', function(entity, portType)
    return ApparatusClient.ports(entity, portType)
end)

MIFire.ApparatusClient = ApparatusClient

return ApparatusClient
