# Changelog

Notable changes to `mi_fire`. Format follows [Keep a Changelog](https://keepachangelog.com).
Versions follow [Semantic Versioning](https://semver.org).

## [Unreleased]

### Fixed

- SCBA worn through a clothing menu is recognised, the same way turnout gear already was.
  A visible harness previously counted for nothing.
- Fire kills at the rate the gear model says it does. Every fire node was spawning a real
  engine fire underneath it, which ignited and killed players on the engine's own schedule
  — full structural turnout gave about seven seconds instead of a minute. Fires still light
  the scene; the light is drawn directly now.
- Stop, drop and roll is a real action: you drop, you roll on the ground, and you get up.
  Rolling also cuts what the fire is doing to you, so taking the correct action pays rather
  than merely delaying the same outcome.
- Standing in a fire no longer charges you twice for the same heat. Radiant heat is what
  reaches you near a fire; the flame already accounts for standing in one. In full turnout
  that was the difference between dying at forty seconds having never caught fire, and the
  minute the gear is rated for.
- Catching fire is survivable if you act at once. The engine's own ped fire was applying
  damage on top of the resource's, killing a firefighter in about two seconds against a
  four second roll — so stop, drop and roll could not be performed by anyone.
- A PASS device keeps alarming when the bottle runs out. It previously switched itself off
  at the moment its wearer most needed it, which also stopped it alarming during last stand.
- Turnout gear can now actually be repaired or replaced. Wear was tracked server-side but
  never sent to the player, so both options stayed hidden however burned the set was.
- Flammable-liquid fires produce black, heavy smoke from the first second. Smoke colour was
  driven only by how developed the fire was, with no input from what was burning.

### Changed

- A full air bottle is ten minutes rather than thirty.
- Heat and smoke no longer distort the screen, and there is no coughing. That information
  moved to a HUD showing air, gear condition and heat as three separate readable numbers.
  The screen effects remain available in config, switched off.

### Added

- A fireground HUD: air remaining, gear condition, and heat load. Each row appears only
  when it has something to say.
- `/fire gear` — explains why a truck is showing no turnout or SCBA options. An
  ox_target option that does not appear produces no error and no log line, so it reports
  the whole chain instead: ox_target's state, the job gate, whether the vehicle counts as
  apparatus, and each option evaluated against the truck you are stood at. Reachable by
  anyone, since the person who cannot see the option is the one who needs the reason.
- **Gear condition, repair, and replacement.** Damaged turnout can be serviced or swapped
  for a fresh set, and how damage behaves is a server's choice between three models:
  gear that recovers on its own once you are clear of the fire, gear that stays damaged
  until someone deals with it, or gear that resets at the start of each shift. Repair
  takes longer the worse the set is, restores a little less each time, and is refused
  outright on a set that is condemned — past a point real turnout gets replaced rather
  than patched.
- **The fire engine.** Nodes ignite, grow, consume fuel, spread, and go out. Knocking a
  fire down is not extinguishing it: a node driven to zero keeps its fuel and may reflash
  unless a crew keeps working it, which is overhaul.
- Suppression through the agent matrix, with one entry point so no water source can
  bypass it. The wrong agent adds intensity and fires its hazard rather than being
  clamped to zero.
- Propagation with per-class spread rates, caps, and a drifting global wind that wildland
  fires run with.
- Client fire rendering, scaled by intensity so a crew can see the water working.
- `/fire` command family: start, here, at, stop, stopall, list, info, agent, wind, classes.
- Export surface, both name-compatible with the resource mi_fire replaces and a richer
  native API.
- Pump panel architecture designed and documented: one renderer driving per-model layout
  files, with an auto-generated fallback so an unconfigured apparatus still works.

- Repository scaffold: manifest, module layout, and load order.
- `shared/hydraulics.lua` — fireground hydraulics with real friction-loss coefficients,
  smooth bore and fog nozzle flow, elevation and appliance loss, pump discharge pressure,
  the NFPA 1901 pump curve, hydrant percent-drop capacity, and cavitation detection.
  Pure Lua, runnable outside FiveM.
- Test harness with 94 assertions against hand-worked fireground problems.
- Fire classes A, B, C, D, K, gas, wildland, and vehicle, each with its own growth,
  spread, reflash, and hazard behaviour.
- Agent effectiveness matrix across six extinguishing agents, including negative
  effectiveness where the wrong agent makes a fire worse.
- Protective equipment tiers with fire and heat resistance, integrity degradation, and an
  ignition threshold. No tier grants immunity, and the resource refuses to boot if one is
  configured to.
- Districts with fuel character, area-of-play configuration, and run cards.
- Framework bridge with Qbox, ESX, and standalone adapters.
- Dispatch bridge with lb-tablet, custom, and none providers.
- Target, inventory, and appearance bridges.
- Server state, permissions, and boot-time configuration validation.
- MySQL-backed station configuration with a numbered migration runner. Stations, their
  placed points (lights, speakers, panels, bay doors, apparatus bays), and their coverage
  polygons are runtime data built in game rather than hand-edited coordinates.
- Sprinkler systems the fire department installs in buildings. Heads fuse individually
  over the fire using real temperature ratings and the orifice formula Q = K*sqrt(P),
  flow until the tank runs dry, and then need a five-step reset with replacement heads.
  Systems discharge through the agent matrix, so installing a water system over a
  commercial kitchen makes a Class K fire worse. A fire department connection lets a crew
  supply a drained system from an engine. Waterflow raises its own dispatch.
