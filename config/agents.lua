--- Extinguishing agent effectiveness.
---
--- This table is what makes fire classes matter. Without it, a Class D fire is a Class A
--- fire wearing a different colour, and the only thing a firefighter has to know is
--- "point hose at orange".
---
--- `effectiveness` multiplies how fast an agent knocks intensity down:
---     > 1.0   better than water on Class A
---     = 1.0   the baseline
---     < 1.0   works, slowly
---     = 0.0   does nothing at all
---     < 0.0   **makes it worse** -- intensity climbs and the hazard fires
---
--- A negative number is not a trick. Water on a grease fire really does make a fireball,
--- and a script that quietly clamps that to zero is teaching the wrong lesson.

MIFireAgents = {}

--- Flow rates and reach per agent, used by nozzles and extinguishers.
MIFireAgents.properties = {
    water = {
        label = 'Water',
        fromTank = true,             -- drawn from the apparatus water tank
        conductive = true,           -- matters for Class C
    },
    foam = {
        label = 'AFFF foam',
        fromTank = true,
        fromFoamCell = true,         -- drawn from the foam cell, not the water tank
        conductive = true,
        blankets = true,             -- suppresses reflash on liquid fuels
    },
    dry_chem = {
        label = 'Dry chemical (ABC)',
        fromTank = false,            -- extinguisher only
        conductive = false,
    },
    co2 = {
        label = 'Carbon dioxide',
        fromTank = false,
        conductive = false,
        displacesOxygen = true,      -- dangerous in a confined space
    },
    wet_chem = {
        label = 'Wet chemical (Class K)',
        fromTank = false,
        conductive = true,
        saponifies = true,           -- the reason it works on cooking oil
    },
    dry_powder = {
        label = 'Dry powder (Class D)',
        fromTank = false,
        conductive = false,
    },
}

--- The matrix. Rows are agents, columns are fire classes.
---
--- `hazard` fires when effectiveness is negative or the combination is dangerous for a
--- reason other than being useless. It is what actually hurts the player.
MIFireAgents.matrix = {

    water = {
        A        = { effectiveness = 1.00 },
        B        = { effectiveness = -0.60, hazard = 'spread',
                     note = 'A straight stream pushes burning liquid outward instead of putting it out.' },
        C        = { effectiveness = 0.30, hazard = 'shock',
                     note = 'Water conducts. It will knock the fire down and electrocute whoever is holding the nozzle.' },
        D        = { effectiveness = -1.00, hazard = 'explosion',
                     note = 'Water on burning metal dissociates into hydrogen and oxygen. It explodes.' },
        K        = { effectiveness = -0.80, hazard = 'flare',
                     note = 'Water flashes to steam under the oil and throws burning grease across the room.' },
        gas      = { effectiveness = 0.20,
                     note = 'Cools exposures. Does not address a fire that is being fed.' },
        wildland = { effectiveness = 1.10 },
        vehicle  = { effectiveness = 0.90 },
    },

    foam = {
        A        = { effectiveness = 1.15 },
        B        = { effectiveness = 1.80,
                     note = 'The correct agent. The blanket also stops it reflashing.' },
        C        = { effectiveness = 0.25, hazard = 'shock' },
        D        = { effectiveness = -0.90, hazard = 'explosion',
                     note = 'Foam is mostly water, and burning metal does not care that it is foamy.' },
        K        = { effectiveness = 0.40,
                     note = 'Better than water, but wet chemical is what the hood system uses for a reason.' },
        gas      = { effectiveness = 0.20 },
        wildland = { effectiveness = 1.30 },
        vehicle  = { effectiveness = 1.40 },
    },

    dry_chem = {
        A        = { effectiveness = 0.70,
                     note = 'Knocks flame down but does not soak the fuel, so deep-seated Class A reflashes.' },
        B        = { effectiveness = 1.50 },
        C        = { effectiveness = 1.60,
                     note = 'Non-conductive. The right answer for energized equipment.' },
        D        = { effectiveness = 0.00,
                     note = 'ABC dry chemical is not Class D dry powder. It does nothing here.' },
        K        = { effectiveness = 0.50 },
        gas      = { effectiveness = 0.90 },
        wildland = { effectiveness = 0.30 },
        vehicle  = { effectiveness = 0.80 },
    },

    co2 = {
        A        = { effectiveness = 0.35, note = 'No cooling and no residue, so Class A comes straight back.' },
        B        = { effectiveness = 1.20 },
        C        = { effectiveness = 1.50, note = 'Clean and non-conductive -- good around electronics.' },
        D        = { effectiveness = -0.30, hazard = 'reaction' },
        K        = { effectiveness = 0.30 },
        gas      = { effectiveness = 0.60 },
        wildland = { effectiveness = 0.10 },
        vehicle  = { effectiveness = 0.40 },
    },

    wet_chem = {
        A        = { effectiveness = 0.60 },
        B        = { effectiveness = 0.70 },
        C        = { effectiveness = 0.20, hazard = 'shock' },
        D        = { effectiveness = -0.70, hazard = 'explosion' },
        K        = { effectiveness = 2.00,
                     note = 'Saponifies the oil into a soapy crust. Purpose-built, and it shows.' },
        gas      = { effectiveness = 0.20 },
        wildland = { effectiveness = 0.30 },
        vehicle  = { effectiveness = 0.40 },
    },

    dry_powder = {
        A        = { effectiveness = 0.30 },
        B        = { effectiveness = 0.60 },
        C        = { effectiveness = 0.70 },
        D        = { effectiveness = 1.90,
                     note = 'The only thing on this list that works on burning metal.' },
        K        = { effectiveness = 0.30 },
        gas      = { effectiveness = 0.40 },
        wildland = { effectiveness = 0.20 },
        vehicle  = { effectiveness = 0.40 },
    },
}

--- What each hazard does when it fires.
MIFireAgents.hazards = {
    --- Applying water to a liquid pool: the incident grows.
    spread = {
        chancePerTick = 22.0,
        spawnNodes = 1,
        spawnRadius = 5.0,
        intensityBoost = 8.0,
        notify = 'The stream is pushing the fire, not killing it.',
    },

    --- Water on energized equipment: the stream conducts back up to the nozzle.
    shock = {
        chancePerTick = 14.0,
        damage = 35.0,
        ragdollMs = 3500,
        --- Holding the nozzle is what gets you hurt. Backup crew take less.
        backupDamageFraction = 0.35,
        notify = 'The stream conducted back up the line.',
    },

    --- Water on burning metal.
    explosion = {
        chancePerTick = 18.0,
        radius = 8.0,
        damage = 90.0,
        cameraShake = 1.2,
        notify = 'It went off.',
    },

    --- Water into hot cooking oil.
    flare = {
        chancePerTick = 30.0,
        radius = 4.0,
        damage = 45.0,
        intensityBoost = 20.0,
        spawnNodes = 2,
        spawnRadius = 3.0,
        notify = 'The grease flashed.',
    },

    --- CO2 or powder reacting badly.
    reaction = {
        chancePerTick = 12.0,
        intensityBoost = 12.0,
        notify = 'That made it worse.',
    },
}

--- Baseline knockdown. Multiplied by agent effectiveness, divided by class resistance,
--- and scaled by flow, so a 2.5 inch line genuinely does more than a booster line.
MIFireAgents.suppression = {
    --- Intensity removed per second at a reference flow of 150 gpm with a 1.0 agent.
    intensityPerSecondAtReferenceFlow = 9.0,
    referenceFlowGpm = 150.0,

    --- Flow above the reference keeps helping, but with diminishing returns -- past a
    --- point you are wetting things that are already wet.
    flowExponent = 0.75,

    --- Maximum useful distance from nozzle to node, metres.
    maxRange = 22.0,
    --- Effectiveness at maximum range, relative to point blank.
    rangeFalloff = 0.45,

    --- An extinguisher is not a hose line. Flat rate, short range, small supply.
    extinguisher = {
        intensityPerSecond = 4.0,
        maxRange = 6.0,
    },
}

return MIFireAgents
