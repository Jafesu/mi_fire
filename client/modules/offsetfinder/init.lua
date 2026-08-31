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

--- Ports authored this session, per vehicle. Cleared when you change rigs, because a port
--- list is only meaningful against the truck it was measured on.
local session = { model = nil, modelName = nil, ports = {} }

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
    local count = 1
    for _, port in ipairs(session.ports) do
        if port.type == portType then count = count + 1 end
    end

    return ('%s%d'):format(portType, count)
end

-- ---------------------------------------------------------------------------
-- Placing one port
-- ---------------------------------------------------------------------------

local function placePort(vehicle)
    local typeInput = lib.inputDialog('New port', {
        {
            type = 'select',
            label = 'Type',
            options = (function()
                local options = {}
                for _, name in ipairs(TYPE_ORDER) do
                    options[#options + 1] = { value = name, label = name }
                end
                return options
            end)(),
            required = true,
            default = 'discharge',
        },
    })

    if not typeInput then return end
    local portType = typeInput[1]

    local idInput = lib.inputDialog('New port', {
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
            description = 'Shown to players. Optional.',
            default = '',
        },
        {
            type = 'number',
            label = 'Hose size, inches',
            description = 'Discharges only. 1.75, 2.5, 3 or 5.',
            default = portType == 'discharge' and 1.75 or nil,
        },
    })

    if not idInput then return end

    local id, label, size = idInput[1], idInput[2], idInput[3]

    for _, port in ipairs(session.ports) do
        if port.id == id then
            return lib.notify({
                description = ('There is already a port called "%s"'):format(id),
                type = 'error',
            })
        end
    end

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
                title = 'Port placed',
                description = ('%s "%s" at %.2f, %.2f, %.2f -- %d on this rig')
                    :format(portType, id, result.offset.x, result.offset.y, result.offset.z,
                        #session.ports),
                type = 'success',
            })

            OffsetFinder.menu(vehicle)
        end,
        onCancel = function() OffsetFinder.menu(vehicle) end,
    })
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
        lines[#lines + 1] = Apparatus.format(port)
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
            title = 'Place a port',
            description = 'Aim where it goes, nudge it, confirm',
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
                local world = GetOffsetFromEntityInWorldCoords(vehicle, port.x, port.y, port.z)
                DrawMarker(28, world.x, world.y, world.z, 0, 0, 0, 0, 0, 0,
                    0.07, 0.07, 0.07, 255, 190, 60, 200, false, false, 2, false, nil, nil, false)
            end

            -- Placed this session in a different colour, so "already had" and "just added"
            -- are distinguishable at a glance.
            for _, port in ipairs(session.ports) do
                local world = GetOffsetFromEntityInWorldCoords(vehicle, port.x, port.y, port.z)
                DrawMarker(28, world.x, world.y, world.z, 0, 0, 0, 0, 0, 0,
                    0.07, 0.07, 0.07, 80, 230, 120, 200, false, false, 2, false, nil, nil, false)
            end
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Command
-- ---------------------------------------------------------------------------

CreateThread(function()
    while not MIFire.ready do Wait(250) end

    lib.addCommand('fireoffset', {
        help = 'Author apparatus port offsets on the vehicle you are stood at',
        restricted = false,
    }, function()
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
    end)

    Util.debug('offsetfinder', '/fireoffset registered')
end)

MIFire.OffsetFinder = OffsetFinder

return OffsetFinder
