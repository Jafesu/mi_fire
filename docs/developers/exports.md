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

## Status

**None of these are implemented yet.** Phase 1 is in progress; this page describes the
contract they will honour so integrations can be written against it in advance.

Check [internal/CONTRACTS.md](../internal/CONTRACTS.md) for what is actually live.
Anything marked `planned` there does not exist and will error if you call it.
