--- Smoke.
---
--- Everything here exists so that smoke can be **read**. The four attributes -- volume,
--- velocity, density and colour -- are the ones a real officer uses on arrival, and the
--- conclusions they support (flashover coming, backdraft waiting) are the two moments where
--- reading correctly saves a crew.
---
--- The colours in particular are not decoration. Colour reports the stage of heating and,
--- through `travelToPale`, how far the smoke has come from the seat. Black at one window
--- and white at the eaves is one fire, not two -- and the black is nearer.

MIFireSmoke = {}

-- ---------------------------------------------------------------------------
-- Colour
-- ---------------------------------------------------------------------------

--- Base colour per stage of heating, 0-255.
---
---   white / light grey  moisture driving off. Early and cool.
---   pale yellow         fuel heating, still early.
---   brown / tan         unfinished wood off-gassing. **Brown means the fire is into the
---                       structure**, which is one of the most useful single reads there is.
---   near black          carbon rich and hot. This smoke is unburned fuel and it will
---                       burn violently the moment it finds air.
MIFireSmoke.stageColour = {
    incipient = { r = 232, g = 232, b = 236 },
    growth    = { r = 205, g = 198, b = 172 },
    pyrolysis = { r = 138, g = 104, b = 64  },
    developed = { r = 34,  g = 32,  b = 31  },
}

--- Pure carbon. What a sooty fuel pulls its colour toward regardless of how hot the fire
--- is -- a pool of diesel smokes black while it is still small, because sooting is a
--- property of the fuel and not of the temperature.
MIFireSmoke.sootColour = { r = 24, g = 22, b = 21 }

--- What smoke fades toward as it travels, cools, and filters through the building.
MIFireSmoke.travelColour = { r = 216, g = 216, b = 220 }

--- Metres of travel before smoke has substantially paled. Lower makes the difference
--- between openings more dramatic and easier to read.
MIFireSmoke.travelToPale = 22.0

--- Metres before smoke has thinned out, and before it has stopped moving under pressure.
MIFireSmoke.travelToThin = 26.0
MIFireSmoke.travelToStill = 14.0

-- ---------------------------------------------------------------------------
-- Ventilation
-- ---------------------------------------------------------------------------

--- The multiplier on everything.
---
--- A fire with nowhere to go builds pressure, burns incompletely, and produces dense dark
--- smoke -- which is why ventilation is a tactical decision rather than a detail. Getting
--- it right buys a crew the room; getting it wrong hands them a backdraft.
MIFireSmoke.ventilation = {
    --- Nothing open. The fire consumes its oxygen and drops back to smouldering: little
    --- visible flame, heavy smoke, pressure cycling in and out of every gap.
    --- Looks calmer than it is, which is exactly what makes it dangerous.
    sealed = {
        label = 'sealed',
        volumeMultiplier = 1.15,
        densityMultiplier = 1.45,
        velocityMultiplier = 0.30,   -- starved fires do not push
        flashoverMultiplier = 0.15,  -- not enough air to flash
        backdraftMultiplier = 1.60,  -- this is the backdraft condition
        --- A starved fire cannot keep growing.
        intensityCeiling = 55.0,
    },

    --- A door or a window, but not enough. The fire is ventilation-limited: hot, pressured,
    --- pushing turbulent smoke. This is the flashover condition.
    limited = {
        label = 'ventilation-limited',
        volumeMultiplier = 1.0,
        densityMultiplier = 1.15,
        velocityMultiplier = 1.10,
        flashoverMultiplier = 1.35,
        backdraftMultiplier = 0.25,
        intensityCeiling = 100.0,
    },

    --- Adequately opened. The fire burns freely and grows, but the smoke lifts and a crew
    --- can work under it. More fire, less surprise -- usually the right trade.
    open = {
        label = 'open',
        volumeMultiplier = 0.85,
        densityMultiplier = 0.70,
        velocityMultiplier = 0.55,
        flashoverMultiplier = 0.30,
        backdraftMultiplier = 0.0,
        intensityCeiling = 100.0,
    },
}

--- What a fresh indoor incident starts as. Most structure fires are found
--- ventilation-limited, because the building was shut when it started.
MIFireSmoke.defaultVentilation = 'limited'

--- Confinement. Smoke that cannot disperse is thicker and pushes harder.
MIFireSmoke.confinedVolumeMultiplier = 1.6
MIFireSmoke.confinedVelocityMultiplier = 1.4

-- ---------------------------------------------------------------------------
-- Thresholds
-- ---------------------------------------------------------------------------

--- Velocity above which smoke reads as turbulent rather than laminar.
---
--- The single most important threshold in the file. Turbulent smoke is heat-pushed, which
--- means the compartment has stopped absorbing heat and is giving it back.
MIFireSmoke.turbulentAbove = 0.55

--- Density multiplier per stage. Late-stage smoke carries far more unburned fuel.
MIFireSmoke.stageDensity = {
    incipient = 0.35,
    growth    = 0.65,
    pyrolysis = 0.9,
    developed = 1.25,
}

--- Risk above which a size-up warns.
MIFireSmoke.warnAbove = 0.45

--- Backdraft risk above which the smoke visibly pulses in and out.
--- The most recognisable backdraft sign there is, and the one to render.
MIFireSmoke.pulsingAbove = 0.45

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

MIFireSmoke.flashover = {
    enabled = true,
    --- Sustained seconds above `warnAbove` before it actually happens. The warning has to
    --- be long enough to act on, or reading smoke is pointless.
    warningSeconds = 25.0,
    --- Chance per second once the warning has elapsed.
    chancePerSecond = 12.0,
    --- Everything in the compartment lights.
    radius = 9.0,
    intensityJump = 60.0,
    spawnNodes = 5,
    --- Damage to anyone inside, before gear.
    damage = 95.0,
}

MIFireSmoke.backdraft = {
    enabled = true,
    --- Backdraft does not build to a timer. It waits, and it is *triggered* -- by someone
    --- opening the compartment. That is the whole character of it.
    triggeredByVentilation = true,
    --- Opening a sealed compartment from the wrong place. Vertical ventilation is safe;
    --- forcing a door at ground level is not.
    safeVentilation = 'vertical',
    radius = 14.0,
    intensityJump = 75.0,
    spawnNodes = 6,
    damage = 130.0,
    --- Thrown clear, which is what actually happens.
    knockbackForce = 12.0,
}

-- ---------------------------------------------------------------------------
-- Ventilation actions
-- ---------------------------------------------------------------------------

--- What a crew can do about it.
MIFireSmoke.actions = {
    force_door = {
        label = 'Force the door',
        seconds = 6.0,
        setsVentilation = 'open',
        --- Horizontal ventilation at ground level is what sets off a backdraft.
        triggersBackdraft = true,
    },
    take_window = {
        label = 'Take the window',
        seconds = 3.0,
        setsVentilation = 'limited',
        triggersBackdraft = true,
    },
    vertical_vent = {
        label = 'Cut the roof',
        seconds = 18.0,
        setsVentilation = 'open',
        --- Venting above the fire lets the heat and smoke go straight up rather than
        --- drawing air across it. This is the correct answer to a suspected backdraft and
        --- the reason roof work exists.
        triggersBackdraft = false,
        vertical = true,
        --- Lifting the smoke buys real time before flashover.
        flashoverRelief = 0.6,
    },
    close_up = {
        label = 'Close it up',
        seconds = 4.0,
        setsVentilation = 'sealed',
        triggersBackdraft = false,
    },
}

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

--- Which particle effect carries which behaviour.
---
--- Turbulent and laminar need genuinely different effects, not the same one at a different
--- rate. Boiling smoke and a lazy column look nothing alike, and telling them apart is the
--- most important read on the fireground.
---
--- These dictionary and effect names are verified working pairs. A name that is not in its
--- dictionary draws nothing and reports nothing.
MIFireSmoke.visual = {
    turbulentDict = 'core',
    turbulentName = 'ent_amb_smoke_foundry',

    laminarDict = 'scr_agencyheistb',
    laminarName = 'scr_env_agency3b_smoke',

    --- Height above the node for the plume as it leaves, and for the same smoke after it
    --- has drifted and cooled. The gap between the two is what makes the colour change
    --- visible from outside.
    seatHeight = 1.2,
    driftHeight = 5.0,

    --- Metres of travel the upper layer is rendered as having done. Raising this makes the
    --- top of a plume paler and the seat easier to locate.
    driftTravel = 14.0,
}

-- ---------------------------------------------------------------------------
-- Size-up vocabulary
-- ---------------------------------------------------------------------------

--- The words a size-up uses. Four bands each, low to high.
MIFireSmoke.words = {
    volume    = { 'light', 'moderate', 'heavy', 'massive' },
    velocity  = { 'lazy', 'steady', 'pushing', 'pushing hard' },
    density   = { 'thin', 'moderate', 'thick', 'impenetrable' },
    turbulent = 'boiling and turbulent',

    colour = {
        incipient = 'white',
        growth    = 'light grey',
        pyrolysis = 'brown',
        developed = 'black',
    },
}

--- What a size-up concludes, and at what fire rank it is offered.
---
--- Everyone sees the observation. The interpretation is gated, so the skill is taught
--- rather than replaced -- a probationary firefighter is told what they can see, and an
--- officer is told what it means.
MIFireSmoke.sizeup = {
    command = 'sizeup',
    --- Minimum job grade to receive the interpretation as well as the observation.
    interpretationGrade = 2,
    --- How far away a size-up can be performed.
    maxDistance = 60.0,

    conclusions = {
        flashover = 'That is heat-pushed. The compartment has stopped absorbing and is '
            .. 'giving it back. Expect flashover -- get a line in place or get out.',
        backdraft = 'Low velocity with that density means it is starved and breathing. '
            .. 'Do not open it at ground level. Vent it vertically first.',
        pyrolysis = 'Brown smoke means it is into the structural timber, not just the '
            .. 'contents.',
        clean = 'Smoke is lifting and thinning. It is finding air and burning cleanly.',
    },
}

return MIFireSmoke
