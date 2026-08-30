--- Exposure tests.
---
--- The invariant from ADR 0001, checked from the other direction: no configuration of gear
--- makes a firefighter safe. `validate.lua` proves no tier is *configured* with immunity;
--- these prove the maths never *produces* it either.
---
--- The survival figures at the end are the ones worth arguing over. A tier that survives an
--- hour in a fire is decoration; one that survives four seconds is a joke. Having them as
--- numbers means the argument can happen here rather than in a burning building.

return function(t)
    local Exposure = MIFire.Exposure
    local cfg = MIFireGear.exposure

    local none = MIFireGear.tiers.none
    local structural = MIFireGear.tiers.structural
    local proximity = MIFireGear.tiers.proximity
    local hazmatA = MIFireGear.tiers.hazmat_a

    -- -----------------------------------------------------------------------

    t.describe('flame damage')

    t.ok(Exposure.flameDamage(100, none, cfg.flame) > 0,
        'an unprotected player takes damage standing in fire')

    t.ok(Exposure.flameDamage(100, structural, cfg.flame)
        < Exposure.flameDamage(100, none, cfg.flame),
        'turnout gear reduces it')

    t.ok(Exposure.flameDamage(100, structural, cfg.flame) > 0,
        'but never to zero -- this is the invariant the whole design rests on')

    t.ok(Exposure.flameDamage(100, proximity, cfg.flame) > 0,
        'and not even for the best gear in the config')

    t.ok(Exposure.flameDamage(30, none, cfg.flame)
        < Exposure.flameDamage(100, none, cfg.flame),
        'a smouldering node hurts less than a developed one')

    t.equal(Exposure.flameDamage(0, none, cfg.flame), 0.0, 'and a dead node does nothing')

    t.describe('even an absurd configuration cannot grant immunity')

    -- validate.lua rejects this at boot, so it should be unreachable. Belt and braces:
    -- the maths clamps too, so a config that somehow slipped through still cannot produce
    -- a safe firefighter.
    local cheat = { fireResist = 5.0, integrity = 100 }
    t.ok(Exposure.flameDamage(100, cheat, cfg.flame) > 0,
        'a fireResist far above 1.0 is clamped rather than inverting the damage')

    local negative = { fireResist = -3.0, integrity = 100 }
    t.ok(Exposure.flameDamage(100, negative, cfg.flame) > 0,
        'and a negative one does not amplify it into nonsense')

    -- -----------------------------------------------------------------------

    t.describe('gear burns through')

    t.ok(Exposure.gearDegradation(100, structural) > 0, 'standing in fire wears gear down')
    t.ok(Exposure.gearDegradation(20, structural) < Exposure.gearDegradation(100, structural),
        'faster in a hotter fire')
    t.equal(Exposure.gearDegradation(100, none), 0.0,
        'a station uniform has no integrity to lose')

    t.describe('and worn gear protects less')

    local fresh = Exposure.effectiveFireResist(structural.integrity, structural)
    local burned = Exposure.effectiveFireResist(0, structural)

    t.ok(fresh > burned, 'a burned coat protects less than a fresh one')
    t.ok(burned > 0, 'but still something -- a burned coat is still a coat')
    t.near(fresh, structural.fireResist, 0.01, 'fresh gear performs at its rated value')

    t.describe('and eventually you ignite')

    t.equal(Exposure.canIgnite(structural.integrity, structural), false,
        'fresh turnout does not let you catch fire')
    t.equal(Exposure.canIgnite(0, structural), true,
        'burned-through turnout does')
    t.equal(Exposure.canIgnite(0, none), true,
        'and with no gear at all you are always ignitable')

    -- The threshold is a fraction, so it has to scale with the tier's own pool.
    local justAbove = structural.integrity * (structural.ignitionThreshold + 0.05)
    local justBelow = structural.integrity * (structural.ignitionThreshold - 0.05)
    t.equal(Exposure.canIgnite(justAbove, structural), false, 'just above the threshold, no')
    t.equal(Exposure.canIgnite(justBelow, structural), true, 'just below it, yes')

    -- -----------------------------------------------------------------------

    t.describe('radiant heat')

    local nearHeat = Exposure.heatBuild(1.0, 100, none, cfg.heat, cfg.flame)
    local farHeat = Exposure.heatBuild(4.0, 100, none, cfg.heat, cfg.flame)

    t.ok(nearHeat > 0, 'standing near a fire builds heat')
    t.ok(nearHeat > farHeat, 'and more of it the closer you are')

    local radius = Exposure.heatRadius(100, cfg.heat, cfg.flame)
    t.equal(Exposure.heatBuild(radius + 1, 100, none, cfg.heat, cfg.flame), 0.0,
        'beyond the radius nothing accumulates, so a fire across the street does not cook you')

    t.ok(Exposure.heatBuild(1.0, 100, structural, cfg.heat, cfg.flame) < nearHeat,
        'turnout reduces heat build-up')
    t.ok(Exposure.heatBuild(1.0, 100, proximity, cfg.heat, cfg.flame)
        < Exposure.heatBuild(1.0, 100, structural, cfg.heat, cfg.flame),
        'and proximity gear, which exists for radiant heat, reduces it more than turnout')

    t.ok(Exposure.heatRadius(100, cfg.heat, cfg.flame) > Exposure.heatRadius(20, cfg.heat, cfg.flame),
        'a bigger fire radiates further')

    t.describe('and heat has consequences before it kills you')

    local mild = Exposure.heatEffects(cfg.heat.staminaDrainAt - 5, cfg.heat)
    local straining = Exposure.heatEffects(cfg.heat.staminaDrainAt + 5, cfg.heat)
    local cooking = Exposure.heatEffects(cfg.heat.maxLoad, cfg.heat)

    t.equal(mild.straining, false, 'a low heat load is survivable and quiet')
    t.equal(straining.straining, true, 'past the stamina threshold you start labouring')
    t.equal(mild.damagePerSecond, 0.0, 'and heat alone does not hurt at low load')
    t.ok(cooking.damagePerSecond > 0, 'at maximum load it does')

    -- -----------------------------------------------------------------------

    t.describe('smoke is stopped by SCBA and nothing else')

    local density = Exposure.smokeDensity(2.0, 100, 1.5, false, cfg.smoke)
    t.ok(density > 0, 'a fire produces smoke around it')

    t.ok(Exposure.smokeDamage(density, false, cfg.smoke) > 0,
        'and breathing it hurts')

    t.equal(Exposure.smokeDamage(density, true, cfg.smoke), 0.0,
        'an SCBA with air stops it completely -- the one true immunity in mi_fire')

    -- The point of ADR 0001, from the other side: gear is not even an argument here.
    t.equal(Exposure.smokeDamage(1.0, true, cfg.smoke), 0.0,
        'even at maximum density')

    t.describe('and indoor smoke is worse')

    local outdoor = Exposure.smokeDensity(3.0, 100, 1.0, false, cfg.smoke)
    local indoor = Exposure.smokeDensity(3.0, 100, 1.0, true, cfg.smoke)
    t.ok(indoor > outdoor,
        'smoke does not disperse indoors, which is why interior fires kill people')

    t.describe('and a smoky class produces more of it')

    local sooty = Exposure.smokeDensity(3.0, 100, 2.0, false, cfg.smoke)
    local clean = Exposure.smokeDensity(3.0, 100, 0.6, false, cfg.smoke)
    t.ok(sooty > clean,
        'a flammable liquid fire smokes far more than a gas jet, per config/fire_classes')

    t.ok(Exposure.smokeDensity(100.0, 100, 1.0, false, cfg.smoke) == 0.0,
        'and smoke thins to nothing at distance')

    -- -----------------------------------------------------------------------

    t.describe('survival: gear buys time, and time runs out')

    -- The figures the design actually rests on. All of these are seconds standing in a
    -- fully developed fire without moving.
    local bare = Exposure.survivalSeconds(100, none, cfg)
    local turnout = Exposure.survivalSeconds(100, structural, cfg)
    local prox = Exposure.survivalSeconds(100, proximity, cfg)
    local hazmat = Exposure.survivalSeconds(100, hazmatA, cfg)

    t.ok(turnout > bare * 2,
        'turnout gear buys substantially longer than a station uniform')
    t.ok(prox > turnout,
        'and proximity gear longer still')

    t.ok(hazmat < turnout,
        'while a hazmat suit is worse in fire than turnout -- a Level A suit is plastic, '
        .. 'and walking a hazmat crew into flame should be punished')

    -- The bounds that make it a fireground rather than a cutscene. Measured figures at
    -- full intensity: station uniform 11.5s, turnout 34.5s, proximity 57.5s.
    t.ok(bare < 20,
        'a station uniform gives seconds, not half a minute -- fire has to be frightening')
    t.ok(turnout > 20,
        'but turnout is not so fragile that walking through a doorway kills you')
    t.ok(turnout < 180,
        'and nothing in the config lets a crew camp inside a room that is fully alight')

    t.ok(turnout / bare > 2.5,
        'the gap between gear and no gear is large enough to be the reason to wear it')

    t.describe('every tier eventually dies')

    for name, tier in pairs(MIFireGear.tiers) do
        local seconds = Exposure.survivalSeconds(100, tier, cfg)
        t.ok(seconds < 3600,
            ('the %s tier does not survive indefinitely in a fire'):format(name))
    end
end
