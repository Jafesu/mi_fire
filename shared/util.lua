--- Small shared helpers.
---
--- Pure where possible, so most of this is testable outside FiveM too. Anything that
--- needs a game native belongs in a client or server module, not here.

MIFire = MIFire or {}

local Util = {}

-- ---------------------------------------------------------------------------
-- Numbers
-- ---------------------------------------------------------------------------

---@param value number
---@param min number
---@param max number
---@return number
function Util.clamp(value, min, max)
    value = tonumber(value) or 0
    if value < min then return min end
    if value > max then return max end
    return value
end

---@param a number
---@param b number
---@param t number 0-1
---@return number
function Util.lerp(a, b, t)
    return a + (b - a) * Util.clamp(t, 0.0, 1.0)
end

--- Round to a number of decimal places. Used everywhere a pressure or flow reaches a
--- player, because a gauge reading 169.74999999 is a bug report.
---@param value number
---@param places integer|nil Defaults to 0.
---@return number
function Util.round(value, places)
    value = tonumber(value) or 0
    local mult = 10 ^ (places or 0)
    if value >= 0 then
        return math.floor(value * mult + 0.5) / mult
    end
    return math.ceil(value * mult - 0.5) / mult
end

--- Map a value from one range to another, clamped to the output range.
function Util.remap(value, inMin, inMax, outMin, outMax)
    if inMax == inMin then return outMin end
    local t = (value - inMin) / (inMax - inMin)
    return Util.clamp(outMin + t * (outMax - outMin), math.min(outMin, outMax), math.max(outMin, outMax))
end

-- ---------------------------------------------------------------------------
-- Randomness
-- ---------------------------------------------------------------------------

--- A float in [min, max).
function Util.randomFloat(min, max)
    return min + math.random() * (max - min)
end

--- Pick a key from a table of `key = weight`. Returns nil for an empty or zero-weight
--- table rather than erroring, because weights come from config and configs get edited.
---@param weights table<any, number>
---@return any|nil
function Util.weightedPick(weights)
    local total = 0.0
    for _, weight in pairs(weights) do
        if type(weight) == 'number' and weight > 0 then total = total + weight end
    end
    if total <= 0 then return nil end

    local roll = math.random() * total
    local cursor = 0.0
    for key, weight in pairs(weights) do
        if type(weight) == 'number' and weight > 0 then
            cursor = cursor + weight
            if roll <= cursor then return key end
        end
    end

    -- Floating point can land past the last bucket. Return something valid.
    for key, weight in pairs(weights) do
        if type(weight) == 'number' and weight > 0 then return key end
    end
    return nil
end

--- Roll a percentage chance. `chance` is 0-100.
function Util.chance(percent)
    return math.random() * 100.0 < (tonumber(percent) or 0)
end

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

---@param source table
---@return table
function Util.shallowCopy(source)
    local out = {}
    for key, value in pairs(source) do out[key] = value end
    return out
end

---@param source table
---@return table
function Util.deepCopy(source)
    if type(source) ~= 'table' then return source end
    local out = {}
    for key, value in pairs(source) do
        out[key] = type(value) == 'table' and Util.deepCopy(value) or value
    end
    return out
end

--- Merge `override` onto a copy of `base`, recursing into hash tables.
---
--- **Arrays are replaced, not merged.** Overriding a list of five with a list of one means
--- the list of one, which is what anyone writing a config expects. Merging them by index
--- would keep elements four and five and silently produce a list nobody wrote -- the kind
--- of bug that looks like a permissions failure rather than a merge failure.
---
--- Used for config defaults: a district, apparatus, or fire class overriding a base profile.
---@param base table
---@param override table|nil
---@return table
function Util.merge(base, override)
    local out = Util.deepCopy(base)
    if type(override) ~= 'table' then return out end

    for key, value in pairs(override) do
        if type(value) == 'table' and type(out[key]) == 'table'
            and #value == 0 and #out[key] == 0 then
            -- Both are hashes: merge them.
            out[key] = Util.merge(out[key], value)
        else
            -- Either side being a sequence means replace outright.
            out[key] = type(value) == 'table' and Util.deepCopy(value) or value
        end
    end

    return out
end

---@param list table
---@return integer
function Util.count(list)
    local n = 0
    for _ in pairs(list) do n = n + 1 end
    return n
end

--- Table keys as an array, for iteration order that does not change under you.
---@param source table
---@return table
function Util.keys(source)
    local out = {}
    for key in pairs(source) do out[#out + 1] = key end
    return out
end

-- ---------------------------------------------------------------------------
-- Geometry
-- ---------------------------------------------------------------------------

--- Squared 2D distance. Prefer this in loops -- the square root is not free and is
--- almost never needed when all you are doing is comparing against a radius.
function Util.distance2dSq(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return dx * dx + dy * dy
end

function Util.distance3dSq(ax, ay, az, bx, by, bz)
    local dx, dy, dz = ax - bx, ay - by, az - bz
    return dx * dx + dy * dy + dz * dz
end

--- Is a point inside a convex or concave polygon? Ray casting, so it handles both.
--- Districts use this when they are not simple boxes.
---@param x number
---@param y number
---@param points table Array of { x, y } or vector-likes.
---@return boolean
function Util.pointInPolygon(x, y, points)
    local inside = false
    local count = #points
    if count < 3 then return false end

    local j = count
    for i = 1, count do
        local pi, pj = points[i], points[j]
        local xi, yi = pi.x or pi[1], pi.y or pi[2]
        local xj, yj = pj.x or pj[1], pj.y or pj[2]

        if ((yi > y) ~= (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi) + xi) then
            inside = not inside
        end
        j = i
    end

    return inside
end

-- ---------------------------------------------------------------------------
-- Strings and identity
-- ---------------------------------------------------------------------------

local idCounter = 0

--- Monotonic id with a prefix. Not a UUID -- these are per-runtime handles, and a
--- readable `incident:14` beats a hex blob when something goes wrong at 2am.
---@param prefix string
---@return string
function Util.nextId(prefix)
    idCounter = idCounter + 1
    return ('%s:%d'):format(prefix, idCounter)
end

--- Seconds to a `M:SS` clock, for air remaining and tank time.
---@param seconds number
---@return string
function Util.clock(seconds)
    seconds = tonumber(seconds) or 0
    if seconds == math.huge then return '--:--' end
    if seconds < 0 then seconds = 0 end
    local mins = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    return ('%d:%02d'):format(mins, secs)
end

-- ---------------------------------------------------------------------------
-- Logging
-- ---------------------------------------------------------------------------

--- Debug print, gated on `Config.debug`. Reads the config at call time rather than
--- caching it, so toggling debug at runtime works without a restart.
---@param category string
---@param message string
function Util.debug(category, message, ...)
    local config = rawget(_G, 'Config')
    if not config or not config.debug then return end
    local formatted = select('#', ...) > 0 and message:format(...) or message
    print(('[mi_fire:%s] %s'):format(category, formatted))
end

---@param message string
function Util.warn(message, ...)
    local formatted = select('#', ...) > 0 and message:format(...) or message
    print(('[mi_fire] WARNING: %s'):format(formatted))
end

MIFire.Util = Util

return Util
