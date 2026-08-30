--- Appearance bridge.
---
--- Turnout gear is a clothing swap, but the *protection* is never read from clothing.
--- The active tier lives in server state; this file only makes the player look right.
---
--- That separation matters: if resistance came from what a player is wearing, anyone
--- with a clothing menu could grant themselves fire protection. Here, wearing a turnout
--- skin gets you a look and nothing else.

MIFire = MIFire or {}

local Appearance = { available = false, resource = 'illenium-appearance' }

--- Appearance stored before donning, so doffing can put it back.
---@type table|nil
local stored = nil

local function ensure()
    if Appearance.available then return true end
    Appearance.available = GetResourceState(Appearance.resource) == 'started'
    if not Appearance.available then
        MIFire.Util.warn('%s is not started; turnout gear will change protection but not appearance',
            Appearance.resource)
    end
    return Appearance.available
end

-- ---------------------------------------------------------------------------

--- Capture what the player currently looks like.
--- Returns nil when the appearance resource is missing, which callers treat as
--- "skip the visual change", not as an error.
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

--- Apply a tier's component set.
---
--- `components` is `{ tops = { drawable, texture }, legs = { ... }, ... }` as authored in
--- `config/gear.lua`. A drawable of -1 means "leave this slot alone", so a partial set
--- (a coat but not boots) works without having to specify everything.
---@param components table
---@return boolean applied
function Appearance.applyComponents(components)
    if not ensure() or type(components) ~= 'table' then return false end

    local payload = {}
    for slot, value in pairs(components) do
        if type(value) == 'table' and (value.drawable or -1) >= 0 then
            payload[slot] = { drawable = value.drawable, texture = value.texture or 0 }
        end
    end

    if next(payload) == nil then return false end

    local ok, err = pcall(function()
        exports[Appearance.resource]:setPedComponents(cache.ped, payload)
    end)

    if not ok then
        MIFire.Util.warn('could not apply components: %s', tostring(err))
        return false
    end

    return true
end

--- Don a gear tier's appearance, remembering what was there first.
---
--- Only the *first* don stores anything. Donning SCBA over turnout must not overwrite
--- the memory of the player's civilian clothes with a picture of them in turnout.
---@param tier table A tier from `config/gear.lua`.
---@param sex string|nil 'male' or 'female'; detected from the ped model when omitted.
---@return boolean
function Appearance.don(tier, sex)
    if not tier or not tier.appearance then return false end

    if not stored then
        stored = Appearance.capture()
    end

    sex = sex or (IsPedMale(cache.ped) and 'male' or 'female')
    local set = tier.appearance[sex] or tier.appearance.male
    if not set then return false end

    return Appearance.applyComponents(set)
end

--- Put the player back in what they were wearing.
---@return boolean
function Appearance.doff()
    if not ensure() then
        stored = nil
        return false
    end

    if not stored then return false end

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

--- Whether we are currently holding a stored appearance to return to.
---@return boolean
function Appearance.hasStored()
    return stored ~= nil
end

--- Hand the stored appearance to the server for persistence across a disconnect.
--- Someone who logs out in gear should not come back in their underwear.
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
