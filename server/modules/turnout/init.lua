--- Turnout gear and SCBA.
---
--- The rule this file exists to hold: **protection is server state, never clothing.** A
--- player wearing a turnout skin from a clothing menu has a look and nothing else. Every
--- resistance lookup reads what is recorded here, set only by actually donning at a rack.
---
--- Turnout and SCBA are independent. Partial states are legal and meaningful: SCBA without
--- turnout means you breathe but burn, turnout without SCBA means you survive flame but
--- not smoke. Both are real fireground mistakes worth being able to make.
---
--- Air lives on the **item**, not the player. A bottle carried between rigs keeps its
--- pressure, and racking it is what refills it -- which is why a firefighter cannot hoard
--- full cylinders and never visit a station.

MIFire = MIFire or {}

local Turnout = {}

local Util = MIFire.Util
local State = MIFire.State
local Permissions = MIFire.Permissions
local Inventory = MIFire.Inventory

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

---@param source integer
---@param message string
---@param kind string|nil
local function notify(source, message, kind)
    if source == 0 then return end
    TriggerClientEvent('mi_fire:client:notify', source, message, kind or 'inform')
end

--- Tell a client to put a gear appearance on, take one off, or restore what was underneath.
---@param source integer
---@param action string 'apply' | 'restore'
---@param set table|nil
local function pushAppearance(source, action, set)
    TriggerClientEvent('mi_fire:client:gearAppearance', source, action, set)
end

--- Tell a client what it is wearing, so its target options offer the right thing.
--- The client uses this for menus only -- protection is still read from server state.
---@param source integer
local function pushGearState(source)
    local entry = State.getGear(source)
    local tier = MIFireGear.tiers[entry.tier]

    TriggerClientEvent('mi_fire:client:gearState', source,
        entry.tier, entry.tier ~= MIFireGear.defaultTier, entry.integrity,
        tier and tier.integrity or 0)
end

-- ---------------------------------------------------------------------------
-- Turnout
-- ---------------------------------------------------------------------------

--- What integrity this character's set was left at.
---
--- Keyed to the character and tier rather than the session, so changing clothes never
--- repairs a burned coat -- the gear is worn out, not the visit.
---@param source integer
---@param tierName string
---@return number
function Turnout.recallIntegrity(source, tierName)
    local tier = MIFireGear.tiers[tierName]
    if not tier then return 0.0 end

    local integrity = tier.integrity or 0.0
    local rules = MIFireGear.integrity

    -- On the session model, gear is fresh every time it goes on. On the others, it
    -- resumes where it was left.
    if rules.mode == MIFire.Integrity.Mode.SESSION then return integrity end
    if not rules.saveBetweenSessions or integrity <= 0 then return integrity end

    local stored = Inventory.getMetadata(source, 'turnout_' .. tierName,
        rules.metadataKey, nil)

    return tonumber(stored) or integrity
end

--- Put a gear tier on.
---@param source integer
---@param tierName string
---@return boolean ok
---@return string|nil reason
function Turnout.don(source, tierName)
    if Config.gearRequiresJob then
        local allowed, why = Permissions.requireFirefighter(source)
        if not allowed then return false, why end
    end

    local tier = MIFireGear.tiers[tierName]
    if not tier then return false, ('unknown gear tier "%s"'):format(tostring(tierName)) end

    local entry = State.getGear(source)
    if entry.tier == tierName then return false, 'you are already wearing that' end

    local integrity = Turnout.recallIntegrity(source, tierName)
    State.setGear(source, tierName, integrity)

    -- Per-character markings -- name tape, rank -- merged over the department set.
    -- Falls back to the plain tier appearance when nothing is stored for this character.
    local appearance = MIFire.GearAppearance and MIFire.GearAppearance.forPlayer(source, tierName)
        or tier.appearance

    if appearance then
        pushAppearance(source, 'apply', appearance)
    end

    pushGearState(source)
    Util.debug('turnout', '%s donned %s (integrity %.0f)', tostring(source), tierName, integrity)
    return true
end

--- Take gear off and go back to whatever was underneath.
---@param source integer
---@return boolean ok
---@return string|nil reason
function Turnout.doff(source)
    local entry = State.getGear(source)
    if entry.tier == MIFireGear.defaultTier then
        return false, 'you are not wearing any gear'
    end

    -- Write the wear back so a rough call costs something afterwards.
    Turnout.storeIntegrity(source, entry.tier, entry.integrity)

    State.clearGear(source)

    -- SCBA sits on a different slot, so doffing turnout must not silently strip it.
    -- Restore the base appearance, then put the SCBA back if it is still worn.
    pushAppearance(source, 'restore')

    local scba = State.getScba(source)
    if scba.worn then
        pushAppearance(source, 'apply',
            scba.active and MIFireScba.appearance.active or MIFireScba.appearance.inactive)
    end

    pushGearState(source)
    Util.debug('turnout', '%s doffed gear', tostring(source))
    return true
end


-- ---------------------------------------------------------------------------
-- Recognising gear from what is worn
-- ---------------------------------------------------------------------------

--- The client reports its clothing; this decides what that amounts to.
---
--- **Not gated on job by default.** Turnout gear is a coat. If a civilian gets hold of a
--- set it protects them, because that is what the coat does -- and a system that decided
--- otherwise would be telling a player the gear on their back is not really gear.
--- `Config.gearRequiresJob` restores the restriction for servers that want it.
---
--- The client is trusted about what it is wearing. That is a small surface: the worst a
--- forged report achieves is a civilian who is harder to set on fire, and obtaining the
--- clothing is the real gate.
---
--- Integrity is keyed to the character and the tier rather than to this session, so
--- changing clothes does not repair a burned coat and putting the same gear back on
--- resumes where it left off.
-- ---------------------------------------------------------------------------
-- Air, per character
-- ---------------------------------------------------------------------------

--- What each character's bottle was left at.
---
--- Needed because a set can now be recognised from clothing, and a bottle that refilled
--- itself every time someone re-equipped the skin would make air management optional. The
--- bank is the same idea as turnout integrity: the equipment is worn out, not the visit.
---
--- Written through to the SCBA item's metadata when the player actually has one, so a
--- carried bottle survives a restart. A set that exists only as clothing does not have an
--- item to write to, so it comes back full after a restart -- stated rather than hidden.
---@type table<string, number>
local airBank = {}

---@param source integer
---@return string
local function airKey(source)
    return MIFire.Framework.getIdentifier(source) or ('src:' .. source)
end

--- Air this character should get when a set goes on.
---@param source integer
---@return number seconds
local function recallAir(source)
    local capacity = MIFireScba.air.capacitySeconds

    if Inventory.has(source, MIFireScba.item) then
        local stored = Inventory.getMetadata(source, MIFireScba.item,
            MIFireScba.air.metadataKey, nil)
        if stored then return Util.clamp(tonumber(stored) or capacity, 0.0, capacity) end
    end

    local banked = airBank[airKey(source)]
    if banked then return Util.clamp(banked, 0.0, capacity) end

    -- No record at all: a first bottle, and it is full.
    return capacity
end

--- Remember where the bottle got to.
---@param source integer
---@param air number
local function bankAir(source, air)
    airBank[airKey(source)] = air

    if Inventory.has(source, MIFireScba.item) then
        Inventory.updateMetadata(source, MIFireScba.item, MIFireScba.air.metadataKey, air)
    end
end

Turnout.bankAir = bankAir

--- Recognise an SCBA set from what is on the ped.
---
--- Same rule as turnout (ADR 0004): the harness is the harness however it got there. This
--- only decides whether a set is **worn** -- the valve stays a deliberate act, so nobody
--- silently burns a bottle because they picked a skin.
---@param source integer
---@param worn table
---@param sex string|nil
local function reconcileScba(source, worn, sex)
    local recognised = MIFire.GearMatch.matchScba(worn, MIFireScba.appearance, sex)
    local scba = State.getScba(source)

    if recognised and not scba.worn then
        local air = recallAir(source)

        State.setScba(source, { worn = true, active = false, air = air, fromClothing = true })
        TriggerClientEvent('mi_fire:client:scbaState', source, false, air,
            MIFireScba.air.capacitySeconds)

        if air <= 0 then
            notify(source, 'That bottle is empty. Refill it at the rig.', 'error')
        else
            notify(source, ('SCBA on. %s of air. Open the valve to breathe it.')
                :format(Util.clock(air)), 'inform')
        end

        Util.debug('scba', '%s recognised as wearing SCBA with %.0fs air',
            tostring(source), air)

    elseif not recognised and scba.worn and scba.fromClothing then
        -- Only clear what clothing put on. A set donned at the rig is tracked by the rig,
        -- and taking the visual off should not silently discard it.
        bankAir(source, scba.air)
        State.clearScba(source)
        TriggerClientEvent('mi_fire:client:scbaState', source, false, nil, nil)
        Util.debug('scba', '%s took the SCBA off', tostring(source))
    end
end

RegisterNetEvent('mi_fire:server:reportGear', function(worn, sex)
    local source = source
    if type(worn) ~= 'table' then return end

    reconcileScba(source, worn, sex)

    local entry = State.getGear(source)

    if Config.gearRequiresJob
        and not MIFire.Framework.isFirefighter(source)
        and not Permissions.isAdmin(source) then
        -- Only reachable when a server has opted back into gear being a job perk.
        if entry.tier ~= MIFireGear.defaultTier then
            State.clearGear(source)
            pushGearState(source)
        end

        local scba = State.getScba(source)
        if scba.worn and scba.fromClothing then
            bankAir(source, scba.air)
            State.clearScba(source)
            TriggerClientEvent('mi_fire:client:scbaState', source, false, nil, nil)
        end
        return
    end

    local tierName, coverage = MIFire.GearMatch.identify(worn, MIFireGear.tiers, sex)

    if not tierName then
        if entry.tier ~= MIFireGear.defaultTier then
            State.clearGear(source)
            pushGearState(source)
            Util.debug('turnout', '%s is no longer wearing gear', tostring(source))
        end
        return
    end

    if entry.tier == tierName and math.abs((entry.coverage or 0) - coverage) < 0.01 then
        return
    end

    -- Integrity comes from what this character's set was left at, not from a fresh pool
    -- every time they get dressed.
    local integrity = Turnout.recallIntegrity(source, tierName)

    State.setGear(source, tierName, integrity)
    State.getGear(source).coverage = coverage

    pushGearState(source)
    Util.debug('turnout', '%s recognised as wearing %s (%.0f%% coverage, integrity %.0f)',
        tostring(source), tierName, coverage * 100, integrity)
end)


-- ---------------------------------------------------------------------------
-- Gear condition
-- ---------------------------------------------------------------------------

--- Repairs performed on this character's set, so repaired gear can lose a little ceiling
--- each time and eventually need replacing rather than being patched forever.
---@type table<string, integer>
local repairCounts = {}

---@param source integer
---@param tierName string
---@return string
local function repairKey(source, tierName)
    local identifier = MIFire.Framework.getIdentifier(source) or ('src:' .. source)
    return identifier .. ':' .. tierName
end

--- What condition someone's gear is in, in words.
---@param source integer
---@return table|nil { tier, condition, fraction, integrity, capacity, condemned }
function Turnout.condition(source)
    local entry = State.getGear(source)
    if entry.tier == MIFireGear.defaultTier then return nil end

    local tier = MIFireGear.tiers[entry.tier]
    local capacity = tier and tier.integrity or 0

    local condition, fraction = MIFire.Integrity.condition(
        entry.integrity, capacity, MIFireGear.integrity)

    return {
        tier = entry.tier,
        label = tier and tier.label or entry.tier,
        condition = condition,
        fraction = fraction,
        integrity = entry.integrity,
        capacity = capacity,
        condemned = MIFire.Integrity.isCondemned(entry.integrity, capacity, MIFireGear.integrity),
    }
end

--- Repair the set someone is wearing.
---
--- Repaired gear does not come back as new -- each repair costs a little of the ceiling, so
--- a set that has been through several fires is eventually replaced rather than patched
--- indefinitely. That is what happens to real turnout.
---@param source integer
---@return boolean ok
---@return string|nil reason
---@return number|nil seconds How long it should take.
function Turnout.repair(source)
    local entry = State.getGear(source)
    if entry.tier == MIFireGear.defaultTier then
        return false, 'you are not wearing any gear'
    end

    local tier = MIFireGear.tiers[entry.tier]
    local capacity = tier and tier.integrity or 0

    local ok, why = MIFire.Integrity.canRepair(entry.integrity, capacity, MIFireGear.integrity)
    if not ok then return false, why end

    local key = repairKey(source, entry.tier)
    repairCounts[key] = (repairCounts[key] or 0) + 1

    local restored = MIFire.Integrity.afterRepair(capacity, repairCounts[key], MIFireGear.integrity)

    entry.integrity = restored
    Turnout.storeIntegrity(source, entry.tier, restored)
    pushGearState(source)

    local condition = MIFire.Integrity.condition(restored, capacity, MIFireGear.integrity)
    notify(source, ('Gear serviced -- %s'):format(condition), 'success')

    Util.debug('turnout', '%s repaired %s to %.0f (repair #%d)',
        tostring(source), entry.tier, restored, repairCounts[key])

    return true
end

--- Draw a fresh set. Fast, and the only option once a set is condemned.
---@param source integer
---@param tierName string|nil Defaults to what they are wearing.
---@return boolean ok
---@return string|nil reason
function Turnout.replace(source, tierName)
    tierName = tierName or State.getGear(source).tier
    local tier = MIFireGear.tiers[tierName]

    if not tier or tierName == MIFireGear.defaultTier then
        return false, 'no gear to replace'
    end

    local key = repairKey(source, tierName)
    repairCounts[key] = 0

    local capacity = tier.integrity or 0
    State.setGear(source, tierName, capacity)
    Turnout.storeIntegrity(source, tierName, capacity)
    pushGearState(source)

    notify(source, 'Fresh set drawn', 'success')
    return true
end

--- Write integrity somewhere it survives, per the configured model.
---@param source integer
---@param tierName string
---@param integrity number
function Turnout.storeIntegrity(source, tierName, integrity)
    if not MIFireGear.integrity.saveBetweenSessions then return end
    if MIFireGear.integrity.mode == MIFire.Integrity.Mode.SESSION then return end

    Inventory.updateMetadata(source, 'turnout_' .. tierName,
        MIFireGear.integrity.metadataKey, integrity)
end

-- ---------------------------------------------------------------------------
-- Recovery
-- ---------------------------------------------------------------------------

--- On the 'regenerate' model, gear recovers once its wearer is clear of the fire.
---
--- Driven off the exposure module's record of when this player was last in flame, so
--- "clear of the fire" means what it says rather than "not currently taking damage".
CreateThread(function()
    while not MIFire.ready do Wait(250) end

    if MIFireGear.integrity.mode ~= MIFire.Integrity.Mode.REGENERATE then return end

    local interval = 2000
    local dt = interval / 1000.0

    while true do
        Wait(interval)

        for _, playerId in ipairs(GetPlayers()) do
            local source = tonumber(playerId)
            local entry = source and State.getGear(source)

            if entry and entry.tier ~= MIFireGear.defaultTier then
                local tier = MIFireGear.tiers[entry.tier]
                local capacity = tier and tier.integrity or 0

                if capacity > 0 and entry.integrity < capacity then
                    local clearFor = MIFire.ExposureServer
                        and MIFire.ExposureServer.secondsSinceFlame(source) or math.huge

                    local recovered = MIFire.Integrity.recover(
                        entry.integrity, capacity, clearFor, dt, MIFireGear.integrity)

                    if recovered > entry.integrity then
                        entry.integrity = recovered
                        pushGearState(source)
                    end
                end
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Transports
-- ---------------------------------------------------------------------------

RegisterNetEvent('mi_fire:server:repairGear', function(coords)
    local source = source
    if coords and not Permissions.isNear(source, coords, 6.0) then
        return notify(source, 'you are not at the gear room', 'error')
    end

    local ok, why = Turnout.repair(source)
    if not ok and why then notify(source, why, 'error') end
end)

RegisterNetEvent('mi_fire:server:replaceGear', function(coords)
    local source = source
    if coords and not Permissions.isNear(source, coords, 6.0) then
        return notify(source, 'you are not at a rack', 'error')
    end

    -- Drawing a fresh set is department property, so this one is job-gated even though
    -- wearing gear is not.
    local allowed, why = Permissions.requireFirefighter(source)
    if not allowed then return notify(source, why or 'not allowed', 'error') end

    local ok, reason = Turnout.replace(source)
    if not ok and reason then notify(source, reason, 'error') end
end)

exports('GetGearCondition', function(source) return Turnout.condition(source) end)
exports('RepairGear', function(source) return Turnout.repair(source) end)
exports('ReplaceGear', function(source, tier) return Turnout.replace(source, tier) end)

-- ---------------------------------------------------------------------------
-- SCBA
-- ---------------------------------------------------------------------------

--- Put an SCBA set on. Does not open the air -- that is `Turnout.setScbaActive`.
---@param source integer
---@param opts table|nil { fromRack = boolean, air = number }
---@return boolean ok
---@return string|nil reason
function Turnout.donScba(source, opts)
    opts = opts or {}

    -- Taking a set off department property is department business; wearing one you already
    -- have is not. So the job check lives on the rack rather than here.
    if opts.fromRack or Config.gearRequiresJob then
        local allowed, why = Permissions.requireFirefighter(source)
        if not allowed then return false, why end
    end

    local scba = State.getScba(source)
    if scba.worn then return false, 'you are already wearing a set' end

    local air

    if opts.fromRack then
        -- A rack hands out a full bottle. Nothing is taken from inventory, because the
        -- rack is where bottles live.
        air = MIFireScba.air.capacitySeconds
    else
        -- Worn from a carried bottle: the item is the source of truth for its pressure.
        if not Inventory.has(source, MIFireScba.item) then
            return false, 'you have no SCBA set'
        end
        air = tonumber(Inventory.getMetadata(source, MIFireScba.item,
            MIFireScba.air.metadataKey, MIFireScba.air.capacitySeconds))
    end

    air = Util.clamp(tonumber(opts.air) or air, 0.0, MIFireScba.air.capacitySeconds)

    State.setScba(source, { worn = true, active = false, air = air, fromRack = opts.fromRack })
    pushAppearance(source, 'apply', MIFireScba.appearance.inactive)

    TriggerClientEvent('mi_fire:client:scbaState', source, false, air,
        MIFireScba.air.capacitySeconds)

    local minutes = air / 60.0
    notify(source, ('SCBA on. %.0f minutes of air. Open the valve to breathe it.'):format(minutes),
        'success')

    Util.debug('scba', '%s donned SCBA with %.0fs air', tostring(source), air)
    return true
end

--- Take an SCBA set off. Its remaining air goes back to the item, or to the rack.
---@param source integer
---@param opts table|nil { toRack = boolean }
---@return boolean ok
---@return string|nil reason
function Turnout.doffScba(source, opts)
    opts = opts or {}

    local scba = State.getScba(source)
    if not scba.worn then return false, 'you are not wearing a set' end

    -- Racking a bottle refills it, which is the whole reason to go back to the rig.
    if opts.toRack then
        bankAir(source, MIFireScba.air.capacitySeconds)
    else
        bankAir(source, scba.air)
    end

    State.clearScba(source)

    -- Restoring wipes everything, so put the turnout back on if it is still worn.
    pushAppearance(source, 'restore')

    local gearEntry = State.getGear(source)
    if gearEntry.tier ~= MIFireGear.defaultTier then
        local appearance = MIFire.GearAppearance
            and MIFire.GearAppearance.forPlayer(source, gearEntry.tier)
        if appearance then pushAppearance(source, 'apply', appearance) end
    end

    TriggerClientEvent('mi_fire:client:scbaState', source, false, nil,
        MIFireScba.air.capacitySeconds)
    notify(source, opts.toRack and 'SCBA racked and refilled' or 'SCBA off', 'inform')
    return true
end

--- Open or close the air valve.
---
--- This is the line between "carrying a set" and "protected from smoke". Inactive uses no
--- air and gives nothing; active gives complete smoke immunity and burns the bottle.
---@param source integer
---@param active boolean
---@return boolean ok
---@return string|nil reason
function Turnout.setScbaActive(source, active)
    local scba = State.getScba(source)
    if not scba.worn then return false, 'you are not wearing a set' end

    if active and scba.air <= 0 then
        return false, 'the bottle is empty'
    end

    if scba.active == active then
        return false, active and 'the valve is already open' or 'the valve is already shut'
    end

    scba.active = active
    pushAppearance(source, 'apply',
        active and MIFireScba.appearance.active or MIFireScba.appearance.inactive)

    if active then
        notify(source, ('Breathing bottle air -- %s remaining'):format(Util.clock(scba.air)), 'inform')
    else
        notify(source, 'Air valve shut', 'inform')
    end

    TriggerClientEvent('mi_fire:client:scbaState', source, scba.active, scba.air,
        MIFireScba.air.capacitySeconds)

    Util.debug('scba', '%s set air %s', tostring(source), tostring(active))
    return true
end

--- Refill a worn or carried set.
---@param source integer
---@param seconds number|nil How much air to add; nil fills it.
---@return boolean ok
---@return string|nil reason
function Turnout.refillScba(source, seconds)
    local capacity = MIFireScba.air.capacitySeconds
    local scba = State.getScba(source)

    if scba.worn then
        if scba.air >= capacity then return false, 'the bottle is already full' end
        scba.air = Util.clamp(scba.air + (seconds or capacity), 0.0, capacity)
        bankAir(source, scba.air)
        TriggerClientEvent('mi_fire:client:scbaState', source, scba.active, scba.air, capacity)
        notify(source, ('Bottle filled to %s'):format(Util.clock(scba.air)), 'success')
        return true
    end

    if not Inventory.has(source, MIFireScba.item) then
        return false, 'you have no SCBA set'
    end

    local air = tonumber(Inventory.getMetadata(source, MIFireScba.item,
        MIFireScba.air.metadataKey, 0)) or 0
    if air >= capacity then return false, 'the bottle is already full' end

    Inventory.updateMetadata(source, MIFireScba.item, MIFireScba.air.metadataKey,
        Util.clamp(air + (seconds or capacity), 0.0, capacity))
    notify(source, 'Bottle filled', 'success')
    return true
end

-- ---------------------------------------------------------------------------
-- Air consumption
-- ---------------------------------------------------------------------------

--- Burn air for one tick.
---
--- Exertion matters far more than time. A rated thirty-minute bottle gives closer to
--- fifteen under work, and that gap is the point -- air management is a skill, not a timer.
---@param source integer
---@param dt number Seconds.
---@param exertion string|nil Key from `MIFireScba.air.exertion`.
---@param inSmoke boolean|nil
local function consumeAir(source, dt, exertion, inSmoke)
    local scba = State.getScba(source)
    if not scba.worn or not scba.active then return end

    local rate = MIFireScba.air.baseRate
        * (MIFireScba.air.exertion[exertion or 'idle'] or 1.0)
        * (inSmoke and MIFireScba.air.smokeMultiplier or 1.0)

    local before = scba.air
    scba.air = math.max(0.0, scba.air - rate * dt)

    local capacity = MIFireScba.air.capacitySeconds
    local wasAbove = function(fraction) return before > capacity * fraction end
    local nowBelow = function(fraction) return scba.air <= capacity * fraction end

    -- One warning per threshold crossing, not one per tick.
    if wasAbove(MIFireScba.air.criticalAt) and nowBelow(MIFireScba.air.criticalAt) then
        notify(source, 'AIR CRITICAL -- get out now', 'error')
    elseif wasAbove(MIFireScba.air.lowAirAt) and nowBelow(MIFireScba.air.lowAirAt) then
        notify(source, 'Low air alarm -- begin your exit', 'error')
    elseif wasAbove(MIFireScba.air.warnAt) and nowBelow(MIFireScba.air.warnAt) then
        notify(source, ('Half a bottle left -- %s'):format(Util.clock(scba.air)), 'inform')
    end

    if scba.air <= 0 and scba.active then
        scba.active = false
        pushAppearance(source, 'apply', MIFireScba.appearance.inactive)
        notify(source, 'Out of air. Smoke is no longer being kept out.', 'error')
    end

    -- Bank as it is spent. A set recognised from clothing has no item behind it, so
    -- without this the bottle would refill itself every time the skin came back on.
    bankAir(source, scba.air)

    TriggerClientEvent('mi_fire:client:scbaState', source, scba.active, scba.air, capacity)
end

--- Clients report their own exertion, since only they know whether they are sprinting.
--- Air is still decremented server-side, so a client claiming to be idle forever only
--- changes the rate, never the fact that the bottle empties.
RegisterNetEvent('mi_fire:server:reportExertion', function(exertion, inSmoke)
    local source = source
    if type(exertion) ~= 'string' then exertion = 'idle' end
    if not MIFireScba.air.exertion[exertion] then exertion = 'idle' end

    local scba = State.getScba(source)
    scba.exertion = exertion
    scba.inSmoke = inSmoke == true
end)

CreateThread(function()
    while not MIFire.ready do Wait(250) end

    local interval = 1000
    local dt = interval / 1000.0

    while true do
        Wait(interval)

        for _, entry in ipairs(MIFire.Framework.getOnDutyFirefighters()) do
            local scba = State.getScba(entry.source)
            if scba.worn and scba.active then
                consumeAir(entry.source, dt, scba.exertion, scba.inSmoke)
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Transports
-- ---------------------------------------------------------------------------

--- Every one of these is a thin wrapper. The gates live in the services above.

local function respond(source, ok, reason)
    if not ok and reason then notify(source, reason, 'error') end
    return ok
end

RegisterNetEvent('mi_fire:server:donTurnout', function(tierName, coords)
    local source = source
    -- Position is re-checked here: a client saying it is at an apparatus is a request.
    if coords and not Permissions.isNear(source, coords, 6.0) then
        return notify(source, 'you are not at the apparatus', 'error')
    end
    respond(source, Turnout.don(source, tierName))
end)

RegisterNetEvent('mi_fire:server:doffTurnout', function()
    local source = source
    respond(source, Turnout.doff(source))
end)

RegisterNetEvent('mi_fire:server:donScba', function(opts)
    local source = source
    opts = type(opts) == 'table' and opts or {}

    if opts.coords and not Permissions.isNear(source, opts.coords, 6.0) then
        return notify(source, 'you are not at the rack', 'error')
    end

    -- Only a real rack hands out a free bottle. A client cannot claim one.
    local fromRack = opts.fromRack == true and opts.coords ~= nil
    local ok, reason = Turnout.donScba(source, { fromRack = fromRack })
    respond(source, ok, reason)
end)

RegisterNetEvent('mi_fire:server:doffScba', function(opts)
    local source = source
    opts = type(opts) == 'table' and opts or {}
    local toRack = opts.toRack == true and opts.coords ~= nil
        and Permissions.isNear(source, opts.coords, 6.0)
    local ok, reason = Turnout.doffScba(source, { toRack = toRack })
    respond(source, ok, reason)
end)

RegisterNetEvent('mi_fire:server:toggleScba', function()
    local source = source
    local scba = State.getScba(source)
    local ok, reason = Turnout.setScbaActive(source, not scba.active)
    respond(source, ok, reason)
end)

RegisterNetEvent('mi_fire:server:refillScba', function(coords)
    local source = source
    if coords and not Permissions.isNear(source, coords, 6.0) then
        return notify(source, 'you are not at a cascade', 'error')
    end
    local ok, reason = Turnout.refillScba(source)
    respond(source, ok, reason)
end)

--- Using the item is the third route in, alongside a station rack and an apparatus.
---
--- Wired as an ox_inventory item export rather than `registerUsableItem`, because most
--- servers already have an SCBA item pointing somewhere and repointing one string is a
--- smaller change than redefining the item:
---
---     ['scba'] = { label = 'SCBA', weight = 220,
---                  server = { export = 'mi_fire.useScba' } },
---
--- ox_inventory calls this as `export(nil, event, item, inventory, slot)`, so the first
--- argument we see is the event. `inventory.id` is the player.
---@param event string 'usingItem' | 'usedItem' | 'buying'
---@param item table
---@param inventory table
---@return boolean|nil false cancels the use
exports('useScba', function(event, item, inventory)
    if event ~= 'usingItem' then return end

    local source = inventory and inventory.id
    if not source then return false end

    local scba = State.getScba(source)
    local ok, reason

    if scba.worn then
        ok, reason = Turnout.doffScba(source)
    else
        ok, reason = Turnout.donScba(source, { fromRack = false })
    end

    respond(source, ok, reason)

    -- Returning false stops ox_inventory consuming or animating the item when the action
    -- did not happen, so a refused use does not look like a successful one.
    if not ok then return false end
end)

-- ---------------------------------------------------------------------------
-- Cleanup
-- ---------------------------------------------------------------------------

AddEventHandler('playerDropped', function()
    -- Air is written back so a bottle does not silently refill by logging out.
    local scba = State.getScba(source)
    if scba.worn and not scba.fromRack then
        Inventory.updateMetadata(source, MIFireScba.item, MIFireScba.air.metadataKey, scba.air)
    end
end)

--- Re-send gear state to a client.
---
--- The exposure module owns the burning-through, so it is the one that knows integrity
--- moved. Without this the client's copy stayed at whatever it was when the coat went on,
--- and the repair and replace options -- which are gated on integrity being below full --
--- never appeared however hard the gear was worked.
---@param source integer
function Turnout.pushState(source)
    pushGearState(source)
end

MIFire.Turnout = Turnout

return Turnout
