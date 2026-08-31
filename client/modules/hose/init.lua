--- Hose lines, client side.
---
--- Draws the rope, carries the nozzle, and asks the server for everything. It decides nothing:
--- whether a line exists, who is on it and whether it has water in it all live server-side,
--- and this file is told.
---
--- The rope is a real GTA rope rather than a prop. It is simulated, it collides, it sags under
--- its own weight and it follows both ends — nothing anyone could author as a static model
--- would behave better, and rope type 4 is what the fire hose resource already on this machine
--- uses rather than a number picked off a list.

MIFire = MIFire or {}

local HoseClient = {}

local Util = MIFire.Util
local Hose = MIFire.Hose
local Target = MIFire.Target

--- Resolved at call time rather than captured at load time.
---
--- A file-scope `local ApparatusClient = MIFire.ApparatusClient` binds whatever happened to be
--- there when this file loaded, and nothing in the file says which other files have loaded
--- yet. It was nil, and the only symptom was an error the first time somebody aimed at a
--- truck. The manifest order is fixed too, but one of those is a rule you have to remember and
--- the other cannot go wrong.
---@return table
local function apparatus()
    return MIFire.ApparatusClient
end

--- What the server says exists, keyed by line id.
---@type table<string, table>
local lines = {}

--- What we have actually drawn, keyed by line id.
---@type table<string, table>
local drawn = {}

--- The line this client is on, if any.
local mine = nil

--- Is this server id on this line?
---
--- `crew` arrives as a list rather than a set, so this is a scan. Crews are three or four
--- people; the alternative was a table whose keys change shape depending on which server ids
--- happen to be in it.
---@param line table
---@param serverId integer
---@return boolean
local function onCrew(line, serverId)
    for i = 1, #(line.crew or {}) do
        if line.crew[i] == serverId then return true end
    end

    return false
end

local texturesLoaded = false

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

local function ensureTextures()
    if texturesLoaded then return true end

    RopeLoadTextures()

    local waited = 0
    while not RopeAreTexturesLoaded() and waited < 3000 do
        Wait(50)
        waited = waited + 50
    end

    texturesLoaded = RopeAreTexturesLoaded()

    if not texturesLoaded then
        Util.warn('rope textures would not load; hose lines will not draw')
    end

    return texturesLoaded
end

--- Put the nozzle in the hands, as an actual equipped weapon.
---
--- **This used to make a world object with `CreateWeaponObject` and glue it to the hand bone,
--- and that was the wrong call.** An attached object is scenery: it cannot be fired, it has no
--- stance, and the ped stands there with a thing stuck to their fist. Water has to come out of
--- a nozzle, so the nozzle has to be a weapon the game has actually equipped.
---
--- The note that used to be here said `GiveWeaponToPed` gets stripped by ox_inventory within a
--- second. **That was wrong too, and it is worth spelling out because it sent the whole thing
--- down a dead end.** It was concluded while the weapon had no archetype -- and a weapon that
--- does not exist, when given, is absent immediately afterwards, which looks exactly like
--- something taking it away. It was never the inventory. There was simply no weapon.
---
--- A weapon asset still has to be requested and waited on, the same as a model. Missing that
--- returns nothing and looks, once again, exactly like a missing archetype.
---@param ped integer
---@return boolean equipped
local function equipNozzle(ped)
    local name = MIFireHose.visuals.nozzleWeapon
    if not name then return false end

    local hash = joaat(name)

    if not HasWeaponAssetLoaded(hash) then
        RequestWeaponAsset(hash, 31, 0)

        local waited = 0
        while not HasWeaponAssetLoaded(hash) and waited < 2500 do
            Wait(50)
            waited = waited + 50
        end
    end

    if not HasWeaponAssetLoaded(hash) then
        Util.warn('nozzle weapon "%s" would not load. Its weapons.meta and '
            .. 'weaponarchetypes.meta must be declared with `data_file` **and** listed in '
            .. '`files`, and the client has to reconnect after they are added. Falling back '
            .. 'to a prop.', name)
        return false
    end

    -- Ammo is nominal. Nothing about the water is decided here: how much reaches the fire is
    -- the server's business, from the line's flow. The weapon exists to be held and aimed.
    GiveWeaponToPed(ped, hash, 1000, false, true)
    SetCurrentPedWeapon(ped, hash, true)

    return HasPedGotWeapon(ped, hash, false)
end

---@param ped integer
local function unequipNozzle(ped)
    local name = MIFireHose.visuals.nozzleWeapon
    if not name then return end

    local hash = joaat(name)
    if HasPedGotWeapon(ped, hash, false) then RemoveWeaponFromPed(ped, hash) end
end

--- How a charged line is carried.
---
--- Two different clipsets, two different natives, and picking the wrong pairing is what T-posed
--- a firefighter. The distinction is the whole thing:
---
---   **movement clipset** -- `SetPedMovementClipset`. The walk, run and idle. Names generally
---                           begin `move_`.
---
---   **weapon clipset**   -- `SetPedStrafeClipset`. How the thing is actually held and aimed.
---                           This is the one that decides whether a nozzle looks like a pistol
---                           or a minigun.
---
--- `weapons@heavy@minigun` is a *weapon* clipset -- it is what the game own weaponanimations
--- lists as the minigun `WeaponClipSetHash`. Passing it to `SetPedMovementClipset` T-poses,
--- because a weapon clipset has no walk or idle clips in it and the skeleton falls back to its
--- bind pose. `HasAnimSetLoaded` answers true either way, so there is no check to write, only
--- the right native to call.
---@param ped integer
---@param clipset string|nil
---@return boolean applied
local function applyNozzleStrafe(ped, clipset)
    clipset = clipset or MIFireHose.visuals.nozzleStrafeClipset
    if not clipset or clipset == '' then return false end

    RequestAnimSet(clipset)

    local waited = 0
    while not HasAnimSetLoaded(clipset) and waited < 2000 do
        Wait(50)
        waited = waited + 50
    end

    if not HasAnimSetLoaded(clipset) then
        Util.warn('nozzle strafe clipset "%s" would not load', clipset)
        return false
    end

    SetPedStrafeClipset(ped, clipset)
    return true
end

--- The walk, as opposed to the hold. Usually not needed -- the weapon clipset above is what
--- changes how the nozzle is carried.
---@param ped integer
---@param clipset string|nil
---@return boolean applied
local function applyNozzleHold(ped, clipset)
    clipset = clipset or MIFireHose.visuals.nozzleClipset
    if not clipset or clipset == '' then return false end

    RequestAnimSet(clipset)

    local waited = 0
    while not HasAnimSetLoaded(clipset) and waited < 2000 do
        Wait(50)
        waited = waited + 50
    end

    if not HasAnimSetLoaded(clipset) then
        Util.warn('nozzle movement clipset "%s" would not load', clipset)
        return false
    end

    SetPedMovementClipset(ped, clipset, 1.0)
    return true
end

--- Both of them, because either one left behind outlasts the nozzle.
---@param ped integer
local function clearNozzleHold(ped)
    ResetPedMovementClipset(ped, 0.0)
    ResetPedStrafeClipset(ped)
end

--- A plain prop, for a server without the weapon registered.
---@param ped integer
---@return integer|nil
local function attachNozzleProp(ped)
    local name = MIFireHose.visuals.nozzleProp
    if not name or name == '' then return nil end

    local model = joaat(name)

    RequestModel(model)

    local waited = 0
    while not HasModelLoaded(model) and waited < 5000 do
        Wait(50)
        waited = waited + 50
    end

    if not HasModelLoaded(model) then
        Util.warn('nozzle prop "%s" would not load', name)
        return nil
    end

    local coords = GetEntityCoords(ped)
    local prop = CreateObject(model, coords.x, coords.y, coords.z, true, true, false)

    AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, 57005),
        0.12, 0.02, -0.02, -75.0, 12.0, 0.0, true, true, false, true, 1, true)

    SetModelAsNoLongerNeeded(model)

    return prop
end

--- Which way a fitting points, in the world.
---
--- The port's heading is relative to the vehicle, so a rig parked at any angle still has its
--- discharge pointing out of the side it is on. Used to lay the last few rope vertices along
--- the outlet's axis, which is what makes the hose leave the coupling straight.
---@param entity integer
---@param port table|nil
---@return vector3
local function portAxis(entity, port)
    if not port or not port.heading then return vector3(0.0, 0.0, 0.0) end

    local heading = math.rad(GetEntityHeading(entity) + port.heading)
    return vector3(-math.sin(heading), math.cos(heading), 0.0)
end

--- Where a line starts, in the world.
---@param line table
---@return vector3|nil
---@return integer|nil vehicle
---@return table|nil port
local function sourceCoords(line)
    if not line.sourceNet then return nil end
    if not NetworkDoesNetworkIdExist(line.sourceNet) then return nil end

    local entity = NetToVeh(line.sourceNet)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end

    local profile = apparatus().profile(entity)
    local port = profile and MIFire.Apparatus.port(profile, line.sourcePort)

    if not port then return GetEntityCoords(entity), entity, nil end

    return apparatus().portCoords(entity, port), entity, port
end

---@param id string
---@param line table
local function draw(id, line)
    if MIFireHose.visuals.enabled == false then
        drawn[id] = nil
        return
    end
    if not ensureTextures() then return end

    local from, vehicle, port = sourceCoords(line)

    if not from then
        drawn[id] = nil
        return
    end

    local holder = line.nozzleHolder and GetPlayerFromServerId(line.nozzleHolder)
    local holderPed = holder and holder ~= -1 and GetPlayerPed(holder) or nil

    -- Nobody is holding it. A dropped line is real and worth drawing eventually, but it needs
    -- a world position to hang from that nothing currently records.
    if not holderPed or not DoesEntityExist(holderPed) then
        drawn[id] = nil
        return
    end

    local size = MIFireHose.sizes[line.diameter] or {}
    local maxLength = Hose.lengthFeet(size, line.sections) * 0.3048

    local ropeType = line.diameter >= (MIFireHose.visuals.largeAbove or 2.5)
        and MIFireHose.visuals.ropeTypeLarge
        or MIFireHose.visuals.ropeType

    -- Started short and paid out. A rope created at its full two hundred feet between two
    -- points five metres apart is a heap; one created at exactly the span is a tow cable.
    -- Vertex count follows length, so a short rope is a rope with nothing in the middle.
    local initial = MIFireHose.visuals.initialLength or 25.0

    local rope = AddRope(from.x, from.y, from.z, 0.0, 0.0, 0.0,
        maxLength, ropeType, math.min(initial, maxLength), 0.5, 1.0,
        false, true, false, 1.0, false, 0)

    if not rope or rope == 0 then
        Util.warn('AddRope failed for line %s -- check the rope type in config/hose.lua', id)
        drawn[id] = nil
        return
    end

    -- The claim was already staked by the caller; fill in what it needs to tear this down if
    -- the build fails partway.
    drawn[id] = drawn[id] or {}
    drawn[id].rope = rope
    drawn[id].vehicle = vehicle
    drawn[id].pending = true

    -- A rope has no vertices until it has been simulated once.
    --
    -- How many it ends up with is the rope *type's* business, not the length's -- type 6 comes
    -- back with three however long it is made. Demanding eight and refusing to draw below that
    -- meant the thickest type could never be used, which was the wrong lesson to draw from a
    -- rope that shook: the shaking was pinning every vertex there was, and the fix is to pin
    -- fewer rather than to insist on more.
    local vertices = 0
    local waited = 0

    while vertices < 2 and waited < 500 do
        Wait(0)
        vertices = GetRopeVertexCount(rope) or 0
        waited = waited + 16
    end

    if vertices < 2 then
        Util.warn('rope for line %s never simulated', id)
        if DoesRopeExist(rope) then DeleteRope(rope) end
        drawn[id] = nil
        return
    end

    if not lines[id] or not DoesEntityExist(holderPed) then
        if DoesRopeExist(rope) then DeleteRope(rope) end
        drawn[id] = nil
        return
    end

    -- Simulated, or it draws as a straight taut line between its ends.
    ActivatePhysics(rope)

    drawn[id] = {
        rope = rope,
        vehicle = vehicle,
        nozzle = nil,
        holder = holderPed,
        vertices = vertices,
        length = math.min(initial, maxLength),
        maxLength = maxLength,
        port = port,
    }

end

---@param id string
local function undraw(id)
    local entry = drawn[id]
    if not entry then return end

    if entry.rope and DoesRopeExist(entry.rope) then DeleteRope(entry.rope) end

    drawn[id] = nil
end

--- The nozzle in our own hands.
---
--- Kept entirely apart from the rope. It used to be created inside `draw`, which meant it only
--- appeared when a rope did -- and a rope only draws once the line is coupled to something. So
--- a crew walking an uncoupled line out from the bed had nothing in their hands the whole way,
--- which is exactly the part of the job where they are carrying a nozzle.
local heldNozzle = nil

--- Whether the weapon itself is equipped, as opposed to the fallback prop being attached.
local nozzleEquipped = false

--- How many times it has had to be put back. See `reconcileNozzle`.
local reEquips = 0

--- The nozzle in our own hands.
---
--- Kept apart from the rope, which it used to be built alongside -- so it only appeared once a
--- line was coupled, and a crew walking an uncoupled line out from the bed carried nothing the
--- whole way.
---
--- The weapon is re-checked rather than assumed. Something else on a server can take a weapon
--- off a ped, and the failure is silent: the nozzle vanishes from the hand and the line goes on
--- flowing. If it keeps happening that is said out loud once, because the cause is outside this
--- resource and guessing at it from in here wastes an evening.
local function reconcileNozzle()
    local line = mine and lines[mine]
    local holding = line ~= nil and line.nozzleHolder == GetPlayerServerId(PlayerId())

    if holding then
        if not nozzleEquipped and not heldNozzle then
            nozzleEquipped = equipNozzle(cache.ped)

            if nozzleEquipped then
                -- Only once the weapon is genuinely in hand. Posing an empty-handed ped with a
                -- weapon stance is how the T-pose happened: the strip below removed the weapon
                -- and the clipset stayed.
                applyNozzleStrafe(cache.ped)
                applyNozzleStrafe(cache.ped)
            applyNozzleHold(cache.ped)
            else
                heldNozzle = attachNozzleProp(cache.ped)
            end

        elseif nozzleEquipped then
            local hash = joaat(MIFireHose.visuals.nozzleWeapon)

            if not HasPedGotWeapon(cache.ped, hash, false) then
                reEquips = reEquips + 1

                -- The stance goes with the weapon. Leaving it applied to an empty-handed ped
                -- is what produced a T-posing firefighter rather than a bare-handed one.
                clearNozzleHold(cache.ped)

                if reEquips == 4 then
                    Util.warn('the nozzle weapon keeps being removed from this ped. '
                        .. 'ox_inventory disarms any weapon it did not equip itself unless the '
                        .. 'weapon is in its ignore list -- add to server.cfg: '
                        .. 'setr inventory:ignoreweapons ["%s"]', MIFireHose.visuals.nozzleWeapon)
                end

                nozzleEquipped = equipNozzle(cache.ped)

                if nozzleEquipped then
                    applyNozzleStrafe(cache.ped)
                    applyNozzleHold(cache.ped)
                end
            end
        end

    elseif nozzleEquipped or heldNozzle then
        if nozzleEquipped then
            unequipNozzle(cache.ped)
            clearNozzleHold(cache.ped)
        end

        if heldNozzle and DoesEntityExist(heldNozzle) then DeleteEntity(heldNozzle) end

        nozzleEquipped = false
        heldNozzle = nil
        reEquips = 0
    end
end

-- ---------------------------------------------------------------------------
-- Sync
-- ---------------------------------------------------------------------------

--- What the server says exists.
---
--- Tears down and records; it does not build. Putting a rope up is the reconcile loop's job,
--- so a rope that fails to build or is torn down by a hiccup comes back on its own rather than
--- waiting for the server to send another update.
RegisterNetEvent('mi_fire:client:hoseLine', function(id, line)
    if type(id) ~= 'string' then return end

    if not line then
        undraw(id)
        lines[id] = nil
        if mine == id then mine = nil end
        return
    end

    local previous = lines[id]
    lines[id] = line

    if onCrew(line, GetPlayerServerId(PlayerId())) then
        mine = id
    elseif mine == id then
        mine = nil
    end

    -- Only when something that changes the rope's *shape* changed. Rebuilding on every update
    -- would tear the hose down once a second, since the pump syncs every charged line on its
    -- tick.
    if previous and (previous.sourceNet ~= line.sourceNet
        or previous.nozzleHolder ~= line.nozzleHolder
        or previous.sections ~= line.sections) then
        undraw(id)
    end
end)

--- Reconcile what is drawn against what should be, every frame.
---
--- **Reconciling rather than reacting.** The rope used to be built in response to a sync event
--- and torn down by the same handler, which had two failure modes that both showed up in play:
--- a rope that failed to build never tried again, and a rope torn down by a momentary hiccup --
--- a network id not resolving for one frame, say -- stayed gone until the server happened to
--- send another update. The line appearing and then vanishing on connect was the second of
--- those.
---
--- Now the loop asks what should exist and makes it so. A transient failure costs a frame.
---
--- Holding the ends is the other half, and two things in it matter, neither obvious:
---
--- **Neither end is attached to an entity.** `AttachRopeToEntity` and `AttachEntitiesToRope`
--- make the rope a physical constraint on whatever they bind, which is how a fire engine ends
--- up airborne, and they hold their end rigidly enough that the rope cannot hang. Pinning says
--- where a vertex is and applies force to nothing.
---
--- **Three vertices are pinned at the rig**, along the outlet's axis, so the hose leaves the
--- coupling straight rather than at whatever angle physics settles on.
CreateThread(function()
    while true do
        if next(lines) == nil and next(drawn) == nil then
            Wait(250)
            reconcileNozzle()
        else
            Wait(0)

            reconcileNozzle()

            -- Anything drawn whose line is gone.
            for id in pairs(drawn) do
                if not lines[id] then undraw(id) end
            end

            for id, line in pairs(lines) do
                local entry = drawn[id]

                if entry and entry.pending then
                    -- Still building. Pinning now would use vertex 0, which is the end the
                    -- firefighter is on.

                elseif entry and (not entry.rope or not DoesRopeExist(entry.rope)) then
                    -- The rope went away underneath us. Drop the record and let this loop
                    -- build a new one next frame rather than leaving the line invisible.
                    drawn[id] = nil

                elseif not entry then
                    -- Claimed here rather than inside `draw`, and built on its own thread.
                    -- `draw` yields while it waits for the rope to simulate, and yielding
                    -- inside a `pairs` walk of a table another handler can rewrite is how a
                    -- loop ends up with an invalid key.
                    drawn[id] = { pending = true }

                    CreateThread(function() draw(id, line) end)

                else
                    local from = sourceCoords(line)
                    local holder = entry.holder

                    if not from or not holder or not DoesEntityExist(holder) then
                        -- Transient. A network id that does not resolve this frame is not a
                        -- reason to delete a hose.

                    else
                        -- `GetPedBoneCoords` rather than `GetWorldPositionOfEntityBone` with
                        -- a converted index.
                        --
                        -- 6286 is PH_R_Hand, a prop-attachment bone that not every ped model
                        -- carries. `GetPedBoneIndex` returns -1 when it is absent, and asking
                        -- for the world position of bone -1 gives a point near the world
                        -- origin -- which is why the hose was heading off into the distance
                        -- instead of to the firefighter holding it. 57005 is SKEL_R_Hand and
                        -- is on every ped.
                        local hand = GetPedBoneCoords(holder, 57005, 0.0, 0.0, 0.0)

                        -- And a guard, because a bad bone gives a plausible-looking vector
                        -- rather than an error. A hand is not fifty metres from its owner.
                        if #(hand - GetEntityCoords(holder)) > 5.0 then
                            hand = GetEntityCoords(holder)
                        end

                        PinRopeVertex(entry.rope, 0, hand.x, hand.y, hand.z)

                        local axis = portAxis(entry.vehicle, entry.port)
                        local last = entry.vertices - 1

                        PinRopeVertex(entry.rope, last, from.x, from.y, from.z)

                        -- The guide vertex, which makes the hose leave the fitting straight
                        -- rather than at whatever angle the physics settles on -- but only
                        -- when there is a vertex to spare.
                        --
                        -- With four or fewer, pinning it would leave nothing free between the
                        -- two ends, and a rope with no free vertices is a taut line that
                        -- shakes as its pins disagree. Whatever the rope has left over is what
                        -- hangs, so it never gets spent.
                        if entry.vertices >= 5 then
                            PinRopeVertex(entry.rope, last - 1,
                                from.x + axis.x * 0.3,
                                from.y + axis.y * 0.3,
                                from.z + axis.z * 0.3)
                        end

                        -- Pay the line out as the crew walks and haul it in as they return,
                        -- capped at what is on the bed.
                        --
                        -- Not every frame. A walking ped's hand moves several centimetres a
                        -- frame, so the distance never settles, and reshaping a rope four
                        -- times a second is plenty -- doing it sixty is its own source of
                        -- shaking.
                        local now = GetGameTimer()

                        if now - (entry.lengthAt or 0) > 250 then
                            entry.lengthAt = now

                            local slack = 1.0 + (MIFireHose.visuals.slack or 0.35)
                            local wanted = math.min(entry.maxLength,
                                math.max(4.0, #(from - hand) * slack))

                            if math.abs(wanted - (entry.length or 0)) > 1.0 then
                                RopeForceLength(entry.rope, wanted)
                                entry.length = wanted
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Working the nozzle
-- ---------------------------------------------------------------------------

--- Where the water is going.
---@return vector3|nil
local function aimPoint(reach)
    local camera = GetGameplayCamCoord()
    local direction = MIFire.Placement.cameraDirection()

    local target = vector3(
        camera.x + direction.x * reach,
        camera.y + direction.y * reach,
        camera.z + direction.z * reach)

    local ray = StartExpensiveSynchronousShapeTestLosProbe(
        camera.x, camera.y, camera.z, target.x, target.y, target.z, -1, cache.ped, 4)

    local _, hit, endCoords = GetShapeTestResult(ray)

    return (hit == 1 or hit == true) and endCoords or target
end

--- Put water on the fire.
---
--- The client reports where it is aiming and the server decides what that does, because
--- suppression is fire state and fire state is the server's. The worst a forged aim achieves
--- is putting water somewhere the player is not looking.
CreateThread(function()
    while not MIFire.ready do Wait(250) end

    while true do
        local line = mine and lines[mine]
        -- `usable` is the pump's verdict: a line below a third of its rated nozzle pressure
        -- is soft, and a soft line puts water on the floor rather than on the fire.
        local flowing = line and line.state == 'charged' and (line.gpm or 0) > 0
            and line.usable ~= false
            and line.nozzleHolder == GetPlayerServerId(PlayerId())

        Wait(flowing and 500 or 1000)

        if flowing then
            local nozzle = MIFireHose.nozzles[line.nozzle or 'fog']
            local pattern = line.pattern or (nozzle and nozzle.defaultPattern) or 'straight'
            local reach = nozzle and nozzle.reach and nozzle.reach[pattern] or 15.0

            local point = aimPoint(reach)

            if point then
                -- Half a second of flow, since that is the tick. Efficiency is the pattern's:
                -- a wide fog puts far less water on the seat than a straight stream.
                local efficiency = nozzle and Hose.patternEfficiency(nozzle, pattern) or 1.0

                TriggerServerEvent('mi_fire:server:hoseWater', {
                    x = point.x, y = point.y, z = point.z,
                }, line.gpm * efficiency, 0.5)
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Interactions
-- ---------------------------------------------------------------------------

---@param entity integer
---@param coords vector3|nil
---@return table|nil port
local function dischargeAt(entity, coords)
    if not coords then return nil end

    local ports = apparatus().ports(entity, 'discharge')

    for i = 1, #ports do
        if apparatus().atPort(entity, coords, 'discharge') then
            local world = apparatus().portCoords(entity, ports[i])
            if #(coords - world) <= 1.0 then return ports[i] end
        end
    end

    return nil
end

CreateThread(function()
    while not MIFire.ready do Wait(250) end

    TriggerServerEvent('mi_fire:server:requestHoses')

    Target.addGlobalVehicle({
        {
            name = 'mi_fire:pullPreconnect',
            icon = 'fire-flame-simple',
            label = 'Take the preconnect',
            distance = 2.5,
            canInteract = function(entity, _, coords)
                if mine then return false end
                if not apparatus().isApparatus(entity) then return false end

                -- Only an outlet with hose already on it. A bare discharge has nothing to
                -- take: its hose is still on the bed.
                local port = dischargeAt(entity, coords)
                return port ~= nil and port.preconnected ~= nil
            end,
            onSelect = function(data)
                local port = dischargeAt(data.entity, data.coords)
                if not port then return end

                local finished = lib.progressBar({
                    duration = math.floor((MIFireHose.work.pullSeconds or 4.0) * 1000),
                    label = ('Pulling %s'):format(port.label or port.id),
                    canCancel = true,
                    disable = { move = true, car = true, combat = true },
                })

                if finished then
                    TriggerServerEvent('mi_fire:server:pullHose',
                        VehToNet(data.entity), port.id)
                end
            end,
        },
        {
            name = 'mi_fire:pullFromBed',
            icon = 'layer-group',
            label = 'Pull hose off the bed',
            distance = 2.5,
            canInteract = function(entity, _, coords)
                if mine then return false end
                if not apparatus().isApparatus(entity) then return false end
                return apparatus().atPort(entity, coords, 'hosebed')
            end,
            onSelect = function(data)
                local netId = VehToNet(data.entity)
                local port = apparatus().nearestPort(data.entity, 'hosebed')
                if not port then return end

                local contents = lib.callback.await('mi_fire:bedContents', false, netId, port.id)

                if not contents or #contents == 0 then
                    return lib.notify({ description = 'This bed is empty', type = 'error' })
                end

                local options = {}

                for _, entry in ipairs(contents) do
                    local size = MIFireHose.sizes[entry.size] or {}

                    options[#options + 1] = {
                        title = entry.label,
                        description = ('%d ft left of %d  ·  %d for a crew')
                            :format(entry.feet, entry.capacity, size.crew or 1),
                        icon = 'grip-lines',
                        disabled = entry.feet <= 0,
                        onSelect = function()
                            local sectionFeet = size.sectionFeet or 50
                            local most = math.max(1, math.floor(entry.feet / sectionFeet))

                            local input = lib.inputDialog(entry.label, {
                                {
                                    type = 'slider',
                                    label = 'Lengths',
                                    description = ('%d ft each. The bed has %d.')
                                        :format(sectionFeet, most),
                                    min = 1,
                                    max = math.min(most, MIFireHose.maxSections),
                                    default = math.min(4, most),
                                },
                            })

                            if not input then return end

                            local finished = lib.progressBar({
                                duration = math.floor(
                                    (MIFireHose.work.pullSeconds or 4.0) * 1000 * input[1] * 0.5),
                                label = ('Pulling %d length(s)'):format(input[1]),
                                canCancel = true,
                                disable = { move = true, car = true, combat = true },
                            })

                            if finished then
                                TriggerServerEvent('mi_fire:server:pullFromBed',
                                    netId, port.id, entry.size, input[1])
                            end
                        end,
                    }
                end

                lib.registerContext({
                    id = 'mi_fire_bed',
                    title = 'Hose bed',
                    options = options,
                })

                lib.showContext('mi_fire_bed')
            end,
        },
        {
            name = 'mi_fire:connectHose',
            icon = 'link',
            label = 'Couple the line here',
            distance = 2.5,
            canInteract = function(entity, _, coords)
                local line = mine and lines[mine]
                if not line or line.sourceNet then return false end
                if not apparatus().isApparatus(entity) then return false end
                return dischargeAt(entity, coords) ~= nil
            end,
            onSelect = function(data)
                local port = dischargeAt(data.entity, data.coords)
                if not port then return end

                local finished = lib.progressBar({
                    duration = math.floor((MIFireHose.work.connectSeconds or 3.0) * 1000),
                    label = 'Coupling',
                    canCancel = true,
                    disable = { move = true, car = true, combat = true },
                })

                if finished then
                    TriggerServerEvent('mi_fire:server:connectHose',
                        VehToNet(data.entity), port.id)
                end
            end,
        },
        {
            name = 'mi_fire:pumpPanel',
            icon = 'gauge-high',
            label = 'Pump panel',
            distance = 2.5,
            canInteract = function(entity, _, coords)
                if not apparatus().isApparatus(entity) then return false end
                return apparatus().atPort(entity, coords, 'panel')
            end,
            onSelect = function(data)
                HoseClient.panel(data.entity)
            end,
        },
    })

    Util.debug('hose', 'hose interactions registered')
end)

--- Working someone else's line.
---
--- On the ped rather than on the hose, because a rope is not a targetable entity -- you back up
--- the firefighter, which is also how it works on a real fireground.
---
--- Note the direction, which is not obvious and was not: **the person without a line targets
--- the person with one.** Joining a crew is the joiner's act. Someone already on a line who
--- looks at a colleague sees nothing, because there is nothing for them to do to them.
CreateThread(function()
    while not MIFire.ready do Wait(250) end

    --- The line a targeted player is on, if any.
    ---@param entity integer
    ---@return string|nil id
    ---@return table|nil line
    local function lineOf(entity)
        if not entity or entity == 0 or not IsPedAPlayer(entity) then return nil end

        local index = NetworkGetPlayerIndexFromPed(entity)
        if not index or index == -1 then return nil end

        local serverId = GetPlayerServerId(index)

        for id, line in pairs(lines) do
            if onCrew(line, serverId) then return id, line end
        end

        return nil
    end

    Target.addGlobalPlayer({
        {
            name = 'mi_fire:backupLine',
            icon = 'people-group',
            label = 'Back up this line',
            distance = 2.5,
            canInteract = function(entity)
                if mine then return false end
                return lineOf(entity) ~= nil
            end,
            onSelect = function(data)
                local id = lineOf(data.entity)
                if id then TriggerServerEvent('mi_fire:server:joinHoseCrew', id) end
            end,
        },
        {
            name = 'mi_fire:takeNozzle',
            icon = 'hand-holding-droplet',
            label = 'Take the nozzle',
            distance = 2.5,
            canInteract = function(entity)
                local id, line = lineOf(entity)

                -- Only when nobody has it. Taking a working nozzle out of someone's hands is
                -- not a thing you do to a colleague mid-attack.
                return id ~= nil and line.nozzleHolder == nil
            end,
            onSelect = function(data)
                local id = lineOf(data.entity)
                if id then TriggerServerEvent('mi_fire:server:takeNozzle', id) end
            end,
        },
    })

    --- Leaving is done to yourself, so it goes on your own ped.
    Target.addGlobalPlayer({
        {
            name = 'mi_fire:leaveLine',
            icon = 'right-from-bracket',
            label = 'Leave this line',
            distance = 2.5,
            canInteract = function(entity)
                return mine ~= nil and entity == cache.ped
            end,
            onSelect = function()
                TriggerServerEvent('mi_fire:server:leaveHose')
            end,
        },
    })
end)

-- ---------------------------------------------------------------------------
-- Held controls
-- ---------------------------------------------------------------------------

CreateThread(function()
    while not MIFire.ready do Wait(250) end

    --- Opening the nozzle is a control held during an action already in progress, which is the
    --- one case the ox_target rule allows a keybind for.
    lib.addKeybind({
        name = 'mi_fire_nozzle',
        description = 'Open or close the nozzle',
        defaultKey = 'G',
        onPressed = function()
            local line = mine and lines[mine]
            if not line then return end

            if line.nozzleHolder ~= GetPlayerServerId(PlayerId()) then
                return lib.notify({ description = 'You are not on the nozzle', type = 'error' })
            end

            -- Open or shut, not a number of gallons. What comes out is the pump's answer.
            local open = (line.bail or 0) > 0

            TriggerServerEvent('mi_fire:server:setHoseBail', open and 0.0 or 1.0)
        end,
    })

    lib.addKeybind({
        name = 'mi_fire_pattern',
        description = 'Change nozzle pattern',
        defaultKey = 'B',
        onPressed = function()
            local line = mine and lines[mine]
            if not line or line.nozzleHolder ~= GetPlayerServerId(PlayerId()) then return end

            TriggerServerEvent('mi_fire:server:cycleNozzlePattern')
        end,
    })
end)

--- Remove every rope and prop this client made, regardless of what the server thinks.
---
--- The escape hatch for a line that has gone wrong. It does not ask the server first, because
--- the case it exists for is exactly the one where the two disagree.
--- What this client believes about hose lines.
---
--- The server's list and a client's list disagreeing is the whole bug class here -- "back up
--- this line" not appearing looked like a rule refusing, and was a table arriving in a shape
--- the client could not read. Asking only the server could never have shown that.
--- Lay all eight rope types out side by side.
---
--- GTA ships eight, and they differ in thickness and texture. We picked 4 because the hose
--- resource on this machine uses it, which is evidence but not a comparison -- and since a
--- rope's texture cannot be changed for one resource without changing it for every rope on the
--- server, the eight built-in types are the whole of what is available without abandoning
--- ropes entirely.
---
--- So: look at them. If one reads as hose, that is the answer and it costs nothing. If none
--- do, the answer is the rewrite in HOSE-010 and this will have taken a minute to find out.
RegisterNetEvent('mi_fire:client:ropeTypes', function()
    RopeLoadTextures()

    local waited = 0
    while not RopeAreTexturesLoaded() and waited < 3000 do
        Wait(50)
        waited = waited + 50
    end

    local origin = GetEntityCoords(cache.ped)
    local forward = GetEntityForwardVector(cache.ped)
    local right = vector3(forward.y, -forward.x, 0.0)

    local made = {}

    for ropeType = 0, 7 do
        -- Two metres apart across your facing, each a five metre span at chest height so the
        -- texture is visible rather than foreshortened.
        local offset = ropeType * 2.0 - 7.0

        local ax = origin.x + right.x * offset + forward.x * 3.0
        local ay = origin.y + right.y * offset + forward.y * 3.0
        local bx = origin.x + right.x * offset + forward.x * 8.0
        local by = origin.y + right.y * offset + forward.y * 8.0
        local z = origin.z + 1.2

        local rope = AddRope(ax, ay, z, 0.0, 0.0, 0.0,
            6.0, ropeType, 6.0, 0.5, 1.0, false, false, false, 1.0, false, 0)

        if rope and rope ~= 0 then
            Wait(0)

            local vertices = GetRopeVertexCount(rope) or 0

            if vertices >= 2 then
                ActivatePhysics(rope)
                PinRopeVertex(rope, 0, ax, ay, z)
                PinRopeVertex(rope, vertices - 1, bx, by, z)
            end

            made[#made + 1] = { rope = rope, type = ropeType, x = ax, y = ay, z = z }
        end
    end

    lib.notify({
        title = ('%d rope type(s)'):format(#made),
        description = 'Numbered left to right. Two minutes. Pick the one that reads as hose.',
        type = 'inform',
    })

    CreateThread(function()
        local until_ = GetGameTimer() + 120000

        while GetGameTimer() < until_ do
            Wait(0)

            for i = 1, #made do
                local entry = made[i]
                local onScreen, sx, sy = GetScreenCoordFromWorldCoord(
                    entry.x, entry.y, entry.z + 0.4)

                if onScreen then
                    SetTextFont(4)
                    SetTextScale(0.0, 0.4)
                    SetTextColour(255, 220, 120, 240)
                    SetTextOutline()
                    SetTextCentre(true)
                    SetTextEntry('STRING')
                    AddTextComponentString(('type %d'):format(entry.type))
                    DrawText(sx, sy)
                end
            end
        end

        for i = 1, #made do
            if DoesRopeExist(made[i].rope) then DeleteRope(made[i].rope) end
        end
    end)
end)

--- Try to put each candidate prop in your hand, one at a time.
---
--- Separates two questions that look identical from the outside: is the attaching broken, or
--- is that particular model not reaching this client? A base game prop appearing proves the
--- first is fine and the answer is the second.
RegisterNetEvent('mi_fire:client:testNozzle', function()
    -- The weapon first, through exactly the path the real one uses.
    local weapon = MIFireHose.visuals.nozzleWeapon

    if weapon then
        local hash = joaat(weapon)

        RequestWeaponAsset(hash, 31, 0)

        local waited = 0
        while not HasWeaponAssetLoaded(hash) and waited < 2500 do
            Wait(50)
            waited = waited + 50
        end

        local loaded = HasWeaponAssetLoaded(hash)

        -- Equip it, rather than making a world object out of it.
        --
        -- The object test only ever proved the archetype existed, which was the old question.
        -- The question now is whether the weapon **stays** equipped, because that is what
        -- decides if it can be fired -- and if something on the server strips it, that shows up
        -- here as gotAfter=false rather than as a mystery on the fireground.
        local gaveOk, heldNow, heldAfter = false, false, false

        if loaded then
            GiveWeaponToPed(cache.ped, hash, 1000, false, true)
            SetCurrentPedWeapon(cache.ped, hash, true)

            gaveOk = true
            heldNow = HasPedGotWeapon(cache.ped, hash, false)

            applyNozzleHold(cache.ped)

            TriggerEvent('chat:addMessage',
                { args = { 'mi_fire', '      equipped -- look at your hands, then wait' } })

            Wait(4000)
            heldAfter = HasPedGotWeapon(cache.ped, hash, false)

            RemoveWeaponFromPed(cache.ped, hash)
            clearNozzleHold(cache.ped)
        end

        local line = ('  %-26s assetLoaded=%s gave=%s gotNow=%s gotAfter4s=%s')
            :format(weapon, tostring(loaded), tostring(gaveOk),
                tostring(heldNow), tostring(heldAfter))

        TriggerEvent('chat:addMessage', { args = { 'mi_fire', line } })
        print('[mi_fire] ' .. line)

        if loaded and not heldAfter then
            local why = '      it did not stay equipped -- something on this server is '
                .. 'removing it. That is the ox_inventory case, and the fix is one entry.'
            TriggerEvent('chat:addMessage', { args = { 'mi_fire', why } })
            print('[mi_fire] ' .. why)
        end

        RemoveWeaponAsset(hash)
    end

    -- Built rather than declared, because `nozzleProp` is usually nil and `ipairs` stops at
    -- the first hole. `{ nil, 'a', 'b' }` iterates zero times, which is why the prop test
    -- printed its heading and its footer and nothing at all in between.
    local candidates = {}

    for _, name in ipairs({
        MIFireHose.visuals.nozzleProp or false,
        'hei_prop_heist_hose_01',
        'prop_fire_hosereel_l1',
        'prop_fire_hosebox_01',
        'prop_fire_exting_1a',
        'prop_tool_fireaxe',
    }) do
        if name then candidates[#candidates + 1] = name end
    end

    local out = { '--- nozzle prop test ---' }

    for _, name in ipairs(candidates) do
        if name then
            local model = joaat(name)
            local known = IsModelInCdimage(model) or IsModelValid(model)

            RequestModel(model)

            local waited = 0
            while not HasModelLoaded(model) and waited < 2000 do
                Wait(50)
                waited = waited + 50
            end

            local loaded = HasModelLoaded(model)

            out[#out + 1] = ('  %-26s known=%s loaded=%s')
                :format(name, tostring(known), tostring(loaded))

            if loaded then
                -- Actually put it in the hand for two seconds. Loading and attaching are
                -- different failures and only one of them is visible from a log line.
                local coords = GetEntityCoords(cache.ped)
                local prop = CreateObject(model, coords.x, coords.y, coords.z, false, true, false)

                if prop and prop ~= 0 then
                    AttachEntityToEntity(prop, cache.ped,
                        GetPedBoneIndex(cache.ped, 57005),
                        0.12, 0.02, -0.02, -75.0, 12.0, 0.0,
                        true, true, false, true, 1, true)

                    out[#out + 1] = '      attached -- look at your hand'
                    Wait(2500)
                    DeleteEntity(prop)
                else
                    out[#out + 1] = '      CreateObject returned nothing'
                end

                SetModelAsNoLongerNeeded(model)
            end
        end
    end

    out[#out + 1] = 'If a base game prop appeared and yours did not, the model is not reaching '
        .. 'this client -- reconnect (F8, "reconnect").'

    for i = 1, #out do
        TriggerEvent('chat:addMessage', { args = { 'mi_fire', out[i] } })
        print('[mi_fire] ' .. out[i])
    end

    TriggerServerEvent('mi_fire:server:relayHoseDiagnosis', out)
end)

--- `/fire nozzlehold <clipset|off> [move]` -- try a carrying stance without a restart.
---
--- The stance is the one part of the nozzle that cannot be settled from a file. Two clipsets do
--- two different jobs through two different natives, `HasAnimSetLoaded` answers true for both,
--- and the wrong pairing is a T-pose -- so it gets tried rather than reasoned about.
---
--- Default is the **weapon** clipset, which is the hold. Pass `move` for the movement clipset,
--- which is the walk. Whatever looks right goes into `MIFireHose.visuals`.
RegisterNetEvent('mi_fire:client:nozzleHold', function(clipset, kind)
    local function say(text)
        TriggerEvent('chat:addMessage', { args = { 'mi_fire', text } })
        print('[mi_fire] ' .. text)
    end

    if not clipset or clipset == 'off' or clipset == 'reset' then
        clearNozzleHold(cache.ped)
        return say('stance cleared -- both clipsets')
    end

    -- Cleared first, so a bad clipset leaves the ped standing normally rather than stacking on
    -- top of whatever the last attempt did.
    clearNozzleHold(cache.ped)
    Wait(100)

    local movement = kind == 'move'
    local ok = movement and applyNozzleHold(cache.ped, clipset)
        or (not movement and applyNozzleStrafe(cache.ped, clipset))

    if ok then
        say(('applied "%s" as the %s clipset -- aim, and walk around')
            :format(clipset, movement and 'movement' or 'weapon'))
        say('T-posing means it is the other kind. "/fire nozzlehold off" undoes it.')
    else
        say(('"%s" would not load'):format(clipset))
    end
end)

RegisterNetEvent('mi_fire:client:diagnoseHoses', function()
    local me = GetPlayerServerId(PlayerId())
    local lineCount = 0
    for _ in pairs(lines) do lineCount = lineCount + 1 end

    local out = {
        '--- what the CLIENT sees ---',
        ('you are server id %d; you are on line: %s'):format(me, tostring(mine)),
        ('lines known: %d, ropes drawn: %d'):format(lineCount, (function()
            local n = 0
            for _ in pairs(drawn) do n = n + 1 end
            return n
        end)()),
    }

    for id, line in pairs(lines) do
        local ids = {}
        for i = 1, #(line.crew or {}) do ids[#ids + 1] = tostring(line.crew[i]) end

        out[#out + 1] = ('  %s  %s  crew [%s] of %d  nozzle %s  %s')
            :format(id, line.state, table.concat(ids, ','),
                line.crewRequired or 0, tostring(line.nozzleHolder),
                onCrew(line, me) and 'YOU ARE ON IT' or '')
    end

    if lineCount == 0 then
        out[#out + 1] = '  none -- if the server says otherwise, the sync is not arriving'
    end

    for i = 1, #out do print('[mi_fire] ' .. out[i]) end

    -- Sent back to be replied through the same path as the server's half, so both land in the
    -- same place. The last round produced a screenshot of the server half alone, because the
    -- client's went to a chat box that was not open.
    TriggerServerEvent('mi_fire:server:relayHoseDiagnosis', out)
end)

RegisterNetEvent('mi_fire:client:clearHoseProps', function()
    for id in pairs(drawn) do undraw(id) end

    if heldNozzle and DoesEntityExist(heldNozzle) then DeleteEntity(heldNozzle) end
    if nozzleEquipped then
        unequipNozzle(cache.ped)
        clearNozzleHold(cache.ped)
    end

    heldNozzle = nil
    nozzleEquipped = false
    reEquips = 0
    drawn = {}
    lines = {}
    mine = nil
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    -- An equipped weapon and an attached object both outlive the resource, with nothing left
    -- to remove either. A firefighter stuck holding a nozzle after a restart is a support
    -- ticket, and one stuck in the minigun stance is a stranger one.
    if heldNozzle and DoesEntityExist(heldNozzle) then DeleteEntity(heldNozzle) end
    if nozzleEquipped then
        unequipNozzle(cache.ped)
        clearNozzleHold(cache.ped)
    end
end)

--- The pump panel, until Phase 4's NUI replaces it.
---
--- A menu rather than a panel, deliberately: the real one is authored against the photographs
--- in `docs/Reference/PumpPanels/` and is a project of its own.
---
--- **Nobody types a pressure.** The operator works the throttle and pulls the gates, exactly as
--- they would on the rig, and the gauges read what that produces. An early version had them
--- entering a number into each discharge, which is not how a panel works and would have shaped
--- the real one wrongly.
---@param entity integer
function HoseClient.panel(entity)
    local netId = VehToNet(entity)

    local state = lib.callback.await('mi_fire:pumpState', false, netId)

    if not state then
        return lib.notify({ description = 'That rig has no pump', type = 'error' })
    end

    local options = {}

    -- Offered rather than refused. Being told what is wrong and then having to find the
    -- control somewhere else is the shape of a menu written by someone who already knew where
    -- it was.
    if not state.engaged then
        options[#options + 1] = {
            title = 'Engage the pump',
            description = 'The rig has to be stopped. Nothing works until this is done.',
            icon = 'gears',
            onSelect = function()
                TriggerServerEvent('mi_fire:server:setPump', netId, true)
                Wait(200)
                HoseClient.panel(entity)
            end,
        }

        lib.registerContext({
            id = 'mi_fire_pump',
            title = ('%s -- pump panel'):format(state.label or 'Apparatus'),
            options = options,
        })

        return lib.showContext('mi_fire_pump')
    end

    -- --- The master reading ----------------------------------------------------------------

    options[#options + 1] = {
        title = ('Master discharge -- %.0f psi'):format(state.masterPsi or 0),
        description = ('throttle %d%%  ·  %.0f gpm total  ·  tank %.0f / %.0f gal%s')
            :format(math.floor((state.throttle or 0) * 100), state.totalGpm or 0,
                state.tank.water, state.tank.capacity,
                state.cavitating and '  ·  CAVITATING' or ''),
        icon = 'gauge-high',
        readOnly = true,
    }

    options[#options + 1] = {
        title = 'Throttle up',
        description = 'Raises pressure on every outlet -- there is one pump',
        icon = 'arrow-up',
        onSelect = function()
            TriggerServerEvent('mi_fire:server:throttle', netId, MIFirePump.throttleStep)
            HoseClient.panel(entity)
        end,
    }

    options[#options + 1] = {
        title = 'Throttle down',
        icon = 'arrow-down',
        onSelect = function()
            TriggerServerEvent('mi_fire:server:throttle', netId, -MIFirePump.throttleStep)
            HoseClient.panel(entity)
        end,
    }

    -- --- The gates ------------------------------------------------------------------------

    for _, outlet in ipairs(state.outlets or {}) do
        local shut = (outlet.valve or 0) <= 0.01

        local description

        if not outlet.connected then
            description = 'nothing coupled to it'
        elseif shut then
            description = 'gate shut'
        else
            description = ('%.0f psi at the gate  ·  %.0f gpm  ·  nozzle %.0f psi (%s)')
                :format(outlet.psi or 0, outlet.gpm or 0, outlet.nozzlePsi or 0,
                    outlet.condition or '-')
        end

        options[#options + 1] = {
            title = ('%s -- %s'):format(outlet.label,
                shut and 'shut' or ('%d%% open'):format(math.floor((outlet.valve or 0) * 100))),
            description = description,
            icon = shut and 'circle' or 'circle-dot',
            onSelect = function()
                local input = lib.inputDialog(outlet.label, {
                    {
                        type = 'slider',
                        label = 'Gate',
                        description = 'How far the handle is pulled',
                        min = 0,
                        max = 100,
                        default = math.floor((outlet.valve or 0) * 100),
                        step = 10,
                    },
                })

                if input then
                    TriggerServerEvent('mi_fire:server:setValve',
                        netId, outlet.id, (input[1] or 0) / 100.0)
                end

                HoseClient.panel(entity)
            end,
        }
    end

    -- --- Lines waiting for water ------------------------------------------------------------

    for id, line in pairs(lines) do
        if line.sourceNet == netId and line.state == 'connected' then
            options[#options + 1] = {
                title = ('Charge %s'):format(line.sourcePort or id),
                description = 'Fill the line. Then open its gate.',
                icon = 'droplet',
                onSelect = function()
                    TriggerServerEvent('mi_fire:server:chargeHose', id, true)
                    HoseClient.panel(entity)
                end,
            }

        elseif line.sourceNet == netId and line.state == 'charged' then
            options[#options + 1] = {
                title = ('Shut down %s'):format(line.sourcePort or id),
                icon = 'droplet-slash',
                onSelect = function()
                    TriggerServerEvent('mi_fire:server:chargeHose', id, false)
                    HoseClient.panel(entity)
                end,
            }
        end
    end

    options[#options + 1] = {
        title = 'Disengage the pump',
        description = 'Shuts everything down. The rig can be driven again.',
        icon = 'power-off',
        onSelect = function()
            TriggerServerEvent('mi_fire:server:setPump', netId, false)
        end,
    }

    lib.registerContext({
        id = 'mi_fire_pump',
        title = ('%s -- pump panel'):format(state.label or 'Apparatus'),
        options = options,
    })

    lib.showContext('mi_fire_pump')
end

exports('GetHoseLine', function() return mine and lines[mine] or nil end)
exports('GetHoseLines', function() return lines end)

MIFire.HoseClient = HoseClient

return HoseClient
