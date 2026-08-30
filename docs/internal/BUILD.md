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
| Protection comes from server state, never clothing | `server/core/state.lua`, `bridge/appearance/` |
| Smoke is stopped by SCBA and nothing else | `config/gear.lua` has no smoke field at all |
| The server owns all fire and water truth | `server/core/state.lua` |
| Every interaction is `ox_target` | `bridge/target/ox_target.lua` |
| Hydraulics are real, and testable outside the game | `shared/hydraulics.lua` |

## Module map

| Path | Contains |
|---|---|
| `docs/` | User documentation. `docs/internal/` is the engineering record. |
| `config/` | All tuning. One file per system. Documented in `docs/configuration/`. |
| `shared/` | Pure Lua used by both sides. Side-effect free and unit-testable. |
| `bridge/` | Every third-party integration. One adapter per resource. |
| `server/core/` | State, permissions, sync. No feature logic. |
| `server/modules/` | Feature services. Each owns its state and exposes functions. |
| `client/modules/` | Rendering, detection, interaction. No business logic. |
| `client/modules/targets/` | Every `ox_target` registration, in one readable place. |
| `web/` | React + Vite + TypeScript pump panel. |
| `tools/` | Test runner and specs. Runs outside FiveM. |

## Load order

`fxmanifest.lua` is the authority; this is why it is ordered the way it is.

1. `shared/enums.lua` — vocabulary, needed by everything
2. `shared/util.lua` — helpers, needed by config validation
3. `shared/hydraulics.lua` — pure math, no dependencies
4. `config/*.lua` — reads nothing, provides globals
5. `bridge/*` — needs config, detects what is running
6. `server/core/*` — needs bridge
7. `server/main.lua` — validates config, then declares ready

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
| `MIFire.State` | `server/core/state.lua` |
| `MIFire.Permissions` | `server/core/permissions.lua` |

## Phase status

| Phase | Scope | Status |
|---|---|---|
| 0 | Foundation: scaffold, bridges, config, test harness | **done** |
| 1 | Fire core: nodes, classes, agents, exposure, districts, AOP, generation, admin, exports | in progress |
| 2 | Apparatus, offset finder, turnout | todo |
| 3 | Hoses: pull, lay, connect, crew slots | todo |
| 4 | Pump operations and the panel | todo |
| 5 | Supply and ground ladders | todo |
| 6 | SCBA, PASS, hazmat | todo |
| 6b | Station alerting | todo |
| 7 | Water rescue | todo |
| 8 | Polish | todo |

See [TASKS.md](TASKS.md) for the task breakdown.
