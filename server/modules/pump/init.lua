--- Pump operations, server side.
---
--- Owns what each rig's pump is doing and solves every live line against it, once a second.
---
--- **This is where the nozzle stops choosing its own flow.** Before this, opening a nozzle
--- asked for a number of gallons and got it. Now the nozzle has a bail position and the pump
--- has a discharge pressure, and what comes out of the tip is whatever survives the trip --
--- which is the entire reason a pump operator exists and the only thing that makes a panel
--- worth looking at.

MIFire = MIFire or {}

local PumpServer = {}

local Util = MIFire.Util
local Pump = MIFire.Pump
local Hose = MIFire.Hose

--- Pump state per apparatus, keyed by network id.
---@type table<number, table>
local pumps = {}

--- State for a rig, created on first use.
---@param entity integer
---@return table|nil
function PumpServer.state(entity)
    local profile = MIFire.ApparatusServer.profile(entity)
    if not profile or not MIFire.Apparatus.hasPump(profile) then return nil end

    local netId = NetworkGetNetworkIdFromEntity(entity)
    if not netId or netId == 0 then return nil end

    local state = pumps[netId]

    if not state then
        state = {
            netId = netId,
            --- Discharge pressure per port, psi. Nothing is open until an operator opens it,
            --- which is why a charged line with no pressure set does nothing.
            discharges = {},
            --- Pressure governor. Holds a setpoint across changes on other discharges, which
            --- is the whole reason the device exists.
            governor = { mode = 'rpm', setpoint = 0.0 },
            intakePsi = 0.0,
            cavitating = false,
            totalGpm = 0.0,
        }

        pumps[netId] = state
    end

    return state
end

--- Set what an outlet is putting out.
---@param entity integer
---@param portId string
---@param psi number
---@return boolean ok
---@return string|nil reason
function PumpServer.setDischarge(entity, portId, psi)
    local profile = MIFire.ApparatusServer.profile(entity)
    if not profile then return false, 'that is not fire apparatus' end

    local port = MIFire.Apparatus.port(profile, portId)
    if not port or port.type ~= 'discharge' then return false, 'no such discharge' end

    local state = PumpServer.state(entity)
    if not state then return false, 'that rig has no pump' end

    local tank = MIFire.ApparatusServer.tank(entity)
    if not tank or not tank.pumpEngaged then return false, 'the pump is not engaged' end

    -- The relief valve is a real limit, not a suggestion. Past it the pump is not making more
    -- pressure, it is dumping the excess back to intake.
    local maximum = profile.maxDischargePsi or 250.0

    state.discharges[portId] = math.max(0.0, math.min(tonumber(psi) or 0.0, maximum))

    return true, (tonumber(psi) or 0) > maximum
        and ('the relief valve holds this pump at %d psi'):format(maximum)
        or nil
end

---@param entity integer
---@param portId string
---@return number psi
function PumpServer.dischargePsi(entity, portId)
    local state = PumpServer.state(entity)
    return state and state.discharges[portId] or 0.0
end

-- ---------------------------------------------------------------------------
-- Solving
-- ---------------------------------------------------------------------------

--- How long a line actually is, in feet.
---
--- The hose on the bed, not the distance to the fire. A crew that stretches two hundred feet
--- to reach forty feet away is carrying two hundred feet of friction loss, which is a real and
--- commonly underappreciated cost of over-stretching.
---@param line table
---@return number
local function lineLengthFeet(line)
    local size = MIFireHose.sizes[line.diameter]
    if not size then return 0.0 end

    return Hose.lengthFeet(size, line.sections or 1)
end

--- Solve every line on one pump and hand out the water.
---@param entity integer
---@param state table
---@param lines table[] Charged lines fed by this rig.
---@param dt number
local function solvePump(entity, state, lines, dt)
    local profile = MIFire.ApparatusServer.profile(entity)
    local tank = MIFire.ApparatusServer.tank(entity)
    if not profile or not tank then return end

    -- --- What each line wants -----------------------------------------------------------

    local demands = {}

    for i = 1, #lines do
        local line = lines[i]
        local size = MIFireHose.sizes[line.diameter] or {}
        local nozzle = MIFireHose.nozzles[line.nozzle or ''] or {}

        local psi = state.discharges[line.sourcePort] or 0.0

        -- The bail. Closed is closed however much pressure is behind it, which is what lets a
        -- crew move up without shutting the whole line down at the panel.
        local bail = math.max(0.0, math.min(1.0, line.bail or 0.0))

        local gpm, nozzlePsi, losses = 0.0, 0.0, {}

        if bail > 0 and psi > 0 then
            gpm, nozzlePsi, losses = Pump.solveLine({
                dischargePsi = psi,
                diameter = line.diameter,
                lengthFeet = lineLengthFeet(line),
                elevationFeet = line.elevationFeet or 0.0,
                appliance = line.appliance,
                nozzle = nozzle,
                ratedGpm = size.gpmRange and size.gpmRange[2],
                startGpm = line.gpm or 100.0,
            })

            gpm = gpm * bail
        end

        demands[#demands + 1] = {
            line = line,
            gpm = gpm,
            nozzlePsi = nozzlePsi,
            losses = losses,
        }
    end

    -- --- What the pump can make ---------------------------------------------------------

    local highest = 0.0
    for portId, psi in pairs(state.discharges) do
        if psi > highest then highest = psi end
    end

    local wanted = 0.0
    for i = 1, #demands do wanted = wanted + demands[i].gpm end

    local available, over = Pump.capacity(profile.pumpRatingGpm or 0, highest, wanted)
    local shared = Pump.share(demands, available)

    state.totalGpm = math.min(wanted, available)
    state.overCapacity = over

    -- --- Cavitation ---------------------------------------------------------------------

    -- Off the tank there is no intake pressure to speak of, so a rig drafting its own tank at
    -- more than the tank can feed is exactly the case this catches. A supply line raises the
    -- intake, which is Phase 5.
    local wasCavitating = state.cavitating
    state.cavitating = MIFire.Hydraulics.isCavitating(state.intakePsi, wanted, available)

    if state.cavitating and not wasCavitating then
        for i = 1, #demands do
            MIFire.HoseServer.notify(demands[i].line,
                'The pump is cavitating -- it is being asked for more than it is being fed',
                'error')
        end
    end

    -- --- Hand it out --------------------------------------------------------------------

    for i = 1, #demands do
        local demand = demands[i]
        local line = demand.line
        local gpm = shared[i] or 0.0

        -- The crew is the last limit. Pressure and pump capacity decide what the line *can*
        -- flow; the people on it decide what they can hold open.
        local size = MIFireHose.sizes[line.diameter]

        if size then
            local ceiling = Hose.flowCeiling(size, MIFire.HoseServer.crewOn(line),
                MIFireHose.underCrewed)
            gpm = math.min(gpm, ceiling)
        end

        -- Spend the tank. Whatever the pump is being asked for, it can only move what it has.
        local wantedGallons = gpm * (dt / 60.0)
        local drawn = MIFire.ApparatusServer.draw(entity, wantedGallons)

        if wantedGallons > 0 and drawn < wantedGallons * 0.99 then
            gpm = drawn * (60.0 / math.max(0.01, dt))
        end

        line.gpm = gpm
        line.dischargePsi = state.discharges[line.sourcePort] or 0.0
        line.nozzlePsi = demand.nozzlePsi
        line.losses = demand.losses

        local nozzle = MIFireHose.nozzles[line.nozzle or ''] or {}
        local usable, word = Pump.lineCondition(demand.nozzlePsi, nozzle)

        line.usable = usable
        line.condition = word
    end
end

-- ---------------------------------------------------------------------------
-- Tick
-- ---------------------------------------------------------------------------

CreateThread(function()
    while not MIFire.ready do Wait(250) end

    local interval = 1000
    local dt = interval / 1000.0

    while true do
        Wait(interval)

        -- Group charged lines by the rig feeding them, so a pump is solved once with all of
        -- its lines rather than once per line. Sharing capacity between them is the whole
        -- point and it cannot be done a line at a time.
        local byRig = {}

        for _, line in pairs(MIFire.HoseServer.all()) do
            if line.state == 'charged' and line.sourceNet then
                byRig[line.sourceNet] = byRig[line.sourceNet] or {}
                table.insert(byRig[line.sourceNet], line)
            end
        end

        for netId, lines in pairs(byRig) do
            local entity = NetworkGetEntityFromNetworkId(netId)

            if entity and entity ~= 0 and DoesEntityExist(entity) then
                local state = PumpServer.state(entity)

                if state then
                    local ok, err = pcall(solvePump, entity, state, lines, dt)
                    if not ok then
                        Util.warn('pump solve failed for %s: %s', tostring(netId), tostring(err))
                    end

                    MIFire.HoseServer.syncAll(lines)
                end
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Transports
-- ---------------------------------------------------------------------------

RegisterNetEvent('mi_fire:server:setDischarge', function(netId, portId, psi)
    local source = source
    if type(portId) ~= 'string' then return end

    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 then return end

    if not MIFire.Permissions.isNear(source, GetEntityCoords(entity), 6.0) then return end

    local ok, note = PumpServer.setDischarge(entity, portId, tonumber(psi) or 0)

    if note then
        TriggerClientEvent('mi_fire:client:notify', source, note, ok and 'inform' or 'error')
    end
end)

exports('GetPumpState', function(entity) return PumpServer.state(entity) end)
exports('SetDischargePressure', function(entity, portId, psi)
    return PumpServer.setDischarge(entity, portId, psi)
end)

MIFire.PumpServer = PumpServer

return PumpServer
