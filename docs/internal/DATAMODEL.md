# Data model

## What goes in the database, and what does not

The split is not "important things in MySQL". It is:

| Lives in `config/` | Lives in MySQL |
|---|---|
| Things you edit in a text editor | Things you build by walking around |
| Fire behaviour, agent effectiveness, gear numbers | Stations, their lights, speakers, panels, bays |
| Districts, area of play, run cards | Station coverage polygons |
| Hose, apparatus, and hydrant profiles | — |

A station is the clearest case for the database. Hand-editing
`{ x = -1193.4, y = -1487.2, z = 4.4 }` for every speaker in every bay of every station is
a job nobody finishes, and it produces coordinates nobody can verify by reading them.
Those rows are written in game by the placement tool.

Fire tuning is the opposite. You want to see all of it at once, diff it, and copy it
between servers. That is a file.

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

## Hot apply

Station changes take effect without a resource restart. The placement tool writes the row
and publishes the change; clients rebuild their local station view from that.

If a station change needs `restart mi_fire` to show up, the feature is not finished. This
is a verification step, not an aspiration — see `docs/internal/CONTRIBUTING.md`.
