# Tasks

Status is one of `todo`, `in-progress`, `review`, `done`, `blocked`.
Set a task to `in-progress` before you start it, not after.

---

## Phase 0 — Foundation

| ID | Task | Status |
|---|---|---|
| `SETUP-001` | Repository scaffold, `fxmanifest.lua`, `.gitignore` | done |
| `SETUP-002` | `shared/enums.lua` — shared vocabulary | done |
| `SETUP-003` | `shared/util.lua` — helpers | done |
| `SETUP-004` | Framework bridge with Qbox / ESX / standalone adapters | done |
| `SETUP-005` | Dispatch bridge with lb-tablet, custom, none providers | done |
| `SETUP-006` | Target, inventory, and appearance bridges | done |
| `SETUP-007` | `server/core/` state and permissions | done |
| `SETUP-008` | Test harness and docs tree | done |
| `SETUP-009` | Database core, migration runner, station schema | done |

## Phase 1 — Fire core

| ID | Task | Status | Depends on |
|---|---|---|---|
| `FIRE-001` | Fire class and agent configuration | done | `SETUP-002` |
| `FIRE-002` | Node lifecycle: ignite, grow, consume fuel, go out | todo | `FIRE-001` |
| `FIRE-003` | Propagation: spread rolls, wind, spread caps | todo | `FIRE-002` |
| `FIRE-004` | Incident merge when scenes touch | todo | `FIRE-003` |
| `FIRE-005` | Suppression: agent matrix, knockdown, reflash, overhaul | todo | `FIRE-002` |
| `FIRE-006` | Hazards: spread, shock, explosion, flare, reaction | todo | `FIRE-005` |
| `FIRE-007` | Client rendering: PTFX, sound, intensity scaling, render distance | todo | `FIRE-002` |
| `FIRE-008` | Smoke volumes, separate from flame | todo | `FIRE-002` |
| `FIRE-009` | Interior probing so indoor fires land inside rooms | todo | `FIRE-002` |
| `FIRE-010` | Vehicle fire, including the EV reflash variant | todo | `FIRE-002` |
| `EXPO-001` | Exposure model: the three damage channels | todo | `FIRE-002` |
| `EXPO-002` | Gear resistance, integrity degradation, ignition threshold | todo | `EXPO-001` |
| `EXPO-003` | Catching fire, self-extinguish, partner extinguish | todo | `EXPO-002` |
| `ZONE-001` | District resolution: which district is a point in | todo | `SETUP-003` |
| `ZONE-002` | AOP: manual mode, `/aop` commands | todo | `ZONE-001` |
| `ZONE-003` | AOP: auto mode following population, with hold timer | todo | `ZONE-002` |
| `ZONE-004` | Run cards: district plus class to due stations and assignment | todo | `ZONE-001` |
| `GEN-001` | Ambient generation clock, capacity and spacing gates | todo | `ZONE-002` |
| `GEN-002` | Outdoor placement: ground probe, validity, player distance | todo | `GEN-001` |
| `GEN-003` | Indoor placement via learned interiors | todo | `GEN-002`, `FIRE-009` |
| `GEN-004` | Retire `mi_fire_origins` once parity is reached | todo | `GEN-003` |
| `DISP-001` | Raise dispatches from incidents through the bridge | todo | `ZONE-004` |
| `ADMIN-001` | `/fire` command family | todo | `FIRE-002` |
| `ADMIN-002` | `/aop` and `/district` commands | todo | `ZONE-002` |
| `API-001` | SmartFires-compatible export surface | todo | `FIRE-002` |
| `API-002` | Native mi_fire export surface | todo | `API-001` |
| `API-003` | Repoint `mi_fire_rescue` and verify victims still work | todo | `API-001` |
| `DOC-001` | `docs/guides/firefighting-basics.md` | todo | `FIRE-005` |
| `DOC-002` | `docs/guides/admin-guide.md` | todo | `ADMIN-002` |

## Phase 2 — Placement, apparatus, turnout

| ID | Task | Status | Depends on |
|---|---|---|---|
| `PLACE-001` | Shared placement gizmo: raycast preview, surface-normal orientation | todo | — |
| `PLACE-002` | Gizmo: 6-DOF nudge, snap toggles, confirm and cancel | todo | `PLACE-001` |
| `PLACE-003` | Polygon builder: walk the perimeter, close the loop, set height | todo | `PLACE-001` |
| `APP-001` | Apparatus profile schema and config | todo | — |
| `APP-002` | Offset finder on the shared gizmo, snapping to vehicle bones | todo | `PLACE-002`, `APP-001` |
| `APP-003` | Offset finder: export to clipboard and to config | todo | `APP-002` |
| `APP-004` | Tank state: water and foam, per vehicle | todo | `APP-001` |
| `APP-005` | Pump engage and disengage | todo | `APP-004` |
| `TURN-001` | Gear compartment target on apparatus | todo | `APP-001` |
| `TURN-002` | Don and doff through illenium-appearance | todo | `TURN-001` |
| `TURN-003` | Gear state survives disconnect and reconnect | todo | `TURN-002` |
| `TURN-004` | Real gear tiers wired to the Phase 1 exposure hooks | todo | `TURN-002`, `EXPO-002` |
| `HYD-001` | Hydrant registry and prop offsets | todo | `APP-002` |

## Later phases

Tasks are written when the phase starts. The scope of each is in the plan and summarised
in [BUILD.md](BUILD.md).

### Station alerting — Phase 6b, movable earlier

Only needs `PLACE-003` and `DISP-001`, so it can run ahead of Phase 6 if you want stations
alive sooner.

| ID | Task | Status | Depends on |
|---|---|---|---|
| `STN-001` | Station CRUD service over the schema | todo | `SETUP-009` |
| `STN-002` | `/firestation` tool: create, edit, place points | todo | `STN-001`, `PLACE-002` |
| `STN-003` | Coverage and interior polygons via the polygon builder | todo | `STN-002`, `PLACE-003` |
| `STN-004` | Hot apply: station changes take effect with no restart | todo | `STN-001` |
| `STN-005` | Zoned alerting: tones, lights, turnout timer | todo | `STN-003`, `DISP-001` |
| `STN-006` | Panel: acknowledge, silence, test tones, reset lights | todo | `STN-005` |
| `DOC-003` | `docs/guides/station-operations.md` | todo | `STN-006` |

### Remaining phases

| Phase | Scope |
|---|---|
| 3 | Hoses: pull, carry, lay, connect, charge, nozzles, crew slots |
| 4 | Pump operations, hydraulics on live lines, the React panel |
| 5 | Supply, relay, transfer, drafting, ground ladders |
| 6 | SCBA, PASS, hazmat |
| 6b | Station alerting |
| 7 | Water rescue |
| 8 | Polish |
