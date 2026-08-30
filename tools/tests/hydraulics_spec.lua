--- Hydraulics tests.
---
--- Every case here is a hand-worked fireground problem with a known answer, not a
--- snapshot of whatever the code happened to return. If a test fails, the code is wrong
--- until someone shows the arithmetic says otherwise.

return function(t)
    local H = dofile('shared/hydraulics.lua')

    -- -----------------------------------------------------------------------
    -- Coefficients
    -- -----------------------------------------------------------------------

    t.describe('coefficients')

    t.equal(H.coefficient(1.75), 15.5, 'the 1.75 inch coefficient is 15.5')
    t.equal(H.coefficient(2.5), 2.0, 'the 2.5 inch coefficient is 2')
    t.equal(H.coefficient(5.0), 0.08, 'the 5 inch coefficient is 0.08')
    t.equal(H.coefficient(0), 0.0, 'a zero diameter has no coefficient rather than erroring')
    t.equal(H.coefficient(nil), 0.0, 'a nil diameter has no coefficient rather than erroring')

    t.ok(H.coefficient(2.25) < H.coefficient(2.0), 'an interpolated size falls between its neighbours (upper)')
    t.ok(H.coefficient(2.25) > H.coefficient(2.5), 'an interpolated size falls between its neighbours (lower)')

    -- -----------------------------------------------------------------------
    -- Friction loss
    -- -----------------------------------------------------------------------

    t.describe('friction loss')

    -- 200 ft of 1.75 inch at 150 gpm: FL = 15.5 * 1.5^2 * 2 = 69.75
    t.near(H.frictionLoss(1.75, 150, 200), 69.75, 0.01,
        '200 ft of 1.75 inch at 150 gpm loses 69.75 psi')

    -- 500 ft of 5 inch at 1000 gpm: FL = 0.08 * 10^2 * 5 = 40
    t.near(H.frictionLoss(5.0, 1000, 500), 40.0, 0.01,
        '500 ft of 5 inch at 1000 gpm loses 40 psi -- the classic LDH supply figure')

    -- 300 ft of 2.5 inch at 250 gpm: FL = 2 * 2.5^2 * 3 = 37.5
    t.near(H.frictionLoss(2.5, 250, 300), 37.5, 0.01,
        '300 ft of 2.5 inch at 250 gpm loses 37.5 psi')

    t.equal(H.frictionLoss(1.75, 0, 200), 0.0, 'no flow means no friction loss')
    t.equal(H.frictionLoss(1.75, 150, 0), 0.0, 'no length means no friction loss')

    -- Doubling flow quadruples loss. This is the property that makes the whole
    -- system behave, so it is asserted directly rather than trusted.
    t.near(H.frictionLoss(2.5, 500, 100), H.frictionLoss(2.5, 250, 100) * 4, 0.01,
        'doubling the flow quadruples the loss')

    t.describe('parallel lines')

    -- Two 3 inch lines carrying 600 gpm each carry 300. FL = 0.8 * 3^2 * 5 = 36
    t.near(H.frictionLossParallel(3.0, 600, 500, 2), 36.0, 0.01,
        'siamesed 3 inch lines split the flow before the loss is calculated')

    t.near(H.frictionLossParallel(3.0, 600, 500, 1), H.frictionLoss(3.0, 600, 500), 0.01,
        'one parallel line is just a single line')

    t.ok(H.frictionLossParallel(3.0, 600, 500, 2) < H.frictionLoss(3.0, 600, 500) / 3,
        'two lines cut loss by more than half, because loss follows the square of flow')

    -- -----------------------------------------------------------------------
    -- Nozzles
    -- -----------------------------------------------------------------------

    t.describe('smooth bore nozzles')

    -- Published tip flows at 50 psi handline pressure.
    t.near(H.smoothBoreFlow(1.0, 50), 210.0, 1.0, 'a 1 inch tip at 50 psi flows 210 gpm')
    t.near(H.smoothBoreFlow(0.9375, 50), 185.0, 1.0, 'a 15/16 inch tip at 50 psi flows 185 gpm')
    t.near(H.smoothBoreFlow(0.875, 50), 161.0, 1.0, 'a 7/8 inch tip at 50 psi flows 161 gpm')
    t.near(H.smoothBoreFlow(1.125, 50), 266.0, 1.0, 'a 1-1/8 inch tip at 50 psi flows 266 gpm')

    -- Master stream tips run at 80 psi.
    t.near(H.smoothBoreFlow(1.375, 80), 502.0, 2.0, 'a 1-3/8 inch master tip at 80 psi flows about 500 gpm')

    t.equal(H.smoothBoreFlow(0, 50), 0.0, 'no tip means no flow')
    t.equal(H.smoothBoreFlow(1.0, 0), 0.0, 'no pressure means no flow')

    -- The inverse has to actually invert.
    t.near(H.smoothBorePressureFor(1.0, H.smoothBoreFlow(1.0, 50)), 50.0, 0.01,
        'solving pressure from flow inverts solving flow from pressure')

    t.describe('fog nozzles')

    t.near(H.fogFlow(150, 100, 100), 150.0, 0.01, 'a fog nozzle at its rated pressure gives its rated flow')
    t.near(H.fogFlow(150, 100, 25), 75.0, 0.01, 'a quarter of rated pressure gives half the flow')
    t.ok(H.fogFlow(150, 100, 150) > 150.0, 'over-pressuring a fog nozzle increases flow')

    -- -----------------------------------------------------------------------
    -- Elevation
    -- -----------------------------------------------------------------------

    t.describe('elevation')

    t.near(H.elevationLossFeet(100), 43.4, 0.01, '100 feet of head costs 43.4 psi')
    t.near(H.elevationLossFeet(-50), -21.7, 0.01, 'a nozzle below the pump gives pressure back')
    t.equal(H.elevationLossFloors(1), 0.0, 'the ground floor costs nothing')
    t.equal(H.elevationLossFloors(5), 20.0, 'the fifth floor costs 20 psi at 5 psi per floor')
    t.equal(H.elevationLossFloors(-1), -10.0, 'a basement gives pressure back')

    -- -----------------------------------------------------------------------
    -- Appliances
    -- -----------------------------------------------------------------------

    t.describe('appliance loss')

    t.equal(H.applianceLoss(150, { count = 1 }), 0.0, 'an appliance under 350 gpm costs nothing')
    t.equal(H.applianceLoss(400, { count = 1 }), 10.0, 'an appliance at or above 350 gpm costs 10 psi')
    t.equal(H.applianceLoss(400, { count = 2 }), 20.0, 'appliance losses accumulate')
    t.equal(H.applianceLoss(500, { masterStream = true }), 25.0, 'a master stream device costs a flat 25 psi')
    t.equal(H.applianceLoss(200, { masterStream = true }), 25.0, 'the master stream 25 psi is flat, not flow-dependent')
    t.equal(H.applianceLoss(300, { standpipe = true }), 25.0, 'a standpipe costs a flat 25 psi')
    t.equal(H.applianceLoss(0, { count = 5 }), 0.0, 'no flow means no appliance loss')

    -- -----------------------------------------------------------------------
    -- Pump discharge pressure -- the number the panel shows
    -- -----------------------------------------------------------------------

    t.describe('pump discharge pressure')

    -- The plan's worked example: 200 ft of 1.75 inch, 150 gpm, 100 psi fog nozzle.
    -- PDP = 100 + 69.75 + 0 + 0 = 169.75
    local attack = H.solveDischarge({
        nozzlePressure = 100, gpm = 150, diameter = 1.75, lengthFt = 200,
    })
    t.near(attack.pdp, 169.75, 0.01, 'a standard 1.75 inch attack line wants about 170 psi')
    t.near(attack.frictionLoss, 69.75, 0.01, 'and its friction loss is reported separately')
    t.equal(attack.elevationLoss, 0.0, 'with no elevation on the ground floor')

    -- Same line to the fifth floor adds 20 psi.
    local upstairs = H.solveDischarge({
        nozzlePressure = 100, gpm = 150, diameter = 1.75, lengthFt = 200, floor = 5,
    })
    t.near(upstairs.pdp, 189.75, 0.01, 'the same line on the fifth floor wants 20 psi more')

    -- A 2.5 inch smooth bore: 250 gpm, 50 psi tip, 200 ft.
    -- FL = 2 * 2.5^2 * 2 = 25. PDP = 50 + 25 = 75.
    local bigLine = H.solveDischarge({
        nozzlePressure = 50, gpm = 250, diameter = 2.5, lengthFt = 200,
    })
    t.near(bigLine.pdp, 75.0, 0.01, 'a 2.5 inch smooth bore handline wants only 75 psi')

    -- Multi-segment: 300 ft of 3 inch into a wye, then 100 ft of 1.75 inch at 150 gpm.
    -- 3 inch at 150 gpm: 0.8 * 1.5^2 * 3 = 5.4
    -- 1.75 inch at 150 gpm: 15.5 * 1.5^2 * 1 = 34.875
    -- PDP = 100 + 5.4 + 34.875 = 140.275
    local segmented = H.solveDischarge({
        nozzlePressure = 100, gpm = 150,
        segments = {
            { diameter = 3.0, lengthFt = 300 },
            { diameter = 1.75, lengthFt = 100 },
        },
    })
    t.near(segmented.pdp, 140.275, 0.01,
        'a 3 inch lay into a short 1.75 inch attack costs far less than 400 ft of 1.75 inch')

    t.ok(segmented.pdp < H.solveDischarge({
        nozzlePressure = 100, gpm = 150, diameter = 1.75, lengthFt = 400,
    }).pdp, 'which is the entire reason crews lay 3 inch to a wye')

    -- Explicit elevation wins over floor.
    local explicitElev = H.solveDischarge({
        nozzlePressure = 100, gpm = 150, diameter = 1.75, lengthFt = 200,
        floor = 10, elevationFt = 0,
    })
    t.near(explicitElev.pdp, 169.75, 0.01, 'an explicit elevation overrides the floor shortcut')

    -- -----------------------------------------------------------------------
    -- Pump capability
    -- -----------------------------------------------------------------------

    t.describe('pump capacity')

    t.equal(H.pumpCapacityAt(1500, 150), 1500.0, 'a pump makes its full rating at 150 psi')
    t.equal(H.pumpCapacityAt(1500, 100), 1500.0, 'and is still capped at its rating below that')
    t.near(H.pumpCapacityAt(1500, 200), 1050.0, 0.01, 'it makes 70 percent at 200 psi')
    t.near(H.pumpCapacityAt(1500, 250), 750.0, 0.01, 'and 50 percent at 250 psi')
    t.near(H.pumpCapacityAt(1500, 175), 1275.0, 0.01, 'between rating points it interpolates')
    t.ok(H.pumpCapacityAt(1500, 300) < 750.0, 'past 250 psi it keeps falling rather than holding')
    t.ok(H.pumpCapacityAt(1500, 1000) >= 0.0, 'and never goes negative')
    t.equal(H.pumpCapacityAt(0, 150), 0.0, 'a pump with no rating delivers nothing')

    -- -----------------------------------------------------------------------
    -- Water supply
    -- -----------------------------------------------------------------------

    t.describe('hydrant percent drop')

    t.near(H.percentDrop(80, 72), 10.0, 0.01, 'an 80 to 72 psi drop is 10 percent')
    t.near(H.percentDrop(80, 40), 50.0, 0.01, 'an 80 to 40 psi drop is 50 percent')
    t.equal(H.percentDrop(80, 80), 0.0, 'no drop is zero percent')
    t.equal(H.percentDrop(0, 0), 100.0, 'a dead hydrant reads as fully dropped rather than dividing by zero')
    t.equal(H.percentDrop(80, 100), 0.0, 'a residual above static clamps at zero rather than going negative')

    local total, mult = H.availableFlow(80, 76, 250)
    t.equal(mult, 3.0, 'a drop of 5 percent means three more lines are available')
    t.equal(total, 1000.0, 'so 250 gpm in use means 1000 gpm total')

    local _, mult15 = H.availableFlow(80, 69, 250)
    t.equal(mult15, 2.0, 'a drop between 11 and 15 percent means two more lines')

    local _, mult25 = H.availableFlow(80, 64, 250)
    t.equal(mult25, 1.0, 'a drop between 16 and 25 percent means one more line')

    local _, multOver = H.availableFlow(80, 40, 250)
    t.ok(multOver < 1.0, 'past 25 percent, less than one more line is available')
    t.ok(multOver > 0.0, 'but the number degrades smoothly instead of snapping to zero')

    t.describe('cavitation')

    local ok1 = H.isCavitating(50, 500, 1000)
    t.equal(ok1, false, 'good intake pressure with spare supply is not cavitating')

    local bad1, sev1 = H.isCavitating(50, 1500, 1000)
    t.equal(bad1, true, 'drawing more than the supply can give cavitates')
    t.ok(sev1 > 0.0, 'and reports a severity')

    local bad2 = H.isCavitating(10, 500, 1000)
    t.equal(bad2, true, 'so does an intake below 20 psi even with nominal supply')

    local bad3, sev3 = H.isCavitating(0, 500, 0)
    t.equal(bad3, true, 'pumping with no supply at all cavitates')
    t.equal(sev3, 1.0, 'at full severity')

    t.describe('tank time')

    t.near(H.tankSecondsRemaining(500, 150), 200.0, 0.01,
        '500 gallons at 150 gpm lasts 200 seconds -- the reason a tank-only attack is short')
    t.equal(H.tankSecondsRemaining(500, 0), math.huge, 'a tank with nothing flowing lasts forever')
    t.equal(H.tankSecondsRemaining(0, 150), 0.0, 'an empty tank is already out')

    -- -----------------------------------------------------------------------
    -- The rule the plan promised to enforce here
    -- -----------------------------------------------------------------------

    t.describe('gear resistance is bounded')

    -- config/gear.lua is loaded as a plain chunk so this test does not need FiveM.
    local gearChunk = loadfile('config/gear.lua')
    t.ok(gearChunk ~= nil, 'config/gear.lua parses')

    if gearChunk then
        local env = { math = math, table = table, string = string, pairs = pairs, ipairs = ipairs }
        if setfenv then
            setfenv(gearChunk, env)
            gearChunk()
        else
            gearChunk = loadfile('config/gear.lua', 't', env)
            gearChunk()
        end

        local tiers = env.MIFireGear and env.MIFireGear.tiers
        t.ok(type(tiers) == 'table', 'and exposes a tier table')

        if type(tiers) == 'table' then
            local checked = 0
            for name, tier in pairs(tiers) do
                t.ok(type(tier.fireResist) == 'number' and tier.fireResist < 1.0,
                    ('the %s tier grants resistance, not immunity'):format(name))
                t.ok(tier.fireResist >= 0.0, ('the %s tier resistance is not negative'):format(name))
                checked = checked + 1
            end
            t.ok(checked > 0, 'and there is at least one tier to check')
        end
    end
end
