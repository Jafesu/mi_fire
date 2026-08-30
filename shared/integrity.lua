--- Gear integrity: what happens to damaged equipment.
---
--- Three models, because servers disagree about this and both positions are defensible.
---
---   **regenerate**  gear recovers on its own once you are clear of the fire. Forgiving,
---                   no logistics, and nobody is ever stuck. "Back out for a minute and
---                   you are good again."
---   **persist**     damage stays until someone repairs or replaces the set. Realistic --
---                   thermal damage to real turnout does not heal, and NFPA 1851 exists
---                   precisely because gear has to be inspected and serviced after a fire.
---                   Adds logistics, and a reason for a station to have a gear room.
---   **session**     damage lasts the shift and resets when you re-don. A middle ground
---                   that costs nothing to run.
---
--- Pure, so what happens to a coat can be reasoned about without setting one on fire.

MIFire = MIFire or {}

local Integrity = {}

Integrity.Mode = {
    REGENERATE = 'regenerate',
    PERSIST = 'persist',
    SESSION = 'session',
}

-- ---------------------------------------------------------------------------
-- Recovery
-- ---------------------------------------------------------------------------

--- How much integrity a set recovers in `dt` seconds.
---
--- Only `regenerate` recovers at all. The delay matters more than the rate: a crew that
--- ducks out for two seconds should not be reset, and one that rotates out properly should
--- be. That gap is the whole mechanic.
---
---@param current number Current integrity.
---@param capacity number The tier's full integrity.
---@param secondsSinceFlame number How long since this set was last in fire.
---@param dt number
---@param config table `MIFireGear.integrity`
---@return number integrity
function Integrity.recover(current, capacity, secondsSinceFlame, dt, config)
    if config.mode ~= Integrity.Mode.REGENERATE then return current end
    if capacity <= 0 then return current end
    if current >= capacity then return current end

    local rules = config.regenerate or {}
    if secondsSinceFlame < (rules.delaySeconds or 60.0) then return current end

    local ceiling = capacity * math.max(0.0, math.min(1.0, rules.recoverTo or 1.0))
    if current >= ceiling then return current end

    return math.min(ceiling, current + (rules.ratePerSecond or 2.0) * dt)
end

-- ---------------------------------------------------------------------------
-- Condition
-- ---------------------------------------------------------------------------

--- Is this set too far gone to repair?
---
--- Condemned gear is a real thing: past a point a coat is not repaired, it is taken out of
--- service. Modelling that gives replacement a purpose distinct from repair.
---@param current number
---@param capacity number
---@param config table
---@return boolean
function Integrity.isCondemned(current, capacity, config)
    if capacity <= 0 then return false end
    local rules = config.persist or {}
    return (current / capacity) <= (rules.condemnedBelow or 0.15)
end

--- Can this set still be repaired rather than replaced?
---@param current number
---@param capacity number
---@param config table
---@return boolean ok
---@return string|nil reason
function Integrity.canRepair(current, capacity, config)
    if config.mode == Integrity.Mode.REGENERATE then
        return false, 'gear recovers on its own on this server'
    end

    if capacity <= 0 then return false, 'that gear has nothing to repair' end
    if current >= capacity then return false, 'that set is already in good condition' end

    if Integrity.isCondemned(current, capacity, config) then
        return false, 'that set is beyond repair -- it needs replacing'
    end

    return true
end

--- A word for what condition a set is in, for the player.
---
--- Bands rather than a percentage, because "78% integrity" is a number from a spreadsheet
--- and "showing wear" is something a firefighter would actually say.
---@param current number
---@param capacity number
---@param config table
---@return string condition
---@return number fraction
function Integrity.condition(current, capacity, config)
    if capacity <= 0 then return 'none', 0.0 end

    local fraction = math.max(0.0, math.min(1.0, current / capacity))

    if Integrity.isCondemned(current, capacity, config) then return 'condemned', fraction end
    if fraction >= 0.9 then return 'serviceable', fraction end
    if fraction >= 0.6 then return 'showing wear', fraction end
    if fraction >= 0.3 then return 'damaged', fraction end
    return 'badly damaged', fraction
end

-- ---------------------------------------------------------------------------
-- Repair
-- ---------------------------------------------------------------------------

--- How long repairing a set should take.
---
--- Scaled by how bad it is, so a scorched coat is quick and a nearly-condemned one is a
--- job. A flat time would make it a formality.
---@param current number
---@param capacity number
---@param config table
---@return number seconds
function Integrity.repairSeconds(current, capacity, config)
    local rules = config.persist or {}
    local base = rules.repairSeconds or 45.0

    if capacity <= 0 then return base end

    local missing = 1.0 - math.max(0.0, math.min(1.0, current / capacity))
    return base * (0.35 + 0.65 * missing)
end

--- What a set is worth after repair.
---
--- Repaired gear does not come back as new. Each repair loses a little of the ceiling, so
--- a set that has been through several fires is eventually replaced rather than endlessly
--- patched -- which is what actually happens to turnout gear.
---@param capacity number
---@param repairs number How many times this set has been repaired.
---@param config table
---@return number integrity
function Integrity.afterRepair(capacity, repairs, config)
    local rules = config.persist or {}
    local loss = rules.ceilingLossPerRepair or 0.0

    local ceiling = capacity * math.max(0.2, 1.0 - loss * math.max(0, repairs))
    return ceiling
end

MIFire.Integrity = Integrity

return Integrity
