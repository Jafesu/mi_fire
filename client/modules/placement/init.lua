--- The shared placement gizmo.
---
--- Aim at a surface, a preview snaps to the point you are looking at and lies flat against it,
--- then nudge it into place and confirm. Used by `/fireoffset` for apparatus ports and, later,
--- by the station tool and the sprinkler tool.
---
--- One module rather than three, deliberately. The alternative is the same raycast, the same
--- nudge keys and the same confirm logic written three times, drifting apart, so that moving a
--- speaker feels different from placing a discharge for no reason a user could explain.
---
--- **Aiming is coarse placement; nudging is fine placement.** Neither involves typing a
--- coordinate. That is the whole design: hand-editing `{ x = -1193.4, y = -1487.2, z = 4.4 }`
--- for every port on every rig is the kind of job that never gets finished, and a config file
--- full of half-finished guesses is worse than an empty one.

MIFire = MIFire or {}

local Placement = {}

local Util = MIFire.Util

--- Only one gizmo at a time. Two would fight over the same keys and the same camera.
local active = nil

--- Nudge step in metres, and how much a fine step is.
local STEP = 0.05
local FINE = 0.01
local COARSE = 0.25

--- Rotation step in degrees.
local TURN = 5.0

-- ---------------------------------------------------------------------------
-- Aiming
-- ---------------------------------------------------------------------------

--- Where is the player looking, and what is the surface facing?
---
--- Returns the hit position and the surface normal, so a preview can lie flat against a wall
--- without anyone typing a rotation. That is the single most useful thing this does: a speaker
--- aimed at a wall should mount against it, and working that out from a normal is free.
---@param maxDistance number
---@param ignore integer|nil Entity to ignore, usually the player's own ped.
---@return boolean hit
---@return vector3 coords
---@return vector3 normal
---@return integer entity
local function aim(maxDistance, ignore)
    local camera = GetGameplayCamCoord()
    local direction = Placement.cameraDirection()

    local target = vector3(
        camera.x + direction.x * maxDistance,
        camera.y + direction.y * maxDistance,
        camera.z + direction.z * maxDistance)

    local ray = StartExpensiveSynchronousShapeTestLosProbe(
        camera.x, camera.y, camera.z,
        target.x, target.y, target.z,
        -1, ignore or 0, 4)

    local _, hit, endCoords, surfaceNormal, entity = GetShapeTestResult(ray)

    return hit == 1 or hit == true, endCoords, surfaceNormal, entity
end

--- Unit vector the gameplay camera is pointing along.
---@return vector3
function Placement.cameraDirection()
    local rotation = GetGameplayCamRot(2)
    local pitch = math.rad(rotation.x)
    local yaw = math.rad(rotation.z)
    local cosPitch = math.abs(math.cos(pitch))

    return vector3(-math.sin(yaw) * cosPitch, math.cos(yaw) * cosPitch, math.sin(pitch))
end

--- Heading that faces out of a surface.
---
--- A wall-mounted thing should face into the room, and the surface normal already says which
--- way that is. Flat ground gives a useless normal, so the player's own heading is used there
--- instead -- pointing the same way you are is a better default than pointing north.
---@param normal vector3
---@return number degrees
local function headingFromNormal(normal)
    if not normal or (math.abs(normal.x) < 0.01 and math.abs(normal.y) < 0.01) then
        return GetEntityHeading(cache.ped)
    end

    return (math.deg(math.atan2(normal.y, normal.x)) - 90.0) % 360.0
end

-- ---------------------------------------------------------------------------
-- The gizmo
-- ---------------------------------------------------------------------------

--- Start placing something.
---
---@param opts table
---   label       string   shown in the help text
---   maxDistance number   how far the aim ray reaches, default 12
---   parent      integer  entity the result is reported relative to, or nil for world
---   snapToAim   boolean  keep following the aim until the first nudge, default true
---   onConfirm   fun(result: table)  called with { coords, heading, offset, normal, entity }
---   onCancel    fun()|nil
---@return boolean started
function Placement.start(opts)
    if active then
        lib.notify({ description = 'Already placing something', type = 'error' })
        return false
    end

    active = {
        label = opts.label or 'Placing',
        maxDistance = opts.maxDistance or 12.0,
        parent = opts.parent,
        following = opts.snapToAim ~= false,
        onConfirm = opts.onConfirm,
        onCancel = opts.onCancel,
        coords = nil,
        heading = 0.0,
        normal = nil,
        entity = 0,
        step = STEP,
    }

    CreateThread(function()
        while active do
            Wait(0)
            Placement.frame()
        end
    end)

    return true
end

function Placement.stop()
    active = nil
end

---@return boolean
function Placement.isActive()
    return active ~= nil
end

--- One frame of the gizmo.
function Placement.frame()
    local state = active
    if not state then return end

    -- Follow the aim until the player nudges, then hold still so a fine adjustment is not
    -- undone by the camera drifting a degree.
    if state.following then
        local hit, coords, normal, entity = aim(state.maxDistance, cache.ped)

        if hit then
            state.coords = coords
            state.normal = normal
            state.entity = entity
            state.heading = headingFromNormal(normal)
        end
    end

    if not state.coords then
        Placement.drawHelp(state, 'Aim at a surface')
        return
    end

    Placement.drawPreview(state)
    Placement.drawHelp(state)
    Placement.readInput(state)
end

--- The preview itself: a marker at the point, and an arrow showing which way it faces.
---@param state table
function Placement.drawPreview(state)
    local c = state.coords

    DrawMarker(28, c.x, c.y, c.z, 0, 0, 0, 0, 0, 0,
        0.08, 0.08, 0.08, 80, 200, 255, 180, false, false, 2, false, nil, nil, false)

    -- Which way it faces, half a metre out along the heading. Without this, orientation is
    -- invisible until something is placed wrong and nobody can see why.
    local rad = math.rad(state.heading)
    DrawLine(c.x, c.y, c.z,
        c.x - math.sin(rad) * 0.5, c.y + math.cos(rad) * 0.5, c.z,
        80, 200, 255, 220)

    -- A vertical stalk, so a point on the floor is visible from standing height.
    DrawLine(c.x, c.y, c.z, c.x, c.y, c.z + 0.4, 80, 200, 255, 120)
end

---@param state table
---@param override string|nil
function Placement.drawHelp(state, override)
    local lines = {
        ('~b~%s~s~'):format(state.label),
        override or (state.following
            and '~y~Aiming~s~ -- nudge or ~b~ENTER~s~ to place'
            or '~g~Adjusting~s~'),
        '',
        '~b~Arrows~s~ move  ~b~PgUp/PgDn~s~ height  ~b~[ ]~s~ turn',
        '~b~SHIFT~s~ fine  ~b~ALT~s~ coarse  ~b~R~s~ re-aim',
        '~b~ENTER~s~ confirm  ~b~BACKSPACE~s~ cancel',
    }

    if state.coords and state.parent and DoesEntityExist(state.parent) then
        local offset = GetOffsetFromEntityGivenWorldCoords(state.parent,
            state.coords.x, state.coords.y, state.coords.z)
        lines[3] = ('~c~x %.3f  y %.3f  z %.3f'):format(offset.x, offset.y, offset.z)
    elseif state.coords then
        lines[3] = ('~c~%.2f, %.2f, %.2f'):format(state.coords.x, state.coords.y, state.coords.z)
    end

    SetTextFont(4)
    SetTextScale(0.34, 0.34)
    SetTextColour(255, 255, 255, 220)
    SetTextOutline()

    local y = 0.32
    for i = 1, #lines do
        SetTextEntry('STRING')
        AddTextComponentString(lines[i])
        DrawText(0.015, y)
        y = y + 0.022
    end
end

--- Move it. Relative to the camera, not to the world, so "left" means left on screen.
---@param state table
function Placement.readInput(state)
    -- Suppress the controls we are borrowing, or nudging also cycles weapons and leans the
    -- camera about.
    DisableControlAction(0, 27, true)   -- up
    DisableControlAction(0, 173, true)  -- down
    DisableControlAction(0, 174, true)  -- left
    DisableControlAction(0, 175, true)  -- right
    DisableControlAction(0, 44, true)   -- Q / cover
    DisableControlAction(0, 38, true)   -- E

    local step = state.step
    if IsControlPressed(0, 21) then step = FINE end        -- shift
    if IsControlPressed(0, 19) then step = COARSE end      -- alt

    local forward = Placement.cameraDirection()
    local flat = vector3(forward.x, forward.y, 0.0)
    local length = math.sqrt(flat.x * flat.x + flat.y * flat.y)
    if length > 0.001 then flat = vector3(flat.x / length, flat.y / length, 0.0) end
    local right = vector3(flat.y, -flat.x, 0.0)

    local dx, dy, dz = 0.0, 0.0, 0.0

    if IsDisabledControlPressed(0, 27) then dx, dy = flat.x * step, flat.y * step end
    if IsDisabledControlPressed(0, 173) then dx, dy = -flat.x * step, -flat.y * step end
    if IsDisabledControlPressed(0, 174) then dx, dy = dx - right.x * step, dy - right.y * step end
    if IsDisabledControlPressed(0, 175) then dx, dy = dx + right.x * step, dy + right.y * step end
    if IsControlPressed(0, 10) then dz = step end          -- page up
    if IsControlPressed(0, 11) then dz = -step end         -- page down

    if dx ~= 0.0 or dy ~= 0.0 or dz ~= 0.0 then
        state.following = false
        state.coords = vector3(state.coords.x + dx, state.coords.y + dy, state.coords.z + dz)
    end

    if IsControlJustPressed(0, 39) then                     -- [
        state.heading = (state.heading - TURN) % 360.0
        state.following = false
    end

    if IsControlJustPressed(0, 40) then                     -- ]
        state.heading = (state.heading + TURN) % 360.0
        state.following = false
    end

    -- Back to following the aim, for when a nudge has gone somewhere silly.
    if IsControlJustPressed(0, 45) then                     -- R
        state.following = true
    end

    if IsControlJustPressed(0, 191) then                    -- enter
        Placement.confirm()
    end

    if IsControlJustPressed(0, 194) then                    -- backspace
        Placement.cancel()
    end
end

function Placement.confirm()
    local state = active
    if not state or not state.coords then return end

    local result = {
        coords = state.coords,
        heading = state.heading,
        normal = state.normal,
        entity = state.entity,
    }

    -- The offset is what almost every caller actually wants: a number that stays correct
    -- however the vehicle is parked.
    if state.parent and DoesEntityExist(state.parent) then
        result.offset = GetOffsetFromEntityGivenWorldCoords(state.parent,
            state.coords.x, state.coords.y, state.coords.z)
        result.relativeHeading = (state.heading - GetEntityHeading(state.parent)) % 360.0
    end

    local callback = state.onConfirm
    active = nil

    if callback then callback(result) end
end

function Placement.cancel()
    local state = active
    if not state then return end

    local callback = state.onCancel
    active = nil

    if callback then callback() end
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    active = nil
end)

MIFire.Placement = Placement

return Placement
