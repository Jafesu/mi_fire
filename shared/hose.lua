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
