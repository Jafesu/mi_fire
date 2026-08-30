--- Reading smoke.
---
--- Smoke is not a by-product of fire in this model. It is the primary source of information
--- about a fire you cannot see, and it is read the way a real officer reads it: by four
--- attributes, taken together.
---
---   **Volume**    how much fuel is off-gassing. On its own it means little -- a large
---                 building holds a lot of smoke without much fire.
---   **Velocity**  how hard it is leaving, which tells you the *pressure* inside. The most
---                 important of the four. Turbulent smoke is heat-pushed and means the
---                 compartment has stopped absorbing heat. Laminar smoke is volume-pushed
---                 and means it still is.
---   **Density**   how much unburned fuel is suspended in it. Thick smoke *is* fuel, and
---                 it will burn violently the moment it finds air.
---   **Colour**    how far through heating the fuel is -- and, critically, how far the
---                 smoke has travelled. Smoke lightens as it cools and filters, so black at
---                 a window with white at the eaves tells you where the seat is.
---
--- Pure. No natives, no state. The whole point is that these conclusions can be checked
--- against known fireground readings rather than eyeballed in game.

MIFire = MIFire or {}

local Smoke = {}

--- Stage of heating, which is what colour is really reporting.
Smoke.Stage = {
    INCIPIENT = 'incipient',   -- moisture driving off. Early, cool, white.
    GROWTH    = 'growth',      -- fuel heating, light smoke
    PYROLYSIS = 'pyrolysis',   -- unfinished wood off-gassing. Brown means structure.
    DEVELOPED = 'developed',   -- carbon rich, hot, black. This is unburned fuel.
}

--- What the smoke is warning about, if anything.
Smoke.Warning = {
    NONE      = 'none',
    FLASHOVER = 'flashover',
    BACKDRAFT = 'backdraft',
}

-- ---------------------------------------------------------------------------
-- Stage
-- ---------------------------------------------------------------------------

--- How far through heating this fire is.
---
--- Driven by intensity and by how much of the fuel has been consumed, because a fire that
--- has been burning a while is into different materials than one that has just started.
---@param intensity number 0-100
---@param fuelFraction number Remaining fuel, 0-1.
---@param class table Resolved fire class.
---@return string stage
function Smoke.stage(intensity, fuelFraction, class)
    intensity = math.max(0.0, math.min(100.0, tonumber(intensity) or 0))
    fuelFraction = math.max(0.0, math.min(1.0, tonumber(fuelFraction) or 1.0))

    -- A class that burns clean never reaches the dirty stages however hot it gets. A gas
    -- jet at full intensity is not producing brown smoke.
    local dirtiness = (class and class.smokeVolume or 1.0)

    if intensity < 25 then return Smoke.Stage.INCIPIENT end
    if intensity < 50 then return Smoke.Stage.GROWTH end

    if dirtiness < 0.8 then
        -- Clean-burning fuel skips the pyrolysis look entirely.
        return intensity >= 75 and Smoke.Stage.DEVELOPED or Smoke.Stage.GROWTH
    end

    -- Consumed fuel means the fire has moved on to whatever is underneath, which for a
    -- structure means the structure.
    if intensity < 75 or fuelFraction > 0.6 then return Smoke.Stage.PYROLYSIS end
    return Smoke.Stage.DEVELOPED
end

-- ---------------------------------------------------------------------------
-- The four attributes
-- ---------------------------------------------------------------------------

--- Smoke at the seat of the fire.
---
--- Ventilation is the multiplier on everything. A fire with nowhere to go builds pressure,
--- burns incompletely, and produces dense dark smoke pushing hard -- which is exactly the
--- reading that precedes a flashover.
---
---@param opts table
---   intensity      number  0-100
---   fuelFraction   number  0-1 remaining
---   class          table   resolved fire class
---   ventilation    string  'sealed' | 'limited' | 'open'
---   confined       boolean indoors, so smoke cannot disperse
---@param config table `MIFireSmoke`
---@return table attributes { volume, velocity, density, stage, turbulent, colour }
function Smoke.attributes(opts, config)
    local intensity = math.max(0.0, math.min(100.0, tonumber(opts.intensity) or 0))
    local class = opts.class or {}
    local vent = config.ventilation[opts.ventilation or 'open'] or config.ventilation.open

    local stage = Smoke.stage(intensity, opts.fuelFraction or 1.0, class)
    local dirtiness = class.smokeVolume or 1.0

    -- Volume: how much is being produced. Fuel character and intensity.
    local volume = (intensity / 100.0) * dirtiness * vent.volumeMultiplier
    if opts.confined then volume = volume * config.confinedVolumeMultiplier end

    -- Density: unburned fuel suspended. Incomplete combustion makes dirtier smoke, and a
    -- starved fire burns very incompletely indeed.
    local density = (intensity / 100.0) * dirtiness * vent.densityMultiplier
    density = density * (config.stageDensity[stage] or 1.0)

    -- Velocity: pressure. Heat drives it, restriction concentrates it.
    local velocity = (intensity / 100.0) * vent.velocityMultiplier
    if opts.confined then velocity = velocity * config.confinedVelocityMultiplier end

    -- Turbulent means heat-pushed: the compartment has stopped absorbing heat and is
    -- giving it back. This is the single most important thing on the fireground and it is
    -- one boolean.
    local turbulent = velocity >= config.turbulentAbove
        and (stage == Smoke.Stage.DEVELOPED or stage == Smoke.Stage.PYROLYSIS)

    return {
        volume = math.max(0.0, math.min(1.0, volume)),
        density = math.max(0.0, math.min(1.0, density)),
        velocity = math.max(0.0, math.min(1.0, velocity)),
        stage = stage,
        turbulent = turbulent,
        travelled = 0.0,
        colour = Smoke.colour(stage, 0.0, config),
    }
end

-- ---------------------------------------------------------------------------
-- Colour, and what travel does to it
-- ---------------------------------------------------------------------------

--- Colour for a stage of heating, lightened by how far the smoke has travelled.
---
--- This is the interaction that makes smoke readable across a building. Hot black smoke
--- cools as it moves, loses carbon onto every surface it touches, and comes out grey or
--- white at the far end. So black at one opening and white at another is not two fires --
--- it is one fire, and the black is nearer the seat.
---@param stage string
---@param travelled number Metres from the seat.
---@param config table
---@return table colour { r, g, b } each 0-255
function Smoke.colour(stage, travelled, config)
    local base = config.stageColour[stage] or config.stageColour[Smoke.Stage.GROWTH]
    local pale = config.travelColour

    local distance = math.max(0.0, tonumber(travelled) or 0.0)
    local t = math.min(1.0, distance / math.max(0.1, config.travelToPale))

    -- Ease it: most of the lightening happens early, as the hottest smoke cools fastest.
    t = 1.0 - (1.0 - t) * (1.0 - t)

    return {
        r = base.r + (pale.r - base.r) * t,
        g = base.g + (pale.g - base.g) * t,
        b = base.b + (pale.b - base.b) * t,
    }
end

--- Age smoke as it moves away from the seat.
---
--- It cools, lightens, thins, and slows. All four attributes change, which is why smoke
--- from the same fire reads differently at different openings.
---@param attributes table
---@param distance number Metres travelled since the seat.
---@param config table
---@return table aged A copy; the original is not mutated.
function Smoke.travel(attributes, distance, config)
    distance = math.max(0.0, tonumber(distance) or 0.0)

    local thinning = math.max(0.0, 1.0 - (distance / math.max(0.1, config.travelToThin)))
    local slowing = math.max(0.0, 1.0 - (distance / math.max(0.1, config.travelToStill)))

    return {
        volume = attributes.volume * (0.4 + 0.6 * thinning),
        density = attributes.density * thinning,
        velocity = attributes.velocity * slowing,
        stage = attributes.stage,
        -- Turbulence is a local property of pressure. Smoke that has travelled is no
        -- longer being pushed, whatever it was doing at the seat.
        turbulent = attributes.turbulent and slowing > 0.6,
        travelled = distance,
        colour = Smoke.colour(attributes.stage, distance, config),
    }
end

-- ---------------------------------------------------------------------------
-- Prediction
-- ---------------------------------------------------------------------------

--- How close this compartment is to flashover, 0-1.
---
--- Flashover is every surface in a room reaching ignition temperature at once. The reading
--- that precedes it is well known: high volume, turbulent velocity, thick density, dark
--- colour -- what crews call **black fire**, because it is fuel and it is about to light.
---
--- Requires a compartment. An outdoor fire has nowhere to hold the heat.
---@param attributes table
---@param ventilation string
---@param confined boolean
---@param config table
---@return number risk 0-1
function Smoke.flashoverRisk(attributes, ventilation, confined, config)
    if not confined then return 0.0 end

    local vent = config.ventilation[ventilation or 'open'] or config.ventilation.open
    if vent.flashoverMultiplier <= 0 then return 0.0 end

    -- All four have to agree. Any one of them alone is not a flashover warning, and
    -- treating it as one would cry wolf constantly.
    local dark = (attributes.stage == Smoke.Stage.DEVELOPED) and 1.0
        or (attributes.stage == Smoke.Stage.PYROLYSIS) and 0.6 or 0.0

    local signal = attributes.volume * attributes.density
        * (attributes.turbulent and 1.0 or 0.45) * dark

    return math.max(0.0, math.min(1.0, signal * vent.flashoverMultiplier))
end

--- How close this compartment is to backdraft, 0-1.
---
--- The opposite condition to flashover, and the more dangerous one because it looks
--- calmer. A sealed fire consumes its oxygen and drops back to smouldering: little visible
--- flame, heavy dense smoke, and pressure cycling in and out of every gap as the fire
--- breathes. Introduce air and the whole volume deflagrates.
---
--- The tell is the pulsing. Smoke that moves *both ways* through an opening is a fire
--- asking for oxygen.
---@param attributes table
---@param ventilation string
---@param confined boolean
---@param config table
---@return number risk 0-1
function Smoke.backdraftRisk(attributes, ventilation, confined, config)
    if not confined then return 0.0 end

    local vent = config.ventilation[ventilation or 'open'] or config.ventilation.open
    if vent.backdraftMultiplier <= 0 then return 0.0 end

    -- Dense, dark, and *not* pushing hard. Low velocity is the point: a backdraft fire is
    -- starved, so it is not driving smoke out under pressure the way a flashover fire is.
    local starved = 1.0 - attributes.velocity
    local dark = (attributes.stage == Smoke.Stage.DEVELOPED) and 1.0
        or (attributes.stage == Smoke.Stage.PYROLYSIS) and 0.5 or 0.0

    local signal = attributes.density * starved * dark

    return math.max(0.0, math.min(1.0, signal * vent.backdraftMultiplier))
end

--- Is this smoke pulsing in and out?
---
--- Purely a rendering and reading cue, but the most recognisable backdraft sign there is.
---@param backdraft number Risk 0-1.
---@param config table
---@return boolean
function Smoke.isPulsing(backdraft, config)
    return backdraft >= (config.pulsingAbove or 0.45)
end

-- ---------------------------------------------------------------------------
-- Putting it into words
-- ---------------------------------------------------------------------------

--- Describe smoke the way an officer would, one attribute at a time.
---
--- Deliberately reports the *observation* separately from the *conclusion*. A size-up that
--- only says "flashover imminent" teaches nobody anything; one that says what was seen and
--- then what it means is how the skill is actually taught.
---@param attributes table
---@param config table
---@return table reading { volume, velocity, density, colour, observations, warning, risk }
function Smoke.read(attributes, ventilation, confined, config)
    local function band(value, labels)
        if value >= 0.75 then return labels[4] end
        if value >= 0.5 then return labels[3] end
        if value >= 0.25 then return labels[2] end
        return labels[1]
    end

    local volumeWord = band(attributes.volume, config.words.volume)
    local velocityWord = attributes.turbulent
        and config.words.turbulent
        or band(attributes.velocity, config.words.velocity)
    local densityWord = band(attributes.density, config.words.density)
    local colourWord = config.words.colour[attributes.stage] or 'grey'

    local flashover = Smoke.flashoverRisk(attributes, ventilation, confined, config)
    local backdraft = Smoke.backdraftRisk(attributes, ventilation, confined, config)

    local warning, risk = Smoke.Warning.NONE, 0.0

    -- Backdraft wins ties. It kills people who thought they were looking at a small fire,
    -- and the consequence of calling it wrongly is far cheaper than missing it.
    if backdraft >= config.warnAbove and backdraft >= flashover then
        warning, risk = Smoke.Warning.BACKDRAFT, backdraft
    elseif flashover >= config.warnAbove then
        warning, risk = Smoke.Warning.FLASHOVER, flashover
    end

    return {
        volume = volumeWord,
        velocity = velocityWord,
        density = densityWord,
        colour = colourWord,
        stage = attributes.stage,
        turbulent = attributes.turbulent,
        pulsing = Smoke.isPulsing(backdraft, config),
        warning = warning,
        risk = risk,
        flashoverRisk = flashover,
        backdraftRisk = backdraft,
    }
end

MIFire.Smoke = Smoke

return Smoke
