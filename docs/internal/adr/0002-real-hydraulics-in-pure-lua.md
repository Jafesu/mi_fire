# 0002 — Real hydraulics, in pure Lua

**Status:** accepted
**Date:** 2026-08-30

## Context

A pump panel needs numbers. There are two ways to get them:

1. A tuning curve — pressure is a 0-100 value with multipliers for hose diameter and
   length. Easy to balance, reads fine on a gauge.
2. Real fireground hydraulics — published friction-loss coefficients, real nozzle
   pressures, the actual pump curve.

Option 1 is less work and the numbers mean nothing. A pump operator who knows the job
looks at the panel and sees noise.

## Decision

Real hydraulics, in `shared/hydraulics.lua`:

- Friction loss `FL = C · Q² · L` with the standard coefficient table.
- Smooth bore flow `Q = 29.7 · d² · √NP`.
- Elevation at 0.434 psi per foot, or the 5-psi-per-floor fireground shortcut.
- Appliance loss thresholds at 350 gpm, flat 25 psi for master streams and standpipes.
- `PDP = NP + FL + EL + AL`.
- Pump capacity to NFPA 1901: 100% at 150 psi, 70% at 200, 50% at 250.
- Hydrant capacity from the percent-drop rule.

The module is **pure**: no game natives, no side effects, no FiveM dependencies. It runs
under a plain Lua interpreter.

## Why purity matters here

Because it makes the numbers testable. `tools/run_tests.lua` asserts against hand-worked
fireground problems with known answers — 200 ft of 1.75″ flowing 150 gpm on a 100 psi fog
nozzle needs 169.75 psi at the pump, and 500 ft of 5″ at 1000 gpm loses 40 psi. Those are
checkable facts, not snapshots of what the code happens to do.

Every other part of this resource trusts these numbers. Being able to verify them without
launching a server is worth the constraint.

## Consequences

- `shared/` must parse under Lua 5.1, since the test interpreter may not be 5.4. No `//`,
  no bitwise operators, no `goto` in shared code.
- The constants in `hydraulics.lua` are **not tuning values**. Changing a coefficient makes
  the resource lie to someone who knows the real figure. Tuning belongs in `config/`.
- Players who know the job get a system that rewards knowing it. Players who do not get
  an assist mode later, and a guide that teaches the concept before showing the control.

## Reversing this

Replacing the model with a curve would silently invalidate every test and every number on
the pump panel. If it ever needs to happen, delete the tests in the same commit rather
than leaving them asserting against a model that no longer exists.
