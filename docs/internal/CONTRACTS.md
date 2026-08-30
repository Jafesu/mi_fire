# Contracts

Every export, event, and callback `mi_fire` exposes. A contract change updates this file
**in the same commit** that makes it.

Status: `planned` (designed, not written), `review` (written, not verified in game),
`stable` (verified in game).

---

## Server exports — SmartFires-compatible

These deliberately match the names and return shapes of the resource being replaced, so
`mi_fire_rescue` migrates with a one-line config change. See
[INTEGRATIONS.md](INTEGRATIONS.md) for the required return shape.

| Export | Signature | Status | Task |
|---|---|---|---|
| `CreateFire` | `(x, y, z, fireType, radius, count, interiorId?, suppressDispatch?) -> incidentId \| nil` | planned | `API-001` |
| `StopFire` | `(incidentId) -> ok: boolean` | planned | `API-001` |
| `GetAllFires` | `() -> FireRow[]` | planned | `API-001` |
| `GetFiresForIncident` | `(incidentId) -> FireRow[]` | planned | `API-001` |
| `GetIncidentStatus` | `(incidentId) -> status: string \| nil` | planned | `API-001` |
| `ProbeInteriorAtCoords` | `(x, y, z) -> interiorId: integer \| nil` | planned | `API-001` |
| `GetActiveVehicleFires` | `(opts?) -> VehicleFireRow[]` | planned | `API-001` |
| `StartVehicleFire` | `(vehNet, opts?) -> incidentId \| nil` | planned | `API-001` |
| `CreateSmoke` | `(x, y, z, smokeType, radius, suppressDispatch?) -> incidentId \| nil` | planned | `API-001` |
| `StopSmoke` | `(incidentId) -> ok: boolean` | planned | `API-001` |
| `ApplyFireDamageAtCoords` | `(x, y, z, radius, amount, opts?) -> affected: integer` | planned | `API-001` |

## Server exports — native

Richer API for new integrations. Prefer these over the compatible set above.

| Export | Signature | Status | Task |
|---|---|---|---|
| `StartIncident` | `(spec: IncidentSpec) -> incidentId \| nil, err?` | planned | `API-002` |
| `GetIncident` | `(incidentId) -> Incident \| nil` | planned | `API-002` |
| `GetIncidents` | `(filter?) -> Incident[]` | planned | `API-002` |
| `ExtinguishAt` | `(coords, radius, agent, amount) -> knockedDown: number` | planned | `API-002` |
| `GetDistrictAt` | `(coords) -> districtName \| nil` | planned | `ZONE-001` |
| `GetActiveAop` | `() -> districtName[]` | planned | `ZONE-002` |
| `SetAop` | `(districtNames: string[]) -> ok, err?` | planned | `ZONE-002` |
| `GetGearTier` | `(source) -> tierName, integrity` | planned | `EXPO-002` |

## Client exports

| Export | Signature | Status | Task |
|---|---|---|---|
| `GetAllFires` | `() -> FireRow[]` | planned | `API-001` |
| `GetAllSmokes` | `() -> SmokeRow[]` | planned | `API-001` |
| `IsFireNearby` | `(radius?) -> boolean, nearestDistance?` | planned | `API-001` |
| `IsFireStillActive` | `(incidentId) -> boolean` | planned | `API-001` |

## Events

| Event | Direction | Payload | Status |
|---|---|---|---|
| `mi_fire:client:teardown` | server to client | none | review |

Nothing else is registered yet. Net events that accept player input must validate at the
service boundary — see [CONVENTIONS.md](CONVENTIONS.md).

## Types

```lua
--- The row shape mi_fire_rescue and mi_fire_origins expect.
---@class FireRow
---@field id string
---@field coords vector3
---@field incidentId string
---@field sourceIncidentId string
---@field type string        -- 'outdoors' | 'indoors'
---@field active boolean
---@field live boolean       -- false once knocked down
---@field pendingSeed boolean
---@field strength number
---@field isDead boolean
---@field generation integer

---@class IncidentSpec
---@field coords vector3
---@field class string           -- a key from MIFire.Enums.FireClass
---@field nodeCount integer?
---@field radius number?
---@field interiorId integer?
---@field floor integer?
---@field origin string?         -- MIFire.Enums.IncidentOrigin
---@field suppressDispatch boolean?
---@field description string?
```
