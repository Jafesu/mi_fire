--- Hose lines: crew, flow, and what happens when you are short-handed.
---
--- Pure. No natives, so what a two-person 2.5 inch can actually do is checkable without
--- finding two people and a fire.
---
--- The rule this module exists to enforce: **a bigger line is not simply better.** More water
--- costs more people, more pressure and more time. If a 2.5 inch were strictly superior a
--- crew would take it everywhere and the choice would be decoration.

MIFire = MIFire or {}

local Hose = {}

--- How many people a line wants, at its rated flow.
---@param size table An entry from `MIFireHose.sizes`.
---@return integer
function Hose.crewRequired(size)
    return math.max(1, math.floor(tonumber(size.crew) or 1))
end

--- What a crew of this size can actually get out of this line.
---
--- Never zero and never a refusal. One firefighter on a 2.5 inch gets a fraction of its flow
--- and a line that fights them, which is the honest answer -- "you may not" teaches nothing
--- and reads as the script being in charge rather than the physics.
---@param size table
---@param crew integer How many are actually on it.
---@param config table `MIFireHose.underCrewed`
---@return number gpm The most this crew can flow.
---@return integer missing How many short they are.
function Hose.flowCeiling(size, crew, config)
    local required = Hose.crewRequired(size)
    local maximum = size.gpmRange and size.gpmRange[2] or 100.0
    local minimum = size.gpmRange and size.gpmRange[1] or 20.0

    crew = math.max(0, math.floor(tonumber(crew) or 0))

    if crew == 0 then return 0.0, required end
    if crew >= required then return maximum, 0 end

    local missing = required - crew
    local ceiling = maximum * (config.flowCeilingPerMissing ^ missing)

    -- Never below what the line would trickle at, or an under-crewed line becomes a closed
    -- one and the player reads it as broken rather than as hard.
    return math.max(minimum * 0.5, ceiling), missing
end

--- How badly the nozzle wanders, in degrees.
---@param size table
---@param crew integer
---@param config table
---@return number degrees
function Hose.aimDrift(size, crew, config)
    local _, missing = Hose.flowCeiling(size, crew, config)
    return missing * (config.aimDriftPerMissing or 0.0)
end

--- Chance per second of losing the line.
---
--- Scales with how short the crew is **and** with how hard the line is being pushed: a 2.5
--- inch held by one person at a trickle is awkward, and the same line at full flow is a
--- whipping charged hose that will hurt them.
---@param size table
---@param crew integer
---@param gpm number What is actually flowing.
---@param config table
---@return number chance 0-1
function Hose.lossChance(size, crew, gpm, config)
    local _, missing = Hose.flowCeiling(size, crew, config)
    if missing <= 0 then return 0.0 end

    local maximum = size.gpmRange and size.gpmRange[2] or 100.0
    local load = math.max(0.0, math.min(1.0, (tonumber(gpm) or 0.0) / maximum))

    return missing * (config.lossChancePerMissing or 0.0) * load
end

--- What a line weighs to move.
---
--- Charged hose is heavier than uncharged by a long way, which is the whole reason a crew
--- stretches dry and calls for water once they are in position rather than dragging a live
--- line through a building.
---@param size table
---@param sections integer
---@param charged boolean
---@return number kilograms
function Hose.dragWeight(size, sections, charged)
    local per = tonumber(size.dragPerSection) or 10.0
    local weight = per * math.max(0, sections)

    -- Water is most of the weight once the line is live.
    return charged and weight * 3.2 or weight
end

--- How fast a crew can move a line.
---@param size table
---@param sections integer
---@param charged boolean
---@param crew integer
---@param config table `MIFireHose.work`
---@return number metresPerSecond
function Hose.dragSpeed(size, sections, charged, crew, config)
    local weight = Hose.dragWeight(size, sections, charged)
    local base = tonumber(config.dragSpeed) or 1.0

    -- Each person carries their share. Crew is the thing that makes a big line movable, which
    -- is the same reason it takes three of them to work it.
    local carried = weight / math.max(1, crew)

    -- 25kg each is comfortable; past that it slows sharply.
    local factor = math.min(1.0, 25.0 / math.max(1.0, carried))

    return base * factor
end

--- Feet of hose in a line.
---@param size table
---@param sections integer
---@return number feet
function Hose.lengthFeet(size, sections)
    return (tonumber(size.sectionFeet) or 50) * math.max(0, sections)
end

--- Sections needed to cover a distance, rounded up -- hose comes in lengths.
---@param size table
---@param metres number
---@return integer
function Hose.sectionsFor(size, metres)
    local feet = (tonumber(metres) or 0.0) * 3.28084
    local per = tonumber(size.sectionFeet) or 50

    return math.max(1, math.ceil(feet / per))
end

--- Can this nozzle go on this line?
---
--- A supply line has no nozzle at all: 5 inch LDH feeds an appliance or another pump, and
--- putting a fog nozzle on it is a category error rather than a bad idea.
---@param size table
---@param nozzleName string
---@return boolean
---@return string|nil reason
function Hose.acceptsNozzle(size, nozzleName)
    if size.supplyOnly then
        return false, ('%s is a supply line -- it feeds an appliance, not a nozzle')
            :format(size.label or 'that hose')
    end

    for _, allowed in ipairs(size.nozzles or {}) do
        if allowed == nozzleName then return true end
    end

    return false, ('%s does not take that nozzle'):format(size.label or 'that hose')
end

--- How far apart two points are, ignoring nothing.
---@param a table
---@param b table
---@return number metres
local function distance(a, b)
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    local dz = (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- Where the hose has been laid, one point at a time.
---
--- A GTA rope cannot describe a walked path. Rope type 6 comes back with **three** vertices
--- however long it is made, so pinning the ends leaves one point in the middle and everything
--- between them is a free-hanging catenary that moves whenever either end does. That is why a
--- line follows the firefighter around instead of staying where it was laid, and why adding
--- slack never helped: more slack is a longer curve between the same two moving points.
---
--- So the path is recorded rather than simulated. A point is dropped every `spacing` metres as
--- the nozzle is carried away from the rig, and taken back up when the crew walks in again --
--- which is what a hose does, rather than dragging its whole length along behind.
---
--- Pure, and separate from the rendering, because the interesting behaviour is the hysteresis:
--- dropping and consuming at the same distance makes a point flicker in and out with every step
--- taken near the boundary, and each flicker is a rope created and destroyed.
---
---@param trail table[] The points so far, nearest the rig first. Mutated in place.
---@param position table Where the nozzle is now.
---@param spacing number Metres between points.
---@param maxPoints number|nil Refuse to grow past this.
---@return string change 'added' | 'removed' | 'none'
function Hose.trailStep(trail, position, spacing, maxPoints)
    if type(trail) ~= 'table' or type(position) ~= 'table' then return 'none' end

    spacing = tonumber(spacing) or 3.0
    if spacing <= 0 then return 'none' end

    local count = #trail
    if count == 0 then return 'none' end

    -- Walking back in. Checked before laying more, so a crew reversing takes up slack rather
    -- than laying a point on top of one they are about to reach.
    --
    -- 0.6 of the spacing, not the spacing itself: consuming at the same distance as dropping
    -- means a step either side of the boundary adds and removes a point repeatedly, and every
    -- one of those is a rope built and torn down.
    if count >= 2 and distance(position, trail[count - 1]) < spacing * 0.6 then
        trail[count] = nil
        return 'removed'
    end

    if distance(position, trail[count]) >= spacing then
        if maxPoints and count >= maxPoints then return 'none' end
        trail[count + 1] = { x = position.x, y = position.y, z = position.z }
        return 'added'
    end

    return 'none'
end

--- How much hose is actually out, along the path rather than as the crow flies.
---
--- The honest number: a line walked around a corner has used its length going round the corner,
--- and measuring the straight line back to the rig would say a crew has hose left that they do
--- not. This is what should be compared against what was pulled from the bed.
---
---@param trail table[]
---@param head table|nil Where the nozzle is now, beyond the last point.
---@return number metres
function Hose.trailLength(trail, head)
    if type(trail) ~= 'table' then return 0.0 end

    local total = 0.0

    for i = 2, #trail do
        total = total + distance(trail[i - 1], trail[i])
    end

    if head and #trail > 0 then
        total = total + distance(trail[#trail], head)
    end

    return total
end


--- Turn the bezel one notch.
---
--- Pure, and separate from the event that calls it, because the interesting part is the
--- **ends**. Opening a fog fully and finding it back at a straight stream is not something a
--- nozzle does, and on a fireground it would be a faceful of steam -- so a directional step
--- clamps. A plain cycle still wraps, because the command that uses it has nowhere to show you
--- which end you are at and stopping dead reads as broken.
---
---@param nozzle table
---@param current string|nil
---@param direction integer|nil -1 tightens toward a straight stream, 1 opens the fog, nil cycles
---@return string|nil pattern nil when there is nothing to change to
function Hose.stepPattern(nozzle, current, direction)
    if type(nozzle) ~= 'table' then return nil end

    local patterns = nozzle.patterns
    if type(patterns) ~= 'table' or #patterns < 2 then return nil end

    current = current or nozzle.defaultPattern or patterns[1]

    local index = 1
    for i = 1, #patterns do
        if patterns[i] == current then index = i break end
    end

    if direction == 1 or direction == -1 then
        local wanted = math.max(1, math.min(#patterns, index + direction))
        if wanted == index then return nil end
        return patterns[wanted]
    end

    return patterns[(index % #patterns) + 1]
end


--- How much of the flow lands where it is aimed.
---
--- A wide fog is a shield, not an extinguishing pattern. It protects a crew crossing a room
--- and it puts very little water on the seat, which is a tactical decision rather than a
--- setting to leave alone.
---@param nozzle table
---@param pattern string
---@return number multiplier
function Hose.patternEfficiency(nozzle, pattern)
    local efficiency = nozzle.efficiency or {}
    return tonumber(efficiency[pattern]) or 1.0
end

--- Smooth bore flow, from the tip and the nozzle pressure.
---
--- Delegated to the hydraulics rather than duplicated, because that is where the published
--- formula lives and two copies of a formula is one too many.
---@param nozzle table
---@param nozzlePressure number|nil Defaults to the nozzle's rated pressure.
---@return number|nil gpm Nil for a fog nozzle, whose flow is set rather than derived.
function Hose.smoothBoreFlow(nozzle, nozzlePressure)
    if not nozzle.tipInches then return nil end

    return MIFire.Hydraulics.smoothBoreFlow(
        nozzle.tipInches, nozzlePressure or nozzle.nozzlePressure)
end

MIFire.Hose = Hose

return Hose
