# 0003 — Pump panels are data, not code

**Status:** accepted
**Date:** 2026-08-30

## Context

Each apparatus should have a pump panel that matches the real thing. A Pierce engine panel and
a tower ladder panel are genuinely different instruments, and a single generic panel reskinned
per truck would throw away most of what makes pump operations interesting.

The obvious implementation is one React UI per truck. With the current fleet that is seven
frontends. They drift apart, a fix to one is a fix to none of the others, and every apparatus
added later is a new frontend project rather than a config change.

## Decision

**One renderer, many layout files.** A panel is a data file describing a grid of widgets with
positions and data bindings. The renderer maps a widget `type` to a component and binds it to a
path in live pump state. Adding a gauge style is a component; adding a truck is a config block.

Panels vary along four axes, which is far less than it appears — a Pierce side-mount and an
E-ONE side-mount are about ninety percent the same panel:

| Axis | Changes | Examples |
|---|---|---|
| Family | The layout | `engine`, `puc`, `ladder`, `tower`, `tanker`, `rescue`, `brush` |
| Theme | Purely visual | stainless / black, gauge face, needle and bezel style |
| Modules | Which controls exist | governor, foam system, tank gauge style |
| Overrides | Per-model specifics | discharge names, count, sizes |

## Supporting evidence

This is not a guess about how apparatus differ. The 2026 pack at
`[assets]/[vehicles]/2026firetrucks` **ships four modelled pump panels** —
`Pump_Panelengine`, `Pump_Panelladdder`, `Pump_Paneltower`, `Pump_PanelPUC`. The family split
is therefore a fact about the trucks rather than a decision we invented, and NUI layouts should
match the physical panel on the rig the player is standing at.

PUC earns its own family rather than being a theme: Pierce Ultimate Configuration is a real
single-pump architecture with no separate pump house, operated differently from a conventional
midship pumper.

## Consequences

- **Panel discharges bind to real ports.** `portId` is the same key `/fireoffset` authors into
  `config/apparatus.lua`. A layout naming a port the apparatus does not have is rejected by boot
  validation, so a panel promising a discharge that does not exist fails at startup rather than
  mid-incident.
- **An unconfigured truck still works.** With no layout, a panel is generated from the
  apparatus's discharge ports. Every rig is usable from day one and authored layouts become
  progressive enhancement — which also means the feature ships before a single layout exists.
  This fallback path is built *first*, deliberately.
- Shipped layouts use generic family and theme names, not manufacturer wordmarks or logos.
  Layout archetypes are not anyone's property; a server owner can relabel locally.
- An in-NUI layout editor becomes possible later, because layouts are already data. It should be
  designed once several exist and the real friction is known.

## What would make this wrong

If panels turned out to share almost nothing — if every truck needed bespoke widget types rather
than bespoke arrangement — the layout schema would be carrying no weight and per-truck components
would be honest. Evidence so far points the other way: four modelled panels across six apparatus,
and the differences are arrangement and module choice rather than kind.
