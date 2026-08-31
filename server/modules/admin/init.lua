--- Admin commands.
---
--- Thin transports. Every one of these calls a service and reports what it said; none of
--- them contain fire logic. If a command needs to know how a fire works, the logic is in
--- the wrong place.
---
--- Access comes from `Config.permissions` via the permission service: either an ACE, or a
--- job at or above a configured grade. The server console is always allowed.
---
--- The commands are registered **unrestricted** on purpose. `lib.addCommand`'s `restricted`
--- maps to an ACE, and FiveM refuses the command before the handler runs -- which would make
--- job-grade access impossible, since a grade is runtime state an ACE cannot express. So the
--- gate is here instead, and a denied caller gets told why rather than "unknown command".

MIFire = MIFire or {}

local Admin = {}

local Util = MIFire.Util
local State = MIFire.State
local Permissions = MIFire.Permissions

-- ---------------------------------------------------------------------------
-- Reply helpers
-- ---------------------------------------------------------------------------

--- Answer on whichever channel the command came from. Source 0 is the console, which
--- cannot receive a notification.
---@param source integer
---@param message string
---@param kind string|nil 'inform' | 'error' | 'success'
local function reply(source, message, kind)
    if source == 0 then
        print(('[mi_fire] %s'):format(message))
        return
    end

    TriggerClientEvent('mi_fire:client:notify', source, message, kind or 'inform')
end

---@param source integer
---@param lines string[]
local function replyList(source, lines)
    for i = 1, #lines do reply(source, lines[i]) end
end

--- Where the caller is. Nil for the console, which has no position.
---@param source integer
---@return table|nil
local function callerCoords(source)
    if source == 0 then return nil end
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return nil end
    local coords = GetEntityCoords(ped)
    return { x = coords.x, y = coords.y, z = coords.z }
end

-- ---------------------------------------------------------------------------
-- Subcommands
-- ---------------------------------------------------------------------------

local subcommands = {}

--- `/fire start <class> [radius] [nodes]` -- at the caller's feet.
subcommands.start = function(source, args)
    local coords = callerCoords(source)
    if not coords then
        return reply(source, 'the console has no position; use "fire at <x> <y> <z>"', 'error')
    end

    local className = args[2] or 'A'
    if not MIFire.FireClass.exists(className) then
        return reply(source, ('unknown fire class "%s"; try: %s')
            :format(className, table.concat(MIFire.FireClass.names(), ', ')), 'error')
    end

    local incidentId, err = MIFire.Fire.startIncident({
        coords = coords,
        class = className,
        radius = tonumber(args[3]) or 3.0,
        nodeCount = tonumber(args[4]) or 3,
        origin = MIFire.Enums.IncidentOrigin.ADMIN,
        description = 'Started by an administrator',
    })

    if not incidentId then
        return reply(source, ('could not start a fire: %s'):format(tostring(err)), 'error')
    end

    reply(source, ('started %s (class %s)'):format(incidentId, className), 'success')
end

--- `/fire here` -- one node, class A, no scatter. The quickest possible test.
subcommands.here = function(source)
    local coords = callerCoords(source)
    if not coords then
        return reply(source, 'the console has no position; use "fire at <x> <y> <z>"', 'error')
    end

    local incidentId, err = MIFire.Fire.startIncident({
        coords = coords,
        class = 'A',
        nodeCount = 1,
        origin = MIFire.Enums.IncidentOrigin.ADMIN,
    })

    if not incidentId then
        return reply(source, ('could not start a fire: %s'):format(tostring(err)), 'error')
    end

    reply(source, ('started %s'):format(incidentId), 'success')
end

--- `/fire at <x> <y> <z> [class] [nodes]`
subcommands.at = function(source, args)
    local x, y, z = tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
    if not x or not y or not z then
        return reply(source, 'usage: fire at <x> <y> <z> [class] [nodes]', 'error')
    end

    local className = args[5] or 'A'
    if not MIFire.FireClass.exists(className) then
        return reply(source, ('unknown fire class "%s"'):format(className), 'error')
    end

    local incidentId, err = MIFire.Fire.startIncident({
        coords = { x = x, y = y, z = z },
        class = className,
        nodeCount = tonumber(args[6]) or 3,
        radius = 3.0,
        origin = MIFire.Enums.IncidentOrigin.ADMIN,
    })

    if not incidentId then
        return reply(source, ('could not start a fire: %s'):format(tostring(err)), 'error')
    end

    reply(source, ('started %s at %.1f, %.1f, %.1f'):format(incidentId, x, y, z), 'success')
end

--- `/fire stop <id>`
subcommands.stop = function(source, args)
    local incidentId = args[2]
    if not incidentId then return reply(source, 'usage: fire stop <id>', 'error') end

    -- Accept a bare number as shorthand for "incident:N", since typing the prefix every
    -- time is tedious and the ids are printed with it.
    if tonumber(incidentId) then incidentId = 'incident:' .. incidentId end

    if MIFire.Fire.stopIncident(incidentId) then
        reply(source, ('stopped %s'):format(incidentId), 'success')
    else
        reply(source, ('no incident %s'):format(incidentId), 'error')
    end
end

--- `/fire stopall`
subcommands.stopall = function(source)
    local count = MIFire.Fire.stopAll()
    reply(source, ('stopped %d incident(s)'):format(count), 'success')
end

--- `/fire list`
subcommands.list = function(source)
    local incidents = State.getIncidents()
    if next(incidents) == nil then
        return reply(source, 'nothing is burning')
    end

    local lines = {}
    for incidentId in pairs(incidents) do
        local info = MIFire.Fire.describe(incidentId)
        if info then
            lines[#lines + 1] = ('%s  class %s  %d node(s), %d live  avg intensity %.0f  %ds old')
                :format(info.id, info.class, info.nodeCount, info.liveNodes,
                    info.averageIntensity, info.ageSeconds)
        end
    end

    table.sort(lines)
    replyList(source, lines)
end

--- `/fire info <id>`
subcommands.info = function(source, args)
    local incidentId = args[2]
    if not incidentId then return reply(source, 'usage: fire info <id>', 'error') end
    if tonumber(incidentId) then incidentId = 'incident:' .. incidentId end

    local info = MIFire.Fire.describe(incidentId)
    if not info then return reply(source, ('no incident %s'):format(incidentId), 'error') end

    replyList(source, {
        ('%s  class %s  origin %s'):format(info.id, info.class, info.origin),
        ('  nodes: %d total, %d live, %d knocked down'):format(
            info.nodeCount, info.liveNodes, info.knockedDownNodes),
        ('  average intensity %.1f, fuel remaining %.0f'):format(
            info.averageIntensity, info.fuelRemaining),
        ('  at %.1f, %.1f, %.1f'):format(info.coords.x, info.coords.y, info.coords.z),
        ('  %d seconds old'):format(info.ageSeconds),
    })
end

--- `/fire agent <agent> [radius] [gpm] [seconds]`
---
--- The test harness for the agent matrix, and the only way to put a fire out until hose
--- lines exist in Phase 3. Applying the wrong agent here fires the real hazard, which is
--- the point -- this is how the matrix gets verified in game.
subcommands.agent = function(source, args)
    local coords = callerCoords(source)
    if not coords then
        return reply(source, 'the console has no position', 'error')
    end

    local agentName = args[2]
    if not agentName then
        local names = {}
        for name in pairs(MIFireAgents.matrix) do names[#names + 1] = name end
        table.sort(names)
        return reply(source, ('usage: fire agent <%s> [radius] [gpm] [seconds]')
            :format(table.concat(names, '|')), 'error')
    end

    if not MIFireAgents.matrix[agentName] then
        return reply(source, ('unknown agent "%s"'):format(agentName), 'error')
    end

    local result = MIFire.Fire.applyAgent(coords, tonumber(args[3]) or 12.0, agentName, {
        gpm = tonumber(args[4]) or 150.0,
        seconds = tonumber(args[5]) or 3.0,
        source = source,
    })

    if result.nodesAffected == 0 then
        return reply(source, 'nothing in range that agent affects')
    end

    local direction = result.intensityRemoved >= 0 and 'removed' or 'ADDED'
    local message = ('%s: %d node(s), %s %.1f intensity, %d knocked down')
        :format(agentName, result.nodesAffected, direction,
            math.abs(result.intensityRemoved), result.knockedDown)

    if #result.hazards > 0 then
        message = message .. (' -- hazards fired: %s'):format(table.concat(result.hazards, ', '))
    end

    reply(source, message, result.intensityRemoved >= 0 and 'success' or 'error')
end

--- `/fire wind [heading degrees] [speed 0-1]`
subcommands.wind = function(source, args)
    if args[2] then
        MIFire.Spread.setWind(math.rad(tonumber(args[2]) or 0), tonumber(args[3]) or 0.5)
    end

    local wind = MIFire.Spread.getWind()
    reply(source, ('wind heading %.0f degrees, speed %.2f')
        :format(math.deg(wind.heading) % 360, wind.speed))
end

--- `/fire classes`
subcommands.classes = function(source)
    local lines = {}
    for _, name in ipairs(MIFire.FireClass.names()) do
        local class = MIFire.FireClass.resolve(name)
        lines[#lines + 1] = ('%-9s %s'):format(name, class.label or '')
    end
    replyList(source, lines)
end

--- `/fire sizeup [id]` -- read the smoke on the nearest incident.
---
--- Not gated on admin, because reading smoke is the job rather than an administrative act.
--- What *is* gated is the interpretation: everyone is told what they can see, and an
--- officer is told what it means. That teaches the skill instead of replacing it.
subcommands.sizeup = function(source, args)
    local coords = callerCoords(source)
    if not coords then
        return reply(source, 'the console cannot look at anything', 'error')
    end

    local incidentId = args[2]
    if incidentId and tonumber(incidentId) then incidentId = 'incident:' .. incidentId end

    if not incidentId then
        local nearest, nearestDistance
        for id, incident in pairs(State.getIncidents()) do
            local distance = math.sqrt(Util.distance3dSq(
                coords.x, coords.y, coords.z,
                incident.coords.x, incident.coords.y, incident.coords.z))
            if distance <= MIFireSmoke.sizeup.maxDistance
                and (not nearestDistance or distance < nearestDistance) then
                nearest, nearestDistance = id, distance
            end
        end
        incidentId = nearest
    end

    if not incidentId then
        return reply(source, 'nothing close enough to size up')
    end

    local reading = MIFire.SmokeServer.sizeUp(incidentId)
    if not reading then
        return reply(source, 'no smoke showing', 'error')
    end

    -- The observation. Everyone gets this.
    replyList(source, {
        ('%s volume, %s.'):format(reading.volume, reading.velocity),
        ('%s and %s.'):format(reading.density, reading.colour),
        ('Ventilation reads %s.'):format(reading.ventilation),
    })

    -- The interpretation. Gated on rank.
    local _, _, grade = MIFire.Framework.getJob(source)
    if (grade or 0) < MIFireSmoke.sizeup.interpretationGrade
        and not Permissions.hasAdminAce(source) then
        return
    end

    local conclusions = MIFireSmoke.sizeup.conclusions

    if reading.warning == MIFire.Smoke.Warning.FLASHOVER then
        reply(source, conclusions.flashover, 'error')
    elseif reading.warning == MIFire.Smoke.Warning.BACKDRAFT then
        reply(source, conclusions.backdraft, 'error')
    elseif reading.stage == MIFire.Smoke.Stage.PYROLYSIS then
        reply(source, conclusions.pyrolysis)
    elseif reading.values.density < 0.35 then
        reply(source, conclusions.clean)
    end
end

--- `/fire vent <action> [id]` -- change how a compartment is ventilated.
---
--- The tactical decision the whole smoke model exists to make interesting. Forcing a door
--- on a starved compartment is how a crew gets hurt; cutting the roof first is how they
--- do not.
subcommands.vent = function(source, args)
    local coords = callerCoords(source)
    if not coords then
        return reply(source, 'the console cannot ventilate anything', 'error')
    end

    local actionName = args[2]
    if not actionName or not MIFireSmoke.actions[actionName] then
        local names = {}
        for name, action in pairs(MIFireSmoke.actions) do
            names[#names + 1] = ('%s (%s)'):format(name, action.label)
        end
        table.sort(names)
        return replyList(source, {
            'usage: fire vent <action> [id]',
            table.concat(names, ', '),
        })
    end

    local incidentId = args[3]
    if incidentId and tonumber(incidentId) then incidentId = 'incident:' .. incidentId end

    if not incidentId then
        local nearest, nearestDistance
        for id, incident in pairs(State.getIncidents()) do
            local distance = math.sqrt(Util.distance3dSq(
                coords.x, coords.y, coords.z,
                incident.coords.x, incident.coords.y, incident.coords.z))
            if distance <= 30.0 and (not nearestDistance or distance < nearestDistance) then
                nearest, nearestDistance = id, distance
            end
        end
        incidentId = nearest
    end

    if not incidentId then return reply(source, 'nothing close enough to ventilate') end

    local ok, why, backdraft = MIFire.SmokeServer.ventilate(incidentId, actionName, source)
    if not ok then return reply(source, why or 'that did not work', 'error') end

    if backdraft then
        reply(source, 'It went up. You opened a starved compartment at ground level.', 'error')
    else
        reply(source, ('%s -- ventilation now %s'):format(
            MIFireSmoke.actions[actionName].label,
            MIFire.SmokeServer.ventilationOf(incidentId)), 'success')
    end
end

--- `/fire render` -- ask your own client what it knows and what it is drawing.
---
--- Exists because "I ran the command and nothing happened" was impossible to diagnose from
--- the server: it had started the fire, and said so truthfully. This separates three
--- different bugs -- the client never got the node, the particle dictionary failed to load,
--- or the effect name is not in that dictionary and the native returned 0 without saying so.
subcommands.render = function(source)
    if source == 0 then
        return reply(source, 'the console has no client to ask; run this in game', 'error')
    end
    TriggerClientEvent('mi_fire:client:diagnose', source)
    reply(source, 'render diagnosis printed to your chat and F8 console')
end

--- `/fire gear` -- why there is no turnout or SCBA option on the truck you are stood at.
---
--- Same reasoning as `render`: an ox_target option that does not appear is five booleans
--- deep and produces no error, no log line, and nothing to look at. The client knows all
--- five, so it is asked.
subcommands.gear = function(source)
    if source == 0 then
        return reply(source, 'the console has no client to ask; run this in game', 'error')
    end

    -- The server's own view first. The client and the server can disagree about what you
    -- are wearing -- that disagreement is exactly the bug class this exists for, and asking
    -- only the client cannot see it.
    local State = MIFire.State
    local tier, entry = State.getGearTier(source)
    local capacity = tier and tier.integrity or 0

    local lines = {
        '--- what the SERVER thinks you are wearing ---',
        ('tier: %s   integrity: %.1f / %.1f   coverage: %.0f%%'):format(
            entry.tier or 'none', entry.integrity or 0, capacity,
            (entry.coverage or 1.0) * 100),
    }

    if capacity <= 0 then
        lines[#lines + 1] = '  -> NO PROTECTION. A tier with no integrity pool is always '
            .. 'ignitable, so you will catch fire almost at once.'
    else
        lines[#lines + 1] = ('  fireResist %.2f, ignites below %.0f (%.0f%%), currently %s')
            :format(tier.fireResist or 0,
                capacity * (tier.ignitionThreshold or 0), (tier.ignitionThreshold or 0) * 100,
                MIFire.Exposure.canIgnite(entry.integrity or 0, tier)
                    and 'IGNITABLE' or 'not ignitable')
    end

    local scba = State.getScba(source)
    lines[#lines + 1] = ('scba: worn=%s active=%s armed=%s air=%.0fs%s'):format(
        tostring(scba.worn), tostring(scba.active), tostring(scba.passArmed == true),
        scba.air or 0, scba.fromClothing and ' (from clothing)' or '')

    local down, why = MIFire.Medical.isDown(source)
    lines[#lines + 1] = ('down: %s%s'):format(tostring(down), why and (' (' .. why .. ')') or '')

    -- What the exposure model is sampling where you are standing right now, and what each
    -- channel is doing to you per second. This is the number that matters: "I died in seven
    -- seconds" is only diagnosable against the per-channel breakdown.
    local ped = GetPlayerPed(source)
    if ped and ped ~= 0 and MIFire.ExposureServer then
        local sample = MIFire.ExposureServer.sample(GetEntityCoords(ped), tier)
        local ex = MIFireGear.exposure

        local resist = MIFire.Exposure.effectiveFireResist(entry.integrity or 0, tier)
            * MIFire.GearMatch.protectionMultiplier(entry.coverage or 1.0, MIFireGear.coverage)

        local flame = sample.flameIntensity > 0
            and MIFire.Exposure.flameDamage(sample.flameIntensity, { fireResist = resist }, ex.flame)
            or 0.0

        lines[#lines + 1] = ('exposure here: flame intensity %.0f, smoke %.2f, heat build %.1f')
            :format(sample.flameIntensity, sample.smokeDensity, sample.heatBuild)
        lines[#lines + 1] = ('  effective resist %.3f  ->  flame %.2f hp/s')
            :format(resist, flame)

        if not scba.active and sample.smokeDensity > 0 then
            lines[#lines + 1] = ('  smoke %.2f hp/s -- YOUR VALVE IS SHUT, so smoke is '
                .. 'hurting you'):format((ex.smoke.damagePerTick or 0) * sample.smokeDensity)
        end
    end

    -- Handed to the client rather than printed here, so both halves land in one F8 block.
    -- Splitting them across the server console and the chat box is how the useful half
    -- gets lost.
    TriggerClientEvent('mi_fire:client:diagnoseGear', source, lines)
    reply(source, 'gear diagnosis printed to your F8 console -- both halves')
end

--- `/fire decals` -- find a decal type that actually draws on this build.
---
--- Every other visual constant in this resource is pinned to a name verified in something
--- already running. There was no `AddDecal` call anywhere on this machine to check against,
--- and a bad decal type returns 0 and prints nothing -- the same silent failure that made an
--- invented particle name look like broken rendering for a whole session. So the value gets
--- authored by looking at it.
subcommands.decals = function(source, args)
    if source == 0 then
        return reply(source, 'the console has no client to draw on; run this in game', 'error')
    end
    -- `/fire decals sweep` walks a wide range of type IDs rather than the configured
    -- shortlist. Worth having because "none of my guesses worked" and "the native is
    -- refusing outright" look identical from the outside, and they need different fixes.
    local sweep = args[2] == 'sweep'

    TriggerClientEvent('mi_fire:client:decalTest', source, sweep)
    reply(source, sweep
        and 'sweeping every plausible type; markers last two minutes'
        or 'candidates laid out ahead of you -- try "/fire decals sweep" if none appear')
end

--- `/fire scorch` -- how many burn marks exist, and clear them.
subcommands.scorch = function(source, args)
    if args[2] == 'clear' then
        local removed = MIFire.ScorchServer.clear()
        return reply(source, ('cleared %d burn mark(s)'):format(removed))
    end

    local count = 0
    for _ in pairs(MIFire.ScorchServer.all()) do count = count + 1 end

    reply(source, ('%d burn mark(s), lasting %.0f minutes each')
        :format(count, MIFireScorch.lifetimeMinutes))
end

--- `/fire hose` -- what lines exist, and a way out when one is stuck.
---
--- Exists because the first in-game test left a player holding a prop attached to a line whose
--- rope had gone wrong, with nothing in the world to target to get rid of it. A system that can
--- strand someone needs a way to un-strand them that does not involve a server restart.
subcommands.hose = function(source, args)
    local action = args[2]

    if action == 'clear' then
        local count = 0
        for id in pairs(MIFire.HoseServer.all()) do
            MIFire.HoseServer.stow(source, id, true)
            count = count + 1
        end

        TriggerClientEvent('mi_fire:client:clearHoseProps', -1)
        return reply(source, ('cleared %d line(s)'):format(count), 'success')
    end

    if action == 'drop' then
        MIFire.HoseServer.leaveCrew(source)
        TriggerClientEvent('mi_fire:client:clearHoseProps', source)
        return reply(source, 'dropped your line', 'success')
    end

    local lines = MIFire.HoseServer.all()
    local rows = {}

    for id, line in pairs(lines) do
        local crew = 0
        for _ in pairs(line.crew or {}) do crew = crew + 1 end

        rows[#rows + 1] = ('%s  %s"  %s  %d/%d crew  %.0f gpm  rig %s')
            :format(id, tostring(line.diameter), line.state, crew,
                line.crewRequired or 1, line.gpm or 0, tostring(line.sourceNet))
    end

    table.insert(rows, 1, '--- what the SERVER holds ---')

    if #rows == 1 then rows[#rows + 1] = '  no lines out' end

    rows[#rows + 1] = 'fire hose drop   -- put your own line down'
    rows[#rows + 1] = 'fire hose clear  -- remove every line'

    replyList(source, rows)

    -- The client's half, in the same block. The two disagreeing is the whole bug class here.
    TriggerClientEvent('mi_fire:client:diagnoseHoses', source)
end

--- `/fire ropetypes` -- lay all eight rope types out and pick one.
---
--- A rope's texture cannot be changed for one resource without changing it for every rope on
--- the server, so the eight built-in types are the whole of what is available without giving
--- up ropes entirely. Worth a minute of looking before committing to a rewrite.
subcommands.ropetypes = function(source)
    if source == 0 then
        return reply(source, 'the console has nowhere to put them; run this in game', 'error')
    end

    TriggerClientEvent('mi_fire:client:ropeTypes', source)
    reply(source, 'eight ropes ahead of you, numbered. Set the best as MIFireHose.visuals.ropeType')
end

--- `/fire nozzle` -- why there is nothing in your hand.
---
--- Tries the configured prop and then base game ones, loading and attaching each in turn. A
--- base game prop appearing proves the attaching works and the answer is that the configured
--- model is not reaching this client; none appearing means something else entirely.
subcommands.nozzle = function(source)
    if source == 0 then
        return reply(source, 'the console has no hands; run this in game', 'error')
    end

    TriggerClientEvent('mi_fire:client:testNozzle', source)
    reply(source, 'trying each candidate for two seconds; watch your hand')
end

--- `/fire nozzlehold <clipset|off> [move]` -- try a carrying stance without a restart.
---
--- The stance a nozzle is held in cannot be settled from a file. Two clipsets do two different
--- jobs through two different natives -- the weapon clipset is the hold, the movement clipset
--- is the walk -- the game reports both as loaded, and the wrong pairing is a T-pose. So it
--- gets tried, and the winner goes into `MIFireHose.visuals`.
subcommands.nozzlehold = function(source, args)
    if source == 0 then
        return reply(source, 'the console has no body to pose; run this in game', 'error')
    end

    -- `args[2]`, not `args[1]`: the dispatcher passes the subcommand name as the first entry.
    local clipset = args[2]

    if not clipset then
        return reply(source,
            'usage: /fire nozzlehold <clipset|off> [move]. Default is the weapon clipset, '
            .. 'which is the hold -- try weapons@heavy@minigun. Add "move" for the walk, '
            .. 'where names begin move_. "off" puts you back to normal.', 'error')
    end

    TriggerClientEvent('mi_fire:client:nozzleHold', source, clipset, args[3])
    reply(source, ('trying "%s" as the %s clipset -- aim, and walk around')
        :format(clipset, args[3] == 'move' and 'movement' or 'weapon'))
end

--- `/fire nozzlegrip ...` -- move the nozzle in the hand.
---
--- Baking a new origin into the model costs an export and a restart to see one attempt. This is
--- the same job live, and it prints the config line to paste back when it looks right.
---
---     /fire nozzlegrip show                  what it is now
---     /fire nozzlegrip aim                   hold the aim pose and edit that placement
---     /fire nozzlegrip carry                 let go, and edit the carrying placement
---     /fire nozzlegrip nudge <axis> <amount> one axis at a time: x y z rx ry rz
---     /fire nozzlegrip bone <left|right>     which hand
---     /fire nozzlegrip <x> <y> <z> <rx> <ry> <rz>   all six at once
---     /fire nozzlegrip off                   hand placement back to the game
---
--- `aim` holds the aim control down, because tuning the aiming placement otherwise means
--- holding right mouse, typing, releasing to look, and re-aiming -- per nudge, of which there
--- are dozens.
---
--- Per-axis because finding a placement means changing one thing and seeing what moved.
--- Retyping six numbers to alter one of them is how people stop bothering.
subcommands.nozzlegrip = function(source, args)
    if source == 0 then
        return reply(source, 'the console has no hands; run this in game', 'error')
    end

    local action = args[2]

    if action == 'off' or action == 'reset' then
        TriggerClientEvent('mi_fire:client:nozzleGrip', source, 'off')
        return reply(source, 'grip override cleared')
    end

    if not action or action == 'show' then
        TriggerClientEvent('mi_fire:client:nozzleGrip', source, 'show')
        return reply(source,
            'nudge one axis at a time: /fire nozzlegrip nudge z 0.02. '
            .. '"aim" holds the aim pose so you can tune it without holding the button.')
    end

    if action == 'aim' or action == 'carry' then
        TriggerClientEvent('mi_fire:client:nozzleGrip', source, action)
        return reply(source, action == 'aim'
            and 'holding aim -- nudges now edit the aiming placement'
            or 'aim released -- nudges now edit the carrying placement')
    end

    if action == 'bone' then
        local bone = args[3]

        if bone ~= 'left' and bone ~= 'right' then
            return reply(source, 'usage: /fire nozzlegrip bone <left|right>', 'error')
        end

        TriggerClientEvent('mi_fire:client:nozzleGrip', source, 'bone', bone)
        return reply(source, ('moved to the %s hand'):format(bone))
    end

    if action == 'nudge' then
        local axis = args[3]
        local amount = tonumber(args[4])

        if not amount then
            return reply(source,
                'usage: /fire nozzlegrip nudge <x|y|z|rx|ry|rz> <amount>. '
                .. 'Try 0.02 for a position, 15 for a rotation, and negatives to go back.',
                'error')
        end

        TriggerClientEvent('mi_fire:client:nozzleGrip', source, 'nudge', axis, amount)
        return reply(source, ('%s %+g'):format(tostring(axis), amount))
    end

    -- Six numbers, all at once.
    local numbers = {}

    for i = 2, 7 do
        local value = tonumber(args[i])

        if not value then
            return reply(source,
                ('"%s" is neither a number nor one of show, aim, carry, nudge, bone, off')
                    :format(tostring(args[i])), 'error')
        end

        numbers[#numbers + 1] = value
    end

    TriggerClientEvent('mi_fire:client:nozzleGrip', source, 'set', {
        bone = 'right',
        x = numbers[1], y = numbers[2], z = numbers[3],
        rx = numbers[4], ry = numbers[5], rz = numbers[6],
    })

    reply(source, 'applied -- look at your hands')
end

--- `/fire perms` -- why you can or cannot use these commands.
---
--- Deliberately reachable by anyone: someone who cannot run the commands is exactly who
--- needs to see this, and it reveals nothing beyond their own access.
subcommands.perms = function(source)
    replyList(source, MIFire.Permissions.explain(source))
end

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------

local USAGE = {
    'fire start <class> [radius] [nodes]  -- at your feet',
    'fire here                            -- one class A node',
    'fire at <x> <y> <z> [class] [nodes]',
    'fire agent <agent> [radius] [gpm] [seconds]',
    'fire stop <id> | stopall | list | info <id>',
    'fire classes | wind [heading] [speed]',
    'fire perms                           -- why you can or cannot use these',
    'fire render                          -- what your client is actually drawing',
    'fire gear                            -- why the truck has no gear options',
    'fire decals [sweep]                  -- find a working burn-mark decal type',
    'fire scorch [clear]                  -- burn marks: count, or remove them all',
    'fire hose [drop|clear]               -- lines out, and a way out of a stuck one',
    'fire ropetypes                       -- compare the eight rope types',
    'fire nozzle                          -- why there is nothing in your hand',
    'fire sizeup [id]                     -- read the smoke',
    'fire vent <action> [id]              -- force_door | take_window | vertical_vent | close_up',
}

---@param source integer
---@param args string[]
function Admin.handle(source, args)
    local sub = args[1] and args[1]:lower()

    -- `perms` is the one subcommand anyone may run: it only reports the caller's own access,
    -- and refusing to explain a refusal is how a permissions problem becomes a support ticket.
    -- Reading smoke and ventilating are the job rather than administration, so they are
    -- gated on being a firefighter instead of on admin.
    if sub == 'sizeup' or sub == 'vent' then
        local allowed, why = Permissions.requireFirefighter(source)
        if not allowed then return reply(source, why or 'not allowed', 'error') end

        local ok, err = pcall(subcommands[sub], source, args)
        if not ok then
            Util.warn('command "fire %s" failed: %s', sub, tostring(err))
            reply(source, ('that failed: %s'):format(tostring(err)), 'error')
        end
        return
    end

    if sub ~= 'perms' and sub ~= 'gear' then
        local allowed, why = Permissions.requireAdmin(source, sub)
        if not allowed then
            reply(source, why or 'not allowed', 'error')
            return reply(source, 'run "/fire perms" to see exactly why')
        end
    end

    if not sub or sub == 'help' then
        return replyList(source, USAGE)
    end

    local handler = subcommands[sub]
    if not handler then
        reply(source, ('unknown subcommand "%s"'):format(sub), 'error')
        return replyList(source, USAGE)
    end

    local ok, err = pcall(handler, source, args)
    if not ok then
        Util.warn('command "fire %s" failed: %s', sub, tostring(err))
        reply(source, ('that failed: %s'):format(tostring(err)), 'error')
    end
end

CreateThread(function()
    while not MIFire.ready do Wait(250) end

    local name = Config.commands.fire or 'fire'

    lib.addCommand(name, {
        help = 'Fire administration. Run "/fire perms" if it refuses you.',
        params = {
            { name = 'subcommand', type = 'string', help = 'start|here|at|agent|stop|stopall|list|info|classes|wind|perms|gear', optional = true },
        },
        -- Intentionally unrestricted; see the note at the top of this file.
    }, function(source, args, raw)
        -- ox_lib maps named params into the args table, so rebuild the positional list the
        -- subcommand handlers expect rather than teaching every one of them two shapes.
        local positional = {}
        for word in raw:gmatch('%S+') do positional[#positional + 1] = word end
        table.remove(positional, 1)   -- drop the command name itself

        Admin.handle(source, positional)
    end)

    Util.debug('admin', 'registered /%s', name)
end)

MIFire.Admin = Admin

return Admin
