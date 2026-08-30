--- Protective equipment tiers.
---
--- The governing rule, enforced by a test in `tools/tests/hydraulics_spec.lua`:
--- **nothing here may grant immunity to fire.** `fireResist` is a damage multiplier and
--- must stay below 1.0. Gear buys a firefighter time, and time runs out.
---
--- Smoke is deliberately absent from this file. Smoke is stopped by SCBA and by nothing
--- else -- see `config/scba.lua`. A firefighter in full turnout with no air on is still
--- breathing smoke.
---
--- Appearance slot names follow illenium-appearance's vocabulary -- `hat`, `torso2`,
--- `pants`, `shoes`, `arms`, `t-shirt`, `vest`, `mask`. Note that `hat` is a **prop**, not
--- a component: they go through different natives, and a helmet listed as a component
--- silently does nothing. `bridge/appearance/illenium.lua` sorts them out.

MIFireGear = {}

--- How resistance is read at runtime.
---
--- **Protection follows the clothing.** A firefighter who got dressed at a station locker,
--- through an outfit menu, or from a job clock-in is wearing turnout gear, and it protects
--- them exactly as much as if they had taken it off the truck. Donning at an apparatus is a
--- convenience, not the source of truth.
---
--- Recognition matches on **drawable and never texture**, because texture carries the name
--- tape and rank and is per-character. See `shared/gearmatch.lua`.
MIFireGear.defaultTier = 'none'

--- What partial coverage is worth.
---
--- Wearing the coat without the helmet is not the same as wearing the set. Protection
--- scales from `minimum` at signature-only up to full at a complete set, so a missing hood
--- is a real decision rather than a cosmetic one.
MIFireGear.coverage = {
    partialCounts = true,
    minimum = 0.55,
}

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
        fireResist = 0.62,
        heatResist = 0.40,
        chemResist = 0.05,
        integrity = 110,
        degradeRate = 6.5,
        ignitionThreshold = 0.25,
        selfExtinguish = 5.0,
        mobility = 0.97,
        appearance = nil,   -- not authored for this server yet
        signature = { 'torso2' },
    },

    --- Full structural turnout. The default fireground tier.
    --- Survives walking through fire. Does not survive standing in it.
    structural = {
        label = 'Structural turnout gear',
        fireResist = 0.93,
        heatResist = 0.70,
        chemResist = 0.15,
        integrity = 240,
        degradeRate = 4.2,
        ignitionThreshold = 0.20,
        selfExtinguish = 3.0,
        mobility = 0.92,
        appearance = {
            male = {
                hat    = 251,   -- helmet. A prop, not a component.
                torso2 = 692,   -- turnout coat
                pants  = 11,    -- no separate trousers -- the boots carry them
                shoes  = 164,   -- bunker boots with trousers
                arms   = 179,   -- gloves
            },
            female = {
                hat    = 251,
                torso2 = 692,
                pants  = 11,
                shoes  = 164,
                arms   = 179,
            },
        },

        --- Slots that must match for this to count as turnout at all.
        ---
        --- The coat, and only the coat. `pants = 11` is "no separate trousers" and half the
        --- outfits on a server use it; matching on that would identify half the population
        --- as firefighters. The rest of the set adds coverage once the coat is there.
        signature = { 'torso2' },
    },

    --- Aluminized proximity gear. Built for radiant heat off a fuel fire -- aircraft,
    --- bulk flammable liquid. Heavy, hot, and slow to work in.
    proximity = {
        label = 'Proximity gear',
        fireResist = 0.95,
        heatResist = 0.90,
        chemResist = 0.20,
        integrity = 320,
        degradeRate = 4.5,
        ignitionThreshold = 0.15,
        selfExtinguish = 3.5,
        mobility = 0.84,
        appearance = nil,   -- not authored for this server yet
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
        appearance = nil,   -- not authored for this server yet
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
        appearance = nil,   -- not authored for this server yet
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
        appearance = nil,   -- not authored for this server yet
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
        appearance = nil,   -- not authored for this server yet
    },
}

--- What happens to damaged gear.
---
--- Three models, because servers disagree about this and both positions are defensible.
--- Pick one; the rest of the system does not care which.
---
---   'regenerate'  Gear recovers on its own once you are clear of the fire. Forgiving, no
---                 logistics, nobody ever stuck without a coat. Back out for a minute and
---                 you are good again.
---
---   'persist'     Damage stays until someone repairs or replaces the set. Realistic --
---                 thermal damage to real turnout does not heal, which is why NFPA 1851
---                 exists. Gives a station gear room a purpose and makes a bad call cost
---                 something afterwards.
---
---   'session'     Damage lasts the shift and resets when you next put gear on. A middle
---                 ground that needs no repair points and no database.
MIFireGear.integrity = {
    mode = 'persist',

    --- Only used by 'regenerate'.
    regenerate = {
        --- Seconds clear of any fire before a set starts recovering. This matters more
        --- than the rate: ducking out for two seconds should not reset a coat, and
        --- rotating out properly should.
        delaySeconds = 60.0,

        --- Integrity restored per second once recovery has started. Set this very high for
        --- "clear of the fire for a minute and it is as good as new".
        ratePerSecond = 3.0,

        --- Fraction of full integrity recovery reaches. Below 1.0, gear slowly accumulates
        --- damage across a shift even on this mode.
        recoverTo = 1.0,
    },

    --- Only used by 'persist'.
    persist = {
        --- Base seconds to repair a set, scaled by how bad it is -- a scorched coat is
        --- quick and a nearly-condemned one is a job.
        repairSeconds = 45.0,

        --- Below this fraction a set is **condemned**: it cannot be repaired and has to be
        --- replaced. Past a point real gear is taken out of service rather than patched,
        --- and modelling that gives replacement a purpose distinct from repair.
        condemnedBelow = 0.15,

        --- Seconds to draw a fresh set from a rack. Fast, because the slow option is
        --- repairing the one you have.
        replaceSeconds = 10.0,

        --- Ceiling lost each time a set is repaired, as a fraction. Repaired gear does not
        --- come back as new, so a set that has been through several fires eventually gets
        --- replaced rather than endlessly patched. Set 0.0 to repair to full every time.
        ceilingLossPerRepair = 0.08,

        --- Where a set can be repaired. Racks on apparatus can hand out fresh gear but
        --- cannot service it -- that is a station job.
        repairAtStation = true,
        repairAtApparatus = false,
    },

    --- Store integrity across sessions, on ox_inventory item metadata when present and in
    --- server state otherwise. Turning this off makes 'persist' behave like 'session'.
    saveBetweenSessions = true,
    metadataKey = 'integrity',
}

--- Exposure tuning. These are the knobs a server owner actually turns.
MIFireGear.exposure = {
    --- Direct flame, applied per tick to a player standing in a node.
    flame = {
        tickMs = 500,
        baseDamagePerTick = 6.0,      -- against an unprotected player at full intensity
        intensityScaling = true,      -- scale by node intensity 0-100

        --- How close counts as standing in it. Everything beyond this is radiant heat.
        contactRadius = 1.8,
    },

    --- What heat and smoke do to the screen.
    ---
    --- **Off.** All of it, by default.
    ---
    --- This started as heat washing the picture out and escalating into a screen effect,
    --- and smoke darkening and closing in with a cough animation. In play it was wrong in
    --- both directions at once: the heat overlay was GTA's drug-trip effect, which reads as
    --- being poisoned rather than being cooked, and none of it told you *which* of the
    --- three channels was hurting you -- so a distorted screen was indistinguishable from
    --- the resource malfunctioning.
    ---
    --- The information is real and worth having. The screen is the wrong place to put it,
    --- because a firefighter cannot act on "something is wrong with your vision". It lives
    --- on the HUD instead, where heat, air, and gear condition are three separate readable
    --- numbers, and the screen is left alone so you can see the fire you came to fight.
    ---
    --- Turn any of it back on if you want it. Every timecycle named here is one already in
    --- production use rather than one read off a wiki list, for the same reason particle
    --- names are pinned: a bad name fails silently and looks like a broken feature.
    visuals = {
        --- Heat. `heliGunCam` washes the picture out; `rply_motionblur` makes it swim.
        heat = {
            enabled = false,
            onsetFraction = 0.35,
            buildingTimecycle = 'heliGunCam',
            severeFraction = 0.75,
            severeTimecycle = 'rply_motionblur',
            maxStrength = 0.55,
            --- Camera shake at severe load. Physiological stress, not an explosion.
            shake = 'SKY_DIVING_SHAKE',
            shakeAmplitude = 0.25,
        },

        --- Smoke. Only ever applied when you are actually breathing it -- a sealed mask
        --- means you can see, which is most of why you wear one.
        smoke = {
            enabled = false,
            timecycle = 'spectator5',
            maxStrength = 1.0,
            --- The coughing animation. Separate from the screen, because a server can
            --- reasonably want the audible tell without the visual one.
            cough = false,
        },

        --- One notification when heat crosses into the range where it damages you on its
        --- own. Independent of the screen effects: a warning you can read is useful even
        --- when nothing is distorting.
        warnOnSevereHeat = true,
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
    ---
    --- Density is currently derived from nearby fire nodes, weighted by each class's
    --- `smokeVolume`. A real smoke system (`FIRE-008`) replaces the source without
    --- changing anything else here.
    smoke = {
        tickMs = 1000,
        damagePerTick = 3.0,          -- slower than fire, but it does not stop
        visionOnset = 4.0,            -- seconds of exposure before vision degrades
        coughOnset = 6.0,

        --- How far smoke carries from a node before it is too thin to matter.
        radius = 9.0,
        --- Smoke does not disperse indoors, which is why interior fires kill people.
        indoorMultiplier = 2.0,
        --- Density below this is ignored entirely, so a distant fire does not produce a
        --- permanent faint cough.
        minimumDensity = 0.08,
    },

    --- Catching fire.
    ignition = {
        --- Once integrity is below the tier threshold, each flame tick rolls this.
        chancePerTick = 0.08,
        --- Damage per tick while burning, before gear resistance.
        ---
        --- Was 6.0, which made stop-drop-roll unreachable rather than difficult. By the
        --- time a structural set burns through you are ~46 seconds into the fire with
        --- roughly 28 of your 100 usable points left; 6 a second of burn on top of the
        --- flame damage killed you in about 3.7 seconds against a 4-second roll. The
        --- mechanic could not be performed by anyone, at any skill level, ever.
        ---
        --- At 3.0 the same firefighter has around six seconds. Rolling immediately works;
        --- hesitating does not, and getting clear of the flame first roughly doubles the
        --- window -- which is the correct lesson rather than an arbitrary one.
        burnDamagePerTick = 3.0,
        --- A partner with a charged line can put someone out faster than rolling.
        hoselineExtinguishSeconds = 1.5,
        --- Burning stops on its own eventually, so a disconnect mid-burn does not leave
        --- someone alight forever.
        maximumBurnSeconds = 45.0,

        --- The flames on a burning player.
        ---
        --- Drawn by us rather than with `StartEntityFire`, which looks right but brings
        --- GTA's own ped fire damage with it -- fast, unconfigurable, and independent of
        --- every number above. It killed a firefighter in about two seconds against a
        --- three second roll, so stop-drop-roll could not be performed at all, while the
        --- model here had given them eighteen seconds.
        ---
        --- `core`/`fire_wrecked_truck_vent` is the same pair the fire nodes use, so it is
        --- verified rather than taken off a list. Bone 24816 is the spine, so the flames
        --- sit on the torso and follow a ragdoll rather than pooling at the feet.
        particle = {
            dict = 'core',
            name = 'fire_wrecked_truck_vent',
            scale = 0.5,
            bone = 24816,
            z = 0.0,
        },
    },

    --- Superseded by `MIFireGear.integrity` above, which covers all three models rather
    --- than only the persistent one. Kept as an alias so an older config still loads.
    persistence = {
        enabled = true,
        metadataKey = 'integrity',
        condemnedBelow = 0.15,
    },
}

return MIFireGear
