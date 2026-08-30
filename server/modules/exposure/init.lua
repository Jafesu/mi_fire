--- Exposure.
---
--- The thing that makes every other system mean something. Until this existed, turnout
--- gear was a costume, SCBA was a countdown, and a PASS device alarmed for a firefighter
--- nothing could put down.
---
--- Three channels, ticked independently because they run at different rates: flame twice
--- a second, heat and smoke once. Damage is decided here and applied by the client,
--- because a player's ped is owned by their own client -- the same split the hazard system
--- already uses. The trust boundary is real and unavoidable in FiveM; what the server keeps
--- is the decision, the gear tier, and the air.

MIFire = MIFire or {}

local ExposureServer = {}

local Util = MIFire.Util
local State = MIFire.State
local Exposure = MIFire.Exposure
local Enums = MIFire.Enums

local cfg = MIFireGear.exposure

--- Per-player exposure state. Heat load persists between ticks; everything else is derived.
---@type table<integer, table>
local tracked = {}

---@param source integer
---@return table
local function stateFor(source)
    if not tracked[source] then
        tracked[source] = {
            heat = 0.0,
            burning = false,
            burningSince = 0,
            smokeSeconds = 0.0,
            lastFlameAt = 0,
        }
    end
    return tracked[source]
end

-- ---------------------------------------------------------------------------
-- Sampling the fireground
-- ---------------------------------------------------------------------------

--- What a point is exposed to.
---
--- One pass over the nodes producing all three channels, because the alternative is three
--- passes over the same list every tick.
---@param coords vector3
---@return table sample { flameIntensity, nearestFlame, heatBuild, smokeDensity }
function ExposureServer.sample(coords, tier)
    local sample = {
        flameIntensity = 0.0,
        nearestFlame = math.huge,
        heatBuild = 0.0,
        smokeDensity = 0.0,
    }

    local contact = cfg.flame.contactRadius
    local maxReach = math.max(
        Exposure.heatRadius(100, cfg.heat, cfg.flame),
        (cfg.smoke.radius or 9.0) * (cfg.smoke.indoorMultiplier or 2.0))

    for _, node in pairs(State.getNodes()) do
        if node.intensity > 0
            and node.state ~= Enums.NodeState.OUT
            and node.state ~= Enums.NodeState.OVERHAULED then

            local dx = coords.x - node.coords.x
            local dy = coords.y - node.coords.y
            local dz = coords.z - node.coords.z
            local distSq = dx * dx + dy * dy + dz * dz

            if distSq <= maxReach * maxReach then
                local distance = math.sqrt(distSq)

                -- Flame: the hottest node you are standing in wins, rather than summing.
                -- Standing where two fires overlap should not be twice as lethal as a
                -- fire twice the size.
                if distance <= contact and node.intensity > sample.flameIntensity then
                    sample.flameIntensity = node.intensity
                    sample.nearestFlame = distance
                end

                -- Heat accumulates from every source, because standing between two fires
                -- genuinely is hotter than standing beside one.
                sample.heatBuild = sample.heatBuild
                    + Exposure.heatBuild(distance, node.intensity, tier, cfg.heat, cfg.flame)

                -- Smoke takes the worst source rather than summing, so a row of small
                -- fires does not produce impossible density.
                local classConfig = node.resolved or {}
                local density = Exposure.smokeDensity(distance, node.intensity,
                    classConfig.smokeVolume or 1.0, node.interiorId ~= nil, cfg.smoke)

                if density > sample.smokeDensity then sample.smokeDensity = density end
            end
        end
    end

    return sample
end

-- ---------------------------------------------------------------------------
-- Applying
-- ---------------------------------------------------------------------------

--- Tell a client to take damage and show the effects.
---
--- Batched into one event per player per tick. Three separate events for the three
--- channels would triple the traffic for no benefit.
local function push(source, payload)
    TriggerClientEvent('mi_fire:client:exposure', source, payload)
end

--- Advance one player.
---@param source integer
---@param dt number
local function tickPlayer(source, dt)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return end

    local tier, gearEntry = State.getGearTier(source)
    local coords = GetEntityCoords(ped)
    local sample = ExposureServer.sample(coords, tier)
    local player = stateFor(source)

    local payload = { }
    local damage = 0.0

    -- --- Flame -----------------------------------------------------------

    if sample.flameIntensity > 0 then
        -- Gear that has been burned through protects less. Without this, integrity would
        -- tick down and change nothing until it crossed a threshold.
        local resist = Exposure.effectiveFireResist(gearEntry.integrity, tier)
        damage = damage + Exposure.flameDamage(sample.flameIntensity,
            { fireResist = resist }, cfg.flame) * dt

        -- Burn through the gear.
        local worn = Exposure.gearDegradation(sample.flameIntensity, tier) * dt
        if worn > 0 then
            gearEntry.integrity = math.max(0.0, gearEntry.integrity - worn)
        end

        -- Catch fire, once the gear is gone or there was none to begin with.
        if not player.burning and Exposure.canIgnite(gearEntry.integrity, tier) then
            if Util.chance(cfg.ignition.chancePerTick * 100.0 * dt) then
                player.burning = true
                player.burningSince = os.time()
                payload.ignited = true
                Util.debug('exposure', '%s caught fire', tostring(source))
            end
        end

        payload.flame = {
            intensity = sample.flameIntensity,
            integrity = gearEntry.integrity,
            capacity = tier.integrity or 0,
        }

        player.lastFlameAt = os.time()
    end

    -- --- Burning ---------------------------------------------------------

    if player.burning then
        damage = damage + cfg.ignition.burnDamagePerTick * (1000.0 / cfg.flame.tickMs)
            * dt * (1.0 - Exposure.effectiveFireResist(gearEntry.integrity, tier))

        -- Stops on its own eventually, so a disconnect mid-burn does not leave someone
        -- permanently alight.
        if os.time() - player.burningSince > cfg.ignition.maximumBurnSeconds then
            player.burning = false
            payload.extinguished = true
        end

        payload.burning = true
    end

    -- --- Heat ------------------------------------------------------------

    if sample.heatBuild > 0 then
        player.heat = math.min(cfg.heat.maxLoad, player.heat + sample.heatBuild * dt)
    elseif player.heat > 0 then
        player.heat = math.max(0.0, player.heat - Exposure.heatDecay(cfg.heat) * dt)
    end

    if player.heat > 0 then
        local effects = Exposure.heatEffects(player.heat, cfg.heat)
        damage = damage + effects.damagePerSecond * dt

        payload.heat = {
            load = Util.round(player.heat, 1),
            fraction = effects.fraction,
            straining = effects.straining,
        }
    end

    -- --- Smoke -----------------------------------------------------------

    if sample.smokeDensity >= (cfg.smoke.minimumDensity or 0.0) then
        -- The one hard stop in the whole model. A sealed SCBA with air is total immunity
        -- to smoke, and no gear tier appears in this calculation at all.
        local hasAir = State.hasAir(source)

        damage = damage + Exposure.smokeDamage(sample.smokeDensity, hasAir, cfg.smoke) * dt

        if not hasAir then
            player.smokeSeconds = player.smokeSeconds + dt
        else
            player.smokeSeconds = 0.0
        end

        payload.smoke = {
            density = Util.round(sample.smokeDensity, 2),
            protected = hasAir,
            exposedSeconds = Util.round(player.smokeSeconds, 1),
        }
    else
        player.smokeSeconds = math.max(0.0, player.smokeSeconds - dt)
    end

    -- --- Send ------------------------------------------------------------

    if damage > 0 then payload.damage = damage end

    if next(payload) ~= nil then
        push(source, payload)
    elseif player.heat <= 0 and player.smokeSeconds <= 0 and not player.burning then
        -- Nothing happening and nothing decaying: tell the client once so it can clear its
        -- effects, then stop tracking.
        if tracked[source] then
            push(source, { clear = true })
            tracked[source] = nil
        end
    end
end

-- ---------------------------------------------------------------------------
-- Service
-- ---------------------------------------------------------------------------

--- Put a burning player out. Called by stop-drop-roll and by a partner with a hose line.
---@param source integer
---@return boolean
function ExposureServer.extinguish(source)
    local player = tracked[source]
    if not player or not player.burning then return false end

    player.burning = false
    push(source, { extinguished = true })
    Util.debug('exposure', '%s was put out', tostring(source))
    return true
end

---@param source integer
---@return boolean
function ExposureServer.isBurning(source)
    local player = tracked[source]
    return player ~= nil and player.burning == true
end

---@param source integer
---@return number
function ExposureServer.heatLoad(source)
    local player = tracked[source]
    return player and player.heat or 0.0
end

-- ---------------------------------------------------------------------------
-- Tick
-- ---------------------------------------------------------------------------

CreateThread(function()
    while not MIFire.ready do Wait(250) end

    local interval = cfg.flame.tickMs
    local dt = interval / 1000.0

    while true do
        Wait(interval)

        -- Nothing burning and nobody hurt means nothing to do. This is the common case on
        -- a quiet server and it should cost nothing.
        if State.countNodes() > 0 or next(tracked) ~= nil then
            for _, playerId in ipairs(GetPlayers()) do
                local source = tonumber(playerId)
                if source then
                    local ok, err = pcall(tickPlayer, source, dt)
                    if not ok then
                        Util.warn('exposure tick failed for %s: %s', tostring(source), tostring(err))
                    end
                end
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Transports
-- ---------------------------------------------------------------------------

--- The client reports that stop-drop-roll finished. The duration was enforced client-side
--- by a progress bar, and the worst a forged call achieves is putting yourself out early --
--- which is not worth a round trip to prevent.
RegisterNetEvent('mi_fire:server:selfExtinguish', function()
    ExposureServer.extinguish(source)
end)

--- A partner with a charged line puts someone out. Gated on proximity, because doing it
--- from across the map is the thing worth preventing.
RegisterNetEvent('mi_fire:server:extinguishPlayer', function(targetServerId)
    local src = source
    local target = tonumber(targetServerId)
    if not target or not ExposureServer.isBurning(target) then return end

    local targetPed = GetPlayerPed(target)
    if not targetPed or targetPed == 0 then return end

    if not MIFire.Permissions.isNear(src, GetEntityCoords(targetPed), 8.0) then return end

    ExposureServer.extinguish(target)
end)

AddEventHandler('playerDropped', function()
    tracked[source] = nil
end)

exports('IsBurning', function(source) return ExposureServer.isBurning(source) end)
exports('GetHeatLoad', function(source) return ExposureServer.heatLoad(source) end)

MIFire.ExposureServer = ExposureServer

return ExposureServer
