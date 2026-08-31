--- Turnout and SCBA, client side.
---
--- Applies appearance, reports exertion, and registers the interactions. It decides
--- nothing: what tier you are wearing and how much air you have live on the server, and
--- this file is told.
---
--- The interactions are `ox_target` on the apparatus, per the project rule. The one
--- exception is the air valve, which is a keybind -- opening your own mask is an action on
--- yourself, not on the world, and the ox_target rule is about interacting with things.

MIFire = MIFire or {}

local TurnoutClient = {}

local Util = MIFire.Util
local Appearance = MIFire.Appearance
local Target = MIFire.Target

--- Mirror of the server's SCBA state, for the HUD and for knowing what to offer.
local scba = { worn = false, active = false, air = 0.0, capacity = 0.0 }

-- ---------------------------------------------------------------------------
-- Appearance
-- ---------------------------------------------------------------------------

RegisterNetEvent('mi_fire:client:gearAppearance', function(action, set)
    if action == 'apply' then
        -- Remember civilian clothes before the first piece goes on. Only the first call
        -- stores anything, so SCBA over turnout does not overwrite the memory.
        Appearance.remember()
        Appearance.applyForSex(set)
    elseif action == 'restore' then
        Appearance.restore()
    end

    -- Our own change counts too, and the server should hear about it immediately rather
    -- than on the next poll.
    SetTimeout(250, function()
        if MIFire.reportWornGear then MIFire.reportWornGear(true) end
    end)
end)

--- What the server says we are wearing. Used to decide which target options to offer;
--- it is never consulted for protection, which is read server-side.
local gear = { tier = nil, worn = false, integrity = 0.0, capacity = 0.0 }

RegisterNetEvent('mi_fire:client:gearState', function(tier, worn, integrity, capacity)
    gear.tier = tier
    gear.worn = worn == true
    gear.integrity = tonumber(integrity) or 0.0
    gear.capacity = tonumber(capacity) or 0.0
    MIFire.wearingGear = gear.worn
end)

RegisterNetEvent('mi_fire:client:scbaState', function(active, air, capacity)
    scba.worn = air ~= nil
    scba.active = active == true
    scba.air = tonumber(air) or 0.0
    scba.capacity = tonumber(capacity) or 0.0
end)


-- ---------------------------------------------------------------------------
-- What we are actually wearing
-- ---------------------------------------------------------------------------

--- Protection follows the clothing, so the client reports what is on the ped and the
--- server decides what that amounts to.
---
--- The server cannot read this itself -- `GetPedDrawableVariation` is client-only -- so it
--- is reported. That is safe because the server still gates on **job**: a civilian
--- reporting a full set of turnout gets nothing, because they are not a firefighter.
---
--- Drawables only. Texture carries the per-character name tape and rank, and matching on it
--- would mean a firefighter with their own markings is not recognised as wearing the gear.
local WATCHED_SLOTS = {
    hat = { kind = 'prop', id = 0 },
    torso2 = { kind = 'component', id = 11 },
    arms = { kind = 'component', id = 3 },
    pants = { kind = 'component', id = 4 },
    shoes = { kind = 'component', id = 6 },
    ['t-shirt'] = { kind = 'component', id = 8 },
    vest = { kind = 'component', id = 9 },
    mask = { kind = 'component', id = 1 },
    bag = { kind = 'component', id = 5 },
}

---@return table worn `{ slot = drawable }`
local function readWornGear()
    local ped = cache.ped
    local worn = {}

    for slot, def in pairs(WATCHED_SLOTS) do
        if def.kind == 'prop' then
            worn[slot] = GetPedPropIndex(ped, def.id)
        else
            worn[slot] = GetPedDrawableVariation(ped, def.id)
        end
    end

    return worn
end

--- Report only when something changed. A clothing set is nine numbers; sending it every
--- two seconds for every player forever would be pure noise on the wire.
local lastReported

local function reportWornGear(force)
    local worn = readWornGear()

    local fingerprint = ('%s|%s|%s|%s|%s|%s'):format(
        worn.hat or -1, worn.torso2 or -1, worn.arms or -1,
        worn.pants or -1, worn.shoes or -1, worn['t-shirt'] or -1)

    if not force and fingerprint == lastReported then return end
    lastReported = fingerprint

    TriggerServerEvent('mi_fire:server:reportGear', worn, IsPedMale(cache.ped) and 'male' or 'female')
end

MIFire.reportWornGear = reportWornGear

CreateThread(function()
    while not MIFire.ready do Wait(250) end

    -- Once on spawn, then on change. Getting dressed is not a frequent event.
    reportWornGear(true)

    while true do
        Wait(2000)
        reportWornGear(false)
    end
end)

--- Anything that changes clothes should say so rather than waiting for the poll.
RegisterNetEvent('illenium-appearance:client:setPedAppearance', function()
    SetTimeout(250, function() reportWornGear(true) end)
end)

-- ---------------------------------------------------------------------------
-- Exertion
-- ---------------------------------------------------------------------------

--- What the player is doing, for air consumption.
---
--- Reported by the client because only the client knows whether the ped is sprinting.
--- The server still owns the bottle: a client claiming to be idle forever changes the
--- rate, never the fact that air runs out.
---@return string
local function currentExertion()
    local ped = cache.ped

    if IsPedSprinting(ped) then return 'sprinting' end
    if IsPedRunning(ped) then return 'running' end

    -- Carrying counts as work even standing still. For now that means anything attached
    -- to the ped; once hose lines and ladders exist (Phase 3, Phase 5) they report their
    -- own load, which is heavier than a carried object.
    if IsEntityAttachedToAnyPed(ped) then return 'carrying' end

    if IsPedWalking(ped) then return 'walking' end
    return 'idle'
end

CreateThread(function()
    while true do
        -- Only report while actually breathing bottle air. There is no reason to send
        -- this every two seconds for every player on the server.
        Wait(scba.active and 2000 or 5000)

        if MIFire.ready and scba.active then
            local nearby = false
            if MIFire.FireClient then
                -- Smoke does not exist yet (FIRE-008); once it does, this becomes a smoke
                -- density check rather than a proximity one.
                nearby = exports.mi_fire:IsFireNearby(12.0) == true
            end

            TriggerServerEvent('mi_fire:server:reportExertion', currentExertion(), nearby)
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Air valve
-- ---------------------------------------------------------------------------

local function toggleAir()
    if not scba.worn then
        return lib.notify({ description = 'You are not wearing a set', type = 'error' })
    end
    TriggerServerEvent('mi_fire:server:toggleScba')
end

CreateThread(function()
    while not MIFire.ready do Wait(250) end

    lib.addKeybind({
        name = MIFireScba.toggle.command,
        description = MIFireScba.toggle.label,
        defaultKey = MIFireScba.toggle.keybind,
        onPressed = toggleAir,
    })

    RegisterCommand(MIFireScba.toggle.command, toggleAir, false)
end)

-- ---------------------------------------------------------------------------
-- Interactions
-- ---------------------------------------------------------------------------

--- Is this vehicle fire apparatus?
---
--- Now that `config/apparatus.lua` exists, this is a real model list -- but it still falls
--- back to any emergency-class vehicle while `allowUnprofiled` is on, so a server running
--- rigs nobody has authored yet is usable rather than broken.
---@param entity integer
---@return boolean
local function isApparatus(entity)
    return MIFire.ApparatusClient.isApparatus(entity)
end

--- Is the player at the right compartment for this?
---
--- A rig with no port of that type authored answers true anywhere on it, so a fleet nobody
--- has run `/fireoffset` on behaves exactly as it did before. Authoring ports *tightens* the
--- interaction rather than being what makes it exist -- nobody should have to author a truck
--- before they can get a coat out of it.
---@param entity integer
---@param coords vector3|nil
---@param portType string
---@return boolean
local function atPort(entity, coords, portType)
    return MIFire.ApparatusClient.atPort(entity, coords, portType)
end

local function coordsOf(entity)
    local coords = GetEntityCoords(entity)
    return { x = coords.x, y = coords.y, z = coords.z }
end

--- The apparatus options, kept in a file-local so `/fire gear` can evaluate the exact
--- entries ox_target holds rather than a copy of them that can drift out of step.
---
--- `Target.addGlobalVehicle` decorates these in place -- the job gate is folded into
--- `canInteract` and `requiresFirefighter` is cleared -- so the flag is snapshotted below
--- before registration, purely so a refusal can name which gate refused.
local apparatusOptions = {
        {
            name = 'mi_fire:repairGear',
            icon = 'screwdriver-wrench',
            label = 'Service turnout gear',
            distance = 2.5,
            canInteract = function(entity, _, coords)
                if not isApparatus(entity) then return false end
                if not atPort(entity, coords, 'gear') then return false end
                if not MIFireGear.integrity.persist.repairAtApparatus then return false end
                return gear.worn and gear.integrity < (gear.capacity or math.huge)
            end,
            onSelect = function(data)
                local seconds = MIFire.Integrity.repairSeconds(
                    gear.integrity, gear.capacity or 100, MIFireGear.integrity)

                local finished = lib.progressBar({
                    duration = math.floor(seconds * 1000),
                    label = 'Servicing gear',
                    canCancel = true,
                    disable = { move = true, car = true, combat = true },
                })

                if finished then
                    TriggerServerEvent('mi_fire:server:repairGear', coordsOf(data.entity))
                end
            end,
        },
        {
            name = 'mi_fire:replaceGear',
            icon = 'shirt',
            label = 'Draw a fresh set',
            distance = 2.5,
            requiresFirefighter = true,
            canInteract = function(entity, _, coords)
                if not isApparatus(entity) then return false end
                if not atPort(entity, coords, 'gear') then return false end
                return gear.worn and gear.integrity < (gear.capacity or math.huge) * 0.95
            end,
            onSelect = function(data)
                local finished = lib.progressBar({
                    duration = math.floor(
                        (MIFireGear.integrity.persist.replaceSeconds or 10.0) * 1000),
                    label = 'Drawing a fresh set',
                    canCancel = true,
                    disable = { move = true, car = true, combat = true },
                })

                if finished then
                    TriggerServerEvent('mi_fire:server:replaceGear', coordsOf(data.entity))
                end
            end,
        },
        {
            name = 'mi_fire:donTurnout',
            icon = 'fire-extinguisher',
            label = 'Don turnout gear',
            distance = 2.5,
            requiresFirefighter = true,
            canInteract = function(entity, _, coords)
                return isApparatus(entity) and atPort(entity, coords, 'gear')
                    and not MIFire.wearingGear
            end,
            onSelect = function(data)
                TriggerServerEvent('mi_fire:server:donTurnout', 'structural', coordsOf(data.entity))
            end,
        },
        {
            name = 'mi_fire:doffTurnout',
            icon = 'shirt',
            label = 'Doff turnout gear',
            distance = 2.5,
            requiresFirefighter = true,
            canInteract = function(entity, _, coords)
                return isApparatus(entity) and atPort(entity, coords, 'gear')
                    and MIFire.wearingGear == true
            end,
            onSelect = function()
                TriggerServerEvent('mi_fire:server:doffTurnout')
            end,
        },
        {
            name = 'mi_fire:donScba',
            icon = 'wind',
            label = 'Take an SCBA set',
            distance = 2.5,
            requiresFirefighter = true,
            canInteract = function(entity, _, coords)
                return MIFireScba.sources.apparatus.enabled
                    and isApparatus(entity) and atPort(entity, coords, 'scba_rack')
                    and not scba.worn
            end,
            onSelect = function(data)
                TriggerServerEvent('mi_fire:server:donScba',
                    { fromRack = true, coords = coordsOf(data.entity) })
            end,
        },
        {
            name = 'mi_fire:rackScba',
            icon = 'wind',
            label = 'Rack SCBA set',
            distance = 2.5,
            requiresFirefighter = true,
            canInteract = function(entity, _, coords)
                return MIFireScba.sources.apparatus.enabled and isApparatus(entity)
                    and atPort(entity, coords, 'scba_rack') and scba.worn
            end,
            onSelect = function(data)
                TriggerServerEvent('mi_fire:server:doffScba',
                    { toRack = true, coords = coordsOf(data.entity) })
            end,
        },
        {
            name = 'mi_fire:refillScba',
            icon = 'gauge-high',
            label = 'Refill air bottle',
            distance = 2.5,
            requiresFirefighter = true,
            canInteract = function(entity, _, coords)
                return isApparatus(entity) and atPort(entity, coords, 'scba_rack')
                    and scba.worn and scba.air < scba.capacity * 0.95
            end,
            onSelect = function(data)
                TriggerServerEvent('mi_fire:server:refillScba', coordsOf(data.entity))
            end,
        },
}

--- `{ label, requiresFirefighter }` per option, taken before decoration clears the flag.
local optionGates = {}
for i = 1, #apparatusOptions do
    optionGates[i] = {
        label = apparatusOptions[i].label,
        requiresFirefighter = apparatusOptions[i].requiresFirefighter == true,
    }
end

CreateThread(function()
    while not MIFire.ready do Wait(250) end

    Target.addGlobalVehicle(apparatusOptions)

    -- Static station racks, for servers that want one before the station tool exists.
    for _, point in ipairs(MIFireScba.sources.station.points or {}) do
        Target.addSphere(point.coords, point.radius or 1.5, {
            {
                name = 'mi_fire:stationScba',
                icon = 'wind',
                label = point.label or 'SCBA rack',
                requiresFirefighter = true,
                onSelect = function()
                    local coords = { x = point.coords.x, y = point.coords.y, z = point.coords.z }
                    if scba.worn then
                        TriggerServerEvent('mi_fire:server:doffScba',
                            { toRack = true, coords = coords })
                    else
                        TriggerServerEvent('mi_fire:server:donScba',
                            { fromRack = true, coords = coords })
                    end
                end,
            },
        })
    end

    Util.debug('turnout', 'gear and SCBA interactions registered')
end)

-- ---------------------------------------------------------------------------
-- Diagnosis
-- ---------------------------------------------------------------------------

--- Why is there no gear option on this truck?
---
--- Every one of these interactions is a chain of quiet booleans -- ox_target running, the
--- client booted, the entity counting as apparatus, the job gate, and the option's own
--- `canInteract`. Any single false produces exactly the same symptom: no option, no error,
--- no log line. That is not diagnosable by looking at it, so it reports itself instead.
---@return string[]
local function diagnoseGear()
    local lines = {}
    local function say(fmt, ...) lines[#lines + 1] = fmt:format(...) end

    say('ox_target: %s', GetResourceState('ox_target'))
    say('client ready: %s', tostring(MIFire.ready))
    say('framework: %s', MIFire.Framework.name or 'none')

    local job, onDuty, grade = MIFire.Framework.getJob()
    say('your job: %s (on duty: %s, grade %d)', job or 'none', tostring(onDuty), grade or 0)

    local known = {}
    for name in pairs(Config.fireJobs) do known[#known + 1] = name end
    table.sort(known)
    say('Config.fireJobs: %s', table.concat(known, ', '))
    say('Config.requireOnDuty: %s', tostring(Config.requireOnDuty))

    local isFf = MIFire.Framework.isFirefighter()
    say('counts as a firefighter: %s', tostring(isFf))

    if not isFf then
        if not job then
            say('  -> no job at all. The framework bridge is not seeing your player data.')
        elseif not Config.fireJobs[job] then
            say('  -> "%s" is not in Config.fireJobs. Add it to config/config.lua.', job)
        elseif Config.requireOnDuty and not onDuty then
            say('  -> you hold the job but are off duty. Clock on, or set '
                .. 'Config.requireOnDuty = false.')
        end
    end

    -- The closest vehicle, which is the one they are stood at -- the same position they
    -- would be in to target it. Deliberately not a raycast: a diagnostic that needs to be
    -- aimed correctly is one more thing that can fail while you are diagnosing.
    local ped = cache.ped
    local coords = GetEntityCoords(ped)
    local vehicle = GetVehiclePedIsIn(ped, false)

    if vehicle == 0 then
        vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, 10.0, 0, 71)
    end

    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        say('no vehicle within 10m -- stand next to the apparatus and run this again')
        return lines
    end

    local model = GetEntityModel(vehicle)
    local class = GetVehicleClass(vehicle)
    say('nearest vehicle: %s (model %s, class %d)',
        GetDisplayNameFromVehicleModel(model), tostring(model), class)

    -- Profiles are keyed by model *name*, lowercase. Looking them up by hash always missed,
    -- so this line reported "not listed" for a rig that is listed -- which is worse than no
    -- line at all, because it sends someone to check a config that was already correct.
    local name = GetDisplayNameFromVehicleModel(model)
    local profile = name and MIFireApparatus.profiles[name:lower()]

    say('profile: %s (%d port(s))',
        profile and 'listed' or 'not listed -- falling back to any emergency vehicle',
        profile and #(profile.ports or {}) or 0)

    local apparatusOk = isApparatus(vehicle)
    say('counts as apparatus: %s', tostring(apparatusOk))

    if not apparatusOk then
        say('  -> class %d is not 18 (emergency). Check the vehicle meta, or wait for '
            .. 'config/apparatus.lua.', class)
    end

    say('gear: tier=%s worn=%s integrity=%.1f/%.1f',
        gear.tier or 'none', tostring(gear.worn), gear.integrity, gear.capacity)
    say('scba: worn=%s active=%s air=%.0f/%.0f',
        tostring(scba.worn), tostring(scba.active), scba.air, scba.capacity)
    say('integrity mode: %s (repair at apparatus: %s)',
        MIFireGear.integrity.mode, tostring(MIFireGear.integrity.persist.repairAtApparatus))
    say('SCBA from apparatus enabled: %s', tostring(MIFireScba.sources.apparatus.enabled))

    say('--- what you should see on that vehicle ---')

    -- Calls the decorated `canInteract` -- the same function object ox_target calls -- so this
    -- cannot drift from the real gate.
    --
    -- Aimed at each option's own compartment rather than at the middle of the truck. Passing
    -- the vehicle centre answered "would this work if you aimed at a point inside the engine
    -- block", which is no, for everything with a zone -- so every option read as blocked and
    -- the report was useless exactly when it was needed.
    local centre = GetEntityCoords(vehicle)

    ---@param portType string
    ---@return vector3
    local function aimFor(portType)
        local _, coords = MIFire.ApparatusClient.nearestPort(vehicle, portType, centre)
        return coords or centre
    end

    local aims = {
        ['mi_fire:repairGear'] = 'gear',
        ['mi_fire:replaceGear'] = 'gear',
        ['mi_fire:donTurnout'] = 'gear',
        ['mi_fire:doffTurnout'] = 'gear',
        ['mi_fire:donScba'] = 'scba_rack',
        ['mi_fire:rackScba'] = 'scba_rack',
        ['mi_fire:refillScba'] = 'scba_rack',
    }

    for i = 1, #apparatusOptions do
        local opt = apparatusOptions[i]
        local gate = optionGates[i]
        local at = aims[opt.name] and aimFor(aims[opt.name]) or centre

        local ok = opt.canInteract == nil
            or opt.canInteract(vehicle, 1.0, at, nil, nil) == true

        local note = ''
        if not ok and gate.requiresFirefighter and not isFf then
            note = '  (blocked by the job gate)'
        end

        say('  [%s] %s%s', ok and 'x' or ' ', gate.label, note)
    end

    say('(each tested aimed at its own compartment, not at the middle of the rig)')

    return lines
end

RegisterNetEvent('mi_fire:client:diagnoseGear', function(serverLines)
    local lines = {}

    for i = 1, #(serverLines or {}) do lines[#lines + 1] = serverLines[i] end
    lines[#lines + 1] = '--- what the CLIENT sees ---'

    for _, line in ipairs(diagnoseGear()) do lines[#lines + 1] = line end
    for i = 1, #lines do
        TriggerEvent('chat:addMessage', { args = { 'mi_fire', lines[i] } })
    end
    print('[mi_fire] gear diagnosis:')
    for i = 1, #lines do print('  ' .. lines[i]) end
end)

-- ---------------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------------

--- Air remaining, for a HUD or another resource.
---@return boolean worn
---@return boolean active
---@return number airSeconds
---@return number capacitySeconds
exports('GetScbaState', function()
    return scba.worn, scba.active, scba.air, scba.capacity
end)

--- What gear tier this client is wearing, for a HUD.
---@return string|nil tier
---@return boolean worn
---@return number integrity
exports('GetGearState', function()
    return gear.tier, gear.worn, gear.integrity, gear.capacity
end)

--- What condition the gear is in, in words rather than a percentage.
---@return string|nil condition
---@return number fraction
exports('GetGearCondition', function()
    if not gear.worn or gear.capacity <= 0 then return nil, 0.0 end
    return MIFire.Integrity.condition(gear.integrity, gear.capacity, MIFireGear.integrity)
end)

MIFire.TurnoutClient = TurnoutClient

return TurnoutClient
