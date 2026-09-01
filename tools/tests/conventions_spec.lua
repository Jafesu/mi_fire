--- Conventions that are checkable, so they are checked rather than remembered.
---
--- Every rule here exists because breaking it produced a bug that was hard to see. A note in
--- CONVENTIONS.md is worth something; a test that fails is worth more.

return function(t)
    ---@param path string
    ---@return string|nil
    local function read(path)
        local handle = io.open(path, 'r')
        if not handle then return nil end
        local source = handle:read('*a')
        handle:close()
        return source
    end

    --- XML with its comments removed.
    ---
    --- The same reason `findCode` exists for Lua: a rule written down in a file should not trip
    --- its own check. The camera check caught the invented hash inside the paragraph explaining
    --- that it had been removed, which is correct behaviour from the test and a bad question to
    --- be asking of the text.
    ---@param source string
    ---@return string
    local function withoutXmlComments(source)
        return (source:gsub('<!%-%-.-%-%->', ''))
    end

    --- Lines that are not comments, so a rule written down in a file does not trip its own
    --- check.
    ---@param source string
    ---@param pattern string
    ---@return string|nil
    local function findCode(source, pattern)
        for line in source:gmatch('[^\n]+') do
            if not line:match('^%s*%-%-') and line:find(pattern) then return line end
        end
        return nil
    end

    local clientFiles = {
        'bridge/target/ox_target.lua',
        'client/main.lua',
        'client/modules/notify.lua',
        'client/modules/hud.lua',
        'client/modules/fire/render.lua',
        'client/modules/fire/init.lua',
        'client/modules/turnout/init.lua',
        'client/modules/scba/pass.lua',
        'client/modules/exposure/init.lua',
        'client/modules/smoke/init.lua',
        'client/modules/scorch/init.lua',
        'client/modules/hose/init.lua',
        'client/modules/apparatus/init.lua',
        'client/modules/placement/init.lua',
        'client/modules/offsetfinder/scan.lua',
        'client/modules/offsetfinder/init.lua',
    }

    -- -----------------------------------------------------------------------

    t.describe('client files do not call server-only ox_lib functions')

    -- `lib.addCommand` is server-side only. On a client it raises "No such export addCommand
    -- in resource ox_lib" and the command never registers -- which presents as the command
    -- silently doing nothing rather than as an obvious failure. `/fireoffset` shipped that
    -- way and was only found by someone running it.
    for _, path in ipairs(clientFiles) do
        local source = read(path)

        if source then
            t.equal(findCode(source, 'lib%.addCommand'), nil,
                ('%s uses RegisterCommand rather than lib.addCommand'):format(path))
        end
    end

    -- -----------------------------------------------------------------------

    t.describe('the interaction rule is kept')

    -- Every world interaction goes through ox_target. Keybinds exist only for controls held
    -- during an action already in progress. The rule is only worth having if it is checked,
    -- so the exceptions are named here rather than left to judgement.
    local pollingAllowed = {
        ['client/modules/placement/init.lua'] = true,   -- the gizmo is a held-input tool
        ['client/modules/exposure/init.lua'] = true,    -- stop-drop-roll is a held control
    }

    for _, path in ipairs(clientFiles) do
        local source = read(path)

        if source and not pollingAllowed[path] then
            t.equal(findCode(source, 'IsControlJustPressed'), nil,
                ('%s does not poll for a keypress to interact with the world'):format(path))

            t.equal(findCode(source, 'DrawText3D'), nil,
                ('%s does not use a drawtext prompt'):format(path))
        end
    end

    -- -----------------------------------------------------------------------

    t.describe('nothing hands damage back to the engine')

    -- The fault that cost two sessions, twice: StartScriptFire under every fire node and
    -- StartEntityFire on a burning player both apply the engine's own damage, which knows
    -- nothing about turnout gear or any other number this resource computes.
    --
    -- StopEntityFire is fine -- putting someone out is not applying damage.
    for _, path in ipairs(clientFiles) do
        local source = read(path)

        if source then
            t.equal(findCode(source, 'StartEntityFire'), nil,
                ('%s does not set a ped alight with the engine\'s own fire'):format(path))
        end
    end

    local render = read('client/modules/fire/render.lua')

    if render then
        -- The one call site is allowed to exist, because it is config-gated and off, and a
        -- server that understands the trade can turn it on. What is not allowed is it being
        -- on by default, which is asserted in fire_spec.
        t.ok(findCode(render, 'StartScriptFire') ~= nil,
            'the script fire path still exists for servers that want it')
    end

    -- -----------------------------------------------------------------------

    t.describe('the manifest lists each file once')

    -- `offsetfinder/scan.lua` appeared three times, because a wiring script that inserts a line
    -- was run three times and nothing objected. FiveM loads a duplicate entry twice, which for
    -- most files is merely waste and for one holding state is a bug nobody would look for.
    do
        local manifest = read('fxmanifest.lua')

        -- Per block, not across the whole file. The bridges are deliberately in both
        -- `client_scripts` and `server_scripts` -- one adapter, two sides -- and flagging that
        -- would be flagging the design.
        if manifest then
            for _, block in ipairs({ 'shared_scripts', 'client_scripts', 'server_scripts' }) do
                local body = manifest:match(block .. '%s*{(.-)}')

                if body then
                    local seen, duplicates = {}, {}

                    for path in body:gmatch("'([%w_/%.%-]+%.lua)'") do
                        if seen[path] then
                            duplicates[#duplicates + 1] = path
                        else
                            seen[path] = true
                        end
                    end

                    t.equal(#duplicates, 0,
                        ('%s declares each file once%s'):format(block,
                            #duplicates > 0 and (': ' .. table.concat(duplicates, ', ')) or ''))
                end
            end
        end
    end

    t.describe('and loads shared client helpers before what reads them')

    -- `hose` takes `MIFire.ApparatusClient` as a file-scope local. Loading it first bound nil,
    -- and the only symptom was an error the first time somebody aimed at a truck. The lazy
    -- lookup in that file makes it safe either way; this keeps the order honest as well.
    do
        local manifest = read('fxmanifest.lua')

        if manifest then
            local order = {}
            local index = 0

            for path in manifest:gmatch("'([%w_/%.%-]+%.lua)'") do
                index = index + 1
                order[path] = order[path] or index
            end

            local helpers = {
                'client/modules/apparatus/init.lua',
                'client/modules/placement/init.lua',
            }

            local consumers = {
                'client/modules/hose/init.lua',
                'client/modules/turnout/init.lua',
                'client/modules/offsetfinder/init.lua',
            }

            for _, helper in ipairs(helpers) do
                for _, consumer in ipairs(consumers) do
                    if order[helper] and order[consumer] then
                        t.ok(order[helper] < order[consumer],
                            ('%s loads before %s'):format(helper, consumer))
                    end
                end
            end
        end
    end

    -- -----------------------------------------------------------------------

    t.describe('player interactions use the player registration')

    -- ox_target keeps NPC peds and player peds apart: `addGlobalPed` never fires on a player.
    -- "Back up this line" was registered on the NPC one and could not appear on a colleague at
    -- any distance, under any condition -- an option that exists, passes review, and is
    -- unreachable.
    do
        local hose = read('client/modules/hose/init.lua')

        if hose then
            t.equal(findCode(hose, 'addGlobalPed'), nil,
                'the hose module targets players with addGlobalPlayer, not addGlobalPed')
        end

        local bridge = read('bridge/target/ox_target.lua')

        if bridge then
            t.ok(bridge:find('function Target.addGlobalPlayer') ~= nil,
                'the target bridge offers a player registration at all')
            t.ok(bridge:find('removeGlobalPlayer') ~= nil,
                'and takes it down again, or a restart leaves it behind')
        end
    end

    -- -----------------------------------------------------------------------

    t.describe('admin subcommands read their arguments from the right place')

    -- `/fire` passes the whole line, so `args[1]` is the subcommand name and a subcommand's own
    -- first argument is `args[2]`. Getting that wrong does not error: the value read is simply
    -- the subcommand's own name, so every call falls into the usage branch and prints help. It
    -- looks exactly like mistyping the command, which is why it survived being run and read.
    do
        local source = read('server/modules/admin/init.lua') or ''
        local split = source:find('function Admin.handle', 1, true)

        t.ok(split ~= nil, 'the dispatcher is where it is expected')

        if split then
            -- Only the dispatcher itself may look at args[1]; it is the one thing that
            -- legitimately wants the subcommand name.
            local definitions = source:sub(1, split - 1)
            local offender = findCode(definitions, 'args%[1%]')

            t.equal(offender, nil,
                'no subcommand reads args[1] -- that is the subcommand name, not an argument')
        end
    end

    -- -----------------------------------------------------------------------

    t.describe('the nozzle placements are usable numbers')

    -- These were found by nudging in game over two sessions, one of which was lost to a crash.
    -- They are not derivable from anything and nobody will notice a typo in them until they next
    -- pick up a line, so the shape is worth asserting even though the values cannot be.
    do
        local visuals = MIFireHose.visuals or {}

        for _, name in ipairs({ 'nozzleGrip', 'nozzleGripAiming' }) do
            local grip = visuals[name]

            if grip ~= nil then
                t.equal(type(grip), 'table', ('%s is a table'):format(name))

                t.ok(grip.bone == 'left' or grip.bone == 'right',
                    ('%s.bone is left or right'):format(name))

                for _, axis in ipairs({ 'x', 'y', 'z' }) do
                    t.equal(type(grip[axis]), 'number', ('%s.%s is a number'):format(name, axis))

                    -- An offset from a hand bone measured in metres. Anything approaching a
                    -- metre is a typo, and it puts the nozzle somewhere near the player's feet
                    -- or out in the road rather than in their hand.
                    t.ok(math.abs(grip[axis] or 0) < 0.5,
                        ('%s.%s is within half a metre of the hand'):format(name, axis))
                end

                for _, axis in ipairs({ 'rx', 'ry', 'rz' }) do
                    t.equal(type(grip[axis]), 'number', ('%s.%s is a number'):format(name, axis))

                    -- Wrapped, so a value carried over from nudging past a full turn does not
                    -- get copied into the config where it reads as nonsense.
                    t.ok((grip[axis] or 0) >= 0 and (grip[axis] or 0) < 360,
                        ('%s.%s is wrapped into 0-359'):format(name, axis))
                end
            end
        end
    end

    -- -----------------------------------------------------------------------

    t.describe('the nozzle is equipped, not glued to the hand')

    -- `CreateWeaponObject` makes a world object out of a weapon hash and it can be attached to
    -- a bone, which looks right in a screenshot and is useless: an attached object cannot be
    -- fired and carries no stance. A nozzle exists to put water on a fire, so it has to be a
    -- weapon the game has actually equipped.
    --
    -- This was believed to be impossible because `GiveWeaponToPed` appeared to be stripped by
    -- ox_inventory within a second. It was not. That was measured while the weapon had no
    -- archetype, and a weapon that does not exist is absent right after being given -- which
    -- looks exactly the same. The dead end cost a rebuild of the whole nozzle path.
    do
        local source = read('client/modules/hose/init.lua') or ''

        t.equal(findCode(source, 'CreateWeaponObject'), nil,
            'the hose client does not create the nozzle as a world object')

        t.ok(findCode(source, 'GiveWeaponToPed') ~= nil,
            'the hose client equips the nozzle as a weapon')

        -- Equipping without ever removing leaves a firefighter armed with a nozzle for the
        -- rest of the session, including after they put the line down.
        t.ok(findCode(source, 'RemoveWeaponFromPed') ~= nil,
            'and takes it away again')

        -- The stance is set from a movement clipset rather than a weaponanimations.meta,
        -- because that file replaces the game's whole animation set instead of merging into
        -- it -- both resources on this machine that ship one carry a 13,000 line copy of the
        -- vanilla data, and two of those cannot both be right.
        local clipset = (MIFireHose.visuals or {}).nozzleClipset
        t.ok(clipset == nil or type(clipset) == 'string',
            'nozzleClipset is a clipset name or nothing')

        -- Both of them. The hold is a weapon clipset through `SetPedStrafeClipset` and the
        -- walk is a movement clipset through `SetPedMovementClipset`, and either one left
        -- applied outlasts the nozzle -- on a ped with nothing in their hands.
        t.ok(findCode(source, 'ResetPedMovementClipset') ~= nil,
            'the carrying walk is cleared when the nozzle is put down')

        t.ok(findCode(source, 'ResetPedStrafeClipset') ~= nil,
            'and so is the hold')
    end

    -- -----------------------------------------------------------------------

    t.describe('shipped game data is well-formed XML')

    -- A double hyphen is illegal inside an XML comment, and the comments in these files are
    -- long and full of prose, where "--" is the natural way to punctuate an aside. Every meta
    -- here failed on it at first write.
    --
    -- It is worth a test because of what an invalid meta costs. These files are not read by
    -- this resource -- they are handed to the game, which parses them itself and is not obliged
    -- to explain a refusal. A weapon that does not appear, or worse a weapon file that takes
    -- other weapons down with it, is a long way from an unclosed comment in a paragraph nobody
    -- was reading.
    do
        local metas = {
            'data/weapons.meta',
            'data/weaponarchetypes.meta',
            'data/weaponanimations.meta',
        }

        for _, path in ipairs(metas) do
            local source = read(path)

            t.ok(source ~= nil, ('%s exists'):format(path))

            if source then
                t.ok(source:find('^%s*<%?xml', 1) ~= nil,
                    ('%s starts with an XML declaration'):format(path))

                -- Walk the comments and check the inside of each.
                local bad = nil
                local pos = 1

                while true do
                    local openAt = source:find('<!--', pos, true)
                    if not openAt then break end

                    local closeAt = source:find('-->', openAt + 4, true)
                    if not closeAt then
                        bad = 'unterminated comment'
                        break
                    end

                    local body = source:sub(openAt + 4, closeAt - 1)
                    if body:find('--', 1, true) then
                        bad = 'a double hyphen inside a comment'
                        break
                    end

                    pos = closeAt + 3
                end

                t.equal(bad, nil, ('%s has no illegal comment content'):format(path))
            end
        end
    end

    -- -----------------------------------------------------------------------

    t.describe('the weapon names real cameras, and no empty ones')

    -- A camera slot left empty is not "no camera" -- it is a lookup that finds nothing, and the
    -- game does that lookup when you aim, take cover, or move while firing. Two of these were
    -- empty and the third was `DEFAULT_FIRE_EXTINGUISHER_CAMERA`, which does not exist anywhere:
    -- it was written because it sounded like the right shape.
    --
    -- This cannot check that a hash is real, which is the failure that actually cost the most.
    -- It can check that one is present, which would have caught two of the three, and it records
    -- the shape of the mistake for whoever edits this next.
    do
        local weapons = withoutXmlComments(read('data/weapons.meta') or '')

        for _, tag in ipairs({ 'DefaultCameraHash', 'CoverCameraHash', 'RunAndGunCameraHash' }) do
            local paired = weapons:match('<' .. tag .. '>([^<]*)</' .. tag .. '>')
            local selfClosing = weapons:find('<' .. tag .. '%s*/>')

            t.equal(selfClosing, nil, ('%s is not left empty'):format(tag))
            t.ok(paired ~= nil and paired:gsub('%s', '') ~= '',
                ('%s names a camera'):format(tag))
        end

        -- The one invented value, by name. Cheap, and it never comes back.
        t.equal(weapons:find('DEFAULT_FIRE_EXTINGUISHER_CAMERA', 1, true), nil,
            'the invented camera hash is gone')
    end

    -- -----------------------------------------------------------------------

    t.describe('a volumetric weapon names the particle it fires')

    -- This one crashed the game. `FireType VOLUMETRIC_PARTICLE` makes the game emit a particle
    -- on every shot, and it takes the name from `FlashFx`. An empty `FlashFx` sends it looking
    -- for something that is not there, and it goes down natively on the first trigger pull --
    -- no script error, no warning, nothing in the log but a stack of game addresses.
    --
    -- It was left empty deliberately, on the reasoning that mi_fire draws its own water and the
    -- weapon needed no effect of its own. The field has to be populated whether or not it ever
    -- renders; the two chance values beside it are what decide that.
    --
    -- Nothing else in this repository could have caught it: the XML is valid, the weapon loads,
    -- and the fault only appears when someone pulls the trigger.
    do
        local weapons = withoutXmlComments(read('data/weapons.meta') or '')
        local fireType = weapons:match('<FireType>([%w_]+)</FireType>')

        if fireType == 'VOLUMETRIC_PARTICLE' then
            local flash = weapons:match('<FlashFx>([^<]*)</FlashFx>')

            t.ok(flash ~= nil and flash:gsub('%s', '') ~= '',
                'FireType VOLUMETRIC_PARTICLE has a FlashFx particle to fire')
        end

        -- A self-closing `<FlashFx />` is the shape the empty one actually took, and it would
        -- slip past a match on the paired form above.
        if fireType == 'VOLUMETRIC_PARTICLE' then
            t.equal(weapons:find('<FlashFx%s*/>'), nil,
                'and it is not the self-closing empty form')
        end
    end

    -- -----------------------------------------------------------------------

    t.describe('the nozzle weapon agrees across every file that names it')

    -- Four files have to say the same thing for a custom weapon to load, and nothing in Lua
    -- notices when they drift. The symptom is a weapon that silently never appears, which is
    -- indistinguishable from a missing archetype and cost a round of testing to diagnose once.
    do
        local weapons = read('data/weapons.meta') or ''
        local archetypes = read('data/weaponarchetypes.meta') or ''
        local hose = MIFireHose.visuals or {}

        local weaponName = weapons:match('<Name>(WEAPON_[%w_]+)</Name>')
        local weaponModel = weapons:match('<Model>([%w_]+)</Model>')
        local archetypeModel = archetypes:match('<modelName>([%w_]+)</modelName>')
        local archetypeTxd = archetypes:match('<txdName>([%w_]+)</txdName>')

        t.equal(weaponName, hose.nozzleWeapon,
            'config nozzleWeapon matches <Name> in data/weapons.meta')
        -- Normally these must match. While a model bisect is running they deliberately do not,
        -- and the marker is what separates "being tested" from "quietly broken" -- so the test
        -- still fails if the model is wrong and nobody said why.
        local diagnostic = weapons:find('DIAGNOSTIC', 1, true) ~= nil

        if diagnostic then
            t.ok(weaponModel ~= nil and weaponModel ~= archetypeModel,
                'a model bisect is running -- weapons.meta names a different model on purpose')
            t.ok(weapons:find('TO RESTORE', 1, true) ~= nil,
                'and it says how to put the real model back')
        else
            t.equal(weaponModel, archetypeModel,
                '<Model> in weapons.meta matches <modelName> in weaponarchetypes.meta')
        end
        t.equal(archetypeTxd, archetypeModel,
            'the archetype txdName matches its own modelName')

        -- The archetype's model, not the weapon's: during a bisect the weapon points elsewhere
        -- on purpose, but the archetype still declares ours and it still has to be shipped.
        t.ok(archetypeModel ~= nil and read('stream/' .. archetypeModel .. '.ydr') ~= nil,
            ('stream/%s.ydr is shipped'):format(tostring(archetypeModel)))

        -- The slot has to exist in the navigate order or the weapon is unreachable.
        local slot = weapons:match('<Slot>(SLOT_[%w_]+)</Slot>')
        t.ok(slot ~= nil and weapons:find('<Entry>' .. slot .. '</Entry>', 1, true) ~= nil,
            'the weapon slot appears in SlotNavigateOrder')
    end

    -- -----------------------------------------------------------------------

    t.describe('borrowed assets are declared, not hidden')

    -- `w_am_hose` belongs to SmartHose. Referencing a streamed model by name while that
    -- resource is installed copies nothing and redistributes nothing, which makes it fine for
    -- development and not fine to forget. The declaration is what the boot warning reads, so
    -- an undeclared borrow is a silent one.
    do
        local visuals = MIFireHose.visuals or {}
        local borrowed = visuals.borrowed or {}

        -- Base game names this check recognises. Anything else has to be declared as
        -- borrowed, which is the whole point -- a model or weapon that is neither is one
        -- nobody has thought about.
        local ours = {
            prop_fire_hosereel = true,
            prop_fire_hosereel_l1 = true,
            prop_fire_hosebox_01 = true,
            hei_prop_heist_hose_01 = true,

            -- Ours, built from CAD by tools/assets/nozzle/ and shipped in stream/.
            WEAPON_MINOZZLE = true,
        }

        for key, value in pairs(visuals) do
            if type(value) == 'string' and value:find('^[%w_]+$') and key ~= 'borrowed' then
                local vanilla = ours[value] or value:find('^prop_') or value:find('^hei_')

                t.ok(vanilla ~= nil or borrowed[value] ~= nil,
                    ('%s = "%s" is either a base game model or declared as borrowed')
                        :format(key, value))
            end
        end

        for model, owner in pairs(borrowed) do
            t.ok(type(owner) == 'string' and owner ~= '',
                ('borrowed model "%s" names the resource it came from'):format(model))
        end
    end

    -- -----------------------------------------------------------------------

    t.describe('every event that is sent is listened for')

    -- The check that would have caught deleting the hose sync handler. A block replacement
    -- spanned it, the server carried on broadcasting `mi_fire:client:hoseLine` to nobody, and
    -- the symptom was three unrelated-looking things -- no nozzle, no coupling, a rope that
    -- never appeared -- none of which pointed at a missing listener.
    --
    -- Nothing about that is visible in review. It is exactly the shape of thing a test should
    -- hold.
    local serverFiles = {
        'bridge/framework/init.lua',
        'bridge/dispatch/init.lua',
        'bridge/inventory/ox_inventory.lua',
        'bridge/medical/init.lua',
        'server/core/db.lua',
        'server/core/state.lua',
        'server/core/permissions.lua',
        'server/modules/apparatus/init.lua',
        'server/main.lua',
        'server/modules/fire/init.lua',
        'server/modules/fire/spread.lua',
        'server/modules/turnout/appearance.lua',
        'server/modules/turnout/init.lua',
        'server/modules/scba/pass.lua',
        'server/modules/exposure/init.lua',
        'server/modules/smoke/init.lua',
        'server/modules/scorch/init.lua',
        'server/modules/hose/init.lua',
        'server/modules/pump/init.lua',
        'server/modules/admin/init.lua',
        'server/api/exports.lua',
    }

    ---@param paths string[]
    ---@param pattern string
    ---@return table<string, string> name -> the file it was found in
    local function collect(paths, pattern)
        local found = {}

        for _, path in ipairs(paths) do
            local source = read(path)

            if source then
                for name in source:gmatch(pattern) do
                    found[name] = found[name] or path
                end
            end
        end

        return found
    end

    do
        local sent = collect(serverFiles, "TriggerClientEvent%s*%(%s*'([%w_:]+)'")
        local heard = collect(clientFiles, "RegisterNetEvent%s*%(%s*'([%w_:]+)'")

        for name, path in pairs(sent) do
            t.ok(heard[name] ~= nil,
                ('%s is sent from %s and something listens for it'):format(name, path))
        end
    end

    t.describe('and the other way round')

    do
        local sent = collect(clientFiles, "TriggerServerEvent%s*%(%s*'([%w_:]+)'")
        local heard = collect(serverFiles, "RegisterNetEvent%s*%(%s*'([%w_:]+)'")

        for name, path in pairs(sent) do
            t.ok(heard[name] ~= nil,
                ('%s is sent from %s and something listens for it'):format(name, path))
        end
    end

    t.describe('and every callback awaited is registered')

    do
        local awaited = collect(clientFiles, "lib%.callback%.await%s*%(%s*'([%w_:]+)'")
        local registered = collect(serverFiles, "lib%.callback%.register%s*%(%s*'([%w_:]+)'")

        for name, path in pairs(awaited) do
            t.ok(registered[name] ~= nil,
                ('%s is awaited from %s and something answers it'):format(name, path))
        end
    end

    -- -----------------------------------------------------------------------

    t.describe('custom assets are not gated on base game validity checks')

    -- Twice in two attempts, and both cost a round of testing.
    --
    -- `IsModelInCdimage` and `IsWeaponValid` answer about the game's own archetypes and weapon
    -- list. A streamed model or a weapon from a `weapons.meta` fails them while working
    -- perfectly -- so using one as a gate refuses to try, and then reports the asset as
    -- missing, which sends the search after the asset instead of after the check.
    --
    -- Ask them if the answer is interesting. Never let them decide whether to attempt.
    do
        local hose = read('client/modules/hose/init.lua')

        if hose then
            for _, predicate in ipairs({ 'IsWeaponValid', 'IsModelInCdimage' }) do
                for line in hose:gmatch('[^\n]+') do
                    if not line:match('^%s*%-%-') and line:find(predicate) then
                        t.ok(line:find('^%s*local ') ~= nil,
                            ('%s is recorded rather than used as a gate (%s)')
                                :format(predicate, line:gsub('^%s+', '')))
                    end
                end
            end
        end
    end

    -- -----------------------------------------------------------------------

    t.describe('every declared data file is also shipped')

    -- `data_file` says what a file *is*. `files` is what actually sends it to a client. Only
    -- declaring them meant every client asked for the weapon asset and never received it,
    -- which presents as an archetype that is genuinely absent -- and was diagnosed that way
    -- three times running, through the metas, the streaming and the natives, while the
    -- manifest was simply not shipping them.
    --
    -- Nothing about that is visible in either block on its own. It is only visible in the gap.
    do
        local manifest = read('fxmanifest.lua')

        if manifest then
            local shipped = {}

            local block = manifest:match('files%s*{(.-)}')

            -- Comment lines are dropped before anything is read out of the block. An
            -- apostrophe in prose -- "SmartHose's manifest" -- opens a string as far as a
            -- pattern is concerned and swallows the rest of the block, which made this test
            -- fail against a manifest that was correct.
            if block then
                local code = {}

                for line in block:gmatch('[^\n]+') do
                    if not line:match('^%s*%-%-') then code[#code + 1] = line end
                end

                block = table.concat(code, '\n')

                for path in block:gmatch("'([^']+)'") do
                    shipped[path] = true

                    -- A glob covers everything under it.
                    local prefix = path:match('^(.-)%*')
                    if prefix then shipped['glob:' .. prefix] = true end
                end
            end

            for path in manifest:gmatch("data_file%s+'[%w_]+'%s+'([^']+)'") do
                local covered = shipped[path] ~= nil

                if not covered then
                    for key in pairs(shipped) do
                        local prefix = key:match('^glob:(.+)$')
                        if prefix and path:sub(1, #prefix) == prefix then
                            covered = true
                            break
                        end
                    end
                end

                t.ok(covered,
                    ('%s is declared with data_file and shipped in files'):format(path))
            end
        end
    end
end
