--- Solving a live line.
---
--- The claim under test: **a nozzle operator does not choose a flow.** They open the bail, and
--- what comes out is decided by the pressure the pump operator sends and by everything between
--- the two. If that were not true the pump panel would be scenery.

return function(t)
    local Pump = MIFire.Pump
    local nozzles = MIFireHose.nozzles

    -- -----------------------------------------------------------------------

    t.describe('everything between the pump and the tip takes its share')

    local psi, losses = Pump.nozzlePressure({
        dischargePsi = 150.0,
        diameter = 1.75,
        lengthFeet = 200,
        gpm = 150,
    })

    -- 200ft of 1.75 inch at 150 gpm is 69.75 psi of friction, from the published coefficient.
    t.near(losses.friction, 69.75, 0.01, 'the friction loss is the hand-worked figure')
    t.near(psi, 150.0 - 69.75, 0.01, 'and what reaches the nozzle is what is left')

    t.describe('including the climb')

    local ground = Pump.nozzlePressure({
        dischargePsi = 150.0, diameter = 1.75, lengthFeet = 200, gpm = 150,
    })

    local upstairs = Pump.nozzlePressure({
        dischargePsi = 150.0, diameter = 1.75, lengthFeet = 200, gpm = 150,
        elevationFeet = 30.0,
    })

    t.ok(upstairs < ground, 'three floors up costs pressure the ground floor does not pay')

    -- 0.434 psi per foot: the weight of a foot of water. Half a psi per foot is the fireground
    -- rule of thumb people work in their heads, and it is deliberately not what the module
    -- uses -- the approximation is for a pump operator under pressure, not for the model they
    -- are being taught against.
    t.near(ground - upstairs, 13.02, 0.05,
        'the exact figure rather than the rule of thumb')

    t.describe('and a line can simply not reach')

    -- Worth being a real answer rather than a small number. 400ft of 1.75 at 200 gpm is past
    -- what 100 psi will push, and a pump operator needs to be told that rather than shown a
    -- gauge reading two.
    local unreachable = Pump.nozzlePressure({
        dischargePsi = 100.0, diameter = 1.75, lengthFeet = 400, gpm = 200,
    })

    t.equal(unreachable, 0.0, 'nothing arrives at the tip')

    -- -----------------------------------------------------------------------

    t.describe('a smooth bore flows what its tip and pressure say')

    -- Arithmetic, which is why a pump operator can work one out in their head.
    local sb = nozzles.smoothbore_15_16

    t.near(Pump.nozzleFlow(sb, 50.0), 185.0, 10.0, '15/16 at 50 psi is about 185 gpm')
    t.ok(Pump.nozzleFlow(sb, 80.0) > Pump.nozzleFlow(sb, 50.0),
        'and more pressure is more water, with no setting involved')

    t.equal(Pump.nozzleFlow(sb, 0.0), 0.0, 'no pressure is no water')

    -- -----------------------------------------------------------------------

    t.describe('a line solves for its own flow')

    -- Circular: friction depends on flow, flow depends on the pressure that survives friction.
    local gpm, nozzlePsi = Pump.solveLine({
        dischargePsi = 150.0,
        diameter = 1.75,
        lengthFeet = 200,
        nozzle = sb,
    })

    t.ok(gpm > 0, 'it converges on a flow')
    t.ok(nozzlePsi > 0, 'and a nozzle pressure')

    -- The check that the solution is self-consistent rather than merely a number: feed the
    -- flow back in and the pressure that comes out should be the one it settled on.
    local check = Pump.nozzlePressure({
        dischargePsi = 150.0, diameter = 1.75, lengthFeet = 200, gpm = gpm,
    })

    t.near(check, nozzlePsi, 2.0, 'and the answer agrees with itself')

    t.describe('a longer stretch off the same discharge flows less')

    local short = Pump.solveLine({
        dischargePsi = 150.0, diameter = 1.75, lengthFeet = 100, nozzle = sb,
    })

    local long = Pump.solveLine({
        dischargePsi = 150.0, diameter = 1.75, lengthFeet = 400, nozzle = sb,
    })

    t.ok(short > long,
        ('%.0f gpm at 100ft against %.0f at 400ft, off the same pressure'):format(short, long))

    t.describe('and the pump operator can pay for the difference')

    local compensated = Pump.solveLine({
        dischargePsi = 220.0, diameter = 1.75, lengthFeet = 400, nozzle = sb,
    })

    t.ok(compensated > long,
        'more pressure gets the flow back, which is the entire job at the panel')

    -- -----------------------------------------------------------------------

    t.describe('the pump curve is a real limit')

    -- NFPA 1901: rated flow at 150 psi, 70% at 200, half at 250.
    local at150 = Pump.capacity(1500, 150, 0)
    local at250 = Pump.capacity(1500, 250, 0)

    t.near(at150, 1500, 1.0, 'a 1500 gpm pump makes 1500 at 150 psi')
    t.near(at250, 750, 1.0, 'and half that at 250')

    local _, over = Pump.capacity(1500, 200, 1400)
    t.equal(over, true, 'asking 1400 gpm at 200 psi is asking for more than it has')

    -- -----------------------------------------------------------------------

    t.describe('opening a second line takes water off the first')

    -- The single most important thing for a nozzle crew to feel, and the reason a governor
    -- exists at all.
    local shared = Pump.share({ { gpm = 200 }, { gpm = 200 } }, 250)

    t.ok(shared[1] < 200, 'the first line loses flow when the second opens')
    t.near(shared[1] + shared[2], 250, 0.01, 'and between them they get what there is')
    t.near(shared[1], shared[2], 0.01, 'shared proportionally rather than first come first served')

    t.describe('but not when there is enough to go round')

    local plenty = Pump.share({ { gpm = 150 }, { gpm = 150 } }, 1500)

    t.near(plenty[1], 150, 0.01, 'a pump with capacity to spare shorts nobody')

    -- -----------------------------------------------------------------------

    t.describe('a line is named soft rather than shown a small number')

    local ok, word = Pump.lineCondition(15.0, nozzles.fog)
    t.equal(ok, false, 'fifteen psi on a 100 psi fog nozzle is not a working line')
    t.equal(word, 'soft', 'and it says so')

    t.equal(select(2, Pump.lineCondition(0.0, nozzles.fog)), 'no water',
        'nothing at all is its own answer')

    t.equal(select(2, Pump.lineCondition(100.0, nozzles.fog)), 'good',
        'and its rated pressure is good')

    t.equal(select(2, Pump.lineCondition(160.0, nozzles.fog)), 'over-pressured',
        'while too much is worth saying too -- it is how a nozzle gets taken off a crew')
end
