# Build

What `mi_fire` is, how it is laid out, and where to find things.

## What this is

A ground-up fire generation and firefighting resource for FiveM. It replaces a stack of
separate third-party resources — fires, hoses, supply lines, water monitors, SCBA — with
one system where those parts actually know about each other, because the interesting
behaviour lives in the seams between them.

The design goal is that the script teaches the job. A pump operator who knows real
fireground hydraulics should find the numbers on the panel mean what they mean, and a
player who does the wrong thing to the wrong class of fire should find out why.

## Design invariants

These are the claims the rest of the design rests on. Changing one is an ADR, not a tweak.

| Invariant | Where it is enforced |
|---|---|
| Nothing grants immunity to fire | `server/main.lua` boot validation, plus a test |
| Protection follows the clothing, however it got there | `shared/gearmatch.lua`, [ADR 0004](adr/0004-protection-follows-the-clothing.md) |
| Protective equipment is not job-locked; taking it off a rig is | `Config.gearRequiresJob`, `Permissions.requireFirefighter` |
| Smoke is stopped by SCBA and nothing else | `config/gear.lua` has no smoke field at all |
| The resource owns its damage; no native applies it for us | `bridge/medical/`, `ignition.particle` over `StartEntityFire` |
| The server owns all fire and water truth | `server/core/state.lua` |
| Every interaction is `ox_target` | `bridge/target/ox_target.lua` |
| Hydraulics are real, and testable outside the game | `shared/hydraulics.lua` |
| Things you build in game live in MySQL, not a config file | `install/migrations/`, `server/core/db.lua` |
| Station changes hot-apply without a restart | `server/modules/station/` |
| Sprinklers buy time, they do not win | `config/sprinklers.lua` tank sizing |

## Module map

| Path | Contains |
|---|---|
| `docs/` | User documentation. `docs/internal/` is the engineering record. |
| `config/` | All tuning. One file per system. Documented in `docs/configuration/`. |
| `install/migrations/` | Numbered, append-only SQL. Applied by the runner, never by hand. |
| `shared/` | Pure Lua used by both sides. Side-effect free and unit-testable. |
| `bridge/` | Every third-party integration. One adapter per resource. |
| `server/core/` | State, permissions, sync. No feature logic. |
| `server/modules/` | Feature services. Each owns its state and exposes functions. |
| `client/modules/` | Rendering, detection, interaction. No business logic. |
| `client/modules/targets/` | Every `ox_target` registration, in one readable place. |
| `client/modules/placement/` | Shared raycast-and-nudge gizmo, used by the offset finder and the station tool. |
| `web/` | NUI. Positional PASS audio and the fireground HUD today; the React pump panel lands here in Phase 4. |
| `tools/` | Test runner and specs. Runs outside FiveM. |

## Load order

`fxmanifest.lua` is the authority; this is why it is ordered the way it is.

1. `shared/enums.lua` — vocabulary, needed by everything
2. `shared/util.lua` — helpers, needed by config validation
3. `shared/hydraulics.lua` — pure math, no dependencies
4. `config/*.lua` — reads nothing, provides globals
5. `bridge/*` — needs config, detects what is running
6. `server/core/*` — needs bridge. `db.lua` before `state.lua`.
7. `server/main.lua` — validates config, runs migrations, then declares ready

Modules that need a bridge must not run at file scope; wait for `MIFire.ready`.

## Globals

One namespace, `MIFire`, holding the subsystem tables. Config files use their own globals
(`Config`, `MIFireGear`, `MIFireZones`, `MIFireClasses`, `MIFireAgents`) because that is
the convention every FiveM server owner already expects from a `config/` directory.

| Global | Set by |
|---|---|
| `MIFire.Enums` | `shared/enums.lua` |
| `MIFire.Util` | `shared/util.lua` |
| `MIFire.Hydraulics` | `shared/hydraulics.lua` |
| `MIFire.Framework` | `bridge/framework/init.lua` |
| `MIFire.Dispatch` | `bridge/dispatch/init.lua` (server) |
| `MIFire.Target` | `bridge/target/ox_target.lua` (client) |
| `MIFire.Appearance` | `bridge/appearance/illenium.lua` (client) |
| `MIFire.Inventory` | `bridge/inventory/ox_inventory.lua` (server) |
| `MIFire.DB` | `server/core/db.lua` |
| `MIFire.State` | `server/core/state.lua` |
| `MIFire.Permissions` | `server/core/permissions.lua` |
| `MIFire.FireClass` | `shared/fireclass.lua` |
| `MIFire.Suppression` | `shared/suppression.lua` |
| `MIFire.Fire` | `server/modules/fire/init.lua` |
| `MIFire.Spread` | `server/modules/fire/spread.lua` |
| `MIFire.Admin` | `server/modules/admin/init.lua` |
| `MIFire.Exposure` | `shared/exposure.lua` |
| `MIFire.GearMatch` | `shared/gearmatch.lua` |
| `MIFire.Integrity` | `shared/integrity.lua` |
| `MIFire.Pass` | `shared/pass.lua` |
| `MIFire.Smoke` | `shared/smoke.lua` |
| `MIFire.Medical` | `bridge/medical/init.lua` |
| `MIFire.Turnout` | `server/modules/turnout/init.lua` |
| `MIFire.ExposureServer` | `server/modules/exposure/init.lua` |
| `MIFire.SmokeServer` | `server/modules/smoke/init.lua` |
| `MIFire.Hud` | `client/modules/hud.lua` |

## Phase status

Phases are not worked strictly in order. Where a later phase's feature was needed to test an
earlier one -- turnout gear to survive a fire, SCBA to survive smoke -- it was built early
rather than stubbed, so the table below records what is actually in the tree.

| Phase | Scope | Status |
|---|---|---|
| 0 | Foundation: scaffold, bridges, config, test harness | **done** |
| 1 | Fire core: nodes, classes, agents, exposure, districts, AOP, generation, admin, exports | **mostly done** -- engine, suppression, three-channel exposure, smoke, admin and exports done and tested in game. Ambient generation and dispatch still unproven. |
| 2 | Placement gizmo, apparatus, offset finder, turnout | **partly done** -- turnout gear is complete and in game: tiers, recognition from clothing, coverage, integrity, condition, repair and replacement. The placement gizmo, `config/apparatus.lua` and `/fireoffset` are untouched, and until they exist any emergency-class vehicle counts as apparatus. |
| 3 | Hoses: pull, lay, connect, crew slots | todo |
| 4 | Pump operations and the panel | todo -- waiting on panel screenshots |
| 5 | Supply and ground ladders | todo |
| 6 | SCBA, PASS, hazmat | **partly done** -- SCBA air, exertion, alarms, refill and racking are in, as is the four-phase PASS device with positional audio. Hazmat, the accountability board, mayday and RIT are not started. |
| 6b | Station alerting, MySQL-backed and placed in game | **schema only** -- migrations and the runner exist; nothing places or alerts yet. |
| 6c | Sprinkler systems: install, activate, deplete, reset | **model only** -- config and the pure suppression model exist and are tested; nothing is installable in game. |
| 7 | Water rescue | todo |
| 8 | Polish | todo |

**Why 2 and 6 ran early.** Phase 1's exposure model damages players from the first fire, and
there is no way to test that a coat reduces damage without a coat, or that SCBA stops smoke
without a bottle. Both were built to the point where Phase 1 could be verified, and no
further -- which is why turnout is finished while the apparatus config it is nominally part
of does not exist yet.

See [TASKS.md](TASKS.md) for the task breakdown.
