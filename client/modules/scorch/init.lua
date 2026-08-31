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
    local handle = AddDecal(
        MIFireScorch.decal,
        mark.coords.x, mark.coords.y, mark.coords.z + 0.5,
        0.0, 0.0, -1.0,
        1.0, 0.0, 0.0,
        mark.size, mark.size,
        colour.r or 0.16, colour.g or 0.15, colour.b or 0.14, alpha,
        -1.0,          -- never times out on its own; the server decides when it goes
        false, false, false)

    if handle and handle ~= 0 then
        drawn[id] = handle
        return
    end

    if not warnedAboutDecal then
        warnedAboutDecal = true
        Util.warn('AddDecal returned 0 for type %s -- no burn marks will appear. '
            .. 'Run "/fire decals" to find a type that works on this build, then set '
            .. 'MIFireScorch.decal in config/scorch.lua.', tostring(MIFireScorch.decal))
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
RegisterNetEvent('mi_fire:client:decalTest', function()
    local ped = cache.ped
    local origin = GetEntityCoords(ped)
    local forward = GetEntityForwardVector(ped)

    local lines = { 'Decal candidates laid out ahead of you, left to right:' }

    for i = 1, #MIFireScorch.decalCandidates do
        local decal = MIFireScorch.decalCandidates[i]

        -- Two metres apart along your facing, so they do not overlap.
        local x = origin.x + forward.x * (i * 2.5)
        local y = origin.y + forward.y * (i * 2.5)

        local handle = AddDecal(decal, x, y, origin.z + 0.5,
            0.0, 0.0, -1.0, 1.0, 0.0, 0.0,
            1.8, 1.8,
            0.16, 0.15, 0.14, 0.9,
            120.0, false, false, false)

        lines[#lines + 1] = ('  %d. type %s -- %s'):format(
            i, tostring(decal),
            (handle and handle ~= 0) and 'placed' or 'REJECTED by the game')

        DrawMarker(2, x, y, origin.z + 1.2, 0, 0, 0, 0, 0, 0,
            0.3, 0.3, 0.3, 255, 190, 60, 180, false, true, 2, false)
    end

    lines[#lines + 1] = 'They last two minutes. Set the one that looks right as '
        .. 'MIFireScorch.decal in config/scorch.lua.'

    for i = 1, #lines do
        TriggerEvent('chat:addMessage', { args = { 'mi_fire', lines[i] } })
        print('[mi_fire] ' .. lines[i])
    end
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
