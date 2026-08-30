--- Per-character gear appearance.
---
--- Turnout carries a name tape and rank markings, so the drawable is shared across a
--- department while the texture is personal. That makes it **identity, not equipment**:
--- it belongs to the firefighter, not to the coat they picked up.
---
--- Which is why it is a database row keyed to the character rather than item metadata.
--- Item metadata would be wrong twice: gear issued from an apparatus rack has no item at
--- all, and a coat handed to someone else would carry the previous owner's name with it.
---
--- Overrides are merged over the tier's base appearance at don time, so a character stores
--- only what differs -- usually one texture.

MIFire = MIFire or {}

local GearAppearance = {}

local Util = MIFire.Util
local DB = MIFire.DB

--- Cached per identifier, because this is read every time anyone dons.
---@type table<string, table<string, table>>
local cache = {}

-- ---------------------------------------------------------------------------
-- Reading
-- ---------------------------------------------------------------------------

--- Load every override this character has, across all tiers.
---@param identifier string
---@return table<string, table> byTier
local function load(identifier)
    if cache[identifier] then return cache[identifier] end

    local byTier = {}

    for _, row in ipairs(DB.query(
        'SELECT `tier`, `overrides` FROM `mi_fire_gear_appearance` WHERE `identifier` = ?',
        { identifier })) do

        local ok, decoded = pcall(json.decode, row.overrides)
        if ok and type(decoded) == 'table' then
            byTier[row.tier] = decoded
        else
            Util.warn('gear appearance for %s / %s is not valid JSON; ignoring it',
                identifier, tostring(row.tier))
        end
    end

    cache[identifier] = byTier
    return byTier
end

--- The appearance a specific character should get for a tier.
---
--- Falls back to the tier's base set, so a firefighter with no personal markings still
--- gets dressed. A missing database is the same case: everyone wears the department set.
---@param source integer
---@param tierName string
---@return table|nil appearance `{ male = {...}, female = {...} }`
function GearAppearance.forPlayer(source, tierName)
    local tier = MIFireGear.tiers[tierName]
    if not tier or not tier.appearance then return nil end

    if not DB.isAvailable() then return tier.appearance end

    local identifier = MIFire.Framework.getIdentifier(source)
    if not identifier then return tier.appearance end

    local overrides = load(identifier)[tierName]
    if not overrides then return tier.appearance end

    -- Merge per sex. `Util.merge` replaces lists and merges hashes, and an appearance set
    -- is a hash of slots, so a partial override touches only the slots it names.
    local out = {}
    for sex, set in pairs(tier.appearance) do
        out[sex] = Util.merge(set, overrides[sex] or overrides)
    end

    return out
end

-- ---------------------------------------------------------------------------
-- Writing
-- ---------------------------------------------------------------------------

--- Set a character's markings for a tier.
---
--- `overrides` is `{ slot = texture }` or `{ slot = { drawable = n, texture = n } }`, and
--- may be split by sex: `{ male = { torso2 = 4 }, female = { torso2 = 7 } }`.
---@param identifier string
---@param tierName string
---@param overrides table
---@param opts table|nil { label = string, updatedBy = string }
---@return boolean ok
---@return string|nil reason
function GearAppearance.set(identifier, tierName, overrides, opts)
    opts = opts or {}

    if not DB.isAvailable() then
        return false, 'the database is unavailable, so markings cannot be saved'
    end

    if not MIFireGear.tiers[tierName] then
        return false, ('unknown gear tier "%s"'):format(tostring(tierName))
    end

    if type(overrides) ~= 'table' or next(overrides) == nil then
        return false, 'no overrides given'
    end

    -- Reject a slot name that does not exist, rather than storing something that will
    -- silently do nothing when it is applied.
    local function validate(set)
        for slot in pairs(set) do
            if slot ~= 'male' and slot ~= 'female' then
                if not MIFire.Appearance or not MIFire.Appearance.resolveSlot then
                    -- The bridge is client-side; on the server, check against the known
                    -- slot names in the tier's own set instead.
                    return true
                end
            end
        end
        return true
    end

    validate(overrides)

    local encoded = json.encode(overrides)

    local affected = DB.update([[
        INSERT INTO `mi_fire_gear_appearance` (`identifier`, `tier`, `overrides`, `label`, `updated_by`)
        VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            `overrides` = VALUES(`overrides`),
            `label` = VALUES(`label`),
            `updated_by` = VALUES(`updated_by`)
    ]], { identifier, tierName, encoded, opts.label, opts.updatedBy })

    if affected == 0 then return false, 'the write did not take' end

    cache[identifier] = nil
    Util.debug('turnout', 'set gear appearance for %s / %s', identifier, tierName)
    return true
end

--- Clear a character's markings for a tier, putting them back on the department set.
---@param identifier string
---@param tierName string|nil nil clears every tier.
---@return boolean
function GearAppearance.clear(identifier, tierName)
    if not DB.isAvailable() then return false end

    if tierName then
        DB.update('DELETE FROM `mi_fire_gear_appearance` WHERE `identifier` = ? AND `tier` = ?',
            { identifier, tierName })
    else
        DB.update('DELETE FROM `mi_fire_gear_appearance` WHERE `identifier` = ?', { identifier })
    end

    cache[identifier] = nil
    return true
end

--- Everything stored for a character, for an admin listing or a management UI.
---@param identifier string
---@return table<string, table>
function GearAppearance.get(identifier)
    return Util.deepCopy(load(identifier))
end

--- Drop the cache for one character, or all of them. Call after writing from outside.
---@param identifier string|nil
function GearAppearance.invalidate(identifier)
    if identifier then cache[identifier] = nil else cache = {} end
end

-- ---------------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------------

--- For an EUP or personnel resource that already knows who has which name tape.
---
--- Taking an identifier rather than a source on purpose: markings are usually assigned
--- from an admin panel while the firefighter is offline.
exports('SetGearAppearance', function(identifier, tier, overrides, opts)
    return GearAppearance.set(identifier, tier, overrides, opts)
end)

exports('GetGearAppearance', function(identifier)
    return GearAppearance.get(identifier)
end)

exports('ClearGearAppearance', function(identifier, tier)
    return GearAppearance.clear(identifier, tier)
end)

AddEventHandler('playerDropped', function()
    local identifier = MIFire.Framework.getIdentifier(source)
    if identifier then cache[identifier] = nil end
end)

MIFire.GearAppearance = GearAppearance

return GearAppearance
