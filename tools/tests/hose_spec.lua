--- Hose lines.
---
--- The claim under test is the one the whole design rests on: **a bigger line is not simply
--- better.** If a 2.5 inch were strictly superior a crew would take it everywhere and choosing
--- the line would be decoration rather than a decision.

return function(t)
    local Hose = MIFire.Hose
    local sizes = MIFireHose.sizes
    local under = MIFireHose.underCrewed

    local booster = sizes[1.0]
    local attack = sizes[1.75]
    local big = sizes[2.5]
    local ldh = sizes[5.0]

    -- -----------------------------------------------------------------------

    t.describe('a bigger line costs more people')

    t.ok(Hose.crewRequired(big) > Hose.crewRequired(attack),
        'a 2.5 inch wants more hands than a 1.75')
    t.ok(Hose.crewRequired(attack) > Hose.crewRequired(booster),
        'and a 1.75 more than a booster reel')

    t.describe('and gives more water for them')

    t.ok(big.gpmRange[2] > attack.gpmRange[2],
        'which is the trade -- more people, more water')

    t.describe('so a full crew on a small line beats a short crew on a big one')

    -- The decision the whole system exists to make interesting. Two firefighters who take the
    -- 1.75 put more water on the fire than the same two who took the 2.5 because it was
    -- bigger, and that has to be true or nobody ever chooses correctly.
    local twoOnAttack = Hose.flowCeiling(attack, 2, under)
    local twoOnBig = Hose.flowCeiling(big, 2, under)

    t.ok(twoOnAttack > twoOnBig,
        ('two on a 1.75 flow %.0f gpm; the same two on a 2.5 manage %.0f')
            :format(twoOnAttack, twoOnBig))

    -- -----------------------------------------------------------------------

    t.describe('being short-handed is never a refusal')

    -- One firefighter who wants to try a 2.5 inch should be allowed to find out. A rule that
    -- says "you may not" teaches nothing and reads as the script being in charge.
    local alone = Hose.flowCeiling(big, 1, under)

    t.ok(alone > 0, 'one person on a 2.5 inch still gets water out of it')
    t.ok(alone < big.gpmRange[2] * 0.5, 'but nothing like what it is rated for')

    t.describe('and it gets worse faster than linearly')

    local twoShort = big.gpmRange[2] - Hose.flowCeiling(big, 1, under)
    local oneShort = big.gpmRange[2] - Hose.flowCeiling(big, 2, under)

    t.ok(twoShort > oneShort * 1.5,
        'two short is much worse than twice one short, so a crew of two is workable and a '
        .. 'crew of one is not')

    t.describe('nobody on it flows nothing')

    t.equal(Hose.flowCeiling(big, 0, under), 0.0, 'an unheld line is not flowing')

    -- -----------------------------------------------------------------------

    t.describe('losing the line depends on how hard you push it')

    -- A 2.5 held by one person at a trickle is awkward; the same line at full flow is a
    -- whipping charged hose. Both are true, and the difference is what makes throttling back a
    -- real option rather than a punishment for being short-handed.
    local gentle = Hose.lossChance(big, 1, 60.0, under)
    local hard = Hose.lossChance(big, 1, big.gpmRange[2], under)

    t.ok(hard > gentle, 'pushing an under-crewed line harder makes it more likely to get away')
    t.ok(gentle > 0, 'but it is never entirely safe')

    t.equal(Hose.lossChance(big, 3, big.gpmRange[2], under), 0.0,
        'a full crew does not lose the line at all')

    -- -----------------------------------------------------------------------

    t.describe('charged hose is much heavier than dry')

    local dry = Hose.dragWeight(attack, 4, false)
    local wet = Hose.dragWeight(attack, 4, true)

    t.ok(wet > dry * 2.5,
        'which is why a crew stretches dry and calls for water once they are in position, '
        .. 'rather than dragging a live line through a building')

    t.describe('and crew is what makes a line movable')

    local soloSpeed = Hose.dragSpeed(big, 4, true, 1, MIFireHose.work)
    local crewSpeed = Hose.dragSpeed(big, 4, true, 3, MIFireHose.work)

    t.ok(crewSpeed > soloSpeed, 'three move a charged 2.5 faster than one does')

    -- -----------------------------------------------------------------------

    t.describe('hose comes in lengths')

    t.equal(Hose.sectionsFor(attack, 15.0), 1,
        'fifteen metres is inside one 50ft length')
    t.equal(Hose.sectionsFor(attack, 20.0), 2,
        'and twenty is not, so you take two -- you cannot stretch 60ft of 50ft hose')

    t.equal(Hose.lengthFeet(attack, 4), 200, 'four lengths is 200ft')

    -- -----------------------------------------------------------------------

    t.describe('a supply line has no nozzle')

    -- Not a bad idea -- a category error. LDH feeds an appliance or another pump.
    local ok, why = Hose.acceptsNozzle(ldh, 'fog')
    t.equal(ok, false, 'you cannot put a fog nozzle on 5 inch LDH')
    t.ok(why and why:find('supply line') ~= nil, 'and it says why')

    t.equal(Hose.acceptsNozzle(attack, 'fog'), true, 'an attack line does take one')
    t.equal(Hose.acceptsNozzle(attack, 'smoothbore_1_1_4'), false,
        'but not a tip sized for the bigger line')

    -- -----------------------------------------------------------------------

    t.describe('a wide fog is a shield, not an extinguishing pattern')

    local fog = MIFireHose.nozzles.fog

    t.ok(Hose.patternEfficiency(fog, 'wide') < Hose.patternEfficiency(fog, 'straight') * 0.7,
        'it puts far less water on the seat')
    t.ok(fog.reach.wide < fog.reach.straight * 0.5, 'and reaches nowhere')
    t.ok(fog.entrains.wide > fog.entrains.straight,
        'while moving a lot of air, which is a tactic and a hazard')

    -- -----------------------------------------------------------------------

    t.describe('smooth bore flow comes from the tip, not from a setting')

    -- Which is why a smooth bore is predictable and a fog nozzle is not: you cannot dial the
    -- wrong flow into one.
    local small = Hose.smoothBoreFlow(MIFireHose.nozzles.smoothbore_15_16)
    local large = Hose.smoothBoreFlow(MIFireHose.nozzles.smoothbore_1_1_4)

    t.ok(large > small, 'a bigger tip flows more at the same pressure')
    t.near(small, 185.0, 10.0, '15/16 inch at 50 psi is about 185 gpm')

    t.equal(Hose.smoothBoreFlow(fog), nil,
        'and a fog nozzle has no tip, so its flow is set rather than derived')

    -- -----------------------------------------------------------------------

    t.describe('the booster reel is in the config but is not an attack line')

    t.ok(booster.gpmRange[2] < attack.gpmRange[1],
        'a booster reel at full flow is below what a 1.75 inch does at its minimum')
    t.equal(booster.reel, true, 'and it is rewound rather than repacked')

    t.describe('repacking is the price of pulling a line')

    t.ok(MIFireHose.work.repackSecondsPerSection > MIFireHose.work.rewindSecondsPerSection * 2,
        'which is exactly why the reel gets reached for when it should not be')
end
