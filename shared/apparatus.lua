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

--- Is this port an area or a fitting?
---@param port table
---@param shapes table `MIFireApparatus.portShapes`
---@return string 'zone' | 'point'
function Apparatus.shape(port, shapes)
    return (shapes and shapes[port.type]) == 'zone' and 'zone' or 'point'
end

--- The box a set of corners describes.
---
--- **Corners are walked around an opening, not around a footprint.** A gear locker is a door
--- in the side of a rig, so all four corners come back with the same `x` -- a flat vertical
--- rectangle. A hose bed is walked around its rim, so all four come back with the same `z` --
--- a flat horizontal one. Both are the natural thing to do and both are correct.
---
--- The first version treated corners as a floor plan and tested a point against them in the
--- x/y plane. That works for the hose bed and is meaningless for the locker: a shape with no
--- width has no area, so nothing is ever inside it, and every compartment on the side of the
--- truck silently answered no.
---
--- So: take the bounding box of whatever was walked, and give depth to whichever axis came
--- back flat. A door gets depth into the rig, a rim gets height above and below it, and
--- neither needs the person walking it to think about which they are drawing.
---@param port table
---@param depths table `MIFireApparatus.zoneDepth`
---@return table min `{ x, y, z }`
---@return table max
function Apparatus.bounds(port, depths)
    local corners = port.corners or {}

    local min = { x = math.huge, y = math.huge, z = math.huge }
    local max = { x = -math.huge, y = -math.huge, z = -math.huge }

    for i = 1, #corners do
        local corner = corners[i]

        for _, axis in ipairs({ 'x', 'y', 'z' }) do
            local value = tonumber(corner[axis]) or 0.0
            if value < min[axis] then min[axis] = value end
            if value > max[axis] then max[axis] = value end
        end
    end

    if #corners == 0 then
        return { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 }
    end

    local depth = tonumber(port.depth)
        or tonumber(depths and depths[port.type])
        or tonumber(depths and depths.default)
        or 1.0

    -- Anything under this counts as flat and gets the depth. Nobody walks a perfect plane, so
    -- a few centimetres of wobble must not stop an opening being recognised as one.
    local flat = 0.35

    for _, axis in ipairs({ 'x', 'y', 'z' }) do
        if (max[axis] - min[axis]) < flat then
            local centre = (max[axis] + min[axis]) * 0.5
            min[axis] = centre - depth * 0.5
            max[axis] = centre + depth * 0.5
        end
    end

    return min, max
end

--- Is a point inside this port?
---
--- Takes the point already converted to **vehicle-local** space, which is what keeps a
--- compartment where it is however the truck is parked.
---@param port table
---@param localPoint table `{ x, y, z }` in vehicle space
---@param shapes table `MIFireApparatus.portShapes`
---@param depths table `MIFireApparatus.zoneDepth`
---@return boolean
function Apparatus.contains(port, localPoint, shapes, depths)
    if Apparatus.shape(port, shapes) == 'zone' then
        local corners = port.corners

        -- Not walked yet. Answering false would hide the interaction; the caller falls back
        -- to the whole vehicle instead.
        if type(corners) ~= 'table' or #corners < 3 then return false end

        local min, max = Apparatus.bounds(port, depths)

        return localPoint.x >= min.x and localPoint.x <= max.x
            and localPoint.y >= min.y and localPoint.y <= max.y
            and localPoint.z >= min.z and localPoint.z <= max.z
    end

    local reach = tonumber(port.radius) or 0.55

    local dx = localPoint.x - (port.x or 0.0)
    local dy = localPoint.y - (port.y or 0.0)
    local dz = localPoint.z - (port.z or 0.0)

    return (dx * dx + dy * dy + dz * dz) <= reach * reach
end

--- The middle of a port, for anything that needs a position rather than a test.
---@param port table
---@param shapes table
---@return table `{ x, y, z }`
function Apparatus.centre(port, shapes)
    if Apparatus.shape(port, shapes) == 'zone' and type(port.corners) == 'table'
        and #port.corners > 0 then

        local x, y, z, count = 0.0, 0.0, 0.0, 0

        for i = 1, #port.corners do
            local corner = port.corners[i]
            x, y, z = x + corner.x, y + corner.y, z + corner.z
            count = count + 1
        end

        return { x = x / count, y = y / count, z = z / count }
    end

    return { x = port.x or 0.0, y = port.y or 0.0, z = port.z or 0.0 }
end

--- Check one port for the things that are wrong regardless of context.
---@param port table
---@param portTypes table `MIFireApparatus.portTypes`
---@param index integer For the message.
---@return string|nil error
function Apparatus.validatePort(port, portTypes, index, shapes)
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
    local zone = Apparatus.shape(port, shapes) == 'zone'

    -- --- Areas -------------------------------------------------------------------------

    if zone and not bone then
        if type(port.corners) ~= 'table' then
            return ('port "%s" is a %s, which is an area rather than a fitting, and needs '
                .. 'corners -- walk them with /fireoffset'):format(port.id, port.type)
        end

        if #port.corners < 3 then
            return ('port "%s" has %d corner(s); a footprint needs at least three')
                :format(port.id, #port.corners)
        end

        for corner_index, corner in ipairs(port.corners) do
            for _, axis in ipairs({ 'x', 'y', 'z' }) do
                if type(corner[axis]) ~= 'number' then
                    return ('port "%s" corner %d has no %s')
                        :format(port.id, corner_index, axis)
                end
            end

            if math.abs(corner.x) > 20.0 or math.abs(corner.y) > 20.0
                or math.abs(corner.z) > 20.0 then
                return ('port "%s" corner %d is off the rig -- corners are local to the '
                    .. 'vehicle, in metres'):format(port.id, corner_index)
            end
        end

        return nil
    end

    -- --- Fittings ----------------------------------------------------------------------

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

    return nil
end

--- Check a whole profile.
---@param profile table
---@param portTypes table
---@return string[] errors
function Apparatus.validate(profile, portTypes, shapes)
    local errors = {}
    local seen = {}

    for index, port in ipairs(profile.ports or {}) do
        local err = Apparatus.validatePort(port, portTypes, index, shapes)

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
---@param reach number `MIFireApparatus.pointReach`
---@return string[] warnings
function Apparatus.warnings(profile, reach, shapes)
    local warnings = {}
    local ports = profile.ports or {}

    for i = 1, #ports do
        for j = i + 1, #ports do
            local a, b = ports[i], ports[j]

            -- Only same-type ports compete: a discharge and a gear locker offering at once is
            -- two different questions, not an ambiguous one.
            -- Only fittings compete. Two compartments overlapping is a compartment with two
            -- things in it, which is ordinary; two discharges overlapping is an ambiguous
            -- choice between two pieces of brass.
            if a.type == b.type
                and Apparatus.anchor(a) == 'offset' and Apparatus.anchor(b) == 'offset'
                and Apparatus.shape(a, shapes) == 'point' then

                local dx = (a.x or 0) - (b.x or 0)
                local dy = (a.y or 0) - (b.y or 0)
                local dz = (a.z or 0) - (b.z or 0)
                local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

                local combined = (tonumber(a.radius) or reach) + (tonumber(b.radius) or reach)

                if distance < combined and (not a.label or not b.label) then
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

        -- An apparatus is about 2.5m wide and 10m long, so anything much past 1.5m either
        -- side of the centreline is off the rig. Not an error, because a deck gun or an
        -- outrigger legitimately reaches -- but it is far more often an aim ray that went past
        -- the truck and hit the ground behind it, and that is worth saying out loud.
        if Apparatus.anchor(port) == 'offset' and Apparatus.shape(port, shapes) == 'point'
            and math.abs(port.x or 0) > 2.0 then
            warnings[#warnings + 1] = ('port "%s" is %.1fm from the centreline, which is off '
                .. 'the side of the rig -- most likely the aim went past the truck')
                :format(port.id, math.abs(port.x))
        end

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
function Apparatus.format(port, shapes)
    if Apparatus.anchor(port) == 'bone' then
        local nudge = ''

        if (port.x or 0) ~= 0 or (port.y or 0) ~= 0 or (port.z or 0) ~= 0 then
            nudge = (', x = %.3f, y = %.3f, z = %.3f')
                :format(port.x or 0, port.y or 0, port.z or 0)
        end

        return ('        { id = %q, type = %q, bone = %q%s },')
            :format(port.id, port.type, port.bone, nudge)
    end

    if Apparatus.shape(port, shapes) == 'zone' and type(port.corners) == 'table' then
        local lines = {
            ('        { id = %q, type = %q,'):format(port.id, port.type),
        }

        if port.label then
            lines[#lines + 1] = ('          label = %q,'):format(port.label)
        end

        lines[#lines + 1] = '          corners = {'

        for i = 1, #port.corners do
            local corner = port.corners[i]
            lines[#lines + 1] = ('            { x = %.3f, y = %.3f, z = %.3f },')
                :format(corner.x, corner.y, corner.z)
        end

        lines[#lines + 1] = '          } },'

        return table.concat(lines, '\n')
    end

    local extra = ''
    if tonumber(port.size) then extra = extra .. (', size = %s'):format(port.size) end
    if port.label then extra = extra .. (', label = %q'):format(port.label) end

    return ('        { id = %q, type = %q, x = %.3f, y = %.3f, z = %.3f, heading = %.1f%s },')
        :format(port.id, port.type, port.x, port.y, port.z, port.heading or 0.0, extra)
end

MIFire.Apparatus = Apparatus

return Apparatus
