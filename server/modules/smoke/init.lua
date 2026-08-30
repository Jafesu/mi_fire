--- Smoke.
---
--- Computes what each fire is producing, tracks the ventilation state that drives it, and
--- runs the two events reading it is supposed to let a crew avoid.
---
--- The design point: **flashover builds and backdraft waits.** Flashover has a timer, so
--- reading the smoke buys real seconds to act. Backdraft has no timer at all -- it sits
--- there indefinitely and is *triggered*, by someone opening the compartment from the wrong
--- place. That asymmetry is the character of the two, and it is why one is announced and
--- the other is not.

MIFire = MIFire or {}

local SmokeServer = {}

local Util = MIFire.Util
local State = MIFire.State
local Smoke = MIFire.Smoke
local Enums = MIFire.Enums

--- Per-incident smoke state.
---@type table<string, table>
local incidents = {}

---@param incidentId string
---@return table
local function stateFor(incidentId)
    if not incidents[incidentId] then
        local incident = State.getIncident(incidentId)
        incidents[incidentId] = {
            ventilation = (incident and incident.interiorId)
                and MIFireSmoke.defaultVentilation or 'open',
            flashoverSeconds = 0.0,
            flashedOver = false,
            attributes = nil,
        }
    end
    return incidents[incidentId]
end

-- ---------------------------------------------------------------------------
-- Reading
-- ---------------------------------------------------------------------------

--- The worst reading across an incident's nodes.
---
--- Worst rather than average, because a size-up is about the most dangerous thing visible,
--- not the typical thing. An officer reporting the average of a fire is not doing a size-up.
---@param incidentId string
---@return table|nil attributes
---@return table|nil node The node it came from.
function SmokeServer.readIncident(incidentId)
    local incident = State.getIncident(incidentId)
    if not incident then return nil end

    local smoke = stateFor(incidentId)
    local confined = incident.interiorId ~= nil

    local worst, worstNode, worstScore = nil, nil, -1

    for _, node in ipairs(State.getNodesForIncident(incidentId)) do
        if node.intensity > 0 and node.state ~= Enums.NodeState.OUT then
            local fuelFraction = node.resolved.fuel > 0
                and (node.fuel / node.resolved.fuel) or 0.0

            local attributes = Smoke.attributes({
                intensity = node.intensity,
                fuelFraction = fuelFraction,
                class = node.resolved,
                ventilation = smoke.ventilation,
                confined = confined,
            }, MIFireSmoke)

            -- Rank by what the smoke is warning about, then by how much of it there is.
            local score = math.max(
                Smoke.flashoverRisk(attributes, smoke.ventilation, confined, MIFireSmoke),
                Smoke.backdraftRisk(attributes, smoke.ventilation, confined, MIFireSmoke))
                * 10.0 + attributes.volume

            if score > worstScore then
                worst, worstNode, worstScore = attributes, node, score
            end
        end
    end

    return worst, worstNode
end

--- A full reading, in the words a size-up uses.
---@param incidentId string
---@return table|nil
function SmokeServer.sizeUp(incidentId)
    local attributes = SmokeServer.readIncident(incidentId)
    if not attributes then return nil end

    local incident = State.getIncident(incidentId)
    local smoke = stateFor(incidentId)

    local reading = Smoke.read(attributes, smoke.ventilation,
        incident.interiorId ~= nil, MIFireSmoke)

    reading.ventilation = MIFireSmoke.ventilation[smoke.ventilation].label
    reading.incidentId = incidentId
    return reading
end

-- ---------------------------------------------------------------------------
-- Ventilation
-- ---------------------------------------------------------------------------

--- Change an incident's ventilation.
---
--- Returns whether a backdraft was set off, because that is the whole consequence of
--- getting this wrong and the caller needs to know it happened.
---@param incidentId string
---@param actionName string Key from `MIFireSmoke.actions`.
---@param source integer|nil Who did it.
---@return boolean ok
---@return string|nil reason
---@return boolean backdraft
function SmokeServer.ventilate(incidentId, actionName, source)
    local incident = State.getIncident(incidentId)
    if not incident then return false, 'no such incident', false end

    local action = MIFireSmoke.actions[actionName]
    if not action then return false, 'unknown ventilation action', false end

    local smoke = stateFor(incidentId)
    local confined = incident.interiorId ~= nil

    -- Check for backdraft *before* changing the state, because the risk is a property of
    -- the compartment as it was when someone opened it.
    local backdraft = false

    if MIFireSmoke.backdraft.enabled and action.triggersBackdraft and confined then
        local attributes = SmokeServer.readIncident(incidentId)

        if attributes then
            local risk = Smoke.backdraftRisk(attributes, smoke.ventilation, true, MIFireSmoke)
            if risk >= MIFireSmoke.warnAbove and Util.chance(risk * 100.0) then
                SmokeServer.triggerBackdraft(incidentId, source)
                backdraft = true
            end
        end
    end

    smoke.ventilation = action.setsVentilation

    -- Venting above the fire lets heat go straight up rather than drawing air across it,
    -- which is why it is the answer to a suspected backdraft and why it buys time.
    if action.vertical and action.flashoverRelief then
        smoke.flashoverSeconds = smoke.flashoverSeconds * (1.0 - action.flashoverRelief)
    end

    Util.debug('smoke', '%s ventilation -> %s%s', incidentId, action.setsVentilation,
        backdraft and ' (BACKDRAFT)' or '')

    SmokeServer.publish(incidentId)
    return true, nil, backdraft
end

---@param incidentId string
---@return string
function SmokeServer.ventilationOf(incidentId)
    return stateFor(incidentId).ventilation
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

--- Everything in the compartment lights at once.
---@param incidentId string
function SmokeServer.triggerFlashover(incidentId)
    local incident = State.getIncident(incidentId)
    if not incident then return end

    local smoke = stateFor(incidentId)
    smoke.flashedOver = true
    smoke.flashoverSeconds = 0.0

    local cfg = MIFireSmoke.flashover

    for _, node in ipairs(State.getNodesForIncident(incidentId)) do
        node.intensity = math.min(node.resolved.maxIntensity,
            node.intensity + cfg.intensityJump)
    end

    for _ = 1, cfg.spawnNodes do
        local angle = Util.randomFloat(0, math.pi * 2)
        local distance = Util.randomFloat(1.0, cfg.radius)
        MIFire.Fire.addNode(incidentId, {
            x = incident.coords.x + math.cos(angle) * distance,
            y = incident.coords.y + math.sin(angle) * distance,
            z = incident.coords.z,
        }, incident.class, { interiorId = incident.interiorId })
    end

    TriggerClientEvent('mi_fire:client:fireEvent', -1, {
        kind = 'flashover',
        coords = incident.coords,
        radius = cfg.radius,
        damage = cfg.damage,
    })

    Util.debug('smoke', 'FLASHOVER at %s', incidentId)
end

--- A starved fire finds air all at once.
---@param incidentId string
---@param source integer|nil Whoever opened it.
function SmokeServer.triggerBackdraft(incidentId, source)
    local incident = State.getIncident(incidentId)
    if not incident then return end

    local cfg = MIFireSmoke.backdraft
    local smoke = stateFor(incidentId)

    for _, node in ipairs(State.getNodesForIncident(incidentId)) do
        node.intensity = math.min(node.resolved.maxIntensity,
            node.intensity + cfg.intensityJump)
    end

    for _ = 1, cfg.spawnNodes do
        local angle = Util.randomFloat(0, math.pi * 2)
        local distance = Util.randomFloat(1.0, cfg.radius)
        MIFire.Fire.addNode(incidentId, {
            x = incident.coords.x + math.cos(angle) * distance,
            y = incident.coords.y + math.sin(angle) * distance,
            z = incident.coords.z,
        }, incident.class, { interiorId = incident.interiorId })
    end

    -- It has its air now, so it is no longer a backdraft risk -- it is a working fire.
    smoke.ventilation = 'open'

    TriggerClientEvent('mi_fire:client:fireEvent', -1, {
        kind = 'backdraft',
        coords = incident.coords,
        radius = cfg.radius,
        damage = cfg.damage,
        knockback = cfg.knockbackForce,
        source = source,
    })

    Util.debug('smoke', 'BACKDRAFT at %s', incidentId)
end

-- ---------------------------------------------------------------------------
-- Sync
-- ---------------------------------------------------------------------------

--- Push an incident's smoke to clients so they can render and read it.
---@param incidentId string
function SmokeServer.publish(incidentId)
    local attributes, node = SmokeServer.readIncident(incidentId)
    local smoke = incidents[incidentId]

    if not attributes or not node then
        TriggerClientEvent('mi_fire:client:smoke', -1, incidentId, nil)
        return
    end

    TriggerClientEvent('mi_fire:client:smoke', -1, incidentId, {
        coords = node.coords,
        volume = Util.round(attributes.volume, 2),
        density = Util.round(attributes.density, 2),
        velocity = Util.round(attributes.velocity, 2),
        turbulent = attributes.turbulent,
        stage = attributes.stage,
        colour = attributes.colour,
        ventilation = smoke.ventilation,
        pulsing = Smoke.isPulsing(
            Smoke.backdraftRisk(attributes, smoke.ventilation, true, MIFireSmoke), MIFireSmoke),
    })
end

-- ---------------------------------------------------------------------------
-- Tick
-- ---------------------------------------------------------------------------

CreateThread(function()
    while not MIFire.ready do Wait(250) end

    local interval = 2000
    local dt = interval / 1000.0

    while true do
        Wait(interval)

        for incidentId, incident in pairs(State.getIncidents()) do
            local smoke = stateFor(incidentId)
            local confined = incident.interiorId ~= nil
            local attributes = SmokeServer.readIncident(incidentId)

            if attributes then
                smoke.attributes = attributes

                -- Flashover builds. The warning window is the whole reason to read smoke,
                -- so it has to be long enough to act on.
                if MIFireSmoke.flashover.enabled and confined and not smoke.flashedOver then
                    local risk = Smoke.flashoverRisk(attributes, smoke.ventilation,
                        true, MIFireSmoke)

                    if risk >= MIFireSmoke.warnAbove then
                        smoke.flashoverSeconds = smoke.flashoverSeconds + dt

                        if smoke.flashoverSeconds >= MIFireSmoke.flashover.warningSeconds
                            and Util.chance(MIFireSmoke.flashover.chancePerSecond * dt) then
                            SmokeServer.triggerFlashover(incidentId)
                        end
                    else
                        -- Cooling off, so the clock winds back rather than resetting.
                        -- A crew that improves conditions should see the benefit.
                        smoke.flashoverSeconds = math.max(0.0, smoke.flashoverSeconds - dt)
                    end
                end

                SmokeServer.publish(incidentId)
            end
        end

        -- Forget incidents that are out.
        for incidentId in pairs(incidents) do
            if not State.getIncident(incidentId) then
                TriggerClientEvent('mi_fire:client:smoke', -1, incidentId, nil)
                incidents[incidentId] = nil
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------------

exports('SizeUpIncident', function(incidentId)
    return SmokeServer.sizeUp(tostring(incidentId))
end)

exports('GetVentilation', function(incidentId)
    return SmokeServer.ventilationOf(tostring(incidentId))
end)

exports('SetVentilation', function(incidentId, action)
    return SmokeServer.ventilate(tostring(incidentId), action)
end)

MIFire.SmokeServer = SmokeServer

return SmokeServer
