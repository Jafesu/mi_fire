--- Fixed fire protection systems.
---
--- Sprinklers installed by the fire department in buildings. They are placed in game with
--- the same tool as station equipment and stored in MySQL, because a sprinkler layout is
--- something you build by walking a building, not something you type.
---
--- The design point worth protecting: **sprinklers buy time, they do not win.** A system
--- holds a fire down until its water runs out, and then the fire resumes. What the tank
--- buys is the time for a crew to arrive, and what the fire department connection buys is
--- the ability to keep the system running past that. A sprinkler system that simply put
--- fires out would delete the job.
---
--- The second design point: **sprinklers apply an agent, and the agent can be wrong.**
--- A water system over a commercial kitchen makes a Class K fire worse, exactly as it
--- would in reality, which is why real kitchens have wet-chemical hood systems instead.
--- That is not a bug to be special-cased away.

MIFireSprinklers = {}

--- Admin command that opens the sprinkler tool. Installation is a fire department job,
--- so it is gated on the fire job rather than on admin -- see `installRequiresAdmin`.
MIFireSprinklers.command = 'sprinkler'

--- Whether installing a new system needs admin, or any on-duty firefighter can do it.
--- Servers that want fire prevention to be a player activity set this false.
MIFireSprinklers.installRequiresAdmin = true

-- ---------------------------------------------------------------------------
-- System types
-- ---------------------------------------------------------------------------

--- How a system decides which heads flow.
---
--- The distinction that matters, and that fiction almost always gets wrong: on a normal
--- system **only the heads over the fire open**. Each head is an independent heat-
--- activated device. Deluge systems are the exception, and they exist for hazards where
--- soaking the whole room is the correct answer.
MIFireSprinklers.systemTypes = {

    wet = {
        label = 'Wet pipe',
        --- Pipes are always charged. Water arrives the instant a head fuses.
        activationDelaySeconds = 0.0,
        perHeadActivation = true,
        --- The common case, and the sensible default for most buildings.
        default = true,
    },

    dry = {
        label = 'Dry pipe',
        --- Pipes hold pressurised air; a valve releases water once pressure drops. That
        --- takes real time, and the fire grows during it.
        activationDelaySeconds = 25.0,
        perHeadActivation = true,
    },

    preaction = {
        label = 'Pre-action',
        --- Needs two events: a detector *and* a fused head. Used where an accidental
        --- discharge would be as expensive as the fire -- server rooms, archives.
        activationDelaySeconds = 8.0,
        perHeadActivation = true,
        requiresDetection = true,
    },

    deluge = {
        label = 'Deluge',
        --- Open heads, no heat element. One trip and the entire system flows.
        --- Correct for flammable liquid and aircraft hazards, ruinous anywhere else.
        activationDelaySeconds = 3.0,
        perHeadActivation = false,
        --- Drains its tank fast, because every head is flowing.
        allHeadsFlow = true,
    },
}

-- ---------------------------------------------------------------------------
-- Agents
-- ---------------------------------------------------------------------------

--- What a system discharges. Keys are agents from `shared/enums.lua`, so suppression runs
--- through the same `config/agents.lua` matrix a hose line does.
---
--- This is what makes installing the right system matter. A water system in a paint store
--- is not a partial win, it is an accelerant.
MIFireSprinklers.agents = {
    water = {
        label = 'Water',
        --- Multiplier on the tank, since water is what the tank holds.
        consumptionMultiplier = 1.0,
    },
    foam = {
        label = 'Foam-water',
        --- Correct for Class B occupancies. The concentrate runs out faster than plain
        --- water would, which is the trade for it working at all.
        consumptionMultiplier = 1.35,
    },
    wet_chem = {
        label = 'Wet chemical (kitchen hood)',
        --- Hood suppression over cooking equipment. Small charge, short duration, and
        --- the only correct answer over a fryer.
        consumptionMultiplier = 2.5,
    },
}

-- ---------------------------------------------------------------------------
-- Heads
-- ---------------------------------------------------------------------------

--- Sprinkler head types.
---
--- `temperatureRating` is the real fahrenheit figure and is what the label shows.
--- `activationHeat` is what the simulation actually tests: the heat load a head must see
--- before its element fuses, on the same 0-100 scale as `MIFireGear.exposure.heat`.
--- Both are here because the first is what a player recognises and the second is what the
--- engine can use.
---
--- `kFactor` sets flow: **Q = K x sqrt(P)**, the real orifice formula. A standard K5.6
--- head at 15 psi flows about 21.7 gpm.
MIFireSprinklers.headTypes = {

    ordinary = {
        label = 'Ordinary (135-170F)',
        temperatureRating = 155,
        activationHeat = 28.0,
        kFactor = 5.6,
        bulbColour = { r = 220, g = 40, b = 40 },      -- red
        coverageRadius = 3.6,                           -- metres, ~130 sq ft
        default = true,
    },

    intermediate = {
        label = 'Intermediate (175-225F)',
        temperatureRating = 200,
        activationHeat = 42.0,
        kFactor = 5.6,
        bulbColour = { r = 240, g = 220, b = 60 },      -- yellow
        coverageRadius = 3.6,
    },

    high = {
        label = 'High (250-300F)',
        temperatureRating = 286,
        activationHeat = 60.0,
        kFactor = 5.6,
        bulbColour = { r = 60, g = 130, b = 240 },      -- blue
        coverageRadius = 3.6,
    },

    extra_high = {
        label = 'Extra high (325-375F)',
        temperatureRating = 350,
        activationHeat = 78.0,
        kFactor = 5.6,
        bulbColour = { r = 170, g = 80, b = 220 },      -- purple
        coverageRadius = 3.6,
    },

    --- Large-drop / early-suppression heads. More water, wider coverage, drains faster.
    esfr = {
        label = 'ESFR (early suppression)',
        temperatureRating = 165,
        activationHeat = 26.0,
        kFactor = 14.0,
        bulbColour = { r = 220, g = 40, b = 40 },
        coverageRadius = 4.6,
    },
}

-- ---------------------------------------------------------------------------
-- Hydraulics
-- ---------------------------------------------------------------------------

MIFireSprinklers.hydraulics = {
    --- Pressure at the head when running off the system tank. Feeds Q = K x sqrt(P).
    --- Modest on purpose: a gravity or break tank is not a fire pump.
    tankPressurePsi = 15.0,

    --- Pressure at the head when an engine is pumping into the fire department
    --- connection. Higher pressure means more flow per head and better knockdown, which
    --- is the tactical reason to bother connecting.
    fdcPressurePsi = 45.0,

    --- Suppression strength relative to a hose line at the same flow. Sprinklers wet a
    --- wide area rather than putting a stream where it is needed, so they are worth less
    --- per gallon than a nozzle in a firefighter's hands.
    suppressionEfficiency = 0.7,
}

-- ---------------------------------------------------------------------------
-- Tanks
-- ---------------------------------------------------------------------------

MIFireSprinklers.tank = {
    --- Default capacity for a newly installed system, in gallons. At 15 psi a K5.6 head
    --- flows ~21.7 gpm, so this is roughly 15 minutes on two heads, or under 4 minutes
    --- if six open. That is the shape the whole feature depends on: long enough to
    --- matter, short enough that nobody relies on it.
    defaultGallons = 750.0,

    --- Bounds offered when installing or resizing a system.
    minimumGallons = 200.0,
    maximumGallons = 5000.0,

    --- Below this fraction the panel and the dispatch both report the system as failing,
    --- so a crew knows the clock is nearly up before it stops.
    lowWaterFraction = 0.20,
}

-- ---------------------------------------------------------------------------
-- Fire department connection
-- ---------------------------------------------------------------------------

--- The siamese inlet on the outside of the building an engine pumps into.
---
--- This is the tactical payoff of the whole system, and the reason a sprinkler is not
--- just scenery: when the tank runs dry, a crew that lays a line to the FDC keeps the
--- heads flowing off the engine instead of watching the building light back up.
MIFireSprinklers.fdc = {
    enabled = true,

    --- Supply diameters accepted. A 2.5 inch line into an FDC is standard.
    acceptedDiameters = { 2.5, 3.0 },

    --- Connecting also refills the system tank while flow is spare, so a crew can
    --- recharge a drained system without a full reset.
    refillsTankGpm = 60.0,

    --- Minimum engine discharge pressure for the FDC to do anything useful.
    minimumSupplyPsi = 100.0,
}

-- ---------------------------------------------------------------------------
-- Reset
-- ---------------------------------------------------------------------------

--- Putting a system back in service after it has run.
---
--- A fused sprinkler head is a one-time device -- the glass bulb is broken and the head
--- is scrap. Real reset means shutting the control valve, draining, replacing every head
--- that operated, refilling, and reopening. That is a genuine job, and modelling it is
--- what makes an activated system a consequence rather than a free save.
MIFireSprinklers.reset = {
    --- Steps in order. Each is an ox_target interaction at the relevant point.
    steps = {
        { id = 'close_valve',   label = 'Close the control valve',  seconds = 4.0,  at = 'riser' },
        { id = 'drain',         label = 'Drain the system',         seconds = 12.0, at = 'riser' },
        { id = 'replace_heads', label = 'Replace fused head',       seconds = 8.0,  at = 'head'  },
        { id = 'refill',        label = 'Refill the tank',          seconds = 20.0, at = 'riser' },
        { id = 'open_valve',    label = 'Return to service',        seconds = 4.0,  at = 'riser' },
    },

    --- Replacement heads are an inventory item when ox_inventory is present. Set to nil
    --- to make reset cost nothing but time.
    headItem = 'sprinkler_head',

    --- Refilling from an apparatus tank rather than a mains connection. Draws from the
    --- truck, which means a tender or a hydrant line, which means the reset is a real
    --- little operation rather than a button.
    refillFromApparatus = true,
    refillGpm = 250.0,

    --- A system left un-reset stays out of service. No timer quietly fixes it.
    autoResetSeconds = nil,
}

-- ---------------------------------------------------------------------------
-- Alarms and dispatch
-- ---------------------------------------------------------------------------

--- A flowing sprinkler is what actually calls the fire department to most commercial
--- fires. Modelling the waterflow alarm means a protected building generates its own
--- call, which is a genuinely different feel from a passer-by phoning it in.
MIFireSprinklers.alarm = {
    enabled = true,

    --- Seconds of continuous flow before the alarm transmits. Real systems use a retard
    --- to ride out pressure surges rather than calling out a crew for a water hammer.
    retardSeconds = 8.0,

    --- Dispatch presentation, merged over `Config.DispatchCalls.default`.
    dispatch = {
        code = '10-70A',
        title = 'Waterflow Alarm',
        priority = 'high',
    },

    --- Local audible bell at the riser, so anyone in the building knows.
    localBell = {
        enabled = true,
        range = 40.0,
    },

    --- A system that runs dry with fire still burning escalates, because the building has
    --- just lost its protection and the crew needs to know.
    depletionEscalates = true,
    depletionDispatch = {
        code = '10-70B',
        title = 'Sprinkler System Depleted',
        priority = 'high',
    },
}

-- ---------------------------------------------------------------------------
-- Impairment
-- ---------------------------------------------------------------------------

--- A system can be deliberately taken out of service -- for maintenance, or by an arsonist
--- who knows what they are doing. An impaired system does not flow.
MIFireSprinklers.impairment = {
    --- Anyone may close a control valve; that is how real buildings get burned down.
    --- Requiring the fire job here makes tampering impossible, which is less interesting.
    closingValveRequiresFireJob = false,

    --- An impaired system is visible on the riser and reported on any dispatch to that
    --- building, so a crew is told before they arrive rather than discovering it.
    reportOnDispatch = true,
}

return MIFireSprinklers
