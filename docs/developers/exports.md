# Exports

Full signatures and current status live in
[internal/CONTRACTS.md](../internal/CONTRACTS.md). This page is the practical version.

## Compatibility exports

mi_fire exposes exports under the same names and return shapes as the fire resource many
servers are migrating from, so existing add-ons keep working unchanged.

```lua
-- Server
local incidentId = exports.mi_fire:CreateFire(x, y, z, 'A', 3.0, 5)
local fires      = exports.mi_fire:GetAllFires()
exports.mi_fire:StopFire(incidentId)

-- Client
local fires  = exports.mi_fire:GetAllFires()
local nearby = exports.mi_fire:IsFireNearby(20.0)
```

If you are pointing an existing resource at mi_fire, that is usually the whole migration.

## Native API

Prefer these for new work. They carry more information and are not constrained by an
older resource's shape.

```lua
local incidentId, err = exports.mi_fire:StartIncident({
    coords      = vec3(215.0, -810.0, 30.0),
    class       = 'B',        -- A, B, C, D, K, gas, wildland, vehicle
    nodeCount   = 6,
    description = 'Fuel spill alight at the loading dock',
})

local incident = exports.mi_fire:GetIncident(incidentId)
local district = exports.mi_fire:GetDistrictAt(coords)
local aop      = exports.mi_fire:GetActiveAop()
```

## Gear, SCBA, and personal markings

```lua
-- Server. Assign a firefighter's name tape and rank markings.
-- Takes an identifier, not a source: markings are usually set from an admin panel
-- while the firefighter is offline.
exports.mi_fire:SetGearAppearance('ABC12345', 'structural', {
    male   = { torso2 = { drawable = 692, texture = 4 } },
    female = { torso2 = { drawable = 692, texture = 4 } },
}, { label = 'Casey / Deputy District Chief' })

exports.mi_fire:GetGearAppearance('ABC12345')
exports.mi_fire:ClearGearAppearance('ABC12345', 'structural')

-- Client. What this player is wearing and breathing.
local worn, active, air, capacity = exports.mi_fire:GetScbaState()
local tier, wearingGear, integrity = exports.mi_fire:GetGearState()
```

### Wiring an existing SCBA item

If you already have an SCBA item, repoint its export and change nothing else:

```lua
['scba'] = {
    label = 'SCBA',
    weight = 220,
    server = { export = 'mi_fire.useScba' },
}
```

Using the item toggles the set on and off. The air valve is a separate keybind, so using
the item never accidentally starts burning air.

## Status

**None of these are implemented yet.** Phase 1 is in progress; this page describes the
contract they will honour so integrations can be written against it in advance.

Check [internal/CONTRACTS.md](../internal/CONTRACTS.md) for what is actually live.
Anything marked `planned` there does not exist and will error if you call it.
