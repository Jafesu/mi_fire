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

--- How does this port work out where it is?
---
--- Two anchors, and the difference matters:
---
---   **bone**    The port hangs off a named bone on the model. Survives the model being
---               updated, moves with anything animated, and needs no measuring -- if the
---               author put a bone at the hookup, that *is* the hookup. `x/y/z` become a
---               fine offset from the bone rather than from the vehicle.
---
---   **offset**  A fixed point in vehicle-local space, measured with `/fireoffset`. Always
---               available, and wrong the moment the model changes.
---
--- Bone is preferred wherever one exists. The catch is that bone names cannot be read from
--- an `RSC7` model, so they have to be discovered in game -- which `/fireoffset` does by
--- enumerating them rather than by anyone guessing.
---@param port table
---@return string 'bone' | 'offset'
function Apparatus.anchor(port)
    if type(port.bone) == 'string' and port.bone ~= '' then return 'bone' end
    return 'offset'
end

--- How big is this port's interaction zone, and what shape?
---
--- Returns a box when one is declared and a radius otherwise, so callers handle two shapes
--- rather than every type of port having to declare one.
---@param port table
---@param reach table `MIFireApparatus.portReach`
---@return table|nil box `{ x, y, z }` half-extents, vehicle-aligned
---@return number radius Used when there is no box.
function Apparatus.reach(port, reach)
    if type(port.size) == 'table' then
        return {
            x = (tonumber(port.size.x) or 1.0) * 0.5,
            y = (tonumber(port.size.y) or 1.0) * 0.5,
            z = (tonumber(port.size.z) or 1.0) * 0.5,
        }, 0.0
    end

    if tonumber(port.radius) then return nil, tonumber(port.radius) end

    return nil, tonumber(reach and reach[port.type]) or tonumber(reach and reach.default) or 1.2
end

--- Is a point inside this port's zone?
---
--- Takes the point already converted to **vehicle-local** space, which is what makes a box
--- work: compartments run along the side of a rig, and a box aligned to the truck stays
--- correct however it is parked. A sphere big enough to cover a long hose bed would also
--- cover half the crew cab.
---@param port table
---@param localPoint table `{ x, y, z }` in vehicle space
---@param reach table `MIFireApparatus.portReach`
---@return boolean
function Apparatus.contains(port, localPoint, reach)
    local box, radius = Apparatus.reach(port, reach)

    local dx = localPoint.x - (port.x or 0.0)
    local dy = localPoint.y - (port.y or 0.0)
    local dz = localPoint.z - (port.z or 0.0)

    if box then
        return math.abs(dx) <= box.x and math.abs(dy) <= box.y and math.abs(dz) <= box.z
    end

    return (dx * dx + dy * dy + dz * dz) <= radius * radius
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

    local bone = Apparatus.anchor(port) == 'bone'

    -- A bone-anchored port needs no coordinates at all; anything it does carry is a fine
    -- offset from the bone and is optional.
    for _, axis in ipairs({ 'x', 'y', 'z' }) do
        if type(port[axis]) ~= 'number' then
            if not bone then
                return ('port "%s" has no %s offset'):format(port.id, axis)
            end
            port[axis] = 0.0
        end
    end

    -- An offset this far from the vehicle origin is not a port on the truck, it is a typo or
    -- a world coordinate pasted in by mistake. Both are worth catching at boot rather than
    -- discovering when a hose connects to a point in the sky.
    -- A bone nudge should be centimetres, not metres. 1.5m allows for a bone at a panel
    -- centre with the port at its edge, and rejects anything that means the wrong bone was
    -- picked -- which is the mistake this catches, since a wrong bone still resolves to a
    -- real point on the truck and looks fine until a hose connects a metre off.
    local reach = bone and 1.5 or 20.0
    if math.abs(port.x) > reach or math.abs(port.y) > reach or math.abs(port.z) > reach then
        local worst = math.max(math.abs(port.x), math.abs(port.y), math.abs(port.z))

        if bone then
            return ('port "%s" is offset %.1fm from bone "%s" -- a bone offset is a nudge, '
                .. 'not a position. If it needs to be that far, the bone is the wrong one.')
                :format(port.id, worst, port.bone)
        end

        return ('port "%s" is %.1fm from the vehicle origin -- offsets are local to the '
            .. 'vehicle, in metres. A world coordinate pasted here would look exactly like '
            .. 'this.'):format(port.id, worst)
    end

    if port.radius ~= nil then
        local r = tonumber(port.radius)

        if not r or r <= 0 then
            return ('port "%s" has a radius of %s'):format(port.id, tostring(port.radius))
        end

        if r > 6.0 then
            return ('port "%s" has a %.1fm radius, which covers most of the rig -- a zone '
                .. 'that large means every port on that side answers at once and the player '
                .. 'picks from a list instead of pointing at one'):format(port.id, r)
        end
    end

    if port.size ~= nil then
        if type(port.size) ~= 'table' then
            -- `size` is also the hose diameter on a discharge, which is a number. That
            -- overload is deliberate and worth being explicit about rather than silently
            -- treating 1.75 as a box.
            if port.type ~= 'discharge' and port.type ~= 'intake' then
                return ('port "%s" has a size that is neither a box nor a hose diameter')
                    :format(port.id)
            end
        else
            for _, axis in ipairs({ 'x', 'y', 'z' }) do
                local value = tonumber(port.size[axis])

                if not value or value <= 0 then
                    return ('port "%s" has a box with no %s'):format(port.id, axis)
                end

                if value > 12.0 then
                    return ('port "%s" has a %.1fm box on %s, which is longer than the rig')
                        :format(port.id, value, axis)
                end
            end
        end
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

--- Things worth saying about a profile that are not errors.
---
--- Separate from `validate` because these must not stop a server booting. A rig that boots
--- with a confusing eye menu is a worse outcome than one that boots with a warning about it,
--- and refusing to start over ergonomics would be absurd.
---
--- The one that matters: **outlets on a real rig are inches apart**, so their zones overlap
--- and ox_target offers all of them at once. That is fine, and better than making someone
--- pixel-hunt a specific fitting -- but only if each option says which outlet it is. Two
--- entries both reading "Connect a line" is the failure; "Rear (purple)" and "Crosslay
--- (white)" is a menu.
---@param profile table
---@param reach table `MIFireApparatus.portReach`
---@return string[] warnings
function Apparatus.warnings(profile, reach)
    local warnings = {}
    local ports = profile.ports or {}

    for i = 1, #ports do
        for j = i + 1, #ports do
            local a, b = ports[i], ports[j]

            -- Only same-type ports compete: a discharge and a gear locker offering at once is
            -- two different questions, not an ambiguous one.
            if a.type == b.type
                and Apparatus.anchor(a) == 'offset' and Apparatus.anchor(b) == 'offset' then

                local dx = (a.x or 0) - (b.x or 0)
                local dy = (a.y or 0) - (b.y or 0)
                local dz = (a.z or 0) - (b.z or 0)
                local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

                local _, ra = Apparatus.reach(a, reach)
                local _, rb = Apparatus.reach(b, reach)

                if distance < ra + rb and (not a.label or not b.label) then
                    warnings[#warnings + 1] = ('ports "%s" and "%s" are %.2fm apart and their '
                        .. 'zones overlap, so both will offer at once -- give them labels or '
                        .. 'the player sees two identical options')
                        :format(a.id, b.id, distance)
                end
            end
        end
    end

    for i = 1, #ports do
        local port = ports[i]

        if port.preconnected and not tonumber(port.size) then
            warnings[#warnings + 1] = ('port "%s" has hose preconnected but no size -- the '
                .. 'hose system cannot work out what diameter it is pulling'):format(port.id)
        end

        if port.preconnected and not tonumber(port.preconnected.feet) then
            warnings[#warnings + 1] = ('port "%s" is preconnected but does not say how much '
                .. 'hose is on it'):format(port.id)
        end
    end

    return warnings
end

--- Render one port as the config line `/fireoffset` should paste.
---
--- Lives here rather than in the finder so the format is one thing rather than two that drift,
--- and so it can be tested without the game.
---@param port table
---@return string
function Apparatus.format(port)
    -- A bone-anchored port leads with the bone, because that is the interesting part and the
    -- offsets after it are a nudge. Zero offsets are dropped entirely rather than written as
    -- `x = 0.000`, which reads as a measurement someone took.
    if Apparatus.anchor(port) == 'bone' then
        local nudge = ''

        if (port.x or 0) ~= 0 or (port.y or 0) ~= 0 or (port.z or 0) ~= 0 then
            nudge = (', x = %.3f, y = %.3f, z = %.3f')
                :format(port.x or 0, port.y or 0, port.z or 0)
        end

        return ('        { id = %q, type = %q, bone = %q%s },')
            :format(port.id, port.type, port.bone, nudge)
    end

    local zone = ''

    if type(port.size) == 'table' then
        zone = (', size = { x = %.2f, y = %.2f, z = %.2f }')
            :format(port.size.x, port.size.y, port.size.z)
    elseif tonumber(port.radius) then
        zone = (', radius = %.2f'):format(port.radius)
    end

    return ('        { id = %q, type = %q, x = %.3f, y = %.3f, z = %.3f, heading = %.1f%s },')
        :format(port.id, port.type, port.x, port.y, port.z, port.heading or 0.0, zone)
end

MIFire.Apparatus = Apparatus

return Apparatus
