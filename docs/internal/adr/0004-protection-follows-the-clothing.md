# 0004 — Protection follows the clothing

**Status:** accepted
**Date:** 2026-08-30
**Supersedes:** part of [0001](0001-nothing-grants-fire-immunity.md)

## Context

ADR 0001 stated that protection is read from server state and never from what a player is
wearing, so that donning at an apparatus was the only way to become protected. The stated
reason was that otherwise anyone with a clothing menu could grant themselves fire
resistance.

**That was solving the wrong problem, and the cost was severe.**

Firefighters on a real server get dressed in all sorts of ways: a station locker, an
outfit saved in `illenium-appearance`, a job clock-in outfit, an EUP menu. Under 0001 every
one of those produced a firefighter in full turnout gear taking full fire damage — which
does not read as a design decision. It reads as the resource being broken.

The exploit being prevented was also much smaller than the cost. A civilian who somehow
puts on turnout gear and survives a little longer in a fire is not an economy exploit, not
griefing, and not worth breaking the normal path for. Obtaining the clothing is already
gated by whatever restricts the EUP.

## Decision

**Protection follows the clothing.** The gear is recognised from what is actually on the
ped, and it works however it was put on. Donning at an apparatus is a convenience — it
applies the appearance and loads the character's markings — not the source of truth.

**It is not job-gated either.** A coat is a coat. If a civilian gets hold of a set, it
protects them exactly as much as it protects anyone else, and a bottle of air works for
whoever is breathing it. `Config.gearRequiresJob` restores the restriction for servers that
disagree.

The line is drawn somewhere more defensible instead: **taking equipment off an apparatus or
a station rack is department business** and stays job-gated. Getting hold of the gear is
the gate; using it is not.

## How recognition works

Two rules, both load-bearing.

**Match on drawable, never texture.** Texture carries the name tape and rank, which are
per-character (see `mi_fire_gear_appearance`). Matching on texture would mean a firefighter
with their own markings is not recognised as wearing gear at all — the officers would be the
ones losing protection.

**A signature slot must match.** The coat is what says turnout gear. Some pieces are weak
evidence: `pants = 11` means "no separate trousers" and half the outfits on a server use it,
so matching on that alone would identify most of the population as firefighters.

Beyond the signature, coverage scales protection. Wearing the coat without the helmet gives
less than the full set, down to a configurable floor — so a missing hood is a real decision
rather than a cosmetic one.

## What 0001 still holds

Everything about immunity. **Nothing grants immunity to fire**, no `fireResist` may reach
1.0, gear degrades while it protects, and a firefighter who stays in long enough burns
through it and catches light. That invariant is untouched and still enforced in three
places.

What changed is only *where the tier comes from*, not what the tier does.

## Consequences

- The client reports what it is wearing, because `GetPedDrawableVariation` is client-only.
  That is a small trust surface: the worst a forged report achieves is a player who is
  harder to set on fire.
- **Integrity is keyed to the character and tier, not to the session.** Changing clothes
  does not repair a burned coat, and putting the same gear back on resumes where it left
  off. The gear is worn out, not the visit.
- A server that wants gear to be a job perk sets one flag.

## What would make this wrong

If the trust surface turned out to matter — if players started forging gear reports to
grief fire calls, or if fire protection became something worth cheating for because of
some later feature. Neither seems likely for a coat that only makes fire slower.
