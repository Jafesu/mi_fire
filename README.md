# mi_fire

Fire generation, suppression, and fireground operations for FiveM.

One system covering fires, hoses, pump operations, water supply, ground ladders, SCBA,
hazmat, and water rescue — built so those parts know about each other, because the
interesting behaviour lives in the seams between them.

## What makes it different

**Fire classes matter.** A flammable liquid fire is not a red-tinted structure fire. Hit
it with a straight stream and you push it around the room; hit it with foam and it goes
out. Water on burning metal explodes. Water into hot cooking oil throws a fireball. The
agent-versus-class matrix is real, and getting it wrong has consequences.

**The hydraulics are real.** Friction loss uses actual published coefficients. Smooth bore
flow is `29.7 · d² · √NP`. The pump curve is NFPA 1901. A pump operator who knows the job
will find the numbers on the panel mean what they mean.

**Gear buys time, not immunity.** SCBA stops smoke and only smoke. Turnout reduces flame
damage and degrades while it does. Stand in fire long enough and you burn through the gear
and catch fire, whatever you are wearing. No configuration can turn that off.

**Big lines need crews.** One firefighter takes the nozzle; others take backup positions.
Under-crewed, the line whips, the stream wanders, and the nozzle operator goes down.

## Requirements

- `ox_lib` and `ox_target` — required
- Qbox, ESX, or standalone — auto-detected
- `lb-tablet` — optional, for dispatch
- `ox_inventory` — optional, for gear and air persistence
- `illenium-appearance` — optional, for turnout gear appearance

## Installation

See [docs/getting-started/installation.md](docs/getting-started/installation.md).

## Documentation

[docs/](docs/) — guides for firefighters, configuration reference for server owners, and
an export reference for developers.

## Status

In development. See [docs/internal/BUILD.md](docs/internal/BUILD.md) for phase status.
