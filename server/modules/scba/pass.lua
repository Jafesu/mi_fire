--- PASS devices, server side.
---
--- Motion is detected here rather than reported by the client, from position deltas the
--- server already has. Two reasons, and the second is the important one: it is cheap, and
--- a modified client cannot silence its own PASS. A device that can be suppressed by the
--- person wearing it is worse than no device, because a crew would learn to trust it.
---
--- The phase machine itself is in `shared/pass.lua` and is pure. This file only feeds it
--- inputs and broadcasts what comes out.

MIFire = MIFire or {}

local PassServer = {}

local Util = MIFire.Util
local State = MIFire.State
local Pass = MIFire.Pass

---@type table<integer, table> device state, keyed by player
local devices = {}

---@type table<integer, table> last known position, for motion detection
local lastPosition = {}

-- ---------------------------------------------------------------------------

---@param source integer
---@return table
local function deviceFor(source)
    if not devices[source] then devices[source] = Pass.newState() end
    return devices[source]
end

--- Did this player move meaningfully since the last tick?
---
--- Compared against a threshold rather than exact equality, because a standing ped drifts
--- fractionally and a firefighter working a nozzle from one spot should not be told they
--- are motionless.
---@param source integer
---@param ped integer
---@return boolean moved
---@return boolean downed
local function sampleMotion(source, ped)
    local coords = GetEntityCoords(ped)
    local previous = lastPosition[source]

    lastPosition[source] = coords

    local threshold = MIFireScba.pass.movementThreshold
    local moved = true

    if previous then
        moved = #(coords - previous) > threshold
    end

    -- Downed overrides everything the position says: a ragdolled ped slides, and that
    -- movement must not keep the alarm quiet.
    local downed = MIFireScba.pass.alarmWhenDowned
        and (IsPedDeadOrDying(ped, true) or IsPedRagdoll(ped) or GetEntityHealth(ped) <= 105)

    return moved, downed == true
end

--- Tell everyone close enough what this device is doing.
---
--- Broadcast by proximity rather than to everyone: a PASS forty-five metres away is the
--- point, and one across the map is noise on the wire.
---@param source integer
---@param state table
local function broadcast(source, state)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return end

    local coords = GetEntityCoords(ped)
    local range = Pass.range(state.phase, MIFireScba.pass)

    local payload = {
        source = source,
        phase = state.phase,
        escalation = Pass.escalation(state, MIFireScba.pass),
        coords = { x = coords.x, y = coords.y, z = coords.z },
        range = range,
    }

    -- The wearer always hears their own device, whatever the range works out to.
    TriggerClientEvent('mi_fire:client:passState', source, payload)

    if not Pass.isAudible(state.phase) then
        -- Tell listeners it stopped, so nobody is left with a sound playing for a device
        -- that has gone quiet.
        TriggerClientEvent('mi_fire:client:passState', -1, payload)
        return
    end

    local rangeSq = range * range

    for _, playerId in ipairs(GetPlayers()) do
        local listener = tonumber(playerId)
        if listener and listener ~= source then
            local listenerPed = GetPlayerPed(listener)
            if listenerPed and listenerPed ~= 0 then
                local delta = GetEntityCoords(listenerPed) - coords
                if (delta.x * delta.x + delta.y * delta.y + delta.z * delta.z) <= rangeSq then
                    TriggerClientEvent('mi_fire:client:passState', listener, payload)
                end
            end
        end
    end
end

--- A full alarm is a mayday. Everyone on duty is told, wherever they are.
---@param source integer
local function announceFullAlarm(source)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return end

    local coords = GetEntityCoords(ped)
    local name = GetPlayerName(source) or ('player %d'):format(source)

    for _, entry in ipairs(MIFire.Framework.getOnDutyFirefighters()) do
        if entry.source ~= source then
            TriggerClientEvent('mi_fire:client:mayday', entry.source, {
                source = source,
                name = name,
                coords = { x = coords.x, y = coords.y, z = coords.z },
            })
        end
    end

    Util.debug('pass', 'FULL ALARM for %s at %.1f, %.1f, %.1f',
        name, coords.x, coords.y, coords.z)
end

-- ---------------------------------------------------------------------------
-- Service
-- ---------------------------------------------------------------------------

--- Fire the panic button.
---@param source integer
---@return boolean
function PassServer.activate(source)
    if not State.getScba(source).worn then return false end

    local state = deviceFor(source)
    Pass.step(state, 0, { armed = true, manual = true }, MIFireScba.pass)
    broadcast(source, state)
    announceFullAlarm(source)
    return true
end

--- Reset a device. Only clears a full alarm, and not on someone still down.
---@param source integer
---@param target integer|nil Defaults to the caller, so a partner can reset someone else.
---@return boolean ok
---@return string|nil reason
function PassServer.reset(source, target)
    target = target or source

    local state = devices[target]
    if not state or state.phase ~= Pass.Phase.FULL then
        return false, 'that device is not alarming'
    end

    local ped = GetPlayerPed(target)
    local _, downed = sampleMotion(target, ped)

    if downed then
        return false, 'they are still down -- the device will not reset'
    end

    Pass.step(state, 0, { armed = true, reset = true }, MIFireScba.pass)
    broadcast(target, state)
    return true
end

---@param source integer
---@return table
function PassServer.getState(source)
    return deviceFor(source)
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

        if MIFireScba.pass.enabled then
            for _, playerId in ipairs(GetPlayers()) do
                local source = tonumber(playerId)
                local scba = State.getScba(source)

                -- Armed means the set is on and the valve open. A set on your back with
                -- the valve shut is not a device that should be alarming.
                local armed = scba.worn
                    and (scba.active or not MIFireScba.pass.armOnActivate)

                if armed or devices[source] then
                    local ped = GetPlayerPed(source)

                    if ped and ped ~= 0 then
                        local moved, downed = sampleMotion(source, ped)
                        local state = deviceFor(source)

                        local _, changed = Pass.step(state, dt, {
                            armed = armed, moved = moved, downed = downed,
                        }, MIFireScba.pass)

                        if changed then
                            broadcast(source, state)
                            if state.phase == Pass.Phase.FULL then
                                announceFullAlarm(source)
                            end
                        elseif state.phase == Pass.Phase.PRE_ALARM then
                            -- Re-broadcast while escalating so the chirp speeds up.
                            broadcast(source, state)
                        end

                        if state.phase == Pass.Phase.IDLE and not armed then
                            devices[source] = nil
                            lastPosition[source] = nil
                        end
                    end
                end
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Transports
-- ---------------------------------------------------------------------------

RegisterNetEvent('mi_fire:server:passActivate', function()
    PassServer.activate(source)
end)

RegisterNetEvent('mi_fire:server:passReset', function(targetServerId)
    local src = source
    local target = tonumber(targetServerId) or src

    -- Resetting someone else's device means being next to them.
    if target ~= src then
        local targetPed = GetPlayerPed(target)
        if not targetPed or targetPed == 0 then return end
        local coords = GetEntityCoords(targetPed)
        if not MIFire.Permissions.isNear(src, coords, 3.0) then
            return TriggerClientEvent('mi_fire:client:notify', src,
                'you are not close enough to reach the device', 'error')
        end
    end

    local ok, reason = PassServer.reset(src, target)
    if not ok and reason then
        TriggerClientEvent('mi_fire:client:notify', src, reason, 'error')
    end
end)

AddEventHandler('playerDropped', function()
    devices[source] = nil
    lastPosition[source] = nil
end)

exports('GetPassState', function(source)
    local state = devices[source]
    return state and state.phase or Pass.Phase.IDLE
end)

MIFire.PassServer = PassServer

return PassServer
