--- Appearance bridge.
---
--- Turnout gear and SCBA are clothing swaps, but the *protection* is never read from
--- clothing. The active tier lives in server state; this file only makes the player look
--- right. If resistance came from what a player is wearing, anyone with a clothing menu
--- could grant themselves fire protection.
---
--- Slot names follow illenium-appearance's own vocabulary (`torso2`, `arms`, `t-shirt`,
--- `hat`...) so a config written here reads the same as one written there.
---
--- The distinction that matters and is easy to get wrong: a helmet is a **prop**, not a
--- component. They go through different natives with different key names, and putting a
--- helmet in the component list silently does nothing.

MIFire = MIFire or {}

local Appearance = { available = false, resource = 'illenium-appearance' }

--- Ped components, by illenium's slot name.
local COMPONENTS = {
    face = 0, mask = 1, hair = 2, arms = 3, pants = 4, bag = 5,
    shoes = 6, accessory = 7, ['t-shirt'] = 8, vest = 9, decals = 10, torso2 = 11,
}

--- Ped props. Separate natives, separate key name (`prop_id`, not `component_id`).
local PROPS = {
    hat = 0, glass = 1, ear = 2, watch = 6, bracelet = 7,
}

--- Appearance captured before the first piece of gear went on, so doffing can restore it.
---@type table|nil
local stored = nil

local function ensure()
    if Appearance.available then return true end
    Appearance.available = GetResourceState(Appearance.resource) == 'started'
    if not Appearance.available then
        MIFire.Util.warn('%s is not started; gear will change protection but not appearance',
            Appearance.resource)
    end
    return Appearance.available
end

-- ---------------------------------------------------------------------------
-- Slot resolution
-- ---------------------------------------------------------------------------

--- Is this slot known, and is it a component or a prop?
---@param slot string
---@return string|nil kind 'component' | 'prop'
---@return integer|nil id
function Appearance.resolveSlot(slot)
    if COMPONENTS[slot] then return 'component', COMPONENTS[slot] end
    if PROPS[slot] then return 'prop', PROPS[slot] end
    return nil
end

--- Split a `{ slot = drawable }` set into the two shapes illenium wants.
---
--- A value may be a plain drawable number, or `{ drawable = n, texture = n }` when a
--- texture other than 0 is needed. `-1` clears the slot, which is how a helmet comes off.
---@param set table
---@return table components
---@return table props
---@return string[] unknown Slot names that are not real, for reporting rather than silence.
function Appearance.split(set)
    local components, props, unknown = {}, {}, {}

    for slot, value in pairs(set or {}) do
        local drawable, texture

        if type(value) == 'table' then
            drawable, texture = tonumber(value.drawable), tonumber(value.texture) or 0
        else
            drawable, texture = tonumber(value), 0
        end

        if drawable then
            local kind, id = Appearance.resolveSlot(slot)

            if kind == 'component' then
                components[#components + 1] =
                    { component_id = id, drawable = drawable, texture = texture }
            elseif kind == 'prop' then
                props[#props + 1] =
                    { prop_id = id, drawable = drawable, texture = texture }
            else
                unknown[#unknown + 1] = slot
            end
        end
    end

    return components, props, unknown
end

-- ---------------------------------------------------------------------------
-- Applying
-- ---------------------------------------------------------------------------

--- Capture what the player currently looks like.
---@return table|nil
function Appearance.capture()
    if not ensure() then return nil end
    local ok, appearance = pcall(function()
        return exports[Appearance.resource]:getPedAppearance(cache.ped)
    end)
    if not ok then
        MIFire.Util.warn('could not read appearance: %s', tostring(appearance))
        return nil
    end
    return appearance
end

--- Apply a `{ slot = drawable }` set.
---@param set table
---@return boolean applied
function Appearance.apply(set)
    if not ensure() or type(set) ~= 'table' then return false end

    local components, props, unknown = Appearance.split(set)

    for i = 1, #unknown do
        MIFire.Util.warn('unknown appearance slot "%s"; nothing will change for it. Valid: %s',
            unknown[i], 'hat, mask, arms, pants, bag, shoes, accessory, t-shirt, vest, decals, torso2, glass, ear')
    end

    if #components == 0 and #props == 0 then return false end

    local ok, err = pcall(function()
        if #components > 0 then
            exports[Appearance.resource]:setPedComponents(cache.ped, components)
        end
        if #props > 0 then
            exports[Appearance.resource]:setPedProps(cache.ped, props)
        end
    end)

    if not ok then
        MIFire.Util.warn('could not apply appearance: %s', tostring(err))
        return false
    end

    return true
end

--- Apply the right variant of a set for this ped's sex.
---@param set table `{ male = {...}, female = {...} }`
---@return boolean
function Appearance.applyForSex(set)
    if type(set) ~= 'table' then return false end
    local sex = IsPedMale(cache.ped) and 'male' or 'female'
    return Appearance.apply(set[sex] or set.male)
end

-- ---------------------------------------------------------------------------
-- Remembering what was underneath
-- ---------------------------------------------------------------------------

--- Remember the player's own clothing, once.
---
--- Only the *first* call stores anything. Donning SCBA over turnout must not overwrite the
--- memory of civilian clothes with a picture of the player already in turnout -- that is
--- how someone ends up permanently dressed as a firefighter.
---@return boolean stored
function Appearance.remember()
    if stored then return false end
    stored = Appearance.capture()
    return stored ~= nil
end

--- Put the player back in what they were wearing before any gear went on.
---@return boolean
function Appearance.restore()
    if not stored then return false end

    if not ensure() then
        stored = nil
        return false
    end

    local ok, err = pcall(function()
        exports[Appearance.resource]:setPedAppearance(cache.ped, stored)
    end)

    stored = nil

    if not ok then
        MIFire.Util.warn('could not restore appearance: %s', tostring(err))
        return false
    end

    return true
end

---@return boolean
function Appearance.hasStored()
    return stored ~= nil
end

--- Hand the stored appearance to the server for persistence across a disconnect, and take
--- it back on reconnect. Someone who logs out in gear should not come back in their
--- underwear, and should not be stuck in turnout forever either.
---@return table|nil
function Appearance.getStored()
    return stored
end

---@param appearance table|nil
function Appearance.setStored(appearance)
    stored = appearance
end

MIFire.Appearance = Appearance

return Appearance
