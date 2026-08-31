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

    --- Rope type. 6, chosen by looking at all eight side by side with `/fire ropetypes` --
    --- it is the thickest, which is the closest a built-in type gets to hose.
    ---
    --- The texture cannot be changed for one resource: it comes from a shared dictionary, and
    --- replacing it was confirmed in game to change every rope on the server including the
    --- rappel rescue line. So thickness is the whole of what is available here, and looking
    --- like actual hose waits for `HOSE-010`.
    ---
    --- **Not 7.** `mi_utils`' rappel uses it, and sharing a type means any later attempt to
    --- make one look different drags the other along.
    ropeType = 6,
    ropeTypeLarge = 6,

    --- Diameter above which the thicker rope is used, in inches.
    largeAbove = 2.5,

    --- Length the rope is created at, in metres, before it starts paying out.
    ---
    --- Short. A rope created at its full two hundred feet between two points five metres apart
    --- is a heap rather than a hose; this is the length it has while the crew is still at the
    --- rig, and it grows as they walk.
    --- Raised from 12: vertex count follows length, and a rope with only four vertices has
    --- every one of them pinned -- the hand takes the first and the coupling takes the last
    --- two, leaving no middle to hang. It drew taut and shook as the pins disagreed.
    initialLength = 25.0,

    --- Slack, as a fraction of the distance between the two ends.
    ---
    --- The rope is kept at roughly this much more than the span, and pays out as the crew walks
    --- away. Creating it at its full length instead gives sixty metres of rope between two
    --- points five metres apart, which is a heap rather than a hose; creating it at exactly the
    --- span gives a tow cable. Raise it for a lazier, more realistic lay.
    slack = 0.35,

    --- The nozzle in a firefighter's hands.
    ---
    --- **`WEAPON_MINOZZLE` is ours.** A real fog nozzle -- bale handle, pistol grip, toothed
    --- bumper -- built from a CAD model by `tools/assets/nozzle/`, which turns a 183,404
    --- triangle millimetre-scale STL into an 8,000 triangle drawable with the texture baked
    --- and embedded. Nothing is borrowed. See that directory's README for how to rebuild it,
    --- and `ASSET-001` for why borrowing was never going to work.
    ---
    --- A weapon rather than a prop, because a nozzle sprays and a prop cannot be fired. It is
    --- also what supplies the two-handed stance and the aiming, which is what holding a
    --- charged line looks like.
    ---
    --- Everything about how it *behaves* is inherited from the base game fire extinguisher --
    --- `AMMO_FIREEXTINGUISHER`, `FIRE_EXT_STRAFE`, `DamageType FIRE_EXTINGUISHER`. Those are
    --- Rockstar's own identifiers, so `data/weapons.meta` defines a new weapon without
    --- carrying anyone else's content. It does no damage: water knocking a fire down is this
    --- resource's own simulation, applied server-side.
    ---
    --- Made into a world object with `CreateWeaponObject` rather than given, so nothing is
    --- equipped and ox_inventory has nothing to strip.
    nozzleWeapon = 'WEAPON_MINOZZLE',

    --- The carrying stance -- and the honest state of it.
    ---
    --- **Both clipsets are off, because setting either one T-posed the ped while walking.**
    --- Without them the weapon's own stance applies, which is the fire extinguisher's: held in
    --- two hands, pointed forward. Not the minigun brace that a charged line deserves, but it
    --- works, and a firefighter holding a nozzle slightly wrong beats one in a bind pose.
    ---
    --- What was tried, so it is not tried again:
    ---
    --- - `SetPedMovementClipset(ped, 'weapons@heavy@minigun')` -- T-pose.
    --- - `SetPedStrafeClipset(ped, 'weapons@heavy@minigun')` -- holds correctly, T-poses on
    ---   walking.
    --- - Both together -- still T-poses on walking.
    ---
    --- The name is right: `weapons@heavy@minigun` is what the game's own weaponanimations gives
    --- the minigun for *both* `MotionClipSetHash` and `WeaponClipSetHash`. The natives simply do
    --- not reproduce what the weapon animation system does with it.
    ---
    --- **The thing that would actually work is a `weaponanimations.meta` entry**, which is how
    --- the game maps a weapon to its stance in the first place. It is not shipped because that
    --- file *replaces* the game's whole animation set rather than merging -- which is why both
    --- resources on this machine that ship one carry a 13,000 line copy of the vanilla data, and
    --- why a third would fight them. That is a deliberate trade, not an oversight.
    ---
    --- `/fire nozzlehold <clipset|off> [move]` still applies one live, if a better name turns up.

    --- How a charged line is **held**, as a weapon clipset.
    ---
    --- A nozzle on a charged line is braced at the waist in both hands, which is the minigun
    --- shape -- and `weapons@heavy@minigun` is exactly what the game own weaponanimations lists
    --- as the minigun `WeaponClipSetHash`.
    ---
    --- Applied with `SetPedStrafeClipset`. That native is the point: passing this same name to
    --- `SetPedMovementClipset` **T-poses**, because a weapon clipset carries no walk or idle
    --- clips and the skeleton falls back to its bind pose. Two clipsets, two natives, and
    --- `HasAnimSetLoaded` says true for both, so the only way to tell is which native you call.
    ---
    --- Try alternatives live with `/fire nozzlehold <clipset>`, and undo with
    --- `/fire nozzlehold off`.
    --- **Off, because every attempt at it T-posed.** See the note below.
    nozzleStrafeClipset = nil,

    --- How the firefighter **walks** while carrying it, as a movement clipset.
    ---
    --- The same name as the hold, which looks like a mistake and is not: the game's own
    --- weaponanimations gives the minigun `weapons@heavy@minigun` for **both**
    --- `MotionClipSetHash` and `WeaponClipSetHash`. Setting only the hold left the walk with
    --- nothing to fall back on, and walking T-posed.
    ---
    --- Try alternatives with `/fire nozzlehold <clipset> move`.
    nozzleClipset = nil,

    --- Where the nozzle sits in the hand.
    ---
    --- The animation places an equipped weapon by itself, which works while the model is shaped
    --- like the weapon whose animation it borrows. A nozzle held by its bale handle is not a
    --- minigun, so it gets placed by hand: the weapon entity is re-attached to a bone with these
    --- offsets, every pass, because the game re-places it on every stance change.
    ---
    --- `bone` is 'right' or 'left'. Rotations are degrees.
    ---
    --- **Find these with `/fire nozzlegrip`, not by arithmetic.** It moves the nozzle live and
    --- prints the line to paste back here. Baking a new origin into the model instead costs an
    --- export and a restart per attempt.
    ---
    --- Found by nudging in game with `/fire nozzlegrip`, not by arithmetic.
    ---
    --- The left hand, which is the one the minigun animation puts forward on the weapon -- so
    --- the nozzle ends up in the leading hand and the hose runs back past the trailing one,
    --- which is how a charged line is actually worked.
    ---
    --- nil leaves the placement entirely to the game.
    nozzleGrip = { bone = 'left', x = 0.100, y = 0.000, z = 0.000, rx = 30.0, ry = 203.0, rz = 120.0 },

    --- The same, for while the player is aiming.
    ---
    --- Two placements rather than one because the hand rotates between the two stances and the
    --- nozzle has to follow differently -- a set of numbers that looks right at rest goes wrong
    --- the moment anyone aims. `/fire nozzlegrip` edits whichever stance you are currently in,
    --- so aiming and then nudging fixes the aiming pose.
    ---
    --- nil falls back to `nozzleGrip`, so a half-tuned setup is imperfect rather than broken.
    ---
    --- It differs from the carrying placement by 25 degrees of pitch and 100 of yaw and nothing
    --- else, which is the hand rotating as the ped brings the nozzle up. Small, and the reason
    --- one set of numbers could not serve both.
    nozzleGripAiming = { bone = 'left', x = 0.100, y = 0.000, z = 0.000, rx = 55.0, ry = 203.0, rz = 220.0 },

    --- Only if the weapon fails to load, which means the metas did not reach the client.
    ---
    --- Deliberately still here. A weapon needs `data/weapons.meta` and
    --- `data/weaponarchetypes.meta` declared with `data_file` **and** listed in `files`, and a
    --- client that has not reconnected since they were added will not have them. An empty hand
    --- is a worse failure than the wrong prop, because it looks like the hose system is broken
    --- rather than the asset.
    nozzleProp = 'hei_prop_heist_hose_01',

    --- Nothing is borrowed, and nothing from an escrowed resource can be: those assets are
    --- encrypted and make FiveM refuse to load this one. Kept because the boot check and
    --- `conventions_spec` both read it, so the next borrow has to be declared.
    borrowed = {},

    --- The stream itself.
    ---
    --- `core` / `water_cannon_jet` is the base game's own water cannon jet, and it is not a
    --- guess: it is what the water cannon rigs on this machine use, at scale 2.0, driven with an
    --- offset and a rotation exactly like this. Same rule as the fire particle pairs and the roll
    --- animation -- take the one that is already working somewhere rather than the one whose
    --- name sounds right.
    ---
    --- Attached to the weapon entity rather than the ped, so it follows the nozzle through every
    --- stance without anything having to track it.
    ---
    --- The offset is in the **model's** space: the origin is the bale handle, the barrel axis
    --- runs 0.128 below it, and the tip is 0.139 forward. Rotation is the awkward part, because
    --- which way a particle emits is not something you can read off anything -- tune it with
    --- `/fire nozzlestream`.
    stream = {
        asset = 'core',
        name = 'water_cannon_jet',
        scale = 1.2,

        -- At the tip, on the barrel axis.
        x = 0.0, y = 0.139, z = -0.128,
        rx = 0.0, ry = 0.0, rz = 0.0,
    },

    couplingProp = 'prop_fire_hosebox_01',
    reelProp = 'prop_fire_hosereel',

    --- How often a laid line's shape is re-synced to other players, in ms. A rope is
    --- simulated locally, so this only has to agree about the *ends*.
    syncMs = 500,
}

-- ---------------------------------------------------------------------------
-- The hose bed
-- ---------------------------------------------------------------------------

--- What a hose bed carries, when the apparatus does not say.
---
--- **This is where a bare line comes from.** A crosslay or a reel is pulled from its discharge
--- because it is already coupled to one -- that is what preconnected means. Everything else
--- comes off the bed, gets walked out, and is coupled to a discharge afterwards. Pulling a
--- bare line from the discharge it will eventually connect to had the order backwards.
---
--- A real bed is divided. The big one is supply -- a thousand feet of LDH to lay back to a
--- hydrant -- and there is usually a smaller attack bed beside it. They are different hose for
--- different jobs and a crew picks.
---
--- Override per rig with `carries` on the hosebed port:
---
---     { id = 'hosebed1', type = 'hosebed', corners = { ... },
---       carries = { { size = 5.0, feet = 1200 }, { size = 2.5, feet = 600 } } }
MIFireHose.defaultBed = {
    { size = 5.0, feet = 1000 },
    { size = 2.5, feet = 600 },
}

--- Does a bed run out?
---
--- **Yes.** A thousand feet is a thousand feet, and a crew that lays it all has laid it all.
--- Turning this off makes the bed infinite, which removes the reason repacking exists.
MIFireHose.finiteBed = true

--- Maximum lengths a single line may be built from, so nobody lays a mile of hose off one
--- discharge and stalls the water graph.
MIFireHose.maxSections = 20
