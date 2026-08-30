--- Fire engine tests.
---
--- Drives the real engine against stubbed natives: start an incident, tick it, apply
--- agents, and check what happened. `os.time` is replaced with a controllable clock so
--- spread intervals and reflash delays can be tested without waiting for them.
---
--- These run after `boot_spec.lua`, which has already loaded the stack. They reuse that
--- loaded state rather than reloading it.

return function(t)
    local Fire = MIFire.Fire
    local State = MIFire.State
    local Enums = MIFire.Enums

    -- -----------------------------------------------------------------------
    -- Controllable clock
    -- -----------------------------------------------------------------------

    local realTime = os.time
    local now = realTime()
    os.time = function() return now end

    local function advance(seconds) now = now + seconds end

    --- Run the engine for a number of seconds, one tick per second.
    local function run(seconds)
        for _ = 1, seconds do
            advance(1)
            Fire.tick(1.0)
        end
    end

    local function reset()
        Fire.stopAll()
        State.reset()
    end

    reset()

    -- -----------------------------------------------------------------------

    t.describe('starting an incident')

    local id = Fire.startIncident({
        coords = { x = 0.0, y = 0.0, z = 0.0 }, class = 'A', nodeCount = 3, radius = 4.0,
    })

    t.ok(id ~= nil, 'an incident starts')
    t.equal(State.countNodesForIncident(id), 3, 'and seeds the requested number of nodes')

    local info = Fire.describe(id)
    t.equal(info.class, 'A', 'and reports its class')
    t.ok(info.averageIntensity > 0, 'with its nodes already alight')

    local badId, err = Fire.startIncident({ coords = { x = 0, y = 0, z = 0 }, class = 'nonsense' })
    t.equal(badId, nil, 'an unknown class is refused')
    t.equal(err, 'UNKNOWN_CLASS', 'with a reason')

    local noCoords, coordErr = Fire.startIncident({ class = 'A' })
    t.equal(noCoords, nil, 'so is an incident with no coordinates')
    t.equal(coordErr, 'NO_COORDS', 'with a reason')

    reset()

    -- -----------------------------------------------------------------------

    t.describe('a fire grows')

    id = Fire.startIncident({ coords = { x = 0, y = 0, z = 0 }, class = 'A', nodeCount = 1 })
    local node = State.getNodesForIncident(id)[1]
    local startIntensity = node.intensity

    run(10)

    t.ok(node.intensity > startIntensity, 'intensity climbs while there is fuel')
    t.ok(node.fuel < node.resolved.fuel, 'and fuel is consumed as it burns')
    t.equal(node.state, Enums.NodeState.GROWING, 'a developing node is growing')

    reset()

    -- -----------------------------------------------------------------------

    t.describe('a fire runs out of fuel')

    -- Class D, because it does not spread -- so the incident really is down to one node
    -- and cannot quietly reseed itself while the fuel runs out.
    id = Fire.startIncident({ coords = { x = 0, y = 0, z = 0 }, class = 'D', nodeCount = 1 })
    node = State.getNodesForIncident(id)[1]

    -- Burn the fuel down directly rather than ticking for the several minutes it would
    -- really take. The point is what happens at zero, not how long zero takes to reach.
    node.fuel = 0.01
    run(2)

    t.equal(State.getNode(node.id), nil, 'a node with no fuel left is removed')
    t.equal(State.getIncident(id), nil, 'and an incident with no nodes is over')

    reset()

    -- -----------------------------------------------------------------------

    t.describe('the right agent knocks a fire down')

    id = Fire.startIncident({ coords = { x = 0, y = 0, z = 0 }, class = 'A', nodeCount = 1 })
    node = State.getNodesForIncident(id)[1]
    node.intensity = 50.0

    local result = Fire.applyAgent({ x = 0, y = 0, z = 0 }, 10.0, 'water',
        { gpm = 150, seconds = 2 })

    t.equal(result.nodesAffected, 1, 'water reaches the node')
    t.ok(result.intensityRemoved > 0, 'and removes intensity')
    t.ok(node.intensity < 50.0, 'so the fire is smaller than it was')

    -- Enough water to finish it.
    Fire.applyAgent({ x = 0, y = 0, z = 0 }, 10.0, 'water', { gpm = 150, seconds = 30 })
    t.equal(node.state, Enums.NodeState.KNOCKED_DOWN, 'and eventually it is knocked down')
    t.ok(node.fuel > 0, 'with fuel still in it, which is why it can come back')

    reset()

    -- -----------------------------------------------------------------------

    t.describe('the wrong agent makes it worse')

    -- Water on a Class B pool fire. This is the behaviour the whole agent matrix exists
    -- for, so it is asserted directly rather than trusted.
    id = Fire.startIncident({ coords = { x = 0, y = 0, z = 0 }, class = 'B', nodeCount = 1 })
    node = State.getNodesForIncident(id)[1]
    node.intensity = 40.0

    result = Fire.applyAgent({ x = 0, y = 0, z = 0 }, 10.0, 'water', { gpm = 150, seconds = 2 })

    t.ok(result.intensityRemoved < 0, 'water on a Class B fire adds intensity rather than removing it')
    t.ok(node.intensity > 40.0, 'and the node is burning harder than before')

    -- Foam on the same fire does the opposite.
    local before = node.intensity
    result = Fire.applyAgent({ x = 0, y = 0, z = 0 }, 10.0, 'foam', { gpm = 150, seconds = 2 })
    t.ok(result.intensityRemoved > 0, 'foam on the same fire removes intensity')
    t.ok(node.intensity < before, 'and knocks it back')

    reset()

    -- -----------------------------------------------------------------------

    t.describe('agents that do nothing, do nothing')

    -- ABC dry chemical is scored 0.0 against Class D: it is not Class D powder.
    id = Fire.startIncident({ coords = { x = 0, y = 0, z = 0 }, class = 'D', nodeCount = 1 })
    node = State.getNodesForIncident(id)[1]
    node.intensity = 50.0

    result = Fire.applyAgent({ x = 0, y = 0, z = 0 }, 10.0, 'dry_chem', { gpm = 150, seconds = 5 })
    t.equal(result.nodesAffected, 0, 'ABC dry chemical does not touch a Class D fire')
    t.equal(node.intensity, 50.0, 'and the fire is exactly as it was')

    -- Dry powder is the one that works.
    result = Fire.applyAgent({ x = 0, y = 0, z = 0 }, 10.0, 'dry_powder', { gpm = 150, seconds = 5 })
    t.ok(result.intensityRemoved > 0, 'Class D powder does work on it')

    reset()

    -- -----------------------------------------------------------------------

    t.describe('range matters')

    id = Fire.startIncident({ coords = { x = 0, y = 0, z = 0 }, class = 'A', nodeCount = 1 })
    node = State.getNodesForIncident(id)[1]
    node.intensity = 80.0

    local close = Fire.applyAgent({ x = 0, y = 0, z = 0 }, 30.0, 'water',
        { gpm = 150, seconds = 1 })

    node.intensity = 80.0
    local far = Fire.applyAgent({ x = 18.0, y = 0, z = 0 }, 30.0, 'water',
        { gpm = 150, seconds = 1 })

    t.ok(close.intensityRemoved > far.intensityRemoved,
        'water applied point blank does more than water applied from across the street')
    t.ok(far.intensityRemoved > 0, 'but distance still does something inside range')

    reset()

    -- -----------------------------------------------------------------------

    t.describe('flow matters')

    id = Fire.startIncident({ coords = { x = 0, y = 0, z = 0 }, class = 'A', nodeCount = 1 })
    node = State.getNodesForIncident(id)[1]

    node.intensity = 80.0
    local small = Fire.applyAgent({ x = 0, y = 0, z = 0 }, 10.0, 'water',
        { gpm = 100, seconds = 1 })

    node.intensity = 80.0
    local big = Fire.applyAgent({ x = 0, y = 0, z = 0 }, 10.0, 'water',
        { gpm = 250, seconds = 1 })

    t.ok(big.intensityRemoved > small.intensityRemoved,
        'a 2.5 inch line does more than a 1.75 inch line')

    -- But with diminishing returns, which is why flowExponent is below 1.
    t.ok(big.intensityRemoved < small.intensityRemoved * 2.5,
        'though not proportionally more -- past a point you are wetting wet things')

    reset()

    -- -----------------------------------------------------------------------

    t.describe('a knocked down fire can reflash')

    id = Fire.startIncident({ coords = { x = 0, y = 0, z = 0 }, class = 'A', nodeCount = 1 })
    node = State.getNodesForIncident(id)[1]

    node.intensity = 0.0
    node.state = Enums.NodeState.KNOCKED_DOWN
    node.reflashAt = now + 5

    run(6)

    t.equal(node.state, Enums.NodeState.GROWING, 'a node with a reflash due comes back')
    t.ok(node.intensity > 0, 'burning again')

    reset()

    -- -----------------------------------------------------------------------

    t.describe('overhaul makes a knockdown permanent')

    id = Fire.startIncident({ coords = { x = 0, y = 0, z = 0 }, class = 'A', nodeCount = 1 })
    node = State.getNodesForIncident(id)[1]

    node.intensity = 0.0
    node.state = Enums.NodeState.KNOCKED_DOWN
    node.reflashAt = now + 3
    node.overhaulProgress = 0.0

    -- Keep working the node after knockdown -- this is overhaul.
    Fire.applyAgent({ x = 0, y = 0, z = 0 }, 10.0, 'water',
        { gpm = 150, seconds = node.resolved.overhaulSeconds + 1 })

    t.equal(node.state, Enums.NodeState.OVERHAULED, 'sustained water after knockdown overhauls it')
    t.equal(node.reflashAt, nil, 'and cancels the pending reflash')

    run(3)
    t.ok(node.state == Enums.NodeState.OVERHAULED or State.getNode(node.id) == nil,
        'an overhauled node does not come back')

    reset()

    -- -----------------------------------------------------------------------

    t.describe('fire spreads')

    id = Fire.startIncident({ coords = { x = 0, y = 0, z = 0 }, class = 'wildland', nodeCount = 1 })
    node = State.getNodesForIncident(id)[1]
    node.intensity = 100.0

    -- Wildland spreads on an 8 second interval at 55% base chance. Sixty seconds is
    -- plenty for at least one to take, without being so long the test is meaningless.
    run(60)

    t.ok(State.countNodesForIncident(id) > 1, 'a wildland fire spreads to new nodes')

    reset()

    t.describe('wind drives a wildland fire, not just steers it')

    -- Reported from a live test: /fire wind appeared to do nothing. It was steering
    -- direction and reach but never rate, which is close to invisible. Wind now shortens
    -- the interval between spread attempts and improves each one.
    local function spreadTrial(className, windSpeed, seconds)
        reset()
        MIFire.Spread.setWind(math.rad(90), windSpeed)
        local trialId = Fire.startIncident({
            coords = { x = 0, y = 0, z = 0 }, class = className, nodeCount = 3, radius = 5.0,
        })
        run(seconds)
        return State.countNodesForIncident(trialId)
    end

    -- Averaged, because a single run of a probabilistic system proves nothing.
    local function averageNodes(className, windSpeed, seconds, runs)
        local total = 0
        for _ = 1, runs do total = total + spreadTrial(className, windSpeed, seconds) end
        return total / runs
    end

    local calm = averageNodes('wildland', 0.0, 120, 12)
    local gale = averageNodes('wildland', 0.9, 120, 12)

    t.ok(gale > calm * 1.5,
        'a wildland fire in strong wind grows substantially faster than one in still air')

    t.describe('but only for classes that care about wind')

    -- Class A has windInfluence 0. A gale should do nothing to a sofa fire indoors.
    local calmA = averageNodes('A', 0.0, 120, 12)
    local galeA = averageNodes('A', 0.9, 120, 12)

    t.ok(math.abs(galeA - calmA) < calmA * 0.35,
        'a class with no wind influence spreads the same in a gale as in still air')

    reset()

    t.describe('some classes do not spread')

    id = Fire.startIncident({ coords = { x = 0, y = 0, z = 0 }, class = 'D', nodeCount = 1 })
    node = State.getNodesForIncident(id)[1]
    node.intensity = 100.0
    run(60)

    t.equal(State.countNodesForIncident(id), 1,
        'a Class D fire burns where it is and does not creep')

    reset()

    -- -----------------------------------------------------------------------

    t.describe('limits hold')

    id = Fire.startIncident({ coords = { x = 0, y = 0, z = 0 }, class = 'wildland', nodeCount = 1 })
    node = State.getNodesForIncident(id)[1]
    node.intensity = 100.0

    run(400)

    local class = MIFire.FireClass.resolve('wildland')
    t.ok(State.countNodesForIncident(id) <= class.spreadMaxNodes,
        'a spreading fire stops at its class node cap')
    t.ok(State.countNodes() <= Config.limits.maxNodesTotal,
        'and the global node cap is never exceeded')

    reset()

    t.describe('the incident cap holds')

    local started = 0
    for _ = 1, Config.limits.maxIncidents + 5 do
        if Fire.startIncident({ coords = { x = 0, y = 0, z = 0 }, class = 'A', nodeCount = 1 }) then
            started = started + 1
        end
    end

    t.equal(started, Config.limits.maxIncidents,
        'no more incidents start than the configured maximum')

    local capped, capErr = Fire.startIncident({ coords = { x = 0, y = 0, z = 0 }, class = 'A' })
    t.equal(capped, nil, 'and the next one is refused')
    t.equal(capErr, 'INCIDENT_CAP', 'with a reason')

    t.describe('stopping')

    local stopped = Fire.stopAll()
    t.equal(stopped, Config.limits.maxIncidents, 'stopAll stops everything it started')
    t.equal(MIFire.Util.count(State.getIncidents()), 0, 'leaving nothing burning')
    t.equal(State.countNodes(), 0, 'and no orphaned nodes behind')

    -- -----------------------------------------------------------------------

    reset()
    os.time = realTime
end
