--- PASS devices, client side.
---
--- Plays what the server says is happening. The phase machine and the motion detection are
--- both server-side; this file only makes noise and draws.
---
--- Audio has two backends because the right one needs assets that do not exist yet:
---
---   **nui**    HTML5 audio with volume and stereo pan computed from relative position.
---              Works the moment sound files are dropped in, needs no tooling. What it
---              cannot do is occlusion -- a PASS through a wall sounds like one in the
---              open, and muffling is a real cue when searching for someone.
---
---   **native** A positioned GTA sound. True 3D including occlusion, but nothing in the
---              game sounds like a PASS, so it reads as a generic alarm.
---
---   **auto**   NUI when files are configured, native otherwise. So it is audible on a
---              fresh install and correct once someone adds the sounds.
---
--- An engine audio pack (.awc + .dat54.rel) would beat both and is the eventual answer;
--- when it exists it becomes a third backend and nothing else here changes.

MIFire = MIFire or {}

local PassClient = {}

local Util = MIFire.Util
local Pass = MIFire.Pass

---@type table<integer, table> devices this client can currently hear
local audible = {}

---@type table<integer, integer> blips for firefighters in full alarm
local maydayBlips = {}

-- ---------------------------------------------------------------------------
-- Backend selection
-- ---------------------------------------------------------------------------

--- Which backend to use, resolved once.
---@return string
local function backend()
    local audio = MIFireScba.audio or {}
    if audio.backend and audio.backend ~= 'auto' then return audio.backend end

    -- Auto: NUI as soon as there is a full-alarm file. The pre-alarm file is optional --
    -- without it the full sound is played in bursts -- so requiring both here would fall
    -- back to native on a perfectly working setup.
    if audio.files and audio.files.full then return 'nui' end
    return 'native'
end

-- ---------------------------------------------------------------------------
-- Positional maths
-- ---------------------------------------------------------------------------

--- Volume and stereo pan for a sound at `coords`, heard from the player's camera.
---
--- Pan comes from the bearing relative to where the camera is looking, so turning your
--- head moves the sound across the stereo field. That is most of what makes NUI audio
--- feel positioned rather than flat, and it is the cue you actually use when hunting for
--- an alarm.
---@param coords table
---@param range number
---@return number volume 0-1
---@return number pan -1 (left) to 1 (right)
local function spatialise(coords, range)
    local listener = GetGameplayCamCoord()
    local target = vec3(coords.x, coords.y, coords.z)
    local delta = target - listener
    local distance = #delta

    if distance >= range then return 0.0, 0.0 end

    -- Inverse falloff rather than linear: a PASS should stay audible across a room and
    -- fade off sharply beyond its range, not dim evenly the whole way.
    local volume = 1.0 - (distance / range)
    volume = volume * volume

    -- Bearing relative to the camera's facing, projected onto the horizontal plane.
    local camRot = GetGameplayCamRot(2)
    local heading = math.rad(camRot.z)
    local forward = vec2(-math.sin(heading), math.cos(heading))
    local right = vec2(forward.y, -forward.x)

    local flat = vec2(delta.x, delta.y)
    local flatLength = #flat

    local pan = 0.0
    if flatLength > 0.01 then
        flat = flat / flatLength
        pan = (flat.x * right.x) + (flat.y * right.y)
    end

    return Util.clamp(volume, 0.0, 1.0), Util.clamp(pan, -1.0, 1.0)
end

-- ---------------------------------------------------------------------------
-- Playback
-- ---------------------------------------------------------------------------


---@param entry table
local function playNui(entry)
    local audio = MIFireScba.audio
    local isFull = entry.phase == Pass.Phase.FULL

    -- With no dedicated pre-alarm file, the full-alarm sound is played in short repeating
    -- bursts instead. That reads convincingly as chirping and means one file covers both
    -- phases -- splitting the audio improves it but is not required.
    local file = isFull and audio.files.full or (audio.files.preAlarm or audio.files.full)
    if not file then return end

    local burst = (not isFull) and (audio.files.preAlarm == nil)

    local volume, pan = spatialise(entry.coords, entry.range)

    local message = {
        action = 'pass',
        id = entry.source,
        file = file,
        volume = volume * (audio.volume or 1.0),
        pan = pan,
        loop = true,
        burst = burst,
    }

    if burst then
        -- The gap shortens as the pre-alarm escalates, so the chirp speeds up on its way
        -- to full alarm. That acceleration is what gives the wearer a reason to move.
        local cfg = audio.burst or {}
        local atStart = cfg.gapMsAtStart or 1100
        local atFull = cfg.gapMsAtFull or 320

        message.burstMs = cfg.burstMs or 220
        message.gapMs = math.floor(atStart + (atFull - atStart) * (entry.escalation or 0))
    else
        -- A dedicated pre-alarm file carries its own character, so it is only sped up.
        message.rate = isFull and 1.0 or (1.0 + (entry.escalation or 0) * 0.4)
    end

    SendNUIMessage(message)
end

---@param sourceId integer
local function stopNui(sourceId)
    SendNUIMessage({ action = 'passStop', id = sourceId })
end

--- Native fallback. Positioned by the engine, so occlusion works -- it just does not sound
--- like a PASS.
---@param entry table
local function playNative(entry)
    local audio = MIFireScba.audio or {}
    local set = audio.native or {}

    local name = entry.phase == Pass.Phase.FULL
        and (set.fullName or 'Beep_Red') or (set.preAlarmName or 'Beep_Red')
    local soundset = entry.phase == Pass.Phase.FULL
        and (set.fullSet or 'DLC_HEIST_HACKING_SNAKE_SOUNDS')
        or (set.preAlarmSet or 'DLC_HEIST_HACKING_SNAKE_SOUNDS')

    PlaySoundFromCoord(-1, name, entry.coords.x, entry.coords.y, entry.coords.z,
        soundset, false, math.floor(entry.range), false)
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

RegisterNetEvent('mi_fire:client:passState', function(payload)
    if type(payload) ~= 'table' or not payload.source then return end

    if not Pass.isAudible(payload.phase) then
        if audible[payload.source] then
            if backend() == 'nui' then stopNui(payload.source) end
            audible[payload.source] = nil
        end
        return
    end

    local existing = audible[payload.source]
    audible[payload.source] = payload
    payload.nextNativeAt = existing and existing.nextNativeAt or 0

    if backend() == 'nui' then
        playNui(payload)
    end
end)

--- Keep NUI audio positioned as the listener moves. Native audio is positioned by the
--- engine and needs no help, which is the one place it is strictly better.
CreateThread(function()
    while true do
        Wait(next(audible) and 200 or 1000)

        if next(audible) then
            local mode = backend()

            for sourceId, entry in pairs(audible) do
                if mode == 'nui' then
                    playNui(entry)
                else
                    -- Native sounds are one-shots, so they are re-triggered on a cadence
                    -- that speeds up with escalation.
                    local now = GetGameTimer()
                    if now >= (entry.nextNativeAt or 0) then
                        playNative(entry)
                        local gap = entry.phase == Pass.Phase.FULL and 700
                            or math.floor(1400 - entry.escalation * 700)
                        entry.nextNativeAt = now + gap
                    end
                end

                -- Drop anything that has gone silent without telling us, so a disconnect
                -- mid-alarm does not leave a sound playing forever.
                if not audible[sourceId] then
                    if mode == 'nui' then stopNui(sourceId) end
                end
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Mayday
-- ---------------------------------------------------------------------------

--- A full alarm is a mayday: every on-duty firefighter is told, wherever they are, and
--- gets a blip. The alarm is for the people looking, not for the wearer.
RegisterNetEvent('mi_fire:client:mayday', function(data)
    if type(data) ~= 'table' or type(data.coords) ~= 'table' then return end

    if lib and lib.notify then
        lib.notify({
            title = 'MAYDAY',
            description = ('%s -- PASS alarm activated'):format(data.name or 'A firefighter'),
            type = 'error',
            duration = 10000,
        })
    end

    if maydayBlips[data.source] then
        RemoveBlip(maydayBlips[data.source])
    end

    local blip = AddBlipForCoord(data.coords.x, data.coords.y, data.coords.z)
    SetBlipSprite(blip, 303)
    SetBlipColour(blip, 1)
    SetBlipScale(blip, 1.2)
    SetBlipFlashes(blip, true)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(('MAYDAY -- %s'):format(data.name or 'firefighter'))
    EndTextCommandSetBlipName(blip)

    maydayBlips[data.source] = blip
    MIFire.trackBlip(blip)

    PlaySoundFrontend(-1, 'Lose_1st', 'GTAO_FM_Events_Soundset', true)
end)

--- Clear the blip once that device stops alarming.
CreateThread(function()
    while true do
        Wait(2000)
        for sourceId, blip in pairs(maydayBlips) do
            if not audible[sourceId] then
                if DoesBlipExist(blip) then RemoveBlip(blip) end
                maydayBlips[sourceId] = nil
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Controls
-- ---------------------------------------------------------------------------

CreateThread(function()
    while not MIFire.ready do Wait(250) end

    lib.addKeybind({
        name = 'mi_fire_pass',
        description = 'Activate PASS alarm (manual)',
        defaultKey = MIFireScba.pass.manualKey or 'K',
        onPressed = function()
            TriggerServerEvent('mi_fire:server:passActivate')
        end,
    })

    RegisterCommand('passreset', function()
        TriggerServerEvent('mi_fire:server:passReset')
    end, false)

    -- Resetting someone else's device is a world interaction, so it is a target option.
    MIFire.Target.addGlobalPed({
        {
            name = 'mi_fire:passReset',
            icon = 'bell-slash',
            label = 'Reset PASS alarm',
            distance = 2.0,
            requiresFirefighter = true,
            canInteract = function(entity)
                if not IsPedAPlayer(entity) then return false end
                local player = NetworkGetPlayerIndexFromPed(entity)
                if not player then return false end
                local serverId = GetPlayerServerId(player)
                local entry = audible[serverId]
                return entry ~= nil and entry.phase == Pass.Phase.FULL
            end,
            onSelect = function(data)
                local player = NetworkGetPlayerIndexFromPed(data.entity)
                if player then
                    TriggerServerEvent('mi_fire:server:passReset', GetPlayerServerId(player))
                end
            end,
        },
    })
end)

RegisterNetEvent('mi_fire:client:teardown', function()
    for sourceId in pairs(audible) do stopNui(sourceId) end
    for _, blip in pairs(maydayBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    audible = {}
    maydayBlips = {}
end)

MIFire.PassClient = PassClient

return PassClient
