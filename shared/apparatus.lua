--- Resolving apparatus profiles and their ports.
---
--- Pure: no natives, so profile lookup and port validation can be tested without spawning a
--- truck. The model hash is passed in rather than looked up here, which is the only thing
--- that would have needed the game.

MIFire = MIFire or {}

local Apparatus = {}

--- Merge a profile onto the defaults.
---
--- Not a deep merge: `ports` is an array and merging arrays by index is how a five-entry list
--- gets four stale entries left on the end of it. Ports replace wholesale.
---@param profile table
---@param defaults table
---@return table
function Apparatus.resolve(profile, defaults)
    local out = {}

    for key, value in pairs(defaults or {}) do
        out[key] = value
    end

    for key, value in pairs(profile or {}) do
        out[key] = value
    end

    out.ports = profile and profile.ports or {}

    return out
end

--- Every port of a given type.
---@param profile table A resolved profile.
---@param portType string
---@return table[]
function Apparatus.portsOfType(profile, portType)
    local found = {}

    for _, port in ipairs(profile.ports or {}) do
        if port.type == portType then found[#found + 1] = port end
    end

    return found
end

--- One port by id.
---@param profile table
---@param portId string
---@return table|nil
function Apparatus.port(profile, portId)
    for _, port in ipairs(profile.ports or {}) do
        if port.id == portId then return port end
    end

    return nil
end

--- Can this rig pump at all?
---
--- A heavy rescue carries no pump, and offering a pump panel on one is how a player learns
--- the resource does not know what the trucks are.
---@param profile table
---@return boolean
function Apparatus.hasPump(profile)
    return (tonumber(profile.pumpRatingGpm) or 0) > 0
end

--- Check one port for the things that are wrong regardless of context.
---@param port table
---@param portTypes table `MIFireApparatus.portTypes`
---@param index integer For the message.
---@return string|nil error
function Apparatus.validatePort(port, portTypes, index)
    if type(port) ~= 'table' then
        return ('port %d is not a table'):format(index)
    end

    if type(port.id) ~= 'string' or port.id == '' then
        return ('port %d has no id'):format(index)
    end

    if not portTypes[port.type] then
        return ('port "%s" has type "%s", which is not a known port type')
            :format(port.id, tostring(port.type))
    end

    for _, axis in ipairs({ 'x', 'y', 'z' }) do
        if type(port[axis]) ~= 'number' then
            return ('port "%s" has no %s offset'):format(port.id, axis)
        end
    end

    -- An offset this far from the vehicle origin is not a port on the truck, it is a typo or
    -- a world coordinate pasted in by mistake. Both are worth catching at boot rather than
    -- discovering when a hose connects to a point in the sky.
    local reach = 20.0
    if math.abs(port.x) > reach or math.abs(port.y) > reach or math.abs(port.z) > reach then
        return ('port "%s" is %.1fm from the vehicle origin -- offsets are local to the '
            .. 'vehicle, in metres. A world coordinate pasted here would look exactly like '
            .. 'this.'):format(port.id, math.max(math.abs(port.x), math.abs(port.y),
                math.abs(port.z)))
    end

    return nil
end

--- Check a whole profile.
---@param profile table
---@param portTypes table
---@return string[] errors
function Apparatus.validate(profile, portTypes)
    local errors = {}
    local seen = {}

    for index, port in ipairs(profile.ports or {}) do
        local err = Apparatus.validatePort(port, portTypes, index)

        if err then
            errors[#errors + 1] = err
        elseif seen[port.id] then
            -- Duplicate ids are worse than they look: the pump panel binds controls by id, so
            -- two ports sharing one means a valve that opens the wrong outlet.
            errors[#errors + 1] = ('port id "%s" is used more than once'):format(port.id)
        else
            seen[port.id] = true
        end
    end

    if (tonumber(profile.tankGallons) or 0) < 0 then
        errors[#errors + 1] = 'tankGallons is negative'
    end

    if (tonumber(profile.maxDischargePsi) or 0) < 0 then
        errors[#errors + 1] = 'maxDischargePsi is negative'
    end

    return errors
end

--- Render one port as the config line `/fireoffset` should paste.
---
--- Lives here rather than in the finder so the format is one thing rather than two that drift,
--- and so it can be tested without the game.
---@param port table
---@return string
function Apparatus.format(port)
    return ('        { id = %q, type = %q, x = %.3f, y = %.3f, z = %.3f, heading = %.1f },')
        :format(port.id, port.type, port.x, port.y, port.z, port.heading or 0.0)
end

MIFire.Apparatus = Apparatus

return Apparatus
