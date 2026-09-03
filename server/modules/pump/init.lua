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
            --- How far the throttle is open, 0-1. This is the pump's output pressure, and it
            --- is one number for the whole pump -- because that is what a pump is. Every
            --- outlet is fed from it.
            throttle = 0.0,

            --- Gate valve position per port, 0 shut to 1 wide open.
            ---
            --- **Not a pressure.** An operator does not type 150 into a discharge; they pull a
            --- handle. The gauge above it then reads what that outlet is doing, which is the
            --- pump's pressure less whatever a part-closed gate is throttling away.
            valves = {},

            --- Pressure governor. Holds a setpoint across changes on other discharges, which
            --- is the whole reason the device exists. Not implemented yet.
            governor = { mode = 'rpm', setpoint = 0.0 },
            intakePsi = 0.0,
            cavitating = false,
            totalGpm = 0.0,
        }

        pumps[netId] = state
    end

    return state
end

--- What the pump is making, before any valve.
---
--- One number for the whole pump, because that is what a pump is: the throttle drives the
--- impeller and every outlet is fed from the same volute. An operator raising the throttle
--- raises it for everybody.
---@param profile table
---@param throttle number 0-1
---@return number psi
function PumpServer.masterPressure(profile, throttle)
    local maximum = profile.maxDischargePsi or 250.0

    -- Idle is not zero. A pump in gear at idle is already making something, which is why a
    -- line charges before anyone touches the throttle.
    local idle = MIFirePump.idlePsi or 40.0

    return idle + (maximum - idle) * math.max(0.0, math.min(1.0, throttle or 0.0))
end

--- Move the throttle.
---@param entity integer
---@param delta number Change in position, -1 to 1.
---@return boolean ok
---@return string|nil reason
function PumpServer.throttle(entity, delta)
    local state = PumpServer.state(entity)
    if not state then return false, 'that rig has no pump' end

    local tank = MIFire.ApparatusServer.tank(entity)
    if not tank or not tank.pumpEngaged then return false, 'the pump is not engaged' end

    state.throttle = math.max(0.0, math.min(1.0, state.throttle + (tonumber(delta) or 0.0)))

    return true
end

--- Open or close a gate.
---@param entity integer
---@param portId string
---@param position number 0 shut, 1 wide open.
---@return boolean ok
---@return string|nil reason
function PumpServer.setValve(entity, portId, position)
    local profile = MIFire.ApparatusServer.profile(entity)
    if not profile then return false, 'that is not fire apparatus' end

    local port = MIFire.Apparatus.port(profile, portId)
    if not port or port.type ~= 'discharge' then return false, 'no such discharge' end

    local state = PumpServer.state(entity)
    if not state then return false, 'that rig has no pump' end

    local tank = MIFire.ApparatusServer.tank(entity)
    if not tank or not tank.pumpEngaged then return false, 'the pump is not engaged' end

    state.valves[portId] = math.max(0.0, math.min(1.0, tonumber(position) or 0.0))

    return true
end

--- What one outlet is actually putting out.
---
--- A gate valve does not reduce pressure by sitting there -- with nothing flowing, a
--- part-open gate reads the same as a wide one. It throttles when water is moving through it,
--- and the loss grows sharply as it closes.
---
--- Modelled as a loss proportional to how far shut it is, squared, which is the right shape
--- even if the coefficient is ours rather than published. **Flagged as a question** in
--- `docs/guides/pump-operations-explained.md`.
---@param masterPsi number
---@param position number
---@return number psi
function PumpServer.outletPressure(masterPsi, position)
    position = math.max(0.0, math.min(1.0, position or 0.0))

    if position <= 0.0 then return 0.0 end

    local shut = 1.0 - position
    return masterPsi * (1.0 - shut * shut)
end

---@param entity integer
---@param portId string
---@return number psi
function PumpServer.dischargePsi(entity, portId)
    local state = PumpServer.state(entity)
    if not state then return 0.0 end

    local profile = MIFire.ApparatusServer.profile(entity)
    if not profile then return 0.0 end

    return PumpServer.outletPressure(
        PumpServer.masterPressure(profile, state.throttle),
        state.valves[portId] or 0.0)
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

    local masterPsi = PumpServer.masterPressure(profile, state.throttle)
    state.masterPsi = masterPsi

    -- --- What each line wants -----------------------------------------------------------

    local demands = {}

    for i = 1, #lines do
        local line = lines[i]
        local size = MIFireHose.sizes[line.diameter] or {}
        local nozzle = MIFireHose.nozzles[line.nozzle or ''] or {}

        local psi = PumpServer.outletPressure(masterPsi, state.valves[line.sourcePort] or 0.0)

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

    -- Net pressure for the curve is what the pump is making, not what any one outlet reads
    -- after its gate.
    local highest = masterPsi

    local wanted = 0.0
    for i = 1, #demands do wanted = wanted + demands[i].gpm end

    local available, over = Pump.capacity(profile.pumpRatingGpm or 0, highest, wanted)
    local shared = Pump.share(demands, available)

    state.totalGpm = math.min(wanted, available)
    state.overCapacity = over

    -- --- Cavitation ---------------------------------------------------------------------

    -- Off the tank there is no intake pressure to speak of, so the intake term is not consulted
    -- and what catches a rig drawing harder than it can feed is its own capacity against demand.
    -- A supply line raises the intake and makes that term meaningful, which is Phase 5 -- at
    -- which point this passes `true`.
    local fromSupplyLine = (state.intakePsi or 0) > 0

    local wasCavitating = state.cavitating
    state.cavitating = MIFire.Hydraulics.isCavitating(
        state.intakePsi, wanted, available, fromSupplyLine)

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
        line.dischargePsi = PumpServer.outletPressure(
            masterPsi, state.valves[line.sourcePort] or 0.0)
        line.valve = state.valves[line.sourcePort] or 0.0
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

RegisterNetEvent('mi_fire:server:setValve', function(netId, portId, position)
    local source = source
    if type(portId) ~= 'string' then return end

    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 then return end
    if not MIFire.Permissions.isNear(source, GetEntityCoords(entity), 6.0) then return end

    local ok, why = PumpServer.setValve(entity, portId, tonumber(position) or 0)

    if not ok and why then
        TriggerClientEvent('mi_fire:client:notify', source, why, 'error')
    end
end)

RegisterNetEvent('mi_fire:server:throttle', function(netId, delta)
    local source = source

    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 then return end
    if not MIFire.Permissions.isNear(source, GetEntityCoords(entity), 6.0) then return end

    local ok, why = PumpServer.throttle(entity, tonumber(delta) or 0)

    if not ok and why then
        TriggerClientEvent('mi_fire:client:notify', source, why, 'error')
    end
end)

--- Everything the panel needs to draw itself, for one rig.
---
--- Every gauge that has a use is rendered and live, so every gauge that has a use is in here.
lib.callback.register('mi_fire:pumpState', function(source, netId)
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 then return nil end

    local profile = MIFire.ApparatusServer.profile(entity)
    local state = PumpServer.state(entity)
    local tank = MIFire.ApparatusServer.tank(entity)

    if not profile or not state or not tank then return nil end

    local outlets = {}

    for _, port in ipairs(profile.ports or {}) do
        if port.type == 'discharge' then
            local psi = PumpServer.outletPressure(
                state.masterPsi or 0.0, state.valves[port.id] or 0.0)

            local line
            for _, candidate in pairs(MIFire.HoseServer.all()) do
                if candidate.sourceNet == state.netId and candidate.sourcePort == port.id then
                    line = candidate
                    break
                end
            end

            outlets[#outlets + 1] = {
                id = port.id,
                label = port.label or port.id,
                size = port.size,
                valve = state.valves[port.id] or 0.0,
                psi = psi,
                gpm = line and line.gpm or 0.0,
                nozzlePsi = line and line.nozzlePsi or 0.0,
                condition = line and line.condition or nil,
                connected = line ~= nil,
            }
        end
    end

    return {
        label = profile.label,
        family = profile.panelFamily,
        engaged = tank.pumpEngaged,
        throttle = state.throttle,
        masterPsi = state.masterPsi or 0.0,
        intakePsi = state.intakePsi or 0.0,
        totalGpm = state.totalGpm or 0.0,
        cavitating = state.cavitating or false,
        overCapacity = state.overCapacity or false,
        ratedGpm = profile.pumpRatingGpm,
        maxPsi = profile.maxDischargePsi,
        tank = { water = tank.water, capacity = tank.capacity },
        foam = { level = tank.foam, capacity = tank.foamCapacity },
        outlets = outlets,
    }
end)

exports('GetPumpState', function(entity) return PumpServer.state(entity) end)
exports('SetDischargeValve', function(entity, portId, position)
    return PumpServer.setValve(entity, portId, position)
end)

MIFire.PumpServer = PumpServer

return PumpServer
