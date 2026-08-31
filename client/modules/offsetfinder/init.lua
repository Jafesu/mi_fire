--- `/fireoffset` -- author apparatus ports by standing at the rig.
---
--- Every offset in `config/apparatus.lua` has to come from here. Both vehicle packs ship
--- `RSC7`-compressed models, so bone names and geometry cannot be read from the files at all,
--- and a discharge position guessed from a photograph is a hose that connects to thin air.
---
--- The output is a config block on your clipboard. It is deliberately not written to the file
--- for you: a tool that rewrites a config while a server is running is a tool that eventually
--- eats someone's hand edits, and pasting a block is five seconds.

MIFire = MIFire or {}

local OffsetFinder = {}

local Util = MIFire.Util
local Placement = MIFire.Placement
local Apparatus = MIFire.Apparatus
local Scan = MIFire.Scan

--- Ports authored this session, per vehicle. Cleared when you change rigs, because a port
--- list is only meaningful against the truck it was measured on.
local session = { model = nil, modelName = nil, ports = {}, lastType = 'discharge' }

--- The order the type picker offers, most-used first. A discharge is what you are almost
--- always placing, and it should not be four keystrokes down a list.
local TYPE_ORDER = {
    'discharge', 'intake', 'hosebed', 'panel', 'gear',
    'scba_rack', 'ladder_rack', 'deckgun', 'tool',
}

---@return integer|nil vehicle
local function nearestVehicle()
    local ped = cache.ped
    local vehicle = GetVehiclePedIsIn(ped, false)

    if vehicle == 0 then
        local coords = GetEntityCoords(ped)
        vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, 12.0, 0, 71)
    end

    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end

    return vehicle
end

--- Suggest an id, so nobody has to invent `crosslay1` from scratch every time.
---@param portType string
---@return string
local function suggestId(portType)
    -- Counts what is already in the config as well as what has been placed this session.
    -- Counting only the session means a second sitting starts back at 1 and collides with the
    -- work from the first, which fails the boot check with a duplicate id -- and does so long
    -- after the person who caused it has stopped thinking about offsets.
    local taken = {}

    local profile = session.modelName
        and MIFireApparatus.profiles[session.modelName:lower()]

    for _, port in ipairs(profile and profile.ports or {}) do
        taken[port.id] = true
    end

    for _, port in ipairs(session.ports) do
        taken[port.id] = true
    end

    local count = 1
    while taken[('%s%d'):format(portType, count)] do
        count = count + 1
    end

    return ('%s%d'):format(portType, count)
end

-- ---------------------------------------------------------------------------
-- Placing one port
-- ---------------------------------------------------------------------------

--- Place a fitting: one point, and that is the whole of it.
---
--- A discharge or an intake is a specific piece of brass you couple a specific line to. Being
--- asked which one is the interaction rather than an obstacle, so these stay tight and stay
--- points.
---@param vehicle integer
---@param portType string
---@param id string
---@param label string
---@param size number|nil
local function placeFitting(vehicle, portType, id, label, size)
    Placement.start({
        label = ('Placing %s "%s"'):format(portType, id),
        parent = vehicle,
        maxDistance = 12.0,
        onConfirm = function(result)
            if not result.offset then
                return lib.notify({ description = 'Lost the vehicle', type = 'error' })
            end

            session.ports[#session.ports + 1] = {
                id = id,
                type = portType,
                x = result.offset.x,
                y = result.offset.y,
                z = result.offset.z,
                heading = result.relativeHeading or 0.0,
                label = (label ~= '' and label) or nil,
                size = size,
            }

            lib.notify({
                title = 'Fitting placed',
                description = ('%s "%s" -- %d port(s) on this rig')
                    :format(portType, id, #session.ports),
                type = 'success',
            })

            OffsetFinder.menu(vehicle)
        end,
        onCancel = function() OffsetFinder.menu(vehicle) end,
    })
end

--- Walk the corners of a compartment.
---
--- A gear locker, a hose bed, a bottle rack and a pump panel are places on the rig rather than
--- points on it, and a centre plus a size is a poor way to describe one -- it guesses at a
--- shape nobody measured, and a compartment along a chamfered corner is not a box.
---
--- So the corners get walked. Points around the opening, in order, and the footprint is
--- whatever shape they make. Height comes from the type, centred on the average height of the
--- corners -- walk them at roughly the height of the opening and the zone lands around it.
---@param vehicle integer
---@param portType string
---@param id string
---@param label string
---@param wanted integer How many corners to collect.
---@param collected table|nil Corners so far.
local function walkCorners(vehicle, portType, id, label, wanted, collected)
    collected = collected or {}

    local index = #collected + 1

    Placement.start({
        label = ('%s "%s" -- corner %d of %d'):format(portType, id, index, wanted),
        parent = vehicle,
        maxDistance = 12.0,
        onConfirm = function(result)
            if not result.offset then
                return lib.notify({ description = 'Lost the vehicle', type = 'error' })
            end

            collected[#collected + 1] = {
                x = result.offset.x,
                y = result.offset.y,
                z = result.offset.z,
            }

            if #collected < wanted then
                lib.notify({
                    description = ('Corner %d placed. %d to go.')
                        :format(#collected, wanted - #collected),
                    type = 'inform',
                })

                return walkCorners(vehicle, portType, id, label, wanted, collected)
            end

            session.ports[#session.ports + 1] = {
                id = id,
                type = portType,
                corners = collected,
                label = (label ~= '' and label) or nil,
            }

            lib.notify({
                title = 'Compartment placed',
                description = ('%s "%s" with %d corners -- %d port(s) on this rig')
                    :format(portType, id, #collected, #session.ports),
                type = 'success',
            })

            OffsetFinder.menu(vehicle)
        end,
        onCancel = function()
            -- Cancelling partway keeps nothing. A three-cornered gear locker is not a useful
            -- half-result, and silently keeping one would produce a zone nobody meant.
            if #collected > 0 then
                lib.notify({
                    description = ('Discarded %d corner(s)'):format(#collected),
                    type = 'inform',
                })
            end

            OffsetFinder.menu(vehicle)
        end,
    })
end

local function placePort(vehicle)
    local typeInput = lib.inputDialog('New port', {
        {
            type = 'select',
            label = 'Type',
            options = (function()
                local options = {}
                for _, name in ipairs(TYPE_ORDER) do
                    local shape = MIFireApparatus.portShapes[name] == 'zone'
                        and 'area' or 'fitting'
                    options[#options + 1] = {
                        value = name,
                        label = ('%s (%s)'):format(name, shape),
                    }
                end
                return options
            end)(),
            required = true,
            --- Defaults to whatever was placed last. A rig has six discharges and one of most
            --- other things, so re-picking "discharge" every time is the single most repeated
            --- action in authoring a truck.
            default = session.lastType or 'discharge',
        },
    })

    if not typeInput then return end
    local portType = typeInput[1]
    session.lastType = portType

    local isZone = MIFireApparatus.portShapes[portType] == 'zone'

    local fields = {
        {
            type = 'input',
            label = 'Port id',
            description = 'Used by the pump panel to bind a control to this outlet',
            default = suggestId(portType),
            required = true,
        },
        {
            type = 'input',
            label = 'Label',
            description = 'Shown to players. Worth setting on a fitting, since several sit '
                .. 'close together and the label is what tells them apart.',
            default = '',
        },
    }

    if isZone then
        fields[#fields + 1] = {
            type = 'number',
            label = 'Corners',
            description = 'How many points to walk around the compartment. Four is usual.',
            default = 4,
            min = 3,
            max = 8,
        }
    else
        fields[#fields + 1] = {
            type = 'number',
            label = 'Hose size, inches',
            description = 'Discharges and intakes. 1.75, 2.5, 3 or 5.',
            default = portType == 'discharge' and 1.75 or nil,
        }
    end

    local input = lib.inputDialog('New port', fields)
    if not input then return end

    local id, label = input[1], input[2]

    for _, port in ipairs(session.ports) do
        if port.id == id then
            return lib.notify({
                description = ('There is already a port called "%s"'):format(id),
                type = 'error',
            })
        end
    end

    if isZone then
        walkCorners(vehicle, portType, id, label, math.floor(input[3] or 4))
    else
        placeFitting(vehicle, portType, id, label, input[3])
    end
end

-- ---------------------------------------------------------------------------
-- Placing on a bone
-- ---------------------------------------------------------------------------

--- Attach a port to a bone instead of measuring an offset.
---
--- Preferred wherever a bone exists. Nothing to measure, it survives the model being updated,
--- and if the author put a bone at the hookup then that bone *is* the hookup -- more accurate
--- than anything produced by nudging a marker around by hand.
---@param vehicle integer
local function placeOnBone(vehicle)
    local bones = Scan.bones(vehicle)

    if #bones == 0 then
        return lib.notify({
            description = 'No named bones found on this model. Measure an offset instead.',
            type = 'error',
        })
    end

    -- Sorted by how far out from the centreline they sit, so the attachment points an author
    -- would have added for hookups cluster at the top rather than being buried among wheels.
    table.sort(bones, function(a, b)
        return math.abs(a.offset.x) > math.abs(b.offset.x)
    end)

    local options = {}

    for _, bone in ipairs(bones) do
        options[#options + 1] = {
            title = bone.name,
            description = ('x %.2f  y %.2f  z %.2f'):format(
                bone.offset.x, bone.offset.y, bone.offset.z),
            icon = 'bone',
            onSelect = function()
                local input = lib.inputDialog(('Port on "%s"'):format(bone.name), {
                    {
                        type = 'select',
                        label = 'Type',
                        options = (function()
                            local out = {}
                            for _, name in ipairs(TYPE_ORDER) do
                                out[#out + 1] = { value = name, label = name }
                            end
                            return out
                        end)(),
                        required = true,
                        default = 'discharge',
                    },
                    { type = 'input', label = 'Port id', required = true },
                    { type = 'input', label = 'Label', default = '' },
                })

                if not input then return OffsetFinder.menu(vehicle) end

                session.ports[#session.ports + 1] = {
                    id = input[2],
                    type = input[1],
                    bone = bone.name,
                    x = 0.0, y = 0.0, z = 0.0,
                    label = (input[3] ~= '' and input[3]) or nil,
                }

                lib.notify({
                    title = 'Port placed on bone',
                    description = ('%s "%s" on %s'):format(input[1], input[2], bone.name),
                    type = 'success',
                })

                OffsetFinder.menu(vehicle)
            end,
        }
    end

    options[#options + 1] = {
        title = 'Back',
        icon = 'arrow-left',
        onSelect = function() OffsetFinder.menu(vehicle) end,
    }

    lib.registerContext({
        id = 'mi_fire_offset_bones',
        title = ('%d bone(s) -- pick one'):format(#bones),
        options = options,
    })

    lib.showContext('mi_fire_offset_bones')
end

--- Light every bone up, so they can be identified by looking rather than by reading numbers.
---@param vehicle integer
local function showBones(vehicle)
    local lines, bones = Scan.report(vehicle)

    for i = 1, #lines do print('[mi_fire] ' .. lines[i]) end

    lib.notify({
        title = ('%d bone(s)'):format(#bones),
        description = 'Listed in F8. Lit up on the rig for 30 seconds.',
        type = 'inform',
    })

    CreateThread(function()
        local until_ = GetGameTimer() + 30000

        while GetGameTimer() < until_ and DoesEntityExist(vehicle) do
            Wait(0)

            for i = 1, #bones do
                local world = GetWorldPositionOfEntityBone(vehicle, bones[i].index)

                DrawMarker(28, world.x, world.y, world.z, 0, 0, 0, 0, 0, 0,
                    0.05, 0.05, 0.05, 190, 120, 255, 200, false, false, 2, false, nil, nil, false)

                -- Named in place. Thirty bone names in a list is unreadable; thirty labels
                -- floating on the truck is a map.
                local onScreen, sx, sy = GetScreenCoordFromWorldCoord(world.x, world.y, world.z)

                if onScreen then
                    -- Zero for the first argument. It is not a second axis, and passing the
                    -- size twice renders roughly three times too large -- the mistake that
                    -- made the placement help unreadable.
                    SetTextFont(4)
                    SetTextScale(0.0, 0.28)
                    SetTextColour(200, 160, 255, 230)
                    SetTextOutline()
                    SetTextCentre(true)
                    SetTextEntry('STRING')
                    AddTextComponentString(bones[i].name)
                    DrawText(sx, sy)
                end
            end
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Output
-- ---------------------------------------------------------------------------

--- Build the config block for what has been placed.
---@return string
local function buildBlock()
    local lines = {
        ('    [%q] = {'):format(session.modelName:lower()),
        ('        label = %q,'):format(session.modelName),
        '        ports = {',
    }

    for _, port in ipairs(session.ports) do
        lines[#lines + 1] = Apparatus.format(port, MIFireApparatus.portShapes)
    end

    lines[#lines + 1] = '        },'
    lines[#lines + 1] = '    },'

    return table.concat(lines, '\n')
end

local function exportPorts()
    if #session.ports == 0 then
        return lib.notify({ description = 'Nothing placed yet', type = 'error' })
    end

    local block = buildBlock()

    -- Clipboard rather than writing the file. A tool that rewrites a config while the server
    -- is running is one that eventually eats somebody's hand edits.
    lib.setClipboard(block)

    print('\n[mi_fire] --- paste into config/apparatus.lua, inside MIFireApparatus.profiles ---')
    print(block)
    print('[mi_fire] --- end ---\n')

    lib.notify({
        title = 'Copied to clipboard',
        description = ('%d port(s). Also printed to F8 in case the clipboard is blocked.')
            :format(#session.ports),
        type = 'success',
    })
end

-- ---------------------------------------------------------------------------
-- Menu
-- ---------------------------------------------------------------------------

---@param vehicle integer
function OffsetFinder.menu(vehicle)
    local options = {
        {
            title = 'Attach a port to a bone',
            description = 'No measuring, and it survives the model being updated. Try first.',
            icon = 'bone',
            onSelect = function() placeOnBone(vehicle) end,
        },
        {
            title = 'Scan this rig',
            description = 'Light up every bone, and list mod slots and extras in F8',
            icon = 'magnifying-glass',
            onSelect = function() showBones(vehicle) end,
        },
        {
            title = 'Measure a port by hand',
            description = 'Aim where it goes, nudge it, confirm. Use when no bone fits.',
            icon = 'crosshairs',
            onSelect = function() placePort(vehicle) end,
        },
    }

    if #session.ports > 0 then
        options[#options + 1] = {
            title = ('Copy %d port(s) to clipboard'):format(#session.ports),
            description = 'Paste into config/apparatus.lua',
            icon = 'clipboard',
            onSelect = exportPorts,
        }

        options[#options + 1] = {
            title = 'Review and remove',
            icon = 'list',
            onSelect = function() OffsetFinder.reviewMenu(vehicle) end,
        }
    end

    options[#options + 1] = {
        title = 'Show existing ports on this rig',
        description = 'Draws what is already in the config, so you can see what is missing',
        icon = 'eye',
        onSelect = function() OffsetFinder.preview(vehicle) end,
    }

    lib.registerContext({
        id = 'mi_fire_offset',
        title = ('%s -- %d port(s)'):format(session.modelName, #session.ports),
        options = options,
    })

    lib.showContext('mi_fire_offset')
end

---@param vehicle integer
function OffsetFinder.reviewMenu(vehicle)
    local options = {}

    for index, port in ipairs(session.ports) do
        options[#options + 1] = {
            title = ('%s (%s)'):format(port.id, port.type),
            description = ('%.2f, %.2f, %.2f -- select to remove'):format(port.x, port.y, port.z),
            icon = 'trash',
            onSelect = function()
                table.remove(session.ports, index)
                lib.notify({ description = ('Removed "%s"'):format(port.id), type = 'inform' })
                OffsetFinder.menu(vehicle)
            end,
        }
    end

    options[#options + 1] = {
        title = 'Back',
        icon = 'arrow-left',
        onSelect = function() OffsetFinder.menu(vehicle) end,
    }

    lib.registerContext({ id = 'mi_fire_offset_review', title = 'Ports', options = options })
    lib.showContext('mi_fire_offset_review')
end

--- Draw one port: a dot for a fitting, an outline for a compartment.
---@param vehicle integer
---@param port table
---@param r integer
---@param g integer
---@param b integer
function OffsetFinder.drawPort(vehicle, port, r, g, b)
    local corners = port.corners

    if type(corners) == 'table' and #corners > 1 then
        -- The footprint, edge by edge. A compartment drawn as a dot at its centre tells you
        -- nothing about whether the walk was any good.
        for i = 1, #corners do
            local a = corners[i]
            local nextCorner = corners[(i % #corners) + 1]

            local from = GetOffsetFromEntityInWorldCoords(vehicle, a.x, a.y, a.z)
            local to = GetOffsetFromEntityInWorldCoords(vehicle,
                nextCorner.x, nextCorner.y, nextCorner.z)

            DrawLine(from.x, from.y, from.z, to.x, to.y, to.z, r, g, b, 220)

            DrawMarker(28, from.x, from.y, from.z, 0, 0, 0, 0, 0, 0,
                0.04, 0.04, 0.04, r, g, b, 200, false, false, 2, false, nil, nil, false)
        end

        return
    end

    local world = GetOffsetFromEntityInWorldCoords(vehicle,
        port.x or 0.0, port.y or 0.0, port.z or 0.0)

    DrawMarker(28, world.x, world.y, world.z, 0, 0, 0, 0, 0, 0,
        0.07, 0.07, 0.07, r, g, b, 200, false, false, 2, false, nil, nil, false)
end

--- Draw everything already configured for this model, plus what has been placed this session.
---
--- The point is to see the gaps. A rig with four discharges in the config and six on the model
--- is not obvious from reading a config file, and it is completely obvious from standing next
--- to it with the existing ones lit up.
---@param vehicle integer
function OffsetFinder.preview(vehicle)
    local profile = MIFireApparatus.profiles[session.modelName:lower()]
    local existing = profile and profile.ports or {}

    lib.notify({
        description = ('%d in config, %d placed this session. Showing for 30 seconds.')
            :format(#existing, #session.ports),
        type = 'inform',
    })

    CreateThread(function()
        local until_ = GetGameTimer() + 30000

        while GetGameTimer() < until_ and DoesEntityExist(vehicle) do
            Wait(0)

            for _, port in ipairs(existing) do
                OffsetFinder.drawPort(vehicle, port, 255, 190, 60)
            end

            -- Placed this session in a different colour, so "already had" and "just added"
            -- are distinguishable at a glance.
            for _, port in ipairs(session.ports) do
                OffsetFinder.drawPort(vehicle, port, 80, 230, 120)
            end
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Command
-- ---------------------------------------------------------------------------

CreateThread(function()
    while not MIFire.ready do Wait(250) end

    --- `RegisterCommand`, not `lib.addCommand`.
    ---
    --- ox_lib's `addCommand` is **server-side only** -- calling it on a client raises
    --- "No such export addCommand in resource ox_lib" and the command never registers, which
    --- presents as the command silently doing nothing. `/fire` works precisely because it is
    --- registered on the server. `passreset` and the SCBA valve already do it this way.
    RegisterCommand('fireoffset', function()
        local vehicle = nearestVehicle()

        if not vehicle then
            return lib.notify({
                description = 'No vehicle within 12m. Stand at the rig.',
                type = 'error',
            })
        end

        local model = GetEntityModel(vehicle)
        local modelName = GetDisplayNameFromVehicleModel(model)

        -- A port list only means anything against the truck it was measured on, so changing
        -- rigs starts again rather than silently mixing two sets of offsets together.
        if session.model and session.model ~= model then
            if #session.ports > 0 then
                lib.notify({
                    title = 'Different vehicle',
                    description = ('Discarding %d port(s) placed on %s')
                        :format(#session.ports, session.modelName),
                    type = 'warning',
                })
            end
            session.ports = {}
        end

        session.model = model
        session.modelName = modelName

        OffsetFinder.menu(vehicle)
    end, false)

    TriggerEvent('chat:addSuggestion', '/fireoffset',
        'Author apparatus port offsets on the vehicle you are stood at')

    Util.debug('offsetfinder', '/fireoffset registered')
end)

MIFire.OffsetFinder = OffsetFinder

return OffsetFinder
