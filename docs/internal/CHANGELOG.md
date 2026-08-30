# Changelog

Notable changes to `mi_fire`. Format follows [Keep a Changelog](https://keepachangelog.com).
Versions follow [Semantic Versioning](https://semver.org).

## [Unreleased]

### Added

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
