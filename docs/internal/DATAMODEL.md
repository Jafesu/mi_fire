# Data model

## What goes in the database, and what does not

The split is not "important things in MySQL". It is:

| Lives in `config/` | Lives in MySQL |
|---|---|
| Things you edit in a text editor | Things you build by walking around |
| Fire behaviour, agent effectiveness, gear numbers | Stations, their lights, speakers, panels, bays |
| Districts, area of play, run cards | Station coverage polygons |
| Hose, apparatus, and hydrant profiles | Sprinkler systems and their heads |
| Gear tiers and their department appearance | Per-character name tapes and rank markings |
| Sprinkler head types, flow, reset procedure | Which heads exist, and their live state |

A station is the clearest case for the database. Hand-editing
`{ x = -1193.4, y = -1487.2, z = 4.4 }` for every speaker in every bay of every station is
a job nobody finishes, and it produces coordinates nobody can verify by reading them.
Those rows are written in game by the placement tool.

Fire tuning is the opposite. You want to see all of it at once, diff it, and copy it
between servers. That is a file.

Sprinklers add a second reason: **live state that must survive a restart.** How much water
a system has left, which heads have fused, whether it is in service — a system that ran dry
stays dry until a crew resets it, and a server restart is not a reset. That state has
nowhere to live but the database.

## Availability

`oxmysql` is a hard dependency of the manifest, because `@oxmysql/lib/MySQL.lua` is a
load-time include — without it the resource does not start at all. Qbox and ESX both
require it already.

What `server/core/db.lua` handles is the different failure: oxmysql running but the
database unreachable, credentials wrong, or the connection not up at boot. It proves the
connection with a `SELECT 1` rather than trusting the resource state, because a started
oxmysql with a bad connection string looks identical to a working one until the first real
query fails somewhere less convenient.

When that check fails, station features are disabled and **everything else runs normally**.
The fire core has no reason to care whether MySQL is answering.

## Migrations

Numbered files in `install/migrations/`, applied by the runner in `server/core/db.lua` and
recorded in `mi_fire_migrations`.

**Rules:**

- Never hand-run SQL. Add a numbered file.
- Never edit a migration that has shipped. Write a new one.
- Register the new file in the `MIGRATIONS` table in `db.lua`. It is listed explicitly
  rather than globbed, because FiveM cannot enumerate a resource directory at runtime and
  an ordering that depends on filesystem iteration order is an ordering waiting to change
  under you.
- Statements are split on semicolons by a deliberately naive splitter. A migration needing
  a stored procedure or a trigger would break it, and the right answer then is to not write
  one.

## Schema

### `mi_fire_stations`

| Column | Type | Notes |
|---|---|---|
| `id` | `INT UNSIGNED` PK | |
| `name` | `VARCHAR(64)` UNIQUE | Stable key used by run cards in `config/zones.lua` |
| `label` | `VARCHAR(128)` | What people see |
| `district` | `VARCHAR(64)` | Optional; a station may span districts |
| `x` `y` `z` `heading` | `DOUBLE` / `FLOAT` | Station origin, set where you stood when you created it |
| `jobs` | `JSON` | Which jobs this station serves |
| `enabled` | `TINYINT(1)` | Disable without deleting |

`name` is the join key to run cards. Renaming a station breaks its run card, so run cards
reference `name` and not `id` on purpose — the failure is visible instead of silent.

### `mi_fire_station_points`

Every placed point, whatever it does. One table rather than one per kind, because a light
and a speaker differ only in what happens when the tones drop. A new kind should be a row,
not a migration.

| Column | Notes |
|---|---|
| `station_id` | FK, `ON DELETE CASCADE` |
| `kind` | `light`, `speaker`, `panel`, `bay_door`, `apparatus_bay` |
| `x` `y` `z` | Where the raycast hit |
| `rot_x` `rot_y` `rot_z` | Derived from the surface normal, then nudged |
| `prop_model` | Optional |
| `metadata` | `JSON` — per-kind extras without a schema change |

Presentation for each kind is in `config/stations.lua`, not in the row. The database stores
*where a speaker is*; the config stores *how loud speakers are*. Moving the second into the
database would mean editing rows to retune audio.

### `mi_fire_station_zones`

Areas rather than points, drawn by walking the perimeter.

| Column | Notes |
|---|---|
| `station_id` | FK, `ON DELETE CASCADE` |
| `kind` | `coverage`, `interior`, `bay` |
| `vertices` | `JSON` array of `{ x, y }` |
| `min_z` `max_z` | Vertical extent |

`coverage` decides which station is toned for a call. A fire station is not a sphere, and
pretending it is puts the tones in the car park.

A station with no coverage polygon falls back to a circle of
`MIFireStations.defaults.fallbackCoverageRadius`, so a newly created station is immediately
useful and the polygon is a refinement rather than a prerequisite.

### `mi_fire_sprinkler_systems`

Building fire protection, installed by the fire department. Deliberately separate from the
station tables: a station is fire department property whose rows are static presentation,
while a sprinkler system is building infrastructure carrying live state.

| Column | Notes |
|---|---|
| `name` | Stable unique key |
| `system_type` | `wet`, `dry`, `preaction`, `deluge` |
| `agent` | `water`, `foam`, `wet_chem` — runs through the same matrix a hose line does |
| `riser_*` | Control valve position; where most of a reset happens |
| `fdc_*` | Fire department connection. Nullable — a system without one cannot be supplemented |
| `tank_gallons` / `tank_remaining` | Capacity and what is left. `tank_remaining` persists. |
| `status` | `armed`, `flowing`, `empty`, `needs_reset`, `impaired` |
| `in_service` | A closed valve. An impaired system does not flow. |

`agent` is the column that makes installation a decision rather than a formality. A water
system over a commercial kitchen makes a Class K fire *worse*, because `config/agents.lua`
scores `water` against `K` at `-0.8`. That is not a bug to special-case away — it is why
real kitchens have wet-chemical hood systems.

### `mi_fire_sprinkler_heads`

| Column | Notes |
|---|---|
| `system_id` | FK, `ON DELETE CASCADE` |
| `head_type` | `ordinary`, `intermediate`, `high`, `extra_high`, `esfr` |
| `x` `y` `z`, `rot_*` | Placed by aiming at a ceiling |
| `status` | `intact` or `fused` |
| `fused_at` | When it operated |

One row per head, because heads operate **individually**. Only the heads over the fire
fuse, each one is a separate device a crew has to replace, and storing a system as a single
coverage volume would lose exactly the behaviour worth having.

### `mi_fire_gear_appearance`

Per-character turnout markings. A department shares a drawable; the texture carries a name
tape and rank, so it is personal.

| Column | Notes |
|---|---|
| `identifier` | citizenid on Qbox, identifier on ESX |
| `tier` | Gear tier from `config/gear.lua` |
| `overrides` | `JSON` -- `{ slot = { drawable, texture } }`, or split by sex |
| `label` | Human-readable, e.g. "Casey / Deputy District Chief" |

Unique on `(identifier, tier)`, so a firefighter can be marked differently on structural
and wildland sets.

**Why this is not item metadata.** Two reasons, either of which is sufficient. Gear issued
from an apparatus rack has no item at all, so there would be nowhere to put it. And a coat
handed to another firefighter would carry the previous owner's name tape across with it,
which is worse than having no markings.

Overrides are merged over the tier's base appearance at don time, so a character stores
only what differs -- usually a single texture. A firefighter with no row wears the plain
department set, which is also what happens when the database is unreachable.

Written through `exports.mi_fire:SetGearAppearance(identifier, tier, overrides, opts)`,
which takes an identifier rather than a source because markings are normally assigned from
an admin panel while the firefighter is offline.

## Hot apply

Station changes take effect without a resource restart. The placement tool writes the row
and publishes the change; clients rebuild their local station view from that.

If a station change needs `restart mi_fire` to show up, the feature is not finished. This
is a verification step, not an aspiration — see `docs/internal/CONTRIBUTING.md`.
