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

--- Declared here because the exposure event below ignites the player, and the flames it
--- starts are defined further down. A plain `local function` there would leave this call
--- site resolving to a nil global instead.
--- Verified in production on this server: qbx_medical plays it for last stand.
local ROLL_DICT = 'combat@damage@writhe'
local ROLL_CLIP = 'writhe_loop'

local startBurning, stopBurning

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
        startBurning()
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
        stopBurning()
        if lib and lib.notify then
            lib.notify({ description = 'You are out', type = 'success' })
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Visuals
-- ---------------------------------------------------------------------------

--- Screen effects for heat and smoke, and the warnings that replaced them.
---
--- The effects are **off by default**, on the user's call after testing. Heat escalated
--- into GTA's drug-trip overlay, which reads as being poisoned rather than being cooked;
--- smoke darkened and closed in. Neither said *which* of the three channels was hurting
--- you, which is the only thing that changes what you do about it -- so a distorted screen
--- was indistinguishable from the resource malfunctioning.
---
--- That information now lives on the HUD as three readable numbers, and the screen is left
--- alone so you can see the fire. What survives here is the machinery, config-gated, for
--- anyone who wants it back, plus one heat warning that is worth having either way.
CreateThread(function()
    local visuals = MIFireGear.exposure.visuals or {}
    local heatCfg = visuals.heat or {}
    local smokeCfg = visuals.smoke or {}

    local applied = nil
    local warnedSevere = false

    ---@param name string|nil
    ---@param strength number
    local function timecycle(name, strength)
        if name ~= applied then
            if name then SetTimecycleModifier(name) else ClearTimecycleModifier() end
            applied = name
        end
        if name then SetTimecycleModifierStrength(strength) end
    end

    --- One pass. Split out so the early exits are returns rather than labels -- the test
    --- harness parses this file under 5.1, which has no `goto`.
    ---@param busy boolean
    local function step(busy)
        if not busy then
            if applied then timecycle(nil, 0.0) end
            warnedSevere = false
            return
        end

        local severe = heatCfg.severeFraction or 0.75

        -- The warning is independent of the effects. Heat that damages you through the gear
        -- is worth being told about whether or not the screen is doing anything.
        if current.heatFraction >= severe then
            if visuals.warnOnSevereHeat ~= false and not warnedSevere then
                warnedSevere = true
                lib.notify({
                    title = 'Heat',
                    description = 'Your gear is soaking up more than it can shed. '
                        .. 'Back out or get a line on it.',
                    type = 'error',
                    duration = 6000,
                })
            end
        elseif current.heatFraction < severe * 0.8 then
            -- Rearmed with hysteresis, so hovering on the threshold does not spam.
            warnedSevere = false
        end

        -- Straining under heat load: stamina goes. Not a screen effect, and it stays.
        if current.straining then
            RestorePlayerStamina(PlayerId(), 0.0)
            SetPlayerSprint(PlayerId(), false)
        end

        -- Smoke wins the screen when you are actually breathing it, if enabled at all.
        if smokeCfg.enabled and current.smoke > 0 and not current.smokeProtected then
            timecycle(smokeCfg.timecycle or 'spectator5',
                math.min(smokeCfg.maxStrength or 1.0, current.smoke))

            if smokeCfg.cough
                and current.smokeSeconds > (MIFireGear.exposure.smoke.coughOnset or 6.0)
                and not IsPedRagdoll(cache.ped) and math.random() < 0.05 then
                TaskPlayAnim(cache.ped, 'timetable@gardener@smoking_joint',
                    'idle_cough', 8.0, -8.0, 2000, 49, 0, false, false, false)
            end

        elseif heatCfg.enabled then
            local onset = heatCfg.onsetFraction or 0.35

            if current.heatFraction >= severe then
                local into = (current.heatFraction - severe) / math.max(0.01, 1.0 - severe)
                timecycle(heatCfg.severeTimecycle or 'rply_motionblur',
                    math.min(heatCfg.maxStrength or 0.55, 0.25 + into * 0.5))

                if heatCfg.shake then
                    ShakeGameplayCam(heatCfg.shake, (heatCfg.shakeAmplitude or 0.25) * into)
                end

            elseif current.heatFraction >= onset then
                local into = (current.heatFraction - onset) / math.max(0.01, severe - onset)
                timecycle(heatCfg.buildingTimecycle or 'heliGunCam',
                    math.min(heatCfg.maxStrength or 0.55, into * 0.4))

            elseif applied then
                timecycle(nil, 0.0)
            end

        elseif applied then
            timecycle(nil, 0.0)
        end
    end

    while true do
        local busy = current.heatFraction > 0 or current.smoke > 0 or current.burning
        Wait(busy and 200 or 500)
        step(busy)
    end
end)

--- Leave the screen as we found it. Without this, a timecycle set while the resource was
--- running outlives it and the player looks through it until something else sets one.
---
--- `DrugsMichaelAliensFightIn` is named explicitly because earlier builds started it and a
--- player who stopped the resource mid-effect had no way to clear it.
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    ClearTimecycleModifier()
    StopScreenEffect('DrugsMichaelAliensFightIn')
end)

-- ---------------------------------------------------------------------------
-- Being on fire
-- ---------------------------------------------------------------------------

--- A burning player, drawn by us rather than by the engine.
---
--- `StartEntityFire` looks exactly right and is the obvious call, but it brings GTA's own
--- ped fire damage with it -- and that is fast, unconfigurable, and completely independent
--- of the gear model. In play it killed a firefighter from 37 health in about two seconds
--- against a three second roll, so stop-drop-roll could not be performed. Our own model had
--- given them eighteen seconds; the native was simply overriding all of it.
---
--- So the flames are a particle we own and the damage stays server-side, where every other
--- damage channel in this resource already lives.
local burnFx = nil

function startBurning()
    if burnFx then return end

    local layer = MIFireGear.exposure.ignition.particle
    if not layer then return end

    RequestNamedPtfxAsset(layer.dict)
    local waited = 0
    while not HasNamedPtfxAssetLoaded(layer.dict) do
        Wait(50)
        waited = waited + 50
        if waited > 3000 then
            MIFire.Util.warn('burn particle "%s" would not load', layer.dict)
            return
        end
    end

    UseParticleFxAssetNextCall(layer.dict)

    -- On the spine rather than the root, so it sits on the torso instead of pooling at the
    -- feet, and follows a ragdoll.
    burnFx = StartParticleFxLoopedOnPedBone(layer.name, cache.ped,
        0.0, 0.0, layer.z or 0.0, 0.0, 0.0, 0.0,
        layer.bone or 24816, layer.scale or 1.0, false, false, false)

    if burnFx == 0 then
        burnFx = nil
        MIFire.Util.warn('burn particle "%s" is not in dictionary "%s"', layer.name, layer.dict)
    end
end

function stopBurning()
    if burnFx then
        StopParticleFxLooped(burnFx, false)
        burnFx = nil
    end

    -- Belt and braces: if anything else in the server set the ped alight, put it out too.
    StopEntityFire(cache.ped)
end

-- ---------------------------------------------------------------------------
-- Stop, drop and roll
-- ---------------------------------------------------------------------------

--- Put yourself out.
---
--- Takes the tier's `selfExtinguish` time, which is longer in an encapsulating hazmat suit
--- because you cannot roll effectively in one. A partner with a charged line is faster,
--- which is the point of having a partner.
--- Actually stop, drop and roll.
---
--- Three beats, because a progress bar with a standing animation is not the action being
--- described: you go **down**, you **roll**, and you get **up**. The drop is a short
--- ragdoll so the ped genuinely falls rather than teleporting to the floor, the roll is a
--- ground animation with the ped turning over continuously underneath it, and the server is
--- told you are prone for as long as it lasts.
---
--- `combat@damage@writhe` is the dictionary qbx_medical uses for last stand, so it is
--- verified rather than picked off a list -- the same rule the particle names follow, and
--- for the same reason: a wrong name plays nothing and reports nothing.
local function stopDropRoll()
    if rolling or not current.burning then return end
    rolling = true

    local tierName = select(1, exports.mi_fire:GetGearState())
    local tier = MIFireGear.tiers[tierName or MIFireGear.defaultTier] or MIFireGear.tiers.none
    local seconds = tier.selfExtinguish or 5.0

    local ped = cache.ped

    -- Rolling smothers the flame and puts you under the worst of it. The server halves the
    -- damage while this is true, which is what makes the action worth taking rather than a
    -- delay before dying anyway.
    TriggerServerEvent('mi_fire:server:rolling', true)

    -- Drop. Short, so it reads as going down rather than as losing control.
    SetPedToRagdoll(ped, 700, 700, 0, false, false, false)
    Wait(600)

    RequestAnimDict(ROLL_DICT)
    local waited = 0
    while not HasAnimDictLoaded(ROLL_DICT) and waited < 2000 do
        Wait(50)
        waited = waited + 50
    end

    -- Turn over, continuously, for as long as the roll lasts. This is the part that makes it
    -- look like rolling rather than lying still with a progress bar over it.
    local spinning = true
    CreateThread(function()
        local heading = GetEntityHeading(ped)
        while spinning do
            heading = (heading + 9.0) % 360.0
            SetEntityHeading(ped, heading)
            Wait(20)
        end
    end)

    local finished = lib.progressBar({
        duration = math.floor(seconds * 1000),
        label = 'Stop, drop and roll',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = HasAnimDictLoaded(ROLL_DICT)
            and { dict = ROLL_DICT, clip = ROLL_CLIP, flag = 9 }
            or nil,
    })

    spinning = false
    ClearPedTasks(ped)

    rolling = false
    TriggerServerEvent('mi_fire:server:rolling', false)

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
    if current.burning then stopBurning() end
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
