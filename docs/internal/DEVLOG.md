# Development log

Append-only record of every working session. **Newest entries at the bottom.**

Never edit or delete an earlier entry. If a past entry turns out to be wrong, write a new
one saying so — the record of what we believed at the time is part of the value.

## Template

```md
## YYYY-MM-DD · session NNN

**Scope:** task IDs worked
**Changed:** the files that matter, not every file
**Decisions:** anything a later session could reverse by accident. Link the ADR if you wrote one.
**Verified:** what you actually ran, and the result. Say "not verified" if you did not.
**Open:** known-incomplete work, with task IDs
**Next:** the obvious next task
```

**Verified** is the field that matters. Write what you ran, not what you believe.
"Tests pass, not loaded in game yet" is useful. "works" is not.

---

## 2026-08-30 · session 001

**Scope:** `SETUP-001`…`SETUP-008`, `FIRE-001`

**Changed:** repository scaffold from empty. `fxmanifest.lua`, `.gitignore`,
`shared/{enums,util,hydraulics}.lua`, `config/{config,dispatch,zones,fire_classes,agents,gear}.lua`,
`bridge/framework/init.lua`, `bridge/dispatch/init.lua`, `bridge/target/ox_target.lua`,
`bridge/appearance/illenium.lua`, `bridge/inventory/ox_inventory.lua`,
`server/core/{state,permissions}.lua`, `server/main.lua`, `client/main.lua`,
`tools/run_tests.lua`, `tools/tests/hydraulics_spec.lua`, and the `docs/` tree.

**Decisions:**

- `shared/hydraulics.lua` is pure Lua with no game natives, so the pressure model can be
  tested outside FiveM. Every constant in it is a published fire service figure, not a
  tuning value — the comments name which. Tuning belongs in `config/hose.lua`.
- Real friction-loss coefficients, `Q = 29.7·d²·√NP` for smooth bore, NFPA 1901 pump
  curve, and the percent-drop rule for hydrant capacity. Two worked problems from the
  plan are asserted directly: 200 ft of 1.75″ at 150 gpm on a 100 psi fog nozzle gives
  PDP 169.75, and 500 ft of 5″ at 1000 gpm loses 40 psi.
- `config/agents.lua` allows **negative** effectiveness. Water on a Class D fire is −1.0
  and fires an explosion hazard. A script that clamps that to zero teaches the wrong
  lesson, so it does not.
- Gear grants resistance, never immunity. Enforced in three places: boot validation in
  `server/main.lua` refuses to start an invalid config, a test asserts every tier, and
  `config/gear.lua` says so at the top. Smoke has no gear field at all — SCBA is the only
  defence, by construction rather than by convention.
- Protection is read from `server/core/state.lua`, never from what a player is wearing.
  A turnout skin from a clothing menu grants nothing.
- Hazmat suits have *worse* fire resistance than turnout (Level A is 0.15 against
  structural's 0.75) and far better chemical resistance. That trade is real and the config
  should let you walk into it.
- Framework bridge auto-detects Qbox, then ESX, then falls back to standalone. Because of
  that, `qbx_core` was removed from `dependencies` in the manifest — hard-depending on it
  would break the two adapters that exist to avoid exactly that.
- `@oxmysql` removed from `server_scripts`: nothing persists yet, and a DB dependency that
  is not used is a dependency that breaks servers for no benefit.
- Dispatch goes to **lb-tablet**, not ejds-dispatchv2. Payload shape was read off a
  working integration in `mi_gunrunner/server/shipments.lua:151` rather than guessed. The
  provider abstraction matches `mi_gunrunner/config.lua` so the two configure alike.
- `docs/internal/` holds the engineering record; everything else in `docs/` is written for
  players and server owners, following the GitBook layout already used in `ejds-sl`.

**Verified:**

- `lua tools/run_tests.lua` — **94 passed, 0 failed**. Covers coefficients, friction loss
  including the parallel-line case, smooth bore and fog nozzle flow against published tip
  figures, elevation, appliance loss, five worked PDP problems, the pump curve, percent
  drop, cavitation, tank time, and the gear-immunity invariant.
- `luac -p` on all 21 Lua files — all parse.
- **Not** loaded in a running server yet. No in-game verification of any kind has been
  done; the resource has never been started. Everything above is static verification only.

**Open:**

- `FIRE-002`…`FIRE-010`: the node engine itself does not exist yet. Config describes
  behaviour nothing implements.
- No exports yet, so `mi_fire_rescue` cannot be repointed.
- District geometry is placeholder spheres. Real boundaries need `/district here` to walk,
  which needs the resource running.
- `config/gear.lua` appearance drawable IDs are all `-1`. They need the server's actual
  EUP pack, which is a Phase 2 job.

**Next:** `FIRE-002` — the fire node lifecycle in `server/modules/fire/`, then the
class/agent matrix applied to suppression, then exports.

---

## 2026-08-30 · session 002

**Scope:** `SETUP-009`, plus design for `PLACE-001`…`PLACE-003` and `STN-001`…`STN-006`

**Changed:** `install/migrations/0001_stations.sql`, `server/core/db.lua`,
`config/stations.lua`, `fxmanifest.lua`, `server/main.lua`,
`docs/internal/DATAMODEL.md`, `docs/internal/{BUILD,TASKS}.md`.

**Decisions:**

- Station configuration moves to MySQL. The split is not "important things in the
  database" — it is *things you edit in a text editor* versus *things you build by walking
  around*. Fire tuning wants to be diffed and copied between servers, so it stays a file.
  A speaker position wants to be placed by looking at a wall, so it is a row.
- One `mi_fire_station_points` table for every placed kind rather than one per kind. A
  light and a speaker differ only in what happens when the tones drop, so a new kind
  should be a row, not a migration.
- Placement is a raycast tool: aim at a surface, the preview snaps to the hit point and
  takes its rotation from the surface normal, so a wall-mounted speaker sits flat without
  anyone typing a rotation. Fine adjustment reuses the 6-DOF nudge from the offset finder.
- The offset finder and the station tool therefore share one gizmo in
  `client/modules/placement/`, rather than two that drift apart. That is why the placement
  tasks moved to the front of Phase 2 — Phase 6b depends on them.
- A polygon builder covers areas: walk the perimeter dropping vertices, close the loop,
  set the height. Station coverage is not a sphere, and pretending it is puts the tones in
  the car park. A station with no polygon falls back to a radius so it is useful
  immediately and the polygon is a refinement rather than a prerequisite.
- Presentation stays in `config/stations.lua` while position goes in the database. The row
  says *where a speaker is*; the config says *how loud speakers are*. Putting the second
  in the database would mean editing rows to retune audio.
- Station changes must hot-apply. Recorded as a verification step, not an aspiration.

**Correction to session 001:** that session removed `@oxmysql` from the manifest and
described the database integration as gracefully degrading. That was wrong.
`@oxmysql/lib/MySQL.lua` is a **load-time include** — without oxmysql the resource does
not start at all, so any claim of degradation would have been false. `oxmysql` is now a
declared hard dependency, which Qbox and ESX both require anyway. `server/core/db.lua`
still handles the genuinely different failure of oxmysql running but the database being
unreachable, and proves the connection with `SELECT 1` rather than trusting the resource
state — a started oxmysql with bad credentials looks identical to a working one until the
first real query fails somewhere less convenient.

**Verified:**

- `lua tools/run_tests.lua` — 94 passed, 0 failed. Unchanged; nothing this session touched
  the hydraulics.
- `luac -p` on all 22 Lua files — all parse.
- **Not** verified in game. The migration runner has never been executed against a real
  database, so `0001_stations.sql` is unproven — a syntax error in it would only surface on
  first boot. That is the first thing to check next session.

**Open:**

- Everything in Phase 1 remains untouched; the node engine still does not exist.
- `MIGRATIONS` in `db.lua` is a hand-maintained list. Adding a migration file without
  registering it there is a silent no-op, and nothing currently catches that.
- The statement splitter is naive: it splits on semicolons after stripping line comments.
  Any migration needing a stored procedure or trigger would break it.

**Next:** `FIRE-002` — the node lifecycle. The database work is foundation, not progress
toward a playable fire.

---

## 2026-08-30 · session 003

**Scope:** `SETUP-010`, plus design for `SPK-001`…`SPK-009`

**Changed:** `config/sprinklers.lua`, `install/migrations/0002_sprinklers.sql`,
`shared/enums.lua`, `server/core/db.lua`, `fxmanifest.lua`,
`tools/tests/sprinklers_spec.lua`, `tools/run_tests.lua`, `docs/internal/DATAMODEL.md`,
`docs/internal/{BUILD,TASKS,CHANGELOG}.md`.

**Decisions:**

- Sprinklers get their **own tables**, not `mi_fire_station_points`. The request framed
  them as station config, and they do share the placement tooling and the MySQL-backed
  pattern — but a station is fire department property whose rows are static presentation,
  while a sprinkler system is building infrastructure carrying live state. Squeezing state
  into the points table would have meant a `metadata` blob doing the work of real columns.
- That live state is the second reason sprinklers belong in the database at all: water
  remaining, which heads have fused, whether the system is in service. **A server restart
  is not a reset.**
- One row per head, because heads operate **individually** — only the ones that get hot
  enough fuse. This is the detail fiction always gets wrong, and it is what makes an
  activation readable on scene. Storing a system as a single coverage volume would have
  lost exactly the behaviour worth having.
- Head flow uses the real orifice formula `Q = K·√P`, the same relationship as a smooth
  bore nozzle. K5.6 at 15 psi lands on the published 21.7 gpm.
- Systems discharge through the **existing agent matrix**, so a water system over a
  commercial kitchen makes a Class K fire worse. Not special-cased away — it is why real
  kitchens have wet-chemical hood systems, and it makes installing the right system a
  decision rather than a formality. Tested directly.
- The **fire department connection** is the tactical payoff and the reason this is not
  scenery: when the tank runs dry, a crew that lays a line to the FDC keeps the heads
  flowing off the engine at 45 psi instead of the tank's 15. That ties sprinklers into the
  Phase 5 supply work, so `SPK-007` depends on it.
- The **waterflow alarm is the call**. A protected building generates its own dispatch
  after a retard timer, which is a genuinely different feel from a passer-by phoning it in.
  Running dry with fire still burning escalates, because the building just lost its
  protection.
- Reset is five ox_target steps with replacement heads as an inventory item, and
  `autoResetSeconds` is deliberately `nil`. Nothing quietly fixes a system on a timer.
- Placed at **Phase 6c**, after station alerting. It needs the placement gizmo (Phase 2),
  the suppression model (Phase 1), and Phase 5 for the FDC.

**Verified:**

- `lua tools/run_tests.lua` — **136 passed, 0 failed** (94 hydraulics, 42 sprinkler).
- Sprinkler flow asserted against the published K5.6 figure, and the square-root
  relationship checked directly rather than assumed.
- The design invariant is now a test, not a comment: two heads run 17 minutes on the
  default tank, six drain it in under six, and even the largest configurable tank cannot
  outlast an hour of serious flow. A tuning change that turned sprinklers into a win
  button would fail the suite.
- `luac -p` on all 24 Lua files — all parse.
- **Not** verified in game. Neither migration has ever run against a real database, so
  both `0001_stations.sql` and `0002_sprinklers.sql` remain unproven — a syntax error in
  either would only surface on first boot.

**Open:**

- Phase 1 is still untouched. Three sessions of foundation and configuration; no fire has
  ever burned.
- `activationHeat` values are calibrated against a heat scale that `EXPO-001` has not
  built yet. They are reasonable-looking numbers on an axis with no implementation, and
  will almost certainly need retuning once heat actually accumulates.
- Sprinkler suppression assumes `FIRE-005` will expose a way to apply an agent to nodes in
  a radius. That interface does not exist yet.

**Next:** `FIRE-002`, the node lifecycle. Foundation is well ahead of the engine now, and
the gap should close before more configuration is written.

---

## 2026-08-30 · session 004

**Scope:** `SETUP-011` — boot simulation and testable config validation

**Changed:** `shared/validate.lua` (new), `tools/tests/boot_spec.lua` (new),
`server/main.lua`, `fxmanifest.lua`, `tools/run_tests.lua`,
`docs/getting-started/installation.md`.

**Decisions:**

- Config validation moved out of `server/main.lua` into `shared/validate.lua` as a pure
  function taking the config tables as arguments rather than reading globals. That is what
  makes the real boot check runnable outside FiveM, and it lets a test feed it a
  deliberately broken config without mutating the shipped one.
- Added a boot simulation that stubs the natives and loads every server-side file in
  manifest order, then runs validation. It does not prove anything works — only a real
  boot does that. What it removes is the class of failure that costs a server restart
  each to find: a file referencing something not loaded yet, a global that never gets set,
  a typo that only executes at boot.
- The stubs report every optional resource as missing, so the simulated boot exercises the
  path where ox_target, lb-tablet, oxmysql, and the framework are all absent. That is the
  case most likely to be broken and least likely to be tested by hand.
- The boot test cross-checks its own file list against `fxmanifest.lua`. Without that, a
  file added to the manifest would silently stop being boot-checked, which is how a test
  like this rots into decoration.
- Validation gained checks it did not have: AOP mode, district shape well-formedness,
  districts naming unknown fire classes, agents missing a fire class, and hazards named by
  the matrix but never defined. Each is tested by feeding it the broken config, because a
  validation rule that never fires is not a rule.

**Correction to session 001:** `docs/getting-started/installation.md` told readers to
verify the install with `/fire here` and `/fire list`. Those commands do not exist —
`ADMIN-001` has not been written. Shipping a verification step that cannot work was worse
than shipping none. Replaced with what a first boot can actually demonstrate: a clean load,
the debug line naming the detected integrations, two rows in `mi_fire_migrations`, and a
double restart. The section now opens by saying the fire engine is not built yet.

**Verified:**

- `lua tools/run_tests.lua` — **208 passed, 0 failed** (72 boot, 94 hydraulics, 42
  sprinkler). Up from 136.
- The full server-side load order executes cleanly with every optional resource absent,
  and `server/main.lua`'s boot thread runs to completion, emitting the two expected
  warnings for missing dispatch and missing database.
- All 26 Lua files parse.
- **Still not verified on a real server.** No FiveM server on this machine can run it: the
  two FXServer installs under `c:/fivem` are NexusCore templates whose resource folders
  hold no `ox_lib`, `ox_target`, or `qbx_core`, and neither points at this resource tree.
  The migrations remain unproven — the boot simulation stubs `LoadResourceFile` to return
  nil, so it never reads the SQL, let alone executes it.

**Open:**

- Phase 1 still untouched. Four sessions in, no fire has burned.
- The migration SQL is the single largest unverified thing in the repo and can only be
  proven by a real boot.
- Client-side files are excluded from the boot simulation. They need natives and ox_lib's
  `cache` in ways the stubs do not honestly reproduce, and a fake pass there would be
  worse than no test.

**Next:** a real boot on the Qbox server, checking `mi_fire_migrations` has two rows. Then
`FIRE-002`, the node lifecycle.

---

## 2026-08-30 · session 005

**Scope:** first real boot — `SETUP-009` and `SETUP-010` verified in game

**Changed:** nothing. This entry records a verification, not a change.

**Verified:**

First boot on the live Qbox server. The resource had never been started before this.

- `ensure mi_fire` — **started clean, zero errors, zero warnings.**
- Migration runner worked end to end. `mi_fire_migrations` created, then
  `applied migration 0001_stations` and `applied migration 0002_sprinklers` both logged,
  in order. This was the single largest unverified thing in the repo and it is now proven.
- `ensure` run three times total: the resource stopped and restarted twice with no
  teardown errors and no duplicate-registration complaints. That is the double-restart
  check from `CONTRIBUTING.md`, passed.
- oxmysql integration confirmed against MariaDB 12.1.2.

**On the log looking short:** oxmysql printed only one `CREATE TABLE` per migration, which
looked like the statement splitter dropping everything after the first semicolon. It is
not. `took Xms to execute a query!` is oxmysql's **slow-query warning**, not a query log —
it prints only above a threshold, so the faster statements ran silently. Confirmed by
running the real `splitStatements` against both migration files outside the game: 3
statements for `0001_stations`, 2 for `0002_sprinklers`, all five correct. Worth writing
down because the log genuinely reads like a bug and the next person to see it will think
the same thing.

**Not** confirmed at the database: `SHOW TABLES LIKE 'mi_fire%'` should return six rows.
The evidence above is strong but indirect, and the tables have not been listed.

**Also expected, not a fault:** the `[mi_fire:boot] framework=... dispatch=... database=...`
line did not appear, because `Config.debug` defaults to `false` and that line is debug-only.

**Notes for later:**

- Server thread hitch warnings of 211 ms and 670 ms appeared around resource start. The
  447 ms `CREATE TABLE` suggests migrations contribute, but hitches also showed on the
  restarts where no migration ran, so this is more likely ordinary resource-start
  overhead. Not chasing it now; worth re-checking once there is a simulation tick.

**Open:** unchanged. Phase 1 is still untouched and no fire has burned.

**Next:** `FIRE-002`, the node lifecycle. The foundation is now verified rather than
assumed, and there is no remaining excuse to keep writing configuration.

---

## 2026-08-30 · session 006

**Scope:** `FIRE-002`, `FIRE-003`, `FIRE-005`, `FIRE-006`, `FIRE-007`, `ADMIN-001`,
`API-001`, `API-002`

**Changed:** `shared/fireclass.lua`, `shared/suppression.lua`,
`server/modules/fire/{init,spread}.lua`, `server/modules/admin/init.lua`,
`server/api/exports.lua`, `client/modules/fire/init.lua`, `client/modules/notify.lua`,
`tools/tests/fire_spec.lua`, `fxmanifest.lua`, `tools/tests/boot_spec.lua`.

**The engine exists.** A fire now ignites, grows, consumes fuel, spreads, can be knocked
down, reflashes if left, and goes out when the fuel is gone.

**Decisions:**

- Class resolution and the suppression maths went into `shared/` as pure functions, same
  reasoning as the hydraulics: the numbers that decide whether water works are worth being
  able to check outside the game. `server/modules/fire/` is then mostly bookkeeping.
- **One entry point for suppression.** Hose lines, extinguishers, sprinklers, the admin
  command, and `ApplyFireDamageAtCoords` all route through `Fire.applyAgent`. A future
  water source cannot bypass the agent matrix by being added somewhere else.
- Negative knockdown is applied as growth rather than clamped, and fires the configured
  hazard. Water on a Class B pool genuinely makes the incident worse. Tested directly.
- Fuel burns proportionally to intensity, so a developed fire eats its fuel faster than a
  smouldering one and a fire held down by a crew lasts longer. That falls out of one line
  rather than a special case.
- Knockdown is not extinguishment. A node driven to zero intensity goes to `KNOCKED_DOWN`
  with its fuel intact and may schedule a reflash. Sustained application after knockdown
  is overhaul, which cancels the reflash and makes it permanent. This is the loop that
  makes putting a fire out an activity rather than a moment.
- Spread scales with intensity, so a fire being fought spreads more slowly even before it
  is knocked out. Wind is one slowly drifting global vector, blended by per-class
  `windInfluence` -- wildland runs with it, everything else ignores it.
- Spread refuses to place a node within half a spread radius of an existing one. Without
  that, a scene becomes a pile rather than a fire.
- Client renders with particles rather than `StartScriptFire`. Script fires are capped,
  spread on their own schedule, and cannot be sized -- all three fight a
  server-authoritative model. Particles cost manual cleanup, which is what the handle
  trackers in `client/main.lua` are for.
- Sync is one batched event per tick, not one per node. A spreading wildland fire changes
  dozens of nodes in the same tick.
- `/fire agent <agent>` exists as the test harness for the matrix, and is the only way to
  put a fire out until hose lines land in Phase 3.
- Exports that depend on unbuilt systems return empty rather than erroring, and
  `CONTRACTS.md` now has a "Not implemented" section naming what each is waiting on. A
  consumer that iterates the result keeps working; one that expects behaviour finds out
  from the docs.

**Verified:**

- `lua tools/run_tests.lua` -- **273 passed, 0 failed** (was 208).
- `fire_spec.lua` drives the real engine with a controllable clock: growth, fuel
  exhaustion, knockdown, reflash, overhaul, spread, class caps, incident caps, and
  stopAll leaving no orphaned nodes.
- The behaviours that justify the whole design are asserted, not assumed: water on Class B
  adds intensity while foam removes it; ABC dry chemical does literally nothing to a
  Class D fire while dry powder works; point-blank beats long range; a bigger line beats a
  smaller one but not proportionally.
- All 30 Lua files parse.
- **Not** run in game. No fire has been seen on a screen.

**Fixed in the harness:** the boot simulation hung once the engine added
`while true do Wait() end` threads, because `Wait` was a no-op stub. It now throws a
sentinel so a thread unwinds at its first yield, and reaching a yield counts as success.
Two `fire_spec` assertions also failed initially and were the test's fault, not the
engine's -- Class A burns 0.075 fuel per tick, so draining 0.5 fuel needs seven ticks and
the test allowed three.

**Open:**

- `EXPO-001`: fire does not hurt players yet. Hazards damage, ordinary flame does not.
- `FIRE-004` merge, `FIRE-008` smoke, `FIRE-009` interiors, `FIRE-010` vehicle fires.
- `ZONE-*` and `GEN-*`: nothing generates on its own; every fire is admin- or export-started.
- No dispatch is raised yet -- `DISP-001` needs run cards.
- `API-003`: `mi_fire_rescue` still points at the old resource. The export shape is
  written to match but has never been tested against it.
- Particle asset and name are guesses carried over from the old config and may look wrong
  in game.

**Next:** boot it and light one. `/fire here`, then `/fire agent water`, then
`/fire start B` and water it to watch the matrix bite. After that, `EXPO-001`.

---

## 2026-08-30 · session 007

**Scope:** pump panel architecture — design and documentation only. No code.

**Changed:** `docs/internal/adr/0003-panels-are-data-not-code.md`,
`docs/internal/APPARATUS.md`, `docs/internal/TASKS.md`.

**Why no code:** Phase 4 is gated on Phase 1-3, and on reference screenshots of the in-game
panels that do not exist yet. The session 006 engine also has not been tested in game. Building
on top of an untested engine, toward an unbuildable phase, would have been motion rather than
progress.

**Decisions:**

- **A panel is data, not code.** One renderer, a layout file per model. The alternative is seven
  React frontends that drift apart, where every apparatus added later is a new frontend project.
  Full reasoning in ADR 0003.
- Panels vary along four axes — family, theme, modules, per-model overrides — and that is far
  less variation than it looks. A Pierce side-mount and an E-ONE side-mount are about ninety
  percent the same panel.
- **The truck pack settled the family split.** `2026firetrucks` ships four modelled pump panels
  (`Pump_Panelengine`, `Pump_Panelladdder`, `Pump_Paneltower`, `Pump_PanelPUC`), so families are
  a fact about the apparatus rather than a taxonomy we invented.
- PUC gets its own family rather than a theme. Pierce Ultimate Configuration is a real
  single-pump architecture with no separate pump house, operated differently.
- **The panel is a mod slot.** `Pump_Panelengine` sits on `VMT_HYDRO` and turns off bone
  `misc_p`; intake fittings sit on `VMT_WING_L`. Opening the NUI can physically open the panel on
  the truck. Opt-in per model, because it makes mi_fire partly responsible for the vehicle's
  appearance and can fight a customs resource.
- **The auto-generated fallback is built first**, before any authored layout. It makes the
  feature useful immediately and it is the path that otherwise never gets tested, because the
  authored panels look better.
- Panel discharges bind to `portId`s from `config/apparatus.lua`, validated at boot. A panel
  promising a discharge the truck does not have should fail at startup, not mid-incident.

**Findings, recorded in `APPARATUS.md`:**

- `brushtruck` ships **no mod kit at all** and uses extras rather than mod slots. No panel
  geometry to deploy, so its panel is pure NUI — which makes it the honest test of the generated
  fallback, and the reason `brush` is built early despite being last in priority.
- **`alamolhp` is not a fire rig.** It is a police Alamo from a law-enforcement pack. It was
  listed as brush apparatus earlier in this session on the strength of its filename; that was
  wrong and is corrected in `APPARATUS.md`.
- Both packs ship `RSC7`-compressed models, so **bone names, extra indices, and connection
  geometry cannot be read from disk** — confirmed by attempting it. Everything positional has to
  be found in game with `/fireoffset`. Written down so a later session does not repeat the
  attempt.

**Verified:** nothing to verify — no code changed. Tests were green at 273 when this session
started and were not re-run, because nothing touched them.

**Open:** unchanged from session 006. The engine is still untested in game, `EXPO-001` is still
the next real work, and Phase 4 is blocked on the phases in front of it plus screenshots.

**Next:** the user's in-game test of the fire engine. Then `EXPO-001`.

---

## 2026-08-30 · session 008

**Scope:** `ADMIN-002` — permissions. Reported from the first attempt to run the commands
in game: `/fire` refused with a missing ACE permission.

**Changed:** `config/config.lua`, `server/core/permissions.lua`,
`server/modules/admin/init.lua`, `shared/util.lua`, `shared/validate.lua`,
`tools/tests/permissions_spec.lua`, `tools/tests/boot_spec.lua`,
`docs/getting-started/permissions.md`, `docs/getting-started/installation.md`,
`docs/configuration/README.md`.

**The problem:** `Config.adminAce = 'mi_fire.admin'` required a `server.cfg` grant nobody
had made. Technically correct and practically useless — a resource that does not work
until you read the docs has chosen the wrong default.

**Decisions:**

- **Two independent routes to admin access**, because they answer different questions. ACE
  answers "is this a server administrator"; job and grade answers "is this the fire chief".
  A server admin should not have to clock on as a firefighter to test a scene, and a chief
  should not need server admin to run a drill.
- **Principals are granted at boot.** `Config.permissions.principals` defaults to
  `group.admin` and `group.god`, and `lib.addAce` grants them `mi_fire.admin` on startup.
  Those groups already exist on any Qbox server — `qbx_core/server/commands.lua` gates its
  own admin commands on `group.admin` — so the commands now work with no cfg edit.
- `command.*` aces are deliberately skipped when granting principals. ox_lib owns those,
  and granting one would let a principal run a command this resource never registered.
- **Commands are registered unrestricted on purpose.** `lib.addCommand`'s `restricted` maps
  to an ACE and FiveM refuses before the handler runs, which would make job-grade access
  impossible — a grade is runtime state an ACE cannot express. So the gate moved into the
  service, which also means a refused player is told why instead of getting "unknown
  command". This also fixes a deviation from the plan: the previous code used raw
  `RegisterCommand`.
- **`/fire perms` is available to everyone.** The person who cannot run the commands is
  exactly who needs to see why. It reports every ACE tested, the job and grade actually
  held, the verdict, and the literal `add_ace` line to fix it. "Missing ACE permission" is
  a dead end; this is not.
- Refusals distinguish *no access* from *your rank cannot use this subcommand*, because
  those need different fixes.
- `jobCommands` defaults to everything except `wind`, which changes weather server-wide
  rather than affecting one incident.

**Bug found and fixed in `Util.merge`.** It deep-merged **arrays by index**, so overriding a
five-entry list with a one-entry list kept entries two through five. That surfaced as a
permissions test failure that looked like a permissions bug and was not. Arrays are now
replaced wholesale, which is what anyone writing a config expects. Nothing currently
shipping depended on the old behaviour — checked `fireclass.lua` and `bridge/dispatch` —
but it was a trap waiting for the first config containing a list.

**Verified:**

- `lua tools/run_tests.lua` — **315 passed, 0 failed** (was 273).
- 41 new permission assertions covering the boundaries that actually matter: the grade one
  below the threshold, an unlisted job, a high rank in the wrong job, on-duty and off-duty,
  each route working without the other, subcommand limiting, and that refusals name the
  right cause.
- Validation rejects a permissions block granting nothing, a non-numeric grade, and a
  `jobCommands` entry naming no real subcommand.
- All 32 Lua files parse.
- **Not** re-tested in game. The original report — `/fire` refused — has not been confirmed
  fixed on a running server.

**Open:** unchanged. The fire engine still has not been seen running; this session fixed the
gate in front of it, not anything behind it.

**Next:** the in-game test, now that the commands should actually be reachable.

---

## 2026-08-30 · session 009

**Scope:** `FIRE-007` — fire was invisible in game.

**Changed:** `config/fire_classes.lua`, `client/modules/fire/render.lua` (new),
`client/modules/fire/init.lua`, `server/modules/admin/init.lua`, `shared/validate.lua`,
`fxmanifest.lua`, `config/config.lua`, `tools/tests/boot_spec.lua`.

**The bug:** `/fire here` reported success and drew nothing. The server was correct
throughout — incidents started, nodes were created, sync went out. The particle name
`core / fire_wrecked_plane_cabin` was invented in session 006 and does not exist.

**Why it was invisible rather than broken:** `StartParticleFxLoopedAtCoord` with an effect
name that is not in the given dictionary returns a handle of `0` and prints nothing. No
error, no warning, no clue. The server logs said everything worked, because everything on
the server did.

**Decisions:**

- Particle dictionary and effect names are now taken from **verified working pairs**, read
  out of the reference resource's own `cl_utils.lua` rather than guessed. The mechanism was
  never wrong — the code path is identical to theirs — only the names were.
- **Layered effects.** One particle does not read as a fire; a flame layer plus a smoke
  plume does. Each layer carries its own scale multiplier and Z offset so smoke sits above
  the flame. Every class now has visuals matched to what it should look like: a Class B
  pool fire is wide and low with black smoke, Class D burns white, Class C arcs and
  crackles, and a gas fire is a jet with almost no smoke while it is fed.
- **A native script fire underneath, for light only.** Particles cast none, and the failure
  screenshot was at night — a fire that lights nothing looks wrong in a way no amount of
  particle tuning fixes. GTA owns the light and heat haze; mi_fire still owns whether the
  fire exists. Capped at 40 concurrent, since GTA limits script fires and particles must
  carry on regardless.
- **Boot validation now rejects an unverified particle name.** The name cannot be checked
  without the game running, so instead every name must be one already confirmed to work,
  listed in `VERIFIED_PTFX`. Adding a new one means confirming it in game first. That is
  friction, and it is the point: this class of bug is invisible at runtime and cheap to
  catch at boot.
- **`/fire render`** asks the caller's own client what it knows and what it is drawing.
  This existed nowhere and should have from the start: "I ran the command and nothing
  happened" was impossible to diagnose from the server, which had done its job correctly
  and said so. The diagnosis separates three unrelated bugs — the client never received the
  node, the dictionary failed to load, or the effect name is not in it.
- Rendering moved to its own `render.lua`. It is where the failure was and deserves to be
  readable without the sync and export code around it.

**Verified:**

- `lua tools/run_tests.lua` — **319 passed, 0 failed** (was 315).
- Three new validation cases, including one that feeds it the exact invented name from
  session 006 and asserts it is now rejected.
- All 33 Lua files parse.
- **Not** confirmed fixed in game. The names are taken from a working resource and the
  code path matches, but nothing has been seen burning yet.

**Open:**

- Everything from session 006 still stands: no exposure model, no generation, no dispatch.
- Scale ranges and layer offsets are first guesses and will need a look once a fire is
  actually visible.
- If a fire now renders but looks wrong rather than absent, that is tuning in
  `config/fire_classes.lua` rather than a bug.

**Next:** re-test. `/fire here`, then `/fire render` if it is still invisible — the
diagnosis will say which of the three failures it is.

---

## 2026-08-30 · session 010

**Scope:** `FIRE-003` — wind, following the first successful in-game test.

**Changed:** `server/modules/fire/spread.lua`, `tools/tests/fire_spec.lua`,
`config/config.lua` (debug back off).

**The engine works in game.** First full run-through, and every behaviour the design rests
on held up:

- `/fire here` starts and renders. `/fire agent water` knocks it down and extinguishes it.
- **`/fire start B` then `/fire agent water` spread the fire.** The agent matrix does what
  it claims, in the game, with a player watching. `/fire agent foam` then killed it.
- `/fire list` and `/fire stopall` reconcile correctly.

The `attempt to index a nil value (upvalue 'Render')` errors from the same session were a
stale client cache, not a load-order fault — `refresh` had not been run before `restart`.
Verified separately that `render.lua` loads clean and sets `MIFire.Render`.

**The one real finding: `/fire wind` appeared to do nothing.**

It was not broken. Measured in the harness, wildland spread was working the whole time —
median first spread at 16 s, reaching about 16 nodes in three minutes. But wind only
steered **direction** and slightly extended **reach**; it never touched **rate**. The only
visible effect was a change in node count from fewer placement collisions, which is close
to imperceptible while standing next to a fire.

The expectation behind the report was the correct one: a wind-driven fire spreads *faster*,
not merely sideways. So wind now shortens the interval between spread attempts and improves
each attempt, both scaled by the class's `windInfluence`.

Measured before and after, 3 seed nodes, averaged over 30 runs:

| Wind | Before: nodes @120s | After: nodes @120s | After: median first spread |
|---|---|---|---|
| 0.0 | ~10 | 10.2 | 16 s |
| 0.5 | ~22 | 22.4 | 12 s |
| 0.9 | ~27 | 29.7 | **5 s** |

A gale now takes a wildland fire to its node cap and starts it spreading in five seconds
instead of sixteen. Class A, which has `windInfluence = 0`, is unaffected — 6.2 nodes calm
against 6.0 in a gale — so a gale still does nothing to a sofa fire indoors.

**Verified:**

- `lua tools/run_tests.lua` — **321 passed, 0 failed** (was 319).
- Two new assertions, both averaged over 12 runs because one run of a probabilistic system
  proves nothing: a wildland fire in strong wind grows substantially faster than in still
  air, and a class with no wind influence does not.
- In game: the full command sequence above, by hand.

**Open:**

- Unchanged: no exposure model, no ambient generation, no dispatch, no smoke.
- Spread caps at 30 nodes for wildland. In a strong wind that cap is now reached in about
  two minutes, so it is the next thing likely to feel wrong — a running brush fire should
  probably keep going rather than stopping dead at a number.
- `Config.debug` was left on in a previous session and is now off again. It should not be
  committed on.

**Next:** `EXPO-001`. Fire is visible, spreads, and can be put out; it still cannot hurt
anyone.

---

## 2026-08-30 · session 011

**Scope:** `TURN-001`, `TURN-002`, `TURN-004`, `SCBA-001`…`SCBA-004`, `DOC-006`

**Changed:** `config/scba.lua` (new), `config/gear.lua`, `config/config.lua`,
`bridge/appearance/illenium.lua` (rewritten), `server/modules/turnout/init.lua` (new),
`server/modules/turnout/appearance.lua` (new), `server/core/state.lua`,
`install/migrations/0003_gear_appearance.sql` (new), `install/items.lua` (new),
`client/modules/turnout/init.lua` (new), `tools/tests/scba_spec.lua` (new),
`docs/guides/scba-and-air.md` (new).

**Decisions:**

- **Wearing a set is not breathing from it.** SCBA has two states: on the back with the
  valve shut, which uses no air and protects from nothing, and mask sealed, which is total
  smoke immunity and a running clock. One boolean separates them and it is the only thing
  the exposure model will ask about, via `State.hasAir`.
- **Turnout and SCBA are independent**, on different ped slots -- `torso2` for the coat,
  `t-shirt` for the harness. Partial states are legal and meaningful: SCBA without turnout
  means you breathe but burn; turnout without SCBA means you survive flame but not smoke.
  Both are real mistakes worth being able to make.
- **A helmet is a prop, not a component.** They go through different natives with different
  key names, and a helmet listed among components silently does nothing. The bridge now
  splits a `{ slot = drawable }` set into the two shapes illenium wants, and *warns* about
  an unknown slot rather than dropping it in silence. There is a test.
- Slot names follow illenium's own vocabulary (`hat`, `torso2`, `arms`, `t-shirt`) so a set
  written in our config reads the same as one written in theirs.
- **Air is on the item, not the player.** A bottle carried between rigs keeps its pressure,
  and racking it is what refills it -- so a firefighter cannot hoard full cylinders and
  never visit a station. Same pattern as `mi_diving`.
- Exertion drives consumption far more than time. Sprinting costs three times standing
  still, so a rated 30-minute bottle gives well under half that under work. That gap is the
  feature: air management is a skill, not a countdown.
- The valve toggle is a **keybind**, not an ox_target option. Opening your own mask is an
  action on yourself; the ox_target rule is about interacting with the world.

**Two changes made mid-session on the user's word:**

- They already have an SCBA item, so the integration is an **ox_inventory item export**
  (`server.export = 'mi_fire.useScba'`) rather than `registerUsableItem`. Repointing one
  string beats redefining an item. Verified the call signature against ox_inventory's
  `useExport` in `modules/items/shared.lua:1`, which invokes it as
  `export(nil, event, item, inventory, slot)` -- so the first argument seen is the event
  and `inventory.id` is the player.
- **Turnout markings are per-character.** Their gear carries name tapes and ranks, so the
  drawable is departmental and the texture is personal. That makes it *identity, not
  equipment*, and it became `mi_fire_gear_appearance` keyed on the character rather than
  item metadata. Item metadata would have been wrong twice over: gear issued from an
  apparatus rack has no item at all, and a coat handed to another firefighter would carry
  the previous owner's name across with it. Merged over the tier's base set at don time,
  so a character stores only what differs.

**Verified:**

- `lua tools/run_tests.lua` — **390 passed, 0 failed** (was 321).
- New SCBA suite asserts the state machine at its boundaries: a worn set with a shut valve
  protects from nothing, an open valve on an empty bottle protects from nothing, the valve
  will not open on an empty bottle, doffing turnout leaves SCBA on, and wearing the turnout
  *skin* through a clothing menu grants no resistance at all.
- Appearance slot resolution is tested directly, including that `hat` routes to props and
  an invented slot name is reported rather than dropped.
- All 37 Lua files parse.
- **Not** tested in game.

**Harness note:** `bridge/appearance/illenium.lua` is now loaded by the boot simulation.
It is a client file, but its slot resolution is arithmetic on tables and is exactly the
kind of logic worth testing -- a helmet routed to the wrong native fails silently. Files
that genuinely need natives at load time stay excluded.

**Open:**

- `EXPO-001` still not built, so none of this protects against anything yet. SCBA burns air
  and turnout records a tier, but nothing is hurting the player.
- `SCBA-005`, the PASS device, is configured but not implemented.
- `TURN-003`: gear does not yet survive a disconnect.
- Only `structural` has a real appearance. The other tiers are `nil` until their EUP
  drawables are known.
- The apparatus check is loose -- any emergency-class vehicle -- until `config/apparatus.lua`
  exists.

**Next:** `EXPO-001`. Everything built this session is protection against damage that does
not exist yet.

---

## 2026-08-30 · session 012

**Scope:** `SCBA-005` — the PASS device, including its audio.

**Changed:** `shared/pass.lua` (new), `server/modules/scba/pass.lua` (new),
`client/modules/scba/pass.lua` (new), `web/index.html` + `web/sounds.js` (new),
`web/sounds/pass.ogg` (supplied by the user), `config/scba.lua`,
`tools/tests/pass_spec.lua` (new), `docs/guides/scba-and-air.md`.

**Answering the question that started this:** there were no PASS sounds, and no audio in
the resource at all. There is now.

**Decisions:**

- **The phase machine is pure**, in `shared/pass.lua`. Same reasoning as the hydraulics,
  but more acute: verifying that a chirp starts at twenty-five seconds means standing
  perfectly still for twenty-five seconds, and checking that movement clears a pre-alarm
  but not a full alarm means doing it twice more. Nobody repeats that by hand, so it would
  have rotted. Twenty-six assertions now cover it.
- **Movement clears a pre-alarm but not a full alarm.** That asymmetry is the whole design.
  A firefighter working a nozzle from one spot sets off a chirp and wiggles it away; one
  who goes down and is dragged out is still alarming when they arrive, because the alarm is
  for the people looking rather than for the wearer.
- **Reset refuses on someone still down.** Otherwise a well-meaning partner silences the
  device on an unconscious firefighter, which is the exact opposite of what it is for.
- **Motion is detected server-side** from position deltas the server already has. Cheap,
  and a modified client cannot silence its own PASS -- a device that can be suppressed by
  its wearer is worse than none, because a crew would learn not to trust it. Downed
  overrides the position check, since a ragdolled ped slides and that must not read as
  movement.
- **Audio is a swappable backend**, chosen because the right answer needs assets that do
  not exist. NUI uses Web Audio with a `StereoPannerNode`, and Lua computes volume and pan
  from the camera -- bearing is most of what makes a sound feel located, and it is the cue
  actually used when hunting an alarm. `native` is a positioned GTA beep so a fresh install
  is audible. `auto` picks between them.
- What NUI **cannot** do is occlusion. A PASS through a wall sounds like one in the open,
  and muffling is a real search cue. An engine audio pack (`.awc` + compiled `.dat54.rel`)
  would fix that and is the eventual answer; when one exists it is a third backend and
  nothing else changes.
- **One sound file covers both phases.** The user asked whether to split the audio. With no
  dedicated pre-alarm file, the full-alarm sound is played in short repeating bursts whose
  gap shortens as it escalates, which reads convincingly as chirping. Splitting improves it
  and is optional, which is a better answer than requiring more assets.

**Bug caught before shipping:** `backend()` in auto mode required *both* audio files, so a
setup with only the full-alarm sound -- which is the setup we now ship and recommend --
would have fallen back to the native beep and looked like the NUI path was broken.

**Verified:**

- `lua tools/run_tests.lua` — **434 passed, 0 failed** (was 390).
- All 41 Lua files parse.
- **Not** tested in game. The audio path in particular is unproven: NUI `AudioContext` can
  start suspended, and whether it resumes without user interaction inside FiveM is the
  thing most likely to be wrong.

**Open:**

- `EXPO-001` still not built. A PASS now alarms correctly for a firefighter who goes down,
  but nothing in the game can put them down yet.
- Accountability board (who is inside, on what air) is not built; mayday currently notifies
  and blips.
- The audio has never been heard. If it is silent in game, check the F8 console for a
  `could not load` line from `sounds.js` before assuming the phase machine is at fault.

**Next:** `EXPO-001`, which is now overdue -- three sessions of protective equipment
against damage that does not exist.
