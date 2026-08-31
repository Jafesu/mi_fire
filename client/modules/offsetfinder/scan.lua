--- Reading a rig's bones, mod slots and extras at runtime.
---
--- Both vehicle packs ship `RSC7`-compressed models, so none of this can be read from disk.
--- But unlike a decal type, a bone can be *asked about*: `GetEntityBoneIndexByName` returns
--- -1 for a name the model does not have, which turns "what bones does this truck have" from
--- a guess into an enumeration.
---
--- Why it is worth the trouble: a port anchored to a bone needs no measuring and survives the
--- model being updated. If the author put a bone at the hookup then that bone **is** the
--- hookup, and it is more accurate than anything anyone will produce by nudging a marker
--- around by hand. `misc_a`..`misc_z` in particular are the conventional slots modders use for
--- exactly this, and `docs/internal/APPARATUS.md` already records the 2026 pack's panel mod
--- switching off `misc_p` -- which is direct evidence this pack uses them.
---
--- Offsets remain the fallback, because a model with no useful bones is a real possibility and
--- the resource should not depend on the goodwill of a vehicle author.

MIFire = MIFire or {}

local Scan = {}

--- Names worth asking about.
---
--- Two groups. The conventional attachment slots, which is where a thoughtful author puts
--- hookups, and vanilla vehicle bones, which are always present and are useful as coarse
--- anchors -- a rear discharge hung off `boot` is still better than a hand-measured offset.
local CANDIDATES = {}

do
    -- misc_a .. misc_z: the modder's slots.
    for i = 0, 25 do
        CANDIDATES[#CANDIDATES + 1] = 'misc_' .. string.char(97 + i)
    end

    -- extra_1 .. extra_16: toggleable geometry, which on a fire truck is often equipment.
    for i = 1, 16 do
        CANDIDATES[#CANDIDATES + 1] = 'extra_' .. i
    end

    -- Vanilla structure, for coarse anchoring and for sanity -- if none of these resolve,
    -- the scan itself is broken rather than the model being bare.
    local vanilla = {
        'chassis', 'chassis_dummy', 'bodyshell', 'bonnet', 'boot',
        'door_dside_f', 'door_dside_r', 'door_pside_f', 'door_pside_r',
        'wheel_lf', 'wheel_rf', 'wheel_lr', 'wheel_rr',
        'seat_dside_f', 'seat_pside_f',
        'engine', 'exhaust', 'overheat', 'petrolcap', 'petroltank',
        'siren1', 'siren2', 'siren_glass1',
        'headlight_l', 'headlight_r', 'taillight_l', 'taillight_r',
        'platelight', 'attach_female',
        -- Names a fire-truck author might plausibly use. Costing one native call each to
        -- ask is cheaper than never finding out.
        'hose', 'hose_1', 'hose_2', 'nozzle', 'pump', 'panel', 'pumppanel',
        'hydrant', 'intake', 'discharge', 'monitor', 'deckgun', 'ladder',
    }

    for i = 1, #vanilla do
        CANDIDATES[#CANDIDATES + 1] = vanilla[i]
    end
end

--- Every bone on this vehicle that we can name.
---
--- Prefers the real enumeration where the build provides it -- `GetEntityBoneCount` and
--- `GetEntityBoneName` are CFX additions rather than vanilla natives, so their presence is
--- checked rather than assumed. Falling back to the candidate list means a model with a bone
--- named something nobody thought of stays invisible, which is a real limitation and is
--- reported rather than hidden.
---@param vehicle integer
---@return table[] bones `{ name, index, offset = vector3 }`
---@return boolean enumerated True if every bone was listed, false if only candidates were tried
function Scan.bones(vehicle)
    local found = {}
    local seen = {}

    local enumerated = false

    if type(GetEntityBoneCount) == 'function' and type(GetEntityBoneName) == 'function' then
        local count = GetEntityBoneCount(vehicle) or 0

        if count > 0 then
            enumerated = true

            for index = 0, count - 1 do
                local name = GetEntityBoneName(vehicle, index)

                if name and name ~= '' and not seen[name] then
                    seen[name] = true
                    found[#found + 1] = { name = name, index = index }
                end
            end
        end
    end

    if not enumerated then
        for i = 1, #CANDIDATES do
            local name = CANDIDATES[i]
            local index = GetEntityBoneIndexByName(vehicle, name)

            if index and index ~= -1 and not seen[name] then
                seen[name] = true
                found[#found + 1] = { name = name, index = index }
            end
        end
    end

    -- Resolve each to a vehicle-local offset, which is what makes the list readable: "a bone
    -- called misc_e" means nothing, "a bone called misc_e, 1.2m right and 0.4m back" is a
    -- discharge on the officer's side.
    for i = 1, #found do
        local world = GetWorldPositionOfEntityBone(vehicle, found[i].index)
        found[i].offset = GetOffsetFromEntityGivenWorldCoords(vehicle, world.x, world.y, world.z)
    end

    return found, enumerated
end

--- Which mod slots actually carry geometry.
---
--- The 2026 pack hangs its pump panel and intake fitting on mod slots, so knowing which are
--- populated is what makes physically deploying the panel possible later. `GetNumVehicleMods`
--- returns 0 for a slot the kit does not use.
---@param vehicle integer
---@return table[] `{ slot, name, count }`
function Scan.mods(vehicle)
    -- Named for readability in the report; the numbers are the values the natives take.
    local slots = {
        { 0, 'spoiler' }, { 1, 'bumper_f' }, { 2, 'bumper_r' }, { 3, 'skirt' },
        { 4, 'exhaust' }, { 5, 'chassis' }, { 6, 'grille' }, { 7, 'bonnet' },
        { 8, 'wing_l' }, { 9, 'wing_r' }, { 10, 'roof' },
        { 23, 'wheels' }, { 24, 'wheels_rear' },
        { 25, 'plaque' }, { 27, 'trim' }, { 28, 'ornaments' },
        { 30, 'dial' }, { 33, 'steering' }, { 34, 'shifter' },
        { 35, 'plaque_b' }, { 38, 'hydro' }, { 48, 'livery' },
    }

    SetVehicleModKit(vehicle, 0)

    local found = {}

    for i = 1, #slots do
        local slot, name = slots[i][1], slots[i][2]
        local count = GetNumVehicleMods(vehicle, slot) or 0

        if count > 0 then
            found[#found + 1] = {
                slot = slot,
                name = name,
                count = count,
                current = GetVehicleMod(vehicle, slot),
            }
        end
    end

    return found
end

--- Which extras the model defines.
---@param vehicle integer
---@return table[] `{ index, on }`
function Scan.extras(vehicle)
    local found = {}

    for index = 1, 16 do
        if DoesExtraExist(vehicle, index) then
            found[#found + 1] = { index = index, on = IsVehicleExtraTurnedOn(vehicle, index) }
        end
    end

    return found
end

--- Everything, as printable lines.
---@param vehicle integer
---@return string[] lines
---@return table bones
function Scan.report(vehicle)
    local model = GetEntityModel(vehicle)
    local name = GetDisplayNameFromVehicleModel(model)

    local bones, enumerated = Scan.bones(vehicle)
    local mods = Scan.mods(vehicle)
    local extras = Scan.extras(vehicle)

    local lines = {
        ('--- %s (model %s) ---'):format(name, tostring(model)),
        enumerated
            and ('bones: %d, fully enumerated'):format(#bones)
            or ('bones: %d found by name. This build has no bone enumeration native, so only '
                .. 'known names were tried -- a bone called something unexpected will not '
                .. 'appear here.'):format(#bones),
    }

    for i = 1, #bones do
        local b = bones[i]
        lines[#lines + 1] = ('  %-22s  x %6.2f  y %6.2f  z %6.2f')
            :format(b.name, b.offset.x, b.offset.y, b.offset.z)
    end

    lines[#lines + 1] = ('mod slots with geometry: %d'):format(#mods)
    for i = 1, #mods do
        lines[#lines + 1] = ('  %-12s slot %-3d %d option(s), currently %d')
            :format(mods[i].name, mods[i].slot, mods[i].count, mods[i].current)
    end

    lines[#lines + 1] = ('extras: %d'):format(#extras)
    for i = 1, #extras do
        lines[#lines + 1] = ('  extra_%d  %s')
            :format(extras[i].index, extras[i].on and 'on' or 'off')
    end

    return lines, bones
end

MIFire.Scan = Scan

return Scan
