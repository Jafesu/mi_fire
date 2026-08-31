--- Solving a live hose line.
---
--- `shared/hydraulics.lua` holds the published fireground formulae. This turns them into an
--- answer for one line at one moment: given what the pump is putting out and what is on the
--- end, how much water actually leaves the nozzle?
---
--- **The direction matters and it is the whole point of a pump panel.** A nozzle operator does
--- not choose a flow. They open the bail, and what comes out is decided by the pressure the
--- pump operator is sending and by everything between the two -- length, diameter, elevation,
--- appliances. A crew that wants more water asks for more pressure, and a pump operator who
--- does not give it has a crew standing in a fire with a soft line.
---
--- Pure. No natives, so a line can be solved without laying one.

MIFire = MIFire or {}

local Pump = {}

local Hydraulics = MIFire.Hydraulics

--- What is left at the nozzle after the trip.
---
--- Everything between the pump and the tip takes its share, and what remains is what does the
--- work. A negative answer means the line will not reach at all -- 300ft of 1.75 inch up six
--- floors simply cannot be supplied at 100 psi, and finding that out is the pump operator's
--- job rather than a surprise.
---@param spec table
---   dischargePsi  number  what the pump is putting out at this outlet
---   diameter      number  inches
---   lengthFeet    number
---   gpm           number  the flow being carried
---   elevationFeet number|nil
---   appliance     string|nil  a key into the appliance table, or nil
---@return number psi Nozzle pressure. May be zero.
---@return table losses Where the pressure went: friction, elevation, appliance.
function Pump.nozzlePressure(spec)
    local friction = Hydraulics.frictionLoss(
        spec.diameter, spec.gpm or 0, spec.lengthFeet or 0)

    local elevation = Hydraulics.elevationLossFeet(spec.elevationFeet or 0)

    local appliance = spec.appliance
        and Hydraulics.applianceLoss(spec.gpm or 0, { type = spec.appliance })
        or 0.0

    local remaining = (spec.dischargePsi or 0) - friction - elevation - appliance

    return math.max(0.0, remaining), {
        friction = friction,
        elevation = elevation,
        appliance = appliance,
    }
end

--- What a nozzle flows at a given pressure.
---
--- A smooth bore is arithmetic -- the tip and the pressure decide it, which is why it is
--- predictable and why a pump operator can work one out in their head. A fog nozzle is rated
--- for a flow at a pressure and falls off either side of it.
---@param nozzle table An entry from `MIFireHose.nozzles`.
---@param psi number Nozzle pressure.
---@param ratedGpm number|nil For a fog nozzle; its rated flow.
---@return number gpm
function Pump.nozzleFlow(nozzle, psi, ratedGpm)
    if psi <= 0 then return 0.0 end

    if nozzle.tipInches then
        return Hydraulics.smoothBoreFlow(nozzle.tipInches, psi)
    end

    return Hydraulics.fogFlow(
        ratedGpm or 150.0, nozzle.nozzlePressure or 100.0, psi)
end

--- Solve a line by converging on its own flow.
---
--- Circular by nature: friction loss depends on flow, and flow depends on what pressure
--- survives the friction loss. Solved by iteration rather than algebra because the nozzle
--- curves are not all invertible, and because a handful of passes is exact enough for a number
--- that is displayed to one decimal place.
---
--- Converges quickly -- friction loss is well behaved over the range a hose line lives in.
---@param spec table As `Pump.nozzlePressure`, plus `nozzle` and `ratedGpm`, minus `gpm`.
---@param iterations integer|nil Default 12.
---@return number gpm
---@return number nozzlePsi
---@return table losses
function Pump.solveLine(spec, iterations)
    local nozzle = spec.nozzle or {}
    local gpm = spec.startGpm or 100.0
    local psi, losses = 0.0, {}

    for _ = 1, iterations or 12 do
        psi, losses = Pump.nozzlePressure({
            dischargePsi = spec.dischargePsi,
            diameter = spec.diameter,
            lengthFeet = spec.lengthFeet,
            gpm = gpm,
            elevationFeet = spec.elevationFeet,
            appliance = spec.appliance,
        })

        local solved = Pump.nozzleFlow(nozzle, psi, spec.ratedGpm)

        -- Damped, or the iteration oscillates: too much flow costs pressure, which cuts the
        -- flow, which returns the pressure, and so on forever.
        gpm = gpm + (solved - gpm) * 0.5

        if math.abs(solved - gpm) < 0.5 then break end
    end

    return math.max(0.0, gpm), psi, losses
end

--- What the pump can actually deliver.
---
--- NFPA 1901: a pump makes its rated flow at 150 psi, 70% of it at 200, and half at 250. So a
--- 1500 gpm pump asked for 1500 gpm at 200 psi is being asked for something it cannot do, and
--- the answer is not "it works a bit worse" -- it is that the pressure falls until the demand
--- fits the curve.
---@param ratedGpm number
---@param netPressure number
---@param demandGpm number
---@return number availableGpm
---@return boolean overCapacity
function Pump.capacity(ratedGpm, netPressure, demandGpm)
    local available = Hydraulics.pumpCapacityAt(ratedGpm, netPressure)
    return available, (demandGpm or 0) > available
end

--- Share what there is between the lines that want it.
---
--- When demand exceeds what the pump can make, every line loses proportionally. That is what
--- actually happens: opening a second discharge takes pressure off the first, which is the
--- single most important thing for a nozzle crew to feel and the reason a governor exists.
---@param demands table[] `{ gpm }` per line
---@param available number
---@return number[] scaled
function Pump.share(demands, available)
    local total = 0.0
    for i = 1, #demands do total = total + (demands[i].gpm or 0) end

    if total <= available or total <= 0 then
        local out = {}
        for i = 1, #demands do out[i] = demands[i].gpm or 0 end
        return out
    end

    local scale = available / total
    local out = {}

    for i = 1, #demands do out[i] = (demands[i].gpm or 0) * scale end

    return out
end

--- Is the line usable at all?
---
--- Below about a third of its rated nozzle pressure a line is not underperforming, it is
--- limp -- no reach, no penetration, and a crew that thinks it has water when it does not.
--- Worth naming rather than leaving as a small number on a gauge.
---@param psi number
---@param nozzle table
---@return boolean
---@return string
function Pump.lineCondition(psi, nozzle)
    local rated = nozzle.nozzlePressure or 100.0

    if psi <= 1.0 then return false, 'no water' end
    if psi < rated * 0.35 then return false, 'soft' end
    if psi < rated * 0.75 then return true, 'low' end
    if psi > rated * 1.35 then return true, 'over-pressured' end

    return true, 'good'
end

MIFire.Pump = Pump

return Pump
