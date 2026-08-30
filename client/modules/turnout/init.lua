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
end)

--- What the server says we are wearing. Used to decide which target options to offer;
--- it is never consulted for protection, which is read server-side.
local gear = { tier = nil, worn = false, integrity = 0.0 }

RegisterNetEvent('mi_fire:client:gearState', function(tier, worn, integrity)
    gear.tier = tier
    gear.worn = worn == true
    gear.integrity = tonumber(integrity) or 0.0
    MIFire.wearingGear = gear.worn
end)

RegisterNetEvent('mi_fire:client:scbaState', function(active, air, capacity)
    scba.worn = air ~= nil
    scba.active = active == true
    scba.air = tonumber(air) or 0.0
    scba.capacity = tonumber(capacity) or 0.0
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
--- Until `config/apparatus.lua` exists (`APP-001`), any emergency-class vehicle a
--- firefighter is standing at counts. That is deliberately loose: it makes gear reachable
--- now, and tightens to a real model list later without the interaction changing.
---@param entity integer
---@return boolean
local function isApparatus(entity)
    if not entity or entity == 0 then return false end

    local apparatus = rawget(_G, 'MIFireApparatus')
    if apparatus and apparatus.profiles then
        return apparatus.profiles[GetEntityModel(entity)] ~= nil
    end

    return GetVehicleClass(entity) == 18   -- emergency
end

local function coordsOf(entity)
    local coords = GetEntityCoords(entity)
    return { x = coords.x, y = coords.y, z = coords.z }
end

CreateThread(function()
    while not MIFire.ready do Wait(250) end

    Target.addGlobalVehicle({
        {
            name = 'mi_fire:donTurnout',
            icon = 'fire-extinguisher',
            label = 'Don turnout gear',
            distance = 2.5,
            requiresFirefighter = true,
            canInteract = function(entity)
                return isApparatus(entity) and not MIFire.wearingGear
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
            canInteract = function(entity)
                return isApparatus(entity) and MIFire.wearingGear == true
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
            canInteract = function(entity)
                return MIFireScba.sources.apparatus.enabled
                    and isApparatus(entity) and not scba.worn
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
            canInteract = function(entity)
                return MIFireScba.sources.apparatus.enabled and isApparatus(entity) and scba.worn
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
            canInteract = function(entity)
                return isApparatus(entity) and scba.worn
                    and scba.air < scba.capacity * 0.95
            end,
            onSelect = function(data)
                TriggerServerEvent('mi_fire:server:refillScba', coordsOf(data.entity))
            end,
        },
    })

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
    return gear.tier, gear.worn, gear.integrity
end)

MIFire.TurnoutClient = TurnoutClient

return TurnoutClient
