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
end
