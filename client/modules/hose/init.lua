--- Hose lines, client side.
---
--- Draws the rope, carries the nozzle, and asks the server for everything. It decides nothing:
--- whether a line exists, who is on it and whether it has water in it all live server-side,
--- and this file is told.
---
--- The rope is a real GTA rope rather than a prop. It is simulated, it collides, it sags under
--- its own weight and it follows both ends — nothing anyone could author as a static model
--- would behave better, and rope type 4 is what the fire hose resource already on this machine
--- uses rather than a number picked off a list.

MIFire = MIFire or {}

local HoseClient = {}

local Util = MIFire.Util
local Hose = MIFire.Hose
local Target = MIFire.Target

--- Resolved at call time rather than captured at load time.
---
--- A file-scope `local ApparatusClient = MIFire.ApparatusClient` binds whatever happened to be
--- there when this file loaded, and nothing in the file says which other files have loaded
--- yet. It was nil, and the only symptom was an error the first time somebody aimed at a
--- truck. The manifest order is fixed too, but one of those is a rule you have to remember and
--- the other cannot go wrong.
---@return table
local function apparatus()
    return MIFire.ApparatusClient
end

--- What the server says exists, keyed by line id.
---@type table<string, table>
local lines = {}

--- What we have actually drawn, keyed by line id.
---@type table<string, table>
local drawn = {}

--- The line this client is on, if any.
local mine = nil

local texturesLoaded = false

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

local function ensureTextures()
    if texturesLoaded then return true end

    RopeLoadTextures()

    local waited = 0
    while not RopeAreTexturesLoaded() and waited < 3000 do
        Wait(50)
        waited = waited + 50
    end

    texturesLoaded = RopeAreTexturesLoaded()

    if not texturesLoaded then
        Util.warn('rope textures would not load; hose lines will not draw')
    end

    return texturesLoaded
end

--- The nozzle in someone's hands.
---
--- Off by default, and that is deliberate. There is no vanilla prop that looks like a nozzle:
--- `prop_fire_hosereel_l1` is the reel itself, and in hand it reads as a firefighter carrying a
--- large flat coil of something. Better nothing in the hand than the wrong thing in it.
---
--- Set `MIFireHose.visuals.nozzleProp` if you have an addon prop worth using.
---@param ped integer
---@return integer|nil
local function attachNozzle(ped)
    local name = MIFireHose.visuals.nozzleProp
    if not name or name == '' then return nil end

    local model = joaat(name)

    RequestModel(model)
    local waited = 0
    while not HasModelLoaded(model) and waited < 3000 do
        Wait(50)
        waited = waited + 50
    end

    if not HasModelLoaded(model) then
        Util.warn('nozzle prop "%s" would not load', name)
        return nil
    end

    local coords = GetEntityCoords(ped)
    local prop = CreateObject(model, coords.x, coords.y, coords.z, true, true, false)

    AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, 57005),
        0.12, 0.02, -0.02, -75.0, 12.0, 0.0, true, true, false, true, 1, true)

    SetModelAsNoLongerNeeded(model)

    return prop
end

--- Where a line starts, in the world.
---@param line table
---@return vector3|nil
---@return integer|nil vehicle
local function sourceCoords(line)
    if not line.sourceNet then return nil end
    if not NetworkDoesNetworkIdExist(line.sourceNet) then return nil end

    local entity = NetToVeh(line.sourceNet)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end

    local profile = apparatus().profile(entity)
    local port = profile and MIFire.Apparatus.port(profile, line.sourcePort)

    if not port then return GetEntityCoords(entity), entity end

    return apparatus().portCoords(entity, port), entity
end

---@param id string
---@param line table
local function draw(id, line)
    if drawn[id] then return end
    if MIFireHose.visuals.enabled == false then return end
    if not ensureTextures() then return end

    local from, vehicle = sourceCoords(line)
    if not from then return end

    local holder = line.nozzleHolder and GetPlayerFromServerId(line.nozzleHolder)
    local holderPed = holder and holder ~= -1 and GetPlayerPed(holder) or nil

    -- Nobody is holding it. A dropped line is real and worth drawing eventually, but it needs
    -- a world position to hang from that nothing currently records, so it is skipped rather
    -- than drawn somewhere wrong.
    if not holderPed or not DoesEntityExist(holderPed) then return end

    local size = MIFireHose.sizes[line.diameter] or {}
    local maxLength = Hose.lengthFeet(size, line.sections) * 0.3048

    local ropeType = line.diameter >= (MIFireHose.visuals.largeAbove or 2.5)
        and MIFireHose.visuals.ropeTypeLarge
        or MIFireHose.visuals.ropeType

    local rope = AddRope(from.x, from.y, from.z, 0.0, 0.0, 0.0,
        maxLength, ropeType, maxLength, 0.0, 1.0,
        false, false, false, 1.0, false, 0)

    if not rope or rope == 0 then
        Util.warn('AddRope failed for line %s', id)
        return
    end

    MIFire.trackRope(rope)

    -- **The truck is never attached to the rope.**
    --
    -- `AttachEntitiesToRope` binds two entities and then makes the rope's length a physical
    -- constraint between them. Attaching a fire engine to one end of that is how a fire engine
    -- ends up airborne -- and it did, because the world coordinates it expects were being given
    -- vehicle-local offsets and a literal 0,0,0, so the rope was trying to pull the rig to the
    -- centre of the map. `ActivatePhysics` then let it.
    --
    -- Pinning a vertex sets where that end of the rope *is*, and applies force to nothing. The
    -- pin is refreshed as the rig moves, so the hose still comes off the right outlet.
    PinRopeVertex(rope, 0, from.x, from.y, from.z)

    local hand = GetPedBoneCoords(holderPed, 57005, 0.0, 0.0, 0.0)
    AttachRopeToEntity(rope, holderPed, hand.x, hand.y, hand.z, true)

    local entry = { rope = rope, vehicle = vehicle, nozzle = nil, holder = holderPed }

    if line.nozzleHolder == GetPlayerServerId(PlayerId()) then
        entry.nozzle = attachNozzle(cache.ped)
    end

    drawn[id] = entry
end

---@param id string
local function undraw(id)
    local entry = drawn[id]
    if not entry then return end

    if entry.rope and DoesRopeExist(entry.rope) then DeleteRope(entry.rope) end
    if entry.nozzle and DoesEntityExist(entry.nozzle) then DeleteEntity(entry.nozzle) end

    drawn[id] = nil
end

--- Keep the rig end of each rope on its outlet.
---
--- The pin is a world position rather than an attachment, so it does not follow the truck on
--- its own. Refreshing it costs one native per line and cannot move the vehicle, which is the
--- entire reason it is done this way.
CreateThread(function()
    while true do
        Wait(200)

        for id, entry in pairs(drawn) do
            local line = lines[id]

            if not line or not entry.rope or not DoesRopeExist(entry.rope) then
                undraw(id)
            else
                local from = sourceCoords(line)
                if from then PinRopeVertex(entry.rope, 0, from.x, from.y, from.z) end
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Sync
-- ---------------------------------------------------------------------------

RegisterNetEvent('mi_fire:client:hoseLine', function(id, line)
    if type(id) ~= 'string' then return end

    if not line then
        undraw(id)
        lines[id] = nil
        if mine == id then mine = nil end
        return
    end

    local previous = lines[id]
    lines[id] = line

    if line.crew and line.crew[GetPlayerServerId(PlayerId())] then
        mine = id
    elseif mine == id then
        mine = nil
    end

    -- Redraw when something that changes the rope's shape changed. Rebuilding a rope every
    -- tick would be both expensive and visibly jittery.
    if previous and (previous.sourceNet ~= line.sourceNet
        or previous.nozzleHolder ~= line.nozzleHolder
        or previous.sections ~= line.sections) then
        undraw(id)
    end

    draw(id, line)
end)

-- ---------------------------------------------------------------------------
-- Working the nozzle
-- ---------------------------------------------------------------------------

--- Where the water is going.
---@return vector3|nil
local function aimPoint(reach)
    local camera = GetGameplayCamCoord()
    local direction = MIFire.Placement.cameraDirection()

    local target = vector3(
        camera.x + direction.x * reach,
        camera.y + direction.y * reach,
        camera.z + direction.z * reach)

    local ray = StartExpensiveSynchronousShapeTestLosProbe(
        camera.x, camera.y, camera.z, target.x, target.y, target.z, -1, cache.ped, 4)

    local _, hit, endCoords = GetShapeTestResult(ray)

    return (hit == 1 or hit == true) and endCoords or target
end

--- Put water on the fire.
---
--- The client reports where it is aiming and the server decides what that does, because
--- suppression is fire state and fire state is the server's. The worst a forged aim achieves
--- is putting water somewhere the player is not looking.
CreateThread(function()
    while not MIFire.ready do Wait(250) end

    while true do
        local line = mine and lines[mine]
        local flowing = line and line.state == 'charged' and (line.gpm or 0) > 0
            and line.nozzleHolder == GetPlayerServerId(PlayerId())

        Wait(flowing and 500 or 1000)

        if flowing then
            local nozzle = MIFireHose.nozzles[line.nozzle or 'fog']
            local pattern = line.pattern or (nozzle and nozzle.defaultPattern) or 'straight'
            local reach = nozzle and nozzle.reach and nozzle.reach[pattern] or 15.0

            local point = aimPoint(reach)

            if point then
                -- Half a second of flow, since that is the tick. Efficiency is the pattern's:
                -- a wide fog puts far less water on the seat than a straight stream.
                local efficiency = nozzle and Hose.patternEfficiency(nozzle, pattern) or 1.0

                TriggerServerEvent('mi_fire:server:hoseWater', {
                    x = point.x, y = point.y, z = point.z,
                }, line.gpm * efficiency, 0.5)
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Interactions
-- ---------------------------------------------------------------------------

---@param entity integer
---@param coords vector3|nil
---@return table|nil port
local function dischargeAt(entity, coords)
    if not coords then return nil end

    local ports = apparatus().ports(entity, 'discharge')

    for i = 1, #ports do
        if apparatus().atPort(entity, coords, 'discharge') then
            local world = apparatus().portCoords(entity, ports[i])
            if #(coords - world) <= 1.0 then return ports[i] end
        end
    end

    return nil
end

CreateThread(function()
    while not MIFire.ready do Wait(250) end

    TriggerServerEvent('mi_fire:server:requestHoses')

    Target.addGlobalVehicle({
        {
            name = 'mi_fire:pullHose',
            icon = 'fire-flame-simple',
            label = 'Pull a line',
            distance = 2.5,
            canInteract = function(entity, _, coords)
                if mine then return false end
                if not apparatus().isApparatus(entity) then return false end
                return dischargeAt(entity, coords) ~= nil
            end,
            onSelect = function(data)
                local port = dischargeAt(data.entity, data.coords)
                if not port then return end

                local finished = lib.progressBar({
                    duration = math.floor((MIFireHose.work.pullSeconds or 4.0) * 1000),
                    label = ('Pulling %s'):format(port.label or port.id),
                    canCancel = true,
                    disable = { move = true, car = true, combat = true },
                })

                if finished then
                    TriggerServerEvent('mi_fire:server:pullHose',
                        VehToNet(data.entity), port.id)
                end
            end,
        },
        {
            name = 'mi_fire:connectHose',
            icon = 'link',
            label = 'Connect the line here',
            distance = 2.5,
            canInteract = function(entity, _, coords)
                local line = mine and lines[mine]
                if not line or line.sourceNet then return false end
                if not apparatus().isApparatus(entity) then return false end
                return dischargeAt(entity, coords) ~= nil
            end,
            onSelect = function(data)
                local port = dischargeAt(data.entity, data.coords)
                if not port then return end

                local finished = lib.progressBar({
                    duration = math.floor((MIFireHose.work.connectSeconds or 3.0) * 1000),
                    label = 'Coupling',
                    canCancel = true,
                    disable = { move = true, car = true, combat = true },
                })

                if finished then
                    TriggerServerEvent('mi_fire:server:connectHose',
                        VehToNet(data.entity), port.id)
                end
            end,
        },
        {
            name = 'mi_fire:chargeLine',
            icon = 'droplet',
            label = 'Charge the line',
            distance = 2.5,
            canInteract = function(entity, _, coords)
                if not apparatus().atPort(entity, coords, 'panel') then return false end

                -- Only this rig's lines. Listing every line on the server meant a third engine
                -- offered to charge two other engines' crosslays, which is both wrong and
                -- dangerous -- a pump operator would be charging a line they cannot see.
                local netId = VehToNet(entity)

                for _, line in pairs(lines) do
                    if line.sourceNet == netId
                        and (line.state == 'connected' or line.state == 'charged') then
                        return true
                    end
                end

                return false
            end,
            onSelect = function(data)
                local options = {}
                local netId = VehToNet(data.entity)

                for id, line in pairs(lines) do
                    if line.sourceNet ~= netId then
                        -- Belongs to another rig.
                    elseif line.state == 'connected' then
                        options[#options + 1] = {
                            title = ('Charge %s'):format(line.sourcePort or id),
                            description = ('%s, %d length(s)')
                                :format((MIFireHose.sizes[line.diameter] or {}).label
                                    or line.diameter, line.sections),
                            icon = 'droplet',
                            onSelect = function()
                                TriggerServerEvent('mi_fire:server:chargeHose', id, true)
                            end,
                        }
                    elseif line.state == 'charged' then
                        options[#options + 1] = {
                            title = ('Shut down %s'):format(line.sourcePort or id),
                            icon = 'droplet-slash',
                            onSelect = function()
                                TriggerServerEvent('mi_fire:server:chargeHose', id, false)
                            end,
                        }
                    end
                end

                lib.registerContext({
                    id = 'mi_fire_charge', title = 'Lines', options = options,
                })
                lib.showContext('mi_fire_charge')
            end,
        },
    })

    Util.debug('hose', 'hose interactions registered')
end)

--- Backing up someone else's line, and picking up a dropped nozzle.
---
--- On the ped rather than on the hose, because a rope is not a targetable entity -- you back
--- up the firefighter, which is also how it works on a real fireground.
CreateThread(function()
    while not MIFire.ready do Wait(250) end

    Target.addGlobalPed({
        {
            name = 'mi_fire:backupLine',
            icon = 'people-group',
            label = 'Back up this line',
            distance = 2.0,
            canInteract = function(entity)
                if mine then return false end
                if not IsPedAPlayer(entity) then return false end

                local other = GetPlayerServerId(NetworkGetPlayerIndexFromPed(entity))

                for _, line in pairs(lines) do
                    if line.crew and line.crew[other] then return true end
                end

                return false
            end,
            onSelect = function(data)
                local other = GetPlayerServerId(NetworkGetPlayerIndexFromPed(data.entity))

                for id, line in pairs(lines) do
                    if line.crew and line.crew[other] then
                        return TriggerServerEvent('mi_fire:server:joinHoseCrew', id)
                    end
                end
            end,
        },
    })
end)

-- ---------------------------------------------------------------------------
-- Held controls
-- ---------------------------------------------------------------------------

CreateThread(function()
    while not MIFire.ready do Wait(250) end

    --- Opening the nozzle is a control held during an action already in progress, which is the
    --- one case the ox_target rule allows a keybind for.
    lib.addKeybind({
        name = 'mi_fire_nozzle',
        description = 'Open or close the nozzle',
        defaultKey = 'G',
        onPressed = function()
            local line = mine and lines[mine]
            if not line then return end

            if line.nozzleHolder ~= GetPlayerServerId(PlayerId()) then
                return lib.notify({ description = 'You are not on the nozzle', type = 'error' })
            end

            local size = MIFireHose.sizes[line.diameter]
            local wide = (line.gpm or 0) > 0

            TriggerServerEvent('mi_fire:server:setHoseFlow',
                wide and 0.0 or (size and size.gpmRange[2] or 100.0))
        end,
    })

    lib.addKeybind({
        name = 'mi_fire_pattern',
        description = 'Change nozzle pattern',
        defaultKey = 'B',
        onPressed = function()
            local line = mine and lines[mine]
            if not line or line.nozzleHolder ~= GetPlayerServerId(PlayerId()) then return end

            TriggerServerEvent('mi_fire:server:cycleNozzlePattern')
        end,
    })
end)

--- Remove every rope and prop this client made, regardless of what the server thinks.
---
--- The escape hatch for a line that has gone wrong. It does not ask the server first, because
--- the case it exists for is exactly the one where the two disagree.
RegisterNetEvent('mi_fire:client:clearHoseProps', function()
    for id in pairs(drawn) do undraw(id) end

    drawn = {}
    lines = {}
    mine = nil
end)

exports('GetHoseLine', function() return mine and lines[mine] or nil end)
exports('GetHoseLines', function() return lines end)

MIFire.HoseClient = HoseClient

return HoseClient
