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
end
