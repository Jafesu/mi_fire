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

---

## 2026-08-30 · session 013

**Scope:** `EXPO-001`, `EXPO-002`, `EXPO-003` — the exposure model. Overdue by three
sessions.

**Changed:** `shared/exposure.lua` (new), `server/modules/exposure/init.lua` (new),
`client/modules/exposure/init.lua` (new), `config/gear.lua`,
`tools/tests/exposure_spec.lua` (new), `docs/configuration/README.md`,
`docs/guides/scba-and-air.md`.

**Fire can now hurt people.** Until this, turnout gear was a costume, SCBA was a countdown,
and a PASS device alarmed for a firefighter nothing could put down.

**Decisions:**

- Three channels ticked separately, because they run at different rates: flame twice a
  second, heat and smoke once. Damage is decided server-side and applied by the client,
  since a player's ped is owned by their own client. The trust boundary is real and
  unavoidable in FiveM; what the server keeps is the decision, the gear tier, and the air.
- **Worn gear protects less.** `effectiveFireResist` scales with remaining integrity, so a
  burned coat is genuinely worse than a fresh one. Without that, integrity would be a
  number that ticked down and changed nothing until it crossed a threshold.
- Flame takes the *hottest* node you are standing in rather than summing, because standing
  where two fires overlap should not be twice as lethal as one fire twice the size. Heat
  sums across sources, because standing between two fires really is hotter. Smoke takes the
  worst source, so a row of small fires cannot produce impossible density.
- **Smoke density is derived from fire nodes** weighted by each class's `smokeVolume`,
  because `FIRE-008` does not exist. It is a number rather than a boolean specifically so a
  real smoke system replaces the source later without touching the exposure model.
- Health floors at 1 rather than 0. mi_fire injures; whatever medical resource the server
  runs decides what dying means.
- Burning stops on its own after a maximum, so a disconnect mid-burn does not leave someone
  permanently alight.

**Balance, measured rather than guessed.** The first pass was wrong in two places and the
figures showed it: a station uniform survived 25 seconds standing in a fully developed
fire, and smoke took 200 seconds to put someone down. Neither is frightening. After tuning
`baseDamagePerTick` 4 to 9, smoke `damagePerTick` 1 to 3, and softening the degradation
floor from 50% to 70% of rated resist:

| Gear | Before | After |
|---|---|---|
| Station uniform | 25.0s | **11.5s** |
| Wildland | 32.5s | 16.5s |
| Structural turnout | 55.5s | **34.5s** |
| Proximity | 83.0s | 57.5s |
| Smoke, no SCBA, indoors | 200s | **67s** |

The degradation floor had to move up as damage moved up. Steep degradation plus a damage
rate high enough to make fire frightening collapses the gap between turnout and a shirt,
and that gap is the entire reason to wear the gear.

**Verified:**

- `lua tools/run_tests.lua` — **493 passed, 0 failed** (was 434).
- ADR 0001 is now checked from both directions. `validate.lua` proves no tier is
  *configured* with immunity; the exposure tests prove the maths never *produces* it —
  including feeding it a `fireResist` of 5.0 and of −3.0 and confirming damage still lands.
- Three balance invariants are assertions, not intentions: a station uniform gives under
  twenty seconds, turnout gives over twenty, and turnout is at least 2.5× a shirt. A tuning
  change that breaks one fails the suite.
- All 44 Lua files parse.
- **Not** tested in game.

**Open:**

- Smoke has no visual. The damage and the screen effect are there, but there is no smoke to
  see — `FIRE-008`.
- Heat and smoke screen effects use stock GTA timecycle modifiers picked by name and have
  never been looked at. They may be wrong, ugly, or both.
- No accountability board: who is inside, on what air, at what heat.
- `mobility` is configured per tier and not applied anywhere. Heavy gear does not yet slow
  anyone down.

**Next:** in-game test of the whole loop, which is now worth doing — `/fire here`, walk in
without gear and die, then in turnout and survive, then watch a PASS alarm when it kills
you.

---

## 2026-08-30 · session 014

**Scope:** exposure balance, on the report that turnout gear lasted only about thirty
seconds.

**Changed:** `config/gear.lua`, `shared/exposure.lua`, `tools/tests/exposure_spec.lua`,
`docs/configuration/README.md`, `docs/guides/scba-and-air.md`.

**The report was right.** Thirty-five seconds standing in a fully developed fire is a dash
in and out, not an interior attack.

| Gear | Before | After | Gear now fails at |
|---|---|---|---|
| Station uniform | 11.5s | 12.5s | -- |
| Wildland brush | 16.5s | 30.0s | 21s |
| Structural turnout | 34.5s | **92.5s** | 60s |
| Proximity | 57.5s | 116.5s | 97s |

Changed `fireResist` to 0.62 / 0.93 / 0.95 for wildland, structural and proximity, raised
their integrity pools, raised `degradeRate` to match, softened the degradation floor from
70% to 88% of rated, and lowered `baseDamagePerTick` from 9 to 8.

**Why the degradation floor moved the other way this time.** Session 013 raised it from 50%
to 70% to stop damage collapsing the gear/no-gear gap. This time it went to 88%, for a
different reason: the real consequence of burning through gear is not that it protects
slightly less, it is that you become **ignitable**. That is a far sharper cliff than a
resistance number sliding, and applying both punished the same mistake twice while eating
the working window turnout exists to provide.

**A bug caught by measuring rather than by testing.** The first candidate set raised
resistance without raising degradation, and produced 96-second survival with the gear
*never* burning through -- so `canIgnite` never returned true and catching fire became
unreachable dead code. Every survival number looked healthy. The mechanic was simply never
entering.

That is now an assertion: for every tier with an integrity pool, gear must become ignitable
before death, with at least five seconds between. Proximity gear failed it on the first fix
with a three-second window and needed its `degradeRate` raised to 2.8.

**Verified:**

- `lua tools/run_tests.lua` -- **499 passed, 0 failed** (was 493).
- Four balance invariants now assert rather than hope: a station uniform gives under twenty
  seconds, turnout gives over sixty, nothing survives four minutes, and turnout is at least
  four times a shirt.
- Survival *and* failure figures published in both the configuration reference and the
  player guide, so the numbers are arguable without reading Lua.

**Open:** unchanged from session 013. Still no smoke visual, no accountability board, and
`mobility` is configured but applied nowhere.

**Next:** in-game test of the full loop.

---

## 2026-08-30 · session 015

**Scope:** medical integration, and a correction to every survival figure published so far.

**Changed:** `bridge/medical/init.lua` (new), `client/modules/exposure/init.lua`,
`server/modules/exposure/init.lua`, `server/modules/scba/pass.lua`, `shared/exposure.lua`,
`config/gear.lua`, `tools/tests/exposure_spec.lua`, `fxmanifest.lua`,
`docs/internal/INTEGRATIONS.md`, `docs/configuration/README.md`,
`docs/guides/scba-and-air.md`.

**Two real bugs, both found by a pre-flight check rather than by testing.**

**One: every survival figure was double the truth.** A GTA player ped reads 200 health at
full and is **dead at 100**, so the usable pool is 100 points and not 200.
`Exposure.survivalSeconds` modelled 200. The figures reported in sessions 013 and 014 --
including the 34.5 seconds that prompted the complaint about turnout, and the 92.5 seconds
offered as its fix -- were all twice the real number. Actual turnout survival at the time
of the complaint was about **17 seconds**, not 35.

Corrected, then retuned against the real pool. `baseDamagePerTick` 8 to 6:

| Gear | Gear fails at | You go down |
|---|---|---|
| Station uniform | immediately | ~9s |
| Wildland brush | ~13s | ~20s |
| Structural turnout | ~46s | ~64s |
| Proximity | ~60s | ~76s |

**Two: `SetEntityHealth` does not raise a damage event.** qbx_medical decides last stand
from `CEventNetworkEntityDamage` (`client/dead.lua:118`), so health set directly is
invisible to it -- a firefighter would have slid to zero and died outright with no last
stand, no bleeding and no injury record. `ApplyDamageToPed` raises the event properly, and
is what qbx_medical uses on itself for bleed damage (`client/wounding.lua:61`).

**Decisions:**

- Added `bridge/medical/init.lua`, targeting **qbx_medical** as instructed. It answers two
  questions: is this player down, and how do I hurt them in a way the medical resource will
  notice. Server-side death state is read from `metadata.isdead` / `metadata.inlaststand`
  rather than asked of the client, because the client being asked may be the unconscious
  one.
- qbx_medical is in `[disabled]` and `osp_ambulance` is running, so the bridge prefers
  qbx_medical, falls back to osp_ambulance, then to raw health. The fallback is the path
  that runs today and it had to work.
- Exposure stops damaging anyone already down. Otherwise a downed firefighter could not be
  rescued, because the fire would keep killing them faster than a crew could reach them.
- PASS now asks the medical bridge whether someone is down instead of guessing from health.
  That makes **last stand** count, which is exactly who the device exists to find, and a raw
  health check would miss them the moment a medic stabilised them above the threshold.
- Sub-point damage is banked rather than floored away. `ApplyDamageToPed` takes whole
  numbers, and smoke at low density is well under one point per tick -- flooring each call
  would have rounded it to nothing forever and made smoke harmless.

**The failure-window assertion earned itself twice.** With the corrected pool it caught that
wildland and proximity gear never burned through before death at all, and structural only
had a nine-second window. All three degradation rates were raised.

**Verified:**

- `lua tools/run_tests.lua` — **502 passed, 0 failed** (was 499).
- All 45 Lua files parse; load order and every file-scope global capture checked against
  the manifest.
- Published figures in the configuration reference and the player guide corrected to the
  real numbers.
- **Still not tested in game.**

**Open:** no smoke visual, no accountability board, `mobility` applied nowhere. Screen
effects still unviewed.

**Next:** in-game test.

---

## 2026-08-30 · session 016

**Scope:** `FIRE-008` — smoke, rebuilt as something readable rather than a by-product.

**Changed:** `shared/smoke.lua`, `config/smoke.lua`, `server/modules/smoke/init.lua`,
`client/modules/smoke/init.lua` (all new), `server/modules/admin/init.lua`,
`tools/tests/smoke_spec.lua` (new), manifest and boot spec.

**The technical enabler**, checked before anything was promised: `SetParticleFxLoopedColour`,
`SetParticleFxLoopedAlpha` and `SetParticleFxLoopedEvolution` are all in production use on
this server (`[jim]/jim-mechanic`, `[qbx]/qbx_core`). Colour, opacity and behaviour are
controllable per particle instance, which is what makes any of this possible.

**Decisions:**

- Four attributes, mapped one-to-one onto rendering: volume to scale, density to alpha,
  colour to tint, velocity to which effect and how often it is re-emitted.
- **Velocity is the important one.** Turbulent smoke is heat-pushed and means the
  compartment has stopped absorbing heat; laminar is volume-pushed and means it still is.
  Rendered as genuinely different effects rather than the same one faster, because boiling
  smoke and a lazy column look nothing alike.
- **Colour reports stage and travel together.** Brown means the fire is into structural
  timber. Black at one opening with white at another is one fire, and the black is nearer
  the seat. Two plume layers are drawn per fire -- one at the seat and one higher with
  travel applied -- so that difference is visible from outside without needing building
  geometry we do not have.
- **Flashover builds, backdraft waits.** Flashover has a 25-second warning window, so
  reading the smoke buys real time. Backdraft has no timer at all: it sits indefinitely and
  is *triggered* by someone opening the compartment. That asymmetry is the character of the
  two, and the reason one is announced and the other is not.
- Backdraft risk is evaluated **before** the ventilation change is applied, since the risk
  is a property of the compartment as it was when someone opened it.
- Vertical ventilation is the safe answer and takes three times as long as forcing a door,
  so the correct choice costs something.
- Flashover's clock winds back rather than resetting when conditions improve, so a crew
  that cools a room sees the benefit.
- `sizeup` and `vent` are gated on being a **firefighter**, not an admin. Reading smoke is
  the job. The observation is given to everyone and the interpretation is gated on rank, so
  a probationer is told what they can see and an officer is told what it means.

**Verified:**

- `lua tools/run_tests.lua` — **557 passed, 0 failed** (was 502).
- Fifty smoke assertions, none of them snapshots. Each is something true about smoke: an
  outdoor fire never flashes over, a ventilated fire cannot backdraft, a gas jet never
  reads as pyrolysing, a starved fire has *lower* velocity than a flashover fire, and an
  early open fire warns of nothing — because warnings that fire constantly stop being
  listened to.
- All 49 Lua files parse.
- **Not** tested in game. The plume rendering, the two events, and the tint values are all
  unproven.

**Open:**

- Smoke is rendered per incident at the worst node rather than per node. Simpler and reads
  well, but a large scene shows one plume rather than several.
- No neutral plane, no smoke pathing through interiors, no volumetric fill. All three need
  interior geometry that is not available.
- Ventilation actions are commands, not `ox_target` interactions on actual doors and
  windows. That needs the placement work in Phase 2.

**Next:** in-game test.

---

## 2026-08-30 · session 017

**Scope:** ADR 0004 — protection follows the clothing. Reverses part of ADR 0001 on the
user's correction.

**Changed:** `shared/gearmatch.lua` (new), `config/gear.lua`, `config/config.lua`,
`server/modules/turnout/init.lua`, `client/modules/turnout/init.lua`,
`server/modules/exposure/init.lua`, `tools/tests/gearmatch_spec.lua` (new),
`tools/tests/scba_spec.lua`, `docs/internal/adr/0004-*` (new), `adr/0001-*`,
`docs/internal/TESTING.md`, `docs/getting-started/permissions.md`.

**ADR 0001 was solving the wrong problem.** It said protection is read from server state and
never from clothing, so donning at an apparatus was the only route. The reasoning was that
otherwise anyone with a clothing menu could grant themselves fire resistance.

The cost of that was severe and the exploit was trivial. Firefighters get dressed at station
lockers, through outfit menus, from job clock-ins — and every one of those produced a
firefighter in full turnout taking full fire damage. That does not read as a design
decision; it reads as the resource being broken. Meanwhile the thing being prevented was a
civilian surviving a few seconds longer in a fire.

**Then the same argument taken further, also on the user's call:** gear is not job-gated at
all. A coat is a coat. If a civilian gets hold of a set it protects them, and a bottle of air
works for whoever is breathing it. `Config.gearRequiresJob` restores the restriction for
anyone who disagrees.

The line moved somewhere more defensible: **taking equipment off an apparatus or a station
rack is department business** and stays job-gated. Obtaining the gear is the gate; using it
is not.

**Decisions:**

- Recognition matches on **drawable and never texture**. Texture carries the per-character
  name tape and rank, so matching on it would mean the officers are the ones who lose
  protection.
- **A signature slot must match** — the coat. `pants = 11` means "no separate trousers" and
  half the outfits on a server use it, so matching on that alone would identify most of the
  population as firefighters.
- Coverage scales protection between a floor and full, so wearing the coat without the
  helmet protects less than the full set. A missing hood becomes a real decision.
- The client reports what it is wearing, because `GetPedDrawableVariation` is client-only.
  Small trust surface: the worst a forged report achieves is a player who is harder to set
  on fire.
- **Integrity is keyed to character and tier, not to the session.** Changing clothes does
  not repair a burned coat, and putting the same gear back on resumes where it left off.
  The gear is worn out, not the visit.

**What ADR 0001 keeps:** everything about immunity. No tier may reach `fireResist` 1.0,
gear degrades while it protects, and staying in long enough still sets you alight. Only the
*source of the tier* changed, and the test asserting the bound now sits alongside the one
asserting the new behaviour.

**Verified:**

- `lua tools/run_tests.lua` — **592 passed, 0 failed** (was 557).
- The `scba_spec` block that asserted the old rule was rewritten rather than deleted, so the
  suite now states the new behaviour and the surviving half of the old one side by side.
- `TESTING.md` section 2 inverted. That check previously read "you should take full damage"
  and now reads the opposite, with the civilian and partial-coverage cases added.
- All 51 Lua files parse.
- **Not** tested in game.

**Open:** unchanged, minus the job-gating note.

**Next:** in-game test.

---

## 2026-08-30 · session 018

**Scope:** `GEAR-004` gear condition, repair, and the three integrity models

**Changed:** `shared/integrity.lua` (new), `config/gear.lua`,
`server/modules/turnout/init.lua`, `server/modules/exposure/init.lua`,
`client/modules/turnout/init.lua`, `tools/tests/integrity_spec.lua` (new),
`fxmanifest.lua`, `tools/tests/boot_spec.lua`, `docs/configuration/README.md`,
`docs/guides/scba-and-air.md`, `docs/internal/TESTING.md`.

**The gap this closes.** Session 017 made gear integrity persist across sessions and keyed
it to the character rather than the visit — a coat you burned stayed burned. What it did not
build was any way to *un*-burn it. Integrity fell, protection fell with it, and there was no
repair path, no replacement path, and nothing that put a set back in service. Persistence
without a repair path is not realism, it is a one-way ratchet: play long enough and every
firefighter on the server is in condemned gear with no recourse. That was a dead end and it
shipped as one.

**Decisions:**

- **Three models, chosen in config, because both positions are defensible.** A server that
  wants gear to be a logistics system and a server that wants it to be a damage modifier are
  both asking for something reasonable, and the argument between them is not one this
  resource should settle:

  | Mode | Behaviour |
  |---|---|
  | `regenerate` | Recovers on its own once the wearer is clear of the fire |
  | `persist` | Stays damaged until repaired or replaced (default) |
  | `session` | Lasts the shift, resets when gear next goes on |

  Nothing outside `shared/integrity.lua` knows which is active. The exposure model, the
  target options, and the protection multiplier are all identical across the three.

- **On `regenerate`, the delay is the mechanic, not the rate.** `delaySeconds` before
  recovery starts is what makes rotating out mean something; without it, backing out of a
  doorway for two seconds would reset a coat and the whole model would be decorative. The
  rate can be set arbitrarily high and the model stays coherent as long as the delay holds.

- **"Clear of the fire" means clear of the fire.** Recovery reads
  `ExposureServer.secondsSinceFlame`, not "not currently taking damage" — those differ, and
  the cheap version would let someone recover while standing in a node that happened not to
  have ticked yet.

- **Repaired gear does not come back as new.** `ceilingLossPerRepair` takes a slice off the
  ceiling each service, so a set that has been through several fires is eventually replaced
  rather than patched forever. Without it, one set of turnout lasts the life of the server
  and the replacement path is dead code. The ceiling has a floor so gear never repairs to
  nothing, and the loss can be set to `0.0` by anyone who wants indefinite patching.

- **Condemned gear cannot be repaired.** Below `condemnedBelow` the only option is a fresh
  set. Past a point real turnout is taken out of service rather than serviced, and modelling
  that is what gives replacement a purpose distinct from repair.

- **Replacing is faster than repairing, and that is the trade.** A fresh set is quick but it
  is department property and stays job-gated; servicing the set you have is slow but
  available to anyone, consistent with session 017's line — obtaining gear is the gate,
  using it is not.

- **Repair time scales with damage.** A scorched coat is quick and a nearly-condemned one is
  a job, so the progress bar carries information rather than being a fixed toll.

- **Racks hand out, stations service.** `repairAtApparatus` defaults off: an engine can give
  you a fresh set at 3am but it is not a gear room. Both are config, so a server that does
  not run a station can turn servicing on at the truck.

**Verified:**

- `lua tools/run_tests.lua` — **626 passed, 0 failed** (was 596).
- `integrity_spec` asserts each model on its own terms: `regenerate` does not recover inside
  the delay and does past it; `persist` never recovers however long you wait; condemned gear
  refuses repair and says to replace; repair restores less each time but never to nothing;
  and the shipped config is coherent — the mode exists, the threshold is a fraction, and
  replacing is faster than repairing.
- All 52 Lua files parse.
- **Not** tested in game. Sections 2–7 of `TESTING.md` remain unrun, now including the
  repair and mode-switch checks added this session.

**Open:**

- `TURN-003` — gear state still does not survive a disconnect while worn.
- Only the `structural` tier has an authored appearance.
- No accountability board, so a condemned set is not visible to a company officer.

**Next:** in-game test — gear, SCBA, exposure, PASS, smoke, and now repair.

---

## 2026-08-30 · session 019

**Scope:** first real in-game test of gear, SCBA, exposure, PASS and smoke, and the seven
defects it found.

**Changed:** `shared/gearmatch.lua`, `shared/smoke.lua`, `config/{gear,scba,smoke,fire_classes}.lua`,
`server/modules/{turnout,exposure,scba/pass}/init.lua`, `client/modules/{exposure,turnout}/init.lua`,
`client/modules/hud.lua` (new), `web/{hud.js,index.html}` (new), `client/modules/turnout/init.lua`
diagnostics, `tools/tests/{gearmatch,exposure}_spec.lua`, and the docs.

**This is the first entry written against evidence rather than reasoning.** Six of the seven
were invisible from the code and every one of them was a case of something quietly not
happening. That is the pattern worth remembering.

**Decisions:**

- **SCBA never got the ADR 0004 treatment the coat did.** Turnout was taught to follow the
  clothing; SCBA was left requiring the rig. A firefighter wearing a visible harness was told
  "you are not wearing a set". `GearMatch.matchScba` fixes it on the same rule. Recognising
  the *masked* drawable does not open the valve -- the server owns the bottle, and air should
  not drain because someone picked a skin.

- **Air is now banked per character.** Recognition from clothing needs somewhere to resume
  from, or re-equipping the skin would be a free refill and air management would be optional.
  Same idea as turnout integrity: the equipment is worn out, not the visit. A set with no item
  behind it comes back full after a restart, which is stated rather than hidden.

- **A full bottle is 10 minutes, not 30** (user's call). A real 30-minute bottle gives 15-20
  under work and that gap is worth modelling -- but a GTA fire is over in minutes, so 30
  minutes of game air meant the bottle was never the constraint it is on a real fireground.

- **`StartEntityFire` was overriding the entire gear model.** It looks exactly right and
  brings GTA's own ped fire damage with it: fast, unconfigurable, independent of every number
  in `config/gear.lua`. It killed a firefighter from 37 health in about two seconds against a
  four second roll, so stop-drop-roll was unperformable by anyone. Our own model had given
  them eighteen seconds. Flames are now a particle we own -- and there is a new invariant in
  BUILD.md: **the resource owns its damage; no native applies it for us.**

  The test that should have caught this measured the window between the gear failing and
  death *without* the burn damage that starts at ignition. It now simulates being alight,
  and asserts the roll is completable both in and out of the flame.

- **A PASS runs on its own battery.** `armed` was `worn and valve open`, so an empty bottle
  silently disarmed the device at the exact moment its wearer was most likely to need it --
  which is why it did not alarm during last stand: the bottle had usually run out by the time
  they went down. It now latches on at first valve-open and stays armed until the set comes
  off. It alarming with the valve shut is correct, not a glitch.

- **Smoke colour had no input from the fuel.** Stage alone drove it, so a flammable-liquid
  fire smoked white while it was still small. Backwards -- sooting is a property of the fuel,
  not the temperature, which is why a diesel pool is black from the first second. Each class
  now carries `sootiness`, biasing colour toward carbon and thickening density independent of
  stage. Class B 0.85, gas and D 0.05.

- **The repair options could not appear.** The exposure module degrades integrity server-side
  and never pushed the new value, so the client believed the coat was full forever and both
  repair and replace stayed hidden however hard it was worked. Pushed now, throttled to 2%
  steps.

- **Screen effects are off, all of them** (user's call). Heat escalated into
  `DrugsMichaelAliensFightIn` -- the drug-trip overlay -- which reads as being poisoned rather
  than cooked. But the deeper problem was that none of it said *which* of the three channels
  was hurting you, which is the only thing that changes what you do. A distorted screen was
  indistinguishable from the resource malfunctioning, and the user reported it as exactly
  that. The information moved to a HUD where heat, air and gear condition are three separate
  readable numbers, and the screen is left alone. The machinery survives behind
  `visuals`, every flag `false`.

- **`/fire gear`** was added before any of this, because "no option on the truck" is five
  booleans deep and none of them log.

**Verified:**

- `lua tools/run_tests.lua` — **642 passed, 0 failed** (was 596 at session start).
- The burn-window test prints its measurements, so the numbers are in the output rather than
  implied: structural gets 78s clear of the flame for a 3s roll.
- A scratch probe confirmed the model matches what was observed in game -- ignition at 45.5s
  with 37.2 health, death at 63.8s -- which is what established that the tuning was fine and
  the native was the problem.
- All 53 Lua files parse; `web/hud.js` passes `node --check`.
- Sections 1, and most of 3, 5, 6 and 7 of `TESTING.md` **passed in game**. That is the first
  real confirmation the fire engine, suppression, ventilation, backdraft, flashover and PASS
  audio all work.
- **Not** re-tested in game since these fixes.

**Open:**

- `TURN-003` — gear state still does not survive a disconnect while worn.
- Ambient generation and dispatch remain unproven; nothing in this round touched them.
- The HUD lives in a plain NUI page. Phase 4's React app becomes the `ui_page`, at which
  point this becomes a component in it.
- A second player has still not heard a PASS at range, and nobody has been put out by a
  partner.

**Next:** re-run `TESTING.md` sections 2-6 against these fixes.

---

## 2026-08-30 · session 020

**Scope:** the round-two test, and the defect that had been overruling the entire exposure
model since Phase 1.

**Changed:** `client/modules/fire/render.lua`, `config/fire_classes.lua`, `shared/pass.lua`,
`config/scba.lua`, `server/modules/admin/init.lua`, `server/modules/exposure/init.lua`,
`client/modules/turnout/init.lua`, `tools/tests/{fire,pass}_spec.lua`, docs.

**The defect.** `render.lua` called `StartScriptFire` under every node, described in its own
comment as "Light. Not the fire itself" and in config as "decoration". It is neither. A
script fire is a real engine fire that ignites peds within a second or two of contact and
burns them down on GTA's schedule, which knows nothing about `fireResist`, integrity,
coverage, or any other number this resource computes.

Full structural turnout gave **seven seconds** instead of sixty-four, and ignition took
**two** instead of forty-six. Every survival figure in `docs/` was being computed correctly
and then discarded by the engine.

**What made it hard to see, and worth writing down:** the three symptoms looked mutually
contradictory. Igniting in two seconds requires integrity below 20%, but the HUD showed the
coat full and serviceable -- and *both readings were correct*. Our model really had only
taken 29 of 240 integrity in those seven seconds; it simply was not the thing doing the
killing. Two correct readings that cannot both be true is the signature of a third actor,
and the reflex to reach for the tuning knobs is exactly wrong.

The arithmetic was never the problem. 657 tests passed throughout, because every one of them
was testing a model that the game was ignoring.

**This is the second instance of the same fault.** `StartEntityFire` was removed from the
burning-player path last session for identical reasons. Fixing one and leaving the other is
why the invariant went into BUILD.md, and it is why it is now a test that walks every class
rather than a sentence in a document.

**Decisions:**

- **Light is drawn, not spawned.** `DrawLightWithRange` per frame -- flickering, scaled by
  intensity, distance-culled, idle when nothing burns. That was the only thing the script
  fire was genuinely wanted for, and removing it without a replacement would have made every
  night fire a flat orange smudge.

- **`/fire gear` returns both halves in one block.** The server's view went to chat while the
  client's went to F8, so the useful half was lost -- and the client half alone was
  self-consistent and could never have found this. It now carries the resolved tier,
  integrity against capacity, whether the wearer is currently ignitable, and what the
  exposure model samples where they stand, broken down per channel in hp/s.

- **Ignition logs the tier and integrity it fired at**, and warns outright above half
  integrity. That combination is a contradiction rather than a tuning problem and should
  announce itself rather than present as gear that does not work.

- **PASS runs shortened timings when the wearer is down** -- 11 seconds to full alarm rather
  than 38. A real PASS cannot tell you are down and takes its full thirty-odd seconds either
  way; accurate, and useless, since that is most of a bleed-out timer spent silent. The
  realistic values are one config line away and there is a test asserting both.

**Verified:**

- `lua tools/run_tests.lua` — **657 passed, 0 failed** (was 642).
- **Confirmed in game by the user:** full turnout now lasts about a minute and ignites
  around forty-six seconds, matching the model.
- All 53 Lua files parse.

**Open:**

- Whether fires still read well at night now the script fire is gone. The drawn light is
  untested by eye.
- The rest of round two: repair modes, the clothing-menu SCBA path, and everything needing
  a second player.

**Next:** the remainder of `TESTING.md`, starting with the repair modes -- none of which has
ever executed, since both options were unreachable until two sessions ago.

---

## 2026-08-30 · session 021

**Scope:** the roll made real, and burn marks (`SCORCH-001`).

**Changed:** `shared/scorch.lua`, `config/scorch.lua`, `server/modules/scorch/init.lua`,
`client/modules/scorch/init.lua` (all new), `client/modules/exposure/init.lua`,
`server/modules/exposure/init.lua`, `server/modules/fire/init.lua`, `config/gear.lua`,
`server/modules/admin/init.lua`, `tools/tests/{scorch,exposure}_spec.lua`, manifest, docs.

**"Just barely" is a bug report.** The roll completed, so it would have been easy to call it
done. But an action that barely beats doing nothing is a delay, not a mechanic -- the player
learns that the correct response did not really matter. Rolling now cuts flame, burn and gear
degradation to 40% while it runs, which is defensible on its own terms: prone is below the
fire and the ground is what smothers a burning coat. Rolling without backing out of the flame
first went from marginal to about 36 seconds against a 3 second roll, and the margin is
asserted rather than left to feel.

It is also an actual roll now -- drop via a short ragdoll, a ground animation with the ped
turning over underneath it, then up. `combat@damage@writhe` is what qbx_medical uses for last
stand, so it is verified rather than chosen from a list.

**Burn marks, and an honest gap.** Every visual constant in this resource is pinned to
something already running: the particle pairs came out of a working fire resource, the roll
animation out of qbx_medical. There is no `AddDecal` call anywhere on this machine, so the
decal type is the first visual constant that **could not** be verified that way -- and
`AddDecal` returns 0 for a bad type and prints nothing, which is precisely the silent failure
that cost a whole session to an invented particle name.

Rather than guess and hope, `/fire decals` lays every candidate out in a numbered row in
front of the player, reports which the game accepted, and the value gets authored by looking
at it. Same principle as the offset finder. The client also warns once, loudly, naming the
config key, if a decal comes back 0 in normal use.

**Decisions:**

- **Both cleanup models, together**, per the user's call. Marks age out after three hours so
  an unattended server stays bounded, and a crew can wash a scene down sooner. Neither alone
  is right: a timeout only means scenes tidy themselves and overhaul has no product, while
  cleanup only means a server nobody polices accumulates marks forever.
  `lifetimeMinutes = 0` gives permanent marks, and those deliberately stop fading -- a mark
  that must be cleaned should stay legible.

- **Marks merge rather than stack.** Anything within 60% of an existing mark's radius grows
  it instead of adding another. A fire that spread through six nodes in a room should leave a
  scorched room, not six circles fighting over the same square metre.

- **Size follows what happened**, weighted 70% duration and 30% peak intensity. A brief flare
  at full intensity is still brief. Without the duration term every scene reads identically
  and the marks stop carrying information, which is most of the reason to have them.

- **Marks are made when a node dies, not while it burns.** A decal under an active fire is
  invisible under the flames and would have to be resized every tick to follow it.

- **`/fire stopall` does not clear marks.** An admin stopping a test fire should not scatter
  scorching across the map; `/fire scorch clear` is separate and explicit.

**Verified:**

- `lua tools/run_tests.lua` — **692 passed, 0 failed** (was 663).
- All 56 Lua files parse.
- **Not** tested in game. The decal type in particular is unproven by construction -- see
  `TESTING.md` section 9, which is deliberately ordered to run `/fire decals` first.

**Open:**

- The decal type. Nothing else in this session is uncertain; this is.
- Whether the ragdoll-then-animate transition reads cleanly or looks like a stutter, and
  whether 9 degrees per 20ms is the right spin rate for the roll.
- Marks are not persisted to the database, so a server restart loses them. Given a three hour
  lifetime that is defensible, but a station that burned last night having no trace of it is
  a reasonable thing to want.

**Next:** in-game round three, starting with `/fire decals`.

---

## 2026-08-31 · session 022

**Scope:** `HOSE-001`…`HOSE-004`, the rope, and Phase 2's zone rework.

**Changed:** `config/{hose,apparatus}.lua`, `shared/{hose,apparatus}.lua`,
`server/modules/{hose,apparatus,admin}/init.lua`, `client/modules/{hose,apparatus,placement,offsetfinder}/init.lua`,
`tools/tests/{hose,apparatus,conventions}_spec.lua`.

**Hoses work.** A crosslay pulls off the rig, the rope draws, it connects, it charges from the
pump panel, and water goes on the fire through the same agent matrix everything else uses.
Crew slots, flow ceilings and the tank clock are all live.

**Ports became two shapes**, on the user's call. Compartments -- gear, tools, hose bed, bottle
rack, ladder rack, panel -- are areas whose corners get walked with `/fireoffset`, tested with
a crossing count so a footprint can be any quadrilateral. Fittings -- discharges, intakes,
deck gun -- stay tight points, because picking the right piece of brass *is* the interaction.
A centre plus a size was the wrong description for either: it guesses at a shape nobody
measured.

**The rope cost four rounds and a fire engine, and it should not have.**

Every other visual constant in this resource came from reading something already running: the
particle pairs out of a working fire resource, the roll animation out of qbx_medical, the decal
sweep after a scan proved decals dead here. The rope is the one place I worked from the native
names instead, and it produced, in order: nothing drawn, a fire engine thrown across the map
and deleted, a flickering line, and a taut cable that stretched past its own length.

`AttachEntitiesToRope` takes world coordinates and was handed vehicle-local offsets and a
literal 0,0,0 -- so the rope became a constraint between the rig and the centre of the map.
`AttachRopeToEntity` and `PinRopeVertex` both wanted vertex 0, so they fought every frame.
Without `ActivatePhysics` a rope draws as a straight line. And attaching *either* end rigidly
removes the freedom the sag comes from.

SmartHose is on this machine and had the answer the whole time: pin both ends every frame,
attach nothing, pin three vertices along the outlet axis so the hose leaves the coupling
straight. Reading it first would have cost ten minutes.

**Decisions:**

- **The truck is never attached to the rope.** Not "attached correctly" -- not attached. Pinning
  applies force to nothing, so the failure that destroyed a vehicle is unavailable rather than
  fixed.

- **No nozzle prop.** `prop_fire_hosereel_l1` is the reel, and in hand it read as a firefighter
  carrying a large flat coil. There is no vanilla prop that looks like a nozzle, and nothing in
  the hand beats the wrong thing in it.

- **`/fire hose drop|clear`.** The first test stranded a player holding a prop with nothing in
  the world to target. A system that can strand someone needs an exit that is not a restart,
  and `clear` deliberately does not ask the server first -- the case it exists for is the one
  where the two disagree.

- **Three conventions became tests rather than notes**: no client file calls `lib.addCommand`,
  no manifest block declares a file twice, and shared client helpers load before their
  consumers. All three had already been broken once.

**Verified:**

- `lua tools/run_tests.lua` — **901 passed, 0 failed** (was 830).
- Confirmed in game: crosslay pulls, rope draws off the authored rear discharge, connect works.

**Open:**

- `HOSE-010`, parked: the hose follows the firefighter rather than lying where it was walked.
  The note says why more slack will not fix it and what will.
- `SCORCH-002`, parked: burn marks are on the marker fallback.
- Nothing in Phase 3 has been tested with two players, so crew slots and backup positions are
  unproven.

**Next:** the rest of Phase 3 -- appliances and the gated wye -- or Phase 4, which now has its
panel photographs.

---

## 2026-08-31 — a nozzle of our own

**Scope:** `ASSET-001`. Build a nozzle from a CAD model instead of borrowing one.

**Changed:**

- `tools/assets/nozzle/build_nozzle.py` — CAD STL to game-ready mesh, headless and repeatable.
- `tools/assets/nozzle/export_ydr.py` — Sollumz shader material, drawable, `.ydr`.
- `tools/assets/nozzle/README.md` — the source, the run, and the three things that were hard.
- `config/hose.lua` — the nozzle is `WEAPON_FIREEXTINGUISHER` until the new one is wired.

**Decisions:**

- **The two halves are separate scripts.** The build is pure Blender and always works; the
  export needs Sollumz. Split so a Sollumz problem never costs the geometry work. They also
  take different flags, which is not cosmetic — see below.

- **`--factory-startup` on the build, never on the export.** It does not merely disable add-ons,
  it discards the extension *repository* list, so Sollumz cannot be resolved at all:
  `extension repository "repo_sollumz_org" doesn't exist`.

- **8,000 triangles, from 183,404.** Keeping 4.4%. GTA handguns sit near 2-4k and rifles near
  6-10k, so this is the generous end of normal for something held at arm's length. The
  triangles were not where anyone would guess: a 23 mm ring carried 28,904 of them and the bale
  handle carried 47,116. Collapse decimation, not planar — planar leaves n-gons and does nothing
  for the cylinders, which is where the budget actually goes.

- **Ambient occlusion baked to a diffuse map.** An STL has no UVs, no materials and no texture,
  and a script will not hand-paint one. Contact shading in the flutes, under the bale handle and
  inside the teeth is most of what makes metal read as solid, and it costs one bake.

- **Orientation was settled by looking, not by reasoning.** Rendered the model with a red cube at
  +Y and a blue cube at +Z. Two attempts to infer the axes from part centroids gave the wrong
  answer, because the down-barrel view shows the *far* end filling the silhouette — the end that
  looks like the tip is the end that is not. Final mapping `(x, y, z) -> (z, y, -x)` at 0.001,
  written as one matrix because the chained-rotation form was wrong twice and a matrix can be
  checked against a bounding box by eye.

**Verified:**

- Both scripts run headless end to end on Blender 5.2.1 LTS with Sollumz 2.9.0.
- `183,404 -> 8,000` triangles; final bounds `(-0.061, -0.150, -0.064) .. (0.061, 0.147, 0.150)`
  metres, which is a 296 mm nozzle with the tip forward and the handle up.
- `mi_nozzle.ydr`, 163,065 bytes, magic `RSC7`, resource version 165 — a genuine RAGE drawable
  container rather than an empty file reported as success.
- `lua tools/run_tests.lua` — **1014 passed, 0 failed**.
- **Not** verified in game. The `.ydr` has not been loaded by FiveM, and until the metas exist
  it cannot be.

**Open:**

- The texture does not reach the client yet: it needs embedding in the drawable or a `.ytd`.
- `weapons.meta` and `weaponarchetypes.meta` are unwritten. The archetype is genuinely required
  here because this is a new model.
- `HOSE-010`, `HOSE-011`, `SCORCH-002` all unchanged.

**Next:** the texture, then the two metas, then one line in `config/hose.lua`.

---

## 2026-08-31 (later) — the nozzle is ours, and the extinguisher is gone

**Scope:** `ASSET-001`, finished on disk. Texture, metas, streaming, wiring.

**Changed:**

- `stream/w_mi_nozzle.ydr` — the nozzle, texture embedded.
- `data/weapons.meta`, `data/weaponarchetypes.meta` — `WEAPON_MINOZZLE` and its archetype.
- `fxmanifest.lua` — both metas declared with `data_file` and listed in `files`.
- `config/hose.lua` — `nozzleWeapon = 'WEAPON_MINOZZLE'`. `WEAPON_FIREEXTINGUISHER` removed.
- `tools/assets/nozzle/build_nozzle.py` — material zones, two-pass bake, a DDS writer.
- `.gitignore` — `data/*.meta` no longer ignored; those files are ours now.
- `conventions_spec` — five new assertions.

**Decisions:**

- **The weapon inherits the base game extinguisher's behaviour, not its model.**
  `AMMO_FIREEXTINGUISHER`, `FIRE_EXT_STRAFE`, `DamageType FIRE_EXTINGUISHER`. Those are
  Rockstar's identifiers, so a new weapon gets defined without carrying anyone else's content.
  It does no damage: water knocking a fire down is this resource's own simulation.

- **Material zones, from connected islands rather than coordinates.** The nozzle is black rubber
  bumper and grip, olive body, polished ring. Two positional rules were wrong before the third
  worked: the bale handle is a single CAD island covering both its olive arms and its black
  grip, and it passes straight through the slice of barrel where the polished ring belongs, so
  a coordinate rule painted fragments of the handle chrome. Zone positions came off a
  colour-coded render of the CAD parts, not guesswork.

- **The texture is written as DDS by hand.** Sollumz will only embed DDS -- it warns, skips, and
  still reports a successful export for anything else. Uncompressed A8R8G8B8 rather than BC1: a
  block compressor is a hundred lines of bit packing that could not be validated without a
  reader on this machine, and being wrong there would look like a texture bug rather than an
  encoder bug. 512px, so it costs 1 MB rather than 4.

- **The fallback prop stays.** A client that has not reconnected since the metas were added will
  not have them, and an empty hand reads as a broken hose system rather than a missing asset.

**Verified:**

- `lua tools/run_tests.lua` — **1021 passed, 0 failed** (was 1014).
- The new cross-file assertions were **mutation tested**: renaming `<modelName>` in the
  archetype fails two of them by name. A test that cannot fail is worth nothing.
- Export runs clean with no Sollumz warnings; `UVMap 0` is the real unwrap renamed, not an empty
  layer added beside it.
- `w_mi_nozzle.ydr` is 361,270 bytes, magic `RSC7`, resource version 165. It grew from 163,160
  when the texture began embedding, which is how the silent DDS-only rejection was caught.
- **Not** verified in game. Nothing here has been loaded by FiveM.

**Open:**

- One in-game test: restart, **reconnect**, `/fire nozzle`. If the fallback prop appears, the
  metas did not reach the client.
- Attach offsets are untuned -- the nozzle will sit in the hand at whatever the current numbers
  give until someone looks at it.
- The bumper teeth get chewed by decimation at 4.4%.
- `HOSE-010`, `HOSE-011`, `SCORCH-002` unchanged.

**Next:** hold the nozzle in game and tune where it sits in the hand.

---

## 2026-08-31 (third) — the nozzle is a weapon, not an ornament

**Scope:** first in-game run of `WEAPON_MINOZZLE`, and what it showed.

**What the test reported:** `assetLoaded=1 object=true`. The metas reach the client, the
archetype resolves, the model is real. Everything after this is placement and plumbing.

**Changed:**

- `client/modules/hose/init.lua` — `equipNozzle` / `unequipNozzle` replace `createNozzle`.
  `applyNozzleHold` / `clearNozzleHold` set the carrying stance. `reconcileNozzle` re-checks
  that the weapon is still there and says so once if it keeps disappearing.
- `tools/assets/nozzle/build_nozzle.py` — `GRIP_ORIGIN`, so the model origin is the grip.
- `config/hose.lua` — `nozzleClipset = 'weapons@heavy@minigun'`.
- `/fire nozzle` now equips and re-checks after four seconds rather than making an object.

**Decisions:**

- **A correction, and it is the important entry.** The note in this repository saying
  `GiveWeaponToPed` is stripped by ox_inventory within a second was **wrong**, and it cost the
  whole nozzle path. It was concluded while the weapon had no archetype, and a weapon that does
  not exist is absent immediately after being given -- indistinguishable from something taking
  it away. `CreateWeaponObject` was adopted to work around a problem that did not exist, and an
  attached object cannot be fired, which is the entire point of a nozzle.

  The general lesson is the one this project keeps relearning: when two explanations fit, the
  boring one is usually right, and the way to tell them apart is a measurement rather than an
  argument. `/fire nozzle` now makes that measurement -- it reports whether the weapon is still
  equipped four seconds later, so the inventory question is answered by data.

- **The model origin is the grip, and it is baked.** An equipped weapon has no Lua attach
  offsets; GTA puts the origin at the hand bone. So `GRIP_ORIGIN` is the only control, and
  tuning it costs a rebuild. Worth it -- the alternative tunes freely and cannot spray.

- **No pistol grip on this model.** The disc underneath is the bale handle's pivot plate. Found
  by rendering marker spheres at candidate origins rather than by reading part centroids, which
  had already been wrong twice on this model.

- **The stance is a movement clipset, not a meta.** `weapons@heavy@minigun` via
  `SetPedMovementClipset`. A `weaponanimations.meta` **replaces** the game's animation set
  rather than merging, which is why the two resources here that ship one each carry 13,000 lines
  of copied vanilla data. Ours would have been a third, and they cannot all win.

**Verified:**

- `lua tools/run_tests.lua` — **1026 passed, 0 failed** (was 1021).
- Five new assertions: the hose client does not use `CreateWeaponObject`, does equip and
  unequip, and clears the stance.
- Rebuilt and re-exported: `w_mi_nozzle.ydr`, 356,218 bytes, bounds now
  `(-0.061, -0.135, -0.064) .. (0.061, 0.162, 0.150)` -- shifted by the grip origin.
- **Not** retested in game.

**Open:**

- Retest: restart, reconnect, `/fire nozzle`, then pull a line. `gotAfter4s=false` would mean
  something really is stripping the weapon, and the fix is one ox_inventory entry.
- `GRIP_ORIGIN` is a first guess. Expect one round of adjustment.
- `WEAPON_HOSE` in `ox_inventory/data/weapons.lua` is SmartHose's and stale -- that item errors
  because the weapon no longer exists, and it is not ours to use.
- `HOSE-010`, `HOSE-011`, `SCORCH-002` unchanged.

**Next:** hold a charged line and see where the nozzle actually sits.

---

## 2026-08-31 (fourth) — it was the inventory after all, and the stance T-posed

**Scope:** second in-game run. Two failures, both now understood.

**What the test reported:** the re-equip warning fired, meaning the weapon was put back four
times and taken away four times. And pulling a hose T-posed the player.

**Changed:**

- `client/modules/hose/init.lua` — the stance is cleared whenever the weapon goes, and only
  applied when it is genuinely in hand. `applyNozzleHold` takes an explicit clipset so the
  tester and the real path share one function.
- `config/hose.lua` — `nozzleClipset = nil`. It was `weapons@heavy@minigun`.
- `server/modules/admin/init.lua`, `client/modules/hose/init.lua` — `/fire nozzlehold
  <clipset|off>`, to find a stance live.

**Decisions:**

- **ox_inventory really does strip it — and the previous entry in this log, which said it does
  not, was wrong in the other direction.** Both things were true at different times. Earlier the
  weapon did not exist, which is why it vanished; now it exists and ox_inventory disarms it.
  Correcting a wrong conclusion with another confident guess is how an afternoon disappears, so
  this one was settled by reading `ox_inventory/client.lua` rather than by reasoning:

  ```lua
  elseif client.weaponmismatch and not client.ignoreweapons[weaponHash] then
  ```

  Any weapon the player did not equip through the inventory is disarmed unless listed in
  `ignoreweapons`. The fix is `setr inventory:ignoreweapons ["WEAPON_MINOZZLE"]` in server.cfg --
  a convar, so no resource gets edited and an ox_inventory update cannot wipe it. Their
  `init.lua` already hardcodes `WEAPON_HOSE` the messy way, which is the same fix in the form
  that does get wiped.

- **A weapon clipset is not a movement clipset.** `weapons@heavy@minigun` is what
  `weaponanimations.meta` lists as the minigun's motion clipset, which is exactly why it looked
  safe. Passed to `SetPedMovementClipset` it T-poses: a movement clipset carries walk, run and
  idle clips, a weapon clipset does not, and with nothing to stand in the skeleton falls back to
  its bind pose. `HasAnimSetLoaded` answers true for both, so there is no check to write.

- **So the stance is found by trying, not by reading.** `/fire nozzlehold` applies one live and
  `off` undoes it. This is the third thing on this model that could not be reasoned out and had
  to be looked at -- after the orientation and the grip -- which is starting to look less like
  bad luck and more like the shape of the work.

- **The two bugs fed each other.** The strip removed the weapon; the stance stayed applied to an
  empty-handed ped. A T-pose was the visible result of both at once, which is why the stance is
  now cleared in the same branch that notices the weapon has gone.

**Verified:**

- `lua tools/run_tests.lua` — **1027 passed, 0 failed** (was 1026).
- The strip mechanism was read in `ox_inventory/client.lua`, not inferred.
- **Not** retested in game.

**Open:**

- Retest after the convar: pull a line, confirm the nozzle stays and can be fired.
- Find a stance with `/fire nozzlehold`. `move_ballistic_minigun` is the first candidate worth
  trying, on the grounds that it at least begins `move_`.
- `GRIP_ORIGIN` still unjudged -- nothing has stayed in a hand long enough to look at it.
- `HOSE-010`, `HOSE-011`, `SCORCH-002` unchanged.

**Next:** the convar, then a stance, then finally look at where the thing sits.

---

## 2026-08-31 (fifth) — it holds, and the T-pose was the wrong native

**Scope:** third in-game run. The convar worked; the nozzle stays in hand.

**What the test showed:** the weapon holds. The stance was the fire extinguisher's rather than
the minigun's, and the nozzle was gripped by its body rather than its handle.

**Changed:**

- `tools/assets/nozzle/build_nozzle.py` — `GRIP_ORIGIN` moved to the bale handle.
- `client/modules/hose/init.lua` — `applyNozzleStrafe` alongside `applyNozzleHold`; both cleared
  together.
- `config/hose.lua` — `nozzleStrafeClipset = 'weapons@heavy@minigun'`.
- `/fire nozzlehold <clipset|off> [move]` now picks which kind of clipset to try.

**Decisions:**

- **The T-pose was the wrong native, not the wrong name.** `weapons@heavy@minigun` was right all
  along -- it is what the game's own `weaponanimations.meta` lists as the minigun
  `WeaponClipSetHash`. It was being passed to `SetPedMovementClipset`, and a weapon clipset
  carries no walk or idle clips, so there was nothing to stand in and the skeleton fell back to
  its bind pose. The right native is `SetPedStrafeClipset`.

  Worth recording because the previous entry in this log concluded the name was unusable and
  gave up on it. It was one function call away. `HasAnimSetLoaded` answers true for both kinds,
  so nothing in the API distinguishes them -- the distinction is only in which setter you call,
  which is exactly the sort of thing that is invisible until someone reads the vanilla data and
  notices the field is called *Weapon*ClipSetHash.

- **Two clipsets, cleared together.** The hold and the walk are separate, and either one left
  applied outlasts the nozzle on a ped with empty hands. `conventions_spec` now requires both
  resets.

- **The origin is on the bale handle.** That is what a bale handle is for. The first attempt put
  it on the barrel axis and held the nozzle by its body, which is wrong for the same reason
  carrying a kettle by the spout would be. `z = 0.128` is the middle of the ribbed grip bar.

- **Still no `weaponanimations.meta`, and now definitely not needed.** That file replaces the
  game's whole animation set rather than merging -- both resources here that ship one carry a
  13,000 line copy of the vanilla data. Two natives do the same job with no global blast radius.

**Verified:**

- `lua tools/run_tests.lua` — **1042 passed, 0 failed**.
- Rebuilt and re-exported: `w_mi_nozzle.ydr`, 363,853 bytes. Bounds
  `(-0.061, -0.157, -0.193) .. (0.061, 0.139, 0.022)` -- the origin now sits at the top, with
  the nozzle hanging below it, which is what a hand on the bale handle looks like.
- **Not** retested in game.

**Open:**

- Retest the hold and the grip together.
- Nothing has been fired yet. Water out of the nozzle is the next real milestone and none of it
  is written.
- `HOSE-010`, `HOSE-011`, `SCORCH-002` unchanged.

**Next:** water.

---

## 2026-08-31 (sixth) — a tuner, rather than another guess at the grip

**Scope:** fourth in-game run. It holds and it poses; the placement is wrong and walking T-poses.

**Changed:**

- `config/hose.lua` — `nozzleClipset = 'weapons@heavy@minigun'`, matching the hold.
- `client/modules/hose/init.lua` — `applyNozzleGrip`, re-attaching the weapon entity to a bone
  with configurable offsets, re-applied every pass.
- `/fire nozzlegrip <left|right> <x> <y> <z> <rx> <ry> <rz>` and `off`.

**Decisions:**

- **The walking T-pose is the missing half of a pair.** The vanilla data gives the minigun
  `weapons@heavy@minigun` for **both** `MotionClipSetHash` and `WeaponClipSetHash`. Only the
  weapon one was set, so the hold was right and the walk had nothing to stand in. Setting both
  matches what the game does with its own weapon, which is a better argument than any reasoning
  about what a clipset contains.

  Also worth recording: the very first T-pose was blamed on passing a weapon clipset to
  `SetPedMovementClipset`. That was probably wrong too -- the weapon was being stripped at the
  same time, so the ped was empty-handed, and this run shows the same name works fine as a
  movement clipset when something is actually in hand. Two bugs overlapping produced a
  confident, wrong conclusion, twice.

- **Placement stops being a rebuild.** Baking a new origin costs an export and a restart to see
  a single attempt, and the grip has now been wrong twice -- centre, then barrel, and the bale
  handle still needs rotating. `GetCurrentPedWeaponEntityIndex` returns the weapon as an entity,
  and an entity can be re-attached, so placement becomes six numbers and a bone that can change
  live.

  This is the same conclusion this project reached about ports and about the rope: when
  something can only be judged by looking at it, the tool that lets someone look is worth more
  than another careful guess. The remaining unknown -- which hand, and which way round -- is one
  I cannot see and the user can.

- **`SKEL_` bones, not `PH_`.** The prop-helper bones are absent on player peds and
  `GetPedBoneIndex` answers -1, which attaches to the world origin. Already paid for once with
  the rope.

- **Re-applied every pass, not once.** The game re-places an equipped weapon on every stance
  change -- drawing, aiming, entering a vehicle. A grip that survives until the first aim is not
  worth having.

**Verified:**

- `lua tools/run_tests.lua` — **1043 passed, 0 failed**.
- **Not** tested in game. The grip numbers are deliberately `nil`: placement stays with the game
  until someone finds better ones.

**Open:**

- Find the grip with `/fire nozzlegrip` and put the numbers in `nozzleGrip`.
- Confirm walking no longer T-poses now both clipsets are set.
- Nothing has been fired. Water is still the next real milestone.

**Next:** water, once the thing is being held properly.

---

## 2026-08-31 (seventh) — the model gets a hose, and a shipped bug found by log line

**Scope:** the nozzle was a nozzle floating in mid air. Now it has a line off the back.

**Changed:**

- `tools/assets/nozzle/build_nozzle.py` — `HOSE_STUB`, a bevelled curve off the coupling; a
  `hose` material zone; and the grip-origin shift moved to the end of the pipeline.

**Decisions:**

- **The second hand needs something to hold.** The carrying pose is two-handed and the model
  ended at the coupling, so the left hand gripped air. A length of hose fixes that and makes the
  line read as continuing past the frame.

- **Its dimensions were measured off the model, not chosen.** Walking the radius forward from the
  back face: a 6 mm stem for the first 20 mm, flaring to 0.0324 by 60 mm, which is the coupling
  body. A hose of radius 0.030 butts onto that with no visible step and swallows the stem, which
  is what a coupling swaged onto hose actually looks like.

- **It curves back and down.** A straight tube points into the firefighter's own chest.

- **Added after decimation.** Its 316 triangles sit on top of the 8,000 rather than inside it,
  and it keeps the roundness it was built with instead of being collapsed.

**A bug that shipped, and how it surfaced:**

Moving `GRIP_ORIGIN` onto the bale handle last session dropped the whole mesh by 0.128 *before*
the zones were classified. Every zone threshold had been read off a render of the model in its
own space, so `GRIP_MIN_Z = 0.100` no longer matched anything: the handle was not found, its
ribbed grip was never marked rubber, and **a nozzle shipped with the wrong colours**.

Nothing failed. The only trace was one line in the build log reading `handle is #-1` where it
had previously read `handle is #31`, and it only got noticed because this build printed it again
next to a number that had changed. That is a thin thread to hang a catch on.

The fix is structural rather than a corrected constant: the origin shift now happens **last**,
after classification and baking, so the grip and the zones cannot invalidate each other. The
general shape of the mistake — a later step quietly breaking an earlier one's assumptions
because they share a coordinate space — is worth remembering, because no test covers it and the
diagnostic that caught it was luck.

**Verified:**

- `lua tools/run_tests.lua` — **1043 passed, 0 failed**.
- Rebuilt: 8,316 triangles, zones `3904 rubber, 3837 olive, 210 chrome, 215 hose` — the rubber
  count back to what it was before the regression, which is the check that the handle is found.
- `w_mi_nozzle.ydr`, 364,122 bytes, exported clean.
- **Not** tested in game.

**Open:**

- Find the grip with `/fire nozzlegrip` now there is a hose to hold.
- Confirm walking no longer T-poses.
- The hose stub carries a faint seam along its length from the UV projection. Cosmetic.
- Still nothing fired.

**Next:** water.

---

## 2026-08-31 (eighth) — the grip command never parsed, and the stance is given up on

**Scope:** fifth in-game run. Two failures, one embarrassing and one worth conceding.

**Changed:**

- `server/modules/admin/init.lua` — `nozzlegrip` and `nozzlehold` read `args[2]`, not `args[1]`.
- `config/hose.lua` — both clipsets off.
- `tools/tests/conventions_spec.lua` — no subcommand may read `args[1]`.

**Decisions:**

- **`/fire nozzlegrip right 0 0 0 0 0 0` printed its own usage text, every time.** `/fire`
  passes the whole line, so `args[1]` is the subcommand name and a subcommand's first argument is
  `args[2]`. Every other subcommand in the file already did this correctly; the two added
  yesterday did not.

  The reason it survived being written and read is that it cannot error. The value read is simply
  the string `nozzlegrip`, which fails the `left|right` check, which prints the usage -- which
  looks exactly like mistyping the command. `conventions_spec` now forbids `args[1]` anywhere
  outside the dispatcher, and the check was mutation tested: reintroducing it fails by name.

- **The minigun stance is given up on, and both clipsets are off.** What was tried:

  | Attempt | Result |
  |---|---|
  | `SetPedMovementClipset` with `weapons@heavy@minigun` | T-pose |
  | `SetPedStrafeClipset` with the same | holds correctly, T-poses on walking |
  | Both together | still T-poses on walking |

  The name is not the problem -- it is what the game's own weaponanimations gives the minigun for
  *both* `MotionClipSetHash` and `WeaponClipSetHash`. The natives do not reproduce what the
  weapon animation system does with it, and three attempts is enough to stop guessing.

  Without them the weapon's own stance applies, which is the fire extinguisher's: two hands,
  pointed forward. Not the brace a charged line deserves, but it works. A firefighter holding a
  nozzle slightly wrong beats one standing in a bind pose.

- **What would actually work is a `weaponanimations.meta` entry**, because that is how the game
  maps a weapon to a stance in the first place. Still not shipped: that file replaces the whole
  vanilla animation set rather than merging, which is why both resources here that ship one carry
  a 13,000 line copy, and a third would fight them -- including ThrowBag, which is installed. That
  is a trade worth making deliberately, with the user, rather than sprung on a live server.

**Verified:**

- `lua tools/run_tests.lua` — **1045 passed, 0 failed**.
- The `args[1]` check was mutation tested: putting it back fails the suite by name.
- **Not** retested in game.

**Open:**

- `/fire nozzlegrip` has never actually run. It should work now.
- The stance is the extinguisher's until someone decides about `weaponanimations.meta`.
- Still nothing fired.

**Next:** the grip, then water.

---

## 2026-08-31 (ninth) — the animation meta, shipped as a deliberate experiment

**Scope:** the minigun stance, done the way the game actually does it.

**Changed:**

- `data/weaponanimations.meta` — one entry, `WEAPON_MINOZZLE`, mapped to the minigun's clip sets.
- `fxmanifest.lua` — declared with `data_file` and listed in `files`.
- All three metas — double hyphens removed from comments.
- `conventions_spec` — shipped game data must be well-formed XML.

**Decisions:**

- **This is the correct fix, and it is a gamble.** Mapping a weapon to a stance is what
  `weaponanimations.meta` is for; three attempts to force it with natives all T-posed. The
  gamble is that `CWeaponAnimationsSets` is a single global structure and nobody here knows
  whether FiveM merges a second one or replaces it outright.

  If it merges, only the nozzle is affected. If it replaces, every weapon not listed in our file
  loses its animations, server-wide. The evidence on this machine points at replacement -- both
  other resources that ship one carry a full 13,000 line copy of the vanilla data, which is only
  necessary if it replaces -- but they may equally have copied that from a tutorial without
  testing. Taken with the user, who owns the server and can restart it, and the revert is one
  line in the manifest.

  **What to check:** draw a pistol, a rifle, and anything from ThrowBag. Fine means it merges.
  Wrong means it replaces, and revert.

- **A double hyphen is illegal inside an XML comment, and all three metas had one.** The comments
  in these files are long prose, where `--` is the natural way to punctuate an aside. Every one
  of them was invalid XML on first write and would have been handed to the game that way.

  Worth a test rather than a fix because of the cost. These files are not read by this resource;
  they go to the game, which parses them itself and is not obliged to explain a refusal. A weapon
  that silently never appears -- or a weapon file that takes other weapons down with it -- is a
  long way from an unclosed comment in a paragraph nobody was reading. `conventions_spec` now
  walks every comment in every shipped meta, mutation tested by putting a hyphen back.

**Verified:**

- `lua tools/run_tests.lua` — **1055 passed, 0 failed** (was 1045).
- All three metas parse as XML under a real parser, not just the new Lua check.
- The XML check was mutation tested: a reintroduced `--` fails by file name.
- **Not** tested in game. This is the run that decides whether the file merges.

**Open:**

- The experiment itself. Revert is one `data_file` line.
- `/fire nozzlegrip` still unrun.
- Still nothing fired.

**Next:** whether other weapons survive.

---

## 2026-08-31 (tenth) — the animation file merges, and the grip gets a nudge

**Scope:** the experiment paid off. Placement is the last thing left.

**The result: FiveM merges `weaponanimations.meta`.** With our file loaded and only
`WEAPON_MINOZZLE` in it, pistols, rifles and ThrowBag's weapon all kept their animations, and the
nozzle is held correctly.

That is worth recording loudly because the evidence pointed the other way. Both resources on this
machine that ship one of these carry a **full 13,000 line copy** of the vanilla data with their
own entry added -- which is only necessary if the file replaces. They had copied an approach that
nobody appears to have checked, and it propagated. A new weapon needs four lines of animation
mapping, not thirteen thousand.

The general lesson is one this project keeps paying for: two resources doing the same thing is
not evidence that the thing is necessary. It is evidence that one of them copied the other.

**Changed:**

- `data/weaponanimations.meta`, `fxmanifest.lua` — comments now record the answer rather than the
  question.
- `/fire nozzlegrip` — per-axis nudging, `show`, and `bone`.

**Decisions:**

- **Nudging is per-axis.** Finding a placement means changing one thing and seeing what moved,
  and retyping six numbers to alter one of them is how people stop bothering.
  `/fire nozzlegrip nudge z 0.02`.

- **It prints the config line, not just the numbers.** A placement found by eye should not then
  have to be copied down by hand out of six separate chat messages.

**Verified:**

- `lua tools/run_tests.lua` — **1055 passed, 0 failed**.
- In game: the stance is right and no other weapon is affected.

**Open:**

- The grip itself, which is now a few minutes of nudging rather than a rebuild.
- Still nothing fired.

**Next:** water.

---

## 2026-08-31 (eleventh) — the grip survives a crash, and aiming gets its own placement

**Scope:** a crash ate a placement mid-tuning. Two fixes and a confirmation.

**Changed:**

- `client/modules/hose/init.lua` — grips persist to KVP; a separate placement while aiming; the
  attach is no longer redone every frame.
- `config/hose.lua` — `nozzleGripAiming`.
- `data/weaponanimations.meta` — the comment now carries the log evidence.

**Decisions:**

- **The placement is saved to KVP.** Finding one is minutes of nudging, and losing it to a crash
  before it has been written down means doing all of it again. Per client, because it is a local
  preference being discovered rather than server state.

  The values from the lost session were **not** recoverable. Every client log was searched and
  none of the reported lines are in any of them -- presumably the tail was never flushed. Which
  is the argument for persisting rather than printing.

- **Aiming gets its own placement.** The hand rotates between carrying and aiming and the nozzle
  has to follow differently, so one set of numbers cannot serve both. `/fire nozzlegrip` edits
  whichever stance the player is currently in, so aiming and then nudging fixes the aiming pose
  with no extra syntax and no way to edit the wrong one by accident.

- **The attach is applied on change, not every frame.** It was being redone every pass, which is
  wasteful for something that holds until broken, and is a plausible contributor to the crash. It
  now re-attaches only when the numbers change, the stance changes, or the weapon entity is
  replaced.

**The merge, confirmed independently:** the client log shows **seven** `weaponanimations.meta`
files loading side by side, from four resources -- FireTools alone ships four, one per tool. If
these replaced rather than merged, only the last would survive and FireTools would have noticed
years ago. Ours is 90 lines; SmartHose's and ThrowBag's are 13,011 and 13,223.

That is a better answer than the in-game check, and it was sitting in a log file the whole time.
Worth remembering that the machine already had the evidence -- the question was never hard, only
unasked.

**Verified:**

- `lua tools/run_tests.lua` — **1055 passed, 0 failed**.
- `/mi_fire/data/weaponanimations.meta` appears in the client log as loading, so the file is
  reaching the game rather than being silently ignored.

**Open:**

- Re-nudge the placement, now that losing it costs nothing.
- The aiming placement has never been set.
- Still nothing fired.

---

## 2026-08-31 (twelfth) — hold the aim, so the aim can be tuned

**Scope:** tuning the aiming placement was unworkable by hand.

**Changed:**

- `client/modules/hose/init.lua`, `server/modules/admin/init.lua` — `/fire nozzlegrip aim` and
  `carry`.

**Decisions:**

- **`aim` holds the aim control down.** Editing the aiming placement otherwise means holding
  right mouse, typing a command, releasing to read the result, and re-aiming -- per nudge, of
  which there are dozens. `SetControlNormal(0, 25, 1.0)` every frame is how a control is held
  from script; there is no set-and-forget native.

  The stance switch and the pose lock are the same action on purpose. Two commands -- one to
  choose which placement you are editing and another to hold the pose -- is two things to get out
  of step, and the failure would be editing one set while looking at the other.

- **It releases itself.** Dropping the line, or the resource stopping, clears the lock. A player
  left holding the aim control with nothing in their hands has no way to work out why they are
  stuck, and would reasonably blame the server rather than a tuning command they ran ten minutes
  earlier.

**Verified:**

- `lua tools/run_tests.lua` — **1055 passed, 0 failed**.
- **Not** tested in game.

**Open:**

- Both placements still unset.
- Still nothing fired.

---

## 2026-08-31 (thirteenth) — the placements, found and baked in

**Scope:** `ASSET-001` is finished except for water coming out of it.

**Changed:**

- `config/hose.lua` — both placements, found in game.
- `client/modules/hose/init.lua` — rotations wrap into 0-359; the `off` message stopped lying.
- `tools/tests/conventions_spec.lua` — the placements are checked for shape.

**The numbers:**

```lua
nozzleGrip       = { bone = 'left', x = 0.100, y = 0, z = 0, rx = 30, ry = 203, rz = 120 }
nozzleGripAiming = { bone = 'left', x = 0.100, y = 0, z = 0, rx = 55, ry = 203, rz = 220 }
```

**Decisions:**

- **The left hand.** That is the one the minigun animation puts forward on the weapon, so the
  nozzle sits in the leading hand and the hose runs back past the trailing one -- which is how a
  charged line is actually worked. Worth noting because every guess made here assumed the right
  hand, on the grounds that GTA equips weapons there. The animation had other ideas, and only
  trying it showed that.

- **The two placements differ by 25 degrees of pitch and 100 of yaw, and nothing else.** That is
  the hand rotating as the ped brings the nozzle up. Small -- and the whole reason one set of
  numbers could not serve both, which took a screenshot of a nozzle sticking sideways to notice.

- **Rotations wrap into 0-359 as they are nudged.** They arrived as `rx = 390` and `rz = 840`,
  which is what nudging by 15 a few dozen times produces. Identical in behaviour, a nuisance to
  read, and worse to copy into a config where the next person has to work out whether 840 means
  something. Wrapped at nudge time so what is reported is what is stored.

- **The shape is tested even though the values cannot be.** They were found by hand over two
  sessions, one of which was lost to a crash. Nobody would notice a typo until the next time they
  picked up a line, so the test asserts a real bone name, offsets within half a metre of the
  hand, and wrapped rotations. A misplaced decimal puts the nozzle out in the road.

**Verified:**

- `lua tools/run_tests.lua` — **1083 passed, 0 failed** (was 1055).
- The values are the ones reported in game, wrapped: `rx 390 -> 30`, `rz 840 -> 120`,
  `rx 415 -> 55`, `rz 940 -> 220`. Modular, so behaviour is unchanged.

**Open:**

- **Water.** Nothing has ever been fired. This is the whole remaining point of the nozzle, and
  none of it is written.
- `HOSE-010`, `HOSE-011`, `SCORCH-002` unchanged.

**Next:** water out of the nozzle, and onto a fire.

---

## 2026-08-31 (fourteenth) — water

**Scope:** water out of the nozzle, and the bezel on the scroll wheel.

**What was already there:** almost all of it. `Fire.applyAgent` is the single entry point for
suppression, `shared/suppression.lua` has the rates and the agent matrix, and
`mi_fire:server:hoseWater` already validated the holder, capped the flow, drew the tank, warned
when it went soft, and routed everything through the matrix. The client already worked out where
the player was aiming.

Two things were missing, and neither was the hard part.

**Changed:**

- `client/modules/hose/init.lua` — water flows while the trigger is held; a visible stream; the
  scroll wheel works the bezel.
- `config/hose.lua` — `visuals.stream`.
- `shared/hose.lua` — `Hose.stepPattern`.
- `server/modules/hose/init.lua` — the pattern event takes a direction.
- `/fire nozzlestream` — aim the particle.

**Decisions:**

- **Water flows while the trigger is held, and not otherwise.** It used to flow continuously for
  anyone holding a charged line, which drained a thousand gallon tank at a rig nobody was
  standing near, and made the nozzle something you carried rather than something you worked. The
  bale on a real nozzle is exactly this.

  The disabled attack control is checked as well as the enabled one, because aiming disables the
  plain control in some states and a nozzle that stopped flowing the moment you aimed it would
  be a puzzling bug to be handed.

- **`core` / `water_cannon_jet`, taken from something already running.** The water cannon rigs on
  this machine drive it at scale 2.0 with an offset and a rotation. Same rule as the fire
  particle pairs and the roll animation: take the one that works somewhere over the one whose
  name sounds right. Attached to the weapon entity rather than the ped, so it follows the nozzle
  through every stance without anything tracking it.

- **The bezel clamps; the command wraps.** Scrolling past a wide fog and arriving back at a
  straight stream is not something a nozzle does, and on a fireground it is a faceful of steam.
  The `/fire` command still wraps, because a command has nowhere to show which end you are at and
  stopping dead reads as broken.

- **The stepping moved into `shared/hose.lua`.** The interesting behaviour is entirely at the
  ends, and inside a net event handler none of it could be tested. Ten assertions now cover both
  stops, the wrap, a smooth bore with nothing to turn, a missing nozzle, and a pattern name that
  does not match anything.

- **The scroll wheel is disabled while the line is open.** Those controls are weapon switching on
  a default bind, so without it adjusting the fog also puts a pistol in your hands.

**Verified:**

- `lua tools/run_tests.lua` — **1094 passed, 0 failed** (was 1084).
- **Not** tested in game. The particle's rotation is a guess and is the thing most likely to be
  wrong -- `/fire nozzlestream nudge rz 90` until it points the right way.

**Open:**

- Aim the stream. Which way a particle emits is not readable from anything.
- Whether scroll up should narrow or widen. One line to flip.
- `HOSE-010`, `HOSE-011`, `SCORCH-002` unchanged.

**Next:** put it on an actual fire and watch the intensity come down.

---

## 2026-08-31 (fifteenth) — a crash on opening the nozzle

**Scope:** the game goes down on the first trigger pull. Cause unconfirmed.

**What could not be established:** the crash log. The legacy FiveM data directory has nothing
newer than several hours before the crash, and the `FiveM for GTAV Enhanced` install alongside it
has no `logs` or `crashes` directory at all. So this entry is reasoning, not evidence, and it
says so.

**Changed:**

- `client/modules/hose/init.lua` — the stream particle attaches to the **hand bone** rather than
  the weapon entity; `/fire nozzlestream off` disables the particle outright.
- `config/hose.lua` — `stream` offsets are now from the hand, and `stream = false` removes it.

**Decisions:**

- **The particle moved off the weapon entity.** On the weapon reads better -- the jet follows the
  nozzle for free -- but the weapon object is created and destroyed by the game *and* re-attached
  by `applyNozzleGrip` on every stance change. Aiming is a stance change, so pulling the trigger
  while aiming re-attached the weapon and started a looped particle on it in the same frame.
  That is a plausible way to take a game down, and the ped is stable in a way a weapon object is
  not.

  It is the best suspect. It is not a confirmed cause, and the difference matters.

- **`off` disables the particle rather than the tuning.** The first question about this crash is
  whether the particle is involved at all, and that deserves an answer in ten seconds rather than
  another round of edits and a restart. Water still flows with it off, so the two halves can be
  bisected against each other in game.

  This is the more useful half of the change. A fix that might work is worth less than a way to
  find out what is actually broken -- and everything else here has been settled by looking rather
  than reasoning.

- **The offsets restart from zero**, because they were relative to the model and are now relative
  to the hand. Nothing carries over and there is nothing to derive them from; `/fire nozzlestream
  nudge` finds them.

**Verified:**

- `lua tools/run_tests.lua` — **1094 passed, 0 failed**.
- Definition order checked: `BONES` and `activeGrip` are both above `startStream`.
- **Nothing about the crash is verified.** The change is a hypothesis with a switch attached.

**Open:**

- Does it still crash with `/fire nozzlestream off`? That answer decides everything next.
- If it does, the particle is innocent and the suspects are the water event, the shape test in
  `aimPoint`, or the control handling.

---

## 2026-08-31 (sixteenth) — the crash dump, and what it rules out

**Scope:** the dump turned up in `logs/CfxCrashDump_2026_08_31_23_31_42`, which is where the
client drops one when it goes down with this resource open.

**What it says:**

```
crash_hash   fivem.exe+16A275F
legacy hash  vegan-chicken-football
stack        GTA5_b3258.exe+16A275F, +16A2683, +91DC5E, +1028AF0, ...
```

Entirely native. **No script error from mi_fire, or from anything else, anywhere before it** --
the last log line is 98 seconds earlier and unrelated. So nothing threw; the game walked into
something and fell over.

The session log also confirms `data/weaponanimations.meta` loading alongside the other two, which
settles the last doubt about that file.

**What it rules out, and what it does not:**

- **The raycast is not it.** `aimPoint` uses `StartExpensiveSynchronousShapeTestLosProbe`, which
  looked like a fair suspect on its name alone -- until `client/modules/placement/init.lua` turned
  out to call the same native, the same way, and to have been exercised heavily by `/fireoffset`
  and every port that has been placed. Proven in this codebase. Changing it would have been churn
  dressed as a fix.

- **A correction to yesterday's reasoning.** This was almost certainly the first time a line has
  ever been charged, usable and flowing, so `aimPoint` is exactly as new in practice as the
  particle is. It was wrong to treat one as established and the other as suspect.

- **The particle is what remains.** It is the one genuinely new native in the path, and it was
  attached to an object the game creates, destroys, and that `applyNozzleGrip` re-attaches on
  every stance change.

**Changed:**

- A bone index of `-1` no longer reaches the particle native. `GetPedBoneIndex` answering -1 means
  the bone is not on this ped, and handing that to a native is how the rope once anchored itself
  to the middle of the map. What it does to a particle is not worth finding out on someone else's
  session.
- `logs/` is gitignored.

**Verified:**

- `lua tools/run_tests.lua` — **1094 passed, 0 failed**.
- Read from the dump rather than guessed: the crash is native, unaccompanied, and the animation
  meta loads.

**Open:**

- The bisect still has to be run. `/fire nozzlestream off` and pull the trigger: still crashing
  means the particle is innocent and the answer is in the water event or the control handling.

---

## 2026-08-31 (seventeenth) — the crash was an empty FlashFx

**Scope:** found, and it was in `data/weapons.meta` the whole time.

**What actually settled it:** the observation that it crashes with an **uncharged, uncoupled**
line. That single fact demolished two days of reasoning in one sentence. The water thread requires
`state == 'charged'`, `gpm > 0`, `usable` and being the nozzle holder before it does anything at
all -- so with an uncharged line there is no particle, no raycast, no water event and no control
handling. None of the code being investigated was running.

Which left only one thing that happens on a click with a nozzle in hand: **firing the weapon**.

**The bug:**

```xml
<FireType>VOLUMETRIC_PARTICLE</FireType>
...
<FlashFx />          <!-- empty -->
```

`VOLUMETRIC_PARTICLE` emits a particle on every shot and takes its name from `FlashFx`. Empty
sends the game looking for something that is not there, and it goes down natively on the first
trigger pull. The working reference has `<FlashFx>weap_extinguisher</FlashFx>` -- with both
chance values at zero, so it never renders. **The field has to be populated whether or not it is
ever used**, which is the entire trap.

It was left empty deliberately, on the reasoning that mi_fire draws its own water and the weapon
needed no effect of its own. That reasoning was wrong, and it was written into a comment as if it
were considered.

**Three wrong guesses, and what each cost:**

1. The particle on the weapon entity. Plausible, well argued, and irrelevant -- it cannot run on
   an uncharged line.
2. The raycast. Ruled out correctly, by finding the same native already proven in
   `client/modules/placement/init.lua`.
3. Everything downstream of the trigger. All of it in the water path, none of it reachable.

The dump was read properly and said "native, no script error", which was true and pointed
nowhere, because *every* candidate was native. What was missing was not more analysis of the
dump; it was the one observation that narrows the set -- and it came from the person who could
press the button.

**Kept anyway:** the particle now attaches to the hand bone rather than the weapon entity, and a
-1 bone index cannot reach the native. Neither was the crash, both are better.

**Changed:**

- `data/weapons.meta` — `FlashFx` names a particle; `PedDamageHash` matches the reference.
- `tools/tests/conventions_spec.lua` — a volumetric weapon must name the particle it fires.

**Verified:**

- `lua tools/run_tests.lua` — **1096 passed, 0 failed**.
- Mutation tested: restoring `<FlashFx />` fails both new assertions by name. The test catches
  the exact form that crashed.
- The XML comment written *for this fix* contained a double hyphen and was invalid until the
  existing check caught it, which is a reasonable advert for that test.

**Open:**

- Whether it actually stops crashing. Nothing here is verified in game.
- The stream particle offsets are still zero and unfound.

---

## 2026-08-31 (eighteenth) — stop guessing at the weapon, align it

**Scope:** the same crash, after the FlashFx fix. Identical hash, identical stack.

**What the second dump said:** `fivem.exe+16A275F`, `vegan-chicken-football`, and a stack
matching the first one frame for frame. So the empty `FlashFx` was a real bug and not this one.
Four guesses now, all wrong, all reasoned from the code rather than from anything measured.

**What changed in approach:** the whole `CWeaponInfo` was diffed field by field against one that
is known to fire without crashing. That found fifty differences, and among them:

- **`DefaultCameraHash` was `DEFAULT_FIRE_EXTINGUISHER_CAMERA`, which does not exist.** It was
  written because it looked like the right shape next to `FIRE_EXT_STRAFE`. Nothing on this
  machine contains that string. Real weapons use `HIP_AIM_CAMERA`.
- **`CoverCameraHash` and `RunAndGunCameraHash` were empty.** An empty camera slot is not "no
  camera", it is a lookup that finds nothing -- and the game does that lookup when you aim, take
  cover, or move while firing.
- **Around forty fields held `0` where the working configuration holds `-1`.** Those are not the
  same thing. `-1` is the sentinel for "unset"; `0` is a real value. Ranges, rumble timings and
  the shot cache window were all being handed a meaningful zero rather than being disabled.

All forty-six are now aligned. The file differs from a working weapon in exactly four places:
`Name`, `Model`, `Slot`, `HumanNameHash`. Damage stays at zero and the `NonViolent` and
`SuppressGunshotEvent` flags stay, so the intent survives.

**The lesson, which is the point of this entry:** this file was written from the schema outwards,
filling every field with what seemed sensible, and a comment was attached to each decision
explaining the reasoning. The reasoning was confident and wrong in at least three places, and the
comments made it look considered. A configuration that has to satisfy an engine you cannot read
is not somewhere to be original: start from one that works and change one thing at a time, which
is now written at the top of the file.

**Changed:**

- `data/weapons.meta` — 46 fields aligned; the header rewritten to record why.
- `tools/tests/conventions_spec.lua` — camera hashes must be present and named; the invented one
  is barred by name; meta checks now strip XML comments first.

**Verified:**

- `lua tools/run_tests.lua` — **1103 passed, 0 failed**.
- Mutation tested: emptying `CoverCameraHash` fails two assertions by name.
- The comment-stripping was itself found by a test -- the invented hash was caught inside the
  paragraph explaining its removal, which is the check being right and the matching being sloppy.
- **Not** tested in game. If it crashes again, the cause is the model or the archetype, because
  nothing else is left to differ.

**Open:**

- Whether it holds.
- The stream particle offsets are still zero.

---

## 2026-09-01 — stop fixing, start bisecting

**Scope:** third identical crash, after the weapon was aligned field for field.

Same hash, same stack. Five attempts at this now, every one a fix reasoned out and shipped
without a measurement behind it. That is the thing to correct, not the next field.

**What is actually known:**

- The crash is on firing, never on equipping or holding, and never varies.
- `data/weapons.meta` now differs from a weapon known to fire without crashing in **four**
  places: `Name`, `Model`, `Slot`, `HumanNameHash`. Three of those are strings a lookup either
  finds or does not.
- **Our model has no skeleton.** The Blender file contains one mesh and no armature, confirmed
  by reading it. Every GTA weapon model is a skinned drawable.

**What could not be established:** the bone names a working weapon uses. Sollumz's importer
produced nothing at all in a headless run -- not for FireTools' circular saw, not for a stock
pistol, and not for our own `.ydr`, which is known to load in game. So the importer is what
failed, and nothing was learned about skeletons from it either way.

Two smaller things went wrong on the way there, both already written down elsewhere in this
repository and both repeated anyway: `read_factory_settings` discards the extension repository
list exactly as `--factory-startup` does, and a broad `grep` across the whole resources tree
takes long enough to need backgrounding.

**Changed:** `data/weapons.meta` points at `w_am_fireext` -- the base game extinguisher's model.

That is not a fix. It is the one measurement that separates the two remaining possibilities, and
it costs a single restart:

| Result | Meaning |
|---|---|
| Crash stops | The fault is in `w_mi_nozzle`, and the missing skeleton is the first thing to look at |
| Crash continues | The model is innocent, and the fault is somewhere none of us has looked |

**On the discipline:** the temptation was to add a skeleton now, because the evidence for its
absence is solid and every weapon has one. That would have been a sixth reasoned guess, and if it
had not worked it would have taught nothing -- the restart would have been spent. A bisect
returns a fact either way. After five wrong guesses, facts are worth more than fixes.

`conventions_spec` was taught about the diagnostic rather than having the check deleted for it:
while the model is swapped it requires the `DIAGNOSTIC` marker and the restore instructions to be
present, so the state is deliberate and cannot be left behind quietly.

**Verified:**

- `lua tools/run_tests.lua` — **1104 passed, 0 failed**.
- The XML comment written for this change contained a double hyphen, again, and was caught by the
  check that exists for it, again.

**Open:**

- The answer to the bisect.
- Restoring `w_mi_nozzle` afterwards, either way.

---

## 2026-09-01 (second) — the model had no skeleton

**Scope:** the bisect failed usefully, and the answer turned up in Sollumz's own source.

**The bisect gave nothing to test.** Pointing `<Model>` at `w_am_fireext` produced no weapon at
all, so there was no trigger to pull. A bad measurement -- but it did not need to be run twice,
because reading the exporter answered the question outright.

**`ydr/ydrexport.py`, line 135:**

```python
if armature_obj or drawable_obj.type == "ARMATURE":
    drawable.skeleton = create_skeleton(...)
else:
    drawable.skeleton = None
```

`sollumz.converttodrawable` produces an **Empty** with the mesh underneath. So every `.ydr` this
pipeline has ever produced shipped `skeleton = None`, while every GTA weapon model is a skinned
drawable and firing looks up a muzzle bone to emit the flash from. The blend confirmed it from
the other side: one mesh, no armature, ever.

**Changed:**

- `tools/assets/nozzle/export_ydr.py` — the Drawable root is now an armature carrying `gun_root`
  and `gun_muzzle`, the muzzle at the tip on the barrel axis.
- `verify_skeleton` — decompresses the finished `.ydr` and fails if the bones are not in it.
- `data/weapons.meta` — the bisect reverted.

**Decisions:**

- **The conversion still runs first.** Building the hierarchy by hand exported nothing and
  reported "has no Sollumz materials", because `get_sollumz_materials` walks the model's LOD
  levels and only `converttodrawable` sets those up. Only the root gets swapped afterwards.

- **The pipeline now checks the file, not itself.** A `.ydr` is an RSC7 container -- 16 byte
  header, then raw deflate -- so the bone names can be read straight out of the finished
  artefact. Every other check in this pipeline asserts what the script believes it did; this one
  asserts what was written. The bug it guards against was silent for the model's entire life:
  clean export, success reported, nothing in any log.

- **Read-only properties no longer abort the property copy.** `shader_order` is derived, and one
  failure was losing the other five silently.

**Verified:**

- The bones are **in the file**: decompressed the 364,263 byte `.ydr` to 1,376,256 bytes and
  found `gun_root`, `gun_muzzle` and the texture name. First change in this sequence confirmed
  rather than assumed.
- `lua tools/run_tests.lua` — **1103 passed, 0 failed**.
- **Not** tested in game.

**Open:**

- Whether a skeleton is what the crash wanted. The evidence is strong and it is still a
  hypothesis until someone pulls a trigger.
- If it still crashes, the model is still the only thing left differing from a working weapon,
  and the next question is whether the mesh needs to be skinned to those bones rather than merely
  parented.

---

## 2026-09-01 (third) — it fires

**The skeleton was the cause.** Six attempts, five of them fixes reasoned out and shipped without
a measurement, and the answer was in Sollumz's own source the whole time: a Drawable rooted on an
Empty exports `skeleton = None`, and a weapon with no muzzle bone takes the game down when fired.

**What is left is cosmetic.** The spray that appears is the weapon's own, not mi_fire's, and two
things follow from that which were not obvious:

- With `FireType VOLUMETRIC_PARTICLE` the `FlashFx` **is** the spray rather than a muzzle flash.
  That is why it fires on an uncoupled, uncharged line, and why it looks like extinguisher powder.
- `FlashFxChanceSP` and `FlashFxChanceMP` are both zero and it emits anyway, so those do not gate
  it.

**Changed:** `FlashFxScale` from 1.0 to 0.01.

**Decisions:**

- **Shrunk rather than renamed.** Swapping `weap_extinguisher` for a water effect is the obvious
  move and is exactly the shape of the bug that crashed the game six times: an unresolvable
  `FlashFx` is unresolvable, and there is no way to check a ptfx name from outside the game. A
  scale is a float. Renaming is a guess; shrinking cannot fail the same way.

- **The behaviour that falls out is the right one.** What the player sees becomes
  `MIFireHose.visuals.stream`, which mi_fire draws and gates on the line being charged and the
  bale open. An uncoupled nozzle producing a jet of anything was wrong regardless of what the
  jet looked like.

**On the six attempts:** the pattern is worth naming, because it repeated. Each fix was reasoned
from the code, was plausible, was shipped, and was wrong. The two things that actually moved it
forward were both observations rather than deductions -- "it crashes even uncharged", which
eliminated every hypothesis at once, and reading the exporter's own branch rather than reasoning
about what it probably did. The dumps were read correctly each time and pointed nowhere, because
every candidate was native.

**Verified:**

- `lua tools/run_tests.lua` — **1103 passed, 0 failed**.
- In game: the weapon equips, holds, and **fires without crashing**.

**Open:**

- The water stream offsets are still zero, so it will emit from the hand until nudged.
- Whether hiding the weapon's own spray leaves anything visible on an uncharged line. It should
  not.

**Next:** aim the water, then put it on a fire.

---

## 2026-09-01 (fourth) — the stream follows the agent

**Scope:** water and foam have to look different, and the client could not tell them apart.

**A correction worth recording:** the note in the last entry said swapping `weap_extinguisher`
for a water effect would be the obvious move. It would not have broken fire extinguishers --
`FlashFx` lives inside a single `CWeaponInfo`, so changing ours affects `WEAPON_MINOZZLE` and
nothing else, and `WEAPON_FIREEXTINGUISHER` keeps its own. The reason not to rename it is the
crash risk alone: a ptfx name cannot be checked from outside the game, and an unresolvable one is
exactly what took the client down six times.

That distinction matters going forward. A foam nozzle, a deck gun and an extinguisher can each
name their own effect without touching each other, so per-weapon effects are a real option later
-- just not one to reach for on a guess.

**Changed:**

- `server/modules/hose/init.lua` — `publicOf` sends `agent`.
- `config/hose.lua` — `streamByAgent`, layered over `stream`.
- `client/modules/hose/init.lua` — the stream picks per agent and restarts when it changes.

**Decisions:**

- **The server always knew and never said.** `applyAgent` has been given `line.agent` since the
  water path was written, but it was not in `publicOf`, so the client drew a water jet whatever
  the rig was proportioning. Foam and water do not look alike, and showing the wrong one teaches
  the wrong thing about which to reach for -- which is the whole point of the agent matrix.

- **Overrides layer, they do not replace.** Only the differences go in `streamByAgent`, so a
  placement found by nudging stays correct for every agent instead of having to be found again
  per agent.

- **`pick()` rather than `or` chains.** A zero offset is a real value and `byAgent.x or base.x`
  steps straight over it. Every field is checked for nil explicitly.

- **Foam has no effect name of its own, deliberately.** It reuses the water jet at a fatter
  scale. Inventing a plausible ptfx name is precisely the mistake that produced six crashes, and
  a placeholder that admits to being one is better than a name nobody has verified. The real
  effect gets taken from something already running, the same way `water_cannon_jet` was.

- **The particle restarts when the agent changes**, not only when the bale does. A looped
  particle keeps whatever it was started with, so switching to foam mid-flow would have gone on
  looking like water until the trigger was released.

**Verified:**

- `lua tools/run_tests.lua` — **1103 passed, 0 failed**.
- **Not** tested in game. Nothing sets `line.agent` to foam yet, so the path is unexercised: this
  is the plumbing being in place before Phase 8 needs it, not a feature that can be used today.

**Open:**

- Nothing proportions foam yet. The rig has a foam cell in config and no way to open it.
- A real foam effect.

