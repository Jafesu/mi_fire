--- Hose lines, server side.
---
--- Owns every line that exists, where both its ends are, who is on it, and whether it is
--- charged. Clients render the rope and ask for things; they never assert that a line exists,
--- because two firefighters arguing about whether the line is charged is not a disagreement a
--- fireground can have.
---
--- The state a line moves through, and why each step is separate:
---
---   `stretching`  Pulled off the bed and being walked out. Dry, light, no water.
---   `connected`   Coupled to a discharge at one end. Still dry.
---   `charged`     The pump operator has given it water. Heavy, and it works.
---
--- Splitting connect from charge is the whole point. A crew stretches dry because charged hose
--- is three times the weight, gets into position, and *then* calls for water -- and a pump
--- operator who charges a line still being walked out has made a real mistake that a real
--- crew would shout about.

MIFire = MIFire or {}

local HoseServer = {}

local Util = MIFire.Util
local State = MIFire.State
local Hose = MIFire.Hose
local Permissions = MIFire.Permissions

--- Every line, keyed by id.
---@type table<string, table>
local lines = {}
local nextId = 0

--- Which line each player is on, so a disconnect can be cleaned up without searching.
---@type table<integer, string>
local playerLine = {}

---@return string
local function newId()
    nextId = nextId + 1
    return ('line_%d'):format(nextId)
end

--- The public shape of a line. Deliberately not the internal table: clients get what they
--- need to draw and decide, and nothing else.
---@param line table
---@return table
local function publicOf(line)
    return {
        id = line.id,
        diameter = line.diameter,
        sections = line.sections,
        state = line.state,
        nozzle = line.nozzle,
        pattern = line.pattern,
        gpm = line.gpm,
        sourceNet = line.sourceNet,
        sourcePort = line.sourcePort,
        nozzleHolder = line.nozzleHolder,

        -- A **list** of server ids, not the set the server keeps. `{ [3] = true }` is a table
        -- with a sparse integer key, and how that survives the trip to a client depends on
        -- which key it happens to be -- a single entry keyed 1 can arrive as an array. A list
        -- of numbers has one meaning.
        crew = (function()
            local ids = {}
            for id in pairs(line.crew or {}) do ids[#ids + 1] = id end
            table.sort(ids)
            return ids
        end)(),

        crewCount = (function()
            local count = 0
            for _ in pairs(line.crew or {}) do count = count + 1 end
            return count
        end)(),

        crewRequired = line.crewRequired,
        anchors = line.anchors,
    }
end

--- Tell everyone on a line something.
---@param line table
---@param message string
---@param kind string|nil
local function notifyLine(line, message, kind)
    for source in pairs(line.crew or {}) do
        TriggerClientEvent('mi_fire:client:notify', source, message, kind or 'inform')
    end
end

---@param line table
---@param target integer|nil
local function sync(line, target)
    TriggerClientEvent('mi_fire:client:hoseLine', target or -1, line.id, publicOf(line))
end

---@param id string
local function drop(id)
    local line = lines[id]
    if not line then return end

    for source in pairs(line.crew or {}) do playerLine[source] = nil end
    if line.nozzleHolder then playerLine[line.nozzleHolder] = nil end

    lines[id] = nil
    TriggerClientEvent('mi_fire:client:hoseLine', -1, id, nil)
end

-- ---------------------------------------------------------------------------
-- Pulling a line
-- ---------------------------------------------------------------------------

--- Pull a line off an apparatus.
---
--- A preconnected port comes with its hose already on it -- that is what a crosslay is, and
--- why it is the first line off the truck. A bare discharge gives you a coupling and nothing
--- else until someone brings hose to it.
---@param source integer
---@param entity integer The apparatus.
---@param portId string
---@return boolean ok
---@return string|nil reason
---@return string|nil lineId
function HoseServer.pull(source, entity, portId)
    if playerLine[source] then
        return false, 'you already have a line'
    end

    local profile = MIFire.ApparatusServer.profile(entity)
    if not profile then return false, 'that is not fire apparatus' end

    local port = MIFire.Apparatus.port(profile, portId)
    if not port then return false, 'no such connection on this rig' end

    if port.type ~= 'discharge' then
        return false, 'you pull a line from a discharge, not from that'
    end

    local diameter = tonumber(port.size) or 1.75
    local size = MIFireHose.sizes[diameter]

    if not size then
        return false, ('this rig declares a %s inch outlet and there is no such hose')
            :format(tostring(diameter))
    end

    local netId = NetworkGetNetworkIdFromEntity(entity)

    -- Preconnected means the hose is already coupled to the outlet. Anything else is a bare
    -- port, and connecting to it is a separate act.
    local preconnected = port.preconnected
    local sections = preconnected
        and math.max(1, math.floor((tonumber(preconnected.feet) or 200) / (size.sectionFeet or 50)))
        or 1

    local id = newId()

    lines[id] = {
        id = id,
        diameter = diameter,
        sections = sections,
        state = preconnected and 'connected' or 'stretching',
        sourceNet = preconnected and netId or nil,
        sourcePort = preconnected and portId or nil,
        nozzle = size.nozzles and size.nozzles[1] or nil,
        pattern = nil,
        gpm = 0.0,
        nozzleHolder = source,
        crew = { [source] = true },
        crewRequired = Hose.crewRequired(size),
        anchors = {},
        reel = preconnected and preconnected.reel or false,
    }

    playerLine[source] = id
    sync(lines[id])

    Util.debug('hose', '%s pulled %s (%s, %d section(s), %s)',
        tostring(source), id, tostring(diameter), sections, lines[id].state)

    return true, nil, id
end

-- ---------------------------------------------------------------------------
-- Connecting
-- ---------------------------------------------------------------------------

--- Couple the loose end to a discharge.
---@param source integer
---@param entity integer
---@param portId string
---@return boolean ok
---@return string|nil reason
function HoseServer.connect(source, entity, portId)
    local id = playerLine[source]
    local line = id and lines[id]
    if not line then return false, 'you are not carrying a line' end

    if line.sourceNet then return false, 'that line is already connected' end

    local profile = MIFire.ApparatusServer.profile(entity)
    if not profile then return false, 'that is not fire apparatus' end

    local port = MIFire.Apparatus.port(profile, portId)
    if not port or port.type ~= 'discharge' then
        return false, 'that is not a discharge'
    end

    -- A 2.5 inch line on a 1.75 inch outlet is a reducer, not a refusal -- but a line already
    -- flaked for one size should not silently become another.
    local portSize = tonumber(port.size)
    if portSize and portSize ~= line.diameter then
        return false, ('that outlet is %s inch and your line is %s')
            :format(tostring(portSize), tostring(line.diameter))
    end

    line.sourceNet = NetworkGetNetworkIdFromEntity(entity)
    line.sourcePort = portId
    line.state = 'connected'

    sync(line)
    Util.debug('hose', '%s connected %s to %s', tostring(source), id, portId)

    return true
end

-- ---------------------------------------------------------------------------
-- Crew
-- ---------------------------------------------------------------------------

--- Take a backup position on someone else's line.
---
--- This is what makes a 2.5 inch a crew job rather than a bigger number. The person on the
--- nozzle cannot work it alone, and the people behind them are doing something real.
---@param source integer
---@param lineId string
---@return boolean ok
---@return string|nil reason
function HoseServer.joinCrew(source, lineId)
    local line = lines[lineId]
    if not line then return false, 'that line is gone' end

    if playerLine[source] then return false, 'you are already on a line' end
    if line.crew[source] then return false, 'you are already on that line' end

    local crewCount = 0
    for _ in pairs(line.crew) do crewCount = crewCount + 1 end

    -- No hard cap at the requirement. More hands than needed is not a problem worth
    -- preventing, and a fourth person on a 2.5 inch is a real thing that happens.
    if crewCount >= line.crewRequired + 2 then
        return false, 'there are enough people on that line'
    end

    line.crew[source] = true
    playerLine[source] = lineId

    sync(line)
    return true
end

---@param source integer
---@return boolean
function HoseServer.leaveCrew(source)
    local id = playerLine[source]
    local line = id and lines[id]
    if not line then return false end

    line.crew[source] = nil
    playerLine[source] = nil

    -- The nozzle leaving does not delete the line. Someone else can pick it up, and a line
    -- lying charged on the ground is a real and instructive hazard.
    if line.nozzleHolder == source then
        line.nozzleHolder = nil
    end

    sync(line)
    return true
end

---@param source integer
---@param lineId string
---@return boolean ok
---@return string|nil reason
function HoseServer.takeNozzle(source, lineId)
    local line = lines[lineId]
    if not line then return false, 'that line is gone' end
    if line.nozzleHolder then return false, 'someone already has the nozzle' end

    if not line.crew[source] then
        if playerLine[source] then return false, 'you are already on a line' end
        line.crew[source] = true
        playerLine[source] = lineId
    end

    line.nozzleHolder = source
    sync(line)

    return true
end

--- How many are on a line.
---@param line table
---@return integer
local function crewCount(line)
    local count = 0
    for _ in pairs(line.crew or {}) do count = count + 1 end
    return count
end

-- ---------------------------------------------------------------------------
-- Water
-- ---------------------------------------------------------------------------

--- Charge a line from its apparatus.
---
--- Separate from connecting on purpose. A crew stretches dry because charged hose is three
--- times the weight, gets into position, and then calls for water -- and a pump operator who
--- charges a line still being walked out has made a mistake a real crew would shout about.
---@param lineId string
---@param charged boolean
---@return boolean ok
---@return string|nil reason
function HoseServer.charge(lineId, charged)
    local line = lines[lineId]
    if not line then return false, 'that line is gone' end

    if charged then
        if not line.sourceNet then return false, 'that line is not connected to anything' end

        local entity = NetworkGetEntityFromNetworkId(line.sourceNet)
        local tank = entity and MIFire.ApparatusServer.tank(entity)

        if not tank then return false, 'the rig it is connected to is gone' end
        if not tank.pumpEngaged then return false, 'the pump is not engaged' end

        line.state = 'charged'
    else
        line.state = line.sourceNet and 'connected' or 'stretching'
        line.gpm = 0.0
    end

    sync(line)
    Util.debug('hose', '%s %s', lineId, charged and 'charged' or 'shut down')

    return true
end

--- Open or close the nozzle.
---@param source integer
---@param gpm number Requested flow.
---@return boolean ok
---@return string|nil reason
function HoseServer.setFlow(source, gpm)
    local id = playerLine[source]
    local line = id and lines[id]
    if not line then return false, 'you are not on a line' end
    if line.nozzleHolder ~= source then return false, 'you are not on the nozzle' end
    if line.state ~= 'charged' then return false, 'that line has no water in it' end

    local size = MIFireHose.sizes[line.diameter]
    local ceiling = Hose.flowCeiling(size, crewCount(line), MIFireHose.underCrewed)

    -- Asking for more than the crew can hold is not refused -- it is capped, and the reason
    -- is said out loud. Being told "you cannot" teaches nothing; being told "you and one other
    -- cannot hold this open past 179 gpm" teaches the whole system.
    line.gpm = math.max(0.0, math.min(tonumber(gpm) or 0.0, ceiling))

    sync(line)
    return true, (line.gpm < (tonumber(gpm) or 0.0))
        and ('%d on this line can hold %.0f gpm'):format(crewCount(line), ceiling)
        or nil
end

-- ---------------------------------------------------------------------------
-- Cleanup
-- ---------------------------------------------------------------------------

--- Put a line away.
---@param source integer
---@param lineId string
---@return boolean ok
---@return string|nil reason
function HoseServer.stow(source, lineId, force)
    local line = lines[lineId]
    if not line then return false, 'that line is gone' end

    -- An admin clearing up a line that has gone wrong is not a crew packing one away, and
    -- refusing them because it is charged would leave the stuck state stuck.
    if line.state == 'charged' and not force then
        return false, 'shut the line down before you pack it'
    end

    drop(lineId)
    return true
end

---@param source integer
---@return table|nil
function HoseServer.lineFor(source)
    local id = playerLine[source]
    return id and lines[id] or nil
end

---@return table
function HoseServer.all()
    return lines
end

-- ---------------------------------------------------------------------------
-- Transports
-- ---------------------------------------------------------------------------

RegisterNetEvent('mi_fire:server:pullHose', function(netId, portId)
    local source = source
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 then return end

    local ok, why = HoseServer.pull(source, entity, portId)
    if not ok and why then
        TriggerClientEvent('mi_fire:client:notify', source, why, 'error')
    end
end)

RegisterNetEvent('mi_fire:server:connectHose', function(netId, portId)
    local source = source
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 then return end

    local ok, why = HoseServer.connect(source, entity, portId)
    TriggerClientEvent('mi_fire:client:notify', source,
        ok and 'Line connected' or (why or 'could not connect'), ok and 'success' or 'error')
end)

RegisterNetEvent('mi_fire:server:joinHoseCrew', function(lineId)
    local source = source
    if type(lineId) ~= 'string' then return end

    local ok, why = HoseServer.joinCrew(source, lineId)
    if not ok and why then
        TriggerClientEvent('mi_fire:client:notify', source, why, 'error')
    end
end)

RegisterNetEvent('mi_fire:server:takeNozzle', function(lineId)
    local source = source
    if type(lineId) ~= 'string' then return end

    local ok, why = HoseServer.takeNozzle(source, lineId)
    if not ok and why then
        TriggerClientEvent('mi_fire:client:notify', source, why, 'error')
    end
end)

RegisterNetEvent('mi_fire:server:leaveHose', function()
    HoseServer.leaveCrew(source)
end)

RegisterNetEvent('mi_fire:server:chargeHose', function(lineId, charged)
    local source = source
    if type(lineId) ~= 'string' then return end

    local ok, why = HoseServer.charge(lineId, charged == true)
    TriggerClientEvent('mi_fire:client:notify', source,
        ok and (charged and 'Line charged' or 'Line shut down') or (why or 'no'),
        ok and 'success' or 'error')
end)

RegisterNetEvent('mi_fire:server:setHoseFlow', function(gpm)
    local source = source
    local ok, note = HoseServer.setFlow(source, tonumber(gpm) or 0.0)

    if ok and note then
        TriggerClientEvent('mi_fire:client:notify', source, note, 'inform')
    elseif not ok and note then
        TriggerClientEvent('mi_fire:client:notify', source, note, 'error')
    end
end)

RegisterNetEvent('mi_fire:server:stowHose', function(lineId)
    local source = source
    if type(lineId) ~= 'string' then return end

    local ok, why = HoseServer.stow(source, lineId)
    if not ok and why then
        TriggerClientEvent('mi_fire:client:notify', source, why, 'error')
    end
end)

--- Water on the fire.
---
--- The client says where it is aiming and the server decides what that does, because
--- suppression is fire state and fire state is the server's. The worst a forged aim achieves
--- is putting water somewhere the player is not looking.
---
--- It also spends the tank, which is the thing that makes a supply line matter: an engine with
--- 750 gallons flowing 150 gpm has five minutes, and that clock is the whole reason anyone
--- lays a hydrant line rather than parking and fighting the fire off the tank.
RegisterNetEvent('mi_fire:server:hoseWater', function(coords, gpm, seconds)
    local source = source
    if type(coords) ~= 'table' then return end

    local line = HoseServer.lineFor(source)
    if not line or line.state ~= 'charged' then return end
    if line.nozzleHolder ~= source then return end

    gpm = math.max(0.0, math.min(tonumber(gpm) or 0.0, line.gpm or 0.0))
    seconds = math.max(0.0, math.min(tonumber(seconds) or 0.5, 2.0))
    if gpm <= 0 then return end

    local entity = NetworkGetEntityFromNetworkId(line.sourceNet)
    if not entity or entity == 0 then return end

    -- Gallons actually delivered, which is not necessarily what was asked for. A tank running
    -- dry does not announce itself; the line simply goes soft, which is what happens.
    local wanted = gpm * (seconds / 60.0)
    local drawn = MIFire.ApparatusServer.draw(entity, wanted)

    if drawn <= 0 then
        if not line.warnedDry then
            line.warnedDry = true
            notifyLine(line, 'The line has gone soft -- the tank is empty', 'error')
        end
        return
    end

    line.warnedDry = nil

    -- The agent is water unless the rig is proportioning foam, which Phase 8 turns on. Routed
    -- through the same entry point every other water source uses, so no line can bypass the
    -- agent matrix and quietly put water on a Class D fire without consequence.
    local delivered = drawn * (60.0 / math.max(0.01, seconds))

    MIFire.Fire.applyAgent(coords, 3.0, line.agent or 'water', {
        gpm = delivered,
        seconds = seconds,
        source = source,
    })
end)

--- Cycle the nozzle pattern.
---
--- Server-side because pattern changes what the water does, and what the water does is fire
--- state.
RegisterNetEvent('mi_fire:server:cycleNozzlePattern', function()
    local source = source
    local line = HoseServer.lineFor(source)
    if not line or line.nozzleHolder ~= source then return end

    local nozzle = MIFireHose.nozzles[line.nozzle or '']
    if not nozzle or not nozzle.patterns or #nozzle.patterns < 2 then
        return TriggerClientEvent('mi_fire:client:notify', source,
            'A smooth bore has one pattern -- that is rather the point of it', 'inform')
    end

    local current = line.pattern or nozzle.defaultPattern or nozzle.patterns[1]
    local index = 1

    for i = 1, #nozzle.patterns do
        if nozzle.patterns[i] == current then index = i break end
    end

    line.pattern = nozzle.patterns[(index % #nozzle.patterns) + 1]
    sync(line)

    TriggerClientEvent('mi_fire:client:notify', source,
        ('Pattern: %s'):format(line.pattern), 'inform')
end)

--- Relay a client's own diagnosis back to it, so both halves arrive the same way.
RegisterNetEvent('mi_fire:server:relayHoseDiagnosis', function(lines_)
    local source = source
    if type(lines_) ~= 'table' then return end

    for i = 1, math.min(#lines_, 20) do
        if type(lines_[i]) == 'string' then
            TriggerClientEvent('mi_fire:client:notify', source, lines_[i], 'inform')
        end
    end
end)

--- A client that just joined has no lines at all.
RegisterNetEvent('mi_fire:server:requestHoses', function()
    local source = source
    for _, line in pairs(lines) do sync(line, source) end
end)

AddEventHandler('playerDropped', function()
    local source = source

    -- Someone leaving does not delete the line their crew was on. It stays, one hand short,
    -- which is exactly what happens when a firefighter goes down or walks off -- and the crew
    -- finds out through the flow ceiling rather than through the hose vanishing.
    HoseServer.leaveCrew(source)
end)

exports('GetHoseLines', function() return lines end)
exports('GetHoseLineFor', function(source) return HoseServer.lineFor(source) end)

MIFire.HoseServer = HoseServer

return HoseServer
