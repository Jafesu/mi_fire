--- Fireground hydraulics.
---
--- Pure arithmetic. No game natives, no side effects. That is deliberate: this file is the
--- single source of truth for every pressure number the resource shows a player, so it has
--- to be runnable -- and testable -- outside FiveM. `tools/run_tests.lua` executes it under
--- a plain interpreter.
---
--- Written against standard fire service formulas. Where a number looks arbitrary it is
--- almost certainly a published constant; the comment says which.
---
--- Units are US fire service throughout, because that is what the formulas and every
--- published coefficient table use:
---   pressure  psi
---   flow      gpm (US gallons per minute)
---   length    feet
---   diameter  inches

local Hydraulics = {}

-- ---------------------------------------------------------------------------
-- Friction loss
-- ---------------------------------------------------------------------------

--- Friction-loss coefficients by hose diameter, in inches.
---
--- These are the standard single-line coefficients used in fire service hydraulics.
--- They are not tuning values -- changing one makes the resource lie to a pump operator
--- who knows the real numbers. Tune `config/hose.lua` instead.
Hydraulics.COEFFICIENTS = {
    [0.75] = 1100.0,  -- booster
    [1.0]  = 150.0,   -- booster
    [1.5]  = 24.0,
    [1.75] = 15.5,
    [2.0]  = 8.0,
    [2.5]  = 2.0,
    [3.0]  = 0.8,     -- 3 inch with 2.5 inch couplings
    [3.5]  = 0.34,
    [4.0]  = 0.2,
    [4.5]  = 0.1,
    [5.0]  = 0.08,
    [6.0]  = 0.05,
}

--- Look up the friction-loss coefficient for a hose diameter.
--- Unknown diameters interpolate from the nearest pair rather than failing, so an
--- unusual size in a config does not hard-error a live pump panel.
---@param diameter number Hose inside diameter, inches.
---@return number coefficient
function Hydraulics.coefficient(diameter)
    diameter = tonumber(diameter)
    if not diameter or diameter <= 0 then return 0.0 end

    local exact = Hydraulics.COEFFICIENTS[diameter]
    if exact then return exact end

    -- Find the bracketing sizes and interpolate logarithmically: coefficients fall off
    -- roughly as the fifth power of diameter, so a linear blend badly overestimates.
    local below, above
    for size in pairs(Hydraulics.COEFFICIENTS) do
        if size < diameter and (not below or size > below) then below = size end
        if size > diameter and (not above or size < above) then above = size end
    end

    if below and above then
        local cBelow, cAbove = Hydraulics.COEFFICIENTS[below], Hydraulics.COEFFICIENTS[above]
        local t = (math.log(diameter) - math.log(below)) / (math.log(above) - math.log(below))
        return math.exp(math.log(cBelow) + t * (math.log(cAbove) - math.log(cBelow)))
    end

    -- Outside the table entirely. Scale from the nearest known size by the fifth-power rule.
    local nearest = below or above
    if not nearest then return 0.0 end
    return Hydraulics.COEFFICIENTS[nearest] * (nearest / diameter) ^ 5
end

--- Friction loss in a single hose line.
---
---     FL = C * Q^2 * L
---
--- where Q is flow in hundreds of gpm and L is length in hundreds of feet.
---@param diameter number Hose inside diameter, inches.
---@param gpm number Flow through the line.
---@param lengthFt number Length of the lay, feet.
---@return number psi Friction loss, never negative.
function Hydraulics.frictionLoss(diameter, gpm, lengthFt)
    gpm = tonumber(gpm) or 0
    lengthFt = tonumber(lengthFt) or 0
    if gpm <= 0 or lengthFt <= 0 then return 0.0 end

    local c = Hydraulics.coefficient(diameter)
    local q = gpm / 100.0
    local l = lengthFt / 100.0
    return c * q * q * l
end

--- Friction loss through parallel lines of the same diameter carrying one flow.
--- Each line carries an equal share, and loss falls with the square of that share --
--- which is the whole reason two 3 inch lines beat one.
---@param diameter number
---@param totalGpm number Combined flow across all lines.
---@param lengthFt number
---@param lineCount integer How many parallel lines, minimum 1.
---@return number psi
function Hydraulics.frictionLossParallel(diameter, totalGpm, lengthFt, lineCount)
    lineCount = math.max(1, math.floor(tonumber(lineCount) or 1))
    return Hydraulics.frictionLoss(diameter, (tonumber(totalGpm) or 0) / lineCount, lengthFt)
end

-- ---------------------------------------------------------------------------
-- Nozzles
-- ---------------------------------------------------------------------------

--- Standard nozzle operating pressures.
Hydraulics.NOZZLE_PRESSURE = {
    smoothbore_handline = 50.0,   -- 50 psi at the tip
    smoothbore_master   = 80.0,   -- master stream devices run 80
    fog                 = 100.0,  -- combination nozzle, standard pressure
    fog_low             = 75.0,   -- low-pressure combination
    fog_ultra_low       = 55.0,
}

--- Discharge from a smooth bore tip.
---
---     Q = 29.7 * d^2 * sqrt(NP)
---
--- 29.7 folds together the orifice discharge coefficient and the unit conversion.
---@param tipInches number Tip diameter, inches.
---@param nozzlePressure number psi at the tip.
---@return number gpm
function Hydraulics.smoothBoreFlow(tipInches, nozzlePressure)
    local d = tonumber(tipInches) or 0
    local np = tonumber(nozzlePressure) or 0
    if d <= 0 or np <= 0 then return 0.0 end
    return 29.7 * d * d * math.sqrt(np)
end

--- The inverse: what tip pressure produces a target flow.
---@param tipInches number
---@param targetGpm number
---@return number psi
function Hydraulics.smoothBorePressureFor(tipInches, targetGpm)
    local d = tonumber(tipInches) or 0
    local q = tonumber(targetGpm) or 0
    if d <= 0 or q <= 0 then return 0.0 end
    local root = q / (29.7 * d * d)
    return root * root
end

--- Flow from a fog nozzle at a given tip pressure.
--- A fog nozzle is rated for a flow at a rated pressure; away from that pressure the
--- flow follows the square root of the ratio, same as any orifice.
---@param ratedGpm number Flow the nozzle is rated for.
---@param ratedPressure number Pressure that rating assumes, psi.
---@param actualPressure number Actual tip pressure, psi.
---@return number gpm
function Hydraulics.fogFlow(ratedGpm, ratedPressure, actualPressure)
    local rated = tonumber(ratedGpm) or 0
    local rp = tonumber(ratedPressure) or 0
    local ap = tonumber(actualPressure) or 0
    if rated <= 0 or rp <= 0 or ap <= 0 then return 0.0 end
    return rated * math.sqrt(ap / rp)
end

-- ---------------------------------------------------------------------------
-- Elevation
-- ---------------------------------------------------------------------------

--- Head pressure: 0.434 psi per foot of elevation, the weight of a foot of water.
--- Positive means the nozzle is above the pump and the pump must overcome it.
---@param feet number Elevation gain in feet; negative for a nozzle below the pump.
---@return number psi
function Hydraulics.elevationLossFeet(feet)
    return (tonumber(feet) or 0) * 0.434
end

--- The fireground shortcut: 5 psi per floor above the pump.
--- Floor 1 is ground level, so floor 1 costs nothing.
---@param floor number Floor number, 1-based. Below grade is allowed and negative.
---@return number psi
function Hydraulics.elevationLossFloors(floor)
    local f = tonumber(floor) or 1
    return (f - 1) * 5.0
end

-- ---------------------------------------------------------------------------
-- Appliances
-- ---------------------------------------------------------------------------

Hydraulics.APPLIANCE_THRESHOLD_GPM = 350.0
Hydraulics.APPLIANCE_LOSS_PSI = 10.0
Hydraulics.MASTER_STREAM_LOSS_PSI = 25.0
Hydraulics.STANDPIPE_LOSS_PSI = 25.0

--- Loss across appliances in the line.
--- Below 350 gpm an appliance costs nothing worth counting; at or above it costs 10 psi.
--- Master stream devices and standpipes are a flat 25 psi regardless of flow.
---@param gpm number Flow through the appliance.
---@param opts table|nil { masterStream = boolean, standpipe = boolean, count = integer }
---@return number psi
function Hydraulics.applianceLoss(gpm, opts)
    opts = opts or {}
    local flow = tonumber(gpm) or 0
    if flow <= 0 then return 0.0 end

    local loss = 0.0
    if opts.masterStream then loss = loss + Hydraulics.MASTER_STREAM_LOSS_PSI end
    if opts.standpipe then loss = loss + Hydraulics.STANDPIPE_LOSS_PSI end

    local count = math.max(0, math.floor(tonumber(opts.count) or 0))
    if count > 0 and flow >= Hydraulics.APPLIANCE_THRESHOLD_GPM then
        loss = loss + (count * Hydraulics.APPLIANCE_LOSS_PSI)
    end

    return loss
end

-- ---------------------------------------------------------------------------
-- Pump discharge pressure
-- ---------------------------------------------------------------------------

--- Solve a complete discharge for the pressure the pump has to make.
---
---     PDP = NP + FL + AL + EL
---
--- `segments` lets a line change diameter partway -- a 3 inch lay into a gated wye into
--- 1.75 inch is two segments, and each is solved with its own flow.
---
---@param spec table
---   nozzlePressure  number  psi at the tip (required)
---   gpm             number  flow through the line (required)
---   diameter        number  hose diameter, inches -- used when `segments` is absent
---   lengthFt        number  lay length, feet -- used when `segments` is absent
---   segments        table|nil  { { diameter, lengthFt, gpm?, lineCount? }, ... }
---   floor           number|nil  nozzle floor, 1-based
---   elevationFt     number|nil  explicit elevation in feet; wins over `floor`
---   appliances      table|nil   passed through to applianceLoss
---@return table result { pdp, nozzlePressure, frictionLoss, elevationLoss, applianceLoss, gpm }
function Hydraulics.solveDischarge(spec)
    spec = spec or {}
    local gpm = tonumber(spec.gpm) or 0
    local np = tonumber(spec.nozzlePressure) or 0

    local fl = 0.0
    if type(spec.segments) == 'table' and #spec.segments > 0 then
        for i = 1, #spec.segments do
            local seg = spec.segments[i]
            local segGpm = tonumber(seg.gpm) or gpm
            local lines = tonumber(seg.lineCount) or 1
            fl = fl + Hydraulics.frictionLossParallel(seg.diameter, segGpm, seg.lengthFt, lines)
        end
    else
        fl = Hydraulics.frictionLoss(spec.diameter, gpm, spec.lengthFt)
    end

    local el
    if spec.elevationFt ~= nil then
        el = Hydraulics.elevationLossFeet(spec.elevationFt)
    else
        el = Hydraulics.elevationLossFloors(spec.floor or 1)
    end

    local al = Hydraulics.applianceLoss(gpm, spec.appliances)

    return {
        pdp = np + fl + el + al,
        nozzlePressure = np,
        frictionLoss = fl,
        elevationLoss = el,
        applianceLoss = al,
        gpm = gpm,
    }
end

-- ---------------------------------------------------------------------------
-- Pump capability
-- ---------------------------------------------------------------------------

--- NFPA 1901 pump rating points: a pump makes its full rated flow only at 150 psi.
Hydraulics.PUMP_CURVE = {
    { pressure = 150.0, fraction = 1.00 },
    { pressure = 200.0, fraction = 0.70 },
    { pressure = 250.0, fraction = 0.50 },
}

--- How much a pump can actually move at a given net pump pressure.
--- Below 150 psi it is still capped at its rating; above 250 it falls off steeply.
---@param ratedGpm number The pump rated capacity at 150 psi.
---@param netPressure number Net pump pressure, psi (discharge minus intake).
---@return number gpm Maximum deliverable flow.
function Hydraulics.pumpCapacityAt(ratedGpm, netPressure)
    local rated = tonumber(ratedGpm) or 0
    local p = tonumber(netPressure) or 0
    if rated <= 0 then return 0.0 end

    local curve = Hydraulics.PUMP_CURVE
    if p <= curve[1].pressure then return rated end

    for i = 1, #curve - 1 do
        local lo, hi = curve[i], curve[i + 1]
        if p <= hi.pressure then
            local t = (p - lo.pressure) / (hi.pressure - lo.pressure)
            return rated * (lo.fraction + t * (hi.fraction - lo.fraction))
        end
    end

    -- Past the last rating point, continue the final slope down to zero rather than
    -- pretending the pump keeps delivering.
    local last, prev = curve[#curve], curve[#curve - 1]
    local slope = (last.fraction - prev.fraction) / (last.pressure - prev.pressure)
    local fraction = last.fraction + slope * (p - last.pressure)
    return rated * math.max(0.0, fraction)
end

-- ---------------------------------------------------------------------------
-- Water supply
-- ---------------------------------------------------------------------------

--- Percentage a hydrant pressure dropped once flow started.
---@param staticPsi number Pressure with nothing flowing.
---@param residualPsi number Pressure while flowing.
---@return number percent 0-100
function Hydraulics.percentDrop(staticPsi, residualPsi)
    local static = tonumber(staticPsi) or 0
    local residual = tonumber(residualPsi) or 0
    if static <= 0 then return 100.0 end
    local drop = (static - residual) / static * 100.0
    if drop < 0 then return 0.0 end
    if drop > 100 then return 100.0 end
    return drop
end

--- The percent-drop rule: how many more lines of the flow already moving a hydrant
--- can supply. This is the field method crews actually use, not a lookup of main sizes.
---@param staticPsi number
---@param residualPsi number
---@param flowInUseGpm number Flow that produced that residual.
---@return number gpm Total available flow, including what is already moving.
---@return number multiplier Additional lines of equal flow available.
function Hydraulics.availableFlow(staticPsi, residualPsi, flowInUseGpm)
    local inUse = tonumber(flowInUseGpm) or 0
    local drop = Hydraulics.percentDrop(staticPsi, residualPsi)

    local multiplier
    if drop <= 10.0 then
        multiplier = 3.0
    elseif drop <= 15.0 then
        multiplier = 2.0
    elseif drop <= 25.0 then
        multiplier = 1.0
    else
        -- Past 25% the rule stops giving whole lines. Fall off toward nothing so the
        -- number keeps meaning something instead of snapping to zero at 25.1%.
        multiplier = math.max(0.0, (100.0 - drop) / 75.0)
    end

    return inUse + (inUse * multiplier), multiplier
end

Hydraulics.CAVITATION_INTAKE_PSI = 20.0

--- Is the pump being asked for more than its supply can give?
--- Real pumps cavitate when intake residual falls below about 20 psi; the operator hears
--- it before the gauge shows it, which is why the panel gets an audible warning.
---@param intakePsi number Intake residual pressure.
---@param demandGpm number What the discharges are asking for.
---@param supplyGpm number What the source can deliver.
---@return boolean cavitating
---@return number severity 0-1, how far past the limit
function Hydraulics.isCavitating(intakePsi, demandGpm, supplyGpm)
    local intake = tonumber(intakePsi) or 0
    local demand = tonumber(demandGpm) or 0
    local supply = tonumber(supplyGpm) or 0

    local overdraw = 0.0
    if supply > 0 and demand > supply then
        overdraw = (demand - supply) / supply
    elseif supply <= 0 and demand > 0 then
        overdraw = 1.0
    end

    local starved = 0.0
    if intake < Hydraulics.CAVITATION_INTAKE_PSI then
        starved = (Hydraulics.CAVITATION_INTAKE_PSI - intake) / Hydraulics.CAVITATION_INTAKE_PSI
    end

    local severity = math.min(1.0, math.max(overdraw, starved))
    return severity > 0.0, severity
end

--- Time to empty a tank at a given flow, in seconds. The number the panel counts down.
---@param tankGallons number Water remaining.
---@param gpm number Combined flow off the tank.
---@return number seconds Returns math.huge when nothing is flowing.
function Hydraulics.tankSecondsRemaining(tankGallons, gpm)
    local gallons = tonumber(tankGallons) or 0
    local flow = tonumber(gpm) or 0
    if flow <= 0 then return math.huge end
    if gallons <= 0 then return 0.0 end
    return (gallons / flow) * 60.0
end

-- ---------------------------------------------------------------------------

MIFire = MIFire or {}
MIFire.Hydraulics = Hydraulics

return Hydraulics
