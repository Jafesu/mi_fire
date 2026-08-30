--- Fire class behaviour.
---
--- What each class of fire *does*. What puts it out is `config/agents.lua`; keeping the
--- two apart means you can retune how fast a brush fire spreads without touching whether
--- foam works on it.
---
--- Intensity is 0-100. Fuel is an abstract pool: a node consumes fuel as it burns and
--- goes out for good when it runs out, which is what makes a fire eventually self-limit
--- instead of burning until someone shows up.

MIFireClasses = {}

--- Applied under every class. A class only lists what differs.
MIFireClasses.base = {
    label = 'Fire',

    --- Growth
    ignitionIntensity = 15.0,    -- intensity a fresh node starts at
    growthPerSecond = 1.2,       -- intensity gained per second while fuel remains
    maxIntensity = 100.0,

    --- Fuel
    fuel = 200.0,                -- pool size
    fuelBurnPerSecond = 0.5,     -- consumed per second, scaled by intensity

    --- Spread
    canSpread = true,
    spreadIntervalSeconds = 18.0,
    spreadChance = 30.0,         -- percent, rolled each interval
    spreadRadius = 4.5,          -- metres to a new node
    spreadMaxNodes = 12,         -- per incident, before this class stops spreading
    windInfluence = 0.0,         -- 0 = ignores wind, 1 = fully wind-driven

    --- Suppression
    resistance = 1.0,            -- divides applied agent effectiveness
    reflashChance = 25.0,        -- percent, when knocked down with fuel remaining
    reflashDelaySeconds = 20.0,
    overhaulSeconds = 8.0,       -- sustained application to make knockdown permanent

    --- Hazards
    explosionChance = 0.0,       -- percent per tick at high intensity
    explosionRadius = 0.0,
    smokeVolume = 1.0,           -- multiplier on smoke produced
    heatMultiplier = 1.0,        -- multiplier on radiant heat output

    --- Presentation
    ptfxAsset = 'core',
    ptfxName = 'fire_wrecked_plane_cabin',
    scale = 1.0,
}

--- Per-class overrides, merged onto `base` at load.
MIFireClasses.classes = {

    --- Class A -- ordinary combustibles. The default structure fire. Behaves the way
    --- everyone expects, which makes it the right thing to learn on.
    A = {
        label = 'Ordinary combustibles',
        growthPerSecond = 1.2,
        fuel = 240.0,
        spreadChance = 32.0,
        smokeVolume = 1.2,
    },

    --- Class B -- flammable liquid. Spreads fast, burns hot, and a straight stream
    --- pushes the pool around instead of putting it out. Foam is the answer.
    B = {
        label = 'Flammable liquid',
        ignitionIntensity = 35.0,
        growthPerSecond = 2.6,
        fuel = 160.0,
        fuelBurnPerSecond = 1.1,
        spreadIntervalSeconds = 10.0,
        spreadChance = 45.0,
        spreadRadius = 6.0,
        resistance = 1.6,
        reflashChance = 55.0,        -- a Class B knockdown that is not blanketed comes back
        reflashDelaySeconds = 12.0,
        smokeVolume = 2.0,
        heatMultiplier = 1.6,
        explosionChance = 0.4,
        explosionRadius = 8.0,
    },

    --- Class C -- energized electrical. Small and stubborn. The danger is not the fire,
    --- it is what happens to a firefighter who hits it with water.
    C = {
        label = 'Energized electrical',
        ignitionIntensity = 20.0,
        growthPerSecond = 0.7,
        fuel = 120.0,
        canSpread = true,
        spreadIntervalSeconds = 30.0,
        spreadChance = 15.0,
        spreadRadius = 3.0,
        resistance = 1.4,
        smokeVolume = 1.4,
        heatMultiplier = 0.8,

        --- Cutting power converts this node to Class A, which is what actually happens
        --- and gives the crew a reason to find the disconnect.
        deenergizesTo = 'A',
    },

    --- Class D -- combustible metal. Rare, violent, and the one where doing the
    --- obvious thing is catastrophic.
    D = {
        label = 'Combustible metal',
        ignitionIntensity = 45.0,
        growthPerSecond = 1.0,
        fuel = 300.0,
        fuelBurnPerSecond = 0.4,
        canSpread = false,           -- it does not creep, it just burns
        resistance = 3.0,
        reflashChance = 40.0,
        smokeVolume = 1.8,
        heatMultiplier = 2.4,        -- burns far hotter than anything else here
        explosionChance = 0.2,
        explosionRadius = 6.0,
    },

    --- Class K -- cooking oil. Confined, hot, and reflashes readily because the oil
    --- stays above its autoignition temperature long after the flame is out.
    K = {
        label = 'Cooking oil',
        ignitionIntensity = 30.0,
        growthPerSecond = 1.4,
        fuel = 100.0,
        spreadIntervalSeconds = 25.0,
        spreadChance = 20.0,
        spreadRadius = 2.5,
        spreadMaxNodes = 4,
        resistance = 1.8,
        reflashChance = 70.0,        -- the defining behaviour of a kitchen fire
        reflashDelaySeconds = 15.0,
        smokeVolume = 1.6,
        heatMultiplier = 1.3,
    },

    --- Pressurized gas, still feeding. Real doctrine is to *not* extinguish this until
    --- the gas is shut off -- put the flame out with fuel still flowing and you have
    --- swapped a fire for an unignited vapour cloud. Cool the exposures, find the valve.
    gas = {
        label = 'Pressurized gas',
        ignitionIntensity = 50.0,
        growthPerSecond = 0.4,       -- fed, so it does not need to grow
        fuel = 100000.0,             -- effectively unlimited until the valve is shut
        fuelBurnPerSecond = 0.0,
        canSpread = false,
        resistance = 2.2,
        reflashChance = 100.0,       -- always comes back while the gas is on
        reflashDelaySeconds = 4.0,
        smokeVolume = 0.6,
        heatMultiplier = 2.0,
        explosionChance = 0.0,

        --- Extinguishing without shutting the gas off first arms a vapour explosion.
        requiresShutoff = true,
        shutoffExplosionChance = 65.0,
        shutoffExplosionRadius = 14.0,
    },

    --- Wildland. The one class where wind genuinely drives the incident, and where an
    --- unattended fire becomes a very large problem.
    wildland = {
        label = 'Vegetation',
        ignitionIntensity = 20.0,
        growthPerSecond = 1.0,
        fuel = 180.0,
        spreadIntervalSeconds = 8.0,
        spreadChance = 55.0,
        spreadRadius = 8.0,
        spreadMaxNodes = 30,         -- the big one
        windInfluence = 0.85,
        resistance = 0.8,            -- easy to knock down, hard to keep down
        reflashChance = 35.0,
        smokeVolume = 2.2,
        heatMultiplier = 1.1,
    },

    --- Vehicle fire. Mixed fuel load. An EV pack is the interesting case: it reflashes
    --- repeatedly and needs sustained flow rather than a quick knockdown.
    vehicle = {
        label = 'Vehicle',
        ignitionIntensity = 30.0,
        growthPerSecond = 1.8,
        fuel = 140.0,
        canSpread = true,
        spreadIntervalSeconds = 20.0,
        spreadChance = 18.0,         -- to nearby vehicles and vegetation
        spreadRadius = 5.0,
        spreadMaxNodes = 6,
        resistance = 1.3,
        reflashChance = 30.0,
        smokeVolume = 1.8,
        heatMultiplier = 1.4,
        explosionChance = 0.15,
        explosionRadius = 7.0,

        --- Set on the node when the burning vehicle is electric.
        electricVariant = {
            resistance = 2.4,
            reflashChance = 80.0,
            reflashDelaySeconds = 25.0,
            overhaulSeconds = 45.0,   -- sustained flow, not a quick hit
            fuel = 320.0,
        },
    },
}

return MIFireClasses
