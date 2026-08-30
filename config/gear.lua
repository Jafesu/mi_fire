--- Protective equipment tiers.
---
--- The governing rule, enforced by a test in `tools/tests/hydraulics_spec.lua`:
--- **nothing here may grant immunity to fire.** `fireResist` is a damage multiplier and
--- must stay below 1.0. Gear buys a firefighter time, and time runs out.
---
--- Smoke is deliberately absent from this file. Smoke is stopped by SCBA and by nothing
--- else -- see `config/scba.lua`. A firefighter in full turnout with no air on is still
--- breathing smoke.

MIFireGear = {}

--- How resistance is read at runtime.
---
--- The active tier is held in server state, keyed to the player, and set only by donning
--- at an apparatus. It is never inferred from what the player is wearing -- putting on a
--- turnout skin through a clothing menu grants nothing, which is the whole point.
MIFireGear.defaultTier = 'none'

--- Damage channels each tier answers, and the field that answers it:
---
---   direct flame   fireResist   multiplier on flame damage. Never 1.0.
---   radiant heat   heatResist   multiplier on heat accumulation.
---   chemical       chemResist   multiplier on hazmat contact damage.
---
--- Degradation:
---
---   integrity           durability pool, spent while in direct flame
---   degradeRate         integrity lost per second of contact at full node intensity
---   ignitionThreshold   integrity fraction below which the wearer can catch fire
---   selfExtinguish      seconds of stop-drop-roll to put yourself out
---   mobility            movement multiplier; heavy gear is slow
MIFireGear.tiers = {

    --- No protective equipment. A station uniform is clothing.
    none = {
        label = 'Station uniform',
        fireResist = 0.0,
        heatResist = 0.0,
        chemResist = 0.0,
        integrity = 0,
        degradeRate = 0.0,
        ignitionThreshold = 1.0,   -- ignites immediately on contact
        selfExtinguish = 6.0,
        mobility = 1.0,
        appearance = nil,          -- donning this tier restores stored clothing
    },

    --- Wildland brush gear. Lighter and cooler to work in, far less structural
    --- protection. Correct for a brush fire, dangerous inside a structure.
    wildland = {
        label = 'Wildland brush gear',
        fireResist = 0.35,
        heatResist = 0.40,
        chemResist = 0.05,
        integrity = 60,
        degradeRate = 3.0,
        ignitionThreshold = 0.25,
        selfExtinguish = 5.0,
        mobility = 0.97,
        appearance = {
            male   = { tops = { drawable = -1, texture = 0 }, legs = { drawable = -1, texture = 0 } },
            female = { tops = { drawable = -1, texture = 0 }, legs = { drawable = -1, texture = 0 } },
        },
    },

    --- Full structural turnout. The default fireground tier.
    --- Survives walking through fire. Does not survive standing in it.
    structural = {
        label = 'Structural turnout gear',
        fireResist = 0.75,
        heatResist = 0.70,
        chemResist = 0.15,
        integrity = 100,
        degradeRate = 2.0,
        ignitionThreshold = 0.20,
        selfExtinguish = 4.0,
        mobility = 0.92,
        appearance = {
            male   = { tops = { drawable = -1, texture = 0 }, legs = { drawable = -1, texture = 0 } },
            female = { tops = { drawable = -1, texture = 0 }, legs = { drawable = -1, texture = 0 } },
        },
    },

    --- Aluminized proximity gear. Built for radiant heat off a fuel fire -- aircraft,
    --- bulk flammable liquid. Heavy, hot, and slow to work in.
    proximity = {
        label = 'Proximity gear',
        fireResist = 0.88,
        heatResist = 0.90,
        chemResist = 0.20,
        integrity = 140,
        degradeRate = 1.4,
        ignitionThreshold = 0.15,
        selfExtinguish = 3.5,
        mobility = 0.84,
        appearance = {
            male   = { tops = { drawable = -1, texture = 0 }, legs = { drawable = -1, texture = 0 } },
            female = { tops = { drawable = -1, texture = 0 }, legs = { drawable = -1, texture = 0 } },
        },
    },

    --- Hazmat suits. Note the trade: chemical protection is excellent and fire
    --- protection is *worse than turnout*. A Level A vapour-tight suit is plastic.
    --- Walking a hazmat crew into flame is a mistake the config should let you make
    --- and then punish, because that is how it works in reality.
    hazmat_d = {
        label = 'Level D -- work uniform',
        fireResist = 0.05,
        heatResist = 0.10,
        chemResist = 0.20,
        integrity = 20,
        degradeRate = 8.0,
        ignitionThreshold = 0.50,
        selfExtinguish = 6.0,
        mobility = 1.0,
        appearance = {
            male   = { tops = { drawable = -1, texture = 0 }, legs = { drawable = -1, texture = 0 } },
            female = { tops = { drawable = -1, texture = 0 }, legs = { drawable = -1, texture = 0 } },
        },
    },

    hazmat_c = {
        label = 'Level C -- splash suit, APR',
        fireResist = 0.10,
        heatResist = 0.15,
        chemResist = 0.55,
        integrity = 30,
        degradeRate = 7.0,
        ignitionThreshold = 0.45,
        selfExtinguish = 6.0,
        mobility = 0.95,
        appearance = {
            male   = { tops = { drawable = -1, texture = 0 }, legs = { drawable = -1, texture = 0 } },
            female = { tops = { drawable = -1, texture = 0 }, legs = { drawable = -1, texture = 0 } },
        },
    },

    hazmat_b = {
        label = 'Level B -- splash suit, SCBA',
        fireResist = 0.12,
        heatResist = 0.18,
        chemResist = 0.80,
        integrity = 35,
        degradeRate = 6.5,
        ignitionThreshold = 0.45,
        selfExtinguish = 6.5,
        mobility = 0.88,
        appearance = {
            male   = { tops = { drawable = -1, texture = 0 }, legs = { drawable = -1, texture = 0 } },
            female = { tops = { drawable = -1, texture = 0 }, legs = { drawable = -1, texture = 0 } },
        },
    },

    hazmat_a = {
        label = 'Level A -- vapour-tight encapsulating suit',
        fireResist = 0.15,
        heatResist = 0.20,
        chemResist = 0.98,
        integrity = 40,
        degradeRate = 6.0,
        ignitionThreshold = 0.45,
        selfExtinguish = 8.0,   -- you cannot roll effectively while encapsulated
        mobility = 0.72,
        appearance = {
            male   = { tops = { drawable = -1, texture = 0 }, legs = { drawable = -1, texture = 0 } },
            female = { tops = { drawable = -1, texture = 0 }, legs = { drawable = -1, texture = 0 } },
        },
    },
}

--- Exposure tuning. These are the knobs a server owner actually turns.
MIFireGear.exposure = {
    --- Direct flame, applied per tick to a player standing in a node.
    flame = {
        tickMs = 500,
        baseDamagePerTick = 4.0,      -- against an unprotected player at full intensity
        intensityScaling = true,      -- scale by node intensity 0-100
    },

    --- Radiant heat, applied by proximity rather than contact.
    heat = {
        tickMs = 1000,
        radiusMultiplier = 3.0,       -- heat reaches this many times the node radius
        buildPerTick = 6.0,           -- heat load gained per tick at the node edge
        decayPerTick = 4.0,           -- heat load shed per tick when clear
        maxLoad = 100.0,
        staminaDrainAt = 40.0,        -- heat load above which stamina starts draining
        damageAt = 85.0,              -- heat load above which heat itself hurts
        damagePerTick = 2.0,
    },

    --- Smoke. SCBA is the only defence; no gear tier reduces this.
    smoke = {
        tickMs = 1000,
        damagePerTick = 1.0,          -- slower than fire, but it does not stop
        visionOnset = 4.0,            -- seconds of exposure before vision degrades
        coughOnset = 6.0,
    },

    --- Catching fire.
    ignition = {
        --- Once integrity is below the tier threshold, each flame tick rolls this.
        chancePerTick = 0.08,
        --- Damage per tick while burning, before gear resistance.
        burnDamagePerTick = 6.0,
        --- A partner with a charged line can put someone out faster than rolling.
        hoselineExtinguishSeconds = 1.5,
    },

    --- Gear damage persists on the item, so a rough call costs something afterwards.
    persistence = {
        enabled = true,
        metadataKey = 'integrity',
        --- Below this fraction the gear is unserviceable and must be replaced.
        condemnedBelow = 0.10,
    },
}

return MIFireGear
