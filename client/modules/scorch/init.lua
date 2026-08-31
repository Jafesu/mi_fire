--- Burn marks, client side.
---
--- Draws what the server says burned, and offers to wash it away.
---
--- The failure mode to know about: `AddDecal` returns 0 for a decal type that does not exist
--- and prints nothing at all. That is the same silent failure that made an invented particle
--- name look like broken rendering for an entire session, and unlike the particle names there
--- was nothing on this machine to verify a decal ID against. So the first failure is reported
--- loudly, once, with the fix named -- and `/fire decals` exists to find the right value by
--- looking at it.

MIFire = MIFire or {}

local ScorchClient = {}

local Util = MIFire.Util
local Scorch = MIFire.Scorch
local Target = MIFire.Target

--- What the server says exists, keyed by id.
---@type table<string, table>
local marks = {}

--- Decal handles we have placed, keyed by mark id, so they can be taken back down.
---@type table<string, integer>
local drawn = {}

--- ox_target zones, keyed by mark id.
---@type table<string, integer>
local zones = {}

local warnedAboutDecal = false

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

---@param id string
---@param mark table
local function draw(id, mark)
    if drawn[id] then return end

    local fade = Scorch.fade(mark.markedAt, GetCloudTimeAsInt(), MIFireScorch)
    local colour = MIFireScorch.colour
    local alpha = (colour.alpha or 0.85) * (1.0 - fade * 0.6)

    -- Projected straight down onto whatever is under the mark, so it takes the shape of the
    -- ground rather than floating at the height the node happened to die at.
    -- Project onto whatever is actually under the mark. A node can die at head height on a
    -- staircase, and a decal placed at that z projects onto nothing.
    local z = mark.coords.z
    local found, groundZ = GetGroundZFor_3dCoord(
        mark.coords.x, mark.coords.y, mark.coords.z + 2.0, false)
    if found then z = groundZ end

    -- Timeout was -1.0 here, meaning "permanent". That is not obviously accepted -- the
    -- parameter is milliseconds and a negative one may simply be rejected, which returns 0
    -- exactly like a bad type ID does. A very large positive value asks for the same thing
    -- without relying on a convention nothing here has confirmed. The server removes marks
    -- when they are cleaned or age out, so this only has to outlast the lifetime.
    local timeout = math.max(600000.0, (MIFireScorch.lifetimeMinutes or 180) * 60000.0)

    -- Colour convention is unconfirmed on this build: the parameters are named as
    -- coefficients but a good deal of working code passes 0-255. `/fire decals` reports
    -- which this build accepts; `colourScale` applies the answer.
    local scale = MIFireScorch.colourScale or 1.0

    local handle = AddDecal(
        MIFireScorch.decal,
        mark.coords.x, mark.coords.y, z + 0.35,
        0.0, 0.0, -1.0,
        1.0, 0.0, 0.0,
        mark.size, mark.size,
        (colour.r or 0.16) * scale, (colour.g or 0.15) * scale, (colour.b or 0.14) * scale,
        alpha * scale,
        timeout,
        false, false, false)

    if handle and handle ~= 0 then
        drawn[id] = handle
        return
    end

    if not warnedAboutDecal then
        warnedAboutDecal = true
        Util.warn('AddDecal returned 0 for type %s -- no burn marks will appear. '
            .. 'Run "/fire decals sweep" to find a type this build accepts, then set '
            .. 'MIFireScorch.decal in config/scorch.lua. If the sweep accepts nothing at '
            .. 'all, the native is refusing outright rather than rejecting the type, and '
            .. 'MIFireScorch.enabled should go false until that is understood.',
            tostring(MIFireScorch.decal))
    end
end

---@param id string
local function undraw(id)
    if drawn[id] then
        RemoveDecal(drawn[id])
        drawn[id] = nil
    end

    if zones[id] then
        Target.removeZone(zones[id])
        zones[id] = nil
    end
end

-- ---------------------------------------------------------------------------
-- Cleaning
-- ---------------------------------------------------------------------------

---@param id string
---@param mark table
local function addCleanupTarget(id, mark)
    if zones[id] or not MIFireScorch.cleanup.enabled then return end

    zones[id] = Target.addSphere(
        vec3(mark.coords.x, mark.coords.y, mark.coords.z),
        MIFireScorch.cleanup.radius or 2.5,
        {
            {
                name = 'mi_fire:cleanScorch:' .. id,
                icon = 'broom',
                label = MIFireScorch.cleanup.label or 'Wash down the scene',
                requiresFirefighter = MIFireScorch.cleanup.requiresFirefighter,
                onSelect = function()
                    local seconds = Scorch.cleanSeconds(
                        mark.size, MIFireScorch.cleanup, MIFireScorch.size)

                    local finished = lib.progressBar({
                        duration = math.floor(seconds * 1000),
                        label = MIFireScorch.cleanup.label or 'Washing down',
                        canCancel = true,
                        disable = { move = true, car = true, combat = true },
                        anim = {
                            dict = 'amb@world_human_janitor@male@idle_a',
                            clip = 'idle_a',
                            flag = 49,
                        },
                    })

                    if finished then
                        TriggerServerEvent('mi_fire:server:cleanScorch', id)
                    end
                end,
            },
        })
end

-- ---------------------------------------------------------------------------
-- Sync
-- ---------------------------------------------------------------------------

RegisterNetEvent('mi_fire:client:scorchSync', function(list)
    if type(list) ~= 'table' then return end

    local seen = {}

    for i = 1, #list do
        local mark = list[i]
        seen[mark.id] = true
        marks[mark.id] = mark
    end

    -- Anything the server no longer has has been cleaned or aged out.
    for id in pairs(marks) do
        if not seen[id] then
            undraw(id)
            marks[id] = nil
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Render loop
-- ---------------------------------------------------------------------------

--- Draw the nearest marks and take down the rest.
---
--- Decals are cheap but not free, and a long shift on a busy server can leave a lot of them,
--- so this is a nearest-N with a distance cut rather than "draw everything the server knows".
CreateThread(function()
    while not MIFire.ready do Wait(250) end

    -- A client that just connected or just restarted the resource has nothing.
    TriggerServerEvent('mi_fire:server:requestScorch')

    local maximum = MIFireScorch.maximumRendered or 60
    local reach = MIFireScorch.drawDistance or 90.0

    while true do
        Wait(2000)

        if MIFireScorch.enabled and next(marks) ~= nil then
            local here = GetEntityCoords(cache.ped)
            local candidates = {}

            for id, mark in pairs(marks) do
                local dx, dy, dz =
                    here.x - mark.coords.x, here.y - mark.coords.y, here.z - mark.coords.z
                local distSq = dx * dx + dy * dy + dz * dz

                if distSq <= reach * reach then
                    candidates[#candidates + 1] = { id = id, mark = mark, distSq = distSq }
                elseif drawn[id] then
                    undraw(id)
                end
            end

            table.sort(candidates, function(a, b) return a.distSq < b.distSq end)

            for i = 1, #candidates do
                local entry = candidates[i]
                if i <= maximum then
                    draw(entry.id, entry.mark)
                    addCleanupTarget(entry.id, entry.mark)
                elseif drawn[entry.id] then
                    undraw(entry.id)
                end
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Finding a decal type that works
-- ---------------------------------------------------------------------------

--- Lay every candidate out in a row so the right one can be chosen by looking at it.
---
--- This exists because there was nothing on this machine to verify a decal ID against, and
--- guessing one that silently draws nothing is a failure mode this project has already paid
--- for once. Same spirit as the offset finder: author the value by seeing it, not by trusting
--- a comment.
--- Find a decal type -- and a parameter convention -- that actually draws on this build.
---
--- Rewritten after the first version produced nothing visible, which told us only that
--- something was wrong and not which thing. There are three independent suspects and
--- guessing between them is how a session gets burned:
---
---   1. the **type ID** does not exist on this build
---   2. `rCoef/gCoef/bCoef` and `opacity` are **0-255**, not the 0-1 they are named for --
---      in which case an opacity of 0.85 is 0.3% and invisible rather than absent
---   3. a `timeout` of -1 is rejected rather than meaning "permanent"
---
--- So this sweeps rather than tests a hypothesis. Every accepted type is reported with its
--- handle, drawn under a numbered marker you can walk to, and laid out in two rows: one in
--- each colour convention. Whichever row you can see settles suspect 2, and which markers
--- have something under them settles suspect 1.
---@param sweep boolean Try a wide range of type IDs rather than the configured candidates.
local function decalTest(sweep)
    local ped = cache.ped
    local origin = GetEntityCoords(ped)
    local forward = GetEntityForwardVector(ped)
    local right = vec3(forward.y, -forward.x, 0.0)

    local types = MIFireScorch.decalCandidates

    if sweep then
        -- Let the game enumerate rather than trusting a list. Cheap: a rejected type costs
        -- one native call that returns 0.
        types = {}
        for id = 0, 40 do types[#types + 1] = id end
        for id = 1000, 1035 do types[#types + 1] = id end
    end

    local lines = {
        ('Testing %d decal type(s). Two rows: near row uses 0-1 colour values, far row uses '
            .. '0-255.'):format(#types),
        'Walk the rows. Whichever you can see tells us which convention this build wants.',
    }

    local accepted, placed = {}, 0

    for i = 1, #types do
        local decal = types[i]

        -- Spread along your right so the rows do not overlap, wrapping every 12.
        local column = (i - 1) % 12
        local row = math.floor((i - 1) / 12)

        local x = origin.x + right.x * (column * 2.2 - 12.0) + forward.x * (4.0 + row * 3.0)
        local y = origin.y + right.y * (column * 2.2 - 12.0) + forward.y * (4.0 + row * 3.0)

        local z = origin.z
        local found, groundZ = GetGroundZFor_3dCoord(x, y, origin.z + 2.0, false)
        if found then z = groundZ end

        -- Convention A: coefficients, as the parameter names claim.
        local a = AddDecal(decal, x, y, z + 0.35,
            0.0, 0.0, -1.0, 1.0, 0.0, 0.0,
            1.6, 1.6,
            0.2, 0.2, 0.2, 1.0,
            600000.0, false, false, false)

        -- Convention B: bytes, as a good deal of working code in the wild passes.
        local b = AddDecal(decal, x, y + 2.6, z + 0.35,
            0.0, 0.0, -1.0, 1.0, 0.0, 0.0,
            1.6, 1.6,
            255.0, 255.0, 255.0, 255.0,
            600000.0, false, false, false)

        if (a and a ~= 0) or (b and b ~= 0) then
            placed = placed + 1
            accepted[#accepted + 1] = decal
            lines[#lines + 1] = ('  type %-5s  coef=%s  bytes=%s'):format(
                tostring(decal),
                (a and a ~= 0) and 'ok' or '--',
                (b and b ~= 0) and 'ok' or '--')
        end
    end

    if placed == 0 then
        lines[#lines + 1] = 'NOTHING was accepted. Every AddDecal call returned 0, so this is '
            .. 'not a type-ID problem -- the native is refusing outright on this build.'
    else
        lines[#lines + 1] = ('%d of %d type(s) accepted. Accepted: %s'):format(
            placed, #types, table.concat(accepted, ', '))
        lines[#lines + 1] = 'Set the one that looks like scorching as MIFireScorch.decal.'
    end

    for i = 1, #lines do
        TriggerEvent('chat:addMessage', { args = { 'mi_fire', lines[i] } })
        print('[mi_fire] ' .. lines[i])
    end

    -- Markers over every slot for two minutes, so an invisible decal is distinguishable
    -- from one placed somewhere you are not looking.
    CreateThread(function()
        local until_ = GetGameTimer() + 120000
        while GetGameTimer() < until_ do
            Wait(0)
            for i = 1, #types do
                local column = (i - 1) % 12
                local row = math.floor((i - 1) / 12)
                local x = origin.x + right.x * (column * 2.2 - 12.0) + forward.x * (4.0 + row * 3.0)
                local y = origin.y + right.y * (column * 2.2 - 12.0) + forward.y * (4.0 + row * 3.0)

                DrawMarker(2, x, y, origin.z + 1.4, 0, 0, 0, 0, 0, 0,
                    0.25, 0.25, 0.25, 255, 190, 60, 140, false, true, 2, false)
            end
        end
    end)
end

RegisterNetEvent('mi_fire:client:decalTest', function(sweep)
    decalTest(sweep == true)
end)

-- ---------------------------------------------------------------------------
-- Teardown
-- ---------------------------------------------------------------------------

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    for id in pairs(drawn) do
        RemoveDecal(drawn[id])
    end

    drawn = {}
end)

exports('GetScorchMarks', function() return marks end)

MIFire.ScorchClient = ScorchClient

return ScorchClient
