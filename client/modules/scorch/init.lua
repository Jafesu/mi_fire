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

--- Two renderers, because the good one does not work everywhere.
---
--- `AddDecal` is the right mechanism: projected, conforms to whatever it lands on, and costs
--- nothing per frame. On the build this was developed against it accepts five type IDs,
--- returns real non-zero handles for every one, and **draws nothing** -- tested at four
--- metres across in flat white at full opacity with a marker overhead, indoors and out. The
--- native is not refusing; something upstream of this resource is eating the result.
---
--- So the default is a flat dark marker disc, which uses the same mechanism as every
--- checkpoint in the game and therefore cannot quietly fail. It costs a draw call per visible
--- mark and does not conform to a slope, which is why it is not the first choice -- only the
--- one that works. `/fire decals sweep` tells a server owner in a minute which they have.

---@param id string
---@param mark table
local function drawDecal(id, mark)
    if drawn[id] then return end

    local fade = Scorch.fade(mark.markedAt, GetCloudTimeAsInt(), MIFireScorch)
    local colour = MIFireScorch.colour
    local alpha = (colour.alpha or 0.85) * (1.0 - fade * 0.6)

    local z = mark.coords.z
    local found, groundZ = GetGroundZFor_3dCoord(
        mark.coords.x, mark.coords.y, mark.coords.z + 2.0, false)
    if found then z = groundZ end

    local timeout = math.max(600000.0, (MIFireScorch.lifetimeMinutes or 180) * 60000.0)
    local scale = MIFireScorch.colourScale or 1.0

    local handle = AddDecal(
        MIFireScorch.decal,
        mark.coords.x, mark.coords.y, z + 0.35,
        0.0, 0.0, -1.0,
        0.0, 1.0, 0.0,
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
        Util.warn('AddDecal returned 0 for type %s. Set MIFireScorch.renderer = "marker" '
            .. 'in config/scorch.lua, or run "/fire decals sweep" to find a type this build '
            .. 'accepts.', tostring(MIFireScorch.decal))
    end
end

--- The marker disc, drawn per frame.
---@param mark table
local function drawMarker(mark)
    local colour = MIFireScorch.markerColour
    local fade = Scorch.fade(mark.markedAt, GetCloudTimeAsInt(), MIFireScorch)

    -- Ages toward transparent rather than blinking out, so a scene that has not been cleaned
    -- still reads as older than one that just burned.
    local alpha = math.floor((colour.alpha or 115) * (1.0 - fade * 0.65))
    if alpha <= 2 then return end

    local z = mark.coords.z
    local found, groundZ = GetGroundZFor_3dCoord(
        mark.coords.x, mark.coords.y, mark.coords.z + 2.0, false)
    if found then z = groundZ end

    -- Type 1 is a vertical cylinder; flattened it is a disc lying on the ground. The last
    -- argument draws it onto whatever is underneath rather than leaving it hanging in the
    -- air over a kerb.
    DrawMarker(1,
        mark.coords.x, mark.coords.y, z + (MIFireScorch.markerLift or 0.03),
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        mark.size, mark.size, MIFireScorch.markerHeight or 0.04,
        colour.r or 20, colour.g or 18, colour.b or 16, alpha,
        false, false, 2, false, nil, nil, true)
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

--- Keep the nearest marks drawn and the rest not.
---
--- Split in two: a slow thread decides *which* marks are near enough to matter, and a fast
--- one draws them. Sorting every mark by distance at frame rate is how a fireground becomes a
--- frame rate problem, and it does not need doing more than twice a second.
local visible = {}

CreateThread(function()
    while not MIFire.ready do Wait(250) end

    -- A client that just connected or just restarted the resource has nothing.
    TriggerServerEvent('mi_fire:server:requestScorch')

    local maximum = MIFireScorch.maximumRendered or 60
    local reach = MIFireScorch.drawDistance or 90.0

    while true do
        Wait(500)

        local nearby = {}

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
                    nearby[#nearby + 1] = entry.mark
                    addCleanupTarget(entry.id, entry.mark)

                    if MIFireScorch.renderer == 'decal' then
                        drawDecal(entry.id, entry.mark)
                    end
                elseif drawn[entry.id] then
                    undraw(entry.id)
                end
            end
        end

        visible = nearby
    end
end)

--- The per-frame half. Only runs at all when the marker renderer is selected and there is
--- something in range, so a decal server and an empty street both cost nothing.
CreateThread(function()
    while true do
        if MIFireScorch.renderer ~= 'marker' or #visible == 0 then
            Wait(500)
        else
            Wait(0)
            for i = 1, #visible do
                drawMarker(visible[i])
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
--- Find a decal type that actually draws on this build.
---
--- **Round two, after round one found five accepted types and showed none of them.**
--- Two faults in that test, both mine:
---
---   The second row was offset in world Y with **no marker over it**, so the row drawn in
---   white -- the one most likely to be visible -- was 2.6 metres from anything the player
---   was told to look at.
---
---   The first row was drawn at 0.2 grey, which on a dark floor is very nearly the floor.
---   A test for "does this render at all" has no business being subtle.
---
--- So this draws only the types the game already accepted, at four metres across, in flat
--- white at full opacity, with a marker directly over every one. If a decal renders on this
--- build at all, it is impossible to miss. If they are still invisible, decals are the wrong
--- mechanism here and the fallback is a different one rather than another parameter.
---
--- Run it **outdoors on tarmac**. Interior floors are a common case for decals not taking,
--- and a station bay is exactly the surface most likely to refuse them.
---@param types table Type IDs to draw.
local function drawCandidates(types)
    local ped = cache.ped
    local origin = GetEntityCoords(ped)
    local forward = GetEntityForwardVector(ped)
    local right = vec3(forward.y, -forward.x, 0.0)

    local placed = {}
    local lines = {
        ('Drawing %d type(s) at 4m across, flat white, full opacity.'):format(#types),
        'Every one has a marker over it. Look straight down at each in turn.',
    }

    for i = 1, #types do
        local decal = types[i]

        -- Six metres apart, along your right, starting well clear of you.
        local offset = (i - 1) * 6.0 - ((#types - 1) * 3.0)
        local x = origin.x + right.x * offset + forward.x * 6.0
        local y = origin.y + right.y * offset + forward.y * 6.0

        local z = origin.z
        local found, groundZ = GetGroundZFor_3dCoord(x, y, origin.z + 3.0, false)
        if found then z = groundZ end

        local handle = AddDecal(decal, x, y, z + 0.3,
            0.0, 0.0, -1.0, 0.0, 1.0, 0.0,
            4.0, 4.0,
            1.0, 1.0, 1.0, 1.0,
            120000.0, false, false, false)

        placed[#placed + 1] = { decal = decal, x = x, y = y, z = z, handle = handle or 0 }
        lines[#lines + 1] = ('  %d. type %s -- handle %s'):format(
            i, tostring(decal), tostring(handle))
    end

    lines[#lines + 1] = 'If every marker has bare ground under it, decals do not render here '
        .. 'and no type ID will fix that -- say so and the mechanism changes.'

    for i = 1, #lines do
        TriggerEvent('chat:addMessage', { args = { 'mi_fire', lines[i] } })
        print('[mi_fire] ' .. lines[i])
    end

    -- A marker over every single one this time, numbered by height so they are tellable
    -- apart from a distance.
    CreateThread(function()
        local until_ = GetGameTimer() + 120000
        while GetGameTimer() < until_ do
            Wait(0)
            for i = 1, #placed do
                local p = placed[i]
                DrawMarker(2, p.x, p.y, p.z + 1.6 + i * 0.35, 0, 0, 0, 0, 0, 0,
                    0.4, 0.4, 0.4, 255, 190, 60, 160, false, true, 2, false)
            end
        end
    end)
end

--- Sweep every plausible type ID and report which the game accepts.
---@return table accepted
local function sweepTypes()
    local accepted = {}

    -- Placed far below the map and immediately removed: this only asks whether the native
    -- accepts the type, and drawing 77 decals around the player to find out is the thing
    -- that made round one unreadable.
    for _, id in ipairs({ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 }) do
        local handle = AddDecal(id, 0.0, 0.0, -200.0,
            0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0,
            100.0, false, false, false)
        if handle and handle ~= 0 then
            accepted[#accepted + 1] = id
            RemoveDecal(handle)
        end
    end

    for id = 1000, 1035 do
        local handle = AddDecal(id, 0.0, 0.0, -200.0,
            0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0,
            100.0, false, false, false)
        if handle and handle ~= 0 then
            accepted[#accepted + 1] = id
            RemoveDecal(handle)
        end
    end

    return accepted
end

RegisterNetEvent('mi_fire:client:decalTest', function(sweep)
    if sweep then
        local accepted = sweepTypes()

        TriggerEvent('chat:addMessage', { args = { 'mi_fire',
            ('accepted types: %s'):format(table.concat(accepted, ', ')) } })
        print('[mi_fire] accepted types: ' .. table.concat(accepted, ', '))

        drawCandidates(accepted)
        return
    end

    drawCandidates(MIFireScorch.decalCandidates)
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
