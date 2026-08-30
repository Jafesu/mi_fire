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
| `SETUP-010` | Sprinkler schema and configuration | done |
| `SETUP-011` | Testable config validation and boot simulation | done |

## Phase 1 — Fire core

| ID | Task | Status | Depends on |
|---|---|---|---|
| `FIRE-001` | Fire class and agent configuration | done | `SETUP-002` |
| `FIRE-002` | Node lifecycle: ignite, grow, consume fuel, go out | done | `FIRE-001` |
| `FIRE-003` | Propagation: spread rolls, wind, spread caps | done | `FIRE-002` |
| `FIRE-004` | Incident merge when scenes touch | todo | `FIRE-003` |
| `FIRE-005` | Suppression: agent matrix, knockdown, reflash, overhaul | done | `FIRE-002` |
| `FIRE-006` | Hazards: spread, shock, explosion, flare, reaction | done | `FIRE-005` |
| `FIRE-007` | Client rendering: PTFX, sound, intensity scaling, render distance | done | `FIRE-002` |
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
| `ADMIN-001` | `/fire` command family | done | `FIRE-002` |
| `ADMIN-002` | `/aop` and `/district` commands | todo | `ZONE-002` |
| `API-001` | SmartFires-compatible export surface | done | `FIRE-002` |
| `API-002` | Native mi_fire export surface | done | `API-001` |
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
| `TURN-001` | Gear compartment target on apparatus | done | `APP-001` |
| `TURN-002` | Don and doff through illenium-appearance | done | `TURN-001` |
| `TURN-003` | Gear state survives disconnect and reconnect | todo | `TURN-002` |
| `SCBA-001` | SCBA state machine: worn, active, air on item metadata | done | `TURN-002` |
| `SCBA-002` | Three equip routes: item, station rack, apparatus | done | `SCBA-001` |
| `SCBA-003` | Air consumption driven by exertion | done | `SCBA-001` |
| `SCBA-004` | Low-air warnings and automatic shutoff | done | `SCBA-003` |
| `SCBA-005` | PASS device, four phases | todo | `SCBA-001` |
| `DOC-006` | `docs/guides/scba-and-air.md` | done | `SCBA-004` |
| `TURN-004` | Real gear tiers wired to the Phase 1 exposure hooks | done | `TURN-002`, `EXPO-002` |
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

### Sprinkler systems — Phase 6c

Fire protection the department installs in buildings. Needs the placement gizmo, the
suppression model, and the supply work for the fire department connection.

| ID | Task | Status | Depends on |
|---|---|---|---|
| `SPK-001` | System CRUD service over the schema | todo | `SETUP-010` |
| `SPK-002` | `/sprinkler` tool: install a system, place riser and FDC | todo | `SPK-001`, `PLACE-002` |
| `SPK-003` | Head placement against ceilings, with type and coverage preview | todo | `SPK-002` |
| `SPK-004` | Activation: per-head heat triggering, system type delays, deluge | todo | `SPK-003`, `EXPO-001` |
| `SPK-005` | Flow and suppression through the agent matrix, tank depletion | todo | `SPK-004`, `FIRE-005` |
| `SPK-006` | Waterflow alarm dispatch, retard timer, depletion escalation | todo | `SPK-005`, `DISP-001` |
| `SPK-007` | FDC: supply a system from an engine, boosted pressure, tank refill | todo | `SPK-005`, Phase 5 |
| `SPK-008` | Reset: close, drain, replace fused heads, refill, return to service | todo | `SPK-005` |
| `SPK-009` | Impairment: close a valve, report it on dispatch | todo | `SPK-001` |
| `DOC-004` | `docs/guides/sprinkler-systems.md` | todo | `SPK-008` |

### Pump panel — Phase 4

Designed in full; see [adr/0003](adr/0003-panels-are-data-not-code.md) and
[APPARATUS.md](APPARATUS.md). **Blocked on reference screenshots** of the in-game panels, which
the user is capturing. Authoring a layout from guesswork means building it twice.

| ID | Task | Status | Depends on |
|---|---|---|---|
| `PANEL-001` | Layout schema: grid, widget types, data bindings | todo | — |
| `PANEL-002` | React renderer, widget components, theme system | todo | `PANEL-001` |
| `PANEL-003` | Auto-generated fallback from apparatus ports | todo | `PANEL-002`, `APP-001` |
| `PANEL-004` | Boot validation: layout `portId`s must exist on the apparatus | todo | `PANEL-001` |
| `PANEL-005` | `engine` family, authored against `EengineHT` | todo | `PANEL-003`, screenshots |
| `PANEL-006` | `puc` family — proves families are real, not skins | todo | `PANEL-005`, screenshots |
| `PANEL-007` | `brush` family against `brushtruck` — no panel geometry at all | todo | `PANEL-003` |
| `PANEL-008` | Physical panel deployment via the mod slot, opt-in per model | todo | `PANEL-005` |
| `PANEL-009` | Shared panel state so two operators see each other's valves | todo | `PANEL-002` |
| `DOC-005` | `docs/guides/pump-operations.md` | todo | `PANEL-005` |

`ladder`, `tower`, and `tanker` families follow in Phase 5 with the aerial and supply work their
controls depend on.

### Remaining phases

| Phase | Scope |
|---|---|
| 3 | Hoses: pull, carry, lay, connect, charge, nozzles, crew slots |
| 4 | Pump operations, hydraulics on live lines, the React panel |
| 5 | Supply, relay, transfer, drafting, ground ladders |
| 6 | SCBA, PASS, hazmat |
| 6b | Station alerting |
| 6c | Sprinkler systems |
| 7 | Water rescue |
| 8 | Polish |
