--- How big a mark a fire leaves, and how long it takes to wash away.
---
--- Pure, so the sizing curve can be checked without setting anything on fire.

MIFire = MIFire or {}

local Scorch = {}

--- How large a mark a node leaves behind.
---
--- Scaled by how long it burned and how hard. A knockdown in the first thirty seconds should
--- leave a scuff; a fire that ate its fuel should leave a floor. Without the time term every
--- mark is the same size and the scene stops carrying information -- which is most of the
--- reason to have them.
---@param burnedSeconds number How long the node was alight.
---@param peakIntensity number 0-100, the hardest it burned.
---@param config table `MIFireScorch.size`
---@return number metres
function Scorch.size(burnedSeconds, peakIntensity, config)
    local minimum = tonumber(config.minimum) or 1.0
    local maximum = tonumber(config.maximum) or 5.0
    local full = math.max(1.0, tonumber(config.fullSizeAfterSeconds) or 120.0)

    local age = math.max(0.0, tonumber(burnedSeconds) or 0.0) / full
    age = math.min(1.0, age)

    local heat = math.max(0.0, math.min(100.0, tonumber(peakIntensity) or 0.0)) / 100.0

    -- Time dominates. A brief flare-up at full intensity is still a brief flare-up, and it
    -- should not leave the same mark as twenty minutes of steady burning.
    local scale = age * 0.7 + heat * 0.3

    return minimum + (maximum - minimum) * scale
end

--- Seconds of work to wash one mark away.
---
--- Scaled by its size for the same reason repair time scales with damage: a fixed toll
--- carries no information, and the number should tell you what you are looking at.
---@param size number Metres, from `Scorch.size`.
---@param config table `MIFireScorch.cleanup`
---@param sizeConfig table `MIFireScorch.size`
---@return number seconds
function Scorch.cleanSeconds(size, config, sizeConfig)
    local base = tonumber(config.seconds) or 10.0
    local minimum = tonumber(sizeConfig.minimum) or 1.0
    local maximum = tonumber(sizeConfig.maximum) or 5.0

    if maximum <= minimum then return base end

    local fraction = (math.max(minimum, math.min(maximum, size)) - minimum)
        / (maximum - minimum)

    -- Half the base time for the smallest mark, one and a half for the largest.
    return base * (0.5 + fraction)
end

--- Has a mark aged out?
---@param markedAt number os.time() when it was made.
---@param now number
---@param config table `MIFireScorch`
---@return boolean
function Scorch.expired(markedAt, now, config)
    local minutes = tonumber(config.lifetimeMinutes) or 0.0

    -- Zero means it never ages out and only ever goes when someone removes it.
    if minutes <= 0 then return false end

    return (now - markedAt) >= minutes * 60.0
end

--- How faded a mark is, 0 fresh to 1 gone.
---
--- Marks lighten as they age rather than blinking out, so a scene that has not been cleaned
--- still reads as older than one that just burned.
---@param markedAt number
---@param now number
---@param config table `MIFireScorch`
---@return number
function Scorch.fade(markedAt, now, config)
    local minutes = tonumber(config.lifetimeMinutes) or 0.0
    if minutes <= 0 then return 0.0 end

    local age = (now - markedAt) / (minutes * 60.0)
    return math.max(0.0, math.min(1.0, age))
end

MIFire.Scorch = Scorch

return Scorch
