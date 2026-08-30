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

## Phase 2 — Apparatus, offset finder, turnout

| ID | Task | Status | Depends on |
|---|---|---|---|
| `APP-001` | Apparatus profile schema and config | todo | — |
| `APP-002` | Offset finder: 6-DOF preview, snap to bone | todo | `APP-001` |
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

| Phase | Scope |
|---|---|
| 3 | Hoses: pull, carry, lay, connect, charge, nozzles, crew slots |
| 4 | Pump operations, hydraulics on live lines, the React panel |
| 5 | Supply, relay, transfer, drafting, ground ladders |
| 6 | SCBA, PASS, hazmat |
| 6b | Station alerting |
| 7 | Water rescue |
| 8 | Polish |
