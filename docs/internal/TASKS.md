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
| `EXPO-001` | Exposure model: the three damage channels | done | `FIRE-002` |
| `EXPO-002` | Gear resistance, integrity degradation, ignition threshold | done | `EXPO-001` |
| `EXPO-003` | Catching fire, self-extinguish, partner extinguish | done | `EXPO-002` |
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

### `SCORCH-002` — burn marks, parked

Working, but on the fallback renderer. Parked deliberately; picked up later.

Burn marks currently draw as flat dark marker discs. That works everywhere and cannot
silently fail, but it costs a draw call per visible mark and does not conform to a slope.

**Do not start by trying more decal type IDs.** That ground is covered: on the build this was
developed against, `AddDecal` accepts exactly five types — 1010, 1015, 1017, 1020, 1030 —
returns real non-zero handles for every one, and draws nothing. Tested at four metres across,
flat white, full opacity, with a marker directly overhead, indoors and outdoors, with both
the 0-1 and 0-255 colour conventions and with positive and negative timeouts. The native is
not refusing the call; something upstream of this resource is eating the result.

Worth trying when it comes back around, roughly in order of promise:

- Whether another resource on the server is clearing decals (`RemoveDecalsInRange` on a
  timer is a common thing for cleanup scripts to do, and it would produce exactly this).
- A streamed texture dictionary shipped with the resource and applied to a flat prop, which
  sidesteps the decal system entirely and conforms to the ground the way a marker cannot.
- `/fire decals sweep` on a different build, to establish whether this is the build or the
  server.

The marker path is good enough that this is polish, not a defect.

## Phase 2 — Placement, apparatus, turnout

| ID | Task | Status | Depends on |
|---|---|---|---|
| `SCORCH-002` | Burn marks: revisit the renderer | **parked** | — |
| `PLACE-001` | Shared placement gizmo: raycast preview, surface-normal orientation | **done** | — |
| `PLACE-002` | Gizmo: 6-DOF nudge, snap toggles, confirm and cancel | **done** | `PLACE-001` |
| `PLACE-003` | Polygon builder: walk the perimeter, close the loop, set height | todo | `PLACE-001` |
| `APP-001` | Apparatus profile schema and config | **done** | — |
| `APP-002` | Offset finder on the shared gizmo | **done** | `PLACE-002`, `APP-001` |
| `APP-003` | Offset finder: export to clipboard | **done** | `APP-002` |
| `APP-004` | Tank state: water and foam, per vehicle | **done** | `APP-001` |
| `APP-005` | Pump engage and disengage | **done** | `APP-004` |
| `TURN-001` | Gear compartment target on apparatus | done | `APP-001` |
| `TURN-002` | Don and doff through illenium-appearance | done | `TURN-001` |
| `TURN-003` | Gear state survives disconnect and reconnect | todo | `TURN-002` |
| `SCBA-001` | SCBA state machine: worn, active, air on item metadata | done | `TURN-002` |
| `SCBA-002` | Three equip routes: item, station rack, apparatus | done | `SCBA-001` |
| `SCBA-003` | Air consumption driven by exertion | done | `SCBA-001` |
| `SCBA-004` | Low-air warnings and automatic shutoff | done | `SCBA-003` |
| `SCBA-005` | PASS device, four phases | done | `SCBA-001` |
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
| `PANEL-000` | Panel photographs captured to `docs/Reference/PumpPanels/` | **done** | — |
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

### `HOSE-010` — the hose should lie where it was walked, parked

Working, but the rope follows the firefighter rather than staying where it was laid. Pulling a
line away from the rig drags the whole hose with you instead of leaving it on the ground
behind you.

**Do not start by adjusting slack or rope length.** That ground is covered: the rope is created
short and paid out, both ends are pinned every frame rather than attached, and three vertices
are pinned along the outlet axis at the rig. That is the shape SmartHose uses and it is correct
as far as it goes. More slack makes a longer rope between the same two moving points; it does
not make the hose stay put.

The reason is structural. Only two points are held — the coupling and the hand — so everything
between them is a free-hanging catenary that moves whenever either end does. A hose that stays
where it was laid needs the **path** recorded, not just the ends:

- Sample the nozzle holder's position as they walk, dropping a world point every metre or so.
- Pin intermediate rope vertices along that trail rather than leaving them free.
- Drop trail points when the crew moves *away* from the rig; consume them when they walk back,
  so the line takes itself in rather than doubling up.
- The trail is also the honest source for hose length used: distance along the path, not the
  straight line to the rig, which is what a real stretch around a corner costs.

Worth doing at the same time: a **dropped** line currently is not drawn at all, because nothing
records where it is when nobody is holding it. The trail solves that too -- the last point is
where the nozzle was put down.

`Supply-Line` on this drive lays a hose along a road and may already do the trail part; read it
before writing this, the way SmartHose should have been read before the rope.

### `HOSE-011` — crew slots, unverified in game

The state, the flow ceiling and the interactions are all written. **None of it has run with two
players.**

Working by inspection and by test: crew tracked per line, join, leave, take nozzle, the flow
ceiling (two on a 2.5 inch are capped at 179 gpm and told so), and a line surviving one hand
short when someone disconnects.

Fixed but unconfirmed: "Back up this line" was registered with `addGlobalPed`, which never
fires on a player ped, so it could not have appeared at all. Now on `addGlobalPlayer`. The
crew list was also sent as a set keyed by server id, which does not arrive at a client with one
meaning; it is a list now. Neither fix has been seen working.

Still modelled and wired to nothing -- correct, tested, unreachable, which is the same shape as
the gear that never burned through:

| | |
|---|---|
| `Hose.aimDrift` | the nozzle should wander when short-handed |
| `Hose.lossChance` | the line should get away, whip, and hurt |
| `Hose.dragWeight` / `dragSpeed` | charged hose should slow a crew down |

Wiring those is what makes a 2.5 inch a three-person line rather than a number in a config
file. `/fire hose` returns both the server's view and the client's in one block, which is the
tool for the next attempt.

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
