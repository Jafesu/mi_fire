--- Smoke rendering.
---
--- Each of the four attributes drives a different particle property, which is what makes
--- the smoke actually readable rather than merely present:
---
---   volume    -> scale
---   density   -> alpha
---   colour    -> tint, via SetParticleFxLoopedColour
---   velocity  -> which effect, and how fast it is re-emitted
---
--- Two plumes per fire. One at the seat showing the smoke as it leaves, and a second above
--- it showing the same smoke after travel -- cooler, paler, thinner. That pairing is what
--- lets someone standing outside see that black smoke at the base is coming out grey at the
--- top, which is how the seat of a fire gets located.

MIFire = MIFire or {}

local SmokeClient = {}

local Util = MIFire.Util

---@type table<string, table> live plumes, keyed by incident
local plumes = {}

---@type table<string, table> latest reading per incident
local readings = {}

local assets = {}

-- ---------------------------------------------------------------------------

---@param dict string
---@return boolean
local function ensureAsset(dict)
    if assets[dict] ~= nil then return assets[dict] end

    if not HasNamedPtfxAssetLoaded(dict) then
        RequestNamedPtfxAsset(dict)
        local deadline = GetGameTimer() + 5000
        while not HasNamedPtfxAssetLoaded(dict) do
            if GetGameTimer() > deadline then
                assets[dict] = false
                Util.warn('smoke particle dictionary "%s" would not load', dict)
                return false
            end
            Wait(0)
        end
    end

    assets[dict] = true
    return true
end

--- Which effect to use.
---
--- Turbulent smoke needs an agitated, boiling effect rather than a lazy column -- that
--- difference is the single most important thing to be able to see, because turbulent means
--- the compartment has stopped absorbing heat.
---@param reading table
---@return string dict
---@return string name
local function effectFor(reading)
    local visual = MIFireSmoke.visual or {}

    if reading.turbulent then
        return visual.turbulentDict or 'core', visual.turbulentName or 'ent_amb_smoke_foundry'
    end

    return visual.laminarDict or 'scr_agencyheistb',
        visual.laminarName or 'scr_env_agency3b_smoke'
end

---@param incidentId string
local function stop(incidentId)
    local plume = plumes[incidentId]
    if not plume then return end

    for i = 1, #plume.handles do
        if DoesParticleFxLoopedExist(plume.handles[i]) then
            StopParticleFxLooped(plume.handles[i], false)
        end
    end

    plumes[incidentId] = nil
end

--- Start or restart a plume.
---@param incidentId string
---@param reading table
local function start(incidentId, reading)
    stop(incidentId)

    local dict, name = effectFor(reading)
    if not ensureAsset(dict) then return end

    local visual = MIFireSmoke.visual or {}
    local handles = {}

    -- Two layers: the smoke as it leaves, and the same smoke after travel. The second is
    -- higher, paler and thinner, which is what a cooling plume looks like from outside.
    local layers = {
        { z = visual.seatHeight or 1.2, travel = 0.0, scale = 1.0 },
        { z = visual.driftHeight or 5.0, travel = visual.driftTravel or 14.0, scale = 1.45 },
    }

    for i = 1, #layers do
        local layer = layers[i]

        UseParticleFxAssetNextCall(dict)
        local handle = StartParticleFxLoopedAtCoord(
            name,
            reading.coords.x, reading.coords.y, reading.coords.z + layer.z,
            0.0, 0.0, 0.0,
            (0.6 + reading.volume * 1.8) * layer.scale,
            false, false, false, false)

        if handle and handle ~= 0 and handle ~= -1 then
            handles[#handles + 1] = handle
            MIFire.trackPtfx(handle)
        end
    end

    if #handles == 0 then return end

    plumes[incidentId] = {
        handles = handles,
        layers = layers,
        turbulent = reading.turbulent,
        stage = reading.stage,
    }
end

--- Apply the four attributes to a live plume.
---@param incidentId string
---@param reading table
local function apply(incidentId, reading)
    local plume = plumes[incidentId]
    if not plume then return end

    -- A change of effect needs a restart; a change of attributes does not.
    if plume.turbulent ~= reading.turbulent then
        return start(incidentId, reading)
    end

    for i = 1, #plume.handles do
        local handle = plume.handles[i]
        local layer = plume.layers[i]

        if DoesParticleFxLoopedExist(handle) then
            -- Colour after travel, so the upper layer is visibly paler than the base. This
            -- is the reading that locates the seat.
            local colour = MIFire.Smoke.colour(reading.stage, layer.travel, MIFireSmoke)

            SetParticleFxLoopedColour(handle,
                colour.r / 255.0, colour.g / 255.0, colour.b / 255.0, false)

            -- Density is opacity. Thick smoke is smoke you cannot see through, and it is
            -- also the smoke that is full of unburned fuel.
            local thinning = i == 1 and 1.0 or 0.55
            local alpha = (0.25 + reading.density * 0.75) * thinning

            -- A pulsing plume is a starved fire breathing in and out -- the most
            -- recognisable backdraft sign there is, and worth rendering literally.
            if reading.pulsing then
                alpha = alpha * (0.55 + 0.45 * math.abs(math.sin(GetGameTimer() / 900.0)))
            end

            SetParticleFxLoopedAlpha(handle, alpha)
            SetParticleFxLoopedScale(handle,
                (0.6 + reading.volume * 1.8) * layer.scale)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Sync
-- ---------------------------------------------------------------------------

RegisterNetEvent('mi_fire:client:smoke', function(incidentId, reading)
    if not reading then
        readings[incidentId] = nil
        stop(incidentId)
        return
    end

    readings[incidentId] = reading
end)

RegisterNetEvent('mi_fire:client:teardown', function()
    for incidentId in pairs(plumes) do stop(incidentId) end
    plumes, readings = {}, {}
end)

--- Render by distance, and keep pulsing plumes updated more often.
CreateThread(function()
    while true do
        local anyPulsing = false
        for _, reading in pairs(readings) do
            if reading.pulsing then anyPulsing = true break end
        end

        Wait(anyPulsing and 100 or 600)

        if MIFire.ready and next(readings) ~= nil then
            local playerCoords = GetEntityCoords(cache.ped)
            local renderSq = (Config.renderDistance * 1.5) ^ 2

            for incidentId, reading in pairs(readings) do
                local distSq = Util.distance3dSq(
                    playerCoords.x, playerCoords.y, playerCoords.z,
                    reading.coords.x, reading.coords.y, reading.coords.z)

                -- Smoke is visible from further away than fire is, which is the point of
                -- it -- you read the smoke on approach, before you can see any flame.
                if distSq <= renderSq and reading.volume > 0.05 then
                    if not plumes[incidentId] then
                        start(incidentId, reading)
                    else
                        apply(incidentId, reading)
                    end
                elseif plumes[incidentId] then
                    stop(incidentId)
                end
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Flashover and backdraft
-- ---------------------------------------------------------------------------

RegisterNetEvent('mi_fire:client:fireEvent', function(data)
    if type(data) ~= 'table' or type(data.coords) ~= 'table' then return end

    local coords = vec3(data.coords.x, data.coords.y, data.coords.z)
    local distance = #(GetEntityCoords(cache.ped) - coords)

    if distance > (data.radius or 10.0) * 2.5 then return end

    local inside = distance <= (data.radius or 10.0)

    if data.kind == 'backdraft' then
        AddExplosion(coords.x, coords.y, coords.z, 4, 0.0, true, false, 0.0)
        if inside then
            -- Thrown clear, which is what actually happens to anyone in the doorway.
            local direction = (GetEntityCoords(cache.ped) - coords)
            SetEntityVelocity(cache.ped,
                direction.x * (data.knockback or 10.0) / math.max(1.0, distance),
                direction.y * (data.knockback or 10.0) / math.max(1.0, distance),
                4.0)
            SetPedToRagdoll(cache.ped, 3000, 3000, 0, false, false, false)
        end
    else
        StartScreenEffect('MP_Bull_TossIn', 0, false)
        Wait(600)
        StopScreenEffect('MP_Bull_TossIn')
    end

    if inside and data.damage then
        MIFire.Medical.damage(data.damage * (1.0 - distance / math.max(1.0, data.radius)))
    end

    ShakeGameplayCam('MEDIUM_EXPLOSION_SHAKE', inside and 1.5 or 0.6)

    if lib and lib.notify then
        lib.notify({
            title = data.kind == 'backdraft' and 'BACKDRAFT' or 'FLASHOVER',
            description = data.kind == 'backdraft'
                and 'The compartment found air all at once.'
                or 'The room lit off.',
            type = 'error',
            duration = 8000,
        })
    end
end)

-- ---------------------------------------------------------------------------
-- Reading it
-- ---------------------------------------------------------------------------

--- The nearest incident with visible smoke, for a size-up.
---@return string|nil incidentId
---@return number distance
function SmokeClient.nearest()
    local playerCoords = GetEntityCoords(cache.ped)
    local best, bestDist

    for incidentId, reading in pairs(readings) do
        local distance = #(playerCoords
            - vec3(reading.coords.x, reading.coords.y, reading.coords.z))

        if distance <= MIFireSmoke.sizeup.maxDistance
            and (not bestDist or distance < bestDist) then
            best, bestDist = incidentId, distance
        end
    end

    return best, bestDist or 0
end

exports('GetSmokeReading', function(incidentId)
    return readings[incidentId]
end)

MIFire.SmokeClient = SmokeClient

return SmokeClient
