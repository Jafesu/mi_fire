--- Apparatus profiles and ports.
---
--- The validation is the part that matters. A bad port surfaces as a hose connecting to
--- nothing halfway through an incident, by which point nobody is going to connect it to a
--- config file they edited last week -- so it has to be caught at boot.

return function(t)
    local Apparatus = MIFire.Apparatus
    local types = MIFireApparatus.portTypes

    t.describe('profiles inherit the defaults')

    local engine = Apparatus.resolve(
        MIFireApparatus.profiles.eengineht, MIFireApparatus.defaults)

    t.equal(engine.label, 'Engine', 'its own values win')
    t.equal(engine.maxDischargePsi, MIFireApparatus.defaults.maxDischargePsi,
        'and it inherits what it does not declare')

    t.describe('but ports are never merged')

    -- Merging arrays by index is how a five-entry list ends up with four stale entries on
    -- the end of it. That bug has been paid for once already in Util.merge.
    local withPorts = Apparatus.resolve(
        { ports = { { id = 'a', type = 'discharge', x = 0, y = 0, z = 0 } } },
        { ports = { { id = 'x' }, { id = 'y' }, { id = 'z' } } })

    t.equal(#withPorts.ports, 1, 'a profile with one port has one port, not three')

    -- -----------------------------------------------------------------------

    t.describe('a port has to be a port')

    local good = { id = 'crosslay1', type = 'discharge', x = 1.1, y = 2.2, z = 0.9 }
    t.equal(Apparatus.validatePort(good, types, 1, MIFireApparatus.portShapes), nil, 'a well formed port passes')

    t.ok(Apparatus.validatePort({ type = 'discharge', x = 0, y = 0, z = 0 }, types, 1, MIFireApparatus.portShapes),
        'one with no id is rejected')

    t.ok(Apparatus.validatePort({ id = 'a', type = 'nonsense', x = 0, y = 0, z = 0 }, types, 1, MIFireApparatus.portShapes),
        'one with an unknown type is rejected -- the panel binds to these, so a typo is a '
        .. 'control that silently does nothing')

    t.ok(Apparatus.validatePort({ id = 'a', type = 'discharge', x = 0, y = 0 }, types, 1, MIFireApparatus.portShapes),
        'one missing an axis is rejected')

    t.describe('and a world coordinate pasted in by mistake is caught')

    -- The failure this prevents: offsets are local to the vehicle, and a world coordinate
    -- looks exactly like a valid port until a hose connects to a point in the sky.
    local worldCoord = { id = 'oops', type = 'discharge', x = -1193.4, y = -1487.2, z = 4.4 }
    local err = Apparatus.validatePort(worldCoord, types, 1, MIFireApparatus.portShapes)

    t.ok(err, 'a coordinate hundreds of metres from the vehicle origin is rejected')
    t.ok(err:find('local to the vehicle') ~= nil, 'and the message says why')

    -- -----------------------------------------------------------------------

    t.describe('duplicate port ids are caught')

    local dupes = {
        ports = {
            { id = 'rear', type = 'discharge', x = 0, y = -3, z = 1 },
            { id = 'rear', type = 'discharge', x = 0.5, y = -3, z = 1 },
        },
    }

    local errors = Apparatus.validate(dupes, types, MIFireApparatus.portShapes)
    t.equal(#errors, 1, 'exactly one complaint')
    t.ok(errors[1]:find('more than once') ~= nil,
        'because two ports sharing an id means a valve that opens the wrong outlet')

    -- -----------------------------------------------------------------------

    t.describe('every shipped profile is valid')

    for name, profile in pairs(MIFireApparatus.profiles) do
        local resolved = Apparatus.resolve(profile, MIFireApparatus.defaults)
        local problems = Apparatus.validate(resolved, MIFireApparatus.portTypes, MIFireApparatus.portShapes)

        t.equal(#problems, 0,
            ('%s has no configuration errors%s'):format(name,
                #problems > 0 and (': ' .. problems[1]) or ''))
    end

    t.describe('and declares a panel family')

    for name, profile in pairs(MIFireApparatus.profiles) do
        local resolved = Apparatus.resolve(profile, MIFireApparatus.defaults)
        t.ok(type(resolved.panelFamily) == 'string' and resolved.panelFamily ~= '',
            ('%s names a panel family'):format(name))
    end

    -- -----------------------------------------------------------------------

    t.describe('a rig without a pump is not offered one')

    local rescue = Apparatus.resolve(
        MIFireApparatus.profiles.erescueht, MIFireApparatus.defaults)

    t.equal(Apparatus.hasPump(rescue), false,
        'a heavy rescue carries no pump, and offering a pump panel on one teaches a player '
        .. 'the resource does not know what the trucks are')

    t.equal(Apparatus.hasPump(engine), true, 'an engine does')

    -- -----------------------------------------------------------------------

    t.describe('the tanker is the outlier it should be')

    local tanker = Apparatus.resolve(
        MIFireApparatus.profiles.etankerht, MIFireApparatus.defaults)

    -- The multiple moved when the engine went from 750 to the 1000 its real rig carries. The
    -- claim being tested is that a tanker is a different kind of vehicle rather than a bigger
    -- engine, and threefold still says that.
    t.ok(tanker.tankGallons >= engine.tankGallons * 2.5,
        ('a tanker carries far more than an engine (%d against %d), which is the whole reason '
            .. 'the rig exists'):format(tanker.tankGallons, engine.tankGallons))

    t.describe('and the brush truck is the only one that pumps while moving')

    local brush = Apparatus.resolve(
        MIFireApparatus.profiles.brushtruck, MIFireApparatus.defaults)

    t.equal(brush.pumpAndRoll, true, 'pump-and-roll is the wildland tactic')
    t.ok(not engine.pumpAndRoll, 'and no structural engine does it')

    -- -----------------------------------------------------------------------

    t.describe('the config block the offset finder pastes is well formed')

    local line = Apparatus.format(good, MIFireApparatus.portShapes)

    t.ok(line:find('id = "crosslay1"') ~= nil, 'it names the id')
    t.ok(line:find('type = "discharge"') ~= nil, 'and the type')
    t.ok(line:find('x = 1.100') ~= nil, 'and the offset, to three decimals')

    -- It has to be loadable Lua, since the whole point is pasting it into a config file.
    local chunk = loadstring and loadstring('return {' .. line .. '}') or load('return {' .. line .. '}')
    t.ok(chunk ~= nil, 'and it parses as Lua, which is the only thing it is for')

    -- -----------------------------------------------------------------------

    t.describe('a port can hang off a bone instead of an offset')

    -- Worth having because a bone needs no measuring and survives the model being updated.
    -- If the vehicle author put a bone at the hookup, that bone *is* the hookup, and it beats
    -- anything produced by nudging a marker around by hand.
    local boned = { id = 'ldh', type = 'discharge', bone = 'misc_e' }

    t.equal(Apparatus.anchor(boned), 'bone', 'a port with a bone is bone-anchored')
    t.equal(Apparatus.anchor(good), 'offset', 'one without is offset-anchored')

    t.equal(Apparatus.validatePort(boned, types, 1, MIFireApparatus.portShapes), nil,
        'and it needs no coordinates at all')

    t.describe('but a bone offset is a nudge, not a position')

    -- The distinction that matters: two metres from the vehicle origin is a plausible port,
    -- two metres from a bone means the wrong bone was picked and nobody noticed.
    local wrongBone = { id = 'ldh', type = 'discharge', bone = 'misc_e',
        x = 2.5, y = 0.0, z = 0.0 }
    local boneErr = Apparatus.validatePort(wrongBone, types, 1, MIFireApparatus.portShapes)

    t.ok(boneErr, 'a large offset from a bone is rejected')
    t.ok(boneErr:find('wrong one') ~= nil, 'and says the bone is probably wrong')

    t.describe('and it formats as a bone line')

    local boneLine = Apparatus.format({ id = 'ldh', type = 'discharge', bone = 'misc_e' },
        MIFireApparatus.portShapes)

    t.ok(boneLine:find('bone = "misc_e"') ~= nil, 'it names the bone')
    t.ok(boneLine:find('x = 0.000') == nil,
        'and does not write zero offsets, which read as a measurement someone took')

    local nudged = Apparatus.format({ id = 'ldh', type = 'discharge', bone = 'misc_e',
        x = 0.1, y = 0.0, z = 0.0 }, MIFireApparatus.portShapes)
    t.ok(nudged:find('x = 0.100') ~= nil, 'but a real nudge is kept')

    -- -----------------------------------------------------------------------

    t.describe('some ports are areas and some are fittings')

    -- The distinction is physical rather than a setting. A gear locker is a metre and a half of
    -- compartment and making someone aim at one point to open it is precision for its own sake.
    -- A discharge is a specific piece of brass you couple a specific line to, and being asked
    -- which one is the interaction rather than an obstacle.
    local shapes = MIFireApparatus.portShapes
    local heights = MIFireApparatus.zoneHeight

    t.equal(Apparatus.shape({ type = 'gear' }, shapes), 'zone', 'a gear locker is an area')
    t.equal(Apparatus.shape({ type = 'hosebed' }, shapes), 'zone', 'so is a hose bed')
    t.equal(Apparatus.shape({ type = 'panel' }, shapes), 'zone', 'and the pump panel')

    t.equal(Apparatus.shape({ type = 'discharge' }, shapes), 'point', 'a discharge is a fitting')
    t.equal(Apparatus.shape({ type = 'intake' }, shapes), 'point', 'so is an intake')

    -- -----------------------------------------------------------------------

    t.describe('an area is the footprint that was walked')

    -- Corners rather than a centre and a size, because a size guesses at a shape nobody
    -- measured -- and a compartment running along a chamfered corner is not a box.
    local locker = {
        id = 'gear1', type = 'gear',
        corners = {
            { x = -1.7, y = -3.0, z = 0.2 },
            { x = -0.7, y = -3.0, z = 0.2 },
            { x = -0.7, y = -1.2, z = 0.2 },
            { x = -1.7, y = -1.2, z = 0.2 },
        },
    }

    t.equal(Apparatus.contains(locker, { x = -1.2, y = -2.0, z = 0.2 }, shapes, heights), true,
        'a point inside the footprint is inside')

    t.equal(Apparatus.contains(locker, { x = -1.2, y = 0.5, z = 0.2 }, shapes, heights), false,
        'and one past the end of it is not, however close it is in the other axes')

    t.equal(Apparatus.contains(locker, { x = 0.5, y = -2.0, z = 0.2 }, shapes, heights), false,
        'nor one on the far side of the rig')

    t.describe('and it is not a rectangle unless you walked one')

    -- The crossing test takes any shape, which is the point of walking corners rather than
    -- declaring a width and a depth.
    local wedge = {
        id = 'w', type = 'tool',
        corners = {
            { x = 0.0, y = 0.0, z = 0.0 },
            { x = 2.0, y = 0.0, z = 0.0 },
            { x = 0.0, y = 2.0, z = 0.0 },
        },
    }

    t.equal(Apparatus.contains(wedge, { x = 0.3, y = 0.3, z = 0.0 }, shapes, heights), true,
        'a point inside the triangle is inside')
    t.equal(Apparatus.contains(wedge, { x = 1.6, y = 1.6, z = 0.0 }, shapes, heights), false,
        'and one outside the hypotenuse is not -- which a bounding box would have got wrong')

    t.describe('height comes from the type, centred on the walk')

    -- Walk the corners at the height of the compartment opening and the zone lands around it,
    -- rather than starting at your feet.
    local floor, ceiling = Apparatus.zoneBounds(locker, heights)

    t.ok(floor < 0.2 and ceiling > 0.2, 'the corners sit inside the height, not at its floor')
    t.near(ceiling - floor, heights.gear, 0.001, 'and the height is the one for that type')

    t.equal(Apparatus.contains(locker, { x = -1.2, y = -2.0, z = 5.0 }, shapes, heights), false,
        'so a point well above the rig is outside')

    -- -----------------------------------------------------------------------

    t.describe('a fitting is a point and stays tight')

    local outlet = { id = 'd1', type = 'discharge', x = -0.9, y = 0.2, z = -0.4 }

    t.equal(Apparatus.contains(outlet, { x = -0.9, y = 0.2, z = -0.4 }, shapes, heights), true,
        'dead on the outlet')
    t.equal(Apparatus.contains(outlet, { x = -0.9, y = 1.4, z = -0.4 }, shapes, heights), false,
        'and a metre away is not, because picking the right outlet is the interaction')

    -- -----------------------------------------------------------------------

    t.describe('an area without corners is rejected')

    local noCorners = Apparatus.validatePort(
        { id = 'g', type = 'gear', x = 0, y = 0, z = 0 }, types, 1, shapes)

    t.ok(noCorners, 'a gear locker with a position and no footprint fails')
    t.ok(noCorners:find('corners') ~= nil, 'and says what it needs')

    t.ok(Apparatus.validatePort({ id = 'g', type = 'gear',
        corners = { { x = 0, y = 0, z = 0 }, { x = 1, y = 0, z = 0 } } }, types, 1, shapes),
        'two corners is not a footprint')

    t.equal(Apparatus.validatePort(locker, types, 1, shapes), nil,
        'and a walked one passes')

    t.describe('a fitting with corners instead of a position is rejected')

    t.ok(Apparatus.validatePort({ id = 'd', type = 'discharge' }, types, 1, shapes),
        'a discharge still needs somewhere to be')

    -- -----------------------------------------------------------------------

    t.describe('every shipped zone port has been walked')

    for name, profile in pairs(MIFireApparatus.profiles) do
        for _, port in ipairs(profile.ports or {}) do
            if Apparatus.shape(port, shapes) == 'zone' then
                t.ok(type(port.corners) == 'table' and #port.corners >= 3,
                    ('%s: %s has a walked footprint'):format(name, port.id))
            end
        end
    end

    -- -----------------------------------------------------------------------

    t.describe('a crosslay is a discharge')

    -- Asked directly, and worth asserting: an intake is water coming in from a hydrant or a
    -- draft, a crosslay is water going out. Modelling it as its own type would mean the pump
    -- panel, the hydraulics and the hose system each knowing two names mean one thing.
    local crosslay = {
        id = 'crosslay1', type = 'discharge', x = -0.9, y = 0.6, z = 0.4,
        size = 1.75, preconnected = { feet = 200 },
    }

    t.equal(Apparatus.validatePort(crosslay, types, 1, MIFireApparatus.portShapes), nil,
        'a preconnected crosslay is a valid discharge')

    local formatted = Apparatus.format(crosslay, shapes)
    t.ok(formatted:find('type = "discharge"') ~= nil, 'and it writes out as one')
end
