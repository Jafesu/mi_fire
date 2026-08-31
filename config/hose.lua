--- Hose, nozzles, and how many people it takes to hold a line.
---
--- The hydraulics in `shared/hydraulics.lua` are published fire service figures and are not
--- tuning values. **This file is the tuning surface.** Everything here is a gameplay decision
--- about how a real constraint should feel, and every number in it can be moved without the
--- resource starting to lie to a pump operator who knows the real ones.
---
--- The design point worth protecting: **a bigger line is not simply better.** It flows more
--- water and it costs more people, more pressure and more time, and a crew that reaches for
--- the 2.5 inch on every call will be slow to every fire. Choosing the line is the decision,
--- and it is only a decision if the wrong choice costs something.

MIFireHose = {}

-- ---------------------------------------------------------------------------
-- Diameters
-- ---------------------------------------------------------------------------

--- One entry per hose size, keyed by diameter in inches.
---
--- `crew` is the number of people to work the line **at its rated flow**. Under-crewed does
--- not mean forbidden -- one firefighter can absolutely open a 2.5 inch, and then wear it.
--- See `MIFireHose.underCrewed` below.
MIFireHose.sizes = {

    --- Booster reel. Permanently plumbed hard rubber on a reel.
    ---
    --- Here because the rigs carry one and crews reach for it, not because it is useful on a
    --- fire. See the note on `preconnected.reel` in `config/apparatus.lua`: the friction loss
    --- is brutal and the flow is a fraction of an attack line. Right for a rubbish fire, a
    --- car, grass, or washing down. Wrong for anything in a structure.
    [1.0] = {
        label = 'Booster reel',
        crew = 1,
        gpmRange = { 20.0, 60.0 },
        --- Per 50ft section, or per foot for a reel since it comes off continuously.
        sectionFeet = 50,
        --- Kilograms of drag per 50ft, charged. What makes a big line heavy to move.
        dragPerSection = 4.0,
        --- Rewound rather than repacked. That is the appeal, and it is why it gets used when
        --- it should not be.
        reel = true,
        nozzles = { 'fog_lowpressure' },
    },

    --- The standard attack line. Fast, one or two people, enough for a room and contents.
    [1.75] = {
        label = '1¾″ attack line',
        crew = 2,
        gpmRange = { 95.0, 200.0 },
        sectionFeet = 50,
        dragPerSection = 11.0,
        nozzles = { 'fog', 'fog_lowpressure', 'smoothbore_15_16' },
    },

    --- The big line. Twice the water and considerably more than twice the trouble.
    ---
    --- Three people is not padding: a charged 2.5 inch at 250 gpm produces enough nozzle
    --- reaction to take a single firefighter off their feet, which is why it is worked from a
    --- knee or from a strap in real life.
    [2.5] = {
        label = '2½″ handline',
        crew = 3,
        gpmRange = { 200.0, 325.0 },
        sectionFeet = 50,
        dragPerSection = 21.0,
        nozzles = { 'smoothbore_1_1_8', 'fog', 'smoothbore_1_1_4' },
    },

    --- Supply, not attack. Feeds another appliance rather than a nozzle.
    [3.0] = {
        label = '3″ supply',
        crew = 2,
        gpmRange = { 250.0, 500.0 },
        sectionFeet = 50,
        dragPerSection = 27.0,
        supplyOnly = true,
        nozzles = {},
    },

    --- Large diameter hose. The hydrant line.
    ---
    --- Uncharged it is dragged; charged it is furniture. That is realistic and it is the
    --- reason laying a supply line is a decision made on approach rather than an afterthought
    --- once the tank runs dry.
    [5.0] = {
        label = '5″ LDH',
        crew = 2,
        gpmRange = { 500.0, 1500.0 },
        sectionFeet = 100,
        dragPerSection = 52.0,
        supplyOnly = true,
        nozzles = {},
    },
}

-- ---------------------------------------------------------------------------
-- Being under-crewed
-- ---------------------------------------------------------------------------

--- What happens when fewer people are on a line than it wants.
---
--- Never a refusal. A firefighter who wants to try a 2.5 inch alone should be allowed to find
--- out, and the finding out is the lesson -- a rule that says "you may not" teaches nothing
--- and reads as the script being in charge.
---
--- Every effect scales with how far below the requirement the crew is, so one short is
--- awkward and two short is unworkable.
MIFireHose.underCrewed = {
    --- Flow ceiling as a fraction of the line's maximum, at one crew short.
    flowCeilingPerMissing = 0.55,

    --- How much the nozzle wanders, in degrees of aim drift per missing crew member.
    aimDriftPerMissing = 7.0,

    --- Chance per second of losing the line entirely, per missing crew member. Losing it means
    --- a whipping charged hose, which hurts.
    lossChancePerMissing = 0.04,

    --- Damage when a line gets away from you.
    whipDamage = 12.0,

    --- Seconds before it can be picked back up.
    recoverySeconds = 4.0,
}

-- ---------------------------------------------------------------------------
-- Nozzles
-- ---------------------------------------------------------------------------

--- Nozzle pressures are real and live in `shared/hydraulics.lua`. What is here is what the
--- nozzle *does* -- pattern, reach, and how it applies water.
MIFireHose.nozzles = {
    fog = {
        label = 'Fog nozzle',
        --- 100 psi at the tip. The conventional combination nozzle.
        nozzlePressure = 100.0,
        patterns = { 'straight', 'narrow', 'wide' },
        defaultPattern = 'straight',
        --- Metres of reach at each pattern. A wide fog protects a crew and reaches nowhere.
        reach = { straight = 18.0, narrow = 12.0, wide = 5.0 },
        --- How much of the flow lands on the fire rather than on the room.
        efficiency = { straight = 1.0, narrow = 0.85, wide = 0.55 },
        --- A wide fog moves air, which is a tactic and a hazard.
        entrains = { straight = 0.0, narrow = 0.2, wide = 1.0 },
    },

    fog_lowpressure = {
        label = 'Low pressure fog',
        nozzlePressure = 75.0,
        patterns = { 'straight', 'narrow', 'wide' },
        defaultPattern = 'straight',
        reach = { straight = 15.0, narrow = 10.0, wide = 4.5 },
        efficiency = { straight = 1.0, narrow = 0.85, wide = 0.55 },
        entrains = { straight = 0.0, narrow = 0.2, wide = 1.0 },
    },

    --- Smooth bore. Lower pressure, better reach, no pattern to get wrong.
    ---
    --- Flow is not chosen -- it falls out of the tip size and the nozzle pressure through
    --- `Q = 29.7·d²·√NP`, which is why a smooth bore is predictable and a fog nozzle is not.
    smoothbore_15_16 = {
        label = '15/16″ smooth bore',
        nozzlePressure = 50.0,
        tipInches = 0.9375,
        patterns = { 'solid' },
        defaultPattern = 'solid',
        reach = { solid = 21.0 },
        efficiency = { solid = 1.0 },
        entrains = { solid = 0.0 },
    },

    smoothbore_1_1_8 = {
        label = '1⅛″ smooth bore',
        nozzlePressure = 50.0,
        tipInches = 1.125,
        patterns = { 'solid' },
        defaultPattern = 'solid',
        reach = { solid = 23.0 },
        efficiency = { solid = 1.0 },
        entrains = { solid = 0.0 },
    },

    smoothbore_1_1_4 = {
        label = '1¼″ smooth bore',
        nozzlePressure = 50.0,
        tipInches = 1.25,
        patterns = { 'solid' },
        defaultPattern = 'solid',
        reach = { solid = 25.0 },
        efficiency = { solid = 1.0 },
        entrains = { solid = 0.0 },
    },
}

-- ---------------------------------------------------------------------------
-- Working a line
-- ---------------------------------------------------------------------------

MIFireHose.work = {
    --- Seconds to shoulder a preconnected load off the bed.
    pullSeconds = 4.0,

    --- Seconds to couple a length to a discharge, an appliance, or another length.
    connectSeconds = 3.0,

    --- Seconds to break a coupling.
    disconnectSeconds = 2.0,

    --- Seconds to repack a bed per 50ft section. Slow on purpose: repacking is the price of
    --- pulling a line, and a crew that pulls three and repacks none is a crew that runs out
    --- of hose. A reel is rewound instead and is much faster, which is its whole appeal.
    repackSecondsPerSection = 12.0,
    rewindSecondsPerSection = 3.0,

    --- How far a length can be dragged from its coupling before it will not stretch further.
    stretchTolerance = 1.5,

    --- Metres a charged line can be dragged per second, before crew weight.
    dragSpeed = 1.1,
}

-- ---------------------------------------------------------------------------
-- What a hose looks like
-- ---------------------------------------------------------------------------

--- No custom asset is needed, and that is worth stating because it is not obvious.
---
--- The line itself is a GTA **rope**, not a model: `AddRope` renders a physical, simulated,
--- collidable line that sags under its own weight and follows both ends. Nothing anyone could
--- author as a prop would behave better, and a prop would need a compile step this project
--- has no way to run.
---
--- Every name here is verified in something already running on this machine rather than taken
--- from a list -- rope type 4 is what the fire hose resource on this drive uses, and the props
--- are base game. Same rule as the particle pairs and the roll animation, for the same reason:
--- a wrong name here fails silently.
MIFireHose.visuals = {
    --- Draw hose lines at all. Off turns the rope off and leaves the mechanic working, which
    --- is worth having while the rendering is the least proven part of the system.
    enabled = true,

    --- Rope type. 4 is the one a working hose resource uses; 7 is thicker, for LDH.
    ropeType = 4,
    ropeTypeLarge = 7,

    --- Diameter above which the thicker rope is used, in inches.
    largeAbove = 2.5,

    --- Length the rope is created at, in metres, before it starts paying out.
    ---
    --- Short. A rope created at its full two hundred feet between two points five metres apart
    --- is a heap rather than a hose; this is the length it has while the crew is still at the
    --- rig, and it grows as they walk.
    initialLength = 12.0,

    --- Slack, as a fraction of the distance between the two ends.
    ---
    --- The rope is kept at roughly this much more than the span, and pays out as the crew walks
    --- away. Creating it at its full length instead gives sixty metres of rope between two
    --- points five metres apart, which is a heap rather than a hose; creating it at exactly the
    --- span gives a tow cable. Raise it for a lazier, more realistic lay.
    slack = 0.35,

    --- Props. Base game, all four confirmed present in resources on this machine.
    --- Nothing, by default. There is no vanilla prop that looks like a nozzle --
    --- prop_fire_hosereel_l1 is the reel itself, and in hand it reads as a firefighter
    --- carrying a large flat coil. Better nothing in the hand than the wrong thing.
    nozzleProp = nil,
    couplingProp = 'prop_fire_hosebox_01',
    reelProp = 'prop_fire_hosereel',

    --- How often a laid line's shape is re-synced to other players, in ms. A rope is
    --- simulated locally, so this only has to agree about the *ends*.
    syncMs = 500,
}

--- Maximum lengths a single line may be built from, so nobody lays a mile of hose off one
--- discharge and stalls the water graph.
MIFireHose.maxSections = 20
