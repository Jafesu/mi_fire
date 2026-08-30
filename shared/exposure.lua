--- Exposure maths.
---
--- Three damage channels, three separate defences, and no combination of equipment that
--- makes a firefighter safe. See ADR 0001.
---
---   **Flame**   standing in a node. Reduced by turnout `fireResist`, never removed.
---               Sustained contact degrades the gear, and degraded gear protects less.
---   **Heat**    proximity, not contact. Reduced by `heatResist`. Accumulates as a load
---               that decays when you back out.
---   **Smoke**   stopped completely by an SCBA with air, and by nothing else. No gear
---               tier reduces it -- `config/gear.lua` has no smoke field at all.
---
--- Pure, so the numbers can be checked outside the game. Balance arguments about how long
--- a firefighter survives in a room are much easier to have against a table of figures
--- than against someone standing in a fire.

MIFire = MIFire or {}

local Exposure = {}

-- ---------------------------------------------------------------------------
-- Flame
-- ---------------------------------------------------------------------------

--- Damage per second from standing in fire.
---
--- `fireResist` is a multiplier that is clamped below 1.0 at config load, so this can
--- never return zero for a burning node. That is the invariant: gear buys time.
---@param intensity number Node intensity, 0-100.
---@param tier table Resolved gear tier.
---@param config table `MIFireGear.exposure.flame`
---@return number damagePerSecond
function Exposure.flameDamage(intensity, tier, config)
    intensity = math.max(0.0, math.min(100.0, tonumber(intensity) or 0))
    if intensity <= 0 then return 0.0 end

    local base = config.baseDamagePerTick * (1000.0 / config.tickMs)

    if config.intensityScaling then
        base = base * (intensity / 100.0)
    end

    local resist = math.max(0.0, math.min(0.95, tonumber(tier.fireResist) or 0.0))
    return base * (1.0 - resist)
end

--- Integrity lost per second of contact.
---
--- Scaled by intensity, so a smouldering node is survivable far longer than a developed
--- one. A tier with no integrity pool (a station uniform) has nothing to lose and returns
--- zero -- it was never protecting anything.
---@param intensity number
---@param tier table
---@return number integrityPerSecond
function Exposure.gearDegradation(intensity, tier)
    if (tonumber(tier.integrity) or 0) <= 0 then return 0.0 end

    intensity = math.max(0.0, math.min(100.0, tonumber(intensity) or 0))
    return (tonumber(tier.degradeRate) or 0.0) * (intensity / 100.0)
end

--- Has this gear been burned through far enough that the wearer can catch fire?
---@param integrity number Current integrity.
---@param tier table
---@return boolean
function Exposure.canIgnite(integrity, tier)
    local capacity = tonumber(tier.integrity) or 0

    -- No gear at all: the threshold is 1.0, so an unprotected player is always ignitable.
    if capacity <= 0 then return true end

    local fraction = math.max(0.0, integrity) / capacity
    return fraction <= (tonumber(tier.ignitionThreshold) or 0.0)
end

--- Effective protection right now, accounting for wear.
---
--- Burned gear protects less than fresh gear. Without this, integrity would be a number
--- that ticked down and changed nothing until it crossed a threshold.
---@param integrity number
---@param tier table
---@return number fireResist 0 to just under 1
function Exposure.effectiveFireResist(integrity, tier)
    local capacity = tonumber(tier.integrity) or 0
    local resist = math.max(0.0, math.min(0.95, tonumber(tier.fireResist) or 0.0))

    if capacity <= 0 then return resist end

    local fraction = math.max(0.0, math.min(1.0, integrity / capacity))

    -- Falls to 88% of its rated value at zero integrity rather than to nothing. A burned
    -- coat is still a coat; it is just no longer doing its job properly.
    --
    -- Kept shallow on purpose. The real consequence of burning through gear is not that it
    -- protects less -- it is that you become ignitable, which is a far sharper cliff than
    -- a resistance number sliding. Making this steep as well punished the same mistake
    -- twice and collapsed the working window that turnout exists to provide.
    return resist * (0.88 + 0.12 * fraction)
end

-- ---------------------------------------------------------------------------
-- Heat
-- ---------------------------------------------------------------------------

--- How far radiant heat reaches from a node.
---@param intensity number
---@param config table `MIFireGear.exposure.heat`
---@param flameConfig table `MIFireGear.exposure.flame`
---@return number metres
function Exposure.heatRadius(intensity, config, flameConfig)
    intensity = math.max(0.0, math.min(100.0, tonumber(intensity) or 0))
    local contact = tonumber(flameConfig.contactRadius) or 1.8
    return contact * config.radiusMultiplier * (0.4 + 0.6 * (intensity / 100.0))
end

--- Heat load gained per second at a distance from a node.
---
--- Full strength at the flame edge, falling to nothing at the limit of the radius. Returns
--- zero beyond it, so a fire across the street does not slowly cook anyone.
---@param distance number Metres from the node.
---@param intensity number
---@param tier table
---@param config table `MIFireGear.exposure.heat`
---@param flameConfig table `MIFireGear.exposure.flame`
---@return number loadPerSecond
function Exposure.heatBuild(distance, intensity, tier, config, flameConfig)
    local radius = Exposure.heatRadius(intensity, config, flameConfig)
    if radius <= 0 or distance >= radius then return 0.0 end

    local proximity = 1.0 - (distance / radius)
    local base = config.buildPerTick * (1000.0 / config.tickMs)
    local resist = math.max(0.0, math.min(0.99, tonumber(tier.heatResist) or 0.0))

    return base * proximity * (intensity / 100.0) * (1.0 - resist)
end

--- Heat load shed per second when clear of any fire.
---@param config table
---@return number
function Exposure.heatDecay(config)
    return config.decayPerTick * (1000.0 / config.tickMs)
end

--- What a given heat load is doing to the wearer.
---@param load number 0 to maxLoad
---@param config table
---@return table effects { straining, damagePerSecond, fraction }
function Exposure.heatEffects(load, config)
    local maxLoad = config.maxLoad
    local fraction = math.max(0.0, math.min(1.0, load / math.max(1.0, maxLoad)))

    local damage = 0.0
    if load >= config.damageAt then
        -- Ramps in past the threshold rather than switching on, so the last stretch before
        -- collapse is a warning rather than a surprise.
        local over = (load - config.damageAt) / math.max(1.0, maxLoad - config.damageAt)
        damage = config.damagePerTick * (1000.0 / config.tickMs) * math.min(1.0, over + 0.2)
    end

    return {
        straining = load >= config.staminaDrainAt,
        damagePerSecond = damage,
        fraction = fraction,
    }
end

-- ---------------------------------------------------------------------------
-- Smoke
-- ---------------------------------------------------------------------------

--- Smoke density at a distance from a node.
---
--- Derived from fire nodes because a real smoke system does not exist yet (`FIRE-008`).
--- When it does, this is replaced by a lookup and nothing else in the exposure model
--- changes -- which is the reason density is a number rather than a boolean.
---@param distance number
---@param intensity number
---@param smokeVolume number Class multiplier from `config/fire_classes.lua`.
---@param indoors boolean Smoke does not disperse indoors.
---@param config table `MIFireGear.exposure.smoke`
---@return number density 0-1
function Exposure.smokeDensity(distance, intensity, smokeVolume, indoors, config)
    local radius = (config.radius or 8.0) * (smokeVolume or 1.0)
    if indoors then radius = radius * (config.indoorMultiplier or 2.0) end

    if radius <= 0 or distance >= radius then return 0.0 end

    local proximity = 1.0 - (distance / radius)
    local density = proximity * (intensity / 100.0) * (smokeVolume or 1.0)

    if indoors then density = density * (config.indoorMultiplier or 2.0) end

    return math.max(0.0, math.min(1.0, density))
end

--- Damage per second from breathing smoke.
---
--- **`hasAir` is the whole function.** A sealed SCBA with air is total immunity, and it is
--- the only such thing in mi_fire. No gear tier appears in this calculation at all, which
--- is by construction rather than by convention.
---@param density number 0-1
---@param hasAir boolean SCBA worn, valve open, bottle not empty.
---@param config table
---@return number damagePerSecond
function Exposure.smokeDamage(density, hasAir, config)
    if hasAir then return 0.0 end
    if density <= 0 then return 0.0 end

    return config.damagePerTick * (1000.0 / config.tickMs) * density
end

-- ---------------------------------------------------------------------------
-- Balance helpers
-- ---------------------------------------------------------------------------

--- How long a tier survives standing in a fire of a given intensity, in seconds.
---
--- Not used by the engine. It exists so balance can be argued against a number: a tier
--- that survives an hour is decoration, and one that survives four seconds is a joke.
---@param intensity number
---@param tier table
---@param config table `MIFireGear.exposure`
---@param health number|nil Starting health, defaults to 200.
---@return number seconds
function Exposure.survivalSeconds(intensity, tier, config, health)
    health = health or 200.0

    local integrity = tonumber(tier.integrity) or 0
    local elapsed, step = 0.0, 0.5

    while health > 0 and elapsed < 3600 do
        local resist = Exposure.effectiveFireResist(integrity, tier)
        local shielded = { fireResist = resist }

        health = health - Exposure.flameDamage(intensity, shielded, config.flame) * step
        integrity = math.max(0.0, integrity
            - Exposure.gearDegradation(intensity, tier) * step)

        elapsed = elapsed + step
    end

    return elapsed
end

MIFire.Exposure = Exposure

return Exposure
