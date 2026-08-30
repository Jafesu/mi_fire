--- Fire class resolution.
---
--- `config/fire_classes.lua` stores a base table plus per-class overrides, so a class only
--- writes down what differs. This resolves the two into the table the engine actually
--- reads, and caches the result because it is read every tick for every node.
---
--- Pure. No natives, no state beyond the cache.

MIFire = MIFire or {}

local FireClass = {}
local resolved = {}

--- Merge a class over the base and cache it.
---
--- `variant` picks a sub-table on the class -- `electricVariant` on a vehicle fire, for
--- example -- and layers it on top. That is how an EV burns like a car that will not stay
--- out without needing its own class.
---
---@param className string Key from `MIFireClasses.classes`.
---@param variant string|nil Sub-table on the class to layer on.
---@return table|nil class Nil when the class does not exist.
function FireClass.resolve(className, variant)
    if type(className) ~= 'string' then return nil end

    local cacheKey = variant and (className .. ':' .. variant) or className
    if resolved[cacheKey] then return resolved[cacheKey] end

    local classes = rawget(_G, 'MIFireClasses')
    if not classes or type(classes.classes) ~= 'table' then return nil end

    local override = classes.classes[className]
    if not override then return nil end

    local merged = MIFire.Util.merge(classes.base or {}, override)

    if variant and type(override[variant]) == 'table' then
        merged = MIFire.Util.merge(merged, override[variant])
    end

    -- Variant sub-tables are configuration, not runtime fields. Strip them so a node
    -- carrying a resolved class does not drag a copy of every variant around with it.
    for key, value in pairs(merged) do
        if type(value) == 'table' and key:match('Variant$') then
            merged[key] = nil
        end
    end

    merged.name = className
    merged.variant = variant

    resolved[cacheKey] = merged
    return merged
end

--- Drop the cache. Called when configuration is reloaded.
function FireClass.clearCache()
    resolved = {}
end

--- Every class name that exists.
---@return string[]
function FireClass.names()
    local classes = rawget(_G, 'MIFireClasses')
    if not classes or type(classes.classes) ~= 'table' then return {} end

    local out = {}
    for name in pairs(classes.classes) do out[#out + 1] = name end
    table.sort(out)
    return out
end

---@param className string
---@return boolean
function FireClass.exists(className)
    local classes = rawget(_G, 'MIFireClasses')
    return classes ~= nil and type(classes.classes) == 'table'
        and classes.classes[className] ~= nil
end

--- Pick a fire class for a district, weighted by what can burn there.
---@param district table A district from `MIFireZones.districts`.
---@return string|nil className
function FireClass.pickForDistrict(district)
    if type(district) ~= 'table' or type(district.fireClasses) ~= 'table' then return nil end
    return MIFire.Util.weightedPick(district.fireClasses)
end

MIFire.FireClass = FireClass

return FireClass
