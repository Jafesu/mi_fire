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
    t.equal(Apparatus.validatePort(good, types, 1), nil, 'a well formed port passes')

    t.ok(Apparatus.validatePort({ type = 'discharge', x = 0, y = 0, z = 0 }, types, 1),
        'one with no id is rejected')

    t.ok(Apparatus.validatePort({ id = 'a', type = 'nonsense', x = 0, y = 0, z = 0 }, types, 1),
        'one with an unknown type is rejected -- the panel binds to these, so a typo is a '
        .. 'control that silently does nothing')

    t.ok(Apparatus.validatePort({ id = 'a', type = 'discharge', x = 0, y = 0 }, types, 1),
        'one missing an axis is rejected')

    t.describe('and a world coordinate pasted in by mistake is caught')

    -- The failure this prevents: offsets are local to the vehicle, and a world coordinate
    -- looks exactly like a valid port until a hose connects to a point in the sky.
    local worldCoord = { id = 'oops', type = 'discharge', x = -1193.4, y = -1487.2, z = 4.4 }
    local err = Apparatus.validatePort(worldCoord, types, 1)

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

    local errors = Apparatus.validate(dupes, types)
    t.equal(#errors, 1, 'exactly one complaint')
    t.ok(errors[1]:find('more than once') ~= nil,
        'because two ports sharing an id means a valve that opens the wrong outlet')

    -- -----------------------------------------------------------------------

    t.describe('every shipped profile is valid')

    for name, profile in pairs(MIFireApparatus.profiles) do
        local resolved = Apparatus.resolve(profile, MIFireApparatus.defaults)
        local problems = Apparatus.validate(resolved, MIFireApparatus.portTypes)

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

    t.ok(tanker.tankGallons > engine.tankGallons * 3,
        'a tanker carries an order of magnitude more water than an engine, which is the '
        .. 'whole reason the rig exists')

    t.describe('and the brush truck is the only one that pumps while moving')

    local brush = Apparatus.resolve(
        MIFireApparatus.profiles.brushtruck, MIFireApparatus.defaults)

    t.equal(brush.pumpAndRoll, true, 'pump-and-roll is the wildland tactic')
    t.ok(not engine.pumpAndRoll, 'and no structural engine does it')

    -- -----------------------------------------------------------------------

    t.describe('the config block the offset finder pastes is well formed')

    local line = Apparatus.format(good)

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

    t.equal(Apparatus.validatePort(boned, types, 1), nil,
        'and it needs no coordinates at all')

    t.describe('but a bone offset is a nudge, not a position')

    -- The distinction that matters: two metres from the vehicle origin is a plausible port,
    -- two metres from a bone means the wrong bone was picked and nobody noticed.
    local wrongBone = { id = 'ldh', type = 'discharge', bone = 'misc_e',
        x = 2.5, y = 0.0, z = 0.0 }
    local boneErr = Apparatus.validatePort(wrongBone, types, 1)

    t.ok(boneErr, 'a large offset from a bone is rejected')
    t.ok(boneErr:find('wrong one') ~= nil, 'and says the bone is probably wrong')

    t.describe('and it formats as a bone line')

    local boneLine = Apparatus.format({ id = 'ldh', type = 'discharge', bone = 'misc_e' })

    t.ok(boneLine:find('bone = "misc_e"') ~= nil, 'it names the bone')
    t.ok(boneLine:find('x = 0.000') == nil,
        'and does not write zero offsets, which read as a measurement someone took')

    local nudged = Apparatus.format({ id = 'ldh', type = 'discharge', bone = 'misc_e',
        x = 0.1, y = 0.0, z = 0.0 })
    t.ok(nudged:find('x = 0.100') ~= nil, 'but a real nudge is kept')

    -- -----------------------------------------------------------------------

    t.describe('a port is a zone, not a point')

    -- Aiming at a single point to open a locker is precision for its own sake. A gear
    -- compartment is a metre and a half of truck and should be targetable like one.
    local reach = MIFireApparatus.portReach

    local locker = { id = 'gear1', type = 'gear', x = -1.2, y = -2.0, z = 0.2 }
    local outlet = { id = 'd1', type = 'discharge', x = -0.9, y = 0.2, z = -0.4 }

    local _, lockerRadius = Apparatus.reach(locker, reach)
    local _, outletRadius = Apparatus.reach(outlet, reach)

    t.ok(lockerRadius > outletRadius,
        'a compartment is more generous than an outlet -- connecting a line to the right '
        .. 'discharge is the interaction, and six generous zones side by side means picking '
        .. 'from a list instead of pointing at one')

    t.describe('and it defaults by type without being declared')

    t.near(lockerRadius, reach.gear, 0.001, 'a gear port gets the gear reach')
    t.near(select(2, Apparatus.reach({ type = 'nonsense' }, reach)), reach.default, 0.001,
        'and an unlisted type falls back to the default rather than to nothing')

    t.describe('an explicit radius wins')

    t.near(select(2, Apparatus.reach({ type = 'gear', radius = 0.4 }, reach)), 0.4, 0.001,
        'a port that declares its own zone gets it')

    -- -----------------------------------------------------------------------

    t.describe('boxes are vehicle-aligned')

    -- The shape that matters for a rig. Compartments run along the side, and a sphere large
    -- enough to cover a long hose bed also covers half the crew cab.
    local bed = {
        id = 'hosebed1', type = 'hosebed', x = 0.0, y = -3.0, z = 0.9,
        size = { x = 2.0, y = 3.0, z = 0.8 },
    }

    t.equal(Apparatus.contains(bed, { x = 0.9, y = -4.0, z = 1.0 }, reach), true,
        'a point inside the box is inside')

    t.equal(Apparatus.contains(bed, { x = 0.0, y = -1.0, z = 0.9 }, reach), false,
        'and one beyond its length is not, even though it is close in the other two axes')

    t.equal(Apparatus.contains(bed, { x = 1.5, y = -3.0, z = 0.9 }, reach), false,
        'nor is one beyond its width')

    t.describe('spheres still work for anything that is round')

    t.equal(Apparatus.contains(outlet, { x = -0.9, y = 0.2, z = -0.4 }, reach), true,
        'dead on the outlet')
    t.equal(Apparatus.contains(outlet, { x = -0.9, y = 2.0, z = -0.4 }, reach), false,
        'and a metre and a half away is not')

    -- -----------------------------------------------------------------------

    t.describe('a zone the size of the truck is rejected')

    -- Worse than no zone: every port on that side answers at once, and the player picks from
    -- a list rather than pointing at the one they want.
    local huge = Apparatus.validatePort(
        { id = 'x', type = 'gear', x = 0, y = 0, z = 0, radius = 9.0 }, types, 1)

    t.ok(huge, 'a nine metre radius is rejected')
    t.ok(huge:find('covers most of the rig') ~= nil, 'and says why')

    t.ok(Apparatus.validatePort(
        { id = 'x', type = 'gear', x = 0, y = 0, z = 0, radius = -1 }, types, 1),
        'so is a negative one')

    t.ok(Apparatus.validatePort({ id = 'x', type = 'hosebed', x = 0, y = 0, z = 0,
        size = { x = 20.0, y = 1.0, z = 1.0 } }, types, 1),
        'and a box longer than the rig')

    t.describe('but a hose diameter on a discharge is not a box')

    -- `size` is overloaded: a box on a compartment, a hose diameter on an outlet. Worth being
    -- explicit about rather than silently reading 1.75 as a bounding box.
    t.equal(Apparatus.validatePort(
        { id = 'd', type = 'discharge', x = 0, y = 0, z = 0, size = 1.75 }, types, 1), nil,
        'a discharge may carry a numeric size')

    t.ok(Apparatus.validatePort(
        { id = 'g', type = 'gear', x = 0, y = 0, z = 0, size = 1.75 }, types, 1),
        'a compartment may not')

    -- -----------------------------------------------------------------------

    t.describe('a crosslay is a discharge')

    -- Asked directly, and worth asserting: an intake is water coming in from a hydrant or a
    -- draft, a crosslay is water going out. Modelling it as its own type would mean the pump
    -- panel, the hydraulics and the hose system each knowing two names mean one thing.
    local crosslay = {
        id = 'crosslay1', type = 'discharge', x = -0.9, y = 0.6, z = 0.4,
        size = 1.75, preconnected = { feet = 200 },
    }

    t.equal(Apparatus.validatePort(crosslay, types, 1), nil,
        'a preconnected crosslay is a valid discharge')

    local formatted = Apparatus.format(crosslay)
    t.ok(formatted:find('type = "discharge"') ~= nil, 'and it writes out as one')
end
