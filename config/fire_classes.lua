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

    --- Presentation.
    ---
    --- `ptfx` is a list of layers drawn together, because one particle effect does not read
    --- as a fire -- a flame layer plus a smoke plume does. Each layer has its own scale
    --- multiplier and vertical offset so smoke can sit above the flame.
    ---
    --- These dictionary and effect names are **verified working** pairs. A name that does
    --- not exist fails silently: the native returns a handle of 0 and you get no fire and
    --- no error, which is exactly how the first version of this shipped looking broken.
    --- Do not invent new ones -- confirm them in game first.
    ptfx = {
        { dict = 'core',        name = 'fire_wrecked_truck_vent',  scale = 1.0, z = 0.0 },
        { dict = 'scr_trevor3', name = 'scr_trev3_trailer_plume',  scale = 0.8, z = 0.6 },
    },
    scale = 1.0,

    --- Also start a native GTA script fire under the particles.
    ---
    --- Worth it: a script fire casts real light and heat haze, which particles do not, and
    --- without it a night-time fire is a flat orange smudge that lights nothing. The engine
    --- still owns whether the fire exists -- the script fire is decoration that gets removed
    --- with the node.
    ---
    --- GTA caps concurrent script fires (around 70), so this is skipped once the client is
    --- already rendering a lot of them; particles carry on regardless.
    scriptFire = true,
}

--- Per-class overrides, merged onto `base` at load.
MIFireClasses.classes = {

    --- Class A -- ordinary combustibles. The default structure fire. Behaves the way
    --- everyone expects, which makes it the right thing to learn on.
    A = {
        label = 'Ordinary combustibles',
        ptfx = {
            { dict = 'core',        name = 'fire_wrecked_truck_vent', scale = 1.0, z = 0.0 },
            { dict = 'scr_trevor3', name = 'scr_trev3_trailer_plume', scale = 0.9, z = 0.6 },
        },
        growthPerSecond = 1.2,
        fuel = 240.0,
        spreadChance = 32.0,
        smokeVolume = 1.2,
        --- Ordinary combustibles. Pale early, darkening as the fire works into the
        -- structure -- so this stays low and lets stage do the talking.
        sootiness = 0.15,
    },

    --- Class B -- flammable liquid. Spreads fast, burns hot, and a straight stream
    --- pushes the pool around instead of putting it out. Foam is the answer.
    B = {
        label = 'Flammable liquid',
        -- A pool fire is wide and low with heavy black smoke, not a column.
        ptfx = {
            { dict = 'core', name = 'fire_petroltank_truck',        scale = 1.2, z = 0.0 },
            { dict = 'core', name = 'ent_amb_smoke_foundry',        scale = 1.3, z = 1.0 },
        },
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
        --- Hydrocarbons. Black, thick, and rolling from the first second. This is the
        -- read that identifies a flammable-liquid fire across a car park.
        sootiness = 0.85,
        heatMultiplier = 1.6,
        explosionChance = 0.4,
        explosionRadius = 8.0,
    },

    --- Class C -- energized electrical. Small and stubborn. The danger is not the fire,
    --- it is what happens to a firefighter who hits it with water.
    C = {
        label = 'Energized electrical',
        -- Small flame, arcing, and the electrical crackle that tells a crew what it is
        -- before they put water on it.
        ptfx = {
            { dict = 'scr_michael2', name = 'scr_mich3_heli_fire',  scale = 0.7, z = 0.0 },
            { dict = 'core',         name = 'ent_amb_elec_crackle', scale = 1.0, z = 0.3 },
        },
        ignitionIntensity = 20.0,
        growthPerSecond = 0.7,
        fuel = 120.0,
        canSpread = true,
        spreadIntervalSeconds = 30.0,
        spreadChance = 15.0,
        spreadRadius = 3.0,
        resistance = 1.4,
        smokeVolume = 1.4,
        --- Burning insulation and plastics. Acrid and dark out of proportion to size.
        sootiness = 0.55,
        heatMultiplier = 0.8,

        --- Cutting power converts this node to Class A, which is what actually happens
        --- and gives the crew a reason to find the disconnect.
        deenergizesTo = 'A',
    },

    --- Class D -- combustible metal. Rare, violent, and the one where doing the
    --- obvious thing is catastrophic.
    D = {
        label = 'Combustible metal',
        -- Burning metal is blindingly bright and white rather than orange.
        ptfx = {
            { dict = 'core', name = 'ent_ray_meth_fires',           scale = 1.1, z = 0.0 },
            { dict = 'core', name = 'ent_amb_smoke_factory_white',  scale = 1.4, z = 0.8 },
        },
        ignitionIntensity = 45.0,
        growthPerSecond = 1.0,
        fuel = 300.0,
        fuelBurnPerSecond = 0.4,
        canSpread = false,           -- it does not creep, it just burns
        resistance = 3.0,
        reflashChance = 40.0,
        smokeVolume = 1.8,
        --- Burning metal is brilliant white light and metal-oxide smoke, not carbon.
        sootiness = 0.05,
        heatMultiplier = 2.4,        -- burns far hotter than anything else here
        explosionChance = 0.2,
        explosionRadius = 6.0,
    },

    --- Class K -- cooking oil. Confined, hot, and reflashes readily because the oil
    --- stays above its autoignition temperature long after the flame is out.
    K = {
        label = 'Cooking oil',
        -- Confined and greasy. Small flame, dirty smoke.
        ptfx = {
            { dict = 'core', name = 'ent_ray_meth_fires',    scale = 0.7, z = 0.0 },
            { dict = 'core', name = 'ent_amb_smoke_general', scale = 0.9, z = 0.5 },
        },
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
        --- Cooking oil is a hydrocarbon; it smokes heavily and dark.
        sootiness = 0.6,
        heatMultiplier = 1.3,
    },

    --- Pressurized gas, still feeding. Real doctrine is to *not* extinguish this until
    --- the gas is shut off -- put the flame out with fuel still flowing and you have
    --- swapped a fire for an unignited vapour cloud. Cool the exposures, find the valve.
    gas = {
        label = 'Pressurized gas',
        -- A jet flame, not a pile of burning material. Almost no smoke while it is fed.
        ptfx = {
            { dict = 'core', name = 'fire_petroltank_truck', scale = 1.0, z = 0.0 },
        },
        ignitionIntensity = 50.0,
        growthPerSecond = 0.4,       -- fed, so it does not need to grow
        fuel = 100000.0,             -- effectively unlimited until the valve is shut
        fuelBurnPerSecond = 0.0,
        canSpread = false,
        resistance = 2.2,
        reflashChance = 100.0,       -- always comes back while the gas is on
        reflashDelaySeconds = 4.0,
        smokeVolume = 0.6,
        --- A clean gas flame barely smokes at all, which is its own tell -- a lot of
        -- fire and no smoke means pressurised fuel.
        sootiness = 0.05,
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
        ptfx = {
            { dict = 'core',            name = 'fire_wrecked_truck_vent',   scale = 0.9, z = 0.0 },
            { dict = 'scr_agencyheistb', name = 'scr_env_agency3b_smoke',   scale = 1.4, z = 0.8 },
        },
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
        --- Vegetation smoke is pale tan and voluminous rather than black.
        sootiness = 0.25,
        heatMultiplier = 1.1,
    },

    --- Vehicle fire. Mixed fuel load. An EV pack is the interesting case: it reflashes
    --- repeatedly and needs sustained flow rather than a quick knockdown.
    vehicle = {
        label = 'Vehicle',
        ptfx = {
            { dict = 'core', name = 'fire_vehicle',        scale = 1.0, z = 0.0 },
            { dict = 'core', name = 'ent_amb_elec_crackle', scale = 0.8, z = 0.4 },
        },
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
        --- Tyres, fuel, plastics and upholstery. Close to a Class B read.
        sootiness = 0.75,
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
