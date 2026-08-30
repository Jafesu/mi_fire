# 0001 — Nothing grants immunity to fire

**Status:** accepted, partially superseded by [0004](0004-protection-follows-the-clothing.md)
**Date:** 2026-08-30

> **Superseded in one respect.** This ADR originally said protection is read from server
> state and never from clothing. That was wrong and 0004 reverses it — protection now
> follows what is actually being worn, however it was put on.
>
> **Everything about immunity still holds.** Nothing grants immunity to fire, no tier may
> reach `fireResist` 1.0, gear degrades while it protects, and a firefighter who stays in
> long enough catches light. Only the *source of the tier* changed.

## Context

Most firefighting scripts treat protective equipment as a boolean: wearing turnout gear
means fire cannot hurt you. It is simple to implement and simple to understand.

It is also the reason firefighting in those servers is not interesting. If gear makes you
invulnerable, there is no decision to make on the fireground — you walk into the fire,
stand in it, and wait. Nothing about position, time, air, or crew size matters.

## Decision

No piece of equipment removes fire damage. `fireResist` is a multiplier and is clamped
below 1.0. Gear buys **time**, and time runs out:

- Sustained flame contact degrades gear integrity.
- Degraded gear protects less.
- Below a per-tier ignition threshold, the wearer can catch fire regardless of what they
  are wearing.

Smoke is the single exception in the other direction: a sealed SCBA with air remaining is
genuine immunity to smoke, and it ends the moment the bottle does. No gear tier reduces
smoke at all — `config/gear.lua` has no smoke field, so the rule holds by construction
rather than by convention.

## Enforcement

Three places, deliberately redundant, because a rule with one enforcement point is a rule
that gets edited out:

1. `server/main.lua` validates every tier at boot and **refuses to start** the resource if
   one has `fireResist >= 1.0`.
2. `tools/tests/hydraulics_spec.lua` asserts the bound across every configured tier.
3. `config/gear.lua` states the rule at the top of the file.

## Consequences

- A server owner who wants a more forgiving fireground raises `integrity`, which gives
  crews longer inside without ever making them invulnerable. That is the intended knob.
- Turnout gear has a running cost: integrity persists per character and tier, and needs
  repair. Changing clothes does not repair it.
- Hazmat suits have *worse* fire resistance than turnout, which surprises people. It is
  correct — a Level A vapour-tight suit is plastic.

## Reversing this

Do not reverse this without also reworking the exposure model, SCBA, PASS, RIT, and crew
size, all of which only mean something because the fireground can kill you. Removing this
invariant removes the reason those systems exist.
