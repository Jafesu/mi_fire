--- Burn marks, server side.
---
--- The server owns which marks exist, for the same reason it owns which fires exist: two
--- firefighters standing in the same doorway have to see the same burn pattern, or the scene
--- stops being evidence of anything.
---
--- Clients draw them and ask to clean them. Nothing here trusts a client about where a mark
--- is, only about which one they are standing at.

MIFire = MIFire or {}

local ScorchServer = {}

local Util = MIFire.Util
local Scorch = MIFire.Scorch
local Permissions = MIFire.Permissions

--- Every live mark, keyed by id.
---@type table<string, table>
local marks = {}
local nextId = 0

---@return string
local function newId()
    nextId = nextId + 1
    return ('scorch_%d'):format(nextId)
end

--- Push the whole set to one client, or to everyone.
---@param target integer|nil
local function sync(target)
    local list = {}

    for id, mark in pairs(marks) do
        list[#list + 1] = {
            id = id,
            coords = mark.coords,
            size = mark.size,
            markedAt = mark.markedAt,
        }
    end

    TriggerClientEvent('mi_fire:client:scorchSync', target or -1, list)
end

--- Record that something burned here.
---
--- Called when a node dies rather than while it burns: a decal under an active fire is
--- invisible under the flames and would have to be resized every tick to follow it.
---@param coords table
---@param burnedSeconds number
---@param peakIntensity number
---@return string|nil id
function ScorchServer.mark(coords, burnedSeconds, peakIntensity)
    if not MIFireScorch.enabled then return nil end
    if type(coords) ~= 'table' then return nil end

    local size = Scorch.size(burnedSeconds or 0, peakIntensity or 0, MIFireScorch.size)

    -- Merge into a mark that already covers this ground. A fire that spread through six
    -- nodes in a room should leave a scorched room, not six overlapping circles fighting
    -- each other for the same square metre.
    for id, mark in pairs(marks) do
        local dx, dy, dz = coords.x - mark.coords.x, coords.y - mark.coords.y,
            coords.z - mark.coords.z

        if (dx * dx + dy * dy + dz * dz) <= (mark.size * 0.6) ^ 2 then
            if size > mark.size then
                mark.size = math.min(MIFireScorch.size.maximum, size)
                mark.markedAt = os.time()
                sync()
            end
            return id
        end
    end

    -- Bounded, so a server nobody ever cleans up on does not grow without limit. Oldest
    -- goes, since that is the one closest to ageing out anyway.
    local count = 0
    for _ in pairs(marks) do count = count + 1 end

    if count >= (MIFireScorch.maximumStored or 400) then
        local oldestId, oldestAt = nil, math.huge
        for id, mark in pairs(marks) do
            if mark.markedAt < oldestAt then oldestId, oldestAt = id, mark.markedAt end
        end
        if oldestId then marks[oldestId] = nil end
    end

    local id = newId()
    marks[id] = {
        coords = { x = coords.x, y = coords.y, z = coords.z },
        size = size,
        markedAt = os.time(),
    }

    sync()
    Util.debug('scorch', 'marked %s at %.1f, %.1f (%.1fm)', id, coords.x, coords.y, size)

    return id
end

--- Wash one away.
---@param id string
---@return boolean ok
---@return string|nil reason
function ScorchServer.clean(id)
    if not marks[id] then return false, 'that mark is already gone' end

    marks[id] = nil
    sync()
    Util.debug('scorch', 'cleaned %s', tostring(id))

    return true
end

---@param id string
---@return table|nil
function ScorchServer.get(id)
    return marks[id]
end

---@return table
function ScorchServer.all()
    return marks
end

--- Remove every mark. Used by `/fire stopall` and on teardown.
---@return integer removed
function ScorchServer.clear()
    local count = 0
    for _ in pairs(marks) do count = count + 1 end

    marks = {}
    sync()

    return count
end

-- ---------------------------------------------------------------------------
-- Ageing
-- ---------------------------------------------------------------------------

CreateThread(function()
    while not MIFire.ready do Wait(250) end

    while true do
        -- A minute is plenty: the shortest sensible lifetime is measured in tens of minutes,
        -- and marks fade visually on the client rather than waiting for this to notice.
        Wait(60000)

        if MIFireScorch.enabled and MIFireScorch.lifetimeMinutes > 0 then
            local now = os.time()
            local expired = nil

            for id, mark in pairs(marks) do
                if Scorch.expired(mark.markedAt, now, MIFireScorch) then
                    expired = expired or {}
                    expired[#expired + 1] = id
                end
            end

            if expired then
                for i = 1, #expired do marks[expired[i]] = nil end
                sync()
                Util.debug('scorch', '%d mark(s) aged out', #expired)
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Transports
-- ---------------------------------------------------------------------------

RegisterNetEvent('mi_fire:server:cleanScorch', function(id)
    local source = source
    if type(id) ~= 'string' then return end

    local mark = marks[id]
    if not mark then return end

    -- The client picks which mark; the server checks they are standing at it. That is the
    -- whole trust boundary here, and it is enough -- the worst a forged id achieves is
    -- cleaning a mark somebody else was going to clean.
    if not Permissions.isNear(source, mark.coords, (MIFireScorch.cleanup.radius or 2.5) + 3.0) then
        return
    end

    if MIFireScorch.cleanup.requiresFirefighter then
        local allowed = Permissions.requireFirefighter(source)
        if not allowed then return end
    end

    ScorchServer.clean(id)
end)

--- A client that has just joined, or just restarted the resource, has no marks at all.
RegisterNetEvent('mi_fire:server:requestScorch', function()
    sync(source)
end)

AddEventHandler('playerJoining', function()
    local source = source
    SetTimeout(5000, function() sync(source) end)
end)

exports('GetScorchMarks', function() return marks end)
exports('MarkScorch', function(coords, seconds, intensity)
    return ScorchServer.mark(coords, seconds, intensity)
end)
exports('ClearScorchMarks', function() return ScorchServer.clear() end)

MIFire.ScorchServer = ScorchServer

return ScorchServer
