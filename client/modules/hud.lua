--- The fireground HUD.
---
--- Three numbers that cannot be got any other way: air remaining, the condition of the
--- coat, and how much heat is going into it. Everything else about a fireground is visible
--- in the world and has no business on the screen.
---
--- It exists because the screen effects alone were ambiguous. Vision washing out could have
--- been heat, smoke, or the bottle running dry, and there was no way to tell which -- so the
--- effect read as the resource misbehaving rather than as information. An effect that
--- changes what you should do has to say what it is.
---
--- Rows appear only when they have something to say. A firefighter with a full bottle and a
--- good coat sees nothing at all, which is the correct amount of HUD for standing at a
--- station.

MIFire = MIFire or {}

local Hud = { visible = false }

--- Last payload sent, so an unchanged frame costs nothing on the NUI bridge.
local lastSignature = nil

---@return table|nil
local function build()
    local air, gear, heat = nil, nil, nil

    local scbaWorn, scbaActive, scbaAir, scbaCapacity = exports.mi_fire:GetScbaState()
    if scbaWorn then
        air = {
            worn = true,
            active = scbaActive == true,
            seconds = scbaAir or 0.0,
            capacity = scbaCapacity or MIFireScba.air.capacitySeconds,
            lowAt = MIFireScba.air.lowAirAt,
            criticalAt = MIFireScba.air.criticalAt,
        }
    end

    local tier, worn, integrity, capacity = exports.mi_fire:GetGearState()
    if worn and (capacity or 0) > 0 then
        local condition, fraction = MIFire.Integrity.condition(
            integrity, capacity, MIFireGear.integrity)

        gear = {
            worn = true,
            tier = tier,
            condition = condition,
            fraction = fraction,
            condemned = MIFire.Integrity.isCondemned(integrity, capacity, MIFireGear.integrity),
        }
    end

    local exposure = exports.mi_fire:GetExposure()
    if exposure and (exposure.heatFraction or 0) > 0 then
        heat = { fraction = exposure.heatFraction, burning = exposure.burning == true }
    end

    if not air and not gear and not heat then return nil end

    return { action = 'hud', air = air, gear = gear, heat = heat }
end

--- A cheap fingerprint, rounded to what the HUD can actually display. Air ticks every
--- second and heat every fraction, so sending on any change at all would push a message
--- several times a second for a display that cannot show the difference.
---@param payload table|nil
---@return string
local function signature(payload)
    if not payload then return 'none' end

    return ('%s|%s|%s|%s|%s'):format(
        payload.air and math.floor(payload.air.seconds) or '-',
        payload.air and tostring(payload.air.active) or '-',
        payload.gear and math.floor(payload.gear.fraction * 100) or '-',
        payload.gear and payload.gear.condition or '-',
        payload.heat and math.floor(payload.heat.fraction * 100) or '-')
end

CreateThread(function()
    while not MIFire.ready do Wait(250) end

    while true do
        Wait(500)

        local payload = build()
        local sig = signature(payload)

        if sig ~= lastSignature then
            lastSignature = sig
            SendNUIMessage(payload or { action = 'hud' })
        end
    end
end)

--- Clear the display on teardown, or a restart leaves a frozen air gauge on screen.
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SendNUIMessage({ action = 'hud' })
end)

MIFire.Hud = Hud

return Hud
