--- Per-vehicle truth: what each rig carries, and where things are on it.
---
--- This is the file `/fireoffset` writes into, and almost everything after Phase 2 reads from
--- it. A hose connects to a `port` on this list; the pump panel binds its discharges to the
--- same `portId`s; the SCBA rack, the gear compartment and the ladder rack are all ports.
---
--- **Ports cannot be authored from disk.** Both vehicle packs ship `RSC7`-compressed models,
--- so bone names and geometry cannot be read from the files at all. Every offset here has to
--- be found in game with `/fireoffset` and pasted back. Anything that claims otherwise was
--- guessed, and a guessed discharge is a hose connecting to thin air.
---
--- Offsets are **local to the vehicle**, in metres, `x` right, `y` forward, `z` up, exactly as
--- `GetOffsetFromEntityInWorldCoords` takes them. That is deliberate: the same numbers work on
--- a rig parked at any angle, which a world coordinate does not.

MIFireApparatus = {}

--- Port types. A port is any place on a rig you can interact with.
---
--- Kept as a closed set because the pump panel validates its discharges against this at boot,
--- and a typo in a `type` should be a startup error rather than a control that silently does
--- nothing at an incident.
MIFireApparatus.portTypes = {
    discharge   = true,   -- water out: crosslays, rear beds, LDH, deck gun feed
    intake      = true,   -- water in: hydrant supply, draft, tank fill
    hosebed     = true,   -- where a line is pulled from
    deckgun     = true,   -- the monitor itself
    panel       = true,   -- where the pump panel NUI is opened
    gear        = true,   -- turnout compartment
    scba_rack   = true,   -- bottles
    ladder_rack = true,   -- ground ladders
    tool        = true,   -- general compartment
}

--- Defaults merged under every profile, so a new rig only declares what differs.
MIFireApparatus.defaults = {
    --- Water on board, US gallons. A real engine carries 500-1000; the tank is the clock
    --- you are working against until a supply line is established.
    tankGallons = 750.0,

    --- Foam concentrate, gallons. Nil means no foam system at all, which is different from
    --- an empty cell -- one is a rig that cannot do Class B, the other is one that has run out.
    foamGallons = nil,

    --- Rated pump capacity, GPM at 150 psi. Feeds the NFPA 1901 curve in
    --- `shared/hydraulics.lua`, so this is the number the whole pressure model hangs off.
    pumpRatingGpm = 1500.0,

    --- Highest discharge pressure the pump will produce before the relief valve opens.
    maxDischargePsi = 250.0,

    --- Can it pump while moving? Brush rigs can; almost nothing else should.
    pumpAndRoll = false,

    --- Panel layout family. See `docs/internal/adr/0003-panels-are-data-not-code.md`.
    panelFamily = 'engine',

    --- Does opening the panel physically deploy it on the model? Only true where the pack
    --- actually ships the geometry -- see `docs/internal/APPARATUS.md`.
    deployPanelMod = false,

    --- Ports, authored with `/fireoffset`. Empty until someone stands at the rig and does it.
    ports = {},
}

--- One entry per model.
---
--- Keyed by **model name**, lowercase. Resolved to a hash at boot, because a hash literal in a
--- config file is unreadable and the Lua 5.1 parse gate the tests run under rejects the
--- backtick form outright.
MIFireApparatus.profiles = {

    -- --- 2026 fire truck pack ------------------------------------------------------------
    -- The primary fleet. Six Pierce-style rigs; four ship modelled pump panels, which is why
    -- panel families are a fact about the trucks rather than a taxonomy we invented.

    ['eengineht'] = {
        label = 'Engine',
        tankGallons = 750.0,
        foamGallons = 30.0,
        pumpRatingGpm = 1500.0,
        panelFamily = 'engine',
        deployPanelMod = true,
        ports = {
            { id = "hosebed1", type = "hosebed", x = -0.086, y = -4.142, z = 0.853, heading = 180.0 },
            { id = "pumppanel", type = "panel", x = -0.902, y = 0.186, z = -0.328, heading = 105.0 },
            { id = "gear1", type = "gear", x = -1.238, y = -2.054, z = 0.159, heading = 90.0 },
            { id = "toolcompartment", type = "tool", x = -1.238, y = -2.054, z = 0.159, heading = 90.0 },
            { id = "scba_rack1", type = "scba_rack", x = -1.238, y = -3.709, z = 0.221, heading = 90.0 },
            { id = "ladder_rack", type = "ladder_rack", x = 0.934, y = -2.446, z = 0.467, heading = 270.0 },
            { id = "discharge1", type = "discharge", x = -0.894, y = 0.178, z = -0.435, heading = 90.0 },
            { id = "discharge2", type = "discharge", x = -0.893, y = -0.260, z = -0.394, heading = 90.0 },
            { id = "intake1", type = "intake", x = -0.894, y = -0.060, z = -0.942, heading = 90.0 },
            { id = "discharge3", type = "discharge", x = -1.044, y = 0.440, z = -0.913, heading = 90.0 },
        },
    },

    ['epucht'] = {
        label = 'PUC Engine',
        tankGallons = 500.0,
        foamGallons = 30.0,
        pumpRatingGpm = 1500.0,
        --- Pierce Ultimate Configuration is a single-pump architecture with no separate pump
        --- house, operated differently from a conventional midship pumper. Its own family,
        --- not a skin.
        panelFamily = 'puc',
        deployPanelMod = true,
    },

    ['eladderlt'] = {
        label = 'Aerial Ladder',
        tankGallons = 300.0,
        pumpRatingGpm = 1500.0,
        panelFamily = 'ladder',
        deployPanelMod = true,
        --- The ladder pipe is a master stream a hundred feet up, which is where the elevation
        --- term in `shared/hydraulics.lua` finally earns its place.
        aerial = { maxHeightFeet = 100.0, hasLadderPipe = true },
    },

    ['etowerlt'] = {
        label = 'Tower Ladder',
        tankGallons = 300.0,
        pumpRatingGpm = 1500.0,
        panelFamily = 'tower',
        deployPanelMod = true,
        aerial = { maxHeightFeet = 95.0, hasLadderPipe = true, platform = true },
    },

    ['etankerht'] = {
        label = 'Tanker',
        --- The whole point of the rig. A tanker is a shuttle, not an attack piece, and its
        --- tank is an order of magnitude past an engine's.
        tankGallons = 3000.0,
        pumpRatingGpm = 750.0,
        maxDischargePsi = 200.0,
        panelFamily = 'tanker',
        dumpValve = true,
    },

    ['erescueht'] = {
        label = 'Heavy Rescue',
        --- Little or no pump. Confirm on the model before building a panel for it.
        tankGallons = 0.0,
        pumpRatingGpm = 0.0,
        panelFamily = 'rescue',
    },

    -- --- Outside that pack ----------------------------------------------------------------

    --- Both of these are in service on this server -- there are panel photographs for them in
    --- `docs/Reference/PumpPanels/`, which is the evidence they exist. Their figures are
    --- conventional engine values and should be corrected against the real rigs.
    ['enforcereng'] = {
        label = 'Enforcer Engine',
        tankGallons = 750.0,
        foamGallons = 30.0,
        pumpRatingGpm = 1500.0,
        panelFamily = 'engine',
    },

    ['engine1'] = {
        label = 'Engine',
        tankGallons = 750.0,
        foamGallons = 20.0,
        pumpRatingGpm = 1250.0,
        panelFamily = 'engine',
    },

    ['brushtruck'] = {
        label = 'Brush Truck',
        tankGallons = 400.0,
        pumpRatingGpm = 250.0,
        maxDischargePsi = 150.0,
        --- The only family that can flow while moving, which is the whole tactic for a
        --- wildland rig and something no other family does.
        pumpAndRoll = true,
        panelFamily = 'brush',
        --- Ships no mod kit at all -- it uses extras rather than mod slots, so there is no
        --- panel geometry to deploy and the NUI opens on its own. That makes it the honest
        --- test of the generated fallback panel.
        deployPanelMod = false,
    },
}

--- What to do about a fire vehicle with no profile.
---
--- `true` treats any emergency-class vehicle as a generic engine, so a server running rigs
--- nobody has authored yet is usable rather than broken. The generated pump panel exists for
--- the same reason. Set `false` once your fleet is authored, so an unconfigured rig is
--- obvious instead of quietly behaving like something it is not.
MIFireApparatus.allowUnprofiled = true

--- The profile an unprofiled emergency vehicle gets, when the above is true.
MIFireApparatus.unprofiled = {
    label = 'Apparatus',
    tankGallons = 500.0,
    pumpRatingGpm = 1000.0,
    panelFamily = 'engine',
}
