--- Exposure, client side.
---
--- Applies what the server decided, and shows the player what is happening to them. The
--- visuals matter more than they look: a firefighter needs to know they are cooking before
--- they collapse, and the only channel for that is the screen.
---
--- Nothing here decides anything. Damage, heat load, ignition and smoke density all arrive
--- from the server.

MIFire = MIFire or {}

local ExposureClient = {}

local Util = MIFire.Util

--- Latest exposure state, driven by the server.
local current = {
    heat = 0.0,
    heatFraction = 0.0,
    straining = false,
    burning = false,
    smoke = 0.0,
    smokeSeconds = 0.0,
    smokeProtected = false,
    integrity = nil,
    capacity = nil,
}

local rolling = false

-- ---------------------------------------------------------------------------
-- Receiving
-- ---------------------------------------------------------------------------

RegisterNetEvent('mi_fire:client:exposure', function(payload)
    if type(payload) ~= 'table' then return end

    if payload.clear then
        current.heat, current.heatFraction = 0.0, 0.0
        current.straining, current.burning = false, false
        current.smoke, current.smokeSeconds = 0.0, 0.0
        return
    end

    if payload.damage and payload.damage > 0 then
        -- Through the medical bridge, which raises a real damage event so qbx_medical can
        -- see it, banks sub-point damage rather than rounding it away, and refuses to keep
        -- hurting someone who is already down.
        MIFire.Medical.damage(payload.damage)
    end

    if payload.heat then
        current.heat = payload.heat.load
        current.heatFraction = payload.heat.fraction
        current.straining = payload.heat.straining
    else
        current.heat, current.heatFraction, current.straining = 0.0, 0.0, false
    end

    if payload.smoke then
        current.smoke = payload.smoke.density
        current.smokeSeconds = payload.smoke.exposedSeconds
        current.smokeProtected = payload.smoke.protected
    else
        current.smoke, current.smokeSeconds = 0.0, 0.0
    end

    if payload.flame then
        current.integrity = payload.flame.integrity
        current.capacity = payload.flame.capacity
    end

    if payload.ignited then
        current.burning = true
        StartEntityFire(cache.ped)
        if lib and lib.notify then
            lib.notify({
                title = 'You are on fire',
                description = 'Stop, drop and roll -- hold X. Or get a line on you.',
                type = 'error',
                duration = 8000,
            })
        end
    end

    if payload.burning ~= nil then current.burning = payload.burning end

    if payload.extinguished then
        current.burning = false
        StopEntityFire(cache.ped)
        if lib and lib.notify then
            lib.notify({ description = 'You are out', type = 'success' })
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Visuals
-- ---------------------------------------------------------------------------

--- Screen effects for heat and smoke.
---
--- Heat distorts and desaturates; smoke darkens and narrows vision. They are deliberately
--- different so a player can tell which one is killing them, which decides whether the
--- answer is to back off or to put a mask on.
CreateThread(function()
    local activeEffect = nil

    while true do
        local busy = current.heatFraction > 0.15 or current.smoke > 0 or current.burning
        Wait(busy and 0 or 500)

        if not busy then
            if activeEffect then
                StopScreenEffect(activeEffect)
                activeEffect = nil
            end
            ClearTimecycleModifier()
        else
            -- Heat: the screen shimmers and washes out as the load climbs.
            if current.heatFraction > 0.4 then
                SetTimecycleModifier('heliGunCam')
                SetTimecycleModifierStrength(current.heatFraction * 0.6)

                if current.heatFraction > 0.75 and activeEffect ~= 'DrugsMichaelAliensFightIn' then
                    if activeEffect then StopScreenEffect(activeEffect) end
                    activeEffect = 'DrugsMichaelAliensFightIn'
                    StartScreenEffect(activeEffect, 0, true)
                end
            end

            -- Smoke: darkens and closes in. Only if there is no air -- a sealed mask means
            -- you can see, which is most of why you wear one.
            if current.smoke > 0 and not current.smokeProtected then
                local intensity = math.min(1.0, current.smoke)
                SetTimecycleModifier('spectator5')
                SetTimecycleModifierStrength(intensity)

                -- Coughing, once exposure has gone on long enough to be worth animating.
                if current.smokeSeconds > (MIFireGear.exposure.smoke.coughOnset or 6.0) then
                    if not IsPedRagdoll(cache.ped) and math.random() < 0.01 then
                        TaskPlayAnim(cache.ped, 'timetable@gardener@smoking_joint',
                            'idle_cough', 8.0, -8.0, 2000, 49, 0, false, false, false)
                    end
                end
            end

            -- Straining under heat load: stamina goes.
            if current.straining then
                RestorePlayerStamina(PlayerId(), 0.0)
                SetPlayerSprint(PlayerId(), false)
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Stop, drop and roll
-- ---------------------------------------------------------------------------

--- Put yourself out.
---
--- Takes the tier's `selfExtinguish` time, which is longer in an encapsulating hazmat suit
--- because you cannot roll effectively in one. A partner with a charged line is faster,
--- which is the point of having a partner.
local function stopDropRoll()
    if rolling or not current.burning then return end
    rolling = true

    local tierName = select(1, exports.mi_fire:GetGearState())
    local tier = MIFireGear.tiers[tierName or MIFireGear.defaultTier] or MIFireGear.tiers.none
    local seconds = tier.selfExtinguish or 5.0

    local finished = lib.progressBar({
        duration = math.floor(seconds * 1000),
        label = 'Stop, drop and roll',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'move_m@injured', clip = 'idle', flag = 9 },
    })

    rolling = false

    if finished then
        TriggerServerEvent('mi_fire:server:selfExtinguish')
    end
end

CreateThread(function()
    while not MIFire.ready do Wait(250) end

    lib.addKeybind({
        name = 'mi_fire_roll',
        description = 'Stop, drop and roll',
        defaultKey = 'X',
        onPressed = stopDropRoll,
    })
end)

-- ---------------------------------------------------------------------------
-- Putting someone else out
-- ---------------------------------------------------------------------------

CreateThread(function()
    while not MIFire.ready do Wait(250) end

    MIFire.Target.addGlobalPed({
        {
            name = 'mi_fire:extinguishPlayer',
            icon = 'fire-extinguisher',
            label = 'Put them out',
            distance = 3.0,
            requiresFirefighter = true,
            canInteract = function(entity)
                if not IsPedAPlayer(entity) then return false end
                -- Only offered on someone actually alight. The server checks again.
                return IsEntityOnFire(entity)
            end,
            onSelect = function(data)
                local player = NetworkGetPlayerIndexFromPed(data.entity)
                if not player then return end

                local finished = lib.progressBar({
                    duration = math.floor(
                        (MIFireGear.exposure.ignition.hoselineExtinguishSeconds or 1.5) * 1000),
                    label = 'Putting them out',
                    canCancel = true,
                    disable = { move = true, combat = true },
                })

                if finished then
                    TriggerServerEvent('mi_fire:server:extinguishPlayer',
                        GetPlayerServerId(player))
                end
            end,
        },
    })
end)

-- ---------------------------------------------------------------------------
-- Teardown and exports
-- ---------------------------------------------------------------------------

RegisterNetEvent('mi_fire:client:teardown', function()
    ClearTimecycleModifier()
    AnimpostfxStopAll()
    if current.burning then StopEntityFire(cache.ped) end
    current.heat, current.heatFraction, current.smoke = 0.0, 0.0, 0.0
    current.burning, current.straining = false, false
end)

--- What is currently happening to this player, for a HUD.
---@return table
exports('GetExposure', function()
    return {
        heat = current.heat,
        heatFraction = current.heatFraction,
        burning = current.burning,
        smoke = current.smoke,
        smokeProtected = current.smokeProtected,
        gearIntegrity = current.integrity,
        gearCapacity = current.capacity,
    }
end)

MIFire.ExposureClient = ExposureClient

return ExposureClient
