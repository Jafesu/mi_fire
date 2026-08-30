--- Sprinkler tests.
---
--- Two things are being protected here. The first is that head flow follows the real
--- orifice formula and lands on published figures. The second is the design invariant:
--- **sprinklers buy time, they do not win.** A configuration where a system outlasts a
--- working fire has quietly deleted the job, and that is easy to do by accident while
--- tuning tank sizes.

return function(t)
    local H = dofile('shared/hydraulics.lua')
    local S = dofile('config/sprinklers.lua')
    local A = dofile('config/agents.lua')

    --- Q = K * sqrt(P), the same orifice relationship as a smooth bore nozzle.
    local function headFlow(headType, psi)
        return headType.kFactor * math.sqrt(psi)
    end

    -- -----------------------------------------------------------------------

    t.describe('sprinkler head flow')

    local ordinary = S.headTypes.ordinary
    local tankPsi = S.hydraulics.tankPressurePsi
    local fdcPsi = S.hydraulics.fdcPressurePsi

    t.equal(ordinary.kFactor, 5.6, 'the standard head is K5.6')

    -- Published: a K5.6 head at 15 psi flows about 21.7 gpm.
    t.near(headFlow(ordinary, 15), 21.7, 0.2,
        'a K5.6 head at 15 psi flows about 21.7 gpm')

    -- Quadrupling pressure doubles flow, because flow follows the square root.
    t.near(headFlow(ordinary, 60), headFlow(ordinary, 15) * 2, 0.01,
        'four times the pressure gives twice the flow')

    t.ok(headFlow(ordinary, fdcPsi) > headFlow(ordinary, tankPsi),
        'pumping into the FDC flows more per head than the tank does -- the reason to connect')

    local esfr = S.headTypes.esfr
    t.ok(esfr.kFactor > ordinary.kFactor, 'an ESFR head is a bigger orifice than a standard head')
    t.ok(esfr.coverageRadius > ordinary.coverageRadius, 'and covers more floor')

    t.describe('head temperature ratings')

    -- Ratings must be strictly ordered, or "install a higher-rated head so it does not
    -- trip on a hot day" stops meaning anything.
    local ordered = { 'ordinary', 'intermediate', 'high', 'extra_high' }
    for i = 1, #ordered - 1 do
        local lower, higher = S.headTypes[ordered[i]], S.headTypes[ordered[i + 1]]
        t.ok(higher.temperatureRating > lower.temperatureRating,
            ('%s is rated hotter than %s'):format(ordered[i + 1], ordered[i]))
        t.ok(higher.activationHeat > lower.activationHeat,
            ('%s needs more heat to fuse than %s'):format(ordered[i + 1], ordered[i]))
    end

    for name, head in pairs(S.headTypes) do
        t.ok(head.activationHeat > 0 and head.activationHeat < 100,
            ('the %s head fuses somewhere inside the 0-100 heat scale'):format(name))
    end

    -- -----------------------------------------------------------------------

    t.describe('sprinklers buy time, they do not win')

    local tank = S.tank.defaultGallons
    local perHead = headFlow(ordinary, tankPsi)

    local twoHeads = H.tankSecondsRemaining(tank, perHead * 2)
    local sixHeads = H.tankSecondsRemaining(tank, perHead * 6)

    -- Long enough that a crew has a reason to hurry rather than a reason not to bother.
    t.ok(twoHeads >= 300, 'two heads run for at least five minutes')

    -- Short enough that nobody can treat a sprinkler as the plan. A serious fire opens
    -- more heads, and more heads drain the tank faster -- the system fails hardest
    -- exactly when it is needed most, which is the correct and interesting behaviour.
    t.ok(sixHeads <= 600, 'six heads drain the tank inside ten minutes')
    t.ok(sixHeads < twoHeads, 'a bigger fire opens more heads and runs the tank down faster')

    -- The failure mode this whole test exists to catch.
    t.ok(H.tankSecondsRemaining(S.tank.maximumGallons, perHead * 6) <= 3600,
        'even the largest configurable tank cannot outlast an hour of serious flow')

    t.describe('deluge drains faster than a per-head system')

    t.equal(S.systemTypes.deluge.perHeadActivation, false,
        'a deluge system does not wait for individual heads')
    t.equal(S.systemTypes.wet.perHeadActivation, true,
        'a wet pipe system fuses heads individually -- only the ones over the fire')

    t.ok(S.systemTypes.dry.activationDelaySeconds > S.systemTypes.wet.activationDelaySeconds,
        'a dry system takes real time to get water to the head, and the fire grows meanwhile')

    -- -----------------------------------------------------------------------

    t.describe('the agent can be wrong')

    -- Every agent a sprinkler can discharge must exist in the suppression matrix, or the
    -- system would silently do nothing at all.
    for agentName in pairs(S.agents) do
        t.ok(type(A.matrix[agentName]) == 'table',
            ('the %s sprinkler agent exists in the agent matrix'):format(agentName))
    end

    -- The behaviour that makes installing the right system a decision: a water system
    -- over a kitchen is not a partial win.
    t.ok(A.matrix.water.K.effectiveness < 0,
        'a water sprinkler over a Class K fire makes it worse, as it would in reality')
    t.ok(A.matrix.wet_chem.K.effectiveness > 1.0,
        'which is why a kitchen gets a wet chemical system instead')
    t.ok(A.matrix.water.B.effectiveness < 0,
        'and a water system over flammable liquid spreads it')
    t.ok(A.matrix.foam.B.effectiveness > 1.0,
        'which is why a Class B occupancy gets foam-water')

    -- -----------------------------------------------------------------------

    t.describe('reset is a real job')

    t.ok(#S.reset.steps >= 3, 'resetting a system takes several steps, not one button')
    t.equal(S.reset.autoResetSeconds, nil,
        'nothing quietly resets a system on a timer -- a crew has to do it')

    local hasHeadStep = false
    for _, step in ipairs(S.reset.steps) do
        if step.at == 'head' then hasHeadStep = true end
        t.ok((tonumber(step.seconds) or 0) > 0,
            ('the "%s" reset step takes time'):format(step.id))
    end
    t.ok(hasHeadStep, 'and every fused head has to be physically replaced')

    t.describe('tank bounds')

    t.ok(S.tank.minimumGallons < S.tank.defaultGallons, 'the default tank is above the minimum')
    t.ok(S.tank.defaultGallons < S.tank.maximumGallons, 'and below the maximum')
    t.ok(S.tank.lowWaterFraction > 0 and S.tank.lowWaterFraction < 1,
        'the low water warning fires somewhere before the tank is empty')
end
