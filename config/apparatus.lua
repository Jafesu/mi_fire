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
    --- Water out: crosslays, rear beds, LDH, deck gun feed, and the line that fills another
    --- rig's tank.
    ---
    --- **What a crosslay is.** A preconnected attack line -- also called a mattydale or a
    --- speedlay -- stored in a *transverse* bed above the pump, running side to side so it can
    --- be pulled from either side of the rig. Usually 1.75 inch, 150 to 250 feet, already
    --- coupled to its discharge. It is the first line off the truck at a house fire, and it is
    --- the reason an engine can put water on a fire within seconds of stopping.
    ---
    --- It is **not** anything to do with moving water between apparatus. That confusion is
    --- easy to have and worth writing down: rig-to-rig transfer is a `discharge` on the
    --- supplying engine connected to an `intake` on the receiving one, and the same intake
    --- takes a hydrant supply line. Some rigs also carry a dedicated direct tank fill inlet;
    --- model that as another `intake` unless it needs to behave differently.
    ---
    --- A crosslay is a discharge with hose already on it, which is what `preconnected`
    --- describes:
    ---
    ---     { id = 'crosslay1', type = 'discharge', x = ..., y = ..., z = ...,
    ---       size = 1.75, preconnected = { feet = 200 } }
    ---
    --- **A booster reel** -- the "REEL" discharge on the panel, also called a red line -- is
    --- the same idea with two differences that matter:
    ---
    ---     { id = 'reel', type = 'discharge', x = ..., y = ..., z = ...,
    ---       size = 1.0, preconnected = { feet = 200, reel = true } }
    ---
    --- It is permanently plumbed hard rubber hose on a fixed reel, so it is pulled and
    --- **rewound** rather than pulled and repacked -- one person, seconds, no reloading the
    --- bed afterwards. That convenience is the entire appeal and the entire danger.
    ---
    --- At three quarters or one inch it flows a fraction of what a crosslay does, and the
    --- friction loss is brutal: `shared/hydraulics.lua` carries the real coefficients, 1100
    --- for 0.75 inch and 150 for 1 inch, against 15.5 for a 1.75 inch crosslay. Two hundred
    --- feet of booster line at any useful flow eats more pressure than the line is worth.
    ---
    --- So it is right for a rubbish fire, a car fire, a grass fire, or washing a scene down,
    --- and **badly wrong for anything in a structure**. Pulling the red line on a room and
    --- contents fire is a real and recurring mistake, and it should be one here too: nothing
    --- special-cases it, the flow is simply too small to knock the fire down, and the crew
    --- finds out while the fire keeps growing. That falls out of the hydraulics rather than
    --- being scripted, which is the correct way for a lesson to arrive.
    ---
    --- A crosslay or a reel having its own port type would mean the pump panel, the hydraulics
    --- and the hose system each having to know that several names mean one thing. On the real
    --- rig it is all the same plumbing, with a gauge and a valve on the panel exactly like the
    --- rear bed.
    discharge   = true,
    --- Water in: a hydrant supply line, a draft from open water, or another rig's discharge
    --- filling this one's tank. All three arrive the same way, so they are one type.
    intake      = true,
    hosebed     = true,   -- where a line is pulled from
    deckgun     = true,   -- the monitor itself
    panel       = true,   -- where the pump panel NUI is opened
    gear        = true,   -- turnout compartment
    scba_rack   = true,   -- bottles
    ladder_rack = true,   -- ground ladders
    tool        = true,   -- general compartment
}

--- Which port types are an area, and which are a single fitting.
---
--- The distinction is physical rather than a setting. A gear locker, a hose bed, a bottle rack
--- and a pump panel are **places on the rig** -- a metre and a half of compartment, or most of
--- its length -- and making someone aim at one point to open a locker is precision for its own
--- sake. A discharge or an intake is a **fitting**: a specific piece of brass you couple a
--- specific line to, and being asked which one is the interaction rather than an obstacle.
---
--- So zone ports carry `corners` -- four points walked around the compartment -- and point
--- ports carry a position and nothing else.
MIFireApparatus.portShapes = {
    gear        = 'zone',
    tool        = 'zone',
    hosebed     = 'zone',
    scba_rack   = 'zone',
    ladder_rack = 'zone',
    panel       = 'zone',

    --- Fittings. You point at the one you want.
    discharge   = 'point',
    intake      = 'point',
    deckgun     = 'point',
}

--- How close counts, for a point port. One number, because a fitting is a fitting.
---
--- Deliberately tight. The outlets on a real rig are inches apart, and a generous radius on six
--- adjacent discharges means picking from a list of six identical options instead of pointing
--- at the one you want.
MIFireApparatus.pointReach = 0.55

--- How tall a zone is, in metres, when its corners do not imply one.
---
--- The corners give the footprint; this gives the height, centred on the average height of the
--- four points. Walk the corners at roughly the height of the compartment opening and the zone
--- lands around it.
MIFireApparatus.zoneHeight = {
    gear        = 1.8,
    tool        = 1.8,
    hosebed     = 1.6,
    scba_rack   = 1.6,
    ladder_rack = 1.4,
    panel       = 1.8,
    default     = 1.6,
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
            --- A hose bed runs most of the width of the rig, so it is a box rather than a
            --- sphere. Boxes are vehicle-aligned, so this stays correct however it is parked.
            { id = "hosebed1", type = "hosebed",
              corners = {
                { x = -1.286, y = -4.942, z = 0.853 },
                { x = 1.114, y = -4.942, z = 0.853 },
                { x = 1.114, y = -3.342, z = 0.853 },
                { x = -1.286, y = -3.342, z = 0.853 },
              } },
            { id = "pumppanel", type = "panel",
              corners = {
                { x = -1.402, y = -0.714, z = -0.328 },
                { x = -0.402, y = -0.714, z = -0.328 },
                { x = -0.402, y = 1.086, z = -0.328 },
                { x = -1.402, y = 1.086, z = -0.328 },
              } },
            --- Gear and tools share one compartment, so they share a box. Two options on
            --- one locker is correct -- it is one locker.
            { id = "gear1", type = "gear",
              corners = {
                { x = -1.738, y = -2.954, z = 0.159 },
                { x = -0.738, y = -2.954, z = 0.159 },
                { x = -0.738, y = -1.154, z = 0.159 },
                { x = -1.738, y = -1.154, z = 0.159 },
              } },
            { id = "toolcompartment", type = "tool",
              corners = {
                { x = -1.738, y = -2.954, z = 0.159 },
                { x = -0.738, y = -2.954, z = 0.159 },
                { x = -0.738, y = -1.154, z = 0.159 },
                { x = -1.738, y = -1.154, z = 0.159 },
              } },
            { id = "scba_rack1", type = "scba_rack",
              corners = {
                { x = -1.738, y = -4.409, z = 0.221 },
                { x = -0.738, y = -4.409, z = 0.221 },
                { x = -0.738, y = -3.009, z = 0.221 },
                { x = -1.738, y = -3.009, z = 0.221 },
              } },
            --- Ladders run nearly the length of the rig.
            { id = "ladder_rack", type = "ladder_rack",
              corners = {
                { x = 0.434, y = -4.446, z = 0.467 },
                { x = 1.434, y = -4.446, z = 0.467 },
                { x = 1.434, y = -0.446, z = 0.467 },
                { x = 0.434, y = -0.446, z = 0.467 },
              } },
            --- The outlets are inches apart on a real rig, so these zones overlap and
            --- ox_target offers several at once. That is correct rather than a problem, but
            --- only while every option says which outlet it is -- two entries both reading
            --- "connect a line" is the failure the labels exist to prevent.
            ---
            --- **Rename these to match the panel tags.** The panel gauges are colour coded
            --- and each outlet carries a matching tag, so `discharge_green` and a green gauge
            --- agree by construction and Phase 4 binds to them without a second list.
            { id = "discharge1", type = "discharge", x = -0.894, y = 0.178, z = -0.435, heading = 90.0,
              label = "Panel discharge, upper front", size = 2.5 },
            { id = "discharge2", type = "discharge", x = -0.893, y = -0.260, z = -0.394, heading = 90.0,
              label = "Panel discharge, upper rear", size = 2.5 },
            --- The steamer. Large diameter, so this is the hydrant and the rig-to-rig fill.
            { id = "intake1", type = "intake", x = -0.894, y = -0.060, z = -0.942, heading = 90.0,
              label = "Steamer intake", size = 5.0 },
            { id = "discharge3", type = "discharge", x = -1.044, y = 0.440, z = -0.913, heading = 90.0,
              label = "Panel discharge, lower", size = 2.5 },
            { id = "rear_purple", type = "discharge", x = -0.389, y = -4.699, z = -0.266, heading = 180.0,
              label = "Rear discharge (purple)", size = 2.5 },
            --- Preconnected, so there is already hose on it and a crew pulls the load rather
            --- than connecting a line. 200ft of 1.75 inch is the conventional load; correct it
            --- against the rig if it carries something else.
            { id = "rear_crosslay_white", type = "discharge", x = -0.120, y = -4.469, z = -0.209, heading = 180.0,
              label = "Crosslay (white)", size = 1.75, preconnected = { feet = 200 } },

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
